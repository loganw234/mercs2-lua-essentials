-- refinery_assault.lua -- WORKED EXAMPLE MISSION: offshore oil-refinery assault (China vs Allies, you back
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
  -- set dressing spawned immediately, so it's already there during the cutscene: allied ships in the water
  -- + the guards around the AA guns (generated from the export)
  { type="spawn", template="MarkV (Full)", at={x=-644.02,y=-37.73,z=2440.14}, yaw=-70.486, hold=0 },
  { type="spawn", template="MarkV (Full)", at={x=-627.21,y=-35.56,z=2439.61}, yaw=-71.053, hold=0 },
  { type="spawn", template="MarkV (Full)", at={x=-556.41,y=-38.24,z=2675.86}, yaw=73.256, hold=0 },
  { type="spawn", template="Omen (Full)", at={x=-476.67,y=-36.39,z=2572.67}, yaw=121.756, hold=0 },
  { type="spawn", template="Omen (Full)", at={x=-418.53,y=-36.38,z=2449.98}, yaw=167.111, hold=0 },
  { type="spawn", template="Omen (Full)", at={x=-514.98,y=-36.37,z=2397.84}, yaw=-113.093, hold=0 },
  { type="spawn", template="Omen (Full)", at={x=-556.13,y=-36.32,z=2438.36}, yaw=-58.841, hold=0 },
  { type="spawn", template="Allied Soldier", at={x=-509.54,y=-2.16,z=2601.99}, yaw=-179.037, hold=0 },
  { type="spawn", template="Allied Soldier", at={x=-514.72,y=-2.16,z=2601.92}, yaw=-179.037, hold=0 },
  { type="spawn", template="Allied Heavy (Light MG)", at={x=-509.45,y=-2.16,z=2596.99}, yaw=-179.037, hold=0 },
  { type="spawn", template="Allied Soldier", at={x=-515.59,y=-2.09,z=2628.41}, yaw=-38.979, hold=0 },
  { type="spawn", template="Allied Soldier", at={x=-511.70,y=-2.09,z=2625.26}, yaw=-38.979, hold=0 },
  { type="spawn", template="Allied Heavy (Light MG)", at={x=-512.39,y=-2.15,z=2632.33}, yaw=-38.979, hold=0 },

  -- the air wave (Chinese, hostile). A FEW persist past the cutscene (Logan: leave some helis in the fight);
  -- wz2 is the guaranteed downing and ka2 is ephemeral, the rest stay.
  { type="spawn", template="WZ10 (Full)",  at={x=-382.23,y=28.36,z=2237.92}, yaw=-11.342, name="wz_lead", group="airwave", hold=0 },
  { type="spawn", template="WZ10 (Full)",  at={x=-415.39,y=28.59,z=2255.97}, yaw=-9.501,  name="wz2",     group="airwave", ephemeral=true, hold=0 },
  { type="spawn", template="WZ10 (Full)",  at={x=-449.86,y=28.94,z=2251.63}, yaw=-7.098,  name="wz3",     group="airwave", hold=0 },
  { type="spawn", template="Ka29b (Full)", at={x=-438.53,y=31.23,z=2101.45}, yaw=-8.939,  name="ka1",     group="airwave", hold=0 },
  { type="spawn", template="Ka29b (Full)", at={x=-319.83,y=30.84,z=2130.35}, yaw=-18.026, name="ka2",     group="airwave", ephemeral=true, hold=0 },
  -- the allied pad-AA "SAM site": fires on the wave (relations already hostile), then the strike wipes it
  { type="spawn", template="HMMWV (Avenger) (Full)", at={x=-523.16,y=-2.18,z=2604.95}, yaw=-172.356, name="aa1", group="padAA", ephemeral=true, hold=0 },
  { type="spawn", template="HMMWV (Avenger) (Full)", at={x=-500.07,y=-2.18,z=2602.85}, yaw=177.321,  name="aa2", group="padAA", ephemeral=true, hold=0 },
  { type="spawn", template="LAVIII (AD) (Full)",     at={x=-511.17,y=-2.18,z=2612.02}, yaw=-179.649, name="aa3", group="padAA", ephemeral=true, hold=0 },

  -- send the wave in, fanned across the approach
  { type="fly", target="wz_lead", at={x=-497,y=32,z=2662}, hold=0 },
  { type="fly", target="wz2",     at={x=-470,y=34,z=2650}, hold=0 },
  { type="fly", target="wz3",     at={x=-525,y=30,z=2648}, hold=0 },
  { type="fly", target="ka1",     at={x=-505,y=36,z=2690}, hold=0 },
  { type="fly", target="ka2",     at={x=-455,y=38,z=2700}, hold=0 },

  -- REVEAL from black, alongside the AA guns, watching the wave come in off the sea. STATIC camera (no
  -- chase = no jitter) -- the helis fly across the frame.
  { type="camera", at={x=-540,y=12,z=2600}, lookAt={x=-470,y=28,z=2350}, hold=0 },
  { type="fade", to=0, hold=0 },
  { type="music", cue="mu_pmc_panicloop_01", hold=0 },
  { type="subtitle", text="The Allies have too much oil. We'd like you to relieve them of it.", hold=5 },

  -- pan: a smooth dolly back + up so BOTH the incoming helis AND the AA guns are in frame at once
  { type="camera", at={x=-540,y=12,z=2600}, to={x=-577,y=33,z=2540}, lookAt={x=-505,y=10,z=2625}, hold=6 },
  { type="subtitle", text="They're on the triple-A now.", hold=0 },

  -- a heli goes down (guaranteed, on top of any live AA fire)
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

  -- friendly transport touches down where you'll start
  { type="spawn", template="Mi26 (CH) (Driver)", at={x=-455.63,y=48,z=2635.81}, yaw=-141.769, name="transport", hold=0 },
  { type="fly", target="transport", at={x=-455.63,y=11,z=2635.81}, height=11, hold=0 },
  { type="camera", at={x=-431.80,y=20,z=2600}, look="transport", hold=4.5 },
  { type="subtitle", text="Transport's down. Move out, merc.", hold=0 },

  { type="fade", to=1, hold=1.5 },
}


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

  start = { x=-461.91, y=9.91, z=2636.13, yaw=-92.768 },

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
    { spawn="Allied Officer", x=-534.43, y=-2.15, z=2664.70, yaw=-71.365, group="ALLIED" },
    { spawn="Allied Soldier", x=-532.81, y=-2.15, z=2659.95, yaw=-71.365, group="ALLIED" },
    { spawn="Allied Soldier", x=-531.21, y=-2.15, z=2655.22, yaw=-71.365, group="ALLIED" },
    { spawn="Allied Soldier", x=-529.61, y=-2.15, z=2650.48, yaw=-71.365, group="ALLIED" },
    { spawn="Allied Soldier", x=-529.67, y=-2.15, z=2666.29, yaw=-71.365, group="ALLIED" },
    { spawn="Allied Soldier", x=-528.03, y=-2.15, z=2661.67, yaw=-71.365, group="ALLIED" },
    { spawn="Allied Soldier", x=-526.48, y=-2.15, z=2656.82, yaw=-71.365, group="ALLIED" },
    { spawn="Allied Soldier", x=-524.88, y=-2.15, z=2652.08, yaw=-71.365, group="ALLIED" },
    { spawn="Allied Soldier", x=-524.94, y=-2.15, z=2667.89, yaw=-71.365, group="ALLIED" },
    { spawn="Allied Heavy (Light MG)", x=-523.34, y=-2.15, z=2663.15, yaw=-71.365, group="ALLIED" },
    { spawn="Allied Heavy (Light MG)", x=-521.74, y=-2.15, z=2658.42, yaw=-71.365, group="ALLIED" },
    { spawn="Allied Heavy (Light MG)", x=-520.14, y=-2.15, z=2653.68, yaw=-71.365, group="ALLIED" },
    { spawn="Allied Heavy (AA)", x=-517.00, y=-2.15, z=2660.01, yaw=-71.365, group="ALLIED" },
    { spawn="Allied Heavy (AA)", x=-515.40, y=-2.15, z=2655.28, yaw=-71.365, group="ALLIED" },
    { spawn="Allied Boss", x=-535.11, y=-2.15, z=2706.61, yaw=21.840, group="ALLIED" },
    { spawn="Allied Officer", x=-530.47, y=-2.15, z=2708.48, yaw=21.840, group="ALLIED" },
    { spawn="Allied Officer", x=-525.87, y=-2.15, z=2710.01, yaw=21.840, group="ALLIED" },
    { spawn="Allied Soldier", x=-521.19, y=-2.15, z=2712.20, yaw=21.840, group="ALLIED" },
    { spawn="Allied Soldier", x=-516.55, y=-2.15, z=2714.06, yaw=21.840, group="ALLIED" },
    { spawn="Allied Soldier", x=-536.97, y=-2.15, z=2711.26, yaw=21.840, group="ALLIED" },
    { spawn="Allied Soldier", x=-532.33, y=-2.15, z=2713.11, yaw=21.840, group="ALLIED" },
    { spawn="Allied Soldier", x=-527.69, y=-2.15, z=2714.98, yaw=21.840, group="ALLIED" },
    { spawn="Allied Soldier", x=-523.05, y=-2.15, z=2716.84, yaw=21.840, group="ALLIED" },
    { spawn="Allied Soldier", x=-518.41, y=-2.15, z=2718.70, yaw=21.840, group="ALLIED" },
    { spawn="Allied Soldier", x=-538.83, y=-2.15, z=2715.90, yaw=21.840, group="ALLIED" },
    { spawn="Allied Soldier", x=-534.19, y=-2.15, z=2717.76, yaw=21.840, group="ALLIED" },
    { spawn="Allied Soldier", x=-529.55, y=-2.15, z=2719.62, yaw=21.840, group="ALLIED" },
    { spawn="Allied Soldier", x=-524.91, y=-2.15, z=2721.48, yaw=21.840, group="ALLIED" },
    { spawn="Allied Soldier", x=-520.26, y=-2.15, z=2723.34, yaw=21.840, group="ALLIED" },
    { spawn="Allied Heavy (Light MG)", x=-540.69, y=-2.15, z=2720.54, yaw=21.840, group="ALLIED" },
    { spawn="Allied Heavy (Light MG)", x=-536.05, y=-2.15, z=2722.40, yaw=21.840, group="ALLIED" },
    { spawn="Allied Heavy (Light MG)", x=-531.40, y=-2.15, z=2724.25, yaw=21.840, group="ALLIED" },
    { spawn="Allied Heavy (Light MG)", x=-526.77, y=-2.15, z=2726.12, yaw=21.840, group="ALLIED" },
    { spawn="Allied Airborne", x=-533.27, y=-2.15, z=2728.90, yaw=21.840, group="ALLIED" },
    { spawn="Allied Airborne", x=-528.62, y=-2.15, z=2730.76, yaw=21.840, group="ALLIED" },
    { spawn="Chinese Sniper", x=-490.90, y=13.85, z=2711.66, yaw=-88.947, group="CHINA" },
    { spawn="Chinese Sniper", x=-492.40, y=13.85, z=2703.69, yaw=-89.559, group="CHINA" },
    { spawn="Chinese Sniper", x=-490.89, y=13.85, z=2725.49, yaw=-45.219, group="CHINA" },
    { spawn="Chinese Officer", x=-470.37, y=9.86, z=2683.74, yaw=177.278, group="CHINA" },
    { spawn="Chinese Soldier", x=-474.12, y=9.86, z=2683.61, yaw=177.278, group="CHINA" },
    { spawn="Chinese Soldier", x=-479.11, y=9.86, z=2683.84, yaw=177.278, group="CHINA" },
    { spawn="Chinese Soldier", x=-484.10, y=9.86, z=2684.08, yaw=177.278, group="CHINA" },
    { spawn="Chinese Soldier", x=-469.54, y=9.86, z=2678.42, yaw=177.278, group="CHINA" },
    { spawn="Chinese Soldier", x=-474.36, y=9.86, z=2678.61, yaw=177.278, group="CHINA" },
    { spawn="Chinese Soldier", x=-479.35, y=9.86, z=2678.84, yaw=177.278, group="CHINA" },
    { spawn="Chinese Heavy (Light MG)", x=-484.35, y=9.86, z=2679.09, yaw=177.278, group="CHINA" },
    { spawn="Chinese Heavy (Light MG)", x=-469.60, y=9.86, z=2673.36, yaw=177.278, group="CHINA" },
    { spawn="Chinese Elite Soldier", x=-484.80, y=9.86, z=2674.02, yaw=177.278, group="CHINA" },
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
    { id="vfx1", effect="vfx", at={-538.93,-2.09,2644.25}, count=2, radius=4, delay=1.1, trigger={ref="charge_armed"} },
    { id="vfx2", effect="vfx", at={-548.96,-2.09,2663.8}, count=2, radius=4, delay=1.4, trigger={ref="charge_armed"} },
    { id="vfx3", effect="vfx", at={-547.31,-2.09,2675.1}, count=2, radius=4, delay=1.7, trigger={ref="charge_armed"} },
    { id="vfx4", effect="vfx", at={-531.76,-2.09,2644.83}, count=2, radius=4, delay=2.0, trigger={ref="charge_armed"} },
    { id="vfx5", effect="vfx", at={-500.5,-2.09,2667.69}, count=2, radius=4, delay=2.3, trigger={ref="charge_armed"} },
    { id="vfx6", effect="vfx", at={-500.51,-2.09,2685.71}, count=2, radius=4, delay=2.6, trigger={ref="charge_armed"} },
    { id="vfx7", effect="vfx", at={-500.49,-2.09,2700.31}, count=2, radius=4, delay=2.9, trigger={ref="charge_armed"} },
    { id="vfx8", effect="vfx", at={-496.2,-2.1,2650.92}, count=2, radius=4, delay=3.2, trigger={ref="charge_armed"} },
    { id="vfx9", effect="vfx", at={-495.67,-2.08,2635.32}, count=2, radius=4, delay=3.5, trigger={ref="charge_armed"} },
    { id="vfx10", effect="vfx", at={-527.84,-2.08,2631.47}, count=2, radius=4, delay=3.8, trigger={ref="charge_armed"} },
    { id="flyby1", effect="flyby", at={-523.23,-0.74,2603.85}, delay=2.6, trigger={ref="charge_armed"} },
    { id="flyby2", effect="flyby", at={-511.33,0.13,2610.35}, delay=3.2, trigger={ref="charge_armed"} },
    { id="flyby3", effect="flyby", at={-500.01,-0.73,2601.75}, delay=3.8, trigger={ref="charge_armed"} },
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
