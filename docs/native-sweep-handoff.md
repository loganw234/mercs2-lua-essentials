# Native-coverage sweep — handoff / status

**Read this first if you are picking up the engine-native mapping work.** It is written to survive a context
compaction: it assumes you remember nothing, and it carries the operational knowledge that is expensive to
rediscover. Companion file: [`deferred-setters.md`](deferred-setters.md) (per-native worklists, call-site
evidence, and the decisions about what is deliberately NOT wrapped).

Last updated 2026-07-26.

---

## 1. What this project is

Ess wraps Mercenaries 2's engine natives. `api/natives.json` is a live `pairs(_G)` walk of the running game
and is the inventory of what exists; `called_by_ess` on each namespace is the coverage flag, so the gap
between them is the worklist. The engine has **965 native functions**, plus a much larger script-backed
surface, and Ess reaches a fraction of both.

**No source exists for engine natives — but check that a namespace IS one before assuming.** The single
biggest correction this project has made was discovering that `Hud.*` and `Pda.*`, 106 functions catalogued
as opaque natives, are ordinary resident Lua with readable source. `natives.json`'s `kind` field is now
trustworthy on this point (see §2), but the instinct to check first is worth keeping.

Evidence comes from four places, in descending order of authority:

1. **Live probing** through the lua-bridge REPL — the only ground truth for behaviour.
2. **The decompiled corpus** — `~/Desktop/Mercs2_Decompiled_Lua`. Shows real call sites, so arity and
   argument vocabulary. It only covers what shipped scripts happen to call.

   **Use `docs/mercs2-luacd/src` (370 files), not the repo root.** The repo contains the same 370 scripts
   TWICE — once at `./src/{resident,shell,vz}` and once at `./docs/mercs2-luacd/src/{...}` — so an `rglob`
   from the root double-counts every call site. Any call-site figure in this document from before
   2026-07-26 is doubled: `Hud.ObjectiveTray` is 98 sites and not 196, `Hud.Radar` 41 and not 82. The tell
   is that every count comes out even.
3. **The notes repo** — `../notes-on-the-released-game`. Its `docs/lua_engine_bindings_audit_deep_dive.md`
   is the *verified* EXE binding audit (31 namespaces, 1081 bindings, **61 no-op stubs**). Its
   `output/extracted/` holds LEVEL data, which contains things the script corpus does not — this is how the
   full atmosphere-region list was found.
4. **The wiki** (wiki.mercs2.tools) — untapped this session, and known to contain at least one thing the
   corpus does not (`Human.Inventory`, which Ess already uses despite zero corpus call sites).

---

## 2. Operational knowledge — the expensive-to-rediscover part

### Verifying what is loaded
- **`Ess.VERSION` is NOT sufficient.** It sat at `0.4.2` across two sessions' worth of new functions before
  being bumped to `0.5.0`. **Check function presence instead**: `type(Ess.Pda.blip)`, etc. Bump the version
  when you add a module so the next person has a coarse signal at all.
- **Hot-reload without a relaunch**: `Loader.LoadFile("OnLoad/1_Ess.lua")` after `launch.py --deploy`. The
  path is relative to `<game>/scripts/`, so the prefix is `OnLoad/…` and **not** `scripts/OnLoad/…` — the
  wrong path returns cleanly and loads nothing, which looks exactly like a load that did not take. It
  cannot REMOVE a function (see below), but it is otherwise the fast loop.
- A relaunch loads whatever is **deployed** at `<game>/scripts/OnLoad/1_Ess.lua`, which is frequently stale.
  `python tools/launch.py --status` reports `SIZE MISMATCH -- redeploy`. Run `--build --deploy` before
  trusting anything after a relaunch.
- **Hot-reloading cannot REMOVE a function.** `Ess.Object` is a persistent table; deleting a function from
  source and re-loading leaves the old one live until a fresh game load.

### Two REPL clients, different trade-offs
- `python tools/lua_repl.py --code '<lua>'` — the repo's tool. Wraps your chunk in a `pcall` **and a
  `Loader.Printf` nonce**, and reads the result from the LOG, not the socket. That wrapper makes big-result
  natives work that would otherwise fail, but it also means **a chunk can report OK when the executor
  actually errored**. If a result looks surprising, check `lua_bridge_DEV.log` before believing it.
- `bridge_send.py` (scratchpad) — sends the raw chunk, no wrapper. Better for isolating bridge behaviour;
  worse for anything returning a large table.

### Result-channel limits
- **Results are single-line.** Output truncates at the first newline in the returned string. Sanitise with
  `string.gsub(s, "[\r\n]", "~")` before returning anything that might contain one.
