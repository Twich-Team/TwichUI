-- The Group Finder's shared, lazily constructed browser. All searches and contact
-- actions belong to Controller.lua; drawing and local filter controls live here.
local R = TwichUI
local GF = R.GroupFinder
local W = {}
GF.Window = W

local WIDTH, HEIGHT = 1060, 630
local ROW_H, VISIBLE = 85, 4
local ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }
local ROLE_NAME = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
local ROLE_ART = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local IVORY, MUTED, GREEN = { .97, .91, .78 }, { .69, .63, .53 }, { .60, .83, .41 }
local f, popup, painting
local offset, lastMode = 0, nil
local rows = {}

local function L() return R.Look end
local function CL() return R.CraftLook end
local function Plain(value)
    if type(value) ~= "string" then return value == nil and "" or tostring(value) end
    return (value:gsub("|", "||"))
end
local function Text(parent, size, serif, color)
    local fs = L().Text(parent, "body")
    CL().Font(fs, size, true, serif and "serif" or nil)
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("MIDDLE"); fs:SetWordWrap(false)
    fs:SetTextColor(unpack(color or IVORY))
    return fs
end
local function SetText(fs, value) fs:SetText(Plain(value)) end
local function Rule(parent, x, y, width)
    local t = L().Solid(parent, "BORDER", { .52, .37, .22 }, .75)
    t:SetPoint("TOPLEFT", x, -y); t:SetSize(width, 1)
    return t
end
local function Tip(host, title, body)
    host:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        local a = type(title) == "function" and title() or title
        local b = type(body) == "function" and body() or body
        if not a and not b then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Plain(a or "Group Finder"), 1, .94, .80)
        if b and b ~= "" then GameTooltip:AddLine(Plain(b), .85, .80, .70, true) end
        GameTooltip:Show()
    end)
    host:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end
local function Button(parent, label, x, y, width, height, action, kind)
    local b = R.FrameLook.Button(parent, label, width, kind == "confirmation" and "primary" or "secondary", action)
    b:SetPoint("TOPLEFT", x, -y); b:SetHeight(height or 32)
    CL().Control(b, kind)
    CL().Font(b.text, 16, true)
    return b
end
local function Edit(parent, x, y, width, text, changed, numeric)
    local b = L().EditBox(parent, width, 31)
    b:SetPoint("TOPLEFT", x, -y)
    CL().Dress(b, "field")
    b:SetAutoFocus(false); b:SetMaxLetters(numeric and 3 or 80)
    if numeric then b:SetNumeric(true) end
    b:SetText(text or "")
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    b:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    b:SetScript("OnTextChanged", function(self, user)
        if user and not painting then changed(self:GetText()) end
    end)
    return b
end
local function Change(key, value) if GF.ChangeFilter then GF.ChangeFilter(key, value) end end
local function Filters() return GF.filters or {} end
local function ToggleSet(key, value)
    local copy = {}
    for k, v in pairs(Filters()[key] or {}) do if v then copy[k] = true end end
    copy[value] = not copy[value] or nil
    Change(key, copy)
end
local function ActivityList()
    if GF.GetActivities then return GF.GetActivities() end
    return GF.Data and GF.Data.Activities and GF.Data.Activities() or {}
end
local function ActivityName(id)
    for _, a in ipairs(ActivityList()) do if a.id == id then return a.name end end
    return "Unavailable dungeon (" .. tostring(id) .. ")"
end
local function ActivityIcon(id)
    for _, a in ipairs(ActivityList()) do if a.id == id then return a.iconSmall or a.icon end end
    return R.PATH .. [[media\textures\place-dungeon]]
