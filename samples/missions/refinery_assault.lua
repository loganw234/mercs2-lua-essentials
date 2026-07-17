-- refinery_assault.lua -- WORKED EXAMPLE MISSION: offshore oil-refinery assault (China vs Allies, you back
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
    { spawn="MarkV (Full)", x=-644.02, y=-37.73, z=2440.14, yaw=-70.486, group="ALLIED_NAVY" },
    { spawn="MarkV (Full)", x=-627.21, y=-35.56, z=2439.61, yaw=-71.053, group="ALLIED_NAVY" },
    { spawn="MarkV (Full)", x=-556.41, y=-38.24, z=2675.86, yaw=73.256, group="ALLIED_NAVY" },
    { spawn="Omen (Full)", x=-476.67, y=-36.39, z=2572.67, yaw=121.756, group="ALLIED_NAVY" },
    { spawn="Omen (Full)", x=-418.53, y=-36.38, z=2449.98, yaw=167.111, group="ALLIED_NAVY" },
    { spawn="Omen (Full)", x=-514.98, y=-36.37, z=2397.84, yaw=-113.093, group="ALLIED_NAVY" },
    { spawn="Omen (Full)", x=-556.13, y=-36.32, z=2438.36, yaw=-58.841, group="ALLIED_NAVY" },
    { spawn="Allied Soldier", x=-509.54, y=-2.16, z=2601.99, yaw=-179.037, group="ALLIED" },
    { spawn="Allied Soldier", x=-514.72, y=-2.16, z=2601.92, yaw=-179.037, group="ALLIED" },
    { spawn="Allied Heavy (Light MG)", x=-509.45, y=-2.16, z=2596.99, yaw=-179.037, group="ALLIED" },
    { spawn="Allied Heavy (AT Rocket)", x=-514.45, y=-2.16, z=2596.90, yaw=-179.037, group="ALLIED" },
    { spawn="Allied Soldier", x=-515.59, y=-2.09, z=2628.41, yaw=-38.979, group="ALLIED" },
    { spawn="Allied Soldier", x=-511.70, y=-2.09, z=2625.26, yaw=-38.979, group="ALLIED" },
    { spawn="Allied Heavy (Light MG)", x=-512.39, y=-2.15, z=2632.33, yaw=-38.979, group="ALLIED" },
    { spawn="Allied Heavy (AT Rocket)", x=-508.56, y=-2.09, z=2629.15, yaw=-38.979, group="ALLIED" },
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
    { spawn="Allied Heavy (AT Rocket)", x=-520.20, y=-2.15, z=2669.49, yaw=-71.365, group="ALLIED" },
    { spawn="Allied Heavy (AT Rocket)", x=-518.60, y=-2.15, z=2664.75, yaw=-71.365, group="ALLIED" },
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
    { spawn="Allied Heavy (AT Rocket)", x=-522.12, y=-2.15, z=2727.98, yaw=21.840, group="ALLIED" },
    { spawn="Allied Heavy (AT Rocket)", x=-542.55, y=-2.15, z=2725.18, yaw=21.840, group="ALLIED" },
    { spawn="Allied Heavy (AT Rocket)", x=-537.91, y=-2.15, z=2727.04, yaw=21.840, group="ALLIED" },
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
    { spawn="Chinese Heavy (RPG)", x=-474.60, y=9.86, z=2673.62, yaw=177.278, group="CHINA" },
    { spawn="Chinese Heavy (RPG)", x=-479.60, y=9.86, z=2673.84, yaw=177.278, group="CHINA" },
    { spawn="Chinese Elite Soldier", x=-484.80, y=9.86, z=2674.02, yaw=177.278, group="CHINA" },
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
    { id="vfx1", effect="vfx", at={-538.93,-2.09,2644.25}, count=2, radius=4, trigger={ref="charge_armed"} },
    { id="vfx2", effect="vfx", at={-548.96,-2.09,2663.8}, count=2, radius=4, trigger={ref="charge_armed"} },
    { id="vfx3", effect="vfx", at={-547.31,-2.09,2675.1}, count=2, radius=4, trigger={ref="charge_armed"} },
    { id="vfx4", effect="vfx", at={-531.76,-2.09,2644.83}, count=2, radius=4, trigger={ref="charge_armed"} },
    { id="vfx5", effect="vfx", at={-500.5,-2.09,2667.69}, count=2, radius=4, trigger={ref="charge_armed"} },
    { id="vfx6", effect="vfx", at={-500.51,-2.09,2685.71}, count=2, radius=4, trigger={ref="charge_armed"} },
    { id="vfx7", effect="vfx", at={-500.49,-2.09,2700.31}, count=2, radius=4, trigger={ref="charge_armed"} },
    { id="vfx8", effect="vfx", at={-496.2,-2.1,2650.92}, count=2, radius=4, trigger={ref="charge_armed"} },
    { id="vfx9", effect="vfx", at={-495.67,-2.08,2635.32}, count=2, radius=4, trigger={ref="charge_armed"} },
    { id="vfx10", effect="vfx", at={-527.84,-2.08,2631.47}, count=2, radius=4, trigger={ref="charge_armed"} },
    { id="flyby1", effect="flyby", at={-523.23,-0.74,2603.85}, trigger={ref="charge_armed"} },
    { id="flyby2", effect="flyby", at={-511.33,0.13,2610.35}, trigger={ref="charge_armed"} },
    { id="flyby3", effect="flyby", at={-500.01,-0.73,2601.75}, trigger={ref="charge_armed"} },
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
