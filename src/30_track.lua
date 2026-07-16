-- Ess/30_track.lua -- Ess.Track: the generic answer to every leak-prone Add.../Remove... pair on this
-- engine. Ess.Event: Event.Create wrapped with Track integration.
--
-- API:
--   Ess.Track.new() -> tracker
--     tracker:add(closeFn) / :event(handle) / :guid(uGuid) / :marker(handle) / :radar(sName) / :pda(sName)
--     tracker:closeAll()
--   Ess.Event.on(eventType, args, cb, tracker) -> handle
--   Ess.Event.off(handle)

local Ess = _G.Ess

-- ============================================================
-- Ess.Track -- the single most leak-prone shape on this engine, repeated everywhere: an Add-something
-- call returns a handle that only its matching Remove call accepts, and there is no "clear everything I
-- made" native function for ANY of them (Event.Create/Delete, Marker.Add*/Remove, Hud.Radar:AddObjective/
-- RemoveObjective, Pda.Map:AddBlip/RemoveBlip, Object.AddQualityRef/RemoveQualityRef, Object.
-- AddToDisposer/RemoveFromDisposer, Pg.AddContextAction/RemoveContextAction). ContractFramework's own
-- `task = {events={}, guids={}, markers={}, marks={}}` + cleanupTask is exactly this pattern, hand-rolled
-- once per framework instead of shared -- Ess.Track is that shared implementation.
-- ============================================================
Ess.Track = {}
Ess.Track.__index = Ess.Track

function Ess.Track.new()
    return setmetatable({ _items = {} }, Ess.Track)
end

-- :add(closeFn) -> closeFn -- generic escape hatch: register any zero-arg teardown function.
function Ess.Track:add(closeFn)
    if type(closeFn) == "function" then self._items[#self._items + 1] = closeFn end
    return closeFn
end

-- :event(handle) -> handle -- tracks an Event.Create handle for Event.Delete on teardown.
function Ess.Track:event(handle)
    if handle then self:add(function() pcall(Event.Delete, handle) end) end
    return handle
end

-- :guid(uGuid) -> uGuid -- tracks a spawned object for Object.Remove on teardown.
function Ess.Track:guid(uGuid)
    if uGuid then self:add(function() pcall(Object.Remove, uGuid) end) end
    return uGuid
end

-- :marker(handle) -> handle -- tracks a Marker.Add*() handle for Marker.Remove on teardown.
function Ess.Track:marker(handle)
    if handle then self:add(function() pcall(Marker.Remove, handle) end) end
    return handle
end

-- :radar(sName) -> sName -- tracks a Hud.Radar:AddObjective({sName=...}) registration for
-- RemoveObjective on teardown.
function Ess.Track:radar(sName)
    if sName then self:add(function() pcall(function() Hud.Radar:RemoveObjective({ sName = sName }) end) end) end
    return sName
end

-- :pda(sName) -> sName -- tracks a Pda.Map:AddBlip({sName=...}) registration for RemoveBlip on teardown.
function Ess.Track:pda(sName)
    if sName then self:add(function() pcall(function() Pda.Map:RemoveBlip({ sName = sName }) end) end) end
    return sName
end

-- :closeAll() -- runs every registered teardown in reverse-registration order, then clears the tracker.
-- Safe to call more than once (a re-:closeAll() on an already-empty tracker is just a no-op) and safe to
-- keep using the tracker afterward (a fresh :add() after :closeAll() starts a new batch).
function Ess.Track:closeAll()
    for i = #self._items, 1, -1 do
        pcall(self._items[i])
    end
    self._items = {}
end

-- ============================================================
-- Ess.Event -- thin wrapper so Event.Create failures log instead of silently returning a broken handle,
-- and so registering with a tracker is one extra argument instead of a separate line.
-- ============================================================
Ess.Event = Ess.Event or {}

-- Ess.Event.on(eventType, args, cb, tracker) -> handle | nil
-- `args` shape must match what `eventType` expects -- getting the shape wrong doesn't error, it just
-- silently never fires, so double-check against wiki/namespaces/event.md if a handler seems dead.
function Ess.Event.on(eventType, args, cb, tracker)
    local ok, handle = pcall(Event.Create, eventType, args, cb)
    if not ok then
        Ess.Log("Event.on failed: " .. tostring(handle))
        return nil
    end
    if tracker then tracker:event(handle) end
    return handle
end

function Ess.Event.off(handle)
    local ok = pcall(Event.Delete, handle)
    return ok and true or false
end
