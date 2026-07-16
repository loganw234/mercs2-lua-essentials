-- Ess/12_vehicle.lua -- Ess.Vehicle: seat/rider queries + the human-doesn't-SetPosition workaround.
--
-- API:
--   Ess.Vehicle.driver(uVeh) -> uCharGuid | nil
--   Ess.Vehicle.riders(uVeh) -> { uCharGuid, ... }
--   Ess.Vehicle.seatOf(uChar) -> sSeat | nil
--   Ess.Vehicle.enterBestSeat(uChar, uVeh) -> ok
--   Ess.Vehicle.enterSeatExcluding(uChar, uVeh, excludeSeats) -> ok   (documented gap, see below)
--   Ess.Vehicle.followGhost(template, x, y, z) -> ghost | nil         ghost.guid, ghost:update(x,y,z), ghost:remove()

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
function Ess.Vehicle.enterBestSeat(uChar, uVeh)
    local ok = pcall(MrxUtil.EnterBestAvailableSeat, uChar, uVeh)
    return ok and true or false
end

-- Ess.Vehicle.enterSeatExcluding(uChar, uVeh, excludeSeats) -> ok
-- INTENDED for "board a vehicle but never take the driver seat" (e.g. a co-op partner boarding after the
-- driver already has). DOCUMENTED GAP: the exact native call this should use hasn't been verified against
-- primary source in this pass (only summarized third-hand from a deep-dive survey) -- MrxUtil does NOT
-- appear to expose an exclusion-list form of seat entry, and fabricating a plausible-sounding function
-- name here would be worse than being honest about the gap. This currently just falls back to
-- enterBestSeat, which does NOT guarantee avoiding an excluded seat -- do not rely on the exclusion
-- actually working until this is verified against wiki/deep-dives/destroyer-vehicle.md and fixed.
function Ess.Vehicle.enterSeatExcluding(uChar, uVeh, excludeSeats)
    Ess.Log("Vehicle.enterSeatExcluding: NOT YET VERIFIED, falling back to enterBestSeat (exclusion not enforced)")
    return Ess.Vehicle.enterBestSeat(uChar, uVeh)
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
