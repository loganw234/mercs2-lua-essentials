# Deferred setters — engine mutators not yet wrapped

Working notes for the native-coverage sweep. The read side of `Player` and `Object` is wrapped and
live-verified; the **mutators** were deliberately held back, because verifying a setter means *actually
changing the running game* — cash, fuel, costume and profile writes land in the save.

This file exists so that context isn't lost between sessions. Everything below is grouped by **what you'd
need in order to verify it**, since that's the thing that actually gates progress. Call-site counts and
sample call sites come from the decompiled corpus (`~/Desktop/Mercs2_Decompiled_Lua`, 834 `.lua` files) and
are the evidence for arity and argument types.

Coverage state at time of writing: `Player` 21/107 wrapped, `Object` 47/87 wrapped.

---

## Already-known traps that apply here

Carried over from the getter pass — these will bite when the setters get written:

- **`Player.SetCash` / `SetFuel` skip the HUD refresh.** `Ess.Player.giveCash`/`giveFuel` deliberately route
  through `MrxPmc.AddCashQty`/`AddFuelQty` instead, which update the on-screen counter. A raw `SetCash`
  changes the number without the HUD noticing. Whatever wrapper gets written must either use the MrxPmc
  path or document loudly that it doesn't. Note `Player.AddCash`/`AddFuel` also exist (2 call sites each) —
  worth checking whether *those* refresh the HUD, which would make them the better primitive.
- **`Player.IsJoined` takes a numeric slot index, not a guid** — and returns `nil` (falsy) if handed a guid,
  so it fails silently. Any slot-targeted setter should be checked for the same convention rather than
  assumed to take a guid.
- **A non-nil slot guid is not evidence of a second player.** `GetPlayer(1)` / `GetSecondaryPlayer()` return
  a real-looking handle for an empty slot.
- **`Object.SetModelName` pairs with a getter that returns userdata, not a string.** `GetModelName` hands
  back an interned handle, so a set/get round-trip can't be asserted on a string.

---

## 1. Safe to verify on any save (benign / self-reversing)

Visual or transient state; worst case is an odd-looking frame.

| Native | Sites | Sample call site |
|---|--:|---|
| `Object.FadeOut` | 34 | `Object.FadeOut(A1_2, 10, true)` — (guid, duration, ?bool) |
| `Object.CloseGate` | 27 | `Object.CloseGate(A0_2)` |
| `Object.OpenGate` | 17 | `Object.OpenGate(A0_3)` |
| `Object.PlayMaterialAnimation` | 24 | `Object.PlayMaterialAnimation(uVehicle, "energy_wave", false)` |
| `Object.StopMaterialAnimation` | 6 | `Object.StopMaterialAnimation(uGuid, "global_weapon_beacon")` |
| `Object.PlayAnimation` | 7 | `Object.PlayAnimation(L12_2, L11_2, false, nil, 0, true)` — 6 args |
| `Object.StopAllAnimation` | 4 | `Object.StopAllAnimation(L13_2)` |
| `Object.StopAnimationChannel` | 2 | `Object.StopAnimationChannel(self._vehicle, "hijack")` |
| `Object.SetName` | 15 | `Object.SetName(A1_2[1], "HqInterior")` — round-trips with the wrapped `Ess.Object.name` |
| `Object.SetUnkillable` | 6 | `Object.SetUnkillable(uGuid, true, "Support")` — reason string, like `SetInvincible` |
| `Object.ApplyAngularImpulse` | 2 | `Object.ApplyAngularImpulse(L0_2, -x, 0, z, true)` — (guid, x,y,z, bLocal) |
| `Object.SetHibernationDistance` | 4 | `Object.SetHibernationDistance(uGuid, 1.0E-6)` — note the near-zero idiom |
| `Player.SetScopeEnabled` | 8 | `Player.SetScopeEnabled(oOverlay:GetOwner(), false)` |
| `Player.SetVehicleDisguise` | 7 | `Player.SetVehicleDisguise(false)` — no guid arg; getter confirmed live |

**Note on `SetHibernationDistance`:** the `1.0E-6` sample is a script forcing an object to *never*
hibernate. `RevertHibernationDistance` (0 call sites) is presumably the undo — worth pairing them in one
wrapper so callers can't leak the override.

---

## 2. Needs a throwaway save (writes persistent state)

Do **not** run these against a save anyone cares about.

