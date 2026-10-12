-- TwichUI: options in Esc > Options > AddOns > TwichUI (/twichui)
-- The one home for TwichUI's settings, built from Blizzard's own controls.
-- A short overview page links to one page per feature (subcategories of
-- TwichUI). Rarely changed options sit under an "Advanced" header that only
-- shows with "Show advanced options" (on the overview) on; they keep their
-- values (and keep working) while hidden. Stat weights are a page under Gear
-- comparison (gear/Window.lua), since a ranked list and a table of numbers
-- don't fit the standard controls.

local R = TwichUI

local function AskReload()
    StaticPopupDialogs.TWICHUI_RELOAD = {
        text = "TwichUI: this change takes effect after reloading your UI. Reload now?",
        button1 = RELOADUI or "Reload", button2 = "Later",
        OnAccept = ReloadUI,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("TWICHUI_RELOAD")
end

-- Addons TwichUI can skin. addon = folder name.
local SKINS = {
    { key = "attuneSkin", addon = "Attune", label = "Attune",
      what = "Gives the Attune window (/attune) and its quest panels the EllesmereUI look." },
    { key = "auctionatorSkin", addon = "Auctionator", label = "Auctionator",
      what = "Gives Auctionator's tabs, buttons, lists and boxes the EllesmereUI look. Also needs EllesmereUI's Auction House window skin." },
    { key = "foreverDungeonJournalSkin", addon = "ForeverDungeonJournal", label = "Dungeon Journal",
      what = "Gives the Forever Dungeon Journal window (/fj) the EllesmereUI look." },
    { key = "whatsTrainingSkin", addon = "WhatsTraining", label = "WhatsTraining",
      what = "Gives WhatsTraining's floating window (/wt) the EllesmereUI look." },
}

local function AddonState(addon)
    return R.Setups and R.Setups.AddonState(addon) or "ready"
end

local function Loaded(addon)
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon) or false
end

-- What a skin is doing right now: a word or two, and a sentence (or nil).
-- onAtLoad: whether the skin's toggle was on when the UI loaded.
local function SkinStatus(skin, onAtLoad)
    local state = AddonState(skin.addon)
    if state == "missing" then return R.GREY .. "Not installed|r", "Install " .. skin.label .. " to use this skin." end
    if state == "disabled" then return R.GREY .. "Turned off|r", skin.label .. " is turned off in your AddOns list." end
    local on = R:Enabled(skin.key)
    if on ~= onAtLoad then
        return R.GOLD .. (on and "On" or "Off") .. " after reload|r", "Reload your UI for this to take effect."
    end
    if not on then return R.GREY .. "Off|r", nil end
    if AddonState("EllesmereUI") == "missing" then
        return R.GREY .. "Waiting for EllesmereUI|r", "EllesmereUI isn't installed. The skin only works with it."
    end
    if not R.S then
        return R.GREY .. "Waiting for EllesmereUI|r", "EllesmereUI hasn't switched on TwichUI's skins. Check its third-party addon skin options."
    end
    if not Loaded(skin.addon) then
        return R.GREEN .. "Ready|r", "Applies when " .. skin.label .. " loads."
    end
    return R.GREEN .. "Active|r", nil
end

