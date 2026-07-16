-- Ess/80_contract.lua -- Ess.Contract: the ephemeral-mission engine, absorbed from ContractFramework.lua.
-- Third of three absorptions (uilib -> Ess.UI, ModNet -> Ess.Net, this -> Ess.Contract).
--
-- WHY THIS IS SAFE (read once): the native contract system corrupts saves because it registers into
-- WifMissionData, serializes MrxTask nodes INTO the save, and drives missions through dynamic_import +
-- mrxbriefing + the MrxState load gate. This framework touches NONE of that. A contract is an EPHEMERAL
-- runtime object built only from safe primitives (Pg.Spawn / Event.* / Object.* / MrxPmc). It never
-- writes to the game save, so it can't corrupt one. Tradeoff: a contract does not survive a save/reload
-- (it's simply re-offered on the next level load).
--
-- MODDER API (unchanged from ContractFramework.lua, just under Ess.Contract now):
--   Ess.Contract.Register{ id=, title=, briefing=, reward={cash=,fuel=}, start={x,y,z,yaw},
--                          objectives = { Ess.Contract.Destroy{...}, Ess.Contract.Reach{...}, ... },
--                          onComplete=fn, onFail=fn }
--   Objective builders: .Destroy{} .Reach{} .Defend{} .Collect{} .Escort{} .Enter{} .Hold{} .Group{}
--                        .Interact{} .Verify{} .Extract{} .Race{} .Survive{} .Chase{} .Protect{} .StayInArea{}
--   Ess.Contract.Accept(idOrDef)  Ess.Contract.Abort()  Ess.Contract.Status()  Ess.Contract.List()
--   Ess.Contract.UI.Panel{...} / Ess.Contract.UI.Bar{...}  -- now REAL (aliased to Ess.UI), where
--     ContractFramework.lua's own version was only ever a stub placeholder (`C.UI = C.UI or {}`, never
--     implemented -- "need a .gfx; see README"). Reusing Ess.UI here instead of hand-rolling a second
--     widget implementation is the whole point of absorbing uilib first.
--
-- 81_contract_objectives.lua adds the 16 objective-type handlers (tHandlers); 82_contract_encounter.lua
-- adds the support-effects/relations/AI-orders/triggers subsystem, now built on Ess.Relations/
-- Ess.AIOrders/Ess.Triggers instead of re-hand-rolling that logic a second time.

import("MrxPmc")
import("MrxUtil")
import("MrxMusic")

local Ess = _G.Ess
Ess.Contract = Ess.Contract or {}
local C = Ess.Contract
C._registry = C._registry or {}   -- ordered array of defs (rebuilt each level load)
C._byId     = C._byId or {}        -- id -> def
C.tHandlers = C.tHandlers or {}
C.UI        = C.UI or {}

-- Contract.UI.Panel/.Bar -- real now, aliased straight to Ess.UI (see file header). No .gfx authoring
-- needed: ui_panel.gfx/ui_bar.gfx are the same movies Ess.UI itself already uses.
C.UI.Panel = Ess.UI.Panel
C.UI.Bar   = Ess.UI.Bar

-- Fresh registry each load (OnLoad re-runs). Nothing here persists into the game save.
C._registry, C._byId = {}, {}

