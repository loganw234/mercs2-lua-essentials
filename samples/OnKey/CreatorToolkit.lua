local KEYVAL = "f8"   -- opens the toolkit menu; also add "CreatorToolkit.lua=f8" under [OnKey] in lua_loader.ini

-- =====================================================================
-- CreatorToolkit -- a HUB of in-game dev/creator tools behind one menu (F8). Mercs2 never shipped an editor,
-- so this is the "build things in the running game" kit. One key opens a menu; pick a tool. Several tools are
-- toggles (they pop their own HUD and keep running until you toggle them off from the menu again).
--
-- TOOLS
--   Object inspector  -- aim at ANYTHING: live name/faction/health/distance readout (WAILA for everything)
--   AI-cap meter      -- live count of nearby AI vs the ~200 soft cap (the documented CTD ceiling) -- spawn safely
--   Nearby scanner    -- a scrollable list of nearby objects; pick one to log its full details
--   Debug overlay     -- the Ess.Easy.Debug pos/aim/health overlay (folded in here)
--   Teleport bookmarks-- save/recall named world positions; PERSISTS across reload (grab your spawn coords)
--   Prop placer       -- spawn a chosen template at your reticle, rotate it, delete it -- dress a scene
--   Dev panel         -- invincible / infinite ammo / time-scale / freeze nearby AI / clear heat / heal / cash
--   Photo mode        -- park a hero-shot camera behind you + hide player markers (first-pass: static shot)
--   Camera recorder   -- drop camera keyframes as you walk, then play them back as a cinematic fly-through
--
-- Built entirely from confirmed Ess calls (Player/Object/Probe/Vehicle/UI/Camera/Time/SaveVar/RNG/Raw). It's a
-- FIRST-PASS draft: the two camera tools park/blend the camera through the confirmed cinematic API but don't
-- implement a WASD freecam yet (you author by positioning your character), and there's no native "hide the
-- whole HUD" call, so photo mode hides player markers only.
--
-- DEPLOY: Ess (dist/Ess.lua) OnLoad; this at scripts/OnKey/CreatorToolkit.lua , [OnKey] CreatorToolkit.lua=f8.
-- =====================================================================

local Ess = _G.Ess
if not (Ess and Ess.UI and Ess.UI.Menu) then
    if Loader and Loader.Printf then Loader.Printf("[creatorkit] load the Essentials framework (1_Ess.lua) first") end
    return
end

_G.CreatorKit = _G.CreatorKit or { placed = {}, keys = {} }
local T = _G.CreatorKit
local function onoff(b) return b and "ON" or "OFF" end
local openHub   -- forward decl (sub-tools reopen the hub)

-- ---- Object inspector -------------------------------------------------------------------------------
local function toggleInspector()
    if T.inspectorOn then
        Ess.Loop.stop("CreatorKit.inspect"); if T.inspPanel then T.inspPanel:hide() end; T.inspectorOn = false; return
    end
    if not T.inspPanel then T.inspPanel = Ess.UI.Panel{ x = 8, y = 150, w = 320, title = "INSPECT" } end
    T.inspPanel:show(); T.inspectorOn = true
    Ess.Loop.start("CreatorKit.inspect", 0.15, function()
        if not T.inspectorOn then return false end
        local g = Ess.Player.targetUnderReticle(0)
        if g then
            local px, py, pz = Ess.Player.pose(0)
            local d = px and Ess.Object.distance(g, px, py, pz)
            T.inspPanel:title("INSPECT: " .. (Ess.Object.displayName(g) or "?"))
            T.inspPanel:line(0, Ess.Probe.describeSafe(g))
            T.inspPanel:line(1, d and string.format("distance : %.1f", d) or "distance : ?")
            T.inspPanel:line(2, "guid     : " .. tostring(Ess.Name(g)))
        else
            T.inspPanel:title("INSPECT"); T.inspPanel:line(0, "(aim at something)")
            T.inspPanel:line(1, ""); T.inspPanel:line(2, "")
        end
        return true
    end)
end

