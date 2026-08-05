#!/usr/bin/env python3
"""tools/checkpure.py -- OFFLINE behavioral tests for Ess's pure-Lua namespaces.

smoke.py proves the framework works in the running game, but it needs the game up. Most of Ess touches the
engine and can only be tested that way -- but the pure-Lua utility namespaces (Math, Str, Color, Table, and
the deterministic parts of RNG/State/Time) have NO engine surface, so they can be executed and asserted
without the game at all. This runs them in an embedded Lua (via `lupa`) with the real `src/*.lua` loaded,
so a regression in a pure helper turns this red on any machine, no game required.

Scope + caveats:
  * PURE logic only. Anything that calls Object/Pg/Vehicle/Hud/etc. belongs in a recipe + smoke.py instead.
  * lupa here embeds Lua 5.5, a superset of the engine's 5.1 -- fine for BEHAVIOR of standard constructs
    (these namespaces use nothing version-specific), but NOT a substitute for CI's `luac5.1 -p` syntax gate.
  * A few engine globals the loaded files reference at call time (Sys clock, Junk.FormatTime) are stubbed
    with deterministic fakes below, so cooldown/clock/RNG-seed logic is exercised against known time.

Requires: `pip install lupa`. Usage: `python tools/checkpure.py` (exit 0 iff every group passes).
"""
import pathlib
import sys

try:
    import lupa
except ImportError:
    print("[checkpure] needs lupa: pip install lupa")
    sys.exit(2)

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"

# the pure (or deterministically-stubbable) src files, in load order
SRC_FILES = ["00_core.lua", "01_math.lua", "02_str.lua", "03_color.lua", "04_vec.lua", "07_names.lua",
             "15_machine.lua",
             "08_ecs.lua",
             "19_inspect.lua",
             "22_state.lua", "23_time.lua", "53_rng.lua", "52_points.lua",
             # 30_track only touches the engine INSIDE its teardown closures, never at load time, so it
             # loads fine here -- and 98_stop's Ess.Track:any() needs Ess.Track to exist when it loads.
             "30_track.lua", "98_stop.lua"]

# deterministic stubs for the handful of engine globals these files touch at call time
STUBS = """
-- Lua 5.5 folded atan2 into 2-arg math.atan and dropped the old name; the engine's 5.1 still HAS
-- math.atan2, which Ess.Math.angleTo correctly targets. Shim it back so the 5.5 test env can run angleTo.
if not math.atan2 then math.atan2 = math.atan end
_G.Ess = {}
_G.Loader = { Printf = function() end }
_G.Sys = {
  RealTimeStamp = function() return { t = 0 } end,
  MainTimeStamp = function() return { t = 0 } end,
  TimeStampGetElapsed = function(s) return 0 end,   -- frozen clock: 0s always elapsed
  TimeStampMark = function(s) end,
  SetTimeScale = function(n) end,
}
_G.Junk = { FormatTime = function(n, b) return "0:00" end }
_G.Event = { Delete = function() end, Create = function() return "EV" end }
_G.Object = { Remove = function() end }
_G.Marker = { Remove = function() end }
-- Ess.stop dispatch targets, each logging where it routed so a test can assert the ROUTE, not just an effect.
_G.STOPLOG = {}
"""

# each test chunk asserts, then `return true`. eq() gives a readable message on mismatch.
PRELUDE = "local function eq(a,b,m) assert(a==b, (m or '')..' got '..tostring(a)) end\n"

