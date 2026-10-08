-- TwichUI: addon data window (/tui data)
-- A read-only look at what addons keep between sessions: addons on the left,
-- each with the data a scan found for it; the chosen item's contents on the
-- right, opened a level at a time. Nothing can be changed here. TwichUI's own
-- data can be deleted from its Saved data list, which this window links to.
-- Lists are ScrollBoxes, so only the rows on screen exist however big the
-- data is. Styled by EllesmereUI's skin toolkit when it's available.

local R = TwichUI
local SD = R.StoredData
local DW = {}
R.StoredDataWindow = DW

local GOLD, GREY = R.GOLD, R.GREY
local WIDTH, HEIGHT = 900, 580
local LEFT_W = 330
local ADDON_H, TREE_H = 22, 18
local PAGE = 200                 -- entries shown per table before "Show more"
local KEY_COLOR = "|cffd9c7a0"

local f                          -- main frame
local open = {}                  -- [addon] = true: its data is listed under it
local openWorking = {}           -- [addon] = true: its probable working data is listed too
local selected                   -- name of the item shown on the right
local tree                       -- { root = node, first = { [table] = path } }
local refreshQueued = false

---------------------------------------------------------------------------
-- Helpers (same look as the sharing window)
---------------------------------------------------------------------------
local function Skin(kind, obj, ...)
    local S = R.S
    if not (S and S[kind] and obj) then return end
    pcall(S[kind], obj, ...)
end

local function Accent()
    local S = R.S
    if S and S.GetAccentColor then
        local ok, r, g, b = pcall(S.GetAccentColor)
        if ok and r then return r, g, b end
    end
    return 0.79, 0.64, 0.29
end

