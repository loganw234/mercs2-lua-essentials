-- Ess/58_support.lua -- Ess.Support: the iconic Mercs2 combat call-ins -- airstrikes, artillery, gunship
-- runs, bombing runs, and reinforcements -- as standalone one-liners. These are the exact confirmed effects
-- Ess.Contract's support system fires (82_contract_encounter.lua's SUPPORT_EFFECTS), lifted out so you can
-- call one ANYWHERE without authoring a contract. Fire-and-forget: each schedules its own timed ordnance /
-- flybys; the spawned shells and flyby vehicles are engine-managed one-shots, so there's nothing to clean up.
--
-- All positions are world (x, y, z). `owner` (a faction NAME like "China" / "Allied") tags who "fired" it so
-- the game attributes damage/kills correctly; omit for unattributed. Template/ammo/vehicle strings default to
-- the confirmed ones the contract system uses -- pass your own once the spawn catalog lands.
--
-- API:
--   Ess.Support.shell(x,y,z, opts)       one falling shell (the primitive the rest build on). opts: ammo, dropHeight, owner
--   Ess.Support.artillery(x,y,z, opts)   N shells rain onto the area. opts: count(5), radius(14), ammo, owner, stagger
--   Ess.Support.airstrike(x,y,z, opts)   a gunship/jet streaks over. opts: vehicle, altitude(120), speed(55)
--   Ess.Support.bombingrun(x,y,z, opts)  a plane walks a stick of bombs across it. opts: vehicle, ammo, count(3), altitude, speed
--   Ess.Support.gunship(x,y,z, opts)     N helicopters pass over, fanned. opts: template("AH1Z"), count(3), stagger, spread
--   Ess.Support.reinforce(x,y,z, opts)   units arrive. opts: faction, units={templates}, deliver("copter"|"paradrop"|direct)
--   Ess.Easy.Airstrike.at(x,y,z) / .onTarget(i) / .onMe(i)   -- one-tap presets (a jet pass + a few shells)

import("MrxCopterDrop")

local Ess = _G.Ess
Ess.Support = Ess.Support or {}
Ess.Easy = Ess.Easy or {}
Ess.Easy.Airstrike = Ess.Easy.Airstrike or {}

-- MrxCopterDrop.Create wants a 2-letter faction CODE, not the long name (matches the contract's own map).
local HELO_FACTION = { Allied = "AL", China = "CH", Guerilla = "GR", OC = "OC", Pirate = "PR", VZ = "VZ" }
local rng = Ess.RNG.new()
local function scatter(r) return (rng:next() * 2 - 1) * r end        -- uniform in [-r, r]
local function ownerGuid(name) return name and Ess.Guid(name) or nil end
local function after(delay, fn) pcall(Event.Create, Event.TimerRelative, { delay }, fn) end

function Ess.Support.shell(x, y, z, opts)
    opts = opts or {}
    pcall(Airstrike.SpawnOrdnance, opts.ammo or "Gunship Shell", x, y + (opts.dropHeight or 220), z,
        0, -100, 0, "impact", 1, ownerGuid(opts.owner))
end

function Ess.Support.artillery(x, y, z, opts)
    opts = opts or {}
    local n, r, stagger = opts.count or 5, opts.radius or 14, opts.stagger or 0.35
    for i = 1, n do
        local dx, dz = scatter(r), scatter(r)
        after(stagger * (i - 1), function() Ess.Support.shell(x + dx, y, z + dz, opts) end)
    end
end

function Ess.Support.airstrike(x, y, z, opts)
    opts = opts or {}
    pcall(Airstrike.Flyby, opts.vehicle or "Support Vehicle (Autogunship)",
        x - 50, z + 300, x, z, y + (opts.altitude or 120), opts.speed or 55)
end

function Ess.Support.bombingrun(x, y, z, opts)
    opts = opts or {}
    local vehicle, bomb = opts.vehicle or "Support Vehicle (A10)", opts.ammo or "Bomb"
    local alt, speed, n, owner = y + (opts.altitude or 150), opts.speed or 160, opts.count or 3, ownerGuid(opts.owner)
    local uJet
    local function drop()
        for i = 1, n do
            after(0.14 * (i - 1), function()
                local jx, jy, jz = x, alt, z
                if uJet then local ok, a, b, c = pcall(Object.GetPosition, uJet); if ok and a then jx, jy, jz = a, b, c end end
                pcall(Airstrike.SpawnOrdnance, bomb, jx, jy, jz, 0, -60, 0, "impact", 1, owner)
            end)
        end
    end
    local ok, jet = pcall(Airstrike.Flyby, vehicle, x - 350, z + 350, x, z, alt, speed, drop)
    if ok then uJet = jet end
end

function Ess.Support.gunship(x, y, z, opts)
    opts = opts or {}
    local tmpl, n = opts.template or "AH1Z", opts.count or 3
    local stagger, spread = opts.stagger or 1.6, opts.spread or 45
    for i = 1, n do
        local off = (i - 1) * spread
        after(stagger * (i - 1), function()
            pcall(Airstrike.Flyby, tmpl, x - 60 - off, z + 300 + off, x + off, z, y + (opts.altitude or 55), opts.speed or 45)
        end)
    end
end

function Ess.Support.reinforce(x, y, z, opts)
    opts = opts or {}
    local fac, units, deliver = HELO_FACTION[opts.faction] or opts.faction or "VZ", opts.units or {}, opts.deliver
    local function spawnOne(i, tmpl)
        local ox, oz = ((i - 1) % 3 - 1) * 4, math.floor((i - 1) / 3) * 4
        if deliver == "copter" then pcall(MrxCopterDrop.Create, fac, tmpl, x + ox, y, z + oz, false)
        else Ess.Object.spawn(tmpl, x + ox, y, z + oz) end           -- guarded spawn (blank template safe)
    end
    if deliver == "paradrop" then
        pcall(Airstrike.Flyby, opts.vehicle or "Support Vehicle (Paradrop_AL)", x - 350, z + 350, x, z, y + (opts.altitude or 180), opts.speed or 140)
        for i, tmpl in ipairs(units) do after(1.5 + 0.2 * i, function() spawnOne(i, tmpl) end) end
    else
        for i, tmpl in ipairs(units) do spawnOne(i, tmpl) end
    end
end

-- ---- Easy presets: a jet pass plus a few shells on a spot / your target / your own head ----
function Ess.Easy.Airstrike.at(x, y, z)
    Ess.Support.airstrike(x, y, z)
    Ess.Support.artillery(x, y, z, { count = 4, radius = 10 })
end
function Ess.Easy.Airstrike.onTarget(i)
    local u = Ess.Player.targetUnderReticle(i or 0)
    if u then local x, y, z = Ess.Object.pos(u); if x then Ess.Easy.Airstrike.at(x, y, z) end end
end
function Ess.Easy.Airstrike.onMe(i)                                  -- for the brave / the cinematic
    local x, y, z = Ess.Player.pose(i or 0)
    if x then Ess.Easy.Airstrike.at(x, y, z) end
end
