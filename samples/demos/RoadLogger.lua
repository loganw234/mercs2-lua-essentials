local KEYVAL = "free"   -- toggle key -- F1-F12 are the suggested keys for this folder's other demos, so
                        -- bind this to whatever's free for you

-- RoadLogger.lua -- summon an INVINCIBLE Veyron and auto-log your position every 0.25s as you drive, to
-- build a dense road map with real height (y) data. Press your bound key to START (summons the car in
-- front + hops you in, or reuses the car you're already in); press it again to STOP and print how many
-- points you got. The Veyron is a low car, so its logged y sits close to the road surface -- a good
-- height reference.
--
-- Read the trail back with:  grep "\[ROAD\]" "<game>/scripts/lua_loader_printf.log"
--   -> lines like:  [ROAD] 142  x=2739.70  y=-13.80  z=-786.10  yaw=92.8
-- DEPLOY: this is reference code, not installed by Ess. Copy it into scripts/OnKey/ yourself and bind it
-- to any free key, e.g.  RoadLogger.lua=Insert  under [OnKey].

local Ess = _G.Ess
if not (Ess and Ess.Easy and Ess.Easy.Vehicle and Ess.Loop) then
    if Loader and Loader.Printf then Loader.Printf("[roadlog] load the Essentials framework (dist/Ess.lua) first") end
    return
end

local LOOP_ID  = "RoadLogger"
local INTERVAL = 0.25
local MIN_MOVE = 1.0   -- only log once you've moved >1 unit; skips parked-idle spam, never skips while
                       -- driving (even crawling is >1 unit per 0.25s). Set to 0 for a strict every-tick log.

_G.RoadLogger = _G.RoadLogger or { on = false, veh = nil, n = 0, lx = nil, lz = nil }
local S = _G.RoadLogger

-- ---- STOP (second press) ----------------------------------------------
if S.on then
    S.on = false
    Ess.Loop.stop(LOOP_ID)
    Ess.Log(string.format("[roadlog] STOPPED -- logged %d point(s). grep \"[ROAD]\" the log to pull them.", S.n))
    return
end

-- ---- START (first press) ----------------------------------------------
local char = Ess.Player.character(0)
if not char then Ess.Log("[roadlog] no player character (are you in the world?)"); return end

-- reuse the car you're already driving, otherwise summon a Veyron in front and get in
local veh = Ess.Object.vehicleOf(char)
if not (veh and Ess.Object.valid(veh)) then veh = Ess.Easy.Vehicle.summon("Veyron") end
if not veh then Ess.Log("[roadlog] couldn't get or summon a vehicle"); return end
Ess.Object.setInvincible(veh, true, "RoadLogger")

S.on, S.veh, S.n, S.lx, S.lz = true, veh, 0, nil, nil
Ess.Log("[roadlog] STARTED -- logging every " .. INTERVAL .. "s in an invincible Veyron (press your bound key again to stop)")

Ess.Loop.start(LOOP_ID, INTERVAL, function()
    if not S.on then return false end
    -- log the car's position; fall back to the car you're currently in, then to on-foot if you hopped out
    local g = S.veh
    if not (g and Ess.Object.valid(g)) then g = Ess.Object.vehicleOf(Ess.Player.character(0)); S.veh = g end
    local x, y, z, yaw
    if g and Ess.Object.valid(g) then
        local ok, px, py, pz = pcall(Object.GetPosition, g)
        if ok and px then x, y, z = px, py, pz; local oky, yv = pcall(Object.GetYaw, g); yaw = (oky and yv) or 0 end
    end
    if not x then x, y, z, yaw = Ess.Player.pose(0) end          -- on-foot fallback
    if not x then return true end
    if S.lx and ((x - S.lx) * (x - S.lx) + (z - S.lz) * (z - S.lz)) < (MIN_MOVE * MIN_MOVE) then
        return true                                              -- hasn't moved far enough since the last point
    end
    S.n = S.n + 1
    S.lx, S.lz = x, z
    Ess.Log(string.format("[ROAD] %d  x=%.2f  y=%.2f  z=%.2f  yaw=%.1f", S.n, x, y, z, yaw or 0))
    return true
end)
