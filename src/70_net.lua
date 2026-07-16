-- Ess/70_net.lua -- Ess.Net.hijackCallback: safely extend an existing engine callback without swallowing
-- other traffic on it, generalized from ModNet.lua's own confirmed real-world fix.
--
-- API:
--   Ess.Net.hijackCallback(moduleTable, name, isMinePredicate, onMine) -> ok
--
-- CONFIRMED REAL-WORLD PROBLEM this solves (ModNet v1.1's own fix): `MrxFactionManager.NetEventCallback`
-- is SHARED with the game's own faction traffic on the same custom-event id. An earlier, naive hijack
-- (`MrxFactionManager.NetEventCallback = function(...) handle it end`, ignoring anything not recognized)
-- unconditionally claimed every packet on that id, which silently swallowed the game's own co-op join/
-- faction-sync events -- the real, shipped root cause of a co-op BLACK SCREEN on connection. The fix:
-- mark every packet YOU send with a magic value, and in the hijacked callback only claim packets that
-- carry your marker -- everything else passes straight through to whatever the original callback would
-- have done with it.
--
-- `Ess.Net.hijackCallback` extracts that exact recipe (mark -> check -> claim-mine-or-passthrough) as a
-- reusable primitive for ANY always-resident callback a future mod wants to safely extend, not just this
-- one. It's built on `Ess.Override.wrap` (90_override.lua) rather than hand-rolling a second copy of the
-- tail-call-avoidance machinery -- and is, if anything, SAFER than ModNet's own literal code: ModNet's own
-- pass-through line is `return orig(evt, tArgs)`, itself a tail call (apparently fine in that specific
-- confirmed-working co-op-tested case, but this project's own established rule is "never `return
-- fOriginal(...)`," full stop) -- this version never tail-calls the original in EITHER branch.
--
-- moduleTable = the resident module table (e.g. `MrxFactionManager`, already `import()`'d by the caller
--   -- import is FILE-SCOPED, this file doesn't and can't import it for you).
-- name = the field name to hijack (e.g. "NetEventCallback").
-- isMinePredicate(...) -> bool = YOUR marker check, called with whatever arguments the native callback
--   itself receives (shape varies per callback -- this doesn't assume any particular one).
-- onMine(...) = called (pcall-guarded) when isMinePredicate returns true; the original is NOT called for
--   a "mine" packet, exactly matching ModNet's own confirmed-correct behavior (a marker-tagged packet is
--   fully yours, not also forwarded to whatever used to handle that id).

local Ess = _G.Ess
Ess.Net = Ess.Net or {}

function Ess.Net.hijackCallback(moduleTable, name, isMinePredicate, onMine)
    return Ess.Override.wrap(moduleTable, name, function(callOriginal, ...)
        local okp, mine = pcall(isMinePredicate, ...)
        if okp and mine then
            pcall(onMine, ...)
            return
        end
        local a, b, c, d = callOriginal(...)
        return a, b, c, d
    end)
end
