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
helpers rather than being absorbed itself. See [FEATURE_SHEET.md](FEATURE_SHEET.md) — its "Implementation
status" section opens with an at-a-glance summary, then the full chronological build history below that.

## Layout

- `FEATURE_SHEET.md` — the design doc; read this first (start with its "at a glance" summary).
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
- `dist/` — the generated file. **Gitignored, not committed** — build it yourself before deploying.
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

## Related repos

- `mercs2-lua-mods` — the ORIGINAL `ModNet`, `uilib`, `ContractFramework`, and the `WaveDefense` gamemode
  that motivated this project. `WaveDefense.lua` is still the active, maintained gamemode file — the other
  three are historical only, superseded by their native `Ess.*` absorptions above and no longer deployed.
- `mercs2-layer-framework` — the ORIGINAL `LayerFw`, superseded by native `Ess.Layers`. Historical only.
