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
--   Ess.Followers._orderScoped(scope, guids, behavior, opts)   the scoped core order() itself calls with
--                                                  scope="__all__" -- Ess.Squad.orderTeam reuses this
--                                                  directly to command a SUBSET without racing order()
--   Ess.Followers._issue(guids, behavior, opts)    _orderScoped's own core, no marker/auto-resume wiring --
--                                                  Ess.Squad.queue reuses this for step-by-step sequencing,
--                                                  which needs its OWN completion signal per step instead
--   Ess.Followers.setMarkersEnabled(bOn)           opt-in floating world markers, see below
--   Ess.Followers.markersEnabled() -> bool
--   Ess.Followers.on(eventName, fn) -> stop()      generic pub/sub -- "onRecruit"/"onDismiss"(guid,wasKilled)
--                                                  /"onFollowerDown" today; Ess.Squad forwards its own
--                                                  .on(...) to this SAME bus for its higher-level events
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
-- driver gets a reissued-MoveTo escort loop (see startFollowLoop); a passenger/gunner is left completely
-- alone (they already go wherever the vehicle goes, and touching their Role/Goal at all risks ejecting them
-- for nothing). No separate "who's in which vehicle" tracker needed for any of this -- Ess.Object.vehicleOf
-- (guid) answers it live, same confirmed finding as Ess.Easy.Followers.orderEnter's own header.
--
-- RESUME ALSO USES THE LOOP ON FOOT (CONFIRMED LIVE 2026-07-25, superseding an earlier assumption in this
-- section that on-foot just reissues the plain native Follow role unchanged): it doesn't. A follower taken
-- off native Follow for ANY order snaps back hostile toward `target` within 1-3 seconds on its own, and
-- reissuing Ai.Role("Follow") afterward returns a truthy handle but never actually moves them -- both
-- confirmed side-by-side against an untouched follower on native Follow the whole time, who never drifted
-- and moved fine. Native Follow is reliable ONLY on its first engagement, straight from recruit() (left
-- unchanged) -- every RESUME, on foot or not, now goes through startFollowLoop instead, which also re-pins
-- feeling every tick to stop the drift. See startFollowLoop's own header for the full account and the one
-- accepted tradeoff (a resumed follower loses native Follow's free vehicle-boarding-with-you convenience
-- until explicitly orderEnter()'d again).

local Ess = _G.Ess
Ess.Followers = Ess.Followers or {}

local roster = {}      -- guid-key -> { stop = <Ess.On.death stop fn>, target = <the guid it follows> }
local order_ = {}      -- insertion-ordered guid list, for a stable list()
local marks = {}       -- guid-key -> Ess.Mark.object handle (only populated while markers are enabled)
local orderMarksByScope = {}  -- scope -> Ess.Mark.zone handles from THAT scope's current order destination(s)
                              -- -- keyed (not a single shared slot) so Ess.Squad can issue an order to one
                              -- team without clearing/racing another team's own in-flight order. "__all__"
                              -- is Ess.Followers.order()'s own scope (the whole roster).
local markersOn = true
local colorStep = 0
local followLoops = {}   -- guid-key -> Ess.Loop id, for a guid being followed-back via reissued MoveTo
                          -- instead of the native Follow role -- see smartFollow() below for why. Used for
                          -- BOTH a vehicle driver's escort AND an on-foot follower's RESUME (see
                          -- startFollowLoop's header -- native Follow turned out not to be reliably
                          -- re-engageable once broken, on foot or not).
local followLoopAnchors = {} -- guid-key -> the ONE disposable TinyGeometry each loop repositions and
                              -- targets every tick (see startFollowLoop) -- removed the moment the loop stops

local function key(guid) return tostring(guid) end

-- ---- generic event bus ----------------------------------------------------------------------------------
-- A plain string-keyed pub/sub, the one piece neither Ess.On (engine-signal-specific: death/area/health/
-- vehicle/tick/labeled) nor Ess.Event (raw engine Event handles) provides. Lives here because Followers'
-- own lifecycle (recruit/dismiss/death) is the first thing worth observing without polling; Ess.Squad
-- forwards Ess.Squad.on to this SAME bus (see 67_squad.lua) rather than keeping a second one, so its own
-- higher-level events (onStepComplete, onVehicleMounted, ...) fire through the identical mechanism.
local listeners = {}   -- event name -> { fn, fn, ... }

-- Ess.Followers.on(eventName, fn) -> stop() -- fn(...) whenever that event fires. Unknown event names are
-- fine (just never fire) -- no fixed registry to keep in sync as new events get added elsewhere.
function Ess.Followers.on(eventName, fn)
    if not (eventName and fn) then return function() end end
    listeners[eventName] = listeners[eventName] or {}
    local bucket = listeners[eventName]
    bucket[#bucket + 1] = fn
    return function()
        for i, f in ipairs(bucket) do
            if f == fn then table.remove(bucket, i); break end
        end
    end
end

function Ess.Followers._emit(eventName, ...)
    local bucket = listeners[eventName]
    if not bucket then return Ess.Safe.reject("Ess.Followers", "no marker bucket for that follower "
        .. "-- marker not placed") end
    for _, fn in ipairs(bucket) do pcall(fn, ...) end
end

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

local function clearOrderMarks(scope)
    local existing = orderMarksByScope[scope]
    if not existing then return end
    for _, h in ipairs(existing) do Ess.Mark.clear(h) end
    orderMarksByScope[scope] = nil
end

-- markDestination(opts) -> handles -- returns the marks it created (rather than pushing straight into
-- orderMarksByScope) so _orderScoped can clear THIS SPECIFIC batch when ITS order naturally completes,
-- without racing a newer order in the SAME scope that's already replaced that scope's entry by then.
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
    local ok, driver = Ess.Safe.quiet(Vehicle.GetDriver, veh)
    if ok and driver == guid then return "driver" end
    return "passenger"
end

local function stopFollowLoop(guid)
    local k = key(guid)
    if followLoops[k] then Ess.Loop.stop(followLoops[k]); followLoops[k] = nil end
    if followLoopAnchors[k] then Ess.Object.remove(followLoopAnchors[k]); followLoopAnchors[k] = nil end
end

-- Ess.Followers._stopFollowLoop(guid) -- exposed on the Ess table (crosses the per-file do...end scope
-- boundary, see _issue's own header) so Ess.Squad.Formation can clear an existing vehicle-escort/on-foot
-- resume loop before handing the same guid over to ITS OWN formation-slot loop -- otherwise both would
-- fight over the guid's movement every tick.
Ess.Followers._stopFollowLoop = stopFollowLoop

-- Ess.Followers._followLoopAnchorOf(guid) -> uGuid|nil -- the disposable TinyGeometry a vehicle-escort/
-- on-foot-resume loop is currently repositioning every tick for this guid (nil if not in one right now).
-- followLoopAnchors is otherwise a private closure table with no other way to reach it -- added for the
-- Followers/Squad web tool's live map, mirroring Ess.Squad._formationAnchorOf's own reasoning: "where is
-- this unit's CURRENT waypoint," not just the unit itself, is what actually lets you watch a stuck escort/
-- resume loop live instead of just seeing a unit stand still with no visible explanation why.
function Ess.Followers._followLoopAnchorOf(guid)
    return followLoopAnchors[key(guid)]
end

-- startFollowLoop(guid, target, minDist, maxDist, stillEligibleFn) -- the reissued-MoveTo mechanism behind
-- BOTH a vehicle driver's escort AND (CONFIRMED LIVE 2026-07-25, see below) an on-foot follower's RESUME --
-- native Follow turned out not to be the universal answer this file originally assumed. Three confirmed-live
-- fixes stacked on top of each other:
--   1. Naively reissuing "MoveTo target" (targeting the player object directly, no stopping distance)
--      drives straight into the player -- Goal="MoveTo" closes ALL the way to the target's exact position,
--      unlike the native Follow role's own MinDistance/MaxDistance/MoveDistance holding pattern, which this
--      loop reimplements by hand since it isn't a Role: idle once within minDist, only starts closing again
--      once past maxDist (hysteresis, so it doesn't twitch at the boundary).
--   2. The computed stand-off point (minDist out from the player, toward the guid's current heading) first
--      tried "MoveToPos" directly, on the theory that -- unlike for an on-foot human generally, see
--      60_aiorders.lua's file header -- a vehicle driver was the ONE confirmed corpus use of that goal.
--      CONFIRMED LIVE this doesn't hold for a bare Ai.Goal call the way it seemed to from the corpus alone:
--      Ai.Goal({Goal="MoveToPos",...}) returned nil for a driver, while "MoveTo" targeting a real object
--      (the same anchorAt() trick 60_aiorders.lua's own move/defend/patrol/flee use) worked immediately.
--      So this reuses ONE disposable TinyGeometry anchor, repositioned every tick instead of retargeted by
--      coordinate, rather than spawning a fresh one each time.
--   3. CONFIRMED LIVE 2026-07-25, the reason this is used for an on-foot RESUME too, not just vehicles: a
--      follower taken off native Follow for ANY order (even a plain "move") has their Ai.Feeling toward
--      `target` snap back hostile within 1-3 SECONDS on its own once away from it -- side-by-side tested
--      against an untouched follower who stayed on native Follow the whole time and never drifted at all,
--      so the native Role itself is what's suppressing it, not the one-time LivingWorld/Vip/feeling setup
--      recruit() already did. Worse: even with feeling hammered stable and Vip/LivingWorld re-asserted
--      fresh, reissuing Ai.Role("Follow") returned a valid handle but never actually moved the unit -- while
--      a plain "move" Goal at that EXACT same spot worked immediately. Native Follow is therefore only
--      reliable on its FIRST engagement (straight from recruit(), see that function -- left unchanged, it's
--      the one confirmed-good path); every RESUME (order("follow",...)/auto-resume) now goes through this
--      loop instead of trying to re-engage the Role, on foot or not -- see smartFollow() below. The
--      tradeoff, accepted since there's no demonstrated alternative: a RESUMED follower loses native
--      Follow's own free vehicle-boarding-with-the-player convenience (the ContextAction prompt is tied to
--      the Role) until explicitly orderEnter()'d -- a fresh recruit still gets it.
-- `stillEligibleFn(guid)` decides what "has this guid left the situation this loop is for" means (a vehicle
-- escort stops once they're no longer the driver; an on-foot resume stops once they've boarded ANY vehicle).
-- Debounced to 3 CONSECUTIVE misses (this loop's own 1s interval, so ~3 real seconds), not a single reading
-- -- confirmed live 2026-07-24 that a single transient bad read (e.g. right as another follower nearby was
-- recruited/spawned) permanently killed a perfectly good loop, since Ess.Loop treats a false return as
-- final, not "retry me." Self-stops (and removes its anchor) once the guid or target dies.
local function startFollowLoop(guid, target, minDist, maxDist, stillEligibleFn)
    stopFollowLoop(guid)
    minDist = minDist or 10
    maxDist = maxDist or 20
    local k = key(guid)
    local id = "Ess.Followers.followLoop:" .. k
    followLoops[k] = id
    local gx0, gy0, gz0 = Ess.Object.pos(guid)
    local anchor = gx0 and Ess.Object.spawn("TinyGeometry", gx0, gy0, gz0)
    if anchor then followLoopAnchors[k] = anchor end
    local moving = false
    local missedChecks = 0
    Ess.Loop.start(id, 1, function()
        if not anchor or not Object.IsAlive(guid) or not Object.IsAlive(target) then return false end
        if not stillEligibleFn(guid) then
            missedChecks = missedChecks + 1
            if missedChecks >= 3 then return false end
            return true   -- possibly-transient miss -- skip this tick's movement, keep the loop alive
        end
        missedChecks = 0
        -- see point 3 above -- re-pin every tick, not just once, for as long as this guid is off native
        -- Follow; a threshold (not "always SetFeeling") so this never fights a caller's OWN deliberate
        -- negative-feeling change toward some OTHER guid (this only ever touches guid<->target).
        local fok, feeling = Ess.Safe.quiet(Ai.GetFeeling, guid, target)
        if fok and feeling and feeling < 50 then Ess.Safe.quiet(Ai.SetFeeling, guid, target, 100) end
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
            Ess.Safe.quiet(Ai.Goal, { AIGuid = guid, Goal = "MoveTo", Target = anchor, Priority = "HiPri", Force = true })
        end
        return true
    end)
end

-- startEscort(guid, ...) -- the vehicle-DRIVER-specific case: stops once `guid` is no longer that vehicle's
-- driver (they got out, or someone else took the wheel).
local function startEscort(guid, target, minDist, maxDist)
    startFollowLoop(guid, target, minDist, maxDist, function(g) return vehicleRoleOf(g) == "driver" end)
end

-- startFootFollowLoop(guid, ...) -- the on-foot-RESUME case (see point 3 in startFollowLoop's header):
-- stops the moment `guid` boards ANY vehicle (driver or passenger) -- at that point smartFollow's own
-- vehicle-aware dispatch takes back over next time it's called (order("follow",...) or the next
-- auto-resume), same as it always has for a vehicle occupant.
local function startFootFollowLoop(guid, target, minDist, maxDist)
    startFollowLoop(guid, target, minDist, maxDist, function(g) return vehicleRoleOf(g) == nil end)
end

-- smartFollow(guid, target, minDist, maxDist) -- the vehicle-aware "go back to following" ONE guid needs;
-- used by both an explicit order("follow", ...) and the internal auto-resume below. A passenger/gunner is
-- left COMPLETELY alone -- they're already going wherever their vehicle goes, and touching their Role/Goal
-- at all risks pulling them out of their seat for no reason. On foot goes through startFollowLoop, NOT a
-- reissued native Ai.Role("Follow") -- see startFollowLoop's header, point 3, for why re-engaging the Role
-- on a RESUMING follower turned out not to work at all (looked accepted, never actually moved them, AND
-- left them drifting back hostile). recruit()'s own FIRST engagement is unaffected -- it's the one
-- confirmed-reliable native-Role path, left exactly as it was.
local function smartFollow(guid, target, minDist, maxDist)
    local role = vehicleRoleOf(guid)
    if role == "driver" then
        startEscort(guid, target, minDist, maxDist)
    elseif role == "passenger" then
        -- ride along -- no order needed, and issuing one risks ejecting them for nothing
    else
        startFootFollowLoop(guid, target, minDist, maxDist)
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
    -- checked BEFORE the roster/state teardown below, since Object.IsAlive would trivially read false
    -- afterward regardless of why dismiss() was actually called -- this is the one place that can tell
    -- "died" (fires onFollowerDown, the auto-dismiss path from recruit()'s own Ess.On.death hook) apart
    -- from "dismissed while still alive" (fires onDismiss) without needing a second call-site flag.
    local ok, alive = Ess.Safe.quiet(Object.IsAlive, guid)
    local wasKilled = ok and alive == false
    entry.stop()
    roster[k] = nil
    for i, g in ipairs(order_) do
        if key(g) == k then table.remove(order_, i); break end
    end
    if marks[k] then Ess.Mark.clear(marks[k]); marks[k] = nil end
    stopFollowLoop(guid)
    Ess.Safe.quiet(Ai.Role, { AIGuid = guid, Role = "Idle", Priority = "hiPri" })
    Ess.Safe.quiet(Ai.LivingWorld, { AIGuid = guid, Attrib = "LivingWorldBehaviour", State = true })
    Ess.Safe.quiet(Ai.SetState, { AIGuid = guid, State = "Vip", Value = false })
    if wasKilled then Ess.Followers._emit("onFollowerDown", guid) end
    Ess.Followers._emit("onDismiss", guid, wasKilled)
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
        local ok, feeling = Ess.Safe.quiet(Ai.GetFeeling, guid, target)
        if ok and feeling and feeling < 0 then Ess.Safe.quiet(Ai.SetFeeling, guid, target, 100) end
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
    Ess.Followers._emit("onRecruit", guid)
    return true
end

function Ess.Followers.dismissAll()
    -- iterate a COPY -- dismiss() mutates order_/roster as it goes, walking the live table would skip
    -- entries the same way removing from an array while iterating it always does.
    local snapshot = {}
    for i, g in ipairs(order_) do snapshot[i] = g end
    for _, g in ipairs(snapshot) do Ess.Followers.dismiss(g) end
end

-- Ess.Followers.list() -> guids
-- Self-healing: also PRUNES order_ in place of any guid whose roster entry is already gone (confirmed live
-- 2026-07-25 that this can happen -- a death-triggered auto-dismiss racing a manual dismissAll() call left
-- order_ holding 2 already-nil-rostered guids, so count()/list() kept reporting dead followers no further
-- dismiss() call could clear, since dismiss() itself only removes an entry it can still find in roster).
-- Same lazy-prune-on-read idiom Ess.Squad.team() already uses over this same roster for the same reason.
function Ess.Followers.list()
    local out = {}
    local i = 1
    while i <= #order_ do
        local g = order_[i]
        if roster[key(g)] then
            out[#out + 1] = g
            i = i + 1
        else
            table.remove(order_, i)
        end
    end
    return out
end

function Ess.Followers.count()
    return #Ess.Followers.list()
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

-- Ess.Followers._issue(list, behavior, opts) -> ok
-- The "make a fresh order actually take" mechanics -- clears leftover goal/role state and (deferred,
-- confirmed-necessary settle time) issues `behavior` to exactly these guids. NO marker tracking, NO
-- auto-resume-follow wiring -- just the raw issuing primitive. Shared by Ess.Followers._orderScoped below
-- (whole-order/team semantics, which layers marker tracking + auto-resume on top) AND Ess.Squad.queue
-- (67_squad_queue.lua -- step-by-step semantics, which needs its OWN completion wiring per step instead of
-- auto-resume-follow between steps). Exposed on the Ess table, not local, so it crosses the per-file
-- do...end scope boundary build/merge.py wraps each src file in.
--
-- CONFIRMED LIVE 2026-07-24: recruit()'s Ai.Role("Follow", HardPriority=true) keeps reasserting itself over
-- a one-shot Ai.Goal issued the SAME tick -- an "attack" order silently did nothing while a follower's Role
-- stayed Follow, even though the Goal call itself returned a valid handle. Releasing the Role AND issuing
-- the new order in the same call never worked in live testing; a short deferred delay between the two
-- (Event.TimerRelative) is what made it reliably take effect -- so this returns optimistically and the
-- actual command fires a beat later, same as every other deferred call in this codebase.
function Ess.Followers._issue(list, behavior, opts)
    opts = opts or {}
    -- CONFIRMED LIVE 2026-07-24, the actual root cause behind the priority-vs-priority confusion above:
    -- Ess.AIOrders' own per-behavior defaults (e.g. attack's "med") are NOT reliably enough to override a
    -- released Follow Role's leftover state, even with Force=true and Ai.RemoveGoal already applied -- only
    -- "hi"/HiPri consistently worked in testing. Every order issued through a follower's already-HardPriority
    -- Follow role needs to win decisively, so default to "hi" here specifically (NOT changed in
    -- Ess.AIOrders.command itself, whose own callers never have this Role-preemption problem to begin with).
    opts.priority = opts.priority or "hi"

    -- CONFIRMED LIVE 2026-07-24: a follower can still be mid-way through a PRIOR order's goal (e.g. still
    -- walking to an old guard point) when a new one comes in -- Force=true on the new goal doesn't reliably
    -- preempt one left over from an EARLIER order() call the way it preempts hold's Anchor lock. Clear it
    -- first with Ai.RemoveGoal({Handle=0}) -- 0 is the confirmed "whatever's current" wildcard the game's
    -- own scripts use when they didn't keep a specific handle to remove (see e.g. allcon002.lua).
    for _, g in ipairs(list) do Ess.Safe.quiet(Ai.RemoveGoal, { AIGuid = g, Handle = 0 }) end

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

    -- stop any active follow-loop (vehicle escort OR on-foot resume) before a NEW non-follow order -- a
    -- guid mid-loop who's now being ordered to e.g. attack shouldn't have that loop fighting the new order
    -- for control every 1-3 seconds.
    for _, g in ipairs(list) do stopFollowLoop(g) end
    for _, g in ipairs(list) do Ess.Safe.quiet(Ai.Role, { AIGuid = g, Role = "Idle", Priority = "hiPri" }) end

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

-- Ess.Followers._orderScoped(scope, list, behavior, opts) -> ok
-- The whole-order layer on top of _issue: marker tracking + auto-resume-follow on natural completion,
-- scoped so Ess.Squad.orderTeam(teamName, ...) can command an arbitrary SUBSET of the roster without racing
-- Ess.Followers.order()'s own whole-roster orders (or another team's). `scope` is just a string key for
-- orderMarksByScope/clearOrderMarks -- "__all__" (Ess.Followers.order's own scope) and a team name are
-- otherwise handled identically. See Ess.Followers.order() below for the public, whole-roster entry point
-- this wraps.
function Ess.Followers._orderScoped(scope, list, behavior, opts)
    opts = opts or {}
    opts.priority = opts.priority or "hi"
    clearOrderMarks(scope)                -- clear whatever the LAST order in THIS scope left behind (see
                                           -- below for why a naturally-completed order might already have)
    local thisOrderMarks = markDestination(opts)
    orderMarksByScope[scope] = thisOrderMarks

    if behavior ~= "follow" then
        -- onDone: fires on natural completion only (see header) -- clears THIS order's own destination
        -- marker(s) (confirmed live 2026-07-24: they used to linger after the unit arrived) and resumes
        -- Follow. Compares against THIS SCOPE's current entry (not just clearing blindly) so a newer order
        -- in the SAME scope that already ran its own clearOrderMarks()/replaced the entry isn't stepped on
        -- by this older callback firing late -- a DIFFERENT scope's entry is never touched at all.
        local function onDone()
            for _, h in ipairs(thisOrderMarks) do Ess.Mark.clear(h) end
            if orderMarksByScope[scope] == thisOrderMarks then orderMarksByScope[scope] = nil end
            resumeFollow(list)
        end
        if behavior == "attack" and opts.target then
            Ess.On.death(opts.target, onDone)
        elseif behavior == "move" or (behavior == "patrol" and opts.loop == false) then
            opts.onComplete = onDone
        end
    end

    return Ess.Followers._issue(list, behavior, opts)
end

-- Ess.Followers.order(behavior, opts) -> ok
-- Commands the WHOLE current roster at once -- any of Ess.AIOrders' 11 behaviors (guard/patrol/attack/...),
-- same opts shape as Ess.AIOrders.command. Empty roster is a safe no-op (command() already handles an empty
-- guids list per-behavior). Just the "__all__"-scoped case of _orderScoped above -- see it for the actual
-- mechanics and every CONFIRMED LIVE note behind them.
function Ess.Followers.order(behavior, opts)
    return Ess.Followers._orderScoped("__all__", Ess.Followers.list(), behavior, opts)
end
