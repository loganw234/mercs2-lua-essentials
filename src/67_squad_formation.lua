-- Ess/67_squad_formation.lua -- Ess.Squad.Formation: on-foot positional formations (wedge/column/line/
-- diamond) for a squad operating independently of the player. Explicitly "visual sugar," not a precision
-- tactical system (per the design discussion that shaped this) -- a wedge is just N units walking to
-- waypoints staggered slightly from each other and the leader, recomputed every tick as the leader moves.
--
-- WHY THIS CAN'T USE NATIVE Ai.Role("Follow"): the native Role holds a single MinDistance/MaxDistance band
-- around ONE target point -- it has no notion of "stand at THIS specific offset, rotated to the leader's
-- facing." A real per-slot position means abandoning the Role entirely for formation members, generalizing
-- the SAME two ingredients Ess.Followers.startFollowLoop already proved out for a vehicle escort/on-foot
-- resume (see that file's header): a reissued MoveTo to a repositioned TinyGeometry anchor, plus a feeling
-- re-pin every tick (anything off native Follow drifts hostile on its own, confirmed live there) -- just
-- with per-slot offset math here instead of a hysteresis band around the leader.
--
-- API:
--   Ess.Squad.setFormation(targetGroup, formationType, opts) -> ok
--     formationType: "wedge" (default) | "column" | "line" | "diamond"
--     opts: { leader = guid (default the local player), spacing = number (default 3) }
--   Ess.Squad.clearFormation(targetGroup) -> ok    stops the formation loop, leaves guids wherever they are

local Ess = _G.Ess
Ess.Squad = Ess.Squad or {}

local formationLoops = {}    -- guid-key -> Ess.Loop id
local formationAnchors = {}  -- guid-key -> the ONE disposable TinyGeometry each loop repositions every tick

local function key(guid) return tostring(guid) end

local function stopSlot(guid)
    local k = key(guid)
    if formationLoops[k] then Ess.Loop.stop(formationLoops[k]); formationLoops[k] = nil end
    if formationAnchors[k] then Ess.Object.remove(formationAnchors[k]); formationAnchors[k] = nil end
end

-- Ess.Squad._formationAnchorOf(guid) -> uGuid|nil -- the disposable TinyGeometry this guid's formation slot
-- is currently repositioning every tick (nil if not in formation right now). formationAnchors is otherwise
-- a private closure table with no other way to reach it from outside this file -- added for the Followers/
-- Squad web tool's live map, so "where is this unit's formation waypoint RIGHT NOW" (not just the unit
-- itself) can be streamed and watched moving, e.g. to debug a formation that isn't converging correctly.
function Ess.Squad._formationAnchorOf(guid)
    return formationAnchors[key(guid)]
end

-- slotOffset(formationType, index, total, spacing) -> right, forward -- LEADER-LOCAL offset (right+ = the
-- leader's right side, forward+ = ahead of the leader), fed straight into Ess.Math.rotateOffset every tick
-- -- the same right/forward convention MissionForge's own squad-grid placement already uses.
local function slotOffset(formationType, index, total, spacing)
    if formationType == "column" then
        -- single file directly behind the leader, increasing distance
        return 0, -spacing * index
    elseif formationType == "line" then
        -- flat wall spread horizontally, just behind the leader
        return (index - (total + 1) / 2) * spacing, -spacing * 0.5
    elseif formationType == "diamond" then
        -- 360-degree perimeter around the leader
        local angle = (index - 1) / total * 2 * math.pi
        return math.sin(angle) * spacing, math.cos(angle) * spacing
    else
        -- "wedge" (default): V-shape opening forward, alternating left/right, growing behind the leader
        local rank = math.ceil(index / 2)
        local side = (index % 2 == 1) and -1 or 1
        return side * rank * spacing * 0.8, -rank * spacing
    end
end

local function startSlot(guid, leader, formationType, index, total, spacing)
    stopSlot(guid)
    local k = key(guid)
    local id = "Ess.Squad.formation:" .. k
    formationLoops[k] = id
    local gx0, gy0, gz0 = Ess.Object.pos(guid)
    local anchor = gx0 and Ess.Object.spawn("TinyGeometry", gx0, gy0, gz0)
    if anchor then formationAnchors[k] = anchor end
    local rx, rz = slotOffset(formationType, index, total, spacing)
    Ess.Loop.start(id, 0.5, function()
        if not anchor or not Object.IsAlive(guid) or not Object.IsAlive(leader) then return false end
        -- re-pin feeling every tick -- this guid is off native Follow the whole time it's in formation,
        -- the same drift Ess.Followers.startFollowLoop's own header documents and fixes the same way.
        local fok, feeling = pcall(Ai.GetFeeling, guid, leader)
        if fok and feeling and feeling < 50 then pcall(Ai.SetFeeling, guid, leader, 100) end

        local lx, ly, lz = Ess.Object.pos(leader)
        if not lx then return true end
        local yaw = Ess.Object.yaw(leader) or 0
        local wx, wz = Ess.Math.rotateOffset(lx, lz, yaw, rx, rz)
        local gx, gy, gz = Ess.Object.pos(guid)
        if not gx then return true end
        local dist = math.sqrt((gx - wx) ^ 2 + (gz - wz) ^ 2)
        -- small hysteresis (0.75u) so this doesn't reissue a goal every 0.5s over sub-unit jitter once a
        -- guid has basically reached its slot.
        if dist > 0.75 then
            Ess.Object.setPos(anchor, wx, ly, wz)
            pcall(Ai.Goal, { AIGuid = guid, Goal = "MoveTo", Target = anchor, Priority = "HiPri", Force = true })
        end
        return true
    end)
end

-- Ess.Squad.setFormation(targetGroup, formationType, opts) -> ok
function Ess.Squad.setFormation(targetGroup, formationType, opts)
    opts = opts or {}
    local guids = Ess.Squad._resolveGuids(targetGroup)
    if not guids or #guids == 0 then return false end
    local leader = opts.leader or Ess.Player.character(0)
    if not leader then return false end
    local spacing = opts.spacing or 3
    for i, g in ipairs(guids) do
        -- clear whatever's currently driving this guid FIRST -- an existing Ess.Followers-managed
        -- vehicle-escort/on-foot-resume loop (see that file's startFollowLoop) would otherwise keep
        -- running in parallel with this guid's new formation-slot loop, both fighting over its movement.
        -- Native Role/leftover Goal state gets the same RemoveGoal wildcard + Role->Idle release every
        -- other transition in this codebase uses.
        Ess.Followers._stopFollowLoop(g)
        pcall(Ai.RemoveGoal, { AIGuid = g, Handle = 0 })
        pcall(Ai.Role, { AIGuid = g, Role = "Idle", Priority = "hiPri" })
        startSlot(g, leader, formationType, i, #guids, spacing)
    end
    return true
end

-- Ess.Squad.clearFormation(targetGroup) -> ok -- stops every formation loop for this group, leaving guids
-- frozen wherever they currently stand. Deliberately does NOT auto-resume Follow (unlike Ess.Squad.queue's
-- own cancelQueue, which explicitly reverts to Follow as ITS documented fallback) -- a formation is
-- typically cleared to hand the group to a DIFFERENT explicit order, not to send them back to following;
-- call order("follow", ...)/orderTeam yourself if that's what should happen next.
function Ess.Squad.clearFormation(targetGroup)
    local guids = Ess.Squad._resolveGuids(targetGroup)
    if not guids or #guids == 0 then return false end
    for _, g in ipairs(guids) do stopSlot(g) end
    return true
end