local function Text(parent, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    if R.S then Skin("Font", fs) end
    return fs
end

local function Btn(parent, label, w, onClick, tooltip)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    if tooltip then R.Interact.Tip(b, label, tooltip) end
    Skin("Button", b)
    Skin("StateButtonLabel", b)
    return b
end

local function Well(box)
    if R.S then
        Skin("Panel", box, { inset = true })
    else
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        box:SetBackdropColor(0, 0, 0, 0.35)
        box:SetBackdropBorderColor(1, 1, 1, 0.08)
    end
end

local function When(t) return t and date("%b %d, %H:%M", t) or "?" end

-- A recessed box with a ScrollBox list; init(row, data) fills a row.
local function List(parent, w, h, rowH, init)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(w, h)
    Well(box)
    box.scroll = CreateFrame("Frame", nil, box, "WowScrollBoxList")
    box.scroll:SetPoint("TOPLEFT", 4, -4)
    box.scroll:SetPoint("BOTTOMRIGHT", -20, 4)
    box.bar = CreateFrame("EventFrame", nil, box, "MinimalScrollBar")
    box.bar:SetPoint("TOPLEFT", box.scroll, "TOPRIGHT", 6, 0)
    box.bar:SetPoint("BOTTOMLEFT", box.scroll, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(rowH)
    view:SetElementInitializer("Button", init)
    ScrollUtil.InitScrollBoxListWithScrollBar(box.scroll, box.bar, view)
    Skin("ScrollBar", box.bar)
    box.empty = Text(box, "GameFontDisableSmall")
    box.empty:SetPoint("TOPLEFT", 16, -16)
    box.empty:SetPoint("TOPRIGHT", -30, -16)
    box.empty:SetJustifyV("TOP")
    box.empty:SetSpacing(2)
    return box
end

local function SetRows(box, rows, emptyText, keepScroll)
    box.scroll:SetDataProvider(CreateDataProvider(rows), keepScroll and true or false)
    box.empty:SetText(#rows == 0 and (emptyText or "") or "")
end

local function RowParts(row, labelTemplate)
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.05)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    local r, g, b = Accent()
    row.sel:SetColorTexture(r, g, b, 0.14)
    row.right = Text(row, "GameFontDisableSmall")
    row.right:SetPoint("RIGHT", -6, 0)
    row.right:SetJustifyH("RIGHT")
    row.label = Text(row, labelTemplate)
    row.label:SetPoint("LEFT", 6, 0)
    row.label:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
    row.label:SetWordWrap(false)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

---------------------------------------------------------------------------
-- Sizes in words
---------------------------------------------------------------------------
-- "1,234 entries · about 56 KB", or why there's no number.
local function SizeText(name)
    if not SD.Readable(name) then return "not loaded" end
    local s = SD.sizes[name]
    if not s then return "counting..." end
    if s.failed then return "changed while counting" end
    if SD.Found(name) and SD.Found(name).value then return "about " .. SD.FormatSize(s.bytes) end
    return ("%s · about %s"):format(SD.Num(s.entries), SD.FormatSize(s.bytes))
end

-- The addon's total, while every item is counted; nil until then.
local function AddonBytes(a)
    local total = 0
    for _, name in ipairs(a.vars) do
        local s = SD.sizes[name]
        if not s or s.failed then return nil end
        total = total + s.bytes
    end
    return total
end

---------------------------------------------------------------------------
-- Left: addons and their data
---------------------------------------------------------------------------
local addons                     -- SD.Addons() as last listed

local function ShowItem(name)
    selected = name
    tree = nil
    DW:Refresh()
end

local function AddonTooltip(row)
    local a = row.data.addon
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(a.title, 1, 1, 1)
    if a.title ~= a.name then GameTooltip:AddLine(a.name, 0.6, 0.6, 0.6) end
    GameTooltip:AddLine(a.statusText, 1, 0.82, 0)
    if a.own then
        GameTooltip:AddLine("TwichUI's own data, as its .toc declares it. All of it is account-wide. Delete what you no longer need from Saved data, below.", nil, nil, nil, true)
    elseif #a.vars + #a.working > 0 then
        local first = SD.Found(a.vars[1] or a.working[1])
        GameTooltip:AddLine(("%d item(s) appeared as it loaded, in the scan on %s."):format(#a.vars + #a.working, When(first and first.seen)), nil, nil, nil, true)
        if #a.working > 0 then
            GameTooltip:AddLine(("%d of them look like the addon's own working data, listed apart and left out of its total."):format(#a.working), 0.7, 0.7, 0.7, true)
        end
    elseif SD.LastScan() then
        GameTooltip:AddLine(a.status == "loaded" and "The last scan found no data for it." or "Not loaded in the last scan, so its data couldn't be found.", nil, nil, nil, true)
    end
    if a.before then
        GameTooltip:AddLine("It loaded before TwichUI, so a scan can't tell which data is its own.", nil, nil, nil, true)
    end
    if a.status ~= "loaded" and #a.vars + #a.working > 0 then
        GameTooltip:AddLine("The game loads an addon's data only while the addon is loaded, so it can't be shown now.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

local function ItemTooltip(row)
    local name = row.data.name
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(name, 1, 1, 1)
    local e = SD.Found(name)
    if SD.IsOwn(name) then
        GameTooltip:AddLine("Declared by TwichUI. Account-wide.", nil, nil, nil, true)
    elseif e then
        local working = SD.WorkingReason(name, e.owner)
        if working then
            GameTooltip:AddLine(("Appeared when %s loaded (scan on %s), but it probably isn't saved: it looks like the addon's own working data, made by its code each session. %s"):format(
                R.Setups.AddonTitle(e.owner), When(e.seen), working), nil, nil, nil, true)
        else
            GameTooltip:AddLine(("Appeared when %s loaded (scan on %s). That makes it very likely, not certain, to be that addon's saved data."):format(
                R.Setups.AddonTitle(e.owner), When(e.seen)), nil, nil, nil, true)
        end
    end
    local s = SD.sizes[name]
    if s and not s.failed then
        GameTooltip:AddLine(" ")
        if not (e and e.value) then GameTooltip:AddLine(("%s entries"):format(SD.Num(s.entries)), 1, 1, 1) end
        GameTooltip:AddLine(("About %s if saved as it is now (an estimate)"):format(SD.FormatSize(s.bytes)), 1, 1, 1)
        GameTooltip:AddLine("Some addons trim their data as they save it, such as leaving out settings still at their defaults, so the file can be smaller.", 0.7, 0.7, 0.7, true)
        if s.shared then GameTooltip:AddLine("Some tables appear more than once; each is counted once.", 0.7, 0.7, 0.7, true) end
        if s.unsaved then GameTooltip:AddLine("Holds functions or frames, which aren't saved to disk.", 0.7, 0.7, 0.7, true) end
        if s.partial then GameTooltip:AddLine("Some of it is hidden by the game and wasn't counted.", 0.7, 0.7, 0.7, true) end
    elseif s and s.failed then
        GameTooltip:AddLine("It changed while being counted. Open the window again to count afresh.", nil, nil, nil, true)
    end
    GameTooltip:AddLine("Whether data is account-wide or per character isn't something the game tells addons. The exact file size can only be seen outside the game.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function GroupTooltip(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText("Probably working data", 1, 1, 1)
    GameTooltip:AddLine("These appeared as the addon loaded, but their names suggest the addon's own working data, made by its code each session, rather than anything saved: names that start with _, are in capitals, or are the addon's own name. They're listed in case they are saved, and left out of the addon's total.", nil, nil, nil, true)
    GameTooltip:Show()
end

local function LeftClick(row)
    local d = row.data
    if d.addon then
        if #d.addon.vars + #d.addon.working == 0 then return end
        open[d.addon.name] = not open[d.addon.name] or nil
        DW:Refresh()
    elseif d.group then
        openWorking[d.group.name] = not openWorking[d.group.name] or nil
        DW:Refresh()
    else
        ShowItem(d.name)
    end
end

local function InitLeft(row, d)
    if not row.label then
        RowParts(row, "GameFontHighlight")
        row:SetScript("OnClick", LeftClick)
    end
    row.data = d
    row.sel:SetShown(d.name ~= nil and d.name == selected)
    if d.addon then
        local a = d.addon
        row:SetScript("OnEnter", AddonTooltip)
        row.label:SetPoint("LEFT", 6, 0)
        row.label:SetFontObject(a.status == "loaded" and "GameFontHighlight" or "GameFontDisable")
        local mark = (#a.vars + #a.working == 0) and "   " or (open[a.name] and "-  " or "+  ")
        row.label:SetText(GREY .. mark .. "|r" .. a.title)
        local right = a.statusText
        local bytes = a.status == "loaded" and #a.vars > 0 and AddonBytes(a)
        if a.status == "loaded" then right = bytes and ("about " .. SD.FormatSize(bytes)) or (#a.vars > 0 and "counting..." or "") end
        row.right:SetText(right)
    elseif d.group then
        row:SetScript("OnEnter", GroupTooltip)
        row.label:SetPoint("LEFT", 26, 0)
        row.label:SetFontObject("GameFontDisableSmall")
        row.label:SetText((openWorking[d.group.name] and "-  " or "+  ") .. "Probably working data")
        row.right:SetText(#d.group.working)
    else
        row:SetScript("OnEnter", ItemTooltip)
        row.label:SetPoint("LEFT", d.working and 44 or 26, 0)
        row.label:SetFontObject((SD.Readable(d.name) and not d.working) and "GameFontHighlightSmall" or "GameFontDisableSmall")
        row.label:SetText(SD.Plain(d.name))
        row.right:SetText(SizeText(d.name))
    end
end

local function LeftRows()
    local rows = {}
    for _, a in ipairs(addons) do
        rows[#rows + 1] = { addon = a }
        if open[a.name] then
            for _, name in ipairs(a.vars) do rows[#rows + 1] = { name = name } end
            if #a.working > 0 then
                rows[#rows + 1] = { group = a }
                if openWorking[a.name] then
                    for _, name in ipairs(a.working) do rows[#rows + 1] = { name = name, working = true } end
                end
            end
        end
    end
    return rows
end

---------------------------------------------------------------------------
-- Right: the chosen item as a tree
---------------------------------------------------------------------------
-- Name.key["other key"][3]
local function PathOf(node)
    local k = node.key
    if not node.parent then return SD.Plain(k) end
    local part
    if type(k) == "string" and k:match("^[%a_][%w_]*$") then part = "." .. k
    elseif type(k) == "string" then part = '["' .. SD.ShowKey(k) .. '"]'
    else part = SD.ShowKey(k) end
    return PathOf(node.parent) .. part
end

-- Whether v is one of node's own containing tables (a loop).
local function IsAncestor(node, v)
    local p = node
    while p do
        if p.value == v then return true end
        p = p.parent
    end
    return false
end

local function Kid(node, i)
    node.kids = node.kids or {}
    local kid = node.kids[i]
    if not kid then
        local k = node.keys[i]
        local v = rawget(node.value, k)
        kid = { key = k, value = v, depth = node.depth + 1, parent = node }
        if type(v) == "table" then
            kid.loop = IsAncestor(node, v)
            if canaccesstable and not canaccesstable(v) then kid.hiddenTable = true
            else kid.count, kid.more = SD.CountTo(v, 1000) end
        end
        node.kids[i] = kid
    end
    return kid
end

local function OpenNode(node)
    if not node.keys then
        node.keys, node.hidden, node.unsorted = SD.Keys(node.value)
        node.limit = PAGE
    end
    if not tree.first[node.value] then tree.first[node.value] = PathOf(node) end
    node.open = true
end

local function Flatten(node, rows)
    local n = math.min(#node.keys, node.limit)
    for i = 1, n do
        local kid = Kid(node, i)
        rows[#rows + 1] = { node = kid }
        if kid.open then Flatten(kid, rows) end
    end
    if #node.keys > node.limit then rows[#rows + 1] = { more = node } end
    if node.hidden and node.hidden > 0 then rows[#rows + 1] = { hiddenOf = node } end
end

local function NodeText(node)
    local pad = ("    "):rep(node.depth - 1)
    local key = KEY_COLOR .. SD.ShowKey(node.key) .. "|r"
    local v = node.value
    if type(v) ~= "table" then return pad .. "   " .. key .. "  " .. SD.ShowValue(v, 160) end
    local mark = (node.loop or node.hiddenTable) and "   " or (node.open and "-  " or "+  ")
    local note
    if node.hiddenTable then note = "hidden by the game"
    elseif node.loop then note = "contains itself"
    else
        note = node.count == 0 and "empty" or (SD.Num(node.count) .. (node.more and "+" or "") .. " entries")
        local first = tree.first[v]
        if first and first ~= PathOf(node) then note = note .. ", same table as " .. first end
    end
    return pad .. GREY .. mark .. "|r" .. key .. "  " .. GREY .. "{ " .. note .. " }|r"
end

local function TreeTooltip(row)
    local d = row.data
    local node = d.node
    if not node then return end
    GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
    GameTooltip:SetText(PathOf(node), 1, 1, 1, 1, true)
    if type(node.value) ~= "table" then
        GameTooltip:AddLine(SD.ShowValue(node.value, 1000), 1, 1, 1, true)
        GameTooltip:AddLine(type(node.value), 0.6, 0.6, 0.6)
    elseif node.unsorted then
        GameTooltip:AddLine("Too many entries to sort; shown in stored order.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

local function TreeClick(row)
    local d = row.data
    if d.more then
        d.more.limit = d.more.limit + PAGE
    elseif d.node and type(d.node.value) == "table" and not d.node.loop and not d.node.hiddenTable then
        if d.node.open then d.node.open = false else OpenNode(d.node) end
    else
        return
    end
    DW:RefreshTree(true)
end

local function InitTree(row, d)
    if not row.label then
        RowParts(row, "GameFontHighlightSmall")
        row.right:SetText("")
        row:SetScript("OnClick", TreeClick)
        row:SetScript("OnEnter", TreeTooltip)
    end
    row.data = d
    row.sel:Hide()
    if d.more then
        local left = #d.more.keys - d.more.limit
        row.label:SetText(("%s%s+  Show %d more (%s left)|r"):format(("    "):rep(d.more.depth), GOLD, math.min(PAGE, left), SD.Num(left)))
    elseif d.hiddenOf then
        row.label:SetText(("%s%s%d entries hidden by the game|r"):format(("    "):rep(d.hiddenOf.depth), GREY, d.hiddenOf.hidden))
    else
        row.label:SetText(NodeText(d.node))
    end
end

function DW:RefreshTree(keepScroll)
    if not f then return end
    local box, name = f.tree, selected
    if not name then
        f.head:SetText("")
        f.sub:SetText("")
        SetRows(box, {}, "Choose an item on the left to look through it. Addons with data have a + beside them.\n\nNothing here can be changed.")
        return
    end
    local owner = SD.Owner(name)
    f.head:SetText(SD.Plain(name))
    if not SD.Readable(name) then
        f.sub:SetText(owner and R.Setups.AddonTitle(owner) or "")
        tree = nil
        SetRows(box, {}, ("%s isn't loaded in this session (%s), so its data isn't in the game's memory and can't be shown. The game loads an addon's data only while the addon is loaded."):format(
            owner and R.Setups.AddonTitle(owner) or "Its addon", (select(2, SD.Status(owner or "")) or ""):lower()))
        return
    end
    f.sub:SetText(("%s  ·  %s"):format(R.Setups.AddonTitle(owner), SizeText(name)))
    local value = SD.Value(name)
    if type(value) ~= "table" then
        tree = nil
        SetRows(box, {}, "Value: " .. SD.ShowValue(value, 1000))
        return
    end
    if canaccesstable and not canaccesstable(value) then
        tree = nil
        SetRows(box, {}, "The game keeps this table hidden from addons.")
        return
    end
    if not (tree and tree.root.value == value) then
        tree = { first = {}, root = { key = name, value = value, depth = 0 } }
        OpenNode(tree.root)
    end
    local rows = {}
    Flatten(tree.root, rows)
    SetRows(box, rows, "Empty.", keepScroll)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function AskScan()
    if InCombatLockdown() then R.Print("that has to wait until you're out of combat.") return end
    R.Interact.Confirm("TWICHUI_DATA_SCAN",
        "Find which data each addon keeps? Your UI reloads once and this window opens again. Nothing is changed, copied or sent.",
        function() SD.Scan() end, { combat = true })
end

local function Build()
    f = CreateFrame("Frame", "TwichUIAddonData", UIParent, "BackdropTemplate")
    f:Hide()                     -- so the first Show runs OnShow (frames start shown)
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:HookScript("OnShow", R.FitToScreen)
    tinsert(UISpecialFrames, "TwichUIAddonData")
    if R.S then Skin("Shell", f) else
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.07, 0.065, 0.06, 0.97)
        f:SetBackdropBorderColor(0.25, 0.23, 0.2, 1)
    end

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(26, 26)
    logo:SetPoint("TOPLEFT", 12, -8)
    logo:SetTexture(R.ICON)
    local title = Text(f, "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("Addon data")
    title:SetTextColor(1, 1, 1)
    local sub = Text(f, "GameFontDisableSmall")
    sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
    sub:SetText("what your addons keep between sessions · read-only")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    Skin("CloseButton", close)

    local listH = HEIGHT - 44 - 96
    f.left = List(f, LEFT_W, listH, ADDON_H, InitLeft)
    f.left:SetPoint("TOPLEFT", 14, -44)

    f.head = Text(f, "GameFontNormal")
    f.head:SetPoint("TOPLEFT", f.left, "TOPRIGHT", 14, -2)
    f.head:SetPoint("RIGHT", -16, 0)
    f.head:SetWordWrap(false)
    f.head:SetTextColor(1, 1, 1)
    f.sub = Text(f, "GameFontDisableSmall")
    f.sub:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT", 0, -4)
    f.sub:SetPoint("RIGHT", -16, 0)
    f.sub:SetWordWrap(false)
    f.tree = List(f, WIDTH - LEFT_W - 42, listH - 38, TREE_H, InitTree)
    f.tree:SetPoint("BOTTOMLEFT", f.left, "BOTTOMRIGHT", 14, 0)

    f.scanned = Text(f, "GameFontHighlightSmall")
    f.scanned:SetPoint("TOPLEFT", f.left, "BOTTOMLEFT", 2, -10)
    f.scanned:SetWidth(WIDTH - 360)
    f.note = Text(f, "GameFontDisableSmall")
    f.note:SetPoint("TOPLEFT", f.scanned, "BOTTOMLEFT", 0, -6)
    f.note:SetWidth(WIDTH - 360)
    f.note:SetSpacing(2)
    f.note:SetText("Only addons loaded now can be shown: the game doesn't load data for addons that are off, waiting to load or removed, and addons can't read the files on disk. Sizes estimate the data as it is now; the saved file can be smaller.")

    local scan = Btn(f, "Find addon data", 150, AskScan,
        "Reloads your UI once and notes which data appears as each addon loads. Nothing is changed, copied or sent.")
    scan:SetPoint("BOTTOMRIGHT", -16, 14)
    local mine = Btn(f, "TwichUI's saved data", 170, function()
        if R.Window then R.Window:ShowStorage() end
    end, "TwichUI's own saved setups, backups and Undo copies, where you can delete what you no longer need.")
    mine:SetPoint("RIGHT", scan, "LEFT", -8, 0)

    f:SetScript("OnShow", function()
        SD.ClearSizes()
        addons = SD.Addons()
        for _, a in ipairs(addons) do
            for _, name in ipairs(a.vars) do SD.Measure(name) end
            for _, name in ipairs(a.working) do SD.Measure(name) end
        end
        DW:Refresh()
    end)
    f:SetScript("OnHide", function()
        SD.ClearSizes()
        tree, addons = nil, nil
    end)
end

-- Counts arrive a few at a time; redraw at most a few times a second.
SD.OnChange(function()
    if refreshQueued or not (f and f:IsShown()) then return end
    refreshQueued = true
    C_Timer.After(0.25, function()
        refreshQueued = false
        if not (f and f:IsShown() and addons) then return end
        SetRows(f.left, LeftRows(), nil, true)
        if selected and SD.Readable(selected) then
            f.sub:SetText(("%s  ·  %s"):format(R.Setups.AddonTitle(SD.Owner(selected)), SizeText(selected)))
        end
    end)
end)

function DW:Refresh()
    if not (f and f:IsShown()) then return end
    addons = addons or SD.Addons()
    local scanned = SD.LastScan()
    f.scanned:SetText(scanned and ("Last scan: %s. Run it again after adding or changing addons."):format(When(scanned))
        or (GOLD .. "Not scanned yet.|r Press Find addon data to see which data each addon keeps."))
    SetRows(f.left, LeftRows(), nil, true)
    DW:RefreshTree()
end

function DW:Show()
    if not f then Build() end
    if f:IsShown() then DW:Refresh() else f:Show() end
end

function DW:Toggle()
    if f and f:IsShown() then f:Hide() else DW:Show() end
end
