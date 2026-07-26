-- Ess/57_minimap.lua -- Ess.Minimap: the minimap WIDGET, as opposed to the things drawn on it.
--
-- API:
--   Ess.Minimap.widget()                -> the raw MinimapWidget, or nil
--   Ess.Minimap.range(n)                set the view range once (see the stomp warning below)
--   Ess.Minimap.lockRange(n)            set it and KEEP it, by replacing the auto-zoom handler
--   Ess.Minimap.unlockRange()           restore the game's speed-based auto-zoom
--   Ess.Minimap.autoZoom(tOpts)         retune the auto-zoom instead of defeating it
--   Ess.Minimap.rotation(n) / .show(b) / .border(sTex, nW, nH)
--
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHY THIS IS NOT PART OF Ess.Mark, AND WHY SETTING THE RANGE IS NOT ENOUGH
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Hud.Radar -- the namespace Ess.Mark drives -- can only add, remove and animate OBJECTIVES. It has no way
-- to touch the minimap itself. The widget underneath it does: MinimapWidget carries SetRange, SetRotation,
-- SetBorder and SetVisible, none of which is reachable through any Hud.* function. Getting at it means
-- asking the widget registry directly, MrxGuiBase.GetWidgetByName("Minimap"), which is a documented pattern
-- in the game's own code (mrxguiinterface.lua:511 does the same thing for the objective tray).
--
-- THE RANGE IS RECOMPUTED FROM PLAYER SPEED. MinimapDataUpdateHandler (mrxguibase.lua:1532) runs on every
-- minimap data update and ends by calling MinimapSetRange with a value derived purely from
-- Object.GetVelocity: 150 below speed 10, 400 above speed 50, linear between. So a plain SetRange applies
-- immediately and then gets overwritten by the next update.
--
-- Measured 2026-07-26: setting range 1500 while standing still visibly zoomed the map out AND HELD, until
-- the map was turned -- at which point the handler ran and snapped it back. That is the exact shape the
-- source predicts, and it is why .range() below is documented as a one-shot and .lockRange() exists.
-- With lockRange the same zoom holds through turning and driving, confirmed the same day.
--
-- The fix is not to fight it on a timer -- it is to own the recomputation, the same lesson Ess.Atmosphere
-- learned about region blends. Two things had to be got right to do that:
--
--   * The handler is NOT a plain global. `_G.MinimapDataUpdateHandler` is nil live (measured). Resident
--     modules declare bare globals and the engine's import() machinery namespaces them, so it is really
--     MrxGuiBase.MinimapDataUpdateHandler.
--   * Patching that module entry would not work anyway. The widget captures the function BY VALUE at
--     construction (`self:SetEventHandler("GuiMinimapUpdate", MinimapDataUpdateHandler)` at
--     mrxguibase.lua:1445), so it holds the original regardless of what the module table says afterwards.
--
-- So the override is installed ON THE WIDGET, via its own SetEventHandler, wrapping whatever handler is
-- currently registered. That is narrower than a global patch (it affects one widget, not every consumer of
-- the module) and it is properly reversible, because Widget:SetEventHandler deletes the previous Event
-- registration before making the new one rather than leaking it.
--
-- CAVEAT: the widget is rebuilt on level load, which takes the override with it. Re-apply after a load.

local Ess = _G.Ess
Ess.Minimap = Ess.Minimap or {}

-- Ess.Minimap.widget() -> MinimapWidget|nil -- the widget itself, for anything not wrapped here. Not cached:
-- the widget is rebuilt across level loads, so a stale handle would silently stop working.
function Ess.Minimap.widget()
    local ok, w = Ess.Safe.quiet(function() return MrxGuiBase.GetWidgetByName("Minimap") end)
    if ok and type(w) == "table" then return w end
    return nil
end

-- Ess.Minimap.range(n) -- ONE-SHOT. Applies immediately, survives until the next minimap data update, then
-- the speed-based auto-zoom overwrites it. Fine for a momentary effect; use lockRange for anything that
-- should persist. The game's own range runs 150 (standing) to 400 (fast).
function Ess.Minimap.range(n)
    local v = tonumber(n)
    local w = v and Ess.Minimap.widget()
    if not w then return false end
    Ess.Safe.quiet(function() w:SetRange(v) end)
    return true
end

-- Install `fn` as the minimap's update handler, remembering whatever was there so it can be put back.
-- Always wraps rather than replaces at the call sites below: the original handler does the actual
-- MinimapUpdate that DRAWS the map before it ever touches the range, so a handler that skipped it would
-- freeze the minimap rather than zoom it.
local function installHandler(fn)
    local w = Ess.Minimap.widget()
    if not w or type(w.EventHandlers) ~= "table" then return nil end
    if not Ess.Minimap._origHandler then
        local h = w.EventHandlers.GuiMinimapUpdate
        if type(h) ~= "function" then return nil end
        Ess.Minimap._origHandler = h
    end
    local ok = Ess.Safe.quiet(function() w:SetEventHandler("GuiMinimapUpdate", fn) end)
    if not ok then return nil end
    return w
