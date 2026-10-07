-- TwichUI: options in Esc > Options > AddOns > TwichUI (/twichui)
-- The one home for TwichUI's settings, built from Blizzard's own controls.
-- A short overview page links to one page per feature (subcategories of
-- TwichUI). Rarely changed options sit under an "Advanced" header that only
-- shows with "Show advanced options" (on the overview) on; they keep their
-- values (and keep working) while hidden. Stat weights are a page under Gear
-- comparison (gear/Window.lua), since a ranked list and a table of numbers
-- don't fit the standard controls.

local R = TwichUI

local function AskReload()
    StaticPopupDialogs.TWICHUI_RELOAD = {
        text = "TwichUI: this change takes effect after reloading your UI. Reload now?",
        button1 = RELOADUI or "Reload", button2 = "Later",
        OnAccept = ReloadUI,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("TWICHUI_RELOAD")
end

-- Addons TwichUI can skin. addon = folder name.
local SKINS = {
    { key = "attuneSkin", addon = "Attune", label = "Attune",
      what = "Gives the Attune window (/attune) and its quest panels the EllesmereUI look." },
    { key = "auctionatorSkin", addon = "Auctionator", label = "Auctionator",
      what = "Gives Auctionator's tabs, buttons, lists and boxes the EllesmereUI look. Also needs EllesmereUI's Auction House window skin." },
    { key = "foreverDungeonJournalSkin", addon = "ForeverDungeonJournal", label = "Dungeon Journal",
      what = "Gives the Forever Dungeon Journal window (/fj) the EllesmereUI look." },
    { key = "whatsTrainingSkin", addon = "WhatsTraining", label = "WhatsTraining",
      what = "Gives WhatsTraining's floating window (/wt) the EllesmereUI look." },
}

local function AddonState(addon)
    return R.Setups and R.Setups.AddonState(addon) or "ready"
end

local function Loaded(addon)
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon) or false
end

-- What a skin is doing right now: a word or two, and a sentence (or nil).
-- onAtLoad: whether the skin's toggle was on when the UI loaded.
local function SkinStatus(skin, onAtLoad)
    local state = AddonState(skin.addon)
    if state == "missing" then return R.GREY .. "Not installed|r", "Install " .. skin.label .. " to use this skin." end
    if state == "disabled" then return R.GREY .. "Turned off|r", skin.label .. " is turned off in your AddOns list." end
    local on = R:Enabled(skin.key)
    if on ~= onAtLoad then
        return R.GOLD .. (on and "On" or "Off") .. " after reload|r", "Reload your UI for this to take effect."
    end
    if not on then return R.GREY .. "Off|r", nil end
    if AddonState("EllesmereUI") == "missing" then
        return R.GREY .. "Waiting for EllesmereUI|r", "EllesmereUI isn't installed. The skin only works with it."
    end
    if not R.S then
        return R.GREY .. "Waiting for EllesmereUI|r", "EllesmereUI hasn't switched on TwichUI's skins. Check its third-party addon skin options."
    end
    if not Loaded(skin.addon) then
        return R.GREEN .. "Ready|r", "Applies when " .. skin.label .. " loads."
    end
    return R.GREEN .. "Active|r", nil
end

