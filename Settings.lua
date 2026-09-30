-- TwichUI: options in Esc > Options > AddOns > TwichUI (/twichui)
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

local function Build()
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local category, layout = Settings.RegisterVerticalLayoutCategory("TwichUI")
    R.settingsCategory = category
    local BOOL = (Settings.VarType and Settings.VarType.Boolean) or "boolean"

    local function Header(text)
        if CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end

    local function Toggle(key, label, tooltip, needsReload)
        local setting = Settings.RegisterAddOnSetting(category, "TWICHUI_" .. key, key, TwichUIDB.modules, BOOL, label, R.DEFAULT_MODULES[key])
        Settings.CreateCheckbox(category, setting, tooltip)
        if setting.SetValueChangedCallback then
            setting:SetValueChangedCallback(function()
                if needsReload then AskReload() end
                if R.Window then R.Window:Refresh() end
            end)
        end
        return setting
    end

    local function Button(label, buttonText, onClick, tooltip)
        if CreateSettingsButtonInitializer then
            layout:AddInitializer(CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true))
        end
    end

    Header("Media")
    Toggle("media", "Custom fonts and sounds",
        "Adds Alegreya, Alegreya Sans, Barlow and Cinzel fonts, plus the bell alert sounds, to the font and sound lists of EllesmereUI and other addons. Nothing changes until you pick them there.",
        true)

    Header("Chat")
    Toggle("quietLogin", "Hide addon welcome messages",
        "Hides the \"loaded\" and \"type /command for options\" lines addons print when you log in or reload. Errors and warnings still show. Type /twichui hidden to see what was hidden this session.",
        true)

    Header("Skins")
    Toggle("auctionatorSkin", "Skin Auctionator",
        "Gives Auctionator's tabs, buttons, lists and boxes the EllesmereUI look. Needs EllesmereUI with its Auction House window skin turned on.",
        true)

    Header("Configuration Sharing")
    Toggle("setupSharing", "Configuration Sharing",
        "Save the settings of the addons you choose as an addon configuration, send it to friends in game, and apply configurations friends send you. Type /pack.",
        true)
    Toggle("acceptSetups", "Let friends send me addon configurations",
        "When on, friends can offer you their addon configuration. You're always asked first, unless you chose \"Always accept\" for that friend. Nothing is applied until you click Apply.",
        false)
    Header("Configuration Sharing: how it's sent")
    Toggle("shareWhisper", "Allow direct messages",
        "Send and receive configurations with hidden addon messages straight to one player. Only they receive it.\n\n" .. TwichUI.Share.WHY_FOREVER,
        false)
    Toggle("shareGroup", "Allow group channel",
        "Send and receive over your party or raid's hidden addon channel. Everyone in the group receives the data; only the named recipient's TwichUI reads it, the rest ignore it. No chat text appears.\n\nUse this on Forever, where direct messages don't work yet.",
        false)
    Toggle("shareGuild", "Allow guild channel",
        "Send and receive over your guild's hidden addon channel. Every online guild member receives the data; only the named recipient's TwichUI reads it. No chat text appears, but it uses guild-wide bandwidth, so prefer the group channel when you can.",
        false)
    Header("Group")
    Toggle("groupCheck", "Version and group check",
        "Off until you turn it on. Both players need it on to see each other.\n\nWhen you're in a group, TwichUI trades version numbers with other TwichUI users (a few bytes, group channel only) and tells you when someone's version is newer or too old to share with. Also powers /twichui check and the Group tab, and a once-per-game-build test that switches sharing back to direct messages when Forever fixes them.",
        false)
    Button("Open Configuration Sharing", "Open", function()
        if not R:Enabled("setupSharing") then
            R.Print("turn on Configuration Sharing first.")
            return
        end
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        R.Window:Show()
    end, "Opens the Configuration Sharing window (same as typing /pack).")

    Settings.RegisterAddOnCategory(category)
end

R:OnInit(function()
    local ok, err = pcall(Build)
    if not ok then geterrorhandler()(err) end
end)
