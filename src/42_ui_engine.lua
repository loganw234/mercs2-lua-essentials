-- Ess/42_ui_engine.lua -- Ess.UI's private engine: the shared heartbeat, focus model, and small
-- utilities every widget in the kit depends on. Ported from uilib.lua v2.2's proven-correct plumbing --
-- the exact same recipe that made ForgeMenu rock-solid: edge-drained key input, a self-re-arming
-- heartbeat that idles when nothing needs it, async-load warmup re-paints, everything pcall-wrapped.
-- Rebuilt here on top of Ess's own already-tested primitives (Ess.Gfx for the raw widget, Ess.Loop for
-- the heartbeat, Ess.Input for key polling, Ess.Time.clock for the per-frame wall-clock delta) instead of
-- uilib's private copies of the same mechanisms.
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
--
-- `runtime` is the new single asset: one movie whose payload is an AS2 UI toolkit that draws
-- every widget at runtime from theme parameters. The per-widget entries are kept because
-- they are part of the published surface and because widgets are being migrated one at a
-- time -- anything not yet retargeted still loads its own movie.
Ess.UI.FILES = Ess.UI.FILES or {
    runtime = "ess_ui.gfx",
    list = "ui_list.gfx", panel = "ui_panel.gfx", bar = "ui_bar.gfx",
    toast = "ui_toast.gfx", confirm = "ui_confirm.gfx", input = "ui_input.gfx",
    chat = "chat.gfx", board = "contracts.gfx",
}
-- ============================ the canvas ================================
-- Widget coordinates are NOT pixels. MrxGuiBase defines a fixed virtual space
-- (nWidgetSpaceScreenWidth/Height = 640x480, mrxguibase.lua:1791) and the engine scales it to
-- whatever the display is, so every x/y/w/h in this kit is already resolution-independent --
-- the same numbers land in the same relative place at 1080p, 1440p or 4K. There is nothing
-- to compute per-resolution and no reason to express sizes as percentages: a percentage of
-- 640 is just a number you could have written directly.
--
-- Do NOT read MrxGuiBase.nScreenWidth/nScreenHeight for this. They report 640x480 with
-- scale 1 regardless of the real display, because g_nGuiScreenWidthTemp was nil when that
-- module loaded -- they are defaults, not measurements.
--
-- MEASURED (1440p, 16:9), and then CORRECTED:
--
-- First reading: a 640-wide marker strip filled ~75% of the screen, which looked like
-- "the canvas is 853 units wide (480 * 16/9) and 640 is only part of it". Setting
-- CANVAS_W = 853 and anchoring a marker to right=0 then put it COMPLETELY OFF SCREEN.
--
-- The real constraint is not the canvas, it is OUR WIDGET. rtEnsure() builds the runtime
-- FlashWidget with SetLocation(0, 0, 640, 480) and ess_ui.gfx's stage is 640x480, so
-- anything drawn past x=640 is outside the widget rectangle and gets clipped. The 75%
-- figure was measuring how much of a widescreen display a 640-wide WIDGET covers -- not
-- how wide the canvas is.
--
-- So the usable drawing area is 640x480, full stop, and CANVAS_W is 640 on every display.
-- The right quarter of a widescreen display is simply outside our widget.
--
-- TO ACTUALLY USE THE FULL WIDTH you would need BOTH: rebuild ess_ui.gfx with a wider
-- stage, AND widen the widget rect to match. Neither alone is enough -- widening only the
-- rect stretches the 640 stage across it. Deliberately not done: it needs a decision about
-- what 4:3 displays should then do (an 853-wide stage squeezed into a 640-wide rect
-- distorts), and the kit has always lived in a 640x480 box.
Ess.UI.CANVAS_H = Ess.UI.CANVAS_H or 480

Ess.UI.CANVAS_W = Ess.UI.CANVAS_W or 640

-- The usable virtual width. A function rather than a bare constant so that widening the
-- widget + stage later is a change in one place rather than at every call site.
function Ess.UI.canvasW() return Ess.UI.CANVAS_W end

-- w, h, ratio -- ratio is the game's own category string ("WIDESCREEN" / "NORMAL"), not a number.
function Ess.UI.screen()
    local ok, r = Ess.Safe.quiet(Graphics.GetScreenRatio)
    return Ess.UI.canvasW(), Ess.UI.CANVAS_H, (ok and r or nil)
