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

import("MrxPmc")

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
