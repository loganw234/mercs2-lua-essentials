-- Ess/57_hud.lua -- Ess.Hud: native HUD popups, using confirmed-working resident-module patterns instead
-- of a hand-rolled custom widget -- distinct from Ess.UI.Toast (a custom .gfx movie widget); these use
-- the game's OWN built-in popup chrome.
--
-- API:
--   Ess.Hud.hint(sMsg, sId, bBroadcast)   the native tutorial-style hint popup (icon+sound), stays up
--                                         until hidden -- CONFIRMED reusable for arbitrary text, live-
--                                         tested with a screenshot (wiki/snippets.md)
--   Ess.Hud.hideHint(sId, bBroadcast)
--   Ess.Hud.banner(sMsg)                  a clean, icon-free, centered text banner via the EventFanfare
--                                         "custom" trick (CONFIRMED live-tested)
--   Ess.Hud.objective(sText [,nSlot])     set the persistent objective-tray line (nil clears it); nSlot
--                                         defaults to 1 (the "current objective" line)
--   Ess.Hud.radio(sText, nHold)           a transient radio-chatter subtitle that auto-clears after nHold s

import("MrxTutorialManager")
import("MrxGuiHudMessage")

local Ess = _G.Ess
Ess.Hud = Ess.Hud or {}

-- Ess.Hud.hint(sMsg, sId, bBroadcast) -- the tutorial-hint popup (a d-pad/book icon + notification sound)
-- the game itself shows for "you're swimming"/"low on fuel" turns out to be a completely generic,
-- reusable primitive underneath -- CONFIRMED by live testing (wiki/snippets.md, with a screenshot). No
-- auto-hide timer; stays up until Ess.Hud.hideHint is called with a MATCHING sId (a different/missing id
-- does NOT clear it -- confirmed by live testing, useful when more than one script might show a message
-- at once). Local-only by default (bBroadcast=false/omitted); pass bBroadcast=true to opt into the
-- native's own co-op broadcast (its actual network behavior is unconfirmed/untested here, since
-- confirming it needs a second player -- default to the safer local-only behavior rather than the
-- native's own default-to-broadcast).
function Ess.Hud.hint(sMsg, sId, bBroadcast)
    if type(sMsg) ~= "string" or sMsg == "" then return end
    pcall(MrxTutorialManager.ShowMessage, sMsg, not bBroadcast, sId)
end

function Ess.Hud.hideHint(sId, bBroadcast)
    pcall(MrxTutorialManager.HideMessage, not bBroadcast, sId)
end

-- Ess.Hud.banner(sMsg) -- a clean, icon-free, centered text banner. CONFIRMED live-tested trick
-- (wiki/namespaces/hud.md): Hud.EventFanfare:Commence gates on sType being a key in
-- MrxGuiHudMessage._tEventTextures (declared without `local`, so writable via import) -- registering a
-- texture name that doesn't correspond to any real loaded asset produces no icon/no gold header, just
-- vText centered on screen. The 9 REAL sType values (contact/support/stockpile/etc, already used by
-- Ess.Contract's own fanfare) are untouched; this only ever adds the one "custom" key.
local bannerReady = false
local function ensureBannerTexture()
    if bannerReady then return end
    local ok = pcall(function() MrxGuiHudMessage._tEventTextures.custom = "ess_custom_banner_noexist" end)
    bannerReady = ok
end
function Ess.Hud.banner(sMsg)
    if type(sMsg) ~= "string" or sMsg == "" then return end
    ensureBannerTexture()
    pcall(function() Hud.EventFanfare:Commence({ sType = "custom", vText = sMsg }) end)
end

-- Ess.Hud.objective(sText [,nSlot]) -- set the persistent objective-tray line (Hud.ObjectiveTray, slot 1 by
-- default = the "current objective" line; slot 3 is the transient radio line, driven by Ess.Hud.radio). Pass
-- nil sText to clear that slot. CONFIRMED (this is exactly what Ess.Contract drives its objective line with);
-- promoted here so ANY mission/mod can set the HUD objective without reaching into Contract or re-deriving
-- the SetSlotToText/ClearSlot shape. The optional slot lets Ess.Objective/Ess.Quest show a goal on a line
-- other than a running Contract's.
function Ess.Hud.objective(sText, nSlot)
    local slot = tonumber(nSlot) or 1
    if sText == nil then pcall(function() Hud.ObjectiveTray:ClearSlot({ nSlot = slot }) end)
    else pcall(function() Hud.ObjectiveTray:SetSlotToText({ nSlot = slot, sText = tostring(sText) }) end) end
end

-- Ess.Hud.radio(sText, nHold) -- a transient "radio chatter" subtitle (objective-tray slot 3) that clears
-- itself after nHold seconds (default 5) -- the game's own one-off mission-chatter line, and the natural
-- fit for cutscene dialogue/subtitles. A generation guard means a NEWER radio() call won't get wiped early
-- by an OLDER line's pending clear-timer (an improvement over Ess.Contract's own hudSay, which can).
Ess.Hud._radioGen = Ess.Hud._radioGen or 0
function Ess.Hud.radio(sText, nHold)
    if type(sText) ~= "string" or sText == "" then return end
    Ess.Hud._radioGen = Ess.Hud._radioGen + 1
    local myGen = Ess.Hud._radioGen
    pcall(function() Hud.ObjectiveTray:SetSlotToText({ nSlot = 3, sText = sText }) end)
    pcall(Event.Create, Event.TimerRelative, { tonumber(nHold) or 5 }, function()
        if Ess.Hud._radioGen == myGen then pcall(function() Hud.ObjectiveTray:ClearSlot({ nSlot = 3 }) end) end
    end)
end
