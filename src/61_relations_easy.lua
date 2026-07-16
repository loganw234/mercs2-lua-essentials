-- Ess/61_relations_easy.lua -- Ess.Easy.Relations: the two genuinely common presets, no {a,b,set} tuple
-- vocabulary to learn. Tracks one handle internally, so only ONE easy-tier relation set can be active at a
-- time -- deliberate: this tier is guardrails for the common single-encounter case, not the general
-- multi-handle tool (use Ess.Relations directly for that). Calling makeHostile/makeAllies again first
-- restores whatever the previous easy-tier call set, so it can't leak or stack.

local Ess = _G.Ess
Ess.Easy = Ess.Easy or {}
Ess.Easy.Relations = Ess.Easy.Relations or {}

-- Ess.Easy.Relations.makeHostile(factionList) -- every faction in the list becomes hostile to PMC.
function Ess.Easy.Relations.makeHostile(factionList)
    Ess.Easy.Relations.restore()
    local pairsList = {}
    for _, f in ipairs(factionList or {}) do pairsList[#pairsList + 1] = { f, "PMC", "hostile" } end
    Ess.Easy.Relations._handle = Ess.Relations.apply(pairsList, "Easy.Relations")
end

-- Ess.Easy.Relations.makeAllies(factionList) -- every pair within the list becomes mutually allied.
function Ess.Easy.Relations.makeAllies(factionList)
    Ess.Easy.Relations.restore()
    local pairsList = {}
    local list = factionList or {}
    for i = 1, #list do
        for j = i + 1, #list do
            pairsList[#pairsList + 1] = { list[i], list[j], "ally" }
        end
    end
    Ess.Easy.Relations._handle = Ess.Relations.apply(pairsList, "Easy.Relations")
end

-- Ess.Easy.Relations.war(factionA, factionB) -- make two factions fight EACH OTHER (mutually hostile),
-- independent of the player. This is the faction-vs-faction case makeHostile CAN'T express -- makeHostile
-- only ever means "hostile to PMC (you)", so "China attacks the Allies" needs this instead.
function Ess.Easy.Relations.war(a, b)
    Ess.Easy.Relations.restore()
    Ess.Easy.Relations._handle = Ess.Relations.apply({ { a, b, "hostile" } }, "Easy.Relations")
end

-- Ess.Easy.Relations.sideWith(friendFaction, foeFaction) -- YOU (PMC) join `friend` against `foe` in one
-- call: PMC allies `friend`, PMC is hostile to `foe`, and `friend` is at war with `foe`. The whole stance
-- for "I'm helping side A crush side B" (e.g. sideWith("China","Allied") -- you back China's assault on the
-- Allied refinery).
function Ess.Easy.Relations.sideWith(friend, foe)
    Ess.Easy.Relations.restore()
    Ess.Easy.Relations._handle = Ess.Relations.apply({
        { "PMC", friend, "ally" },
        { "PMC", foe,    "hostile" },
        { friend, foe,   "hostile" },
    }, "Easy.Relations")
end

function Ess.Easy.Relations.restore()
    if Ess.Easy.Relations._handle then
        Ess.Relations.restore(Ess.Easy.Relations._handle)
        Ess.Easy.Relations._handle = nil
    end
end
