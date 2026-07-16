# EXAMPLE-MISSION BRIEFING — hardened compaction note (written 2026-07-17)

You (Claude) are mid-project on the **Ess ("Essentials") Lua framework for Mercenaries 2**. This note is the
authoritative resume anchor if the conversation was compacted. Read it fully, then continue. It is
self-contained on purpose.

---

## 1. THE TASK WE'RE STARTING

Build a **theoretical example mission from a new-ish user's perspective**, to fold the whole framework
together and surface FRICTION POINTS. Logan's framing: "A new-ish user wants to create a nicely designed
mission, reusing some audio lines, making some little cinematics. Maybe something like **the Allies being
attacked by the CN (China) faction**."

Two parallel goals:
1. **Author the example mission** using `Ess.Contract` + the new Easy layer + the cinematic camera + audio
   lines + faction relations. Do it AS a beginner would (reach for `Ess.Easy.*` first) and NOTE every place
   the framework is awkward, missing a helper, or forces raw calls. Those friction points drive improvements.
2. **Update the MissionForge script to be more in line with Essentials** — refactor it to consume `Ess.*`
   helpers instead of its own hand-rolled code / raw natives. Do this alongside the mission work.

This is a CONSUMER test: the point is to find gaps by using the framework for real, then fix them.

The scenario factions are confirmed real: **`Allied`** and **`China`** (others: `PMC` = player, `VZ`,
`Guerilla`, `Pirate`, `OC`, `Civ`). Relations use these abbrev strings.

---

## 2. HOW TO WORK — the dev-loop (operationally load-bearing, do NOT re-derive)

Two repos matter:
- **Essentials repo:** `C:\Users\logan\source\repos\mercs2-lua-essentials` — the framework. `src/NN_*.lua`
  files, `build/merge.py` concatenates them into `dist/Ess.lua` (gitignored), MANIFEST is an explicit
  ordered list in `build/merge.py`. Local git only, NO remote. Commit when things work.
- **Docs/corpus repo:** `C:\Users\logan\Desktop\Mercs2_Decompiled_Lua\docs\mercs2-luacd` — the wiki +
  the decompiled game source at `src/{resident,vz,shell}/*.lua` (~230 files, real call-site evidence) +
  `tools/loadcheck.py` (offline load-checker). **This is also your CWD.**

The game install: `C:\Games\Mercenaries 2 World in Flames`. Log:
`C:\Games\Mercenaries 2 World in Flames\scripts\lua_loader_printf.log`.

**The cycle (each edit):**
1. Edit `src/*.lua` in the essentials repo. If you add a NEW file, add it to `build/merge.py`'s MANIFEST in
   dependency order.
2. `cd <essentials> && python build/merge.py`  → rebuilds `dist/Ess.lua`, prints file count + orphan check.
3. `python tools/loadcheck.py "<essentials>\dist\Ess.lua"` — **run this from the DOCS repo** (that's where
   loadcheck.py lives). Offline lupa check; "chunk loaded to completion OK" = good. It STUBS `import`, so it
   won't catch a wrong resident-module import name — only a live run does.
4. **Hot-reload into the running game** (fast, no relaunch): `python "<essentials>\tools\lua_repl.py" --file
   "<essentials>\dist\Ess.lua"`. Ess init is idempotent (guards against double-wrap). ⚠ Hot-reload is
   ADDITIVE — it does NOT remove functions you deleted from source (they linger in the live `Ess` table
   until a fresh launch). A `type(Ess.X.removed)=="function"` after removal is a reload artifact, not a bug.
5. Live-test: `python "<essentials>\tools\lua_repl.py" --code '<lua>'`.

**⚠ THE BRIDGE SOCKET READ IS FLAKY** (one-execution-behind + batches; `--code` frequently TIMES OUT even
though the chunk RAN). Reliable pattern: have the chunk `Loader.Printf("[TAG] ...")` its result, then read
the log with `grep -h "\[TAG\]" "<game>\scripts\lua_loader_printf.log" | tail`. Treat the log as
authoritative; treat a `[lua_repl] TIMEOUT` as "probably ran, go check the log," not failure.

