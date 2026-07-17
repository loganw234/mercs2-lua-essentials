-- RECIPE: REACT to what happens -- when something dies, when you enter an area, when you get hurt.
-- Namespaces: Ess.On, Ess.Object, Ess.Player, Ess.Easy.Triggers.
--
-- Most of Ess is imperative (you make things happen). Ess.On is the other half: hooks that fire when the
-- world does something, without wiring raw events or a contract. Each returns a stop() to cancel it.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local px, py, pz = Ess.Player.pose(0)
if not px then Ess.Log("[SMOKE] react_to_things: FAIL (no player position)") return end

local stops = {}

-- 1) when a specific object dies (a real Event.ObjectDeath hook)
local car = Ess.Object.spawnAhead("Veyron", 10)
if car then stops[#stops + 1] = Ess.On.death(car, function() Ess.Easy.Toast("The car blew up!") end) end

-- 2) the moment you walk into a zone near you (fires once)
stops[#stops + 1] = Ess.On.enterArea(px, py, pz + 15, 8, function() Ess.Easy.Toast("You entered the zone") end)

-- 3) whenever you take damage (polls the player's health dropping)
stops[#stops + 1] = Ess.On.playerHurt(function(hp, lost)
    Ess.Log("[recipe] react_to_things: took " .. lost .. " damage (hp now " .. hp .. ")")
end)

local ok = (#stops >= 2)
for _, s in ipairs(stops) do if type(s) ~= "function" then ok = false end end

-- tidy the hooks + the car after 20s (a real mod leaves them running)
Ess.Easy.Triggers.after(20, function()
    for _, s in ipairs(stops) do pcall(s) end
    if car then Ess.Object.remove(car) end
end)

Ess.Log("[recipe] react_to_things: hooked death / enterArea / playerHurt -- wreck the car, walk north, or take a hit")
Ess.Log("[SMOKE] react_to_things: " .. (ok and "PASS" or "FAIL"))
