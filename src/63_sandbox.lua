-- Ess/63_sandbox.lua -- Ess.Sandbox: begin/finish an ephemeral, guaranteed-restored mode across every
-- registered provider at once, with saves gated for the whole duration.
--
-- The single biggest unifying idea in this whole design (FEATURE_SHEET.md): LayerFw's begin/add/remove/
-- swap/expect/finish (snapshot -> apply -> GUARANTEED restore, save-gated so a crash mid-mode just
-- leaves the pre-mode vanilla state) and WaveDefense.lua's independently-built cash isolation
-- (isolateSupports/restoreSupports, restoreEconomy, its own Pg.SaveGame wrap) are the SAME pattern
-- applied to two different resources, written twice -- with WaveDefense's copy duplicating the save-gate
-- LayerFw already solved generically. This is one implementation, one save-gate, four built-in providers.
--
-- API:
--   Ess.Sandbox.begin(id, providerNames, opts) -> ok
--   Ess.Sandbox.finish(id)
--   Ess.Sandbox.isActive(id) -> bool
--
-- Built-in providers: "layers" (adopts LayerFw if deployed alongside Ess -- existence-checked, never a
-- hard dependency, exactly like the 99_adopt.lua aliases), "economy" (cash isolation), "supports"
-- (support-menu isolation), "relations" (thin wrapper over Ess.Relations, reads opts.relations).

local Ess = _G.Ess
Ess.Sandbox = Ess.Sandbox or {}
Ess.Sandbox._active = Ess.Sandbox._active or {}
Ess.Sandbox._nActive = Ess.Sandbox._nActive or 0

-- ============================================================
-- Built-in provider: relations -- opts.relations is the {a,b,set} pairs list to pass straight through
-- to Ess.Relations.apply/restore, keyed by the SAME sandbox id so they tear down together.
-- ============================================================
Ess.Raw.Sandbox.register("relations", {
    apply = function(id, opts)
        if opts and opts.relations then Ess.Relations.apply(id, opts.relations) end
    end,
    restore = function(id)
        Ess.Relations.restore(id)
    end,
})

