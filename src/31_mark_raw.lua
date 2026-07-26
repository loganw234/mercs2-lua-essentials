-- Ess/31_mark_raw.lua -- Ess.Raw.Mark: the three marking surfaces as fully independent calls.
-- ContractFramework.lua's private `mark()` decomposed into its three constituent native calls.
--
-- API:
--   Ess.Raw.Mark.radar(uGuid, tex, rgb) -> sName|nil     / .removeRadar(sName)
--   Ess.Raw.Mark.radarAt(sName, x, y, z, tex, rgb)        a radar dot at a POINT, with no object behind it
--   Ess.Raw.Mark.pulseRadar / .blinkRadar / .sonarRadar / .stopRadarAnimation   effects on an existing dot
--   Ess.Raw.Mark.radarRegion(uGuid, rgb, a, bInvert) / .removeRadarRegion(uGuid)   shade a zone boundary
--   Ess.Raw.Mark.pda(uGuid, tex, sLabel) -> sName|nil      / .removePda(sName)
--   Ess.Raw.Mark.world(uGuid, tex, rgb, size, dist) -> handle|nil   / .removeWorld(handle)
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
    local ok, s = Ess.Safe.quiet(Sys.GuidToString, uGuid)
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

-- Ess.Raw.Mark.pda(uGuid, tex, sLabel) -> sName|nil -- PDA map blip, also keyed by name.
--
-- sLabel is not cosmetic padding: a blip with NO label displays its TEXTURE NAME on the map. The PDA's
-- render path builds a positional array whose label slot is `tBlip.sLabel or tMissionData.sDefaultBlipLabel`
-- (mrxguipda.lua:600), and with no label and no owning mission that slot goes nil and the movie shows the
-- texture instead. Confirmed live 2026-07-26 -- this is exactly why every Ess.Mark blip has always read
-- "icon_yellow_mc" on the map. Defaulting to the guid string is not pretty, but it is at least identifying,
-- and Ess.Mark passes opts.label through so a caller can do better.
function Ess.Raw.Mark.pda(uGuid, tex, sLabel)
    local sName = guidName(uGuid)
    local ok = pcall(function()
        Pda.Map:AddBlip({ sName = sName, uGuid = uGuid, sTexture = tex or "icon_yellow_mc",
                          sLabel = sLabel or sName, nSortOrder = 2 })
    end)
    return ok and sName or nil
end
function Ess.Raw.Mark.removePda(sName)
    if sName then pcall(function() Pda.Map:RemoveBlip({ sName = sName }) end) end
end

-- ---- radar: the rest of Hud.Radar -----------------------------------------------------------------------
-- Everything below drives an EXISTING radar objective by the sName that .radar() returned. None of it has an
-- Ess.Mark equivalent, because these are effects applied to a marker rather than ways of placing one.

-- Ess.Raw.Mark.radarAt(sName, x, y, z, tex, rgb) -> sName|nil -- a radar objective at a FIXED WORLD POINT
-- with no object behind it. Hud.Radar:AddObjective takes nX/nY/nZ as well as uGuid, and .radar() above only
-- ever passes the guid, so this whole capability was unreachable: marking a place rather than a thing.
-- Note the engine's own odd default of nY = 2 when omitted (mrxguibase.lua:1485), not 0.
function Ess.Raw.Mark.radarAt(sName, x, y, z, tex, rgb)
    if type(sName) ~= "string" or sName == "" then return nil end
    local r, g, b = rgbOf(rgb)
    local ok = pcall(function()
        Hud.Radar:AddObjective({ sName = sName, nX = x, nY = y, nZ = z,
            sTexture = tex or "objective_action", nR = r, nG = g, nB = b,
            nWidth = 10.666667, nHeight = 10.666667, nSortOrder = 5 })
    end)
    return ok and sName or nil
end

