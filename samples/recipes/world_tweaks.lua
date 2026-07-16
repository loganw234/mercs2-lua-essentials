-- RECIPE: tweak the world -- lose your wanted level, roam past the map walls, recolour the sky.
-- Namespaces: Ess.Easy.World.
--
-- These are the "sandbox play" one-liners. Note: the atmosphere tints (tint/brightness/hellscape) are
-- REGION-GATED -- they only visibly do anything while you're standing in a real named map region, not at
-- the HQ. The calls are safe anywhere; they just no-op at the base.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

Ess.Easy.World.clearWanted()          -- drop all police / military heat
Ess.Easy.World.removeMapBoundary()    -- lift the invisible out-of-bounds walls (roam the whole map)
Ess.Easy.World.tint(120, 60, 200)     -- a purple cast over the world (region-gated)

Ess.Easy.Triggers.after(4, function() Ess.Easy.World.resetAtmosphere() end)   -- put the sky back after a bit

local ok = type(Ess.Easy.World.clearWanted) == "function"
    and type(Ess.Easy.World.removeMapBoundary) == "function"
    and type(Ess.Easy.World.tint) == "function"
Ess.Log("[recipe] world_tweaks: cleared heat, lifted the map walls, tinted the sky")
Ess.Log("[SMOKE] world_tweaks: " .. (ok and "PASS" or "FAIL"))
