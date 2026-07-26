-- Ess/58_pda.lua -- Ess.Pda: the player's PDA -- the mission log, the reference database, the statistics
-- screen, and the map layer underneath Ess.Mark's blips.
--
-- API:
--   Ess.Pda.log(sMessage [,tOpts])          add a line to the PDA log (the running mission journal)
--   Ess.Pda.dossier(sTitle, sText [,sIcon]) add a DOSSIER database entry (re-adding a title EDITS it)
--   Ess.Pda.statCategory(sCategory [,sIcon])
--   Ess.Pda.stat(sCategory, sDesc, sData)   add a row to a statistics category
--   Ess.Pda.blip(sName, tOpts) / Ess.Pda.removeBlip(sName)
--   Ess.Pda.selectedMission()               -> the mission id the player has selected, or nil
--   Ess.Pda.suppress(bOn)                   hide/show the PDA
--   Ess.Pda.attitude(sFaction, nAttitude [,sTexture])
--
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHAT THIS IS, AND WHY IT IS WORTH HAVING
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Like Ess.Hud, none of `Pda.*` is an engine native. `resident/mrxguiinterface.lua` sets
-- `_G.Pda = PdaInterface` (and `_G.oPda` as a second name for the same table), and every function is a thin
-- method-called wrapper that resolves the "PDA" Scaleform widget and forwards to it. Everything documented
-- here was read from that source rather than inferred from the names.
--
-- The interesting part is PERSISTENCE. Ess already had plenty of ways to put text on screen for a few
-- seconds, and Ess.UI can draw arbitrary custom Flash. What it had no way to do was leave a permanent,
-- player-reviewable RECORD: a log line they can scroll back to, a dossier entry about a character, a
-- statistic that accumulates. A mission that writes its story into the PDA log reads like part of the game
-- in a way a toast notification never does.
--
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- COLOURS AND LOCALIZATION TOKENS
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- sColor here is a BARE HEX STRING with no "#" and no "0x" -- the game passes "3399FF" for events and
-- "FFFFFF" for dialogue. Ess.Color exists but produces numbers, so this takes the string form the widget
-- wants and does not try to be clever about it.
--
-- Text fields accept literal strings, which is what makes any of this usable from a mod. The shipped game
-- almost always passes a LOCALIZATION TOKEN instead -- "[Generic.CheckpointReached]", "[PDA.Support.denied]"
-- -- which the widget resolves against the string database. A token that does not resolve renders as the
-- raw bracketed text, so if you see literal square brackets on screen, that is what happened. Inline colour
-- tags use the same syntax ("[red]some text"), so a leading bracket in your own text is worth avoiding.

local Ess = _G.Ess
Ess.Pda = Ess.Pda or {}

-- ---- The log ------------------------------------------------------------------------------------------
-- Ess.Pda.log(sMessage [,tOpts]) -- append a line to the PDA log. The most useful thing in this file: it is
-- the one way to leave a permanent, scrollable, player-reviewable record of what a mod did.
--   tOpts.sType    the log section -- "objective", "event" or "dialog", the three the shipped game uses.
--                  All three were confirmed to route and display live 2026-07-26. Passed straight through,
--                  so an unrecognised value is the widget's problem rather than an error here.
--   tOpts.sName    a short label. The game passes "" everywhere, which is why it defaults to that.
--   tOpts.sColor   bare hex, no "#" and no "0x" -- e.g. "3399FF". Defaults to the game's own event blue.
--                  Ess.Color is deliberately NOT used here: it produces numbers, and this wants the string.
function Ess.Pda.log(sMessage, tOpts)
    if type(sMessage) ~= "string" or sMessage == "" then
        Ess.Safe.reject("Ess.Pda.log", "sMessage must be a non-empty string")
        return false
    end
    local o = type(tOpts) == "table" and tOpts or {}
    Ess.Safe.named("Ess.Pda.log", function()
        Pda.Database:AddLogEntry({ sType = o.sType or "event", sName = o.sName or "",
                                   sMessage = sMessage, sColor = o.sColor or "3399FF" })
    end)
    return true
end

