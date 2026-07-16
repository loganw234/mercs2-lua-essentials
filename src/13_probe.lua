-- Ess/13_probe.lua -- Ess.Probe: nearby-object queries and safe "what is this guid" description.
--
-- API:
--   Ess.Probe.nearby(x, y, z, radius, kind, filter) -> { uGuid, ... }
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

-- Ess.Probe.nearby(x, y, z, radius, kind, filter) -> { uGuid, ... }
-- Collapses Pg.FastCollectHumans/GroundVehicles/Buildings/Flying/Tanks/Helicopters (11 separate "find
-- nearby X" native names) into one dispatcher, deduped by guid string across whichever families `kind`
-- selects.
--   kind:   "humans" | "vehicles" | "buildings" | nil/"any" (humans + ground vehicles + flying)
--   filter: optional Object.HasLabel string (e.g. "VZ") -- only objects carrying that label are kept
function Ess.Probe.nearby(x, y, z, radius, kind, filter)
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
    local seen, out = {}, {}
    for _, fn in ipairs(fns) do
        local ok, t = pcall(fn, x, y, z, radius)
        if ok and type(t) == "table" then
            for _, u in pairs(t) do
                local key = u and tostring(u)
                if key and not seen[key] then
                    seen[key] = true
                    if not filter or hasLabel(u, filter) then
                        out[#out + 1] = u
                    end
                end
            end
        end
    end
    return out
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
