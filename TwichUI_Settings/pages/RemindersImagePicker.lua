-- TwichUI settings: the Reminders image picker. A frame beside the settings window (R.SettingsAnchor, where the template catalog and the
-- live preview also sit, one at a time) with two sources behind two tabs: TwichUI artwork (every picture TwichUI has made for reminders,
-- by category, with search) and Game icons (the icon of an item you name by its ID or link, as a reminder could always use).
--
-- Browsing is a candidate, never a change: clicking a picture or naming an item only marks it and shows it in the details strip. Apply
-- commits it through the page's checked path (reminders/Gallery.lua's G.Choose, one RM.SetDisplayMany: the mode, the picture and where it
-- comes from, all or none) and puts the picker away; Cancel, the X, Esc and the settings window closing discard it and write nothing.
-- It draws no reminder on screen and never starts the live preview: the page redraws its own preview after it closes, as it does after
-- the catalog. What is catalogued is reminders/Gallery.lua's; the pictures are docs/reminders-art.md's.
--
--   IP.Open(id, env)   env: { Say(text, tone), Changed() }   open for reminder `id`, starting from the picture it has now
--   IP.Cancel(), IP.Apply(), IP.Shown(), IP.Frame(), IP.ReminderId(), IP.Candidate()

local R = TwichUI
local IP = {}
R.RemindersImagePicker = IP

local WIDTH, HEIGHT, PAD, GAP = 512, 668, 16, 8
local SIDEBAR_W = 144
local TILE, THUMB, COLS = 96, 78, 3
local GRID_W = COLS * TILE + (COLS - 1) * GAP
local PANE_TOP, PANE_H = 122, 362
local NAME = "TwichUIReminderImagePicker"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- A small picture standing for each category in the sidebar (catalog ids), so the list reads at a glance.
local CATEGORY_ART = {
    ["Equipment"] = "reminder-lion-shield", ["Buffs & Effects"] = "reminder-arcane-sigil", ["Supplies"] = "reminder-health-potion",
    ["Character"] = "reminder-low-health", ["Adventure"] = "reminder-marked-map", ["General"] = "reminder-bronze-bell",
}

local f, session
local function Wg() return R.SettingsWidgets end
local function RM() return R.Reminders end
local function G() return R.Reminders.Gallery end

function IP.Shown() return f ~= nil and f:IsShown() end
function IP.Frame() return f end
function IP.ReminderId() return session and session.id end
function IP.Candidate() return session and session.candidate end
function IP.Source() return session and session.source end

---------------------------------------------------------------------------
-- Pictures
---------------------------------------------------------------------------
-- A catalog entry or an item drawn into `tex` at `size` units (the art keeps its aspect; an item's icon is a square).
local function Draw(tex, candidate, size)
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetAlpha(1)
    if not candidate then
        tex:SetTexture(QUESTION)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tex:SetSize(size, size)
    elseif candidate.kind == "art" then
        local file, l, r, t, b, aspect = RM().ArtTexture(candidate.target, size)
        tex:SetTexture(file)
        tex:SetTexCoord(l, r, t, b)
        tex:SetSize(size * math.min(1, aspect), size / math.max(1, aspect))
    elseif candidate.kind == "icon" then
        tex:SetSize(size, size)
        R.Icons.Apply(tex, candidate.target, size)
    else
        local icon = C_Item and C_Item.GetItemIconByID and candidate.item and C_Item.GetItemIconByID(candidate.item)
        tex:SetTexture(icon or QUESTION)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tex:SetSize(size, size)
    end
end
IP.Draw = Draw

---------------------------------------------------------------------------
-- The details strip: what the candidate is, and where it comes from
---------------------------------------------------------------------------
local function Details()
    local d = f.details
    local c = session and session.candidate
    Draw(d.thumb, c, 64)
    if not c then
        d.name:SetText("Nothing chosen")
        d.line:SetText(session and session.source == "game" and "Name an item to use its icon." or "Choose a picture from the list.")
        d.source:SetText("")
    elseif c.kind == "item" then
        local E = R.RemindersEditor
        local name, state = E.ItemInfo(c.item)
        d.name:SetText(name or ("Item " .. c.item))
        d.line:SetText(state == "ok" and ("Item " .. c.item) or state == "missing" and "The game has no such item. Check the number." or "Loading the item's details...")
        d.source:SetText("Game icon")
    else
        d.name:SetText(c.name)
        d.line:SetText(c.description or "")
        d.source:SetText(c.category .. " · TwichUI artwork")
    end
    f.apply:SetEnabled(c ~= nil and not (c.kind == "item" and not RM().ValidItem(c.item)))
end

---------------------------------------------------------------------------
-- The artwork pane: categories, search and the grid
---------------------------------------------------------------------------
-- A tile is marked by the selection skin, a warm gold wash and the settings' gold rim (full strength when chosen, a quiet bronze hint
-- while the pointer is over an unchosen one). The picture sits on a frame above them so they never cover it.
local function Mark(tile, on)
    tile.chosen = on and true or false
    tile:SetSelected(tile.chosen)
    if tile.rim then
        tile.rim:SetShown(tile.chosen or tile.hot == true)
        tile.rim:SetAlpha(tile.chosen and 1 or 0.45)
        tile.wash:SetShown(tile.chosen)
    end
