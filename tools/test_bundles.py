#!/usr/bin/env python3
"""tools/test_bundles.py -- offline behavioral tests for the "intent bundle" namespaces whose value is pure
STATE-MACHINE logic (not the native calls they ultimately make): Ess.Objective / Ess.Quest /
Ess.Easy.Objective (src/59_objective.lua) and Ess.Easy.Debug.overlay (src/97_easy_debug.lua).

Like tools/checkpure.py, this runs the real framework Lua under lupa (embedded Lua) with the ENGINE
touchpoints stubbed -- so the counting / sequencing / auto-wiring / teardown / reload-safe-replace logic and
the overlay's line-building + toggle are executed exactly as the game would run them, no game required. It
does NOT prove the underlying native calls (HUD tray writes, UI.Panel render, Probe/Mark/Player reads) -- those
are composed from confirmed call sites and need an in-game smoke pass (python tools/smoke.py). Wired into CI
alongside checkpure.

Usage: python tools/test_bundles.py   (run from anywhere)
"""
import sys
import pathlib
from lupa import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"


def run(title, src_file, harness):
    code = (SRC / src_file).read_text(encoding="utf-8")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().CODE = lua.eval("function() return function()\n" + code + "\nend end")()
    print("== " + title + " ==")
    try:
        lua.execute(harness)
    except Exception as e:  # a failed assert() surfaces here with its message
        print("[FAIL]", e)
        return False
    return True


