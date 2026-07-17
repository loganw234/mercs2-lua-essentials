-- RECIPE: remember values across an OnKey script's re-runs -- no save file involved.
-- Namespaces: Ess.State.
--
-- An OnKey script re-runs top-to-bottom on every keypress: your `local`s reset, and only the global `_G`
-- table survives between presses. Ess.State gives you a `_G`-backed table that persists across those re-runs
-- -- and, unlike a blind `_G.S = _G.S or {...}`, it merges in defaults you ADD later (so shipping a new
-- field in an update actually takes effect next run instead of being skipped). This is the in-session
-- cousin of Ess.SaveVar, which persists across full game restarts (see the persistent_vars recipe).

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- grab (or create) this mod's persistent state
local S = Ess.State("recipe_demo", { presses = 0, mode = "idle" })
S.presses = S.presses + 1              -- this survives to the next keypress

-- fetching the same-named state again returns the SAME table (that identity is what makes it persist) --
-- and a default added here (`added`) gets merged in WITHOUT wiping the running `presses` count.
local S2 = Ess.State("recipe_demo", { presses = 0, mode = "idle", added = "new-in-this-version" })

local ok = (S2 == S) and (S2.presses == S.presses) and (S2.added == "new-in-this-version")
Ess.Log("[recipe] remember_this_session: presses=" .. S.presses ..
    " (climbs each keypress); newly-added default merged in = " .. tostring(S2.added))
Ess.Log("[SMOKE] remember_this_session: " .. (ok and "PASS" or "FAIL"))
