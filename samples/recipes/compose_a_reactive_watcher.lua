-- RECIPE: set something up that keeps reacting after the script has finished running.
-- Namespaces: Ess.On, Ess.State, Ess.Track, Ess.Loop, Ess.stop, Ess.Object.
--
-- Part of the compose_* track (see compose_a_closure.lua).
--
-- THE IDEA A GRAPH CAN'T HOLD. A compiled graph is a SEQUENCE: it runs top to bottom and it's done. But an
-- OnKey script finishing doesn't mean your mod is over -- a hook you registered keeps firing, a loop you
-- started keeps ticking, and closures you created stay alive holding their state. The script is the SETUP;
-- the mod is what runs afterwards.
--
-- That's also the part that's easy to get wrong, in two specific ways this recipe demonstrates the fix for:
--   * LEAKING. Press the key twice and you have two of everything, both firing. Ess.Loop.start's fixed id
--     handles that for loops; for hooks you have to hold the stop() somewhere that survives, which means
--     Ess.State.
--   * ORPHANING. A hook whose subject is gone keeps firing forever, doing nothing, costing something.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- Ess.State survives the script re-running -- so this is where the previous run's teardown handles live.
-- Without this, a second keypress silently doubles every watcher below.
local S = Ess.State("compose_a_reactive_watcher", { tracker = nil, arms = 0, hits = 0 })

-- FIRST: undo whatever the previous run set up. This one block is what makes the recipe re-runnable, and
-- it's the single most-forgotten line in reactive mod code.
if S.tracker then
    S.tracker:closeAll()
    Ess.Log("[recipe] compose_a_reactive_watcher: tore down the previous run's watchers")
end
S.tracker = Ess.Track.new()
S.arms = S.arms + 1

local px, py, pz = Ess.Player.pose(0)
if not px then Ess.Log("[SMOKE] compose_a_reactive_watcher: FAIL (no player position)") return end

-- ---------------------------------------------------------------------------
-- A watcher with its own memory. The closure keeps `count` and `peak` privately; the hook keeps firing long
-- after this script returns. Neither idea has a node shape.
-- ---------------------------------------------------------------------------
local function makeHurtWatcher(label)
    local count, worst = 0, 0
    return function()
        count = count + 1
        S.hits = S.hits + 1                              -- shared, survives re-runs
        local hp = Ess.Object.health(Ess.Player.character(0)) or 0
        if hp > worst then worst = hp end
        Ess.Log(string.format("[recipe] %s: hurt #%d (hp now %d)", label, count, hp))
    end
end

-- Every hook's stop() goes straight into the tracker via :any -- so cleanup is one call regardless of how
-- many we register, and regardless of their shapes (see compose_one_cleanup.lua).
S.tracker:any(Ess.On.playerHurt(makeHurtWatcher("hurt-watcher")))

-- A zone the player can walk into, reacting whenever they do. Fires as an event, not on a schedule.
S.tracker:any(Ess.On.enterArea(px, py, pz, 25, function()
    Ess.Log("[recipe] compose_a_reactive_watcher: back in the start zone")
end))

-- A watcher over a SPAWNED subject, which introduces the orphan problem: when the car dies, the hook that
-- watches it has nothing left to watch.
local car = Ess.Object.spawnAhead("Veyron", 12)
if car then
    S.tracker:guid(car)                                   -- so teardown removes the car too
    S.tracker:any(Ess.On.death(car, function()
        Ess.Log("[recipe] compose_a_reactive_watcher: the watched car died")
    end))
    -- ...and a self-retiring poll. Returning false from an Ess.Loop tick ends it, so the loop cleans ITSELF
    -- up the moment its subject is gone, instead of ticking forever over a dead guid.
    Ess.Loop.start("compose_a_reactive_watcher.poll", 0.5, function()
        if not Ess.Object.alive(car) then
            Ess.Log("[recipe] compose_a_reactive_watcher: subject gone, poll retiring itself")
            return false
        end
        return true
    end)
    S.tracker:any("compose_a_reactive_watcher.poll")       -- a string id, tracked like anything else
end

Ess.Log(string.format("[recipe] compose_a_reactive_watcher: armed (run #%d, %d hurt events seen so far "
    .. "across all runs)", S.arms, S.hits))

-- Self-check: the watchers are armed, the tracker holds them, and re-running is safe.
local ok = (S.tracker ~= nil) and (S.arms >= 1) and Ess.Loop.isRunning("compose_a_reactive_watcher.poll")

-- For the smoke run specifically, don't leave live watchers behind -- a real mod WOULD leave them running,
-- which is the entire point, but a test that leaves things armed pollutes every recipe after it.
S.tracker:closeAll()
S.tracker = nil
ok = ok and (Ess.Loop.isRunning("compose_a_reactive_watcher.poll") ~= true)

Ess.Log("[SMOKE] compose_a_reactive_watcher: " .. (ok and "PASS" or "FAIL"))
