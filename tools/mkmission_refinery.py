#!/usr/bin/env python3
"""mkmission_refinery.py -- turn the MissionForge export for the oil-refinery assault into a runnable
Ess.Contract Lua file (samples/missions/refinery_assault.lua).

A FIRST, mission-specific step toward closing the web-tool pipeline gap (the export still emits the old
Contract.Register; there's no cinematic authoring). NOT yet a general export->contract compiler:
- the bulky `def.units` block IS generated straight from the export (faithful coords, faction-regrouped),
- the creative parts (intro cinematic, objective tuning, trigger/FX wiring) are hand-authored constants here
  and reference the export only for coordinates, so re-placing things in MissionForge + re-exporting +
  re-running this keeps positions in sync.

Usage:  python tools/mkmission_refinery.py
Reads:  samples/missions/refinery_assault.export.txt
Writes: samples/missions/refinery_assault.lua
"""
import os, re

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
EXPORT = os.path.join(REPO, "samples", "missions", "refinery_assault.export.txt")
OUT    = os.path.join(REPO, "samples", "missions", "refinery_assault.lua")

# Templates the INTRO CINEMATIC owns (it spawns + animates + destroys these). They must NOT also appear in
# def.units, because def.units spawn only AFTER the cutscene ends.
CINEMATIC_OWNED = {
    "Ka29b (Full)", "WZ10 (Full)", "Mi26 (CH) (Driver)",
    "HMMWV (Avenger) (Full)", "LAVIII (AD) (Full)",
}

UNIT_RE = re.compile(
    r'faction="(?P<fac>\w+)",\s*kind="(?P<kind>\w+)",\s*spawn="(?P<spawn>[^"]+)",'
    r'\s*placeholder="[^"]*",\s*x=(?P<x>-?[\d.]+),\s*y=(?P<y>-?[\d.]+),'
    r'\s*z=(?P<z>-?[\d.]+),\s*yaw=(?P<yaw>-?[\d.]+)'
)

def group_for(fac, kind):
    if fac == "ALLIED":
        return "ALLIED" if kind == "infantry" else "ALLIED_NAVY"
    if fac == "CHINA":
        return "CHINA"
    return fac

def gen_units(text):
    lines, kept, skipped = [], 0, 0
    for m in UNIT_RE.finditer(text):
        spawn = m.group("spawn")
        if spawn in CINEMATIC_OWNED:
            skipped += 1
            continue
        grp = group_for(m.group("fac"), m.group("kind"))
        lines.append(
            '    {{ spawn="{s}", x={x}, y={y}, z={z}, yaw={yaw}, group="{g}" }},'.format(
                s=spawn, x=m.group("x"), y=m.group("y"), z=m.group("z"),
                yaw=m.group("yaw"), g=grp))
        kept += 1
    return "\n".join(lines), kept, skipped

