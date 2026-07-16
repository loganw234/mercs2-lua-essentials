-- Ess/51_ui_board.lua -- Ess.UI.Board: a two-pane board (contracts.gfx): a scrolling list on the left +
-- a details pane on the right (category line, up to 4 reward lines, up to 8 objective lines, a progress
-- bar + progress text). Direct port of uilib.lua's UI.Board -- Ess.Contract's own board UI (the contract
-- selection screen, intermission shops, etc) is built on this, not a separate hand-rolled UI.
--
-- local b = Ess.UI.Board{ x, y, title, hint, items, focus, onSelect, onChoose, onBack }
--   b:items({ {header="SECTION"}, {label="Entry", any=data}, ... })   -- same item shape as Ess.UI.List
--   b:detail({ category="OIL FIELD", rewards={"$5000","Fuel +200"},
--              objectives={"Destroy 3 tanks","Reach the LZ"}, progress=0.4, progressText="2/5" })
--   b:title(s)  b:hint(s)   -- onSelect(item,i,board) fires on every move so you can refresh :detail

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

function Ess.UI.Board(opts)
    opts = opts or {}
    local o = {}
    o._gfx = Ess.Gfx.widget(Ess.UI.FILES.board, opts.x or 60, opts.y or 60, opts.w or 660, opts.h or 420)
    o._shown = true
    local function c(fn, args) Ess.Gfx.call(o._gfx, fn, args) end
    o._call = c
    Ess.UI._attachCommon(o); Ess.UI._register(o)
    o._items, o._sel, o._off = {}, 1, 0
    o._titleStr, o._hintStr = opts.title, opts.hint
    o.onSelect, o.onChoose, o.onBack = opts.onSelect, opts.onChoose, opts.onBack

    local VIS, TOP, PITCH, TRK_Y, TRK_H = 12, 64, 26, 64, 312

    local function selectable(i) local it = o._items[i]; return it ~= nil and not it.header end
    local function nearest(from, dir)
        local i = from
        while i >= 1 and i <= #o._items do
            if selectable(i) then return i end
            i = i + dir
        end
        return nil
    end
    local function fireSelect()
        if o.onSelect then pcall(o.onSelect, o._items[o._sel], o._sel, o) end
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
            elseif it.header then c("SetHdr", { i, tostring(it.header) }); c("SetRow", { i, "" })
            else c("SetRow", { i, tostring(it.label or "?") }); c("SetHdr", { i, "" }) end
        end
        if n == 0 then
            c("SetHdr", { 0, tostring(opts.empty or "EMPTY") }); c("SetSelected", { -1 }); c("SetScroll", { 0, 0 })
        else
            if selectable(o._sel) then c("SetSelected", { (o._sel - 1) - o._off }) else c("SetSelected", { -1 }) end
            if n > VIS then
                local th = TRK_H * VIS / n; if th < 18 then th = 18 end
                local ty = TRK_Y + (TRK_H - th) * o._off / (n - VIS)
                c("SetScroll", { math.floor(ty), math.floor(th) })
            else
                c("SetScroll", { 0, 0 })
            end
        end
        return self
    end

    function o:title(s) o._titleStr = s; c("SetTitle", { tostring(s) }) return self end
    function o:hint(s)  o._hintStr = s;  c("SetHint",  { tostring(s) }) return self end
    function o:detail(d)
        d = d or {}
        c("SetCat", { tostring(d.category or " ") })
        local rw = d.rewards or {}
        for i = 0, 3 do c("SetReward", { i, tostring(rw[i + 1] or " ") }) end
        local ob = d.objectives or {}
        for i = 0, 7 do c("SetObj", { i, tostring(ob[i + 1] or " ") }) end
        c("SetBar", { math.floor((tonumber(d.progress) or 0) * 100) })
        c("SetProg", { tostring(d.progressText or " ") })
        o._detail = d
        return self
    end
    function o:items(t)
        o._items = t or {}
        o._sel = nearest(1, 1) or 1
        o._off = 0
        o:paint()
        fireSelect()
        return self
    end
    function o:selected() return o._items[o._sel], o._sel end
    function o:select(i) if selectable(i) then o._sel = i; o:paint(); fireSelect() end return self end

    function o:_keyvk(vk)
        local k = Ess.UI.navName(vk); if not k then return end
        if k == "up" or k == "down" then
            local d = (k == "up") and -1 or 1
            local t = nearest(o._sel + d, d)
            if t and t ~= o._sel then o._sel = t; o:paint(); fireSelect() end
        elseif k == "enter" or k == "right" then
            local it = o._items[o._sel]
            if it and not it.header and o.onChoose then pcall(o.onChoose, it, o._sel, o) end
        elseif k == "left" or k == "esc" then
            if o.onBack then pcall(o.onBack, o) end
        end
    end

    function o:_repaint()
        if o._titleStr then c("SetTitle", { tostring(o._titleStr) }) end
        if o._hintStr then c("SetHint", { tostring(o._hintStr) }) end
        o:paint()
        if o._detail then o:detail(o._detail) end
    end

    if o._titleStr then c("SetTitle", { tostring(o._titleStr) }) end
    if o._hintStr then c("SetHint", { tostring(o._hintStr) }) end
    o:items(opts.items or {})
    o:detail(opts.detail or {})
    o._warmup = Ess.UI._WARMUP
    if opts.focus then o:focus() end
    Ess.UI._ensureTick()
    return o
end
