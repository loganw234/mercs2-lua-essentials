-- Ess/58_shop.lua -- Ess.Shop: the game's own full-screen purchase UI, driven from a mod.
--
-- API:
--   Ess.Shop.open(tItems [,tOpts]) -> bool   build and show a shop in one call
--   Ess.Shop.close()                         tear it down (also your escape hatch -- see below)
--   Ess.Shop.isOpen()                        -> bool
--   Ess.Shop.ICONS                           a few known-good item icon names
--
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHAT THIS IS
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- The stockpile/support store: a real modal Flash interface (store.gfx) with item tiles, icons, prices,
-- stock counts, an equip flow and a live cash/fuel readout. Nothing in Ess.UI comes close -- this is the
-- shipped game's own storefront, and a mod can fill it with arbitrary items and get a callback when the
-- player buys one.
--
-- The native surface is six calls that must happen in order (Create -> AddItem* -> SetCallback ->
-- SetCloseCallback -> Commence, then Close), each taking the player guid again, each silently returning
-- false on a wrong argument. Ess.Shop.open does the whole sequence and reports which step failed.
--
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- FIVE THINGS THAT WILL COST YOU AN HOUR IF YOU DO NOT KNOW THEM
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 1. USE THE FULL ITEM FORM FOR CUSTOM ITEMS. The native has a short AddItem and a long AddItemFull, and
--    the short one is NOT a convenience -- it is for the game's own catalogue. _SetupShopFlash only renders
--    an item if it has sDesc AND sTexture AND nCurrentStock, or if its sId is found in
--    MrxSupportData.tSupportData. A short-form item with an id the game does not know renders NOTHING, with
--    no error. Ess.Shop always uses the full form, and requires sDesc/sTexture, so this cannot happen.
--
-- 2. THE BUY CALLBACK'S ARGUMENTS COME AFTER YOUR CALLBACK DATA. _FlashSupportBoughtCallback copies your
--    tCallbackData, appends the item's sId and the quantity, and unpacks the lot. Passing no callback data
--    -- which is what this wrapper does -- makes the signature simply fn(sId, nQuantity). Same trap as
--    Ess.On.script, and the same fix: do not pass callback data and the arguments become legible.
--
-- 3. A SECOND Create FOR THE SAME PLAYER RETURNS FALSE. The shop is keyed by player guid in _tShopList and
--    Create refuses if an entry exists. So a shop left open blocks every later one. Ess.Shop.open closes
--    any existing shop first rather than failing.
--
-- 4. IT IS MODAL AND IT CAN STRAND THE PLAYER. _RunShop takes control focus and toggles the HUD off. Closing
--    with Escape was measured to leave the player WITH NO GAME CONTROL: the buy and close callbacks all
--    fired correctly and the shop deregistered itself, but input never came back. See Ess.Shop.close, which
--    exists as much to recover from that as to close a shop -- calling it when nothing is open is a valid,
--    supported rescue.
--
-- 5. THE ROOT CAUSE IS IN ReleaseControlFocus, and it is worth knowing about for ANY modal, not just this
--    one. It pops the focus queue, then only reassigns ControlModeManager[uOwner] IF THERE IS A NEXT
--    HOLDER -- so draining the queue to empty leaves the mode flag stuck at its previous value. Measured:
--    queue depth 0, holder nil, mode still `true`. Anything in Ess that takes control focus and is the last
--    holder inherits this, so reach for Ess.Shop.close's repair rather than rediscovering it.
--
-- ALSO WORTH KNOWING: the shop injects the player's three EQUIPPED SUPPORT SLOTS from the PDA on top of
-- whatever you add, so your items are never the only things in the list.
--
-- ON TIERING: there is no Ess.Easy.Shop, on purpose. The Easy tier is for verbs a beginner reaches for
-- constantly (mark this, spawn that); a modal storefront is a niche, deliberate thing to build, and a
-- one-liner preset would mostly hide the item table -- which IS the content. Ess.Shop.open is already the
-- whole six-call native sequence collapsed into one call, so the Core tier is doing that job. Revisit if a
-- common shape actually emerges from use.

local Ess = _G.Ess
Ess.Shop = Ess.Shop or {}

