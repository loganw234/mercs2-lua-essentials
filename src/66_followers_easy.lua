-- Ess/66_followers_easy.lua -- Ess.Easy.Followers: named calls over the whole current roster, mirroring
-- Ess.Easy.AIOrders' own attack/patrol/guard shape but with no guids param -- Followers already knows who.

local Ess = _G.Ess
Ess.Easy = Ess.Easy or {}
Ess.Easy.Followers = Ess.Easy.Followers or {}

-- Ess.Easy.Followers.recruit(guid) -> ok -- follows the local player (Ess.Player.character(0)) with the
-- confirmed default distances (see 60_aiorders.lua's BEHAVIORS.follow).
function Ess.Easy.Followers.recruit(guid)
    return Ess.Followers.recruit(guid, { target = Ess.Player.character(0) })
end

function Ess.Easy.Followers.orderAttack(target)
    return Ess.Followers.order("attack", { target = target })
end

function Ess.Easy.Followers.orderPatrol(points)
    return Ess.Followers.order("patrol", { points = points })
end

function Ess.Easy.Followers.orderGuard(at)
    return Ess.Followers.order("defend", { at = at })
end

-- Ess.Easy.Followers.showMarkers() / .hideMarkers() -- named aliases for the boolean toggle, see
-- Ess.Followers.setMarkersEnabled's own header for what they actually turn on.
function Ess.Easy.Followers.showMarkers()
    Ess.Followers.setMarkersEnabled(true)
end
function Ess.Easy.Followers.hideMarkers()
    Ess.Followers.setMarkersEnabled(false)
end
