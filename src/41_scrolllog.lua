-- Ess/41_scrolllog.lua -- Ess.ScrollLog: a scrolling on-screen text buffer, via the ONE confirmed
-- bug-free construction path for MrxGuiTextBuffer.
--
-- API:
--   Ess.ScrollLog.new(name, x, y, w, h) -> scrollLog | nil
--   scrollLog:add(msg, duration)     -- duration defaults to 1s, deliberately short, see below
--   scrollLog:setVisible(bool)
--   scrollLog:clearAll()
--
-- CONFIRMED SHIPPED ENGINE BUG this works around (coop-chat-ui.md): the documented constructor,
-- `MrxGuiTextBuffer.InstantiateTextBuffer`, references a global `oWidget` that doesn't exist anywhere in
-- its own scope (a straightforward copy-paste bug in the shipped game code) -- calling it throws
-- `attempt to index a nil value (global 'oWidget')` and crashes whatever called it. Patching the
-- constructor from outside doesn't work either: the patched copy runs in the PATCHING script's own
-- environment, not MrxGuiTextBuffer's private one, so its own unqualified internal calls
-- (AddMessage/ClearMessages/etc, real functions private to that module) can't resolve and it strands mid-
-- init. The confirmed-working path instead uses a SECOND, never-broken constructor-equivalent:
-- `HandleInstantiationEventForTextBuffer(oWidget, tEvent)`, an event-driven initializer where `oWidget`
-- really is that function's own first parameter -- hand-build a bare widget, name it "MessageBox" (this
-- exact string flips on the translucent chat-box backdrop), and call this function on it directly. No
-- patch, no touching the buggy constructor at all. This ~30-line workaround was duplicated near-verbatim
-- between CoopChatUI and WorldProbeLogUI before this; one library instead of two hand-rolled copies.
--
-- CONFIRMED REAL BUG this also fixes: display-duration x message-count is real QUEUED wall-clock time --
-- each message occupies the box for its own duration before the next one can even show. An early version
-- of a bulk dump blindly copied a 15-second per-message default across 194 lines -- nearly 50 minutes of
-- queued messages, silently blocking every later update on that same box. `duration` here defaults to 1s
-- (not the native AddMessage's own longer defaults) specifically so this mistake can't repeat by omission
-- -- pass a longer duration explicitly for something that genuinely should linger.

import("MrxGui")
import("MrxGuiTextBuffer")

local Ess = _G.Ess
Ess.ScrollLog = Ess.ScrollLog or {}
Ess.ScrollLog._instances = Ess.ScrollLog._instances or {}

-- Ess.ScrollLog.new(name, x, y, w, h) -> scrollLog | nil
-- `name` is a reuse key: calling new() again with the same name returns the SAME instance rather than
-- building a second overlapping widget (the same "give it its own global name" caution CoopChatUI/
-- WorldProbeLogUI both apply, generalized so two callers can't collide on one shared box).
function Ess.ScrollLog.new(name, x, y, w, h)
    if Ess.ScrollLog._instances[name] then return Ess.ScrollLog._instances[name] end
    x, y, w, h = x or 20, y or 150, w or 340, h or 220

    local ok, box = pcall(function()
        local b = MrxGui.ImageWidget:new()
        b:SetLocation(x, y, x + w, y + h)
        b.BasicData = b.BasicData or {}
        b.BasicData.name = "MessageBox"

        local initFunc = _G.HandleInstantiationEventForTextBuffer
            or (_G.MrxGuiTextBuffer and _G.MrxGuiTextBuffer.HandleInstantiationEventForTextBuffer)
        if not initFunc then return nil end
        initFunc(b, {})

        b:SetColor(24, 24, 24)
        b:SetTranslucency(200)
        local okp, p = pcall(Player.GetLocalPlayer)
        if okp and p then pcall(function() b:SetOwner(p) end) end

        MrxGui.AddWidget(b)
        b:SetVisible(false)
        return b
    end)
    if not ok or not box then
        Ess.Log("ScrollLog.new: failed to build a text buffer for '" .. tostring(name) .. "'")
        return nil
    end

    local sl = { box = box, shown = false }

    function sl:add(msg, duration)
        if not self.box or not self.box.AddMessage then return end
        -- Real confirmed signature: AddMessage(sMessage, nPriority, nDisplayDuration, nFadeDuration,
        -- bClearBuffer, bAllowsAppends). Priority 5 / fade 1s / no-clear / allow-appends, matching the
        -- confirmed WorldProbeLogUI convention.
        pcall(function() self.box:AddMessage(msg, 5, duration or 1, 1, false, true) end)
        self:setVisible(true)
    end

    function sl:setVisible(bOn)
        bOn = bOn and true or false
        pcall(function() self.box:SetVisible(bOn) end)
        self.shown = bOn
    end

    function sl:clearAll()
        if self.box and self.box.ClearMessages then pcall(function() self.box:ClearMessages() end) end
    end

    Ess.ScrollLog._instances[name] = sl
    return sl
end
