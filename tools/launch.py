#!/usr/bin/env python3
"""tools/launch.py -- build -> deploy -> launch -> skip-intro, one tool.

Chains together everything needed to go from "I edited src/*.lua" to "the game is sitting at the
'play online?' prompt with the new build loaded and a virtual controller ready to drive it":

    python tools/launch.py --all

...which is exactly `--build --deploy --controller --launch --skip-intro` in that order. Each step
is also available individually (e.g. `--deploy` alone after a manual edit-test loop where you don't want
to relaunch the game every time).

STEPS
  --build            run build/merge.py -> dist/Ess.lua
  --deploy           copy dist/Ess.lua -> <game>/scripts/OnLoad/1_Ess.lua (byte-verified), and ensure
                      lua_loader.ini has an [OnLoad] entry for it (added/updated in place -- the file's
                      existing header comments and any other sections/entries are left untouched)
  --controller       make sure a virtual X360 pad is connected (reuses an already-running tools/xpad.py
                      server if one answers on --port, else starts a fresh detached one, then waits
                      --controller-settle seconds -- our own liveness check only confirms the Python-side
                      pad object exists, not that Windows' XInput slot assignment has fully settled).
                      MUST happen before --launch -- Mercenaries 2 only detects a controller that was
                      already present at process start; plugging one in afterward is never picked up.
  --launch           start <game>/Mercenaries2.exe (detached -- keeps running after this script exits)
  --skip-intro       requires --launch in the SAME run (needs the game's PID to focus its window -- see
                     below). An OPEN-LOOP (fixed-delay, not state-checked) sequence: bring the game window
                     to the foreground (SetForegroundWindow + an Alt-tap to defeat Windows' foreground
                     lock, PLUS a belt-and-suspenders click at the window's center -- synthetic controller
                     input goes wherever OS focus is, and launching a process does NOT hand it focus by
                     itself), tap START/A alternating several times to clear the intro cutscene(s) (not
                     fully certain a single button covers every skip prompt), re-focus, one
                     deliberate START to clear the title screen (idling there starts a demo reel -- don't
                     wait long), re-focus, wait for the main menu, one more deliberate START to go from the
                     default "Continue" selection to the "play online?" prompt, then STOP (deliberately --
                     the default choice on that prompt isn't confirmed yet, so this macro never resolves
                     it). Tune the --*-wait / --cutscene-* flags below if actual timing on your machine
                     differs.
  --all              the whole chain, in order
  --stop-controller  tell a running xpad server to disconnect the virtual pad and exit
  --status           report what's currently true (built? deployed+matching? controller up? game running?)
                      and exit -- takes no other action

CAVEAT: this script has NO visual feedback loop -- it can't see the screen, so --skip-intro is timed
open-loop. It reports what IT did (commands sent, process still alive or not); it can't confirm the game
actually reached the intended screen. Watch the game window (or ask a second pass to check) and adjust
the timing flags if the sequence lands early/late.

Usage examples:
    python tools/launch.py --all
    python tools/launch.py --build --deploy
    python tools/launch.py --status
    python tools/launch.py --stop-controller
"""
import argparse
import ctypes
from ctypes import wintypes
import pathlib
import re
import subprocess
import shutil
import sys
import time

user32 = ctypes.windll.user32

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS_DIR = pathlib.Path(__file__).resolve().parent
DIST = REPO_ROOT / "dist" / "Ess.lua"
DEFAULT_GAME_DIR = pathlib.Path(r"C:\Games\Mercenaries 2 World in Flames")
EXE_NAME = "Mercenaries2.exe"
DEPLOY_NAME = "1_Ess.lua"
DEPLOY_PRIORITY = 5  # lowest number loads first; leaves room below for anything that must load even earlier

sys.path.insert(0, str(TOOLS_DIR))
import xpad  # noqa: E402  (same tools/ directory)


# ============================================================
# Window focus. Synthetic XInput/controller events go to whichever window has OS focus -- launching the
# game does NOT give it focus by itself (it can land behind this terminal), so every button tap before
# this was fixed was landing nowhere. Two layers, per Logan: try to properly foreground the window, AND
# (belt-and-suspenders) click its center regardless of whether the foreground call reports success.
# ============================================================
_ENUM_PROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)


