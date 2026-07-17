-- Ess/10_player.lua -- Ess.Player: player/character identity, without the 8-getter native sprawl.
--
-- API:
--   Ess.Player.character(i) -> uCharGuid | nil     i=0 (or nil) local, i=1 secondary co-op partner
--   Ess.Player.slot(i)      -> uPlayerGuid | nil    the player-SLOT guid (distinct from the character guid)
--   Ess.Player.camera(i)    -> uCameraGuid | nil    resolves index -> Player.GetCamera(slot) in one call
--   Ess.Player.giveCash(n)                          routes through MrxPmc.AddCashQty (HUD-updating)
--   Ess.Player.giveFuel(n)                          routes through MrxPmc.AddFuelQty (HUD-updating)
--   Ess.Player.pose(i)      -> x, y, z, yaw, uChar, uPlayerSlot
--   Ess.Player.targetUnderReticle(i) -> uGuid|nil, x, y, z    "what am I aiming at" -- the flagship reason
--                                        the wiki's whole Engine Namespaces section exists at all
--   Ess.Player.removeBoundaries() -> nCleared    lifts every active out-of-bounds volume, all players
--   Ess.Player.setInputEnabled(bOn, i)           freeze/restore gameplay input (Player.SetInputEnabled)
--   Ess.Player.rumble(i, fLength)                Pg.Rumble -- controller haptic feedback
--   Ess.Player.teleport(x, y, z, yaw, onDone)    warp the player(s) to a world spot -- the CONFIRMED
--                                                MrxUtil.TeleportHeroesToLocations idiom (NOT raw SetPosition)
--   Ess.Player.inVehicle(i) -> uVehicleGuid|nil / .onFoot(i) -> bool    what the player is doing right now

import("MrxPmc")
import("MrxUtil")

local Ess = _G.Ess
Ess.Player = Ess.Player or {}

