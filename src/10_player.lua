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
--   Ess.Player.viewPoint(nDist, nHeight, i) -> x, y, z | nil   a point ahead of where the player is LOOKING
--                                        (engine camera vector -- no reticle fallback, no obstacle test)
--   Ess.Player.removeBoundaries() -> nCleared    lifts every active out-of-bounds volume, all players
--   Ess.Player.setInputEnabled(bOn, i)           freeze/restore gameplay input (Player.SetInputEnabled)
--   Ess.Player.rumble(i, fLength)                Pg.Rumble -- controller haptic feedback
--   Ess.Player.teleport(x, y, z, yaw, onDone)    warp the player(s) to a world spot -- the CONFIRMED
--                                                MrxUtil.TeleportHeroesToLocations idiom (NOT raw SetPosition)
--   Ess.Player.inVehicle(i) -> uVehicleGuid|nil / .onFoot(i) -> bool    what the player is doing right now
--   Ess.Player.cash() -> n                       read the economy (giveCash stays the way to CHANGE it)
--   Ess.Player.fuel() -> nCurrent, nCapacity
--   Ess.Player.isCoop() -> bool                  a real co-op session, not just "slot 1 exists"
--   Ess.Player.count() -> n                      occupied player slots (1 in single-player)
--   Ess.Player.joined(i) -> bool                 is slot i occupied -- wraps a native that takes an INDEX,
--                                                not a guid, and returns nil (falsy) if handed one
--   Ess.Player.name(i) -> sName | nil            the slot's profile name

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
        local ok, c = Ess.Safe.quiet(Player.GetSecondaryCharacter)
        if ok then return c end
        return nil
    end
    local ok, c = Ess.Safe.quiet(Player.GetLocalCharacter)
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
        local ok, p = Ess.Safe.quiet(Player.GetSecondaryPlayer)
        if ok then return p end
        return nil
    end
    local ok, p = Ess.Safe.quiet(Player.GetLocalPlayer)
    if ok then return p end
    return nil
end

-- Ess.Player.camera(i) -> uCameraGuid | nil
-- Every Camera.* call needs Player.GetCamera(slot) first -- two-step boilerplate on every call site.
-- This resolves the index straight to a camera guid so Ess.Camera.* helpers (later namespace) can take a
-- player index directly.
function Ess.Player.camera(i)
    local slot = Ess.Player.slot(i)
    if not slot then return Ess.Safe.reject("Ess.Player", "no player slot for that index "
        .. "-- index 1 is the CO-OP PARTNER and is nil in single-player") end
    local ok, cam = Ess.Safe.quiet(Player.GetCamera, slot)
    if ok then return cam end
    return nil
end

-- Ess.Player.giveCash(n) / Ess.Player.giveFuel(n) -> ok
-- ALWAYS routes through MrxPmc.AddCashQty/AddFuelQty. NEVER Player.SetCash/AddCash/SetFuel/AddFuel --
-- those are CONFIRMED to silently skip the HUD refresh MrxPmc's calls trigger, so the number changes but
-- the player never sees it update. No player-index argument: cash/fuel is this machine's own campaign
-- wallet, not a per-character resource (in co-op each machine has its own wallet already).
function Ess.Player.giveCash(n)
    local ok = Ess.Safe.quiet(MrxPmc.AddCashQty, n, false, "[Ess]")
    return ok and true or false
end

function Ess.Player.giveFuel(n)
    local ok = Ess.Safe.quiet(MrxPmc.AddFuelQty, n)
    return ok and true or false
end

-- Ess.Player.pose(i) -> x, y, z, yaw, uChar, uPlayerSlot
-- One-stop "where is this player, facing which way" -- promoted from uilib's private pose() helper.
-- yaw defaults to 0 if unreadable; x/y/z are nil if there's no character at all (e.g. i=1 outside co-op).
function Ess.Player.pose(i)
    local char = Ess.Player.character(i)
    local player = Ess.Player.slot(i)
    if not char then return nil, nil, nil, 0, nil, player end
    local ok, px, py, pz = Ess.Safe.quiet(Object.GetPosition, char)
    if not ok or not px then return nil, nil, nil, 0, char, player end
    local yaw = 0
    local oky, yv = Ess.Safe.quiet(Object.GetYaw, char)
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
    local ok, x, y, z, g = Ess.Safe.quiet(Player.GetTargetUnderReticle, slot)
    if not ok then return nil end
    return g, x, y, z
end

