-- TwichUI settings: ammunition warning (ammo/). Two pages: General (the switch, when to show, the text and
-- icon, the optional background and border, the place, the preview, the optional sound) and Custom ammunition (the
-- items you registered; Ammo.lua's sibling AmmoItems.lua draws that list). The warning is decided and drawn, and every
-- value is checked and saved, by the core addon's ammo/ files; this file only describes rows that call their Get/Set.
-- Nothing here is needed for the warning to work. It never equips, moves, buys or uses anything.

local R = TwichUI
local K = R.SettingsKit

local function AM() return R.Ammo end
local function On() return R:Enabled("ammoWarning") end

K.Page({
    key = "ammo", name = "Ammunition warning", nav = "Ammunition warning", order = 52, group = "class",
    description = "A line of text near the middle of the screen when the ammunition for your equipped ranged weapon is missing, out or the wrong kind. Off until you turn it on.",
    keywords = "display style rpg notification standard hunter warrior ammo ammunition arrows bullets quiver ranged bow gun crossbow warning alert out of ammo no ammo wrong ammo sound position move preview",
    overview = {
        label = "Ammunition warning", tip = "A warning near the middle of the screen when the ammunition for your equipped ranged weapon is missing, out or the wrong kind.",
        when = function() return R.Ammo ~= nil end,
        status = function() return K.OnOff(R:Enabled("ammoWarning")) end,
    },
    when = function() return R.Ammo ~= nil end,
    build = function()
        local MS = R.MenuStyle
        local Header, Toggle, Button, Under = K.Header, K.Toggle, K.Button, K.Under
        local BOOL, STRING, NUMBER = K.BOOL, K.STRING, K.NUMBER
        local am = AM()

        Header("Ammunition warning", "Shows one line of text near the middle of the screen while an equipped ranged weapon that takes ammunition has none you can use. It only reads what is equipped and carried, never equips or moves anything, says nothing in chat and does nothing until you turn it on.")
        local main = Toggle("ammoWarning", "Warn when my ammunition is missing, out or wrong",
            "When your equipped ranged weapon takes ammunition (the game says whether it does, whatever your class), shows NO AMMO EQUIPPED when none is selected but you carry some that fits, OUT OF AMMO when none is selected and none that fits is carried (or the selected stack is empty), and WRONG AMMO EQUIPPED when arrows are selected for a gun or bullets for a bow. It stays quiet when the weapon takes no ammunition, when you have no ranged weapon, and while the game has not yet told it enough to be sure.\n\nThe bank, mail and the auction house are never counted. Turn it off to remove it completely: nothing listens for the game's events and nothing is drawn. With a weapon that takes no ammunition equipped, only the change of weapon is noticed.")
        Under(K.Status("On this character",
            function()
                if not On() then return "Off" end
                local s = R.AmmoWarning.Snapshot()
                if not s.running then return "Waiting for the game world" end
                if s.shown then return R.AmmoState.MESSAGES[s.shown] end
                if s.state == "ok" then return "Ammunition is fine" end
                if s.state == "inactive" then return "No ranged weapon that takes ammunition" end
                return "Checking"
            end,
            function()
                return "What it concluded the last time it looked."
            end,
            "Whether the warning applies to the character you are playing, and what it last found. Read when this page is drawn; it is not polled.",
            function()
                local s = On() and R.AmmoWarning.Snapshot()
                if s and s.shown then return "warn" end
                return On() and "ok" or "quiet"
            end), main, On)

        Header("When to show", "Showing it out of combat lets you fix the problem before you pull. It never shows for a weapon that takes no ammunition.")
        local resettable = {}
        local function Shared(variable, key, varType, label, set)
            local setting = K.Proxy("ammo" .. variable, varType, label, am.DEFAULTS[key],
                function() return am.Get(key) end, set or function(value) am.Set(key, value) end)
            if setting then resettable[#resettable + 1] = { setting = setting, default = am.DEFAULTS[key] } end
            return setting
        end
        Under(K.Dropdown(Shared("Show", "show", STRING, "Show the warning"), function() return am.CHOICES.show end,
            "Whenever my ranged weapon needs ammunition shows it as soon as a problem is found, in or out of combat. Only in combat keeps it hidden until you are in combat; if your ammunition runs out mid-fight it appears then."), main, On)

        Header("Text and icon", "The words are fixed: NO AMMO EQUIPPED, OUT OF AMMO and WRONG AMMO EQUIPPED. How they look is yours.")
        Under(K.Dropdown(Shared("Style", "style", STRING, "Display style"), function() return am.CHOICES.style end,
            "Standard is the warning as one line of text. RPG Notification draws it like the zone arrival card: a small heading, a bronze rule, the warning in the card's type and a short line beneath. It settles in once when a problem begins, fades once when it is fixed and stays up for as long as the problem does. Both show the same warnings under the same rules, and each keeps its own settings when you switch. Use Show under Place and preview to see the one you chose."), main, On)
        Under(K.Checkbox(Shared("Icon", "icon", BOOL, "Show an ammunition icon (Standard)", function(v) am.Set("icon", v and true or false) end),
            "Standard style only. Shows the icon of the ammunition beside the words, when there is one to show: what is selected, or what you carry that fits, or what you last had selected."), main, On)
        Under(K.Dropdown(Shared("Font", "font", STRING, "Font"),
            function() return MS.Fonts.Choices(am.Get("font"), { { "default", "Game font (default)" } }) end,
            "The warning text's typeface. In RPG Notification, Game font means the zone arrival card's own typeface. Fonts come from LibSharedMedia, so TwichUI's, EllesmereUI's and any other addon's are listed. A font that has gone is drawn with the game's own and stays chosen."), main, On)
        local size = am.LIMITS.fontSize
        Under(K.Slider(Shared("FontSize", "fontSize", NUMBER, "Text size", function(v) am.Set("fontSize", math.floor(v + 0.5)) end),
            size[1], size[2], "The size in pixels of the warning text. In RPG Notification this is the main line; the heading and the line beneath are drawn smaller so the hierarchy stays."), main, On)
        Under(K.Dropdown(Shared("FontOutline", "fontOutline", STRING, "Text outline"), function() return am.CHOICES.fontOutline end,
            "Outline and Thick outline draw a line round each letter, which keeps the words readable over any background. Shadow is a soft dark edge. None leaves the text bare."), main, On)
        Under(K.Swatch(Shared("TextColor", "textColor", STRING, "Text color"), "The color of the warning text."), main, On)
        local scale = am.LIMITS.scale
        Under(K.Slider(Shared("Scale", "scale", NUMBER, "Scale", function(v) am.Set("scale", math.floor(v + 0.5)) end),
            scale[1], scale[2], "Makes the whole warning bigger or smaller, in percent."), main, On)
        local opacity = am.LIMITS.opacity
        Under(K.Slider(Shared("Opacity", "opacity", NUMBER, "Opacity", function(v) am.Set("opacity", math.floor(v + 0.5)) end),
            opacity[1], opacity[2], "How solid the warning is as a whole, in percent: its text, icon, background and border together."), main, On)

        Header("Background and border", "Standard style only; RPG Notification draws its own rule instead. Nothing is drawn behind the words until you choose a background or a border, so the warning does not cover the world. Both can be switched on here, either alone.")
        K.Appearance(am.Look, "ammoLook", "warning", "Shows a sample of the warning drawn with this look. The sample is not a real warning and plays no sound.",
            function()
                local W = R.AmmoWarning
                if W.PreviewActive() then W.PreviewStop() elseif not W.PreviewStart() then R.Print("the preview waits until you are out of combat.") end
                K.RefreshOverview()
            end, "Reset the background and border", "Puts the warning's background and border back to the default, which is none. The warning's other settings and its place are kept.", main, On, {
                labels = { BgTexture = "Warning background texture", BgColor = "Warning background color", BgOpacity = "Warning background opacity",
                    BorderTexture = "Warning border texture", BorderSize = "Warning border thickness", BorderColor = "Warning border color",
                    BorderOpacity = "Warning border opacity" } })

        Header("Place and preview", "The warning takes no clicks, so it never gets in the way of the world. Only while you have it unlocked does a handle over it take the mouse.")
        local previewRow = Under(Button("Preview",
            function() return R.AmmoWarning.PreviewActive() and "Hide" or "Show" end,
            function()
                local W = R.AmmoWarning
                if W.PreviewActive() then W.PreviewStop()
                elseif not W.PreviewStart() then R.Print("the preview waits until you are out of combat.") end
                K.RefreshOverview()
            end,
            "Shows a sample of the warning, for any class, so you can judge a change without running out of ammunition. It is the real warning's frame with a made-up message, plays no sound and changes nothing about your equipment. It ends when you close these settings, enter combat or turn the warning off."), main, On)
        Under(Button("Sample message",
            function() local m = R.AmmoWarning.PreviewMessage() return m or "Next" end,
            function() R.AmmoWarning.PreviewNext() end,
            "Shows the next of the three messages in the preview, so each can be judged for width and color."), previewRow,
            function() return On() and R.AmmoWarning.PreviewActive() end, "Greyed out: show the preview first.")
        Under(Button("Move the warning",
            function() return R.AmmoWarning.PositioningActive() and "Lock" or "Unlock" end,
            function()
                local W = R.AmmoWarning
                if W.PositioningActive() then W.PositionEnd()
                elseif not W.PositionStart() then R.Print("the warning can be moved when you are out of combat.") end
                K.RefreshOverview()
            end,
            "Unlock shows a sample with a highlighted handle over it. Drag the handle to move the warning; right-click it, or press Lock, when you are done. Unlocking ends by itself if you enter combat. The place is kept on your screen even if your screen size changes, and is not shared."), main, On)
        Under(Button("Reset position", "Reset", function() R.AmmoWarning.ResetPosition() end,
            "Puts the warning back at its default place, a little above the middle of the screen. Only the place changes."), main, On)

        Header("Sound", "Off by default. The sound plays once when a problem begins while you can see the warning, never over and over, and never at login or when you turn the warning on.")
        local soundRow = Under(K.Checkbox(Shared("Sound", "sound", BOOL, "Play a sound when a problem begins", function(v) am.Set("sound", v and true or false) end),
            "Plays the chosen sound once when ammunition goes missing, runs out or is wrong while the warning is visible. At least five seconds pass between two sounds, so swapping stacks or a burst of bag changes does not repeat it. The preview never plays it."), main, On)
        local function SoundOn() return On() and am.Get("sound") end
        local soundWhy = "Greyed out: turn the sound on first."
        Under(K.Dropdown(Shared("SoundName", "soundName", STRING, "Sound"),
            function() return R:SoundChoices(am.Get("soundName")) end,
            "TwichUI's own sounds, then every sound LibSharedMedia lists. A sound that has gone plays the default instead and stays chosen."), soundRow, SoundOn, soundWhy)
        Under(K.Dropdown(Shared("SoundChannel", "soundChannel", STRING, "Volume channel"), function() return am.CHOICES.soundChannel end,
            "The game has no volume for a single sound; this chooses which of the game's volume sliders it follows."), soundRow, SoundOn, soundWhy)
        Under(Button("Play the sound", "Play", function() R.AmmoWarning.TestSound() end,
            "Plays the chosen sound once, on the chosen channel."), soundRow, SoundOn, soundWhy)

        Header("Reset", "The reset says what it covers. Your background and border, the place and your custom ammunition are not changed by it.")
        K.ResetButton("Ammunition warning settings", resettable, function() am.ResetSettings() end,
            "Puts the settings on this page back to their defaults: when it shows, the icon, the text, the size, the opacity and the sound. The switch, the background and border, the warning's place and your custom ammunition are kept.")
    end,
})
