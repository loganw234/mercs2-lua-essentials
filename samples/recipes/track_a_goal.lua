-- RECIPE: track a GOAL on the HUD -- a counted objective that ticks up and fires when it's met, plus a goal
-- that completes ITSELF off a world event. The middle ground between a bare Ess.Hud.objective text line and a
-- whole Ess.Contract.
-- Namespaces: Ess.Objective, Ess.Easy.Objective, Ess.Object, Ess.Player.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- 1) a manual COUNTED goal: shows "Collect intel   N/3" and fires onComplete when it reaches the target.
--    A real mod calls goal:advance() from its own events; here we just drive it straight to done.
local done = false
local goal = Ess.Objective.new{ label = "Collect intel", target = 3,
    onComplete = function() done = true; Ess.Easy.Toast("Objective complete!") end }
goal:advance()          -- 1/3
goal:advance()          -- 2/3
goal:advance()          -- 3/3 -> completes, clears the HUD line, fires onComplete

-- 2) a goal WIRED to a world event: spawn a car and make "destroy it" the objective. It auto-completes the
--    moment the car dies, and marks the target on radar/PDA/world for you -- one line, no event glue.
local car = Ess.Object.spawnAhead("Veyron", 12)
local wired = car and Ess.Easy.Objective.destroy(car, "Destroy the car")

local ok = done and goal:isDone() and (not car or wired ~= nil)

-- tidy up after 20s (a real mod leaves the goal running until the player finishes it)
Ess.Easy.Triggers.after(20, function()
    if wired then pcall(function() wired:cancel() end) end
    if car then Ess.Object.remove(car) end
end)

Ess.Log("[recipe] track_a_goal: counted goal ran to 3/3; a 'Destroy the car' goal is up -- wreck the car to see it self-complete")
Ess.Log("[SMOKE] track_a_goal: " .. (ok and "PASS" or "FAIL"))
