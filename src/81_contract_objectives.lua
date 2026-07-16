-- Ess/81_contract_objectives.lua -- Ess.Contract's 15 objective-type handlers, absorbed from
-- ContractFramework.lua. Each is `fn(inst, task, obj, onDone)`; call onDone(true|false) exactly once.
-- Push spawns/blips/events into `task` (its own bucket) so several can run at once in parallel mode.
--
-- Uses C._track/_mark/_markZone/_addEv/_resolveTargets -- 80_contract.lua's own local helpers, exposed
-- as C._xxx fields since each src file is a separate do...end block in the merged chunk.

local Ess = _G.Ess
local C = Ess.Contract
local track, mark, markZone, addEv = C._track, C._mark, C._markZone, C._addEv
local resolveTargets = C._resolveTargets
local xyz = C._xyz
local safeSpawn = C._safeSpawn

C.tHandlers.chase = function(inst, task, obj, onDone)       -- destroy a FLEEING target before it reaches its escape point
    local guids = resolveTargets(inst, task, obj)
    local total = #guids
    if total == 0 then return onDone(true) end
    local ez = obj.tZone
    for _, u in ipairs(guids) do
        mark(task, u, "destroy")
        local a = u; local okd, drv = pcall(Vehicle.GetDriver, u); if okd and drv then a = drv end   -- steer the driver of a vehicle
        if ez and ez.x then pcall(Ai.Goal, { AIGuid = a, Goal = "MoveToPos", Location = { ez.x, ez.y, ez.z }, Priority = "HiPri", Force = true }) end
        pcall(Ai.SetHaste, a, obj.nHaste or 1)
    end
    local killed = 0
    for _, u in ipairs(guids) do
        addEv(task, Event.Create(Event.ObjectDeath, { u }, function()
            if not inst.bActive then return end
            killed = killed + 1; Ess.Log("  runner down (" .. killed .. "/" .. total .. ")")
            if killed >= total then onDone(true) end
        end, {}))
    end
    if ez and ez.x then                                     -- fail the instant any target reaches the escape zone
        local r = ez.r or 15
        local function watch()
            if not inst.bActive or task.done then return end
            for _, u in ipairs(guids) do
                local ok, ux, _, uz = pcall(Object.GetPosition, u)
                if ok and ux then local dx, dz = ux - ez.x, uz - ez.z; if dx * dx + dz * dz <= r * r then Ess.Log("  the target got away!"); return onDone(false) end end
            end
            addEv(task, Event.Create(Event.TimerRelative, { 0.5 }, watch))
        end
        watch()
    end
    if obj.nTime then addEv(task, Event.Create(Event.TimerRelative, { obj.nTime }, function()
        if inst.bActive and not task.done then Ess.Log("  chase timed out"); onDone(false) end end)) end
end

C.tHandlers.survive = function(inst, task, obj, onDone)
    local left = obj.nTime or 60
    if obj.sTarget then                                 -- optional: fail if a protected unit (group/name) dies before the timer
        local grp = (inst.groups or {})[obj.sTarget]; local u = grp and grp[1]
        if not u then local ok, g = pcall(Pg.GetGuidByName, obj.sTarget); if ok then u = g end end
        if u then addEv(task, Event.Create(Event.ObjectDeath, { u }, function()
            if inst.bActive and not task.done then Ess.Log("  protected target lost"); onDone(false) end end)) end
    end
    local function tick()
        if not inst.bActive or task.done then return end
        C._hudLine(1, "[white]" .. (obj.sDesc or "Hold out") .. "  (" .. math.max(0, math.floor(left)) .. "s)")
        if left <= 0 then return onDone(true) end
        left = left - 1
        addEv(task, Event.Create(Event.TimerRelative, { 1 }, tick))
    end
    tick()
end

C.tHandlers.destroy = function(inst, task, obj, onDone)
    local guids = resolveTargets(inst, task, obj)   -- spawned / named / live-queried
    local total = #guids
    if total == 0 then return onDone(true) end
    local quota, killed = obj.nQuota or total, 0
    for _, u in ipairs(guids) do
        mark(task, u, "destroy")
        addEv(task, Event.Create(Event.ObjectDeath, { u }, function()
            if not inst.bActive then return end
            killed = killed + 1; Ess.Log("  target down (" .. killed .. "/" .. quota .. ")")
            if killed >= quota then onDone(true) end
        end, {}))
    end
