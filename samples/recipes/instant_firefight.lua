-- RECIPE: start an instant firefight, and check what the player's up to.
-- Namespaces: Ess.Easy.Spawn, Ess.Player.
--
-- One line drops a squad of hostiles in front of you and sends them at you -- the "I just want some action
-- right now" button. Plus the little state getters mods reach for: are you on foot or driving?

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- drop 4 hostiles ahead and set them on you (opts: template / count / dist / attack=false to just place them)
local squad = Ess.Easy.Spawn.enemies(4)

-- what's the player doing right now?
local where = Ess.Player.onFoot(0) and "on foot" or ("driving " .. tostring(Ess.Player.inVehicle(0)))

local ok = (#squad >= 1)
Ess.Log("[recipe] instant_firefight: spawned " .. #squad .. " hostiles and sent them at you (" .. where .. ")")
Ess.Easy.Triggers.after(15, function() for _, g in ipairs(squad) do Ess.Object.remove(g) end end)   -- tidy up

Ess.Log("[SMOKE] instant_firefight: " .. (ok and "PASS" or "FAIL"))
