-- Ess/48_ui_input.lua -- Ess.UI.Input: one-shot typed prompt. Enter -> onSubmit(text), Esc -> onCancel().
-- One at a time (a singleton). Uses Ess.Input.VkToChar for character typing.
--
-- Ess.UI.Input{ prompt, text, max, onSubmit, onCancel }
--
-- RETARGETED onto the shared ess_ui.gfx runtime. Public API, key handling, the caret blink
-- and the focus save/restore are unchanged -- the blink is still driven by the heartbeat
-- (it checks _isInput and calls _echo), because it is input state rather than decoration.

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

local ECHO_COLS = 40   -- how much of a long entry stays visible, tail-anchored

function Ess.UI.Input(opts)
    opts = opts or {}
    local S = Ess.UI._S
    local o = S.input
    if not o then
        o = {}
        local id = Ess.UI._rtId("input")
        Ess.UI._attachRuntimeCommon(o, id)
        Ess.UI._register(o)
        o._id = id
        o._isInput = true
        Ess.UI._rtcall("Panel", { id, opts.x or 160, opts.y or 260, 340, 56 })
        Ess.UI._rtcall("PanelFit", { id, 0 })

        function o:_echo()
            local t = o._text or ""
            if #t > ECHO_COLS then t = "..." .. t:sub(#t - ECHO_COLS + 1) end
            -- Foot() rather than a body line: the echo is drawn in the primary text colour
            -- along the bottom, which is where the old ui_input.gfx put it.
            Ess.UI._rtcall("Foot", { o._id, "> " .. t .. (o._blink and "_" or " ") })
        end

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
    Ess.UI._rtcall("PanelTitle", { o._id, o._t })
    o:_echo()
    o:show()
    o:focus()
    return o
end