- For long output, `Loader.Printf` it and read `scripts/lua_loader_printf.log` by byte offset instead.
- **Large returns overflow the executor.** The bridge builds its Lua frame by hand at `L->top` with only
  `LUA_MINSTACK` headroom and never grows the stack. Measured: r=40 (35 results) fine, r=100+ errors and
  prints stack residue as "results". The threshold is ~200-240 results and it is INTERMITTENT with live
  traffic. **Accepted as a known limitation** — use smaller queries from the REPL. Scripts running inside
  the game get a normal engine frame and are unaffected.

### The UI cluster is script, and it is method-called
- **`Hud.*` and `Pda.*` are NOT engine natives.** `resident/mrxguiinterface.lua` opens with
  `_G.Hud = HudInterface` / `_G.Pda = PdaInterface`, and all 106 functions are thin wrappers that resolve a
  Scaleform widget by name (`_GetWidgetsForPlayers(vPlayer, "Objective Tray")`) and forward to it. The
  widget classes are script too — `mrxguimanager.lua`, `mrxguitextbuffer.lua`, `mrxguipda.lua`,
  `mrxguihudmessage.lua`. **Read these rather than probing.** Every non-obvious fact in `57_hud.lua` and
  `58_pda.lua` came from the source in minutes; probing would have taken a session and missed most of it.
- **They are COLON calls taking one named-field table**: `Hud.MessageBox:AddMessage{sMessage=...}`. The
  wrappers use `self` (MessageBox reads `self.sName` to choose its widget; `Hud.SubtitleBuffer` is literally
  the same functions bound to a table with a different `sName`). A dot-call hits the wrong widget.
- Every wrapper accepts `vPlayer` (nil = all players, which is what singleplayer wants) and `bDontNetSync`.
  `Net.IsServer()` is **true** in singleplayer, so the co-op broadcast branches do execute.

### Engine quirks that will bite
- **String escapes are OCTAL, not decimal.** `"\101"` is `"A"` (65), not 101. Base-8 accumulator with no
  validation of the digits 8/9. See [[reference-merc2-lua-octal-escapes]] in agent memory.
- **The engine's text path is single-byte CP1252.** A UTF-8 `.lua` renders `Möbius` as `MÃ¶bius`. The bridge
  now transcodes at load time (v0.5.0+).
- **`tostring()` with two arguments returns a FUNCTION** on this build. Several natives return two values
  (`GetCurrentSetting`), so `tostring(f())` can silently produce a function instead of a string.
- **Name lookup is case-insensitive** (`Pg.GetGuidByName`).
- **`nil` is often used where `false` is meant** — `Vehicle.IsFlying` on a car, `Object.IsWinched` on a
  non-winch object. Falsy either way, but `x == false` is never true. Wrappers normalise this.

### Do not do these
- **Do not batch `Graphics.Atmosphere.ChangeLineRegionSetting`.** Six in one chunk caused a measured
  **13-second engine stall**, with the watchdog firing correctly on a real hang and the game degraded for
  minutes afterwards. Pace it if it is ever needed.
- **Do not use `_G.__name`-style double-underscore globals** in probe chunks; use plain names.

---

## 3. What was done this session

### lua-bridge (`../Merc2-Mods-Exp`) — released v0.5.0, v0.5.1, v0.5.2

| Release | Contents |
|---|---|
| **v0.5.0** | Loader reliability pass: OnKey focus gate, OnBoot/OnLoad re-arm on menu return, `g_seenL` ring, watchdog coverage for loader scripts, source-encoding normalisation (BOM strip + UTF-8→CP1252), hotkey modifiers/numpad, scan hardening, `Loader.GetLoadPhase`/`LoadFile`, `m2_logf` format fixes |
| **v0.5.1** | Transport correctness: raw-TCP result channel was **one execution behind** (results had no association with the requesting connection); WebSocket TEXT frames could carry invalid UTF-8 (high bytes now `\uXXXX` with the real CP1252 mapping, so `0x92`→U+2019) |
| **v0.5.2** | **Framerate regression fix.** The first Lua chunk of a session could permanently halve FPS. Chain: watchdog false-positive on first chunk (stall clock only advanced on drains) → its reset wiped `g_seenL` → that counterfeited a "new VM" event → the v0.5.0 menu re-arm fired → cleared `g_OnLoadTriggered` → re-enabled a per-log-line scan with no reachable exit. Fixed at all three layers. |

Also proven and fixed in v0.5.0: **every chunk execution was corrupting the hooked function's stack frame**
— this build's `luaB_pcall` writes its status to `saved_base[0]`, so the original detoured function read a
replaced argument 1. And `[ok]` was previously unreachable (status was looked for in the wrong slot).

