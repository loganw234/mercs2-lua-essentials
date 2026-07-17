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
  find / copy / merge.
- **`Ess.Math`** — clamp01 / remap / smoothstep / lerpAngle (shortest-path angle lerp) / wrap.
- **`Ess.RNG`** — `:shuffle` (in-place, unbiased Fisher-Yates) and `:pickN` (distinct sample without
  replacement).
- Recipes: `text_and_tables`, `pick_colors`, `random_order`.

All of the above is pure Lua (no engine calls) and was verified by execution against the real source (via
lupa), not just built — so it's correctness-checked despite the game being closed.

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
