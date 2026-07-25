-- RECIPE: build your OWN abstraction on top of Ess, and use it three ways.
-- Namespaces: Ess.Object, Ess.Table, Ess.Easy.Mark, Ess.Track, Ess.Math, Ess.RNG.
--
-- Part of the compose_* track (see compose_a_closure.lua).
--
-- THE POINT. Everything else in samples/recipes/ shows you how to call Ess. This one shows you how to stop
-- calling Ess directly -- how to write the two or three helpers YOUR mod needs, in your own vocabulary, and
-- then write the rest of the mod in that vocabulary instead.
--
-- This is the real ceiling on a node graph, and it isn't about which functions exist. A graph has no way to
-- say "here is a new operation, defined in terms of the old ones, that I can now use everywhere." (The visual
-- editor's Function Start/Return blocks are the nearest thing, and they're per-graph -- they can't be shared
-- between scripts or built up into a library.) Once you can define `spawnRing`, the graph's per-node wiring
-- stops being an advantage and starts being work.
--
-- Note what the helpers below have in common: each takes a DATA description of what you want, loops, and
-- hands back something you can keep using. That's the shape you can't draw.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- ===========================================================================
-- YOUR LIBRARY. Three helpers, each one thing Ess doesn't do because it's YOUR mod's idea, not a framework
-- primitive. In a real mod these live in one OnLoad file and every other script uses them.
-- ===========================================================================

-- spawnRing(template, n, radius, opts) -> tGuids
-- Place n things evenly around the player. Ess has spawnAhead (one thing, one direction); a ring is a loop
-- over it, which is exactly the kind of small idea worth naming once.
local function spawnRing(sTemplate, n, radius, opts)
    opts = opts or {}
    local px, py, pz = Ess.Player.pose(0)
    if not px then return {} end
    local out = {}
    for i = 1, n do
        -- Ess.Math.pointAhead projects from a yaw, so sweeping the yaw sweeps the ring. No trig here on
        -- purpose -- pointAhead already owns the engine's forward convention (and its once-mirrored sign).
        local yaw = (360 / n) * (i - 1)
        local x, z = Ess.Math.pointAhead(px, pz, yaw, radius)
        local g = Ess.Object.spawn(sTemplate, x, py + (opts.height or 0), z, yaw + 180)
        if g then
            out[#out + 1] = g
            -- Passing the tracker IN is what makes the helper safe to use without remembering cleanup at
            -- every call site: whatever it spawns is already registered for teardown before you see it.
            if opts.tracker then opts.tracker:guid(g) end
            if opts.mark then
                local h = Ess.Easy.Mark.enemy(g)
                if opts.tracker then opts.tracker:any(h) end
            end
        end
    end
    return out
end

-- eachAlive(tGuids, fn) -> nTouched
-- "Do this to all of them, skipping anything already dead." Every mod that manages a group writes this loop;
-- writing it once means the aliveness check can never be forgotten at one of the call sites.
local function eachAlive(tGuids, fn)
    local n = 0
    for _, g in ipairs(tGuids or {}) do
        if Ess.Object.alive(g) then
            fn(g)
            n = n + 1
        end
    end
    return n
end

-- healthReport(tGuids) -> tSummary
-- Fold a group down to one readable summary. Built on Ess.Table.reduce, so it's a description rather than
-- a loop with three accumulators to keep straight.
local function healthReport(tGuids)
    local live = Ess.Table.filter(tGuids or {}, function(g) return Ess.Object.alive(g) end)
    local hp = Ess.Table.reduce(live, function(sum, g) return sum + (Ess.Object.health(g) or 0) end, 0)
    return {
        total = #(tGuids or {}),
        alive = #live,
        dead = #(tGuids or {}) - #live,
        totalHp = hp,
        avgHp = (#live > 0) and (hp / #live) or 0,
    }
end

-- ===========================================================================
-- NOW USE THEM. Three different jobs, no Ess.Object.spawn in sight -- the mod is written in the vocabulary
-- above, which is the thing worth taking away from this file.
-- ===========================================================================

local tracker = Ess.Track.new()      -- one teardown for everything below

-- Use 1: a ring of cars.
local ring = spawnRing("Veyron", 5, 16, { tracker = tracker })
Ess.Log(string.format("[recipe] compose_your_own_helper: spawned a ring of %d", #ring))

-- Use 2: the same helper, different template/shape -- a tighter, taller ring. Reuse is the whole return on
-- having named it.
local inner = spawnRing("Veyron", 3, 8, { tracker = tracker, height = 0 })

-- Use 3: operate on the group through your own verb, not through a loop you re-derive each time.
local damaged = eachAlive(ring, function(g) Ess.Object.setHealth(g, 60) end)
eachAlive(inner, function(g) Ess.Object.heal(g) end)

local before = healthReport(ring)
eachAlive(ring, function(g) Ess.Object.heal(g) end)
local after = healthReport(ring)

Ess.Log(string.format("[recipe] compose_your_own_helper: ring %d/%d alive, avg HP %.0f -> %.0f",
    after.alive, after.total, before.avgHp, after.avgHp))

-- Composition on top of composition: pick a random member with Ess.RNG (never math.random -- see 53_rng.lua)
-- and mark it, using the list a helper gave back.
local rng = Ess.RNG.new()
local chosen = rng:pick(ring)
if chosen then tracker:any(Ess.Easy.Mark.objective(chosen)) end

local ok = (#ring == 5) and (#inner == 3) and (damaged == 5)
    and (after.avgHp >= before.avgHp) and (after.alive == 5)

-- One line ends all of it -- both rings and the marker (see compose_one_cleanup.lua).
tracker:closeAll()
Ess.Log("[SMOKE] compose_your_own_helper: " .. (ok and "PASS" or "FAIL"))
