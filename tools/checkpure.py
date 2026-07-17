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
SRC_FILES = ["00_core.lua", "01_math.lua", "02_str.lua", "03_color.lua",
             "22_state.lua", "23_time.lua", "53_rng.lua"]

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
