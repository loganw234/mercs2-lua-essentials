#!/usr/bin/env python3
"""mkmission_refinery.py -- turn the MissionForge export for the oil-refinery assault into a runnable
Ess.Contract Lua file (samples/missions/refinery_assault.lua).

A FIRST, mission-specific step toward closing the web-tool pipeline gap. NOT a general export->contract
compiler: the bulky rosters are generated from the export (faithful coords), while the intro cinematic +
objective/trigger/FX wiring are hand-authored constants that reference the export only for coordinates.

Roster classification (from the export):
  - CINEMATIC_OWNED templates  -> handled by the hand-authored INTRO (spawned + animated + destroyed there)
  - ROCKET_UNITS               -> DROPPED (they shred the fragile rig too fast)
  - allied boats + allied infantry near the pad (z < PRESPAWN_Z) -> PRE-SPAWNED in the intro (set dressing
                                  visible during the cutscene: ships in the water, guards around the AA)
  - everything else            -> def.units (spawn after the cutscene when you take control)

Usage:  python tools/mkmission_refinery.py
Reads:  samples/missions/refinery_assault.export.txt
Writes: samples/missions/refinery_assault.lua
"""
import os, re

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
EXPORT = os.path.join(REPO, "samples", "missions", "refinery_assault.export.txt")
OUT    = os.path.join(REPO, "samples", "missions", "refinery_assault.lua")

CINEMATIC_OWNED = {
    "Ka29b (Full)", "WZ10 (Full)", "Mi26 (CH) (Driver)",
    "HMMWV (Avenger) (Full)", "LAVIII (AD) (Full)",
}
ROCKET_UNITS = { "Chinese Heavy (RPG)", "Allied Heavy (AT Rocket)" }
PRESPAWN_Z = 2645.0   # allied set-dressing south of this (the pad/AA cluster) spawns during the intro

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

def classify(fac, kind, spawn, z):
    if spawn in CINEMATIC_OWNED: return "skip"
    if spawn in ROCKET_UNITS:    return "drop"
    if fac == "ALLIED" and kind == "vehicle":                        return "prespawn"   # boats
    if fac == "ALLIED" and kind == "infantry" and z < PRESPAWN_Z:    return "prespawn"   # pad/AA guards
    return "defunit"

def gen_rosters(text):
    prespawn, defunits = [], []
    counts = { "skip": 0, "drop": 0, "prespawn": 0, "defunit": 0 }
    for m in UNIT_RE.finditer(text):
        fac, kind, spawn = m.group("fac"), m.group("kind"), m.group("spawn")
        x, y, z, yaw = m.group("x"), m.group("y"), m.group("z"), m.group("yaw")
        cat = classify(fac, kind, spawn, float(z))
        counts[cat] += 1
        if cat == "prespawn":
            # small stagger (hold) so the set dressing spawns a few per frame under black, not all at once
            prespawn.append('  {{ type="spawn", template="{s}", at={{x={x},y={y},z={z}}}, yaw={yaw}, hold=0.1 }},'.format(
                s=spawn, x=x, y=y, z=z, yaw=yaw))
        elif cat == "defunit":
            defunits.append('    {{ spawn="{s}", x={x}, y={y}, z={z}, yaw={yaw}, group="{g}" }},'.format(
                s=spawn, x=x, y=y, z=z, yaw=yaw, g=group_for(fac, kind)))
    return "\n".join(prespawn), "\n".join(defunits), counts

