-- RECIPE: a whole linear MISSION in one table -- no Contract, no manual event wiring. Each step shows on the
-- HUD objective line and (for the auto kinds) completes itself + drops its own marker. This is the light
-- middle tier: heavier than a single Ess.Objective, far lighter than a save-safe Ess.Contract.
-- Namespaces: Ess.Quest, Ess.Easy.Objective, Ess.Player, Ess.Math.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local x, y, z, yaw = Ess.Player.pose(0)
if not x then Ess.Log("[SMOKE] a_quick_mission: FAIL (no player position)") return end

-- a point ~25u ahead of you to walk to (the first step's destination)
local ax, az = Ess.Math.pointAhead(x, z, yaw or 0, 25)

-- a two-step quest: an AUTO "reach" step (completes when you arrive) then a MANUAL "return" step.
local quest = Ess.Quest.new{
    steps = {
        { reach = { ax, y, az, 8 }, label = "Advance to the marker" },   -- auto: fires on arrival
        "Return to safety",                                             -- manual: call quest:advance()
    },
    onStep = function(i, t) Ess.Log("[recipe] a_quick_mission: cleared step " .. i .. "/" .. t) end,
    onComplete = function() Ess.Easy.Toast("Mission complete!") end,
}

-- prove the sequencer works live without having to walk there: skip() force-completes the current step, which
-- should advance us from step 1 to step 2.
local i0 = select(1, quest:step())     -- 1
quest:skip()                           -- force step 1 done -> advances to step 2
local i1 = select(1, quest:step())     -- 2
local ok = (i0 == 1 and i1 == 2 and not quest:isDone())

-- tidy up after 20s (a real mod leaves the quest up until the player finishes it)
Ess.Easy.Triggers.after(20, function() pcall(function() quest:cancel() end) end)

Ess.Log("[recipe] a_quick_mission: quest advanced to step 2/2 ('Return to safety') on the HUD")
Ess.Log("[SMOKE] a_quick_mission: " .. (ok and "PASS" or "FAIL"))
