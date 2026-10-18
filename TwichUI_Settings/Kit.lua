-- TwichUI Settings: the page list and the controls every page uses
-- Each page file (pages/<Page>.lua) declares a page with K.Page{ ... build = function(page) ... end }. Its build
-- function calls the controls below, which only *describe* rows: a label, a tooltip, the setting it reads and
-- writes through its feature's own Get/Set, what it is greyed out under. No frame is
-- made here. The descriptions are made once, the first time the window opens (K.Describe), and are what search
-- reads; Window.lua draws a page's rows the first time that page is shown.
--
-- Rules for a setting (docs/settings.md has the rest):
--   * its variable (TWICHUI_<name>), saved key and default never change for a label or a page move;
--   * reads and writes go through the feature's Get/Set (or its switch, through Switches.lua); a page never
--     writes TwichUIDB itself;
--   * a setter validates, does nothing when the value is the same, saves once and redraws only what it changes.

local R = TwichUI
local K = {
    definitions = {},   -- K.Page definitions, as declared
    pages = {},         -- [key] = page, once described: { key, def, name, parent, group, rows = {} }
    list = {},          -- the described pages, in their order
    variables = {},     -- [TWICHUI_name] = setting
    settings = {},      -- settings in the order made
    rowsById = {},      -- [row id] = row
    switchRows = {},    -- [switch key] = its checkbox row
}
R.SettingsKit = K

K.BOOL, K.STRING, K.NUMBER = "boolean", "string", "number"

