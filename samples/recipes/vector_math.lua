-- RECIPE: 3D vector math -- aim a direction, offset a point, build a knockback shove.
-- Namespaces: Ess.Vec.
--
-- Ess.Vec works in flat x,y,z (three values in, three out) -- the same shape Ess.Object.pos/setPos and
-- Ess.Object.impulse already use -- so results drop straight into those calls with no table juggling.
-- Ess.Math holds the 2D/ground-plane + angle helpers; Ess.Vec is the full-3D companion.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- a unit direction from one point toward another (aim a projectile, a look, a shove)
local dx, dy, dz = Ess.Vec.dir(0, 0, 0, 0, 0, 10)              -- 0, 0, 1

-- the point 5 units from A toward B (place a spawn a little ahead of a target)
local px, py, pz = Ess.Vec.toward(0, 0, 0, 30, 0, 40, 5)       -- 3, 0, 4  (5 units along a 3-4-5 diagonal)

-- a knockback impulse = unit direction * strength.
-- GOTCHA worth knowing: Lua truncates a multi-return call to ONE value unless it's the LAST item in a list,
-- so `Ess.Vec.scale(Ess.Vec.dir(...), 8000)` would silently pass only dir's x. Capture into locals to nest.
-- (A Vec call DOES expand fully when it's the last arg of an engine call, e.g. Ess.Object.impulse(u, dir).)
local nx, ny, nz = Ess.Vec.dir(0, 0, 0, 3, 0, 4)
local ix, iy, iz = Ess.Vec.scale(nx, ny, nz, 8000)             -- 4800, 0, 6400

-- how those plug into the engine (shown; needs a live guid so not run here):
--   Ess.Object.impulse(guid, ix, iy, iz, false)                        -- world-space shove that way
--   Ess.Object.setPos(guid, Ess.Vec.toward(fx,fy,fz, tx,ty,tz, 5))     -- step it 5 units toward a target

local ok = (dz == 1) and (px == 3 and pz == 4) and (ix == 4800 and iz == 6400)
    and (Ess.Vec.length(3, 4, 0) == 5)
Ess.Log(string.format("[recipe] vector_math: dir=%g,%g,%g  toward=%g,%g,%g  shove=%g,%g,%g",
    dx, dy, dz, px, py, pz, ix, iy, iz))
Ess.Log("[SMOKE] vector_math: " .. (ok and "PASS" or "FAIL"))