### Ess (this repo) — 10 commits, none pushed

`7541040 · cd232ad · 85db1bc · c215a97 · 19c63f1 · d4cc8e2 · 3e8fee0 · 18154ab · 47dde99 · d34b4df`

**Tooling.** `dump_natives.py` was broken (a `NameError` meant it could not run at all) and was recording
the bridge's OWN registrations as engine natives — 29 of them (`Loader` 9, `Tcp` 1, 19 math polyfills). The
math case hid because `Math == math` is one table under two names. Engine surface 1146 → **1108**.

**Namespaces extended** (read side, then mutators):

| Namespace | Start | Now |
|---|---|---|
| Player | 14/107 | 22/107 |
| Object | 40/87 | 56/87 |
| Vehicle | 11/40 | 24/40 |
| Human | 5/21 | 18/21 |
| Sys | 10/64 | 20/64 (new `Ess.Sys`, `src/05_sys.lua`) |
| Pg | 32/80 | 35/80 |
| Atmosphere | 6/37 | new `Ess.Atmosphere`, `src/06_atmosphere.lua` |
| Hud + Pda | 8/106 | 34/106 (`src/57_hud.lua` extended, new `src/58_pda.lua`, new `src/57_minimap.lua`) |

**New modules:** `05_sys.lua` (environment/build/settings), `06_atmosphere.lua` (transaction model + key
vocabulary + region system).

**Notable additions:** `Ess.Player.viewPoint` (engine camera vector — no reticle fallback, unlike
`viewYaw`), `Ess.Probe.inArea`/`awakeInArea`, `Ess.Vehicle.seatInfo` (full seat descriptor), `Ess.Unname`
(guid↔string round trip), `Ess.Easy.World.freezeTime`.

**Withdrawn:** `Ess.Object.name` — `Object.GetName` returns userdata with no string form reachable from Lua.

---

## 4. Decisions already made — do not re-open

- **Economy setters NOT exposed** (`Player.SetCash/AddCash/SetFuel/AddFuel/SetFuelCapacity`, profile/costume
  writers). They write the save, and `giveCash`/`giveFuel` already route through `MrxPmc` so the HUD
  updates — the raw setters do not.
- **Game-state drivers NOT exposed** (`Sys.RequestGameState` at 86 sites, `StartSingleplayer`,
  `SetLevelName`, `Pg.UnloadAsset` at 54, `UnloadLayer`/`LoadLayer`/`ReloadLayer`, `LoadGame`). A wrong
  argument does something drastic rather than nothing.
- **The hijack state machine is skipped** — 11 natives driving one sequence with invariants. Deserves its
  own focused pass, not a tail-end batch.
- **`ChangeLineRegionSetting` not wrapped** — see §5.
- **`Pda.Database.AddHelpEntry` not wrapped — it is a write-only dead end.** The widget stores it exactly
  like a dossier entry into `oPda.CustomData.tDataHelp`, and that table is initialised in one place,
  appended to in one place, and **read in none**. `tDataDossiers` is read at `mrxguipda.lua:1388` and
  rendered, which is why dossiers appear and help entries do not. Confirmed live: nowhere in the PDA.
- **`Hud.FactionDisplay.RemoveMeter` / `.RemoveAllMeters` have EMPTY BODIES** in the shipped script.
  Callable, return nil, do nothing. Not wrapped.
- **`Hud.Tutorial.ShowTutorialOnscreen` / `.ShowTutorialForObject` not wrapped** — broken for any explicit
  `vPlayer`: a userdata player builds an empty target list (silent no-op) and a table player reads an
  undeclared global and errors inside `pairs(nil)`. Only the omitted-`vPlayer` path works, and nothing in
  the corpus ever called either.

---

## 5. The atmosphere finding (relevant to any lighting/visual work)

- **`Graphics.Atmosphere` is transactional.** `GetValue` returns nil outside `Begin()`/`End()`.
- **Keys are not validated** and the engine misspells its own: `fBloomContastMultiplier` (Contast). A bogus
  key reads 0, and 0 is legitimate for real keys, so there is no existence test.
- **There are 40 atmosphere regions**, not the 6 the corpus names. The full list is in the LEVEL data
  (`notes-on-the-released-game/output/extracted/batch_vz/blocks/00029_blocks__VZ__layers_static_P000_Q3.block.bin`
  — `strings | grep rgn_atmo_`). 41 strings → 40 regions because lookup is case-insensitive.