TESTS = {
    "stop": r"""
-- Ess.stop must route all five disposal idioms Ess grew (see 98_stop.lua's header) to the right place.
Ess.Mark      = { clear   = function(h) STOPLOG[#STOPLOG+1] = "mark"      end }
Ess.Relations = { restore = function(h) STOPLOG[#STOPLOG+1] = "relations" end }
Ess.Loop      = { _run = { tick = true },
                  isRunning = function(id) return Ess.Loop._run[id] == true end,
                  stop = function(id) Ess.Loop._run[id] = nil; STOPLOG[#STOPLOG+1] = "loop:"..id end }
Ess.Sandbox   = { _on = { arena = true },
                  isActive = function(id) return Ess.Sandbox._on[id] == true end,
                  finish = function(id) Ess.Sandbox._on[id] = nil; STOPLOG[#STOPLOG+1] = "sandbox:"..id end }
local function clear() for i=#STOPLOG,1,-1 do STOPLOG[i]=nil end end

-- 1. a closure
clear(); local called = false
assert(Ess.stop(function() called = true end) == true, 'closure -> true')
assert(called, 'closure was actually invoked')

-- 2. a string id, disambiguated by ASKING each registry which owns it
clear(); assert(Ess.stop("tick") == true, 'live loop id -> true')
eq(STOPLOG[1], "loop:tick", 'routed to Ess.Loop')
clear(); assert(Ess.stop("arena") == true, 'active sandbox id -> true')
eq(STOPLOG[1], "sandbox:arena", 'routed to Ess.Sandbox')
clear(); assert(Ess.stop("nobody-owns-this") == false, 'unknown id -> false, not a throw')
eq(#STOPLOG, 0, 'unknown id routed nowhere')

-- 3. an object with its own teardown method; :closeAll/:cancel/:stop all honoured, method beats field shape
clear(); local n = 0
assert(Ess.stop({ closeAll = function() n = n + 1 end }) == true, ':closeAll -> true')
assert(Ess.stop({ cancel   = function() n = n + 1 end }) == true, ':cancel -> true')
assert(Ess.stop({ stop     = function() n = n + 1 end }) == true, ':stop -> true')
eq(n, 3, 'each method form invoked exactly once')
-- a Mark-SHAPED table that also has a method must use the method, or an Objective carrying a uGuid misroutes
clear(); local viaMethod = false
Ess.stop({ uGuid = "G", cancel = function() viaMethod = true end })
assert(viaMethod and #STOPLOG == 0, 'method wins over field shape')

-- 4. a Relations handle (keyed on `snaps`, same field Ess.Relations.restore itself reads)
clear(); assert(Ess.stop({ label = "x", snaps = {}, restored = false }) == true, 'relations handle -> true')
eq(STOPLOG[1], "relations", 'routed to Ess.Relations')

-- 5. a Mark handle, including one with every surface disabled (carries only uGuid)
clear(); assert(Ess.stop({ uGuid = "G", radarName = "r" }) == true, 'mark handle -> true')
eq(STOPLOG[1], "mark", 'routed to Ess.Mark')
clear(); Ess.stop({ uGuid = "G" }); eq(STOPLOG[1], "mark", 'bare uGuid mark still routes to Mark')

-- nil and junk are no-ops that report false rather than throwing -- teardown must never be the thing that
-- fails at level unload.
assert(Ess.stop(nil) == false, 'nil -> false'); assert(Ess.stop(42) == false, 'number -> false')
-- and a closure that THROWS is still contained
assert(Ess.stop(function() error('teardown blew up') end) == false, 'throwing closure -> false, not a throw')

-- Ess.stopAll: reverse order, counts what it tore down.
-- NOTE the array here is DENSE on purpose. An earlier version of this test used `{ f, nil, f }` to check
-- hole-skipping and failed -- correctly: `#t` is UNDEFINED on a table with a nil hole (CONTRIBUTING.md's
-- engine rules, and the exact desync Ess.Table.compact exists to repair), so the length stopAll iterates is
-- not meaningful there. That was the test being wrong, not stopAll. Holes are the caller's to fix, with
-- Ess.Table.compact, and stopAll's own doc comment says so.
clear(); local order = {}
local t2 = { function() order[#order+1] = 1 end,
             function() order[#order+1] = 2 end,
             function() order[#order+1] = 3 end }
eq(Ess.stopAll(t2), 3, 'stopAll counts what it tore down')
eq(order[1], 3, 'stopAll runs in REVERSE order')
eq(order[3], 1, '...all the way down')
eq(Ess.stopAll("nope"), 0, 'stopAll on a non-table -> 0')
-- No hole test at all, deliberately. `#t` on an array with a nil hole is UNDEFINED in Lua -- it can be 1 or
-- 3 for the same table, at the implementation's discretion -- so any assertion about how far stopAll gets is
-- asserting nothing. Ess.stopAll's own doc comment tells callers to Ess.Table.compact first; that is the
-- contract, and a test cannot strengthen it.

-- Ess.Track:any bridges the two: mixed shapes in one tracker, all gone on :closeAll()
clear(); local tr = Ess.Track.new()
local hit = false
eq(tr:any("tick2"), "tick2", ':any returns its argument for chaining')
Ess.Loop._run["tick2"] = true
tr:any(function() hit = true end)
tr:any({ uGuid = "G" })
tr:closeAll()
assert(hit, ':closeAll ran the tracked closure')
eq(STOPLOG[#STOPLOG], "loop:tick2", ':closeAll tore down in reverse, loop registered first goes last')
return true
""",

    "Safe": r"""
local S = Ess.Safe
local ok,a,b = S.call(function(x) return x, x+1 end, 5); assert(ok==true and a==5 and b==6,'call success')
assert(S.call(function() error('boom') end)==false,'call failure -> false (logs via Ess.Log)')
assert(S.quiet(function() error('x') end)==false,'quiet failure -> false (no log)')
eq(S.string(true,'hi','fb'),'hi','string ok'); eq(S.string(true,123,'fb'),'fb','string non-string')
eq(S.string(false,'hi','fb'),'fb','string not-ok'); eq(S.string(true,nil),'?','string default fallback')
assert(S.template('VZ Soldier')==true,'template valid'); assert(S.template('')==false,'template empty')
assert(S.template('   ')==false,'template whitespace'); assert(S.template(nil)==false,'template nil')
assert(S.template(5)==false,'template non-string')

-- 6-value arity (was 4): the widest native return in the corpus is 4, so this is headroom -- but it has to
-- actually pass all six through, or a future wide call silently truncates exactly like the old form did.
local o,a1,b1,c1,d1,e1,f1 = S.call(function() return 1,2,3,4,5,6 end)
assert(o==true and a1==1 and f1==6,'call passes 6 values through')

assert(S.callv == nil,'no variadic form ships (untested path for a case that does not exist)')

-- Interior nils still land in the right slots in the fixed-arity form.
local oi,i1,i2,i3 = S.quiet(function() return 1,nil,3 end)
assert(oi==true and i1==1 and i2==nil and i3==3,'interior nils keep their positions')

-- Diagnostics. reset() first so this group's own asserts above don't pollute the counts.
S.reset()
assert(Ess.lastError()==nil,'reset clears lastError')
local _, total0 = S.stats(); eq(total0, 0, 'reset zeroes the total')
S.quiet(function() error('recorded') end)
local rec = Ess.lastError()
assert(rec ~= nil and string.find(rec.msg,'recorded',1,true) ~= nil,'quiet failure IS recorded (was invisible before)')
local _, total1 = S.stats(); eq(total1, 1, 'total counts a quiet failure')

-- With DEBUG off, the expensive half (label resolution + per-label tally) is skipped entirely.
local tallyOff = S.stats(); eq(#tallyOff, 0, 'DEBUG off -> no per-label tally')

-- With DEBUG on, named() attributes the failure to the label the caller supplied.
Ess.DEBUG = true
S.named('MyMod.thing', function() error('boom') end)
local t = S.stats()
assert(#t == 1 and t[1].label == 'MyMod.thing' and t[1].count == 1,'named() tallies under its own label')
S.named('MyMod.thing', function() error('boom') end)
eq(S.stats()[1].count, 2,'repeat failures accumulate under one label')
Ess.DEBUG = false
S.reset()

-- A SUCCESSFUL call must never be recorded -- if it were, the tally would be noise instead of a signal.
S.quiet(function() return 1 end); S.call(function() return 1 end)
local _, totalOk = S.stats(); eq(totalOk, 0,'successful calls are not recorded')

-- ---- channel 2: guard rejections (the common case -- see Ess.DEBUG's header) ----
-- Must ALWAYS return nil, so `return Ess.Safe.reject(...)` is a legal one-line early-out for any wrapper
-- whose contract is "nil on failure". A non-nil return here would silently corrupt every such caller.
S.reset(); Ess.DEBUG = false
assert(S.reject('Ess.X.y','no guid') == nil,'reject returns nil with DEBUG off')
local tOff, totOff = S.stats()
eq(#tOff, 0,'DEBUG off -> reject records nothing'); eq(totOff, 0,'DEBUG off -> reject does not bump total')
assert(Ess.lastError() == nil,'DEBUG off -> reject leaves lastError alone')

Ess.DEBUG = true
assert(S.reject('Ess.X.y','no guid') == nil,'reject returns nil with DEBUG on too')
local rj = Ess.lastError()
assert(rj ~= nil and rj.rejected == true,'rejection is flagged as a rejection, not a thrown error')
assert(rj.label == 'Ess.X.y','rejection carries its label')
assert(string.find(rj.msg,'no guid',1,true) ~= nil,'rejection carries the REASON, which a throw cannot')
eq(S.stats()[1].count, 1,'rejection tallies')

-- Rejections and throws share one tally, so stats() is a single "what is going wrong" list.
S.named('Ess.X.y', function() error('thrown') end)
eq(S.stats()[1].count, 2,'a throw and a rejection under one label accumulate together')
Ess.DEBUG = false; S.reset()
return true
""",
    "Math": r"""
local M = Ess.Math
eq(M.clamp(5,0,3),3,'clamp'); eq(M.clamp01(1.5),1,'clamp01'); eq(M.sign(-2),-1,'sign')
eq(M.round(2.5),3,'round'); eq(M.round(3.14159,2),3.14,'round dp')
eq(M.lerp(0,10,0.5),5,'lerp'); eq(M.remap(50,0,100,0,1),0.5,'remap'); eq(M.remap(1,0,0,7,9),7,'remap deg')
eq(M.smoothstep(0.5),0.5,'smoothstep'); eq(M.wrap(370,0,360),10,'wrap'); eq(M.wrap(-10,0,360),350,'wrap neg')
eq(M.normDeg(190),-170,'normDeg'); eq(M.lerpAngle(350,10,0.5),0,'lerpAngle'); eq(M.lerpAngle(350,10,1),10,'lerpAngle 1')
eq(M.dist2D(0,0,3,4),5,'dist2D'); eq(M.dist2DSq(0,0,3,4),25,'dist2DSq'); eq(M.dist3DSq(0,0,0,1,2,2),9,'dist3DSq')
assert(M.within2D(0,0,3,4,5) and not M.within2D(0,0,3,4,4),'within2D')
assert(M.within3D(0,0,0,1,2,2,3) and not M.within3D(0,0,0,1,2,2,2),'within3D')
eq(M.angleTo(0,0,0,1),0,'angleTo fwd')   -- facing +Z is yaw 0 in the engine convention
-- edges
eq(M.clamp(-5,0,3),0,'clamp lo'); eq(M.remap(150,0,100,0,1),1.5,'remap extrapolates')
assert(M.within2D(0,0,3,4,5) and not M.within2D(0,0,3,4,4.9),'within2D boundary'); eq(M.lerpAngle(10,350,0.5),0,'lerpAngle short way')
return true
""",
    "Str": r"""
local S = Ess.Str
eq(S.trim('  hi  '),'hi','trim')
eq(#S.split('a,b,c'),3,'split'); eq(S.split('a.b','.')[2],'b','split literal'); eq(#S.split('abc',''),3,'split chars')
eq(S.join({'a','b','c'},'-'),'a-b-c','join')
assert(S.startsWith('hello','he') and S.endsWith('hello','lo') and S.contains('hello','ell'),'affix')
eq(S.count('aaaa','aa'),2,'count nonoverlap')
eq(S.padLeft('5',3,'0'),'005','padLeft'); eq(S.capitalize('hi'),'Hi','cap'); eq(S.title('a b'),'A B','title')
eq(#S.lines('a\nb\nc'),3,'lines'); eq(#S.lines('a\nb\n'),2,'lines trailing')
eq(S.truncate('hello world',8),'hello...','truncate')
-- edges
eq(#S.split(',a,',','),3,'split leading/trailing'); eq(S.split('a','x')[1],'a','split no-match'); eq(S.trim('   '),'','trim all-ws')
assert(S.endsWith('x','') and S.startsWith('x',''),'affix empty'); eq(S.truncate('hello',5),'hello','trunc exact'); eq(S.padLeft('hello',3),'hello','pad already-longer')
eq(S.count('abc',''),0,'count empty needle'); eq(#S.lines(''),1,'lines empty')
return true
""",
    "Color": r"""
local C = Ess.Color
local function s(f,...) local r,g,b=f(...); return r..','..g..','..b end
eq(s(C.hex,'#ff8800'),'255,136,0','hex'); eq(s(C.hex,'f80'),'255,136,0','hex short')
assert(C.hex('xyz')==nil and C.hex('12345')==nil,'hex invalid')
eq(s(C.hsv,0,1,1),'255,0,0','hsv red'); eq(s(C.hsv,120,1,1),'0,255,0','hsv green'); eq(s(C.hsv,0,0,1),'255,255,255','hsv white')
eq(s(C.lerp,{0,0,0},{255,255,255},0.5),'128,128,128','lerp'); eq(s(C.of,'red'),'255,0,0','of')
assert(C.of('nope')==nil,'of nil')
-- edges
eq(s(C.hsv,360,1,1),'255,0,0','hsv wrap'); eq(s(C.hex,'#FF8800'),'255,136,0','hex uppercase')
eq(s(C.lerp,{0,0,0},{100,0,0},2),'100,0,0','lerp clamps t>1'); eq(s(C.of,'RED'),'255,0,0','of case-insensitive')
return true
""",
    "Table": r"""
local T = Ess.Table
eq(#T.keys({a=1,b=2}),2,'keys'); eq(T.count({a=1,b=2,c=3}),3,'count'); assert(T.isEmpty({}),'isEmpty')
assert(T.contains({1,2,3},2) and not T.contains({1,2,3},9),'contains'); eq(T.indexOf({10,20},20),2,'indexOf')
local m=T.map({1,2,3},function(v) return v*10 end); eq(m[3],30,'map')
local f=T.filter({1,2,3,4},function(v) return v%2==0 end); eq(#f,2,'filter')
local v,i=T.find({1,2,3},function(v) return v>1 end); eq(v,2,'find'); eq(i,2,'find idx')
local mg=T.merge({a=1},{b=2,a=9}); eq(mg.a,9,'merge'); eq(mg.b,2,'merge add')
-- compact: rebuild a hole (a[2]=nil) into a dense array
local h={10,20,30}; h[2]=nil; T.compact(h); eq(#h,2,'compact len'); eq(h[2],30,'compact shift')
local sl=T.slice({10,20,30,40},2,3); eq(#sl,2,'slice len'); eq(sl[1],20,'slice start'); eq(T.slice({1,2,3},2)[2],3,'slice default j')
local rv=T.reverse({1,2,3}); eq(rv[1],3,'reverse head'); eq(rv[3],1,'reverse tail')
eq(T.reduce({1,2,3,4},function(a,v) return a+v end,0),10,'reduce sum')
-- edges
eq(#T.slice({1,2,3},3,1),0,'slice reversed=empty'); eq(#T.slice({1,2,3},0,99),3,'slice clamps')
eq(T.reduce({1,2},function(a,v) return a..v end,'x'),'x12','reduce init'); eq(#T.filter({1,3},function(v) return v>10 end),0,'filter none')
assert(T.find({1,2},function(v) return v>9 end)==nil,'find none'); eq(T.merge({a=1},nil).a,1,'merge nil src')
assert(T.reverse({})[1]==nil and T.map({},function() end)[1]==nil,'empty-array ops')
return true
""",
    "RNG": r"""
-- :pick on a PLAIN array (raw values, not weight tables). Pre-0.4.0 this threw, because every entry was
-- indexed as e[weightKey] unconditionally -- so the obvious reading of "pick" was the one thing it couldn't do.
local rp = Ess.RNG.new(7)
local plain = { "a", "b", "c" }
local got = rp:pick(plain)
assert(got == "a" or got == "b" or got == "c", 'pick works on a plain array of strings')
local nums = { 10, 20, 30 }
local gotN = rp:pick(nums)
assert(gotN == 10 or gotN == 20 or gotN == 30, 'pick works on a plain array of numbers')
eq(rp:pick({ "only" }), "only", 'single-element plain array')
-- a MIXED list must not throw either: non-tables weigh 1, tables use their weight field
local mixed = { "bare", { w = 5, tag = "heavy" } }
for _ = 1, 20 do
    local m = rp:pick(mixed)
    assert(m == "bare" or (type(m) == "table" and m.tag == "heavy"), 'mixed list picks either shape')
end
-- weighted behaviour on table entries is UNCHANGED: w=0 alongside w=100 should never come up in 200 draws
local weighted = { { w = 0, tag = "never" }, { w = 100, tag = "always" } }
for _ = 1, 200 do eq(rp:pick(weighted).tag, "always", 'zero-weight entry is never picked') end

local g = Ess.RNG.new(42)
for _=1,50 do local n=g:int(6); assert(n>=1 and n<=6,'int range') end
local base={} for i=1,8 do base[i]=i end
local sh={} for i=1,8 do sh[i]=base[i] end; g:shuffle(sh)
eq(#sh,8,'shuffle len'); table.sort(sh); for i=1,8 do eq(sh[i],i,'shuffle multiset') end
local pn=g:pickN({1,2,3,4,5},3); eq(#pn,3,'pickN'); local seen={} for _,v in ipairs(pn) do assert(not seen[v],'pickN distinct'); seen[v]=true end
eq(#g:pickN({1,2,3},9),3,'pickN clamp'); eq(#g:pickN({1,2,3},0),0,'pickN zero')
-- weighted pick with a zero-weight entry should never return it
local picked={} for _=1,100 do picked[g:pick({{id='a',w=1},{id='z',w=0}}).id]=true end
assert(not picked['z'],'weighted skips w=0')
-- edges
assert(g:chance(1)==true and g:chance(0)==false,'chance edges'); eq(g:int(0),1,'int guards n<1')
assert(g:pick({{w=1,id='x'}}).id=='x','pick single'); assert(#g:shuffle({})==0,'shuffle empty')
return true
""",
    "Vec": r"""
local V = Ess.Vec
-- compare numerically, not by string: lupa's Lua 5.5 prints a float zero as "0.0" (5.1 prints "0"), so a
-- string compare would spuriously fail on exact components like a normalized 0.
local function c(a,b) return math.abs(a-b) < 1e-9 end
local function v(m,ex,ey,ez,x,y,z) assert(c(x,ex) and c(y,ey) and c(z,ez), m..' got '..x..','..y..','..z) end
assert(c(V.length(3,4,0),5),'length'); assert(c(V.length(0,0,0),0),'length0')
v('normalize',0.6,0.8,0, V.normalize(3,4,0)); v('normalize0',0,0,0, V.normalize(0,0,0))
v('scale',2,4,6, V.scale(1,2,3,2)); v('add',5,7,9, V.add(1,2,3,4,5,6)); v('sub',4,5,6, V.sub(5,7,9,1,2,3))
assert(c(V.dot(1,0,0,0,1,0),0) and c(V.dot(1,2,3,1,2,3),14),'dot')
v('dir',0,0,1, V.dir(0,0,0,0,0,5)); v('toward',0,0,3, V.toward(0,0,0,0,0,10,3)); v('lerp',5,5,5, V.lerp(0,0,0,10,10,10,0.5))
v('sub',1,0,0, V.sub(5,3,2,4,3,2)); assert(c(V.dot(2,0,0,3,0,0),6),'dot parallel')
return true
""",
    "Points": r"""
local P = Ess.Points
-- bucket by radius tier (r<=5 inf, r<=15 veh, else heli)
local b = P.bucket({{0,0,0,3},{0,0,0,10},{0,0,0,20}})
eq(#b.inf,1,'bucket inf'); eq(#b.veh,1,'bucket veh'); eq(#b.heli,1,'bucket heli')
local b2 = P.bucket({{0,0,0,20}})   -- no infantry-tier point -> inf falls back to the whole list
eq(#b2.inf,1,'bucket inf fallback'); eq(#b2.heli,1,'bucket heli2')
-- ideal: nearest-first within [minDist,maxDist] (Y ignored; points are {x,y,z,r})
local pts = {{0,0,60,3},{0,0,20,3},{0,0,40,3},{0,0,30,3},{0,0,50,3}}   -- z-dists 60,20,40,30,50 unsorted
local id = P.ideal(pts, 0,0, {minDist=10, maxDist=100, maxCount=24})
eq(#id,5,'ideal count'); eq(id[1][3],20,'ideal nearest first')
-- windowing + tier-2 fallback: [10,80] leaves {20,50} (<4), so drop the ceiling -> {20,50,200}
local id2 = P.ideal({{0,0,5,3},{0,0,20,3},{0,0,50,3},{0,0,200,3}}, 0,0, {minDist=10, maxDist=80})
eq(#id2,3,'ideal tier-2'); eq(id2[1][3],20,'ideal tier-2 nearest')
return true
""",
    "State": r"""
local s = Ess.State('checkpure', { a = 1 })
s.a = s.a + 4
local s2 = Ess.State('checkpure', { a = 1, b = 2 })   -- same table; new default b merged, a preserved
assert(s2 == s,'same table'); eq(s2.a,5,'preserved'); eq(s2.b,2,'merged default')
return true
""",
    "Time": r"""
-- frozen clock (elapsed always 0): a cooldown is ready once, then blocked inside its window
local ready = Ess.Time.cooldown(0.5)
assert(ready()==true,'cooldown first free'); assert(ready()==false,'cooldown blocks in window')
local clk = Ess.Time.clock(); assert(type(clk:delta())=='number','clock delta')
return true
""",
    "Names": r"""
local N = Ess.Names
-- degrades honestly with no table loaded: nil, and label falls back to the bare hash
assert(N.installed()==false,'not installed before load'); eq(N.count(),0,'count 0 uninstalled')
assert(N.of('0x0005EB70')==nil,'of() nil when uninstalled')
eq(N.label('0x0005EB70'),'0x0005EB70','label falls back to the bare hash')
-- adopt a fixture (E54047D5 is al_veh_boat_destroyer -- a real, plan-cited vector)
N.load({ ['0x0005EB70']='hp_snap_oilrig_bld_buildingC', ['0xE54047D5']='al_veh_boat_destroyer' })
assert(N.installed()==true,'installed after load'); eq(N.count(),2,'count')
eq(N.of('0x0005EB70'),'hp_snap_oilrig_bld_buildingC','exact hit')
-- normalisation: the same hash written lower-case, bare, or 0x-lower all resolve
eq(N.of('0x0005eb70'),'hp_snap_oilrig_bld_buildingC','lower-case hit')
eq(N.of('E54047D5'),'al_veh_boat_destroyer','bare (no 0x) hit')
eq(N.of('0xe54047d5'),'al_veh_boat_destroyer','0x + lower-case hit')
-- a NAME is not a hash and is never coerced into one; a miss is nil, never a fabricated name
assert(N.of('al_veh_boat_destroyer')==nil,'a name is not a hash')
assert(N.of('0xZZ')==nil,'non-hex -> nil'); assert(N.of('0xDEADBEEF')==nil,'unknown hash -> nil, never a guess')
eq(N.label('0xDEADBEEF'),'0xDEADBEEF','label of an unknown -> bare hash')
eq(N.label('0x0005eb70'),'hp_snap_oilrig_bld_buildingC (0x0005EB70)','label of a known -> "name (0xHASH)"')
return true
""",
    "Machine": r"""
-- Ess.Machine touches the engine, but its BRANCHING (name vs 0xHASH, the dead-state guard, hash resolution,
-- and the OnStateChange dispatch/chain) is pure decision logic -- provable against recording stubs shaped
-- like the real natives (ObjectState.SetState(g, nodeHash, stateHash) etc., confirmed in resident/oilrig.lua).
local M = Ess.Machine
local SET = {}
_G.String = { GetHash = function(s) return "H:" .. s end }
_G.Sys.GuidToString = function(g) if type(g)=='string' then return g end return g and g.s or nil end
_G.Sys.StringToGuid = function(s) return "G:" .. s end
_G.ObjectState = { SetState = function(g,n,st) SET[#SET+1] = {g=g,n=n,st=st} end }

-- a NAME node + a KNOWN state name are both hashed through String.GetHash (== the engine's own call shape)
Ess.DEBUG = false
assert(M.set('OBJ','hp_snap_x','CollapseState')==true,'set name/name')
eq(SET[1].n,'H:hp_snap_x','node name -> String.GetHash'); eq(SET[1].st,'H:CollapseState','state name -> String.GetHash')
-- a bare 0xHASH goes the Sys.StringToGuid route, and a 0xHASH state bypasses the vocabulary check
assert(M.set('OBJ','0x11','0xACB51200')==true,'set hash/hash'); eq(SET[2].n,'G:0x11','node hash -> StringToGuid')
-- a state NAME outside the global vocabulary is DEAD (never reached by damage) -> refused, no call issued
local before=#SET
assert(M.set('OBJ','hp','BogusState')==nil,'unknown state name refused')
eq(#SET,before,'no SetState issued for a dead state name')
assert(M.set(nil,'hp','PristineState')==nil,'no guid refused')
-- name(): a state hash -> its vocabulary name; unknown -> the bare hash, never a guess
eq(M.name('0x694683EB'),'CollapseState','known state hash -> name')
eq(M.name('0x0ACE072A'),'InitState','cracked state hash -> name')
eq(M.name('0xDEADBEEF'),'0xDEADBEEF','unknown state hash -> bare hash')
eq(M.name({s='0x7687DF41'}),'DestroyedState','a state GUID resolves via Sys.GuidToString')
eq(#M.vocab(),13,'vocab lists all 13 known states')
-- onChange: the engine fires the global with GUIDs; our dispatcher enriches + chains any prior
local seen, prior = {}, {}
_G.OnStateChange = function(g,n,s) prior[#prior+1]=g end     -- a "mission's own" hook present first
local stop = M.onChange(function(g, sState, sNode) seen[#seen+1]={g=g,st=sState} end)
_G.OnStateChange('OBJ', {s='0x1'}, {s='0x694683EB'})
eq(#seen,1,'handler fired'); eq(seen[1].st,'CollapseState','handler got the enriched state NAME')
eq(#prior,1,'the pre-existing OnStateChange was chained, not clobbered')
stop(); _G.OnStateChange('OBJ2', {s='0x1'}, {s='0x7687DF41'})
eq(#seen,1,'after stop() the handler no longer fires'); eq(#prior,2,'the chained prior still fires')
return true
""",
    "Ecs": r"""
-- Ess.Ecs is a pure lookup over the generated 232-class registry; the hashes are pandemic_hash_m2(name),
-- verified against the RE (RuntimeHealth=0xF9B9B2A5, StateMachine=0x98A3661F).
local E = Ess.Ecs
eq(#E.classes(), 232, '232 classes')
eq(#E.families(), 9, '9 families')
-- exact get (case-insensitive) + the derived hash/family readers
local c = E.get('RuntimeHealth'); assert(c and c.n=='RuntimeHealth', 'get RuntimeHealth')
eq(c.h, '0xF9B9B2A5', 'RuntimeHealth hash'); eq(c.f, 'gameplay_state_health_mission', 'RuntimeHealth family')
eq(E.get('runtimehealth').n, 'RuntimeHealth', 'get is case-insensitive')
eq(E.hash('StateMachine'), '0x98A3661F', 'StateMachine hash')
eq(E.family('ControllerCar'), 'controllers_physics', 'family()')
-- misses are nil, never a guess
assert(E.get('NoSuchComponent')==nil,'unknown class -> nil'); assert(E.hash('NoSuchComponent')==nil,'unknown hash -> nil')
assert(E.hash(nil)==nil,'nil -> nil')
-- find matches on name OR family, case-insensitive
assert(#E.find('controller') > 1, 'find matches many controllers')
assert(#E.find('ai_perception_population') > 1, 'find matches a whole family')
eq(#E.find('zzzznope'), 0, 'find miss -> empty')
-- every hash is a canonical 0x + 8 hex string (the resolver-key form, dodging the Lua-float trap)
for _, cc in ipairs(E.classes()) do
    assert(type(cc.h)=='string' and cc.h:match('^0x%x%x%x%x%x%x%x%x$'), 'canonical hash: '..tostring(cc.h))
end
return true
""",
    "Inspect": r"""
-- Ess.Inspect composes engine getters into a typed record; the RECORD ASSEMBLY, the handle->name resolution
-- (Object.GetModelName returns an opaque HANDLE -> Sys.GuidToString -> Ess.Names -- verified live), the
-- 1/0-bool coercion and the formatting are pure logic, provable against stubs shaped like the real getters.
_G.Sys.GuidToString = function(g) if type(g)=='string' then return g end return g and g.s or nil end
_G.Sys.StringToGuid = function(s) return s end
_G.Object.GetName = function(g) return {s="0x000BF11E"} end          -- opaque HANDLE, not a string
_G.Object.GetModelName = function(g) return {s="0xB4FE2B80"} end     -- (0xB4FE2B80 = civ_veh_car_veyron live)
Ess.Object = {
  valid=function(g) return g~='dead' end, alive=function() return true end,
  health=function() return 42 end, maxHealth=function() return 100 end, invincible=function() return false end,
  playerControlled=function() return 1 end,   -- engine 1/0; 0 is truthy in Lua, so it MUST be coerced
  pos=function() return 12.0,4.0,-67.0 end, yaw=function() return 1.57 end,
  velocity=function() return 0,0,0 end, speed=function() return 0.0 end,
  physicsType=function() return 2 end, awake=function() return true end, hibernated=function() return false end,
  vehicleOf=function() return nil end, parent=function() return nil end, attached=function() return {} end,
}
Ess.Vehicle = { driver=function() return nil end, seatOf=function() return nil end }
Ess.Probe = { getFaction=function() return "OC" end }
Ess.Names.load({ ["0x000BF11E"]="residential_bld_corner110x126_ruin", ["0xB4FE2B80"]="civ_veh_car_veyron" })

local r = Ess.Inspect("0x4000C068")     -- callable sugar == Ess.Inspect.read
assert(r ~= nil, 'record'); eq(r.name,'residential_bld_corner110x126_ruin','name from GetName HANDLE via Ess.Names')
eq(r.model,'civ_veh_car_veyron','model from GetModelName handle'); eq(r.health,42,'health'); eq(r.maxHealth,100,'maxHealth')
assert(r.playerControlled == true, '1/0 engine bool coerced to true'); assert(r.alive == true,'alive')
assert(r.pos and r.pos.x==12.0 and r.pos.z==-67.0,'pos table'); eq(r.faction,'OC','faction')
eq(Ess.Inspect.read('0x1').name, r.name, 'read() == callable sugar')
assert(Ess.Inspect('dead')==nil,'invalid guid -> nil'); assert(Ess.Inspect(nil)==nil,'nil guid -> nil')
local ln = Ess.Inspect.line('0x4000C068')
assert(type(ln)=='string' and ln:find('residential_bld',1,true) and ln:find('hp=42/100',1,true) and ln:find('OC',1,true),'line: '..ln)
eq(Ess.Inspect.line('dead'),'<nil or invalid>','line invalid')
-- a handle Ess.Names can't reverse degrades to the bare hash, never a guess
_G.Object.GetName = function(g) return {s="0xDEADBEEF"} end
eq(Ess.Inspect.read('0x1').name,'0xDEADBEEF','unresolved handle -> bare hash')
return true
""",
}


def main():
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute(STUBS)
    for name in SRC_FILES:
        L.execute((SRC / name).read_text(encoding="utf-8"))

    passed = failed = 0
    for group, chunk in TESTS.items():
        try:
            L.execute(PRELUDE + chunk)
            print("[PASS] %s" % group)
            passed += 1
        except lupa.LuaError as e:
            print("[FAIL] %s -- %s" % (group, e))
            failed += 1
    print("\n%d group(s) passed, %d failed" % (passed, failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
