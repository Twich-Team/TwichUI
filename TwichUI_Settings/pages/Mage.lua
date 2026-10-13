-- TwichUI settings: Mage (Mages only): the travel and conjuring launchers, the refreshments panel and its trade
-- help, selling ordinary food and drink, and the look of the launchers' menus and of the panel.

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "mage", name = "Mage", order = 50, group = "class",
    description = "Data bar launchers for your teleports, portals and conjuring, a refreshments panel for your group, and selling ordinary food and drink.",
    keywords = "teleport portal conjure water food refreshments trade sell vendor merchant data bar broker menu",
    when = function() return R.MageTravel ~= nil and R.MageTravel.ForPlayer() end,   -- Mages only
    overview = {
        label = "Mage", tip = "Data bar launchers for your teleports and portals and for conjuring food and water, and a refreshments panel for your group.",
        status = function()
            local parts = (R.Refreshments and 3 or 2) + (R.MageSell and 1 or 0)
            local on = (R:Enabled("mageTravel") and 1 or 0) + (R:Enabled("mageConjure") and 1 or 0)
                + ((R.Refreshments and R:Enabled("mageRefreshments")) and 1 or 0)
                + ((R.MageSell and R.MageSell.Enabled()) and 1 or 0)
            return K.OnOff(on > 0, ("%d of %d on"):format(on, parts), "Off")
        end,
    },
    build = function()
        local Header, Toggle, Button, Choice, Under = K.Header, K.Toggle, K.Button, K.Choice, K.Under
        local STRING = K.STRING
        local MT = R.MageTravel

        Header("Mage Travel", "A launcher for your data bar that lists your teleports and portals. It casts only the one you click, and never chooses a destination for you.")
        local mage = Toggle("mageTravel", "Mage Travel launcher on my data bar",
            "Adds \"TwichUI Mage Travel\" to the list of your data bar addon (any that shows LibDataBroker launchers, such as EllesmereUI's Broker Plugin block). Click it for a small menu of the teleports and portals your faction can learn: click a learned one to cast it; hover one you haven't learned for the level it is trained at. It can't be opened in combat, and closes when combat starts.\n\nWithout a data bar addon there is nowhere for it to show. Turning it off takes it off your data bar after a reload.")
        Under(Choice("mageTravelText", "Text on the data bar",
            "The word shown beside the launcher's icon on your data bar. None leaves just the icon. If your data bar shows plugin names too, it may read \"Mage Travel: Travel\"; that is the data bar's own label option.",
            STRING, MT.DEFAULT_TEXT, MT.TextChoice, MT.SetTextChoice, MT.TEXTS),
            mage, function() return R:Enabled("mageTravel") end)

        local MC = R.MageConjure
        Header("Mage Conjuring", "A launcher for your data bar with your best Conjure Food and Conjure Water. It casts only the one you click.")
        local conjure = Toggle("mageConjure", "Mage Conjuring launcher on my data bar",
            "Adds \"TwichUI Mage Conjuring\" to the list of your data bar addon (any that shows LibDataBroker launchers, such as EllesmereUI's Broker Plugin block). Click it for a small menu with one entry each for Conjure Food and Conjure Water, the highest rank you have learned of each: click one to cast it. With none learned, the first rank is shown muted; hover it for the level it is trained at. Shift-left-click the launcher to conjure water and shift-right-click to conjure food, each at your highest rank. It can't be opened in combat, and closes when combat starts; the shift-clicks don't work in combat either.\n\nWithout a data bar addon there is nowhere for it to show. Turning it off takes it off your data bar after a reload.")
        Under(Choice("mageConjureText", "Text on the data bar",
            "The word shown beside the launcher's icon on your data bar. None leaves just the icon. If your data bar shows plugin names too, it may read \"Mage Conjuring: Conjure\"; that is the data bar's own label option.",
            STRING, MC.DEFAULT_TEXT, MC.TextChoice, MC.SetTextChoice, MC.TEXTS),
            conjure, function() return R:Enabled("mageConjure") end)

        local RF = R.Refreshments
        local refreshToggle   -- the refreshments switch, which its appearance is greyed out under
        if RF then
            Header("Mage refreshments", "Plan the conjured food and water you hand to your party or raid, conjure it by click or key, and tick off who you've supplied. TwichUI never casts, trades or whispers for you.")
            local refresh = Toggle("mageRefreshments", "Refreshments panel",
                "A small panel (/tui refreshments, or its key in Key Bindings > TwichUI) for getting your group fed and watered. It works out how much water and food your party or raid needs from each class's share and what you keep, at the best rank each person can use, against what is in your bags. Its Water and Food buttons conjure once per click or key press; drag one to an action bar to hold a key with the game's Press and Hold Casting instead. A checklist shows who you've supplied; you mark it yourself, and it starts again when you leave the group or reload.\n\nIt can't be opened in combat and closes when combat starts. Off by default.")
            refreshToggle = refresh
            local function RefreshOn() return R:Enabled("mageRefreshments") end
            Under(Button("Refreshments panel", "Open", function()
                K.CloseOptions()
                if R.RefreshmentsPanel then R.RefreshmentsPanel.Open() end
            end, "Opens the panel (same as typing /tui refreshments)."), refresh, RefreshOn)
            local RB = R.RefreshmentsBroker
            if RB then
                Under(Choice("refreshmentsText", "Text on the data bar",
                    "Adds \"TwichUI Mage Refreshments\" to the list of your data bar addon (any that shows LibDataBroker plugins, such as EllesmereUI's Broker Plugin block) once refreshments are on; no reload needed. Click it to open the panel, right-click for these options; hover it for how much water and food is prepared and who is supplied.\n\nThe word beside its icon: how many of your group are supplied (\"3/5 supplied\"), \"Refreshments\", or none. On your own it reads \"Refreshments\". Turned off, it reads \"Off\" until you reload.",
                    STRING, RB.DEFAULT_TEXT, RB.TextChoice, RB.SetTextChoice, RB.TEXTS), refresh, RefreshOn)
            end
            if R.RefreshmentsTrade then
                local trade = Under(Toggle("mageRefreshmentsTrade", "Fill trade button and trade tracking",
                    "While you trade with someone in your group, a small strip under the trade window shows what their share still asks for, with a Fill trade button. Nothing happens until you click it: it puts whole stacks of the rank planned for them into empty slots, and when a part stack is needed, splits it into an empty bag slot for your next click to add. It never takes out what is already in the window, never puts in anything else, and never accepts the trade.\n\nWhen the game says a trade was completed, what you offered is marked as handed over. If TwichUI can't confirm it, the panel asks you to confirm or dismiss it. People outside your group get no share."), refresh, RefreshOn)
                local RT = R.RefreshmentsTrade
                local function TradeOn() return RefreshOn() and R:Enabled("mageRefreshmentsTrade") end
                Under(Toggle("mageRefreshmentsAutoFill", "Fill trades automatically",
                    "When a trade with someone in your group opens, whoever opened it, what is planned for them goes in by itself a moment later, without clicking Fill trade; a part stack goes in once the game has split it. It never accepts the trade, never adds anything once either of you has pressed Trade, and stops for that trade as soon as you take something out of it. It waits while you hold something on the cursor or are in combat.\n\nIf the game doesn't allow it, it switches itself off until you reload (one line says so) and the Fill trade button still works."), trade, TradeOn)
                Under(Choice("refreshmentsTradeGives", "Each trade puts in",
                    "Their whole share: every trade with them gets their class's whole share again, however much they had before, for when they come back for more. What is handed over still adds up in the checklist.\n\nOnly what is still owed: their share less what they've been handed this session, so once they're supplied, a trade adds nothing.",
                    STRING, RT.DEFAULT_GIVES, RT.Gives, RT.SetGives, RT.GIVES), trade, TradeOn)
            end
            if R.RefreshmentShares then
                Button("Refreshment shares", "Edit", function() R:OpenSettings("refreshmentShares") end,
                    "How many water and food each class gets in a party and in a raid, and how many you keep. Single items, not stacks.")
            end
        end

        local MSL, MSW = R.MageSell, R.MageSellWindow
        if MSL then
            Header("Sell ordinary food and drink", "Optional. Sells plain, non-conjured food and drink when you open a merchant, so conjured refreshments are what your bags hold. Off by default. Conjured items, special food, quest items, anything locked or without a sell price, and anything on your never-sell list are always kept.")
            local sell = Toggle("mageSell", "Sell non-conjured food and drink",
                "When you open a merchant, TwichUI sells the ordinary food and drink in your bags: plain items that only restore health or mana. It keeps Mage-conjured food and water (made by you or another Mage), buff food, feasts, potions and reagents, quest items, locked items, items with no sell price, and anything on your never-sell list; when it can't tell, it keeps the item.\n\nIt starts in Dry run, which only says what it would sell. A visit sells at most a few stacks so your own sales stay in the merchant's Buyback tab, which holds a limited number; other sales can still push entries out. Nothing is destroyed, bought or taken from the bank, mail or anywhere but your bags.\n\nOff by default. Other Mage features don't turn it on.")
            local function SellOn() return MSL.Enabled() end
            Under(Toggle("mageSellFood", "Sell ordinary food",
                "Plain food that only restores health. Food that restores both health and mana is sold only when drink is on as well."), sell, SellOn)
            Under(Toggle("mageSellDrink", "Sell ordinary drink",
                "Plain drink that only restores mana. Food that restores both health and mana is sold only when food is on as well."), sell, SellOn)
            Under(Toggle("mageSellDryRun", "Dry run: report only, sell nothing",
                "While this is on, opening a merchant only tells you what would be sold, once, in your own chat. Nothing is sold. It is on until you turn it off: check /tui sell first, then turn it off to sell for real."), sell, SellOn)
            if MSW then
                Under(Button("Eligible items and never-sell list", "Open", function()
                    K.CloseOptions()
                    MSW.Show()
                end, "Shows what would be sold now and what is kept and why, and lets you add items to a never-sell list. Nothing is sold by opening it (same as /tui sell)."), sell, SellOn)
            end
        end

        Header("Broker menu appearance", "How the menus of your data bar launchers look. One background and border for all of them. Only the look changes; what the menus do doesn't.")
        K.Appearance(R.MenuStyle, "brokerMenu", "menu",
            "A sample menu beside this window that shows these settings as you change them. It does nothing when clicked. Esc closes it.",
            function() R.SpellMenu.TogglePreview() end,
            "Menu appearance", "Puts the background and border of the menus back to their defaults. Nothing else is changed.")

        local RP = R.RefreshmentsPanel
        if RP and RP.Style and refreshToggle then
            Header("Refreshments panel appearance", "How the refreshments panel and its strip under the trade window look. Only the look changes; what they do doesn't.")
            K.Appearance(RP.Style, "refreshmentsPanel", "panel",
                "Opens the refreshments panel beside this window, to see these settings as you change them. It is the real panel; Esc or its close box shuts it.",
                function() RP.TogglePreview() end,
                "Panel appearance", "Puts the background and border of the refreshments panel and its trade strip back to their defaults. Nothing else is changed.",
                refreshToggle, function() return R:Enabled("mageRefreshments") end)
        end
    end,
})

-- Refreshment shares: how many water and food each class gets (modules/RefreshmentsShares.lua). A table of
-- numbers, so the feature draws it itself; the window shows it as a page.
K.Page({
    key = "refreshmentShares", name = "Refreshment shares", parent = "mage", order = 51,
    description = "How many conjured water and food each class gets in a party and in a raid, and how many you keep.",
    keywords = "water food amount stacks party raid class share keep",
    when = function() return R.RefreshmentShares ~= nil and R.RefreshmentShares.Frame ~= nil end,
    host = function() return R.RefreshmentShares.Frame() end,
})
