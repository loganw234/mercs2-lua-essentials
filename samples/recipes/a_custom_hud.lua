-- RECIPE: a live-updating HUD -- a panel of text lines plus a progress bar, refreshed on a heartbeat.
-- Namespaces: Ess.UI (Panel, Bar), Ess.Loop, Ess.Player, Ess.Object.
--
-- Build the widgets ONCE, then push fresh values into them from an Ess.Loop tick. The widgets ride Ess.UI's
-- shared heartbeat for their own repaint/animation; your loop just calls their setters. (Needs the UI wad
-- deployed so the .gfx movies exist -- see GETTING_STARTED.)

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- a titled text panel and a labelled bar
local panel = Ess.UI.Panel{ x = 20, y = 120, title = "STATUS" }
local bar   = Ess.UI.Bar{ x = 20, y = 250, label = "Health" }

-- refresh 4x/second off the one shared heartbeat. Panel lines are 0-indexed; Bar:set takes 0..1.
local ticks = 0
Ess.Loop.start("recipe_hud", 0.25, function()
    ticks = ticks + 1
    local me = Ess.Player.character(0)
    local x, y, z = Ess.Object.pos(me)
    panel:line(0, x and string.format("Pos:  %.0f, %.0f, %.0f", x, y, z) or "Pos:  ?")
    panel:line(1, "Ticks: " .. ticks)

    local hp, maxhp = Ess.Object.health(me), Ess.Object.maxHealth(me)
    if hp and maxhp and maxhp > 0 then bar:set(hp / maxhp) end

    if ticks >= 60 then                 -- ~15s, then tidy the widgets away
        panel:destroy(); bar:destroy()
        return false
    end
    return true
end)

local ok = (panel ~= nil) and (bar ~= nil)
Ess.Log("[recipe] a_custom_hud: live status panel + health bar for ~15s")
Ess.Log("[SMOKE] a_custom_hud: " .. (ok and "PASS" or "FAIL"))
