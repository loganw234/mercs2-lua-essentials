-- Ess/99_adopt.lua -- Ess.Contract: thin, existence-checked alias onto ContractFramework, when (and
-- only when) it's actually deployed alongside Ess in the same game install.
--
-- HISTORY: this file used to also alias Ess.Net -> ModNet and Ess.UI -> uilib. Both are now natively
-- absorbed into Ess itself (70_net.lua/71_net_wire.lua and 42_ui_engine.lua through 55_ui_board.lua) --
-- Ess.Net/Ess.UI are ALWAYS present with real functionality now, never "unavailable," so aliasing them
-- here would be actively wrong (and did log a misleading "unavailable" message for a night before this
-- was caught -- confirmed live, fixed here). Ess.Contract is the one piece not yet absorbed; this file
-- shrinks to just that, and should be deleted entirely once Ess.Contract absorbs ContractFramework.lua
-- too (see FEATURE_SHEET.md's port status).
--
-- NEVER a hard dependency: this file must load and Ess must work completely fine whether or not
-- ContractFramework is deployed. Confirmed real global name, read directly from its own source:
-- 1_ContractFramework.lua declares `_G.Contract` via the standard `_G.X = _G.X or {}` reload-safe idiom.

local Ess = _G.Ess

if _G.Contract then
    Ess.Contract = _G.Contract
else
    Ess.Log("adopt: ContractFramework (_G.Contract) not present in this install -- Ess.Contract unavailable")
end
