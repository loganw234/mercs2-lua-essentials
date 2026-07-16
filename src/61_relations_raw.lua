-- Ess/61_relations_raw.lua -- Ess.Raw.Relations: single-pair snapshot/set/restore primitives.
--
-- API:
--   Ess.Raw.Relations.snapshot(ga, gb) -> { ok, val }
--   Ess.Raw.Relations.set(ga, gb, val) -> ok
--   Ess.Raw.Relations.restore(ga, gb, snap) -> ok

local Ess = _G.Ess
Ess.Raw = Ess.Raw or {}
Ess.Raw.Relations = Ess.Raw.Relations or {}

-- Ess.Raw.Relations.snapshot(ga, gb) -> { ok = bool, val = number|nil }
-- `ok` is the load-bearing field here: it distinguishes "read a real value" from "the read itself
-- failed" -- collapsing those two into one slot (as ContractFramework.lua's `_applyRelations` does,
-- `o1ok and o1`) is CONFIRMED to lose the distinction between a genuine 0 (neutral) and "unknown,"
-- because Lua's `and` short-circuits to `false` the instant ok is false, and `if s[3] then` then
-- silently skips restoring that direction forever. Keeping ok/val separate is what fixes it.
function Ess.Raw.Relations.snapshot(ga, gb)
    local ok, val = pcall(Ai.GetRelation, ga, gb)
    return { ok = ok and true or false, val = (ok and val) or nil }
end

function Ess.Raw.Relations.set(ga, gb, val)
    local ok = pcall(Ai.SetRelation, ga, gb, val)
    return ok and true or false
end

-- Ess.Raw.Relations.restore(ga, gb, snap) -> ok
-- CONFIRMED FIX for the gap in ContractFramework.lua's `_restoreRelations` (Known Bug #3): if the
-- ORIGINAL read failed (snap.ok == false), there is genuinely nothing to restore TO -- log it honestly
-- instead of silently no-oping, so the gap is visible rather than invisible. If the read DID succeed,
-- always restore, even when the original value itself was 0 (neutral is a real, valid value to restore).
function Ess.Raw.Relations.restore(ga, gb, snap)
    if not snap or not snap.ok then
        Ess.Log("Relations.restore: no valid original reading for " .. tostring(ga) .. "->" .. tostring(gb) ..
            " (the snapshot read itself failed) -- cannot restore, leaving the current value in place")
        return false
    end
    return Ess.Raw.Relations.set(ga, gb, snap.val)
end
