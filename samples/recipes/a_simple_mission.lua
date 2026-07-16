-- RECIPE: author a whole custom mission -- objectives, a briefing, a cash/fuel reward -- and start it.
-- Namespaces: Ess.Contract.
--
-- A contract is an EPHEMERAL mission: it's built from safe primitives and never touches the game save (so
-- it can't corrupt one; it just re-offers on the next load). Register a def, then Accept it. There are 16
-- objective builders (Destroy/Reach/Defend/Escort/Hold/Survive/Extract/Race/...); this uses two.
--
-- NOTE: this leaves a LIVE mission running for you to actually play (wreck the two cars, then walk to the
-- start point). Call Ess.Contract.Abort() to cancel it. A real mission would also place you with def.start
-- and could open with an intro def.cinematic.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local px, py, pz = Ess.Player.pose(0)
if not px then Ess.Log("[SMOKE] a_simple_mission: FAIL (no player position)") return end

Ess.Contract.Register{
    id = "recipe_mission",
    title = "Recipe: Clear the Yard",
    briefing = "Wreck the two cars, then reach the extraction point.",
    reward = { cash = 5000, fuel = 50 },
    objectives = {
        -- Destroy spawns its own targets (template, x, y, z, yaw) and completes when they're all wrecked.
        Ess.Contract.Destroy{ desc = "Destroy the 2 cars", spawns = {
            { "Veyron", px + 16, py, pz + 5, 0 },
            { "Veyron", px + 16, py, pz - 5, 0 },
        } },
        -- Reach completes when a hero enters the radius of a point.
        Ess.Contract.Reach{ desc = "Reach the extraction point", at = { px, py, pz }, radius = 12 },
    },
    onComplete = function() Ess.Log("[recipe] a_simple_mission: contract COMPLETE, reward paid") end,
}
Ess.Contract.Accept("recipe_mission")

-- confirm the engine accepted it and it's running with our two objectives live (Ess.Contract.Status is the
-- same shape a HUD board reads). Completion needs you to actually play it, so the smoke check is "it started".
local st = Ess.Contract.Status()
local ok = st ~= nil and st.objectives and #st.objectives == 2
Ess.Log("[recipe] a_simple_mission: accepted; " .. (st and #st.objectives or 0) .. " objectives live")
Ess.Log("[SMOKE] a_simple_mission: " .. (ok and "PASS (mission running -- Ess.Contract.Abort() to cancel)" or "FAIL"))
