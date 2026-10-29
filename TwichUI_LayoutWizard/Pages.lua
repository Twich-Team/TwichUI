-- TwichUI Layout Setup: the six pages
-- Each page is built the first time it is shown and kept; showing it again only re-reads the model (Model.lua) and
-- re-writes its texts, so opening, going back and forth, and re-opening make nothing new. A page never decides anything:
-- it draws what the model says, and its buttons call the model (or the window's confirmed actions) and then ask the
-- window to draw again. Text blocks are one wrapped string per section, so a page's frame count does not depend on what
-- it says.
--
--   Pages.Build(key, parent, env) -> page { frame, Refresh() }
--   env: { Relayout(), Go(step), Actions = { reload, restore, undo, keepUpdate, keep, check, forget, again } }

local R = TwichUI
local LY = R.Layouts
local WZ = R.LayoutWizard
local M = WZ.Model
local Pages = {}
WZ.Pages = Pages

Pages.CONTENT_W = 718
Pages.DETAIL_ROWS = 5   -- settings shown at once in an update's details (the rest a page at a time)
local CONTENT_W = Pages.CONTENT_W
local LEFT_W, GAP = 372, 16
local RIGHT_X = LEFT_W + GAP

local function Look() return R.Look end
local function Pal() return R.Look.pal end

---------------------------------------------------------------------------
-- A column of items stacked top to bottom (the visible ones), and small pieces
---------------------------------------------------------------------------
local function Height(obj)
    local h
    if obj.GetStringHeight then h = obj:GetStringHeight() else h = obj:GetHeight() end
    return (type(h) == "number" and h > 0) and h or 14
end

local function NewColumn(frame, x, y)
    return { frame = frame, x = x or 0, y0 = y or 0, items = {} }
end

local function Put(col, obj, gap, indent)
    col.items[#col.items + 1] = { obj = obj, gap = gap or 8, indent = indent or 0 }
    return obj
end

-- Places the visible items; returns the column's height.
local function Flow(col)
    local y = col.y0
    for _, it in ipairs(col.items) do
        local o = it.obj
        if o:IsShown() then
            o:ClearAllPoints()
            o:SetPoint("TOPLEFT", col.frame, "TOPLEFT", col.x + it.indent, -(y + it.gap))
            y = y + it.gap + Height(o)
        end
    end
    return y
end

local function Text(parent, kind, width)
    local fs = Look().Text(parent, kind or "body")
    if width then fs:SetWidth(width) end
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    return fs
end

local function Heading(parent, text, width)
    local fs = Text(parent, "heading", width)
    fs:SetText(text)
    return fs
end

-- "- a" lines joined: one string per section
local function Bullets(list, prefix)
    local out = {}
    for _, l in ipairs(list or {}) do out[#out + 1] = (prefix or "- ") .. l end
    return table.concat(out, "\n")
end

-- A flat chip with a word in it (a status is never colour alone).
local TONE = { ok = "Ready", warn = "Check", block = "Blocked", info = "Note" }
local function Chip(parent)
    local L, pal = Look(), Pal()
    local chip = L.Tag(parent, "Ready")
    function chip:SetTone(tone)
        local fill, text = pal.ink, pal.stone
        local a = 0.30
        if tone == "ok" then fill, text, a = pal.tealLo, pal.tealHi, 0.9
        elseif tone == "warn" then fill, text, a = pal.bronzeText, pal.bronzeText, 0.22
        elseif tone == "block" then fill, text, a = pal.danger.bg, pal.danger.text, 1 end
        self.bg:SetColorTexture(fill[1], fill[2], fill[3], a)
        self.text:SetTextColor(text[1], text[2], text[3])
        self.text:SetText(TONE[tone] or TONE.info)
        self:SetWidth(math.max(44, self.text:GetStringWidth() + 12))
    end
    return chip
end
Pages.Chip = Chip

-- A selectable card: a title, a wrapped hint, "Selected" at the right when chosen, a bar along its foot.
local function Card(parent, width, onClick)
    local L, pal = Look(), Pal()
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetWidth(width)
    L.Panel(b)
    L.Hover(b, pal.text, 0.05)
    b.fill = L.Solid(b, "BACKGROUND", pal.bronzeText, 0.10)
    b.fill:SetPoint("TOPLEFT", 1, -1)
    b.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    b.fill:Hide()
    b.bar = L.Solid(b, "ARTWORK", pal.bronzeText, 1)
    b.bar:SetHeight(2)
    b.bar:SetPoint("BOTTOMLEFT", 1, 1)
    b.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    b.bar:Hide()
    b.title = Text(b, "body", width - 100)
    b.title:SetPoint("TOPLEFT", 12, -10)
    b.mark = L.Text(b, "meta")
    b.mark:SetPoint("TOPRIGHT", -10, -11)
    b.mark:SetText("Selected")
    b.mark:Hide()
    b.hint = Text(b, "small", width - 24)
    b.hint:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -4)
    b:SetScript("OnClick", onClick)
    function b:Fill(title, hint)
        self.title:SetText(title)
        self.hint:SetText(hint or "")
        self.hint:SetShown(hint ~= nil and hint ~= "")
        local h = 10 + Height(self.title) + (hint and hint ~= "" and (4 + Height(self.hint)) or 0) + 12
        self:SetHeight(h)
    end
    function b:SetSelected(v)
        self.fill:SetShown(v)
        self.bar:SetShown(v)
        self.mark:SetShown(v)
    end
    return b
end

local function Button(parent, label, w, kind, fn, tip)
    local b = Look().Button(parent, label, w, kind, fn)
    b:SetHeight(24)
    if tip then R.Interact.Tip(b, label, tip) end
    return b
end

-- The preview (steps 2 to 5), in the right-hand column, redrawn from the model each time the page is shown. Under it: the
-- scenario the sample shows (Solo, Target selected, ...) and the full-size preview. Neither changes anything in the game.
local function PreviewColumn(page, parent, y, env)
    local view = WZ.Preview.Build(parent, {
        scenario = function(id) M.SetScenario(id) env.Relayout() end,
        overlay = function() env.Overlay() end,
    })
    view.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", RIGHT_X, -(y or 24))
    page.preview = view
    function page.RefreshPreview()
        local scene = M.Scene()
        if not scene then
            view:Clear()
            view.caption:SetText("TwichUI couldn't read your screen's size, so there is nothing to draw.")
            view:Controls(M.Scenario(), M.OverlayBlock() or "Nothing to show.")
            return
        end
        local note = M.SceneNote()
        view.caption:SetText(WZ.Preview.CAPTION .. (note and (" " .. note) or ""))
        local accent, o = M.Accent()
        if not accent and o and o.id == "class" then accent = WZ.ClassColor and WZ.ClassColor() end
        local issues = M.SceneIssues(scene)
        view:Set(scene, accent, issues)
        view:Controls(M.Scenario(), M.OverlayBlock())
    end
end

---------------------------------------------------------------------------
-- 1. Welcome and compatibility
---------------------------------------------------------------------------
local function BuildWelcome(parent, env)
    local L = Look()
    local page = { frame = CreateFrame("Frame", nil, parent) }
    local f = page.frame
    f:SetSize(CONTENT_W, 10)

    local emblem = f:CreateTexture(nil, "ARTWORK")
    emblem:SetSize(96, 96)
    emblem:SetPoint("TOPLEFT", 0, -6)
    WZ.Art.Apply(emblem, "emblem")
    local head = L.Text(f, "title")
    head:SetPoint("TOPLEFT", 116, -10)
    head:SetText("Set up TwichUI's interface layout")
    local intro = Text(f, "body", CONTENT_W - 116)
    intro:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
    intro:SetText("This walks you through a complete interface: where chat, the damage meter, the minimap, the unit frames and the action bars sit, and how EllesmereUI and TwichUI look, worked out for your screen.")
    local safe = Text(f, "small", CONTENT_W - 116)
    safe:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -8)
    safe:SetText("Nothing changes until you press Apply on the Review step, and Restore puts your previous setup back afterwards. Nothing reloads by itself, and nothing here runs unless you open it.")
    page.safe = safe

    local fit = f:CreateTexture(nil, "ARTWORK")
    fit:SetSize(44, 44)
    WZ.Art.Apply(fit, "screenFit")
    local compatHead = Heading(f, "Does it work here?", CONTENT_W - 60)
    local compatNote = Text(f, "small", CONTENT_W - 60)
    compatNote:SetText("What this game client, your screen and the game's state allow. Each line says what it found; nothing is changed by looking.")
    page.rows = {}

    -- the package to set up from: shown only once someone has sent one (the included package is the only one before that)
    local pkgHead = Heading(f, "Layout package", CONTENT_W)
    local pkgNote = Text(f, "small", CONTENT_W - 60)
    page.srcCards = {}
    for i = 1, 1 + (LY and LY.Store and LY.Store.LIMITS.received or 3) do
        local card = Card(f, CONTENT_W - 30, function() end)
        card:Hide()
        page.srcCards[i] = card
    end
    local removeBtn = Button(f, "Remove this package", 170, "secondary", function() env.Actions.removePackage() end,
        "Deletes the stored copy of this package. An install already made from it, and Restore, are not touched. Ask the sender again if you want it back.")
    removeBtn:Hide()

    local function Row(i)
        local row = page.rows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, f)
        row:SetSize(CONTENT_W, 30)
        row.chip = Chip(row)
        row.chip:SetPoint("TOPLEFT", 0, -2)
        row.label = Text(row, "body", 150)
        row.label:SetPoint("TOPLEFT", 72, -2)
        row.detail = Text(row, "small", CONTENT_W - 72 - 160 - 90)
        row.detail:SetPoint("TOPLEFT", 232, -3)
        row.link = Button(row, "See it", 70, "secondary", function() end)
        row.link:SetPoint("TOPRIGHT", 0, -2)
        page.rows[i] = row
        return row
    end

    function page.Refresh()
        local items = M.Compat()
        for i, it in ipairs(items) do
            local row = Row(i)
            row.chip:SetTone(it.state)
            row.label:SetText(it.label)
            row.detail:SetText(it.detail)
            row.link:SetShown(it.go ~= nil)
            if it.go then row.link:SetScript("OnClick", function() env.Go(it.go) end) end
            row:SetHeight(math.max(26, Height(row.detail) + 6))
            row:Show()
        end
        for i = #items + 1, #page.rows do page.rows[i]:Hide() end
        local y = math.max(112, 10 + 24 + 8 + Height(intro) + 8 + Height(safe) + 22)
        local sources = M.Sources()
        local showSources = #sources > 1
        pkgHead:SetShown(showSources)
        pkgNote:SetShown(showSources)
        for i, card in ipairs(page.srcCards) do card:SetShown(showSources and sources[i] ~= nil) end
        removeBtn:Hide()
        if showSources then
            pkgHead:ClearAllPoints()
            pkgHead:SetPoint("TOPLEFT", 0, -y)
            pkgNote:ClearAllPoints()
            pkgNote:SetPoint("TOPLEFT", pkgHead, "BOTTOMLEFT", 0, -3)
            local loading, failed = M.Loading(), M.SourceError()
            pkgNote:SetText(loading and "Opening the package: unpacking it and checking it again, a little at a time..."
                or failed and "That package couldn't be opened. Choose another, or remove it."
                or "Layouts other players sent you are stored here. Choosing one only changes what this setup shows; nothing is applied until Review.")
            y = y + Height(pkgHead) + 3 + Height(pkgNote) + 8
            for i, src in ipairs(sources) do
                local card = page.srcCards[i]
                if card then
                    card:SetScript("OnClick", function()
                        M.SetSource(src.key, function() env.Relayout() end)
                        env.Relayout()
                    end)
                    local hint = src.kind == "bundled" and ("Included with TwichUI, revision %d."):format(src.revision or 0)
                        or ("Revision %d, %s."):format(src.revision or 0, src.sender and ("sent by " .. src.sender) or "sent to you")
                    card:Fill(src.title .. (src.kind == "bundled" and " (included)" or ""), hint)
                    card:SetSelected(M.Source() == src.key or M.Loading() == src.key)
                    card:ClearAllPoints()
                    card:SetPoint("TOPLEFT", 0, -y)
                    y = y + card:GetHeight() + 6
                end
            end
            if M.Package() then
                removeBtn:ClearAllPoints()
                removeBtn:SetPoint("TOPLEFT", 0, -y)
                removeBtn:Show()
                y = y + 30
            end
            y = y + 10
        end
        fit:ClearAllPoints()
        fit:SetPoint("TOPLEFT", 0, -y)
        compatHead:ClearAllPoints()
        compatHead:SetPoint("TOPLEFT", 56, -y)
        compatNote:ClearAllPoints()
        compatNote:SetPoint("TOPLEFT", compatHead, "BOTTOMLEFT", 0, -3)
        y = y + 56
        for i = 1, #items do
            local row = page.rows[i]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            y = y + row:GetHeight() + 4
        end
        f:SetHeight(y + 8)
        return y + 8
    end
    return page
