-- Ess/40_gfx.lua -- Ess.Gfx: the raw FlashWidget primitives (Ess.Raw tier for custom-UI work).
-- Ess.Menu/Ess.UI (Core/Easy tiers) alias uilib's already-engine-verified widget kit instead of
-- reimplementing it -- see src/99_adopt.lua. This file is only the boilerplate every one of uilib.lua,
-- contracts.lua, ForgeCam, and ForgeMenu independently hand-rolled around MrxGuiBase.FlashWidget.
--
-- API:
--   Ess.Gfx.widget(file, x, y, w, h) -> widget | nil     widget = { raw = <FlashWidget>, shown = bool }
--   Ess.Gfx.call(widget, fn, args) -> ok
--   Ess.Gfx.onEvent(widget, name, cb) -> ok
--   Ess.Gfx.setVisible(widget, bool)
--   Ess.Gfx.warmupRerender(rt, ticks)
--   Ess.Gfx.menuNav(widget, keys) -> stop()

import("MrxGuiBase")
import("MrxGuiManager")

local Ess = _G.Ess
Ess.Gfx = Ess.Gfx or {}

-- Ess.Gfx.widget(file, x, y, w, h) -> widget | nil
-- Builds+shows a FlashWidget from a deployed .gfx asset (`file`, no extension needed at this layer --
-- pass whatever SetSwfFile itself expects). Every one of uilib.lua/contracts.lua/ForgeCam/ForgeMenu hand-
-- rolled this same construct-set_location-load-add-show sequence separately.
--
-- KNOWN BUG THIS FIXES AT THE SOURCE: `FlashWidget:SetLocation` takes CORNER coordinates
-- (x1, y1, x2, y2), NOT (x, y, width, height). uilib.lua v2.1 found and fixed this
-- (`SetLocation(x, y, x+w, y+h)`); `contracts.lua`'s own `make_widget`/`build()` in the SAME repo never
-- got the fix and still passes `SetLocation(x, y, w, h)` directly -- a currently-shipping instance of an
-- already-solved bug (renders slightly small rather than crashing, which is exactly why it went
-- unnoticed). Doing the x+w/y+h math here, once, makes it structurally impossible to get wrong again.
function Ess.Gfx.widget(file, x, y, w, h)
    local okp, player = pcall(Player.GetLocalPlayer)
    local ok, wg = pcall(function()
        local wg = MrxGuiBase.FlashWidget:new()
        if okp and player then pcall(function() wg:SetOwner(player) end) end
        wg:SetLocation(x, y, x + w, y + h)
        wg:SetSwfFile(file, nil, nil)
        MrxGuiBase.AddWidget(wg)
        if okp and player then pcall(function() MrxGuiManager.AddWidgetToHud(player, wg) end) end
        return wg
    end)
    if not ok or not wg then
        Ess.Log("Gfx.widget: failed to build widget from '" .. tostring(file) .. "'")
        return nil
    end
    return { raw = wg, shown = false }
end

-- Ess.Gfx.call(widget, fn, args) -> ok
-- pcall-wrapped Lua -> movie call (`CallActionScriptCallback`). `args` defaults to {} so callers don't
-- need their own nil-guard for a zero-arg AS2 function.
function Ess.Gfx.call(widget, fn, args)
    if not widget or not widget.raw then return false end
    local ok = pcall(function() widget.raw:CallActionScriptCallback(fn, args or {}) end)
    return ok and true or false
end

-- Ess.Gfx.onEvent(widget, name, cb) -> ok
-- pcall-wrapped movie -> Lua binding (`SetFlashEventHandler`). The native shape is
-- `SetFlashEventHandler(name, function(_, v) ... end, {})` -- a mandatory `(_, v)` two-arg callback plus a
-- mandatory trailing `{}` third argument to the native call itself, both confirmed real and easy to get
-- subtly wrong by hand (custom-ui.md). This hides both: your `cb` just receives `v` directly.
function Ess.Gfx.onEvent(widget, name, cb)
    if not widget or not widget.raw then return false end
    local ok = pcall(function()
        widget.raw:SetFlashEventHandler(name, function(_, v)
            local okc, err = pcall(cb, v)
            if not okc then Ess.Log("Gfx.onEvent '" .. tostring(name) .. "' callback error: " .. tostring(err)) end
        end, {})
    end)
    return ok and true or false