-- Ess.Player.viewYaw(i) -> yaw, bFromReticle
-- The yaw the player is LOOKING along -- as opposed to Ess.Player.pose's 4th return, which is the CHEST/
-- BODY yaw. These are genuinely different: stand still and swing the mouse and the view rotates while the
-- body does not (measured live at up to 111 degrees apart; running forward re-aligns them). So "in front of
-- the player" has two legitimate meanings, and this is the one a player perceives.
--
-- Derived from the reticle hit point (Player.GetTargetUnderReticle) turned into a bearing by Ess.Math.angleTo.
-- NEVER returns nil while you have a character: if the reticle has no usable hit -- aiming at open SKY is
-- the known case, and a hit closer than MIN_VIEW_DIST gives a junk bearing -- it FALLS BACK to the body yaw
-- and returns false as the second value. Callers that care can branch on that; callers that don't still get
-- a usable yaw, which is what makes the opt-in flags built on this safe by construction.
local MIN_VIEW_DIST = 3   -- a reticle hit right on top of you yields a meaningless bearing
function Ess.Player.viewYaw(i)
    local px, py, pz, bodyYaw = Ess.Player.pose(i)
    if not px then return nil, false end
    local _, rx, _, rz = Ess.Player.targetUnderReticle(i)
    if rx and rz and Ess.Math.dist2D(px, pz, rx, rz) >= MIN_VIEW_DIST then
        return Ess.Math.angleTo(px, pz, rx, rz), true
    end
    return bodyYaw or 0, false
end

-- Ess.Player.viewPoint(nDist, nHeight, i) -> x, y, z | nil
-- A world point nDist ahead of where the player is LOOKING, nHeight above the ground there.
--
-- This is the engine's own answer to the problem Ess.Player.viewYaw works around. viewYaw DERIVES a look
-- bearing from the reticle hit and falls back to the body yaw when there is no usable hit (aiming at open
-- sky); Pg.FindPointFromCamera uses the camera vector directly, so it never degrades and needs no reticle.
-- Prefer this over `pose()` + Ess.Math.pointAhead whenever you mean "in front of the player" in the sense a
-- PLAYER means it. Ess.Object.spawnAhead still uses the body yaw by design -- the two are different
-- questions, and were measured 135 degrees apart during verification.
--
-- Live-verified 2026-07-26 from two positions, with the body 135 degrees off the view: the returned point's
-- bearing matched Ess.Player.viewYaw to within a degree both times.
--
-- Three things worth knowing, all measured:
--
--   * nDist is measured FROM THE CAMERA, which sits ~3 units behind the character. The achieved distance
--     from the PLAYER is therefore a flat 3 less than requested, at every scale -- 25->22, 100->97,
--     400->397, 1600->1597. A constant offset, not a percentage. This wrapper does not "correct" it, since
--     the raw value is what shipped scripts pass and matching them keeps behaviour predictable; just don't
--     expect exactly nDist at short range, where 3 units is a large fraction of it.
--
--   * NO OBSTACLE TEST. The point is not raycast against geometry -- a request for 1600 units achieved 1597
--     straight through a building. Y comes out at ground level for that horizontal position (a car spawned
--     at nHeight=0 measured 0.52 above ground), so it samples terrain height, but it will happily hand you
--     a point inside a wall. Check it before spawning something solid there.
--
--   * The native takes a third argument that every shipped script passes as -1. It has no observable effect
--     whatsoever: -1/0/1/2/3/4/8/16/-2 and nil all returned byte-identical points, over open ground and
--     while facing a building. This passes -1 to match the corpus rather than inventing a meaning for it.
function Ess.Player.viewPoint(nDist, nHeight, i)
    local uChar = Ess.Player.character(i or 0)
    if not uChar then return nil end
    local ok, x, y, z = Ess.Safe.quiet(Pg.FindPointFromCamera,
                                       nDist or 20, nHeight or 0, -1, uChar)
    if ok and x then return x, y, z end
    return nil
end

-- Ess.Player.removeBoundaries() -- CONFIRMED (wiki/snippets.md): clears every out-of-bounds volume
-- currently active, for every connected player at once (co-op safe by construction -- iterates
-- Player.GetAllPlayers(), not a single index, so this takes no `i` argument). Only clears what's active
-- RIGHT NOW -- doesn't disable the boundary system itself, so the game's own scripts can still add a new
-- one later (e.g. on a mission/area transition). Runtime-only, matching Ess.Object.setInvincible-style
-- "re-added each load" boundary volumes documented elsewhere in this project.
function Ess.Player.removeBoundaries()
    local ok, players = Ess.Safe.quiet(Player.GetAllPlayers)
    if not ok or type(players) ~= "table" then return 0 end
    local n = 0
    for _, p in ipairs(players) do
        if Ess.Safe.quiet(Player.RemoveAllBoundary, p) then n = n + 1 end
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
    Ess.Safe.quiet(Player.SetInputEnabled, p, bOn and true or false)
