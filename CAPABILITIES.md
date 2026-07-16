# Ess — Capabilities Reference

What the `Ess` framework can do **right now**, organized by what you reach for. This is the current-state
reference; for *why* things are the way they are (the design history, the absorption pivots, the bug hunts),
see [FEATURE_SHEET.md](FEATURE_SHEET.md) — that's the append-only build log, this is the map of the finished
building.

`Ess` (`_G.Ess`) is one global. Deploy `dist/Ess.lua` (built with `python build/merge.py`) as an OnLoad
script — nothing else is required; the four frameworks it grew out of (uilib, ModNet, ContractFramework,
LayerFw) are all absorbed natively, not dependencies.

## The three tiers

Most namespaces expose one or more of three parallel tiers. Use the highest one that fits:

- **`Ess.Easy.*`** — guardrails. Intent-named presets (`Ess.Easy.Mark.enemy(guid)`), smallest surface, hard
  to misconfigure. Where a beginner starts.
- **`Ess.*`** (unqualified, "Core") — named parameters and sensible defaults with full control. Where you go
  when you want to override a default.
- **`Ess.Raw.*`** — the building blocks the other two are assembled from, for composing something Ess didn't
  anticipate. Not a "skip the safety" hatch — the actual primitives.

Tiering is selective — only namespaces with a real beginner/advanced gap have all three (Mark, AIOrders,
Relations, Triggers, Sandbox). Simple namespaces (RNG, Time, Table…) are single-tier.

---

## Core primitives

| Namespace | What it's for | Key calls |
|---|---|---|
| `Ess.Safe` | The `pcall`-and-log idiom, once | `.call(fn, ...)`, `.quiet(fn, ...)`, `.string(ok, val, fallback)` |
| `Ess.Table` | Dense-array repair | `.compact(t)` (rebuild after a nil hole) |
| `Ess.Guid` / `Ess.Name` | Name↔guid, pcall-wrapped | `Ess.Guid(name)`, `Ess.Name(guid)` |
| `Ess.Log` | One line to the bridge log | `Ess.Log(msg)` |
| `Ess.State` | Reload-safe `_G` state, field-merged | `Ess.State(name, defaults)` (adding a default later still takes effect) |
| `Ess.SaveVar` | Namespaced persistent vars over `Loader.SaveVar` | `Ess.SaveVar.ns(prefix)` → `:get/:set/:flag/:setFlag` |
| `Ess.RNG` | Engine-safe RNG (avoids the 32-bit-float big-LCG trap) | `Ess.RNG.new(seed)` → `:next/:int/:pick/:chance` |

## Identity & world query

| Namespace | What it's for | Key calls |
|---|---|---|
| `Ess.Player` | Player/character identity without the 8-getter sprawl | `.character(i)` (0 local, 1 co-op partner), `.slot(i)`, `.camera(i)`, `.pose(i)`, `.giveCash(n)`, `.giveFuel(n)`, `.targetUnderReticle(i)`, `.rumble(i, len)`, `.removeBoundaries()`, `.teleport(x,y,z, yaw, onDone)` (co-op-safe warp) |
| `Ess.Object` | The everyday object-manipulation namespace | **spawn:** `.spawn(template, x,y,z, yaw)` (guarded); **transform:** `.pos/.setPos`, `.yaw/.setYaw`, `.distance`; **life:** `.health/.setHealth/.maxHealth/.heal`, `.kill/.revive/.remove`, `.alive/.valid`, `.setInvincible`; **state:** `.visible/.setVisible`, `.hasLabel/.addLabel/.removeLabel`, `.displayName`, `.playerControlled`; **physics:** `.enablePhysics/.disablePhysics`, `.impulse`; **vehicle watch:** `.vehicleOf`, `.pollVehicleChange` |
| `Ess.Vehicle` | Seats/riders/entry | `.driver(veh)`, `.riders(veh)`, `.seatOf(char)`, `.enterBestSeat(char, veh)`, `.enterSeatExcluding(char, veh, excl)`, `.exit(veh, char)`, `.followGhost(template, x,y,z)` |
| `Ess.Probe` | Nearby-object collection, one dispatcher | `.nearby(...)` (**excludes the player by default**), `.nearest(...)` (closest match), `.getFaction(guid)`, `.describeSafe(guid)` |

## Timing & input

