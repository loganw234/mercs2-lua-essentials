-- Ess/67_squad_easy.lua -- Ess.Easy.Squad: named one-liners over Ess.Squad's team layer, mirroring
-- Ess.Easy.Followers' own attack/patrol/guard shape but scoped to a team name instead of the whole roster.

local Ess = _G.Ess
Ess.Easy = Ess.Easy or {}
Ess.Easy.Squad = Ess.Easy.Squad or {}

function Ess.Easy.Squad.createTeam(teamName, guids)
    return Ess.Squad.createTeam(teamName, guids)
end

function Ess.Easy.Squad.assignRole(guid, roleType)
    return Ess.Squad.assignRole(guid, roleType)
end

function Ess.Easy.Squad.orderTeamAttack(teamName, target)
    return Ess.Squad.orderTeam(teamName, "attack", { target = target })
end

function Ess.Easy.Squad.orderTeamPatrol(teamName, points)
    return Ess.Squad.orderTeam(teamName, "patrol", { points = points })
end

function Ess.Easy.Squad.orderTeamGuard(teamName, at)
    return Ess.Squad.orderTeam(teamName, "defend", { at = at })
end

-- Ess.Easy.Squad.orderTeamFollow(teamName) -> ok -- returns just this team to following (vehicle-aware,
-- same smartFollow dispatch as Ess.Followers.order("follow", ...) -- see that file's header).
function Ess.Easy.Squad.orderTeamFollow(teamName)
    return Ess.Squad.orderTeam(teamName, "follow", {})
end

-- Ess.Easy.Squad.queue(teamName, steps, onComplete) -> ok -- named-callback-only shorthand over
-- Ess.Squad.queue; use Ess.Squad.queue directly for onCancel or per-step timeouts.
function Ess.Easy.Squad.queue(teamName, steps, onComplete)
    return Ess.Squad.queue(teamName, steps, { onComplete = onComplete })
end

function Ess.Easy.Squad.cancelQueue(teamName)
    return Ess.Squad.cancelQueue(teamName)
end

function Ess.Easy.Squad.mountUp(vehGuid, teamName)
    return Ess.Squad.Tactics.mountUp(vehGuid, teamName)
end

function Ess.Easy.Squad.dismountAndSecure(teamName, atPos, radius)
    return Ess.Squad.Tactics.dismountAndSecure(teamName, atPos, radius)
end

-- Ess.Easy.Squad.setFormation(teamName, formationType) -> ok -- follows the local player in "wedge"/
-- "column"/"line"/"diamond" at Ess.Squad.setFormation's own default spacing.
function Ess.Easy.Squad.setFormation(teamName, formationType)
    return Ess.Squad.setFormation(teamName, formationType)
end

function Ess.Easy.Squad.clearFormation(teamName)
    return Ess.Squad.clearFormation(teamName)
end