end

-- Ess.Gfx.setVisible(widget, bool)
-- KNOWN BUG THIS FIXES: the getter is `GetVisible()`, not `IsVisible()` (which doesn't exist -- calling
-- it nil-calls and gets silently swallowed by pcall, so nothing visibly breaks, it just never toggles).
-- AND `not w:GetVisible()` is ALSO wrong even with the right name: the getter returns `1`/`0`, and only
-- `nil`/`false` are falsy in Lua, so `not 0` evaluates to `false` -- a naive toggle never flips. Fix: never
-- read the getter back at all. `widget.shown` is this wrapper's own tracked boolean, set only here.
function Ess.Gfx.setVisible(widget, bOn)
    if not widget or not widget.raw then return end
    bOn = bOn and true or false
    pcall(function() widget.raw:SetVisible(bOn) end)
    widget.shown = bOn
end

-- Ess.Gfx.warmupRerender(rt, ticks)
-- CONFIRMED GOTCHA: `SetSwfFile` is asynchronous -- a repaint call made immediately after building the
-- widget can silently drop (the movie hasn't finished loading yet). uilib.lua's fix (WARMUP=8) is to
-- re-run the widget's own repaint a further `ticks` times (default 8) on a short heartbeat after
-- showing it, so at least one of those calls lands after the movie is actually ready.
--
-- `rt` ("repaint thunk") is a zero-arg function that resends whatever state the widget needs to show --
-- the caller supplies it (this helper doesn't know what any given widget's fields even are), typically a
-- closure over `widget` and whatever Ess.Gfx.call arguments it needs to redo. Runs on Ess.Loop at the
-- same 0.05s interval uilib's own heartbeat uses.
function Ess.Gfx.warmupRerender(rt, ticks)
    ticks = ticks or 8
    local remaining = ticks
    local id = "Ess.Gfx.warmupRerender:" .. tostring(rt)
    Ess.Loop.start(id, 0.05, function()
        local ok, err = pcall(rt)
        if not ok then Ess.Log("Gfx.warmupRerender repaint error: " .. tostring(err)) end
        remaining = remaining - 1
        return remaining > 0
    end)
end

-- Ess.Gfx.menuNav(widget, keys) -> stop()
-- A HUD FlashWidget receives no native input of its own -- menu navigation has to be driven from Lua by
-- polling and forwarding into the movie's own compiled AS2 menu logic (custom-ui.md's confirmed pattern:
-- Lua only ever says "up"/"down"/"pick this one" via CallActionScriptCallback("Move"/"Choose", ...), the
-- movie owns selection state and visuals). Built on Ess.Input.poll -- the correct edge-triggered shape,
-- not a raw per-key IsKeyDown loop (see Ess.Input's own doc comment for why that's a real, repeated bug
-- elsewhere in this project).
--
-- keys defaults to {up=0x26 (VK_UP), down=0x28 (VK_DOWN), enter=0x0D (VK_RETURN)} -- override to match
-- UI.KEYS if remapped. Returns a stop() function.
function Ess.Gfx.menuNav(widget, keys)
    keys = keys or { up = 0x26, down = 0x28, enter = 0x0D }
    local id = "Ess.Gfx.menuNav:" .. tostring(widget)
    Ess.Loop.start(id, 0.05, function()
        local input = Ess.Input.poll()
        for _, vk in ipairs(input.pressed) do
            if vk == keys.up then
                Ess.Gfx.call(widget, "Move", { -1 })
            elseif vk == keys.down then
                Ess.Gfx.call(widget, "Move", { 1 })
            elseif vk == keys.enter then
                Ess.Gfx.call(widget, "Choose", {})
            end
        end
        return true
    end)
    return function() Ess.Loop.stop(id) end
end