end

---------------------------------------------------------------------------
-- 2. Layout: Classic or Compact Adventure. Choosing re-draws the preview at once and changes nothing else.
---------------------------------------------------------------------------
local function BuildLayout(parent, env)
    local page = { frame = CreateFrame("Frame", nil, parent), cards = {} }
    local f = page.frame
    f:SetSize(CONTENT_W, 10)
    local col = NewColumn(f)
    Put(col, Heading(f, "Choose a layout", LEFT_W), 4)
    local sub = Put(col, Text(f, "small", LEFT_W), 4)
    sub:SetText("Pick one; the preview changes at once, to scale, for your screen. Nothing is applied until the Review step, and you can switch layouts later.")
    PreviewColumn(page, f, 24, env)

    local function LayoutCard(i)
        local card = page.cards[i]
        if card then return card end
        card = Card(f, LEFT_W, function() end)
        card.pic = card:CreateTexture(nil, "ARTWORK")
        card.pic:SetSize(160, 80)
        card.name = Text(card, "title", LEFT_W - 190)
        card.tag = Chip(card)
        card.covers = Text(card, "small", LEFT_W - 24)
        card.title:Hide()
        page.cards[i] = card
        Put(col, card, 10)
        return card
    end

    function page.Refresh()
        local current = M.Layout()
        for i, layout in ipairs(M.LayoutList()) do
            local card = LayoutCard(i)
            local selected = layout.id == current.id
            card:SetScript("OnClick", function()
                M.SetLayout(layout.id)
                env.Relayout()
            end)
            card.hasPic = WZ.Art.Apply(card.pic, layout.art)
            card.name:SetText(layout.title)
            card.tag:SetTone("warn")
            card.tag.text:SetText("Preview build")
            card.tag:SetWidth(math.max(44, card.tag.text:GetStringWidth() + 12))
            card.tag:SetShown(layout.dev)
            card.hint:SetText(layout.blurb)
            card.hint:Show()
            card.covers:SetText(Bullets(layout.covers))
            card.covers:SetShown(selected)
            card:SetSelected(selected)
            card.pic:ClearAllPoints()
            card.name:ClearAllPoints()
            card.tag:ClearAllPoints()
            card.hint:ClearAllPoints()
            card.covers:ClearAllPoints()
            local top = 12
            if card.hasPic then
                card.pic:SetPoint("TOPLEFT", 12, -top)
                card.name:SetPoint("TOPLEFT", 12 + 160 + 14, -top - 2)
                card.tag:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -8)
                top = top + 80 + 10
            else
                card.name:SetPoint("TOPLEFT", 12, -top)
                card.tag:SetPoint("LEFT", card.name, "RIGHT", 10, 0)
                top = top + Height(card.name) + 8
            end
            card.hint:SetWidth(LEFT_W - 24)
            card.hint:SetPoint("TOPLEFT", 12, -top)
            card.covers:SetPoint("TOPLEFT", card.hint, "BOTTOMLEFT", 0, -8)
            card:SetHeight(top + Height(card.hint) + 8 + (selected and (Height(card.covers) + 6) or 0) + 12)
            card:Show()
        end
        local y = Flow(col)
        page.RefreshPreview()
        f:SetHeight(math.max(y, 260) + 8)
        return f:GetHeight()
    end
    return page
