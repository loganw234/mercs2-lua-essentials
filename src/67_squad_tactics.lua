-- Ess/67_squad_tactics.lua -- Ess.Squad.Tactics: pre-packaged multi-stage squad tactics built on
-- Ess.Followers._issue + Ess.Squad's own team/role bookkeeping -- no new native calls.
--
-- API:
--   Ess.Squad.Tactics.mountUp(vehGuid, targetGroup, opts) -> ok
--     Smart multi-seat vehicle loading -- whoever's been Ess.Squad.assignRole(guid, "driver")'d among the
--     group boards first as driver; everyone else boards as passenger (opts.passengerRole to override, e.g.
--     "gunner"). Fires "onVehicleMounted" (vehGuid, guids) once every guid in the group is seated in SOME
--     vehicle, or gives up silently after opts.timeout (default 20s) -- a blocked/full vehicle is a real,
--     expected outcome here, not an error.
--   Ess.Squad.Tactics.dismountAndSecure(targetGroup, atPos, radius) -> ok
--     Disgorges the group from whatever vehicle(s) it's currently riding and establishes a defend perimeter
--     at atPos once out.

local Ess = _G.Ess
Ess.Squad = Ess.Squad or {}
Ess.Squad.Tactics = Ess.Squad.Tactics or {}

local function allSeated(guids)
    for _, g in ipairs(guids) do
        if not Ess.Object.vehicleOf(g) then return false end
    end
    return true
end

function Ess.Squad.Tactics.mountUp(vehGuid, targetGroup, opts)
    if not vehGuid then return false end
    opts = opts or {}
    local guids = Ess.Squad._resolveGuids(targetGroup)
    if not guids or #guids == 0 then return false end

    -- role-assigned drivers board FIRST (before a passenger call could otherwise claim the seat); everyone
    -- else boards as passenger (or opts.passengerRole, e.g. "gunner", for a vehicle with turret seats).
    local drivers, others = {}, {}
    for _, g in ipairs(guids) do
        if Ess.Squad.roleOf(g) == "driver" then drivers[#drivers + 1] = g
        else others[#others + 1] = g end
    end
    if #drivers > 0 then Ess.Followers._issue(drivers, "enter", { target = vehGuid, role = "driver" }) end
    if #others > 0 then Ess.Followers._issue(others, "enter", { target = vehGuid, role = opts.passengerRole or "passenger" }) end

    -- poll until everyone's actually seated -- same idiom Ess.Squad.queue's own "enter" step uses, just a
    -- one-off here rather than wired into a multi-step sequence.
    local id = "Ess.Squad.mountUp:" .. tostring(vehGuid)
    local budget = opts.timeout or 20
    local elapsed = 0
    Ess.Loop.start(id, 0.5, function()
        if allSeated(guids) then
            Ess.Followers._emit("onVehicleMounted", vehGuid, guids)
            return false
        end
        elapsed = elapsed + 0.5
        return elapsed < budget
    end)
    return true
end

-- Ess.Squad.Tactics.dismountAndSecure(targetGroup, atPos, radius) -> ok
-- BEHAVIORS.deploy (60_aiorders.lua) targets the VEHICLE guids themselves, not their passengers -- collect
-- whichever of `guids` are CURRENTLY riding in a vehicle and deploy the (deduplicated) vehicle guid(s).
--
-- CONFIRMED LIVE 2026-07-25: Deploy only ejects PASSENGERS -- a vehicle's DRIVER stays seated straight
-- through it (the vehicle just sits there with them still in it). "The whole squad dismounts" needs an
-- explicit exit for whoever's still driving -- Vehicle.Exit(vehGuid, riderGuid, bool), confirmed across
-- many corpus call sites (e.g. resident/mrxsupportcopterdelivery.lua's own `Vehicle.Exit(uHeli, uDriver,
-- false)` for exactly this "make the driver get out" case).
function Ess.Squad.Tactics.dismountAndSecure(targetGroup, atPos, radius)
    local guids = Ess.Squad._resolveGuids(targetGroup)
    if not guids or #guids == 0 or not atPos then return false end

    local vehSeen, vehs = {}, {}
    for _, g in ipairs(guids) do
        local veh = Ess.Object.vehicleOf(g)
        if veh and not vehSeen[tostring(veh)] then
            vehSeen[tostring(veh)] = true
            vehs[#vehs + 1] = veh
        end
    end
    if #vehs > 0 then
        Ess.Followers._issue(vehs, "deploy", {})
        for _, veh in ipairs(vehs) do
            local ok, driver = pcall(Vehicle.GetDriver, veh)
            if ok and driver then pcall(Vehicle.Exit, veh, driver, false) end
        end
    end

    -- 2s -- gives Deploy a moment to actually eject riders before a Defend/Anchor goal takes hold on
    -- guids still technically mid-exit; same class of engine settle-delay _issue's own Role-release
    -- already needs, just a separate step here since deploy/defend are two different behaviors.
    Event.Create(Event.TimerRelative, { 2 }, function()
        Ess.Followers._issue(guids, "defend", { at = atPos, radius = radius or 15 })
    end)
    return true
end
