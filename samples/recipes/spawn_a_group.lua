-- RECIPE: put a whole GROUP into the world in one call -- a section, a convoy, a prop field.
-- Namespaces: Ess.Spawn, Ess.Easy.Spawn, Ess.Track.
--
-- Ess.Object.spawn places one thing at one coordinate. Everything past that -- a squad, a patrol, a mixed
-- section -- used to mean hand-rolling a loop plus placement trig. Ess.Spawn is that loop, done once.
--
-- The idea worth taking away: a ROSTER is just a Lua list of template names, so a group's composition is
-- data you define once and reuse. That is the thing a node graph cannot hold for you.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- One tracker for the whole recipe, so every single thing it spawns comes back out in one call at the end.
-- Bulk spawning without bulk cleanup is how you end up with forty objects you can't find.
local tracker = Ess.Track.new()

-- ── 1. A named roster -- the composition of an allied rifle section, written once ────────────────────────
local AL_RIFLE_SECTION = { "AL Soldier", "AL Soldier", "AL Soldier", "AL Heavy", "AL Sniper" }

-- No count = one of each, in the order written: the section exactly as described.
local section = Ess.Spawn.many(AL_RIFLE_SECTION, nil, {
    minDist = 12, maxDist = 30,        -- a ring around you, not a pile at your feet
    snapToGround = true, faceCentre = true,
    tracker = tracker,
})
Ess.Log(string.format("[recipe] spawn_a_group: section of %d", #section))

-- Give a count and the roster REPEATS to fill it, keeping its ratio exact -- 10 units is two sections'
-- worth, still 3 riflemen : 1 heavy : 1 sniper.
local platoon = Ess.Spawn.many(AL_RIFLE_SECTION, 10, { minDist = 35, maxDist = 60, tracker = tracker })

-- ── 2. Exact counts instead of a ratio ───────────────────────────────────────────────────────────────────
local convoy = Ess.Spawn.mixed({ { "Veyron", 2 }, { "VZ Soldier", 4 } }, {
    pattern = "line", spacing = 8, tracker = tracker,      -- a column along one axis
})

-- ── 3. The Easy tier -- same machinery, no options to think about ────────────────────────────────────────
local props = Ess.Easy.Spawn.props(5)
for _, g in ipairs(props) do tracker:guid(g) end

-- ── 4. The group is just a list, so everything else in Ess takes it ──────────────────────────────────────
-- This is the payoff of returning guids: mark them, order them, count them, recruit them.
for _, g in ipairs(section) do Ess.Easy.Mark.enemy(g) end

local ok = #section == #AL_RIFLE_SECTION and #platoon == 10 and #convoy == 6 and #props == 5

-- ── 5. One call takes all of it back out ─────────────────────────────────────────────────────────────────
Ess.Easy.Triggers.after(8, function()
    tracker:closeAll()
    Ess.Log("[recipe] spawn_a_group: everything cleaned up")
end)

Ess.Log(string.format("[recipe] spawn_a_group: section=%d platoon=%d convoy=%d props=%d (clearing in 8s)",
    #section, #platoon, #convoy, #props))
Ess.Log("[SMOKE] spawn_a_group: " .. (ok and "PASS" or "FAIL"))
