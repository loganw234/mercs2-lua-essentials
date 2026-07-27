/* tools/test_bridge_client.js -- verify ess-bridge.js's WebSocket RESULT HANDLING end-to-end, with no game.
 * Run: `node tools/test_bridge_client.js`
 *
 * WHY THIS EXISTS
 * The result path crosses four representations, and a mistake in any one of them fails silently rather than
 * loudly -- the client's own `JSON.parse` sits inside a `catch { return; }`, so a malformed frame is DROPPED,
 * not reported, and `run()` just times out looking like "the chunk didn't execute". That is the worst possible
 * failure mode to debug from the outside, so it gets a test that models every hop:
 *
 *   1. the client wraps user code           -> Lua source containing our tag + separator
 *   2. Lua runs it and calls Loader.WsSend  -> one Lua string with a REAL TAB byte in it
 *   3. the bridge JSON-escapes that line    -> js_escape_into(), reimplemented faithfully below
 *   4. the frame arrives as JSON text       -> {"type":"ws","line":"...\t..."}
 *   5. the client parses and resolves       -> { ok, value }
 *
 * Hop 3 is the load-bearing one and the reason this file exists: a raw tab byte inside a JSON string is
 * INVALID JSON. If the bridge ever stopped escaping it, every successful result would vanish into that catch.
 * The escaper here is a line-for-line port of the C so the test fails if the two ever disagree.
 *
 * Source of truth for the wire contract (read, not guessed):
 *   Merc2-Mods-Exp/mods/lua-bridge-DEV/lua_bridge_DEV.c -- ws_broadcast_typed_line / js_escape_into /
 *   LuaLoaderWsSend, and the "Wire contract" comment block above the WebSocket section.
 */
"use strict";
const path = require("path");
const EssBridge = require(path.resolve(__dirname, "ess-bridge.js"));

let failures = 0;
function check(label, cond, detail) {
  if (cond) return;
  failures++;
  console.log("  [FAIL] " + label + (detail === undefined ? "" : "  -- " + JSON.stringify(detail)));
}

// ---- faithful port of the bridge's js_escape_into() -------------------------------------------------------
// Anything below 0x20 that isn't one of the named escapes becomes \u00xx. Everything else passes through.
function jsEscape(s) {
  let out = "";
  for (const ch of String(s)) {
    const c = ch.codePointAt(0);
    if (ch === "\\" || ch === '"') out += "\\" + ch;
    else if (ch === "\n") out += "\\n";
    else if (ch === "\r") out += "\\r";
    else if (ch === "\t") out += "\\t";
    else if (ch === "\b") out += "\\b";
    else if (ch === "\f") out += "\\f";
    else if (c < 0x20) out += "\\u" + c.toString(16).padStart(4, "0");
    else out += ch;
  }
  return out;
}

// ---- a stand-in bridge -----------------------------------------------------------------------------------
// Behaves like the real one: acks the chunk, then "runs" the Lua by interpreting only what our own wrapper
// emits, and broadcasts the result through the same JSON envelope the C builds.
function makeFakeBridge(opts) {
  opts = opts || {};
  class FakeWS {
    constructor() {
      this.sent = [];
      FakeWS.last = this;
      setTimeout(() => this.onopen && this.onopen(), 0);
    }
    send(raw) {
      this.sent.push(raw);
      const msg = JSON.parse(raw);
      // ACK, exactly as the bridge does.
      this._deliver({ type: "ack", id: msg.id, status: "queued" });
      if (opts.dropResult) return;   // simulate a lost result line

      // Pull our tag and the OK/ERR literal straight out of the emitted Lua, then reproduce what
      // Loader.WsSend would carry: tag .. OK/ERR .. <tab> .. tostring(result).
      const tag = (msg.code.match(/'(<<<WSR:[^']+>>>)'/) || [])[1];
      check("wrapper embedded a tag", !!tag, msg.code.slice(0, 120));
      if (!tag) return;
      check("wrapper builds the separator with string.char(9), not a \\t escape",
            /string\.char\(9\)/.test(msg.code) && !/\\t/.test(msg.code), msg.code);
      check("wrapper passes ONE argument to Loader.WsSend (no top-level comma)",
            /Loader\.WsSend\((?:[^,()]|\([^()]*\))*\)/.test(msg.code), msg.code);

      const ok = !opts.fail;
      const value = opts.value === undefined ? "0.4.2" : opts.value;
      const luaLine = tag + (ok ? "OK" : "ERR") + "\t" + value;   // the REAL tab Lua would produce

      // The bridge's envelope. Escaping is what keeps this parseable.
      const frame = opts.skipEscaping
        ? '{"type":"ws","line":"' + luaLine + '"}'                 // the bug this test guards against
        : '{"type":"ws","line":"' + jsEscape(luaLine) + '"}';
      this._deliver(frame);
    }
    _deliver(objOrRaw) {
      const raw = typeof objOrRaw === "string" ? objOrRaw : JSON.stringify(objOrRaw);
      setTimeout(() => this.onmessage && this.onmessage({ data: raw }), 0);
    }
    close() { this.onclose && this.onclose(); }
  }
  return FakeWS;
}

async function run(label, opts, code) {
  const bridge = new EssBridge("ws://127.0.0.1:27050", { WebSocketImpl: makeFakeBridge(opts) });
  await bridge.connect();
  const r = await bridge.run(code || "return Ess.VERSION", { resultTimeout: 300 });
  return r;
}

(async () => {
  // 1. the ordinary success path
  let r = await run("success", {});
  check("success resolves ok:true", r.ok === true, r);
  check("success returns the value with the separator stripped", r.value === "0.4.2", r);
  check("success is acked", r.acked === true, r);
  check("success is not a timeout", r.timedOut === false, r);

  // 2. the failure path -- ERR must not be reported as ok
  r = await run("failure", { fail: true, value: "some error text" });
  check("failure resolves ok:false", r.ok === false, r);
  check("failure still delivers the message", r.value === "some error text", r);

  // 3. A VALUE CONTAINING A TAB. The parser splits on the FIRST tab, so embedded tabs must survive intact --
  //    this is exactly what a multi-value Loader.WsSend or a tab-joined result looks like.
  r = await run("tabbed value", { value: "a\tb\tc" });
  check("a value containing tabs keeps them all", r.value === "a\tb\tc", r);
  check("a tabbed value is still ok:true", r.ok === true, r);

  // 4. Values that stress the JSON escaping on the way through.
  for (const v of ['quote " inside', "back\\slash", "newline\nhere", "ctrlbyte", "unicode ✓"]) {
    r = await run("escaped value", { value: v });
    check("survives JSON escaping: " + JSON.stringify(v), r.value === v, r);
  }

  // 5. THE REGRESSION GUARD. If the bridge ever stops escaping, the frame is invalid JSON and the client's
  //    parse-catch drops it -- the result must time out rather than silently resolve with garbage.
  r = await run("unescaped frame", { skipEscaping: true, value: "x" });
  check("an UNESCAPED tab makes the frame unparseable, so it times out rather than lying",
        r.timedOut === true && r.ok === undefined, r);

  // 6. a genuinely lost result line still resolves (never hangs)
  r = await run("dropped", { dropResult: true });
  check("a dropped result times out instead of hanging", r.timedOut === true, r);
  check("a dropped result still reports the ack", r.acked === true, r);

  console.log(failures === 0
    ? "[bridge-test] all checks passed"
    : "[bridge-test] " + failures + " check(s) FAILED");
  process.exit(failures === 0 ? 0 : 1);
})();
