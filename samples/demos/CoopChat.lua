local KEYVAL = "f2"   -- must be in the first 10 lines (add "CoopChat.lua=f2" under [OnKey])

-- CoopChat.lua -- co-op text chat, built on the Essentials framework (Ess.Net + Ess.UI.Chat).
--
-- A SAMPLE of how little a mod has to do once it sits on Ess. Every hard part of co-op messaging -- the
-- collision-proof callback hijack, packing/chunking, reassembly, the sender id, the ready-gate handshake --
-- lives in Ess.Net; the scrolling window + typed input line is Ess.UI.Chat. This file is just glue: send
-- typed lines on the "chat" channel, show received lines titled with the sender's name, and freeze local
-- movement while typing. Compare its length to everything Ess absorbs to run it.
--
-- USERNAME: set the USERNAME constant below to your display name. It rides the wire with each message so the
-- OTHER player sees your lines titled "<name>: ...". Your OWN lines always echo as "You:". Leave it blank
-- ("") to fall back to the P1/P2 convention -- so this is fully back-compatible with a peer who never set one.
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

-- Your display name (see the header). Blank = fall back to the P1/P2 convention. Can also be changed at
-- runtime with  _G.EssCoopChat.username = "..."  -- the send below reads that if it's set.
local USERNAME = ""

local function label(id) return "P" .. (tonumber(id or 0) + 1) end   -- player id 0/1 -> P1/P2

-- onSubmit: broadcast the line (with our name) over Ess.Net, then retitle the prompt's bare local echo to
-- "You: text". Ess.UI.Chat's prompt pushes the raw typed line first (then calls this), so we pop those
-- wrapped lines back off and re-push the titled version. We send a { name, text } table so the peer can
-- title it with our name; Ess.Net.Send serializes tables natively, so no extra work.
local function onSubmit(text)
  local myName = (_G.EssCoopChat and _G.EssCoopChat.username) or USERNAME or ""
  Ess.Net.Send(CH, { name = myName, text = text })
  local ui = _G.EssCoopChat and _G.EssCoopChat.ui
  if ui and ui._log then
    local wrap = Ess.UI.wrap(text, 52)
    if type(wrap) == "table" then
      for _ = 1, #wrap do table.remove(ui._log) end       -- drop the bare lines the prompt just pushed
      ui:push("You: " .. text)                             -- your own lines always echo as "You:"
    end
  end
end

-- ===== build once: the Ess.UI.Chat window + the movement-freeze wraps =====
if not _G.EssCoopChat then
  _G.EssCoopChat = {}
  local C = _G.EssCoopChat
  C.username = USERNAME   -- seed from the config constant; editable at runtime via _G.EssCoopChat.username
  -- autoHide = 10: the window fades out 10s after the last message (frozen while you're typing), so co-op
  -- chatter doesn't sit on screen forever. Received/sent lines re-surface it automatically.
  C.ui = Ess.UI.Chat{ x = 20, y = 330, w = 384, title = "CO-OP CHAT", onSubmit = onSubmit, autoHide = 10 }

  -- Wrap Chat's own prompt/_endInput to (a) freeze local player movement/actions while the input line has
  -- focus -- typing stays intact, since Ess.Player.setInputEnabled gates GAME control only, not the keyboard
  -- stream the UI reads -- and (b) manage the window: opening the prompt re-shows a faded window; closing it
  -- (Esc) hides immediately, which is the "close it quicker than the 10s" manual dismiss. On Enter, Chat
  -- re-pushes the sent line right after _endInput, so the window pops back up for its 10s read window.
  local basePrompt, baseEnd = C.ui.prompt, C.ui._endInput
  C.ui.prompt    = function(self, cb) Ess.Player.setInputEnabled(false); self:show(); return basePrompt(self, cb) end
  C.ui._endInput = function(self)     Ess.Player.setInputEnabled(true);  baseEnd(self); self:hide() end

  C.ui:push("[co-op chat ready -- press " .. KEYVAL .. " to type]")
  Ess.Log("[coopchat] built on Ess.Net + Ess.UI.Chat")
end

-- ===== each keypress: (re)register the receiver (idempotent), then open the input line =====
-- The peer sends a { name, text } table (see onSubmit). Title the line with their name if they set one,
-- else fall back to P1/P2 from the sender id. Also tolerate a bare string (an older/other client that
-- sent plain text) so mismatched versions still read cleanly.
Ess.Net.On(CH, function(sender, msg)
  local ui = _G.EssCoopChat and _G.EssCoopChat.ui
  if not ui then return end
  local name, text
  if type(msg) == "table" then name, text = msg.name, msg.text else text = msg end
  if type(text) ~= "string" then return end
  local who = (type(name) == "string" and name ~= "") and name or label(sender)
  ui:push(who .. ": " .. text)
end)

_G.EssCoopChat.ui:prompt(onSubmit)
