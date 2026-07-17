-- RECIPE: create a pile of things, then tear it ALL down with one call -- no leaks, no bookkeeping.
-- Namespaces: Ess.Track, Ess.Event, Ess.Object, Ess.Easy.Triggers.
--
-- Every "Add X" call on this engine hands back a handle that only its matching "Remove X" accepts, and
-- there is NO "remove everything I made" native for ANY of them (events, spawns, markers, radar/PDA blips,
-- quality refs, disposers, context actions). Ess.Track is the shared answer: register things as you make
-- them, then :closeAll() runs every teardown in reverse order. This is exactly what a contract task bucket
-- is built from -- you get the same leak-proof lifecycle for your own scripts in one object.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local px, py, pz = Ess.Player.pose(0)
if not px then Ess.Log("[SMOKE] track_lifecycles: FAIL (no player position)") return end

local tr = Ess.Track.new()

-- :guid(u) tracks a spawned object for Object.Remove. It returns the guid, so you can wrap the spawn inline.
local a = tr:guid(Ess.Object.spawn("Veyron", px + 6, py, pz + 4))
local b = tr:guid(Ess.Object.spawn("Veyron", px + 6, py, pz - 4))

-- :event(h) tracks an Event.Create handle for Event.Delete (here via Ess.Event.on, which also logs a bad
-- Create instead of handing back a broken handle). A 10s heartbeat we'll never let reach 10s -- closeAll kills it.
tr:event(Ess.Event.on(Event.TimerRelative, { 10 }, function() end))

-- :add(fn) is the generic escape hatch -- ANY zero-arg teardown. Here it just flips a flag so we can prove
-- the whole batch actually ran.
local closerRan = false
tr:add(function() closerRan = true end)

local before = Ess.Object.valid(a) and Ess.Object.valid(b)
Ess.Log("[recipe] track_lifecycles: 2 cars + a timer + a closer registered on ONE tracker")

-- show the batch for a beat, then drop everything at once. (A contract does exactly this in cleanupTask;
-- an OnKey tool does it when you toggle a mode off. One call, whatever's in the bucket.)
Ess.Easy.Triggers.after(2, function()
    tr:closeAll()                                   -- cars removed, timer deleted, closer fired -- in one line
    local goneA = not Ess.Object.valid(a)
    local ok = before and closerRan                 -- closer ran => every registered teardown ran
    Ess.Log("[recipe] track_lifecycles: closeAll -> closer ran=" .. tostring(closerRan) .. ", car removed=" .. tostring(goneA))
    Ess.Log("[SMOKE] track_lifecycles: " .. (ok and "PASS" or "FAIL"))
end)
