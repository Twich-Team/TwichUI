-- TwichUI settings: Home. A row for each feature page with its status and a way to it, where to find help,
-- and the few settings that belong to TwichUI as a whole. Described last, once every page exists (Kit.lua).

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "overview", name = "TwichUI", nav = "Home", order = 0, group = "home",
    description = "A quiet interface companion for WoW: Forever. Every feature has its own page, and every one can be turned off.",
    keywords = "home start overview help general",
    build = function()
        local Header, Toggle, Button = K.Header, K.Toggle, K.Button

        Header("Help", "Where to find things. Neither button here changes a setting.")
        Button("Welcome", "Show", function()
            K.CloseOptions()
            if R.Welcome then R.Welcome.Show() end
        end, "Shows the short introduction again (same as typing /tui about). It changes nothing.")
        Button("Chat commands", "List", function() R.RunCommand("help") end,
            "Prints the /tui commands in your chat window: this window, the Chronicle, the sharing window, the troubleshooting report and card previews.")

        -----------------------------------------------------------------------
        Header("General", "Settings for TwichUI as a whole.")
        local advancedSetting = K.TableSetting("showAdvanced", "showAdvanced", function() return TwichUIDB.ui end,
            "Show advanced options", false, "switch:ui.showAdvanced")
        local withAdvanced = {}
        for _, def in ipairs(K.Ordered()) do
            if K.advancedPages[def.key] and K.pages[def.key] then withAdvanced[#withAdvanced + 1] = def.name end
        end
        K.Checkbox(advancedSetting,
            "Opens the Advanced sections by themselves. They hold options most players never need to change: textures, fonts, timings and similar. Off, each one opens when you choose it. These pages have one: "
            .. table.concat(withAdvanced, ", ") .. ". Advanced options keep their values and keep working either way.")
        Toggle("media", "Custom fonts and sounds",
            "Adds Alegreya, Alegreya Sans, Barlow, Cinzel and Spectral fonts, plus the bell alert sounds, to the font and sound lists of EllesmereUI and other addons. Nothing changes until you pick them there.")
        Toggle("quietLogin", "Hide addon welcome messages",
            "Hides the \"loaded\" and \"type /command for options\" lines addons print when you log in or reload. Errors and warnings still show. Type /twichui hidden to see what was hidden this session.")
    end,
})