def _find_window_for_pid(pid):
    found = []

    def cb(hwnd, _lparam):
        if not user32.IsWindowVisible(hwnd):
            return True
        wpid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(wpid))
        if wpid.value == pid and user32.GetWindowTextLengthW(hwnd) > 0:
            found.append(hwnd)
        return True

    user32.EnumWindows(_ENUM_PROC(cb), 0)
    return found[0] if found else None


def _find_window_by_title(substr):
    found = []

    def cb(hwnd, _lparam):
        if not user32.IsWindowVisible(hwnd):
            return True
        length = user32.GetWindowTextLengthW(hwnd)
        if length > 0:
            buf = ctypes.create_unicode_buffer(length + 1)
            user32.GetWindowTextW(hwnd, buf, length + 1)
            if substr.lower() in buf.value.lower():
                found.append(hwnd)
        return True

    user32.EnumWindows(_ENUM_PROC(cb), 0)
    return found[0] if found else None


def focus_game_window(pid, title_hint="Mercenaries"):
    hwnd = _find_window_for_pid(pid) or _find_window_by_title(title_hint)
    if not hwnd:
        print("[launch] focus: couldn't find the game window yet (will still try a blind center click)")
    else:
        SW_RESTORE = 9
        user32.ShowWindow(hwnd, SW_RESTORE)
        # Windows' foreground-lock sometimes refuses SetForegroundWindow from a background process;
        # a harmless bare Alt tap (never meaningfully processed by the target app) satisfies the check
        # Windows uses to decide "the user is actively interacting" and unblocks it.
        VK_MENU, KEYEVENTF_KEYUP = 0x12, 0x0002
        user32.keybd_event(VK_MENU, 0, 0, 0)
        user32.keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, 0)
        if user32.SetForegroundWindow(hwnd):
            print("[launch] focus: brought the game window to the foreground")
        else:
            print("[launch] focus: SetForegroundWindow reported failure, will still try a center click")

    # belt-and-suspenders: click the center of the window (or the primary screen, if we never found a
    # window handle at all) regardless of whether the foreground call above reported success.
    rect = wintypes.RECT()
    if hwnd and user32.GetWindowRect(hwnd, ctypes.byref(rect)):
        cx, cy = (rect.left + rect.right) // 2, (rect.top + rect.bottom) // 2
    else:
        cx = user32.GetSystemMetrics(0) // 2   # SM_CXSCREEN
        cy = user32.GetSystemMetrics(1) // 2   # SM_CYSCREEN
    user32.SetCursorPos(cx, cy)
    MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP = 0x0002, 0x0004
    user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
    time.sleep(0.05)
    user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
    print(f"[launch] focus: clicked ({cx},{cy})")


def _run(cmd):
    r = subprocess.run(cmd)
    return r.returncode == 0


def build():
    print("[launch] build: running build/merge.py")
    if not _run([sys.executable, str(REPO_ROOT / "build" / "merge.py")]):
        print("[launch] build FAILED")
        sys.exit(1)


def _ensure_loader_ini(game_dir):
    """Add/update an [OnLoad] entry for DEPLOY_NAME in lua_loader.ini WITHOUT disturbing anything else
    already in the file (its header comments, other sections, other entries)."""
    ini_path = game_dir / "scripts" / "lua_loader.ini"
    lines = ini_path.read_text(encoding="utf-8", errors="ignore").splitlines() if ini_path.exists() else []

    section_re = re.compile(r"^\s*\[(.+?)\]\s*$")
    key_re = re.compile(r"^\s*([^=;]+?)\s*=")

    onload_start, onload_end = None, len(lines)
    for i, line in enumerate(lines):
        m = section_re.match(line)
        if m:
            if onload_start is not None:
                onload_end = i
                break
            if m.group(1).strip() == "OnLoad":
                onload_start = i

    entry = f"{DEPLOY_NAME}={DEPLOY_PRIORITY}"
    if onload_start is None:
        if lines and lines[-1].strip() != "":
            lines.append("")
        lines.append("[OnLoad]")
        lines.append(entry)
    else:
        found = False
        for i in range(onload_start + 1, onload_end):
            m = key_re.match(lines[i])
            if m and m.group(1).strip() == DEPLOY_NAME:
                lines[i] = entry
                found = True
                break
        if not found:
            lines.insert(onload_start + 1, entry)

    ini_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[launch] lua_loader.ini: ensured [OnLoad] {entry}")