end

-- Resolve an edge-relative box to concrete x, y, w, h.
--
--   Ess.UI.anchor{ right = 8, top = 8, w = 160, h = 22 }   -- 8 in from the top-right
--   Ess.UI.anchor{ cx = true, bottom = 40, w = 300, h = 80 } -- centred, 40 up from the bottom
--
-- Point of the indirection: "8 in from the right edge" resolves against the MEASURED canvas
-- width, whereas `x = 640 - 160 - 8` written at a call site bakes in the 4:3 assumption.
-- Ess.UI.TOAST_X used to be exactly that, and put toasts ~213 units left of the real edge on
-- every widescreen display. Use this for anything right- or bottom-anchored.
function Ess.UI.anchor(a)
    a = a or {}
    local CW, CH = Ess.UI.canvasW(), Ess.UI.CANVAS_H
    local w = a.w or 100
    local h = a.h or 24
    local x, y
    if a.cx then x = math.floor((CW - w) / 2)
    elseif a.right then x = CW - w - a.right
    else x = a.left or 0 end
    if a.cy then y = math.floor((CH - h) / 2)
    elseif a.bottom then y = CH - h - a.bottom
    else y = a.top or 0 end
    return x, y, w, h
end

-- Toasts default to the RIGHT side (fixed 640x480 virtual canvas, Scaleform scales it to any resolution).
Ess.UI.TOAST_W = Ess.UI.TOAST_W or 160
Ess.UI.TOAST_H = Ess.UI.TOAST_H or 22
Ess.UI.TOAST_GAP = Ess.UI.TOAST_GAP or 25
-- TOAST_X is deliberately left UNSET. The usable width depends on Graphics.GetScreenRatio(),
-- which may not be answerable at OnLoad time, so Ess.UI.Toast resolves it lazily against the
-- real canvas. Setting it explicitly still overrides, exactly as before.
Ess.UI.TOAST_Y = Ess.UI.TOAST_Y or 150
Ess.UI.TOAST_SLOTS = Ess.UI.TOAST_SLOTS or 3
Ess.UI.TOAST_TTL = Ess.UI.TOAST_TTL or 4

local TICK = 0.05
Ess.UI._WARMUP = 8
-- held-arrow auto-repeat pacing (the Ess.UI.KEYS scroll axis): wait REPEAT_DELAY seconds before the first
-- auto-move, then fire one every REPEAT_RATE while the key stays physically down. Overridable like the
-- other Ess.UI.* tunables above.
Ess.UI.REPEAT_DELAY = Ess.UI.REPEAT_DELAY or 0.35
Ess.UI.REPEAT_RATE  = Ess.UI.REPEAT_RATE  or 0.06

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

-- ============================ the shared runtime =========================
--
-- One fullscreen FlashWidget hosting ess_ui.gfx, shared by every retargeted widget. Each
-- Ess.UI widget becomes a container clip INSIDE that movie, addressed by a string id, so
-- N widgets cost one movie load instead of N.
--
-- Two problems this solves that the per-widget movies had:
--
--   * Async load. SetSwfFile returns before the movie exists, so early calls are dropped.
--     uilib's answer was to re-send state 8 times and hope. Here every call before the
--     load callback fires is QUEUED and flushed in order once it does -- nothing is
--     dropped and nothing is sent twice.
--   * Capacity. The movie builds rows on demand, so the old fixed slot counts (8 panel
--     lines, 3 toasts, 5 chat lines) are gone.
--
-- The load callback is unverified on this engine as of writing, so there is a timeout
-- fallback: if it hasn't fired by RT_LOAD_TIMEOUT, the queue is flushed anyway. A UI that
-- appears slightly late is recoverable; one that never appears is not.

local RT_LOAD_TIMEOUT = 3.0

S.rt = S.rt or nil        -- { gfx=, ready=bool, queue={}, ids={} }

function Ess.UI._rtReady()
    return S.rt ~= nil and S.rt.ready == true
end

local function rtFlush()
    local rt = S.rt
    if not rt then return end
    local q = rt.queue
    rt.queue = {}
    for i = 1, #q do
        Ess.Gfx.call(rt.gfx, q[i][1], q[i][2])
    end
