-- Ess/44_ui_panel.lua -- Ess.UI.Panel: title bar + body lines, body auto-resizes.
--
-- Ess.UI.Panel{ x, y, w, h, title, lines }
--   :title(s)  :line(i,s)  :fit(n)  :clear()  :show() :hide() :focus() :blur() :destroy()
--
-- RETARGETED onto the shared ess_ui.gfx runtime (see 42_ui_engine.lua). The public API is
-- unchanged -- every call above behaves exactly as it did against ui_panel.gfx -- with two
-- differences, both widenings:
--
--   * THE 8-LINE CAP IS GONE. ui_panel.gfx hand-listed eight text fields (p_line0..7), so
--     :line(8, s) and beyond silently did nothing and :fit(n) clamped at 8. The runtime
--     creates rows on demand, so :line(20, s) now works. Behaviour for i <= 7 is identical.
--   * No warm-up re-painting. Calls made before the movie finishes loading are queued and
--     flushed in order, so state cannot be dropped -- which is what the old _warmup /
--     _repaint pair existed to paper over.
--
-- The old Lua-side line cache is also gone: it only existed to re-send state during
-- warm-up, and the queue makes that unnecessary. Panels are now write-through.

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

function Ess.UI.Panel(opts)
    opts = opts or {}
    local o = {}
    local id = Ess.UI._rtId("panel")
    local x = opts.x or 20
    local y = opts.y or 120
    local w = opts.w or 300
    local h = opts.h or 200

    Ess.UI._attachRuntimeCommon(o, id)
    Ess.UI._register(o)
    o._lines = 0

    Ess.UI._rtcall("Panel", { id, x, y, w, h })

    function o:title(s)
        Ess.UI._rtcall("PanelTitle", { id, tostring(s) })
        return self
    end

    -- No upper bound any more. Negative still clamps to 0, which is what :clear() relies on.
    function o:fit(n)
        n = tonumber(n) or 0
        if n < 0 then n = 0 end
        o._lines = n
        Ess.UI._rtcall("PanelFit", { id, n })
        return self
    end

    -- i is 0-based, as before. Auto-grows to fit, as before -- it just no longer stops at 8.
    function o:line(i, s)
        i = tonumber(i) or 0
        if i < 0 then return self end
        s = tostring(s)
        Ess.UI._rtcall("PanelLine", { id, i, s })
        if s:gsub("%s", "") ~= "" and (i + 1) > o._lines then o._lines = i + 1 end
        return self
    end

    function o:clear()
        o._lines = 0
        Ess.UI._rtcall("PanelClear", { id })
        return self
    end

    -- The movie owns the layout, so ask it rather than recomputing the arithmetic here --
    -- duplicating it is what previously drew a bar through the middle of a tall panel.
    -- Answers asynchronously; `cb(w, h)` is called when the movie replies.
    function o:measure(cb)
        Ess.UI._rtMetrics(id, cb)
        return self
    end

    if opts.title then o:title(opts.title) end
    o:fit(opts.lines or 0)
    return o
end
