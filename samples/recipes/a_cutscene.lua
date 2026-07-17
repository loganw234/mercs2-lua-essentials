-- RECIPE: play a declarative CUTSCENE -- an ordered timeline of camera shots, spawns and narration.
-- Namespaces: Ess.Cinematic, Ess.Player.
--
-- A cutscene is a list of {type=, <params>, hold=} steps that fire in order, each holding `hold` seconds
-- before the next. The runtime is an ORCHESTRATOR over pieces you've already met (camera, spawn, AI orders,
-- HUD narration, fades, sound) -- so one flat list gives you camera cuts/dollies/orbits, actors, captions,
-- and it ALWAYS restores camera + control on finish/skip (a cutscene can never strand the player). Contracts
-- play one as an intro via def.cinematic; here we build a tiny one inline. ESC skips (every step still fires).

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local px, py, pz = Ess.Player.pose(0)
if not px then Ess.Log("[SMOKE] a_cutscene: FAIL (no player position)") return end

-- steps refer to spawned actors by the name= you give them (ctx.named); ephemeral=true actors are removed
-- automatically when the cutscene ends. Kept short so it wraps up quickly.
local steps = {
    { type = "spawn",    template = "Veyron", at = { px + 14, py, pz }, name = "hero_car", ephemeral = true },
    { type = "camera",   at = { px + 22, py + 4, pz + 6 }, look = "hero_car", hold = 1.2 },   -- fixed vantage, auto-tracks
    { type = "subtitle", text = "Recipe: a two-shot cutscene.", hold = 0 },                    -- caption (fires same tick)
    { type = "orbit",    target = "hero_car", radius = 9, height = 4, speed = 60, hold = 1.2 }, -- then swing around it
}

local seq = Ess.Cinematic.play(steps, {
    skippable = true,
    onDone = function()
        -- fires after the last step AND after control is fully restored -- the meaningful "it worked" signal.
        Ess.Log("[recipe] a_cutscene: finished, camera/control restored, ephemeral actor cleaned up")
        Ess.Log("[SMOKE] a_cutscene: PASS")
    end,
})

if not seq then Ess.Log("[SMOKE] a_cutscene: FAIL (cutscene did not start)")
else Ess.Log("[recipe] a_cutscene: playing " .. #steps .. " steps (ESC to skip)") end
