# mercs2-lua-essentials

`Ess` — the foundational Lua library for Mercenaries 2 modding. Wraps every hard-won pattern this
project has discovered (bone manipulation, the 32-bit-float RNG trap, leak-prone handle APIs, the
FlashWidget corner-coordinate bug, the trigger/relations/AI-order vocabulary built for wave-defense)
into safe, one-line helpers, so a new modder doesn't have to rediscover them by crashing the game first.

**Status: core primitives built, nothing else yet.** See [FEATURE_SHEET.md](FEATURE_SHEET.md) for the
full namespace map and its "Implementation status" section for exactly what's done vs. planned — it
documents what's brand new, what's adopted unchanged from an existing framework (`ModNet`, `uilib`,
`ContractFramework`, `LayerFw`), and what's extracted from where it currently lives buried and duplicated
inside `WaveDefense.lua`/`ContractFramework.lua`.

## Layout

- `FEATURE_SHEET.md` — the design doc; read this first.
- `src/` — per-namespace source files. `00_core.lua`/`10_player.lua`/`11_object.lua`/`12_vehicle.lua`/
  `13_probe.lua`/`20_loop.lua`/`21_input.lua`/`22_state.lua`/`30_track.lua`/`53_rng.lua` exist; the rest of
  the sheet's namespaces don't yet.
- `build/merge.py` — concatenates `src/*.lua` (in an explicit dependency order, not alphabetical) into
  one deployable `dist/Ess.lua`. Run `python build/merge.py` from anywhere; it resolves its own paths.
- `dist/` — the generated file. **Gitignored, not committed** — build it yourself before deploying.
- `tools/` — testing infrastructure (not part of the `Ess` library itself). `xpad.py` is a virtual
  Xbox 360 controller (ViGEmBus + `vgamepad`), driven over a local TCP socket, for exercising
  controller-driven code like `Ess.Input.hijackController` end to end. `launch.py` chains
  build -> deploy -> launch -> menu-navigation into one command (`python tools/launch.py --all`),
  confirmed working end-to-end 2026-07-16. See `tools/README.md`.

## Quick start (once you've built `dist/Ess.lua`)

Copy it into `<game>/scripts/OnLoad/` as `1_Ess.lua` and give it a low number in `lua_loader.ini`'s
`[OnLoad]` section (before `ModNet`/`uilib`/`ContractFramework` if you use those too). Every other mod
script just reads off the global `_G.Ess` table — see `FEATURE_SHEET.md` for the full API.

## Related repos

- `mercs2-lua-mods` — `ModNet`, `uilib`, `ContractFramework`, and the `WaveDefense` gamemode that
  motivated this project.
- `mercs2-layer-framework` — `LayerFw`, adopted here as the `layers` provider for `Ess.Sandbox`.
