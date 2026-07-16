-- RECIPE: spawn a helicopter and fly it in (AI-piloted).
-- Namespaces: Ess.Object, Ess.Vehicle, Ess.Player, Ess.Easy.Triggers.
--
-- Two gotchas this recipe bakes in: the "(Full)" template tag spawns a vehicle CREWED and already flying (a
-- bare "AH1Z" has no pilot and just drops), and moving an AI helicopter is Ess.Vehicle.flyTo (which waits for
-- the pilot to exist, then Ai.Deliver) -- NOT a plain move order, which won't fly a helicopter at all.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local px, py, pz = Ess.Player.pose(0)
if not px then Ess.Log("[SMOKE] command_a_helicopter: FAIL (no player position)") return end

local heli = Ess.Object.spawn("AH1Z (Full)", px - 20, py + 30, pz - 20)   -- crewed + airborne
if heli then
    Ess.Vehicle.flyTo(heli, px + 6, py + 7, pz + 6, { height = 6 })         -- send the AI pilot to me
end

local ok = heli ~= nil
Ess.Log("[recipe] command_a_helicopter: spawned a crewed AH1Z and sent it my way"
    .. (heli and (" (driver " .. (Ess.Vehicle.driver(heli) and "seated" or "boarding") .. ")") or ""))
Ess.Easy.Triggers.after(10, function() Ess.Object.remove(heli) end)

Ess.Log("[SMOKE] command_a_helicopter: " .. (ok and "PASS" or "FAIL"))
