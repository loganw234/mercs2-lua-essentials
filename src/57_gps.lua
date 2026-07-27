-- Ess/57_gps.lua -- Ess.Gps: the player's map beacon -- the waypoint they drop on the PDA map and then
-- drive towards.
--
-- API:
--   Ess.Gps.set(x, z [,tOpts])   place the beacon marker at a world X/Z
--   Ess.Gps.clear()              remove it, engine-side and marker-side
--   Ess.Gps.get()                -> x, z  (nil if no beacon)
--   Ess.Gps.distance([i])        -> world units from player i to the beacon, or nil
--   Ess.Gps.onSet(fn)            fn(x, z) when the PLAYER sets a beacon      -- returns stop()
--   Ess.Gps.onClear(fn)          fn() when the player clears one             -- returns stop()
--
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHAT THE GPS ACTUALLY IS -- IT IS NOT A ROUTING SYSTEM
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Worth saying up front, because the name promises more than the engine delivers: there is no pathfinding
-- here, no route line, no turn-by-turn anything. The entire GPS feature, at the script layer, is ONE RADAR
-- OBJECTIVE WITH A RESERVED NAME. mrxguihudradar.lua's handler is four lines:
--
--     oMap:AddObjective("GPS Beacon Marker", tEvent.PosX, 0, tEvent.PosZ, 255,255,255,
--                       10.666667, 10.666667, "MiniMap_Icon_GPS_Marker", nil, true, nil, nil, 4)
--
-- That is it. Which is good news for a mod: placing a beacon needs no special native, just an objective
-- under the same name, and that is what .set() does.
--
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE ASYMMETRY: YOU CAN CLEAR IT, BUT THERE IS NO SetGPS
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- `Player.ClearGPS(uPlayer)` is a real engine native (confirmed present live). There is NO `Player.SetGPS` --
-- not undocumented, absent: it does not appear anywhere in a full pairs(_G) walk of the running game. Setting
-- a beacon is a UI ACTION the player performs on the PDA map, which fires the widget's SetGPSDest event.
--
-- So .set() draws the marker and .clear() does BOTH halves -- calls the native (which clears whatever engine
-- state backs the real beacon, including one the player placed) and deletes the marker (which is all a
-- script-placed one ever was). Note the consequence: a beacon placed by .set() is cosmetic. It shows up on
-- the minimap correctly, but the engine does not consider it the player's GPS destination.
--
-- ALSO NOTE the texture. "MiniMap_Icon_GPS_Marker" is NOT in mrxutil.lua's tObjRadarMaker table, which is
-- the closed list MarkerGetIndexByName_Radar validates against -- and the game's own GPS handler uses it
-- anyway. That is the proof that the table gates only the CO-OP NET SYNC path (which sends an index, so it
-- needs the name to be in the list) and not local rendering, which passes the string straight to the widget.
-- Textures outside the list therefore work locally and silently fail to replicate to a co-op client.

local Ess = _G.Ess
Ess.Gps = Ess.Gps or {}

-- The reserved name and texture, taken verbatim from mrxguihudradar.lua so a beacon placed here and one
-- placed by the game are the same object -- setting ours replaces theirs rather than stacking on top.
local GPS_NAME    = "GPS Beacon Marker"
local GPS_TEXTURE = "MiniMap_Icon_GPS_Marker"

-- Ess.Gps.set(x, z [,tOpts]) -- place the beacon at a world X/Z. Y is deliberately absent: the game's own
-- handler passes 0 for it, because the minimap is top-down and height is not representable.
--   tOpts.rgb        tint, default white like the game's
--   tOpts.sTexture   override the icon (see the note above about local-only textures)
--   tOpts.nSize      icon size, default the game's own 10.666667
-- Marking a script-placed beacon as known too, so .get() reports it rather than falling through to the
-- PDA's stale fields.
function Ess.Gps.set(x, z, tOpts)
    local nx, nz = tonumber(x), tonumber(z)
    if not nx or not nz then
        Ess.Safe.reject("Ess.Gps.set", "needs numeric x and z")
        return false
    end
    local o = type(tOpts) == "table" and tOpts or {}
    local r = (o.rgb and o.rgb[1]) or 255
    local g = (o.rgb and o.rgb[2]) or 255
    local b = (o.rgb and o.rgb[3]) or 255
    local size = tonumber(o.nSize) or 10.666667
    local ok = Ess.Safe.named("Ess.Gps.set", function()
        Hud.Radar:AddObjective({ sName = GPS_NAME, nX = nx, nY = 0, nZ = nz,
            nR = r, nG = g, nB = b, nWidth = size, nHeight = size,
            sTexture = o.sTexture or GPS_TEXTURE, bSticky = true, nSortOrder = 4 })
    end)
    if ok then Ess.Gps._x, Ess.Gps._z, Ess.Gps._known = nx, nz, true end
    return ok
end

