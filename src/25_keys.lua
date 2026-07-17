-- Ess/25_keys.lua -- Ess.Keys: bind several key -> action handlers inside ONE script. The OnKey loader binds
-- one key per script (in lua_loader.ini), but a mod is usually a TOOLKIT of hotkeys. Ess.Keys drains the
-- edge-triggered key buffer on one shared Ess.Loop and dispatches each registered key, so a single script can
-- own a whole panel of actions. Edge-triggered: a held key fires its action ONCE.
--
-- CAVEAT (shared input buffer): this reads the same edge buffer Ess.UI's focused widgets read, so don't run
-- Ess.Keys AND a focused Ess.UI.Menu on the same keys at once -- they'll contend. Use one, or distinct keys.
--
-- API:
--   Ess.Keys.on(key, fn)     key = a VK number (0x74) OR a name ("F5", "space", "a", "1", "up") -- fn(bShift)
--   Ess.Keys.off(key)        stop handling that key
--   Ess.Keys.clear()         drop every binding
--   Ess.Keys.isBound(key) -> bool
--   Ess.Keys.vk(name) -> number | nil    resolve a name to its Windows VK code (the map this uses)

local Ess = _G.Ess
Ess.Keys = Ess.Keys or {}
-- Fresh each level load: a reload invalidates the shared loop and any bindings a prior session left. (An
-- OnKey re-run does NOT re-run this OnLoad file, so a consumer's bindings still persist between its keypresses.)
Ess.Keys._map = {}

-- name -> Windows virtual-key code
local NAMES = {}
for n = 1, 12 do NAMES["f" .. n] = 0x70 + (n - 1) end                 -- F1..F12
for c = string.byte("a"), string.byte("z") do NAMES[string.char(c)] = c - 32 end   -- a..z -> 0x41..0x5A
for d = 0, 9 do NAMES[tostring(d)] = 0x30 + d end                     -- 0..9
NAMES.space = 0x20; NAMES.enter = 0x0D; NAMES.escape = 0x1B; NAMES.esc = 0x1B; NAMES.tab = 0x09; NAMES.backspace = 0x08
NAMES.up = 0x26; NAMES.down = 0x28; NAMES.left = 0x25; NAMES.right = 0x27; NAMES.shift = 0x10; NAMES.ctrl = 0x11
NAMES.insert = 0x2D; NAMES.delete = 0x2E; NAMES.home = 0x24; NAMES["end"] = 0x23; NAMES.pageup = 0x21; NAMES.pagedown = 0x22

function Ess.Keys.vk(key)
    if type(key) == "number" then return key end
    return NAMES[tostring(key):lower()]
end

-- self-arming poll loop; idles (returns false to auto-stop) whenever nothing is bound.
local function ensureLoop()
    if Ess.Loop.isRunning("Ess.Keys") then return end
    Ess.Loop.start("Ess.Keys", 0.05, function()
        if not next(Ess.Keys._map) then return false end
        local input = Ess.Input.poll()
        local shift = input.down(0x10)
        for _, vk in ipairs(input.pressed) do
            local fn = Ess.Keys._map[vk]
            if fn then pcall(fn, shift) end
        end
        return true
    end)
end

function Ess.Keys.on(key, fn)
    local vk = Ess.Keys.vk(key)
    if not vk then Ess.Log("Keys.on: unknown key '" .. tostring(key) .. "'"); return end
    if type(fn) ~= "function" then Ess.Log("Keys.on: '" .. tostring(key) .. "' needs a function"); return end
    Ess.Keys._map[vk] = fn
    ensureLoop()
end

function Ess.Keys.off(key)
    local vk = Ess.Keys.vk(key)
    if vk then Ess.Keys._map[vk] = nil end
end

function Ess.Keys.clear() Ess.Keys._map = {} end

function Ess.Keys.isBound(key)
    local vk = Ess.Keys.vk(key)
    return vk ~= nil and Ess.Keys._map[vk] ~= nil
end
