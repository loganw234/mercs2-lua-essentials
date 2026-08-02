#!/usr/bin/env python3
"""tools/test_spawn.py -- offline behavioral tests for Ess.Spawn (src/18_spawn.lua).

Same approach as tools/test_bundles.py: run the real framework Lua under lupa with the engine touchpoints
stubbed, so the logic that actually matters here executes exactly as the game would run it.

WHAT THIS PROVES (all of it pure, none of it needing a game):
  * the validate-EVERYTHING-before-spawning-anything rule -- the load-bearing safety property, since a blank
    template hard-CRASHES the engine past pcall and a bulk spawner is the easiest place to hit one
  * roster cycling keeps a composition's ratio exact; a count-less roster spawns one of each
  * the count cap refuses rather than trying
  * placement actually separates things (n spawns at n distinct points) and honours minDist/maxDist
  * tracker/onEach wiring, and that a throwing onEach cannot strand already-spawned objects

WHAT IT DOES NOT PROVE: that Pg.Spawn accepts these template names, or that a snapped object lands on real
terrain. Those are engine facts and need `python tools/smoke.py` against a running game.

Usage: python tools/test_spawn.py   (exit 1 on any failure)
"""
import math
import pathlib
import sys

try:
    from lupa import LuaRuntime
except ImportError:
    print("[test_spawn] needs lupa: pip install lupa")
    sys.exit(2)

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"

# The stub world. Ess.Object.spawn is the ONLY way 18_spawn.lua reaches the engine, so recording its calls
# captures every placement decision the module makes. It refuses a blank template exactly as the real one
# does, so a test that expects "nothing spawned" is testing the real contract rather than a lenient stub.
PRELUDE = r'''
-- Lua 5.5 (what lupa embeds) folded atan2 into a 2-arg math.atan and dropped the old name. The engine's 5.1
-- still HAS math.atan2, which Ess.Math.angleTo correctly targets -- so this shim is a property of the test
-- harness, not of the framework. Same line tools/checkpure.py already carries, for the same reason.
if not math.atan2 then math.atan2 = math.atan end
_G.Ess = {}
Ess.Safe = {
  quiet = function(fn, ...) local ok,a,b,c,d,e,f = pcall(fn, ...) if not ok then return false end return true,a,b,c,d,e,f end,
  named = function(_, fn, ...) local ok,a,b,c,d,e,f = pcall(fn, ...) if not ok then return false end return true,a,b,c,d,e,f end,
  reject = function(label, why) REJECTS[#REJECTS+1] = tostring(label)..": "..tostring(why) return nil end,
  template = function(s) return type(s) == "string" and s:gsub("%s", "") ~= "" end,
}
Ess.Log = function(m) LOGS[#LOGS+1] = tostring(m) end

SPAWNED, REJECTS, LOGS, SNAPPED = {}, {}, {}, {}
local nextGuid = 0
Ess.Object = {
  spawn = function(t, x, y, z, yaw)
    if type(t) ~= "string" or t:gsub("%s","") == "" then return nil end
    if REFUSE_TEMPLATE and t == REFUSE_TEMPLATE then return nil end   -- simulate an engine-side refusal
    nextGuid = nextGuid + 1
    SPAWNED[#SPAWNED+1] = { guid = nextGuid, template = t, x = x, y = y, z = z, yaw = yaw }
    return nextGuid
  end,
  pos = function(g) return 100, 5, 200 end,
  yaw = function(g) return 90 end,
  snapToGround = function(g) SNAPPED[#SNAPPED+1] = g end,
}
Ess.Player = {
  pose = function(i) if i == 1 then return nil end return 0, 10, 0, 0 end,   -- p1 absent, like single-player
  viewYaw = function(i) return 45 end,
}
Ess.Math = {
  pointAhead = function(x, z, yaw, d)
    return x + math.sin(math.rad(yaw)) * d, z + math.cos(math.rad(yaw)) * d
  end,
  angleTo = function(fx, fz, tx, tz) return math.deg(math.atan2(tx - fx, tz - fz)) end,
  normDeg = function(d) d = d % 360 if d < 0 then d = d + 360 end return d end,
}
-- A deterministic stand-in for Ess.RNG: a fixed sequence is enough to prove cycling/placement wiring, and
-- keeps the assertions stable. The REAL Ess.RNG is what runs in game (never math.random -- the 32-bit float
-- LCG trap); this only stands in for it here.
local seq, si = {}, 0
for k = 1, 97 do seq[k] = ((k * 37) % 97) / 97 end   -- 97 distinct values, coprime step: no short cycle
Ess.RNG = { new = function() si = 0 return {
  next = function(self) si = si + 1 return seq[((si-1) % #seq) + 1] end,
  pick = function(self, list) si = si + 1 return list[((si-1) % #list) + 1] end,
} end }
Ess.Track = { new = function() return { held = {}, guid = function(self, g) self.held[#self.held+1] = g end } end }
'''

