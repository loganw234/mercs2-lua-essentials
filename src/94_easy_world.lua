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
-- ⚠ REGION-GATED (confirmed the hard way): these modify the atmosphere of the named map region you're
-- standing IN. They work out in the real map (Maracaibo/Caracas/...), but NO-OP when you're "outside all
-- regions" -- e.g. inside the PMC HQ or on its runway apron, where you're on the bare base default
-- atmosphere with no active region object to modify. So we warn if you're not in a region. (The global
-- setters SetTime/SetSky/SetTimeSpeed are deliberately NOT used -- confirmed inert in live play.)
local ATMO_REGIONS = {
    "rgn_atmo_Maracaibo", "rgn_atmo_Caracas", "rgn_atmo_caracas", "rgn_atmo_Angelfalls", "rgn_atmo_GR",
    "rgn_atmo_GRstripmine", "rgn_atmo_PMC", "rgn_atmo_PMCinterior", "rgn_atmo_carmonaislandrain",
    "rgn_atmo_interior",
}
local function inAtmoRegion()
    local char = Ess.Player.character(0)
    if not char then return false end
    for _, name in ipairs(ATMO_REGIONS) do
        local ok, rgn = pcall(Pg.GetGuidByName, name)
        if ok and rgn then
            local oki, inside = pcall(Object.InsideBoundary, char, rgn, true)
            if oki and (inside == true or inside == 1) then return true end
        end
    end
    return false
end
local function atmosApply(fn)
    if not inAtmoRegion() then
        Ess.Log("Easy.World: atmosphere is region-gated -- you're not standing in a map atmosphere region " ..
                "(e.g. the HQ/runway), so this won't show. Head out into the map and try again.")
    end
    pcall(function()
        Graphics.Atmosphere.Begin()
        fn()
        Graphics.Atmosphere.End(0.5)
    end)
end

-- Ess.Easy.World.tint(r, g, b) -- wash the world in an ambient color (0..255 each; default deep red).
function Ess.Easy.World.tint(r, g, b)
    atmosApply(function() Graphics.Atmosphere.SetColorValue("uiAmbientColor", r or 220, g or 30, b or 30, 255) end)
end

-- Ess.Easy.World.brightness(n) -- overall light level; 0.05 ~ near-black, 1 = normal, >1 blown out.
function Ess.Easy.World.brightness(n)
    atmosApply(function() Graphics.Atmosphere.SetValue("fLightIntensity", n or 1) end)
end

-- Ess.Easy.World.hellscape() -- the confirmed dark + deep-red look, in one call.
function Ess.Easy.World.hellscape()
    atmosApply(function()
        Graphics.Atmosphere.SetValue("fLightIntensity", 0.08)
        Graphics.Atmosphere.SetColorValue("uiAmbientColor", 220, 30, 30, 255)
    end)
end

-- Ess.Easy.World.resetAtmosphere() -- undo any tint/brightness back to the region's default look.
function Ess.Easy.World.resetAtmosphere()
    pcall(Graphics.Atmosphere.Restore)
end
