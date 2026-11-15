-- TwichUI settings: Loot Rolls › Loot cards (loot/). A card for each group-loot roll, in place of the game's roll window, and how the cards
-- look and where they sit. The rows call loot/Config.lua's Get/Set; the switch is Switches.lua's. Rules, and automatic rolling, are on the
-- Loot rules tab (LootRules.lua). The preview beside the window is Companion.lua's (the real card renderer over a made-up item).
-- Nothing here rolls, and nothing here is needed for loot cards to work.

local R = TwichUI
local K = R.SettingsKit
local DOT = "  \194\183  "

local function LR() return R.LootRolls end
local function On() return R:Enabled("lootRolls") end

-- Placement: the sample card on its own frame, dragged, kept only on Finish. The settings window steps aside meanwhile.
local bar, restore, placing
local function PlacementClosed(saved)
    local back = restore
    placing, restore = nil, nil
    if bar then bar:Hide() end
    if R.SettingsUI.SuspendForPlacement then R.SettingsUI.SuspendForPlacement(false, back) end
end

local function StartPlacement()
    local G, M = R.SettingsWidgets, R.SettingsMaterial
    if placing then return end
    local ok, why = R.LootCards.PlaceStart(PlacementClosed)
    if not ok then R.Print("%s", "Loot cards: " .. (why or "can't place them now.")) return end
    if not bar then
        bar = CreateFrame("Frame", "TwichUILootPlacement", UIParent)
        bar:SetSize(500, 78)
        bar:SetPoint("TOP", UIParent, "TOP", 0, -36)
        bar:SetFrameStrata("FULLSCREEN_DIALOG")
        bar:SetClampedToScreen(true)
        bar:EnableMouse(true)
        M.Companion(bar)
        bar.title = G.Text(bar, "body"); bar.title:SetPoint("TOPLEFT", 16, -12); bar.title:SetText("Place the loot cards")
        bar.note = G.Text(bar, "small"); bar.note:SetPoint("BOTTOMLEFT", 16, 18); bar.note:SetWidth(250)
        bar.note:SetText("Drag the sample card. Cancel keeps where they were.")
        bar.cancel = G.Button(bar, "Cancel", 86, "secondary", function() R.LootCards.PlaceFinish(false) end)
        bar.cancel:SetPoint("BOTTOMRIGHT", -112, 12)
        bar.finish = G.Button(bar, "Finish", 86, "primary", function() R.LootCards.PlaceFinish(true) end)
        bar.finish:SetPoint("BOTTOMRIGHT", -16, 12)
        bar:SetScript("OnHide", function() if placing and R.LootCards.Placing() then R.LootCards.PlaceFinish(false) end end)
    end
    placing, restore = true, true
    R.SettingsUI.SuspendForPlacement(true)
    bar:Show()
end

function R.LootCardsPageStatus()
    local lr = LR()
    if not On() then return "Off" end
    local snap = lr.Snapshot()
    if snap.failed then return "Using the game's window" end
    if snap.cards == 0 then return "Waiting for a roll" end
    return snap.cards == 1 and "1 card showing" or (snap.cards .. " cards showing")
end

