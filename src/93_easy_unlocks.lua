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
