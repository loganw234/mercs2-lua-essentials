-- RECIPE: read an entity as a typed, named record -- Ess.Inspect.
-- Namespaces: Ess.Inspect, Ess.Player, Ess.Object.
--
-- Ess.Probe.describeSafe gives a one-line string; Ess.Inspect gives a RECORD you can branch on, grouped like
-- the engine's components, with the model/name resolved from their opaque handles via Ess.Names. Inspect the
-- player, print the grouped view, and read a couple of fields off the record directly.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local me = Ess.Player.character(0)

-- the grouped inspector view, to the log
Ess.Inspect.print(me)

-- the record itself is just a table -- pull fields off it
local r = Ess.Inspect.read(me)
if r then
    Ess.Log("[recipe] inspect: model=" .. tostring(r.model) .. " hp=" .. tostring(r.health) .. "/" .. tostring(r.maxHealth))
    Ess.Log("[recipe] inspect: " .. Ess.Inspect.line(me))
end

-- and a nearby vehicle if there is one (models resolve to real names -- civ_veh_car_*, etc.)
local px, py, pz = Ess.Object.pos(me)
local veh = px and Ess.Probe and Ess.Probe.nearest and Ess.Probe.nearest(px, py, pz, 200, "vehicles")
if veh then Ess.Log("[recipe] inspect: nearby vehicle -> " .. Ess.Inspect.line(veh)) end

-- PASS = the read produced a record with a guid and the one-liner is a string (never nil)
local ok = (r ~= nil) and (type(r.guid) == "string") and (type(Ess.Inspect.line(me)) == "string")
Ess.Log("[SMOKE] inspect: " .. (ok and "PASS" or "FAIL"))
