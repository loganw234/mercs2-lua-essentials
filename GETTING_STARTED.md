# Getting started with Ess

*Mercenaries 2* never shipped with mod support. What makes Lua modding possible is a **lua-bridge** loader
(an ASI plugin) that runs your `.lua` scripts inside the live game and exposes the engine's own `Object` /
`Pg` / `Vehicle` / `Ai` / `Player` / `Hud` namespaces to them. `Ess` sits on top of that: it wraps the
sharp edges of those raw calls into safe one-liners, so you can spend your time on your mod instead of
rediscovering which call crashes the engine.

This guide gets you from nothing to a working keypress mod. It assumes the lua-bridge loader is already
installed in your game (that's the one prerequisite Ess doesn't provide — if `scripts/lua_loader.ini` exists
in your game folder, you have it).

---

## 1. Install Ess

From a release zip (recommended — [Releases](https://github.com/loganw234/mercs2-lua-essentials/releases)),
extract it over your game folder. It drops three things into place:

```
<game>/data/vz-patch.wad             the .gfx movies Ess.UI renders through (menus, toasts, chat)
<game>/scripts/OnLoad/1_Ess.lua      the framework itself
<game>/scripts/OnKey/*.lua           optional bind-to-a-key demos
```

Then register the framework in `scripts/lua_loader.ini` — **add** this line (merge it into any existing
`[OnLoad]` section; don't overwrite the file):

```ini
[OnLoad]
1_Ess.lua=5
```

Launch the game. When a level loads you'll see `[Ess] v0.1.1 ready` in `scripts/lua_loader_printf.log`.
That's it — every other script can now use the global `Ess` table.

---

## 2. The two kinds of script

The loader runs your scripts at two moments, from two folders:

| Folder | Runs | Registered in `lua_loader.ini` | Use it for |
|---|---|---|---|
| `scripts/OnLoad/` | once, every time a level loads | `[OnLoad]` — `name.lua=<number>` (low = earlier) | libraries (like Ess), always-on systems |
| `scripts/OnKey/` | every time you press its key | `[OnKey]` — `name.lua=<key>` (e.g. `F5`, `insert`) | tools and mods you trigger by hand |

The number after an `[OnLoad]` script is its load order (Ess uses `5`, so it loads before your scripts that
depend on it). The value after an `[OnKey]` script is the key that fires it.

**Two things about OnKey scripts that trip everyone up at first:**

- An OnKey script **re-runs from the top on every keypress.** A `local` you set is gone by the next press;
  only the global `_G` table persists between runs. This is why Ess gives you `Ess.State` (below).
- The loader **re-reads the file each press**, so editing an OnKey script's code is live — no relaunch. But
  adding a *new* script or changing its `.ini` key binding needs a game relaunch to be picked up.

---

## 3. Your first mod

Create `scripts/OnKey/MyFirstMod.lua`:

```lua
-- fail cleanly if Ess didn't load (wrong load order, or not installed)
if not _G.Ess then Loader.Printf("load Ess first") return end

-- spawn a supercar in front of you and drop into the driver seat
Ess.Easy.Vehicle.summon("Veyron")

-- a little feedback on the HUD
Ess.Easy.Toast("Enjoy the ride")
```

Bind it in `scripts/lua_loader.ini`:

```ini
[OnKey]
MyFirstMod.lua=F5
```

Relaunch (new script + new binding), load a game, press **F5**. A Veyron appears ahead of you and you're in
it. You just wrote a mod.

Everything you'll build is variations on this: guard on `_G.Ess`, then call into it. The
[`samples/recipes/`](samples/recipes) folder is a couple dozen more of these, each a short "how do I *X*?" —
read them to learn the idioms, they're the fastest way in.

---

## 4. The shape of the API

Ess is organized in three tiers — reach for the highest one that fits:

- **`Ess.Easy.*`** — one-call, intent-named, hard to misuse: `Ess.Easy.Spawn.explosion()`,
  `Ess.Easy.World.clearWanted()`, `Ess.Easy.Camera.orbit(guid)`. Start here.
- **`Ess.*`** — named parameters and full control: `Ess.Object.spawn(template, x, y, z, yaw)`,
  `Ess.Mark.object(guid, { rgb = Ess.Color.NAMES.red })`.
- **`Ess.Raw.*`** — the primitives the other two are built from, for composing something new.

In-game, `Ess.Easy.Console.open()` opens a searchable, browsable list of the whole `Ess.Easy.*` surface —
the fastest way to discover what's available without leaving the game.

The full reference is [CAPABILITIES.md](CAPABILITIES.md) (what everything does) and, if you want the *why*,
[FEATURE_SHEET.md](FEATURE_SHEET.md) (the design log).

---

## 5. The re-run gotcha, and the two tools that solve it

Because an OnKey script re-runs each press, "toggle" mods and background loops need state that survives
between runs. Two helpers cover almost every case:

```lua
if not _G.Ess then Loader.Printf("load Ess first") return end

-- Ess.State: a table that persists across re-runs (and merges in new defaults if you add them later)
local S = Ess.State("MyMod", { godMode = false })

S.godMode = not S.godMode                              -- flip it each press
Ess.Object.setInvincible(Ess.Player.character(0), S.godMode, "MyMod")
Ess.Easy.Toast("God mode: " .. (S.godMode and "ON" or "OFF"))
```

And for anything that needs to run every frame (a HUD, a watcher), never hand-roll a timer — use the one
shared, reload-safe heartbeat:

```lua
-- ticks 5x/second; return false to stop. Calling start() again with the same id replaces the old loop,
-- so pressing the key twice never leaks a second loop.
Ess.Loop.start("MyMod.tick", 0.2, function()
    -- ...do something each tick...
    return true
end)
```

---

## 6. The dev loop (if you're building from source)

The repo builds to a single file:

```
python build/merge.py         # concatenate src/*.lua -> dist/Ess.lua
python build/package.py        # ...and zip it up in game-folder layout for a release
```

With the game running and the lua-bridge up, `python tools/smoke.py` reloads your current build and runs
every recipe as a self-test — a fast way to confirm a change didn't break a public helper. See
[tools/README.md](tools/README.md) for the live-reload REPL and the launch automation.

---

## Where to go next

- **[samples/recipes/](samples/recipes)** — short, runnable "how do I *X*?" scripts. The best way to learn.
- **[samples/OnKey/](samples/OnKey)** — bigger bind-to-a-key demos, including the MissionForge mission
  authoring tool.
- **[CAPABILITIES.md](CAPABILITIES.md)** — the full, current API surface, grouped by what you reach for.
- **`Ess.Easy.Console.open()`** — the same surface, browsable in-game.
