-- TwichUI settings: the Reminders template catalog. A frame beside the settings window (R.SettingsAnchor, as the sample
-- previews do) listing the templates as cards: a picture, a name, a line about it and "Use template"; and "Custom
-- reminder" under them. Choosing one goes through the page's own P.Create, which makes the reminder by the same checked
-- path as before (reminders/Config.lua RM.Create: a fresh copy, its own id, turned off), selects it and opens its editor.
-- A refusal (the limit, a newer profile) is said here and the catalog stays open. Closing it, by its box, Esc or the
-- settings window closing, makes and changes nothing. Catalog filters affect the visible templates only.

local R = TwichUI
local C = {}
R.RemindersCatalog = C
local CARD_ART = { item = { 222, 256 }, custom = { 51, 64, "-small" } }

local WIDTH, PAD, GAP = 504, 16, 10
local LIST_W = WIDTH - PAD * 2 - 22
local CARD_W = (LIST_W - GAP) / 2
local CARD_H, THUMB = 196, 94
local FILTERS = { { "all", "All" }, { "preparation", "Preparation" }, { "equipment", "Equipment" } }
local TEMPLATE_META = {
    enchant = { "preparation", "oil poison stone temporary buff" },
    wellFed = { "preparation", "food eat buff" },
    shield = { "equipment", "offhand off hand" },
    ammo = { "equipment", "arrows bullets ranged" },
    item = { "equipment", "gear missing" },
}
local ORDER = { "enchant", "wellFed", "shield", "ammo", "item" }
local NAME = "TwichUIReminderCatalog"

local f
local function Wg() return R.SettingsWidgets end
local function RM() return R.Reminders end

-- The template's own picture: its artwork where it has some, else the feature's icon.
local function Picture(tex, kind)
    local meta = CARD_ART[kind]
    if meta then
        tex:SetTexture(R.PATH .. [[media\reminders\]] .. kind .. (meta[3] or "") .. ".tga")
        tex:SetTexCoord(0, meta[1] / meta[2], 0, 1)
        local aspect = meta[1] / meta[2]
        tex:SetSize(THUMB * math.min(1, aspect), THUMB / math.max(1, aspect))
        return
    end
    local d = RM().TemplateDisplay(kind) or {}
    tex:SetVertexColor(1, 1, 1, 1)
    if (d.mode == "artwork" or d.mode == "artworkText") and RM().Art(d.art) then
        local file, l, r, t, b, aspect = RM().ArtTexture(d.art, THUMB)
        tex:SetTexture(file)
        tex:SetTexCoord(l, r, t, b)
        tex:SetSize(math.max(1, math.floor(THUMB * math.min(1, aspect) + 0.5)), math.floor(THUMB / math.max(1, aspect) + 0.5))
        return
    end
    tex:SetSize(THUMB, THUMB)
    if d.iconSource == "item" then
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    elseif R.Icons then
        R.Icons.Apply(tex, d.icon or "reminders", THUMB)
    end
end

function C.Say(text, tone)
    if not f then return end
    f.say:SetText(text or "")
    local G = Wg()
    G.Color(f.say, tone == "warn" and G.pal.danger.text or G.pal.textDim)
end

-- Used by the cards and the custom row. The page makes it; on success this goes away, on a refusal it stays and says why.
local function Use(kind)
    local P = R.RemindersPage
    if not P then return end
    local ok, why = P.Create(kind)
    if ok then C.Hide() else C.Say(why, "warn") end
end

local function Filter(resetScroll)
    local query = f.search:GetText():lower():match("^%s*(.-)%s*$")
    f.placeholder:SetShown(query == "" and not f.search:HasFocus())
    for _, tab in ipairs(f.tabs) do tab:SetSelected(tab.category == f.category) end
    local count = 0
    for _, card in ipairs(f.cards) do
        local show = f.category == "all" or f.category == card.category
        for term in query:gmatch("%S+") do
            if not card.searchText:find(term, 1, true) then show = false; break end
        end
        card:SetShown(show)
        if show then
            local col, row = count % 2, math.floor(count / 2)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", f.content, "TOPLEFT", col * (CARD_W + GAP), -row * (CARD_H + GAP))
            count = count + 1
        end
    end
    f.none:SetShown(count == 0)
    f.content:SetHeight(math.max(70, math.ceil(count / 2) * (CARD_H + GAP)))
    if f.fitRail then f.fitRail(f.content:GetHeight()) end
    if resetScroll then f.scroll:SetVerticalScroll(0) end
end

