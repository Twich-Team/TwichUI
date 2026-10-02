-- TwichUI: options in Esc > Options > AddOns > TwichUI (/twichui)
-- The one home for TwichUI's settings, built from Blizzard's own controls.
-- Rarely changed options only show with "Show advanced options" on; they keep
-- their values (and keep working) while hidden. Stat weights get their own
-- page under TwichUI (gear/Window.lua), since a ranked list and a table of
-- numbers don't fit the standard controls.

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
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local category, layout = Settings.RegisterVerticalLayoutCategory("TwichUI")
    R.settingsCategory = category
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
    Header("General")
    local advancedSetting = Settings.RegisterAddOnSetting(category, "TWICHUI_showAdvanced", "showAdvanced", TwichUIDB.ui, BOOL,
        "Show advanced options", false)
    Settings.CreateCheckbox(category, advancedSetting,
        "Shows rarely changed options in each section below: how upgrade hints are judged and revealed, the bag mark style, and how configurations are sent. Hidden options keep their values.")
    Toggle("media", "Custom fonts and sounds",
        "Adds Alegreya, Alegreya Sans, Barlow and Cinzel fonts, plus the bell alert sounds, to the font and sound lists of EllesmereUI and other addons. Nothing changes until you pick them there.",
        true)

    -----------------------------------------------------------------------
    Header("Gear comparison", "Quiet upgrade hints for your class and main talent tree. A rough estimate from item stats, not a simulation.")
    Toggle("gearHints", "Upgrade hints in item tooltips",
        "Adds a short line to an item's tooltip when it looks like an upgrade for your class and main talent tree, such as \"Likely upgrade for Fury\". Hold Shift (your compare-items key) to see why.\n\n\"Use:\" and \"Chance on hit:\" effects aren't weighed.",
        false)
    local bags = Toggle("gearBagIcons", "Mark upgrades in my bags",
        "A small mark in the corner of bag slots holding gear the tooltip would call an upgrade, fainter for possible upgrades. Works with Blizzard's bags; bag addons draw their own slots.",
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
            local styles = {}
            for i, style in ipairs(B.STYLES) do styles[i] = { style.key, style.label } end
            Under(Advanced(Choice("gearBagStyle", "Bag mark style",
                "The mark on upgrades in your bags. All use the game's own art.",
                STRING, "gilded",
                function() return P.Get("bagStyle") end, function(value) P.Set("bagStyle", value) end,
                styles)), bags, function() return R:Enabled("gearBagIcons") end)
        end
    end

    -----------------------------------------------------------------------
    Header("Addon skins", "Gives these addons the EllesmereUI look. Needs EllesmereUI with its third-party addon skins on. TwichUI only skins the addons listed here.")
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
    Header("Chat")
    Toggle("quietLogin", "Hide addon welcome messages",
        "Hides the \"loaded\" and \"type /command for options\" lines addons print when you log in or reload. Errors and warnings still show. Type /twichui hidden to see what was hidden this session.",
        true)

    -----------------------------------------------------------------------
    Header("Configuration sharing", "Share the settings of the addons you choose with friends, and apply theirs. You always choose what to apply, and Undo puts your own settings back.")
    local sharing = Toggle("setupSharing", "Configuration sharing",
        "Save the settings of the addons you choose as an addon configuration, send it to friends in game, and apply configurations friends send you. Type /pack.",
        true)
    local function SharingOn() return R:Enabled("setupSharing") end
    Under(Toggle("acceptSetups", "Let friends send me addon configurations",
        "When on, friends can offer you their addon configuration. You're always asked first, unless you chose \"Always accept\" for that friend. Nothing is applied until you click Apply.",
        false), sharing, SharingOn)
    Toggle("groupCheck", "Version and group check",
        "Off until you turn it on. Both players need it on to see each other.\n\nWhen you're in a group, TwichUI trades version numbers with other TwichUI users (a few bytes, group channel only) and tells you when someone's version is newer or too old to share with. Also powers /twichui check and the Group tab, and a once-per-game-build test that switches sharing back to direct messages when Forever fixes them.",
        false)
    Button("Configuration sharing", "Open", function()
        if not R:Enabled("setupSharing") then
            R.Print("turn on Configuration sharing first.")
            return
        end
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        R.Window:Show()
    end, "Opens the Configuration sharing window: send your configuration, apply ones friends sent, restore points and group check (same as typing /pack).")
    Advanced(Toggle("shareWhisper", "Send by direct message",
        "Send and receive configurations with hidden addon messages straight to one player. Only they receive it.\n\n" .. R.Share.WHY_FOREVER,
        false))
    Advanced(Toggle("shareGroup", "Send over the group channel",
        "Send and receive over your party or raid's hidden addon channel. Everyone in the group receives the data; only the named recipient's TwichUI reads it, the rest ignore it. No chat text appears.\n\nUse this on Forever, where direct messages don't work yet.",
        false))
    Advanced(Toggle("shareGuild", "Send over the guild channel",
        "Send and receive over your guild's hidden addon channel. Every online guild member receives the data; only the named recipient's TwichUI reads it. No chat text appears, but it uses guild-wide bandwidth, so prefer the group channel when you can.",
        false))

    if R.GearWindow and R.GearWindow.Register then R.GearWindow:Register(category) end
    Settings.RegisterAddOnCategory(category)
end

R:OnInit(function()
    local ok, err = pcall(Build)
    if not ok then geterrorhandler()(err) end
end)
