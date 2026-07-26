-- Ess/94_easy_world.lua -- Ess.Easy.World: one-line "make the world do X" verbs for beginners. Each hides
-- the import + the namespace a newcomer would otherwise have to hunt down -- the whole point of the Easy
-- tier is that the thought "I want to remove the map boundary" becomes exactly one call you can guess.
--
-- API:
--   Ess.Easy.World.removeMapBoundary()   drop the invisible walls fencing the player into the unlocked map
--   Ess.Easy.World.clearWanted()         instantly lose all heat (clear the pursuit/wanted level)
--   Ess.Easy.World.tint(r, g, b)         wash the world in an ambient color (0..255)
--   Ess.Easy.World.brightness(n)         overall light level (0.05 ~ near-black, 1 = normal)
--   Ess.Easy.World.hellscape()           fun preset: dark + deep red
--   Ess.Easy.World.resetAtmosphere()     undo any tint/brightness back to the region default
--   Ess.Easy.World.night() / .day()      hold the time-of-day clock. NOT map-wide -- regions with their
--                                        own atmosphere preset override it; see the note at the impl
--   Ess.Easy.World.lockTimeOfDay(n)      the same, for any 0..1 time
--   Ess.Easy.World.freezeTime()          stop the day/night cycle -- THIS ONE IS RELIABLY MAP-WIDE
--   Ess.Easy.World.setTimeSpeed(n)       rescale the cycle (0 = frozen); no getter exists to restore it
--   Ess.Easy.World.unlockTimeOfDay(nSpeed)   release the lock; leaves the clock where it is unless given

import("WifVzBoundary")

local Ess = _G.Ess
Ess.Easy = Ess.Easy or {}
Ess.Easy.World = Ess.Easy.World or {}

-- Ess.Easy.World.removeMapBoundary() -- removes the single "world boundary" that fences the player into the
-- story-unlocked portion of the map (the invisible wall + the Fiona-voiced warning + static). CONFIRMED
-- (WifVzBoundary.RemoveWorldBoundary, real call site in the decompiled corpus). This is DISTINCT from
-- Ess.Player.removeBoundaries, which clears the local player's own per-player boundary volumes.
--
-- CAVEAT (surfaced auditing this): this call is HOST/SERVER-authoritative -- it works in single-player and
-- for the co-op host, but no-ops on a co-op CLIENT, and it only clears whatever main boundary is currently
-- active. For a client-safe full unlock use Ess.Player.removeBoundaries() instead (the confirmed-live
-- Player.RemoveAllBoundary loop). Kept as its own verb because it targets the STORY world-boundary system
-- specifically, which is what a single-player roamer usually means. No clean restore.
function Ess.Easy.World.removeMapBoundary()
    Ess.Safe.quiet(WifVzBoundary.RemoveWorldBoundary)
end

-- Ess.Easy.World.clearWanted() -- instantly drop all pursuit/wanted heat. CONFIRMED (Pg.ClearPursuitLock,
-- a global -- no import; real call sites in vz mission scripts + MrxFactionManager).
function Ess.Easy.World.clearWanted()
    Ess.Safe.quiet(Pg.ClearPursuitLock, true)
end