-- ---- AI-cap meter -----------------------------------------------------------------------------------
local AI_CAP = 200
local function toggleMeter()
    if T.meterOn then
        Ess.Loop.stop("CreatorKit.meter"); if T.meterPanel then T.meterPanel:hide() end; T.meterOn = false; return
    end
    if not T.meterPanel then T.meterPanel = Ess.UI.Panel{ x = 8, y = 280, w = 320, title = "AI-CAP METER" } end
    T.meterPanel:show(); T.meterOn = true
    Ess.Loop.start("CreatorKit.meter", 1.0, function()          -- 1 Hz: the scan is heavy at this radius
        if not T.meterOn then return false end
        local px, py, pz = Ess.Player.pose(0)
        if not px then return true end
        local hum = #Ess.Probe.nearby(px, py, pz, 220, "humans")
        local veh = #Ess.Probe.nearby(px, py, pz, 220, "vehicles")
        local total = hum + veh
        T.meterPanel:line(0, "AI humans : " .. hum)
        T.meterPanel:line(1, "vehicles  : " .. veh)
        T.meterPanel:line(2, string.format("total/cap : %d / %d", total, AI_CAP))
        T.meterPanel:line(3, total >= AI_CAP * 0.85 and "!! NEAR AI CAP -- CTD RISK !!" or "headroom ok")
        return true
    end)
end

-- ---- Nearby scanner ---------------------------------------------------------------------------------
local function openScanner()
    local px, py, pz = Ess.Player.pose(0)
    if not px then Ess.UI.Toast("Can't read your position"); return end
    local items = {}
    local function addKind(kind, header)
        local list = Ess.Probe.nearby(px, py, pz, 60, kind)
        if #list > 0 then
            items[#items + 1] = { header = header }
            for _, g in ipairs(list) do
                local d = Ess.Object.distance(g, px, py, pz) or 0
                items[#items + 1] = { label = string.format("%s  [%s]  %.0fu",
                    (Ess.Object.displayName(g) or "?"), (Ess.Probe.getFaction(g) or "-"), d), any = g }
            end
        end
    end
    addKind("humans", "HUMANS"); addKind("vehicles", "VEHICLES")
    if #items == 0 then Ess.UI.Toast("Nothing within 60u"); return end
    if T.menu then T.menu:close() end                           -- hand focus to the list
    T.scanner = Ess.UI.List{ x = 40, y = 60, title = "NEARBY (60u)", hint = "ENTER LOG   LEFT BACK",
        items = items, focus = true,
        onChoose = function(it) if it and it.any then
            Ess.Log("Scanner: " .. Ess.Probe.describeSafe(it.any)); Ess.UI.Toast("Logged -- see the log") end end,
        onBack = function() if T.scanner then T.scanner:hide():blur() end; openHub() end }
end

-- ---- Teleport bookmarks (persistent) ----------------------------------------------------------------
local WP_SLOTS = 6
local sv = Ess.SaveVar.ns("CreatorKit_wp")
local function wpStr(i) return sv:get("s" .. i, "") end
local function saveWp(i)
    local x, y, z, yaw = Ess.Player.pose(0)
    if not x then Ess.UI.Toast("Can't read your position"); return end
    sv:set("s" .. i, string.format("%.2f,%.2f,%.2f,%.3f", x, y, z, yaw or 0)); Ess.UI.Toast("Saved bookmark " .. i)
end
local function recallWp(i)
    local s = wpStr(i); if s == "" then Ess.UI.Toast("Bookmark " .. i .. " is empty"); return end
    local p = Ess.Str.split(s, ",")
    local x, y, z, yaw = tonumber(p[1]), tonumber(p[2]), tonumber(p[3]), tonumber(p[4])
    if x then Ess.Player.teleport(x, y, z, yaw); Ess.UI.Toast("Warped to bookmark " .. i) end
end

-- ---- Prop placer ------------------------------------------------------------------------------------
local PROP_TEMPLATES = { "Veyron", "UH1 Transport", "AH1Z (Full)", "VZ Soldier",
                         "Supply Drop (Light MG)", "fx_Explosion_Huge", "Explosion (Grenade)" }
