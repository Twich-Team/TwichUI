-- TwichUI settings: Camping bar (camping/Bar.lua: a bar of buttons for the campfire, the camp objects your
-- professions make and the Cozy Sleeping Bag; what is on it, when it shows, and how it looks).

local R = TwichUI
local K = R.SettingsKit

local UNLOCK_STATUS = {
    off = { "Off" },
    ["no-eui"] = { "EllesmereUI isn't installed or turned on", "The bar is moved in Edit Mode until it is." },
    ["no-api"] = { "This EllesmereUI has no Unlock Mode", "The bar is moved in Edit Mode." },
    waiting = { "Waiting for EllesmereUI", "It hasn't finished loading yet." },
    ["register-failed"] = { "EllesmereUI didn't take the anchor", "The bar is moved in Edit Mode. /tui diagnostics has the details." },
    ["module-off"] = { "Ready", "The anchor appears in Unlock Mode while the camping bar is on." },
    active = { "In EllesmereUI's Unlock Mode", "Type /unlock and look for \"TwichUI Camping bar\"." },
}

-- Each profession's section: the game's own trade icon (a path into the client's art, nothing shipped) and a
-- muted color for its title and the stripe down its card. Artwork only: the bar never reads either.
local ICON_DIR = "Interface\\Icons\\"
local PROFESSION = {
    alchemy = { icon = ICON_DIR .. "Trade_Alchemy", color = { 0.40, 0.76, 0.60 } },
    blacksmithing = { icon = ICON_DIR .. "Trade_BlackSmithing", color = { 0.90, 0.48, 0.32 } },
    cooking = { icon = ICON_DIR .. "INV_Misc_Food_15", color = { 0.92, 0.74, 0.40 } },
    enchanting = { icon = ICON_DIR .. "Trade_Engraving", color = { 0.70, 0.58, 0.90 } },
    engineering = { icon = ICON_DIR .. "Trade_Engineering", color = { 0.42, 0.78, 0.84 } },
    firstaid = { icon = ICON_DIR .. "INV_Misc_Bandage_15", color = { 0.88, 0.52, 0.54 } },
    fishing = { icon = ICON_DIR .. "Trade_Fishing", color = { 0.46, 0.64, 0.90 } },
    herbalism = { icon = ICON_DIR .. "Trade_Herbalism", color = { 0.60, 0.80, 0.46 } },
    leatherworking = { icon = ICON_DIR .. "INV_Misc_ArmorKit_17", color = { 0.80, 0.56, 0.34 } },
    mining = { icon = ICON_DIR .. "Trade_Mining", color = { 0.72, 0.74, 0.78 } },
    skinning = { icon = ICON_DIR .. "INV_Misc_Pelt_Wolf_01", color = { 0.66, 0.54, 0.40 } },
    tailoring = { icon = ICON_DIR .. "Trade_Tailoring", color = { 0.88, 0.62, 0.80 } },
}

K.Page({
    key = "camping", icon = "camping", name = "Camping bar", tab = "Camping bar", order = 41, group = "everyday",
    description = "A bar for camping: your campfire kit, the camp objects your professions make, and the Cozy Sleeping Bag. You click; nothing is placed for you.",
    keywords = "camp campfire camping fire tent kit profession object blueprint sleeping bag cozy rested buff bar action hide dungeon raid resting mouseover fade",
    overview = {
        label = "Camping bar", tip = "A bar for the campfire kit, camp objects and the Cozy Sleeping Bag.",
        status = function() return K.OnOff(R:Enabled("campingBar")) end,
    },
    build = function()
        local Header, Toggle, Button, Proxy, ProxyToggle, Under = K.Header, K.Toggle, K.Button, K.Proxy, K.ProxyToggle, K.Under
        local BOOL, STRING, NUMBER = K.BOOL, K.STRING, K.NUMBER
        local CB, CD = R.Camping, R.CampingData
        if not (CB and CD) then return end

        Header("Camping bar", "Buttons for WoW: Forever's camping, filled in from what your character knows and carries.")
        local camping = Toggle("campingBar", "Show the camping bar",
            "Adds a bar with a button for each thing you can put down at a camp: the campfire kit you hold (or the Basic Campfire spell), each camp object you have in your bags, each one you know the recipe for but haven't made, and the Cozy Sleeping Bag once you have it.\n\nA button with the item in your bags uses it when you click. A dimmed button is a recipe you know with none made: clicking it opens the recipe in your professions window and crafts nothing. TwichUI never places, crafts or casts anything for you.\n\nThe bar reads your bags, skills and recipes when they change; a change in combat waits until combat ends. Move it in Edit Mode.")
        local function On() return R:Enabled("campingBar") end

        local function Check(variable, key, label, tooltip, parent, isOn, why)
            local setting = ProxyToggle(variable, label, tooltip, CB.DEFAULTS[key], function() return CB.Get(key) end,
                function(value) CB.Set(key, value and true or false) end)
            return Under(setting, parent or camping, isOn or On, why)
        end

        K.Badge(Header("What is on the bar", "Choose what the bar fills itself with."), "Waits for combat")
        Check("campingFire", "showFire", "Show the campfire button",
            "The campfire kit with the most room that is in your bags. With none, the Basic Campfire spell if you know it; with neither, a dimmed button for the best kit recipe you know.")
        Check("campingBag", "showBag", "Show the Cozy Sleeping Bag",
            "Appears when the bag is in your bags. It never appears before you have it.")
        Check("campingBest", "best", "Only the best object of each profession",
            "For each profession, show one button: what you hold beats what you could make, and a higher tier beats a lower one. Off, every object you hold or can make is shown. Per the guides a higher tier keeps the lower tier's buff, but that has not been confirmed in the game.")
        Check("campingOnlyBags", "onlyBags", "Only what is in my bags",
            "Hide the dimmed buttons for recipes you know but haven't made. The Basic Campfire spell, which needs no kit, stays.")
        -- One section per profession, each with its own icon and color, in the order the bar shows them.
        for _, group in ipairs(CD.GROUPS) do
            local key = group.key
            local look = PROFESSION[key] or {}
            local names, seen = {}, {}
            for _, o in ipairs(group.objects) do
                if not seen[o.name] then seen[o.name] = true; names[#names + 1] = o.name end
            end
            local section = Header(group.name, "Camp objects " .. group.name .. " makes: " .. table.concat(names, ", ") .. ". Turn the profession off to leave all of them off the bar, or pick the ones you want.")
            section.settingsSecondary = true
            K.Accent(section,
                look.icon, look.color)
            local row = Check("campingGroup_" .. key, "grp_" .. key, "Show " .. group.name .. " objects",
                "Off hides every " .. group.name .. " camp object from the bar, whether you hold it or only know the recipe.")
            -- Each object can also be left off on its own; they follow the profession's switch.
            for _, o in ipairs(group.objects) do
                Check("campingObject_" .. o.item, "obj_" .. o.item, ("Tier %d: %s"):format(o.tier, o.name),
                    ("Off keeps the %s %s off the bar, whether you hold one or only know the recipe."):format(group.name, o.name),
                    row, function() return On() and CB.Get("grp_" .. key) end,
                    function()
                        if not On() then return "Greyed out: needs \"Show the camping bar\" turned on." end
                        return "Greyed out: " .. group.name .. " objects are turned off above."
                    end)
            end
        end

        K.Header("Eat button", "A button that eats buff food and sits you down at the fire. You still click: nothing is eaten for you.")
        local eat = Check("campingEat", "eat", "Show an eat button",
            "Adds a button for buff food (food that makes you Well Fed, recognised from the item's own text, never from a list) that is in your bags. Clicking it eats the food and sits you down. It is hidden while you have no such food. You can also give it a key in the game's Key Bindings (TwichUI, \"Eat buff food and sit\").")
        local function EatOn() return On() and CB.Get("eat") end
        local EAT_WHY = function()
            if not On() then return "Greyed out: needs \"Show the camping bar\" turned on." end
            return "Greyed out: needs \"Show an eat button\" turned on."
        end
        local modeSetting = Proxy("campingEatMode", STRING, "Which food", CB.DEFAULTS.eatMode, function() return CB.Get("eatMode") end,
            function(value) CB.Set("eatMode", value) end)
        Under(K.Dropdown(modeSetting, function() return { { "auto", "The best buff food I have" }, { "choose", "The food I choose" } } end,
            "The best is the buff food in your bags that restores the most (a part stack is used up first). Choosing keeps to one food: the button is hidden while it isn't in your bags."),
            eat or camping, EatOn, EAT_WHY)
        local foodSetting = Proxy("campingEatItem", NUMBER, "Chosen food", CB.DEFAULTS.eatItem, function() return CB.Get("eatItem") end,
            function(value) CB.Set("eatItem", math.floor(value + 0.5)) end)
        Under(K.Dropdown(foodSetting, function()
            local list, have = { { 0, "None chosen" } }, {}
            for _, food in ipairs(CB.BuffFoods(true)) do
                list[#list + 1] = { food.id, ("%s (%d)"):format(food.name or ("Item " .. food.id), food.count) }
                have[food.id] = true
            end
            local saved = CB.Get("eatItem")
            if saved ~= 0 and not have[saved] then list[#list + 1] = { saved, "Item " .. saved .. " (not in your bags)" } end
            return list
        end, "The buff food in your bags right now. Open this list again after your bags change."),
            eat or camping, function() return EatOn() and CB.Get("eatMode") == "choose" end,
            function()
                if not EatOn() then return EAT_WHY() end
                return "Greyed out: needs \"The food I choose\" above."
            end)
        Check("campingEatSit", "eatSit", "Sit down after eating",
            "The button runs /use for the food and then /sit. Off, it only eats (eating seats you anyway on most food).",
            eat or camping, EatOn, EAT_WHY)

        K.Header("When it shows", "The bar can step aside when you don't want it. A hidden bar is only hidden: nothing else changes.")
        Check("campingHideParty", "hideParty", "Hide in dungeons", "Hidden inside a 5-player dungeon.")
        Check("campingHideRaid", "hideRaid", "Hide in raids", "Hidden inside a raid.")
        Check("campingHidePvp", "hidePvp", "Hide in battlegrounds and arenas", "Hidden inside a battleground or arena.")
        Check("campingHideResting", "hideResting", "Hide in rested areas", "Hidden while the game says you are resting, as in an inn or a city.")
        Check("campingHideCombat", "hideCombat", "Hide in combat", "Hidden while you are in combat, back when it ends.")
        Check("campingNearFire", "onlyNearFire", "Only near a campfire",
            "Shown only while the game gives you its \"Campfire Nearby\" effect. In combat the game may not say, and then the bar stays as it was. This relies on that effect being what Forever uses; it has not been checked in the game.")

        K.Badge(Header("Appearance", "Make the bar match the rest of your interface. In combat the game doesn't let the buttons change, so a change waits until combat ends; opacity changes at once. The buttons themselves change, so watch them on your screen."), "Waits for combat")
        local resettable = {}
        local function Remember(variable, varType, label, key, set)
            local setting = Proxy(variable, varType, label, CB.DEFAULTS[key], function() return CB.Get(key) end, set)
            if setting then resettable[#resettable + 1] = { setting = setting, default = CB.DEFAULTS[key] } end
            return setting
        end
        local function Slider(variable, key, label, tooltip, parent, isOn, why)
            local limit = CB.LIMITS[key]
            local setting = Remember(variable, NUMBER, label, key, function(value) CB.Set(key, math.floor(value + 0.5)) end)
            return Under(K.Slider(setting, limit[1], limit[2], tooltip), parent or camping, isOn or On, why)
        end
        Slider("campingSize", "size", "Button size", "The width and height of each button, in pixels.")
        Slider("campingSpacing", "spacing", "Space between buttons", "The gap between buttons, in pixels.")
        Slider("campingPerLine", "perLine", "Buttons per row", "How many buttons sit in a row (or a column, when stacked) before the next row starts.")
        local layoutSetting = Remember("campingLayout", STRING, "Layout", "layout", function(value) CB.Set("layout", value) end)
        Under(K.Dropdown(layoutSetting, function() return { { "horizontal", "Rows" }, { "vertical", "Columns" } } end,
            "Whether buttons fill a row before starting the next, or a column."), camping, On)
        local textureSetting = Remember("campingBorderTexture", STRING, "Border texture", "borderTexture", function(value) CB.Set("borderTexture", value) end)
        Under(K.Dropdown(textureSetting, CB.TextureChoices,
            "Solid is a plain line. With EllesmereUI installed, its own border textures are listed too, drawn the way its bars draw them. The rest are LibSharedMedia borders. Picking one sets a thickness and color that suit it unless you have set your own."), camping, On)
        Slider("campingBorderSize", "borderSize", "Border thickness", "The border around each button, in pixels. 0 for none. A texture needs about 8 or more to read well.")
        local classToggle
        local classSetting = Remember("campingBorderClass", BOOL, "Use my class color for the border", "borderClass",
            function(value) CB.Set("borderClass", value and true or false) end)
        if classSetting then
            classToggle = Under(K.Checkbox(classSetting, "Draws the border in your class color instead of the color below."), camping, On)
        end
        local colorSetting = Remember("campingBorderColor", STRING, "Border color", "borderColor", function(value) CB.Set("borderColor", value) end)
        Under(K.Swatch(colorSetting, "The color of the border. Greyed out while the class color is used."),
            classToggle or camping, function() return On() and not CB.Get("borderClass") end,
            function()
                if not On() then return "Greyed out: needs \"Show the camping bar\" turned on." end
                return "Greyed out: the border uses your class color. Turn that off to choose another."
            end)
        Slider("campingBorderOpacity", "borderOpacity", "Border opacity", "How solid the border is, in percent. Applies to the class color too.")
        Slider("campingZoom", "zoom", "Icon zoom", "How much of the icon's edge is cropped, in percent.")
        local countSetting = Remember("campingShowCount", BOOL, "Show how many I have", "showCount",
            function(value) CB.Set("showCount", value and true or false) end)
        if countSetting then
            Under(K.Checkbox(countSetting, "A small number in the corner of a button when you hold more than one."), camping, On)
        end
        Slider("campingButtonOpacity", "buttonOpacity", "Bar opacity", "How solid the bar is, in percent.")
        local mouseoverSetting = Remember("campingMouseover", BOOL, "Fade when the mouse is away", "mouseover",
            function(value) CB.Set("mouseover", value and true or false) end)
        if mouseoverSetting then
            local mouseover = Under(K.Checkbox(mouseoverSetting,
                "The bar fades to the opacity below until the mouse is over a button. Even at 0 a button still takes a click, so move the mouse to where it is."), camping, On)
            Slider("campingIdleOpacity", "idleOpacity", "Opacity when the mouse is away",
                "How solid the bar is, in percent, while the mouse is not over it.",
                mouseover or camping, function() return On() and CB.Get("mouseover") end,
                function()
                    if not On() then return "Greyed out: needs \"Show the camping bar\" turned on." end
                    return "Greyed out: needs \"Fade when the mouse is away\" turned on."
                end)
        end
        local CU = R.CampingUnlock
        if CU then
            local unlockBase = "Move the bar in EllesmereUI's Unlock Mode instead of Edit Mode. A \"TwichUI Camping bar\" anchor appears there (and a \"TwichUI Sleeping bag bar\" one for the sleeping bag bar), and you drag it, nudge it, type its X and Y or anchor it to another element the way you do the rest of your interface. Turning this on keeps the bar where it is. The place is still saved by TwichUI; EllesmereUI's anchor links are saved by EllesmereUI.\n\nOpen Unlock Mode with /unlock. It can't be opened in combat, and nothing is moved then.\n\nOff, or without EllesmereUI, the bar is moved in Edit Mode. Your choice is kept while EllesmereUI is away."
            local unlock = Check("campingUnlock", "unlockMode", "Use EllesmereUI Unlock Mode", unlockBase)
            if unlock and unlock.GetTooltip ~= nil then
                -- read when the tooltip is shown, so it is never stale
                local withParent = unlock.GetTooltip
                unlock.GetTooltip = function(self)
                    local code = CU.Status()
                    local text = UNLOCK_STATUS[code] or { code }
                    local color = (code == "active" and R.GREEN) or (code == "off" and R.GREY) or R.GOLD
                    local tip = withParent(self) or unlockBase
                    return tip .. "\n\nStatus: " .. color .. text[1] .. "|r" .. (text[2] and ("\n" .. text[2]) or "")
                end
            end
        end
        Under(Button("Bar position", "Reset", function() CB.ResetPosition() end,
            "Puts the camping bar back at its default place. Only its place changes."), camping, On)
        K.ResetButton("Bar appearance", resettable, CB.ResetLook,
            "Puts size, spacing, layout, border, zoom, opacity and the count back to their defaults. What is on the bar, when it shows and its place are kept.")
    end,
})
