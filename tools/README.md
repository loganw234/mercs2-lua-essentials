# tools/

Testing infrastructure for this repo, separate from `src/` (the actual `Ess` library).

## `xpad.py` -- virtual Xbox 360 controller for testing controller-driven Lua

Lets automated tests actually generate real XInput controller events, so code like
`Ess.Input.hijackController` (currently flagged unverified in `21_input.lua`) can be exercised end to
end instead of just read-reviewed.

**One-time setup:**
```
pip install vgamepad
```
`vgamepad` bundles the ViGEmBus driver installer (a kernel-mode virtual-gamepad driver from the
open-source ViGEm project) at `<site-packages>/vgamepad/win/vigem/install/x64/ViGEmBusSetup_x64.msi`.
Run that once, elevated (it'll prompt for UAC), if `python -c "import vgamepad; vgamepad.VX360Gamepad()"`
doesn't succeed cleanly. Confirmed working on this machine 2026-07-16 (ViGEmBus was actually already
present in the driver store from something else installed previously; the MSI run here was a no-op/repair
and the Python-level smoke test — create pad, press A, release A — is what actually confirmed it works).

**The quirk this tool is built around:** Mercenaries 2 only detects a controller that was already present
when the game *launched* — plugging one in afterward doesn't get picked up. So the server (which creates
the virtual pad) always has to start **before** the game does, and has to stay running for the rest of
the session:

```
# 1. start the server FIRST -- this is what "plugs in" the virtual controller
python tools/xpad.py serve

# 2. THEN launch the game

# 3. drive it from anywhere, any number of times, while both keep running
python tools/xpad.py send PRESS A
python tools/xpad.py send TAP B 0.2
python tools/xpad.py send STICK L 0.75 -1.0
python tools/xpad.py send TRIGGER R 1.0
python tools/xpad.py send RESET

# 4. when done
python tools/xpad.py send QUIT
```

Full protocol + button names are in `xpad.py`'s own docstring. Verified standalone (server up, all
commands round-tripping correctly including a bad-button error case, clean QUIT) on 2026-07-16, and
CONFIRMED live-driving the actual game (see `launch.py` below, which uses it for the whole intro/menu
sequence) the same day.

## `launch.py` -- build -> deploy -> launch -> skip-intro, one command

```
python tools/launch.py --all
```

Chains: `build/merge.py` -> copy `dist/Ess.lua` to `<game>/scripts/OnLoad/1_Ess.lua` (byte-verified) and
add/update its `lua_loader.ini` `[OnLoad]` entry in place -> start (or reuse) an `xpad.py` server -> launch
the game -> bring its window to the foreground (SetForegroundWindow + a belt-and-suspenders center click,
since synthetic controller input goes wherever OS focus is and launching a process does NOT hand it focus)
-> an open-loop button macro: alternating START/A taps to clear the intro cutscene(s), one deliberate START
past the title screen (idling there starts a demo reel), one more to go from the default "Continue"
selection to the "play online?" prompt, then a final `--resolve-taps` burst of alternating A/START
(4 taps, 4s apart by default) to push past that prompt into an actual loaded game. Steps are also
available individually (`--build`/`--deploy`/`--controller`/`--launch`/`--skip-intro`), plus `--status`
(read-only) and `--stop-controller`. Full flag list in the script's own `--help`/docstring.

**CONFIRMED working end-to-end 2026-07-16** (after several rounds of live tuning with Logan watching the
screen — this tool has no visual feedback loop of its own, all timing is open-loop/fixed-delay): reaches
an actual loaded game from a cold launch, confirmed by `[Ess] v0.1.0 ready` appearing in
`lua_loader_printf.log`. Fixes that took iteration to find: (1) the game window needs OS focus or
synthetic input lands nowhere — launching a process doesn't give it focus by itself; (2) a fresh virtual
pad needs a settle delay before the game's own controller enumeration at boot, beyond what our own
liveness check confirms; (3) intro cutscenes don't all skip on the same button, so bursts alternate
START/A rather than mashing one; (4) the very first successful run actually sailed past the "play
online?" prompt into a real game by itself (generous timing + tolerance for over-presses), which is why
the sequence now deliberately keeps going with `--resolve-taps` instead of trying to stop exactly on that
one screen.

## `lua_repl.py` -- log-based live REPL into the running game

Rewritten 2026-07-16 from the docs-corpus original (`docs/mercs2-luacd/tools/lua_repl.py`, sibling repo)
after Logan flagged that version's `return`-over-socket handling as unreliable. The bridge's socket output
is genuinely one-execution-behind (it flushes chunk N's result on the NEXT connection), which the original
worked around with a fragile nonce+poll-with-flush-chunks dance. **This version has the chunk itself
Loader.Printf its result (tagged with a per-call nonce) to `lua_loader_printf.log`, and treats that log as
the authoritative result channel** — reading an append-only file has none of the socket's buffering
ambiguity. The socket is still used to send the code and to surface an immediate (but explicitly
advisory/possibly-stale) error signal.

```
python tools/lua_repl.py --code 'return Player.GetCash()'
python tools/lua_repl.py --file experiment.lua
python tools/lua_repl.py --probe                                   # is the bridge reachable?
python tools/lua_repl.py --log-size                                # byte offset -- record before launching
python tools/lua_repl.py --wait-log "[Ess]" --since-bytes N --wait-timeout 90   # block until OnLoad ran
```

**CONFIRMED end-to-end 2026-07-16**, against a real loaded game reached via `launch.py --all`:
- `return 1+1` -> `2` (basic round-trip).
- `Ess` confirmed loaded and reachable (`Ess.VERSION` read back correctly).
- **`Ess.Player.character(0) == Player.GetLocalCharacter()`** -> `true` — the flagship convenience
  function verified to return the EXACT same guid as the native call, not just "loads without error."
- A deliberately broken call correctly surfaced the real Lua traceback via the ERR-tagged path
  (`attempt to call global '...' (a nil value)`).
- **`Ess.RNG.new(1)` drew 3 real, varying values live in the actual 32-bit-float engine** — behavioral
  confirmation of the single most important hard-won fact in this whole project, not just reasoning about
  it offline.

Single-line results only (a `tostring()`'d value containing its own newline truncates at the first one) --
fine for scalars/coordinates, not for dumping a big table; nothing has needed more than that yet.

### Suggested next test: `Ess.Input.hijackController`

Have a probe script register `Ess.Input.hijackController` and log every event it receives, drive the
virtual pad's stick/buttons via `xpad.py`, then read the log back via `lua_repl.py` to confirm the hijack
actually receives real controller input (and that the "letters only while hijacked" caveat about the
underlying PDA claiming arrows holds up). This is the concrete next step flagged in `FEATURE_SHEET.md`'s
Implementation status section.
