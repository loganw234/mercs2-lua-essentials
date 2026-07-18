-- Ess/71_net_wire.lua -- Ess.Net: the rest of the co-op data-sync layer, absorbing ModNet.lua's wire
-- protocol wholesale. The protocol logic itself (serialization, chunking/reassembly, the LWW synced-
-- state channel, the ready-gate handshake) is a FAITHFUL, byte-for-byte port -- this is confirmed-working
-- production co-op code (real co-op wave-defense sessions), not something to creatively rewrite. Only the
-- scaffolding around it is modernized: the callback hijack now goes through Ess.Net.hijackCallback
-- (70_net.lua, which IS a generalization of this exact recipe) instead of a second hand-rolled copy, and
-- the heartbeat runs on Ess.Loop instead of a raw self-rescheduling Event.Create.
--
-- LAYERS (use the highest one that fits):
--   1. Synced state (simplest):
--        local S = Ess.Net.Shared("mymod")   -- a table whose fields auto-sync (LWW)
--        S.score = 100                        -- write -> broadcast; read S.score anywhere
--        Ess.Net.Set("k", v) / Ess.Net.Get("k")            -- default namespace shortcuts
--        Ess.Net.Track("hp", function() return myHp end)   -- push a local var out on a heartbeat
--   2. Messages:
--        Ess.Net.On("chat", function(sender, text) ... end)   -- sender = 0/1 player id
--        Ess.Net.Send("chat", "hello")                         -- any value: str/num/bool/table
--   3. Raw (experts): Ess.Net.OnRaw("ch", fn) / Ess.Net.SendRaw("ch", {numbers})
-- Pair Send<->On and SendRaw<->OnRaw per channel. Constraints: numbers are 24-bit-safe; small-payload
-- control plane (sync STATE, not files); host-authoritative or single-writer keys converge cleanest.

local Ess = _G.Ess
Ess.Net = Ess.Net or {}
local M = Ess.Net

-- ===== config (experts may tune before/after load) =====
M.EV    = M.EV    or 5     -- SendCustomEvent id (<8). SHARED with the game's own faction events on this
                           -- id; M.MAGIC below is what tells Ess.Net packets apart from theirs.
M.MAGIC = M.MAGIC or 5066564   -- "MOD" (0x4D4F44): leads every Ess.Net packet (tArgs[1]) so the receiver
                               -- only claims genuinely-ours traffic and passes the game's own events through.