end

local function SelectTile(tile)
    if not (session and tile.entry) then return end
    session.candidate = tile.entry
    for _, t in ipairs(f.tiles) do Mark(t, t.entry ~= nil and t:IsShown() and G().SameCandidate(t.entry, session.candidate)) end
    Details()
end

local function Tile(i)
    if f.tiles[i] then return f.tiles[i] end
    local M = R.SettingsMaterial
    local t = M.Segment(f.content, "", TILE, function(self) SelectTile(self) end)
    t:SetSize(TILE, TILE)
    local level = t:GetFrameLevel() or 1
    -- the settings' own gold wash and hover rim, over the selection skin
    t.wash = CreateFrame("Frame", nil, t)
    t.wash:SetAllPoints()
    t.wash:SetFrameLevel(level + 1)
    t.wash:EnableMouse(false)
    R.SettingsCraft.Sheet(t.wash, "selection-hot", { layer = "BACKGROUND", corner = 8 }):SetAlpha(0.30)
    t.wash:Hide()
    t.rim = CreateFrame("Frame", nil, t)
    t.rim:SetAllPoints()
    t.rim:SetFrameLevel(level + 2)
    t.rim:EnableMouse(false)
    R.SettingsCraft.Sheet(t.rim, "hover-rim", { layer = "OVERLAY", corner = 8 })
    t.rim:Hide()
    t.body = CreateFrame("Frame", nil, t)
    t.body:SetAllPoints()
    t.body:SetFrameLevel(level + 3)
    t.body:EnableMouse(false)
    t.thumb = t.body:CreateTexture(nil, "ARTWORK")
    t.thumb:SetPoint("CENTER", 0, 0)
    t:HookScript("OnEnter", function(self) self.hot = true; Mark(self, self.chosen) end)
    t:HookScript("OnLeave", function(self) self.hot = false; Mark(self, self.chosen) end)
    t:HookScript("OnHide", function(self) self.hot = false end)
    R.Interact.Tip(t, nil, function(self) return self.entry and (self.entry.description or "") or nil end, "ANCHOR_TOP")
    f.tiles[i] = t
    return t
end

