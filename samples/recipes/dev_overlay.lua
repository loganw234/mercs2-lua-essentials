-- RECIPE: the DEV OVERLAY -- a live panel showing your exact position, what you're aiming at, on-foot/vehicle,
-- health, and how many things are nearby. Toggle it while building a mod to read a spawn/teleport position
-- straight off the screen instead of Loader.Printf-ing it. (Bind it to a key for real use -- see the
-- DebugOverlay OnKey demo.)
-- Namespaces: Ess.Easy.Debug.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

Ess.Easy.Debug.overlay()                 -- toggle it ON
local on = Ess.Easy.Debug.isOn()

-- leave it up 8s so you can see it update, then toggle it OFF (a real mod hangs it off a keybind instead)
Ess.Easy.Triggers.after(8, function() Ess.Easy.Debug.hide() end)

local ok = (on == true)
Ess.Log("[recipe] dev_overlay: overlay panel is up top-left for 8s -- your coords / aim / health / nearby")
Ess.Log("[SMOKE] dev_overlay: " .. (ok and "PASS" or "FAIL"))
