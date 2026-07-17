# mercs2-lua-essentials

`Ess` — the foundational Lua library for Mercenaries 2 modding. Wraps every hard-won pattern this
project has discovered (bone manipulation, the 32-bit-float RNG trap, leak-prone handle APIs, the
FlashWidget corner-coordinate bug, the trigger/relations/AI-order vocabulary built for wave-defense)
into safe, one-line helpers, so a new modder doesn't have to rediscover them by crashing the game first.

**Status: the full framework is built and live-tested.** Every namespace in the original design (Groups
A–J) exists and has been verified against the running game, not just load-checked. `uilib`, `ModNet`,
`ContractFramework`, and `LayerFw` — originally meant to stay separate frameworks Ess would merely alias —
are now fully **absorbed as native `Ess` code** (`Ess.UI`, `Ess.Net`, `Ess.Contract`, `Ess.Layers`); the
original standalone files are retired from active use, kept untouched in their own repos in case they're
needed again. `WaveDefense.lua` (the gamemode that motivated this whole project) is the one deliberate
exception — it stays its own file, flagged for an eventual, not-yet-started refactor to *consume* `Ess.*`
helpers rather than being absorbed itself.

**New here?** [GETTING_STARTED.md](GETTING_STARTED.md) — install Ess and write your first keypress mod in a
few minutes. **Full reference:** [CAPABILITIES.md](CAPABILITIES.md) — a clean, current-state map of
everything `Ess` does, organized by what you reach for and tier-aware. For the design rationale and full
build history (every bug found, every pivot), see [FEATURE_SHEET.md](FEATURE_SHEET.md). **Extending Ess** (or
writing your own Mercs2 Lua)? [CONTRIBUTING.md](CONTRIBUTING.md) covers the build, the three verification
gates, and the confirmed engine rules to respect.

## Layout

- `CAPABILITIES.md` — **current-state capability reference; read this first** to see what Ess can do now.
- `FEATURE_SHEET.md` — the original design doc + append-only build log (the *why* and the history).
- `src/` — per-namespace source files, `NN_name.lua` (numeric prefix = load/dependency order, not
  alphabetical — see `build/merge.py`'s own comments for why). Roughly: `00`–`14` core/identity/query,
  `20`–`22` timing/input/state, `30`–`31` tracking/marking, `40`–`57` UI/gfx/sound/hud, `60`–`64` the
  encounter toolkit (AI orders/relations/triggers/sandbox/layers), `70`–`71` networking, `80`–`83` the
  contract engine, `90` overrides, `95`–`96` cross-cutting Easy-tier presets and the in-game API console.
  Many namespaces are tiered — `Ess.Raw.X` (composability) → `Ess.X` (Core, named params) → `Ess.Easy.X`
  (guardrails, opinionated presets) — where a real beginner/advanced gap exists; see FEATURE_SHEET.md's
  "Tiered access model" section.
- `build/merge.py` — concatenates `src/*.lua` (in an explicit dependency order, not alphabetical) into
  one deployable `dist/Ess.lua`. Run `python build/merge.py` from anywhere; it resolves its own paths.
- `build/package.py` — the **release build action**: runs `merge.py`, then zips a fresh `1_Ess.lua`, the
  `data/vz-patch.wad` UI patch, the `samples/OnKey/` demos, and the recipe catalog into
  `dist/Ess-<version>.zip`, laid out in the game's own folder structure (`scripts/OnLoad/` + `scripts/OnKey/`
  + `data/`) so a user just extracts it over their Mercenaries 2 install. `Ess-README.txt` inside carries the
  `lua_loader.ini` lines. Attach the zip to a GitHub Release (`gh release create v<version> dist/Ess-<version>.zip`).
- `dist/` — the generated file(s). **Gitignored, not committed** — build/package them yourself before shipping.
- `tools/` — testing infrastructure (not part of the `Ess` library itself). `xpad.py` is a virtual
  Xbox 360 controller (ViGEmBus + `vgamepad`), driven over a local TCP socket — must be started before the
  game launches. `launch.py` chains build → deploy → virtual-controller → launch → menu-navigation into
  one command (`python tools/launch.py --all`, or `--all --wait-ess` to also poll for the `[Ess]` ready
  marker in the background from the moment the game process starts). `lua_repl.py` is a log-based live
  REPL into the running game — `--code '<lua>'` runs a chunk and returns its result via the printf log
  (not the socket, which is one-execution-behind). See `tools/README.md` and
  `.claude/skills/ess-live-test/SKILL.md` for the full dev-loop workflow.

## Quick start (once you've built `dist/Ess.lua`)

Copy it into `<game>/scripts/OnLoad/` as `1_Ess.lua` and give it a low number in `lua_loader.ini`'s
`[OnLoad]` section. That's it — `Ess` no longer needs `ModNet`/`uilib`/`ContractFramework`/`LayerFw`
deployed alongside it; everything they used to provide is now native. Every other mod script just reads
off the global `_G.Ess` table — see `FEATURE_SHEET.md` for the full API, or once the game is running, open
`Ess.Easy.Console.open()` in-game for a searchable, browsable reference of the `Ess.Easy.*` surface and a
handful of standout Core-tier one-liners.

## Releasing

Releases are cut by GitHub Actions on a **version bump** — you never build or upload the zip by hand:

1. Bump `Ess.VERSION` in [`src/00_core.lua`](src/00_core.lua) (e.g. `"0.1.0"` → `"0.2.0"`).
2. Add a matching `## [0.2.0]` section to [`CHANGELOG.md`](CHANGELOG.md) describing the changes — this
   becomes the release notes.
3. Commit both and push to `master`.

[`.github/workflows/release.yml`](.github/workflows/release.yml) fires (it watches `src/00_core.lua`), and
if a `v0.2.0` tag doesn't already exist it builds a fresh `1_Ess.lua`, runs the `luac` syntax gate, packages
`dist/Ess-0.2.0.zip` via `build/package.py`, and publishes a Release tagged `v0.2.0` with the changelog
section as its body and the zip attached. It's idempotent — a push that doesn't change the version does
nothing. [`.github/workflows/ci.yml`](.github/workflows/ci.yml) additionally build- and syntax-checks every
push/PR (the stock-Lua parse check the dev box can't run), so a broken build never reaches a release.

## Related repos

- `mercs2-lua-mods` — the ORIGINAL `ModNet`, `uilib`, `ContractFramework`, and the `WaveDefense` gamemode
  that motivated this project. `WaveDefense.lua` is still the active, maintained gamemode file — the other
  three are historical only, superseded by their native `Ess.*` absorptions above and no longer deployed.
- `mercs2-layer-framework` — the ORIGINAL `LayerFw`, superseded by native `Ess.Layers`. Historical only.
