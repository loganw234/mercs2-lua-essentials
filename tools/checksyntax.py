#!/usr/bin/env python3
"""tools/checksyntax.py -- compile every src/*.lua and the built dist/Ess.lua. Offline, no game needed.

WHY THIS EXISTS SEPARATELY FROM checkpure.py
checkpure runs the PURE subset (11 of 84 files) and actually executes them to assert behaviour. That is a
much stronger check where it applies, but it deliberately covers only files with no engine surface -- so a
syntax error anywhere in the other 73 is invisible to every offline gate the repo has. The first time it
would be noticed is a live load, and the failure mode there is the whole framework silently not loading.

This closes that gap the cheap way: COMPILE ONLY, never execute. Compiling needs no engine globals, no
stubs, and no game, because a chunk that references `Hud.Radar` is perfectly compilable -- the name is only
resolved when it RUNS. So every file can be checked, not just the pure ones.

Note on Lua versions: lupa embeds a modern Lua (5.4+) while the game is 5.1. That is fine for this purpose,
since Ess targets the 5.1 subset and nothing here uses syntax the two disagree on -- but it does mean this
validates SYNTAX, not 5.1 semantics. checkpure remains the behavioural gate, and the game remains the truth.

Usage: `python tools/checksyntax.py`  (exit 1 on any failure)
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
DIST = ROOT / "dist"


def main():
    try:
        import lupa
    except ImportError:
        print("[checksyntax] needs lupa: pip install lupa")
        return 1

    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    # `load` compiles and returns the chunk (or nil + message); it never runs it.
    #
    # Returning a single STRING on purpose -- "" for success, the message otherwise. Handing back `load`'s
    # own (function, error) pair looks tidier and does not work: on success that is one Lua function value,
    # and unpacking it Python-side raises "iteration is only supported for tables", which then reports every
    # file in the repo as a failure. A single string has no such ambiguity.
    compile_chunk = L.eval("""
        function(src, name)
            local fn, err = load(src, name)
            if fn then return "" end
            return tostring(err)
        end
    """)

    targets = sorted(SRC.glob("*.lua"))
    built = DIST / "Ess.lua"
    if built.exists():
        targets.append(built)

    failed = 0
    for p in targets:
        rel = p.relative_to(ROOT).as_posix()
        try:
            err = compile_chunk(p.read_text(encoding="utf-8"), "@" + rel)
        except Exception as e:                                   # a lupa-level problem, not a Lua one
            print("[FAIL] %-28s harness error: %s" % (rel, e))
            failed += 1
            continue
        if err:
            print("[FAIL] %-28s %s" % (rel, err))
            failed += 1

    n = len(targets)
    if failed:
        print("\n%d of %d file(s) FAILED to compile" % (failed, n))
        return 1
    print("[ok] %d file(s) compile cleanly (%d in src/, plus the built dist)" % (n, n - (1 if built.exists() else 0)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
