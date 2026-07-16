-- Ess/94_easy_world.lua -- Ess.Easy.World: one-line "make the world do X" verbs for beginners. Each hides
-- the import + the namespace a newcomer would otherwise have to hunt down -- the whole point of the Easy
-- tier is that the thought "I want to remove the map boundary" becomes exactly one call you can guess.
--
-- API:
--   Ess.Easy.World.removeMapBoundary()   drop the invisible walls fencing the player into the unlocked map

import("WifVzBoundary")

local Ess = _G.Ess
Ess.Easy = Ess.Easy or {}
Ess.Easy.World = Ess.Easy.World or {}

-- Ess.Easy.World.removeMapBoundary() -- removes the single "world boundary" that fences the player into the
-- story-unlocked portion of the map (the invisible wall + the Fiona-voiced warning + static). CONFIRMED
-- (WifVzBoundary.RemoveWorldBoundary, real call site in the decompiled corpus). This is DISTINCT from
-- Ess.Player.removeBoundaries, which clears the local player's own per-player boundary volumes -- this drops
-- the whole VZ world-boundary system so you can roam the entire physical map. There's no clean restore (the
-- boundary is re-established per-mission via WifVzBoundary.SetupBoundary*), so treat it as a one-way
-- "let me roam" toggle for the session.
function Ess.Easy.World.removeMapBoundary()
    pcall(WifVzBoundary.RemoveWorldBoundary)
end
