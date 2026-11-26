-- Compact native-listing browser. Frames own input; the controller owns queries,
-- identity, party eligibility and saved filters. No search is initiated by drawing.
local R = TwichUI
local GF, W = R.GroupFinder, {}
GF.Window = W
local WIDTH, HEIGHT, ROW_H, VISIBLE = 920, 548, 42, 8
local LIST_W, DETAIL_W = 584, 302
local ROLES = { "TANK", "HEALER", "DAMAGER" }
local ROLE_NAME = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
local ROLE_ART = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local IVORY, MUTED, GREEN = { .97, .91, .78 }, { .68, .63, .54 }, { .63, .80, .47 }
local f, popup, painting, offset, lastMode = nil, nil, false, 0, nil
local rows, pickerSearch = {}, ""
local ActivitiesMenu, MoreMenu, PresetsMenu, LevelMenu
local function L() return R.Look end
local function CL() return R.CraftLook end
local function Plain(v) return type(v) == "string" and v:gsub("|", "||") or v == nil and "" or tostring(v) end
local function Text(parent, size, serif, color)
    local t = L().Text(parent, "body")
    CL().Font(t, size, true, serif and "serif" or nil)
    t:SetTextColor(unpack(color or IVORY)); t:SetJustifyH("LEFT"); t:SetJustifyV("MIDDLE"); t:SetWordWrap(false)
    return t
end
local function SetText(t, v) t:SetText(Plain(v)) end
local function Tip(host, title, body)
    if host.SetMotionScriptsWhileDisabled then host:SetMotionScriptsWhileDisabled(true) end
    host:HookScript("OnEnter", function(self)
        local a, b = title, body
        if type(a) == "function" then a = a() end
        if type(b) == "function" then b = b() end
        if not GameTooltip or not (a or b) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(Plain(a or "Group Finder"), 1, .94, .80)
        if b and b ~= "" then GameTooltip:AddLine(Plain(b), .85, .80, .70, true) end
        GameTooltip:Show()
    end)
    host:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end
local function Rule(parent, x, y, width)
    local t = L().Solid(parent, "BORDER", { .43, .33, .23 }, .55)
    t:SetPoint("TOPLEFT", x, -y); t:SetSize(width, 1); return t
end
local function Button(parent, label, x, y, width, height, action, kind)
    local b = R.FrameLook.Button(parent, label, width, kind == "confirmation" and "primary" or "secondary", action)
    b:SetPoint("TOPLEFT", x, -y); b:SetHeight(height or 27)
    CL().Control(b, kind); CL().Font(b.text, 13, true)
    return b
end
local function Edit(parent, x, y, width, text, changed, numeric)
    local b = L().EditBox(parent, width, 27)
    b:SetPoint("TOPLEFT", x, -y); CL().Dress(b, "field"); CL().Font(b, 13, true)
    b:SetAutoFocus(false); b:SetMaxLetters(numeric and 3 or 128)
    if numeric then b:SetNumeric(true) end
    b:SetText(text or "")
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    b:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    b:SetScript("OnTextChanged", function(self, user) if user and not painting then changed(self:GetText()) end end)
    return b
end
local function Filters() return GF.filters or {} end
local function Change(key, value) GF.ChangeFilter(key, value) end
local function Activities() return GF.GetActivities() end
local function Activity(id)
    for _, a in ipairs(Activities()) do if a.id == id then return a end end
    return { id = id, name = "Unavailable dungeon (" .. tostring(id) .. ")", icon = R.PATH .. [[media\textures\place-dungeon]] }
end
local function ToggleSet(key, value)
    local set = {}; for k, v in pairs(Filters()[key] or {}) do if v then set[k] = true end end
    set[value] = not set[value] or nil; Change(key, set)
end
local function SetActivities(set, none) GF.SetActivities(set, none) end
local function ToggleActivity(id)
    local set, filters = {}, Filters()
    if not filters.activitiesNone and not next(filters.activities or {}) then
        for _, a in ipairs(Activities()) do set[a.id] = true end
    else for k, on in pairs(filters.activities or {}) do if on then set[k] = true end end end
    set[id] = not set[id] or nil
    SetActivities(set, next(set) == nil)
