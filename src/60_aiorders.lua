-- Ess/60_aiorders.lua -- Ess.AIOrders: command a spawned unit GROUP, extracted from ContractFramework.lua's
-- AI_BEHAVIORS table so it's usable outside a running contract -- the direct unblock for the stalled
-- Active-World director project.
--
-- API:
--   Ess.AIOrders.setGroup(name, guids) / .group(name) -> guids     a standalone group registry
--   Ess.AIOrders.command(guids, behavior, opts, tracker) -> ok
--
-- behaviors (each built ONLY on confirmed Ai.Goal/Ai.Anchor/Ai.Deploy primitives, exactly as
-- ContractFramework.lua already uses them):
--   move    -> MoveTo(anchor at at)               go to a spot and stop
--   face    -> Face(at)                          turn to face a point (staging / cutscene feel)
--   hold    -> Idle + Anchor(0)                   stand ground where spawned, don't give chase
--   defend  -> MoveTo(anchor) + Anchor(radius)    hold an area, fight anything inside it
--   attack  -> Attack(target group / nearest hero)  hunt a target
--   patrol  -> MoveTo chain through anchored points  walk a route (loops unless loop=false)
--   follow  -> Ai.Role("Follow") -- the game's real "recruit" mechanic, auto-holds distance and rides
--              along in vehicles on its own (see BEHAVIORS.follow below for the confirmed setup sequence)
--   flee    -> MoveTo(anchor) directly away from the nearest hero
--   enter   -> board a vehicle (opts.target = its group name) as driver/gunner/passenger
--   deploy  -> a transport (guids = vehicles) disgorges its passengers
--   animate -> play a canned action ("Cower", "Stand", ...)
--
-- opts fields used across behaviors: at={x,y,z}, points={ {x,y,z}, ... }, loop, speed, priority,
-- target=<group name or raw uGuid>, radius, role, action, interval, distance, onComplete (move, and patrol
-- when loop=false only -- fires once every guid has finished; a looping patrol never calls it).
--
-- CONFIRMED LIVE 2026-07-24: every "go to this raw {x,y,z}" behavior here used to hand Ai.Goal a
-- "MoveToPos"/Location={x,y,z} table. That's WRONG for an on-foot human -- confirmed by direct live testing
-- (Ai.Goal returns nil, no error since it's pcall-wrapped, for ANY MoveToPos on a human regardless of
-- distance, while the identical unit accepts "Idle" fine) and by the full decompiled game script corpus,
-- where "MoveToPos" appears in exactly one file and only ever targets a VEHICLE DRIVER, never a walking
-- human. The confirmed-working substitute is "MoveTo" targeting a real OBJECT guid -- see anchorAt() below,
-- which spawns a TinyGeometry at the destination (the same disposable-anchor trick `defend` already used
-- for its own Ai.Anchor radius) and targets THAT instead of a raw coordinate.

local Ess = _G.Ess
Ess.AIOrders = Ess.AIOrders or {}
Ess.AIOrders._groups = Ess.AIOrders._groups or {}

-- Ess.AIOrders.setGroup(name, guids) / .group(name) -> guids
-- A standalone stand-in for ContractFramework's `inst.groups` -- lets `attack`/`follow`/`enter` target
-- ANOTHER named group without needing a contract instance to hold the registry. Empty table (never nil)
-- for an unknown name, matching groupGuids' own confirmed-safe fallback.
function Ess.AIOrders.setGroup(name, guids)
    Ess.AIOrders._groups[tostring(name)] = guids
end
function Ess.AIOrders.group(name)
    return Ess.AIOrders._groups[tostring(name or "")] or {}
end

local function xyz(t)
    if not t then return nil end
    return t.x or t[1], t.y or t[2], t.z or t[3]
end
local function nearestHero()
    local ok, u = pcall(Player.GetLocalCharacter)
    if ok then return u end
end
local actor, pri, aiGoal, haste =
    Ess.Raw.AIOrders.actor, Ess.Raw.AIOrders.pri, Ess.Raw.AIOrders.goal, Ess.Raw.AIOrders.haste

-- anchorAt(x, y, z, tracker) -> uGuid|nil -- spawns a disposable TinyGeometry at a raw coordinate so a
-- "MoveTo" goal (the confirmed-working primitive for an on-foot human, see file header) has a real object
-- to target. Tracked via `tracker` if one was given, same as every other spawned-prop cleanup in this repo;
-- omit it and the anchor just isn't cleaned up for you (an existing, accepted caveat, not new here).
local function anchorAt(x, y, z, tracker)
    local ok, anchor = pcall(Pg.Spawn, "TinyGeometry", x, y, z)
    if not (ok and anchor) then return nil end
    if tracker then tracker:guid(anchor) end
    return anchor
