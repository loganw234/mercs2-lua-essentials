-- Ess/65_cinematic.lua -- Ess.Cinematic: a declarative CUTSCENE TIMELINE runtime. Play an ordered list of
-- steps -- camera cuts/tracks/dollies, waits, spawns, AI orders, heli fly-ins, narration/VO, fades, shakes,
-- music, teleports -- pacing them with per-step "hold" durations. This is the engine a "cinematic suite"
-- for mission building sits on: MissionForge captures the SPATIAL steps (camera vantages, look-at points,
-- action markers) in-game, the web tool authors the SEQUENCING (order/durations/params), and both just emit
-- a `steps` list this runs. Ess.Contract plays one as a mission intro (def.cinematic).
--
-- It builds entirely on primitives that already exist and are live-confirmed -- Ess.Camera's cinematic
-- take-over (beginCinematic/placeCamera/lookAtObject-auto-track/fade), Ess.Object.spawn (guarded),
-- Ess.AIOrders.command, Ess.Vehicle.flyTo, Ess.Hud, Ess.Sound/VO, Ess.Player.teleport -- so it's an
-- ORCHESTRATOR, not new engine spelunking.
--
-- API:
--   Ess.Cinematic.play(steps, opts) -> seq | nil
--     steps = { {type=, <params>, hold=}, ... }   (see STEP handlers below for each type's params)
--     opts  = { camera=(true, take over the screen), blend=(0, instant cuts), skippable=(true),
--               skipKey=(0x1B ESC), startFade=(false, open on black), i=(0 player index), onDone=fn(ctx) }
--     Each step fires in order; the timeline advances `hold` seconds after firing it (hold 0 / omitted =
--     fire the NEXT step the same tick, so several actions can start together). A {type="wait"} step just
--     holds. ALWAYS restores camera/control on finish, skip, or stop -- a cutscene can never strand the
--     player. Skippable: pressing ESC fast-forwards -- every remaining step still FIRES (so mission actors
--     that a cutscene spawns/positions all end up in place), just with zero holds.
--   Ess.Cinematic.skip()                fast-forward the active cutscene (drain remaining steps instantly)
--   Ess.Cinematic.stop([seq])           end it now, restore control, run onDone
--   Ess.Cinematic.isPlaying() -> bool   /  Ess.Cinematic.active() -> seq | nil
--
-- STEP CONTEXT: steps share a `ctx` -- ctx.named[name]=guid (a `spawn` with name= registers here; camera
-- look=/order target=/fly target= resolve names, plus "player"/"partner"), ctx.groups[grp]={guids} (a
-- spawn with group= buckets here; order group= commands them), ctx.track (Ess.Track -- a spawn marked
-- ephemeral=true is cleaned up when the cutscene ends; by default spawns PERSIST into the mission).

import("MrxMusic")
pcall(function() import("MrxVoSequence") end)   -- optional VO; not every install has it

local Ess = _G.Ess
Ess.Cinematic = Ess.Cinematic or {}
Ess.Easy = Ess.Easy or {}
Ess.Easy.Cinematic = Ess.Easy.Cinematic or {}

Ess.Cinematic._active = nil   -- reset fresh every load: a reload tears down the world + every Ess.Loop, so
                              -- any sequence in flight before it is gone -- never carry a stale handle over.

local TICK       = 0.05
local LOOP_ID    = "Ess.Cinematic"
local CAMMOVE_ID = "Ess.Cinematic.cammove"

-- ---- small resolvers -------------------------------------------------------
local function xyz(p)
    if type(p) ~= "table" then return nil end
    return p.x or p[1], p.y or p[2], p.z or p[3]
end

-- ref -> guid: an existing guid (userdata) as-is, "player"/"partner" -> the hero(es), a name registered by
-- a `spawn` step (ctx.named), else a world-object name via Ess.Guid. Lets steps refer to things by a label
-- the author picked instead of a raw guid nobody has until runtime.
local function resolveGuid(ctx, ref)
    if ref == nil then return nil end
    if type(ref) == "userdata" then return ref end
    if ref == "player" or ref == "hero" then return Ess.Player.character(ctx.i) end
    if ref == "partner" or ref == "player2" then return Ess.Player.character(1) end
    if ctx.named[ref] then return ctx.named[ref] end
    return Ess.Guid(ref)
end

-- ---- step handlers ---------------------------------------------------------
-- Each: fn(step, ctx, seq). Side-effect only. Missing/empty params fail soft (a bad step never aborts the
-- whole timeline -- fireStep pcall-wraps and logs, then the sequence carries on).
local STEP = {}

-- {type="wait", time=} -- pure pause; the hold does the work (see holdOf).
STEP.wait = function() end

-- {type="camera", at={x,y,z}, look=<ref>|nil, lookAt={x,y,z}|nil, bone=, to={x,y,z}|nil}
-- Cut the camera to `at`, framing either a world point (lookAt) or an object that it then AUTO-TRACKS as it
-- moves (look, optional bone -- e.g. look="heli",bone="Bone_Chest" tracks a pilot). Give `to` for a DOLLY:
-- the camera lerps at->to across this step's hold (Blend 0 keeps it smooth, the confirmed moving-cam rule).
STEP.camera = function(step, ctx, seq)
    Ess.Loop.stop(CAMMOVE_ID)   -- end any dolly still running from a previous camera step
    local ax, ay, az = xyz(step.at)
    local function applyLook()
        if step.lookAt then
            local lx, ly, lz = xyz(step.lookAt)
            if lx then Ess.Camera.lookAtPoint(lx, ly, lz, seq.i) end
        elseif step.look then
            local g = resolveGuid(ctx, step.look)
            if g then Ess.Camera.lookAtObject(g, step.bone, seq.i) end
        end
    end
    if ax then Ess.Camera.placeCamera(ax, ay, az, seq.i) end
    applyLook()
    local tx, ty, tz = xyz(step.to)
    if ax and tx then
        local dur = step.hold or 0; if dur <= 0 then dur = 2 end
        local t0 = Ess.Time.stamp()
        Ess.Loop.start(CAMMOVE_ID, 0.033, function()
            local f = Ess.Time.elapsed(t0) / dur
            if f >= 1 then Ess.Camera.placeCamera(tx, ty, tz, seq.i); applyLook(); return false end
            Ess.Camera.placeCamera(ax + (tx - ax) * f, ay + (ty - ay) * f, az + (tz - az) * f, seq.i)
            applyLook()   -- re-issue the look every tick (required for a MOVING camera to stay smooth)
            return true
        end)
    end
end

-- {type="spawn", template=, at={x,y,z}, yaw=, name=, group=, ephemeral=, invincible=}
-- Spawn one thing (Ess.Object.spawn's blank-template guard applies). name= registers it for later steps;
-- group= buckets it (+ registers the group with Ess.AIOrders so an `order` step can command it). By default
-- it PERSISTS (mission actors outlive the cutscene); ephemeral=true cleans it up when the cutscene ends.
STEP.spawn = function(step, ctx)
    local x, y, z = xyz(step.at)
    if not (step.template and x) then return end
    local g = Ess.Object.spawn(step.template, x, y, z, step.yaw)
    if not g then return end
    if step.name then ctx.named[step.name] = g end
    if step.group then
        local grp = ctx.groups[step.group] or {}
        grp[#grp + 1] = g
        ctx.groups[step.group] = grp
        Ess.AIOrders.setGroup(step.group, grp)
    end
    if step.ephemeral then ctx.track:guid(g) end
    if step.invincible then Ess.Object.setInvincible(g, true, "Ess.Cinematic") end
end

-- {type="order", group=|target=, behavior=, at={x,y,z}, points={{x,y,z}..}, radius=, speed=, loop=}
-- Command a spawned group (or a single named target) with any Ess.AIOrders behavior (move/patrol/attack/...).
STEP.order = function(step, ctx)
    local guids = step.group and ctx.groups[step.group]
    if (not guids or #guids == 0) and step.target then
        local g = resolveGuid(ctx, step.target); if g then guids = { g } end
    end
    if not guids or #guids == 0 then return end
    local opts = { at = step.at, points = step.points, radius = step.radius, speed = step.speed, loop = step.loop }
    if step.attackTarget then opts.target = resolveGuid(ctx, step.attackTarget) end
    Ess.AIOrders.command(guids, step.behavior or "move", opts, ctx.track)
end

-- {type="fly", target=<heli ref>, at={x,y,z}, height=} -- send an AI helicopter to a point (Ai.Deliver).
STEP.fly = function(step, ctx)
    local heli = resolveGuid(ctx, step.target or step.name)
    local x, y, z = xyz(step.at)
    if not (heli and x) then return end
    Ess.Vehicle.flyTo(heli, x, y, z, { height = step.height })
end

-- {type="say", text=} / {type="banner", text=} -- a clean centered narration banner (Ess.Hud.banner).
STEP.say = function(step) Ess.Hud.banner(step.text or step.msg or "") end
STEP.banner = STEP.say

-- {type="hint", text=, id=} -- the persistent tutorial-style HUD popup (stays until hideHint / cutscene end).
STEP.hint = function(step, ctx)
    Ess.Hud.hint(step.text or step.msg or "", step.id or "ess_cinematic")
    ctx._hintId = step.id or "ess_cinematic"
end

-- {type="vo", lines={...}|text=, gap=} -- a voice-over line sequence (MrxVoSequence), gaps between lines.
STEP.vo = function(step)
    if not (MrxVoSequence and MrxVoSequence.Start) then return end
    local lines = step.lines or step.text
    if type(lines) == "string" then lines = { lines } end
    if type(lines) ~= "table" or #lines == 0 then return end
    local seq = {}
    for i, ln in ipairs(lines) do seq[#seq + 1] = ln; if i < #lines then seq[#seq + 1] = step.gap or 1 end end
    pcall(MrxVoSequence.Start, seq)
end

-- {type="music", cue=} / {type="music", stop=true} -- special music cue on/off (MrxMusic).
STEP.music = function(step)
    if step.stop or step.cue == "stop" or step.cue == "" then pcall(MrxMusic.StopSpecialMusic)
    else pcall(MrxMusic.PlaySpecialMusic, step.cue or "mu_pmc_panicloop_01") end
end

-- {type="fade", to=0|1} / {out=true} -- full-screen fade (0 clear, 1 black). Pairs across two steps for a
-- fade-out-then-in transition. (The cutscene ALSO auto-clears to 0 when it ends, so it can't strand black.)
STEP.fade = function(step) Ess.Camera.fade(step.to or (step.out and 1) or 0) end

-- {type="shake", preset=, amplitude=, duration=} -- camera shake for impacts.
STEP.shake = function(step, ctx, seq)
    Ess.Camera.shake(seq.i, step.preset, Ess.Player.character(seq.i), step.amplitude, step.duration)
end

-- {type="teleport", at={x,y,z}, yaw=} -- warp the hero(es) (Ess.Player.teleport -- co-op safe).
STEP.teleport = function(step)
    local x, y, z = xyz(step.at)
    if x then Ess.Player.teleport(x, y, z, step.yaw) end
end

-- {type="relations", pairs={{"China","Allied","hostile"}, ...}} -- set faction stance for the scene.
-- NOT auto-restored (a mission's relations persist past its intro); use Ess.Relations directly for scoped.
STEP.relations = function(step)
    if type(step.pairs) == "table" then Ess.Relations.apply(step.pairs, "Ess.Cinematic") end
end

-- {type="func", fn=function(ctx, seq) ... end} -- arbitrary code (the web tool's "custom" escape hatch).
STEP.func = function(step, ctx, seq) if type(step.fn) == "function" then pcall(step.fn, ctx, seq) end end
STEP.custom = STEP.func

-- ---- runtime ---------------------------------------------------------------
local function fireStep(seq, step)
    local h = STEP[step.type or ""]
    if not h then Ess.Log("Cinematic: unknown step type '" .. tostring(step.type) .. "'"); return end
    local ok, err = pcall(h, step, seq.ctx, seq)
    if not ok then Ess.Log("Cinematic step '" .. tostring(step.type) .. "' error: " .. tostring(err)) end
end

local function holdOf(seq, step)
    if seq.skipping then return 0 end
    local h = step.hold
    if h == nil and step.type == "wait" then h = step.time or step.seconds end
    return tonumber(h) or 0
end

local function finish(seq)
    if seq.done then return end
    seq.done = true
    Ess.Loop.stop(LOOP_ID)
    Ess.Loop.stop(CAMMOVE_ID)
    if seq.opts.camera ~= false then Ess.Camera.endCinematic(seq.i) end
    Ess.Camera.fade(0)                                   -- never leave the screen faded to black
    if seq.ctx._hintId then Ess.Hud.hideHint(seq.ctx._hintId) end
    pcall(function() seq.ctx.track:closeAll() end)       -- drop only the ephemeral spawns (persistent ones stay)
    if Ess.Cinematic._active == seq then Ess.Cinematic._active = nil end
    Ess.Log("Cinematic: done (" .. tostring(seq.idx) .. "/" .. tostring(#seq.steps) .. " steps)")
    if type(seq.opts.onDone) == "function" then pcall(seq.opts.onDone, seq.ctx) end   -- fire AFTER the done log so callback logs read in order
end

local function tick(seq)
    if seq.done then return false end
    if seq.opts.skippable ~= false and not seq.skipping then
        local input = Ess.Input.poll()
        for _, vk in ipairs(input.pressed) do
            if vk == (seq.opts.skipKey or 0x1B) then seq.skipping = true; Ess.Log("Cinematic: skipped") end
        end
    end
    local t = Ess.Time.elapsed(seq.t0)
    while not seq.done and t >= seq.nextAt and seq.idx < #seq.steps do
        seq.idx = seq.idx + 1
        local step = seq.steps[seq.idx]
        fireStep(seq, step)
        seq.nextAt = seq.nextAt + holdOf(seq, step)
    end
    if seq.idx >= #seq.steps and t >= seq.nextAt then finish(seq); return false end
    return true
end

-- Ess.Cinematic.play(steps, opts) -> seq | nil
function Ess.Cinematic.play(steps, opts)
    if type(steps) ~= "table" then return nil end
    opts = opts or {}
    if Ess.Cinematic._active then Ess.Cinematic.stop() end   -- one cutscene at a time; a new one supersedes
    local i = opts.i or 0
    local seq = {
        steps = steps, opts = opts, i = i, idx = 0, nextAt = 0, skipping = false, done = false,
        ctx = { named = {}, groups = {}, i = i, track = Ess.Track.new() },
    }
    Ess.Cinematic._active = seq
    Ess.Input.clear()                                        -- drop the key that launched us (no instant skip)
    if opts.camera ~= false then Ess.Camera.beginCinematic(i, opts.blend or 0) end
    if opts.startFade then Ess.Camera.fade(1) end            -- open on black; fade in via a step
    seq.t0 = Ess.Time.stamp()
    Ess.Log("Cinematic: playing " .. #steps .. " step(s)" .. (opts.camera == false and " (no camera takeover)" or ""))
    Ess.Loop.start(LOOP_ID, TICK, function() return tick(seq) end)
    return seq
end

function Ess.Cinematic.skip()  if Ess.Cinematic._active then Ess.Cinematic._active.skipping = true end end
function Ess.Cinematic.stop(seq)
    seq = seq or Ess.Cinematic._active
    if seq then finish(seq) end
end
function Ess.Cinematic.isPlaying() return Ess.Cinematic._active ~= nil end
function Ess.Cinematic.active()    return Ess.Cinematic._active end

-- Ess.Easy.Cinematic.play(steps, onDone) -- the zero-opts entry (skippable cutscene, camera takeover).
function Ess.Easy.Cinematic.play(steps, onDone)
    return Ess.Cinematic.play(steps, { onDone = onDone })
end

-- Ess.Easy.Cinematic.shot(at, lookAt, seconds) -> step -- build one static camera shot on a world point,
-- held `seconds`. Sugar so a hand-authored list reads as a storyboard: { shot(a,b,4), shot(c,d,3), ... }.
function Ess.Easy.Cinematic.shot(at, lookAt, seconds)
    return { type = "camera", at = at, lookAt = lookAt, hold = seconds or 3 }
end
