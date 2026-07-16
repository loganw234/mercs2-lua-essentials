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
commands round-tripping correctly including a bad-button error case, clean QUIT) on 2026-07-16 --
**not yet exercised against the live game**, since that needs the game launched with the server already
up per the quirk above.

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
selection to the "play online?" prompt, then stop. Steps are also available individually
(`--build`/`--deploy`/`--controller`/`--launch`/`--skip-intro`), plus `--status` (read-only) and
`--stop-controller`. Full flag list in the script's own `--help`/docstring.

**CONFIRMED working end-to-end 2026-07-16** (after two rounds of live tuning with Logan watching the
screen — this tool has no visual feedback loop of its own, all timing is open-loop/fixed-delay): reached
the "play online?" prompt from a cold launch, and `lua_loader_printf.log` showed `[Ess] v0.1.0 ready` —
real in-engine confirmation the deploy pipeline works, not just a `loadcheck.py` pass. Fixes that took two
iterations to find: (1) the game window needs OS focus or synthetic input lands nowhere — launching a
process doesn't give it focus by itself; (2) a fresh virtual pad needs a settle delay before the game's
own controller enumeration at boot, beyond what our own liveness check confirms; (3) intro cutscenes
apparently don't all skip on the same button, so the burst alternates START/A rather than mashing one.

### Suggested next test: `Ess.Input.hijackController`

Combine this with `docs/mercs2-luacd/tools/lua_repl.py` (the live Lua bridge, TCP 127.0.0.1:27050, in the
sibling docs corpus): have a probe script register `Ess.Input.hijackController` and log every event it
receives, drive the virtual pad's stick/buttons via `xpad.py`, then read the log back over the REPL to
confirm the hijack actually receives real controller input (and that the "letters only while hijacked"
caveat about the underlying PDA claiming arrows holds up). This is the concrete next step flagged in
`FEATURE_SHEET.md`'s Implementation status section.