end

---------------------------------------------------------------------------
-- A page that asks one choice: its cards (3. Helpers)
---------------------------------------------------------------------------
local function BuildHelpers(parent, env)
    local page = { frame = CreateFrame("Frame", nil, parent), cards = {} }
    local f = page.frame
    f:SetSize(CONTENT_W, 10)
    local col = NewColumn(f)
    Put(col, Heading(f, "Choose TwichUI's helpers", LEFT_W), 4)
    local sub = Put(col, Text(f, "small", LEFT_W), 4)
    local note = Text(f, "small", LEFT_W)
    note:SetText("These only turn features on, never off, and you can change any of them later in TwichUI's settings. Features that share, play sounds or act for you are never part of this.")
    PreviewColumn(page, f, 24, env)

    local none = Text(f, "body", LEFT_W)
    none:SetText("This package doesn't ask which of TwichUI's helpers to turn on. Nothing is chosen here; go on to the next step.")
    none:SetPoint("TOPLEFT", 0, -60)

    function page.Refresh()
        local ch = M.Choice("helpers")
        if not ch then
            -- a package from another player may ask nothing here
            sub:Hide()
            note:Hide()
            none:Show()
            for _, card in ipairs(page.cards) do card:Hide() end
            page.RefreshPreview()
            f:SetHeight(260)
            return 260
        end
        none:Hide()
        sub:Show()
        note:Show()
        sub:SetText(ch.hint)
        for i, o in ipairs(ch.options) do
            local card = page.cards[i]
            if not card then
                card = Card(f, LEFT_W, function() end)
                page.cards[i] = card
                Put(col, card, 8)
            end
            card:SetScript("OnClick", function()
                M.SetPick("helpers", o.id)
                env.Relayout()
            end)
            card:Fill(o.label, o.hint)
            card:SetSelected(M.Pick("helpers") == o.id)
            card:Show()
        end
        for i = #ch.options + 1, #page.cards do page.cards[i]:Hide() end
        if not page.noteAdded then page.noteAdded = true Put(col, note, 12) end
        sub:Show()
        local y = Flow(col)
        page.RefreshPreview()
        f:SetHeight(math.max(y, 260) + 8)
        return f:GetHeight()
    end
    return page
