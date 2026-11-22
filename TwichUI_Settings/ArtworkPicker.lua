local R = TwichUI
local IP = {}
R.SettingsArtworkPicker = IP

local WIDTH, HEIGHT, PAD, GAP = 512, 668, 16, 8
local SIDEBAR_W = 144
local TILE, THUMB, COLS = 96, 78, 3
local GRID_W = COLS * TILE + (COLS - 1) * GAP
local PANE_TOP, PANE_H = 122, 362
local NAME = "TwichUIArtworkPicker"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- A small picture standing for each category in the sidebar (catalog ids), so the list reads at a glance.
local CATEGORY_ART = {
    ["Equipment"] = "reminder-lion-shield", ["Buffs & Effects"] = "reminder-arcane-sigil", ["Supplies"] = "reminder-health-potion",
    ["Character"] = "reminder-low-health", ["Adventure"] = "reminder-marked-map", ["General"] = "reminder-bronze-bell",
}

local f, session
local function Wg() return R.SettingsWidgets end
local function G() return R.Artwork end
local function Same(a, b) return a and b and a.kind == b.kind and a.id == b.id end
local function Ref(entry) return entry and (entry.ref or entry) end

function IP.Shown() return f ~= nil and f:IsShown() end
function IP.Frame() return f end
function IP.State()
    if not session then return nil end
    local c = session.candidate
    return { owner = session.owner, key = session.key, token = session.token, candidate = c and { kind = c.kind, id = c.id }, source = session.source, category = session.category }
end
function IP.Candidate() local s = IP.State(); return s and s.candidate end
function IP.Source() return session and session.source end

---------------------------------------------------------------------------
-- Pictures
---------------------------------------------------------------------------
-- A catalog entry or an item drawn into `tex` at `size` units (the art keeps its aspect; an item's icon is a square).
local function Draw(tex, candidate, size)
    local ok
    if candidate and candidate.kind == "automatic" and session and session.opts.automatic then
        session.opts.automatic.Draw(tex, size)
        return
    end
    if candidate then ok = G().Draw(tex, Ref(candidate), size) end
    if not ok and candidate and session then
        local fallback = session.opts.fallback or session.opts.automatic
        if fallback then fallback.Draw(tex, size); return false end
    end
    if not ok then
        tex:SetVertexColor(1, 1, 1, 1); tex:SetAlpha(1)
        tex:SetTexture(QUESTION); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92); tex:SetSize(size, size)
    end
    return ok
end
IP.Draw = Draw

---------------------------------------------------------------------------
-- The details strip: what the candidate is, and where it comes from
---------------------------------------------------------------------------
local requested = {}
local function Plain(v) if v == nil or (issecretvalue and issecretvalue(v)) then return nil end return v end
local function ItemInfo(id)
    if not id or not C_Item then return nil, "loading" end
    local name = C_Item.GetItemNameByID and Plain(C_Item.GetItemNameByID(id))
    if type(name) == "string" and name ~= "" then return name, "ok" end
    if C_Item.GetItemInfoInstant and Plain((C_Item.GetItemInfoInstant(id))) == nil and (requested[id] or 0) >= 2 then return nil, "missing" end
    if (requested[id] or 0) < 2 and C_Item.RequestLoadItemDataByID then
        requested[id] = (requested[id] or 0) + 1; C_Item.RequestLoadItemDataByID(id)
    end
    return nil, "loading"
