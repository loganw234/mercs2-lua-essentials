# Ess — Feature Sheet (working design doc, v0.1)

`Ess` (global `_G.Ess`, long form "Essentials") is the foundational Lua library for Mercenaries 2
modding. Its job: take every hard-won pattern this project has discovered — bone manipulation, the
32-bit-float RNG trap, leak-prone handle APIs, the corner-coordinate widget bug, the trigger/relations/
AI-order vocabulary built for wave-defense — and make it a one-line call instead of folklore a new
modder has to rediscover by crashing the game first.

This document maps the **whole system** before any of it is built, so implementation has a target
instead of growing organically. It is not final — naming and grouping are explicitly up for revision
once we start writing code against it.

## Implementation status (2026-07-16)

**Built:** Groups A, B, C, D (`Ess.Safe`/`Table`/`Guid`/`Name`/`Log`, `Ess.Player`, `Ess.Object`,
`Ess.Vehicle`, `Ess.Probe`, `Ess.Loop`/`Timer`, `Ess.Input`, `Ess.State`/`SaveVar`, `Ess.Track`/`Event`)
plus `Ess.RNG` pulled forward from Group F — all single-tier, zero dependency on `ModNet`/`uilib`/
`ContractFramework`. Source in `src/00_core.lua` through `src/53_rng.lua`; `build/merge.py` concatenates
them into `dist/Ess.lua` (gitignored, build it yourself: `python build/merge.py`). Verified with the
existing corpus's own `tools/loadcheck.py` — loads clean, chunk reaches the bottom, boot line fires.
**Deploy pipeline + first real BEHAVIORAL verification CONFIRMED in-engine 2026-07-16:** `tools/launch.py`
(build -> deploy -> virtual-controller -> launch -> menu-navigation all the way into an actual loaded
game) + `tools/lua_repl.py` (a rewritten, log-based live REPL — see `tools/README.md`) together confirmed,
against the real running game (not `loadcheck.py`'s stubbed lupa environment):
- The merged `dist/Ess.lua` loads clean (`[Ess] v0.1.0 ready` in `lua_loader_printf.log`).
- **`Ess.Player.character(0)` returns the EXACT same guid as `Player.GetLocalCharacter()`** — the flagship
  convenience function, byte-for-byte verified, not just load-checked.
- The error path works: a deliberately broken call correctly surfaces the real Lua traceback through the
  log-tag mechanism (`attempt to call global '...' (a nil value)`), not just a generic failure.
- **`Ess.RNG` produces real, varying values in the ACTUAL 32-bit-float engine** (`Ess.RNG.new(1)` drawing
  3 values in a row: `0.001 0.086 0.437`) — this is the single most important hard-won fact in the whole
  project (the big-LCG-degenerates trap) confirmed working live, not just reasoned about.

**★ 2026-07-16 (overnight session) — full behavioral smoke-test pass, everything in Groups A-D + RNG now
individually exercised live** except `Ess.Input.hijackController` (still an honest documented gap, see
below): `Ess.Safe.call/quiet/string`, `Ess.Table.compact`, `Ess.Guid`/`Ess.Name`, `Ess.Player.slot/camera/
pose/giveCash/giveFuel`, `Ess.Object.vehicleOf/setInvincible/pollVehicleChange`, `Ess.Vehicle.driver/riders/
seatOf/enterBestSeat/followGhost`, `Ess.Probe.nearby/getFaction/describeSafe`, `Ess.Loop.start/stop/
isRunning` (confirmed a live self-incrementing heartbeat actually ticks asynchronously AND that `.stop()`
halts it before any further tick), `Ess.Timer` (elapsed + the 0.25s clamp), `Ess.State` (confirmed the
actual field-merge fix: an existing field survives a later `defaults` call while a newly-added default
field still gets picked up), `Ess.SaveVar` (real `Loader.SaveVar`/`LoadVar` round-trip), `Ess.Track`
(confirmed reverse-registration teardown order), `Ess.Event.on/off` (confirmed a tracked timer both fires
AND can be cancelled before firing), `Ess.Input.poll`/`VkToChar`. All passed.

**Two genuine discoveries from this pass, now documented in-source:**
- `Ess.Player.slot(1)` (⁠→`Player.GetSecondaryPlayer()`) returns a real, non-nil, distinct-from-slot-0 guid
  even in single-player — unlike `Ess.Player.character(1)`, which correctly nils outside co-op. Do not use
  `slot(1)` as a co-op check; `character(1)` is the correct one (already was, this just confirms it's the
  ONLY correct one). See `src/10_player.lua`.
- `Ess.Vehicle.enterBestSeat` itself is confirmed working (returns true, character actually seats) — but
  spawning a `Veyron` and entering it from INSIDE the PMC HQ interior cell was immediately followed by the
  bridge's Lua execution tick stalling for 30+s (process stayed alive/"Responding" per Windows, but zero
  chunks executed, not even a bare `return 1+1`), recovered only via killing the process and a fresh
  relaunch. Causation unconfirmed (could be coincidental) but flagged in `src/12_vehicle.lua` — avoid
  repeating spawn+enter-vehicle from an interior cell without review.

**Two documented gaps, left honest rather than guessed:** `Ess.Vehicle.enterSeatExcluding` falls back to
`enterBestSeat` without enforcing the exclusion (the real native call wasn't confirmed against primary
source this pass); `Ess.Input.hijackController` is synthesized from a deep-dive survey summary, not a
direct source read — both are flagged in their own file's header comment, and `hijackController`
specifically remains untested (lower priority than building the unbuilt namespaces below; `tools/xpad.py`
exists to eventually drive a real controller-event test for it).

**★ 2026-07-16 (overnight session) — rest of Group F built and behaviorally verified live:**
`Ess.Bones` (`attachFX`/`detachFX`/`waitForReady`/`aimVector`/`probeNames`), `Ess.Camera`
(`lookAtAnchor`/`staleAxisDecay`/`followHardpoint`), `Ess.Points` (`bucket`/`ideal`) — source in
`src/50_bones.lua`/`51_camera.lua`/`52_points.lua`, added to `build/merge.py`'s MANIFEST. Every function
individually exercised against the live game (Points additionally verified with pure synthetic data, no
game needed): `attachFX`/`detachFX` glued+removed a real FX on the player's own `bone_attach_rhand`;
`aimVector` returned a real non-zero vector between two hand bones; `probeNames` correctly distinguished
2 real hits from 1 miss in a 3-candidate sweep; `waitForReady` fired its callback (player character is
always immediately ready, as documented); `lookAtAnchor` spawned a `TinyGeometry` anchor and bound
`Camera.SetLookAt` without any bridge stall; `staleAxisDecay` produced the exact expected 0.50/0.50/0.00
sequence across a simulated timeout; `followHardpoint` ran ~15 ticks over 1.5s against the player's own
chest bone with zero errors in the log. All passed.

**★ 2026-07-16 (overnight session) — Group E built and verified: `Ess.Gfx` + adopt-aliases.**
`src/40_gfx.lua` (`widget`/`call`/`onEvent`/`setVisible`/`warmupRerender`/`menuNav`) live-tested against
`"minimap"`, a real pre-existing base-game movie asset (deliberately not authoring a new `.gfx` WAD patch
tonight — out of scope, a separate toolchain, and touching game data files is more invasive than this
session's mandate). All six functions confirmed: widget construction, own-tracked visibility (not
`GetVisible()`), a direct `CallActionScriptCallback`, `SetFlashEventHandler` registration, a repaint thunk
firing exactly its requested tick count then self-stopping, and menu-nav polling running error-free.
`src/99_adopt.lua` (`Ess.Net`/`Ess.UI`/`Ess.Contract`) confirmed correctly detecting ModNet/uilib/
ContractFramework are NOT deployed in this install and logging that fact rather than erroring — the
alias-wiring itself is untestable further until one of those frameworks is deployed alongside Ess, but the
defensive existence-check path is proven correct.