local function Fill()
    if not session then return end
    local list = G().Search(f.search:GetText(), session.category)
    f.count = #list
    f.empty:SetShown(#list == 0)
    f.showAll:SetShown(#list == 0)
    f.content:SetHeight(math.max(1, math.ceil(#list / COLS) * (TILE + GAP)))
    for i, entry in ipairs(list) do
        local t = Tile(i)
        t.entry = entry
        t.twichuiTip.title = entry.name
        local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", f.content, "TOPLEFT", col * (TILE + GAP), -row * (TILE + GAP))
        Draw(t.thumb, entry, THUMB)
        Mark(t, session.candidate ~= nil and G().SameCandidate(entry, session.candidate))
        t:Show()
    end
    for i = #list + 1, #f.tiles do
        f.tiles[i].entry = nil
        Mark(f.tiles[i], false)
        f.tiles[i]:Hide()
    end
    if f.fitRail then f.fitRail(f.content:GetHeight()) end
end

local function Categories()
    for _, b in ipairs(f.cats) do
        b:SetSelected(session ~= nil and b.category == session.category)
    end
end

local function Query()
    f.searchHint:SetShown(f.search:GetText() == "" and not f.search:HasFocus())
end

function IP.SetCategory(category)
    if not session then return end
    session.category = category
    Categories()
    Fill()
    f.scroll:SetVerticalScroll(0)
end

function IP.SetQuery(text)
    if not f then return end
    f.search:SetText(text or "")
    Query()
    Fill()
    f.scroll:SetVerticalScroll(0)
end

---------------------------------------------------------------------------
-- The game icons pane
---------------------------------------------------------------------------
local function TakeItem(text)
    local id = RM().ParseItem(text)
    if not id then
        IP.Say("That isn't an item ID. Type the number from the item's link, paste the link, or drop the item on the box.", "warn")
        return
    end
    IP.Say("")
    f.itemBox:SetText("")
    f.itemBox:ClearFocus()
    if session then session.candidate = G().ItemCandidate(id) end
    IP.Refresh()
end
IP.TakeItem = TakeItem

local function ItemPane()
    local c = session and session.candidate
    local item = c and c.kind == "item" and c
    Draw(f.itemThumb, item or nil, 64)
    if item then
        local line, tone = R.RemindersEditor.Kit.ItemLine(item.item)
        f.itemInfo:SetText(line)
        R.RemindersEditor.Kit.Tone(f.itemInfo, tone)
    else
        f.itemInfo:SetText("No item chosen yet.")
        R.RemindersEditor.Kit.Tone(f.itemInfo, "quiet")
    end
end

---------------------------------------------------------------------------
-- Source tabs
---------------------------------------------------------------------------
function IP.SetSource(source)
    if not (f and session) then return end
    session.source = source
    f.tabArt:SetSelected(source == "art")
    f.tabGame:SetSelected(source == "game")
    f.artPane:SetShown(source == "art")
    f.gamePane:SetShown(source == "game")
    if source == "art" then Fill() end
    IP.Refresh()
end

function IP.Refresh()
    if not (f and session) then return end
    Details()
    if session.source == "game" then ItemPane() end
    if session.source == "art" then
        for _, t in ipairs(f.tiles) do
            if t:IsShown() then Mark(t, t.entry ~= nil and session.candidate ~= nil and G().SameCandidate(t.entry, session.candidate)) end
        end
    end
end

function IP.Say(text, tone)
    if not f then return end
    f.say:SetText(text or "")
    local W = Wg()
    W.Color(f.say, tone == "warn" and W.pal.danger.text or W.pal.textDim)
end

---------------------------------------------------------------------------
-- Choosing and closing
---------------------------------------------------------------------------
-- Away, writing nothing. The page draws its preview again (the companion place is the picker's until then).
function IP.Cancel()
    if not IP.Shown() then session = nil; return end
    f:Hide()
end

function IP.Apply()
    if not (IP.Shown() and session and session.candidate) then return false end
    local candidate, id = session.candidate, session.id
    local ok, why = G().Choose(id, candidate)
    if not ok then
        IP.Say(why or RM().REFUSE.value, "warn")
        return false
    end
    local env = session.env
    f:Hide()
    if env and env.Changed then env.Changed() end
    return true
end

local function Build()
    local W, M = Wg(), R.SettingsMaterial
    f = CreateFrame("Frame", NAME, UIParent)
    f.companionHeight = HEIGHT
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    M.Companion(f)
    M.HeaderBand(f, 72)
    f:SetScript("OnHide", function()
        f.search:ClearFocus()
        f.itemBox:ClearFocus()
        session = nil
        if R.RemindersPage then R.RemindersPage.QueueRefresh() end
    end)

    f.title = M.ReminderFont(W.Text(f, "heading"), 23, true)
    f.title:SetPoint("TOPLEFT", PAD, -14)
    f.title:SetText("Choose an image")
    f.sub = M.ReminderFont(W.Text(f, "body"), 14)
    f.sub:SetPoint("TOPLEFT", PAD, -44)
    f.sub:SetText("Select an illustration for your reminder.")
    f.close = W.Button(f, "X", 26, "secondary", IP.Cancel)
    M.ReminderControl(f.close)
    f.close:SetPoint("TOPRIGHT", -12, -12)

    -- sources
    local tabW = (WIDTH - PAD * 2 - GAP) / 2
    f.tabArt = M.Segment(f, "TwichUI artwork", tabW, function() IP.SetSource("art") end)
    f.tabArt:SetHeight(34)
    f.tabArt:SetPoint("TOPLEFT", PAD, -78)
    f.tabGame = M.Segment(f, "Game icons", tabW, function() IP.SetSource("game") end)
    f.tabGame:SetHeight(34)
    f.tabGame:SetPoint("TOPLEFT", PAD + tabW + GAP, -78)
    R.Interact.Tip(f.tabArt, "TwichUI artwork", "Pictures TwichUI has made for reminders, by kind.")
    R.Interact.Tip(f.tabGame, "Game icons", "The icon of any item, by its ID or link. The item doesn't need to be carried or equipped.")

    ---------------- artwork pane
    f.artPane = CreateFrame("Frame", nil, f)
    f.artPane:SetPoint("TOPLEFT", PAD, -PANE_TOP)
    f.artPane:SetSize(WIDTH - PAD * 2, PANE_H)
    f.search = W.EditBox(f.artPane, WIDTH - PAD * 2, 27)
    f.search:SetPoint("TOPLEFT", 0, 0)
    f.search:SetMaxLetters(60)
    M.ReminderControl(f.search, "field")
    f.searchHint = M.SearchDecoration(f.search, "Search artwork...")
    f.search:SetScript("OnTextChanged", function() Query(); Fill(); if f.scroll then f.scroll:SetVerticalScroll(0) end end)
    f.search:HookScript("OnEditFocusGained", Query)
    f.search:HookScript("OnEditFocusLost", Query)
    f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    f.cats = {}
    local names = G().Categories()
    for i, category in ipairs(names) do
        local b = M.Segment(f.artPane, category, SIDEBAR_W, function() IP.SetCategory(category) end)
        b:SetHeight(30)
        b.category = category
        b:SetPoint("TOPLEFT", 0, -(35 + (i - 1) * 34))
        b.craftLabelInset = 32
        local art = CATEGORY_ART[category]
        if art and RM().Art(art) then
            local icon = b:CreateTexture(nil, "OVERLAY")
            icon:SetPoint("LEFT", 8, 0)
            icon:SetSize(20, 20)
            local file, l, r, t, bt = RM().ArtTexture(art, 32)
            icon:SetTexture(file)
            icon:SetTexCoord(l, r, t, bt)
        else
            -- All has no picture of its own: four small squares
            for q = 0, 3 do
                local sq = W.Solid(b, "OVERLAY", W.pal.bronzeText, 0.95)
                sq:SetSize(7, 7)
                sq:SetPoint("LEFT", 10 + (q % 2) * 9, (q < 2) and 5 or -5)
            end
        end
        if b.twichCraft and b.twichCraft.Refresh then b.twichCraft.Refresh() end
        f.cats[i] = b
    end

    f.scroll, f.content = W.Scroll(f.artPane, GRID_W)
    f.fitRail = M.ScrollRail(f.scroll)
    f.scroll:SetPoint("TOPLEFT", SIDEBAR_W + GAP, -35)
    f.scroll:SetPoint("BOTTOMRIGHT", -22, 0)
    f.empty = W.Text(f.content, "body")
    f.empty:SetWidth(GRID_W - 16)
    f.empty:SetPoint("TOPLEFT", 8, -12)
    f.empty:SetText("No picture matches. Try another word, or show everything again.")
    f.showAll = W.Button(f.content, "Show all pictures", 160, "secondary", function() IP.SetQuery(""); IP.SetCategory(G().ALL) end)
    M.ReminderControl(f.showAll, "action")
    f.showAll:SetHeight(30)
    f.showAll:SetPoint("TOPLEFT", 8, -64)
    f.tiles = {}

    ---------------- game icons pane
    f.gamePane = CreateFrame("Frame", nil, f)
    f.gamePane:SetPoint("TOPLEFT", PAD, -PANE_TOP)
    f.gamePane:SetSize(WIDTH - PAD * 2, PANE_H)
    f.gamePane:Hide()
    local box = CreateFrame("Frame", nil, f.gamePane)
    box:SetAllPoints()
    M.PanelFace(box, "espresso")
    f.itemLabel = M.ReminderFont(W.Text(box, "heading"), 16, true)
    f.itemLabel:SetPoint("TOPLEFT", 16, -16)
    f.itemLabel:SetText("Use an item's icon")
    f.itemHelp = M.ReminderFont(W.Text(box, "body"), 14)
    f.itemHelp:SetPoint("TOPLEFT", 16, -44)
    f.itemHelp:SetWidth(WIDTH - PAD * 2 - 32)
    f.itemHelp:SetText("Type an item's ID, paste its link, or drop the item here from your bags (it goes straight back). Press Enter. The item doesn't need to be carried or equipped.")
    f.itemBox = W.EditBox(box, WIDTH - PAD * 2 - 32, 28)
    f.itemBox:SetPoint("TOPLEFT", 16, -108)
    f.itemBox:SetMaxLetters(200)
    M.ReminderControl(f.itemBox, "field")
    f.itemBox:SetScript("OnEnterPressed", function(self) TakeItem(self:GetText()) end)
    f.itemBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.itemBox:SetScript("OnReceiveDrag", function()
        local kind, id = GetCursorInfo()
        if kind ~= "item" then return end
        ClearCursor()   -- the item goes straight back where it came from; only its ID is noted
        if issecretvalue and issecretvalue(id) then return end
        TakeItem(tostring(id or ""))
    end)
    R.Interact.Tip(f.itemBox, "Item", "Type its item ID, paste its link, or drop it here from your bags (it goes straight back). Press Enter.")
    f.itemThumb = box:CreateTexture(nil, "ARTWORK")
    f.itemThumb:SetPoint("TOPLEFT", 16, -156)
    f.itemInfo = M.ReminderFont(W.Text(box, "body"), 14)
    f.itemInfo:SetPoint("TOPLEFT", f.itemThumb, "TOPRIGHT", 12, -4)
    f.itemInfo:SetWidth(WIDTH - PAD * 2 - 32 - 76)

    ---------------- details strip, Apply, Cancel
    local d = CreateFrame("Frame", nil, f)
    d:SetPoint("TOPLEFT", PAD, -(PANE_TOP + PANE_H + 8))
    d:SetSize(WIDTH - PAD * 2, 92)
    M.PanelFace(d, "card")
    d.thumb = d:CreateTexture(nil, "ARTWORK")
    d.thumb:SetPoint("LEFT", 14, 0)
    d.name = M.ReminderFont(W.Text(d, "heading"), 17, true)
    d.name:SetPoint("TOPLEFT", 90, -14)
    d.name:SetWidth(WIDTH - PAD * 2 - 106)
    d.name:SetMaxLines(1)
    d.line = M.ReminderFont(W.Text(d, "body"), 14)
    d.line:SetPoint("TOPLEFT", 90, -38)
    d.line:SetWidth(WIDTH - PAD * 2 - 106)
    d.line:SetMaxLines(2)
    d.source = W.Text(d, "small")
    d.source:SetPoint("BOTTOMLEFT", 90, 10)
    d.source:SetWidth(WIDTH - PAD * 2 - 106)
    f.details = d

    -- the same footer buttons as the When designer's: Cancel quiet, Apply the gold confirmation
    f.cancel = W.Button(f, "Cancel", 104, "secondary", IP.Cancel)
    M.ReminderControl(f.cancel, "action")
    f.cancel:SetHeight(38)
    M.ReminderFont(f.cancel.text, 14)
    f.cancel:SetPoint("BOTTOMRIGHT", -PAD, 36)
    f.apply = W.Button(f, "Apply", 116, "primary", function() IP.Apply() end)
    M.ReminderControl(f.apply, "confirmation")
    f.apply:SetHeight(38)
    M.ReminderFont(f.apply.text, 14)
    f.apply:SetPoint("RIGHT", f.cancel, "LEFT", -GAP, 0)
    R.Interact.Tip(f.apply, "Apply", "Use this picture for the reminder. Nothing changes until you do.")
    f.say = W.Text(f, "small")
    f.say:SetPoint("BOTTOMLEFT", PAD, 14)
    f.say:SetWidth(WIDTH - PAD * 2)
end

-- Opens it beside the settings window (centered if that is not up), starting from what the reminder shows now.
function IP.Open(id, env)
    local v = RM().Get(id)
    if not v then return false end
    if IP.Shown() and session and session.id == id then IP.Cancel(); return false end   -- the button toggles it
    local designer, catalog = R.RemindersDesigner, R.RemindersCatalog
    if designer and designer.Shown() then return false end
    if not f then Build() end
    if catalog then catalog.Hide() end
    if R.RemindersPreview then R.RemindersPreview.Hide() end   -- the companion place holds one thing at a time
    local start = G().CandidateOf(v.display)
    local source = G().Source(v.display)
    session = { id = id, env = env, start = start, candidate = start, category = G().ALL, source = source == "item" and "game" or "art" }
    f.search:SetText("")
    f.itemBox:SetText("")
    Query()
    IP.Say("")
    if R.RemindersPreview then R.RemindersPreview.Place(f) end
    f:Show()
    Categories()
    IP.SetSource(session.source)
    f.scroll:SetVerticalScroll(0)
    -- bring the current picture into view
    if session.source == "art" and start then
        for i, e in ipairs(G().Search("", session.category)) do
            if G().SameCandidate(e, start) then
                local row = math.floor((i - 1) / COLS)
                f.scroll:SetVerticalScroll(math.max(0, math.min(row * (TILE + GAP) - (TILE + GAP), f.content:GetHeight() - PANE_H + 35)))
                break
            end
        end
    end
    return true
end

if R.OnSettingsClosed then R.OnSettingsClosed(IP.Cancel) end
