-- RECIPE: launch, boost, and knock things around with impulses -- the "speed boost" / "sent them flying" feel.
-- Namespaces: Ess.Easy.Impulse (+ Ess.Impulse / Ess.Raw.Impulse for finer control).
--
-- The one-liners (all MASS-SCALED, so the same call feels right on a bike or a tank -- an impulse is mass*Δv):
--   Ess.Easy.Impulse.speedBoost(vehicle) - a forward speed boost, the Spy Hunter effect (defaults to the car
--                                          you're driving, or you on foot)
--   Ess.Easy.Impulse.launch(guid)        - pop something straight UP
--   Ess.Easy.Impulse.knockback(guid, from) - shove it away from a source ("the blast sent them flying")
-- For full control: Ess.Impulse.push(guid, { forward=, up=, side=, dir={x,y,z}, strength=, scaleByMass= }).

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local px, py, pz = Ess.Player.pose(0)
if not px then Ess.Log("[SMOKE] speed_boost: FAIL (no player position)") return end

-- spawn a test car and LAUNCH it straight up, then confirm a beat later that it actually left the ground --
-- a real physics effect, not just "the call ran".
local car = Ess.Object.spawn("Veyron", px + 12, py, pz)
if not car then Ess.Log("[SMOKE] speed_boost: FAIL (spawn failed)") return end

local _, y0 = Ess.Object.pos(car)
Ess.Easy.Impulse.launch(car, 10)                          -- pop it up

Ess.Easy.Triggers.after(0.5, function()
    local _, y1 = Ess.Object.pos(car)
    local rose = y0 and y1 and (y1 > y0 + 0.3)            -- did it climb?
    Ess.Object.remove(car)
    Ess.Log(string.format("[recipe] speed_boost: launched a car; height %.2f -> %.2f", y0 or 0, y1 or 0))
    Ess.Log("[SMOKE] speed_boost: " .. (rose and "PASS" or "FAIL"))
end)

Ess.Log("[recipe] speed_boost: launched a test car (also try speedBoost / knockback on a vehicle you're in)")
