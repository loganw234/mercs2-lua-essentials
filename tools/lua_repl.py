#!/usr/bin/env python3
"""tools/lua_repl.py -- log-based headless REPL into the live Merc2 lua-bridge.

REWRITTEN 2026-07-16 from the docs-corpus original (docs/mercs2-luacd/tools/lua_repl.py). That version
read a chunk's `return` value back over the bridge's own TCP socket -- workable, but the bridge's socket
output is genuinely one-execution-behind (it flushes chunk N's result on the NEXT connection, after chunk
N+1 already queued), which needed a nonce + poll-with-flush-chunks workaround that was fragile in practice
(Logan: "may have had issues with improperly reading returns").

THIS VERSION instead has the chunk itself write its result to lua_loader_printf.log via Loader.Printf
(tagged with a per-call random nonce so concurrent/rapid calls can't cross-read each other's answer), and
treats the LOG as the authoritative result channel -- reading a plain append-only file has none of the
socket's buffering ambiguity. The socket is still used to actually SEND the code (that part was never the
problem) and whatever comes back on it immediately is still surfaced, but purely as an ADVISORY,
possibly-stale error signal -- never as the source of the actual return value.

FEEDBACK CHANNELS
  * Result: read back from lua_loader_printf.log (this is `value` / what gets printed as OK/ERROR).
  * A Lua-side pcall failure inside your own code surfaces the same way, tagged ERR instead of OK.
  * Whatever the socket itself returned immediately is also reported, labeled advisory/possibly-stale --
    genuine send/connect failures are NOT advisory, those are a hard failure (bridge unreachable).
  * Loader.Printf calls INSIDE your own code land in the same log, interleaved with everything else
    currently running -- they are NOT captured as "the result", only this wrapper's own tagged line is.

USAGE
  python tools/lua_repl.py --code 'return Player.GetCash()'
  python tools/lua_repl.py --file experiment.lua
  echo 'return 1+1' | python tools/lua_repl.py
  python tools/lua_repl.py --probe                          # just check whether the bridge is reachable
  python tools/lua_repl.py --log-size                       # print the log's current byte size -- record
                                                             # this BEFORE launching the game, then pass it
                                                             # as --since-bytes to --wait-log afterward.
                                                             # (safe even if the game truncates the log on
                                                             # launch -- both poll functions detect a
                                                             # shrunk file and treat it as starting fresh)
  python tools/lua_repl.py --wait-log "[Ess]" --since-bytes 12345 --wait-timeout 90
                                                             # block until TEXT appears in NEW log content
                                                             # (or timeout) -- e.g. confirm OnLoad actually
                                                             # ran before sending your first real command

PROTOCOL: send `<chunk>\\n<<<RUN>>>\\n` on 127.0.0.1:27050 (per lua_bridge's BridgeServerThread); your code
runs wrapped in `pcall` so its `return` value (or the error) gets Loader.Printf'd with a nonce tag, then
this tool polls the log for that tag. Single-line results only -- a `tostring()`'d value containing its
own newline truncates at the first one; fine for scalars/coordinates, not for dumping big tables.
"""
import argparse
import pathlib
import random
import socket
import sys
import time

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 27050
DEFAULT_GAME_DIR = pathlib.Path(r"C:\Games\Mercenaries 2 World in Flames")
SENTINEL = "<<<RUN>>>"
END_MARKER = "<<<END>>>"


def _log_path(game_dir):
    return pathlib.Path(game_dir) / "scripts" / "lua_loader_printf.log"


def log_size(game_dir):
    p = _log_path(game_dir)
    return p.stat().st_size if p.exists() else 0


def _wrap(code, tag_ok, tag_err):
    return (
        "local __ok, __result = pcall(function()\n"
        + code + "\n"
        + "end)\n"
        + "if __ok then Loader.Printf('" + tag_ok + "' .. tostring(__result)) "
        + "else Loader.Printf('" + tag_err + "' .. tostring(__result)) end\n"
    )


def _send_raw(host, port, wrapped, connect_timeout=5.0, read_timeout=2.0):
    """Fire `wrapped` into the bridge. Returns (ok, advisory_text). advisory_text is whatever (if
    anything) came back on THIS connection -- per the bridge's one-execution-behind buffering this may
    be stale (a PREVIOUS command's leftovers), so it's surfaced as advisory only, never trusted as this
    command's actual result (the log poll is authoritative for that)."""
    try:
        s = socket.create_connection((host, port), timeout=connect_timeout)
    except OSError as e:
        return False, ("bridge not reachable at %s:%d (%s) -- is the game running with lua-bridge loaded?"
                        % (host, port, e))
    s.settimeout(read_timeout)
    try:
        s.sendall((wrapped.rstrip("\n") + "\n" + SENTINEL + "\n").encode("utf-8"))
        buf = ""
        deadline = time.monotonic() + read_timeout
        while time.monotonic() < deadline:
            try:
                chunk = s.recv(4096)
            except socket.timeout:
                break
            if not chunk:
                break
            buf += chunk.decode("utf-8", errors="replace")
            if END_MARKER in buf:
                buf = buf.split(END_MARKER, 1)[0]
                break
        return True, buf.strip()
    finally:
        try:
            s.close()
        except OSError:
            pass


