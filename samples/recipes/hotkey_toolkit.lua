-- RECIPE: turn one script into a whole hotkey toolkit -- several keys, several actions.
-- Namespaces: Ess.Keys, Ess.Easy.*.
--
-- lua_loader.ini binds ONE key to launch a script. Ess.Keys lets that one script then own a whole panel of
-- hotkeys: bind as many key -> action handlers as you like, dispatched off one shared loop (edge-triggered,
-- so a held key fires once). Keys are VK numbers or names ("F6", "space", "a"). After running this, press
-- the keys in-game.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

Ess.Keys.on("F6", function() Ess.Easy.Spawn.explosion() end)                         -- F6 = a boom in front
Ess.Keys.on("F7", function() Ess.Easy.Vehicle.summon("UH1 Transport") end)           -- F7 = summon a heli
Ess.Keys.on("F8", function(shift)                                                    -- F8 = clear heat, Shift+F8 = chaos
    if shift then Ess.Easy.World.hellscape() else Ess.Easy.World.clearWanted() end
end)

local ok = Ess.Keys.isBound("F6") and Ess.Keys.isBound("F7") and Ess.Keys.isBound("F8")
Ess.Log("[recipe] hotkey_toolkit: bound F6=boom, F7=heli, F8=clear-heat (Shift+F8=hellscape)")
Ess.Log("[SMOKE] hotkey_toolkit: " .. (ok and "PASS (now press F6 / F7 / F8)" or "FAIL"))
