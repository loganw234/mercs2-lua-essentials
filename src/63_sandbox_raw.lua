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
Ess.Raw.Sandbox._gated = Ess.Raw.Sandbox._gated or false
Ess.Raw.Sandbox._installed = Ess.Raw.Sandbox._installed or false

function Ess.Raw.Sandbox.register(name, provider)
    Ess.Raw.Sandbox._providers[name] = provider
end

-- ---- save gate: exactly the pattern WaveDefense.lua hand-rolled at its own top level (a direct
-- Pg.SaveGame reassignment, guarded by "not already wrapped"), rebuilt on top of Ess.Override.wrap
-- instead of a second hand-rolled copy -- installed ONCE, toggled by a shared boolean from then on so
-- repeated begin/finish calls never stack another layer of wrapping.
local function installSaveGate()
    if Ess.Raw.Sandbox._installed then return end
    if type(Pg) ~= "table" or type(Pg.SaveGame) ~= "function" then return end
    local ok = Ess.Override.wrap(Pg, "SaveGame", function(orig, ...)
        if Ess.Raw.Sandbox._gated then
            Ess.Log("Sandbox: savegame suppressed (a sandbox is active)")
            return
        end
        local a, b, c, d = orig(...)
        return a, b, c, d
    end)
    if ok then Ess.Raw.Sandbox._installed = true end
end

-- Ess.Raw.Sandbox.gateSaves() -- WHY THIS MATTERS: a savegame landing mid-sandbox (isolated economy at
-- $0, factions mid-hostile-swap, a layer mid-transition) would bake that transient state into the save.
-- Confirmed real risk in WaveDefense.lua's own comments ("the death -> medevac flow fires a savegame in
-- that window; if it lands at $0 ... their money is gone").
--
-- ⚠ installSaveGate() below installs LAZILY (first-ever call, then never again -- see `_installed`) --
-- see 64_layers.lua's own header for a narrow but real ordering hazard this creates if a mod mixes direct
-- Ess.Layers calls with Ess.Sandbox in the same session. Prefer Ess.Sandbox's "layers" provider over
-- calling Ess.Layers directly when both might be in play.
function Ess.Raw.Sandbox.gateSaves()
    installSaveGate()
    Ess.Raw.Sandbox._gated = true
end

function Ess.Raw.Sandbox.ungateSaves()
    Ess.Raw.Sandbox._gated = false
end
