-- Ess/46_ui_toast.lua -- Ess.UI.Toast: transient notification, 3 stacked slots, oldest replaced,
-- auto-hides. Direct port of uilib.lua's UI.Toast.
--
-- Ess.UI.Toast("text"[, { ttl = seconds }])

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

function Ess.UI.Toast(text, opts)
    opts = opts or {}
    local S = Ess.UI._S
    S.toasts = S.toasts or {}
    local pick, soonest
    for i = 1, Ess.UI.TOAST_SLOTS do
        local t = S.toasts[i]
        if not t or not t.ttl then pick = i; break end
        if not soonest or t.ttl < S.toasts[soonest].ttl then soonest = i end
    end
    pick = pick or soonest or 1
    local t = S.toasts[pick]
    if not t then
        t = {}
        t._gfx = Ess.Gfx.widget(Ess.UI.FILES.toast, Ess.UI.TOAST_X, Ess.UI.TOAST_Y + (pick - 1) * Ess.UI.TOAST_GAP,
            Ess.UI.TOAST_W, Ess.UI.TOAST_H)
        S.toasts[pick] = t
    end
    local function c(fn, args) Ess.Gfx.call(t._gfx, fn, args) end
    local lines = Ess.UI.wrap(tostring(text), 46)
    t.l0, t.l1 = lines[1] or "", lines[2] or ""
    t.repaint = function() c("SetLine", { 0, t.l0 }); c("SetLine", { 1, t.l1 }) end
    t.repaint()
    if t._gfx then Ess.Gfx.setVisible(t._gfx, true) end
    t.ttl = (opts.ttl or Ess.UI.TOAST_TTL)
    t.warmup = Ess.UI._WARMUP
    function t:dismiss() t.ttl = nil; if t._gfx then Ess.Gfx.setVisible(t._gfx, false) end end
    Ess.UI._ensureTick()
    return t
end
