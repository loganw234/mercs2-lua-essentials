# EXAMPLE-MISSION BRIEFING — hardened compaction note (rewritten 2026-07-17, session 2)

You (Claude) are mid-project building **the Ess ("Essentials") Lua framework for Mercenaries 2** and, on top
of it, **authoring an example mission end-to-end as a consumer test**. This note is the authoritative resume
anchor after a compaction. Read it fully, then continue. Self-contained on purpose.

---

## 1. THE TASK RIGHT NOW

Author a full example mission through the real pipeline (MissionForge → export → `Ess.Contract`), as a
new-ish user would, to surface friction — and fix the tooling live as we hit it. **Logan designs; I build
tooling + fix friction.**

**THE MISSION (Logan's design):** an **offshore oil refinery (an oil rig)** — Logan found a good one in-game
and has the basic initial layout started. **Allies defend it; China assaults it; the player BACKS CHINA**
("The Allies have too much oil, we'd like you to relieve them of it" — a real VO line to reuse for the intro).
**Intro cinematic:** helicopters fly in and the player watches from a vantage as the attack kicks off before
getting involved — an **air wave** clears the rig's air defenses (a **scripted missile strikes a SAM site
Logan places**, and the SAM is allowed to get a round or two off so some incoming helis get shot down for
drama), then a **friendly (Chinese) transport lands**, **fade to black**, and the player is **dropped at the
"exit" point** to begin real gameplay. Logan has **basic objective-flow points laid out to be tested next.**

**Relations for this mission (one call):** `Ess.Easy.Relations.sideWith("China", "Allied")` — China↔Allied
hostile, PMC(you)↔China ally, PMC↔Allied hostile. (Verified.)

**IMMEDIATE NEXT STEP after reading this:** confirm with Logan where he left off (he said the basic start +
objective-flow points are laid out), then keep authoring — help him place/wire objectives in MissionForge and
turn the export into a running `Ess.Contract`, and build the intro cutscene as `Ess.Cinematic` steps.

---

## 1b. SESSION 3 PROGRESS (mission BUILT + tested once, reworked; staged for a re-test)

The mission is authored + live-ran once, end-to-end (`prog` reached 0.67 — interact→survive worked; the
extract leg + cutscene surfaced fixes). It is **generated** from Logan's MissionForge export:
- `samples/missions/refinery_assault.export.txt` — Logan's raw export (84 units etc.).
- `tools/mkmission_refinery.py` — turns the export → `samples/missions/refinery_assault.lua` (the runnable
  `Ess.Contract`). The bulky `def.units` (70, cinematic-owned 14 excluded, faction-regrouped ALLIED/
  ALLIED_NAVY/CHINA) are machine-generated; the intro cinematic + objective/trigger/FX wiring are
  hand-authored constants in the script. **Re-place in MissionForge → re-export → re-run the script to
  keep coords in sync.** (This is the first real piece of the export→Ess.Contract pipeline the friction
  log wants; the web tool still emits old `Contract.Register`.)
- **Run it:** `python tools/lua_repl.py --file samples/missions/refinery_assault.lua` (registers + accepts).

**TEST #1 FINDINGS (Logan watched) + what I fixed this session (all built + loadcheck-clean + deployed,
NOT yet live-verified — game was closed to reset the rig):**
1. Only 2 helis flew + the downing fired instantly, before the flight read → **reworked cutscene**: spawn
   the WHOLE wave first (5 helis) so the establish shot frames them massing, `fly` all 5 fanned in, a **12s
   trailing `chase`** on the lead (watch them cross the rig), THEN frame the pad, THEN the downing + arty.
2. The strike destroys the landing pad → **extract point MOVED** to the original transport-landing spot
   (`-455.63, 9.85, 2635.81`, back where you start) — you retreat there.
3. All proximity FX triggers fired on the INBOUND path (they sit between spawn z2636 and the objective
   z2737) → **FX re-gated behind the charge arming**: a `{kind="objective", index=2}` trigger fires the
   arty/vfx/flybys when the SURVIVE objective completes (the "rig comes down as you fall back" cascade),
   not raw proximity.
4. **The rig genuinely COLLAPSES** under the explosions/RPGs (Logan: "very visually pleasing") — that's why
   the player ended at y=-36 (in the sea). → mission now uses **`sandbox = true`** (new framework feature)
   so saves are gated + the destruction never serializes.
5. Logan wants "extract = done" replaced with **board the transport (no transit UI) + a couple victory-lap
   orbits, THEN finalize** → built as a framework feature (see §5). The extract objective now uses it.

