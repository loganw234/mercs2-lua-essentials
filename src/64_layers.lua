-- Ess/64_layers.lua -- Ess.Layers: safe, save-clean runtime manipulation of the vz_state_* layer system
-- for EPHEMERAL modes (arenas/minigames). Absorbed from LayerFw.lua (mercs2-layer-framework) -- the one
-- library left as an ADOPTED external dependency when uilib/ModNet/ContractFramework were absorbed;
-- now native, matching the same treatment (Logan: "the other framework files are to be abandoned, moving
-- forward Essentials will contain all of them"). Everything routes through MrxLayerManager (never raw
-- Pg.LoadLayer/UnloadLayer) so its _tLoadedLayers bookkeeping -- the single source of truth the native
-- save reads -- stays authoritative and consistent with the world at all times. STATIC layers (terrain/
-- geometry) are refused outright. Layer changes are applied for a mode's duration and ALWAYS restored on
-- finish(); saves are gated (no-op'd) the whole time via the shared Ess.Save gate (24_save.lua), so a
-- crash mid-mode just leaves the pre-mode vanilla save on disk -- nothing to recover.
--
-- API:
--   Ess.Layers.begin(sId)                  open a mode: snapshot baseline + gate saves. false if already open.
--   Ess.Layers.add(vLayers[, fCb])          load layer(s) (culls dupes/nonexistent; refuses static)
--   Ess.Layers.remove(vLayers[, fCb])       unload layer(s) (refuses static)
--   Ess.Layers.swap(vRemove, vAdd[, fCb])   remove-then-add, sequenced (the mission idiom)
--   Ess.Layers.expect{ present=, absent=[, cb=] }   converge the world to a declared set (fixes drift)
--   Ess.Layers.composite([fCb])             OPTIONAL: force a VISIBLE recomposite (WaitForStreaming)
--   Ess.Layers.finish([fCb])                restore baseline + un-gate saves
--   Ess.Layers.isActive() / .isLoaded(sName) / .snapshot() / .current()
--
-- Ess.Sandbox's built-in "layers" provider (63_sandbox.lua) is a thin wrapper over this -- was
-- `_G.LayerFw.begin(id)`/`.finish()`, existence-checked; now `Ess.Layers.begin(id)`/`.finish()` directly.

import("MrxLayerManager")
import("MrxState")

local Ess = _G.Ess
Ess.Layers = Ess.Layers or {}
local L = Ess.Layers
L.active   = L.active   or nil     -- session id string while a mode is open (nil = idle)
L.baseline = L.baseline or nil     -- { [lowername]=true } loaded dynamic-layer snapshot taken at begin
L.delta    = L.delta    or nil     -- { added={}, removed={} } what THIS mode changed (for logs/debug)

local function safe(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, e = pcall(fn, ...)
    if not ok then Ess.Log("Layers: ERR " .. tostring(e)) end
    return ok
end
local function lower(s) return string.lower(tostring(s)) end
local function aslist(v) if type(v) == "string" then return { v } elseif type(v) == "table" then return v end return {} end
local function count(set) local n = 0 for _ in pairs(set or {}) do n = n + 1 end return n end
local function setToList(set) local t = {} for k in pairs(set or {}) do t[#t + 1] = k end return t end

-- read MrxLayerManager's live dynamic-layer table -- the ONLY source of "what's loaded" (there is
-- no Pg.GetLoadedLayers native). Returns a name->true set of currently-loaded dynamic layers.
local function currentSet()
    local set = {}
    local lm = MrxLayerManager
    if lm and lm._tLoadedLayers then
        for name in pairs(lm._tLoadedLayers) do set[name] = true end
    end
    return set
end

local function isStatic(name)
    local ok, r = pcall(function() return Pg.IsStaticLayer(name) end)
    return ok and r and true or false
end

-- lowercase + drop STATIC layers (terrain/geometry must never be touched mid-session).
local function clean(list, opWord)
    local out = {}
    for _, n in ipairs(list) do
        local ln = lower(n)
        if isStatic(ln) then Ess.Log("Layers: refusing STATIC layer '" .. ln .. "' (" .. tostring(opWord) .. ")")
        else out[#out + 1] = ln end
    end
    return out
end

-- ---- save gating: routes through the ONE shared gate (Ess.Save, 24_save.lua) instead of Ess.Layers
-- stashing/swapping Pg.SaveGame itself. This is the structural fix for a real ordering hazard that existed
-- when Ess.Layers and Ess.Sandbox each owned their own Pg.SaveGame swap: a specific interleaving could have
-- Layers' finish() reassign Pg.SaveGame back to a value that silently discarded Sandbox's own wrap. Now
-- nobody reassigns Pg.SaveGame directly -- both just add/remove a holder key on Ess.Save, and the single
-- never-uninstalled wrap suppresses saves whenever ANY holder is active. Ess.Layers only ever runs one mode
-- at a time (begin() refuses if already active), so a single fixed holder key is all it needs.
local SAVE_KEY = "Ess.Layers"
local function gateSaves()   Ess.Save.gate(SAVE_KEY)   end
local function ungateSaves() Ess.Save.ungate(SAVE_KEY) end

-- ---- public API ----------------------------------------------------------------------------
function L.isActive() return L.active ~= nil end
function L.current()  return setToList(currentSet()) end
function L.snapshot() return L.baseline and setToList(L.baseline) or {} end
function L.isLoaded(name)
    local lm = MrxLayerManager
    return (lm and lm._tLoadedLayers and lm._tLoadedLayers[lower(name)] ~= nil) or false
end

function L.begin(sId)
    if L.active then Ess.Log("Layers: begin ignored -- already active: " .. tostring(L.active)); return false end
    L.active   = sId or "mode"
    L.baseline = currentSet()
    L.delta    = { added = {}, removed = {} }
    gateSaves()
    Ess.Log("Layers: BEGIN '" .. L.active .. "' (baseline " .. count(L.baseline) .. " dynamic layers, saves gated)")
    return true
end

function L.add(vLayers, fCb)
    if not L.active then Ess.Log("Layers: add ignored -- no active mode (call Ess.Layers.begin first)"); return end
    local list = clean(aslist(vLayers), "add")
    if #list == 0 then if fCb then safe(fCb) end return end
    for _, n in ipairs(list) do L.delta.added[n] = true; L.delta.removed[n] = nil end
    Ess.Log("Layers: add " .. table.concat(list, ", "))
    safe(function() MrxLayerManager.Add(list, fCb, nil, true) end)   -- bCullDupes = true
end

function L.remove(vLayers, fCb)
    if not L.active then Ess.Log("Layers: remove ignored -- no active mode"); return end
    local list = clean(aslist(vLayers), "remove")
    if #list == 0 then if fCb then safe(fCb) end return end
    for _, n in ipairs(list) do L.delta.removed[n] = true; L.delta.added[n] = nil end
    Ess.Log("Layers: remove " .. table.concat(list, ", "))
    safe(function() MrxLayerManager.Remove(list, fCb) end)
end

function L.swap(vRemove, vAdd, fCb)
    if not L.active then Ess.Log("Layers: swap ignored -- no active mode"); return end
    local rem = clean(aslist(vRemove), "swap-remove")
    local add = clean(aslist(vAdd), "swap-add")
    for _, n in ipairs(rem) do L.delta.removed[n] = true; L.delta.added[n] = nil end
    for _, n in ipairs(add) do L.delta.added[n] = true; L.delta.removed[n] = nil end
    Ess.Log("Layers: swap  -" .. #rem .. " / +" .. #add)
    safe(function()
        MrxLayerManager.Remove(rem, function()
            MrxLayerManager.Add(add, fCb, nil, true)
        end)
    end)
end

-- Declarative convergence: make the world match { present = {...}, absent = {...} }, issuing only
-- the minimal add/remove. Directly answers the two failure modes -- "expected but missing" gets
-- loaded, "present but unexpected" gets unloaded.
function L.expect(spec)
    if not L.active then Ess.Log("Layers: expect ignored -- no active mode"); return end
    spec = spec or {}
    local want    = clean(aslist(spec.present or {}), "expect-present")
    local notWant = clean(aslist(spec.absent  or {}), "expect-absent")
    local cur = currentSet()
    local toAdd, toRemove = {}, {}
    for _, n in ipairs(want)    do if not cur[n] then toAdd[#toAdd + 1] = n end end
    for _, n in ipairs(notWant) do if     cur[n] then toRemove[#toRemove + 1] = n end end
    Ess.Log("Layers: expect: converge +" .. #toAdd .. " / -" .. #toRemove)
    L.swap(toRemove, toAdd, spec.cb)
end

-- OPTIONAL. Force the engine to actually RE-COMPOSITE the layers just added/removed, from a context
-- (OnLoad, or just standing still) that wouldn't stream them in on its own. Many ephemeral modes DON'T
-- need this -- one that teleports/fast-travels the player composites for free. Best-effort; call AFTER
-- the layer ops finish.
function L.composite(fCb)
    local MS = MrxState
    if not (MS and MS.Enter) then Ess.Log("Layers: composite skipped -- MrxState unavailable"); if fCb then safe(fCb) end return end
    Ess.Log("Layers: composite: forcing WaitForStreaming recomposite")
    safe(function()
        MS.Enter(MS.STATE_WAITFORGAME, function()
            MS.Enter(MS.STATE_WAITFORSTREAMING, nil, nil, function()
                MS.Exit(MS.STATE_WAITFORSTREAMING)
            end)
            MS.Exit(MS.STATE_WAITFORGAME)
            Ess.Log("Layers: composite: recomposite done")
            if fCb then safe(fCb) end
        end)
    end)
end

function L.finish(fCb)
    if not L.active then Ess.Log("Layers: finish ignored -- no active mode"); if fCb then safe(fCb) end return end
    local sId  = L.active
    local cur  = currentSet()
    local base = L.baseline or {}
    -- diff current -> baseline: remove what we added, re-add what we removed. Restores EXACTLY,
    -- whatever the mode did in between (doesn't rely on the delta being complete).
    local toRemove, toAdd = {}, {}
    for n in pairs(cur)  do if not base[n] then toRemove[#toRemove + 1] = n end end
    for n in pairs(base) do if not cur[n]  then toAdd[#toAdd + 1]       = n end end
    toRemove = clean(toRemove, "restore-remove")   -- guard: never unload a static layer on restore
    Ess.Log("Layers: FINISH '" .. sId .. "' restoring: -" .. #toRemove .. " / +" .. #toAdd)
    local finished = false
    local function done()
        if finished then return end
        finished = true
        ungateSaves()
        L.active, L.baseline, L.delta = nil, nil, nil
        Ess.Log("Layers: restored to baseline, saves un-gated")
        if fCb then safe(fCb) end
    end
    local ok = safe(function()
        MrxLayerManager.Remove(toRemove, function()
            MrxLayerManager.Add(toAdd, done, nil, true)
        end)
    end)
    if not ok then done() end   -- manager unavailable/threw -- still un-gate + clear so we can't strand the mode
end