# ------------------------------------------------------------------ hand-authored Lua around the units
HEADER = '''-- refinery_assault.lua -- WORKED EXAMPLE MISSION: offshore oil-refinery assault (China vs Allies, you back
-- China). Built from the MissionForge export (refinery_assault.export.txt) via tools/mkmission_refinery.py.
--
-- HOW IT'S PUT TOGETHER (the load-bearing bit a new author must understand):
--   Ess.Contract.Accept -> teleports you to def.start -> applies def.relations -> PLAYS def.cinematic ->
--   and only THEN spawns def.units + runs the objectives. So anything the intro shows or blows up (the
--   incoming helis, the doomed pad-AA "SAM site", the landing transport) is spawned BY THE CINEMATIC, not
--   by def.units -- those don't exist yet while the camera is on them. The rig's defenders and your Chinese
--   ground squad are def.units; they appear when the fade clears and you take control.
--
-- Relations are set before the cutscene, so the allied pad-AA is already hostile to the Chinese helis and
-- opens fire on its own; the intro also script-kills one heli so a downing is guaranteed.

if not _G.Ess then Loader.Printf("[refinery] Ess framework not loaded -- deploy dist/Ess.lua first"); return end
local Ess = _G.Ess
local C   = Ess.Contract

-- =====================================================================================================
-- INTRO CINEMATIC -- owns the aircraft + the SAM site. Camera vantages/look-points are the ones placed in
-- MissionForge (the export's `cinematic` block); the sequencing/holds are authored here.
-- =====================================================================================================
local INTRO = {
  -- spawn the WHOLE air wave (Chinese, hostile) + the allied pad-AA that fires on it. Spawned first, on the
  -- opening black, so the establishing shot frames them already massing. All ephemeral (gone at the cut-out)
  -- except the transport further down.
  { type="spawn", template="WZ10 (Full)",  at={x=-382.23,y=28.36,z=2237.92}, yaw=-11.342, name="wz_lead", group="airwave", ephemeral=true, hold=0 },
  { type="spawn", template="WZ10 (Full)",  at={x=-415.39,y=28.59,z=2255.97}, yaw=-9.501,  name="wz2",     group="airwave", ephemeral=true, hold=0 },
  { type="spawn", template="WZ10 (Full)",  at={x=-449.86,y=28.94,z=2251.63}, yaw=-7.098,  name="wz3",     group="airwave", ephemeral=true, hold=0 },
  { type="spawn", template="Ka29b (Full)", at={x=-438.53,y=31.23,z=2101.45}, yaw=-8.939,  name="ka1",     group="airwave", ephemeral=true, hold=0 },
  { type="spawn", template="Ka29b (Full)", at={x=-319.83,y=30.84,z=2130.35}, yaw=-18.026, name="ka2",     group="airwave", ephemeral=true, hold=0 },
  { type="spawn", template="HMMWV (Avenger) (Full)", at={x=-523.16,y=-2.18,z=2604.95}, yaw=-172.356, name="aa1", group="padAA", ephemeral=true, hold=0 },
  { type="spawn", template="HMMWV (Avenger) (Full)", at={x=-500.07,y=-2.18,z=2602.85}, yaw=177.321,  name="aa2", group="padAA", ephemeral=true, hold=0 },
  { type="spawn", template="LAVIII (AD) (Full)",     at={x=-511.17,y=-2.18,z=2612.02}, yaw=-179.649, name="aa3", group="padAA", ephemeral=true, hold=0 },

  -- establish: high over the ocean, framing the massing wave; fade in from black
  { type="camera", at={x=-343.02,y=49.85,z=2521.36}, lookAt={x=-453.04,y=31.26,z=2240.30}, hold=0 },
  { type="fade", to=0, hold=0 },
  { type="music", cue="mu_pmc_panicloop_01", hold=0 },
  { type="subtitle", text="The Allies have too much oil. We'd like you to relieve them of it.", hold=4 },

  -- send the WHOLE wave in, fanned across the rig approach
  { type="fly", target="wz_lead", at={x=-497,y=32,z=2662}, hold=0 },
  { type="fly", target="wz2",     at={x=-470,y=34,z=2650}, hold=0 },
  { type="fly", target="wz3",     at={x=-525,y=30,z=2648}, hold=0 },
  { type="fly", target="ka1",     at={x=-505,y=36,z=2690}, hold=0 },
  { type="fly", target="ka2",     at={x=-455,y=38,z=2700}, hold=0 },

  -- watch them cross the rig for a good beat -- a trailing shot on the lead (tracks its pilot's chest bone
  -- to stay smooth on a moving heli)
  { type="subtitle", text="Air wave inbound over the rig.", hold=0 },
  { type="chase", target="wz_lead", look="wz_lead", bone="Bone_Chest", dist=36, height=13, angle=200, hold=12 },

  -- frame the pad: the allied triple-A is firing on the wave now
  { type="camera", at={x=-431.80,y=31.77,z=2509.82}, lookAt={x=-515.90,y=17.81,z=2633.29}, hold=3 },
  { type="subtitle", text="Watch their triple-A on the deck.", hold=0 },

  -- one of ours goes down (guaranteed, on top of any live AA fire), now that we've seen the flight
  { type="func", fn=function(ctx) if ctx.named.wz2 then pcall(Object.Kill, ctx.named.wz2) end end, hold=0 },
  { type="shake", preset="ShakeCameraMedium", amplitude=7, duration=2, hold=0 },
  { type="subtitle", text="They got one of ours!", hold=2.5 },

  -- scripted artillery wipes the SAM site; the pad is clear
  { type="func", fn=function(ctx)
      local px, py, pz = -511, -2, 2607
      for i=1,6 do
        local dx, dz = (i*37 % 22) - 11, (i*53 % 22) - 11
        pcall(Event.Create, Event.TimerRelative, { 0.3*(i-1) }, function()
          pcall(Airstrike.SpawnOrdnance, "Gunship Shell", px+dx, py+220, pz+dz, 0, -100, 0, "impact", 1, nil)
        end)
      end
      for _, n in ipairs({"aa1","aa2","aa3"}) do
        local g = ctx.named[n]
        if g then pcall(Event.Create, Event.TimerRelative, { 1.1 }, function() pcall(Object.Kill, g) end) end
      end
    end, hold=0 },
  { type="shake", preset="ShakeCameraLarge", amplitude=9, duration=3, hold=0 },
  { type="subtitle", text="Arty's zeroing the SAMs -- the pad is clear.", hold=3.5 },

  -- friendly transport lands at the ORIGINAL landing point (persists -- it's your ride out). The strike
  -- destroys the pad, so this landing spot -- back where you start -- is the extraction LZ you retreat to.
  { type="spawn", template="Mi26 (CH) (Driver)", at={x=-455.63,y=48,z=2635.81}, yaw=-141.769, name="transport", hold=0 },
  { type="fly", target="transport", at={x=-455.63,y=11,z=2635.81}, height=11, hold=0 },
  { type="camera", at={x=-431.80,y=20,z=2600}, look="transport", hold=4.5 },
  { type="subtitle", text="Transport's down. Move out, merc.", hold=0 },

  -- fade to black; when the cutscene ends, def.units spawn and you take control
  { type="fade", to=1, hold=1.5 },
}

'''