- **Crossing a region starts an interpolated blend (~1s)** toward that region's authored preset. Your change
  becomes the blend's starting point — which is why atmosphere "does not stick".
- **Time RATE vs time VALUE is the key asymmetry.** `SetTimeSpeed(0)` is global and survives crossings.
  `SetTime(n)` is overridden by any region with its own preset — verified with a keeper ticking 1,299 times
  at 10 Hz while the sky stayed daylight. **So freezing the cycle is reliably map-wide; forcing a specific
  time is not.**
- **`EnableImmediatelyChangeMode(true)` is NOT inert** — it removes interpolation, turning the crossing fade
  into a hard cut.
- **There is no `GetTimeSpeed`.** Once changed, the authored rate cannot be restored except by level reload.

---

## 5a. The Hud/Pda findings (2026-07-26, all live-confirmed on screen)

- **PDA map coordinates are world X and world Z** (`nY` is Z — the render path adds `nZOffset` to it).
  Height is not representable. **The X axis is MIRRORED**: measured with a four-blip cross, `nY+400` drew
  above the player, `nX+400` drew LEFT and `nX-400` drew RIGHT. The flip is inside the Flash movie.
- **A blip with no `sTexture` is INVISIBLE** — placed and hoverable, but nothing is drawn until the cursor
  is over it. **A blip with no `sLabel` displays its TEXTURE NAME** (the render path builds a positional
  array whose label slot goes nil, and the movie shows the texture instead). This is why `Ess.Mark`'s blips
  read "icon_yellow_mc". `Ess.Pda.blip` now defaults both.
- **Icon names are CLOSED SETS**, enumerated in `mrxutil.lua` and now exposed as `Ess.Pda.ICONS` (32) and
  `Ess.Hud.RADAR_ICONS` (23). `MarkerGetIndexByName_*` linear-searches them and returns 0 for anything else.
- **`Hud.MessageBox` `nDuration < 0` means PERMANENT** (the widget converts it to duration 10000 +
  `bPersistent`). Confirmed still on screen many minutes later. Priority is 0–5, out-of-range clamps to 5.
- **`ModifyPendingMessage` means "pending" literally** — it searches the queue, so a message already on
  screen cannot be found and you get a bare `false`. Adding to an empty box displays immediately, so the
  very next modify fails. Not a bug.
- **`Hud.Tutorial:SetText` is STICKY** — no duration, stays until cleared with `sText = nil`.
- **`Hud.ClassyText` is the nicest text primitive in the game** (animated `text_effect.swf`). 640×480
  virtual space; `nX` is overwritten by the game so it is always horizontally centred.
- PDA log `sType` "objective" / "event" / "dialog" all route and display. `sColor` is bare hex, no `#`.
- Re-adding a dossier entry with the same `sTitle` **edits** it rather than duplicating.

### The three marker layers (Ess.Mark) — alignment and colour

- **The three surfaces do not share an icon namespace.** The same objective is `HUD_objective_destroy` in
  the world, `objective_destroy` on the radar and `icon_destroy_1_mc` on the PDA, each validated against a
  different fixed table in `mrxutil.lua` by a different lookup function. Nothing in the engine relates them.
  `Ess.Mark.KINDS` now records the correspondence for **action / destroy / defend / verify / deliverable /
  outpost / generic** plus `faction_*`, every name verified present in all three tables.
- **Colour is available on two of the three.** `rgb` tints the radar dot and the world icon/ring, verified
  with three otherwise-identical markers rendering red/green/blue. **`Pda.Map.AddMapBlip` has no colour
  argument at all** — thirteen parameters, none of them rgb — so the PDA layer can only be coloured by
  choosing a different texture. This is a hard engine limit, not a gap in the wrapper.

### The minimap widget (`Ess.Minimap`) — reachable, and the range fights back

- `Hud.Radar` can only add/remove/animate objectives. The **widget** underneath carries `SetRange`,
  `SetRotation`, `SetBorder` and `SetVisible`, none reachable through any `Hud.*` function. Get it with
  `MrxGuiBase.GetWidgetByName("Minimap")` — the game does the same thing at `mrxguiinterface.lua:511`.
- **The range is recomputed from player speed on every minimap update** (`MinimapDataUpdateHandler`,
  `mrxguibase.lua:1532`: 150 below speed 10, 400 above 50, linear between). A bare `SetRange` applies and
  visibly holds until the next update — measured: range 1500 held while standing still, snapped back on
  turning.
