-- Ess/19_inspect.lua -- Ess.Inspect: a structured, NAMED read of an entity -- the "remote inspector".
--
-- `Ess.Probe.describeSafe` gives a one-line string; this returns a typed RECORD (a Lua table) grouped the way
-- the engine's components are -- identity / transform / health / physics / vehicle / faction -- every field
-- pulled through its confirmed getter and guarded, so a field the engine won't answer is simply absent rather
-- than an error. It is the read side of the bridge Plan 03 calls "typed reads, not eval": instead of a raw
-- table dump you get named fields you can branch on.
--
-- The one thing it recovers that nothing else can: a readable NAME and MODEL. `Object.GetName` /
-- `Object.GetModelName` return an opaque interned HANDLE (userdata), not a string -- Ess.Object's own header
-- says you "cannot read it back". But that handle stringifies to its `0xHASH` through `Sys.GuidToString`, and
-- Ess.Names reverses the hash -- so the inspector hands back `oc_veh_helicopter_md500` where the getter alone
-- gives you an unprintable handle. With the Ess.Names table absent it degrades to the bare `0x…`.
--
-- API:
--   Ess.Inspect.read(uGuid)  -> tRecord | nil   the typed record (nil only for a nil/!valid guid).
--                                               Ess.Inspect(uGuid) is sugar for the same call.
--   Ess.Inspect.print(uGuid)                    log the record, grouped, for the console (the inspector view)
--   Ess.Inspect.line(uGuid)  -> string          a one-line summary (name/model/pos/hp/faction)
--
-- tRecord fields (each present only when the engine answered): guid, name, model, valid, alive, health,
-- maxHealth, invincible, playerControlled, pos {x,y,z}, yaw, velocity {x,y,z}, speed, physicsType, awake,
-- hibernated, faction, vehicle {of|driver|seat}, parent, attached {…}.

local Ess = _G.Ess

Ess.Inspect = Ess.Inspect or {}

-- Object.GetName / GetModelName return an interned HANDLE, not a string. Stringify it to its 0xHASH and
-- reverse that through Ess.Names -- the only path to the readable name, since the getter can't return one.
local function resolve_handle(fn, uGuid)
    if type(fn) ~= "function" then return nil end
    local ok, h = Ess.Safe.quiet(fn, uGuid)
    if not ok or h == nil then return nil end
    local ok2, s = Ess.Safe.quiet(Sys.GuidToString, h)
    if not ok2 or type(s) ~= "string" then return nil end
    return (Ess.Names and Ess.Names.of(s)) or s          -- name if we can reverse it, else the bare hash
end

-- Engine getters return 1/0 for booleans (and 0 is truthy in Lua) -- coerce to a real bool. nil passes through.
local function tobool(v)
    if v == nil then return nil end
    return v == true or v == 1
end