end

---------------------------------------------------------------------------
-- 4. Personalize
---------------------------------------------------------------------------
local function ClassColor()
    local class = UnitClass and select(2, UnitClass("player"))
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return { c.r, c.g, c.b } end
    return { 0.62, 0.60, 0.56 }
end
WZ.ClassColor = ClassColor

local function BuildPersonalize(parent, env)
    local L, pal = Look(), Pal()
    local page = { frame = CreateFrame("Frame", nil, parent), swatches = {}, sizes = {}, groups = {} }
    local f = page.frame
    f:SetSize(CONTENT_W, 10)
    local art = f:CreateTexture(nil, "ARTWORK")
    art:SetSize(52, 52)
    art:SetPoint("TOPLEFT", 0, -4)
    WZ.Art.Apply(art, "personalize")
    local head = Heading(f, "Make it yours", LEFT_W - 64)
    head:SetPoint("TOPLEFT", 64, -8)
    local sub = Text(f, "small", LEFT_W - 64)
    sub:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -3)
    sub:SetText("Each choice changes the preview at once and nothing else until you apply.")

    local accentHead = Heading(f, "", LEFT_W)
    local accentName = Text(f, "body", LEFT_W)
    local accentHint = Text(f, "small", LEFT_W)
    local sizeHead = Heading(f, "", LEFT_W)
    local sizeHint = Text(f, "small", LEFT_W)
    local reset = Button(f, "Start over", 100, "secondary", function() M.ResetPicks() env.Relayout() end,
        "Puts every choice back to the layout's own, here and on the Helpers step. Nothing in the game changes.")
    PreviewColumn(page, f, 24, env)

    -- Two more groups of two cards (tooltip placement, friendly player nameplates): each made once, then only re-written.
    local SAMPLE_PLATES = { { "Sample warrior", "WARRIOR", { 0.78, 0.61, 0.43 } }, { "Sample priest", "PRIEST", { 1, 1, 1 } },
        { "Sample mage", "MAGE", { 0.25, 0.78, 0.92 } } }
    local BLUE = { 0.667, 0.667, 1 }
    local function Group(id)
        local g = page.groups[id]
        if g then return g end
        g = { head = Heading(f, "", LEFT_W), hint = Text(f, "small", LEFT_W), note = Text(f, "small", LEFT_W), cards = {} }
        if id == "friendly-plates" then
            g.sample, g.caption = {}, Text(f, "small", LEFT_W)
            for i = 1, #SAMPLE_PLATES do
                local row = { bar = f:CreateTexture(nil, "ARTWORK"), name = L.Text(f, "small") }
                row.bar:SetSize(70, 7)
                g.sample[i] = row
            end
        end
        page.groups[id] = g
        return g
    end
    local function HideGroup(g)
        g.head:Hide() g.hint:Hide() g.note:Hide()
        for _, c in ipairs(g.cards) do c:Hide() end
        for _, r in ipairs(g.sample or {}) do r.bar:Hide() r.name:Hide() end
        if g.caption then g.caption:Hide() end
    end
    local function DrawGroup(id, y)
        local ch = M.Choice(id)
        local g = Group(id)
        if not ch then HideGroup(g) return y end
        g.head:Show()
        g.hint:Show()
        g.head:SetText(ch.label)
        g.head:ClearAllPoints()
        g.head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        g.hint:SetText(ch.hint or "")
        g.hint:ClearAllPoints()
        g.hint:SetPoint("TOPLEFT", g.head, "BOTTOMLEFT", 0, -3)
        y = y + Height(g.head) + 3 + Height(g.hint) + 8
        for i, o in ipairs(ch.options) do
            local card = g.cards[i]
            if not card then card = Card(f, (LEFT_W - 8) / 2, function() end) g.cards[i] = card end
            card:SetScript("OnClick", function() M.SetPick(id, o.id) env.Relayout() end)
            card:Fill(o.label, o.hint)
            card:SetSelected(M.Pick(id) == o.id)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * ((LEFT_W - 8) / 2 + 8), -y)
            card:Show()
        end
        for i = #ch.options + 1, #g.cards do g.cards[i]:Hide() end
        local h = 0
        for i = 1, #ch.options do h = math.max(h, g.cards[i]:GetHeight()) end
        for i = 1, #ch.options do g.cards[i]:SetHeight(h) end
        y = y + h + 6
        local derived = M.Derived(id)
        g.note:SetText(derived and "Shown as your game has it now. Pick one to choose for yourself." or "")
        g.note:SetShown(derived)
        g.note:ClearAllPoints()
        g.note:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        if derived then y = y + Height(g.note) + 4 end
        if g.sample then
            -- synthetic friendly players (never a real nameplate). Class colors is EllesmereUI's own plate (names only in a name-only
            -- layout); Standard blue is Blizzard's plate, which EllesmereUI no longer manages: drawn as a plain blue bar, since how it
            -- looks is Blizzard's setting.
            local mode = M.PlatesMode() or { nameOnly = false }
            local blue = M.Pick(id) == "blue"
            for i, sp in ipairs(SAMPLE_PLATES) do
                local row = g.sample[i]
                local class = RAID_CLASS_COLORS and RAID_CLASS_COLORS[sp[2]]
                local cc = class and { class.r, class.g, class.b } or sp[3]
                row.name:SetText(sp[1])
                row.bar:ClearAllPoints()
                row.name:ClearAllPoints()
                if mode.nameOnly and not blue then
                    row.name:SetTextColor(cc[1], cc[2], cc[3])
                    row.bar:Hide()
                    row.name:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * 120, -y)
                else
                    local col = blue and BLUE or cc
                    row.bar:SetColorTexture(col[1], col[2], col[3], 1)
                    row.bar:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * 120, -y)
                    row.bar:Show()
                    row.name:SetTextColor(1, 1, 1)
                    row.name:SetPoint("TOPLEFT", row.bar, "BOTTOMLEFT", 0, -2)
                end
                row.name:Show()
            end
            y = y + ((mode.nameOnly and not blue) and 16 or 26)
            local cap = "A sample, not your nameplates."
            if blue then
                cap = cap .. " EllesmereUI stops managing friendly player nameplates and Blizzard's draw them, by Blizzard's own settings (Esc > Options > Nameplates); what EllesmereUI last set for them stays until you change it there."
            end
            g.caption:SetText(cap)
            g.caption:ClearAllPoints()
            g.caption:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
            g.caption:Show()
            y = y + Height(g.caption) + 4
        end
        return y + 12
    end

    local none = Text(f, "body", LEFT_W)
    none:SetText("This package doesn't ask for an accent colour or a size. Nothing is chosen here; go on to the review.")
    none:SetPoint("TOPLEFT", 0, -90)

    function page.Refresh()
        local accent, size = M.Choice("accent"), M.Choice("size")
        local shown = accent ~= nil and size ~= nil
        for _, w in ipairs({ accentHead, accentName, accentHint, sizeHead, sizeHint, reset, sub }) do w:SetShown(shown) end
        none:SetShown(not shown)
        if not shown then
            -- a package from another player may offer neither
            for _, sw in ipairs(page.swatches) do sw:Hide() end
            for _, c in ipairs(page.sizes) do c:Hide() end
            for _, g in pairs(page.groups) do HideGroup(g) end
            page.RefreshPreview()
            f:SetHeight(260)
            return 260
        end
        accentHead:SetText(accent.label)
        accentHead:ClearAllPoints()
        accentHead:SetPoint("TOPLEFT", 0, -82)
        accentHint:SetText(accent.hint)
        accentHint:ClearAllPoints()
        accentHint:SetPoint("TOPLEFT", accentHead, "BOTTOMLEFT", 0, -3)
        local y = 82 + Height(accentHead) + 3 + Height(accentHint) + 10
        local x = 0
        for i, o in ipairs(accent.options) do
            local sw = page.swatches[i]
            if not sw then
                sw = CreateFrame("Button", nil, f, "BackdropTemplate")
                sw:SetSize(36, 36)
                L.Surface(sw, pal.well, 1, pal.control, 1)
                sw.fill = L.Solid(sw, "ARTWORK", pal.stone, 1)
                sw.fill:SetPoint("TOPLEFT", 4, -4)
                sw.fill:SetPoint("BOTTOMRIGHT", -4, 4)
                sw.under = L.Solid(sw, "OVERLAY", pal.bronzeText, 1)
                sw.under:SetHeight(3)
                sw.under:SetPoint("TOPLEFT", sw, "BOTTOMLEFT", 0, -3)
                sw.under:SetPoint("TOPRIGHT", sw, "BOTTOMRIGHT", 0, -3)
                L.Hover(sw, pal.text, 0.12, 4)
                page.swatches[i] = sw
            end
            local col = o.swatch or (o.id == "class" and ClassColor()) or pal.stone
            sw.fill:SetColorTexture(col[1], col[2], col[3], 1)
            sw:ClearAllPoints()
            sw:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
            x = x + 44
            local chosen = M.Pick("accent") == o.id
            sw.under:SetShown(chosen)
            local edge = chosen and pal.text or pal.control
            sw:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
            sw:SetScript("OnClick", function() M.SetPick("accent", o.id) env.Relayout() end)
            R.Interact.Tip(sw, o.label, o.hint or (o.id == "class" and "Follows the character you play." or nil))
            sw:Show()
        end
        for i = #accent.options + 1, #page.swatches do page.swatches[i]:Hide() end
        y = y + 36 + 8
        local o = M.PickedOption("accent")
        accentName:SetText(o and ("Chosen: " .. o.label) or "")
        accentName:ClearAllPoints()
        accentName:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        y = y + Height(accentName) + 18

        sizeHead:SetText(size.label)
        sizeHead:ClearAllPoints()
        sizeHead:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        sizeHint:SetText(size.hint)
        sizeHint:ClearAllPoints()
        sizeHint:SetPoint("TOPLEFT", sizeHead, "BOTTOMLEFT", 0, -3)
        y = y + Height(sizeHead) + 3 + Height(sizeHint) + 8
        for i, so in ipairs(size.options) do
            local card = page.sizes[i]
            if not card then card = Card(f, (LEFT_W - 8) / 2, function() end) page.sizes[i] = card end
            card:SetScript("OnClick", function() M.SetPick("size", so.id) env.Relayout() end)
            card:Fill(so.label, so.hint)
            card:SetSelected(M.Pick("size") == so.id)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * ((LEFT_W - 8) / 2 + 8), -y)
            card:Show()
        end
        local h = 0
        for _, c in ipairs(page.sizes) do h = math.max(h, c:GetHeight()) end
        for _, c in ipairs(page.sizes) do c:SetHeight(h) end
        y = y + h + 18
        y = DrawGroup("tooltip", y)
        y = DrawGroup("friendly-plates", y)
        y = y + 2
        reset:ClearAllPoints()
        reset:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        reset:SetEnabled(not M.IsDefault())
        y = y + 24
        page.RefreshPreview()
        f:SetHeight(math.max(y, 260) + 8)
        return f:GetHeight()
    end
    return page