| Native | Sites | Sample call site |
|---|--:|---|
| `Player.SetCash` | 13 | `Player.SetCash(nInGameCash + MrxPmc.GetClientReimburseAmount())` |
| `Player.AddCash` | 2 | `Player.AddCash(totalAmount)` |
| `Player.SetFuel` | 16 | `Player.SetFuel(_nOldFuel)` |
| `Player.AddFuel` | 2 | `Player.AddFuel(nAmt)` |
| `Player.SetFuelCapacity` | 2 | `Player.SetFuelCapacity(GetFuelCapacity())` |
| `Player.SetProfileCostume` | 5 | `Player.SetProfileCostume(0)` — getter returns `1` on the current save |
| `Player.SetAvailableCostumes` | 4 | `Player.SetAvailableCostumes(WifPmcInterior.GetAvailableCostumes())` |
| `Player.SetProfileCharacter` | 0 | — |
| `Player.SetProfileUpgrade` | 0 | — |
| `Player.SetInPmc` | 8 | `Player.SetInPmc(L6_2, false)` |
| `Player.SetSurvivalMode` | 6 | `Player.SetSurvivalMode(A0_2, false)` |
| `Player.SetHealthClamp` | 6 | `Player.SetHealthClamp(A0_2, true)` |

---

## 3. Needs specific context to exercise at all

These can't be meaningfully tested from a character standing in the world.

### Winch / cargo — needs a winch-capable helicopter
Confirmed on a character: `HasWinch` → `false`, `GetWinchState` → `nil`, `IsWinched` → `nil` (note: `nil`,
not `false`). Get a cargo helicopter first, then this whole cluster can be done in one pass.

| Native | Sites | Sample |
|---|--:|---|
| `Object.AttachCargoToWinch` | 9 | `Object.AttachCargoToWinch(A1_2, A0_2)` |
| `Object.DetachCargoFromWinch` | 13 | `Object.DetachCargoFromWinch(A0_2)` |
| `Object.SetWinchState` | 9 | `Object.SetWinchState(A0_2, "deployed")` — **string** state, not a bool |

### Boundary — needs a boundary volume guid
`Ess.Player.removeBoundaries()` already wraps the teardown side.

| Native | Sites | Sample |
|---|--:|---|
| `Player.AddBoundary` | 4 | `Player.AddBoundary(uPlayerGuid, uBoundary)` |
| `Player.RemoveBoundary` | 2 | `Player.RemoveBoundary(uPlayerGuid, uBoundary)` |
| `Player.SetOutBoundary` | 9 | `Player.SetOutBoundary(L5_2, false)` |
| `Player.SetBoundaryCallback` | 2 | `Player.SetBoundaryCallback(uPlayerGuid, BoundaryCallback)` |

### Co-op — needs a second player joined
| Native | Sites | Sample |
|---|--:|---|
| `Player.SetPlayerJoinedCallback` | 3 | `Player.SetPlayerJoinedCallback(OnPlayerJoined)` |
| `Player.SetPlayerLeftCallback` | 3 | `Player.SetPlayerLeftCallback(OnPlayerLeft)` |
| `Player.RemovePlayerJoinedCallback` | 3 | no args |
| `Player.RemovePlayerLeftCallback` | 3 | no args |
| `Player.SetWaitForInGame` | 6 | `Player.SetWaitForInGame(uSecondaryCharacter)` |
| `Player.SetSeatMovementLocks` | 6 | `Player.SetSeatMovementLocks(uPlayerGuid, false)` |
| `Player.ClaimSeat` | 0 | — |

### PDA / satellite — needs the PDA map open
| Native | Sites | Sample |
|---|--:|---|
| `Player.SetPDAMapMode` | 6 | `Player.SetPDAMapMode(oDesignator.uOwner, false)` |
| `Player.SetPDAMapModeCallback` | 14 | `Player.SetPDAMapModeCallback(uPlayerGuid, false, ApplySatelliteUpdateEvent)` |
| `Player.SetPDAMapModeCancelCallback` | 2 | `(self.uOwner, SatelliteTargettingCancel, {self})` — note the **table** 3rd arg |
| `Player.SetSatelliteScanMode` | 2 | `Player.SetSatelliteScanMode(uPlayer, false, 0, 0, 0)` — 5 args |
| `Player.SetupSatelliteScan` / `SetSatelliteScanCallbacks` / `SetSatelliteScanPaused` / `AddSatelliteScanTarget` | 0 | — |

---

## 3b. Vehicle — the hijack state machine, and the rest

`Vehicle` is 17/40 wrapped after the seat-inspection pass. Its mutators split into one coherent subsystem
and a handful of odds and ends.

