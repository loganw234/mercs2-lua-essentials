-- Ess/62_triggers_raw.lua -- Ess.Raw.Triggers: one condition primitive at a time -- the full vocabulary
-- extracted from ContractFramework.lua's `armTrigger`, generalized away from a running contract instance.
--
-- API:
--   Ess.Raw.Triggers.arm(spec, onFire, tracker) -> cancel()
--
-- spec shapes (all confirmed real, ported from armTrigger):
--   nil | "immediate"                         fires onFire() right away
--   "once" | {once=seconds}                    fires once after a delay (default 3s)
--   "recurring" | {recurring=iv, limit=, delay=}  fires every iv seconds, optionally capped at `limit` times
--   {proximity=r, at={x,y,z}}                  fires when the local player gets within r of a point
--   {onDestroy=uGuidOrName}                    fires when a specific object dies
--   {onHealthBelow={target=uGuid, pct=50}}     fires when target drops below pct% of its health AT ARM TIME
--   {onCleared={at={x,y,z}, radius=, kind=, faction=}}   fires when a populated area becomes empty
--
-- NOT ported: ContractFramework's `onObjComplete` (fires on a top-level CONTRACT objective index) -- that
-- concept only exists inside a running Contract instance, there's nothing standalone to generalize it to.
-- If you need that specific behavior, arm your own {once=...} poll against whatever tracks your objective
-- state, or use Ess.Triggers.gate (62_triggers.lua) to compose from other triggers instead.
--
-- `tracker`, if given (an Ess.Track), gets every scheduled Event.Create handle registered for cleanup.
-- Returns cancel() -- call it to stop this trigger from ever firing, even if its condition is later met.

local Ess = _G.Ess
Ess.Raw = Ess.Raw or {}
Ess.Raw.Triggers = Ess.Raw.Triggers or {}

local function xyz(t)
    if not t then return nil end
    return t.x or t[1], t.y or t[2], t.z or t[3]
end

function Ess.Raw.Triggers.arm(spec, onFire, tracker)
    local active = true
    local function cancel() active = false end
    local function fire() if active then onFire() end end
    local function schedule(delay, fn)
        local h = Event.Create(Event.TimerRelative, { delay }, fn)
        if tracker then tracker:event(h) end
        return h
    end

    if spec == nil or spec == "immediate" then
        fire()
        return cancel
    end
    if spec == "once" then spec = { once = 3 } end
    if spec == "recurring" then spec = { recurring = 10 } end
    if type(spec) ~= "table" then
        Ess.Log("Triggers.arm: unrecognized spec " .. tostring(spec))
        return cancel
    end

    if spec.once then
        schedule(tonumber(spec.once) or 3, fire)
        return cancel
    end

    if spec.recurring then
        local iv, lim, cnt = spec.recurring, spec.limit, 0
        local function tick()
            if not active then return end
            fire()
            cnt = cnt + 1
            if not (lim and cnt >= lim) then schedule(iv, tick) end
        end
        schedule(spec.delay or iv, tick)
        return cancel
    end

    if spec.proximity then
        local zx, zy, zz = xyz(spec.at)
        local r = spec.proximity
        local function poll()
            if not active then return end
            local uc = Player.GetLocalCharacter()
            if uc and zx then
                local ok, px, _, pz = pcall(Object.GetPosition, uc)
                if ok and px then
                    local dx, dz = px - zx, pz - zz
                    if dx * dx + dz * dz <= r * r then return fire() end
                end
            end
            schedule(0.4, poll)
        end
        poll()
        return cancel
    end

    if spec.onDestroy then
        local target, g = spec.onDestroy, nil
        if type(target) == "string" then
            local ok, gg = pcall(Pg.GetGuidByName, target)
            if ok then g = gg end
        else
            g = target
        end
        if g then
            local h = Event.Create(Event.ObjectDeath, { g }, fire)
            if tracker then tracker:event(h) end
        else
            Ess.Log("Triggers.arm: onDestroy target not found: " .. tostring(target))
        end
        return cancel
    end

    if spec.onHealthBelow then
        local hb = spec.onHealthBelow
        local target, pct = hb.target, hb.pct or 50
        local base
        local function poll()
            if not active then return end
            if target then
                local ok, hp = pcall(Object.GetHealth, target)
                if ok and hp then
                    base = base or (hp > 0 and hp) or base
                    if base and base > 0 and hp <= base * (pct / 100) then return fire() end
                end
            end
            schedule(0.5, poll)
        end
        poll()
        return cancel
    end

    if spec.onCleared then
        local oc = spec.onCleared
        local zx, zy, zz = xyz(oc.at or spec.at)
        local r = oc.radius or 45
        local kind, faction = oc.kind, oc.faction
        local seen
        local function poll()
            if not active or not zx then return end
            local n = #Ess.Probe.nearby(zx, zy, zz, r, kind, faction)
            if n > 0 then seen = true end
            if seen and n == 0 then return fire() end
            schedule(0.8, poll)
        end
        poll()
        return cancel
    end

    Ess.Log("Triggers.arm: spec table matched no known condition")
    return cancel
end
