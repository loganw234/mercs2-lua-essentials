-- RECIPE: spawn particle effects -- at a spot, or attached to an object.
-- Namespaces: Ess.Easy.Spawn (fx / fxOn), Ess.Object, Ess.Player, Ess.Easy.Triggers.
--
--   Ess.Easy.Spawn.fx(template, x, y, z)        - a particle effect at a world location
--   Ess.Easy.Spawn.fxOn(template, guid [, bone]) - glued to an object (name a bone to pin it to a bone)
-- You name the bone because only YOU know what model you're attaching to. Confirmed FX template names
-- include fx_Explosion_Huge, global_particle_explosion_c4, global_particle_env_smokeplume_distance_tall.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local px, py, pz = Ess.Player.pose(0)
if not px then Ess.Log("[SMOKE] attach_effects: FAIL (no player position)") return end

-- a smoke plume at a fixed point
Ess.Easy.Spawn.fx("global_particle_env_smokeplume_distance_tall", px + 8, py, pz + 8)

-- a smoke plume attached to a spawned car (so it moves with it)
local car = Ess.Object.spawn("Veyron", px + 4, py, pz + 4)
if car then Ess.Easy.Spawn.fxOn("global_particle_env_smokeplume_distance_tall", car) end

local ok = (type(Ess.Easy.Spawn.fx) == "function") and (car ~= nil)
Ess.Log("[recipe] attach_effects: smoke plume at a point + attached to a car")
Ess.Easy.Triggers.after(6, function() Ess.Object.remove(car) end)

Ess.Log("[SMOKE] attach_effects: " .. (ok and "PASS" or "FAIL"))
