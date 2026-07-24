-- Ess/20_loop.lua -- Ess.Loop: the one shared self-rescheduling heartbeat primitive.
-- (Wall-clock delta timing lives in Ess.Time -- see Ess.Time.clock in 23_time.lua. It used to live here as
-- a separate Ess.Timer, which duplicated Ess.Time's native stamp calls; folded into Ess.Time so there's one
-- home for timing.)
--
-- API:
--   Ess.Loop.start(id, interval, tickFn)   tickFn() returns true to keep going, false/nil to auto-stop
--   Ess.Loop.stop(id)
--   Ess.Loop.isRunning(id) -> bool
--   Ess.Loop.stats(id) -> { interval, ticks, lastDuration, avgDuration, lastError } | nil
--   Ess.Loop.list() -> { {id=, interval=, ticks=, lastDuration=, avgDuration=, lastError=}, ... }, sorted by id
--
-- stats()/list() are purely additive introspection -- every existing call site across this project (20+
-- files, none of which touch Ess.Loop._reg directly, only the public start/stop/isRunning surface) is
-- unaffected. Each tick's real wall-clock cost is measured via Ess.Time.stamp() (a call into a file that
-- loads AFTER this one in build/merge.py's MANIFEST -- safe only because it's invoked from inside the
-- step() closure below, which never runs until long after the whole merged chunk has finished loading, by
-- which point Ess.Time exists; do not call Ess.Time.* at this file's top level).
-- lastDuration/avgDuration exist specifically to catch a tickFn that's expensive relative to its own
-- interval (a tight poller doing real work) -- compare lastDuration/interval yourself for a "% of budget"
-- figure; that ratio isn't computed here so this stays a plain data source, not an opinionated monitor.

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

    -- Reset stats on every start() call, even when reusing an existing `reg` (same id, new generation) --
    -- a fresh start conceptually means a fresh loop, so stale numbers from whatever ran under this id
    -- before shouldn't linger (e.g. across an OnKey script's re-run, or a hot-reloaded tickFn).
    reg.interval = interval
    reg.ticks = 0
    reg.lastDuration = nil
    reg.avgDuration = nil
    reg.lastError = nil

    local function step()
        if Ess.Loop._reg[id] ~= reg or reg.gen ~= myGen then return end -- superseded or explicitly stopped
        local t0 = Ess.Time.stamp()
        local ok, keepGoing = pcall(tickFn)
        local dt = Ess.Time.elapsed(t0)
        reg.ticks = reg.ticks + 1
        reg.lastDuration = dt
        -- Exponential moving average (weight 0.2) instead of a running total/count -- deliberately favors
        -- recent behavior over all-time history, so a loop that WAS slow at first but has since settled
        -- reads as settled, not permanently dragged down by its own startup cost.
        reg.avgDuration = reg.avgDuration and (reg.avgDuration + (dt - reg.avgDuration) * 0.2) or dt
        if not ok then
            reg.lastError = tostring(keepGoing)
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

-- Ess.Loop.stats(id) -> { interval, ticks, lastDuration, avgDuration, lastError } | nil
-- A snapshot, not a live reference -- safe to hold onto and print without it changing under you.
function Ess.Loop.stats(id)
    local reg = Ess.Loop._reg[id]
    if not reg then return nil end
    return {
        interval = reg.interval,
        ticks = reg.ticks,
        lastDuration = reg.lastDuration,
        avgDuration = reg.avgDuration,
        lastError = reg.lastError,
    }
end

-- Ess.Loop.list() -> array of { id=, interval=, ticks=, lastDuration=, avgDuration=, lastError= }
-- Sorted by id for stable, predictable ordering across repeated calls (plain pairs() iteration order
-- isn't guaranteed) -- the shape a dashboard/monitor wants to poll on an interval and just render.
function Ess.Loop.list()
    local ids = {}
    for id in pairs(Ess.Loop._reg) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)

    local out = {}
    for _, id in ipairs(ids) do
        local reg = Ess.Loop._reg[id]
        out[#out + 1] = {
            id = id,
            interval = reg.interval,
            ticks = reg.ticks,
            lastDuration = reg.lastDuration,
            avgDuration = reg.avgDuration,
            lastError = reg.lastError,
        }
    end
    return out
end

