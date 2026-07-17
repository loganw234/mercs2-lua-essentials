-- RECIPE: pin an effect to a named bone on a character, and handle a fresh spawn's startup delay.
-- Namespaces: Ess.Bones, Ess.Object, Ess.Player, Ess.Easy.Triggers.
--
-- Every bone on a character (and every hardpoint on a vehicle) is reachable from Lua BY NAME -- the engine
-- hashes the name, so declared "hp_*" hardpoints and raw "bone_*" skeleton joints resolve the same way.
--   Ess.Bones.attachFX(guid, bone, template) -> fx   spawn an FX at a bone and glue it there (moves with it)
--   Ess.Bones.detachFX(guid, fx)                     undo it (Detach + Remove; nil-safe)
--   Ess.Bones.waitForReady(guid, cb)                 a fresh Pg.Spawn's bones read nil for ~0.3s -- wait first
--   Ess.Bones.aimVector(guid, hpBase, hpTip)         the axis between two hardpoints (a turret's barrel line)
--   Ess.Bones.probeNames(guid, prefixes, suffixes)   sweep candidate names (a discovery tool -- see its caveat)

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local me = Ess.Player.character(0)
if not me then Ess.Log("[SMOKE] attach_to_bones: FAIL (no player character)") return end

-- Pin a smoke plume to YOUR head bone. The player character is already streamed in, so its bones resolve
-- immediately -- run around and the plume follows your head. ("Bone_Head"/"Bone_Chest" are confirmed human
-- joint names; a vehicle uses its own "hp_*" hardpoint names instead.)
local plume = Ess.Bones.attachFX(me, "Bone_Head", "global_particle_env_smokeplume_distance_tall")
local ok = plume ~= nil
Ess.Log("[recipe] attach_to_bones: head-plume attached=" .. tostring(ok))

-- The fresh-spawn case: a just-spawned model's hardpoints are nil for a moment, so reading them at spawn
-- time silently fails. waitForReady polls until the object's transform has initialized, THEN calls back --
-- the correct way to touch anything on a thing you just spawned.
local px, py, pz = Ess.Player.pose(0)
local car = Ess.Object.spawn("Veyron", px + 10, py, pz)
if car then
    Ess.Bones.waitForReady(car, function(u)
        local x, y, z = Ess.Object.pos(u)
        Ess.Log(string.format("[recipe] attach_to_bones: fresh spawn ready, transform @ %.1f,%.1f,%.1f", x or 0, y or 0, z or 0))
    end)
end

-- tidy up: peel the plume back off, remove the car.
Ess.Easy.Triggers.after(6, function()
    Ess.Bones.detachFX(me, plume)
    if car then Ess.Object.remove(car) end
end)

Ess.Log("[SMOKE] attach_to_bones: " .. (ok and "PASS" or "FAIL"))
