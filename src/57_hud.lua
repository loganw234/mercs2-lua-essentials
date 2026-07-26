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
--   Ess.Hud.title(sText [,nDur] [,tOpts]) the stylised animated title overlay (text_effect.swf)
--   Ess.Hud.location(sText [,nDur])       the region-name banner ("Playa del Este"-style card)
--   Ess.Hud.message(sText [,tOpts])       a message-box line; returns a handle for update/remove
--   Ess.Hud.updateMessage(h, sText)       edit a message that is still QUEUED (see the caveat below)
--   Ess.Hud.removeMessage(h) / clearMessages()
--   Ess.Hud.tutorial(sText)               the tutorial strip -- STICKY, pass nil to clear
--   Ess.Hud.image(sTexture [,nSlot] [,nW] [,nH])   put an image in an objective-tray slot
--   Ess.Hud.cash(n) / Ess.Hud.fuel(n [,nMax])     the resource readouts -- DISPLAY ONLY
--   Ess.Hud.resources(bShow [,nDur]) / Ess.Hud.suppressResources(bCash, bFuel)
--
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THIS WHOLE NAMESPACE IS READABLE LUA, NOT A BLACK BOX
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- `Hud.*` and `Pda.*` look like engine natives and were catalogued as such for a long time, but they are
-- not. `resident/mrxguiinterface.lua` opens with `_G.Hud = HudInterface` / `_G.Pda = PdaInterface`, and
-- every one of its 106 functions is a thin wrapper that resolves a Scaleform widget by name
-- (`_GetWidgetsForPlayers(vPlayer, "Objective Tray")`) and forwards to it. The widget classes are script
-- too, in mrxguimanager.lua / mrxguitextbuffer.lua / mrxguihudmessage.lua. So everything below was READ,
-- not guessed -- and then confirmed on screen live 2026-07-26.
--
-- Three consequences worth carrying:
--
-- 1. THEY ARE METHOD CALLS. `Hud.MessageBox:AddMessage{...}` -- colon, not dot. The wrappers use `self`
--    (MessageBox reads `self.sName` to pick its widget), and Hud.SubtitleBuffer is literally the same
--    functions bound to a table with a different sName. A dot-call silently targets the wrong widget or
--    errors. Every call in this file uses a colon.
--
-- 2. EVERY WRAPPER TAKES ONE TABLE with named `vPlayer` / `bDontNetSync` fields. Omitting vPlayer means
--    "all players", which is what you want in singleplayer. Do NOT pass it explicitly to the Tutorial
--    functions -- see Ess.Hud.tutorial's note, they are broken for that case in the shipped script.
--
-- 3. TWO OF THEM ARE DEAD. `Hud.FactionDisplay.RemoveMeter` and `.RemoveAllMeters` have empty bodies.
--    They are callable and return nil, so nothing tells you at runtime. Not wrapped here.

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
    Ess.Safe.quiet(MrxTutorialManager.ShowMessage, sMsg, not bBroadcast, sId)
end

function Ess.Hud.hideHint(sId, bBroadcast)
    Ess.Safe.quiet(MrxTutorialManager.HideMessage, not bBroadcast, sId)
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
    Ess.Safe.quiet(Event.Create, Event.TimerRelative, { tonumber(nHold) or 5 }, function()
        if Ess.Hud._radioGen == myGen then pcall(function() Hud.ObjectiveTray:ClearSlot({ nSlot = 3 }) end) end
    end)
end

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- The rest of the native HUD. Added 2026-07-26 from the mrxguiinterface.lua source, live-confirmed on screen.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════

-- Ess.Hud.RADAR_ICONS -- the minimap's icon vocabulary, the radar counterpart to Ess.Pda.ICONS. Also a
-- CLOSED SET: MrxUtil.MarkerGetIndexByName_Radar linear-searches this exact 23-entry table (mrxutil.lua
-- tObjRadarMaker) and returns 0 for anything else. Ess.Mark's radar default is "objective_action", one of
-- the first six.
Ess.Hud.RADAR_ICONS = {
    "objective_destroy", "objective_deliverable", "objective_action",
    "objective_defend", "objective_verify", "objective_outpost",
    "temp_radar_icon_db", "temp_radar_icon_dbactive",
    "MiniMap_Icon_Faction_PMC", "MiniMap_Icon_Faction_GR", "MiniMap_Icon_Faction_OC",
    "MiniMap_Icon_Faction_PR", "MiniMap_Icon_Faction_AN", "MiniMap_Icon_Faction_CH",
    "MiniMap_Icon_Faction_VZ",
    "MiniMap_Icon_Faction_GR_locked", "MiniMap_Icon_Faction_OC_locked",
    "MiniMap_Icon_Faction_PR_locked", "MiniMap_Icon_Faction_AN_locked",
    "MiniMap_Icon_Faction_CH_locked",
    "MiniMap_Icon_Symbol_Yellow", "MiniMap_Icon_Misha", "MiniMap_Icon_Eva",
}

