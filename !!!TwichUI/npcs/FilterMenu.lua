-- TwichUI: the NPC filter on the world map's tool bar
-- A small funnel button on the map tools bar (pins/MapTools.lua draws it and calls Toggle) that opens a compact menu of the
-- kinds of NPC the map shows (npcs/Kinds.lua's list, in the settings' order), each a checkbox. It is another way to set the same
-- choices the Vendors and trainers settings hold (npcs/Prefs.lua's show.<kind>): there is no second copy, and the map
-- (npcs/Map.lua) draws from those choices as it always did, so a change made here is drawn at once and seen in the settings.
--   The button: on by default (Map Toolbar settings: "Show NPC filter button"; ui.partyPins.npcFilter) and there only while
--     Vendors and trainers is on, as Navigate is there only while Navigation is. Hiding it changes no filter and stops none.
--   The menu: one row per kind (checkbox, its icon, its name), always all of them, whether or not the area has any; Show
--     all and Hide all, which change only these kinds (and write them in one go, so the map is drawn once). It stays open
--     while you check several. It is made the first time it is opened and only repainted afterwards: opening it reads
--     nothing from the list of NPCs. A list too tall for the map scrolls.
--   Several roles: an NPC shows while any one of its kinds is checked, wearing the icon of its first checked kind (the rule
--     npcs/Map.lua already had: NpcKinds.Primary with the checked kinds). An NPC picked out by the NPC search is drawn for as
--     long as it is picked out whatever is checked, and only that one; a change here leaves the pick as it is and does not
--     change what is saved for it.
--   Closes with: a click anywhere else, Esc, the same button, another tool or the help or the search list opening, the map,
--     the bar, the button or Vendors and trainers going off.
-- Saved: nothing here. Nothing is listened to per frame; the one listener (the prefs' change notice) repaints only an open menu.

local R = TwichUI
local PL = R.PinsLook
local S = R.ChronicleStyle
local NK, NP = R.NpcKinds, R.NpcPrefs
local FM = {}
R.NpcFilterMenu = FM

local NAME = "TwichUINpcFilter"
local WIDTH = 236
local GUTTER = 22                 -- room for the scroll bar when the list has to scroll
local BOX, ICON = 12, 14
local MIN_LIST = 110              -- the least of the list that is shown when the room is short
local EDGE = 8                    -- kept clear of the map's lower edge
local NOTE = "An NPC with several roles shows while any one of them is checked."
local HOW = "Click to show or hide these on the world map."

local menu, scroll, content, note, showAll, hideAll
local rows, heads = {}, {}        -- rows[kind id]; heads[section id]
local owner                       -- the button it hangs from
local stats = { opens = 0, changes = 0, bulk = 0 }

local function Pal()
    local T = R.MapTools
    return T and T.Pal and T.Pal() or { text = { 0.94, 0.91, 0.82 }, textDim = { 0.80, 0.78, 0.72 }, stone = { 0.62, 0.60, 0.56 },
        teal = { 0.36, 0.58, 0.57 }, tealHi = { 0.58, 0.78, 0.76 }, tealLo = { 0.18, 0.33, 0.33 } }
end
local function Paint(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end
local function Solid(f, layer, c, a)
    local t = f:CreateTexture(nil, layer)
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    return t
end

function FM.Wanted() return R:Enabled("npcMap") and PL.Pref("npcFilter") == true end
function FM.IsOpen() return menu ~= nil and menu:IsShown() end

-- An open settings window shows the choices again (a window never opened has nothing to redraw).
local function SyncSettings()
    local UI = R.SettingsUI
    if UI and UI.RefreshValues then pcall(UI.RefreshValues) end
end

---------------------------------------------------------------------------
-- Closing
---------------------------------------------------------------------------
function FM.Close()
    if not (menu and menu:IsShown()) then return false end
    menu:Hide()
    return true
end

local function OnGlobalMouseDown()
    if not (menu and menu:IsShown()) then return end
    if menu:IsMouseOver() then return end
    if owner and owner:IsMouseOver() then return end   -- the button's own click closes it, once
    FM.Close()
end

---------------------------------------------------------------------------
-- The state: the checkboxes and the two bulk buttons, from the saved choices
---------------------------------------------------------------------------
local function Repaint()
    if not menu then return end
    local pal = Pal()
    local on, total = 0, 0
    for _, kind in ipairs(NK.LIST) do
        local row = rows[kind.id]
        local checked = NP.Shown(kind.id)
        total = total + 1
        if checked then on = on + 1 end
        row.mark:SetShown(checked)
        row.icon:SetAlpha(checked and 1 or 0.45)
        row.icon:SetDesaturated(not checked)
        Paint(row.label, checked and pal.text or pal.textDim)
    end
    -- a button that would change nothing is dim (still hoverable: its tooltip says so)
    showAll:SetEnabled(on < total)
    hideAll:SetEnabled(on > 0)
    Paint(showAll.text, on < total and pal.tealHi or pal.stone)
    Paint(hideAll.text, on > 0 and pal.tealHi or pal.stone)
end

-- One kind. Returns whether the choice was kept.
function FM.SetKind(id, value)
    if not (NK.BY_ID[id] and R:Enabled("npcMap")) then return false end
    local ok = NP.Set("show." .. id, value and true or false)
    if ok then
        stats.changes = stats.changes + 1
        SyncSettings()
    end
    return ok
end

-- Every kind at once, in one change.
function FM.SetAll(value)
    if not R:Enabled("npcMap") then return false end
    local ok = NP.SetAllShown(value and true or false)
    if ok then
        stats.bulk = stats.bulk + 1
        SyncSettings()
    end
    return ok
end

-- The prefs changed (here, in the settings, by a profile): an open menu shows it.
NP.Subscribe(function()
    if menu and menu:IsShown() then Repaint() end
end)

---------------------------------------------------------------------------
-- Building (once, the first time it opens)
---------------------------------------------------------------------------
local function TextButton(label, tip, onClick)
    local b = CreateFrame("Button", nil, menu)
    b:RegisterForClicks("LeftButtonUp")
    b.text = PL.Text(b, "GameFontNormalSmall", "meta")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT", 0, -2)
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(tip, 0.78, 0.74, 0.66, true)
        if not self:IsEnabled() then GameTooltip:AddLine("Already the case.", 0.62, 0.58, 0.51) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function NewRow(kind)
    local pal = Pal()
    local b = CreateFrame("Button", nil, content)
    b:RegisterForClicks("LeftButtonUp")
    b.kind = kind
    local hl = Solid(b, "HIGHLIGHT", pal.tealHi, 0.16)
    hl:SetAllPoints()
    -- the checkbox: an outlined square, filled in when checked (the shape says it, not only the color)
    b.edge = Solid(b, "BORDER", pal.stone, 0.9)
    b.edge:SetSize(BOX, BOX)
    b.edge:SetPoint("LEFT", b, "LEFT", 6, 0)
    b.fill = Solid(b, "ARTWORK", { 0.06, 0.05, 0.04 }, 1)
    b.fill:SetSize(BOX - 2, BOX - 2)
    b.fill:SetPoint("CENTER", b.edge, "CENTER", 0, 0)
    b.mark = Solid(b, "OVERLAY", pal.tealHi, 1)
    b.mark:SetSize(BOX - 6, BOX - 6)
    b.mark:SetPoint("CENTER", b.edge, "CENTER", 0, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ICON, ICON)
    b.icon:SetPoint("LEFT", b.edge, "RIGHT", 6, 0)
    b.icon:SetTexture(kind.icon)
    b.label = PL.Text(b, "GameFontHighlightSmall", "control")
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.label:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    b.label:SetWordWrap(false)
    b.label:SetText(kind.label)
    -- the whole row is the target: the box and the name both toggle
    b:SetScript("OnClick", function(self) FM.SetKind(self.kind.id, not NP.Shown(self.kind.id)) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT", -2, 0)
        GameTooltip:SetText(self.kind.label, 1, 1, 1)
        if self.kind.tip then GameTooltip:AddLine(self.kind.tip, 0.78, 0.74, 0.66, true) end
        GameTooltip:AddLine(HOW, 0.86, 0.69, 0.30, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Build(parent)
    if menu then return end
    menu = CreateFrame("Frame", NAME, parent, "BackdropTemplate")
    menu:SetFrameStrata("HIGH")
    menu:EnableMouse(true)                    -- a click on the menu is not a click on the map
    menu:Hide()
    menu.title = PL.Text(menu, "GameFontNormalSmall", "name")
    menu.title:SetText("NPC filters")
    menu.title:SetWordWrap(false)
    showAll = TextButton("Show all", "Checks every kind of NPC. Only these choices change: not your pins, pings or route, and nothing is deleted or sent.", function() FM.SetAll(true) end)
    hideAll = TextButton("Hide all", "Unchecks every kind of NPC, so no NPC markers show. Only these choices change: not your pins, pings or route, and nothing is deleted or sent.", function() FM.SetAll(false) end)

    scroll = CreateFrame("ScrollFrame", nil, menu, "UIPanelScrollFrameTemplate")
    scroll.paintBar = S.ScrollBar(scroll, PL.palette)
    -- hidden until the list is too tall for the room (the template's own switch for it)
    scroll.scrollBarHideable = true
    scroll.ScrollBar:Hide()
    for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
        local arrow = scroll.ScrollBar[key]
        if arrow then arrow:Hide() end
    end
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH, 1)
    scroll:SetScrollChild(content)

    for _, section in ipairs(NK.SECTIONS) do
        heads[section.id] = PL.Text(content, "GameFontNormalSmall", "meta")
        heads[section.id]:SetText(section.label)
        heads[section.id]:SetWordWrap(false)
    end
    for _, kind in ipairs(NK.LIST) do rows[kind.id] = NewRow(kind) end
    note = PL.Text(content, "GameFontNormalSmall", "meta")
    note:SetWordWrap(true)
    note:SetJustifyV("TOP")
    note:SetText(NOTE)

    menu:SetScript("OnShow", function() R:On("GLOBAL_MOUSE_DOWN", OnGlobalMouseDown) end)
    menu:SetScript("OnHide", function()
        R:Off("GLOBAL_MOUSE_DOWN", OnGlobalMouseDown)
        for _, row in pairs(rows) do
            if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
        end
        if GameTooltip:IsOwned(showAll) or GameTooltip:IsOwned(hideAll) then GameTooltip:Hide() end
        local T = R.MapTools
        if T and T.Repaint then T.Repaint() end   -- the button is lit only while the menu is open
    end)
    if UISpecialFrames then tinsert(UISpecialFrames, NAME) end   -- Esc closes it (never through the game menu's handler list)
end

---------------------------------------------------------------------------
-- Drawing (each time it opens, and when the look changes)
---------------------------------------------------------------------------
-- The room below the button, down to the map's lower edge, in the menu's units; nil when it can't be told.
local function Room()
    local container = WorldMapFrame and WorldMapFrame.GetCanvasContainer and WorldMapFrame:GetCanvasContainer()
    if not (owner and container) then return nil end
    local top, bottom = owner:GetBottom(), container:GetBottom()
    local so, sc, sm = owner:GetEffectiveScale(), container:GetEffectiveScale(), menu:GetEffectiveScale()
    if not (top and bottom and so and sc and sm and sm > 0) then return nil end
    return (top * so - bottom * sc) / sm - 3 - EDGE
end

local function Layout()
    local pal = Pal()
    local pad = math.max(4, math.ceil(PL.Surface(PL.MenuLook, menu)))
    local size = PL.Get("textSize")
    local rowH = math.max(20, math.ceil(size * 1.25) + 6)
    local headH = math.max(16, math.ceil(size * 1.25) + 4)
    local width = math.floor(WIDTH * size / PL.DEFAULTS.textSize + 0.5)
    local container = WorldMapFrame and WorldMapFrame.GetCanvasContainer and WorldMapFrame:GetCanvasContainer()
    local wide = container and container:GetWidth() or 0
    if wide > 0 then width = math.min(width, math.max(200, math.floor(wide * 0.6))) end
    local inner = width - pad * 2

    -- the top line: the name, and the two bulk buttons at the right
    local topH = rowH
    menu.title:ClearAllPoints()
    menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", pad + 6, -pad - 3)
    Paint(menu.title, PL.palette.gold)
    hideAll:ClearAllPoints()
    hideAll:SetSize(math.ceil(hideAll.text:GetStringWidth() or 40) + 8, topH - 4)
    hideAll:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -pad - 2, -pad - 1)
    showAll:ClearAllPoints()
    showAll:SetSize(math.ceil(showAll.text:GetStringWidth() or 40) + 8, topH - 4)
    showAll:SetPoint("RIGHT", hideAll, "LEFT", -2, 0)
    menu.title:SetPoint("RIGHT", showAll, "LEFT", -6, 0)

    -- the list: a heading and its kinds, section after section, then the note
    local function Place(need)
        local w = inner - (need and GUTTER or 0)
        local y = 0
        for _, section in ipairs(NK.SECTIONS) do
            local head = heads[section.id]
            head:ClearAllPoints()
            head:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -y - 3)
            head:SetWidth(w - 12)
            Paint(head, pal.stone)
            y = y + headH
            for _, kind in ipairs(NK.LIST) do
                if kind.section == section.id then
                    local row = rows[kind.id]
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                    row:SetSize(w, rowH)
                    y = y + rowH
                end
            end
        end
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -y - 6)
        note:SetWidth(w - 12)
        Paint(note, pal.stone)
        y = y + 6 + math.ceil(note:GetStringHeight() or 24) + 4
        content:SetSize(w, y)
        return y, w
    end
    local contentH = Place(false)
    local room = Room()
    local chrome = pad * 2 + topH + 6
    local maxList = room and math.max(MIN_LIST, room - chrome) or contentH
    local need = contentH > maxList
    local listH, w = contentH, inner
    if need then
        _, w = Place(true)
        listH = maxList
    end
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", menu, "TOPLEFT", pad, -(pad + topH + 6))
    scroll:SetSize(w, listH)
    scroll:SetVerticalScroll(0)
    menu:SetSize(width, chrome + listH)
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -3)   -- inside the map: the bar's right end is the map's
    menu:SetFrameLevel((owner:GetParent():GetFrameLevel() or 1) + 20)
end

---------------------------------------------------------------------------
-- Opening
---------------------------------------------------------------------------
-- anchor: the filter button. Returns whether the menu is open. The caller (the tool bar) has put away what it shouldn't
-- share the map's attention with.
function FM.Open(anchor)
    if not FM.Wanted() then
        if R.PinsMap and R.PinsMap.Notice then R.PinsMap.Notice("Vendors and trainers is turned off in TwichUI's settings.") end
        return false
    end
    if not (anchor and anchor.GetParent and anchor:GetParent()) then return false end
    Build(anchor:GetParent())
    owner = anchor
    stats.opens = stats.opens + 1
    Layout()
    Repaint()
    menu:Show()
    menu:Raise()
    return true
end

function FM.Toggle(anchor)
    if FM.IsOpen() then FM.Close() return false end
    return FM.Open(anchor)
end

-- Vendors and trainers, or the button, went off: nothing stays open. (The tool bar draws itself again.)
function FM.Refresh()
    if not FM.Wanted() then FM.Close() end
    local T = R.MapTools
    if T and T.Refresh then T.Refresh() end
end

local function LookChanged()
    if menu and menu:IsShown() then Layout() Repaint() end
end
PL.Subscribe(LookChanged)
PL.MenuLook.Subscribe(LookChanged)

-- Read only, for /tui diagnostics and the tests: states and counts.
function FM.Snapshot()
    local checked = 0
    for _, kind in ipairs(NK.LIST) do if NP.Shown(kind.id) then checked = checked + 1 end end
    return { wanted = FM.Wanted(), built = menu ~= nil, open = FM.IsOpen(), kinds = #NK.LIST, checked = checked,
        opens = stats.opens, changes = stats.changes, bulk = stats.bulk }
end
function FM.Row(id) return rows[id] end
