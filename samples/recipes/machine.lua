-- RECIPE: drive & watch the destruction state machine -- Ess.Machine.
-- Namespaces: Ess.Machine, Ess.Probe, Ess.Named.
--
-- Every destructible runs a state machine over a GLOBAL vocabulary (PristineState .. DestroyedState ..
-- CollapseState). This arms a listener that logs every transition with the hashes resolved to NAMES, then
-- inspects a nearby building's machine. Forcing a specific state is shown too, but node addressing is
-- object-specific (a multi-part building's pieces are reached via Ess.Machine.link), so the live SetState is
-- gated behind finding a target and left for you to point at a node you've inspected.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

-- 1. Watch EVERY destruction transition in the world, legibly. uGuid is the raw object; sState/sNode come
--    already resolved to names where we know them (state vocabulary + Ess.Names), else the bare hash.
local stop = Ess.Machine.onChange(function(uGuid, sState, sNode)
    Ess.Log(string.format("[machine] %s -> %s  (node %s)", tostring(Ess.Named(uGuid)), sState, sNode))
end)

-- 2. The known vocabulary, and the reverse lookup that makes a log line readable.
Ess.Log("[recipe] machine: " .. #Ess.Machine.vocab() .. " known states; 0x694683EB = " .. Ess.Machine.name("0x694683EB"))

-- 3. Inspect a nearby destructible's live machine (dumped to the loader log by the engine itself).
local target = Ess.Probe and Ess.Probe.nearest and Ess.Probe.nearest("buildings")
if target then
    Ess.Log("[recipe] machine: printing the machine of " .. tostring(Ess.Named(target)))
    Ess.Machine.print(target)
    -- To DRIVE it: resolve the piece you want, then set its state. Node addressing is per-object --
    -- inspect the print() output (or use a known hardpoint) before forcing a state:
    --   local piece = Ess.Machine.link(target, "hp_snap_<piece>")
    --   Ess.Machine.set(piece or target, "<nodeNameOrHash>", "CollapseState")
else
    Ess.Log("[recipe] machine: no building nearby to inspect (move near one and re-run)")
end

-- let the listener run briefly, then tidy up
Ess.Loop.start("recipe_machine_watch", 5, function() stop(); return false end)

-- PASS = the surface answered deterministically: the vocabulary is populated, a known hash reverses to its
-- name, and onChange handed back a stop(). (Whether a live transition fires is what smoke.py in a running
-- game confirms -- this recipe arms it and says what it saw.)
local ok = (#Ess.Machine.vocab() > 0)
    and (Ess.Machine.name("0x7687DF41") == "DestroyedState")
    and (type(stop) == "function")
Ess.Log("[SMOKE] machine: " .. (ok and "PASS" or "FAIL"))
