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

-- Ess.Easy.Followers.orderEnter(vehicleGuid, role) -> ok -- role defaults to "driver" (not AIOrders'
-- own "passenger" default) specifically so a lone follower enters as the one seat that keeps every
-- LATER order (move/attack/guard/...) working through the SAME guid already on the roster.
--
-- CONFIRMED LIVE 2026-07-24 (this was a real open question, not an assumption): NO secondary
-- unit-currently-controls-which-vehicle tracker is needed. Recruited a follower, orderEnter()'d them into
-- a car as driver, then order("move", ...) using their OWN stored human guid (unchanged) -- the CAR
-- drove to the point. Ess.Raw.AIOrders.actor() already implements the established "AI goals target the
-- DRIVER, not the vehicle hull" rule (Vehicle.GetDriver(veh)) -- a follower who's currently driving IS
-- already the correct AIGuid for the engine to steer the vehicle through, so the roster never needs to
-- know "this guid is currently a car." (Bonus confirmed behavior: once that move finished, attack/move's
-- auto-resume-follow fired as usual -- the follower got back OUT of the car and returned to following on
-- foot, same as it would from any other order.) A follower entering as a passenger/gunner instead is
-- still recruit()ed and orderable as themselves, just not "the vehicle."
function Ess.Easy.Followers.orderEnter(vehicleGuid, role)
    return Ess.Followers.order("enter", { target = vehicleGuid, role = role or "driver" })
end

-- Ess.Easy.Followers.showMarkers() / .hideMarkers() -- named aliases for the boolean toggle, see
-- Ess.Followers.setMarkersEnabled's own header for what they actually turn on.
function Ess.Easy.Followers.showMarkers()
    Ess.Followers.setMarkersEnabled(true)
end
function Ess.Easy.Followers.hideMarkers()
    Ess.Followers.setMarkersEnabled(false)
end
