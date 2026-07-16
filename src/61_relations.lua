-- Ess/61_relations.lua -- Ess.Relations: named faction-pair stance sets, applied and restored as one unit.
--
-- Unifies the SAME snapshot->apply->restore pattern independently built twice (ContractFramework.lua's
-- `def.relations`, generic/trigger-aware; WaveDefense.lua's `setupRelations`/`restoreRelations`,
-- snapshot-based) into one implementation, with the restore-on-failed-read gap (Known Bug #3, see
-- 61_relations_raw.lua) fixed at the source instead of needing a third independent fix.
--
-- API:
--   Ess.Relations.apply(pairs [, label]) -> handle   pairs = { {a,b,set}, ... } or { {a=,b=,set=}, ... }
--   Ess.Relations.restore(handle)
--   Ess.Relations.isActive(handle) -> bool
--   Ess.Relations.getFeeling(uGuidA, uGuidB) -> n / .setFeeling(uGuidA, uGuidB, n)   INDIVIDUAL-pair
--                                                relation (Ai.GetFeeling/SetFeeling), distinct from the
--                                                FACTION-level apply/restore above -- no snapshot/restore
--                                                needed, it's a thin direct wrapper
--
-- HANDLE-BASED so two independent callers can NEVER collide (an earlier id-keyed version shared a flat
-- module table -- two callers reusing a generic id like "combat" would restore/overwrite the wrong set).
-- Each apply() mints its own opaque handle carrying its own snapshot; restore(handle) undoes exactly that
-- one apply, nothing else. `label` is optional and purely for log readability. Hold the handle (in your own
-- var, an Ess.Track, or an instance field) until you restore -- there is no global "restore everything"
-- because there is no longer any global registry to collide in.

import("MrxFactionManager")

local Ess = _G.Ess
Ess.Relations = Ess.Relations or {}

-- set values, matching both ContractFramework.lua and WaveDefense.lua's confirmed conventions.
local REL_VALUE = { friend = 100, ally = 100, allied = 100, neutral = 0, enemy = -100, hostile = -100 }
-- faction-name -> MrxFactionManager abbreviation, for SetAttitudeMutable below (ContractFramework.lua's
-- own mapping, confirmed real).
local FACTION_ABBREV = { Allied = "All", China = "Chi", Guerilla = "Gur", OC = "Oil", Pirate = "Pir", VZ = "VZ", PMC = "Pmc" }

local function factionGuid(name)
    local ok, g = pcall(Pg.GetGuidByName, name)
    if ok then return g end
    return nil
end

-- Ess.Relations.apply(pairs [, label]) -> handle
-- `pairs` entries: {a, b, set} or {a=, b=, set=} where `set` is "friend"/"ally"/"neutral"/"enemy"/
-- "hostile" (case-insensitive) or a raw number. Sets BOTH directions (a->b and b->a) to the same value,
-- mirroring both source implementations -- a "mutual stance," not a one-way read.
--
-- Returns an opaque handle. Pass it to Ess.Relations.restore(handle) to undo exactly this set later. Any
-- number of relation sets can be active at once for different purposes and they can't interfere -- each
-- carries its own snapshot on its own handle (unlike WaveDefense's single global W._relSnap, which could
-- only ever track one, and unlike the earlier id-keyed version of THIS function, which two callers could
-- collide in).
function Ess.Relations.apply(pairsList, label)
    local h = { label = label or "relations", snaps = {}, restored = false }
    for _, r in ipairs(pairsList or {}) do
        local a, b = r.a or r[1], r.b or r[2]
        local setVal = r.set or r[3] or "neutral"
        local val = REL_VALUE[tostring(setVal):lower()] or tonumber(setVal) or 0
        local ga, gb = factionGuid(a), factionGuid(b)
        if ga and gb then
            -- CONFIRMED behavior from ContractFramework.lua's own _applyRelations: when a relation
            -- involves PMC specifically, make the OTHER faction's attitude "official" so the HUD reflects
            -- it correctly (SetAttitudeMutable), not just the raw Ai.SetRelation numeric stance below.
            if b == "PMC" and FACTION_ABBREV[a] then pcall(MrxFactionManager.SetAttitudeMutable, FACTION_ABBREV[a]) end
            if a == "PMC" and FACTION_ABBREV[b] then pcall(MrxFactionManager.SetAttitudeMutable, FACTION_ABBREV[b]) end
            h.snaps[#h.snaps + 1] = { ga = ga, gb = gb, snap = Ess.Raw.Relations.snapshot(ga, gb) }
            h.snaps[#h.snaps + 1] = { ga = gb, gb = ga, snap = Ess.Raw.Relations.snapshot(gb, ga) }
            Ess.Raw.Relations.set(ga, gb, val)
            Ess.Raw.Relations.set(gb, ga, val)
            Ess.Log("Relations.apply[" .. h.label .. "]: " .. tostring(a) .. "<->" .. tostring(b) .. " = " .. tostring(setVal))
        else
            Ess.Log("Relations.apply[" .. h.label .. "]: unknown faction '" .. tostring(a) .. "' / '" .. tostring(b) .. "'")
        end
    end
    return h
end

-- Ess.Relations.restore(handle) -- undoes exactly the pairs applied under this handle, back to their
-- pre-apply values (or logs+skips a direction whose original read failed, per the Known Bug #3 fix).
-- Idempotent: restoring an already-restored (or nil) handle is a safe no-op.
function Ess.Relations.restore(h)
    if type(h) ~= "table" or h.restored then return end
    for _, s in ipairs(h.snaps) do
        Ess.Raw.Relations.restore(s.ga, s.gb, s.snap)
    end
    h.restored = true
end

function Ess.Relations.isActive(h)
    return type(h) == "table" and h.restored == false
end

-- Ess.Relations.getFeeling(uGuidA, uGuidB) -> n / .setFeeling(uGuidA, uGuidB, n)
-- CONFIRMED (wiki/namespaces/ai.md): Ai.GetFeeling/SetFeeling is a per-INDIVIDUAL-pair relationship value,
-- distinct from the per-FACTION Ai.GetRelation/SetRelation the apply/restore functions above are built on
-- -- real confirmed use (mrxfollow.lua): SetFeeling(uGuid, uTarget, 100) to neutralize hostility on a
-- SPECIFIC subject before starting a scripted "Follow" role, without touching that subject's whole
-- faction's stance. Pairs naturally with Ess.AIOrders' own "follow" behavior for exactly that case.
--
-- CONFIRMED LIVE GOTCHA this session: a FRESHLY Pg.Spawn'd character's feeling reads back as a stale 0 if
-- queried in the same tick as the spawn -- the same class of "needs a moment to settle" delay already
-- documented for Ess.Bones (hardpoints nil for ~0.3s after spawn). Wait at least one tick/frame after
-- spawning before calling getFeeling/setFeeling on a target you just created.
function Ess.Relations.getFeeling(uGuidA, uGuidB)
    local ok, n = pcall(Ai.GetFeeling, uGuidA, uGuidB)
    return (ok and n) or 0
end

function Ess.Relations.setFeeling(uGuidA, uGuidB, n)
    pcall(Ai.SetFeeling, uGuidA, uGuidB, n)
end
