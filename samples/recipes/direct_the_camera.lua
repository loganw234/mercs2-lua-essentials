-- RECIPE: take over the camera for a cinematic shot -- orbit a target, then hand control back.
-- Namespaces: Ess.Easy.Camera, Ess.Camera, Ess.Object, Ess.Player, Ess.Easy.Triggers.
--
-- The camera on this engine has real gotchas (SetPosition no-ops without a live look-at binding; a moving
-- camera must use Blend 0 or it rubber-bands). Ess.Camera bakes the confirmed recipes in; Ess.Easy.Camera
-- gives you the finished shots:
--   Ess.Easy.Camera.orbit(guid, opts) -> stop()   smoothly circle a target (radius/height/speed/startAngle)
--   Ess.Easy.Camera.watch(guid, opts) -> stop()   a locked-off tracking shot (opts.chase to trail it)
--   Ess.Easy.Camera.shake(i) / Ess.Camera.fov(i, angle, dur)   punch-ups for impacts / zooms
-- ⚠ Any of these STEAL look control until you call the returned stop() (or Ess.Camera.panicRevert(), the
-- fire-blind escape hatch). ALWAYS provide a way back -- this one auto-releases after 5 seconds.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local px, py, pz = Ess.Player.pose(0)
if not px then Ess.Log("[SMOKE] direct_the_camera: FAIL (no player position)") return end

-- something worth looking at
local car = Ess.Object.spawn("Veyron", px + 12, py, pz)
if not car then Ess.Log("[SMOKE] direct_the_camera: FAIL (spawn failed)") return end

-- orbit it: the camera circles the car, re-aiming every tick (smooth, Blend 0 under the hood).
local stop = Ess.Easy.Camera.orbit(car, { radius = 10, height = 4, speed = 45 })
local tookOver = Ess.Camera._cine[0] ~= nil     -- entering cinematic mode records state per player index

Ess.Log("[recipe] direct_the_camera: orbiting a car; camera took over=" .. tostring(tookOver))

-- hand control back and clean up. (stop() == Ess.Camera.endCinematic(0) -- both release + kill the loop.)
Ess.Easy.Triggers.after(5, function()
    stop()
    Ess.Object.remove(car)
    local reverted = Ess.Camera._cine[0] == nil
    local ok = tookOver and reverted
    Ess.Log("[recipe] direct_the_camera: control handed back=" .. tostring(reverted))
    Ess.Log("[SMOKE] direct_the_camera: " .. (ok and "PASS" or "FAIL"))
end)
