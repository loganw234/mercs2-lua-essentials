-- Ess/17_pursuit.lua -- Ess.Pursuit: the wanted/heat system, wrapped with its two live-confirmed traps
-- encoded so nobody rediscovers them. The underlying Pg.*Pursuit* family was mapped and live-probed in the
-- 2026-07-22 bindings pass (wiki namespaces/pg.md, "Pursuit/Wanted System") -- most of it had zero corpus
-- call sites before that.
--
-- API:
--   Ess.Pursuit.state() -> t | nil        the read channel: { Level, Active, PlayerState, Faction, Locked,
--                                         SecondsLeft, SecondsLeftInLevel, Duration } (idle: Level=0,
--                                         Active=false, Faction=0xFFFFFFFF)
--   Ess.Pursuit.level() -> n              shortcut: state().Level, 0 when idle/unreadable
--   Ess.Pursuit.start(faction, nLevel) -> ok    START a pursuit (real countdown seeded, ~400s at level 3).
--                                         `faction` = "VZ"/"Allied"/"OC"/... name or a faction guid.
--                                         NOTE: starting a pursuit alone spawns nothing to chase you --
--                                         PlayerState stays "Stopped" until faction units actually engage.
--   Ess.Pursuit.clear() -> ok             ★ THE actual reset for an active pursuit (ClearPursuitLock(true)
--                                         drops state to Level=0). The Restrict* calls below do NOT do this.
--   Ess.Pursuit.seconds(faction, n) -> ok       set the remaining pursuit seconds (SetPursuitSeconds)
--   Ess.Pursuit.levelTimes(n1, n2) -> ok        tune level durations (SetPursuitLevelTimes, corpus: 120,300)
--   Ess.Pursuit.lock(faction, nLevel) -> ok     pin the pursuit (LockPursuit; undo with .clear())
--   Ess.Pursuit.custom(faction, nDur, tSettings) -> ok   SetCustomPursuit (corpus-confirmed shape; its
--                                         effect needs an actively-engaged pursuit to observe)
--   Ess.Pursuit.capLevel(nLevel) -> ok    ⚠ ONE-WAY RATCHET DOWN for the whole session -- see below
--   Ess.Pursuit.restrictAll(bOn) -> ok            gate ORGANIC heat buildup on/off (all factions)
--   Ess.Pursuit.restrictFaction(faction, bOn) -> ok        ...for one faction
--   Ess.Pursuit.clearRestrictions() -> ok         drop every restriction
--   Ess.Easy.World.noPursuit(bOn)         one call: stop the current chase AND keep new organic heat off
--                                         (true/nil = on; false = restore normal pursuit behavior)
--
-- ★ THE TWO LIVE-CONFIRMED TRAPS (2026-07-22, both re-verified with GetPursuitState reads between steps):
--   1. `Pg.SetMaxPursuitLevel(n)` is a ONE-WAY RATCHET DOWN for the rest of the session. Nothing raises the
--      ceiling back up -- a bigger n, a (faction, n) form, 99, SetPursuitLevelTimes, SetCustomPursuit were
--      ALL tried and none undo it; only a save-load or full restart resets it. capLevel() therefore logs a
--      loud warning every call -- it's a real capability ("this mode never exceeds heat 2") but it is a
--      session-length commitment, not a tunable.
--   2. `RestrictAllPursuit`/`RestrictPursuitFaction`/`ClearPursuitRestrictions` do NOT clear an active
--      pursuit (despite the names) and do NOT block a scripted .start() -- they only gate ORGANIC (AI-
--      driven) escalation. The off switch for a live chase is .clear(), nothing else.

local Ess = _G.Ess
Ess.Pursuit = Ess.Pursuit or {}
Ess.Easy = Ess.Easy or {}
Ess.Easy.World = Ess.Easy.World or {}

-- faction name -> guid (accepts an already-resolved guid untouched). Names resolve the normal way
-- (Pg.GetGuidByName via Ess.Guid): "Allied", "China", "Guerilla", "OC", "Pirate", "VZ".
local function factionOf(faction)
    if type(faction) == "string" then return Ess.Guid(faction) end
    return faction
end

function Ess.Pursuit.state()
    local ok, t = pcall(Pg.GetPursuitState)
    if ok and type(t) == "table" then return t end
    return nil
end

function Ess.Pursuit.level()
    local t = Ess.Pursuit.state()
    return (t and t.Level) or 0
end

function Ess.Pursuit.start(faction, nLevel)
    local f = factionOf(faction)
    if not f then Ess.Log("Pursuit.start: unknown faction " .. tostring(faction)); return false end
    local ok = pcall(Pg.SetPursuit, f, nLevel or 1, true)
    return ok and true or false
end

function Ess.Pursuit.clear()
    local ok = pcall(Pg.ClearPursuitLock, true)
    return ok and true or false
end

function Ess.Pursuit.seconds(faction, n)
    local f = factionOf(faction)
    if not f then return false end
    local ok = pcall(Pg.SetPursuitSeconds, f, n or 0, true)
    return ok and true or false
end

function Ess.Pursuit.levelTimes(n1, n2)
    local ok = pcall(Pg.SetPursuitLevelTimes, n1 or 120, n2 or 300)
    return ok and true or false
end

function Ess.Pursuit.lock(faction, nLevel)
    local f = factionOf(faction)
    if not f then return false end
    local ok = pcall(Pg.LockPursuit, f, nLevel or 1)
    return ok and true or false
end

function Ess.Pursuit.custom(faction, nDur, tSettings)
    local f = factionOf(faction)
    if not f then return false end
    local ok = pcall(Pg.SetCustomPursuit, f, nDur or 60, tSettings or {})
    return ok and true or false
end

function Ess.Pursuit.capLevel(nLevel)
    Ess.Log("Pursuit.capLevel(" .. tostring(nLevel) .. "): ONE-WAY for this session -- nothing raises the "
        .. "ceiling again until a save-load/restart (live-confirmed)")
    local ok = pcall(Pg.SetMaxPursuitLevel, nLevel or 1)
    return ok and true or false
end

function Ess.Pursuit.restrictAll(bOn)
    if bOn == nil then bOn = true end
    local ok = pcall(Pg.RestrictAllPursuit, bOn and true or false)
    return ok and true or false
end

function Ess.Pursuit.restrictFaction(faction, bOn)
    local f = factionOf(faction)
    if not f then return false end
    if bOn == nil then bOn = true end
    local ok = pcall(Pg.RestrictPursuitFaction, f, bOn and true or false)
    return ok and true or false
end

function Ess.Pursuit.clearRestrictions()
    local ok = pcall(Pg.ClearPursuitRestrictions)
    return ok and true or false
end

-- Ess.Easy.World.noPursuit(bOn) -- the whole thought in one call. ON (true/nil): clear the active chase AND
-- restrict new organic heat, so you stay cold. OFF (false): lift the restriction (any pursuit a script
-- starts explicitly was never blocked either way -- see trap #2 above). Sits beside .clearWanted() (which
-- stays exactly as it was: a one-shot clear with no ongoing restriction).
function Ess.Easy.World.noPursuit(bOn)
    if bOn == nil then bOn = true end
    if bOn then
        Ess.Pursuit.clear()
        Ess.Pursuit.restrictAll(true)
    else
        Ess.Pursuit.restrictAll(false)
    end
end
