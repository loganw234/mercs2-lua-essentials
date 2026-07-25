-- Ess/67_squad_queue.lua -- Ess.Squad.queue: an asynchronous multi-step sequence, e.g.
-- [enter vehicle] -> (wait until seated) -> [move to LZ] -> (wait for arrival) -> [deploy]. Built entirely
-- on Ess.Followers._issue (see 66_followers.lua's header) plus the SAME completion signals
-- Ess.Followers._orderScoped itself uses (onComplete for move/non-looping patrol, Ess.On.death for attack) --
-- no new native calls.
--
-- API:
--   Ess.Squad.queue(targetGroup, steps, queueOpts) -> ok
--     targetGroup: a team name (string, resolved via Ess.Squad.team) OR a raw guid list
--     steps: { {behavior=..., opts={...}, timeout=seconds}, ... } -- opts is the same shape
--            Ess.AIOrders.command/Ess.Followers.order already take; timeout defaults to 30s
--     queueOpts: { onComplete = fn(), onCancel = fn() }
--   Ess.Squad.cancelQueue(targetGroup) -> ok    aborts, reverts the group to Follow (a safe fallback)
--
-- WHY THIS DOESN'T GO THROUGH Ess.Followers._orderScoped (Ess.Followers.order()'s own core): _orderScoped
-- auto-resumes Follow the moment ANY step naturally completes -- exactly wrong mid-sequence (a follower
-- would peel off and start following the player again between step 1 and step 2). Queue uses _issue
-- directly instead, wiring its OWN step-advancement in place of _orderScoped's auto-resume-follow, and only
-- returns a group to Follow at the very end if the caller's own onComplete asks for it (or on cancelQueue,
-- which explicitly reverts to Follow as its own documented fallback).
--
-- STEP COMPLETION SIGNALS (matches whatever Ess.AIOrders/Ess.Followers already provide -- see
-- 60_aiorders.lua's own opts fields):
--   move / non-looping patrol -> opts.onComplete, the native per-unit Callback fan-in (CONFIRMED LIVE
--            2026-07-25 hang-proof now -- see 60_aiorders.lua's own fix note -- a single unit's silently
--            failed Ai.Goal used to hang this forever for the WHOLE group)
--   attack  -> Ess.On.death(opts.target, ...) -- waits for the target, not the followers, to die
--   enter   -> polls Ess.Object.vehicleOf(guid) every 0.5s until EVERY guid in the group is seated in SOME
--              vehicle (a squad might board different seats/vehicles -- "seated at all" is the signal)
--   anything else (hold/defend/guard/looping patrol/face/animate/flee/deploy) -> no natural completion
--              signal exists for these (same honest limit Ess.Followers.order()'s own header notes) -- a
--              step like this just runs out its own timeout before the queue advances past it.
-- EVERY step also gets a timeout watchdog regardless of the above -- one stuck unit/blocked path/a native
-- Callback that never arrives can't freeze the whole sequence forever; whichever fires first (the natural
-- signal or the timeout) advances the queue, the other is a no-op (guarded by `advanced`).

local Ess = _G.Ess
Ess.Squad = Ess.Squad or {}

local DEFAULT_STEP_TIMEOUT = 30
local activeQueues = {}   -- queueKey -> { guids=, steps=, idx=, onComplete=, onCancel=, cancelled= }

-- queueKey(targetGroup) -- a team name is used directly (string equality already works); a raw guid list is
-- keyed by its SORTED content, not table identity, so Ess.Squad.cancelQueue(sameGuids) works even if the
-- caller builds a brand new table containing the same guids rather than keeping the original reference.
local function queueKey(targetGroup)
    if type(targetGroup) == "string" then return "team:" .. targetGroup end
    local parts = {}
    for _, g in ipairs(targetGroup or {}) do parts[#parts + 1] = tostring(g) end
    table.sort(parts)
    return "guids:" .. table.concat(parts, ",")
end

local function runQueueStep(qk, qs)
    if qs.cancelled then return end
    local step = qs.steps[qs.idx]
    if not step then
        activeQueues[qk] = nil
        if qs.onComplete then pcall(qs.onComplete) end
        Ess.Followers._emit("onQueueComplete", qs.guids)
        return
    end

    local opts = step.opts or {}
    local behavior = step.behavior
    local advanced = false
    local loopId = "Ess.Squad.queue:" .. tostring(qk) .. ":" .. tostring(qs.idx)

    local function advance()
        if advanced or qs.cancelled then return end
        advanced = true
        Ess.Loop.stop(loopId)
        Ess.Followers._emit("onStepComplete", qs.guids, qs.idx, behavior)
        qs.idx = qs.idx + 1
        runQueueStep(qk, qs)
    end

    if behavior == "attack" and opts.target then
        Ess.On.death(opts.target, advance)
    elseif behavior == "move" or (behavior == "patrol" and opts.loop == false) then
        opts.onComplete = advance
    end

    Ess.Followers._issue(qs.guids, behavior, opts)

    -- ONE combined poll+timeout tick per step: for "enter", the natural completion IS the poll (every guid
    -- seated in some vehicle); every step -- including one with its own native Callback/death signal wired
    -- above -- ALSO gets a hard ceiling here, so a stuck unit/blocked path/a signal that never arrives can't
    -- freeze the whole queue forever.
    local budget = step.timeout or DEFAULT_STEP_TIMEOUT
    local elapsed = 0
    Ess.Loop.start(loopId, 0.5, function()
        if advanced or qs.cancelled then return false end
        if behavior == "enter" then
            local allSeated = true
            for _, g in ipairs(qs.guids) do
                if not Ess.Object.vehicleOf(g) then allSeated = false; break end
            end
            if allSeated then advance(); return false end
        end
        elapsed = elapsed + 0.5
        if elapsed >= budget then advance(); return false end
        return true
    end)
end

-- Ess.Squad.queue(targetGroup, steps, queueOpts) -> ok -- replaces any EXISTING queue already running for
-- this same targetGroup (same key derivation as cancelQueue) rather than running two in parallel over the
-- same guids.
function Ess.Squad.queue(targetGroup, steps, queueOpts)
    if not steps or #steps == 0 then return false end
    local guids = Ess.Squad._resolveGuids(targetGroup)
    if not guids or #guids == 0 then return false end
    Ess.Squad.cancelQueue(targetGroup)
    queueOpts = queueOpts or {}
    local qk = queueKey(targetGroup)
    local qs = {
        guids = guids, steps = steps, idx = 1,
        onComplete = queueOpts.onComplete, onCancel = queueOpts.onCancel,
        cancelled = false,
    }
    activeQueues[qk] = qs
    runQueueStep(qk, qs)
    return true
end

-- Ess.Squad.cancelQueue(targetGroup) -> ok -- aborts the currently-running step (whichever it is) and
-- reverts the group to Follow, the safe fallback state. A no-op (returns false) if nothing's running for
-- this targetGroup.
function Ess.Squad.cancelQueue(targetGroup)
    local qk = queueKey(targetGroup)
    local qs = activeQueues[qk]
    if not qs then return false end
    qs.cancelled = true
    activeQueues[qk] = nil
    Ess.Loop.stop("Ess.Squad.queue:" .. tostring(qk) .. ":" .. tostring(qs.idx))
    if qs.onCancel then pcall(qs.onCancel) end
    Ess.Followers._issue(qs.guids, "follow", {})
    return true
end