end
local function RoleText(values, openings)
    local labels, known = {}, false
    for _, role in ipairs(ROLES) do
        local v = values and values[role]
        if v ~= nil then known = true end
        if openings and type(v) == "number" and v > 0 or not openings and v then labels[#labels + 1] = ROLE_NAME[role] end
    end
    if #labels > 0 then return table.concat(labels, " + ") end
    return openings and (known and "No open roles" or "Open roles unknown") or "Roles unknown"
end
local function FirstRole(values, openings)
    for _, role in ipairs(ROLES) do
        local v = values and values[role]
        if openings and type(v) == "number" and v > 0 or not openings and v then return role end
    end
end
local function RoleIcon(host, role, x, y, size)
    local t = host:CreateTexture(nil, "OVERLAY")
    t:SetSize(size or 18, size or 18); t:SetPoint("TOPLEFT", x, -y)
    function t:SetRole(value)
        if ROLE_ART[value] then self:SetTexture(R.PATH .. [[media\partydeath\role-]] .. ROLE_ART[value]); self:Show() else self:Hide() end
    end
    t:SetRole(role); return t
end
-- Real CheckButtons with illustrated marks. Their parent row owns the whole hit
-- region; keyboard/controller clients still see a checked control, not punctuation.
local function Indicator(parent)
    local c = CreateFrame("CheckButton", nil, parent)
    c:SetSize(17, 17); c:EnableMouse(false)
    c.face = CL().Sheet(c, "field", { layer = "ARTWORK", corner = 4 })
    c.circle = c:CreateTexture(nil, "OVERLAY"); c.circle:SetAllPoints(); c.circle:SetTexture(R.PATH .. [[media\style-v2\switch-thumb.tga]])
    c.circle:SetVertexColor(.56, .47, .31)
    c.dot = c:CreateTexture(nil, "OVERLAY"); c.dot:SetSize(8, 8); c.dot:SetPoint("CENTER"); c.dot:SetTexture(R.PATH .. [[media\style-v2\switch-thumb.tga]])
    c.dot:SetVertexColor(1, .74, .26)
    c.tick = c:CreateTexture(nil, "OVERLAY"); c.tick:SetAllPoints(); c.tick:SetTexture(R.PATH .. [[media\loot\check-small]])
    c.mixed = L().Solid(c, "OVERLAY", { .95, .69, .28 }, 1); c.mixed:SetSize(9, 2); c.mixed:SetPoint("CENTER")
    function c:Paint(checked, radio, mixed)
        self:SetChecked(checked == true)
        self.face:SetShown(not radio); self.circle:SetShown(radio == true)
        self.dot:SetShown(radio == true and checked == true)
        self.tick:SetShown(not radio and checked == true and not mixed)
        self.mixed:SetShown(mixed == true)
    end
    return c
end
local function ClosePopup() if popup then popup:Hide() end end
local function NewOption(parent)
    local b = CreateFrame("Button", nil, parent)
    b.hover = L().Solid(b, "BACKGROUND", { .27, .22, .15 }, .55); b.hover:SetAllPoints(); b.hover:Hide()
    b.selected = L().Solid(b, "BACKGROUND", { .055, .20, .16 }, .65); b.selected:SetAllPoints(); b.selected:Hide()
    b.icon = b:CreateTexture(nil, "OVERLAY"); b.icon:SetSize(26, 26)
    b.mark = Indicator(b)
    b.text = Text(b, 13); b.secondary = Text(b, 11, false, MUTED)
    b.input = Edit(parent, 0, 0, 100, "", function(value) if b.entry then b.entry.value = value end end)
    b:SetScript("OnClick", function(self)
        local e = self.entry
        if e and e.action then e.action(); if e.close then ClosePopup() end end
    end)
    b:HookScript("OnEnter", function(self) if self:IsEnabled() then self.hover:Show() end end)
    b:HookScript("OnLeave", function(self) self.hover:Hide() end)
    Tip(b, function() return b.entry and b.entry.text end, function() return b.entry and b.entry.tip end)
    return b
end
-- All small menus share their row style and one reusable frame/control pool.
-- Picker and filter sections supply layout; they do not issue queries while painting.
local function Menu(anchor, title, kind, entries, width, height, options)
    options = options or {}
    if not popup then
        popup = CreateFrame("Frame", nil, f); W.popup = popup
        popup:SetFrameStrata("FULLSCREEN_DIALOG"); popup:SetFrameLevel(f:GetFrameLevel() + 40); popup:EnableMouse(true); popup:SetClampedToScreen(true)
        CL().PanelFace(popup, "walnut")
        popup.title = Text(popup, 18, true); popup.title:SetPoint("TOPLEFT", 13, -9)
        popup.close = R.FrameLook.Close(popup, ClosePopup); popup.close:SetPoint("TOPRIGHT", -8, -8); popup.close:SetSize(24, 24)
        popup.search = Edit(popup, 12, 41, 340, "", function(value) pickerSearch = value; ActivitiesMenu(true) end)
        popup.searchHint = CL().SearchDecoration(popup.search, "Find a dungeon")
        popup.scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
        popup.content = CreateFrame("Frame", nil, popup.scroll); popup.content:SetSize(100, 1); popup.scroll:SetScrollChild(popup.content)
        popup.items = {}; CL().ScrollRail(popup.scroll)
        popup.action = Button(popup, "", 12, 0, 100, 29, function()
            if popup.options and popup.options.action then popup.options.action() end
        end, "confirmation")
        popup.hint = Text(popup, 11, false, MUTED)
        popup.hint:SetPoint("BOTTOMLEFT", 13, 45)
    end
    local same, oldScroll = W.menuKind == kind and popup:IsShown(), popup.scroll:GetVerticalScroll()
    W.menuKind, W.controls, popup.options = kind, {}, options
    popup:ClearAllPoints(); popup:SetSize(width, height)
    popup:SetPoint(options.anchorLeft and "TOPLEFT" or "TOPRIGHT", anchor, options.anchorLeft and "BOTTOMLEFT" or "BOTTOMRIGHT", 0, -4)
    popup.title:SetWidth(width - 54); SetText(popup.title, title)
    local top = options.search and 76 or 39
    popup.search:SetShown(options.search == true); popup.search:SetWidth(width - 24)
    if options.search and popup.search:GetText() ~= pickerSearch then popup.search:SetText(pickerSearch) end
    W.controls["picker-search"] = popup.search
    popup.scroll:ClearAllPoints(); popup.scroll:SetPoint("TOPLEFT", 10, -top)
    popup.scroll:SetPoint("BOTTOMRIGHT", -28, options.action and 67 or 12)
    local contentWidth, fullHeight = width - 40, 1
    popup.content:SetWidth(contentWidth)
    for i, entry in ipairs(entries) do
        local item = popup.items[i]
        if not item then item = NewOption(popup.content); popup.items[i] = item end
        item.entry = entry
        local x, y, w, h = entry.x or 0, entry.y or (i - 1) * 29, entry.width or contentWidth, entry.height or 28
        item:ClearAllPoints(); item:SetPoint("TOPLEFT", x, -y); item:SetSize(w, h)
        item.input:ClearAllPoints(); item.input:SetPoint("TOPLEFT", x, -y); item.input:SetSize(w, h)
        item.hover:Hide(); item.selected:SetShown(entry.checked == true and not entry.header)
        if entry.input then
            item:Hide(); item.input:Show(); item.input:SetText(entry.value or "")
            if entry.id then W.controls[entry.id] = item.input end
        else
            item:Show(); item.input:Hide(); item:SetEnabled(not entry.disabled and not entry.header)
            item.icon:ClearAllPoints(); item.icon:SetPoint("LEFT", 5, 0); item.icon:SetSize(entry.iconSize or 25, entry.iconSize or 25)
            item.icon:SetShown(entry.icon ~= nil); if entry.icon then item.icon:SetTexture(entry.icon) end
            item.mark:ClearAllPoints(); item.mark:SetPoint("RIGHT", -5, 0)
            item.mark:SetShown(entry.checked ~= nil); item.mark:Paint(entry.checked, entry.radio, entry.mixed)
            local inset = entry.icon and (entry.iconSize or 25) + 12 or 7
            item.text:ClearAllPoints(); item.text:SetPoint("LEFT", inset, entry.secondary and 7 or 0)
            item.text:SetSize(math.max(20, w - inset - (entry.checked ~= nil and 29 or 9)), entry.secondary and 19 or h)
            SetText(item.text, entry.text); item.text:SetTextColor(unpack(entry.header and { .83, .68, .44 } or entry.disabled and MUTED or IVORY))
            CL().Font(item.text, entry.header and 14 or 13, true, entry.header and "serif" or nil)
            item.secondary:ClearAllPoints(); item.secondary:SetPoint("LEFT", inset, -9); item.secondary:SetSize(w - inset - 29, 15)
            SetText(item.secondary, entry.secondary); item.secondary:SetShown(entry.secondary ~= nil)
            if entry.id then W.controls[entry.id] = item end
        end
        fullHeight = math.max(fullHeight, y + h)
    end
    for i = #entries + 1, #popup.items do popup.items[i]:Hide(); popup.items[i].input:Hide() end
    popup.content:SetHeight(fullHeight)
    popup.scroll:SetVerticalScroll(same and options.keepScroll and oldScroll or 0)
    popup.action:SetShown(options.action ~= nil); popup.hint:SetShown(options.action ~= nil)
    if options.action then
        popup.action:ClearAllPoints(); popup.action:SetPoint("BOTTOMLEFT", 12, 10); popup.action:SetWidth(width - 24)
        popup.action.text:SetText(options.actionText or "Done"); popup.action:SetEnabled(options.enabled ~= false)
        popup.hint:SetWidth(width - 26); SetText(popup.hint, options.hint)
        W.controls[options.actionID or "menu-action"] = popup.action
    end
    popup:Show()
end
ActivitiesMenu = function(keep)
    local filters, all, entries = Filters(), Activities(), {}
    local selected = filters.activities or {}
    local implicitAll = not filters.activitiesNone and not next(selected)
    local level = GF.Data.Plain(UnitLevel and UnitLevel("player"))
    local suggested, matched, selectedCount = {}, 0, 0
    for _, a in ipairs(all) do
        if a.minLevel and a.maxLevel and type(level) == "number" and level >= a.minLevel and level <= a.maxLevel then suggested[a.id] = true; matched = matched + 1 end
        if implicitAll or selected[a.id] then selectedCount = selectedCount + 1 end
    end
    local allSelected = #all > 0 and selectedCount == #all
    entries[1] = { id = "dungeon-all", text = "All dungeons", secondary = "Select the full available dungeon list", checked = allSelected,
        mixed = selectedCount > 0 and not allSelected, height = 38, y = 0,
        action = function() SetActivities({}, false); ActivitiesMenu(true) end }
    local n, overlap = 0, 0
    for id in pairs(suggested) do n = n + 1; if implicitAll or selected[id] then overlap = overlap + 1 end end
    local exact = n > 0 and overlap == n and selectedCount == n
    entries[2] = { id = "dungeon-level", text = "Dungeons for my level", secondary = matched > 0 and "Select verified suggested activity ranges" or "No verified ranges match your level",
        checked = exact, mixed = not exact and overlap > 0, disabled = matched == 0, height = 38, y = 39,
        action = function() if next(suggested) then SetActivities(suggested, false); ActivitiesMenu(true) end end }
    local query, y = pickerSearch:lower(), 82
    local known = {}
    for _, a in ipairs(all) do
        known[a.id] = true
        if query == "" or a.name:lower():find(query, 1, true) then
            local id = a.id
            entries[#entries + 1] = { id = "dungeon-" .. id, text = a.name, icon = a.iconSmall or a.icon,
                secondary = a.minLevel and a.maxLevel and ("Suggested level " .. a.minLevel .. "–" .. a.maxLevel) or "Suggested levels unavailable",
                checked = implicitAll or selected[id] == true, y = y, height = 36,
                action = function() ToggleActivity(id); ActivitiesMenu(true) end }
            y = y + 37
        end
    end
    for id in pairs(selected) do
        if not known[id] then
            local missing = id
            entries[#entries + 1] = { text = Activity(id).name .. " · remove", checked = true, y = y, height = 30,
                action = function() ToggleActivity(missing); ActivitiesMenu(true) end }; y = y + 31
        end
    end
    if #entries == 2 then entries[#entries + 1] = { text = "No dungeons match this search", disabled = true, y = y, height = 30 } end
    Menu(f.activities, "Choose dungeons", "dungeons", entries, 372, 430, {
        search = true, anchorLeft = true, keepScroll = keep, actionText = "Search selected dungeons", actionID = "picker-search-action",
        enabled = not filters.activitiesNone and GF.state ~= "searching", hint = "Checkboxes filter loaded results immediately.",
        action = function() f.search:ClearFocus(); if GF.Refresh() then ClosePopup() end end,
    })
end
local function Header(entries, label, icon, x, y, width)
    entries[#entries + 1] = { header = true, text = label, icon = R.PATH .. [[media\icons\]] .. icon .. "-small", iconSize = 20, x = x, y = y, width = width, height = 24 }
end
MoreMenu = function()
    local entries, filters, players = {}, Filters(), GF.mode == "players"
    local y, width, col = 0, 446, 197
    if players then
        Header(entries, "Class", "classResources", 0, 0, 400)
        for i, token in ipairs(CLASSES) do
            local class = token
            entries[#entries + 1] = { id = "class-" .. class, text = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class,
                icon = R.PATH .. [[media\guildloc\class-]] .. class .. "-small", iconSize = 19,
                checked = filters.classes and filters.classes[class] == true,
                x = ((i - 1) % 3) * 134, y = 26 + math.floor((i - 1) / 3) * 29, width = 132, height = 28,
                action = function() ToggleSet("classes", class); MoreMenu() end }
        end
        y = 119
    end
    Header(entries, "Playstyle", "profiles", 0, y, col)
    local styles = {}; for _, row in ipairs(GF.snapshot or {}) do if row.playstyle and row.playstyle > 0 then styles[row.playstyle] = true end end
    if filters.playstyle then styles[filters.playstyle] = true end
    local ordered = {}; for style in pairs(styles) do ordered[#ordered + 1] = style end; table.sort(ordered)
    local styleY = y + 25
    entries[#entries + 1] = { id = "style-any", text = "Any playstyle", checked = not filters.playstyle, radio = true, x = 0, y = styleY, width = col, height = 25,
        action = function() Change("playstyle", nil); MoreMenu() end }
    styleY = styleY + 26
    for _, style in ipairs(ordered) do
        local value = style
        local label = GetGeneralPlaystyleString and GetGeneralPlaystyleString(value)
        if label and label ~= "" then
            entries[#entries + 1] = { id = "style-" .. value, text = label, checked = filters.playstyle == value, radio = true, x = 0, y = styleY, width = col, height = 25,
                action = function() Change("playstyle", value); MoreMenu() end }; styleY = styleY + 26
        end
    end
    if #ordered == 0 then entries[#entries + 1] = { text = "No advertised preferences", disabled = true, x = 0, y = styleY, width = col, height = 24 }; styleY = styleY + 25 end
    Header(entries, "Listing age", "reminderWhen", 209, y, col)
    for i, choice in ipairs({ { "Any age", false }, { "Within 5 minutes", 300 }, { "Within 15 minutes", 900 } }) do
        local value = choice[2]
        entries[#entries + 1] = { id = "age-" .. tostring(value or "any"), text = choice[1], checked = (filters.maxAge or false) == value, radio = true,
            x = 209, y = y + 25 + (i - 1) * 26, width = col, height = 25,
            action = function() Change("maxAge", value or nil); MoreMenu() end }
    end
    local bottom = math.max(styleY, y + 107) + 7
    Header(entries, "Social", "profilesSharing", 0, bottom, col)
    for i, choice in ipairs({ { "Friends in listing", "friendsOnly", "friends" }, { "Guild members", "guildOnly", "guild" } }) do
        local key = choice[2]
        entries[#entries + 1] = { id = "social-" .. choice[3], text = choice[1], checked = filters[key] == true,
            x = 0, y = bottom + 25 + (i - 1) * 26, width = col, height = 25,
            action = function() Change(key, not Filters()[key]); MoreMenu() end }
    end
    Header(entries, "Sort by", "reviewChanges", 209, bottom, col)
    for i, choice in ipairs({ { "Recommended", "default" }, { "Newest first", "newest" }, { "Activity name", "activity" } }) do
        local value = choice[2]
        entries[#entries + 1] = { id = "sort-" .. value, text = choice[1], checked = (filters.sort or "default") == value, radio = true,
            x = 209, y = bottom + 25 + (i - 1) * 26, width = col, height = 25,
            action = function() Change("sort", value); MoreMenu() end }
    end
    Menu(f.more, "More filters", "filters", entries, width, math.min(472, bottom + 218), {
        actionText = "Clear local filters", actionID = "clear-local", hint = "Keeps selected dungeons. Resets search, roles and levels too.",
        action = function() GF.ClearFilters(); MoreMenu() end,
    })
end
LevelMenu = function()
    local filters = Filters()
    local lo, hi = { id = "level-min", input = true, value = filters.minLevel and tostring(filters.minLevel) or "", y = 25, height = 27 },
        { id = "level-max", input = true, value = filters.maxLevel and tostring(filters.maxLevel) or "", y = 83, height = 27 }
    Menu(f.level, "Player level", "level", {
        { text = "Minimum (blank = any)", header = true, y = 0, height = 24 }, lo,
        { text = "Maximum (blank = any)", header = true, y = 58, height = 24 }, hi,
        { id = "level-any", text = "Any player level", y = 119, height = 27, action = function() Change("minLevel", nil); Change("maxLevel", nil); ClosePopup() end },
    }, 276, 255, { actionText = "Apply level range", actionID = "level-apply", hint = "Character levels, separate from dungeon suggestions.", action = function()
        local a, b = tonumber(lo.value), tonumber(hi.value)
        if a then a = math.max(1, math.min(255, math.floor(a))) end
        if b then b = math.max(1, math.min(255, math.floor(b))) end
        if a and b and a > b then a, b = b, a end
        Change("minLevel", a); Change("maxLevel", b); ClosePopup()
    end })
end
PresetsMenu = function()
    local name = { id = "preset-name", input = true, value = "", y = 25, height = 27 }
    local entries = { { text = "Save current filters as", header = true, y = 0, height = 24 }, name,
        { id = "preset-save", text = "Save preset", y = 57, height = 28, action = function()
            if GF.SavePreset(name.value) then PresetsMenu() end
        end } }
    local y = 92
    for _, value in ipairs(GF.GetPresets()) do
        local key = value
        entries[#entries + 1] = { id = "preset-load-" .. key, text = key, icon = R.PATH .. [[media\icons\profiles-small]], y = y, height = 28, width = 228,
            tip = "Load the saved filters. Refresh if its dungeon scope differs.", close = true, action = function() GF.LoadPreset(key) end }
        entries[#entries + 1] = { id = "preset-remove-" .. key, text = "Remove", x = 231, y = y, width = 76, height = 28,
            action = function() GF.DeletePreset(key); PresetsMenu() end }; y = y + 30
    end
    Menu(f.presets, "Presets", "presets", entries, 350, math.min(370, y + 54))
end
local function Selected(button, selected)
    button.twichSelected = selected == true
    if button.twichCraft then button.twichCraft:SetSkin(selected and "selection" or "segment") end
    if button.roleChip and button.twichCraft then button.twichCraft:SetTint(selected and .42 or 1, selected and .83 or 1, selected and .73 or 1) end
end
local function Row(index)
    local row = CreateFrame("Button", nil, f.list)
    row:SetPoint("TOPLEFT", 8, -8 - (index - 1) * ROW_H); row:SetSize(LIST_W - 20, ROW_H)
    row.background = L().Solid(row, "BACKGROUND", { .14, .105, .076 }, index % 2 == 0 and .2 or .06); row.background:SetAllPoints()
    row.selection = L().Solid(row, "ARTWORK", { .035, .16, .125 }, .88); row.selection:SetAllPoints()
    row.hover = L().Solid(row, "ARTWORK", { .34, .27, .17 }, .22); row.hover:SetAllPoints(); row.hover:Hide()
    row.rail = L().Solid(row, "OVERLAY", { 1, .65, .13 }, 1); row.rail:SetPoint("TOPLEFT"); row.rail:SetPoint("BOTTOMLEFT"); row.rail:SetWidth(3)
    Rule(row, 4, ROW_H - 1, LIST_W - 29)
    row.icon = row:CreateTexture(nil, "OVERLAY"); row.icon:SetSize(34, 34); row.icon:SetPoint("LEFT", 8, 0)
    row.title = Text(row, 17, true); row.title:SetPoint("TOPLEFT", 50, -1); row.title:SetSize(313, 22)
    row.meta = Text(row, 12, false, MUTED); row.meta:SetPoint("TOPLEFT", 50, -23); row.meta:SetSize(303, 16)
    row.count = Text(row, 16, true); row.count:SetPoint("TOPRIGHT", -9, -1); row.count:SetSize(184, 22); row.count:SetJustifyH("RIGHT")
    row.roleIcon = RoleIcon(row, nil, 366, 24, 16)
    row.roles = Text(row, 12); row.roles:SetPoint("TOPRIGHT", -9, -23); row.roles:SetSize(171, 17); row.roles:SetJustifyH("RIGHT")
    row:SetScript("OnClick", function(self) ClosePopup(); if self.result then GF.Select(self.result.id) end end)
    row:SetScript("OnEnter", function() row.hover:Show() end); row:SetScript("OnLeave", function() row.hover:Hide() end)
    Tip(row, function() return row.result and (GF.mode == "players" and row.result.leader or row.result.activityName) end, function()
        local r = row.result; if not r then return end
        return (r.leader or "Unknown leader") .. "\nLevel " .. (r.level or "?") .. " " .. (r.className or "") .. " · " .. (r.zone or "Location unknown")
            .. "\n" .. RoleText(GF.mode == "players" and r.roles or r.openings, GF.mode ~= "players")
            .. (r.contacted and "\n" .. r.contacted .. " this session" or "")
    end)
    rows[index] = row
end
local function Build()
    if f then return end
    f = CreateFrame("Frame", "TwichUIGroupFinder", UIParent); W.frame = f
    f:SetSize(WIDTH, HEIGHT); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true)
    f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", function(self) self:StartMoving() end); f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:Hide(); if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "TwichUIGroupFinder" end
    local shell = R.FrameLook.Shell(f); CL().Window(f, shell, { header = 41 })
    local header = CreateFrame("Frame", nil, f); header:SetAllPoints(); header:SetFrameLevel(f:GetFrameLevel() + 2)
    f.crest = header:CreateTexture(nil, "OVERLAY"); f.crest:SetTexture(R.PATH .. [[media\icon]]); f.crest:SetSize(38, 38); f.crest:SetPoint("TOPLEFT", 14, -3)
    f.title = Text(header, 23, true); f.title:SetPoint("TOPLEFT", 59, -6); f.title:SetSize(530, 32); f.title:SetText("TwichUI Group Finder")
    f.native = Button(header, "Blizzard Browse", 730, 9, 142, 25, GF.ReturnToNative)
    f.close = R.FrameLook.Close(header, GF.Close); f.close:SetPoint("TOPRIGHT", -13, -10); f.close:SetSize(24, 24)
    f.tabs = {}
    f.tabs.groups = Button(f, "Find a group", 18, 43, 154, 29, function() ClosePopup(); GF.SetMode("groups") end, "segment")
    f.tabs.players = Button(f, "Recruit players", 177, 43, 154, 29, function() ClosePopup(); GF.SetMode("players") end, "segment")
    for _, tab in pairs(f.tabs) do CL().Font(tab.text, 16, true, "serif"); tab.text:SetHeight(24) end
    Rule(f, 12, 76, WIDTH - 24)
    f.activities = Button(f, "Dungeons · All", 18, 84, 240, 28, function() pickerSearch = ""; ActivitiesMenu() end, "dropdown")
    L().Chevron(f.activities, f.activities, "RIGHT", -12, 0, true, IVORY)
    Tip(f.activities, "Selected dungeons", function()
        local filters, names = Filters(), {}
        if filters.activitiesNone then return "No dungeons selected. Open the picker to choose." end
        if not next(filters.activities or {}) then return "All available five-player dungeons. Click to choose a narrower scope." end
        for _, a in ipairs(Activities()) do if filters.activities[a.id] then names[#names + 1] = a.name end end
        return table.concat(names, "\n") .. (GF.queryDirty and "\nSearch selected dungeons to fetch this scope." or "")
    end)
    f.roleLabel = Text(f, 11, false, MUTED); f.roleLabel:SetPoint("TOPLEFT", 274, -79); f.roleLabel:SetSize(240, 15)
    f.roles = {}
    for i, role in ipairs(ROLES) do
        local key = role
        local b = Button(f, "   " .. ROLE_NAME[role], 273 + (i - 1) * 80, 96, 77, 26, function() ToggleSet("roles", key) end, "segment")
        b.roleChip = true; RoleIcon(b, role, 6, 5, 16); CL().Font(b.text, 12, true); f.roles[role] = b
        Tip(b, "Match any selected role", "Several chips use OR: a listing can match any selected role. No selected chips means all roles. The party toggle adds its own condition.")
    end
    f.needs = Button(f, "", 526, 91, 211, 28, function() Change("needsRole", not Filters().needsRole) end)
    f.check = Indicator(f.needs); f.check:SetPoint("LEFT", 7, 0)
    f.needs.text:ClearAllPoints(); f.needs.text:SetPoint("LEFT", 31, 0); f.needs.text:SetPoint("RIGHT", -6, 0); CL().Font(f.needs.text, 13, true)
    Tip(f.needs, "Role matching", function()
        if GF.mode == "players" then return GF.party and GF.party.known and "Advertised roles must fit a known party opening AND any manually selected role chips. No chips means any open role."
            or GF.party and GF.party.reason or "Party roles are unavailable. Manual role chips remain usable." end
        return "Uses the role chips in this view. Several selected roles match any opening; no chips selected matches any open role."
    end)
    f.more = Button(f, "More filters", 752, 91, 150, 28, MoreMenu)
    f.search = Edit(f, 18, 124, 494, "", function(value) Change("search", value) end)
    f.searchHint = CL().SearchDecoration(f.search, "Search groups")
    f.level = Button(f, "Any level", 359, 124, 153, 27, LevelMenu, "dropdown"); L().Chevron(f.level, f.level, "RIGHT", -12, 0, true, IVORY)
    f.presets = Button(f, "Presets", 526, 124, 143, 27, PresetsMenu, "dropdown"); L().Chevron(f.presets, f.presets, "RIGHT", -12, 0, true, IVORY)
    f.refresh = Button(f, "Refresh", 680, 124, 222, 27, function() ClosePopup(); f.search:ClearFocus(); GF.Refresh() end)
    Tip(f.refresh, "Search selected dungeons", "Only this click, the picker Search button, or the refresh key starts a native query. Local filters never search.")
    f.list = CreateFrame("Frame", nil, f); f.list:SetPoint("TOPLEFT", 13, -158); f.list:SetSize(LIST_W, 357); CL().PanelFace(f.list, "espresso")
    f.detail = CreateFrame("Frame", nil, f); f.detail:SetPoint("TOPLEFT", 605, -158); f.detail:SetSize(DETAIL_W, 357); CL().PanelFace(f.detail, "walnut")
    f.slider = CreateFrame("Slider", nil, f.list); f.slider:SetPoint("TOPRIGHT", -4, -9); f.slider:SetSize(6, 337)
    f.slider:SetOrientation("VERTICAL"); f.slider:SetMinMaxValues(0, 0); f.slider:SetValueStep(1)
    f.slider:SetThumbTexture(R.PATH .. [[media\style-v2\switch-thumb.tga]])
    local thumb = f.slider:GetThumbTexture(); thumb:SetSize(5, 28); thumb:SetVertexColor(.72, .51, .28)
    f.slider:SetScript("OnValueChanged", function(_, value) if not painting then offset = math.floor(value + .5); W.Render() end end)
    f.list:EnableMouseWheel(true); f.list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(math.max(0, #(GF.rows or {}) - VISIBLE), offset - delta)); W.Render()
    end)
    for i = 1, VISIBLE do Row(i) end
    f.empty = Text(f.list, 16, true, MUTED); f.empty:SetPoint("CENTER", 0, 15); f.empty:SetSize(500, 78); f.empty:SetWordWrap(true); f.empty:SetJustifyH("CENTER")
    f.clear = Button(f.list, "Clear local filters", 190, 219, 200, 28, GF.ClearFilters); f.clear:Hide()
    local d = f.detail
    d.title = Text(d, 19, true); d.title:SetPoint("TOPLEFT", 13, -10); d.title:SetSize(276, 41); d.title:SetWordWrap(true); d.title:SetJustifyV("TOP")
    d.meta = Text(d, 13); d.meta:SetPoint("TOPLEFT", 13, -53); d.meta:SetSize(276, 20)
    d.zone = Text(d, 12, false, GREEN); d.zone:SetPoint("TOPLEFT", 13, -76); d.zone:SetSize(276, 19)
    d.rule = Rule(d, 12, 101, 278)
    d.section = Text(d, 16, true); d.section:SetPoint("TOPLEFT", 13, -105); d.section:SetSize(276, 23)
    d.slots = {}
    for i = 1, 5 do
        local slot = CreateFrame("Button", nil, d); slot:SetPoint("TOPLEFT", 13, -130 - (i - 1) * 25); slot:SetSize(276, 24)
        slot.face = CL().Sheet(slot, "field", { layer = "BACKGROUND", corner = 5 })
        slot.icon = RoleIcon(slot, nil, 6, 3, 18)
        slot.text = Text(slot, 13); slot.text:SetPoint("LEFT", 32, 0); slot.text:SetWidth(237)
        slot:SetScript("OnClick", function(self)
            if GF.mode ~= "players" or not GF.selected then return end
            local entries = {}; for j, id in ipairs(GF.selected.activities or {}) do
                local a = Activity(id); entries[#entries + 1] = { text = a.name, icon = a.iconSmall or a.icon, disabled = true, y = (j - 1) * 31, height = 30 }
            end
            Menu(self, "Listed dungeons", "listed", entries, 350, math.min(380, 54 + #entries * 31))
        end)
        Tip(slot, function() return slot.fullName end, function() return GF.mode == "players" and "Click to see every listed dungeon." or nil end)
        d.slots[i] = slot
    end
    d.partyTitle = Text(d, 16, true); d.partyTitle:SetPoint("TOPLEFT", 13, -214); d.partyTitle:SetSize(276, 23); d.partyTitle:SetText("Your party")
    d.partyInfo = Text(d, 13); d.partyInfo:SetPoint("TOPLEFT", 13, -240); d.partyInfo:SetSize(276, 32); d.partyInfo:SetWordWrap(true)
    d.whisper = Button(d, "Whisper leader", 13, 280, 276, 31, function() GF.Contact("whisper") end, "confirmation")
    d.invite = Button(d, "Invite", 152, 280, 137, 31, function() GF.Contact("invite") end, "confirmation")
    Tip(d.whisper, "Whisper", function() return GF.ContactReason("whisper") end); Tip(d.invite, "Invite", function() return GF.ContactReason("invite") end)
    d.reason = Text(d, 11, false, MUTED); d.reason:SetPoint("TOPLEFT", 13, -317); d.reason:SetSize(276, 31); d.reason:SetWordWrap(true)
    d.reasonArea = CreateFrame("Frame", nil, d); d.reasonArea:SetAllPoints(d.reason); d.reasonArea:EnableMouse(true)
    Tip(d.reasonArea, "Contact availability", function() return W.actionReason end)
    d.empty = Text(d, 14, false, MUTED); d.empty:SetPoint("TOPLEFT", 13, -76); d.empty:SetSize(276, 90); d.empty:SetWordWrap(true)
    d.empty:SetText("Select a result to see its party, dungeons and available actions.")
    Rule(f, 12, 521, WIDTH - 24)
    f.count = Text(f, 13); f.count:SetPoint("BOTTOMLEFT", 18, 9); f.count:SetSize(284, 20)
    f.status = Text(f, 12, false, MUTED); f.status:SetPoint("BOTTOMRIGHT", -18, 9); f.status:SetSize(578, 20); f.status:SetJustifyH("RIGHT")
    f.statusArea = CreateFrame("Frame", nil, f); f.statusArea:SetAllPoints(f.status); f.statusArea:EnableMouse(true)
    Tip(f.statusArea, "Search status", function() return W.statusDetail end)
    f:SetScript("OnHide", function() ClosePopup(); f.search:ClearFocus(); GF.OnWindowHidden() end)
end
local function Details()
    local d, r, players = f.detail, GF.selected, GF.mode == "players"
    SetText(d.title, r and (players and r.leader or r.activityName) or "Select a listing")
    d.empty:SetShown(not r)
    for _, part in ipairs({ d.meta, d.zone, d.rule, d.section, d.whisper, d.reason, d.reasonArea }) do part:SetShown(r ~= nil) end
    d.invite:SetShown(r ~= nil and players); d.partyTitle:SetShown(r ~= nil and players); d.partyInfo:SetShown(r ~= nil and players)
    if not r then for _, slot in ipairs(d.slots) do slot:Hide() end; return end
    SetText(d.meta, players and ("Level " .. (r.level or "?") .. " " .. (r.className or r.class or "Player")) or ((r.leader or "Unknown leader") .. " · Level " .. (r.level or "?")))
    local near = r.zone and R.QoLGroupFinderZones and R.QoLGroupFinderZones.Nearby(r.zone)
    SetText(d.zone, (r.zone or "Location unknown") .. (near and " · Same area" or "")); d.zone:SetTextColor(unpack(r.zone and GREEN or MUTED))
    SetText(d.section, players and "Listed for" or "Party")
    local roster = {}
    if not players then
        for _, role in ipairs(ROLES) do
            for _, member in ipairs(r.roster or {}) do if member.role == role then roster[#roster + 1] = member end end
            for _ = 1, r.openings and r.openings[role] or 0 do roster[#roster + 1] = { name = ROLE_NAME[role] .. " needed", role = role } end
        end
        for _, member in ipairs(r.roster or {}) do if not ROLE_ART[member.role] then roster[#roster + 1] = member end end
    end
    for i, slot in ipairs(d.slots) do
        local name, role, icon
        if players then
            local id = r.activities and r.activities[i]
            if id and i <= 3 then local a = Activity(id); name, icon = a.name, a.iconSmall or a.icon end
        else local member = roster[i]; name, role = member and member.name or "Roster unavailable", member and member.role end
        slot:SetShown(name ~= nil); slot.fullName = name
        if name then
            SetText(slot.text, name .. (players and i == 3 and #r.activities > 3 and (" +" .. (#r.activities - 3)) or ""))
            slot.icon:SetRole(role); if icon then slot.icon:SetTexture(icon); slot.icon:Show() end
        end
    end
    local p = GF.party or {}
    if players then
        local partyY = 130 + math.min(3, #(r.activities or {})) * 25 + 12
        d.partyTitle:ClearAllPoints(); d.partyTitle:SetPoint("TOPLEFT", 13, -partyY)
        d.partyInfo:ClearAllPoints(); d.partyInfo:SetPoint("TOPLEFT", 13, -(partyY + 25))
    end
    SetText(d.partyInfo, p.known and ((p.count or "?") .. " / 5 · " .. (p.count == 5 and "Party full" or RoleText(p.openings, true) .. " needed")) or p.reason or "Party roles unavailable")
    d.whisper:SetWidth(players and 130 or 276); d.whisper.text:SetText(players and "Whisper" or "Whisper leader")
    CL().Control(d.whisper, players and "secondary" or "confirmation")
    local whyWhisper, whyInvite = GF.ContactReason("whisper", r), GF.ContactReason("invite", r)
    d.whisper:SetEnabled(whyWhisper == nil); d.invite:SetEnabled(whyInvite == nil)
    W.actionReason = players and whyInvite or whyWhisper
    SetText(d.reason, W.actionReason or (r.contacted and r.contacted .. " this session" or ""))
end
function W.Render()
    if not f then return end
    painting = true
    local players, filters, list = GF.mode == "players", Filters(), GF.rows or {}
    if lastMode ~= GF.mode then offset, lastMode = 0, GF.mode end
    Selected(f.tabs.groups, not players); Selected(f.tabs.players, players)
    for _, role in ipairs(ROLES) do Selected(f.roles[role], filters.roles and filters.roles[role] == true) end
    f.roleLabel:SetText(players and "PLAYER ROLES" or "OPEN ROLES")
    f.needs.text:SetText(players and "Fill missing roles" or "Needs my role")
    f.check:Paint(filters.needsRole, false, false); f.needs:SetEnabled(not players or GF.party and GF.party.known == true)
    local n, named = 0, nil; for id in pairs(filters.activities or {}) do n, named = n + 1, id end
    f.activities.text:SetText(filters.activitiesNone and "Dungeons · None selected" or n == 0 and "Dungeons · All" or n == 1 and ("Dungeons · " .. Plain(Activity(named).name)) or ("Dungeons · " .. n .. " selected"))
    f.search:SetWidth(players and 330 or 494)
    if f.search:GetText() ~= (filters.search or "") then f.search:SetText(filters.search or "") end
    f.searchHint:SetText(players and "Search players" or "Search groups"); f.searchHint:SetShown(f.search:GetText() == "" and not f.search:HasFocus())
    f.level:SetShown(players); f.level.text:SetText("Any level")
    if filters.minLevel or filters.maxLevel then f.level.text:SetText("Level " .. (filters.minLevel or 1) .. "–" .. (filters.maxLevel or "any")) end
    local hidden = GF.HiddenFilterCount(); f.more.text:SetText("More filters" .. (hidden > 0 and (" · " .. hidden) or ""))
    f.refresh:SetEnabled(GF.state ~= "searching")
    f.refresh.text:SetText(GF.state == "searching" and "Searching…" or GF.queryDirty and "Search selected dungeons" or "Refresh")
    offset = math.max(0, math.min(math.max(0, #list - VISIBLE), offset))
    f.slider:SetMinMaxValues(0, math.max(0, #list - VISIBLE)); f.slider:SetValue(offset); f.slider:SetShown(#list > VISIBLE)
    W.visibleRows = 0
    for i, row in ipairs(rows) do
        local r = list[offset + i]; row.result = r; row:SetShown(r ~= nil)
        if r then
            W.visibleRows = W.visibleRows + 1
            local selected = GF.selected and GF.selected.id == r.id and GF.selected.identity == r.identity
            row.selection:SetShown(selected); row.rail:SetShown(selected)
            row.icon:SetTexture(players and r.class and R.PATH .. [[media\guildloc\class-]] .. r.class .. "-small" or r.icon)
            SetText(row.title, players and r.leader or r.activityName)
            SetText(row.meta, players and ("Level " .. (r.level or "?") .. " " .. (r.className or r.class or "Player") .. " · " .. (r.zone or "Location unknown"))
                or ((r.leader or "Unknown leader") .. " · " .. (r.zone or "Location unknown")))
            row.count:SetText(players and "" or ((r.numMembers or "?") .. " / 5"))
            row.roleIcon:SetRole(FirstRole(players and r.roles or r.openings, not players))
            SetText(row.roles, RoleText(players and r.roles or r.openings, not players))
            row.roleIcon:ClearAllPoints()
            row.roleIcon:SetPoint("RIGHT", row.roles, "RIGHT", -math.min(171, row.roles:GetStringWidth()) - 5, 0)
        end
    end
    f.empty:SetShown(#list == 0)
    f.clear:SetShown(#list == 0 and (GF.availableCount or 0) > 0 and GF.state == "ready" and not filters.activitiesNone)
    local empty
    if filters.activitiesNone then empty = "Choose at least one dungeon to search."
    elseif GF.state == "searching" then empty = "Searching selected dungeons…"
    elseif GF.state == "idle" then empty = "Choose dungeons, then Search selected dungeons."
    elseif GF.state == "failed" then empty = "Search failed. Use Refresh to try again."
    elseif GF.queryDirty then empty = "Dungeon selection changed. Search selected dungeons."
    elseif GF.state == "stale" then empty = "Results are stale. Refresh to search again."
    elseif GF.availableCount == 0 then empty = players and "No solo players found for these dungeons." or "No groups found for these dungeons."
    else empty = "No matches with these filters." end
    SetText(f.empty, empty); SetText(f.count, #list .. " matching " .. (players and "players" or "groups"))
    W.UpdateStatus(); Details(); painting = false
end
function W.UpdateStatus()
    if not f then return end
    local short, detail = GF.GetStatus()
    W.statusText, W.statusDetail = short, detail
    SetText(f.status, short)
end
function W.Show()
    Build()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    f:SetScale(math.max(.55, math.min(1, (width - 28) / WIDTH, (height - 28) / HEIGHT)))
    f:Show(); W.Render()
end
function W.Hide() if f then f:Hide() end end
function W.IsShown() return f and f:IsShown() or false end
function W.RowCount() return #rows end
function W.Metrics()
    return { width = f and f:GetWidth() or WIDTH, height = f and f:GetHeight() or HEIGHT,
        rowHeight = rows[1] and rows[1]:GetHeight() or ROW_H, visibleRows = #rows }
end
