local KEYVAL = "f12"   -- toggle key; also add "BossFight.lua=f12" under [OnKey] in lua_loader.ini

-- BossFight.lua -- press F12 to summon a mini-BOSS ahead of you with a real on-screen health bar. It's tanky
-- (this engine has no SetMaxHealth, so "tanky" = it REGENERATES in phase 1). Chip it down to 50% and it
-- ENRAGES: the regen stops, the screen shakes, and it calls in reinforcements. Finish it for a cash reward.
-- Press F12 again while it's alive to abort the fight and clean everything up.
--
-- Showcases a full encounter arc from confirmed pieces: Ess.Object.spawnAhead + Ess.UI.Bar (live health) +
-- Ess.On.healthBelow (the phase-2 trigger) + Ess.On.death (victory) + Ess.Easy.Spawn.enemies (adds) +
-- Ess.Easy.Camera.shake + Ess.Hud.banner + Ess.Easy.Fun.fanfare + Ess.Mark + Ess.Loop.
--
-- DEPLOY: Ess (dist/Ess.lua) OnLoad; this at scripts/OnKey/BossFight.lua , [OnKey] BossFight.lua=f12.

local Ess = _G.Ess
if not (Ess and Ess.Object and Ess.UI and Ess.UI.Bar) then
    if Loader and Loader.Printf then Loader.Printf("[bossfight] load the Essentials framework (1_Ess.lua) first") end
    return
end

_G.BossFight = _G.BossFight or {}
local B = _G.BossFight

local LOOP_ID = "BossFight.tick"
local REGEN = 6          -- hp/sec regained in phase 1 (kept low so the fight is always winnable)
local REWARD = 50000

local function cleanup()
    Ess.Loop.stop(LOOP_ID)
    for _, s in ipairs(B.stops or {}) do pcall(s) end
    for _, g in ipairs(B.adds or {}) do Ess.Object.remove(g) end
    if B.boss then Ess.Object.remove(B.boss) end
    if B.mark then Ess.Mark.clear(B.mark); B.mark = nil end
    if B.bar then B.bar:hide() end
    B.stops, B.adds, B.boss = {}, {}, nil
end

-- Toggle: if a boss is already up, F12 aborts it.
if B.boss and Ess.Object.alive(B.boss) then
    cleanup()
    Ess.UI.Toast("Boss fight aborted")
    Loader.Printf("BossFight: aborted")
    return
end
cleanup()   -- clear any stale state before starting fresh

local boss = Ess.Object.spawnAhead("VZ Soldier", 22)
if not boss then Loader.Printf("BossFight: spawn failed"); return end
B.boss, B.phase = boss, 1
B.stops, B.adds = {}, {}
B.maxhp = Ess.Object.maxHealth(boss) or 100
B.mark = Ess.Easy.Mark.objective(boss)
B.bar = B.bar or Ess.UI.Bar{ x = 170, y = 40, w = 320, label = "BOSS" }
B.bar:label("BOSS"):set(1):show()
Ess.Hud.banner("BOSS INCOMING")
Ess.UI.Toast("Defeat the boss!")

-- Phase 2 at 50% health: enrage.
B.stops[#B.stops + 1] = Ess.On.healthBelow(boss, 50, function()
    if not B.boss then return end
    B.phase = 2
    Ess.Hud.banner("ENRAGED!")
    Ess.Easy.Camera.shake(0)
    if B.bar then B.bar:label("BOSS  [ENRAGED]") end
    local adds = Ess.Easy.Spawn.enemies(3)                 -- reinforcements rush you
    for _, g in ipairs(adds) do B.adds[#B.adds + 1] = g end
end)

-- Victory on death.
B.stops[#B.stops + 1] = Ess.On.death(boss, function()
    Ess.Loop.stop(LOOP_ID)
    if B.bar then B.bar:hide() end
    if B.mark then Ess.Mark.clear(B.mark); B.mark = nil end
    Ess.Hud.banner("BOSS DEFEATED")
    Ess.Easy.Fun.fanfare(true)
    Ess.Player.giveCash(REWARD)
    Ess.UI.Toast("Victory! +$" .. REWARD)
    B.boss = nil
end)

-- Heartbeat: drive the health bar, and regenerate the boss while it's in phase 1.
Ess.Loop.start(LOOP_ID, 0.25, function()
    if not B.boss or not Ess.Object.alive(boss) then return false end
    local hp = Ess.Object.health(boss)
    if not hp then return false end
    if B.phase == 1 then
        hp = math.min(B.maxhp, hp + REGEN * 0.25)          -- regen this tick
        Ess.Object.setHealth(boss, hp)
    end
    if B.bar then B.bar:set(hp / B.maxhp) end
    return true
end)

Loader.Printf("BossFight: boss up (regen phase 1, enrages at 50%). F12 again to abort.")
