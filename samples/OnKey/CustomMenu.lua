local KEYVAL = "f4"   -- must be in the first 10 lines (add "CustomMenu.lua=f4" under [OnKey])

-- CustomMenu.lua -- "I want my own menu of cool stuff." A beginner template for a custom in-game menu, built
-- on Ess.UI.Menu and wired to the Ess.Easy.* one-liners. Press F4 to toggle it. COPY THIS FILE, swap in the
-- entries you want, and you've got your own menu -- no .gfx authoring, no widget plumbing.
--
-- HOW A MENU WORKS (the whole API you need):
--   local menu = Ess.UI.Menu{ title = "...", key = "F4" }   -- make a menu
--   menu:category("Name", function(m) ... end)              -- a submenu you drill into
--   menu:entry("Label", function(ctx) ... end)              -- a button; its action(ctx) runs when picked
--   menu:switch("Label", getFn, setFn)                      -- an ON/OFF toggle button
-- `ctx` (passed to every action) carries the player's position + helpers:
--   ctx.x/ctx.y/ctx.z/ctx.yaw/ctx.char   ctx:spawn(template, distAhead)   ctx:hint(msg)   ctx:close()
--   ctx:confirm(text, onYes)   ctx:ask(prompt, onSubmit)
-- Arrow keys move, Enter picks, Left goes back / closes.
--
-- DEPLOY: Ess (dist/Ess.lua) as an OnLoad script; this under scripts/OnKey/ with  CustomMenu.lua=f4.

local Ess = _G.Ess
if not (Ess and Ess.UI and Ess.UI.Menu) then
    if Loader and Loader.Printf then Loader.Printf("[custommenu] load the Essentials framework (dist/Ess.lua) first") end
    return
end

-- persistent state for the one toggle switch below (survives the OnKey re-run on each keypress)
_G.CustomMenu = _G.CustomMenu or {}
local State = _G.CustomMenu

local menu = Ess.UI.Menu{ title = "MY COOL MENU", key = KEYVAL }

menu:category("Spawn", function(m)
    m:entry("Helicopter (hop in)", function()    Ess.Easy.Vehicle.summon("AH1Z (Full)") end)  -- spawn + drive
    m:entry("A fast car",          function(ctx) ctx:spawn("Veyron", 8) end)                   -- 8u ahead of you
    m:entry("Supply crate",        function()    Ess.Easy.Spawn.crate() end)
    m:entry("A few soldiers",      function(ctx) for i = 1, 3 do ctx:spawn("Chinese Soldier", 9 + i * 2) end end)
end)

menu:category("Effects", function(m)
    m:entry("Big explosion (ahead)", function()    Ess.Easy.Spawn.explosion("fx_Explosion_Huge") end)
    m:entry("Slow motion (3s)",      function()    Ess.Easy.Time.slowmo(0.3, 3) end)
    m:entry("Smoke on me",           function(ctx) Ess.Easy.Spawn.fxOn("global_particle_env_smokeplume_distance_tall", ctx.char) end)
end)

menu:category("Me", function(m)
    m:entry("Heal to full",       function(ctx) Ess.Object.heal(ctx.char); ctx:hint("Healed") end)
    m:entry("Grappling hook",     function(ctx) Ess.Easy.Player.giveGrapplingHook(); ctx:hint("Grapple unlocked") end)
    m:entry("Unlock fast travel", function(ctx) Ess.Easy.Player.unlockFastTravel(); ctx:hint("Fast travel unlocked") end)
    m:entry("Become Fiona",       function()    Ess.Easy.Player.skin("pmc_hum_fiona") end)   -- a reload restores you
end)

menu:category("World", function(m)
    -- a switch reads a value with get(), flips it, and applies it with set(newValue, ctx)
    m:switch("Remove map walls", function() return State.noBounds end, function(v, ctx)
        State.noBounds = v
        if v then Ess.Easy.World.removeMapBoundary(); ctx:hint("Roam anywhere") end
    end)
    m:entry("Lose the cops",  function(ctx) Ess.Easy.World.clearWanted(); ctx:hint("Heat cleared") end)
    m:entry("Hellscape look", function()    Ess.Easy.World.hellscape() end)   -- region-gated (a real map area)
    m:entry("Reset the sky",  function()    Ess.Easy.World.resetAtmosphere() end)
end)

menu:category("Fun", function(m)
    m:entry("Victory fanfare", function() Ess.Easy.Fun.fanfare(true) end)
    m:entry("Dance!",          function() Ess.Easy.Fun.dance() end)
end)

menu:entry("Close", function(ctx) ctx:close() end)

menu:toggle()   -- F4 opens/closes the menu (this whole script re-runs on each keypress; toggle() flips it)
Ess.Log("[custommenu] toggled -- built on Ess.UI.Menu + Ess.Easy.*")
