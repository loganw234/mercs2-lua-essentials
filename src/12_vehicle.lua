-- Ess/12_vehicle.lua -- Ess.Vehicle: seat/rider queries + the human-doesn't-SetPosition workaround.
--
-- API:
--   Ess.Vehicle.driver(uVeh) -> uCharGuid | nil
--   Ess.Vehicle.riders(uVeh) -> { uCharGuid, ... }
--   Ess.Vehicle.seatOf(uChar) -> sSeat | nil
--   Ess.Vehicle.enterBestSeat(uChar, uVeh) -> ok
--   Ess.Vehicle.enterSeatExcluding(uChar, uVeh, excludeSeats) -> ok, sSeatTypeUsed
--   Ess.Vehicle.exit(uVeh, uChar) -> ok
--   Ess.Vehicle.flyTo(uHeli, x, y, z, opts) -> cancel()               send an AI heli to a point (driver-wait
--                                        + Ai.Deliver); opts.onReady(driver) fires when the order is issued
--   Ess.Vehicle.followGhost(template, x, y, z) -> ghost | nil         ghost.guid, ghost:update(x,y,z), ghost:remove()
--   Ess.Easy.Vehicle.summon(sTemplate, opts) -> uVeh | nil            spawn a vehicle in front + hop in the
--                                        driver seat -- the whole "give me a <vehicle>" thought in ONE line

import("MrxUtil")

local Ess = _G.Ess
Ess.Vehicle = Ess.Vehicle or {}

-- Ess.Vehicle.driver(uVeh) -> uCharGuid | nil
function Ess.Vehicle.driver(uVeh)
    local ok, d = pcall(Vehicle.GetDriver, uVeh)
    if ok then return d end
    return nil
end

-- Ess.Vehicle.riders(uVeh) -> { uCharGuid, ... } (empty table if none/unreadable, never nil)
function Ess.Vehicle.riders(uVeh)
    local ok, r = pcall(Vehicle.GetRiders, uVeh)
    if ok and type(r) == "table" then return r end
    return {}
end

-- Ess.Vehicle.seatOf(uChar) -> sSeat | nil -- which seat uChar currently occupies, if any.
-- Together with .driver/.riders this collapses the 7-getter overlap (GetDriver/GetRiders/GetFromRider/
-- GetSeatFromRider/GetRiderFromSeat/GetFromSeat/GetSeatByType) down to the 3 shapes actually needed day
-- to day; the raw namespace stays available for anything more exotic.
function Ess.Vehicle.seatOf(uChar)
    local ok, s = pcall(Vehicle.GetSeatFromRider, uChar)
    if ok then return s end
    return nil
end

-- Ess.Vehicle.enterBestSeat(uChar, uVeh) -> ok
-- pcall-wrapped MrxUtil.EnterBestAvailableSeat -- confirmed d/g/p/c (driver/gunner/passenger/cargo) seat
-- priority order.
--
-- CONFIRMED LIVE (2026-07-16, PMC HQ interior): the call itself returns true and the character does
-- enter the seat. CAUTION, unconfirmed causally but suspicious: immediately after a Pg.Spawn'd Veyron +
-- enterBestSeat from INSIDE this interior cell, the very next bridge chunk (even a bare `return 1+1`)
-- stalled the Lua execution tick for 30+s with the game process still alive/"Responding" per Windows --
-- recovered only via killing the process and a fresh relaunch. Never confirmed the vehicle-entry was the
-- actual cause (could be coincidental), but flagging: avoid spawning+entering a vehicle from inside an
-- interior cell again without Logan's review, and if testing this elsewhere, don't immediately chain a
-- follow-up query in the same breath -- leave a beat and re-probe first.
function Ess.Vehicle.enterBestSeat(uChar, uVeh)
    local ok = pcall(MrxUtil.EnterBestAvailableSeat, uChar, uVeh)
    return ok and true or false
end

-- Ess.Vehicle.enterSeatExcluding(uChar, uVeh, excludeSeats) -> ok, sSeatTypeUsed | nil
-- For "board a vehicle but never take the driver seat" (e.g. a co-op partner boarding after the driver
-- already has). VERIFIED against primary source: `wiki/deep-dives/destroyer-vehicle.md`'s `DestroyerTool.lua`
-- (a real, live-confirmed-working deployed script, not a summary) does exactly this for its co-op-partner
-- boarding button -- `Vehicle.GetSeatByType(uVeh, sType, true)` resolves a specific seat-type code ("d"/
-- "g"/"p"/"c") to a seat guid, then `Vehicle.EnterBySeatGuid(uVeh, uChar, uSeat, true)` boards it -- looped
-- over the allowed types in priority order, skipping any type named in `excludeSeats`. Both boolean
-- arguments are passed exactly as the confirmed-working reference does; their precise semantics are
-- otherwise unconfirmed (see wiki/namespaces/vehicle.md), so this doesn't invent different values.
local ALL_SEAT_TYPES = { "d", "g", "p", "c" }   -- driver/gunner/passenger/cargo, matches EnterBestAvailableSeat's own priority order
function Ess.Vehicle.enterSeatExcluding(uChar, uVeh, excludeSeats)
    local excl = {}
    for _, s in ipairs(excludeSeats or {}) do excl[s] = true end
    for _, sType in ipairs(ALL_SEAT_TYPES) do
        if not excl[sType] then
            local okSeat, uSeat = pcall(Vehicle.GetSeatByType, uVeh, sType, true)
            if okSeat and uSeat then
                local okEnter, entered = pcall(Vehicle.EnterBySeatGuid, uVeh, uChar, uSeat, true)
                if okEnter and entered then return true, sType end
            end
        end
    end
    return false, nil
