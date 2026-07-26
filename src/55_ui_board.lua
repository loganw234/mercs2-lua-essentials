-- Ess/55_ui_board.lua -- Ess.UI.Board: a two-pane board -- a scrolling list on the left + a
-- details pane on the right (category line, reward lines, objective lines, a progress bar +
-- progress text). Ess.Contract's board UI is built on this.
--
-- local b = Ess.UI.Board{ x, y, w, h, rows, title, hint, items, focus, onSelect, onChoose, onBack }
--   b:items({ {header="SECTION"}, {label="Entry", any=data}, ... })   -- same shape as Ess.UI.List
--   b:detail({ category="OIL FIELD", rewards={"$5000","Fuel +200"},
--              objectives={"Destroy 3 tanks","Reach the LZ"}, progress=0.4, progressText="2/5" })
--   b:title(s)  b:hint(s)   -- onSelect(item,i,board) fires on every move so you can refresh :detail
--
-- RETARGETED, and RE-BUILT AS A COMPOSITION. The board is now literally an Ess.UI.List beside
-- an Ess.UI.Panel with an Ess.UI.Bar under it -- three existing widgets on the shared runtime,
-- rather than a fourth bespoke movie.
--
-- That deletes the copy of List's windowing logic this file used to carry (selectable/nearest/
-- the offset maths/the scrollbar arithmetic, all duplicated with slightly different constants).
-- One consequence worth knowing: fixes and features in List now reach Board automatically --
-- the wrap-around at both ends, for instance, which this file's copy did not have.
--
-- Widened: the old contracts.gfx had 4 reward fields and 8 objective fields, so longer lists
-- were silently cut. There is no cap now.

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

function Ess.UI.Board(opts)
    opts = opts or {}
    local o = {}

    local x = opts.x or 60
    local y = opts.y or 60
    local w = opts.w or 660
    local h = opts.h or 420
    local rows = tonumber(opts.rows) or 12
    local listW = math.floor(w * 0.42)
    local gap = 10
    local detailX = x + listW + gap
    local detailW = w - listW - gap

    o.onSelect, o.onChoose, o.onBack = opts.onSelect, opts.onChoose, opts.onBack

    -- Left pane. Not focused itself -- the Board owns focus and forwards keys, so exactly
    -- one object is in the engine's focus slot (the kit's one-focus rule).
    o._list = Ess.UI.List{
        x = x, y = y, w = listW, rows = rows,
        title = opts.title, hint = opts.hint,
        onChoose = function(it, i) if o.onChoose then pcall(o.onChoose, it, i, o) end end,
        onBack = function() if o.onBack then pcall(o.onBack, o) end end,
        onSelect = function(it, i) if o.onSelect then pcall(o.onSelect, it, i, o) end end,
    }
    -- Right pane.
    o._detail = Ess.UI.Panel{ x = detailX, y = y, w = detailW, title = "DETAILS" }
    o._bar = Ess.UI.Bar{ x = detailX, y = y + h - 44, w = detailW, h = 36, label = "", value = 0 }

    -- The Board is the focusable object; it delegates every key to the list.
    o._rtid = o._list._rtid       -- so the engine's liveness/focus checks see a runtime widget
    o._shown = true
    Ess.UI._register(o)

    function o:_keyvk(vk, shift) o._list:_keyvk(vk, shift) end

    function o:items(t) o._list:items(t) return self end
    function o:selected() return o._list:selected() end
    function o:select(i) o._list:select(i) return self end
    function o:title(s) o._list:title(s) return self end
    function o:hint(s) o._list:hint(s) return self end
    function o:paint() o._list:paint() return self end

    -- The details pane. Laid out as a flat run of lines: category, blank, rewards,
    -- blank, objectives. No caps on either list.
    function o:detail(d)
        d = d or {}
        local lines = {}
        if d.category then lines[#lines + 1] = tostring(d.category) end
        if d.rewards and #d.rewards > 0 then
            if #lines > 0 then lines[#lines + 1] = "" end
            lines[#lines + 1] = "REWARDS"
            for _, r in ipairs(d.rewards) do lines[#lines + 1] = "  " .. tostring(r) end
        end
        if d.objectives and #d.objectives > 0 then
            if #lines > 0 then lines[#lines + 1] = "" end
            lines[#lines + 1] = "OBJECTIVES"
            for _, ob in ipairs(d.objectives) do lines[#lines + 1] = "  " .. tostring(ob) end
        end
        o._detail:clear()
        for i, line in ipairs(lines) do o._detail:line(i - 1, line) end
        if d.title then o._detail:title(tostring(d.title)) end
        o._bar:set(tonumber(d.progress) or 0)
        o._bar:label(tostring(d.progressText or ""))
        return self
    end

    function o:show()
        o._list:show(); o._detail:show(); o._bar:show()
        o._shown = true
        return self
    end
    function o:hide()
        o._list:hide(); o._detail:hide(); o._bar:hide()
        o._shown = false
        if Ess.UI._S.focus == o then Ess.UI._S.focus = nil end
        return self
    end
    function o:destroy()
        o._list:destroy(); o._detail:destroy(); o._bar:destroy()
        if Ess.UI._S.focus == o then Ess.UI._S.focus = nil end
        return self
    end
    function o:focus() Ess.UI.Focus(o); return self end
    function o:blur() if Ess.UI._S.focus == o then Ess.UI._S.focus = nil end return self end
    function o:_repaint() end

    if opts.items then o:items(opts.items) end
    if opts.focus then o:focus() end
    Ess.UI._ensureTick()
    return o
end
