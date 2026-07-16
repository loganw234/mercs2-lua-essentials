-- Ess/60_aiorders_easy.lua -- Ess.Easy.AIOrders: named calls hiding `opts`, the three most common orders.

local Ess = _G.Ess
Ess.Easy = Ess.Easy or {}
Ess.Easy.AIOrders = Ess.Easy.AIOrders or {}

function Ess.Easy.AIOrders.attack(guids, target)
    return Ess.AIOrders.command(guids, "attack", { target = target })
end

function Ess.Easy.AIOrders.patrol(guids, points)
    return Ess.AIOrders.command(guids, "patrol", { points = points })
end

-- "guard" is the friendlier name for the "defend" behavior -- hold an area, fight anything inside it.
function Ess.Easy.AIOrders.guard(guids, at)
    return Ess.AIOrders.command(guids, "defend", { at = at })
end
