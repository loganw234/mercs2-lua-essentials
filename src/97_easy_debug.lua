-- Ess/97_easy_debug.lua -- Ess.Easy.Debug: a live on-screen DEV OVERLAY for mod authors. Toggle it on and a
-- small panel follows you around showing the things you constantly need while building a mod and otherwise
-- have to Loader.Printf one at a time:
--   * your exact world position + yaw   (the #1 thing you want -- to paste into a spawn/teleport call)
--   * what you're aiming at             (name, faction, distance -- read an object's identity without a hook)
--   * on foot / what vehicle you're in
--   * your health
--   * how many humans / vehicles are nearby
--
-- Pure composition of already-live-verified Ess pieces -- Ess.UI.Panel (the widget) + Ess.Loop (the refresh)
-- + Ess.Player.pose/targetUnderReticle/inVehicle + Ess.Probe.nearby + Ess.Object -- no new engine calls.
--
-- Deliberately NOT shown: a "FPS" number. This overlay refreshes on a fixed-interval Ess.Loop (a timer, not
-- a per-render-frame hook), so any framerate it computed would be the TICK rate, not the real framerate --
-- a confidently-wrong number. Everything here is something the engine can actually report.
--
-- API:
--   Ess.Easy.Debug.overlay(opts)   toggle the overlay on/off (call again to hide). opts (all optional):
--                                    x, y (screen pos), interval (refresh s, default 0.2), radius (nearby
--                                    scan, default 40), i (player index). Returns the panel, or nil when
--                                    toggled off.
--   Ess.Easy.Debug.hide()          force it off.
--   Ess.Easy.Debug.isOn() -> bool

local Ess = _G.Ess
Ess.Easy = Ess.Easy or {}
Ess.Easy.Debug = Ess.Easy.Debug or {}

-- file-local session state: persists across OnKey re-runs (which don't re-run this OnLoad chunk), so the
-- toggle is a real toggle; a world reload re-runs the chunk and resets it (the old panel/loop are dead by
-- then anyway -- same reload-safe reasoning as Ess.Loop's registry).
local S = { on = false, panel = nil, i = 0 }
local LOOP_ID = "Ess.Easy.Debug.overlay"

local function fmtCoord(x, y, z)
    if not x then return "(?)" end
    return string.format("(%.1f, %.1f, %.1f)", x, y, z)
end

-- a short one-line identity for whatever's under the reticle: "Name  FAC  d=12.3", or nil if nothing.
local function aimLine(i, px, py, pz)
    local g, hx, hy, hz = Ess.Player.targetUnderReticle(i)
    if not g then return "aim: (nothing)" end
    local name = Ess.Name(g) or "?"
    local fac = Ess.Probe.getFaction(g) or "-"
    local d = px and Ess.Object.distance(g, px, py, pz)
    if d then return string.format("aim: %s  %s  d=%.1f", name, fac, d) end
    return "aim: " .. name .. "  " .. fac
end

local function vehLine(i)
    local veh = Ess.Player.inVehicle(i)
    if not veh then return "on foot" end
    return "vehicle: " .. (Ess.Name(veh) or "?")
end

local function healthLine(i)
    local char = Ess.Player.character(i)
    if not char then return "health: -" end
    local hp = Ess.Object.health(char)
    local okm, mx = pcall(Object.GetMaxHealth, char)
    if hp and okm and mx then return string.format("health: %.0f / %.0f", hp, mx) end
    if hp then return "health: " .. tostring(hp) end
    return "health: ?"
end

local function nearbyLine(px, py, pz, r)
    if not px then return "nearby: -" end
    local hum = #Ess.Probe.nearby(px, py, pz, r, "humans")     -- both exclude the player by default
    local veh = #Ess.Probe.nearby(px, py, pz, r, "vehicles")
    return string.format("near(%d): %d hum  %d veh", r, hum, veh)
end

local function refresh(i, r)
    local p = S.panel
    if not p then return end
    local px, py, pz, yaw = Ess.Player.pose(i)
    p:line(0, "pos: " .. fmtCoord(px, py, pz) .. (px and string.format("  yaw %.0f", yaw or 0) or ""))
    p:line(1, aimLine(i, px, py, pz))
    p:line(2, vehLine(i) .. "   " .. healthLine(i))
    -- the nearby line is the one expensive part (two native FastCollect passes over the radius); the rest is
    -- cheap. Gate it to ~1x/sec and cache the result so the panel's fast pos/aim refresh doesn't run a world
    -- scan on every tick -- a dev overlay should stay light enough not to perturb what you're measuring.
    if S.nearbyReady and S.nearbyReady() then S.nearbyCache = nearbyLine(px, py, pz, r) end
    p:line(3, S.nearbyCache or "near: ...")
end

local function teardown()
    Ess.Loop.stop(LOOP_ID)
    if S.panel then pcall(function() S.panel:destroy() end); S.panel = nil end
    S.on = false
end

function Ess.Easy.Debug.overlay(opts)
    if S.on then teardown(); return nil end      -- toggle off
    opts = opts or {}
    local i = tonumber(opts.i) or 0
    local r = tonumber(opts.radius) or 40
    local interval = tonumber(opts.interval) or 0.2
    S.i = i
    S.panel = Ess.UI.Panel{ x = opts.x or 20, y = opts.y or 40, w = opts.w or 360, title = "Ess Debug" }
    S.nearbyReady = Ess.Time.cooldown(1)          -- gate the nearby world-scan to ~1x/sec (its first call is
    S.nearbyCache = nil                           -- always ready, so the immediate paint below still scans)
    S.on = true
    refresh(i, r)                                 -- paint once immediately, don't wait a tick
    Ess.Loop.start(LOOP_ID, interval, function()
        if not S.on or not S.panel then return false end
        refresh(i, r)
        return true
    end)
    return S.panel
end

function Ess.Easy.Debug.hide() if S.on then teardown() end end
function Ess.Easy.Debug.isOn() return S.on end