M.SLOTS = M.SLOTS or 5     -- tArgs per send (3 are header now: magic+header+sender); rest are payload
M.HB    = M.HB    or 2.0   -- heartbeat seconds (Track polling + late-join reconcile)
M.OFF   = M.OFF   or false -- KILL SWITCH: when true, Ess.Net installs NO receiver hijack on
                           -- MrxFactionManager.NetEventCallback and puts NOTHING on the wire (local
                           -- Shared/Set still update, just don't broadcast). Set it true BEFORE Ess loads
                           -- (e.g. a lower-numbered OnLoad script doing `_G.Ess={Net={OFF=true}}`) to fully
                           -- take Ess.Net out of a co-op session -- the exact isolation test for "is Ess.Net
                           -- interfering with the join flow" (same method that diagnosed ModNet).

-- ===== persistent state (survives a reload) =====
M._chan  = M._chan  or {}  -- chash -> { fn, raw, name }
M._rx    = M._rx    or {}  -- reassembly buffers
M._store = M._store or {}  -- _store[ns][key] = { v, ver, src }
M._watch = M._watch or {}  -- { ns, key, get, last }
M._peerReady = false       -- ready-gate: reset every load so we re-run the handshake and never
                           -- broadcast to a peer still on its load screen (its Ess.Net isn't installed yet)

local function try(f, ...) if type(f) == "function" then local ok, v = pcall(f, ...); if ok then return v end end end
local function now() return try(Sys and Sys.RealTime) or 0 end
local function localId()
    return try(Player and Player.GetLocalPlayerId) or try(Player and Player.GetLocalId)
        or ((Net and Net.IsServer and Net.IsServer()) and 0 or 1)
end
local function chash(name)   -- name -> 16-bit id, identical on both machines
    local h = 0
    for i = 1, #name do h = (h * 33 + string.byte(name, i)) % 65536 end
    return h
end

-- ---- serialize a Lua value <-> byte string (number/string/bool/nil/nested table) ----
local function u16(n) return string.char(math.floor(n / 256) % 256, n % 256) end
local function serInto(v, out)
    local t = type(v)
    if v == nil then out[#out + 1] = "\000"
    elseif t == "boolean" then out[#out + 1] = v and "\002" or "\001"
    elseif t == "number" then local s = tostring(v); out[#out + 1] = "\003" .. string.char(#s) .. s
    elseif t == "string" then out[#out + 1] = "\004" .. u16(#v) .. v
    elseif t == "table" then
        local n = 0; for _ in pairs(v) do n = n + 1 end
        out[#out + 1] = "\005" .. u16(n)
        for k, val in pairs(v) do serInto(k, out); serInto(val, out) end
    else out[#out + 1] = "\000" end   -- functions/userdata -> nil
end
local function serialize(v) local o = {}; serInto(v, o); return table.concat(o) end
local function deser(s, i)
    local tag = string.byte(s, i); i = i + 1
    if tag == 0 then return nil, i
    elseif tag == 1 then return false, i
    elseif tag == 2 then return true, i
    elseif tag == 3 then local ln = string.byte(s, i); i = i + 1; return tonumber(string.sub(s, i, i + ln - 1)), i + ln
    elseif tag == 4 then local ln = string.byte(s, i) * 256 + string.byte(s, i + 1); i = i + 2; return string.sub(s, i, i + ln - 1), i + ln
    elseif tag == 5 then
        local n = string.byte(s, i) * 256 + string.byte(s, i + 1); i = i + 2; local tb = {}
        for _ = 1, n do local k; k, i = deser(s, i); local val; val, i = deser(s, i); tb[k] = val end
        return tb, i
    end
    return nil, i + 1
end
local function unserialize(s) local ok, v = pcall(deser, s, 1); if ok then return v end end

-- ---- bytes <-> numbers (3 bytes/number; faithful, incl. NULs -- TLV self-delimits any trailing pad) ----
local function bytesToNums(s)
    local n = {}
    for i = 1, #s, 3 do n[#n + 1] = (string.byte(s, i) or 0) * 65536 + (string.byte(s, i + 1) or 0) * 256 + (string.byte(s, i + 2) or 0) end
    return n
end
local function numsToBytes(nums)
    local t = {}
    for _, x in ipairs(nums) do t[#t + 1] = string.char(math.floor(x / 65536) % 256, math.floor(x / 256) % 256, x % 256) end
    return table.concat(t)
end

-- ===== wire: chunked send + reassembly =====
local function wireSend(ch, nums, reliable)
    if M.OFF then return end                       -- kill switch: never put anything on the wire
    if not (Net and Net.SendCustomEvent) then return end
    -- Ready-gate: in co-op, hold ALL traffic until the peer says it's loaded (Ess.Net installed),
    -- EXCEPT the handshake channels. Stops us pumping evt=5 at a still-loading joiner whose native
    -- faction handler would choke on it. (Local M._store still updates; only the wire is held.)
    if M.IsCoop() and not M._peerReady and ch ~= M._readyCh and ch ~= M._ackCh then return end
    local PAY = M.SLOTS - 3; if PAY < 1 then PAY = 1 end   -- 3 header slots now: magic, header, sender+ch
    local total = math.max(1, math.ceil(#nums / PAY))
    M._mid = ((M._mid or 0) + 1) % 255
    local me = localId()
    for c = 0, total - 1 do
        -- slot1=MAGIC (marks this as Ess.Net, not a game event on the shared id),
        -- slot2=header (mid/seq/total), slot3=sender+channel
        local a = { M.MAGIC, M._mid * 65536 + c * 256 + total, me * 65536 + ch }
        for p = 1, PAY do local v = nums[c * PAY + p]; if v ~= nil then a[#a + 1] = v end end
        Net.SendCustomEvent("MrxFactionManager", M.EV, a, reliable ~= false)
    end
end
local function dispatch(ch, sender, nums)
    local c = M._chan[ch]; if not c then return end
    if c.raw then pcall(c.fn, sender, nums)
    else pcall(c.fn, sender, unserialize(numsToBytes(nums))) end
end
local function wireRecv(tArgs)
    -- tArgs[1] = M.MAGIC (already checked by the hijack's isMinePredicate before this runs).
    local h = tArgs[2] or 0
    local mid = math.floor(h / 65536) % 256; local seq = math.floor(h / 256) % 256; local total = h % 256
    local s2 = tArgs[3] or 0
    local sender = math.floor(s2 / 65536) % 256; local ch = s2 % 65536
    local nums = {}; local i = 4; while tArgs[i] ~= nil do nums[#nums + 1] = tArgs[i]; i = i + 1 end
    local key = sender .. "/" .. ch .. "/" .. mid
    local m = M._rx[key]; if not m then m = { total = total, parts = {}, t = now() }; M._rx[key] = m end
    m.parts[seq] = nums; m.t = now()
    local have = 0; for _ in pairs(m.parts) do have = have + 1 end
    if have >= m.total then
        M._rx[key] = nil
        local all = {}
        for c2 = 0, m.total - 1 do local pr = m.parts[c2]; if pr then for _, v in ipairs(pr) do all[#all + 1] = v end end end
        dispatch(ch, sender, all)
    end
end

-- ===== public: messages + raw =====
function M.On(name, fn)    M._chan[chash(name)] = { fn = fn, raw = false, name = name } end
function M.OnRaw(name, fn) M._chan[chash(name)] = { fn = fn, raw = true,  name = name } end
function M.Send(name, value, reliable)   wireSend(chash(name), bytesToNums(serialize(value)), reliable) end
function M.SendRaw(name, nums, reliable) wireSend(chash(name), nums, reliable) end

-- ===== public: identity / authority =====
local function T(x) return x == true or x == 1 end   -- engine flags are sometimes bool, sometimes 1/0
function M.Me()     return localId() end                                   -- this machine's player id (0/1)
function M.IsCoop() return T(try(Net and Net.IsMultiplayer)) end           -- in a live co-op session?
function M.IsHost() return M.IsCoop() and T(try(Net and Net.IsServer)) end -- true only on the host/authority
function M.IsAuthority() return not M.IsCoop() or M.IsHost() end            -- SP OR co-op host = "should I run the sim?" (IsHost alone is FALSE in single-player)

-- ===== public: synced state (last-writer-wins) + tracked locals =====
local STATE = "ModNet$state"   -- wire-format channel name kept byte-identical for compatibility
local function broadcastKey(ns, key)
    local e = M._store[ns] and M._store[ns][key]; if not e then return end
    M.Send(STATE, { ns, key, e.ver, e.src, e.v }, true)
end
function M.setv(ns, key, value)
    local st = M._store[ns]; if not st then st = {}; M._store[ns] = st end
    local e = st[key]; local ver = (e and e.ver or 0) + 1
    st[key] = { v = value, ver = ver, src = localId() }
    broadcastKey(ns, key)
end
function M.getv(ns, key) local st = M._store[ns]; local e = st and st[key]; if e then return e.v end end
function M.Shared(ns)
    return setmetatable({}, {
        __index    = function(_, k) return M.getv(ns, k) end,
        __newindex = function(_, k, v) M.setv(ns, k, v) end,
    })
end
function M.Set(key, value) M.setv("_", key, value) end
function M.Get(key)        return M.getv("_", key) end
function M.Track(key, getter, ns)   -- idempotent: safe to call again on a reload
    ns = ns or "_"
    for _, w in ipairs(M._watch) do if w.ns == ns and w.key == key then w.get = getter; return end end
    M._watch[#M._watch + 1] = { ns = ns, key = key, get = getter, last = nil }
end

-- state channel receiver: apply last-writer-wins (ver, then higher sender id breaks ties -> converges)
if not M._stateOn then
    M._stateOn = true
    M.On(STATE, function(_, msg)
        if type(msg) ~= "table" then return end
        local ns, key, ver, src, value = msg[1], msg[2], msg[3], msg[4], msg[5]
        if ns == nil or key == nil then return end
        local st = M._store[ns]; if not st then st = {}; M._store[ns] = st end
        local e = st[key]
        if not e or ver > e.ver or (ver == e.ver and (src or -1) > (e.src or -1)) then
            st[key] = { v = value, ver = ver, src = src }
        end
    end)
end

-- ===== ready-gate handshake (also gives clean late-join sync) =====
local function reconcileAll()
    for ns, st in pairs(M._store) do for key in pairs(st) do broadcastKey(ns, key) end end
end
M._reconcile = reconcileAll

local READY = "ModNet$ready"   -- wire-format channel names kept byte-identical for compatibility
local RACK  = "ModNet$rack"
M._readyName = READY
M._readyCh   = chash(READY)
M._ackCh     = chash(RACK)
if not M._readyOn then
    M._readyOn = true
    -- Host side: a joiner just told us it finished loading. Open our wire to it, ack so it
    -- stops retrying, and push our whole store so it catches up on everything it missed.
    M.On(READY, function(sender)
        M._peerReady = true
        M.Send(RACK, 1)
        reconcileAll()
        Ess.Log("Net: peer READY (from " .. tostring(sender) .. ") -> ack + full reconcile")
    end)
    -- Joiner side: host acked our readiness. Wire is open; push our store too (sync both ways).
    M.On(RACK, function()
        M._peerReady = true
        reconcileAll()
        Ess.Log("Net: READY acked -> wire open")
    end)
end

-- ===== heartbeat: poll tracked locals; periodically re-broadcast state for late joiners =====
-- Runs on Ess.Loop instead of ModNet's own raw self-rescheduling Event.Create -- always returns true
-- (never idles, unlike Ess.UI's heartbeat) since co-op state needs polling for the whole session.
-- Ess.Loop.start's own generation-guard already supersedes any previous instance cleanly on a reload, so
-- no separate "_hbStarted" flag is needed the way ModNet.lua's own version required.
Ess.Loop.start("Ess.Net.heartbeat", M.HB, function()
    if Net and Net.IsMultiplayer and Net.IsMultiplayer() then
        -- Ready-gate: the JOINER (non-authority) keeps announcing it's loaded until the host acks
        -- (RACK). The host stays silent (wireSend gate) until it hears this, so nothing hits a joiner
        -- still on its load screen. Retried here to cover packet loss.
        if not M.IsAuthority() and not M._peerReady then M.Send(READY, 1) end
        for _, w in ipairs(M._watch) do
            local ok, v = pcall(w.get)
            if ok and v ~= w.last then w.last = v; M.setv(w.ns, w.key, v) end
        end
        M._hbN = (M._hbN or 0) + 1
        if M._peerReady and M._hbN % 5 == 0 then   -- every ~5 beats: full reconcile (LWW ignores dupes)
            reconcileAll()
        end
        local t = now(); for k, m in pairs(M._rx) do if t - (m.t or 0) > 10 then M._rx[k] = nil end end
    else
        M._peerReady = false   -- single-player / left the session: re-handshake next time we're in one
    end
    return true
end)

-- ===== install: the collision-proof callback hijack, via Ess.Net.hijackCallback (70_net.lua) =====
import("MrxFactionManager")   -- always-resident hijack target (harmless to import even when OFF)
if M.OFF then
    Ess.Log("Net: DISABLED (Ess.Net.OFF) -- no receiver hijack on NetEventCallback, no wire traffic")
else
    local installed = Ess.Net.hijackCallback(MrxFactionManager, "NetEventCallback",
        function(evt, tArgs) return evt == M.EV and tArgs ~= nil and tArgs[1] == M.MAGIC end,
        function(_, tArgs) wireRecv(tArgs) end)
    if installed then
        Ess.Log("Net: receiver installed on MrxFactionManager (EV=" .. M.EV .. " MAGIC=" .. M.MAGIC .. ", collision-proof marker active)")
    end
end

Ess.Log("Net: v" .. (Ess.VERSION or "?") .. " ready (EV=" .. M.EV .. " SLOTS=" .. M.SLOTS .. " HB=" .. M.HB .. ")")

-- On every load, a freshly-loaded joiner (non-authority) announces readiness immediately so the host
-- opens the wire without waiting for the first heartbeat tick. Heartbeat then retries.
if not M.OFF and M.IsCoop() and not M.IsAuthority() then pcall(function() M.Send(READY, 1) end) end
