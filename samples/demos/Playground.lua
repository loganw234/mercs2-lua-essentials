local KEYVAL = "f3"   -- add "Playground.lua=f3" under [OnKey] in lua_loader.ini

-- Playground.lua -- press F3 to open the Ess interactive PLAYGROUND: drill into Ess.Easy.* functions by
-- topic, RUN one live, and cycle its parameters to see EXACTLY what each does in-game, on demand. The
-- fastest way to learn what the framework can do without reading a line of code. Press F3 again to close it.
--
-- DEPLOY: Ess (dist/Ess.lua) as an OnLoad script; this under scripts/OnKey/ with  Playground.lua=f3.

local Ess = _G.Ess
if not (Ess and Ess.Easy and Ess.Easy.Console) then
    if Loader and Loader.Printf then Loader.Printf("[playground] load the Essentials framework (1_Ess.lua) first") end
    return
end

Ess.Easy.Console.play()   -- toggles open / closed
