-- RECIPE: control the heat -- start, read, and clear a faction pursuit; go stealth-ghost and back.
-- Namespaces: Ess.Pursuit, Ess.Relations, Ess.Easy.Player.
--
-- The pursuit ("wanted") system is fully scriptable: start a chase at a chosen level, read the live
-- countdown, and -- the part the native names make confusing -- CLEAR it with the one call that actually
-- works (Ess.Pursuit.clear; the restrict* family only gates ORGANIC heat buildup and never stops an
-- active chase). Ghost mode floors your AI detectability and restores your exact original value.
--
-- Deliberately NOT demonstrated: Ess.Pursuit.capLevel -- it is a live-confirmed ONE-WAY ratchet for the
-- whole session (nothing raises the ceiling again until a save-load), so a smoke script must never call it.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local fail = false
local function check(label, ok)
    if not ok then fail = true; Ess.Log("[SMOKE] control_pursuit: FAIL (" .. label .. ")") end
end

-- 1. idle read -- the state table is the read channel for everything here
local t0 = Ess.Pursuit.state()
check("state() readable", t0 ~= nil)

-- 2. start a level-1 VZ pursuit... (this seeds a real countdown; nothing spawns to chase you by itself)
check("start", Ess.Pursuit.start("VZ", 1))
local t1 = Ess.Pursuit.state()
check("started", t1 and t1.Active and (t1.Level or 0) >= 1)

-- 3. ...and clear it again -- Ess.Pursuit.clear() is THE reset (ClearPursuitLock under the hood)
check("clear", Ess.Pursuit.clear())
local t2 = Ess.Pursuit.state()
check("cleared", t2 and (t2.Level or 0) == 0)

-- 4. ghost on -> perceivability drops to the engine's floor; ghost off -> your original value comes back
local char = Ess.Player.character(0)
local before = char and Ess.Relations.getPerceivability(char)
Ess.Easy.Player.ghost(true)
local during = char and Ess.Relations.getPerceivability(char)
Ess.Easy.Player.ghost(false)
local after = char and Ess.Relations.getPerceivability(char)
check("ghost lowered", before and during and during < before)
check("ghost restored", before and after and after == before)

if not fail then Ess.Log("[SMOKE] control_pursuit: PASS") end
