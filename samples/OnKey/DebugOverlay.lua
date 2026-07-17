local KEYVAL = "f8"   -- add "DebugOverlay.lua=f8" under [OnKey] in lua_loader.ini

-- DebugOverlay.lua -- press F8 to toggle the Ess dev overlay: a live panel that follows you around showing
-- your exact world position + yaw, what you're aiming at (name/faction/distance), on-foot vs. which vehicle,
-- your health, and how many humans/vehicles are nearby. The fast way to grab a spawn or teleport position
-- while building a mod -- read it off the screen instead of logging it. Press F8 again to hide it.
--
-- DEPLOY: Ess (dist/Ess.lua) as an OnLoad script; this under scripts/OnKey/ with  DebugOverlay.lua=f8.

local Ess = _G.Ess
if not (Ess and Ess.Easy and Ess.Easy.Debug) then
    if Loader and Loader.Printf then Loader.Printf("[debugoverlay] load the Essentials framework (1_Ess.lua) first") end
    return
end

Ess.Easy.Debug.overlay()   -- toggles open / closed
