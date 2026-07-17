-- RECIPE: react when the player gets into or out of ANY vehicle.
-- Namespaces: Ess.Object, Ess.Player, Ess.Easy.Triggers.
--
-- There's no native "entered a vehicle" event you can wildcard against an unknown vehicle -- the seat-entry
-- bind needs a specific vehicle+seat known in advance. So Ess polls `Vehicle.GetFromRider` on a heartbeat
-- and fires your callback on the nil<->guid transition. onChange(nowVeh, prevVeh): a non-nil nowVeh means
-- "just got in" (it's the vehicle guid); nil means "just got out."

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local me = Ess.Player.character(0)
if not me then Ess.Log("[SMOKE] watch_a_vehicle: FAIL (no player character)") return end

local stop = Ess.Object.pollVehicleChange(me, function(nowVeh, prevVeh)
    if nowVeh then
        Ess.Easy.Toast("Entered a vehicle")
        Ess.Log("[recipe] watch_a_vehicle: entered " .. tostring(Ess.Object.displayName(nowVeh) or nowVeh))
    else
        Ess.Easy.Toast("On foot again")
        Ess.Log("[recipe] watch_a_vehicle: exited")
    end
end, 0.4)   -- poll every 0.4s

-- a real mod keeps the watch running; the recipe stops itself after 20s so it tidies up.
Ess.Easy.Triggers.after(20, function() stop() end)

local ok = (type(stop) == "function")
Ess.Log("[recipe] watch_a_vehicle: watching for 20s -- hop in a car / bike / heli to see it fire")
Ess.Log("[SMOKE] watch_a_vehicle: " .. (ok and "PASS" or "FAIL"))