**NEW FRAMEWORK FEATURES built this session (in `dist`, deployed):**
- **`def.sandbox`** on `Ess.Contract` (`true` | `{providers=,opts=}`) — wraps the whole contract in an
  `Ess.Sandbox` (save-gate + `layers` provider), begun at Accept, finished at complete/fail/abort. For a
  mission that destroys a persistent set piece. `Ess.Layers.begin` only snapshots+gates (no geometry
  change) so it's safe. **The save-gate is the guaranteed win (destroyed rig never serializes → pristine
  next load). The IN-SESSION visual restore (swapping the pristine layer live) is UNVERIFIED — a flagged
  live experiment (the rig is the Merida oil rig, layers `vz_state_mer_oilrig_pristine`, dynamic/toggleable
  per the [[layer-framework-project]] work).**
- **`Ess.Contract.Extract{ ..., heli=, victoryLap={orbits,radius,height,line,cam*} }`** — on reaching+
  holding the LZ, seats the player in the crewed heli via `Ess.Vehicle.enterSeatExcluding(pc,heli,{"d"})`
  (**EnterBySeatGuid, NOT MrxTransit → no transit UI**, the pattern from `src/vz/oilcon002.lua`), then
  `Ess.Vehicle.orbitFlight(heli, cx,cy,cz, {...})` flies a couple laps while an `Ess.Cinematic` chase
  watches, then completes. New helper **`Ess.Vehicle.orbitFlight`** (12_vehicle.lua).
- **interact objective now draws a ground ring** when it's a bare point (81_contract_objectives.lua) — was
  invisible for a plant/hack/sabotage-a-spot objective.

**RE-TEST NEXT (game must be relaunched fresh — Logan closed it to reset the collapsed rig):** relaunch →
`python tools/lua_repl.py --file samples/missions/refinery_assault.lua` → watch the reworked cutscene (does
the wave fly + pan for ~12s? does the downing land after? does the arty clear the pad?), then play through
interact→survive→**the FX cascade + rig collapse on charge-arm**→retreat to the transport→**victory-lap
orbits**→complete. Then judge: cutscene polish, does the victory lap read well, does the sandbox save-gate
hold (and optionally try a live `Ess.Layers.swap` of the pristine rig layer to restore geometry in-session).

---

## 2. DEPLOYED SETUP (NEW — no more hot-reloading Ess each session)

The game now boots with everything deployed:
- **Ess auto-loads:** `dist/Ess.lua` is deployed to `C:\Games\Mercenaries 2 World in Flames\scripts\OnLoad\1_Ess.lua`, registered in `scripts\lua_loader.ini` as `[OnLoad] 1_Ess.lua=5`. It loads on world load — `_G.Ess` is just there. (CONFIRMED loading fine.)
- **MissionForge on F7:** deployed to `scripts\OnKey\MissionForge.lua`, registered `[OnKey] MissionForge.lua=F7`. Press F7 in-game to open it. (CONFIRMED working.)
- **Redeploy after editing** (Ess): `python tools/launch.py --build --deploy` (rebuilds dist + copies to OnLoad + updates the ini). Or just `cp dist/Ess.lua "<game>/scripts/OnLoad/1_Ess.lua"`.
- **Redeploy MissionForge:** edit the REPO copy, then `cp "<repo>/samples/OnKey/MissionForge.lua" "<game>/scripts/OnKey/MissionForge.lua"`. The game re-reads the OnKey file on each F7 press (state in `_G.MissionForge` persists across the re-run), so a re-deploy + two F7 taps refreshes it without losing placements.
- **Relaunch (after a crash / to boot fresh):** `python tools/launch.py --all` (build→deploy→launch→skip-intro; reaches a loaded game). It does NOT touch OnKey/ or the ini's `[OnKey]`, so MissionForge survives. After it, teleport to the safe spot (below) since you boot at the default location.

---

## 3. REPOS & SOURCES OF TRUTH

- **Ess framework:** `C:\Users\logan\source\repos\mercs2-lua-essentials` (local git, NO remote). `src/NN_*.lua`
  → `python build/merge.py` → `dist/Ess.lua` (gitignored; MANIFEST is explicit in build/merge.py). `CAPABILITIES.md`
  = current surface. Commit when things work; end body with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **MissionForge:** NOW repo-tracked at `mercs2-lua-essentials/samples/OnKey/MissionForge.lua` (the source of
  truth). The game's `scripts/Misc/MissionForge.lua` is the OLD location — **stale, ignore it** (don't edit it).
- **Docs/corpus repo:** `C:\Users\logan\Desktop\Mercs2_Decompiled_Lua\docs\mercs2-luacd` (CWD) — the wiki + decompiled
  game source (`src/{resident,vz,shell}`, real call sites) + `tools/loadcheck.py` (offline load checker). The
  **web tool** is here: `tools/missionforge/index.html` — parses `MISSIONFORGE_EXPORT` → generates a contract,
  but STILL emits old `Contract.Register{}`, NOT `Ess.Contract.Register{}` (a known friction gap, see §6).

