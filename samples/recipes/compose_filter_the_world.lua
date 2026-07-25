-- RECIPE: ask the world a question, then filter/sort/count the answer.
-- Namespaces: Ess.Probe, Ess.Table, Ess.Object, Ess.Math, Ess.Player.
--
-- Part of the compose_* track (see compose_a_closure.lua for what that means).
--
-- WHY THIS ONE ISN'T A GRAPH. `Ess.Probe.nearby` hands back a LIST of unknown length. A node graph is built
-- around a fixed set of wires you drew in advance: it has no natural way to say "for each of however many
-- things came back, test it, keep the ones that matter, and sort what's left." The visual editor's own docs
-- name this gap outright -- a list parameter there is a text widget where you type a Lua table literal by
-- hand. Iteration is the first thing you genuinely gain by writing the Lua yourself.
--
-- Ess.Table is the toolkit for it: .filter/.map/.find/.reduce over the array part, all non-mutating and all
-- returning DENSE arrays (never a nil hole -- see Ess.Table.compact's header for why that distinction bites).

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

local px, py, pz = Ess.Player.pose(0)
if not px then Ess.Log("[SMOKE] compose_filter_the_world: FAIL (no player position)") return end

-- One query: everything within 120 units. `nearby` excludes the player by default.
local all = Ess.Probe.nearby(px, py, pz, 120, "any")
Ess.Log(string.format("[recipe] compose_filter_the_world: %d objects within 120u", #all))

-- Decorate each guid with what we care about. map() gives a parallel array of plain tables -- easier to sort
-- and read than juggling several arrays of raw guids.
local seen = Ess.Table.map(all, function(g)
    local x, y, z = Ess.Object.pos(g)
    return {
        guid = g,
        alive = Ess.Object.alive(g),
        hp = Ess.Object.health(g),
        dist = (x and Ess.Math.dist2D(px, pz, x, z)) or 9999,
    }
end)

-- Now the questions a graph can't ask. Each is one line because Ess.Table already has the shape.
local alive     = Ess.Table.filter(seen, function(o) return o.alive end)
local hurt      = Ess.Table.filter(alive, function(o) return o.hp and o.hp < 100 end)
local closest   = Ess.Table.reduce(seen, function(best, o)
    if not best or o.dist < best.dist then return o end
    return best
end, nil)
local totalHp   = Ess.Table.reduce(alive, function(sum, o) return sum + (o.hp or 0) end, 0)

-- Sorting is plain Lua -- table.sort in place on a copy, so `seen` keeps its original order.
local byDistance = Ess.Table.copy(seen)
table.sort(byDistance, function(a, b) return a.dist < b.dist end)

Ess.Log(string.format("[recipe] compose_filter_the_world: %d alive, %d of them hurt, %d total HP",
    #alive, #hurt, totalHp))
if closest then
    Ess.Log(string.format("[recipe] compose_filter_the_world: nearest is %.1fu away (%s)",
        closest.dist, tostring(Ess.Probe.describeSafe(closest.guid))))
end

-- Find the first thing matching a predicate, without scanning by hand. find() returns value, index.
local firstFar, atIndex = Ess.Table.find(byDistance, function(o) return o.dist > 50 end)
if firstFar then
    Ess.Log(string.format("[recipe] compose_filter_the_world: first past 50u is entry %d at %.1fu",
        atIndex, firstFar.dist))
end

-- Self-check: the derived sets have to be internally consistent, whatever happens to be nearby right now
-- (an empty world is a legitimate result -- being ALONE isn't a failure, so #all == 0 still passes).
local ok = (#alive <= #seen) and (#hurt <= #alive) and (#seen == #all)
if #byDistance > 1 then
    ok = ok and (byDistance[1].dist <= byDistance[#byDistance].dist)   -- the sort really sorted
end
if closest and #seen > 0 then
    ok = ok and (closest.dist <= byDistance[1].dist + 0.001)            -- reduce agrees with the sort
end

Ess.Log("[SMOKE] compose_filter_the_world: " .. (ok and "PASS" or "FAIL"))
