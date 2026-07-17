# Changelog

All notable changes to Ess are recorded here. Versions track `Ess.VERSION` in `src/00_core.lua`.

Releases are automatic: **bump `Ess.VERSION`, add a matching `## [x.y.z]` section below, and push to
`master`**. `.github/workflows/release.yml` then builds a fresh `1_Ess.lua`, syntax-checks it, packages the
zip, and publishes a GitHub Release tagged `v<version>` using that section as the notes. (No section for the
version? It still releases, with auto-generated commit notes.) See the README's "Releasing" section.

## [Unreleased]

Closing "creativity gaps" for new modders — the framework is strong on *how* to do things, thinner on *what
you can do* and on reacting to the player. All additive. **Not yet in-game smoke-run** (built from confirmed
calls + offline-verified where pure); test in a live game, then bump to `0.3.0` to release.

### Added
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
  read a spawn/teleport position off the screen instead of logging it. Bound to F8 via the new `DebugOverlay`
  OnKey demo (shipped in the zip). Line-building + toggle verified offline; panel render needs an in-game
  pass. Recipe: `dev_overlay`. (Deliberately shows no "FPS" — the refresh is a timer, so any framerate would
  be the tick rate, not the real one.)
- **`Ess.Hud.objective(text, nSlot)`** now takes an optional tray slot (default 1), so `Ess.Objective`/`Quest`
  can show a goal on a line other than a running Contract's. Backward-compatible.
- **`Ess.Safe.template(name)`** — the canonical "is this a spawnable template" check (non-blank string),
  centralising the blank-`Pg.Spawn`-hard-crash guard that was re-inlined in ~6 spawn paths, so a new spawn
  path is one call from safe. Covered by `tools/checkpure.py`.

- **`VehicleInspector` OnKey demo** (F6) — a WAILA-style "what vehicle am I in" inspector (poll-detect the
  vehicle you enter, dump its guid + details to the log, live HUD panel). Ships in the zip; a compact showcase
  of `Ess.Player`/`Object`/`Vehicle`/`UI`/`Loop`.

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
