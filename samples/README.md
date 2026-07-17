# Ess samples

Everything here is meant to keep working release to release — it's the framework's **living documentation**
and its **pre-release smoke test** at the same time.

- **`recipes/`** — short "**how do I achieve X?**" scripts, one task each. Read them to learn the idiom; run
  them to prove the framework still works. Each ends with a self-verifying `[SMOKE] <name>: PASS/FAIL` log
  line, and any that spawn things clean up after themselves a few seconds later.
- **`OnKey/`** — larger interactive demos you bind to a key and watch.

Each file guards on `_G.Ess` and bails cleanly if the framework isn't loaded, so nothing errors deep in a
handler.

## Recipes (`samples/recipes/`)

| Recipe | Achieves | Namespaces |
|---|---|---|
| `spawn_and_control` | spawn a thing in front of you, then move / face / heal / remove it | Object, Math, Player |
| `watch_a_vehicle` | react when the player enters/exits any vehicle | Object, Player |
| `command_a_squad` | spawn a group of units and order them | Object, AIOrders |
| `command_a_helicopter` | spawn a crewed helicopter and fly it in (AI-piloted) | Vehicle, Object |
| `make_them_fight` | set two factions at war and confirm the stance took | Relations |
| `random_selection` | pick things at random the engine-safe way | RNG |
| `random_order` | shuffle a list / sample distinct entries | RNG |
| `text_and_tables` | split/trim/join text; map/filter/find over tables | Str, Table |
| `pick_colors` | build marker/UI colours — hex, HSV, gradients, presets | Color |
| `find_whats_around` | scan for nearby objects | Probe |
| `mark_things` | put objective / zone markers down, then clear them | Mark |
| `do_it_later` | run something after a delay, and on a repeating timer | Triggers, Loop, Time |
| `cooldowns` | rate-limit an action; get a per-frame delta | Time |
| `slow_motion` | a slow-motion finisher beat | Time |
| `attach_effects` | particle FX at a point / attached to an object | Easy.Spawn |
| `speed_boost` | launch / boost / knockback with mass-scaled impulses | Easy.Impulse |
| `notify_the_player` | toast / banner / objective line / radio subtitle | Hud, UI |
| `a_custom_hud` | a live-updating panel + progress bar | UI, Loop |
| `persistent_vars` | remember a value across save/reload | SaveVar |
| `remember_this_session` | keep state across an OnKey script's re-runs | State |
| `give_weapons` | give the player a weapon + infinite ammo | Human |
| `an_arena` | run a save-safe ephemeral "arena" / minigame mode | Sandbox |
| `world_tweaks` | clear heat / lift the map walls / recolour the sky | Easy.World |
| `player_powers` | grappling hook / fast travel / free support unlocks | Easy.Player |
| `for_fun` | swap your look + play a fanfare | Easy.Player, Easy.Fun |
| `a_simple_mission` | author a whole 2-objective mission with a reward | Contract |
| `a_richer_mission` | a mission where a trigger fires mid-mission support call-ins | Contract |
| `a_cutscene` | play a declarative cutscene — camera shots + an actor + narration | Cinematic |
| `direct_the_camera` | take over the camera for an orbit shot, then hand control back | Easy.Camera, Camera |
| `attach_to_bones` | pin an effect to a named bone; handle a fresh spawn's startup delay | Bones |
| `track_lifecycles` | bundle spawns/events/timers on one handle, tear it all down at once | Track, Event |
| `override_safely` | change game logic without the tail-call crash; merge into a live table | Override |

## Interactive scripts (`samples/OnKey/`)

Larger bind-to-a-key scripts — demos to watch, plus the mission-authoring tool. Deploy the ones you want into
the game's `scripts/OnKey/` and bind them in `lua_loader.ini` (e.g. `MissionForge.lua=F7` under `[OnKey]`).

| Script | Key | What it is |
|---|---|---|
| `MissionForge` | F7 | **the mission-authoring tool** — walk (or fly) around and drop-at-your-position placement of units / objectives / support / triggers / AI-orders / **cinematic camera shots**, then export a `MISSIONFORGE_EXPORT` block for the web tool (or hand-authoring) to turn into an `Ess.Contract`. A full tool, not a demo (~1100 lines); consumes Ess throughout. |
| `CustomMenu` | F4 | **make your own menu of cool stuff** — a beginner template: Ess.UI.Menu wired to the Ess.Easy.* one-liners (spawn / effects / unlocks / world tweaks). Copy it and swap in your own entries. |
| `CoopChat` | F2 | co-op text chat — per-player username over the wire, auto-fade (Net + UI.Chat) |
| `CinematicDemo` | F9 | a 12-step showcase cutscene — camera / spawn / fly-in / orbit / narration (Cinematic) |
| `CarStunt` | F10 | get in a car, rocket down the runway, launch + do aerial tricks, watch yourself fly (Impulse + Camera) |

## Running the smoke test

With the game running (lua-bridge up) and `dist/Ess.lua` built (`python build/merge.py`):

```
python tools/smoke.py
```

It reloads the current build, runs every recipe, and reports `PASS` / `FAIL` / `MISSING` per recipe, exiting
non-zero if anything isn't green. Run it before tagging a release — if a change broke a public helper, a
recipe goes red.

Recipes whose real result is **visual** (FX, HUD text, the slow-mo feel) verify only that the calls ran
clean; their `[recipe] ...` log line says what each one achieved so you can eyeball the game to confirm.
