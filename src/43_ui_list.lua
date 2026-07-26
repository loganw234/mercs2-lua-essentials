-- Ess/43_ui_list.lua -- Ess.UI.List: the raw scrollable list widget (section headers the cursor
-- skips, scrollbar, body that auto-resizes to content).
--
-- Ess.UI.List{ x, y, w, h, rows, title, crumb, hint, items, empty, focus, onChoose, onBack, onSelect }
--   items = { {header="SECTION"}, {label="Entry", any=yourdata}, ... }
--   :items(t)  :selected()->item,i  :select(i)  :paint()
--   :title(s)  :crumb(s)  :hint(s)
--   onChoose(item,i,list)  onSelect(item,i,list)  onBack(list)
--   plus the common :show() :hide() :focus() :blur() :destroy() from 42_ui_engine.lua
--
-- RETARGETED onto the shared ess_ui.gfx runtime (see 42_ui_engine.lua). Unchanged: the public
-- API, the item format, the header-skipping cursor, the wrap-around at both ends, the
-- key bindings (up/down move, enter/right choose, left/esc back) and the whole focus model.
-- Navigation is still driven by the Lua heartbeat's key polling -- deliberately, so this
-- change is only about who DRAWS.
--
-- WINDOWED ON PURPOSE. The list shows `rows` rows at a time and indexes into the item table
-- with an offset, rather than creating a clip per item. That is O(visible) instead of
-- O(total), which matters: a real user menu in the wild has 831 entries. The old fixed
-- VIS = 10 is now `opts.rows` (default 10), so a taller list can show more -- a widening,
-- not a change.
--
-- Gone: the pixel constants (TOP/PITCH/TRH/BODY) that tied scrollbar and resize maths to
-- ui_list.gfx's exact artwork. The movie now derives both from the theme's own metrics, so
-- restyling rowHeight no longer silently desynchronises the scrollbar.

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

function Ess.UI.List(opts)
    opts = opts or {}
    local o = {}
    local id = Ess.UI._rtId("list")
    local x = opts.x or 40
    local y = opts.y or 60
    local w = opts.w or 320

    Ess.UI._attachRuntimeCommon(o, id)
    Ess.UI._register(o)

    local VIS = tonumber(opts.rows) or 10
    if VIS < 1 then VIS = 1 end

    o._items, o._sel, o._off = {}, 1, 0
    o._title, o._crumb, o._hint = opts.title, opts.crumb, opts.hint
    o.onChoose, o.onBack, o.onSelect = opts.onChoose, opts.onBack, opts.onSelect

    Ess.UI._rtcall("Rows", { id, x, y, w, 0 })
    Ess.UI._rtcall("RowsMeta", { id, tostring(opts.crumb or ""), tostring(opts.hint or "") })
    if opts.title then Ess.UI._rtcall("PanelTitle", { id, tostring(opts.title) }) end
    if opts.empty then Ess.UI._rtcall("RowsEmpty", { id, tostring(opts.empty) }) end

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

        -- How many row slots the movie needs: the window, or fewer if the data is
        -- shorter. The movie pools and reuses them, so shrinking is free.
        local shown = n
        if shown > VIS then shown = VIS end
        if shown < 0 then shown = 0 end
        Ess.UI._rtcall("RowsFit", { id, shown })

        for i = 0, shown - 1 do
            local it = o._items[o._off + i + 1]
            if not it then
                Ess.UI._rtcall("RowSet", { id, i, "", false })
            elseif it.header then
                Ess.UI._rtcall("RowSet", { id, i, hdr_text(it), true })
            else
                Ess.UI._rtcall("RowSet", { id, i, tostring(it.label or "?"), false })
            end
        end

        if n == 0 or not selectable(o._sel) then
            Ess.UI._rtcall("RowSelect", { id, -1 })
        else
            Ess.UI._rtcall("RowSelect", { id, (o._sel - 1) - o._off })
        end

        -- Data offsets, not pixels -- the movie works out the thumb.
        Ess.UI._rtcall("RowsScroll", { id, o._off, n, VIS })
        return self
    end

    function o:title(s) o._title = s; Ess.UI._rtcall("PanelTitle", { id, tostring(s) }) return self end
    function o:crumb(s)
        o._crumb = s
        Ess.UI._rtcall("RowsMeta", { id, tostring(s or ""), tostring(o._hint or "") })
        return self
    end
    function o:hint(s)
        o._hint = s
        Ess.UI._rtcall("RowsMeta", { id, tostring(o._crumb or ""), tostring(s or "") })
        return self
    end

    function o:items(t)
        o._items = t or {}
        o._sel = nearest(1, 1) or 1
        o._off = 0
        return o:paint()
    end
    function o:selected() return o._items[o._sel], o._sel end
    function o:select(i) if selectable(i) then o._sel = i; o:paint() end return self end

    function o:measure(cb) Ess.UI._rtMetrics(id, cb) return self end

    -- Unchanged from the pre-retarget version: same keys, same wrap-around, same callbacks.
    function o:_keyvk(vk)
        local k = Ess.UI.navName(vk); if not k then return end
        if k == "up" or k == "down" then
            local d = (k == "up") and -1 or 1
            local t = nearest(o._sel + d, d)
            -- rolled off an end -> wrap around to the other end (down at the bottom jumps to the top, up at
            -- the top jumps to the bottom). nearest() skips section headers, so the wrap target is real too.
            if not t then t = (d == 1) and nearest(1, 1) or nearest(#o._items, -1) end
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

    o:items(opts.items or {})
    if opts.focus then o:focus() end
    Ess.UI._ensureTick()
    return o
end
