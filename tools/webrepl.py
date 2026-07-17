#!/usr/bin/env python3
"""tools/webrepl.py -- serve a browser "mod page" that drives the LIVE game through Ess.

Browsers can't open a raw TCP socket, and the Merc2 lua-bridge is raw TCP on 127.0.0.1:27050. So this is a
tiny LOCAL relay: it serves webrepl.html and exposes POST /exec, which forwards a Lua snippet to the bridge
and reads the result back exactly the way tools/lua_repl.py does (log-tagged, authoritative). Open the page
in a browser and click buttons / type `Ess.*` calls -- they run in the running game, live.

    python tools/webrepl.py
    python tools/webrepl.py --web-port 9000 --game-dir "C:/Games/Mercenaries 2 World in Flames"

Then open http://127.0.0.1:8770 while the game is running with Ess (dist/Ess.lua) + the lua-bridge loaded.

SECURITY: binds to 127.0.0.1 ONLY. It executes arbitrary Lua in your game -- never expose it on a public
interface. This is a local dev tool.
"""
import argparse
import json
import os
import pathlib
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# reuse the exact send/poll protocol from the REPL rather than re-deriving it
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lua_repl  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
HTML = HERE / "webrepl.html"


class Handler(BaseHTTPRequestHandler):
    # injected by main()
    bridge_host = lua_repl.DEFAULT_HOST
    bridge_port = lua_repl.DEFAULT_PORT
    game_dir = str(lua_repl.DEFAULT_GAME_DIR)

    def _send(self, code, body, ctype="application/json"):
        b = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            try:
                self._send(200, HTML.read_text(encoding="utf-8"), "text/html; charset=utf-8")
            except OSError:
                self._send(500, "webrepl.html not found next to webrepl.py")
        elif self.path == "/probe":
            self._send(200, json.dumps({"up": lua_repl.probe(self.bridge_host, self.bridge_port)}))
        else:
            self._send(404, json.dumps({"error": "not found"}))

    def do_POST(self):
        if self.path != "/exec":
            self._send(404, json.dumps({"error": "not found"}))
            return
        try:
            n = int(self.headers.get("Content-Length", 0))
            code = json.loads(self.rfile.read(n).decode("utf-8")).get("code", "")
        except Exception as e:
            self._send(400, json.dumps({"error": "bad request: %s" % e}))
            return
        if not code.strip():
            self._send(400, json.dumps({"error": "empty code"}))
            return
        r = lua_repl.execute(self.bridge_host, self.bridge_port, self.game_dir, code)
        if not r["sent"]:
            out = {"ok": False, "error": r["error"] or "bridge unreachable"}
        elif r["log_ok"] is None:
            out = {"ok": False, "error": "timeout -- no result from the game (is Ess loaded + bridge up?)"}
        else:
            out = {"ok": bool(r["log_ok"]), "value": r["value"]}
            if not r["log_ok"]:
                out["error"] = r["value"]
        self._send(200, json.dumps(out))

    def log_message(self, *a):   # keep the console quiet
        pass


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--web-port", type=int, default=8770, help="port to serve the page on (default 8770)")
    ap.add_argument("--host", default=lua_repl.DEFAULT_HOST, help="lua-bridge host (default 127.0.0.1)")
    ap.add_argument("--port", type=int, default=lua_repl.DEFAULT_PORT, help="lua-bridge port (default 27050)")
    ap.add_argument("--game-dir", default=str(lua_repl.DEFAULT_GAME_DIR), help="game folder (holds the result log)")
    args = ap.parse_args()

    Handler.bridge_host, Handler.bridge_port, Handler.game_dir = args.host, args.port, args.game_dir
    srv = ThreadingHTTPServer(("127.0.0.1", args.web_port), Handler)
    print("[webrepl] serving  http://127.0.0.1:%d" % args.web_port)
    print("[webrepl] bridge   %s:%d   (game-dir: %s)" % (args.host, args.port, args.game_dir))
    print("[webrepl] open that URL in a browser with the game running. Ctrl+C to stop.")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n[webrepl] bye")


if __name__ == "__main__":
    main()