| Namespace | What it's for | Key calls |
|---|---|---|
| `Ess.Time` | All wall-clock timing (survives world-pause) | `.stamp()`/`.elapsed(s)`/`.mark(s)` (explicit), `.cooldown(seconds)` → `ready()`, `.clock(maxDelta)` → `:delta()` (auto-advancing per-frame dt), `.scale(n)`/`.restoreScale()`, `.format(sec, tenths)`; `Ess.Easy.Time.slowmo(n, seconds)` |
| `Ess.Loop` | The one shared reload-safe heartbeat | `.start(id, interval, tickFn)`, `.stop(id)`, `.isRunning(id)` |
| `Ess.Input` | The only correct key-polling shape + device query | `.poll()` → `{pressed, down(vk)}`, `.VkToChar(vk, shift)`, `.usingController()`, `.hijackController(onInput)` |
| `Ess.TextConsole` | A typed-input console, no `.gfx` asset needed | `.open{ onSubmit=, … }`, `.close()`, `.isOpen()` |

## Tracking & cleanup

| Namespace | What it's for | Key calls |
|---|---|---|
| `Ess.Track` | One registry for every leak-prone Add/Remove pair | `Ess.Track.new()` → `:event/:guid/:marker/:radar/:pda/:qualityRef/:disposer/:contextAction/:add`, then `:closeAll()` |
| `Ess.Event` | `Event.Create` that logs failures + auto-tracks | `.on(type, args, cb, tracker)`, `.off(handle)` |
| `Ess.Save` | The **one** shared save-gate (suppress saves during an ephemeral mode) | `.gate(key)`, `.ungate(key)`, `.isGated()` — saves suppressed while ≥1 holder; used internally by Layers + Sandbox |

## Humans & combat

| Namespace | What it's for | Key calls |
|---|---|---|
| `Ess.Human` | Weapon/inventory/action control for a character | `.equipWeapon/.dropWeapon/.primaryWeapon/.secondaryWeapon/.allWeapons/.setAllWeapons`, `.ammo/.setAmmo/.maxAmmo/.refillAmmo/.setInfiniteAmmo`, `.reloadAll/.doAction/.knockdown/.disableWeapons/.enableWeapons`; `Ess.Easy.Human.giveWeapon(char, templateName)` |

## Markers

| Tier | Key calls |
|---|---|
| `Ess.Easy.Mark` | `.enemy(guid)` (radar+PDA), `.objective(guid)` (all 3), `.zone(x,y,z,r)` (world ring) |
| `Ess.Mark` | `.object(guid, {radar=, pda=, world=})`, `.zone(x,y,z,r, opts)`, `.clear(handle)` |
| `Ess.Raw.Mark` | `.radar/.pda/.world/.worldDisc` (3 surfaces independently), `.pulse/.haltPulse` (flash existing), `.showPlayerMarkers(on)` |

## Camera, bones & spatial

| Namespace | What it's for | Key calls |
|---|---|---|
| `Ess.Camera` | Camera effects (top-level `Camera` + `Graphics.Camera` + `Graphics.Effect`, kept clear) | `.shake/.stopShake`, `.fov/.restoreFov`, `.fade(amt)` (+ `Easy.Camera.shake/fadeOut/fadeIn`), `.lookAtAnchor`, `.followHardpoint`, `.staleAxisDecay` |
| `Ess.Bones` | The confirmed bone/hardpoint recipes | `.attachFX/.detachFX`, `.waitForReady`, `.aimVector`, `.probeNames` |
| `Ess.Points` | Arena spawn-point selection | `.bucket(spawnList)`, `.ideal(pts, refX, refZ, opts)` |

## Audio & HUD

| Namespace | What it's for | Key calls |
|---|---|---|
| `Ess.Sound` | Direct sound/ambience cueing | `.cue/.stop/.ambience/.stopAmbience/.volume`; `Ess.Easy.Sound.play(cue)` |
| `Ess.Hud` | Native HUD popups | `.hint/.hideHint` (tutorial-style), `.banner(msg)` (centered text) |

## UI kit

| Namespace | What it's for | Key calls |
|---|---|---|
| `Ess.UI` | The 9-widget kit (native port of uilib) | `.Menu`, `.List`, `.Panel`, `.Bar`, `.Toast`, `.Confirm`, `.Input`, `.Chat`, `.Board` (+ `.wrap/.comma/.fmt_time` helpers) |
| `Ess.Easy` (UI) | Single-call UI | `Ess.Easy.Toast(msg)`, `Ess.Easy.Confirm(text, onYes, onNo)`, `Ess.Easy.Menu(title, entries)` |
| `Ess.Gfx` | Raw FlashWidget primitives (the Raw tier of UI) | `.widget/.call/.onEvent/.setVisible/.warmupRerender/.menuNav` |
| `Ess.ScrollLog` | A scrolling text log widget | `.new(name, x,y,w,h)` |
| `Ess.Easy.Console` | An in-game browsable/searchable reference of every `Ess.Easy.*` call | `.open()`, `.search()`, `.close()` |

