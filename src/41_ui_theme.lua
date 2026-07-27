-- Ess/41_ui_theme.lua -- Ess.UI.Theme: the whole look of the UI kit as plain data.
--
-- Ess.UI's widgets are drawn at RUNTIME by ess_ui.gfx (see 42_ui_engine.lua's runtime
-- section), from parameters pushed out of this table. Nothing is baked into the movie, so
-- restyling the kit is assigning a few numbers -- no Flash tools, no re-export, no wad
-- rebuild.
--
-- The intended way to use it, from your own OnLoad script registered AFTER Ess:
--
--     Ess.UI.Theme.accent      = 0x59D0FF     -- header / highlight colour
--     Ess.UI.Theme.panelAlpha  = 80           -- more transparent panels
--     Ess.UI.Theme.rowHeight   = 22           -- roomier lists
--     Ess.UI.Theme.apply()                    -- push + redraw anything already on screen
--
-- Setting values before any widget exists needs no apply() -- the first widget picks them
-- up. apply() exists so a theme can be changed while the UI is live (handy from the
-- console).
--
-- RESERVED NAMES: `apply`, `reset`, `preset`, `get` and `_push` are functions on this table
-- and `DEFAULTS`/`PRESETS` are sub-tables, so none of those seven can be used as theme keys.
-- Harmless today -- none appears in DEFAULTS, so none is ever pushed to the movie -- but
-- T.get("preset") hands back a function rather than a value, which is worth knowing.
--
-- A key set to nil falls back to its default rather than drawing nothing, so a typo
-- degrades to "stock look" instead of an invisible panel.

local Ess = _G.Ess
Ess.UI = Ess.UI or {}

-- The defaults mirror ess_ui.gfx's own ThemeDefaults() exactly, and reproduce the look the
-- kit has always had -- adopting the runtime changes nothing visually until someone asks.
local DEFAULTS = {
    -- colour (0xRRGGBB)
    accent = 0xE88C18, accentText = 0x191919,
    panelFill = 0x181A1F, panelAlpha = 92, panelBorder = 0x2A2E37, borderWidth = 1,
    rowFill = 0x1E2127, rowFillAlt = 0x22252C,
    rowHover = 0x2E333C, rowSelected = 0x59D0FF, rowSelectedText = 0x10151A,
    textPrimary = 0xE1E5EC, textDim = 0x969CA8, textAccent = 0x78D2FF,
    textHeader = 0xE1E5EC,
    barFill = 0x5AD078, barTrack = 0x282C34,
    -- Not drawn by any chrome -- a shared palette for YOUR code to reference via
    -- Ess.UI.Theme.get("danger"), so a mod's own colours track the active theme.
    warn = 0xFFC448, danger = 0xE05252,
    -- metrics, in CANVAS units -- Ess.UI.CANVAS_W x CANVAS_H, which is the movie's 853x480 stage
    -- divided by Ess.UI.SCALE (1137x640 at the default 75). NOT pixels, and not the 640x480 the
    -- engine's own widget space uses.
    radius = 4, rowHeight = 18, titleHeight = 26, padding = 8,
    scrollbarWidth = 4, crumbHeight = 14, hintHeight = 14,
    -- type
    font = "_normal_Font", sizeTitle = 13, sizeBody = 11, sizeSmall = 10,
    -- feel
    easing = 0.35, hoverEnabled = 0,
    -- KNOWN NON-FUNCTIONAL: beginGradientFill renders flat in this GFx build at every
    -- rotation tested, even with the mandatory matrix argument. Kept so nothing breaks if
    -- it is ever fixed; setting it does nothing today. See
    -- gfxforge-web/examples/mercs2/ess_ui.results.md.
    gradientHeader = 0, gradientAngle = 1.5707963,
}

Ess.UI.Theme = Ess.UI.Theme or {}
local T = Ess.UI.Theme

Ess.UI.Theme.DEFAULTS = DEFAULTS

