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
