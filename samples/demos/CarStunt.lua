local KEYVAL = "f10"   -- must be in the first 10 lines (add "CarStunt.lua=f10" under [OnKey])

-- CarStunt.lua -- get in a car, rocket down the runway, launch into the air and pull a couple of aerial
-- tricks -- and watch YOURSELF fly: once you're airborne the camera swings out to the side, then smoothly
-- swings back to you as you come down. Showcases the Ess.Impulse feature set (speedBoost / push / spin)
-- folded together with Ess.Camera's cinematic swings. Press F10.
--
-- NOTE the tricks are deliberately GENTLE -- a vehicle spun too hard can crash the physics engine, so this
-- does a lazy roll + a nose-up flip, not a blender. Crank the spin strengths if you're feeling brave.
--
-- DEPLOY: Ess (dist/Ess.lua) as an OnLoad script; this under scripts/OnKey/ with  CarStunt.lua=f10.

local Ess = _G.Ess
if not (Ess and Ess.Impulse and Ess.Camera and Ess.Player) then
    if Loader and Loader.Printf then Loader.Printf("[carstunt] load the Essentials framework (dist/Ess.lua) first") end
    return
end

local px, py, pz, yaw, char = Ess.Player.pose(0)
if not char then Ess.Log("[carstunt] no player character") return end

-- spawn the car ahead + facing your way, make it invincible (so a hard landing can't wreck it or you), and
-- drop you in the driver seat.
local car = Ess.Object.spawnAhead("Veyron", 6)
if not car then Ess.Log("[carstunt] couldn't spawn the car") return end
Ess.Object.setInvincible(car, true, "CarStunt")
Ess.Vehicle.enterBestSeat(char, car)

local function at(t, fn) Ess.Easy.Triggers.after(t, function() pcall(fn) end) end

-- ROCKET down the runway (forward, mass-scaled)
at(0.4, function() Ess.Easy.Impulse.speedBoost(car, 10) end)
at(0.9, function() Ess.Easy.Impulse.speedBoost(car, 13) end)
at(1.4, function() Ess.Easy.Impulse.speedBoost(car, 15) end)

-- LAUNCH into the air (up-heavy, a little forward)
at(1.9, function() Ess.Impulse.push(car, { forward = 6, up = 18 }) end)

-- AIRBORNE: swing the camera out to the side and lock onto the car so you watch yourself fly. The 1s blend
-- makes it a smooth swing, not a cut.
at(2.15, function()
    local cx, cy, cz = Ess.Object.pos(car)
    -- 90 deg off your facing = straight out to the side (via Ess.Math, not a hand-rolled sin/cos)
    local sx, sz = Ess.Math.pointAhead(cx or px, cz or pz, (yaw or 0) + 90, 16)
    Ess.Camera.beginCinematic(0, 1)
    Ess.Camera.placeCamera(sx, (cy or py) + 7, sz, 0)
    Ess.Camera.lookAtObject(car, nil, 0)                        -- tracks the car as it flies + tumbles
    Ess.Camera.hold(0)
end)

-- a couple of GENTLE aerial tricks (few + low strength on purpose)
at(2.5, function() Ess.Impulse.spin(car, { up = 6, at = { 2, 0, 0 } }) end)             -- a lazy barrel roll
at(3.2, function() Ess.Impulse.spin(car, { forward = 7, at = { 0, -0.3, -1.4 } }) end)  -- a nose-up flip

-- the stunt's over -- swing the camera smoothly back to you, then hand control back.
at(4.7, function()
    local cx, cy, cz = Ess.Object.pos(car)
    local bx, bz = Ess.Math.pointAhead(cx or px, cz or pz, yaw, -7)   -- just behind the car
    Ess.Camera.blend(0, 1)                                            -- re-arm the blend = a smooth swing back
    Ess.Camera.placeCamera(bx, (cy or py) + 4, bz, 0)
    Ess.Camera.lookAtObject(char, nil, 0)
end)
at(5.9, function()
    Ess.Camera.endCinematic(0)                     -- release -- the camera is already near your normal view
    Ess.Object.heal(char)                          -- top you off, just in case
    Ess.Log("[carstunt] stuck the landing -- you've still got the car")
end)

Ess.Log("[carstunt] buckle up -- launching! (you're in the driver seat)")