-- ---- The reference database ---------------------------------------------------------------------------
-- Ess.Pda.dossier(sTitle, sText [,sIcon]) -- add an entry to the PDA's dossier section. Adding the same
-- sTitle twice UPDATES that entry rather than duplicating it (the widget keys an index by title), so this
-- doubles as "edit". Confirmed on screen 2026-07-26. sIcon is optional and renders blank if omitted.
--
-- NOT WRAPPED: Pda.Database.AddHelpEntry. It is a WRITE-ONLY DEAD END. The widget stores it exactly like a
-- dossier entry -- same shape, same indexing -- into oPda.CustomData.tDataHelp, and that table is
-- initialised in one place and appended to in one place and READ IN NONE. tDataDossiers by contrast is read
-- at mrxguipda.lua:1388 and rendered, which is why dossier entries appear and help entries do not. Live
-- testing agreed: an added help entry was nowhere in the PDA. There is no argument that fixes this, so
-- there is no wrapper for it.
function Ess.Pda.dossier(sTitle, sText, sIcon)
    if type(sTitle) ~= "string" or sTitle == "" then
        Ess.Safe.reject("Ess.Pda.dossier", "sTitle must be a non-empty string")
        return false
    end
    Ess.Safe.named("Ess.Pda.dossier", function()
        Pda.Database:AddDossierEntry({ sTitle = sTitle, sText = tostring(sText or ""), sIcon = sIcon })
    end)
    return true
end

-- ---- Statistics ---------------------------------------------------------------------------------------
-- A category must exist before rows can be added to it. Both are additive and there is no remove.
function Ess.Pda.statCategory(sCategory, sIcon)
    if type(sCategory) ~= "string" or sCategory == "" then
        Ess.Safe.reject("Ess.Pda.statCategory", "sCategory must be a non-empty string")
        return false
    end
    Ess.Safe.named("Ess.Pda.statCategory", function()
        Pda.Database:AddStatisticCategory({ sCategory = sCategory, sIcon = sIcon })
    end)
    return true
end

function Ess.Pda.stat(sCategory, sDesc, sData)
    if type(sCategory) ~= "string" or sCategory == "" then
        Ess.Safe.reject("Ess.Pda.stat", "sCategory must be a non-empty string")
        return false
    end
    Ess.Safe.named("Ess.Pda.stat", function()
        Pda.Database:AddStatisticEntry({ sCategory = sCategory, sDesc = tostring(sDesc or ""),
                                         sData = tostring(sData or "") })
    end)
    return true
end

-- ---- The map ------------------------------------------------------------------------------------------
-- Ess.Pda.ICONS -- the PDA map's icon vocabulary. This is a CLOSED SET, not free-form: the co-op broadcast
-- path resolves the name through MrxUtil.MarkerGetIndexByName_Pda, which is a linear search of a fixed
-- table (mrxutil.lua tObjPdaMarker) that logs a complaint and returns index 0 for anything it does not
-- recognise. Ess.Mark hardcodes one of these and the rest were effectively undiscoverable.
--
-- 32 names here from 34 engine entries: tObjPdaMarker lists "icon_yellow_mc" TWICE (first and last) and
-- ends with an empty string. Deduplicated, because the index those resolve to only matters to the co-op
-- broadcast and both copies name the same icon. The _1/_2/_3 suffixes are objective tiers -- tier 3 is the
-- "tertiary" set the PDA can filter out wholesale.
Ess.Pda.ICONS = {
    "icon_yellow_mc",
    "icon_action_1_mc", "icon_action_2_mc", "icon_action_3_mc",
    "icon_outpost_1_mc", "icon_outpost_2_mc", "icon_outpost_3_mc",
    "icon_defend_1_mc", "icon_defend_2_mc", "icon_defend_3_mc",
    "icon_destroy_1_mc", "icon_destroy_2_mc", "icon_destroy_3_mc",
    "icon_verify_1_mc", "icon_verify_2_mc", "icon_verify_3_mc",
    "icon_deliverable_1_mc", "icon_deliverable_2_mc", "icon_deliverable_3_mc",
    "icon_pmc_mc", "icon_an_mc", "icon_ch_mc", "icon_gr_mc", "icon_oc_mc", "icon_pr_mc", "icon_vz_mc",
    "icon_an_locked_mc", "icon_ch_locked_mc", "icon_gr_locked_mc",
    "icon_oc_locked_mc", "icon_pr_locked_mc", "icon_vz_locked_mc",
}

