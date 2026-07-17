-- RECIPE: call in an airstrike / artillery / gunship run -- the iconic Mercs2 support, no contract needed.
-- Namespaces: Ess.Support, Ess.Easy.Airstrike, Ess.Player.
--
-- Ess.Support lifts the combat call-ins out of the mission system so you can fire one anywhere in a line.
-- Everything's a world position; `owner` (a faction name) tags who fired it so kills attribute correctly.
-- This fires a barrage a safe distance AWAY so it doesn't land on you.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local px, py, pz = Ess.Player.pose(0)
if not px then Ess.Log("[SMOKE] call_in_support: FAIL (no player position)") return end

local tx, ty, tz = px + 45, py, pz + 45          -- target a spot well clear of you

Ess.Support.airstrike(tx, ty, tz)                                             -- a gunship streaks over
Ess.Support.artillery(tx, ty, tz, { count = 6, radius = 12, owner = "China" }) -- shells rain, attributed to China
Ess.Support.gunship(tx, ty, tz, { count = 2 })                                 -- a couple of helicopters pass
-- and the one-tap presets:
--   Ess.Easy.Airstrike.onTarget()   -- barrage whatever your reticle is on
--   Ess.Support.reinforce(tx, ty, tz, { faction = "VZ", units = { "Veyron" }, deliver = "copter" })  -- a drop-in

local ok = type(Ess.Support.artillery) == "function" and type(Ess.Easy.Airstrike.at) == "function"
Ess.Log("[recipe] call_in_support: airstrike + artillery(6) + 2 gunships called in 45u away")
Ess.Log("[SMOKE] call_in_support: " .. (ok and "PASS" or "FAIL"))
