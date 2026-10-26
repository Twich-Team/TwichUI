-- TwichUI Layout Setup: the six pages
-- Each page is built the first time it is shown and kept; showing it again only re-reads the model (Model.lua) and
-- re-writes its texts, so opening, going back and forth, and re-opening make nothing new. A page never decides anything:
-- it draws what the model says, and its buttons call the model (or the window's confirmed actions) and then ask the
-- window to draw again. Text blocks are one wrapped string per section, so a page's frame count does not depend on what
-- it says.
--
--   Pages.Build(key, parent, env) -> page { frame, Refresh() }
--   env: { Relayout(), Go(step), Actions = { reload, restore, keep, check, forget, again } }

local R = TwichUI
local WZ = R.LayoutWizard
local M = WZ.Model
local Pages = {}
WZ.Pages = Pages

Pages.CONTENT_W = 718
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

-- The preview (steps 2 to 5), in the right-hand column, redrawn from the model each time the page is shown.
local function PreviewColumn(page, parent, y)
    local view = WZ.Preview.Build(parent)
    view.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", RIGHT_X, -(y or 24))
    page.preview = view
    function page.RefreshPreview()
        local geo = M.Preview()
        if not geo then view:Clear() view.caption:SetText("TwichUI couldn't read your screen's size, so there is nothing to draw.") return end
        view.caption:SetText(WZ.Preview.CAPTION)
        local accent, o = M.Accent()
        if not accent and o and o.id == "class" then accent = WZ.ClassColor and WZ.ClassColor() end
        local issues = geo.fits and nil or M.FitLines(geo, 3)
        view:Set(geo, accent, issues)
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
-- 2. Layout
---------------------------------------------------------------------------
local function BuildLayout(parent)
    local page = { frame = CreateFrame("Frame", nil, parent) }
    local f = page.frame
    f:SetSize(CONTENT_W, 10)
    local col = NewColumn(f)
    Put(col, Heading(f, "Choose a layout", LEFT_W), 4)
    local sub = Put(col, Text(f, "small", LEFT_W), 4)
    sub:SetText("TwichUI ships one layout today. You see it here to scale, for your screen, before anything is applied.")
    local card = Card(f, LEFT_W, function() end)
    Put(col, card, 10)
    card.pic = card:CreateTexture(nil, "ARTWORK")
    card.pic:SetSize(160, 80)
    card.name = Text(card, "title", LEFT_W - 190)
    card.tag = Chip(card)
    card.covers = Text(card, "small", LEFT_W - 24)
    page.card = card
    PreviewColumn(page, f, 24)

    function page.Refresh()
        local layout = M.Layout()
        card.hasPic = WZ.Art.Apply(card.pic, layout.art)
        card.name:SetText(layout.title)
        card.tag:SetTone("warn")
        card.tag.text:SetText("Preview build")
        card.tag:SetWidth(math.max(44, card.tag.text:GetStringWidth() + 12))
        card.tag:SetShown(layout.dev)
        card.title:Hide()
        card.hint:SetText(layout.blurb)
        card.hint:Show()
        card.covers:SetText(Bullets(layout.covers))
        card.mark:Show()
        card.mark:SetText("Selected")
        card.fill:Show()
        card.bar:Show()
        -- picture and name on the first row, then the text
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
        card:SetHeight(top + Height(card.hint) + 8 + Height(card.covers) + 14)
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
    PreviewColumn(page, f, 24)

    function page.Refresh()
        local ch = M.Choice("helpers")
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
    local page = { frame = CreateFrame("Frame", nil, parent), swatches = {}, sizes = {} }
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
    PreviewColumn(page, f, 24)

    function page.Refresh()
        local accent, size = M.Choice("accent"), M.Choice("size")
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
        end
        local h = 0
        for _, c in ipairs(page.sizes) do h = math.max(h, c:GetHeight()) end
        for _, c in ipairs(page.sizes) do c:SetHeight(h) end
        y = y + h + 14
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
local function BuildReview(parent)
    local pal = Pal()
    local page = { frame = CreateFrame("Frame", nil, parent) }
    local f = page.frame
    f:SetSize(CONTENT_W, 10)
    local col = NewColumn(f)
    Put(col, Heading(f, "Review before you apply", LEFT_W), 4)
    local lead = Put(col, Text(f, "small", LEFT_W), 4)
    lead:SetText("This is exactly what Apply will do on this screen. Nothing has changed yet.")
    local blocked = Put(col, Text(f, "body", LEFT_W), 8)
    blocked:SetTextColor(pal.danger.text[1], pal.danger.text[2], pal.danger.text[3])
    local fitWarn = Put(col, Text(f, "small", LEFT_W), 8)
    fitWarn:SetTextColor(pal.danger.text[1], pal.danger.text[2], pal.danger.text[3])
    Put(col, Heading(f, "Your choices", LEFT_W), 10)
    local picks = Put(col, Text(f, "small", LEFT_W), 3)
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
    PreviewColumn(page, f, 24)
    page.tHead, page.eHead = tHead, eHead

    function page.Refresh()
        local r = M.Review()
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
        fitWarn:SetText(r.fit and not r.fit.fits and ("Doesn't fit this screen: " .. table.concat(r.fit.lines, " ") .. " You can still apply it; the pieces are placed as shown.") or "")
        fitWarn:SetShown(r.fit ~= nil and not r.fit.fits)
        local lines = {}
        for _, p in ipairs(r.picks or {}) do lines[#lines + 1] = p.choice .. ": " .. p.option end
        picks:SetText(Bullets(lines))
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
            "Forgets the restore point and changes nothing else: what was installed stays, but Restore will no longer be offered."),
        restore = Button(f, "Restore previous setup", 170, "danger", function() A.restore() end,
            "Puts your previous profiles back and removes the install's own. It shows exactly what it will do and asks first."),
        forget = Button(f, "Forget the record", 140, "danger", function() A.forget() end,
            "Forgets a record that can't be read. Nothing else is changed."),
    }
    local ORDER = { "reload", "check", "again", "keep", "restore", "forget" }
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