FOOTER_TMPL = '''
-- =====================================================================================================
-- THE CONTRACT
-- =====================================================================================================
C.Register({
  id = "refinery_assault",
  title = "Relieve Them Of It",
  category = "EXAMPLE",
  briefing = "The Allies are sitting on an offshore refinery. China wants it. Ride the air assault in, "
          .. "plant a charge on the core, hold while it arms, then fall back to the transport before the rig goes up.",
  reward = { cash = 250000, fuel = 200 },

  -- the rig genuinely collapses under the mission's explosions/RPGs -- wrap the whole thing in a save-gated
  -- sandbox so that destruction lives only in memory and never serializes (pristine rig on the next load).
  sandbox = true,

  -- you spawn on the deck where the transport dropped you (the MissionForge spawn marker)
  start = { x=-461.91, y=9.91, z=2636.13, yaw=-92.768 },

  -- China + you (PMC) vs the Allied garrison. Applied BEFORE the cutscene so the pad-AA engages the helis.
  relations = {
    { "China",  "PMC",    "friend" },
    { "China",  "Allied", "enemy"  },
    { "PMC",    "Allied", "enemy"  },
  },

  cinematic = INTRO,

  -- the playable roster (spawns after the cutscene). Faction-regrouped from the export's flat "A":
  --   ALLIED = rig infantry (defend the core), ALLIED_NAVY = the boats, CHINA = your ground squad.
  units = {
{UNITS}
  },

  objectives = {
    C.Interact{ desc = "Plant the charge on the refinery core", at = {-526.89,-2.10,2737.72}, radius = 6, time = 5 },
    C.Survive{  desc = "Hold the core while the charge arms",   time = 60 },
    -- extract moved to the ORIGINAL transport-landing point (the strike destroys the old pad). Boards the
    -- crewed transport (no transit UI) + flies a couple of victory-lap orbits before the mission finalizes.
    C.Extract{  desc = "Fall back to the transport and extract", at = {-455.63,9.85,2635.81}, radius = 12,
                boardTime = 2, heli = "Mi26 (CH) (Driver)",
                victoryLap = { orbits = 2, radius = 110, height = 55, line = "Rig's ours. Let's take her home." } },
  },

  -- Allied garrison digs in around the core; your Chinese squad pushes up once you advance past the start.
  waypoints = {
    { id="allied_hold", group="ALLIED", behavior="defend", at={-524.02,9.90,2714.44}, radius=35.7 },
    { id="china_push",  group="CHINA",  behavior="move",   at={-524.02,9.90,2714.44}, trigger={ref="t_push"} },
  },

  -- FX gated behind the CHARGE ARMING (objective 2 complete), NOT raw proximity -- so the rig only starts
  -- coming apart once you've planted+held and are falling back, not on the walk in.
  support = {
    { id="say_start",   effect="say", text="Push to the rig -- clear those defenders!",              hold=6, trigger={ref="t_start"} },
    { id="say_extract", effect="say", text="Charge is set -- the whole rig's coming down. Get to the transport!", hold=7, trigger={ref="charge_armed"} },
    { id="arty_chaos",  effect="artillery", at={-501.62,-2,2680.34}, radius=16, count=8, owner="China", trigger={ref="charge_armed"} },
    { id="shake1",      effect="shake", preset="ShakeCameraLarge", amplitude=8, duration=5, trigger={ref="charge_armed"} },
{VFX}
  },

  triggers = {
    { id="t_start",      kind="proximity", at={-468.46,9.91,2636.89}, radius=8 },   -- kickoff line (you spawn on it)
    { id="t_push",       kind="proximity", at={-487.92,9.91,2641.16}, radius=6 },   -- your squad advances
    { id="charge_armed", kind="objective", index=2 },                               -- survive done -> the rig comes down
  },

  onComplete = function() Ess.Log("[refinery] rig secured -- extraction complete") end,
  onFail     = function() Ess.Log("[refinery] mission failed") end,
})

-- Auto-accept for live testing. Comment this out to instead accept it from the contract board (F5).
C.Accept("refinery_assault")
Loader.Printf("[refinery] registered + accepted 'refinery_assault'")
'''

