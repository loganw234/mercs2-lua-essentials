-- RECIPE: browse the engine's ECS component vocabulary -- Ess.Ecs.
-- Namespaces: Ess.Ecs.
--
-- An entity is assembled from reflection component classes. Ess.Ecs is the catalogue of all ~232, in 9
-- families, each with the component hash the engine's resolver keys on. Pure lookup -- no game needed to
-- browse it -- but it's the vocabulary a live component read (or the destruction/AI/physics tooling) names
-- things with.

local Ess = _G.Ess
if not Ess then if Loader and Loader.Printf then Loader.Printf("[recipe] load Ess first") end return end

Ess.Log("[recipe] ecs: " .. #Ess.Ecs.classes() .. " component classes across " .. #Ess.Ecs.families() .. " families")

-- the hash the engine keys on, for a couple of well-known components
Ess.Log("[recipe] ecs: RuntimeHealth=" .. tostring(Ess.Ecs.hash("RuntimeHealth"))
    .. "  StateMachine=" .. tostring(Ess.Ecs.hash("StateMachine")))

-- what's in the AI family, and where a class lives
local ai = Ess.Ecs.find("ai_perception_population")
Ess.Log("[recipe] ecs: ai_perception_population has " .. #ai .. " classes; ControllerCar is in "
    .. tostring(Ess.Ecs.family("ControllerCar")))

-- PASS = the registry is populated and the readers agree on a known class
local c = Ess.Ecs.get("runtimehealth")   -- case-insensitive
local ok = (#Ess.Ecs.classes() == 232)
    and (c ~= nil and c.h == "0xF9B9B2A5" and c.f == "gameplay_state_health_mission")
    and (Ess.Ecs.get("NoSuchComponent") == nil)
Ess.Log("[SMOKE] ecs: " .. (ok and "PASS" or "FAIL"))
