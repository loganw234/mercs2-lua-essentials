-- Ess/46_ui_toast.lua -- Ess.UI.Toast: transient notification, stacked slots, auto-hides.
--
-- Ess.UI.Toast("text"[, { ttl = seconds }])
--
-- RETARGETED onto the shared ess_ui.gfx runtime (see 42_ui_engine.lua). The public call is
-- unchanged, as is the returned object's :dismiss(), the Ess.UI.TOAST_* tunables, and the
-- slot-recycling rule (fill a free slot; otherwise take over the one expiring soonest).
--
-- Two differences, both widenings:
--
--   * TOAST_SLOTS is now a tunable, not a ceiling. It was 3 because ui_toast.gfx was a
--     single-toast movie instantiated three times; the runtime creates a panel per slot on
--     demand, so raising Ess.UI.TOAST_SLOTS just works.
--   * Text is no longer pre-wrapped in Lua. The movie's text field wraps natively, so long
--     toasts wrap properly instead of being cut to the two lines the old movie had fields
--     for. Ess.UI.wrap stays exported -- user scripts call it directly -- it just isn't
--     needed here any more.
--
-- Lifetimes are still counted down by the shared heartbeat in 42_ui_engine.lua, which is
-- what hides an expired toast.

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

function Ess.UI.Toast(text, opts)
    opts = opts or {}
    local S = Ess.UI._S
    S.toasts = S.toasts or {}

    -- Pick a free slot, else the one that expires soonest -- unchanged behaviour.
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
        t._rtid = Ess.UI._rtId("toast")
        t._slot = pick
        Ess.UI._rtcall("Panel", {
            t._rtid,
            Ess.UI.TOAST_X or (Ess.UI.canvasW() - Ess.UI.TOAST_W - 8),
            Ess.UI.TOAST_Y + (pick - 1) * Ess.UI.TOAST_GAP,
            Ess.UI.TOAST_W,
            Ess.UI.TOAST_H,
        })
        -- A toast has no title bar; one body line holding the (movie-wrapped) message.
        Ess.UI._rtcall("PanelFit", { t._rtid, 1 })
        S.toasts[pick] = t
    end

    -- Toasts are deliberately title-less: a Panel with no title draws no header band,
    -- which is what stops a one-line notification from carrying a big empty accent bar.
    t.text = tostring(text)
    Ess.UI._rtcall("PanelLine", { t._rtid, 0, t.text })
    Ess.UI._rtcall("Show", { t._rtid, 1 })
    t.ttl = (opts.ttl or Ess.UI.TOAST_TTL)

    -- The heartbeat calls these; keeping the field names it already looks for (_gfx was the
    -- old handle, and the loop tests it for liveness) would be misleading here, so the
    -- engine's toast servicing checks _rtid instead.
    function t:dismiss()
        t.ttl = nil
        Ess.UI._rtcall("Show", { t._rtid, 0 })
        return t
    end

    Ess.UI._ensureTick()
    return t
end
