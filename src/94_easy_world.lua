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
-- restores the natural look. (The global setters SetTime/SetSky/SetTimeSpeed are deliberately NOT used --
-- confirmed inert in live play; these use the confirmed SetValue/SetColorValue interface.)
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
    local ok, cur = pcall(Graphics.Atmosphere.GetCurrentSetting)
    Ess.Easy.World._atmoTag = ok and tostring(cur) or nil
    Ess.Loop.start("Ess.World.atmoKeeper", 0.2, function()
        local f = Ess.Easy.World._atmo
        if not f then return false end               -- cleared by resetAtmosphere -> stop
        local ok2, c2 = pcall(Graphics.Atmosphere.GetCurrentSetting)
        local tag = ok2 and tostring(c2) or nil
        if tag ~= Ess.Easy.World._atmoTag then        -- zone swapped the atmosphere -> snap our look back
            rawApply(f, 0)
            local ok3, c3 = pcall(Graphics.Atmosphere.GetCurrentSetting)
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
    pcall(Graphics.Atmosphere.Restore)
end