-- Ess.Raw.Mark.pulseRadar(sName, tOpts) -- pulse an existing radar objective's SIZE. Distinct from
-- Ess.Raw.Mark.pulse, which colours the in-world marker: this one throbs the minimap dot. Engine defaults
-- (applied by the wrapper, reproduced here so the shape is visible): duration 2, min 2x2, max 6x6, speed 8.
-- tOpts.bOneWay grows once instead of oscillating.
function Ess.Raw.Mark.pulseRadar(sName, tOpts)
    if type(sName) ~= "string" then return false end
    local o = type(tOpts) == "table" and tOpts or {}
    return pcall(function()
        Hud.Radar:AnimateObjectiveSize({ sName = sName, nDuration = tonumber(o.nDuration),
            nMinWidth = tonumber(o.nMin), nMinHeight = tonumber(o.nMin),
            nMaxWidth = tonumber(o.nMax), nMaxHeight = tonumber(o.nMax),
            nSpeedWidth = tonumber(o.nSpeed), nSpeedHeight = tonumber(o.nSpeed),
            bOneWay = o.bOneWay and true or nil })
    end)
end

-- Ess.Raw.Mark.blinkRadar(sName, tOpts) -- fade an existing radar objective in and out. Engine defaults:
-- duration 1, alpha 0..1, speed 0.5.
function Ess.Raw.Mark.blinkRadar(sName, tOpts)
    if type(sName) ~= "string" then return false end
    local o = type(tOpts) == "table" and tOpts or {}
    return pcall(function()
        Hud.Radar:AnimateObjectiveAlpha({ sName = sName, nDuration = tonumber(o.nDuration),
            nMinAlpha = tonumber(o.nMinAlpha), nMaxAlpha = tonumber(o.nMaxAlpha),
            nSpeed = tonumber(o.nSpeed), bOneWay = o.bOneWay and true or nil })
    end)
end

-- Ess.Raw.Mark.sonarRadar(sName, tOpts) -- the expanding-ring sonar sweep, the most elaborate radar effect
-- the game has and the one with a full 14-field call site to copy (mrxfactionmanager.lua's "Reporter"
-- pulse). Engine defaults: 4 total blips, 1 visible, width 2..8, delay 1, alpha 0..1, grow speed 5.
-- tOpts.sTexture defaults to the game's own "temp_radar_pulse". nDuration 0 means indefinite at that site.
function Ess.Raw.Mark.sonarRadar(sName, tOpts)
    if type(sName) ~= "string" then return false end
    local o = type(tOpts) == "table" and tOpts or {}
    local r, g, b = rgbOf(o.rgb)
    return pcall(function()
        Hud.Radar:AnimateObjectiveSonar({ sName = sName, nDuration = tonumber(o.nDuration) or 0,
            sTexture = o.sTexture or "temp_radar_pulse",
            nTotalBlips = tonumber(o.nTotalBlips), nVisibleBlips = tonumber(o.nVisibleBlips),
            nMinWidth = tonumber(o.nMinWidth), nMaxWidth = tonumber(o.nMaxWidth),
            nBlipDelay = tonumber(o.nBlipDelay), nAlphaAtMin = tonumber(o.nAlphaAtMin),
            nAlphaAtMax = tonumber(o.nAlphaAtMax), nGrowSpeed = tonumber(o.nGrowSpeed),
            nRed = r, nGreen = g, nBlue = b })
    end)
end

-- Ess.Raw.Mark.stopRadarAnimation(sName [,sType]) -- stop animating. sType defaults to "all", which is the
-- widget's own default (mrxguibase.lua:1508) and the ONLY value confirmed: the per-animation type names are
-- decided below the script layer, inside _GuiInternal.MinimapUnanimateObjective, so nothing readable says
-- whether "size"/"alpha"/"sonar" are accepted. Use "all" unless you have tested otherwise.
function Ess.Raw.Mark.stopRadarAnimation(sName, sType)
    if type(sName) ~= "string" then return false end
    return pcall(function()
        Hud.Radar:UnanimateObjective({ sName = sName, sType = sType or "all" })
    end)
end

