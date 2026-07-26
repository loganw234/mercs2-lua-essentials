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

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE THREE ICON VOCABULARIES, AND WHY A KIND HAS TO NAME ALL THREE
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- The three marking surfaces do NOT share an icon namespace. The same objective is "HUD_objective_destroy"
-- in the world, "objective_destroy" on the radar and "icon_destroy_1_mc" on the PDA, and each name is
-- validated against a different fixed table in mrxutil.lua (tObjWorldMarkers / tObjRadarMaker /
-- tObjPdaMarker) by a different lookup function. Nothing in the engine relates them; the correspondence is
-- purely by naming convention, which is why it has to be written down somewhere, and this is that place.
--
-- This table used to carry only `rdr` and `wld`, inherited from ContractFramework.lua, and every kind was
-- hardcoded to "icon_yellow_mc" on the PDA. So marking something as a DESTROY objective produced a destroy
-- icon in the world, a destroy icon on the radar, and an anonymous yellow dot on the map -- the three layers
-- disagreed for every kind. `pda` closes that, and `outpost` is added because all three tables have it.
--
-- Ess.Mark.KINDS is the public name for this: iterate it to discover what kinds exist rather than guessing.
-- Any name here is guaranteed present in all three engine tables (verified against mrxutil.lua 2026-07-26),
-- so a kind can never half-resolve.
local OBJ_ICONS = {
    action      = { rdr = "objective_action",      wld = "HUD_objective_action",      pda = "icon_action_1_mc" },
    destroy     = { rdr = "objective_destroy",     wld = "HUD_objective_destroy",     pda = "icon_destroy_1_mc" },
    defend      = { rdr = "objective_defend",      wld = "HUD_objective_defend",      pda = "icon_defend_1_mc" },
    verify      = { rdr = "objective_verify",      wld = "HUD_objective_verify",      pda = "icon_verify_1_mc" },
    deliverable = { rdr = "objective_deliverable", wld = "HUD_objective_deliverable", pda = "icon_deliverable_1_mc" },
    outpost     = { rdr = "objective_outpost",     wld = "HUD_objective_outpost",     pda = "icon_outpost_1_mc" },
    -- The generic marker. MiniMap_Icon_Symbol_Yellow is in BOTH the world and radar tables, so those two
    -- line up despite the naming being the least consistent of the lot. The PDA leg deliberately does NOT
    -- use icon_yellow_mc, its apparent counterpart: that name is registered but DRAWS NOTHING (verified
    -- against three other icons side by side), so pairing it here would make `generic` the one kind that
    -- silently vanishes on the map. icon_action_1_mc is the generic objective icon that renders.
    generic     = { rdr = "MiniMap_Icon_Symbol_Yellow", wld = "MiniMap_Icon_Symbol_Yellow", pda = "icon_action_1_mc" },
}
-- `destination` predates this table and is used by Ess.Mark.zone's default and by existing consumers, so it
-- stays as an alias rather than a rename -- same table identity, so it picks up `pda` for free.
OBJ_ICONS.destination = OBJ_ICONS.deliverable

-- The per-faction sets, which line up the same way. Kept separate from OBJ_ICONS because the world layer is
-- incomplete: there is no HUD_faction_PMC or HUD_faction_VZ (PMC borrows its HQ icon, VZ has no world icon
-- at all and falls back to generic). Radar and PDA have all seven.
local FACTION_ICONS = {
    gr  = { rdr = "MiniMap_Icon_Faction_GR",  wld = "HUD_faction_GR", pda = "icon_gr_mc" },
    oc  = { rdr = "MiniMap_Icon_Faction_OC",  wld = "HUD_faction_OC", pda = "icon_oc_mc" },
    pr  = { rdr = "MiniMap_Icon_Faction_PR",  wld = "HUD_faction_PR", pda = "icon_pr_mc" },
    an  = { rdr = "MiniMap_Icon_Faction_AN",  wld = "HUD_faction_AN", pda = "icon_an_mc" },
    ch  = { rdr = "MiniMap_Icon_Faction_CH",  wld = "HUD_faction_CH", pda = "icon_ch_mc" },
    pmc = { rdr = "MiniMap_Icon_Faction_PMC", wld = "HUD_HQ_PMC",     pda = "icon_pmc_mc" },
    vz  = { rdr = "MiniMap_Icon_Faction_VZ",  wld = nil,              pda = "icon_vz_mc" },
}
for k, v in pairs(FACTION_ICONS) do OBJ_ICONS["faction_" .. k] = v end

-- Ess.Mark.KINDS -- the public, iterable kind vocabulary. Values are the per-layer texture triples, so
-- Ess.Mark.KINDS.destroy.pda is a legal answer to "what icon does a destroy objective use on the map".
Ess.Mark.KINDS = OBJ_ICONS

