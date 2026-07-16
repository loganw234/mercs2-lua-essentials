-- Ess/31_mark_raw.lua -- Ess.Raw.Mark: the three marking surfaces as fully independent calls.
-- ContractFramework.lua's private `mark()` decomposed into its three constituent native calls.
--
-- API:
--   Ess.Raw.Mark.radar(uGuid, tex, rgb) -> sName|nil     / .removeRadar(sName)
--   Ess.Raw.Mark.pda(uGuid, tex) -> sName|nil             / .removePda(sName)
--   Ess.Raw.Mark.world(uGuid, tex, rgb) -> handle|nil     / .removeWorld(handle)
--   Ess.Raw.Mark.worldDisc(uGuid, radius, rgb, alpha) -> handle|nil   (a ground ring, not a floating icon)
--   Ess.Raw.Mark.pulse(uGuid, rgb) / .haltPulse(uGuid)   flash an EXISTING marker in a color -- takes the
--                                                         object uGuid directly, not a marker handle
--   Ess.Raw.Mark.showPlayerMarkers(bOn)                   Gui.EnablePlayerMarkers -- a GLOBAL toggle, not
--                                                          per-guid like everything else in this file

local Ess = _G.Ess
Ess.Raw = Ess.Raw or {}
Ess.Raw.Mark = Ess.Raw.Mark or {}

local function guidName(uGuid)
    local sName = tostring(uGuid)
    local ok, s = pcall(Sys.GuidToString, uGuid)
    if ok and s then sName = s end
    return sName
end
local function rgbOf(rgb)
    return (rgb and rgb[1]) or 255, (rgb and rgb[2]) or 200, (rgb and rgb[3]) or 0
end

-- Ess.Raw.Mark.radar(uGuid, tex, rgb) -> sName|nil -- round radar objective. Keyed by the guid string
-- (sName), since RemoveObjective removes by name, not handle.
function Ess.Raw.Mark.radar(uGuid, tex, rgb)
    local sName = guidName(uGuid)
    local r, g, b = rgbOf(rgb)
    local ok = pcall(function()
        Hud.Radar:AddObjective({ sName = sName, uGuid = uGuid, sTexture = tex or "objective_action",
            nR = r, nG = g, nB = b, nWidth = 10.666667, nHeight = 10.666667, nSortOrder = 5 })
    end)
    return ok and sName or nil
end
function Ess.Raw.Mark.removeRadar(sName)
    if sName then pcall(function() Hud.Radar:RemoveObjective({ sName = sName }) end) end
end

-- Ess.Raw.Mark.pda(uGuid, tex) -> sName|nil -- PDA map blip, also keyed by name.
function Ess.Raw.Mark.pda(uGuid, tex)
    local sName = guidName(uGuid)
    local ok = pcall(function()
        Pda.Map:AddBlip({ sName = sName, uGuid = uGuid, sTexture = tex or "icon_yellow_mc", nSortOrder = 2 })
    end)
    return ok and sName or nil
end
function Ess.Raw.Mark.removePda(sName)
    if sName then pcall(function() Pda.Map:RemoveBlip({ sName = sName }) end) end
end

-- Ess.Raw.Mark.world(uGuid, tex, rgb) -> handle|nil -- the floating in-world icon. Returns a real
-- Marker.AddBlip handle (NOT a name) -- RemoveWorld/Marker.Remove takes the handle, not sName.
function Ess.Raw.Mark.world(uGuid, tex, rgb)
    local r, g, b = rgbOf(rgb)
    local ok, m = pcall(Marker.AddBlip, uGuid, tex or "HUD_objective_action", 32, r, g, b, 255, 2, 5, 175)
    if ok then return m end
    return nil
end
function Ess.Raw.Mark.removeWorld(handle)
    if handle then pcall(Marker.Remove, handle) end
end

-- Ess.Raw.Mark.worldDisc(uGuid, radius, rgb, alpha) -> handle|nil -- a ground ring (Marker.AddDisc), the
-- "go here" zone marker, distinct from a floating icon.
function Ess.Raw.Mark.worldDisc(uGuid, radius, rgb, alpha)
    local r, g, b = rgbOf(rgb)
    local ok, m = pcall(Marker.AddDisc, uGuid, radius or 15, r, g, b, alpha or 0.15)
    if ok then return m end
    return nil
end

-- Ess.Raw.Mark.pulse(uGuid, rgb) / .haltPulse(uGuid) -- flashes/pulses the object's EXISTING marker in a
-- color, a "draw attention to this" effect distinct from placing a new static marker. CONFIRMED real
-- start/stop pair (mrxfactionmanager.lua): both take the object's own uGuid directly, NOT a marker
-- handle, unlike every other function in this file.
function Ess.Raw.Mark.pulse(uGuid, rgb)
    local r, g, b = rgbOf(rgb)
    pcall(Marker.Pulse, uGuid, r, g, b)
end
function Ess.Raw.Mark.haltPulse(uGuid)
    pcall(Marker.HaltPulse, uGuid)
end

-- Ess.Raw.Mark.showPlayerMarkers(bOn) -- CONFIRMED (mrxbriefing.lua): Gui.EnablePlayerMarkers(bEnabled),
-- a GLOBAL on/off toggle (not keyed to a guid like every other function in this file) for whether OTHER
-- players' HUD markers render at all. Real confirmed use: hide during a cutscene/briefing, restore after --
-- the same "temporarily quiet the HUD for a scripted moment" need Ess.Camera.fade/Ess.Hud already serve.
function Ess.Raw.Mark.showPlayerMarkers(bOn)
    pcall(Gui.EnablePlayerMarkers, bOn and true or false)
end
