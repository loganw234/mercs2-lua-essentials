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
--
-- NOTE this is the Camera.* namespace (chase-cam/look-at/position/shake), not Graphics.Camera (LOD/FOV/
-- near-far) -- confirmed cross-namespace footgun (they share only a name), keep them separate. `fov`/
-- `restoreFov` below ARE Graphics.Camera, deliberately placed in this same file (they're still "camera
-- effects" from a modder's point of view) but calling a DIFFERENT native table with a DIFFERENT argument
-- shape (an index, not a guid) than every other function here -- don't let the shared file confuse the
-- two namespaces underneath.

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

-- Ess.Easy.Camera.shake(i) -- zero-config "just shake the screen" for the common explosion/impact case.
Ess.Easy = Ess.Easy or {}
Ess.Easy.Camera = Ess.Easy.Camera or {}
function Ess.Easy.Camera.shake(i)
    local char = Ess.Player.character(i)
    Ess.Camera.shake(i, "ShakeCameraMedium", char, 6, 5)
end
