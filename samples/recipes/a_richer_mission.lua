-- RECIPE: a mission with SCRIPTED EVENTS -- a trigger that fires support call-ins.
-- Namespaces: Ess.Contract (objectives + triggers + support).
--
-- a_simple_mission covers plain objectives + a reward. This adds the encounter toolkit on top: a named
-- `trigger` that, when it fires, sets off `support` call-ins wired to it by `trigger={ref="<id>"}`. Real
-- missions use this for "when the player reaches the depot, call in an ambush." A support/waypoint entry
-- that is only ever REFERENCED doesn't need its own id -- the first two call-ins below are deliberately
-- id-less to show that's fine.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local px, py, pz = Ess.Player.pose(0)
if not px then Ess.Log("[SMOKE] a_richer_mission: FAIL (no player position)") return end

local ambushFired = false   -- flipped by the trigger's custom call-in, to prove the wiring ran end to end

Ess.Contract.Register{
    id = "recipe_raid",
    title = "Recipe: Ambush at the Depot",
    briefing = "Wreck the supply trucks, then extract -- but expect company.",
    reward = { cash = 20000, fuel = 60 },
    objectives = {
        Ess.Contract.Destroy{ desc = "Wreck the 2 supply trucks", spawns = {
            { "Veyron", px + 18, py, pz + 6, 0 },
            { "Veyron", px + 18, py, pz - 6, 0 },
        } },
        Ess.Contract.Reach{ desc = "Reach the extraction point", at = { px, py, pz }, radius = 12 },
    },
    -- a named trigger. kind="immediate" fires it the instant the mission starts; swap to kind="proximity"
    -- (at=, radius=) for "when the player arrives", kind="onDestroy" for "when that target dies", or
    -- kind="once" (delay=) for a timer -- the support wiring below is identical regardless of WHEN it fires.
    triggers = {
        { id = "t_ambush", kind = "immediate" },
    },
    -- call-ins that fire WHEN t_ambush fires. The first two have no id (nothing references them, so they
    -- don't need one); the third is a `custom` hook we use to observe that the chain actually ran.
    support = {
        { effect = "say", text = "Ambush! Danger close!", hold = 5, trigger = { ref = "t_ambush" } },
        { effect = "vfx", at = { px + 16, py, pz }, count = 3, radius = 6, trigger = { ref = "t_ambush" } },
        { id = "note_ambush", effect = "custom", trigger = { ref = "t_ambush" },
          fn = function() ambushFired = true end },
    },
}
Ess.Contract.Accept("recipe_raid")

-- an immediate trigger fires synchronously during Accept, so the call-ins (including both id-less ones)
-- have already run by the time Accept returns -- no waiting, no race with anything else.
local st = Ess.Contract.Status()
local acceptedOk = st ~= nil and st.objectives and #st.objectives == 2
local ok = acceptedOk and ambushFired
Ess.Log("[recipe] a_richer_mission: accepted " .. (st and #st.objectives or 0)
    .. " objectives; trigger -> support call-ins fired=" .. tostring(ambushFired))
Ess.Log("[SMOKE] a_richer_mission: " .. (ok and "PASS (running -- Ess.Contract.Abort() to cancel)" or "FAIL"))