end

-- Marks the runtime live, pushes the theme, then flushes anything queued. Idempotent, so
-- the load callback and the timeout fallback can both call it safely.
local function rtBecomeReady(why)
    local rt = S.rt
    if not rt or rt.ready then return end
    rt.ready = true
    -- The theme has to land before the queued widget calls, or the first draw uses
    -- defaults and then visibly restyles.
    if Ess.UI.Theme and Ess.UI.Theme._push then
        Ess.UI.Theme._push(function(fn, args) Ess.Gfx.call(rt.gfx, fn, args) end)
    end
    rtFlush()
    Ess.Log("UI runtime ready (" .. tostring(why) .. ")")
end

-- Builds the shared runtime widget on first use. Fullscreen, because widgets position
-- themselves inside the movie's own 640x480 canvas rather than via the widget rectangle.
local function rtEnsure()
    if S.rt and S.rt.gfx then return S.rt end
    S.rt = { gfx = nil, ready = false, queue = {}, ids = {} }
    local gfx = Ess.Gfx.widget(Ess.UI.FILES.runtime, 0, 0, 640, 480, function()
        rtBecomeReady("load callback")
    end)
    if not gfx then
        Ess.Log("UI runtime: FAILED to build the shared widget (is ess_ui.gfx injected?)")
        S.rt = nil
        return nil
    end
    S.rt.gfx = gfx
    -- movie -> Lua. Registered immediately rather than inside the load callback: these are
    -- host-side registrations on the widget, not on the movie, so they survive the load and
    -- catch anything the movie sends afterwards.
    Ess.Gfx.onEvent(gfx, "essuiMetrics", function(v)
        -- "<id>:x=..;y=..;w=..;h=..;rows=..;kind=.."
        local s = tostring(v)
        local wid = s:match("^([^:]+):")
        if not wid then return end
        local t = {}
        for k, val in s:gmatch("(%w+)=([%-%w]+)") do t[k] = tonumber(val) or val end
        local cb = S.rt and S.rt.metricsCb and S.rt.metricsCb[wid]
        if cb then
            S.rt.metricsCb[wid] = nil
            pcall(cb, t.w, t.h, t)
        end
    end)
    -- EVERY event name the movie can send has to be registered HERE, up front.
    -- Registering a new name on an already-loaded widget does not bind: Metrics
    -- (registered here) delivered fine while Diag and ScreenInfo (registered later,
    -- from a test) silently never arrived. Matches how the game's own code does it --
    -- it registers all its SetFlashEventHandlers inside the SetSwfFile load callback.
    Ess.Gfx.onEvent(gfx, "essui", function(v)
        S.rt.lastDiag = tostring(v)
        Ess.Log("UI runtime diag: " .. tostring(v))
    end)
    Ess.Gfx.onEvent(gfx, "essuiScreen", function(v)
        S.rt.screen = tostring(v)
        Ess.Log("UI runtime screen: " .. tostring(v))
    end)
    Ess.Gfx.onEvent(gfx, "essuiRow", function(v)
        -- "<id>:<rowIndex>" from an opt-in mouse handler inside the movie
        local s = tostring(v)
        local wid, idx = s:match("^([^:]+):(%d+)$")
        if not wid then return end
        local cb = S.rt and S.rt.rowCb and S.rt.rowCb[wid]
        if cb then pcall(cb, tonumber(idx)) end
    end)
    Ess.Gfx.setVisible(gfx, true)
    -- Fallback in case the load callback never fires on this engine.
    local id = "Ess.UI.rtLoadTimeout"
    local waited = 0
    Ess.Loop.start(id, 0.1, function()
        waited = waited + 0.1
        if Ess.UI._rtReady() then return false end
        if waited >= RT_LOAD_TIMEOUT then
            rtBecomeReady("timeout fallback -- load callback did not fire")
            return false
        end
        return true
    end)
    return S.rt
end

