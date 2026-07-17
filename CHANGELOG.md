# Changelog

All notable changes to Ess are recorded here. Versions track `Ess.VERSION` in `src/00_core.lua`.

Releases are automatic: **bump `Ess.VERSION`, add a matching `## [x.y.z]` section below, and push to
`master`**. `.github/workflows/release.yml` then builds a fresh `1_Ess.lua`, syntax-checks it, packages the
zip, and publishes a GitHub Release tagged `v<version>` using that section as the notes. (No section for the
version? It still releases, with auto-generated commit notes.) See the README's "Releasing" section.

## [Unreleased]

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
  utilities); `cooldowns`,
  `remember_this_session` (timing / session state); `watch_a_vehicle`, `a_custom_hud` (engine patterns).
- **`tools/checkpure.py`** — an offline behavioral test suite (via lupa) for the pure namespaces
  (Math / Str / Color / Table / RNG / State / Time), wired into CI alongside the syntax gate. Catches
  pure-logic regressions with no game required — coverage `smoke.py` can't give without the game up.
- The release zip now bundles the on-ramp and the full reference (`Ess-GETTING_STARTED.md` /
  `Ess-CAPABILITIES.md`), so a download is self-contained for learning, not just installing.

**Verification (game was closed for this batch):** the utility layer and the pure recipes
(`text_and_tables` / `pick_colors` / `random_order` / `cooldowns` / `remember_this_session`) were verified by
EXECUTION against the real source via lupa — correctness-checked, not merely built. The two engine-touching
recipes (`watch_a_vehicle`, `a_custom_hud`) compose only confirmed calls and pass the syntax gate, but were
NOT smoke-run in-engine — run `python tools/smoke.py` to confirm them before relying on them.

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
