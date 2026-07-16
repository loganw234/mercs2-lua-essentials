-- RECIPE: pick things at random the ENGINE-SAFE way -- random waves, loot tables, spawn scatter.
-- Namespaces: Ess.RNG.
--
-- WHY a helper at all: this engine's Lua is 32-bit float, so the usual big Park-Miller LCG silently loses
-- precision and stops being random. Ess.RNG uses a small generator that stays exact here. Seed it for
-- reproducible tests, or omit the seed for a time-seeded stream.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local rng = Ess.RNG.new(1234)                                  -- reproducible; Ess.RNG.new() = time-seeded

local d6   = rng:int(6)                                        -- an integer in [1, 6]
local coin = rng:chance(0.5)                                   -- true ~half the time
local pick = rng:pick({ "AH1Z", "Mi35", "WZ10" })             -- one element of a list (uniform here; pass
                                                              -- {w=} weights on table entries for weighted)
-- draw a few more and confirm they stay in range AND actually vary (a broken RNG returns the same value)
local a, b, c = rng:int(100), rng:int(100), rng:int(100)
local inRange = d6 >= 1 and d6 <= 6
local varied  = not (a == b and b == c)

Ess.Log(string.format("[recipe] random_selection: d6=%d coin=%s pick=%s  samples=%d,%d,%d",
    d6, tostring(coin), tostring(pick), a, b, c))
Ess.Log("[SMOKE] random_selection: " .. ((inRange and varied and pick ~= nil) and "PASS" or "FAIL"))
