-- TwichUI settings: Camping bar, the Cozy Sleeping Bag's progress bar (camping/Rest.lua). A tab of the Camping bar page: whether
-- it shows, where it sits, and how it looks (the bar, its notches, its border, its text). The bar is part of the camping bar, so
-- it is on only while that is.

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "campingRest", name = "Sleeping bag bar", nav = "Sleeping bag bar", parent = "camping", order = 42,
    description = "A progress bar while you lie in the Cozy Sleeping Bag: three minutes, a notch at each minute you earn another 1% experience, and a timer.",
    keywords = "camp camping sleeping bag cozy rested experience progress bar timer notch minute border texture font color size opacity",
    when = function() return R.Camping ~= nil and R.CampingRest ~= nil end,
    build = function()
        local Header, Button, Proxy, Under = K.Header, K.Button, K.Proxy, K.Under
        local BOOL, STRING, NUMBER = K.BOOL, K.STRING, K.NUMBER
        local CB, RB = R.Camping, R.CampingRest
        local MS = R.MenuStyle
        if not (CB and RB) then return end

        K.Badge(Header("Sleeping bag bar", "A bar that fills to three minutes while you lie in the Cozy Sleeping Bag, with a notch at each minute and a timer. It is part of the camping bar, so it is on only while that is."), "Shows in combat")
        K.Status("Camping bar", function() return K.OnOff(R:Enabled("campingBar")) end, function()
            if R:Enabled("campingBar") then return nil end
            return "Turn the camping bar on, on the Camping bar tab, for this bar to work."
        end, "This bar belongs to the camping bar. Everything below is greyed out while the camping bar is off.", function()
            return R:Enabled("campingBar") and "ok" or "warn"
        end)
        local rest = K.ProxyToggle("campingRest", "Show the sleeping bag bar",
            "While you lie in the Cozy Sleeping Bag, a bar fills to three minutes with a notch at each minute and a timer. It starts when the game says you are resting soon after you used the bag, and the buff's stack count (once it exists) keeps it in step. It stops when you leave the bag, stays a few seconds, then goes. It only watches: it never uses the bag, plays a sound or speaks. Reading the bag this way has not been checked in the game: /tui camp probe shows what the game says.",
            CB.DEFAULTS.restShow, function() return CB.Get("restShow") end, function(value) CB.Set("restShow", value and true or false) end)
        local function On() return R:Enabled("campingBar") and CB.Get("restShow") end
        local WHY = function()
            if not R:Enabled("campingBar") then return "Greyed out: needs the camping bar turned on (the Camping bar tab)." end
            return "Greyed out: needs \"Show the sleeping bag bar\" turned on."
        end

        local resettable = {}
        local function Remember(variable, varType, label, key, set)
            local setting = Proxy(variable, varType, label, CB.DEFAULTS[key], function() return CB.Get(key) end, set)
            if setting then resettable[#resettable + 1] = { setting = setting, default = CB.DEFAULTS[key] } end
            return setting
        end
        local function Slider(variable, key, label, tooltip, parent, isOn, why)
            local limit = CB.LIMITS[key]
            local setting = Remember(variable, NUMBER, label, key, function(value) CB.Set(key, math.floor(value + 0.5)) end)
            return Under(K.Slider(setting, limit[1], limit[2], tooltip), parent or rest, isOn or On, why or WHY)
        end
        local function Check(variable, key, label, tooltip)
            local setting = Remember(variable, BOOL, label, key, function(value) CB.Set(key, value and true or false) end)
            if setting then return Under(K.Checkbox(setting, tooltip), rest, On, WHY) end
        end
        local function Swatch(variable, key, label, tooltip, parent, isOn, why)
            local setting = Remember(variable, STRING, label, key, function(value) CB.Set(key, value) end)
            return Under(K.Swatch(setting, tooltip), parent or rest, isOn or On, why or WHY)
        end
        local function Dropdown(variable, key, label, choices, tooltip)
            local setting = Remember(variable, STRING, label, key, function(value) CB.Set(key, value) end)
            return Under(K.Dropdown(setting, choices, tooltip), rest, On, WHY)
        end

        -- Place
        Under(Button("Sleeping bag bar sample", "Show a sample", function()
            if not RB.Preview() then
                R.Print("the sample needs the camping bar and the sleeping bag bar turned on, and isn't shown while a real one is.")
            end
        end, "Runs the bar through its three minutes in a few seconds so you can see the notches, the colors and the timer. Nothing is used or changed."), rest, On, WHY)
        Under(Button("Move the sleeping bag bar", function() return RB.Moving() and "Done" or "Move" end, function()
            if RB.Moving() then RB.StopMove() return end
            local ok, why = RB.StartMove()
            if not ok then
                R.Print(why == "unlock" and "EllesmereUI's Unlock Mode moves this bar: type /unlock and look for \"TwichUI Sleeping bag bar\"."
                    or "turn the camping bar and the sleeping bag bar on first.")
            end
        end, "Shows the bar with a sample and an outline you can drag to where you want it. Click Done, or close this window, to finish. You can also move it in Edit Mode, or in EllesmereUI's Unlock Mode when that is turned on (Camping bar tab, \"Use EllesmereUI Unlock Mode\"; the anchor is \"TwichUI Sleeping bag bar\")."), rest, On, WHY)
        Under(Button("Sleeping bag bar position", "Reset", function() RB.ResetPosition() end,
            "Puts the sleeping bag bar back at its default place. Only its place changes."), rest, On, WHY)

        -- The bar
        Header("The bar", "Its size, the texture of the fill, and its colors.")
        Check("campingRestSmooth", "restSmooth", "Make the sleeping bag bar fill smoothly",
            "The fill grows a little every frame-ish (about 30 times a second) instead of in small steps five times a second, and its width is not rounded to whole pixels. It only does this while the bar is on screen, and it reads the game no more often than before.")
        Slider("campingRestWidth", "restWidth", "Sleeping bag bar width", "The width of the whole bar, including the icon, in pixels.")
        Slider("campingRestHeight", "restHeight", "Sleeping bag bar height", "The height of the bar, in pixels.")
        Check("campingRestIcon", "restIcon", "Show the bag's icon on the bar", "The Cozy Sleeping Bag's icon at the left of the bar.")
        Dropdown("campingRestTexture", "restTexture", "Sleeping bag bar fill texture", function()
            return MS and MS.StatusBars and MS.StatusBars.Choices(CB.Get("restTexture")) or { { "solid", "Flat color" } }
        end, "The picture the fill is drawn with. A flat color is plain; with EllesmereUI installed its textures are listed too, and any other addon's status bar textures that LibSharedMedia knows. A texture that has gone is drawn flat and stays chosen.")
        Swatch("campingRestFill", "restFill", "Sleeping bag bar fill color", "The color of the fill while it fills. A texture is tinted by it.")
        Swatch("campingRestDone", "restDoneColor", "Sleeping bag bar color when full", "The color of the fill once all three minutes are done.")
        Swatch("campingRestBack", "restBack", "Sleeping bag bar background color", "The color behind the fill. Its opacity is part of the color.")
        Slider("campingRestOpacity", "restOpacity", "Sleeping bag bar opacity", "How solid the whole bar is, in percent.")

        -- Notches
        Header("Notches", "The marks at one and two minutes.")
        Swatch("campingRestNotch", "restNotchColor", "Sleeping bag bar notch color", "The color of the marks.")
        Slider("campingRestNotchWidth", "restNotchWidth", "Sleeping bag bar notch width", "How wide the marks are, in pixels.")

        -- Border
        Header("Border", "The line around the bar.")
        local textureRow = Dropdown("campingRestBorderTexture", "restBorderTexture", "Sleeping bag bar border texture", CB.RestBorderChoices,
            "Solid is a plain line. With EllesmereUI installed, its own border textures are listed too, drawn the way its bars draw them. The rest are LibSharedMedia borders. Picking one sets a thickness and color that suit it unless you have set your own.")
        Slider("campingRestBorderSize", "restBorderSize", "Sleeping bag bar border thickness", "The border, in pixels. 0 for none. A texture needs about 6 or more to read well.", textureRow)
        local classRow
        local classSetting = Remember("campingRestBorderClass", BOOL, "Use my class color for the sleeping bag bar border", "restBorderClass",
            function(value) CB.Set("restBorderClass", value and true or false) end)
        if classSetting then
            classRow = Under(K.Checkbox(classSetting, "Draws the border in your class color instead of the color below."), rest, On, WHY)
        end
        Swatch("campingRestBorderColor", "restBorderColor", "Sleeping bag bar border color", "The color of the border. Greyed out while the class color is used.",
            classRow, function() return On() and not CB.Get("restBorderClass") end,
            function()
                if not On() then return WHY() end
                return "Greyed out: the border uses your class color. Turn that off to choose another."
            end)
        Slider("campingRestBorderOpacity", "restBorderOpacity", "Sleeping bag bar border opacity", "How solid the border is, in percent. Applies to the class color too.")

        -- Text
        Header("Text", "The words on the bar: what you have earned on the left, the timer on the right.")
        Dropdown("campingRestFont", "restFont", "Sleeping bag bar font", function()
            if MS and MS.Fonts then return MS.Fonts.Choices(CB.Get("restFont"), { { "default", "Game font (default)" } }) end
            return { { "default", "Game font (default)" } }
        end, "The typeface of both texts. Fonts come from LibSharedMedia, so TwichUI's, EllesmereUI's and any other addon's are listed. A font that has gone is drawn with the game's own and stays chosen.")
        Dropdown("campingRestOutline", "restOutline", "Sleeping bag bar text outline", function()
            return { { "outline", "Outline" }, { "thick", "Thick outline" }, { "none", "None" } }
        end, "The edge drawn round each letter so it stays readable over the fill.")
        local labelRow = Check("campingRestLabel", "restLabel", "Show the experience earned on the bar", "The words on the left of the bar: \"Resting...\", then \"+1% experience\" and so on.")
        local labelOn = function() return On() and CB.Get("restLabel") end
        local labelWhy = function()
            if not On() then return WHY() end
            return "Greyed out: needs \"Show the experience earned on the bar\" turned on."
        end
        Slider("campingRestTextSize", "restTextSize", "Sleeping bag bar label size", "The size of the words on the left, in points.", labelRow, labelOn, labelWhy)
        Swatch("campingRestTextColor", "restTextColor", "Sleeping bag bar label color", "The color of the words on the left.", labelRow, labelOn, labelWhy)
        local timerSetting = Remember("campingRestTimer", STRING, "Sleeping bag bar timer", "restTimer", function(value) CB.Set("restTimer", value) end)
        local timerRow = Under(K.Dropdown(timerSetting, function() return {
            { "remaining", "Time left to three minutes" }, { "elapsed", "Time in the bag" },
            { "next", "Time to the next minute" }, { "off", "No timer" } } end,
            "What the number on the right of the bar counts."), rest, On, WHY)
        local timerOn = function() return On() and CB.Get("restTimer") ~= "off" end
        local timerWhy = function()
            if not On() then return WHY() end
            return "Greyed out: the timer is set to \"No timer\"."
        end
        Slider("campingRestTimerSize", "restTimerSize", "Sleeping bag bar timer size", "The size of the timer on the right, in points.", timerRow, timerOn, timerWhy)
        Swatch("campingRestTimerColor", "restTimerColor", "Sleeping bag bar timer color", "The color of the timer on the right.", timerRow, timerOn, timerWhy)

        -- After
        Header("When it ends", "What the bar does once you finish or leave the bag.")
        Slider("campingRestLinger", "restLinger", "Sleeping bag bar seconds to stay when done", "How long the bar stays after you finish or leave the bag. 0 hides it at once.")

        K.ResetButton("Sleeping bag bar appearance", resettable, CB.ResetRestLook,
            "Puts the sleeping bag bar's size, colors, border, text and timer back to their defaults. Whether it is on and its place are kept.")
    end,
})
