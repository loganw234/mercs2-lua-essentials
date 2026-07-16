-- Ess/21_input.lua -- Ess.Input: the one correct keyboard-polling shape, a VK->char table, and the
-- controller-hijack trick for continuous analog input under a paused world. Ess.TextConsole: a
-- standalone typed-input console built on top of Ess.Input.VkToChar.
--
-- API:
--   Ess.Input.poll() -> { pressed = {vk, ...}, down = function(vk) -> bool }
--   Ess.Input.VkToChar(vk, bShift) -> sChar | nil
--   Ess.Input.hijackController(onInput) -> release()      niche -- see caveat below; low priority to
--                                                          verify further, most mods don't need this
--   Ess.Input.usingController() -> bool                    Gui.ControllerInUse -- for branching HUD hint
--                                                           text ("Press A" vs "Press E"), the common case
--   Ess.TextConsole.open{ prompt=, text=, max=, lockPlayer=, onSubmit=, onCancel=, onChange= }
--   Ess.TextConsole.close()
--   Ess.TextConsole.isOpen() -> bool

import("MrxGuiBase")
import("MrxGui")

local Ess = _G.Ess
Ess.Input = Ess.Input or {}

-- Ess.Input.poll() -> { pressed = {vk, ...}, down = fn(vk) -> bool }
-- The ONLY correct input-polling shape on this engine: Loader.PopKeyEvents() (an edge-triggered ring
-- buffer -- each byte is a VK code that went up->down since the last drain) for discrete presses, PLUS
-- Loader.GetKeyboardState() (a 256-byte snapshot) for "is this held right now." Call this ONCE per tick
-- and read both fields off the result.
--
-- NEVER call Loader.IsKeyDown per key in a loop -- every framerate bug this project has hit in a custom
-- menu/console/HUD came from exactly that mistake, independently, more than once (uilib, contracts.lua,
-- ForgeMenu, MissionForge all hit it and fixed it separately before this existed). This function makes
-- the correct pattern the only one on offer.
function Ess.Input.poll()
    local pressed = {}
    local ev = Loader.PopKeyEvents()
    if ev and ev ~= "" then
        for i = 1, #ev do pressed[#pressed + 1] = string.byte(ev, i) end
    end
    local ks = Loader.GetKeyboardState()
    local function down(vk)
        if not ks then return false end
        return (string.byte(ks, vk + 1) or 0) >= 128
    end
    return { pressed = pressed, down = down }
end

-- ============================================================
-- Ess.Input.VkToChar -- US keyboard layout: A-Z, 0-9, space, common punctuation, shifted variants.
-- Direct port of uilib's CHAR table (already correct/tested) -- the exact table this project's shipped
-- cheat/spawn menus each duplicated byte-for-byte before this existed.
-- ============================================================
local CHAR = {}
for c = 0x41, 0x5A do CHAR[c] = { n = string.char(c + 32), s = string.char(c) } end
local DIGSHIFT = { [0] = ")", "!", "@", "#", "$", "%", "^", "&", "*", "(" }
for d = 0, 9 do CHAR[0x30 + d] = { n = tostring(d), s = DIGSHIFT[d] } end
CHAR[0x20] = { n = " ", s = " " }
local PUNCT = {
    { 0xBC, ",", "<" }, { 0xBE, ".", ">" }, { 0xBF, "/", "?" }, { 0xBD, "-", "_" },
    { 0xBB, "=", "+" }, { 0xBA, ";", ":" }, { 0xDE, "'", "\"" }, { 0xDB, "[", "{" },
    { 0xDD, "]", "}" }, { 0xDC, "\\", "|" }, { 0xC0, "`", "~" },
}
for _, p in ipairs(PUNCT) do CHAR[p[1]] = { n = p[2], s = p[3] } end

function Ess.Input.VkToChar(vk, bShift)
    local m = CHAR[vk]
    if not m then return nil end
    return bShift and m.s or m.n
end