def deploy(game_dir):
    if not DIST.exists():
        print("[launch] deploy FAILED: dist/Ess.lua doesn't exist -- run with --build first")
        sys.exit(1)
    onload = game_dir / "scripts" / "OnLoad"
    onload.mkdir(parents=True, exist_ok=True)
    target = onload / DEPLOY_NAME
    shutil.copyfile(DIST, target)
    src_size, dst_size = DIST.stat().st_size, target.stat().st_size
    if src_size != dst_size:
        print(f"[launch] deploy FAILED: size mismatch ({src_size} vs {dst_size})")
        sys.exit(1)
    print(f"[launch] deploy: {target} ({dst_size} bytes, verified)")
    _ensure_loader_ini(game_dir)


def _xpad_alive(port):
    try:
        return xpad.send(["PING"], port) == "PONG"
    except Exception:
        return False


def start_controller(port, settle=2.0):
    if _xpad_alive(port):
        print(f"[launch] controller: already up on port {port}, reusing it")
        return
    print(f"[launch] controller: starting a new xpad server on port {port} (detached)")
    subprocess.Popen(
        [sys.executable, str(TOOLS_DIR / "xpad.py"), "serve", "--port", str(port)],
        creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP,
    )
    for _ in range(20):
        time.sleep(0.25)
        if _xpad_alive(port):
            print("[launch] controller: up and responding")
            # Our own PING only confirms the Python-side VX360Gamepad object exists -- it does NOT
            # confirm Windows' XInput slot assignment has fully settled. Give the OS a moment before a
            # freshly-launching game does its own controller enumeration at boot (Logan, 2026-07-16).
            print(f"[launch] controller: settling {settle}s before launching the game")
            time.sleep(settle)
            return
    print("[launch] controller: WARNING -- no response after 5s, continuing anyway")


def stop_controller(port):
    if not _xpad_alive(port):
        print("[launch] controller: nothing running")
        return
    xpad.send(["QUIT"], port)
    print("[launch] controller: stopped")


def launch(game_dir):
    exe = game_dir / EXE_NAME
    if not exe.exists():
        print(f"[launch] FAILED: {exe} not found")
        sys.exit(1)
    print(f"[launch] starting {exe}")
    return subprocess.Popen(
        [str(exe)], cwd=str(game_dir),
        creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP,
    )


def skip_intro(pid, port, focus_wait, boot_wait, cutscene_taps, cutscene_gap, title_wait, menu_wait):
    print(f"[launch] skip-intro: waiting {focus_wait}s for the game window to appear")
    time.sleep(focus_wait)
    focus_game_window(pid)
    remaining = max(0.0, boot_wait - focus_wait)
    print(f"[launch] skip-intro: waiting {remaining}s more for the game to finish booting")
    time.sleep(remaining)

    print(f"[launch] skip-intro: tapping START/A (alternating) x{cutscene_taps} to clear the intro "
          "cutscene(s) -- Logan wasn't 100% sure a plain START-mash covers every skip prompt, and "
          "over-presses are tolerated here regardless of which button")
    burst_buttons = ["START", "A"]
    for i in range(cutscene_taps):
        xpad.send(["TAP", burst_buttons[i % 2], "0.1"], port)
        time.sleep(cutscene_gap)

    print(f"[launch] skip-intro: waiting {title_wait}s, then ONE deliberate START to clear the title "
          "screen (kept short -- idling here starts a demo reel)")
    time.sleep(title_wait)
    focus_game_window(pid)
    xpad.send(["TAP", "START", "0.1"], port)

    print(f"[launch] skip-intro: waiting {menu_wait}s for the main menu (default selection = Continue), "
          "then ONE START to reach the 'play online?' prompt")
    time.sleep(menu_wait)
    focus_game_window(pid)
    xpad.send(["TAP", "START", "0.1"], port)
    print("[launch] skip-intro: at the 'play online?' prompt -- stopping here on purpose "
          "(default choice not yet confirmed); sequence complete")


