-- TwichUI Layout Setup: the review table's window (docs/layouts/publishing.md, "Review the changes")
-- Section 3 of the authoring workspace: a summary, a toolbar (search and four filters), a table of the changes (one compact row
-- each, a page at a time), a pager, and under the table the details of the change picked: where it is stored, what it does to each
-- layout, why it deserves a look, and its values before and after. The model is AuthorReview.lua; this only draws it.
--
-- Built once with the window (BuildReview): a fixed pool of rows and of leaf rows. Drawing writes their texts and shows the ones in
-- use, so paging, filtering, opening details and drawing again make nothing new and add no handlers. Nothing here runs per frame.
--
--   AuthorWindow.DrawReview(y) -> y     BuildReview(L)

local R = TwichUI
local LY = R.Layouts
local WZ = R.LayoutWizard
local A = WZ.Author
local RV = WZ.AuthorReview
local AW = WZ.AuthorWindow
local kit = AW.kit

local ROW_H = 28
local LEAF_ROWS = 8
local MAX_ROWS = RV.PAGE_SIZES[#RV.PAGE_SIZES]
local ROW_W = AW.CONTENT_W - 6
-- columns: left edge and width (the checkbox, setting, change, details, destination, affects, attention)
local X = { check = 8, name = 34, kind = 236, detail = 310, dest = 378, affects = 494, attn = 614 }
local WIDTH = { name = 196, kind = 70, detail = 64, dest = 110, affects = 114, attn = 116 }

local AMBER = { 0.88, 0.68, 0.30 }
local RED = { 0.92, 0.50, 0.42 }

local function Content() return AW.Content() end
local function Frames(n) AW.frames = AW.frames + (n or 1) end

local function Color(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end
local function Cell(parent, kind, width)
    local fs = kit.Text(parent, kind, width)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetMaxLines then fs:SetMaxLines(1) end
    return fs
end

local function NextKey(list, key)
    for i, e in ipairs(list) do if e.key == key then return (list[i + 1] or list[1]).key end end
    return list[1].key
end

local function LabelOf(list, key)
    for _, e in ipairs(list) do if e.key == key then return e.label end end
    return key
end

local function Plural(n, one, many) return n == 1 and one or many end

---------------------------------------------------------------------------
-- What a row says
---------------------------------------------------------------------------
-- The attention cell: the word, its colour, and the left-edge marker. Colour is never the only sign: every state has its word.
local function Attention(it)
    if not it.include then return "Excluded", "stone", nil end
    local level = RV.Level(it)
    if level == "blocked" then return "Blocked", RED, RED end
    if level == "review" then
        if RV.IsReviewed(it) then return "Reviewed", "teal", nil end
        if RV.StaleReason(it) then return "Review again", AMBER, AMBER end
        return "Review", AMBER, AMBER
    end
    if RV.IsReviewed(it) then return "Reviewed", "teal", nil end
    if level == "info" then return "Note", "dim", nil end
    return "-", "stone", nil
end

local function Tone(pal, c)
    if c == "stone" then return pal.stone elseif c == "teal" then return pal.tealHi elseif c == "dim" then return pal.textDim end
    return c or pal.text
end

local KIND_TONE = { removed = RED, default = AMBER }

local function RowTip(row)
    local it = row.it
    if not it then return nil end
    local lines = { RV.Name(it), "ID: " .. RV.Tech(it), "Now stored in: " .. RV.Storage(it) }
    local word = Attention(it)
    lines[#lines + 1] = "Attention: " .. word
    local flags = RV.Flags(it)
    for _, f in ipairs(flags.list) do
        if f.level ~= "none" then lines[#lines + 1] = ("- %s"):format(f.text) end
    end
    local why = RV.StaleReason(it)
    if why then lines[#lines + 1] = "Marked reviewed before, but " .. why .. "." end
    lines[#lines + 1] = "Click the row for its details."
    return table.concat(lines, "\n")
end

local function PaintRow(row, it, index, selected)
    local pal = kit.Look().pal
    row.it = it
    local on = it.include
    local word, tone, mark = Attention(it)
    row.check:SetChecked(on)
    row.name:SetText(RV.Name(it))
    Color(row.name, on and pal.text or pal.stone)
    row.kind:SetText(RV.KIND_LABEL[it.kind])
    Color(row.kind, KIND_TONE[it.kind] or (on and pal.textDim or pal.stone))
    row.detail:SetText(RV.Details(it))
    Color(row.detail, on and pal.textDim or pal.stone)
    row.dest.text:SetText(RV.Destination(it))
    row.dest:SetEnabled(on and not it.baseOnly)
    local impact = RV.Impact(it)
    row.affects:SetText(impact.text)
    Color(row.affects, impact.unknown and AMBER or (on and pal.text or pal.stone))
    row.attn:SetText(word)
    Color(row.attn, Tone(pal, tone))
    row.bar:SetShown(mark ~= nil)
    if mark then row.bar:SetColorTexture(mark[1], mark[2], mark[3], 1) end
    row.band:SetShown(index % 2 == 0)
    row.sel:SetShown(selected)
    row.selTop:SetShown(selected)
    row.selBottom:SetShown(selected)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function Redraw() AW.Refresh() end

local function Choose(it)
    RV.Select(it.id)
    local st = RV.State()
    st.leafPage = 1
    Redraw()
end

local function ChangeDestination(it)
    if it.to == "base" then
        A.SetTarget(it.id, "variant")
        Redraw()
        return
    end
    local reach = RV.PromotionReach(it)
    if #reach == 0 then
        A.SetTarget(it.id, "base")
        Redraw()
        return
    end
    R.Interact.Confirm("TWICHUI_LAYOUT_SHARE",
        ("Share \"%s\" with every layout?\n\nIt moves into the shared base, so %s would also get the new value. Nothing is published yet; you can move it back."):format(
            RV.Name(it), table.concat(reach, " and ")),
        function()
            A.SetTarget(it.id, "base")
            Redraw()
        end, { accept = "Share it" })
end

local function Bulk(on)
    local changed, risky = RV.Bulk(on)
    if changed == 0 then return end
    if on and risky > 0 then
        R.Interact.Confirm("TWICHUI_LAYOUT_BULK",
            ("Include %d %s?\n\n%d of them %s a removal or a reset: including one decides what players who have the layout end up with. Nothing is published yet."):format(
                changed, Plural(changed, "change", "changes"), risky, risky == 1 and "is" or "are"),
            function() RV.ApplyBulk(true) Redraw() end, { accept = "Include them" })
        return
    end
    RV.ApplyBulk(on)
    Redraw()
end

local function NextToReview()
    local it = RV.NextNeedingReview()
    local st = RV.State()
    if not it then
        st.note = "Nothing else in this view needs review."
        Redraw()
        return
    end
    st.note = nil
    RV.Select(it.id)
    st.leafPage = 1
    RV.Reveal(it.id)
    Redraw()
end

---------------------------------------------------------------------------
-- Building (once)
---------------------------------------------------------------------------
local function Cycler(parent, width, text, fn, tip)
    local b = kit.Button(parent, text, width, "secondary", fn)
    R.Interact.Tip(b, nil, tip)
    return b
end

local function Swatch(parent, L)
    local t = L.Solid(parent, "OVERLAY", { 1, 1, 1 }, 1)
    t:SetSize(12, 12)
    t:Hide()
    return t
end

function AW.BuildReview(L)
    local content = Content()
    local pal = L.pal
    local W = AW.CONTENT_W
    local rv = { static = {} }
    AW.pool.rv = rv
    local function St(o) rv.static[#rv.static + 1] = o return o end

    rv.summary = St(kit.Text(content, "body", W))
    rv.reassure = St(kit.Text(content, "small", W))
    rv.skipped = kit.Text(content, "small", W - 20)
    rv.searchLabel = St(kit.Text(content, "small", 46))
    rv.searchLabel:SetText("Search")
    rv.search = St(kit.Edit(content, 140, function(text)
        local st = RV.State()
        if st and text ~= st.search then RV.SetFilter("search", text) Redraw() end
    end))
    R.Interact.Tip(rv.search, "Search the changes", "Looks in the names, the setting ids, the change type and the destination. Press Enter to search; clear the box to see everything.")

    rv.status = St(Cycler(content, 138, "", function()
        RV.SetFilter("status", NextKey(RV.STATUSES, RV.State().status)) Redraw()
    end, function()
        local lines = { "Which changes to list. Click for the next." }
        for _, e in ipairs(RV.STATUSES) do lines[#lines + 1] = (e.key == RV.State().status and "> " or "  ") .. e.label end
        lines[#lines + 1] = "Needs review: included changes with a reason to look that you have not marked reviewed. Blocked: included changes the last Check refused."
        return table.concat(lines, "\n")
    end))
    rv.kind = St(Cycler(content, 112, "", function()
        RV.SetFilter("kind", NextKey(RV.KINDS, RV.State().kind)) Redraw()
    end, function()
        local lines = { "Which kind of change to list. Click for the next." }
        for _, e in ipairs(RV.KINDS) do lines[#lines + 1] = (e.key == RV.State().kind and "> " or "  ") .. e.label end
        lines[#lines + 1] = "Reset: a TwichUI setting your profile leaves at its default that the layout sets to something else."
        return table.concat(lines, "\n")
    end))
    rv.layout = St(Cycler(content, 124, "", function()
        local s = A.Session()
        local list = { { key = "all" } }
        for _, v in ipairs(s.variants) do list[#list + 1] = { key = v } end
        RV.SetFilter("layout", NextKey(list, RV.State().layout)) Redraw()
    end, "Lists only the changes that would really change the layout named (after the layers are composed), whichever layer they are stored in. Click for the next layout."))
    rv.sort = St(Cycler(content, 132, "", function()
        RV.SetFilter("sort", NextKey(RV.SORTS, RV.State().sort)) Redraw()
    end, function()
        local lines = { "How the table is ordered. Click for the next." }
        for _, e in ipairs(RV.SORTS) do lines[#lines + 1] = (e.key == RV.State().sort and "> " or "  ") .. e.label end
        lines[#lines + 1] = "The order is kept as it is while you include, leave out, mark or move changes; choosing a filter or a sort puts it in order again."
        return table.concat(lines, "\n")
    end))
    rv.count = St(kit.Text(content, "small", 400))
    rv.clear = St(kit.Button(content, "Clear filters", 100, "secondary", function() RV.ClearFilters() rv.search:SetText("") Redraw() end,
        "Shows every change again: clears the search, the status, the type and the layout. The sort stays."))
    rv.include = St(kit.Button(content, "Include", 190, "secondary", function() Bulk(true) end))
    rv.exclude = St(kit.Button(content, "Leave out", 190, "secondary", function() Bulk(false) end))
    rv.next = St(kit.Button(content, "Next needing review", 150, "secondary", NextToReview,
        "Selects the next included change that has a reason to look and is not marked reviewed, in the order shown."))
    rv.blocked = St(kit.Button(content, "Show blocked", 110, "secondary", function() RV.SetFilter("status", "blocked") Redraw() end,
        "Lists only the included changes the last Check refused."))
    rv.note = St(kit.Text(content, "small", W - 20))
    rv.empty = St(kit.Text(content, "body", W - 20))

    -- the table: a header, then a pool of rows
    rv.head = CreateFrame("Frame", nil, content)
    rv.head:SetSize(ROW_W, 22)
    L.Solid(rv.head, "BACKGROUND", pal.band, 1):SetAllPoints()
    local rule = L.Solid(rv.head, "ARTWORK", pal.bronzeText, 0.55)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)
    rv.headText = {}
    for _, c in ipairs({ { "check", "Include", 56 }, { "name", "Setting", WIDTH.name }, { "kind", "Change", WIDTH.kind }, { "detail", "Details", WIDTH.detail },
        { "dest", "Destination", WIDTH.dest }, { "affects", "Affects", WIDTH.affects }, { "attn", "Attention", WIDTH.attn } }) do
        local fs = Cell(rv.head, "meta", c[3])
        fs:SetPoint("LEFT", rv.head, "LEFT", c[1] == "check" and 4 or X[c[1]], 0)
        fs:SetText(c[2])
        Color(fs, pal.bronzeText)
        rv.headText[c[1]] = fs
    end
    Frames(10)

    rv.rows = {}
    for i = 1, MAX_ROWS do
        local f = CreateFrame("Button", nil, content)
        f:SetSize(ROW_W, ROW_H)
        f:RegisterForClicks("LeftButtonUp")
        local row = { frame = f }
        row.band = L.Solid(f, "BACKGROUND", pal.text, 0.035)
        row.band:SetAllPoints()
        row.hover = L.Solid(f, "BACKGROUND", pal.text, 0.07)
        row.hover:SetAllPoints()
        row.hover:Hide()
        row.sel = L.Solid(f, "BACKGROUND", pal.tealLo, 0.55)
        row.sel:SetAllPoints()
        row.selTop = L.Solid(f, "ARTWORK", pal.tealHi, 0.9)
        row.selTop:SetHeight(1)
        row.selTop:SetPoint("TOPLEFT", 0, 0)
        row.selTop:SetPoint("TOPRIGHT", 0, 0)
        row.selBottom = L.Solid(f, "ARTWORK", pal.tealHi, 0.9)
        row.selBottom:SetHeight(1)
        row.selBottom:SetPoint("BOTTOMLEFT", 0, 0)
        row.selBottom:SetPoint("BOTTOMRIGHT", 0, 0)
        row.sep = L.Solid(f, "ARTWORK", pal.bronzeLo, 0.45)
        row.sep:SetHeight(1)
        row.sep:SetPoint("BOTTOMLEFT", 0, 0)
        row.sep:SetPoint("BOTTOMRIGHT", 0, 0)
        row.bar = L.Solid(f, "OVERLAY", AMBER, 1)
        row.bar:SetWidth(3)
        row.bar:SetPoint("TOPLEFT", 0, 0)
        row.bar:SetPoint("BOTTOMLEFT", 0, 0)
        -- the include box changes inclusion and nothing else (a child button answers its own click; the row never hears it)
        row.check = L.Checkbox(f, function(on)
            if row.it then A.SetInclude(row.it.id, on) end
            Redraw()
        end)
        row.check:SetPoint("LEFT", f, "LEFT", X.check, 0)
        row.name = Cell(f, "body", WIDTH.name)
        row.name:SetPoint("LEFT", f, "LEFT", X.name, 0)
        row.kind = Cell(f, "small", WIDTH.kind)
        row.kind:SetPoint("LEFT", f, "LEFT", X.kind, 0)
        row.detail = Cell(f, "small", WIDTH.detail)
        row.detail:SetPoint("LEFT", f, "LEFT", X.detail, 0)
        row.dest = kit.Button(f, "This layout", WIDTH.dest, "secondary", function() if row.it then ChangeDestination(row.it) end end)
        row.dest:SetHeight(20)
        row.dest:SetPoint("LEFT", f, "LEFT", X.dest, 0)
        R.Interact.Tip(row.dest, "Where this change is stored", function()
            local it = row.it
            if not it then return nil end
            local text = "'This layout' keeps it in the layout being edited. 'Shared base' puts it in the base every layout starts from; the details say what that does to each layout."
            if it.baseOnly then return text, it.rootOnly and "This kind of setting only lives in the shared base." or "Only the shared base can stop naming it." end
            if not it.include then return text, "Include the change to choose." end
            return text
        end)
        row.affects = Cell(f, "small", WIDTH.affects)
        row.affects:SetPoint("LEFT", f, "LEFT", X.affects, 0)
        row.attn = Cell(f, "small", WIDTH.attn)
        row.attn:SetPoint("LEFT", f, "LEFT", X.attn, 0)
        f:SetScript("OnClick", function() if row.it then Choose(row.it) end end)
        R.Interact.Tip(f, nil, function() return RowTip(row) end)
        f:HookScript("OnEnter", function() row.hover:Show() end)
        f:HookScript("OnLeave", function() row.hover:Hide() end)
        f:HookScript("OnHide", function() row.hover:Hide() end)
        f:Hide()
        rv.rows[i] = row
        Frames(16)
    end

    -- the pager
    rv.prev = St(kit.Button(content, "Previous", 90, "secondary", function() local st = RV.State() RV.SetPage(st.page - 1) Redraw() end))
    rv.nextPage = St(kit.Button(content, "Next", 90, "secondary", function() local st = RV.State() RV.SetPage(st.page + 1) Redraw() end))
    rv.range = St(kit.Text(content, "small", 260))
    rv.size = St(Cycler(content, 100, "", function()
        local st = RV.State()
        local sizes, at = RV.PAGE_SIZES, 1
        for i, n in ipairs(sizes) do if n == st.size then at = i end end
        RV.SetPageSize(sizes[(at % #sizes) + 1])
        Redraw()
    end, "How many changes a page lists. The changes themselves are the same."))

    -- the details of one change
    local d = CreateFrame("Frame", nil, content, "BackdropTemplate")
    L.Panel(d)
    d:SetSize(W - 6, 200)
    d:Hide()
    rv.d = d
    d.name = kit.Text(d, "heading", 380)
    d.tech = kit.Text(d, "meta", 420)
    d.review = kit.Button(d, "Mark reviewed", 124, "secondary", function()
        local it = RV.Selected()
        if it then RV.SetReviewed(it.id, not RV.IsReviewed(it)) Redraw() end
    end, "Your own note that you looked at this change as it is now. It is not approval, it does not clear a blocked change, and it is forgotten if the values, the destination or the layouts it affects change.")
    d.close = kit.Button(d, "Close details", 100, "secondary", function() RV.Select(nil) Redraw() end, "Hides the details. The change keeps its place in the table.")
    d.facts = kit.Text(d, "small", W - 40)
    d.layoutLines = {}
    for i = 1, LY.MAX_VARIANTS do d.layoutLines[i] = kit.Text(d, "small", W - 40) end
    d.flagLines = {}
    for i = 1, 8 do d.flagLines[i] = kit.Text(d, "small", W - 40) end
    d.blob = kit.Text(d, "small", W - 40)
    d.note = kit.Text(d, "small", W - 40)
    d.colA = Cell(d, "meta", 250)
    d.colB = Cell(d, "meta", 200)
    d.colC = Cell(d, "meta", 200)
    d.colA:SetText("Setting")
    d.colB:SetText("Before")
    d.colC:SetText("After")
    for _, fs in ipairs({ d.colA, d.colB, d.colC }) do Color(fs, pal.bronzeText) end
    d.raw = kit.Button(d, "Show raw paths", 120, "secondary", function()
        local st = RV.State()
        st.raw = not st.raw
        Redraw()
    end, "Shows each setting by its path inside the module, as EllesmereUI or TwichUI stores it, instead of a readable name.")
    d.leaves = {}
    for i = 1, LEAF_ROWS do
        local f = CreateFrame("Button", nil, d)
        f:SetSize(W - 40, 22)
        local leaf = { frame = f }
        leaf.band = L.Solid(f, "BACKGROUND", pal.text, 0.035)
        leaf.band:SetAllPoints()
        leaf.label = Cell(f, "small", 236)
        leaf.label:SetPoint("LEFT", f, "LEFT", 4, 0)
        leaf.before = Cell(f, "small", 190)
        leaf.after = Cell(f, "small", 190)
        leaf.sb = Swatch(f, L)
        leaf.sa = Swatch(f, L)
        R.Interact.Tip(f, nil, function()
            local lf = leaf.data
            if not lf then return nil end
            return ("%s\n%s\nBefore: %s\nAfter: %s"):format(lf.label, lf.raw ~= "" and ("Path: " .. lf.raw) or "The whole setting", lf.beforeFull, lf.afterFull)
        end)
        f:Hide()
        d.leaves[i] = leaf
        Frames(7)
    end
    d.leafPrev = kit.Button(d, "‹", 26, "secondary", function() local st = RV.State() st.leafPage = math.max(1, (st.leafPage or 1) - 1) Redraw() end)
    d.leafNext = kit.Button(d, "›", 26, "secondary", function() local st = RV.State() st.leafPage = (st.leafPage or 1) + 1 Redraw() end)
    d.leafRange = kit.Text(d, "small", 240)
    Frames(12)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local LEVEL_WORD = { blocked = "Blocked", review = "Review", info = "Note" }
local LEVEL_TONE = { blocked = RED, review = AMBER, info = "dim" }

local function DrawDetails(rv, it, y, st)
    local d = rv.d
    local pal = kit.Look().pal
    local content = Content()
    local detail = RV.Detail(it)
    d:ClearAllPoints()
    d:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    d:Show()
    local x, dy = 12, 10
    local function At(obj, ox, oy) obj:ClearAllPoints() obj:SetPoint("TOPLEFT", d, "TOPLEFT", ox, -oy) end

    d.name:SetText(RV.Name(it))
    At(d.name, x, dy)
    d.tech:SetText("ID: " .. RV.Tech(it))
    At(d.tech, x, dy + kit.Height(d.name) + 2)
    d.close:ClearAllPoints()
    d.close:SetPoint("TOPRIGHT", d, "TOPRIGHT", -10, -8)
    d.review:ClearAllPoints()
    d.review:SetPoint("RIGHT", d.close, "LEFT", -6, 0)
    local reviewed = RV.IsReviewed(it)
    d.review.text:SetText(reviewed and "Reviewed (undo)" or "Mark reviewed")
    dy = dy + kit.Height(d.name) + kit.Height(d.tech) + 10

    local n = it.n
    local counts = ("%s: %s"):format(RV.KIND_LABEL[it.kind], RV.Details(it))
    if n and not n.capped and (n.added > 0 or n.removed > 0) then
        counts = counts .. (" (%d changed, %d added, %d removed)"):format(n.changed, n.added, n.removed)
    end
    d.facts:SetText(("%s.   Stored now in: %s.   Proposed destination: %s.   %s."):format(
        counts, RV.Storage(it), RV.Destination(it), it.include and "Included" or "Left out"))
    At(d.facts, x, dy)
    dy = dy + kit.Height(d.facts) + 6

    local impact = RV.Impact(it)
    for i, line in ipairs(d.layoutLines) do
        local e = impact.byVariant[i]
        line:SetShown(e ~= nil)
        if e then
            line:SetText(("%s: %s."):format(e.title, e.note))
            Color(line, e.changes and pal.text or pal.textDim)
            At(line, x, dy)
            dy = dy + kit.Height(line) + 1
        end
    end
    dy = dy + 6

    local flags = RV.Flags(it)
    local shown = 0
    for _, f in ipairs(flags.list) do
        shown = shown + 1
        local line = d.flagLines[shown]
        if not line then break end
        local text = ("%s: %s"):format(LEVEL_WORD[f.level] or "Note", f.text)
        if #f.evidence > 0 then text = text .. " (" .. table.concat(f.evidence, "; ") .. ")" end
        if f.action then text = text .. " " .. f.action end
        line:SetText(text)
        line:Show()
        Color(line, f.level == "blocked" and RED or f.level == "review" and AMBER or pal.textDim)
        At(line, x, dy)
        dy = dy + kit.Height(line) + 2
    end
    for i = shown + 1, #d.flagLines do d.flagLines[i]:Hide() end
    if shown == 0 then dy = dy + 0 end

    local stale = RV.StaleReason(it)
    local noteText
    if stale then noteText = "You marked this reviewed earlier, but " .. stale .. ". It needs a look again."
    elseif flags.level == "blocked" then noteText = "Marking a change reviewed does not clear a blocked change; the last Check still refuses it."
    elseif it.include and flags.level == "review" and not reviewed then noteText = "Marking it reviewed only records that you looked. Publishing is decided by Check." end
    if RV.IsBlob(it) then
        d.blob:SetText("This module is included and replaced as a whole. The differences below are for inspection: they cannot be included one at a time.")
        d.blob:Show()
        At(d.blob, x, dy + 2)
        dy = dy + kit.Height(d.blob) + 6
    else d.blob:Hide() end
    if noteText then
        d.note:SetText(noteText)
        d.note:Show()
        At(d.note, x, dy)
        dy = dy + kit.Height(d.note) + 6
    else d.note:Hide() end

    -- the leaf table
    local pages = math.max(1, math.ceil(#detail.leaves / LEAF_ROWS))
    st.leafPage = math.max(1, math.min(pages, st.leafPage or 1))
    At(d.colA, x + 4, dy)
    At(d.colB, x + 244, dy)
    At(d.colC, x + 244 + 198, dy)
    d.raw:ClearAllPoints()
    d.raw:SetPoint("TOPRIGHT", d, "TOPRIGHT", -10, -(dy - 4))
    d.raw.text:SetText(st.raw and "Show names" or "Show raw paths")
    dy = dy + 20
    local first = (st.leafPage - 1) * LEAF_ROWS
    for i, leaf in ipairs(d.leaves) do
        local lf = detail.leaves[first + i]
        leaf.data = lf
        leaf.frame:SetShown(lf ~= nil)
        if lf then
            leaf.frame:ClearAllPoints()
            leaf.frame:SetPoint("TOPLEFT", d, "TOPLEFT", x, -dy)
            local tag = lf.kind == "added" and "  [added]" or lf.kind == "removed" and "  [removed]" or ""
            leaf.label:SetText((st.raw and lf.raw ~= "" and lf.raw or lf.label) .. tag)
            Color(leaf.label, pal.text)
            local function Side(fs, sw, text, color, at)
                local ox = at + (color and 16 or 0)
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", leaf.frame, "LEFT", ox, 0)
                fs:SetText(text)
                sw:ClearAllPoints()
                sw:SetPoint("LEFT", leaf.frame, "LEFT", at, 0)
                if color then sw:SetColorTexture(color.r, color.g, color.b, 1) sw:Show() else sw:Hide() end
            end
            Side(leaf.before, leaf.sb, lf.before, lf.beforeColor, 244)
            Side(leaf.after, leaf.sa, lf.after, lf.afterColor, 244 + 198)
            local missing = { ["(missing)"] = true }
            Color(leaf.before, missing[lf.before] and pal.stone or pal.textDim)
            Color(leaf.after, missing[lf.after] and pal.stone or pal.text)
            leaf.band:SetShown(i % 2 == 0)
            dy = dy + 22
        end
    end
    if #detail.leaves == 0 then
        d.leafRange:SetText(it.kind == "default" and "The setting goes back to TwichUI's default." or "No leaf-level differences to list.")
    else
        d.leafRange:SetText(("%d-%d of %d%s"):format(first + 1, math.min(first + LEAF_ROWS, #detail.leaves), detail.total,
            detail.truncated and (" (only the first %d are listed)"):format(RV.MAX_LEAVES) or ""))
    end
    d.leafRange:ClearAllPoints()
    d.leafRange:SetPoint("TOPLEFT", d, "TOPLEFT", x + 70, -(dy + 6))
    d.leafPrev:ClearAllPoints()
    d.leafPrev:SetPoint("TOPLEFT", d, "TOPLEFT", x, -(dy + 2))
    d.leafNext:ClearAllPoints()
    d.leafNext:SetPoint("LEFT", d.leafPrev, "RIGHT", 4, 0)
    d.leafPrev:SetEnabled(st.leafPage > 1)
    d.leafNext:SetEnabled(st.leafPage < pages)
    d.leafPrev:SetShown(pages > 1)
    d.leafNext:SetShown(pages > 1)
    if pages <= 1 then d.leafRange:ClearAllPoints() d.leafRange:SetPoint("TOPLEFT", d, "TOPLEFT", x, -(dy + 6)) end
    dy = dy + 32
    d:SetHeight(dy)
    return y + dy + 8
end

function AW.DrawReview(y)
    local s = A.Session()
    local rv = AW.pool.rv
    local Place = kit.Place
    y = kit.Section("h3", "3. Review the changes", y)
    local function HideAll()
        for _, o in ipairs(rv.static) do o:Hide() end
        rv.head:Hide()
        rv.skipped:Hide()
        rv.d:Hide()
        for _, row in ipairs(rv.rows) do row.frame:Hide() end
    end
    if not s.items then
        HideAll()
        rv.summary:SetText("Capture first. The changes appear here as a table: what changed, where each one will be stored, which layouts it changes, and its values before and after.")
        rv.summary:Show()
        Place(rv.summary, 0, y)
        return y + kit.Height(rv.summary) + 10
    end
    local st = RV.State()
    local page = RV.Page()
    local c = RV.Counts()
    for _, o in ipairs(rv.static) do o:Show() end

    rv.summary:SetText(RV.SummaryText())
    Place(rv.summary, 0, y)
    y = y + kit.Height(rv.summary) + 2
    rv.reassure:SetText("Changes stay in this draft until you publish. Nothing here changes a profile.")
    Place(rv.reassure, 0, y)
    y = y + kit.Height(rv.reassure) + 8

    -- the toolbar
    Place(rv.searchLabel, 0, y + 5)
    Place(rv.search, 48, y)
    if not rv.search:HasFocus() then rv.search:SetText(st.search) end
    local x = 48 + 140 + 6
    for _, o in ipairs({ { rv.status, "Status: " .. LabelOf(RV.STATUSES, st.status), 138 },
        { rv.kind, "Type: " .. (st.kind == "all" and "All" or LabelOf(RV.KINDS, st.kind)), 112 },
        { rv.layout, "Affects: " .. (st.layout == "all" and "All" or RV.Short(st.layout)), 124 },
        { rv.sort, "Sort: " .. LabelOf(RV.SORTS, st.sort), 132 } }) do
        o[1].text:SetText(o[2])
        Place(o[1], x, y)
        x = x + o[3] + 6
    end
    rv.layout:SetShown(#s.variants > 1)
    y = y + 30

    local filtered = RV.Filtered()
    rv.count:SetText(filtered and ("Showing %d of %d changes. Filters are on."):format(page.total, c.changes) or ("%d %s."):format(c.changes, Plural(c.changes, "change", "changes")))
    Color(rv.count, filtered and AMBER or kit.Look().pal.textDim)
    Place(rv.count, 0, y + 5)
    rv.clear:SetEnabled(filtered)
    Place(rv.clear, 410, y)
    y = y + 30

    -- bulk actions: exactly the changes in the order, on every page
    local on = RV.Bulk(true)
    local off = RV.Bulk(false)
    local scope = filtered and ("%d filtered %s"):format(page.total, Plural(page.total, "change", "changes")) or ("all %d %s"):format(page.total, Plural(page.total, "change", "changes"))
    rv.include.text:SetText("Include " .. scope)
    rv.exclude.text:SetText("Leave out " .. scope)
    rv.include:SetEnabled(on > 0)
    rv.exclude:SetEnabled(off > 0)
    R.Interact.Tip(rv.include, "Include", ("Includes the %d %s listed by the current filters, on every page, not only this one. %d of them %s not included yet."):format(
        page.total, Plural(page.total, "change", "changes"), on, on == 1 and "is" or "are"))
    R.Interact.Tip(rv.exclude, "Leave out", ("Leaves out the %d %s listed by the current filters, on every page. A change left out is not published; nothing is deleted."):format(
        page.total, Plural(page.total, "change", "changes")))
    Place(rv.include, 0, y)
    Place(rv.exclude, 196, y)
    Place(rv.next, 392, y)
    rv.blocked:SetShown(c.blocked > 0)
    rv.blocked.text:SetText(("Show blocked (%d)"):format(c.blocked))
    rv.blocked:SetWidth(130)
    Place(rv.blocked, 548, y)
    y = y + 30
    if st.note then
        rv.note:SetText(st.note)
        rv.note:Show()
        Place(rv.note, 0, y)
        y = y + kit.Height(rv.note) + 4
    else rv.note:Hide() end

    -- the table
    rv.head:Show()
    rv.head:ClearAllPoints()
    rv.head:SetPoint("TOPLEFT", Content(), "TOPLEFT", 0, -y)
    y = y + 22
    for i, row in ipairs(rv.rows) do
        local it = page.rows[i]
        row.frame:SetShown(it ~= nil)
        if it then
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", Content(), "TOPLEFT", 0, -y)
            PaintRow(row, it, i, st.selected == it.id)
            y = y + ROW_H
        else row.it = nil end
    end
    if page.total == 0 then
        rv.empty:SetText(filtered and "No changes match these filters. Clear them to see all of the changes."
            or "The captured profiles do not differ from the starting package, so there is nothing to review.")
        rv.empty:Show()
        Place(rv.empty, 8, y + 8)
        y = y + kit.Height(rv.empty) + 18
    else rv.empty:Hide() end
    y = y + 6

    -- the pager
    rv.prev:SetEnabled(page.page > 1)
    rv.nextPage:SetEnabled(page.page < page.pages)
    rv.range:SetText(page.total == 0 and "0 of 0" or ("%d-%d of %d.  Page %d of %d."):format(page.from, page.to, page.total, page.page, page.pages))
    rv.size.text:SetText("Rows: " .. st.size)
    Place(rv.prev, 0, y)
    Place(rv.nextPage, 96, y)
    Place(rv.range, 200, y + 5)
    Place(rv.size, 470, y)
    y = y + 32

    -- skipped settings and the details
    local skipped = A.Skipped()
    if #skipped > 0 then
        rv.skipped:SetText(("%d %s left alone because a wizard choice (such as the accent colour) sets %s."):format(
            #skipped, #skipped == 1 and "setting is" or "settings are", #skipped == 1 and "it" or "them"))
        rv.skipped:Show()
        Place(rv.skipped, 0, y)
        y = y + kit.Height(rv.skipped) + 6
    else rv.skipped:Hide() end
    local picked = RV.Selected()
    if picked then y = DrawDetails(rv, picked, y, st) else rv.d:Hide() end
    return y + 6
end