# vfx + flyby supports pulled straight from the export coords; ALL gated behind charge_armed (the "rig comes
# apart as you fall back" cascade). Each vfx gets a small 2-blast cluster for more visual weight.
VFX_ALL = [
    (-538.93, -2.09, 2644.25), (-548.96, -2.09, 2663.80), (-547.31, -2.09, 2675.10),
    (-531.76, -2.09, 2644.83), (-500.50, -2.09, 2667.69), (-500.51, -2.09, 2685.71),
    (-500.49, -2.09, 2700.31), (-496.20, -2.10, 2650.92), (-495.67, -2.08, 2635.32),
    (-527.84, -2.08, 2631.47),
]
FLYBY_ALL = [
    (-523.23, -0.74, 2603.85), (-511.33, 0.13, 2610.35), (-500.01, -0.73, 2601.75),
]

def gen_vfx():
    out, i = [], 0
    for (x, y, z) in VFX_ALL:
        i += 1
        out.append('    {{ id="vfx{i}", effect="vfx", at={{{x},{y},{z}}}, count=2, radius=4, trigger={{ref="charge_armed"}} }},'.format(i=i, x=x, y=y, z=z))
    j = 0
    for (x, y, z) in FLYBY_ALL:
        j += 1
        out.append('    {{ id="flyby{j}", effect="flyby", at={{{x},{y},{z}}}, trigger={{ref="charge_armed"}} }},'.format(j=j, x=x, y=y, z=z))
    return "\n".join(out)

def main():
    with open(EXPORT, "r", encoding="utf-8") as f:
        text = f.read()
    units, kept, skipped = gen_units(text)
    body = HEADER + FOOTER_TMPL.replace("{UNITS}", units).replace("{VFX}", gen_vfx())
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(body)
    print("wrote {}  ({} def.units kept, {} cinematic-owned skipped)".format(
        os.path.relpath(OUT, REPO), kept, skipped))

if __name__ == "__main__":
    main()
