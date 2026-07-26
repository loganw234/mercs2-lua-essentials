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
--   Ess.On.labeled(label, r, fn [,i])     fn(uGuid) ONCE per world-labeled object as it streams in near
--                                         player i (the ObjectFilter + Event.ObjectProximity discovery idiom)
--   Ess.On.script(sName, fn)              fn(tPayload) when the GAME posts the named script event -- the
--                                         one hook here that listens to the shipped game rather than polling

local Ess = _G.Ess
Ess.On = Ess.On or {}
Ess.On._n = Ess.On._n or 0
local function nextId(kind) Ess.On._n = Ess.On._n + 1; return "Ess.On." .. kind .. ":" .. Ess.On._n end

function Ess.On.death(guid, fn)
    -- A hook that never fires is the worst silence in the framework: nothing is wrong, nothing is logged,
    -- and the mod just never reacts. Ess.Safe.reject makes the no-op visible under Ess.DEBUG. The returned
    -- do-nothing stop() is unchanged, so callers keep working exactly as before.
    if not guid then
        Ess.Safe.reject("Ess.On.death", "no guid -- hook not armed, it will never fire")
        return function() end
    end
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
    if not char then
        Ess.Safe.reject("Ess.On.vehicle", "no character for player " .. tostring(i or 0)
            .. " -- hook not armed (asking for the co-op partner in single-player does this)")
        return function() end
    end
    return Ess.Object.pollVehicleChange(char, fn)        -- returns its own stop()
end

function Ess.On.tick(interval, fn)
    local id = nextId("tick")
    Ess.Loop.start(id, interval or 1, function() pcall(fn); return true end)
    return function() Ess.Loop.stop(id) end
end

-- Ess.On.labeled(sLabel, nRadius, fn, i) -> stop()
-- fn(uGuid) fires ONCE for each object carrying world label sLabel as it comes within nRadius of player i
-- (default 300 / player 0). This wraps the CONFIRMED discovery idiom for "find objects by their world
-- label" -- the game's own wiftutorialcollectibles.lua and our live-tested CollectibleFinder sample both do
-- exactly this dance: ObjectFilter.GetObjects can NOT query by label; the way to catch label-matching
-- objects is a proximity event armed on a label filter, which fires as they stream in. After each hit the
-- object is AddObject(filter, guid, true)-EXCLUDED so it never re-fires (that's also why this hook is
-- once-per-object by design -- the exclusion IS the dedupe). ObjectFilter's registration was mapped in the
-- 2026-07-22 bindings pass (wiki namespaces/objectfilter.md); the arg shapes here are the corpus-confirmed
-- ones, not guesses. Promoted from CollectibleFinder's inline version, which stays as the worked example.
function Ess.On.labeled(sLabel, nRadius, fn, i)
    if type(sLabel) ~= "string" or sLabel == "" then
        Ess.Safe.reject("Ess.On.labeled", "label must be a non-empty string, got " .. type(sLabel))
        return function() end
    end
    local char = Ess.Player.character(i or 0)
    if not char then
        Ess.Safe.reject("Ess.On.labeled", "no character for player " .. tostring(i or 0) .. " -- not armed")
        return function() end
    end
    local okf, filter = Ess.Safe.quiet(ObjectFilter.Create)
    if not okf or not filter then
        Ess.Safe.reject("Ess.On.labeled", "ObjectFilter.Create returned nothing -- not armed")
        return function() end
    end
    Ess.Safe.quiet(ObjectFilter.SetFilter, filter, sLabel)
    local ev
    local function onProx(tGuids)
        if type(tGuids) ~= "table" then tGuids = { tGuids } end
        for _, u in ipairs(tGuids) do
            Ess.Safe.quiet(ObjectFilter.AddObject, filter, u, true)   -- exclude: this object never re-fires
            pcall(fn, u)
        end
    end
    local oke, e = Ess.Safe.quiet(Event.CreatePersistent, Event.ObjectProximity,
        { filter, char, "<", nRadius or 300, false, false }, onProx, {})
    if oke then ev = e end
    return function() if ev then Ess.Safe.quiet(Event.Delete, ev); ev = nil end end
end

-- Ess.On.script(sName, fn) -> stop() -- fire fn(tPayload) whenever the GAME posts the named script event.
--
-- Every other hook in this file watches the world by polling or by an engine event. This one listens to the
-- shipped game's own announcements: `Event.Post("GPS Beacon Set", {nX = ..., nY = ...})` and friends. That
-- makes it the cheapest way to react to something the base game already knows about, instead of polling for
-- its side effects.
--
-- THE CALLBACK ARGUMENT ORDER IS NOT OBVIOUS, and getting it wrong is a silent nil-index. Event.Create's
-- callback data comes FIRST and the POSTED TABLE arrives after it. Measured 2026-07-26 with a probe event:
-- callback data "CALLBACKDATA" landed in argument 1 and the posted `{marker="PAYLOAD"}` in argument 2. This
-- is also why oilcon020.lua reads `.nX` off what looks like its own callback data -- it passes
-- `{self, tBeaconData}` where tBeaconData is an undeclared global, so the array is really just `{self}` and
-- the payload lands in the second slot by accident of that nil. Passing no callback data at all, as below,
-- makes the payload argument 1 and the whole thing legible.
--
-- Event names the shipped game posts (exact strings, spaces and capitals included):
--   "GPS Beacon Set" / "GPS Beacon Cleared"   -- see Ess.Gps, which wraps these two
--   "PDA Open" / "PDA Close"
--   "Support Menu Open" / "Support Menu Close" / "SupportUsed"
--   "Satellite Targetting Start" / " Success" / " Cancelled"
--   "Satellite Minigame Start" / " Sector Hit" / " Sector Miss"
--   "Transit Interface Open" / " Success" / "transitStart" / "transitEnd"
--   "MunitionsPickup" / "NoMunitions" / "UntagMunitions"
--   "mpPlayerJoin" / "mpPlayerLeft" / "InFocus" / "Airstrike" / "RecruitAvailable" / "HeroReported"
--   "MedevacComplete" / "SurvivalMode" / "SurvivalCooldownEnded" / "parkingLotStart" / "oilrigDestroyed"
--
-- The validation function is required by Event.ScriptEvent (it filters which posts you care about); this
-- passes an accept-everything one, matching what the game's own call sites do.
function Ess.On.script(sName, fn)
    if type(sName) ~= "string" or sName == "" then
        Ess.Safe.reject("Ess.On.script", "event name must be a non-empty string, got " .. type(sName))
        return function() end
    end
    if type(fn) ~= "function" then
        Ess.Safe.reject("Ess.On.script", "no callback given for '" .. sName .. "' -- not armed")
        return function() end
    end
    local ev
    local ok, e = Ess.Safe.quiet(Event.CreatePersistent, Event.ScriptEvent,
        { sName, function() return true end },
        function(tPayload) pcall(fn, tPayload) end, {})
    if not ok then
        Ess.Safe.reject("Ess.On.script", "could not create ScriptEvent for '" .. sName .. "'")
        return function() end
    end
    ev = e
    return function() if ev then Ess.Safe.quiet(Event.Delete, ev); ev = nil end end
end
