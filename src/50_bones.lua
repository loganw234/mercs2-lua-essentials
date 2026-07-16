-- Ess/50_bones.lua -- Ess.Bones: reading/attaching to any bone or hardpoint on a character or vehicle.
--
-- API:
--   Ess.Bones.attachFX(uGuid, bone, template) -> uFx | nil
--   Ess.Bones.detachFX(uGuid, uFx) -> ok
--   Ess.Bones.waitForReady(uGuid, cb, maxTries)
--   Ess.Bones.aimVector(uGuid, hpBase, hpTip) -> dx, dy, dz | nil
--   Ess.Bones.probeNames(uGuid, prefixes, suffixes) -> { {name=,x=,y=,z=}, ... }, nTried
--
-- Confirmed live (human-skeleton-boneprobe, wiki/deep-dives/bone-manipulation.md): every bone on a
-- character AND a vehicle is reachable from Lua by name -- `Object.GetHardpointPosition`/`Object.Attach`/
-- `Object.SetTransformToObject` hash the name string (pandemic_hash_m2) rather than looking it up as
-- text, so `hp_*` declared hardpoints and raw `bone_*` skeleton joints resolve through the exact same
-- lookup. 85/89 base human bones + all 158 Allied Destroyer bones confirmed resolving live.

local Ess = _G.Ess
Ess.Bones = Ess.Bones or {}

-- Ess.Bones.attachFX(uGuid, bone, template) -> uFx | nil
-- The confirmed 3-call recipe: read the bone's world position, spawn the FX there, attach it to the
-- bone, then snap its transform exactly onto the bone so it doesn't drift before the next tick. Returns
-- the spawned FX guid (pass to detachFX later) or nil if any step failed (bad bone name, blank template,
-- spawn failure).
function Ess.Bones.attachFX(uGuid, bone, template)
    if type(template) ~= "string" or template:match("^%s*$") then
        Ess.Log("Bones.attachFX: blank template rejected (would CTD Pg.Spawn)")
        return nil
    end
    local okp, x, y, z = pcall(Object.GetHardpointPosition, uGuid, bone)
    if not okp or not x then return nil end
    local oks, uFx = pcall(Pg.Spawn, template, x, y, z, 0)
    if not oks or not uFx then return nil end
    pcall(Object.Attach, uGuid, bone, uFx)
    pcall(Object.SetTransformToObject, uFx, uGuid, bone)
    return uFx
end

-- Ess.Bones.detachFX(uGuid, uFx) -> ok
-- Undoes attachFX: Detach then Remove. Safe to call with a nil uFx (a no-op, not an error) so callers
-- don't need their own nil-guard around cleanup.
function Ess.Bones.detachFX(uGuid, uFx)
    if not uFx then return false end
    pcall(Object.Detach, uGuid, uFx)
    local ok = pcall(Object.Remove, uFx)
    return ok and true or false
end

-- Ess.Bones.waitForReady(uGuid, cb, maxTries)
-- CONFIRMED GOTCHA: a freshly Pg.Spawn'd model's hardpoints return nil for ~0.3s after spawn -- reading
-- them synchronously at spawn time silently fails. This polls every 0.1s (via Ess.Loop) until `uGuid`
-- has a resolvable position, then calls cb(uGuid); gives up and calls cb(uGuid) anyway after `maxTries`
-- (default 6, i.e. ~0.6s -- comfortably past the documented ~0.3s window) so a caller is never left
-- hanging on a guid that's genuinely broken, though cb should still defensively re-check whatever bone
-- it actually needs.
--
-- DESIGN NOTE: this checks Object.GetPosition, not a specific bone -- waitForReady doesn't know which
-- hardpoint the caller ultimately wants (a character and a vehicle have entirely different bone names),
-- so a resolvable overall position is used as a universal "this object's transform hierarchy has
-- initialized" proxy instead. If a caller has one exact bone name in mind, polling
-- Object.GetHardpointPosition on that name directly is a strictly stronger check -- do that inline
-- instead of this helper when the bone name is already known.
function Ess.Bones.waitForReady(uGuid, cb, maxTries)
    maxTries = maxTries or 6
    local tries = 0
    Ess.Loop.start("Ess.Bones.waitForReady:" .. tostring(uGuid), 0.1, function()
        tries = tries + 1
        local ok, x = pcall(Object.GetPosition, uGuid)
        if ok and x then
            local okc, err = pcall(cb, uGuid)
            if not okc then Ess.Log("Bones.waitForReady callback error: " .. tostring(err)) end
            return false
        end
        if tries >= maxTries then
            Ess.Log("Bones.waitForReady: gave up after " .. tostring(maxTries) .. " tries, calling back anyway")
            local okc, err = pcall(cb, uGuid)
            if not okc then Ess.Log("Bones.waitForReady callback error: " .. tostring(err)) end
            return false
        end
        return true
    end)
end

-- Ess.Bones.aimVector(uGuid, hpBase, hpTip) -> dx, dy, dz | nil
-- The vector between two hardpoints on the same object IS the aim/facing axis of whatever they mount
-- (e.g. a turret's "hp_seat_cannon" breech -> "hp_barreltip_cannon" muzzle gives the barrel line).
-- CONFIRMED on the Allied Destroyer's cannon -- this is genuinely new capability the destroyer deep-dive
-- originally said wasn't Lua-reachable, until the bone-probe work proved otherwise. Returns nil if
-- either hardpoint doesn't resolve (wrong name, or this model doesn't carry it).
function Ess.Bones.aimVector(uGuid, hpBase, hpTip)
    local ok1, bx, by, bz = pcall(Object.GetHardpointPosition, uGuid, hpBase)
    if not ok1 or not bx then return nil end
    local ok2, tx, ty, tz = pcall(Object.GetHardpointPosition, uGuid, hpTip)
    if not ok2 or not tx then return nil end
    return tx - bx, ty - by, tz - bz
end

-- Ess.Bones.probeNames(uGuid, prefixes, suffixes) -> hits, nTried
-- Generalizes DestroyerTool.ProbeHardpoints's prefix x suffix candidate-name sweep: builds every
-- `prefix..suffix` combination, pcall-probes Object.GetHardpointPosition for each, and returns the hits
-- (as {name=, x=, y=, z=}) plus how many candidates were tried in total.
--
-- HARD CAVEAT, keep this attached wherever this is used: GetHardpointPosition is confirmed HASH-KEYED
-- (pandemic_hash_m2) -- a garbage string can collide onto a real bone's hash and return real, valid
-- coordinates. A hit here is proof the STRING is a valid handle for some real node, NOT proof it's that
-- node's true dev name. This is a research/discovery tool, not something to build production logic on
-- top of the assumption that a hit means what its text suggests.
function Ess.Bones.probeNames(uGuid, prefixes, suffixes)
    local tried = {}
    local hits = {}
    local nTried = 0
    local function tryName(name)
        if tried[name] then return end
        tried[name] = true
        nTried = nTried + 1
        local ok, x, y, z = pcall(Object.GetHardpointPosition, uGuid, name)
        if ok and x then
            hits[#hits + 1] = { name = name, x = x, y = y, z = z }
        end
    end
    prefixes = prefixes or {}
    suffixes = suffixes or {}
    for _, prefix in ipairs(prefixes) do
        for _, suffix in ipairs(suffixes) do
            tryName(prefix .. suffix)
        end
    end
    return hits, nTried
end
