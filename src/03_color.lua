-- Ess/03_color.lua -- Ess.Color: RGB helpers for the many `rgb = { r, g, b }` parameters across Ess
-- (Ess.Mark, Ess.UI, the objective marker tints). Pure Lua, no engine calls, no Ess deps. Everything works
-- in 0-255 space, matching what those consumers expect.
--
-- The colour functions return THREE values (r, g, b), which drops straight into an `rgb = { ... }` param
-- because it's the sole element: `Ess.Mark.object(g, { rgb = { Ess.Color.hex("#ff8800") } })` captures all
-- three. The presets in Ess.Color.NAMES are ready-made { r, g, b } tables for the same slots.
--
-- API:
--   Ess.Color.hex(s) -> r, g, b | nil       parse "#RRGGBB" / "RRGGBB" / "#RGB" (short form)
--   Ess.Color.hsv(h, s, v) -> r, g, b       h in [0,360), s and v in [0,1] -> rgb (rainbows, distinct tints)
--   Ess.Color.lerp(c1, c2, t) -> r, g, b    blend two { r, g, b } colours, t in [0,1] (health-bar gradients)
--   Ess.Color.of(name) -> r, g, b | nil     look up a preset by name ("red", "orange", ...)
--   Ess.Color.NAMES = { red = { 255,0,0 }, ... }   the preset table, usable directly as an rgb param

local Ess = _G.Ess
Ess.Color = Ess.Color or {}
local C = Ess.Color

local function round(x) return math.floor(x + 0.5) end
local function clampByte(x) if x < 0 then return 0 elseif x > 255 then return 255 else return round(x) end end

function C.hex(s)
    s = tostring(s):gsub("^#", "")
    if #s == 3 then                                  -- short form: "f80" -> "ff8800"
        s = s:sub(1, 1):rep(2) .. s:sub(2, 2):rep(2) .. s:sub(3, 3):rep(2)
    end
    if #s ~= 6 then return nil end
    local r = tonumber(s:sub(1, 2), 16)
    local g = tonumber(s:sub(3, 4), 16)
    local b = tonumber(s:sub(5, 6), 16)
    if not (r and g and b) then return nil end
    return r, g, b
end

function C.hsv(h, s, v)
    h = ((tonumber(h) or 0) % 360) / 60
    s = math.max(0, math.min(tonumber(s) or 0, 1))
    v = math.max(0, math.min(tonumber(v) or 0, 1))
    local c = v * s
    local x = c * (1 - math.abs(h % 2 - 1))
    local m = v - c
    local r, g, b
    if     h < 1 then r, g, b = c, x, 0
    elseif h < 2 then r, g, b = x, c, 0
    elseif h < 3 then r, g, b = 0, c, x
    elseif h < 4 then r, g, b = 0, x, c
    elseif h < 5 then r, g, b = x, 0, c
    else              r, g, b = c, 0, x end
    return clampByte((r + m) * 255), clampByte((g + m) * 255), clampByte((b + m) * 255)
end

-- blend c1 -> c2 by t. Each colour is { r, g, b } (or r/g/b keys). t clamped to [0,1].
function C.lerp(c1, c2, t)
    t = math.max(0, math.min(tonumber(t) or 0, 1))
    local r1, g1, b1 = c1[1] or c1.r or 0, c1[2] or c1.g or 0, c1[3] or c1.b or 0
    local r2, g2, b2 = c2[1] or c2.r or 0, c2[2] or c2.g or 0, c2[3] or c2.b or 0
    return clampByte(r1 + (r2 - r1) * t), clampByte(g1 + (g2 - g1) * t), clampByte(b1 + (b2 - b1) * t)
end

C.NAMES = {
    red = { 255, 0, 0 }, green = { 0, 200, 0 }, blue = { 40, 100, 255 }, yellow = { 255, 220, 0 },
    orange = { 255, 140, 0 }, cyan = { 0, 220, 220 }, magenta = { 255, 0, 255 }, purple = { 160, 60, 220 },
    pink = { 255, 120, 180 }, lime = { 160, 255, 40 }, teal = { 0, 160, 160 }, white = { 255, 255, 255 },
    black = { 0, 0, 0 }, gray = { 128, 128, 128 }, grey = { 128, 128, 128 }, brown = { 140, 90, 40 },
}

function C.of(name)
    local c = C.NAMES[tostring(name):lower()]
    if not c then return nil end
    return c[1], c[2], c[3]
end
