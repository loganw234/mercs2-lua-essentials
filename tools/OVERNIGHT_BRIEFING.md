# OVERNIGHT BRIEFING — read this FIRST, before anything else, if context was just compacted

This file is your anchor. If you're reading this because Logan just ran a goal/loop command and pointed
you here, assume you remember almost nothing of the conversation that produced it — everything you need
to resume correctly is either here or one hop away via an explicit pointer. Read this whole file before
touching any tool.

## 0. The mission (Logan's exact framing, 2026-07-16)

Work **overnight, autonomously, unsupervised**, filling out as much of the `Ess` framework as you can
reach. Keep going until: Logan stops you, you hit a genuine hard wall, or you exhaust the options actually
available to you — he explicitly doubts you'll exhaust them in 8 hours, so don't stop early out of
caution; there is a LOT of legitimate work below.

**The one hard constraint: the player character is located inside the PMC HQ interior.** Most outdoor/
world-streamed functionality is unavailable from here — not everything in FEATURE_SHEET.md's remaining
groups can be live-tested right now. Logan's instruction: work on what you CAN reach, and extrapolate
further design/implementation from the wiki docs and decompiled source corpus for the rest. Don't try to
force your way outdoors (see Safety Rules — teleporting out of an interior cell is a known crash risk).

## 1. Orientation — what this project is, in one paragraph

`Ess` (global `_G.Ess`) is a foundational Lua library for Mercenaries 2 modding, being built from scratch
in its own repo, `C:\Users\logan\source\repos\mercs2-lua-essentials` (local git only, no remote, 8 commits
as of this writing, latest `f8eaa83`). The design is fully mapped in `FEATURE_SHEET.md` at the repo root —
**read that file's "Namespace catalog" and "Implementation status" sections now if you haven't already
this session**, it is the canonical spec for everything described below. This briefing does not repeat
that content, only what you need to resume acting on it.

## 2. How to actually DO anything — the dev-loop

**Read `.claude/skills/ess-live-test/SKILL.md` now** (same repo). It is the complete, tested procedure for
launching the game, confirming the framework loaded, and sending/reading Lua against the live engine. Do
not improvise a different testing approach — this one is confirmed working end-to-end as of last night.

The one-paragraph version: `python tools/lua_repl.py --log-size` (record offset) → `python tools/launch.py
--all` (build+deploy+launch, lands inside an actual loaded game) → `python tools/lua_repl.py --wait-log
"[Ess]" --since-bytes <offset> --wait-timeout 90` (confirms ready) → `python tools/lua_repl.py --code
'return ...'` as many times as needed. Check `python tools/launch.py --status` first if unsure whether a
game session is already up from earlier in the night — don't blindly relaunch if one's already running and
working.

## 3. What's built and confirmed vs. what isn't (as of commit `f8eaa83`)

`src/` currently has, in `build/merge.py`'s MANIFEST order:
`00_core.lua 10_player.lua 11_object.lua 12_vehicle.lua 13_probe.lua 20_loop.lua 21_input.lua 22_state.lua
30_track.lua 53_rng.lua` — Groups A, B, C, D + RNG (pulled forward from F). All load clean in-engine.
**Behaviorally verified live:** `Ess.Player.character(0)` (exact match vs `Player.GetLocalCharacter()`),
`Ess.RNG` (real varying output). **Everything else in those 10 files has NOT been individually exercised
yet** — Object/Vehicle/Probe/Loop/Timer/Input/State/SaveVar/Track/Event are load-tested only. Cheap,
valuable early task: smoke-test each of these with a `--code` call before building anything new, so you
know your actual starting baseline instead of assuming.

**Not yet built at all:** the rest of Group F (`Ess.Bones`, `Ess.Camera`, `Ess.Points` — files `50_bones.lua`,
`51_camera.lua`, `52_points.lua` don't exist yet), Group E (`Ess.Gfx`, `Ess.ScrollLog`, the `Ess.Net`/
`Ess.UI`/`Ess.Contract` adopt-aliases — `40_gfx.lua`, `41_scrolllog.lua`, `95_ui_easy.lua`, `99_adopt.lua`),
Group J (`Ess.Override` — `90_override.lua`), and all of Group G (the tiered `Ess.AIOrders`/`Ess.Relations`/
`Ess.Triggers`/`Ess.Sandbox`). Full specs for every one of these are in `FEATURE_SHEET.md`'s namespace
catalog — go read the relevant row(s) before implementing, don't work from memory of this briefing alone.

