-- RECIPE: remember a value across save/reload -- XP, unlock flags, high scores, a run counter.
-- Namespaces: Ess.SaveVar.
--
-- Ess.SaveVar wraps Loader.SaveVar with a per-mod namespace so two mods can't clobber each other's keys.
-- Values survive a save/reload (unlike an Ess.State global, which is per-session). Use it for anything the
-- player should keep between play sessions.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local sv = Ess.SaveVar.ns("RecipeDemo")        -- namespace your vars

local before = sv:get("runs", 0)               -- read with a default (0 the very first time)
sv:set("runs", before + 1)                     -- write it back (persists)
local after = sv:get("runs", 0)

sv:setFlag("said_hello", true)                 -- flags are the boolean flavor
local flagged = sv:flag("said_hello")

local ok = (after == before + 1) and (flagged == true)
Ess.Log("[recipe] persistent_vars: run counter " .. before .. " -> " .. after .. "; flag=" .. tostring(flagged))
Ess.Log("[SMOKE] persistent_vars: " .. (ok and "PASS" or "FAIL"))