-- ATMOSPHERE / lighting -- the CONFIRMED-live interface (session-camera-atmosphere-findings.md + verified
-- again in-engine): Graphics.Atmosphere.Begin() ; SetValue("fLightIntensity", n) /
-- SetColorValue("uiAmbientColor", r,g,b,255) ; End(dur). Graphics.Atmosphere is a global namespace (no
-- import). This hides the Begin/End scope.
--
-- These apply GLOBALLY (confirmed live: they modify whatever atmosphere is currently active, in ANY zone
-- including out of bounds). The one catch: CROSSING INTO A NEW ZONE re-applies that zone's own atmosphere,
-- which overwrites your custom look. So these are PERSISTENT by default -- a lightweight keeper loop watches
-- the active setting (Graphics.Atmosphere.GetCurrentSetting) and snaps your look back the instant a zone
-- swaps it out, so it survives driving across the map. Ess.Easy.World.resetAtmosphere() stops the keeper and
-- restores the natural look.
--
-- CORRECTION 2026-07-26: this block previously claimed the global setters SetTime/SetSky/SetTimeSpeed were
-- "confirmed inert in live play". That is WRONG for SetTime/SetTimeSpeed, and the error mattered -- it
-- steered work away from the only interface that actually moves the sky. Graphics.Atmosphere.SetTime(0.95)
-- visibly turns the sky to night (confirmed on screen by a human, and confirmed again by watching it fade
-- back over ~1s on a zone crossing); SetTimeSpeed(0) freezes the cycle. What IS true is that they are not
-- SetValue keys and take no part in the Begin/End transaction, so they need their own keeper -- see
-- lockTimeOfDay below. SetSky remains untested here and IS one of the 61 no-op stubs in the verified EXE
-- audit, so that part of the old claim may well hold.
Ess.Easy.World._atmo = Ess.Easy.World._atmo or nil   -- current custom apply fn (nil = none active)
Ess.Easy.World._atmoTag = nil                        -- last-seen active-setting string (zone-change detector)

local function rawApply(fn, dur)
    pcall(function()
        Graphics.Atmosphere.Begin()
        fn()
        Graphics.Atmosphere.End(dur or 0.5)
    end)
end

-- The keeper: re-apply the custom look whenever the active atmosphere setting changes (i.e. you crossed a
-- zone and it overwrote us). Uses End(0) on the re-apply so it SNAPS back with no easing flash.
local function setPersistentAtmo(fn)
    Ess.Easy.World._atmo = fn
    rawApply(fn, 0.5)                                 -- first application eases in
    local ok, cur = Ess.Safe.quiet(Graphics.Atmosphere.GetCurrentSetting)
    Ess.Easy.World._atmoTag = ok and tostring(cur) or nil
    Ess.Loop.start("Ess.World.atmoKeeper", 0.2, function()
        local f = Ess.Easy.World._atmo
        if not f then return false end               -- cleared by resetAtmosphere -> stop
        local ok2, c2 = Ess.Safe.quiet(Graphics.Atmosphere.GetCurrentSetting)
        local tag = ok2 and tostring(c2) or nil
        if tag ~= Ess.Easy.World._atmoTag then        -- zone swapped the atmosphere -> snap our look back
            rawApply(f, 0)
            local ok3, c3 = Ess.Safe.quiet(Graphics.Atmosphere.GetCurrentSetting)
            Ess.Easy.World._atmoTag = (ok3 and tostring(c3)) or tag
        end
        return true
    end)
end

-- Ess.Easy.World.tint(r, g, b) -- wash the world in an ambient color (0..255 each; default deep red).
function Ess.Easy.World.tint(r, g, b)
    setPersistentAtmo(function() Graphics.Atmosphere.SetColorValue("uiAmbientColor", r or 220, g or 30, b or 30, 255) end)
end

-- Ess.Easy.World.brightness(n) -- overall light level; 0.05 ~ near-black, 1 = normal, >1 blown out.
function Ess.Easy.World.brightness(n)
    setPersistentAtmo(function() Graphics.Atmosphere.SetValue("fLightIntensity", n or 1) end)
end

-- Ess.Easy.World.hellscape() -- the confirmed dark + deep-red look, in one call (and it sticks across zones).
function Ess.Easy.World.hellscape()
    setPersistentAtmo(function()
        Graphics.Atmosphere.SetValue("fLightIntensity", 0.08)
        Graphics.Atmosphere.SetColorValue("uiAmbientColor", 220, 30, 30, 255)
    end)
end

