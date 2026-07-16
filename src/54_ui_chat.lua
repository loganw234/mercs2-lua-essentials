-- Ess/54_ui_chat.lua -- Ess.UI.Chat: a scrolling message log (chat.gfx) with an optional typed input
-- line. Direct port of uilib.lua's UI.Chat.
--
-- local ch = Ess.UI.Chat{ x, y, title, onSubmit, autoHide }
--   ch:push("a message")     -- add a line (keeps the last `max` visible; body auto-resizes)
--   ch:prompt()              -- enter input mode: type, Enter -> push + onSubmit(text), Esc cancels
--   ch:title(s)  ch:clear()
--   autoHide = seconds       -- optional: auto-hide the window this long after the last pushed message.
--                               Frozen while it has input focus (never fades mid-type) and re-surfaces on
--                               the next push. Omit for the default always-visible behaviour.

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

function Ess.UI.Chat(opts)
    opts = opts or {}
    local o = {}
    o._gfx = Ess.Gfx.widget(Ess.UI.FILES.chat, opts.x or 20, opts.y or 400, opts.w or 360, opts.h or 132)
    o._shown = true
    local function c(fn, args) Ess.Gfx.call(o._gfx, fn, args) end
    o._call = c
    Ess.UI._attachCommon(o); Ess.UI._register(o)
    o._titleStr = opts.title
    o._log = {}
    o._max = opts.max or 60
    o._cur, o._tgt = 100, 100
    o._setsize = function(v) c("SetSize", { v }) end
    o.onSubmit = opts.onSubmit
    o._autoHide = opts.autoHide   -- seconds; nil = stay visible (default, unchanged behaviour)
    local BASE_H = 132

    local function paintLog()
        local total = #o._log
        local shown = total; if shown > 5 then shown = 5 end
        for i = 0, 4 do
            if i < shown then c("SetMsg", { i, o._log[total - shown + i + 1] or "" }) else c("SetMsg", { i, "" }) end
        end
        if shown < 1 then shown = 1 end
        Ess.UI._setTarget(o, 100 * (50 + 16 * shown) / BASE_H)
    end
    o._paintLog = paintLog

    function o:title(s) o._titleStr = s; c("SetTitle", { tostring(s) }) return self end
    function o:push(text)
        for _, line in ipairs(Ess.UI.wrap(tostring(text), 52)) do o._log[#o._log + 1] = line end
        while #o._log > o._max do table.remove(o._log, 1) end
        paintLog()
        if o._autoHide then                      -- (re)start the auto-hide countdown; resurface if faded out
            if o._shown == false then o:show() end
            o._hideIn = o._autoHide
            Ess.UI._ensureTick()
        end
        return self
    end
    function o:clear() o._log = {}; paintLog(); return self end

    function o:_echo()
        local t = o._text or ""
        if #t > 44 then t = "..." .. t:sub(#t - 44 + 1) end
        c("SetInput", { "> " .. t .. (o._blink and "_" or " ") })
    end
    function o:prompt(onSubmit)
        o._text = ""; o._blink, o._blinkClock = true, 0; o._isInput = true
        if onSubmit then o.onSubmit = onSubmit end
        o:_echo(); o:focus()
        return self
    end
    function o:_endInput()
        o._isInput = false
        c("SetInput", { " " })
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

    function o:_repaint()
        if o._titleStr then c("SetTitle", { tostring(o._titleStr) }) end
        paintLog()
        if o._isInput then o:_echo() end
        if o._setsize then o._setsize(o._cur) end
    end

    if opts.title then o:title(opts.title) end
    paintLog()
    o._cur = o._tgt; o._setsize(o._cur)
    o._warmup = Ess.UI._WARMUP
    Ess.UI._ensureTick()
    return o
end
