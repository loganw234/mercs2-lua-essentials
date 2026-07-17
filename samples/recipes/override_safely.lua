-- RECIPE: change a piece of game logic WITHOUT the engine's tail-call crash -- two safe patterns.
-- Namespaces: Ess.Override.
--
-- Writing `SomeModule.Fn = function(...) return orig(...) end` compiles as a Lua TAIL CALL, which collapses
-- the stack frame -- and this engine walks frames with getfenv(n) internally, so a collapsed frame throws
-- ":1: no function environment for tail call" from deep inside ENGINE code (a real, already-shipped crash).
-- Ess.Override makes that pattern impossible to write:
--   Ess.Override.wrap(t, name, newFn)      newFn(callOriginal, ...) -- callOriginal is the ONLY way to reach
--                                          the real original, always via the confirmed-safe two-line shape.
--   Ess.Override.mergeIntoLiveTable(t,k,d) append rows into a table the game already reads from, instead of
--                                          replacing the function that reads it (the wardrobe-unlock pattern).

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- Pattern 1: WRAP. We use a throwaway table here so the recipe is self-contained, but in a real mod `demo`
-- would be an engine module and "greet" one of its functions. newFn receives callOriginal first: call it to
-- get the original's result, then augment it -- you never touch the raw original, so you can't tail-call it.
local demo = { greet = function(name) return "hi " .. tostring(name) end }
Ess.Override.wrap(demo, "greet", function(callOriginal, name)
    local base = callOriginal(name)     -- the real original, invoked the crash-proof way
    return base .. "!"                  -- ...then add to it
end)
local greetOk = (demo.greet("world") == "hi world!")
-- wrapping the same key twice is refused (it would silently stack an invisible extra layer) -> returns false
local doubleRefused = (Ess.Override.wrap(demo, "greet", function() end) == false)

-- Pattern 2: MERGE INTO A LIVE TABLE. The real win for data the game re-reads every frame (costume lists,
-- unlock tables): append to the SAME table object so existing, unmodified reader code sees your rows with
-- zero risk of dropping the responsibilities a full function replacement would. Tables are references --
-- everyone holding `menu.items` sees the appended rows immediately.
local menu = { items = { "stock_A", "stock_B" } }
local liveRef = menu.items
Ess.Override.mergeIntoLiveTable(menu, "items", { "modded_C", "modded_D" })
local mergeOk = (#menu.items == 4) and (menu.items == liveRef)   -- grew, and it's still the SAME object

local ok = greetOk and doubleRefused and mergeOk
Ess.Log("[recipe] override_safely: wrap composes=" .. tostring(greetOk)
    .. ", double-wrap refused=" .. tostring(doubleRefused)
    .. ", live-merge in place=" .. tostring(mergeOk))
Ess.Log("[SMOKE] override_safely: " .. (ok and "PASS" or "FAIL"))