local function Build()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterVerticalLayoutSubcategory) then return end
    local root, rootLayout = Settings.RegisterVerticalLayoutCategory("TwichUI")
    R.settingsCategory = root
    R.settingsCategories = { overview = root }   -- R:OpenSettings(key)

    -- Pages are made up front so the category list keeps this order. The
    -- helpers below add to whichever page Use() last selected; the page is
    -- built in one go, so nothing is added after the next Use().
    local pages = { overview = { category = root, layout = rootLayout } }
    -- parentKey: a page of its own under another page (the list shows it indented, under that page)
    local function NewPage(key, name, parentKey)
        local parent = parentKey and pages[parentKey] and pages[parentKey].category or root
        local category, layout = Settings.RegisterVerticalLayoutSubcategory(parent, name)
        pages[key] = { category = category, layout = layout }
        R.settingsCategories[key] = category
        if parent ~= root and category.SetExpanded and parent.SetExpanded then parent:SetExpanded(true) end
    end
    NewPage("gear", "Gear comparison")
    NewPage("notifications", "Notifications")
    if R.QoL then NewPage("qol", "Quality of life") end
    NewPage("food", "Food and drink")
    if R.MageTravel and R.MageTravel.ForPlayer() then NewPage("mage", "Mage") end   -- Mages only
    NewPage("chronicle", "Journey Chronicle")
    if R.Pins then NewPage("pins", "Party pins") end
    NewPage("auction", "Auction House")
    NewPage("skins", "Addon skins")
    if R.RestedXPSkin then NewPage("restedxp", "RestedXP guide window", "skins") end
    NewPage("sharing", "Configuration sharing")
    if R.Diag and R.DiagWindow then NewPage("troubleshooting", "Troubleshooting") end

    local category, layout
    local function Use(key) category, layout = pages[key].category, pages[key].layout end
    Use("overview")

    local VarType = Settings.VarType or {}
    local BOOL = VarType.Boolean or "boolean"
    local STRING = VarType.String or "string"
    local NUMBER = VarType.Number or "number"

    TwichUIDB.ui = TwichUIDB.ui or {}
    if TwichUIDB.ui.showAdvanced == nil then TwichUIDB.ui.showAdvanced = false end
    local function AdvancedShown() return TwichUIDB.ui.showAdvanced == true end

    -- Hidden until "Show advanced options" is on. The setting keeps its value.
    local function Advanced(initializer)
        if initializer and initializer.AddShownPredicate then initializer:AddShownPredicate(AdvancedShown) end
        return initializer
    end

    -- Greyed out while the parent checkbox is off. The row's saved value is left alone; its tooltip
    -- says why it is greyed out, for as long as it is. why: a sentence, or a function returning one
    -- (or nil for the usual "needs <parent> turned on").
    local function Under(initializer, parent, isOn, why)
        if initializer and parent and initializer.SetParentInitializer then
            initializer:SetParentInitializer(parent, isOn)
            local base = initializer.GetTooltip
            initializer.GetTooltip = function(self)
                local tip = base and base(self) or self.data.tooltip
                if isOn and not isOn() then
                    local reason = type(why) == "function" and why() or (type(why) == "string" and why or nil)
                    reason = reason or ("Greyed out: needs \"" .. tostring(parent:GetName()) .. "\" turned on.")
                    return (tip and (tip .. "\n\n") or "") .. reason
                end
                return tip
            end
        end
        return initializer
    end

    -- The overview's feature rows: a name, a short status, and a button to that
    -- page. The status is rewritten whenever a toggle changes (no polling).
    local overviewRows = {}
    local function RefreshOverview()
        for _, row in ipairs(overviewRows) do
            if row.initializer.data then
                row.initializer.data.name = row.label .. "   " .. row.status()
            end
        end
    end

    local function Header(text, tooltip)
        if CreateSettingsListSectionHeaderInitializer then
            local initializer = CreateSettingsListSectionHeaderInitializer(text, tooltip)
            layout:AddInitializer(initializer)
            return initializer
        end
    end

    local function Toggle(key, label, tooltip, needsReload, onChange)
        if needsReload then tooltip = tooltip .. "\n\nTakes effect after you reload your UI." end
        local setting = Settings.RegisterAddOnSetting(category, "TWICHUI_" .. key, key, TwichUIDB.modules, BOOL, label, R.DEFAULT_MODULES[key])
        local initializer = Settings.CreateCheckbox(category, setting, tooltip)
        if setting.SetValueChangedCallback then
            setting:SetValueChangedCallback(function()
                if needsReload then AskReload() end
                if onChange then onChange() end
                RefreshOverview()
                if R.Window then R.Window:Refresh() end
            end)
        end
        return initializer, setting
    end

    local function Button(label, buttonText, onClick, tooltip)
        if CreateSettingsButtonInitializer then
            local initializer = CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true)
            layout:AddInitializer(initializer)
            return initializer
        end
    end

    -- A setting stored somewhere other than the modules table.
    local function Proxy(variable, varType, label, default, get, set)
        if not Settings.RegisterProxySetting then return end
        return Settings.RegisterProxySetting(category, "TWICHUI_" .. variable, varType, label, default, get, set)
    end

    local function ProxyToggle(variable, label, tooltip, default, get, set)
        local setting = Proxy(variable, BOOL, label, default, get, set)
        return setting and Settings.CreateCheckbox(category, setting, tooltip)
    end

    -- options: { { value, label, tooltip }, ... } or a function returning that.
    local function Choice(variable, label, tooltip, varType, default, get, set, options)
        local setting = Proxy(variable, varType, label, default, get, set)
        if not (setting and Settings.CreateDropdown and Settings.CreateControlTextContainer) then return end
        return Settings.CreateDropdown(category, setting, function()
            local container = Settings.CreateControlTextContainer()
            for _, option in ipairs(type(options) == "function" and options() or options) do
                container:Add(option[1], option[2], option[3])
            end
            return container:GetData()
        end, tooltip)
    end

    -- One look's controls (modules/MenuStyle.lua): background and border texture, color and opacity,
    -- border thickness, a preview and a reset. style: the look; prefix: its settings' names; noun: what
    -- it is the look of ("menu", "panel"); parent, isOn: the switch it is greyed out under, if any.
    -- preview: nil for no Preview button. resetLabel: nil for no Reset button (the caller resets the
    -- returned { setting, default } list itself). options, all optional: order: the rows' suffixes in the
    -- order to list them; advanced: { [suffix] = true } for rows under an Advanced header (shown with
    -- "Show advanced options"; labels: { [suffix] = a label of its own } where a page lists these rows beside
    -- another look's and they must be told apart.
    local function Appearance(style, prefix, noun, previewTip, preview, resetLabel, resetTip, parent, isOn, options)
        local resettable = {}   -- { setting, default }, for Reset
        local advanced = options and options.advanced
        local function Add(initializer, suffix)
            if advanced and advanced[suffix] then Advanced(initializer) end
            if parent and initializer then Under(initializer, parent, isOn) end
            if initializer and options and options.decorate then options.decorate(suffix, initializer) end
            return initializer
        end
        local function Remember(suffix, varType, label, key)
            if options and options.labels and options.labels[suffix] then label = options.labels[suffix] end
            local setting = Proxy(prefix .. suffix, varType, label, style.DEFAULTS[key],
                function() return style.Get(key) end, function(value) style.Set(key, value) end)
            if setting then resettable[#resettable + 1] = { setting = setting, default = style.DEFAULTS[key] } end
            return setting
        end
        local function Textures(suffix, key, label, tooltip, choices)
            local setting = Remember(suffix, STRING, label, key)
            if setting and Settings.CreateDropdown and Settings.CreateControlTextContainer then
                Add(Settings.CreateDropdown(category, setting, function()
                    local container = Settings.CreateControlTextContainer()
                    for _, choice in ipairs(choices()) do container:Add(choice[1], choice[2]) end
                    return container:GetData()
                end, tooltip), suffix)
            end
        end
        local function Swatch(suffix, key, label, tooltip)
            local setting = Remember(suffix, STRING, label, key)
            if setting and Settings.CreateColorSwatch then Add(Settings.CreateColorSwatch(category, setting, tooltip), suffix) end
        end
        local function Slider(suffix, key, label, tooltip)
            local limit = style.LIMITS[key]
            local setting = Remember(suffix, NUMBER, label, key)
            if not (setting and Settings.CreateSlider and Settings.CreateSliderOptions) then return end
            local sliderOptions = Settings.CreateSliderOptions(limit[1], limit[2], 1)
            if MinimalSliderWithSteppersMixin and sliderOptions.SetLabelFormatter then
                sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            end
            Add(Settings.CreateSlider(category, setting, sliderOptions, tooltip), suffix)
        end
        local rows = {
            BgTexture = function()
                Textures("BgTexture", "bgTexture", "Background texture",
                    "None leaves the " .. noun .. " see-through apart from its border. Solid color is a flat fill. The rest are the game's own backgrounds, the textures EllesmereUI offers for its own backgrounds (while it is installed), and any LibSharedMedia background or status bar texture, so an addon that adds textures there adds them here. A texture is tinted by the color below; choose white to see it as it is.",
                    style.BackgroundChoices)
            end,
            BgColor = function()
                Swatch("BgColor", "bgColor", "Background color", "The color of the background, or the tint of a textured one.")
            end,
            BgOpacity = function()
                Slider("BgOpacity", "bgOpacity", "Background opacity",
                    "How solid the background is, in percent. Only the background fades; the " .. noun .. "'s text, icons and border stay as they are.")
            end,
            BorderTexture = function()
                Textures("BorderTexture", "borderTexture", "Border texture",
                    "None draws no border. Solid line is a plain line. The rest are the game's own borders, EllesmereUI's own border textures while it is installed, and any LibSharedMedia border. Picking one sets a thickness that suits it unless you have set your own; change it below.",
                    style.BorderChoices)
            end,
            BorderSize = function()
                Slider("BorderSize", "borderSize", "Border thickness",
                    "The border's width in screen pixels, so it looks the same at any UI scale. 0 for none. A textured border needs about 8 or more to read well. It never covers the " .. noun .. "'s text.")
            end,
            BorderColor = function()
                Swatch("BorderColor", "borderColor", "Border color", "The color of the border, or the tint of a textured one.")
            end,
            BorderOpacity = function()
                Slider("BorderOpacity", "borderOpacity", "Border opacity",
                    "How solid the border is, in percent. Only the border fades.")
            end,
            -- only for a look that names them (they have defaults of their own)
            BgTiling = function()
                Textures("BgTiling", "bgTiling", "Background tiling",
                    "How a textured background fills the " .. noun .. ". Automatic repeats the game's and LibSharedMedia's backgrounds and stretches the textures EllesmereUI and status bars offer, as they are drawn there. Repeat tiles any texture at the size below; Stretch fits it to the " .. noun .. ". A plain color is neither.",
                    function() return R.ChronicleAppearance and R.ChronicleAppearance.TILING_CHOICES or {} end)
            end,
            BgTileSize = function()
                Slider("BgTileSize", "bgTileSize", "Background tile size",
                    "How big one repeat of a tiled background is, in screen pixels.")
            end,
            BgInset = function()
                Slider("BgInset", "bgInset", "Background inset",
                    "How far the background sits in from the " .. noun .. "'s edge, in screen pixels, so a thick or textured border has a margin of plain " .. noun .. " behind it. Not the same as the border's own thickness or the content padding.")
            end,
        }
        local headed = false
        for _, suffix in ipairs(options and options.order or
            { "BgTexture", "BgColor", "BgOpacity", "BorderTexture", "BorderSize", "BorderColor", "BorderOpacity" }) do
            if advanced and advanced[suffix] and not headed then
                headed = true
                Advanced(Header(options.advancedHeader or "Advanced look", options.advancedTip or "Textures, thickness and opacity."))
            end
            rows[suffix]()
        end
        if preview then Add(Button("Preview", "Show or hide", preview, previewTip), "Preview") end
        if resetLabel then
            Add(Button(resetLabel, "Reset", function()
                for _, entry in ipairs(resettable) do
                    if entry.setting.SetValue then pcall(entry.setting.SetValue, entry.setting, entry.default) end
                end
                style.Reset()   -- and forget the saved values altogether, so the defaults are used as they come
            end, resetTip), "Reset")
        end
        return resettable
    end

    -----------------------------------------------------------------------
    -- Feature pages first; the overview is filled in at the end, once each
    -- page's status is known.
    Use("gear")
    Header("Upgrade hints", "Quiet upgrade hints for your class and main talent tree. A rough estimate from item stats, not a simulation. Nothing to set up first: TwichUI starts from its own rough stat weights for each class and tree, which you can change under Stat weights if you follow a guide.")
    Toggle("gearHints", "Upgrade hints in item tooltips",
        "Adds a short line to an item's tooltip when it looks like an upgrade for your class and main talent tree, such as \"Likely upgrade for Fury\". Hold Shift (your compare-items key) to see why.\n\nWorks as soon as it is on, using TwichUI's built-in rough stat weights for your class and tree; you don't have to enter anything. No hint is shown for a class TwichUI has no weights for.\n\n\"Use:\" and \"Chance on hit:\" effects aren't weighed.",
        false)
    local bags = Toggle("gearBagIcons", "Mark upgrades in my bags",
        "A small mark in the corner of bag slots holding gear the tooltip would call an upgrade, fainter for possible upgrades. Works with Blizzard's bags and EllesmereUI Bags.",
        false, function() if R.GearBags then R.GearBags.Refresh() end end)

    local P, D, B = R.GearPrefs, R.GearData, R.GearBags
    if P and D then
        Choice("gearTree", "Weigh gear for",
            "The talent tree this character's gear is weighed for. Automatic uses the tree with the most talent points when one clearly leads. Until you have spent points, while two trees are tied, or if your talents can't be read, it uses your class's usual levelling tree, and the reasoning (hold Shift over an item) says so. Choose a tree here to override it; the choice is kept for this character only.",
            NUMBER, 0,
            function() return P.TreeChoice() or 0 end,
            function(value) P.SetTreeChoice(value ~= 0 and value or nil) end,
            function()
                local trees, _, auto = D.Trees()
                local list = { { 0, auto and ("Automatic (" .. auto.name .. ")") or "Automatic" } }
                for _, tree in ipairs(trees or {}) do list[#list + 1] = { tree.skillLine, tree.name } end
                return list
            end)
    end
    if R.GearWindow then
        Button("Stat weights", "Edit", function() R.GearWindow:Show() end,
            "Optional. How each of your talent trees values stats. Each starts from TwichUI's rough weights; change them only if you want hints to follow a guide: rank the stats it lists (a stat priority), or edit the numbers (stat weights). A priority with nothing ranked yet falls back to the tree's weights.")
    end
    if P then
        Advanced(Header("Advanced"))
        Advanced(ProxyToggle("gearPossible", "Show possible upgrades too",
            "Also mark gear that looks a little better, or better apart from effects the estimate can't weigh. Off: only likely upgrades and empty slots.",
            true, function() return P.Get("glancePossible") and true or false end, function(value) P.Set("glancePossible", value) end))
        Advanced(ProxyToggle("gearFuture", "Hint at gear for higher levels",
            "Gear you can't wear yet only because of its level gets a hint with that level, such as \"Likely upgrade at level 32\". Handy at the auction house.",
            true, function() return P.Get("futureLevels") and true or false end, function(value) P.Set("futureLevels", value) end))

        local function Gain(key)
            local numbers = P.STRICTNESS[key]
            return ("Likely from %d%% better than what you wear, possible from %d%%."):format(
                math.floor(numbers.likely * 100 + 0.5), math.floor(numbers.possible * 100 + 0.5))
        end
        Advanced(Choice("gearStrictness", "How big a gain counts",
            "How much better than what you wear an item must look before it gets a hint.",
            STRING, "balanced",
            function() return P.Get("strictness") end, function(value) P.Set("strictness", value) end,
            {
                { "cautious", "Cautious", Gain("cautious") },
                { "balanced", "Balanced", Gain("balanced") },
                { "eager", "Eager", Gain("eager") },
            }))
        Advanced(Choice("gearReveal", "Show the reasoning",
            "What to hold over an item to see why it got its hint: what it's compared with, the stat changes that mattered most and the weights used.",
            STRING, "compare",
            function() return P.Get("reveal") end, function(value) P.Set("reveal", value) end,
            {
                { "compare", "Hold Shift", "Your compare-items key." },
                { "alt", "Hold Alt" },
                { "ctrl", "Hold Ctrl" },
                { "always", "Always", "The reasoning shows under every item you could wear." },
            }))
        if B then
            local stylePreview
            local styles = {}
            for i, style in ipairs(B.STYLES) do styles[i] = { style.key, style.label } end
            local styleRow = Choice("gearBagStyle", "Bag mark style",
                "The mark on upgrades in your bags. All use the game's own art. The square beside the list shows how it looks on a bag slot.",
                STRING, "gilded",
                function() return P.Get("bagStyle") end,
                function(value)
                    P.Set("bagStyle", value)
                    if stylePreview then B.ApplyStyle(stylePreview.mark, value) end
                end,
                styles)
            -- A preview slot beside the dropdown. Setting rows are recycled, so
            -- the slot is made once per row frame and tracked only while shown.
            if styleRow and styleRow.InitFrame then
                local initFrame, resetter = styleRow.InitFrame, styleRow.Resetter
                styleRow.InitFrame = function(self, frame)
                    initFrame(self, frame)
                    local slot = frame.TwichUIStylePreview
                    if not slot then
                        slot = CreateFrame("Frame", nil, frame)
                        slot:SetSize(26, 26)
                        slot.back = slot:CreateTexture(nil, "BACKGROUND")
                        slot.back:SetAllPoints()
                        slot.back:SetColorTexture(0.05, 0.05, 0.05, 0.9)
                        slot.mark = slot:CreateTexture(nil, "OVERLAY")
                        slot.mark:SetPoint("TOPLEFT", 1, -1)
                        frame.TwichUIStylePreview = slot
                    end
                    slot:ClearAllPoints()
                    slot:SetPoint("RIGHT", frame, "CENTER", -90, 0)
                    slot:SetFrameLevel(frame:GetFrameLevel() + 5)
                    B.ApplyStyle(slot.mark, P.Get("bagStyle"))
                    slot:Show()
                    stylePreview = slot
                end
                styleRow.Resetter = function(self, frame)
                    if resetter then resetter(self, frame) end
                    if frame.TwichUIStylePreview then frame.TwichUIStylePreview:Hide() end
                    if stylePreview == frame.TwichUIStylePreview then stylePreview = nil end
                end
            end
            Under(Advanced(styleRow), bags, function() return R:Enabled("gearBagIcons") end)
        end
    end

    if R.GearWindow and R.GearWindow.Register then R.GearWindow:Register(pages.gear.category) end

    -----------------------------------------------------------------------
    Use("skins")
    Header("EllesmereUI look", "Gives these addons the EllesmereUI look. Needs EllesmereUI with its third-party addon skins on. TwichUI only skins the addons listed here.")
    -- Each skin's tooltip ends with its status, kept current by the events
    -- that can change it (no polling).
    local skinRows = {}
    local function RefreshSkinStatus()
        for _, row in ipairs(skinRows) do
            local status, detail = SkinStatus(row.skin, row.onAtLoad)
            if row.initializer.data then
                row.initializer.data.tooltip = row.skin.what .. "\n\nTakes effect after you reload your UI.\n\nStatus: " .. status .. (detail and ("\n" .. detail) or "")
            end
        end
        RefreshOverview()
    end
    for _, skin in ipairs(SKINS) do
        local installed = AddonState(skin.addon) ~= "missing"
        local label = installed and skin.label or (skin.label .. "  " .. R.GREY .. "(not installed)|r")
        local initializer = Toggle(skin.key, label, skin.what, true, RefreshSkinStatus)
        if initializer then
            skinRows[#skinRows + 1] = { skin = skin, initializer = initializer, onAtLoad = R:Enabled(skin.key) }
            if not installed and initializer.AddModifyPredicate then
                initializer:AddModifyPredicate(function() return false end)
            end
        end
    end
    RefreshSkinStatus()
    R:OnSkin(RefreshSkinStatus)
    R:On("PLAYER_LOGIN", RefreshSkinStatus)
    R:On("ADDON_LOADED", function(name)
        for _, skin in ipairs(SKINS) do
            if name == skin.addon then RefreshSkinStatus() return end
        end
    end)

    -----------------------------------------------------------------------
    -- RestedXP: its own look, set here. Not through EllesmereUI, which it doesn't need.
    -- Its settings are a page of their own under this one (they are many): a short pointer here.
    local RS = R.RestedXPSkin
    if RS then
        Header("RestedXP guide window", "Gives the RestedXP Guides window a TwichUI look, and its waypoint arrow a shape, color and size of your choosing. Its settings are on a page of their own, under this one.")
        Button("RestedXP guide window", "Open its settings", function() R:OpenSettings("restedxp") end,
            "Opens the RestedXP guide window page, under Addon skins: the switch, the look, text, spacing, scroll bar, header and footer, and the waypoint arrow.")
        Use("restedxp")
        Header("RestedXP guide window", "Gives the RestedXP Guides window a TwichUI look: a background and border, text colors, fonts and sizes, a quieter header and footer, and a slim scroll bar; and its waypoint arrow a shape, color and size of your choosing. It never changes guide content, progress, step completion or the window's position and size. Works with or without EllesmereUI.")
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
        local function RestedXPStatus()
            local state = RS.Status()
            local text = STATUS[state.code] or { state.code }
            local color = (state.code == "active" and R.GREEN) or (state.code == "off" and R.GREY) or R.GOLD
            return color .. text[1] .. "|r", text[2]
        end
        local rxpBase = "Gives the RestedXP guide window the TwichUI look. Turning it on makes TwichUI the theme RestedXP uses (it remembers the one you had); turning it off puts that one back. Everything below is TwichUI's look; RestedXP's own settings are unchanged."
        local rxpToggle, rxpSwitch = Toggle("restedxpSkin", "Skin the RestedXP guide window", rxpBase, false, function()
            RS.OnSwitch()
            RefreshOverview()
        end)
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

        local resettable = Appearance(RS.Look, "restedxpLook", "window", nil, nil, nil, nil, rxpToggle, RxpOn, {
            order = { "BgColor", "BorderColor", "BgTexture", "BgOpacity", "BorderTexture", "BorderSize", "BorderOpacity" },
            advanced = { BgTexture = true, BgOpacity = true, BorderTexture = true, BorderSize = true, BorderOpacity = true },
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
        local function TextSwatch(variable, key, label, tooltip, isAdvanced)
            local setting = TextSetting(variable, STRING, label, key)
            if setting and Settings.CreateColorSwatch then
                local row = Settings.CreateColorSwatch(category, setting, tooltip)
                if isAdvanced then Advanced(row) end
                Under(row, rxpToggle, RxpOn)
            end
        end
        -- common: a plain choice rather than one under Advanced
        local function TextChoice(variable, key, label, tooltip, choices, common)
            local setting = TextSetting(variable, STRING, label, key)
            if setting and Settings.CreateDropdown and Settings.CreateControlTextContainer then
                local row = Settings.CreateDropdown(category, setting, function()
                    local container = Settings.CreateControlTextContainer()
                    for _, choice in ipairs(choices(RS.Text.Get(key))) do container:Add(choice[1], choice[2]) end
                    return container:GetData()
                end, tooltip)
                if not common then Advanced(row) end
                Under(row, rxpToggle, RxpOn)
                return row
            end
        end
        local function TextToggle(variable, key, label, tooltip, isAdvanced)
            local setting = TextSetting(variable, BOOL, label, key)
            if setting and Settings.CreateCheckbox then
                local row = Settings.CreateCheckbox(category, setting, tooltip)
                if isAdvanced then Advanced(row) end
                Under(row, rxpToggle, RxpOn)
                return row
            end
        end
        local function TextSlider(variable, key, label, tooltip, parent, isOn, why)
            local limit = RS.Text.LIMITS[key]
            local setting = TextSetting(variable, NUMBER, label, key)
            if not (setting and limit and Settings.CreateSlider and Settings.CreateSliderOptions) then return end
            local options = Settings.CreateSliderOptions(limit[1], limit[2], 1)
            if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            end
            return Under(Settings.CreateSlider(category, setting, options, tooltip), parent or rxpToggle, isOn or RxpOn, why)
        end
        TextSwatch("TitleColor", "titleColor", "Title text color",
            "The color of the guide's title, the footer and each step's number tab. Colors RestedXP gives meaning to in a step's own text (warnings, objectives, links) are not changed.")
        TextSwatch("BodyColor", "bodyColor", "Step text color",
            "The base color of the step and objective text. Colors RestedXP gives meaning to (warnings, objectives, links) are not changed.")

        Header("Current step", "The panel above the guide list that shows the step you are on.")
        TextToggle("SettingsButton", "settingsButton", "Show settings button on current-step hover",
            "A small cog in the upper-right corner of the current-step panel, shown while the pointer is over the panel. It opens RestedXP's menu (choose a guide, go to a step, RestedXP's options), the same one as the menu button at the footer's left, so it is there even when that button is hidden below. It is only a shortcut: it changes nothing in RestedXP and does not move the text.")
        TextChoice("StepLabel", "stepLabel", "Step label format",
            "What the tab above the current step says. X is the step's number in the guide, the one RestedXP shows in its list. Y is how many steps the guide has: its whole list, including steps with nothing to do (so it is the number of the last row), for the character you are on. The percentage is X divided by Y, rounded to the nearest whole number: it is how far along the guide's steps you are, not time spent and not a promise that every objective on the way was done (the last step reads 100 %). A tab with a title of its own, such as a tip, is left as RestedXP draws it; where the guide's size isn't known, the tab says Step X. While in combat the tab shows RestedXP's own text and changes when it ends.",
            function() return RS.STEPLABEL_CHOICES end, true)

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
            function() return RS.FOOTER_CHOICES end, true)

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
            function() return RS.SCROLLBAR_CHOICES end, true)
        local tint = ProxyToggle("restedxpTintScrollbar", "Tint the scroll bar",
            "The slim scroll bar's strip and arrows take the border color, at a soft strength. Off: EllesmereUI's neutral white (or the game's own arrows). Applies to RestedXP's own scroll bar too, which is tinted to the border color.", RS.Text.DEFAULTS.tintScrollbar,
            function() return RS.Text.Get("tintScrollbar") end, function(value) RS.Text.Set("tintScrollbar", value) end)
        Advanced(tint)
        Under(tint, rxpToggle, RxpOn)

        Header("Waypoint arrow", "RestedXP's arrow that points to the next place in the guide. Its own options (Arrow Scale, Arrow Text Size, turning it off) are RestedXP's and stay; these are applied on top. It is only its picture and string that change: where it points, and when it shows, are RestedXP's.")
        TextChoice("ArrowShape", "arrowShape", "Arrow shape",
            "The arrow's picture: TwichUI's bronze plate, RestedXP's own pointer for its theme, the pointer each of RestedXP's other themes draws (blue, red, gold, green and so on), its v2 pointer, and EllesmereUI's chevron when it is installed. All of them point up, so RestedXP rotates them the same way. A shape that has gone is drawn as RestedXP's own and stays chosen.",
            RS.ArrowChoices, true)
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
            if timerSwitch and timerSwitch.GetTooltip ~= nil then
                local TIMER_STATUS = {
                    off = "Off: timer bars are drawn as RestedXP draws them.",
                    ["skin-off"] = "Waiting: the guide window's look isn't drawing (the skin is off, another RestedXP theme is chosen, or another skin is replacing the window).",
                    unsupported = "This version of RestedXP has no timer bars this can draw. Nothing was changed.",
                    active = "Active.",
                }
                local base = timerSwitch:GetTooltip()
                timerSwitch.GetTooltip = function()
                    local state = TM.Status()
                    return (base or "") .. "\n\nStatus: " .. (TIMER_STATUS[state.code] or state.code)
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
            local function TimerChoice(variable, key, label, tooltip, choices, isAdvanced)
                local setting = TimerSetting(variable, STRING, label, key)
                if setting and Settings.CreateDropdown and Settings.CreateControlTextContainer then
                    local row = Settings.CreateDropdown(category, setting, function()
                        local container = Settings.CreateControlTextContainer()
                        for _, choice in ipairs(type(choices) == "function" and choices(Opt.Get(key)) or choices) do
                            container:Add(choice[1], choice[2])
                        end
                        return container:GetData()
                    end, tooltip)
                    if isAdvanced then Advanced(row) end
                    Under(row, timerSwitch, TimersOn, TimersWhy)
                end
            end
            local function TimerSwatch(variable, key, label, tooltip, isAdvanced)
                local setting = TimerSetting(variable, STRING, label, key)
                if setting and Settings.CreateColorSwatch then
                    local row = Settings.CreateColorSwatch(category, setting, tooltip)
                    if isAdvanced then Advanced(row) end
                    Under(row, timerSwitch, TimersOn, TimersWhy)
                end
            end
            local function TimerSlider(variable, key, label, tooltip, isAdvanced)
                local limit = Opt.LIMITS[key]
                local setting = TimerSetting(variable, NUMBER, label, key)
                if not (setting and limit and Settings.CreateSlider and Settings.CreateSliderOptions) then return end
                local options = Settings.CreateSliderOptions(limit[1], limit[2], 1)
                if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
                end
                local row = Settings.CreateSlider(category, setting, options, tooltip)
                if isAdvanced then Advanced(row) end
                Under(row, timerSwitch, TimersOn, TimersWhy)
            end
            local function TimerToggle(variable, key, label, tooltip, isAdvanced)
                local setting = TimerSetting(variable, BOOL, label, key)
                if setting and Settings.CreateCheckbox then
                    local row = Settings.CreateCheckbox(category, setting, tooltip)
                    if isAdvanced then Advanced(row) end
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
            TimerSwatch("LabelColor", "labelColor", "Label color",
                "The color of the text at the left of the bar: what you are waiting for.")
            TimerSwatch("TimeColor", "timeColor", "Time color",
                "The color of the remaining time at the right of the bar.")
            TimerSlider("LabelSize", "labelSize", "Label size",
                "The size of the label. The bar grows to fit a larger size, so the text is never cut off at the top or bottom. A label too long for the bar is cut short with an ellipsis, never run into the time.")
            TimerSlider("TimeSize", "timeSize", "Time size",
                "The size of the remaining time.")
            TimerToggle("ShowIcon", "showIcon", "Show RestedXP's clock icon",
                "The small pocket watch at the left of each bar. It is only a picture. Off, the bar takes its room.")
            TimerSlider("BarHeight", "barHeight", "Bar height",
                "How tall each bar is, in pixels. RestedXP's own is 16. Taller than the footer's strip, a bar covers the bottom of the list while it runs. RestedXP stacks several bars as it always did, and decides their width, which follows the window's.")
            TimerSlider("TextPadding", "textPadding", "Text padding",
                "The room between the label or the time and the bar's ends, in pixels.", true)

            local timerLook = Appearance(TM.Look, "restedxpTimerLook", "bar", "Shows two made-up timer bars beside this window (a short and a long label) in the look set here. They are only a sample: no timer is started, nothing in RestedXP changes, and they go away when this window closes.",
                function() TM.TogglePreview() end, nil, nil, timerSwitch, TimersOn, {
                order = { "BgColor", "BorderColor", "BgTexture", "BgOpacity", "BorderTexture", "BorderSize", "BorderOpacity" },
                advanced = { BgTexture = true, BgOpacity = true, BorderTexture = true, BorderSize = true, BorderOpacity = true },
                advancedHeader = "Advanced timer bar look",
                labels = {
                    BgTexture = "Timer background texture", BgColor = "Timer background color",
                    BgOpacity = "Timer background opacity", BorderTexture = "Timer border texture",
                    BorderSize = "Timer border thickness", BorderColor = "Timer border color",
                    BorderOpacity = "Timer border opacity",
                },
            })
            for _, entry in ipairs(timerLook) do resettableTimers[#resettableTimers + 1] = entry end

            Advanced(Header("Advanced timer bar text and fill", "Textures, fonts and outlines for the timer bars. The lists come from LibSharedMedia, so media other addons add appears here; EllesmereUI's textures are listed while it is installed."))
            TimerChoice("FillTexture", "fillTexture", "Fill texture",
                "The texture the fill is drawn with: a flat fill (the default, which shows the colors exactly), RestedXP's own bar texture, EllesmereUI's bar textures while it is installed, and any LibSharedMedia status bar texture. A texture that has gone is drawn as RestedXP's own and stays chosen.",
                TM.FillChoices, true)
            TimerChoice("LabelFont", "labelFont", "Label font",
                "The font of the label. By default the same as the guide's step text. A font that has gone is drawn as that and stays chosen.",
                TM.LabelFontChoices, true)
            TimerChoice("LabelOutline", "labelOutline", "Label outline",
                "An outline round the label. The default keeps light text readable over the fill.",
                TM.OUTLINE_CHOICES, true)
            TimerChoice("TimeFont", "timeFont", "Time font",
                "The font of the remaining time. By default the same as the label's.", TM.TimeFontChoices, true)
            TimerChoice("TimeOutline", "timeOutline", "Time outline",
                "An outline round the remaining time. By default the same as the label's.", TM.TIME_OUTLINE_CHOICES, true)
            local resetTimers = Button("Reset timer bars", "Reset", function()
                for _, entry in ipairs(resettableTimers) do
                    if entry.setting.SetValue then pcall(entry.setting.SetValue, entry.setting, entry.default) end
                end
                TM.Reset()
            end, "Puts the timer bars' fill, text, size, background and border back to the defaults, and turns Skin timer bars on. Nothing else changes: not the window's look, RestedXP's settings or its timers.")
            Under(resetTimers, rxpToggle, RxpOn)
        end

        Advanced(Header("Advanced text", "Fonts and outlines. Sizes are set under Text size, or follow RestedXP's own Guide Font Size option."))
        TextChoice("TitleFont", "titleFont", "Title font",
            "The font of the guide's title, the footer and step number tabs. The list comes from LibSharedMedia, so fonts other addons add appear here. RestedXP's own is the default. A font that has gone is drawn as the default and stays chosen.",
            RS.FontChoices)
        TextChoice("TitleOutline", "titleOutline", "Title outline", "An outline round the title text.",
            function() return RS.OUTLINE_CHOICES end)
        TextChoice("BodyFont", "bodyFont", "Step text font",
            "The font of step and objective text. A font that has gone is drawn as RestedXP's own and stays chosen.",
            RS.FontChoices)
        TextChoice("BodyOutline", "bodyOutline", "Step text outline", "An outline round the step and objective text.",
            function() return RS.OUTLINE_CHOICES end)
        TextChoice("Dividers", "dividers", "Header and footer borders",
            "Light: the header, the footer and each step's tab draw a fainter border than the window, with no highlight line, so the borders don't stack. Full border: the same border as the window.",
            function() return RS.DIVIDER_CHOICES end)
        local reset = Button("Reset appearance", "Reset", function()
            for _, entry in ipairs(resettable) do
                if entry.setting.SetValue then pcall(entry.setting.SetValue, entry.setting, entry.default) end
            end
            RS.Reset()
        end, "Puts this look's background, border, colors, fonts, sizes, spacing, what shows and the waypoint arrow back to the defaults. Nothing else changes: not the switch, RestedXP's settings, guide progress or positions, or the rest of TwichUI.")
        Under(reset, rxpToggle, RxpOn)

        R:On("PLAYER_LOGIN", RefreshOverview)
    end

    -----------------------------------------------------------------------
    Use("notifications")
    Header("Notifications", "Small, quiet cards near the edges of the screen for moments worth a glance. None of them makes you do anything, and each can be turned off on its own.")
    Toggle("arrivalReducedMotion", "Reduced motion",
        "The notification cards only fade in and out, without moving. Applies to the zone, training and friend cards.")

    Header("Zone arrival", "A short, quiet title card when you arrive somewhere new, in place of the game's own zone text.")
    local function RefreshArrival() if R.Arrival then R.Arrival.Refresh() end end
    local arrival = Toggle("arrival", "Show a title card when I arrive in a new zone",
        "The zone's name appears near the top of the screen under a thin bronze rule, with the smaller place you're in beneath it, then fades away. It replaces the game's own zone text while on. Not shown when you log in or reload, or while on a flight path: only where you land.\n\nIf another addon also replaces the zone text, you may see both.",
        false, RefreshArrival)
    local function ArrivalOn() return R:Enabled("arrival") end
    Under(Toggle("arrivalSubzones", "Also for smaller places",
        "A quieter card when you walk into a smaller place within the zone, such as a town. Off: moving within a zone shows nothing.",
        false, RefreshArrival), arrival, ArrivalOn)
    Under(Toggle("arrivalDungeons", "Show dungeon and raid arrival cards",
        "Walking into a dungeon or raid shows its name with \"Dungeon\" or \"Raid\" beneath it. Off: you get the ordinary zone card there, as before. Not shown when you log in or reload inside one.",
        false, RefreshArrival), arrival, ArrivalOn)

    Header("New training", "A short card when you level up and there is class training you haven't taken yet.")
    Toggle("trainingNotice", "Show new training when I level up",
        "When you level up and there are class spells or ranks you could train and don't know yet, including ones from earlier levels you haven't trained, a short title card near the top of the screen, below the zone's name, lists them (only the highest rank of each spell), in the zone card's style with no frame. Move it in Edit Mode. They are available to train at your class trainer; nothing is learned for you. Nothing shows when there is nothing to train. It waits until you're out of combat, fades by itself, and makes no sound or chat line. Reduced motion (above) applies.\n\nType /tui training to see the card for your current level. Spell data comes from What's Training?.",
        false, function() if R.Training then R.Training.Refresh() end end)

    Header("Friend login", "A short card when a Battle.net friend comes online, in place of the game's own pop-up.")
    local friendLogin = Toggle("friendLogin", "Show Battle.net friend logins as a TwichUI card",
        "When a Battle.net friend comes online, a short card with their name, a Horde or Alliance mark if the game says which faction they play, and the character they are on, in the zone card's style with no frame. It replaces the game's own friend-online pop-up while on; the pop-ups for friends going offline, broadcasts, friend requests and invitations, and the line in chat, are unchanged. Turn it off to get the game's pop-up back. The game's own Social options still apply: with Show Toast Window or Online Friends off, nothing shows. Nothing shows at login or reload, or in combat; several friends arriving together give one card. Move it in Edit Mode. It plays a soft chime, which you can change below. Reduced motion (above) applies.\n\nType /tui friend to see the card.",
        false, function() if R.FriendLogin then R.FriendLogin.Refresh() end end)
    local function FriendLoginOn() return R:Enabled("friendLogin") end
    Under(Toggle("friendLoginSound", "Play a soft chime with it",
        "A short chime (TwichUI Notification) when the card appears. Off: the card is silent."), friendLogin, FriendLoginOn)
    local FriendLogin = R.FriendLogin
    if FriendLogin then
        local channels = {}
        for i, channel in ipairs(FriendLogin.CHANNELS) do channels[i] = { channel.key, channel.label, channel.tooltip } end
        Under(Choice("friendLoginChannel", "Chime volume follows",
            "A sound file can't have a volume of its own, so the chime is as loud as the game volume you choose here. Set that volume in the game's Audio options: lower it to make the chime quieter, or pick the one you keep lowest.",
            STRING, FriendLogin.CHANNEL_DEFAULT,
            function() return (FriendLogin.SoundChannel()) end,
            function(value) TwichUIDB.ui.friendLoginChannel = value end,
            channels), friendLogin, FriendLoginOn)
        Under(Button("Hear the chime", "Play", function() FriendLogin.PlaySound() end,
            "Plays the chime now, at the volume you have chosen."), friendLogin, FriendLoginOn)
    end

    local Notify = R.Notify
    if Notify then
        Header("Notification previews", "Try the cards without waiting for the real thing. A preview tests how a card looks and sounds, not whether the game event is noticed: it uses made-up details, records and changes nothing, and works even when that card is turned off.")
        ProxyToggle("previewSounds", "Play notification sounds in previews",
            "Previews are silent unless this is on. The friend login chime then plays with its preview, on the volume you chose above, but only while \"Play a soft chime with it\" is on, as it is for a real login. The other cards have no sound.",
            false,
            function() return TwichUIDB.ui.previewSounds == true end,
            function(value) TwichUIDB.ui.previewSounds = value and true or false end)
        local previewTips = {
            arrival = "Shows the zone card with a made-up place, where and how it would really appear.",
            training = "Shows the new training card with made-up spells. Nothing is trained or marked, and it can't be clicked.",
            friend = "Shows the friend login card with a made-up friend. No friend state is read or changed.",
            welcome = "Shows the Welcome Back card with a made-up entry. Your Chronicle isn't read, and its link does nothing.",
        }
        local labels = {}
        for _, info in ipairs(Notify.Kinds()) do labels[info.kind] = info.label end
        -- A preview waits for the fight to end, like the cards themselves, and says when it couldn't show.
        local previewWhy = { full = "too many cards are waiting. Try Clear previews.", unknown = "that card isn't available." }
        local function Preview(kind)
            if InCombatLockdown() then R.Print("previews wait until you're out of combat.") return end
            local ok, why = Notify.Preview(kind)
            if ok == false then R.Print("couldn't show that preview: %s", previewWhy[why] or "it's already showing.") end
        end
        for _, kind in ipairs({ "arrival", "training", "friend", "welcome" }) do
            if labels[kind] then
                Button(labels[kind], "Preview", function() Preview(kind) end,
                    previewTips[kind] .. " It appears above this window and fades by itself. Real notices always come first.")
            end
        end
        Button("Test coordinated sequence", "Run", function()
            if InCombatLockdown() then R.Print("previews wait until you're out of combat.") return end
            local sent, dropped = Notify.PreviewSequence()
            R.Print("Test sequence: %d sample notices sent, %d repeat dropped. Cards in different places show together; the rest take turns.", sent, dropped)
        end, "Sends a fixed set of sample notices at once: a zone card, a friend card, a training card, a repeat of the zone card (which is dropped) and a Welcome Back card. The friend card shows beside the zone card; the training and Welcome Back cards wait their turn at the top.")
        Button("Clear previews", "Clear", function() Notify.ClearPreviews() end,
            "Stops every preview, showing or waiting. Real notices aren't touched.")
    end

    local Arrival = R.Arrival
    if Arrival then
        local holds = {}
        for i, hold in ipairs(Arrival.HOLDS) do
            holds[i] = { hold.key, hold.label, ("Stays %g seconds before fading away."):format(hold.seconds) }
        end
        Advanced(Header("Advanced"))
        Under(Advanced(Choice("arrivalHold", "How long the zone card stays",
            "How long the zone's name stays before it fades away. Cards for smaller places stay a little shorter.",
            STRING, Arrival.HOLD_DEFAULT,
            function() return (Arrival.HoldChoice()) end,
            function(value) TwichUIDB.ui.arrivalHold = value end,
            holds)), arrival, ArrivalOn)
    end

    -----------------------------------------------------------------------
    if pages.qol then
        Use("qol")
        local Q = R.QoL
        -- Each row's tooltip ends with a note when Leatrix Plus has the same option on. It is kept
        -- current by the events that can change it (no polling).
        local qolRows = {}
        local function RefreshQol()
            for _, row in ipairs(qolRows) do
                if row.initializer.data then
                    row.initializer.data.tooltip = row.what .. (Q.LeatrixOverlap(row.key)
                        and "\n\nLeatrix Plus also has this turned on. Both do it, which does no harm, but you only need one." or "")
                end
            end
            RefreshOverview()
        end
        local function QolToggle(key, label, what, feature)
            local initializer = Toggle(key, label, what, false, function()
                if feature then Q.Apply(feature) end
                RefreshQol()
            end)
            if initializer and Q.LEATRIX[key] then qolRows[#qolRows + 1] = { key = key, what = what, initializer = initializer } end
            return initializer
        end
        local function QolChoice(variable, key, label, tooltip, options)
            local varType = (key == "summonsFrom" or key == "duelsFrom") and STRING or NUMBER
            return Choice(variable, label, tooltip, varType, Q.DEFAULTS[key],
                function() return Q.Get(key) end, function(value) Q.Set(key, value) end, options)
        end
        local function Seconds(n) return n == 0 and "Don't wait" or (n == 1 and "1 second" or ("%d seconds"):format(n)) end
        local function Waits(key)
            local list = {}
            for i, n in ipairs(Q.CHOICES[key]) do list[i] = { n, Seconds(n) } end
            return list
        end

        Header("Summons and resurrection", "Small conveniences for when another player offers to move or raise you. Each is off until you turn it on, and each does only the one thing it says.")
        local summons = QolToggle("qolSummons", "Accept summons",
            "Accepts a summon from another player for you after a short wait, so you arrive without clicking. The game's own pop-up stays up during the wait: choose Decline there to stay where you are. Only an ordinary summon is accepted; a scenario summon, or one that skips a starting area's introduction, is always left to you. Nothing is accepted in combat or when the game won't let you teleport, and there is no second try: the pop-up stays for you to answer.\n\nYou arrive wherever the summoner stands, so choose who you trust below.",
            R.QoLSummons.feature)
        local function SummonsOn() return R:Enabled("qolSummons") end
        Under(QolChoice("qolSummonsFrom", "summonsFrom", "Accept summons from",
            "Who can summon you without asking. Friends are your character friends and the WoW characters of Battle.net friends; guild members are read from the guild roster the game has loaded. A summon with no name the game will give is never accepted, except from Anyone.",
            {
                { "known", "Friends, guild and group members" },
                { "group", "Group members only", "People in your party or raid." },
                { "anyone", "Anyone", "Any player's summon, strangers included." },
            }), summons, SummonsOn)

        local resurrect = QolToggle("qolResurrect", "Accept resurrection",
            "Accepts a resurrection another player offers you, so you get up without clicking the pop-up. The game's own waiting time is kept: if it hasn't passed, the offer is accepted when it ends, if it still stands. An offer that carries resurrection sickness is left for you to decide. Soulstones and other self-resurrection, spirit healers and corpse runs aren't touched, and it never releases your spirit. Not used on Hardcore rules.\n\nTurn it off if you'd rather choose who raises you.",
            R.QoLResurrect.feature)
        local function ResurrectOn() return R:Enabled("qolResurrect") end
        Under(QolToggle("qolResurrectCombat", "Also accept combat resurrections",
            "Also accepts a resurrection from someone who is in combat. The game doesn't mark combat resurrections, so this is judged by the person offering being in your group and in combat; someone outside your group can't be seen either way and counts as an ordinary offer. Off: those offers wait for you to accept them yourself. You rise with little health, into whatever fight is still going.",
            R.QoLResurrect.feature), resurrect, ResurrectOn)

        Header("Battlegrounds", "Dying in a battleground, where the next step is nearly always to release.")
        local release = QolToggle("qolReleasePvP", "Release in battlegrounds",
            "After you die in a battleground, your spirit is released for you after a short wait. Battlegrounds only: never in dungeons, raids, arenas or the open world, where nothing here can tell that releasing is wanted. Nothing is released while you have a soulstone or other self-resurrection on offer, while someone's resurrection is on offer, or when the game says you can't release. Hold Shift as the wait ends to keep your body. Not used on Hardcore rules.\n\nThere is no second try: if it doesn't release, the game's own Release button is still there.",
            R.QoLRelease.feature)

        Header("Duels", "Duel requests from other players.")
        local duels = QolToggle("qolDuels", "Decline duel requests",
            "Declines an ordinary duel request as soon as it arrives, unless it's from someone you allow below. The challenger sees it declined, as if you had pressed Decline; TwichUI says nothing in chat and shows no message. If the game doesn't give the challenger's name, the request is declined. Off: duels work as the game does.",
            R.QoLDuels.feature)
        local function DuelsOn() return R:Enabled("qolDuels") end
        Under(QolChoice("qolDuelsFrom", "duelsFrom", "Still allow duels from",
            "Whose duel requests you still get to answer yourself. Friends are your character friends and the WoW characters of Battle.net friends; guild members are read from the guild roster the game has loaded.",
            {
                { "known", "Friends, guild and group members" },
                { "friendsGuild", "Friends and guild members" },
                { "friends", "Friends only" },
                { "nobody", "Nobody", "Every duel request is declined." },
            }), duels, DuelsOn)
        Under(QolToggle("qolDuelsToDeath", "Also decline duels to the death",
            "Also declines a duel to the death, which Forever treats as a separate, lethal kind of duel (accepting one asks you to type a confirmation). The same exceptions apply. Off: duels to the death still reach you.",
            R.QoLDuels.feature), duels, DuelsOn)

        Header("Game Menu", "A shortcut in the Escape menu.")
        QolToggle("qolQuickKeybind", "Quick Keybind button",
            "Adds a Quick Keybind button to the Game Menu, below Macros. It opens the game's own Quick Keybind Mode, the one in Settings > Keybindings, with its usual instructions and Okay and Cancel buttons; entering it changes no bindings. Like the game's own, it can't be opened in combat, and the button is dimmed until combat ends.",
            R.QoLQuickKeybind.feature)

        local GW = R.QoLGuideWaypoint
        if GW then
            Header("RestedXP guides", "Uses the game's own waypoint for where RestedXP is leading you. RestedXP's arrow and map pins are unchanged.")
            local gwBase = "Puts the game's waypoint (its map pin and the marker in the world) on the place RestedXP's arrow is leading you to, and moves it on when RestedXP does. Where RestedXP only routes you along a path, it marks where that path ends; a kill area with no single destination gets none.\n\nA waypoint you placed yourself is never moved or cleared: while yours is there, this waits. If you clear or replace its waypoint, it leaves it so until the next destination. Each new destination is made the tracked one, which can take the in-world marker from a quest you were tracking. Turning this off clears its own waypoint."
            local STATUS = {
                off = { "Off" },
                ["restedxp-missing"] = { "RestedXP not installed", "Install RestedXP Guides to use this." },
                ["restedxp-disabled"] = { "RestedXP turned off", "RestedXP Guides is turned off in your AddOns list." },
                waiting = { "Waiting for RestedXP", "RestedXP hasn't finished loading yet." },
                unsupported = { "This RestedXP isn't supported", "This version of RestedXP doesn't have what this needs (its arrow and map updates). Nothing was changed." },
                ["no-guide"] = { "No guide", "RestedXP has no guide showing." },
                ["no-destination"] = { "No destination", "RestedXP's arrow isn't leading anywhere right now (for example, in an instance)." },
                route = { "No single destination", "This step only has a route or an area, so there is nothing to mark." },
                ["map-refused"] = { "Can't mark this map", "The game doesn't allow a waypoint on the map this destination is on." },
                yours = { "Your waypoint is in use", "Your own waypoint is left as it is. Clear it to let this mark the next destination." },
                cleared = { "Waiting for the next destination", "Its waypoint was cleared or replaced, so it waits for RestedXP's next destination." },
                shown = { "Showing the destination" },
            }
            local guideToggle = QolToggle("qolGuideWaypoint", "Mark RestedXP's destination", gwBase, GW.feature)
            if guideToggle and guideToggle.GetTooltip ~= nil then
                -- read when the tooltip is shown, so it is never stale
                guideToggle.GetTooltip = function()
                    local code = GW.Status()
                    local text = STATUS[code] or { code }
                    local color = (code == "shown" and R.GREEN) or (code == "off" and R.GREY) or R.GOLD
                    return gwBase .. "\n\nStatus: " .. color .. text[1] .. "|r" .. (text[2] and ("\n" .. text[2]) or "")
                end
            end
        end

        Advanced(Header("Advanced"))
        Under(Advanced(QolChoice("qolSummonsWait", "summonsWait", "Wait before accepting a summon",
            "How long the summon's pop-up stays up before it is accepted, so you can decline it.", Waits("summonsWait"))), summons, SummonsOn)
        Under(Advanced(QolChoice("qolReleaseWait", "releaseWait", "Wait before releasing",
            "How long after you die before your spirit is released. A resurrection offered in that time cancels the release, and holding Shift as it ends keeps your body.", Waits("releaseWait"))),
            release, function() return R:Enabled("qolReleasePvP") end)

        RefreshQol()
        R:On("PLAYER_LOGIN", RefreshQol)
        R:On("ADDON_LOADED", function(name) if name == "Leatrix_Plus" then RefreshQol() end end)
    end

    -----------------------------------------------------------------------
    Use("food")
    Header("Food and Drink buttons", "Two small buttons you click to eat or drink. TwichUI never uses anything for you.")
    local foodDrink = Toggle("foodDrink", "Show Food and Drink buttons",
        "Adds a Food button and a Drink button. Each holds the food or drink in your bags that restores the most (by the amount the item's own text states) among what you can use, and eats or drinks it only when you click it. It chooses only plain food and drink, judged from the item's own text: buff food, feasts and anything it can't read are never picked. An empty button means there is nothing it can tell is plain food or drink in your bags.\n\nThe choice updates when your bags change; if they change during combat, it updates when combat ends. Move the buttons in Edit Mode. Nothing is saved but where you put them and the look you choose below.",
        false, function() if R.FoodDrink then R.FoodDrink.Refresh() end end)
    local function FoodDrinkOn() return R:Enabled("foodDrink") end
    Under(Toggle("foodDrinkFood", "Show the Food button",
        "Off: only the Drink button is shown.",
        false, function() if R.FoodDrink then R.FoodDrink.Refresh() end end), foodDrink, FoodDrinkOn)
    Under(Toggle("foodDrinkDrink", "Show the Drink button",
        "Off: only the Food button is shown. Classes without mana may not want this one.",
        false, function() if R.FoodDrink then R.FoodDrink.Refresh() end end), foodDrink, FoodDrinkOn)

    local FD = R.FoodDrink
    if FD then
        Under(ProxyToggle("foodDrinkPreferConjured", "Prefer Mage-conjured food and water",
            "When you carry Mage-conjured food or water you can use, the buttons choose it over ordinary food or drink, even when an ordinary item restores more health or mana. Food and water are chosen separately: with conjured food but no conjured water, the Food button holds the conjured food and the Drink button holds the best ordinary drink. With none of a kind, that button chooses as it always does. Among conjured items, the one that restores the most is chosen. It works for any character carrying conjured items, not only Mages, and never lets in an item the buttons would otherwise skip. Off, the choice is the one that restores the most.",
            FD.DEFAULTS.preferConjured, function() return FD.Get("preferConjured") end,
            function(value) FD.Set("preferConjured", value and true or false) end), foodDrink, FoodDrinkOn)

        -- Where they go. Edit Mode moves the buttons unless this is on and EllesmereUI is there.
        local FDU = FD.Unlock
        if FDU then
            local unlockBase = "Move the buttons in EllesmereUI's Unlock Mode instead of Edit Mode. A \"TwichUI Food & Drink\" anchor appears there, and you drag it, nudge it, type its X and Y or anchor it to another element the way you do the rest of your interface. Turning this on keeps the buttons where they are. The place is still saved by TwichUI; EllesmereUI's anchor links are saved by EllesmereUI.\n\nOpen Unlock Mode with /unlock. It can't be opened in combat, and nothing is moved then.\n\nOff, or without EllesmereUI, the buttons are moved in Edit Mode as before. Your choice is kept while EllesmereUI is away."
            local UNLOCK_STATUS = {
                off = { "Off" },
                ["no-eui"] = { "EllesmereUI isn't installed or turned on", "The buttons are moved in Edit Mode until it is." },
                ["no-api"] = { "This EllesmereUI has no Unlock Mode", "The buttons are moved in Edit Mode." },
                waiting = { "Waiting for EllesmereUI", "It hasn't finished loading yet." },
                ["register-failed"] = { "EllesmereUI didn't take the anchor", "The buttons are moved in Edit Mode. /tui diagnostics has the details." },
                ["module-off"] = { "Ready", "The anchor appears in Unlock Mode while a Food or Drink button is on." },
                active = { "In EllesmereUI's Unlock Mode", "Type /unlock and look for \"TwichUI Food & Drink\"." },
            }
            local unlock = Under(Toggle("foodDrinkUnlock", "Use EllesmereUI Unlock Mode", unlockBase, false,
                function() FD.Refresh() end), foodDrink, FoodDrinkOn)
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

        Header("Appearance", "Make the buttons match the rest of your interface.")
        local resettable = {}   -- { setting, default }, for Reset
        local function Remember(variable, varType, label, key, set)
            local setting = Proxy(variable, varType, label, FD.DEFAULTS[key], function() return FD.Get(key) end, set)
            if setting then resettable[#resettable + 1] = { setting = setting, default = FD.DEFAULTS[key] } end
            return setting
        end
        local function Slider(variable, key, label, tooltip, parent, isOn, why)
            local limit = FD.LIMITS[key]
            local setting = Remember(variable, NUMBER, label, key, function(value) FD.Set(key, math.floor(value + 0.5)) end)
            if not (setting and Settings.CreateSlider and Settings.CreateSliderOptions) then return end
            local options = Settings.CreateSliderOptions(limit[1], limit[2], 1)
            if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            end
            return Under(Settings.CreateSlider(category, setting, options, tooltip), parent or foodDrink, isOn or FoodDrinkOn, why)
        end
        Slider("foodDrinkSize", "size", "Button size", "The width and height of each button, in pixels.")
        Slider("foodDrinkSpacing", "spacing", "Space between buttons", "The gap between the two buttons, in pixels.")
        local layoutSetting = Remember("foodDrinkLayout", STRING, "Layout", "layout", function(value) FD.Set("layout", value) end)
        if layoutSetting and Settings.CreateDropdown and Settings.CreateControlTextContainer then
            Under(Settings.CreateDropdown(category, layoutSetting, function()
                local container = Settings.CreateControlTextContainer()
                container:Add("horizontal", "Side by side")
                container:Add("vertical", "Stacked")
                return container:GetData()
            end, "Whether the buttons sit next to each other or one above the other."), foodDrink, FoodDrinkOn)
        end
        local textureSetting = Remember("foodDrinkBorderTexture", STRING, "Border texture", "borderTexture", function(value) FD.Set("borderTexture", value) end)
        if textureSetting and Settings.CreateDropdown and Settings.CreateControlTextContainer then
            Under(Settings.CreateDropdown(category, textureSetting, function()
                local container = Settings.CreateControlTextContainer()
                for _, choice in ipairs(FD.TextureChoices()) do container:Add(choice[1], choice[2]) end
                return container:GetData()
            end, "Solid is a plain line. With EllesmereUI installed, its own border textures (such as Pixels Textured) are listed too, drawn the way its bars draw them. The rest are border textures from LibSharedMedia, so any addon that adds borders to it adds them here. Picking one sets a thickness and color that suit it unless you have set your own; change them below."), foodDrink, FoodDrinkOn)
        end
        Slider("foodDrinkBorderSize", "borderSize", "Border thickness", "The border around each button, in pixels. 0 for none. A texture needs about 8 or more to read well.")
        local classToggle
        local classSetting = Remember("foodDrinkBorderClass", BOOL, "Use my class color for the border", "borderClass",
            function(value) FD.Set("borderClass", value and true or false) end)
        if classSetting then
            classToggle = Under(Settings.CreateCheckbox(category, classSetting,
                "Draws the border in your class color instead of the color below."), foodDrink, FoodDrinkOn)
        end
        local colorSetting = Remember("foodDrinkBorderColor", STRING, "Border color", "borderColor", function(value) FD.Set("borderColor", value) end)
        if colorSetting and Settings.CreateColorSwatch then
            Under(Settings.CreateColorSwatch(category, colorSetting,
                "The color of the border. Greyed out while the class color is used."),
                classToggle or foodDrink, function() return FoodDrinkOn() and not FD.Get("borderClass") end,
                function()
                    if not FoodDrinkOn() then return "Greyed out: needs \"Show Food and Drink buttons\" turned on." end
                    return "Greyed out: the border uses your class color. Turn that off to choose another."
                end)
        end
        Slider("foodDrinkBorderOpacity", "borderOpacity", "Border opacity", "How solid the border is, in percent. 100 is fully opaque. Applies to the class color too.")
        Slider("foodDrinkZoom", "zoom", "Icon zoom", "How much of the icon's edge is cropped, in percent. More looks tighter inside the border.")
        local countSetting = Remember("foodDrinkShowCount", BOOL, "Show how many I have", "showCount",
            function(value) FD.Set("showCount", value and true or false) end)
        if countSetting then
            Under(Settings.CreateCheckbox(category, countSetting,
                "A small number in the corner of a button when you have more than one."), foodDrink, FoodDrinkOn)
        end
        Slider("foodDrinkButtonOpacity", "buttonOpacity", "Button opacity", "How solid the buttons are, in percent. 100 is fully opaque.")
        local mouseoverSetting = Remember("foodDrinkMouseover", BOOL, "Fade when the mouse is away", "mouseover",
            function(value) FD.Set("mouseover", value and true or false) end)
        if mouseoverSetting then
            local mouseover = Under(Settings.CreateCheckbox(category, mouseoverSetting,
                "The buttons fade to the opacity below until the mouse is over one, then return to the button opacity. Even at 0 a button still takes a click, so move the mouse to where it is."), foodDrink, FoodDrinkOn)
            Slider("foodDrinkIdleOpacity", "idleOpacity", "Opacity when the mouse is away",
                "How solid the buttons are, in percent, while the mouse is not over them.",
                mouseover or foodDrink, function() return FoodDrinkOn() and FD.Get("mouseover") end,
                function()
                    if not FoodDrinkOn() then return "Greyed out: needs \"Show Food and Drink buttons\" turned on." end
                    return "Greyed out: needs \"Fade when the mouse is away\" turned on."
                end)
        end
        Button("Appearance", "Reset", function()
            for _, entry in ipairs(resettable) do
                if entry.setting.SetValue then pcall(entry.setting.SetValue, entry.setting, entry.default) end
            end
        end, "Puts size, spacing, layout, border, zoom, opacity and the count back to their defaults. The place is kept.")
    end

    -----------------------------------------------------------------------
    local MT = R.MageTravel
    if pages.mage then
        Use("mage")
        Header("Mage Travel", "A launcher for your data bar that lists your teleports and portals. It casts only the one you click, and never chooses a destination for you.")
        local mage = Toggle("mageTravel", "Mage Travel launcher on my data bar",
            "Adds \"TwichUI Mage Travel\" to the list of your data bar addon (any that shows LibDataBroker launchers, such as EllesmereUI's Broker Plugin block). Click it for a small menu of the teleports and portals your faction can learn: click a learned one to cast it; hover one you haven't learned for the level it is trained at. It can't be opened in combat, and closes when combat starts.\n\nWithout a data bar addon there is nowhere for it to show. Turning it off takes it off your data bar after a reload.",
            false, function()
                MT.Refresh()
                if not R:Enabled("mageTravel") and MT.Available() then AskReload() end
            end)
        Under(Choice("mageTravelText", "Text on the data bar",
            "The word shown beside the launcher's icon on your data bar. None leaves just the icon. If your data bar shows plugin names too, it may read \"Mage Travel: Travel\"; that is the data bar's own label option.",
            STRING, MT.DEFAULT_TEXT, MT.TextChoice, MT.SetTextChoice, MT.TEXTS),
            mage, function() return R:Enabled("mageTravel") end)

        local MC = R.MageConjure
        Header("Mage Conjuring", "A launcher for your data bar with your best Conjure Food and Conjure Water. It casts only the one you click.")
        local conjure = Toggle("mageConjure", "Mage Conjuring launcher on my data bar",
            "Adds \"TwichUI Mage Conjuring\" to the list of your data bar addon (any that shows LibDataBroker launchers, such as EllesmereUI's Broker Plugin block). Click it for a small menu with one entry each for Conjure Food and Conjure Water, the highest rank you have learned of each: click one to cast it. With none learned, the first rank is shown muted; hover it for the level it is trained at. Shift-left-click the launcher to conjure water and shift-right-click to conjure food, each at your highest rank. It can't be opened in combat, and closes when combat starts; the shift-clicks don't work in combat either.\n\nWithout a data bar addon there is nowhere for it to show. Turning it off takes it off your data bar after a reload.",
            false, function()
                MC.Refresh()
                if not R:Enabled("mageConjure") and MC.Available() then AskReload() end
            end)
        Under(Choice("mageConjureText", "Text on the data bar",
            "The word shown beside the launcher's icon on your data bar. None leaves just the icon. If your data bar shows plugin names too, it may read \"Mage Conjuring: Conjure\"; that is the data bar's own label option.",
            STRING, MC.DEFAULT_TEXT, MC.TextChoice, MC.SetTextChoice, MC.TEXTS),
            conjure, function() return R:Enabled("mageConjure") end)

        local RF = R.Refreshments
        local refreshToggle   -- the refreshments switch, which its appearance is greyed out under
        if RF then
            Header("Mage refreshments", "Plan the conjured food and water you hand to your party or raid, conjure it by click or key, and tick off who you've supplied. TwichUI never casts, trades or whispers for you.")
            local refresh = Toggle("mageRefreshments", "Refreshments panel",
                "A small panel (/tui refreshments, or its key in Key Bindings > TwichUI) for getting your group fed and watered. It works out how much water and food your party or raid needs from each class's share and what you keep, at the best rank each person can use, against what is in your bags. Its Water and Food buttons conjure once per click or key press; drag one to an action bar to hold a key with the game's Press and Hold Casting instead. A checklist shows who you've supplied; you mark it yourself, and it starts again when you leave the group or reload.\n\nIt can't be opened in combat and closes when combat starts. Off by default.",
                false, function() RF.Refresh() end)
            refreshToggle = refresh
            local function RefreshOn() return R:Enabled("mageRefreshments") end
            Under(Button("Refreshments panel", "Open", function()
                if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
                if R.RefreshmentsPanel then R.RefreshmentsPanel.Open() end
            end, "Opens the panel (same as typing /tui refreshments)."), refresh, RefreshOn)
            local RB = R.RefreshmentsBroker
            if RB then
                Under(Choice("refreshmentsText", "Text on the data bar",
                    "Adds \"TwichUI Mage Refreshments\" to the list of your data bar addon (any that shows LibDataBroker plugins, such as EllesmereUI's Broker Plugin block) once refreshments are on; no reload needed. Click it to open the panel, right-click for these options; hover it for how much water and food is prepared and who is supplied.\n\nThe word beside its icon: how many of your group are supplied (\"3/5 supplied\"), \"Refreshments\", or none. On your own it reads \"Refreshments\". Turned off, it reads \"Off\" until you reload.",
                    STRING, RB.DEFAULT_TEXT, RB.TextChoice, RB.SetTextChoice, RB.TEXTS), refresh, RefreshOn)
            end
            if R.RefreshmentsTrade then
                local trade = Under(Toggle("mageRefreshmentsTrade", "Fill trade button and trade tracking",
                    "While you trade with someone in your group, a small strip under the trade window shows what their share still asks for, with a Fill trade button. Nothing happens until you click it: it puts whole stacks of the rank planned for them into empty slots, and when a part stack is needed, splits it into an empty bag slot for your next click to add. It never takes out what is already in the window, never puts in anything else, and never accepts the trade.\n\nWhen the game says a trade was completed, what you offered is marked as handed over. If TwichUI can't confirm it, the panel asks you to confirm or dismiss it. People outside your group get no share.",
                    false, function() R.RefreshmentsTrade.Refresh() end), refresh, RefreshOn)
                local RT = R.RefreshmentsTrade
                local function TradeOn() return RefreshOn() and R:Enabled("mageRefreshmentsTrade") end
                Under(Toggle("mageRefreshmentsAutoFill", "Fill trades automatically",
                    "When a trade with someone in your group opens, whoever opened it, what is planned for them goes in by itself a moment later, without clicking Fill trade; a part stack goes in once the game has split it. It never accepts the trade, never adds anything once either of you has pressed Trade, and stops for that trade as soon as you take something out of it. It waits while you hold something on the cursor or are in combat.\n\nIf the game doesn't allow it, it switches itself off until you reload (one line says so) and the Fill trade button still works.",
                    false), trade, TradeOn)
                Under(Choice("refreshmentsTradeGives", "Each trade puts in",
                    "Their whole share: every trade with them gets their class's whole share again, however much they had before, for when they come back for more. What is handed over still adds up in the checklist.\n\nOnly what is still owed: their share less what they've been handed this session, so once they're supplied, a trade adds nothing.",
                    STRING, RT.DEFAULT_GIVES, RT.Gives, RT.SetGives, RT.GIVES), trade, TradeOn)
            end
            if R.RefreshmentShares then
                Button("Refreshment shares", "Edit", function() R.RefreshmentShares.Show() end,
                    "How many water and food each class gets in a party and in a raid, and how many you keep. Single items, not stacks.")
            end
        end

        local MSL, MSW = R.MageSell, R.MageSellWindow
        if MSL then
            Header("Sell ordinary food and drink", "Optional. Sells plain, non-conjured food and drink when you open a merchant, so conjured refreshments are what your bags hold. Off by default. Conjured items, special food, quest items, anything locked or without a sell price, and anything on your never-sell list are always kept.")
            local sell = Toggle("mageSell", "Sell non-conjured food and drink",
                "When you open a merchant, TwichUI sells the ordinary food and drink in your bags: plain items that only restore health or mana. It keeps Mage-conjured food and water (made by you or another Mage), buff food, feasts, potions and reagents, quest items, locked items, items with no sell price, and anything on your never-sell list; when it can't tell, it keeps the item.\n\nIt starts in Dry run, which only says what it would sell. A visit sells at most a few stacks so your own sales stay in the merchant's Buyback tab, which holds a limited number; other sales can still push entries out. Nothing is destroyed, bought or taken from the bank, mail or anywhere but your bags.\n\nOff by default. Other Mage features don't turn it on.",
                false, function()
                    MSL.Refresh()
                    if MSL.Enabled() then
                        R.Print("ordinary food and drink will be sold at merchants" .. (MSL.DryRun() and " once Dry run is turned off (for now it only reports). /tui sell shows what would go." or ". /tui sell shows what is kept."))
                    end
                end)
            local function SellOn() return MSL.Enabled() end
            Under(Toggle("mageSellFood", "Sell ordinary food",
                "Plain food that only restores health. Food that restores both health and mana is sold only when drink is on as well.",
                false, function() MSL.Refresh() end), sell, SellOn)
            Under(Toggle("mageSellDrink", "Sell ordinary drink",
                "Plain drink that only restores mana. Food that restores both health and mana is sold only when food is on as well.",
                false, function() MSL.Refresh() end), sell, SellOn)
            Under(Toggle("mageSellDryRun", "Dry run: report only, sell nothing",
                "While this is on, opening a merchant only tells you what would be sold, once, in your own chat. Nothing is sold. It is on until you turn it off: check /tui sell first, then turn it off to sell for real.",
                false, function() MSL.Refresh() end), sell, SellOn)
            if MSW then
                Under(Button("Eligible items and never-sell list", "Open", function()
                    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
                    MSW.Show()
                end, "Shows what would be sold now and what is kept and why, and lets you add items to a never-sell list. Nothing is sold by opening it (same as /tui sell)."), sell, SellOn)
            end
        end

        Header("Broker menu appearance", "How the menus of your data bar launchers look. One background and border for all of them. Only the look changes; what the menus do doesn't.")
        Appearance(R.MenuStyle, "brokerMenu", "menu",
            "A sample menu beside this window that shows these settings as you change them. It does nothing when clicked. Esc closes it.",
            function() R.SpellMenu.TogglePreview() end,
            "Menu appearance", "Puts the background and border of the menus back to their defaults. Nothing else is changed.")

        local RP = R.RefreshmentsPanel
        if RP and RP.Style and refreshToggle then
            Header("Refreshments panel appearance", "How the refreshments panel and its strip under the trade window look. Only the look changes; what they do doesn't.")
            Appearance(RP.Style, "refreshmentsPanel", "panel",
                "Opens the refreshments panel beside this window, to see these settings as you change them. It is the real panel; Esc or its close box shuts it.",
                function() RP.TogglePreview() end,
                "Panel appearance", "Puts the background and border of the refreshments panel and its trade strip back to their defaults. Nothing else is changed.",
                refreshToggle, function() return R:Enabled("mageRefreshments") end)
        end
        if R.RefreshmentShares and R.RefreshmentShares.Register then R.RefreshmentShares.Register(pages.mage.category) end
    end

    -----------------------------------------------------------------------
    Use("chronicle")
    Header("Automatic entries", "A quiet, private journal for this character. It isn't shared, sent or backed up with your configuration, and it never tells you what to do next.")
    local chronicle = Toggle("chronicle", "Keep moments for me automatically",
        "On by default. TwichUI adds a short entry to this character's Chronicle for the moments you pick below. It starts the moment it is on and never looks back. You can always write your own notes, whatever this is set to.",
        false, function() if R.ChronicleRecorder then R.ChronicleRecorder.Refresh() end end)
    local function ChronicleOn() return R:Enabled("chronicle") end
    local function ChronicleToggle(key, label, tooltip)
        Under(Toggle(key, label, tooltip, false, function() if R.ChronicleRecorder then R.ChronicleRecorder.Refresh() end end),
            chronicle, ChronicleOn)
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
        "When you log in to a character that has Chronicle entries, a small bookmark shows the last place the Chronicle noted and how long ago, with a link to open it. It fades by itself, doesn't appear after a reload or in combat, and makes no sound or chat line. It only reads your entries; it adds none. Move it in Edit Mode.",
        false, function() if R.WelcomeBack then R.WelcomeBack.Refresh() end end)
    Choice("chronicleClock", "Time format",
        "How times are shown in your Chronicle.",
        STRING, "12",
        function() return TwichUIDB.ui.chronicleClock == "24" and "24" or "12" end,
        function(value)
            TwichUIDB.ui.chronicleClock = value
            if R.ChronicleWindow then R.ChronicleWindow:Refresh() end
        end,
        { { "12", "12-hour (3:45 PM)" }, { "24", "24-hour (15:45)" } })
    Button("Journey Chronicle", "Open", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if R.ChronicleWindow then R.ChronicleWindow:Show() end
    end, "Opens your Chronicle (same as typing /tui chronicle).")

    -- Appearance of the Chronicle window (chronicle/Appearance.lua). Not the zone arrival card or the Welcome
    -- Back card, and nothing to do with what is recorded.
    local CA = R.ChronicleAppearance
    local Fonts = R.MenuStyle and R.MenuStyle.Fonts
    if CA and CA.Look then
        local resettable = {}
        Header("Appearance", "How the Chronicle window looks: its background, border, text and accents. It changes nothing about what is recorded, your entries or notes, and not the zone arrival or Welcome Back cards. Changes show at once in the window if it is open; the defaults are the look it has always had.")
        Button("Chronicle window", "Show or hide", function()
            if R.ChronicleWindow then R.ChronicleWindow:Toggle() end
        end, "Shows your real Chronicle beside these settings so you can watch each change as you make it. It opens above this panel; drag it by its title to move it aside. It only reads your entries. (The Open button above closes this panel first.)")

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

        Header("Background", "The window's fill. A plain color is the default; textures come from the game, from EllesmereUI (while it is installed) and from any LibSharedMedia pack. The header band and the list behind the entries fade with it, so a faint window is faint all through. Text, icons, buttons and the border keep their own strength.")
        Merge(Appearance(CA.Look, "chronicleLook", "window", nil, nil, nil, nil, nil, nil, {
            order = { "BgTexture", "BgColor", "BgOpacity", "BgTiling", "BgTileSize", "BgInset" },
            advanced = { BgTiling = true, BgTileSize = true, BgInset = true },
            advancedHeader = "Advanced background", advancedTip = "How a textured background repeats and where it sits.",
            labels = { BgTexture = "Background texture", BgColor = "Background color", BgOpacity = "Background opacity" },
            decorate = Decorate,
        }))

        Header("Border", "The window's edge. The Chronicle ledger is the default: a bronze rim with a lit inner edge, tinted by the color below. Any other choice replaces it with a single border of the thickness you set. The window grows to give a border and the content padding room; its place and your entries do not move.")
        Merge(Appearance(CA.Look, "chronicleLook", "window", nil, nil, nil, nil, nil, nil, {
            order = { "BorderTexture", "BorderColor", "BorderOpacity", "BorderSize" },
            labels = { BorderTexture = "Border style", BorderColor = "Border color", BorderOpacity = "Border opacity", BorderSize = "Border thickness" },
            decorate = Decorate,
        }))

        local function Setting(variable, varType, label, key)
            local setting = Proxy("chronicle" .. variable, varType, label, CA.DEFAULTS[key],
                function() return CA.Get(key) end, function(value) CA.Set(key, value) end)
            if setting then resettable[#resettable + 1] = { setting = setting, default = CA.DEFAULTS[key] } end
            return setting
        end
        local function Swatch(variable, key, label, tooltip, isAdvanced)
            local setting = Setting(variable, STRING, label, key)
            if setting and Settings.CreateColorSwatch then
                local row = Settings.CreateColorSwatch(category, setting, tooltip)
                if isAdvanced then Advanced(row) end
                return row
            end
        end
        local function Pick(variable, key, label, tooltip, choices, isAdvanced)
            local setting = Setting(variable, STRING, label, key)
            if setting and Settings.CreateDropdown and Settings.CreateControlTextContainer then
                local row = Settings.CreateDropdown(category, setting, function()
                    local container = Settings.CreateControlTextContainer()
                    for _, choice in ipairs(choices(CA.Get(key))) do container:Add(choice[1], choice[2]) end
                    return container:GetData()
                end, tooltip)
                if isAdvanced then Advanced(row) end
                return row
            end
        end
        local function Check(variable, key, label, tooltip, isAdvanced)
            local setting = Setting(variable, BOOL, label, key)
            if setting and Settings.CreateCheckbox then
                local row = Settings.CreateCheckbox(category, setting, tooltip)
                if isAdvanced then Advanced(row) end
                return row
            end
        end
        local function Slide(variable, key, label, tooltip, isAdvanced)
            local limit = CA.LIMITS[key]
            local setting = Setting(variable, NUMBER, label, key)
            if not (setting and limit and Settings.CreateSlider and Settings.CreateSliderOptions) then return end
            local options = Settings.CreateSliderOptions(limit[1], limit[2], 1)
            if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            end
            local row = Settings.CreateSlider(category, setting, options, tooltip)
            if isAdvanced then Advanced(row) end
            return row
        end
        local function FontChoices(first)
            return function(current)
                return Fonts and Fonts.Choices(current, first) or first
            end
        end

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
            function() return CA.OUTLINE_CHOICES end, true)

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
        Swatch("ScrollThumbColor", "scrollThumbColor", "Scroll bar thumb", "The color of the scroll bar's moving part.", true)
        Swatch("ScrollTrackColor", "scrollTrackColor", "Scroll bar track", "The color of the scroll bar's groove, drawn faintly.", true)
        Swatch("DividerColor", "dividerColor", "Divider color", "The color of the lines between entries and under the title band.", true)

        Advanced(Header("Advanced layout", "Room and strength of the whole window."))
        Slide("Padding", "padding", "Content padding",
            "Extra space between the border and the content, in pixels. The window grows by twice this; its place doesn't change. This is separate from the border's own thickness.", true)
        Slide("WindowOpacity", "windowOpacity", "Overall window opacity",
            "Fades the whole window, text and border included, in percent. It multiplies the background, border and text strengths above rather than replacing them, so 50 here with a 50 background is a quarter. 100 is the default; it cannot go below 40 so the window can always be found.", true)

        Button("Reset Chronicle appearance", "Reset", function()
            for _, entry in ipairs(resettable) do
                if entry.setting.SetValue then pcall(entry.setting.SetValue, entry.setting, entry.default) end
            end
            CA.Reset()
        end, "Puts the Chronicle window's background, border, text, accents and layout back to the defaults. Nothing else changes: your entries and notes, the date filter, the time format, what is recorded, sounds and the cards are left as they are.")
    end

    -----------------------------------------------------------------------
    -- Party pins (pins/). The switch, how pins are placed and labelled, and the pin window's look. The pins
    -- themselves are managed in the pin window, not here.
    local PL = R.PinsLook
    if pages.pins and PL then
        Use("pins")
        Header("Party pins", "Named pins on your world map: local pins only you see, kept between sessions, and party pins shared with party members who have TwichUI, for as long as you are in that party. Players without TwichUI see nothing. Nothing is written in chat. Off until you turn it on.")
        local function PinsOn() return R:Enabled("partyPins") end
        local pinsToggle = Toggle("partyPins", "Party pins",
            "Turns on map pins: place them with the map clicks below or Place a pin in the pin window, see your party's, and manage them all in one window (/tui pins).\n\nOff: TwichUI's pins leave the map, party pins you received are dropped and nothing is sent or taken in. Your local pins are kept for when you turn it on again.",
            false, function()
                if R.PinSync then R.PinSync.Refresh() end
                if R.PinsMap then R.PinsMap.Refresh() end
                if R.PinsMinimap then R.PinsMinimap.Refresh() end
                if R.PinsBroker then R.PinsBroker.Refresh() end
                if R.PinsWay then R.PinsWay.Refresh() end
                if not PinsOn() then
                    if R.PinsWindow then R.PinsWindow.Hide(); R.PinsWindow.CloseMenu() end
                    if R.PinsEditor then R.PinsEditor.Close() end
                    if R.PinsBrokerMenu then R.PinsBrokerMenu.Close() end
                end
            end)
        Under(Button("Your pins", "Open", function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
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
        Under(Choice("pinsBarText", "Text on the data bar",
            "The words beside the entry's icon: how many pins are on your map (\"5 pins, 2 party\"), just the number, \"Map Pins\", or nothing. With none, the icon stays so there is still something to click. Turned off, it reads \"Off\" until you reload.",
            STRING, BR.DEFAULTS.text, function() return BR.Get("text") end, function(value) BR.Set("text", value) end, BR.TEXTS),
            pinsToggle, PinsOn)
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
        if barColorSetting and Settings.CreateColorSwatch then
            Under(Settings.CreateColorSwatch(category, barColorSetting, "The color of the data bar entry's text. The icon keeps its own colors."),
                barColor, function() return PinsOn() and BR.Get("customColor") end)
        end

        local flashToggle = Under(ProxyToggle("pinsBarFlash", "Point out a new pin on the data bar",
            "When a pin arrives from someone in your party, the entry's text changes to \"New pin: <name>\" in the color below, for the time below, and then goes back to what it was. Pins you place, and ones you already had, don't trigger it. Several arriving within the time are counted together.\n\nNothing is written in chat and no sound plays.",
            BR.DEFAULTS.flash, function() return BR.Get("flash") end, function(value) BR.Set("flash", value and true or false) end),
            pinsToggle, PinsOn)
        local function FlashOn() return PinsOn() and BR.Get("flash") end
        local flashSeconds = Proxy("pinsBarFlashSeconds", NUMBER, "New pin shown for (seconds)", BR.DEFAULTS.flashSeconds,
            function() return BR.Get("flashSeconds") end, function(value) BR.Set("flashSeconds", value) end)
        if flashSeconds and Settings.CreateSlider and Settings.CreateSliderOptions then
            local options = Settings.CreateSliderOptions(BR.LIMITS.flashSeconds[1], BR.LIMITS.flashSeconds[2], 1)
            if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right) end
            Under(Settings.CreateSlider(category, flashSeconds, options, "How long the text stays changed after a pin arrives, in seconds. Another pin arriving restarts the time."), flashToggle, FlashOn)
        end
        local flashColor = Proxy("pinsBarFlashColor", STRING, "New pin color", BR.DEFAULTS.flashColor,
            function() return BR.Get("flashColor") end, function(value) BR.Set("flashColor", value) end)
        if flashColor and Settings.CreateColorSwatch then
            Under(Settings.CreateColorSwatch(category, flashColor, "The color of the text while a new pin is pointed out, whatever the text color above. The icon is tinted the same, for a data bar that removes color codes from text (EllesmereUI's Broker Plugin block does, until its Strip Colors option is off for this block; its icon tint is honored)."), flashToggle, FlashOn)
        end

        Header("Data bar menu appearance", "How the menu a click on the data bar entry opens looks: background and border. Only the menu's look changes; its text follows the pin window's font and size, and what it does doesn't change. It starts out looking like the Mage launchers' menus, and changing one doesn't change the other.")
        Appearance(PL.MenuLook, "pinsMenu", "menu",
            "Opens the real pin menu beside this window to see these settings as you change them. It stays until you press this again or Esc. Its buttons work, so it is your actual pins.",
            function() if R.PinsBrokerMenu then R.PinsBrokerMenu.TogglePreview() end end,
            "Pin menu appearance", "Puts the background and border of the data bar menu back to their defaults. Nothing else is changed.",
            pinsToggle, PinsOn)

        local MT = PL.MapText
        Header("Map text", "How pin names look on the world map and the minimap: one look for both. Only the names change; pins, clicks and the pin window don't.")
        local mapReset = {}
        local function MapRemember(variable, varType, label, key)
            local setting = Proxy(variable, varType, label, MT.DEFAULTS[key], function() return MT.Get(key) end, function(value) MT.Set(key, value) end)
            if setting then mapReset[#mapReset + 1] = { setting = setting, default = MT.DEFAULTS[key] } end
            return setting
        end
        local mapFont = MapRemember("pinsMapFont", STRING, "Name font", "font")
        if mapFont and Settings.CreateDropdown and Settings.CreateControlTextContainer then
            Under(Settings.CreateDropdown(category, mapFont, function()
                local container = Settings.CreateControlTextContainer()
                local Fonts = R.MenuStyle and R.MenuStyle.Fonts
                local first = { { "default", "Game font (default)" } }
                for _, choice in ipairs(Fonts and Fonts.Choices(MT.Get("font"), first) or first) do container:Add(choice[1], choice[2]) end
                return container:GetData()
            end, "The font for pin names on the maps. A font that has gone (its media pack is not loaded) is drawn as the game's own and stays chosen."), pinsToggle, PinsOn)
        end
        local mapSize = MapRemember("pinsMapSize", NUMBER, "Name size", "size")
        if mapSize and Settings.CreateSlider and Settings.CreateSliderOptions then
            local options = Settings.CreateSliderOptions(MT.LIMITS.size[1], MT.LIMITS.size[2], 1)
            if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right) end
            Under(Settings.CreateSlider(category, mapSize, options, "The size of pin names on the maps, in points. A name has more room as it grows, and a long one is shortened with ... when it still doesn't fit."), pinsToggle, PinsOn)
        end
        local mapColor = MapRemember("pinsMapColor", STRING, "Name color", "color")
        if mapColor and Settings.CreateColorSwatch then
            Under(Settings.CreateColorSwatch(category, mapColor, "The color of pin names on the maps. A pin's own color tints the pin, not its name."), pinsToggle, PinsOn)
        end
        local mapOutline = MapRemember("pinsMapOutline", STRING, "Name outline", "outline")
        if mapOutline and Settings.CreateDropdown and Settings.CreateControlTextContainer then
            Under(Settings.CreateDropdown(category, mapOutline, function()
                local container = Settings.CreateControlTextContainer()
                for _, choice in ipairs(MT.OUTLINES) do container:Add(choice[1], choice[2]) end
                return container:GetData()
            end, "A dark edge round each letter, which keeps a name readable over a busy map. It works with or without the shadow."), pinsToggle, PinsOn)
        end
        local mapShadow = MapRemember("pinsMapShadow", BOOL, "Name shadow", "shadow")
        if mapShadow and Settings.CreateCheckbox then
            Under(Settings.CreateCheckbox(category, mapShadow, "A soft dark shadow one pixel below and right of each letter. On by default, as the game draws it."), pinsToggle, PinsOn)
        end
        Under(Button("Reset map text", "Reset", function()
            for _, entry in ipairs(mapReset) do
                if entry.setting.SetValue then pcall(entry.setting.SetValue, entry.setting, entry.default) end
            end
            MT.Reset()
        end, "Puts pin names on the maps back to the game font, size 10, white, no outline and the shadow on. Your pins, the map clicks, the label choices and the pin window's look are not touched."), pinsToggle, PinsOn)

        Header("Window appearance", "How the pin window looks: background, border, text and accent. Only the window changes; your pins, the clicks and the map pins don't. It looks complete without EllesmereUI; EllesmereUI's and LibSharedMedia's textures and fonts are listed when they are there.")
        local pinsReset = Appearance(PL.Look, "pinsLook", "window", nil, nil, nil, nil, pinsToggle, PinsOn)
        local function Remember(variable, varType, label, key)
            local setting = Proxy(variable, varType, label, PL.DEFAULTS[key], function() return PL.Get(key) end, function(value) PL.Set(key, value) end)
            if setting then pinsReset[#pinsReset + 1] = { setting = setting, default = PL.DEFAULTS[key] } end
            return setting
        end
        local fontSetting = Remember("pinsFont", STRING, "Text font", "font")
        if fontSetting and Settings.CreateDropdown and Settings.CreateControlTextContainer then
            Under(Settings.CreateDropdown(category, fontSetting, function()
                local container = Settings.CreateControlTextContainer()
                local Fonts = R.MenuStyle and R.MenuStyle.Fonts
                local first = { { "default", "Game font (default)" } }
                for _, choice in ipairs(Fonts and Fonts.Choices(PL.Get("font"), first) or first) do container:Add(choice[1], choice[2]) end
                return container:GetData()
            end, "The font for the pin window's text. A font that has gone (its media pack is not loaded) is drawn as the game's own and stays chosen."), pinsToggle, PinsOn)
        end
        local sizeSetting = Remember("pinsTextSize", NUMBER, "Text size", "textSize")
        if sizeSetting and Settings.CreateSlider and Settings.CreateSliderOptions then
            local options = Settings.CreateSliderOptions(PL.LIMITS.textSize[1], PL.LIMITS.textSize[2], 1)
            if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right) end
            Under(Settings.CreateSlider(category, sizeSetting, options, "The size of pin names, in points. Places, counts and hints are drawn two points smaller."), pinsToggle, PinsOn)
        end
        local accentSetting = Remember("pinsAccent", STRING, "Accent color", "accentColor")
        if accentSetting and Settings.CreateColorSwatch then
            Under(Settings.CreateColorSwatch(category, accentSetting, "The color of the Place a pin button, the selected row and the scroll bar's arrows. Pin colors are each pin's own."), pinsToggle, PinsOn)
        end
        local densitySetting = Remember("pinsDensity", STRING, "Rows", "density")
        if densitySetting and Settings.CreateDropdown and Settings.CreateControlTextContainer then
            Under(Settings.CreateDropdown(category, densitySetting, function()
                local container = Settings.CreateControlTextContainer()
                for _, choice in ipairs(PL.DENSITY) do container:Add(choice[1], choice[2]) end
                return container:GetData()
            end, "Comfortable shows each pin's map and coordinates under its name. Compact is one line per pin (the place is in the pin's tooltip on the map)."), pinsToggle, PinsOn)
        end
        Under(Button("Reset window appearance", "Reset", function()
            for _, entry in ipairs(pinsReset) do
                if entry.setting.SetValue then pcall(entry.setting.SetValue, entry.setting, entry.default) end
            end
            PL.Reset()
        end, "Puts the pin window's background, border, font, text size, accent and rows back to the defaults. Your pins, the map clicks and the label choice are not touched."), pinsToggle, PinsOn)

        Header("New pin window appearance", "How the window that opens when you place a pin (and when you rename or recolor one) looks: background and border. Only that window's look changes; its text follows the pin window's font, size and accent, and what it does doesn't change. It starts out like the pin window, and changing one doesn't change the other.")
        Appearance(PL.EditorLook, "pinsEditor", "window",
            "Opens the real new pin window, with a made-up pin, beside this window to see these settings as you change them. Its Save does nothing. It stays until you press this again or Esc.",
            function() if R.PinsEditor then R.PinsEditor.TogglePreview() end end,
            "New pin window appearance", "Puts the background and border of the new pin window back to their defaults. Nothing else is changed.",
            pinsToggle, PinsOn)
    end

    -----------------------------------------------------------------------
    Use("sharing")
    Header("Addon configurations", "Share the settings of the addons you choose with friends, and apply theirs. You always choose what to apply, and Undo puts your own settings back.")
    local sharing = Toggle("setupSharing", "Configuration sharing",
        "Save the settings of the addons you choose as an addon configuration, send it to friends in game, and apply configurations friends send you. Type /tui share.",
        true, function() if not R:Enabled("setupSharing") and R.Share then R.Share:Settle("module-off") end end)
    local function SharingOn() return R:Enabled("setupSharing") end
    Under(Toggle("acceptSetups", "Let friends send me addon configurations",
        "When on, friends can offer you their addon configuration. You're always asked first, unless you chose \"Always accept\" for that friend. Nothing is applied until you click Apply.",
        false, function() if not R:Enabled("acceptSetups") and R.Share then R.Share:Settle("module-off", true) end end), sharing, SharingOn)
    Toggle("groupCheck", "Version and group check",
        "On by default. Both players need it on to see each other. Other players never see these messages, even without TwichUI.\n\nWhen you're in a group, TwichUI trades version numbers with other TwichUI users (a few bytes, group channel only) and tells you when someone's version is newer or too old to share with. Also powers /tui check and Party compatibility check in /tui share, and a once-per-game-build test message that shows in Sending options whether direct messages reached another TwichUI user.",
        true)
    Under(Button("Configuration sharing", "Open", function()
        if not R:Enabled("setupSharing") then
            R.Print("turn on Configuration sharing first.")
            return
        end
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        R.Window:Show()
    end, "Opens the sharing window: send your setup, review ones friends sent, create backups and run the party compatibility check (same as typing /tui share)."), sharing, SharingOn)
    Button("Addon data", "Open", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if R.StoredDataWindow then R.StoredDataWindow:Show() end
    end, "See which addons keep data between sessions, about how big it is, and look through it. Read-only: nothing can be changed there (same as typing /tui data).")
    Button("Saved Data Explorer", "Open", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if R.ExplorerWindow then R.ExplorerWindow.Show() end
    end, "Look through what TwichUI keeps: its settings, your backups and Undo copies, your saved setup, setups friends sent, the Journey Chronicle, and exactly what Send would send. Read-only: nothing is changed, restored or sent there (same as typing /tui saved).")
    Advanced(Header("Advanced"))
    Advanced(Choice("shareTransport", "Send configurations by",
        "How your configuration travels when you press Send. TwichUI uses only the one you pick and never switches by itself if it fails. Receiving works on all three, whatever you pick here.\n\n" .. R.Share.TRANSPORT_EXPLAIN,
        STRING, "DIRECT",
        function() return R.Share.Transport() end,
        function(value) R.Share.SetTransport(value) end,
        function()
            local list = {}
            for _, key in ipairs(R.Share.TRANSPORTS) do
                list[#list + 1] = { key, R.Share.TRANSPORT_LABEL[key], R.Share.TRANSPORT_HELP[key] }
            end
            return list
        end))

    -----------------------------------------------------------------------
    if pages.troubleshooting then
        Use("troubleshooting")
        local Diag, Window = R.Diag, R.DiagWindow
        Header("Troubleshooting", "A report of how TwichUI is set up and what each part says about itself, to copy and share when something does not work. It is built on your computer when you ask for it. Nothing is sent anywhere.")
        Button("Troubleshooting report", "Open", function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
            Window.Show()
        end, "Opens the report in a window you can read and copy from (click in the text, Ctrl+A, Ctrl+C). It lists settings, module states, counts and reason codes. It leaves out character, realm, guild, friend and BattleTag names, chat, Chronicle entries and your configuration. Same as typing /tui diagnostics.")
        Header("Temporary tracing", "Off until you start it. While on, TwichUI records short notes about its own decisions (why a friend card was skipped, what the food buttons chose) in memory, to include in the report. It stops by itself after 15 minutes, is never saved, and is gone after a reload.")
        local tracing
        local function TracingName() return "Tracing   " .. (Diag.Tracing() and (R.GREEN .. "On|r") or (R.GREY .. "Off|r")) end
        tracing = Button(TracingName(), "Start", function()
            if Diag.Tracing() then Diag.Stop("manual") else Diag.Start() end
        end, "Starts or stops tracing. Start it, reproduce the problem, then open the report. Same as /tui diagnostics start and /tui diagnostics stop.")
        if tracing and tracing.data then
            tracing.data.buttonText = function() return Diag.Tracing() and "Stop" or "Start" end
            Diag.OnChange(function()
                tracing.data.name = TracingName()
                if SettingsPanel and SettingsPanel:IsShown() and SettingsPanel.RepairDisplay then SettingsPanel:RepairDisplay() end
            end)
        end
        Button("Collected records", "Clear", function() Window.Command("clear") end,
            "Forgets the trace records and recent errors kept so far, on this computer only. Tracing, if on, carries on. Same as /tui diagnostics clear.")
    end

    -----------------------------------------------------------------------
    Use("auction")
    Header("Sell from Bags", "A tab in the Auction House for listing items from your bags, one at a time.")
    Toggle("auctionPosting", "Add a Sell from Bags tab to the Auction House",
        "Lists the items in your bags that the auction house will take. Picking one searches its current listings (that item only, never the whole auction house) and suggests a price that matches the lowest comparable listing, with what it's based on. You set the quantity, price and duration; nothing is posted until you press Post. Results aren't saved.",
        false, function() if R.AuctionWindow then R.AuctionWindow.Refresh() end end)

    -----------------------------------------------------------------------
    Use("overview")
    Header("A quiet interface companion for WoW: Forever.",
        "TwichUI makes the game's interface a little clearer and more cohesive, without taking over. Each feature has its own page below, and every one can be turned off.")

    local function OnOff(on, onText, offText)
        if on then return R.GREEN .. (onText or "On") .. "|r" end
        return R.GREY .. (offText or "Off") .. "|r"
    end
    -- key: page to open; status: a word or two for the row.
    local function FeatureRow(key, label, tooltip, status)
        if not CreateSettingsButtonInitializer then return end
        local initializer = CreateSettingsButtonInitializer(label, "Open", function()
            if Settings.OpenToCategory and R.settingsCategories[key] then
                Settings.OpenToCategory(R.settingsCategories[key]:GetID())
            end
        end, tooltip, false)
        layout:AddInitializer(initializer)
        overviewRows[#overviewRows + 1] = { initializer = initializer, label = label, status = status }
    end
    if R.GearPrefs then
        FeatureRow("gear", "Gear comparison", "Quiet upgrade hints in item tooltips and bags, and the stat weights behind them.",
            function() return OnOff(R:Enabled("gearHints") or R:Enabled("gearBagIcons")) end)
    end
    FeatureRow("notifications", "Notifications", "Quiet cards for arriving somewhere new, new training at a level-up, and friends logging in. Previews of each card are on this page.",
        function()
            local on = (R:Enabled("arrival") and 1 or 0) + (R:Enabled("trainingNotice") and 1 or 0) + (R:Enabled("friendLogin") and 1 or 0)
            return OnOff(on > 0, ("%d of 3 on"):format(on), "Off")
        end)
    if pages.qol then
        FeatureRow("qol", "Quality of life", "Small opt-in conveniences: accepting summons and resurrection, releasing in battlegrounds, declining duels, a Quick Keybind button in the Game Menu, and the game's waypoint on RestedXP's destination.",
            function()
                local on = (R:Enabled("qolSummons") and 1 or 0) + (R:Enabled("qolResurrect") and 1 or 0)
                    + (R:Enabled("qolReleasePvP") and 1 or 0) + (R:Enabled("qolDuels") and 1 or 0)
                    + (R:Enabled("qolQuickKeybind") and 1 or 0)
                local total = 5
                if R.QoLGuideWaypoint then
                    total = total + 1
                    if R:Enabled("qolGuideWaypoint") then on = on + 1 end
                end
                return OnOff(on > 0, ("%d of %d on"):format(on, total), "Off")
            end)
    end
    FeatureRow("food", "Food and drink", "Two buttons you click to eat or drink the best food or drink in your bags.",
        function() return OnOff(R:Enabled("foodDrink")) end)
    if pages.mage then
        local mageParts = (R.Refreshments and 3 or 2) + (R.MageSell and 1 or 0)
        FeatureRow("mage", "Mage", "Data bar launchers for your teleports and portals and for conjuring food and water, and a refreshments panel for your group.",
            function()
                local on = (R:Enabled("mageTravel") and 1 or 0) + (R:Enabled("mageConjure") and 1 or 0)
                    + ((R.Refreshments and R:Enabled("mageRefreshments")) and 1 or 0)
                    + ((R.MageSell and R.MageSell.Enabled()) and 1 or 0)
                return OnOff(on > 0, ("%d of %d on"):format(on, mageParts), "Off")
            end)
    end
    FeatureRow("chronicle", "Journey Chronicle", "Your private journal for this character.",
        function() return OnOff(R:Enabled("chronicle"), "Recording", "Notes only") end)
    if pages.pins then
        FeatureRow("pins", "Party pins", "Named pins on your world map, and pins shared with party members who have TwichUI.",
            function() return OnOff(R:Enabled("partyPins")) end)
    end
    FeatureRow("auction", "Auction House", "A Sell from Bags tab for listing items one at a time.",
        function() return OnOff(R:Enabled("auctionPosting")) end)
    FeatureRow("skins", "Addon skins", "The EllesmereUI look for supported addons. Needs EllesmereUI; the rest of TwichUI works without it.", function()
        local installed, on = 0, 0
        for _, skin in ipairs(SKINS) do
            if AddonState(skin.addon) ~= "missing" then
                installed = installed + 1
                if R:Enabled(skin.key) then on = on + 1 end
            end
        end
        if installed == 0 then return R.GREY .. "None installed|r" end
        return OnOff(on > 0, ("%d of %d on"):format(on, installed), "Off")
    end)
    FeatureRow("sharing", "Configuration sharing", "Share your addon settings with friends, and keep backups.",
        function() return OnOff(R:Enabled("setupSharing")) end)
    if pages.troubleshooting then
        FeatureRow("troubleshooting", "Troubleshooting", "A report to copy when something does not work, and optional temporary tracing.",
            function() return R.Diag.Tracing() and (R.GREEN .. "Tracing on|r") or (R.GREY .. "Tracing off|r") end)
    end
    RefreshOverview()

    -----------------------------------------------------------------------
    Header("Help", "Where to find things. Neither button here changes a setting.")
    Button("Welcome", "Show", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if R.Welcome then R.Welcome.Show() end
    end, "Shows the short introduction again (same as typing /tui about). It changes nothing.")
    Button("Chat commands", "List", function() R.RunCommand("help") end,
        "Prints the /tui commands in your chat window: this window, the Chronicle, the sharing window, the troubleshooting report and card previews.")

    -----------------------------------------------------------------------
    Header("General")
    local advancedSetting = Settings.RegisterAddOnSetting(category, "TWICHUI_showAdvanced", "showAdvanced", TwichUIDB.ui, BOOL,
        "Show advanced options", false)
    Settings.CreateCheckbox(category, advancedSetting,
        "Shows an Advanced section on the pages that have one: how upgrade hints are judged and revealed and the bag mark style (Gear comparison), how long the zone card stays (Notifications), how long to wait before accepting a summon or releasing (Quality of life), and how configurations are sent (Configuration sharing). Hidden options keep their values.")
    Toggle("media", "Custom fonts and sounds",
        "Adds Alegreya, Alegreya Sans, Barlow, Cinzel and Spectral fonts, plus the bell alert sounds, to the font and sound lists of EllesmereUI and other addons. Nothing changes until you pick them there.",
        true)
    Toggle("quietLogin", "Hide addon welcome messages",
        "Hides the \"loaded\" and \"type /command for options\" lines addons print when you log in or reload. Errors and warnings still show. Type /twichui hidden to see what was hidden this session.",
        true)

    Settings.RegisterAddOnCategory(root)
end

R:OnInit(function()
    local ok, err = pcall(Build)
    if not ok then geterrorhandler()(err) end
end)
