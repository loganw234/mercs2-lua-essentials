-- Ess/15_machine.lua -- Ess.Machine: the object's destruction / entity STATE MACHINE as a live control surface.
--
-- Every destructible in the world runs a state machine keyed on a GLOBAL vocabulary of state hashes --
-- `PristineState`, `DamagedState`, `DestroyedState`, `GoneState`, `CollapseState`, … -- shared across ALL
-- destructibles (they are not per-object labels). Damage drives transitions; each state runs an Enter/Exit
-- command script (SHOW/HIDE hierarchy subtrees, start emitters). This namespace lets you drive that machine
-- by hand -- "force this building to CollapseState and watch it" -- and listen to every transition, with the
-- hashes resolved to their names (via Ess.Names + the state vocabulary below).
--
-- Distinct from two neighbours with similar names: `Ess.State(name, defaults)` (22_state.lua) is the _G
-- persistence idiom; `Ess.Human.setState(char, posture)` (14_human.lua) is the HUMAN posture machine. This
-- is the OBJECT machine, the one destruction runs on.
--
-- API:
--   Ess.Machine.set(uGuid, node, state) -> bool     force a node of an object's machine to a state.
--                                                    `node`/`state` are a NAME (hashed for you) or a bare
--                                                    "0xHASH". State is validated against the vocabulary --
--                                                    a novel name ships but is never reached by damage, so
--                                                    an unknown one is rejected (Ess.DEBUG) rather than run.
--   Ess.Machine.link(uGuid, hardpoint) -> uSub|nil  resolve a linked sub-part by its hardpoint name/hash
--                                                    (ObjectState.GetLinkGuid) -- a multi-part building's
--                                                    pieces are addressed this way, and set() is node-keyed.
--   Ess.Machine.onChange(fn) -> stop()              fn(uGuid, sState, sNode) on EVERY transition, with the
--                                                    state/node hashes resolved to names where known. uGuid
--                                                    is the raw, actionable object guid.
--   Ess.Machine.name(hashOrGuid) -> sName           a state guid/"0xHASH" -> its vocabulary name, else the
--                                                    bare hash (never a guessed name).
--   Ess.Machine.print(uGuid)                        dump the object's live machine to the loader log
--                                                    (ObjectState.PrintStateMachine).
--   Ess.Machine.STATES / .vocab()                   the known state-name vocabulary.
--
-- ✅ SMOKE-TESTED LIVE over the lua-bridge in a running retail game (call shapes from resident/oilrig.lua):
--   * every native exists and is callable (`ObjectState.SetState`/`GetLinkGuid`/`PrintStateMachine`,
--     `String.GetHash`, `Sys.GuidToString`/`StringToGuid`, `Object.GetHealth`);
--   * `String.GetHash` returns the EXACT vocabulary hashes below (CollapseState=0x694683EB,
--     PristineState=0xACB51200, DestroyedState=0x7687DF41, …), and `name()` reverses them;
--   * `set()` drove a real building's 8 structural nodes to DestroyedState -- returned true for all 8, and
--     the engine reported each transition back through `onChange` (chained onto the world's own OnStateChange,
--     state hashes resolved to names live, uncracked states falling back to the bare hash as intended). This
--     is a LOGICAL state change (the object stays alive); visible destruction is the damage path -- see set();
--   * `set()` refuses a state name outside the vocabulary before calling the engine.
--
-- ⚠ onChange hooks the GLOBAL `OnStateChange`. Resident mission scripts define their own; this CHAINS any it
-- finds (both fire) rather than clobbering it. But Lua globals are last-write-wins, so a resident script
-- that defines `function OnStateChange` AFTER Ess loads shadows this dispatcher -- your handlers simply stop
-- receiving, they never break the mission. Documented, not silently assumed.

local Ess = _G.Ess

Ess.Machine = Ess.Machine or {}