-- Ess.Easy.World.resetAtmosphere() -- stop the keeper and let the world's natural look return.
function Ess.Easy.World.resetAtmosphere()
    Ess.Easy.World._atmo = nil                        -- keeper stops itself on its next tick
    Ess.Loop.stop("Ess.World.atmoKeeper")
    Ess.Safe.quiet(Graphics.Atmosphere.Restore)
end

-- Ess.Easy.World.lockTimeOfDay(n) -- freeze the time-of-day clock at n (0..1) and hold it there.
-- Ess.Easy.World.night() / .day() / .unlockTimeOfDay() are the one-word forms.
--
-- ⚠⚠ READ THIS BEFORE USING IT: THIS IS NOT MAP-WIDE, and an earlier version of this comment wrongly said
-- it was. Measured 2026-07-26, with the keeper confirmed ticking 1,299 times at 10 Hz and the lock holding
-- at 0.95 the whole time -- and the sky still full daylight on one side of a region boundary.
--
-- TIME AND REGION ATMOSPHERE ARE SEPARATE SYSTEMS. A region's authored atmosphere preset paints the sky
-- DIRECTLY; it is not derived from the time-of-day clock. So SetTime moves a clock that any region with its
-- own preset simply overrides, and re-asserting faster cannot win because the clock is not the thing being
-- contested. Where this DOES hold:
--
--   * the gaps BETWEEN atmosphere regions (a large part of the map -- the engine falls back to a global
--     default there, which the clock does drive)
--   * regions whose preset follows the time clock rather than overriding it
--
-- and where it does not: any region with an authored preset of its own. Expect a visible change crossing
-- into one. That is a property of the engine's data, not a bug in this keeper.
--
-- The obvious fix -- reconfigure the regions themselves via Graphics.Atmosphere.ChangeLineRegionSetting --
-- is only a partial one and is NOT wired up here. All 40 regions are addressable (their names are in the
-- level data, not the script corpus; see 06_atmosphere.lua), and the call works. But the setting names are
-- AUTHORED PRESETS we cannot enumerate or create -- "night" is attested on exactly one region and reads as
-- late evening rather than night -- and the call is expensive enough that six in one chunk caused a
-- measured 13-second engine stall. A blanket 40-region apply would have to be paced over seconds, and would
-- still leave the gaps untouched, since a gap is the ABSENCE of a region and has nothing to configure.
--
-- Why a keeper is needed at all, and why it is not the same one the tint/brightness helpers use:
--
--   * Time is NOT a SetValue key. It has its own natives (SetTime/SetTimeSpeed) which take no part in the
--     Begin/End transaction, so the existing atmoKeeper cannot carry it.
--
--   * Crossing an atmosphere region does not simply overwrite the time -- it starts an INTERPOLATED BLEND,
--     roughly a second long, from wherever the sky currently is toward that region's own settings. Your
--     night sky is used as the blend's STARTING POINT. Measured live.
--
--   * It re-asserts on EVERY tick, deliberately, including while a blend is running. An earlier version
--     waited for Ess.Atmosphere.blending() to clear before re-applying, on the theory that fighting a blend
--     is futile. In practice that was exactly what made crossings ugly: waiting hands the engine a full
--     second of uncontested daylight and then snaps back, which reads as a jarring flash. Pinning the time
--     every 0.1s instead keeps the sky where you put it THROUGH the blend, so a crossing is barely visible.
--
--     SetTime is a direct assignment rather than a transaction, so re-asserting it costs two native calls
--     and does not itself start an interpolation -- which is what makes hammering it viable here, and what
--     makes this different from the tint/brightness keeper (those go through Begin/End and genuinely should
--     not be spammed).
--
-- WHY THIS IS A KEEPER AND NOT ChangeLineRegionSetting: reconfiguring the region itself is the obviously
-- nicer mechanism, and it does work -- but Graphics.Atmosphere.GetLineRegion() reports FORTY line regions in
-- the vz level and only SIX of them have names (the rgn_atmo_* set). The other 34 cannot be resolved by
-- Pg.GetGuidByName, so they cannot be addressed at all. Setting all six named regions to "night" was tried
-- live: the current region changed immediately, and crossing into one of the unnamed 34 reverted it. A
-- 6-of-40 solution is not a map-wide one, so the keeper stays.
--
-- Also worth knowing if you go that route anyway: the setting names are authored presets, not values you
-- control. "night" on these regions reads as late evening rather than true night, and blends in far more
-- slowly than the ~1s a normal crossing takes.
Ess.Easy.World._timeLock = Ess.Easy.World._timeLock or nil