`Ess.UI.Menu`'s builder (`:entry/:category/:header/:switch`) and its `ctx:` helpers
(`:hint/:toast/:confirm/:ask/:spawn/:close`) are the one surface kept byte-for-byte backward-compatible with
the old uilib menu system, so existing menu scripts port unchanged.

## Encounter toolkit (standalone gameplay scripting)

All tiered (`Raw`/Core/`Easy`). This is the encounter machinery extracted from ContractFramework, usable
without a running contract.

| Namespace | Core | Easy |
|---|---|---|
| `Ess.AIOrders` | `.command(guids, behavior, opts, tracker)` — 11 behaviors (move/patrol/defend/attack/hold/face/follow/flee/enter/deploy/animate); `.setGroup/.group` | `.attack(guids, target)`, `.patrol(guids, points)`, `.guard(guids, at)` |
| `Ess.Relations` | `.apply(pairs, label)` → **handle**, `.restore(handle)`, `.isActive(handle)`, `.getFeeling/.setFeeling` (per-individual) | `.makeHostile(factions)`, `.makeAllies(factions)`, `.restore()` |
| `Ess.Triggers` | `.arm(spec, onFire, tracker)` (stateless); `.scope()` → an **isolated** `:arm/:armNamed/:gate/:declare/:markFired` namespace | `.onPlayerNear(x,y,z,r,fn)`, `.onDeath(guid,fn)`, `.after(seconds,fn)` |
| `Ess.Sandbox` | `.begin(id, providerNames, opts)`, `.finish(id)`, `.isActive(id)` — providers: layers/economy/supports/relations, all save-gated | `.arena(id, opts)` (all providers on), `.done(id)` |
| `Ess.Layers` | Save-clean `vz_state_*` layer manipulation for arenas/minigames: `.begin/.add/.remove/.swap/.expect/.composite/.finish`, `.isActive/.isLoaded/.snapshot/.current` | (used via `Ess.Sandbox`'s `layers` provider) |
| `Ess.Raw` | `Raw.AIOrders` (actor/pri/goal/haste/priorityTarget/enable), `Raw.Relations` (snapshot/set/restore), `Raw.Triggers.arm` (full condition vocabulary), `Raw.Sandbox` (register/gateSaves/ungateSaves) | |

Trigger conditions (`Ess.Raw.Triggers.arm` specs): `"immediate"`/`"once"`/`"recurring"`, `{proximity=r, at=}`,
`{onDestroy=guidOrName | "nearest"}`, `{onHealthBelow={target=, pct=}}`, `{onCleared={at=, radius=, faction=}}`.

## Missions

| Namespace | What it's for | Key calls |
|---|---|---|
| `Ess.Contract` | The full ephemeral-mission engine (native port of ContractFramework) | `.Register(def)`, `.Accept(id)`, `.Abort()`, `.Status()`; 16 objective types via `C.Destroy/Reach/Defend/Hold/Survive/Stay/…`; relations/support/AI-orders/triggers subsystems (consumers of the encounter toolkit above) |
| `Ess.Easy.Contract` | One-call contracts | `.destroy(title, spawns, opts)`, `.reach(title, at, radius, opts)` |

## Networking

| Namespace | What it's for | Key calls |
|---|---|---|
| `Ess.Net` | Co-op data sync (native port of ModNet) | `.Shared(ns)` (auto-syncing table), `.Set/.Get/.Track`, `.On/.Send` (messages), `.OnRaw/.SendRaw`, `.Me/.IsCoop/.IsHost/.IsAuthority`; `.hijackCallback(module, name, isMine, onMine)` (safely extend any resident callback) |

## Meta

| Namespace | What it's for | Key calls |
|---|---|---|
| `Ess.Override` | Change engine logic without the tail-call crash | `.wrap(target, name, newFn)` (makes the crash shape structurally impossible), `.mergeIntoLiveTable(t, key, data)` |

---

## Verification status

Everything above is built and live-tested against the running game (most with exact before/after value
confirmations). Two honest limits, both external rather than untested logic:

- **Co-op peer-to-peer delivery** (`Ess.Net`) — the wire protocol is a faithful port of confirmed-working
  co-op code, but full two-machine delivery hasn't been re-verified solo (needs a second machine).
- **`Ess.Input.hijackController`** — its known bug is fixed, but it hasn't been driven with real controller
  input at an open PDA (needs `tools/xpad.py` driving a live controller event).

## Not in scope

`WaveDefense.lua` (a gamemode, not a framework) stays its own file — a future refactor will make it *consume*
`Ess.*` rather than be absorbed. WAD/gfx authoring (gfxforge/gfx_tool) and the lua-bridge substrate itself
are separate tools Ess builds on, not things it wraps.
