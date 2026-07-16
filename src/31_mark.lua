-- Ess/31_mark.lua -- Ess.Mark: opts-driven object/zone marking -- the motivating example for the whole
-- tiered design. ContractFramework.lua's `mark()` marks all three surfaces unconditionally; WaveDefense's
-- `addEnemyBlip` deliberately marks radar+PDA only, skipping the world icon (CONFIRMED intentional, not a
-- gap: not every marked thing should also clutter the world with a floating icon). The correct primitive
-- isn't "always mark all three," it's three independent opt-out toggles -- both existing call sites become
-- this same function with different opts, not two different implementations.
--
-- API:
--   Ess.Mark.object(uGuid, opts) -> handle     opts: radar=true, pda=true, world=true, kind=, rgb=
--   Ess.Mark.zone(x, y, z, radius, opts) -> handle
--   Ess.Mark.clear(handle)

local Ess = _G.Ess
Ess.Mark = Ess.Mark or {}

-- objective marker icon sets, taken straight from ContractFramework.lua's OBJ_ICONS (the base game's own
-- MrxTaskObjective family: radar = "objective_*", in-world = "HUD_objective_*").
local OBJ_ICONS = {
    destroy     = { rdr = "objective_destroy",     wld = "HUD_objective_destroy" },
    verify      = { rdr = "objective_verify",      wld = "HUD_objective_verify" },
    defend      = { rdr = "objective_defend",      wld = "HUD_objective_defend" },
    action      = { rdr = "objective_action",      wld = "HUD_objective_action" },
    destination = { rdr = "objective_deliverable", wld = "HUD_objective_deliverable" },
}

-- Ess.Mark.object(uGuid, opts) -> handle
-- opts.radar/opts.pda/opts.world each default true (opt OUT, not opt in -- matches ContractFramework's
-- all-three-by-default convention; pass radar=true,pda=true,world=false to match WaveDefense's instead).
-- opts.kind picks the icon set (destroy/verify/defend/action/destination, default "action").
function Ess.Mark.object(uGuid, opts)
    opts = opts or {}
    local ic = OBJ_ICONS[opts.kind] or OBJ_ICONS.action
    local h = { uGuid = uGuid }
    if opts.radar ~= false then h.radarName = Ess.Raw.Mark.radar(uGuid, ic.rdr, opts.rgb) end
    if opts.pda ~= false then h.pdaName = Ess.Raw.Mark.pda(uGuid, "icon_yellow_mc") end
    if opts.world ~= false then h.worldHandle = Ess.Raw.Mark.world(uGuid, ic.wld, opts.rgb) end
    return h
end

-- Ess.Mark.zone(x, y, z, radius, opts) -> handle|nil
-- Spawns a TinyGeometry anchor (safe mid-gameplay, per Ess.Camera's own documented caveat) and marks it
-- as a "destination" -- ContractFramework.lua's markZone, generalized with the same opts shape as object().
-- opts.world (default true) draws the ground ring (Marker.AddDisc); opts.radar/opts.pda (default true)
-- add the round-radar/PDA destination blip on the SAME anchor.
function Ess.Mark.zone(x, y, z, radius, opts)
    opts = opts or {}
    local ok, anchor = pcall(Pg.Spawn, "TinyGeometry", x, y, z)
    if not ok or not anchor then return nil end
    local h = { anchor = anchor }
    if opts.world ~= false then
        h.discHandle = Ess.Raw.Mark.worldDisc(anchor, radius, opts.rgb, opts.alpha)
    end
    if opts.radar ~= false then h.radarName = Ess.Raw.Mark.radar(anchor, OBJ_ICONS.destination.rdr, opts.rgb) end
    if opts.pda ~= false then h.pdaName = Ess.Raw.Mark.pda(anchor, "icon_yellow_mc") end
    return h
end

-- Ess.Mark.clear(handle) -- tears down every surface a handle actually used, plus the zone anchor prop
-- if there was one. Safe to call on a partial handle (any field missing/nil is just skipped).
function Ess.Mark.clear(handle)
    if not handle then return end
    if handle.radarName then Ess.Raw.Mark.removeRadar(handle.radarName) end
    if handle.pdaName then Ess.Raw.Mark.removePda(handle.pdaName) end
    if handle.worldHandle then Ess.Raw.Mark.removeWorld(handle.worldHandle) end
    if handle.discHandle then Ess.Raw.Mark.removeWorld(handle.discHandle) end
    if handle.anchor then pcall(Object.Remove, handle.anchor) end
end