end
local function Details()
    local d, c = f.details, session and session.candidate
    local ready = Draw(d.thumb, c, 64)
    local entry = c and G().Get(c)
    if not c then
        d.name:SetText("Nothing chosen")
        d.line:SetText(session and session.source == "game" and "Name an item to use its icon." or "Choose a picture from the list.")
        d.source:SetText("")
    elseif c.kind == "automatic" then
        d.name:SetText(session.opts.automatic.name); d.line:SetText(""); d.source:SetText("Automatic")
    elseif c.kind == "item" then
        local name, state = ItemInfo(c.id)
        d.name:SetText(name or ("Item " .. c.id))
        d.line:SetText(state == "ok" and ("Item " .. c.id) or state == "missing" and "The game has no such item. Check the number." or "Loading the item's details...")
        d.source:SetText("Game icon")
    elseif entry and ready then
        d.name:SetText(entry.name); d.line:SetText(entry.description or ""); d.source:SetText(entry.category .. " · TwichUI artwork")
    else
        local fallback = session.opts.fallback or session.opts.automatic
        d.name:SetText(fallback and ("Artwork unavailable — showing " .. fallback.name) or "Artwork unavailable")
        d.line:SetText("Choose another picture to replace it."); d.source:SetText("TwichUI artwork")
    end
    f.apply:SetEnabled(c ~= nil and (c.kind == "item" or c.kind == "automatic" or (entry ~= nil and ready)))
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
    session.candidate = G().Check(tile.entry.ref)
    for _, t in ipairs(f.tiles) do Mark(t, t.entry ~= nil and t:IsShown() and Same(Ref(t.entry), session.candidate)) end
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
        Draw(t.thumb, entry.ref, THUMB)
        Mark(t, session.candidate ~= nil and Same(entry.ref, session.candidate))
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
    local id = type(text) == "string" and tonumber(text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$"))
    local ref = id and G().Check({ kind = "item", id = id })
    id = ref and ref.id
    if not id then
        IP.Say("That isn't an item ID. Type the number from the item's link, paste the link, or drop the item on the box.", "warn")
        return
    end
    IP.Say("")
    f.itemBox:SetText("")
    f.itemBox:ClearFocus()
    if session then session.candidate = ref end
    IP.Refresh()
end
IP.TakeItem = TakeItem

local function ItemPane()
    local c = session and session.candidate
    local item = c and c.kind == "item" and c
    Draw(f.itemThumb, item, 64)
    local line, tone = "No item chosen yet.", "quiet"
    if item then
        local name, state = ItemInfo(item.id)
        if state == "ok" then line, tone = ("%s (item %d)"):format(name, item.id), "ok"
        elseif state == "missing" then line, tone = ("The game has no item %d. Check the number."):format(item.id), "warn"
        else line, tone = ("Item %d: loading its details..."):format(item.id), nil end
    end
    f.itemInfo:SetText(line)
    local W = Wg(); W.Color(f.itemInfo, tone == "warn" and W.pal.danger.text or (tone == "ok" and W.pal.sage or (tone == "quiet" and W.pal.stone or W.pal.textDim)))
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
            if t:IsShown() then Mark(t, t.entry ~= nil and session.candidate ~= nil and Same(Ref(t.entry), session.candidate)) end
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
local closingReason
function IP.Close(owner, reason)
    if not session or (owner and session.owner ~= owner) then return false end
    closingReason = reason or "cancelled"
    if IP.Shown() then f:Hide() end
    return true
end
function IP.Cancel() return IP.Close(nil, "cancelled") end
function IP.Apply()
    if not (IP.Shown() and session and session.candidate) or session.applying then return false end
    local current = session
    if not current.owner:IsVisible() or not current.opts.IsCurrent() then IP.Close(current.owner, "invalidated"); return false end
    local candidate = G().Check(current.candidate)
    if not candidate then IP.Say("Please choose a picture.", "warn"); return false end
    if candidate.kind ~= "item" and candidate.kind ~= "automatic" then
        local ready = G().Get(candidate) and G().Draw(f.details.thumb, candidate, 64)
        if not ready then IP.Refresh(); IP.Say("Artwork unavailable.", "warn"); return false end
    end
    current.applying = true
    local called, accepted, why = pcall(current.opts.OnApply, candidate)
    current.applying = false
    if session ~= current then return called and accepted == true end
    if not called and R.Fault then R.Fault("settings artwork picker", accepted) end
    if not called or accepted ~= true then IP.Say(called and (why or "Could not apply this picture.") or "Could not apply this picture.", "warn"); return false end
    IP.Close(current.owner, "applied")
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
    f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    f:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    f:SetScript("OnEvent", function() if session and session.candidate and session.candidate.kind == "item" then IP.Refresh() end end)
    f:SetScript("OnHide", function()
        f.search:ClearFocus()
        f.itemBox:ClearFocus()
        local old, reason = session, closingReason or "cancelled"
        session, closingReason, requested = nil, nil, {}
        R.SettingsMaterial.RestoreCompanionAnchor()
        if old and old.opts.OnClosed then pcall(old.opts.OnClosed, reason) end
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
        if art and G().Get({ kind = "art", id = art }) then
            local icon = b:CreateTexture(nil, "OVERLAY")
            icon:SetPoint("LEFT", 8, 0)
            icon:SetSize(20, 20)
            G().Draw(icon, { kind = "art", id = art }, 20)
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
    f.showAll = W.Button(f.content, "Show all pictures", 160, "secondary", function() IP.SetQuery(""); IP.SetCategory("All") end)
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
    f.automatic = W.Button(f, "Use automatic icon", 160, "secondary", function()
        if session and session.opts.automatic then session.candidate = { kind = "automatic" }; IP.Refresh() end
    end)
    M.ReminderControl(f.automatic, "action")
    f.automatic:SetHeight(38); f.automatic:SetPoint("BOTTOMLEFT", PAD, 36)
    f.say = W.Text(f, "small")
    f.say:SetPoint("BOTTOMLEFT", PAD, 14)
    f.say:SetWidth(WIDTH - PAD * 2)
end

local hooked = setmetatable({}, { __mode = "k" })
function IP.Open(owner, opts)
    if not owner or type(owner.IsVisible) ~= "function" or type(owner.HookScript) ~= "function" then return false, "invalid_owner" end
    if type(opts) ~= "table" or opts.key == nil or type(opts.IsCurrent) ~= "function" or type(opts.OnApply) ~= "function"
        or (opts.OnClosed ~= nil and type(opts.OnClosed) ~= "function") then return false, "invalid_options" end
    if opts.fallback ~= nil and (type(opts.fallback) ~= "table" or type(opts.fallback.name) ~= "string" or type(opts.fallback.Draw) ~= "function") then return false, "invalid_options" end
    if opts.automatic ~= nil and (type(opts.automatic) ~= "table" or type(opts.automatic.label) ~= "string"
        or type(opts.automatic.name) ~= "string" or type(opts.automatic.Draw) ~= "function") then return false, "invalid_options" end
    local start = opts.selection and G().Check(opts.selection)
    if opts.selection and not start then return false, "invalid_ref" end
    if start and start.kind == "automatic" and not opts.automatic then return false, "invalid_ref" end
    if not owner:IsVisible() or not opts.IsCurrent() then return false, "stale_owner" end
    if session and session.owner == owner and session.key == opts.key then IP.Close(owner); return false, "toggled" end
    if session then IP.Close(nil, "replaced") end
    if not f then Build() end
    if not hooked[owner] then
        owner:HookScript("OnHide", function() if session and session.owner == owner then IP.Close(owner, "owner_hidden") end end)
        hooked[owner] = true
    end
    start = start or (opts.automatic and { kind = "automatic" } or nil)
    local token = {}
    session = { owner = owner, key = opts.key, opts = opts, token = token, candidate = start, category = "All", source = start and start.kind == "item" and "game" or "art" }
    f.sub:SetText(opts.subtitle or "Select an illustration.")
    f.automatic:SetShown(opts.automatic ~= nil)
    if opts.automatic then f.automatic.text:SetText(opts.automatic.label) end
    f.search:SetText(""); f.itemBox:SetText(""); Query(); IP.Say("")
    R.SettingsMaterial.PlaceCompanion(f)
    f:Show(); Categories(); IP.SetSource(session.source); f.scroll:SetVerticalScroll(0)
    if session.source == "art" and start then
        for i, e in ipairs(G().Search("", session.category)) do
            if Same(e.ref, start) then
                local row = math.floor((i - 1) / COLS)
                f.scroll:SetVerticalScroll(math.max(0, math.min(row * (TILE + GAP) - (TILE + GAP), f.content:GetHeight() - PANE_H + 35)))
                break
            end
        end
    end
    return true, token
end

if R.OnSettingsClosed then R.OnSettingsClosed(function() IP.Close(nil, "settings_closed") end) end
if R.Profiles and R.Profiles.OnApply then
    R.Profiles.OnApply("views", "settings-artwork-picker", function() IP.Close(nil, "invalidated") end)
end
