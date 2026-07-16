-- Ess/92_easy_spawn.lua -- Ess.Easy.Spawn: one-line "make something cool appear near me" verbs. All spawn
-- via Ess.Object.spawn/spawnAhead (blank-template crash guard + in-front math already handled), using the
-- confirmed template-name strings a beginner would never guess. Defaults are chosen so a bare call
-- (`Ess.Easy.Spawn.explosion()`) does something fun immediately.

local Ess = _G.Ess
Ess.Easy = Ess.Easy or {}
Ess.Easy.Spawn = Ess.Easy.Spawn or {}

-- Ess.Easy.Spawn.explosion(sType) -> uGuid | nil -- a big boom ~10 units in front of you (in front, not
-- on your face, so it's dramatic without instakilling). CONFIRMED explosion templates (pg-spawn-calls):
-- "Explosion (Grenade)" (default), "Explosion (C4)", "Explosion (MOAB)", "Explosion (Rocket Artillery)",
-- "fx_Explosion_Huge". These are REAL, damaging explosions -- don't stand in them.
function Ess.Easy.Spawn.explosion(sType)
    return Ess.Object.spawnAhead(sType or "Explosion (Grenade)", 10, 0)
end

-- Ess.Easy.Spawn.crate(sType) -> uGuid | nil -- a supply drop that parachutes down just in front of you.
-- CONFIRMED crate templates (bountycopter.lua): "Supply Drop (Light MG)" (default), "Supply Drop
-- (Blueprints)", "Supply Drop (Treasure)". Spawned high so it falls in with its chute, the way the game's
-- own bounty crates do.
function Ess.Easy.Spawn.crate(sType)
    return Ess.Object.spawnAhead(sType or "Supply Drop (Light MG)", 6, 150)
end

-- Ess.Easy.Spawn.weapon(sName) -> uGuid | nil -- drop a weapon PICKUP on the ground in front of you (walk
-- over it to grab it). CONFIRMED weapon templates (spawn-reference/weapons): "RPG" (default), "Sniper
-- Rifle", "Assault Rifle", "Minigun", "Shotgun", "Grenade Launcher", "C4", "Anti-Material Rifle", "Pistol".
-- (To put a weapon straight into your hands instead, use Ess.Easy.Human.giveWeapon.)
function Ess.Easy.Spawn.weapon(sName)
    return Ess.Object.spawnAhead(sName or "RPG", 6, 0)
end

-- Ess.Easy.Spawn.airstrike(sRound) -- call a shell down on your own head (a classic sandbox gag). CONFIRMED
-- shape (MasterCheatMenu's DropOrdnanceAt): Airstrike.SpawnOrdnance(round, x, y+high, z, vx,vy,vz, fuze,
-- value) -- a shell spawned 250 up with downward velocity, impact-fused. Real, lethal ordnance. sRound
-- defaults to "Artillery Shell"; other confirmed rounds: "Gunship Shell", "Cluster Bomb Projectile",
-- "Cruise Missile Projectile", "Bomb".
function Ess.Easy.Spawn.airstrike(sRound)
    local px, py, pz = Ess.Object.pos(Ess.Player.character(0))
    if not px then return end
    pcall(Airstrike.SpawnOrdnance, sRound or "Artillery Shell", px, py + 250, pz, 0, -100, 0, "impact", 1)
end

-- ============================================================
-- Particle / FX -- spawn an effect three ways: at a LOCATION, ON an object (its current position), or
-- BOUND to a bone on an object (follows it). CONFIRMED FX/particle templates (pg-spawn-calls):
--   "fx_Explosion_Huge", "global_particle_explosion_c4", "global_particle_env_smokeplume_distance_tall",
--   plus the whole "Explosion (Grenade/C4/MOAB/...)" family. One-shot FX self-destruct; ambient ones (a
--   smoke plume) persist until you Object.Remove them.
-- YOU supply the bone name in the bone form -- only you know your target model's bone names (a character's
-- real bones work; vehicle collision-string hardpoints do NOT bind, see the camera notes).
-- ============================================================

-- Ess.Easy.Spawn.fx(sTemplate, x, y, z) -> uGuid | nil -- an effect at a world location.
function Ess.Easy.Spawn.fx(sTemplate, x, y, z)
    return Ess.Object.spawn(sTemplate, x, y, z)
end

-- Ess.Easy.Spawn.fxOn(sTemplate, uGuid, sBone) -> handle | nil -- an effect on an object. With sBone it's
-- GLUED to that bone and follows the object (via the confirmed Ess.Bones.attachFX recipe); without a bone
-- it's a one-shot spawned at the object's current position (won't follow). Remove a bone-bound one with
-- Ess.Bones.detachFX(uGuid, handle).
function Ess.Easy.Spawn.fxOn(sTemplate, uGuid, sBone)
    if sBone then return Ess.Bones.attachFX(uGuid, sBone, sTemplate) end
    local x, y, z = Ess.Object.pos(uGuid)
    if not x then return nil end
    return Ess.Object.spawn(sTemplate, x, y, z)
end