-- Ess.Hud.title(sText [,nDuration] [,tOpts]) -- the stylised animated title overlay, the nicest-looking text
-- primitive the game has. It loads text_effect.swf, so it ANIMATES in and out rather than just appearing.
--
-- Positioning works in a 640x480 VIRTUAL SPACE, not screen pixels and not 0..1 -- nY=240 is the vertical
-- middle, and it is clamped to 0..450. Horizontal position is NOT yours to set: DisplayClassyText overwrites
-- whatever nX you pass with a centred value on its very first line, so the box is always centred and 566.67
-- wide; sJustification only decides how the text sits INSIDE that fixed box.
--
--   tOpts.nY            0..450, default 240 (middle). Small numbers are near the top.
--   tOpts.sJustify      "left" (default) | "center" | "right"
--   tOpts.sVertAnchor   "center" (default) | "bottom" | anything else = top; decides what nY measures TO
--   tOpts.bExpand       boolean, passed through to the Flash movie
--
-- nDuration is in seconds (default 3) and is multiplied by 30 internally, so the movie is frame-timed.
function Ess.Hud.title(sText, nDuration, tOpts)
    if type(sText) ~= "string" or sText == "" then return false end
    local o = type(tOpts) == "table" and tOpts or {}
    Ess.Safe.quiet(function()
        Hud.ClassyText:ShowText({
            sText = sText,
            nY = tonumber(o.nY) or 240,
            nDuration = tonumber(nDuration) or 3,
            sJustification = o.sJustify or "center",
            sVertAnchor = o.sVertAnchor or "center",
            bExpand = o.bExpand and true or false,
        })
    end)
    return true
end

-- Ess.Hud.location(sText [,nDuration]) -- the region-name banner the game shows when you cross into a named
-- area. Purely cosmetic and takes arbitrary text, so it doubles as a chapter/act card. nDuration in seconds.
function Ess.Hud.location(sText, nDuration)
    if type(sText) ~= "string" or sText == "" then return false end
    Ess.Safe.quiet(function()
        Hud.MapLabel:Show({ sLocation = sText, nDuration = tonumber(nDuration) or 10 })
    end)
    return true
end

-- Ess.Hud.message(sText [,tOpts]) -> handle -- a line in the message box (the notification stack the game
-- uses for "Checkpoint reached", support denials, and so on). Returns the tMessageIds handle, or nil.
--
--   tOpts.nDuration     seconds, default 2. NEGATIVE MEANS PERMANENT: AddMessage turns any nDuration < 0
--                       into duration 10000 plus a bPersistent flag, so it stays until removed by hand.
--   tOpts.nPriority     0..5, default 5. Out-of-range values are silently clamped to 5, and 0 takes a
--                       separate high-priority path in the widget.
--   tOpts.nFade         fade seconds, default 0.25
--   tOpts.bClearBuffer  clear everything else when this one displays
--   tOpts.bAppends      default true
--   tOpts.fCallback / tOpts.tCallbackData -- a real Lua callback, invoked by the widget
function Ess.Hud.message(sText, tOpts)
    if type(sText) ~= "string" or sText == "" then return nil end
    local o = type(tOpts) == "table" and tOpts or {}
    local ids
    Ess.Safe.quiet(function()
        ids = Hud.MessageBox:AddMessage({
            sMessage = sText,
            nDuration = tonumber(o.nDuration) or 2,
            nPriority = tonumber(o.nPriority),
            nFadeTime = tonumber(o.nFade),
            bClearBuffer = o.bClearBuffer and true or nil,
            bAllowsAppends = o.bAppends,
            fCallback = type(o.fCallback) == "function" and o.fCallback or nil,
            tCallbackData = type(o.tCallbackData) == "table" and o.tCallbackData or nil,
        })
    end)
    return ids
end

-- Ess.Hud.updateMessage(handle, sText) -> bool -- edit a message in place.
--
-- READ THIS BEFORE RELYING ON IT. The native is ModifyPending-Message and it means the word "pending"
-- literally: it searches the widget's PendingMessages QUEUE, so it only works while the message is still
-- waiting its turn. A message that is already on screen has moved to CurrentMessages and cannot be found,
-- and you get a plain `false` with no other signal. Measured: adding one message to an empty box displays it
-- immediately, so the very next update call returns false. It is useful for editing a line queued BEHIND a
-- busy stack, which is exactly what the game itself uses it for; it is not a general "change that text".
-- To replace a visible line, remove it and add a new one.
function Ess.Hud.updateMessage(handle, sText)
    if type(handle) ~= "table" or type(sText) ~= "string" then return false end
    local ok
    Ess.Safe.quiet(function()
        ok = Hud.MessageBox:ModifyPendingMessage({ tMessageIds = handle, sMessage = sText })
    end)
    return ok == true