def _poll_log(game_dir, tag_ok, tag_err, since_bytes, timeout):
    p = _log_path(game_dir)
    deadline = time.monotonic() + timeout
    while True:
        if p.exists():
            if p.stat().st_size < since_bytes:
                # The game truncates/resets this log on a fresh launch. If since_bytes was recorded
                # against a PRIOR session's (longer) log, seeking to it in the new, shorter file would
                # silently read nothing forever -- so a shrunk file means "treat as new file, from 0".
                since_bytes = 0
            with open(p, "r", encoding="utf-8", errors="replace") as f:
                f.seek(since_bytes)
                new_text = f.read()
            for tag, is_ok in ((tag_ok, True), (tag_err, False)):
                i = new_text.find(tag)
                if i != -1:
                    start = i + len(tag)
                    end = new_text.find("\n", start)
                    value = new_text[start:end if end != -1 else None]
                    return is_ok, value.rstrip("\r")
        if time.monotonic() >= deadline:
            return None, None
        time.sleep(0.15)


def probe(host, port):
    try:
        socket.create_connection((host, port), timeout=1.0).close()
        return True
    except OSError:
        return False


def execute(host, port, game_dir, code, timeout=15.0):
    """Run `code` in the live game. Returns a dict:
        {"sent": bool, "log_ok": True/False/None, "value": str|None, "advisory": str|None, "error": str|None}
    log_ok is None if the log never showed our tag within `timeout` (bridge down, chunk hung, or a
    load-time error before Loader itself was reachable)."""
    nonce = "R%06d" % random.randint(100000, 999999)
    tag_ok, tag_err = "<<<REPL %s OK>>>" % nonce, "<<<REPL %s ERR>>>" % nonce
    since = log_size(game_dir)
    wrapped = _wrap(code, tag_ok, tag_err)
    sent, advisory = _send_raw(host, port, wrapped)
    if not sent:
        return {"sent": False, "log_ok": None, "value": None, "advisory": None, "error": advisory}
    log_ok, value = _poll_log(game_dir, tag_ok, tag_err, since, timeout)
    return {"sent": True, "log_ok": log_ok, "value": value, "advisory": advisory or None, "error": None}


def wait_log(game_dir, text, since_bytes, timeout):
    p = _log_path(game_dir)
    deadline = time.monotonic() + timeout
    while True:
        if p.exists():
            if p.stat().st_size < since_bytes:
                # see comment in _poll_log -- a fresh launch truncates this log, so a stale offset
                # from before the (re)launch must be treated as "start of a new file", not honored as-is.
                since_bytes = 0
            with open(p, "r", encoding="utf-8", errors="replace") as f:
                f.seek(since_bytes)
                new_text = f.read()
            if text in new_text:
                return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(0.25)


def read_source(code, file, stdin_ok):
    if code is not None:
        return code
    if file:
        with open(file, "r", encoding="utf-8") as f:
            return f.read()
    if stdin_ok and not sys.stdin.isatty():
        data = sys.stdin.read()
        if data.strip():
            return data
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--code", help="inline Lua chunk to run")
    ap.add_argument("--file", help="Lua file to run")
    ap.add_argument("--game-dir", default=str(DEFAULT_GAME_DIR))
    ap.add_argument("--host", default=DEFAULT_HOST)
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--timeout", type=float, default=15.0, help="seconds to wait for the log-tagged result")
    ap.add_argument("--probe", action="store_true", help="just check whether the bridge is reachable")
    ap.add_argument("--log-size", action="store_true", help="print the log's current byte size and exit")
    ap.add_argument("--wait-log", metavar="TEXT", help="block until TEXT appears in the log, then exit")
    ap.add_argument("--since-bytes", type=int, default=0, help="only consider log content written after this byte offset")
    ap.add_argument("--wait-timeout", type=float, default=60.0)
    args = ap.parse_args()

    if args.probe:
        up = probe(args.host, args.port)
        print("[lua_repl] bridge %s:%d is %s" % (args.host, args.port, "UP" if up else "DOWN"))
        sys.exit(0 if up else 2)

    if args.log_size:
        print(log_size(args.game_dir))
        sys.exit(0)

    if args.wait_log is not None:
        print("[lua_repl] waiting up to %.0fs for %r in the log (since byte %d)..." % (
            args.wait_timeout, args.wait_log, args.since_bytes))
        found = wait_log(args.game_dir, args.wait_log, args.since_bytes, args.wait_timeout)
        print("[lua_repl] " + ("FOUND" if found else "TIMED OUT, not seen"))
        sys.exit(0 if found else 2)

    code = read_source(args.code, args.file, stdin_ok=True)
    if code is None:
        up = probe(args.host, args.port)
        print("[lua_repl] no code given. bridge %s:%d is %s." % (
            args.host, args.port, "UP" if up else "DOWN"))
        print("[lua_repl] pass --code '<lua>', --file <path>, --probe, --log-size, or --wait-log <text>.")
        sys.exit(0 if up else 2)

    result = execute(args.host, args.port, args.game_dir, code, args.timeout)
    if not result["sent"]:
        print("[lua_repl] SEND FAILED: " + result["error"])
        sys.exit(2)
    if result["log_ok"] is None:
        print("[lua_repl] TIMEOUT: chunk sent, but no tagged result appeared in the log within %.0fs" % args.timeout)
        if result["advisory"]:
            print("[lua_repl] (advisory, possibly stale, socket text: %s)" % result["advisory"])
        sys.exit(2)
    if result["log_ok"]:
        print("[lua_repl] OK: " + (result["value"] if result["value"] is not None else ""))
    else:
        print("[lua_repl] ERROR: " + (result["value"] if result["value"] is not None else ""))
    if result["advisory"]:
        low = result["advisory"].lower()
        if "error" in low or "attempt to" in low:
            print("[lua_repl] (advisory socket text ALSO looked error-like -- possibly a different/stale "
                  "exchange, not necessarily this command: %s)" % result["advisory"])
    sys.exit(0 if result["log_ok"] else 1)


if __name__ == "__main__":
    main()
