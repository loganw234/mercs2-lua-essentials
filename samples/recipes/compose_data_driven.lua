-- RECIPE: describe an encounter as DATA, then run the data.
-- Namespaces: Ess.Object, Ess.Table, Ess.AIOrders, Ess.Track, Ess.Math, Ess.Easy.Mark.
--
-- Part of the compose_* track (see compose_a_closure.lua).
--
-- THE SHIFT. A node graph is one node per thing that happens: five spawns means five nodes, and a sixth
-- enemy means editing the graph. Data-driven means the SHAPE of the encounter lives in a table, and one small
-- interpreter walks it -- so a sixth enemy is one more line of table, and a whole second encounter is a whole
-- second table with no new code at all.
--
-- This is the same move Ess.Contract and Ess.Cinematic already make internally (a contract def is data; a
-- cutscene is a list of step tables). This recipe shows you doing it for yourself, at a smaller scale, which
-- is usually where it starts.
--
-- Once your encounter is data you get things that are awkward any other way: validate it before running,
-- count what's in it, difficulty-scale it by transforming the table, save it, or generate it.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- ===========================================================================
-- THE DATA. Nothing here executes; it's a description. Read it as a spec sheet -- which is the advantage:
-- someone who doesn't know the Ess API can still tell exactly what this encounter is.
-- ===========================================================================
local ENCOUNTER = {
    { template = "Veyron", at = { dist = 14, bearing = 0   }, hp = 100, order = "hold",   mark = true  },
    { template = "Veyron", at = { dist = 18, bearing = 72  }, hp = 60,  order = "hold",   mark = false },
    { template = "Veyron", at = { dist = 18, bearing = 144 }, hp = 60,  order = "hold",   mark = false },
    { template = "Veyron", at = { dist = 22, bearing = 216 }, hp = 40,  order = "hold",   mark = true  },
    { template = "Veyron", at = { dist = 22, bearing = 288 }, hp = 40,  order = "hold",   mark = false },
}

-- ===========================================================================
-- THE INTERPRETER. Small, written once, and completely indifferent to how big the table gets.
-- ===========================================================================

-- validate(spec) -> tProblems -- checking the DATA before touching the engine is something you can only do
-- when the encounter IS data. A blank template would hard-CRASH the engine (pcall cannot catch a native
-- crash), so Ess.Safe.template is the gate, and here it runs across the whole encounter up front.
local function validate(spec)
    local problems = {}
    for i, e in ipairs(spec) do
        if not Ess.Safe.template(e.template) then
            problems[#problems + 1] = string.format("entry %d: unusable template %q", i, tostring(e.template))
        end
        if type(e.at) ~= "table" or not e.at.dist then
            problems[#problems + 1] = string.format("entry %d: no at.dist", i)
        end
    end
    return problems
end

-- scale(spec, factor) -> new spec -- a pure transform of the table. Difficulty tuning without touching the
-- spawn code at all, which is the payoff for keeping description and execution separate.
local function scale(spec, factor)
    return Ess.Table.map(spec, function(e)
        local copy = Ess.Table.copy(e)
        copy.hp = math.min(100, math.floor((e.hp or 100) * factor))
        return copy
    end)
end

-- run(spec, tracker) -> tSpawned -- the ONLY part that talks to the engine.
local function run(spec, tracker)
    local px, py, pz = Ess.Player.pose(0)
    if not px then return {} end
    local spawned = {}
    for _, e in ipairs(spec) do
        local x, z = Ess.Math.pointAhead(px, pz, e.at.bearing or 0, e.at.dist or 10)
        local g = Ess.Object.spawn(e.template, x, py + (e.at.height or 0), z, (e.at.bearing or 0) + 180)
        if g then
            tracker:guid(g)
            if e.hp then Ess.Object.setHealth(g, e.hp) end
            if e.mark then tracker:any(Ess.Easy.Mark.enemy(g)) end
            spawned[#spawned + 1] = { guid = g, spec = e }
        end
    end
    -- Orders are issued per distinct order type, not per unit -- grouping falls out of the data for free.
    local byOrder = {}
    for _, s in ipairs(spawned) do
        local key = s.spec.order or "hold"
        byOrder[key] = byOrder[key] or {}
        table.insert(byOrder[key], s.guid)
    end
    for order, guids in pairs(byOrder) do
        Ess.AIOrders.command(guids, order, { at = { px, py, pz } }, tracker)
    end
    return spawned
end

-- ===========================================================================
-- USE IT.
-- ===========================================================================
local problems = validate(ENCOUNTER)
if #problems > 0 then
    for _, p in ipairs(problems) do Ess.Log("[recipe] compose_data_driven: INVALID -- " .. p) end
    Ess.Log("[SMOKE] compose_data_driven: FAIL (spec did not validate)")
    return
end

-- Questions you can ask a table but not a graph.
local marked = #Ess.Table.filter(ENCOUNTER, function(e) return e.mark end)
local totalHp = Ess.Table.reduce(ENCOUNTER, function(sum, e) return sum + (e.hp or 0) end, 0)
Ess.Log(string.format("[recipe] compose_data_driven: %d entries, %d marked, %d total HP",
    #ENCOUNTER, marked, totalHp))

-- And a validation that PROVES the guard works, on a deliberately broken spec.
local broken = { { template = "   ", at = { dist = 5 } } }
local brokenProblems = validate(broken)

-- Difficulty scaling, as a pure table transform.
local hard = scale(ENCOUNTER, 1.5)
local hardHp = Ess.Table.reduce(hard, function(sum, e) return sum + (e.hp or 0) end, 0)
Ess.Log(string.format("[recipe] compose_data_driven: scaled to hard -> %d total HP", hardHp))

local tracker = Ess.Track.new()
local spawned = run(ENCOUNTER, tracker)
Ess.Log(string.format("[recipe] compose_data_driven: ran the spec, %d units up", #spawned))

local ok = (#spawned == #ENCOUNTER)
    and (#brokenProblems == 1)          -- the blank template WAS caught, before any spawn
    and (hardHp > totalHp)              -- scaling really scaled
    and (marked == 2)

tracker:closeAll()                       -- units, markers and AI-order anchors, all in one line
Ess.Log("[SMOKE] compose_data_driven: " .. (ok and "PASS" or "FAIL"))
