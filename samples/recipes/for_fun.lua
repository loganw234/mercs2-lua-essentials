-- RECIPE: just for fun -- change your look and play a victory sting.
-- Namespaces: Ess.Easy.Player (skin), Ess.Easy.Fun.
--
-- Ess.Easy.Player.skin swaps your WHOLE-FIGURE outfit by model code (individual body parts don't work --
-- it's the whole "*_hum_*" figure). A reload restores your normal look. Confirmed codes include
-- "pmc_hum_fiona", "pmc_hum_eva", "vz_hum_solano", "al_hum_boss", "ch_hum_boss".

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

Ess.Easy.Player.skin("pmc_hum_fiona")   -- become Fiona
Ess.Easy.Fun.fanfare(true)              -- the mission-success music sting
-- Ess.Easy.Fun.dance()                  -- uncomment to do the technoviking dance

local ok = type(Ess.Easy.Player.skin) == "function" and type(Ess.Easy.Fun.fanfare) == "function"
Ess.Log("[recipe] for_fun: swapped skin + played a fanfare")
Ess.Log("[SMOKE] for_fun: " .. (ok and "PASS" or "FAIL"))
