local KEYVAL = "f2"   -- must be in the first 10 lines (add "CoopChat.lua=f2" under [OnKey])

-- CoopChat.lua -- co-op text chat, built on the Essentials framework (Ess.Net + Ess.UI.Chat).
--
-- A SAMPLE of how little a mod has to do once it sits on Ess. Every hard part of co-op messaging -- the
-- collision-proof callback hijack, packing/chunking, reassembly, the sender id, the ready-gate handshake --
-- lives in Ess.Net; the scrolling window + typed input line is Ess.UI.Chat. This file is just glue: send
-- typed lines on the "chat" channel, show received lines titled P1/P2, and freeze local movement while
-- typing. Compare its length to everything Ess absorbs to run it.
--
-- Refit from the older ModNet_CoopChat.lua, which sat on the standalone _G.ModNet + _G.UI globals. Those two
-- frameworks are now absorbed natively into Ess, so this consumes Ess.Net / Ess.UI / Ess.Player instead --
-- no separate ModNet.lua or uilib.lua deployment, just Ess.
--
-- DEPLOY (both machines): Ess (dist/Ess.lua) as an OnLoad script loads first (e.g. scripts/OnLoad/1_Ess.lua);
-- then this file under scripts/OnKey/ with  CoopChat.lua=f2  under [OnKey]. Run ONE co-op chat script, not
-- several -- they would all claim the same "chat" wire.
----------------------------------------------------------------------------

local Ess = _G.Ess
if not (Ess and Ess.UI and Ess.UI.Chat and Ess.Net and Ess.Net.Send) then
  if Loader and Loader.Printf then
    Loader.Printf("[coopchat] load the Essentials framework (dist/Ess.lua) as an OnLoad script first")
  end
  return
end

local CH = "chat"

local function label(id) return "P" .. (tonumber(id or 0) + 1) end   -- player id 0/1 -> P1/P2

-- onSubmit: broadcast the line over Ess.Net, then retitle the prompt's bare local echo to "P<me>: text".
-- Ess.UI.Chat's prompt pushes the raw typed line first (then calls this), so we pop those wrapped lines
-- back off and re-push the titled version -- keeping the local echo consistent with how the peer sees it.
local function onSubmit(text)
  Ess.Net.Send(CH, text)
  local ui = _G.EssCoopChat and _G.EssCoopChat.ui
  if ui and ui._log then
    local wrap = Ess.UI.wrap(text, 52)
    if type(wrap) == "table" then
      for _ = 1, #wrap do table.remove(ui._log) end       -- drop the bare lines the prompt just pushed
      ui:push(label(Ess.Net.Me()) .. ": " .. text)         -- re-push, titled with this machine's player id
    end
  end
end

-- ===== build once: the Ess.UI.Chat window + the movement-freeze wraps =====
if not _G.EssCoopChat then
  _G.EssCoopChat = {}
  local C = _G.EssCoopChat
  C.ui = Ess.UI.Chat{ x = 20, y = 330, w = 384, title = "CO-OP CHAT", onSubmit = onSubmit }

  -- Freeze local player movement/actions while the input line has focus (typing stays intact -- Ess.Player.
  -- setInputEnabled gates GAME control only, not the keyboard stream the UI reads). Wrap Chat's own prompt/
  -- _endInput so entering input disables control and leaving it restores.
  local basePrompt, baseEnd = C.ui.prompt, C.ui._endInput
  C.ui.prompt    = function(self, cb) Ess.Player.setInputEnabled(false); return basePrompt(self, cb) end
  C.ui._endInput = function(self)     Ess.Player.setInputEnabled(true);  return baseEnd(self)      end

  C.ui:push("[co-op chat ready -- press " .. KEYVAL .. " to type]")
  Ess.Log("[coopchat] built on Ess.Net + Ess.UI.Chat")
end

-- ===== each keypress: (re)register the receiver (idempotent), then open the input line =====
Ess.Net.On(CH, function(sender, text)
  local ui = _G.EssCoopChat and _G.EssCoopChat.ui
  if ui and type(text) == "string" then ui:push(label(sender) .. ": " .. text) end
end)

_G.EssCoopChat.ui:prompt(onSubmit)
