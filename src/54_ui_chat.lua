-- Ess/54_ui_chat.lua -- Ess.UI.Chat: a scrolling message log with an optional typed input line.
--
-- local ch = Ess.UI.Chat{ x, y, w, lines, max, title, onSubmit, autoHide }
--   ch:push("a message")     -- add a line (keeps the last `lines` visible; body auto-resizes)
--   ch:prompt()              -- enter input mode: type, Enter -> push + onSubmit(text), Esc cancels
--   ch:title(s)  ch:clear()
--   autoHide = seconds       -- optional: auto-hide this long after the last pushed message.
--                               Frozen while it has input focus (never fades mid-type) and
--                               re-surfaces on the next push. Omit for always-visible.
--
-- RETARGETED onto the shared ess_ui.gfx runtime. Public API and behaviour unchanged,
-- including the autoHide semantics (which the engine heartbeat still drives).
--
-- Widened: the visible window was hard-wired to 5 because chat.gfx had five message fields.
-- It is now `opts.lines` (default 5) and can be any size. `opts.max` still bounds the stored
-- backlog, as before.

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

local WRAP_COLS = 52
local ECHO_COLS = 44

function Ess.UI.Chat(opts)
    opts = opts or {}
    local o = {}
    local id = Ess.UI._rtId("chat")
    Ess.UI._attachRuntimeCommon(o, id)
    Ess.UI._register(o)
    o._id = id

    local VIS = tonumber(opts.lines) or 5
    if VIS < 1 then VIS = 1 end

    o._titleStr = opts.title
    o._log = {}
    o._max = opts.max or 60
    o.onSubmit = opts.onSubmit
    o._autoHide = opts.autoHide   -- seconds; nil = stay visible (default, unchanged)

    Ess.UI._rtcall("Panel", { id, opts.x or 20, opts.y or 400, opts.w or 360, opts.h or 132 })
    if opts.title then Ess.UI._rtcall("PanelTitle", { id, tostring(opts.title) }) end

    local function paintLog()
        local total = #o._log
        local shown = total
        if shown > VIS then shown = VIS end
        Ess.UI._rtcall("PanelFit", { id, shown })
        for i = 0, shown - 1 do
            Ess.UI._rtcall("PanelLine", { id, i, o._log[total - shown + i + 1] or "" })
        end
    end
    o._paintLog = paintLog

    function o:title(s)
        o._titleStr = s
        Ess.UI._rtcall("PanelTitle", { id, tostring(s) })
        return self
    end

    function o:push(text)
        for _, line in ipairs(Ess.UI.wrap(tostring(text), WRAP_COLS)) do
            o._log[#o._log + 1] = line
        end
        while #o._log > o._max do table.remove(o._log, 1) end
        paintLog()
        if o._autoHide then                      -- (re)start the countdown; resurface if faded
            if o._shown == false then o:show() end
            o._hideIn = o._autoHide
            Ess.UI._ensureTick()
        end
        return self
    end

    function o:clear() o._log = {}; paintLog(); return self end

    function o:_echo()
        local t = o._text or ""
        if #t > ECHO_COLS then t = "..." .. t:sub(#t - ECHO_COLS + 1) end
        Ess.UI._rtcall("Foot", { id, "> " .. t .. (o._blink and "_" or " ") })
    end

    function o:prompt(onSubmit)
        o._text = ""; o._blink, o._blinkClock = true, 0; o._isInput = true
        if onSubmit then o.onSubmit = onSubmit end
        o:_echo(); o:focus()
        return self
    end

    function o:_endInput()
        o._isInput = false
        Ess.UI._rtcall("Foot", { id, "" })
        if Ess.UI._S.focus == o then Ess.UI._S.focus = nil end
    end

    function o:_keyvk(vk, shift)
        if not o._isInput then return end
        if vk == 0x0D then
            local t = o._text or ""
            o:_endInput()
            if #t > 0 then o:push(t); if o.onSubmit then pcall(o.onSubmit, t) end end
        elseif vk == 0x1B then o:_endInput()
        elseif vk == 0x08 then local t = o._text or ""; if #t > 0 then o._text = t:sub(1, #t - 1); o:_echo() end
        else
            local ch = Ess.Input.VkToChar(vk, shift)
            if ch and #(o._text or "") < 200 then o._text = (o._text or "") .. ch; o:_echo() end
        end
    end

    function o:measure(cb) Ess.UI._rtMetrics(id, cb) return self end

    paintLog()
    Ess.UI._ensureTick()
    return o
end
