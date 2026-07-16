-- Ess/83_contract_easy.lua -- Ess.Easy.Contract: register+accept a single-objective contract in one call.
-- The one Core-tier namespace in the whole framework with no Easy tier at all until now -- a beginner
-- otherwise has to learn Register/def.id/Accept just to get "kill these guys" or "go here" working.
--
-- Ess.Easy.Contract.destroy(sTitle, tSpawns, tOpts) -> sId
-- Ess.Easy.Contract.reach(sTitle, at, radius, tOpts) -> sId
--   tOpts (both) = { desc=, reward={cash=,fuel=} }

local Ess = _G.Ess
local C = Ess.Contract
Ess.Easy = Ess.Easy or {}
Ess.Easy.Contract = Ess.Easy.Contract or {}

C._nextEasyContractId = C._nextEasyContractId or 0
local function quickAccept(sTitle, tObjectives, tOpts)
    tOpts = tOpts or {}
    C._nextEasyContractId = C._nextEasyContractId + 1
    local id = "easy" .. C._nextEasyContractId
    C.Register({ id = id, title = sTitle, objectives = tObjectives, reward = tOpts.reward })
    C.Accept(id)
    return id
end

-- Ess.Easy.Contract.destroy(sTitle, tSpawns, tOpts) -> sId
-- tSpawns = { {template, x, y, z, yaw?}, ... }, same shape as the Core Destroy builder's `spawns`.
function Ess.Easy.Contract.destroy(sTitle, tSpawns, tOpts)
    tOpts = tOpts or {}
    return quickAccept(sTitle, { C.Destroy({ desc = tOpts.desc or sTitle, spawns = tSpawns }) }, tOpts)
end

-- Ess.Easy.Contract.reach(sTitle, at, radius, tOpts) -> sId
-- at = {x,y,z}.
function Ess.Easy.Contract.reach(sTitle, at, radius, tOpts)
    tOpts = tOpts or {}
    return quickAccept(sTitle, { C.Reach({ desc = tOpts.desc or sTitle, at = at, radius = radius }) }, tOpts)
end
