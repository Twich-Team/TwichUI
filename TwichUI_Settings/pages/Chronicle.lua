-- TwichUI settings: Journey Chronicle (what is recorded automatically, the time format, Welcome Back), and the
-- Chronicle window's appearance (chronicle/Appearance.lua) on a page of its own under it.

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "chronicle", icon = "journeyChronicle", name = "Journey Chronicle", order = 60, group = "journey",
    description = "A quiet, private journal for this character. It isn't shared, sent or backed up with your configuration.",
    keywords = "journal diary notes log history level death boss gold riding profession welcome back bookmark clock time",
    overview = {
        label = "Journey Chronicle", tip = "Your private journal for this character.",
        status = function() return K.OnOff(R:Enabled("chronicle"), "Recording", "Notes only") end,
    },
    build = function()
        local Header, Toggle, Button, Choice, Under = K.Header, K.Toggle, K.Button, K.Choice, K.Under
        local STRING = K.STRING

        Header("Automatic entries", "A quiet, private journal for this character. It isn't shared, sent or backed up with your configuration, and it never tells you what to do next.")
        local chronicle = Toggle("chronicle", "Keep moments for me automatically",
            "On by default. TwichUI adds a short entry to this character's Chronicle for the moments you pick below. It starts the moment it is on and never looks back. You can always write your own notes, whatever this is set to.")
        local function ChronicleOn() return R:Enabled("chronicle") end
        local function ChronicleToggle(key, label, tooltip)
            Under(Toggle(key, label, tooltip), chronicle, ChronicleOn)
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
            "When you log in to a character that has Chronicle entries, a small bookmark shows the last place the Chronicle noted and how long ago, with a link to open it. It fades by itself, doesn't appear after a reload or in combat, and makes no sound or chat line. It only reads your entries; it adds none. Move it in Edit Mode.")
        Choice("chronicleClock", "Time format",
            "How times are shown in your Chronicle.",
            STRING, "12",
            R.Chronicle.Clock, R.Chronicle.SetClock,
            { { "12", "12-hour (3:45 PM)" }, { "24", "24-hour (15:45)" } })
        Button("Journey Chronicle", "Open", function()
            K.CloseOptions()
            if R.ChronicleWindow then R.ChronicleWindow:Show() end
        end, "Opens your Chronicle (same as typing /tui chronicle).")

        -- The window's look has a page of its own, under this one (they are many): a short pointer here.
        if K.pages.chronicleLook then
            Header("Appearance", "How the Chronicle window looks: its background, border, text and accents. Its settings are on a page of their own, under this one.")
            Button("Chronicle appearance", "Open its page", function() R:OpenSettings("chronicleLook") end,
                "Opens the Chronicle appearance page, under this one: background, border, typography, accents and layout. Nothing there changes what is recorded.")
        end
    end,
})

