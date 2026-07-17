# Porting a menu script to `Ess.UI.Menu`

Ess absorbed **both** old menu libraries — uilib (`UI.Menu`) and ForgeMenu (`ForgeMenu.new`) — into one
surface: `Ess.UI.Menu`. It's kept **API-compatible** with them on purpose, so porting an existing menu is a
couple of lines at the top; the categories/entries/`ctx` below are untouched.

You also get to **delete a dependency**: `Ess.UI.Menu` lives inside `dist/Ess.lua`, so once Ess is loaded
(`[OnLoad] 1_Ess.lua`) you no longer register `uilib.lua` or `ForgeMenu.lua` in `lua_loader.ini`.

The whole builder + `ctx` surface (identical across all three):

```
menu:entry(label, action)      menu:category(label, buildFn)   menu:header(text)
menu:switch(label, get, set)   menu:toggle() / :open() / :close() / :isOpen()
ctx.x  ctx.y  ctx.z  ctx.yaw  ctx.char  ctx.player
ctx:spawn(template, dist)   ctx:hint(msg)   ctx:toast(msg)   ctx:print(msg)   ctx:close()
ctx:confirm(text, onYes, onNo)   ctx:ask(prompt, onSubmit, onCancel)
```

---

## uilib (`UI.Menu`) → Ess  — one alias line

`Ess.UI.Menu` is the uilib menu, byte-for-byte. Point `UI` at `Ess.UI` at the top and **nothing else changes**
(constructor, `:entry`/`:category`/`:switch`, `ctx`, `menu:toggle()` all identical).

```lua
-- BEFORE (uilib)
if not (_G.UI and UI.Menu) then
    Loader.Printf("SpawnMenu: uilib not loaded"); return
end

-- AFTER (Ess) -- alias UI to Ess.UI; the rest of the file is unchanged
local UI = _G.Ess and _G.Ess.UI
if not (UI and UI.Menu) then
    Loader.Printf("SpawnMenu: load Ess (dist/Ess.lua) first"); return
end
```

Everything past that line — `UI.Menu{ title=.., key=.. }`, every `menu:category`/`:entry`/`:switch`, and the
final `menu:toggle()` — works as written, because `UI` now resolves to `Ess.UI`.

*(`ctx:hint` already popped a top-right toast in uilib, so no behavior change there.)*

---

## ForgeMenu (`ForgeMenu.new`) → Ess  — guard + constructor

Two edits: the load guard and the constructor (positional args become one table). The builder and `ctx`
below are unchanged.

```lua
-- 1. guard: depend on Ess instead of the ForgeMenu library
--    BEFORE
if not ForgeMenu then Loader.Printf("load ForgeMenu first"); return end
--    AFTER
local Ess = _G.Ess
if not (Ess and Ess.UI and Ess.UI.Menu) then Loader.Printf("load Ess (dist/Ess.lua) first"); return end

-- 2. constructor:  ForgeMenu.new("Title", {key=..})  ->  Ess.UI.Menu{ title="Title", key=.. }
--    BEFORE
local menu = ForgeMenu.new("MY MENU", { key = "F8" })
--    AFTER
local menu = Ess.UI.Menu{ title = "MY MENU", key = "F8" }
```

`menu:entry` / `:category` / `:switch`, and every `ctx` helper (`ctx:spawn`, `ctx:hint`, `ctx:print`,
`ctx:close`, `ctx.x/y/z/yaw/char`) port **as-is** — `ctx:print` maps to `Ess.Log` internally, so even
that carries over.

**One behavior note:** `ctx:hint` now pops a **toast** (top-right) instead of writing the menu's bottom
line. Same call, nicer feedback — nothing to change unless you were relying on the old placement.

---

## Reference

`samples/OnKey/CustomMenu.lua` (F4) is a complete working menu on `Ess.UI.Menu` — diff your script against
it if anything looks off.
