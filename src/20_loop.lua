-- Ess/20_loop.lua -- Ess.Loop: the one shared self-rescheduling heartbeat primitive. Ess.Timer: wall-clock delta.
--
-- API:
--   Ess.Loop.start(id, interval, tickFn)   tickFn() returns true to keep going, false/nil to auto-stop
--   Ess.Loop.stop(id)
--   Ess.Loop.isRunning(id) -> bool
--   Ess.Timer.start() -> timer                   timer:elapsed() -> seconds since last call, clamped 0.25s

local Ess = _G.Ess
Ess.Loop = Ess.Loop or {}

-- Registry is ALWAYS reset fresh on (re)load, not `or {}` -- a world reload invalidates every previously
-- scheduled Event.TimerRelative anyway (this is an OnLoad script and OnLoad re-runs on every level load),
-- so any entries surviving from before the reload would just be stale bookkeeping pointing at loops the
-- engine already killed, not real leftover work. Matches uilib's own reload-safe boot reset.
Ess.Loop._reg = {}

-- Ess.Loop.start(id, interval, tickFn)
-- Registers (or REPLACES) a self-rescheduling Event.TimerRelative loop under `id`. `tickFn()` is called
-- every `interval` seconds; return true (or any truthy value) to keep going, false/nil to auto-stop.
--
-- Calling start() again with the SAME id supersedes any previous loop under that id immediately, via a
-- generation counter that invalidates the old loop's next reschedule. This is what makes it safe to call
-- Ess.Loop.start unconditionally from the top of a re-run OnKey script without leaking a duplicate loop
-- on every keypress -- exactly the class of bug uilib's own engine had to fix once already (this
-- generalizes that fix instead of every consumer re-deriving it).
--
-- The heartbeat this replaces is independently reimplemented at least five times across this project
-- (uilib's ensureTick, contracts.lua's poll(), WaveDefense's main loop, ForgeMenu, MissionForge) -- one
-- shared, reload-safe implementation instead.
function Ess.Loop.start(id, interval, tickFn)
    interval = interval or 1
    local reg = Ess.Loop._reg[id]
    if not reg then
        reg = { gen = 0 }
        Ess.Loop._reg[id] = reg
    end
    reg.gen = reg.gen + 1
    local myGen = reg.gen

    local function step()
        if Ess.Loop._reg[id] ~= reg or reg.gen ~= myGen then return end -- superseded or explicitly stopped
        local ok, keepGoing = pcall(tickFn)
        if not ok then
            Ess.Log("Loop '" .. tostring(id) .. "' tick error: " .. tostring(keepGoing))
            keepGoing = false
        end
        if Ess.Loop._reg[id] ~= reg or reg.gen ~= myGen then return end -- tickFn itself may have stopped/replaced this loop
        if keepGoing then
            Event.Create(Event.TimerRelative, { interval }, step)
        else
            Ess.Loop._reg[id] = nil
        end
    end

    Event.Create(Event.TimerRelative, { interval }, step)
end

-- Ess.Loop.stop(id) -- cancels a running loop early; its next scheduled tick will see it's gone and
-- quietly not reschedule (no error, no dangling reference).
function Ess.Loop.stop(id)
    Ess.Loop._reg[id] = nil
end

function Ess.Loop.isRunning(id)
    return Ess.Loop._reg[id] ~= nil
end

-- ============================================================
-- Ess.Timer -- Sys.RealTimeStamp/Sys.TimeStampMark/Sys.TimeStampGetElapsed, collapsed to one object.
-- Needed because Event.TimerRelative's OWN delta freezes under world-pause (menus/PDA) but the wall clock
-- does not -- every heartbeat in this project that has to keep working while the game is paused
-- (uilib, WaveDefense, ForgeCam, MissionForge) ends up hand-rolling this exact 3-call primitive.
-- ============================================================
Ess.Timer = Ess.Timer or {}
Ess.Timer.__index = Ess.Timer

function Ess.Timer.start()
    local ok, stamp = pcall(Sys.RealTimeStamp)
    return setmetatable({ stamp = ok and stamp or nil }, Ess.Timer)
end

-- :elapsed() -> seconds since the last :elapsed() call (or since :start(), the first time), clamped to
-- 0.25s so a long pause/hitch can't blow up per-tick math downstream.
function Ess.Timer:elapsed()
    if not self.stamp then return 0 end
    local ok, e = pcall(Sys.TimeStampGetElapsed, self.stamp)
    if not ok or not e then e = 0 end
    if e > 0.25 then e = 0.25 end
    pcall(Sys.TimeStampMark, self.stamp)
    return e
end
