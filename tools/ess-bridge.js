/* ess-bridge.js -- a tiny, dependency-free browser client for the Mercenaries 2 lua-bridge over WebSocket.
 * Connect straight from a web page to the live game -- no Python/relay -- once the bridge speaks WS
 * (see BRIDGE_WEBSOCKET.md for exactly what the bridge needs).
 *
 * WHY RESULTS WORK THE WAY THEY DO (read this -- it's the whole design):
 *   The bridge runs your Lua whenever the engine next drives its pump -- and the pump rides on the game's own
 *   (noop'd) native debug-print, which every stock script calls constantly, so chunks run promptly and
 *   reliably (it's been driven overnight at 200-300k executed calls/sec). What's NOT reliable is the DIRECT
 *   socket return -- it's one-execution-behind (buffering). So the robust channel is the LOG: Loader.Printf
 *   lines are ordered and unambiguous, and the bridge forwards them over WS as a live feed. This client,
 *   exactly like tools/lua_repl.py, WRAPS each chunk to Loader.Printf a nonce-tagged result and matches that
 *   tag on the stream -- reliable + ordered, and no correlation plumbing in the bridge's C (the id lives in
 *   Lua). Note it forwards Loader.Printf (the dedicated CLEAN log), not the game's spammy native print.
 *
 *   You get TWO signals per run():
 *     * ACK    -- the bridge received + queued your chunk (immediate, reliable).
 *     * RESULT -- the tagged log line came back. Reliable in practice (the pump fires constantly). If no line
 *                 arrives within resultTimeout, run() resolves with { timedOut:true } instead of hanging --
 *                 a rare safety net (a dropped/slow line), not the norm; the chunk almost certainly ran.
 *
 * USAGE
 *   const bridge = new EssBridge("ws://127.0.0.1:27050");
 *   bridge.onLog = (line) => appendToConsole(line);          // the LIVE game log feed
 *   bridge.onStatus = (s) => setDot(s);                      // "connecting" | "open" | "closed" | "error"
 *   await bridge.connect();
 *   const r = await bridge.run('return Ess.VERSION');        // { ok:true, value:"0.2.1", acked:true }
 *   bridge.run('Ess.Player.giveCash(100000)');               // fire-and-forget is fine (still resolves)
 *
 * Works in any browser (native WebSocket). In Node, pass an impl: new EssBridge(url, { WebSocketImpl: require('ws') }).
 */