-- Item icon names from MrxSupportData. Not a closed set -- any loaded texture works -- but an unresolvable
-- name draws a BLACK BOX WITH AN X rather than failing, so the tile still appears and the mistake is easy
-- to miss in a list. These are the "supplies_*" family, all verified rendering live 2026-07-26.
--
-- Deliberately absent: "HUD_ICON_support_crate". It appears in mrxsupportdata.lua alongside these, and it
-- is the one that drew the placeholder box in testing -- so proximity in the source is not evidence a
-- texture resolves in THIS widget. Test an icon before relying on it.
Ess.Shop.ICONS = {
    "supplies_PMC_crate", "supplies_AN_crate", "supplies_CH_crate", "supplies_GR_crate",
    "supplies_OC_crate", "supplies_Blanco_crate", "supplies_anti_air", "supplies_anti_material",
    "supplies_anti_tank", "supplies_covert", "supplies_cqb", "supplies_CH_sniper",
}

local function localPlayer()
    local ok, p = Ess.Safe.quiet(Player.GetLocalPlayer)
    if ok and type(p) == "userdata" then return p end
    return nil
end

-- Ess.Shop.isOpen() -- whether a shop is currently registered for the local player.
function Ess.Shop.isOpen()
    return Ess.Shop._open == true
end