T.propIdx = T.propIdx or 1
local function placeProp()
    local g, hx, hy, hz = Ess.Player.targetUnderReticle(0)   -- the point under your reticle
    if not hx then                                            -- nothing targeted -> a spot ahead of you
        local px, py, pz, yaw = Ess.Player.pose(0)
        if not px then return end
        hx, hz = Ess.Math.pointAhead(px, pz, yaw or 0, 8); hy = py
    end
    local u = Ess.Object.spawn(PROP_TEMPLATES[T.propIdx], hx, hy, hz)
    if u then T.placed[#T.placed + 1] = u; Ess.UI.Toast("Placed " .. PROP_TEMPLATES[T.propIdx]) end
end
local function rotateLast()
    local u = T.placed[#T.placed]; if not u then return end
    T.propYaw = ((T.propYaw or 0) + 45) % 360
    Ess.Object.setYaw(u, math.rad(T.propYaw)); Ess.UI.Toast("Rotated to " .. T.propYaw .. "deg")
end
local function deleteLast()
    local u = table.remove(T.placed); if u then Ess.Object.remove(u); Ess.UI.Toast("Deleted last prop") end
end
local function deleteAllProps()
    for _, u in ipairs(T.placed) do Ess.Object.remove(u) end
    T.placed = {}; Ess.UI.Toast("Cleared all placed props")
end

-- ---- Dev panel toggles ------------------------------------------------------------------------------
local function toggleInvincible()
    T.inv = not T.inv; Ess.Object.setInvincible(Ess.Player.character(0), T.inv, "CreatorKit")
    Ess.UI.Toast("Invincible: " .. onoff(T.inv))
end
local function toggleInfAmmo()
    T.ammo = not T.ammo; Ess.Human.setInfiniteAmmo(Ess.Player.character(0), T.ammo)
    Ess.UI.Toast("Infinite ammo: " .. onoff(T.ammo))
end
local function freezeNearbyAI(bFreeze)
    local px, py, pz = Ess.Player.pose(0); if not px then return end
    local n = 0
    for _, g in ipairs(Ess.Probe.nearby(px, py, pz, 80, "humans")) do
        Ess.Raw.AIOrders.enable(g, not bFreeze); n = n + 1
    end
    Ess.UI.Toast((bFreeze and "Froze " or "Woke ") .. n .. " nearby AI")
end

-- ---- Photo mode (static hero shot + hide markers) ---------------------------------------------------
local function togglePhoto()
    if T.photo then
        Ess.Camera.endCinematic(0); Ess.Raw.Mark.showPlayerMarkers(true); T.photo = false
        Ess.UI.Toast("Photo mode OFF"); return
    end
    local px, py, pz, yaw = Ess.Player.pose(0); if not px then return end
    local bx, bz = Ess.Math.pointAhead(px, pz, (yaw or 0) + 180, 6)   -- 6u behind you
    Ess.Camera.beginCinematic(0, 0.6)
    Ess.Camera.placeCamera(bx, py + 3, bz, 0)
    Ess.Camera.lookAtPoint(px, py + 1, pz, 0)
    Ess.Raw.Mark.showPlayerMarkers(false); T.photo = true
    Ess.UI.Toast("Photo mode ON (toggle off to restore)")
end

-- ---- Camera-path recorder ---------------------------------------------------------------------------
local function dropKeyframe()
    local x, y, z, yaw = Ess.Player.pose(0); if not x then return end
    T.keys[#T.keys + 1] = { x = x, y = y, z = z, yaw = yaw or 0 }
    Ess.UI.Toast("Keyframe " .. #T.keys .. " dropped")
end
local function playPath()
    local keys = T.keys
    if #keys < 2 then Ess.UI.Toast("Drop at least 2 keyframes first"); return end
    local HOLD = 2.5
    local function place(k)
        local lx, lz = Ess.Math.pointAhead(k.x, k.z, k.yaw, 10)   -- look 10u ahead of the vantage
        Ess.Camera.placeCamera(k.x, k.y + 2, k.z, 0); Ess.Camera.lookAtPoint(lx, k.y + 1, lz, 0)
    end
    Ess.Camera.beginCinematic(0, 0.6); place(keys[1])
    local idx = 1
    Ess.Loop.start("CreatorKit.cam", HOLD, function()
        idx = idx + 1
        if idx > #keys then Ess.Camera.endCinematic(0); Ess.UI.Toast("Path complete"); return false end
        Ess.Camera.blend(0, HOLD * 0.9); place(keys[idx])       -- re-arm a smooth move to the next vantage
        return true
    end)
    Ess.UI.Toast("Playing a " .. #keys .. "-shot fly-through")
end

-- ---- the hub menu -----------------------------------------------------------------------------------
openHub = function()
    local menu = Ess.UI.Menu({ title = "CREATOR TOOLKIT", id = "CreatorKit", key = "close" })
    menu:header("Inspect")
    menu:entry(function() return "Object inspector : " .. onoff(T.inspectorOn) end, function() toggleInspector() end)
    menu:entry(function() return "AI-cap meter     : " .. onoff(T.meterOn) end, function() toggleMeter() end)
    menu:entry("Nearby scanner...", function() openScanner() end)
    menu:entry(function() return "Debug overlay    : " .. onoff(Ess.Easy.Debug.isOn()) end, function() Ess.Easy.Debug.overlay() end)

    menu:header("Author")
    menu:category("Teleport bookmarks", function(cat)
        cat:header("Pick a slot to WARP to it")
        for i = 1, WP_SLOTS do
            cat:entry(function() local s = wpStr(i); return "Slot " .. i .. " : " .. (s ~= "" and s or "(empty)") end,
                function() recallWp(i) end)
        end
        cat:header("Save your current position")
        for i = 1, WP_SLOTS do cat:entry("Save current -> slot " .. i, function() saveWp(i) end) end
    end)
    menu:category("Prop placer", function(cat)
        cat:header("Aim where you want it, then place")
        cat:entry(function() return "Template : " .. PROP_TEMPLATES[T.propIdx] end,
            function() T.propIdx = T.propIdx % #PROP_TEMPLATES + 1 end)
        cat:entry("Place at reticle", function() placeProp() end)
        cat:entry("Rotate last +45deg", function() rotateLast() end)
        cat:entry("Delete last", function() deleteLast() end)
        cat:entry("Delete ALL placed", function() deleteAllProps() end)
    end)

    menu:header("Control")
    menu:category("Dev panel", function(cat)
        cat:entry(function() return "Invincible    : " .. onoff(T.inv) end, function() toggleInvincible() end)
        cat:entry(function() return "Infinite ammo : " .. onoff(T.ammo) end, function() toggleInfAmmo() end)
        cat:header("Time scale")
        cat:entry("Slow (0.3x)", function() Ess.Time.scale(0.3) end)
        cat:entry("Normal (1x)", function() Ess.Time.restoreScale() end)
        cat:entry("Fast (2x)", function() Ess.Time.scale(2) end)
        cat:header("Nearby AI")
        cat:entry("Freeze nearby AI", function() freezeNearbyAI(true) end)
        cat:entry("Wake nearby AI", function() freezeNearbyAI(false) end)
        cat:header("Quick actions")
        cat:entry("Clear wanted heat", function() Ess.Easy.World.clearWanted() end)
        cat:entry("Heal to full", function() Ess.Object.heal(Ess.Player.character(0)) end)
        cat:entry("Give $100,000", function() Ess.Player.giveCash(100000) end)
    end)
    menu:entry(function() return "Photo mode       : " .. onoff(T.photo) end, function() togglePhoto() end)
    menu:category("Camera recorder", function(cat)
        cat:header("Walk to a spot, drop a keyframe, repeat -- then play")
        cat:entry(function() return "Drop keyframe (have " .. #T.keys .. ")" end, function() dropKeyframe() end)
        cat:entry("Play fly-through", function() playPath() end)
        cat:entry("Clear keyframes", function() T.keys = {}; Ess.UI.Toast("Keyframes cleared") end)
    end)

    T.menu = menu
    menu:open()
end

-- Toggle the hub on each F8 press.
if T.menu and T.menu:isOpen() then T.menu:close() else openHub() end
