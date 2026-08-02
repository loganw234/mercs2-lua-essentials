-- Ess/18_spawn.lua -- Ess.Spawn: put MANY things in the world in one call.
--
-- The gap: Ess.Object.spawn places exactly one object at exactly one coordinate. Everything past that --
-- a squad, a convoy, a prop field, a mixed section -- meant hand-rolling a loop plus placement trig, which
-- is where the mistakes live. Ess.Easy.Spawn.enemies was the one bulk verb, hard-wired to hostile infantry
-- charging the player; this generalises that shape without changing it.
--
-- API:
--   Ess.Spawn.many(vTemplates, nCount, tOpts) -> tGuids   the dispatcher; a roster or a single template
--   Ess.Spawn.mixed(tSpecs, tOpts) -> tGuids              {{template, count}, ...} in one placement
--   Ess.Spawn.at(vTemplates, tPoints, tOpts) -> tGuids    one per explicit {x,y,z} point
--   Ess.Spawn.PATTERNS -> tNames                          the placement names many() accepts
--
-- vTemplates is EITHER a single template string OR an array of them -- a named roster:
--     AL_RIFLE_SECTION = { "AL Soldier", "AL Soldier", "AL Heavy", "AL Sniper" }
--     Ess.Spawn.many(AL_RIFLE_SECTION)                     -- one of each: the section, exactly as written
--     Ess.Spawn.many(AL_RIFLE_SECTION, 12)                 -- 12 units, cycling that composition 3x over
-- Omitting nCount with an array spawns ONE OF EACH, so a roster reads as the literal unit it describes.
-- Give nCount and the roster becomes a composition that repeats -- `pick="cycle"` (default) keeps the ratio
-- exact and deterministic; `pick="random"` draws freely for variety.
--
-- EVERY TEMPLATE IS VALIDATED BEFORE ANYTHING SPAWNS. A blank/whitespace template hard-CRASHES the engine
-- in native C++ and pcall canNOT catch a native crash (CONTRIBUTING.md's engine rules). In a bulk spawner
-- that danger is worse than in a single one: validating lazily would spawn seven units, hit the bad eighth
-- entry, and take the game down having already half-applied the call. So the whole roster is checked first
-- and a bad entry means NOTHING spawns -- an all-or-nothing call you can retry, not a mess to clean up.
--
-- Randomness goes through Ess.RNG, never math.random: this engine's 32-bit floats make a naive LCG silently
-- degenerate (see 53_rng.lua). Pass `seed` for a reproducible layout.

local Ess = _G.Ess
Ess.Spawn = Ess.Spawn or {}

-- The cap exists because nothing else stops you. `Ess.Spawn.many(t, 5000)` is a plausible typo and the
-- engine will genuinely try, then die. Raise it deliberately with opts.max when you mean it.
local DEFAULT_MAX = 64

Ess.Spawn.PATTERNS = { "scatter", "grid", "line", "circle" }

-- Deliberately NOT the wedge/column/diamond vocabulary from Ess.Squad.Formation. Those are MARCHING
-- formations -- computed relative to a moving leader and re-issued as the squad walks. These are static
-- placements evaluated once, at spawn. Sharing the words would imply the spawner produces a formation that
-- holds, which it does not; spawn with `grid`, then Ess.Squad.setFormation if you want it maintained.

-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Placement. Each returns dx, dz -- an offset from the centre, in world units.
-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────
local function placeScatter(i, n, o, rng)
    -- The proposal's own shape: a ring between minDist and maxDist of the centre.
    --
    -- The ANGLE IS SECTORED, NOT FULLY RANDOM. Each unit owns a 1/n slice of the circle and is jittered
    -- inside it, so no two ever share an angle. A naive `rng:next() * 2pi` per unit reads as the obvious
    -- implementation and is what this had first -- but random placement has no minimum-separation
    -- guarantee, so two units can and do land on the same spot. The offline test caught exactly that
    -- (6 spawns, 2 identical positions). For infantry it looks sloppy; for vehicles it is worse than
    -- sloppy, since two cars spawned inside each other get violently shoved apart by the physics.
    -- Sectoring costs nothing, still looks organic, and makes the overlap structurally impossible.
    --
    -- Radius is drawn UNIFORMLY rather than area-weighted. Area weighting is the statistically even choice
    -- but pushes most units toward the outer edge, which reads as a hollow ring in game; uniform spreads
    -- them through the band the way a player expects "somewhere 8-25 units away" to look.
    local minD = o.minDist or 8
    local maxD = o.maxDist or math.max(minD + 12, 25)
    if maxD < minD then minD, maxD = maxD, minD end
    local sector = (2 * math.pi) / math.max(n, 1)
    -- 0.8 keeps the jitter strictly inside the unit's own sector, so sectors can never overlap at the edges
    local ang = (i - 1) * sector + (rng:next() - 0.5) * sector * 0.8
    local rad = minD + rng:next() * (maxD - minD)
    return math.sin(ang) * rad, math.cos(ang) * rad
end

local function placeGrid(i, n, o)
    local spacing = o.spacing or 4
    local cols = o.columns or math.max(1, math.ceil(math.sqrt(n)))
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local rows = math.ceil(n / cols)
    -- centred on the middle of the block, so the group straddles the centre instead of growing out of it
    return (col - (cols - 1) / 2) * spacing, (row - (rows - 1) / 2) * spacing
end

local function placeLine(i, n, o)
    local spacing = o.spacing or 4
    return (i - 1 - (n - 1) / 2) * spacing, 0
end

local function placeCircle(i, n, o)
    -- radius follows from spacing so a 3-unit and a 30-unit circle both look deliberate rather than
    -- squashing everyone together at a fixed radius
    local spacing = o.spacing or 4
    local rad = o.radius or math.max(spacing, (n * spacing) / (2 * math.pi))
    local ang = ((i - 1) / math.max(n, 1)) * 2 * math.pi
    return math.sin(ang) * rad, math.cos(ang) * rad
end

local function offsetFor(pattern, i, n, o, rng)
    if pattern == "grid"   then return placeGrid(i, n, o) end
    if pattern == "line"   then return placeLine(i, n, o) end
    if pattern == "circle" then return placeCircle(i, n, o) end
    return placeScatter(i, n, o, rng)
end

-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Centre resolution: at{} > around(guid) > ahead of the player (the default).
-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────
local function resolveCentre(o)
    if o.at then
        local a = o.at
        local x, y, z = a.x or a[1], a.y or a[2], a.z or a[3]
        if x and y and z then return x, y, z, o.yaw or 0 end
        return nil, nil, nil, nil, "opts.at needs x, y and z"
    end
    if o.around then
        local x, y, z = Ess.Object.pos(o.around)
        if not x then return nil, nil, nil, nil, "opts.around is not a live object" end
        return x, y, z, o.yaw or (Ess.Object.yaw(o.around) or 0)
    end
    local i = o.i or 0
    local px, py, pz, yaw = Ess.Player.pose(i)
    if not px then
        return nil, nil, nil, nil, "no pose for player " .. tostring(i)
            .. " (no character yet, or a co-op partner in single-player)"
    end
    if o.useView then yaw = Ess.Player.viewYaw(i) end
    local dist = o.ahead
    if dist == nil then dist = 20 end
    if dist ~= 0 then
        local x, z = Ess.Math.pointAhead(px, pz, yaw or 0, dist)
        return x, py, z, yaw or 0
    end
    return px, py, pz, yaw or 0
end

-- normaliseTemplates(v) -> tList | nil, sWhy -- one string becomes a one-entry roster, so everything
-- downstream handles exactly one shape.
local function normaliseTemplates(v)
    if type(v) == "string" then
        if not Ess.Safe.template(v) then return nil, "blank or whitespace-only template" end
        return { v }
    end
    if type(v) ~= "table" or #v == 0 then
        return nil, "expected a template string or a non-empty array of them"
    end
    for idx = 1, #v do
        if not Ess.Safe.template(v[idx]) then
            -- Names the INDEX. In a 16-entry roster "one of them is blank" is not an actionable message.
            return nil, "roster entry #" .. idx .. " is not a usable template (blank, or not a string)"
        end
    end
    return v
end

-- Ess.Spawn.many(vTemplates, nCount, tOpts) -> tGuids   (always a table; empty on refusal)
--
-- tOpts, all optional:
--   WHERE    at={x,y,z} | around=uGuid | ahead=nDist (default 20 in front) ; i=playerIndex, useView=bool
--   SHAPE    pattern="scatter"(default)|"grid"|"line"|"circle"
--            scatter: minDist(8), maxDist(25)      grid: spacing(4), columns      line: spacing(4)
--            circle:  spacing(4), radius
--   EACH     yaw (fixed), faceCentre=true, faceAway=true, height(0), snapToGround=true
--   DRAW     pick="cycle"(default)|"random", seed
--   ADMIN    tracker=Ess.Track, onEach=function(uGuid, nIndex, sTemplate), max(64)
function Ess.Spawn.many(vTemplates, nCount, tOpts)
    local o = tOpts or {}
    local list, why = normaliseTemplates(vTemplates)
    if not list then
        Ess.Safe.reject("Ess.Spawn.many", why .. " -- nothing spawned")
        return {}
    end

    -- No count with a roster means "the roster IS the order": one of each, in the order written.
    local n = nCount or #list
    if type(n) ~= "number" or n < 1 then
        Ess.Safe.reject("Ess.Spawn.many", "count must be a positive number, got " .. tostring(nCount))
        return {}
    end
    n = math.floor(n)
    local cap = o.max or DEFAULT_MAX
    if n > cap then
        Ess.Safe.reject("Ess.Spawn.many", "refusing " .. n .. " spawns (cap " .. cap
            .. ") -- raise it with opts.max if you mean it")
        return {}
    end

    local cx, cy, cz, cyaw, err = resolveCentre(o)
    if not cx then
        Ess.Safe.reject("Ess.Spawn.many", err .. " -- nothing spawned")
        return {}
    end

    local rng = Ess.RNG.new(o.seed)
    local random = (o.pick == "random")
    local pattern = o.pattern or "scatter"
    local out = {}

    for i = 1, n do
        -- cycle keeps a roster's composition exact and repeatable; random trades that for variety
        local tmpl = random and rng:pick(list) or list[((i - 1) % #list) + 1]
        local dx, dz = offsetFor(pattern, i, n, o, rng)
        local x, z = cx + dx, cz + dz

        local yaw = o.yaw or cyaw
        if o.faceCentre or o.faceAway then
            -- angleTo gives the yaw that FACES the centre; the away case is the opposite heading
            yaw = Ess.Math.angleTo(x, z, cx, cz)
            if o.faceAway then yaw = Ess.Math.normDeg(yaw + 180) end
        end

        local g = Ess.Object.spawn(tmpl, x, cy + (o.height or 0), z, yaw)
        if g then
            out[#out + 1] = g
            -- Tracking each guid as it lands (not in a batch at the end) means an onEach that errors
            -- can't leave already-spawned objects untracked and unowned.
            if o.tracker then o.tracker:guid(g) end
            if o.snapToGround then Ess.Object.snapToGround(g) end
            if o.onEach then Ess.Safe.named("Ess.Spawn.many.onEach", o.onEach, g, #out, tmpl) end
        end
    end

    if #out < n then
        Ess.Log("Spawn.many: " .. #out .. " of " .. n .. " spawned (the engine refused the rest)")
    end
    return out
end

-- Ess.Spawn.mixed(tSpecs, tOpts) -> tGuids
-- tSpecs = { {"VZ Soldier", 6}, {"Veyron", 2} } -- explicit counts per template, one shared placement.
-- The difference from a roster: a roster repeats to fill a count, this states each count outright. Use it
-- when the composition is "6 riflemen and 2 cars", not "these types in this ratio".
function Ess.Spawn.mixed(tSpecs, tOpts)
    if type(tSpecs) ~= "table" or #tSpecs == 0 then
        Ess.Safe.reject("Ess.Spawn.mixed", "expected { {template, count}, ... }")
        return {}
    end
    -- Flatten to a roster whose cycle order reproduces the requested counts exactly, then hand off -- so
    -- placement, capping, tracking and validation all stay in ONE implementation.
    local roster = {}
    for idx = 1, #tSpecs do
        local spec = tSpecs[idx]
        local tmpl = type(spec) == "table" and spec[1] or spec
        local count = (type(spec) == "table" and spec[2]) or 1
        if not Ess.Safe.template(tmpl) then
            Ess.Safe.reject("Ess.Spawn.mixed", "spec #" .. idx .. " has no usable template -- nothing spawned")
            return {}
        end
        for _ = 1, math.max(1, math.floor(count)) do roster[#roster + 1] = tmpl end
    end
    local o = {}
    for k, v in pairs(tOpts or {}) do o[k] = v end
    o.pick = "cycle"      -- forced: "random" would defeat the point of stating exact counts
    return Ess.Spawn.many(roster, #roster, o)
end

-- Ess.Spawn.at(vTemplates, tPoints, tOpts) -> tGuids
-- One spawn per explicit point: tPoints = { {x,y,z}, {x=,y=,z=}, ... }. For hand-authored placements and
-- for feeding Ess.Points' arena buckets straight in. Templates cycle across the points.
function Ess.Spawn.at(vTemplates, tPoints, tOpts)
    local o = tOpts or {}
    local list, why = normaliseTemplates(vTemplates)
    if not list then
        Ess.Safe.reject("Ess.Spawn.at", why .. " -- nothing spawned")
        return {}
    end
    if type(tPoints) ~= "table" or #tPoints == 0 then
        Ess.Safe.reject("Ess.Spawn.at", "expected a non-empty array of {x,y,z} points")
        return {}
    end
    local out = {}
    for i = 1, #tPoints do
        local p = tPoints[i]
        local x, y, z = p.x or p[1], p.y or p[2], p.z or p[3]
        if x and y and z then
            local tmpl = list[((i - 1) % #list) + 1]
            local g = Ess.Object.spawn(tmpl, x, y + (o.height or 0), z, o.yaw)
            if g then
                out[#out + 1] = g
                if o.tracker then o.tracker:guid(g) end
                if o.snapToGround then Ess.Object.snapToGround(g) end
                if o.onEach then Ess.Safe.named("Ess.Spawn.at.onEach", o.onEach, g, #out, tmpl) end
            end
        else
            Ess.Safe.reject("Ess.Spawn.at", "point #" .. i .. " is missing x, y or z -- skipped")
        end
    end
    return out
end
