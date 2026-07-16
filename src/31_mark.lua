-- Ess/31_mark.lua -- Ess.Mark: opts-driven object/zone marking -- the motivating example for the whole
-- tiered design. ContractFramework.lua's `mark()` marks all three surfaces unconditionally; WaveDefense's
-- `addEnemyBlip` deliberately marks radar+PDA only, skipping the world icon (CONFIRMED intentional, not a
-- gap: not every marked thing should also clutter the world with a floating icon). The correct primitive
-- isn't "always mark all three," it's three independent opt-out toggles -- both existing call sites become
-- this same function with different opts, not two different implementations.
--
-- API:
--   Ess.Mark.object(uGuid, opts) -> handle
--       opts: radar=true, pda=true, world=true (floating icon), disc=false (ground ring), kind=, rgb=,
--             radius= (disc), discAlpha=, size=/dist= (floating-icon size + draw-distance)
--   Ess.Mark.zone(x, y, z, radius, opts) -> handle
--       opts: world=true (ground ring), radar=true, pda=true, icon=false (ALSO a floating icon), kind=,
--             rgb=, discAlpha=, size=/dist= (floating-icon size + draw-distance)
--   Ess.Mark.clear(handle)
--
-- Every surface (round-radar, PDA blip, ground ring, floating in-world icon) is an independent opt so ONE
-- call covers any combination -- the design goal is that a consumer never has to drop to Ess.Raw.Mark and
-- hand-assemble a multi-surface marker just because it wants, say, a ground ring AND a floating icon on the
-- same anchor (the exact combination MissionForge needed, which motivated the `icon`/`disc`/size/dist opts).

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
-- opts.world is the floating in-world icon; opts.disc (default OFF) adds a ground ring around the object
-- too (opts.radius default 15, opts.discAlpha its fill). opts.kind picks the icon set (destroy/verify/
-- defend/action/destination, default "action"); opts.size/opts.dist tune the floating icon's look.
function Ess.Mark.object(uGuid, opts)
    opts = opts or {}
    local ic = OBJ_ICONS[opts.kind] or OBJ_ICONS.action
    local h = { uGuid = uGuid }
    if opts.radar ~= false then h.radarName = Ess.Raw.Mark.radar(uGuid, ic.rdr, opts.rgb) end
    if opts.pda ~= false then h.pdaName = Ess.Raw.Mark.pda(uGuid, "icon_yellow_mc") end
    if opts.world ~= false then h.worldHandle = Ess.Raw.Mark.world(uGuid, ic.wld, opts.rgb, opts.size, opts.dist) end
    if opts.disc then h.discHandle = Ess.Raw.Mark.worldDisc(uGuid, opts.radius or 15, opts.rgb, opts.discAlpha) end
    return h
end

-- Ess.Mark.zone(x, y, z, radius, opts) -> handle|nil
-- Spawns a TinyGeometry anchor (via the guarded Ess.Object.spawn -- a blank template would hard-crash, and
-- this is the one create-verb that guards it) and marks it. opts.world (default true) draws the ground ring
-- (Marker.AddDisc, opts.discAlpha its fill); opts.radar/opts.pda (default true) add the round-radar/PDA blip
-- on the SAME anchor; opts.icon (default OFF) ALSO drops a floating in-world icon on it. opts.kind picks the
-- icon set for the radar blip AND the floating icon (default "destination"); opts.size/opts.dist tune the
-- floating icon. The zone OWNS its anchor, so Ess.Mark.clear removes the prop for you.
function Ess.Mark.zone(x, y, z, radius, opts)
    opts = opts or {}
    local ic = OBJ_ICONS[opts.kind] or OBJ_ICONS.destination
    local anchor = Ess.Object.spawn("TinyGeometry", x, y, z)
    if not anchor then return nil end
    local h = { anchor = anchor }
    if opts.world ~= false then
        h.discHandle = Ess.Raw.Mark.worldDisc(anchor, radius, opts.rgb, opts.discAlpha or opts.alpha)
    end
    if opts.icon then h.worldHandle = Ess.Raw.Mark.world(anchor, ic.wld, opts.rgb, opts.size, opts.dist) end
    if opts.radar ~= false then h.radarName = Ess.Raw.Mark.radar(anchor, ic.rdr, opts.rgb) end
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