OBJECTIVE = r'''
_G.Ess = {}
local HUD = {}
Ess.Hud = { objective = function(t, slot) HUD[(slot or 1)] = t end }
local WIRED = {}
local function wire(kind) return function(...)
    local args = {...}; local fn
    for i=#args,1,-1 do if type(args[i])=="function" then fn=args[i]; break end end
    local e = { fn = fn, stopped = false }; WIRED[kind] = e
    return function() e.stopped = true end
end end
Ess.On = { enterArea = wire("enter"), death = wire("death"), tick = wire("tick"),
           exitArea = wire("exit"), insideArea = wire("inside"), healthBelow = wire("hb"),
           playerHurt = wire("hurt"), vehicle = wire("veh") }
Ess.Player = { character = function(i) return "CHAR" .. tostring(i or 0) end }
Ess.Easy = {}
local MARK = { live = 0 }
local function placeMark() MARK.live = MARK.live + 1; return "H" .. MARK.live end
Ess.Easy.Mark = { zone = function() return placeMark() end, objective = function() return placeMark() end }
Ess.Mark = { clear = function(h) if h then MARK.live = MARK.live - 1 end end }
local POP = 0
Ess.Probe = { nearby = function(x,y,z,r,kind,filter) local t={}; for k=1,POP do t[k]=k end; return t end }

local function hud(slot) return HUD[slot or 1] end
local function eq(a,b,msg) if a~=b then error((msg or "").." : expected ["..tostring(b).."] got ["..tostring(a).."]",2) end end
local P=0; local function pass(n) P=P+1; print("  [PASS] "..n) end
CODE()

do local done=0
  local o = Ess.Objective.new{ label="Collect", target=3, onComplete=function() done=done+1 end }
  eq(hud(1), "Collect   0/3", "A create"); o:advance(); eq(hud(1), "Collect   1/3", "A 1/3")
  o:advance(); eq(o:isDone(), false, "A not done at 2"); o:advance(); eq(o:isDone(), true, "A done at 3")
  eq(hud(1), nil, "A cleared"); eq(done, 1, "A cb once"); o:advance(); eq(done, 1, "A no-op after done")
  pass("A manual counted objective") end

do local o = Ess.Objective.new{ label="Go" }
  eq(hud(1), "Go", "B no counter"); o:advance(); eq(hud(1), nil, "B cleared"); eq(o:isDone(), true, "B done")
  pass("B single-step objective") end

do local steps, qdone = {}, 0
  local q = Ess.Quest.new{ steps={ "Reach", {label="Smash", target=2}, "Escape" },
      onStep=function(i,t) steps[#steps+1]=i end, onComplete=function() qdone=qdone+1 end }
  eq(hud(1), "(1/3) Reach", "C s1"); q:advance(); eq(hud(1), "(2/3) Smash   0/2", "C s2")
  q:advance(); eq(hud(1), "(2/3) Smash   1/2", "C s2p"); q:advance(); eq(hud(1), "(3/3) Escape", "C s3")
  local i,t = q:step(); eq(i,3,"C i"); eq(t,3,"C t"); q:advance(); eq(q:isDone(), true, "C done")
  eq(hud(1), nil, "C cleared"); eq(qdone, 1, "C cb"); eq(#steps, 3, "C onStep x3")
  pass("C quest sequence") end

do local reached, before = 0, MARK.live
  local o = Ess.Easy.Objective.reach(1,2,3, 8, "At the dock", function() reached=reached+1 end)
  eq(hud(1), "At the dock", "D shown"); eq(MARK.live, before+1, "D marked"); eq(WIRED.enter.stopped, false, "D live")
  WIRED.enter.fn(); eq(o:isDone(), true, "D done"); eq(reached, 1, "D cb")
  eq(WIRED.enter.stopped, true, "D watcher down"); eq(MARK.live, before, "D marker cleared")
  pass("D Easy.Objective.reach") end

do local ok, fail = 0, 0
  local o = Ess.Easy.Objective.survive(3, "Hold", function() ok=ok+1 end, function() fail=fail+1 end)
  eq(hud(1), "Hold   3s", "E init"); local tick, death = WIRED.tick, WIRED.death
  tick.fn(); eq(hud(1), "Hold   2s", "E 2s"); tick.fn(); eq(hud(1), "Hold   1s", "E 1s")
  tick.fn(); eq(o:isDone(), true, "E done"); eq(ok,1,"E ok"); eq(fail,0,"E no fail")
  eq(tick.stopped, true, "E tick down"); eq(death.stopped, true, "E death down")
  pass("E Easy.Objective.survive") end

do local ok, fail = 0, 0
  local o = Ess.Easy.Objective.survive(30, "Hold", function() ok=ok+1 end, function() fail=fail+1 end)
  local tick = WIRED.tick; WIRED.death.fn()
  eq(o:isDone(), true, "F done"); eq(fail,1,"F fail"); eq(ok,0,"F no ok"); eq(tick.stopped, true, "F tick down")
  pass("F survive fail path") end

do local cb=0
  local o1 = Ess.Objective.new{ id="mission", label="One", onComplete=function() cb=cb+1 end }
  eq(hud(1), "One", "G first"); local o2 = Ess.Objective.new{ id="mission", label="Two" }
  eq(o1:isDone(), true, "G cancelled"); eq(cb, 0, "G silent"); eq(hud(1), "Two", "G second")
  pass("G reload-safe id replace") end

do local killed, before = 0, MARK.live
  local o = Ess.Easy.Objective.destroy("TANK7", "Blow the tank", function() killed=killed+1 end)
  eq(hud(1), "Blow the tank", "H shown"); eq(MARK.live, before+1, "H marked")
  WIRED.death.fn(); eq(o:isDone(), true, "H done"); eq(killed,1,"H cb"); eq(MARK.live, before, "H cleared")
  pass("H Easy.Objective.destroy") end

do local cleared, before = 0, MARK.live; POP = 3
  local o = Ess.Easy.Objective.clear(0,0,0, 40, "VZ", "Clear the beach", function() cleared=cleared+1 end)
  eq(hud(1), "Clear the beach   3 left", "I init"); eq(MARK.live, before+1, "I marked"); local tick = WIRED.tick
  POP=2; tick.fn(); eq(hud(1), "Clear the beach   2 left", "I 2"); POP=1; tick.fn(); eq(hud(1), "Clear the beach   1 left", "I 1")
  POP=0; tick.fn(); eq(o:isDone(), true, "I done"); eq(cleared,1,"I cb"); eq(tick.stopped, true, "I poll down"); eq(MARK.live, before, "I cleared")
  pass("I Easy.Objective.clear (poll)") end

do local mstart = MARK.live; POP = 2; local qdone = 0
  local q = Ess.Easy.Quest({ { reach={1,2,3,8}, label="Go" }, { destroy="TANK", label="Kill" },
      { clear={0,0,0,40,"VZ"}, label="Sweep" }, "Escape" }, function() qdone=qdone+1 end)
  eq(hud(1), "(1/4) Go", "J s1"); eq(MARK.live, mstart+1, "J 1 mark"); WIRED.enter.fn()
  eq(hud(1), "(2/4) Kill", "J s2"); eq(MARK.live, mstart+1, "J 1 mark s2"); WIRED.death.fn()
  eq(hud(1), "(3/4) Sweep   2 left", "J s3"); POP=1; WIRED.tick.fn(); eq(hud(1), "(3/4) Sweep   1 left", "J s3 count")
  POP=0; WIRED.tick.fn(); eq(hud(1), "(4/4) Escape", "J s4"); eq(MARK.live, mstart, "J no mark manual")
  q:advance(); eq(q:isDone(), true, "J done"); eq(qdone,1,"J cb"); eq(hud(1), nil, "J cleared"); eq(MARK.live, mstart, "J all cleared")
  pass("J auto-wired Quest") end

print(P .. " objective/quest checks passed")
'''

