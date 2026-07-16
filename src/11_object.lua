-- Ess/11_object.lua -- Ess.Object: the everyday object-manipulation namespace. `Object.*` is the biggest
-- engine namespace (87 functions) and nearly every gameplay script touches it; this wraps the confirmed,
-- broadly-used operations with pcall-safety and one canonical name each, so a modder isn't dropping to raw
-- native calls (and hitting the invalid-guid throws) for basic "move / hurt / hide / label / launch this."
--
-- API:
--   -- transform
--   Ess.Object.pos(uGuid) -> x,y,z | nil            Ess.Object.setPos(uGuid, x,y,z)   (teleport an OBJECT)
--   Ess.Object.yaw(uGuid) -> n | nil                Ess.Object.setYaw(uGuid, n)
--   Ess.Object.distance(uGuidA, uGuidBOrX, yOrIgnoreY, z, bIgnoreY) -> n | nil   collapses
--                                        Object.GetDistanceFrom's two confirmed forms into one call
--   -- health & life
--   Ess.Object.health(uGuid) -> n | nil             Ess.Object.setHealth(uGuid, n)
--   Ess.Object.maxHealth(uGuid) -> n | nil          Ess.Object.heal(uGuid)   (set-to-GetMaxHealth)
--   Ess.Object.kill(uGuid) / .revive(uGuid, nDelay) / .remove(uGuid)
--   Ess.Object.alive(uGuid) -> bool / .valid(uGuid) -> bool
--   Ess.Object.setInvincible(uGuid, bOn, sReason)
--   -- visibility, labels, identity
--   Ess.Object.visible(uGuid) -> bool               Ess.Object.setVisible(uGuid, bOn)
--   Ess.Object.hasLabel(uGuid, s) -> bool / .addLabel(uGuid, s) / .removeLabel(uGuid, s)
--   Ess.Object.displayName(uGuid) -> s              Ess.Object.playerControlled(uGuid) -> bool
--   -- physics
--   Ess.Object.enablePhysics(uGuid) / .disablePhysics(uGuid)
--   Ess.Object.impulse(uGuid, x,y,z, bLocal)        Object.ApplyImpulse (launch/knockback)
--   -- spawn (the one create-verb -- Pg.Spawn, not Object.*, with the blank-template crash guard built in)
--   Ess.Object.spawn(sTemplate, x,y,z, yaw) -> uGuid | nil
--   -- vehicle-entry watch
--   Ess.Object.vehicleOf(uChar) -> uVehicleGuid | nil
--   Ess.Object.pollVehicleChange(uChar, onChange, interval) -> stop()

local Ess = _G.Ess
Ess.Object = Ess.Object or {}

-- engine getters sometimes return 1/0 rather than a real boolean, and 0 is TRUTHY in Lua -- coerce every
-- boolean-returning native through this so a naive `if Ess.Object.alive(g)` can't be fooled by a 0.
local function truthy(v) return v == true or v == 1 end

-- Ess.Object.vehicleOf(uChar) -> uVehicleGuid | nil
-- Unifies 4 overlapping entry points across 2 namespaces (Object.InSeat / Object.InVehicle /
-- Player.GetControlledObject / Vehicle.GetFromRider) into the one that's actually the confirmed idiom in
-- the shipped source: Vehicle.GetFromRider(char) -> vehicle guid (driver OR passenger) or nil.
function Ess.Object.vehicleOf(uChar)
    if not uChar then return nil end
    local ok, v = pcall(Vehicle.GetFromRider, uChar)
    if ok then return v end
    return nil
end