end

-- Ess.Minimap.lockRange(n) -- set the range and KEEP it against the auto-zoom.
function Ess.Minimap.lockRange(n)
    local v = tonumber(n)
    if not v then return false end
    Ess.Minimap._lockedRange = v
    local w = installHandler(function(oMinimap, ...)
        Ess.Safe.quiet(Ess.Minimap._origHandler, oMinimap, ...)
        local r = Ess.Minimap._lockedRange
        if r and oMinimap then Ess.Safe.quiet(function() oMinimap:SetRange(r) end) end
    end)
    if not w then Ess.Minimap._lockedRange = nil; return false end
    Ess.Safe.quiet(function() w:SetRange(v) end)
    return true
end

-- Ess.Minimap.unlockRange() -- put the original handler back and let the auto-zoom resume.
function Ess.Minimap.unlockRange()
    Ess.Minimap._lockedRange = nil
    local orig = Ess.Minimap._origHandler
    if not orig then return true end
    local w = Ess.Minimap.widget()
    if w then Ess.Safe.quiet(function() w:SetEventHandler("GuiMinimapUpdate", orig) end) end
    Ess.Minimap._origHandler = nil
    return true
end

-- Ess.Minimap.autoZoom(tOpts) -- retune the speed-based zoom rather than defeating it, reproducing the
-- game's own curve with your numbers. tOpts.nMinSpeed/nMaxSpeed (stock 10/50) and nMinRange/nMaxRange
-- (stock 150/400). Passing no options reinstates the stock figures, so this doubles as a reset.
function Ess.Minimap.autoZoom(tOpts)
    local o = type(tOpts) == "table" and tOpts or {}
    local minSpd = tonumber(o.nMinSpeed) or 10
    local maxSpd = tonumber(o.nMaxSpeed) or 50
    local minRng = tonumber(o.nMinRange) or 150
    local maxRng = tonumber(o.nMaxRange) or 400
    if maxSpd <= minSpd then return false end
    Ess.Minimap._lockedRange = nil
    return installHandler(function(oMinimap, ...)
        Ess.Safe.quiet(Ess.Minimap._origHandler, oMinimap, ...)
        if not oMinimap then return end
        local v
        Ess.Safe.quiet(function()
            local uChar = Player.GetControlledObject(oMinimap:GetOwner())
            if uChar then v = Object.GetVelocity(uChar) end
        end)
        -- GetVelocity returns a SCALAR on this engine, not a vector -- the stock handler relies on the same
        -- thing. A nil reading means leave the range alone, which is what the original does too.
        if not v then return end
        local r
        if v < minSpd then r = minRng
        elseif v > maxSpd then r = maxRng
        else r = minRng + (v - minSpd) * (maxRng - minRng) / (maxSpd - minSpd) end
        Ess.Safe.quiet(function() oMinimap:SetRange(r) end)
    end) ~= nil
end

-- Ess.Minimap.rotation(n) -- rotate the minimap. ONE-SHOT: the game drives rotation from camera heading
-- through the same update handler, and lockRange's wrapper deliberately only forces the RANGE, so rotation
-- is reset on the next update just as a bare SetRange is. Owning it would mean suppressing the original
-- handler's rotation argument, which would break the map's north-up behaviour -- not worth it for an effect
-- with no known use. Fine for a momentary flourish.
function Ess.Minimap.rotation(n)
    local v = tonumber(n)
    local w = v and Ess.Minimap.widget()
    if not w then return false end
    Ess.Safe.quiet(function() w:SetRotation(v) end)
    return true
end

-- Ess.Minimap.show(bOn) -- hide or show the whole minimap. This is what the game's own E3-demo HUD mode does
-- (MinimapHandleE3HudModeEvent), so it is a supported state and not a hack.
function Ess.Minimap.show(bOn)
    local w = Ess.Minimap.widget()
    if not w then return false end
    Ess.Safe.quiet(function() w:SetVisible(bOn ~= false) end)
    return true
end

-- Ess.Minimap.border(sTexture, nWidth, nHeight) -- swap the minimap's frame texture. Guarded inside the
-- widget by `if _GuiInternal.SetMinimapBorder then`, so on a build without that native it is a silent no-op
-- rather than an error -- which also means a `true` from here does NOT prove anything changed.
function Ess.Minimap.border(sTexture, nWidth, nHeight)
    if type(sTexture) ~= "string" or sTexture == "" then return false end
    local w = Ess.Minimap.widget()
    if not w then return false end
    Ess.Safe.quiet(function() w:SetBorder(sTexture, tonumber(nWidth), tonumber(nHeight)) end)
    return true
end
