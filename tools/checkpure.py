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
SRC_FILES = ["00_core.lua", "01_math.lua", "02_str.lua", "03_color.lua", "04_vec.lua",
             "22_state.lua", "23_time.lua", "53_rng.lua", "52_points.lua"]

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
"""

# each test chunk asserts, then `return true`. eq() gives a readable message on mismatch.
PRELUDE = "local function eq(a,b,m) assert(a==b, (m or '')..' got '..tostring(a)) end\n"

TESTS = {
    "Safe": r"""
local S = Ess.Safe
local ok,a,b = S.call(function(x) return x, x+1 end, 5); assert(ok==true and a==5 and b==6,'call success')
assert(S.call(function() error('boom') end)==false,'call failure -> false (logs via Ess.Log)')
assert(S.quiet(function() error('x') end)==false,'quiet failure -> false (no log)')
eq(S.string(true,'hi','fb'),'hi','string ok'); eq(S.string(true,123,'fb'),'fb','string non-string')
eq(S.string(false,'hi','fb'),'fb','string not-ok'); eq(S.string(true,nil),'?','string default fallback')
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
