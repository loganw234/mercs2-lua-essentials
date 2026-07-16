-- Ess/24_save.lua -- Ess.Save: the ONE shared save-gate. Any subsystem that needs to suppress savegames/
-- autosaves for the duration of an ephemeral mode (Ess.Layers, Ess.Sandbox, or a future one) routes through
-- this instead of stashing/swapping Pg.SaveGame itself.
--
-- API:
--   Ess.Save.gate(sHolderKey)     add a holder -- saves are suppressed while >=1 holder is active
--   Ess.Save.ungate(sHolderKey)   remove a holder -- saves resume once the LAST holder is gone
--   Ess.Save.isGated() -> bool    are saves currently suppressed?
--   Ess.Save.holders() -> {keys}  who's currently holding the gate (for diagnostics)
--
-- WHY THIS EXISTS (a real, confirmed hazard it removes at the source): before this, Ess.Layers and
-- Ess.Sandbox EACH gated saves their own way -- Layers by a raw `Pg.SaveGame = noop` stash-and-swap,
-- Sandbox by a lazily-installed Ess.Override.wrap. Because Sandbox's wrap installs on the FIRST-EVER
-- Ess.Sandbox.begin() call, a specific interleaving (Ess.Layers.begin() directly, then the session's first
-- Ess.Sandbox.begin() while that Layers mode is still active, then Ess.Layers.finish()) had Layers'
-- finish() reassign Pg.SaveGame back to the PRE-Layers value -- silently discarding Sandbox's freshly
-- installed wrap, leaving Sandbox's save-gate permanently ineffective for the rest of the session. Two
-- independent things both owning Pg.SaveGame is the root cause. Ess.Save fixes it structurally: the wrap is
-- installed ONCE and NEVER uninstalled -- it simply passes through when no holders are active. Nobody ever
-- reassigns Pg.SaveGame directly again, so one gate-user can't clobber another's, by construction.

local Ess = _G.Ess
Ess.Save = Ess.Save or {}
Ess.Save._holders   = Ess.Save._holders   or {}     -- set of active holder keys ({key=true})
Ess.Save._installed = Ess.Save._installed or false  -- persists: the wrap is installed once for the process

local function anyHolders()
    return next(Ess.Save._holders) ~= nil
end

local function holderList()
    local t = {}
    for k in pairs(Ess.Save._holders) do t[#t + 1] = k end
    return table.concat(t, ", ")
end
Ess.Save.holders = function()
    local t = {}
    for k in pairs(Ess.Save._holders) do t[#t + 1] = k end
    return t
end

-- Install the gate ONCE. Deliberately a plain manual wrap, NOT Ess.Override.wrap: (1) Ess.Override
-- (90_override.lua) loads AFTER this file, so it isn't available at load time; (2) there's no tail-call
-- concern here anyway -- the wrapper either suppresses (returns nothing) or calls the captured original as
-- a plain statement and returns its results on a separate line, which is exactly the confirmed-safe shape
-- Ess.Override.wrap enforces. The `_installed` flag persists across OnLoad re-runs (Ess.Save survives via
-- `Ess.Save or {}`), and Pg.SaveGame is a native engine function whose reference is stable for the whole
-- process, so the single install stays live -- re-wrapping on every reload would just stack layers.
local function install()
    if Ess.Save._installed then return end
    if type(Pg) == "table" and type(Pg.SaveGame) == "function" then
        local origSave = Pg.SaveGame
        Pg.SaveGame = function(...)
            if anyHolders() then
                Ess.Log("Save: savegame suppressed (holders: " .. holderList() .. ")")
                return
            end
            local a, b, c, d = origSave(...)
            return a, b, c, d
        end
    end
    if type(Sys) == "table" and type(Sys.RequestAutosave) == "function" then
        local origReq = Sys.RequestAutosave
        Sys.RequestAutosave = function(...)
            if anyHolders() then return end
            local a, b, c, d = origReq(...)
            return a, b, c, d
        end
    end
    if type(Sys) == "table" and type(Sys.ForceNextAutosave) == "function" then
        local origForce = Sys.ForceNextAutosave
        Sys.ForceNextAutosave = function(...)
            if anyHolders() then return end
            local a, b, c, d = origForce(...)
            return a, b, c, d
        end
    end
    Ess.Save._installed = true
end

-- Ess.Save.gate(sHolderKey) -- give each caller a distinct key (e.g. "Ess.Layers", "sandbox:myArena").
-- Idempotent per key: gating twice with the same key is a single holder, so a paired ungate() clears it.
function Ess.Save.gate(sHolderKey)
    sHolderKey = sHolderKey or "default"
    install()
    Ess.Save._holders[sHolderKey] = true
end

function Ess.Save.ungate(sHolderKey)
    Ess.Save._holders[sHolderKey or "default"] = nil
end

function Ess.Save.isGated()
    return anyHolders()
end

-- Boot: clear holders on every world (re)load. A reload ends any ephemeral mode that was mid-flight, so
-- saves MUST resume -- this is strictly safer than the old per-subsystem `_gated or false` persistence,
-- which could leave saves stuck gated forever if a mode was active at the moment of a reload. `_installed`
-- deliberately does NOT reset (the wrap itself survives the reload; only who's holding it is cleared).
Ess.Save._holders = {}
