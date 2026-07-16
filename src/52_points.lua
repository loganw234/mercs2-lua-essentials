-- Ess/52_points.lua -- Ess.Points: pure spawn-point data transforms, ported from WaveDefense.lua's
-- bucketArena/idealPoints and generalized beyond wave-defense. No live world touched -- these operate on
-- plain coordinate tables, so they're testable offline/synthetically with no game running at all.
--
-- Point format: a spawn point is a 4-tuple {x, y, z, r} (matching MissionForge's arena export shape),
-- where r is an optional radius-tier hint (defaults to 3, i.e. infantry-tier, if omitted).
--
-- API:
--   Ess.Points.bucket(spawnList) -> { inf = {...}, veh = {...}, heli = {...} }
--   Ess.Points.ideal(pts, refX, refZ, opts) -> { p, ... }   opts = {minDist=18, maxDist=80, maxCount=24}

local Ess = _G.Ess
Ess.Points = Ess.Points or {}

-- Ess.Points.bucket(spawnList) -> { inf = {...}, veh = {...}, heli = {...} }
-- Direct port of WaveDefense.lua's bucketArena, generalized to take a plain list instead of mutating an
-- "arena" table in place: r<=5 -> infantry tier, r<=15 -> vehicle tier, r>15 -> heli tier (matches
-- MissionForge's own radius-tier convention). If NO point qualifies for the infantry tier, `.inf` falls
-- back to the full input list (WaveDefense's own fallback: "any point can take infantry") rather than an
-- empty table, so a caller drawing from `.inf` is never left with zero options.
function Ess.Points.bucket(spawnList)
    spawnList = spawnList or {}
    local out = { inf = {}, veh = {}, heli = {} }
    for _, p in ipairs(spawnList) do
        local r = p[4] or 3
        if r <= 5 then
            out.inf[#out.inf + 1] = p
        elseif r <= 15 then
            out.veh[#out.veh + 1] = p
        else
            out.heli[#out.heli + 1] = p
        end
    end
    if #out.inf == 0 then out.inf = spawnList end
    return out
end

-- Ess.Points.ideal(pts, refX, refZ, opts) -> { p, ... }
-- Direct port of WaveDefense.lua's idealPoints: nearest-first distance-windowed point selection around a
-- reference (refX, refZ) -- note Y is deliberately ignored, matching the source (arena spawn points are
-- compared on the horizontal plane only). opts.minDist/maxDist/maxCount default to WaveDefense's own
-- confirmed-working values (18/80/24 -- "use more spawn points -> fewer enemies per point").
--
-- Three-tier fallback, exactly as confirmed in the source (each existing to guarantee SOME usable output
-- rather than an empty result the caller has to special-case):
--   1. Points within [minDist, maxDist], nearest first, capped at maxCount.
--   2. If fewer than 4 came back, drop the maxDist ceiling (keep only the minDist floor) and retry.
--   3. If STILL zero, return every point unfiltered.
function Ess.Points.ideal(pts, refX, refZ, opts)
    opts = opts or {}
    local minDist = opts.minDist or 18
    local maxDist = opts.maxDist or 80
    local maxCount = opts.maxCount or 24

    pts = pts or {}
    local scored = {}
    for _, p in ipairs(pts) do
        local dx, dz = p[1] - refX, p[3] - refZ
        scored[#scored + 1] = { p = p, d = dx * dx + dz * dz }
    end
    table.sort(scored, function(a, b) return a.d < b.d end)

    local out = {}
    for _, s in ipairs(scored) do
        local dist = math.sqrt(s.d)
        if dist >= minDist and dist <= maxDist then
            out[#out + 1] = s.p
            if #out >= maxCount then break end
        end
    end
    if #out < 4 then
        out = {}
        for _, s in ipairs(scored) do
            if math.sqrt(s.d) >= minDist then
                out[#out + 1] = s.p
                if #out >= maxCount then break end
            end
        end
    end
    if #out == 0 then out = pts end
    return out
end
