-- Ess/43_ui_list.lua -- Ess.UI.List: the raw scrollable list widget (10 visible rows, section headers
-- the cursor skips, scrollbar, body that auto-resizes to content). Direct port of uilib.lua's UI.List.
--
-- Ess.UI.List{ x, y, title, crumb, hint, items, empty, focus, onChoose, onBack, onSelect }
--   items = { {header="SECTION"}, {label="Entry", any=yourdata}, ... }
--   :items(t)  :selected()->item,i  :select(i)  :paint()
--   :title(s)  :crumb(s)  :hint(s)
--   onChoose(item,i,list)  onSelect(item,i,list)  onBack(list)
--   plus the common :show() :hide() :focus() :blur() :destroy() from 42_ui_engine.lua

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

function Ess.UI.List(opts)
    opts = opts or {}
    local o = {}
    o._gfx = Ess.Gfx.widget(Ess.UI.FILES.list, opts.x or 40, opts.y or 60, opts.w or 320, opts.h or 360)
    o._shown = true
    local function c(fn, args) Ess.Gfx.call(o._gfx, fn, args) end
    o._call = c
    Ess.UI._attachCommon(o); Ess.UI._register(o)
    o._cur, o._tgt = 100, 100
    o._setsize = function(v) c("SetSize", { v }) end
    o._items, o._sel, o._off = {}, 1, 0
    o._title, o._crumb, o._hint = opts.title, opts.crumb, opts.hint
    o.onChoose, o.onBack, o.onSelect = opts.onChoose, opts.onBack, opts.onSelect

    local VIS, TOP, PITCH, TRH, BODY = 10, 64, 24, 232, 296

    local function selectable(i) local it = o._items[i]; return it ~= nil and not it.header end
    local function nearest(from, dir)
        local i = from
        while i >= 1 and i <= #o._items do
            if selectable(i) then return i end
            i = i + dir
        end
        return nil
    end
    local function hdr_text(it)
        if it.header == true then return tostring(it.label or "") end
        return tostring(it.header)
    end

    function o:paint()
        local n = #o._items
        if n > 0 then
            if not selectable(o._sel) then o._sel = nearest(o._sel, 1) or nearest(o._sel, -1) or 1 end
            local s0 = o._sel - 1
            if o._off > s0 then o._off = s0 end
            if s0 > o._off + VIS - 1 then o._off = s0 - VIS + 1 end
            if o._off < 0 then o._off = 0 end
        else
            o._off = 0
        end
        for i = 0, VIS - 1 do
            local it = o._items[o._off + i + 1]
            if not it then c("SetRow", { i, "" }); c("SetHdr", { i, "" })
            elseif it.header then c("SetHdr", { i, hdr_text(it) }); c("SetRow", { i, "" })
            else c("SetRow", { i, tostring(it.label or "?") }); c("SetHdr", { i, "" }) end
        end
        if n == 0 then
            c("SetHdr", { 0, tostring(opts.empty or "EMPTY") }); c("SetSelected", { -1 }); c("SetScroll", { 0, 0 })
        else
            if selectable(o._sel) then c("SetSelected", { (o._sel - 1) - o._off }) else c("SetSelected", { -1 }) end
            if n > VIS then
                local th = TRH * VIS / n; if th < 16 then th = 16 end
                local ty = TOP + (TRH - th) * o._off / (n - VIS)
                c("SetScroll", { math.floor(ty), math.floor(th) })
            else
                c("SetScroll", { 0, 0 })
            end
        end
        local shown = n; if shown > VIS then shown = VIS end; if shown < 1 then shown = 1 end
        Ess.UI._setTarget(o, 100 * (PITCH * shown + 12) / BODY)
        return self
    end

    function o:_repaint()
        if o._title then c("SetTitle", { tostring(o._title) }) end
        if o._crumb then c("SetCrumb", { tostring(o._crumb) }) end
        if o._hint then c("SetHint", { tostring(o._hint) }) end
        o:paint()
        if o._setsize then o._setsize(o._cur) end
    end

    function o:title(s) o._title = s; c("SetTitle", { tostring(s) }) return self end
    function o:crumb(s) o._crumb = s; c("SetCrumb", { tostring(s) }) return self end
    function o:hint(s)  o._hint = s;  c("SetHint",  { tostring(s) }) return self end
    function o:items(t)
        o._items = t or {}
        o._sel = nearest(1, 1) or 1
        o._off = 0
        return o:paint()
    end
    function o:selected() return o._items[o._sel], o._sel end
    function o:select(i) if selectable(i) then o._sel = i; o:paint() end return self end

    function o:_keyvk(vk)
        local k = Ess.UI.navName(vk); if not k then return end
        if k == "up" or k == "down" then
            local d = (k == "up") and -1 or 1
            local t = nearest(o._sel + d, d)
            if t and t ~= o._sel then
                o._sel = t; o:paint()
                if o.onSelect then pcall(o.onSelect, o._items[o._sel], o._sel, o) end
            end
        elseif k == "enter" or k == "right" then
            local it = o._items[o._sel]
            if it and not it.header and o.onChoose then pcall(o.onChoose, it, o._sel, o) end
        elseif k == "left" or k == "esc" then
            if o.onBack then pcall(o.onBack, o) end
        end
    end

    if o._title then c("SetTitle", { tostring(o._title) }) end
    if o._crumb then c("SetCrumb", { tostring(o._crumb) }) end
    if o._hint then c("SetHint", { tostring(o._hint) }) end
    o:items(opts.items or {})
    o._cur = o._tgt; o._setsize(o._cur)
    o._warmup = Ess.UI._WARMUP
    if opts.focus then o:focus() end
    Ess.UI._ensureTick()
    return o
end
