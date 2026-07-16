-- Ess/48_ui_input.lua -- Ess.UI.Input: one-shot typed prompt. Enter -> onSubmit(text), Esc -> onCancel().
-- One at a time (a singleton, matching uilib.lua's UI.Input exactly). Uses Ess.Input.VkToChar for
-- character typing instead of a private copy of the VK->char table.
--
-- Ess.UI.Input{ prompt, text, max, onSubmit, onCancel }

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

function Ess.UI.Input(opts)
    opts = opts or {}
    local S = Ess.UI._S
    local o = S.input
    if not o then
        o = {}
        o._gfx = Ess.Gfx.widget(Ess.UI.FILES.input, opts.x or 160, opts.y or 260, 340, 56)
        local function c(fn, args) Ess.Gfx.call(o._gfx, fn, args) end
        o._call = c
        Ess.UI._attachCommon(o); Ess.UI._register(o)
        o._isInput = true
        function o:_echo()
            local t = o._text or ""
            if #t > 40 then t = "..." .. t:sub(#t - 40 + 1) end
            c("SetInput", { "> " .. t .. (o._blink and "_" or " ") })
        end
        function o:_repaint() c("SetTitle", { o._t or "INPUT" }); o:_echo() end
        function o:_char(ch)
            if #(o._text or "") < (o._max or 120) then o._text = (o._text or "") .. ch; o:_echo() end
        end
        function o:_bs()
            local t = o._text or ""
            if #t > 0 then o._text = t:sub(1, #t - 1); o:_echo() end
        end
        function o:_finish(useCancel)
            o:hide()
            S.focus = o._prev; o._prev = nil
            local sub, can = o._cb, o._cancel
            o._cb, o._cancel = nil, nil
            if useCancel then
                if can then pcall(can) end
            else
                if sub then pcall(sub, o._text or "") end
            end
        end
        function o:_keyvk(vk, shift)
            if vk == 0x0D then o:_finish(false)
            elseif vk == 0x1B then o:_finish(true)
            elseif vk == 0x08 then o:_bs()
            else
                local ch = Ess.Input.VkToChar(vk, shift)
                if ch then o:_char(ch) end
            end
        end
        S.input = o
    end
    o._t = tostring(opts.prompt or "INPUT -- ENTER SUBMIT   ESC CANCEL")
    o._text = tostring(opts.text or "")
    o._max = opts.max or 120
    o._cb, o._cancel = opts.onSubmit, opts.onCancel
    o._blink, o._blinkClock = true, 0
    o._prev = S.focus
    o._warmup = Ess.UI._WARMUP
    o:_repaint()
    o:show()
    o:focus()
    return o
end
