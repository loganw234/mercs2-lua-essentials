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
| `command_a_squad` | spawn a group of units and order them | Object, AIOrders |
| `command_a_helicopter` | spawn a crewed helicopter and fly it in (AI-piloted) | Vehicle, Object |
| `make_them_fight` | set two factions at war and confirm the stance took | Relations |
| `random_selection` | pick things at random the engine-safe way | RNG |
| `find_whats_around` | scan for nearby objects | Probe |
| `mark_things` | put objective / zone markers down, then clear them | Mark |
| `do_it_later` | run something after a delay, and on a repeating timer | Triggers, Loop, Time |
| `slow_motion` | a slow-motion finisher beat | Time |
| `attach_effects` | particle FX at a point / attached to an object | Easy.Spawn |
| `notify_the_player` | toast / banner / objective line / radio subtitle | Hud, UI |
| `persistent_vars` | remember a value across save/reload | SaveVar |
| `a_simple_mission` | author a whole 2-objective mission with a reward | Contract |

## Interactive demos (`samples/OnKey/`)

| Demo | Key | Shows |
|---|---|---|
| `CoopChat` | F2 | co-op text chat — per-player username over the wire, auto-fade (Net + UI.Chat) |
| `CinematicDemo` | F9 | a 12-step showcase cutscene — camera / spawn / fly-in / orbit / narration (Cinematic) |

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