**Relaunch (only if the game crashed / you need deleted functions gone):**
`cd <essentials> && python tools/launch.py --all --wait-ess`. `--wait-ess` FALSE-NEGATIVES often (warns even
when Ess loaded) — verify directly with `--code 'return tostring(_G.Ess ~= nil)'`, retry after ~8s if it
returns false/`nil` (a boot race, not a failure). To stop the game: PowerShell `Get-Process Mercenaries2
-ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep -Seconds 2` (use the PowerShell tool, NOT
Bash — Bash mangles `$_`).

---

## 3. FRAMEWORK STATE (HEAD = commit `3a79456`, 58 src files, dist ~377KB)

Every namespace is built + live-tested. **`CAPABILITIES.md`** in the essentials repo is the current
capability catalog — READ IT for the full surface. `FEATURE_SHEET.md` is the long append-only build history.
Namespaces you'll lean on for the mission:

- **`Ess.Contract`** (`src/80-83_contract*.lua`) — THE ephemeral-mission engine (native port of the old
  ContractFramework). `Ess.Contract.Register{def}` / `.Accept(id)` / `.Abort()` / `.Status()`. **16 objective
  handlers** (destroy/reach/hold/survive/defend/collect/escort/enter/protect/stay/group/interact/verify/
  extract/race/chase). Triggers (proximity/once/recurring/onDestroy/health/objective/cleared + all/count
  gates). SUPPORT_EFFECTS (say/vfx/music/damage/artillery/reinforce/flyby/bombingrun/heli/vo/shake/hint).
  `def.relations` / `def.units` (grouped spawns) / `def.waypoints` (AI orders) / `def.support` /
  `def.triggers` / `def.start` (teleport heroes via MrxUtil.TeleportHeroesToLocations) / `def.onBegin`.
  `Ess.Easy.Contract.destroy(title, spawns, opts)` / `.reach(title, at, radius, opts)` = one-call contracts.
  **Objective-complete trigger is `def.triggers={{id=,kind="objective",index=N}}` referenced via
  `trigger={ref=id}` — NOT an inline `{onObjComplete=N}` (that was a doc bug, fixed).**
- **`Ess.Relations`** — faction stance. `Ess.Easy.Relations.makeHostile({factions})` / `.makeAllies(...)` /
  `.restore()`. Core: `Ess.Relations.apply(id, {{a,b,"hostile"|"ally"|n}})` / `.restore(id)`,
  `.getFeeling/.setFeeling` (per-individual). For "Allies attacked by China": makeHostile between China and
  Allied, etc.
- **`Ess.AIOrders`** — command spawned groups: `Ess.Easy.AIOrders.attack/patrol/guard`, Core
  `.command(guids, behavior, opts)` (move/patrol/defend/attack/hold/face/follow/flee/enter/deploy/animate).
- **`Ess.Easy.Camera`** — cinematics (see §4). **`Ess.Vehicle.flyTo`** — AI heli to a point.
- **`Ess.Sound`** (`src/56_sound.lua`) — `cue/stop/ambience/volume` + `Ess.Easy.Sound.play`. For AUDIO LINES,
  Contract's `vo` support effect wraps `MrxVoSequence`; `say` uses `Hud.ObjectiveTray`. **You'll need to
  find confirmed VO/audio-line identifiers in the corpus** (grep `src/vz` for `MrxVoSequence`/`Say`/`vo` /
  audio bank names) — reusing audio lines means finding real line names.
- **`Ess.Hud`** — `.hint(msg)` (tutorial popup), `.banner(msg)` (centered text). Narration.
- **`Ess.Mark` / `Ess.Easy.Mark`** — objective/enemy/zone markers.
- **`Ess.Easy.Spawn`** — explosion/crate/weapon/airstrike/**fx(t,x,y,z)**/**fxOn(t,guid,bone)**.
- **`Ess.Object`** — spawn/spawnAhead/pos/setPos/health/damage/kill/heal/alive/impulse/hasLabel/etc.
- **`Ess.Easy.World`** — removeMapBoundary/clearWanted/hellscape/tint/brightness (atmosphere is REGION-GATED,
  see §4), + persistent keeper.