### The hijack state machine — do these as ONE unit, not piecemeal
Eleven natives that clearly drive a single sequence. Wrapping them individually would expose a state machine
without its invariants, which is worse than not wrapping it. Needs a hijackable vehicle plus an NPC to
hijack it — `seatInfo(seat).IsHijackable` is now the way to find a valid target.

| Native | Sites | Sample |
|---|--:|---|
| `Vehicle.HijackStart` | 2 | `Vehicle.HijackStart(self._hijacker, self._hijackee, self._vehicle, self)` — 4 args, last is a **handler table** |
| `Vehicle.HijackComplete` | 2 | `Vehicle.HijackComplete(self._hijacker)` |
| `Vehicle.HijackAbort` | 2 | `Vehicle.HijackAbort(self._hijacker)` |
| `Vehicle.HijackAbortDone` | 4 | `Vehicle.HijackAbortDone(self._hijacker)` |
| `Vehicle.CancelHijack` | 3 | `Vehicle.CancelHijack(L4_2)` |
| `Vehicle.SetHijackState` | 2 | `Vehicle.SetHijackState(self._hijacker, i)` — integer state |
| `Vehicle.SetHijackSuccess` | 2 | `Vehicle.SetHijackSuccess(self._hijacker, false)` |
| `Vehicle.IsHijackRemote` | 2 | guarded in the corpus as `Vehicle.IsHijackRemote and Vehicle.IsHijackRemote(...)` — the shipped script **defends against it not existing** |
| `Vehicle.IsHijackBad` | 0 | — |
| `Vehicle.StartTankHijackMotion` | 0 | — |
| `Vehicle.StopTankHijackMotion` | 4 | `Vehicle.StopTankHijackMotion(self._vehicle)` |

The `IsHijackRemote and IsHijackRemote(...)` guard is worth heeding: a shipped game script does not trust
that binding to be present, which hints at a build/version difference. Probe for existence before use.

### Everything else
| Native | Sites | Sample | Notes |
|---|--:|---|---|
| `Vehicle.SetParts` | 54 | `Vehicle.SetParts(uGuid, "LightFront", false)` | most-used uncovered native in the namespace; returns a value (`bLightStart = ...`) |
| `Vehicle.Enter` | 36 | `Vehicle.Enter(uVeh, uStarter)` | `Ess.Vehicle.enterBestSeat` already covers the common path |
| `Vehicle.CloseDoor` / `OpenDoor` | 6 / 4 | `Vehicle.OpenDoor(guid, "DriverHatch")` | door name is a **string** |
| `Vehicle.SetCanPlayerUse` | 4 | `Vehicle.SetCanPlayerUse(uHeli, "d", true)` | seat-type string |
| `Vehicle.EnableTurret` | 12 | `Vehicle.EnableTurret(self._hijackee, "head", false, "all", false)` | 5 args |
| `Vehicle.SetTurretPitch` | 2 | `Vehicle.SetTurretPitch(self._vehicle, "main_turret", 0)` | |
| `Vehicle.SetTurretYaw` | 0 | — | pairs with the above |
| `Vehicle.TransferToSeat` | 3 | `Vehicle.TransferToSeat(A0_2, L5_2, false)` | `Ess.Vehicle.seatTransfers` finds valid targets |
| `Vehicle.ClearControls` | 2 | `Vehicle.ClearControls(self._vehicle)` | |
| `Vehicle.SpinHeli` | 0 | — | |

### Unresolved getter
`Vehicle.GetFromSeat` (0 call sites) returned **nil** for both a seat guid and a vehicle guid, so its
argument type is still unknown — deliberately left unwrapped rather than guessed. `GetRiderFromSeat` covers
the obvious reading and is wrapped as `Ess.Vehicle.riderInSeat`.

---

## 3c. Human and Sys

### Human — 8/21 wrapped
Three queries wrapped this pass (`carrying`, `grappling`, `swimming`). The rest are mutators, and one of
them is the most-used uncovered native across every namespace surveyed so far.

