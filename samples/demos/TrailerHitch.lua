local KEYVAL = "free"   -- toggle key -- F1-F12 are the suggested keys for this folder's other demos, so
                        -- bind this to whatever's free for you

-- TrailerHitch.lua -- spawn a truck + a fuel trailer ahead of you and rigidly HITCH the trailer to the
-- truck's hitch hardpoint. Demonstrates the engine's "weld object B onto a hardpoint on object A" primitive:
--
--     Object.Attach(uParent, sHardpoint, uChild)          -- returns bOk, uInst
--     Object.SetTransformToObject(uChild, uParent, sHardpoint)   -- seat it exactly, right after
--     Object.Detach(uParent, uChild)                       -- release
--
-- CONFIRMED LIVE: the trailer seats on the hitch and FOLLOWS the truck through movement (tracked it to
-- ~0.08m after the truck was flung ~200 units) while keeping its own physics. Press the key again to remove
-- both vehicles.
--
-- TWO THINGS TO KNOW (both inherent to Object.Attach):
--   1. It's a RIGID weld -- no articulation/pivot. The trailer can't swing behind the truck like a real hitch;
--      the engine exposes no joint / tow-constraint API to Lua. (A per-frame follow-with-lag script could fake
--      a pivot, but the trailer's own physics would partly fight it.)
--   2. It seats by the CHILD'S ORIGIN on the hardpoint -- not by a chosen hardpoint on the child. If the
--      trailer's coupling isn't at its origin the height/position sits slightly off. The clean offset fix is
--      the 6-arg Object.SetTransformToObject form (an offset variant seen in the DLC scripts, not yet decoded)
--      or attaching to an invisible anchor placed at hitch+offset.
--
-- DEPLOY: Ess (dist/Ess.lua) OnLoad; this at scripts/OnKey/TrailerHitch.lua bound to a free key. Do it in the
-- open world -- spawning a vehicle into geometry blows it up (that's why we spawn AHEAD + a little up).

local Ess = _G.Ess
if not (Ess and Ess.Object) then
  if Loader and Loader.Printf then Loader.Printf("[hitch] load the Essentials framework (1_Ess.lua) first") end
  return
end

local TRUCK, TRUCK_HITCH = "Austin (CIV)", "hp_trailerhitch"
local TRAILER = "Civ Fueltrailer"

local S = _G.TrailerHitch or {}
_G.TrailerHitch = S

-- toggle off: clean the previous pair up
if S.truck then
  if S.trailer then Ess.Object.remove(S.trailer) end
  Ess.Object.remove(S.truck)
  S.truck, S.trailer = nil, nil
  Ess.UI.Toast("Hitch demo cleared")
  return
end

-- spawn ahead + elevated + invincible so a graze on the way down can't blow them up
local truck = Ess.Object.spawnAhead(TRUCK, 12, 4)
local trailer = Ess.Object.spawnAhead(TRAILER, 24, 4)
if not (truck and trailer) then Ess.Log("hitch: spawn failed (check template names)"); return end
Ess.Object.setInvincible(truck, true, "hitch")
Ess.Object.setInvincible(trailer, true, "hitch")
S.truck, S.trailer = truck, trailer

-- the hitch: weld the trailer onto the truck's hitch hardpoint, then seat it exactly there
local ok = Object.Attach(truck, TRUCK_HITCH, trailer)
Object.SetTransformToObject(trailer, truck, TRUCK_HITCH)

Ess.Log("hitch: Object.Attach(" .. TRUCK .. ", " .. TRUCK_HITCH .. ", " .. TRAILER .. ") -> " .. tostring(ok))
Ess.UI.Toast(ok and "Trailer hitched -- get in the truck and drive, it follows" or "Attach failed -- check the hitch hardpoint name")
