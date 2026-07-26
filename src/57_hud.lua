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
--   Ess.Hud.Faction.*                     the faction meters, the pursuit bar, and the ON-SCREEN COUNTDOWN
--                                         (add/set/timer/pursuit/inZone/hide/show/levels)
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
    local ok = Ess.Safe.named("Ess.Hud.banner(register texture)", function()
        MrxGuiHudMessage._tEventTextures.custom = "ess_custom_banner_noexist"
    end)
    bannerReady = ok
end
function Ess.Hud.banner(sMsg)
    if type(sMsg) ~= "string" or sMsg == "" then
        Ess.Safe.reject("Ess.Hud.banner", "sMsg must be a non-empty string")
        return
    end
    ensureBannerTexture()
    Ess.Safe.named("Ess.Hud.banner", function() Hud.EventFanfare:Commence({ sType = "custom", vText = sMsg }) end)
end

-- Ess.Hud.objective(sText [,nSlot]) -- set the persistent objective-tray line (Hud.ObjectiveTray, slot 1 by
-- default = the "current objective" line; slot 3 is the transient radio line, driven by Ess.Hud.radio). Pass
-- nil sText to clear that slot. CONFIRMED (this is exactly what Ess.Contract drives its objective line with);
-- promoted here so ANY mission/mod can set the HUD objective without reaching into Contract or re-deriving
-- the SetSlotToText/ClearSlot shape. The optional slot lets Ess.Objective/Ess.Quest show a goal on a line
-- other than a running Contract's.
function Ess.Hud.objective(sText, nSlot)
    local slot = tonumber(nSlot) or 1
    if sText == nil then Ess.Safe.named("Ess.Hud.objective", function() Hud.ObjectiveTray:ClearSlot({ nSlot = slot }) end)
    else Ess.Safe.named("Ess.Hud.objective", function() Hud.ObjectiveTray:SetSlotToText({ nSlot = slot, sText = tostring(sText) }) end) end
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
    Ess.Safe.named("Ess.Hud.radio", function() Hud.ObjectiveTray:SetSlotToText({ nSlot = 3, sText = sText }) end)
    Ess.Safe.quiet(Event.Create, Event.TimerRelative, { tonumber(nHold) or 5 }, function()
        if Ess.Hud._radioGen == myGen then Ess.Safe.named("Ess.Hud.radio", function() Hud.ObjectiveTray:ClearSlot({ nSlot = 3 }) end) end
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
    if type(sText) ~= "string" or sText == "" then
        Ess.Safe.reject("Ess.Hud.title", "sText must be a non-empty string")
        return false
    end
    local o = type(tOpts) == "table" and tOpts or {}
    Ess.Safe.named("Ess.Hud.title", function()
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
    if type(sText) ~= "string" or sText == "" then
        Ess.Safe.reject("Ess.Hud.location", "sText must be a non-empty string")
        return false
    end
    Ess.Safe.named("Ess.Hud.location", function()
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
    if type(sText) ~= "string" or sText == "" then
        Ess.Safe.reject("Ess.Hud.message", "sText must be a non-empty string")
        return nil
    end
    local o = type(tOpts) == "table" and tOpts or {}
    local ids
    Ess.Safe.named("Ess.Hud.message", function()
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
    if type(handle) ~= "table" or type(sText) ~= "string" then
        Ess.Safe.reject("Ess.Hud.updateMessage", "handle must be a table")
        return false
    end
    local ok
    Ess.Safe.named("Ess.Hud.updateMessage", function()
        ok = Hud.MessageBox:ModifyPendingMessage({ tMessageIds = handle, sMessage = sText })
    end)
    return ok == true
end

-- Ess.Hud.removeMessage(handle) -- same pending-only constraint as updateMessage.
function Ess.Hud.removeMessage(handle)
    if type(handle) ~= "table" then
        Ess.Safe.reject("Ess.Hud.removeMessage", "handle must be a table")
        return false
    end
    Ess.Safe.named("Ess.Hud.removeMessage", function() Hud.MessageBox:RemovePendingMessage({ tMessageIds = handle }) end)
    return true
end

-- Ess.Hud.clearMessages() -- wipe the message box, visible AND queued. This one has no pending caveat.
function Ess.Hud.clearMessages()
    Ess.Safe.named("Ess.Hud.clearMessages", function() Hud.MessageBox:Clear({}) end)
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
    Ess.Safe.named("Ess.Hud.tutorial", function()
        Hud.Tutorial:SetText({ sText = (type(sText) == "string" and sText ~= "") and sText or nil })
    end)
    return true
end

-- Ess.Hud.image(sTexture [,nSlot] [,nW] [,nH]) -- put an IMAGE in an objective-tray slot instead of text.
-- Same slot numbering as Ess.Hud.objective (1 = current objective line, 3 = the radio line).
function Ess.Hud.image(sTexture, nSlot, nW, nH)
    if type(sTexture) ~= "string" or sTexture == "" then
        Ess.Safe.reject("Ess.Hud.image", "sTexture must be a non-empty string")
        return false
    end
    Ess.Safe.named("Ess.Hud.image", function()
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
    if not v then
        Ess.Safe.reject("Ess.Hud.cash", "nValue must be a number, got " .. type(nValue))
        return false
    end
    local o = type(tOpts) == "table" and tOpts or {}
    Ess.Safe.named("Ess.Hud.cash", function()
        Hud.ResourceCounter:SetCash({ nValue = v, sReason = o.sReason, nIncrement = tonumber(o.nIncrement) })
    end)
    return true
end

function Ess.Hud.fuel(nValue, nMax)
    local v = tonumber(nValue)
    if not v then
        Ess.Safe.reject("Ess.Hud.fuel", "nValue must be a number, got " .. type(nValue))
        return false
    end
    Ess.Safe.named("Ess.Hud.fuel", function()
        Hud.ResourceCounter:SetFuel({ nValue = v, nMax = tonumber(nMax) })
    end)
    return true
end

-- Ess.Hud.resources(bShow [,nDuration]) -- show (for nDuration seconds, default 3) or hide the cash+fuel
-- readouts. Hiding is indefinite.
function Ess.Hud.resources(bShow, nDuration)
    Ess.Safe.named("Ess.Hud.resources", function()
        if bShow == false then Hud.ResourceCounter:Hide({})
        else Hud.ResourceCounter:Show({ nDuration = tonumber(nDuration) or 3 }) end
    end)
    return true
end

-- Ess.Hud.suppressResources(bCash, bFuel) -- the game's own "hide these during a cutscene" switch, separate
-- from show/hide and independently settable per counter.
function Ess.Hud.suppressResources(bCash, bFuel)
    Ess.Safe.named("Ess.Hud.suppressResources", function()
        Hud.ResourceCounter:SetSuppressed({ bSuppressCash = bCash and true or false,
                                            bSuppressFuel = bFuel and true or false })
    end)
    return true
end

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Ess.Hud.Faction -- the faction meters, the pursuit bar, and the on-screen countdown
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- A sub-table rather than eight more flat Ess.Hud verbs, because this is one coherent widget: a row of
-- labelled gauges, each belonging to a faction, that can show a value, flip into a red PURSUIT state, or run
-- a TIMER. The timer is the reason to care -- it is the only on-screen countdown the game exposes, it comes
-- with real HUD chrome, and it fires a Lua callback when it expires. Anything on a clock (defuse this,
-- survive this, reach it before the convoy) gets a native-looking presentation for four lines of code.
--
--   Ess.Hud.Faction.add(sFaction [,sTexture])       create a meter
--   Ess.Hud.Faction.set(sFaction, nValue [,bInit])  0..100
--   Ess.Hud.Faction.timer(sFaction, nSeconds [,fn]) countdown; fn() on expiry
--   Ess.Hud.Faction.pursuit(sFaction, nSeconds [,fn])
--   Ess.Hud.Faction.inZone(sFaction, bInside [,bInit])
--   Ess.Hud.Faction.hide(sFaction)
--   Ess.Hud.Faction.levels(tThresholds, tNames [,sPursuitName] [,bShow])   ⚠ GLOBAL AND DESTRUCTIVE
--   Ess.Hud.Faction.restoreLevels()       undo .levels(), back to the game's own vocabulary
--
-- ── WHAT TO KNOW BEFORE USING IT ───────────────────────────────────────────────────────────────────────
--
-- VALUES ARE 0..100. mrxguihudfactiongauge.lua fixes _knMin = 0 and _knMax = 100, and the bar maths divides
-- by the gap between thresholds, so feeding it a relation value straight from Ess.Relations will not do --
-- the game converts first (ConvertRelationToMeterValue).
--
-- ⚠⚠ .levels() IS DESTRUCTIVE AND GLOBAL. READ THIS BEFORE CALLING IT. ⚠⚠
--
-- It does not configure "your" meter. SetLevels writes the module-level _tLevels and _tLevelNames in
-- mrxguihudfactiongauge.lua, and EVERY gauge reads those -- including the game's own. Set custom level
-- names and the REAL faction meters start using them: a live test set {ESS CALM, ESS EDGY, ESS ANGRY,
-- ESS FURIOUS} and Universal Petroleum's own meter subsequently rendered "ESS FURIOUS" as its mood. The
-- player's faction standing display is simply wrong from then on, for every faction, until the level
-- reloads.
--
-- There is also no getter, so the previous vocabulary cannot be captured and put back generically -- the
-- only recovery is knowing the stock values, which is why STOCK_THRESHOLDS/STOCK_NAMES/STOCK_PURSUIT are
-- recorded below and Ess.Hud.Faction.restoreLevels() exists.
--
-- So: do not call .levels() to label a meter of your own. Use it only when you deliberately intend to
-- restyle the game's entire faction vocabulary, and restore it when you are done. For a mod that just wants
-- a countdown or a gauge, .timer/.set/.pursuit need none of this.
--
-- (The thresholds themselves are less dangerous than the names -- a value still lands in some band -- but
-- they are equally global, so a custom scale silently rescales the real meters too.)
--
-- SETTING A VALUE ABOVE ZERO CANCELS AN ACTIVE PURSUIT (SetValue calls StopPursuit when
-- bPursuitActive and nValue > _knMin). So do not drive a meter's value while its pursuit is running unless
-- ending it is what you meant.
--
-- THE TIMER CANNOT BE STOPPED through this namespace. The widget HAS a StopTimer, but Hud.FactionDisplay
-- never wraps it -- ten functions, and that is not one of them. Starting a new timer on the same faction is
-- the only way to displace a running one. (The widget's StopTimer is also mildly broken anyway: it calls
-- oTimer:Stop(nTime) where nTime is an undeclared global.)
--
-- THE TIMER CALLBACK TAKES NO ARGUMENTS AND FIRES ONCE. _TimerCallback unpacks only the callback data --
-- which this passes none of, as everywhere else in Ess -- and clears the stored callback before calling it.
--
-- METERS EXPIRE ON THEIR OWN, ABOUT FIVE SECONDS AFTER THEIR LAST UPDATE, AND CANNOT BE PINNED OPEN.
-- mrxguihudfactionbuffer.lua gives each occupied slot a life that counts down every frame; a timer sets it
-- to 5 + the timer's duration and a pursuit to 2 + its duration. At zero the gauge slides out and frees its
-- slot, unless a pursuit is still running, which extends it. Treat a meter as a flash of feedback, not a
-- panel you own -- and see the note further down about why refreshing it does not help.
--
-- NOT WRAPPED, all three EMPTY FUNCTIONS -- callable, return nil, do nothing:
--   * RemoveMeter and RemoveAllMeters (mrxguiinterface.lua). Use .hide(), which is real.
--   * ShowAll, behind Hud.FactionDisplay:Show (mrxguihudfactionbuffer.lua:198 -- the whole body is
--     `function ShowAll(oWidget, nDuration) end`). An Ess.Hud.Faction.show existed here briefly and was
--     withdrawn on measurement: it reported success and the meters still vanished, because there was never
--     any code behind it.
Ess.Hud.Faction = Ess.Hud.Faction or {}

-- The stock thresholds and value range, so a caller can reason about levels without reading the widget.
Ess.Hud.Faction.RANGE = { nMin = 0, nMax = 100 }

-- The stock level vocabulary, copied verbatim from mrxguihudfactiongauge.lua's Init(). Recorded because
-- .levels() overwrites it globally and the engine offers no getter, so these strings are the ONLY way back
-- to the game's own faction moods short of a level reload. They are localisation TOKENS rather than
-- English -- that is why the real meters render proper faction names from them, and why substituting
-- readable text is exactly what breaks them.
Ess.Hud.Faction.STOCK_THRESHOLDS = { 0, 25, 50, 75 }
Ess.Hud.Faction.STOCK_NAMES = { "[0x671b379b]", "[0x7c4225bc]", "[0xdb614732]", "[0x8c4d842e]" }
Ess.Hud.Faction.STOCK_PURSUIT = "[0x1cab5133]"
-- Kept as an alias; STOCK_THRESHOLDS is the clearer name now that restoring is the point.
Ess.Hud.Faction.DEFAULT_THRESHOLDS = Ess.Hud.Faction.STOCK_THRESHOLDS

local function factionGuard(sLabel, sFaction)
    if type(sFaction) ~= "string" or sFaction == "" then
        Ess.Safe.reject(sLabel, "sFaction must be a non-empty faction code (PMC/AN/CH/GR/OC/PR/VZ)")
        return false
    end
    return true
end

-- Ess.Hud.Faction.add(sFaction [,sTexture]) -- put a meter on screen for this faction. sTexture is the
-- marker icon shown beside it; the game passes each faction's own marker texture.
function Ess.Hud.Faction.add(sFaction, sTexture)
    if not factionGuard("Ess.Hud.Faction.add", sFaction) then return false end
    Ess.Safe.named("Ess.Hud.Faction.add", function()
        Hud.FactionDisplay:AddMeter({ sFaction = sFaction, sTexture = sTexture })
    end)
    return true
end

-- Ess.Hud.Faction.set(sFaction, nValue [,bInitialize]) -- 0..100. bInitialize snaps instead of animating.
-- Values outside the range are passed through rather than clamped, because the widget's own level maths
-- treats the ends as open and clamping here would silently disagree with it.
function Ess.Hud.Faction.set(sFaction, nValue, bInitialize)
    if not factionGuard("Ess.Hud.Faction.set", sFaction) then return false end
    local v = tonumber(nValue)
    if not v then
        Ess.Safe.reject("Ess.Hud.Faction.set", "nValue must be a number 0..100, got " .. type(nValue))
        return false
    end
    Ess.Safe.named("Ess.Hud.Faction.set", function()
        Hud.FactionDisplay:SetValue({ sFaction = sFaction, nValue = v,
                                      bInitialize = bInitialize and true or nil, bForceOnClient = true })
    end)
    return true
end

-- Ess.Hud.Faction.timer(sFaction, nSeconds [,fn]) -- the on-screen countdown. fn() fires once on expiry.
function Ess.Hud.Faction.timer(sFaction, nSeconds, fn)
    if not factionGuard("Ess.Hud.Faction.timer", sFaction) then return false end
    local t = tonumber(nSeconds)
    if not t or t <= 0 then
        Ess.Safe.reject("Ess.Hud.Faction.timer", "nSeconds must be a positive number")
        return false
    end
    Ess.Safe.named("Ess.Hud.Faction.timer", function()
        Hud.FactionDisplay:StartTimer({ sFaction = sFaction, nDuration = t,
                                        fCallback = type(fn) == "function"
                                            and function() pcall(fn) end or nil })
    end)
    return true
end

-- Ess.Hud.Faction.pursuit(sFaction, nSeconds [,fn]) -- the red "you are being hunted" gauge. fn() on
-- completion. Pass nSeconds <= 0 for an indefinite pursuit with no callback, which is what the game does
-- for a pursuit that ends on an event rather than a clock.
--
-- IT FILLS, IT DOES NOT DRAIN -- confirmed on screen, and the source agrees: StartPursuitGauge first snaps
-- the bar to empty (`AnimateToPoint(nGaugeFrontEmptyPoint, 0, true)`) and then _AnimateToEnd animates it
-- out to the full gauge length over nSeconds. So it reads as a threat closing in rather than a timer
-- running out, which is the opposite of what "pursuit duration" suggests.
function Ess.Hud.Faction.pursuit(sFaction, nSeconds, fn)
    if not factionGuard("Ess.Hud.Faction.pursuit", sFaction) then return false end
    local t = tonumber(nSeconds) or -1
    Ess.Safe.named("Ess.Hud.Faction.pursuit", function()
        Hud.FactionDisplay:StartPursuit({ sFaction = sFaction, nDuration = t, bForceOnClient = true,
                                          fCallback = type(fn) == "function"
                                              and function() pcall(fn) end or nil })
    end)
    return true
end

-- Ess.Hud.Faction.inZone(sFaction, bInside [,bInitialize]) -- mark the player as inside that faction's
-- territory, which is how the game highlights the relevant meter as you cross a border.
function Ess.Hud.Faction.inZone(sFaction, bInside, bInitialize)
    if not factionGuard("Ess.Hud.Faction.inZone", sFaction) then return false end
    Ess.Safe.named("Ess.Hud.Faction.inZone", function()
        Hud.FactionDisplay:SetInsideFactionZone({ sFaction = sFaction, bInside = bInside and true or false,
                                                  bInitialize = bInitialize and true or nil })
    end)
    return true
end

-- Ess.Hud.Faction.hide(sFaction) -- hide one meter. The real teardown, since RemoveMeter is a no-op.
function Ess.Hud.Faction.hide(sFaction)
    if not factionGuard("Ess.Hud.Faction.hide", sFaction) then return false end
    Ess.Safe.named("Ess.Hud.Faction.hide", function()
        Hud.FactionDisplay:HideMeter({ sFaction = sFaction, bForceOnClient = true })
    end)
    return true
end

-- NO KEEP FUNCTION HERE, AND THAT IS A FINDING RATHER THAN AN OMISSION.
--
-- A meter cannot be held on screen. The obvious approach -- re-set its value on a timer just under the
-- ~5-second slot life, the way Ess.Easy.World holds an atmosphere against the region system -- was built
-- and MEASURED, and does not work: a keeper refreshing every 3 seconds (verified firing, 4 refreshes in 12
-- seconds against a running tick loop) still let the meter expire on schedule. So whatever actually renews
-- a slot is not reachable through SetValue, despite the buffer's SetValue path appearing to set
-- tSlotLife = math.max(5, remaining).
--
-- Combined with Hud.FactionDisplay:Show being an empty function, that means THE FACTION METERS ARE
-- INHERENTLY TRANSIENT: they exist to flash up in response to something and then leave. Design around that
-- rather than against it -- .timer and .pursuit both hold the meter for their own duration (5 + nTime and
-- 2 + nTime respectively), which is the supported way to keep one up for a known period.

-- Ess.Hud.Faction.levels(tThresholds, tNames [,sPursuitName] [,bShow]) -- redefine the level bands shared by
-- every gauge. tThresholds ascending numbers STARTING AT 0, tNames the same length.
--
-- The native validates hard and returns false on any of: a non-number threshold, a non-string name, a first
-- threshold that is not 0, or mismatched lengths. Those four are checked here first so the failure comes
-- with a reason rather than a bare false.
--
-- It LOOKS like it validates ascending order too, and it does not: that check compares every threshold
-- against a nPrevLevel initialised to -1 and never updated inside the loop, so it can only ever fire for a
-- value below -1. Descending or duplicate thresholds sail through and produce a gauge whose level maths
-- divides by a negative or zero range. This wrapper does the ordering check the engine intended.
-- Ess.Hud.Faction.restoreLevels() -- put the game's own level vocabulary back after .levels() has replaced
-- it. Always available and always correct, because the stock values are constants rather than something
-- captured at runtime (there is no getter to capture from).
--
-- Note the meters do not repaint until something updates them, so a gauge already showing a custom mood
-- keeps that text until its next set/timer/pursuit. Call .set() on anything visible to force it through.
function Ess.Hud.Faction.restoreLevels()
    Ess.Safe.named("Ess.Hud.Faction.restoreLevels", function()
        Hud.FactionDisplay:ConfigureThresholds({
            tLevelThresholds = Ess.Hud.Faction.STOCK_THRESHOLDS,
            tLevelNames = Ess.Hud.Faction.STOCK_NAMES,
            sPursuitName = Ess.Hud.Faction.STOCK_PURSUIT,
        })
    end)
    return true
end

function Ess.Hud.Faction.levels(tThresholds, tNames, sPursuitName, bShow)
    local L = "Ess.Hud.Faction.levels"
    if type(tThresholds) ~= "table" or type(tNames) ~= "table" then
        Ess.Safe.reject(L, "tThresholds and tNames must both be tables")
        return false
    end
    if #tThresholds ~= #tNames then
        Ess.Safe.reject(L, "tThresholds has " .. #tThresholds .. " entries but tNames has " .. #tNames)
        return false
    end
    if #tThresholds == 0 then
        Ess.Safe.reject(L, "need at least one threshold")
        return false
    end
    if tThresholds[1] ~= 0 then
        Ess.Safe.reject(L, "the first threshold must be exactly 0, got " .. tostring(tThresholds[1]))
        return false
    end
    local prev
    for i, v in ipairs(tThresholds) do
        if type(v) ~= "number" then
            Ess.Safe.reject(L, "threshold " .. i .. " is not a number")
            return false
        end
        -- The check the engine meant to make; see the note above.
        if prev and v <= prev then
            Ess.Safe.reject(L, "thresholds must ascend: entry " .. i .. " (" .. v .. ") is not above "
                            .. "the previous (" .. prev .. ")")
            return false
        end
        prev = v
    end
    for i, s in ipairs(tNames) do
        if type(s) ~= "string" then
            Ess.Safe.reject(L, "level name " .. i .. " is not a string")
            return false
        end
    end
    Ess.Safe.named(L, function()
        Hud.FactionDisplay:ConfigureThresholds({ tLevelThresholds = tThresholds, tLevelNames = tNames,
                                                 sPursuitName = sPursuitName,
                                                 bDisplayResult = bShow and true or nil })
    end)
    return true
end
