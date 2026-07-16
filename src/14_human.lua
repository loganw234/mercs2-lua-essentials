-- Ess/14_human.lua -- Ess.Human: weapon/inventory control and action/animation playback for a character
-- guid, wrapping the `Human` engine namespace (+ the small `Weapon` namespace for ammo, since it operates
-- on the weapon guids Ess.Human's own getters return -- one home instead of a third tiny namespace).
--
-- API:
--   Ess.Human.equipWeapon(uChar, uWeapon)        Human.Inventory.EquipWeapon -- the confirmed-working
--                                                 form; the top-level Human.EquipWeapon has zero real call
--                                                 sites anywhere in the decompiled corpus, so this
--                                                 deliberately does NOT expose that one.
--   Ess.Human.dropWeapon(uChar, uWeapon)         Human.Inventory.DropWeapon
--   Ess.Human.primaryWeapon(uChar) -> uGuid|nil   Human.Inventory.GetPrimaryWeapon
--   Ess.Human.secondaryWeapon(uChar) -> uGuid|nil Human.Inventory.GetSecondaryWeapon
--   Ess.Human.allWeapons(uChar) -> { uGuid, ... }  Human.Inventory.GetAllWeapons (never nil, empty table)
--   Ess.Human.setAllWeapons(uChar, tWeaponGuids)  Human.Inventory.SetAllWeapons
--   Ess.Human.reloadAll(uChar)                    Human.Inventory.ReloadAll(uChar, false)
--   Ess.Human.doAction(uChar, sActionName)        Human.DoAction -- e.g. "Cower"/"Stand"/"Proximity"
--   Ess.Human.disableWeapons(uChar) / .enableWeapons(uChar)
--   Ess.Human.knockdown(uChar, nDuration)
--   Ess.Human.ammo(uWeapon) -> n                  Weapon.GetReserveAmmo
--   Ess.Human.setAmmo(uWeapon, n)                 Weapon.SetReserveAmmo
--   Ess.Human.maxAmmo(uWeapon) -> n                Weapon.GetMaxReserveAmmo
--   Ess.Human.refillAmmo(uWeapon)                  the confirmed "set to GetMaxReserveAmmo" one-liner,
--                                                   independently duplicated across pmccon001.lua/vzacon001.lua
--   Ess.Human.setInfiniteAmmo(uChar, bOn)          Object.SetInfiniteAmmo -- maxes reserve ammo forever
--   Ess.Easy.Human.giveWeapon(uChar, sTemplateName) -> ok    spawn-free "just give them a gun by name"

local Ess = _G.Ess
Ess.Human = Ess.Human or {}

function Ess.Human.equipWeapon(uChar, uWeapon)
    return pcall(Human.Inventory.EquipWeapon, uChar, uWeapon) and true or false
end

function Ess.Human.dropWeapon(uChar, uWeapon)
    return pcall(Human.Inventory.DropWeapon, uChar, uWeapon) and true or false
end

function Ess.Human.primaryWeapon(uChar)
    local ok, w = pcall(Human.Inventory.GetPrimaryWeapon, uChar)
    return (ok and w) or nil
end

function Ess.Human.secondaryWeapon(uChar)
    local ok, w = pcall(Human.Inventory.GetSecondaryWeapon, uChar)
    return (ok and w) or nil
end

function Ess.Human.allWeapons(uChar)
    local ok, t = pcall(Human.Inventory.GetAllWeapons, uChar)
    if ok and type(t) == "table" then return t end
    return {}
end

function Ess.Human.setAllWeapons(uChar, tWeaponGuids)
    return pcall(Human.Inventory.SetAllWeapons, uChar, tWeaponGuids) and true or false
end

function Ess.Human.reloadAll(uChar)
    pcall(Human.Inventory.ReloadAll, uChar, false)
end

function Ess.Human.doAction(uChar, sActionName)
    if type(sActionName) ~= "string" or sActionName == "" then return end
    pcall(Human.DoAction, uChar, sActionName)
end

function Ess.Human.disableWeapons(uChar) pcall(Human.DisableWeapons, uChar) end
function Ess.Human.enableWeapons(uChar)  pcall(Human.EnableWeapons, uChar) end

function Ess.Human.knockdown(uChar, nDuration)
    pcall(Human.Knockdown, uChar, nDuration or 0.5)
end

-- ---- ammo (Weapon namespace -- operates on the weapon guids Ess.Human's own getters return) ----
function Ess.Human.ammo(uWeapon)
    local ok, n = pcall(Weapon.GetReserveAmmo, uWeapon)
    return (ok and n) or 0
end

function Ess.Human.setAmmo(uWeapon, n)
    pcall(Weapon.SetReserveAmmo, uWeapon, n)
end

function Ess.Human.maxAmmo(uWeapon)
    local ok, n = pcall(Weapon.GetMaxReserveAmmo, uWeapon)
    return (ok and n) or 0
end

-- Ess.Human.refillAmmo(uWeapon) -- CONFIRMED pattern, identical across pmccon001.lua/vzacon001.lua:
-- Weapon.SetReserveAmmo(w, Weapon.GetMaxReserveAmmo(w)).
function Ess.Human.refillAmmo(uWeapon)
    Ess.Human.setAmmo(uWeapon, Ess.Human.maxAmmo(uWeapon))
end

-- Ess.Human.setInfiniteAmmo(uChar, bOn) -- CONFIRMED live-tested (wiki/snippets.md): Object.SetInfiniteAmmo
-- keeps RESERVE ammo maxed forever; the magazine currently being fired still empties normally and still
-- needs a reload (grenades: infinite reserve, still thrown one at a time). Note this is on the Object
-- namespace (a character guid), not Human/Weapon -- kept in this file anyway since it's still squarely a
-- "character ammo" concern, matching Ess.Human's own existing habit of folding in the small Weapon
-- namespace for the same reason.
function Ess.Human.setInfiniteAmmo(uChar, bOn)
    pcall(Object.SetInfiniteAmmo, uChar, bOn and true or false)
end

-- Ess.Easy.Human.giveWeapon(uChar, sTemplateName) -> ok
-- LIVE-CONFIRMED this session: Pg.GetGuidByName(sTemplateName) resolves a weapon TEMPLATE name (e.g.
-- "Grenade Launcher") to a real guid distinct from any weapon the character already carries, and
-- Human.Inventory.EquipWeapon on THAT guid genuinely adds a new weapon (verified via an exact
-- before/after GetAllWeapons count change, 2 -> 3) -- not just re-equipping something already held, which
-- is all the confirmed real call sites (mrxshootinggallery.lua) happen to show. No blank-template guard
-- needed here the way Pg.Spawn needs one -- GetGuidByName on an empty/bad name just returns nil/false,
-- it doesn't hard-crash the engine the way an empty Pg.Spawn does.
Ess.Easy = Ess.Easy or {}
Ess.Easy.Human = Ess.Easy.Human or {}
function Ess.Easy.Human.giveWeapon(uChar, sTemplateName)
    if type(sTemplateName) ~= "string" or sTemplateName == "" then return false end
    local ok, uWeapon = pcall(Pg.GetGuidByName, sTemplateName)
    if not ok or not uWeapon then
        Ess.Log("Easy.Human.giveWeapon: no weapon template named '" .. tostring(sTemplateName) .. "'")
        return false
    end
    return Ess.Human.equipWeapon(uChar, uWeapon)
end