function Ess.Easy.World.lockTimeOfDay(n)
    if type(n) ~= "number" then n = 0.95 end
    Ess.Easy.World._timeLock = n
    Ess.Atmosphere.setTimeSpeed(0)
    Ess.Atmosphere.setTime(n)
    Ess.Loop.start("Ess.World.timeKeeper", 0.1, function()
        local t = Ess.Easy.World._timeLock
        if not t then return false end                  -- unlocked -> stop the loop
        -- Re-assert EVERY tick, including mid-blend. See the note below on why waiting is worse.
        Ess.Atmosphere.setTimeSpeed(0)
        Ess.Atmosphere.setTime(t)
        return true
    end)
    return true
end

-- Ess.Easy.World.night() / .day() -- the two you actually want. 0.95 reads as night, 0.3 as daytime.
function Ess.Easy.World.night() return Ess.Easy.World.lockTimeOfDay(0.95) end
function Ess.Easy.World.day()   return Ess.Easy.World.lockTimeOfDay(0.30) end

-- Ess.Easy.World.unlockTimeOfDay(nSpeed) -- stop the keeper. Pass a speed to resume the cycle at; omit it
-- and the clock is LEFT WHERE IT IS (frozen if .freezeTime or a lock had stopped it).
--
-- ⚠ Deliberately does not "restore normal speed", because there is no way to know what normal was: the
-- namespace has SetTimeSpeed but NO GetTimeSpeed, so the original rate cannot be read back or restored once
-- changed. An earlier version defaulted to 1 on the assumption that meant normal -- it does not, it is far
-- faster (a full day in a few seconds). Guessing a rate is worse than leaving the clock alone. If you need
-- the game's authored rate back, reload the level.
function Ess.Easy.World.unlockTimeOfDay(nSpeed)
    Ess.Easy.World._timeLock = nil
    Ess.Loop.stop("Ess.World.timeKeeper")
    if type(nSpeed) == "number" then Ess.Atmosphere.setTimeSpeed(nSpeed) end
    return true
end

-- Ess.Easy.World.freezeTime() / .setTimeSpeed(n) -- stop (or rescale) the day/night cycle.
--
-- THIS ONE IS GENUINELY MAP-WIDE, and it is the reliable half of time control. Verified live with NO keeper
-- running: SetTimeSpeed(0) survives a region crossing intact, where SetTime does not.
--
-- The asymmetry is the useful thing to know, and it is not guessable:
--   * the time RATE is global state that region presets leave alone      -> freezing sticks, everywhere
--   * the time VALUE is overridden by any region's authored preset       -> forcing a time does not stick
--
-- So "stop the sky changing" is reliably achievable map-wide; "make it night everywhere" is not (see
-- lockTimeOfDay above). For most mission work -- keeping lighting stable across a scripted sequence so a
-- cutscene or a timed objective does not drift into dusk -- freezing is what you actually wanted anyway.
--
-- No restore: see the note on unlockTimeOfDay about the missing GetTimeSpeed.
function Ess.Easy.World.setTimeSpeed(n)
    if type(n) ~= "number" then return false end
    return Ess.Atmosphere.setTimeSpeed(n)
end

function Ess.Easy.World.freezeTime() return Ess.Easy.World.setTimeSpeed(0) end