-- Ess.Shop.close() -- tear the shop down, and RECOVER THE PLAYER'S INPUT whatever state things are in.
--
-- This does more than call the native, because the native alone is not enough to get unstuck -- established
-- the hard way 2026-07-26, when closing a test shop with Escape left the player with no game control and
-- MrxGuiSupportShop.Close could not help, since it returns early unless _tShopList still has an entry and by
-- then it did not. Three separate pieces of state outlive the widget:
--
--   1. LTILibName.ChangeShellState(true), set by _RunShop and never cleared -- mrxguisupportshop.lua
--      contains exactly ONE call to it, while mrxbriefing.lua balances its pairs properly.
--   2. ControlModeManager, which is the real culprit. ReleaseControlFocus pops the queue and then only
--      reassigns ControlModeManager[uOwner] IF THERE IS A NEXT HOLDER -- so emptying the queue leaves the
--      flag stuck at its old value. Measured exactly that: queue depth 0, holder nil, mode still `true`.
--   3. The HUD, toggled off by _RunShop and restored only on the normal path.
--
-- The ControlModeManager repair is deliberately CONDITIONAL: it only fires when the focus queue is actually
-- empty, which is what makes a leftover flag provably stale. Clearing it unconditionally would stamp on a
-- legitimate holder -- a dialog box, the support menu -- that is genuinely mid-interaction.
--
-- Safe to call when nothing is open, which is the point: it is the escape hatch.
function Ess.Shop.close()
    local p = localPlayer()
    if p then pcall(function() Hud.Shop:Close({ uPlayer = p }) end) end
    Ess.Shop._open = false

    -- Balance the shell state the shop sets and never clears.
    Ess.Safe.quiet(function()
        if LTILibName and LTILibName.ChangeShellState then LTILibName.ChangeShellState(false) end
    end)

    if p then
        Ess.Safe.quiet(function()
            local q = MrxGuiBase.ControlFocusQueue and MrxGuiBase.ControlFocusQueue[p]
            local mode = MrxGuiBase.ControlModeManager and MrxGuiBase.ControlModeManager[p]
            -- Only when nothing holds focus is a set flag provably stale.
            if mode ~= nil and (not q or #q == 0) then
                if mode then MrxGuiBase.SetDialogBoxMode(p, false)
                else MrxGuiBase.SetSupportMenuMode(p, false) end
                MrxGuiBase.ControlModeManager[p] = nil
            end
        end)
        Ess.Safe.quiet(function() MrxGuiManager.ToggleHud(p, true) end)
    end
    return true
end

-- Ess.Shop.open(tItems [,tOpts]) -> bool
--
-- tItems is an array of item tables. Required per item: sName, sDesc, sTexture, nCost.
--
-- ── nOwned / nCap ARE THE PLAYER'S STOCKPILE, NOT SHELF INVENTORY ──────────────────────────────────────
-- The native calls these nCurrentStock and nMaxStock, which reads like "how many are for sale". It is not.
-- They describe HOW MANY THE PLAYER ALREADY HAS and the cap on holding them -- the purchase dialog labels
-- the first one STOCKPILE and counts upward from it as you pick a quantity. An item with nOwned = 0 is not
-- sold out; it is one the player owns none of yet, and they can still buy as many as nCap allows. Named
-- nOwned/nCap here so the wrong reading is not available. (Confirmed on screen: an item added with 0 was
-- bought four at a time.)
--
-- Optional: sId (defaults to sName -- it is what the buy callback reports, so give it a stable value if
-- sName is localised), nOwned (default 0), nCap (default 99), bUnlocked (default TRUE -- the native's own
-- default is false, which renders an item the player cannot buy, a confusing default for a mod), bNew,
-- bFuelTank, nFuelQuantity.
--
-- tOpts.onBuy(sId, nQuantity)  fires when the player buys. NOT when they close.
-- tOpts.onClose()              fires on close, however it happens -- button, or Ess.Shop.close().
--
-- Returns false and records a reject (visible under Ess.DEBUG) naming the step that failed.
function Ess.Shop.open(tItems, tOpts)
    if type(tItems) ~= "table" or #tItems == 0 then
        Ess.Safe.reject("Ess.Shop.open", "needs a non-empty array of item tables")
        return false
    end
    local p = localPlayer()
    if not p then
        Ess.Safe.reject("Ess.Shop.open", "no local player guid")
        return false
    end
    local o = type(tOpts) == "table" and tOpts or {}

    -- Create refuses while an entry exists for this player, so clear any stale one first. This is the
    -- difference between "the shop is broken" and "someone forgot to close the last one".
    if Ess.Shop._open then Ess.Shop.close() end

    local created = false
    pcall(function() created = Hud.Shop:Create({ uPlayer = p }) end)
    if not created then
        Ess.Safe.reject("Ess.Shop.open", "Hud.Shop:Create returned false -- a shop may already exist")
        return false
    end

    local nAdded = 0
    for _, it in ipairs(tItems) do
        if type(it) == "table" and type(it.sName) == "string" and type(it.sDesc) == "string"
           and type(it.sTexture) == "string" and tonumber(it.nCost) then
            local added = false
            pcall(function()
                added = Hud.Shop:AddItemFull({
                    uPlayer = p,
                    sName = it.sName, sDescription = it.sDesc, sTexture = it.sTexture,
                    nCashCost = tonumber(it.nCost),
                    -- The native's names; ours say what they mean. See the header note.
                    nCurrentStock = tonumber(it.nOwned) or 0,
                    nMaxStock = tonumber(it.nCap) or 99,
                    -- Default UNLOCKED. The native defaults this false, which draws an item the player is
                    -- not allowed to buy -- almost never what a mod means.
                    bUnlocked = (it.bUnlocked ~= false),
                    sId = it.sId or it.sName,
                    bFuelTank = it.bFuelTank and true or false,
                    bMarkAsNew = it.bNew and true or false,
                    nFuelQuantity = tonumber(it.nFuelQuantity),
                    sRawName = it.sRawName or it.sName,
                })
            end)
            if added then nAdded = nAdded + 1 end
        end
    end
    if nAdded == 0 then
        Ess.Shop.close()
        Ess.Safe.reject("Ess.Shop.open", "no item was accepted -- each needs sName, sDesc, sTexture, nCost")
        return false
    end

    -- No tCallbackData on purpose: it would be unpacked AHEAD of sId and nQuantity and shift the signature.
    if type(o.onBuy) == "function" then
        pcall(function()
            Hud.Shop:SetCallback({ uPlayer = p, fCallback = function(sId, nQty) pcall(o.onBuy, sId, nQty) end })
        end)
    end
    pcall(function()
        Hud.Shop:SetCloseCallback({ uPlayer = p, fCallback = function()
            Ess.Shop._open = false
            if type(o.onClose) == "function" then pcall(o.onClose) end
        end })
    end)

    local ok = pcall(function() Hud.Shop:Commence({ uPlayer = p }) end)
    if not ok then
        Ess.Shop.close()
        Ess.Safe.reject("Ess.Shop.open", "Commence failed")
        return false
    end
    Ess.Shop._open = true
    return true
end
