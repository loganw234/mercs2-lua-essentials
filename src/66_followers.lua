-- Ess/66_followers.lua -- Ess.Followers: a lifecycle-aware "who's currently assigned to me" roster, built
-- entirely on Ess.AIOrders (the recruit/follow sequence in 60_aiorders.lua's BEHAVIORS.follow), Ess.On.death
-- (32_on.lua), and Ess.Mark (31_mark.lua) -- no new native calls of its own.
--
-- The gap this closes: Ess.AIOrders.command is stateless -- every call re-passes an explicit guid list, and
-- nothing remembers who you've already recruited. BEHAVIORS.follow's own header admits it never reverts the
-- Ai.Feeling/LivingWorld/Vip state it sets when following ends. This module is the "mine" concept neither
-- of those has: recruit() runs that confirmed sequence AND remembers the guid; dismiss() reverts it AND
-- forgets the guid; a dead follower prunes itself automatically (Ess.On.death), no polling needed; order()
-- is the actual payoff -- command the whole current roster without re-threading a guid list through your
-- own script every time.
--
-- API:
--   Ess.Followers.recruit(guid, opts) -> ok       runs feeling/LivingWorld/Vip/Role, adds to roster
--   Ess.Followers.dismiss(guid) -> ok             reverts Vip/LivingWorld/Role, removes from roster
--   Ess.Followers.dismissAll()                    dismiss() every current follower
--   Ess.Followers.list() -> guids                 current roster (already self-pruned on death)
--   Ess.Followers.count() -> n
--   Ess.Followers.isFollower(guid) -> bool
--   Ess.Followers.order(behavior, opts)           command the whole roster -- any of AIOrders' 11 behaviors
--   Ess.Followers.setMarkersEnabled(bOn)           opt-in floating world markers, see below
--   Ess.Followers.markersEnabled() -> bool
--
-- opts (recruit): same target/minDistance/maxDistance/moveDistance/speed opts BEHAVIORS.follow accepts,
-- plus opts.target (defaults to Ess.Player.character(0), same as AIOrders' own follow default).
--
-- MARKERS (module-wide toggle, ON by default): setMarkersEnabled(true) puts a floating world-space
-- icon over every current AND future follower's head, each in its own color -- picked by stepping the hue
-- wheel by the golden angle (137.508 degrees) so any number of followers stay evenly spread with no fixed
-- palette to run out of and no two consecutive picks landing close together. order()'s own destination
-- (guard/move's point, patrol's waypoints) also gets a temporary neutral-white ground-ring marker while
-- enabled, cleared as soon as a new order supersedes it -- "where did I just tell them to go," not just
-- "where are they now." Toggling OFF clears every marker this module placed (never anyone else's).
--
-- AUTO-RESUME-FOLLOW (confirmed live 2026-07-24, only on a NATURAL completion signal): order()'s own
-- Ai.Role("Idle") release (see below) leaves a follower on whatever the new order was until something tells
-- it to stop. attack resumes Follow the moment its target dies (Ess.On.death on the target); a non-looping
-- move/patrol resumes once every follower finishes its route (onComplete, see 60_aiorders.lua). Guard/hold/
-- a LOOPING patrol/anything else has no natural "done" -- it stays on that order until you explicitly
-- order("follow", opts) again.
--
-- VEHICLE-AWARE FOLLOW (confirmed live 2026-07-24): "return to following" -- whether from auto-resume above
-- or an explicit order("follow", ...) -- goes through smartFollow, not a blanket re-issue of the native
-- Follow role. Ai.Role("Follow") wants its subject to board a vehicle WITH the target, so reissuing it on a
-- follower who's currently DRIVING their own vehicle (after orderEnter, say) makes them climb back OUT to
-- go do that instead -- the "gunner runs out the instant an order finishes" bug this exists to prevent. A
-- driver instead gets a reissued-MoveTo escort loop (the pre-native-Role approach this project's own
-- `follow` used before, scoped here to just the driver); a passenger/gunner is left completely alone (they
-- already go wherever the vehicle goes, and touching their Role/Goal at all risks ejecting them for
-- nothing); on foot uses the plain native Follow role, unchanged. No separate "who's in which vehicle"
-- tracker needed for any of this -- Ess.Object.vehicleOf(guid) answers it live, same confirmed finding as
-- Ess.Easy.Followers.orderEnter's own header.

local Ess = _G.Ess
Ess.Followers = Ess.Followers or {}

local roster = {}      -- guid-key -> { stop = <Ess.On.death stop fn>, target = <the guid it follows> }
local order_ = {}      -- insertion-ordered guid list, for a stable list()
local marks = {}       -- guid-key -> Ess.Mark.object handle (only populated while markers are enabled)
local orderMarks = {}  -- Ess.Mark.zone handles from the CURRENT order's destination(s)
local markersOn = true
local colorStep = 0
local escortLoops = {}   -- guid-key -> Ess.Loop id, for a vehicle DRIVER being escorted via reissued MoveTo
                          -- instead of the native Follow role -- see smartFollow() below for why
local escortAnchors = {} -- guid-key -> the ONE disposable TinyGeometry each escort loop repositions and
                          -- targets every tick (see startEscort) -- removed the moment the loop stops

local function key(guid) return tostring(guid) end

-- ---- color cycling for the marker toggle -- see header for why golden-angle stepping ------------------
local function hslToRgb(h, s, l)
    h = h / 360
    local function hue2rgb(p, q, t)
        if t < 0 then t = t + 1 end
        if t > 1 then t = t - 1 end
        if t < 1 / 6 then return p + (q - p) * 6 * t end
        if t < 1 / 2 then return q end
        if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
        return p
    end
    local r, g, b
    if s == 0 then
        r, g, b = l, l, l
    else
        local q = (l < 0.5) and (l * (1 + s)) or (l + s - l * s)
        local p = 2 * l - q
        r, g, b = hue2rgb(p, q, h + 1 / 3), hue2rgb(p, q, h), hue2rgb(p, q, h - 1 / 3)
    end
    return { math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5) }
end
local function nextColor()
    colorStep = colorStep + 1
    return hslToRgb((colorStep * 137.508) % 360, 0.85, 0.55)
end

-- ---- markers ------------------------------------------------------------------------------------------

-- Ess.Followers.setMarkersEnabled(bOn) -- see header. Toggling ON retroactively marks the CURRENT roster;
-- toggling OFF clears every marker this module placed. A no-op if already in the requested state.
function Ess.Followers.setMarkersEnabled(bOn)
    bOn = bOn and true or false
    if bOn == markersOn then return end
    markersOn = bOn
    if markersOn then
        for _, g in ipairs(order_) do
            local k = key(g)
            if not marks[k] then
                marks[k] = Ess.Mark.object(g, { world = true, radar = false, pda = false, rgb = nextColor() })
            end
        end
    else
        for _, h in pairs(marks) do Ess.Mark.clear(h) end
        marks = {}
    end
end

function Ess.Followers.markersEnabled()
    return markersOn
end

local function xyzOf(t)
    if not t then return nil end
    return t.x or t[1], t.y or t[2], t.z or t[3]
end

local ORDER_MARK_RGB = { 255, 255, 255 }   -- neutral white -- distinct from any follower's own cycled color

local function clearOrderMarks()
    for _, h in ipairs(orderMarks) do Ess.Mark.clear(h) end
    orderMarks = {}
end

-- markDestination(opts) -> handles -- returns the marks it created (rather than pushing straight onto the
-- shared orderMarks) so order() can clear THIS SPECIFIC batch when ITS order naturally completes, without
-- racing a newer order() call that's already replaced orderMarks with its own batch by then.
local function markDestination(opts)
    local created = {}
    if not markersOn then return created end
    if opts.at then
        local x, y, z = xyzOf(opts.at)
        if x then
            local h = Ess.Mark.zone(x, y, z, opts.radius or 8, { rgb = ORDER_MARK_RGB, discAlpha = 0.25, radar = false, pda = false })
            if h then created[#created + 1] = h end
        end
    end
    if opts.points then
        for _, pt in ipairs(opts.points) do
            local x, y, z = xyzOf(pt)
            if x then
                local h = Ess.Mark.zone(x, y, z, 4, { rgb = ORDER_MARK_RGB, discAlpha = 0.25, radar = false, pda = false })
                if h then created[#created + 1] = h end
            end
        end
    end
    -- attack's opts.target is a GUID (or a registered group name -- see BEHAVIORS.attack), not a raw
    -- coordinate; only mark it when it's an actual object (a string here means an unresolved group name,
    -- nothing to attach a floating icon to).
    if opts.target and type(opts.target) == "userdata" then
        local h = Ess.Mark.object(opts.target, { world = true, radar = false, pda = false, rgb = ORDER_MARK_RGB })
        if h then created[#created + 1] = h end
    end
    return created
end

-- ---- vehicle-aware "return to following" ---------------------------------------------------------------
-- CONFIRMED LIVE 2026-07-24: the native Ai.Role("Follow") wants a follower to board a vehicle WITH the
-- player -- reissuing it on a follower who's currently DRIVING their own vehicle (a tank you just put them
-- in, say) makes them get back OUT to go do that instead, exactly the "gunner runs out the moment an order
-- finishes" bug this section exists to prevent. No separate "who's in which vehicle" bookkeeping is needed
-- to detect this, though -- Ess.Object.vehicleOf(guid) (Vehicle.GetFromRider under it) answers "is this guid
-- CURRENTLY riding in a vehicle" live, same confirmed-no-tracker-needed finding as orderEnter's own header.

-- vehicleRoleOf(guid) -> "driver" | "passenger" | nil (nil = on foot).
local function vehicleRoleOf(guid)
    local veh = Ess.Object.vehicleOf(guid)
    if not veh then return nil end
    local ok, driver = pcall(Vehicle.GetDriver, veh)
    if ok and driver == guid then return "driver" end
    return "passenger"
end

local function stopEscort(guid)
    local k = key(guid)
    if escortLoops[k] then Ess.Loop.stop(escortLoops[k]); escortLoops[k] = nil end
    if escortAnchors[k] then Ess.Object.remove(escortAnchors[k]); escortAnchors[k] = nil end
end

-- startEscort(guid, target, minDist, maxDist) -- the pre-native-Role approach this project's own `follow`
-- behavior used before BEHAVIORS.follow was rewritten onto Ai.Role, scoped here specifically to a vehicle's
-- driver. Two confirmed-live fixes stacked on top of each other:
--   1. Naively reissuing "MoveTo target" (targeting the player object directly, no stopping distance)
--      drives the vehicle straight into the player -- Goal="MoveTo" closes ALL the way to the target's
--      exact position, unlike the native Follow role's own MinDistance/MaxDistance/MoveDistance holding
--      pattern, which this loop reimplements by hand since it isn't a Role: idle once within minDist, only
--      starts closing again once past maxDist (hysteresis, so it doesn't twitch at the boundary).
--   2. The computed stand-off point (minDist out from the player, toward the vehicle's current heading)
--      first tried "MoveToPos" directly, on the theory that -- unlike for an on-foot human, see
--      60_aiorders.lua's file header -- a vehicle driver was the ONE confirmed corpus use of that goal.
--      CONFIRMED LIVE this doesn't hold for a bare Ai.Goal call the way it seemed to from the corpus alone:
--      Ai.Goal({Goal="MoveToPos",...}) returned nil for this driver, while "MoveTo" targeting a real object
--      (the same anchorAt() trick 60_aiorders.lua's own move/defend/patrol/flee use) worked immediately.
--      So this reuses ONE disposable TinyGeometry anchor, repositioned every tick instead of retargeted by
--      coordinate, rather than spawning a fresh one each time.
-- Self-stops (and removes its anchor) once the driver dies or genuinely leaves the seat for good.
--
-- CONFIRMED LIVE 2026-07-24: stopping on the FIRST "not driver anymore" reading was too eager -- a single
-- transient bad read (e.g. right as another follower nearby was recruited/spawned) permanently killed a
-- perfectly good escort loop, since Ess.Loop treats a false return as final, not "retry me." Debounced to 3
-- CONSECUTIVE misses (this loop's own 1s interval, so ~3 real seconds) before concluding they've actually
-- left, rather than trusting any single vehicleRoleOf() read on its own.
local function startEscort(guid, target, minDist, maxDist)
    stopEscort(guid)
    minDist = minDist or 10
    maxDist = maxDist or 20
    local k = key(guid)
    local id = "Ess.Followers.escort:" .. k
    escortLoops[k] = id
    local gx0, gy0, gz0 = Ess.Object.pos(guid)
    local anchor = gx0 and Ess.Object.spawn("TinyGeometry", gx0, gy0, gz0)
    if anchor then escortAnchors[k] = anchor end
    local moving = false
    local missedDriverChecks = 0
    Ess.Loop.start(id, 1, function()
        if not anchor or not Object.IsAlive(guid) or not Object.IsAlive(target) then return false end
        if vehicleRoleOf(guid) ~= "driver" then
            missedDriverChecks = missedDriverChecks + 1
            if missedDriverChecks >= 3 then return false end
            return true   -- possibly-transient miss -- skip this tick's movement, keep the loop alive
        end
        missedDriverChecks = 0
        local gx, gy, gz = Ess.Object.pos(guid)
        local tx, ty, tz = Ess.Object.pos(target)
        if not (gx and tx) then return true end
        local dx, dz = gx - tx, gz - tz
        local dist = math.sqrt(dx * dx + dz * dz)
        if dist > maxDist then moving = true
        elseif dist <= minDist then moving = false end
        if moving then
            if dist < 0.01 then dx, dz, dist = 1, 0, 1 end   -- degenerate (right on top) -- pick a direction
            local px = tx + dx / dist * minDist
            local pz = tz + dz / dist * minDist
            Ess.Object.setPos(anchor, px, ty, pz)
            pcall(Ai.Goal, { AIGuid = guid, Goal = "MoveTo", Target = anchor, Priority = "HiPri", Force = true })
        end
        return true
    end)
end

-- smartFollow(guid, target, minDist, maxDist) -- the vehicle-aware "go back to following" ONE guid needs;
-- used by both an explicit order("follow", ...) and the internal auto-resume below. A passenger/gunner is
-- left COMPLETELY alone -- they're already going wherever their vehicle goes, and touching their Role/Goal
-- at all risks pulling them out of their seat for no reason. On foot is the plain native Follow role,
-- unchanged (minDist/maxDist only apply to the vehicle-escort case -- the native Role has its own
-- MinDistance/MaxDistance defaults, see BEHAVIORS.follow).
local function smartFollow(guid, target, minDist, maxDist)
    local role = vehicleRoleOf(guid)
    if role == "driver" then
        startEscort(guid, target, minDist, maxDist)
    elseif role == "passenger" then
        -- ride along -- no order needed, and issuing one risks ejecting them for nothing
    else
        stopEscort(guid)   -- e.g. just got out of a vehicle they were being escort-looped in
        Ess.AIOrders.command({ guid }, "follow", { target = target })
    end
end

-- ---- roster lifecycle -----------------------------------------------------------------------------------

-- Ess.Followers.dismiss(guid) -> ok
-- Reverts exactly what recruit()'s sequence set: Role back to "Idle" (matches resident/mrxfollow.lua's own
-- _ToggleFollowingBehavior(false) in the decompiled game corpus), LivingWorldBehaviour back on, Vip state
-- off, stops any active vehicle-escort loop, and clears its marker if one was placed. A guid that was never
-- recruited is a safe no-op.
function Ess.Followers.dismiss(guid)
    local k = key(guid)
    local entry = roster[k]
    if not entry then return false end
    entry.stop()
    roster[k] = nil
    for i, g in ipairs(order_) do
        if key(g) == k then table.remove(order_, i); break end
    end
    if marks[k] then Ess.Mark.clear(marks[k]); marks[k] = nil end
    stopEscort(guid)
    pcall(Ai.Role, { AIGuid = guid, Role = "Idle", Priority = "hiPri" })
    pcall(Ai.LivingWorld, { AIGuid = guid, Attrib = "LivingWorldBehaviour", State = true })
    pcall(Ai.SetState, { AIGuid = guid, State = "Vip", Value = false })
    return true
end

-- Ess.Followers.recruit(guid, opts) -> ok
-- Runs the confirmed live 2026-07-24 recruit sequence via Ess.AIOrders.command itself -- one implementation
-- of the sequence, not two copies to keep in sync -- then remembers the guid (and what it's following, for
-- order()'s own auto-resume) so order()/list() can find it, and wires Ess.On.death so a follower that dies
-- prunes itself with no polling.
--
-- CONFIRMED LIVE 2026-07-24: this needs the SAME vehicle-awareness as smartFollow (see that function's own
-- header just above) -- a guid that's already sitting in a vehicle at recruit time (real game state, so
-- this can happen even right after a fresh Lua reload wipes the roster) got the native Follow role applied
-- while seated, same as the auto-resume bug this section already fixed once. Checked with vehicleRoleOf()
-- up front instead of always running the native sequence: a driver skips straight to the escort loop (the
-- Vip/LivingWorld/Role prerequisites are specific to Ai.Role("Follow"), which the escort path never uses --
-- only the hostility-neutralize step still applies), a passenger/gunner is registered as-is with nothing
-- touched, and on-foot is the unchanged original sequence.
function Ess.Followers.recruit(guid, opts)
    if not guid then return false end
    local k = key(guid)
    if roster[k] then return true end                 -- already a follower -- idempotent, not an error
    opts = opts or {}
    local target = opts.target or Ess.Player.character(0)
    local role = vehicleRoleOf(guid)
    if role == "driver" then
        local ok, feeling = pcall(Ai.GetFeeling, guid, target)
        if ok and feeling and feeling < 0 then pcall(Ai.SetFeeling, guid, target, 100) end
    elseif role ~= "passenger" then
        local ok = Ess.AIOrders.command({ guid }, "follow", opts)
        if not ok then return false end
    end
    -- minDist/maxDist are for the VEHICLE-escort case specifically (see startEscort) -- distinct from
    -- opts.minDistance/maxDistance/moveDistance, which BEHAVIORS.follow already consumed above for the
    -- native Role's own on-foot holding pattern. Remembered here so a later auto-resume/order("follow", ...)
    -- reuses whatever this recruit() call asked for instead of startEscort's own bare defaults.
    roster[k] = {
        stop = Ess.On.death(guid, function() Ess.Followers.dismiss(guid) end),
        target = target, minDist = opts.escortMinDistance, maxDist = opts.escortMaxDistance,
    }
    order_[#order_ + 1] = guid
    if markersOn then marks[k] = Ess.Mark.object(guid, { world = true, radar = false, pda = false, rgb = nextColor() }) end
    if role == "driver" then startEscort(guid, target, opts.escortMinDistance, opts.escortMaxDistance) end
    return true
end

function Ess.Followers.dismissAll()
    -- iterate a COPY -- dismiss() mutates order_/roster as it goes, walking the live table would skip
    -- entries the same way removing from an array while iterating it always does.
    local snapshot = {}
    for i, g in ipairs(order_) do snapshot[i] = g end
    for _, g in ipairs(snapshot) do Ess.Followers.dismiss(g) end
end

function Ess.Followers.list()
    local out = {}
    for _, g in ipairs(order_) do out[#out + 1] = g end
    return out
end

function Ess.Followers.count()
    return #order_
end

function Ess.Followers.isFollower(guid)
    return roster[key(guid)] ~= nil
end

-- resumeFollow(guids) -- re-issues follow for exactly these guids using each one's OWN remembered follow
-- target from recruit() (not necessarily the player -- recruit(guid, {target=...}) lets it be anyone).
-- Goes through smartFollow so a vehicle driver/passenger among them is handled correctly (see that
-- function's own header) instead of blindly re-issuing the native Follow role at everyone. Internal to
-- order()'s auto-resume; a caller wanting to resume everyone deliberately should just call
-- order("follow", {target=...}) themselves.
local function resumeFollow(guids)
    for _, g in ipairs(guids) do
        local entry = roster[key(g)]
        if entry then smartFollow(g, entry.target, entry.minDist, entry.maxDist) end
    end
end

-- Ess.Followers.order(behavior, opts) -> ok
-- Commands the WHOLE current roster at once -- any of Ess.AIOrders' 11 behaviors (guard/patrol/attack/...),
-- same opts shape as Ess.AIOrders.command. Empty roster is a safe no-op (command() already handles an empty
-- guids list per-behavior).
--
-- CONFIRMED LIVE 2026-07-24: recruit()'s Ai.Role("Follow", HardPriority=true) keeps reasserting itself over
-- a one-shot Ai.Goal issued the SAME tick -- an "attack" order silently did nothing while a follower's Role
-- stayed Follow, even though the Goal call itself returned a valid handle. Releasing the Role AND issuing
-- the new order in the same call never worked in live testing; a short deferred delay between the two
-- (Event.TimerRelative) is what made it reliably take effect -- so order() returns optimistically and the
-- actual command fires a beat later, same as every other deferred call in this codebase.
function Ess.Followers.order(behavior, opts)
    opts = opts or {}
    -- CONFIRMED LIVE 2026-07-24, the actual root cause behind the priority-vs-priority confusion above:
    -- Ess.AIOrders' own per-behavior defaults (e.g. attack's "med") are NOT reliably enough to override a
    -- released Follow Role's leftover state, even with Force=true and Ai.RemoveGoal already applied -- only
    -- "hi"/HiPri consistently worked in testing. Every order issued through a follower's already-HardPriority
    -- Follow role needs to win decisively, so default to "hi" here specifically (NOT changed in
    -- Ess.AIOrders.command itself, whose own callers never have this Role-preemption problem to begin with).
    opts.priority = opts.priority or "hi"
    local list = Ess.Followers.list()
    clearOrderMarks()                     -- clear whatever the LAST order left behind (see below for why
                                           -- a naturally-completed order might already have cleared itself)
    local thisOrderMarks = markDestination(opts)
    orderMarks = thisOrderMarks

    -- CONFIRMED LIVE 2026-07-24: a follower can still be mid-way through a PRIOR order's goal (e.g. still
    -- walking to an old guard point) when a new one comes in -- Force=true on the new goal doesn't reliably
    -- preempt one left over from an EARLIER order() call the way it preempts hold's Anchor lock. Clear it
    -- first with Ai.RemoveGoal({Handle=0}) -- 0 is the confirmed "whatever's current" wildcard the game's
    -- own scripts use when they didn't keep a specific handle to remove (see e.g. allcon002.lua).
    for _, g in ipairs(list) do pcall(Ai.RemoveGoal, { AIGuid = g, Handle = 0 }) end

    if behavior == "follow" then
        -- per-guid via smartFollow, not one blanket Ess.AIOrders.command -- a vehicle driver/passenger
        -- among the roster needs different handling than an on-foot follower (see smartFollow's header).
        -- opts.escortMinDistance/escortMaxDistance override each guid's own recruit()-time default if given.
        local target = opts.target or Ess.Player.character(0)
        for _, g in ipairs(list) do
            local entry = roster[key(g)]
            local minDist = opts.escortMinDistance or (entry and entry.minDist)
            local maxDist = opts.escortMaxDistance or (entry and entry.maxDist)
            smartFollow(g, target, minDist, maxDist)
        end
        return true
    end

    -- stop any active vehicle-escort loop before a NEW non-follow order -- a driver being escort-looped
    -- who's now being ordered to e.g. attack shouldn't have the escort loop fighting the new order for
    -- control every 3 seconds.
    for _, g in ipairs(list) do stopEscort(g) end
    for _, g in ipairs(list) do pcall(Ai.Role, { AIGuid = g, Role = "Idle", Priority = "hiPri" }) end

    -- onDone: fires on natural completion only (see header) -- clears THIS order's own destination marker(s)
    -- (confirmed live 2026-07-24: they used to linger after the unit arrived) and resumes Follow. Compares
    -- against the CURRENT orderMarks (not just clearing blindly) so a newer order() call that already ran
    -- its own clearOrderMarks()/replaced orderMarks isn't stepped on by this older callback firing late.
    local function onDone()
        for _, h in ipairs(thisOrderMarks) do Ess.Mark.clear(h) end
        if orderMarks == thisOrderMarks then orderMarks = {} end
        resumeFollow(list)
    end
    if behavior == "attack" and opts.target then
        Ess.On.death(opts.target, onDone)
    elseif behavior == "move" or (behavior == "patrol" and opts.loop == false) then
        opts.onComplete = onDone
    end

    -- 1.5s -- confirmed live 2026-07-24 that BOTH 0.1s and 0.5s were unreliable settle time after releasing
    -- the Role for the deferred Goal to actually take (every manual reissue several real seconds later
    -- worked; the short deferred ones intermittently didn't). Same class of engine settle-delay as the
    -- "state reads stale for ~0.3s after spawn" gotcha elsewhere in this codebase, just apparently a bigger
    -- margin for a Role release specifically. Noticeable but not disruptive at gameplay pace.
    Event.Create(Event.TimerRelative, { 1.5 }, function()
        Ess.AIOrders.command(list, behavior, opts)
    end)
    return true
end