| Native | Sites | Sample | Notes |
|---|--:|---|---|
| `Human.SetState` | **45** | `Human.SetState(L6_2, "Upright", "Idle")` | two **string** state args — a stance/action pair. Highest-value single native left anywhere; deserves a proper enum-ish wrapper rather than a passthrough |
| `Human.ForceExitSeatNoSnap` | 18 | `Human.ForceExitSeatNoSnap(Player.GetCharacter(...))` | "no snap" = skip the exit animation/teleport |
| `Human.SetFireLock` | 8 | `Human.SetFireLock(uChar1, false)` | |
| `Human.SetPreemptiveRagdoll` | 8 | `Human.SetPreemptiveRagdoll(self._hijackee)` | |
| `Human.SetAllowCorpseCleanup` | 6 | `Human.SetAllowCorpseCleanup(uGuid, false)` | **returns a value** (corpus logs the result) |
| `Human.StopGrappling` | 5 | `Human.StopGrappling(L6_2)` | pairs with the wrapped `.grappling()` |
| `Human.SetJostleEnabled` | 3 | `Human.SetJostleEnabled(L7_2, A0_2)` | |
| `Human.Drop` | 8 | `Human.Drop(L7_2)` | pairs with the wrapped `.carrying()` |
| `Human.PersistTransform` | 8 | `Human.PersistTransform(L7_2)` | |
| `Human.Scrub` | 3 | `Human.Scrub(L7_2)` | |
| `Human.Emote` / `EquipWeapon` / `StowWeapon` | 0 | — | all three **exist** live (type == "function"), just unused by shipped scripts |

Note `Human.EquipWeapon`/`StowWeapon` are distinct from the already-wrapped
`Human.Inventory.EquipWeapon` that `Ess.Human.equipWeapon` uses — same names, different tables.

### Sys — 20/64 wrapped
The environment/settings half is now `Ess.Sys` (05_sys.lua); timing and autosave were already covered by
`Ess.Time` / `Ess.Save`. What's left are mostly **game-state machine drivers** — dangerous, not just
persistent-state-changing.

| Native | Sites | Sample | Notes |
|---|--:|---|---|
| `Sys.RequestGameState` | **86** | `Sys.RequestGameState("unloading")` | most-called uncovered native in the survey. Drives the engine's own state machine — mis-sequencing it could hard-lock or unload the level. Needs its valid state strings enumerated from the corpus BEFORE anything is wrapped |
| `Sys.StartSingleplayer` | 4 | `Sys.StartSingleplayer(sLevelName, sMasterScript)` | starts a level — will tear down the current session |
| `Sys.SetLevelName` / `SetMasterScriptName` | 2 / 2 | | paired with the above |
| `Sys.SetSkipMission` | 17 | `Sys.SetSkipMission("")` | |
| `Sys.AddStringDb` / `ClearStringDb` | 3 / 1 | `Sys.AddStringDb("patch01")` | localisation DB loading — relevant to DLC/patch work |
| `Sys.SetAssetRequestMax` | 4 | `Sys.SetAssetRequestMax(_knOrigAssetRequestMax)` | corpus saves the old value first and restores it — copy that idiom |
| `Sys.SetNumberOfViewports` | 4 | `Sys.SetNumberOfViewports(1)` | splitscreen |
| `Sys.SetLuaSaveVersion` | 4 | | save-format versioning |
| `Sys.SetTutorialsEnabled` / `SetINIBriefing` | 2 / 3 | | the write side of two `Ess.Sys.settings()` reads |
| `Sys.PlayIntroMovies` / `StartWithResources` | 4 / 2 | | both read as predicates despite the verb-ish names — check before assuming they mutate |

`Sys.RequestGameState` is the one to be careful with: 86 call sites means it is central, and that also means
a wrong state string is likely to do something drastic rather than nothing.

---

## 4. Dark — no call sites anywhere, arity unknown

Only reachable by live probing. `Player` and `Object` both have **zero** no-op stubs per the verified EXE
audit, so these are real functions, not dead bindings — the names are just never used by shipped scripts.

`Player`: `SetAimMode`, `SetPlayerStart`, `SetGrappleEnabled` (2 sites, `(uGuid, bEnable)`),
`SetSurvivalModeCallback`, `SetSwimmingSearchRadius`, `SetVehicleControlsLock`

`Object`: `SetMass`, `SetPositionToObject`, `StopAnimation`, `QueueAcceleration`,
`BeginQueuedAcceleration`, `RevertHibernationDistance`

`QueueAcceleration` + `BeginQueuedAcceleration` look like a deliberate pair (queue N, then commit) — worth
probing together rather than separately.

---

## Method reminder

Probe before wrapping. The getter pass turned up several signatures that reading the name would have got
wrong (`IsJoined` taking an index, `GetVelocity` returning a scalar, `GetModelName` returning userdata,
`PolarToRect` taking degrees in the opposite argument order). Assume the same rate of surprise here.

Workflow is `.claude/skills/ess-live-test` — `launch.py --status` first, and **verify the loaded `Ess.VERSION`
before trusting any result**: a relaunch picks up whatever is deployed at `scripts/OnLoad/`, which is not
necessarily the current build.
