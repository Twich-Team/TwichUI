-- TwichUI settings: the RestedXP guide window's look (modules/RestedXPSkin.lua) and its timer bars
-- (modules/RestedXPTimers.lua). A page of its own under Addon skins. Not through EllesmereUI, which it doesn't need.

local R = TwichUI
local K = R.SettingsKit

local STATUS = {
    off = { "Off", nil },
    ["restedxp-missing"] = { "RestedXP not installed", "Install RestedXP Guides to use this. Your settings here are kept." },
    ["restedxp-disabled"] = { "RestedXP turned off", "RestedXP Guides is turned off in your AddOns list. Your settings here are kept." },
    waiting = { "Waiting for RestedXP", "RestedXP hasn't finished loading yet." },
    unsupported = { "This RestedXP isn't supported", "This version of RestedXP doesn't have what the skin needs (RenderFrame, RegisterTheme and its guide window). Nothing was changed." },
    conflict = { "Another RestedXP skin is drawing", "EUI-RestedXP or LiteTweaks is replacing RestedXP's window. Layering two skins would fight, so this one waits. Turn the other's RestedXP skin off, then press Use the TwichUI look." },
    ["theme-not-selected"] = { "Another RestedXP theme is chosen", "RestedXP is using a different theme, so the skin is stepped aside. Press Use the TwichUI look, or choose TwichUI under RestedXP's Look and Feel." },
    ["v2-window"] = { "Colors and font only", "RestedXP's v2 guide window (beta) is on. Only the theme's colors and font reach it; its frames are drawn by RestedXP." },
    active = { "Active", nil },
}

local TIMER_STATUS = {
    off = "Off: timer bars are drawn as RestedXP draws them.",
    ["skin-off"] = "Waiting: the guide window's look isn't drawing (the skin is off, another RestedXP theme is chosen, or another skin is replacing the window).",
    unsupported = "This version of RestedXP has no timer bars this can draw. Nothing was changed.",
    active = "Active.",
}

