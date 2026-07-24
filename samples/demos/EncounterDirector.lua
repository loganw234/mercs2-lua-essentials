local KEYVAL = "f1"   -- trigger key; also add "EncounterDirector.lua=f1" under [OnKey] in lua_loader.ini

-- EncounterDirector.lua -- press F1 to have the "director" roll a random ENCOUNTER around you: an ambush, a
-- cash bounty, a guarded supply drop, an incoming artillery strike you have to dodge, or a 3-checkpoint time
-- trial. Weighted-random, so every press is a different beat -- turn the open world into a rolling sandbox.
--
-- Showcases the RNG + the intent bundles doing something replayable: Ess.RNG:pick (weighted choice) +
-- Ess.Easy.Spawn.enemies/crate + Ess.Easy.Objective.destroy (a self-marking bounty) + Ess.Quest (an
-- auto-wired reach-checkpoint race) + Ess.Support/Airstrike + Ess.Hud.banner + Ess.Time.cooldown (anti-spam).
--
-- DEPLOY: Ess (dist/Ess.lua) OnLoad; this at scripts/OnKey/EncounterDirector.lua , [OnKey] EncounterDirector.lua=f1.

local Ess = _G.Ess
if not (Ess and Ess.RNG and Ess.Easy and Ess.Quest) then
    if Loader and Loader.Printf then Loader.Printf("[director] load the Essentials framework (1_Ess.lua) first") end
    return
end

_G.Director = _G.Director or {}
local D = _G.Director
D.rng = D.rng or Ess.RNG.new()
D.ready = D.ready or Ess.Time.cooldown(3)     -- anti-spam: at most one roll every 3s

-- a point `dist` units ahead of you at ground level (hides the yaw/trig math)
local function ahead(dist)
    local x, y, z, yaw = Ess.Player.pose(0)
    if not x then return nil end
    local ax, az = Ess.Math.pointAhead(x, z, yaw or 0, dist)
    return ax, y, az
end

-- ---- the encounters (each self-contained; each cleans up after itself via the bundles it uses) ----
local function ambush()
    Ess.Hud.banner("AMBUSH!")
    Ess.UI.Toast("Contact -- you're surrounded")
    Ess.Easy.Spawn.enemies(D.rng:int(3) + 3)                 -- 4..6 hostiles, spawned onto you
end

local function bounty()
    local x, y, z = ahead(20)
    if not x then return end
    local tgt = Ess.Object.spawn("VZ Soldier", x, y, z)
    if not tgt then return end
    Ess.Hud.banner("BOUNTY")
    Ess.Easy.Objective.destroy(tgt, "Eliminate the bounty", function()
        Ess.Player.giveCash(20000); Ess.UI.Toast("Bounty collected! +$20,000")
    end)
end

local function supply()
    Ess.Hud.banner("SUPPLY DROP")
    Ess.UI.Toast("A crate dropped nearby -- and it's guarded")
    Ess.Easy.Spawn.crate()
    Ess.Easy.Spawn.enemies(2)
end

local function dangerClose()
    local x, y, z = Ess.Player.pose(0)                       -- your position RIGHT NOW -- so you must move
    if not x then return end
    Ess.Hud.banner("INCOMING -- MOVE!")
    Ess.UI.Toast("Artillery locked on your position!")
    Ess.Easy.Triggers.after(4, function() Ess.Easy.Airstrike.at(x, y, z) end)
end

local function timeTrial()
    local x1, y1, z1 = ahead(25)
    local x2, y2, z2 = ahead(50)
    local x3, y3, z3 = ahead(75)
    if not x1 then return end
    Ess.Hud.banner("TIME TRIAL")
    Ess.UI.Toast("Reach all three checkpoints!")
    Ess.Quest.new{
        steps = {
            { reach = { x1, y1, z1, 8 }, label = "Checkpoint 1" },
            { reach = { x2, y2, z2, 8 }, label = "Checkpoint 2" },
            { reach = { x3, y3, z3, 8 }, label = "Checkpoint 3" },
        },
        onComplete = function() Ess.Player.giveCash(15000); Ess.UI.Toast("Trial complete! +$15,000") end,
    }
end

local ENCOUNTERS = {
    { name = "ambush",       fn = ambush,      w = 3 },
    { name = "bounty",       fn = bounty,      w = 2 },
    { name = "supply drop",  fn = supply,      w = 2 },
    { name = "danger close", fn = dangerClose, w = 2 },
    { name = "time trial",   fn = timeTrial,   w = 1 },
}

-- one weighted-random encounter per press.
if not D.ready() then Ess.UI.Toast("Director is cooling down..."); return end
local pick = D.rng:pick(ENCOUNTERS)
Loader.Printf("Director: rolling '" .. pick.name .. "'")
local ok, err = pcall(pick.fn)
if not ok then Loader.Printf("Director '" .. pick.name .. "' error: " .. tostring(err)) end
