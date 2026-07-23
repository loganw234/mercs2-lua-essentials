# Changelog

All notable changes to Ess are recorded here. Versions track `Ess.VERSION` in `src/00_core.lua`.

Releases are automatic: **bump `Ess.VERSION`, add a matching `## [x.y.z]` section below, and push to
`master`**. `.github/workflows/release.yml` then builds a fresh `1_Ess.lua`, syntax-checks it, packages the
zip, and publishes a GitHub Release tagged `v<version>` using that section as the notes. (No section for the
version? It still releases, with auto-generated commit notes.) See the README's "Releasing" section.

## [Unreleased]

## [0.3.1]

**The 2026-07-22 bindings-pass harvest.** A live-probe mapping of the engine's never-called `luaL_Reg`
bindings (wiki `namespaces/` pages, updated the same day) confirmed signatures for a batch of natives with
zero call sites anywhere in the decompiled corpus. Everything below wraps only live-confirmed or
corpus-confirmed calls, and everything is **additive** — no existing function changed signature or behavior.

### Added

- **`Ess.Pursuit`** (new namespace, `src/17_pursuit.lua`) — the wanted/heat system: `.state()/.level()`,
  `.start(faction, level)`, **`.clear()`** (the one true reset), `.seconds/.levelTimes/.lock/.custom`,
  `.capLevel(n)` (⚠ live-confirmed ONE-WAY session ratchet — logs a loud warning), `.restrictAll/
  .restrictFaction/.clearRestrictions` (gate ORGANIC heat only — they do NOT clear an active chase; the
  wrapper docs encode both confirmed traps). Plus **`Ess.Easy.World.noPursuit(bOn)`** — stop the current
  chase and keep new organic heat off, one call. (`Easy.World.clearWanted` is untouched.)
- **`Ess.Object` motion & geometry** — `.velocity(g)` / `.speed(g)` / `.speedSq(g)` (first motion API in
  Ess), `.size(g)` (model bbox extents — takes a guid, not a name), `.localToWorld(g, lx,ly,lz)` (the
  engine's full 3D transform incl. pitch/roll — prefer over yaw-only `Ess.Math.rotateOffset` on tilted
  objects), `.heightAboveGround(g)` (with the exact-0-placeholder caveat from the terrain project),
  `.snapToGround(g, offset)`, and `.invincible(g)` (the missing getter).
- **`Ess.Vehicle`** — `.repair(v)` (RestoreHealth+RestoreAmmo — the vehicle repair long thought missing),
  `.evictAll(v)` (Ai.EveryoneOut, confirmed), `.isFlipped(v)`, `.land(heliOrPilot)` (Ai.HeliLand, confirmed
  real descent; resolves the pilot via `.driver` — pairs with `.flyTo`).
- **`Ess.Probe`** — eight new `nearby()` kinds (`tanks`, `helicopters`, `boats`, `cars`, `jets`, `props`,
  `usables`, `groundNoTanks`) on the same dispatcher (unknown kinds still fall to `any`, unchanged), and
  `.allByName(name)` (every matching guid — `Ess.Guid` stays the single-match form).
- **`Ess.On.labeled(label, r, fn)`** — fires once per world-labeled object as it streams in near the
  player: the confirmed ObjectFilter + `Event.ObjectProximity` discovery idiom, promoted from the
  CollectibleFinder sample exactly as its header planned.
- **`Ess.Relations.getPerceivability/.setPerceivability`** — the per-individual AI detectability stat
  (confirmed reversible), and **`Ess.Easy.Player.ghost(bOn)`** — floor your detectability, restore your
  exact original on toggle-off. Registered in the Console + playground.