-- ============================================================
-- Runtime engine (one live contract instance at a time)
-- ============================================================
-- Each objective (and each background condition) runs as a self-contained "task" holding its own
-- events/guids/markHandles, so several can run at once (parallel mode) and each tears down on its own.
-- markHandles holds Ess.Mark handles (replacing ContractFramework's own separately-tracked marks/markers
-- arrays -- Ess.Mark.object/.zone already return ONE combined handle covering all three surfaces).
local function track(task, u) if u then task.guids[#task.guids + 1] = u end return u end
local function objRgb()
    local ok, r, g, b = pcall(MrxUtil.GetPrimaryObjectiveRgb)
    if ok and r then return r, g, b end
    return 255, 200, 0
end

-- C._newTask() -> task
-- CONFIRMED LIVE bug this fixes: Ess.Triggers.arm/armNamed/gate AND Ess.AIOrders.command's `tracker`
-- parameter both expect an Ess.Track-shaped object (real `:event(handle)`/`:guid(uGuid)` methods) -- a
-- plain `{events={}, ...}` table literal passed as tracker crashes with "attempt to call method 'event'
-- (a nil value)" the moment a trigger actually schedules something, or "...'guid'..." the moment a
-- `defend` AI order spawns its anchor prop. Every task bucket in this file and
-- 82_contract_encounter.lua is built through this constructor instead of an inline table literal, so
-- it's always tracker-compatible with both consumers.
local TaskMT = { __index = {} }
function TaskMT.__index:event(handle)
    if handle then self.events[#self.events + 1] = handle end
    return handle
end
function TaskMT.__index:guid(u)
    if u then self.guids[#self.guids + 1] = u end
    return u
end
function C._newTask()
    return setmetatable({ events = {}, guids = {}, markHandles = {}, done = false }, TaskMT)
end

-- ---- HUD narration: the base game's objective tray (Hud.ObjectiveTray:SetSlotToText). Slot 1 = the
-- current objective line (persistent); slot 3 = transient "radio" chatter that clears itself.
local function hudLine(slot, text)
    if C._muteObj and slot == 1 then return end   -- a hideTracker contract draws its own HUD -> suppress the objective line
    if text == nil then pcall(function() Hud.ObjectiveTray:ClearSlot({ nSlot = slot }) end)
    else pcall(function() Hud.ObjectiveTray:SetSlotToText({ nSlot = slot, sText = tostring(text) }) end) end
end
local function hudSay(text, hold)                          -- one-shot radio line, auto-cleared
    if not text or text == "" then return end
    hudLine(3, tostring(text))
    pcall(Event.Create, Event.TimerRelative, { tonumber(hold) or 5 }, function() hudLine(3, nil) end)
    Ess.Log("Contract:   \"" .. tostring(text) .. "\"")
end
-- ints from a plain number OR a {min,max} range; used for randomised counts.
local function rspan(v) if type(v) == "table" then local a, b = v[1] or v.min or 0, v[2] or v.max or v[1] or 0
        return math.floor(a + math.randf(0, (b - a) + 0.999)) end
    return v end
local function rchance(c) return not c or c >= 1 or math.randf(0, 1) <= c end   -- true unless a <1 chance rolls against it

-- mark an EXISTING object as an objective on the three surfaces, via Ess.Mark. Returns the handle for
-- task-scoped cleanup (also appended to task.markHandles automatically).
local function mark(task, uGuid, kind)
    local r, g, b = objRgb()
    local h = Ess.Mark.object(uGuid, { kind = kind, rgb = { r, g, b } })
    task.markHandles[#task.markHandles + 1] = h
    return h
end
-- mark a ZONE via Ess.Mark.zone (spawns the TinyGeometry anchor + ground ring + destination blip).
-- Also appended to task.markHandles for the safety-net cleanup, but callers needing to unmark ONE
-- checkpoint early (race) can call Ess.Mark.clear(handle) on the returned handle directly at any time --
-- Ess.Mark.clear is safe to call twice on the same handle (Object.Remove on an already-gone guid just
-- no-ops through pcall).
local function markZone(task, x, y, z, radius)
    local r, g, b = objRgb()
    local h = Ess.Mark.zone(x, y, z, radius, { rgb = { r, g, b } })
    if h then task.markHandles[#task.markHandles + 1] = h end
    return h
end
local function addEv(task, e) if e then task.events[#task.events + 1] = e end return e end

local function cleanupTask(task)
    for _, e in ipairs(task.events) do pcall(Event.Delete, e) end
    for _, h in ipairs(task.markHandles) do Ess.Mark.clear(h) end
    for _, u in ipairs(task.guids) do pcall(Object.Remove, u) end
    task.events, task.markHandles, task.guids = {}, {}, {}
end

function C._CleanupAll(inst)
    for _, t in ipairs(inst.tasks or {}) do cleanupTask(t) end
    inst.tasks = {}
end

-- ---- target sourcing: an objective's targets may be SPAWNED, NAMED (placed), or LIVE-QUERIED ----
-- collectInArea mirrors ContractFramework's original two-independent-filter shape (faction AND label
-- both optionally applied) -- Ess.Probe.nearby only supports one filter, so this layers a second HasLabel
-- pass on top of it rather than extending Ess.Probe's own public contract for one consumer's needs.
local function hasLabel(u, lbl) local ok, r = pcall(Object.HasLabel, u, lbl); return ok and r end
local function collectInArea(x, y, z, r, kind, faction, label)
    local out = Ess.Probe.nearby(x, y, z, r, kind, faction)
    if not label then return out end
    local filtered = {}
    for _, u in ipairs(out) do if hasLabel(u, label) then filtered[#filtered + 1] = u end end
    return filtered
end
C._collectInArea = collectInArea   -- exposed for 82_contract_encounter.lua

-- safeSpawn(template, x, y, z, yaw) -> ok, uGuid
-- CONFIRMED real gap found auditing this port against FEATURE_SHEET.md's own Known Bug #8: a blank/
-- whitespace Pg.Spawn template string hard-CRASHES the engine (an empty name resolves to a null asset in
-- native C++), and pcall canNOT catch a native crash, only a Lua error -- every Ess helper that reaches
-- Pg.Spawn must validate the template BEFORE calling it, matching the guard already used in
-- Ess.Vehicle.followGhost/Ess.Bones.attachFX/Ess.UI.Menu's ctx:spawn. The ORIGINAL ContractFramework.lua's
-- own Pg.Spawn call sites (the direct ancestor of every one in this file and 81/82) never had this guard
-- either -- a contract author's typo'd blank tSpawns[1]/def.units spawn field could CTD the game. Fixed
-- here, not present in the original; every Contract Pg.Spawn call site in this file and 81/82 goes
-- through this instead of a bare pcall(Pg.Spawn, ...).
local function safeSpawn(template, x, y, z, yaw)
    if type(template) ~= "string" or template:match("^%s*$") then
        Ess.Log("Contract: blank spawn template rejected (would CTD Pg.Spawn)")
        return false, nil
    end
    return pcall(Pg.Spawn, template, x, y, z, yaw)
end

-- flat list of target guids from obj.tSpawns (spawned + tracked for removal), obj.tObjects (named
-- placements) and obj.tWhere (a live FastCollect query). Existing world objects are NOT tracked, so
-- they're never removed on cleanup.
local function resolveTargets(inst, task, obj)
    local out = {}
    for _, s in ipairs(obj.tSpawns or {}) do
        local ok, u = safeSpawn(s[1], s[2], s[3], s[4])
        if ok and u then track(task, u); if s[5] then pcall(Object.SetYaw, u, s[5]) end; out[#out + 1] = u end
    end
    for _, name in ipairs(obj.tObjects or {}) do
        local ok, u = pcall(Pg.GetGuidByName, name)
        if ok and u then out[#out + 1] = u end
    end
    local w = obj.tWhere
    if w and w.area then
        local a = w.area
        for _, u in ipairs(collectInArea(a.x or a[1], a.y or a[2], a.z or a[3], a.r or a[4] or 50, w.kind, w.faction, w.label)) do
            out[#out + 1] = u
        end
    end
    return out
end

-- table-driven reward payout (cash/fuel confirmed; support/equipment via MrxPmc)
local function grantReward(r)
    if type(r) ~= "table" then return end
    if r.cash then Ess.Player.giveCash(r.cash) end
    if r.fuel then Ess.Player.giveFuel(r.fuel) end
    if type(r.support) == "table" then for id, n in pairs(r.support) do pcall(MrxPmc.AddSupportQty, id, n) end end
    if type(r.equipment) == "table" then for _, id in ipairs(r.equipment) do pcall(MrxPmc.AddEquipment, id) end end
end

-- Native completion fanfare = the music sting + a HUD banner. sType MUST be one of the shipped
-- EventFanfare styles or Hud.EventFanfare:Commence crashes on its PDA-log concat, so we clamp it.
local FANFARE_TYPES = { contact = true, support = true, stockpile = true, landingzone = true,
    hvtcapture = true, hvtkill = true, bounty = true, outfit = true, highscore = true }
local function showFanfare(d)
    pcall(MrxMusic.PlayFanfare, true)
    local sType = d.fanfareType; if not FANFARE_TYPES[sType] then sType = "highscore" end
    local sText = d.fanfare or ((d.title or d.id) .. " complete")
    pcall(function() Hud.EventFanfare:Commence({ sType = sType, vText = sText }) end)
end

function C._finish(inst, bWin)
    if not inst.bActive then return end
    inst.bActive = false
    C._muteObj = nil                   -- restore the objective tray for normal contracts
    hudLine(1, nil); hudLine(3, nil)   -- clear the HUD objective + chatter lines
    if inst.musicOn then pcall(MrxMusic.StopSpecialMusic) end   -- return to the normal soundtrack
    local d = inst.def
    -- snapshot final objective state for the board's Status() (persists until the next Accept)
    local fin = {}
    for i = 1, #(d.objectives or {}) do fin[i] = { done = inst.objDone[i] == true } end
    C.finished = { result = bWin and "complete" or "failed", objectives = fin }
    if type(C.onFinish) == "function" then pcall(C.onFinish, C.finished.result) end
    if bWin then
        grantReward(d.reward)
        local r = d.reward or {}
        Ess.Log(string.format("*** COMPLETE '%s'  $%d / %d fuel ***", d.title or d.id, r.cash or 0, r.fuel or 0))
        showFanfare(d)
        if d.onComplete then pcall(d.onComplete) end
    else
        Ess.Log("xxx FAILED '" .. (d.title or d.id) .. "'")
        if d.onFail then pcall(d.onFail) end
    end
    if C._restoreRelations then C._restoreRelations(inst) end   -- put faction stances back the way we found them
    C._CleanupAll(inst)
    C.active = nil
end

-- run ONE objective as its own task; onDone(true|false) reports its outcome (exactly once)
function C._run(inst, obj, onDone)
    local task = C._newTask()
    inst.tasks[#inst.tasks + 1] = task
    local h = C.tHandlers[obj.sType]
    if not h then Ess.Log("no handler '" .. tostring(obj.sType) .. "'"); onDone(false); return task end
    Ess.Log(string.format("  objective (%s) - %s", obj.sType, obj.sDesc or ""))
    if obj.sDesc and obj.sType ~= "survive" then hudLine(1, "[white]" .. obj.sDesc) end   -- survive draws its own countdown line
    if obj.sMsg then hudSay(obj.sMsg, 6) end                                               -- per-objective radio line
    h(inst, task, obj, function(bOk)
        if task.done or not inst.bActive then return end
        task.done = true
        cleanupTask(task)
        onDone(bOk)
    end)
    return task
end

-- Run an objective LIST in a mode ("sequential" default | "parallel"), calling onDone(true|false)
-- once the whole list resolves. markFn(index, ok) fires as each objective in THIS list finishes.
function C._runList(inst, objs, mode, onDone, markFn)
    if mode == "parallel" then
        local nReq, doneFlag = 0, false
        for _, o in ipairs(objs) do if not o.optional then nReq = nReq + 1 end end
        if nReq == 0 then return onDone(true) end
        for idx, obj in ipairs(objs) do
            C._run(inst, obj, function(bOk)
                if not inst.bActive or doneFlag then return end
                if markFn then markFn(idx, bOk) end
                if obj.optional then
                    if bOk and obj.bonus then Ess.Player.giveCash(obj.bonus)
                        Ess.Log("  bonus objective complete (+$" .. obj.bonus .. ")") end
                elseif bOk == false then
                    doneFlag = true; onDone(false)
                else
                    nReq = nReq - 1
                    if nReq <= 0 then doneFlag = true; onDone(true) end
                end
            end)
        end
    else
        local i = 0
        local function step(prevOk)
            if not inst.bActive then return end
            if prevOk == false then return onDone(false) end
            i = i + 1
            local obj = objs[i]
            if not obj then return onDone(true) end
            C._run(inst, obj, function(ok) if markFn then markFn(i, ok) end step(ok) end)
        end
        step(true)
    end
end

-- background conditions running for the WHOLE contract: an overall time limit, plus any def.fail
-- conditions (protect a target / stay in an area). A violated condition fails the contract.
function C._startBackground(inst)
    local d = inst.def
    if C._spawnUnits then C._spawnUnits(inst) end   -- spawn & group def.units FIRST so orders can command them
    if d.timeLimit then
        local task = C._newTask()
        inst.tasks[#inst.tasks + 1] = task
        addEv(task, Event.Create(Event.TimerRelative, { d.timeLimit }, function()
            if inst.bActive then Ess.Log("time limit reached"); C._finish(inst, false) end
        end))
    end
    for _, cond in ipairs(d.fail or {}) do
        C._run(inst, cond, function(bOk) if inst.bActive and bOk == false then C._finish(inst, false) end end)
    end
    if C._startSupport then C._startSupport(inst) end   -- airstrikes / artillery / reinforcements + generic triggers
end

function C.Accept(idOrDef)
    -- co-op: only the host runs contracts. This checks the NATIVE Net.* functions directly (not
    -- Ess.Net/ModNet's own IsCoop/IsHost) -- CONFIRMED real gotcha: in SINGLE-PLAYER, Net.IsClient() can
    -- report true, which silently no-ops every accept if gated on IsClient() alone. Gate on
    -- IsMultiplayer first so SP always proceeds; only a REAL multiplayer client is ever skipped.
    if Net.IsMultiplayer() and Net.IsClient() then return end
    local def = type(idOrDef) == "string" and C._byId[idOrDef] or idOrDef
    if type(def) ~= "table" then Ess.Log("Contract.Accept: unknown contract"); return end
    if C.active and C.active.bActive then C.Abort() end
    C.finished = nil   -- clear any prior result so Status() reflects THIS contract
    if def.fResolve then pcall(def.fResolve, def) end   -- fill in any dynamic (e.g. player-relative) coords
    -- CONFIRMED LIVE quirk worth remembering: tostring() on a plain table in this engine's Lua does NOT
    -- give a short "table: 0x..." address string the way stock Lua does -- it dumps the table's own
    -- field contents instead. Harmless for uniqueness (still a distinct string per instance) but ugly
    -- and verbose in logs -- a real incrementing counter avoids relying on that surprising behavior at
    -- all, for anything (like a per-instance namespace key) that just needs a short, unique id.
    C._nextInstId = (C._nextInstId or 0) + 1
    local inst = { def = def, bActive = true, tasks = {}, objDone = {}, startStamp = Sys.RealTimeStamp(),
                   _id = "c" .. C._nextInstId }
    C.active = inst
    Ess.Log("accepted '" .. (def.title or def.id) .. "'" .. (def.mode == "parallel" and " [parallel]" or ""))
    local function begin()
        if not inst.bActive then return end
        C._muteObj = def.hideTracker                                  -- HUD-owning modes suppress the objective tray line
        Ess.Log("starting '" .. (def.title or def.id) .. "' (" .. #(def.objectives or {}) .. " objectives)")
        if def.intro then hudSay(def.intro, 7) end                    -- opening radio line

        -- the OPTIONAL relations/support/trigger setup must NEVER block the core objective runner:
        -- pcall each so a bad relation/support/trigger can't kill begin() before C._runList.
        if C._applyRelations then local ok, e = pcall(C._applyRelations, inst); if not ok then Ess.Log("relations setup error -> " .. tostring(e)) end end
        local sbOk, sbE = pcall(C._startBackground, inst); if not sbOk then Ess.Log("support/trigger setup error -> " .. tostring(sbE)) end
        -- ESCAPE HATCH: after heroes are placed + the contract's background is up, hand off to a bespoke
        -- gamemode. pcall'd so it can NEVER block the objective runner.
        if def.onBegin then local obOk, obE = pcall(def.onBegin, inst); if not obOk then Ess.Log("onBegin error -> " .. tostring(obE)) end end
        C._runList(inst, def.objectives or {}, def.mode, function(ok) C._finish(inst, ok) end,
                   function(i, ok) if ok then inst.objDone[i] = true end end)
    end
    if def.start then
        local s = def.start
        local locs = {}
        if type(s[1]) == "table" then                     -- a LIST of spawns (co-op: one location per hero)
            for i, p in ipairs(s) do locs[i] = { p.x or p[1], p.y or p[2], p.z or p[3], p.yaw or p[4] or 0 } end
        else                                              -- a single spawn ({x=,y=,z=,yaw=} or {x,y,z,yaw})
            locs[1] = { s.x or s[1], s.y or s[2], s.z or s[3], s.yaw or s[4] or 0 }
        end
        pcall(MrxUtil.TeleportHeroesToLocations, locs, begin)   -- extra locations are ignored in single-player
    else
        begin()
    end
end

function C.Abort() if C.active then C._finish(C.active, false) end end

-- ============================================================
-- Objective builders (friendly sugar -> internal shape)
-- ============================================================
local function xyz(t) if t.x then return t.x, t.y, t.z else return t[1], t[2], t[3] end end
local function zone(at, radius, dr) if not at then return { r = radius or dr } end local x, y, z = xyz(at); return { x = x, y = y, z = z, r = radius or dr } end
-- passthrough optional/bonus (parallel mode) + mirror sType/sDesc to type/desc for the GFx board
local function ob(o, t) o.optional = t.optional; o.bonus = t.bonus; o.sMsg = t.msg; o.type = o.sType; o.desc = o.sDesc; return o end

function C.Destroy(t) return ob({ sType = "destroy", sDesc = t.desc, tSpawns = t.spawns, tObjects = t.objects, tWhere = t.where, nQuota = t.quota }, t) end
function C.Reach(t)   return ob({ sType = "reach",   sDesc = t.desc, tZone = zone(t.at, t.radius, 15) }, t) end
function C.Defend(t)  return ob({ sType = "defend",  sDesc = t.desc, nTime = t.time, sTarget = t.target }, t) end
function C.Collect(t) return ob({ sType = "collect", sDesc = t.desc, tItems = t.items, nQuota = t.quota, nRadius = t.radius }, t) end
function C.Escort(t)  return ob({ sType = "escort",  sDesc = t.desc, tSpawn = t.spawn, tZone = zone(t.to, t.radius, 15) }, t) end
function C.Enter(t)   return ob({ sType = "enter",   sDesc = t.desc, sTarget = t.target, tSpawn = t.spawn, sSeat = t.seat }, t) end
function C.Hold(t)    return ob({ sType = "hold",    sDesc = t.desc, tZone = zone(t.at, t.radius, 15), nTime = t.time }, t) end
function C.Group(t)    return ob({ sType = "group",    sDesc = t.desc, sMode = t.mode, tObjectives = t.objectives }, t) end
function C.Interact(t) local z; if t.at then local x, y, zz = xyz(t.at); z = { x = x, y = y, z = zz } end
                       return ob({ sType = "interact", sDesc = t.desc, sTarget = t.target, tSpawn = t.spawn, tZone = z, nRadius = t.radius or 4, nTime = t.time }, t) end
function C.Verify(t)   return ob({ sType = "verify",   sDesc = t.desc, sTarget = t.target, tSpawn = t.spawn, bCapture = t.capture, nCaptureHealth = t.captureHealth, nRadius = t.radius }, t) end
function C.Extract(t)  return ob({ sType = "extract",  sDesc = t.desc, tZone = zone(t.at, t.radius, 15), nBoardTime = t.boardTime, sHeli = t.heli }, t) end
function C.Race(t)     return ob({ sType = "race",     sDesc = t.desc, tCheckpoints = t.checkpoints, nRadius = t.radius, nTime = t.time }, t) end
function C.Survive(t)  return ob({ sType = "survive",  sDesc = t.desc, nTime = t.time, sTarget = t.target }, t) end
function C.Chase(t)    return ob({ sType = "chase",    sDesc = t.desc, tSpawns = t.spawns, tObjects = t.objects, tWhere = t.where, tZone = zone(t.escapeAt, t.escapeRadius, 15), nTime = t.time, nHaste = t.haste }, t) end
-- background fail-conditions for a contract's `fail = { ... }` list
function C.Protect(t)    return { sType = "protect", type = "protect", sDesc = t.desc, desc = t.desc, sTarget = t.target, tSpawn = t.spawn } end
function C.StayInArea(t) return { sType = "stay", type = "stay", sDesc = t.desc, desc = t.desc, tZone = zone(t.at, t.radius, 100) } end

-- ============================================================
-- Registration
-- ============================================================
function C.Register(def)
    if type(def) ~= "table" or not def.id then Ess.Log("Contract.Register: table with an 'id' required"); return end
    if not def.objectives or #def.objectives == 0 then Ess.Log("Contract.Register: '" .. def.id .. "' has no objectives") end
    if not C._byId[def.id] then C._registry[#C._registry + 1] = def end
    C._byId[def.id] = def
    Ess.Log("registered '" .. def.id .. "'" .. (def.title and (" (" .. def.title .. ")") or ""))
end
function C.List() return C._registry end
C.All = C.List   -- alias the GFx board's preferred detection name

-- ============================================================
-- Status - the live state of the active contract, in exactly the shape a GFx board reads through an
-- API.status() adapter: { finished, progress, timeLeft, objectives = { {done=bool}, ... } }
-- ============================================================
function C.Status()
    if C.finished then
        return { finished = C.finished.result,
                 progress = (C.finished.result == "complete") and 1 or nil,
                 objectives = C.finished.objectives }
    end
    local inst = C.active
    if not inst or not inst.bActive then return nil end
    local objs = inst.def.objectives or {}
    local st, done = { objectives = {} }, 0
    for i = 1, #objs do
        local d = inst.objDone[i] == true
        st.objectives[i] = { done = d }
        if d then done = done + 1 end
    end
    if #objs > 0 then st.progress = done / #objs end
    if inst.def.timeLimit and inst.startStamp then
        local ok, e = pcall(Sys.TimeStampGetElapsed, inst.startStamp)
        if ok and e then st.timeLeft = math.max(0, inst.def.timeLimit - e) end
    end
    return st
end

-- Each src/*.lua file is wrapped in its own do...end block by build/merge.py, so these `local` helpers
-- aren't visible from 81_contract_objectives.lua / 82_contract_encounter.lua directly -- expose them as
-- C._xxx fields (private-by-convention, not part of the modder-facing API) so the other two files can
-- reach them without duplicating this logic a second time. Placed at the very end of the file, after
-- every referenced local is actually defined (a forward reference here would just capture nil).
C._track, C._mark, C._markZone, C._addEv = track, mark, markZone, addEv
C._hudLine, C._hudSay, C._rspan, C._rchance = hudLine, hudSay, rspan, rchance
C._resolveTargets, C._grantReward, C._xyz = resolveTargets, grantReward, xyz
C._safeSpawn = safeSpawn
