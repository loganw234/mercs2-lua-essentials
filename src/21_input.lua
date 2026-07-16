-- Ess/21_input.lua -- Ess.Input: the one correct keyboard-polling shape, a VK->char table, and the
-- controller-hijack trick for continuous analog input under a paused world.
--
-- API:
--   Ess.Input.poll() -> { pressed = {vk, ...}, down = function(vk) -> bool }
--   Ess.Input.VkToChar(vk, bShift) -> sChar | nil
--   Ess.Input.hijackController(onInput) -> release()      UNVERIFIED in this build, see caveat below

import("MrxGuiBase")

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
    local ok, pda = pcall(MrxGuiBase.WidgetIdIndex, "PDA")
    if not ok or not pda then
        Ess.Log("Input.hijackController: couldn't find the PDA widget (unverified path -- see file header)")
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
