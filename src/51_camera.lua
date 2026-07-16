-- Ess/51_camera.lua -- Ess.Camera: the confirmed anchor-prop / stale-axis-decay / hardpoint-follow
-- recipes from the freecam + destroyer deep dives, generalized beyond one script.
--
-- API:
--   Ess.Camera.lookAtAnchor(x, y, z, i) -> uAnchor | nil
--   Ess.Camera.staleAxisDecay(axes, timeoutMs) -> tracker  tracker:update(tInput, now)  tracker.values[name]
--   Ess.Camera.followHardpoint(uGuid, hp, i, interval) -> stop()
--   Ess.Camera.shake(i, sPreset, uSource, nAmplitude, nDuration)   Camera.Shake (per-player camera guid)
--   Ess.Camera.stopShake(i, uSource)                               for the "ConstantlyRandom" preset
--   Ess.Camera.fov(i, nAngle, nDuration) / .restoreFov(i, nDuration)   Graphics.Camera.*FovParams --
--                                          takes the player INDEX directly, NOT a camera guid (see below)
--   Ess.Camera.fade(nAmount)                                          Graphics.Effect.CameraFade (0=clear,
--                                          1=black) -- a THIRD distinct native table, see below
--   Ess.Easy.Camera.shake(i) / .fadeOut() / .fadeIn()
--   -- CINEMATIC (steals mouse control until released):
--   Ess.Camera.beginCinematic(i, blend) / .placeCamera(x,y,z,i) / .blend(i, dur) (re-arm for a smooth move) /
--     .lookAtObject(uGuid, bone, i) / .lookAtPoint(x,y,z,i) / .hold(i) / .endCinematic(i) / .panicRevert()
--   Ess.Easy.Camera.watch(uGuid, opts) -> stop()   watch a target (e.g. a heli you spawned) fly in;
--                                        default = static locked shot, opts.chase = follow from opts.angle
--   Ess.Easy.Camera.orbit(uGuid, opts) -> stop()    smoothly orbit a target (radius/height/speed/startAngle)
--
-- NOTE this is the Camera.* namespace (chase-cam/look-at/position/shake), not Graphics.Camera (LOD/FOV/
-- near-far) -- confirmed cross-namespace footgun (they share only a name), keep them separate. `fov`/
-- `restoreFov` below ARE Graphics.Camera, deliberately placed in this same file (they're still "camera
-- effects" from a modder's point of view) but calling a DIFFERENT native table with a DIFFERENT argument
-- shape (an index, not a guid) than every other function here -- don't let the shared file confuse the
-- two namespaces underneath. `fade` is yet a THIRD table (Graphics.Effect), included here for the same
-- "modder looks under Camera for any screen/camera effect" reasoning.

local Ess = _G.Ess
Ess.Camera = Ess.Camera or {}

-- Ess.Camera.lookAtAnchor(x, y, z, i) -> uAnchor | nil
-- CONFIRMED (freecam.md): Camera.SetPosition silently no-ops on this engine until an active
-- Camera.SetLookAt binding exists -- not even a hardcoded oversized test teleport moves the camera
-- without one. The fix is spawning a small anchor prop and pointing SetLookAt at it once; from then on,
-- moving/removing the anchor is the only thing needed (Ess.Camera.followHardpoint below is exactly that:
-- re-target an anchor via Object.SetPosition every tick).
--
-- CAVEAT DIRECTLY CONFIRMED: `Pg.Spawn("Verification Camera", ...)` into a LIVE, RUNNING world (not
-- paused) triggers a support/camera call-in that fails and despawns it almost immediately -- it's only
-- safe as a paused-world anchor (a freecam-style tool). ContractFramework's own zone markers hit this the
-- hard way and switched to a "TinyGeometry" anchor instead, which IS confirmed safe mid-gameplay
-- (WaveDefense.lua uses it for its drop markers and airstrike anchors, live, repeatedly). This function
-- therefore defaults to "TinyGeometry" -- do NOT switch the default to "Verification Camera" without
-- confirming you're only ever calling this from a genuinely paused world.
--
-- i = player index (0/1, default 0) -- which player's camera to bind. Returns the anchor guid so the
-- caller can Object.SetPosition it every tick to redirect the look, or Object.Remove it when done.
function Ess.Camera.lookAtAnchor(x, y, z, i)
    local cam = Ess.Player.camera(i)
    if not cam then return nil end
    local ok, uAnchor = pcall(Pg.Spawn, "TinyGeometry", x, y, z)
    if not ok or not uAnchor then return nil end
    pcall(Camera.SetLookAt, cam, uAnchor)
    return uAnchor
end

-- Ess.Camera.staleAxisDecay(axes, timeoutMs) -> tracker
-- CONFIRMED (freecam.md): the engine's ControllerInput event omits an axis field entirely once it goes
-- idle, rather than sending one final 0 -- naively "only update when present" freezes a stick at its last
-- nonzero reading forever (runaway drift after letting go). This tracks a last-updated timestamp per axis
-- name and forces it back to 0 once it's gone `timeoutMs` (default 150, the confirmed value from
-- freecam.md) without a fresh reading.
--
-- axes = a list of axis name strings (e.g. {"LeftAnalogX","LeftAnalogY","RightAnalogX","RightAnalogY"} --
-- matching whatever field names the ControllerInput tInput table actually uses for your case).
-- tracker.values[name] always reads the current (possibly decayed-to-0) value. Call tracker:update(tInput,
-- now) once per ControllerInput event, where `now` is your own running wall-clock seconds (e.g. accumulated
-- Sys.TimeStampGetElapsed dt, same as freecam.md's Freecam.now) -- this deliberately doesn't own the clock
-- itself so it composes with whatever timing a caller already has.
function Ess.Camera.staleAxisDecay(axes, timeoutMs)
    local timeout = (timeoutMs or 150) / 1000
    local tracker = { values = {}, _at = {} }
    for _, name in ipairs(axes) do
        tracker.values[name] = 0
        tracker._at[name] = 0
    end

    function tracker:update(tInput, now)
        for _, name in ipairs(axes) do
            local v = tInput and tInput[name]
            if v ~= nil then
                self.values[name] = v
                self._at[name] = now
            elseif now - self._at[name] > timeout then
                self.values[name] = 0
            end
        end
    end

    return tracker
end

-- Ess.Camera.followHardpoint(uGuid, hp, i, interval) -> stop()
-- The confirmed fallback for keeping a camera pointed at a DYNAMIC (moving) object+hardpoint, where the
-- native object+hardpoint camera form no-ops: re-read the hardpoint's world position every `interval`
-- seconds (default 0.05) and push it straight into Camera.SetPosition.
--
-- REQUIRES an active Camera.SetLookAt binding to already exist (see lookAtAnchor above) -- SetPosition
-- alone still won't visibly move the camera without one, exactly the same gotcha as everywhere else in
-- this namespace. This is a general moving-camera-target helper, NOT a fix for the separate, still-
-- unsolved vehicle GUNNING camera (Player.GetCamera while seated in a turret is confirmed to not be the
-- actual active camera object at all -- see human-skeleton-boneprobe / bone-manipulation.md's "known hard
-- limit" -- don't expect this to help with that case).
function Ess.Camera.followHardpoint(uGuid, hp, i, interval)
    interval = interval or 0.05
    local cam = Ess.Player.camera(i)
    if not cam then return function() end end
    local id = "Ess.Camera.followHardpoint:" .. tostring(uGuid) .. ":" .. tostring(hp)
    Ess.Loop.start(id, interval, function()
        local ok, x, y, z = pcall(Object.GetHardpointPosition, uGuid, hp)
        if ok and x then
            pcall(Camera.SetPosition, cam, x, y, z, true)
        end
        return true
    end)
    return function() Ess.Loop.stop(id) end
end

-- Ess.Camera.shake(i, sPreset, uSource, nAmplitude, nDuration)
-- CONFIRMED (wiki/namespaces/camera.md): Camera.Shake(uCameraGuid, sShakeName, uSourceGuid, nAmplitude,
-- nDuration), real named presets seen in the corpus: "ShakeCameraMedium" (one-shot, e.g. an explosion),
-- "ShakeCameraConstantlyRandom" (ongoing, paired with stopShake below). sPreset defaults to
-- "ShakeCameraMedium" -- the confirmed one-shot preset -- since that's the safer default for a single
-- call (an ongoing shake left unstopped would run until the player leaves the level).
function Ess.Camera.shake(i, sPreset, uSource, nAmplitude, nDuration)
    local cam = Ess.Player.camera(i)
    if not cam then return end
    pcall(Camera.Shake, cam, sPreset or "ShakeCameraMedium", uSource, nAmplitude or 6, nDuration or 5)
end

-- Ess.Camera.stopShake(i, uSource) -- the confirmed counterpart call for an ongoing
-- "ShakeCameraConstantlyRandom" shake (started via Ess.Camera.shake with that preset name).
function Ess.Camera.stopShake(i, uSource)
    local cam = Ess.Player.camera(i)
    if not cam then return end
    pcall(Camera.Shake, cam, "StopShakeCameraConstantly", uSource)
end

-- Ess.Camera.fov(i, nAngle, nDuration) / .restoreFov(i, nDuration)
-- CONFIRMED (wiki/namespaces/graphics.md): Graphics.Camera.SetFovParams(nCameraIndex, nAngle, nDuration) /
-- RestoreFovParams(nCameraIndex, nDuration) -- blends the field-of-view to a new angle over nDuration
-- seconds, then reverts. Every confirmed real call site passes a literal player-slot INDEX (0), not a
-- camera guid -- this is a genuinely different native table than top-level Camera despite the shared
-- "Camera" name (see file header). `i` here is that index directly, defaulting to 0 (the local player).
function Ess.Camera.fov(i, nAngle, nDuration)
    pcall(Graphics.Camera.SetFovParams, i or 0, nAngle, nDuration or 1)
end

function Ess.Camera.restoreFov(i, nDuration)
    pcall(Graphics.Camera.RestoreFovParams, i or 0, nDuration or 1)
end

-- Ess.Camera.fade(nAmount) -- CONFIRMED (wiki/namespaces/graphics.md): Graphics.Effect.CameraFade(nAmount),
-- a THIRD distinct native table sharing "Camera" in name/vicinity with top-level Camera and Graphics.Camera
-- (see file header) -- a full-screen fade keyed 0 (clear) to 1 (black), used at the start/end of
-- `resident/mrxactionhijack.lua`'s hijack cinematic. No duration argument exists at any confirmed call
-- site (both real uses pass a bare 0 or 1), so none is exposed here -- don't guess one.
function Ess.Camera.fade(nAmount)
    pcall(Graphics.Effect.CameraFade, nAmount)
end

-- Ess.Easy.Camera.shake(i) -- zero-config "just shake the screen" for the common explosion/impact case.
Ess.Easy = Ess.Easy or {}
Ess.Easy.Camera = Ess.Easy.Camera or {}
function Ess.Easy.Camera.shake(i)
    local char = Ess.Player.character(i)
    Ess.Camera.shake(i, "ShakeCameraMedium", char, 6, 5)
end

-- Ess.Easy.Camera.fadeOut() / .fadeIn() -- named presets for the two confirmed values, no 0/1 to remember.
function Ess.Easy.Camera.fadeOut()
    Ess.Camera.fade(1)
end

function Ess.Easy.Camera.fadeIn()
    Ess.Camera.fade(0)
end

-- ============================================================
-- CINEMATIC camera -- take over the player's camera for a scripted shot. ⚠ STEALS mouse/look control from
-- the player until endCinematic() (or panicRevert()) is called -- ALWAYS provide a way back.
--
-- CONFIRMED-live sequence (session-camera-atmosphere-findings.md, distilled from mrxactionhijack.lua):
--   Player.SetCinematicMode(p, true, true); Camera.Blend(c, dur)
--   Camera.SetPosition(c, x, y, z, true)           -- fixed vantage
--   Camera.SetLookAt(c, uGuid, sBone)              -- object+bone form AUTO-TRACKS the object as it moves
--   Camera.Hold(c, true, false)
-- release: Camera.Hold(c,false,false); Camera.StopBlending(c); Player.SetCinematicMode(p, false)
-- ============================================================
Ess.Camera._cine = Ess.Camera._cine or {}   -- active-cinematic state per player index

-- Ess.Camera.beginCinematic(i, nBlend) -> ok -- enters cinematic mode and blends in. Steals control.
function Ess.Camera.beginCinematic(i, nBlend)
    local p, c = Ess.Player.slot(i), Ess.Player.camera(i)
    if not (p and c) then return false end
    pcall(Player.SetCinematicMode, p, true, true)
    pcall(Camera.Blend, c, nBlend or 1)
    Ess.Camera._cine[i or 0] = { p = p, c = c }
    return true
end

-- Ess.Camera.placeCamera(x, y, z, i) -- put the cinematic camera at a fixed world vantage.
function Ess.Camera.placeCamera(x, y, z, i)
    local c = Ess.Player.camera(i)
    if c then pcall(Camera.SetPosition, c, x, y, z, true) end
end

-- Ess.Camera.blend(i, nDur) -- (re)arm the blend time so the NEXT placeCamera eases to its new spot over
-- nDur seconds instead of cutting. beginCinematic sets this once; call this to re-arm it for a later smooth
-- move (e.g. swing the camera out to the side, then later swing it back). This is for DISCRETE moves -- one
-- placeCamera per blend; a PER-TICK moving camera still wants blend 0 (the rubber-band rule, see below).
function Ess.Camera.blend(i, nDur)
    local c = Ess.Player.camera(i)
    if c then pcall(Camera.Blend, c, nDur or 1) end
end

-- Ess.Camera.lookAtObject(uGuid, sBone, i) -- lock the camera onto an object (optionally a specific bone/
-- hardpoint). The object form auto-tracks: as the object moves, the camera keeps pointing at it -- exactly
-- the "watch it fly in" behavior. sBone optional (nil = the object's origin).
function Ess.Camera.lookAtObject(uGuid, sBone, i)
    local c = Ess.Player.camera(i)
    if not c then return end
    if sBone then pcall(Camera.SetLookAt, c, uGuid, sBone)
    else pcall(Camera.SetLookAt, c, uGuid) end
end

-- Ess.Camera.lookAtPoint(x, y, z, i) -- lock the camera onto a fixed world point (coord form).
function Ess.Camera.lookAtPoint(x, y, z, i)
    local c = Ess.Player.camera(i)
    if c then pcall(Camera.SetLookAt, c, x, y, z, false, true) end
end

-- Ess.Camera.hold(i) -- pin the current framing.
function Ess.Camera.hold(i)
    local c = Ess.Player.camera(i)
    if c then pcall(Camera.Hold, c, true, false) end
end

-- Ess.Camera.endCinematic(i) -- release control back to the player and stop any watch/orbit follow loop.
function Ess.Camera.endCinematic(i)
    local idx = i or 0
    Ess.Loop.stop("Ess.Camera.watch:" .. idx)
    Ess.Loop.stop("Ess.Camera.orbit:" .. idx)
    local st = Ess.Camera._cine[idx]
    if not st then return end
    pcall(Camera.Hold, st.c, false, false)
    pcall(Camera.StopBlending, st.c)
    pcall(Player.SetCinematicMode, st.p, false)
    Ess.Camera._cine[idx] = nil
end

-- Ess.Camera.panicRevert() -- force-release EVERY active cinematic (the always-works escape hatch; the
-- lua-bridge still accepts commands while control is locked, so this can be fired blind to recover).
function Ess.Camera.panicRevert()
    for idx in pairs(Ess.Camera._cine) do Ess.Camera.endCinematic(idx) end
end

local function xyzOf(p) if not p then return nil end return p.x or p[1], p.y or p[2], p.z or p[3] end

-- pointAlongPath(path, frac) -> x,y,z -- position `frac` (0..1) of the way along a polyline of {x,y,z} points.
local function pointAlongPath(path, frac)
    local n = #path
    if n == 0 then return 0, 0, 0 end
    if n == 1 then return xyzOf(path[1]) end
    local s = math.max(0, math.min(frac, 1)) * (n - 1)
    local seg = math.floor(s)
    local lf = s - seg
    local ax, ay, az = xyzOf(path[seg + 1] or path[n])
    local bx, by, bz = xyzOf(path[seg + 2] or path[n])
    return ax + (bx - ax) * lf, ay + (by - ay) * lf, az + (bz - az) * lf
end

-- THE CAMERA-SMOOTHNESS RULE (confirmed live 2026-07-17 against Logan's own OrbitCam/CinCam scripts): a
-- MOVING camera must enter cinematic mode with Camera.Blend(c, 0) -- an INSTANT blend. With the default 1s
-- blend, every per-tick Camera.SetPosition restarts a 1-second interpolation and the camera rubber-bands
-- (that was the "jitter"). With Blend 0, per-tick coordinate SetPosition + a re-issued SetLookAt each tick
-- is perfectly smooth. (The object-attach camera forms are a dead end -- they don't bind; don't chase them.)
--
-- REMAINING quirk (accepted, not fixable here): chase/orbit read the TARGET's position each tick, so a
-- FAST-moving target (a heli at speed, a crate still falling) quantizes and the follow jitters slightly;
-- it smooths out as the target slows. Best practice: for a high-velocity subject use a STATIC watch point
-- (the default `watch` locked-off shot, which only PANS -- native and jitter-free), and save chase/orbit
-- for slower or stationary subjects.

-- Ess.Easy.Camera.watch(uGuid, opts) -> stop() -- take over the camera for a cinematic shot of a target
-- (e.g. a helicopter you spawned). Call the returned stop() (or Ess.Camera.endCinematic) to hand control back.
--   default  : a LOCKED-OFF tracking shot -- camera placed ONCE at a fixed vantage, native SetLookAt panning
--              to keep the target framed as it moves (nice 1s ease-in). Zero per-tick position updates.
--   chase    : opts.chase=true -- camera FOLLOWS the target from a fixed ANGLE around it (Blend 0, per-tick).
--              Give opts.angle to pick the viewpoint; a FIXED angle avoids the velocity-heading noise that
--              makes an auto-trailing cam jitter, so the user dials in a clean shot.
--
-- ⚠ Tracking a MOVING VEHICLE: point the look at whoever is RIDING it -- SetLookAt's object-track works on
-- CHARACTER bones (the pilot's "Bone_Chest"), not vehicle hardpoints. So: opts={ look=pilotGuid,
-- bone="Bone_Chest" } (pilot = Ess.Vehicle.driver(heli)).
--
-- opts: at={x,y,z} (static vantage; default just above you), height (static vantage height, 6), look (guid
--       to track; default uGuid), bone (bone on `look`), chase (bool), angle (chase viewpoint degrees, 200),
--       dist (chase distance, 16), chaseHeight (chase height above target, 6), i.
function Ess.Easy.Camera.watch(uGuid, opts)
    opts = opts or {}
    local i = opts.i
    local look = opts.look or uGuid

    if opts.chase then
        if not Ess.Camera.beginCinematic(i, 0) then return function() end end   -- Blend 0 for a moving cam
        local dist, height = opts.dist or 16, opts.chaseHeight or 6
        local ar = math.rad(opts.angle or 200)                                 -- FIXED viewpoint angle
        local ox, oz = math.sin(ar) * dist, math.cos(ar) * dist
        local id = "Ess.Camera.watch:" .. (i or 0)
        Ess.Loop.start(id, 0.033, function()
            local ok, tx, ty, tz = pcall(Object.GetPosition, uGuid)
            if ok and tx then
                Ess.Camera.placeCamera(tx + ox, ty + height, tz + oz, i)       -- fixed offset -> no heading noise
                Ess.Camera.lookAtObject(look, opts.bone, i)                    -- re-issue each tick
            end
            return true
        end)
    else
        if not Ess.Camera.beginCinematic(i, opts.blend or 1) then return function() end end
        local vx, vy, vz = xyzOf(opts.at)
        if not vx then
            local px, py, pz = Ess.Player.pose(i or 0)
            vx, vy, vz = px or 0, (py or 0) + (opts.height or 6), pz or 0
        end
        Ess.Camera.placeCamera(vx, vy, vz, i)
        Ess.Camera.lookAtObject(look, opts.bone, i)
        Ess.Camera.hold(i)
    end
    return function() Ess.Camera.endCinematic(i) end
end

-- Ess.Easy.Camera.orbit(uGuid, opts) -> stop() -- take over the camera and smoothly ORBIT a target (or the
-- player if you pass their character). Generalized from Logan's OrbitCam: Blend 0 + per-tick coordinate
-- SetPosition around a circle + a re-issued SetLookAt every tick. Great for showing off a spawned thing.
--   opts: radius (12), height (above the target, 4), speed (degrees/sec, 40), startAngle (deg, 0),
--         look (guid to look at; default uGuid), bone (bone on `look`), i.
function Ess.Easy.Camera.orbit(uGuid, opts)
    opts = opts or {}
    local i = opts.i
    local look = opts.look or uGuid
    if not Ess.Camera.beginCinematic(i, 0) then return function() end end       -- Blend 0 for a moving cam
    local radius, height = opts.radius or 12, opts.height or 4
    local speed = math.rad(opts.speed or 40)
    local start = math.rad(opts.startAngle or 0)
    local id = "Ess.Camera.orbit:" .. (i or 0)
    local t0 = Ess.Time.stamp()
    Ess.Loop.start(id, 0.033, function()
        local ok, tx, ty, tz = pcall(Object.GetPosition, uGuid)
        if ok and tx then
            local a = start + Ess.Time.elapsed(t0) * speed
            Ess.Camera.placeCamera(tx + math.sin(a) * radius, ty + height, tz + math.cos(a) * radius, i)
            Ess.Camera.lookAtObject(look, opts.bone, i)
        end
        return true
    end)
    return function() Ess.Camera.endCinematic(i) end
end
