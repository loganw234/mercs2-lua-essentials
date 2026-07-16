-- Ess/63_sandbox_raw.lua -- Ess.Raw.Sandbox: the provider registry + the save-gate primitive underneath
-- Ess.Sandbox. Write your own provider (a {snapshot=, apply=, restore=} table) for anything not covered
-- by the Core tier's built-ins (layers/economy/supports/relations).
--
-- API:
--   Ess.Raw.Sandbox.register(name, { apply = fn(id, opts), restore = fn(id) })
--   Ess.Raw.Sandbox.gateSaves() / .ungateSaves()

local Ess = _G.Ess
Ess.Raw = Ess.Raw or {}
Ess.Raw.Sandbox = Ess.Raw.Sandbox or {}
Ess.Raw.Sandbox._providers = Ess.Raw.Sandbox._providers or {}

function Ess.Raw.Sandbox.register(name, provider)
    Ess.Raw.Sandbox._providers[name] = provider
end

-- ---- save gate: delegates to the ONE shared gate (Ess.Save, 24_save.lua). WHY IT MATTERS: a savegame
-- landing mid-sandbox (isolated economy at $0, factions mid-hostile-swap, a layer mid-transition) would
-- bake that transient state into the save -- confirmed real risk in WaveDefense.lua's own comments ("the
-- death -> medevac flow fires a savegame in that window; if it lands at $0 ... their money is gone").
--
-- These forward to Ess.Save with a single generic holder key. Ess.Sandbox.begin()/.finish() (63_sandbox.lua)
-- do NOT use these -- they hold Ess.Save keyed by each sandbox's own id, so concurrent sandboxes gate
-- independently. This pair exists only for a Raw-tier provider author who wants to gate saves by hand
-- without going through the full Sandbox lifecycle. Because everything now routes through the one
-- never-uninstalled Ess.Save wrap, no gate-user can ever clobber another's -- the old Layers/Sandbox
-- ordering hazard (two things each owning Pg.SaveGame) is gone by construction.
function Ess.Raw.Sandbox.gateSaves()   Ess.Save.gate("Ess.Raw.Sandbox")   end
function Ess.Raw.Sandbox.ungateSaves() Ess.Save.ungate("Ess.Raw.Sandbox") end
