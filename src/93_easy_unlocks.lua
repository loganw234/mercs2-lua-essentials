-- Ess/93_easy_unlocks.lua -- Ess.Easy.Player: one-line progress/gear unlocks (the game's own cheat-menu
-- functions, wired up so a beginner doesn't have to find the module + import it). Ess.Easy.Fun: pure
-- for-the-lulz effects. Every call here is a CONFIRMED real function (most are what mrxcheatbootstrap.lua
-- itself calls), so they're safe cheat-style toggles, not guesses.

import("MrxPmc")
import("MrxTransit")
import("MrxHqManager")
import("MrxRewardData")
import("MrxSupportData")
import("MrxMusic")

local Ess = _G.Ess
Ess.Easy = Ess.Easy or {}
Ess.Easy.Player = Ess.Easy.Player or {}
Ess.Easy.Fun = Ess.Easy.Fun or {}

-- Ess.Easy.Player.giveGrapplingHook() -- unlock the grappling hook. CONFIRMED live (sample OnKey scripts):
-- MrxPmc.AddEquipment("GrapplingHook").
function Ess.Easy.Player.giveGrapplingHook()
    pcall(MrxPmc.AddEquipment, "GrapplingHook")
end

-- Ess.Easy.Player.unlockFastTravel() -- unlock every landing zone so you can fast-travel anywhere.
-- CONFIRMED (MrxTransit.UnlockAllLandingZones, wired to the game's cheat menu).
function Ess.Easy.Player.unlockFastTravel()
    pcall(MrxTransit.UnlockAllLandingZones)
end

-- Ess.Easy.Player.unlockAllHQs() -- unlock every HQ/outpost. CONFIRMED (MrxHqManager.UnlockAllHq).
function Ess.Easy.Player.unlockAllHQs()
    pcall(MrxHqManager.UnlockAllHq)
end

-- Ess.Easy.Player.giveAllRewards() -- dispense every unlock reward at once. CONFIRMED
-- (MrxRewardData.DispenseAllRewards, a cheat-menu function).
function Ess.Easy.Player.giveAllRewards()
    pcall(MrxRewardData.DispenseAllRewards)
end

-- Ess.Easy.Player.freeSupport(bOn) -- ignore all airstrike/support stock + unlock requirements, so you can
-- call any support for free. CONFIRMED (MrxSupportData.SetIgnoreRequirements). Pass false to turn it back on.
function Ess.Easy.Player.freeSupport(bOn)
    if bOn == nil then bOn = true end
    pcall(MrxSupportData.SetIgnoreRequirements, bOn and true or false)
end

-- Ess.Easy.Player.ghost(bOn, i) -- stealth mode: drop your AI detectability to the engine's own floor so AI
-- perception (mostly) can't see you; call again (or pass false) to restore your original value exactly.
-- Built on Ess.Relations.setPerceivability -- Ai.SetPerceivability is LIVE-CONFIRMED reversible
-- (90 -> 30 -> 90, 2026-07-22 probe pass); whether floor-level perceivability makes AI fully blind vs just
-- near-sighted is the read-the-name interpretation and needs the in-game pass. No arg = toggle. Reload-safe:
-- the saved original lives in Ess.State, so an OnKey re-run toggles rather than double-saving.
function Ess.Easy.Player.ghost(bOn, i)
    local S = Ess.State("EssEasyGhost", { on = false, saved = nil })
    local char = Ess.Player.character(i or 0)
    if not char then return false end
    if bOn == nil then bOn = not S.on end
    if bOn and not S.on then
        local n, floor = Ess.Relations.getPerceivability(char)
        if not n then Ess.Log("ghost: couldn't read perceivability"); return false end
        S.saved = n
        Ess.Relations.setPerceivability(char, floor or 0)
        S.on = true
        Ess.UI.Toast("Ghost ON -- AI detectability floored")
    elseif (not bOn) and S.on then
        Ess.Relations.setPerceivability(char, S.saved or 90)
        S.on = false
        Ess.UI.Toast("Ghost OFF -- detectability restored")
    end
    return S.on
end

-- Ess.Easy.Player.skin(sCode, i) -- change the player's whole-figure costume/skin. CONFIRMED
-- (npc-skin-swap project / WardrobeUnlocker): Player.SetOutfit(char, sModelCode) swaps the entire figure
-- (individual body PARTS don't work -- whole "*_hum_*" model only). Confirmed codes include "pmc_hum_fiona",
-- "pmc_hum_eva", "pmc_hum_diablo", "vz_hum_solano", "al_hum_boss", "ch_hum_boss", "gr_hum_boss",
-- "civ_hum_beachfemale_a", "police_hum_officer_b" (plus ~30 more in sample-scripts-onload). A reload
-- restores your normal look. NOTE: a skin swap re-inits the model, so its bones aren't ready for ~0.3s --
-- wait a beat before attaching bone FX (Ess.Easy.Spawn.fxOn) to a JUST-skinned character.
function Ess.Easy.Player.skin(sCode, i)
    local char = Ess.Player.character(i)
    if char and type(sCode) == "string" and sCode ~= "" then pcall(Player.SetOutfit, char, sCode) end
end

-- Ess.Easy.Fun.fanfare(bWin) -- play the mission-success (or, with false, mission-fail) music sting.
-- CONFIRMED (MrxMusic.PlayFanfare, mrxtaskcontract.lua).
function Ess.Easy.Fun.fanfare(bWin)
    pcall(MrxMusic.PlayFanfare, bWin ~= false)
end

-- Ess.Easy.Fun.dance() -- make your character do the "technoviking" dance. CONFIRMED live (snippets): load
-- the animation asset, then Human.PlayRawAnimation. Pure easter egg.
function Ess.Easy.Fun.dance()
    local u = Ess.Player.character(0)
    if not u then return end
    pcall(Pg.LoadAsset, "player_mattias_bare_technoviking", "animation")
    pcall(Human.PlayRawAnimation, u, "player_mattias_bare_technoviking", false, false, 0, false)
end
