# WebSocket support in the lua-bridge

> **STATUS: IMPLEMENTED.** This started as a proposal for what the bridge *needed*; the bridge has since
> shipped it, essentially as specified below. The authoritative source is now
> `Merc2-Mods-Exp/mods/lua-bridge-DEV/lua_bridge_DEV.c` — see its `WebSocket transport` section, plus
> `ws_broadcast_typed_line`, `js_escape_into` and `LuaLoaderWsSend`. Read this document for the *why*; read
> that file for the truth. The four message types, the hidden `Loader.WsSend` channel and the Lua-side tag
> trick all landed unchanged, so what follows is still an accurate description — but the imperative voice
> ("the bridge needs…") is historical.
>
> **Verified against the implementation 2026-07-25**, by reading the C rather than by running it. Confirmed
> facts worth knowing, all of which the reference client depends on:
> - `js_escape_into` **does** escape a literal tab as `\t`. This matters more than it looks: a raw tab byte
>   inside a JSON string is *invalid JSON*, and `ess-bridge.js` parses frames inside a `try/catch` that
>   **silently drops** anything unparseable — so if that escaping ever regressed, every result would vanish
>   and `run()` would just look like it timed out. `tools/test_bridge_client.js` guards exactly that.
> - `Loader.WsSend` and `Loader.Printf` join **multiple** string arguments with a **TAB**
>   (`m2_lua_join_strings` in the SDK). The reference client passes **one** concatenated argument, so the
>   wire format stays ours rather than depending on that separator.
> - ⚠ **OPEN BUG — a returned byte ≥ `0x80` kills the WebSocket connection.** Confirmed live 2026-07-25,
>   byte by byte: ASCII and `0x7F` are fine; `0x80` and `0xE9` ("é" in CP1252) both drop the socket
>   (`onerror` → `onclose`); the *same* character sent as valid UTF-8 (`0xC3 0xA9`) arrives correctly as `é`.
>   RFC 6455 requires a text frame to be valid UTF-8 and the receiver **must** fail the connection otherwise,
>   but `js_escape_into` passes every byte ≥ `0x20` through unchanged. Since the engine's text path is
>   single-byte **CP1252**, any localized name or typographic character in a returned string will do this.
>   **Fix:** in `js_escape_into`, emit `0x80`–`0xFF` as `\u00XX` (it already does exactly this for `< 0x20`).
>   Better still, map the CP1252 `0x80`–`0x9F` block to its true codepoints — `0x92` is U+2019, not U+0092 —
>   but the naive form is enough to keep the frame valid. Raw TCP is unaffected; only WS text framing cares.
> - The raw-TCP result line is `[ok]` + **TAB** + values on success, `[runtime]` + **space** + message on
>   failure, terminated by `<<<END>>>`. Two changes there are worth knowing about if you ever parse it:
>   `[ok]` is newly *reachable* at all (the status used to be read from a stack slot that always held a
>   table, so **every** result — successes included — came back labelled `[runtime]`), and a junk `<table>`
>   artifact that used to prefix every result is now skipped. Nothing in this repo parses that line, so
>   nothing here needed changing; `tools/lua_repl.py` reads its own nonce-tagged line out of the log instead.

Raw TCP stays exactly as-is; WebSocket is an alternate transport on the same listener. Reference client:
[`ess-bridge.js`](ess-bridge.js).

Line numbers below are against the older `mercs2-lua-mods/mods/lua-bridge/lua_bridge.c` and are historical.

## The design in one paragraph

A browser can't open raw TCP, but it can open a **WebSocket**, which is just an HTTP upgrade + a framed
byte stream. The bridge's core (`InQueuePush` → pump → `LuaDoString` → output) is already transport-agnostic,
so WS only touches the edges of `BridgeServerThread` (line 2581). Results come back over a **hidden WS channel**
(`Loader.WsSend` — a new global that broadcasts to WS clients but **never writes the log**), so there's **no
correlation plumbing to add in C** *and* the real log stays clean: the client tags its result in Lua and
matches the tag on that channel (the same tag trick `lua_repl.py` uses, just off a WS feed instead of the file).

