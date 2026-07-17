-- Ess/02_str.lua -- Ess.Str: the everyday string helpers Lua 5.1's thin `string` library leaves you to
-- hand-roll. Pure Lua, no engine calls, no Ess deps -- loads right after 01_math. Every mod that parses a
-- config line, builds a HUD label, or splits a comma-list ends up rewriting these; here once, tested.
--
-- All separators/needles are LITERAL text, not Lua patterns (that's the common footgun -- `split(s, ".")`
-- surprising you by splitting on every character because `.` is a pattern). Where a function takes a
-- separator it's matched plain (string.find(..., true)); reach for the stdlib directly if you actually want
-- pattern matching.
--
-- API:
--   Ess.Str.trim(s) -> s                     strip leading/trailing whitespace
--   Ess.Str.split(s, sep) -> { piece, ... }  split on a literal sep (default ","); "" sep -> per character
--   Ess.Str.join(list, sep) -> s             the inverse (sep default "")
--   Ess.Str.startsWith(s, prefix) -> bool    Ess.Str.endsWith(s, suffix) -> bool
--   Ess.Str.contains(s, needle) -> bool      literal substring test
--   Ess.Str.count(s, needle) -> n            non-overlapping literal occurrences
--   Ess.Str.padLeft(s, width, ch) -> s       Ess.Str.padRight(s, width, ch) -> s   (ch default " ")
--   Ess.Str.capitalize(s) -> s               first letter up, rest untouched
--   Ess.Str.title(s) -> s                    Capitalize Each Word
--   Ess.Str.lines(s) -> { line, ... }        split on \n (a \r before it is dropped)
--   Ess.Str.truncate(s, n [, ellipsis]) -> s clip to n chars, appending "..." (or your ellipsis) if clipped

local Ess = _G.Ess
Ess.Str = Ess.Str or {}
local S = Ess.Str

function S.trim(s)
    return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

function S.startsWith(s, prefix)
    s, prefix = tostring(s), tostring(prefix)
    return s:sub(1, #prefix) == prefix
end

function S.endsWith(s, suffix)
    s, suffix = tostring(s), tostring(suffix)
    if suffix == "" then return true end
    return s:sub(-#suffix) == suffix
end

function S.contains(s, needle)
    return string.find(tostring(s), tostring(needle), 1, true) ~= nil
end

function S.count(s, needle)
    s, needle = tostring(s), tostring(needle)
    if needle == "" then return 0 end
    local n, i = 0, 1
    while true do
        local a = string.find(s, needle, i, true)
        if not a then return n end
        n = n + 1
        i = a + #needle          -- non-overlapping
    end
end

-- split on a LITERAL separator. Empty sep -> one entry per character. A sep that never matches -> { s }.
function S.split(s, sep)
    s = tostring(s)
    sep = sep == nil and "," or tostring(sep)
    local out = {}
    if sep == "" then
        for i = 1, #s do out[i] = s:sub(i, i) end
        return out
    end
    local i = 1
    while true do
        local a, b = string.find(s, sep, i, true)
        if not a then
            out[#out + 1] = s:sub(i)
            return out
        end
        out[#out + 1] = s:sub(i, a - 1)
        i = b + 1
    end
end

function S.join(list, sep)
    local parts = {}
    for i = 1, #list do parts[i] = tostring(list[i]) end
    return table.concat(parts, sep == nil and "" or tostring(sep))
end

local function pad(s, width, ch, left)
    s = tostring(s)
    ch = (ch == nil or ch == "") and " " or tostring(ch):sub(1, 1)
    local need = (tonumber(width) or 0) - #s
    if need <= 0 then return s end
    local fill = string.rep(ch, need)
    if left then return fill .. s end
    return s .. fill
end
function S.padLeft(s, width, ch)  return pad(s, width, ch, true)  end
function S.padRight(s, width, ch) return pad(s, width, ch, false) end

function S.capitalize(s)
    s = tostring(s)
    if s == "" then return s end
    return s:sub(1, 1):upper() .. s:sub(2)
end

function S.title(s)
    return (tostring(s):gsub("(%a)([%w]*)", function(first, rest) return first:upper() .. rest end))
end

function S.lines(s)
    s = tostring(s)
    local out = {}
    for line in (s .. "\n"):gmatch("(.-)\n") do
        out[#out + 1] = (line:gsub("\r$", ""))
    end
    -- a trailing newline shouldn't manufacture an empty final line beyond the real content
    if #out > 0 and out[#out] == "" and not s:find("\n\n$") and s:sub(-1) == "\n" then out[#out] = nil end
    return out
end

function S.truncate(s, n, ellipsis)
    s = tostring(s)
    n = tonumber(n) or 0
    if #s <= n then return s end
    ellipsis = ellipsis == nil and "..." or tostring(ellipsis)
    if n <= #ellipsis then return s:sub(1, n) end
    return s:sub(1, n - #ellipsis) .. ellipsis
end
