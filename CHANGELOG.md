# Changelog

All notable changes to Ess are recorded here. Versions track `Ess.VERSION` in `src/00_core.lua`.

Releases are automatic: **bump `Ess.VERSION`, add a matching `## [x.y.z]` section below, and push to
`master`**. `.github/workflows/release.yml` then builds a fresh `1_Ess.lua`, syntax-checks it, packages the
zip, and publishes a GitHub Release tagged `v<version>` using that section as the notes. (No section for the
version? It still releases, with auto-generated commit notes.) See the README's "Releasing" section.

## [Unreleased]

## [0.5.0]

**The engine-native sweep, a UI kit that draws itself, and the visual editor finally fed from the source.**
720 public functions, up from 434 — and every one of them now has a node definition, where before 509 of
them were invisible to the node editor entirely.

Most of this came out of live probing against a running game rather than reading the decompiled scripts, and
the traps below are recorded because none of them are guessable from a function name.

### Added

- **`Ess.Pda`** — the mission log, dossier, statistics and map layer. `mission()`/`missionExists()` register
  a real trackable PDA mission; a blip naming one becomes a mission blip and inherits its icon and label.
- **`Ess.Hud`** grew `title` (the stylised animated overlay), `location`, `message` (negative duration =
  permanent), `tutorial`, `image`, and the cash/fuel readouts — display-only, they move the number on screen
  and not the money.
- **`Ess.Hud.Faction`** — the faction meters, the pursuit gauge, and `timer()`, the only on-screen countdown
  the game exposes, with real HUD chrome and a callback on expiry.
- **`Ess.Minimap`** — the minimap *widget*, which no `Hud.*` function reaches. `lockRange` owns the update
  handler so a zoom sticks; the game otherwise recomputes it from player speed every update.