local function Build()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterVerticalLayoutSubcategory) then return end
    local root, rootLayout = Settings.RegisterVerticalLayoutCategory("TwichUI")
    R.settingsCategory = root
    R.settingsCategories = { overview = root }   -- R:OpenSettings(key)

    -- Pages are made up front so the category list keeps this order. The
    -- helpers below add to whichever page Use() last selected; the page is
    -- built in one go, so nothing is added after the next Use().
    local pages = { overview = { category = root, layout = rootLayout } }
    local function NewPage(key, name)
        local category, layout = Settings.RegisterVerticalLayoutSubcategory(root, name)
        pages[key] = { category = category, layout = layout }
        R.settingsCategories[key] = category
    end
    NewPage("gear", "Gear comparison")
    NewPage("notifications", "Notifications")
    NewPage("food", "Food and drink")
    if R.ComboPoints and R.ComboPoints.ForPlayer() then NewPage("combo", "Combo points") end   -- Rogues only
    if R.MageTravel and R.MageTravel.ForPlayer() then NewPage("mage", "Mage") end   -- Mages only
    NewPage("chronicle", "Journey Chronicle")
    NewPage("auction", "Auction House")
    NewPage("skins", "Addon skins")
    NewPage("sharing", "Configuration sharing")

    local category, layout
    local function Use(key) category, layout = pages[key].category, pages[key].layout end
    Use("overview")

    local VarType = Settings.VarType or {}
    local BOOL = VarType.Boolean or "boolean"
    local STRING = VarType.String or "string"
    local NUMBER = VarType.Number or "number"

    TwichUIDB.ui = TwichUIDB.ui or {}
    if TwichUIDB.ui.showAdvanced == nil then TwichUIDB.ui.showAdvanced = false end
    local function AdvancedShown() return TwichUIDB.ui.showAdvanced == true end

    -- Hidden until "Show advanced options" is on. The setting keeps its value.
    local function Advanced(initializer)
        if initializer and initializer.AddShownPredicate then initializer:AddShownPredicate(AdvancedShown) end
        return initializer
    end

    -- Greyed out while the parent checkbox is off.
    local function Under(initializer, parent, isOn)
        if initializer and parent and initializer.SetParentInitializer then
            initializer:SetParentInitializer(parent, isOn)
        end
        return initializer
    end

    -- The overview's feature rows: a name, a short status, and a button to that
    -- page. The status is rewritten whenever a toggle changes (no polling).
    local overviewRows = {}
    local function RefreshOverview()
        for _, row in ipairs(overviewRows) do
            if row.initializer.data then
                row.initializer.data.name = row.label .. "   " .. row.status()
            end
        end
    end

    local function Header(text, tooltip)
        if CreateSettingsListSectionHeaderInitializer then
            local initializer = CreateSettingsListSectionHeaderInitializer(text, tooltip)
            layout:AddInitializer(initializer)
            return initializer
        end
    end

    local function Toggle(key, label, tooltip, needsReload, onChange)
        local setting = Settings.RegisterAddOnSetting(category, "TWICHUI_" .. key, key, TwichUIDB.modules, BOOL, label, R.DEFAULT_MODULES[key])
        local initializer = Settings.CreateCheckbox(category, setting, tooltip)
        if setting.SetValueChangedCallback then
            setting:SetValueChangedCallback(function()
                if needsReload then AskReload() end
                if onChange then onChange() end
                RefreshOverview()
                if R.Window then R.Window:Refresh() end
            end)
        end
        return initializer, setting
    end

    local function Button(label, buttonText, onClick, tooltip)
        if CreateSettingsButtonInitializer then
            local initializer = CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true)
            layout:AddInitializer(initializer)
            return initializer
        end
    end

    -- A setting stored somewhere other than the modules table.
    local function Proxy(variable, varType, label, default, get, set)
        if not Settings.RegisterProxySetting then return end
        return Settings.RegisterProxySetting(category, "TWICHUI_" .. variable, varType, label, default, get, set)
    end

    local function ProxyToggle(variable, label, tooltip, default, get, set)
        local setting = Proxy(variable, BOOL, label, default, get, set)
        return setting and Settings.CreateCheckbox(category, setting, tooltip)
    end

    -- options: { { value, label, tooltip }, ... } or a function returning that.
    local function Choice(variable, label, tooltip, varType, default, get, set, options)
        local setting = Proxy(variable, varType, label, default, get, set)
        if not (setting and Settings.CreateDropdown and Settings.CreateControlTextContainer) then return end
        return Settings.CreateDropdown(category, setting, function()
            local container = Settings.CreateControlTextContainer()
            for _, option in ipairs(type(options) == "function" and options() or options) do
                container:Add(option[1], option[2], option[3])
            end
            return container:GetData()
        end, tooltip)
    end

    -----------------------------------------------------------------------
    -- Feature pages first; the overview is filled in at the end, once each
    -- page's status is known.
    Use("gear")
    Header("Upgrade hints", "Quiet upgrade hints for your class and main talent tree. A rough estimate from item stats, not a simulation.")
    Toggle("gearHints", "Upgrade hints in item tooltips",
        "Adds a short line to an item's tooltip when it looks like an upgrade for your class and main talent tree, such as \"Likely upgrade for Fury\". Hold Shift (your compare-items key) to see why.\n\n\"Use:\" and \"Chance on hit:\" effects aren't weighed.",
        false)
    local bags = Toggle("gearBagIcons", "Mark upgrades in my bags",
        "A small mark in the corner of bag slots holding gear the tooltip would call an upgrade, fainter for possible upgrades. Works with Blizzard's bags and EllesmereUI Bags.",
        false, function() if R.GearBags then R.GearBags.Refresh() end end)

    local P, D, B = R.GearPrefs, R.GearData, R.GearBags
    if P and D then
        Choice("gearTree", "Weigh gear for",
            "The talent tree this character's gear is weighed for. Automatic follows the tree you've put the most points into, or your class's usual levelling tree before then.",
            NUMBER, 0,
            function() return P.TreeChoice() or 0 end,
            function(value) P.SetTreeChoice(value ~= 0 and value or nil) end,
            function()
                local trees, _, auto = D.Trees()
                local list = { { 0, auto and ("Automatic (" .. auto.name .. ")") or "Automatic" } }
                for _, tree in ipairs(trees or {}) do list[#list + 1] = { tree.skillLine, tree.name } end
                return list
            end)
    end
    if R.GearWindow then
        Button("Stat weights", "Edit", function() R.GearWindow:Show() end,
            "How each of your talent trees values stats: a stat priority you rank, as guides list them, or stat weights you can change.")
    end
    if P then
        Advanced(Header("Advanced"))
        Advanced(ProxyToggle("gearPossible", "Show possible upgrades too",
            "Also mark gear that looks a little better, or better apart from effects the estimate can't weigh. Off: only likely upgrades and empty slots.",
            true, function() return P.Get("glancePossible") and true or false end, function(value) P.Set("glancePossible", value) end))
        Advanced(ProxyToggle("gearFuture", "Hint at gear for higher levels",
            "Gear you can't wear yet only because of its level gets a hint with that level, such as \"Likely upgrade at level 32\". Handy at the auction house.",
            true, function() return P.Get("futureLevels") and true or false end, function(value) P.Set("futureLevels", value) end))

        local function Gain(key)
            local numbers = P.STRICTNESS[key]
            return ("Likely from %d%% better than what you wear, possible from %d%%."):format(
                math.floor(numbers.likely * 100 + 0.5), math.floor(numbers.possible * 100 + 0.5))
        end
        Advanced(Choice("gearStrictness", "How big a gain counts",
            "How much better than what you wear an item must look before it gets a hint.",
            STRING, "balanced",
            function() return P.Get("strictness") end, function(value) P.Set("strictness", value) end,
            {
                { "cautious", "Cautious", Gain("cautious") },
                { "balanced", "Balanced", Gain("balanced") },
                { "eager", "Eager", Gain("eager") },
            }))
        Advanced(Choice("gearReveal", "Show the reasoning",
            "What to hold over an item to see why it got its hint: what it's compared with, the stat changes that mattered most and the weights used.",
            STRING, "compare",
            function() return P.Get("reveal") end, function(value) P.Set("reveal", value) end,
            {
                { "compare", "Hold Shift", "Your compare-items key." },
                { "alt", "Hold Alt" },
                { "ctrl", "Hold Ctrl" },
                { "always", "Always", "The reasoning shows under every item you could wear." },
            }))
        if B then
            local stylePreview
            local styles = {}
            for i, style in ipairs(B.STYLES) do styles[i] = { style.key, style.label } end
            local styleRow = Choice("gearBagStyle", "Bag mark style",
                "The mark on upgrades in your bags. All use the game's own art. The square beside the list shows how it looks on a bag slot.",
                STRING, "gilded",
                function() return P.Get("bagStyle") end,
                function(value)
                    P.Set("bagStyle", value)
                    if stylePreview then B.ApplyStyle(stylePreview.mark, value) end
                end,
                styles)
            -- A preview slot beside the dropdown. Setting rows are recycled, so
            -- the slot is made once per row frame and tracked only while shown.
            if styleRow and styleRow.InitFrame then
                local initFrame, resetter = styleRow.InitFrame, styleRow.Resetter
                styleRow.InitFrame = function(self, frame)
                    initFrame(self, frame)
                    local slot = frame.TwichUIStylePreview
                    if not slot then
                        slot = CreateFrame("Frame", nil, frame)
                        slot:SetSize(26, 26)
                        slot.back = slot:CreateTexture(nil, "BACKGROUND")
                        slot.back:SetAllPoints()
                        slot.back:SetColorTexture(0.05, 0.05, 0.05, 0.9)
                        slot.mark = slot:CreateTexture(nil, "OVERLAY")
                        slot.mark:SetPoint("TOPLEFT", 1, -1)
                        frame.TwichUIStylePreview = slot
                    end
                    slot:ClearAllPoints()
                    slot:SetPoint("RIGHT", frame, "CENTER", -90, 0)
                    slot:SetFrameLevel(frame:GetFrameLevel() + 5)
                    B.ApplyStyle(slot.mark, P.Get("bagStyle"))
                    slot:Show()
                    stylePreview = slot
                end
                styleRow.Resetter = function(self, frame)
                    if resetter then resetter(self, frame) end
                    if frame.TwichUIStylePreview then frame.TwichUIStylePreview:Hide() end
                    if stylePreview == frame.TwichUIStylePreview then stylePreview = nil end
                end
            end
            Under(Advanced(styleRow), bags, function() return R:Enabled("gearBagIcons") end)
        end
    end

    if R.GearWindow and R.GearWindow.Register then R.GearWindow:Register(pages.gear.category) end

    -----------------------------------------------------------------------
    Use("skins")
    Header("EllesmereUI look", "Gives these addons the EllesmereUI look. Needs EllesmereUI with its third-party addon skins on. TwichUI only skins the addons listed here.")
    -- Each skin's tooltip ends with its status, kept current by the events
    -- that can change it (no polling).
    local skinRows = {}
    local function RefreshSkinStatus()
        for _, row in ipairs(skinRows) do
            local status, detail = SkinStatus(row.skin, row.onAtLoad)
            if row.initializer.data then
                row.initializer.data.tooltip = row.skin.what .. "\n\nStatus: " .. status .. (detail and ("\n" .. detail) or "")
            end
        end
        RefreshOverview()
    end
    for _, skin in ipairs(SKINS) do
        local installed = AddonState(skin.addon) ~= "missing"
        local label = installed and skin.label or (skin.label .. "  " .. R.GREY .. "(not installed)|r")
        local initializer = Toggle(skin.key, label, skin.what, true, RefreshSkinStatus)
        if initializer then
            skinRows[#skinRows + 1] = { skin = skin, initializer = initializer, onAtLoad = R:Enabled(skin.key) }
            if not installed and initializer.AddModifyPredicate then
                initializer:AddModifyPredicate(function() return false end)
            end
        end
    end
    RefreshSkinStatus()
    R:OnSkin(RefreshSkinStatus)
    R:On("PLAYER_LOGIN", RefreshSkinStatus)
    R:On("ADDON_LOADED", function(name)
        for _, skin in ipairs(SKINS) do
            if name == skin.addon then RefreshSkinStatus() return end
        end
    end)

    -----------------------------------------------------------------------
    Use("notifications")
    Header("Notifications", "Small, quiet cards near the edges of the screen for moments worth a glance. None of them makes you do anything, and each can be turned off on its own.")
    Toggle("arrivalReducedMotion", "Reduced motion",
        "The notification cards only fade in and out, without moving. Applies to the zone, training and friend cards.")

    Header("Zone arrival", "A short, quiet title card when you arrive somewhere new, in place of the game's own zone text.")
    local function RefreshArrival() if R.Arrival then R.Arrival.Refresh() end end
    local arrival = Toggle("arrival", "Show a title card when I arrive in a new zone",
        "The zone's name appears near the top of the screen under a thin bronze rule, with the smaller place you're in beneath it, then fades away. It replaces the game's own zone text while on. Not shown when you log in or reload, or while on a flight path: only where you land.\n\nIf another addon also replaces the zone text, you may see both.",
        false, RefreshArrival)
    local function ArrivalOn() return R:Enabled("arrival") end
    Under(Toggle("arrivalSubzones", "Also for smaller places",
        "A quieter card when you walk into a smaller place within the zone, such as a town. Off: moving within a zone shows nothing.",
        false, RefreshArrival), arrival, ArrivalOn)
    Under(Toggle("arrivalDungeons", "Show dungeon and raid arrival cards",
        "Walking into a dungeon or raid shows its name with \"Dungeon\" or \"Raid\" beneath it. Off: you get the ordinary zone card there, as before. Not shown when you log in or reload inside one.",
        false, RefreshArrival), arrival, ArrivalOn)

    Header("New training", "A short card when you level up and there is class training you haven't taken yet.")
    Toggle("trainingNotice", "Show new training when I level up",
        "When you level up and there are class spells or ranks you could train and don't know yet, including ones from earlier levels you haven't trained, a short title card near the top of the screen, below the zone's name, lists them (only the highest rank of each spell), in the zone card's style with no frame. Move it in Edit Mode. They are available to train at your class trainer; nothing is learned for you. Nothing shows when there is nothing to train. It waits until you're out of combat, fades by itself, and makes no sound or chat line. Reduced motion (above) applies.\n\nType /tui training to see the card for your current level. Spell data comes from What's Training?.",
        false, function() if R.Training then R.Training.Refresh() end end)

    Header("Friend login", "A short card when a Battle.net friend comes online, in place of the game's own pop-up.")
    local friendLogin = Toggle("friendLogin", "Show Battle.net friend logins as a TwichUI card",
        "When a Battle.net friend comes online, a short card with their name, a Horde or Alliance mark if the game says which faction they play, and the character they are on, in the zone card's style with no frame. It replaces the game's own friend-online pop-up while on; the pop-ups for friends going offline, broadcasts, friend requests and invitations, and the line in chat, are unchanged. Turn it off to get the game's pop-up back. The game's own Social options still apply: with Show Toast Window or Online Friends off, nothing shows. Nothing shows at login or reload, or in combat; several friends arriving together give one card. Move it in Edit Mode. It plays a soft chime, which you can change below. Reduced motion (above) applies.\n\nType /tui friend to see the card.",
        false, function() if R.FriendLogin then R.FriendLogin.Refresh() end end)
    local function FriendLoginOn() return R:Enabled("friendLogin") end
    Under(Toggle("friendLoginSound", "Play a soft chime with it",
        "A short chime (TwichUI Notification) when the card appears. Off: the card is silent."), friendLogin, FriendLoginOn)
    local FriendLogin = R.FriendLogin
    if FriendLogin then
        local channels = {}
        for i, channel in ipairs(FriendLogin.CHANNELS) do channels[i] = { channel.key, channel.label, channel.tooltip } end
        Under(Choice("friendLoginChannel", "Chime volume follows",
            "A sound file can't have a volume of its own, so the chime is as loud as the game volume you choose here. Set that volume in the game's Audio options: lower it to make the chime quieter, or pick the one you keep lowest.",
            STRING, FriendLogin.CHANNEL_DEFAULT,
            function() return (FriendLogin.SoundChannel()) end,
            function(value) TwichUIDB.ui.friendLoginChannel = value end,
            channels), friendLogin, FriendLoginOn)
        Under(Button("Hear the chime", "Play", function() FriendLogin.PlaySound() end,
            "Plays the chime now, at the volume you have chosen."), friendLogin, FriendLoginOn)
    end

    local Arrival = R.Arrival
    if Arrival then
        local holds = {}
        for i, hold in ipairs(Arrival.HOLDS) do
            holds[i] = { hold.key, hold.label, ("Stays %g seconds before fading away."):format(hold.seconds) }
        end
        Advanced(Header("Advanced"))
        Under(Advanced(Choice("arrivalHold", "How long the zone card stays",
            "How long the zone's name stays before it fades away. Cards for smaller places stay a little shorter.",
            STRING, Arrival.HOLD_DEFAULT,
            function() return (Arrival.HoldChoice()) end,
            function(value) TwichUIDB.ui.arrivalHold = value end,
            holds)), arrival, ArrivalOn)
    end

    -----------------------------------------------------------------------
    Use("food")
    Header("Food and Drink buttons", "Two small buttons you click to eat or drink. TwichUI never uses anything for you.")
    local foodDrink = Toggle("foodDrink", "Show Food and Drink buttons",
        "Adds a Food button and a Drink button. Each holds the food or drink in your bags that restores the most (by the amount the item's own text states) among what you can use, and eats or drinks it only when you click it. It chooses only plain food and drink, judged from the item's own text: buff food, feasts and anything it can't read are never picked. An empty button means there is nothing it can tell is plain food or drink in your bags.\n\nThe choice updates when your bags change; if they change during combat, it updates when combat ends. Move the buttons in Edit Mode. Nothing is saved but where you put them and the look you choose below.",
        false, function() if R.FoodDrink then R.FoodDrink.Refresh() end end)
    local function FoodDrinkOn() return R:Enabled("foodDrink") end
    Under(Toggle("foodDrinkFood", "Show the Food button",
        "Off: only the Drink button is shown.",
        false, function() if R.FoodDrink then R.FoodDrink.Refresh() end end), foodDrink, FoodDrinkOn)
    Under(Toggle("foodDrinkDrink", "Show the Drink button",
        "Off: only the Food button is shown. Classes without mana may not want this one.",
        false, function() if R.FoodDrink then R.FoodDrink.Refresh() end end), foodDrink, FoodDrinkOn)

    local FD = R.FoodDrink
    if FD then
        Header("Appearance", "Make the buttons match the rest of your interface.")
        local resettable = {}   -- { setting, default }, for Reset
        local function Remember(variable, varType, label, key, set)
            local setting = Proxy(variable, varType, label, FD.DEFAULTS[key], function() return FD.Get(key) end, set)
            if setting then resettable[#resettable + 1] = { setting = setting, default = FD.DEFAULTS[key] } end
            return setting
        end
        local function Slider(variable, key, label, tooltip, parent, isOn)
            local limit = FD.LIMITS[key]
            local setting = Remember(variable, NUMBER, label, key, function(value) FD.Set(key, math.floor(value + 0.5)) end)
            if not (setting and Settings.CreateSlider and Settings.CreateSliderOptions) then return end
            local options = Settings.CreateSliderOptions(limit[1], limit[2], 1)
            if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            end
            return Under(Settings.CreateSlider(category, setting, options, tooltip), parent or foodDrink, isOn or FoodDrinkOn)
        end
        Slider("foodDrinkSize", "size", "Button size", "The width and height of each button, in pixels.")
        Slider("foodDrinkSpacing", "spacing", "Space between buttons", "The gap between the two buttons, in pixels.")
        local layoutSetting = Remember("foodDrinkLayout", STRING, "Layout", "layout", function(value) FD.Set("layout", value) end)
        if layoutSetting and Settings.CreateDropdown and Settings.CreateControlTextContainer then
            Under(Settings.CreateDropdown(category, layoutSetting, function()
                local container = Settings.CreateControlTextContainer()
                container:Add("horizontal", "Side by side")
                container:Add("vertical", "Stacked")
                return container:GetData()
            end, "Whether the buttons sit next to each other or one above the other."), foodDrink, FoodDrinkOn)
        end
        local textureSetting = Remember("foodDrinkBorderTexture", STRING, "Border texture", "borderTexture", function(value) FD.Set("borderTexture", value) end)
        if textureSetting and Settings.CreateDropdown and Settings.CreateControlTextContainer then
            Under(Settings.CreateDropdown(category, textureSetting, function()
                local container = Settings.CreateControlTextContainer()
                for _, choice in ipairs(FD.TextureChoices()) do container:Add(choice[1], choice[2]) end
                return container:GetData()
            end, "Solid is a plain line. With EllesmereUI installed, its own border textures (such as Pixels Textured) are listed too, drawn the way its bars draw them. The rest are border textures from LibSharedMedia, so any addon that adds borders to it adds them here. Picking one sets a thickness and color that suit it unless you have set your own; change them below."), foodDrink, FoodDrinkOn)
        end
        Slider("foodDrinkBorderSize", "borderSize", "Border thickness", "The border around each button, in pixels. 0 for none. A texture needs about 8 or more to read well.")
        local classToggle
        local classSetting = Remember("foodDrinkBorderClass", BOOL, "Use my class color for the border", "borderClass",
            function(value) FD.Set("borderClass", value and true or false) end)
        if classSetting then
            classToggle = Under(Settings.CreateCheckbox(category, classSetting,
                "Draws the border in your class color instead of the color below."), foodDrink, FoodDrinkOn)
        end
        local colorSetting = Remember("foodDrinkBorderColor", STRING, "Border color", "borderColor", function(value) FD.Set("borderColor", value) end)
        if colorSetting and Settings.CreateColorSwatch then
            Under(Settings.CreateColorSwatch(category, colorSetting,
                "The color of the border. Greyed out while the class color is used."),
                classToggle or foodDrink, function() return FoodDrinkOn() and not FD.Get("borderClass") end)
        end
        Slider("foodDrinkBorderOpacity", "borderOpacity", "Border opacity", "How solid the border is, in percent. 100 is fully opaque. Applies to the class color too.")
        Slider("foodDrinkZoom", "zoom", "Icon zoom", "How much of the icon's edge is cropped, in percent. More looks tighter inside the border.")
        local countSetting = Remember("foodDrinkShowCount", BOOL, "Show how many I have", "showCount",
            function(value) FD.Set("showCount", value and true or false) end)
        if countSetting then
            Under(Settings.CreateCheckbox(category, countSetting,
                "A small number in the corner of a button when you have more than one."), foodDrink, FoodDrinkOn)
        end
        Slider("foodDrinkButtonOpacity", "buttonOpacity", "Button opacity", "How solid the buttons are, in percent. 100 is fully opaque.")
        local mouseoverSetting = Remember("foodDrinkMouseover", BOOL, "Fade when the mouse is away", "mouseover",
            function(value) FD.Set("mouseover", value and true or false) end)
        if mouseoverSetting then
            local mouseover = Under(Settings.CreateCheckbox(category, mouseoverSetting,
                "The buttons fade to the opacity below until the mouse is over one, then return to the button opacity. Even at 0 a button still takes a click, so move the mouse to where it is."), foodDrink, FoodDrinkOn)
            Slider("foodDrinkIdleOpacity", "idleOpacity", "Opacity when the mouse is away",
                "How solid the buttons are, in percent, while the mouse is not over them.",
                mouseover or foodDrink, function() return FoodDrinkOn() and FD.Get("mouseover") end)
        end
        Button("Appearance", "Reset", function()
            for _, entry in ipairs(resettable) do
                if entry.setting.SetValue then pcall(entry.setting.SetValue, entry.setting, entry.default) end
            end
        end, "Puts size, spacing, layout, border, zoom, opacity and the count back to their defaults. The place is kept.")
    end

    -----------------------------------------------------------------------
    local CP = R.ComboPoints
    if pages.combo then
        Use("combo")
        Header("Combo points", "The combo points on your target, where you want them. It shows only what the game reports and never uses an ability for you.")
        local function RefreshCombo() CP.Refresh() end
        local combo = Toggle("comboPoints", "Show TwichUI combo points",
            "Shows the combo points on your current target as small points, a thin bar or a number. It reads them from the game whenever they change, when you change target, and when combat starts or ends; it never guesses them. Move it in Edit Mode, where it shows with sample points, or type /tui combo to watch it fill.",
            false, RefreshCombo)
        local function ComboOn() return R:Enabled("comboPoints") end

        local resettable = {}   -- { setting, default }, for Reset
        local function Remember(variable, varType, label, key, set)
            local default = CP.DEFAULTS[key]
            if default == nil and CP.COLORS[key] then default = CP.THEMES[1][CP.COLORS[key]] end   -- a colour: the default look's
            local setting = Proxy(variable, varType, label, default, function() return CP.Get(key) end,
                set or function(value) CP.Set(key, value) end)
            if setting then resettable[#resettable + 1] = { setting = setting, default = default } end
            return setting
        end
        -- options: { { value, label, tooltip }, ... } or a function returning that.
        local function Pick(variable, key, label, tooltip, options, parent, isOn)
            local setting = Remember(variable, STRING, label, key)
            if not (setting and Settings.CreateDropdown and Settings.CreateControlTextContainer) then return end
            return Under(Settings.CreateDropdown(category, setting, function()
                local container = Settings.CreateControlTextContainer()
                for _, option in ipairs(type(options) == "function" and options() or options) do
                    container:Add(option[1], option[2], option[3])
                end
                return container:GetData()
            end, tooltip), parent or combo, isOn or ComboOn)
        end
        local function Slider(variable, key, label, tooltip, parent, isOn)
            local limit = CP.LIMITS[key]
            local setting = Remember(variable, NUMBER, label, key, function(value) CP.Set(key, math.floor(value + 0.5)) end)
            if not (setting and Settings.CreateSlider and Settings.CreateSliderOptions) then return end
            local options = Settings.CreateSliderOptions(limit[1], limit[2], 1)
            if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            end
            return Under(Settings.CreateSlider(category, setting, options, tooltip), parent or combo, isOn or ComboOn)
        end
        local function Check(variable, key, label, tooltip, parent, isOn)
            local setting = Remember(variable, BOOL, label, key, function(value) CP.Set(key, value and true or false) end)
            return setting and Under(Settings.CreateCheckbox(category, setting, tooltip), parent or combo, isOn or ComboOn)
        end

        local style = Pick("comboStyle", "style", "Style", "How the points are drawn.", {
            { "pips", "Points", "A small marker for each point." },
            { "bar", "Thin bar", "A slim bar, one segment for each point." },
            { "number", "Number", "Just the count, in gold." },
        })
        local function StyleIs(value) return function() return ComboOn() and CP.Get("style") == value end end
        local looks = {}
        for i, theme in ipairs(CP.THEMES) do looks[i] = { theme.key, theme.label, theme.tooltip } end
        Pick("comboTheme", "theme", "Look", "The colors of the points. Use my own colors (Advanced) sets your own.", looks)
        Pick("comboVisibility", "visibility", "Show it",
            "When the display is on screen. It always hides while you're dead.", {
            { "points", "When I have points", "Only while your target carries at least one of your combo points." },
            { "target", "Whenever I have a target", "While you have a living enemy targeted, with empty points when you have none on it." },
            { "combat", "In combat", "Whenever you're in combat, with or without a target. Hidden out of combat." },
            { "always", "Always", "All the time, with or without a target or a fight, empty when you have no points." },
        })

        local others = {}
        if C_AddOns and C_AddOns.IsAddOnLoaded then
            if C_AddOns.IsAddOnLoaded("EllesmereUIUnitFrames") then others[#others + 1] = "Enable Class Resource (EllesmereUI Unit Frames)" end
            if C_AddOns.IsAddOnLoaded("EllesmereUIResourceBars") then others[#others + 1] = "Show Class Resource (EllesmereUI Resource Bars)" end
        end
        local othersText = #others > 0
            and ("\n\nEllesmereUI can show combo points too. If you see them twice, turn off " .. table.concat(others, " or ") .. " in EllesmereUI's options. TwichUI doesn't change EllesmereUI's settings.")
            or ""
        Header("Other combo point displays", "So you don't see your combo points twice." .. othersText)
        Under(Toggle("comboPointsHideGame", "Hide the game's combo points by the target portrait",
            "While TwichUI's combo points are on, the game's own beside the target's portrait are hidden. Turn this off to keep both. Turning TwichUI's off gives the game's back. A change made in combat applies when it ends." .. othersText,
            false, RefreshCombo), combo, ComboOn)

        Header("Size and layout")
        Pick("comboOrientation", "orientation", "Layout", "Whether the points run across or up.", {
            { "horizontal", "Side by side" }, { "vertical", "Stacked" },
        })
        Pick("comboDirection", "direction", "First point", "Which end the first point sits at.", {
            { "forward", "Left (bottom when stacked)" }, { "reverse", "Right (top when stacked)" },
        })
        Pick("comboShape", "shape", "Point shape", "The shape of each point. For the Points style.", {
            { "square", "Square" }, { "round", "Round" },
        }, style, StyleIs("pips"))
        Slider("comboPipSize", "pipSize", "Point size", "The width and height of each point, in pixels. For the Points style.", style, StyleIs("pips"))
        Slider("comboBarLength", "barLength", "Bar length", "The length of the whole bar, in pixels. For the Thin bar style.", style, StyleIs("bar"))
        Slider("comboBarHeight", "barHeight", "Bar thickness", "How thick the bar is, in pixels. For the Thin bar style.", style, StyleIs("bar"))
        Slider("comboNumberSize", "numberSize", "Number size", "The size of the count. For the Number style.", style, StyleIs("number"))
        Slider("comboSpacing", "spacing", "Space between points", "The gap between points, in pixels.", style,
            function() return ComboOn() and CP.Get("style") ~= "number" end)
        Slider("comboScale", "scale", "Scale", "The size of the whole display, in percent.")
        Slider("comboOpacity", "opacity", "Opacity", "How solid the display is, in percent.")

        local function Swatch(variable, key, label, tooltip, parent, isOn)
            local setting = Remember(variable, STRING, label, key)
            if setting and Settings.CreateColorSwatch then
                return Under(Settings.CreateColorSwatch(category, setting, tooltip), parent or combo, isOn or ComboOn)
            end
        end
        Header("Borders")
        local TEXTURE_TIP = "Solid is a plain line. With EllesmereUI installed, its own border textures (such as Pixels Textured) are listed too, drawn the way its bars draw them. The rest are border textures from LibSharedMedia, so any addon that adds borders to it adds them here. Picking one sets a thickness and color that suit it unless you have set your own. The same list as the Food and Drink buttons."
        local pointBorder = Check("comboPointBorder", "pointBorder", "Border on each point",
            "An edge round every point, so each reads on its own against any ground. For the Points and Thin bar styles.")
        local function PointBorderOn() return ComboOn() and CP.Get("pointBorder") end
        Pick("comboPointBorderTexture", "pointBorderTexture", "Point border texture",
            TEXTURE_TIP .. " A texture sits over the point's edge and is square even round round points.",
            function() return CP.TextureChoices("pointBorderTexture") end, pointBorder, PointBorderOn)
        Slider("comboPointBorderSize", "pointBorderSize", "Point border thickness",
            "In pixels. A texture needs about 6 or more to read well; a thick border needs more space between points.", pointBorder, PointBorderOn)
        Swatch("comboBorderColor", "borderColor", "Point border color",
            "The color of each point's border. It starts as the look's.", pointBorder, PointBorderOn)
        local frameBorder = Check("comboFrameBorder", "frameBorder", "Border round the whole display",
            "One border round all the points (or the number) together. Off: only the Leather and bronze look, or a backing of your own, gets its thin bronze edge.")
        local function FrameBorderOn() return ComboOn() and CP.Get("frameBorder") end
        Pick("comboFrameBorderTexture", "frameBorderTexture", "Display border texture", TEXTURE_TIP,
            function() return CP.TextureChoices("frameBorderTexture") end, frameBorder, FrameBorderOn)
        Slider("comboFrameBorderSize", "frameBorderSize", "Display border thickness",
            "In pixels. A texture needs about 8 or more to read well.", frameBorder, FrameBorderOn)
        Swatch("comboFrameBorderColor", "frameBorderColor", "Display border color",
            "The color of the border round the whole display. Bronze by default.", frameBorder, FrameBorderOn)

        Header("Animation")
        local animation = Pick("comboAnimation", "animation", "Animation",
            "Short touches that never get in the way of the count. With Reduced motion on (Notifications), Full is shown as Subtle and there is no mist.", {
            { "full", "Full", "A brief light on each point you gain, spent points fading out, a thin gold rule that brightens once when your points are full, and a short fade when the display hides." },
            { "subtle", "Subtle", "The same, fainter." },
            { "off", "Off", "No animation, and no mist." },
        })
        local function MistOn() return ComboOn() and CP.Get("animation") ~= "off" end
        local mist = Pick("comboMist", "mist", "Poison mist",
            "A soft green mist behind the points, drawn from TwichUI's own art. It drifts, so Reduced motion turns it off.", {
            { "off", "Off", "No mist." },
            { "full", "When my points are full", "A single soft puff that rises and thins away as your points fill up." },
            { "points", "While I have points", "A faint mist that keeps drifting behind the points while you have any on your target." },
        }, animation, MistOn)
        Swatch("comboMistColor", "mistColor", "Mist color", "The color of the mist. A muted poison green by default.",
            mist, function() return MistOn() and CP.Get("mist") ~= "off" end)
        Under(Button("Combo points", "Preview", function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
            local ok, why = CP.Preview()
            if not ok then R.Print(why) end
        end, "Closes the options and fills the points one by one, so you can see the look (same as typing /tui combo)."), combo, ComboOn)
        Button("Appearance", "Reset", function()
            for _, entry in ipairs(resettable) do
                if entry.setting.SetValue then pcall(entry.setting.SetValue, entry.setting, entry.default) end
            end
            CP.ClearColors()
        end, "Puts the style, look, visibility, size, layout, borders, animation, mist, colors and font back to their defaults. The place is kept.")

        Advanced(Header("Advanced"))
        local custom = Check("comboCustomColors", "customColors", "Use my own colors",
            "Use the colors below instead of the look's. They start as the look's own.")
        Advanced(custom)
        local function CustomOn() return ComboOn() and CP.Get("customColors") end
        for _, swatch in ipairs({
            { "comboActiveColor", "activeColor", "Filled point", "A point you have." },
            { "comboInactiveColor", "inactiveColor", "Empty point", "A point you don't have yet." },
            { "comboBackgroundColor", "backgroundColor", "Backing", "A backing behind the points, edged in bronze. Fully clear for none, as most looks have." },
        }) do
            local setting = Remember(swatch[1], STRING, swatch[3], swatch[2])
            if setting and Settings.CreateColorSwatch then
                Under(Advanced(Settings.CreateColorSwatch(category, setting, swatch[4])), custom or combo, CustomOn)
            end
        end
        Advanced(Pick("comboFont", "font", "Number font",
            "The font of the count. Fonts from LibSharedMedia are listed, so other addons' fonts appear too. For the Number style.",
            function() return CP.FontChoices() end, style, StyleIs("number")))
        Advanced(Pick("comboOutline", "outline", "Number outline", "An outline keeps the count readable over bright ground. For the Number style.", {
            { "NONE", "None" }, { "OUTLINE", "Thin" }, { "THICKOUTLINE", "Thick" },
        }, style, StyleIs("number")))
        Advanced(Check("comboShadow", "shadow", "Number shadow", "A soft shadow under the count. For the Number style.", style, StyleIs("number")))
    end

    -----------------------------------------------------------------------
    local MT = R.MageTravel
    if pages.mage then
        Use("mage")
        Header("Mage Travel", "A launcher for your data bar that lists your teleports and portals. It casts only the one you click, and never chooses a destination for you.")
        local mage = Toggle("mageTravel", "Mage Travel launcher on my data bar",
            "Adds \"TwichUI Mage Travel\" to the list of your data bar addon (any that shows LibDataBroker launchers, such as EllesmereUI's Broker Plugin block). Click it for a small menu of the teleports and portals your faction can learn: click a learned one to cast it; hover one you haven't learned for the level it is trained at. It can't be opened in combat, and closes when combat starts.\n\nWithout a data bar addon there is nowhere for it to show. Turning it off takes it off your data bar after a reload.",
            false, function()
                MT.Refresh()
                if not R:Enabled("mageTravel") and MT.Available() then AskReload() end
            end)
        Under(Choice("mageTravelText", "Text on the data bar",
            "The word shown beside the launcher's icon on your data bar. None leaves just the icon. If your data bar shows plugin names too, it may read \"Mage Travel: Travel\"; that is the data bar's own label option.",
            STRING, MT.DEFAULT_TEXT, MT.TextChoice, MT.SetTextChoice, MT.TEXTS),
            mage, function() return R:Enabled("mageTravel") end)

        local MC = R.MageConjure
        Header("Mage Conjuring", "A launcher for your data bar that lists your Conjure Food and Conjure Water ranks. It casts only the one you click.")
        local conjure = Toggle("mageConjure", "Mage Conjuring launcher on my data bar",
            "Adds \"TwichUI Mage Conjuring\" to the list of your data bar addon (any that shows LibDataBroker launchers, such as EllesmereUI's Broker Plugin block). Click it for a small menu of the Conjure Food and Conjure Water ranks, highest first, so you can also conjure a lower rank for a lower-level friend: click a learned one to cast it; hover one you haven't learned for the level it is trained at. Shift-left-click the launcher to conjure water and shift-right-click to conjure food, each at your highest rank. It can't be opened in combat, and closes when combat starts; the shift-clicks don't work in combat either.\n\nWithout a data bar addon there is nowhere for it to show. Turning it off takes it off your data bar after a reload.",
            false, function()
                MC.Refresh()
                if not R:Enabled("mageConjure") and MC.Available() then AskReload() end
            end)
        Under(Choice("mageConjureText", "Text on the data bar",
            "The word shown beside the launcher's icon on your data bar. None leaves just the icon. If your data bar shows plugin names too, it may read \"Mage Conjuring: Conjure\"; that is the data bar's own label option.",
            STRING, MC.DEFAULT_TEXT, MC.TextChoice, MC.SetTextChoice, MC.TEXTS),
            conjure, function() return R:Enabled("mageConjure") end)
    end

    -----------------------------------------------------------------------
    Use("chronicle")
    Header("Automatic entries", "A quiet, private journal for this character. It isn't shared, sent or backed up with your configuration, and it never tells you what to do next.")
    local chronicle = Toggle("chronicle", "Keep moments for me automatically",
        "On by default. TwichUI adds a short entry to this character's Chronicle for the moments you pick below. It starts the moment it is on and never looks back. You can always write your own notes, whatever this is set to.",
        false, function() if R.ChronicleRecorder then R.ChronicleRecorder.Refresh() end end)
    local function ChronicleOn() return R:Enabled("chronicle") end
    local function ChronicleToggle(key, label, tooltip)
        Under(Toggle(key, label, tooltip, false, function() if R.ChronicleRecorder then R.ChronicleRecorder.Refresh() end end),
            chronicle, ChronicleOn)
    end
    ChronicleToggle("chronicleLevels", "Reaching a new level", "Adds an entry when you gain a level.")
    ChronicleToggle("chronicleZones", "Arriving somewhere new", "Adds an entry when you travel into a new zone, including entering a dungeon. Not when you log in.")
    ChronicleToggle("chronicleBosses", "Defeating an encounter", "Adds an entry when a dungeon or raid encounter you fought ends in victory. Only the encounter's name is kept.")
    ChronicleToggle("chronicleDeaths", "Falling in battle", "Adds an entry when your character dies, with the zone you were in. Off until you choose it.")
    ChronicleToggle("chronicleGold", "Gold earned milestones", "Adds an entry when the gold you've gained since tracking began reaches 10, 50, 100, 500, 1,000, 5,000 and 10,000. Spending doesn't lower it, and what you already carry isn't counted.")
    ChronicleToggle("chronicleRiding", "Learning to ride", "Adds an entry when you learn a new Riding rank.")
    ChronicleToggle("chronicleProfessions", "Professions", "Adds an entry when you learn a profession, and when a profession skill first reaches 75, 150, 225, 300, 375 and 450. Professions and skill you already have aren't counted.")
    ChronicleToggle("chronicleChat", "Show Chronicle entries in chat", "Prints a quiet line in your own chat window when an entry is added automatically. Only you see it; it is never sent to anyone. Entries are still recorded when this is off.")
    Toggle("chronicleSound", "Play Chronicle opening sound", "Plays a soft page-turn sound each time you open the Chronicle. It follows your game sound settings and volume.")
    Toggle("welcomeBack", "Show a Welcome Back bookmark",
        "When you log in to a character that has Chronicle entries, a small bookmark shows the last place the Chronicle noted and how long ago, with a link to open it. It fades by itself, doesn't appear after a reload or in combat, and makes no sound or chat line. It only reads your entries; it adds none. Move it in Edit Mode.",
        false, function() if R.WelcomeBack then R.WelcomeBack.Refresh() end end)
    Choice("chronicleClock", "Time format",
        "How times are shown in your Chronicle.",
        STRING, "12",
        function() return TwichUIDB.ui.chronicleClock == "24" and "24" or "12" end,
        function(value)
            TwichUIDB.ui.chronicleClock = value
            if R.ChronicleWindow then R.ChronicleWindow:Refresh() end
        end,
        { { "12", "12-hour (3:45 PM)" }, { "24", "24-hour (15:45)" } })
    Button("Journey Chronicle", "Open", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if R.ChronicleWindow then R.ChronicleWindow:Show() end
    end, "Opens your Chronicle (same as typing /tui chronicle).")

    -----------------------------------------------------------------------
    Use("sharing")
    Header("Addon configurations", "Share the settings of the addons you choose with friends, and apply theirs. You always choose what to apply, and Undo puts your own settings back.")
    local sharing = Toggle("setupSharing", "Configuration sharing",
        "Save the settings of the addons you choose as an addon configuration, send it to friends in game, and apply configurations friends send you. Type /tui share.",
        true)
    local function SharingOn() return R:Enabled("setupSharing") end
    Under(Toggle("acceptSetups", "Let friends send me addon configurations",
        "When on, friends can offer you their addon configuration. You're always asked first, unless you chose \"Always accept\" for that friend. Nothing is applied until you click Apply.",
        false), sharing, SharingOn)
    Toggle("groupCheck", "Version and group check",
        "On by default. Both players need it on to see each other. Other players never see these messages, even without TwichUI.\n\nWhen you're in a group, TwichUI trades version numbers with other TwichUI users (a few bytes, group channel only) and tells you when someone's version is newer or too old to share with. Also powers /tui check and Party compatibility check in /tui share, and a once-per-game-build test message that shows in Sending options whether direct messages reached another TwichUI user.",
        true)
    Button("Configuration sharing", "Open", function()
        if not R:Enabled("setupSharing") then
            R.Print("turn on Configuration sharing first.")
            return
        end
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        R.Window:Show()
    end, "Opens the sharing window: send your setup, review ones friends sent, create backups and run the party compatibility check (same as typing /tui share).")
    Advanced(Header("Advanced"))
    Advanced(Choice("shareTransport", "Send configurations by",
        "How your configuration travels when you press Send. TwichUI uses only the one you pick and never switches by itself if it fails. Receiving works on all three, whatever you pick here.\n\n" .. R.Share.TRANSPORT_EXPLAIN,
        STRING, "DIRECT",
        function() return R.Share.Transport() end,
        function(value) R.Share.SetTransport(value) end,
        function()
            local list = {}
            for _, key in ipairs(R.Share.TRANSPORTS) do
                list[#list + 1] = { key, R.Share.TRANSPORT_LABEL[key], R.Share.TRANSPORT_HELP[key] }
            end
            return list
        end))

    -----------------------------------------------------------------------
    Use("auction")
    Header("Sell from Bags", "A tab in the Auction House for listing items from your bags, one at a time.")
    Toggle("auctionPosting", "Add a Sell from Bags tab to the Auction House",
        "Lists the items in your bags that the auction house will take. Picking one searches its current listings (that item only, never the whole auction house) and suggests a price that matches the lowest comparable listing, with what it's based on. You set the quantity, price and duration; nothing is posted until you press Post. Results aren't saved.",
        false, function() if R.AuctionWindow then R.AuctionWindow.Refresh() end end)

    -----------------------------------------------------------------------
    Use("overview")
    Header("A quiet interface companion for WoW: Forever.",
        "TwichUI makes the game's interface a little clearer and more cohesive, without taking over. Each feature has its own page below, and every one can be turned off.")

    local function OnOff(on, onText, offText)
        if on then return R.GREEN .. (onText or "On") .. "|r" end
        return R.GREY .. (offText or "Off") .. "|r"
    end
    -- key: page to open; status: a word or two for the row.
    local function FeatureRow(key, label, tooltip, status)
        if not CreateSettingsButtonInitializer then return end
        local initializer = CreateSettingsButtonInitializer(label, "Open", function()
            if Settings.OpenToCategory and R.settingsCategories[key] then
                Settings.OpenToCategory(R.settingsCategories[key]:GetID())
            end
        end, tooltip, false)
        layout:AddInitializer(initializer)
        overviewRows[#overviewRows + 1] = { initializer = initializer, label = label, status = status }
    end
    if R.GearPrefs then
        FeatureRow("gear", "Gear comparison", "Quiet upgrade hints in item tooltips and bags, and the stat weights behind them.",
            function() return OnOff(R:Enabled("gearHints") or R:Enabled("gearBagIcons")) end)
    end
    FeatureRow("notifications", "Notifications", "Quiet cards for arriving somewhere new, new training at a level-up, and friends logging in.",
        function()
            local on = (R:Enabled("arrival") and 1 or 0) + (R:Enabled("trainingNotice") and 1 or 0) + (R:Enabled("friendLogin") and 1 or 0)
            return OnOff(on > 0, ("%d of 3 on"):format(on), "Off")
        end)
    FeatureRow("food", "Food and drink", "Two buttons you click to eat or drink the best food or drink in your bags.",
        function() return OnOff(R:Enabled("foodDrink")) end)
    if pages.combo then
        FeatureRow("combo", "Combo points", "Your combo points on the target, where you want them, in your choice of style.",
            function() return OnOff(R:Enabled("comboPoints")) end)
    end
    if pages.mage then
        FeatureRow("mage", "Mage", "Data bar launchers for your teleports and portals, and for conjuring food and water.",
            function()
                local on = (R:Enabled("mageTravel") and 1 or 0) + (R:Enabled("mageConjure") and 1 or 0)
                return OnOff(on > 0, ("%d of 2 on"):format(on), "Off")
            end)
    end
    FeatureRow("chronicle", "Journey Chronicle", "Your private journal for this character.",
        function() return OnOff(R:Enabled("chronicle"), "Recording", "Notes only") end)
    FeatureRow("auction", "Auction House", "A Sell from Bags tab for listing items one at a time.",
        function() return OnOff(R:Enabled("auctionPosting")) end)
    FeatureRow("skins", "Addon skins", "The EllesmereUI look for supported addons.", function()
        local installed, on = 0, 0
        for _, skin in ipairs(SKINS) do
            if AddonState(skin.addon) ~= "missing" then
                installed = installed + 1
                if R:Enabled(skin.key) then on = on + 1 end
            end
        end
        if installed == 0 then return R.GREY .. "None installed|r" end
        return OnOff(on > 0, ("%d of %d on"):format(on, installed), "Off")
    end)
    FeatureRow("sharing", "Configuration sharing", "Share your addon settings with friends, and keep backups.",
        function() return OnOff(R:Enabled("setupSharing")) end)
    RefreshOverview()

    -----------------------------------------------------------------------
    Header("General")
    local advancedSetting = Settings.RegisterAddOnSetting(category, "TWICHUI_showAdvanced", "showAdvanced", TwichUIDB.ui, BOOL,
        "Show advanced options", false)
    Settings.CreateCheckbox(category, advancedSetting,
        "Shows an Advanced section on the pages that have one: how upgrade hints are judged and revealed and the bag mark style (Gear comparison), how long the zone card stays (Notifications), your own colors and the number's font (Combo points, for Rogues), and how configurations are sent (Configuration sharing). Hidden options keep their values.")
    Toggle("media", "Custom fonts and sounds",
        "Adds Alegreya, Alegreya Sans, Barlow, Cinzel and Spectral fonts, plus the bell alert sounds, to the font and sound lists of EllesmereUI and other addons. Nothing changes until you pick them there.",
        true)
    Toggle("quietLogin", "Hide addon welcome messages",
        "Hides the \"loaded\" and \"type /command for options\" lines addons print when you log in or reload. Errors and warnings still show. Type /twichui hidden to see what was hidden this session.",
        true)

    Settings.RegisterAddOnCategory(root)
end

R:OnInit(function()
    local ok, err = pcall(Build)
    if not ok then geterrorhandler()(err) end
end)
