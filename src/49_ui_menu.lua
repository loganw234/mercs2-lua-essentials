-- Ess/49_ui_menu.lua -- Ess.UI.Menu: ForgeMenu-style declarative drill-down, rendered on a reused
-- Ess.UI.List. Direct port of uilib.lua's UI.Menu (v2.2) -- the ONE piece in this whole port that needs
-- STRICT backward compatibility: every existing menu script written against uilib's UI.Menu (entry/
-- category/header/switch + the ctx: helpers) must keep working unmodified against Ess.UI.Menu, just
-- swapping which global it's built through.
--
-- Ess.UI.Menu{ title, id, key, x, y, onClose }   (or Ess.UI.Menu("TITLE"))
--   :entry(label, action)        action(ctx)
--   :category(label, buildFn)    buildFn(childBuilder) -- nests freely
--   :header(text)
--   :switch(label, get, set)     a labelled ON/OFF toggle entry
--   :toggle()  :open()  :close()  :isOpen()
--   ctx: x/y/z/yaw/char/player, :hint(msg)  :toast(msg)  :print(msg)  :close()
--        :confirm(text,onYes,onNo)  :ask(prompt,onSubmit,onCancel)  :spawn(template,dist)
--
-- A label may be a function returning a string (live ON/OFF toggles re-render on every action).

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

local function resolveLabel(node)
    local l = node.label
    if type(l) == "function" then local ok, v = pcall(l); l = ok and v or "?" end
    return tostring(l or "?")
end