-- The global state vocabulary. Keyed by hash STRING ("0x…") -- like Ess.Names, and for the same reason: this
-- is Lua 5.1 with 32-bit floats, and a table keyed by the numeric hash would collide high values. The engine
-- hands these to Lua as GUIDs, which stringify through Sys.GuidToString to exactly this form.
--   * The first nine are CRACKED and authoritative (state_machine_destruction_code_map.md §29 — code-literal
--     and rainbow-verified against the retail exe).
--   * The last four are names the shipped Lua uses (resident/oilrig.lua et al.); the name is real and the
--     hash is String.GetHash of it, so they are safe to reverse.
-- Two more core hashes (0x381BE6A4, 0xCE603754) and oilrig's 0x28825D4C are real but UNCRACKED — deliberately
-- absent, so name() returns their bare hash rather than a fabricated label.
Ess.Machine.STATES = {
    ["0x0ACE072A"] = "InitState",        ["0xACB51200"] = "PristineState",
    ["0x5A6E8927"] = "InitDamagedState", ["0x1D5575A1"] = "DamagedState",
    ["0x5D308F4F"] = "InitDestroyedState", ["0x7687DF41"] = "DestroyedState",
    ["0x92791EBB"] = "StartDestroyedState", ["0xCA261E5B"] = "GoneState",
    ["0xA530B827"] = "DetachState",
    ["0x4C88281B"] = "FireDebrisState",  ["0x004641A5"] = "FireDestroyedState",
    ["0x694683EB"] = "CollapseState",    ["0x0753C8F7"] = "CollapseFireState",
}

-- name -> true, derived once from STATES, for the set() validation (a name the damage system will actually
-- reach). Built here rather than hand-kept so it can never drift from the table above.
local KNOWN = {}
for _, name in pairs(Ess.Machine.STATES) do KNOWN[name] = true end

