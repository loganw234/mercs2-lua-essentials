-- Ess/47_ui_confirm.lua -- Ess.UI.Confirm: modal yes/no. Grabs keys (Left/Right pick, Enter choose, Esc
-- = no; defaults to NO), restores focus, then onResult(true|false). One at a time (a singleton, matching
-- uilib.lua's UI.Confirm exactly).
--
-- Ess.UI.Confirm{ text, title, yes, no, onResult }

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

function Ess.UI.Confirm(opts)
    opts = opts or {}
    local S = Ess.UI._S
    local o = S.confirm
    if not o then
        o = {}
        o._gfx = Ess.Gfx.widget(Ess.UI.FILES.confirm, opts.x or 180, opts.y or 200, 300, 110)
        local function c(fn, args) Ess.Gfx.call(o._gfx, fn, args) end
        o._call = c
        Ess.UI._attachCommon(o); Ess.UI._register(o)
        function o:_resolve(res)
            o:hide()
            S.focus = o._prev; o._prev = nil
            local cb = o._cb; o._cb = nil
            if cb then pcall(cb, res) end
        end
        function o:_repaint()
            c("SetTitle", { o._t or "CONFIRM" })
            c("SetMsg", { 0, o._m0 or "" }); c("SetMsg", { 1, o._m1 or "" })
            c("SetOpt", { 0, o._o0 or "YES" }); c("SetOpt", { 1, o._o1 or "NO" })
            c("SetPick", { o._pick or 1 })
        end
        function o:_keyvk(vk)
            local k = Ess.UI.navName(vk); if not k then return end
            if k == "left" or k == "right" or k == "up" or k == "down" then
                o._pick = 1 - (o._pick or 1); c("SetPick", { o._pick })
            elseif k == "enter" then o:_resolve(o._pick == 0)
            elseif k == "esc" then o:_resolve(false) end
        end
        S.confirm = o
    end
    local msg = Ess.UI.wrap(tostring(opts.text or "Are you sure?"), 44)
    o._t = tostring(opts.title or "CONFIRM")
    o._m0, o._m1 = msg[1] or "", msg[2] or ""
    o._o0, o._o1 = tostring(opts.yes or "YES"), tostring(opts.no or "NO")
    o._pick = 1                                        -- default highlight = NO
    o._cb = opts.onResult
    o._prev = S.focus
    o._warmup = Ess.UI._WARMUP
    o:_repaint()
    o:show()
    o:focus()
    return o
end
