-- RECIPE: give the player a weapon and never let them run out of ammo.
-- Namespaces: Ess.Human, Ess.Player.
--
-- Ess.Easy.Human.giveWeapon(char, templateName) adds a weapon by its TEMPLATE NAME (a real weapon in the
-- game, resolved via Pg.GetGuidByName -- a bad name just no-ops, no crash). "Grenade Launcher" is a
-- confirmed one. Ess.Human has the full inventory surface (equip/drop/primaryWeapon/ammo/refill/...).

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local char = Ess.Player.character(0)
if not char then Ess.Log("[SMOKE] give_weapons: FAIL (no player character)") return end

local before = Ess.Human.allWeapons(char)
local nBefore = (type(before) == "table") and #before or 0

local added = Ess.Easy.Human.giveWeapon(char, "Grenade Launcher")   -- add a weapon by template name
Ess.Human.setInfiniteAmmo(char, true)                               -- and never run dry

local after = Ess.Human.allWeapons(char)
local nAfter = (type(after) == "table") and #after or 0

-- PASS when the operation succeeded and the player has weapons. (The count only GROWS if they didn't already
-- carry this one -- re-giving a held weapon still succeeds but leaves the count unchanged, so don't assert >.)
local ok = (added ~= false) and (nAfter >= nBefore) and (nAfter >= 1)

Ess.Log("[recipe] give_weapons: gave 'Grenade Launcher' (weapons " .. nBefore .. " -> " .. nAfter .. ") + infinite ammo")
Ess.Log("[SMOKE] give_weapons: " .. (ok and "PASS" or "FAIL"))
