-- Ess/60_aiorders_raw.lua -- Ess.Raw.AIOrders: the small helpers under every AI_BEHAVIORS entry, exposed
-- directly for a behavior not in the Core built-in list.
--
-- API:
--   Ess.Raw.AIOrders.pri(p) -> "HiPri"|"MedPri"|"LoPri"
--   Ess.Raw.AIOrders.actor(g) -> uGuid          the DRIVER of a vehicle, or g itself if g isn't one
--   Ess.Raw.AIOrders.goal(args) -> handle|false  pcall-wrapped Ai.Goal
--   Ess.Raw.AIOrders.haste(g, speed)             pcall-wrapped Ai.SetHaste, no-op if speed is nil

local Ess = _G.Ess
Ess.Raw = Ess.Raw or {}
Ess.Raw.AIOrders = Ess.Raw.AIOrders or {}

local AI_PRI = { hi = "HiPri", high = "HiPri", med = "MedPri", medium = "MedPri", lo = "LoPri", low = "LoPri" }
function Ess.Raw.AIOrders.pri(p)
    return AI_PRI[tostring(p or "hi"):lower()] or "HiPri"
end

-- Ess.Raw.AIOrders.actor(g) -> uGuid
-- CONFIRMED rule (ContractFramework.lua's `aiActor`, mirrors pircon004's chaser): AI goals must target the
-- DRIVER of a vehicle, not the vehicle hull itself, or the order silently does nothing.
function Ess.Raw.AIOrders.actor(g)
    local ok, drv = pcall(Vehicle.GetDriver, g)
    if ok and drv then return drv end
    return g
end

function Ess.Raw.AIOrders.goal(args)
    local ok, h = pcall(Ai.Goal, args)
    return ok and h
end

function Ess.Raw.AIOrders.haste(g, speed)
    if speed then pcall(Ai.SetHaste, g, speed) end
end
