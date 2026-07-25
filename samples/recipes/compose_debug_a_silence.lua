-- RECIPE: your mod did nothing and said nothing. Find out why.
-- Namespaces: Ess.DEBUG, Ess.lastError, Ess.Safe (.stats/.reset/.reject).
--
-- Part of the compose_* track (see compose_a_closure.lua).
--
-- THE WALL EVERY BEGINNER HITS. Ess fails SILENTLY on purpose: a wrapper's whole job is to return nil instead
-- of propagating a problem, so a call with a stale guid or a nil argument gives you no log line, no error, and
-- no effect. Nothing to search for. `Ess.DEBUG = true` turns that silence into a sentence.
--
-- There are two different silences, and knowing which you're looking at is most of the diagnosis:
--
--   1. A THROWN failure    -- an engine call raised an error and a pcall swallowed it.
--   2. A GUARD REJECTION   -- Ess looked at your arguments, decided the call couldn't work, and returned
--                             early WITHOUT EVER CALLING THE ENGINE.
--
-- (2) is the common one, and it's the useful one, because Ess knows WHY it gave up -- so the message is
-- specific ("no opts.at destination given") rather than a generic engine error string. Measured on the live
-- game, malformed native calls essentially never throw at all: 14 deliberately-broken ones (nil, garbage and
-- stale guids across Object/Player/Vehicle/Human/Ai/Marker/Camera/Sys/Pg) produced ZERO Lua errors.
--
-- THE WORKFLOW, which is the actual point of this recipe:
--   Ess.Safe.reset()          clear the slate so what's left is only your repro
--   Ess.DEBUG = true          start talking
--   ...do the thing that didn't work...
--   Ess.lastError()           what gave up most recently, and why
--   Ess.Safe.stats()          everything that gave up, worst offender first
--   Ess.DEBUG = false         back to quiet (it survives a level reload, so remember this)

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local wasDebug = Ess.DEBUG          -- restore it at the end; leaving DEBUG on floods the log
Ess.Safe.reset()
Ess.DEBUG = true

local ok = true
local function want(label, cond)
    if not cond then ok = false; Ess.Log("[recipe] compose_debug_a_silence: FAILED -> " .. label) end
end

-- ---------------------------------------------------------------------------
-- A real silence, reproduced: order some units to move, but forget the destination.
-- Without DEBUG this returns quietly and the units simply carry on doing whatever they were doing. That is
-- indistinguishable, from the outside, from "the AI ignored me" or "Ess is broken".
-- ---------------------------------------------------------------------------
Ess.AIOrders.command({ Ess.Player.character(0) }, "move", {})    -- no opts.at !

local e = Ess.lastError()
want("lastError() reports the rejection", e ~= nil)
if e then
    Ess.Log("[recipe] silence #1 -> " .. tostring(e.label) .. " : " .. tostring(e.msg))
    want("it is flagged as a guard rejection, not a throw", e.rejected == true)
    want("it names the function that gave up", e.label == "Ess.AIOrders.move")
end

-- ---------------------------------------------------------------------------
-- Another: ask for the CO-OP PARTNER's position in single-player. Index 1 is the partner, and there isn't
-- one -- so this spawns nothing, and (before DEBUG) said nothing.
-- ---------------------------------------------------------------------------
local nothing = Ess.Object.spawnAhead("Veyron", 8, 0, 1)
want("nothing spawned for the absent partner", nothing == nil)
local e2 = Ess.lastError()
if e2 then Ess.Log("[recipe] silence #2 -> " .. tostring(e2.label) .. " : " .. tostring(e2.msg)) end

-- ---------------------------------------------------------------------------
-- A hook that never fires -- the nastiest kind, because nothing is wrong and nothing happens, forever.
-- ---------------------------------------------------------------------------
local deadHook = Ess.On.death(nil, function() Ess.Log("never runs") end)
want("you still get a usable stop() back", type(deadHook) == "function")
local e3 = Ess.lastError()
if e3 then Ess.Log("[recipe] silence #3 -> " .. tostring(e3.label) .. " : " .. tostring(e3.msg)) end

-- ---------------------------------------------------------------------------
-- stats(): every give-up this session, worst first. In a real session this is where you notice that one
-- helper failed 4,000 times inside a per-frame loop while you were looking somewhere else entirely.
-- ---------------------------------------------------------------------------
local tally, total = Ess.Safe.stats()
Ess.Log(string.format("[recipe] compose_debug_a_silence: %d distinct call sites gave up, %d failures total",
    #tally, total))
for i = 1, math.min(#tally, 5) do
    Ess.Log(string.format("[recipe]   %d x %s", tally[i].count, tally[i].label))
end
want("stats() saw at least the three rejections above", #tally >= 3)

-- You can use the same channel for YOUR OWN code. reject() always returns nil, so it fits an early-out on
-- one line, and your mod's give-ups show up in the same stats() list as the framework's.
local function healTarget(uGuid)
    if not uGuid then return Ess.Safe.reject("MyMod.healTarget", "called with no guid") end
    Ess.Object.heal(uGuid)
    return true
end
healTarget(nil)
local e4 = Ess.lastError()
want("your own reject() is recorded the same way", e4 ~= nil and e4.label == "MyMod.healTarget")
if e4 then Ess.Log("[recipe] your own -> " .. tostring(e4.label) .. " : " .. tostring(e4.msg)) end

-- ---------------------------------------------------------------------------
-- And back to quiet. With DEBUG off, none of this costs anything: reject() checks one boolean and returns.
-- ---------------------------------------------------------------------------
Ess.DEBUG = false
Ess.Safe.reset()
Ess.AIOrders.command({ Ess.Player.character(0) }, "move", {})    -- the same silent failure as before
local quietTally, quietTotal = Ess.Safe.stats()
want("DEBUG off records nothing", #quietTally == 0 and quietTotal == 0)
want("DEBUG off leaves lastError alone", Ess.lastError() == nil)

Ess.DEBUG = wasDebug
Ess.Log("[SMOKE] compose_debug_a_silence: " .. (ok and "PASS" or "FAIL"))