(function (root) {
  "use strict";

  var _seq = 0;
  function nextId() { return "q" + (++_seq).toString(36) + Date.now().toString(36); }

  // Wrap user code so it prints a single, nonce-tagged result line. Mirrors tools/lua_repl.py's _wrap:
  // pcall the body, then Loader.Printf("<tag>OK\t<value>") or "<tag>ERR\t<error>". Single line only --
  // a tostring() with its own newline truncates at the first, fine for scalars / coords / short strings.
  function wrap(code, tag) {
    return "local __ok, __r = pcall(function()\n" + code + "\nend)\n" +
           "Loader.Printf('" + tag + "' .. (__ok and 'OK\\t' or 'ERR\\t') .. tostring(__r))\n";
  }

  function EssBridge(url, opts) {
    opts = opts || {};
    this.url = url || "ws://127.0.0.1:27050";
    this.resultTimeout = opts.resultTimeout || 8000;    // ms to wait for the tagged RESULT line
    this.autoReconnect = opts.autoReconnect !== false;  // default on
    this._WS = opts.WebSocketImpl || root.WebSocket;
    this.ws = null;
    this.state = "closed";
    this._pending = {};        // id -> { tag, resolve, timer, acked, onAck }
    this._reconnectDelay = 1000;
    this.onLog = opts.onLog || function () {};       // (line) live Loader.Printf feed (result lines filtered out)
    this.onStatus = opts.onStatus || function () {}; // (state)
  }

  EssBridge.prototype._set = function (s) { this.state = s; try { this.onStatus(s); } catch (e) {} };

  EssBridge.prototype.connect = function () {
    var self = this;
    return new Promise(function (resolve, reject) {
      if (!self._WS) { reject(new Error("no WebSocket implementation available")); return; }
      self._set("connecting");
      var ws;
      try { ws = new self._WS(self.url); } catch (e) { self._set("error"); reject(e); return; }
      self.ws = ws;
      ws.onopen = function () { self._reconnectDelay = 1000; self._set("open"); resolve(); };
      ws.onerror = function () { self._set("error"); /* onclose follows */ };
      ws.onclose = function () {
        self._set("closed");
        self._failAll("connection closed");
        if (self.autoReconnect) {
          setTimeout(function () { self.connect().catch(function () {}); }, self._reconnectDelay);
          self._reconnectDelay = Math.min(self._reconnectDelay * 1.7, 15000);
        }
      };
      ws.onmessage = function (ev) { self._onMessage(ev.data); };
    });
  };

  EssBridge.prototype.close = function () {
    this.autoReconnect = false;
    if (this.ws) { try { this.ws.close(); } catch (e) {} }
  };

  /* run(code, opts) -> Promise<{ ok, value, acked, timedOut, error? }>
   * Resolves on the tagged RESULT line, or after resultTimeout with { timedOut:true }. Always resolves
   * (never rejects) so fire-and-forget calls can't throw an unhandled rejection. */
  EssBridge.prototype.run = function (code, opts) {
    opts = opts || {};
    var self = this;
    return new Promise(function (resolve) {
      if (self.state !== "open" || !self.ws) { resolve({ ok: false, acked: false, error: "not connected" }); return; }
      var id = nextId();
      var tag = "<<<WSR:" + id + ">>>";
      var entry = { tag: tag, acked: false, onAck: opts.onAck || null, resolve: resolve };
      entry.timer = setTimeout(function () {
        delete self._pending[id];
        // no tagged line in the window -- rare (the pump fires constantly); the chunk most likely ran, the
        // line was just slow/lost. A never-hang safety net, not "it didn't execute".
        resolve({ ok: undefined, value: null, acked: entry.acked, timedOut: true });
      }, opts.resultTimeout || self.resultTimeout);
      self._pending[id] = entry;
      try { self.ws.send(JSON.stringify({ id: id, code: wrap(String(code), tag) })); }
      catch (e) { clearTimeout(entry.timer); delete self._pending[id]; resolve({ ok: false, acked: false, error: String(e) }); }
    });
  };

  EssBridge.prototype._onMessage = function (data) {
    var msg;
    try { msg = JSON.parse(data); } catch (e) { return; }   // ignore non-JSON control frames

    if (msg.type === "ack") {
      var e = this._pending[msg.id];
      if (e) { e.acked = (msg.status === "queued"); if (e.onAck) { try { e.onAck(msg); } catch (x) {} } }
      return;
    }

    if (msg.type === "log") {
      var line = msg.line == null ? "" : String(msg.line);
      // Is this line one of our tagged RESULT lines? If so, resolve that request and DON'T echo it as log.
      for (var id in this._pending) {
        var p = this._pending[id];
        var at = line.indexOf(p.tag);
        if (at !== -1) {
          var rest = line.slice(at + p.tag.length);
          var ok = rest.indexOf("OK\t") === 0;
          var value = rest.slice(rest.indexOf("\t") + 1);
          clearTimeout(p.timer); delete this._pending[id];
          p.resolve({ ok: ok, value: value, acked: true, timedOut: false });
          return;
        }
      }
      try { this.onLog(line); } catch (x) {}   // an ordinary game log line -> the live feed
      return;
    }
    // {type:"result"} (if a bridge also sends the direct return) is ignored here -- the log tag is authoritative.
  };

  EssBridge.prototype._failAll = function (why) {
    for (var id in this._pending) {
      var e = this._pending[id];
      clearTimeout(e.timer);
      e.resolve({ ok: false, value: null, acked: e.acked, timedOut: false, error: why });
    }
    this._pending = {};
  };

  root.EssBridge = EssBridge;
  if (typeof module !== "undefined" && module.exports) module.exports = EssBridge;
})(typeof self !== "undefined" ? self : this);
