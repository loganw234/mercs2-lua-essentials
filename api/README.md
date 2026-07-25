# `api/` — machine-readable manifests

Three JSON files describe Ess and the engine it sits on, for **tooling** rather than for reading. They ship in
every release zip under `api/`, so a consumer can pull them from a release asset instead of building this repo.

| File | What it answers | Where it comes from |
|---|---|---|
| `ess.json` | *What can I call?* Every public `Ess` function — namespace, tier, parameters, returns, description, source file and line. | **Generated** by `build/manifest.py` from `src/`. In `dist/`, rebuilt every build. |
| `natives.json` | *What exists at all?* The whole engine surface, split into **engine natives** (C++, no source anywhere) and **resident game script** (ordinary Lua, with its path in the decompiled corpus). Each namespace records which of its functions Ess already reaches. | **Captured** by `tools/dump_natives.py` from a *running game*. Committed here. |
| `nodes.json` | *How do I show this to a beginner?* Node definitions for the visual editor — one per function, with a plain-English description, a type and default and explanation for every parameter, and its output shape. | **Generated** by `build/nodes.py` from `ess.json` + `nodes.overlay.json`. In `dist/`. |

## Why two of them are generated and one is committed

`ess.json` is *derived from this repo's own source*, so it must never be stale — it is gitignored and
regenerated on every build. `natives.json` is *captured from an external system* (a live game), which CI has
no way to reproduce, so a gitignored copy would simply be absent from every release. Committing it is the only
thing that works, and it changes essentially never — only if the game or the bridge changes.

That distinction is load-bearing, not bookkeeping: the v0.4.0 release shipped without its manifests precisely
because this wasn't thought through the first time.

## `nodes.overlay.json` — the hand-authored half

`ess.json` knows a function's *signature*. It cannot know that `uGuid` means "a live handle, not a quoted
string", that `nDist` is in world units and defaults to 18, or that an AI order with no destination is silently
dropped. That knowledge lives in the source comments, and the overlay is where it gets written down in a form
a beginner-facing tool can use.

**Edit the overlay, never `ess.json`** — that one is regenerated from `src/` and your edits would be destroyed
on the next build.

The overlay **cannot invent anything**. `python build/nodes.py --check` (which CI runs) validates every entry
against `ess.json`: an entry naming a function that doesn't exist, or giving a function a parameter it doesn't
have, fails the build. The overlay adds *meaning* to a real signature; it can never add a signature. That is
what keeps a hand-maintained file from drifting into fiction.

## Consuming `nodes.json`

Each node carries everything needed to render and compile it:

```json
{
  "id": "essgen/object/spawnahead",
  "call": "Ess.Object.spawnAhead",
  "title": "Object: Spawn Ahead Of Player",
  "desc": "Creates something a set distance in front of the player, already facing the same way.",
  "category": "Ess.Object",
  "tier": "core",
  "kind": "action",
  "params": [
    {"name": "sTemplate", "type": "string", "default": "Veyron", "desc": "...", "optional": false, "inferred": false}
  ],
  "returns": [{"name": "uGuid", "type": "guid", "desc": "..."}],
  "source": {"file": "11_object.lua", "line": 378}
}
```

**`type` decides how a value reaches the generated Lua**, and getting it wrong is the difference between a
working node and one that silently does nothing:

| type | Widget | Reaches Lua as |
|---|---|---|
| `number` | number | spliced raw — `18` |
| `string` | text | **quoted** — `'Veyron'` |
| `guid` | text | **spliced RAW** — `Ess.Player.character(0)`. A guid is a live engine handle, so the widget's text is *code*. Quoting one produces Lua that runs, logs nothing, and does nothing. |
| `bool` | toggle | `true` / `false` |
| `table` | text | spliced raw — `{ x, y, z }` |
| `function` | text | spliced raw — `function() ... end` |
| `lua` | text | spliced raw — any other expression |

**`kind`** is `action` (has exec pins; emits a statement; multi-value returns are captured into one local each)
or `getter` (no exec pins; the call is spliced inline as an expression). A getter can only ever have **one**
return, because Lua truncates a multi-value call to a single value when it isn't the last item in a list —
`build/nodes.py` automatically promotes any multi-return getter to an action rather than silently dropping
values.

**`inferred: true`** on a parameter means its type was guessed from the parameter's *name* and not confirmed
against the source. Treat those with suspicion; `python build/nodes.py --report` lists what is still unconfirmed.

### Ready-made consumer

`dist/ess-nodes.generated.js` registers every one of these as a litegraph node type, for anyone who wants it
working with no integration at all. Load it after litegraph and after the editor's own `codegen.js`.

Its type ids are prefixed **`essgen/`, never `ess/`** — deliberately. The visual editor has its own
hand-written `ess/` nodes; registering generated types under the same ids would silently overwrite hand-tuned
ones depending on script load order. Both can coexist, so an editor can migrate one namespace at a time on
purpose rather than all at once by accident.

`node tools/test_nodes.js` executes that file against a stubbed editor and asserts the Lua it produces — no
browser, no editor checkout, no game.