TESTS = r'''
local function eq(a, b, m) assert(a == b, (m or "") .. " -- got " .. tostring(a) .. ", wanted " .. tostring(b)) end
local function reset() SPAWNED, REJECTS, LOGS, SNAPPED = {}, {}, {}, {} REFUSE_TEMPLATE = nil end

-- ---- the safety property: one bad entry means NOTHING spawns ----------------------------------------
reset()
local r = Ess.Spawn.many({ "Good A", "Good B", "", "Good D" }, 4)
eq(#r, 0, "a blank roster entry refuses the WHOLE call")
eq(#SPAWNED, 0, "and spawns absolutely nothing (not a partial batch)")
assert(REJECTS[1] and REJECTS[1]:find("#3"), "the rejection names the offending INDEX, not just 'a bad entry'")

reset()
eq(#Ess.Spawn.many("   ", 3), 0, "a whitespace-only single template refuses")
eq(#SPAWNED, 0, "nothing spawned for a blank single template")
reset()
eq(#Ess.Spawn.many({}, 3), 0, "an empty roster refuses")
reset()
eq(#Ess.Spawn.many(nil, 3), 0, "a nil template refuses")

-- ---- roster semantics --------------------------------------------------------------------------------
reset()
local section = { "AL Soldier", "AL Soldier", "AL Heavy", "AL Sniper" }
r = Ess.Spawn.many(section)
eq(#r, 4, "no count + a roster = one of each")
eq(SPAWNED[3].template, "AL Heavy", "and in the order written")

reset()
r = Ess.Spawn.many(section, 12)
eq(#r, 12, "a count repeats the roster")
local heavies = 0
for _, s in ipairs(SPAWNED) do if s.template == "AL Heavy" then heavies = heavies + 1 end end
eq(heavies, 3, "cycling keeps the composition's RATIO exact (1 in 4 -> 3 of 12)")

reset()
r = Ess.Spawn.many("Veyron", 5)
eq(#r, 5, "a single template still works as a count")
eq(SPAWNED[5].template, "Veyron", "and every one is that template")

-- ---- the cap -----------------------------------------------------------------------------------------
reset()
eq(#Ess.Spawn.many("Veyron", 5000), 0, "an absurd count is refused, not attempted")
eq(#SPAWNED, 0, "and nothing spawns")
assert(REJECTS[1]:find("cap"), "the rejection explains the cap")
reset()
eq(#Ess.Spawn.many("Veyron", 100, { max = 200 }), 100, "opts.max raises it deliberately")
reset()
eq(#Ess.Spawn.many("Veyron", 0), 0, "zero is refused")
eq(#Ess.Spawn.many("Veyron", -3), 0, "a negative count is refused")

-- ---- placement: things must not land on top of each other --------------------------------------------
for _, pattern in ipairs({ "scatter", "grid", "line", "circle" }) do
    reset()
    Ess.Spawn.many("Veyron", 6, { pattern = pattern, spacing = 5 })
    eq(#SPAWNED, 6, pattern .. ": spawned them all")
    local seen, dupes = {}, 0
    for _, s in ipairs(SPAWNED) do
        local key = string.format("%.2f,%.2f", s.x, s.z)
        if seen[key] then dupes = dupes + 1 end
        seen[key] = true
    end
    eq(dupes, 0, pattern .. ": every unit got a DISTINCT position (the whole point of a pattern)")
end

-- scatter must honour its distance band, measured from the resolved centre
reset()
Ess.Spawn.many("Veyron", 8, { at = { 0, 0, 0 }, pattern = "scatter", minDist = 10, maxDist = 20 })
for _, s in ipairs(SPAWNED) do
    local d = math.sqrt(s.x * s.x + s.z * s.z)
    assert(d >= 9.99 and d <= 20.01, "scatter stayed inside minDist..maxDist -- got " .. d)
end

-- a reversed band is corrected rather than producing an empty range
reset()
Ess.Spawn.many("Veyron", 4, { at = { 0, 0, 0 }, pattern = "scatter", minDist = 30, maxDist = 10 })
eq(#SPAWNED, 4, "min/max given backwards still spawns")
for _, s in ipairs(SPAWNED) do
    local d = math.sqrt(s.x * s.x + s.z * s.z)
    assert(d >= 9.99 and d <= 30.01, "and clamps into the corrected band -- got " .. d)
end

-- ---- centre resolution -------------------------------------------------------------------------------
reset()
Ess.Spawn.many("Veyron", 1, { at = { 500, 7, 900 }, pattern = "grid" })
eq(SPAWNED[1].x, 500, "opts.at is used verbatim (x)")
eq(SPAWNED[1].z, 900, "opts.at is used verbatim (z)")
eq(SPAWNED[1].y, 7, "opts.at sets the height too")

reset()
Ess.Spawn.many("Veyron", 1, { around = 42, pattern = "grid" })
eq(SPAWNED[1].x, 100, "opts.around centres on that object's position")

reset()
eq(#Ess.Spawn.many("Veyron", 2, { i = 1 }), 0, "asking for an absent co-op partner refuses cleanly")
assert(REJECTS[1]:find("player 1"), "and says which player")

reset()
eq(#Ess.Spawn.many("Veyron", 1, { at = { 1, 2 } }), 0, "a malformed opts.at refuses")

-- ---- per-unit options --------------------------------------------------------------------------------
reset()
Ess.Spawn.many("Veyron", 3, { at = { 0, 0, 0 }, height = 25, pattern = "grid" })
eq(SPAWNED[1].y, 25, "height offsets every spawn")

reset()
Ess.Spawn.many("Veyron", 3, { snapToGround = true, pattern = "grid" })
eq(#SNAPPED, 3, "snapToGround is applied per spawn")

reset()
Ess.Spawn.many("Veyron", 4, { at = { 0, 0, 0 }, pattern = "circle", faceCentre = true, spacing = 6 })
for _, s in ipairs(SPAWNED) do assert(s.yaw ~= nil, "faceCentre gives every unit a yaw") end

reset()
Ess.Spawn.many("Veyron", 2, { yaw = 123, pattern = "grid" })
eq(SPAWNED[1].yaw, 123, "an explicit yaw is used as-is")

-- ---- tracker + onEach --------------------------------------------------------------------------------
reset()
local tr = Ess.Track.new()
r = Ess.Spawn.many("Veyron", 5, { tracker = tr, pattern = "grid" })
eq(#tr.held, 5, "every spawn is registered with the tracker -- bulk spawn, bulk cleanup")

reset()
local seenIdx, seenTmpl = {}, {}
Ess.Spawn.many(section, 4, { onEach = function(g, i, t) seenIdx[#seenIdx+1] = i seenTmpl[#seenTmpl+1] = t end })
eq(#seenIdx, 4, "onEach fires once per spawn")
eq(seenIdx[4], 4, "with a 1-based running index")
eq(seenTmpl[3], "AL Heavy", "and the template that was actually used")

reset()
local tr2 = Ess.Track.new()
r = Ess.Spawn.many("Veyron", 4, { tracker = tr2, onEach = function() error("user callback blew up") end })
eq(#r, 4, "a throwing onEach does not abort the batch")
eq(#tr2.held, 4, "and every object is STILL tracked -- none stranded untracked and unowned")

-- ---- partial engine refusal --------------------------------------------------------------------------
reset()
REFUSE_TEMPLATE = "AL Heavy"
r = Ess.Spawn.many(section, 8)
eq(#r, 6, "an engine-refused template is skipped, the rest still spawn")
assert(#LOGS > 0 and LOGS[#LOGS]:find("of 8"), "and the shortfall is reported honestly")

-- ---- mixed -------------------------------------------------------------------------------------------
reset()
r = Ess.Spawn.mixed({ { "VZ Soldier", 6 }, { "Veyron", 2 } })
eq(#r, 8, "mixed spawns the exact total")
local soldiers = 0
for _, s in ipairs(SPAWNED) do if s.template == "VZ Soldier" then soldiers = soldiers + 1 end end
eq(soldiers, 6, "with each spec's exact count")

reset()
eq(#Ess.Spawn.mixed({ { "", 3 } }), 0, "a blank template in a spec refuses the whole call")
eq(#SPAWNED, 0, "and spawns nothing")
reset()
eq(#Ess.Spawn.mixed({}), 0, "an empty spec list refuses")

-- ---- at ----------------------------------------------------------------------------------------------
reset()
r = Ess.Spawn.at("Veyron", { { 1, 2, 3 }, { x = 4, y = 5, z = 6 } })
eq(#r, 2, "at() accepts both array and named point shapes")
eq(SPAWNED[2].x, 4, "and places at the given coordinate")

reset()
r = Ess.Spawn.at({ "A", "B" }, { { 1,1,1 }, { 2,2,2 }, { 3,3,3 } })
eq(SPAWNED[3].template, "A", "templates cycle across the points")

reset()
r = Ess.Spawn.at("Veyron", { { 1, 2, 3 }, { 9 } })
eq(#r, 1, "a malformed point is skipped, not fatal")
assert(REJECTS[1]:find("#2"), "and names which point")

-- ---- the Easy tier ------------------------------------------------------------------------------------
reset() eq(#Ess.Easy.Spawn.units(5), 5, "Easy units")
reset() eq(#Ess.Easy.Spawn.vehicles(3), 3, "Easy vehicles")
reset() eq(#Ess.Easy.Spawn.props(4), 4, "Easy props")
reset() eq(#Ess.Easy.Spawn.units(6, "AL Soldier"), 6, "Easy units with one template")
reset() eq(#Ess.Easy.Spawn.units(6, { "AL Soldier", "AL Heavy" }), 6, "Easy units with a roster")
reset() eq(#Ess.Easy.Spawn.units(nil, section), 4, "Easy units, count-less roster = one of each")
reset() eq(#Ess.Easy.Spawn.roster(section, 12, 20, 60), 12, "Easy roster, the proposal's own shape")
-- The Easy tier's distance arguments are named and documented "from the player", so they are measured HERE
-- from the player at (0,0) -- NOT from Ess.Spawn's default centre 20 units ahead.
--
-- This assertion previously measured from (0, 20), the ahead-centre, and so asserted the BUG was correct:
-- Ess.Easy.Spawn.roster passed the band through without overriding the centre, putting units 2..53 from the
-- player when asked for 20..60. The offline suite passed the whole time. A live run caught it in one call
-- (2026-07-26). Lesson worth keeping: a test written from the implementation instead of from the PROMISE
-- will happily ratify whatever the code already does.
reset()
Ess.Easy.Spawn.roster(section, 6, 20, 60)
for _, s in ipairs(SPAWNED) do
    local d = math.sqrt(s.x * s.x + s.z * s.z)        -- from the PLAYER, which is what the argument names mean
    assert(d >= 19.9 and d <= 60.1, "roster's band is measured from the PLAYER -- got " .. d)
end

-- And the same promise for the other three Easy verbs, each against its own documented band.
for _, case in ipairs({ { "units", 6, 20 }, { "vehicles", 12, 30 }, { "props", 4, 18 } }) do
    reset()
    Ess.Easy.Spawn[case[1]](5)
    for _, s in ipairs(SPAWNED) do
        local d = math.sqrt(s.x * s.x + s.z * s.z)
        assert(d >= case[2] - 0.1 and d <= case[3] + 0.1,
               "Easy " .. case[1] .. " ring is centred on the player -- got " .. d)
    end
end
reset() eq(#Ess.Easy.Spawn.units(3), 3, "Easy tier still refuses nothing valid")

-- ---- backwards compatibility --------------------------------------------------------------------------
assert(type(Ess.Easy.Spawn.enemies) == "function", "Ess.Easy.Spawn.enemies still exists, untouched")
return true
'''


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    for f in ("18_spawn.lua", "92_easy_spawn.lua"):
        # each src file is wrapped exactly as build/merge.py wraps it, so a top-level local can't leak
        lua.execute("do\n" + (SRC / f).read_text(encoding="utf-8") + "\nend")
    # 92_easy_spawn.lua's other verbs reach namespaces this harness doesn't stub; only the bulk ones are
    # exercised below, so stub the rest of its dependencies as no-ops rather than half-building a world.
    lua.execute("Ess.Easy.AIOrders = { attack = function() end }")
    try:
        lua.execute(TESTS)
    except Exception as e:
        print("[FAIL] " + str(e))
        return 1
    print("[test_spawn] all Ess.Spawn checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
