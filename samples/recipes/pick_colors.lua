-- RECIPE: build colours for markers and UI -- hex, HSV, gradients, named presets.
-- Namespaces: Ess.Color (+ Ess.Mark to use them).
--
-- Ess.Mark and Ess.UI take colours as `rgb = { r, g, b }` (0-255). Ess.Color makes those without reaching
-- for a hex chart: parse a web colour, spin a hue for N distinct team tints, or blend green->red for a
-- health bar. The colour functions return three values, which drop straight into an `rgb = { ... }` slot
-- because they're the only element inside the braces.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- parse a web hex colour (long or short form) into an rgb param
local orange = { Ess.Color.hex("#ff8800") }                       -- { 255, 136, 0 }

-- a health-bar gradient: blend green -> red by how hurt something is
local hurt75 = { Ess.Color.lerp(Ess.Color.NAMES.green, Ess.Color.NAMES.red, 0.75) }

-- N evenly-spaced hues -> N distinct team tints (rainbow), no colour chart needed
local teamTints = {}
for i = 0, 3 do teamTints[i + 1] = { Ess.Color.hsv(i * 90, 1, 1) } end   -- 0/90/180/270 degrees

-- a named preset drops straight into a marker (shown; needs a live world to actually render):
--   Ess.Mark.zone(x, y, z, 20, { rgb = Ess.Color.NAMES.cyan })
--   Ess.Mark.object(guid, { rgb = { Ess.Color.hex("#ff0044") } })
local presetR, presetG, presetB = Ess.Color.of("red")

local ok = (orange[1] == 255 and orange[2] == 136 and orange[3] == 0)
    and (#hurt75 == 3 and hurt75[1] > hurt75[2])   -- redder than green by now
    and (#teamTints == 4)
    and (presetR == 255 and presetG == 0 and presetB == 0)

Ess.Log(string.format("[recipe] pick_colors: hex=%d,%d,%d  hurt75=%d,%d,%d  4 team tints ready",
    orange[1], orange[2], orange[3], hurt75[1], hurt75[2], hurt75[3]))
Ess.Log("[SMOKE] pick_colors: " .. (ok and "PASS" or "FAIL"))
