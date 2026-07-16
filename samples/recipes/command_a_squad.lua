-- RECIPE: spawn a squad and command it. Group your units, then order the whole group at once.
-- Namespaces: Ess.Object, Ess.AIOrders, Ess.Player, Ess.Easy.Triggers.
--
-- The pattern: collect the guids you spawn into a list, then Ess.AIOrders.command(guids, behavior, opts).
-- Behaviors: move / patrol / defend / attack / hold / face / follow / flee / enter / deploy / animate.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local px, py, pz = Ess.Player.pose(0)
if not px then Ess.Log("[SMOKE] command_a_squad: FAIL (no player position)") return end

-- spawn a 3-man squad off to the side, collecting each guid
local squad = {}
for i = 1, 3 do
    local g = Ess.Object.spawn("VZ Soldier", px + 12, py, pz + 6 + i * 2)
    if g then squad[#squad + 1] = g end
end

-- order the whole group to move to a point. opts carries at={x,y,z} / points={...} / radius / speed / target
-- depending on the behavior. (Ess.Easy.AIOrders.attack/patrol/guard are one-call shortcuts for the common ones.)
Ess.AIOrders.command(squad, "move", { at = { x = px, y = py, z = pz } })

local ok = #squad == 3
Ess.Log("[recipe] command_a_squad: spawned " .. #squad .. " soldier(s) and ordered them to move to me")
Ess.Easy.Triggers.after(8, function() for _, g in ipairs(squad) do Ess.Object.remove(g) end end)   -- tidy up

Ess.Log("[SMOKE] command_a_squad: " .. (ok and "PASS" or "FAIL"))
