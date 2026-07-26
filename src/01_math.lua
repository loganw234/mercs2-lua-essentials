-- Ess/01_math.lua -- Ess.Math: the small geometry/number helpers this project re-derives in file after
-- file (the spawn-ahead forward trig, camera orbit/dolly lerps, MissionForge's grid placement, distance
-- checks in a dozen encounter scripts). One confirmed-correct home for each so nobody re-implements -- and
-- re-mis-signs -- the yaw math again. Loads right after 00_core (pure functions, no Ess deps).
--
-- ENGINE CONVENTION (load-bearing, live-calibrated 2026-07-19): Y is UP; the horizontal plane is X/Z.
-- A yaw's FORWARD vector is **(+sin(yaw), +cos(yaw))** in (x,z). angleTo/pointAhead below are exact
-- inverses of each other -- if the convention ever needs revisiting, they MUST be changed as a pair.
--
-- ⚠ THIS WAS MIRRORED (x sign) UNTIL 2026-07-19 -- history, because it hid for a long time and will
-- otherwise be "re-fixed" back. It used to be (-sin, +cos), with angleTo = atan2(-dx, dz). Proven wrong by
-- an A/B marker test: two rings placed from the SAME body yaw, one per convention. Facing EAST (yaw ~ +90)
-- the (+sin) ring was dead ahead and the (-sin) ring was 180 degrees BEHIND. Facing NORTH (yaw ~ 0) the two
-- rings COINCIDE, because sin(0) = 0.
--   => the error is INVISIBLE at yaw 0/180 and MAXIMAL at yaw +-90.
--   => ALWAYS calibrate this facing EAST/WEST. An earlier calibration done facing north "passed" and let
--      the mirror survive; a second one misread the residual as camera parallax. Don't repeat either.
--
-- ✔ INDEPENDENT CORROBORATION (2026-07-26): the engine exposes a native `Math.GetXZHeading(x,y,z) -> deg`
-- that nothing in Ess calls. Fed the forward vector for a spread of yaws (0, +-45, +-90, 135, 180) it
-- returns the yaw back to within 0.05 deg EVERY time -- i.e. the engine itself agrees that forward is
-- (+sin, +cos). That is a second, independent witness for the convention above, from the engine rather
-- than from a marker test, and it is why this comment can now say "confirmed" rather than "calibrated".
-- Useful as a re-calibration oracle too: if this convention is ever doubted again, compare against
-- Math.GetXZHeading before re-running the ring test.
--
-- ⚠ SEPARATELY (a real, DIFFERENT phenomenon -- don't conflate it with the above): Object.GetYaw(character)
-- is the CHEST/BODY orientation, NOT where the player is LOOKING. Stand still and swing the mouse and the
-- view rotates while the body does not; running forward re-aligns them. So even with the trig correct,
-- "spawn in front of me" lands in front of the BODY. For VIEW-relative placement derive the look direction
-- separately (Ess.Player.targetUnderReticle -> angleTo) and pass THAT yaw in.
--
-- API:
--   Ess.Math.clamp(v, lo, hi) -> n            Ess.Math.lerp(a, b, t) -> n            Ess.Math.sign(v) -> -1|0|1
--   Ess.Math.round(v [, decimals]) -> n       Ess.Math.approach(cur, target, maxStep) -> n  (ease toward)
--   Ess.Math.dist2D(x1,z1, x2,z2) -> n        Ess.Math.dist3D(x1,y1,z1, x2,y2,z2) -> n
--   Ess.Math.angleTo(fromX,fromZ, toX,toZ) -> yawDegrees   -- the yaw that FACES from->to
--   Ess.Math.pointAhead(x, z, yawDeg, dist) -> x2, z2      -- project (x,z) forward by a yaw (spawnAhead math)
--   Ess.Math.rotateOffset(x, z, yawDeg, localX, localZ) -> x2, z2  -- a local (right,forward) offset -> world
--   Ess.Math.normDeg(deg) -> n in [-180, 180)             -- normalize an angle (shortest-turn friendly)
--   Ess.Math.clamp01(v) -> n                  Ess.Math.remap(v, inLo,inHi, outLo,outHi) -> n  (linear rescale)
--   Ess.Math.smoothstep(t) -> n (ease 0..1)   Ess.Math.lerpAngle(a,b,t) -> deg (shortest path)   Ess.Math.wrap(v,lo,hi) -> n
--   Ess.Math.dist2DSq/.dist3DSq(...) -> n (no sqrt)   Ess.Math.within2D(x1,z1,x2,z2,r) / .within3D(...) -> bool (range test)

-- ⚠ THE ENGINE'S OWN `Math.*` NATIVES -- TWO OF THEM ARE TRAPS. `Math` and `math` are the SAME table
-- (`Math == math` is true live), so the capital alias is not a separate namespace; eight of its entries are
-- engine additions rather than stock Lua 5.1. Ess covers the useful ones already, but anyone reaching for
-- the natives directly needs these two warnings, both live-measured 2026-07-26:
--
--   Math.PolarToRect(angleDEGREES, radius) -> x, y
--     NOT yaw-compatible. It is a plain textbook polar->cartesian: (r*cos, r*sin), zero degrees along +X,
--     whereas this engine's forward is (sin, cos) with zero along +Z. So the outputs are TRANSPOSED against
--     everything else here -- feeding a yaw into it puts the result 90 degrees off AND mirrored, which is
--     the exact failure documented above. Note also the argument order is (angle, radius), not (r, theta).
--     If you ever do want it: PolarToRect(90 - yaw, dist) reproduces Ess.Math.pointAhead(0, 0, yaw, dist).
--     Verified: pointAhead disagrees with the raw native at every yaw tested, and agrees after that fix.
--
--   Math.randf(a, b)  -> uniform over [a, b+1), NOT [a, b]
--     It borrows Math.randi's inclusive-integer span (max-min+1). Measured over 300 samples, randf(5,10)
--     produced a maximum of 10.96. `Math.randf()` with no arguments is a normal [0,1). Use Ess.RNG instead
--     -- it is seedable, reproducible, and documented against this engine's 32-bit-float trap.
--
-- The other six are fine: Length / Normalize / CrossProduct match Ess.Vec exactly (A/B'd), GetXZHeading is
-- the corroboration noted above, round is half-away-from-zero (Ess.Math.round adds decimal places), and
-- randi(min,max) is a correct inclusive integer roll.

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
-- (toX,toZ), in the engine's own yaw convention (forward = (+sin,cos)). Feed the result to Object.SetYaw /
-- Ess.Object.setYaw to turn a thing to face a target. Returns 0 if the two points coincide.
-- EXACT INVERSE of pointAhead below: angleTo(x,z, pointAhead(x,z,Y,d)) == Y. Change both or neither.
function M.angleTo(fromX, fromZ, toX, toZ)
    local dx, dz = toX - fromX, toZ - fromZ
    if dx == 0 and dz == 0 then return 0 end
    return math.deg(math.atan2(dx, dz))
end

-- Ess.Math.pointAhead(x, z, yawDeg, dist) -> x2, z2 -- the point `dist` units in FRONT of (x,z) when facing
-- yawDeg. This is exactly Ess.Object.spawnAhead's projection, exposed for reuse (place something ahead of an
-- NPC, aim a dolly, offset a marker) without re-deriving the sin/cos. Y is unchanged (caller keeps it).
function M.pointAhead(x, z, yawDeg, dist)
    local yr = math.rad(yawDeg or 0)
    return x + math.sin(yr) * dist, z + math.cos(yr) * dist
end

-- Ess.Math.rotateOffset(x, z, yawDeg, localX, localZ) -> worldX, worldZ
-- Place a LOCAL offset (localX = right+, localZ = forward+) into world space around (x,z) for a thing facing
-- yawDeg -- i.e. "put this at 5 right and 10 ahead of me". The general case pointAhead is the localX=0
-- special case of. Exists because a hand-rolled rotation matrix is exactly where this project re-derived --
-- and re-mis-signed -- the yaw math before (MissionForge's squad grid); use this instead of writing one.
function M.rotateOffset(x, z, yawDeg, localX, localZ)
    local yr = math.rad(yawDeg or 0)
    local s, c = math.sin(yr), math.cos(yr)
    return x + localX * c + localZ * s, z - localX * s + localZ * c
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
