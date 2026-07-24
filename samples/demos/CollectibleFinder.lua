local KEYVAL = "free"   -- toggle key -- F1-F12 are the suggested keys for this folder's other demos, so
                        -- bind this to whatever's free for you

-- CollectibleFinder.lua -- an Ess reimplementation of a community proximity-marker script. Marks "SpareParts"
-- collectible boxes on radar / PDA / world as you approach, and CLEARS each marker the instant you collect
-- that box. Press the key again to turn it off (and wipe every marker cleanly).
--
-- WHAT THE ESS VERSION FIXES vs the hand-rolled original:
--   * marking is one call -- Ess.Mark.object (radar/pda/world in one), no native Hud.Radar/Pda/Marker fallback
--   * markers auto-clear on collect -- Ess.On.death(box) instead of never removing them
--   * leak-proof teardown -- every marker + the proximity event are tracked and released on toggle-off
--   * Ess.Player / Ess.Object / Ess.Log instead of raw getters + Debug.Printf
--
-- WHY the raw ObjectFilter + Event.ObjectProximity (the one part still "native"): that is the CONFIRMED way
-- to catch objects by their WORLD label as they stream in (the game's own wiftutorialcollectibles.lua does
-- this). ObjectFilter.GetObjects only returns objects explicitly AddObject'd to a filter, NOT world-label
-- matches -- so a proximity event on a label filter is how you discover them. After marking one we
-- AddObject(filter, guid, true) to EXCLUDE it, so the event won't re-fire for the same box. (A future
-- Ess.On.labeled(label, radius, fn) could wrap this whole dance -- noted for the framework.)
--
-- DEPLOY: Ess (dist/Ess.lua) OnLoad; this at scripts/OnKey/CollectibleFinder.lua bound to a free key. To run
-- it ALWAYS-ON instead, drop the toggle block and just call arm() from an OnLoad script.

local Ess = _G.Ess
if not (Ess and Ess.Mark and Ess.On) then
  if Loader and Loader.Printf then Loader.Printf("[collectibles] load the Essentials framework (1_Ess.lua) first") end
  return
end

local LABEL = "SpareParts"          -- the world label the collectible boxes carry
local RADIUS = 500                  -- detect this far out (streaming is the real cap)
local RGB = { 180, 51, 36 }         -- marker colour

local S = _G.CollectibleFinder or { on = false }
_G.CollectibleFinder = S

local function markOne(guid)
  if not Ess.Object.alive(guid) then return end
  if Ess.Object.hasLabel(guid, "CollectableInvalidated") then return end   -- already collected/spent
  S.found = S.found + 1
  local h = Ess.Mark.object(guid, { radar = true, pda = true, world = true, rgb = RGB })
  if h then
    S.marks[#S.marks + 1] = h
    S.stops[#S.stops + 1] = Ess.On.death(guid, function() Ess.Mark.clear(h) end)   -- clear it when collected
  end
  Ess.Log("collectible #" .. S.found .. " marked (" .. (Ess.Name(guid) or "?") .. ")")
end

local function onProximity(tGuids)
  if type(tGuids) ~= "table" then tGuids = { tGuids } end
  for _, guid in ipairs(tGuids) do
    pcall(ObjectFilter.AddObject, S.filter, guid, true)   -- exclude so this box won't re-fire the event
    markOne(guid)
  end
end

local function arm()
  local char = Ess.Player.character(0)
  if not char then Ess.Log("finder: player not ready"); return false end
  S.filter = ObjectFilter.Create()
  ObjectFilter.SetFilter(S.filter, LABEL)
  -- fires with a table of guids whenever a matching object enters RADIUS of the player; persistent = keeps firing
  S.event = Event.CreatePersistent(Event.ObjectProximity, { S.filter, char, "<", RADIUS, false, false }, onProximity, {})
  Ess.Log("collectible finder ARMED (label=" .. LABEL .. ", radius=" .. RADIUS .. ")")
  return true
end

local function disarm()
  if S.event then pcall(Event.Delete, S.event); S.event = nil end
  for _, stop in ipairs(S.stops or {}) do pcall(stop) end           -- unhook the death watchers
  for _, h in ipairs(S.marks or {}) do Ess.Mark.clear(h) end        -- wipe every marker
  S.marks, S.stops = {}, {}
end

-- toggle
if S.on then
  disarm()
  S.on = false
  Ess.UI.Toast("Collectible finder OFF (" .. (S.found or 0) .. " found)")
else
  S.marks, S.stops, S.found = {}, {}, 0
  if arm() then S.on = true; Ess.UI.Toast("Collectible finder ON -- boxes light up as you near them") end
end