end
local function RoleText(roles, openings)
    local out = {}
    for _, role in ipairs(ROLE_ORDER) do
        if openings and type(roles and roles[role]) == "number" and roles[role] > 0 or not openings and roles and roles[role] then
            out[#out + 1] = ROLE_NAME[role]
        end
    end
    if #out > 0 then return table.concat(out, " + ") end
    if openings and roles then return "No open roles" end
    return openings and "Open roles unknown" or "Role unknown"
end
local function RoleIcon(host, role, x, y, size)
    local icon = host:CreateTexture(nil, "OVERLAY")
    icon:SetSize(size or 24, size or 24); icon:SetPoint("TOPLEFT", x, -y)
    function icon:SetRole(value)
        if ROLE_ART[value] then self:SetTexture(R.PATH .. [[media\partydeath\role-]] .. ROLE_ART[value]); self:Show() else self:Hide() end
    end
    icon:SetRole(role)
    return icon
end
local function FirstRole(row, openings)
    local values = openings and row.openings or row.roles
    for _, role in ipairs(ROLE_ORDER) do
        local v = values and values[role]
        if openings and type(v) == "number" and v > 0 or not openings and v then return role end
    end
end
local function ClosePopup() if popup then popup:Hide() end end

-- One reusable, scrollable menu; controls remain real native buttons/edit boxes.
local function Menu(anchor, title, entries, width)
    if not popup then
        popup = CreateFrame("Frame", nil, f)
        popup:SetFrameLevel(f:GetFrameLevel() + 40); popup:EnableMouse(true)
        CL().PanelFace(popup, "walnut")
        popup.title = Text(popup, 19, true)
        popup.title:SetPoint("TOPLEFT", 14, -12); popup.title:SetWidth(290)
        popup.close = R.FrameLook.Close(popup, ClosePopup)
        popup.close:SetPoint("TOPRIGHT", -8, -8)
        popup.scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
        popup.scroll:SetPoint("TOPLEFT", 10, -42); popup.scroll:SetPoint("BOTTOMRIGHT", -29, 12)
        popup.content = CreateFrame("Frame", nil, popup.scroll)
        popup.content:SetSize(310, 1); popup.scroll:SetScrollChild(popup.content)
        popup.items = {}
        CL().ScrollRail(popup.scroll)
    end
    local menuWidth = width or 370
    popup:ClearAllPoints(); popup:SetSize(menuWidth, math.min(480, 62 + #entries * 32))
    popup:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    popup:SetClampedToScreen(true)
    popup.content:SetWidth(menuWidth - 42); popup.content:SetHeight(math.max(1, #entries * 32))
    popup.scroll:SetVerticalScroll(0)
    SetText(popup.title, title)
    for i, entry in ipairs(entries) do
        local item = popup.items[i]
        if not item then
            item = Button(popup.content, "", 0, (i - 1) * 32, menuWidth - 44, 30, function(self)
                local e = self.entry
                if e and e.action then e.action(); if e.close then ClosePopup() end end
            end)
            item.input = Edit(popup.content, 0, (i - 1) * 32, menuWidth - 44, "", function(value)
                local e = item.entry
                if e then e.value = value end
            end)
            popup.items[i] = item
        end
        item.entry = entry
        item:SetWidth(menuWidth - 44); item.input:SetWidth(menuWidth - 44)
        if entry.input then
            item:Hide(); item.input:Show(); item.input:SetText(entry.value or "")
        else
            item.input:Hide(); item:Show()
            item.text:SetText((entry.checked == nil and "" or entry.checked and "|cffd9b963[+] |r" or "[  ] ") .. Plain(entry.text))
            item.text:SetJustifyH("LEFT"); item.text:SetWidth(menuWidth - 60)
            item:SetEnabled(not entry.disabled)
        end
    end
    for i = #entries + 1, #popup.items do popup.items[i]:Hide(); popup.items[i].input:Hide() end
    popup:Show()
end
local function ActivitiesMenu()
    local filters, entries = Filters(), {}
    entries[#entries + 1] = { text = "All dungeons", checked = not next(filters.activities or {}), action = function() Change("activities", {}); ActivitiesMenu() end }
    local supported, suggested = false, {}
    local level = UnitLevel and UnitLevel("player")
    if issecretvalue and issecretvalue(level) then level = nil end
    for _, activity in ipairs(ActivityList()) do
        if activity.minLevel and activity.maxLevel then
            supported = true
            if type(level) == "number" and level >= activity.minLevel and level <= activity.maxLevel then suggested[activity.id] = true end
        end
    end
    if supported then
        entries[#entries + 1] = { text = next(suggested) and "Dungeons for my level" or "No suggested dungeons for your level", disabled = not next(suggested), action = function()
            if next(suggested) then Change("activities", suggested); ActivitiesMenu() end
        end }
    end
    local known = {}
    for _, activity in ipairs(ActivityList()) do
        local id = activity.id; known[id] = true
        entries[#entries + 1] = { text = activity.name, checked = filters.activities and filters.activities[id] == true,
            action = function() ToggleSet("activities", id); ActivitiesMenu() end }
    end
    for id in pairs(filters.activities or {}) do
        if not known[id] then entries[#entries + 1] = { text = ActivityName(id) .. " — remove", checked = true,
            action = function() ToggleSet("activities", id); ActivitiesMenu() end } end
    end
    Menu(f.activities, "Choose dungeons", entries, 390)
end
local function LevelMenu()
    local filters = Filters()
    local min = { input = true, value = filters.minLevel and tostring(filters.minLevel) or "" }
    local max = { input = true, value = filters.maxLevel and tostring(filters.maxLevel) or "" }
    Menu(f.level, "Player level", {
        { text = "Minimum level (blank = any)", disabled = true }, min,
        { text = "Maximum level (blank = any)", disabled = true }, max,
        { text = "Apply level range", close = true, action = function()
            local lo, hi = tonumber(min.value), tonumber(max.value)
            if lo then lo = math.max(1, math.min(255, math.floor(lo))) end
            if hi then hi = math.max(1, math.min(255, math.floor(hi))) end
            if lo and hi and lo > hi then lo, hi = hi, lo end
            Change("minLevel", lo); Change("maxLevel", hi)
        end },
        { text = "Any player level", close = true, action = function() Change("minLevel", nil); Change("maxLevel", nil) end },
    }, 300)
end
local function MoreMenu()
    local filters, entries = Filters(), {}
    if GF.mode == "players" then
        for _, token in ipairs(CLASS_ORDER) do
            local class = token
            entries[#entries + 1] = { text = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class,
                checked = filters.classes and filters.classes[class] == true,
                action = function() ToggleSet("classes", class); MoreMenu() end }
        end
        entries[#entries + 1] = { text = "Damage style: Unknown", disabled = true }
    end
    for _, option in ipairs({ { "Default order", "default" }, { "Newest first", "newest" }, { "Activity name", "activity" } }) do
        local value = option[2]
        entries[#entries + 1] = { text = option[1], checked = (filters.sort or "default") == value,
            action = function() Change("sort", value); MoreMenu() end }
    end
    for _, option in ipairs({ { "Any listing age", false }, { "Listed within 5 minutes", 300 }, { "Listed within 15 minutes", 900 } }) do
        local value = option[2]
        entries[#entries + 1] = { text = option[1], checked = (filters.maxAge or false) == value,
            action = function() Change("maxAge", value or nil); MoreMenu() end }
    end
    entries[#entries + 1] = { text = "Friends in listing", checked = filters.friendsOnly == true,
        action = function() Change("friendsOnly", not filters.friendsOnly); MoreMenu() end }
    entries[#entries + 1] = { text = "Guild members in listing", checked = filters.guildOnly == true,
        action = function() Change("guildOnly", not filters.guildOnly); MoreMenu() end }
    -- Native values are reliable only when an actual listing provides them.
    local styles = {}
    for _, row in ipairs(GF.snapshot or GF.rows or {}) do if type(row.playstyle) == "number" and row.playstyle > 0 then styles[row.playstyle] = true end end
    if filters.playstyle then entries[#entries + 1] = { text = "Any playstyle", action = function() Change("playstyle", nil); MoreMenu() end } end
    local orderedStyles = {}; for value in pairs(styles) do orderedStyles[#orderedStyles + 1] = value end
    table.sort(orderedStyles)
    for _, value in ipairs(orderedStyles) do
        local style = value
        local label = GetGeneralPlaystyleString and GetGeneralPlaystyleString(style)
        if type(label) == "string" and label ~= "" then
            entries[#entries + 1] = { text = label, checked = filters.playstyle == style,
                action = function() Change("playstyle", filters.playstyle ~= style and style or nil); MoreMenu() end }
        end
    end
    Menu(f.more, "More filters", entries, 390)
end
local function PresetsMenu()
    local name = { input = true, value = "" }
    local entries = { { text = "Name this preset", disabled = true }, name,
        { text = "Save current filters", action = function()
            if GF.SavePreset and name.value and name.value:match("%S") then GF.SavePreset(name.value); PresetsMenu() end
        end } }
    local names = GF.GetPresets and GF.GetPresets() or {}
    for _, value in ipairs(names) do
        local key = value
        entries[#entries + 1] = { text = "Load: " .. key, close = true, action = function() if GF.LoadPreset then GF.LoadPreset(key) end end }
        entries[#entries + 1] = { text = "Remove: " .. key, action = function() if GF.DeletePreset then GF.DeletePreset(key); PresetsMenu() end end }
    end
    Menu(f.presets, "Presets", entries, 360)
end

local function Row(index)
    local row = CreateFrame("Button", nil, f.list)
    row:SetPoint("TOPLEFT", 12, -16 - (index - 1) * ROW_H); row:SetSize(638, ROW_H - 1)
    row.face = CL().PanelFace(row, "walnut")
    row.selection = L().Solid(row, "ARTWORK", { .025, .095, .075 }, .94); row.selection:SetAllPoints()
    row.selectionGrain = CL().QuietTile(row, "card", "ARTWORK", 0)
    row.selectionGrain:SetVertexColor(.12, .35, .28, .22)
    row.selectedRim = CL().Sheet(row, "selection", { layer = "ARTWORK", sub = 1, corner = 8 })
    row.selectedRim:SetTint(.48, .71, .61)
    row.selectedRim.parts[5]:SetAlpha(0)
    row.rail = L().Solid(row, "OVERLAY", { 1, .63, .06 }, 1)
    row.rail:SetPoint("TOPLEFT", 0, -1); row.rail:SetPoint("BOTTOMLEFT", 0, 1); row.rail:SetWidth(5)
    row.icon = row:CreateTexture(nil, "OVERLAY"); row.icon:SetSize(69, 69); row.icon:SetPoint("LEFT", 14, 0)
    row.title = Text(row, 27, true); row.title:SetPoint("TOPLEFT", 96, -10); row.title:SetSize(304, 34)
    row.meta = Text(row, 16); row.meta:SetPoint("TOPLEFT", 97, -46); row.meta:SetSize(319, 24)
    row.count = Text(row, 25, true); row.count:SetPoint("TOPLEFT", 424, -10); row.count:SetSize(174, 32)
    row.roleIcon = RoleIcon(row, nil, 424, 46, 24)
    row.roles = Text(row, 16); row.roles:SetPoint("TOPLEFT", 454, -46); row.roles:SetSize(174, 24)
    row.contacted = Text(row, 12, false, MUTED); row.contacted:SetPoint("TOPRIGHT", -10, -5); row.contacted:SetSize(80, 16); row.contacted:SetJustifyH("RIGHT")
    row:SetScript("OnClick", function(self) ClosePopup(); if self.result then GF.Select(self.result.id) end end)
    Tip(row, function() return row.result and (GF.mode == "players" and row.result.leader or row.result.activityName) end,
        function()
            local r = row.result
            if not r then return end
            return (r.leader or "Unknown leader") .. " · " .. (r.zone or "Location unknown") .. "\n" .. RoleText(GF.mode == "players" and r.roles or r.openings, GF.mode ~= "players")
        end)
    rows[index] = row
end

local function Build()
    if f then return end
    f = CreateFrame("Frame", "TwichUIGroupFinder", UIParent)
    W.frame = f
    f:SetSize(WIDTH, HEIGHT); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:Hide()
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "TwichUIGroupFinder" end
    local shell = R.FrameLook.Shell(f)
    CL().Window(f, shell, { header = 55 })
    local header = CreateFrame("Frame", nil, f); header:SetAllPoints(); header:SetFrameLevel(f:GetFrameLevel() + 2)
    f.crest = header:CreateTexture(nil, "OVERLAY"); f.crest:SetTexture(R.PATH .. [[media\icon]]); f.crest:SetSize(58, 58); f.crest:SetPoint("TOPLEFT", 17, -5)
    f.title = Text(header, 32, true); f.title:SetPoint("TOPLEFT", 83, -12); f.title:SetSize(620, 40); f.title:SetText("TwichUI Group Finder")
    f.native = Button(header, "Blizzard Browse", 828, 17, 174, 31, function() ClosePopup(); GF.ReturnToNative() end)
    f.close = R.FrameLook.Close(header, function() if GF.Close then GF.Close() else W.Hide() end end)
    f.close:SetPoint("TOPRIGHT", -17, -17); f.close:SetSize(30, 30)
    f.tabs = {}
    f.tabs.groups = Button(f, "Find a group", 24, 65, 194, 37, function() ClosePopup(); GF.SetMode("groups") end, "segment")
    f.tabs.players = Button(f, "Recruit players", 224, 65, 194, 37, function() ClosePopup(); GF.SetMode("players") end, "segment")
    CL().Font(f.tabs.groups.text, 21, true, "serif"); CL().Font(f.tabs.players.text, 21, true, "serif")
    f.tabs.groups.text:SetHeight(30); f.tabs.players.text:SetHeight(30)
    Rule(f, 14, 106, 1032)
    f.category = Button(f, "Dungeons", 25, 117, 141, 32, ActivitiesMenu, "dropdown")
    f.activities = Button(f, "All dungeons", 168, 117, 190, 32, ActivitiesMenu, "dropdown")
    L().Chevron(f.activities, f.activities, "RIGHT", -13, 0, true, IVORY)
    f.roles = {}
    for i, role in ipairs(ROLE_ORDER) do
        local key = role
        local b = Button(f, "   " .. ROLE_NAME[role], 387 + (i - 1) * 103, 117, 98, 32,
            function() ToggleSet("roles", key) end, "segment")
        RoleIcon(b, role, 10, 7, 20); f.roles[role] = b
    end
    f.needs = Button(f, "", 717, 117, 171, 32, function() Change("needsRole", not Filters().needsRole) end)
    f.check = f.needs:CreateTexture(nil, "OVERLAY"); f.check:SetTexture(R.PATH .. [[media\guides\status-done-small]]); f.check:SetSize(25, 25); f.check:SetPoint("LEFT", 5, 0)
    f.needs.text:ClearAllPoints(); f.needs.text:SetPoint("LEFT", 31, 0); f.needs.text:SetWidth(136)
    CL().Font(f.needs.text, 14, true)
    Tip(f.needs, "Role matching", function()
        if GF.mode == "players" then return GF.party and GF.party.reason or "Uses known openings in your current party. Manual roles remain available." end
        return "Matches openings against the roles selected here."
    end)
    f.more = Button(f, "More filters", 906, 117, 128, 32, MoreMenu)
    f.search = Edit(f, 25, 161, 586, "", function(value) Change("search", value) end)
    f.searchHint = CL().SearchDecoration(f.search, "Search groups")
    f.level = Button(f, "Any level", 462, 161, 149, 32, LevelMenu, "dropdown")
    L().Chevron(f.level, f.level, "RIGHT", -12, 0, true, IVORY)
    f.presets = Button(f, "Presets", 635, 161, 166, 32, PresetsMenu, "dropdown")
    L().Chevron(f.presets, f.presets, "RIGHT", -12, 0, true, IVORY)
    f.refresh = Button(f, "Refresh", 906, 161, 128, 32, function() ClosePopup(); f.search:ClearFocus(); GF.Refresh() end)
    Tip(f.refresh, "Refresh listings", "Searches the selected dungeons. You can also bind Refresh Group Finder in the game's key bindings.")
    Rule(f, 14, 202, 1032)
    f.list = CreateFrame("Frame", nil, f); f.list:SetPoint("TOPLEFT", 14, -207); f.list:SetSize(663, 374)
    CL().PanelFace(f.list, "espresso")
    f.detail = CreateFrame("Frame", nil, f); f.detail:SetPoint("TOPLEFT", 684, -207); f.detail:SetSize(362, 374)
    CL().PanelFace(f.detail, "walnut")
    f.slider = CreateFrame("Slider", nil, f.list)
    f.slider:SetPoint("TOPRIGHT", -4, -15); f.slider:SetSize(7, 340)
    f.slider:SetOrientation("VERTICAL"); f.slider:SetMinMaxValues(0, 0); f.slider:SetValueStep(1)
    f.slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = f.slider:GetThumbTexture(); thumb:SetSize(5, 28); thumb:SetVertexColor(.64, .45, .25)
    f.slider:SetScript("OnValueChanged", function(_, value) if not painting then offset = math.floor(value + .5); W.Render() end end)
    f.list:EnableMouseWheel(true)
    f.list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(math.max(0, #(GF.rows or {}) - VISIBLE), offset - delta)); W.Render()
    end)
    for i = 1, VISIBLE do Row(i) end
    f.empty = Text(f.list, 17, false, MUTED); f.empty:SetPoint("CENTER"); f.empty:SetSize(570, 130); f.empty:SetWordWrap(true); f.empty:SetJustifyH("CENTER")
    local d = f.detail
    d.title = Text(d, 29, true); d.title:SetPoint("TOPLEFT", 19, -10); d.title:SetSize(326, 38)
    d.meta = Text(d, 17); d.meta:SetPoint("TOPLEFT", 19, -43); d.meta:SetSize(324, 24)
    d.zone = Text(d, 16, false, GREEN); d.zone:SetPoint("TOPLEFT", 20, -69); d.zone:SetSize(323, 26)
    Rule(d, 18, 99, 326)
    d.section = Text(d, 23, true); d.section:SetPoint("TOPLEFT", 19, -105); d.section:SetSize(326, 31)
    d.slots = {}
    for i = 1, 5 do
        local slot = CreateFrame("Frame", nil, d); slot:SetPoint("TOPLEFT", 20, -137 - (i - 1) * 31); slot:SetSize(323, 29)
        slot.face = CL().Sheet(slot, "field", { layer = "BACKGROUND", corner = 5 })
        slot.icon = RoleIcon(slot, nil, 10, 3, 22)
        slot.text = Text(slot, 17); slot.text:SetPoint("LEFT", 53, 0); slot.text:SetWidth(260)
        slot:EnableMouse(true)
        slot:SetScript("OnMouseUp", function(self)
            if GF.mode ~= "players" or not GF.selected then return end
            local entries = {}
            for _, id in ipairs(GF.selected.activities or {}) do entries[#entries + 1] = { text = ActivityName(id), disabled = true } end
            Menu(self, "All listed dungeons", entries, 390)
        end)
        Tip(slot, function()
            return GF.mode == "players" and "All listed dungeons" or nil
        end, function()
            if GF.mode ~= "players" then return end
            local names = {}; for _, id in ipairs(GF.selected and GF.selected.activities or {}) do names[#names + 1] = ActivityName(id) end
            return table.concat(names, "\n") .. "\nClick to view all."
        end)
        d.slots[i] = slot
    end
    d.partyTitle = Text(d, 23, true); d.partyTitle:SetPoint("TOPLEFT", 19, -221); d.partyTitle:SetSize(326, 30); d.partyTitle:SetText("Your party")
    d.partyInfo = Text(d, 17); d.partyInfo:SetPoint("TOPLEFT", 26, -255); d.partyInfo:SetSize(312, 32)
    Tip(d, "Listed dungeons", function()
        if GF.mode ~= "players" then return end
        local out = {}; for _, id in ipairs(GF.selected and GF.selected.activities or {}) do out[#out + 1] = ActivityName(id) end
        return table.concat(out, "\n")
    end)
    d.whisper = Button(d, "Whisper leader", 20, 311, 323, 43, function() GF.Contact("whisper") end, "confirmation")
    d.invite = Button(d, "Invite", 181, 311, 162, 43, function() GF.Contact("invite") end, "confirmation")
    Tip(d.whisper, "Whisper", function() local _, why = GF.CanContact and GF.CanContact("whisper", GF.selected); return why end)
    Tip(d.invite, "Invite", function() local _, why = GF.CanContact and GF.CanContact("invite", GF.selected); return why end)
    Rule(f, 14, 588, 1032)
    f.count = Text(f, 18); f.count:SetPoint("BOTTOMLEFT", 25, 14); f.count:SetSize(440, 25)
    f.status = Text(f, 16, false, MUTED); f.status:SetPoint("BOTTOMRIGHT", -25, 15); f.status:SetSize(540, 24); f.status:SetJustifyH("RIGHT")
    f.statusArea = CreateFrame("Frame", nil, f); f.statusArea:SetAllPoints(f.status); f.statusArea:EnableMouse(true)
    Tip(f.statusArea, "Group Finder status", function() return W.statusText end)
    f:SetScript("OnHide", function() ClosePopup(); f.search:ClearFocus(); if GF.OnWindowHidden then GF.OnWindowHidden() end end)
end

local function SetSelected(button, selected, teal)
    if button.SetSelected then button:SetSelected(selected) else button.twichSelected = selected end
    if button.twichCraft then
        button.twichCraft:SetSkin(selected and "selection" or "segment")
        if teal then button.twichCraft:SetTint(selected and .40 or 1, selected and .88 or 1, selected and .81 or 1) end
    end
end
local function Details()
    local d, r, players = f.detail, GF.selected, GF.mode == "players"
    SetText(d.title, r and (players and r.leader or r.activityName) or "Choose a listing")
    SetText(d.meta, r and (players and ("Level " .. (r.level or "?") .. " " .. (r.className or r.class or "Player"))
        or ((r.leader or "Unknown leader") .. " · Level " .. (r.level or "?"))) or "")
    local zone = r and r.zone
    local nearby = zone and R.QoLGroupFinderZones and R.QoLGroupFinderZones.Nearby(zone)
    SetText(d.zone, r and ((zone or "Location unknown") .. (nearby and " · Same area" or "")) or "")
    d.zone:SetTextColor(unpack(zone and GREEN or MUTED))
    SetText(d.section, players and "Listed for" or "Party")
    d.partyTitle:SetShown(players and r ~= nil); d.partyInfo:SetShown(players and r ~= nil)
    local roster = {}
    if r and not players then
        for _, role in ipairs(ROLE_ORDER) do
            for _, member in ipairs(r.roster or {}) do if member.role == role then roster[#roster + 1] = member end end
            for _ = 1, r.openings and r.openings[role] or 0 do roster[#roster + 1] = { name = ROLE_NAME[role] .. " needed", role = role } end
        end
        for _, member in ipairs(r.roster or {}) do if not ROLE_ART[member.role] then roster[#roster + 1] = member end end
    end
    for i, slot in ipairs(d.slots) do
        local name, role
        if r then
            if players then
                local activity = r.activities and r.activities[i]
                if activity and i <= 2 then name = ActivityName(activity) end
            else
                local member = roster[i]
                if member then name, role = member.name or "Member", member.role end
                name = name or "Roster unavailable"
            end
        end
        slot:SetShown(name ~= nil)
        if name then
            SetText(slot.text, name); slot.icon:SetRole(role)
            if players then slot.icon:SetTexture(ActivityIcon(r.activities[i])); slot.icon:Show() end
        end
    end
    if players and r and #(r.activities or {}) > 2 then
        SetText(d.slots[2].text, ActivityName(r.activities[2]) .. " +" .. (#r.activities - 2))
    end
    local p = GF.party or {}
    local opening = RoleText(p.openings, true)
    local partyText = p.known and ((p.count or "?") .. " / 5  ·  " .. (p.count == 5 and "Party full" or opening .. " needed")) or (p.reason or "Party roles unavailable")
    SetText(d.partyInfo, partyText)
    d.partyInfo:SetWordWrap(true)
    d.whisper:SetWidth(players and 145 or 323)
    d.whisper.text:SetText(players and "Whisper" or "Whisper leader")
    CL().Control(d.whisper, players and "secondary" or "confirmation")
    d.invite:SetShown(players)
    local whisper = r ~= nil
    local invite = r ~= nil and p.canInvite == true
    if GF.CanContact then whisper = GF.CanContact("whisper", r); invite = GF.CanContact("invite", r) end
    d.whisper:SetEnabled(whisper and true or false); d.invite:SetEnabled(invite and true or false)
end

function W.Render()
    if not f then return end
    painting = true
    local players, filters, list = GF.mode == "players", Filters(), GF.rows or {}
    if lastMode ~= GF.mode then offset, lastMode = 0, GF.mode end
    SetSelected(f.tabs.groups, not players); SetSelected(f.tabs.players, players)
    for _, role in ipairs(ROLE_ORDER) do SetSelected(f.roles[role], filters.roles and filters.roles[role] == true, true) end
    f.needs.text:SetText(players and "Fill missing roles" or "Needs my role")
    f.check:SetShown(filters.needsRole == true)
    f.needs:SetEnabled(not players or GF.party and GF.party.known == true)
    local count = 0; for _ in pairs(filters.activities or {}) do count = count + 1 end
    f.activities.text:SetText(count > 0 and (count .. " selected") or "All dungeons")
    f.search:SetWidth(players and 421 or 586)
    if f.search:GetText() ~= (filters.search or "") then f.search:SetText(filters.search or "") end
    f.searchHint:SetText(players and "Search players" or "Search groups")
    f.searchHint:SetShown(f.search:GetText() == "" and not f.search:HasFocus())
    f.level:SetShown(players)
    f.level.text:SetText("Any level")
    if filters.minLevel or filters.maxLevel then f.level.text:SetText("Level " .. (filters.minLevel or "1") .. "–" .. (filters.maxLevel or "any")) end
    f.refresh:SetEnabled(GF.state ~= "searching")
    f.refresh.text:SetText(GF.state == "searching" and "Searching…" or "Refresh")
    offset = math.max(0, math.min(math.max(0, #list - VISIBLE), offset))
    f.slider:SetMinMaxValues(0, math.max(0, #list - VISIBLE)); f.slider:SetValue(offset); f.slider:SetShown(#list > VISIBLE)
    for i, row in ipairs(rows) do
        local result = list[offset + i]
        row.result = result; row:SetShown(result ~= nil)
        if result then
            local selected = GF.selected and result.id == GF.selected.id and result.identity == GF.selected.identity
            row.selection:SetShown(selected); row.selectionGrain:SetShown(selected); row.selectedRim:SetShown(selected); row.rail:SetShown(selected)
            local icon = players and result.class and R.PATH .. [[media\guildloc\class-]] .. result.class or result.icon
            row.icon:SetTexture(icon or R.PATH .. [[media\textures\place-dungeon]])
            SetText(row.title, players and result.leader or result.activityName)
            SetText(row.meta, players and ("Level " .. (result.level or "?") .. " " .. (result.className or result.class or "Player") .. " · " .. (result.zone or "Location unknown"))
                or ((result.leader or "Unknown leader") .. " · " .. (result.zone or "Location unknown")))
            row.count:SetText(players and "" or ((result.numMembers or "?") .. " / 5"))
            row.roleIcon:ClearAllPoints(); row.roleIcon:SetPoint("TOPLEFT", 424, players and -30 or -46)
            row.roleIcon:SetRole(FirstRole(result, not players))
            row.roles:ClearAllPoints(); row.roles:SetPoint("TOPLEFT", 454, players and -30 or -46)
            SetText(row.roles, (players and "" or "Needs ") .. RoleText(players and result.roles or result.openings, not players))
            row.contacted:SetText(result.contacted and "Contacted" or "")
        end
    end
    f.empty:SetShown(#list == 0)
    local empty
    if GF.state == "searching" then empty = "Searching for dungeon listings…"
    elseif GF.state == "idle" then empty = "Choose your dungeons, then click Refresh."
    elseif GF.state == "failed" then empty = "The search failed. Click Refresh to try again."
    elseif GF.availableCount == 0 then empty = players and "No solo players were found for these dungeons. Click Refresh to try again."
        or "No groups were found for these dungeons. Click Refresh to try again."
    else empty = "Available listings are hidden by your filters. Try fewer filters or a different search." end
    SetText(f.empty, empty)
    SetText(f.count, #list .. " matching " .. (players and "players" or "groups"))
    W.UpdateStatus()
    Details()
    painting = false
end

function W.UpdateStatus()
    if not f then return end
    local status = GF.message
    if GF.state == "searching" then status = "Searching…"
    elseif GF.state == "failed" then status = status or "Search failed · Showing previous results"
    elseif GF.lastSuccess then
        local age = math.max(0, math.floor((GetTime and GetTime() or GF.lastSuccess) - GF.lastSuccess))
        local refreshed = (GF.state == "stale" and "Stale · " or "") .. "Last refreshed " .. age .. "s ago"
        status = status and status ~= "" and (status .. " · " .. refreshed) or refreshed
    end
    W.statusText = status or "Refresh to search"
    SetText(f.status, W.statusText)
end
function W.Show()
    Build()
    local width = UIParent.GetWidth and UIParent:GetWidth() or WIDTH + 40
    local height = UIParent.GetHeight and UIParent:GetHeight() or HEIGHT + 40
    local scale = math.min(1, (width - 28) / WIDTH, (height - 28) / HEIGHT)
    f:SetScale(math.max(.55, scale)); f:Show(); W.Render()
end
function W.Hide() if f then f:Hide() end end
function W.IsShown() return f and f:IsShown() or false end
function W.RowCount() return #rows end
