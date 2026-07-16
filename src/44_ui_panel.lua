-- Ess/44_ui_panel.lua -- Ess.UI.Panel: title bar + up to 8 lines, body auto-resizes. Direct port of
-- uilib.lua's UI.Panel.
--
-- Ess.UI.Panel{ x, y, title, lines }
--   :title(s)  :line(i,s)  :fit(n)  :clear()

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

local function panel_px(n) return 40 + 18 * n end

function Ess.UI.Panel(opts)
    opts = opts or {}
    local o = {}
    o._gfx = Ess.Gfx.widget(Ess.UI.FILES.panel, opts.x or 20, opts.y or 120, opts.w or 300, opts.h or 200)
    o._shown = true
    local function c(fn, args) Ess.Gfx.call(o._gfx, fn, args) end
    o._call = c
    Ess.UI._attachCommon(o); Ess.UI._register(o)
    o._lines = 8
    o._titleStr = opts.title
    o._L = {}
    o._cur, o._tgt = 100, 100
    o._setsize = function(v) c("SetSize", { v }) end

    function o:title(s) o._titleStr = s; c("SetTitle", { tostring(s) }) return self end
    function o:fit(n)
        n = tonumber(n) or 0; if n < 0 then n = 0 end; if n > 8 then n = 8 end
        o._lines = n
        Ess.UI._setTarget(o, 100 * panel_px(n) / 200)
        return self
    end
    function o:line(i, s)
        o._L[i] = tostring(s)
        c("SetLine", { i, tostring(s) })
        if o._L[i]:gsub("%s", "") ~= "" and (i + 1) > (o._lines or 0) then o:fit(i + 1) end
        return self
    end
    function o:clear()
        for i = 0, 7 do o._L[i] = ""; c("SetLine", { i, "" }) end
        o:fit(0)
        return self
    end
    function o:_repaint()
        if o._titleStr then c("SetTitle", { tostring(o._titleStr) }) end
        for i = 0, 7 do if o._L[i] then c("SetLine", { i, o._L[i] }) end end
        if o._setsize then o._setsize(o._cur) end
    end

    if opts.title then o:title(opts.title) end
    o:fit(opts.lines or 0)
    o._cur = o._tgt; o._setsize(o._cur)
    o._warmup = Ess.UI._WARMUP
    Ess.UI._ensureTick()
    return o
end