-- Ess.Gps.clear() -- clear both halves: the engine's own GPS state and the minimap marker. Safe to call with
-- no beacon set.
function Ess.Gps.clear()
    Ess.Safe.named("Ess.Gps.clear", function()
        if Player.ClearGPS then Player.ClearGPS(Player.GetLocalPlayer()) end
    end)
    Ess.Safe.named("Ess.Gps.clear", function() Hud.Radar:RemoveObjective({ sName = GPS_NAME }) end)
    Ess.Gps._x, Ess.Gps._z, Ess.Gps._known = nil, nil, true
    return true
end

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHY THIS MODULE TRACKS THE BEACON ITSELF
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- The obvious way to answer "where is the beacon" is to read the PDA widget: mrxguipda.lua's
-- HandleMarkerUpdate stores nMarkerX/nMarkerZ on its CustomData. That source DOES NOT UPDATE PROMPTLY.
-- Measured 2026-07-26: after the player set a beacon and then cleared it, nMarkerX still read 3008 -- and a
-- later reading of the same field, after another cycle, was correctly nil. So it catches up eventually but
-- lags the actual state by an unknown amount, which makes it useless for "is there a beacon right now".
--
-- The script EVENTS, by contrast, were exact: four in a row across two cycles, in order, with the right
-- coordinates. So this module listens to those from load and keeps its own answer, and the PDA fields are
-- consulted only as a cold-start fallback -- for a beacon placed before Ess loaded, where a possibly-stale
-- value still beats none.
--
-- (Worth knowing if you go looking: HandleMarkerUpdate and HandleMarkerClear, the only corpus code that
-- writes those fields, are BOTH UNBOUND -- absent from the SetFlashEventHandler block that wires the PDA's
-- other twelve callbacks -- and yet the events fire anyway. Whatever posts them is outside the script
-- layer, so the corpus cannot tell you when those fields are written. That is the deeper reason to trust
-- the events instead: their behaviour is observable, the field's is not.)
local function armTracking()
    if Ess.Gps._stopTrackSet then Ess.Gps._stopTrackSet() end
    if Ess.Gps._stopTrackClear then Ess.Gps._stopTrackClear() end
    Ess.Gps._stopTrackSet = Ess.On.script("GPS Beacon Set", function(t)
        if type(t) == "table" then
            -- The payload's nY field carries a Z coordinate -- see Ess.Gps.onSet.
            Ess.Gps._x, Ess.Gps._z = t.nX, t.nY
            Ess.Gps._known = true
        end
    end)
    Ess.Gps._stopTrackClear = Ess.On.script("GPS Beacon Cleared", function()
        Ess.Gps._x, Ess.Gps._z = nil, nil
        Ess.Gps._known = true
    end)
end
armTracking()

-- Ess.Gps.get() -> x, z | nil -- where the beacon is, or nil if there is none.
--
-- Accurate once any beacon event has been seen, because the module tracks them (see above). Before that it
-- falls back to the PDA widget's stored fields, which can be stale in the cleared direction -- so a nil
-- return always means "no beacon", but a non-nil return from a cold start might be a beacon already gone.
function Ess.Gps.get()
    if Ess.Gps._known then
        if Ess.Gps._x and Ess.Gps._z then return Ess.Gps._x, Ess.Gps._z end
        return nil
    end
    local ok, pda = Ess.Safe.named("Ess.Gps.get", function() return MrxGuiBase.GetWidgetByName("PDA") end)
    if ok and type(pda) == "table" and type(pda.CustomData) == "table" then
        local mx, mz = pda.CustomData.nMarkerX, pda.CustomData.nMarkerZ
        if mx and mz then return mx, mz end
    end
    if Ess.Gps._x and Ess.Gps._z then return Ess.Gps._x, Ess.Gps._z end
    return nil
end

-- Ess.Gps.distance([i]) -> n | nil -- how far player i is from the beacon, in world units, measured in the
-- XZ plane only (the beacon has no height, so including Y would just add the player's altitude as error).
function Ess.Gps.distance(i)
    local bx, bz = Ess.Gps.get()
    if not bx then return nil end
    local char = Ess.Player.character(i or 0)
    if not char then return nil end
    local px, _, pz = Ess.Object.pos(char)
    if not px then return nil end
    local dx, dz = px - bx, pz - bz
    return math.sqrt(dx * dx + dz * dz)
end

-- Ess.Gps.onSet(fn) / Ess.Gps.onClear(fn) -> stop() -- react to the PLAYER placing or clearing a beacon.
-- Both verified firing across two full set/clear cycles. They are the game's own script events, so they
-- report a beacon dropped in the PDA and NOT one placed by Ess.Gps.set, which draws the marker directly.
--
-- The set payload's field names do not match its meaning: it arrives as `{nX = ..., nY = ...}` and the
-- field called nY holds a Z coordinate. fn receives (x, z) already untangled. The clear payload carries no
-- coordinates at all -- measured as CLEARED(nil,nil) -- so onClear's fn takes no arguments.
function Ess.Gps.onSet(fn)
    if type(fn) ~= "function" then return function() end end
    return Ess.On.script("GPS Beacon Set", function(t)
        if type(t) ~= "table" then return end
        fn(t.nX, t.nY)
    end)
end

function Ess.Gps.onClear(fn)
    if type(fn) ~= "function" then return function() end end
    return Ess.On.script("GPS Beacon Cleared", function() fn() end)
end
