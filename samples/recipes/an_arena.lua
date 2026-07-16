-- RECIPE: run an ephemeral "arena" mode SAFELY -- an isolated minigame that can't corrupt the save.
-- Namespaces: Ess.Sandbox (+ Ess.Layers / Ess.Save under the hood).
--
-- Ess.Easy.Sandbox.arena turns on the isolation providers (a scratch layer state, an isolated economy,
-- support/relations sandboxing) AND gates Pg.SaveGame so nothing serializes while it's active -- so a
-- wave-arena or minigame you spin up leaves the real campaign save untouched. done() restores everything.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local id = "recipe_arena"

Ess.Easy.Sandbox.arena(id)                    -- begin: isolation on, saving gated
local during = Ess.Sandbox.isActive(id)

-- ... your minigame would run here; saves are suppressed and state is scratch ...

Ess.Easy.Sandbox.done(id)                     -- end: restores layers/economy/relations, re-enables saving
local after = Ess.Sandbox.isActive(id)

local ok = (during == true) and (after == false)
Ess.Log("[recipe] an_arena: sandbox active during=" .. tostring(during) .. ", after done=" .. tostring(after))
Ess.Log("[SMOKE] an_arena: " .. (ok and "PASS" or "FAIL"))