---

## 4. DEV-LOOP & TOOLS (operationally load-bearing)

1. Edit `src/*.lua` (Ess) or `samples/OnKey/MissionForge.lua`.
2. `cd <ess-repo> && python build/merge.py` (rebuild dist; only for Ess src changes).
3. `python tools/loadcheck.py "<file>"` — **run from the DOCS repo**. Offline lupa check; "chunk loaded to
   completion OK" = good. (MissionForge guards on Ess, so under loadcheck it bails at the guard — that's fine,
   it still validates syntax.)
4. Deploy (see §2), or hot-test via the bridge:
   `python "<ess-repo>/tools/lua_repl.py" --code '<lua>'` / `--file <file>`.
   ⚠ **Bridge read is FLAKY** (one-behind, batches, TIMEOUTs though the chunk ran). Route results through
   `Loader.Printf("[TAG] ...")` and read the log: `grep "\[TAG\]" "<game>/scripts/lua_loader_printf.log" | tail`.
   ⚠ **Hot-reloading the WHOLE dist resets `Ess.Loop._reg`** (kills running loops). To add/patch ONE namespace
   live WITHOUT killing loops, `--file` just that one `src/NN_*.lua` (e.g. reloaded `61_relations_easy.lua`
   to add `war`/`sideWith` while a heli-boost loop kept running).
5. **Smoke test before shipping Ess:** `python tools/smoke.py` — reloads dist + runs `samples/recipes/*.lua`,
   reports PASS/FAIL (19/19 currently). Add a recipe when you add a namespace. (See memory [[ess-samples-and-smoketest]].)
- **Stop the game:** PowerShell `Get-Process Mercenaries2 -ErrorAction SilentlyContinue | Stop-Process -Force`.

---

## 5. FRAMEWORK STATE (all committed, main; HEAD ≈ `c7a6f99`)

Ess is deployed + current. Namespaces most relevant to the mission (full surface in `CAPABILITIES.md`):
- **`Ess.Cinematic`** (`src/65_cinematic.lua`) — the cutscene-timeline runtime this mission's intro rides.
  `.play(steps, opts)` / `.define(id,steps)` / `.playNamed(id)` / `.skip()` / `.stop()`. Steps: camera(cut/
  track/dolly)/orbit/chase/wait/spawn/face/order/fly/say/banner/subtitle/hint/vo/music/sound/fade/shake/
  teleport/relations/func — each paced by a per-step `hold` (0 = fire together). Shared `ctx`: a spawn's
  `name=`/`group=` register actors later steps reference. **Skippable (ESC)**, always restores control/clears
  fade. **Contract hook:** `def.cinematic` (inline steps OR a named-id string) plays as a GATED intro
  (objectives wait for it); trigger-fired mid-mission via a `{effect="cinematic", steps=|cinematic="id"}`
  support effect. See memory [[mercs2-cinematic-camera-and-heli-nav]] for the camera rules it's built on.
- **`Ess.Contract`** — the ephemeral mission engine. `.Register{def}` / `.Accept(id)` / `.Abort()` / `.Status()`;
  16 objective builders (Destroy/Reach/Defend/Escort/Hold/Survive/Extract/Race/Chase/Verify/…); `def.start`
  (teleport heroes), `def.relations`, `def.units`(grouped), `def.waypoints`(AI orders), `def.support`,
  `def.triggers`, `def.cinematic`, reward{cash,fuel}, onComplete/onFail.
