-- StarterMod.lua -- a COPY-ME template for your first real mod. Bind it to a key in lua_loader.ini:
--     [OnKey]
--     StarterMod.lua=F5
-- ...then press F5 in-game. This one toggles god mode on and off; gut the ACTION block and drop your own
-- in. The three things every OnKey mod needs are all labelled below. Full tour: GETTING_STARTED.md.

-- (1) GUARD -- bail cleanly if Ess isn't loaded (wrong load order, or not installed). Do this first, always.
if not _G.Ess then Loader.Printf("StarterMod: load Ess first (1_Ess.lua in scripts/OnLoad)") return end

-- (2) STATE -- an OnKey script re-runs top-to-bottom on EVERY keypress, so a plain `local` resets each time.
-- Ess.State gives you a table that survives across those re-runs (and merges in new defaults you add later,
-- so shipping an update that adds a field just works). This is what makes a "toggle" possible at all.
local S = Ess.State("StarterMod", { on = false })

-- (3) ACTION + FEEDBACK -- flip the toggle, apply it, tell the player. Replace this whole block with your mod.
S.on = not S.on
local me = Ess.Player.character(0)
if me then Ess.Object.setInvincible(me, S.on, "StarterMod") end

Ess.Easy.Toast("God mode: " .. (S.on and "ON" or "OFF"))
Ess.Log("[StarterMod] god mode -> " .. tostring(S.on))

-- IDEAS to swap in for the ACTION block (all one-liners -- browse samples/recipes/ for dozens more):
--   Ess.Easy.Vehicle.summon("UH1 Transport")      -- spawn a helicopter and drop into the pilot seat
--   Ess.Easy.Spawn.explosion()                     -- a boom in front of you
--   Ess.Easy.World.clearWanted()                   -- lose all heat
--   Ess.Easy.Player.giveGrapplingHook()            -- unlock a cheat-menu power
--   Ess.Easy.Console.open()                        -- browse the whole Ess.Easy.* menu in-game
