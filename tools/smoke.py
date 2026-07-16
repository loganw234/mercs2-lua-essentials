#!/usr/bin/env python3
"""tools/smoke.py -- run samples/recipes/*.lua as a pre-release smoke test.

Every recipe ends with a self-verifying `[SMOKE] <name>: PASS/FAIL` log line (name == the file's stem). This
reloads the CURRENT dist/Ess.lua into the running game (so you're testing exactly what you'd ship), runs every
recipe through the lua-bridge, then reads the game log and reports which recipes passed.

Requires the game running with the lua-bridge up (same as lua_repl.py) and dist/Ess.lua built (merge.py).

Usage: python tools/smoke.py
Exit code 0 iff every recipe reported PASS.
"""
import glob
import pathlib
import re
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
RECIPES = sorted(glob.glob(str(ROOT / "samples" / "recipes" / "*.lua")))
LUA_REPL = str(ROOT / "tools" / "lua_repl.py")
DIST = str(ROOT / "dist" / "Ess.lua")
LOG = r"C:\Games\Mercenaries 2 World in Flames\scripts\lua_loader_printf.log"


def bridge(args):
    subprocess.run([sys.executable, LUA_REPL] + args, capture_output=True)


def main():
    if not RECIPES:
        print("[smoke] no recipes found in samples/recipes/")
        return 2

    print("[smoke] reloading dist/Ess.lua (testing the current build) ...")
    bridge(["--file", DIST])
    time.sleep(0.5)

    # a unique marker so we only read THIS run's results out of the shared log
    marker = "SMOKE_RUN_%d" % int(time.time())
    bridge(["--code", 'Loader.Printf("[SMOKE] === %s ===")' % marker])

    names = []
    for path in RECIPES:
        name = pathlib.Path(path).stem
        names.append(name)
        print("[smoke] running %s ..." % name)
        bridge(["--file", path])
        time.sleep(0.3)

    time.sleep(4)  # let any delayed (timer/loop) PASSes land

    try:
        with open(LOG, "r", encoding="utf-8", errors="ignore") as f:
            text = f.read()
    except OSError as e:
        print("[smoke] can't read the game log: %s" % e)
        return 2

    idx = text.rfind(marker)  # only look at output after our marker
    if idx >= 0:
        text = text[idx:]

    results = {}
    for m in re.finditer(r"\[SMOKE\]\s+(\w+):\s+(PASS|FAIL)", text):
        results[m.group(1)] = m.group(2)  # last occurrence wins

    npass = nfail = nmiss = 0
    print("\n=== SMOKE TEST RESULTS ===")
    for name in names:
        r = results.get(name)
        if r == "PASS":
            npass += 1
            tag = "PASS"
        elif r == "FAIL":
            nfail += 1
            tag = "FAIL"
        else:
            nmiss += 1
            tag = "MISSING"
        print("  %-8s %s" % (tag, name))
    print("\n%d passed, %d failed, %d missing (of %d)" % (npass, nfail, nmiss, len(names)))
    return 0 if (nfail == 0 and nmiss == 0) else 1


if __name__ == "__main__":
    sys.exit(main())
