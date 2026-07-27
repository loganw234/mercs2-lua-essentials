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
--   -- mutators
--   Ess.Human.setState(uChar, sPosture, sAnim) -> bool   Upright|InVehicle|Subdued|Cower + "Idle"/clip
--                                                        NO feedback on a bad state -- see impl note
--   Ess.Human.setFireLock(uChar, b) -> bool         stop firing without disarming
--   Ess.Human.setJostle(uChar, b) -> bool           stop crowds shoving a placed NPC
--   Ess.Human.allowCorpseCleanup(uChar, b) -> bool  keep a body for a scene
--   Ess.Human.preemptiveRagdoll(uChar) -> bool      ragdoll BEFORE the cause (hijack idiom)
--   Ess.Human.persistTransform(uChar) -> bool
--   Ess.Human.drop(uChar) -> bool                   false = nothing was carried (meaningful)
--   Ess.Human.stopGrappling(uChar) -> bool
--   Ess.Human.forceExitSeat(uChar) -> bool          abrupt eject, no animation
--   Ess.Human.carrying(uChar) -> bool             hauling a body/crate (blocks climb, swim, most weapons)
--   Ess.Human.grappling(uChar) -> bool            mid-grapple (hijack/takedown melee)
--   Ess.Human.swimming(uChar) -> bool             in deep water
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
    return Ess.Safe.quiet(Human.Inventory.EquipWeapon, uChar, uWeapon) and true or false
end

function Ess.Human.dropWeapon(uChar, uWeapon)
    return Ess.Safe.quiet(Human.Inventory.DropWeapon, uChar, uWeapon) and true or false
end

function Ess.Human.primaryWeapon(uChar)
    local ok, w = Ess.Safe.quiet(Human.Inventory.GetPrimaryWeapon, uChar)
    return (ok and w) or nil
end

function Ess.Human.secondaryWeapon(uChar)
    local ok, w = Ess.Safe.quiet(Human.Inventory.GetSecondaryWeapon, uChar)
    return (ok and w) or nil
end

function Ess.Human.allWeapons(uChar)
    local ok, t = Ess.Safe.quiet(Human.Inventory.GetAllWeapons, uChar)
    if ok and type(t) == "table" then return t end
    return {}
end

function Ess.Human.setAllWeapons(uChar, tWeaponGuids)
    return Ess.Safe.quiet(Human.Inventory.SetAllWeapons, uChar, tWeaponGuids) and true or false
end

function Ess.Human.reloadAll(uChar)
    Ess.Safe.quiet(Human.Inventory.ReloadAll, uChar, false)
end

function Ess.Human.doAction(uChar, sActionName)
    if type(sActionName) ~= "string" or sActionName == "" then return end
    Ess.Safe.quiet(Human.DoAction, uChar, sActionName)
end

function Ess.Human.disableWeapons(uChar) Ess.Safe.quiet(Human.DisableWeapons, uChar) end
function Ess.Human.enableWeapons(uChar)  Ess.Safe.quiet(Human.EnableWeapons, uChar) end

function Ess.Human.knockdown(uChar, nDuration)
    Ess.Safe.quiet(Human.Knockdown, uChar, nDuration or 0.5)
end

