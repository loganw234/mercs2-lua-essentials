-- Ess/62_triggers.lua -- Ess.Triggers: named triggers + validated logic gates over Ess.Raw.Triggers.
--
-- API:
--   Ess.Triggers.arm(spec, onFire, tracker) -> cancel()             same as Ess.Raw.Triggers.arm
--   Ess.Triggers.armNamed(id, spec, onFire, tracker) -> cancel()    like arm(), but registers `id` for gate()
--   Ess.Triggers.gate(inputs, need, onFire, tracker) -> cancel()    fires once `need` of `inputs` have fired
--
-- ⚠ `id` lives in a SHARED FLAT namespace (`_known`/`_fired` below are module-level, not per-caller) --
-- the exact same shape of problem `Ess.SaveVar.ns(prefix)` exists to solve elsewhere in this framework.
-- Two independent systems both calling `armNamed("start", ...)` WILL silently collide: one's trigger
-- firing satisfies the other's gate too. `Ess.Contract` avoids this by prefixing every id with a
-- per-instance `ns` string before it ever reaches these tables (see 82_contract_encounter.lua) -- do the
-- same in your own code (e.g. `armNamed(myModName .. ":start", ...)`) if you're calling this directly.

local Ess = _G.Ess
Ess.Triggers = Ess.Triggers or {}
Ess.Triggers._fired = Ess.Triggers._fired or {}
Ess.Triggers._known = Ess.Triggers._known or {}

function Ess.Triggers.arm(spec, onFire, tracker)
    return Ess.Raw.Triggers.arm(spec, onFire, tracker)
end

-- Ess.Triggers.armNamed(id, spec, onFire, tracker) -> cancel()
-- Same as arm(), but registers `id` so a later Ess.Triggers.gate can name it as one of its `inputs`.
function Ess.Triggers.armNamed(id, spec, onFire, tracker)
    Ess.Triggers._known[id] = true
    return Ess.Raw.Triggers.arm(spec, function()
        Ess.Triggers._fired[id] = true
        if onFire then onFire() end
    end, tracker)
end

-- Ess.Triggers.gate(inputs, need, onFire, tracker) -> cancel()
-- Fires once `need` (default: ALL of them) of the NAMED triggers listed in `inputs` have fired.
--
-- CONFIRMED FIX for a real gap found reading ContractFramework.lua this session (Known Bug #2):
-- `_startSupport`'s gate handling (`kind="all"/"count"`) polls `inst.trigFired[id]` for each of a gate's
-- `inputs`, but that flag is ONLY ever set inside `trigAction`, which only runs for a NAMED `def.triggers`
-- entry firing -- an input id that actually belongs to a `def.support`/`def.waypoints` entry (even one
-- with its own inline `trigger` condition) never sets that flag, so the gate polls forever and silently
-- never satisfies, contradicting the framework's own documented worked example. This version validates
-- every input against `_known` (ids actually registered via armNamed) at gate-creation time and logs
-- loudly for any that aren't -- fail loud instead of a gate that quietly never fires.
function Ess.Triggers.gate(inputs, need, onFire, tracker)
    inputs = inputs or {}
    need = need or #inputs
    if #inputs == 0 then
        -- CONFIRMED real gap found on a deep re-read: `need > 0` below (deliberately, to stop an empty
        -- gate from firing immediately) means an empty `inputs` table just polls forever and NEVER fires
        -- OR stops on its own -- an unbounded leak without a tracker. Same "fail loud" treatment as an
        -- unknown id, since this was previously silent.
        Ess.Log("Triggers.gate: called with an empty inputs list -- this gate will poll forever and " ..
            "never fire; pass a tracker so it at least gets cleaned up, or fix the inputs list")
    end
    for _, id in ipairs(inputs) do
        if not Ess.Triggers._known[id] then
            Ess.Log("Triggers.gate: input '" .. tostring(id) .. "' was never armed via armNamed -- " ..
                "this gate can NEVER be satisfied by it as written, fix the id or arm it first")
        end
    end
    local active = true
    local function poll()
        if not active then return end
        local n = 0
        for _, id in ipairs(inputs) do if Ess.Triggers._fired[id] then n = n + 1 end end
        if n >= need and need > 0 then
            if onFire then onFire() end
            return
        end
        local h = Event.Create(Event.TimerRelative, { 0.4 }, poll)
        if tracker then tracker:event(h) end
    end
    poll()
    return function() active = false end
end
