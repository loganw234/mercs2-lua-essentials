-- Ess/95_ui_easy.lua -- Ess.Easy.Toast/Confirm/Menu: the handful of single-call UI cases that don't need
-- the full widget-object API. Ess.Gfx (raw FlashWidget primitives) is the Raw tier for UI; the absorbed
-- Ess.UI is Core (already fairly friendly, so most UI work doesn't need an Easy tier at all) -- this file
-- is the thin sliver on top that does.
--
-- Ess.Easy.Toast(msg)                          -- a plain string, no opts table
-- Ess.Easy.Confirm(text, onYes, onNo)          -- positional callbacks, no opts table
-- Ess.Easy.Menu(title, entries)                -- entries = { {label,fn}, ... } or { [label]=fn, ... },
--                                                  FLAT (no :category nesting) -- use Ess.UI.Menu directly
--                                                  for the full builder if you need nesting/:switch

local Ess = _G.Ess
Ess.Easy = Ess.Easy or {}

-- Ess.Easy.Toast(msg) -- fire-and-forget notification.
function Ess.Easy.Toast(msg)
    return Ess.UI.Toast(tostring(msg))
end

-- Ess.Easy.Confirm(text, onYes, onNo) -- pop a yes/no dialog; onNo is optional (default: do nothing).
function Ess.Easy.Confirm(text, onYes, onNo)
    return Ess.UI.Confirm({ text = text, onResult = function(yes)
        if yes then if onYes then pcall(onYes) end
        elseif onNo then pcall(onNo) end
    end })
end

-- Ess.Easy.Menu(title, entries) -- opens immediately, one flat level, no bools/tables to configure.
-- entries accepts either shape:
--   { {"Heal", healFn}, {"Spawn Car", spawnFn} }        -- ordered array of {label, action} pairs
--   { ["Heal"] = healFn, ["Spawn Car"] = spawnFn }       -- map (order not guaranteed by Lua's pairs())
-- Each action receives the same ctx as Ess.UI.Menu's full builder (ctx:hint/toast/confirm/ask/spawn/close).
function Ess.Easy.Menu(title, entries)
    local m = Ess.UI.Menu(title)
    entries = entries or {}
    if entries[1] ~= nil then
        for _, e in ipairs(entries) do
            if type(e) == "table" and e[1] then m:entry(e[1], e[2]) end
        end
    else
        for label, fn in pairs(entries) do m:entry(label, fn) end
    end
    m:open()
    return m
end
