-- TwichUI options: the overview (the TwichUI page itself). A row for each feature page with its status and
-- a button to it, where to find help, and the few settings that belong to TwichUI as a whole. Built last,
-- once every page exists (settings/Register.lua).

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "overview", name = "TwichUI", order = 0,
    build = function()
        local Header, Toggle, Button = K.Header, K.Toggle, K.Button

        Header("A quiet interface companion for WoW: Forever.",
            "TwichUI makes the game's interface a little clearer and more cohesive, without taking over. Each feature has its own page below, and every one can be turned off.")

        -- key: page to open; status: a word or two for the row.
        local function FeatureRow(key, label, tooltip, status)
            if not CreateSettingsButtonInitializer then return end
            local initializer = CreateSettingsButtonInitializer(label, "Open", function()
                if Settings.OpenToCategory and R.settingsCategories[key] then
                    Settings.OpenToCategory(R.settingsCategories[key]:GetID())
                end
            end, tooltip, false)
            K.layout:AddInitializer(initializer)
            K.overviewRows[#K.overviewRows + 1] = { initializer = initializer, label = label, status = status }
        end
        -- In the pages' own order; a page that is not there this session (not a Mage, an addon missing) has no row.
        for _, def in ipairs(K.Ordered()) do
            local row = def.overview
            if row and K.pages[def.key] and (row.when == nil or row.when()) then
                FeatureRow(def.key, row.label, row.tip, row.status)
            end
        end
        K.RefreshOverview()

        -----------------------------------------------------------------------
        Header("Help", "Where to find things. Neither button here changes a setting.")
        Button("Welcome", "Show", function()
            K.CloseOptions()
            if R.Welcome then R.Welcome.Show() end
        end, "Shows the short introduction again (same as typing /tui about). It changes nothing.")
        Button("Chat commands", "List", function() R.RunCommand("help") end,
            "Prints the /tui commands in your chat window: this window, the Chronicle, the sharing window, the troubleshooting report and card previews.")

        -----------------------------------------------------------------------
        Header("General")
        local advancedSetting = Settings.RegisterAddOnSetting(K.category, "TWICHUI_showAdvanced", "showAdvanced", TwichUIDB.ui, K.BOOL,
            "Show advanced options", false)
        K.advancedSetting = advancedSetting
        local withAdvanced = {}
        for _, def in ipairs(K.Ordered()) do
            if K.advancedPages[def.key] and K.pages[def.key] then withAdvanced[#withAdvanced + 1] = def.name end
        end
        Settings.CreateCheckbox(K.category, advancedSetting,
            "Shows the Advanced sections, which hold options most players never need to change: textures, fonts, timings and similar. These pages have one: "
            .. table.concat(withAdvanced, ", ") .. ". Hidden options keep their values and keep working.")
        Toggle("media", "Custom fonts and sounds",
            "Adds Alegreya, Alegreya Sans, Barlow, Cinzel and Spectral fonts, plus the bell alert sounds, to the font and sound lists of EllesmereUI and other addons. Nothing changes until you pick them there.",
            true)
        Toggle("quietLogin", "Hide addon welcome messages",
            "Hides the \"loaded\" and \"type /command for options\" lines addons print when you log in or reload. Errors and warnings still show. Type /twichui hidden to see what was hidden this session.",
            true)
    end,
})
