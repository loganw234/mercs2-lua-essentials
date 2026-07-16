-- Ess/62_triggers_easy.lua -- Ess.Easy.Triggers: the handful of single-purpose cases that cover most
-- real usage, no spec-table syntax to learn.

local Ess = _G.Ess
Ess.Easy = Ess.Easy or {}
Ess.Easy.Triggers = Ess.Easy.Triggers or {}

function Ess.Easy.Triggers.onPlayerNear(x, y, z, r, fn)
    return Ess.Triggers.arm({ proximity = r, at = { x, y, z } }, fn)
end

function Ess.Easy.Triggers.onDeath(uGuid, fn)
    return Ess.Triggers.arm({ onDestroy = uGuid }, fn)
end

function Ess.Easy.Triggers.after(seconds, fn)
    return Ess.Triggers.arm({ once = seconds }, fn)
end
