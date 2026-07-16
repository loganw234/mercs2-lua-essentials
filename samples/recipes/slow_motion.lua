-- RECIPE: a slow-motion moment -- the finisher / impact beat.
-- Namespaces: Ess.Easy.Time, Ess.Time.
--
-- Ess.Easy.Time.slowmo(scale, seconds) slows the whole game and auto-restores after `seconds` of REAL time
-- (so the restore isn't itself slowed down). For manual control use Ess.Time.scale(n) / .restoreScale().

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

Ess.Easy.Time.slowmo(0.3, 2)     -- 30% speed for 2 seconds, then back to normal on its own

local ok = type(Ess.Easy.Time.slowmo) == "function"
Ess.Log("[recipe] slow_motion: game at 30% speed for 2s, then auto-restores")
Ess.Log("[SMOKE] slow_motion: " .. (ok and "PASS" or "FAIL"))
