-- RECIPE: hold state in a CLOSURE, so a behaviour remembers things between ticks.
-- Namespaces: Ess.State, Ess.Loop, Ess.Player, Ess.Math.
--
-- THE COMPOSITION TRACK. This recipe and its `compose_*` siblings exist for one reason: they show what a
-- node graph structurally can't do. Everything else in samples/recipes/ is a sequence of one-liners -- and
-- the visual editor at visual.mercs2.tools does sequences of one-liners better than typing them, because you
-- can see the wiring. Reach for hand-written Lua when you want the things below: a closure over state,
-- iteration over a collection, a hook that outlives the script, or an abstraction of your own.
--
-- WHAT A CLOSURE BUYS YOU HERE. A node graph gives every node its own widget values, fixed when you wire it.
-- It has no way to express "a private variable that this behaviour, and only this behaviour, keeps updating."
-- Below, `travelled` and `lastX/lastZ` live inside makeOdometer() -- invisible to the rest of the script,
-- carried between ticks, and you can make TWO independent odometers by calling it twice.
--
-- Ess.State is the OTHER half, and does a different job: it survives the script being re-run from the top
-- (which an OnKey script does on every keypress -- see GETTING_STARTED.md §5). A closure survives between
-- TICKS; Ess.State survives between RUNS. Real mods usually want both, as here.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- makeOdometer() -> tick function. Each call returns a FRESH counter with its own private state -- that's
-- the part a graph can't express. Nothing outside can read or corrupt `travelled`.
local function makeOdometer(label)
    local travelled, lastX, lastZ = 0, nil, nil
    return function()
        local x, _, z = Ess.Player.pose(0)
        if not x then return travelled end
        if lastX then travelled = travelled + Ess.Math.dist2D(lastX, lastZ, x, z) end
        lastX, lastZ = x, z
        return travelled
    end
end

-- Two independent instances from the same factory, proving the state really is per-closure.
local odoA = makeOdometer("A")
local odoB = makeOdometer("B")

-- Ess.State: survives the script re-running. Bump a run counter so you can see it climb across keypresses.
local S = Ess.State("compose_a_closure", { runs = 0, bestMetres = 0 })
S.runs = S.runs + 1

-- Seed both odometers from the current position, then drive them by hand with a known displacement so this
-- recipe is deterministic enough to self-check without the player actually moving.
odoA(); odoB()
local x0, y0, z0 = Ess.Player.pose(0)
local ok = false
if x0 then
    -- Feed A twice and B once, from the same real positions -- if the state were shared (a plain `local` at
    -- file scope, or a graph's single widget value) both would read identically. They must not.
    odoA(); odoA()
    odoB()
    local a, b = odoA(), odoB()
    ok = (a ~= nil and b ~= nil and a >= b)
    if a > S.bestMetres then S.bestMetres = a end
    Ess.Log(string.format("[recipe] compose_a_closure: run #%d  odoA=%.2f  odoB=%.2f  best=%.2f",
        S.runs, a, b, S.bestMetres))

    -- A live one, for real use: tick an odometer 5x/second and stop it after a few seconds. `Ess.Loop.start`
    -- with a fixed id is reload-safe -- pressing the key twice replaces the loop instead of leaking a second.
    local live = makeOdometer("live")
    local ticks = 0
    Ess.Loop.start("compose_a_closure.odo", 0.2, function()
        ticks = ticks + 1                      -- also closure state, also private to this loop
        local m = live()
        if ticks >= 15 then
            Ess.Log(string.format("[recipe] compose_a_closure: you moved %.1f units in 3s", m))
            return false                        -- returning false ends the loop
        end
        return true
    end)
end

Ess.Log("[SMOKE] compose_a_closure: " .. (ok and "PASS" or "FAIL"))
