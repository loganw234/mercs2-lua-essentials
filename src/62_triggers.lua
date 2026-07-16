-- Ess/62_triggers.lua -- Ess.Triggers: named triggers + validated logic gates over Ess.Raw.Triggers.
--
-- API:
--   Ess.Triggers.arm(spec, onFire, tracker) -> cancel()   same as Ess.Raw.Triggers.arm (stateless)
--   Ess.Triggers.scope() -> scope                          an ISOLATED named-trigger/gate namespace
--     scope:arm(spec, onFire, tracker) -> cancel()
--     scope:armNamed(id, spec, onFire, tracker) -> cancel()   register `id` so a gate can name it as input
--     scope:gate(inputs, need, onFire, tracker) -> cancel()   fires once `need` of `inputs` have fired
--     scope:declare(id)      register an id that fires by some OTHER mechanism (so a gate can reference it)
--     scope:markFired(id)    mark such an id as fired (call before triggering its action, so a chained
--                            gate/reference sees it satisfied)
--
-- WHY SCOPES (structural fix for a real collision): named-trigger ids and gate inputs cross-reference by
-- NAME, so armNamed and gate must share state. An earlier version kept that state in ONE module-level pair
-- of tables (`_known`/`_fired`) shared by every caller -- two independent systems both calling
-- `armNamed("start", ...)` would silently collide (one's trigger firing satisfied the other's gate). Now
-- each `scope()` owns its own `_known`/`_fired`, so two scopes CAN'T interfere no matter what ids they
-- reuse -- the collision is impossible by construction, not merely warned about. `Ess.Contract` gives each
-- running contract instance its own scope; a direct caller makes one per independent group of triggers.
-- (`Ess.Triggers.arm` stays top-level because it's stateless -- it never names anything or shares a table.)

local Ess = _G.Ess
Ess.Triggers = Ess.Triggers or {}

-- Stateless: fire-and-forget a single condition. No shared state, so it stays a plain top-level call.
function Ess.Triggers.arm(spec, onFire, tracker)
    return Ess.Raw.Triggers.arm(spec, onFire, tracker)
end

-- Ess.Triggers.scope() -> scope -- an isolated named-trigger/gate namespace. Cheap; make as many as you
-- like. Nothing in one scope's _known/_fired is visible to any other scope.
function Ess.Triggers.scope()
    local S = { _known = {}, _fired = {} }

    function S:arm(spec, onFire, tracker)
        return Ess.Raw.Triggers.arm(spec, onFire, tracker)
    end

    -- scope:armNamed(id, spec, onFire, tracker) -> cancel()
    -- Like arm(), but registers `id` in THIS scope so a later scope:gate can name it as one of its inputs,
    -- and marks it fired (in this scope) the moment it fires so a gate referencing it sees it satisfied.
    function S:armNamed(id, spec, onFire, tracker)
        S._known[id] = true
        return Ess.Raw.Triggers.arm(spec, function()
            S._fired[id] = true
            if onFire then onFire() end
        end, tracker)
    end

    -- scope:declare(id) / scope:markFired(id) -- for an id whose firing is driven by something OTHER than
    -- armNamed (a custom poll, or a gate's own id needing to be referenceable). declare() makes a gate's
    -- input-validation accept it; markFired() records that it fired (call it BEFORE running the id's action
    -- so a chained gate/reference observes it as satisfied in the same tick).
    function S:declare(id)   S._known[id] = true end
    function S:markFired(id) S._fired[id] = true end

    -- scope:gate(inputs, need, onFire, tracker) -> cancel()
    -- Fires once `need` (default: ALL of them) of the named ids in `inputs` have fired IN THIS SCOPE.
    -- Validates each input against this scope's _known and warns loudly on any that were never registered
    -- (a gate that can never be satisfied), and on an empty inputs list (a gate that polls forever) --
    -- fail loud instead of a gate that quietly never fires.
    function S:gate(inputs, need, onFire, tracker)
        inputs = inputs or {}
        need = need or #inputs
        if #inputs == 0 then
            Ess.Log("Triggers.gate: called with an empty inputs list -- this gate will poll forever and " ..
                "never fire; pass a tracker so it at least gets cleaned up, or fix the inputs list")
        end
        for _, id in ipairs(inputs) do
            if not S._known[id] then
                Ess.Log("Triggers.gate: input '" .. tostring(id) .. "' was never armed/declared in this " ..
                    "scope -- this gate can NEVER be satisfied by it as written, fix the id or arm it first")
            end
        end
        local active = true
        local function poll()
            if not active then return end
            local n = 0
            for _, id in ipairs(inputs) do if S._fired[id] then n = n + 1 end end
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

    return S
end
