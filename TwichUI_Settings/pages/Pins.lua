-- TwichUI settings: Party pins (pins/). The switch, how pins are placed and labelled, the data bar entry and the
-- arrival sound; and, on a page of its own under it, the look of the pin window, its menu, the new pin window and
-- pin names on the maps. The pins themselves are managed in the pin window, not here; nothing on these pages
-- reads or writes them.

local R = TwichUI
local K = R.SettingsKit

local pinsToggle   -- the Party pins switch (the Party pins page), which the look is greyed out under

K.Page({
    key = "pins", name = "Party pins", order = 70, group = "journey",
    description = "Named pins on your world map: local pins only you see, and party pins shared with party members who have TwichUI.",
    keywords = "map pin waypoint way tomtom marker minimap party share coordinates",
    when = function() return R.Pins ~= nil end,
    overview = {
        label = "Party pins", tip = "Named pins on your world map, and pins shared with party members who have TwichUI.",
        status = function() return K.OnOff(R:Enabled("partyPins")) end,
    },
    build = function()
        local PL = R.PinsLook
        if not PL then return end
        local Header, Toggle, Button, Choice, Proxy, ProxyToggle, Under = K.Header, K.Toggle, K.Button, K.Choice, K.Proxy, K.ProxyToggle, K.Under
        local STRING, NUMBER, BOOL = K.STRING, K.NUMBER, K.BOOL

        Header("Party pins", "Named pins on your world map: local pins only you see, kept between sessions, and party pins shared with party members who have TwichUI, for as long as you are in that party. Players without TwichUI see nothing. Nothing is written in chat. Off until you turn it on.")
        local function PinsOn() return R:Enabled("partyPins") end
        pinsToggle = Toggle("partyPins", "Party pins",
            "Turns on map pins: place them with the map clicks below or Place a pin in the pin window, see your party's, and manage them all in one window (/tui pins).\n\nOff: TwichUI's pins leave the map, party pins you received are dropped and nothing is sent or taken in. Your local pins are kept for when you turn it on again.")
        Under(Button("Your pins", "Open", function()
            K.CloseOptions()
            if R.PinsWindow then R.PinsWindow.Show() end
        end, "Opens the pin window (same as /tui pins): every pin with its place and who made it, search, filters, and what you can do with each."), pinsToggle, PinsOn)

        Header("Waypoint commands", "/twichway 52.3 40.7 Name makes a local pin on your map. Put a zone name or #mapID before the numbers for another map, or use /twichway paste for several lines. /way does the same when no other addon has it.")
        Under(ProxyToggle("pinsWayAlso", "Also make a pin from /way",
            "Off by default. When another addon such as WaypointUI or TomTom has /way, TwichUI lets it handle the command as usual and then also makes a pin from the same text. You get both: that addon's waypoint and a TwichUI pin. Text that isn't a waypoint (reset, paste, list) makes no pin. Nothing of the other addon is replaced; /twichway works either way.",
            PL.PREF_DEFAULTS.wayAlso, function() return PL.Pref("wayAlso") end, function(value) PL.SetPref("wayAlso", value and true or false) end),
            pinsToggle, PinsOn)

        Header("Placing and showing", "Ctrl-click stays the game's own waypoint and Shift-click is left for other map addons. Only the exact click chosen here places a pin; every other click works on the map as before.")
        local function ClickChoices()
            local out = {}
            for _, c in ipairs(PL.CLICKS) do out[#out + 1] = { c[1], c[2] } end
            return out
        end
        local clickSettings = {}
        local function ClickChoice(key, variable, label, tooltip)
            local other = key == "localClick" and "partyClick" or "localClick"
            local row = Choice(variable, label, tooltip, STRING, PL.PREF_DEFAULTS[key],
                function() return PL.Pref(key) end,
                function(value)
                    local before = PL.Pref(other)
                    PL.SetPref(key, value)
                    -- picking the other's click swapped them: show the other's new value too
                    local swapped = clickSettings[other]
                    if PL.Pref(other) ~= before and swapped and swapped.SetValue then pcall(swapped.SetValue, swapped, PL.Pref(other)) end
                end, ClickChoices)
            if row and row.GetSetting then clickSettings[key] = row:GetSetting() end
            Under(row, pinsToggle, PinsOn)
        end
        ClickChoice("localClick", "pinsLocalClick", "Map click for a local pin",
            "The click on the world map that places a local pin, which only you see. It opens a small editor first, for its name and color. Picking the click a party pin uses swaps the two.")
        ClickChoice("partyClick", "pinsPartyClick", "Map click for a party pin",
            "The click that places a party pin. It opens the editor first and is sent to your party only when you press Save; Cancel sends nothing. Picking the click a local pin uses swaps the two.")
        Under(Choice("pinsLabels", "Pin names on the map",
            "Pin names under the pins on the world map. On hover keeps a busy map clear: a name shows when the pointer is on its pin, and for the pin selected in the pin window or by a click. Pin names are always in the tooltip.",
            STRING, PL.PREF_DEFAULTS.labels, function() return PL.Pref("labels") end, function(value) PL.SetPref("labels", value) end,
            PL.LABELS), pinsToggle, PinsOn)
        Under(ProxyToggle("pinsMinimap", "Show pins on the minimap",
            "Shows pins that are within range of you on your minimap, in their color and, for a party pin, with its badge. A pin appears only while you are on the map it was placed on (or a map inside it), and only when it is close enough to be on the minimap: nothing points at a pin that is out of range. Names are in the tooltip, and right-click opens the same actions as on the world map. Pins you removed from your map aren't shown.",
            PL.PREF_DEFAULTS.minimap, function() return PL.Pref("minimap") end, function(value) PL.SetPref("minimap", value and true or false) end),
            pinsToggle, PinsOn)
        Under(Choice("pinsMinimapLabels", "Pin names on the minimap",
            "Pin names beside the pins on the minimap. Never leaves the minimap as it is (names are in the tooltip). On hover shows a name when the pointer is on its pin, and for the pin selected in the pin window. Always can crowd a small minimap. Only applies while Show pins on the minimap is on.",
            STRING, PL.PREF_DEFAULTS.minimapLabels, function() return PL.Pref("minimapLabels") end,
            function(value) PL.SetPref("minimapLabels", value) end, PL.MINIMAP_LABELS), pinsToggle, PinsOn)

        local BR = PL.Bar
        Header("Data bar", "\"TwichUI Party Pins\" in a data bar addon that shows LibDataBroker plugins (for example EllesmereUI's Broker Plugin block). Click it for a small menu of your pins, right-click for these options. It is listed once Party pins is on, with no reload. What it says, its icon and its color are yours; the data bar addon still sets its font and size.")
        K.DataBarNote(Under(Choice("pinsBarText", "Text on the data bar",
            "The words beside the entry's icon: how many pins are on your map (\"5 pins, 2 party\"), just the number, \"Map Pins\", or nothing. With none, the icon stays so there is still something to click. Turned off, it reads \"Off\" until you reload.",
            STRING, BR.DEFAULTS.text, function() return BR.Get("text") end, function(value) BR.Set("text", value) end, BR.TEXTS),
            pinsToggle, PinsOn))
        Under(ProxyToggle("pinsBarIcon", "Show the icon on the data bar",
            "The small map icon beside the text. Off leaves just the text. It always shows while the text is set to None, so the entry is never empty.",
            BR.DEFAULTS.icon, function() return BR.Get("icon") end, function(value) BR.Set("icon", value and true or false) end),
            pinsToggle, PinsOn)
        local barColor = Under(ProxyToggle("pinsBarCustomColor", "Use my own text color",
            "Draws the entry's text in the color below. Off leaves it in the data bar's own text color.\n\nSome data bars remove color codes from plugin text so that their own text color applies. EllesmereUI's Broker Plugin block does that until you turn off its Strip Colors option for this block.",
            BR.DEFAULTS.customColor, function() return BR.Get("customColor") end, function(value) BR.Set("customColor", value and true or false) end),
            pinsToggle, PinsOn)
        local barColorSetting = Proxy("pinsBarColor", STRING, "Data bar text color", BR.DEFAULTS.color,
            function() return BR.Get("color") end, function(value) BR.Set("color", value) end)
        Under(K.Swatch(barColorSetting, "The color of the data bar entry's text. The icon keeps its own colors."),
            barColor, function() return PinsOn() and BR.Get("customColor") end)

        local flashToggle = Under(ProxyToggle("pinsBarFlash", "Point out a new pin on the data bar",
            "When a pin arrives from someone in your party, the entry's text changes to \"New pin: <name>\" in the color below, for the time below, and then goes back to what it was. Pins you place, and ones you already had, don't trigger it. Several arriving within the time are counted together.\n\nNothing is written in chat. The sound is set separately, below.",
            BR.DEFAULTS.flash, function() return BR.Get("flash") end, function(value) BR.Set("flash", value and true or false) end),
            pinsToggle, PinsOn)
        local function FlashOn() return PinsOn() and BR.Get("flash") end
        local flashSeconds = Proxy("pinsBarFlashSeconds", NUMBER, "New pin shown for (seconds)", BR.DEFAULTS.flashSeconds,
            function() return BR.Get("flashSeconds") end, function(value) BR.Set("flashSeconds", value) end)
        Under(K.Slider(flashSeconds, BR.LIMITS.flashSeconds[1], BR.LIMITS.flashSeconds[2],
            "How long the text stays changed after a pin arrives, in seconds. Another pin arriving restarts the time."), flashToggle, FlashOn)
        local flashColor = Proxy("pinsBarFlashColor", STRING, "New pin color", BR.DEFAULTS.flashColor,
            function() return BR.Get("flashColor") end, function(value) BR.Set("flashColor", value) end)
        Under(K.Swatch(flashColor, "The color of the text while a new pin is pointed out, whatever the text color above. The icon is tinted the same, for a data bar that removes color codes from text (EllesmereUI's Broker Plugin block does, until its Strip Colors option is off for this block; its icon tint is honored)."), flashToggle, FlashOn)

        do
            local SD = PL.Sound
            Header("Sound", "A short sound when a pin arrives from someone in your party, so you notice it without looking at the map. Pins you place yourself make no sound, and nothing is written in chat.")
            local soundToggle = Under(ProxyToggle("pinsSound", "Play a sound when a party pin arrives",
                "Plays the sound below once when a pin arrives from another player. Pins you place, updates to pins you already have, and ones you already held don't play it, and several arriving within a couple of seconds give one sound. Off: pins arrive silently.",
                SD.DEFAULTS.enabled, function() return SD.Get("enabled") end, function(value) SD.Set("enabled", value and true or false) end),
                pinsToggle, PinsOn)
            local function SoundOn() return PinsOn() and SD.Get("enabled") end
            local soundFile = Proxy("pinsSoundFile", STRING, "Sound", SD.DEFAULTS.sound,
                function() return SD.Get("sound") end, function(value) SD.Set("sound", value) end)
            Under(K.Dropdown(soundFile, function() return R.PinsSound and R.PinsSound.Choices(SD.Get("sound")) or {} end,
                "The sound to play. TwichUI's own are listed first, then every sound other addons have added to LibSharedMedia. Press Hear the sound to try it. A sound that has gone (its addon isn't loaded) stays chosen, and TwichUI Map Pin plays in its place."),
                soundToggle, SoundOn)
            local soundChannels = {}
            for i, ch in ipairs(SD.CHANNELS) do soundChannels[i] = { ch[1], ch[2], ch[3] } end
            Under(Choice("pinsSoundChannel", "Volume follows",
                "A sound file can't have a volume of its own, so the sound is as loud as the game volume you choose here. Set that volume in the game's Audio options: lower it to make the sound quieter, or pick the one you keep lowest.",
                STRING, SD.DEFAULTS.channel, function() return SD.Get("channel") end, function(value) SD.Set("channel", value) end,
                soundChannels), soundToggle, SoundOn)
            Under(Button("Hear the sound", "Play", function() if R.PinsSound then R.PinsSound.Play() end end,
                "Plays the sound now, at the volume you have chosen."), soundToggle, SoundOn)
        end

        -- The look of the pin window, its menu, the new pin window and pin names: a page of its own, under this one.
        if K.pages.pinsLook then
            Header("Appearance", "How the pin window, the data bar menu, the new pin window and pin names on the maps look. Their settings are on a page of their own, under this one.")
            Under(Button("Pin appearance", "Open its page", function() R:OpenSettings("pinsLook") end,
                "Opens the Pin appearance page, under this one: the pin window, its data bar menu, the new pin window and pin names on the maps. Nothing there changes your pins."),
                pinsToggle, PinsOn)
        end
    end,
})

K.Page({
    key = "pinsLook", name = "Pin appearance", nav = "Appearance", parent = "pins", order = 71,
    description = "How the pin window, its data bar menu, the new pin window and pin names on the maps look. Nothing here changes your pins.",
    keywords = "pins look theme font size outline shadow window menu editor",
    when = function() return R.Pins ~= nil and R.PinsLook ~= nil end,
    build = function()
        local PL = R.PinsLook
        local Header, Proxy, Under = K.Header, K.Proxy, K.Under
        local STRING, NUMBER, BOOL = K.STRING, K.NUMBER, K.BOOL
        local function PinsOn() return R:Enabled("partyPins") end

        Header("Data bar menu appearance", "How the menu a click on the data bar entry opens looks: background and border. Only the menu's look changes; its text follows the pin window's font and size, and what it does doesn't change. It starts out looking like the Mage launchers' menus, and changing one doesn't change the other.")
        K.Appearance(PL.MenuLook, "pinsMenu", "menu",
            "Opens the real pin menu beside this window to see these settings as you change them. It stays until you press this again or Esc. Its buttons work, so it is your actual pins.",
            function() if R.PinsBrokerMenu then R.PinsBrokerMenu.TogglePreview() end end,
            "Pin menu appearance", "Puts the background and border of the data bar menu back to their defaults. Nothing else is changed.",
            pinsToggle, PinsOn)

        local MT = PL.MapText
        local function FontChoices(current)
            local Fonts = R.MenuStyle and R.MenuStyle.Fonts
            local first = { { "default", "Game font (default)" } }
            return Fonts and Fonts.Choices(current, first) or first
        end
        Header("Map text", "How pin names look on the world map and the minimap: one look for both. Only the names change; pins, clicks and the pin window don't. There is no sample: open your world map or minimap with a pin on it to see each change.")
        local mapReset = {}
        local function MapRemember(variable, varType, label, key)
            local setting = Proxy(variable, varType, label, MT.DEFAULTS[key], function() return MT.Get(key) end, function(value) MT.Set(key, value) end)
            if setting then mapReset[#mapReset + 1] = { setting = setting, default = MT.DEFAULTS[key] } end
            return setting
        end
        Under(K.Dropdown(MapRemember("pinsMapFont", STRING, "Name font", "font"), function() return FontChoices(MT.Get("font")) end,
            "The font for pin names on the maps. A font that has gone (its media pack is not loaded) is drawn as the game's own and stays chosen."), pinsToggle, PinsOn)
        Under(K.Slider(MapRemember("pinsMapSize", NUMBER, "Name size", "size"), MT.LIMITS.size[1], MT.LIMITS.size[2],
            "The size of pin names on the maps, in points. A name has more room as it grows, and a long one is shortened with ... when it still doesn't fit."), pinsToggle, PinsOn)
        Under(K.Swatch(MapRemember("pinsMapColor", STRING, "Name color", "color"),
            "The color of pin names on the maps. A pin's own color tints the pin, not its name."), pinsToggle, PinsOn)
        Under(K.Dropdown(MapRemember("pinsMapOutline", STRING, "Name outline", "outline"), function() return MT.OUTLINES end,
            "A dark edge round each letter, which keeps a name readable over a busy map. It works with or without the shadow."), pinsToggle, PinsOn)
        Under(K.Checkbox(MapRemember("pinsMapShadow", BOOL, "Name shadow", "shadow"),
            "A soft dark shadow one pixel below and right of each letter. On by default, as the game draws it."), pinsToggle, PinsOn)
        Under(K.ResetButton("Reset map text", mapReset, MT.Reset,
            "Puts pin names on the maps back to the game font, size 10, white, no outline and the shadow on. Your pins, the map clicks, the label choices and the pin window's look are not touched."), pinsToggle, PinsOn)

        Header("Window appearance", "How the pin window looks: background, border, text and accent. Only the window changes; your pins, the clicks and the map pins don't. It looks complete without EllesmereUI; EllesmereUI's and LibSharedMedia's textures and fonts are listed when they are there. There is no sample: open the pin window (/tui pins) to see each change.")
        local pinsReset = K.Appearance(PL.Look, "pinsLook", "window", nil, nil, nil, nil, pinsToggle, PinsOn)
        local function Remember(variable, varType, label, key)
            local setting = Proxy(variable, varType, label, PL.DEFAULTS[key], function() return PL.Get(key) end, function(value) PL.Set(key, value) end)
            if setting then pinsReset[#pinsReset + 1] = { setting = setting, default = PL.DEFAULTS[key] } end
            return setting
        end
        Under(K.Dropdown(Remember("pinsFont", STRING, "Text font", "font"), function() return FontChoices(PL.Get("font")) end,
            "The font for the pin window's text. A font that has gone (its media pack is not loaded) is drawn as the game's own and stays chosen."), pinsToggle, PinsOn)
        Under(K.Slider(Remember("pinsTextSize", NUMBER, "Text size", "textSize"), PL.LIMITS.textSize[1], PL.LIMITS.textSize[2],
            "The size of pin names, in points. Places, counts and hints are drawn two points smaller."), pinsToggle, PinsOn)
        Under(K.Swatch(Remember("pinsAccent", STRING, "Accent color", "accentColor"),
            "The color of the Place a pin button, the selected row and the scroll bar's arrows. Pin colors are each pin's own."), pinsToggle, PinsOn)
        Under(K.Dropdown(Remember("pinsDensity", STRING, "Rows", "density"), function() return PL.DENSITY end,
            "Comfortable shows each pin's map and coordinates under its name. Compact is one line per pin (the place is in the pin's tooltip on the map)."), pinsToggle, PinsOn)
        Under(K.ResetButton("Reset window appearance", pinsReset, PL.Reset,
            "Puts the pin window's background, border, font, text size, accent and rows back to the defaults. Your pins, the map clicks and the label choice are not touched."), pinsToggle, PinsOn)

        Header("New pin window appearance", "How the window that opens when you place a pin (and when you rename or recolor one) looks: background and border. Only that window's look changes; its text follows the pin window's font, size and accent, and what it does doesn't change. It starts out like the pin window, and changing one doesn't change the other.")
        K.Appearance(PL.EditorLook, "pinsEditor", "window",
            "Opens the real new pin window, with a made-up pin, beside this window to see these settings as you change them. Its Save does nothing. It stays until you press this again or Esc.",
            function() if R.PinsEditor then R.PinsEditor.TogglePreview() end end,
            "New pin window appearance", "Puts the background and border of the new pin window back to their defaults. Nothing else is changed.",
            pinsToggle, PinsOn)
    end,
})
