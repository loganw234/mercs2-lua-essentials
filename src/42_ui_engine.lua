-- Ess/42_ui_engine.lua -- Ess.UI's private engine: the shared heartbeat, focus model, and small
-- utilities every widget in the kit depends on. Ported from uilib.lua v2.2's proven-correct plumbing --
-- the exact same recipe that made ForgeMenu rock-solid: edge-drained key input, a self-re-arming
-- heartbeat that idles when nothing needs it, async-load warmup re-paints, everything pcall-wrapped.
-- Rebuilt here on top of Ess's own already-tested primitives (Ess.Gfx for the raw widget, Ess.Loop for
-- the heartbeat, Ess.Input for key polling, Ess.Timer for wall-clock delta) instead of uilib's private
-- copies of the same mechanisms.
--
-- Not meant to be called by modders directly -- this is Ess.UI's own internals. See the individual
-- widget files (43_ui_list.lua etc) for the public API.

local Ess = _G.Ess
Ess.UI = Ess.UI or {}
Ess.UI._S = Ess.UI._S or {}
local S = Ess.UI._S

Ess.UI.VERSION = "1.0"  -- Ess's port of uilib v2.2 -- see FEATURE_SHEET.md for the port notes

-- Movie asset names, WITH the .gfx suffix -- matches uilib.lua's own UI.FILES exactly (its
-- confirmed-working production convention), not the extension-less form used elsewhere in Ess.Gfx's own
-- tests (that test never had visual confirmation the movie content actually rendered, only that the
-- widget object constructed without erroring -- don't copy that convention here without re-verifying it).
Ess.UI.FILES = Ess.UI.FILES or {
    list = "ui_list.gfx", panel = "ui_panel.gfx", bar = "ui_bar.gfx",
    toast = "ui_toast.gfx", confirm = "ui_confirm.gfx", input = "ui_input.gfx",
    chat = "chat.gfx", board = "contracts.gfx",
}
-- Toasts default to the RIGHT side (fixed 640x480 virtual canvas, Scaleform scales it to any resolution).
Ess.UI.TOAST_W = Ess.UI.TOAST_W or 160
Ess.UI.TOAST_H = Ess.UI.TOAST_H or 22
Ess.UI.TOAST_GAP = Ess.UI.TOAST_GAP or 25
Ess.UI.TOAST_X = Ess.UI.TOAST_X or (640 - Ess.UI.TOAST_W - 8)
Ess.UI.TOAST_Y = Ess.UI.TOAST_Y or 150
Ess.UI.TOAST_SLOTS = Ess.UI.TOAST_SLOTS or 3
Ess.UI.TOAST_TTL = Ess.UI.TOAST_TTL or 4

local TICK = 0.05
Ess.UI._WARMUP = 8

-- ============================ utilities ==============================
function Ess.UI.wrap(s, width)
    s = tostring(s or ""); width = width or 46
    local out = {}
    while #s > width do
        local cut = width
        for i = width, math.max(1, width - 15), -1 do
            if s:sub(i, i) == " " then cut = i; break end
        end
        out[#out + 1] = s:sub(1, cut)
        s = s:sub(cut + 1):gsub("^%s+", "")
    end
    if #s > 0 then out[#out + 1] = s end
    if #out == 0 then out[1] = "" end
    return out
end

function Ess.UI.comma(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local r = s:reverse():gsub("(%d%d%d)", "%1,")
    return (r:reverse():gsub("^,", ""))
end

function Ess.UI.fmt_time(sec)
    sec = math.floor(tonumber(sec) or 0)
    local m = math.floor(sec / 60)
    local s2 = sec - m * 60
    if s2 < 10 then return m .. ":0" .. s2 end
    return m .. ":" .. s2
end

-- ============================ nav keys =================================
-- Remappable globally, e.g. Ess.UI.KEYS.up = 0x57 ('W'). Distinct from Ess.Input.VkToChar (character
-- typing) -- this maps a vk to a semantic nav direction (up/down/left/right/enter/esc) instead.
Ess.UI.KEYS = Ess.UI.KEYS or { up = 0x26, down = 0x28, left = 0x25, right = 0x27, enter = 0x0D, esc = 0x1B }
function Ess.UI.navName(vk)
    local k = Ess.UI.KEYS
    if vk == k.up then return "up"
    elseif vk == k.down then return "down"
    elseif vk == k.left then return "left"
    elseif vk == k.right then return "right"
    elseif vk == k.enter then return "enter"
    elseif vk == k.esc then return "esc" end
    return nil
end

-- ============================== focus ==================================
-- Exactly one widget hears keys. Setting it swallows any buffered keys (so the toggle press doesn't leak
-- in) and wakes the heartbeat.
local function ui_focus(o)
    S.focus = o
    pcall(Loader.ClearKeyEvents)
    Ess.UI._ensureTick()
end
function Ess.UI.Focus(w) ui_focus(w) end
function Ess.UI.Focused() return S.focus end

-- ============================ widget-common =============================
-- show/hide/focus/blur/destroy shared by every widget object. `o._gfx` is an Ess.Gfx widget wrapper
-- ({raw=,shown=}, from Ess.Gfx.widget) -- widgets built here always store IT, never the raw FlashWidget
-- directly, so Ess.Gfx.setVisible's own GetVisible/IsVisible bugfix stays in effect everywhere.
function Ess.UI._attachCommon(o)
    function o:show()
        if o._gfx then Ess.Gfx.setVisible(o._gfx, true) end
        o._shown = true
        o._warmup = Ess.UI._WARMUP
        Ess.UI._ensureTick()
        pcall(function() o:_repaint() end)
        return self
    end
    function o:hide()
        if o._gfx then Ess.Gfx.setVisible(o._gfx, false) end
        o._shown = false
        if S.focus == o then S.focus = nil end
        return self
    end
    function o:destroy()
        -- no widget-removal API confirmed in this engine -- hide + drop the reference and let it fall
        -- out of the live list. Prefer reuse over destroy where possible (matches uilib's own note).
        if S.focus == o then S.focus = nil end
        if o._gfx then Ess.Gfx.setVisible(o._gfx, false) end
        o._gfx = nil
        return self
    end
    function o:focus() ui_focus(o); return self end
    function o:blur() if S.focus == o then S.focus = nil end return self end
    function o:_repaint() end  -- widgets override to re-send their state
end

-- body-resize easing target (the "Forge feel"); waking the heartbeat animates it
function Ess.UI._setTarget(o, pct)
    o._tgt = pct
    Ess.UI._ensureTick()
end

function Ess.UI._register(o)
    S.live = S.live or {}
    for _, e in ipairs(S.live) do if e == o then return end end
    S.live[#S.live + 1] = o
end

-- ============================ the shared heartbeat =======================
-- Services: (1) keys for the focused widget, (2) warm-up re-paints + size easing for live widgets,
-- (3) toast lifetimes, (4) input caret blink.
local function service(dt)
    local f = S.focus
    if f and f._keyvk and f._gfx and f._shown ~= false then
        local input = Ess.Input.poll()
        local shift = input.down(0x10)
        for _, vk in ipairs(input.pressed) do
            if S.focus ~= f then break end          -- an action changed focus mid-drain: stop feeding the old widget
            f:_keyvk(vk, shift)
        end
    end
    if S.live then
        for i = #S.live, 1, -1 do
            local o = S.live[i]
            if not o or not o._gfx then
                table.remove(S.live, i)
            else
                if o._warmup and o._warmup > 0 then
                    o._warmup = o._warmup - 1
                    pcall(function() o:_repaint() end)
                end
                if o._cur and o._tgt and o._cur ~= o._tgt then
                    local d = o._tgt - o._cur
                    if d > 0.5 or d < -0.5 then o._cur = o._cur + d * 0.35 else o._cur = o._tgt end
                    if o._setsize then o._setsize(o._cur) end
                end
            end
        end
    end
    if S.toasts then
        for i = 1, Ess.UI.TOAST_SLOTS do
            local t = S.toasts[i]
            if t and t.ttl then
                if t.warmup and t.warmup > 0 then t.warmup = t.warmup - 1; pcall(t.repaint) end
                t.ttl = t.ttl - dt
                if t.ttl <= 0 then
                    t.ttl = nil
                    if t._gfx then Ess.Gfx.setVisible(t._gfx, false) end
                end
            end
        end
    end
    if f and f._isInput and f._gfx and f._shown ~= false then
        f._blinkClock = (f._blinkClock or 0) + dt
        if f._blinkClock >= 0.35 then f._blinkClock = 0; f._blink = not f._blink; f:_echo() end
    end
end

local function needsTick()
    if S.focus then return true end
    if S.live then
        for _, o in ipairs(S.live) do
            if o._gfx and ((o._warmup and o._warmup > 0) or (o._cur and o._tgt and o._cur ~= o._tgt)) then
                return true
            end
        end
    end
    if S.toasts then
        for i = 1, Ess.UI.TOAST_SLOTS do if S.toasts[i] and S.toasts[i].ttl then return true end end
    end
    return false
end

-- start the heartbeat if it isn't already running; it self-stops when idle (needsTick() becomes the
-- tick's own return value, matching Ess.Loop's "true = keep going" contract exactly). Guarded by
-- isRunning rather than calling Ess.Loop.start unconditionally -- Loop.start REPLACES/reschedules a
-- running loop under the same id rather than leaving it alone, so an unconditional call here (e.g. from
-- every :show()) would keep resetting the next-tick timer instead of just confirming it's already armed.
local uiTimer
function Ess.UI._ensureTick()
    if Ess.Loop.isRunning("Ess.UI.heartbeat") then return end
    if not uiTimer then uiTimer = Ess.Timer.start() end
    Ess.Loop.start("Ess.UI.heartbeat", TICK, function()
        local dt = uiTimer:elapsed()
        local ok, err = pcall(service, dt)
        if not ok then Ess.Log("UI heartbeat tick error: " .. tostring(err)) end
        return needsTick()
    end)
end

-- ============================ boot ======================================
-- Re-runs on every world (re)load, by which point the engine has torn down every FlashWidget from the
-- previous world. Forget all stale handles + state so everything rebuilds cleanly (singletons on next
-- use, menus/lists on next open) and no orphaned heartbeat or focus survives a load.
S.live, S.focus, S.openId = {}, nil, nil
S.confirm, S.input, S.toasts = nil, nil, nil
if S.menus then for _, rt in pairs(S.menus) do rt.list = nil; rt.open = false; rt.menu = nil end end