-- ---- ammo (Weapon namespace -- operates on the weapon guids Ess.Human's own getters return) ----
function Ess.Human.ammo(uWeapon)
    local ok, n = Ess.Safe.quiet(Weapon.GetReserveAmmo, uWeapon)
    return (ok and n) or 0
end

function Ess.Human.setAmmo(uWeapon, n)
    Ess.Safe.quiet(Weapon.SetReserveAmmo, uWeapon, n)
end

function Ess.Human.maxAmmo(uWeapon)
    local ok, n = Ess.Safe.quiet(Weapon.GetMaxReserveAmmo, uWeapon)
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
    Ess.Safe.quiet(Object.SetInfiniteAmmo, uChar, bOn and true or false)
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
    local ok, uWeapon = Ess.Safe.quiet(Pg.GetGuidByName, sTemplateName)
    if not ok or not uWeapon then
        Ess.Log("Easy.Human.giveWeapon: no weapon template named '" .. tostring(sTemplateName) .. "'")
        return false
    end
    return Ess.Human.equipWeapon(uChar, uWeapon)
end

-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Character STATE queries. Live-probed 2026-07-26; all three return real booleans (no nil-for-false trap,
-- unlike Vehicle.IsFlying / Object.IsWinched).
-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────

-- Ess.Human.carrying(uChar) -> bool -- is this character hauling something (a body, a crate)? The state
-- that blocks climbing, swimming and most weapon use, so it's usually the reason an action "silently
-- doesn't work" on an NPC.
function Ess.Human.carrying(uChar)
    if not uChar then return false end
    local ok, b = Ess.Safe.quiet(Human.IsCarrying, uChar)
    return (ok and b) and true or false
end

-- Ess.Human.grappling(uChar) -> bool -- mid-grapple (the hijack/takedown melee state).
function Ess.Human.grappling(uChar)
    if not uChar then return false end
    local ok, b = Ess.Safe.quiet(Human.IsGrappling, uChar)
    return (ok and b) and true or false
end

-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────
-- MUTATORS. Live-verified 2026-07-26 against a spawned throwaway NPC rather than the player, since a bad
-- posture can leave a character stuck.
-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────

-- Ess.Human.setState(uChar, sPosture, sAnim) -> bool -- the character state machine. 45 call sites in the
-- shipped scripts, the most-used mutator in this namespace.
--
-- Vocabulary, harvested from every corpus call site (there is no way to enumerate it at runtime):
--   sPosture : "Upright" | "InVehicle" | "Subdued" | "Cower"
--   sAnim    : "Idle", or a named animation clip
--              (e.g. "lifestylejobPlayerArmwrestlingWinningloop01")
-- "Upright","Idle" is by far the most common pairing -- it is the shipped idiom for "return this character
-- to normal", e.g. after a cutscene or a Cower.
--
-- ⚠ NO FEEDBACK WHATSOEVER. The native returns nil for a valid state AND for a garbage one -- verified by
-- passing "NotAReal","State", which is indistinguishable from success. So this wrapper's `true` means the
-- call did not throw, NOT that the state was applied. Misspell a posture and it fails silently forever.
--
-- Which is why the posture is CHECKED AGAINST A WHITELIST here. Ess normally passes strings through and
-- lets the engine judge them -- but this engine call cannot judge, so a guard in the wrapper is the only
-- point in the whole chain where a typo can ever be caught. POSTURES is exported so a caller can offer the
-- four rather than retype them; the ANIMATION name is still passed through, since clip names are open-ended
-- and there is no list to check against.
Ess.Human.POSTURES = { "Upright", "InVehicle", "Subdued", "Cower" }
local POSTURE_OK = {}
for _, s in ipairs(Ess.Human.POSTURES) do POSTURE_OK[s] = true end

function Ess.Human.setState(uChar, sPosture, sAnim)
    if not uChar or type(sPosture) ~= "string" then return false end
    if not POSTURE_OK[sPosture] then
        Ess.Safe.reject("Ess.Human.setState", "'" .. sPosture .. "' is not a known posture -- expected "
                        .. table.concat(Ess.Human.POSTURES, ", ")
                        .. " (the native reports nothing either way, so this guard is the only signal)")
        return false
    end
    local ok = Ess.Safe.quiet(Human.SetState, uChar, sPosture, sAnim or "Idle")
    return ok and true or false
end

-- Ess.Human.setFireLock(uChar, bLocked) -> bool -- stop a character firing without disarming them.
-- Distinct from .disableWeapons(), which takes the weapon away entirely.
function Ess.Human.setFireLock(uChar, bLocked)
    if not uChar then return false end
    local ok, r = Ess.Safe.quiet(Human.SetFireLock, uChar, bLocked and true or false)
    return (ok and r ~= false) and true or false
end

-- Ess.Human.setJostle(uChar, bEnabled) -> bool -- whether this character gets shoved by others walking into
-- them. Turning it off is the usual fix for an NPC placed for a scene drifting out of position in a crowd.
function Ess.Human.setJostle(uChar, bEnabled)
    if not uChar then return false end
    local ok = Ess.Safe.quiet(Human.SetJostleEnabled, uChar, bEnabled and true or false)
    return ok and true or false
end

-- Ess.Human.allowCorpseCleanup(uChar, bAllow) -> bool -- whether the engine may despawn this body. Pass
-- false to keep a corpse around for a scripted scene; the streaming system otherwise reclaims it.
function Ess.Human.allowCorpseCleanup(uChar, bAllow)
    if not uChar then return false end
    local ok, r = Ess.Safe.quiet(Human.SetAllowCorpseCleanup, uChar, bAllow and true or false)
    return (ok and r ~= false) and true or false
end

-- Ess.Human.preemptiveRagdoll(uChar) -> bool -- switch to ragdoll BEFORE the thing that would cause it,
-- which is how the shipped hijack code makes a takedown look right rather than snapping.
function Ess.Human.preemptiveRagdoll(uChar)
    if not uChar then return false end
    local ok = Ess.Safe.quiet(Human.SetPreemptiveRagdoll, uChar)
    return ok and true or false
end

-- Ess.Human.persistTransform(uChar) -> bool -- pin the character's current position/orientation so the
-- engine stops re-deriving it. Used in the corpus around seat exits and scripted placement.
function Ess.Human.persistTransform(uChar)
    if not uChar then return false end
    local ok, r = Ess.Safe.quiet(Human.PersistTransform, uChar)
    return (ok and r ~= false) and true or false
end

-- Ess.Human.drop(uChar) -> bool -- drop whatever is being carried. The return is MEANINGFUL: false means
-- there was nothing to drop (verified on an NPC carrying nothing), so this doubles as a "did I actually
-- drop something" check. Pairs with .carrying().
function Ess.Human.drop(uChar)
    if not uChar then return false end
    local ok, r = Ess.Safe.quiet(Human.Drop, uChar)
    return (ok and r ~= false) and true or false
end

-- Ess.Human.stopGrappling(uChar) -> bool -- break out of a grapple. Pairs with .grappling().
function Ess.Human.stopGrappling(uChar)
    if not uChar then return false end
    local ok = Ess.Safe.quiet(Human.StopGrappling, uChar)
    return ok and true or false
end

-- Ess.Human.forceExitSeat(uChar) -> bool -- eject a character from a vehicle seat with NO exit animation
-- and no reposition ("NoSnap"). Abrupt by design; Ess.Vehicle.exit() is the graceful form. The right tool
-- when the vehicle is about to be removed and a normal exit would leave the character mid-animation.
function Ess.Human.forceExitSeat(uChar)
    if not uChar then return false end
    local ok = Ess.Safe.quiet(Human.ForceExitSeatNoSnap, uChar)
    return ok and true or false
end

-- Ess.Human.swimming(uChar) -> bool -- in deep water and actually swimming.
--
-- Shipped game scripts call this as `Human.IsSwimming and Human.IsSwimming(uChar)` -- Pandemic's own code
-- guards against the binding being absent, which suggests it isn't present in every build. It IS present
-- here (live-confirmed), and Ess.Safe.quiet makes the guard moot either way: a missing binding comes back
-- false rather than throwing.
function Ess.Human.swimming(uChar)
    if not uChar then return false end
    local ok, b = Ess.Safe.quiet(Human.IsSwimming, uChar)
    return (ok and b) and true or false
end
