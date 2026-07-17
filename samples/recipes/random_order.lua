-- RECIPE: shuffle a list and sample from it -- the engine-safe way.
-- Namespaces: Ess.RNG.
--
-- random_selection covers a single weighted roll; this covers ORDER. `table.sort` with a random comparator
-- is biased and can even error (an inconsistent comparator is undefined behavior), so Ess.RNG gives you a
-- proper Fisher-Yates shuffle and a distinct-sample helper. Each Ess.RNG.new() is its own stream, so two
-- systems shuffling in the same tick don't perturb each other.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local rng = Ess.RNG.new()          -- seeded from the wall clock

-- shuffle a spawn order in place (unbiased)
local order = {}
for i = 1, 10 do order[i] = i end
rng:shuffle(order)

-- pull 3 DISTINCT templates out of a pool (sample without replacement) -- e.g. pick this wave's enemies
local pool = { "AH1Z", "Mi35", "UH1 Transport", "A10", "Veyron" }
local wave = rng:pickN(pool, 3)

-- verify: shuffle kept all 10 elements (just reordered), and the sample is 3 distinct entries
local sortedCheck = {}
for i = 1, #order do sortedCheck[i] = order[i] end
table.sort(sortedCheck)
local intact = (#order == 10)
for i = 1, 10 do if sortedCheck[i] ~= i then intact = false end end

local distinct, seen = (#wave == 3), {}
for _, v in ipairs(wave) do if seen[v] then distinct = false end seen[v] = true end

local ok = intact and distinct
Ess.Log("[recipe] random_order: shuffled 10 (intact=" .. tostring(intact) .. ")  wave=" .. Ess.Str.join(wave, ", "))
Ess.Log("[SMOKE] random_order: " .. (ok and "PASS" or "FAIL"))
