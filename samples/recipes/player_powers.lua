-- RECIPE: give yourself the good stuff -- the game's own unlocks, one call each.
-- Namespaces: Ess.Easy.Player.
--
-- These wrap the game's OWN cheat-menu functions (the same ones the shipped cheat menu calls), so they're
-- real, safe toggles -- not guesses. Great for a "sandbox mode" or a testing menu.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

Ess.Easy.Player.giveGrapplingHook()   -- unlock the grappling hook
Ess.Easy.Player.unlockFastTravel()    -- unlock every landing zone (fast-travel anywhere)
Ess.Easy.Player.freeSupport()         -- airstrikes / support with no stock or unlock requirements
-- also available: Ess.Easy.Player.unlockAllHQs() / .giveAllRewards() / .skin(code)

local ok = type(Ess.Easy.Player.giveGrapplingHook) == "function"
    and type(Ess.Easy.Player.unlockFastTravel) == "function"
    and type(Ess.Easy.Player.freeSupport) == "function"
Ess.Log("[recipe] player_powers: grappling hook + fast travel + free support")
Ess.Log("[SMOKE] player_powers: " .. (ok and "PASS" or "FAIL"))
