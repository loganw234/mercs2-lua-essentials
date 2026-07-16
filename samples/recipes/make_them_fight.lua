-- RECIPE: make two factions go to war with each other (China vs the Allies) and confirm the stance took.
-- Namespaces: Ess.Relations, Ess.Raw.Relations, Ess.Guid.
--
-- Ess.Easy.Relations.makeHostile only makes factions hostile TO THE PLAYER. For a faction-vs-faction war
-- (neither side being you) you want the core Ess.Relations.apply, which sets a MUTUAL stance for any pair
-- and hands back a HANDLE you hold and later restore -- so nothing leaks and two systems can't collide.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- set China <-> Allied to hostile. "hostile"/"ally"/"neutral" (or a raw number) both directions at once.
local handle = Ess.Relations.apply({ { "China", "Allied", "hostile" } }, "recipe_war")

-- prove it took: read the raw faction-to-faction relation back. On this engine hostile == -100.
local snap = Ess.Raw.Relations.snapshot(Ess.Guid("China"), Ess.Guid("Allied"))
local ok = snap and snap.ok and snap.val == -100
Ess.Log("[recipe] make_them_fight: China<->Allied relation is now " .. tostring(snap and snap.val)
    .. " (-100 = hostile)")

-- put the stances back exactly the way we found them (a real mission holds the handle for its whole run,
-- or lets Ess.Contract's def.relations manage this automatically).
Ess.Relations.restore(handle)

Ess.Log("[SMOKE] make_them_fight: " .. (ok and "PASS" or "FAIL"))