**★ CRITICAL, easy to forget: `build/merge.py`'s `MANIFEST` list is a hand-maintained, EXPLICIT ordered
list, not a glob.** A new `src/*.lua` file that isn't added to `MANIFEST` will silently NOT be built into
`dist/Ess.lua` — you'll edit a file, rebuild, redeploy, retest, and be confused why nothing changed. Add
every new file to `MANIFEST` in the same edit where you create it. For any TIERED namespace (Mark, or
Group G's four), remember Raw must load before Core before Easy — `MANIFEST`'s listed order is what
governs this, NOT alphabetical filename order (which gets `_raw`/`_easy` suffixes backwards).

## 4. Priority-ordered task list for tonight

Work roughly in this order — earlier items are safer, higher-confidence, and testable from inside the
HQ; later items carry more risk or need more re-reading first. Don't feel bound to strict sequencing if
something's blocked; use judgment.

1. **Smoke-test the existing 10 files' untested functions** (see §3) — cheap, closes a real gap, and
   confirms your dev-loop is working before you build on top of it.
2. **`Ess.Bones` (`src/50_bones.lua`)** — `attachFX`/`waitForReady`/`aimVector`/`probeNames`, per
   FEATURE_SHEET Group F. High confidence this works from the HQ interior: bone/hardpoint operations on
   the PLAYER CHARACTER's own skeleton were CONFIRMED working live regardless of location
   (`human-skeleton-boneprobe` memory) — re-read that memory and `wiki/deep-dives/bone-manipulation.md`
   before implementing. Test by attaching an FX to your own character's bones and reading back a hardpoint
   position — no outdoor world needed.
3. **`Ess.Camera` (`src/51_camera.lua`)** — re-read `wiki/deep-dives/freecam.md`/`destroyer-vehicle.md`
   first. `lookAtAnchor`/`staleAxisDecay`/`followHardpoint` should be testable on your own character/camera
   indoors; note the KNOWN HARD LIMIT (no Lua touchpoint for a driving/gunning camera) doesn't apply here
   since you're not testing from inside a vehicle.
4. **`Ess.Points` (`src/52_points.lua`)** — `bucket`/`ideal` are pure data transforms (radius bucketing,
   distance-window selection) ported from `WaveDefense.lua`'s `bucketArena`/`idealPoints` — no live world
   needed at all, test with synthetic coordinate tables via `--code`.
5. **Group E — `Ess.Gfx` (`src/40_gfx.lua`)** — the FlashWidget primitives. **A HUD widget renders
   regardless of indoor/outdoor location** (it's a screen overlay, not world geometry) — this is fully
   testable from the HQ. Re-read `wiki/deep-dives/custom-ui.md` and the corner-coordinate bug already
   documented in FEATURE_SHEET's Known Bugs #1 before implementing `Ess.Gfx.widget` — get that right the
   first time, it's the whole point of this namespace existing.
6. **Group E — `Ess.Net`/`Ess.UI`/`Ess.Contract` adopt-aliases (`src/99_adopt.lua`)** — thin, existence-
   checked aliases (`Ess.Net = ModNet` etc.) IF those frameworks are deployed alongside `Ess` in the same
   game install; if they're not currently deployed there, write the alias code defensively (existence-
   checked, never a hard dependency, per FEATURE_SHEET) and note it as untestable-right-now rather than
   skipping it.
7. **Group J — `Ess.Override` (`src/90_override.lua`)** — small, safe, no live-world dependency at all
   (it's a meta-helper for safely wrapping functions). Fine to slot in whenever convenient.
8. **Group G — ONLY after re-reading the FULL current source of both**
   `C:\Users\logan\source\repos\mercs2-lua-mods\mods\lua-wave-defense\scripts\OnLoad\1_ContractFramework.lua`
   **and** `...\lua-wave-defense\WaveDefense.lua` (an earlier design pass only got through ~70% of each
   before hitting a read-length limit — do not extract from a summary again, read the real files this time,
   they're not that long). Build `Ess.AIOrders`/`Ess.Relations`/`Ess.Triggers`/`Ess.Sandbox` as NEW,
   STANDALONE code in `mercs2-lua-essentials` (this is safe and in-scope). **Do NOT edit
   `ContractFramework.lua`/`WaveDefense.lua` themselves to consume the new Ess code** — that's a separate,
   more invasive refactor of an already-working, co-op-tested file in a DIFFERENT repo, and should wait for
   explicit review, not happen unsupervised. Building the tiered Ess.* versions standalone and testing them
   independently is the right scope for tonight.

After each item: update `FEATURE_SHEET.md`'s "Implementation status" section, commit locally (see §6), and
append one line to the Progress Log at the bottom of THIS file (§8) so a later compaction cycle tonight can
see what already happened without re-deriving it.

## 5. Safety rules — non-negotiable, unsupervised session

- **Scope: stay inside `mercs2-lua-essentials`.** Do not edit files in `mercs2-lua-mods` or
  `mercs2-layer-framework` (the other repos `Ess` will eventually adopt/alias) without that being an
  explicit, reviewed decision — not something to do autonomously overnight.
- **Never push to any remote**, anywhere. Commit locally only (none of these repos even have a remote
  configured, but the rule stands regardless).
- **Do not attempt to teleport/relocate the character out of the PMC HQ interior.** The AI primer's own
  documented hard limit: multi-player teleport helpers are confirmed to crash the game when used from
  inside an interior cell. Work within the HQ; don't try to engineer your way outdoors.
- **Never call `Pg.Spawn` with a blank/whitespace template string** — confirmed hard engine crash, not
  even catchable by `pcall`. Every `Ess` function that reaches `Pg.Spawn` already validates this; if you
  write new code that spawns anything, validate first.
- **Never wrap `dynamic_import`/`dynamic_remove`**, even transparently — confirmed crash, unrelated to
  anything `Ess` needs.
- **Never write `return fOriginal(...)` inside an override wrapper** — tail-call, breaks the engine's
  module system. `Ess.Override` (§4 item 7) exists specifically to make this mistake structurally
  unavailable; if you build it, get this right.
- **If the game crashes:** don't panic-retry the same operation in a loop. Note what you were doing, check
  `launch.py --status`, relaunch via the standard dev-loop, and try something else. If the SAME specific
  operation crashes it twice, stop attempting that one thing, log it as a wall for that item, and move on
  — don't burn the rest of the night on one crash.
- **When genuinely uncertain whether something is safe to try:** skip it and note it as "flagged for
  Logan" rather than guessing. This mirrors how `Ess.Vehicle.enterSeatExcluding` and
  `Ess.Input.hijackController` were already handled honestly in Group B/C — a documented gap beats a
  fabricated confidence.

## 6. Housekeeping — commit + document as you go, exactly like tonight's session did

For each namespace you finish: `python -m py_compile` the new file (or the whole merge) as a syntax
sanity check, add it to `build/merge.py`'s `MANIFEST`, rebuild, redeploy, live-test via the dev-loop, THEN
`git add`/`git commit` (local only) with a message describing what was built and what was actually
confirmed live vs. just load-checked — match the honesty level of tonight's commits (e.g. `9911b7d`,
`b1434d8`) which explicitly separated "loads clean" from "behaviorally verified." Update
`FEATURE_SHEET.md`'s Implementation status section every time, not just at the end — if the night ends
abruptly, that section should always reflect true current state.

## 7. When to stop

- Logan tells you to stop.
- A genuine hard wall: something that blocks ALL remaining reachable work, not just one item (e.g., the
  game itself becomes unlaunchable and troubleshooting `launch.py`/the bridge doesn't resolve it within a
  reasonable number of tries — note what you tried, don't loop on it forever).
- You've actually worked through everything in §4 down to the point where the only remaining work is
  either (a) genuinely outdoor-only and can't be reached from the HQ, or (b) the deferred
  ContractFramework.lua/WaveDefense.lua refactor that's explicitly out of scope for an unsupervised
  session. If you get here, say so clearly and stop rather than inventing busywork.

## 8. Key file/path quick-reference

| What | Where |
|---|---|
| This repo | `C:\Users\logan\source\repos\mercs2-lua-essentials` |
| Design spec | `FEATURE_SHEET.md` (repo root) |
| Dev-loop procedure | `.claude/skills/ess-live-test/SKILL.md` |
| Source (10 files, done) | `src/00_core.lua` … `src/53_rng.lua` (see §3) |
| Build script | `build/merge.py` (hand-edit `MANIFEST` for every new file!) |
| Deployable output | `dist/Ess.lua` (gitignored, build it: `python build/merge.py`) |
| Controller emulator | `tools/xpad.py` |
| Launcher | `tools/launch.py` |
| Live REPL | `tools/lua_repl.py` |
| Game install | `C:\Games\Mercenaries 2 World in Flames` |
| Wiki (extrapolation source) | `C:\Users\logan\Desktop\Mercs2_Decompiled_Lua\docs\mercs2-luacd\wiki\` (namespaces/, deep-dives/, resident/) |
| Decompiled source (ground truth) | `C:\Users\logan\Desktop\Mercs2_Decompiled_Lua\docs\mercs2-luacd\src\` |
| ContractFramework/WaveDefense (Group G source) | `C:\Users\logan\source\repos\mercs2-lua-mods\mods\lua-wave-defense\` |
| Persistent memory index | `~/.claude/projects/<this-project-slug>/memory/MEMORY.md` — search for `ess-` prefixed entries first |

---

## Progress log (append one line per completed item, newest at bottom)

- 2026-07-16 23:xx — briefing written, no autonomous work started yet.
- 2026-07-16 (overnight start) — fixed a real bug in `lua_repl.py`: `--wait-log`/`--since-bytes` silently
  timed out forever if the log was truncated (by a fresh game launch) below the recorded offset. Fixed in
  both poll functions, committed `fcfd4d3`.
- 2026-07-16 (overnight) — smoke-tested ALL of Groups A-D + RNG live (item 1 of §4 done). All passed.
  Two real discoveries logged in FEATURE_SHEET.md + in-source comments: `Player.slot(1)` non-nil in
  single-player (not a valid co-op check, use `character(1)`); spawn+enter-vehicle from the PMC HQ interior
  preceded a 30s+ bridge stall, recovered via process kill+relaunch, causation unconfirmed but flagged.
  Committed `e178e6b`. Moving to item 2 (`Ess.Bones`) next.
- 2026-07-16 (overnight) — hit a real stall during smoke-testing: spawning+entering a Veyron from inside
  the PMC HQ interior preceded the bridge's Lua tick freezing for 30s+ (process alive/"Responding", zero
  chunks executed). Recovered via process kill + relaunch (single-instance lock meant `launch.py --all`
  silently failed with exit 1 until the old process was actually gone — watch for that pattern). Flagged
  in `src/12_vehicle.lua`, not repeated.
- 2026-07-16 (overnight) — built + live-verified items 2-4 (`Ess.Bones`/`Ess.Camera`/`Ess.Points`, the rest
  of Group F). All functions individually exercised live, all passed. Committed `86e57b7`. Moving to item
  5 (`Ess.Gfx`) next.
- 2026-07-16 (overnight) — built + live-verified items 5-7 (`Ess.Gfx`, the `Ess.Net`/`UI`/`Contract`
  adopt-aliases, `Ess.Override`). Tested Gfx against a real pre-existing "minimap" asset rather than
  authoring a new WAD patch (deliberately out of scope tonight). Found + resolved a REPL-testing-
  methodology quirk along the way (multi-return values fed directly into `tostring(...)` can misbehave in
  this engine — not an Ess bug, just don't test that way; noted in FEATURE_SHEET.md). Committed `2854635`.
  Only item 8 (Group G) remains — starting the required full re-read of ContractFramework.lua/
  WaveDefense.lua now, per the explicit instruction not to work from a prior summary this time.
- 2026-07-16 (overnight) — fully re-read both ContractFramework.lua (1265 lines) and WaveDefense.lua
  (1601 lines) end to end (not a summary), then built + live-verified ALL of Group G: `Ess.AIOrders`/
  `Ess.Relations`/`Ess.Triggers`/`Ess.Sandbox`, Raw/Core/Easy tiers, 12 files. Fixed two real bugs found
  reading the source (Known Bugs #2 and #3 — Triggers' gate-input validation, Relations' restore-on-
  failed-read). Sandbox is the first production use of Ess.Override.wrap. Committed `31d5866`. This
  completes ALL 8 items in this briefing's §4 priority list.
- 2026-07-16 (overnight) — §4 fully complete, but clearly more well-specified, safe, in-scope work
  remained in FEATURE_SHEET.md's own catalog (not busywork — real unbuilt rows with real specs), so
  continued rather than stopping early: built + live-verified `Ess.Mark` (`871c2bc`, the tiered design's
  own motivating example), `Ess.Net.hijackCallback` (`785fb16`, generalizes ModNet's confirmed black-
  screen fix; also caught+fixed a real adopt-ordering bug this introduced in 99_adopt.lua), and
  `Ess.ScrollLog` (`4ca6789`, the MrxGuiTextBuffer workaround — caught+fixed a real missing-`import()` bug
  live, which `loadcheck.py`'s stub couldn't have caught at all).
- 2026-07-16 (overnight) — **stopping point reached.** Every namespace in FEATURE_SHEET.md's catalog is
  now built and live-verified EXCEPT: (a) the parts of `Ess.Net`/`Ess.UI`/`Ess.Contract` that need
  ModNet/uilib/ContractFramework actually deployed alongside Ess to test against (not the case in this
  install; the alias mechanism itself is already correctly wired, defensively, in `99_adopt.lua`), (b)
  refactoring `ContractFramework.lua`/`WaveDefense.lua` themselves to consume the new code (explicitly
  out of scope for an unsupervised session per §5), and (c) `Ess.Input.hijackController`, a gap that
  predates tonight and needs a qualitatively different kind of test (real controller-driven PDA
  interaction) than the REPL-based pattern this whole session used. This matches §7's stopping condition
  exactly — remaining work is genuinely blocked, out of scope, or a different category of task, not
  something to keep inventing around. Stopping here.
