local KEYVAL = "f6"   -- toggle key; also add "VehicleInspector.lua=f6" under [OnKey] in lua_loader.ini

-- =====================================================================
-- VehicleInspector - a WAILA-style "what vehicle am I in" tool.  (Essentials demo)
--
-- HOW IT WORKS (and why it's a poll, not a hook)
--   The player's "get in nearest seat" action is bound in NATIVE code - there's no player-facing Lua
--   function to override, and Event.ObjectInSeat needs a specific vehicle guid + seat known ahead of time.
--   So we do what the game's own resident code does: poll "what vehicle is the player in" on a light
--   heartbeat and watch for the nil -> guid transition. That transition IS "just entered".
--
--   On ENTER: dumps the vehicle's guid + all readable details to the log, pops a toast, shows a live panel.
--   While IN: the panel refreshes health each tick.
--   On EXIT:  logs it and hides the panel.
--
-- A compact showcase of Ess.Player / Ess.Object / Ess.Vehicle / Ess.UI / Ess.Loop working together.
--
-- DEPLOY:  Ess (dist/Ess.lua) as an OnLoad script; this at scripts/OnKey/VehicleInspector.lua with
--          [OnKey] VehicleInspector.lua=f6 . Ess.UI is native, so the HUD panel always works when Ess
--          is loaded (no separate uilib needed).
-- =====================================================================

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("VehicleInspector: load Ess (dist/Ess.lua) first") end return end

_G.VehInspect = _G.VehInspect or {}
local V = _G.VehInspect
V.active = V.active or false

local LOOP_ID = "VehInspector.tick"
local TICK = 0.1   -- 10 Hz: instant enough for enter/exit, negligible cost

-- values-or-nil helper, routed through Ess.Safe.quiet (guarded, no log spam) -- only needed for the few
-- fields Ess has no wrapper for; the Ess.* getters below are already pcall-guarded internally.
local function safe(fn, ...) local ok, a, b, c = Ess.Safe.quiet(fn, ...); if ok then return a, b, c end end

-- Gather everything readable about a vehicle guid (nil-safe throughout).
local function details(veh, char)
    local d = {}
    d.guid      = Ess.Name(veh) or tostring(veh)
    d.name      = safe(Object.GetName, veh)            -- no Ess wrapper for the raw internal name
    d.localized = Ess.Object.displayName(veh)
    d.hp        = Ess.Object.health(veh)
    d.maxhp     = Ess.Object.maxHealth(veh)
    d.px, d.py, d.pz = Ess.Object.pos(veh)
    d.yaw       = Ess.Object.yaw(veh)
    d.mass      = safe(Object.GetMass, veh)            -- no Ess wrapper
    d.phys      = safe(Object.GetPhysicsType, veh)     -- no Ess wrapper
    local drv   = Ess.Vehicle.driver(veh)
    d.isDriver  = (drv ~= nil and drv == char)
    d.seat      = Ess.Vehicle.seatOf(char)
    return d
end

local function dumpLog(d)
    Loader.Printf("=================== VEHICLE ENTERED ===================")
    Loader.Printf("  guid       = " .. tostring(d.guid))
    Loader.Printf("  name       = " .. tostring(d.name))
    Loader.Printf("  localized  = " .. tostring(d.localized))
    Loader.Printf(string.format("  health     = %s / %s", tostring(d.hp), tostring(d.maxhp)))
    Loader.Printf(string.format("  position   = %.2f, %.2f, %.2f   yaw = %.3f",
        d.px or 0, d.py or 0, d.pz or 0, d.yaw or 0))
    Loader.Printf("  seat       = " .. tostring(d.seat) .. "   role = " .. (d.isDriver and "DRIVER" or "PASSENGER"))
    Loader.Printf("  mass       = " .. tostring(d.mass) .. "   physics = " .. tostring(d.phys))
    Loader.Printf("======================================================")
end

-- On-screen readout (Ess.UI is native, so it's always available when Ess is loaded).
local function panelShow(d)
    if not V.panel then V.panel = Ess.UI.Panel{ x = 8, y = 150, w = 300, title = "IN VEHICLE" } end
    V.panel:title(tostring(d.localized or d.name or "VEHICLE"))
    V.panel:line(0, "name : " .. tostring(d.name))
    V.panel:line(1, "role : " .. (d.isDriver and "DRIVER" or "PASSENGER") .. "   seat: " .. tostring(d.seat))
    V.panel:line(2, string.format("hp   : %s / %s", tostring(d.hp), tostring(d.maxhp)))
    V.panel:line(3, "guid : " .. tostring(d.guid))
    V.panel:show()
end
local function panelLive(veh)   -- cheap live refresh: only the two values that change while seated
    if V.panel then V.panel:line(2, string.format("hp   : %s / %s",
        tostring(Ess.Object.health(veh)), tostring(Ess.Object.maxHealth(veh)))) end
end
local function panelHide() if V.panel then V.panel:hide() end end

-- Heartbeat on the shared reload-safe loop. Ess.Loop's own generation guard replaces the hand-rolled V.gen
-- dance: start() with the same id supersedes any prior loop, stop() ends it cleanly, and it's flushed on a
-- world reload -- so no manual re-arm and no leak on repeated F6 presses.
local function startTick()
    Ess.Loop.start(LOOP_ID, TICK, function()
        if not V.active then return false end
        local char = Ess.Player.character(0)
        local veh  = char and Ess.Object.vehicleOf(char) or nil
        if veh ~= V.cur then                       -- state changed since last tick
            if veh then
                local d = details(veh, char)
                dumpLog(d)
                Ess.UI.Toast("Entered: " .. tostring(d.localized or d.name or "vehicle"))
                panelShow(d)
            else
                Loader.Printf("VehicleInspector: exited vehicle")
                Ess.UI.Toast("Exited vehicle")
                panelHide()
            end
            V.cur = veh
        elseif veh then
            panelLive(veh)                          -- still inside: refresh live stats
        end
        return true
    end)
end

-- Toggle (this file re-runs on each F6 press).
V.active = not V.active
if V.active then
    V.cur = nil
    startTick()
    Loader.Printf("VehicleInspector: ON - enter a vehicle to dump it (guid + details to log). F6 to stop.")
else
    Ess.Loop.stop(LOOP_ID)
    panelHide()
    Loader.Printf("VehicleInspector: OFF")
end
