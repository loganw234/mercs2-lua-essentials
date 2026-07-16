-- Ess/22_state.lua -- Ess.State: the `_G.X = _G.X or {defaults}` idiom, done field-by-field.
-- Ess.SaveVar: a namespaced, typed wrapper over Loader.SaveVar/LoadVar.
--
-- API:
--   Ess.State(name, defaults) -> persistent table
--   Ess.SaveVar.ns(prefix) -> ns object: ns:get(key,default) / ns:set(key,val) / ns:flag(key) / ns:setFlag(key,bOn)

local Ess = _G.Ess

-- Ess.State(name, defaults) -> persistent table
-- Every stateful OnKey/OnLoad script needs this (a script re-executes fully on each keypress/reload; only
-- _G survives between runs) -- but merges field BY FIELD instead of a blind top-level `or`.
--
-- CONFIRMED real bug this fixes: `_G.S = _G.S or {a=1,b=2}` silently drops a newly-added field (say you
-- add `c=3` to `defaults` in a later edit) if `_G.S` already exists from an earlier run in the same
-- session -- the `or` short-circuits on the WHOLE table the instant it sees `_G.S` is non-nil, so the new
-- key is never even considered. Merging key-by-key means adding a field to `defaults` later always takes
-- effect on the next run, even if the table already exists.
function Ess.State(name, defaults)
    local key = "_Ess_state_" .. tostring(name)
    local S = _G[key]
    if not S then
        S = {}
        _G[key] = S
    end
    for k, v in pairs(defaults or {}) do
        if S[k] == nil then S[k] = v end
    end
    return S
end

-- ============================================================
-- Ess.SaveVar -- Loader.SaveVar/LoadVar is a FLAT namespace shared by every mod (numbers/strings/booleans
-- only, persists across game restarts in lua_loader_data.ini) -- every mod ends up hand-rolling its own
-- prefixed get/set + unlock-flag idiom over it (directly confirmed duplicated in WaveDefense.lua). One
-- namespaced wrapper instead.
-- ============================================================
Ess.SaveVar = Ess.SaveVar or {}
Ess.SaveVar.__index = Ess.SaveVar

-- Ess.SaveVar.ns(prefix) -> namespace object
-- `local sv = Ess.SaveVar.ns("MyMod")` then `sv:get("xp", 0)`, `sv:set("xp", n)`, `sv:flag("unlock_x")`.
-- Every key is stored as `<prefix>_<key>` so two mods' saved values can never collide.
function Ess.SaveVar.ns(prefix)
    return setmetatable({ prefix = tostring(prefix) .. "_" }, Ess.SaveVar)
end

function Ess.SaveVar:get(key, default)
    local v = Loader.LoadVar(self.prefix .. key)
    if v == nil then return default end
    return v
end

function Ess.SaveVar:set(key, value)
    Loader.SaveVar(self.prefix .. key, value)
end

-- :flag(key) -> bool -- a get() specialized for booleans (default false)
function Ess.SaveVar:flag(key)
    return self:get(key, false) == true
end

function Ess.SaveVar:setFlag(key, bOn)
    self:set(key, bOn and true or false)
end
