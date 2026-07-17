-- Ess/59_objective.lua -- Ess.Objective + Ess.Quest: a lightweight COUNTED-GOAL tracker.
--
-- This fills the gap between the two things Ess already had and nothing in between:
--   * Ess.Hud.objective("Kill 5 enemies")  -- a bare text line. No state, no counter, no completion.
--   * Ess.Contract{...}                     -- a whole save-safe mission engine. Overkill for "show a goal".
-- Ess.Objective is the middle: a stateful goal that shows "Kill 5 enemies   3/5" on the HUD objective line,
-- ticks up as you advance it, and fires a callback when it's met -- WITHOUT authoring a Contract. It's pure
-- composition of pieces Ess already live-verifies: Ess.Hud.objective (the HUD line) + Ess.On (auto-wiring
-- completion to a world event) + Ess.Loop (the survive timer). No new engine calls.
--
-- Ess.Objective (Core) -- one counted goal:
--   local o = Ess.Objective.new{ label="Collect intel", target=5, onComplete=fn }
--   o:advance()        add 1 (default) -- HUD shows "Collect intel   1/5", then 2/5... fires onComplete at 5
--   o:advance(n) / o:set(n) / o:progress() -> count,target / o:isDone() / o:label(s)
--   o:complete() / o:fail() / o:cancel()   force an end (complete fires onComplete; cancel is silent)
--   opts: label, target(1), slot(1), show(true), onComplete, onProgress(count,target), onFail
--   opts.id  -- a stable id makes it RELOAD-SAFE: re-creating with the same id cancels the prior one first
--             (same idea as Ess.Loop.start's id), so an OnKey script re-run doesn't leak a stale watcher.
--
-- Ess.Quest (Core) -- an ordered SEQUENCE of objectives shown one at a time on the objective line. Steps can
-- be MANUAL (you advance them) or AUTO-WIRED (they complete themselves off a world event + drop their marker),
-- so a whole linear mission is one table with no glue:
--   Ess.Quest.new{ steps={
--       { reach = {2700,-14,-780, 10}, label = "Get to the docks" },   -- auto: arrive
--       { destroy = uTowerGuid,        label = "Blow the tower"    },   -- auto: it dies
--       { clear  = {2700,-14,-780, 50, "VZ"}, label = "Clear them out" }, -- auto: area emptied
--       "Escape",                                                       -- manual: call q:advance()
--   }}
--   :advance(n)   advance the CURRENT step  ·  :skip()  force current done -> next  ·  :cancel()
--   :step() -> i,total  ·  :current() -> the live Objective  ·  :isDone()
--   opts: steps, slot(1), showCounter(true -> "(2/3) label"), onStep(i,total), onComplete
-- (Heavier than this -- save-safe, co-op-synced, many objective types? That's Ess.Contract. Quest is the
--  lightweight "linear scripted sequence on the objective line" middle tier.)
--
-- Ess.Easy.Objective (Easy) -- the intent bundles: a goal WIRED to a world event in one line, no polling
-- or event glue on the caller's side. reach/destroy/clear also drop the matching MAP MARKER for you (so the
-- player sees WHERE) and clear it when the goal resolves -- the whole "show goal + mark it + detect + clean
-- up" loop in one call:
--   Ess.Easy.Objective(label, target, onComplete)        a manual counted goal (you call :advance())
--   Ess.Easy.Objective.reach(x,y,z,r, label, onDone)     enter the radius (drops a "go here" ground ring)
--   Ess.Easy.Objective.destroy(guid, label, onDone)      that object dies (marks it on radar/PDA/world)
--   Ess.Easy.Objective.clear(x,y,z,r, faction, label, onDone)  POLLS the area's population and completes
--                                                        when every `faction` unit in it is dead -- the
--                                                        "eliminate the enemies here" goal the engine has
--                                                        no clean per-kill event for. Shows "N left".
--   Ess.Easy.Objective.survive(seconds, label, onDone, onFail)  completes after N s; FAILS if the player dies
--   Ess.Easy.Quest(steps, onComplete)                    a one-liner Ess.Quest

