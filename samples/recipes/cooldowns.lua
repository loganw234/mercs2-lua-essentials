-- RECIPE: rate-limit an action, and get a per-frame delta -- the two timing shapes.
-- Namespaces: Ess.Time.
--
-- Two different jobs, two different tools, both surviving a world-pause (they read the real clock):
--   * Ess.Time.cooldown(sec) -> ready()   -- "am I allowed to do this again yet?" ready() is true at most
--                                             once per window (and the FIRST call is always free).
--   * Ess.Time.clock() -> clock:delta()   -- an auto-advancing per-frame dt for a heartbeat (clamped so a
--                                             pause/hitch can't blow up your per-tick math).

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- gate an ability behind a half-second cooldown
local canDash = Ess.Time.cooldown(0.5)
local first = canDash()        -- true  -- first use is free
local again = canDash()        -- false -- still inside the 0.5s window (and it does NOT push the window back)

-- a per-frame delta clock -- the shape a Loop tick wants for its dt
local clock = Ess.Time.clock()
local dt = clock:delta()       -- ~0 on the first read; "seconds since last delta()" after that

-- turn raw seconds into a HUD string (engine call -- returns nil if run off-engine)
local hud = Ess.Time.format(90)

Ess.Log(string.format("[recipe] cooldowns: first=%s again=%s dt=%.3f hud=%s",
    tostring(first), tostring(again), dt, tostring(hud)))
-- real usage: `if canDash() then Ess.Easy.Impulse.speedBoost() end` in a Loop tick fires at most 2x/second.
local ok = (first == true) and (again == false) and (type(dt) == "number")
Ess.Log("[SMOKE] cooldowns: " .. (ok and "PASS" or "FAIL"))
