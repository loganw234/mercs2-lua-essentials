/* tools/probe_ws_bytes.js -- LIVE probe: which byte values survive a lua-bridge WebSocket text frame?
 *
 * Requires the game running with a WS-capable lua-bridge. Run: `node tools/probe_ws_bytes.js`
 *
 * NOT IN CI, on purpose: this deliberately breaks the socket it is testing, so it cannot share a connection
 * with anything else. It exists as the standing reproduction for an OPEN BRIDGE BUG, and as the check to run
 * after that bug is fixed.
 *
 * THE BUG (confirmed live 2026-07-25). A returned byte >= 0x80 kills the connection:
 *     ASCII, 0x7F ................ fine
 *     0x80, 0xE9 ("e-acute") ..... socket dies (onerror -> onclose)
 *     0xC3 0xA9 (same char, UTF-8) fine, arrives as the character
 * RFC 6455 requires a WebSocket TEXT frame to carry valid UTF-8 and the receiver MUST fail the connection on
 * invalid UTF-8. The bridge's js_escape_into() passes every byte >= 0x20 through unchanged, so a lone high
 * byte goes out raw. The engine's text path is single-byte CP1252, so any localized name or typographic
 * character in a returned string triggers it.
 *
 * FIX: in js_escape_into (Merc2-Mods-Exp/mods/lua-bridge-DEV/lua_bridge_DEV.c), emit 0x80-0xFF as \u00XX,
 * as it already does for < 0x20. Better: map the CP1252 0x80-0x9F block to real codepoints (0x92 -> U+2019).
 *
 * EXPECTED OUTPUT once fixed: every row reads "alive".
 */
"use strict";
const path = require("path");
const EssBridge = require(path.resolve(__dirname, "ess-bridge.js"));

const URL = process.env.ESS_BRIDGE_URL || "ws://127.0.0.1:27050";

// Each trial gets its OWN connection: a dead socket can't be reused, and sharing one would make every
// trial after the first failure meaningless.
async function trial(label, code) {
  const bridge = new EssBridge(URL, { WebSocketImpl: globalThis.WebSocket });
  bridge.autoReconnect = false;
  const states = [];
  bridge.onStatus = (s) => states.push(s);
  try {
    await bridge.connect();
  } catch (e) {
    console.log("  ????? " + label + "   (could not connect: " + e.message + ")");
    return null;
  }
  const r = await bridge.run(code, { resultTimeout: 4000 });
  await new Promise((res) => setTimeout(res, 600));       // give a close time to land
  const died = states.includes("error") || states.includes("closed");
  console.log("  " + (died ? "DIED " : "alive") + "  " + label.padEnd(42) +
              (died ? "" : "-> " + JSON.stringify(r.value)));
  try { bridge.close(); } catch (e) {}
  await new Promise((res) => setTimeout(res, 250));
  return died;
}

(async () => {
  console.log("probing " + URL + " -- which bytes survive a WS text frame?\n");
  const results = [];
  results.push(["ascii",      await trial("pure ASCII (control)", "return 'plain ascii'")]);
  results.push(["0x7F",       await trial("byte 0x7F (last ASCII)", "return string.char(127)")]);
  results.push(["0x80",       await trial("byte 0x80 (first high byte)", "return string.char(128)")]);
  results.push(["0x92",       await trial("byte 0x92 (CP1252 curly apostrophe)", "return string.char(146)")]);
  results.push(["0xE9",       await trial("byte 0xE9 (233, CP1252 e-acute)", "return string.char(233)")]);
  results.push(["utf8",       await trial("valid UTF-8 for the same char", "return string.char(195)..string.char(169)")]);
  results.push(["ascii2",     await trial("ASCII again (proves it's the byte, not the socket)", "return 'still fine'")]);

  const deaths = results.filter(([, d]) => d === true).map(([k]) => k);
  console.log("");
  if (deaths.length === 0) {
    console.log("ALL ALIVE -- the high-byte escaping bug appears FIXED in this bridge build.");
    process.exit(0);
  }
  console.log("BUG PRESENT -- these byte cases dropped the connection: " + deaths.join(", "));
  console.log("See this file's header for the one-line fix in js_escape_into.");
  process.exit(1);
})();
