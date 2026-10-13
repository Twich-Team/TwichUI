-- TwichUI: options in Esc > Options > AddOns > TwichUI (/twichui)
-- The one home for TwichUI's settings, built from Blizzard's own controls. A short overview page links to
-- one page per feature (subcategories of TwichUI). Rarely changed options sit under an "Advanced" header that
-- only shows with "Show advanced options" (on the overview) on; they keep their values (and keep working)
-- while hidden. Stat weights and Refreshment shares are pages of their own (gear/Window.lua,
-- modules/RefreshmentsShares.lua), since a ranked list and a table of numbers don't fit the standard controls.
--
-- How the files fit together (docs/settings.md has the conventions):
--   settings/Kit.lua       this file: the page list and the controls every page uses
--   settings/<Page>.lua    one file per page: K.Page{ ... } with a build function; reads and writes go
--                          through the feature's own Get/Set (or its switch in TwichUIDB.modules)
--   settings/Register.lua  at start-up: makes the pages in order, builds each, adds TwichUI to the list
-- Nothing is built until TwichUI's saved variables are in. The controls below add to the page being built
-- (K.Use), so they are only called from a page's build function.

local R = TwichUI
local K = { pages = {}, definitions = {} }
R.SettingsKit = K

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
-- def: { key, name, parent (a page key, or nil for directly under TwichUI), order (a number: the place in
-- the list), when (optional: whether the page exists for this character and these addons, asked once at
-- start-up), build (fills the page), overview (optional: { label, tip, status = function, when = function },
-- the page's row on the overview) }.
function K.Page(def)
    assert(type(def.key) == "string" and type(def.name) == "string" and type(def.build) == "function", "a page needs a key, a name and a build function")
    K.definitions[#K.definitions + 1] = def
end

-- The page definitions in their place in the list (by order, then as declared).
function K.Ordered()
    local list = {}
    for i, def in ipairs(K.definitions) do list[i] = { def = def, index = i } end
    table.sort(list, function(a, b)
        local oa, ob = a.def.order or 0, b.def.order or 0
        if oa ~= ob then return oa < ob end
        return a.index < b.index
    end)
    for i, entry in ipairs(list) do list[i] = entry.def end
    return list
end

-- The page the controls below add to.
function K.Use(key)
    local page = K.pages[key]
    K.key, K.category, K.layout = key, page.category, page.layout
end

---------------------------------------------------------------------------
-- Small shared pieces
---------------------------------------------------------------------------
function K.AskReload()
    StaticPopupDialogs.TWICHUI_RELOAD = {
        text = "TwichUI: this change takes effect after reloading your UI. Reload now?",
        button1 = RELOADUI or "Reload", button2 = "Later",
        OnAccept = ReloadUI,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("TWICHUI_RELOAD")
end

function K.AddonState(addon)
    return R.Setups and R.Setups.AddonState(addon) or "ready"
end

function K.Loaded(addon)
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon) or false
end

-- Closes the options so a TwichUI window opened from them is not hidden behind the panel.
function K.CloseOptions()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
end

function K.AdvancedShown() return TwichUIDB.ui.showAdvanced == true end

-- Hidden until "Show advanced options" is on. The setting keeps its value.
K.advancedPages = {}   -- [page key] = true for the pages with an Advanced section
function K.Advanced(initializer)
    if initializer and initializer.AddShownPredicate then
        initializer:AddShownPredicate(K.AdvancedShown)
        K.advancedPages[K.key] = true
    end
    return initializer
end

-- The last row of a page with an Advanced section, while those are hidden: says so, and shows them. It turns on
-- the one "Show advanced options" switch (the overview's, K.advancedSetting), so the panel redraws as usual.
function K.AdvancedHint()
    local row = K.Button("Advanced options", "Show", function()
        local setting = K.advancedSetting
        if setting and setting.SetValue then setting:SetValue(true) else TwichUIDB.ui.showAdvanced = true end
    end, "This page has more options under Advanced headers, for things most players never need to change. Show shows them on every page; it is the same as \"Show advanced options\" on the TwichUI page, where you can hide them again. Hidden options keep their values and keep working.")
    if row and row.AddShownPredicate then row:AddShownPredicate(function() return not K.AdvancedShown() end) end
    return row
end

-- Greyed out while the parent checkbox is off. The row's saved value is left alone; its tooltip
-- says why it is greyed out, for as long as it is. why: a sentence, or a function returning one
-- (or nil for the usual "needs <parent> turned on").
function K.Under(initializer, parent, isOn, why)
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

---------------------------------------------------------------------------
-- The overview's feature rows: a name, a short status, and a button to that page. The status is rewritten
-- whenever a toggle changes (no polling).
---------------------------------------------------------------------------
K.overviewRows = {}
function K.RefreshOverview()
    for _, row in ipairs(K.overviewRows) do
        if row.initializer.data then
            row.initializer.data.name = row.label .. "   " .. row.status()
        end
    end
end

function K.OnOff(on, onText, offText)
    if on then return R.GREEN .. (onText or "On") .. "|r" end
    return R.GREY .. (offText or "Off") .. "|r"
end

---------------------------------------------------------------------------
-- Controls. Each adds to the page last chosen with K.Use.
---------------------------------------------------------------------------
function K.Header(text, tooltip)
    if CreateSettingsListSectionHeaderInitializer then
        local initializer = CreateSettingsListSectionHeaderInitializer(text, tooltip)
        K.layout:AddInitializer(initializer)
        return initializer
    end
end

-- A switch in TwichUIDB.modules (its default is Core.lua's DEFAULT_MODULES).
-- The game calls a setting's change callback even when the value did not change (pressing Defaults, or a
-- Reset putting back what was already there), so the switch remembers the value it last acted on:
--   onChange(on)  the feature's own update, only when the value really changed;
--   needsReload   asks to reload only when the value differs from the one the UI loaded with;
--   onStatus()    status text (tooltips) to rewrite, every time: cheap, and never touches the feature.
-- The overview's status is rewritten every time too.
K.switches, K.applied = {}, {}
K.switchOrder = {}   -- keys in the order registered (a page's parent switch before the ones under it)
K.reloadAtLoad = {}  -- [key] = the value the UI loaded with, for switches that take effect after a reload
function K.Toggle(key, label, tooltip, needsReload, onChange, onStatus)
    if needsReload then tooltip = tooltip .. "\n\nTakes effect after you reload your UI." end
    local setting = Settings.RegisterAddOnSetting(K.category, "TWICHUI_" .. key, key, TwichUIDB.modules, K.BOOL, label, R.DEFAULT_MODULES[key])
    local initializer = Settings.CreateCheckbox(K.category, setting, tooltip)
    local atLoad = R:Enabled(key)
    K.switches[key], K.applied[key] = setting, atLoad
    K.switchOrder[#K.switchOrder + 1] = key
    if needsReload then K.reloadAtLoad[key] = atLoad end
    if setting.SetValueChangedCallback then
        setting:SetValueChangedCallback(function()
            local on = R:Enabled(key)
            if on ~= K.applied[key] then
                K.applied[key] = on
                if needsReload and on ~= atLoad then K.AskReload() end
                if onChange then onChange(on) end
            end
            if onStatus then onStatus() end
            K.RefreshOverview()
        end)
    end
    return initializer, setting
end

-- After a profile change (Profiles.lua) has put other values in TwichUIDB.modules: each switch is told to
-- read its value again, in the order registered, so a feature whose switch changed runs its own update once,
-- one that didn't change does nothing, and a switch that needs a reload asks as it does when clicked.
-- Returns the keys whose update failed (each reported); the rest are still told.
function K.SyncSwitches()
    local failed = {}
    for _, key in ipairs(K.switchOrder) do
        local setting = K.switches[key]
        if setting and setting.NotifyUpdate then
            local ok, err = pcall(setting.NotifyUpdate, setting)
            if not ok then
                failed[#failed + 1] = key
                R.Fault("switch " .. key, err)
            end
        end
    end
    return failed
end

-- Whether a switch that takes effect after a reload now differs from the value the UI loaded with.
function K.ReloadPending()
    for key, atLoad in pairs(K.reloadAtLoad) do
        if R:Enabled(key) ~= atLoad then return true end
    end
    return false
end

-- Every option stored somewhere other than the modules table shows its value again (an open panel redraws
-- them). Nothing is set.
function K.RefreshValues()
    for _, setting in ipairs(K.proxies) do
        if setting.NotifyUpdate then
            local ok, err = pcall(setting.NotifyUpdate, setting)
            if not ok then R.Fault("option " .. tostring(setting.GetVariable and setting:GetVariable()), err) end
        end
    end
end

-- Turns a switch on or off through its checkbox, so its update, the overview and an open options panel all
-- follow (R:SetEnabled). applied: the caller has already done what the change needs; only the status follows.
-- Returns false when the switch has no checkbox (the options are not built).
function K.SetSwitch(key, on, applied)
    local setting = K.switches[key]
    if not (setting and setting.SetValue) then return false end
    if applied then K.applied[key] = on end
    setting:SetValue(on)
    return true
end

function K.Button(label, buttonText, onClick, tooltip)
    if CreateSettingsButtonInitializer then
        local initializer = CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true)
        K.layout:AddInitializer(initializer)
        return initializer
    end
end

-- A setting stored somewhere other than the modules table.
K.proxies = {}
function K.Proxy(variable, varType, label, default, get, set)
    if not Settings.RegisterProxySetting then return end
    local setting = Settings.RegisterProxySetting(K.category, "TWICHUI_" .. variable, varType, label, default, get, set)
    if setting then K.proxies[#K.proxies + 1] = setting end
    return setting
end

function K.ProxyToggle(variable, label, tooltip, default, get, set)
    local setting = K.Proxy(variable, K.BOOL, label, default, get, set)
    return setting and Settings.CreateCheckbox(K.category, setting, tooltip)
end

-- options: { { value, label, tooltip }, ... } or a function returning that.
function K.Choice(variable, label, tooltip, varType, default, get, set, options)
    local setting = K.Proxy(variable, varType, label, default, get, set)
    if not (setting and Settings.CreateDropdown and Settings.CreateControlTextContainer) then return end
    return Settings.CreateDropdown(K.category, setting, function()
        local container = Settings.CreateControlTextContainer()
        for _, option in ipairs(type(options) == "function" and options() or options) do
            container:Add(option[1], option[2], option[3])
        end
        return container:GetData()
    end, tooltip)
end

-- A dropdown for an already registered setting. choices(): { { value, label }, ... }.
function K.Dropdown(setting, choices, tooltip)
    if not (setting and Settings.CreateDropdown and Settings.CreateControlTextContainer) then return end
    return Settings.CreateDropdown(K.category, setting, function()
        local container = Settings.CreateControlTextContainer()
        for _, choice in ipairs(choices()) do container:Add(choice[1], choice[2]) end
        return container:GetData()
    end, tooltip)
end

-- A whole-number slider from min to max for an already registered setting, its value shown at the right.
function K.Slider(setting, min, max, tooltip)
    if not (setting and Settings.CreateSlider and Settings.CreateSliderOptions) then return end
    local options = Settings.CreateSliderOptions(min, max, 1)
    if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    end
    return Settings.CreateSlider(K.category, setting, options, tooltip)
end

function K.Swatch(setting, tooltip)
    if setting and Settings.CreateColorSwatch then return Settings.CreateColorSwatch(K.category, setting, tooltip) end
end

function K.Checkbox(setting, tooltip)
    if setting and Settings.CreateCheckbox then return Settings.CreateCheckbox(K.category, setting, tooltip) end
end

-- A Reset button: reset() is the feature's own Reset, which forgets the saved values and redraws once; then
-- each control in resettable ({ setting, default } entries) is told to show its value again. Nothing is set
-- one control at a time, so the feature redraws once, not once per control.
function K.ResetButton(label, resettable, reset, tooltip)
    return K.Button(label, "Reset", function()
        reset()
        for _, entry in ipairs(resettable) do
            local setting = entry.setting
            if setting.NotifyUpdate then pcall(setting.NotifyUpdate, setting) end
        end
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
function K.Appearance(style, prefix, noun, previewTip, preview, resetLabel, resetTip, parent, isOn, options)
    local STRING, NUMBER = K.STRING, K.NUMBER
    local resettable = {}   -- { setting, default }, for Reset
    local advanced = options and options.advanced
    local function Add(initializer, suffix)
        if advanced and advanced[suffix] then K.Advanced(initializer) end
        if parent and initializer then K.Under(initializer, parent, isOn) end
        if initializer and options and options.decorate then options.decorate(suffix, initializer) end
        return initializer
    end
    local function Remember(suffix, varType, label, key)
        if options and options.labels and options.labels[suffix] then label = options.labels[suffix] end
        local setting = K.Proxy(prefix .. suffix, varType, label, style.DEFAULTS[key],
            function() return style.Get(key) end, function(value) style.Set(key, value) end)
        if setting then resettable[#resettable + 1] = { setting = setting, default = style.DEFAULTS[key] } end
        return setting
    end
    local function Textures(suffix, key, label, tooltip, choices)
        local setting = Remember(suffix, STRING, label, key)
        local row = K.Dropdown(setting, choices, tooltip)
        if row then Add(row, suffix) end
    end
    local function Swatch(suffix, key, label, tooltip)
        local row = K.Swatch(Remember(suffix, STRING, label, key), tooltip)
        if row then Add(row, suffix) end
    end
    local function Slider(suffix, key, label, tooltip)
        local limit = style.LIMITS[key]
        local row = K.Slider(Remember(suffix, NUMBER, label, key), limit[1], limit[2], tooltip)
        if row then Add(row, suffix) end
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
            K.Advanced(K.Header(options.advancedHeader or "Advanced look", options.advancedTip or "Textures, thickness and opacity."))
        end
        rows[suffix]()
    end
    if preview then Add(K.Button("Preview", "Show or hide", preview, previewTip), "Preview") end
    if resetLabel then
        Add(K.ResetButton(resetLabel, resettable, style.Reset, resetTip), "Reset")
    end
    return resettable
end
