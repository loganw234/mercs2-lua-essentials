-- Ess/16_impulse.lua -- Ess.Impulse: launch / boost / knock objects around, the confirmed Object.ApplyImpulse
-- way, with the fiddly bits handled. The 3-tier waterfall: Ess.Raw.Impulse (the bare natives) feeds
-- Ess.Impulse (a mass-scaled directional push that hides the local-axis convention) feeds Ess.Easy.Impulse
-- (speedBoost / launch / knockback intent presets).
--
-- CONFIRMED CONVENTION (resident/spyhunter.lua's boost/jump mechanic -- the SPEED-BOOST effect this wraps):
--   Object.ApplyImpulse(uGuid, x, y, z, bLocal) in LOCAL space is (x = SIDE, y = UP, z = FORWARD).
--   Real boosts scale the impulse by the object's MASS -- e.g. ApplyImpulse(u, 0, 10000, 8*mass, true) --
--   because an impulse is mass * Δvelocity, so to change SPEED by a consistent amount no matter how heavy the
--   thing is, the impulse itself must scale with its mass. That mass bookkeeping (Object.GetMass, the axis
--   order, local-vs-world) is exactly what makes the raw call awkward; Ess.Impulse.push does it for you.

local Ess = _G.Ess
Ess.Raw = Ess.Raw or {}
Ess.Raw.Impulse = Ess.Raw.Impulse or {}
Ess.Impulse = Ess.Impulse or {}
Ess.Easy = Ess.Easy or {}
Ess.Easy.Impulse = Ess.Easy.Impulse or {}

-- ============================================================
-- RAW -- the bare natives, one pcall each. (Ess.Object.impulse is the same call as .apply; these add the
-- point-impulse and the mass getter the higher tiers need, and keep the whole system in one namespace.)
-- ============================================================

-- Ess.Raw.Impulse.apply(uGuid, x, y, z, bLocal) -- Object.ApplyImpulse. LOCAL space (bLocal true, the default)
-- is (x=side, y=up, z=forward); WORLD space (bLocal false) is world x/y/z.
function Ess.Raw.Impulse.apply(uGuid, x, y, z, bLocal)
    pcall(Object.ApplyImpulse, uGuid, x or 0, y or 0, z or 0, bLocal ~= false)
end

-- Ess.Raw.Impulse.applyAtPoint(uGuid, ix, iy, iz, px, py, pz, bLocal) -- Object.ApplyPointImpulse: an impulse
-- (ix,iy,iz) applied at an OFFSET point (px,py,pz) rather than the center -- an off-center push imparts SPIN
-- (torque), which is how spyhunter.lua does its barrel-roll flip. Defaults to local space.
function Ess.Raw.Impulse.applyAtPoint(uGuid, ix, iy, iz, px, py, pz, bLocal)
    pcall(Object.ApplyPointImpulse, uGuid, ix or 0, iy or 0, iz or 0, px or 0, py or 0, pz or 0, bLocal ~= false)
end

-- Ess.Raw.Impulse.mass(uGuid) -> n | nil -- Object.GetMass, pcall'd (the scaling factor the boosts use).
function Ess.Raw.Impulse.mass(uGuid)
    local ok, m = pcall(Object.GetMass, uGuid)
    if ok and type(m) == "number" then return m end
    return nil
end

-- ============================================================
-- CORE -- Ess.Impulse.push: one directional push with the mass scaling + axis convention handled.
-- ============================================================
local DEFAULT_MASS = 1000   -- fallback if GetMass is unavailable, so a mass-scaled push still does something

-- Ess.Impulse.push(uGuid, opts) -- shove an object. opts:
--   forward / up / side  -- LOCAL-space components ("forward" = the way it faces); omit any -> 0.
--   dir = {x,y,z}        -- OR a WORLD-space direction (overrides forward/up/side) -- for knockback etc.
--   strength             -- scales `dir` (default 1); for the forward/up/side form just bake it into those.
--   scaleByMass          -- default TRUE: multiply by the object's mass so the VELOCITY change is the same on
--                           a light bike or a heavy tank (impulse = mass*Δv). Pass false for a raw, mass-
--                           independent shove where you supply the full magnitude yourself.
function Ess.Impulse.push(uGuid, opts)
    opts = opts or {}
    local factor = 1
    if opts.scaleByMass ~= false then factor = Ess.Raw.Impulse.mass(uGuid) or DEFAULT_MASS end
    if opts.dir then
        local d, s = opts.dir, (opts.strength or 1) * factor
        Ess.Raw.Impulse.apply(uGuid, (d.x or d[1] or 0) * s, (d.y or d[2] or 0) * s, (d.z or d[3] or 0) * s, false)
    else
        Ess.Raw.Impulse.apply(uGuid, (opts.side or 0) * factor, (opts.up or 0) * factor, (opts.forward or 0) * factor, true)
    end
end

-- Ess.Impulse.spin(uGuid, opts) -- an OFF-CENTER impulse to make something roll / flip (spyhunter's barrel
-- roll). opts.forward/up/side = the impulse (local); opts.at = {x,y,z} the local offset it's applied at (the
-- lever arm -- further from center = more spin). scaleByMass as in push.
function Ess.Impulse.spin(uGuid, opts)
    opts = opts or {}
    local factor = 1
    if opts.scaleByMass ~= false then factor = Ess.Raw.Impulse.mass(uGuid) or DEFAULT_MASS end
    local at = opts.at or {}
    Ess.Raw.Impulse.applyAtPoint(uGuid,
        (opts.side or 0) * factor, (opts.up or 0) * factor, (opts.forward or 0) * factor,
        at.x or at[1] or 0, at.y or at[2] or 0, at.z or at[3] or 0, true)