-- Ess.Raw.Mark.radarRegion(uGuid, rgb, nAlpha, bInvert) / .removeRadarRegion(uGuid) -- shade a line region
-- on the minimap, the effect the game uses for faction-zone boundaries. Note this targets the "MinimapFlash"
-- widget, NOT "Minimap" -- a different widget from every other function here. The corpus's two call sites
-- both use black at alpha 160, and bInvert shades OUTSIDE the region instead of inside.
function Ess.Raw.Mark.radarRegion(uGuid, rgb, nAlpha, bInvert)
    local r, g, b = (rgb and rgb[1]) or 0, (rgb and rgb[2]) or 0, (rgb and rgb[3]) or 0
    return pcall(function()
        Hud.Radar:AddLineRegion({ uGuid = uGuid, nRed = r, nGreen = g, nBlue = b,
                                  nAlpha = tonumber(nAlpha) or 160, bInvert = bInvert and true or false })
    end)
end
function Ess.Raw.Mark.removeRadarRegion(uGuid)
    return pcall(function() Hud.Radar:RemoveLineRegion({ uGuid = uGuid }) end)
end

-- Ess.Raw.Mark.world(uGuid, tex, rgb, size, dist) -> handle|nil -- the floating in-world icon. Returns a
-- real Marker.AddBlip handle (NOT a name) -- RemoveWorld/Marker.Remove takes the handle, not sName.
-- `size` is the on-screen icon size (Marker.AddBlip's 3rd arg, default 32) and `dist` is the last arg
-- (default 175) that shipped call sites vary between ~175 and ~220 -- both optional and exposed so a
-- consumer can match its own visual style instead of being locked to one hardcoded look (the two values
-- MissionForge, ForgeCam and the contract markers each picked differently before this was configurable).
function Ess.Raw.Mark.world(uGuid, tex, rgb, size, dist)
    local r, g, b = rgbOf(rgb)
    local ok, m = Ess.Safe.quiet(Marker.AddBlip, uGuid, tex or "HUD_objective_action", size or 32, r, g, b, 255, 2, 5, dist or 175)
    if ok then return m end
    return nil
end
function Ess.Raw.Mark.removeWorld(handle)
    if handle then Ess.Safe.quiet(Marker.Remove, handle) end
end

-- Ess.Raw.Mark.worldDisc(uGuid, radius, rgb, alpha) -> handle|nil -- a ground ring (Marker.AddDisc), the
-- "go here" zone marker, distinct from a floating icon.
function Ess.Raw.Mark.worldDisc(uGuid, radius, rgb, alpha)
    local r, g, b = rgbOf(rgb)
    local ok, m = Ess.Safe.quiet(Marker.AddDisc, uGuid, radius or 15, r, g, b, alpha or 0.15)
    if ok then return m end
    return nil
end

-- Ess.Raw.Mark.pulse(uGuid, rgb) / .haltPulse(uGuid) -- flashes/pulses the object's EXISTING marker in a
-- color, a "draw attention to this" effect distinct from placing a new static marker. CONFIRMED real
-- start/stop pair (mrxfactionmanager.lua): both take the object's own uGuid directly, NOT a marker
-- handle, unlike every other function in this file.
function Ess.Raw.Mark.pulse(uGuid, rgb)
    local r, g, b = rgbOf(rgb)
    Ess.Safe.quiet(Marker.Pulse, uGuid, r, g, b)
end
function Ess.Raw.Mark.haltPulse(uGuid)
    Ess.Safe.quiet(Marker.HaltPulse, uGuid)
end

-- Ess.Raw.Mark.showPlayerMarkers(bOn) -- CONFIRMED (mrxbriefing.lua): Gui.EnablePlayerMarkers(bEnabled),
-- a GLOBAL on/off toggle (not keyed to a guid like every other function in this file) for whether OTHER
-- players' HUD markers render at all. Real confirmed use: hide during a cutscene/briefing, restore after --
-- the same "temporarily quiet the HUD for a scripted moment" need Ess.Camera.fade/Ess.Hud already serve.
function Ess.Raw.Mark.showPlayerMarkers(bOn)
    Ess.Safe.quiet(Gui.EnablePlayerMarkers, bOn and true or false)
end