-- The left-hand list's groups, in order. A page names its group; a page under another takes its parent's.
K.GROUPS = {
    { key = "home" },
    { key = "everyday", label = "Everyday" },
    { key = "journey", label = "Journey" },
    { key = "class", label = "Gear & class" },
    { key = "addons", label = "Other addons" },
    { key = "config", label = "Your configuration" },
}

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
-- def: { key, name, nav (shorter name in the list or in its parent's tabs, optional), tab (the label of a page that
-- has pages under it, in their tab strip; default "General"), group, parent (a page key: the page is a tab of its
-- parent, not a row in the list), order, description
-- (one line under the title), when (whether the page exists this session), build (describes its rows),
-- host (returns a frame of the feature's own, shown before the page's rows; hostHeight: its height, hostAfter: the
-- name of the section it follows instead, for a page with rows on both sides of it), keywords (extra words search
-- finds the page by), onShow (called each time the window goes to the page, before it is drawn: a page that shows
-- a snapshot takes it there), overview = { label, tip, status = function, when = function } (its row on Home) }.
function K.Page(def)
    assert(type(def.key) == "string" and type(def.name) == "string" and (type(def.build) == "function" or type(def.host) == "function"),
        "a page needs a key, a name and a build or host function")
    K.definitions[#K.definitions + 1] = def
end

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

function K.Use(key)
    K.key, K.current, K.section = key, K.pages[key], nil
end

---------------------------------------------------------------------------
-- Settings: a value a control shows and changes. Like the game's own setting objects: SetValue writes only a
-- value that differs, and the change callbacks run either way (so a control redraws).
---------------------------------------------------------------------------
local Setting = {}
Setting.__index = Setting
K.SettingClass = Setting

function Setting:GetName() return self.name end
function Setting:GetVariable() return self.variable end
function Setting:GetValue() return self.get() end
function Setting:GetDefaultValue() return self.default end
function Setting:SetValueChangedCallback(fn) self.callbacks[#self.callbacks + 1] = fn end

function Setting:Changed()
    local value = self.get()
    for _, fn in ipairs(self.callbacks) do fn(self, value) end
    if K.onSettingChanged then K.onSettingChanged(self) end
end

function Setting:SetValue(value)
    if self.get() ~= value then self.set(value) end
    self:Changed()
end

-- Shows the value again (it was changed somewhere else, or reset in one go).
function Setting:NotifyUpdate()
    self.notified = self.notified + 1
    self:Changed()
end

function Setting:SetValueToDefault()
    if self.default == nil then return false end
    self:SetValue(self.default)
    return true
end

-- variable: without the TWICHUI_ prefix. kind: "proxy" or "switch:<table>.<key>".
local function NewSetting(variable, varType, name, default, get, set, kind)
    local full = "TWICHUI_" .. variable
    assert(not K.variables[full], full .. " is made once")
    local s = setmetatable({
        variable = full, id = variable, varType = varType, name = name, default = default, get = get, set = set,
        kind = kind or "proxy", page = K.current and K.current.name, pageKey = K.key, callbacks = {}, notified = 0,
    }, Setting)
    K.variables[full] = s
    K.settings[#K.settings + 1] = s
    return s
end
K.NewSetting = NewSetting

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local Row = {}
Row.__index = Row
K.RowClass = Row

function Row:AddShownPredicate(fn) self.shown[#self.shown + 1] = fn end
function Row:AddModifyPredicate(fn) self.modify[#self.modify + 1] = fn end
function Row:SetParentInitializer(parent, isOn)
    self.parent = parent
    if isOn then self.modify[#self.modify + 1] = isOn end
end
function Row:GetSetting() return self.data.setting end
function Row:GetName()
    if self.data.setting then return self.data.setting:GetName() end
    return self.data.name
end
function Row:GetTooltip()
    local tip = self.data.tooltip
    if type(tip) == "function" then tip = tip(self) end
    return tip
end
function Row:Enabled()
    for _, fn in ipairs(self.modify) do if not fn() then return false end end
    return true
end
function Row:Shown()
    for _, fn in ipairs(self.shown) do if not fn() then return false end end
    return true
end
-- Why the row is greyed out, while it is (nil otherwise).
function Row:DisabledReason()
    if self:Enabled() then return nil end
    local why = self.why
    if type(why) == "function" then why = why() end
    if type(why) ~= "string" then
        why = self.parent and ("Needs \"" .. tostring(self.parent:GetName()) .. "\" turned on.") or "Not available right now."
    end
    return (why:gsub("^Greyed out: ", ""):gsub("^%l", string.upper))
end

local function Slug(text)
    return (tostring(text or ""):lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[^%w]+", "-"):gsub("^-+", ""):gsub("-+$", ""))
end

-- Adds a row to the page being described. data: { name, tooltip, setting, buttonText, ... }.
local function AddRow(kind, data)
    local page = K.current
    if not page then return nil end
    local row = setmetatable({
        kind = kind, data = data, shown = {}, modify = {}, page = K.key, section = K.section,
        setting = data.setting,
    }, Row)
    if kind == "header" then
        K.section = row
        row.section = nil
    end
    local id = data.setting and data.setting.id or (K.key .. ":" .. Slug(data.name))
    if K.rowsById[id] then
        local n = 2
        while K.rowsById[id .. "-" .. n] do n = n + 1 end
        id = id .. "-" .. n
    end
    row.id = id
    K.rowsById[id] = row
    page.rows[#page.rows + 1] = row
    return row
end
K.AddRow = AddRow

---------------------------------------------------------------------------
-- Small shared pieces
---------------------------------------------------------------------------

function K.AddonState(addon)
    return R.Setups and R.Setups.AddonState(addon) or "ready"
end

function K.Loaded(addon)
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon) or false
end

-- Closes the settings window before a TwichUI window of its own opens (sharing, the report, ...).
function K.CloseOptions()
    if R.SettingsUI then R.SettingsUI.Close() end
end

-- Puts a row in a section other than the one it was described under (a page's own Reset, described after its
-- last section).
function K.InSection(row, header)
    if row then
        row.section = header
        row.fixedSection = true
    end
    return row
end

-- Greyed out while isOn() is false. The saved value is left alone; the tooltip and the row say why, for as long
-- as it is greyed out. why: a sentence, or a function returning one (nil: "needs <parent> turned on").
function K.Under(row, parent, isOn, why)
    if row and parent then
        row:SetParentInitializer(parent, isOn)
        row.why = why
        local base = row.GetTooltip
        row.GetTooltip = function(self)
            local tip = base(self)
            if isOn and not isOn() then
                local reason = type(why) == "function" and why() or (type(why) == "string" and why or nil)
                reason = reason or ("Greyed out: needs \"" .. tostring(parent:GetName()) .. "\" turned on.")
                return (tip and (tip .. "\n\n") or "") .. reason
            end
            return tip
        end
    end
    return row
end

-- A small label beside a row or a section's title (e.g. "Waits for combat").
function K.Badge(row, text)
    if row then row.badge = text end
    return row
end

-- A short line under a row's label that is there whether or not the row is greyed out: what a setting is
-- doing right now that its label doesn't say (a fallback in use, an integration missing). fn() returns the
-- sentence (or nil for none) and, optionally, a tone: "warn" for something the person chose that can't work as
-- set, "reload" for a change waiting on a reload; anything else is quiet. Read whenever the page is drawn, so it
-- is never captured at load. A greyed-out row shows why it is greyed out instead.
function K.Note(row, fn)
    if row then row.note = fn end
    return row
end

-- The note for a data bar entry (a Mage launcher, the pins entry) while no addon provides LibDataBroker, which is
-- the one check Troubleshooting's "Data bar library" line reads too. isOn: whether the entry is wanted (nothing
-- is said about one that is off). It is not an error: the feature's other parts work without a data bar.
function K.DataBarNote(row, isOn)
    return K.Note(row, function()
        local S = R.DiagStatus
        if S and S.DataBarLibrary and not S.DataBarLibrary() and (not isOn or isOn()) then
            return "No data bar addon provides LibDataBroker, so this has nowhere to appear. Nothing else is affected."
        end
    end)
end

-- The status words on a page's title line ("3 of 3 on", "Off"): the window's accent when something is on and
-- its quiet gray when not (the game-wide green and gray are the fallback where the palette isn't loaded).
local function Escape(c)
    local function B(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return ("|cff%02x%02x%02x"):format(B(c[1]), B(c[2]), B(c[3]))
end
function K.OnOff(on, onText, offText)
    local pal = R.SettingsWidgets and R.SettingsWidgets.pal
    if on then return (pal and Escape(pal.tealHi) or R.GREEN) .. (onText or "On") .. "|r" end
    return (pal and Escape(pal.stone) or R.GREY) .. (offText or "Off") .. "|r"
end

-- Something changed that other rows show (a status, the start page's statuses): an open window redraws.
function K.RefreshOverview()
    if K.onRefresh then K.onRefresh() end
end

---------------------------------------------------------------------------
-- Controls. Each adds to the page being described.
---------------------------------------------------------------------------
-- A section: its title and, as tooltip, the sentence or two shown under it.
function K.Header(text, tooltip)
    return AddRow("header", { name = text, tooltip = tooltip })
end

-- A switch in TwichUIDB.modules (default: Core.lua's DEFAULT_MODULES). What a change does is Switches.lua's.
function K.Toggle(key, label, tooltip)
    local W = R.Switches
    if W.NeedsReload(key) then tooltip = tooltip .. "\n\nTakes effect after you reload your UI." end
    local setting = NewSetting(key, K.BOOL, label, R.DEFAULT_MODULES[key],
        function()
            local v = TwichUIDB.modules[key]
            if v == nil then return R:Enabled(key) end
            return v
        end,
        function(value) W.Set(key, value) end,
        "switch:modules." .. key)
    local row = AddRow("checkbox", { setting = setting, tooltip = tooltip })
    if row then
        row.switch = key
        if W.NeedsReload(key) then row.badge = "Reload" end
        K.switchRows[key] = row
    end
    return row, setting
end

-- A setting kept in a table of its own (key in tbl()), not through a feature. Only "Reduce window motion".
function K.TableSetting(variable, key, tbl, label, default, kind)
    return NewSetting(variable, K.BOOL, label, default,
        function() local t = tbl(); return t[key] end,
        function(value) tbl()[key] = value end,
        kind)
end

-- A setting stored by its feature (get/set are the feature's own).
function K.Proxy(variable, varType, label, default, get, set)
    return NewSetting(variable, varType, label, default, get, set, "proxy")
end

function K.ProxyToggle(variable, label, tooltip, default, get, set)
    local setting = K.Proxy(variable, K.BOOL, label, default, get, set)
    return K.Checkbox(setting, tooltip)
end

function K.Checkbox(setting, tooltip)
    if setting then return AddRow("checkbox", { setting = setting, tooltip = tooltip }) end
end

-- A list of { value, label, tooltip } (or a function returning one).
local function Normalize(list)
    local out = {}
    for i, option in ipairs(list or {}) do
        out[i] = { value = option[1], label = option[2], tooltip = option[3] }
    end
    return out
end

-- options: { { value, label, tooltip }, ... } or a function returning that.
function K.Choice(variable, label, tooltip, varType, default, get, set, options)
    local setting = K.Proxy(variable, varType, label, default, get, set)
    local row = AddRow("dropdown", { setting = setting, tooltip = tooltip })
    if row then
        row.choices = function() return Normalize(type(options) == "function" and options() or options) end
        setting.options = row.choices
    end
    return row
end

-- A dropdown for a setting already made. choices(): { { value, label }, ... }.
function K.Dropdown(setting, choices, tooltip)
    if not setting then return end
    local row = AddRow("dropdown", { setting = setting, tooltip = tooltip })
    if row then
        row.choices = function() return Normalize(choices()) end
        setting.options = row.choices
    end
    return row
end

-- A whole-number slider from min to max.
function K.Slider(setting, min, max, tooltip)
    if not setting then return end
    local row = AddRow("slider", { setting = setting, tooltip = tooltip })
    if row then
        row.options = { min = min, max = max, step = 1 }
        setting.slider = row.options
    end
    return row
end

-- A color, saved as AARRGGBB text (as the game's own color swatch does).
function K.Swatch(setting, tooltip)
    if not setting then return end
    local row = AddRow("swatch", { setting = setting, tooltip = tooltip })
    if row then setting.swatch = true end
    return row
end

-- buttonText: text, or a function returning it.
function K.Button(label, buttonText, onClick, tooltip)
    local row = AddRow("button", { name = label, buttonText = buttonText, tooltip = tooltip })
    if row then row.click = onClick end
    return row
end

-- A line of information, not a control: the label, its current value at the right and, under the label, a
-- sentence. value(), detail() and tone() are called whenever the page is drawn and return text (detail: or nil);
-- tone() returns "ok", "warn", "quiet" or nil and only colors the value: the words say the same.
function K.Status(label, value, detail, tooltip, tone)
    local row = AddRow("status", { name = label, tooltip = tooltip })
    if row then row.value, row.detail, row.tone = value, detail, tone end
    return row
end

-- A row on the start page: a feature, its status, and a way to its page.
function K.Link(label, target, status, tooltip)
    local row = AddRow("link", { name = label, tooltip = tooltip })
    if row then
        row.target, row.status = target, status
        row.click = function() R:OpenSettings(target) end
    end
    return row
end

---------------------------------------------------------------------------
-- Resets: what putting settings back to their defaults would change right now
---------------------------------------------------------------------------
-- settings: a list of settings (with defaults). Returns { total, count (how many differ from their default now),
-- on, off (names of on/off settings that would be turned on or off), reload (names of those that take effect
-- only after a reload) }. Reads only.
function K.ResetPlan(settings)
    local plan = { total = #settings, count = 0, on = {}, off = {}, reload = {} }
    for _, s in ipairs(settings) do
        if s.default ~= nil then
            local ok, current = pcall(s.get)
            if ok and current ~= s.default then
                plan.count = plan.count + 1
                if s.varType == K.BOOL then
                    local list = s.default and plan.on or plan.off
                    list[#list + 1] = s.name
                    -- a reload is needed only if the default is not what this session loaded with: a change not yet
                    -- reloaded for, put back to the default, clears instead
                    if s.kind:find("^switch:modules%.") and R.Switches.NeedsReload(s.id) and R.Switches.atLoad[s.id] ~= s.default then
                        plan.reload[#plan.reload + 1] = s.name
                    end
                end
            end
        end
    end
    return plan
end

local function Names(list, max)
    max = max or 4
    local shown = {}
    for i = 1, math.min(#list, max) do shown[i] = "\"" .. tostring(list[i]) .. "\"" end
    local text = table.concat(shown, ", ")
    if #list > max then text = text .. (" and %d more"):format(#list - max) end
    return text
end

-- The part of a reset confirmation that says what changes: how many settings differ, what is turned on or off
-- and whether a reload is needed. Nothing here is a fixed number: it is counted from the settings as they are.
function K.ResetEffects(plan)
    local lines = {}
    lines[#lines + 1] = ("%d of the %d settings shown here differ from their defaults and go back to them."):format(plan.count, plan.total)
    if #plan.on > 0 then lines[#lines + 1] = "Turns on: " .. Names(plan.on) .. "." end
    if #plan.off > 0 then lines[#lines + 1] = "Turns off: " .. Names(plan.off) .. "." end
    if #plan.reload > 0 then
        lines[#lines + 1] = "Takes effect after you reload your UI: " .. Names(plan.reload) .. ". Nothing reloads by itself."
    end
    return table.concat(lines, " ")
end

-- A Reset button: reset() is the feature's own Reset, which forgets the saved values and redraws once; then
-- each control in resettable ({ setting, default } entries) shows its value again. It asks first, with the
-- scope the button's tooltip states (the feature's own sentence about what is and is not reset) and what would
-- actually change now. Nothing is reset until the question is accepted.
function K.ResetButton(label, resettable, reset, tooltip)
    local row
    local function Settings()
        local list = {}
        for i, entry in ipairs(resettable) do list[i] = entry.setting end
        return list
    end
    local function Apply()
        reset()
        for _, entry in ipairs(resettable) do
            local setting = entry.setting
            if setting.NotifyUpdate then pcall(setting.NotifyUpdate, setting) end
        end
        K.RefreshOverview()
    end
    row = K.Button(label, "Reset", function()
        local question = label:find("^Reset") and (label .. "?") or ("Reset " .. label:lower() .. "?")
        local text = question .. "\n\n" .. (tooltip or "") .. "\n\n" .. K.ResetEffects(K.ResetPlan(Settings()))
        if R.Interact and R.Interact.Confirm then
            R.Interact.Confirm("TWICHUI_SETTINGS_RESET_SECTION", text, Apply, { accept = "Reset" })
        else
            Apply()
        end
    end, tooltip)
    if row then row.reset = true end
    return row
end

---------------------------------------------------------------------------
-- One look's controls (modules/MenuStyle.lua): background and border texture, color and opacity, border
-- thickness, a preview and a reset. style: the look; prefix: its settings' names; noun: what it is the look of
-- ("menu", "panel"); parent, isOn: the switch it is greyed out under, if any. preview: nil for no Preview button.
-- resetLabel: nil for no Reset button (the caller resets the returned { setting, default } list itself).
-- options, all optional: order: the rows' suffixes in the order to list them; labels: { [suffix] = a label of
-- its own }; decorate(suffix, row).
---------------------------------------------------------------------------
function K.Appearance(style, prefix, noun, previewTip, preview, resetLabel, resetTip, parent, isOn, options)
    local STRING, NUMBER = K.STRING, K.NUMBER
    local resettable = {}
    local function Add(row, suffix)
        if parent and row then K.Under(row, parent, isOn) end
        if row and options and options.decorate then options.decorate(suffix, row) end
        return row
    end
    local function Remember(suffix, varType, label, key)
        if options and options.labels and options.labels[suffix] then label = options.labels[suffix] end
        local setting = K.Proxy(prefix .. suffix, varType, label, style.DEFAULTS[key],
            function() return style.Get(key) end, function(value) style.Set(key, value) end)
        if setting then resettable[#resettable + 1] = { setting = setting, default = style.DEFAULTS[key] } end
        return setting
    end
    local function Textures(suffix, key, label, tooltip, choices)
        local row = K.Dropdown(Remember(suffix, STRING, label, key), choices, tooltip)
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
    for _, suffix in ipairs(options and options.order or
        { "BgTexture", "BgColor", "BgOpacity", "BorderTexture", "BorderSize", "BorderColor", "BorderOpacity" }) do
        rows[suffix]()
    end
    if preview then Add(K.Button("Preview", "Show or hide", preview, previewTip), "Preview") end
    if resetLabel then
        Add(K.ResetButton(resetLabel, resettable, style.Reset, resetTip), "Reset")
    end
    return resettable
end

---------------------------------------------------------------------------
-- Describing every page (once)
---------------------------------------------------------------------------
local function GroupOf(def)
    if def.group then return def.group end
    local parent = def.parent and K.pages[def.parent]
    return parent and parent.group or "everyday"
end

-- Makes every page that exists this session, in order, and describes its rows. A page that fails to describe
-- is reported and shown as such; the others are still there. Safe to call again: it only works once.
function K.Describe()
    if K.described then return end
    K.described = true
    TwichUIDB.ui = TwichUIDB.ui or {}

    local defs, overview = {}, nil
    for _, def in ipairs(K.Ordered()) do
        local ok, exists = true, true
        if def.when then ok, exists = pcall(def.when) end
        if not ok then
            R.Fault("settings page " .. def.key, exists)
            exists = false
        end
        -- a page under another is only there with it (Refreshment shares without the Mage page)
        if exists and def.parent and not K.pages[def.parent] then exists = false end
        if exists then
            local page = {
                key = def.key, def = def, name = def.name, nav = def.nav or def.name,
                parent = def.parent and K.pages[def.parent] and def.parent or nil, rows = {}, children = {},
            }
            page.group = GroupOf(def)
            if def.key == "overview" then page.group = "home" end
            K.pages[def.key] = page
            if page.parent then table.insert(K.pages[page.parent].children, page) end
            if def.key == "overview" then overview = def else defs[#defs + 1] = def end
        end
    end
    -- The start page is described last, once every page's place is known.
    if overview then defs[#defs + 1] = overview end
    for _, def in ipairs(defs) do
        local page = K.pages[def.key]
        K.list[#K.list + 1] = page
        if def.build then
            K.Use(def.key)
            local ok, err = pcall(def.build, page)
            if not ok then
                page.failed = true
                R.Fault("settings page " .. def.key, err)
            end
        end
    end
    K.Use(nil)
end

-- Every page in navigation order: by group, then each top-level page followed by its children. Search and the
-- tests walk this; the left-hand list shows only the top-level pages (K.SidebarOrder).
function K.NavOrder()
    local out = {}
    for _, group in ipairs(K.GROUPS) do
        for _, page in ipairs(K.list) do
            if page.group == group.key and not page.parent then
                out[#out + 1] = page
                for _, child in ipairs(K.Tabs(page.key)) do
                    if child ~= page then out[#out + 1] = child end
                end
            end
        end
    end
    return out
end

-- The pages the left-hand list shows: the top-level ones, by group. A page under another is reached through its
-- parent's tabs, so it has no row of its own.
function K.SidebarOrder()
    local out = {}
    for _, group in ipairs(K.GROUPS) do
        for _, page in ipairs(K.list) do
            if page.group == group.key and not page.parent then out[#out + 1] = page end
        end
    end
    return out
end

-- The top-level page a page belongs to (itself when it is one).
function K.Root(key)
    local page = K.pages[key]
    return page and (page.parent and K.pages[page.parent] or page) or nil
end

-- The tabs of a page's family, in order: the top-level page first, then each page under it. Empty when the page
-- has nothing under it, so only a feature with secondary pages shows tabs.
function K.Tabs(key)
    local root = K.Root(key)
    if not root or #root.children == 0 then return {} end
    local kids = {}
    for _, child in ipairs(root.children) do kids[#kids + 1] = child end
    table.sort(kids, function(a, b) return (a.def.order or 0) < (b.def.order or 0) end)
    table.insert(kids, 1, root)
    return kids
end

-- A page's label in its family's tab strip: the top-level page is "General" unless it names a tab of its own.
function K.TabLabel(page)
    if page.parent then return page.nav end
    return page.def.tab or "General"
end

-- The settings a page's "Reset this page" puts back (every setting on it with a default; profile choices have
-- none), in the page's order.
function K.Resettable(key)
    local page = K.pages[key]
    local out, seen = {}, {}
    for _, row in ipairs(page and page.rows or {}) do
        local s = row.data.setting
        if s and s.default ~= nil and s.pageKey == key and not seen[s] then
            seen[s] = true
            out[#out + 1] = s
        end
    end
    return out
end

-- What "Reset this page" would change now (K.ResetPlan of the page's settings).
function K.ResetPagePlan(key) return K.ResetPlan(K.Resettable(key)) end

-- The question "Reset this page" asks: names the page, counts what differs, says what is turned on or off and
-- what needs a reload, and what is never touched.
function K.ResetPageText(page, plan)
    return ("Reset every setting on the %s page to its default?\n\n%s\n\nNothing on other pages changes, and map pins, the Journey Chronicle, backups, stat weights and profiles are not affected."):format(
        page.name, K.ResetEffects(plan))
end

-- Puts every setting on one page back to its default, one at a time, through its feature's own setter (as the
-- game's Defaults button did for "this page"). Returns how many there were.
function K.ResetPage(key)
    local list = K.Resettable(key)
    for _, s in ipairs(list) do
        local ok, err = pcall(s.SetValueToDefault, s)
        if not ok then R.Fault("reset " .. s.variable, err) end
    end
    return #list
end

-- Every setting not kept in TwichUIDB.modules shows its value again (after a profile change). Nothing is set.
function K.RefreshValues()
    for _, s in ipairs(K.settings) do
        local ok, err = pcall(s.NotifyUpdate, s)
        if not ok then R.Fault("setting " .. s.variable, err) end
    end
end
