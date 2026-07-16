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

function Ess.Easy.Relations.restore()
    if Ess.Easy.Relations._handle then
        Ess.Relations.restore(Ess.Easy.Relations._handle)
        Ess.Easy.Relations._handle = nil
    end
end
