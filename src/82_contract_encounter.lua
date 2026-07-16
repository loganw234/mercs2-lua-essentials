-- Ess/82_contract_encounter.lua -- Ess.Contract's relationships / support call-ins / AI orders / generic
-- triggers, absorbed from ContractFramework.lua -- now built on Ess.Relations/Ess.AIOrders/Ess.Triggers
-- instead of re-hand-rolling that logic a third time (it was already extracted from this exact source
-- earlier tonight as Group G).
--
--   def.relations = { { "Allied","PMC","friend" }, { "VZ","PMC","enemy" }, { "VZ","Allied","enemy" } }
--   def.units     = { { spawn=, x=,y=,z=, yaw=, group="A" }, ... }         framework-owned, grouped units
--   def.waypoints = { { id=, group="A", behavior="patrol"|"move"|"defend"|"attack"|"hold"|"face"|
--                       "follow"|"flee"|"enter"|"deploy"|"animate", points={ {x,y,z},... } | at={x,y,z},
--                       radius=, speed=, loop=, target=, trigger= }, ... }
--   def.support   = { { id=, effect=, at={x,y,z}, radius=, owner=, <params>, trigger= }, ... }
--   def.triggers  = { { id=, kind="proximity"|"recurring"|"once"|"onDestroy"|"health"|"objective"|
--                       "cleared"|"all"|"count", ... } }
-- triggers' fires={} and support/order trigger={ref=id} may target support ids OR waypoint ids.
-- effects: artillery(ammo) / flyby(=airstrike, vehicle) / bombingrun(vehicle+ammo) / heli /
--   reinforce(deliver=copter|paradrop) / say(text) / music(cue) / vfx(particle) / damage(target,pct|kill) /
--   vo(lines) / shake(preset,amplitude,duration,player) / hint(text,id) / custom
-- trigger conditions: "immediate" | "once" | "recurring" | {proximity=r} | {onDestroy="nearest"|name}
--   | {onHealthBelow={target=,pct=}} | {onCleared={faction=,radius=}} | {ref=id}
--   LOGIC GATES (as def.triggers entries): kind="all"/"count" with inputs={trigIds}, need=N (count).
--   OBJECTIVE-COMPLETE is NOT an inline trigger= shape (Ess.Raw.Triggers.arm has no onObjComplete branch,
--   deliberately -- see 62_triggers_raw.lua's own header) -- it's a top-level named def.triggers entry
--   instead: { id=, kind="objective", index=N }, referenced from a support/waypoint the normal way via
--   trigger={ref=id}.

-- import() is file-scoped -- 80_contract.lua importing these doesn't make them visible here, confirmed
-- the hard way (a live crash on MrxMusic in that file before this comment existed).
import("MrxMusic")
import("MrxCopterDrop")
pcall(function() import("MrxVoSequence") end)   -- optional VO integration; pcall since not every install has it

local Ess = _G.Ess
local C = Ess.Contract

local FACTION_ABBREV = { Allied = "All", China = "Chi", Guerilla = "Gur", OC = "Oil", Pirate = "Pir", VZ = "VZ", PMC = "Pmc" }
local HELO_FACTION   = { Allied = "AL", China = "CH", Guerilla = "GR", OC = "OC", Pirate = "PR", VZ = "VZ" }
local function factionGuid(name) local ok, g = pcall(Pg.GetGuidByName, name); if ok then return g end end
local function evPos(ev) if ev.at then return C._xyz(ev.at) end return ev.x, ev.y, ev.z end
local function ownerGuid(ev) if ev.owner then return factionGuid(ev.owner) end end

-- ---- relations: now a two-line wrapper over Ess.Relations, replacing the ~25-line hand-rolled
-- snapshot/apply/restore pair this file used to carry independently. Holds the handle on the instance so
-- each contract restores exactly its own relation set.
function C._applyRelations(inst)
    inst._relHandle = Ess.Relations.apply(inst.def.relations or {}, "Ess.Contract:" .. tostring(inst._id))
end
function C._restoreRelations(inst)
    if inst._relHandle then Ess.Relations.restore(inst._relHandle); inst._relHandle = nil end
end

-- ---- support effects: one-shot actions a trigger fires. Push spawns/events into `task` for cleanup.
local SUPPORT_EFFECTS = {}
SUPPORT_EFFECTS.artillery = function(inst, task, ev)          -- N shells rain onto the zone (spread), owned by `owner`
    local x, y, z = evPos(ev); if not x then return end
    local ammo, n, r, owner = ev.ammo or "Gunship Shell", C._rspan(ev.count) or 5, ev.radius or 14, ownerGuid(ev)
    for i = 1, n do
        local dx, dz = math.randf(0, 2 * r) - r, math.randf(0, 2 * r) - r
        C._addEv(task, Event.Create(Event.TimerRelative, { 0.35 * (i - 1) }, function()
            if inst.bActive then pcall(Airstrike.SpawnOrdnance, ammo, x + dx, y + 220, z + dz, 0, -100, 0, "impact", 1, owner) end
        end))
    end
end
SUPPORT_EFFECTS.flyby = function(inst, task, ev)              -- a support vehicle streaks over the zone
    local x, y, z = evPos(ev); if not x then return end
    pcall(Airstrike.Flyby, ev.vehicle or "Support Vehicle (Autogunship)", x - 50, z + 300, x, z, y + (ev.altitude or 120), ev.speed or 55)
end
SUPPORT_EFFECTS.airstrike = SUPPORT_EFFECTS.flyby
SUPPORT_EFFECTS.bombingrun = function(inst, task, ev)         -- an aircraft makes a pass and walks a stick of bombs onto the zone
    local x, y, z = evPos(ev); if not x then return end
    local vehicle, bomb = ev.vehicle or "Support Vehicle (A10)", ev.ammo or "Bomb"
    local alt, speed, n, owner = y + (ev.altitude or 150), ev.speed or 160, C._rspan(ev.count) or 3, ownerGuid(ev)
    local uJet
    local function drop()
        if not inst.bActive then return end
        for i = 1, n do
            C._addEv(task, Event.Create(Event.TimerRelative, { 0.14 * (i - 1) }, function()
                if not inst.bActive then return end
                local jx, jy, jz = x, alt, z
                if uJet then local ok, a, b, c = pcall(Object.GetPosition, uJet); if ok and a then jx, jy, jz = a, b, c end end
                pcall(Airstrike.SpawnOrdnance, bomb, jx, jy, jz, 0, -60, 0, "impact", 1, owner)
            end))
        end
        Ess.Log("  bombing run: " .. n .. "x " .. tostring(bomb))
    end
    local ok, jet = pcall(Airstrike.Flyby, vehicle, x - 350, z + 350, x, z, alt, speed, drop)
    if ok then uJet = jet end
end
SUPPORT_EFFECTS.heli = function(inst, task, ev)               -- a wave of N helicopters passes over, fanned out
    local x, y, z = evPos(ev); if not x then return end
    local tmpl, n = ev.template or "AH1Z", C._rspan(ev.count) or 3
    local stagger = ev.stagger or 1.6
    local spread  = ev.spread or 45
    for i = 1, n do
        local off = (i - 1) * spread
        C._addEv(task, Event.Create(Event.TimerRelative, { stagger * (i - 1) }, function()
            if inst.bActive then pcall(Airstrike.Flyby, tmpl, x - 60 - off, z + 300 + off, x + off, z, y + (ev.altitude or 55), ev.speed or 45) end
        end))
    end
end
SUPPORT_EFFECTS.reinforce = function(inst, task, ev)         -- units arrive: deliver="copter"|"paradrop"|else direct spawn
    local x, y, z = evPos(ev); if not x then return end
    local fac, spawns = HELO_FACTION[ev.faction] or ev.faction or "VZ", ev.spawns or {}
    local function spawnOne(i, tmpl)
        local ox, oz = ((i - 1) % 3 - 1) * 4, math.floor((i - 1) / 3) * 4
        if ev.deliver == "copter" then pcall(MrxCopterDrop.Create, fac, tmpl, x + ox, y, z + oz, false)
        else local ok, u = C._safeSpawn(tmpl, x + ox, y, z + oz); if ok then C._track(task, u) end end
    end
    if ev.deliver == "paradrop" then
        pcall(Airstrike.Flyby, ev.vehicle or "Support Vehicle (Paradrop_AL)", x - 350, z + 350, x, z, y + (ev.altitude or 180), ev.speed or 140)
        for i, tmpl in ipairs(spawns) do C._addEv(task, Event.Create(Event.TimerRelative, { 1.5 + 0.2 * i }, function() if inst.bActive then spawnOne(i, tmpl) end end)) end
    else
        for i, tmpl in ipairs(spawns) do spawnOne(i, tmpl) end
    end
    Ess.Log("  reinforcements inbound (" .. #spawns .. ", " .. (ev.deliver or "direct") .. ")")
end
SUPPORT_EFFECTS.custom = function(inst, task, ev) if type(ev.fn) == "function" then pcall(ev.fn, ev, task) end end
SUPPORT_EFFECTS.say = function(inst, task, ev) C._hudSay(ev.text or ev.msg, ev.hold) end
SUPPORT_EFFECTS.music = function(inst, task, ev)
    if ev.stop or ev.cue == "stop" or ev.cue == "" then pcall(MrxMusic.StopSpecialMusic)
    else inst.musicOn = true; pcall(MrxMusic.PlaySpecialMusic, ev.cue or "mu_pmc_panicloop_01") end
end
SUPPORT_EFFECTS.vfx = function(inst, task, ev)              -- cosmetic explosions / fire / smoke (NO damage)
    local x, y, z = evPos(ev); if not x then return end
    local particle, n, r = ev.particle or "global_particle_explosion_flash_large", C._rspan(ev.count) or 1, ev.radius or 0
    for i = 1, n do
        local dx, dz = (r > 0) and (math.randf(0, 2 * r) - r) or 0, (r > 0) and (math.randf(0, 2 * r) - r) or 0
        C._addEv(task, Event.Create(Event.TimerRelative, { 0.25 * (i - 1) }, function()
            if inst.bActive then pcall(Airstrike.SpawnDirectedObject, particle, x + dx, y + (ev.up or 1), z + dz, 0, 1, 0) end
        end))
    end
end
SUPPORT_EFFECTS.damage = function(inst, task, ev)          -- scripted damage / kill on a target GROUP (or named unit / area)
    local guids = (inst.groups or {})[tostring(ev.target or "")] or {}
    if #guids == 0 and ev.target then local g = factionGuid(ev.target); if g then guids = { g } end end
    if #guids == 0 and ev.at then local x, y, z = evPos(ev); guids = C._collectInArea(x, y, z, ev.radius or 30, ev.kind, ev.faction) end
    local pct = ev.pct or 25
    for _, g in ipairs(guids) do
        if ev.kill then pcall(Object.Kill, g)
        else local ok, hp = pcall(Object.GetHealth, g); if ok and hp and hp > 0 then pcall(Object.SetHealth, g, hp * (pct / 100)) end end
    end
    Ess.Log("  damage -> " .. #guids .. (ev.kill and " killed" or (" to " .. pct .. "%")))
end
SUPPORT_EFFECTS.vo = function(inst, task, ev)              -- play a voice-over line sequence; no-op if VO isn't loaded
    if not (MrxVoSequence and MrxVoSequence.Start) then return end
    local lines = ev.lines; if type(lines) == "string" then lines = { lines } end
    if type(lines) ~= "table" or #lines == 0 then return end
    local seq = {}; for i, ln in ipairs(lines) do seq[#seq + 1] = ln; if i < #lines then seq[#seq + 1] = ev.gap or 1 end end
    pcall(MrxVoSequence.Start, seq)
end
SUPPORT_EFFECTS.shake = function(inst, task, ev)           -- camera shake feedback (explosions, impacts)
    Ess.Camera.shake(ev.player or 0, ev.preset or "ShakeCameraMedium", Ess.Player.character(ev.player or 0), ev.amplitude or 6, ev.duration or 5)
end
SUPPORT_EFFECTS.hint = function(inst, task, ev)            -- native tutorial-style HUD hint popup (icon+sound)
    Ess.Hud.hint(ev.text or ev.msg, ev.id)
end

-- ---- normalize a def.triggers entry's `kind` field into an Ess.Raw.Triggers.arm-compatible spec
-- (mirrors ContractFramework.lua's own namedTrig). kind="objective" is handled separately below since it
-- needs inst.objDone directly -- not something the standalone Ess.Triggers vocabulary reaches.
local function namedSpec(t)
    if t.kind == "proximity" then return { proximity = t.radius or 15, at = t.at } end
    if t.kind == "recurring" then return { recurring = t.interval or 10, limit = t.limit } end
    if t.kind == "once" or t.kind == "timer" then return { once = t.delay or 3 } end
    if t.kind == "onDestroy" then return { onDestroy = t.target or "nearest", at = t.at, radius = t.radius } end
    if t.kind == "health" then return { onHealthBelow = { pct = t.pct or 50, target = t.target } } end
    if t.kind == "cleared" then return { onCleared = { radius = t.radius, faction = t.faction, kind = t.targetKind }, at = t.at, radius = t.radius } end
    return "immediate"
end

-- spawn def.units, bucket their guids by group, and track them for teardown (one task bucket). Also
-- registers each group with Ess.AIOrders.setGroup so waypoint/order target= lookups resolve -- NOTE:
-- Ess.AIOrders' group registry is GLOBAL, not per-instance, so this relies on ContractFramework's own
-- existing "only one active contract at a time" invariant (C.Accept aborts any prior active instance)
-- to avoid two contracts' groups colliding under the same name.
function C._spawnUnits(inst)
    local d = inst.def
    inst.groups = inst.groups or {}
    if not d.units or #d.units == 0 then return end
    local task = C._newTask()
    inst.tasks[#inst.tasks + 1] = task
    local n = 0
    for _, u in ipairs(d.units) do
        local tmpl = u.spawn or u.template or u[1]
        if type(tmpl) == "table" then tmpl = tmpl[1 + math.floor(math.randf(0, #tmpl - 0.001))] end   -- pick one of a list
        local x, y, z = C._xyz(u.at or { u.x, u.y, u.z })
        if tmpl and x and C._rchance(u.chance) then                                                    -- u.chance<1 = probabilistic spawn
            local ok, g = C._safeSpawn(tmpl, x, y, z, u.yaw)
            if ok and g then
                C._track(task, g)
                if u.yaw then pcall(Object.SetYaw, g, u.yaw) end
                local grp = tostring(u.group or "A")
                inst.groups[grp] = inst.groups[grp] or {}
                inst.groups[grp][#inst.groups[grp] + 1] = g
                Ess.AIOrders.setGroup(grp, inst.groups[grp])
                n = n + 1
            end
        end
    end
    if n > 0 then Ess.Log("  spawned " .. n .. " grouped unit(s)") end
end

-- ---- support + AI orders + triggers runner (from _startBackground; one auto-cleaned task bucket) ----
function C._startSupport(inst)
    local d = inst.def
    if not (d.support or d.triggers or d.waypoints) then return end
    inst.support, inst.waypoints = {}, {}
    for _, ev in ipairs(d.support or {})   do if ev.id then inst.support[ev.id]   = ev end end
    for _, wp in ipairs(d.waypoints or {}) do if wp.id then inst.waypoints[wp.id] = wp end end
    local task = C._newTask()
    inst.tasks[#inst.tasks + 1] = task
    -- Each contract instance gets its OWN Ess.Triggers scope, so a trigger/gate id from a PREVIOUS accept
    -- (or another instance) can never look "already fired" to this one -- isolation is structural now, not
    -- a per-instance string-prefix workaround over a shared global registry (the id namespace that used to
    -- be spelled `ns .. t.id` is just `t.id` within this scope).
    local trigScope = Ess.Triggers.scope()
    inst.trigScope = trigScope

    local function fireSupport(idOrEv)
        local ev = type(idOrEv) == "table" and idOrEv or inst.support[idOrEv]
        if not ev then return end
        local fx = SUPPORT_EFFECTS[ev.effect or "custom"]
        if fx then Ess.Log("  support '" .. tostring(ev.id or ev.effect) .. "' fired"); pcall(fx, inst, task, ev) end
    end
    local function fireOrder(idOrWp)
        local wp = type(idOrWp) == "table" and idOrWp or inst.waypoints[idOrWp]
        if not wp then return end
        local guids = (inst.groups or {})[tostring(wp.group or "")] or {}
        Ess.Log(string.format("  order '%s' (%s) -> group %s [%d unit%s]",
            tostring(wp.id or wp.behavior), tostring(wp.behavior or "move"), tostring(wp.group), #guids, #guids == 1 and "" or "s"))
        Ess.AIOrders.command(guids, wp.behavior or "move", wp, task)
    end
    local function fireById(id)                                     -- a named trigger's fires{} may name a support OR an order
        if inst.support[id]   then fireSupport(id) end
        if inst.waypoints[id] then fireOrder(id) end
    end

    for _, ev in ipairs(d.support or {}) do                          -- supports self-arm unless they wait on a named trigger
        local tr = ev.trigger
        if not (type(tr) == "table" and tr.ref) then Ess.Triggers.arm(tr, function() fireSupport(ev) end, task) end
    end
    for _, wp in ipairs(d.waypoints or {}) do                        -- orders self-arm; default = immediate after a short settle
        local tr = wp.trigger
        if not (type(tr) == "table" and tr.ref) then
            if tr == nil then tr = { once = wp.delay or 1.5 } end     -- let crews seat / units wake before ordering
            Ess.Triggers.arm(tr, function() fireOrder(wp) end, task)
        end
    end

    -- CONFIRMED LIVE double-fire bug this fixes, present in ContractFramework.lua's own trigAction (not
    -- introduced by this port -- a faithful port would reproduce it): if a support/waypoint entry is
    -- wired to a trigger BOTH via that trigger's own `fires={id}` list AND via the entry's own
    -- `trigger={ref=t.id}`, the original fires it TWICE per trigger activation -- once through each scan,
    -- with no deduplication between the two paths. Track what's already fired THIS trigAction call and
    -- skip a second hit, so wiring the same relationship both ways (redundant but not unreasonable to
    -- write) doesn't double-fire.
    local function trigAction(t)                                      -- what a trigger (or gate) does when it fires
        local already = {}
        for _, id in ipairs(t.fires or {}) do
            if not already[id] then already[id] = true; fireById(id) end
        end
        for _, ev in ipairs(d.support or {}) do
            local tr = ev.trigger
            if type(tr) == "table" and tr.ref == t.id and not already[ev.id] then already[ev.id] = true; fireSupport(ev) end
        end
        for _, wp in ipairs(d.waypoints or {}) do
            local tr = wp.trigger
            if type(tr) == "table" and tr.ref == t.id and not already[wp.id] then already[wp.id] = true; fireOrder(wp) end
        end
    end
    for _, t in ipairs(d.triggers or {}) do
        if t.kind == "objective" then                                 -- needs inst.objDone directly (see namedSpec's own note)
            local idx = tonumber(t.index or t.obj) or 1
            local function poll()
                if not inst.bActive then return end
                if inst.objDone and inst.objDone[idx] then
                    trigScope:markFired(t.id)
                    return trigAction(t)
                end
                C._addEv(task, Event.Create(Event.TimerRelative, { 0.4 }, poll))
            end
            trigScope:declare(t.id)
            poll()
        elseif t.kind == "all" or t.kind == "count" then               -- LOGIC GATE
            local inputs = {}
            for _, id in ipairs(t.inputs or {}) do inputs[#inputs + 1] = id end
            local need = (t.kind == "all") and #(t.inputs or {}) or (t.need or #(t.inputs or {}))
            trigScope:declare(t.id)   -- so ANOTHER gate/fires{} can reference this gate's own id too
            trigScope:gate(inputs, need, function()
                trigScope:markFired(t.id)
                Ess.Log("  gate '" .. tostring(t.id) .. "' (" .. t.kind .. ") satisfied")
                trigAction(t)
            end, task)
        else
            trigScope:armNamed(t.id, namedSpec(t), function() trigAction(t) end, task)
        end
    end
end

-- ============================================================
-- A built-in demo so the board isn't empty on a fresh install. Modders add their own via Register.
-- ============================================================
C.Register({
    id = "demo_convoy", title = "Demo: Wreck the Convoy", category = "DEMO",
    briefing = "Three cars, then reach the drop.",
    reward = { cash = 50000, fuel = 100 },
    objectives = {
        C.Destroy({ desc = "Destroy 3 cars" }),
        C.Reach({ desc = "Reach the drop-off", radius = 12 }),
    },
    -- fResolve runs at accept time to fill in dynamic coords (here, relative to the player). Real
    -- modder contracts use absolute coords from the creator and don't need this.
    fResolve = function(def)
        local uc = Player.GetLocalCharacter(); if not uc then return end
        local x, y, z = Object.GetPosition(uc)
        def.objectives[1].tSpawns = { { "Veyron", x + 8, y, z + 3, 0 }, { "Veyron", x + 10, y, z, 0 }, { "Veyron", x + 8, y, z - 3, 0 } }
        def.objectives[2].tZone   = { x = x + 40, y = y, z = z, r = 12 }
    end,
})

Ess.Log("Contract: loaded (" .. #C._registry .. " contract(s) registered)")
