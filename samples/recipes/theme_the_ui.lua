-- RECIPE: restyle the whole UI kit -- switch a preset, tweak single values, define your own.
-- Namespaces: Ess.UI.Theme (+ Ess.UI.setScale).
--
-- Every Ess.UI widget is DRAWN AT RUNTIME from ~36 plain values. There is no baked-in look: no Flash
-- tools, no re-export, no wad rebuild. Restyling the kit is assigning numbers.
--
-- Two ways in, and you can mix them:
--
--   Ess.UI.Theme.preset("cyan")        -- a whole look at once
--   Ess.UI.Theme.accent = 0x59D0FF     -- or one value
--   Ess.UI.Theme.apply()               -- push it and redraw what is already on screen
--
-- Setting values BEFORE any widget exists needs no apply() -- the first widget picks them up. apply()
-- is for changing the look while the UI is live, which is what makes this pleasant to tune from the
-- console: type, apply, look, repeat.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local T = Ess.UI.Theme

-- ---------------------------------------------------------------------------------------------------
-- 1. THE BUILT-IN PRESETS. `classic` is the stock look and is deliberately an empty table -- every key
--    falls through to its default. That is worth knowing: it means the defaults ARE a theme, not
--    something privileged, and preset("classic") is always the way back.
-- ---------------------------------------------------------------------------------------------------
local names = {}
for name in pairs(T.PRESETS) do names[#names + 1] = name end
table.sort(names)
--   classic  cyan  slate  amber  neon  mono  dusk

-- ---------------------------------------------------------------------------------------------------
-- 2. A PRESET IS JUST A TABLE OF OVERRIDES. Here is `cyan` in full -- six keys, nothing else:
--
--        cyan = {
--            accent = 0x59D0FF, accentText = 0x10151A, textAccent = 0x9BE4FF,
--            rowSelected = 0x59D0FF, rowSelectedText = 0x10151A,
--            radius = 8, rowHeight = 22,
--        }
--
--    Anything it does not mention keeps the default, so a preset only has to say what makes it
--    different. Colours are 0xRRGGBB; metrics are in canvas units.
-- ---------------------------------------------------------------------------------------------------
local cyanKeys = 0
for _ in pairs(T.PRESETS.cyan) do cyanKeys = cyanKeys + 1 end

-- ---------------------------------------------------------------------------------------------------
-- 3. SWITCHING. preset() clears any previous overrides first, so looks never blend into each other.
-- ---------------------------------------------------------------------------------------------------
T.preset("cyan")
local accentAfterPreset = T.get("accent")          -- 0x59D0FF, from the preset

-- ---------------------------------------------------------------------------------------------------
-- 4. TWEAKING ON TOP. Assign, then apply(). Use T.get(k) to READ the effective value -- reading T[k]
--    directly gives nil for anything you have not personally set, since defaults live behind it.
-- ---------------------------------------------------------------------------------------------------
T.panelAlpha = 80                                   -- more transparent panels
T.rowHeight  = 24                                   -- roomier lists
T.apply()
local alphaAfterTweak = T.get("panelAlpha")         -- 80
local rawUnset        = rawget(T, "barFill")        -- nil: never set, still draws the default

-- ---------------------------------------------------------------------------------------------------
-- 5. YOUR OWN PRESET. Add to the table and it behaves exactly like the built-ins.
-- ---------------------------------------------------------------------------------------------------
T.PRESETS.recipe_demo = {
    accent = 0x2ED573, accentText = 0x06210F,
    rowSelected = 0x2ED573, rowSelectedText = 0x06210F,
    textAccent = 0x8CF0B4, radius = 6,
}
T.preset("recipe_demo")
local accentAfterOwn = T.get("accent")              -- 0x2ED573

-- An unknown name is REPORTED rather than silently ignored, because a typo'd preset would otherwise
-- look exactly like "theming doesn't work". It leaves the current theme alone.
T.preset("no_such_preset_exists")
local survivedTypo = (T.get("accent") == 0x2ED573)

-- ---------------------------------------------------------------------------------------------------
-- 6. THE SHARED PALETTE. `warn` and `danger` are not drawn by any chrome -- they exist so YOUR code can
--    pull colours that track the active theme instead of hardcoding its own.
--       Ess.UI.Toast("Low fuel", { rgb = { Ess.Color.hex(string.format("#%06X", T.get("warn"))) } })
-- ---------------------------------------------------------------------------------------------------
local danger = T.get("danger")

-- ---------------------------------------------------------------------------------------------------
-- 7. SCALE IS SEPARATE FROM THEME. The theme is the LOOK; the scale is how large the whole kit draws.
--    Scaling only the font sizes would leave text rattling around inside boxes that stayed put, so
--    setScale moves chrome, text, spacing and positions together. Default 75; lower means smaller.
--
--    Note it also re-derives Ess.UI.CANVAS_W/H, since scaling down enlarges the usable canvas.
-- ---------------------------------------------------------------------------------------------------
local scaleBefore, canvasBefore = Ess.UI.SCALE, Ess.UI.CANVAS_W
Ess.UI.setScale(70)
local canvasAtSeventy = Ess.UI.CANVAS_W             -- smaller canvas: less room, bigger chrome
Ess.UI.setScale(scaleBefore)                        -- put it back

-- ---------------------------------------------------------------------------------------------------
-- Back to stock. reset() drops every override; preset("classic") is the same thing said differently.
-- ---------------------------------------------------------------------------------------------------
T.reset()
local accentAfterReset = T.get("accent")            -- the default amber again
T.PRESETS.recipe_demo = nil                         -- leave the preset table as we found it

local ok = (#names >= 7)
    and (cyanKeys == 7)
    and (accentAfterPreset == 0x59D0FF)
    and (alphaAfterTweak == 80)
    and (rawUnset == nil)
    and (accentAfterOwn == 0x2ED573)
    and survivedTypo
    and (danger == T.DEFAULTS.danger)
    and (canvasAtSeventy < canvasBefore)            -- a bigger scale means a smaller canvas
    and (Ess.UI.SCALE == scaleBefore)
    and (accentAfterReset == T.DEFAULTS.accent)

Ess.Log(string.format("[recipe] theme_the_ui: %d presets, cyan defines %d keys, canvas %d -> %d at scale 70",
    #names, cyanKeys, canvasBefore, canvasAtSeventy))
Ess.Log("[SMOKE] theme_the_ui: " .. (ok and "PASS" or "FAIL"))
