-- Ess/53_rng.lua -- Ess.RNG: an engine-safe random number generator + weighted pick.
--
-- API:
--   Ess.RNG.new(seed) -> generator
--     generator:next() -> [0,1)     generator:int(n) -> [1,n]     generator:chance(p) -> bool
--     generator:pick(list, weightKey) -> element of list, weighted
--     generator:shuffle(list) -> list (in-place)   generator:pickN(list, n) -> { n distinct elements }

local Ess = _G.Ess
Ess.RNG = {}
Ess.RNG.__index = Ess.RNG

-- Ess.RNG.new(seed) -> generator
--
-- THE big engine gotcha this whole namespace exists to paper over: this engine's Lua numbers are 32-BIT
-- FLOAT (single precision), not the usual 64-bit double -- integers are only exact up to 2^24
-- (16,777,216). The obvious PRNG choice, a Park-Miller/MINSTD LCG (state = state*16807 mod 2^31), SILENTLY
-- DEGENERATES on this engine: state*16807 blows past 2^24 almost immediately and starts rounding, and the
-- generator can get stuck outputting the same value on every call. CONFIRMED: this happened for real in
-- WaveDefense.lua -- every weighted crate/unit roll came out identical for an entire play session before
-- it was diagnosed. The engine's built-in `math.random` is confirmed dead/unusable here too -- don't reach
-- for it either.
--
-- THE FIX (confirmed, engine-verified): a small ZX-Spectrum-style LCG whose entire arithmetic stays under
-- 2^23 no matter what: state = (state * 75) % 65537. Full period 65536, verified well-distributed. Keep
-- any hot integer math YOU do near this under ~2^23 too, for the same reason -- it's not just this
-- generator, it's the engine's whole number type.
--
-- Each Ess.RNG.new() is its OWN independent stream (seeded from the wall clock by default), so two mods
-- drawing from Ess.RNG in the same tick don't perturb each other's sequence the way one shared global
-- generator would.
function Ess.RNG.new(seed)
    local s = tonumber(seed)
    if not s then
        local ok, t = pcall(Sys.RealTime)
        s = (math.floor(((ok and t) or 0) * 1000) % 65536) + 1
    end
    if s < 1 then s = 1 end
    return setmetatable({ state = s }, Ess.RNG)
end

-- :next() -> a float in [0, 1)
function Ess.RNG:next()
    self.state = (self.state * 75) % 65537
    return self.state / 65537
end

-- :int(n) -> an integer in [1, n]
function Ess.RNG:int(n)
    if not n or n < 1 then return 1 end
    return 1 + math.floor(self:next() * n)
end

-- :chance(p) -> true with probability p (0..1); omit p for a coin flip
function Ess.RNG:chance(p)
    if p == nil then p = 0.5 end
    if p >= 1 then return true end
    if p <= 0 then return false end
    return self:next() <= p
end

-- :pick(list, weightKey) -> one element of `list`, weighted by each entry's [weightKey] field (default
-- "w"), falling back to weight 1 for entries missing it.
-- Collapses the same accumulator-loop weighted-pick WaveDefense.lua wrote three separate times
-- (pickUnit/pickDrop/pickCrate, same logic, copy-pasted) into one implementation.
function Ess.RNG:pick(list, weightKey)
    weightKey = weightKey or "w"
    local total = 0
    for _, e in ipairs(list) do total = total + (e[weightKey] or 1) end
    if total <= 0 then return list[1] end
    local r = self:next() * total
    local acc = 0
    for _, e in ipairs(list) do
        acc = acc + (e[weightKey] or 1)
        if r <= acc then return e end
    end
    return list[#list]
end

-- :shuffle(list) -> list -- in-place Fisher-Yates shuffle of the array part, using this generator (returns
-- the same list, for chaining). This is the engine-safe way to randomize order: `table.sort` with a random
-- comparator is biased AND undefined behavior (an inconsistent comparator can error in some Lua builds).
function Ess.RNG:shuffle(list)
    for i = #list, 2, -1 do
        local j = self:int(i)                     -- uniform in [1, i]
        list[i], list[j] = list[j], list[i]
    end
    return list
end

-- :pickN(list, n) -> { ... } -- n DISTINCT random elements (sample without replacement), order randomized.
-- n >= #list returns a shuffled copy of the whole list; n <= 0 returns {}. Never mutates `list`.
function Ess.RNG:pickN(list, n)
    local pool = {}
    for i = 1, #list do pool[i] = list[i] end
    self:shuffle(pool)
    n = math.min(math.max(0, math.floor(tonumber(n) or 0)), #pool)
    local out = {}
    for i = 1, n do out[i] = pool[i] end
    return out
end