# ------------------------------------------------------------------ hand-authored Lua around the rosters
HEADER = '''-- refinery_assault.lua -- WORKED EXAMPLE MISSION: offshore oil-refinery assault (China vs Allies, you back
-- China). Built from the MissionForge export (refinery_assault.export.txt) via tools/mkmission_refinery.py.
--
-- HOW IT'S PUT TOGETHER (the load-bearing bit a new author must understand):
--   Ess.Contract.Accept -> teleports you to def.start -> applies def.relations -> PLAYS def.cinematic ->
--   and only THEN spawns def.units + runs the objectives. So anything the intro shows or blows up -- the
--   incoming helis, the doomed pad-AA "SAM site", the transport, and the intro set-dressing (boats + the
--   guards around the AA) -- is spawned BY THE CINEMATIC, not by def.units (those don't exist yet while the
--   camera is on them). The rig's core defenders + your Chinese ground squad are def.units; they appear
--   when the fade clears and you take control.
--
-- Relations are set before the cutscene, so the allied pad-AA is already hostile to the Chinese helis and
-- opens fire on its own; the intro also script-kills one heli so a downing is guaranteed.

if not _G.Ess then Loader.Printf("[refinery] Ess framework not loaded -- deploy dist/Ess.lua first"); return end
local Ess = _G.Ess
local C   = Ess.Contract

-- =====================================================================================================
-- INTRO CINEMATIC. Opens on black (opts.startFade + a pre-Accept fade) so the character is never seen
-- standing on the rig before the camera takes over.
-- =====================================================================================================
local INTRO = {
  -- ESTABLISH THE SHOT FIRST (under black): fixed vantage at Logan's placed "preview" camera point, framing
  -- his placed look point out at the heli staging area. The look POINT is anchor-backed by the framework now
  -- (a coord SetLookAt doesn't bind, so placeCamera would no-op) -- so the vantage actually takes effect.
  -- NO camera movement anywhere in this intro (static vantage, only the look target changes).
  { type="camera", at={x=-343.02,y=49.85,z=2521.36}, lookAt={x=-453.04,y=31.26,z=2240.30}, hold=0 },

  -- set dressing, spawned STAGGERED under black (a few per frame -> no one-frame spawn spike): allied ships
  -- in the water + the guards around the AA guns (generated from the export)
{PRESPAWN}

  -- the air wave (Chinese, hostile), also staggered. A FEW persist past the cutscene (Logan: leave some helis
  -- in the fight); wz2 is the guaranteed downing and ka2 is ephemeral, the rest stay.
  { type="spawn", template="WZ10 (Full)",  at={x=-382.23,y=28.36,z=2237.92}, yaw=-11.342, name="wz_lead", group="airwave", hold=0.12 },
  { type="spawn", template="WZ10 (Full)",  at={x=-415.39,y=28.59,z=2255.97}, yaw=-9.501,  name="wz2",     group="airwave", ephemeral=true, hold=0.12 },
  { type="spawn", template="WZ10 (Full)",  at={x=-449.86,y=28.94,z=2251.63}, yaw=-7.098,  name="wz3",     group="airwave", hold=0.12 },
  { type="spawn", template="Ka29b (Full)", at={x=-438.53,y=31.23,z=2101.45}, yaw=-8.939,  name="ka1",     group="airwave", hold=0.12 },
  { type="spawn", template="Ka29b (Full)", at={x=-319.83,y=30.84,z=2130.35}, yaw=-18.026, name="ka2",     group="airwave", ephemeral=true, hold=0.12 },
  -- the allied pad-AA "SAM site": fires on the wave (relations already hostile), then the strike wipes it
  { type="spawn", template="HMMWV (Avenger) (Full)", at={x=-523.16,y=-2.18,z=2604.95}, yaw=-172.356, name="aa1", group="padAA", ephemeral=true, hold=0.12 },
  { type="spawn", template="HMMWV (Avenger) (Full)", at={x=-500.07,y=-2.18,z=2602.85}, yaw=177.321,  name="aa2", group="padAA", ephemeral=true, hold=0.12 },
  { type="spawn", template="LAVIII (AD) (Full)",     at={x=-511.17,y=-2.18,z=2612.02}, yaw=-179.649, name="aa3", group="padAA", ephemeral=true, hold=0.4 },

  -- send the wave in, fanned across the approach (they head for the AA/rig)
  { type="fly", target="wz_lead", at={x=-497,y=32,z=2662}, hold=0 },
  { type="fly", target="wz2",     at={x=-505,y=30,z=2620}, hold=0 },
  { type="fly", target="wz3",     at={x=-525,y=30,z=2648}, hold=0 },
  { type="fly", target="ka1",     at={x=-505,y=36,z=2690}, hold=0 },
  { type="fly", target="ka2",     at={x=-455,y=38,z=2700}, hold=0 },

  -- REVEAL: fade in on the wave coming off the sea; watch for a few seconds (static shot, no movement).
  { type="fade", to=0, hold=0 },
  { type="music", cue="mu_pmc_panicloop_01", hold=0 },
  { type="subtitle", text="The Allies have too much oil. We'd like you to relieve them of it.", hold=6 },

  -- FOCUS over on the AA guns (Logan's placed pad look point) -- the helis have naturally reached there by
  -- now, so both are framed. Re-aim ONLY (same vantage) -- no camera move.
  { type="camera", at={x=-343.02,y=49.85,z=2521.36}, lookAt={x=-515.90,y=17.81,z=2633.29}, hold=4 },
  { type="subtitle", text="They're on the triple-A now.", hold=0 },

  -- a heli goes down at the pad (guaranteed, on top of any live AA fire)
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

  -- friendly transport touches down (CLEAR of your drop point so it can't shove you into the sea)
  { type="spawn", template="Mi26 (CH) (Driver)", at={x=-448,y=48,z=2612}, yaw=-141.769, name="transport", hold=0 },
  { type="fly", target="transport", at={x=-448,y=11,z=2612}, height=11, hold=0 },
  { type="camera", at={x=-343.02,y=49.85,z=2521.36}, look="transport", hold=4.5 },
  { type="subtitle", text="Transport's down. Move out, merc.", hold=0 },

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
          .. "plant a charge on the core, hold while it arms, then fall back to the LZ before the rig goes up.",
  reward = { cash = 250000, fuel = 200 },

  -- the rig genuinely collapses under the mission's explosions -- wrap the whole thing in a save-gated
  -- sandbox so that destruction lives only in memory and never serializes (pristine rig on the next load).
  sandbox = true,

  -- DROP POINT: on solid deck near where your Chinese squad lands, and well CLEAR of the transport's
  -- touchdown (the old spawn sat right under it, which shoved the player off the rig into the sea).
  -- (Adjust in MissionForge if you want a different exit; keep it clear of the transport at -448,2612.)
  start = { x=-470, y=9.86, z=2675, yaw=177 },

  relations = {
    { "China",  "PMC",    "friend" },
    { "China",  "Allied", "enemy"  },
    { "PMC",    "Allied", "enemy"  },
  },

  -- open on black so the character is never seen on the rig before the camera hijack
  cinematic = { steps = INTRO, opts = { startFade = true, skippable = true } },

  -- the playable roster (spawns after the cutscene). Faction-regrouped from the export's flat "A":
  --   ALLIED = the CORE rig defenders (defend the core); CHINA = your ground squad. (Boats + the pad/AA
  --   guards are pre-spawned in the intro; rocket units are trimmed so the rig lives longer.)
  units = {
{UNITS}
  },

  objectives = {
    C.Interact{ desc = "Plant the charge on the refinery core", at = {-526.89,-2.10,2737.72}, radius = 6, time = 2 },
    C.Survive{  desc = "Hold the core while the charge arms",   time = 5 },
    -- exfil moved to the first trigger point south of the core (the original transport LZ gets destroyed).
    -- Boards the crewed transport (no transit UI) + flies a couple of victory-lap orbits before finalizing.
    C.Extract{  desc = "Fall back to the LZ and extract", at = {-522.10,-2.09,2697.43}, radius = 12,
                boardTime = 2, heli = "Mi26 (CH) (Driver)",
                victoryLap = { orbits = 2, radius = 110, height = 55, line = "Rig's ours. Let's take her home." } },
  },

  -- the CORE allied garrison digs in around the core; your Chinese squad pushes up once you advance.
  waypoints = {
    { id="allied_hold", group="ALLIED", behavior="defend", at={-524.02,9.90,2714.44}, radius=35.7 },
    { id="china_push",  group="CHINA",  behavior="move",   at={-524.02,9.90,2714.44}, trigger={ref="t_push"} },
  },

  -- FX gated behind the CHARGE ARMING (objective 2 complete), NOT raw proximity -- so the rig only starts
  -- coming apart once you've planted+held and are falling back to the LZ.
  support = {
    { id="say_start",   effect="say", text="Push to the rig -- clear those defenders!",              hold=6, trigger={ref="t_start"} },
    { id="say_extract", effect="say", text="Charge is set -- the whole rig's coming down. Get to the LZ!", hold=7, trigger={ref="charge_armed"} },
    -- the collapse cascade: RIPPLED via per-support delay (not all on one frame) -- reads as a rolling
    -- destruction and avoids the simultaneous-spawn spike that can CTD the physics engine.
    { id="arty_chaos",  effect="artillery", at={-501.62,-2,2680.34}, radius=16, count=8, owner="China", delay=0.5, trigger={ref="charge_armed"} },
    { id="shake1",      effect="shake", preset="ShakeCameraLarge", amplitude=8, duration=6, trigger={ref="charge_armed"} },
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

-- Fade to black BEFORE accepting so the teleport-to-rig frame is hidden too (the cutscene then opens black).
pcall(Ess.Camera.fade, 1)
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
    # Ripple the blasts out over ~3.5s (delay grows per blast) so the rig comes apart in a rolling wave
    # rather than one catastrophic frame -- the fix for the simultaneous-cascade CTD.
    out, i = [], 0
    for (x, y, z) in VFX_ALL:
        i += 1
        d = round(0.8 + 0.3 * i, 2)   # 1.1s .. 3.8s
        out.append('    {{ id="vfx{i}", effect="vfx", at={{{x},{y},{z}}}, count=2, radius=4, delay={d}, trigger={{ref="charge_armed"}} }},'.format(i=i, x=x, y=y, z=z, d=d))
    j = 0
    for (x, y, z) in FLYBY_ALL:
        j += 1
        d = round(2.0 + 0.6 * j, 2)   # flybys come in over the tail of the cascade
        out.append('    {{ id="flyby{j}", effect="flyby", at={{{x},{y},{z}}}, delay={d}, trigger={{ref="charge_armed"}} }},'.format(j=j, x=x, y=y, z=z, d=d))
    return "\n".join(out)

def main():
    with open(EXPORT, "r", encoding="utf-8") as f:
        text = f.read()
    prespawn, defunits, counts = gen_rosters(text)
    body = (HEADER.replace("{PRESPAWN}", prespawn)
            + FOOTER_TMPL.replace("{UNITS}", defunits).replace("{VFX}", gen_vfx()))
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(body)
    print("wrote {}".format(os.path.relpath(OUT, REPO)))
    print("  def.units={defunit}  pre-spawned={prespawn}  rockets dropped={drop}  cinematic-owned={skip}".format(**counts))

if __name__ == "__main__":
    main()