- **Two traps in overriding it**, both hit and both fixed: `_G.MinimapDataUpdateHandler` is **nil** because
  `import()` namespaces resident globals (it is `MrxGuiBase.MinimapDataUpdateHandler`), and patching that
  module entry would not work anyway because **the widget captures the handler by value at construction**
  (`mrxguibase.lua:1445`). The override has to go on the widget via its own `SetEventHandler`, which is also
  narrower and properly reversible. Confirmed holding through turning and driving.
- The widget is **rebuilt on level load**, taking any override with it. Re-apply after a load.
- Other handlers on the widget, all untouched so far: `SetGPSDest`, `ClearGPSDest`, `SetTargetMarker`,
  `HomingLockStart/Update/Clear`, `HomingLaunched`. The GPS routing layer is the obvious next thing here.

---

## 6. What is next

### `Sound` (audio) — the remaining cluster

**`Sound`** — 88 total, 5 covered, 49 uncovered with evidence, ~325 call sites (halved; see §1). **9 known
stubs**, and unlike Hud/Pda this one really is engine-native, so it must be probed rather than read.
Blocked on verification: there is no audio channel to the agent, so a human must confirm anything plays.

### Hud/Pda leftovers, in rough value order

- **`Hud.Radar` is done** (8/9). Only `UpdateObjective` is unwrapped, and deliberately: it calls the exact
  same `oWidget:AddObjective` as `AddObjective` with the same arguments, so re-adding under an existing
  name already is the update. Not worth a second name.
- **`Pda.Map`** 11 uncovered — the mission system (`AddMission`, `SetSelectedMission`,
  `SetMissionTrackCallback`, `SetMissionTrackable`). This is how a mod registers as a real trackable
  mission rather than a loose blip, and `Ess.Contract` is the obvious consumer.
- **`Hud.Shop`** 7, all uncovered — `Create`/`AddItemFull`/`SetCallback`/`Commence`. A working native
  purchase UI with callbacks; the biggest single unexplored piece here.
- **`Hud.FactionDisplay`** — `StartTimer` is an on-screen countdown with a callback; `AddMeter`/`SetValue`
  drive arbitrary labelled meters. (`RemoveMeter`/`RemoveAllMeters` are dead — see §4.)
- The fanfare family (`Fanfare`, `SupportFanfare`, `ContactFanfare`, `CardFanfare`, `JobFanfare`,
  `TextFanfare`, `FanfareQueue`) — `Ess.Contract` already drives `EventFanfare`; the others are the same
  shape.
- `Hud.Cinematic` (letterbox/play/pause) pairs with `Ess.Cinematic`.

Both remaining areas need a human watching/listening. That is the constraint, not the code.

### Also outstanding
- **`mercs2-lua-essentials/tools/test_bridge_client.js`** contains a deliberate line-for-line port of the
  bridge's `js_escape_into`, so the two disagreeing fails the test. That port is now **stale** (it predates
  the v0.5.1 high-byte escaping) and no test input uses a high byte, so it would not catch a regression in
  exactly the code that changed. It also requires the retired `ess-bridge.js` rather than the canonical
  `mercs2-tools-shared/js/bridge-client.js`.
- **`lua_repl.py` can drop its log-based workaround** now that the one-execution-behind bug is fixed
  (v0.5.1). Different repo; give the fix some mileage first.
- **`12_vehicle.lua`'s `enterBestSeat` caution** describes a 30-second stall after spawn-and-enter in an
  interior, never causally confirmed. Two *real* stall causes were found this session (watchdog
  false-positive, executor stack overflow) — that note may describe one of them and could be retired if it
  no longer reproduces.
- **`stack_diag = 1`** still ships enabled in the bridge ini. It is the regression detector for the frame
  corruption; consider defaulting it off once confident.

---

## 7. Workflow reminders

- The live-test workflow is `.claude/skills/ess-live-test`. `launch.py --status` first, **always verify by
  function presence**, and rebuild+redeploy after any src change.
- Gates before every commit: `python tools/checkpure.py` (offline, 11 groups) and `python tools/smoke.py`
  (needs the game, 49 recipes, ~2.5 min). Smoke occasionally reports 1 "missing" from a late timer PASS —
  re-run before treating it as a failure.
- **Probe before wrapping.** This session found `IsJoined` taking an index not a guid, `GetVelocity`
  returning a scalar, `GetName`/`GetModelName`/`GetCurrentSetting`/`GetLineRegionSetting` all returning
  opaque userdata, `PolarToRect` taking (angle, radius) in DEGREES, and `randf(a,b)` returning `[a, b+1)`.
  Assume the same rate of surprise.
- **Return values differ in how much they tell you.** `Vehicle.SetParts` is self-validating (nil = no such
  part); `Human.SetState` returns nil for valid AND invalid states. Check which kind you have before relying
  on a result.
