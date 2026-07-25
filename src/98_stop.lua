-- Ess/98_stop.lua -- Ess.stop: one teardown verb that works on anything Ess handed you.
--
-- THE PROBLEM. Ess grew 27 distinct teardown verbs across its namespaces, over FIVE structurally different
-- disposal idioms. Each is defensible on its own -- `dismiss` genuinely reads better than `remove` for a
-- follower -- but together they mean "how do I turn this off" has no learnable answer. You look it up, every
-- time, per namespace:
--
--   closure returned      Ess.On.death(g, fn)          -> stop()
--   opaque handle table   Ess.Mark.object(g, {...})     -> Ess.Mark.clear(h)
--   caller-supplied id    Ess.Loop.start("id", ...)     -> Ess.Loop.stop("id")
--   object with a method  Ess.Objective.new{...}        -> :cancel()
--   tracker registry      Ess.Track.new()               -> :closeAll()
--
-- Ess.stop(x) accepts all five and does the right thing. NOTHING is deprecated by this -- every existing
-- verb still works and is still the most precise way to say what you mean. This is the one you reach for when
-- you're holding a handle and just want it gone, and the one a teaching example can use without a detour
-- into which namespace spells teardown which way.
--
-- API:
--   Ess.stop(x) -> bool                 tear down a closure / handle table / id string / object. true if it did.
--   Ess.stopAll(t) -> nCount            Ess.stop every element of an array, reverse order. Returns how many worked.
--   Ess.Track:any(x) -> x               register ANY of the five with a tracker, torn down by :closeAll()
--
-- WHY DUCK-TYPING RATHER THAN TAGGING EVERY HANDLE. Stamping a type field onto each handle at creation would
-- be less guessy, but it would change the shape of handles that already ship and that user code already
-- holds -- and Ess.Mark.clear/Ess.Relations.restore identify their own handles by field shape ALREADY, so the
-- discriminators below aren't new inference, they're the same ones those functions use. Method checks run
-- before field checks so an object that happens to carry a matching field can't be misrouted.

local Ess = _G.Ess

-- Ess.stop(x) -> bool
-- Returns true if something was actually torn down, false if x was nil/unrecognised. Never throws: every
-- teardown runs guarded, because "clean this up" is exactly the call you don't want failing at level unload.
function Ess.stop(x)
    if x == nil then return false end

    -- 1. A closure. Ess.On.*, Ess.Triggers.arm, Ess.Camera.followHardpoint and Ess.Easy.Camera.orbit all
    --    return their own stop() -- by far the most common shape.
    if type(x) == "function" then
        return Ess.Safe.named("Ess.stop(closure)", x) and true or false
    end

    -- 2. A caller-supplied string id. Ess.Loop and Ess.Sandbox are both keyed this way, so the id alone is
    --    ambiguous -- resolved by ASKING each registry whether it owns that id, rather than guessing from
    --    the string. Loop first: it's far more common, and the two namespaces' ids don't collide in practice.
    if type(x) == "string" then
        if Ess.Loop and Ess.Loop.isRunning and Ess.Loop.isRunning(x) then
            Ess.Loop.stop(x)
            return true
        end
        if Ess.Sandbox and Ess.Sandbox.isActive and Ess.Sandbox.isActive(x) then
            Ess.Sandbox.finish(x)
            return true
        end
        Ess.Safe.reject("Ess.stop", "no running loop or active sandbox with the id '" .. x .. "'")
        return false
    end

    if type(x) ~= "table" then
        Ess.Safe.reject("Ess.stop", "cannot tear down a " .. type(x))
        return false
    end

    -- 3. An object that knows how to close itself. Checked before any field shape below, so a real method
    --    always wins. :closeAll is Ess.Track, :cancel is Ess.Objective/Ess.Quest, :stop is the general case.
    for _, method in ipairs({ "closeAll", "cancel", "stop" }) do
        if type(x[method]) == "function" then
            return Ess.Safe.named("Ess.stop(:" .. method .. ")", function() x[method](x) end) and true or false
        end
    end

    -- 4. An Ess.Relations handle -- `snaps` is the field Ess.Relations.restore itself keys on.
    if x.snaps ~= nil and Ess.Relations and Ess.Relations.restore then
        Ess.Relations.restore(x)
        return true
    end

    -- 5. An Ess.Mark handle -- these are exactly the fields Ess.Mark.clear reads. `uGuid`/`anchor` are
    --    included because a mark with every surface disabled still carries one of them and nothing else.
    if Ess.Mark and Ess.Mark.clear and (x.radarName or x.pdaName or x.worldHandle or x.discHandle
            or x.uGuid ~= nil or x.anchor ~= nil) then
        Ess.Mark.clear(x)
        return true
    end

    Ess.Safe.reject("Ess.stop", "unrecognised handle -- no :closeAll/:cancel/:stop method, and not a "
        .. "Mark or Relations handle. Use the namespace's own teardown verb.")
    return false
end

-- Ess.stopAll(tHandles) -> nStopped
-- Reverse order, mirroring Ess.Track:closeAll -- things set up later usually depend on things set up earlier,
-- so tearing down backwards is the order that doesn't surprise.
--
-- ⚠ tHandles must be a DENSE array. This walks `#tHandles`, and `#` is UNDEFINED on a table with a nil hole
-- (CONTRIBUTING.md's engine rules; it can report 1 or 3 for the same three-slot table with the middle one
-- nil), so a holed list may be torn down only partway -- silently. If you built the list by nil-ing entries
-- out as you went, run Ess.Table.compact(t) first, which exists for exactly this. Individual nils ARE skipped
-- safely; it is the LENGTH that can't be trusted, which is not something this function can fix for you.
function Ess.stopAll(tHandles)
    if type(tHandles) ~= "table" then return 0 end
    local n = 0
    for i = #tHandles, 1, -1 do
        if Ess.stop(tHandles[i]) then n = n + 1 end
    end
    return n
end

-- Ess.Track:any(x) -> x
-- The bridge between the two: hand a tracker ANY of the five disposal shapes and :closeAll() will tear it
-- down with the rest. Ess.Track's typed registrars (:event/:guid/:marker/...) stay the better choice when you
-- know what you have -- they wrap the specific native Remove call directly, no dispatch involved. This is for
-- when you're collecting mixed things (a mark handle, a loop id, and an Ess.On stop() in one list).
-- Returns x unchanged so it chains: `local h = tracker:any(Ess.Easy.Mark.enemy(g))`.
if Ess.Track then
    function Ess.Track:any(x)
        if x ~= nil then self:add(function() Ess.stop(x) end) end
        return x
    end
end