**★ 2026-07-16 (overnight session) — Group J built and verified: `Ess.Override`.** `src/90_override.lua`
(`wrap`/`mergeIntoLiveTable`) live-tested: `wrap` correctly composes original+new logic, its double-wrap
guard refuses (and doesn't corrupt) a second wrap attempt on the same key, and `mergeIntoLiveTable`
confirmed to append into (never replace) the existing table object, preserving reference identity across
repeated merges — exactly the "tables are references" mechanic the wardrobe-unlock precedent relies on.

**Also discovered while testing tonight (a REPL/testing-methodology note, not an Ess bug):** passing a
multi-return-value expression directly as the sole argument to `tostring(...)` in this engine's Lua can
produce surprising results (observed `tostring(1, nil, nil, nil)` -> `"nil"`, `tostring(1, nil)` ->
a function-address string) — capture into a single named local first (`local r = f(); tostring(r)`),
never `tostring(multiReturnCall())` directly, when testing anything through `lua_repl.py`.

**★ 2026-07-16 (overnight session) — Group G built and behaviorally verified: the full tiered encounter
toolkit.** Per the required full re-read (not a prior summary) of both `ContractFramework.lua` (1265
lines) and `WaveDefense.lua` (1601 lines) in `mercs2-lua-mods`, done this session end to end. All 12 files
(Raw/Core/Easy × 4 namespaces) built, added to `build/merge.py`'s MANIFEST, and live-tested — as NEW
standalone code only, `ContractFramework.lua`/`WaveDefense.lua` themselves untouched, per the explicit
scope boundary:

- **`Ess.Relations`** (`src/61_relations_raw/61_relations/61_relations_easy.lua`) — unifies
  `ContractFramework`'s trigger-aware `def.relations` and `WaveDefense`'s snapshot-based `setupRelations`/
  `restoreRelations` into one implementation, fixing Known Bug #3 at the source (a failed original
  `Ai.GetRelation` read is now tracked as `{ok=false}` and logged, not silently collapsed into a skipped
  restore by `o1ok and o1`). Live-tested: `apply`/`restore` round-tripped VZ<->Guerilla exactly
  (100 -> -100 -> 100).
- **`Ess.Triggers`** (`src/62_triggers_raw/62_triggers/62_triggers_easy.lua`) — extracts `armTrigger`'s
  full condition vocabulary (immediate/once/recurring/proximity/onDestroy/onHealthBelow/onCleared; NOT
  ported: `onObjComplete`, which only means something inside a running Contract instance) plus a validated
  `gate(inputs, need, onFire)`. **Fixes the real gap found reading the source this session (Known Bug #2):**
  a gate's `inputs` can silently reference an id that was never a *named* trigger (e.g. a support/waypoint
  id), which then can never satisfy it — `Ess.Triggers.gate` now validates every input against the
  `armNamed` registry at creation time and logs loudly instead of hanging silently forever. Live-tested:
  `once`/`proximity` fired correctly, a 2-input gate fired only once both named triggers fired, and the
  exact validation warning fired for a deliberately-unregistered input id.
- **`Ess.AIOrders`** (`src/60_aiorders_raw/60_aiorders/60_aiorders_easy.lua`) — extracts the full
  `AI_BEHAVIORS` table (move/face/hold/defend/attack/patrol/follow/flee/enter/deploy/animate) + the
  `aiActor`/`aiPri` helpers into a standalone `command(guids, behavior, opts, tracker)`, with a standalone
  group registry (`setGroup`/`group`) replacing `inst.groups`. Live-tested on a real spawned `VZ Soldier`:
  `hold`/`face`/`move`/`attack`/`animate` all issued cleanly with zero errors and no bridge stall (the
  vehicle-related `enter`/`deploy` behaviors, and `patrol`/`follow`/`flee`, were built but NOT live-tested
  this session — deliberately, out of caution after the earlier vehicle-enter stall incident, not because
  of any known issue with them specifically).
- **`Ess.Sandbox`** (`src/63_sandbox_raw/63_sandbox/63_sandbox_easy.lua`) — the biggest unifying idea in
  the whole design: one `begin(id, providerNames, opts)`/`finish(id)` pair, with `Pg.SaveGame` gated for
  the whole duration (built on `Ess.Override.wrap` — the first real production use of it), over four
  built-in providers: `relations` (thin wrapper over `Ess.Relations`), `economy` (cash isolation, ported
  from `WaveDefense`'s `W.savedCash`/`restoreEconomy`), `supports` (HUD support-menu isolation, ported from
  `isolateSupports`/`restoreSupports`), `layers` (adopts `LayerFw` if deployed, existence-checked exactly
  like the `99_adopt.lua` aliases — confirmed API read directly from `LayerFw.lua`: `L.begin(sId)`/
  `L.finish(fCb)`). Live-tested: `economy`+`relations` together isolated cash to an exact `5000` and set a
  relation, then `finish` restored BOTH to their exact original values (`73400` cash, `100` relation); the
  save-gate boolean itself confirmed to transition `false->true->false` correctly across a real begin/
  finish cycle, including a real `Ess.Override.wrap` install onto `Pg.SaveGame`. `supports` and `layers`
  were NOT live-tested (supports needs a specific HUD widget state; layers needs `LayerFw` deployed
  alongside `Ess` in this install, which it isn't) — both are defensively existence-checked, matching the
  `99_adopt.lua` precedent, not fabricated confidence.

**Not built, and explicitly out of scope for this session:** `Ess.Mark`'s own tiered files (a smaller,
separately-specified piece not part of the four Group G namespaces above); refactoring
`ContractFramework.lua`/`WaveDefense.lua` themselves to actually CONSUME the new `Ess.*` code (a deliberate
scope boundary — that's a more invasive cross-repo change to an already-working, co-op-tested system, and
belongs in a reviewed follow-up, not an unsupervised session).

## Non-goals

- Not a replacement for `ModNet`/`uilib`/`ContractFramework`/`LayerFw`. Where one of those already solves
  a problem well (and is co-op-verified in the case of ModNet/uilib/ContractFramework), `Ess` **adopts**
  it as a dependency/provider rather than reimplementing it. Rebuilding a working, live-tested system from
  scratch for consistency alone is not worth the regression risk.
- Not a WAD/gfx authoring tool. `gfxforge`/`gfx_tool`/the movie-asset pipeline stay separate build-time
  tools; `Ess.Gfx` only wraps the **runtime** `FlashWidget` API a movie is driven through.
- Not a replacement for `lua-bridge` itself. `Loader.*`/`Tcp.*`/the script-loader hooks are the substrate
  `Ess` is built on, not something it wraps.

## Design principles