-- ============================================================
-- Built-in provider: economy -- CONFIRMED pattern (WaveDefense.lua's W.savedCash/restoreEconomy): bank
-- the campaign wallet to 0 (optionally to a fixed opts.startCash instead), restore it exactly on finish.
-- Persisted via Ess.SaveVar so a mid-session inspection can see it, though unlike WaveDefense's own
-- single-global-key version, this doesn't auto-recover a STRANDED deduction from a crashed prior session
-- (Loader.SaveVar/LoadVar has no key-enumeration API, so there's no general way to discover an arbitrary
-- caller's sandbox id at boot to check it) -- a real, honest scope reduction versus the WaveDefense-
-- specific original, not an oversight.
-- ============================================================
import("MrxPmc")
local ECON_NS = "EssSandboxEconomy"
Ess.Raw.Sandbox.register("economy", {
    apply = function(id, opts)
        local sv = Ess.SaveVar.ns(ECON_NS)
        local ok, cash = pcall(MrxPmc.GetCashQty)
        cash = (ok and cash) or 0
        sv:set(id .. "_saved", cash)
        pcall(MrxPmc.AddCashQty, -cash, false, "[Ess.Sandbox]")
        if opts and opts.startCash then pcall(MrxPmc.AddCashQty, opts.startCash, false, "[Ess.Sandbox]") end
    end,
    restore = function(id)
        local sv = Ess.SaveVar.ns(ECON_NS)
        local saved = sv:get(id .. "_saved", nil)
        if saved == nil then return end
        local ok, cur = pcall(MrxPmc.GetCashQty)
        cur = (ok and cur) or 0
        pcall(MrxPmc.AddCashQty, saved - cur, false, "[Ess.Sandbox]")
        sv:set(id .. "_saved", nil)
    end,
})

-- ============================================================
-- Built-in provider: supports -- CONFIRMED pattern (WaveDefense.lua's isolateSupports/restoreSupports):
-- snapshot the HUD support quick-select menu's current items, wipe it down to the transport default,
-- restore exactly what was there on finish. Requires MrxGuiBase.GetWidgetByNameAndOwner to find the raw
-- "Support Menu" widget; if that's unavailable this just no-ops (existence-checked, not a hard failure).
-- ============================================================
Ess.Raw.Sandbox._supportSnaps = Ess.Raw.Sandbox._supportSnaps or {}
local function supportWidget()
    local okp, p = pcall(Player.GetLocalPlayer)
    if not okp or not p then return nil end
    pcall(function() import("MrxGuiBase") end)
    local G = _G.MrxGuiBase
    if not (G and G.GetWidgetByNameAndOwner) then return nil end
    local okw, w = pcall(G.GetWidgetByNameAndOwner, "Support Menu", p)
    if okw then return w end
    return nil
end
Ess.Raw.Sandbox.register("supports", {
    apply = function(id)
        local w = supportWidget()
        local saved = {}
        if w and w.CustomData and w.CustomData.tItemList then
            for _, it in ipairs(w.CustomData.tItemList) do
                saved[#saved + 1] = { sName = it.sName, sIcon = it.sIcon, oSupport = it.oSupport }
            end
        end
        Ess.Raw.Sandbox._supportSnaps[id] = saved
        if w and w.RemoveAll then pcall(function() w:RemoveAll() end) end
    end,
    restore = function(id)
        local w = supportWidget()
        if w and w.RemoveAll then pcall(function() w:RemoveAll() end) end
        for _, it in ipairs(Ess.Raw.Sandbox._supportSnaps[id] or {}) do
            pcall(function()
                Hud.SupportMenu:AddItem({ vPlayer = nil, sName = it.sName, sIcon = it.sIcon,
                    oSupport = it.oSupport, bDontNetSync = true })
            end)
        end
        Ess.Raw.Sandbox._supportSnaps[id] = nil
    end,
})

-- ============================================================
-- Built-in provider: layers -- adopts LayerFw (confirmed API: L.begin(sId) -> bool, L.finish(fCb))
-- IF it's deployed alongside Ess in this install, existence-checked exactly like the 99_adopt.lua
-- aliases -- never a hard dependency. LayerFw does its OWN internal save-gating too (separate from this
-- file's gateSaves/ungateSaves); the two compose fine since each only ever restores Pg.SaveGame back to
-- whatever IT saw as "original" at the point it wrapped, chaining correctly either order.
-- ============================================================
Ess.Raw.Sandbox.register("layers", {
    apply = function(id)
        if not _G.LayerFw then
            Ess.Log("Sandbox: 'layers' provider requested but LayerFw (_G.LayerFw) isn't deployed in this install")
            return
        end
        _G.LayerFw.begin(id)
    end,
    restore = function(id)
        if not _G.LayerFw then return end
        _G.LayerFw.finish()
    end,
})

-- ============================================================
-- Ess.Sandbox.begin(id, providerNames, opts) -> ok
-- Gates saves (once, even across nested/concurrent sandboxes -- tracked by a simple active-count),
-- then calls apply(id, opts) on each named provider in order. A provider that errors is logged and
-- skipped -- it's simply not added to this id's active-provider list, so finish() won't try to restore
-- something that never successfully applied.
-- ============================================================
function Ess.Sandbox.begin(id, providerNames, opts)
    if Ess.Sandbox._active[id] then
        Ess.Log("Sandbox.begin: '" .. tostring(id) .. "' is already active")
        return false
    end
    opts = opts or {}
    Ess.Raw.Sandbox.gateSaves()
    Ess.Sandbox._nActive = Ess.Sandbox._nActive + 1
    local applied = {}
    for _, name in ipairs(providerNames or {}) do
        local p = Ess.Raw.Sandbox._providers[name]
        if p and p.apply then
            local ok, err = pcall(p.apply, id, opts)
            if ok then
                applied[#applied + 1] = name
            else
                Ess.Log("Sandbox.begin: provider '" .. name .. "' apply error: " .. tostring(err))
            end
        else
            Ess.Log("Sandbox.begin: unknown provider '" .. tostring(name) .. "'")
        end
    end
    Ess.Sandbox._active[id] = { providers = applied }
    Ess.Log("Sandbox.begin '" .. tostring(id) .. "' -> " .. table.concat(applied, ", "))
    return true
end

-- Ess.Sandbox.finish(id) -- restores every provider that successfully applied under this id, in order,
-- then ungates saves once the LAST active sandbox finishes (not necessarily this one, if several are
-- nested/concurrent).
function Ess.Sandbox.finish(id)
    local a = Ess.Sandbox._active[id]
    if not a then return end
    for _, name in ipairs(a.providers) do
        local p = Ess.Raw.Sandbox._providers[name]
        if p and p.restore then
            local ok, err = pcall(p.restore, id)
            if not ok then Ess.Log("Sandbox.finish: provider '" .. name .. "' restore error: " .. tostring(err)) end
        end
    end
    Ess.Sandbox._active[id] = nil
    Ess.Sandbox._nActive = math.max(0, Ess.Sandbox._nActive - 1)
    if Ess.Sandbox._nActive == 0 then Ess.Raw.Sandbox.ungateSaves() end
    Ess.Log("Sandbox.finish '" .. tostring(id) .. "'")
end

function Ess.Sandbox.isActive(id)
    return Ess.Sandbox._active[id] ~= nil
end
