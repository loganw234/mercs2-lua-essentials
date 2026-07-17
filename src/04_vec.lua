-- Ess/04_vec.lua -- Ess.Vec: 3D vector helpers on flat (x, y, z) values -- the spatial math that spawn /
-- aim / knockback / camera code keeps open-coding (normalize a direction, step a point toward a target,
-- lerp two positions). Pure Lua, no engine calls, no Ess deps.
--
-- Everything takes and returns FLAT components (three values), not a table -- matching how the rest of Ess
-- passes positions (Ess.Object.pos returns x,y,z; Ess.Object.setPos takes x,y,z) and Ess.Color's own
-- three-value convention. So results drop straight into those calls:
--   Ess.Object.setPos(u, Ess.Vec.toward(px,py,pz, tx,ty,tz, 5))    -- move it 5 units toward the target
--   Ess.Object.impulse(u, Ess.Vec.scale(Ess.Vec.dir(fx,fy,fz, tx,ty,tz), 8000))   -- shove it that way
--
-- (Ess.Math holds the 2D/ground-plane + angle helpers -- angleTo, pointAhead, dist2D, within2D. Ess.Vec is
-- the full-3D vector companion to those.)
--
-- API (each returns flat components):
--   Ess.Vec.length(x,y,z) -> n
--   Ess.Vec.normalize(x,y,z) -> nx,ny,nz          unit vector; a zero vector returns 0,0,0 (never NaN)
--   Ess.Vec.scale(x,y,z, s) -> x,y,z
--   Ess.Vec.add(x1,y1,z1, x2,y2,z2) -> x,y,z      Ess.Vec.sub(a, b) -> x,y,z   (a - b, i.e. the vector b->a)
--   Ess.Vec.dot(x1,y1,z1, x2,y2,z2) -> n
--   Ess.Vec.dir(fromX,fromY,fromZ, toX,toY,toZ) -> nx,ny,nz          unit direction from A to B
--   Ess.Vec.toward(fromX,fromY,fromZ, toX,toY,toZ, dist) -> x,y,z    the point `dist` from A toward B
--   Ess.Vec.lerp(x1,y1,z1, x2,y2,z2, t) -> x,y,z                     interpolate two positions

local Ess = _G.Ess
Ess.Vec = Ess.Vec or {}
local V = Ess.Vec

function V.length(x, y, z)
    return math.sqrt(x * x + y * y + z * z)
end

function V.normalize(x, y, z)
    local len = math.sqrt(x * x + y * y + z * z)
    if len == 0 then return 0, 0, 0 end
    return x / len, y / len, z / len
end

function V.scale(x, y, z, s)
    return x * s, y * s, z * s
end

function V.add(x1, y1, z1, x2, y2, z2)
    return x1 + x2, y1 + y2, z1 + z2
end

function V.sub(x1, y1, z1, x2, y2, z2)
    return x1 - x2, y1 - y2, z1 - z2
end

function V.dot(x1, y1, z1, x2, y2, z2)
    return x1 * x2 + y1 * y2 + z1 * z2
end

function V.dir(fx, fy, fz, tx, ty, tz)
    return V.normalize(tx - fx, ty - fy, tz - fz)
end

function V.toward(fx, fy, fz, tx, ty, tz, dist)
    local nx, ny, nz = V.dir(fx, fy, fz, tx, ty, tz)
    return fx + nx * dist, fy + ny * dist, fz + nz * dist
end

function V.lerp(x1, y1, z1, x2, y2, z2, t)
    return x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, z1 + (z2 - z1) * t
end
