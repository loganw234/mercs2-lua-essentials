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
--   Ess.DEBUG                                      set true to surface every internally-swallowed failure
--   Ess.Safe.call(fn, ...) -> ok, a..f              pcall + auto-log-on-failure (up to 6 return values)
--   Ess.Safe.quiet(fn, ...) -> ok, a..f             same, but only logs when Ess.DEBUG is on
--   Ess.Safe.named(label, fn, ...) -> ok, a..f      .quiet with an explicit label (for closures)
--   Ess.Safe.reject(label, reason) -> nil           record a GUARD rejection (the engine was never called)
--   (no variadic form -- see the note below Ess.Safe.reject for why one was removed rather than shipped)
--   Ess.Safe.string(ok, val, fallback) -> s         only trust a native return as a string if it really is one
--   Ess.Safe.template(sTemplate) -> bool            true only for a usable, non-blank spawn-template string
--   Ess.lastError() -> tRecord | nil                the most recent swallowed failure (msg/label/count)
--   Ess.Safe.stats() -> tArray                      per-callsite failure tallies, worst first (needs Ess.DEBUG)
--   Ess.Safe.reset()                                clear the recorded failures and tallies
--   Ess.Table.compact(t) -> t                       rebuild a numeric array densely (fixes nil-hole #/ipairs desync)
--   Ess.Table collection helpers                    .keys/.values/.count/.isEmpty/.contains/.indexOf,
--                                                    .map/.filter/.find/.reduce, .slice/.reverse, .copy/.merge
--   Ess.Guid(name) -> uGuid | nil                   Pg.GetGuidByName, pcall-wrapped, one canonical name
--   Ess.Name(uGuid) -> sHash | nil                  Sys.GuidToString, pcall-wrapped (confirmed to throw on some objects)
--   Ess.Unname(sHash) -> uGuid | nil                Sys.StringToGuid -- the exact inverse of Ess.Name, for
--                                                    getting a guid through a string-only channel

_G.Ess = _G.Ess or {}
local Ess = _G.Ess
Ess.VERSION = "0.6.1"

Ess.Safe = Ess.Safe or {}
Ess.Table = Ess.Table or {}

-- Ess.DEBUG -- OFF by default. The single most common "why isn't my mod doing anything" wall is that Ess
-- fails SILENTLY on purpose: a wrapper's whole job is to return nil instead of propagating a problem, so a
-- call with a stale guid or a nil argument produces no log line, no error, and no effect. Set
-- `Ess.DEBUG = true` (from a script, or live over the bridge) and everything Ess quietly gave up on starts
-- reporting itself.
--
-- THERE ARE TWO SEPARATE CHANNELS, because there are two genuinely different silences, and the second is
-- the common one:
--
--   1. A THROWN failure -- an engine call raised a real Lua error and a pcall swallowed it.
--      Recorded by Ess.Safe.* below.
--   2. A GUARD REJECTION -- Ess looked at the arguments, decided the call couldn't work, and returned early
--      WITHOUT EVER CALLING THE ENGINE (`if not uChar then return nil end`, a blank spawn template, an AI
--      order with no destination). Recorded by Ess.Safe.reject().
--
-- Channel 2 exists because of a live measurement (2026-07-25, this running game): 14 deliberately-malformed
-- native calls -- nil/garbage/stale guids across Object/Player/Vehicle/Human/Ai/Marker/Camera/Sys/Pg -- threw
-- ZERO Lua errors. They fail safe, returning nil or (for a stale guid) stale values. So in day-to-day use a
-- beginner's mod almost never trips channel 1; it trips channel 2, or the engine no-ops with a straight
-- face. A diagnostic built only on caught errors would have been quiet in exactly the case it was built for.
--
-- That measurement is NOT license to drop the pcall guards, and this file doesn't: the crash/throw cases
-- documented in CONTRIBUTING.md were recorded defensively (any observed crash written down as a fact, with
-- deliberate breadth over pinpoint reproduction), so a rare throw in some other location or game state
-- stays entirely plausible. Both channels are load-bearing; only their relative frequency is now known.
--
-- Deliberately read at CALL time, not captured -- so flipping it mid-session takes effect immediately, and
-- an OnKey script can toggle it. `or false` (not `= false`) so the setting survives a level reload, which
-- re-runs this whole file.
Ess.DEBUG = Ess.DEBUG or false

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
-- ok then Loader.Printf(...) end`. Fixed-arity (6 return values) rather than a generic table-pack/unpack
-- dance: the widest native return in this whole corpus is 4 values (Player.GetTargetUnderReticle's
-- x,y,z,guid), so 6 is real headroom, and a fixed-arity return allocates NOTHING -- these sit inside
-- per-frame heartbeats, where one throwaway table per engine call would be a real cost on this engine's
-- Lua 5.1.
--
-- Every one of these routes failures through recordFailure() below, which is what makes Ess.DEBUG able to
-- see a swallowed error at all. Prefer them over a bare `pcall` in new code for exactly that reason: a bare
-- pcall's failure is invisible to the diagnostics, forever.
--
-- ON FAILURE, ALL OF THEM RETURN A BARE `false` -- deliberately NOT pcall's own `false, errMessage`. Every
-- caller in this framework is shaped `local ok, val = Ess.Safe.quiet(...)`, and handing back the error
-- STRING as `val` would put a truthy non-nil in the slot a caller reads as "the value", turning a clean
-- nil-on-failure into a garbage-on-failure footgun. Read the message via Ess.lastError() instead.
-- ============================================================

-- The recorded-failure state. Kept on Ess (not a file-local) so a level reload -- which re-runs this whole
-- file -- doesn't wipe a session's tally, and so the bridge REPL can read it directly.
Ess.Safe._last = Ess.Safe._last or nil    -- { msg=, label=, count= } of the most recent failure
Ess.Safe._fails = Ess.Safe._fails or 0    -- total swallowed failures this session
Ess.Safe._tally = Ess.Safe._tally or {}    -- [label] = count, only populated while Ess.DEBUG is on
Ess.Safe._labels = Ess.Safe._labels or nil -- lazy [functionRef] = "Namespace.FnName" reverse map

-- The engine namespaces Ess actually calls into, for turning a bare function REFERENCE back into a
-- readable name when something fails. There is no cheap way to ask Lua "what is this function called", so
-- this walks the real global tables once and builds the reverse map. Built LAZILY, on the first failure
-- while Ess.DEBUG is on -- costs nothing at all in the normal (debug-off) case.
--
-- Nested one level deep as well: Graphics.Camera / Graphics.Effect are separate tables Ess.Camera calls
-- through, and would otherwise resolve to nothing.
local ENGINE_NS = {
    "Object", "Ai", "Pg", "Player", "Vehicle", "Sys", "Airstrike", "Human", "Camera", "Event", "Graphics",
    "Marker", "Sound", "Weapon", "ObjectFilter", "Junk", "Gui", "Loader", "Hud", "Net", "Inventory",
    "MrxPmc", "MrxMusic", "MrxUtil", "MrxFactionManager", "MrxVoSequence", "MrxTutorialManager",
    "MrxCopterDrop", "MrxTransit", "MrxSupportData", "MrxRewardData", "MrxHqManager", "WifVzBoundary",
}

local function buildLabelMap()
    local map = {}
    for _, nsName in ipairs(ENGINE_NS) do
        local ns = _G[nsName]
        if type(ns) == "table" then
            -- pcall'd: iterating a native-backed table is not guaranteed safe on this engine, and a
            -- diagnostic helper must never be the thing that breaks a running mod.
            pcall(function()
                for k, v in pairs(ns) do
                    if type(v) == "function" then
                        map[v] = nsName .. "." .. tostring(k)
                    elseif type(v) == "table" and type(k) == "string" then
                        for k2, v2 in pairs(v) do
                            if type(v2) == "function" then
                                map[v2] = nsName .. "." .. k .. "." .. tostring(k2)
                            end
                        end
                    end
                end
            end)
        end
    end
    return map
end

-- resolveLabel(fn) -> string -- only ever called on the failure path with Ess.DEBUG on.
local function resolveLabel(fn)
    if type(fn) ~= "function" then return "?" end
    if not Ess.Safe._labels then Ess.Safe._labels = buildLabelMap() end
    local name = Ess.Safe._labels[fn]
    if name then return name end
    -- A closure: built fresh on every call, so it can never be in the reverse map. There is NO way to
    -- recover a name for one here -- CONFIRMED LIVE 2026-07-25: `type(_G.debug)` is `nil` on this engine.
    -- The debug library isn't merely unused by the shipped scripts (zero occurrences in the whole
    -- decompiled corpus), it is absent outright, so a `debug.getinfo(fn, "S")` fallback -- which an earlier
    -- draft of this file had, guarded -- was confirmed dead code and removed rather than left in looking
    -- like it might do something.
    --
    -- Ess.Safe.named() is therefore the ONLY way to attribute a closure's failure. Use it for any closure
    -- whose identity you'd actually want in a log.
    return "closure"
end

-- recordFailure(fn, err, label) -- the one place a swallowed failure is accounted for.
--
-- Two tiers on purpose. ALWAYS (cheap, unconditional): bump one integer and keep the message, so
-- Ess.lastError() is useful even if you only thought to look after the fact. ONLY WITH Ess.DEBUG ON
-- (expensive): resolve the function to a readable name, tally per-callsite, and log. Getters like
-- Object.GetPosition fail as routine control flow (a dead guid), tens of times per tick inside
-- Ess.Probe.nearby -- so the always-on path has to stay at "increment a number".
local function recordFailure(fn, err, label)
    -- 32-bit float numbers here: integers are only exact to 2^24 (see CONTRIBUTING.md's engine rules), so
    -- stop counting well before precision would start silently lying about the total.
    if Ess.Safe._fails < 16000000 then Ess.Safe._fails = Ess.Safe._fails + 1 end
    local msg = tostring(err)
    if not Ess.DEBUG then
        Ess.Safe._last = { msg = msg, label = label, count = Ess.Safe._fails }
        return
    end
    label = label or resolveLabel(fn)
    local n = (Ess.Safe._tally[label] or 0) + 1
    Ess.Safe._tally[label] = n
    Ess.Safe._last = { msg = msg, label = label, count = Ess.Safe._fails }
    Ess.Log("DEBUG " .. label .. " failed (#" .. n .. "): " .. msg)
end

-- Ess.Safe.call(fn, ...) -> ok, a, b, c, d, e, f
-- Wraps ANY engine call (a function reference + its args, OR a zero-arg closure for a multi-statement
-- body). ALWAYS logs on failure, Ess.DEBUG or not -- for a call whose failure is genuinely abnormal.
function Ess.Safe.call(fn, ...)
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if not ok then
        recordFailure(fn, a)
        if not Ess.DEBUG then Ess.Log("Safe.call failed: " .. tostring(a)) end
        return false
    end
    return true, a, b, c, d, e, f
end

-- Ess.Safe.quiet(fn, ...) -> ok, a, b, c, d, e, f
-- For calls that are expected to fail sometimes as part of normal control flow (probing whether an object
-- has a label, reading a dead guid's position), where a log line every failure would drown the log.
--
-- The failure is still RECORDED either way -- "quiet" now means "quiet unless you asked to hear it", not
-- "invisible". Turning Ess.DEBUG on makes every one of these speak up, which is the whole point of the
-- flag; before this, these calls were unconditionally undiagnosable.
function Ess.Safe.quiet(fn, ...)
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if not ok then
        recordFailure(fn, a)
        return false
    end
    return true, a, b, c, d, e, f
end

-- Ess.Safe.named(sLabel, fn, ...) -> ok, a, b, c, d, e, f
-- Ess.Safe.quiet with the label supplied up front. Use it for a CLOSURE (`Ess.Safe.named("Contract.tick",
-- function() ... end)`) -- a closure is a fresh function object every call, so it can never be in the
-- reverse-name map and would otherwise tally as an indistinguishable "closure".
--
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHICH WRAPPER TO USE -- the rule, because getting it wrong is invisible until you turn Ess.DEBUG on
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--   Ess.Safe.quiet(SomeNative, a, b)          a function REFERENCE. Attributed by the reverse-name map.
--   Ess.Safe.named("Ess.X.y", function() end)  a CLOSURE. Needs the label or it tallies as "closure".
--   Ess.Safe.call(...)                         when a failure is genuinely abnormal and always worth a log.
--   pcall(userCallback, ...)                   a BARE pcall, and correct here: a mod author's error is not
--                                              an Ess failure, and recording it would make Ess.Safe.stats()
--                                              blame the framework for a bug in the mod.
--
-- The closure case matters more than it looks. Any native called with COLON syntax -- the whole Hud.*/Pda.*
-- surface, `Hud.MessageBox:AddMessage{...}` -- cannot be passed as a reference at all, so it MUST be
-- wrapped in a closure, so it must use .named. An audit on 2026-07-26 found 37 such call sites that had
-- reached for .quiet: every failure was being recorded, but all of them landed in one undifferentiated
-- "closure" bucket, which is nearly as undiagnosable as not recording them.
function Ess.Safe.named(sLabel, fn, ...)
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if not ok then
        recordFailure(fn, a, tostring(sLabel))
        return false
    end
    return true, a, b, c, d, e, f
end

-- Ess.Safe.reject(sLabel, sReason) -> nil
-- The GUARD-REJECTION channel (channel 2 in Ess.DEBUG's header). Call it at the point an Ess wrapper gives
-- up on its own arguments, before the engine is involved at all:
--
--     function Ess.Object.heal(uGuid)
--         if not uGuid then return Ess.Safe.reject("Ess.Object.heal", "no guid") end
--         ...
--
-- ALWAYS RETURNS nil, which is what makes that a single line instead of three: `return Ess.Safe.reject(...)`
-- reads as the early-out it already was, and every Ess getter's documented "nil on failure" contract is
-- unchanged. A guard that returns something other than nil (`return false`, `return {}`) should still call
-- this and then return its own value on the next line.
--
-- This is the channel that actually answers "why did nothing happen". Measured on the live game, malformed
-- native calls essentially never throw (see Ess.DEBUG's header), so a beginner's silent mod is nearly always
-- a guard rejection -- and unlike a thrown error, a rejection knows exactly WHY, because Ess is the one that
-- decided. That makes the log line specific ("no guid") instead of a generic engine error string.
--
-- Costs one function call and one boolean test when Ess.DEBUG is off. Deliberately not wrapped in an
-- `if Ess.DEBUG then` at every call site: that would put the flag check in ~200 places and make the guards
-- three lines each, for a saving that does not matter next to the engine call the guard is skipping.
function Ess.Safe.reject(sLabel, sReason)
    if not Ess.DEBUG then return nil end
    local label = tostring(sLabel)
    local n = (Ess.Safe._tally[label] or 0) + 1
    Ess.Safe._tally[label] = n
    Ess.Safe._last = { msg = "rejected: " .. tostring(sReason), label = label, count = Ess.Safe._fails,
                       rejected = true }
    Ess.Log("DEBUG " .. label .. " rejected (#" .. n .. "): " .. tostring(sReason))
    return nil
end

-- NO VARIADIC FORM ON PURPOSE. An `Ess.Safe.callv` passing through every return value instead of the fixed
-- six was written and then deliberately removed: nothing in Ess needs it (the widest native return in the
-- corpus is 4 values), so it would have shipped as an untested code path for a hypothetical caller --
-- exactly what CONTRIBUTING.md's "never let an unverified engine change ride into a release" rules out. It
-- would also have needed `select("#", ...)` and `unpack` to handle trailing nils correctly (a plain
-- `{pcall(...)}` reports `#r == 2` for a result of `true, 1, nil`, silently dropping the third value). Both
-- do exist on this engine -- `unpack` appears 76 times in the decompiled corpus, and `select` is exercised
-- live by samples/recipes/a_quick_mission.lua on every smoke run -- so if a >6-value native call is ever
-- found, this is buildable. Until one is, it stays unbuilt.

-- ============================================================
-- Diagnostics -- the read side of what Ess.Safe records.
-- ============================================================

-- Ess.lastError() -> { msg=, label=, count= } | nil
-- The most recent failure Ess swallowed. `label` is only populated for failures that happened while
-- Ess.DEBUG was on (resolving it is the expensive half) -- so the usual shape is: notice nothing happened,
-- set Ess.DEBUG = true, do it again, then read this.
function Ess.lastError()
    return Ess.Safe._last
end

-- Ess.Safe.stats() -> { {label=, count=}, ... }  (worst first) , nTotalFailures
-- Which calls are failing, and how often. Only tallies failures recorded while Ess.DEBUG was on; the
-- second return is the unconditional session total, so a zero-length array next to a big total means
-- "plenty failed, but before you turned DEBUG on".
function Ess.Safe.stats()
    local out = {}
    for label, count in pairs(Ess.Safe._tally) do
        out[#out + 1] = { label = label, count = count }
    end
    table.sort(out, function(x, y)
        if x.count == y.count then return x.label < y.label end
        return x.count > y.count
    end)
    return out, Ess.Safe._fails
end

-- Ess.Safe.reset() -- clear the tally, the total and the last error. Handy right before reproducing one
-- specific thing, so what's left in stats() is only that.
--
-- Also drops the cached function-name map so it rebuilds on the next failure. That matters because the map
-- is a snapshot of whatever engine globals existed the first time something failed: if DEBUG was on early
-- in a level load, a namespace that populated later would be missing from it permanently, and its failures
-- would read as an unhelpful "closure" forever.
function Ess.Safe.reset()
    Ess.Safe._last = nil
    Ess.Safe._fails = 0
    Ess.Safe._tally = {}
    Ess.Safe._labels = nil
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

-- Both route through Ess.Safe.quiet rather than a bare pcall, like the rest of the framework -- these two
-- are defined below Ess.Safe in this same file, so there's no ordering problem, and `Ess.Guid("typo")`
-- silently returning nil is one of the most common beginner dead ends there is. With Ess.DEBUG on it says so.
function Ess.Guid(name)
    local ok, g = Ess.Safe.quiet(Pg.GetGuidByName, name)
    if ok then return g end
    return nil
end

function Ess.Name(uGuid)
    local ok, s = Ess.Safe.quiet(Sys.GuidToString, uGuid)
    if ok then return s end
    return nil
end

-- Ess.Unname(sHash) -> uGuid | nil -- the INVERSE of Ess.Name. Sys.StringToGuid turns the "0x4000563D"
-- form back into a real guid, and the round trip is exact (live-verified: a character guid -> string ->
-- guid compares == to the original).
--
-- Why it matters: a guid is userdata, so it cannot be stored by Loader.SaveVar / Ess.Save (numbers,
-- strings and booleans only) and cannot be sent over the bridge or a Net message. Ess.Name/Ess.Unname is
-- the pair that gets one through any string-only channel intact.
--
-- ⚠ WITHIN ONE SESSION ONLY. Guids are runtime handles, not stable identifiers -- a string persisted to
-- disk and read back after a reload will resolve to whatever now occupies that handle, or to nothing.
-- For anything that must survive a reload, persist the object's NAME and go back through Ess.Guid.
function Ess.Unname(sHash)
    if not sHash then return nil end
    local ok, g = Ess.Safe.quiet(Sys.StringToGuid, sHash)
    if ok then return g end
    return nil
end