## The three changes

### 1. Accept-branch + handshake + framing (transport only)
- After `accept()` (line 2625), peek the first bytes. `GET … Upgrade: websocket` → WS client; anything else
  → the existing raw-TCP path, untouched.
- **Handshake:** parse the request headers, compute `Sec-WebSocket-Accept = base64(SHA1(key +
  "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))`, reply `101 Switching Protocols`. Windows ships both crypto
  pieces — `BCryptHash` (SHA-1) + `CryptBinaryToStringA` (base64) — so **no vendored crypto**.
- **Framing:** two wrappers around the existing `recv`/`send`. `ws_recv` = read a frame header (FIN/opcode,
  7/16/64-bit length), read the 4-byte mask, XOR-unmask the payload; answer `ping` with `pong`, handle
  `close`. `ws_send` = wrap bytes in a server text frame (unmasked). One WS text message = one request.

### 2. Ack on queue (Tier 1 — reliable)
When a WS request is queued, reply immediately with an ack. This is deterministic — the socket thread owns
it. It replaces the raw path's `OutAppend("[queued]")` (line 2671) for WS clients.

### 3. Two WS output channels: `Loader.Printf` (console) + a NEW `Loader.WsSend` (hidden) ★
Both are tiny, and `LuaLoaderPrintf` (line 1723) — the bridge's **own** function, which already `WriteFile`s
each line under `g_LoaderPrintfMtx` (line 1751) — is what you copy from.

- **`Loader.Printf`** → keep the `WriteFile`, **and** also push the line to WS clients as `{type:"log"}`. That's
  the genuine log, mirrored as a **live console feed** in the browser. (~3 lines added in `LuaLoaderPrintf`.)
- **`Loader.WsSend(str)`** — a **new Lua global**: a copy of `LuaLoaderPrintf` with the `WriteFile` **removed**.
  Broadcast to WS clients as `{type:"ws"}` **only, never to disk.** Register it in `loader_lib` (line 2243)
  next to `Printf`. This is the **hidden channel** — the REPL's tagged results and any mod-initiated telemetry
  ride it without ever touching `lua_loader_printf.log`. (~5 lines.)

Keeping them separate matters: the log is already noisy (the pump source *is* the spammy native debug-print),
so you don't want the REPL's own result plumbing in there too. `Loader.WsSend` keeps it out entirely.

## Wire contract (JSON text frames)

```
Client → bridge   { "id": "q17abc", "code": "<lua source>" }

Bridge → client   { "type": "ack", "id": "q17abc", "status": "queued" }   // immediate, reliable
Bridge → client   { "type": "log", "line": "…a Loader.Printf line…" }     // real log, mirrored as the console
Bridge → client   { "type": "ws",  "line": "…a Loader.WsSend line…" }     // HIDDEN channel, never logged
```

Raw-TCP clients keep the legacy line protocol (`<<<RUN>>>` / `<<<END>>>`); only WS clients get JSON.

## How results come back (and why it's reliable without C plumbing)

The client **wraps** each chunk before sending, so it emits a nonce-tagged line on the hidden channel when it
runs:

```lua
local __ok, __r = pcall(function() <user code> end)
local __sep = string.char(9)   -- a TAB, built without a "\t" escape -- see ess-bridge.js for why
Loader.WsSend("<<<WSR:q17abc>>>" .. (__ok and "OK" or "ERR") .. __sep .. tostring(__r))
```

The separator is deliberately `string.char(9)` rather than a `"\t"` escape. `\t` is standard Lua 5.1 and
almost certainly fine, but a sweep of all 370 decompiled game scripts found **zero** uses of a `\t` escape
inside a string literal, so nothing confirms this engine's lexer handles it — and the engine is known to
deviate on escapes elsewhere (it reads `\ddd` as *octal*, not decimal). `string.char` **is** confirmed here:
`src/21_input.lua` and `src/25_keys.lua` both run `string.char` loops at file-load time, so every `[Ess] ready`
boot exercises it. If `\t` silently produced a literal backslash-t, every result would fail the client's
`indexOf("OK\t") === 0` test and come back as `ok:false` with a mangled value — a whole-channel outage for a
two-character reason, which is not a risk worth carrying for zero benefit.

