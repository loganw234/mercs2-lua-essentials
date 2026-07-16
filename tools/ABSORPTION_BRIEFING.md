# ABSORPTION BRIEFING — read this FIRST if context was just compacted mid-task

This is the resume anchor for an in-progress, user-directed pivot: fully absorbing uilib.lua, ModNet.lua,
and ContractFramework.lua's FUNCTIONALITY into Ess as native code, replacing the earlier "adopt via alias"
design. Logan is present and interactive for this task (not an unsupervised overnight session — that
earlier phase finished cleanly; see `overnight-ess-autonomous-session` memory if you need that history,
it's unrelated to this document).

## 0. The exact ask (Logan, verbatim, this session)

> "Integrate the 2 libraries into the essentials framework, aim to keep backwards compatibility with old
> scripts for uilib, or at least a simple conversion task. I'm currently here so if you run into issues
> you can ask me for guidance."

Then, after an interruption, this correction (supersedes the above where they conflict):

> "I believe you misunderstood. We will no longer have uilib or modnet (or contract framework) lua files,
> the functions they performed are to be rolled into the essentials framework, honestly the one part that
> needs backward compatibility is the uilib menu/category system like the file I sent, make sure it still
> includes the basic ctx:helpers just so scripts already made with the menu system can be integrated
> smoothly with the new essentials framework"

They attached `C:\Games\Mercenaries 2 World in Flames\scripts\Misc\ExampleMenu.lua` as the reference shape
for the Menu compat surface (it happens to call the OLD deprecated `_G.ForgeMenu`, but per Logan's own
wording ("the uilib menu/category system") this is illustrative of the `entry`/`category`/`ctx:` API
shape to preserve — NOT a request to build a separate ForgeMenu-named shim. `Ess.UI.Menu` already matches
this shape exactly; see §2.

**My clarifying questions and Logan's answers (locked in, don't re-ask):**
1. Port scope for ModNet/ContractFramework: **Full parity** (not just what real consumers use).
2. Build order: **uilib → ModNet → Contract** (as I suggested), PLUS: a better ModNet reference exists at
   `C:\Games\Mercenaries 2 World in Flames\scripts\Misc\bak\OnKey\ModNet_CoopChat.lua` (already read and
   used). Also: **"ensure we reutilize uilib for the contract ui's rather than rerolling the ui code
   again. All gfx files are present mentioned, so reuse of those is fine."**
3. Old files (uilib.lua/ModNet.lua/ContractFramework.lua) once each port lands: **leave the old repos
   completely untouched** (mercs2-lua-mods, the uilib OneDrive folder) — just **stop deploying them to
   THIS game install** (remove their `[OnLoad]` entries from `lua_loader.ini` here) once Ess's version is
   confirmed working. Keep the old files around "in case we need them later." **This step (task 10) has
   NOT been started yet** — do it once Ess.Contract is fully verified.

## 1. Orientation

Repo: `C:\Users\logan\source\repos\mercs2-lua-essentials` (local git, no remote). This absorption is a
DELIBERATE ARCHITECTURE CHANGE from the project's earlier "adopt, don't duplicate" thesis (documented
extensively in `FEATURE_SHEET.md`'s Non-goals and the `ess-essentials-framework-project` memory) — that
thesis is now SUPERSEDED for these three specific libraries, per Logan's explicit instruction this
session. Don't "fix" this back toward aliasing; the whole point is these three libraries no longer exist
as separate deployed files.

Dev-loop: same as always — see `.claude/skills/ess-live-test/SKILL.md`. New since the overnight session:
`tools/launch.py --wait-ess` polls for `[Ess]` in the background from the moment the game process
launches (concurrent with the open-loop skip-intro sequence), instead of needing a separate
`lua_repl.py --wait-log` call afterward. Use `python tools/launch.py --all --wait-ess` as the standard
one-shot relaunch+confirm command from now on.

**Recurring gotcha hit constantly this session:** the game must be STOPPED before `launch.py --all` can
start a new one (single-instance lock; a leftover process makes `--launch` silently exit 1). Always:
```
powershell -Command "Get-Process Mercenaries2 -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep -Seconds 2"
```
(via the **PowerShell tool directly**, not embedded in the Bash tool — bash mangles `$_` before it
reaches PowerShell) before every `launch.py --all --wait-ess` call. This project's Bash tool is Git Bash;
process management needs the separate PowerShell tool.

## 2. What's DONE — committed, live-tested, safe to build on

**Ess.UI (uilib absorbed), commit `7903008`.** All 9 widgets: List, Panel, Bar, Toast, Confirm, Input,
Menu, Chat, Board. Files `src/42_ui_engine.lua` through `src/55_ui_board.lua` (see MANIFEST in
`build/merge.py` for the exact list/order). Built on Ess.Gfx (raw widget)/Ess.Loop (heartbeat)/Ess.Input
(keys)/Ess.Timer/Ess.Player.pose instead of uilib's own private copies of those mechanisms.
`Ess.UI.Menu`'s ctx: surface (`entry`/`category`/`header`/`switch`, `ctx:hint/toast/print/close/confirm/
ask/spawn`, `:toggle/:open/:close/:isOpen`) is the STRICT backward-compat piece — confirmed byte-for-byte
matching uilib's own API, live-tested against the exact `ExampleMenu.lua` shape (2-level nested drill-
down, a dynamic-label switch, `ctx:spawn` with a real Veyron). Movie assets (`ui_list.gfx` etc, WITH the
`.gfx` suffix — matches uilib's own convention) confirmed present in this install's `vz-patch.wad` before
starting. Zero errors across the whole test batch.

**Ess.Net (ModNet absorbed), commit `51d852a`.** `src/70_net.lua` (pre-existing `hijackCallback`, built
earlier in the overnight session) + `src/71_net_wire.lua` (the rest: Shared/On/Send/OnRaw/SendRaw/
IsCoop/IsHost/IsAuthority/ready-gate handshake). The wire PROTOCOL itself (serialization, chunking, LWW
state sync) is a faithful byte-for-byte port of confirmed-working co-op code — deliberately not
rewritten. The hijack install now goes through `Ess.Net.hijackCallback` instead of a second hand-rolled
copy. Live-tested: identity functions correct in SP, local Set/Get/Shared round-trip, the REAL
`MrxFactionManager.NetEventCallback` hijack confirmed installed (not a mock), Send/SendRaw exercised with
string/number/table/raw payloads with zero errors. **Full peer-to-peer delivery is UNTESTED — genuinely
needs a second co-op machine**, an honest limitation of solo testing, not a skipped step.

**`src/99_adopt.lua` DELETED.** It used to alias `Ess.Net`/`Ess.UI`/`Ess.Contract` onto the old globals
when present. Now that Net and UI are natively absorbed (and once Contract is too, per §3), the whole
file is obsolete — it was ALSO caught mid-session actively logging a misleading "Ess.Net unavailable"
message even after Ess.Net had real functionality (fixed, then the file was deleted outright once Contract
absorption started, since at that point every consumer it used to alias becomes native).

## 3. What's IN PROGRESS — written, NOT yet committed, mid-live-testing

**Ess.Contract (ContractFramework absorbed).** Three new files, all UNCOMMITTED:
- `src/80_contract.lua` — core: helpers (track/mark/markZone/hudLine/hudSay/rspan/rchance/
  resolveTargets/grantReward/showFanfare/collectInArea), the lifecycle (`_run`/`_runList`/`_finish`/
  `_startBackground`/`Accept`/`Abort`), `Register`/`List`/`Status`, all 16 objective-builder sugar
  functions (`.Destroy` etc), and `Contract.UI.Panel`/`.Bar` (now REAL — thin aliases straight to
  `Ess.UI.Panel`/`Ess.UI.Bar`, completing something ContractFramework.lua itself only ever stubbed:
  `C.UI = C.UI or {}` with no actual implementation, per its own "need a .gfx; see README" comment).
- `src/81_contract_objectives.lua` — the 15 objective-type handlers (`C.tHandlers.chase/survive/destroy/
  reach/defend/collect/escort/enter/hold/protect/stay/group/interact/verify/extract/race`), a close
  port using `C._track`/`C._mark`/`C._markZone`/`C._addEv`/`C._resolveTargets` (exposed as `C._xxx`
  fields at the bottom of file 80, since each src file is its own `do...end` block in the merged chunk —
  file-local helpers aren't visible across files without this).
- `src/82_contract_encounter.lua` — `SUPPORT_EFFECTS` (artillery/flyby/bombingrun/heli/reinforce/custom/
  say/music/vfx/damage/vo), `C._applyRelations`/`_restoreRelations` (now ~2 lines each, thin wrappers
  over `Ess.Relations`), `C._spawnUnits` (also registers each group with `Ess.AIOrders.setGroup`), and
  `C._startSupport` (the trigger/gate/AI-order runner, built on `Ess.Triggers.arm`/`armNamed`/`gate` and
  `Ess.AIOrders.command` instead of re-hand-rolling `armTrigger`/`AI_BEHAVIORS` a third time). Also
  contains the built-in `demo_convoy` contract (ported from the original) and the final
  `Ess.Log("Contract: loaded (N contract(s) registered)")` boot line.

**MANIFEST updated** in `build/merge.py`: `80_contract.lua`, `81_contract_objectives.lua`,
`82_contract_encounter.lua` appended after the Group G / Net files, in that order (dependency order:
Contract needs Ess.Relations/Triggers/AIOrders/Sandbox/UI/Net all already loaded).

**Two OTHER files were extended mid-task (also uncommitted) to close real parity gaps found while
porting** — these are GENERAL improvements to already-existing Ess namespaces, not Contract-specific:
- `src/62_triggers_raw.lua` — `Ess.Raw.Triggers.arm`'s `onDestroy` now ALSO supports the "nearest in a
  radius" dynamic-discovery form (`{onDestroy="nearest"}` or `{onDestroy={at=,radius=,kind=}}`), matching
  ContractFramework's own `armTrigger`'s `findArm()` polling behavior exactly. The earlier (overnight-
  session) version only supported a named/placed target. Doc comment at the top of the file updated too.
- `src/61_relations.lua` — `Ess.Relations.apply` now also calls `MrxFactionManager.SetAttitudeMutable`
  when a relation involves PMC (making the HUD reflect the stance "officially"), matching
  ContractFramework's own `_applyRelations` — the overnight-session version of `Ess.Relations` didn't have
  this. Needs `import("MrxFactionManager")`, added at the top of the file.

### Bugs found and fixed DURING this Contract port's live testing (all already fixed in the current
### uncommitted source — re-verify after resuming, don't re-diagnose from scratch)

1. **Missing `import("MrxMusic")`** in `80_contract.lua` (crashed `showFanfare` on first contract
   completion: `attempt to index global 'MrxMusic' (a nil value)`). Fixed: added the import.
2. **Same class of bug in `82_contract_encounter.lua`**: `MrxMusic` (used directly in
   `SUPPORT_EFFECTS.music`, ungated by any `and`-short-circuit so it WOULD crash), `MrxCopterDrop`, and
   `MrxVoSequence` all needed their OWN `import()` calls in THIS file too — import is file-scoped, one
   file importing something doesn't help a different file in the same merged chunk. Fixed: added all
   three imports (VoSequence wrapped in `pcall(function() import(...) end)` since it's optional/not every
   install has it).
3. **`tostring(inst)` on a plain Lua table in this engine does NOT give a short address string** — it
   DUMPS the table's own field contents (a genuinely new, previously-undiscovered engine quirk, confirmed
   live). Was being used to build a per-instance namespace key for `Ess.Relations`/`Ess.Triggers` — still
   technically worked (still unique per instance) but produced ugly multi-line log spam. Fixed: `C.Accept`
   now assigns a real counter-based `inst._id = "c" .. C._nextInstId` instead, used everywhere a
   namespace key was needed.
4. **Tracker interface mismatch**: `Ess.Triggers.arm`/`armNamed`/`gate` AND `Ess.AIOrders.command` both
   expect their `tracker` parameter to be an `Ess.Track`-shaped object (real `:event(handle)` and
   `:guid(uGuid)` methods) — Contract's own task buckets were plain `{events={}, guids={}, ...}` table
   literals, which crashed the instant a trigger actually scheduled something
   (`attempt to call method 'event' (a nil value)`) or the instant a `defend` AI order spawned its anchor
   prop (`...'guid'...`). Fixed: added `C._newTask()` (a constructor using a small `TaskMT` metatable with
   real `:event`/`:guid` methods) in `80_contract.lua`, and replaced EVERY inline task-literal construction
   in files 80 and 82 (4 total call sites) with `C._newTask()`.
5. **A genuine double-fire bug, confirmed to exist in the ORIGINAL `ContractFramework.lua` too** (not
   introduced by this port — a faithful port reproduces it): `trigAction(t)` fires an id both via
   `t.fires={id}` AND via a separate scan for any support/waypoint whose OWN `.trigger={ref=t.id}` points
   back at it — if a modder (or a test) wires the SAME relationship both ways at once, it fires twice, no
   dedup between the two paths. Fixed IN THE PORT (a judgment call — this is a newly-discovered issue,
   not one of the 9 already-catalogued "Known Bugs," found fresh via live testing, so fixed the same way
   Known Bugs #2/#3 were): `trigAction` now tracks an `already={}` set per call and skips a second hit.

## 4. EXACT resume point — what to do next, in order

**I was mid-relaunch when interrupted.** The game process had just been stopped
(`Stop-Process -Force` on Mercenaries2, confirmed) but `python tools/launch.py --all --wait-ess` had NOT
yet been re-run. Do that first:

```bash
cd "/c/Users/logan/source/repos/mercs2-lua-essentials"
python tools/lua_repl.py --log-size          # record offset (game is stopped, so this may read a stale
                                              # size from before -- that's fine, wait_log's own truncation
                                              # guard handles a shrunk file correctly regardless)
```
Then via the PowerShell tool (not Bash):
```
Get-Process Mercenaries2 -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep -Seconds 2
```
Then:
```bash
python tools/launch.py --all --wait-ess
```

**Then re-run the double-fire test (item 5 above) to CONFIRM the fix actually works live** — it had not
been re-tested yet when interrupted:
```bash
python tools/lua_repl.py --log-size    # record offset first
python tools/lua_repl.py --code "
local x,y,z = Ess.Player.pose(0)
Ess.Contract.Register({
    id = 'test4', title = 'Test Contract 4',
    objectives = { Ess.Contract.Hold({ desc = 'Hold here', at = {x+100,y,z+100}, radius = 10, time = 30 }) },
    support = { { id = 'sayHi', effect = 'say', text = 'Gate-fired only', trigger = {ref='t1'} } },
    triggers = { { id = 't1', kind = 'once', delay = 1.0, fires = {'sayHi'} } },
})
Ess.Contract.Accept('test4')
return 'active='..tostring(Ess.Contract.active ~= nil)
"
# wait >1s, then read the log and confirm 'support 'sayHi' fired' appears EXACTLY ONCE, not twice.
```
Then `Ess.Contract.Abort()` to clean up before moving on.

## 5. Remaining test coverage for Ess.Contract (not yet exercised)

Already confirmed live: `Register`, `Accept` (both instant-complete and long-running paths), `Status()`
mid-flight, `Abort()`, the `reach` and `hold` objective handlers, `def.relations` (via the already-tested
`Ess.Relations`), `def.units`+`Ess.AIOrders.setGroup` group registration, a `hold`-behavior waypoint order,
a `say` support effect, a `once` trigger with `fires={}`, the double-fire fix (pending re-verification per
§4).

**NOT yet tested at all**, roughly in order of value/safety:
- The other 13 objective handlers (destroy/defend/collect/escort/enter/protect/stay/group/interact/
  verify/extract/race/chase/survive) — `destroy` and `survive` are probably the next-easiest/safest to
  try (spawn a target, kill it via `Object.Kill` or similar to confirm the `ObjectDeath` handler fires).
- The gate mechanism (`kind="all"/"count"`) specifically WITHIN Contract's own trigger wiring (the
  underlying `Ess.Triggers.gate` primitive itself WAS confirmed working standalone earlier tonight, but
  not yet exercised through Contract's own `ns`-namespaced wrapping in `_startSupport`).
- `kind="objective"` triggers (fires when a top-level contract objective completes) — the ONE trigger
  kind that's Contract-specific, handled locally in `_startSupport` rather than via `Ess.Triggers`.
- The `onDestroy="nearest"` extension to `Ess.Triggers.arm` (§3's item, extended THIS session) — tested
  only by code-reading, not yet live-fired.
- `SUPPORT_EFFECTS` beyond `say`: artillery/flyby/bombingrun/heli/reinforce/vfx/damage/music/vo — all
  plausible to test from the PMC HQ interior (none require going outdoors), but untested.
- **The `demo_convoy` built-in contract itself** — NOT tested, because its `start` field triggers
  `MrxUtil.TeleportHeroesToLocations`, and the player is inside the PMC HQ interior. This mirrors the
  overnight session's own explicit caution ("do not attempt to teleport out of the interior — confirmed
  crash risk for MULTIPLAYER teleport helpers specifically"). `TeleportHeroesToLocations` is a DIFFERENT,
  single-player-safe utility with its own precedent of working in this exact framework before (a
  `grand_prix` race contract ran end-to-end previously, per the `custom-contract-framework` memory) — but
  given the current session is interactive, THE SAFEST MOVE IS TO ASK LOGAN before trying it, rather than
  assume either way. Don't just try it unprompted.
- `Ess.Contract.List()`/`.All()` — trivial, should just work, but hasn't been explicitly checked.

## 6. After Ess.Contract testing wraps up

1. Commit everything currently uncommitted (see §7 for a draft message) — the three new Contract files,
   the `61_relations.lua`/`62_triggers_raw.lua` extensions, the `99_adopt.lua` deletion, and the
   `build/merge.py` MANIFEST update, likely as ONE commit (they're one cohesive unit of work) or split
   sensibly if it's cleaner to separate "Contract port" from "Triggers/Relations parity extensions."
2. **Task 10 (not started): retire the old files from THIS game install.** Per Logan's explicit answer in
   §0: remove `uilib.lua`/`ModNet.lua`/`ContractFramework.lua`'s entries from
   `C:\Games\Mercenaries 2 World in Flames\scripts\lua_loader.ini`'s `[OnLoad]` section — but ONLY if
   they're even present there (this install's `scripts/OnLoad/` currently only has Ess's own
   `1_Ess.lua` deployed by `launch.py`, so this step may already be a no-op — CHECK the actual directory
   and ini file contents before assuming there's anything to remove). Do NOT touch the source files in
   `mercs2-lua-mods` or the uilib OneDrive folder — Logan was explicit those stay untouched.
3. Update `FEATURE_SHEET.md` — its "Non-goals" section currently says Ess is "Not a replacement for
   ModNet/uilib/ContractFramework/LayerFw" — THIS IS NOW WRONG for three of those four and needs a
   correction/update reflecting the absorption. Also update its per-namespace rows (Group E/H/I currently
   still say "ADOPT" for these three, matching the old design) and the Implementation status section at
   the top.
4. Update project memory (`ess-essentials-framework-project.md`) with this whole absorption arc — the
   architecture pivot, what got built, the bugs found (they're good "hard-won facts" worth preserving
   long-term, matching this project's existing memory style), and the final state.

## 7. Draft commit message (adjust once final test results are in)

```
Absorb ContractFramework into Ess.Contract: full engine port, live-verified

Third and final absorption (uilib -> Ess.UI, ModNet -> Ess.Net, this ->
Ess.Contract). All 15 objective-type handlers, Register/Accept/Abort/Status,
and the support/relations/AI-orders/triggers subsystem ported -- the latter
now a thin consumer of Ess.AIOrders/Relations/Triggers/Sandbox (already built
earlier this project) instead of re-hand-rolling that logic a third time.
Contract.UI.Panel/Bar are now REAL (aliased to Ess.UI), completing something
ContractFramework.lua itself only ever stubbed.

Also extends Ess.Raw.Triggers.arm's onDestroy (the "nearest in a radius"
dynamic-discovery form) and Ess.Relations.apply (the SetAttitudeMutable HUD
call for PMC-involving relations) for genuine full parity -- both real gaps
found while porting, general improvements not specific to Contract.

Deletes the now-fully-obsolete 99_adopt.lua -- all three things it used to
alias are natively implemented now.

[[ live-test results to be filled in after resuming -- see
   tools/ABSORPTION_BRIEFING.md §5 for exact coverage ]]
```

## 8. Safety reminders carried over (still apply)

- Player is inside the PMC HQ interior. Don't attempt to teleport out without asking first (see §5's
  `demo_convoy` note).
- Never push any repo to a remote (none are configured anyway).
- Stay scoped to `mercs2-lua-essentials`; per Logan's explicit answer in §0, do NOT touch
  `mercs2-lua-mods` or the uilib OneDrive folder's actual source files.
- Kill the game process via the PowerShell tool before every relaunch (single-instance lock).
- `loadcheck.py`'s stubbed environment cannot catch missing-`import()` bugs or real-engine-only issues
  (confirmed 3+ times this session alone) — "loads clean" and "behaviorally verified" remain two
  different claims; always live-test.