OVERLAY = r'''
_G.Ess = {}
local LINES, PANEL = {}, nil
Ess.UI = { Panel = function(opts)
    PANEL = { _lines={}, _dead=false, title=opts.title }
    function PANEL:line(i,s) self._lines[i]=s; return self end
    function PANEL:destroy() self._dead=true; return self end
    return PANEL end }
local LOOP = { fn=nil, running=false }
Ess.Loop = { start=function(id,iv,fn) LOOP.fn=fn; LOOP.running=true end, stop=function(id) LOOP.running=false end }
local W = { veh=nil, aim="Soldier", aimGuid="G1", hp=90 }
Ess.Player = {
    pose = function(i) return 10, 20, 30, 45, "CHAR0", "SLOT0" end,
    targetUnderReticle = function(i) if W.aimGuid then return W.aimGuid, 11,21,31 end return nil end,
    inVehicle = function(i) return W.veh end, character = function(i) return "CHAR0" end }
Ess.Probe = {
    nearby = function(x,y,z,r,kind) if kind=="humans" then return {1,2} elseif kind=="vehicles" then return {1} end return {} end,
    getFaction = function(g) return "VZ" end }
Ess.Object = { distance=function(g,x,y,z) return 12.3 end, health=function(c) return W.hp end }
Ess.Name = function(g) return (g==W.aimGuid) and W.aim or "Car" end
-- the overlay throttles its nearby scan through Ess.Time.cooldown(1) -- stub it so the FIRST call (the
-- immediate paint) scans and later ticks reuse the cache, matching real cooldown() behaviour sub-second.
Ess.Time = { cooldown = function(s) local first=true; return function() if first then first=false; return true end return false end end }
_G.Object = { GetMaxHealth = function(c) return 120 end }

local function eq(a,b,msg) if a~=b then error((msg or "").." : expected ["..tostring(b).."] got ["..tostring(a).."]",2) end end
local P=0; local function pass(n) P=P+1; print("  [PASS] "..n) end
CODE()

do eq(Ess.Easy.Debug.isOn(), false, "A off")
  local p = Ess.Easy.Debug.overlay{ radius=40 }
  eq(Ess.Easy.Debug.isOn(), true, "A on")
  eq(p._lines[0], "pos: (10.0, 20.0, 30.0)  yaw 45", "A pos")
  eq(p._lines[1], "aim: Soldier  VZ  d=12.3", "A aim")
  eq(p._lines[2], "on foot   health: 90 / 120", "A state")
  eq(p._lines[3], "near(40): 2 hum  1 veh", "A nearby"); eq(LOOP.running, true, "A loop")
  pass("A overlay on + painted lines") end

do W.aimGuid=nil; W.veh="CAR9"; W.hp=75; LOOP.fn()
  eq(PANEL._lines[1], "aim: (nothing)", "B no target")
  eq(PANEL._lines[2], "vehicle: Car   health: 75 / 120", "B vehicle")
  pass("B refresh tick reflects new state") end

do local r = Ess.Easy.Debug.overlay(); eq(r, nil, "C nil"); eq(Ess.Easy.Debug.isOn(), false, "C off")
  eq(PANEL._dead, true, "C destroyed"); eq(LOOP.running, false, "C stopped")
  pass("C overlay toggle off") end

do Ess.Easy.Debug.hide(); Ess.Easy.Debug.hide(); eq(Ess.Easy.Debug.isOn(), false, "D off")
  pass("D hide() idempotent") end

print(P .. " overlay checks passed")
'''

ok = True
ok = run("Ess.Objective / Ess.Quest / Ess.Easy.Objective", "59_objective.lua", OBJECTIVE) and ok
ok = run("Ess.Easy.Debug.overlay", "97_easy_debug.lua", OVERLAY) and ok
if not ok:
    sys.exit(1)
print("all bundle checks passed")
