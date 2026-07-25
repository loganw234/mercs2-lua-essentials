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

local Ess = _G.Ess
Ess.Followers = Ess.Followers or {}

local roster = {}      -- guid-key -> { stop = <Ess.On.death stop fn>, target = <the guid it follows> }
local order_ = {}      -- insertion-ordered guid list, for a stable list()
local marks = {}       -- guid-key -> Ess.Mark.object handle (only populated while markers are enabled)
local orderMarks = {}  -- Ess.Mark.zone handles from the CURRENT order's destination(s)
local markersOn = true
local colorStep = 0

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

-- ---- roster lifecycle -----------------------------------------------------------------------------------

-- Ess.Followers.dismiss(guid) -> ok
-- Reverts exactly what recruit()'s sequence set: Role back to "Idle" (matches resident/mrxfollow.lua's own
-- _ToggleFollowingBehavior(false) in the decompiled game corpus), LivingWorldBehaviour back on, Vip state
-- off, and clears its marker if one was placed. A guid that was never recruited is a safe no-op.
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
function Ess.Followers.recruit(guid, opts)
    if not guid then return false end
    local k = key(guid)
    if roster[k] then return true end                 -- already a follower -- idempotent, not an error
    opts = opts or {}
    local target = opts.target or Ess.Player.character(0)
    local ok = Ess.AIOrders.command({ guid }, "follow", opts)
    if not ok then return false end
    roster[k] = { stop = Ess.On.death(guid, function() Ess.Followers.dismiss(guid) end), target = target }
    order_[#order_ + 1] = guid
    if markersOn then marks[k] = Ess.Mark.object(guid, { world = true, radar = false, pda = false, rgb = nextColor() }) end
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
-- Internal to order()'s auto-resume; a caller wanting to resume everyone deliberately should just call
-- order("follow", {target=...}) themselves.
local function resumeFollow(guids)
    for _, g in ipairs(guids) do
        local entry = roster[key(g)]
        if entry then Ess.AIOrders.command({ g }, "follow", { target = entry.target }) end
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
        return Ess.AIOrders.command(list, behavior, opts)
    end

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