end

local BEHAVIORS = {}

BEHAVIORS.move = function(tracker, o, guids)
    local x, y, z = xyz(o.at); if not x then return end
    local p = pri(o.priority)
    local anchor = anchorAt(x, y, z, tracker)
    if not anchor then return end
    -- o.onComplete (optional) fires once every guid's own MoveTo goal has reported back, regardless of
    -- each individual outcome -- good enough for "the group is done moving," not a per-unit success guarantee.
    local pending = #guids
    local function onUnitDone()
        pending = pending - 1
        if pending <= 0 then pcall(o.onComplete) end
    end
    for _, g in ipairs(guids) do
        local a = actor(g)
        -- CONFIRMED LIVE 2026-07-25: Ai.Goal can silently refuse to register at all (aiGoal returns a
        -- falsy handle, no error -- the same class of silent no-op this file's header already documents
        -- for other cases) -- when that happens for even ONE guid in the group, no native Callback EVER
        -- arrives for it, so `pending` never reaches 0 and o.onComplete never fires for the WHOLE group,
        -- even guids who completed fine. Confirmed via Ess.Followers.order("move", ...) issued to a
        -- 2-unit team: neither unit's auto-resume-follow ever ran, while the identical order to a lone
        -- unit worked every time. Counting an immediate registration failure as "done" right away (instead
        -- of waiting on a Callback that's never coming) closes that hang.
        local h = aiGoal({ AIGuid = a, Goal = "MoveTo", Target = anchor, Priority = p, Force = true,
                 Callback = o.onComplete and onUnitDone or nil })
        if o.onComplete and not h then onUnitDone() end
        haste(a, o.speed)
    end
end

BEHAVIORS.face = function(tracker, o, guids)
    -- CONFIRMED LIVE 2026-07-24: without Force=true, this silently no-ops on a unit already holding an
    -- Ai.Anchor(AnchorRadius=0) lock (see `hold` below) -- the goal is accepted (no error) but never visibly
    -- turns the unit. Force=true, matching every other movement-ish behavior in this file, overrides it with
    -- no separate "release the anchor" step needed.
    local x, y, z = xyz(o.at); if not x then return end
    for _, g in ipairs(guids) do
        aiGoal({ AIGuid = actor(g), Goal = "Face", Target = { x, y, z }, Position = true, Priority = "HiPri", Force = true })
    end
end

BEHAVIORS.hold = function(tracker, o, guids)
    -- Force=true added proactively, same reasoning as the confirmed face/attack fixes above -- a unit
    -- switching to hold FROM another active order (patrol, attack, ...) needs to preempt whatever goal
    -- that left behind, not just queue behind it.
    for _, g in ipairs(guids) do
        local a = actor(g)
        pcall(Ai.Anchor, { AIGuid = a, AnchorRadius = 0 })
        aiGoal({ AIGuid = a, Goal = "Idle", Priority = "HiPri", Force = true })
    end
end

BEHAVIORS.defend = function(tracker, o, guids)
    local x, y, z = xyz(o.at); if not x then return end
    local r, p = o.radius or 12, pri(o.priority)
    local anchor = anchorAt(x, y, z, tracker)
    if not anchor then return end
    for _, g in ipairs(guids) do
        local a = actor(g)
        aiGoal({ AIGuid = a, Goal = "MoveTo", Target = anchor, Priority = p, Force = true })
        haste(a, o.speed)
        pcall(Ai.Anchor, { AIGuid = a, AnchorGuid = anchor, AnchorRadius = r })
    end
end

BEHAVIORS.attack = function(tracker, o, guids)
    -- o.target accepts EITHER a name registered via Ess.AIOrders.setGroup OR a raw uGuid directly -- it
    -- used to ONLY check the group registry, so passing a raw guid (e.g. a reticle target) silently missed
    -- (group() returns {} for an unknown name, per its own "never nil" contract) and fell all the way
    -- through to nearestHero(), making the squad attack the PLAYER. Group lookup still comes first so an
    -- existing registered-name caller is unaffected; o.target itself is now the fallback instead of
    -- skipping straight to nearestHero().
    local tgt
    if o.target then tgt = Ess.AIOrders.group(o.target)[1] or o.target end
    if not tgt then tgt = nearestHero() end
    local p = pri(o.priority or "med")
    -- no target AND no nearby hero (rare -- nearestHero() almost always succeeds): fall back to just
    -- walking to o.at, same anchor trick as move/defend, not raw MoveToPos (see file header).
    local fallbackAnchor
    if not tgt then
        local x, y, z = xyz(o.at)
        if x then fallbackAnchor = anchorAt(x, y, z, tracker) end
    end
    -- CONFIRMED LIVE 2026-07-24: missing Force=true here the same way `face` was -- a follower coming off a
    -- `defend`/guard order still holds that order's Ai.Anchor lock, and an Attack goal without Force=true
    -- silently fails to override it (no error, the unit just keeps standing there). Force=true, matching
    -- every other combat/movement goal in this file, is what actually preempts it.
    for _, g in ipairs(guids) do
        local a = actor(g)
        if tgt then
            aiGoal({ AIGuid = a, Goal = "Attack", Target = tgt, Priority = p, Force = true })
        elseif fallbackAnchor then
            aiGoal({ AIGuid = a, Goal = "MoveTo", Target = fallbackAnchor, Priority = p, Force = true })
        end
        haste(a, o.speed)
    end
end

BEHAVIORS.patrol = function(tracker, o, guids)
    local pts = o.points or (o.at and { o.at }) or {}
    if #pts == 0 then return end
    local loop, p = (o.loop ~= false and #pts >= 2), pri(o.priority)
    -- one shared anchor per WAYPOINT, not per unit -- every patrolling unit targets the same anchor when
    -- it reaches step i, instead of spawning a fresh TinyGeometry per unit per point.
    local anchors = {}
    for i, pt in ipairs(pts) do
        local x, y, z = xyz(pt)
        if x then anchors[i] = anchorAt(x, y, z, tracker) end
    end
    -- o.onComplete (optional, and only for a NON-looping route -- a loop never "finishes") fires once
    -- every guid has stepped off the end of its route.
    local pending = #guids
    local function finishGuid()
        if o.onComplete then
            pending = pending - 1
            if pending <= 0 then pcall(o.onComplete) end
        end
    end
    for _, g in ipairs(guids) do
        local a = actor(g); haste(a, o.speed)
        local i = 0
        local function step()
            i = i + 1
            if i > #pts then
                if loop then i = 1
                else
                    finishGuid()
                    return
                end
            end
            local anchor = anchors[i]; if not anchor then return end
            -- CONFIRMED LIVE 2026-07-25 (see move's own identical fix): Ai.Goal can silently refuse to
            -- register at all -- no handle, no error, and no Callback EVER arrives for this waypoint. Left
            -- unhandled, this guid's route (and, for a non-looping route, the WHOLE group's onComplete)
            -- hangs forever on a single blocked waypoint. Ending this guid's route right there (same as
            -- running off the end of pts) beats waiting on a Callback that's never coming.
            local h = aiGoal({ AIGuid = a, Goal = "MoveTo", Target = anchor, Priority = p, Force = true,
                     Callback = function(_, State) if State == 1 then step() end end })
            if not h then finishGuid() end
        end
        step()
    end
end

-- BEHAVIORS.follow -- CONFIRMED LIVE 2026-07-24 as Mercenaries 2's own real "recruit" mechanic (see
-- resident/mrxfollow.lua in the decompiled game script corpus): a dedicated Ai.Role("Follow") that
-- auto-maintains MinDistance/MaxDistance on its own and follows the target into/out of vehicles for free --
-- a completely different, far more capable primitive than the old approach here (re-issuing a plain
-- "MoveTo" goal on a dumb timer, no distance-holding, no vehicle handling at all). Three prerequisites,
-- confirmed live IN THIS ORDER, each one silently no-op'ing the whole thing if skipped:
--   1. a hostile/negative Ai.Feeling toward the target blocks the role outright -- neutralize it first.
--   2. Ai.LivingWorld(..., "LivingWorldBehaviour", false) turns off the unit's ambient background AI, which
--      otherwise fights the Follow role for control.
--   3. Ai.SetState(..., "Vip", true) is the confirmed MISSING PIECE -- without it, Ai.Role("Follow") still
--      returns a truthy handle (looks accepted) but the unit never actually moves. This is presumably the
--      same flag the game's own recruitable companions/hostages carry.
-- Nothing here reverts feeling/LivingWorld/Vip when following ends (no Callback wired) -- a genuine gap,
-- not a silent one; a caller that needs a clean stop should track the guid and reissue `hold` or `animate`.
BEHAVIORS.follow = function(tracker, o, guids)
    local target = o.target and Ess.AIOrders.group(o.target)[1] or nearestHero()
    if not target then return end
    for _, g in ipairs(guids) do
        local a = actor(g)
        local ok, feeling = pcall(Ai.GetFeeling, a, target)
        if ok and feeling and feeling < 0 then pcall(Ai.SetFeeling, a, target, 100) end
        pcall(Ai.LivingWorld, { AIGuid = a, Attrib = "LivingWorldBehaviour", State = false })
        pcall(Ai.SetState, { AIGuid = a, State = "Vip", Value = true })
        pcall(Ai.Role, {
            AIGuid = a, Role = "Follow", Target = target,
            MinDistance = o.minDistance or 2, MaxDistance = o.maxDistance or 30, MoveDistance = o.moveDistance or 4,
            Priority = "hiPri", HardPriority = true,
        })
        haste(a, o.speed)
    end
