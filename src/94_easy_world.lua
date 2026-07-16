-- Ess/94_easy_world.lua -- Ess.Easy.World: one-line "make the world do X" verbs for beginners. Each hides
-- the import + the namespace a newcomer would otherwise have to hunt down -- the whole point of the Easy
-- tier is that the thought "I want to remove the map boundary" becomes exactly one call you can guess.
--
-- API:
--   Ess.Easy.World.removeMapBoundary()   drop the invisible walls fencing the player into the unlocked map
--   Ess.Easy.World.clearWanted()         instantly lose all heat (clear the pursuit/wanted level)
--   Ess.Easy.World.setTimeOfDay(n)       set time of day, n = 0..1 (0.5 = noon-ish)
--   Ess.Easy.World.sky(sPreset)          switch the sky/weather preset ("afternoon", "Maracaibo", ...)
--   Ess.Easy.World.timeSpeed(n)          day/night cycle speed; 0 = freeze the sky where it is

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
    pcall(WifVzBoundary.RemoveWorldBoundary)
end

-- Ess.Easy.World.clearWanted() -- instantly drop all pursuit/wanted heat. CONFIRMED (Pg.ClearPursuitLock,
-- a global -- no import; real call sites in vz mission scripts + MrxFactionManager).
function Ess.Easy.World.clearWanted()
    pcall(Pg.ClearPursuitLock, true)
end

-- Time & sky: CONFIRMED convention (mrxbootstrap.lua) -- Graphics.Atmosphere changes are wrapped in a
-- Begin()/End() scope; this hides that so it's a real one-liner. Graphics.Atmosphere is a global namespace
-- (no import).
--   setTimeOfDay(n): n in 0..1 across the day (SetTime).      sky(preset): named sky/weather (SetSky).
--   timeSpeed(n): day/night advance rate (SetTimeSpeed); 0 freezes the current sky.
local function atmos(fn, ...)
    local a = { ... }
    pcall(function()
        Graphics.Atmosphere.Begin()
        fn(unpack(a))
        Graphics.Atmosphere.End()
    end)
end
function Ess.Easy.World.setTimeOfDay(n) atmos(Graphics.Atmosphere.SetTime, n or 0.5) end
function Ess.Easy.World.sky(sPreset)    atmos(Graphics.Atmosphere.SetSky, sPreset or "afternoon") end
function Ess.Easy.World.timeSpeed(n)    atmos(Graphics.Atmosphere.SetTimeSpeed, n or 0) end