-- Ess.Pda.blip(sName, tOpts) -- a PDA map blip, with the parameters Ess.Mark does not expose.
--
-- Ess.Mark already puts blips on the map, but it only ever passes four of AddMapBlip's thirteen arguments
-- (sName, uGuid, sTexture, nSortOrder) because that is all the one corpus call site it was derived from
-- used. The two that matter most here:
--
--   * nX/nY place a blip at a FIXED MAP COORDINATE with no object behind it. Ess.Mark cannot do that at all
--     -- it needs a guid to attach to. This is how you mark a destination, a search area, or a place where
--     something used to be.
--   * sLabel/sDesc give the blip a name and description in the PDA's own list, so it reads as a real
--     objective rather than an anonymous dot.
--
-- ── COORDINATES ────────────────────────────────────────────────────────────────────────────────────────
-- nX/nY are WORLD coordinates, and nY is world **Z**, not world Y -- the render path adds nXOffset to one
-- and nZOffset to the other. Height is not representable; a top-down map has nowhere to put it.
--
-- The X axis is MIRRORED on the map. Measured with four blips in a known cross 2026-07-26: nY+400 drew
-- ABOVE the player, nX+400 drew to the LEFT and nX-400 to the RIGHT. So increasing world X moves a blip
-- left across the PDA. That is the opposite of the obvious guess, and there is nothing in the script layer
-- that says so -- the flip happens inside the Flash movie.
--
-- ── THE TWO DEFAULTS BELOW EXIST BECAUSE OF MEASURED FAILURES ──────────────────────────────────────────
-- sTexture defaults to "icon_yellow_mc" and sLabel defaults to sName, because omitting either fails in a
-- way that looks like the call did not work at all:
--
--   * NO TEXTURE = AN INVISIBLE BLIP. It is placed and hoverable, but nothing is drawn until the cursor
--     is over it. Confirmed live: two untextured blips were invisible, and four textured ones drawn from
--     the list above were all visible immediately.
--   * NO LABEL = THE BLIP DISPLAYS ITS TEXTURE NAME. The render path builds a positional array whose 6th
--     slot is `tBlip.sLabel or tMissionData.sDefaultBlipLabel`; with no label and no owning mission that
--     slot is nil, and what the movie shows instead is the texture. Confirmed live -- an unlabelled blip
--     read "icon_verify_1_mc" on screen. This is also why an Ess.Mark blip (which passes no sLabel) shows
--     up as "icon_yellow_mc".
--
-- Pass sTexture = false to genuinely opt out of the icon.
--
-- Other fields: uGuid (attach to an object instead of coordinates), sMission, nMeter, bSticky, bTodoList,
-- sFaction (the wrapper defaults it to "PMC"), nSortOrder (defaults to 5).
--
-- Blips are NOT tracked for teardown here -- use Ess.Track:pda(sName) if you want automatic cleanup, which
-- is what it already exists for.
function Ess.Pda.blip(sName, tOpts)
    if type(sName) ~= "string" or sName == "" then
        Ess.Safe.reject("Ess.Pda.blip", "sName must be a non-empty string")
        return false
    end
    local o = type(tOpts) == "table" and tOpts or {}
    local tex = o.sTexture
    if tex == nil then tex = "icon_yellow_mc" elseif tex == false then tex = nil end
    Ess.Safe.named("Ess.Pda.blip", function()
        Pda.Map:AddBlip({
            sName = sName,
            nX = tonumber(o.nX), nY = tonumber(o.nY),
            sLabel = o.sLabel or sName, sDesc = o.sDesc,
            uGuid = o.uGuid, sTexture = tex,
            sMission = o.sMission, nMeter = tonumber(o.nMeter),
            bSticky = o.bSticky, bTodoList = o.bTodoList,
            sFaction = o.sFaction, nSortOrder = tonumber(o.nSortOrder),
        })
    end)
    return true
end

function Ess.Pda.removeBlip(sName)
    if type(sName) ~= "string" or sName == "" then
        Ess.Safe.reject("Ess.Pda.removeBlip", "sName must be a non-empty string")
        return false
    end
    Ess.Safe.named("Ess.Pda.removeBlip", function() Pda.Map:RemoveBlip({ sName = sName }) end)
    return true
end

-- Ess.Pda.selectedMission() -> sName or nil -- which mission the player has selected in the PDA.
-- One of the very few READ operations in this whole cluster, and it ignores vPlayer entirely: the wrapper
-- hardcodes Player.GetLocalPlayer(). Returns nil when nothing is selected (measured).
function Ess.Pda.selectedMission()
    local v
    Ess.Safe.named("Ess.Pda.selectedMission", function() v = Pda.Map:GetSelectedMission() end)
    return v
end

-- ---- The PDA itself -----------------------------------------------------------------------------------
-- Ess.Pda.suppress(bOn) -- hide the PDA entirely. The game uses this for briefings and cutscenes.
function Ess.Pda.suppress(bOn)
    Ess.Safe.named("Ess.Pda.suppress", function() Pda:SetSuppressed({ bSuppress = bOn and true or false }) end)
    return true
end

-- Ess.Pda.attitude(sFaction, nAttitude [,sTexture]) -- set a faction's displayed attitude on the database
-- screen. Display only; the real relation lives in Ess.Relations.
function Ess.Pda.attitude(sFaction, nAttitude, sTexture)
    if type(sFaction) ~= "string" or sFaction == "" then
        Ess.Safe.reject("Ess.Pda.attitude", "sFaction must be a non-empty string")
        return false
    end
    Ess.Safe.named("Ess.Pda.attitude", function()
        Pda.Database:SetFactionAttitude({ sName = sFaction, nAttitude = tonumber(nAttitude),
                                          sTexture = sTexture })
    end)
    return true
end