K.Page({
    key = "lootRolls", icon = "lootRolls", name = "Loot Rolls", tab = "Loot cards", order = 26, group = "everyday",
    description = "Loot cards and simple automatic rolling rules.",
    keywords = "loot roll rolls need greed pass group loot card cards window item upgrade vendor timer countdown automatic auto rule rules place position scale",
    overview = {
        label = "Loot Rolls", tip = "A card for each group-loot roll, and optional rules that choose Need, Greed or Pass after a countdown you can stop.",
        when = function() return R.LootRolls ~= nil end,
        status = function()
            if not R:Enabled("lootRolls") then return K.OnOff(false) end
            return K.OnOff(true, R.LootRolls.AutoOn() and "Cards and rules on" or "Cards on")
        end,
    },
    when = function() return R.LootRolls ~= nil and R.LootCards ~= nil end,
    build = function()
        local lr = LR()
        local Under = K.Under
        local BOOL, STRING, NUMBER = K.BOOL, K.STRING, K.NUMBER
        local resettable = {}
        local main
        local function Setting(key, varType, label, set)
            local name = "lootRolls" .. key:sub(1, 1):upper() .. key:sub(2)
            local s = K.Proxy(name, varType, label, lr.DEFAULTS[key], function() return lr.Get(key) end, set or function(v) lr.Set(key, v) end)
            if s and key ~= "x" and key ~= "y" then resettable[#resettable + 1] = { setting = s, default = lr.DEFAULTS[key] } end
            return s
        end
        local function Check(key, label, tip)
            return Under(K.Checkbox(Setting(key, BOOL, label, function(v) lr.Set(key, v and true or false) end), tip), main, On)
        end
        local function Pick(key, label, tip)
            return Under(K.Dropdown(Setting(key, STRING, label), function() return lr.CHOICES[key] end, tip), main, On)
        end
        local function Range(key, label, tip)
            local lim = lr.LIMITS[key]
            return Under(K.Slider(Setting(key, NUMBER, label, function(v) lr.Set(key, math.floor(v + 0.5)) end), lim[1], lim[2], tip), main, On)
        end

        K.Card({
            title = "Loot cards", icon = "lootRolls",
            what = "A card for each group-loot roll: the item, its quality, a countdown and Need, Greed and Pass, in place of the game's roll window. When the game gives them, the other players' rolls and the winner are shown too.",
            summary = function() return R.LootCardsPageStatus() end,
            consequence = "A roll's own game window steps aside only while a card is showing that roll, and comes back at once if the card is closed or anything goes wrong, so you can always roll. Choosing is always your click; automatic rolling is a separate, later choice on the Loot rules tab.",
            details = {
                { "Does it change who gets the item?", "No. It sends exactly what the game's own buttons send, and only when you click (or a rule you turned on counts down on the card and you let it finish)." },
                { "What is the upgrade mark?", "The \"Potential upgrade\" label comes from TwichUI's gear comparison (Gear upgrades). It is a hint, never a recommendation to roll Need, and it is left out when the game hasn't said enough to judge." },
                { "Why might some details be missing?", "Other players' rolls and the winner come from the game's loot history, which this client may or may not provide. Only what it gives is shown; nothing is filled in." },
            },
        })
        main = K.Toggle("lootRolls", "Show loot cards",
            "On: a TwichUI card appears for each group-loot roll and the game's roll window steps aside for it. Off: the game's own window is used and nothing is listened for. Your rules and settings are kept either way.")
        K.Status("Right now", function() return R.LootCardsPageStatus() end, function()
            if not On() then return "Off: the game's own roll window is used." end
            local snap = lr.Snapshot()
            if snap.failed then return "The cards stopped after an error, so the game's own window is shown. Turn this off and on to start again." end
            return "Read when this page is drawn."
        end, "Whether the cards are listening, and how many are showing now.", function()
            if not On() then return "quiet" end
            return lr.Snapshot().failed and "warn" or "ok"
        end)

        -- Appearance and place
        K.Card({
            title = "Size and place", icon = "appearance", switch = false,
            what = "How big the cards are, how they stack, and where the stack sits.",
            summary = function()
                return table.concat({ ("%d%%"):format(lr.Get("scale")), ("up to %d cards"):format(lr.Get("maxCards")), lr.Get("growth") == "up" and "grows upwards" or "grows downwards" }, DOT)
            end,
            consequence = "Placing keeps the place only when you press Finish. Rolls beyond the number of cards you allow keep the game's own window.",
        })
        Range("scale", "Card size (%)", "Makes the cards bigger or smaller.")
        Range("spacing", "Space between cards", "The gap between two cards in the stack.")
        Range("maxCards", "Most cards at once", "How many rolls get a card at the same moment. A roll without a card keeps the game's own window (and no automatic rolling).")
        Pick("growth", "Stack grows", "Downwards: the first roll is at the top. Upwards: the first roll is at the bottom.")
        Under(K.Button("Place the cards", "Place...", StartPlacement,
            "Shows a sample card you drag where you want the stack. The settings window steps aside; Finish keeps the place, Cancel leaves it as it was. Not available in combat or while a roll is open."), main, On)
        Under(K.Button("Position", "Reset", function() lr.ResetPlace() end, "Puts the cards back at their default place. Only their place changes."), main, On)

        -- What a card shows
        K.Card({
            title = "What a card shows", icon = "notifications", switch = false,
            what = "Which details a card shows, how the countdown is drawn and how long a finished card stays.",
            summary = function()
                local parts = { lr.Get("showUpgrade") and "upgrade mark" or "no upgrade mark", lr.Get("showResults") and "results" or "no results" }
                return table.concat(parts, DOT)
            end,
            consequence = "A countdown for an automatic roll is always shown in full, whatever the timer setting says.",
        })
        Check("showUpgrade", "Show the potential upgrade mark", "A small \"Potential upgrade\" label when TwichUI's gear comparison thinks the item may improve what you wear. A hint only: it never chooses anything. Left out when the game hasn't said enough to judge.")
        Check("showValue", "Show the vendor price", "The item's vendor price under its name, when the game gives it.")
        Check("showResults", "Show other players' rolls", "After the roll, who rolled what and who won, when the game's loot history gives it. Only what it gives is shown.")
        Pick("timer", "Timer", "How a roll's countdown is drawn.")
        Range("afterResult", "Keep a finished card for (seconds)", "How long a card stays after its roll ends, with the result if there is one.")
        Check("animate", "Animate cards", "A brief fade and slide as a card appears. Off: cards appear at once.")

        K.ResetButton("Loot card settings", resettable, function() lr.ResetSettings() end,
            "Puts the settings on this page back to their defaults. The switch, the place, your rules and the automatic rolling choices are kept.")
    end,
})