end

C.tHandlers.reach = function(inst, task, obj, onDone)
    local z = obj.tZone or {}
    if not z.x then Ess.Log("reach objective has no location"); return onDone(true) end
    local r = z.r or 15
    markZone(task, z.x, z.y, z.z, r)
    local function poll()
        if not inst.bActive or task.done then return end
        local uc = Player.GetLocalCharacter()
        if uc then local x, _, zz = Object.GetPosition(uc); local dx, dz = x - z.x, zz - z.z
            if dx * dx + dz * dz <= r * r then return onDone(true) end end
        addEv(task, Event.Create(Event.TimerRelative, { 0.25 }, poll))
    end
    poll()
end

C.tHandlers.defend = function(inst, task, obj, onDone)
    if obj.sTarget then
        local uT = Pg.GetGuidByName(obj.sTarget)
        if uT then addEv(task, Event.Create(Event.ObjectDeath, { uT }, function()
            if inst.bActive then onDone(false) end end, {})) end
    end
    addEv(task, Event.Create(Event.TimerRelative, { obj.nTime or 60 }, function()
        if inst.bActive then onDone(true) end
    end))
    Ess.Log(string.format("  hold for %d s", obj.nTime or 60))
end

-- DRAFT (untested; same shape as the rest -- mirrors ContractFramework.lua's own explicitly-flagged status)
C.tHandlers.collect = function(inst, task, obj, onDone)
    local remaining, r = {}, obj.nRadius or 4
    for _, s in ipairs(obj.tItems or {}) do
        local ok, u = safeSpawn(s[1], s[2], s[3], s[4])
        if ok and u then track(task, u); mark(task, u, "action"); remaining[#remaining + 1] = u end
    end
    local quota, got = obj.nQuota or #remaining, 0
    if #remaining == 0 then return onDone(true) end
    local function poll()
        if not inst.bActive or task.done then return end
        local uc = Player.GetLocalCharacter()
        if uc then
            local px, _, pz = Object.GetPosition(uc)
            for i = #remaining, 1, -1 do
                local ix, _, iz = Object.GetPosition(remaining[i])
                local dx, dz = px - ix, pz - iz
                if dx * dx + dz * dz <= r * r then
                    pcall(Object.Remove, remaining[i]); table.remove(remaining, i); got = got + 1
                    Ess.Log("  collected (" .. got .. "/" .. quota .. ")")
                    if got >= quota then return onDone(true) end
                end
            end
        end
        addEv(task, Event.Create(Event.TimerRelative, { 0.25 }, poll))
    end
    poll()
end

C.tHandlers.escort = function(inst, task, obj, onDone)
    local s = obj.tSpawn or {}
    local ok, u = safeSpawn(s[1], s[2], s[3], s[4])
    if not ok or not u then Ess.Log("escort couldn't spawn"); return onDone(true) end
    track(task, u); mark(task, u, "defend")
    addEv(task, Event.Create(Event.ObjectDeath, { u }, function()
        if inst.bActive then onDone(false) end
    end, {}))
    local z = obj.tZone or {}; local r = z.r or 15
    if z.x then markZone(task, z.x, z.y, z.z, r) end
    local function poll()
        if not inst.bActive or task.done or not z.x then return end
        local ex, _, ez = Object.GetPosition(u); local dx, dz = ex - z.x, ez - z.z
        if dx * dx + dz * dz <= r * r then return onDone(true) end
        addEv(task, Event.Create(Event.TimerRelative, { 0.5 }, poll))
    end
    poll()
end

C.tHandlers.enter = function(inst, task, obj, onDone)
    local u = obj.sTarget and Pg.GetGuidByName(obj.sTarget)
    if not u and obj.tSpawn then local s = obj.tSpawn; local ok, uu = safeSpawn(s[1], s[2], s[3], s[4]); if ok then u = track(task, uu) end end
    if not u then Ess.Log("enter has no vehicle"); return onDone(true) end
    mark(task, u, "action")
    addEv(task, Event.Create(Event.ObjectInSeat, { Player.GetAnyCharacter(), u, obj.sSeat or "d", "ei" }, function()
        if inst.bActive then onDone(true) end
    end, {}))
end

C.tHandlers.hold = function(inst, task, obj, onDone)
    local z = obj.tZone or {}
    if not z.x then Ess.Log("hold has no location"); return onDone(true) end
    local r, need, held, step = z.r or 15, obj.nTime or 15, 0, 0.5
    markZone(task, z.x, z.y, z.z, r)
    local function poll()
        if not inst.bActive or task.done then return end
        local uc = Player.GetLocalCharacter()
        if uc then local x, _, zz = Object.GetPosition(uc); local dx, dz = x - z.x, zz - z.z
            if dx * dx + dz * dz <= r * r then held = held + step
                if held >= need then return onDone(true) end end end
        addEv(task, Event.Create(Event.TimerRelative, { step }, poll))
    end
    poll()
end

-- background fail-conditions (put in a contract's `fail = { ... }`; only ever fail, never complete).
C.tHandlers.protect = function(inst, task, obj, onDone)
    local u = obj.sTarget and Pg.GetGuidByName(obj.sTarget)
    if not u and obj.tSpawn then local s = obj.tSpawn; local ok, uu = safeSpawn(s[1], s[2], s[3], s[4]); if ok then u = track(task, uu) end end
    if not u then return end
    mark(task, u, "defend")
    addEv(task, Event.Create(Event.ObjectDeath, { u }, function()
        if inst.bActive then Ess.Log("  protected target lost!"); onDone(false) end
    end, {}))
end

C.tHandlers.stay = function(inst, task, obj, onDone)
    local z = obj.tZone or {}; local r = z.r or 100
    if not z.x then return end
    local function poll()
        if not inst.bActive or task.done then return end
        local uc = Player.GetLocalCharacter()
        if uc then local x, _, zz = Object.GetPosition(uc); local dx, dz = x - z.x, zz - z.z
            if dx * dx + dz * dz > r * r then Ess.Log("  left the mission area!"); return onDone(false) end end
        addEv(task, Event.Create(Event.TimerRelative, { 0.5 }, poll))
    end
    poll()
end

-- structural: a nested objective list with its own mode -- gives full phase/tree nesting for free.
C.tHandlers.group = function(inst, task, obj, onDone)
    Ess.Log("  -- group [" .. (obj.sMode or "sequential") .. "] " .. (obj.sDesc or ""))
    C._runList(inst, obj.tObjectives or {}, obj.sMode, onDone)
end

-- interact: approach a target/point and (optionally) hold it for nTime seconds. One primitive for
-- talk / plant / hack / sabotage / free-prisoner -- the flavour is just the desc.
C.tHandlers.interact = function(inst, task, obj, onDone)
    local u, z = nil, obj.tZone
    if obj.sTarget then local ok, uu = pcall(Pg.GetGuidByName, obj.sTarget); if ok then u = uu end
    elseif obj.tSpawn then local s = obj.tSpawn; local ok, uu = safeSpawn(s[1], s[2], s[3], s[4]); if ok then u = track(task, uu) end end
    if u then local ok, x, y, zz = pcall(Object.GetPosition, u); if ok and x then z = { x = x, y = y, z = zz } end end
    if not z or not z.x then Ess.Log("interact has no target/location"); return onDone(true) end
    if u then mark(task, u, "action") end
    local r, need, held, step = obj.nRadius or 4, obj.nTime or 0, 0, 0.5
    local function poll()
        if not inst.bActive or task.done then return end
        local uc = Player.GetLocalCharacter()
        if uc then
            local x, _, zz = Object.GetPosition(uc); local dx, dz = x - z.x, zz - z.z
            if dx * dx + dz * dz <= r * r then
                held = held + step
                if held >= need then return onDone(true) end
            else held = 0 end   -- must stay to "use" it
        end
        addEv(task, Event.Create(Event.TimerRelative, { step }, poll))
    end
    poll()
end

-- verify: HVT bounty. Completes when the HVT is killed; if obj.bCapture, also completes when the
-- player is adjacent while it's at low health (a subdue approximation).
C.tHandlers.verify = function(inst, task, obj, onDone)
    local u
    if obj.sTarget then local ok, uu = pcall(Pg.GetGuidByName, obj.sTarget); if ok then u = uu end
    elseif obj.tSpawn then local s = obj.tSpawn; local ok, uu = safeSpawn(s[1], s[2], s[3], s[4]); if ok then u = track(task, uu) end end
    if not u then Ess.Log("verify has no HVT"); return onDone(true) end
    mark(task, u, "verify")
    addEv(task, Event.Create(Event.ObjectDeath, { u }, function()
        if inst.bActive then Ess.Log("  HVT verified (KIA)"); onDone(true) end
    end, {}))
    if obj.bCapture then
        local cr, chp = obj.nRadius or 3, obj.nCaptureHealth or 25
        local function poll()
            if not inst.bActive or task.done then return end
            local okp, px, _, pz = pcall(Object.GetPosition, Player.GetLocalCharacter())
            local okt, tx, _, tz = pcall(Object.GetPosition, u)
            local okh, hp = pcall(Object.GetHealth, u)
            if okp and okt and px and tx then
                local dx, dz = px - tx, pz - tz
                if okh and hp and hp <= chp and dx * dx + dz * dz <= cr * cr then
                    Ess.Log("  HVT verified (captured)"); return onDone(true)
                end
            end
            addEv(task, Event.Create(Event.TimerRelative, { 0.3 }, poll))
        end
        poll()
    end
end

-- extract: reach an LZ. nBoardTime = 0 (or nil<=0) -> INSTANT (reach the LZ = extracted, no heli).
-- nBoardTime > 0 -> HOLD the LZ that many seconds (a heli optionally spawns in; leaving resets).
C.tHandlers.extract = function(inst, task, obj, onDone)
    local z = obj.tZone or {}
    if not z.x then Ess.Log("extract has no zone"); return onDone(true) end
    local r, step, need = z.r or 15, 0.5, obj.nBoardTime or 3
    markZone(task, z.x, z.y, z.z, r)
    local boarding, held = false, 0
    local function poll()
        if not inst.bActive or task.done then return end
        local inzone = false
        local uc = Player.GetLocalCharacter()
        if uc then local x, _, zz = Object.GetPosition(uc); local dx, dz = x - z.x, zz - z.z; inzone = dx * dx + dz * dz <= r * r end
        if inzone then
            if need <= 0 then return onDone(true) end   -- INSTANT: reach the LZ and you're extracted
            if not boarding then
                boarding = true
                if obj.sHeli then local ok, h = safeSpawn(obj.sHeli, z.x, z.y + 4, z.z); if ok then track(task, h) end end
                Ess.Log("  extraction inbound - hold the LZ")
            end
            held = held + step
            if held >= need then return onDone(true) end
        else
            boarding, held = false, 0
        end
        addEv(task, Event.Create(Event.TimerRelative, { step }, poll))
    end
    poll()
end

-- race: reach tCheckpoints in order (optionally within nTime); reports the run time.
C.tHandlers.race = function(inst, task, obj, onDone)
    local cps, r = obj.tCheckpoints or {}, obj.nRadius or 12
    local n = #cps
    if n == 0 then return onDone(true) end
    local idx, curSet = 0, nil
    local startStamp = Sys.RealTimeStamp()
    local function armNext()
        if curSet then Ess.Mark.clear(curSet); curSet = nil end   -- unmark the PREVIOUS checkpoint only
        idx = idx + 1
        if idx > n then
            local ok, e = pcall(Sys.TimeStampGetElapsed, startStamp)
            Ess.Log(string.format("  race complete in %.1fs", (ok and e) or 0))
            return onDone(true)
        end
        local c = cps[idx]
        curSet = markZone(task, c[1], c[2], c[3], r)   -- full marker set on the current checkpoint only
        Ess.Log(string.format("  checkpoint %d/%d", idx, n))
    end
    if obj.nTime then
        addEv(task, Event.Create(Event.TimerRelative, { obj.nTime }, function()
            if inst.bActive and not task.done then Ess.Log("  race time expired"); onDone(false) end
        end))
    end
    local function poll()
        if not inst.bActive or task.done then return end
        local uc = Player.GetLocalCharacter()
        if uc and idx >= 1 and idx <= n then
            local c = cps[idx]
            local x, _, zz = Object.GetPosition(uc); local dx, dz = x - c[1], zz - c[3]
            if dx * dx + dz * dz <= r * r then
                armNext()
                if task.done or not inst.bActive then return end
            end
        end
        addEv(task, Event.Create(Event.TimerRelative, { 0.2 }, poll))
    end
    armNext()
    poll()
end
