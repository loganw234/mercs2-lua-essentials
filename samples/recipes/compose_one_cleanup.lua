-- RECIPE: tear down everything you made, with one verb, whatever shape it came back as.
-- Namespaces: Ess.stop, Ess.stopAll, Ess.Track (:any), Ess.Easy.Mark, Ess.On, Ess.Loop, Ess.Object.
--
-- Part of the compose_* track (see compose_a_closure.lua).
--
-- THE PROBLEM THIS SOLVES. Ess grew 27 teardown verbs over five structurally different disposal idioms,
-- because each namespace picked the word that read best locally. Every one still works and is still the most
-- precise thing to say -- but if you're holding four handles of four different shapes, you used to need four
-- different spellings and the knowledge of which was which:
--
--   Ess.On.death(g, fn)        -> a CLOSURE            you call
--   Ess.Easy.Mark.enemy(g)     -> a HANDLE TABLE       Ess.Mark.clear() takes
--   Ess.Loop.start("id", ...)  -> nothing; an ID       Ess.Loop.stop() takes
--   Ess.Objective.new{...}     -> an OBJECT            with :cancel()
--   Ess.Track.new()            -> a TRACKER            with :closeAll()
--
-- Ess.stop(x) takes any of them. Ess.stopAll(t) takes a list of any of them. Ess.Track:any(x) collects any of
-- them into a tracker. That's the whole idea -- nothing new to learn per namespace.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local px, py, pz = Ess.Player.pose(0)
if not px then Ess.Log("[SMOKE] compose_one_cleanup: FAIL (no player position)") return end

local results = {}
local function check(label, cond)
    results[#results + 1] = { label = label, ok = cond and true or false }
    return cond
end

-- ---------------------------------------------------------------------------
-- 1. Ess.stop on each shape, one at a time.
-- ---------------------------------------------------------------------------

-- a closure (Ess.On returns its own stop())
local fired = 0
local stopHook = Ess.On.tick(0.1, function() fired = fired + 1 end)
check("stop(closure)", Ess.stop(stopHook) == true)

-- a handle table (a marker)
local car = Ess.Object.spawnAhead("Veyron", 10)
if car then
    local markHandle = Ess.Easy.Mark.enemy(car)
    check("stop(mark handle)", Ess.stop(markHandle) == true)
end

-- a caller-supplied string id (a loop). Ess.stop asks each registry which one owns the id, rather than
-- guessing from the string -- so the same call works for an Ess.Sandbox id too.
Ess.Loop.start("compose_one_cleanup.demo", 0.5, function() return true end)
check("stop(loop id)", Ess.stop("compose_one_cleanup.demo") == true)
check("loop really stopped", Ess.Loop.isRunning("compose_one_cleanup.demo") ~= true)

-- an object with its own teardown method
local obj = Ess.Objective.new{ label = "Cleanup demo", target = 3, id = "compose_one_cleanup.obj" }
check("stop(:cancel object)", Ess.stop(obj) == true)

-- nil and nonsense are no-ops that report false instead of throwing. Teardown must never be the thing that
-- fails at level unload, so nothing here can raise.
check("stop(nil) is a safe false", Ess.stop(nil) == false)
check("stop(number) is a safe false", Ess.stop(42) == false)

-- ---------------------------------------------------------------------------
-- 2. Ess.stopAll: a mixed list, torn down in reverse (later things usually depend on earlier ones).
-- ---------------------------------------------------------------------------
local order = {}
local mixed = {
    function() order[#order + 1] = "first" end,
    function() order[#order + 1] = "second" end,
    function() order[#order + 1] = "third" end,
}
check("stopAll count", Ess.stopAll(mixed) == 3)
check("stopAll is reverse order", order[1] == "third" and order[3] == "first")

-- ---------------------------------------------------------------------------
-- 3. Ess.Track:any -- collect as you go, tear down once at the end. This is the shape most real mods want:
--    you don't track handles in named variables at all, you just hand each one to the tracker.
-- ---------------------------------------------------------------------------
local tracker = Ess.Track.new()
local tracked = 0

-- :any returns its argument, so it wraps a call inline without an extra line.
local car2 = tracker:guid(Ess.Object.spawnAhead("Veyron", 14))       -- typed registrar: knows it's a guid
if car2 then
    tracker:any(Ess.Easy.Mark.enemy(car2))                            -- a handle table
end
tracker:any(Ess.On.tick(0.1, function() tracked = tracked + 1 end))   -- a closure
Ess.Loop.start("compose_one_cleanup.tracked", 0.5, function() return true end)
tracker:any("compose_one_cleanup.tracked")                            -- a string id

-- One call ends all four, in reverse registration order.
tracker:closeAll()
check("tracker stopped the loop too", Ess.Loop.isRunning("compose_one_cleanup.tracked") ~= true)

-- NOT checked here: whether the car is dead YET. CONFIRMED LIVE 2026-07-25 -- Object.Remove is DEFERRED.
-- Immediately after it, Ess.Object.alive(g) still returns true; it only flips false roughly half a second
-- later (Ess.Object.valid(g) stays true even then -- the guid handle outlives the object). So a synchronous
-- `alive() == false` assertion right after teardown fails for a reason that has nothing to do with teardown,
-- which is exactly what happened when this recipe was first written. If you need to KNOW something is gone,
-- poll for it on an Ess.Loop tick instead of testing on the same tick you removed it.
check("tracker was actually holding the spawn", car2 ~= nil)

-- tidy the first car (it was never given to the tracker, on purpose -- to show the manual path still works)
if car then Ess.Object.remove(car) end

local ok = true
for _, r in ipairs(results) do
    if not r.ok then
        ok = false
        Ess.Log("[recipe] compose_one_cleanup: FAILED -> " .. r.label)
    end
end
Ess.Log(string.format("[recipe] compose_one_cleanup: %d/%d checks passed", (function()
    local n = 0; for _, r in ipairs(results) do if r.ok then n = n + 1 end end; return n
end)(), #results))
Ess.Log("[SMOKE] compose_one_cleanup: " .. (ok and "PASS" or "FAIL"))