-- Call into the runtime movie. Queues until the movie is loaded.
function Ess.UI._rtcall(fn, args)
    local rt = rtEnsure()
    if not rt then return false end
    if not rt.ready then
        rt.queue[#rt.queue + 1] = { fn, args or {} }
        return true
    end
    return Ess.Gfx.call(rt.gfx, fn, args or {})
end

-- Ask the movie for a widget's ACTUAL laid-out box. Async, because the answer comes back
-- through the movie -> Lua event channel: `cb(w, h, all)` where `all` also carries x, y,
-- rows and kind.
--
-- Worth having rather than recomputing in Lua: panels auto-fit, so their height depends on
-- the theme's rowHeight/titleHeight/padding and on how many lines are populated. Any Lua
-- copy of that arithmetic is a second source of truth waiting to drift.
function Ess.UI._rtMetrics(id, cb)
    local rt = rtEnsure()
    if not rt then return false end
    rt.metricsCb = rt.metricsCb or {}
    if cb then rt.metricsCb[id] = cb end
    return Ess.UI._rtcall("Metrics", { id })
end

-- Ask the movie where its canvas edges actually are, then hand the raw report to `cb`.
-- Answers asynchronously through the pre-registered essuiScreen handler.
function Ess.UI._rtScreen(cb)
    local rt = rtEnsure()
    if not rt then return false end
    rt.screen = nil
    Ess.UI._rtcall("ScreenInfo", {})
    if cb then
        -- one short poll: the reply comes back on the movie's next frame
        Ess.Loop.start("Ess.UI.screenProbe", 0.1, function()
            if rt.screen then pcall(cb, rt.screen); return false end
            return true
        end)
    end
    return true
end

-- Last diagnostic line the movie sent (Diag/GradTest report through this).
function Ess.UI._rtDiag() return S.rt and S.rt.lastDiag end

-- Register a row-click callback for a runtime widget (opt-in mouse only).
function Ess.UI._rtOnRow(id, cb)
    local rt = rtEnsure()
    if not rt then return false end
    rt.rowCb = rt.rowCb or {}
    rt.rowCb[id] = cb
    return true
end

-- Unique widget id inside the runtime movie, from a caller-supplied prefix.
function Ess.UI._rtId(prefix)
    local rt = rtEnsure()
    if not rt then return prefix end
    local n = (rt.ids[prefix] or 0) + 1
    rt.ids[prefix] = n
    return prefix .. n
end

-- Attaches the show/hide/destroy trio to a runtime-hosted widget, so retargeted widgets
-- don't each re-implement them against _rtcall.
function Ess.UI._attachRuntimeCommon(o, id)
    o._rtid = id
    o._shown = true
    function o:show()
        Ess.UI._rtcall("Show", { id, 1 })
        o._shown = true
        return self
    end
    function o:hide()
        Ess.UI._rtcall("Show", { id, 0 })
        o._shown = false
        if S.focus == o then S.focus = nil end
        return self
    end
    function o:destroy()
        if S.focus == o then S.focus = nil end
        Ess.UI._rtcall("Destroy", { id })
        -- Drop the runtime id as well as hiding, so the heartbeat's liveness check
        -- retires this object from S.live. The per-movie widgets get this by nil-ing
        -- _gfx; without the equivalent here a destroyed runtime widget stayed on the
        -- live list forever and kept being serviced.
        o._rtid = nil
        o._destroyed = true
        return self
    end
    function o:focus() Ess.UI.Focus(o); return self end
    function o:blur() if S.focus == o then S.focus = nil end return self end
    -- Nothing to warm up any more: calls made before the movie loads are queued rather
    -- than dropped, so there is no state to re-send.
    function o:_repaint() end
    return o
end

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
    -- A focused widget is key-servicable if it owns a FlashWidget (per-movie widgets) OR an
    -- id inside the shared runtime (retargeted ones). Testing only _gfx silently skipped key
    -- delivery for every runtime-hosted widget -- the list rendered perfectly and simply
    -- never moved, because _keyvk was never called at all.
    if f and f._keyvk and (f._gfx or f._rtid) and f._shown ~= false then
        local input = Ess.Input.poll()
        local shift = input.down(0x10)
        for _, vk in ipairs(input.pressed) do
            if S.focus ~= f then break end          -- an action changed focus mid-drain: stop feeding the old widget
            f:_keyvk(vk, shift)
        end
        -- HELD-KEY AUTO-REPEAT (scroll axis only): hold Up/Down to keep moving through a list after a short
        -- initial delay, like an OS text cursor. Only up/down repeat -- enter/esc/left/right stay discrete
        -- (you never want "pick"/"back" to machine-gun off a stuck key). The first move already fired above
        -- via the edge buffer; this re-fires _keyvk while the key stays physically down.
        if S.focus == f then
            local dnK, upK = Ess.UI.KEYS.down, Ess.UI.KEYS.up
            local heldVk = (input.down(dnK) and dnK) or (input.down(upK) and upK) or nil
            if heldVk then
                if S._repVk ~= heldVk then
                    S._repVk, S._repCd = heldVk, Ess.UI.REPEAT_DELAY    -- newly held: arm the initial delay
                else
                    S._repCd = S._repCd - dt
                    if S._repCd <= 0 then
                        f:_keyvk(heldVk, shift)
                        S._repCd = Ess.UI.REPEAT_RATE
                    end
                end
            else
                S._repVk = nil
            end
        end
    else
        S._repVk = nil
    end
    if S.live then
        for i = #S.live, 1, -1 do
            local o = S.live[i]
            -- Liveness: a widget is alive if it owns a FlashWidget (the per-movie widgets)
            -- OR an id inside the shared runtime (the retargeted ones). Testing only _gfx
            -- would drop every runtime-hosted widget from this list on its first tick,
            -- silently killing auto-hide and size easing for them.
            if not o or (not o._gfx and not o._rtid) then
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
                -- auto-hide countdown (opt-in per widget via o._autoHide; used by Ess.UI.Chat's autoHide).
                -- Frozen and refreshed while the widget holds input focus, so a window never fades out from
                -- under someone mid-interaction -- the countdown only runs once it's a passive display again.
                if o._hideIn then
                    if S.focus == o then o._hideIn = o._autoHide
                    elseif o._shown == false then o._hideIn = nil
                    else
                        o._hideIn = o._hideIn - dt
                        if o._hideIn <= 0 then o._hideIn = nil; pcall(function() o:hide() end) end
                    end
                end
            end
        end
    end
    if S.toasts then
        for i = 1, Ess.UI.TOAST_SLOTS do
            local t = S.toasts[i]
            if t and t.ttl then
                -- No warm-up re-paint here any more: a runtime-hosted toast's calls are
                -- queued until the movie loads, so its text cannot be dropped.
                if t.warmup and t.warmup > 0 and t.repaint then
                    t.warmup = t.warmup - 1; pcall(t.repaint)
                end
                t.ttl = t.ttl - dt
                if t.ttl <= 0 then
                    t.ttl = nil
                    if t._rtid then Ess.UI._rtcall("Show", { t._rtid, 0 })
                    elseif t._gfx then Ess.Gfx.setVisible(t._gfx, false) end
                end
            end
        end
    end
    -- fourth and last of the _gfx gates that had to widen for runtime-hosted widgets:
    -- without this the caret in Ess.UI.Input / Ess.UI.Chat simply never blinks
    if f and f._isInput and (f._gfx or f._rtid) and f._shown ~= false then
        f._blinkClock = (f._blinkClock or 0) + dt
        if f._blinkClock >= 0.35 then f._blinkClock = 0; f._blink = not f._blink; f:_echo() end
    end
end

local function needsTick()
    if S.focus then return true end
    if S.live then
        for _, o in ipairs(S.live) do
            -- same widening as the live-list and focus checks: runtime-hosted widgets have
            -- no _gfx, and an auto-hiding one still needs the heartbeat awake to count down
            if (o._gfx or o._rtid) and ((o._warmup and o._warmup > 0) or (o._cur and o._tgt and o._cur ~= o._tgt) or o._hideIn) then
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
    if not uiTimer then uiTimer = Ess.Time.clock() end
    Ess.Loop.start("Ess.UI.heartbeat", TICK, function()
        local dt = uiTimer:delta()
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
-- The shared runtime widget belongs to the previous world and is gone with it. Dropping the
-- handle makes the next Ess.UI call rebuild it (and re-push the theme) from scratch.
S.rt = nil
if S.menus then for _, rt in pairs(S.menus) do rt.list = nil; rt.open = false; rt.menu = nil end end
