-- TwichUI settings: Class resource bars (classbars/). Four pages: General (the switch, when to show, moving the
-- bars, the preview), Layout (sizes, spacing, where the secondary bars go), Appearance (fill, text, background and
-- border, and what your class's own resources do differently) and Effects. The bars are drawn, and every value is
-- checked and saved, by the core addon's classbars/ files; this file only describes rows that call their Get/Set.
-- Nothing here is needed for the bars to work.

local R = TwichUI
local K = R.SettingsKit

local OVERRIDE_TIP = "Set for this resource only: the shared style does not apply to it. Choose \"Same as the shared style\" to stop overriding."

K.Page({
    key = "classBars", name = "Class resource bars", nav = "Class resource bars", order = 55, group = "class",
    description = "Your class's resources as bars: mana, rage or energy, and combo points on your target. Off until you turn it on.",
    keywords = "resource bar mana rage energy focus combo points druid rogue warrior mage power class bar secondary position move unlock preview",
    overview = {
        label = "Class resource bars", tip = "Your class's resources as bars: the power you are using, and combo points for Rogues and Cat Form Druids.",
        when = function() return R.ClassBars ~= nil end,
        status = function() return K.OnOff(R:Enabled("classBars")) end,
    },
    when = function() return R.ClassBars ~= nil end,
    build = function()
        local CB = R.ClassBars
        local Header, Toggle, Button, Under = K.Header, K.Toggle, K.Button, K.Under
        local BOOL, STRING, NUMBER = K.BOOL, K.STRING, K.NUMBER
        local function On() return R:Enabled("classBars") end

        Header("Class resource bars", "Draws the resource your character is using as a bar, and combo points as segments. It reads the power the game itself reports, so a Druid's bar follows the form it is in. It adds no clicks, hides nothing of the game's or of another addon's, and does nothing until you turn it on.")
        local main = Toggle("classBars", "Show class resource bars",
            "Shows a bar for the power you are using now, a segmented bar for combo points (Rogues, and Druids in Cat Form) and, for a Druid whose power is not mana, a thin mana bar. Other classes' special resources are not shown, because the game does not provide them here.\n\nTurn it off to remove the bars completely: nothing listens for the game's events and nothing is drawn. The settings below are kept. Move the bars with \"Move the bars\" below.")
        K.Under(K.Status("Showing now",
            function()
                local snap = CB.Snapshot()
                if not snap.running then return On() and "Waiting for the game world" or "Off" end
                local names = {}
                for _, slot in ipairs({ "primary", "secondary", "tertiary" }) do
                    local key, label = CB.SlotInfo(slot)
                    if key and CB.Get(slot .. "On") then names[#names + 1] = label end
                end
                return #names > 0 and table.concat(names, ", ") or "Nothing to show right now"
            end,
            function() return "The resources your character is drawing now." end,
            "Which resources are being drawn for the character you are playing, read from the game. This changes with your form.",
            function() return On() and "ok" or "quiet" end), main, On)

        Header("When to show", "Each rule says what it hides. A resource's own resting value is mana, energy and focus full, and rage, runic power and combo points empty.")
        local resettable = {}
        local function Shared(variable, key, varType, label, set)
            local setting = K.Proxy("classBars" .. variable, varType, label, CB.DEFAULTS[key],
                function() return CB.Get(key) end, set or function(value) CB.Set(key, value) end)
            if setting then resettable[#resettable + 1] = { setting = setting, default = CB.DEFAULTS[key] } end
            return setting
        end
        Under(K.Dropdown(Shared("Show", "show", STRING, "Show the bars"), function() return CB.CHOICES.show end,
            "Always shows each bar whenever it has something to show. Fade in during combat keeps it there but eases it to full strength when combat starts and back down to the opacity below when it ends. Only in combat hides it out of combat. In combat or when not at rest shows it in combat, and out of combat whenever its resource is away from its resting value: a Warrior's rage while it decays, a Rogue's combo points while you hold any, a Mage's mana while it regenerates. A resource with no known resting value is never hidden by this rule. A resource of your class can follow its own rule on the Appearance page."), main, On)
        local fade = K.Slider(Shared("FadeIdle", "fadeIdle", NUMBER, "Opacity out of combat", function(v) CB.Set("fadeIdle", math.floor(v + 0.5)) end),
            CB.LIMITS.fadeIdle[1], CB.LIMITS.fadeIdle[2],
            "How solid a bar is out of combat, in percent, when its rule is \"Fade in during combat\". In combat it is at full strength. 0 makes it invisible until combat. It is the bar's own opacity, on top of the overall opacity on the Layout page, and has no effect on bars that follow another rule.")
        Under(fade, main, On)
        Under(K.Checkbox(Shared("HideDead", "hideDead", BOOL, "Hide while dead or a ghost", function(v) CB.Set("hideDead", v and true or false) end),
            "Hides the bars while you are dead or a ghost. They come back as soon as you are alive."), main, On)
        Under(K.Checkbox(Shared("HideMounted", "hideMounted", BOOL, "Hide while mounted", function(v) CB.Set("hideMounted", v and true or false) end),
            "Hides the bars while you are mounted. Off by default."), main, On)
        Under(K.Checkbox(Shared("HideVehicle", "hideVehicle", BOOL, "Hide in vehicles", function(v) CB.Set("hideVehicle", v and true or false) end),
            "Hides the bars while the game shows a vehicle's controls. They never show the vehicle's own resource, only yours."), main, On)

        Header("Place and preview", "The bars are made of ordinary frames that take no clicks, so they never get in the way of the world. Only while you are moving them do they take the mouse.")
        local previewRow = Under(Button("Preview",
            function() return CB.PreviewActive() and "Stop" or "Show" end,
            function()
                if CB.PreviewActive() then CB.PreviewStop()
                elseif not CB.PreviewStart() then R.Print("the preview waits until you are out of combat.") end
                K.RefreshOverview()
            end,
            "Shows the bars with made-up numbers, drawn by the same code as the real ones, so you can judge a change without a fight. It is marked Preview on screen, changes nothing about your real resources, and ends when you close these settings, enter combat or turn the bars off. Your real values are kept up to date underneath, so ending it shows the truth at once."), main, On)
        local function Previewing() return On() and CB.PreviewActive() end
        local function WhyPreview() return "Greyed out: turn the preview on first." end
        local level = K.Slider(K.Proxy("classBarsSampleLevel", NUMBER, "Sample level", 70,
            function() local l = CB.PreviewLevels() return l end, function(v) CB.PreviewSet(math.floor(v + 0.5), nil) end), 0, 100,
            "The made-up fill of the preview's continuous bars, in percent. It only changes the preview.")
        Under(level, previewRow, Previewing, WhyPreview)
        local points = K.Slider(K.Proxy("classBarsSamplePoints", NUMBER, "Sample combo points", 3,
            function() local _, p = CB.PreviewLevels() return p end, function(v) CB.PreviewSet(nil, math.floor(v + 0.5)) end), 0, 5,
            "How many segments of the preview's segmented bar are lit. It only changes the preview.")
        Under(points, previewRow, Previewing, WhyPreview)
        local move = Under(Button("Move the bars",
            function() return CB.PositioningActive() and "Finish" or "Move" end,
            function()
                if CB.PositioningActive() then CB.PositionEnd()
                else
                    local ok = CB.PositionStart()
                    if not ok then R.Print("the bars can be moved when you are out of combat.") end
                end
                K.RefreshOverview()
            end,
            "Shows the bars with sample values and a highlighted handle over them. Drag the handle to move them; right-click it, or press Finish, when you are done. Moving ends by itself if you enter combat. The place is kept on your screen even if your screen size changes."), main, On)
        Under(Button("Reset position", "Reset", function() CB.ResetPosition() end,
            "Puts the bars back at their default place near the middle of the screen, below your character. Only the place changes; nothing else is touched."), main, On)

        Header("Reset", "Each reset says what it covers. Other pages, the places of the bars and your class's own resource settings are not changed by it.")
        K.ResetButton("When to show", resettable, function() CB.ResetGroup("behavior") end,
            "Puts \"Show the bars\" and the three hide rules back to their defaults. Sizes, looks, effects, the places of the bars and what your class's resources do differently are kept.")
    end,
})

K.Page({
    key = "classBarsLayout", name = "Class resource bar layout", nav = "Layout", parent = "classBars", order = 56,
    description = "How big the bars are and where the secondary ones sit.",
    keywords = "width height size scale opacity spacing gap segment placement stack separate bars",
    when = function() return R.ClassBars ~= nil end,
    build = function()
        local CB = R.ClassBars
        local Header, Under = K.Header, K.Under
        local BOOL, STRING, NUMBER = K.BOOL, K.STRING, K.NUMBER
        local function On() return R:Enabled("classBars") end
        local main = K.switchRows.classBars
        local resettable = {}
        local function Shared(variable, key, varType, label, set)
            local setting = K.Proxy("classBars" .. variable, varType, label, CB.DEFAULTS[key],
                function() return CB.Get(key) end, set or function(value) CB.Set(key, value) end)
            if setting then resettable[#resettable + 1] = { setting = setting, default = CB.DEFAULTS[key] } end
            return setting
        end
        local function Slider(variable, key, label, tip)
            local lim = CB.LIMITS[key]
            return Under(K.Slider(Shared(variable, key, NUMBER, label, function(v) CB.Set(key, math.floor(v + 0.5)) end), lim[1], lim[2], tip), main, On)
        end

        local _, class = UnitClass("player")
        local slots = CB.SlotsFor(class)
        local has = {}
        for _, slot in ipairs(slots) do has[slot] = true end

        Header("The whole display", "These apply to every bar together. Overall opacity fades the bars, their text and their effects as one; the background and border have an opacity of their own on the Appearance page.")
        Slider("Scale", "scale", "Scale", "How large the bars are as a whole, in percent. 100 is the sizes below.")
        Slider("Opacity", "opacity", "Overall opacity", "How solid the whole display is, in percent: the fill, the text and the effects. The background's own opacity is a separate setting on the Appearance page.")
        Slider("SegmentGap", "segmentGap", "Space between segments", "The gap between a segmented bar's cells, in pixels (combo points). The bar's background shows through it.")
        if has.secondary or has.tertiary then
            Slider("Gap", "gap", "Space between bars", "The gap between one bar and the next, in pixels.")
            Under(K.Dropdown(Shared("Placement", "placement", STRING, "Where the secondary bars go"), function() return CB.CHOICES.placement end,
                "Below or above puts combo points (and a Druid's mana bar) next to the main bar, so the bars move together. Its own place gives them a separate handle: move the main bar and the secondary bars independently while you are moving the bars."), main, On)
        end

        local NAMES = { primary = "Main bar", secondary = "Combo points bar", tertiary = "Druid mana bar" }
        local TIPS = {
            primary = "The bar for the power your character is using now (mana, rage, energy or focus).",
            secondary = "The segmented bar for combo points, on your target. Rogues, and Druids in Cat Form.",
            tertiary = "A thin mana bar for a Druid while another power is shown (Cat, Bear).",
        }
        for _, slot in ipairs(slots) do
            Header(NAMES[slot], TIPS[slot])
            local label = slot:sub(1, 1):upper() .. slot:sub(2)
            Under(K.Checkbox(Shared(label .. "On", slot .. "On", BOOL, "Show the " .. NAMES[slot]:lower(), function(v) CB.Set(slot .. "On", v and true or false) end),
                "Off: this bar is never drawn, whatever the rules on the General page say."), main, On)
            Slider(label .. "Width", slot .. "Width", "Width", "The bar's width in pixels, border included.")
            Slider(label .. "Height", slot .. "Height", "Height", "The bar's height in pixels, border included.")
        end

        Header("Reset", "Each reset says what it covers. Where the bars sit on your screen, the look and the effects are not changed by it.")
        K.ResetButton("Layout", resettable, function() CB.ResetGroup("layout") end,
            "Puts scale, opacity, spacing, placement and every bar's size and on/off back to their defaults. Where the bars sit on your screen, the look and the effects are kept.")
    end,
})

K.Page({
    key = "classBarsLook", name = "Class resource bar appearance", nav = "Appearance", parent = "classBars", order = 57,
    description = "The fill, the text, the background and border, and what your class's own resources do differently.",
    keywords = "texture gradient color fill smoothing font text outline background border class color override resource",
    when = function() return R.ClassBars ~= nil end,
    build = function()
        local CB = R.ClassBars
        local MS = R.MenuStyle
        local Header, Under = K.Header, K.Under
        local BOOL, STRING, NUMBER = K.BOOL, K.STRING, K.NUMBER
        local function On() return R:Enabled("classBars") end
        local main = K.switchRows.classBars
        local resettable = {}
        local function Shared(variable, key, varType, label, set)
            local setting = K.Proxy("classBars" .. variable, varType, label, CB.DEFAULTS[key],
                function() return CB.Get(key) end, set or function(value) CB.Set(key, value) end)
            if setting then resettable[#resettable + 1] = { setting = setting, default = CB.DEFAULTS[key] } end
            return setting
        end
        local function Pick(variable, key, label, tip, choices, parent, isOn, why)
            return Under(K.Dropdown(Shared(variable, key, STRING, label), choices, tip), parent or main, isOn or On, why)
        end
        local function Slide(variable, key, label, tip, parent, isOn, why)
            local lim = CB.LIMITS[key]
            return Under(K.Slider(Shared(variable, key, NUMBER, label, function(v) CB.Set(key, math.floor(v + 0.5)) end), lim[1], lim[2], tip), parent or main, isOn or On, why)
        end
        local function Swatch(variable, key, label, tip, parent, isOn, why)
            return Under(K.Swatch(Shared(variable, key, STRING, label), tip), parent or main, isOn or On, why)
        end

        Header("Fill", "What the filled part of a bar is drawn with. The gradient runs across the part that is filled.")
        Pick("Texture", "texture", "Bar texture",
            "Flat color is a plain fill. The rest are the textures LibSharedMedia has, so any addon that adds status bar textures adds them here, plus EllesmereUI's own while it is installed. A texture that has gone is drawn flat and stays chosen.",
            function() return MS.StatusBars.Choices(CB.Get("texture")) end)
        local style = Pick("FillStyle", "fillStyle", "Fill", "Solid is one color. Gradient shades from one color to another.",
            function() return CB.CHOICES.fillStyle end)
        local function Gradient() return On() and CB.Get("fillStyle") == "gradient" end
        local gradientWhy = function() return On() and "Greyed out: the fill is solid. Choose Gradient above." or "Greyed out: needs \"Show class resource bars\" turned on." end
        Pick("GradientDir", "gradientDir", "Gradient direction", "Which way the gradient runs across a bar.",
            function() return CB.CHOICES.gradientDir end, style, Gradient, gradientWhy)
        local source = Pick("ColorSource", "colorSource", "Fill color",
            "The resource's color is our own muted color for mana, rage, energy and so on (or the game's, for a power we have none for). Your class color uses the color the game gives your class. A color I choose uses the swatch below. A resource of your class can override this below.",
            function() return CB.CHOICES.colorSource end)
        local function Custom() return On() and CB.Get("colorSource") == "custom" end
        local customWhy = function() return On() and "Greyed out: the fill uses the resource's or your class color. Choose \"A color I choose\" above." or "Greyed out: needs \"Show class resource bars\" turned on." end
        local color = Swatch("Color", "color", "Custom color", "The fill color when \"A color I choose\" is used, and the start of a gradient.", source, Custom, customWhy)
        Swatch("Color2", "color2", "Gradient end color", "The color a gradient ends on when \"A color I choose\" is used.", color or source,
            function() return Gradient() and CB.Get("colorSource") == "custom" end,
            function() return On() and "Greyed out: needs a gradient fill and \"A color I choose\"." or "Greyed out: needs \"Show class resource bars\" turned on." end)
        Slide("Shade", "shade", "Gradient end brightness",
            "With the resource's or your class color, the gradient ends on that color at this brightness, in percent. Below 100 darkens it, above lightens it.", style,
            function() return Gradient() and CB.Get("colorSource") ~= "custom" end,
            function() return On() and "Greyed out: needs a gradient fill with the resource's or your class color." or "Greyed out: needs \"Show class resource bars\" turned on." end)
        Under(K.Checkbox(Shared("Smoothing", "smoothing", BOOL, "Ease the fill", function(v) CB.Set("smoothing", v and true or false) end),
            "The fill glides a short way to a new value instead of jumping. It only moves the picture: the numbers, the text and the show rules always use the real value. Off by default. Segmented bars never glide."), main, On)

        Header("Text", "The number on each bar. Fonts come from LibSharedMedia, so TwichUI's, EllesmereUI's and any other addon's are listed.")
        local TEXTS = { { "Primary", "primary", "Main bar text" }, { "Secondary", "secondary", "Combo points text" }, { "Tertiary", "tertiary", "Druid mana text" } }
        local className, class = UnitClass("player")
        local has = {}
        for _, slot in ipairs(CB.SlotsFor(class)) do has[slot] = true end
        for _, t in ipairs(TEXTS) do
            if has[t[2]] then
                Pick(t[1] .. "Text", t[2] .. "Text", t[3],
                    "What the bar says. Current value, Current / maximum, Percentage or Hidden. A segmented bar counts its lit segments, and has no percentage. A resource of your class can override this below.",
                    function() return CB.CHOICES.text end)
            end
        end
        Pick("Font", "font", "Font", "The text's typeface. A font that has gone is drawn with the game's own and stays chosen.",
            function() return MS.Fonts.Choices(CB.Get("font"), { { "default", "Game font (default)" } }) end)
        Slide("FontSize", "fontSize", "Text size", "The text's size in pixels.")
        Pick("FontOutline", "fontOutline", "Text outline", "Outline and Thick outline draw a line round each letter. Shadow is a soft dark edge. None leaves the text bare.",
            function() return CB.CHOICES.fontOutline end)
        Swatch("TextColor", "textColor", "Text color", "The color of the bar text.")
        Pick("TextPlace", "textPlace", "Text position", "Where the text sits on a bar.", function() return CB.CHOICES.textPlace end)

        Header("Background and border", "Behind and around each bar. Only these fade with their own opacity; the fill and text keep theirs.")
        local look = K.Appearance(CB.Look, "classBarsLook", "bar", nil, nil, "Background and border",
            "Puts the background and border (texture, color, opacity and thickness) back to their defaults. Fill, text and every other setting are kept.", main, On)

        Header("Reset", "Each reset says what it covers. The background and border have a reset of their own above, and each of your class's resources below.")
        K.ResetButton("Fill and text", resettable, function() CB.ResetGroup("appearance") end,
            "Puts the fill, gradient, smoothing and text settings back to their defaults. The background and border, the layout, the effects and what your class's resources do differently are kept.")

        -- What this class's own resources do differently. Stored per class and resource, so another class's are never touched.
        local CBR = R.ClassBarResources
        local classWord = className or "Your class"
        local function InheritChoices(list, extra)
            local out = { { "inherit", "Same as the shared style" } }
            for _, c in ipairs(list) do out[#out + 1] = { c[1], c[2] } end
            for _, c in ipairs(extra or {}) do out[#out + 1] = c end
            return out
        end
        for _, r in ipairs(class and CBR.Offered(class) or {}) do
            local ovKey = CBR.OverrideKey(class, r.key)
            local id = "classBarsOv" .. r.key:gsub("_", "")
            Header((classWord .. ": " .. r.label), "What your " .. classWord .. "'s " .. r.label:lower() .. " does differently from the shared style above. Only what you set here is different; everything else follows the shared style. It is saved for this class and resource, so other classes and resources are unaffected.")
            local function Note(row, field, shared)
                K.Note(row, function()
                    if CB.GetOverride(ovKey, field) ~= nil then return OVERRIDE_TIP end
                    return "Following the shared style" .. (shared and (": " .. shared()) or ".")
                end)
                return row
            end
            local sourceRow = Note(Under(K.Dropdown(K.Proxy(id .. "Source", STRING, r.label .. " fill color", "inherit",
                function() return CB.GetOverride(ovKey, "colorSource") or (CB.GetOverride(ovKey, "color") and "custom") or "inherit" end,
                function(value) CB.SetOverride(ovKey, "colorSource", value ~= "inherit" and value or nil)
                    if value == "inherit" then CB.SetOverride(ovKey, "color", nil) end end),
                function() return InheritChoices(CB.CHOICES.colorSource) end,
                "Where this resource's fill color comes from. Same as the shared style follows the Fill color above."), main, On),
                "colorSource", function() for _, c in ipairs(CB.CHOICES.colorSource) do if c[1] == CB.Get("colorSource") then return c[2] end end end)
            Under(K.Swatch(K.Proxy(id .. "Color", STRING, r.label .. " custom color", nil,
                function() return CB.GetOverride(ovKey, "color") or CB.Get("color") end,
                function(value) CB.SetOverride(ovKey, "colorSource", "custom"); CB.SetOverride(ovKey, "color", value) end),
                "The color this resource's fill uses when \"A color I choose\" is used. Choosing a color here also switches this resource to it."), sourceRow or main,
                function() return On() and (CB.GetOverride(ovKey, "colorSource") == "custom" or CB.GetOverride(ovKey, "color") ~= nil) end,
                function() return On() and "Greyed out: this resource's fill is not set to \"A color I choose\"." or "Greyed out: needs \"Show class resource bars\" turned on." end)
            Note(Under(K.Dropdown(K.Proxy(id .. "Text", STRING, r.label .. " text", "inherit",
                function() return CB.GetOverride(ovKey, "text") or "inherit" end,
                function(value) CB.SetOverride(ovKey, "text", value ~= "inherit" and value or nil) end),
                function() return InheritChoices(CB.CHOICES.text) end,
                "What this resource's bar says. Same as the shared style follows the text setting for its bar above."), main, On), "text")
            Note(Under(K.Dropdown(K.Proxy(id .. "Show", STRING, r.label .. " shows", "inherit",
                function() return CB.GetOverride(ovKey, "show") or "inherit" end,
                function(value) CB.SetOverride(ovKey, "show", value ~= "inherit" and value or nil) end),
                function() return InheritChoices(CB.CHOICES.show, { { "never", "Never show this resource" } }) end,
                "When this resource's bar shows. Same as the shared style follows \"Show the bars\" on the General page. Never hides this resource's bar altogether. The hide rules for being dead, mounted or in a vehicle still apply."), main, On), "show",
                function() for _, c in ipairs(CB.CHOICES.show) do if c[1] == CB.Get("show") then return c[2] end end end)
            local reset = K.Button("Reset " .. r.label, "Reset", function()
                R.Interact.Confirm("TWICHUI_CLASS_BARS_RESET_OVERRIDE",
                    ("Reset what your %s's %s does differently?\n\nIts fill color, text and when it shows follow the shared style again. Every other resource and class, and the shared style itself, are not changed."):format(classWord, r.label:lower()),
                    function()
                        CB.ClearOverride(ovKey)
                        K.RefreshValues()
                    end, { accept = "Reset" })
            end, "Makes this resource follow the shared style again for every setting above. Nothing else is changed.")
            if reset then reset.reset = true end
        end
    end,
})

K.Page({
    key = "classBarsEffects", name = "Class resource bar effects", nav = "Effects", parent = "classBars", order = 58,
    description = "Optional touches when a resource reaches full. Off by default; the bars are complete without them.",
    keywords = "effect pulse accent particle frost mage motes reduced motion animation threshold test",
    when = function() return R.ClassBars ~= nil end,
    build = function()
        local CB = R.ClassBars
        local Header, Under = K.Header, K.Under
        local BOOL, NUMBER = K.BOOL, K.NUMBER
        local function On() return R:Enabled("classBars") end
        local resettable = {}
        local function Shared(variable, key, varType, label, set)
            local setting = K.Proxy("classBars" .. variable, varType, label, CB.DEFAULTS[key],
                function() return CB.Get(key) end, set or function(value) CB.Set(key, value) end)
            if setting then resettable[#resettable + 1] = { setting = setting, default = CB.DEFAULTS[key] } end
            return setting
        end
        local main = K.switchRows.classBars
        local function Check(variable, key, label, tip, parent, isOn, why)
            return Under(K.Checkbox(Shared(variable, key, BOOL, label, function(v) CB.Set(key, v and true or false) end), tip), parent, isOn, why)
        end
        local function EffectsOn() return On() and CB.Get("effects") end
        local why = function() return On() and "Greyed out: needs \"Effects\" turned on." or "Greyed out: needs \"Show class resource bars\" turned on." end

        Header("Effects", "Short touches that play once when a resource reaches the threshold from below, never on every update, never on login or when you change target, and never while the bars are hidden. They are drawn over the fill and under the text with flat textures and, for the Mage, a few small glints; they are particle-like, not real particles, and use no model or sound.")
        local effects = Check("Effects", "effects", "Effects",
            "Turns the effects on. Off, nothing is created and nothing runs.", main, On)
        Check("EffectsAccent", "effectsAccent", "Highlight at the threshold",
            "A brief soft highlight over a bar when its resource rises to the threshold below: your combo points complete, your rage reaches the top, your mana comes back to full. It plays again only after the resource has dropped well below the threshold.", effects, EffectsOn, why)
        Check("EffectsClass", "effectsClass", "My class's touch",
            "Adds the class touch where there is one. Mage: a few frost glints rise from the mana bar when mana comes back to full. Other classes have none yet, so this changes nothing for them.", effects, EffectsOn, why)
        Under(K.Slider(Shared("EffectsThreshold", "effectsThreshold", NUMBER, "Threshold", function(v) CB.Set("effectsThreshold", math.floor(v + 0.5)) end),
            CB.LIMITS.effectsThreshold[1], CB.LIMITS.effectsThreshold[2],
            "The level, in percent of the bar, a resource rises to for the highlight. 100 is full. For combo points, 100 is every segment lit."), effects, EffectsOn, why)
        Check("EffectsReducedMotion", "effectsReducedMotion", "Reduced motion",
            "Nothing moves: the highlight becomes a brief steady one and the Mage's glints are not drawn. This is the effects' own setting; it does not change the notification or settings window motion settings.", effects, EffectsOn, why)

        Header("Try it", "Plays what is turned on, once, on the preview bars. The preview uses made-up numbers and changes nothing real.")
        Under(K.Button("Test the effects", "Play", function()
            local n, reason = CB.TestEffect()
            if n == false then
                R.Print(reason == "effects-off" and "turn on Effects first." or reason == "combat" and "the preview waits until you are out of combat." or "turn on the class resource bars first.")
            elseif n == 0 then
                R.Print("nothing is turned on to play: turn on a highlight or a class touch.")
            end
            K.RefreshOverview()
        end, "Shows the preview bars if they are not up and plays each effect that is turned on once. Drag the sample level on the General page across the threshold to see the real trigger."), effects, EffectsOn, why)

        Header("Reset", "Puts only the effects settings back.")
        K.ResetButton("Effects", resettable, function() CB.ResetGroup("effects") end,
            "Puts the effects switch, the highlight, the class touch, the threshold and reduced motion back to their defaults (effects off). Nothing else is changed.")
    end,
})