-- Ess.Input.usingController() -> bool
-- CONFIRMED (wiki/namespaces/gui.md): Gui.ControllerInUse(), always guard-checked at every real call site
-- (`if Gui.ControllerInUse and Gui.ControllerInUse() then` -- `vzacon001.lua`/tutorial scripts), a strong
-- signal it may not exist on every platform build -- this wrapper copies that guard so callers don't have
-- to. The common real use: branching a HUD hint/prompt's wording ("Press A" vs "Press E") without a
-- separate settings flag to track.
--
-- Explicit `b == true or b == 1` rather than a naive `if b then` -- this engine's getters are already
-- documented (wiki/CLAUDE.md) to sometimes return 1/0 instead of a real boolean, and 0 is TRUTHY in Lua
-- (only nil/false are falsy), so a naive truthy check would silently report "using a controller" even
-- when the real answer is 0/false.
function Ess.Input.usingController()
    if not Gui.ControllerInUse then return false end
    local ok, b = pcall(Gui.ControllerInUse)
    return ok and (b == true or b == 1)
end

-- ============================================================
-- Ess.Input.hijackController -- ⚠ UNVERIFIED IN THIS BUILD. Synthesized from a wiki deep-dive survey
-- (freecam.md/forgecam.md), not a direct primary-source read -- confirm against the real deep-dive pages
-- and test live before depending on this in production.
--
-- The documented technique: there is NO real-time/per-frame Event on this engine at all (Event.
-- TimerRelative is sim-gated, frozen under world-pause) -- so while a PDA-style pause is up, the ONLY
-- callback that ticks at all is ControllerInput, and it only fires on ACTUAL controller activity (an idle
-- stick sends nothing, not a final zero -- decay stale axes yourself if "the stick just went idle" matters
-- to you). Hijacking the PDA widget's own ControllerInput handler is the confirmed way to ride that.
--
-- CAVEAT: while hijacked, the PDA underneath still claims arrows/Enter/Esc -- a keyboard UI layered on top
-- of this must use letter keys, not arrows, while it's active.
-- ============================================================

-- Ess.Input.hijackController(onInput) -> release()
-- ALWAYS call the returned release() when done.
function Ess.Input.hijackController(onInput)
    local pda
    local ok = pcall(function()
        for _, oWidget in pairs(MrxGuiBase.WidgetIdIndex) do
            local ok2, sName = pcall(function() return oWidget:GetName() end)
            if ok2 and sName == "PDA" then pda = oWidget; break end
        end
    end)
    if not ok or not pda then
        Ess.Log("Input.hijackController: couldn't find the PDA widget")
        return function() end
    end
    pcall(function() pda:SetVisible(false) end)
    local hookOk = pcall(function() pda:SetEventHandler("ControllerInput", onInput) end)
    if not hookOk then
        Ess.Log("Input.hijackController: SetEventHandler failed")
    end
    return function()
        pcall(function() pda:SetVisible(true) end)
    end
end

-- ============================================================
-- Ess.TextConsole -- the open/close/buffer/backspace/escape/poll-loop free-text console, duplicated
-- near-verbatim between MasterCheatMenu.lua's and CommonSpawnMenu.lua's own "Custom Name..." consoles
-- (down to the same VK table and the same "reset the running-flag on Escape too, not just on the normal
-- not-active check" bug fix -- Escape closes from INSIDE the poll loop, which returns immediately without
-- rescheduling itself; skipping this reset makes the next open() see a stale "already running" flag and
-- never start a new loop at all).
--
-- Unlike Ess.UI.Input (a one-shot modal prompt that auto-closes on submit, needs the ui_input.gfx movie),
-- this is a REPL-style console that stays open across multiple Enter presses -- matching its source
-- material exactly -- and needs no .gfx asset at all, just a plain MrxGui.TextWidget. For a standalone
-- OnKey script (a cheat/spawn menu) that wants one quick text field without pulling in the whole Ess.UI
-- kit.
--
-- Ess.TextConsole.open{ prompt=, text=, max=, lockPlayer=(default true), onSubmit=fn(text), onCancel=fn(),
--                        onChange=fn(text) }
--   lockPlayer disables player movement/actions while typing (Player.SetInputEnabled), matching the
--   original console's behavior -- pass lockPlayer=false for an overlay that should keep gameplay running
--   underneath (e.g. a chat box).
-- Ess.TextConsole.close()   -- safe to call even if not open
-- Ess.TextConsole.isOpen() -> bool
-- ============================================================
import("MrxGui")

