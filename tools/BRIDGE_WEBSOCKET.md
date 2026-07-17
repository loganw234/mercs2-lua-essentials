# Adding WebSocket support to the lua-bridge

What the bridge (`mercs2-lua-mods/mods/lua-bridge/lua_bridge.c`) needs so a **browser can connect directly** —
no Python/PowerShell relay. Raw TCP stays exactly as-is; WebSocket is an alternate transport on the same
listener. Reference client: [`ess-bridge.js`](ess-bridge.js).

Line numbers below are against the current `lua_bridge.c`.

## The design in one paragraph

A browser can't open raw TCP, but it can open a **WebSocket**, which is just an HTTP upgrade + a framed
byte stream. The bridge's core (`InQueuePush` → pump → `LuaDoString` → output) is already transport-agnostic,
so WS only touches the edges of `BridgeServerThread` (line 2581). And results come back the *reliable* way —
over a **live `Loader.Printf` feed** the bridge forwards to WS clients — so there's **no correlation plumbing
to add in C**: the client tags its result in Lua and matches the tag on the feed (exactly how `lua_repl.py`
already gets reliable results from the log file).

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

### 3. Forward `Loader.Printf` over WS (Tier 2 substrate + the live console) ★
This is the important one, and it's small: `LuaLoaderPrintf` (line 1723) is the bridge's **own** function —
it already `WriteFile`s each line to the log under `g_LoaderPrintfMtx` (line 1751). Right there, also push the
same line to a broadcast queue that every connected WS client drains as `{type:"log"}`. ~3 lines. No detour.

That single feed does double duty: it's a **live game console** in the browser, *and* it's the reliable
result channel — see below.

## Wire contract (JSON text frames)

```
Client → bridge   { "id": "q17abc", "code": "<lua source>" }

Bridge → client   { "type": "ack",    "id": "q17abc", "status": "queued" }     // Tier 1, immediate
Bridge → client   { "type": "log",    "line": "…one Loader.Printf line…" }      // unsolicited stream
```

Raw-TCP clients keep the legacy line protocol (`<<<RUN>>>` / `<<<END>>>`); only WS clients get JSON.

## How results come back (and why it's reliable without C plumbing)

The client **wraps** each chunk before sending, so it prints a nonce-tagged line when it runs:

```lua
local __ok, __r = pcall(function() <user code> end)
Loader.Printf("<<<WSR:q17abc>>>" .. (__ok and "OK\t" or "ERR\t") .. tostring(__r))
```

That tagged line rides the log feed back to the browser, which matches `<<<WSR:q17abc>>>` and resolves the
request. The bridge never has to route a result to a request — the `id` lives in Lua-space. This is the same
log-authoritative approach `lua_repl.py` uses, because the direct socket return is **one-execution-behind**
(buffering — its own header note). It is **not** about execution reliability: the pump fires *constantly*
(below), so chunks run promptly; the log is chosen for ordering + cleanliness, not "will it run".

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
- [ ] In `LuaLoaderPrintf` (line 1751), broadcast each line to WS clients as `{type:"log", line}` — the
      **clean** channel only, never the game's native debug-print the pump hooks.
- [ ] (optional) multi-client output routing for browser + TCP at once.

Everything else — the queue, pump, executor, `Loader.Printf` itself — is reused unchanged.