end

-- Ess.Player.rumble(i, fLength) -- CONFIRMED (wiki/namespaces/pg.md): Pg.Rumble(uCharacterGuid, fLength)
-- (`resident/mrxactionhijack.lua`, real values 0.15-ish seconds). Controller haptic feedback -- the common
-- "juice" a damage/impact/pickup moment wants -- resolved through Ess.Player.character(i) rather than
-- taking a raw guid, matching every other function in this file.
function Ess.Player.rumble(i, fLength)
    local char = Ess.Player.character(i)
    if not char then return end
    Ess.Safe.quiet(Pg.Rumble, char, fLength or 0.2)
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
    Ess.Safe.quiet(MrxUtil.TeleportHeroesToLocations, locs, onDone or function() end)
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

-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Economy READ + session shape. All live-probed 2026-07-26 against a loaded save.
--
-- Deliberately NOT a wrapper per native: this file's whole point is to collapse the getter sprawl, so what
-- follows fills genuine capability GAPS rather than mirroring `Player.*` one-for-one. The gap that motivated
-- it: giveCash/giveFuel could WRITE the economy but nothing here could READ it.
-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────

-- Ess.Player.cash() -> n | nil -- current cash. Global to the session, not per-slot (the native takes no
-- argument). Pairs with giveCash, which stays the correct way to CHANGE it: `Player.SetCash` exists and is
-- tempting, but it's the raw setter and skips the HUD refresh MrxPmc.AddCashQty triggers -- the same trap
-- already documented against the fuel/cash setters at the top of this file.
function Ess.Player.cash()
    local ok, n = Ess.Safe.quiet(Player.GetCash)
    if ok then return n end
    return nil
end

-- Ess.Player.fuel() -> nCurrent, nCapacity -- both values, because "is the tank full" and "how low am I"
-- are the two things anyone asks and the capacity is not a constant across saves/upgrades.
-- Measured on a loaded save: 300 / 300.
function Ess.Player.fuel()
    local ok,  cur = Ess.Safe.quiet(Player.GetFuel)
    local ok2, cap = Ess.Safe.quiet(Player.GetFuelCapacity)
    return (ok and cur or nil), (ok2 and cap or nil)
end

-- Ess.Player.isCoop() -> bool -- true only in an actual co-op session.
function Ess.Player.isCoop()
    local ok, b = Ess.Safe.quiet(Player.IsCoopMultiplayer)
    return (ok and b) and true or false
end

-- Ess.Player.count() -> n -- how many player slots are actually in the session (1 in single-player).
function Ess.Player.count()
    local ok, n = Ess.Safe.quiet(Player.GetCurrentPlayers)
    if ok then return n end
    return 1
end

-- Ess.Player.joined(i) -> bool -- is slot i (0 local, 1 co-op partner) actually occupied?
--
-- ⚠ THE REASON THIS WRAPPER EXISTS. The native `Player.IsJoined` takes a numeric SLOT INDEX, while every
-- other Player predicate in this engine takes a player GUID. Handing it a guid does not error -- it returns
-- nil, which is falsy, so `if Player.IsJoined(Ess.Player.slot(1))` reads as "never joined" forever and looks
-- like correct code. Live-confirmed: IsJoined(0)=true, IsJoined(1)=false, IsJoined(<guid>)=nil.
--
-- Note `Player.GetPlayer(1)` and `Player.GetSecondaryPlayer()` both hand back a real-looking slot handle
-- (40000015) even when nobody is in it, so a non-nil slot guid is NOT evidence of a second player. This, or
-- `Ess.Player.character(1) ~= nil`, is the honest test.
function Ess.Player.joined(i)
    local ok, b = Ess.Safe.quiet(Player.IsJoined, (i == 1) and 1 or 0)
    return (ok and b) and true or false
end

-- Ess.Player.name(i) -> sName | nil -- the slot's profile name ("player0" on a local single-player save).
function Ess.Player.name(i)
    local s = Ess.Player.slot(i)
    if not s then return nil end
    local ok, n = Ess.Safe.quiet(Player.GetName, s)
    if ok then return n end
    return nil
end