-- Appearance of the Chronicle window (chronicle/Appearance.lua). Not the zone arrival card or the Welcome
-- Back card, and nothing to do with what is recorded.
K.Page({
    key = "chronicleLook", name = "Chronicle appearance", nav = "Appearance", parent = "chronicle", order = 61,
    description = "How the Chronicle window looks. Nothing here changes what is recorded, your entries or notes.",
    keywords = "chronicle look theme background border font color accent texture opacity",
    when = function() return R.ChronicleAppearance ~= nil and R.ChronicleAppearance.Look ~= nil end,
    build = function()
        local Header, Button, Proxy, Under = K.Header, K.Button, K.Proxy, K.Under
        local BOOL, STRING, NUMBER = K.BOOL, K.STRING, K.NUMBER
        local CA = R.ChronicleAppearance
        local Fonts = R.MenuStyle and R.MenuStyle.Fonts
        local resettable = {}
        local intro = Header("The Chronicle window", "How the Chronicle window looks: its background, border, text and accents. It changes nothing about what is recorded, your entries or notes, and not the zone arrival or Welcome Back cards. Changes show at once in the window if it is open; the defaults are the look it has always had.")
        Button("Chronicle window", "Show or hide", function()
            if R.ChronicleWindow then R.ChronicleWindow:Toggle() end
        end, "Shows your real Chronicle beside these settings so you can watch each change as you make it. It opens beside these settings; drag it by its title to move it aside. It only reads your entries. (The Open button on the Journey Chronicle page closes the settings first.)")

        local rowsBy = {}
        local function Decorate(suffix, initializer)
            rowsBy[suffix] = initializer
            if suffix == "BgTiling" or suffix == "BgTileSize" then
                initializer:AddShownPredicate(function() return CA.BackgroundIsImage() end)
            elseif suffix == "BgInset" then
                initializer:AddShownPredicate(function() return CA.Look.Get("bgTexture") ~= "none" end)
            elseif suffix == "BorderSize" then
                Under(initializer, rowsBy.BorderTexture, CA.BorderHasWidth, function()
                    if CA.Look.Get("borderTexture") == "none" then return "Greyed out: no border is drawn." end
                    return "Greyed out: the Chronicle ledger border has a fixed width. Pick another border to set a thickness."
                end)
            elseif suffix == "BorderColor" or suffix == "BorderOpacity" then
                Under(initializer, rowsBy.BorderTexture, CA.BorderIsShown, "Greyed out: no border is drawn.")
            end
        end
        local function Merge(list) for _, entry in ipairs(list) do resettable[#resettable + 1] = entry end end

        local function Setting(variable, varType, label, key)
            local setting = Proxy("chronicle" .. variable, varType, label, CA.DEFAULTS[key],
                function() return CA.Get(key) end, function(value) CA.Set(key, value) end)
            if setting then resettable[#resettable + 1] = { setting = setting, default = CA.DEFAULTS[key] } end
            return setting
        end
        local function Swatch(variable, key, label, tooltip)
            return K.Swatch(Setting(variable, STRING, label, key), tooltip)
        end
        local function Pick(variable, key, label, tooltip, choices)
            return K.Dropdown(Setting(variable, STRING, label, key), function() return choices(CA.Get(key)) end, tooltip)
        end
        local function Check(variable, key, label, tooltip)
            return K.Checkbox(Setting(variable, BOOL, label, key), tooltip)
        end
        local function Slide(variable, key, label, tooltip)
            local limit = CA.LIMITS[key]
            local setting = Setting(variable, NUMBER, label, key)
            if not limit then return end
            return K.Slider(setting, limit[1], limit[2], tooltip)
        end
        local function FontChoices(first)
            return function(current)
                return Fonts and Fonts.Choices(current, first) or first
            end
        end

        Header("Background", "The window's fill. A plain color is the default; textures come from the game, from EllesmereUI (while it is installed) and from any LibSharedMedia pack. The header band and the list behind the entries fade with it, so a faint window is faint all through. Text, icons, buttons and the border keep their own strength.")
        Merge(K.Appearance(CA.Look, "chronicleLook", "window", nil, nil, nil, nil, nil, nil, {
            order = { "BgTexture", "BgColor", "BgOpacity", "BgTiling", "BgTileSize", "BgInset" },
            labels = { BgTexture = "Background texture", BgColor = "Background color", BgOpacity = "Background opacity" },
            decorate = Decorate,
        }))
        Slide("WindowOpacity", "windowOpacity", "Overall window opacity",
            "Fades the whole window, text and border included, in percent. It multiplies the background, border and text strengths rather than replacing them, so 50 here with a 50 background is a quarter. 100 is the default; it cannot go below 40 so the window can always be found.")

        Header("Border", "The window's edge. The Chronicle ledger is the default: a bronze rim with a lit inner edge, tinted by the color below. Any other choice replaces it with a single border of the thickness you set. The window grows to give a border and the content padding room; its place and your entries do not move.")
        Merge(K.Appearance(CA.Look, "chronicleLook", "window", nil, nil, nil, nil, nil, nil, {
            order = { "BorderTexture", "BorderColor", "BorderOpacity", "BorderSize" },
            labels = { BorderTexture = "Border style", BorderColor = "Border color", BorderOpacity = "Border opacity", BorderSize = "Border thickness" },
            decorate = Decorate,
        }))
        Slide("Padding", "padding", "Content padding",
            "Extra space between the border and the content, in pixels. The window grows by twice this; its place doesn't change. This is separate from the border's own thickness.")

        Header("Typography", "The Chronicle's text. Title, headline, note and date text are separate colors; fonts come from LibSharedMedia, so TwichUI's, EllesmereUI's and any other addon's fonts are listed. Sizes follow the game's own until you set them. Meaningful colors (the red Delete link, warnings, unavailable controls) are kept.")
        Pick("Font", "font", "Text font",
            "The font for dates, notes, labels and button text. The game's own is the default. A font that has gone is drawn as the game's own and stays chosen.",
            FontChoices({ { "default", "Game font (default)" } }))
        Pick("HeadingFont", "headingFont", "Title and headline font",
            "The font for the window's title and each entry's headline. \"Same as text\" follows the text font.",
            FontChoices({ { "inherit", "Same as text font" }, { "default", "Game font" } }))
        Swatch("TitleColor", "titleColor", "Title color", "The color of the window's title.")
        Swatch("HeadingColor", "headingColor", "Headline color", "The color of each entry's headline, and of text under the pointer on controls.")
        Swatch("BodyColor", "bodyColor", "Note color", "The color of the note text under an entry's headline, and of resting button labels.")
        Swatch("MetaColor", "metaColor", "Date and detail color", "The color of dates, places, counts and hints, and of disabled controls.")
        Slide("TextOpacity", "textOpacity", "Text opacity",
            "How solid the text is, in percent. Only text fades; the background, border and icons are not affected. It cannot go below 30 so the window stays readable.")
        local sizes = Check("CustomSizes", "customSizes", "Set text sizes here",
            "Off: sizes are the game's own (title 16, headlines 12, notes and dates 10). On: the four sizes below are used. Rows, the header and the list grow to fit; buttons and the date picker keep their size.")
        local function SizesOn() return CA.Get("customSizes") end
        local function SizesWhy() return "Greyed out: needs \"Set text sizes here\" turned on." end
        for _, def in ipairs({
            { "TitleSize", "titleSize", "Title size", "The window's title." },
            { "HeadingSize", "headingSize", "Headline size", "Each entry's headline." },
            { "BodySize", "bodySize", "Note size", "The note text under a headline, and the text you type in the editor." },
            { "MetaSize", "metaSize", "Date and detail size", "Dates, places, counts and hints." },
        }) do
            local row = Slide(def[1], def[2], def[3], def[4] .. " In points.")
            if row and sizes then Under(row, sizes, SizesOn, SizesWhy) end
        end
        Slide("LineSpacing", "lineSpacing", "Line spacing",
            "Extra pixels between the lines of text that wraps. Rows grow to fit. 0 is the game's own.")
        Pick("Outline", "outline", "Text outline", "An outline round all of the Chronicle's text.",
            function() return CA.OUTLINE_CHOICES end)

        Header("Controls and accents", "The color that picks things out, and the small surfaces around the entries.")
        Swatch("AccentColor", "accentColor", "Accent color",
            "The warm gold used for the Write a note button, the Edit link, a note's frame, the date picker's marks, the scroll bar's arrows and the rim's lit edge.")
        Swatch("HeaderColor", "headerColor", "Header band color", "The band behind the title.")
        Swatch("ListColor", "listColor", "Entry list color", "The recessed area behind the entries.")
        Slide("HoverOpacity", "hoverOpacity", "Entry highlight",
            "How strongly an entry is tinted with the accent color while the pointer is on it. 0 for none.")
        Check("ShowDividers", "showDividers", "Show dividers",
            "The thin lines between entries and under the title band.")
        Check("Worn", "worn", "Worn surface",
            "A faint speckle and a soft shade toward the bottom, so the window reads as worn material rather than flat color. Off for a plain surface.")
        Pick("ButtonStyle", "buttonStyle", "Main button",
            "Filled: the Write a note and Save buttons are filled with a dark tone of the accent. Outline: they are drawn like the others, with an accent border and text.",
            function() return CA.BUTTON_CHOICES end)
        Swatch("ScrollThumbColor", "scrollThumbColor", "Scroll bar thumb", "The color of the scroll bar's moving part.")
        Swatch("ScrollTrackColor", "scrollTrackColor", "Scroll bar track", "The color of the scroll bar's groove, drawn faintly.")
        Swatch("DividerColor", "dividerColor", "Divider color", "The color of the lines between entries and under the title band.")

        K.InSection(K.ResetButton("Reset Chronicle appearance", resettable, CA.Reset,
            "Puts the Chronicle window's background, border, text, accents and layout back to the defaults. Nothing else changes: your entries and notes, the date filter, the time format, what is recorded, sounds and the cards are left as they are."), intro)
    end,
})