Ess.TextConsole = Ess.TextConsole or {}
Ess.TextConsole._S = Ess.TextConsole._S or { active = false, buffer = "" }

local function tcShow(bVisible)
    local S = Ess.TextConsole._S
    if bVisible and not S.widget then
        local ok, w = pcall(function()
            local tw = MrxGui.TextWidget:new()
            tw:SetFont("english_18")
            tw:SetColor(255, 255, 0)
            tw:SetLocation(20, 20, 400, 45)
            local okP, uP = pcall(Player.GetLocalPlayer)
            if okP and uP then pcall(function() tw:SetOwner(uP) end) end
            MrxGui.AddWidget(tw)
            tw:SetVisible(false)
            return tw
        end)
        if ok then S.widget = w end
    end
    if S.widget then pcall(function() S.widget:SetVisible(bVisible) end) end
end

local function tcPaint()
    local S = Ess.TextConsole._S
    if S.widget then pcall(function() S.widget:SetText((S.prompt or "> ") .. S.buffer .. "_") end) end
end

local function tcLoop()
    local S = Ess.TextConsole._S
    if not S.active then return false end
    local sEvents = Loader.PopKeyEvents()
    local okShift, held = pcall(Loader.IsKeyDown, 0x10)   -- VK_SHIFT -- ONE specific key, not a per-key poll loop
    local bShift = okShift and held
    local changed = false
    for i = 1, #sEvents do
        local vk = string.byte(sEvents, i)
        if vk == 0x0D then                       -- Enter: submit, buffer resets, console STAYS open
            local text = S.buffer
            S.buffer = ""
            changed = true
            local cb = S.onSubmit
            if cb then pcall(cb, text) end
            if not S.active then return false end -- onSubmit may have closed it -- state changed under us
        elseif vk == 0x1B then                   -- Escape: cancel and close
            local cb = S.onCancel
            Ess.TextConsole.close()
            if cb then pcall(cb) end
            return false
        elseif vk == 0x08 then                   -- Backspace
            S.buffer = S.buffer:sub(1, #S.buffer - 1)
            changed = true
        else
            local ch = Ess.Input.VkToChar(vk, bShift)
            if ch and #S.buffer < (S.max or 200) then
                S.buffer = S.buffer .. ch
                changed = true
            end
        end
    end
    if changed then
        tcPaint()
        if S.onChange then pcall(S.onChange, S.buffer) end
    end
    return true
end

function Ess.TextConsole.open(opts)
    opts = opts or {}
    local S = Ess.TextConsole._S
    S.active = true
    S.buffer = tostring(opts.text or "")
    S.max = opts.max or 200
    S.prompt = tostring(opts.prompt or "> ")
    S.onSubmit, S.onCancel, S.onChange = opts.onSubmit, opts.onCancel, opts.onChange
    S.lockPlayer = opts.lockPlayer ~= false
    pcall(Loader.ClearKeyEvents)
    if S.lockPlayer then
        local ok, uP = pcall(Player.GetLocalPlayer)
        if ok and uP then pcall(Player.SetInputEnabled, uP, false) end
    end
    tcShow(true)
    tcPaint()
    Ess.Loop.start("Ess.TextConsole", 0.01, tcLoop)
end

function Ess.TextConsole.close()
    local S = Ess.TextConsole._S
    if not S.active then return end
    S.active = false
    Ess.Loop.stop("Ess.TextConsole")
    if S.lockPlayer then
        local ok, uP = pcall(Player.GetLocalPlayer)
        if ok and uP then pcall(Player.SetInputEnabled, uP, true) end
    end
    tcShow(false)
end

function Ess.TextConsole.isOpen()
    return Ess.TextConsole._S.active == true
end
