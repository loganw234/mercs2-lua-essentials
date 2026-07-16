# mercs2-lua-essentials

`Ess` — the foundational Lua library for Mercenaries 2 modding. Wraps every hard-won pattern this
project has discovered (bone manipulation, the 32-bit-float RNG trap, leak-prone handle APIs, the
FlashWidget corner-coordinate bug, the trigger/relations/AI-order vocabulary built for wave-defense)
into safe, one-line helpers, so a new modder doesn't have to rediscover them by crashing the game first.

**Status: design phase.** See [FEATURE_SHEET.md](FEATURE_SHEET.md) for the full namespace map before any
code lands — it documents what's brand new, what's adopted unchanged from an existing framework
(`ModNet`, `uilib`, `ContractFramework`, `LayerFw`), and what's extracted from where it currently lives
buried and duplicated inside `WaveDefense.lua`/`ContractFramework.lua`.

## Layout

- `FEATURE_SHEET.md` — the design doc; read this first.
- `src/` — per-namespace source files (not yet written).
- `build/` — the merge script that concatenates `src/*.lua` into one deployable `Essentials.lua`
  (not yet written).
- `dist/` — the generated deployable file (open question in the feature sheet: committed or built
  on demand).

## Related repos

- `mercs2-lua-mods` — `ModNet`, `uilib`, `ContractFramework`, and the `WaveDefense` gamemode that
  motivated this project.
- `mercs2-layer-framework` — `LayerFw`, adopted here as the `layers` provider for `Ess.Sandbox`.
