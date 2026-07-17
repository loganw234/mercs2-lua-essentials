-- RECIPE: parse and reshape text and tables -- the stdlib gaps Lua 5.1 leaves you to hand-roll.
-- Namespaces: Ess.Str, Ess.Table.
--
-- Lua 5.1's `string` and `table` libraries are thin: no split, no trim, no map/filter, no "is this value in
-- here." Ess.Str and Ess.Table fill those in (pure Lua, no engine calls) so you're not rewriting them in
-- every mod. Everything here is deterministic, so the [SMOKE] check is real assertions, not "it ran clean."

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- Ess.Str: split a config line on a LITERAL comma, trim each field, rejoin. (Ess.Table.map runs trim over
-- the whole list in one pass.)
local raw      = "VZ, Pmc ,China"
local factions = Ess.Table.map(Ess.Str.split(raw, ","), Ess.Str.trim)   -- { "VZ", "Pmc", "China" }
local line     = Ess.Str.join(factions, " vs ")                          -- "VZ vs Pmc vs China"

-- Ess.Table: filter an array (densely, no holes), then ask questions about it
local evens = Ess.Table.filter({ 1, 2, 3, 4, 5, 6 }, function(n) return n % 2 == 0 end)   -- { 2, 4, 6 }
local hasThree = Ess.Table.contains(factions, "China")                   -- true
local whereVZ  = Ess.Table.indexOf(factions, "VZ")                       -- 1

-- Ess.Str odds and ends you reach for building HUD text
local label = Ess.Str.padLeft("7", 3, "0") .. " " .. Ess.Str.truncate("Objective: destroy the refinery", 18)

local ok = (#factions == 3) and (factions[2] == "Pmc") and (line == "VZ vs Pmc vs China")
    and (#evens == 3) and hasThree and (whereVZ == 1)
    and (label == "007 Objective: dest...")

Ess.Log("[recipe] text_and_tables: '" .. line .. "'  evens=" .. Ess.Str.join(evens, ",") .. "  label='" .. label .. "'")
Ess.Log("[SMOKE] text_and_tables: " .. (ok and "PASS" or "FAIL"))
