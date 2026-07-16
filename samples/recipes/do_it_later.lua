-- RECIPE: do something after a delay, and do something on a repeating timer.
-- Namespaces: Ess.Easy.Triggers (after), Ess.Loop, Ess.Time.
--
-- Two different tools for two different jobs:
--   * Ess.Easy.Triggers.after(seconds, fn) -- fire ONCE after a delay ("spawn reinforcements in 10s").
--   * Ess.Loop.start(id, interval, tickFn) -- a repeating heartbeat; return false from tickFn to stop it.
-- Both survive a world-pause and are reload-safe. NEVER hand-roll a self-rescheduling Event.TimerRelative.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- one-shot: run once, 1 second from now.
Ess.Easy.Triggers.after(1, function()
    Ess.Log("[recipe] do_it_later: the one-shot fired (1s later)")
end)

-- repeating: tick every 0.3s, three times, then stop by returning false.
local ticks = 0
Ess.Loop.start("recipe_do_it_later", 0.3, function()
    ticks = ticks + 1
    if ticks >= 3 then
        Ess.Log("[recipe] do_it_later: heartbeat ran " .. ticks .. " times, stopping")
        Ess.Log("[SMOKE] do_it_later: PASS")   -- logged from INSIDE the loop, proving it actually ticked
        return false
    end
    return true
end)

Ess.Log("[recipe] do_it_later: scheduled a one-shot (1s) and a 3-tick heartbeat")