-- Ess.Player.character(i) -> uCharGuid | nil
--   i = 0 or nil -> Player.GetLocalCharacter()    (THIS machine's own character -- single-player-safe)
--   i = 1        -> Player.GetSecondaryCharacter() (the co-op partner's character; CONFIRMED nil outside
--                    co-op -- that nil is returned as-is, never silently coerced into something that would
--                    reach a downstream Object.* call expecting a real guid)
-- Collapses the flagship "which of these 8 getters do I want" problem: GetLocalCharacter/
-- GetPrimaryCharacter/GetSecondaryCharacter/GetAnyCharacter/GetLocalPlayer/GetPrimaryPlayer/
-- GetSecondaryPlayer/GetCharacter(slot). `Player.GetAnyCharacter()` (native, "whichever character, don't
-- care which") stays directly available for the rare case that actually wants it -- not worth wrapping.
function Ess.Player.character(i)
    if i == 1 then
        local ok, c = pcall(Player.GetSecondaryCharacter)
        if ok then return c end
        return nil
    end
    local ok, c = pcall(Player.GetLocalCharacter)
    if ok then return c end
    return nil
end

-- Ess.Player.slot(i) -> uPlayerGuid | nil -- same idea, the player-SLOT guid (what Camera.*/some Ai.*
-- calls actually want) instead of the character guid.
--
-- CONFIRMED LIVE (2026-07-16, single-player, PMC HQ): unlike Ess.Player.character(1) which correctly
-- returns nil outside co-op, Player.GetSecondaryPlayer() returns a REAL, distinct, non-nil player-slot
-- guid (different from slot 0's) even in single-player. Do NOT use `Ess.Player.slot(1) ~= nil` as a
-- "are we in co-op" check -- it will false-positive. Use Ess.Player.character(1) ~= nil for that instead.
function Ess.Player.slot(i)
    if i == 1 then
        local ok, p = pcall(Player.GetSecondaryPlayer)
        if ok then return p end
        return nil
    end
    local ok, p = pcall(Player.GetLocalPlayer)
    if ok then return p end
    return nil
end

-- Ess.Player.camera(i) -> uCameraGuid | nil
-- Every Camera.* call needs Player.GetCamera(slot) first -- two-step boilerplate on every call site.
-- This resolves the index straight to a camera guid so Ess.Camera.* helpers (later namespace) can take a
-- player index directly.
function Ess.Player.camera(i)
    local slot = Ess.Player.slot(i)
    if not slot then return nil end
    local ok, cam = pcall(Player.GetCamera, slot)
    if ok then return cam end
    return nil
end

-- Ess.Player.giveCash(n) / Ess.Player.giveFuel(n) -> ok
-- ALWAYS routes through MrxPmc.AddCashQty/AddFuelQty. NEVER Player.SetCash/AddCash/SetFuel/AddFuel --
-- those are CONFIRMED to silently skip the HUD refresh MrxPmc's calls trigger, so the number changes but
-- the player never sees it update. No player-index argument: cash/fuel is this machine's own campaign
-- wallet, not a per-character resource (in co-op each machine has its own wallet already).
function Ess.Player.giveCash(n)
    local ok = pcall(MrxPmc.AddCashQty, n, false, "[Ess]")
    return ok and true or false
end

function Ess.Player.giveFuel(n)
    local ok = pcall(MrxPmc.AddFuelQty, n)
    return ok and true or false
end

-- Ess.Player.pose(i) -> x, y, z, yaw, uChar, uPlayerSlot
-- One-stop "where is this player, facing which way" -- promoted from uilib's private pose() helper.
-- yaw defaults to 0 if unreadable; x/y/z are nil if there's no character at all (e.g. i=1 outside co-op).
function Ess.Player.pose(i)
    local char = Ess.Player.character(i)
    local player = Ess.Player.slot(i)
    if not char then return nil, nil, nil, 0, nil, player end
    local ok, px, py, pz = pcall(Object.GetPosition, char)
    if not ok or not px then return nil, nil, nil, 0, char, player end
    local yaw = 0
    local oky, yv = pcall(Object.GetYaw, char)
    if oky and yv then yaw = yv end
    return px, py, pz, yaw, char, player
end

-- Ess.Player.targetUnderReticle(i) -> uGuid | nil, x, y, z
-- CONFIRMED shape (wiki/namespaces/player.md): `nX, nY, nZ, uGuid = Player.GetTargetUnderReticle(uPlayerGuid)`
-- -- the coordinates come back FIRST, the guid last (and nil if nothing's under the reticle). Ess.Player's
-- own convention elsewhere puts the guid first as the primary return value, so this reorders on the way
-- out rather than exposing the native's own coordinates-then-guid order.
function Ess.Player.targetUnderReticle(i)
    local slot = Ess.Player.slot(i)
    if not slot then return nil end
    local ok, x, y, z, g = pcall(Player.GetTargetUnderReticle, slot)
    if not ok then return nil end
    return g, x, y, z
end

-- Ess.Player.removeBoundaries() -- CONFIRMED (wiki/snippets.md): clears every out-of-bounds volume
-- currently active, for every connected player at once (co-op safe by construction -- iterates
-- Player.GetAllPlayers(), not a single index, so this takes no `i` argument). Only clears what's active
-- RIGHT NOW -- doesn't disable the boundary system itself, so the game's own scripts can still add a new
-- one later (e.g. on a mission/area transition). Runtime-only, matching Ess.Object.setInvincible-style
-- "re-added each load" boundary volumes documented elsewhere in this project.
function Ess.Player.removeBoundaries()
    local ok, players = pcall(Player.GetAllPlayers)
    if not ok or type(players) ~= "table" then return 0 end
    local n = 0
    for _, p in ipairs(players) do
        if pcall(Player.RemoveAllBoundary, p) then n = n + 1 end
    end
    return n
end

-- Ess.Player.setInputEnabled(bOn, i) -- enable (true) or freeze (false) a player's gameplay input
-- (movement/actions) via Player.SetInputEnabled on the player-SLOT guid. The confirmed "freeze the player
-- during a scripted moment / while a modal UI box has focus" primitive -- Ess.TextConsole uses this same
-- native for its lockPlayer option, and every custom chat/console overlay wants exactly it (freeze on open,
-- restore on close). Takes the player SLOT (not the character), matching the native; i defaults to local.
-- CONFIRMED to leave the keyboard-event stream a Lua UI reads (Loader.PopKeyEvents) intact -- it gates
-- GAME control only, so a chat box can still type while the world is frozen underneath it.
function Ess.Player.setInputEnabled(bOn, i)
    local p = Ess.Player.slot(i)
    if not p then return end
    pcall(Player.SetInputEnabled, p, bOn and true or false)
end

-- Ess.Player.rumble(i, fLength) -- CONFIRMED (wiki/namespaces/pg.md): Pg.Rumble(uCharacterGuid, fLength)
-- (`resident/mrxactionhijack.lua`, real values 0.15-ish seconds). Controller haptic feedback -- the common
-- "juice" a damage/impact/pickup moment wants -- resolved through Ess.Player.character(i) rather than
-- taking a raw guid, matching every other function in this file.
function Ess.Player.rumble(i, fLength)
    local char = Ess.Player.character(i)
    if not char then return end
    pcall(Pg.Rumble, char, fLength or 0.2)
end

-- Ess.Player.teleport(x, y, z, yaw, onDone) -- warp the player to a world position. Wraps the CONFIRMED
-- MrxUtil.TeleportHeroesToLocations idiom (the exact mechanism Ess.Contract's own `def.start` uses, and the
-- one grand_prix's race contract teleport ran on) -- deliberately NOT raw Object.SetPosition, which is
-- unreliable on characters (streaming/physics can snap them back). Teleports ALL connected heroes to this
-- spot (co-op safe); `onDone` fires once the warp completes (use it to spawn/enable things only after the
-- player has actually arrived). For the co-op case where each hero needs a DIFFERENT spot, drop to
-- MrxUtil.TeleportHeroesToLocations directly with a per-hero location list.
--
-- CONFIRMED live behavior: teleporting OUT of the PMC HQ interior cell unloads that cell and drops the
-- player into the open world -- interior coordinates do NOT round-trip (teleport back to an interior y and
-- you'll land on open-world terrain below it and take fall damage instead). This is the clean way to get
-- the player into the streamed gameworld for anything that misbehaves in the cramped HQ interior (e.g. the
-- spawn+enter-vehicle bridge-stall Ess.Vehicle flags). Fall damage on this engine is capped (~97) and never
-- fatal on its own, so an accidental drop can't kill the player -- but heal afterward (Ess.Object.heal) if
-- you don't want them left hurt.
function Ess.Player.teleport(x, y, z, yaw, onDone)
    local locs = { { x, y, z, yaw or 0 } }
    pcall(MrxUtil.TeleportHeroesToLocations, locs, onDone or function() end)
end

-- Ess.Player.inVehicle(i) -> uVehicleGuid | nil -- the vehicle the player is in right now (driver OR
-- passenger), nil on foot. Just Ess.Object.vehicleOf on the player's character, surfaced here because "am I
-- driving?" is a question mods ask constantly (gate a boost/horn, a car-only menu, a "get out first" prompt).
function Ess.Player.inVehicle(i)
    local char = Ess.Player.character(i)
    if not char then return nil end
    return Ess.Object.vehicleOf(char)
end

-- Ess.Player.onFoot(i) -> bool -- the complement: true when the player isn't in any vehicle.
function Ess.Player.onFoot(i)
    return Ess.Player.inVehicle(i) == nil
end