- **`Ess.Vec.cross`** — the cross product (dot's missing sibling), pure Lua.
- **`Ess.Easy.Debug.overlay`** now appends an engine `mem` figure (Sys.MemUsage) to the vehicle/health
  line — the useful signal is it climbing while your script runs.

### Verification status — live-tested in-game before release

Offline first (checkpure 10/10; test_bundles all green — which caught and fixed a real `Sys`-indexing guard
bug in the overlay's mem line; merged chunk loadchecks to completion), then a **full in-game pass on the
release build** (2026-07-22): the whole smoke suite — **42/42 recipes PASS**, including the new
`control_pursuit` (pursuit start → state-read → clear round-trip, and ghost lowering perceivability then
restoring the exact original). Targeted live probes, most with exact before/after numbers:

- `localToWorld` offset of 5 measured **5.00**; `heightAboveGround` read **12.05** on a +12 spawn and
  `snapToGround` took it to **0.00**; `invincible` round-tripped false→true→false; `isFlipped` false upright.
- `size` and `speed`/`velocity` return real values on settled objects (a human measured 0.98 × 1.93 × 0.33)
  — and surfaced a **new documented caveat**: both read nil/zeros in the same tick as the spawn (the known
  fresh-spawn settle class; noted in the file header).
- `Vehicle.repair`: health **25 → 130/130 max**. `Vehicle.evictAll`: driver went **userdata → nil**.
- `Vehicle.land`: a second **live-discovered caveat** — a heli on autonomous combat AI overrides the order;
  under scripted control (`.flyTo` then `.land`) it descended **AGL 35.0 → 19.4** and dropping. The
  flyTo-then-land pattern is now documented as the confirmed usage.
- `Probe.allByName` found a spawned template by name (template-name matching confirmed); all 8 new `nearby`
  kinds dispatch (cars=5 / props=17 / boats=0 / tanks=0 at the test spot); `Pursuit.restrict*` and
  `Easy.World.noPursuit` execute clean; the overlay's `mem` figure renders; `Vec.cross` returned (0,0,1).
- `On.labeled` armed and stopped cleanly (no labeled object inside radius at the test spot to fire on — the
  underlying filter+proximity idiom is already live-proven by the CollectibleFinder sample).

## [0.3.0]

**Headline: a mirrored forward vector is fixed.** Everything that placed or aimed something relative to a
yaw — `spawnAhead`, `Easy.Vehicle.summon`, the menu kit's `ctx:spawn`, `Object.faceToward`/`faceObject`,
MissionForge's squad grids — was mirrored about the forward axis. Live-verified twice (see **Fixed**). If you
wrote code that compensated for the old behaviour, remove the compensation.

The rest of this release closes "creativity gaps" for new modders — the framework was strong on *how* to do
things, thinner on *what you can do* and on reacting to the player. All additive.

**Verification status:** the yaw fix and the new view-relative placement are **live-verified in-game** (exact
numbers below). The additive batch was then **live-verified in-game as well**, feature by feature:

- **`Ess.On`** — 7 of its 8 hooks fired live: `death`, `enterArea`, `insideArea`, `healthBelow`, `tick`,
  `vehicle` (enter + exit), `playerHurt`. *(`exitArea` not exercised.)*
- **`Ess.Support`** — all 7 call-ins fired clean (`shell`, `artillery`, `airstrike`, `bombingrun`,
  `gunship`, `reinforce`, `Easy.Airstrike.at`), with `reinforce` separately confirmed actually delivering
  units.
- **`Ess.Keys`** (`vk`/`on`/`isBound`/`off`), **`Ess.Objective`** + `Easy.Objective.reach/.destroy/.clear/
  .survive`, **`Ess.Quest`** sequencing, **`Easy.Spawn.enemies`**, **`Safe.template`**,
  **`Hud.objective(text, slot)`** — all pass.
- The two pieces that most needed eyes: **`Easy.Debug.overlay()`** renders, and **`Easy.Console.play()`**'s
  drill-in / run-live / param-cycling works.

**Still unverified:** the six OnKey demos that ship in the zip — `VehicleInspector`, `WaveSurvival`,
`BossFight`, `EncounterDirector`, `CreatorToolkit`, `Playground`. They need deploying to `scripts/OnKey/`
plus `lua_loader.ini` bindings and a keypress each. Nothing in the batch changes existing behaviour.

### Fixed
- **The forward vector was mirrored on X.** The engine's forward is `(+sin(yaw), +cos(yaw))`; Ess used
  `(-sin, +cos)`, with `Ess.Math.angleTo` = `atan2(-dx, dz)`. Both were wrong together (they are exact
  inverses and must always change as a pair), so "in front of the player" came out mirrored about the
  forward axis, and `faceToward` aimed objects the wrong way.
  ```lua
  pointAhead:  x - sin(yr)*dist   ->   x + sin(yr)*dist
  angleTo:     atan2(-dx, dz)     ->   atan2(dx, dz)
  ```
  **Why it hid for so long:** it is a *mirror*, not a rotation. Facing **north/south** `sin ≈ 0` and both
  conventions land on the same point — **invisible**. Facing **east/west** it is a full **180° wrong**. In
  between it is a variable, heading-dependent skew that reads as random. Two earlier calibrations were
  defeated by exactly this. **Always calibrate facing east/west.**
  **Proof:** two ground rings placed from the same body yaw, one per convention — facing east the `(+sin)`
  ring was dead ahead and `(-sin)` directly behind; facing north they coincided. Then numerically: with the
  reticle aimed along the body, `angleTo(player → reticle)` now equals `Object.GetYaw` to **±0.3°** (it
  returned the *negative* before).
- **Three inline re-derivations** of that trig, which would have silently kept the old sign, now call
  `Ess.Math`: the menu kit's `ctx:spawn`, `CarStunt`'s side camera, and MissionForge's squad-grid rotation
  matrix (squads were flipping about the forward axis).

### Added
- **`Ess.Player.viewYaw(i) -> yaw, bFromReticle`** — the yaw you're **looking** along, as distinct from
  `Ess.Player.pose`'s 4th return, which is the **chest/body** yaw. These genuinely differ: stand still and
  swing the mouse and the view rotates while the body does not (measured live at up to **111°** apart;
  running forward re-aligns them). Derived from the reticle hit point. **Never nil** while you have a
  character — with no usable hit (aiming at open sky) it falls back to the body yaw and returns `false` as
  the second value, which is what makes the flags below safe without caller-side guarding.
- **Opt-in view-relative placement** — all default **off**, so every existing call is unchanged:
  ```lua
  Ess.Object.spawnAhead(tmpl, dist, height, i, { useView = true })   -- trailing arg
  Ess.Easy.Vehicle.summon(tmpl,                { useView = true })   -- existing opts table
  ctx:spawn(tmpl, dist,                        { useView = true })   -- menu kit
  ```
  Live-verified: with body yaw `-1.5` and view yaw `-47.2`, `spawnAhead{useView=true}` placed the vehicle at
  the computed view point exactly. (A param rather than parallel `LookAhead` functions: `pointAhead` already
  takes an explicit yaw, and full parity would have doubled the spatial surface with twins that are mostly
  meaningless — `faceToward` is never view-relative.)
- **`Ess.Math.rotateOffset(x, z, yaw, localX, localZ)`** — place a local `(right, forward)` offset into world
  space; the general case that `pointAhead` is the `localX = 0` special case of. Added because a hand-rolled
  rotation matrix is exactly how the mirrored sign propagated — use this instead of writing one.
- **`Ess.Support`** + **`Ess.Easy.Airstrike`** — the iconic combat call-ins (airstrike / artillery /
  gunship / bombing run / reinforcements) as standalone one-liners, lifted out of the Contract system so you
  can fire one anywhere. `Ess.Easy.Airstrike.at(x,y,z)` / `.onTarget()` for one-tap. Recipe: `call_in_support`.
- **`Ess.On`** — intent-named reactive hooks so mods respond to the world without wiring raw events:
  `death(guid)`, `enterArea` / `exitArea` / `insideArea`, `healthBelow`, `playerHurt`, `vehicle`, `tick`
  (each returns `stop()`). The area/health/hurt logic is execute-verified offline (stubbed loop). Honest
  about engine limits (no clean "player got a kill" event). Recipe: `react_to_things`.
- **`Ess.Keys`** — bind several hotkeys inside one script (the OnKey loader gives you one key; this lets that
  script own a whole panel): `Ess.Keys.on("F6", fn)` plus off/clear/isBound and a name→VK map. Edge-triggered
  dispatch on one shared loop; resolution + dispatch execute-verified offline. Recipe: `hotkey_toolkit`.
- **`Ess.Easy.Spawn.enemies(n, opts)`** — drop a squad of hostiles ahead and send them at you, one line (an
  instant firefight). Plus `Ess.Player.inVehicle(i)` / `.onFoot(i)` state getters. Recipe: `instant_firefight`.
- **`Ess.Easy.Console.play()`** — the Console is no longer just a reference: an interactive **playground**
  drills into `Ess.Easy.*` functions by topic, RUNS one live on demand, and cycles its parameters (confirmed
  presets) so a new modder sees exactly what each does in-game. Reachable from a pinned row in `.open()`, or
  bound to F3 via the new `Playground` OnKey demo (shipped in the zip). Construction / param-cycling /
  run-dispatch verified offline; UI rendering needs an in-game pass.
- **`Ess.Objective` + `Ess.Quest`** — a lightweight **counted-goal tracker** for the gap between a bare
  `Ess.Hud.objective` text line and a whole `Ess.Contract`. `Ess.Objective` shows "label 3/5" on the HUD and
  fires a callback at target; `Ess.Quest` sequences steps one at a time. The **intent bundles** are the
  headline: `Ess.Easy.Objective.reach/.destroy/.clear/.survive` wire a goal to a world event AND drop its
  marker in one line (`clear` polls an area to sidestep the engine's missing "kill" event), and
  `Ess.Easy.Quest` makes a whole linear mission — `{reach=…}`, `{destroy=…}`, `{clear=…}`, `"manual"` steps —
  one table. State machine (counting, sequencing, auto-wiring, marker + watcher teardown, reload-safe id
  replace) execute-verified offline; the engine reads/marks need an in-game pass. Recipes: `track_a_goal`,
  `a_quick_mission`.
- **`Ess.Easy.Debug.overlay()`** — a live on-screen **dev overlay** for mod authors: your exact position +
  yaw, what you're aiming at (name/faction/distance), on-foot/vehicle, health, nearby counts. Toggle it to
  read a spawn/teleport position off the screen instead of logging it. Callable as `Ess.Easy.Debug.overlay()`
  and surfaced in the `CreatorToolkit` hub (below). Line-building + toggle verified offline; panel render needs
  an in-game pass. Recipe: `dev_overlay`. (Deliberately shows no "FPS" — the refresh is a timer, so any
  framerate would be the tick rate, not the real one.)
- **`Ess.Hud.objective(text, nSlot)`** now takes an optional tray slot (default 1), so `Ess.Objective`/`Quest`
  can show a goal on a line other than a running Contract's. Backward-compatible.
- **`Ess.Safe.template(name)`** — the canonical "is this a spawnable template" check (non-blank string),
  centralising the blank-`Pg.Spawn`-hard-crash guard that was re-inlined in ~6 spawn paths, so a new spawn
  path is one call from safe. Covered by `tools/checkpure.py`.

- **`VehicleInspector` OnKey demo** (F6) — a WAILA-style "what vehicle am I in" inspector (poll-detect the
  vehicle you enter, dump its guid + details to the log, live HUD panel). Ships in the zip; a compact showcase
  of `Ess.Player`/`Object`/`Vehicle`/`UI`/`Loop`.
- **Three "complete mini-mode" OnKey demos** (ship in the zip) — larger playable examples that each compose
  the framework into something that *does* something:
  - **`WaveSurvival`** (F11) — a horde mode: escalating waves rush you, clear one to heal (+ a crate every
    3rd), G for a danger-close airstrike, HUD tracks wave/kills. (`Easy.Spawn.enemies` + `On.death` +
    `Support` + `UI.Panel` + `Keys` + `Time.cooldown`)
  - **`BossFight`** (F12) — a mini-boss with a live `UI.Bar` health bar that regenerates until 50%, then
    enrages (adds + screen shake); cash reward on kill. (`On.healthBelow` + `On.death` + `Camera.shake` +
    `Loop`)
  - **`EncounterDirector`** (F1) — a weighted-random encounter roller (ambush / bounty / supply drop /
    dodge-the-artillery / a 3-checkpoint time trial). (`RNG:pick` + `Easy.Objective.destroy` + `Quest` +
    `Support`)
- **`CreatorToolkit` OnKey demo** (F8) — a **hub of in-game dev/creator tools** behind one menu (the editor
  Mercs2 never shipped): object inspector (WAILA for anything under your reticle), an **AI-cap meter** vs the
  ~200 soft cap, a nearby-object scanner, the debug overlay (folded in — this supersedes the standalone
  `DebugOverlay` demo), **persistent teleport bookmarks** (`SaveVar`), a prop placer (spawn-at-reticle +
  rotate/delete), a dev panel (invincible / infinite ammo / time-scale / freeze nearby AI / clear heat / cash),
  a photo mode, and a **camera-path → cinematic recorder** (drop keyframes, play them back as a fly-through).
  First-pass draft, compile-clean; the two camera tools use the confirmed cinematic API but don't implement a
  WASD freecam yet (you author by positioning your character), and there's no native full-HUD-hide, so photo
  mode hides player markers only. Needs the in-game pass.
- **`tools/webrepl.py` + `tools/webrepl.html`** — a browser **"mod console"**: a tiny local HTTP relay (reusing
  `lua_repl.py`'s protocol) serves a page that makes `Ess.*` calls in the **live game** — a grid of one-click
  actions plus a free-form Lua box, with a live bridge-status indicator. Browsers can't open raw TCP, so the
  relay bridges HTTP → the lua-bridge (127.0.0.1:27050). Binds to localhost only. The whole HTTP↔bridge path is
  verified end-to-end (page serves, `/probe`/`/exec` respond correctly); live results need the game running.

### Hardening (pre-release audit of the unreleased batch, offline)

- **`Ess.Support.reinforce`**'s `deliver="copter"` path now validates the template before `MrxCopterDrop.Create`
  (via `Ess.Safe.template`) — the direct-spawn path was already guarded, the copter path wasn't, and a blank
  template can hard-CTD through the internal spawn (pcall can't catch a native crash).
- **`Ess.Easy.Debug.overlay`** now throttles its nearby world-scan (two native `FastCollect` passes) to ~1×/s
  and caches it, instead of running it on every fast pos/aim tick — a dev overlay should stay light enough not
  to perturb what you're measuring.

## [0.2.1]

### Changed
- **`Ess.Easy.Camera.orbit` and `.watch(chase=true)` now damp the follow by default.** The moving camera
  eases toward its ideal position each tick via `Ess.Vec.lerp`, low-passing the per-tick position
  quantization that made a follow of a FAST subject jitter — confirmed live against an orbit around a heli
  and a hard-launched car. New opts: `smooth` (default `true`; pass `false` for the old exact-snap) and
  `smoothFactor` (0..1, default `0.2` — higher = snappier / less lag, lower = glassier / more lag). The
  static (non-chase) `watch` is unchanged; it has no per-tick position to smooth.

## [0.2.0]

A pure-Lua utility layer, an onboarding + contributor guide, an offline test suite wired into CI, and a
dozen new samples. All additive — nothing changed in existing engine code.

### Added
- **`Ess.Str`** — the string helpers Lua 5.1's thin `string` lib omits: split / join / trim / startsWith /
  endsWith / contains / count / padLeft / padRight / capitalize / title / lines / truncate. Separators are
  LITERAL text, not Lua patterns (so `split(s, ".")` splits on a real dot).
- **`Ess.Color`** — RGB helpers for the `rgb = {r,g,b}` params across `Ess.Mark` / `Ess.UI`: `hex` (web
  colours, long or short form), `hsv` (rainbows and evenly-spaced team tints), `lerp` (health-bar
  gradients), and a `NAMES` preset table.
- **`Ess.Table`** collection helpers — keys / values / count / isEmpty / contains / indexOf / map / filter /
  find / reduce / slice / reverse / copy / merge.
- **`Ess.Math`** — clamp01 / remap / smoothstep / lerpAngle (shortest-path angle lerp) / wrap; plus
  dist2DSq / dist3DSq and within2D / within3D (the `dx*dx+dz*dz <= r*r` range test, named — no sqrt).
- **`Ess.Vec`** — 3D vector math on flat x,y,z (length / normalize / scale / add / sub / dot / dir / toward
  / lerp) — the spatial helpers spawn / aim / knockback code otherwise open-codes.
- **`Ess.RNG`** — `:shuffle` (in-place, unbiased Fisher-Yates) and `:pickN` (distinct sample without
  replacement).
- **GETTING_STARTED.md** — an install-to-first-mod on-ramp (linked from the README) for a game that never
  shipped mod support: the OnLoad/OnKey model, the `_G.Ess` guard, the re-run gotcha, the dev loop.
- **CONTRIBUTING.md** — how to extend Ess safely (the build, the three verification gates, adding a
  namespace) plus the confirmed engine rules every helper respects (a useful reference for any Mercs2 Lua).
- **`samples/OnKey/StarterMod.lua`** — a copy-me starter template (the guard / state / action patterns as a
  god-mode toggle), bound to F5 and shipped in the release zip.
- Recipes: `text_and_tables`, `smooth_and_range`, `pick_colors`, `vector_math`, `random_order` (the new
  utilities); `cooldowns`, `remember_this_session` (timing / session state); `watch_a_vehicle`,
  `a_custom_hud` (engine patterns). The 34-recipe catalog is regrouped by theme.
- **`tools/checkpure.py`** — an offline behavioral test suite (via lupa) for the pure namespaces
  (Math / Str / Color / Table / RNG / State / Time), wired into CI alongside the syntax gate. Catches
  pure-logic regressions with no game required — coverage `smoke.py` can't give without the game up.
- The release zip now bundles the on-ramp and the full reference (`Ess-GETTING_STARTED.md` /
  `Ess-CAPABILITIES.md`), so a download is self-contained for learning, not just installing.

**Verification:** the entire pure-Lua layer (Safe / Str / Color / Vec / Table / Math / RNG / Points / State /
Time) is execute-verified offline by `tools/checkpure.py`, the merged build passes the `luac5.1` syntax gate,
and the **full recipe suite ran 34/34 PASS in a live game** — including the two engine-touching recipes
`watch_a_vehicle` and `a_custom_hud`. The `StarterMod` OnKey template isn't covered by `smoke.py` (it's a
keybound script, not a recipe), but is built from the same confirmed calls those passing recipes exercise.

## [0.1.1]

### Fixed
- Packaging: the release zip now bundles `samples/PORTING_MENUS.md` (and any future top-level sample doc)
  under `Ess-samples/`. `build/package.py` had hardcoded only `samples/README.md`, so the v0.1.0 zip left
  the menu-porting guide out.

## [0.1.0]

First public release — the whole `Ess` framework as one drop-in `1_Ess.lua`, plus the UI wad, the
bind-to-a-key demos, and the recipe catalog.

### Added
- **The framework** — safe, one-line wrappers over this project's hard-won Mercenaries 2 modding patterns,
  across ~60 namespaces: Object / Vehicle / Human / Player / Probe / Bones; the Loop / Input / Time / State /
  Save primitives; the leak-proof Track teardown; the `Ess.UI` kit (menus, lists, toasts, board, chat);
  Camera plus a declarative Cinematic timeline; the encounter toolkit (AIOrders / Relations / Triggers /
  Sandbox / Layers); Net; and the save-safe ephemeral Contract mission engine — organised in the
  Raw → Core → Easy tiered model.
- **Samples** — 25 self-verifying recipes (each a living doc *and* a smoke test run by `tools/smoke.py`) and
  five bind-to-a-key demos, including the MissionForge in-game authoring tool.
- **Build tooling** — `build/merge.py` (concatenate `src/` into `dist/Ess.lua`) and `build/package.py` (the
  release zip in game-folder layout), plus CI + release GitHub Actions.

### Fixed
- Contract trigger action crashed (`table index is nil`) when a support/waypoint was wired by
  `trigger={ref=...}` with no `id` of its own — id-less referenced entries are handled now.
- `escort` read a killable target's position un-pcall'd; `spawnAhead` now reuses `Ess.Math.pointAhead`
  instead of re-inlining the projection; dropped a redundant save-holder reset.

### UI
- Hold Up/Down to auto-repeat through a list/menu after a short delay; the selection now wraps around at the
  top and bottom instead of stopping.
