-- TwichUI settings: Food and drink (modules/FoodDrink.lua: two buttons you click to eat or drink, where they
-- go, and how they look).

local R = TwichUI
local K = R.SettingsKit

local UNLOCK_STATUS = {
    off = { "Off" },
    ["no-eui"] = { "EllesmereUI isn't installed or turned on", "The buttons are moved in Edit Mode until it is." },
    ["no-api"] = { "This EllesmereUI has no Unlock Mode", "The buttons are moved in Edit Mode." },
    waiting = { "Waiting for EllesmereUI", "It hasn't finished loading yet." },
    ["register-failed"] = { "EllesmereUI didn't take the anchor", "The buttons are moved in Edit Mode. /tui diagnostics has the details." },
    ["module-off"] = { "Ready", "The anchor appears in Unlock Mode while a Food or Drink button is on." },
    active = { "In EllesmereUI's Unlock Mode", "Type /unlock and look for \"TwichUI Food & Drink\"." },
}

K.Page({
    key = "food", name = "Food and drink", order = 40, group = "everyday",
    description = "Two buttons you click to eat or drink the best food or drink in your bags. TwichUI never uses anything for you.",
    keywords = "eat drink water bread buttons edit mode unlock ellesmere conjured mana",
    overview = {
        label = "Food and drink", tip = "Two buttons you click to eat or drink the best food or drink in your bags.",
        status = function() return K.OnOff(R:Enabled("foodDrink")) end,
    },
    build = function()
        local Header, Toggle, Button, Proxy, ProxyToggle, Under = K.Header, K.Toggle, K.Button, K.Proxy, K.ProxyToggle, K.Under
        local BOOL, STRING, NUMBER = K.BOOL, K.STRING, K.NUMBER

        Header("Food and Drink buttons", "Two small buttons you click to eat or drink. TwichUI never uses anything for you.")
        local foodDrink = Toggle("foodDrink", "Show Food and Drink buttons",
            "Adds a Food button and a Drink button. Each holds the food or drink in your bags that restores the most (by the amount the item's own text states) among what you can use, and eats or drinks it only when you click it. It chooses only plain food and drink, judged from the item's own text: buff food, feasts and anything it can't read are never picked. An empty button means there is nothing it can tell is plain food or drink in your bags.\n\nThe choice updates when your bags change; if they change during combat, it updates when combat ends. Move the buttons in Edit Mode. Nothing is saved but where you put them and the look you choose below.")
        local function FoodDrinkOn() return R:Enabled("foodDrink") end
        Under(Toggle("foodDrinkFood", "Show the Food button",
            "Off: only the Drink button is shown."), foodDrink, FoodDrinkOn)
        Under(Toggle("foodDrinkDrink", "Show the Drink button",
            "Off: only the Food button is shown. Classes without mana may not want this one."), foodDrink, FoodDrinkOn)

        local FD = R.FoodDrink
        if not FD then return end
        Under(ProxyToggle("foodDrinkPreferConjured", "Prefer Mage-conjured food and water",
            "When you carry Mage-conjured food or water you can use, the buttons choose it over ordinary food or drink, even when an ordinary item restores more health or mana. Food and water are chosen separately: with conjured food but no conjured water, the Food button holds the conjured food and the Drink button holds the best ordinary drink. With none of a kind, that button chooses as it always does. Among conjured items, the one that restores the most is chosen. It works for any character carrying conjured items, not only Mages, and never lets in an item the buttons would otherwise skip. Off, the choice is the one that restores the most.",
            FD.DEFAULTS.preferConjured, function() return FD.Get("preferConjured") end,
            function(value) FD.Set("preferConjured", value and true or false) end), foodDrink, FoodDrinkOn)
        
        -- Add Mage Conjure Food & Drink setting for mages without consumables
        Under(Toggle("qolMageConjureFoodDrink", "Show conjure food/water when no consumables in bags",
            "Mage only. When the Food or Drink button has nothing it can use in your bags, it becomes Conjure Food or Conjure Water, at the highest rank you have learned, and casts it when you click it. Once the food or water is in your bags, the button goes back to it. A button that has an item is never changed."),
            foodDrink, FoodDrinkOn)
        
        -- Where they go. Edit Mode moves the buttons unless this is on and EllesmereUI is there.

        -- Where they go. Edit Mode moves the buttons unless this is on and EllesmereUI is there.
        local FDU = FD.Unlock
        if FDU then
            local unlockBase = "Move the buttons in EllesmereUI's Unlock Mode instead of Edit Mode. A \"TwichUI Food & Drink\" anchor appears there, and you drag it, nudge it, type its X and Y or anchor it to another element the way you do the rest of your interface. Turning this on keeps the buttons where they are. The place is still saved by TwichUI; EllesmereUI's anchor links are saved by EllesmereUI.\n\nOpen Unlock Mode with /unlock. It can't be opened in combat, and nothing is moved then.\n\nOff, or without EllesmereUI, the buttons are moved in Edit Mode as before. Your choice is kept while EllesmereUI is away."
            local unlock = Under(Toggle("foodDrinkUnlock", "Use EllesmereUI Unlock Mode", unlockBase), foodDrink, FoodDrinkOn)
            if unlock and unlock.GetTooltip ~= nil then
                -- read when the tooltip is shown, so it is never stale
                local withParent = unlock.GetTooltip
                unlock.GetTooltip = function(self)
                    local code = FDU.Status()
                    local text = UNLOCK_STATUS[code] or { code }
                    local color = (code == "active" and R.GREEN) or (code == "off" and R.GREY) or R.GOLD
                    local tip = withParent(self) or unlockBase
                    return tip .. "\n\nStatus: " .. color .. text[1] .. "|r" .. (text[2] and ("\n" .. text[2]) or "")
                end
            end
            Under(Button("Position", "Reset", function() FD.ResetPosition() end,
                "Puts the Food and Drink buttons back at their default place. Only their place changes. An anchor you made to another element in EllesmereUI's Unlock Mode is EllesmereUI's, and is removed there."),
                foodDrink, FoodDrinkOn)
        end

        K.Badge(Header("Appearance", "Make the buttons match the rest of your interface. In combat the game doesn't let the buttons change, so a change waits until combat ends; opacity changes at once."), "Waits for combat")
        local resettable = {}   -- { setting, default }, for Reset
        local function Remember(variable, varType, label, key, set)
            local setting = Proxy(variable, varType, label, FD.DEFAULTS[key], function() return FD.Get(key) end, set)
            if setting then resettable[#resettable + 1] = { setting = setting, default = FD.DEFAULTS[key] } end
            return setting
        end
        local function Slider(variable, key, label, tooltip, parent, isOn, why)
            local limit = FD.LIMITS[key]
            local setting = Remember(variable, NUMBER, label, key, function(value) FD.Set(key, math.floor(value + 0.5)) end)
            return Under(K.Slider(setting, limit[1], limit[2], tooltip), parent or foodDrink, isOn or FoodDrinkOn, why)
        end
        Slider("foodDrinkSize", "size", "Button size", "The width and height of each button, in pixels.")
        Slider("foodDrinkSpacing", "spacing", "Space between buttons", "The gap between the two buttons, in pixels.")
        local layoutSetting = Remember("foodDrinkLayout", STRING, "Layout", "layout", function(value) FD.Set("layout", value) end)
        Under(K.Dropdown(layoutSetting, function() return { { "horizontal", "Side by side" }, { "vertical", "Stacked" } } end,
            "Whether the buttons sit next to each other or one above the other."), foodDrink, FoodDrinkOn)
        local textureSetting = Remember("foodDrinkBorderTexture", STRING, "Border texture", "borderTexture", function(value) FD.Set("borderTexture", value) end)
        Under(K.Dropdown(textureSetting, FD.TextureChoices,
            "Solid is a plain line. With EllesmereUI installed, its own border textures (such as Pixels Textured) are listed too, drawn the way its bars draw them. The rest are border textures from LibSharedMedia, so any addon that adds borders to it adds them here. Picking one sets a thickness and color that suit it unless you have set your own; change them below."), foodDrink, FoodDrinkOn)
        Slider("foodDrinkBorderSize", "borderSize", "Border thickness", "The border around each button, in pixels. 0 for none. A texture needs about 8 or more to read well.")
        local classToggle
        local classSetting = Remember("foodDrinkBorderClass", BOOL, "Use my class color for the border", "borderClass",
            function(value) FD.Set("borderClass", value and true or false) end)
        if classSetting then
            classToggle = Under(K.Checkbox(classSetting,
                "Draws the border in your class color instead of the color below."), foodDrink, FoodDrinkOn)
        end
        local colorSetting = Remember("foodDrinkBorderColor", STRING, "Border color", "borderColor", function(value) FD.Set("borderColor", value) end)
        Under(K.Swatch(colorSetting, "The color of the border. Greyed out while the class color is used."),
            classToggle or foodDrink, function() return FoodDrinkOn() and not FD.Get("borderClass") end,
            function()
                if not FoodDrinkOn() then return "Greyed out: needs \"Show Food and Drink buttons\" turned on." end
                return "Greyed out: the border uses your class color. Turn that off to choose another."
            end)
        Slider("foodDrinkBorderOpacity", "borderOpacity", "Border opacity", "How solid the border is, in percent. 100 is fully opaque. Applies to the class color too.")
        Slider("foodDrinkZoom", "zoom", "Icon zoom", "How much of the icon's edge is cropped, in percent. More looks tighter inside the border.")
        local countSetting = Remember("foodDrinkShowCount", BOOL, "Show how many I have", "showCount",
            function(value) FD.Set("showCount", value and true or false) end)
        if countSetting then
            Under(K.Checkbox(countSetting,
                "A small number in the corner of a button when you have more than one."), foodDrink, FoodDrinkOn)
        end
        Slider("foodDrinkButtonOpacity", "buttonOpacity", "Button opacity", "How solid the buttons are, in percent. 100 is fully opaque.")
        local mouseoverSetting = Remember("foodDrinkMouseover", BOOL, "Fade when the mouse is away", "mouseover",
            function(value) FD.Set("mouseover", value and true or false) end)
        if mouseoverSetting then
            local mouseover = Under(K.Checkbox(mouseoverSetting,
                "The buttons fade to the opacity below until the mouse is over one, then return to the button opacity. Even at 0 a button still takes a click, so move the mouse to where it is."), foodDrink, FoodDrinkOn)
            Slider("foodDrinkIdleOpacity", "idleOpacity", "Opacity when the mouse is away",
                "How solid the buttons are, in percent, while the mouse is not over them.",
                mouseover or foodDrink, function() return FoodDrinkOn() and FD.Get("mouseover") end,
                function()
                    if not FoodDrinkOn() then return "Greyed out: needs \"Show Food and Drink buttons\" turned on." end
                    return "Greyed out: needs \"Fade when the mouse is away\" turned on."
                end)
        end
        K.ResetButton("Appearance", resettable, FD.ResetLook,
            "Puts size, spacing, layout, border, zoom, opacity and the count back to their defaults. The place is kept.")
    end,
})
