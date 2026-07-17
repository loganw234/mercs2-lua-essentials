-- Ess/32_on.lua -- Ess.On: intent-named REACTIVE hooks. Most of Ess is imperative (you make things happen);
-- this is the other half -- respond to what the world does, without wiring raw Event.* or authoring a
-- Contract. Each hook returns a stop() you call to cancel it. Built on confirmed pieces (Event.ObjectDeath,
-- Ess.Object.pos/health, Ess.Player, Ess.Loop, Ess.Object.pollVehicleChange, Ess.Math.within2D).
--
-- HONEST LIMITS (engine, not laziness): there is no clean "the PLAYER got a kill" or "who shot me" event on
-- this bridge, so those aren't here -- Ess.On.playerHurt polls the player's own health dropping (the
-- feasible version of "I took damage"), and Ess.On.death watches a KNOWN object you already have a guid for.
--
-- API (every one returns stop()):
--   Ess.On.death(guid, fn)                fn() when that object dies (a real Event.ObjectDeath hook)
--   Ess.On.enterArea(x,y,z,r, fn [,i])    fn(px,py,pz) the moment player i enters radius r -- fires ONCE
--   Ess.On.exitArea(x,y,z,r, fn [,i])     fn(...) the moment they leave (after being inside) -- fires ONCE
--   Ess.On.insideArea(x,y,z,r, fn [,i])   fn(...) EVERY tick while they're inside (a live "zone" callback)
--   Ess.On.healthBelow(guid, pct, fn)     fn(hp) when guid drops below pct% of its health at arm time -- ONCE
--   Ess.On.playerHurt(fn [,i])            fn(newHp, lost) whenever player i's health DROPS (repeats)
--   Ess.On.vehicle(fn [,i])               fn(nowVeh, prevVeh) on entering/leaving a vehicle (poll idiom)
--   Ess.On.tick(interval, fn)             fn() every `interval` seconds (a named, reload-safe Ess.Loop)

local Ess = _G.Ess
Ess.On = Ess.On or {}
Ess.On._n = Ess.On._n or 0
local function nextId(kind) Ess.On._n = Ess.On._n + 1; return "Ess.On." .. kind .. ":" .. Ess.On._n end

function Ess.On.death(guid, fn)
    if not guid then return function() end end
    local h = Ess.Event.on(Event.ObjectDeath, { guid }, function() pcall(fn) end)
    return function() Ess.Event.off(h) end
end

function Ess.On.enterArea(x, y, z, r, fn, i)
    local id = nextId("enterArea")
    Ess.Loop.start(id, 0.25, function()
        local px, _, pz = Ess.Player.pose(i or 0)
        if px and Ess.Math.within2D(x, z, px, pz, r) then pcall(fn, px, y, pz); return false end
        return true
    end)
    return function() Ess.Loop.stop(id) end
end

function Ess.On.exitArea(x, y, z, r, fn, i)
    local id = nextId("exitArea")
    local been = false                                   -- only "leaving" counts once you've been inside
    Ess.Loop.start(id, 0.25, function()
        local px, _, pz = Ess.Player.pose(i or 0)
        if not px then return true end
        if Ess.Math.within2D(x, z, px, pz, r) then been = true
        elseif been then pcall(fn, px, y, pz); return false end
        return true
    end)
    return function() Ess.Loop.stop(id) end
end

function Ess.On.insideArea(x, y, z, r, fn, i)
    local id = nextId("insideArea")
    Ess.Loop.start(id, 0.25, function()
        local px, _, pz = Ess.Player.pose(i or 0)
        if px and Ess.Math.within2D(x, z, px, pz, r) then pcall(fn, px, y, pz) end
        return true
    end)
    return function() Ess.Loop.stop(id) end
end

function Ess.On.healthBelow(guid, pct, fn)
    local id = nextId("healthBelow")
    local base
    Ess.Loop.start(id, 0.4, function()
        local hp = Ess.Object.health(guid)
        if hp then
            base = base or (hp > 0 and hp) or base       -- baseline = health when first read
            if base and base > 0 and hp <= base * ((pct or 50) / 100) then pcall(fn, hp); return false end
        end
        return true
    end)
    return function() Ess.Loop.stop(id) end
end

function Ess.On.playerHurt(fn, i)
    local id = nextId("playerHurt")
    local last
    Ess.Loop.start(id, 0.2, function()
        local hp = Ess.Object.health(Ess.Player.character(i or 0))
        if hp then
            if last and hp < last then pcall(fn, hp, last - hp) end
            last = hp
        end
        return true
    end)
    return function() Ess.Loop.stop(id) end
end

function Ess.On.vehicle(fn, i)
    local char = Ess.Player.character(i or 0)
    if not char then return function() end end
    return Ess.Object.pollVehicleChange(char, fn)        -- returns its own stop()
end

function Ess.On.tick(interval, fn)
    local id = nextId("tick")
    Ess.Loop.start(id, interval or 1, function() pcall(fn); return true end)
    return function() Ess.Loop.stop(id) end
end
