-- RECIPE: ease values, remap ranges, turn the short way, check proximity -- the maths behind HUD bars,
-- smooth motion, and "is it close enough" tests.
-- Namespaces: Ess.Math.
--
-- These are the scalar/geometry helpers you reach for constantly: fill a health bar, ease a fade or a zoom,
-- rotate a yaw without spinning the long way round, and range-check without an sqrt. All pure, so the
-- [SMOKE] check is real assertions.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- remap: turn a raw health value (0..maxHP) into a 0..1 bar fill
local fill = Ess.Math.remap(75, 0, 100, 0, 1)                       -- 0.75

-- smoothstep: ease a 0..1 progress with zero slope at both ends (ease-in-out). Feed it to lerp for smooth
-- interpolation -- here a camera zoom easing from 60 to 90 degrees, halfway through.
local zoom = Ess.Math.lerp(60, 90, Ess.Math.smoothstep(0.5))        -- 75

-- lerpAngle: turn a yaw the SHORT way -- 350 -> 10 eases through 0 (+20), not -340 the long way.
local yaw = Ess.Math.lerpAngle(350, 10, 0.5)                        -- 0

-- within2D: is a point within radius on the ground plane? No sqrt, no fumbled squaring.
local near = Ess.Math.within2D(0, 0, 3, 4, 5)                       -- true (distance 5, radius 5)

-- clamp01 keeps a computed t in range before you ease/lerp with it (a stray negative or >1 won't overshoot)
local safeT = Ess.Math.clamp01(1.4)                                 -- 1

local ok = (fill == 0.75) and (zoom == 75) and (yaw == 0) and near and (safeT == 1)
Ess.Log(string.format("[recipe] smooth_and_range: fill=%.2f zoom=%g yaw=%g near=%s clampedT=%g",
    fill, zoom, yaw, tostring(near), safeT))
Ess.Log("[SMOKE] smooth_and_range: " .. (ok and "PASS" or "FAIL"))