-- Ess.Object.setInvincible(uGuid, bOn, sReason)
-- sReason is REQUIRED here (the native call allows omitting it, but every real call site tags one --
-- "Survival"/"Hijack"/"HQ" -- and it's easy to forget; making it required means you can't accidentally
-- ship an untagged one that some other system can't attribute later).
function Ess.Object.setInvincible(uGuid, bOn, sReason)
    if type(sReason) ~= "string" or sReason == "" then
        Ess.Log("Object.setInvincible: sReason is required (got " .. tostring(sReason) .. ") -- using 'Ess'")
        sReason = "Ess"
    end
    local ok = pcall(Object.SetInvincible, uGuid, bOn and true or false, sReason)
    return ok and true or false
end

-- Ess.Object.pollVehicleChange(uChar, onChange, interval) -> stop()
-- Watches uChar for entering/exiting a vehicle by POLLING Vehicle.GetFromRider on a heartbeat and firing
-- onChange(uVehicleOrNil, uPrevVehicleOrNil) on the nil<->guid transition.
--
-- CONFIRMED idiom (vehicle-occupancy-inspector project): there is NO native "entered a vehicle" event for
-- an UNKNOWN target vehicle -- the seat-entry bind is native-only, and the only Lua-reachable enter event
-- (Event.ObjectInSeat) needs a specific vehicle guid + seat known IN ADVANCE, so it can't wildcard
-- "any vehicle." Poll, don't hook.
--
-- Returns a stop() function; call it to end the watch early. Built on Ess.Loop so it idles/cleans up
-- exactly like every other Ess heartbeat.
function Ess.Object.pollVehicleChange(uChar, onChange, interval)
    interval = interval or 0.5
    local id = "Ess.Object.pollVehicleChange:" .. tostring(uChar)
    local last = Ess.Object.vehicleOf(uChar)
    local stopped = false
    Ess.Loop.start(id, interval, function()
        if stopped then return false end
        local now = Ess.Object.vehicleOf(uChar)
        if now ~= last then
            local prev = last
            last = now
            local ok, err = pcall(onChange, now, prev)
            if not ok then Ess.Log("Object.pollVehicleChange onChange error: " .. tostring(err)) end
        end
        return true
    end)
    return function() stopped = true end
end

-- Ess.Object.distance(uGuidA, uGuidBOrX, yOrIgnoreY, z, bIgnoreY) -> n | nil
-- CONFIRMED (wiki/namespaces/object.md): Object.GetDistanceFrom has two real forms -- object-to-object
-- (uGuidA, uGuidB, bIgnoreY) and object-to-coordinates (uGuidA, x, y, z, bIgnoreY). Dispatches on whether
-- the 2nd argument is a number (coordinates form) or not (object form), matching Ess's own "one canonical
-- name per concept" principle -- one call instead of remembering which shape to use.
function Ess.Object.distance(uGuidA, uGuidBOrX, yOrIgnoreY, z, bIgnoreY)
    if type(uGuidBOrX) == "number" then
        local ok, n = pcall(Object.GetDistanceFrom, uGuidA, uGuidBOrX, yOrIgnoreY, z, bIgnoreY)
        return (ok and n) or nil
    end
    local ok, n = pcall(Object.GetDistanceFrom, uGuidA, uGuidBOrX, yOrIgnoreY)
    return (ok and n) or nil
end

-- Ess.Object.heal(uGuid) -- CONFIRMED "heal to full" idiom seen in real scripts:
-- Object.SetHealth(uGuid, Object.GetMaxHealth(uGuid)).
function Ess.Object.heal(uGuid)
    local ok, maxHp = pcall(Object.GetMaxHealth, uGuid)
    if ok and maxHp then pcall(Object.SetHealth, uGuid, maxHp) end
end

-- ============================================================
-- Transform (all CONFIRMED in real scripts). NOTE the guid-first convention holds for every one of these.
-- ============================================================
-- Ess.Object.pos(uGuid) -> x, y, z | nil -- Object.GetPosition, pcall'd (it throws on an invalid/dead guid).
function Ess.Object.pos(uGuid)
    local ok, x, y, z = pcall(Object.GetPosition, uGuid)
    if ok then return x, y, z end
end
-- Ess.Object.setPos(uGuid, x, y, z) -- teleport an OBJECT. CAVEAT (confirmed elsewhere in this project):
-- SetPosition is unreliable on freshly-spawned/AI HUMANS (streaming/physics can snap them back) -- for
-- moving the PLAYER use Ess.Player.teleport, and for a dynamic ghost-follow use Ess.Vehicle.followGhost.
-- It's solid for props/vehicles and for placing a just-spawned object before it streams in.
function Ess.Object.setPos(uGuid, x, y, z)
    pcall(Object.SetPosition, uGuid, x, y, z)
end
-- Ess.Object.yaw / .setYaw -- unit (deg vs rad) is unconfirmed on this engine (the wiki's own sample
-- scripts disagree); read-modify-write a yaw you got from GetYaw and it's self-consistent regardless.
function Ess.Object.yaw(uGuid)
    local ok, n = pcall(Object.GetYaw, uGuid)
    if ok then return n end
end
function Ess.Object.setYaw(uGuid, n)
    pcall(Object.SetYaw, uGuid, n)
end

-- ============================================================
-- Health & life
-- ============================================================
function Ess.Object.health(uGuid)
    local ok, n = pcall(Object.GetHealth, uGuid)
    if ok then return n end
end
function Ess.Object.setHealth(uGuid, n)
    pcall(Object.SetHealth, uGuid, n)
end
function Ess.Object.maxHealth(uGuid)
    local ok, n = pcall(Object.GetMaxHealth, uGuid)
    if ok then return n end
end
-- Ess.Object.kill / .remove -- both one-way per the Object namespace's own notes: Kill destroys (leaves a
-- corpse/wreck), Remove deletes the object outright. Kept as distinct verbs because they mean different
-- things (a killed vehicle can still be a physical wreck; a removed one is just gone).
-- CONFIRMED (this wrapper's testing): Kill is NOT instantaneous -- Ess.Object.alive(uGuid) still reads true
-- in the same tick as a kill (the death sequence has to begin first) and flips to false a moment later.
-- Poll alive() over a couple ticks rather than reading it right after kill() if you need to know it landed.
function Ess.Object.kill(uGuid)   pcall(Object.Kill, uGuid)   end
function Ess.Object.remove(uGuid) pcall(Object.Remove, uGuid) end
-- Ess.Object.revive(uGuid, nDelay) -- confirmed with an optional delay second arg (e.g. Object.Revive(u, 0.5)).
function Ess.Object.revive(uGuid, nDelay)
    if nDelay then pcall(Object.Revive, uGuid, nDelay) else pcall(Object.Revive, uGuid) end
end
function Ess.Object.alive(uGuid)
    local ok, b = pcall(Object.IsAlive, uGuid)
    return ok and truthy(b)
end
function Ess.Object.valid(uGuid)
    local ok, b = pcall(Object.IsValid, uGuid)
    return ok and truthy(b)
end

-- ============================================================
-- Visibility, labels, identity
-- ============================================================
-- Ess.Object.visible / .setVisible -- Object.IsVisible IS a real boolean-returning native here (distinct
-- from the FlashWidget GetVisible footgun over in Ess.Gfx -- different namespace, different call).
function Ess.Object.visible(uGuid)
    local ok, b = pcall(Object.IsVisible, uGuid)
    return ok and truthy(b)
end
function Ess.Object.setVisible(uGuid, bOn)
    pcall(Object.SetVisible, uGuid, bOn and true or false)
end
-- Labels: a free-form string tag the engine and other scripts read (e.g. "PMC", "Disposable", "garage").
function Ess.Object.hasLabel(uGuid, sLabel)
    local ok, b = pcall(Object.HasLabel, uGuid, sLabel)
    return ok and truthy(b)
end
function Ess.Object.addLabel(uGuid, sLabel)    pcall(Object.AddLabel, uGuid, sLabel)    end
function Ess.Object.removeLabel(uGuid, sLabel) pcall(Object.RemoveLabel, uGuid, sLabel) end
-- Ess.Object.displayName(uGuid) -> localized, human-readable name for HUD/labels (Object.GetLocalizedName).
-- Distinct from Ess.Name(guid), which is the guid's HASH string (Sys.GuidToString) -- different concept.
function Ess.Object.displayName(uGuid)
    local ok, s = pcall(Object.GetLocalizedName, uGuid)
    if ok and type(s) == "string" then return s end
end
-- Ess.Object.playerControlled(uGuid) -> bool -- LIVE DISCOVERY (this wrapper's testing): despite the wiki
-- signature claiming a boolean, Object.IsPlayerControlled actually returns the CONTROLLING PLAYER'S GUID
-- (a userdata) when the object is player-controlled, and a falsy value otherwise -- so a plain truthy()
-- check would wrongly report the real player as NOT controlled (a guid isn't == true or == 1). Coerce
-- "returned a real value" -> true instead.
function Ess.Object.playerControlled(uGuid)
    local ok, v = pcall(Object.IsPlayerControlled, uGuid)
    return ok and v ~= nil and v ~= false and v ~= 0
end

-- ============================================================
-- Physics
-- ============================================================
function Ess.Object.enablePhysics(uGuid)  pcall(Object.EnablePhysics, uGuid)  end
function Ess.Object.disablePhysics(uGuid) pcall(Object.DisablePhysics, uGuid) end
-- Ess.Object.impulse(uGuid, x, y, z, bLocal) -- Object.ApplyImpulse, the confirmed "launch/knock something
-- around" primitive (real call sites scale the impulse by the object's mass, e.g.
-- Object.ApplyImpulse(u, 0, 10000, 6 * mass, true) -- so heavier things need a bigger push). bLocal defaults
-- true (impulse in the object's own space) to match the confirmed call sites.
function Ess.Object.impulse(uGuid, x, y, z, bLocal)
    if bLocal == nil then bLocal = true end
    pcall(Object.ApplyImpulse, uGuid, x or 0, y or 0, z or 0, bLocal and true or false)
end

-- ============================================================
-- Spawn -- the one CREATE verb. Spawning is Pg.Spawn (not Object.*), but a spawned thing IS an object you
-- then drive with everything above, so it lives here. Carries the confirmed blank-template crash guard: a
-- blank/whitespace template string hard-CRASHES the engine and pcall canNOT catch a native crash, so it's
-- validated BEFORE the call, not relied on pcall to make safe.
-- ============================================================
function Ess.Object.spawn(sTemplate, x, y, z, yaw)
    if type(sTemplate) ~= "string" or sTemplate:match("^%s*$") then
        Ess.Log("Object.spawn: blank/invalid template refused (a blank Pg.Spawn hard-crashes the engine)")
        return nil
    end
    local ok, u = pcall(Pg.Spawn, sTemplate, x, y, z)
    if not ok or not u then
        Ess.Log("Object.spawn: Pg.Spawn failed for '" .. sTemplate .. "'")
        return nil
    end
    if yaw then pcall(Object.SetYaw, u, yaw) end
    return u
end
