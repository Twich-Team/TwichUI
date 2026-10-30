-- TwichUI Layout Setup: the six pages
-- Each page is built the first time it is shown and kept; showing it again only re-reads the model (Model.lua) and
-- re-writes its texts, so opening, going back and forth, and re-opening make nothing new. A page never decides anything:
-- it draws what the model says, and its buttons call the model (or the window's confirmed actions) and then ask the
-- window to draw again.
--
-- What a page shows by default is its heading, at most one short line, and the choices or the result. Everything that
-- explains how (what a layout covers, what a preset sets, every compatibility check, every change a review lists, the update
-- policy, the maintenance actions) is behind a labelled disclosure built the first time it is opened; what a player must
-- know (a blocker, a warning, an account-wide effect, a limit of the preview) is a short statement that stays in view.
-- Every choice is a Controls.Choice card, so a selection looks the same wherever it is made.
--
--   Pages.Build(key, parent, env) -> page { frame, Refresh() }
--   env: { Relayout(), Go(step), Overlay(), Actions = { reload, restore, undo, keepUpdate, keep, check, forget, again, ... } }

local R = TwichUI
local LY = R.Layouts
local WZ = R.LayoutWizard
local M = WZ.Model
local Controls = WZ.Controls
local Choice, Disclosure = Controls.Choice, Controls.Disclosure
local Pages = {}
WZ.Pages = Pages

Pages.CONTENT_W = 718
Pages.DETAIL_ROWS = 5   -- settings shown at once in an update's details (the rest a page at a time)
local CONTENT_W = Pages.CONTENT_W
local LEFT_W, GAP = 372, 16
local RIGHT_X = LEFT_W + GAP
local HALF_W = math.floor((CONTENT_W - 16) / 2)

local function Look() return R.Look end
local function Pal() return R.Look.pal end

---------------------------------------------------------------------------
-- A column of items stacked top to bottom (the visible ones), and small pieces
---------------------------------------------------------------------------
local Height = Controls.Height

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

local function Tone(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- A flat chip with a word in it (a status is never colour alone). SetTone(tone [, word]): the word defaults to the tone's own.
local TONE = { ok = "Ready", warn = "Check", block = "Blocked", info = "Note" }
local function Chip(parent)
    local L, pal = Look(), Pal()
    local chip = L.Tag(parent, "Ready")
    function chip:SetTone(tone, word)
        local fill, text = pal.ink, pal.stone
        local a = 0.30
        if tone == "ok" then fill, text, a = pal.tealLo, pal.tealHi, 0.9
        elseif tone == "warn" then fill, text, a = pal.bronzeText, pal.bronzeText, 0.22
        elseif tone == "block" then fill, text, a = pal.danger.bg, pal.danger.text, 1 end
        self.bg:SetColorTexture(fill[1], fill[2], fill[3], a)
        self.text:SetTextColor(text[1], text[2], text[3])
        self.text:SetText(word or TONE[tone] or TONE.info)
        self:SetWidth(math.max(44, self.text:GetStringWidth() + 12))
    end
    return chip
end
Pages.Chip = Chip

local function Button(parent, label, w, kind, fn, tip)
    local b = Look().Button(parent, label, w, kind, fn)
    b:SetHeight(24)
    if tip then R.Interact.Tip(b, label, tip) end
    return b
end

-- Draws a picture for a card: a wizard picture by its Art id, or one of TwichUI's own icons ("icon:<id>"); false when there is none
local function DrawPic(tex, id)
    if not id then tex:Hide() return false end
    local icon = id:match("^icon:(.+)$")
    if icon then
        tex:Show()
        R.Icons.Apply(tex, icon, 64)
        return true
    end
    return WZ.Art.Apply(tex, id)
end

-- The preview (steps 2 and 5), in the right-hand column, redrawn from the model each time the page is shown. Under it: the
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
        view.caption:SetText(WZ.Preview.CAPTION .. (note and ("\n" .. note) or ""))
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
-- What the first page says. One calm opening for everyone; a first installation adds the ways out (Do this later, Skip setup,
-- and EllesmereUI's own setup when it was held back for this one).
Pages.WELCOME = {
    head = "Make yourself at home",
    intro = "Choose a layout, pick your conveniences, and make it yours.",
    account = "Part of the layout (EllesmereUI's) applies to every character on this account.",
    tiles = {
        { "Choose your layout", "Classic or Compact, drawn for your screen." },
        { "Add your preferences", "Helpers, accent, size and more." },
        { "Review, then apply", "Nothing changes until you apply. Your current setup is backed up when you do." },
    },
    status = {
        ok = "Everything the setup needs is in place.",
        warn = "A few things are worth a look before you continue.",
        block = "Fix what is marked Blocked before you continue.",
    },
}
Pages.FIRST = {
    later = "Not now? Do this later (bottom left) offers it again the next time you log in; Skip setup closes it for good. It stays under /tui layout.",
    held = "EllesmereUI's first-run setup is waiting for this one. Applying a layout here answers it.",
}

local function MakeRow(f)
    local row = CreateFrame("Frame", nil, f)
    row:SetSize(CONTENT_W, 30)
    row.chip = Chip(row)
    row.chip:SetPoint("TOPLEFT", 0, -2)
    row.label = Text(row, "body", 150)
    row.label:SetPoint("TOPLEFT", 72, -2)
    row.detail = Text(row, "small", CONTENT_W - 72 - 160 - 90)
    row.detail:SetPoint("TOPLEFT", 232, -3)
    row.link = Button(row, "See it", 70, "secondary", function() end)
    row.link:SetPoint("TOPRIGHT", 0, -2)
    return row
end

local function FillRow(row, it, text, env)
    row.chip:SetTone(it.state)
    row.label:SetText(it.label)
    row.detail:SetText(text)
    row.link:SetShown(it.go ~= nil)
    if it.go then row.link:SetScript("OnClick", function() env.Go(it.go) end) end
    row:SetHeight(math.max(26, Height(row.detail) + 6))
    row:Show()
end

local function BuildWelcome(parent, env)
    local L, pal = Look(), Pal()
    local page = { frame = CreateFrame("Frame", nil, parent), attn = {}, rows = {}, tiles = {} }
    local f = page.frame
    f:SetSize(CONTENT_W, 10)

    local emblem = f:CreateTexture(nil, "ARTWORK")
    emblem:SetSize(72, 72)
    emblem:SetPoint("TOPLEFT", 0, -4)
    WZ.Art.Apply(emblem, "emblem")
    local head = L.Text(f, "title")
    head:SetPoint("TOPLEFT", 92, -10)
    head:SetText(Pages.WELCOME.head)
    local intro = Text(f, "body", CONTENT_W - 92)
    intro:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
    intro:SetText(Pages.WELCOME.intro)

    -- the three points: drawn, not an essay
    local TILE_W = math.floor((CONTENT_W - 20) / 3)
    for i, t in ipairs(Pages.WELCOME.tiles) do
        local tile = CreateFrame("Frame", nil, f, "BackdropTemplate")
        tile:SetSize(TILE_W, 74)
        L.Panel(tile)
        tile:SetPoint("TOPLEFT", (i - 1) * (TILE_W + 10), -86)
        tile.num = L.Text(tile, "title")
        tile.num:SetPoint("TOPLEFT", 12, -8)
        tile.num:SetText(tostring(i))
        tile.num:SetTextColor(pal.bronzeText[1], pal.bronzeText[2], pal.bronzeText[3])
        tile.head = Text(tile, "body", TILE_W - 48)
        tile.head:SetPoint("TOPLEFT", 36, -10)
        tile.head:SetText(t[1])
        tile.sub = Text(tile, "small", TILE_W - 24)
        tile.sub:SetPoint("TOPLEFT", 12, -34)
        tile.sub:SetText(t[2])
        page.tiles[i] = tile
    end
    local account = Text(f, "small", CONTENT_W)
    account:SetText(Pages.WELCOME.account)
    account:SetPoint("TOPLEFT", 0, -168)

    -- the verdict, in a word, and what needs a look
    local chip = Chip(f)
    local status = Text(f, "body", CONTENT_W - 140)

    -- first installation only: the ways out (each changes nothing and asks first)
    local later = Text(f, "small", CONTENT_W)
    later:SetText(Pages.FIRST.later)
    local held = Text(f, "small", CONTENT_W)
    held:SetText(Pages.FIRST.held)
    local skipBtn = Button(f, "Skip setup", 110, "secondary", function() env.Actions.skip() end,
        "Closes the setup without applying anything, and doesn't offer it again by itself. It stays under /tui layout and Home > Interface layout. It asks first.")
    local nativeBtn = Button(f, "Use EllesmereUI's setup instead", 230, "secondary", function() env.Actions.native() end,
        "Closes this setup without applying anything and opens EllesmereUI's own first-run setup, where you choose which of its addons stay on. EllesmereUI reloads when you press its button. It asks first.")
    page.later, page.held, page.skip, page.native = later, held, skipBtn, nativeBtn

    -- the package to set up from: shown only once someone has sent one (the included package is the only one before that)
    local pkgHead = Heading(f, "Layout package", CONTENT_W)
    local pkgNote = Text(f, "small", CONTENT_W)
    page.srcCards = {}
    for i = 1, 1 + (LY and LY.Store and LY.Store.LIMITS.received or 3) do
        local card = Choice(f, CONTENT_W, function() end, { label = true })
        card:Hide()
        page.srcCards[i] = card
    end
    local removeBtn = Button(f, "Remove this package", 170, "secondary", function() env.Actions.removePackage() end,
        "Deletes the stored copy of this package. An install already made from it, and Restore, are not touched. Ask the sender again if you want it back.")
    removeBtn:Hide()

    -- every check, behind its own button (built when first opened)
    page.detailsOpen = false
    local details = Disclosure(f, "Compatibility details", 220, function(open)
        page.detailsOpen = open
        env.Relayout()
    end)
    page.disclosure = details

    function page.Refresh()
        local first = M.FirstRun()
        local sum = M.CompatSummary()
        chip:SetTone(sum.state, sum.word)
        status:SetText(Pages.WELCOME.status[sum.state])
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -196)
        status:ClearAllPoints()
        status:SetPoint("LEFT", chip, "RIGHT", 10, 0)
        local y = 196 + 26

        -- what needs a look, with its short explanation, at once
        for i, it in ipairs(sum.attention) do
            local row = page.attn[i]
            if not row then row = MakeRow(f) page.attn[i] = row end
            FillRow(row, it, it.short, env)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            y = y + row:GetHeight() + 4
        end
        for i = #sum.attention + 1, #page.attn do page.attn[i]:Hide() end
        y = y + 6

        local native = first and M.NativeAvailable()
        later:SetShown(first)
        skipBtn:SetShown(first)
        held:SetShown(native)
        nativeBtn:SetShown(native)
        if first then
            later:ClearAllPoints()
            later:SetPoint("TOPLEFT", 0, -y)
            y = y + Height(later) + 8
            skipBtn:ClearAllPoints()
            skipBtn:SetPoint("TOPLEFT", 0, -y)
            if native then
                nativeBtn:ClearAllPoints()
                nativeBtn:SetPoint("TOPLEFT", skipBtn, "TOPRIGHT", 10, 0)
                held:ClearAllPoints()
                held:SetPoint("TOPLEFT", 0, -(y + 30))
                y = y + 30 + Height(held)
            end
            y = y + 32
        end

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
                or "Layouts other players sent you. Choosing one only changes what this setup shows; nothing is applied until you review it.")
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

        details:SetOpen(page.detailsOpen)
        details:ClearAllPoints()
        details:SetPoint("TOPLEFT", 0, -y)
        y = y + 26
        for i, row in ipairs(page.rows) do row:SetShown(page.detailsOpen and i <= #sum.items) end
        if page.detailsOpen then
            for i, it in ipairs(sum.items) do
                local row = page.rows[i]
                if not row then row = MakeRow(f) page.rows[i] = row end
                FillRow(row, it, it.detail, env)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                y = y + row:GetHeight() + 4
            end
        end
        f:SetHeight(y + 8)
        return y + 8
    end
    return page
end

---------------------------------------------------------------------------
-- 2. Layout: Classic or Compact Adventure. Choosing re-draws the preview at once and changes nothing else.
---------------------------------------------------------------------------
local LAYOUT_PIC = { 128, 64 }

local function BuildLayout(parent, env)
    local page = { frame = CreateFrame("Frame", nil, parent), cards = {} }
    local f = page.frame
    f:SetSize(CONTENT_W, 10)
    local head = Heading(f, "Choose a layout", LEFT_W)
    head:SetPoint("TOPLEFT", 0, -4)
    local sub = Text(f, "small", LEFT_W)
    sub:SetText("The preview updates as you choose.")
    sub:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
    PreviewColumn(page, f, 24, env)

    local more = Disclosure(f, "Layout details", 180, function(open)
        page.detailsOpen = open
        env.Relayout()
    end)
    page.detailsOpen = false
    page.disclosure = more

    local function LayoutCard(i)
        local card = page.cards[i]
        if card then return card end
        card = Choice(f, LEFT_W, function() end, { pic = LAYOUT_PIC, label = true, titleKind = "body" })
        card.traits = Look().Text(card, "meta")
        card.traits:SetJustifyH("LEFT")
        card.traits:SetWordWrap(true)
        card.tag = Chip(card)
        page.cards[i] = card
        return card
    end

    function page.Refresh()
        local current = M.Layout()
        local y = 24 + Height(head) + 4 + Height(sub) + 8
        for i, layout in ipairs(M.LayoutList()) do
            local card = LayoutCard(i)
            card:SetScript("OnClick", function()
                M.SetLayout(layout.id)
                env.Relayout()
            end)
            card.hasPic = DrawPic(card.pic, layout.art)
            local traits = layout.traits and #layout.traits > 0 and table.concat(layout.traits, "  \194\183  ") or nil
            card.traits:SetWidth(LEFT_W - card.textX - 12)
            card.traits:SetText(traits or "")
            card.traits:SetShown(traits ~= nil)
            local extra = traits and (6 + Height(card.traits)) or 0
            local h, bottom = card:Fill(layout.title, layout.desc or layout.blurb, extra)
            card.traits:ClearAllPoints()
            card.traits:SetPoint("TOPLEFT", card.textX, -(bottom + 6))
            card.tag:SetTone("warn", "Preview build")
            card.tag:ClearAllPoints()
            card.tag:SetPoint("TOPLEFT", 10, -(10 + LAYOUT_PIC[2] + 6))
            card.tag:SetShown(layout.dev)
            if layout.dev then card:SetHeight(math.max(h, 10 + LAYOUT_PIC[2] + 6 + 15 + 10)) end
            card:SetSelected(layout.id == current.id)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", 0, -y)
            card:Show()
            y = y + card:GetHeight() + 8
        end
        for i = #M.LayoutList() + 1, #page.cards do page.cards[i]:Hide() end

        -- what the chosen layout covers: behind its own button, built when first opened
        more:SetOpen(page.detailsOpen)
        more:ClearAllPoints()
        more:SetPoint("TOPLEFT", 0, -y)
        y = y + 26
        if page.detailsOpen then
            page.detail = page.detail or Text(f, "small", LEFT_W)
            page.detail:SetText(current.blurb .. "\n\n" .. Bullets(current.covers))
            page.detail:ClearAllPoints()
            page.detail:SetPoint("TOPLEFT", 0, -y)
            page.detail:Show()
            y = y + Height(page.detail) + 6
        elseif page.detail then
            page.detail:Hide()
        end
        page.RefreshPreview()
        f:SetHeight(math.max(y, 280) + 8)
        return f:GetHeight()
    end
    return page
end

---------------------------------------------------------------------------
-- 3. Helpers: one card for each preset the package offers, whatever its number and whatever it sets
---------------------------------------------------------------------------
-- The card's picture: the preset's own shape decides (Model.PresetCard.art), a preset with none gets TwichUI's generic icon.
local PRESET_ART = { keep = "keep", helpers = "helpers", curated = "curated", navigation = "icon:navigation" }
local GENERIC_ART = "icon:qualityOfLife"
local HELP_PIC = { 56, 56 }

local function BuildHelpers(parent, env)
    local page = { frame = CreateFrame("Frame", nil, parent), cards = {}, open = {} }
    local f = page.frame
    f:SetSize(CONTENT_W, 10)
    local head = Heading(f, "Choose TwichUI's helpers", CONTENT_W)
    head:SetPoint("TOPLEFT", 0, -4)
    local sub = Text(f, "small", CONTENT_W)
    sub:SetText("Pick a set of TwichUI helpers. You can change any of them later in TwichUI's settings.")
    -- a preset picked before (or installed) that this package no longer offers: said first, and a choice is asked for
    local gone = Text(f, "small", CONTENT_W)
    Tone(gone, Pal().bronzeText)   -- the warning tone, and the words say it
    local foot = Text(f, "small", CONTENT_W)
    foot:SetText("The layout's own look and places apply whichever you choose.")
    local none = Text(f, "body", CONTENT_W)
    none:SetText("This package doesn't ask which of TwichUI's helpers to turn on. Nothing is chosen here; go on to the next step.")
    none:SetPoint("TOPLEFT", 0, -40)

    local function HelperCard(i)
        local card = page.cards[i]
        if card then return card end
        card = Choice(f, CONTENT_W, function() end, { pic = HELP_PIC, label = true })
        card.more = Disclosure(card, "View included settings", 200, function(open)
            if card.optionId then page.open[card.optionId] = open or nil end
            env.Relayout()
        end)
        page.cards[i] = card
        return card
    end

    function page.Refresh()
        local ch = M.Choice("helpers")
        if not ch then
            sub:Hide() gone:Hide() foot:Hide()
            none:Show()
            for _, card in ipairs(page.cards) do card:Hide() end
            f:SetHeight(120)
            return 120
        end
        none:Hide()
        sub:Show()
        local missing = M.Missing("helpers")
        gone:SetShown(missing ~= nil)
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", 0, -4)
        sub:ClearAllPoints()
        sub:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
        local y = 4 + Height(head) + 4 + Height(sub) + 10
        if missing then
            gone:SetText(("The helper preset you chose before (\"%s\") is no longer offered by this package. Choose one of these; nothing is picked for you."):format(missing))
            gone:ClearAllPoints()
            gone:SetPoint("TOPLEFT", 0, -y)
            y = y + Height(gone) + 8
        else gone:SetText("") end
        for i, o in ipairs(ch.options) do
            local card = HelperCard(i)
            card.optionId = o.id
            card:SetScript("OnClick", function()
                M.SetPick("helpers", o.id)
                env.Relayout()
            end)
            local pc = M.PresetCard("helpers", o.id)
            local art = pc and pc.art and PRESET_ART[pc.art] or GENERIC_ART
            DrawPic(card.pic, art)
            local open = page.open[o.id] == true
            card.more:SetOpen(open)
            -- the included settings, built the first time a card is opened
            if open then
                card.detail = card.detail or Text(card, "small", CONTENT_W - card.textX - 12)
                card.detail:SetText(Bullets(pc and pc.details))
                card.detail:Show()
            elseif card.detail then card.detail:Hide() end
            local detailH = open and (Height(card.detail) + 6) or 0
            local _, bottom = card:Fill(o.label, pc and pc.short or o.hint, 26 + detailH)
            card.more:ClearAllPoints()
            card.more:SetPoint("TOPLEFT", card.textX - 8, -(bottom + 2))
            if open then
                card.detail:ClearAllPoints()
                card.detail:SetPoint("TOPLEFT", card.textX, -(bottom + 30))
            end
            card:SetSelected(M.Pick("helpers") == o.id and not missing)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", 0, -y)
            card:Show()
            y = y + card:GetHeight() + 8
        end
        for i = #ch.options + 1, #page.cards do page.cards[i]:Hide() end
        foot:Show()
        foot:ClearAllPoints()
        foot:SetPoint("TOPLEFT", 0, -(y + 2))
        y = y + 2 + Height(foot)
        f:SetHeight(y + 8)
        return f:GetHeight()
    end
    return page
end

---------------------------------------------------------------------------
-- 4. Personalize: compact choices, each with its own small sample
---------------------------------------------------------------------------
local function ClassColor()
    local class = UnitClass and select(2, UnitClass("player"))
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return { c.r, c.g, c.b } end
    return { 0.62, 0.60, 0.56 }
end
WZ.ClassColor = ClassColor

-- Three synthetic friendly players: nothing of the game's, coloured by the game's own class colours.
local SAMPLE_PLATES = { { "Warrior", "WARRIOR", { 0.78, 0.61, 0.43 } }, { "Priest", "PRIEST", { 1, 1, 1 } }, { "Mage", "MAGE", { 0.25, 0.78, 0.92 } } }
local BLUE = { 0.667, 0.667, 1 }
-- Pictures for the options a package's tooltip choice has by these ids (an option with another id simply has none)
local TIP_ART = { layout = "tipFixed", cursor = "tipCursor" }
local SCOPE = { tooltip = "Applies to every character on this account." }
local SWATCH_W = 70

local function BuildPersonalize(parent, env)
    local L, pal = Look(), Pal()
    local page = { frame = CreateFrame("Frame", nil, parent), swatches = {}, sizes = {}, groups = {} }
    local f = page.frame
    f:SetSize(CONTENT_W, 10)
    local head = Heading(f, "Make it yours", CONTENT_W - 120)
    head:SetPoint("TOPLEFT", 0, -4)
    local sub = Text(f, "small", CONTENT_W - 120)
    sub:SetText("Nothing changes until you apply.")
    sub:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
    local reset = Button(f, "Start over", 100, "secondary", function() M.ResetPicks() env.Relayout() end,
        "Puts every choice back to the layout's own, here and on the Helpers step. Nothing in the game changes.")
    reset:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -4)
    local none = Text(f, "body", CONTENT_W)
    none:SetText("This package doesn't ask for an accent colour or a size. Nothing is chosen here; go on to the review.")
    none:SetPoint("TOPLEFT", 0, -70)

    local accentHead = Heading(f, "", HALF_W)
    local sizeHead = Heading(f, "", HALF_W)
    local sizeHint = Text(f, "small", HALF_W)

    -- one accent: a swatch, its name under it, a check when it is the one
    local function Swatch(i)
        local sw = page.swatches[i]
        if sw then return sw end
        sw = CreateFrame("Button", nil, f, "BackdropTemplate")
        sw:SetSize(SWATCH_W, 66)
        sw.chip = CreateFrame("Frame", nil, sw, "BackdropTemplate")
        sw.chip:SetSize(34, 34)
        sw.chip:SetPoint("TOP", 0, 0)
        L.Surface(sw.chip, pal.well, 1, pal.control, 1)
        sw.fill = L.Solid(sw.chip, "ARTWORK", pal.stone, 1)
        sw.fill:SetPoint("TOPLEFT", 4, -4)
        sw.fill:SetPoint("BOTTOMRIGHT", -4, 4)
        sw.rim = {}
        for k, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 }, { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
            local t = L.Solid(sw.chip, "OVERLAY", pal.text, 1)
            t:SetPoint(spec[1], 0, 0)
            t:SetPoint(spec[2], 0, 0)
            if spec[3] then t:SetWidth(spec[3]) else t:SetHeight(spec[4]) end
            t:Hide()
            sw.rim[k] = t
        end
        sw.icon = sw.chip:CreateTexture(nil, "OVERLAY")
        sw.icon:SetSize(18, 18)
        sw.icon:SetPoint("CENTER", 0, 0)
        sw.icon:Hide()
        sw.mark = Controls.Mark(sw)
        sw.mark:SetPoint("CENTER", sw.chip, "BOTTOMRIGHT", -2, 2)
        sw.mark:Hide()
        sw.name = Text(sw, "small", SWATCH_W - 4)
        sw.name:SetJustifyH("CENTER")
        sw.name:SetPoint("TOP", sw.chip, "BOTTOM", 0, -4)
        L.Hover(sw, pal.text, 0.06)
        page.swatches[i] = sw
        return sw
    end

    -- a group: its heading, a scope note at the right, two cards
    local function Group(id)
        local g = page.groups[id]
        if g then return g end
        g = { head = Heading(f, "", 300), scope = L.Text(f, "meta"), note = Text(f, "small", CONTENT_W), cards = {} }
        g.scope:SetJustifyH("RIGHT")
        g.scope:SetWidth(CONTENT_W - 300)
        g.scope:SetTextColor(pal.bronzeText[1], pal.bronzeText[2], pal.bronzeText[3])
        if id == "friendly-plates" then
            g.limit = Text(f, "small", CONTENT_W)
            g.samples = {}
        end
        page.groups[id] = g
        return g
    end
    local function HideGroup(g)
        g.head:Hide() g.scope:Hide() g.note:Hide()
        if g.limit then g.limit:Hide() end
        for _, c in ipairs(g.cards) do c:Hide() end
    end

    -- three sample nameplates drawn inside a card: names with a bar under each (or the name alone in a name-only layout)
    local function Samples(card)
        if not card.samples then
            card.samples = {}
            for i = 1, #SAMPLE_PLATES do
                card.samples[i] = { bar = card:CreateTexture(nil, "ARTWORK"), name = L.Text(card, "small") }
                card.samples[i].bar:SetSize(80, 7)
            end
        end
        return card.samples
    end

    local function DrawGroup(id, y)
        local ch = M.Choice(id)
        local g = Group(id)
        if not ch then HideGroup(g) return y end
        g.head:Show()
        g.head:SetText(ch.label)
        g.head:ClearAllPoints()
        g.head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        local scope = SCOPE[id]
        g.scope:SetText(scope or "")
        g.scope:SetShown(scope ~= nil)
        g.scope:ClearAllPoints()
        g.scope:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(y + 2))
        y = y + 22
        local mode = id == "friendly-plates" and (M.PlatesMode() or { nameOnly = false }) or nil
        local h = 0
        for i, o in ipairs(ch.options) do
            local card = g.cards[i]
            if not card then
                local pic = id == "tooltip" and { 88, 70 } or nil
                card = Choice(f, HALF_W, function() end, { pic = pic, label = true })
                g.cards[i] = card
            end
            card:SetScript("OnClick", function() M.SetPick(id, o.id) env.Relayout() end)
            local chosen = M.Pick(id) == o.id
            if id == "tooltip" then DrawPic(card.pic, TIP_ART[o.id]) end
            local extra = 0
            if id == "friendly-plates" then extra = 34 end
            local _, bottom = card:Fill(o.label, o.hint, extra)
            if id == "friendly-plates" then
                -- the sample: each player's plate as this option would draw it. Class colors: the player's class color (EllesmereUI's
                -- own plate; names only in a name-only layout). Standard blue: Blizzard's plate, which EllesmereUI no longer manages,
                -- drawn as a plain blue bar since how it looks is Blizzard's setting.
                local blue = o.id == "blue"
                local samples = Samples(card)
                for k, sp in ipairs(SAMPLE_PLATES) do
                    local s = samples[k]
                    local class = RAID_CLASS_COLORS and RAID_CLASS_COLORS[sp[2]]
                    local cc = class and { class.r, class.g, class.b } or sp[3]
                    local x = 12 + (k - 1) * 104
                    s.name:SetText(sp[1])
                    s.name:ClearAllPoints()
                    s.bar:ClearAllPoints()
                    if mode.nameOnly and not blue then
                        s.bar:Hide()
                        s.name:SetTextColor(cc[1], cc[2], cc[3])
                        s.name:SetPoint("TOPLEFT", card, "TOPLEFT", x, -(bottom + 12))
                    else
                        local col = blue and BLUE or cc
                        s.bar:SetColorTexture(col[1], col[2], col[3], 1)
                        s.bar:SetPoint("TOPLEFT", card, "TOPLEFT", x, -(bottom + 8))
                        s.bar:Show()
                        s.name:SetTextColor(1, 1, 1)
                        s.name:SetPoint("TOPLEFT", s.bar, "BOTTOMLEFT", 0, -3)
                    end
                    s.name:Show()
                end
            end
            card:SetSelected(chosen)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * (HALF_W + 16), -y)
            card:Show()
            h = math.max(h, card:GetHeight())
        end
        for i = #ch.options + 1, #g.cards do g.cards[i]:Hide() end
        for i = 1, #ch.options do g.cards[i]:SetHeight(h) end
        y = y + h + 6
        local derived = M.Derived(id)
        g.note:SetText("Shown as your game has it now. Pick one to choose for yourself.")
        g.note:SetShown(derived)
        if derived then
            g.note:ClearAllPoints()
            g.note:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
            y = y + Height(g.note) + 4
        end
        if g.limit then
            -- what Standard blue leaves as it is: stated while it is the pick (not a caption on every page)
            local blue = M.Pick(id) == "blue"
            g.limit:SetText("Blizzard's nameplates draw friendly players, by Blizzard's own settings (Esc > Options > Nameplates). What EllesmereUI last set for them stays until you change it there.")
            g.limit:SetShown(blue)
            if blue then
                g.limit:ClearAllPoints()
                g.limit:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
                y = y + Height(g.limit) + 4
            end
        end
        return y + 8
    end

    function page.Refresh()
        local accent, size = M.Choice("accent"), M.Choice("size")
        local shown = accent ~= nil and size ~= nil
        for _, w in ipairs({ accentHead, sizeHead, sizeHint, reset, sub }) do w:SetShown(shown) end
        none:SetShown(not shown)
        if not shown then
            -- a package from another player may offer neither
            for _, sw in ipairs(page.swatches) do sw:Hide() end
            for _, c in ipairs(page.sizes) do c:Hide() end
            for _, g in pairs(page.groups) do HideGroup(g) end
            f:SetHeight(200)
            return 200
        end
        local top = 4 + Height(head) + 4 + Height(sub) + 12

        -- accent (left): swatches with their names
        accentHead:SetText(accent.label)
        accentHead:ClearAllPoints()
        accentHead:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
        local ay = top + 22
        local per = math.max(1, math.floor(HALF_W / SWATCH_W))
        for i, o in ipairs(accent.options) do
            local sw = Swatch(i)
            local col = o.swatch or (o.id == "class" and ClassColor()) or pal.stone
            sw.fill:SetColorTexture(col[1], col[2], col[3], 1)
            -- the class option carries the class's own icon, so it is never an unexplained swatch
            local token = o.id == "class" and UnitClass and select(2, UnitClass("player")) or nil
            local coords = token and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
            if coords then
                sw.icon:SetTexture([[Interface\WorldStateFrame\Icons-Classes]])
                sw.icon:SetTexCoord(unpack(coords))
                sw.icon:Show()
            else sw.icon:Hide() end
            sw.name:SetText(o.label)
            local chosen = M.Pick("accent") == o.id
            for _, t in ipairs(sw.rim) do t:SetShown(chosen) end
            sw.mark:SetShown(chosen)
            sw.mark:SetOn(chosen)
            local edge = chosen and pal.text or pal.control
            sw.chip:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
            sw:ClearAllPoints()
            sw:SetPoint("TOPLEFT", f, "TOPLEFT", ((i - 1) % per) * SWATCH_W, -(ay + math.floor((i - 1) / per) * 68))
            sw:SetScript("OnClick", function() M.SetPick("accent", o.id) env.Relayout() end)
            R.Interact.Tip(sw, o.label, o.hint or (o.id == "class" and "Follows the character you play." or nil))
            sw:Show()
        end
        for i = #accent.options + 1, #page.swatches do page.swatches[i]:Hide() end
        local accentBottom = ay + math.ceil(#accent.options / per) * 68

        -- size (right): two cards that show their own relative size, and what the package says they change
        local rx = HALF_W + 16
        sizeHead:SetText(size.label)
        sizeHead:ClearAllPoints()
        sizeHead:SetPoint("TOPLEFT", f, "TOPLEFT", rx, -top)
        local cw = math.floor((HALF_W - 8) / 2)
        local sy = top + 22
        local fontFile = (GameFontHighlight and GameFontHighlight.GetFont and GameFontHighlight:GetFont()) or "Fonts\\FRIZQT__.TTF"
        for i, so in ipairs(size.options) do
            local card = page.sizes[i]
            if not card then
                card = Choice(f, cw, function() end, { pic = { 40, 32 } })
                card.pic:Hide()
                card.sample = L.Text(card, "title")
                card.sample:SetPoint("TOPLEFT", 12, -12)
                card.sample:SetText("Aa")
                page.sizes[i] = card
            end
            card:SetScript("OnClick", function() M.SetPick("size", so.id) env.Relayout() end)
            -- "Aa" at the size each option gives: the standard text, and about a seventh larger for Larger (the density's own ratio is 1.15)
            local px = so.density == "larger" and 18 or 15
            if card.sample.SetFont then card.sample:SetFont(fontFile, px, "") end
            card:Fill(so.label, nil)
            card:SetHeight(56)
            card:SetSelected(M.Pick("size") == so.id)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", f, "TOPLEFT", rx + (i - 1) * (cw + 8), -sy)
            card:Show()
        end
        for i = #size.options + 1, #page.sizes do page.sizes[i]:Hide() end
        sizeHint:SetText(M.Brief(size.hint, 140))
        sizeHint:ClearAllPoints()
        sizeHint:SetPoint("TOPLEFT", f, "TOPLEFT", rx, -(sy + 56 + 6))
        local sizeBottom = sy + 56 + 6 + Height(sizeHint)

        local y = math.max(accentBottom, sizeBottom) + 14
        y = DrawGroup("tooltip", y)
        y = DrawGroup("friendly-plates", y)
        reset:SetEnabled(not M.IsDefault())
        f:SetHeight(math.max(y, 200) + 4)
        return f:GetHeight()
    end
    return page
end

---------------------------------------------------------------------------
-- 5. Review: a short receipt, with what changes and the update controls behind buttons
---------------------------------------------------------------------------
local HEADINGS = {
    fresh = { "Ready to apply", "Nothing has changed yet. Apply makes the changes below." },
    update = { "Ready to update", "Nothing has changed yet. Apply makes the changes below." },
    nothing = { "You're already up to date.", "Your installed layout already matches these choices." },
    blocked = { "Can't apply yet", "Nothing has changed." },
}
local MODE_NAME = { keep = "Keep my customizations", recommended = "Reapply the recommended configuration", review = "Review conflicts" }
local NOTE_PREFIX = { warn = "Check: ", block = "Blocked: ", account = "Account-wide: " }
local NOTE_SLOTS = 12
local ROW_SLOTS = 1 + (LY and LY.MAX_CHOICES or 6)

local function BuildReview(parent, env)
    local pal = Pal()
    local page = { frame = CreateFrame("Frame", nil, parent), rows = {}, notes = {} }
    local f = page.frame
    f:SetSize(CONTENT_W, 10)
    local col = NewColumn(f)
    local head = Put(col, Heading(f, HEADINGS.fresh[1], LEFT_W), 4)
    local lead = Put(col, Text(f, "small", LEFT_W), 4)
    local switching = Put(col, Text(f, "small", LEFT_W), 6)

    -- the choices, as compact rows
    for i = 1, ROW_SLOTS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(LEFT_W, 18)
        row.label = Look().Text(row, "small")
        row.label:SetWidth(150)
        row.label:SetPoint("TOPLEFT", 0, -2)
        row.value = Text(row, "body", LEFT_W - 158)
        row.value:SetPoint("TOPLEFT", 158, -1)
        page.rows[i] = row
        Put(col, row, i == 1 and 10 or 2)
    end
    -- the consequences, one short statement each (a warning or a blocker says so in words, not only in colour)
    for i = 1, NOTE_SLOTS do page.notes[i] = Put(col, Text(f, "small", LEFT_W), i == 1 and 10 or 3) end
    local forcedText = Put(col, Text(f, "small", LEFT_W), 8)
    Tone(forcedText, pal.bronzeText)
    local counts = Put(col, Text(f, "small", LEFT_W), 8)

    -- an update: one row for the policy, and the controls behind "Change". Every frame is made once, with the page; the
    -- details show one page of DETAIL_ROWS settings at a time.
    local up = { policyRow = Put(col, CreateFrame("Frame", nil, f), 10) }
    up.policyRow:SetSize(LEFT_W, 24)
    up.policyText = Text(up.policyRow, "body", LEFT_W - 100)
    up.policyText:SetPoint("LEFT", 0, 0)
    page.policyOpen = false
    up.change = Button(up.policyRow, "Change", 80, "secondary", function()
        page.policyOpen = not page.policyOpen
        env.Relayout()
    end, "Choose how this update treats your own changes, and decide setting by setting.")
    up.change:SetPoint("RIGHT", 0, 0)
    up.modes = {}
    for i, m in ipairs({
        { "keep", "Update while keeping my customizations", "Settings you changed since the last install stay as you have them; everything else takes the update." },
        { "recommended", "Reapply the recommended configuration", "Every setting the layout manages takes its value again. Settings you made yours stay yours." },
        { "review", "Review conflicts", "Keeps your changes, and lists each setting so you can choose: keep yours, use the layout's, or make it yours for good." },
    }) do
        local card = Choice(f, LEFT_W, function() M.SetUpdateMode(m[1]) env.Relayout() end, { label = true })
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
    Tone(up.warn, pal.bronzeText)
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

    -- every change, behind "View changes" (the account of what Apply does, section by section)
    page.changesOpen = false
    local changes = Put(col, Disclosure(f, "View changes", 200, function(open)
        page.changesOpen = open
        env.Relayout()
    end), 12)
    page.changes = changes
    local tHead = Put(col, Heading(f, "", LEFT_W), 8)
    local tBody = Put(col, Text(f, "small", LEFT_W), 3)
    local eHead = Put(col, Heading(f, "", LEFT_W), 10)
    local eBody = Put(col, Text(f, "small", LEFT_W), 3)
    local upHead = Put(col, Heading(f, "Update", LEFT_W), 10)
    local upBody = Put(col, Text(f, "small", LEFT_W), 3)
    local keepHead = Put(col, Heading(f, "Left alone", LEFT_W), 10)
    local keep = Put(col, Text(f, "small", LEFT_W), 3)
    local notesHead = Put(col, Heading(f, "Not placed", LEFT_W), 10)
    local notes = Put(col, Text(f, "small", LEFT_W), 3)
    local failHead = Put(col, Heading(f, "If something goes wrong", LEFT_W), 10)
    local fail = Put(col, Text(f, "small", LEFT_W), 3)
    fail:SetText("If a step fails part way, TwichUI tells you what changed and what was put back, and Restore (on the Result step) puts your previous profiles back. Nothing is undone behind your back.")
    page.tHead, page.eHead = tHead, eHead

    -- Force re-apply: for an account an earlier install left stuck. Not a normal step, so it lives under Advanced (opened for you when
    -- it is what a blocked review needs)
    page.advancedOpen = false
    local advanced = Put(col, Disclosure(f, "Advanced", 200, function(open)
        page.advancedOpen = open
        env.Relayout()
    end), 12)
    page.advanced = advanced
    local forceText = Put(col, Text(f, "small", LEFT_W), 6)
    forceText:SetText("For an account an earlier install left stuck. It changes nothing by itself: it plans a new install over what is there and lists what it would replace, and Apply still asks.")
    page.forceBar = Put(col, CreateFrame("Frame", nil, f), 6)
    page.forceBar:SetSize(LEFT_W, 24)
    page.force = Button(page.forceBar, "Force re-apply", 150, "secondary", function()
        M.SetForce(not M.Forced())
        env.Relayout()
    end, "For when an earlier install left things stuck: a failed or stopped install, a restore that never finished, a record that can't be read, or a profile with the install's name. It plans a new install over them and shows exactly what it would replace in the review. Nothing changes until you press Apply and confirm.")
    page.force:SetPoint("TOPLEFT", 0, 0)
    PreviewColumn(page, f, 24, env)

    -- The update block: shown only for an install again. Values the player can't see in the game are never shown as text.
    local DECIDES = { mine = "keep", package = "apply", own = "owned", manage = "apply" }
    function page.RefreshUpdate(u)
        local shown = u ~= nil
        up.policyRow:SetShown(shown)
        local open = shown and (page.policyOpen or u.mode == "review" or u.details == true)
        for _, m in ipairs(up.modes) do m.card:SetShown(open) end
        for _, k in ipairs({ "whole", "wholeBar", "group", "groupBar", "warn" }) do up[k]:SetShown(shown) end
        up.toggle:SetShown(open)
        up.pager:SetShown(false)
        for _, row in ipairs(up.rows) do row.text:SetShown(false) row.bar:SetShown(false) end
        if not u then return end
        up.policyText:SetText("Update: " .. (MODE_NAME[u.mode] or u.mode))
        up.change.text:SetText(open and "Hide" or "Change")
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
        local list = u.details or u.mode == "review"
        up.toggle.text:SetText(list and "Hide the settings" or ("Show each setting (" .. #u.rows .. ")"))
        up.toggle:SetShown(open and #u.rows > 0 and u.mode ~= "review")
        local per = Pages.DETAIL_ROWS
        local pages = math.max(1, math.ceil(#u.rows / per))
        local pg = math.min(math.max(1, u.page or 1), pages)
        for i, slot in ipairs(up.rows) do
            local row = list and u.rows[(pg - 1) * per + i] or nil
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
        up.pager:SetShown(list and pages > 1)
        up.prev:SetEnabled(pg > 1)
        up.next:SetEnabled(pg < pages)
        up.pageText:SetText(("%d of %d"):format(pg, pages))
    end

    function page.Refresh()
        local r = M.Review()
        local rc = M.ReviewReceipt(r)
        page.receipt = rc
        local words = HEADINGS[rc.kind]
        head:SetText(words[1])
        lead:SetText(words[2])
        switching:SetText(r.switching or "")
        switching:SetShown(r.switching ~= nil)
        for i, row in ipairs(page.rows) do
            local it = rc.rows[i]
            row:SetShown(it ~= nil)
            if it then
                row.label:SetText(it.label)
                row.value:SetText(it.value)
                row:SetHeight(math.max(18, Height(row.value) + 4))
            end
        end
        -- the consequences: blockers first, then what a warning says, then the plain facts
        local order = {}
        for _, tone in ipairs({ "block", "warn", "account", "note" }) do
            for _, n in ipairs(rc.notes) do if n.tone == tone then order[#order + 1] = n end end
        end
        for i, fs in ipairs(page.notes) do
            local n = order[i]
            if n and i == #page.notes and #order > i then   -- more than there are slots: the rest are joined, never dropped
                local rest = {}
                for k = i, #order do rest[#rest + 1] = order[k].text end
                n = { tone = n.tone, text = table.concat(rest, " ") }
            end
            fs:SetShown(n ~= nil)
            if n then
                fs:SetText((NOTE_PREFIX[n.tone] or "- ") .. n.text)
                local c = n.tone == "block" and pal.danger.text or n.tone == "warn" and pal.bronzeText or pal.textDim
                Tone(fs, c)
            end
        end
        forcedText:SetText(r.forced and table.concat(r.forced, "\n") or "")
        forcedText:SetShown(r.forced ~= nil)
        local c = rc.counts
        counts:SetShown(c ~= nil)
        if c then
            counts:SetText(("Recommended changes: %d  \194\183  Personal settings kept: %d  \194\183  Conflicts: %d  \194\183  Checked for presence only: %d"):format(
                c.recommended, c.kept, c.conflicts, c.presence))
        end
        page.RefreshUpdate(r.update)

        -- every change, when asked for
        local open = page.changesOpen
        changes:SetOpen(open)
        for _, w in ipairs({ tHead, tBody, eHead, eBody, upHead, upBody, keepHead, keep, notesHead, notes, failHead, fail }) do w:SetShown(false) end
        if open then
            for _, pair in ipairs({ { r.twichui, tHead, tBody }, { r.ellesmereui, eHead, eBody } }) do
                local sec, h, b = pair[1], pair[2], pair[3]
                if sec then
                    h:SetText(sec.title .. ": " .. sec.when:lower())
                    b:SetText(Bullets(sec.lines))
                end
                h:SetShown(sec ~= nil)
                b:SetShown(sec ~= nil)
            end
            local u = r.update
            if u then
                upBody:SetText(Bullets(u.summary) .. (#u.notes > 0 and ("\n" .. Bullets(u.notes)) or ""))
            end
            upHead:SetShown(u ~= nil)
            upBody:SetShown(u ~= nil)
            keepHead:SetShown(true)
            keep:SetShown(true)
            keep:SetText(Bullets(r.preserved))
            notes:SetText(Bullets(r.notes))
            notesHead:SetShown(#r.notes > 0)
            notes:SetShown(#r.notes > 0)
            failHead:SetShown(true)
            fail:SetShown(true)
        end

        -- Advanced: Force re-apply. Opened for you when a blocked review needs it, and while it is on.
        local canForce, forcing = M.CanForce()
        local needs = canForce == true and (rc.kind == "blocked" or forcing == true)
        advanced:SetShown(canForce == true)
        local aopen = canForce == true and (page.advancedOpen or needs)
        advanced:SetOpen(aopen)
        forceText:SetShown(aopen)
        page.forceBar:SetShown(aopen)
        page.force.text:SetText(forcing and "Stop forcing" or "Force re-apply")
        local y = Flow(col)
        page.RefreshPreview()
        f:SetHeight(math.max(y, 260) + 8)
        return f:GetHeight()
    end
    return page
end

---------------------------------------------------------------------------
-- 6. Result: a compact dialog. One heading for the outcome, the layout's name, one sentence, at most one quiet note and the buttons
-- that make sense; everything technical (what was chosen, each step, the counts, what was and wasn't checked) is behind "Details", and
-- the maintenance actions behind "Manage layout". The window (Window.lua) gives this step its own small shape: no stepper, no footer.
-- Only a setup that was read back as planned wears the success picture; every other outcome has its own heading and its recovery
-- actions in view.
---------------------------------------------------------------------------
Pages.COMPACT_W = 466   -- the dialog's content width: the window's 520, less its margins and the scroll bar's room
local CW = Pages.COMPACT_W
local ART_W, ART_H = 144, 72
local SETTLED_PRIMARY = { "done", "settings" }
local SETTLED_MANAGE = { "check", "again", "keep", "keepUpdate", "undo", "restore", "stop", "forget" }
local OPEN_PRIMARY = { "reload", "check", "again", "undo", "restore", "forget" }   -- in view while the setup needs the player
local OPEN_MANAGE = { "keep", "keepUpdate", "stop" }
local VISIBLE_AFFECTED = 3   -- what is named in view; the rest is under Details

local function BuildResult(parent, env)
    local page = { frame = CreateFrame("Frame", nil, parent) }
    local f = page.frame
    f:SetSize(CW, 10)
    local col = NewColumn(f)
    local function Centered(fs) fs:SetJustifyH("CENTER") return fs end

    local artFrame = Put(col, CreateFrame("Frame", nil, f), 4, math.floor((CW - ART_W) / 2))
    artFrame:SetSize(ART_W, ART_H)
    local art = artFrame:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints(artFrame)
    local title = Put(col, Centered(Text(f, "title", CW)), 10)
    local layoutLine = Put(col, Centered(Text(f, "body", CW)), 4)
    local summary = Put(col, Centered(Text(f, "body", CW)), 10)
    local note = Put(col, Centered(Text(f, "small", CW)), 8)           -- the one quiet secondary sentence (a limit of the check, why a reload waited)
    local checked = Put(col, Centered(Text(f, "small", CW)), 8)        -- what "Check again" just found, in view whatever else is folded
    local affected = Put(col, Centered(Text(f, "small", CW)), 8)
    local combat = Put(col, Centered(Text(f, "small", CW)), 8)
    local primaryBox = Put(col, CreateFrame("Frame", nil, f), 14)      -- the buttons that matter now sit in this box, centred in rows
    primaryBox:SetSize(CW, 1)

    local A = env.Actions
    local buttons = {
        done = Button(f, "Done", 110, "primary", function() A.done() end,
            "Closes this. Nothing is finished or discarded by closing: your setup stays managed, and Restore and Undo stay offered until you choose Keep this setup."),
        settings = Button(f, "Open settings", 130, "secondary", function() A.settings() end,
            "Closes this setup and opens TwichUI's settings."),
        reload = Button(f, "Reload now", 120, "primary", function() A.reload() end,
            "Reloads the game's interface now, which finishes EllesmereUI's part. After it, TwichUI reads every value back and shows this. It only happens when you press this."),
        check = Button(f, "Check again", 110, "secondary", function() A.check() end,
            "Reads every managed value back now. It changes and repairs nothing."),
        again = Button(f, "Set up again", 110, "secondary", function() A.again() end,
            "Goes back to the first step of the full setup. Nothing changes until you apply."),
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
    page.buttons = buttons

    -- the account of it, behind "Details"
    page.detailsOpen = false
    local detailsBtn = Put(col, Disclosure(f, "Details", 120, function(open) page.detailsOpen = open env.Relayout() end), 10, math.floor((CW - 120) / 2))
    local detailText = Put(col, Text(f, "small", CW), 6)
    local picksHead = Put(col, Heading(f, "What was chosen", CW), 10)
    local picks = Put(col, Text(f, "small", CW), 3)
    local stepsHead = Put(col, Heading(f, "What happened", CW), 10)
    local steps = Put(col, Text(f, "small", CW), 3)
    local diffHead = Put(col, Heading(f, "What doesn't read back as planned", CW), 10)
    local diffs = Put(col, Text(f, "small", CW), 3)
    local more = Put(col, Text(f, "small", CW), 10)
    -- the maintenance actions, behind "Manage layout"
    page.manageOpen = false
    local manage = Put(col, Disclosure(f, "Manage layout", 160, function(open) page.manageOpen = open env.Relayout() end), 6, math.floor((CW - 160) / 2))
    page.manage = manage
    local manageText = Put(col, Text(f, "small", CW), 6)
    local manageBox = Put(col, CreateFrame("Frame", nil, f), 8)
    manageBox:SetSize(CW, 1)
    local pageNote = Put(col, Centered(Text(f, "small", CW)), 10)   -- why a button did nothing

    -- Centres the buttons of `keys` that are to be shown in rows inside `box` (sizing the box to them), and hides the others.
    local function Place(box, keys, show, can)
        local rows, row, w = {}, {}, 0
        for _, key in ipairs(keys) do
            local b = buttons[key]
            b:SetShown(show[key] == true)
            if show[key] then
                b:SetEnabled(can == nil or can[key] == true)   -- shown but disabled: Reload now in combat says why on the page
                if #row > 0 and w + 8 + b:GetWidth() > CW then rows[#rows + 1] = row row, w = {}, 0 end
                row[#row + 1] = { b = b, x = w }
                w = w + b:GetWidth() + 8
            end
        end
        if #row > 0 then rows[#rows + 1] = row end
        for i, r in ipairs(rows) do
            local last = r[#r]
            local x0 = math.floor((CW - (last.x + last.b:GetWidth())) / 2)
            for _, e in ipairs(r) do
                e.b:ClearAllPoints()
                e.b:SetPoint("TOPLEFT", box, "TOPLEFT", x0 + e.x, -((i - 1) * 32))
            end
        end
        box:SetHeight(math.max(1, #rows * 32 - 8))
        box:SetShown(#rows > 0)
    end

    function page.Refresh(noteText)
        local r = M.Result()
        page.result = r
        -- a new outcome starts as a short dialog again
        if page.kind ~= r.kind then page.kind, page.detailsOpen, page.manageOpen = r.kind, false, false end
        local ready, settled, progress = r.ready == true, r.settled == true, r.progress

        -- the success picture is for a setup that was read back as planned only (never a mismatch, a partial install or a failure)
        local drawn = ready and not progress and WZ.Art.Apply(art, r.art or "emblem") or false
        artFrame:SetShown(drawn)
        title:SetText(r.heading or r.title or "")
        layoutLine:SetText(r.layout or "")
        layoutLine:SetShown(not progress and r.layout ~= nil and settled)
        summary:SetText(r.summary or "")
        summary:SetShown((r.summary or "") ~= "")
        note:SetText(r.note or "")
        note:SetShown(not progress and r.note ~= nil)
        local named, all = {}, r.affected or {}
        for i, a in ipairs(all) do if i <= VISIBLE_AFFECTED then named[#named + 1] = a end end
        if #all > VISIBLE_AFFECTED then named[#named + 1] = ("and %d more, under Details."):format(#all - VISIBLE_AFFECTED) end
        if not r.listAffected then named = {} end   -- a partial install names its parts in its sentence
        checked:SetText(r.checked or "")
        checked:SetShown(not progress and r.checked ~= nil)
        affected:SetText(table.concat(named, "\n"))
        affected:SetShown(not progress and #named > 0)
        combat:SetText(r.combat or "")
        combat:SetShown(not progress and r.combat ~= nil)
        pageNote:SetText(noteText or "")
        pageNote:SetShown(not progress and noteText ~= nil and noteText ~= "")

        -- Details: status, what changed and what was checked, what was chosen, each step, what differs
        local d = {}
        if r.title and r.title ~= "" then d[#d + 1] = "Status: " .. r.title .. "." end
        for _, l in ipairs(r.details or {}) do d[#d + 1] = l end
        local extra = {}
        for i, l in ipairs(r.lines) do
            if l ~= r.checked and (i > 1 or not ready) then extra[#extra + 1] = l end
        end
        detailText:SetText(table.concat(d, "\n"))
        more:SetText(table.concat(extra, "\n\n"))
        local p = {}
        for _, x in ipairs(r.picks) do p[#p + 1] = x.choice .. ": " .. x.option end
        picks:SetText(Bullets(p))
        steps:SetText(Bullets(r.steps))
        diffs:SetText(Bullets(r.diffs))
        local open = not progress and page.detailsOpen
        detailsBtn:SetShown(not progress)
        detailsBtn:SetOpen(page.detailsOpen)
        detailText:SetShown(open and #d > 0)
        more:SetShown(open and #extra > 0)
        picksHead:SetShown(open and #p > 0)
        picks:SetShown(open and #p > 0)
        stepsHead:SetShown(open and #r.steps > 0)
        steps:SetShown(open and #r.steps > 0)
        diffHead:SetShown(open and #r.diffs > 0)
        diffs:SetShown(open and #r.diffs > 0)

        -- which actions, and where: a settled setup has Done (and Open settings) and the rest under Manage layout; one that needs the
        -- player has each recovery action that applies in view
        local can = r.can
        local primaryKeys = settled and SETTLED_PRIMARY or OPEN_PRIMARY
        local manageKeys = settled and SETTLED_MANAGE or OPEN_MANAGE
        local pshow, mshow, anyManage = {}, {}, false
        if not progress then
            for _, key in ipairs(primaryKeys) do
                pshow[key] = settled or can[key] == true or (key == "reload" and r.state == "applied" and can.reload == false and not r.checking)
            end
            for _, key in ipairs(manageKeys) do if can[key] == true then anyManage = true end end
        end
        local showManage = not progress and (anyManage or (settled and r.revision ~= nil))
        manage:SetShown(showManage)
        manage:SetOpen(page.manageOpen)
        local mopen = showManage and page.manageOpen
        for _, key in ipairs(manageKeys) do mshow[key] = mopen and can[key] == true end
        manageText:SetShown(mopen)
        if mopen then
            local t = r.revision and ("Installed revision %d."):format(r.revision) or ""
            if r.updateText then t = t .. " " .. r.updateText end
            if can.keep then
                t = t .. " Keep this setup finishes it: the restore point is forgotten, so Restore and Undo are no longer offered. TwichUI keeps managing the layout for later updates."
            end
            manageText:SetText((t:gsub("^%s+", "")))
        end
        -- every button not in a list for this outcome is hidden
        for key, b in pairs(buttons) do b:Hide() end
        Place(primaryBox, primaryKeys, pshow, not settled and can or nil)   -- Done and Open settings are always available
        Place(manageBox, manageKeys, mshow, can)
        local y = Flow(col)
        f:SetHeight(y + 14)
        return f:GetHeight()
    end
    return page
end

local BUILDERS = { BuildWelcome, BuildLayout, BuildHelpers, BuildPersonalize, BuildReview, BuildResult }

function Pages.Build(step, parent, env)
    return BUILDERS[step](parent, env)
end
