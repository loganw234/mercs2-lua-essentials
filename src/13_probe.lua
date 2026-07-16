-- Ess/13_probe.lua -- Ess.Probe: nearby-object queries and safe "what is this guid" description.
--
-- API:
--   Ess.Probe.nearby(x, y, z, radius, kind, filter, includeSelf) -> { uGuid, ... }
--   Ess.Probe.nearest(x, y, z, radius, kind, filter, includeSelf) -> uGuid, nDist | nil  the single closest
--   Ess.Probe.getFaction(uGuid) -> sAbbrev | nil
--   Ess.Probe.describeSafe(uGuid) -> sDescription

import("MrxUtil")
import("MrxFactionManager")

local Ess = _G.Ess
Ess.Probe = Ess.Probe or {}

local function hasLabel(u, lbl)
    local ok, r = pcall(Object.HasLabel, u, lbl)
    return ok and r and true or false
end

-- Ess.Probe.nearby(x, y, z, radius, kind, filter, includeSelf) -> { uGuid, ... }
-- Collapses Pg.FastCollectHumans/GroundVehicles/Buildings/Flying/Tanks/Helicopters (11 separate "find
-- nearby X" native names) into one dispatcher, deduped by guid string across whichever families `kind`
-- selects.
--   kind:        "humans" | "vehicles" | "buildings" | nil/"any" (humans + ground vehicles + flying)
--   filter:      optional Object.HasLabel string (e.g. "VZ") -- only objects carrying that label are kept
--   includeSelf: default false. The native FastCollect* calls have no concept of "self" -- a query whose
--                radius covers the caller's own position returns the local player's own character(s)
--                exactly like any other nearby human, indistinguishable from a real result. A caller
--                naming a function "nearby" means "find things near me," not "find me" -- so both local
--                player characters are excluded by default; pass includeSelf=true for the rare case that
--                genuinely wants them (e.g. counting total occupants of a zone). CONFIRMED real-world
--                footgun: an ad hoc test query with a typo'd kind ("character", not a valid kind -- see
--                below) silently fell through to the "any" default, returned only the player's own guid,
--                and a destructive call on it killed the player -- see the
--                ess-probe-nearby-self-inclusion-footgun memory/incident, 2026-07-16.
function Ess.Probe.nearby(x, y, z, radius, kind, filter, includeSelf)
    local fns
    if kind == "humans" then
        fns = { Pg.FastCollectHumans }
    elseif kind == "vehicles" then
        fns = { Pg.FastCollectGroundVehicles, Pg.FastCollectFlying }
    elseif kind == "buildings" then
        fns = { Pg.FastCollectBuildings }
    else
        fns = { Pg.FastCollectHumans, Pg.FastCollectGroundVehicles, Pg.FastCollectFlying }
    end
    local self0, self1
    if not includeSelf then
        self0, self1 = Ess.Player.character(0), Ess.Player.character(1)
    end
    local function isSelf(u) return (self0 and u == self0) or (self1 and u == self1) end
    local seen, out = {}, {}
    for _, fn in ipairs(fns) do
        local ok, t = pcall(fn, x, y, z, radius)
        if ok and type(t) == "table" then
            for _, u in pairs(t) do
                local key = u and tostring(u)
                if key and not seen[key] then
                    seen[key] = true
                    if not isSelf(u) and (not filter or hasLabel(u, filter)) then
                        out[#out + 1] = u
                    end
                end
            end
        end
    end
    return out
end

-- Ess.Probe.nearest(x, y, z, radius, kind, filter, includeSelf) -> uGuid, nDist | nil
-- The single CLOSEST match from Ess.Probe.nearby (same args, same player-excluded-by-default behavior).
-- The "find the one thing near here" case that otherwise means calling nearby() and hand-rolling the
-- min-distance loop every time (Ess.Contract's onDestroy="nearest" trigger does exactly that internally).
-- Returns the guid and its distance, or nil if nothing matched in range.
function Ess.Probe.nearest(x, y, z, radius, kind, filter, includeSelf)
    local best, bestD
    for _, u in ipairs(Ess.Probe.nearby(x, y, z, radius, kind, filter, includeSelf)) do
        local d = Ess.Object.distance(u, x, y, z)
        if d and (not bestD or d < bestD) then best, bestD = u, d end
    end
    return best, bestD
end

-- Ess.Probe.getFaction(uGuid) -> sAbbrev | nil
-- MrxUtil.GetFaction -> MrxFactionManager.GetFactionAbbrev fallback chain.
function Ess.Probe.getFaction(uGuid)
    local ok, fac = pcall(MrxUtil.GetFaction, uGuid)
    if ok and fac then
        local ok2, abbr = pcall(MrxFactionManager.GetFactionAbbrev, fac)
        if ok2 and abbr then return abbr end
    end
    return nil
end

-- Ess.Probe.describeSafe(uGuid) -> sDescription
-- A one-line "what is this" for logging/debugging: name, position, health, faction -- every field
-- individually pcall-guarded so ONE bad field can't blank out the whole description.
function Ess.Probe.describeSafe(uGuid)
    if not uGuid then return "<nil>" end
    local name = Ess.Name(uGuid) or "?"
    local okp, x, y, z = pcall(Object.GetPosition, uGuid)
    local pos = "pos?"
    if okp and x then pos = string.format("(%.1f,%.1f,%.1f)", x, y, z) end
    local okh, hp = pcall(Object.GetHealth, uGuid)
    local hpStr = "hp?"
    if okh and hp then hpStr = "hp=" .. tostring(hp) end
    local fac = Ess.Probe.getFaction(uGuid) or "fac?"
    return name .. " " .. pos .. " " .. hpStr .. " " .. fac
end
