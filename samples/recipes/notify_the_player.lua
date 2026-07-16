-- RECIPE: get the player's attention -- the four notification styles and when to use each.
-- Namespaces: Ess.Easy.Toast, Ess.Hud.
--
--   Ess.Easy.Toast(msg)      - a small custom-UI toast, auto-dismisses     (a pickup, a small event)
--   Ess.Hud.banner(msg)      - a big centered fanfare-style banner         (a milestone -- "Area Cleared")
--   Ess.Hud.objective(msg)   - the persistent objective-tray line (nil clears)  (the current task)
--   Ess.Hud.radio(msg, hold) - a self-clearing lower-third subtitle        (radio chatter / dialogue)

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

Ess.Easy.Toast("Pickup collected")
Ess.Hud.banner("Area Cleared")
Ess.Hud.objective("Objective: reach the LZ")
Ess.Hud.radio("\"On my way, over.\"", 4)

Ess.Easy.Triggers.after(5, function() Ess.Hud.objective(nil) end)   -- clear the objective line again

-- these are fire-and-forget HUD calls (the result is on-screen); PASS = they were all callable + didn't error.
local ok = type(Ess.Easy.Toast) == "function" and type(Ess.Hud.banner) == "function"
    and type(Ess.Hud.objective) == "function" and type(Ess.Hud.radio) == "function"
Ess.Log("[recipe] notify_the_player: showed a toast, a banner, the objective line, and a radio subtitle")
Ess.Log("[SMOKE] notify_the_player: " .. (ok and "PASS" or "FAIL"))
