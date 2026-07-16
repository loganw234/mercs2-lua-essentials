-- Ess/60_aiorders.lua -- Ess.AIOrders: command a spawned unit GROUP, extracted from ContractFramework.lua's
-- AI_BEHAVIORS table so it's usable outside a running contract -- the direct unblock for the stalled
-- Active-World director project.
--
-- API:
--   Ess.AIOrders.setGroup(name, guids) / .group(name) -> guids     a standalone group registry
--   Ess.AIOrders.command(guids, behavior, opts, tracker) -> ok
--
-- behaviors (each built ONLY on confirmed Ai.Goal/Ai.Anchor/Ai.Deploy primitives, exactly as
-- ContractFramework.lua already uses them):
--   move    -> MoveToPos(at)                     go to a spot and stop
--   face    -> Face(at)                          turn to face a point (staging / cutscene feel)
--   hold    -> Idle + Anchor(0)                   stand ground where spawned, don't give chase
--   defend  -> MoveToPos(at) + Anchor(radius)     hold an area, fight anything inside it
--   attack  -> Attack(target group / nearest hero)  hunt a target
--   patrol  -> MoveToPos chain through points     walk a route (loops unless loop=false)
--   follow  -> re-issued MoveTo a target, on an interval -- tails something that moves
--   flee    -> MoveToPos directly away from the nearest hero
--   enter   -> board a vehicle (opts.target = its group name) as driver/gunner/passenger
--   deploy  -> a transport (guids = vehicles) disgorges its passengers
--   animate -> play a canned action ("Cower", "Stand", ...)
--
-- opts fields used across behaviors: at={x,y,z}, points={ {x,y,z}, ... }, loop, speed, priority,
-- target=<group name>, radius, role, action, interval, distance.

local Ess = _G.Ess
Ess.AIOrders = Ess.AIOrders or {}
Ess.AIOrders._groups = Ess.AIOrders._groups or {}

-- Ess.AIOrders.setGroup(name, guids) / .group(name) -> guids
-- A standalone stand-in for ContractFramework's `inst.groups` -- lets `attack`/`follow`/`enter` target
-- ANOTHER named group without needing a contract instance to hold the registry. Empty table (never nil)
-- for an unknown name, matching groupGuids' own confirmed-safe fallback.
function Ess.AIOrders.setGroup(name, guids)
    Ess.AIOrders._groups[tostring(name)] = guids
end
function Ess.AIOrders.group(name)
    return Ess.AIOrders._groups[tostring(name or "")] or {}
end

local function xyz(t)
    if not t then return nil end
    return t.x or t[1], t.y or t[2], t.z or t[3]
end
local function nearestHero()
    local ok, u = pcall(Player.GetLocalCharacter)
    if ok then return u end
end
local actor, pri, aiGoal, haste =
    Ess.Raw.AIOrders.actor, Ess.Raw.AIOrders.pri, Ess.Raw.AIOrders.goal, Ess.Raw.AIOrders.haste

local BEHAVIORS = {}

BEHAVIORS.move = function(tracker, o, guids)
    local x, y, z = xyz(o.at); if not x then return end
    local p = pri(o.priority)
    for _, g in ipairs(guids) do
        local a = actor(g)
        aiGoal({ AIGuid = a, Goal = "MoveToPos", Location = { x, y, z }, Priority = p, Force = true })
        haste(a, o.speed)
    end
end

BEHAVIORS.face = function(tracker, o, guids)
    local x, y, z = xyz(o.at); if not x then return end
    for _, g in ipairs(guids) do
        aiGoal({ AIGuid = actor(g), Goal = "Face", Target = { x, y, z }, Position = true, Priority = "HiPri" })
    end
end

BEHAVIORS.hold = function(tracker, o, guids)
    for _, g in ipairs(guids) do
        local a = actor(g)
        pcall(Ai.Anchor, { AIGuid = a, AnchorRadius = 0 })
        aiGoal({ AIGuid = a, Goal = "Idle", Priority = "HiPri" })
    end
end

BEHAVIORS.defend = function(tracker, o, guids)
    local x, y, z = xyz(o.at); if not x then return end
    local r, p = o.radius or 12, pri(o.priority)
    local ok, anchor = pcall(Pg.Spawn, "TinyGeometry", x, y, z)
    if ok and anchor and tracker then tracker:guid(anchor) end
    for _, g in ipairs(guids) do
        local a = actor(g)
        aiGoal({ AIGuid = a, Goal = "MoveToPos", Location = { x, y, z }, Priority = p, Force = true })
        haste(a, o.speed)
        if ok and anchor then pcall(Ai.Anchor, { AIGuid = a, AnchorGuid = anchor, AnchorRadius = r }) end
    end