local function Build()
    local G, M = Wg(), R.SettingsMaterial
    f = CreateFrame("Frame", NAME, UIParent)
    f.companionHeight = 706
    f:SetSize(WIDTH, f.companionHeight)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    M.Companion(f)
    f:SetScript("OnHide", function()
        f.search:ClearFocus()
        if R.RemindersPage then R.RemindersPage.QueueRefresh() end
    end)

    f.title = M.ReminderFont(G.Text(f, "heading"), 23, true)
    f.title:SetPoint("TOPLEFT", PAD, -14)
    f.title:SetText("Create a reminder")
    f.sub = G.Text(f, "body")
    f.sub:SetPoint("TOPLEFT", PAD, -42)
    f.sub:SetText("Choose a template to make it yours.")
    local close = G.Button(f, "X", 26, "secondary", C.Hide)
    M.ReminderControl(close)
    close:SetPoint("TOPRIGHT", -12, -12)

    f.search = G.EditBox(f, WIDTH - PAD * 2, 27)
    f.search:SetPoint("TOPLEFT", PAD, -63)
    f.search:SetMaxLetters(80)
    M.ReminderControl(f.search, "field")
    f.placeholder = G.Text(f.search, "small")
    f.placeholder:SetPoint("LEFT", 8, 0)
    f.placeholder:SetText("Search templates…")
    f.category, f.tabs = "all", {}
    local tw = (WIDTH - PAD * 2 - GAP) / 3
    for i, filter in ipairs(FILTERS) do
        local category, label = filter[1], filter[2]
        local tab = M.Segment(f, label, tw, function() f.category = category; Filter(true) end)
        tab.category = category
        tab:SetPoint("TOPLEFT", PAD + (i - 1) * (tw + GAP / 2), -97)
        f.tabs[i] = tab
    end
    f.scroll, f.content = G.Scroll(f, LIST_W)
    f.fitRail = M.ScrollRail(f.scroll)
    f.scroll:SetPoint("TOPLEFT", PAD, -132)
    f.scroll:SetPoint("BOTTOMRIGHT", -(PAD + 22), 112)
    f.none = G.Text(f.content, "body")
    f.none:SetWidth(LIST_W - 20)
    f.none:SetPoint("TOPLEFT", 8, -12)
    f.none:SetText("No matching templates. Try another search or choose All.")

    f.cards = {}
    local ordered, seen = {}, {}
    for _, kind in ipairs(ORDER) do
        for _, t in ipairs(RM().TEMPLATES) do
            if t[1] == kind then ordered[#ordered + 1] = t; seen[kind] = true end
        end
    end
    for _, t in ipairs(RM().TEMPLATES) do
        if t[1] ~= "custom" and not seen[t[1]] then ordered[#ordered + 1] = t end
    end
    for _, t in ipairs(ordered) do
        local kind = t[1]
        local meta = TEMPLATE_META[kind] or { "equipment", "" }
        local card = CreateFrame("Frame", nil, f.content, "BackdropTemplate")
        card:SetSize(CARD_W, CARD_H)
        M.PanelFace(card, "card")
        card.kind, card.category = kind, meta[1]
        card.searchText = table.concat({ t[2], t[4] or "", meta[2] }, " "):lower()
        card.thumb = card:CreateTexture(nil, "ARTWORK")
        card.thumb:SetPoint("TOP", 0, -7)
        Picture(card.thumb, kind)
        card.name = M.ReminderFont(G.Text(card, "heading"), 15, true)
        card.name:SetPoint("TOPLEFT", 10, -105)
        card.name:SetWidth(CARD_W - 20)
        card.name:SetText(t[2])
        card.brief = G.Text(card, "body")
        card.brief:SetPoint("TOPLEFT", 10, -128)
        card.brief:SetWidth(CARD_W - 20)
        card.brief:SetText(t[4] or "")
        card.use = G.Button(card, "Use template", CARD_W - 20, "primary", function() Use(kind) end)
        card.use:SetPoint("BOTTOMLEFT", 10, 8)
        R.Interact.Tip(card.use, t[2], t[3] .. " It starts turned off.", "ANCHOR_LEFT")
        M.ReminderControl(card.use, "primary")
        local rim = M.Edge(card, "control", 9)
        rim:SetBackdropBorderColor(1, 0.8, 0.48, 0.9)
        rim:Hide()
        card.use:HookScript("OnEnter", function() rim:Show() end)
        card.use:HookScript("OnLeave", function() rim:Hide() end)
        card:HookScript("OnHide", function() rim:Hide() end)
        f.cards[#f.cards + 1] = card
    end
    f.custom = G.Button(f, "Custom reminder", WIDTH - PAD * 2, "secondary", function() Use("custom") end)
    f.custom:SetHeight(36)
    f.custom:SetPoint("BOTTOMLEFT", PAD, 65)
    f.customArt = f.custom:CreateTexture(nil, "OVERLAY")
    Picture(f.customArt, "custom")
    f.customArt:SetSize(23, 29)
    f.customArt:SetPoint("LEFT", 15, 0)
    R.Interact.Tip(f.custom, "Custom reminder", "Start with your own conditions and words. It starts turned off.")
    M.ReminderControl(f.custom)
    f.customNote = G.Text(f, "small")
    f.customNote:SetPoint("BOTTOM", 0, 44)
    f.customNote:SetText("Creates your own editable copy. Starts off.")
    f.say = G.Text(f, "small")
    f.say:SetPoint("BOTTOMLEFT", PAD, 12)
    f.say:SetWidth(WIDTH - PAD * 2)
    f.search:SetScript("OnTextChanged", function() Filter(true) end)
    f.search:HookScript("OnEditFocusGained", function() f.placeholder:Hide() end)
    f.search:HookScript("OnEditFocusLost", function() f.placeholder:SetShown(f.search:GetText() == "") end)
    Filter(true)
end

function C.Shown() return f ~= nil and f:IsShown() end
function C.Frame() return f end

-- Away, and the page draws the preview for the selection again (the companion place is the catalog's until then).
function C.Hide()
    if C.Shown() then f:Hide() end
end

-- Opens it beside the settings window (centered if that is not up), or puts it away.
function C.Toggle()
    if C.Shown() then C.Hide() return end
    local designer = R.RemindersDesigner
    if designer and designer.Shown() and designer.HasUnsaved() then
        designer.RequestClose(C.Toggle)
        return
    end
    if not f then Build() end
    C.Say("")
    f.category = "all"
    f.search:SetText("")
    Filter(true)
    if designer then designer.Close() end
    if R.RemindersPreview then R.RemindersPreview.Hide() end   -- the companion place holds one thing at a time
    if R.RemindersPreview then R.RemindersPreview.Place(f) end
    f:Show()
end

if R.OnSettingsClosed then R.OnSettingsClosed(C.Hide) end