end

BEHAVIORS.flee = function(tracker, o, guids)
    local hero = nearestHero(); local hx, hz
    if hero then local ok, x, _, z = pcall(Object.GetPosition, hero); if ok then hx, hz = x, z end end
    local dist = o.distance or 120
    for _, g in ipairs(guids) do
        local a = actor(g)
        local ok, gx, gy, gz = pcall(Object.GetPosition, g)
        if ok and gx then
            local dx, dz = gx - (hx or gx - 1), gz - (hz or gz)
            local len = math.sqrt(dx * dx + dz * dz); if len < 1 then dx, dz, len = 1, 0, 1 end
            local anchor = anchorAt(gx + dx / len * dist, gy, gz + dz / len * dist, tracker)
            if anchor then
                aiGoal({ AIGuid = a, Goal = "MoveTo", Target = anchor, Priority = "HiPri", Force = true })
            end
            haste(a, o.speed or 1)
        end
    end
end

BEHAVIORS.enter = function(tracker, o, guids)
    -- CONFIRMED LIVE 2026-07-24: same gap `attack`'s o.target had -- this only ever resolved a registered
    -- group name or a STRING name via Pg.GetGuidByName, so a raw vehicle uGuid (e.g. from
    -- Ess.Easy.Followers.orderEnter) silently resolved to nil and the whole behavior no-op'd, no error.
    -- Group name (if registered) still comes first; a string falls to Pg.GetGuidByName same as before;
    -- anything else (a raw uGuid) is now used directly instead of being dropped.
    local veh = o.target and Ess.AIOrders.group(o.target)[1]
    if not veh and o.target then
        if type(o.target) == "string" then
            local ok, g = pcall(Pg.GetGuidByName, o.target)
            if ok then veh = g end
        else
            veh = o.target
        end
    end
    if not veh then return end
    -- CONFIRMED LIVE 2026-07-24: a freshly Pg.Spawn'd vehicle silently refuses an "Enter" goal (Ai.Goal
    -- returns nil, no error) until Vehicle.Usable(veh, true) has been called on it once -- matches
    -- oilcon002.lua's own confirmed sequence (Vehicle.Usable(..., true) immediately before its own Enter
    -- goal). A harmless no-op on a vehicle that's already usable (every placed-in-level vehicle already is).
    pcall(Vehicle.Usable, veh, true)
    for _, g in ipairs(guids) do
        aiGoal({ AIGuid = g, Goal = "Enter", Target = veh, Role = o.role or "passenger", Priority = "HiPri", Force = true })
    end
end

BEHAVIORS.deploy = function(tracker, o, guids)
    for _, g in ipairs(guids) do pcall(Ai.Deploy, { Vehicle = g, Role = "Passenger", Priority = "HiPri", Force = true }) end
end

BEHAVIORS.animate = function(tracker, o, guids)
    for _, g in ipairs(guids) do pcall(Human.DoAction, g, o.action or "Cower") end
end

Ess.AIOrders._behaviors = BEHAVIORS

-- Ess.AIOrders.command(guids, behavior, opts, tracker) -> ok
-- `tracker` (an Ess.Track), if given, receives any spawned anchor props (defend) or scheduled follow-up
-- events (follow) for cleanup -- omit it and those just aren't tracked for you.
function Ess.AIOrders.command(guids, behavior, opts, tracker)
    opts = opts or {}
    local fn = BEHAVIORS[behavior]
    if not fn then
        Ess.Log("AIOrders.command: unknown behavior '" .. tostring(behavior) .. "'")
        return false
    end
    local ok, err = pcall(fn, tracker, opts, guids or {})
    if not ok then Ess.Log("AIOrders.command '" .. tostring(behavior) .. "' error: " .. tostring(err)) end
    return ok
end