- **`Ess.Easy.Relations`** — `.war(a,b)`, **`.sideWith(friend,foe)`** (this mission's stance), `.makeHostile`,
  `.makeAllies`, `.restore`. (`.war`/`.sideWith` were friction fix #1.)
- **`Ess.Impulse`** (3-tier, `src/16_impulse.lua`) — `Ess.Easy.Impulse.speedBoost/launch/knockback`,
  `Ess.Impulse.push{forward,up,side/dir,scaleByMass}`/`.spin`; mass-scaled via `Object.GetMass` (which reads
  nil until the object settles). ⚠ **A vehicle spun TOO hard CTDs the physics engine** — keep spins gentle.
- **`Ess.Math`** (`01_math.lua`): clamp/lerp/round/dist2D/dist3D/angleTo/pointAhead/normDeg (engine yaw conv).
- **`Ess.Object.faceToward(g,x,y,z)`/`.faceObject(g,tgt)`**; **`Ess.Hud.objective(text)`/`.radio(text,hold)`**;
  **`Ess.Input.held(vk)`** (non-draining key check — use in a loop running alongside a menu); **`Ess.Camera.blend(i,dur)`**
  (re-arm a cinematic blend for a smooth discrete camera move).

---

## 6. MISSIONFORGE STATE (the authoring tool, F7)

Refactored onto Ess (spawn/markers/input/heartbeat/widget all `Ess.*`). Drop-at-your-position placement of
units/objectives/support/triggers/AI-orders → exports a `MISSIONFORGE_EXPORT = {…}` block to the log.
**New this session:**
- **CINEMATIC branch** (F7 → CINEMATIC): **Give Helicopter (fly)** = an invincible heli (you invincible too),
  **hold Shift to boost** — for placing camera points in the air; **Loading Preview** (the establishing
  bird's-eye the mission opens on while the scene spawns/settles); **Camera Shot** (a vantage — captures your
  position + FACING, so aim by facing it); **Look-at Point**. These export as a `cinematic = { {kind,x,y,z,yaw} }`
  block. Camera points are sky-blue markers.
- **Catalog enriched 241 → 386 templates** (community spawn strings): new top-level branches **PMC** (heroes +
  vehicles), **CIVILIANS**, **WEAPONS** (pickups, kind=prop), **SUPPORT AIRCRAFT** (jets/planes, kind=vehicle).
- **Forge controls:** arrows move, ←/→ back/open, **P**/Enter place-at-position, **End** export, **T** cycle group,
  Backspace undo, Delete remove-nearest, `,`/`.` objective radius.

**THE PIPELINE GAP (friction, not yet fixed):** the web tool + the cinematic block. The web tool (`docs/…/tools/
missionforge/index.html`) still emits `Contract.Register{}` (old framework) and does NOT ingest the new
`cinematic` block. **For now: hand-author the `def.cinematic` (Ess.Cinematic steps) from the exported camera
points, and hand-write / adapt the `Ess.Contract.Register{}`** — logging the friction. Fixing the web tool to
target `Ess.Contract` + ingest cinematics is a planned task (see the friction log).

---

## 7. FRICTION LOG

`mercs2-lua-essentials/tools/EXAMPLE_MISSION_FRICTION.md` — the running consumer-test findings. #1 (relations
faction-vs-faction gap) FIXED via `war`/`sideWith`. Open/known: web tool emits old `Contract.Register`; no
cinematic authoring in the web tool. **Keep logging every awkward/missing/raw-call moment as we author.**

---

## 8. TESTING ENVIRONMENT & GOTCHAS

- **Safe open-world spot:** `Ess.Player.teleport(2739.7, -14, -786)` (a flat airfield). The refinery is
  elsewhere (Logan flies there). Player HP 120; fall damage caps ~97 (heal with `Ess.Object.heal(char)`).
- **Confirmed spawnables:** `"blanco"` (test char), `"Veyron"`, `"AH1Z (Full)"` (crewed+flying — a bare
  `"AH1Z"` has no pilot and just falls), `"UH1 Transport"`. `(Full)` tag = crewed. Heli nav = `Ess.Vehicle.flyTo`
  (Ai.Deliver), NOT a move order.
- **Camera:** a MOVING camera needs `Camera.Blend(c,0)` (or `Ess.Easy.Camera.watch/orbit/chase`); DISCRETE
  smooth moves use `Ess.Camera.blend(i,1)` + one `placeCamera`. Object-attach camera is a dead end. Track a
  moving vehicle via its pilot's `Bone_Chest`. High-velocity subjects jitter → use a static watch.
- **Atmosphere/weather is REGION-GATED** (only in a real map region, not the airfield) — [[mercs2-atmosphere-region-gating]].
- **Freshly spawned:** hardpoints/bones read 0,0,0 and `GetMass` reads nil for ~0.3s — let it settle.
- **⚠ Physics CTD:** a wildly-spinning vehicle can crash the engine (it crashed once on an over-strong stunt);
  keep `Ess.Impulse.spin` gentle + few. Late-session live flakiness after many hot-reloads/spawns = cumulative
  cruft → relaunch fresh, don't chase a phantom bug.
- Conventions: read `docs/mercs2-luacd/wiki/ai-primer.md` before writing Lua; `Loader.Printf` not Debug.Printf;
  `import()` file-scoped; Lua 5.1; confirmed-only discipline; `Ess.Probe.nearby` excludes the player. WaveDefense
  is untouched.

## 9. MEMORY POINTERS
`MEMORY.md` index. Especially: [[ess-essentials-framework-project]], [[active-world-forge-project]] (MissionForge
+ cinematic suite roadmap + review items), [[ess-samples-and-smoketest]], [[mercs2-cinematic-camera-and-heli-nav]],
[[mercs2-atmosphere-region-gating]], [[ess-open-world-testing-spot]], [[custom-contract-framework]], [[read-ai-primer-before-lua]].