- **`Ess.Easy.Player`** — teleport/giveGrapplingHook/unlockFastTravel/unlockAllHQs/giveAllRewards/
  freeSupport/**skin(code)**. **`Ess.Easy.Fun`** — dance/fanfare.
- **`Ess.Easy.Console.open()`** — an in-game searchable browser of the whole Easy surface (built on
  `src/96_console.lua`'s REGISTRY; add new Easy verbs to that registry as you build them).

Three-tier model: `Ess.Raw.*` (primitives) → `Ess.*` (Core, named params) → `Ess.Easy.*` (intent presets).
Add new capability at the right tier; register Easy verbs in `96_console.lua`.

---

## 4. HARD-WON FACTS FROM THIS SESSION (don't re-derive; several are in memory too)

**Cinematic camera** (`src/51_camera.lua`; memory [[mercs2-cinematic-camera-and-heli-nav]]):
- `Ess.Easy.Camera.watch(target, opts)` — DEFAULT = locked-off tracking shot (camera placed ONCE at a
  vantage + native `SetLookAt` pan; smooth for ANY target). `{chase=true, angle=N}` = a moving follow at a
  FIXED user-set world-bearing angle. `Ess.Easy.Camera.orbit(target, {radius,height,speed,startAngle})`.
- **THE smoothness rule: a MOVING camera must `Camera.Blend(c, 0)` (instant).** With the default 1s blend,
  per-tick `Camera.SetPosition` rubber-bands = jitter. Object-attach camera forms are a DEAD END (never
  bind). Track a moving VEHICLE via its PILOT's character bone (`SetLookAt(c, pilot, "Bone_Chest")`) — vehicle
  hardpoints don't bind. High-velocity targets jitter inherently (per-tick position reads) → use static watch.
- Cinematic STEALS mouse control until `stop()` / `Ess.Camera.endCinematic()` / `Ess.Camera.panicRevert()`.
  Always give a way back — build auto-release (an Ess.Loop that ends after N seconds) into demos.
- Heli nav: `Ess.Vehicle.flyTo(heli, x,y,z, {onReady=fn})` polls for the driver then `Ai.Deliver` (NOT
  `Ai.Goal "MoveToPos"` — that does not fly a heli). `"AH1Z (Full)"` / `(Full)`-tagged templates spawn
  CREWED and flying; a bare template has no pilot and falls & explodes. `(PMC)` etc. are only skin variants.

**Atmosphere/weather is REGION-GATED** (memory [[mercs2-atmosphere-region-gating]]): the live interface is
`Graphics.Atmosphere.Begin(); SetValue("fLightIntensity",n) / SetColorValue("uiAmbientColor",r,g,b,255);
End(dur)`. Works ONLY when standing in a named `rgn_atmo_*` region (Maracaibo/Caracas/...); NO-OP on the HQ
runway / base default. Global `SetTime/SetSky/SetTimeSpeed` are INERT live. `Ess.Easy.World.hellscape/tint/
brightness` are persistent (keeper re-applies on zone change). `GetCurrentSetting()` reads the active
atmosphere hash location-independently.

**Spawn/settle:** a freshly `Pg.Spawn`'d model's hardpoints/bones read `0,0,0` / nil for ~0.3s — poll
`Object.GetHardpointPosition` for a non-origin value before attaching cameras/FX to a bone. A **skin swap**
(`Player.SetOutfit`) also re-inits the model → same settle before bone ops. Blank/whitespace `Pg.Spawn`
template hard-CTDs even through pcall — all Ess spawn paths guard it; never bypass.

**Ai.Feeling / relations settle:** a freshly spawned character's `Ai.GetFeeling` reads stale 0 for a tick —
let it settle ~1s before reading AI/relation state.

---

## 5. TESTING ENVIRONMENT

- Player max HP = **120**; fall damage caps ~97 (never fatal alone). Heal with `Ess.Object.heal(char)`.
- **`"blanco"`** = confirmed spawnable test character (`"PMC"` is NOT). Vehicles: `"UH1 Transport"`,
  `"AH1Z (Full)"` (crewed), `"Veyron"`, etc.
- Safe flat spot (out of the HQ interior): **(2739.7, -14, -786)** via `Ess.Player.teleport(2739.7,-14,-786)`
  (memory [[ess-open-world-testing-spot]]). BUT atmosphere/region features need a real map region (Maracaibo
  etc.) — the runway spot is region-less. Teleporting OUT of the HQ unloads the interior into the open world.
- Spawn+enter-vehicle from INSIDE the PMC HQ interior cell risks a 30s+ bridge stall — do that kind of test
  out in the world.

---

## 6. MISSIONFORGE (the parallel refactor task)

Not yet located this session. It's Logan's drop-at-feet contract-authoring tool (F7), with a web editor at
`docs/mercs2-luacd/tools/missionforge/index.html` and an in-game OnKey script. **At task start: read memory
[[active-world-forge-project]]** for the full description (units/objectives/spawn/support/triggers/AI-orders,
`MISSIONFORGE_EXPORT`, the `Contract.Register{}` generator). Then LOCATE the in-game script — likely under
`C:\Users\logan\source\repos\mercs2-lua-mods\mods\` or the game's `scripts/OnKey|Misc/` (only `ForgeCam.lua`/
`ForgeMenu.lua` are in `scripts/Misc/`; MissionForge may be elsewhere — grep for `MISSIONFORGE`/`MissionForge`
across `mercs2-lua-mods` and the game scripts). The refactor goal: make it consume `Ess.*` (spawn via
`Ess.Object.spawn`, orders via `Ess.AIOrders`, marks via `Ess.Mark`, the camera via `Ess.Easy.Camera`, etc.)
instead of raw natives / its own copies. It emits `Contract.Register{}` today — that should target
`Ess.Contract.Register{}`.

---

## 7. CONVENTIONS & LOGAN'S PREFERENCES (from memory; violating these is a real error)

- **Before writing ANY Mercs2 Lua, read `docs/mercs2-luacd/wiki/ai-primer.md`.** Canonical rules there.
- `Loader.Printf` for debug output, NOT `Debug.Printf`. `pcall` fallible native calls. `import()` is
  FILE-SCOPED (each src file must import every `Mrx*` resident module IT uses — a recurring bug class). Lua
  5.1 only (has global `unpack`, no `goto`). Engine numbers are 32-bit float (use `Ess.RNG`, not a big LCG).
- **CONFIRMED-ONLY discipline:** do not wrap native functions whose argument shapes aren't backed by a real
  call site. Don't guess. This is core to the project's trust.
- Prefer BROAD core-foundation work over niche deep-dives; the three-tier model is the yardstick
  (memory [[ess-development-priorities-feedback]]).
- **`Ess.Probe.nearby` excludes the player by default** — it once caused an accidental player-kill; keep that
  (memory [[ess-probe-nearby-self-inclusion-footgun]]).
- Commit when things WORK, concise message, end body with `Co-Authored-By: Claude Sonnet 5
  <noreply@anthropic.com>`. Update `CAPABILITIES.md` + `96_console.lua` registry when adding Easy verbs.
- **WaveDefense.lua is NOT to be touched** in this work (it's a separate gamemode, a later consume-Ess
  refactor). The mission we build is a fresh example, not WaveDefense.

## 8. MEMORY POINTERS (read these if relevant)
`MEMORY.md` is the index. Especially: [[ess-essentials-framework-project]] (the master history),
[[mercs2-cinematic-camera-and-heli-nav]], [[mercs2-atmosphere-region-gating]], [[ess-open-world-testing-spot]],
[[active-world-forge-project]] (MissionForge + the contract system), [[custom-contract-framework]] (contract
def vocabulary), [[read-ai-primer-before-lua]].

## IMMEDIATE NEXT STEP after reading this
Confirm with Logan the mission's shape (Allies-vs-China), then start authoring it as a beginner would using
`Ess.Easy.*` first — logging friction points as you go — and in parallel locate + begin the MissionForge
refactor. Verify Ess is loaded (`--code 'return tostring(_G.Ess~=nil)'`) before live-testing; relaunch if not.
