-- Ess/61_relations_easy.lua -- Ess.Easy.Relations: the two genuinely common presets, no {a,b,set} tuple
-- vocabulary to learn. Uses one fixed internal id, so only ONE easy-tier relation set can be active at a
-- time -- deliberate: this tier is guardrails for the common single-encounter case, not the general
-- multi-id tool (use Ess.Relations directly for that).

local Ess = _G.Ess
Ess.Easy = Ess.Easy or {}
Ess.Easy.Relations = Ess.Easy.Relations or {}

local EASY_ID = "_Ess_Easy_Relations"

-- Ess.Easy.Relations.makeHostile(factionList) -- every faction in the list becomes hostile to PMC.
function Ess.Easy.Relations.makeHostile(factionList)
    local pairsList = {}
    for _, f in ipairs(factionList or {}) do pairsList[#pairsList + 1] = { f, "PMC", "hostile" } end
    Ess.Relations.apply(EASY_ID, pairsList)
end

-- Ess.Easy.Relations.makeAllies(factionList) -- every pair within the list becomes mutually allied.
function Ess.Easy.Relations.makeAllies(factionList)
    local pairsList = {}
    local list = factionList or {}
    for i = 1, #list do
        for j = i + 1, #list do
            pairsList[#pairsList + 1] = { list[i], list[j], "ally" }
        end
    end
    Ess.Relations.apply(EASY_ID, pairsList)
end

function Ess.Easy.Relations.restore()
    Ess.Relations.restore(EASY_ID)
end
