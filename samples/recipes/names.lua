-- RECIPE: read a hash back as a name -- Ess.Names / Ess.Named.
-- Namespaces: Ess.Names, Ess.Player, Ess.Name.
--
-- The engine addresses everything by a one-way 32-bit hash, so Ess.Name(guid) gives you "0x4000563D", not a
-- word. Ess.Names inverts that using an optional ~23k-entry table (deploy scripts/OnLoad/2_EssNames.lua and
-- add its [OnLoad] line -- see GETTING_STARTED / the release README). With the table absent every call here
-- still returns cleanly (nil / the bare hash), so this recipe passes either way and TELLS you which it saw.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- Is the optional table deployed? Not a failure if not -- just less to show.
local installed = Ess.Names.installed()
Ess.Log("[recipe] names: table " .. (installed and ("installed, " .. Ess.Names.count() .. " names")
                                                or "NOT installed (deploy 2_EssNames.lua to enable)"))

-- Ess.Named(guid): Ess.Name with the meaning put back. For a placed, named world object the guid IS its name
-- hash, so this reads as "name (0xHASH)"; for a fresh spawn (a transient handle) you get the bare hash back.
local me = Ess.Player.character(0)
local shown = Ess.Named(me)
Ess.Log("[recipe] names: player -> " .. tostring(shown) .. "  (raw: " .. tostring(Ess.Name(me)) .. ")")

-- Ess.Names.of(hash): the direct reverse lookup. A miss is nil -- never a fabricated name. Demonstrate on a
-- known real asset when the table is present.
if installed then
    local sample = "0xE54047D5"            -- al_veh_boat_destroyer, a real retail asset
    Ess.Log("[recipe] names: " .. Ess.Names.label(sample))
end

-- PASS = the API answered without throwing: Ess.Named returned a string for a valid object, and label always
-- yields a string even for an unknown hash.
local ok = (type(shown) == "string") and (type(Ess.Names.label("0xDEADBEEF")) == "string")
Ess.Log("[SMOKE] names: " .. (ok and "PASS" or "FAIL"))