K.Page({
    key = "restedxp", name = "RestedXP guide window", nav = "RestedXP guide window", parent = "skins", order = 95,
    description = "A TwichUI look for the RestedXP Guides window, its waypoint arrow and its timer bars. Guide content and progress are RestedXP's own.",
    keywords = "restedxp rxp guide leveling arrow timer bar step theme",
    when = function() return R.RestedXPSkin ~= nil end,
    build = function()
        local RS = R.RestedXPSkin
        local Header, Toggle, Button, Proxy, ProxyToggle, Under = K.Header, K.Toggle, K.Button, K.Proxy, K.ProxyToggle, K.Under
        local BOOL, STRING, NUMBER = K.BOOL, K.STRING, K.NUMBER

        local intro = Header("RestedXP guide window", "Gives the RestedXP Guides window a TwichUI look: a background and border, text colors, fonts and sizes, a quieter header and footer, and a slim scroll bar; and its waypoint arrow a shape, color and size of your choosing. It never changes guide content, progress, step completion or the window's position and size. Works with or without EllesmereUI. There is no sample here: open RestedXP's guide window to see each change as you make it.")
        local function RestedXPStatus()
            local state = RS.Status()
            local text = STATUS[state.code] or { state.code }
            local color = (state.code == "active" and R.GREEN) or (state.code == "off" and R.GREY) or R.GOLD
            return color .. text[1] .. "|r", text[2]
        end
        local rxpBase = "Gives the RestedXP guide window the TwichUI look. Turning it on makes TwichUI the theme RestedXP uses (it remembers the one you had); turning it off puts that one back. Everything below is TwichUI's look; RestedXP's own settings are unchanged."
        local rxpToggle = Toggle("restedxpSkin", "Skin the RestedXP guide window", rxpBase)
        if rxpToggle and rxpToggle.GetTooltip ~= nil then
            -- the status is read when the tooltip is shown, so it is never stale
            rxpToggle.GetTooltip = function(self)
                local status, detail = RestedXPStatus()
                return rxpBase .. "\n\nStatus: " .. status .. (detail and ("\n" .. detail) or "")
            end
        end
        local function RxpOn() return R:Enabled("restedxpSkin") end
        local use = Button("TwichUI look in RestedXP", "Use it", function()
            local ok, why = RS.UseTheme()
            if not ok then
                local reason = why == "conflict" and "another RestedXP skin is drawing."
                    or why == "combat" and "it will be applied when combat ends."
                    or "RestedXP isn't ready."
                R.Print("RestedXP skin: %s", reason)
            end
        end, "Makes TwichUI's theme the one RestedXP uses, if you chose another in RestedXP's own options. The theme you had is remembered and put back if you turn the skin off.")
        Under(use, rxpToggle, RxpOn)

        Header("Window background and border", "The guide window's fill and edge: textures, color, opacity and thickness. Textures come from the game, from EllesmereUI (while it is installed) and from any LibSharedMedia pack.")
        local resettable = K.Appearance(RS.Look, "restedxpLook", "window", nil, nil, nil, nil, rxpToggle, RxpOn, {
            labels = {
                BgTexture = "Window background texture", BgColor = "Window background color",
                BgOpacity = "Window background opacity", BorderTexture = "Window border texture",
                BorderSize = "Window border thickness", BorderColor = "Window border color",
                BorderOpacity = "Window border opacity",
            },
        })

        local function TextSetting(variable, varType, label, key)
            local setting = Proxy("restedxp" .. variable, varType, label, RS.Text.DEFAULTS[key],
                function() return RS.Text.Get(key) end, function(value) RS.Text.Set(key, value) end)
            if setting then resettable[#resettable + 1] = { setting = setting, default = RS.Text.DEFAULTS[key] } end
            return setting
        end
        local function TextSwatch(variable, key, label, tooltip)
            local row = K.Swatch(TextSetting(variable, STRING, label, key), tooltip)
            if row then Under(row, rxpToggle, RxpOn) end
        end
        local function TextChoice(variable, key, label, tooltip, choices)
            local row = K.Dropdown(TextSetting(variable, STRING, label, key), function() return choices(RS.Text.Get(key)) end, tooltip)
            if row then
                Under(row, rxpToggle, RxpOn)
                return row
            end
        end
        local function TextToggle(variable, key, label, tooltip)
            local row = K.Checkbox(TextSetting(variable, BOOL, label, key), tooltip)
            if row then
                Under(row, rxpToggle, RxpOn)
                return row
            end
        end
        local function TextSlider(variable, key, label, tooltip, parent, isOn, why)
            local limit = RS.Text.LIMITS[key]
            local setting = TextSetting(variable, NUMBER, label, key)
            if not limit then return end
            return Under(K.Slider(setting, limit[1], limit[2], tooltip), parent or rxpToggle, isOn or RxpOn, why)
        end
        Header("Text", "Colors, fonts and outlines of the guide's title and steps. Sizes are set under Text size, or follow RestedXP's own Guide Font Size option.")
        TextSwatch("TitleColor", "titleColor", "Title text color",
            "The color of the guide's title, the footer and each step's number tab. Colors RestedXP gives meaning to in a step's own text (warnings, objectives, links) are not changed.")
        TextChoice("TitleFont", "titleFont", "Title font",
            "The font of the guide's title, the footer and step number tabs. The list comes from LibSharedMedia, so fonts other addons add appear here. RestedXP's own is the default. A font that has gone is drawn as the default and stays chosen.",
            RS.FontChoices)
        TextChoice("TitleOutline", "titleOutline", "Title outline", "An outline round the title text.",
            function() return RS.OUTLINE_CHOICES end)
        TextSwatch("BodyColor", "bodyColor", "Step text color",
            "The base color of the step and objective text. Colors RestedXP gives meaning to (warnings, objectives, links) are not changed.")
        TextChoice("BodyFont", "bodyFont", "Step text font",
            "The font of step and objective text. A font that has gone is drawn as RestedXP's own and stays chosen.",
            RS.FontChoices)
        TextChoice("BodyOutline", "bodyOutline", "Step text outline", "An outline round the step and objective text.",
            function() return RS.OUTLINE_CHOICES end)

        Header("Current step", "The panel above the guide list that shows the step you are on.")
        TextToggle("SettingsButton", "settingsButton", "Show settings button on current-step hover",
            "A small cog in the upper-right corner of the current-step panel, shown while the pointer is over the panel. It opens RestedXP's menu (choose a guide, go to a step, RestedXP's options), the same one as the menu button at the footer's left, so it is there even when that button is hidden below. It is only a shortcut: it changes nothing in RestedXP and does not move the text.")
        TextChoice("StepLabel", "stepLabel", "Step label format",
            "What the tab above the current step says. X is the step's number in the guide, the one RestedXP shows in its list. Y is how many steps the guide has: its whole list, including steps with nothing to do (so it is the number of the last row), for the character you are on. The percentage is X divided by Y, rounded to the nearest whole number: it is how far along the guide's steps you are, not time spent and not a promise that every objective on the way was done (the last step reads 100 %). A tab with a title of its own, such as a tip, is left as RestedXP draws it; where the guide's size isn't known, the tab says Step X. While in combat the tab shows RestedXP's own text and changes when it ends.",
            function() return RS.STEPLABEL_CHOICES end)

        Header("Header and footer", "What sits around the guide list. RestedXP's logo and class badge are hidden by default, which gives the guide's title the room they took.")
        TextToggle("ShowTitle", "showTitle", "Show the guide's title",
            "The guide's name in the header. Off, the header's background and border go too, leaving a slim invisible strip (it is still the window's handle, and right-click on it still opens RestedXP's menu), and the name is in the tooltip of the menu button at the footer's left.")
        TextToggle("ShowLogo", "showLogo", "Show RestedXP's logo",
            "RestedXP's round logo at the left of the guide's title. Off, the title takes the room it kept. It is only a picture; the header's menu and the menu button work either way.")
        TextToggle("ShowClassIcon", "showClassIcon", "Show the class badge",
            "The small badge of your class that RestedXP draws beside its logo. Off by default. On, it sits by itself at the left of the title when the logo is off.")
        TextToggle("ShowCog", "showCog", "Show the menu button",
            "The small cog at the footer's left, which opens RestedXP's menu (choose a guide, go to a step, options). Off, the guide menu is still on a right click of the header, and choosing a guide or opening the options is on a right click of a step in the list; the version text loses its tooltip. With the resize handle off as well, the whole bar at the bottom goes and the list takes its room.")
        TextToggle("ShowResizeHandle", "showResizeHandle", "Show the resize handle",
            "The small grip at the footer's right, which resizes the window when dragged. Off, hold Alt and drag the window to resize it, as RestedXP allows. With the menu button off as well, the whole bar at the bottom goes and the list takes its room.")
        TextChoice("Footer", "footer", "Version text",
            "RestedXP's footer shows its version and the range of guide formats it supports. Subdued: smaller and quieter. Hidden: not drawn; it is then in the tooltip of the menu button at the footer's left, which is always there. As RestedXP draws it: unchanged.",
            function() return RS.FOOTER_CHOICES end)
        TextChoice("Dividers", "dividers", "Header and footer borders",
            "Light: the header, the footer and each step's tab draw a fainter border than the window, with no highlight line, so the borders don't stack. Full border: the same border as the window.",
            function() return RS.DIVIDER_CHOICES end)

        Header("Text size", "Sizes of the guide's text. They follow RestedXP's own Guide Font Size option until you set them here.")
        local sizes = TextToggle("CustomSizes", "customSizes", "Set text sizes here",
            "Off: the sizes follow RestedXP's Guide Font Size option, as they always have. On: the three sizes below are used instead, and rows and the window's header grow to fit. RestedXP's option is not changed.")
        local function SizesOn() return RxpOn() and RS.Text.Get("customSizes") end
        local function SizesWhy() if RxpOn() then return "Greyed out: needs \"Set text sizes here\" turned on." end end
        if sizes then
            TextSlider("TitleSize", "titleSize", "Guide title size",
                "The size of the guide's title in the header. The footer text follows it, a little smaller. RestedXP's own is its Guide Font Size plus 2.", sizes, SizesOn, SizesWhy)
            TextSlider("ActiveSize", "activeSize", "Current step text size",
                "The size of the text in the current-step panel above the guide, and of its step tab and icons. RestedXP's own is its Guide Font Size plus 2.", sizes, SizesOn, SizesWhy)
            TextSlider("ListSize", "listSize", "Guide list text size",
                "The size of the text in the list of steps, and of its numbers (one smaller). RestedXP's own is its Guide Font Size.", sizes, SizesOn, SizesWhy)
        end

        Header("Spacing", "Room around the guide's text. Heights, wrapping and the scroll range are RestedXP's own and follow these.")
        TextSlider("LineSpacing", "lineSpacing", "Line spacing",
            "Extra pixels between the lines of a step that wraps, in the list and in the current-step panel. 0 is RestedXP's own.")
        TextSlider("StepPadding", "stepPadding", "Step padding",
            "Extra pixels under each line of the current-step panel and between rows of the list. 0 is RestedXP's own.")

        TextSlider("FutureFade", "futureFade", "Fade the guide list",
            "How much the whole guide list is dimmed, in percent: its background and border, the scroll bar, the steps, and the bar below it with the menu button and the resize handle. The header and the current-step panel stay as they are, so the step you are on stands out. It is only less visible: everything still works. 0 leaves it as RestedXP draws it.")

        Header("Scroll bar", "The guide list's scroll bar.")
        TextChoice("Scrollbar", "scrollbar", "Scroll bar style",
            "Slim: RestedXP's own scroll bar, narrower, with a thin strip for the thumb and a faint track. With EllesmereUI installed the arrows are its arrow icons and the strip is drawn the way its windows draw theirs; without it they are the game's own arrows. Scrolling is unchanged. RestedXP's own: its round arrows and knob.",
            function() return RS.SCROLLBAR_CHOICES end)
        local tint = ProxyToggle("restedxpTintScrollbar", "Tint the scroll bar",
            "The slim scroll bar's strip and arrows take the border color, at a soft strength. Off: EllesmereUI's neutral white (or the game's own arrows). Applies to RestedXP's own scroll bar too, which is tinted to the border color.", RS.Text.DEFAULTS.tintScrollbar,
            function() return RS.Text.Get("tintScrollbar") end, function(value) RS.Text.Set("tintScrollbar", value) end)
        Under(tint, rxpToggle, RxpOn)

        Header("Waypoint arrow", "RestedXP's arrow that points to the next place in the guide. Its own options (Arrow Scale, Arrow Text Size, turning it off) are RestedXP's and stay; these are applied on top. It is only its picture and string that change: where it points, and when it shows, are RestedXP's.")
        TextChoice("ArrowShape", "arrowShape", "Arrow shape",
            "The arrow's picture: TwichUI's bronze plate, RestedXP's own pointer for its theme, the pointer each of RestedXP's other themes draws (blue, red, gold, green and so on), its v2 pointer, and EllesmereUI's chevron when it is installed. All of them point up, so RestedXP rotates them the same way. A shape that has gone is drawn as RestedXP's own and stays chosen.",
            RS.ArrowChoices)
        TextSwatch("ArrowColor", "arrowColor", "Arrow color",
            "A tint over the picture. White leaves it as drawn; a color multiplies it, so it shows best on a light picture such as EllesmereUI's chevron, and the bronze plate takes it as a stain.")
        TextSlider("ArrowOpacity", "arrowOpacity", "Arrow opacity",
            "How solid the arrow's picture is, in percent. The text beside it is not affected.")
        TextSlider("ArrowSize", "arrowSize", "Arrow size",
            "The arrow's size as a percentage of RestedXP's own, which its Arrow Scale option sets: 100 is RestedXP's. The two multiply.")
        TextToggle("ArrowTextShown", "arrowTextShown", "Show the arrow's text",
            "The name of the step and the distance under the arrow. Off, only the arrow is drawn.")
        TextSlider("ArrowTextSize", "arrowTextSize", "Arrow text size",
            "The text under the arrow as a percentage of RestedXP's own, which its Arrow Text Size option sets: 100 is RestedXP's.")

        -- Timer bars: the countdown bars RestedXP shows for waits and flights. A finish on this skin
        -- (modules/RestedXPTimers.lua); greyed out unless the skin and its own switch are on.
        local TM = RS.Timers
        if TM then
            local Opt = TM.Opt
            local function TimersOn() return RxpOn() and Opt.Get("skinTimers") end
            local function TimersWhy() if RxpOn() then return "Greyed out: needs \"Skin timer bars\" turned on." end end
            local resettableTimers = {}
            local timerSwitch = ProxyToggle("restedxpSkinTimers", "Skin timer bars",
                "Gives the countdown bars RestedXP shows at the bottom of its window (waiting for an event or scene, a flight, Hearthstone timing) the same look. Off: the guide window keeps its look and the bars stay as RestedXP draws them. It only changes how a bar is drawn: durations, countdowns and guide progress are RestedXP's own.",
                Opt.DEFAULTS.skinTimers, function() return Opt.Get("skinTimers") end, function(value) Opt.Set("skinTimers", value) end)
            Under(timerSwitch, rxpToggle, RxpOn)
            -- the timer bars' Reset turns this back on, so its checkbox is told too
            if timerSwitch and timerSwitch.GetSetting then
                resettableTimers[#resettableTimers + 1] = { setting = timerSwitch:GetSetting(), default = Opt.DEFAULTS.skinTimers }
            end
            if timerSwitch and timerSwitch.GetTooltip ~= nil then
                -- read when the tooltip is shown (with the greyed-out reason, if any), so it is never stale
                local withParent = timerSwitch.GetTooltip
                timerSwitch.GetTooltip = function(self)
                    local state = TM.Status()
                    return (withParent(self) or "") .. "\n\nStatus: " .. (TIMER_STATUS[state.code] or state.code)
                end
            end
            local function Timer(setting, default)
                if setting then resettableTimers[#resettableTimers + 1] = { setting = setting, default = default } end
                return setting
            end
            local function TimerSetting(variable, varType, label, key)
                return Timer(Proxy("restedxpTimer" .. variable, varType, label, Opt.DEFAULTS[key],
                    function() return Opt.Get(key) end, function(value) Opt.Set(key, value) end), Opt.DEFAULTS[key])
            end
            local function TimerChoice(variable, key, label, tooltip, choices)
                local row = K.Dropdown(TimerSetting(variable, STRING, label, key), function()
                    return type(choices) == "function" and choices(Opt.Get(key)) or choices
                end, tooltip)
                if row then
                    Under(row, timerSwitch, TimersOn, TimersWhy)
                end
            end
            local function TimerSwatch(variable, key, label, tooltip)
                local row = K.Swatch(TimerSetting(variable, STRING, label, key), tooltip)
                if row then
                    Under(row, timerSwitch, TimersOn, TimersWhy)
                end
            end
            local function TimerSlider(variable, key, label, tooltip)
                local limit = Opt.LIMITS[key]
                local setting = TimerSetting(variable, NUMBER, label, key)
                if not limit then return end
                local row = K.Slider(setting, limit[1], limit[2], tooltip)
                if row then
                    Under(row, timerSwitch, TimersOn, TimersWhy)
                end
            end
            local function TimerToggle(variable, key, label, tooltip)
                local row = K.Checkbox(TimerSetting(variable, BOOL, label, key), tooltip)
                if row then
                    Under(row, timerSwitch, TimersOn, TimersWhy)
                end
            end

            Header("Timer bars", "The countdown bars RestedXP shows under its window while you wait for an event or a scene, or ride a flight. Only how they are drawn changes: their time, when they start and end, and what a step needs are RestedXP's own. While RestedXP's v2 guide window (beta) is on they are left as RestedXP draws them.")
            TimerChoice("FillGradient", "fillGradient", "Fill gradient",
                "How the fill shades from the fill color to the second color: left to right, bottom to top, or one color. The shading is drawn across the part of the bar that is filled, so it narrows as the bar runs down. If the game can't draw it, the average of the two colors is used.",
                TM.GRADIENT_CHOICES)
            TimerSwatch("FillColor", "fillColor", "Fill color",
                "The color of the fill, or its darker end when it shades to a second color. The default is a burnished bronze.")
            TimerSwatch("FillColor2", "fillColor2", "Fill gradient end color",
                "The lighter end of the fill's shading (the right or the top). Not used when the gradient is set to None. The default is a muted antique gold.")
            TimerSlider("FillOpacity", "fillOpacity", "Fill opacity",
                "How solid the fill is, in percent. The background, border and text stay as they are.")
            TimerChoice("FillTexture", "fillTexture", "Fill texture",
                "The texture the fill is drawn with: a flat fill (the default, which shows the colors exactly), RestedXP's own bar texture, EllesmereUI's bar textures while it is installed, and any LibSharedMedia status bar texture. A texture that has gone is drawn as RestedXP's own and stays chosen.",
                TM.FillChoices)
            TimerSwatch("LabelColor", "labelColor", "Label color",
                "The color of the text at the left of the bar: what you are waiting for.")
            TimerChoice("LabelFont", "labelFont", "Label font",
                "The font of the label. By default the same as the guide's step text. A font that has gone is drawn as that and stays chosen.",
                TM.LabelFontChoices)
            TimerChoice("LabelOutline", "labelOutline", "Label outline",
                "An outline round the label. The default keeps light text readable over the fill.",
                TM.OUTLINE_CHOICES)
            TimerSwatch("TimeColor", "timeColor", "Time color",
                "The color of the remaining time at the right of the bar.")
            TimerSlider("LabelSize", "labelSize", "Label size",
                "The size of the label. The bar grows to fit a larger size, so the text is never cut off at the top or bottom. A label too long for the bar is cut short with an ellipsis, never run into the time.")
            TimerSlider("TimeSize", "timeSize", "Time size",
                "The size of the remaining time.")
            TimerChoice("TimeFont", "timeFont", "Time font",
                "The font of the remaining time. By default the same as the label's.", TM.TimeFontChoices)
            TimerChoice("TimeOutline", "timeOutline", "Time outline",
                "An outline round the remaining time. By default the same as the label's.", TM.TIME_OUTLINE_CHOICES)
            TimerToggle("ShowIcon", "showIcon", "Show RestedXP's clock icon",
                "The small pocket watch at the left of each bar. It is only a picture. Off, the bar takes its room.")
            TimerSlider("BarHeight", "barHeight", "Bar height",
                "How tall each bar is, in pixels. RestedXP's own is 16. Taller than the footer's strip, a bar covers the bottom of the list while it runs. RestedXP stacks several bars as it always did, and decides their width, which follows the window's.")
            TimerSlider("TextPadding", "textPadding", "Text padding",
                "The room between the label or the time and the bar's ends, in pixels.")

            Header("Timer bar background and border", "The bar's own background and border. Preview shows two made-up bars beside this window; no timer is started.")

            local timerLook = K.Appearance(TM.Look, "restedxpTimerLook", "bar", "Shows two made-up timer bars beside this window (a short and a long label) in the look set here. They are only a sample: no timer is started, nothing in RestedXP changes, and they go away when this window closes.",
                function() TM.TogglePreview() end, nil, nil, timerSwitch, TimersOn, {
                labels = {
                    BgTexture = "Timer background texture", BgColor = "Timer background color",
                    BgOpacity = "Timer background opacity", BorderTexture = "Timer border texture",
                    BorderSize = "Timer border thickness", BorderColor = "Timer border color",
                    BorderOpacity = "Timer border opacity",
                },
            })
            for _, entry in ipairs(timerLook) do resettableTimers[#resettableTimers + 1] = entry end

            local resetTimers = K.ResetButton("Reset timer bars", resettableTimers, TM.Reset,
                "Puts the timer bars' fill, text, size, background and border back to the defaults, and turns Skin timer bars on. Nothing else changes: not the window's look, RestedXP's settings or its timers.")
            Under(resetTimers, rxpToggle, RxpOn)
        end

        local reset = K.ResetButton("Reset appearance", resettable, RS.Reset,
            "Puts this look's background, border, colors, fonts, sizes, spacing, what shows and the waypoint arrow back to the defaults. Nothing else changes: not the switch, RestedXP's settings, guide progress or positions, or the rest of TwichUI.")
        Under(K.InSection(reset, intro), rxpToggle, RxpOn)
    end,
})
