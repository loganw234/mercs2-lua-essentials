-- Ess/31_mark_easy.lua -- Ess.Easy.Mark: the preset matching what you're marking, no bools to think about.

local Ess = _G.Ess
Ess.Easy = Ess.Easy or {}
Ess.Easy.Mark = Ess.Easy.Mark or {}

-- radar+PDA, no world icon -- matches WaveDefense's real convention (don't clutter the world with icons
-- for every enemy).
function Ess.Easy.Mark.enemy(uGuid)
    return Ess.Mark.object(uGuid, { radar = true, pda = true, world = false, kind = "action" })
end

-- all three surfaces -- matches ContractFramework's convention for a real mission objective.
function Ess.Easy.Mark.objective(uGuid)
    return Ess.Mark.object(uGuid, { radar = true, pda = true, world = true, kind = "action" })
end

-- world ring only -- the ground-disc "go here" case, no radar/PDA clutter.
function Ess.Easy.Mark.zone(x, y, z, r)
    return Ess.Mark.zone(x, y, z, r, { radar = false, pda = false, world = true })
end
