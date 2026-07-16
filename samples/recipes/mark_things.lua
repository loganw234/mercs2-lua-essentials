-- RECIPE: put markers on the world -- an objective marker on a unit and a "go here" ground ring -- then
-- clean them up. Namespaces: Ess.Easy.Mark, Ess.Mark, Ess.Player.
--
-- Every Ess.Mark call returns ONE handle covering all the surfaces it drew (radar blip + PDA blip + floating
-- world icon + ground ring). Hold the handle, and Ess.Mark.clear tears down everything it drew -- including
-- the invisible anchor prop a zone spawns for itself. No per-surface bookkeeping.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- mark the player's own character as an objective (radar + PDA + floating icon).
local mObj = Ess.Easy.Mark.objective(Ess.Player.character(0))

-- drop a "go here" ground ring 10 units away (Ess.Easy.Mark.zone spawns its own anchor, no guid needed).
local px, py, pz = Ess.Player.pose(0)
local mZone = px and Ess.Easy.Mark.zone(px + 10, py, pz + 10, 8) or nil

local ok = (mObj ~= nil) and (mZone ~= nil)
Ess.Log("[recipe] mark_things: objective marker + a zone ring placed")

-- clean both up after a few seconds (one call each tears down every surface it drew).
Ess.Easy.Triggers.after(5, function()
    Ess.Mark.clear(mObj)
    Ess.Mark.clear(mZone)
    Ess.Log("[recipe] mark_things: markers cleared")
end)

Ess.Log("[SMOKE] mark_things: " .. (ok and "PASS" or "FAIL"))