end

-- Ess.Hud.removeMessage(handle) -- same pending-only constraint as updateMessage.
function Ess.Hud.removeMessage(handle)
    if type(handle) ~= "table" then return false end
    Ess.Safe.quiet(function() Hud.MessageBox:RemovePendingMessage({ tMessageIds = handle }) end)
    return true
end

-- Ess.Hud.clearMessages() -- wipe the message box, visible AND queued. This one has no pending caveat.
function Ess.Hud.clearMessages()
    Ess.Safe.quiet(function() Hud.MessageBox:Clear({}) end)
    return true
end

-- Ess.Hud.tutorial(sText) -- the tutorial text strip. Pass nil to clear it.
--
-- STICKY: unlike every other text primitive here there is no duration parameter, because the wrapper just
-- calls oWidget:SetText and returns. It stays until something clears it, INCLUDING across whatever else you
-- do -- confirmed live. Clearing is the game's own idiom (mrxtutorialmanager.lua passes sText = nil).
--
-- Distinct from Ess.Hud.hint: hint goes through MrxTutorialManager and gets the popup chrome, icon and
-- notification sound. This is the bare text strip with none of that.
--
-- Note also that Hud.Tutorial's OTHER two functions (ShowTutorialOnscreen, ShowTutorialForObject) are not
-- wrapped, because they are broken in the shipped script for any explicit vPlayer: a userdata player builds
-- an EMPTY target list (silent no-op) and a table player reads an undeclared global and errors inside
-- pairs(nil). Only the omitted-vPlayer path works, and nothing in the corpus ever called them.
function Ess.Hud.tutorial(sText)
    Ess.Safe.quiet(function()
        Hud.Tutorial:SetText({ sText = (type(sText) == "string" and sText ~= "") and sText or nil })
    end)
    return true
end

-- Ess.Hud.image(sTexture [,nSlot] [,nW] [,nH]) -- put an IMAGE in an objective-tray slot instead of text.
-- Same slot numbering as Ess.Hud.objective (1 = current objective line, 3 = the radio line).
function Ess.Hud.image(sTexture, nSlot, nW, nH)
    if type(sTexture) ~= "string" or sTexture == "" then return false end
    Ess.Safe.quiet(function()
        Hud.ObjectiveTray:SetSlotToImage({ nSlot = tonumber(nSlot) or 1, sTexture = sTexture,
                                           nWidth = tonumber(nW), nHeight = tonumber(nH) })
    end)
    return true
end

-- Ess.Hud.cash(nValue [,tOpts]) / Ess.Hud.fuel(nValue [,nMax]) -- the resource readouts.
--
-- DISPLAY ONLY. These write the widget, not the save -- the player's real cash and fuel are untouched, and
-- the next genuine change overwrites whatever you set. That is the same asymmetry recorded for the economy
-- setters: Ess.Easy.giveCash routes through MrxPmc so the number and the HUD agree, while Player.SetCash
-- moves the money without telling the HUD. This moves the HUD without touching the money.
--
-- tOpts.sReason shows the game's own "+$500 (reason)" annotation; tOpts.nIncrement drives the roll-up
-- animation. fuel()'s nMax is an undocumented extra the corpus never used: it appends "/max" to the readout.
function Ess.Hud.cash(nValue, tOpts)
    local v = tonumber(nValue)
    if not v then return false end
    local o = type(tOpts) == "table" and tOpts or {}
    Ess.Safe.quiet(function()
        Hud.ResourceCounter:SetCash({ nValue = v, sReason = o.sReason, nIncrement = tonumber(o.nIncrement) })
    end)
    return true
end

function Ess.Hud.fuel(nValue, nMax)
    local v = tonumber(nValue)
    if not v then return false end
    Ess.Safe.quiet(function()
        Hud.ResourceCounter:SetFuel({ nValue = v, nMax = tonumber(nMax) })
    end)
    return true
end

-- Ess.Hud.resources(bShow [,nDuration]) -- show (for nDuration seconds, default 3) or hide the cash+fuel
-- readouts. Hiding is indefinite.
function Ess.Hud.resources(bShow, nDuration)
    Ess.Safe.quiet(function()
        if bShow == false then Hud.ResourceCounter:Hide({})
        else Hud.ResourceCounter:Show({ nDuration = tonumber(nDuration) or 3 }) end
    end)
    return true
end

-- Ess.Hud.suppressResources(bCash, bFuel) -- the game's own "hide these during a cutscene" switch, separate
-- from show/hide and independently settable per counter.
function Ess.Hud.suppressResources(bCash, bFuel)
    Ess.Safe.quiet(function()
        Hud.ResourceCounter:SetSuppressed({ bSuppressCash = bCash and true or false,
                                            bSuppressFuel = bFuel and true or false })
    end)
    return true
end
