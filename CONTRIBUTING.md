# Contributing to Ess

Ess grows by absorbing hard-won patterns into safe one-liners. This is how to add one without breaking the
build or shipping a footgun — and, in the "Engine rules" section, the confirmed facts about the game's Lua
that every helper here has to respect (useful even if you're just writing your own mod against raw calls).

## Repo layout

```
src/NN_name.lua     one file per namespace; the NN prefix is LOAD ORDER, not alphabetical
build/merge.py       concatenates src/ (in an explicit dependency order) into dist/Ess.lua
build/package.py      builds the release zip in game-folder layout
dist/                 generated, gitignored -- build it, don't commit it
samples/recipes/      short "how do I X?" scripts; each is a living doc AND a smoke test
samples/demos/         bind-to-a-key interactive demos (reference only -- not deployed by Ess itself)
tools/                testing infra (checkpure / smoke / lua_repl / launch / xpad) -- see tools/README.md
```

## How the build works (and the one rule it enforces)

`merge.py` wraps **each** `src/*.lua` file in its own `do ... end` block before concatenating, so a top-level
`local` in one file can't leak into another. The consequence you must respect: **a file's top-level `local`s
are private to that file.** Share across files only through the `_G.Ess` table (a field write like
`function Ess.Foo.bar()`), never a bare `local`. If two files need to share a private helper, expose it as a
`Ess._private` field (see how `80_contract.lua` hands helpers to `81`/`82`).

The `MANIFEST` list in `merge.py` **is** the dependency order — add your file in the position its
dependencies require, not just at the end. Pure files with no Ess deps go early (00–09); anything using
`Ess.Loop`/`Ess.UI`/etc. goes after those load.

## Adding a namespace

1. **Write** `src/NN_name.lua`. Start with a header comment: a one-line purpose, the API list, and — for
   anything non-obvious — *why* (which confirmed call, which gotcha). Match the surrounding density; the
   comments are the docs.
2. **Register** it in `merge.py`'s `MANIFEST`, in dependency order.
3. **Tier it only if there's a real gap** — most namespaces are single-tier. Add `Ess.Easy.*` (guardrail
   presets) / `Ess.Raw.*` (bare primitives) around a Core `Ess.*` only where a beginner/advanced split
   genuinely helps (see Mark, AIOrders, Relations, Triggers, Sandbox for the pattern).
4. **Document** it in `CAPABILITIES.md` (the current-state reference) and note it in `CHANGELOG.md` under
   `## [Unreleased]`.
5. **Add a recipe** in `samples/recipes/` — one task, ending in `Ess.Log("[SMOKE] <name>: " .. (ok and "PASS"
   or "FAIL"))`. It's both the example and the test.
6. **Test it** (see below).

## Verifying a change — three gates, cheapest first

| Tool | Checks | Needs |
|---|---|---|
| `python tools/checkpure.py` | *behavior* of the PURE namespaces (Math/Str/Color/Vec/Table/RNG/State/Time), executed and asserted | just `pip install lupa` — no game |
| CI's `luac5.1 -p` | *syntax* of the merged `dist/Ess.lua`, against the engine's real Lua 5.1 | GitHub Actions (runs on every push) |
| `python tools/smoke.py` | every recipe run *in the live game* | the game running with the lua-bridge up |

If your namespace is **pure** (no engine calls), add a group to `checkpure.py` and you get real
correctness coverage with no game. If it touches the engine, a recipe + `smoke.py` is the only real proof —
compose from confirmed calls and say so in the PR if you couldn't smoke-run it. **Never let an unverified
engine change ride into a release** as if it were tested.

## Releasing

Bump `Ess.VERSION` in `src/00_core.lua`, rename the `CHANGELOG.md` `## [Unreleased]` section to the new
version, and push to `master`. `.github/workflows/release.yml` builds a fresh `1_Ess.lua`, runs the syntax
gate, packages the zip, and publishes the tagged GitHub Release with your changelog section as its notes.

## Coding conventions

- **`pcall`-guard every fallible engine call.** `Object.*` getters throw on an invalid/dead guid; the whole
  point of a wrapper is to return `nil` instead of propagating that. Use `Ess.Safe.call`/`.quiet` or a plain
  `pcall`.
- **One canonical name per concept.** If the engine exposes a call three ways, pick the confirmed idiom and
  wrap it once; don't surface all three.
- **Coerce engine booleans.** Getters return `1`/`0`, and `0` is *truthy* in Lua — a naive `if x` is a bug.
  Check `x == true or x == 1`.
- **Return flat components** (`x, y, z`) to match `Ess.Object.pos`/`setPos`, not tables — but mind the
  multi-return caveat below.

## Engine rules (the confirmed facts every helper respects)

These are the traps Ess exists to paper over. They're real and load-bearing — respect them in any Mercs2 Lua,
Ess or not:

- **It's Lua 5.1**, with 32-bit **float** numbers (integers exact only to 2²⁴). A big-multiplier LCG silently
  degenerates — use `Ess.RNG` for randomness, and keep hot integer math well under 2²³.
- **A blank/whitespace `Pg.Spawn` template hard-CRASHES the engine** (null asset in C++), and `pcall` can't
  catch a native crash — only a Lua error. Validate the template *before* the call (`Ess.Object.spawn` does).
- **`return orig(...)` when overriding an engine function crashes** — it compiles as a tail call, and the
  engine's `getfenv(n)` walks frames, so a collapsed frame throws from deep in engine code. Use
  `Ess.Override.wrap`, which makes that shape structurally unwritable.
- **A freshly `Pg.Spawn`'d model's hardpoints read `nil` for ~0.3s.** Don't read bones at spawn time — poll
  (`Ess.Bones.waitForReady`).
- **`Net.IsClient()` returns true in single-player.** Gate host-only logic on `Net.IsMultiplayer() and
  Net.IsClient()`, never `IsClient()` alone.
- **`FlashWidget:SetLocation` takes CORNER coords** `(x, y, x+w, y+h)`, not `(x, y, w, h)`; the visibility
  getter is `GetVisible()` (there's no `IsVisible`).
- **Debug output goes through `Loader.Printf`** (Ess wraps it as `Ess.Log`), not `Debug.Printf`.
- **The multi-return caveat:** Lua truncates a multi-value call to ONE value unless it's the LAST item in a
  list. So a three-value Ess call (`Ess.Vec.dir`, `Ess.Color.hex`) expands fully as the last argument of a
  call, but to NEST two of them you must capture the inner one into locals first.