def status(game_dir, port):
    print(f"[launch] dist/Ess.lua built:    {'yes' if DIST.exists() else 'no'}")
    target = game_dir / "scripts" / "OnLoad" / DEPLOY_NAME
    if DIST.exists() and target.exists():
        matches = DIST.stat().st_size == target.stat().st_size
        print(f"[launch] deployed at target:   yes ({'size matches build' if matches else 'SIZE MISMATCH -- redeploy'})")
    else:
        print(f"[launch] deployed at target:   no ({target})")
    print(f"[launch] controller server up: {'yes' if _xpad_alive(port) else 'no'} (port {port})")
    exe = game_dir / EXE_NAME
    running = False
    try:
        out = subprocess.run(["tasklist", "/FI", f"IMAGENAME eq {EXE_NAME}"], capture_output=True, text=True)
        running = EXE_NAME.lower() in out.stdout.lower()
    except Exception:
        pass
    print(f"[launch] game process running:  {'yes' if running else 'no'} ({exe})")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game-dir", default=str(DEFAULT_GAME_DIR))
    ap.add_argument("--port", type=int, default=xpad.DEFAULT_PORT)
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--deploy", action="store_true")
    ap.add_argument("--controller", action="store_true")
    ap.add_argument("--launch", action="store_true")
    ap.add_argument("--skip-intro", action="store_true")
    ap.add_argument("--all", action="store_true", help="build + deploy + controller + launch + skip-intro")
    ap.add_argument("--stop-controller", action="store_true")
    ap.add_argument("--status", action="store_true")
    ap.add_argument("--controller-settle", type=float, default=1.6, help="seconds to let a freshly-started virtual pad settle before launching the game")
    ap.add_argument("--focus-wait", type=float, default=2.4, help="seconds after launch before first trying to focus the game window")
    ap.add_argument("--boot-wait", type=float, default=12.0, help="seconds after launch before the first START tap (must be >= --focus-wait)")
    ap.add_argument("--cutscene-taps", type=int, default=6)
    ap.add_argument("--cutscene-gap", type=float, default=4.8, help="seconds between cutscene-skip taps (give the engine time to actually transition between scenes)")
    ap.add_argument("--title-wait", type=float, default=2.4, help="seconds to wait at the title screen before tapping past it")
    ap.add_argument("--menu-wait", type=float, default=3.2, help="seconds to wait for the main menu before the final tap")
    args = ap.parse_args()

    game_dir = pathlib.Path(args.game_dir)

    if args.status:
        status(game_dir, args.port)
        return
    if args.stop_controller:
        stop_controller(args.port)
        return

    do_build = args.build or args.all
    do_deploy = args.deploy or args.all
    do_controller = args.controller or args.all
    do_launch = args.launch or args.all
    do_skip = args.skip_intro or args.all

    if not any([do_build, do_deploy, do_controller, do_launch, do_skip]):
        ap.print_help()
        return

    if do_build:
        build()
    if do_deploy:
        deploy(game_dir)
    if do_controller:
        start_controller(args.port, args.controller_settle)

    proc = launch(game_dir) if do_launch else None

    if do_skip:
        if proc is None:
            print("[launch] skip-intro FAILED: no --launch in this run, so there's no known game PID to focus")
            sys.exit(1)
        skip_intro(proc.pid, args.port, args.focus_wait, args.boot_wait, args.cutscene_taps,
                   args.cutscene_gap, args.title_wait, args.menu_wait)

    if proc is not None:
        code = proc.poll()
        if code is None:
            print("[launch] game process is still running")
        else:
            print(f"[launch] WARNING: game process already exited (code {code}) -- something went wrong")

    print("[launch] done")


if __name__ == "__main__":
    main()
