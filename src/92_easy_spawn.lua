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
    Ess.Safe.quiet(Airstrike.SpawnOrdnance, sRound or "Artillery Shell", px, py + 250, pz, 0, -100, 0, "impact", 1)
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

-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Bulk: units / vehicles / props. Three intent-named wrappers over Ess.Spawn.many, one per thing a beginner
-- actually wants a pile of. Each drops its group in a ring AROUND you (Ess.Spawn's "scatter"), not stacked
-- on one point -- spawning n things at one coordinate is the failure mode these exist to prevent.
--
-- Each takes an optional template that is EITHER one name or a roster array, so the same call covers
-- "eight of these" and "a section made of these types":
--     Ess.Easy.Spawn.units(8)                                        -- eight of the default
--     Ess.Easy.Spawn.units(8, "AL Soldier")                          -- eight of one type
--     Ess.Easy.Spawn.units(8, { "AL Soldier", "AL Heavy" })          -- eight, alternating the two
--     Ess.Easy.Spawn.units(nil, AL_RIFLE_SECTION)                    -- exactly the roster, one of each
-- Nothing here orders anyone to do anything -- these place units, they do not start a fight.
-- Ess.Easy.Spawn.enemies (below) is the one that spawns hostiles AND sends them at you; it is unchanged.
-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────

-- ALL FOUR CENTRE THE RING ON THE PLAYER (`ahead = 0`), not on Ess.Spawn's default centre 20 units in
-- front. Their distance arguments are named "from the player" and are documented that way, so they have to
-- MEAN that. CONFIRMED LIVE 2026-07-26: without this, `roster(section, 12, 20, 60)` put units 2..53 away
-- from the player instead of 20..60 -- the band was correct, but measured from a centre the caller never
-- named. Silent, plausible-looking, and exactly the kind of mismatch a beginner cannot debug.

-- Ess.Easy.Spawn.units(nCount, vTemplate) -> { guid, ... } -- people, 6-20 units out, on the ground.
function Ess.Easy.Spawn.units(nCount, vTemplate)
    return Ess.Spawn.many(vTemplate or "VZ Soldier", nCount, {
        minDist = 6, maxDist = 20, ahead = 0, snapToGround = true, faceCentre = true,
    })
end

-- Ess.Easy.Spawn.vehicles(nCount, vTemplate) -> { guid, ... } -- vehicles need room: a wider ring and more
-- spacing than infantry, or they spawn inside each other and shove themselves apart.
function Ess.Easy.Spawn.vehicles(nCount, vTemplate)
    return Ess.Spawn.many(vTemplate or "Veyron", nCount, {
        minDist = 12, maxDist = 30, ahead = 0, snapToGround = true,
    })
end

-- Ess.Easy.Spawn.props(nCount, vTemplate) -> { guid, ... } -- scenery/clutter. Snapped to the ground so a
-- prop field on a slope doesn't leave half of it buried and half hovering.
function Ess.Easy.Spawn.props(nCount, vTemplate)
    return Ess.Spawn.many(vTemplate or "TinyGeometry", nCount, {
        minDist = 4, maxDist = 18, ahead = 0, snapToGround = true,
    })
end

-- Ess.Easy.Spawn.roster(vTemplates, nQty, nMinDist, nMaxDist) -> { guid, ... }
-- The named-section case in the shape it was actually asked for: a roster table, a quantity, and a distance
-- band. Omit nQty to spawn the roster exactly once through (one of each).
--     AL_RIFLE_SECTION = { "AL Soldier", "AL Soldier", "AL Heavy", "AL Sniper" }
--     Ess.Easy.Spawn.roster(AL_RIFLE_SECTION, 12, 20, 60)
function Ess.Easy.Spawn.roster(vTemplates, nQty, nMinDist, nMaxDist)
    return Ess.Spawn.many(vTemplates, nQty, {
        minDist = nMinDist or 8, maxDist = nMaxDist or 25, ahead = 0,
        snapToGround = true, faceCentre = true,
    })
end

-- Ess.Easy.Spawn.enemies(nCount, opts) -> { guid, ... } -- drop a squad of hostiles a short way in front of
-- you and set them ON you: an instant firefight in one line. opts: template ("VZ Soldier"), dist (14 ahead),
-- spread (3), attack (default true -- order them to attack you; false = just spawn them), target (default you).
-- Returns the spawned guids so you can order/track them further. CONFIRMED enemy template "VZ Soldier"
-- (command_a_squad recipe); swap opts.template once the spawn catalog lands.
function Ess.Easy.Spawn.enemies(nCount, opts)
    opts = opts or {}
    local n, tmpl = nCount or 3, opts.template or "VZ Soldier"
    local px, py, pz, yaw = Ess.Player.pose(0)
    if not px then return {} end
    local sx, sz = Ess.Math.pointAhead(px, pz, yaw or 0, opts.dist or 14)   -- a spot ahead of you (hides the yaw math)
    local spread = opts.spread or 3
    local squad = {}
    for i = 1, n do
        local ox, oz = ((i - 1) % 3 - 1) * spread, math.floor((i - 1) / 3) * spread
        local g = Ess.Object.spawn(tmpl, sx + ox, py, sz + oz)
        if g then squad[#squad + 1] = g end
    end
    if #squad > 0 and opts.attack ~= false then
        local target = opts.target or Ess.Player.character(0)
        if target then Ess.Easy.AIOrders.attack(squad, target) end    -- send them at you
    end
    return squad
end
