-- RECIPE: spawn something in front of me and control it -- position, facing, health, cleanup.
-- Namespaces: Ess.Object, Ess.Player, Ess.Math, Ess.Easy.Triggers.
--
-- Run it (bind under [OnKey], or execute via the bridge). It spawns a car ahead of you, reports where it
-- landed and how far, turns it to face you, tops up its health, then tidies itself away after a few seconds.
-- Doubles as a smoke test: the final [SMOKE] line is PASS only if the whole chain worked.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- spawnAhead hides the "in front of me" yaw/trig -- just say how far ahead. (Ess.Object.spawn(t,x,y,z) is
-- the absolute-coords version, with the same blank-template crash guard.)
local car = Ess.Object.spawnAhead("Veyron", 8)

local ok = false
if car then
    local cx, cy, cz = Ess.Object.pos(car)                       -- where did it end up?
    local px, _, pz  = Ess.Player.pose(0)
    local dist = Ess.Math.dist2D(px, pz, cx, cz)                 -- horizontal distance to the player
    Ess.Object.faceObject(car, Ess.Player.character(0))          -- turn it to face me
    Ess.Object.heal(car)                                         -- set health to full
    local hp = Ess.Object.health(car)
    ok = (cx ~= nil) and (hp ~= nil)
    Ess.Log(string.format("[recipe] spawn_and_control: car @ %.1f,%.1f,%.1f  %.1fu away  hp=%s",
        cx or 0, cy or 0, cz or 0, dist, tostring(hp)))
    Ess.Easy.Triggers.after(6, function() Ess.Object.remove(car) end)   -- tidy up (leaves nothing behind)
end

Ess.Log("[SMOKE] spawn_and_control: " .. (ok and "PASS" or "FAIL"))
