-- Ess/11_object.lua -- Ess.Object: common per-object queries and the vehicle-entry watch idiom.
--
-- API:
--   Ess.Object.vehicleOf(uChar) -> uVehicleGuid | nil
--   Ess.Object.setInvincible(uGuid, bOn, sReason)
--   Ess.Object.pollVehicleChange(uChar, onChange, interval) -> stop()

local Ess = _G.Ess
Ess.Object = Ess.Object or {}

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
