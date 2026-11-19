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

local function Preview()
    local ok, why = R.LootCards.PreviewStart()
    if not ok then R.Print("%s", "Loot cards: " .. (why or "can't preview now.")) end
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
        local function Swatch(key, label, tip, cond)
            return Under(K.Swatch(Setting(key, STRING, label), tip), main, cond or On)
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
        K.Button("Preview a sample roll", "Preview", Preview,
            "Shows a made-up roll on a real card, in your place and at your size. Need, Greed and Pass work, it counts down and ends with made-up results, and nothing is rolled. Works even while loot cards are off. A real roll takes its place.")
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
        Check("animate", "Fade cards in and out", "A card fades in when a roll starts and fades out when it ends or is closed. Off: cards appear and go at once, whatever the times below say.")
        local function Fades() return On() and lr.Get("animate") end
        local fadeIn = Under(K.Slider(Setting("fadeIn", NUMBER, "Fade in (milliseconds)", function(v) lr.Set("fadeIn", math.floor(v / 50 + 0.5) * 50) end), 0, 1000,
            "How long a card takes to fade in. 0 shows it at once."), main, Fades)
        local fadeOut = Under(K.Slider(Setting("fadeOut", NUMBER, "Fade out (milliseconds)", function(v) lr.Set("fadeOut", math.floor(v / 50 + 0.5) * 50) end), 0, 2000,
            "How long a card takes to fade out. 0 takes it away at once."), main, Fades)
        if fadeIn and fadeIn.options then fadeIn.options.step = 50 end
        if fadeOut and fadeOut.options then fadeOut.options.step = 50 end

        -- The countdown bar
        K.Card({
            title = "Countdown bar", icon = "lootDelay", switch = false,
            what = "How the bar that empties while a roll is open is drawn: its texture, height and colors.",
            summary = function()
                local id, label = lr.Get("barTexture"), nil
                for _, choice in ipairs(R.MenuStyle.StatusBars.Choices(id)) do if choice[1] == id then label = choice[2] end end
                label = label or id
                return table.concat({ label, ("%d high"):format(lr.Get("barHeight")), lr.Get("barShift") and "changes color as time runs out" or "one color" }, DOT)
            end,
            consequence = "Only how the bar looks changes: what it counts, and when a roll ends, does not. A rule's countdown always shows its bar and its seconds, and keeps its own color so it can't be mistaken for the roll's time.",
            details = {
                { "Where do the textures come from?", "Flat color, EllesmereUI's bar textures while it is installed, and every LibSharedMedia status bar texture, the same list as the other TwichUI bars. A texture that has gone is drawn flat and stays chosen." },
            },
        })
        Under(K.Dropdown(Setting("barTexture", STRING, "Bar texture"),
            function() return R.MenuStyle.StatusBars.Choices(lr.Get("barTexture")) end,
            "The picture the bar is filled with, tinted by the colors below. Sheer is EllesmereUI's; without EllesmereUI the bar is drawn flat until you choose another. Flat color is a plain fill."), main, On)
        Range("barHeight", "Bar height", "How tall the countdown bar is.")
        Check("barShine", "Highlight along the top of the bar", "A thin light line along the top of the fill. Off draws none.")
        Check("barShift", "Change color as time runs out", "On: the bar uses the plenty-of-time color, then the half-gone color, then the nearly-out color. Off: it keeps the first color to the end.")
        local function Shifts() return On() and lr.Get("barShift") end
        Swatch("barColorHigh", "Bar color", "The bar's color while plenty of time is left (the whole bar's color when it doesn't change).")
        Swatch("barColorMid", "Half-gone color", "The bar's color when about half the time is gone.", Shifts)
        Swatch("barColorLow", "Nearly-out color", "The bar's color when the roll is nearly out of time.", Shifts)
        Swatch("barColorExpired", "Ran-out color", "The full bar on a card whose roll ran out before you chose.")
        Swatch("barColorRule", "Rule countdown color", "The bar's color while a rule counts down to roll for you.")
        Swatch("barTrack", "Track color", "The empty part of the bar, behind the fill.")

        K.ResetButton("Loot card settings", resettable, function() lr.ResetSettings() end,
            "Puts the settings on this page back to their defaults. The switch, the place, your rules and the automatic rolling choices are kept.")
    end,
})