end

-- Ess.Vehicle.exit(uVeh, uChar) -> ok
-- The obvious missing complement to enterBestSeat/enterSeatExcluding -- getting a character back OUT of a
-- vehicle. CONFIRMED signature+usage (destroyer-vehicle.md's DestroyerTool.lua, a real live-confirmed-
-- working script): `Vehicle.Exit(uVehicle, uCharacter, bImmediate)`, called as
-- `Vehicle.Exit(State.uBoat, uChar, true)`. Passes the same trailing `true` the confirmed reference uses;
-- its exact semantics (beyond "make this happen right now" by naming convention) aren't pinned down by
-- call-site evidence alone.
function Ess.Vehicle.exit(uVeh, uChar)
    local ok, result = pcall(Vehicle.Exit, uVeh, uChar, true)
    return ok and result and true or false
end

-- Ess.Vehicle.flyTo(uHeli, x, y, z, opts) -> cancel() -- send an AI helicopter to a world point. Wraps the
-- two gotchas the drop/delivery code (mrxcopterdrop.lua) handles: (1) the flight command is
-- Ai.Deliver(driver, x, y, z, dropHeight, careless) -- NOT Ai.Goal "MoveToPos", which does NOT fly a heli;
-- (2) a freshly-spawned heli has no driver for a moment, so this polls Ess.Vehicle.driver until it exists,
-- THEN issues the order. opts.height (drop height, default 0.5), opts.careless (bool), opts.onReady(driver)
-- (fired once the order is issued -- handy for chaining a camera onto the pilot). Returns cancel() to stop
-- the driver-wait early.
function Ess.Vehicle.flyTo(uHeli, x, y, z, opts)
    opts = opts or {}
    local id = "Ess.Vehicle.flyTo:" .. tostring(uHeli)
    Ess.Loop.start(id, 0.15, function()
        local drv = Ess.Vehicle.driver(uHeli)
        if not drv then return true end                 -- keep waiting for the pilot to exist
        pcall(Ai.Deliver, drv, x, y, z, opts.height or 0.5, opts.careless and true or false)
        if opts.onReady then pcall(opts.onReady, drv) end
        return false                                    -- done
    end)
    return function() Ess.Loop.stop(id) end
end

-- Ess.Vehicle.followGhost(template, x, y, z) -> ghost | nil
-- Spawns `template` at (x,y,z) and returns a `ghost` object: ghost.guid (current guid, may change),
-- ghost:update(nx, ny, nz), ghost:remove().
--
-- CONFIRMED gotcha (ForgeCam's ghost-preview work): Object.SetPosition silently does NOT move a spawned
-- HUMAN (it works fine on props/vehicles). :update() tries SetPosition first, then re-reads the real
-- position -- if it's still off by more than ~3 units (SetPosition didn't take, i.e. this is a human/AI
-- actor that ignored it), it despawns and RE-spawns the template at the new spot instead, and ghost.guid
-- is updated to the new guid so callers always read the CURRENT handle off the object, not a stale one.
function Ess.Vehicle.followGhost(template, x, y, z)
    if type(template) ~= "string" or template:match("^%s*$") then
        Ess.Log("Vehicle.followGhost: blank template rejected (would CTD Pg.Spawn)")
        return nil
    end
    local ok, u = pcall(Pg.Spawn, template, x, y, z)
    if not ok or not u then return nil end

    local ghost = { guid = u }

    function ghost:update(nx, ny, nz)
        pcall(Object.SetPosition, self.guid, nx, ny, nz)
        local okp, cx, cy, cz = pcall(Object.GetPosition, self.guid)
        if okp and cx then
            local dx, dz = cx - nx, cz - nz
            if dx * dx + dz * dz > 9 then -- didn't take (likely human/AI) -- respawn at the new spot
                pcall(Object.Remove, self.guid)
                local ok2, u2 = pcall(Pg.Spawn, template, nx, ny, nz)
                if ok2 and u2 then self.guid = u2 end
            end
        end
    end

    function ghost:remove()
        pcall(Object.Remove, self.guid)
    end

    return ghost
end

-- ============================================================
-- Ess.Easy.Vehicle.summon(sTemplate, opts) -> uVeh | nil
-- The beginner one-liner this whole namespace exists to make possible: the thought "I want a UH1
-- Transport" becomes `Ess.Easy.Vehicle.summon("UH1 Transport")` and you're flying it. Spawns the vehicle a
-- short way IN FRONT of the local player (no coordinate/yaw math to know -- Ess.Object.spawnAhead hides it)
-- and drops the player into the best (driver-first) seat. Midair by default so an aircraft hovers the
-- instant you're piloting it and a ground vehicle just settles; opts.dist / opts.height override.
-- Returns the vehicle guid (nil if the template name was wrong -- spawn logs which).
-- ============================================================
Ess.Easy = Ess.Easy or {}
Ess.Easy.Vehicle = Ess.Easy.Vehicle or {}
function Ess.Easy.Vehicle.summon(sTemplate, opts)
    opts = opts or {}
    local v = Ess.Object.spawnAhead(sTemplate, opts.dist or 18, opts.height or 10)
    if not v then return nil end
    Ess.Vehicle.enterBestSeat(Ess.Player.character(0), v)
    return v
end
