local KEYVAL = "f11"   -- toggle key; also add "WaveSurvival.lua=f11" under [OnKey] in lua_loader.ini

-- WaveSurvival.lua -- press F11 to start an escalating HORDE. Waves of enemies spawn and rush you, each
-- bigger than the last. Clear a wave and you get a breather (heal to full) plus, every third wave, a supply
-- crate. A HUD panel tracks the wave, live enemy count, and kills. Press G for a "danger close" airstrike on
-- your own head (on a cooldown -- brave or desperate). Press F11 again to end the horde and clean it all up.
--
-- Showcases how the pieces compose into a real mode: Ess.Easy.Spawn.enemies (spawn + auto-attack you) +
-- Ess.On.death (reliable per-guid kill tracking -- no area polling) + Ess.Support/Airstrike + Ess.UI.Panel +
-- Ess.Hud.banner + Ess.Time.cooldown + Ess.Keys + Ess.Loop-free scheduling via Ess.Easy.Triggers.after.
--
-- DEPLOY: Ess (dist/Ess.lua) OnLoad; this at scripts/OnKey/WaveSurvival.lua , [OnKey] WaveSurvival.lua=f11.

local Ess = _G.Ess
if not (Ess and Ess.Easy and Ess.Easy.Spawn) then
    if Loader and Loader.Printf then Loader.Printf("[wavesurvival] load the Essentials framework (1_Ess.lua) first") end
    return
end

_G.WaveSurvival = _G.WaveSurvival or {}
local W = _G.WaveSurvival

local BREATHER = 4        -- seconds between waves
local STRIKE_KEY = "g"    -- danger-close airstrike hotkey while the horde runs
local STRIKE_CD = 12      -- ... on this cooldown (seconds)

local startWave, waveCleared   -- mutually recursive -> forward-declare

local function updatePanel()
    if not W.panel then return end
    W.panel:line(0, "wave    : " .. tostring(W.wave))
    W.panel:line(1, "enemies : " .. tostring(W.alive))
    W.panel:line(2, "kills   : " .. tostring(W.kills))
    W.panel:line(3, "[G] danger-close airstrike")
end

local function cleanupEnemies()
    for _, s in ipairs(W.stops or {}) do pcall(s) end          -- drop the death hooks
    for _, g in ipairs(W.enemies or {}) do Ess.Object.remove(g) end
    W.stops, W.enemies = {}, {}
end

startWave = function()
    W.wave = W.wave + 1
    local count = 3 + W.wave * 2
    Ess.Hud.banner("WAVE " .. W.wave)
    Ess.UI.Toast(count .. " incoming!")
    local squad = Ess.Easy.Spawn.enemies(count)                -- spawns ahead + orders them onto you
    W.enemies, W.stops, W.alive = {}, {}, 0
    for _, g in ipairs(squad) do
        W.enemies[#W.enemies + 1] = g
        W.alive = W.alive + 1
        W.stops[#W.stops + 1] = Ess.On.death(g, function()
            if not W.active then return end
            W.alive = W.alive - 1
            W.kills = W.kills + 1
            updatePanel()
            if W.alive <= 0 then waveCleared() end
        end)
    end
    updatePanel()
end

waveCleared = function()
    Ess.UI.Toast("Wave " .. W.wave .. " cleared!")
    Ess.Object.heal(Ess.Player.character(0))                   -- reward: patch you up
    if W.wave % 3 == 0 then Ess.Easy.Spawn.crate() end         -- ... and a crate every 3rd wave
    Ess.Easy.Triggers.after(BREATHER, function() if W.active then startWave() end end)
end

-- Toggle (this file re-runs on each F11 press).
W.active = not W.active
if W.active then
    W.wave, W.kills, W.alive = 0, 0, 0
    if not W.panel then W.panel = Ess.UI.Panel{ x = 8, y = 150, w = 300, title = "IN HORDE" } end
    W.panel:show()
    W.strikeReady = Ess.Time.cooldown(STRIKE_CD)
    Ess.Keys.on(STRIKE_KEY, function()
        if not W.active then return end
        if W.strikeReady() then Ess.UI.Toast("Airstrike inbound!"); Ess.Easy.Airstrike.onMe(0)
        else Ess.UI.Toast("Airstrike on cooldown") end
    end)
    startWave()
    Loader.Printf("WaveSurvival: ON - survive. G for a danger-close airstrike. F11 to stop.")
else
    Ess.Keys.off(STRIKE_KEY)
    cleanupEnemies()
    if W.panel then W.panel:hide() end
    Ess.UI.Toast("Horde over -- " .. tostring(W.kills or 0) .. " kills across " .. tostring(W.wave or 0) .. " waves")
    Loader.Printf("WaveSurvival: OFF")
end