local MenuBuilder = {}
MenuBuilder.__index = MenuBuilder
function MenuBuilder:entry(label, action)
    if type(action) ~= "function" then
        Ess.Log("UI.Menu entry '" .. tostring(label) .. "' needs a function as 2nd arg")
        action = function() end
    end
    self._children[#self._children + 1] = { label = label, action = action }
    return self
end
function MenuBuilder:header(text)
    self._children[#self._children + 1] = { header = tostring(text) }
    return self
end
-- a labelled ON/OFF toggle entry: get() -> current bool, set(newBool, ctx) applies it. Renders
-- "<label>: ON" / "<label>: OFF" and flips on pick. Saves the dynamic-label boilerplate.
function MenuBuilder:switch(label, get, set)
    self._children[#self._children + 1] = {
        label = function() return tostring(label) .. ": " .. ((get and get()) and "ON" or "OFF") end,
        action = function(ctx) local nv = not (get and get()); if set then set(nv, ctx) end end,
    }
    return self
end
function MenuBuilder:category(label, buildFn)
    local node = { label = label, children = {} }
    self._children[#self._children + 1] = node
    local child = setmetatable({ _children = node.children }, MenuBuilder)
    if type(buildFn) == "function" then buildFn(child) end
    return child
end

local Menu = setmetatable({}, { __index = MenuBuilder })
Menu.__index = Menu

local function menu_ctx(menu)
    local px, py, pz, yaw, char, player = Ess.Player.pose(0)
    local ctx = { x = px, y = py, z = pz, yaw = yaw or 0, char = char, player = player, _menu = menu }
    function ctx:hint(msg)  Ess.UI.Toast(tostring(msg)) end
    function ctx:toast(msg) Ess.UI.Toast(tostring(msg)) end          -- alias of :hint (clearer intent)
    function ctx:print(msg) Ess.Log(tostring(msg)) end
    function ctx:close()    self._menu:close() end
    function ctx:confirm(text, onYes, onNo)                          -- pop a yes/no dialog from a menu action
        Ess.UI.Confirm{ text = text, onResult = function(yes)
            if yes then if onYes then pcall(onYes) end elseif onNo then pcall(onNo) end
        end }
    end
    function ctx:ask(prompt, onSubmit, onCancel)                     -- pop a typed prompt from a menu action
        Ess.UI.Input{ prompt = prompt, onSubmit = onSubmit, onCancel = onCancel }
    end
    function ctx:spawn(template, dist)
        -- Pg.Spawn("") hard-CRASHES the engine (empty name -> null asset in C++), and pcall canNOT catch
        -- a native crash -- only Lua errors. Reject blank templates up front.
        if type(template) ~= "string" or template:match("^%s*$") then
            self:hint("NO TEMPLATE SET"); return nil
        end
        if not px then self:hint("NO PLAYER POSITION"); return nil end
        local sx, sz = px, pz
        if dist and dist ~= 0 then
            local yr = math.rad(yaw or 0)
            sx = px - math.sin(yr) * dist
            sz = pz + math.cos(yr) * dist
        end
        local ok, u = pcall(Pg.Spawn, template, sx, py, sz)
        if ok and u then pcall(Object.SetYaw, u, yaw or 0); return u end
        self:hint("SPAWN FAILED: " .. tostring(template))
        return nil
    end
    return ctx
end

-- Runtime state persists across the OnKey re-run, keyed by menu id, so :toggle() really toggles and the
-- list widget is reused instead of leaked. (The menu OBJECT is rebuilt each run and carries the tree.)
local function menu_rt(id)
    local S = Ess.UI._S
    S.menus = S.menus or {}
    S.menus[id] = S.menus[id] or { open = false }
    return S.menus[id]
end

function Menu:_paint()
    local lvl = self._stack[#self._stack]
    local rows = {}
    for _, node in ipairs(lvl.children) do
        if node.header then rows[#rows + 1] = { header = node.header }
        elseif node.children then rows[#rows + 1] = { label = resolveLabel(node) .. "  >", _node = node }
        else rows[#rows + 1] = { label = resolveLabel(node), _node = node } end
    end
    self._rt.list:items(rows)
    local crumb = resolveLabel(self._root)
    for i = 2, #self._stack do crumb = crumb .. " > " .. resolveLabel(self._stack[i]) end
    self._rt.list:crumb(crumb)
end

function Menu:_choose(it)
    local node = it and it._node
    if not node then return end
    if node.children then
        self._stack[#self._stack + 1] = node
        self:_paint()
    elseif node.action then
        local ok, err = pcall(node.action, menu_ctx(self))
        if not ok then Ess.Log("UI.Menu action error: " .. tostring(err)); Ess.UI.Toast("ERROR (see log)") end
        if self._rt.open then                       -- re-render so DYNAMIC labels (:switch / cyclers) show the change
            local list = self._rt.list
            local keep = list and list._sel          -- keep the cursor where it is (a re-items resets it to the top)
            self:_paint()
            if list and keep then list:select(keep) end
        end
    end
end

function Menu:_back()
    if #self._stack > 1 then
        self._stack[#self._stack] = nil
        self:_paint()
    else
        self:close()
    end
end

function Menu:open()
    local S = Ess.UI._S
    local rt = self._rt
    if rt.open then return self end
    if not (Player.GetLocalPlayer() and Player.GetLocalCharacter()) then
        Ess.Log("UI.Menu: no local player yet -- can't open menu '" .. tostring(self._title) .. "'")
        return self
    end
    -- only one Ess.UI.Menu open at a time (they share the same on-screen slot)
    if S.openId and S.openId ~= self._id then
        local o = S.menus and S.menus[S.openId]
        if o and o.open then
            if o.list then pcall(function() o.list:hide():blur() end) end
            o.open = false
            if o.menu and o.menu._onClose then pcall(o.menu._onClose) end
        end
    end
    local hint = "UP/DOWN MOVE   ENTER PICK   LEFT BACK"
    if self._key then hint = hint .. "   " .. tostring(self._key) .. " CLOSE" end
    if not rt.list then
        rt.list = Ess.UI.List{ x = self._x, y = self._y, title = self._title, hint = hint,
            onChoose = function(it) self:_choose(it) end, onBack = function() self:_back() end }
    else
        rt.list.onChoose = function(it) self:_choose(it) end
        rt.list.onBack   = function() self:_back() end
        rt.list:title(self._title):hint(hint)
    end
    rt.menu = self                       -- current run's object (holds this run's tree + action closures)
    self._stack = { self._root }
    self:_paint()
    rt.list:show():focus()
    rt.open = true
    S.openId = self._id
    return self
end

function Menu:close()
    local S = Ess.UI._S
    local rt = self._rt
    if not rt.open then return self end
    if rt.list then rt.list:hide():blur() end
    rt.open = false
    if S.openId == self._id then S.openId = nil end
    if self._onClose then pcall(self._onClose) end
    return self
end

function Menu:toggle() if self._rt.open then self:close() else self:open() end return self end
function Menu:isOpen() return self._rt.open == true end

-- Ess.UI.Menu{ title, id, key, x, y, onClose }  (or Ess.UI.Menu("TITLE"))
--   id  : distinct runtime-state key; defaults to title. Give separate menus distinct titles/ids.
--   key : your toggle key's name, shown in the hint (display only).
function Ess.UI.Menu(opts)
    if type(opts) == "string" then opts = { title = opts } end
    opts = opts or {}
    local title = opts.title or "MENU"
    local id = opts.id or title
    local root = { label = title, children = {} }
    local m = setmetatable({
        _root = root, _children = root.children,
        _title = title, _id = id,
        _key = opts.key, _x = opts.x or 40, _y = opts.y or 60,
        _onClose = opts.onClose,
        _rt = menu_rt(id),
    }, Menu)
    return m
end