end

BEHAVIORS.attack = function(tracker, o, guids)
    local tgt
    if o.target then tgt = Ess.AIOrders.group(o.target)[1] end
    if not tgt then tgt = nearestHero() end
    local p = pri(o.priority or "med")
    for _, g in ipairs(guids) do
        local a = actor(g)
        if tgt then
            aiGoal({ AIGuid = a, Goal = "Attack", Target = tgt, Priority = p })
        else
            local x, y, z = xyz(o.at)
            if x then aiGoal({ AIGuid = a, Goal = "MoveToPos", Location = { x, y, z }, Priority = p }) end
        end
        haste(a, o.speed)
    end
end

BEHAVIORS.patrol = function(tracker, o, guids)
    local pts = o.points or (o.at and { o.at }) or {}
    if #pts == 0 then return end
    local loop, p = (o.loop ~= false and #pts >= 2), pri(o.priority)
    for _, g in ipairs(guids) do
        local a = actor(g); haste(a, o.speed)
        local i = 0
        local function step()
            i = i + 1
            if i > #pts then if loop then i = 1 else return end end
            local x, y, z = xyz(pts[i]); if not x then return end
            aiGoal({ AIGuid = a, Goal = "MoveToPos", Location = { x, y, z }, Priority = p, Force = true,
                     Callback = function(_, State) if State == 1 then step() end end })
        end
        step()
    end
end

BEHAVIORS.follow = function(tracker, o, guids)
    local function tgt() if o.target then return Ess.AIOrders.group(o.target)[1] end return nearestHero() end
    for _, g in ipairs(guids) do
        local a = actor(g)
        local function chase()
            local t = tgt()
            if t then aiGoal({ AIGuid = a, Goal = "MoveTo", Target = t, Priority = pri(o.priority), Force = true }) end
            haste(a, o.speed)
            local h = Event.Create(Event.TimerRelative, { o.interval or 4 }, chase)
            if tracker then tracker:event(h) end
        end
        chase()
    end
end

BEHAVIORS.flee = function(tracker, o, guids)
    local hero = nearestHero(); local hx, hz
    if hero then local ok, x, _, z = pcall(Object.GetPosition, hero); if ok then hx, hz = x, z end end
    local dist = o.distance or 120
    for _, g in ipairs(guids) do
        local a = actor(g)
        local ok, gx, gy, gz = pcall(Object.GetPosition, g)
        if ok and gx then
            local dx, dz = gx - (hx or gx - 1), gz - (hz or gz)
            local len = math.sqrt(dx * dx + dz * dz); if len < 1 then dx, dz, len = 1, 0, 1 end
            aiGoal({ AIGuid = a, Goal = "MoveToPos", Location = { gx + dx / len * dist, gy, gz + dz / len * dist },
                     Priority = "HiPri", Force = true })
            haste(a, o.speed or 1)
        end
    end
end

BEHAVIORS.enter = function(tracker, o, guids)
    local veh = o.target and Ess.AIOrders.group(o.target)[1]
    if not veh and o.target then local ok, g = pcall(Pg.GetGuidByName, o.target); if ok then veh = g end end
    if not veh then return end
    for _, g in ipairs(guids) do
        aiGoal({ AIGuid = g, Goal = "Enter", Target = veh, Role = o.role or "passenger", Priority = "HiPri", Force = true })
    end
end

BEHAVIORS.deploy = function(tracker, o, guids)
    for _, g in ipairs(guids) do pcall(Ai.Deploy, { Vehicle = g, Role = "Passenger", Priority = "HiPri", Force = true }) end
end

BEHAVIORS.animate = function(tracker, o, guids)
    for _, g in ipairs(guids) do pcall(Human.DoAction, g, o.action or "Cower") end
end

Ess.AIOrders._behaviors = BEHAVIORS

-- Ess.AIOrders.command(guids, behavior, opts, tracker) -> ok
-- `tracker` (an Ess.Track), if given, receives any spawned anchor props (defend) or scheduled follow-up
-- events (follow) for cleanup -- omit it and those just aren't tracked for you.
function Ess.AIOrders.command(guids, behavior, opts, tracker)
    opts = opts or {}
    local fn = BEHAVIORS[behavior]
    if not fn then
        Ess.Log("AIOrders.command: unknown behavior '" .. tostring(behavior) .. "'")
        return false
    end
    local ok, err = pcall(fn, tracker, opts, guids or {})
    if not ok then Ess.Log("AIOrders.command '" .. tostring(behavior) .. "' error: " .. tostring(err)) end
    return ok
end
