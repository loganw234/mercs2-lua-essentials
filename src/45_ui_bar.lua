-- Ess/45_ui_bar.lua -- Ess.UI.Bar: label + progress bar.
--
-- Ess.UI.Bar{ x, y, label, value }
--   :set(0..1)  :label(s)
--
-- RETARGETED onto the shared ess_ui.gfx runtime (see 42_ui_engine.lua). The public API,
-- argument names and default position/size are unchanged from the ui_bar.gfx version, and
-- :set() still takes 0..1 and still clamps.
--
-- The old _repaint/_warmup pair is gone: calls made before the movie loads are queued and
-- flushed rather than dropped, so there is no state to re-send.

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

function Ess.UI.Bar(opts)
    opts = opts or {}
    local o = {}
    local id = Ess.UI._rtId("bar")
    -- same defaults the ui_bar.gfx version used, so existing call sites land identically
    local x = opts.x or 20
    local y = opts.y or 330
    local w = opts.w or 300
    local h = opts.h or 36

    Ess.UI._attachRuntimeCommon(o, id)
    Ess.UI._register(o)

    o._pct = 0
    o._labelStr = opts.label

    Ess.UI._rtcall("Bar", { id, x, y, w, h, tostring(opts.label or ""), 0 })

    function o:set(v)
        v = tonumber(v) or 0
        if v < 0 then v = 0 end
        if v > 1 then v = 1 end
        -- _pct stays 0..100 because that is what this object has always exposed to anything
        -- poking at it directly; the movie takes the 0..1 form.
        o._pct = math.floor(v * 100)
        Ess.UI._rtcall("BarSet", { id, v, tostring(o._labelStr or "") })
        return self
    end

    function o:label(s)
        o._labelStr = s
        Ess.UI._rtcall("BarSet", { id, o._pct / 100, tostring(s) })
        return self
    end

    -- Ask the movie for the real laid-out box rather than assuming w/h above.
    function o:measure(cb)
        Ess.UI._rtMetrics(id, cb)
        return self
    end

    if opts.label then o:label(opts.label) end
    o:set(opts.value or 0)
    return o
end
