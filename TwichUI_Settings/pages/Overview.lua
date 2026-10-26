-- TwichUI settings: Home. Three ways in at the top (Home.lua: explore the features, adjust their appearance,
-- review what differs from the defaults), where to find help, and the few settings that belong to TwichUI as a
-- whole. Described last, once every page exists (Kit.lua).

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "overview", icon = "home", name = "TwichUI", nav = "Home", order = 0, group = "home",
    description = "A quiet interface companion for WoW: Forever. Every feature has its own page, and every one can be turned off.",
    keywords = "home start overview help general explore features appearance changed modified defaults",
    hero = true,
    build = function()
        local Header, Toggle, Button = K.Header, K.Toggle, K.Button

        Header("Help", "Neither action changes a setting.")
        Button("Welcome", "Show welcome", function()
            K.CloseOptions()
            if R.Welcome then R.Welcome.Show() end
        end, "Shows the short introduction again (same as typing /tui about). It changes nothing.")
        Button("Chat commands", "View commands", function() R.RunCommand("help") end,
            "Prints the /tui commands in your chat window: this window, the Chronicle, the sharing window, the troubleshooting report and card previews.")

        -----------------------------------------------------------------------
        -- The setup wizard is its own addon (TwichUI_LayoutWizard, load on demand): this only opens it. Not a settings page:
        -- it is a workflow with a review, an apply and a restore, so it has its own window.
        if R.LayoutsLauncher then
            Header("Interface layout", "Set up a complete interface: where chat, the minimap, the unit frames and the action bars sit, and how EllesmereUI and TwichUI look, worked out for your screen. Opening the setup changes nothing.")
            Button("Layout setup", "Open layout setup", function()
                K.CloseOptions()
                R.LayoutsLauncher.OpenWizard()
            end, "Opens the setup window (same as typing /tui layout). You choose a layout and a few personal options, review exactly what it would change, and only then apply it, with a restore point so your previous setup can be put back. Nothing changes until you apply, and nothing reloads by itself.")
        end

        -----------------------------------------------------------------------
        Header("General", "Settings for TwichUI as a whole.")
        local motionSetting = K.TableSetting("reduceSettingsMotion", "reduceSettingsMotion", function() return TwichUIDB.ui end,
            "Reduce window motion", false, "switch:ui.reduceSettingsMotion")
        -- changing it puts any easing in progress where it was going, so nothing is left half-way
        motionSetting:SetValueChangedCallback(function()
            local Wg = R.SettingsWidgets
            if Wg and Wg.Motion then Wg.Motion.Settle() end
        end)
        K.Checkbox(motionSetting,
            "Turns off the fades in TwichUI's own windows, the settings and the sharing window: they open, change page and answer the pointer at once, with no easing. A feature card's sample then shows its end at once, with the same words under it. It applies to these windows only; the Reduced motion option under Notifications is separate and is not changed by this. Saved for the account, not per profile.")
        Toggle("media", "Custom fonts and sounds",
            "Adds Alegreya, Alegreya Sans, Barlow, Cinzel and Spectral fonts, plus the bell alert sounds, to the font and sound lists of EllesmereUI and other addons. Nothing changes until you pick them there.")
        Toggle("quietLogin", "Hide addon welcome messages",
            "Hides the \"loaded\" and \"type /command for options\" lines addons print when you log in or reload. Errors and warnings still show. Type /twichui hidden to see what was hidden this session.")
    end,
})
