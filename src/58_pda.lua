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
--   Ess.Pda.mission(sName, tOpts)           register a real, trackable PDA mission
--   Ess.Pda.missionExists(sName)            the only existence test there is (see its note)
--   Ess.Pda.removeMission(sName)            removes it AND its blips
--   Ess.Pda.selectMission(sName)            set the tracked mission (nil clears)
--   Ess.Pda.trackable(sName, bOn)
--   Ess.Pda.onMissionTrack(fn)              fn(sMission) on track, fn(nil) on untrack
--   Ess.Pda.allowMissionChange(bOn)
--   Ess.Pda.fakePlayerLocation(x, y, z)     draw the player marker elsewhere (no args clears)
--   Ess.Pda.region(uGuid, tOpts) / Ess.Pda.removeRegion(uGuid)
--   Ess.Pda.beaconTutorial(bOn)
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
-- Ess.Pda.ICONS -- the PDA map's icon vocabulary. The names come from a fixed table (mrxutil.lua's
-- tObjPdaMarker) that MrxUtil.MarkerGetIndexByName_Pda linear-searches, complaining and returning index 0
-- for anything it does not recognise. That lookup gates the CO-OP BROADCAST, which sends an index rather
-- than a string; local rendering passes the string straight to the movie, so an unlisted name can still
-- draw locally and simply fail to replicate.
--
-- ⚠ "icon_yellow_mc" IS DELIBERATELY ABSENT, even though it is in the engine's table -- twice, in fact.
-- IT DRAWS NOTHING. Verified with four otherwise-identical blips side by side: icon_action_1_mc and
-- icon_deliverable_1_mc rendered, while icon_yellow_mc and a blip with no texture at all were both blank.
-- It is a registered name that resolves to no art.
--
-- That is worth more than one entry in a list, because icon_yellow_mc is THE ENGINE'S OWN FINAL FALLBACK
-- (`tBlip.sTexture or tMissionData.sDefaultBlipTexture or "icon_yellow_mc"`) and was AddMapMission's
-- default for sDefaultBlipTexture. So any blip that falls all the way through the chain is invisible by
-- construction -- which is also the real reason Ess.Mark's PDA blips have never shown up, a symptom
-- previously blamed on their missing label.
--
-- The _1/_2/_3 suffixes are objective tiers; tier 3 is the "tertiary" set the PDA can filter out wholesale.
Ess.Pda.ICONS = {
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
-- sTexture defaults to "icon_action_1_mc" and sLabel defaults to sName, because omitting either fails in a
-- way that looks like the call did not work at all:
--
--   * A BLIP WITH NO DRAWABLE ICON IS INVISIBLE -- placed and hoverable, but nothing rendered until the
--     cursor is over it. Note this is NOT simply "no texture": the engine's fallback chain ends at
--     icon_yellow_mc, which itself draws nothing (see Ess.Pda.ICONS), so falling through is exactly as
--     invisible as passing nothing. Hence a default that actually renders.
--   * NO LABEL = THE BLIP DISPLAYS ITS TEXTURE NAME. The render path builds a positional array whose 6th
--     slot is `tBlip.sLabel or tMissionData.sDefaultBlipLabel`; with no label and no owning mission that
--     slot is nil, and what the movie shows instead is the texture. Confirmed live -- an unlabelled blip
--     read "icon_verify_1_mc" on screen.
--
-- Pass sTexture = false to genuinely opt out of the icon.
--
-- ⚠ THOSE DEFAULTS ARE SUPPRESSED WHEN THE BLIP BELONGS TO A MISSION, and that matters. The render path is
-- `tBlip.sTexture or tMissionData.sDefaultBlipTexture or "icon_yellow_mc"` and the label works the same way,
-- so a default supplied HERE wins over the mission's and the blip can never inherit. Defaulting
-- unconditionally therefore made sMission's whole reason for existing unreachable -- caught on screen, where
-- mission blips showed the generic yellow dot instead of their mission's icon. With sMission set, both
-- fields are left nil so the mission supplies them; the engine's own final fallback still guarantees an
-- icon, so the invisible-blip trap stays closed either way.
--
-- Other fields: uGuid (attach to an object instead of coordinates), sMission, nMeter, bSticky, bTodoList,
-- sFaction (the wrapper defaults it to "PMC"), nSortOrder (defaults to 5).
--
-- Two things a mission blip gets for free, both from the same association: it turns STICKY while its
-- mission is the tracked one (which is what makes it stand out on the map), and it becomes selectable as a
-- tracking target when Ess.Pda.allowMissionChange is on.
--
-- Blips are NOT tracked for teardown here -- use Ess.Track:pda(sName) if you want automatic cleanup, which
-- is what it already exists for.
function Ess.Pda.blip(sName, tOpts)
    if type(sName) ~= "string" or sName == "" then
        Ess.Safe.reject("Ess.Pda.blip", "sName must be a non-empty string")
        return false
    end
    local o = type(tOpts) == "table" and tOpts or {}
    -- A blip owned by a mission inherits that mission's icon and label, so defaulting either here would
    -- silently win over it. See the note above.
    local owned = type(o.sMission) == "string" and o.sMission ~= ""
    local tex = o.sTexture
    if tex == false then tex = nil
    elseif tex == nil and not owned then tex = "icon_action_1_mc" end
    local label = o.sLabel
    if label == nil and not owned then label = sName end
    Ess.Safe.named("Ess.Pda.blip", function()
        Pda.Map:AddBlip({
            sName = sName,
            nX = tonumber(o.nX), nY = tonumber(o.nY),
            sLabel = label, sDesc = o.sDesc,
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

-- ---- Missions -----------------------------------------------------------------------------------------
-- Ess.Pda.FACTIONS -- the seven codes the PDA recognises. sFaction is looked up in _tFactionNameLookup to
-- get a display name, and anything not in this list resolves to nil and shows no faction. Uppercase.
Ess.Pda.FACTIONS = { "PMC", "AN", "CH", "GR", "OC", "PR", "VZ" }

-- Ess.Pda.mission(sName, tOpts) -> bool -- register a mission, or update one that already exists.
--
-- This is the piece that turns a loose blip into something the PDA treats as a real objective. A blip whose
-- sMission names a registered TRACKABLE mission is rendered as a mission blip, inherits that mission's
-- default icon and label, and can be selected as the player's tracked objective. Ess.Contract is the
-- obvious consumer.
--
--   tOpts.sLabel      the mission's name in the PDA list        REQUIRED for a new mission
--   tOpts.sDesc       its description                           REQUIRED for a new mission
--   tOpts.sFaction    one of Ess.Pda.FACTIONS                   REQUIRED for a new mission
--   tOpts.sIcon       default blip texture for its blips (see Ess.Pda.ICONS)
--   tOpts.sBlipLabel  default blip label for its blips
--   tOpts.bTrackable  default TRUE for a new mission
--   tOpts.bSuppress   hide it; forces bTrackable false and blanks the faction
--   tOpts.nSortOrder  position in the list
--
-- ── THREE THINGS THE NATIVE DOES THAT YOU WOULD NOT GUESS ──────────────────────────────────────────────
--
-- 1. A NEW MISSION IS REJECTED OUTRIGHT unless sLabel, sDesc AND sFaction are all strings -- AddMapMission
--    returns false and does nothing. (Only for a NEW one: updating an existing mission may omit any of
--    them, and each omitted field keeps its old value.) This wrapper checks them up front and rejects with
--    a reason, rather than letting you find out from a `false`.
--
-- 2. sBlipLabel DEFAULTS TO THE STRING "DESIGNER ERROR". Not a placeholder this file invented -- that is
--    literally what mrxguipda.lua puts there, and it renders on the map. Pandemic clearly used it to make
--    a forgotten label impossible to miss in QA. Left as the engine's default rather than silently
--    substituted, because seeing it means you forgot sBlipLabel, and that is worth knowing.
--
-- 3. UPDATES DELIBERATELY GO THROUGH AddMission, NEVER UpdateMission. Pda.Map:UpdateMission is BROKEN by a
--    parameter shift across the wrapper/widget boundary: the wrapper passes tArgs.bTrackable as its 8th
--    positional argument, and UpdateMapMission's 8th parameter is nSortOrder. So asking UpdateMission for
--    bTrackable = true actually sets the SORT ORDER to true, and the trackable flag is untouched. (It is
--    also missing a bTrackable parameter of its own, so it forwards an undeclared global.) AddMapMission's
--    update branch has none of that and handles re-adding an existing name correctly, so this function
--    always uses it. Use Ess.Pda.trackable to change tracking.
function Ess.Pda.mission(sName, tOpts)
    if type(sName) ~= "string" or sName == "" then
        Ess.Safe.reject("Ess.Pda.mission", "sName must be a non-empty string")
        return false
    end
    local o = type(tOpts) == "table" and tOpts or {}
    -- Mirror the native's own new-mission gate so the failure is explained rather than silent. Existing
    -- missions are exempt, matching AddMapMission's update branch -- but we cannot see its mission table
    -- from here, so the check is "you supplied them, or you are relying on an existing entry".
    if not o.bSuppress and (o.sLabel or o.sDesc or o.sFaction) then
        if type(o.sLabel) ~= "string" or type(o.sDesc) ~= "string" or type(o.sFaction) ~= "string" then
            Ess.Safe.reject("Ess.Pda.mission", "a new mission needs sLabel, sDesc AND sFaction as strings "
                            .. "-- the native rejects the whole call otherwise")
            return false
        end
    end
    -- Returns whether the CALL was made, not whether the mission was created -- because the native cannot
    -- tell you. AddMapMission does return a meaningful boolean, but Pda.Map:AddMission throws it away: the
    -- wrapper loops the matching widgets and ignores each result, so it always returns nil. Measured, after
    -- an earlier version of this function reported `false` for three missions that had all been created
    -- correctly. Use Ess.Pda.missionExists when you actually need to know.
    Ess.Safe.named("Ess.Pda.mission", function()
        Pda.Map:AddMission({
            sName = sName, sLabel = o.sLabel, sDesc = o.sDesc, sFaction = o.sFaction,
            sDefaultBlipTexture = o.sIcon, sDefaultBlipLabel = o.sBlipLabel,
            bSuppress = o.bSuppress and true or nil,
            bTrackable = o.bTrackable,
            nSortOrder = tonumber(o.nSortOrder),
        })
    end)
    return true
end

-- Ess.Pda.missionExists(sName) -> bool -- the only way to ask whether a mission is registered.
--
-- There is no getter for the mission table, and every Pda.Map wrapper discards its widget's return value,
-- so nothing reports success directly. This exploits the one native that is CONDITIONAL on existence:
-- SetSelectedMission stores the name only if it is a registered mission, and stores nil otherwise. So
-- selecting a name and reading it back is a genuine existence test -- verified live against three real
-- missions, one never-registered name, and one the guard above had rejected.
--
-- It restores the previous selection afterwards, so it is non-destructive. It is NOT free, though: each
-- selection change emits a Debug.Printf and, on a server, a network event. Do not poll it.
function Ess.Pda.missionExists(sName)
    if type(sName) ~= "string" or sName == "" then
        Ess.Safe.reject("Ess.Pda.missionExists", "sName must be a non-empty string")
        return false
    end
    local prev = Ess.Pda.selectedMission()
    Ess.Pda.selectMission(sName)
    local got = Ess.Pda.selectedMission()
    Ess.Pda.selectMission(prev)
    return got == sName
end

-- Ess.Pda.removeMission(sName) -- remove it AND every blip attached to it. The cascade is the native's own
-- behaviour (RemoveMapMission sweeps tMapBlips for blips whose sMission matches), and it also clears the
-- selection if this was the tracked mission -- so no separate teardown is needed for a mission's blips.
function Ess.Pda.removeMission(sName)
    if type(sName) ~= "string" or sName == "" then
        Ess.Safe.reject("Ess.Pda.removeMission", "sName must be a non-empty string")
        return false
    end
    Ess.Safe.named("Ess.Pda.removeMission", function() Pda.Map:RemoveMission({ sName = sName }) end)
    return true
end

-- Ess.Pda.selectMission(sName) -- set the player's tracked mission; pass nil to clear. A name that is not a
-- registered mission clears the selection rather than erroring, which is the native's behaviour.
function Ess.Pda.selectMission(sName)
    Ess.Safe.named("Ess.Pda.selectMission", function()
        Pda.Map:SetSelectedMission({ sName = sName, bForceOnClient = true })
    end)
    return true
end

-- Ess.Pda.trackable(sName, bOn) -- the working way to change a mission's trackable flag (see note 3 above).
-- A suppressed mission is forced untrackable by the native regardless of what you pass.
function Ess.Pda.trackable(sName, bOn)
    if type(sName) ~= "string" or sName == "" then
        Ess.Safe.reject("Ess.Pda.trackable", "sName must be a non-empty string")
        return false
    end
    Ess.Safe.named("Ess.Pda.trackable", function()
        Pda.Map:SetMissionTrackable({ sName = sName, bTrackable = bOn and true or false })
    end)
    return true
end

-- Ess.Pda.onMissionTrack(fn) -- fn(sMission) when the player TRACKS a mission in the PDA, and fn(nil) when
-- they UNTRACK one. One callback for both, and the argument is how you tell them apart.
--
-- That asymmetry is in the game, not invented here: _HandleTrackEvent appends the mission name to the
-- callback data before unpacking it, and _HandleUntrackEvent unpacks the callback data alone. So with no
-- callback data -- which is what this passes, for the same reason as everywhere else in Ess -- track calls
-- fn with one argument and untrack calls it with none.
--
-- Unlike Ess.On.* this does NOT return a stop(): the native stores a single callback per PDA, so registering
-- is inherently last-one-wins. Pass nil to unregister.
function Ess.Pda.onMissionTrack(fn)
    if fn ~= nil and type(fn) ~= "function" then
        Ess.Safe.reject("Ess.Pda.onMissionTrack", "fn must be a function or nil")
        return false
    end
    Ess.Safe.named("Ess.Pda.onMissionTrack", function()
        Pda.Map:SetMissionTrackCallback({
            fCallback = fn and function(sMission) pcall(fn, sMission) end or nil,
        })
    end)
    return true
end

-- Ess.Pda.allowMissionChange(bOn) -- whether the player may change which mission is tracked. Note the
-- native ignores a `true` on a network client and always disallows there.
function Ess.Pda.allowMissionChange(bOn)
    Ess.Safe.named("Ess.Pda.allowMissionChange", function()
        Pda.Map:SetMissionChangeAllowed({ bAllow = bOn and true or false })
    end)
    return true
end

-- ---- Map presentation ---------------------------------------------------------------------------------
-- Ess.Pda.fakePlayerLocation(x, y, z) -- draw the player marker somewhere other than where they are; pass
-- no arguments to clear it. The game uses this in the PMC interior, where the real position is meaningless
-- on a world map. All three coordinates must be numbers or the native ignores the call.
function Ess.Pda.fakePlayerLocation(x, y, z)
    local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)
    if x ~= nil and not (nx and ny and nz) then
        Ess.Safe.reject("Ess.Pda.fakePlayerLocation", "needs all three of x, y, z as numbers, or none to clear")
        return false
    end
    Ess.Safe.named("Ess.Pda.fakePlayerLocation", function()
        Pda.Map:SetFakePlayerLocation({ nX = nx, nY = ny, nZ = nz })
    end)
    return true
end

-- Ess.Pda.region(uGuid, tOpts) / Ess.Pda.removeRegion(uGuid) -- shade a line region on the PDA map, the
-- counterpart to Ess.Raw.Mark.radarRegion on the minimap.
--
-- Colour handling is the native's, and it is unusual: each channel is clamped to 0..255, the defaults are
-- 64/64/160 at alpha 128 (a muted blue, not black like the radar's), and the ALPHA IS CONVERTED TO A
-- PERCENTAGE internally (a/255*100) while r/g/b become a "0xRRGGBB" string for the Flash movie. So pass
-- alpha in 0..255 like the other channels and let it do the conversion.
function Ess.Pda.region(uGuid, tOpts)
    if uGuid == nil then
        Ess.Safe.reject("Ess.Pda.region", "needs a line-region guid")
        return false
    end
    local o = type(tOpts) == "table" and tOpts or {}
    local rgb = o.rgb
    Ess.Safe.named("Ess.Pda.region", function()
        Pda.Map:AddLineRegion({ uGuid = uGuid,
            nRed = rgb and rgb[1], nGreen = rgb and rgb[2], nBlue = rgb and rgb[3],
            nAlpha = tonumber(o.nAlpha), bInvert = o.bInvert and true or false })
    end)
    return true
end

function Ess.Pda.removeRegion(uGuid)
    if uGuid == nil then
        Ess.Safe.reject("Ess.Pda.removeRegion", "needs a line-region guid")
        return false
    end
    Ess.Safe.named("Ess.Pda.removeRegion", function() Pda.Map:RemoveLineRegion({ uGuid = uGuid }) end)
    return true
end

-- Ess.Pda.beaconTutorial(bOn) -- the PDA's beacon-tutorial mode, which makes the map prompt the player to
-- place a GPS beacon (see Ess.Gps). Used by the game's own GPS tutorial contract.
function Ess.Pda.beaconTutorial(bOn)
    Ess.Safe.named("Ess.Pda.beaconTutorial", function()
        Pda.Map:SetBeaconTutorialMode({ bEnable = bOn and true or false })
    end)
    return true
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
