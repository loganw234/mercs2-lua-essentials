# Troubleshooting

Symptom-first. If you're mid-[GETTING_STARTED.md](GETTING_STARTED.md) and something didn't do what the guide
said, find the closest match below. Everything here is drawn from confirmed facts already documented
elsewhere in this repo (mostly [CONTRIBUTING.md](CONTRIBUTING.md)'s "Engine rules" and
[GETTING_STARTED.md](GETTING_STARTED.md)'s own mechanics) — nothing new is being asserted here, this just
collects it by symptom instead of by topic.

---

## `[Ess] v<version> ready` never shows up in the log at all

Check, in order:

1. **Do you actually have the lua-bridge loader installed?** It's the one prerequisite Ess doesn't
   provide — Ess is a `.lua` file, and nothing runs a `.lua` file without it. If `scripts/lua_loader.ini`
   doesn't exist in your game folder, you don't have it yet. Community tooling, including the loader,
   lives at **[mercs2.tools](https://mercs2.tools/)** — start there.
2. **Is `1_Ess.lua` actually in `scripts/OnLoad/`?** Not `scripts/OnKey/`, not the game's root folder. A
   release zip extracts it to the right place automatically; a hand-copy is easy to put one folder off.
3. **Is it registered under `[OnLoad]`, not `[OnKey]`, in `scripts/lua_loader.ini`?**
   `1_Ess.lua=5` — the `=5` is a load-order number (any low number works), not a key binding. If you
   pasted it under the wrong section header it will sit there unregistered.
4. **Did you overwrite `lua_loader.ini` instead of merging into it?** If a previous edit replaced the
   whole file, your lua-bridge line (and anything else you'd registered) is gone along with it — the
   loader itself won't run without that line either, so *nothing* would work, not just Ess.
5. **Did you relaunch after adding the line?** `lua_loader.ini` is read at game start. Editing an
   *already-registered* `OnKey` script's code is live (see [GETTING_STARTED.md](GETTING_STARTED.md) §2),
   but adding a brand-new registration — which is what installing Ess for the first time is — needs a
   fresh launch to be picked up.

If all five check out and you still see nothing, open `scripts/lua_loader_printf.log` directly and look for
*any* output at all (from the loader itself, not just `[Ess]`) — if the file is empty or not updating,
the lua-bridge itself isn't running, which points back to step 1.

## Ess loaded fine, but my own mod script does nothing (or errors)

- **Missing the load-order guard.** Every sample in this repo starts with
  `if not _G.Ess then ... return end`. If yours doesn't, and Ess happened to load *after* your script (wrong
  `[OnLoad]` number, or your script is itself an `OnLoad` script racing Ess), it fails with a raw Lua error
  instead of a clean message. Add the guard, then check the log for what it prints.
- **You're relying on a `local` surviving a keypress.** An `OnKey` script re-runs from the top on *every*
  press — a plain `local` is gone by the next press; only `_G` persists. This is exactly what
  `Ess.State` is for (see [GETTING_STARTED.md](GETTING_STARTED.md) §5). If a "toggle" mod seems to reset
  itself, this is almost always why.
- **You added a new `OnKey` script, or changed its key binding, without relaunching.** Editing the *code*
  inside an already-registered `OnKey` script is live. Registering a *new* script, or changing which key
  fires it, needs a relaunch — the `.ini` itself is only read at launch.
- **Two scripts are bound to the same key.** `lua_loader.ini` doesn't warn you about a duplicate key —
  behavior in that case isn't something this project has pinned down, so just don't rely on it. Grep your
  `[OnKey]` section for the key you're using.

## The game crashes to desktop (CTD) — no Lua error, just gone

`pcall` cannot catch a native engine crash, only a genuine Lua error — so if something CTDs with no log
line at all, it's very likely one of these confirmed-crashing shapes rather than a bug in your logic:

- **A blank, whitespace-only, or non-string spawn template.** `Pg.Spawn` (and anything built on it) hard-
  crashes on this in native C++. If you're calling `Pg.Spawn` (or another raw spawn primitive) directly
  with a template string built at runtime (concatenation, a table lookup that might miss), validate it
  first with `Ess.Safe.template(s)`. `Ess.Object.spawn` already does this for you — this only bites raw
  calls.
- **`return orig(...)` inside an overridden engine function.** It compiles as a tail call; the engine's own
  `getfenv(n)` walks stack frames, and a collapsed tail-call frame throws from deep inside engine code, not
  from your override. Use `Ess.Override.wrap` instead — it makes this shape impossible to write by
  accident.
- **Reading a freshly-spawned object's bones/hardpoints immediately.** A model's hardpoints read `nil` for
  roughly 0.3s after `Pg.Spawn`. If you're attaching an effect or reading a bone position right after
  spawning, poll with `Ess.Bones.waitForReady` instead of reading on the same tick.

If none of those match your code, it's genuinely new territory — worth writing down what you were doing
right before the crash (the last few log lines, what you'd just spawned/called) since that's the only trace
a native crash leaves behind.

## Random numbers look wrong — repeating, clustering near 0, or not varying at all

This is Lua 5.1 running on 32-bit **float** numbers (not the 64-bit doubles you'd get almost anywhere
else) — a naive large-multiplier LCG silently degenerates under that precision. Use `Ess.RNG.new(seed)` for
anything that needs real randomness; never hand-roll one against `math.random` or a custom LCG. If you
inherited or ported code with its own RNG, that's the first thing to swap out.

## A menu / toast / other `Ess.UI` widget is mispositioned, or won't hide

If you're going through `Ess.UI.Menu` or one of the other eight `Ess.UI` widgets, this shouldn't come up —
they already account for the two gotchas below. It matters if you're calling `Ess.Gfx` (the raw
FlashWidget layer) directly:

- **`FlashWidget:SetLocation` takes *corner* coordinates**, `(x, y, x+w, y+h)`, not `(x, y, w, h)`. Passing
  a width/height straight through silently misplaces or degenerately sizes the widget.
- **The visibility getter is `GetVisible()`.** There's no `IsVisible()` — calling that throws (or, depending
  on how you guarded it, just silently does nothing).

## Something behaves differently in co-op than you expected

- **`Net.IsClient()` returns `true` even in single-player.** If you (or code you're extending) gates
  host-only logic on `Net.IsClient()` alone, it'll incorrectly treat a solo game as a client. Gate on
  `Net.IsMultiplayer() and Net.IsClient()` instead.
- **`Ess.Net` peer-to-peer delivery hasn't been re-verified two-machine-solo** as of this writing (see
  [CAPABILITIES.md](CAPABILITIES.md)'s Verification status) — the wire protocol is a faithful port of
  previously-working code, but if you hit something that looks like a sync bug specifically in real co-op
  (not single-player), that's a known gap in how thoroughly it's been re-exercised, not necessarily your
  code.

## None of the above matches

- Check `scripts/lua_loader_printf.log` directly — every `Ess.Log(...)` call (and `Loader.Printf` in
  general) writes there, prefixed `[Ess]` for anything from the framework itself, so it's easy to grep.
  Debug output goes through `Loader.Printf`, never `Debug.Printf` — if you're looking for output from
  someone else's older script and can't find it, check which one it uses.
- Two hooks are documented as not yet exercised live end-to-end: `Ess.On.exitArea` (the other seven `On`
  hooks are confirmed) and `Ess.Input.hijackController` with *real* controller input (its known bug is
  fixed, but it's only been re-verified up to that fix, not driven live at an open PDA). If you're hitting
  something odd specifically in one of those two, you may be the first to exercise it this way — see
  [CAPABILITIES.md](CAPABILITIES.md)'s Verification status section for the exact wording.
- Still stuck? The full engine-rules list in [CONTRIBUTING.md](CONTRIBUTING.md) covers the confirmed traps
  this document draws from, in more depth and with the reasoning behind each one.
