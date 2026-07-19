-- Ess/11_object.lua -- Ess.Object: the everyday object-manipulation namespace. `Object.*` is the biggest
-- engine namespace (87 functions) and nearly every gameplay script touches it; this wraps the confirmed,
-- broadly-used operations with pcall-safety and one canonical name each, so a modder isn't dropping to raw
-- native calls (and hitting the invalid-guid throws) for basic "move / hurt / hide / label / launch this."
--
-- API:
--   -- transform
--   Ess.Object.pos(uGuid) -> x,y,z | nil            Ess.Object.setPos(uGuid, x,y,z)   (teleport an OBJECT)
--   Ess.Object.yaw(uGuid) -> n | nil                Ess.Object.setYaw(uGuid, n)
--   Ess.Object.faceToward(uGuid, x,y,z)             Ess.Object.faceObject(uGuid, uTarget)  (turn to face)
--   Ess.Object.distance(uGuidA, uGuidBOrX, yOrIgnoreY, z, bIgnoreY) -> n | nil   collapses
--                                        Object.GetDistanceFrom's two confirmed forms into one call
--   -- health & life
--   Ess.Object.health(uGuid) -> n | nil             Ess.Object.setHealth(uGuid, n)
--   Ess.Object.maxHealth(uGuid) -> n | nil          Ess.Object.heal(uGuid)   (set-to-GetMaxHealth)
--   Ess.Object.damage(uGuid, nAmount) -> nNewHealth | nil   deal damage (kills if it would drop <= 0)
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
--   Ess.Object.spawnAhead(sTemplate, nDist, nHeight, i) -> uGuid | nil   spawn in front of the player
--                                        (hides the yaw->sin/cos "in front of me" trig a beginner won't know)
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

-- Ess.Object.faceToward(uGuid, x, y, z) -- turn the object to face a world point (ground-plane yaw; the y
-- arg is accepted for call convenience but not used). Uses Ess.Math.angleTo so the yaw convention matches
-- the engine's own. The everyday "make this NPC/prop look at that spot" for a cutscene or a scripted stance.
function Ess.Object.faceToward(uGuid, x, y, z)
    local px, _, pz = Ess.Object.pos(uGuid)
    if not px or x == nil then return end
    pcall(Object.SetYaw, uGuid, Ess.Math.angleTo(px, pz, x, z))
end

-- Ess.Object.faceObject(uGuid, uTarget) -- same, but face another object's CURRENT position.
function Ess.Object.faceObject(uGuid, uTarget)
    local tx, ty, tz = Ess.Object.pos(uTarget)
    if tx then Ess.Object.faceToward(uGuid, tx, ty, tz) end
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
-- Ess.Object.damage(uGuid, nAmount) -> nNewHealth | nil -- deal nAmount of damage. There is NO native
-- "damage" call on this engine (only GetHealth/SetHealth/Kill), so this reads current health, subtracts,
-- and applies -- and if the result would be <= 0 it Kill()s outright, since SetHealth(uGuid, 0) does NOT
-- reliably register as death here. Returns the new health (0 if it killed), or nil if health couldn't be
-- read. The natural complement to .heal (full up) and .setHealth (set exactly).
function Ess.Object.damage(uGuid, nAmount)
    local ok, hp = pcall(Object.GetHealth, uGuid)
    if not ok or not hp then return nil end
    local nw = hp - (nAmount or 0)
    if nw <= 0 then pcall(Object.Kill, uGuid); return 0 end
    pcall(Object.SetHealth, uGuid, nw)
    return nw
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
-- true (impulse in the object's own space) to match the confirmed call sites. This is the bare call; for the
-- mass-scaling + directional + speedBoost/launch/knockback helpers see the Ess.Impulse system (16_impulse.lua).
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

-- Ess.Object.spawnAhead(sTemplate, nDist, nHeight, i) -> uGuid | nil
-- Spawn sTemplate nDist units IN FRONT of player i (default local), nHeight units up, facing the same way
-- the player is. This hides the forward-projection trig (the yaw -> sin/cos math EVERY "spawn in front of
-- me" needs and that a beginner has no way to know) behind one call -- the confirmed projection is uilib's
-- own ctx:spawn recipe. nDist default 18, nHeight default 0 (bump it up for aircraft / a midair drop).
--
-- ⚠ "in front of" means in front of the character's BODY (Object.GetYaw = chest orientation), NOT in front
-- of where the player is LOOKING -- standing still and swinging the mouse turns the view but not the body.
-- For view-relative placement, resolve the look direction yourself (Ess.Player.targetUnderReticle ->
-- Ess.Math.angleTo) and pass that yaw to Ess.Math.pointAhead.
--
-- HISTORY: a "spawns off to one side" report here was FIRST misdiagnosed as purely this body/view gap. It
-- was actually a mirrored x sign in Ess.Math.pointAhead (fixed 2026-07-19 -- see that file's header). Both
-- effects are real; don't let the body/view explanation talk you out of checking the trig. Calibrate facing
-- EAST/WEST, where a sign error is maximal -- facing north it is invisible.
-- tOpts.useView = true -> project from where the player is LOOKING (Ess.Player.viewYaw) instead of the
-- body yaw, and face the spawn that way too. OPT-IN and trailing, so every existing call is unchanged.
-- Safe by construction: viewYaw falls back to the body yaw when the reticle has no usable hit (open sky).
function Ess.Object.spawnAhead(sTemplate, nDist, nHeight, i, tOpts)
    local px, py, pz, yaw = Ess.Player.pose(i or 0)
    if not px then return nil end
    if tOpts and tOpts.useView then yaw = Ess.Player.viewYaw(i or 0) end
    -- forward projection lives in exactly one place now: Ess.Math.pointAhead (the same sin/cos this used
    -- to inline). Keeps spawnAhead and pointAhead from drifting apart if the yaw convention is ever retuned.
    local x, z = Ess.Math.pointAhead(px, pz, yaw or 0, nDist or 18)
    return Ess.Object.spawn(sTemplate, x, py + (nHeight or 0), z, yaw)
end