end

-- Ess.Impulse.mass(uGuid) -> n | nil -- the mass getter, surfaced at the Core tier too.
function Ess.Impulse.mass(uGuid) return Ess.Raw.Impulse.mass(uGuid) end

-- ============================================================
-- EASY -- intent presets. Default target = an explicit guid, else the vehicle you're driving, else you.
-- ============================================================
local function defaultTarget(uGuid)
    if uGuid then return uGuid end
    local char = Ess.Player.character(0)
    if not char then return nil end
    return Ess.Object.vehicleOf(char) or char        -- boost the car you're in, or you on foot
end

-- Ess.Easy.Impulse.speedBoost(uGuid, strength) -- a forward SPEED BOOST (the Spy Hunter effect). Defaults to
-- the vehicle you're driving. strength ~8 is a strong boost (spyhunter used 6-8); mass-scaled, so it feels the
-- same in a bike or a tank.
function Ess.Easy.Impulse.speedBoost(uGuid, strength)
    local t = defaultTarget(uGuid); if not t then return end
    Ess.Impulse.push(t, { forward = strength or 8 })
end

-- Ess.Easy.Impulse.launch(uGuid, strength) -- pop something straight UP (a hop, or a big launch).
function Ess.Easy.Impulse.launch(uGuid, strength)
    local t = defaultTarget(uGuid); if not t then return end
    Ess.Impulse.push(t, { up = strength or 12 })
end

-- Ess.Easy.Impulse.knockback(uGuid, fromGuid, strength) -- shove uGuid directly AWAY from fromGuid (default
-- source = you) with a slight upward lift -- the "the blast sent them flying" feel. World-direction, mass-scaled.
function Ess.Easy.Impulse.knockback(uGuid, fromGuid, strength)
    if not uGuid then return end
    fromGuid = fromGuid or Ess.Player.character(0)
    local tx, ty, tz = Ess.Object.pos(uGuid)
    local fx, fy, fz = Ess.Object.pos(fromGuid)
    if not (tx and fx) then return end
    local dx, dy, dz = tx - fx, (ty - fy) + 0.5, tz - fz            -- away + a bit up so they lift off
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len <= 0 then dx, dy, dz, len = 0, 1, 0, 1 end
    Ess.Impulse.push(uGuid, { dir = { dx / len, dy / len, dz / len }, strength = strength or 10 })
end