local Ess = _G.Ess
Ess.Objective = Ess.Objective or {}
Ess.Quest = Ess.Quest or {}
-- id -> live objective, for reload-safe replace (persists across OnKey re-runs, like Ess.UI's registries;
-- a world reload kills the underlying loops anyway, leaving only harmless bookkeeping -- see Ess.Loop's note).
Ess.Objective._active = Ess.Objective._active or {}

-- ---- Ess.Objective ------------------------------------------------------------------------------------
local Obj = {}
Obj.__index = Obj

-- the HUD string for an objective: bare label, or "label   3/5" once it's a real count (target > 1).
local function objText(o)
    if (o._target or 1) > 1 then return o._label .. "   " .. o._count .. "/" .. o._target end
    return o._label
end
local function objPaint(o)
    if o._hidden or o._done then return end
    Ess.Hud.objective(objText(o), o._slot)
end

function Ess.Objective.new(opts)
    opts = opts or {}
    local id = opts.id
    -- reload-safe: an id already in use is cancelled (silently) before the replacement takes its slot
    if id and Ess.Objective._active[id] then pcall(function() Ess.Objective._active[id]:cancel() end) end
    local o = setmetatable({
        _id = id,
        _label = tostring(opts.label or "Objective"),
        _target = math.max(1, tonumber(opts.target) or 1),
        _count = 0,
        _slot = tonumber(opts.slot) or 1,
        _onComplete = opts.onComplete,
        _onProgress = opts.onProgress,
        _onFail = opts.onFail,
        _stops = {},                       -- teardown fns (wired Ess.On stop()s, timers) run at end-of-life
        _done = false,
        _hidden = opts.show == false,
    }, Obj)
    if id then Ess.Objective._active[id] = o end
    objPaint(o)
    return o
end

-- register a teardown fn (an Ess.On stop(), etc.) to run when this objective ends -- used by the Easy
-- auto-wired constructors so their world-event watcher is torn down the moment the goal resolves.
function Obj:_own(stopFn)
    if type(stopFn) == "function" then self._stops[#self._stops + 1] = stopFn end
    return self
end
function Obj:_teardown()
    for _, s in ipairs(self._stops) do pcall(s) end
    self._stops = {}
    if self._id and Ess.Objective._active[self._id] == self then Ess.Objective._active[self._id] = nil end
end

function Obj:advance(n)
    if self._done then return self end
    self._count = self._count + (tonumber(n) or 1)
    if self._count > self._target then self._count = self._target end
    objPaint(self)
    if self._onProgress then pcall(self._onProgress, self._count, self._target) end
    if self._count >= self._target then self:complete() end
    return self
end
function Obj:set(n)
    if self._done then return self end
    n = tonumber(n) or 0
    if n < 0 then n = 0 elseif n > self._target then n = self._target end
    self._count = n
    objPaint(self)
    if self._onProgress then pcall(self._onProgress, self._count, self._target) end
    if self._count >= self._target then self:complete() end
    return self
end
function Obj:progress() return self._count, self._target end
function Obj:isDone() return self._done end
function Obj:label(s) self._label = tostring(s); objPaint(self); return self end

-- complete/fail/cancel all end the objective's life exactly once; the HUD line is cleared (the game's own
-- objectives don't linger once met -- celebrate from the onComplete callback with a banner/toast if you want).
local function endObjective(o, cb)
    if o._done then return o end
    o._done = true
    if not o._hidden then Ess.Hud.objective(nil, o._slot) end
    o:_teardown()
    if cb then pcall(cb) end
    return o
end
function Obj:complete() self._count = self._target; return endObjective(self, self._onComplete) end
function Obj:fail()     return endObjective(self, self._onFail) end
function Obj:cancel()   return endObjective(self, nil) end   -- silent (reload-replace / manual abort)

function Obj:hide() self._hidden = true; Ess.Hud.objective(nil, self._slot); return self end
function Obj:show() self._hidden = false; objPaint(self); return self end

-- ---- Ess.Quest ----------------------------------------------------------------------------------------
local Qst = {}
Qst.__index = Qst

function Ess.Quest.new(opts)
    opts = opts or {}
    local q = setmetatable({
        _steps = {},
        _i = 0,
        _slot = tonumber(opts.slot) or 1,
        _showCounter = opts.showCounter ~= false,
        _onStep = opts.onStep,
        _onComplete = opts.onComplete,
        _done = false,
        _cur = nil,
    }, Qst)
    -- normalise each step to a { kind, label, ... } def. A step can be:
    --   "text"                          a manual step (advance it yourself)
    --   { label=, target= }             a manual COUNTED step
    --   { reach={x,y,z,r}, label= }     auto-completes on arrival (Ess.Easy.Objective.reach)
    --   { destroy=guid, label= }        auto-completes when that object dies
    --   { clear={x,y,z,r,faction}, label= }  auto-completes when the area is cleared
    -- The auto kinds turn a whole linear mission into one table -- no manual advancing.
    for _, s in ipairs(opts.steps or {}) do
        local def
        if type(s) == "string" then def = { kind = "manual", label = s, target = 1 }
        elseif s.reach then def = { kind = "reach", label = tostring(s.label or "Reach the marker"), p = s.reach }
        elseif s.destroy then def = { kind = "destroy", label = tostring(s.label or "Destroy the target"), guid = s.destroy }
        elseif s.clear then def = { kind = "clear", label = tostring(s.label or "Clear the area"), p = s.clear }
        else def = { kind = "manual", label = tostring(s.label or "Objective"), target = math.max(1, tonumber(s.target) or 1) } end
        q._steps[#q._steps + 1] = def
    end
    q:_advanceStep()
    return q
end

function Qst:_label(def, idx)
    if self._showCounter and #self._steps > 1 then return "(" .. idx .. "/" .. #self._steps .. ") " .. def.label end
    return def.label
end
-- move to the next step: build its Objective, wiring THAT objective's completion back into this quest. An
-- auto step (reach/destroy/clear) is built through the matching Ess.Easy.Objective constructor -- which
-- self-completes AND drops its own marker -- with the quest's advance as its onDone. (Those constructors use
-- the default objective line, slot 1; a quest on a non-default slot honours it for MANUAL steps only.)
function Qst:_advanceStep()
    self._i = self._i + 1
    if self._i > #self._steps then
        self._done = true; self._cur = nil
        Ess.Hud.objective(nil, self._slot)
        if self._onComplete then pcall(self._onComplete) end
        return
    end
    local idx, total, def = self._i, #self._steps, self._steps[self._i]
    local label = self:_label(def, idx)
    local onStepDone = function()
        if self._onStep then pcall(self._onStep, idx, total) end
        self:_advanceStep()
    end
    if def.kind == "reach" then
        local p = def.p
        self._cur = Ess.Easy.Objective.reach(p[1], p[2], p[3], p[4], label, onStepDone)
    elseif def.kind == "destroy" then
        self._cur = Ess.Easy.Objective.destroy(def.guid, label, onStepDone)
    elseif def.kind == "clear" then
        local p = def.p
        self._cur = Ess.Easy.Objective.clear(p[1], p[2], p[3], p[4], p[5], label, onStepDone)
    else
        self._cur = Ess.Objective.new{ label = label, target = def.target, slot = self._slot, onComplete = onStepDone }
    end
end

function Qst:advance(n) if self._cur then self._cur:advance(n) end return self end
function Qst:skip()     if self._cur then self._cur:complete() end return self end
function Qst:current()  return self._cur end
function Qst:step()     return self._i, #self._steps end
function Qst:isDone()   return self._done end
function Qst:cancel()
    if self._cur then self._cur:cancel() end
    self._done = true; self._cur = nil
    Ess.Hud.objective(nil, self._slot)
    return self
end

-- ---- Ess.Easy.Objective / Ess.Easy.Quest (the intent bundles) -----------------------------------------
Ess.Easy = Ess.Easy or {}

-- Ess.Easy.Objective is a CALLABLE TABLE: Ess.Easy.Objective(label, target, fn) makes a plain manual goal,
-- while Ess.Easy.Objective.reach/.destroy/.survive make goals already wired to a world event.
Ess.Easy.Objective = setmetatable({}, { __call = function(_, label, target, onComplete)
    return Ess.Objective.new{ label = label, target = target, onComplete = onComplete }
end })

-- register a mark handle to be cleared when the objective ends (nil-safe -- Ess.Mark.zone/object can return
-- nil, and Ess.Mark.clear no-ops on a nil or already-gone handle).
local function ownMark(o, h) if h then o:_own(function() Ess.Mark.clear(h) end) end end

-- reach: completes the instant the player walks within `r` of (x,y,z), and drops a "go here" ground ring so
-- they know where. One line instead of hand-wiring Ess.On.enterArea + a marker + an objective + teardown.
-- r defaults to 8 (a comfortable "you're here" radius).
function Ess.Easy.Objective.reach(x, y, z, r, label, onDone)
    r = r or 8
    local o = Ess.Objective.new{ label = label or "Reach the marker", target = 1, onComplete = onDone }
    ownMark(o, Ess.Easy.Mark.zone(x, y, z, r))
    o:_own(Ess.On.enterArea(x, y, z, r, function() o:advance() end))
    return o
end

-- destroy: completes when a KNOWN object (you already hold its guid) dies; marks it on radar/PDA/world.
function Ess.Easy.Objective.destroy(guid, label, onDone)
    local o = Ess.Objective.new{ label = label or "Destroy the target", target = 1, onComplete = onDone }
    ownMark(o, Ess.Easy.Mark.objective(guid))
    o:_own(Ess.On.death(guid, function() o:advance() end))
    return o
end

-- clear: "eliminate every <faction> in this area." The engine has no clean per-kill event, so this POLLS the
-- area population (Ess.Probe.nearby with the faction label) once a second and completes when it hits zero --
-- the same way you'd detect "area cleared" by hand, bundled. The label shows how many are left; marks the zone.
--   faction: an Object.HasLabel string (e.g. "VZ"); nil counts ALL humans in the radius.
function Ess.Easy.Objective.clear(x, y, z, r, faction, label, onDone)
    r = r or 40
    local base = label or "Clear the area"
    local function left() return #Ess.Probe.nearby(x, y, z, r, "humans", faction) end
    local o = Ess.Objective.new{ label = base .. "   " .. left() .. " left", target = 1, onComplete = onDone }
    ownMark(o, Ess.Easy.Mark.zone(x, y, z, r))
    o:_own(Ess.On.tick(1, function()
        if o:isDone() then return end
        local n = left()
        if n <= 0 then o:complete() else o:label(base .. "   " .. n .. " left") end
    end))
    return o
end

-- survive: a live countdown that completes after `seconds`, or FAILS if the local player dies first. The
-- label shows the remaining seconds ("Survive   12s") so the player sees the clock without any extra HUD.
function Ess.Easy.Objective.survive(seconds, label, onDone, onFail)
    seconds = math.max(1, tonumber(seconds) or 30)
    local base = label or "Survive"
    local o = Ess.Objective.new{ label = base .. "   " .. seconds .. "s", target = 1,
        onComplete = onDone, onFail = onFail }
    local remaining = seconds
    o:_own(Ess.On.tick(1, function()
        if o:isDone() then return end
        remaining = remaining - 1
        if remaining > 0 then o:label(base .. "   " .. remaining .. "s") else o:complete() end
    end))
    local char = Ess.Player.character(0)
    if char then o:_own(Ess.On.death(char, function() if not o:isDone() then o:fail() end end)) end
    return o
end

-- Ess.Easy.Quest(steps, onComplete) -- the one-liner sequence.
function Ess.Easy.Quest(steps, onComplete)
    return Ess.Quest.new{ steps = steps, onComplete = onComplete }
end
