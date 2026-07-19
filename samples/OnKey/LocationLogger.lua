local KEYVAL = "f8"   -- must be in the first 10 lines (add "LocationLogger.lua=f8" under [OnKey])

-- LocationLogger.lua -- a tiny worked example: pop up the Ess text console, type a name for the spot
-- you're standing on, and on Enter log that label + your exact coordinates to lua_loader_printf.log.
-- Shows Ess.TextConsole (typed input, no .gfx asset needed) + Ess.Player.pose (position + facing).
--
-- Press F8, type e.g. "airfield south gate", press Enter -> the log gets a [LOCATION] line you can grep.
-- DEPLOY: Ess (dist/Ess.lua) as an OnLoad script; this under scripts/OnKey/ with  LocationLogger.lua=f8.

local Ess = _G.Ess
if not (Ess and Ess.TextConsole) then
    if Loader and Loader.Printf then Loader.Printf("[loclogger] load the Essentials framework (dist/Ess.lua) first") end
    return
end

-- capture where the player is RIGHT NOW, the moment the key is pressed (typing freezes movement anyway)
local x, y, z, yaw = Ess.Player.pose(0)
if not x then Ess.Log("[loclogger] no player position yet (are you in the world?)"); return end

Ess.TextConsole.open{
    prompt = "Name this spot: ",
    onSubmit = function(text)                                  -- Enter: log + close
        Ess.Log(string.format("[LOCATION] %s  @ x=%.2f  y=%.2f  z=%.2f  yaw=%.1f",
            (text ~= "" and text) or "(unnamed)", x, y, z, yaw))
        Ess.TextConsole.close()                                -- (Enter alone keeps it open for more entries)
    end,
    onCancel = function() Ess.Log("[loclogger] cancelled -- nothing logged") end,   -- Escape: close, no log
}