end

---------------------------------------------------------------------------
-- 5. Review
---------------------------------------------------------------------------
local function BuildReview(parent, env)
    local pal = Pal()
    local page = { frame = CreateFrame("Frame", nil, parent) }
    local f = page.frame
    f:SetSize(CONTENT_W, 10)
    local col = NewColumn(f)
    Put(col, Heading(f, "Review before you apply", LEFT_W), 4)
    local lead = Put(col, Text(f, "small", LEFT_W), 4)
    lead:SetText("This is exactly what Apply will do on this screen. Nothing has changed yet.")
    local switching = Put(col, Text(f, "small", LEFT_W), 6)
    local blocked = Put(col, Text(f, "body", LEFT_W), 8)
    blocked:SetTextColor(pal.danger.text[1], pal.danger.text[2], pal.danger.text[3])
    local fitWarn = Put(col, Text(f, "small", LEFT_W), 8)
    fitWarn:SetTextColor(pal.danger.text[1], pal.danger.text[2], pal.danger.text[3])
    Put(col, Heading(f, "Your choices", LEFT_W), 10)
    local picks = Put(col, Text(f, "small", LEFT_W), 3)
    -- Updating an installed layout (updates.md): three ways, then the details behind a button. Every frame here is made once,
    -- with the page; the details show one page of DETAIL_ROWS settings at a time.
    local up = { head = Put(col, Heading(f, "Updating your layout", LEFT_W), 10) }
    up.body = Put(col, Text(f, "small", LEFT_W), 3)
    up.modes = {}
    for i, m in ipairs({
        { "keep", "Update while keeping my customizations", "Settings you changed since the last install stay as you have them; everything else takes the update." },
        { "recommended", "Reapply the recommended configuration", "Every setting the layout manages takes its value again. Settings you made yours stay yours." },
        { "review", "Review conflicts", "Keeps your changes, and lists each setting so you can choose: keep yours, use the layout's, or make it yours for good." },
    }) do
        local card = Card(f, LEFT_W, function() M.SetUpdateMode(m[1]) env.Relayout() end)
        card:Fill(m[2], m[3])
        up.modes[i] = { card = card, id = m[1] }
        Put(col, card, i == 1 and 8 or 4)
    end
    up.whole = Put(col, Text(f, "small", LEFT_W), 8)
    up.wholeBar = Put(col, CreateFrame("Frame", nil, f), 4)
    up.wholeBar:SetSize(LEFT_W, 24)
    up.wholeKeep = Button(up.wholeBar, "Keep mine as it is", 170, "secondary", function() if up.wholeId then M.SetWhole(up.wholeId, "keep") env.Relayout() end end,
        "This update leaves that addon exactly as it is. Its parts of the layout don't change.")
    up.wholeKeep:SetPoint("TOPLEFT", 0, 0)
    up.wholeReplace = Button(up.wholeBar, "Replace with the layout's", 190, "secondary", function() if up.wholeId then M.SetWhole(up.wholeId, "replace") env.Relayout() end end,
        "Takes the layout's version whole. Your current profile is kept, so Undo this update can put it back.")
    up.wholeReplace:SetPoint("LEFT", up.wholeKeep, "RIGHT", 8, 0)
    up.group = Put(col, Text(f, "small", LEFT_W), 8)
    up.groupBar = Put(col, CreateFrame("Frame", nil, f), 4)
    up.groupBar:SetSize(LEFT_W, 24)
    up.groupMine = Button(up.groupBar, "Keep mine (all)", 150, "secondary", function() if up.groupId then M.ChooseGroup(up.groupId, "mine") env.Relayout() end end,
        "Keeps the layout links and every frame linked by them as you have them.")
    up.groupMine:SetPoint("TOPLEFT", 0, 0)
    up.groupPkg = Button(up.groupBar, "Use the layout's (all)", 170, "secondary", function() if up.groupId then M.ChooseGroup(up.groupId, "package") env.Relayout() end end,
        "Takes the layout's links and the frames linked by them, all together.")
    up.groupPkg:SetPoint("LEFT", up.groupMine, "RIGHT", 8, 0)
    up.warn = Put(col, Text(f, "small", LEFT_W), 8)
    up.warn:SetTextColor(pal.bronzeText[1], pal.bronzeText[2], pal.bronzeText[3])
    up.toggle = Put(col, Button(f, "Show each setting", 170, "secondary", function()
        M.ShowDetails(M.UpdateMode() ~= "review" and not (M.Session() and M.Session().update and M.Session().update.details))
        env.Relayout()
    end, "Lists every setting this update changes or keeps, with your value, the layout's, and what each choice means."), 8)
    up.rows = {}
    for i = 1, Pages.DETAIL_ROWS do
        local r = { text = Put(col, Text(f, "small", LEFT_W), i == 1 and 8 or 10) }
        r.bar = Put(col, CreateFrame("Frame", nil, f), 3)
        r.bar:SetSize(LEFT_W, 24)
        r.buttons = {}
        for k = 1, 3 do
            local b = Button(r.bar, "", 118, "secondary", function()
                local d = r.row and r.choices[k]
                if d then M.Choose(r.row.unit, d) env.Relayout() end
            end)
            b:SetPoint("TOPLEFT", (k - 1) * 124, 0)
            r.buttons[k] = b
        end
        r.choices = {}
        up.rows[i] = r
    end
    up.pager = Put(col, CreateFrame("Frame", nil, f), 8)
    up.pager:SetSize(LEFT_W, 24)
    up.prev = Button(up.pager, "Previous", 90, "secondary", function() M.SetDetailPage((M.Session().update.page or 1) - 1) env.Relayout() end)
    up.prev:SetPoint("TOPLEFT", 0, 0)
    up.next = Button(up.pager, "More", 90, "secondary", function() M.SetDetailPage((M.Session().update.page or 1) + 1) env.Relayout() end)
    up.next:SetPoint("LEFT", up.prev, "RIGHT", 8, 0)
    up.pageText = Look().Text(up.pager, "meta")
    up.pageText:SetPoint("LEFT", up.next, "RIGHT", 10, 0)
    page.update = up

    local tHead = Put(col, Heading(f, "", LEFT_W), 10)
    local tBody = Put(col, Text(f, "small", LEFT_W), 3)
    local eHead = Put(col, Heading(f, "", LEFT_W), 10)
    local eBody = Put(col, Text(f, "small", LEFT_W), 3)
    Put(col, Heading(f, "Left alone", LEFT_W), 10)
    local keep = Put(col, Text(f, "small", LEFT_W), 3)
    local notesHead = Put(col, Heading(f, "Not placed", LEFT_W), 10)
    local notes = Put(col, Text(f, "small", LEFT_W), 3)
    Put(col, Heading(f, "If something goes wrong", LEFT_W), 10)
    local fail = Put(col, Text(f, "small", LEFT_W), 3)
    fail:SetText("If a step fails part way, TwichUI tells you what changed and what was put back, and Restore (on the Result step) puts your previous profiles back. Nothing is undone behind your back.")
    PreviewColumn(page, f, 24, env)
    page.tHead, page.eHead = tHead, eHead

    -- The update block: shown only for an install again. Values the player can't see in the game are never shown as text.
    local DECIDES = { mine = "keep", package = "apply", own = "owned", manage = "apply" }
    function page.RefreshUpdate(u)
        local shown = u ~= nil
        for _, k in ipairs({ "head", "body", "whole", "wholeBar", "group", "groupBar", "warn", "toggle", "pager" }) do up[k]:SetShown(shown) end
        for _, m in ipairs(up.modes) do m.card:SetShown(shown) end
        for _, row in ipairs(up.rows) do row.text:SetShown(false) row.bar:SetShown(false) end
        if not u then return end
        up.body:SetText(Bullets(u.summary) .. (#u.notes > 0 and ("\n" .. Bullets(u.notes)) or ""))
        for _, m in ipairs(up.modes) do m.card:SetSelected(m.id == u.mode) end
        local w = u.whole[1]
        up.wholeId = w and w.adapter or nil
        up.whole:SetText(w and w.text or "")
        up.whole:SetShown(w ~= nil)
        up.wholeBar:SetShown(w ~= nil)
        if w then
            up.wholeKeep:SetEnabled(w.choice ~= "keep")
            up.wholeReplace:SetEnabled(w.choice ~= "replace")
        end
        local g = u.groups[1]
        up.groupId = g and g.id or nil
        up.group:SetText(g and g.text or "")
        up.group:SetShown(g ~= nil)
        up.groupBar:SetShown(g ~= nil)
        if g then
            up.groupMine:SetEnabled(g.choice ~= "mine")
            -- a group holding a setting the player made theirs can't take the layout's (the text says how to hand it back)
            up.groupPkg:SetEnabled(g.choice ~= "package" and not g.owned)
        end
        up.warn:SetText(Bullets(u.warnings))
        up.warn:SetShown(#u.warnings > 0)
        local open = u.details or u.mode == "review"
        up.toggle.text:SetText(open and "Hide the settings" or ("Show each setting (" .. #u.rows .. ")"))
        up.toggle:SetShown(#u.rows > 0 and u.mode ~= "review")
        local per = Pages.DETAIL_ROWS
        local pages = math.max(1, math.ceil(#u.rows / per))
        local pg = math.min(math.max(1, u.page or 1), pages)
        for i, slot in ipairs(up.rows) do
            local row = open and u.rows[(pg - 1) * per + i] or nil
            slot.row = row
            if row then
                local values = row.current and ("Yours: " .. row.current .. ". The layout's: " .. row.recommended .. ".") or ""
                slot.text:SetText(("%s (%s)\n%s%s %s"):format(row.label, row.caseText, values ~= "" and (values .. "\n") or "", row.effect, row.owner))
                slot.text:Show()
                local any = false
                for k, b in ipairs(slot.buttons) do
                    local o = row.offers[k]
                    slot.choices[k] = o and o.choice or nil
                    b:SetShown(o ~= nil)
                    if o then
                        b.text:SetText(o.label)
                        b:SetEnabled(DECIDES[o.choice] ~= row.decision)
                        any = true
                    end
                end
                slot.bar:SetShown(any)
            end
        end
        up.pager:SetShown(open and pages > 1)
        up.prev:SetEnabled(pg > 1)
        up.next:SetEnabled(pg < pages)
        up.pageText:SetText(("%d of %d"):format(pg, pages))
    end

    function page.Refresh()
        local r = M.Review()
        switching:SetText(r.switching or "")
        switching:SetShown(r.switching ~= nil)
        if r.problems then
            blocked:SetText("The layout package can't be used. TwichUI Diagnostics has the details.")
            blocked:Show()
        elseif #r.blocked > 0 then
            blocked:SetText("Can't apply yet:\n" .. Bullets(r.blocked))
            blocked:Show()
        else
            blocked:SetText("")
            blocked:Hide()
        end
        -- the fit of what Apply leaves: the boxes, then the pieces (sample sizes), what is only illustrative, what is kept as yours
        local fl = {}
        if r.fit and not r.fit.fits then
            fl[#fl + 1] = "Doesn't fit this screen: " .. table.concat(r.fit.lines, " ") .. " You can still apply it; the pieces are placed as shown."
            if r.fit.scale then fl[#fl + 1] = r.fit.scale end
        elseif r.fit and not r.fit.clear and #r.fit.pieces > 0 then
            fl[#fl + 1] = "Fits, but some pieces may overlap (worked out with sample sizes): " .. table.concat(r.fit.pieces, " ")
        end
        if r.fit and r.fit.retained then fl[#fl + 1] = r.fit.retained end
        if r.fit and r.fit.illustrative and #fl > 0 then fl[#fl + 1] = r.fit.illustrative end
        fitWarn:SetText(table.concat(fl, "\n"))
        fitWarn:SetShown(#fl > 0)
        local lines = {}
        for _, p in ipairs(r.picks or {}) do lines[#lines + 1] = p.choice .. ": " .. p.option end
        picks:SetText(Bullets(lines))
        page.RefreshUpdate(r.update)
        for _, pair in ipairs({ { r.twichui, tHead, tBody }, { r.ellesmereui, eHead, eBody } }) do
            local sec, h, b = pair[1], pair[2], pair[3]
            if sec then
                h:SetText(sec.title .. ": " .. sec.when:lower())
                b:SetText(Bullets(sec.lines))
            end
            h:SetShown(sec ~= nil)
            b:SetShown(sec ~= nil)
        end
        keep:SetText(Bullets(r.preserved))
        notes:SetText(Bullets(r.notes))
        notesHead:SetShown(#r.notes > 0)
        notes:SetShown(#r.notes > 0)
        local y = Flow(col)
        page.RefreshPreview()
        f:SetHeight(math.max(y, 260) + 8)
        return f:GetHeight()
    end
    return page
end

---------------------------------------------------------------------------
-- 6. Result
---------------------------------------------------------------------------
local function BuildResult(parent, env)
    local L = Look()
    local page = { frame = CreateFrame("Frame", nil, parent) }
    local f = page.frame
    f:SetSize(CONTENT_W, 10)
    local col = NewColumn(f)
    local chip = Chip(f)
    chip:SetPoint("TOPLEFT", 0, -10)
    local title = L.Text(f, "title")
    title:SetPoint("LEFT", chip, "RIGHT", 10, 0)
    local lines = Put(col, Text(f, "body", CONTENT_W), 40)
    local picksHead = Put(col, Heading(f, "What was chosen", CONTENT_W), 12)
    local picks = Put(col, Text(f, "small", CONTENT_W), 3)
    local stepsHead = Put(col, Heading(f, "What happened", CONTENT_W), 12)
    local steps = Put(col, Text(f, "small", CONTENT_W), 3)
    local diffHead = Put(col, Heading(f, "What doesn't read back as planned", CONTENT_W), 12)
    local diffs = Put(col, Text(f, "small", CONTENT_W), 3)
    local combat = Put(col, Text(f, "small", CONTENT_W), 10)
    local A = env.Actions
    local buttons = {
        reload = Button(f, "Reload now", 120, "primary", function() A.reload() end,
            "Reloads the game's interface now, which finishes EllesmereUI's part. After it, TwichUI reads every value back and shows this page. It only happens when you press this."),
        check = Button(f, "Check again", 110, "secondary", function() A.check() end,
            "Reads every managed value back now. It changes and repairs nothing."),
        again = Button(f, "Set up again", 110, "secondary", function() A.again() end,
            "Goes back to the first step. Nothing changes until you apply."),
        keep = Button(f, "Keep this setup", 130, "secondary", function() A.keep() end,
            "Finishes the setup: the restore point is forgotten (Restore is no longer offered), and TwichUI keeps managing the layout so a later update keeps your changes."),
        stop = Button(f, "Stop managing", 130, "secondary", function() A.stop() end,
            "Forgets which layout is installed and what the last install left. Nothing installed changes."),
        keepUpdate = Button(f, "Keep the update", 140, "secondary", function() A.keepUpdate() end,
            "Keeps this update for good: the copy of your setup from just before it is removed, and Undo this update is no longer offered. Restore isn't affected."),
        undo = Button(f, "Undo this update", 150, "danger", function() A.undo() end,
            "Puts back how things were just before this update (not before your first install: that is Restore). It shows exactly what it will do and asks first."),
        restore = Button(f, "Restore previous setup", 170, "danger", function() A.restore() end,
            "Puts your previous profiles back and removes the install's own. It shows exactly what it will do and asks first."),
        forget = Button(f, "Forget the record", 140, "danger", function() A.forget() end,
            "Forgets a record that can't be read. Nothing else is changed."),
    }
    local ORDER = { "reload", "check", "again", "keep", "keepUpdate", "undo", "restore", "stop", "forget" }
    page.buttons = buttons

    function page.Refresh()
        local r = M.Result()
        chip:SetTone(r.tone or "info")
        title:SetText(r.title or "")
        lines:SetText(table.concat(r.lines, "\n\n"))
        local p = {}
        for _, x in ipairs(r.picks) do p[#p + 1] = x.choice .. ": " .. x.option end
        picks:SetText(Bullets(p))
        picksHead:SetShown(#p > 0)
        picks:SetShown(#p > 0)
        steps:SetText(Bullets(r.steps))
        stepsHead:SetShown(#r.steps > 0)
        steps:SetShown(#r.steps > 0)
        diffs:SetText(Bullets(r.diffs))
        diffHead:SetShown(#r.diffs > 0)
        diffs:SetShown(#r.diffs > 0)
        combat:SetText(r.combat or "")
        combat:SetShown(r.combat ~= nil)
        local y = Flow(col)
        local x = 0
        y = y + 16
        for _, key in ipairs(ORDER) do
            local b = buttons[key]
            local show = r.can[key] == true or (key == "reload" and r.state == "applied" and r.can.reload == false)
            b:SetShown(show)
            if show then
                b:SetEnabled(r.can[key] == true)
                b:ClearAllPoints()
                if x > 0 and x + b:GetWidth() > CONTENT_W then x, y = 0, y + 32 end   -- a second row rather than past the edge
                b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
                x = x + b:GetWidth() + 8
            end
        end
        f:SetHeight(y + 40)
        page.result = r
        return f:GetHeight()
    end
    return page
end

local BUILDERS = { BuildWelcome, BuildLayout, BuildHelpers, BuildPersonalize, BuildReview, BuildResult }

function Pages.Build(step, parent, env)
    return BUILDERS[step](parent, env)
end
