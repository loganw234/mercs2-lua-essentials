-- Ess/99_adopt.lua -- Ess.Net / Ess.UI / Ess.Contract: thin, existence-checked aliases onto ModNet/uilib/
-- ContractFramework, when (and only when) they're actually deployed alongside Ess in the same game
-- install. "Adopt, don't duplicate" -- these are mature, independently engine/co-op-verified frameworks
-- with their own repos; Ess deliberately does NOT reimplement any of them, only offers a shorter, more
-- consistent name to reach them by once they're present.
--
-- NEVER a hard dependency: this file must load and Ess must work completely fine whether or not any of
-- these three globals exist yet. Confirmed real global names, read directly from each framework's own
-- source (not assumed): ModNet.lua declares `_G.ModNet`, uilib.lua declares `_G.UI`,
-- 1_ContractFramework.lua declares `_G.Contract` -- all via the standard `_G.X = _G.X or {}` reload-safe
-- idiom, so aliasing them here (running from Ess's OnLoad, whichever numeric priority order these load
-- in) is safe regardless of which one happens to load first.
--
-- OUT OF SCOPE for this file (and for Ess generally, for now): rebasing uilib.lua's own internals onto
-- Ess.Loop/Ess.Input/Ess.Gfx so it stops hand-rolling its own copies of those primitives -- that's a
-- cross-repo change to an already-working, independently-verified framework, and belongs in a reviewed
-- change to uilib's own repo, not something this file does unsupervised. This file only ever ADDS a
-- read-only alias field to Ess; it never touches ModNet/UI/Contract's own tables or files.

local Ess = _G.Ess

if _G.ModNet then
    Ess.Net = _G.ModNet
else
    Ess.Log("adopt: ModNet not present in this install -- Ess.Net unavailable")
end

if _G.UI then
    Ess.UI = _G.UI
else
    Ess.Log("adopt: uilib (_G.UI) not present in this install -- Ess.UI unavailable")
end

if _G.Contract then
    Ess.Contract = _G.Contract
else
    Ess.Log("adopt: ContractFramework (_G.Contract) not present in this install -- Ess.Contract unavailable")
end
