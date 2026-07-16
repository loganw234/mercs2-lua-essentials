-- Ess/23_time.lua -- Ess.Time: the Sys.*TimeStamp elapsed-time idiom + time-scale, wrapped.
--
-- API:
--   Ess.Time.stamp() -> uStamp                 real-world clock mark
--   Ess.Time.mainStamp() -> uStamp              pausable/scaled-clock mark
--   Ess.Time.mark(uStamp)                       re-mark an existing stamp in place
--   Ess.Time.elapsed(uStamp) -> n | 0           seconds since the stamp was marked
--   Ess.Time.since(uStamp) -> n | 0             alias of elapsed (reads better at some call sites)
--   Ess.Time.cooldown(seconds) -> ready() -> bool   one-line "has n seconds passed since last ready()==true"
--   Ess.Time.scale(n)                           Sys.SetTimeScale, e.g. Ess.Time.scale(0.2) for slow-mo
--   Ess.Time.restoreScale()                     Ess.Time.scale(1)
--   Ess.Time.format(nSeconds, bUseTenths) -> s  Junk.FormatTime -- a display string for a HUD timer/countdown
--   Ess.Easy.Time.slowmo(n, seconds)            scale(n) that auto-restores after `seconds` (default 0.2, 2)

local Ess = _G.Ess
Ess.Time = Ess.Time or {}

-- Ess.Time.stamp() / Ess.Time.mainStamp() -> uStamp
-- CONFIRMED idiom (resident/antiair.lua:279, resident/mrxplaystate.lua:111, resident/mrxstatsmanager.lua,
-- resident/mrxtaskrace.lua): a stamp is an opaque handle you mark once and read via TimeStampGetElapsed --
-- the real building-block for polled elapsed-time (cooldowns, "how long has X been true") as opposed to
-- the callback-based Event.TimerRelative pattern, which only fires once after a fixed delay.
-- Real-world clock (keeps advancing through pause/slow-mo).
function Ess.Time.stamp()
    local ok, s = pcall(Sys.RealTimeStamp)
    return ok and s or nil
end

-- Pausable/scaled clock (tracks Ess.Time.scale() and game pause) -- use this for gameplay cooldowns that
-- should freeze with the game; use Ess.Time.stamp() for real-world/UI timing that shouldn't.
function Ess.Time.mainStamp()
    local ok, s = pcall(Sys.MainTimeStamp)
    return ok and s or nil
end

-- Ess.Time.mark(uStamp) -- re-marks an EXISTING stamp handle in place (confirmed call sites always re-mark
-- a stamp previously produced by *TimeStamp() rather than creating a new one each time).
function Ess.Time.mark(uStamp)
    if not uStamp then return end
    pcall(Sys.TimeStampMark, uStamp)
end

function Ess.Time.elapsed(uStamp)
    if not uStamp then return 0 end
    local ok, n = pcall(Sys.TimeStampGetElapsed, uStamp)
    return (ok and n) or 0
end

Ess.Time.since = Ess.Time.elapsed

-- Ess.Time.cooldown(seconds) -> ready() -> bool
-- One-line answer to "am I allowed to do this again yet" -- every real cooldown call site hand-rolls a
-- stamp + elapsed + re-mark-on-success loop; this closes over all three. ready() returns true and re-marks
-- at most once per `seconds` window; returns false (and does NOT re-mark) otherwise, so retrying doesn't
-- push the window back.
--
-- The FIRST call is always ready (no stamp exists yet to be "on cooldown" against) -- an ability/action
-- gated by a freshly-created cooldown() should be usable right away, not blocked for the first `seconds`
-- as if it had just been used.
function Ess.Time.cooldown(seconds)
    seconds = seconds or 1
    local uStamp = nil
    return function()
        if uStamp and Ess.Time.elapsed(uStamp) < seconds then return false end
        if uStamp then Ess.Time.mark(uStamp) else uStamp = Ess.Time.stamp() end
        return true
    end
end

-- Ess.Time.scale(n) -- CONFIRMED (resident/hero.lua:249): Sys.SetTimeScale for slow-motion-style effects,
-- e.g. Ess.Time.scale(0.2) for a 5x slowdown. Ess.Time.restoreScale() is just scale(1) under a clearer name
-- for the common "undo the slow-mo" call site.
function Ess.Time.scale(n)
    pcall(Sys.SetTimeScale, n)
end

function Ess.Time.restoreScale()
    Ess.Time.scale(1)
end

-- Ess.Time.format(nSeconds, bUseTenths) -> s
-- CONFIRMED (resident/mrxtimer.lua, resident/mrxstatsmanager.lua): Junk.FormatTime(nTime[, bUseTenths])
-- formats a raw seconds value (e.g. Ess.Time.elapsed(...)) into a display string -- pairs directly with
-- the rest of this namespace for a HUD countdown/stopwatch, and is the confirmed idiom real scripts use
-- for exactly that rather than hand-rolling minutes:seconds formatting.
function Ess.Time.format(nSeconds, bUseTenths)
    local ok, s = pcall(Junk.FormatTime, nSeconds, bUseTenths)
    return (ok and s) or nil
end

-- Ess.Easy.Time.slowmo(n, seconds) -- zero-config "slow the game down for a bit" for the common
-- explosion-impact/finisher-moment case: applies Ess.Time.scale(n) immediately and schedules a single
-- Ess.Time.restoreScale() via Ess.Loop after `seconds` of REAL time (Ess.Time.stamp, not mainStamp --
-- deliberately not scaled itself, or the restore would take `seconds / n` to actually fire).
Ess.Easy = Ess.Easy or {}
Ess.Easy.Time = Ess.Easy.Time or {}
function Ess.Easy.Time.slowmo(n, seconds)
    n = n or 0.2
    seconds = seconds or 2
    Ess.Time.scale(n)
    local uStamp = Ess.Time.stamp()
    local id = "Ess.Easy.Time.slowmo:" .. tostring(uStamp)
    Ess.Loop.start(id, 0.1, function()
        if Ess.Time.elapsed(uStamp) < seconds then return true end
        Ess.Time.restoreScale()
        return false
    end)
end
