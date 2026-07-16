-- Ess/45_ui_bar.lua -- Ess.UI.Bar: label + progress bar. Direct port of uilib.lua's UI.Bar.
--
-- Ess.UI.Bar{ x, y, label, value }
--   :set(0..1)  :label(s)

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

function Ess.UI.Bar(opts)
    opts = opts or {}
    local o = {}
    o._gfx = Ess.Gfx.widget(Ess.UI.FILES.bar, opts.x or 20, opts.y or 330, opts.w or 300, opts.h or 36)
    o._shown = true
    local function c(fn, args) Ess.Gfx.call(o._gfx, fn, args) end
    o._call = c
    Ess.UI._attachCommon(o); Ess.UI._register(o)
    o._pct, o._labelStr = 0, opts.label

    function o:set(v)
        v = tonumber(v) or 0; if v < 0 then v = 0 end; if v > 1 then v = 1 end
        o._pct = math.floor(v * 100)
        c("SetBar", { o._pct })
        return self
    end
    function o:label(s) o._labelStr = s; c("SetLabel", { tostring(s) }) return self end
    function o:_repaint()
        if o._labelStr then c("SetLabel", { tostring(o._labelStr) }) end
        c("SetBar", { o._pct })
    end

    if opts.label then o:label(opts.label) end
    o:set(opts.value or 0)
    o._warmup = Ess.UI._WARMUP
    Ess.UI._ensureTick()
    return o
end
