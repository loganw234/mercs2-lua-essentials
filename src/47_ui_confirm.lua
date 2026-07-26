-- Ess/47_ui_confirm.lua -- Ess.UI.Confirm: modal yes/no. Grabs keys (Left/Right pick, Enter choose, Esc
-- = no; defaults to NO), restores focus, then onResult(true|false). One at a time (a singleton).
--
-- Ess.UI.Confirm{ text, title, yes, no, onResult }
--
-- RETARGETED onto the shared ess_ui.gfx runtime. Public API, key bindings, the NO default and
-- the focus save/restore are all unchanged.
--
-- Widened: the message is no longer clipped to two lines. ui_confirm.gfx had exactly two
-- message fields, so anything longer was silently cut; the runtime creates as many as the
-- text needs. Ess.UI.wrap still does the wrapping here (rather than letting the field wrap
-- natively) so the dialog's width stays predictable regardless of message length.

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

local WRAP_COLS = 44
local MAX_LINES = 8    -- a sanity bound, not a format limit: a dialog taller than this is a panel

function Ess.UI.Confirm(opts)
    opts = opts or {}
    local S = Ess.UI._S
    local o = S.confirm
    if not o then
        o = {}
        local id = Ess.UI._rtId("confirm")
        Ess.UI._attachRuntimeCommon(o, id)
        Ess.UI._register(o)
        o._id = id
        Ess.UI._rtcall("Panel", { id, opts.x or 180, opts.y or 200, 300, 110 })

        function o:_resolve(res)
            o:hide()
            S.focus = o._prev; o._prev = nil
            local cb = o._cb; o._cb = nil
            if cb then pcall(cb, res) end
        end

        function o:_draw()
            Ess.UI._rtcall("PanelTitle", { o._id, o._t or "CONFIRM" })
            local lines = o._lines or {}
            Ess.UI._rtcall("PanelFit", { o._id, #lines })
            for i = 1, #lines do
                Ess.UI._rtcall("PanelLine", { o._id, i - 1, lines[i] })
            end
            -- pick is 0 = yes, 1 = no, matching the old SetPick contract
            Ess.UI._rtcall("Choices", { o._id, o._pick or 1, o._o0 or "YES", o._o1 or "NO" })
        end

        function o:_keyvk(vk)
            local k = Ess.UI.navName(vk); if not k then return end
            if k == "left" or k == "right" or k == "up" or k == "down" then
                o._pick = 1 - (o._pick or 1)
                Ess.UI._rtcall("Choices", { o._id, o._pick, o._o0 or "YES", o._o1 or "NO" })
            elseif k == "enter" then o:_resolve(o._pick == 0)
            elseif k == "esc" then o:_resolve(false) end
        end
        S.confirm = o
    end

    local wrapped = Ess.UI.wrap(tostring(opts.text or "Are you sure?"), WRAP_COLS)
    while #wrapped > MAX_LINES do table.remove(wrapped) end
    o._lines = wrapped
    o._t = tostring(opts.title or "CONFIRM")
    o._o0, o._o1 = tostring(opts.yes or "YES"), tostring(opts.no or "NO")
    o._pick = 1                                        -- default highlight = NO
    o._cb = opts.onResult
    o._prev = S.focus
    o:_draw()
    o:show()
    o:focus()
    return o
end