-- Presets. "classic" is the stock look; keeping it as an explicit preset means a user who
-- has wandered off can always get back, and it documents that the defaults ARE a theme
-- rather than something special.
local PRESETS = {
    classic = {},   -- empty: every key falls through to its default
    cyan = {
        accent = 0x59D0FF, accentText = 0x10151A, textAccent = 0x9BE4FF,
        rowSelected = 0x59D0FF, rowSelectedText = 0x10151A,
        radius = 8, rowHeight = 22,
    },
    slate = {
        accent = 0x4A5160, accentText = 0xE1E5EC,
        panelFill = 0x14161A, panelAlpha = 96, panelBorder = 0x39404D,
        rowFill = 0x191C22, rowFillAlt = 0x1D2128,
        rowSelected = 0x7A8394, rowSelectedText = 0xFFFFFF,
        textAccent = 0xAEB7C6, radius = 2,
    },
    amber = {
        accent = 0xFFC448, accentText = 0x191919,
        rowSelected = 0xFFC448, rowSelectedText = 0x191919,
        textAccent = 0xFFD980, textHeader = 0xFFC448,
    },
    -- deliberately loud, for showing the range rather than for daily use
    neon = {
        accent = 0xFF2D95, accentText = 0x0A0A12,
        panelFill = 0x0A0A12, panelAlpha = 88, panelBorder = 0xFF2D95, borderWidth = 2,
        rowFill = 0x121020, rowFillAlt = 0x181430,
        rowSelected = 0x00F0C0, rowSelectedText = 0x05121A,
        textPrimary = 0xEAE6FF, textAccent = 0x00F0C0, textHeader = 0xFF2D95,
        textDim = 0x7A6FA8, barFill = 0x00F0C0, barTrack = 0x201A38,
        radius = 0, rowHeight = 20, sizeBody = 12,
    },
    -- high contrast, chunky rows -- also a legibility option, not only a look
    mono = {
        accent = 0xFFFFFF, accentText = 0x000000,
        panelFill = 0x000000, panelAlpha = 100, panelBorder = 0xFFFFFF, borderWidth = 1,
        rowFill = 0x000000, rowFillAlt = 0x0D0D0D,
        rowSelected = 0xFFFFFF, rowSelectedText = 0x000000,
        textPrimary = 0xFFFFFF, textDim = 0x9A9A9A, textAccent = 0xFFFFFF,
        textHeader = 0xFFFFFF, barFill = 0xFFFFFF, barTrack = 0x2A2A2A,
        radius = 0, rowHeight = 22, sizeBody = 12, sizeTitle = 14,
    },
    -- soft, low-contrast, rounded
    dusk = {
        accent = 0x8A7BC8, accentText = 0x14121F,
        panelFill = 0x1B1826, panelAlpha = 90, panelBorder = 0x342E4A,
        rowFill = 0x211D2E, rowFillAlt = 0x262234,
        rowSelected = 0xC0A9F0, rowSelectedText = 0x14121F,
        textPrimary = 0xE4DEF5, textDim = 0x8E86A8, textAccent = 0xC0A9F0,
        textHeader = 0xC0A9F0, barFill = 0x8A7BC8, barTrack = 0x2A2540,
        radius = 10, rowHeight = 20,
    },
}
Ess.UI.Theme.PRESETS = PRESETS

-- Effective value for a key: whatever's on the table, else the default. Used by both the
-- push below and by any Lua-side code that needs to lay something out consistently with
-- what the movie will draw.
function T.get(k)
    local v = T[k]
    if v == nil then return DEFAULTS[k] end
    return v
end

-- Every key the movie understands, so pushing is a fixed loop rather than a pairs() walk
-- over a table that also holds three functions and two sub-tables.
local KEYS = {}
for k in pairs(DEFAULTS) do KEYS[#KEYS + 1] = k end
table.sort(KEYS)   -- deterministic push order, so a log of the pushes is diffable

-- Pushes the whole theme into the movie. Called by the engine on first use and by apply().
-- Deliberately pushes ALL keys rather than only changed ones: it runs rarely, and a full
-- push means the movie can never be half-way between two themes.
function T._push(sendFn)
    for i = 1, #KEYS do
        local k = KEYS[i]
        sendFn("ThemeSet", { k, T.get(k) })
    end
end

-- Re-push and redraw everything already on screen. Safe to call when no UI exists.
function T.apply()
    if Ess.UI._rtReady and Ess.UI._rtReady() then
        T._push(Ess.UI._rtcall)
        Ess.UI._rtcall("ThemeApply", {})
    else
        -- Not loaded yet: the engine pushes the theme itself as part of its ready
        -- handshake, so there is nothing to do and nothing to queue.
        Ess.UI._rtcall("ThemeApply", {})
    end
    return T
end

-- Clear every override, back to stock.
function T.reset()
    for i = 1, #KEYS do T[KEYS[i]] = nil end
    return T.apply()
end

-- Apply a named preset. Unknown names are reported rather than silently ignored, since a
-- typo'd preset name would otherwise look like "theming doesn't work".
function T.preset(name)
    local p = PRESETS[name]
    if not p then
        Ess.Log("UI.Theme.preset: no preset named '" .. tostring(name) .. "'")
        return T
    end
    for i = 1, #KEYS do T[KEYS[i]] = nil end
    for k, v in pairs(p) do T[k] = v end
    return T.apply()
end
