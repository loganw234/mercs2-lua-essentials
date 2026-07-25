-- Ess/67_squad.lua -- Ess.Squad: an opt-in team/role layer over Ess.Followers, for scripts managing enough
-- followers that "the whole roster" stops being the right unit of command. Built entirely on
-- Ess.Followers (specifically ._orderScoped, see that file's own header) -- no new native calls, no
-- separate roster; a "team" is just a named, ordered subset of guids that are ALREADY Ess.Followers
-- members.
--
-- API:
--   Ess.Squad.createTeam(teamName, guids)         (re)defines a team's membership -- non-followers dropped
--   Ess.Squad.team(teamName) -> guids             current LIVE membership (self-pruned on read, see below)
--   Ess.Squad.teamOf(guid) -> teamName|nil        which team a guid was last assigned to (auxiliary index)
--   Ess.Squad.assignRole(guid, roleType)          a free-form role string ("driver"/"heavy"/...), consumed
--                                                  by later modules (e.g. Tactics.mountUp), not enforced here
--   Ess.Squad.roleOf(guid) -> roleType|nil
--   Ess.Squad.orderTeam(teamName, behavior, opts) -> ok    Ess.Followers.order(), scoped to one team
--   Ess.Squad.on(eventName, fn) -> stop()          forwards to Ess.Followers.on -- see that file's header
--                                                  for the event list ("onRecruit"/"onDismiss"/
--                                                  "onFollowerDown" today; Squad's own later events --
--                                                  onStepComplete/onQueueComplete/onVehicleMounted/... --
--                                                  fire through this SAME bus, not a second one)
--
-- WHY NO SEPARATE ROSTER: a team member who dies or gets dismiss()'d already self-prunes out of
-- Ess.Followers' own roster; team() re-checks Ess.Followers.isFollower() on every read instead of hooking
-- into dismiss/death itself, so a team's membership can never point at a guid that's no longer a follower
-- -- the mirror image of Ess.Followers.list()'s OWN prune (that one prunes on WRITE, since it owns the
-- roster; team() can't do that, since it's a secondary index over someone else's).
--
-- WHY orderTeam DOESN'T JUST FILTER order()'s RESULT: see Ess.Followers._orderScoped's header --
-- destination markers and the natural-completion auto-resume-follow callback are tracked PER SCOPE, not
-- against one shared "last order" slot, specifically so two teams ordered independently don't clear or
-- resume-follow each other's still-in-flight order.

local Ess = _G.Ess
Ess.Squad = Ess.Squad or {}

local teams = {}   -- teamName -> ordered guid list, as given to createTeam (NOT pre-filtered -- team() below
                    -- filters on every read instead, see header)
local teamOf = {}  -- guid-key -> teamName last assigned via createTeam (auxiliary/best-effort: a guid
                    -- dismissed from Followers entirely still shows its last team here -- team()'s own
                    -- read-time filter is the authority on CURRENT membership, not this index)
local roles = {}   -- guid-key -> free-form role string

local function key(guid) return tostring(guid) end

-- "__all__" is Ess.Followers._orderScoped's own reserved scope for the whole-roster order() -- refusing it
-- as a team name keeps a stray same-named team from silently corrupting that unrelated tracking.
local RESERVED_TEAM_NAME = "__all__"

function Ess.Squad.createTeam(teamName, guids)
    if not teamName or tostring(teamName) == RESERVED_TEAM_NAME then return false end
    local tName = tostring(teamName)
    local list = {}
    for _, g in ipairs(guids or {}) do
        if Ess.Followers.isFollower(g) then
            list[#list + 1] = g
            teamOf[key(g)] = tName
        end
    end
    teams[tName] = list
    return true
end

function Ess.Squad.team(teamName)
    local out = {}
    for _, g in ipairs(teams[tostring(teamName or "")] or {}) do
        if Ess.Followers.isFollower(g) then out[#out + 1] = g end
    end
    return out
end

-- Ess.Squad.teams() -> names -- every team name currently defined via createTeam, sorted for a stable
-- read. Doesn't filter out a team that's since emptied out to zero live members (a caller who cares checks
-- #Ess.Squad.team(name) themselves) -- this just answers "what team NAMES exist," the same "list what's
-- registered" need Ess.Loop.list()/Ess.Followers.list() already answer for their own registries. Added for
-- the Followers/Squad web tool -- external tooling has no other way to discover team names that weren't
-- created by that same tooling instance.
function Ess.Squad.teams()
    local out = {}
    for name in pairs(teams) do out[#out + 1] = name end
    table.sort(out)
    return out
end

function Ess.Squad.teamOf(guid)
    return teamOf[key(guid)]
end

function Ess.Squad.assignRole(guid, roleType)
    if not guid then return false end
    roles[key(guid)] = roleType
    return true
end

function Ess.Squad.roleOf(guid)
    return roles[key(guid)]
end

-- Ess.Squad.orderTeam(teamName, behavior, opts) -> ok -- empty/unknown team is a safe no-op (matches
-- Ess.Followers.order()'s own "empty roster does nothing" behavior).
function Ess.Squad.orderTeam(teamName, behavior, opts)
    local list = Ess.Squad.team(teamName)
    if #list == 0 then return false end
    return Ess.Followers._orderScoped(tostring(teamName), list, behavior, opts)
end

Ess.Squad.on = Ess.Followers.on

-- Ess.Squad._resolveGuids(targetGroup) -> guids -- internal helper shared with 67_squad_queue.lua/
-- 67_squad_tactics.lua. Each src/*.lua file gets its own do...end scope (see build/merge.py's own header
-- for why), so a plain `local` here wouldn't be visible there -- exposed on the shared Ess.Squad table
-- instead, same cross-file pattern Ess.Followers._orderScoped/._issue/._emit already use. Accepts EITHER a
-- team name (resolved via Ess.Squad.team, already live-pruned) or a raw guid list, used as-is.
function Ess.Squad._resolveGuids(targetGroup)
    if type(targetGroup) == "string" then return Ess.Squad.team(targetGroup) end
    return targetGroup or {}
end
