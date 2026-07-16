-- RECIPE: find out what's around me -- scan for nearby objects (enemies, vehicles, anything).
-- Namespaces: Ess.Probe, Ess.Object, Ess.Player, Ess.Easy.Triggers.
--
-- Ess.Probe.nearby(x,y,z, radius [, kind, filter]) returns a list of guids in range; Ess.Probe.nearest(...)
-- returns just the closest one. Both EXCLUDE the player's own character by default -- a deliberate safety
-- default (self-inclusion once caused an accidental "kill everything nearby" including the player).

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local px, py, pz = Ess.Player.pose(0)
if not px then Ess.Log("[SMOKE] find_whats_around: FAIL (no player position)") return end

-- put two things nearby so there's guaranteed something to find
local a = Ess.Object.spawn("Veyron", px + 8, py, pz)
local b = Ess.Object.spawn("Veyron", px - 8, py, pz)

local found = Ess.Probe.nearby(px, py, pz, 20)         -- everything within 20u (player excluded)
local n = (type(found) == "table") and #found or -1
local ok = n >= 2                                      -- at least the two we just placed

Ess.Log("[recipe] find_whats_around: found " .. n .. " object(s) within 20u")
Ess.Easy.Triggers.after(5, function() Ess.Object.remove(a); Ess.Object.remove(b) end)

Ess.Log("[SMOKE] find_whats_around: " .. (ok and "PASS" or ("FAIL (found " .. n .. ")")))