- **`Ess.Gps`**, **`Ess.Shop`** (the game's real full-screen purchase UI, filled with your own items),
  **`Ess.Sys`**, **`Ess.Atmosphere`**, **`Ess.UI.Theme`**.
- **`Ess.On.script(name, fn)`** — react to the ~28 named events the shipped game posts (`"PDA Open"`,
  `"SupportUsed"`, the Satellite events…). Ess previously had no way to hear any of them.
- **`Ess.Sound`** gained cue validation (`duration`/`isCue`/`isLooping` — a mistyped cue is otherwise
  completely silent) and the category mixer.
- **`tools/checksyntax.py`** — compiles every `src/` file plus the built dist offline. `checkpure.py` covers
  11 pure files; a syntax error in the other 73 was previously invisible until a live load.
- **`samples/recipes/theme_the_ui.lua`** — restyling the kit, and a smoke recipe.

### Changed

- **The UI kit draws at runtime from theme data.** One movie replaces eight; the 8-line panel, 3-toast and
  5-chat-line caps are gone because rows are built on demand. `Ess.UI.Theme` is ~36 plain values with seven
  presets. Async load is handled through `SetSwfFile`'s completion callback instead of eight blind repaints.
- **`Ess.Mark`'s three layers agree.** The world, radar and PDA surfaces do not share an icon namespace, and
  the kind table only ever named two of the three — so a "destroy" objective drew a destroy icon in the world
  and on the radar, and an anonymous dot on the map. `Ess.Mark.KINDS` now names all three for every kind.
- **`natives.json` is honest about what is native.** `Hud.*` and `Pda.*` are not engine natives — they are
  resident Lua published under a different global, so 143 functions filed as black boxes have readable
  source. Engine surface 1108 → 965.
- The release zip carries `api/ess-nodes.generated.js` so a browser editor can load the node set from a
  `file://` page.

### Fixed

- **`icon_yellow_mc` draws nothing.** It is a registered icon name with no art, it was the engine's own
  last-resort fallback, and it was Ess's default in three places — which is why `Ess.Mark`'s PDA blips were
  never visible. Earlier diagnosis blamed the missing label; that was only half of it.
- **`Ess.Object.angularImpulse` defaulted to world space** while `.impulse` defaults to local, under a
  comment promising "same argument shape". Aligned.
- **`Ess.Human.setState` now validates the posture.** The native reports nothing for a valid state *and* for
  garbage, so a wrapper guard is the only place a typo can ever be caught.
- **`Ess.UI.setScale` no longer builds the whole UI** as a side effect of setting a number.
- **The widget rect counted the UI scale twice**, so a 520-unit panel covered 61% of the screen instead of
  27%.
- Several silent-failure paths now report on the `Ess.DEBUG` channel instead of returning a bare `false`.

### Notes

- **Not wrapped, because they are dead:** `Pda.Database.AddHelpEntry` (writes a table nothing reads),
  `Hud.FactionDisplay.RemoveMeter`/`RemoveAllMeters` and `ShowAll` (empty bodies), and `Hud.Tutorial`'s two
  `ShowTutorial*` functions (broken for any explicit player).
- **`Ess.Hud.Faction.levels` is globally destructive** — it replaces the game's own faction mood names for
  every faction until the level reloads. `restoreLevels()` undoes it.

## [0.4.2]

**Tooling only — the framework itself is unchanged.** `1_Ess.lua` is byte-identical to 0.4.1's apart from the
version string and the build stamp; `src/` has no functional change in this release. If you only install the
framework, this release gives you nothing new and there is no reason to update. It is versioned at all because
the release *zip* now carries a new file.

**What's new is node definitions for the visual editor, generated from the API and enriched by hand.** The
node-graph editor at [visual.mercs2.tools](https://visual.mercs2.tools) is how most beginners will meet this
framework, and its ~200 nodes were hand-written against `src/*.lua` — accurate, but maintained by memory. This
generates them from `ess.json` instead, and pairs that with a hand-authored overlay carrying the thing a
signature can never carry: what a parameter is *for*, what units it's in, and which of them will silently do
nothing.

**486 nodes, every one enriched by hand against the real source**, with all 896 parameters carrying a
confirmed type, a working default and an explanation — plus 62 functions deliberately skipped, each with a
written reason. 93 of the nodes are the `Ess.Easy.*` beginner tier; 138 are pure getters that wire into other
nodes' inputs.

Nothing in the editor's own repo is touched. This produces the data; adopting it is a separate, deliberate step.

### Added

- **`build/nodes.py`** — merges `dist/ess.json` (what exists) with `api/nodes.overlay.json` (what it means)
  into `dist/nodes.json`, plus `dist/ess-nodes.generated.js`, a working litegraph consumer that proves the data
  is sufficient. `--check` is a drift gate; `--report` shows coverage.
- **`api/nodes.overlay.json`** — the hand-authored half. **The overlay cannot invent anything**: every entry is
  validated against `ess.json`, so one naming a function that doesn't exist, or giving a function a parameter it
  doesn't have, fails the build. It adds *meaning* to a real signature and can never add a signature.
- **`build/merge_overlay.py`** — assembles per-namespace overlay fragments, validating before writing and
  rejecting overlaps, invented names and bad types rather than absorbing them.
- **`tools/test_nodes.js`** — executes the generated nodes against a stubbed editor and asserts the **Lua they
  produce**. No browser, no editor checkout, no game. The load-bearing check is that a `guid` parameter is
  spliced raw rather than quoted: a quoted handle produces Lua that runs, logs nothing and does nothing —
  exactly the silence `Ess.DEBUG` exists to fight, and not something a beginner should have to diagnose.
- **`api/README.md`** — what each manifest answers, the type vocabulary, and how to consume `nodes.json`.
- CI gates for all of it, and `api/nodes.json` in the release zip.

### Fixed (all in the new tooling, not in the framework)

- **Multi-value returns were structurally impossible as getter nodes.** A getter splices its call inline as an
  expression, and Lua truncates a multi-value call to one value unless it is last in a list — so
  `Ess.Color.hex` would have silently delivered `r` and dropped `g` and `b`. Such functions are now
  auto-promoted to action nodes that capture into one local each. **26 functions** were affected. (The
  editor's own convention was to *skip* these; this recovers them instead.)
- **Method-style calls were emitted wrong.** `function Ess.RNG:int(n)` desugars to `Ess.RNG.int(self, n)`, so a
  dotted `Ess.RNG.int(5)` passes 5 as `self` and leaves the real argument nil — no error, just a wrong answer.
  **21 functions** across `Ess.Track`, `Ess.RNG` and `Ess.SaveVar`. They now get a synthetic receiver input and
  emit `Ess.RNG.new():int(5)`. Both have regression tests.

### Notes

- Node type ids are prefixed **`essgen/`, never `ess/`**. The editor's hand-written nodes own `ess/`; sharing
  the prefix would silently overwrite hand-tuned nodes depending on script load order. Both coexist, so an
  editor can migrate one namespace at a time on purpose rather than all at once by accident.
- Descriptions ship in two lengths — `desc_short` for a tooltip, `desc` for a details pane — because the full
  ones carry engine traps worth several sentences (a helicopter running combat AI ignores a land order; a
  pursuit cap is one-way for the whole session) and those don't belong in a hover.
- A `multi-return spill` gate was added to `--check` after one batch spotted that a bare
  `Ess.Player.targetUnderReticle(0)` default would spill three extra arguments into the following parameter.
  It immediately caught two more instances in a later batch that had been missed.

## [0.4.1]

**Packaging fix for 0.4.0.** The v0.4.0 release asset shipped **without `api/ess.json` or `api/natives.json`**
— the two manifests 0.4.0 was largely about. No framework code is affected; if you only installed
`1_Ess.lua`, 0.4.0 was fine and this changes nothing for you.

### Fixed

- **`release.yml` never ran `build/manifest.py`.** `ci.yml` did, so CI went green while the *published* zip was
  missing the manifest: `dist/` is gitignored, so `ess.json` doesn't exist in a fresh checkout, and
  `package.py` skipped it exactly as written. Added the generate step to the release workflow. This is a
  reminder that a passing CI job and a correct release artifact are different claims — the zip is now
  inspected, not assumed.
- **`build/package.py` now WARNS LOUDLY when a manifest is missing** instead of quietly shipping a zip without
  it. That silence is the only reason the 0.4.0 gap reached a published release.
- **`natives.json` moved from gitignored `dist/` to committed `api/natives.json`.** It's captured from a
  **live game** by `tools/dump_natives.py`, so CI physically cannot regenerate it — a gitignored copy would
  have been absent from every release zip forever, no matter what the workflow did. It also changes
  essentially never (only if the game or bridge changes), which makes committing it the honest option. The
  two files now come from two different places on purpose: `dist/ess.json` is *derived from `src/`* and so is
  regenerated every build to guarantee it's never stale; `api/natives.json` is *captured from outside this
  repo* and so is committed. Both are documented that way at every reference.

## [0.4.0]

**The diagnosability pass.** Ess's oldest structural weakness was that it fails *silently* on purpose — a
wrapper returns `nil` instead of propagating a problem, so a mod calling something with a stale guid or a nil
argument produced no log line, no error, and no effect. That is the single most common "why isn't my mod doing
anything" wall, and until now there was no way to see through it. `Ess.DEBUG` opens it up.

Also: `Ess.Safe` — documented since 0.1.0 as "the single most duplicated shape in this whole project" — was
being used by the framework itself **exactly once**. That was an oversight, not a decision. It is now the
mechanism the whole diagnostic layer runs through.

### Added

- **`Ess.DEBUG`** (default `false`) — set it true, from a script or live over the bridge, and everything Ess
  quietly gave up on starts reporting itself. Read at call time, so flipping it mid-session takes effect
  immediately; survives a level reload. Two separate channels, because there are two genuinely different
  silences:
  - **Thrown failures** — an engine call raised a Lua error and a `pcall` swallowed it. Recorded by
    `Ess.Safe.*`.
  - **Guard rejections** — Ess looked at the arguments, decided the call couldn't work, and returned early
    *without ever calling the engine*. Recorded by `Ess.Safe.reject()`.

  CONFIRMED LIVE 2026-07-25: 14 deliberately-malformed native calls (nil / garbage / stale guids across
  `Object`, `Player`, `Vehicle`, `Human`, `Ai`, `Marker`, `Camera`, `Sys`, `Pg`) threw **zero** Lua errors —
  they fail safe, returning `nil` or, for a stale guid, stale values. So the *guard-rejection* channel is the
  one that answers a beginner's "nothing happened", and a diagnostic built only on caught errors would have
  been quiet in exactly the case it exists for. This is **not** a reason to drop the `pcall` guards, and none
  were dropped: the crash cases in CONTRIBUTING.md were recorded defensively (deliberate breadth over pinpoint
  reproduction), so a rare throw in another location or game state stays plausible. Only the relative
  frequency of the two channels is now known.
- **`Ess.Safe.reject(label, reason)`** — the guard-rejection recorder. Always returns `nil`, so a wrapper's
  early-out stays one line: `if not uGuid then return Ess.Safe.reject("Ess.Object.heal", "no guid") end`.
  Unlike a thrown error, a rejection knows *why*, because Ess is what decided — so the log line is specific
  ("no guid") rather than a generic engine error string.
- **`Ess.Safe.named(label, fn, ...)`** — `.quiet` with the label supplied up front, for closures. A closure is
  a fresh function object per call, so it can never appear in the reverse-name map; this is the only way to
  attribute one. CONFIRMED LIVE: `type(_G.debug)` is `nil` on this engine — the debug library is *absent*, not
  merely unused (zero occurrences in the decompiled corpus), so a `debug.getinfo` fallback was confirmed dead
  code and removed rather than left in looking like it might work.
- **`Ess.lastError()`** — the most recent swallowed failure as `{ msg, label, count, rejected }`, or `nil`.
- **`Ess.Safe.stats()`** → per-callsite tallies worst-first, plus the unconditional session total as a second
  return. Throws and rejections share one tally, so it reads as a single "what is going wrong" list.
- **`Ess.Safe.reset()`** — clears the tally, total and last error, and drops the cached name map so it
  rebuilds (it is a snapshot of whatever engine globals existed at first use).

### Changed

- **`Ess.Safe.call` / `.quiet` now pass through 6 return values, up from 4.** The widest native return in the
  whole corpus is 4 (`Player.GetTargetUnderReticle`'s x,y,z,guid), so this is headroom rather than a fix — but
  the old ceiling would have silently truncated a wider call. Still fixed-arity and still allocation-free:
  these sit inside per-frame heartbeats, where a throwaway table per engine call would be a real cost.
  Verified live at 6 values through the game's own VM.
- **`Ess.Safe.quiet` now means "quiet unless you asked to hear it"**, not "invisible". Its failures are always
  counted, and log when `Ess.DEBUG` is on. Previously they were unconditionally undiagnosable.
- **Failure-name resolution** builds a reverse map (function reference → `"Namespace.FnName"`) by walking the
  engine globals once, lazily, only on the first failure while `Ess.DEBUG` is on — so it costs nothing in the
  normal debug-off case. CONFIRMED LIVE: **1,889 functions mapped**, correct on 4/4 spot checks
  (`Object.GetPosition`, `Player.GetLocalCharacter`, `Ai.Goal`, `Pg.Spawn`), including the one-level-deep
  nested tables `Graphics.Camera` and `Graphics.Effect`. (`pairs(Object)` returns exactly 87 functions,
  matching the wiki's own live dump.)

- **`Ess.stop(x)` / `Ess.stopAll(t)` / `Ess.Track:any(x)`** (`src/98_stop.lua`) — one teardown verb for any
  handle shape. Ess grew **27 distinct teardown verbs** across **five structurally different** disposal
  idioms — a closure to call (`Ess.On.*`), a handle table to hand back (`Ess.Mark`, `Ess.Relations`), an id
  string you supplied (`Ess.Loop`, `Ess.Sandbox`), an object with a method (`Ess.Objective:cancel`), a tracker
  (`Ess.Track:closeAll`) — because each namespace picked the word that read best locally. Every one still
  works and none is deprecated; `Ess.stop` is what you reach for when you're just holding a handle and want it
  gone, and what a teaching example can use without a detour into per-namespace spelling. Dispatch is
  duck-typed on the same discriminators `Ess.Mark.clear`/`Ess.Relations.restore` already use, with real
  methods checked first; string ids are resolved by *asking* each registry which one owns the id rather than
  guessing. `nil` and unrecognised input are safe no-ops returning `false` — teardown never throws.
- **`Ess.RNG:pick` now works on a plain array.** Entries that aren't tables weigh 1, giving a uniform pick.
  Previously every entry was indexed as `e[weightKey]` unconditionally, so `rng:pick({guidA, guidB})` — the
  obvious reading of a function called "pick" — **threw** `attempt to index a userdata value`. Weighted
  behaviour for table entries is unchanged (verified: a `w = 0` entry is still never chosen in 200 draws).
  Found by a new recipe doing exactly that against a list of spawned guids.
- **Seven `compose_*` recipes** (`samples/recipes/`) — the **composition track**, and an explicit answer to
  "why write Lua when the visual editor can wire this up?" Every other recipe is a sequence of one-liners,
  which the node editor does better. These demonstrate what a node graph structurally *can't* hold: a closure
  keeping private state between ticks, iteration over a query result of unknown length, an author-defined
  vocabulary the rest of the mod is then written in, behaviour that keeps reacting after the script has
  finished (without leaking on re-run), an encounter described as validated/scalable data, unified teardown,
  and the `Ess.DEBUG` workflow itself. All seven pass live.
- **`dist/ess.json`** (`python build/manifest.py`) — a generated, machine-readable manifest of all **548**
  public functions: namespace, tier, params, returns, description, source file+line, and whether documented.
  Parsed from `src/` itself, which is authoritative — a doc mentioning a function never conjures one into
  existence. Ships in the release zip as `api/ess.json`.
- **`build/manifest.py --check`, the API drift gate**, now running in CI. `ess.json` can't drift from `src/`
  (it's generated from it), but the hand-written surfaces can: the in-game console's registry,
  `CAPABILITIES.md`, and every source header comment. The gate fails the build if any of them names a function
  that doesn't exist. It earned its place immediately — its first run flagged `Ess.Squad.on` and
  `Ess.Time.since` as documented-but-undefined, which turned out to be a hole in the parser (both are plain
  function-reference aliases, `Ess.Time.since = Ess.Time.elapsed`), and its second flagged a real one.
- **`api/natives.json`** (`python tools/dump_natives.py`, needs a live game) — the whole engine surface, from
  a `pairs(_G)` walk inside the running VM: **4,316 functions** across 81 **engine-native** namespaces (C++,
  no source anywhere) and 197 **resident-game-script** ones (ordinary Lua, each with its path in the
  decompiled corpus). Classification is evidence-based, not guessed — the live `_MODULES` registry *is* the
  discriminator. Deduped by **table identity** rather than by name, which matters in both directions: the
  module system puts an imported module's table onto every importer (`MrxPmc.MrxUtil` *is* `MrxUtil`, and
  `oPda` *is* `Pda` — 240 such aliases folded away), while some same-*named* tables are genuinely distinct
  (`SubtitleBuffer ~= Pda.SubtitleBuffer`). Each namespace records which of its functions Ess already reaches,
  so the remainder is the coverage gap. Ships as `api/natives.json`.

### Fixed

- **`Ess.Event.on`'s failure log said `nil`.** The one place the `pcall` → `Ess.Safe` conversion silently
  degraded something: it logged its second return value as the error message, which under `Ess.Safe` is a bare
  `false`/`nil` by design. Now reads the message from `Ess.lastError()`. Found by sweeping every converted site
  for a second-return read inside its own failure branch (10 others turned out to be `if not ok or not val`
  nil-tests, which behave identically).

### Documented (confirmed live, previously unrecorded)

- **`Object.Remove` is DEFERRED, exactly like `Object.Kill`.** `Ess.Object.alive(g)` still reads `true` on the
  same tick you remove something and flips false roughly half a second later. `11_object.lua` documented this
  for `Kill` only. Worse, **`Ess.Object.valid(g)` stays `true` even after `alive()` has flipped** — the guid
  handle outlives the object, so `valid` is not a usable "is it gone yet" test at all. Found by a new recipe
  asserting removal synchronously and failing for a reason unrelated to what it was testing.
- **The `debug` library does not exist on this engine.** `type(_G.debug)` is `nil` — absent outright, not
  merely unused by the shipped scripts (zero occurrences in the whole decompiled corpus). A guarded
  `debug.getinfo` fallback for naming closures was confirmed dead code and removed rather than left in looking
  like it might work; `Ess.Safe.named` is the only way to attribute a closure.
- **`io` does not exist either** (`type(_G.io) == "nil"`), which is why `tools/dump_natives.py` transports its
  dump through `Loader.Printf` and the log file rather than writing a file from inside the game.
- **`FEATURE_SHEET.md`** now says plainly that its opening design section and its "open questions" are
  historical and resolved, rather than reading as current pending work. `README.md` no longer points at it for
  "the full API" — that's `CAPABILITIES.md`, as the same README already said two paragraphs earlier.

### Notes

- Fully backwards compatible. `Ess.Safe.call`/`.quiet` keep their existing contract of returning a **bare
  `false`** on failure — deliberately *not* `pcall`'s `false, errMessage`, since handing the error string back
  in the slot callers read as "the value" would turn a clean nil-on-failure into a garbage-on-failure footgun.
  Read the message via `Ess.lastError()`.
- A variadic `Ess.Safe.callv` was written and then deliberately **removed** rather than shipped: nothing in
  Ess needs it, so it would have been an untested code path for a hypothetical caller. `unpack` (76 corpus
  occurrences) and `select` (live-exercised by `a_quick_mission.lua` every smoke run) both exist on this
  engine, so it is buildable the day a >6-value native call is actually found.

## [0.3.4]

**The `Ess.Squad` team/orchestration pass.** A full team/role/queue/tactics/formation layer over
`Ess.Followers`, plus three more real engine bugs found and fixed via live verification along the way —
on top of the `orderEnter`/vehicle-aware-follow work already sitting unreleased from the previous pass.

### Added

- **`Ess.Squad`** — an opt-in team/role layer over `Ess.Followers` for scripts managing enough followers
  that "the whole roster" stops being the right unit of command. `Ess.Squad.createTeam(name, guids)` /
  `.team(name)` / `.teamOf(guid)` / `.assignRole(guid, roleType)` / `.roleOf(guid)`, and
  `.orderTeam(name, behavior, opts)` — `Ess.Followers.order()` scoped to just that team. Built entirely on
  `Ess.Followers` (specifically the new `Ess.Followers._orderScoped` core `order()` itself now calls) — no
  new native calls, no separate roster. `Ess.Easy.Squad` mirrors `Ess.Easy.Followers`' own shape
  (`createTeam`/`assignRole`/`orderTeamAttack`/`orderTeamPatrol`/`orderTeamGuard`/`orderTeamFollow`).
  CONFIRMED LIVE: ordering one team leaves every other follower (in another team or in none) completely
  undisturbed — destination markers and the natural-completion auto-resume-follow callback are tracked PER
  SCOPE (`orderMarksByScope`, keyed by team name or `"__all__"` for the whole-roster case), not against one
  shared "last order" slot, specifically so two teams ordered independently can't clear or resume-follow
  each other's still-in-flight order.
- **`Ess.Followers.on(eventName, fn)` / `Ess.Squad.on(...)`** — a generic string-keyed pub/sub (the one
  piece neither `Ess.On`, engine-signal-specific, nor `Ess.Event`, raw engine handles, provided).
  `"onRecruit"`, `"onDismiss"(guid, wasKilled)`, `"onFollowerDown"` (a `wasKilled` dismiss, fired
  immediately alongside `onDismiss`) fire today; `Ess.Squad.on` forwards to the SAME bus so its own later,
  higher-level events reuse it rather than standing up a second one.
- **`Ess.Squad.queue(targetGroup, steps, queueOpts)` / `.cancelQueue(targetGroup)`** — an asynchronous
  multi-step sequence (e.g. enter a vehicle → wait until seated → move to the LZ → wait for arrival →
  deploy), for a team name or a raw guid list. Built on the new `Ess.Followers._issue` (the raw
  order-issuing core `_orderScoped` itself now layers marker-tracking + auto-resume-follow on top of) —
  deliberately does NOT go through `_orderScoped`, since auto-resuming Follow the instant one step
  naturally completes is exactly wrong mid-sequence. Step completion reuses whatever signal the behavior
  already provides (`onComplete` for move/non-looping patrol, `Ess.On.death` for attack, polling
  `Ess.Object.vehicleOf` for enter), and EVERY step also gets a timeout watchdog regardless — CONFIRMED
  LIVE this matters: a single unit's silently-failed `Ai.Goal` (see the `move`/`patrol` fix below) would
  otherwise hang the entire sequence forever, not just that one step. `cancelQueue` reverts the group to
  Follow, its documented safe fallback. Fires `"onStepComplete"`/`"onQueueComplete"` on the same event bus.
- **`Ess.Squad.Tactics.mountUp(vehGuid, targetGroup, opts)` / `.dismountAndSecure(targetGroup, atPos,
  radius)`** — role-aware vehicle boarding (whoever's `assignRole(guid, "driver")`'d boards first, as
  driver; everyone else as passenger/`opts.passengerRole`) and disembark-then-defend. CONFIRMED LIVE:
  `Ai.Deploy` only ejects PASSENGERS — a vehicle's driver stayed seated straight through it in testing, so
  `dismountAndSecure` also explicitly `Vehicle.Exit`s whoever's still driving (the corpus's own
  `resident/mrxsupportcopterdelivery.lua` confirms this exact "make the driver get out" call shape).
  `mountUp` fires `"onVehicleMounted"` once every guid in the group is seated in some vehicle, or gives up
  silently past its own timeout (default 20s) — a blocked/full vehicle is a real, expected outcome, not an
  error.
- **`Ess.Squad.setFormation(targetGroup, formationType, opts)` / `.clearFormation(targetGroup)`** — on-foot
  positional formations (`"wedge"`/`"column"`/`"line"`/`"diamond"`) for a squad operating independently of
  the player, recomputed every tick as `opts.leader` (default the local player) moves. Deliberately opt-in
  and explicitly "visual sugar," not a precision tactical system: native `Ai.Role("Follow")` has no notion
  of a per-slot offset, so a formation member is taken off the Role entirely and driven by the same
  reissued-`MoveTo`-to-an-anchor loop `Ess.Followers.startFollowLoop` already proved out for vehicle
  escort/on-foot resume (see that file), just with per-slot offset math (`Ess.Math.rotateOffset`, the same
  right/forward convention the `MissionForge` sample's own squad grid already uses) instead of a hysteresis
  band. CONFIRMED LIVE: a 4-unit wedge and diamond both converged on their expected slot positions relative
  to the player's facing.
- **`Ess.Easy.Followers.orderEnter(vehicleGuid, role)`** — orders the whole current roster to board a
  vehicle (`role` defaults to `"driver"`, not `Ess.AIOrders`' own `"passenger"` default). CONFIRMED LIVE: no
  secondary "which guid is currently driving which vehicle" tracker is needed — a follower who's currently
  driving IS already the correct `AIGuid` for a later `order()` to steer the vehicle through, since
  `Ess.Raw.AIOrders.actor()` already implements the established "target the driver, not the hull" rule.
- **Vehicle-aware "return to following"** — the native `Ai.Role("Follow")` wants its subject to board a
  vehicle WITH the target, so reissuing it on a follower currently DRIVING their own vehicle (after
  `orderEnter`, say) made them climb back OUT to go do that instead — confirmed live, the exact "gunner
  runs out the instant an order finishes" bug this closes. `resumeFollow`/`order("follow", ...)` now route
  through a vehicle-aware check: a driver gets a reissued-`MoveTo` escort loop instead of the Role (holding
  10–20 units off by default, hysteresis so it doesn't twitch at the boundary — first tried retargeting the
  stand-off point via `"MoveToPos"` directly since a vehicle driver was the corpus's one confirmed use of
  that goal, but CONFIRMED LIVE a bare `Ai.Goal` call still returned `nil` for it; switched to the same
  reused-`TinyGeometry`-anchor + `"MoveTo"` trick `move`/`defend`/`patrol`/`flee` already use); a
  passenger/gunner is left completely alone (touching their Role/Goal at all risks ejecting them for
  nothing); on foot is the unchanged native Role. `Ess.Followers.recruit` itself needed the same
  vehicle-awareness — a guid already sitting in a vehicle at recruit time (real game state persists across
  a Lua-side reload) got the native Follow role applied while seated otherwise. The escort loop's own
  "has the driver left?" check is debounced to 3 consecutive misses, not a single reading — a transient bad
  read (e.g. right as another follower was recruited/spawned nearby) was otherwise enough to permanently
  kill a perfectly good escort loop.

### Fixed

- **A follower taken off native `Ai.Role("Follow")` for ANY order (even a plain `move`) snapped back
  hostile toward its target within 1-3 seconds on its own, and reissuing `Ai.Role("Follow")` afterward
  returned a valid handle but never actually moved them again** — both confirmed live side-by-side against
  an untouched follower who stayed on native Follow the whole time and never drifted at all, so the native
  Role itself is what suppresses this, not the one-time `Ai.LivingWorld`/`Ai.SetState("Vip")`/feeling setup
  `recruit()` already does. Native Follow turns out to be reliable ONLY on its first engagement, straight
  from `recruit()` (left unchanged); every RESUME (`order("follow", ...)`/auto-resume/`Ess.Squad.orderTeam`)
  now goes through `startFollowLoop` instead of trying to re-engage the Role at all — the same
  reissued-`MoveTo`-plus-hysteresis mechanism this file already used for a vehicle driver's escort,
  generalized to on-foot too, with a per-tick feeling re-pin added to stop the drift. Accepted tradeoff: a
  RESUMED follower loses native Follow's own free vehicle-boarding-with-you convenience (the ContextAction
  prompt is tied to the Role) until explicitly `orderEnter()`'d again — a fresh `recruit()` still gets it.
- **`Ess.AIOrders.command(..., "move"/"patrol", { onComplete = ... })` could hang forever for an ENTIRE
  group over a single unit** — `Ai.Goal` can silently refuse to register at all (no handle, no error), and
  when that happens for even one guid, no native `Callback` ever arrives for it, so the group's own
  fan-out completion counter never reaches zero and `onComplete` never fires — not even for guids who
  finished fine. Confirmed live: a 2-unit team's `move` order never triggered auto-resume-follow, while the
  identical order to a lone unit worked every time. Both behaviors now count an immediate registration
  failure as "done" right away instead of waiting on a `Callback` that's never coming.
- **`Ess.Followers.list()`/`.count()` could report stale, already-dead followers no further `dismiss()`
  call could clear** — confirmed live: a death-triggered auto-dismiss racing a manual `dismissAll()` call
  left the ordered roster list holding 2 guids whose actual roster entry was already gone. `list()` is now
  self-healing (prunes the ordered list in place of any guid missing from the roster on every read), the
  same lazy-prune-on-read idiom `Ess.Squad.team()` already uses over this same roster.
- **`Ess.AIOrders.command(..., "enter", ...)`'s `target` had the exact same gap `attack`'s `target` did** —
  only ever resolved a registered group name or a string name via `Pg.GetGuidByName`, so a raw vehicle uGuid
  (e.g. from the new `orderEnter`) silently resolved to `nil` and the whole behavior no-op'd, no error.
  `target` now accepts a raw uGuid directly too.

## [0.3.3]

**The `Ess.Followers` / `Ess.AIOrders` live-verification pass.** Every fix and addition below was tested
against the running game (cross-checked against the decompiled game script corpus where the live behavior
alone didn't explain it), not just read-reviewed — see the entries themselves for what was actually
confirmed.

### Added

- **`Ess.Followers`** — a lifecycle-aware "who's currently assigned to me" roster, built entirely on
  `Ess.AIOrders`/`Ess.On.death`/`Ess.Mark` (no new native calls). `Ess.AIOrders.command` is stateless — every
  call re-passes an explicit guid list, and nothing remembers who you've already recruited, or reverts the
  `Ai.Feeling`/`Ai.LivingWorld`/`Ai.SetState("Vip")` state `"follow"` sets when following ends.
  `Ess.Followers.recruit(guid, opts)` runs that sequence AND remembers the guid; `.dismiss(guid)` reverts it
  AND forgets it; a dead follower prunes itself automatically via `Ess.On.death`, no polling. The actual
  payoff is `Ess.Followers.order(behavior, opts)` — command the WHOLE current roster (any of `Ess.AIOrders`'
  11 behaviors) with no guid list to re-thread through your own script every call. `Ess.Easy.Followers` adds
  `recruit(guid)`/`orderAttack(target)`/`orderPatrol(points)`/`orderGuard(at)` one-liners.
  - **Markers, ON by default**: a floating world-space icon over every follower's head (each in its own
    color, stepped by the golden angle so any number of followers stay evenly spread with no fixed palette
    to exhaust), plus a temporary marker at whatever `order()`'s current destination/target is — cleared the
    moment a new order supersedes it or the current one naturally completes. `setMarkersEnabled(bool)` /
    `markersEnabled()` toggle it.
  - **Auto-resume-follow, on natural completion only** (confirmed live): `attack` resumes Follow the instant
    its target dies; a non-looping `move`/`patrol` resumes once every follower finishes its route. Guard/
    hold/a looping patrol have no natural "done" and stay on that order until `order("follow", ...)` is
    called again.
  - Two more confirmed-live fixes specific to ordering an ALREADY-following unit onto something else: a
    follower can still be mid-goal from a PRIOR order when a new one comes in, and `Force=true` alone doesn't
    reliably preempt it — `order()` now clears it first with `Ai.RemoveGoal({Handle=0})` (the confirmed
    "whatever's current" wildcard). And the actual root cause of an intermittent "order does nothing" during
    testing turned out to be priority, not timing: `Ess.AIOrders`' own per-behavior defaults (e.g. attack's
    `"med"`) are not reliably high enough to override a just-released Follow Role's leftover state, even with
    `Force=true` — only `"hi"`/`HiPri` worked consistently, so `order()` now defaults every order's priority
    to `"hi"` (not changed in `Ess.AIOrders.command` itself, whose other callers never had a Role to preempt
    in the first place).
- **`Ess.Loop.stats(id)` / `Ess.Loop.list()`** — introspection into the shared heartbeat registry: each
  loop's `interval`, `ticks` (count since last `start()`), `lastDuration`/`avgDuration` (real wall-clock
  tick cost, via `Ess.Time.stamp()`/`.elapsed()`, EMA-smoothed), and `lastError`. Lets a monitor catch a
  loop whose tick is expensive relative to its own interval — the actual, measurable version of "this
  poller feels heavy" instead of guessing from framerate. Purely additive: `start()`/`stop()`/`isRunning()`
  are unchanged, and every existing call site (20+ files) only ever used that public surface, never
  `Ess.Loop._reg`'s internal shape directly, so extending it is backwards-compatible by construction —
  confirmed by grep before making the change, not assumed.

### Fixed

- **`Ess.AIOrders`: `move`/`defend`/`patrol`/`flee`/`attack`'s position-fallback all silently no-op'd on an
  on-foot human.** Every one of them handed `Ai.Goal` a `"MoveToPos"`/`Location={x,y,z}` table — confirmed
  LIVE to be rejected by the engine (`Ai.Goal` returns `nil`, no error, since it's `pcall`-wrapped) for ANY
  raw-coordinate move on a walking human, regardless of distance, while the identical unit accepts `"Idle"`
  fine. Cross-checked against the full decompiled game script corpus: `"MoveToPos"` appears in exactly one
  file, and only ever targets a VEHICLE DRIVER, never a human. Fixed by spawning a disposable `TinyGeometry`
  at the destination and issuing `"MoveTo"` targeting THAT (the confirmed-working substitute — `defend`
  already did this exact trick for its own `Ai.Anchor` radius) instead of a raw coordinate.
- **`Ess.Easy.AIOrders.attack`'s `target` silently attacked the PLAYER instead of the given guid.**
  `BEHAVIORS.attack` only ever resolved `o.target` through the `Ess.AIOrders.setGroup` registry
  (`Ess.AIOrders.group(o.target)[1]`) — passing a raw guid (a reticle target, say) missed that lookup
  (`group()` returns `{}` for an unregistered name, per its own contract) and fell all the way through to
  `nearestHero()`. `o.target` now accepts EITHER a registered group name OR a raw uGuid directly.
- **`Ess.AIOrders.command(..., "face", ...)` silently no-op'd on a unit already holding an
  `Ai.Anchor(AnchorRadius=0)` lock** (i.e. after a `"hold"` order) — confirmed live: the goal was accepted
  (no error) but never visibly turned the unit. Fixed by adding `Force = true`, matching every other
  movement-ish behavior in this file; no separate "release the anchor" step is needed.
- **`Ess.AIOrders.command(..., "enter", ...)` silently no-op'd on a freshly `Ess.Object.spawn`'d vehicle** —
  confirmed live: `Ai.Goal` accepted the goal (truthy handle) once `Vehicle.Usable(veh, true)` was called on
  it first, matching a confirmed real-game sequence (`oilcon002.lua`). `enter` now calls this once before
  issuing the goal — a harmless no-op on a vehicle that's already usable (every placed-in-level vehicle
  already is).
- **`"attack"` and `"hold"` had the same missing-`Force=true` gap `"face"` did** — a unit coming off a prior
  `"defend"`/guard order (which leaves an `Ai.Anchor` lock active) silently ignored a follow-up `"attack"`
  goal with no error; confirmed live and fixed the same way, proactively applied to `"hold"` too once the
  pattern was clear.

### Changed

- **`Ess.AIOrders.command(..., "follow", ...)` now uses Mercenaries 2's own real "recruit" mechanic**
  (`Ai.Role({Role="Follow", ...})`, confirmed live against the decompiled game script corpus's own
  `resident/mrxfollow.lua`) instead of re-issuing a plain `"MoveTo"` goal on a dumb timer. The native Follow
  role auto-maintains `MinDistance`/`MaxDistance` on its own and follows the target into/out of vehicles for
  free — neither of which the old timer-based approach did at all. Three prerequisites, confirmed live, are
  now applied in order before the role is assigned: neutralize a hostile `Ai.Feeling` toward the target,
  disable the unit's ambient `Ai.LivingWorld` behaviour (it fights the Follow role for control otherwise),
  and set `Ai.SetState(..., "Vip", true)` — confirmed to be the one MISSING piece: without it, `Ai.Role`
  still returns a truthy handle but the unit never actually follows.

## [0.3.2]

### Changed

- **`samples/OnKey/` renamed to `samples/demos/`** and reframed as reference-only, matching
  `samples/recipes/`. The bind-to-a-key demos are no longer auto-deployed into `scripts/OnKey/` or
  pre-bound to keys by the release zip (`build/package.py`) — earlier releases shipped all 12 official
  demos pre-registered across F1-F12, which silently claimed every F-key before a new modder had bound
  their own first mod (the exact key `GETTING_STARTED.md`'s own tutorial suggests). Copy a demo into your
  own `scripts/OnKey/` and bind it yourself; each file's header comment says what it does and suggests a
  key.
- `samples/README.md`'s Interactive scripts table now also documents `CollectibleFinder`, `LocationLogger`,
  `RoadLogger`, and `TrailerHitch` — four working demos that existed in the folder but weren't catalogued
  or shipped. `LocationLogger`/`RoadLogger` no longer hardcode a default key that collided with the
  documented `CreatorToolkit` (F8) / `WaveSurvival` (F11) bindings; all four now suggest "free" like
  `CollectibleFinder`/`TrailerHitch` already did.

### Added

- **`TROUBLESHOOTING.md`** — symptom-first fixes for the common install and mod-authoring failure points,
  composed from facts already confirmed elsewhere in this repo. Linked from `README.md` and
  `GETTING_STARTED.md`, and bundled into the release zip.
- `GETTING_STARTED.md` and `CAPABILITIES.md` now link to the community loader/resources hub
  ([mercs2.tools](https://mercs2.tools/)) and the magic-strings reference
  ([wiki.mercs2.tools/reference.html](https://wiki.mercs2.tools/reference.html)).

### Fixed

- `GETTING_STARTED.md`'s example ready-line was still `[Ess] v0.1.1 ready` against a current `0.3.1` —
  now worded version-agnostically so it won't go stale at the next release.

## [0.3.1]

**The 2026-07-22 bindings-pass harvest.** A live-probe mapping of the engine's never-called `luaL_Reg`
bindings (wiki `namespaces/` pages, updated the same day) confirmed signatures for a batch of natives with
zero call sites anywhere in the decompiled corpus. Everything below wraps only live-confirmed or
corpus-confirmed calls, and everything is **additive** — no existing function changed signature or behavior.

### Added

- **`Ess.Pursuit`** (new namespace, `src/17_pursuit.lua`) — the wanted/heat system: `.state()/.level()`,
  `.start(faction, level)`, **`.clear()`** (the one true reset), `.seconds/.levelTimes/.lock/.custom`,
  `.capLevel(n)` (⚠ live-confirmed ONE-WAY session ratchet — logs a loud warning), `.restrictAll/
  .restrictFaction/.clearRestrictions` (gate ORGANIC heat only — they do NOT clear an active chase; the
  wrapper docs encode both confirmed traps). Plus **`Ess.Easy.World.noPursuit(bOn)`** — stop the current
  chase and keep new organic heat off, one call. (`Easy.World.clearWanted` is untouched.)
- **`Ess.Object` motion & geometry** — `.velocity(g)` / `.speed(g)` / `.speedSq(g)` (first motion API in
  Ess), `.size(g)` (model bbox extents — takes a guid, not a name), `.localToWorld(g, lx,ly,lz)` (the
  engine's full 3D transform incl. pitch/roll — prefer over yaw-only `Ess.Math.rotateOffset` on tilted
  objects), `.heightAboveGround(g)` (with the exact-0-placeholder caveat from the terrain project),
  `.snapToGround(g, offset)`, and `.invincible(g)` (the missing getter).
- **`Ess.Vehicle`** — `.repair(v)` (RestoreHealth+RestoreAmmo — the vehicle repair long thought missing),
  `.evictAll(v)` (Ai.EveryoneOut, confirmed), `.isFlipped(v)`, `.land(heliOrPilot)` (Ai.HeliLand, confirmed
  real descent; resolves the pilot via `.driver` — pairs with `.flyTo`).
- **`Ess.Probe`** — eight new `nearby()` kinds (`tanks`, `helicopters`, `boats`, `cars`, `jets`, `props`,
  `usables`, `groundNoTanks`) on the same dispatcher (unknown kinds still fall to `any`, unchanged), and
  `.allByName(name)` (every matching guid — `Ess.Guid` stays the single-match form).
- **`Ess.On.labeled(label, r, fn)`** — fires once per world-labeled object as it streams in near the
  player: the confirmed ObjectFilter + `Event.ObjectProximity` discovery idiom, promoted from the
  CollectibleFinder sample exactly as its header planned.
- **`Ess.Relations.getPerceivability/.setPerceivability`** — the per-individual AI detectability stat
  (confirmed reversible), and **`Ess.Easy.Player.ghost(bOn)`** — floor your detectability, restore your
  exact original on toggle-off. Registered in the Console + playground.
- **`Ess.Vec.cross`** — the cross product (dot's missing sibling), pure Lua.
- **`Ess.Easy.Debug.overlay`** now appends an engine `mem` figure (Sys.MemUsage) to the vehicle/health
  line — the useful signal is it climbing while your script runs.

### Verification status — live-tested in-game before release

Offline first (checkpure 10/10; test_bundles all green — which caught and fixed a real `Sys`-indexing guard
bug in the overlay's mem line; merged chunk loadchecks to completion), then a **full in-game pass on the
release build** (2026-07-22): the whole smoke suite — **42/42 recipes PASS**, including the new
`control_pursuit` (pursuit start → state-read → clear round-trip, and ghost lowering perceivability then
restoring the exact original). Targeted live probes, most with exact before/after numbers:

- `localToWorld` offset of 5 measured **5.00**; `heightAboveGround` read **12.05** on a +12 spawn and
  `snapToGround` took it to **0.00**; `invincible` round-tripped false→true→false; `isFlipped` false upright.
- `size` and `speed`/`velocity` return real values on settled objects (a human measured 0.98 × 1.93 × 0.33)
  — and surfaced a **new documented caveat**: both read nil/zeros in the same tick as the spawn (the known
  fresh-spawn settle class; noted in the file header).
- `Vehicle.repair`: health **25 → 130/130 max**. `Vehicle.evictAll`: driver went **userdata → nil**.
- `Vehicle.land`: a second **live-discovered caveat** — a heli on autonomous combat AI overrides the order;
  under scripted control (`.flyTo` then `.land`) it descended **AGL 35.0 → 19.4** and dropping. The
  flyTo-then-land pattern is now documented as the confirmed usage.
- `Probe.allByName` found a spawned template by name (template-name matching confirmed); all 8 new `nearby`
  kinds dispatch (cars=5 / props=17 / boats=0 / tanks=0 at the test spot); `Pursuit.restrict*` and
  `Easy.World.noPursuit` execute clean; the overlay's `mem` figure renders; `Vec.cross` returned (0,0,1).
- `On.labeled` armed and stopped cleanly (no labeled object inside radius at the test spot to fire on — the
  underlying filter+proximity idiom is already live-proven by the CollectibleFinder sample).

## [0.3.0]

**Headline: a mirrored forward vector is fixed.** Everything that placed or aimed something relative to a
yaw — `spawnAhead`, `Easy.Vehicle.summon`, the menu kit's `ctx:spawn`, `Object.faceToward`/`faceObject`,
MissionForge's squad grids — was mirrored about the forward axis. Live-verified twice (see **Fixed**). If you
wrote code that compensated for the old behaviour, remove the compensation.

The rest of this release closes "creativity gaps" for new modders — the framework was strong on *how* to do
things, thinner on *what you can do* and on reacting to the player. All additive.

**Verification status:** the yaw fix and the new view-relative placement are **live-verified in-game** (exact
numbers below). The additive batch was then **live-verified in-game as well**, feature by feature:

- **`Ess.On`** — 7 of its 8 hooks fired live: `death`, `enterArea`, `insideArea`, `healthBelow`, `tick`,
  `vehicle` (enter + exit), `playerHurt`. *(`exitArea` not exercised.)*
- **`Ess.Support`** — all 7 call-ins fired clean (`shell`, `artillery`, `airstrike`, `bombingrun`,
  `gunship`, `reinforce`, `Easy.Airstrike.at`), with `reinforce` separately confirmed actually delivering
  units.
- **`Ess.Keys`** (`vk`/`on`/`isBound`/`off`), **`Ess.Objective`** + `Easy.Objective.reach/.destroy/.clear/
  .survive`, **`Ess.Quest`** sequencing, **`Easy.Spawn.enemies`**, **`Safe.template`**,
  **`Hud.objective(text, slot)`** — all pass.
- The two pieces that most needed eyes: **`Easy.Debug.overlay()`** renders, and **`Easy.Console.play()`**'s
  drill-in / run-live / param-cycling works.

**Still unverified:** the six OnKey demos that ship in the zip — `VehicleInspector`, `WaveSurvival`,
`BossFight`, `EncounterDirector`, `CreatorToolkit`, `Playground`. They need deploying to `scripts/OnKey/`
plus `lua_loader.ini` bindings and a keypress each. Nothing in the batch changes existing behaviour.

### Fixed
- **The forward vector was mirrored on X.** The engine's forward is `(+sin(yaw), +cos(yaw))`; Ess used
  `(-sin, +cos)`, with `Ess.Math.angleTo` = `atan2(-dx, dz)`. Both were wrong together (they are exact
  inverses and must always change as a pair), so "in front of the player" came out mirrored about the
  forward axis, and `faceToward` aimed objects the wrong way.
  ```lua
  pointAhead:  x - sin(yr)*dist   ->   x + sin(yr)*dist
  angleTo:     atan2(-dx, dz)     ->   atan2(dx, dz)
  ```
  **Why it hid for so long:** it is a *mirror*, not a rotation. Facing **north/south** `sin ≈ 0` and both
  conventions land on the same point — **invisible**. Facing **east/west** it is a full **180° wrong**. In
  between it is a variable, heading-dependent skew that reads as random. Two earlier calibrations were
  defeated by exactly this. **Always calibrate facing east/west.**
  **Proof:** two ground rings placed from the same body yaw, one per convention — facing east the `(+sin)`
  ring was dead ahead and `(-sin)` directly behind; facing north they coincided. Then numerically: with the
  reticle aimed along the body, `angleTo(player → reticle)` now equals `Object.GetYaw` to **±0.3°** (it
  returned the *negative* before).
- **Three inline re-derivations** of that trig, which would have silently kept the old sign, now call
  `Ess.Math`: the menu kit's `ctx:spawn`, `CarStunt`'s side camera, and MissionForge's squad-grid rotation
  matrix (squads were flipping about the forward axis).

### Added
- **`Ess.Player.viewYaw(i) -> yaw, bFromReticle`** — the yaw you're **looking** along, as distinct from
  `Ess.Player.pose`'s 4th return, which is the **chest/body** yaw. These genuinely differ: stand still and
  swing the mouse and the view rotates while the body does not (measured live at up to **111°** apart;
  running forward re-aligns them). Derived from the reticle hit point. **Never nil** while you have a
  character — with no usable hit (aiming at open sky) it falls back to the body yaw and returns `false` as
  the second value, which is what makes the flags below safe without caller-side guarding.
- **Opt-in view-relative placement** — all default **off**, so every existing call is unchanged:
  ```lua
  Ess.Object.spawnAhead(tmpl, dist, height, i, { useView = true })   -- trailing arg
  Ess.Easy.Vehicle.summon(tmpl,                { useView = true })   -- existing opts table
  ctx:spawn(tmpl, dist,                        { useView = true })   -- menu kit
  ```
  Live-verified: with body yaw `-1.5` and view yaw `-47.2`, `spawnAhead{useView=true}` placed the vehicle at
  the computed view point exactly. (A param rather than parallel `LookAhead` functions: `pointAhead` already
  takes an explicit yaw, and full parity would have doubled the spatial surface with twins that are mostly
  meaningless — `faceToward` is never view-relative.)
- **`Ess.Math.rotateOffset(x, z, yaw, localX, localZ)`** — place a local `(right, forward)` offset into world
  space; the general case that `pointAhead` is the `localX = 0` special case of. Added because a hand-rolled
  rotation matrix is exactly how the mirrored sign propagated — use this instead of writing one.
- **`Ess.Support`** + **`Ess.Easy.Airstrike`** — the iconic combat call-ins (airstrike / artillery /
  gunship / bombing run / reinforcements) as standalone one-liners, lifted out of the Contract system so you
  can fire one anywhere. `Ess.Easy.Airstrike.at(x,y,z)` / `.onTarget()` for one-tap. Recipe: `call_in_support`.
- **`Ess.On`** — intent-named reactive hooks so mods respond to the world without wiring raw events:
  `death(guid)`, `enterArea` / `exitArea` / `insideArea`, `healthBelow`, `playerHurt`, `vehicle`, `tick`
  (each returns `stop()`). The area/health/hurt logic is execute-verified offline (stubbed loop). Honest
  about engine limits (no clean "player got a kill" event). Recipe: `react_to_things`.
- **`Ess.Keys`** — bind several hotkeys inside one script (the OnKey loader gives you one key; this lets that
  script own a whole panel): `Ess.Keys.on("F6", fn)` plus off/clear/isBound and a name→VK map. Edge-triggered
  dispatch on one shared loop; resolution + dispatch execute-verified offline. Recipe: `hotkey_toolkit`.
- **`Ess.Easy.Spawn.enemies(n, opts)`** — drop a squad of hostiles ahead and send them at you, one line (an
  instant firefight). Plus `Ess.Player.inVehicle(i)` / `.onFoot(i)` state getters. Recipe: `instant_firefight`.
- **`Ess.Easy.Console.play()`** — the Console is no longer just a reference: an interactive **playground**
  drills into `Ess.Easy.*` functions by topic, RUNS one live on demand, and cycles its parameters (confirmed
  presets) so a new modder sees exactly what each does in-game. Reachable from a pinned row in `.open()`, or
  bound to F3 via the new `Playground` OnKey demo (shipped in the zip). Construction / param-cycling /
  run-dispatch verified offline; UI rendering needs an in-game pass.
- **`Ess.Objective` + `Ess.Quest`** — a lightweight **counted-goal tracker** for the gap between a bare
  `Ess.Hud.objective` text line and a whole `Ess.Contract`. `Ess.Objective` shows "label 3/5" on the HUD and
  fires a callback at target; `Ess.Quest` sequences steps one at a time. The **intent bundles** are the
  headline: `Ess.Easy.Objective.reach/.destroy/.clear/.survive` wire a goal to a world event AND drop its
  marker in one line (`clear` polls an area to sidestep the engine's missing "kill" event), and
  `Ess.Easy.Quest` makes a whole linear mission — `{reach=…}`, `{destroy=…}`, `{clear=…}`, `"manual"` steps —
  one table. State machine (counting, sequencing, auto-wiring, marker + watcher teardown, reload-safe id
  replace) execute-verified offline; the engine reads/marks need an in-game pass. Recipes: `track_a_goal`,
  `a_quick_mission`.
- **`Ess.Easy.Debug.overlay()`** — a live on-screen **dev overlay** for mod authors: your exact position +
  yaw, what you're aiming at (name/faction/distance), on-foot/vehicle, health, nearby counts. Toggle it to
  read a spawn/teleport position off the screen instead of logging it. Callable as `Ess.Easy.Debug.overlay()`
  and surfaced in the `CreatorToolkit` hub (below). Line-building + toggle verified offline; panel render needs
  an in-game pass. Recipe: `dev_overlay`. (Deliberately shows no "FPS" — the refresh is a timer, so any
  framerate would be the tick rate, not the real one.)
- **`Ess.Hud.objective(text, nSlot)`** now takes an optional tray slot (default 1), so `Ess.Objective`/`Quest`
  can show a goal on a line other than a running Contract's. Backward-compatible.
- **`Ess.Safe.template(name)`** — the canonical "is this a spawnable template" check (non-blank string),
  centralising the blank-`Pg.Spawn`-hard-crash guard that was re-inlined in ~6 spawn paths, so a new spawn
  path is one call from safe. Covered by `tools/checkpure.py`.

- **`VehicleInspector` OnKey demo** (F6) — a WAILA-style "what vehicle am I in" inspector (poll-detect the
  vehicle you enter, dump its guid + details to the log, live HUD panel). Ships in the zip; a compact showcase
  of `Ess.Player`/`Object`/`Vehicle`/`UI`/`Loop`.
- **Three "complete mini-mode" OnKey demos** (ship in the zip) — larger playable examples that each compose
  the framework into something that *does* something:
  - **`WaveSurvival`** (F11) — a horde mode: escalating waves rush you, clear one to heal (+ a crate every
    3rd), G for a danger-close airstrike, HUD tracks wave/kills. (`Easy.Spawn.enemies` + `On.death` +
    `Support` + `UI.Panel` + `Keys` + `Time.cooldown`)
  - **`BossFight`** (F12) — a mini-boss with a live `UI.Bar` health bar that regenerates until 50%, then
    enrages (adds + screen shake); cash reward on kill. (`On.healthBelow` + `On.death` + `Camera.shake` +
    `Loop`)
  - **`EncounterDirector`** (F1) — a weighted-random encounter roller (ambush / bounty / supply drop /
    dodge-the-artillery / a 3-checkpoint time trial). (`RNG:pick` + `Easy.Objective.destroy` + `Quest` +
    `Support`)
- **`CreatorToolkit` OnKey demo** (F8) — a **hub of in-game dev/creator tools** behind one menu (the editor
  Mercs2 never shipped): object inspector (WAILA for anything under your reticle), an **AI-cap meter** vs the
  ~200 soft cap, a nearby-object scanner, the debug overlay (folded in — this supersedes the standalone
  `DebugOverlay` demo), **persistent teleport bookmarks** (`SaveVar`), a prop placer (spawn-at-reticle +
  rotate/delete), a dev panel (invincible / infinite ammo / time-scale / freeze nearby AI / clear heat / cash),
  a photo mode, and a **camera-path → cinematic recorder** (drop keyframes, play them back as a fly-through).
  First-pass draft, compile-clean; the two camera tools use the confirmed cinematic API but don't implement a
  WASD freecam yet (you author by positioning your character), and there's no native full-HUD-hide, so photo
  mode hides player markers only. Needs the in-game pass.
- **`tools/webrepl.py` + `tools/webrepl.html`** — a browser **"mod console"**: a tiny local HTTP relay (reusing
  `lua_repl.py`'s protocol) serves a page that makes `Ess.*` calls in the **live game** — a grid of one-click
  actions plus a free-form Lua box, with a live bridge-status indicator. Browsers can't open raw TCP, so the
  relay bridges HTTP → the lua-bridge (127.0.0.1:27050). Binds to localhost only. The whole HTTP↔bridge path is
  verified end-to-end (page serves, `/probe`/`/exec` respond correctly); live results need the game running.

### Hardening (pre-release audit of the unreleased batch, offline)

- **`Ess.Support.reinforce`**'s `deliver="copter"` path now validates the template before `MrxCopterDrop.Create`
  (via `Ess.Safe.template`) — the direct-spawn path was already guarded, the copter path wasn't, and a blank
  template can hard-CTD through the internal spawn (pcall can't catch a native crash).
- **`Ess.Easy.Debug.overlay`** now throttles its nearby world-scan (two native `FastCollect` passes) to ~1×/s
  and caches it, instead of running it on every fast pos/aim tick — a dev overlay should stay light enough not
  to perturb what you're measuring.

## [0.2.1]

### Changed
- **`Ess.Easy.Camera.orbit` and `.watch(chase=true)` now damp the follow by default.** The moving camera
  eases toward its ideal position each tick via `Ess.Vec.lerp`, low-passing the per-tick position
  quantization that made a follow of a FAST subject jitter — confirmed live against an orbit around a heli
  and a hard-launched car. New opts: `smooth` (default `true`; pass `false` for the old exact-snap) and
  `smoothFactor` (0..1, default `0.2` — higher = snappier / less lag, lower = glassier / more lag). The
  static (non-chase) `watch` is unchanged; it has no per-tick position to smooth.

## [0.2.0]

A pure-Lua utility layer, an onboarding + contributor guide, an offline test suite wired into CI, and a
dozen new samples. All additive — nothing changed in existing engine code.

### Added
- **`Ess.Str`** — the string helpers Lua 5.1's thin `string` lib omits: split / join / trim / startsWith /
  endsWith / contains / count / padLeft / padRight / capitalize / title / lines / truncate. Separators are
  LITERAL text, not Lua patterns (so `split(s, ".")` splits on a real dot).
- **`Ess.Color`** — RGB helpers for the `rgb = {r,g,b}` params across `Ess.Mark` / `Ess.UI`: `hex` (web
  colours, long or short form), `hsv` (rainbows and evenly-spaced team tints), `lerp` (health-bar
  gradients), and a `NAMES` preset table.
- **`Ess.Table`** collection helpers — keys / values / count / isEmpty / contains / indexOf / map / filter /
  find / reduce / slice / reverse / copy / merge.
- **`Ess.Math`** — clamp01 / remap / smoothstep / lerpAngle (shortest-path angle lerp) / wrap; plus
  dist2DSq / dist3DSq and within2D / within3D (the `dx*dx+dz*dz <= r*r` range test, named — no sqrt).
- **`Ess.Vec`** — 3D vector math on flat x,y,z (length / normalize / scale / add / sub / dot / dir / toward
  / lerp) — the spatial helpers spawn / aim / knockback code otherwise open-codes.
- **`Ess.RNG`** — `:shuffle` (in-place, unbiased Fisher-Yates) and `:pickN` (distinct sample without
  replacement).
- **GETTING_STARTED.md** — an install-to-first-mod on-ramp (linked from the README) for a game that never
  shipped mod support: the OnLoad/OnKey model, the `_G.Ess` guard, the re-run gotcha, the dev loop.
- **CONTRIBUTING.md** — how to extend Ess safely (the build, the three verification gates, adding a
  namespace) plus the confirmed engine rules every helper respects (a useful reference for any Mercs2 Lua).
- **`samples/OnKey/StarterMod.lua`** — a copy-me starter template (the guard / state / action patterns as a
  god-mode toggle), bound to F5 and shipped in the release zip.
- Recipes: `text_and_tables`, `smooth_and_range`, `pick_colors`, `vector_math`, `random_order` (the new
  utilities); `cooldowns`, `remember_this_session` (timing / session state); `watch_a_vehicle`,
  `a_custom_hud` (engine patterns). The 34-recipe catalog is regrouped by theme.
- **`tools/checkpure.py`** — an offline behavioral test suite (via lupa) for the pure namespaces
  (Math / Str / Color / Table / RNG / State / Time), wired into CI alongside the syntax gate. Catches
  pure-logic regressions with no game required — coverage `smoke.py` can't give without the game up.
- The release zip now bundles the on-ramp and the full reference (`Ess-GETTING_STARTED.md` /
  `Ess-CAPABILITIES.md`), so a download is self-contained for learning, not just installing.

**Verification:** the entire pure-Lua layer (Safe / Str / Color / Vec / Table / Math / RNG / Points / State /
Time) is execute-verified offline by `tools/checkpure.py`, the merged build passes the `luac5.1` syntax gate,
and the **full recipe suite ran 34/34 PASS in a live game** — including the two engine-touching recipes
`watch_a_vehicle` and `a_custom_hud`. The `StarterMod` OnKey template isn't covered by `smoke.py` (it's a
keybound script, not a recipe), but is built from the same confirmed calls those passing recipes exercise.

## [0.1.1]

### Fixed
- Packaging: the release zip now bundles `samples/PORTING_MENUS.md` (and any future top-level sample doc)
  under `Ess-samples/`. `build/package.py` had hardcoded only `samples/README.md`, so the v0.1.0 zip left
  the menu-porting guide out.

## [0.1.0]

First public release — the whole `Ess` framework as one drop-in `1_Ess.lua`, plus the UI wad, the
bind-to-a-key demos, and the recipe catalog.

### Added
- **The framework** — safe, one-line wrappers over this project's hard-won Mercenaries 2 modding patterns,
  across ~60 namespaces: Object / Vehicle / Human / Player / Probe / Bones; the Loop / Input / Time / State /
  Save primitives; the leak-proof Track teardown; the `Ess.UI` kit (menus, lists, toasts, board, chat);
  Camera plus a declarative Cinematic timeline; the encounter toolkit (AIOrders / Relations / Triggers /
  Sandbox / Layers); Net; and the save-safe ephemeral Contract mission engine — organised in the
  Raw → Core → Easy tiered model.
- **Samples** — 25 self-verifying recipes (each a living doc *and* a smoke test run by `tools/smoke.py`) and
  five bind-to-a-key demos, including the MissionForge in-game authoring tool.
- **Build tooling** — `build/merge.py` (concatenate `src/` into `dist/Ess.lua`) and `build/package.py` (the
  release zip in game-folder layout), plus CI + release GitHub Actions.

### Fixed
- Contract trigger action crashed (`table index is nil`) when a support/waypoint was wired by
  `trigger={ref=...}` with no `id` of its own — id-less referenced entries are handled now.
- `escort` read a killable target's position un-pcall'd; `spawnAhead` now reuses `Ess.Math.pointAhead`
  instead of re-inlining the projection; dropped a redundant save-holder reset.

### UI
- Hold Up/Down to auto-repeat through a list/menu after a short delay; the selection now wraps around at the
  top and bottom instead of stopping.
