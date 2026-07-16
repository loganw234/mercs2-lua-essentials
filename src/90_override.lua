-- Ess/90_override.lua -- Ess.Override: the two confirmed-safe ways to change a piece of the game's own
-- logic without triggering the engine's real, confirmed tail-call crash.
--
-- API:
--   Ess.Override.wrap(target, name, newFn) -> ok
--   Ess.Override.mergeIntoLiveTable(t, key, data) -> ok

local Ess = _G.Ess
Ess.Override = Ess.Override or {}

-- Ess.Override.wrap(target, name, newFn) -> ok
-- Replaces target[name] (a function) with a new one, WITHOUT ever letting the caller write the exact
-- shape that's confirmed to crash this engine: `return fOriginal(...)`.
--
-- CONFIRMED REAL CRASH (custom-contract.md, cost a real crash on an already-shipped mission before it was
-- understood): `SomeModule.SomeFunction = function(...) return fOriginal(...) end` compiles as a Lua TAIL
-- CALL -- the current stack frame is replaced rather than a new one pushed. This engine's own module
-- system uses `getfenv(n)` in places (walking n stack levels to find a module's environment), and a
-- collapsed frame throws that level-counting off, surfacing as `:1: no function environment for tail call
-- at level 2` thrown from deep inside the ENGINE'S OWN code, not the mod that caused it. The confirmed
-- fix, applied consistently: capture the original in a local, call it as a plain statement, return its
-- result on a separate line -- never `return fOriginal(...)` directly.
--
-- Rather than trust every caller to remember that rule by hand, `newFn` here never touches the real
-- original function at all -- it's called as `newFn(callOriginal, ...)`, where `callOriginal` is a small
-- closure THIS function builds once, and that closure is the only thing allowed to invoke the real
-- original, always via the confirmed-safe two-statement shape. Writing the crashing pattern becomes
-- structurally unavailable rather than just discouraged in a comment.
--
-- Guards against silently double-wrapping the same target.name a second time (which would just stack an
-- invisible extra layer) -- a second `wrap` call on an already-wrapped key logs and refuses.
function Ess.Override.wrap(target, name, newFn)
    if type(target) ~= "table" then
        Ess.Log("Override.wrap: target is not a table")
        return false
    end
    local orig = target[name]
    if type(orig) ~= "function" then
        Ess.Log("Override.wrap: target." .. tostring(name) .. " is not a function")
        return false
    end
    target._essWrapped = target._essWrapped or {}
    if target._essWrapped[name] then
        Ess.Log("Override.wrap: target." .. tostring(name) .. " is already Ess-wrapped, refusing to double-wrap")
        return false
    end

    -- The ONLY thing allowed to call the real original. Never `return orig(...)` -- capture into locals,
    -- return them as a separate statement, exactly the confirmed-safe shape.
    local function callOriginal(...)
        local a, b, c, d = orig(...)
        return a, b, c, d
    end

    -- The outer replacement itself also avoids a tail call into newFn, for the same reason -- belt and
    -- suspenders, since newFn is arbitrary caller code that may eventually reach back into engine
    -- environment-sensitive calls via callOriginal, and keeping every frame in this chain a real
    -- (non-collapsed) frame removes any doubt about getfenv(n)'s level-counting landing wrong.
    target[name] = function(...)
        local a, b, c, d = newFn(callOriginal, ...)
        return a, b, c, d
    end
    target._essWrapped[name] = true
    return true
end

-- Ess.Override.mergeIntoLiveTable(t, key, data) -> ok
-- Appends each entry in `data` (a list) onto the existing table at t[key], creating it fresh only if it
-- doesn't already exist -- NEVER replacing t[key] with a new table object if one is already there.
--
-- CONFIRMED PATTERN (function-override.md's wardrobe-unlock case): prefer merging new data into a table
-- the game's own logic already reads from over replacing the function that reads it. The wardrobe menu's
-- costume-select code re-reads `WifPmcInterior._tOutfits[sHero]` FRESH by index every single time it
-- runs, never a cached copy -- so appending new rows into that same live table object makes them appear
-- in the existing, unmodified menu-building/costume-change code with zero risk of losing whatever
-- responsibilities (co-op branching, tutorial-dialog special cases, pagination, network sync) a full
-- function replacement would silently drop. "Tables are references, not copies" is what makes this work:
-- every reader holding onto t[key] sees the same object, appended-to in place, immediately.
function Ess.Override.mergeIntoLiveTable(t, key, data)
    if type(t) ~= "table" then
        Ess.Log("Override.mergeIntoLiveTable: t is not a table")
        return false
    end
    if type(t[key]) ~= "table" then
        t[key] = {}
    end
    local live = t[key]
    for _, v in ipairs(data or {}) do
        live[#live + 1] = v
    end
    return true
end
