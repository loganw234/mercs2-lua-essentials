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
