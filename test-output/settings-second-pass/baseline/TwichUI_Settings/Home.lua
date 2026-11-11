-- TwichUI Settings: the top of the Home page
-- Three ways in, side by side: Explore features (every feature with its icon and whether it is on, each opening
-- its page), Adjust appearance (the pages that change how things look) and Review changed settings (every setting
-- that now differs from TwichUI's default, each opening its control). Choosing one shows it beneath; it is not a
-- wizard, nothing is turned on from here, and which one is shown is kept for the session only. The rest of Home
-- (Help, General) follows as before.
--
--   Home.Build(parent, width, env) -> hero     env: { Navigate(pageKey, rowId), Relayout() }
--   hero:Layout(y) -> height                   places it y below the top of parent and draws what is shown now
--   hero:Resize(width)                         the window was resized: every piece takes the new width (nothing is rebuilt)

local R = TwichUI
local K = R.SettingsKit
local Wg = R.SettingsWidgets
local I = R.Interact
local pal = Wg.pal
local Home = {}
R.SettingsHome = Home
local M = R.SettingsMaterial

local TILE_H, TILE_GAP = 88, 12
local GRID_H, GRID_GAP = 76, 12
local GRID_MIN_COLS, GRID_MAX_COLS, GRID_CELL = 2, 3, 240
local FEATURED = { "notifications", "reminders", "healerWatch", "qol", "magicInventory", "auction",
    "chronicle", "navigation", "cozyBag", "food", "hazard", "workshop" }
local featured = {}
for i, key in ipairs(FEATURED) do featured[key] = i end

-- How many feature cells fit side by side in a row this wide.
local function Columns(width)
    return math.max(GRID_MIN_COLS, math.min(GRID_MAX_COLS, math.floor((width + GRID_GAP) / (GRID_CELL + GRID_GAP))))
end
local LIST_H = 42
local CHANGED_SHOWN = 50

local VIEWS = {
    { key = "explore", icon = "explore", title = "Explore features",
        line = "What each feature does, and whether it is on." },
    { key = "appearance", icon = "appearance", title = "Adjust appearance",
        line = "The pages that change how things look." },
    { key = "changed", icon = "reviewChanges", title = "Review changed settings",
        line = function(n) return n == 0 and "Everything is at its default." or (n == 1 and "1 setting differs from its default." or (n .. " settings differ from their defaults.")) end },
}

local function Icon(parent, id, size)
    -- above the hover wash (ARTWORK sublevel 1), which must tint only the background
    local t = parent:CreateTexture(nil, "ARTWORK", nil, 2)
    t:SetSize(size, size)
    if R.Icons then R.Icons.Apply(t, id, size) else t:Hide() end
    return t
end

-- A flat, clickable panel with a wash under the pointer (Look's Hover) and, when chosen, a gold bar along its
-- foot and a golden-brown fill, like a tab: the title's color and the bar say it is chosen, not color alone.
local function Panel(parent, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h)
    M.PanelFace(b, "card")
    M.MaterialHover(b)
    b.fill = R.SettingsCraft.Sheet(b, "selection", { layer = "BACKGROUND", sub = 2, corner = 10 })
    b.fill:Hide()
    b.bar = Wg.Solid(b, "ARTWORK", pal.bronzeText, 1)
    b.bar:SetDrawLayer("ARTWORK", 2)
    b.bar:SetHeight(2)
    b.bar:SetPoint("BOTTOMLEFT", 1, 1)
    b.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    b.bar:Hide()
    -- the sound goes with the press, not the release, so it is not heard after the page has changed
    b:SetScript("OnMouseDown", function() R:PlayMenuSound() end)
    b:SetScript("OnClick", onClick)
    return b
end

function Home.Build(parent, width, env)
    local hero = { views = {}, shown = "home", grid = {}, looks = {}, changedRows = {}, env = env, query = "" }
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetWidth(width)
    hero.frame = frame

    -- the three ways in
    local tileW = math.floor((width - TILE_GAP * 2) / 3)
    for i, view in ipairs(VIEWS) do
        local tile = Panel(frame, tileW, TILE_H, function()
            hero.shown = view.key
            env.Relayout()
        end)
        tile:SetPoint("TOPLEFT", (i - 1) * (tileW + TILE_GAP), 0)
        tile.icon = Icon(tile, view.icon, 48)
        tile.icon:SetPoint("LEFT", 8, 0)
        tile.title = M.ReminderFont(Wg.Text(tile, "body"), 16, true, "serif")
        tile.title:SetPoint("TOPLEFT", 62, -12)
        tile.title:SetWidth(tileW - 72)
        tile.title:SetText(view.title)
        tile.line = Wg.Text(tile, "small")
        tile.line:SetPoint("TOPLEFT", tile.title, "BOTTOMLEFT", 0, -4)
        tile.line:SetWidth(tileW - 72)
        tile.line:SetWordWrap(true)
        tile.view = view
        tile.index = i
        hero.views[view.key] = tile
    end

    hero.heading = Wg.Text(frame, "heading")
    hero.help = Wg.Text(frame, "small")
    hero.help:SetWidth(width - 4)
    hero.help:SetWordWrap(true)
    hero.find = Wg.EditBox(frame, 220, 28)
    M.SearchDecoration(hero.find, "Find a feature...")
    hero.find:SetScript("OnTextChanged", function(self)
        hero.query = self:GetText():lower():gsub("^%s+", ""):gsub("%s+$", "")
        env.Relayout()
    end)
    hero.find:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    hero.all = Panel(frame, width, 64, function()
        hero.shown = hero.shown == "home" and "explore" or "home"
        env.Relayout()
    end)
    hero.all.icon = Icon(hero.all, "journeyChronicle", 42)
    hero.all.icon:SetPoint("LEFT", 12, 0)
    hero.all.title = M.ReminderFont(Wg.Text(hero.all, "body"), 17, true, "serif")
    hero.all.title:SetPoint("TOPLEFT", 68, -10)
    hero.all.line = Wg.Text(hero.all, "small")
    hero.all.line:SetPoint("TOPLEFT", 68, -34)
    hero.all.arrow = Wg.Text(hero.all, "heading")
    hero.all.arrow:SetPoint("RIGHT", -16, 0); hero.all.arrow:SetText("›")

    -- Explore: every feature in the list, with its status
    local cols = Columns(width)
    local cellW = math.floor((width - GRID_GAP * (cols - 1)) / cols)
    for _, page in ipairs(K.SidebarOrder()) do
        if page.key ~= "overview" then
            local cell = Panel(frame, cellW, GRID_H, function() env.Navigate(page.key) end)
            cell.page = page
            cell.icon = Icon(cell, page.def.icon, 48)
            cell.icon:SetPoint("LEFT", 10, 0)
            local textX = page.def.icon and 68 or 12
            cell.textX = textX
            cell.name = M.ReminderFont(Wg.Text(cell, "body"), 16, true, "serif")
            cell.name:SetPoint("TOPLEFT", textX, -12)
            cell.name:SetWidth(cellW - textX - 24)
            cell.name:SetWordWrap(true)
            cell.name:SetText(page.nav)
            cell.status = Wg.Text(cell, "small")
            cell.status:SetPoint("TOPLEFT", cell.name, "BOTTOMLEFT", 0, -3)
            cell.status:SetWidth(cellW - textX - 8)
            cell.status:SetWordWrap(false)
            cell.arrow = Wg.Text(cell, "heading")
            cell.arrow:SetPoint("RIGHT", -10, 0); cell.arrow:SetText("›")
            local tip = page.def.overview and page.def.overview.tip or page.def.description
            I.Tip(cell, page.name, tip)
            hero.grid[#hero.grid + 1] = cell
        end
    end
    table.sort(hero.grid, function(a, b)
        return (featured[a.page.key] or 1000 + a.page.def.order) < (featured[b.page.key] or 1000 + b.page.def.order)
    end)

    -- Appearance: the pages that change how something looks (appearance tabs, skins, artwork)
    local function Look(page)
        local root = K.Root(page.key)
        local row = Panel(frame, width, LIST_H, function() env.Navigate(page.key) end)
        row.icon = Icon(row, root and root.def.icon, 22)
        row.icon:SetPoint("LEFT", 10, 0)
        row.label = Wg.Text(row, "body")
        row.label:SetPoint("TOPLEFT", 42, -7)
        row.label:SetWidth(width - 120)
        row.label:SetWordWrap(false)
        row.label:SetText(page.parent and (root.name .. "  \226\128\186  " .. K.TabLabel(page)) or page.name)
        row.desc = Wg.Text(row, "small")
        row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
        row.desc:SetWidth(width - 120)
        row.desc:SetWordWrap(false)
        row.desc:SetText(page.def.description or "")
        row.open = Wg.Text(row, "meta")
        row.open:SetPoint("RIGHT", -12, 0)
        row.open:SetText("Open")
        hero.looks[#hero.looks + 1] = row
    end
    for _, page in ipairs(K.NavOrder()) do
        if page.nav == "Appearance" or page.key == "skins" or page.key == "targetArt" then Look(page) end
    end

    hero.empty = Wg.Text(frame, "small")
    hero.empty:SetWidth(width - 4)
    hero.more = Wg.Text(frame, "meta")

    setmetatable(hero, { __index = Home })
    return hero
end

-- A row of the changed-settings list (made when first needed, reused after).
local function ChangedRow(hero, i, width, env)
    local row = hero.changedRows[i]
    if row then return row end
    row = Panel(hero.frame, width, LIST_H, function(self)
        if self.item then env.Navigate(self.item.page.key, self.item.row.id) end
    end)
    row.label = Wg.Text(row, "body")
    row.label:SetPoint("TOPLEFT", 12, -7)
    row.label:SetWidth(width - 260)
    row.label:SetWordWrap(false)
    row.context = Wg.Text(row, "meta")
    row.context:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
    row.context:SetWidth(width - 260)
    row.context:SetWordWrap(false)
    row.now = Wg.Text(row, "small")
    row.now:SetPoint("TOPRIGHT", -12, -7)
    row.now:SetWidth(230)
    row.now:SetJustifyH("RIGHT")
    row.now:SetWordWrap(false)
    row.default = Wg.Text(row, "meta")
    row.default:SetPoint("TOPRIGHT", row.now, "BOTTOMRIGHT", 0, -3)
    row.default:SetWidth(230)
    row.default:SetJustifyH("RIGHT")
    row.default:SetWordWrap(false)
    hero.changedRows[i] = row
    return row
end

-- The window was made wider or narrower: the pieces made already take the new width. Everything here is anchored to
-- the top left of the frame, so only widths (and the tiles' places) change; Layout places the rest, and sizes the
-- cells of the grid to the columns it now has.
function Home:Resize(width)
    local frame = self.frame
    frame:SetWidth(width)
    local tileW = math.floor((width - TILE_GAP * 2) / 3)
    for _, tile in pairs(self.views) do
        tile:SetWidth(tileW)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", (tile.index - 1) * (tileW + TILE_GAP), 0)
        tile.title:SetWidth(tileW - 72)
        tile.line:SetWidth(tileW - 72)
    end
    self.help:SetWidth(width - 4)
    self.empty:SetWidth(width - 4)
    self.all:SetWidth(width)
    self.find:SetWidth(math.min(220, math.floor(width * .42)))
    for _, row in ipairs(self.looks) do
        row:SetWidth(width)
        row.label:SetWidth(width - 120)
        row.desc:SetWidth(width - 120)
    end
    for _, row in ipairs(self.changedRows) do
        row:SetWidth(width)
        row.label:SetWidth(width - 260)
        row.context:SetWidth(width - 260)
    end
end

local function Plain(text) return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

function Home:Layout(y)
    self.y = y
    local frame, width = self.frame, self.frame:GetWidth()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", frame:GetParent(), "TOPLEFT", 0, -y)
    local changed = K.Changed()

    local tileHeight = TILE_H
    for key, tile in pairs(self.views) do
        local chosen = key == self.shown
        tile.fill:SetShown(chosen)
        tile.bar:SetShown(chosen)
        Wg.Color(tile.title, pal.text)
        local line = tile.view.line
        tile.line:SetText(type(line) == "function" and line(#changed) or line)
        tileHeight = math.max(tileHeight, 28 + tile.title:GetStringHeight() + tile.line:GetStringHeight())
    end
    for _, tile in pairs(self.views) do tile:SetHeight(tileHeight) end
    local h = tileHeight + 24

    local heading, help
    if self.shown == "explore" or self.shown == "home" then
        heading, help = self.shown == "home" and "Your features" or "All features", ""
    elseif self.shown == "appearance" then
        heading, help = "Appearance", "Choose a feature to adjust its look."
    else
        local P = R.Profiles
        local profile = P and P.Current and P.Current()
        heading = "Changed settings"
        help = "Compared with defaults" .. (profile and (" in \"" .. profile .. "\"") or "") .. ". Select a setting to edit it."
    end
    self.heading:SetText(heading)
    self.heading:ClearAllPoints()
    self.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -h)
    self.find:ClearAllPoints()
    self.find:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -h + 2)
    self.find:SetShown(self.shown == "home" or self.shown == "explore")
    h = h + math.max(28, self.heading:GetStringHeight() or 14) + 12
    self.help:SetText(help)
    self.help:ClearAllPoints()
    self.help:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -h)
    self.help:SetShown(help ~= "")
    if help ~= "" then h = h + (self.help:GetStringHeight() or 12) + 10 end

    -- explore grid
    local cols = Columns(width)
    local cellW = math.floor((width - GRID_GAP * (cols - 1)) / cols)
    local count = 0
    for _, cell in ipairs(self.grid) do
        local browsing = self.shown == "explore" or self.shown == "home"
        local match = self.query == "" or (cell.page.name .. " " .. (cell.page.def.keywords or "")):lower():find(self.query, 1, true)
        local show = browsing and match and (self.shown == "explore" or self.query ~= "" or featured[cell.page.key])
        cell:SetShown(show)
        if show then
            local col, row = count % cols, math.floor(count / cols)
            count = count + 1
            cell:SetWidth(cellW)
            cell.name:SetWidth(cellW - cell.textX - 24)
            cell.status:SetWidth(cellW - cell.textX - 24)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", frame, "TOPLEFT", col * (cellW + GRID_GAP), -(h + row * (GRID_H + GRID_GAP)))
            local status = cell.page.def.overview and cell.page.def.overview.status
            local ok, text = true, nil
            if status then ok, text = pcall(status) end
            if not ok or type(text) ~= "string" or text == "" then text = "Open its page" end
            cell.status:SetText(text)
        end
    end
    if self.shown == "explore" or self.shown == "home" then
        local rows = math.ceil(count / cols)
        if rows > 0 then h = h + rows * (GRID_H + GRID_GAP) - GRID_GAP end
    end
    local browsing = self.shown == "home" or self.shown == "explore"
    self.all:SetShown(browsing)
    if browsing then
        self.all:ClearAllPoints(); self.all:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(h + 14))
        self.all.title:SetText(self.shown == "home" and "All features" or "Back to your features")
        self.all.line:SetText(self.shown == "home" and "Browse every TwichUI feature" or "Return to Home's featured collection")
        h = h + 78
    end

    -- appearance list
    for i, row in ipairs(self.looks) do
        local show = self.shown == "appearance"
        row:SetShown(show)
        if show then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -h)
            h = h + LIST_H + 6
        end
    end
    if self.shown == "appearance" then h = h - 6 end

    -- changed settings
    local showChanged = self.shown == "changed"
    local n = showChanged and math.min(#changed, CHANGED_SHOWN) or 0
    for i = 1, n do
        local item = changed[i]
        local row = ChangedRow(self, i, width, self.env)
        row.item = item
        local s = item.setting
        row.label:SetText(Plain(s.name))
        local section = item.row.section and item.row.section:GetName()
        local root = K.Root(item.page.key)
        local where = item.page.parent and (root.name .. "  \194\183  " .. K.TabLabel(item.page)) or item.page.name
        if section and section ~= "" and section:lower() ~= item.page.name:lower() then where = where .. "  \194\183  " .. section end
        row.context:SetText(where)
        row.now:SetText("Now: " .. Plain(K.ValueText(s)))
        row.default:SetText("Default: " .. Plain(K.ValueText(s, s.default)))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -h)
        row:Show()
        h = h + LIST_H + 6
    end
    for i = n + 1, #self.changedRows do self.changedRows[i]:Hide(); self.changedRows[i].item = nil end
    self.empty:SetShown((showChanged and #changed == 0) or (browsing and count == 0))
    if browsing and count == 0 then
        self.empty:SetText("No features found. Try another name.")
        self.empty:ClearAllPoints(); self.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -h)
        h = h + 24
    end
    if showChanged and #changed == 0 then
        self.empty:SetText("Every setting is at its default.")
        self.empty:ClearAllPoints()
        self.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -h)
        h = h + (self.empty:GetStringHeight() or 12) + 6
    elseif n > 0 then
        h = h - 6
    end
    self.more:SetShown(showChanged and #changed > n)
    if showChanged and #changed > n then
        self.more:SetText(("And %d more. Search finds any of them by name."):format(#changed - n))
        self.more:ClearAllPoints()
        self.more:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -(h + 8))
        h = h + 8 + (self.more:GetStringHeight() or 12)
    end

    frame:SetHeight(h)
    return h
end
