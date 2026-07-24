local KEYVAL = "f9"   -- must be in the first 10 lines (add "CinematicDemo.lua=f9" under [OnKey])

-- CinematicDemo.lua -- a showcase cutscene built on Ess.Cinematic, doubling as living documentation of the
-- step vocabulary. Press F9 and a short "reinforcements arrive" scene plays around wherever you're standing:
-- an establishing shot, a helicopter flies in under a tracking camera, a ground vehicle is revealed with an
-- orbit, narration throughout, and control hands back. Press ESC any time to skip (every step still fires,
-- so nothing is left half-staged).
--
-- The point of the sample: a whole cutscene is just an ordered list of {type=, params, hold=} tables. Steps
-- with hold=0 fire together (so a camera move + a subtitle start at once); a hold>0 paces the timeline. A
-- `spawn` step's name= registers the actor so later camera/fly steps refer to it by that label. Ess.Cinematic
-- always restores the camera + clears any fade on finish/skip/error -- a cutscene can never strand you.
--
-- DEPLOY: Ess (dist/Ess.lua) as an OnLoad script; then this under scripts/OnKey/ with CinematicDemo.lua=f9.
----------------------------------------------------------------------------

local Ess = _G.Ess
if not (Ess and Ess.Cinematic and Ess.Player) then
  if Loader and Loader.Printf then
    Loader.Printf("[cinedemo] load the Essentials framework (dist/Ess.lua) as an OnLoad script first")
  end
  return
end

-- Don't stack a second cutscene on top of a running one (F9 pressed twice) -- let the first finish.
if Ess.Cinematic.isPlaying() then
  Ess.Log("[cinedemo] a cutscene is already playing")
  return
end

-- Build the scene relative to where the player is RIGHT NOW (so the demo works anywhere). A real mission
-- would use absolute coords captured in MissionForge; this reads the live pose at keypress instead.
local px, py, pz = Ess.Player.pose(0)
if not px then
  Ess.Log("[cinedemo] no player position")
  return
end

local steps = {
  -- open on black, cut to an establishing vantage looking down at the player, then fade in (hold=0 steps
  -- all fire on the same tick, so the cut happens WHILE the screen is still black -- no jarring jump).
  { type = "fade",   to = 1, hold = 0 },
  { type = "camera", at = { px + 18, py + 11, pz + 18 }, lookAt = { px, py + 1, pz }, hold = 0 },
  { type = "subtitle", text = "Command: hold position -- support inbound.", hold = 0 },
  { type = "fade",   to = 0, hold = 3 },

  -- a helicopter spawns high and offset; name it so the camera + fly steps below can refer to it.
  { type = "spawn",  template = "AH1Z (Full)", at = { px - 30, py + 40, pz - 15 }, name = "heli", hold = 1.5 },
  -- chase camera locked on the heli from a fixed angle while it flies in (a fixed angle = a clean, jitter-
  -- free trailing shot). fly + chase both start now (hold=0 on fly) so the camera tracks the whole approach.
  { type = "fly",    target = "heli", at = { px + 4, py + 8, pz + 4 }, height = 7, hold = 0 },
  { type = "chase",  target = "heli", angle = 40, dist = 18, height = 8, hold = 5 },
  { type = "subtitle", text = "Air support on station.", hold = 0 },

  -- reveal a ground vehicle beside the player with a slow orbit -- the classic "here's your new toy" shot.
  { type = "spawn",  template = "HMMWV (Softtop) (Full)", at = { px + 6, py, pz + 6 }, name = "apc", yaw = 0, hold = 0.5 },
  { type = "face",   who = "apc", at = { px, py, pz }, hold = 0 },
  { type = "orbit",  target = "apc", radius = 9, height = 4, speed = 45, hold = 4 },

  -- wrap: a centered banner, a beat, then Ess.Cinematic hands control back automatically.
  { type = "banner", text = "-- Reinforced --", hold = 2 },
}

Ess.Cinematic.play(steps, {
  onDone = function() Ess.Log("[cinedemo] scene complete -- control restored") end,
})
Ess.Log("[cinedemo] playing (" .. #steps .. " steps; ESC to skip)")
