-- TwichUI options: the SpeakStone speech frame's look (modules/SpeakStoneSkin.lua). A page of its own under
-- Addon skins. Not through EllesmereUI, which it doesn't need.

local R = TwichUI
local K = R.SettingsKit

local STATUS = {
    off = { "Off", nil },
    ["speakstone-missing"] = { "SpeakStone not installed", "Install SpeakStone Forever - Main to use this. Your settings here are kept." },
    ["speakstone-disabled"] = { "SpeakStone turned off", "SpeakStone is turned off in your AddOns list. Your settings here are kept." },
    waiting = { "Waiting for the speech frame", "SpeakStone builds its speech frame the first time it has something to show: a spoken line, or the sample line below. The look is applied then." },
    unsupported = { "This SpeakStone isn't supported", "This version of SpeakStone's speech frame doesn't have the pieces the skin needs. Nothing was changed." },
    error = { "Stopped after an error", "The skin put SpeakStone's frame back as it was after an error. Turn it off and on again, or reload your UI, to try again. /tui diagnostics has the details." },
    active = { "Active", nil },
}

K.Page({
    key = "speakstone", name = "SpeakStone speech frame", parent = "skins", order = 96,
    when = function() return R.SpeakStoneSkin ~= nil end,
    build = function()
        local SS = R.SpeakStoneSkin
        local Style = SS.Style
        local Header, Toggle, Button, Proxy, ProxyToggle, Advanced, Under = K.Header, K.Toggle, K.Button, K.Proxy, K.ProxyToggle, K.Advanced, K.Under
        local BOOL, STRING, NUMBER = K.BOOL, K.STRING, K.NUMBER

        Header("SpeakStone speech frame", "Gives SpeakStone's speech frame (the bar that shows who is speaking, the text, a progress line and Pause, Stop and Replay) a TwichUI look: a warm background and thin bronze border, fonts and colors of your choosing, quieter controls and a ringed portrait. It only changes how the frame is drawn: SpeakStone's narration, queue, timing, text, size, position and lock are its own. Works with or without EllesmereUI.")
        local function SkinStatus()
            local state = SS.Status()
            local text = STATUS[state.code] or { state.code }
            local color = (state.code == "active" and R.GREEN) or (state.code == "off" and R.GREY) or R.GOLD
            return color .. text[1] .. "|r", text[2]
        end
        local base = "Gives SpeakStone's speech frame the TwichUI look. Turning it off puts SpeakStone's own look back at once; no reload is needed. Everything below is TwichUI's look; SpeakStone's own settings (its size, position, lock and narration) are unchanged."
        local toggle = Toggle("speakstoneSkin", "Skin the SpeakStone speech frame", base, false, function()
            SS.OnSwitch()
            K.RefreshOverview()
        end)
        if toggle and toggle.GetTooltip ~= nil then
            -- the status is read when the tooltip is shown, so it is never stale
            toggle.GetTooltip = function()
                local status, detail = SkinStatus()
                return base .. "\n\nStatus: " .. status .. (detail and ("\n" .. detail) or "")
            end
        end
        local function On() return R:Enabled("speakstoneSkin") end

        Under(Button("Sample line", "Show or hide", function() SS.TogglePreview() end,
            "Shows SpeakStone's own sample line (the one /ss frame shows), so you can see the look as you change it. No narration is played and nothing is recorded. While SpeakStone is speaking it says so in chat and shows nothing."), toggle, On)

        local resettable = K.Appearance(SS.Look, "speakstoneLook", "speech frame", nil, nil, nil, nil, toggle, On, {
            order = { "BgColor", "BgOpacity", "BorderColor", "BgTexture", "BorderTexture", "BorderSize", "BorderOpacity" },
            advanced = { BgTexture = true, BorderTexture = true, BorderSize = true, BorderOpacity = true },
            labels = {
                BgTexture = "Frame background texture", BgColor = "Frame background color",
                BgOpacity = "Frame background opacity", BorderTexture = "Frame border texture",
                BorderSize = "Frame border thickness", BorderColor = "Frame border color",
                BorderOpacity = "Frame border opacity",
            },
        })

        local function StyleSetting(variable, varType, label, key)
            local setting = Proxy("speakstone" .. variable, varType, label, Style.DEFAULTS[key],
                function() return Style.Get(key) end, function(value) Style.Set(key, value) end)
            if setting then resettable[#resettable + 1] = { setting = setting, default = Style.DEFAULTS[key] } end
            return setting
        end
        local function Swatch(variable, key, label, tooltip, isAdvanced)
            local row = K.Swatch(StyleSetting(variable, STRING, label, key), tooltip)
            if row then
                if isAdvanced then Advanced(row) end
                Under(row, toggle, On)
            end
        end
        local function Slider(variable, key, label, tooltip, isAdvanced)
            local limit = Style.LIMITS[key]
            local setting = StyleSetting(variable, NUMBER, label, key)
            if not limit then return end
            local row = K.Slider(setting, limit[1], limit[2], tooltip)
            if row then
                if isAdvanced then Advanced(row) end
                Under(row, toggle, On)
            end
        end
        local function Choice(variable, key, label, tooltip, choices, isAdvanced)
            local row = K.Dropdown(StyleSetting(variable, STRING, label, key), function() return choices(Style.Get(key)) end, tooltip)
            if row then
                if isAdvanced then Advanced(row) end
                Under(row, toggle, On)
            end
        end
        local function Check(variable, key, label, tooltip, isAdvanced)
            local row = K.Checkbox(StyleSetting(variable, BOOL, label, key), tooltip)
            if row then
                if isAdvanced then Advanced(row) end
                Under(row, toggle, On)
                return row
            end
        end

        Header("Text", "The speaker's name, the dialogue and the playback time. Fonts come from LibSharedMedia, so fonts other addons add appear here; TwichUI's and EllesmereUI's are listed first. A font that has gone is drawn as SpeakStone's own and stays chosen. Colors SpeakStone puts in the text itself (a quest title after the name) are left as they are.")
        Choice("NameFont", "nameFont", "Speaker font",
            "The font of the speaker's name. The default is TwichUI's title face, which is only available for Western game languages; elsewhere SpeakStone's own font is used.",
            SS.FontChoices)
        Slider("NameSize", "nameSize", "Speaker size", "The size of the speaker's name. The row grows to fit it.")
        Swatch("NameColor", "nameColor", "Speaker color", "The color of the speaker's name. A title SpeakStone shows after it in grey keeps that grey.")
        Choice("TextFont", "textFont", "Dialogue font",
            "The font of the dialogue. SpeakStone's own is the default, so every language it supports keeps its letters.", SS.FontChoices)
        Slider("TextSize", "textSize", "Dialogue size",
            "The size of the dialogue. The text area keeps its four lines (or all of the text, with SpeakStone's \"Show all the text\"), at this size.")
        Swatch("TextColor", "textColor", "Dialogue color", "The color of the dialogue.")
        Swatch("TimeColor", "timeColor", "Playback time color",
            "The color of the time and the queue position, and of a button's label while it is unavailable. Kept quieter than the dialogue by default.")

        Header("Controls", "Pause, Stop, Replay and Next, and the settings and close icons. They keep SpeakStone's own labels, tooltips and clicks.")
        Swatch("ButtonText", "buttonText", "Button label color", "The color of a button's label, and of the settings and close icons.")
        Swatch("ButtonFill", "buttonFill", "Button fill color", "The color of a button's fill. It is a little darker while pressed.")
        Swatch("ButtonBorder", "buttonBorder", "Button border color", "The color of the thin line round each button.")
        Swatch("AccentColor", "accentColor", "Hover accent color", "The color a button's label and the icons take under the pointer, and the faint tint behind them.")

        Check("RightClickClose", "rightClickClose", "Close with a right-click",
            "Hides the close button and makes a right-click on the frame do what the close button did: a line that is playing carries on without the frame, a paused line or the sample is stopped. SpeakStone's own right-click opens its menu (size, lock, reset position, fit text); while this is on that menu is on the gear icon only. Off, the close button and the right-click menu are SpeakStone's.")

        Header("Portrait", "The picture of who is speaking. SpeakStone chooses and updates it; only how it is framed changes.")
        Check("ShowPortrait", "showPortrait", "Show the portrait",
            "Off, the portrait and its ring are not drawn and the name and text take the room it kept.")
        Slider("PortraitSize", "portraitSize", "Portrait size", "The portrait's size. The frame grows to hold a larger one.")
        Choice("PortraitShape", "portraitShape", "Portrait shape",
            "Round is SpeakStone's own. Square shows the whole picture.", function() return SS.SHAPE_CHOICES end)
        Swatch("PortraitBorderColor", "portraitBorderColor", "Portrait ring color", "The color of the thin ring round the portrait.")

        Header("Progress line", "The thin line under the text that follows the voice. SpeakStone works out how far along it is; this changes only how it is drawn.")
        Check("ShowProgress", "showProgress", "Show the progress line", "Off, the line is not drawn and the frame is that much shorter.")
        Swatch("ProgressColor", "progressColor", "Progress fill color", "The color of the part that has been spoken.")
        Swatch("TrackColor", "trackColor", "Progress track color", "The color of the line behind it.")
        Slider("ProgressHeight", "progressHeight", "Progress line thickness", "How thick the line is, in pixels.")

        Advanced(Header("Advanced text and spacing", "Fonts and sizes of the smaller text, and room inside the frame."))
        Choice("TimeFont", "timeFont", "Playback time font", "The font of the time and the queue position.", SS.FontChoices, true)
        Slider("TimeSize", "timeSize", "Playback time size", "The size of the time and the queue position. Kept readable at SpeakStone's smallest size.", true)
        Choice("ButtonFont", "buttonFont", "Button font", "The font of the buttons' labels.", SS.FontChoices, true)
        Slider("ButtonSize", "buttonSize", "Button label size",
            "The size of the buttons' labels. The buttons and their row grow to fit it, and a button widens to keep its label whole.", true)
        Slider("LineSpacing", "lineSpacing", "Line spacing", "Extra pixels between the dialogue's lines. SpeakStone's own is 2.", true)
        Slider("Padding", "padding", "Padding", "The room between the border and the portrait, the text and the controls. It is never less than the border's thickness needs.", true)
        Slider("PortraitBorderSize", "portraitBorderSize", "Portrait ring thickness", "How thick the ring round the portrait is, in pixels. 0 for none.", true)

        local reset = K.ResetButton("Reset appearance", resettable, SS.Reset,
            "Puts this look's background, border, text, controls, portrait, progress line and spacing back to the defaults. Nothing else changes: not the switch, SpeakStone's settings, its size and position, or the rest of TwichUI.")
        Under(reset, toggle, On)

        R:On("PLAYER_LOGIN", K.RefreshOverview)
    end,
})