1. **Adopt, don't duplicate.** `ModNet` → `Ess.Net`, `uilib` → `Ess.UI`/`Ess.Menu`, `ContractFramework` →
   `Ess.Contract`, `LayerFw` → the `layers` provider inside `Ess.Sandbox`. Each keeps its own file/repo and
   its own global for backward compatibility; `Ess` just gives it a home in one coherent namespace tree and
   (where safe) reaches inside to promote an already-correct internal helper to public API (e.g.
   `ContractFramework`'s private `mark`/`markZone` becoming public `Ess.Mark`).
2. **Structural safety over documentation.** Where possible, make a footgun impossible to write rather
   than warning about it in a comment. Example: `Ess.Override.wrap` should accept only a shape that
   can't tail-call the original (see Known Bugs below) — not a helper that *could* be used wrong.
3. **Auto-tracked handles.** Every leak-prone `AddX`/`RemoveX` pair discovered in the namespace survey
   (`Marker`, `Event`, `Hud.Radar`, `Pda.Map`, `Object.AddQualityRef`, `Object.AddToDisposer`,
   `Pg.AddContextAction`) gets a shared tracking primitive (`Ess.Track`) instead of five independent
   ad-hoc `task.markers[#task.markers+1] = x` arrays like `ContractFramework` currently hand-rolls.
4. **One canonical name per concept.** The namespace survey found the same "which of these 4/7/8 getters
   do I want" problem repeatedly (`Player.*`, `Vehicle.*`, `Pg.FastCollect*`). `Ess` picks one name and an
   index/kind argument instead of exposing the native sprawl.
5. **One global, `_G.Ess`.** Short enough to type in a console one-liner; namespaced sub-tables for
   everything else (`Ess.Player`, `Ess.Bones`, ...).

---

## Tiered access model

Resolved by interview with Logan (2026-07-16): **three tiers, exposed as three parallel namespaces**,
each literally built on the one below it — `Ess.Easy.*` calls into `Ess.*`, `Ess.*` calls into
`Ess.Raw.*`. A beginner reading `Ess.Easy`'s own autocomplete/docs never has to know the other two exist.

- **`Ess.Raw.*` — composability.** The actual building blocks the other two tiers are assembled from
  (e.g. `Ess.Raw.Mark.radar`/`.pda`/`.world` as three independent calls, `Ess.Raw.Sandbox.register` for a
  brand-new provider). This is where an expert who wants to build something `Ess` didn't anticipate goes —
  not a "skip the safety checks" escape hatch, a "here are the actual primitives" one. Composed correctly,
  `Ess.Raw` can reconstruct everything `Ess.*` (Core) offers.
- **`Ess.*` (unqualified — "Core") — what most of this document already describes.** Named parameters,
  sensible defaults, explicit control over the well-known knobs (e.g. `Ess.Mark.object(uGuid, {radar=,
  pda=, world=})`). The tier a modder graduates to once they understand a concept well enough to want to
  override a default.
- **`Ess.Easy.*` — guardrails.** Optimizes for "hard to misconfigure" over flexibility: opinionated preset
  functions named for *intent*, not mechanism (`Ess.Easy.Mark.enemy(uGuid)`, not `Ess.Easy.Mark(uGuid,
  {radar=true, pda=true, world=false})`) — the convention knowledge (should an enemy get a world marker?
  should a hostile faction stay hostile to its own side?) is baked into the preset name so a newcomer
  never has to know it's a decision at all. Smallest possible surface area: a handful of named calls, not
  a config table.

**Scope — tiering only where it earns its keep**, decided per namespace as each one is actually designed,
not applied uniformly. Confirmed candidates so far (the ones with a real beginner/advanced gap):
`Ess.Mark`, `Ess.Sandbox`, `Ess.Triggers`, `Ess.AIOrders`, `Ess.Relations`, and a handful of `Ess.Easy.*`
presets sitting in front of the adopted `uilib`. Everything else in this document (Groups A, B, C, most of
F, H, I, J) stays **single-tier** — `Ess.RNG`/`Ess.Timer`/`Ess.Table`/etc. are already about as simple as a
beginner needs, and inventing an `Easy`/`Raw` split for them would just be three names for one thing. This
list isn't closed — a namespace can gain tiering later if implementation reveals a real gap, per the same
"does this earn it" test.

---

## Namespace catalog

Each entry: **status** (`NEW` = nothing like this exists yet · `ADOPT` = wrap/re-export an existing
framework unchanged · `EXTRACT` = pull working code out of `WaveDefense.lua`/`ContractFramework.lua` where
it's currently private · `PROMOTE` = make an already-correct private helper public), the problem, and a
concrete API sketch. Source column names which survey/read it came from (`DD`=deep-dives agent,
`NS`=namespaces agent, `OB`=onboarding agent, or a direct file read).

### Group A — Core primitives

| Item | Status | Problem | Sketch |
|---|---|---|---|
| `Ess.Safe.call(fn, ...)` | NEW | The `local ok, r = pcall(...); if not ok then Loader.Printf(...) end` shape is the single most duplicated line in the entire corpus (DD, OB, and every file we've directly read). | `ok, result = Ess.Safe.call(fn, ...)`, auto-logs failures via `Loader.Printf` unless a 3rd `bSilent` arg is set. |
| `Ess.Safe.string(ok, val, fallback)` | NEW | `SafeString` pattern from `world-inspector.md` — only trust a native return if `type(v)=="string"`. | direct port. |
| `Ess.Guid(name)` / `Ess.Name(guid)` | NEW | `Sys.StringToGuid`/`GuidToString` and `Pg.GetGuidByName` each have both a namespaced form and a bare-global alias — confusing duplicate surface (NS). `Sys.GuidToString` is confirmed to throw on at least one real object (DD, world-inspector.md). | pcall-wrapped, one canonical name each direction. |
| `Ess.Table.compact(t)` | EXTRACT | MissionForge's real, fixed bug: `t[#t]=nil` to "pop" leaves a nil hole that desyncs `#`/`ipairs`/`table.insert` (DD, mission-forge.md). | rebuild dense via `pairs()` + `table.sort`. |

### Group B — Identity & world query

| Item | Status | Problem | Sketch |
|---|---|---|---|
| `Ess.Player.character(i)` | NEW | The flagship ask. 8 overlapping getters: `GetLocalCharacter`/`GetPrimaryCharacter`/`GetSecondaryCharacter`/`GetAnyCharacter`/`GetLocalPlayer`/`GetPrimaryPlayer`/`GetSecondaryPlayer`/`GetCharacter(slot)` (NS). | `Ess.Player.character(0)` = local/primary, `Ess.Player.character(1)` = secondary (nil outside co-op, propagated safely — NS flagged raw `nil` flowing into a downstream `Object.*` call as a real risk). |
| `Ess.Player.slot(i)` | NEW | Same problem, player-guid form instead of character-guid. | mirrors `.character`. |
| `Ess.Player.camera(i)` | NEW | Every `Camera.*` call needs `Player.GetCamera(slot)` first — two-step boilerplate on every call site (NS). | resolves index → camera guid internally so `Ess.Camera.*` helpers can take a player index directly. |
| `Ess.Player.giveCash(i, n)` / `giveFuel(i, n)` | NEW | `Player.SetCash`/`AddCash`/`SetFuel`/`AddFuel` confirmed to silently skip the HUD refresh `MrxPmc.AddCashQty`/`AddFuelQty` trigger (NS). Also directly confirmed in `ContractFramework.lua`'s `grantReward` and `WaveDefense.lua`'s `addCash`, both of which already correctly route through `MrxPmc`. | routes through `MrxPmc` unconditionally — makes the correct choice the *only* choice. |
| `Ess.Player.pose(i)` | PROMOTE | `uilib.lua`'s private `pose()` (x,y,z,yaw,char,player) is exactly this, already correct, currently locked inside uilib. | promote to `Ess`, have `uilib`'s `UI.Menu` ctx call through it. |
| `Ess.Object.vehicleOf(uGuid)` | NEW | 4 overlapping entry points across 2 namespaces: `Object.InSeat`, `Object.InVehicle`, `Player.GetControlledObject`, `Vehicle.GetFromRider` (NS). Confirmed idiom (`vehicle-occupancy-inspector` project): **poll**, don't hook — there's no native "entered a vehicle" event with an unknown target vehicle. | one wrapper; `Ess.Object.pollVehicleChange(uChar, onChange)` for the watch-for-nil→guid idiom. |
| `Ess.Object.setInvincible(uGuid, bOn, reason)` | NEW | The reason-tag 3rd arg is easy to forget (NS) — should be required, not optional, in the wrapper even though the native call allows omitting it. | thin wrapper, non-optional 3rd param. |
| `Ess.Vehicle.driver(uVeh)` / `.riderOf(uChar)` | NEW | 7 overlapping getters: `GetDriver`/`GetRiders`/`GetFromRider`/`GetSeatFromRider`/`GetRiderFromSeat`/`GetFromSeat`/`GetSeatByType` (NS). | 2 canonical names cover the common cases; escape hatch to the raw namespace stays available for the rest. |
| `Ess.Vehicle.enterBestSeat` / `.enterSeatExcluding(uChar, uVeh, excl)` | EXTRACT | `MrxUtil.EnterBestAvailableSeat` d/g/p/c order, and the "partner never takes the driver seat" pattern, both confirmed live (DD, destroyer-vehicle.md). | pcall-wrapped ports. |
| `Ess.Vehicle.followGhost(template, x,y,z)` | EXTRACT | `Object.SetPosition` confirmed to silently not move a spawned human — respawn-and-verify is the only fix (DD, forgecam.md; also independently rediscovered in ForgeCam's ghost preview). | spawn → verify-drift-each-tick → respawn-if-drifted, generalized. |
| `Ess.Probe.nearby(pos, radius, kind, filter)` | NEW | `Pg.FastCollectHumans`/`GroundVehicles`/`Buildings`/`Flying`/`Tanks`/`Helicopters` (+ several unconfirmed siblings) are 11 separate names for "find nearby X" (NS). Already independently reimplemented as `collectInArea` in `ContractFramework.lua` and `sweepArena`/`adoptStrays`'s per-faction sweep in `WaveDefense.lua`. | one dispatcher; ports `ContractFramework`'s dedupe-by-guid-string logic (the correct existing implementation). |
| `Ess.Probe.getFaction(uGuid)` | EXTRACT | `MrxUtil.GetFaction` → `MrxFactionManager.GetFactionAbbrev` fallback chain, from `world-inspector.md`'s `DescribeTarget`. | direct port. |
| `Ess.Probe.describeSafe(uGuid)` | EXTRACT | Generic "explain this guid" (name/loc/health/model/faction), pcall'd with real diagnostic text on failure instead of a blank crash (DD, world-inspector.md). | direct port. |

### Group C — Timing & input

| Item | Status | Problem | Sketch |
|---|---|---|---|
| `Ess.Loop.start(id, interval, tickFn, needsTick)` | EXTRACT | The generation-guarded self-rescheduling `Event.TimerRelative` heartbeat is independently built at least **five** times: `uilib.lua`'s `ensureTick`, `contracts.lua`'s `poll()`, `WaveDefense.lua`'s main loop, plus ForgeMenu and MissionForge per the deep-dive survey (DD). `uilib`'s version is the most complete (generation counter, idle self-stop, `needsTick` predicate) — port that one. | `Ess.Loop.start(id, interval, fn, needsTick)` → auto-stops when `needsTick()` returns false, restarts on next `Ess.Loop.wake(id)`. |
| `Ess.Timer.start()` / `:elapsed()` | NEW | `Sys.RealTimeStamp`/`Sys.TimeStampMark`/`Sys.TimeStampGetElapsed` is a 3-call primitive reimplemented as a wall-clock delta in `uilib`, `WaveDefense`, ForgeCam, and MissionForge, specifically because `Event.TimerRelative` freezes under world-pause (NS, DD). | object wrapping the 3 calls, clamped delta (uilib clamps to 0.25s — keep that). |
| `Ess.Input.poll()` | EXTRACT | `Loader.PopKeyEvents()` (edge ring-drain) + `Loader.GetKeyboardState()` (held-state snapshot) is the *only* correct pattern — independently arrived at and documented as "2 calls/tick, never per-key `IsKeyDown` in a loop" in `uilib`, `contracts.lua`, ForgeMenu, and MissionForge, each after first getting it wrong and hitting a framerate bug (DD, OB, and this project's own `uilib-ui-kit`/`active-world-forge-project` memory). | `{pressed = {vk,...}, down = fn(vk)}` per tick; **the raw per-key `IsKeyDown`-in-a-loop pattern should not be exposed at all** — the whole point is making the mistake unavailable. |
| `Ess.Input.VkToChar(vk, shift)` | EXTRACT | The shifted-digit/punctuation table is byte-for-byte duplicated between `MasterCheatMenu.lua` and `CommonSpawnMenu.lua` (OB), and `uilib.lua`'s `CHAR` table is a third, near-identical copy. | one canonical table (uilib's is a good base — already handles A-Z/digits/punctuation). |
| `Ess.Input.hijackController(onInput)` / `.release()` | EXTRACT | The only way to get continuous analog input into Lua: find the `"PDA"` widget, `SetEventHandler("ControllerInput", fn)`, hide/show pair, fully reversible (DD, freecam.md/forgecam.md). | direct port, with the "letters-only nav while hijacked" reminder baked into the doc comment. |
| `Ess.TextConsole.open(opts)` | EXTRACT | The whole open/close/buffer/backspace/escape/poll-loop console pattern (~80 lines) is duplicated near-verbatim between two shipped cheat/spawn menus, including the cross-script mutual-exclusion check (OB). | one library instead of two hand-rolled consoles. |
| `Ess.State(name, defaults)` | NEW | The `_G.X = _G.X or {defaults}` idiom appears in every stateful `OnKey` script — and has a real, hit bug: a blind `or` silently drops newly-added fields on an existing session's table when the schema grows (DD, freecam.md's real bug; also see Known Bugs). | field-by-field merge (`for k,v in pairs(defaults) do if S[k]==nil then S[k]=v end end`), not a top-level `or`. |
| `Ess.SaveVar.ns(prefix)` | EXTRACT | Every mod hand-rolls its own `loadv`/`savev` + unlock-flag idiom over `Loader.SaveVar`/`LoadVar` — directly confirmed duplicated in `WaveDefense.lua`. | `local sv = Ess.SaveVar.ns("MyMod"); sv:get("xp", 0)`, `sv:set("xp", n)`, `sv:flag("unlock_x")`. |

### Group D — Tracking & cleanup

| Item | Status | Problem | Sketch |
|---|---|---|---|
| `Ess.Track.new()` | NEW | The single most leak-prone shape in the engine, repeated everywhere a handle must be remembered to clean up later: `Event.Create`→`Event.Delete`, `Marker.Add*`→`Marker.Remove`, `Hud.Radar:AddObjective`→`RemoveObjective`, `Pda.Map:AddBlip`→`RemoveBlip`, `Object.AddQualityRef`→`RemoveQualityRef`, `Object.AddToDisposer`→`RemoveFromDisposer`, `Pg.AddContextAction`→`RemoveContextAction` (NS). `ContractFramework.lua`'s `task = {events={}, guids={}, markers={}, marks={}}` + `cleanupTask` is a *correct* hand-rolled instance of exactly this, repeated with variations in `WaveDefense.lua` (`W.drops`, `W.crates`, `run.enemies`). | a generic registry: `local t = Ess.Track.new(); t:event(Event.Create(...)); t:marker(Marker.AddBlip(...)); t:closeAll()` — `ContractFramework`'s task-cleanup becomes a thin wrapper over this instead of its own bespoke arrays. |
| `Ess.Event.on(type, args, cb)` | EXTRACT | Wraps `Event.Create`, returns a tracked handle; validates the args-table shape against the event type before calling (a wrong shape doesn't error, it just silently never fires — NS). | thin wrapper + `Ess.Track` integration. |
| `Ess.Mark.object(uGuid, opts)` / `.zone(x,y,z,r,opts)` / `.clear(handle)` | PROMOTE | `ContractFramework.lua`'s private `mark`/`markZone`/`unmarkZone` (lines ~86–132) mark all **three** surfaces unconditionally (round radar `Hud.Radar:AddObjective`, PDA `Pda.Map:AddBlip`, in-world `Marker.AddBlip`/`AddDisc`). `WaveDefense.lua`'s `addEnemyBlip` deliberately marks radar+PDA **only**, skipping the world marker — confirmed **intentional** (Logan: not every marked thing should also clutter the world with a floating icon), not a gap. **This is the motivating example for the tiered design below**: the correct primitive isn't "always mark all three," it's three independent surface toggles (`opts.radar`/`opts.pda`/`opts.world`, each default-on) — `ContractFramework`'s all-three call and `WaveDefense`'s radar+PDA-only call become two different `opts` values against the *same* underlying helper instead of two different implementations. | keyed by guid string, torn down together regardless of which surfaces were used; `ContractFramework` and `WaveDefense` both become consumers of the one shared, fully-configurable implementation. |

**Tiered breakdown — `Ess.Mark`** (the motivating example for the whole tiering model, see the interview
note above):
- `Ess.Raw.Mark.radar(uGuid, tex, rgb)` / `.pda(uGuid, tex)` / `.world(uGuid, tex, rgb)` — the three
  surfaces as fully independent calls, each pcall-wrapped and returning its own handle. `ContractFramework`'s
  `mark()` decomposed into its three constituent native calls (`Hud.Radar:AddObjective`, `Pda.Map:AddBlip`,
  `Marker.AddBlip`).
- `Ess.Mark.object(uGuid, {radar=true, pda=true, world=true})` — one call, all three toggles default-on,
  invokes whichever `Ess.Raw.Mark` primitives it needs and returns one combined handle for `Ess.Mark.clear`.
  This is the row above; `ContractFramework`'s existing all-three call and `WaveDefense`'s radar+PDA-only
  call both become this same function with different `opts` — no more forking into two implementations.
- `Ess.Easy.Mark.enemy(uGuid)` (→ radar+PDA, no world icon — matches `WaveDefense`'s real convention),
  `Ess.Easy.Mark.objective(uGuid)` (→ all three — matches `ContractFramework`'s convention),
  `Ess.Easy.Mark.zone(x,y,z,r)` (→ world ring only, the ground-disc "go here" case). A beginner picks the
  preset matching what they're marking and never sees a bool.

### Group E — UI / GFX

| Item | Status | Problem | Sketch |
|---|---|---|---|
| `Ess.Gfx.widget(file, x, y, w, h)` | EXTRACT (bug-fix) | `MrxGuiBase.FlashWidget:new()`+`SetOwner`+`SetLocation`+`SetSwfFile`+`AddWidget`+`SetVisible`+`AddWidgetToHud` boilerplate, duplicated in `uilib.lua`, `contracts.lua`, and (per DD) `custom-ui.md`/`forgecam.md`/`forge-menu.md`. **`uilib.lua`'s version is correct** (`SetLocation(x, y, x+w, y+h)` — corner coords); **`contracts.lua`'s own `make_widget` (line 55) and its `build()` (line 126) are NOT** — they still pass `SetLocation(x, y, w, h)`, the pre-fix convention `uilib` v2.1 already found and corrected elsewhere in the same repo. It happens not to visibly break by luck (the board renders ~10% smaller than intended, same as the still-unfixed ForgeMenu/MissionForge/ForgeCam instances), but it's a live, currently-shipping instance of an already-solved bug. | one constructor, corner-coordinate math done once, impossible to get wrong afterward — fixes `contracts.lua`'s bug at the source instead of needing a 5th independent fix. |
| `Ess.Gfx.call(widget, fn, args)` | EXTRACT | pcall-wrapped `CallActionScriptCallback`, hand-written ad hoc everywhere. | thin wrapper. |
| `Ess.Gfx.onEvent(widget, name, cb)` | EXTRACT | pcall-wrapped `SetFlashEventHandler` with the required `(_, v)` parameter shape and mandatory trailing `{}` (DD, custom-ui.md). | thin wrapper, gets the shape right so it can't be gotten wrong. |
| `Ess.Gfx.setVisible(widget, bool)` | NEW (bug-fix) | `GetVisible()` (not `IsVisible()`, which silently nil-calls) returns `1`/`0`, and `not 0` is `false` in Lua — a naive `SetVisible(not w:GetVisible())` toggle never flips. Confirmed hit bug (this project's own `wiki` CLAUDE.md, and DD's custom-ui.md). | tracks an owned boolean in the widget wrapper's own state; never reads `GetVisible()` back to decide. |
| `Ess.Gfx.warmupRerender(rt, ticks)` | PROMOTE | `SetSwfFile` is async — a paint immediately after building drops (movie not loaded yet). `uilib.lua`'s `WARMUP=8`-tick re-paint-on-show is the correct fix, already built. | promote from uilib. |
| `Ess.Gfx.menuNav(widget, keys)` | PROMOTE | Edge-triggered Up/Down/Enter → `SetSelected`, needed because a HUD widget gets no native input of its own. `uilib.lua`'s `navName`/list nav is the reference implementation. | promote the input-mapping half; `Ess.Menu` (below) is the full widget. |
| `Ess.ScrollLog.new(name, x,y,w,h)` | EXTRACT | `MrxGuiTextBuffer` via the direct `HandleInstantiationEventForTextBuffer` call — never the documented `InstantiateTextBuffer`, which crashes on a real shipped engine bug (`oWidget` undefined in its own scope). This ~30-line workaround is duplicated near-verbatim between `CoopChatUI` and `WorldProbeLogUI` (DD). Also: display-duration × message-count is real queued wall-clock time — a 194-line dump at a 15s default once blocked a UI for ~50 minutes (DD, world-inspector.md) — the port should default to a short duration for bulk dumps. | one library instead of two hand-rolled copies, with the duration-scaling guard built in. |
| `Ess.Menu` / `Ess.UI` | ADOPT | `uilib.lua`'s `UI.Menu`/`List`/`Panel`/`Bar`/`Toast`/`Confirm`/`Input`/`Chat`/`Board` is a mature, engine-verified 9-widget kit built on the exact `Ess.Loop`/`Ess.Input`/`Ess.Gfx` primitives above. | `Ess.UI = UI` (alias) once uilib itself is rebased onto the shared primitives — no reimplementation. |

**Tiered breakdown — UI:** `Ess.Gfx` above already *is* the `Ess.Raw` tier for widgets (raw FlashWidget
primitives); the adopted `uilib`/`Ess.UI` is the Core tier — it's already fairly friendly, so most UI work
doesn't need an Easy tier at all. A thin `Ess.Easy` layer covers only the handful of single-call cases
that don't need the widget-object API: `Ess.Easy.Toast(msg)`, `Ess.Easy.Confirm(text, onYes)`,
`Ess.Easy.Menu(title, {label=fn, ...})` (a flat, non-nested menu — no `:category` concept). `UI.Menu`'s
full nesting/`:switch`/`ctx:confirm` power stays one tier up, at Core.

### Group F — World manipulation

| Item | Status | Problem | Sketch |
|---|---|---|---|
| `Ess.Bones.attachFX(uGuid, bone, template)` / `.detachFX` | EXTRACT | The 3-call attach recipe (`Pg.Spawn` the FX → `Object.Attach(char, bone, fx)` → `Object.SetTransformToObject(fx, char, bone)`) confirmed live end-to-end in `human-skeleton-boneprobe` (fire/smoke/flares on 30 finger joints). | direct port of the confirmed recipe. |
| `Ess.Bones.waitForReady(uGuid, cb, maxTries)` | EXTRACT | A freshly `Pg.Spawn`'d model's hardpoints return nil for ~0.3s — confirmed gotcha (bone-manipulation deep-dive, `human-skeleton-boneprobe` memory). | poll `GetHardpointPosition` until non-nil instead of reading synchronously at spawn. |
| `Ess.Bones.aimVector(uGuid, hpBase, hpTip)` | EXTRACT | Turret aim = the vector between two hardpoints (e.g. `hp_seat_cannon`→`hp_barreltip_cannon`), confirmed on the destroyer — this is genuinely new capability the destroyer deep-dive originally said wasn't Lua-reachable, until the bone-probe work proved otherwise. | direct port. |
| `Ess.Bones.probeNames(uGuid, prefixes, suffixes)` | EXTRACT | The prefix×suffix pcall-probe pattern from `DestroyerTool.ProbeHardpoints`, generalized. Comes with a hard caveat worth keeping attached: `GetHardpointPosition` is confirmed **hash-keyed** (`pandemic_hash_m2`) — a garbage string can collide onto a real bone and return real coordinates, so a probe hit is not proof of a "real" name. | keep the caveat in the doc comment; this is a research tool, not a production API. |
| `Ess.Camera.lookAtAnchor(x,y,z)` | EXTRACT | `Camera.SetPosition` silently no-ops without an active `SetLookAt` binding — the fix is spawning a `"Verification Camera"` anchor prop + one `SetLookAt` (DD, freecam.md). **Caveat directly confirmed this session:** `Pg.Spawn("Verification Camera")` into a *live, running* world triggers a support/camera call-in that fails and despawns — it's only safe as a paused-world anchor (ForgeCam), never mid-gameplay (`ContractFramework`'s own dive found this the hard way; its zone markers use a `TinyGeometry` anchor instead for exactly this reason). `Ess.Camera`'s port must carry the same caveat or default to `TinyGeometry`. | port with the corrected anchor choice built in as the default. |
| `Ess.Camera.staleAxisDecay(axes, timeoutMs)` | EXTRACT | Force stick axes to 0 after silence — the engine omits idle fields instead of sending a final 0 (DD, freecam.md). | direct port. |
| `Ess.Camera.followHardpoint(uGuid, hp)` | EXTRACT | Per-tick `GetHardpointPosition`→`SetPosition`/`SetLookAt`, the confirmed fallback for a dynamic (moving) vehicle where the object+hardpoint camera form no-ops. | direct port. Keep namespaced separately from **`Ess.RenderCamera`** (LOD/FOV/near-far) — `Camera` and `Graphics.Camera` are two unrelated APIs that share only a name, a confirmed cross-namespace footgun (NS). |
| `Ess.Points.bucket(spawnList)` | EXTRACT | Arena spawn points tiered by radius (≤5 infantry / ≤15 vehicle / >15 heli) — directly confirmed working in `WaveDefense.lua`'s `bucketArena`, the natural runtime counterpart to a MissionForge arena export. | direct port. |
| `Ess.Points.ideal(pts, refX, refZ, opts)` | EXTRACT | Distance-windowed spawn-point selection (nearest-first, min/max radius, capped count) — `WaveDefense.lua`'s `idealPoints`, generalized beyond wave-defense. | direct port. |
| `Ess.RNG.new(seed)` | EXTRACT | Engine Lua numbers are 32-bit float — the obvious big Park-Miller LCG (`state*16807 mod 2^31`) silently degenerates because 2^31 exceeds the exact-integer ceiling (2^24). `WaveDefense.lua`'s ZX-Spectrum small-LCG (`state*75 mod 65537`) is the confirmed, engine-verified fix. This is exactly the kind of fact a new modder will otherwise only learn by watching every crate/unit roll come out identical. | `local r = Ess.RNG.new(); r:next() -> 0..1`, so multiple mods get independent sequences instead of sharing one `WaveDefense`-global stream. |
| `Ess.RNG.weightedPick(list, weightKey)` | EXTRACT | The same accumulator-loop weighted-pick is written **three separate times** inside `WaveDefense.lua` alone (`pickUnit`, `pickDrop`, `pickCrate`) — same logic, copy-pasted. | one implementation. |

### Group G — Encounter / gameplay toolkit

*(This whole group already exists, fully built, inside `ContractFramework.lua` — but locked behind "is there an active contract." The point of this group is making it usable standalone, which directly unblocks the stalled Active-World director project.)*

| Item | Status | Problem | Sketch |
|---|---|---|---|
| `Ess.AIOrders` | EXTRACT | `ContractFramework.lua`'s `AI_BEHAVIORS` table (`move`/`patrol`/`defend`/`attack`/`hold`/`face`/`follow`/`flee`/`enter`/`deploy`/`animate`) is a complete, well-designed "command a group of spawned units" API, built entirely on confirmed `Ai.Goal`/`Ai.Anchor`/`Ai.Deploy` primitives, with the `aiActor()` driver-not-hull targeting rule already correct. Currently only reachable through `def.waypoints` inside a running contract. | extract the behavior table + `groupGuids`/`aiActor`/`aiPri` helpers into a standalone `Ess.AIOrders.command(guids, behavior, opts)`; `ContractFramework`'s own waypoint runner becomes a thin consumer of it. |
| `Ess.Relations` | EXTRACT | Faction snapshot→apply→restore, independently built **three times**: `ContractFramework.lua`'s `def.relations` (generic, trigger-aware), `WaveDefense.lua`'s `setupRelations`/`restoreRelations` (snapshot-based, records original `GetRelation` values first), and (per project memory) `TerritorialWar`. `ContractFramework`'s version has one confirmed gap: if the original `Ai.GetRelation` read fails, that direction is silently never restored — worth fixing while unifying. | one implementation both `ContractFramework` and any future gamemode call; fixes the silent-restore-skip. |
| `Ess.Triggers` | EXTRACT | `ContractFramework.lua`'s `armTrigger` engine (immediate/once/recurring/proximity/onDestroy/onHealthBelow/onObjComplete/onCleared, plus `all`/`count` logic gates) is a complete declarative trigger system, currently reachable only via `def.support`/`def.waypoints`/`def.triggers`. **Confirmed real gap found this session:** a logic gate's `inputs` list can only reference ids that are themselves declared as *named* `def.triggers` entries — an id belonging to a `def.support`/`def.waypoints` entry (even one with its own inline `trigger` condition) never populates `inst.trigFired` and so can never satisfy a gate, contradicting the worked example on the framework's own wiki page. `Ess.Triggers` should validate gate inputs against the named-trigger table at registration time and fail loudly instead of silently never firing. | extract `armTrigger`/`namedTrig`/the gate-poll loop into `Ess.Triggers.arm(spec, onFire)` / `Ess.Triggers.gate(inputs, need, onFire)`, with the validation fix. |
| `Ess.Sandbox` | EXTRACT | The single biggest unifying idea in this whole design. `LayerFw.lua`'s `begin`/`add`/`remove`/`swap`/`expect`/`finish` (snapshot → apply → **guaranteed** restore, with `Pg.SaveGame` gated the entire time so a crash mid-mode just leaves the pre-mode vanilla state) and `WaveDefense.lua`'s independently-built cash isolation (`isolateSupports`/`restoreSupports`, `restoreEconomy`, the `Pg.SaveGame` wrap in `WaveDefense.lua` itself) are **the same pattern applied to two different resources**, written twice, with `WaveDefense`'s copy duplicating the save-gate `LayerFw` already solved generically. | `Ess.Sandbox.register(name, {snapshot=fn, apply=fn, restore=fn})` — providers: `layers` (= `LayerFw`, finally wired in as the project's own memory has been flagging since 2026-07-12), `economy`, `supports`, `relations` (= `Ess.Relations` above). `Ess.Sandbox.begin(id, providerNames)` / `.finish(id)` drives every registered provider through one save-gated snapshot/restore, instead of one hand-rolled copy per gamemode. |

**Tiered breakdown — the encounter toolkit:**

| Namespace | `Ess.Raw.*` (composability) | `Ess.*` (Core, as specified above) | `Ess.Easy.*` (guardrails) |
|---|---|---|---|
| Sandbox | `Sandbox.register(name, {snapshot,apply,restore})`, direct `gateSaves()`/`ungateSaves()` — write your own provider. | `Sandbox.begin(id, providerNames)` / `.finish(id)` over the built-in providers (layers/economy/supports/relations). | `Sandbox.arena(id)` — begins with every built-in provider on, no provider list to think about; `Sandbox.done(id)` closes it out. |
| Triggers | `Triggers.arm(spec, onFire)` — one condition primitive at a time, the extracted `armTrigger`, full vocabulary. | `Triggers` — named triggers + `fires` lists + `all`/`count` logic gates (with the gate-input validation fix from Known Bugs #2). | `Triggers.onPlayerNear(x,y,z,r,fn)` / `.onDeath(uGuid,fn)` / `.after(seconds,fn)` — the handful of single-purpose cases that cover most real usage, no `spec` table syntax. |
| AIOrders | direct `aiActor`/`aiPri` + the raw `Ai.Goal`/`Ai.Anchor`/`Ai.Deploy` shapes — for a behavior not in the built-in list. | `AIOrders.command(guids, behavior, opts)` — the 11 behaviors as designed above. | `AIOrders.attack(guids, target)` / `.patrol(guids, points)` / `.guard(guids, at)` — named calls hiding `opts`. |
| Relations | snapshot/apply/restore primitives directly over `Ai.GetRelation`/`SetRelation`. | `Relations` — `{a,b,set}` tuples as designed above, with the restore-on-failed-read fix from Known Bugs #3. | `Relations.makeHostile(factionList)` / `.makeAllies(factionList)` — the two genuinely common presets, no `"friend"/"enemy"` vocabulary to learn. |

### Group H — Networking

| Item | Status | Problem | Sketch |
|---|---|---|---|
| `Ess.Net` | ADOPT | `ModNet.lua` is a mature, co-op-verified library (`Shared`/`Set`/`Get`/`Track`, `On`/`Send`, `OnRaw`/`SendRaw`, `IsCoop`/`IsHost`/`IsAuthority`, the v1.2 ready-gate handshake) with real, hard-won fixes behind it (the MAGIC-marker collision fix, the ready-gate late-join fix). Not touching its internals. | `Ess.Net = ModNet` (alias) once ModNet itself optionally sits on `Ess.Loop`'s heartbeat instead of its own inline one, for consistency only — not because it's broken. |
| `Ess.Net.hijackCallback(moduleName, name, dispatch)` | NEW | `ModNet` solved *one specific* hijack (`MrxFactionManager.NetEventCallback`) correctly: capture-original-in-a-local, marker-tagged packets only, pcall the receive, never tail-call the original. That exact recipe is reusable for any other always-resident callback a future mod wants to safely extend, not just this one. | a generic "safely extend an existing engine callback without swallowing others' traffic" helper, modeled on `ModNet`'s own fix — not a `ModNet` replacement, a generalization of the *technique* `ModNet` proved. |

### Group I — Missions

| Item | Status | Problem | Sketch |
|---|---|---|---|
| `Ess.Contract` | ADOPT | `ContractFramework.lua` is the whole ephemeral-mission engine — `Register`/`Accept`/`Abort`/`Status`, 15 objective types, the task lifecycle. Not rebuilding this. | `Ess.Contract = Contract` (alias). `Ess`'s own docs should steer newcomers here *instead of* the native `WifMissionData`/`dynamic_import` path — the native path's landmines (never wrap `dynamic_import`, contracts need `bContract=true` or `IsMissionAContract` silently lies, lifecycle callbacks fire with **zero** arguments) are exactly the class of problem `ContractFramework` exists to make irrelevant, not something `Ess` needs its own helpers for. |

### Group J — Meta

| Item | Status | Problem | Sketch |
|---|---|---|---|
| `Ess.Override.wrap(target, name, newFn)` | NEW | Confirmed engine-wide crash pattern, not contract-specific: `return fOriginal(...)` inside a wrapper is a **tail call** that collapses the stack frame, breaking this engine's `getfenv(n)`-based module resolution. Hit as real crashes in the custom-contract deep-dive; the correct pattern (capture original in a local, call-then-return-as-a-second-statement, guard re-wrap via a flag) is already used correctly in `ModNet.lua`'s own hijack and `world-inspector.md`'s `SpawnScraper`. | accept only a function shape that makes the tail-call mistake syntactically unavailable — e.g. `Ess.Override.wrap` captures the original itself and always calls `local a,b,c = orig(...); return a,b,c` internally, so the caller's `newFn` never touches `orig` directly at all. |
| `Ess.Override.mergeIntoLiveTable(t, key, data)` | EXTRACT | Prefer merging new data into a live table over replacing the function that reads it — every downstream reader keeps working unmodified (DD, function-override.md's wardrobe-unlock case). | direct port. |

---

## Known bugs this design should fix at the source

Concrete, currently-real issues surfaced during this research pass — not hypothetical footguns:

1. **`contracts.lua`'s `make_widget`/`build()` still use the pre-fix `SetLocation(x,y,w,h)`** (lines 55 and
   126) instead of `uilib.lua`'s corrected `SetLocation(x,y,x+w,y+h)`. Currently harmless by luck (renders
   slightly small), but it's a live regression of an already-solved bug in a sibling file of the same repo.
2. **Trigger logic gates (`kind="all"/"count"`) can silently never fire** if any of their `inputs` names a
   `def.support`/`def.waypoints` id rather than a named `def.triggers` id — contradicts the framework's own
   documented worked example. `Ess.Triggers` should validate this at registration and fail loudly.
3. **`ContractFramework.lua`'s relation restore silently skips a direction whose original `Ai.GetRelation`
   read failed** — the pre-existing stance is lost rather than restored. Fix while unifying into
   `Ess.Relations`.
4. **`Object.GetVisible()` not `IsVisible()`** (which doesn't exist and nil-calls silently under `pcall`),
   and **`not w:GetVisible()` is *also* wrong** even with the right name, since the getter returns `1`/`0`
   and only `nil`/`false` are falsy in Lua. `Ess.Gfx.setVisible` must track its own boolean, never read the
   getter back to decide.
5. **`Player.SetCash`/`AddCash`/`SetFuel`/`AddFuel` silently skip the HUD refresh** that `MrxPmc.AddCashQty`/
   `AddFuelQty` trigger — `Ess.Player.giveCash`/`giveFuel` must hard-route through `MrxPmc`, no raw-setter
   option.
6. **The `X and false or Y` ternary substitute breaks when `X`'s "true" value is itself `false`** — hit as a
   real load-time crash in `WaveDefense.lua`'s `loadMods` (indexed `mod.vals` for a toggle, which has none).
   Worth a lint-style callout in `Ess`'s own contributor docs even though it can't be fixed by a wrapper.
7. **`_G.X = _G.X or {defaults}` silently drops newly-added fields** on an existing session's table once the
   schema grows — a real, hit bug (`freecam.md`). `Ess.State` merges field-by-field instead.
8. **A blank/whitespace `Pg.Spawn` template string hard-crashes the engine even through `pcall`** — native
   crashes can't be caught, only Lua errors can. `uilib.lua`'s `ctx:spawn` already validates this up front;
   every `Ess` helper that reaches `Pg.Spawn` must do the same validation before the call, not rely on
   `pcall` to make it safe.
9. **Tail-calling the original inside an override (`return fOriginal(...)`)** collapses the stack frame and
    breaks the engine's module system — see `Ess.Override` above.

**Not a bug, corrected:** an earlier draft of this document flagged `WaveDefense.lua`'s radar+PDA-only enemy
blips as a gap versus `ContractFramework`'s all-three-surface marking. That was wrong — it's a deliberate
design choice (not every marked object should also get a floating world icon), and it's the reason
`Ess.Mark` is specified with three independent surface toggles rather than an all-or-nothing default. See
the Group D table above and the tiering discussion below.

---

## Repo / build architecture

Per-namespace source files under `src/`, concatenated by a build script into one deployable file — the
same shape this project already uses for `gfxforge-web`'s `build.py` bundler and the `mercs2-name-cracker`/
`bone_dump` pipelines, so it's a familiar pattern rather than a new convention.

```
mercs2-lua-essentials/
  FEATURE_SHEET.md        <- this document
  README.md
  src/
    00_core.lua            Ess bootstrap, Ess.Safe, Ess.Table, Ess.Guid
    10_player.lua           Ess.Player
    11_object.lua           Ess.Object
    12_vehicle.lua           Ess.Vehicle
    13_probe.lua            Ess.Probe
    20_loop.lua             Ess.Loop, Ess.Timer
    21_input.lua            Ess.Input, Ess.TextConsole
    22_state.lua            Ess.State, Ess.SaveVar
    30_track.lua            Ess.Track, Ess.Event
    31_mark_raw.lua         Ess.Raw.Mark      (radar/pda/world as 3 independent calls)
    31_mark.lua             Ess.Mark          (Core: opts-driven object/zone)
    31_mark_easy.lua        Ess.Easy.Mark     (enemy/objective/zone presets)
    40_gfx.lua              Ess.Gfx = Ess.Raw's widget primitives (the Raw tier of UI)
    41_scrolllog.lua         Ess.ScrollLog
    50_bones.lua            Ess.Bones
    51_camera.lua            Ess.Camera
    52_points.lua            Ess.Points
    53_rng.lua               Ess.RNG
    60_aiorders_raw.lua     Ess.Raw.AIOrders
    60_aiorders.lua         Ess.AIOrders
    60_aiorders_easy.lua    Ess.Easy.AIOrders
    61_relations_raw.lua    Ess.Raw.Relations
    61_relations.lua        Ess.Relations
    61_relations_easy.lua   Ess.Easy.Relations
    62_triggers_raw.lua     Ess.Raw.Triggers
    62_triggers.lua         Ess.Triggers
    62_triggers_easy.lua    Ess.Easy.Triggers
    63_sandbox_raw.lua      Ess.Raw.Sandbox
    63_sandbox.lua          Ess.Sandbox
    63_sandbox_easy.lua     Ess.Easy.Sandbox
    90_override.lua          Ess.Override
    95_ui_easy.lua           Ess.Easy.Toast/Confirm/Menu (thin presets over Ess.UI)
    99_adopt.lua             aliases: Ess.Net=ModNet, Ess.UI=UI, Ess.Contract=Contract
  build/
    merge.py                concatenates src/*.lua in an EXPLICIT manifest order (not a naive
                             alphabetical glob) -> dist/Essentials.lua, stamps a version/build-date
                             header banner
  dist/
    Ess.lua                  (generated; open question below on whether this is committed)
```

Numeric filename prefixes double as both load-order (matching the existing `1_`-prefix lua-bridge
convention this project already uses for framework files) and a visual grouping in a file browser —
`00`–`13` never depend on anything below them, `90`/`99` depend on everything. **Within a tiered group,
alphabetical filename order does NOT match dependency order** (`_mark.lua` sorts before `_mark_easy.lua`
sorts before `_mark_raw.lua`, but Raw must load first, then Core, then Easy) — `merge.py` keeps an
explicit ordered file list for exactly this reason rather than globbing and sorting.

## Relationship to existing frameworks — the migration story

- **`ModNet`, `uilib`, `ContractFramework`, `LayerFw` keep their own repos/files and globals.** Nothing
  about how `WaveDefense.lua` currently deploys (`1_ModNet.lua`, `1_uilib.lua`, `1_ContractFramework.lua`)
  needs to change on day one.
- `Ess` ships as its own `1_Ess.lua` (or similarly prefixed), loaded alongside them. Its `99_adopt.lua`
  aliases (`Ess.Net`, `Ess.UI`, `Ess.Contract`) only activate if the corresponding framework is already
  loaded — existence-checked, never a hard dependency.
- `LayerFw` is the one framework this design asks to change: its `begin`/`add`/`remove`/`swap`/`expect`/
  `finish` API becomes the `layers` provider registered with `Ess.Sandbox`, finally wiring it into a real
  consumer (this project's own memory has flagged "wire LayerFw into WaveDefense" as the next step since
  2026-07-12 and it never happened).
- `ContractFramework`'s private `mark`/`markZone`/`AI_BEHAVIORS`/`armTrigger`/relations code gets promoted
  to public `Ess.*` namespaces; `ContractFramework` itself becomes a (thin, mechanically verified)
  consumer of its own former internals, not a rewrite.
- `WaveDefense.lua` is the biggest beneficiary and the biggest migration effort: its private RNG,
  weighted-pick (×3), economy/support isolation, relations setup/restore, arena bucketing, and blip
  marking all become `Ess.*` calls, and the file should get visibly *smaller*. This migration is **not**
  part of this design pass — flagged here so it's an explicit, deliberate follow-up, not scope creep now.

## Open questions (before implementation starts)

1. ~~**Naming:** `Ess` vs `Essentials` vs something else as the actual global.~~ **Resolved:** `Ess`.
2. **`Ess.RNG` — shared global stream or per-consumer instances?** `WaveDefense.lua` uses one shared
   `W._rng`. Multiple mods sharing one `Ess`-global stream would perturb each other's sequences if both
   draw from it in the same tick — instanced (`Ess.RNG.new()`) avoids that at the cost of every consumer
   remembering to hold onto their own instance.
3. **Is `dist/Ess.lua` committed to the repo**, or built on demand / at release time only? Committing
   it makes "just drop this one file in" trivially copy-pasteable for a newcomer; not committing it keeps
   the repo free of generated-file diffs. (The `gfxforge-web` precedent commits neither — `dist/` is built
   on demand there.) **Currently: not committed** (`dist/` is gitignored) — revisit once there's a release
   to actually ship, not just a working build.
4. **How much of Group G (`AIOrders`/`Relations`/`Triggers`/`Sandbox`) ships in v1** versus being deferred —
   this is the highest-value, highest-effort, highest-regression-risk group since it means touching
   `ContractFramework.lua`'s internals. Could ship v1 with Groups A–F only (zero changes to any existing
   framework) and treat G as a v2 that revisits `ContractFramework`/`WaveDefense` deliberately.
5. **Versioning/compat policy** once other mods start depending on `Ess` directly, mirroring the
   `MODULE_ASSETS`-style versioning `mercs2-lua-mods`' `repository.json` already uses for `lua-bridge`/
   `lua-menu-widgets`.

## Suggested build order (once the sheet above is approved)

1. Group A + C (core primitives, loop/timer/input/state) — zero dependencies, immediately useful standalone,
   zero risk to existing frameworks.
2. Group B + D (identity/query + tracking) — still zero risk, builds on 1.
3. Group F (bones/camera/points/RNG) — zero risk, mostly ports of already-confirmed-working code.
4. Group E (`Ess.Gfx`) + the `Ess.UI`/`Ess.Net`/`Ess.Contract` aliases — first point of contact with the
   existing frameworks, but as additive aliases, not edits to their source.
5. Group G — the deliberate, higher-risk pass that actually opens up `ContractFramework.lua` and
   `WaveDefense.lua` internals. Do this only once 1–4 are stable and (ideally) after a co-op smoke test of
   whatever's live at the time. **Internal order within each tiered namespace: Raw first (it's the
   extraction of what already works inside `ContractFramework`/`WaveDefense`, zero new design), then Core
   (already fully specified above), then Easy last** (its presets are just opinionated calls into Core, so
   it can't be designed correctly until Core exists) — this applies to `Mark` (Group D) too, not just
   Group G.
6. `Ess.Override` (Group J) can land any time after step 1 — it has no dependents yet, it's just a safety
   primitive waiting to be used by whichever later group needs it first.
