-- TwichUI settings: Vendor restocking (modules/Restock.lua): whether it is on, how it buys, and the spending limit for
-- a visit. The list of items and the class reagent suggestions are its own tab (pages/RestockItems.lua).

local R = TwichUI
local K = R.SettingsKit

-- The game's own money entry (a dialog with gold, silver and copper boxes), for the spending limit.
local function EditLimit(onSaved)
    local RS = R.Restock
    local function Save(copper)
        if type(copper) ~= "number" then return end
        local max = RS.LIMITS.limit[2]
        if copper > max then
            R.Print("the spending limit can be at most %s; it wasn't changed.", RS.MoneyText(max))
            return
        end
        if RS.Set("limit", math.floor(copper)) and onSaved then onSaved() end
    end
    StaticPopupDialogs.TWICHUI_RESTOCK_LIMIT = {
        text = "Spend at most this much on restocking at one merchant visit. 0 means nothing is bought.",
        button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
        hasMoneyInputFrame = 1,
        OnShow = function(dialog)
            if dialog and dialog.MoneyInputFrame and MoneyInputFrame_SetCopper then
                MoneyInputFrame_SetCopper(dialog.MoneyInputFrame, RS.Get("limit"))
            end
        end,
        OnAccept = function(dialog)
            if dialog and dialog.MoneyInputFrame and MoneyInputFrame_GetCopper then
                Save(MoneyInputFrame_GetCopper(dialog.MoneyInputFrame))
            end
        end,
        OnHide = function(dialog)
            if dialog and dialog.MoneyInputFrame and MoneyInputFrame_ResetMoney then MoneyInputFrame_ResetMoney(dialog.MoneyInputFrame) end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("TWICHUI_RESTOCK_LIMIT")
end

-- Asked once, before TwichUI may buy without asking: what that authorizes.
local function ConfirmAuto(accept)
    R.Interact.Confirm("TWICHUI_RESTOCK_AUTO",
        "Buy restock items automatically?\n\nWhenever you open a merchant that sells an item on your restock list that is on and below its target, TwichUI buys enough to reach the target, without asking first. That spends your money at matching merchants. Your spending limit for a visit, the money you have and the room in your bags still apply, and it never sells anything to pay for it.\n\nThis confirmation is kept for your account on this computer. A profile or a shared setup can choose automatic buying, but it only buys without asking once you have confirmed it here.",
        accept, { accept = "Buy automatically" })
end

-- A change made anywhere (the list's tab, a profile change, an import) shows on the open page.
if R.Restock then R.Restock.OnChange(function() K.RefreshOverview() end) end

K.Page({
    key = "restock", name = "Vendor restocking", order = 45, group = "everyday",
    description = "Keep chosen items, such as reagents and ammunition, at a set number in your bags, bought from merchants that sell them.",
    keywords = "restock restocking reagent reagents buy purchase vendor merchant ammo ammunition arrows shot powder candle rune supplies automatic spend gold",
    when = function() return R.Restock ~= nil end,
    overview = {
        label = "Vendor restocking", tip = "Keep chosen items at a set number in your bags, bought from merchants that sell them.",
        status = function()
            local RS = R.Restock
            return K.OnOff(RS.Enabled(), RS.Mode() == "auto" and "Buys automatically" or "Asks first", "Off")
        end,
    },
    build = function()
        local Header, Toggle, Choice, ProxyToggle, Button, Under = K.Header, K.Toggle, K.Choice, K.ProxyToggle, K.Button, K.Under
        local RS = R.Restock

        Header("Vendor restocking", "Choose items and how many to keep. Keep 20 in your bags: if you have 7 and a merchant sells it, TwichUI tries to buy 13. Only your carried bags count (quivers, pouches and other special bags included), never your bank, mail or what you have equipped. Nothing is sold to pay for it.")
        local toggle = Toggle("restock", "Restock from merchants",
            "When you open a merchant that sells an item on your restock list, TwichUI counts how many you carry and buys the difference to your target. Only items that are on in the list, and only for gold: anything that costs tokens, items or another currency is left alone. One go per visit; it stops when the merchant closes or combat starts.\n\nIt asks first unless you choose to buy automatically. Off by default, with an empty list.")
        local function On() return RS.Enabled() end

        local modeRow
        modeRow = Under(Choice("restockMode", "When a merchant sells what you need",
            "Ask before purchasing: a question lists what would be bought, how many, at what price and the total. Nothing is bought unless you press Purchase; Cancel buys nothing.\n\nPurchase automatically: buys without asking. It still keeps to your spending limit, your money and your bag space, and checks every purchase again before making it. TwichUI asks you to confirm this the first time.",
            K.STRING, RS.DEFAULTS.mode, RS.SavedMode,
            function(value)
                if value == "auto" and not RS.Acknowledged() then
                    ConfirmAuto(function()
                        RS.Acknowledge()
                        RS.Set("mode", "auto")
                        if modeRow then modeRow:GetSetting():NotifyUpdate() end
                    end)
                    return
                end
                RS.Set("mode", value)
            end, {
                { "ask", "Ask before purchasing", "Shows what would be bought, and buys only when you press Purchase." },
                { "auto", "Purchase automatically", "Buys without asking, within your limits. Asks you to confirm this once." },
            }), toggle, On)
        -- chosen somewhere else (another computer, a profile, a shared setup) and not confirmed here: it asks first
        K.Note(modeRow, function()
            if RS.AutoWaiting() then
                return "Purchase automatically isn't confirmed on this account yet, so TwichUI asks first. Use Confirm below.", "warn"
            end
        end)
        Under(Button("Confirm automatic buying", function() return RS.Acknowledged() and "Confirmed" or "Confirm" end, function()
            ConfirmAuto(function()
                RS.Acknowledge()
                if modeRow then modeRow:GetSetting():NotifyUpdate() end
            end)
        end, "Needed when Purchase automatically was chosen in a profile or a shared setup, or on another computer: until you confirm it here, TwichUI asks before buying. Choosing it above asks you to confirm it then."),
            toggle, function() return On() and RS.AutoWaiting() end, function()
                if RS.Acknowledged() then return "Already confirmed on this account." end
                if not On() then return "Needs \"Restock from merchants\" turned on." end
                return "Nothing to confirm: Purchase automatically isn't chosen."
            end)

        local limit = Under(ProxyToggle("restockUseLimit", "Limit spending per merchant visit",
            "Off: no limit of TwichUI's own; purchases are limited by the money you have.\n\nOn: one visit to a merchant spends at most the amount below on restocking, across all items together. It limits spending, not your targets: when it runs out, items higher in your list are bought first and the rest wait for another visit. 0 means nothing is bought.",
            RS.DEFAULTS.useLimit, function() return RS.Get("useLimit") end,
            function(value) RS.Set("useLimit", value and true or false) end), toggle, On)
        Under(Button("Spending limit per visit", function() return RS.MoneyText(RS.Get("limit")) end, function()
            EditLimit(K.RefreshOverview)
        end, "The most one merchant visit may spend on restocking. Click to change it in the game's gold, silver and copper boxes."),
            limit, function() return On() and RS.Get("useLimit") == true end,
            "Greyed out unless \"Limit spending per merchant visit\" is on.")

        Header("Restock items", "The items to keep, each with its own target and an on/off switch, and suggestions for your class's reagents.")
        Button("Restock items", "Edit", function() R:OpenSettings("restockItems") end,
            "Add items by dropping them from your bags or typing their item ID, set how many to keep, turn each on or off, and choose the order they are bought in.")
        K.Status("On your list", function()
            local all, on = 0, 0
            for _, rule in ipairs(RS.Rules()) do
                all = all + 1
                if rule.enabled then on = on + 1 end
            end
            if all == 0 then return "Nothing yet" end
            return ("%d %s, %d on"):format(all, all == 1 and "item" or "items", on)
        end, nil, "How many items are on your restock list, and how many of them are on.")

        -- The question window's look (modules/RestockPrompt.lua). Not tied to the switch above: the look can be set
        -- before restocking is turned on, and the preview uses made-up items.
        local PR = R.RestockPrompt
        if PR and PR.Style then
            local Style = PR.Style
            local rowsBy = {}
            local function Rim() return Style.Get("borderTexture") == PR.LEDGER end
            local function Decorate(suffix, row)
                rowsBy[suffix] = row
                if suffix == "BorderSize" then
                    Under(row, rowsBy.BorderTexture, function()
                        return Style.Get("borderTexture") ~= "none" and not Rim()
                    end, function()
                        if Style.Get("borderTexture") == "none" then return "Greyed out: no border is drawn." end
                        return "Greyed out: the TwichUI rim has a fixed width. Pick another border to set a thickness."
                    end)
                elseif suffix == "BorderColor" or suffix == "BorderOpacity" then
                    Under(row, rowsBy.BorderTexture, function()
                        return Style.Get("borderTexture") ~= "none" and not Rim()
                    end, function()
                        if Style.Get("borderTexture") == "none" then return "Greyed out: no border is drawn." end
                        return "Greyed out: the TwichUI rim keeps its own colors. Pick another border to set a color."
                    end)
                end
            end
            Header("Question window appearance", "How the window that asks \"Restock from this merchant?\" looks: its background and border. Only the look changes; what it asks, the rows, the total and the Purchase and Cancel buttons are the same, and nothing is bought unless you press Purchase. The default is the TwichUI rim over a dark page; any other border replaces the rim and the window grows to give it room. The title band, the list and the total panel keep their own tint.")
            K.Appearance(Style, "restockPrompt", "window",
                "Shows the real window beside these settings with made-up items, to see these changes as you make them. Purchase and Cancel in it only close it: nothing is bought, and no merchant is involved. Esc closes it too.",
                function() PR.TogglePreview() end,
                "Question window appearance", "Puts the background and border of the question window back to their defaults. Your restock list, how it buys and the spending limit are not touched.",
                nil, nil, { decorate = Decorate })
        end
    end,
})
