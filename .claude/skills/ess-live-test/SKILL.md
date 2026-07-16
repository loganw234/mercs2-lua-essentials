---
name: ess-live-test
description: Use whenever working on the mercs2-lua-essentials (Ess) Lua framework and a change needs to be tested, verified, or iterated against the ACTUAL RUNNING Mercenaries 2 game rather than just read-reviewed or offline-load-checked. Covers launching/relaunching the game for testing, sending Lua code into the live game and reading back results, confirming the framework loaded, and driving the game with a virtual controller. Trigger this proactively for requests like "does this work", "check if X behaves correctly", "verify this", "let's see if it loads", or any request to iterate on src/*.lua -- even if the user doesn't say "test" or name a tool. There is no visual/screenshot capability into this game, so this workflow IS the feedback loop; treat it as the default verification step for any Ess change, not an optional extra.
---

# Testing Ess against the live game

`Ess` is a Lua framework for Mercenaries 2 (2008 PC game) modding. Reading the source or running it
through `tools/loadcheck.py` only proves it *compiles* — it proves nothing about whether a function
actually does the right thing in the real engine. The only way to find that out is to run it live, and
since there is no way to see the game's screen from here, this skill's tools are the entire feedback
channel: what they report back **is** the ground truth available for this task.

Repo root: `C:\Users\logan\source\repos\mercs2-lua-essentials`. Game install:
`C:\Games\Mercenaries 2 World in Flames`. All commands below assume `cd` into the repo root first.

## The three tools, in one sentence each

- **`tools/xpad.py`** — a virtual Xbox 360 controller (a real kernel-level device via ViGEmBus, not a
  fake). `serve` creates it and holds the connection open for as long as the process lives; `send <CMD>`
  drives it (`PRESS`/`RELEASE`/`TAP`/`STICK`/`TRIGGER`/`RESET`/`PING`/`QUIT`). **Must be started before the
  game launches** — Mercenaries 2 only detects a controller that was already present at its own process
  start, so plugging one in after the fact is invisible to it.
- **`tools/launch.py`** — builds `src/*.lua` into `dist/Ess.lua`, deploys it to the game's
  `scripts/OnLoad/` (with a byte-verified copy and an in-place `lua_loader.ini` edit), starts/reuses the
  controller, launches the game, forces window focus (a launched process does NOT get OS focus by
  itself, and synthetic controller input goes wherever focus is), then runs an open-loop button macro
  through the intro cutscenes and menus that reliably lands inside an actual loaded game.
- **`tools/lua_repl.py`** — sends a Lua chunk into the live game's Lua VM and reads back what it did.
  Unlike a typical REPL, the result comes back via a log file, not the socket (see "Why the log, not the
  socket" below) — this makes it robust rather than a shortcut, don't be tempted to "simplify" it back to
  reading the socket directly.

## The standard workflow

Run this exact sequence any time a claim needs checking against the real engine — "did this load", "does
this function return the right thing", "does this crash" — all of it:

```bash
cd "/c/Users/logan/source/repos/mercs2-lua-essentials"

# 1. Record the log's current size BEFORE launching. The log file gets reset/truncated by the game
#    on a fresh launch, so this offset is really "since this session started", not a running total —
#    always take a fresh reading here, never reuse a number from an earlier session.
OFFSET=$(python tools/lua_repl.py --log-size)

# 2. Build + deploy + (re)launch the game, all the way into an actual loaded save.
python tools/launch.py --all

# 3. Confirm the framework is actually ready -- don't just assume the timing worked. This blocks until
#    "[Ess]" (Ess's own OnLoad boot line) shows up in NEW log content, or times out.
python tools/lua_repl.py --wait-log "[Ess]" --since-bytes "$OFFSET" --wait-timeout 90

# 4. Now the game is live and ready. Run as many checks as needed -- the game keeps running between
#    calls, so there's no need to relaunch for each one.
python tools/lua_repl.py --code 'return Ess.Player.character(0) == Player.GetLocalCharacter()'
python tools/lua_repl.py --code 'return tostring(Ess.SomeFunction(...))'
# ... etc, as many as the task needs

# 5. When fully done with this session (not needed between individual checks):
python tools/xpad.py send QUIT      # releases the virtual controller
# then close the game window (there is no clean remote way to do this -- taskkill if truly necessary)
```

If `launch.py --all` was already run earlier in the same working session and the game is still up, skip
straight to step 4 — check first with `python tools/launch.py --status`, which reports (read-only, no
side effects) whether the build is current, whether it's deployed, whether the controller server is up,
and whether the game process is still running.

## Reading `lua_repl.py`'s output

- `[lua_repl] OK: <value>` — your code ran, `<value>` is whatever it `return`ed, stringified. No return
  statement means `nil`. Use `return X` at the end of your `--code` the same way you'd write a one-off
  console command.
- `[lua_repl] ERROR: <lua traceback>` — your code threw; the message is the real Lua error (e.g.
  `attempt to call global 'Foo' (a nil value)`), not a generic failure — read it, it usually says exactly
  what's wrong.
- `[lua_repl] TIMEOUT: ...` — the tagged result never showed up in the log within the timeout. Usually
  means the bridge/game isn't actually up (check `--probe` or `launch.py --status` first), or the code
  hung (an infinite loop, or a call that blocks).
- **Results are single-line only.** If a value's `tostring()` would contain a newline, it truncates at
  the first one. Fine for numbers, booleans, coordinates, short strings; not for dumping a whole table —
  if that's genuinely needed, print several smaller `--code` calls instead of one big one.

## Why the log, not the socket

An earlier version of this REPL tool read the chunk's `return` value back over the bridge's own TCP
socket. That socket's output is genuinely one-execution-behind (it flushes chunk N's result only once
chunk N+1 has already been sent), which needed a fragile workaround to get right, and it wasn't reliable.
The current tool instead has the chunk itself write its tagged result into `lua_loader_printf.log` via
`Loader.Printf`, and treats that plain append-only file as the authoritative answer — reading a log file
has none of the socket's buffering ambiguity. If `lua_repl.py` ever needs modifying, keep this design;
don't revert to trusting the socket's own response for the actual value (it's still read and surfaced,
but only as a best-effort, possibly-stale error signal, exactly as labeled in the tool's output).

## Known-good baseline (confirmed 2026-07-16)

If a check on one of these ever comes back different, something regressed — these are locked-in, verified
facts about how the pipeline behaves when everything is working:

```bash
python tools/lua_repl.py --code 'return 1+1'
# -> OK: 2

python tools/lua_repl.py --code "return tostring(_G.Ess ~= nil) .. ' v' .. tostring(Ess.VERSION)"
# -> OK: true v0.1.0   (or whatever Ess.VERSION currently is)

python tools/lua_repl.py --code 'return Ess.Player.character(0) == Player.GetLocalCharacter()'
# -> OK: true

python tools/lua_repl.py --code "local r = Ess.RNG.new(1); return string.format('%.3f %.3f %.3f', r:next(), r:next(), r:next())"
# -> OK: 0.001 0.086 0.437   (exact values if seeded with 1 -- confirms the engine-safe RNG actually
#    produces real varying output in the live 32-bit-float engine, not the degenerate big-LCG trap)
```

## When something doesn't work

- **`--probe` says the bridge is DOWN**: the game either isn't running, or lua-bridge's ASI isn't loaded
  next to it. Check `launch.py --status` first; if the game is genuinely not running, run the standard
  workflow above from step 1.
- **`launch.py --all` doesn't reach a loaded game**: its whole button sequence is OPEN-LOOP (fixed
  delays, no visual confirmation) and was tuned on this one machine at one point in time. If cutscenes run
  long, boot is slower than expected, or a game update changes a menu, the timing flags
  (`--boot-wait`, `--cutscene-gap`, `--title-wait`, `--menu-wait`, `--resolve-taps`, `--resolve-gap`) may
  need adjusting — see `python tools/launch.py --help`. Confirm readiness with `--wait-log "[Ess]"` rather
  than trusting the launch sequence blindly finished in time.
- **Virtual controller taps don't seem to do anything in-game**: almost always a focus problem —
  synthetic input goes wherever OS focus currently is, and `launch.py` already re-focuses the window at
  each phase, but if something else stole focus in between (another app, a dialog), a tap can land
  nowhere silently. There's no way to detect this except noticing the game didn't progress as expected.
- **A specific `Ess.*` function errors or gives a surprising answer**: that's real, useful information —
  it means the offline design was wrong about something the live engine actually does. Fix the source in
  `src/*.lua`, then repeat from step 2 (rebuild+redeploy; the running game needs a level reload or relaunch
  to pick up an OnLoad change, a plain `--code` resend does NOT re-run OnLoad).