-- Ess.Machine.vocab() -> sorted array of known state names (for a menu, a doc, or an autocomplete).
function Ess.Machine.vocab()
    local out = {}
    for name in pairs(KNOWN) do out[#out + 1] = name end
    table.sort(out)
    return out
end

-- Turn a NAME or a bare "0xHASH" into the hash VALUE the ObjectState natives take. A name is hashed by the
-- engine's own String.GetHash (== pandemic_hash_m2, so it matches every shipped call); a "0x…" string is
-- turned back into the guid/hash value via Sys.StringToGuid (the same inverse Ess.Unname uses). Returns nil
-- for anything that is neither, so a typo can't silently sail through as some other hash.
local function toHashValue(x)
    if type(x) ~= "string" or x == "" then return nil end
    if x:match("^0[xX]%x+$") then
        local ok, g = Ess.Safe.quiet(Sys.StringToGuid, x)
        return ok and g or nil
    end
    local ok, h = Ess.Safe.quiet(String.GetHash, x)
    return ok and h or nil
end

-- Ess.Machine.name(hashOrGuid) -> sName -- resolve a state to its vocabulary name for legible output. Accepts
-- the guid the engine hands OnStateChange (stringified via Ess.Name) or a "0x…" string directly. Falls back
-- to Ess.Names (in case it's really an asset/node hash), then to the bare hash -- never a guess.
function Ess.Machine.name(hashOrGuid)
    local s = hashOrGuid
    if type(s) ~= "string" then s = Ess.Name(hashOrGuid) end   -- a guid -> "0x…"
    if type(s) ~= "string" then return tostring(hashOrGuid) end
    local up = s:gsub("^0[xX]", ""):upper()
    up = "0x" .. string.rep("0", math.max(0, 8 - #up)) .. up
    return Ess.Machine.STATES[up] or (Ess.Names and Ess.Names.of(up)) or up
end

-- Ess.Machine.set(uGuid, node, state) -> bool -- force a node of the object's machine to a state.
--
-- NOTE (live-observed): this drives the machine's LOGICAL state and fires OnStateChange, but it is not a
-- destruction shortcut. Setting a building's nodes to `DestroyedState` flips the state (and reports back)
-- while the object stays alive and intact -- to actually DESTROY something, damage it to 0 / `Ess.Object.kill`
-- (the engine's break-pieces path, which is asynchronous: `alive` stays true for a few frames after). The
-- state that PLAYS the wreck (fires/explosion/kill-self) is `StartDestroyedState`, per the destruction code
-- map. `node` must be a real node hash (from `onChange`/`print`/`link`); node `0x0` is not valid.
function Ess.Machine.set(uGuid, node, state)
    if not uGuid then return Ess.Safe.reject("Ess.Machine.set", "no guid") end
    if type(state) == "string" and not state:match("^0[xX]%x+$") and not KNOWN[state] then
        -- A state name outside the global vocabulary shipping-but-dead is the exact trap M0193/the damage
        -- system embody: the machine never transitions to a name damage doesn't know. Refuse rather than
        -- issue a call that looks like it worked. (A bare 0xHASH is allowed through -- the author is being
        -- explicit and may know a state we haven't cracked, e.g. oilrig's 0x28825D4C.)
        return Ess.Safe.reject("Ess.Machine.set", "'" .. state .. "' is not a known state -- expected one of "
            .. table.concat(Ess.Machine.vocab(), ", ") .. " (or a bare 0xHASH)")
    end
    local nodeH = toHashValue(node)
    if nodeH == nil then return Ess.Safe.reject("Ess.Machine.set", "node is not a name or 0xHASH") end
    local stateH = toHashValue(state)
    if stateH == nil then return Ess.Safe.reject("Ess.Machine.set", "state is not a name or 0xHASH") end
    local ok = Ess.Safe.quiet(ObjectState.SetState, uGuid, nodeH, stateH)
    return ok == true
end

-- Ess.Machine.link(uGuid, hardpoint) -> uSub|nil -- resolve a linked sub-part (a building's tower, a rig's
-- crane) by hardpoint name or hash, so you have a guid to set()/read. Wraps ObjectState.GetLinkGuid.
function Ess.Machine.link(uGuid, hardpoint)
    if not uGuid then return Ess.Safe.reject("Ess.Machine.link", "no guid") end
    local h = toHashValue(hardpoint)
    if h == nil then return Ess.Safe.reject("Ess.Machine.link", "hardpoint is not a name or 0xHASH") end
    local ok, sub = Ess.Safe.quiet(ObjectState.GetLinkGuid, uGuid, h)
    if ok then return sub end
    return nil
end

-- Ess.Machine.print(uGuid) -- dump the live machine (nodes + current states) to the loader log. The engine's
-- own ObjectState.PrintStateMachine; the read-a-value getter it does NOT expose, so this is how you inspect.
function Ess.Machine.print(uGuid)
    if not uGuid then return Ess.Safe.reject("Ess.Machine.print", "no guid") end
    Ess.Safe.quiet(ObjectState.PrintStateMachine, uGuid)
end

-- ---- the reactive read side: OnStateChange -------------------------------------------------------------
-- The engine calls a global OnStateChange(guid, nodeHash, stateHash) on every transition. We install one
-- dispatcher, enrich its args to names, and fan out to registered handlers. Any OnStateChange already present
-- when we install is CHAINED (called after our handlers), so we extend rather than replace it.
Ess.Machine._handlers = Ess.Machine._handlers or {}
Ess.Machine._n = Ess.Machine._n or 0

local function ensureDispatcher()
    if Ess.Machine._installed then return end
    Ess.Machine._prior = _G.OnStateChange           -- may be nil, or a mission's own -- keep it either way
    _G.OnStateChange = function(uGuid, uNode, uState)
        -- resolve once, share with every handler; never let one handler's error stop the others OR the chain
        local sState = Ess.Machine.name(uState)
        local sNode = (Ess.Named and Ess.Named(uNode)) or Ess.Name(uNode) or tostring(uNode)
        for _, h in ipairs(Ess.Machine._handlers) do pcall(h.fn, uGuid, sState, sNode) end
        if type(Ess.Machine._prior) == "function" then pcall(Ess.Machine._prior, uGuid, uNode, uState) end
    end
    Ess.Machine._installed = true
end

-- Ess.Machine.onChange(fn) -> stop() -- fn(uGuid, sState, sNode) on every transition. Returns a stop() that
-- unregisters just this handler (the dispatcher and any chained prior stay in place).
function Ess.Machine.onChange(fn)
    if type(fn) ~= "function" then
        Ess.Safe.reject("Ess.Machine.onChange", "handler is not a function -- not armed")
        return function() end
    end
    ensureDispatcher()
    Ess.Machine._n = Ess.Machine._n + 1
    local id = Ess.Machine._n
    Ess.Machine._handlers[#Ess.Machine._handlers + 1] = { id = id, fn = fn }
    return function()
        for i, h in ipairs(Ess.Machine._handlers) do
            if h.id == id then table.remove(Ess.Machine._handlers, i); return end
        end
    end
end