-- Resolve a kind name to its triple, falling back to a caller-chosen default. Centralised so object() and
-- zone() cannot drift apart on what an unknown kind means.
local function iconsFor(sKind, sDefault)
    return OBJ_ICONS[sKind] or OBJ_ICONS[sDefault] or OBJ_ICONS.action
end

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- CHOOSING SURFACES, AND COLOUR
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- A `kind` names all three layers at once, which is the common case, but it is a DEFAULT and not a
-- straitjacket. Three levels of control, narrowing:
--
--   1. WHICH SURFACES     opts.radar / opts.pda / opts.world / opts.disc -- each independent, all opt-OUT
--                         except disc. `{pda = false}` marks radar and world only.
--   2. WHICH ICON PER     opts.radarIcon / opts.pdaIcon / opts.worldIcon each override just that layer,
--      SURFACE            so you can take kind="destroy" and still show a faction icon on the map.
--   3. NO PRESET AT ALL   Ess.Raw.Mark.radar / .pda / .world / .worldDisc are fully independent calls.
--
-- COLOUR IS NOT AVAILABLE ON ALL THREE -- and this asymmetry is the one thing here most likely to be
-- mistaken for a bug. opts.rgb tints the radar dot (Hud.Radar:AddObjective takes nR/nG/nB) and the in-world
-- icon and ring (Marker.AddBlip/AddDisc take r,g,b), and arbitrary colours work on both: verified live
-- 2026-07-26 with three markers identical but for rgb, which rendered red, green and blue on the minimap
-- and in the world.
--
-- The PDA map has NO COLOUR PARAMETER AT ALL. AddMapBlip takes thirteen arguments and not one of them is
-- rgb, so the same three markers were visually identical on the map. A PDA blip's only colour axis is which
-- texture you pick -- which is why the faction kinds matter: on the map, `faction_gr` IS the colour. Use
-- opts.pdaIcon to colour that layer (confirmed live: kind="destroy" with pdaIcon="icon_gr_mc" shows a
-- destroy icon on radar and in the world, and the guerrilla icon on the map).
local function pick(sOverride, sFromKind)
    if type(sOverride) == "string" and sOverride ~= "" then return sOverride end
    return sFromKind
end

-- Ess.Mark.object(uGuid, opts) -> handle
-- opts.radar/opts.pda/opts.world each default true (opt OUT, not opt in -- matches ContractFramework's
-- all-three-by-default convention; pass radar=true,pda=true,world=false to match WaveDefense's instead).
-- opts.world is the floating in-world icon; opts.disc (default OFF) adds a ground ring around the object
-- too (opts.radius default 15, opts.discAlpha its fill). opts.kind picks the icon set (see Ess.Mark.KINDS,
-- default "action"); opts.radarIcon/pdaIcon/worldIcon override a single layer; opts.rgb tints the radar and
-- world layers but NOT the PDA; opts.label names the PDA blip; opts.size/opts.dist tune the floating icon.
function Ess.Mark.object(uGuid, opts)
    opts = opts or {}
    local ic = iconsFor(opts.kind, "action")
    local h = { uGuid = uGuid }
    if opts.radar ~= false then
        h.radarName = Ess.Raw.Mark.radar(uGuid, pick(opts.radarIcon, ic.rdr), opts.rgb)
    end
    if opts.pda ~= false then
        h.pdaName = Ess.Raw.Mark.pda(uGuid, pick(opts.pdaIcon, ic.pda), opts.label)
    end
    if opts.world ~= false then
        h.worldHandle = Ess.Raw.Mark.world(uGuid, pick(opts.worldIcon, ic.wld), opts.rgb, opts.size, opts.dist)
    end
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
    local ic = iconsFor(opts.kind, "destination")
    local anchor = Ess.Object.spawn("TinyGeometry", x, y, z)
    if not anchor then return nil end
    local h = { anchor = anchor }
    if opts.world ~= false then
        h.discHandle = Ess.Raw.Mark.worldDisc(anchor, radius, opts.rgb, opts.discAlpha or opts.alpha)
    end
    if opts.icon then
        h.worldHandle = Ess.Raw.Mark.world(anchor, pick(opts.worldIcon, ic.wld), opts.rgb, opts.size, opts.dist)
    end
    if opts.radar ~= false then
        h.radarName = Ess.Raw.Mark.radar(anchor, pick(opts.radarIcon, ic.rdr), opts.rgb)
    end
    if opts.pda ~= false then
        h.pdaName = Ess.Raw.Mark.pda(anchor, pick(opts.pdaIcon, ic.pda), opts.label)
    end
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
    if handle.anchor then Ess.Safe.quiet(Object.Remove, handle.anchor) end
end
