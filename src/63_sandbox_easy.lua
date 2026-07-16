-- Ess/63_sandbox_easy.lua -- Ess.Easy.Sandbox: begins with every built-in provider on, no provider list
-- to think about -- the "just isolate everything for my arena/minigame" case.

local Ess = _G.Ess
Ess.Easy = Ess.Easy or {}
Ess.Easy.Sandbox = Ess.Easy.Sandbox or {}

function Ess.Easy.Sandbox.arena(id, opts)
    return Ess.Sandbox.begin(id, { "layers", "economy", "supports", "relations" }, opts)
end

function Ess.Easy.Sandbox.done(id)
    return Ess.Sandbox.finish(id)
end
