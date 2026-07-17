-- Ess/01_math.lua -- Ess.Math: the small geometry/number helpers this project re-derives in file after
-- file (the spawn-ahead forward trig, camera orbit/dolly lerps, MissionForge's grid placement, distance
-- checks in a dozen encounter scripts). One confirmed-correct home for each so nobody re-implements -- and
-- re-mis-signs -- the yaw math again. Loads right after 00_core (pure functions, no Ess deps).
--
-- ENGINE CONVENTION (load-bearing, live-calibrated -- see the ess-open-world-testing-spot memory): Y is UP;
-- the horizontal plane is X/Z. A yaw's FORWARD vector is (-sin(yaw), +cos(yaw)) in (x,z) -- that's the exact
-- projection Ess.Object.spawnAhead was calibrated against in-engine (accurate to ~4deg, the parallax between
-- the character's facing and the third-person camera). angleTo/pointAhead below are consistent with it, so a
-- yaw from angleTo fed to Object.SetYaw faces the way you expect, and pointAhead matches spawnAhead exactly.
--
-- API:
--   Ess.Math.clamp(v, lo, hi) -> n            Ess.Math.lerp(a, b, t) -> n            Ess.Math.sign(v) -> -1|0|1
--   Ess.Math.round(v [, decimals]) -> n       Ess.Math.approach(cur, target, maxStep) -> n  (ease toward)
--   Ess.Math.dist2D(x1,z1, x2,z2) -> n        Ess.Math.dist3D(x1,y1,z1, x2,y2,z2) -> n
--   Ess.Math.angleTo(fromX,fromZ, toX,toZ) -> yawDegrees   -- the yaw that FACES from->to
--   Ess.Math.pointAhead(x, z, yawDeg, dist) -> x2, z2      -- project (x,z) forward by a yaw (spawnAhead math)
--   Ess.Math.normDeg(deg) -> n in [-180, 180)             -- normalize an angle (shortest-turn friendly)
--   Ess.Math.clamp01(v) -> n                  Ess.Math.remap(v, inLo,inHi, outLo,outHi) -> n  (linear rescale)
--   Ess.Math.smoothstep(t) -> n (ease 0..1)   Ess.Math.lerpAngle(a,b,t) -> deg (shortest path)   Ess.Math.wrap(v,lo,hi) -> n
--   Ess.Math.dist2DSq/.dist3DSq(...) -> n (no sqrt)   Ess.Math.within2D(x1,z1,x2,z2,r) / .within3D(...) -> bool (range test)

local Ess = _G.Ess
Ess.Math = Ess.Math or {}
local M = Ess.Math

function M.clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

function M.lerp(a, b, t) return a + (b - a) * t end

function M.sign(v) if v > 0 then return 1 elseif v < 0 then return -1 else return 0 end end

-- round to `decimals` places (default 0 = nearest integer).
function M.round(v, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(v * mult + 0.5) / mult
end

-- move `cur` toward `target` by at most `maxStep` (a frame-rate-independent ease when maxStep = speed*dt).
function M.approach(cur, target, maxStep)
    local d = target - cur
    if d > maxStep then return cur + maxStep elseif d < -maxStep then return cur - maxStep else return target end
end

-- horizontal (X/Z-plane) distance -- the one you want for "how far away is it on the ground," ignoring
-- height. dist3D includes the Y (height) term.
function M.dist2D(x1, z1, x2, z2)
    local dx, dz = x2 - x1, z2 - z1
    return math.sqrt(dx * dx + dz * dz)
end
function M.dist3D(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Ess.Math.angleTo(fromX, fromZ, toX, toZ) -> yaw in DEGREES that points from (fromX,fromZ) toward
-- (toX,toZ), in the engine's own yaw convention (forward = (-sin,cos)). Feed the result to Object.SetYaw /
-- Ess.Object.setYaw to turn a thing to face a target. Returns 0 if the two points coincide.
function M.angleTo(fromX, fromZ, toX, toZ)
    local dx, dz = toX - fromX, toZ - fromZ
    if dx == 0 and dz == 0 then return 0 end
    return math.deg(math.atan2(-dx, dz))
end

-- Ess.Math.pointAhead(x, z, yawDeg, dist) -> x2, z2 -- the point `dist` units in FRONT of (x,z) when facing
-- yawDeg. This is exactly Ess.Object.spawnAhead's projection, exposed for reuse (place something ahead of an
-- NPC, aim a dolly, offset a marker) without re-deriving the sin/cos. Y is unchanged (caller keeps it).
function M.pointAhead(x, z, yawDeg, dist)
    local yr = math.rad(yawDeg or 0)
    return x - math.sin(yr) * dist, z + math.cos(yr) * dist
end

-- normalize any angle to [-180, 180) -- so a difference of two yaws reads as the SHORTEST turn (e.g. 350
-- and 10 differ by 20, not 340). Handy for "am I roughly facing this" checks and smooth turn easing.
function M.normDeg(deg)
    deg = deg % 360
    if deg >= 180 then deg = deg - 360 end
    return deg
end

-- clamp to the unit range [0,1] -- the common case for a lerp/ease parameter.
function M.clamp01(v) if v < 0 then return 0 elseif v > 1 then return 1 else return v end end

-- linear rescale: map v from [inLo,inHi] onto [outLo,outHi] ("a 0..maxHealth into a 0..1 bar," "a distance
-- into an alpha"). A degenerate input range (inLo == inHi) returns outLo rather than dividing by zero.
function M.remap(v, inLo, inHi, outLo, outHi)
    if inHi == inLo then return outLo end
    return outLo + (outHi - outLo) * ((v - inLo) / (inHi - inLo))
end

-- smoothstep ease of a 0..1 t -> 0..1 with zero slope at both ends (3t^2 - 2t^3). Feed it to lerp for an
-- ease-in-out: Ess.Math.lerp(a, b, Ess.Math.smoothstep(t)). Clamps t first.
function M.smoothstep(t)
    t = M.clamp01(t)
    return t * t * (3 - 2 * t)
end

-- interpolate angle a -> b (DEGREES) the SHORTEST way, so 350 -> 10 eases +20 through zero, not -340 the
-- long way round. t in [0,1]; result normalized to [-180,180). The right lerp for a turning yaw.
function M.lerpAngle(a, b, t)
    return M.normDeg(a + M.normDeg(b - a) * t)
end

-- wrap v into the half-open range [lo, hi) -- keep an index, an angle, or a cursor in-band. hi <= lo -> lo.
function M.wrap(v, lo, hi)
    local span = hi - lo
    if span <= 0 then return lo end
    return lo + ((v - lo) % span)
end

-- squared distances -- skip the sqrt when you only COMPARE ("which is closer", "is it within r"). dist2DSq
-- is the horizontal (X/Z) plane; dist3DSq includes height.
function M.dist2DSq(x1, z1, x2, z2)
    local dx, dz = x2 - x1, z2 - z1
    return dx * dx + dz * dz
end
function M.dist3DSq(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    return dx * dx + dy * dy + dz * dz
end

-- Ess.Math.within2D(x1,z1, x2,z2, r) -> bool -- is the second point within radius r of the first, on the
-- ground plane? The `dx*dx + dz*dz <= r*r` range test, named -- no sqrt, no way to fumble the squaring.
-- within3D includes the height term. This is the check every proximity trigger / "reached the zone" poll
-- open-codes; here once.
function M.within2D(x1, z1, x2, z2, r)
    return M.dist2DSq(x1, z1, x2, z2) <= r * r
end
function M.within3D(x1, y1, z1, x2, y2, z2, r)
    return M.dist3DSq(x1, y1, z1, x2, y2, z2) <= r * r
end
