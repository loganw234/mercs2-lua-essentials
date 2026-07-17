-- Ess/00_core.lua -- bootstrap + Ess.Safe, Ess.Table, Ess.Guid/Ess.Name, Ess.Log.
--
-- Ess is the foundational Lua library for Mercenaries 2 modding: safe, one-line wrappers around every
-- hard-won pattern this project has found, so a new modder doesn't rediscover them by crashing the game
-- first. Full design + rationale for every function: FEATURE_SHEET.md in this repo.
--
-- THIS FILE loads first (00_ prefix, and first in build/merge.py's manifest) and must never depend on
-- anything else in Ess -- everything else depends on it.
--
-- DEPLOY: build/merge.py concatenates every src/*.lua into ONE file, dist/Ess.lua. Drop THAT file into
-- <game>/scripts/OnLoad/ as `1_Ess.lua` with a low lua_loader.ini number (loads before ModNet/uilib/
-- ContractFramework if you use those too -- see lua-bridge-load-order-convention).
--
-- API in this file:
--   Ess.Log(msg)                                   prefixed Loader.Printf, used by the rest of Ess
--   Ess.Safe.call(fn, ...) -> ok, a, b, c, d        pcall + auto-log-on-failure (up to 4 return values)
--   Ess.Safe.quiet(fn, ...) -> ok, a, b, c, d       same, but never logs (for expected-to-sometimes-fail calls)
--   Ess.Safe.string(ok, val, fallback) -> s         only trust a native return as a string if it really is one
--   Ess.Table.compact(t) -> t                       rebuild a numeric array densely (fixes nil-hole #/ipairs desync)
--   Ess.Table collection helpers                    .keys/.values/.count/.isEmpty/.contains/.indexOf,
--                                                    .map/.filter/.find/.reduce, .slice/.reverse, .copy/.merge
--   Ess.Guid(name) -> uGuid | nil                   Pg.GetGuidByName, pcall-wrapped, one canonical name
--   Ess.Name(uGuid) -> sHash | nil                  Sys.GuidToString, pcall-wrapped (confirmed to throw on some objects)

_G.Ess = _G.Ess or {}
local Ess = _G.Ess
Ess.VERSION = "0.2.1"

Ess.Safe = Ess.Safe or {}
Ess.Table = Ess.Table or {}

-- ============================================================
-- Ess.Log -- every Ess.* message goes through this so log lines are consistently prefixed and easy to
-- grep out of lua_loader_printf.log. Guarded so Ess never errors even if Loader itself is somehow absent.
-- ============================================================
function Ess.Log(msg)
    if Loader and Loader.Printf then
        Loader.Printf("[Ess] " .. tostring(msg))
    end
end

-- ============================================================
-- Ess.Safe -- the single most duplicated shape in this whole project: `local ok, r = pcall(...); if not
-- ok then Loader.Printf(...) end`. Fixed-arity (4 return values) rather than a generic table-pack/unpack
-- dance -- plenty for every native call in this corpus, and far simpler to read than the alternative.
-- ============================================================

-- Ess.Safe.call(fn, ...) -> ok, a, b, c, d
-- Wraps ANY engine call (a function reference + its args, OR a zero-arg closure for a multi-statement
-- body). Logs once via Ess.Log on failure.
function Ess.Safe.call(fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then
        Ess.Log("Safe.call failed: " .. tostring(a))
        return false
    end
    return true, a, b, c, d
end

-- Ess.Safe.quiet(fn, ...) -> ok, a, b, c, d
-- Same as Ess.Safe.call but NEVER logs -- for calls that are expected to fail sometimes as part of normal
-- control flow (e.g. probing whether an object has a label), where a log line every failure would just be
-- noise.
function Ess.Safe.quiet(fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return false end
    return true, a, b, c, d
end

-- Ess.Safe.string(ok, val, fallback) -> s
-- Only trust a native return as a string if it really is one -- some calls return an unexpected type
-- (bare userdata) on edge cases, confirmed real (wiki/deep-dives/world-inspector.md's SafeString). Pass
-- Ess.Safe.call's own (ok, val) straight through: `Ess.Safe.string(Ess.Safe.call(Object.GetName, u))`.
function Ess.Safe.string(ok, val, fallback)
    if ok and type(val) == "string" then return val end
    return fallback or "?"
end

-- Ess.Safe.template(sTemplate) -> bool
-- The canonical "is this actually a spawnable template name" test. A blank/whitespace/non-string template
-- makes Pg.Spawn (and everything built on it) hard-CRASH the engine in native C++, and pcall canNOT catch a
-- native crash -- only a Lua error. So every spawn path in Ess must validate the template BEFORE the call.
-- That exact guard is currently re-inlined in ~6 places (Object.spawn / Vehicle.followGhost / Bones.attachFX
-- / UI.Menu ctx:spawn / Contract._safeSpawn); centralising the shape here means a NEW spawn path is one call
-- from safe instead of re-deriving it -- the copter-reinforce path and the original Contract Pg.Spawn gap
-- both missed it by hand. (The existing inline guards can migrate to this opportunistically; not worth
-- re-touching verified code in a batch.) Returns true only for a non-empty, non-whitespace string.
function Ess.Safe.template(sTemplate)
    return type(sTemplate) == "string" and sTemplate:gsub("%s", "") ~= ""
end

-- ============================================================
-- Ess.Table
-- ============================================================

-- Ess.Table.compact(t) -> t (same table, mutated in place, also returned for chaining)
-- Rebuilds a numeric array densely. Fixes the real MissionForge bug: `t[#t] = nil` to "pop" the last
-- element leaves a nil HOLE, and Lua's `#` operator is UNDEFINED on a table with a hole -- that desyncs
-- `#`/`ipairs`/`table.insert` and can silently drop or duplicate entries downstream. Prefer `table.remove`
-- in new code (it never leaves a hole) -- this exists for when a hole already happened (someone else's
-- code, or a sparse table you're about to treat as a dense array) and you need it fixed before continuing.
-- Non-numeric keys in `t` are left untouched.
function Ess.Table.compact(t)
    local keys = {}
    for k in pairs(t) do
        if type(k) == "number" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local out = {}
    for i, k in ipairs(keys) do out[i] = t[k] end
    for k in pairs(t) do
        if type(k) == "number" then t[k] = nil end
    end
    for i, v in ipairs(out) do t[i] = v end
    return t
end

-- ---- collection helpers (pure Lua, the basics the stdlib omits). map/filter/find/indexOf work on the
-- ARRAY part (ipairs); keys/values/count/isEmpty/contains/copy/merge work on the whole table (pairs), since
-- `#t` only ever sees the array part and silently misses map keys. All non-mutating except merge. ----
function Ess.Table.keys(t)   local o = {} for k in pairs(t) do o[#o + 1] = k end return o end
function Ess.Table.values(t) local o = {} for _, v in pairs(t) do o[#o + 1] = v end return o end
function Ess.Table.count(t)  local n = 0  for _ in pairs(t) do n = n + 1 end return n end
function Ess.Table.isEmpty(t) return next(t) == nil end
function Ess.Table.contains(t, val)
    for _, v in pairs(t) do if v == val then return true end end
    return false
end
function Ess.Table.indexOf(t, val)
    for i, v in ipairs(t) do if v == val then return i end end
    return nil
end
function Ess.Table.map(t, fn)
    local o = {}
    for i, v in ipairs(t) do o[i] = fn(v, i) end
    return o
end
function Ess.Table.filter(t, fn)   -- densely packed result, never a hole
    local o = {}
    for i, v in ipairs(t) do if fn(v, i) then o[#o + 1] = v end end
    return o
end
function Ess.Table.find(t, fn)     -- first array element where fn(value,index) is truthy -> value, index
    for i, v in ipairs(t) do if fn(v, i) then return v, i end end
    return nil
end
function Ess.Table.copy(t)         -- SHALLOW copy (nested tables are shared, not cloned)
    local o = {}
    for k, v in pairs(t) do o[k] = v end
    return o
end
function Ess.Table.merge(dst, src) -- shallow-copy src's keys onto dst (src wins), mutating + returning dst
    for k, v in pairs(src or {}) do dst[k] = v end
    return dst
end
function Ess.Table.slice(t, i, j)  -- new array of elements [i..j], 1-based inclusive (defaults 1..#t), clamped
    local n = #t
    i = i or 1; j = j or n
    if i < 1 then i = 1 end
    if j > n then j = n end
    local o = {}
    for k = i, j do o[#o + 1] = t[k] end
    return o
end
function Ess.Table.reverse(t)      -- new array with the order flipped
    local o, n = {}, #t
    for k = 1, n do o[k] = t[n - k + 1] end
    return o
end
function Ess.Table.reduce(t, fn, init)  -- fold the array to one value: acc = fn(acc, value, index) from init
    local acc = init
    for i, v in ipairs(t) do acc = fn(acc, v, i) end
    return acc
end

-- ============================================================
-- Ess.Guid / Ess.Name -- Pg.GetGuidByName and Sys.GuidToString each have both a namespaced form and a
-- bare-global alias on this engine, a confusing duplicate surface -- use these instead of remembering
-- which. Both pcall-wrapped: Sys.GuidToString is CONFIRMED to throw outright on at least one real object.
-- ============================================================

function Ess.Guid(name)
    local ok, g = pcall(Pg.GetGuidByName, name)
    if ok then return g end
    return nil
end

function Ess.Name(uGuid)
    local ok, s = pcall(Sys.GuidToString, uGuid)
    if ok then return s end
    return nil
end