-- Ess.Inspect(uGuid) -> tRecord | nil
function Ess.Inspect.read(uGuid)
    if not uGuid then return nil end
    local valid = Ess.Object.valid(uGuid)
    if valid == false then return nil end                -- a stale/garbage guid: nothing to read

    local r = { guid = Ess.Name(uGuid), valid = true }

    -- identity (the handles the getters can't stringify on their own)
    r.name = resolve_handle(Object and Object.GetName, uGuid)
    r.model = resolve_handle(Object and Object.GetModelName, uGuid)
    r.playerControlled = tobool(Ess.Object.playerControlled(uGuid))

    -- health
    r.alive = Ess.Object.alive(uGuid)
    r.health = Ess.Object.health(uGuid)
    r.maxHealth = Ess.Object.maxHealth(uGuid)
    r.invincible = Ess.Object.invincible(uGuid)

    -- transform
    local x, y, z = Ess.Object.pos(uGuid)
    if x then r.pos = { x = x, y = y, z = z } end
    r.yaw = Ess.Object.yaw(uGuid)
    local vx, vy, vz = Ess.Object.velocity(uGuid)
    if vx then r.velocity = { x = vx, y = vy, z = vz } end
    r.speed = Ess.Object.speed(uGuid)

    -- physics
    r.physicsType = Ess.Object.physicsType(uGuid)
    r.awake = Ess.Object.awake(uGuid)
    r.hibernated = Ess.Object.hibernated(uGuid)

    -- relationships
    r.faction = Ess.Probe and Ess.Probe.getFaction(uGuid) or nil
    r.parent = Ess.Object.parent and Ess.Object.parent(uGuid) or nil
    local att = Ess.Object.attached and Ess.Object.attached(uGuid)
    if att and #att > 0 then r.attached = att end

    -- vehicle: whichever way the relationship runs (a rider's vehicle, or this vehicle's driver/riders)
    local veh = Ess.Object.vehicleOf and Ess.Object.vehicleOf(uGuid)
    local drv = Ess.Vehicle and Ess.Vehicle.driver(uGuid)
    if veh or drv then
        r.vehicle = {}
        if veh then r.vehicle.of = Ess.Name(veh) end
        if drv then r.vehicle.driver = Ess.Name(drv) end
        local seat = Ess.Vehicle and Ess.Vehicle.seatOf(uGuid)
        if seat then r.vehicle.seat = seat end
    end

    return r
end

-- Make Ess.Inspect callable: Ess.Inspect(g) == Ess.Inspect.read(g).
setmetatable(Ess.Inspect, { __call = function(_, uGuid) return Ess.Inspect.read(uGuid) end })

-- A readable name for the header: the resolved name if we have one, else the model, else the bare guid.
local function label(r)
    return r.name or r.model or r.guid or "?"
end

-- Ess.Inspect.line(uGuid) -> string -- one-line summary. Always a string (never nil), safe to log.
function Ess.Inspect.line(uGuid)
    local r = Ess.Inspect.read(uGuid)
    if not r then return "<nil or invalid>" end
    local parts = { label(r) .. " (" .. tostring(r.guid) .. ")" }
    if r.model and r.model ~= r.name then parts[#parts + 1] = "model=" .. r.model end
    if r.pos then parts[#parts + 1] = string.format("pos=(%.0f,%.0f,%.0f)", r.pos.x, r.pos.y, r.pos.z) end
    if r.health then parts[#parts + 1] = "hp=" .. tostring(r.health) .. "/" .. tostring(r.maxHealth or "?") end
    if r.faction then parts[#parts + 1] = r.faction end
    return table.concat(parts, " ")
end

-- Ess.Inspect.print(uGuid) -- log the record grouped by component, the remote-inspector view.
function Ess.Inspect.print(uGuid)
    local r = Ess.Inspect.read(uGuid)
    if not r then Ess.Log("[inspect] <nil or invalid guid>"); return end
    Ess.Log("[inspect] " .. label(r) .. " (" .. tostring(r.guid) .. ")")
    if r.model then Ess.Log("  identity   model=" .. r.model .. "  player=" .. tostring(r.playerControlled)) end
    if r.pos then
        Ess.Log(string.format("  transform  pos=(%.1f, %.1f, %.1f)  yaw=%s  speed=%s",
            r.pos.x, r.pos.y, r.pos.z, tostring(r.yaw), tostring(r.speed)))
    end
    if r.health or r.alive ~= nil then
        Ess.Log("  health     " .. tostring(r.health) .. "/" .. tostring(r.maxHealth)
            .. "  alive=" .. tostring(r.alive) .. "  invincible=" .. tostring(r.invincible))
    end
    if r.physicsType ~= nil or r.awake ~= nil then
        Ess.Log("  physics    type=" .. tostring(r.physicsType) .. "  awake=" .. tostring(r.awake)
            .. "  hibernated=" .. tostring(r.hibernated))
    end
    if r.faction then Ess.Log("  faction    " .. r.faction) end
    if r.vehicle then
        Ess.Log("  vehicle    of=" .. tostring(r.vehicle.of) .. "  driver=" .. tostring(r.vehicle.driver)
            .. "  seat=" .. tostring(r.vehicle.seat))
    end
end