That tagged line rides the hidden `{type:"ws"}` channel back to the browser (**invisible to the log**), which
matches `<<<WSR:q17abc>>>` and resolves the request. The bridge never has to route a result to a request — the
`id` lives in Lua-space. It's the same tag trick `lua_repl.py` uses; the reason it reads a side channel at all
(rather than the direct socket return) is that the direct return is **one-execution-behind** — but note that
was a *connect-per-command artifact* (`lua_repl.py` disconnected after each command, so a result flushed on the
*next* connection). A **persistent** WS connection flushes continuously, so that constraint is gone — which
also unlocks the "even cleaner" option below.

**Even cleaner (optional, more C):** because the persistent connection removes the one-behind problem, the
bridge could skip the Lua wrapper entirely and emit the executor's **already-formatted** result — it computes
`result_buf` via `FormatTValue` (line 569) after every run — as a structured `{type:"result", id, ok, value}`
message, WS-only. Richer than Lua's `tostring`, zero client wrapping. Cost: a `char id[]` on `ChunkNode` and
per-record WS framing. Start with the `Loader.WsSend` wrapper (no C queue changes); consider this later.

**Why the pump is not a concern:** it rides on the game's own **noop'd native debug-print**, which every stock
script calls all the time — so it's driven continuously (proven: the bridge ran overnight at ~200–300k
executed chunks/sec brute-forcing hashes in-game). So a client `{timedOut:true}` is a rare safety net (a
dropped/slow line), never "the chunk didn't run," and **no "guaranteed periodic pump" is needed** — it already
is one.

**The real design consideration — keep the feed clean:** forward **`Loader.Printf`** (the dedicated,
uncluttered log), **not** the game's native debug-print. The native print is what the pump hooks, and stock
scripts spam it thousands of times a frame — forwarding *that* would drown the browser in trash. `Loader.Printf`
exists precisely as the separate clean channel (its own comment, line 1693). (Unrelated aside: the
`luaB_pcall`-returns-junk quirk makes the `ok`/value *formatting* best-effort — see `FormatTValue`, line 569.)

## Concurrency note

The current loop is single-client (`listen(srv, 1)`, one `c`, one global `g_outBuf`). "Accept raw TCP **or**
WS, one at a time" needs nothing beyond the above. Running a browser **and** the Python REPL **at once** needs
multi-client accept + a per-client (or broadcast) output path — and the single `g_outBuf` blob cuts against
that. The **log broadcast is naturally many-client** (fan out to all WS clients), so a good incremental target
is: many WS log subscribers + one command connection at a time.

## Checklist

- [ ] Peek-and-branch after `accept()`; WS handshake (BCrypt SHA-1 + base64) → `101`.
- [ ] `ws_recv` (unmask, handle ping/close) + `ws_send` (text frame); 1 message = 1 request.
- [ ] Parse `{id, code}`; `InQueuePush(code)`; send `{type:"ack", id, status:"queued"}`.
- [ ] In `LuaLoaderPrintf` (line 1751), *also* broadcast each line to WS clients as `{type:"log", line}` (keep
      the `WriteFile`).
- [ ] Add `Loader.WsSend(str)` — a `LuaLoaderPrintf` copy **minus** the `WriteFile` → broadcast as
      `{type:"ws", line}`; register in `loader_lib` (line 2243). (This is what result plumbing rides.)
- [ ] (optional) bridge-emitted structured `{type:"result", id, ok, value}` from the executor's `result_buf`
      (needs a `char id[]` on `ChunkNode`) — skips the Lua wrapper entirely.
- [ ] (optional) multi-client output routing for browser + TCP at once.

Everything else — the queue, pump, executor, `Loader.Printf` itself — is reused unchanged.
