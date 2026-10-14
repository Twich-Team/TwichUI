-- TwichUI: Saved Data Explorer window (/tui saved)
-- Sources on the left (settings, backups, sharing, feature data), the chosen one as a tree in the
-- middle, opened a level and a page at a time, and the chosen entry's details and copy box on the
-- right. Read-only: nothing here changes, applies, restores or sends anything. Drawn with TwichUI's own
-- look (Look.lua, the settings window's), so it looks finished without any other addon.
-- Built on first open; while closed it holds nothing and does nothing.

local R = TwichUI
local EX, SD, ST, SH = R.Explorer, R.StoredData, R.Setups, R.Share
local XW = {}
R.ExplorerWindow = XW

-- The Chronicle's drawing helpers and TwichUI's palette (Look.lua); both load after this file, so they are
-- looked up when the window is first built.
local S, K, L
local WIDTH, HEIGHT = 1000, 640
local LEFT_W, RIGHT_W = 240, 290
local MID_X = 16 + LEFT_W + 12
local MID_W = WIDTH - MID_X - 12 - RIGHT_W - 16
local SOURCE_H, TREE_H = 30, 18
local GREY = R.GREY
local WARN = "|cffd98a70"          -- a warning in running text (semantic: kept)
local KEY_COLOR, NUM_COLOR, GOLD   -- keys, numbers and notes in running text: palette escapes, set when built

local f                          -- the window
local sourceId = "settings"      -- the chosen source
local tree                       -- its tree (holds the source's tables while the window is open)
local selected                   -- the chosen entry (a tree node)
local reveal = false             -- personal-looking values shown (this window, until it closes)
local mode = "tree"              -- "tree" or "results"
local search                     -- the last search's results
local searchToken = 0
local readAt                     -- when the tree was read from memory
local summary                    -- { reveal, lines }: the chosen source's summary, worked out once per read
local preparing                  -- a redraw is queued
local reread                     -- ... and the source is to be read again if it changed

-- A | is doubled for anything shown as text, so codes and links are shown as written, never used.
local function Esc(s) return (s:gsub("|", "||")) end

-- The palette role each of the game's font objects takes (the sizes stay the game's own).
local ROLE = {
    GameFontNormalLarge = "text", GameFontNormal = "text", GameFontNormalSmall = "bronzeText",
    GameFontHighlight = "text", GameFontHighlightSmall = "textDim", GameFontDisableSmall = "stone",
}

local function Text(parent, template)
    template = template or "GameFontHighlight"
    local fs
    if template == "GameFontNormalLarge" then
        fs = L.Text(parent, "title")      -- the title face, as the settings window's
    else
        fs = parent:CreateFontString(nil, "OVERLAY", template)
    end
    fs:SetJustifyH("LEFT")
    local c = K[ROLE[template] or "text"]
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

-- A palette color as an inline escape.
local function Hex(c)
    return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

local function Color(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function When(t) return t and date("%H:%M:%S", t) or "?" end

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------
-- A recessed list that only makes the rows on screen; init(row, data) fills a row.
local function List(parent, w, h, rowH, init)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(w, h)
    L.Well(box, 0.9)
    box.scroll = CreateFrame("Frame", nil, box, "WowScrollBoxList")
    box.scroll:SetPoint("TOPLEFT", 4, -4)
    box.scroll:SetPoint("BOTTOMRIGHT", -16, 4)
    box.bar = CreateFrame("EventFrame", nil, box, "MinimalScrollBar")
    box.bar:SetPoint("TOPLEFT", box.scroll, "TOPRIGHT", 4, 0)
    box.bar:SetPoint("BOTTOMLEFT", box.scroll, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(rowH)
    view:SetElementInitializer("Button", init)
    ScrollUtil.InitScrollBoxListWithScrollBar(box.scroll, box.bar, view)
    L.MinimalScrollBar(box.bar)
    box.empty = Text(box, "GameFontDisableSmall")
    box.empty:SetPoint("TOPLEFT", 14, -14)
    box.empty:SetPoint("TOPRIGHT", -26, -14)
    box.empty:SetJustifyV("TOP")
    box.empty:SetSpacing(2)
    return box
end

local function SetRows(box, rows, emptyText, keepScroll)
    box.rows = rows
    box.scroll:SetDataProvider(CreateDataProvider(rows), keepScroll and true or false)
    box.empty:SetText(#rows == 0 and (emptyText or "") or "")
end

-- A recessed box of text that can be selected and copied but not changed.
local function TextBox(parent, w, h)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(w, h)
    L.Well(box, 0.9)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -24, 6)
    L.ScrollBar(scroll)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetWidth(w - 34)
    edit:SetTextInsets(2, 2, 2, 2)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    -- Typing puts the text back: this box is for reading and copying.
    edit:SetScript("OnTextChanged", function(e, user)
        if user then
            e:SetText(e.fixed or "")
            e:HighlightText()
        end
    end)
    scroll:SetScrollChild(edit)
    box.edit, box.scroll = edit, scroll
    function box:Set(text)
        if text == edit.fixed then return end     -- unchanged: keep the reader's place
        edit.fixed = text
        edit:SetText(text)
        scroll:SetVerticalScroll(0)
    end
    return box
end

---------------------------------------------------------------------------
-- What is shown
---------------------------------------------------------------------------
local function Source() return EX.Source(sourceId) end

-- Whether the tree still shows the source's current table. When not, the window reads it again.
local function Live()
    local s = Source()
    local root = s and s.Root()
    return tree ~= nil and root ~= nil and rawequal(root, tree.root.value)
end

-- Received setups are named after the friend, Undo copies after the character: hidden until revealed.
local function SourceLabel(s)
    if s.kind == "received" and not reveal then return "Received setup" end
    return s.label
end

local function SourceDetail(s)
    if s.kind == "undo" and not reveal then return "for one character (name hidden)" end
    return s.detail or ""
end

local function RowKey(node)
    local why = not reveal and EX.PersonalKey(node.key, node.parent and node.parent.key)
    if why then return GREY .. EX.Hidden(why) .. "|r" end
    local part = EX.PathPart(node.key):gsub("^%.", "")
    local s, cut = EX.Clip(part, 80)
    return KEY_COLOR .. Esc(s) .. (cut and "..." or "") .. "|r"
end

local function TableNote(node)
    if node.hiddenTable then return "hidden by the game" end
    if node.loop then return "contains itself" end
    local note = EX.ShapeText(node.count, node.more, node.shape)
    if node.sharedWith then note = note .. ", same table as " .. EX.NodePath(node.sharedWith, reveal) end
    if node.depth >= EX.MAX_DEPTH then note = note .. ", too deep to open here" end
    return note
end

local function RowValue(node)
    local v = node.value
    if type(v) == "table" then return GREY .. "{ " .. Esc(TableNote(node)) .. " }|r" end
    local why = EX.NodeHidden(node, reveal)
    if why then return GREY .. EX.Hidden(why) .. "|r" end
    local t = type(v)
    local text = Esc(EX.ValueText(v, 160))
    if t == "number" or t == "boolean" then return NUM_COLOR .. text .. "|r" end
    if t == "string" then return text end
    return GREY .. text .. "|r"
end

-- A search result's path, with personal-looking keys hidden unless revealed.
local function ResultPath(r)
    return EX.MaskedPath(reveal and tree.root.path or (tree.root.maskedPath or tree.root.path), r.keys, reveal)
end

-- The value a result points at now (nil when it is gone), and its table.
local function ResultValue(r)
    local t, parent = tree.root.value, nil
    for _, k in ipairs(r.keys) do
        if type(t) ~= "table" then return nil, false end
        parent = t
        t = rawget(t, k)
    end
    return t, true, parent
end

---------------------------------------------------------------------------
-- Details on the right
---------------------------------------------------------------------------
local function ShareReport(lines)
    local p = EX.preview
    local function Add(s) lines[#lines + 1] = s end
    if not p then return end
    local mine = p.pack
    Add("OUTGOING SHARE: EXACTLY WHAT SEND SENDS")
    Add(("Built at %s from your saved setup (version %s, saved %s) by the sharing code's own message builders. Nothing was sent, no transfer was started."):format(
        When(p.made), tostring(p.version or "?"), mine.created and date("%b %d %Y, %H:%M", mine.created) or "date not recorded"))
    local stale = EX.PreviewStale(p)
    if stale then Add("STALE: " .. stale) end
    Add("As for a friend who has none of it yet. A friend who already has some parts is sent only the changed ones; the keep list always names them all.")
    Add("")
    Add("MESSAGES")
    Add(("offer: %s once packed, plus the recipient's name, which is added as it goes out (to). Its id is drawn when you send; zeros stand in for it here."):format(
        p.offerBytes and ("about " .. ST.FormatSize(p.offerBytes)) or "size unknown"))
    if p.encodeError then
        Add("data: couldn't be packed here (" .. p.encodeError .. "). Sending would fail the same way.")
    elseif p.encoded then
        Add(("data: %s packed (serialized and compressed), sent over %d %s as about %s addon messages."):format(
            ST.FormatSize(p.encoded), p.lanes, p.lanes == 1 and "lane" or "lanes", SD.Num(p.messages)))
    else
        Add("data: measuring its packed size...")
    end
    Add("")
    local c = EX.ShareContents(p)
    Add("INCLUDED")
    if #c.addons == 0 then Add("No addon settings.") end
    for _, a in ipairs(c.addons) do
        Add(("%s: %s (about %s)"):format(a.title, table.concat(a.tables, ", "), ST.FormatSize(a.bytes)))
    end
    if c.eui then
        Add(("EllesmereUI profile \"%s\"%s: %s characters, exported by EllesmereUI itself."):format(
            c.eui.name or "?", c.eui.version and (" (EllesmereUI " .. c.eui.version .. ")") or "", SD.Num(c.eui.chars)))
    end
    if c.editMode then Add(("Edit Mode layout \"%s\": %s characters."):format(c.editMode.name or "?", SD.Num(c.editMode.chars))) end
    Add(("Recommended addons: %d (names, versions and download links)."):format(c.recommended))
    Add("")
    Add("ABOUT YOU, IN THE MESSAGES")
    for _, id in ipairs(c.identity) do
        local v = id[2]
        local shown = type(v) ~= "string" and "not set" or (reveal and v or EX.Hidden("a character's name"))
        Add(("%s = %s: %s"):format(id[1], shown, id[3]))
    end
    Add("")
    Add("LOOKS PERSONAL")
    local found = p.personal
    if not found then
        Add("Checking the messages...")
    else
        Add(("%d keys or values in the messages look like character names, ids or your notes%s. %s"):format(
            found.count, found.cut and " (checked the first part only)" or "",
            found.count > 0 and (reveal and "They are shown." or "They are hidden on screen, but they are in the messages and are sent.") or ""))
        for _, e in ipairs(found.examples) do
            Add(("  %s: %s"):format(EX.MaskedPath("(share preview)", e.keys, reveal), e.why))
        end
        if found.count > #found.examples then Add(("  and %d more"):format(found.count - #found.examples)) end
        if found.count > 0 then
            Add("Addons often keep sections per character (profile choices, per-character settings). Those go with the addon's settings as the addon saved them.")
        end
    end
    Add("")
    Add("NOT INCLUDED")
    if #c.excluded > 0 then
        Add("Found by your last settings scan, not in the saved setup:")
        for _, e in ipairs(c.excluded) do Add(("  %s: %s"):format(e.name, e.why)) end
    end
    for _, rule in ipairs(c.rules) do Add("- " .. rule) end
    local notSaved, notTicked = EX.SelectionDrift()
    if #notSaved + #notTicked > 0 then
        Add("")
        Add("YOUR TICKS")
        if #notSaved > 0 then Add("Ticked in Share setup but not saved: " .. table.concat(notSaved, ", ")) end
        if #notTicked > 0 then Add("Saved but no longer ticked: " .. table.concat(notTicked, ", ")) end
        Add("Send uses the saved setup until you press Save setup again.")
    end
    Add("")
    Add("SENDING")
    local transport = SH.Transport()
    Add(("Sending by %s. %s"):format(SH.TRANSPORT_LABEL[transport], SH.TRANSPORT_HELP[transport]))
end

-- The summary sizes the whole source, so it is worked out when the source is read, not on every redraw.
local function Summary(s, root)
    if not (summary and summary.reveal == reveal) then
        summary = { reveal = reveal, lines = EX.Summary(s, root, reveal) }
    end
    return summary.lines
end

local function SourceReport()
    local s = Source()
    local lines = {}
    if not s then return "That source isn't there any more." end
    local root = s.Root()
    lines[#lines + 1] = SourceLabel(s):upper()
    lines[#lines + 1] = s.scope
    lines[#lines + 1] = ""
    if s.kind == "preview" then
        ShareReport(lines)
    elseif root ~= nil then
        for _, l in ipairs(Summary(s, root)) do lines[#lines + 1] = l[1] .. ": " .. l[2] end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Choose an entry in the middle to see it here."
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Read from memory: the tables the game loaded from TwichUI's saved variables, as they are now. Changes reach the file on disk when you reload or log out; an addon can't read the file itself."
    return table.concat(lines, "\n")
end

local function NodeReport(node)
    local lines = {}
    local function Add(s) lines[#lines + 1] = s end
    local v = node.value
    Add("PATH")
    Add(EX.NodePath(node, reveal))
    Add("")
    Add("TYPE")
    if EX.IsSecret(v) then
        Add("secret: " .. EX.TypeNote(v))
    elseif type(v) == "table" then
        Add("table: " .. TableNote(node))
        Add(EX.TypeNote(v))
        if node.shape == "list" then Add("A list: keys 1 to " .. node.count .. ".")
        elseif node.shape == "gaps" then Add("Numbered keys with gaps: not a plain list.")
        elseif node.shape == "keyed" then Add("Keyed: no list positions.")
        elseif node.shape == "mixed" then Add("Both list positions and other keys.") end
    else
        Add(type(v) .. ": " .. EX.TypeNote(v))
    end
    if not node.isRoot then
        local k = node.key
        Add("")
        Add("KEY")
        local kt = type(k)
        local why = not reveal and EX.PersonalKey(k, node.parent and node.parent.key)
        if why then Add(EX.Hidden(why))
        elseif kt == "string" then Add(EX.Quote(k) .. "  (text" .. (tonumber(k) and ", not the number " .. k or "") .. ")")
        elseif kt == "number" then Add(EX.NumText(k) .. "  (a number" .. (k >= 1 and k == math.floor(k) and ", a list position" or "") .. ")")
        else Add(EX.ValueText(k) .. "  (" .. kt .. ")") end
    end
    if type(v) ~= "table" then
        Add("")
        Add("VALUE")
        local text, hidden, cut = EX.ValueCopy(node, reveal)
        if hidden then
            Add(text)
            Add("Hidden because it looks personal. It is stored here; turn on Reveal to see it.")
        elseif type(v) == "string" then
            Add(v == "" and '""  (empty text: a stored value, not a missing one)' or text)
            Add(("%s bytes%s"):format(SD.Num(#v), cut and (", showing the first " .. ST.FormatSize(EX.DETAIL_BYTES)) or ""))
        else
            Add(text)
        end
    else
        if node.loop then Add("") Add("It contains itself, so it isn't opened again. Copies write it as a reference.") end
        if node.sharedWith then Add("") Add("The same table is also at " .. EX.NodePath(node.sharedWith, reveal) .. ". It is one table, not a copy; copies write it once.") end
        if node.hiddenTable then Add("") Add("The game keeps this table hidden from addons.") end
        if getmetatable(v) ~= nil then Add("") Add("It has a metatable, so it isn't plain saved data. Only its own entries are shown; none of its code runs.") end
    end
    if Source() and Source().kind == "preview" then
        Add("")
        Add("This is part of the message Send makes. " .. (EX.PreviewStale() and "The preview is stale; refresh it." or ""))
    end
    return table.concat(lines, "\n")
end

local function ShowDetails()
    if not f then return end
    local ok, text = pcall(function()
        if selected and not selected.isRoot then return NodeReport(selected) end
        return SourceReport()
    end)
    if not ok then
        geterrorhandler()(text)
        text = "This couldn't be shown. Nothing was changed."
    end
    f.details:Set(Esc(text))
end

---------------------------------------------------------------------------
-- The middle: source heading, notices, tree or search results
---------------------------------------------------------------------------
local function Banner()
    local s = Source()
    if not s then return WARN .. "That source isn't there any more: it was deleted or replaced. Choose another on the left.|r" end
    if s.kind == "preview" then
        if not EX.preview then return WARN .. (f.previewWhy or "No preview.") .. "|r" end
        local stale = EX.PreviewStale()
        if stale then return WARN .. stale .. " Press Refresh.|r" end
        local found = EX.preview.personal
        if found and found.count > 0 and not reveal then
            return WARN .. ("%d personal-looking values are hidden on screen. They are in these messages and are sent. Reveal to review them.|r"):format(found.count)
        end
        return GREY .. "The real messages, built by the code that sends them. Nothing is sent from here.|r"
    end
    if s.Root() == nil then
        return WARN .. "This isn't there any more: it was deleted, or replaced by a newer one. Choose another on the left.|r"
    end
    if not reveal and s.personal then return GREY .. "Personal-looking values are hidden. Reveal shows them in this window only.|r" end
    return ""
end

local function Status()
    if mode == "results" and search then
        local n = #search.results
        local text = ("%d %s for \"%s\""):format(n, n == 1 and "match" or "matches", Esc(search.query))
        if search.full then text = text .. (", the first %d; narrow the search to see others"):format(EX.SEARCH_RESULTS) end
        if search.cut then text = text .. (", searched the first %s entries only"):format(SD.Num(EX.SEARCH_VISITS)) end
        return text .. ". Click one to show it in the tree."
    end
    if EX.Busy("search") then return "Searching..." end
    if not tree then return "" end
    local text = "Read at " .. When(readAt) .. ". Refresh reads it again."
    if search and #search.results > 0 then text = text .. "  " .. GOLD .. "Search results are kept: clear the search box to forget them.|r" end
    return text
end

local function RenderHead()
    local s = Source()
    f.head:SetText(s and Esc(SourceLabel(s)) or "")
    f.path:SetText(s and Esc(EX.PathOf(s, reveal) or "") or "")
    local lines = {}
    if s then
        local root = s.Root()
        if s.kind == "preview" and EX.preview then
            local p = EX.preview
            lines[#lines + 1] = ("Your saved setup, version %s · %d tables, %s"):format(tostring(p.version or "?"), p.want,
                p.encoded and ("about " .. ST.FormatSize(p.encoded) .. " packed") or "measuring...")
            lines[#lines + 1] = "Sending by " .. SH.TRANSPORT_LABEL[SH.Transport()]
        elseif root ~= nil then
            for i, l in ipairs(Summary(s, root)) do
                if i <= 4 then lines[#lines + 1] = GREY .. l[1] .. ":|r " .. Esc(l[2]) end
            end
        end
    end
    f.summary:SetText(table.concat(lines, "\n"))
    f.banner:SetText(Banner())
    f.status:SetText(Status())
    f.showResults:SetShown(mode == "tree" and search ~= nil and #search.results > 0)
end

local function TreeRows()
    if mode == "results" and search then
        local rows = {}
        for _, r in ipairs(search.results) do rows[#rows + 1] = { result = r } end
        return rows, "Nothing matches."
    end
    if not tree then return {}, "" end
    if type(tree.root.value) ~= "table" then
        return {}, "Value: " .. Esc(EX.ValueText(tree.root.value, 1000))
    end
    return tree:Rows(), "Empty."
end

local function RenderTree(keepScroll)
    if not f then return end
    local ok, rows, empty = pcall(TreeRows)
    if not ok then
        geterrorhandler()(rows)
        rows, empty = {}, "This couldn't be shown. Nothing was changed."
    end
    SetRows(f.tree, rows, empty, keepScroll)
end

local function ScrollTo(node)
    for i, d in ipairs(f.tree.rows or {}) do
        if d.node == node then
            if f.tree.scroll.ScrollToElementDataIndex then
                f.tree.scroll:ScrollToElementDataIndex(i, ScrollBoxConstants and ScrollBoxConstants.AlignCenter or 0.5)
            end
            return
        end
    end
end

---------------------------------------------------------------------------
-- Reading a source
---------------------------------------------------------------------------
-- Reads the chosen source afresh, keeping what was open and chosen where it still exists.
local function Load(keepState)
    if not keepState then EX.Cancel("search") end
    local s = Source()
    local openPaths = keepState and tree and tree.openPaths
    local keys = keepState and selected and not selected.isRoot and EX.KeysOf(selected)
    tree, selected, summary = nil, nil, nil
    if s and s.kind == "preview" and not (keepState and EX.preview and not EX.PreviewStale()) then
        local p, why = EX.BuildPreview()
        f.previewWhy = why
        if p then
            EX.FindPersonal(p.root, "(share preview)", function(found)
                if EX.preview ~= p then return end
                p.personal = found or { count = 0, examples = {} }
                if f and f:IsShown() and Source() and Source().kind == "preview" then RenderHead(); ShowDetails() end
            end)
        end
    end
    local root = s and s.Root()
    if root ~= nil then
        tree = EX.NewTree(root, EX.PathOf(s), openPaths)
        tree.root.maskedPath = s.masked
        readAt = time()
        if keys then selected = tree:Reveal(keys) end
    end
    -- Search results stay on a refresh; each is looked up afresh when shown.
    if not keepState then search, mode = nil, "tree" end
end

local function Choose(id)
    if id ~= sourceId then
        if Source() and Source().kind == "preview" then EX.ReleasePreview() end
        sourceId = id
        search, mode = nil, "tree"
        searchToken = searchToken + 1
        f.search:SetText("")
    end
    Load(false)
    XW.Render()
end

---------------------------------------------------------------------------
-- Left: the sources
---------------------------------------------------------------------------
local function SourceTip(row)
    local s = row.data.source
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(Esc(SourceLabel(s)), 1, 1, 1)
    GameTooltip:AddLine(Esc(s.scope), nil, nil, nil, true)
    if s.Root() == nil then GameTooltip:AddLine("Not there any more.", 0.85, 0.55, 0.45, true) end
    GameTooltip:Show()
end

-- A row's hover wash and divider in the palette: a faint ivory wash, a neutral line.
local function RowArt(row)
    S.RowArt(row, K)
    row.hover:SetColorTexture(K.text[1], K.text[2], K.text[3], 0.05)
end

local function InitSource(row, d)
    if not row.label then
        RowArt(row)
        row.sel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(K.teal[1], K.teal[2], K.teal[3], 0.16)   -- the chosen one: the accent
        row.label = Text(row, "GameFontHighlight")
        row.label:SetPoint("TOPLEFT", 10, -3)
        row.label:SetPoint("RIGHT", -6, 0)
        row.label:SetWordWrap(false)
        row.detail = Text(row, "GameFontDisableSmall")
        row.detail:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
        row.detail:SetPoint("RIGHT", -6, 0)
        row.detail:SetWordWrap(false)
        row:SetScript("OnClick", function(self) if self.data.source then Choose(self.data.source.id) end end)
        row:SetScript("OnEnter", function(self) if self.data.source then self.hover:Show(); SourceTip(self) end end)
        row:SetScript("OnLeave", function(self) self.hover:Hide(); GameTooltip_Hide() end)
    end
    row.data = d
    if d.group then
        row.sel:Hide()
        row.line:Hide()
        row.label:SetFontObject("GameFontNormalSmall")
        row.label:ClearAllPoints()
        row.label:SetPoint("BOTTOMLEFT", 8, 4)
        row.label:SetPoint("RIGHT", -6, 0)
        row.label:SetText(d.group:upper())
        Color(row.label, K.bronzeText)
        row.detail:SetText("")
        return
    end
    local s = d.source
    row.line:Show()
    row.sel:SetShown(s.id == sourceId)
    row.label:SetFontObject("GameFontHighlight")
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", 14, -3)
    row.label:SetPoint("RIGHT", -6, 0)
    row.label:SetText(Esc(SourceLabel(s)))
    Color(row.label, s.Root() ~= nil and K.text or K.stone)
    row.detail:SetText(Esc(SourceDetail(s)))
    Color(row.detail, K.stone)
end

local function RenderSources()
    local rows, group = {}, nil
    for _, s in ipairs(EX.Sources()) do
        if s.group ~= group then
            group = s.group
            rows[#rows + 1] = { group = group }
        end
        rows[#rows + 1] = { source = s }
    end
    SetRows(f.sources, rows, nil, true)
end

---------------------------------------------------------------------------
-- Middle: the tree
---------------------------------------------------------------------------
local function OpenResult(r)
    if not Live() then XW.Refresh() return end
    local node = tree:Reveal(r.keys)
    mode = "tree"
    if not node then
        RenderTree()
        f.status:SetText(WARN .. "That entry isn't there any more.|r")
        return
    end
    selected = node
    RenderTree()
    ScrollTo(node)
    RenderHead()
    ShowDetails()
end

local function TreeClick(row)
    local d = row.data
    if not Live() then XW.Refresh() return end
    if d.result then OpenResult(d.result) return end
    if d.more then
        tree:More(d.more)
    elseif d.node then
        selected = d.node
        if type(d.node.value) == "table" then tree:Toggle(d.node) end
        ShowDetails()
    else
        return
    end
    RenderTree(true)
end

local function TreeTip(row)
    local d = row.data
    if not d.node or d.node.isRoot then return end
    GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
    GameTooltip:SetText(Esc(EX.NodePath(d.node, reveal)), 1, 1, 1, 1, true)
    if type(d.node.value) == "table" then
        local _, why = tree:CanOpen(d.node)
        if why then GameTooltip:AddLine(why, 0.8, 0.7, 0.6, true) end
        if d.node.unsorted then GameTooltip:AddLine("Too many entries to sort; shown in stored order.", 0.7, 0.7, 0.7, true) end
    end
    GameTooltip:Show()
end

local function InitTree(row, d)
    if not row.label then
        RowArt(row)
        row.line:Hide()
        row.sel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(K.teal[1], K.teal[2], K.teal[3], 0.16)   -- the chosen one: the accent
        row.label = Text(row, "GameFontHighlightSmall")
        row.label:SetWordWrap(false)
        row:SetScript("OnClick", TreeClick)
        row:SetScript("OnEnter", function(self) self.hover:Show(); TreeTip(self) end)
        row:SetScript("OnLeave", function(self) self.hover:Hide(); GameTooltip_Hide() end)
    end
    row.data = d
    row.label:ClearAllPoints()
    row.label:SetPoint("RIGHT", -6, 0)
    if d.result then
        row.sel:Hide()
        row.label:SetPoint("LEFT", 6, 0)
        local v, there, parent = ResultValue(d.result)
        local shown
        if not there then shown = GREY .. "(not there any more)|r"
        elseif type(v) == "table" then shown = GREY .. "{ table }|r"
        else
            local k = d.result.keys[#d.result.keys]
            local why = not reveal and EX.PersonalValue(k, v, parent)
            shown = why and (GREY .. EX.Hidden(why) .. "|r") or Esc(EX.ValueText(v, 80))
        end
        row.label:SetText(KEY_COLOR .. Esc(EX.Clip(ResultPath(d.result), 160)) .. "|r  " .. shown)
        return
    end
    if d.more then
        row.sel:Hide()
        row.label:SetPoint("LEFT", 6 + d.more.depth * 12, 0)
        local left = #d.more.keys - d.more.limit
        row.label:SetText(("%s+  Show %d more (%s left)|r"):format(GOLD, math.min(EX.PAGE, left), SD.Num(left)))
        return
    end
    if d.hiddenOf then
        row.sel:Hide()
        row.label:SetPoint("LEFT", 6 + d.hiddenOf.depth * 12, 0)
        row.label:SetText(("%s%d entries hidden by the game|r"):format(GREY, d.hiddenOf.hidden))
        return
    end
    local node = d.node
    row.sel:SetShown(node == selected)
    row.label:SetPoint("LEFT", 6 + (node.depth - 1) * 12, 0)
    local mark = "   "
    if type(node.value) == "table" and tree:CanOpen(node) then mark = node.open and "-  " or "+  " end
    row.label:SetText(GREY .. mark .. "|r" .. RowKey(node) .. "  " .. RowValue(node))
end

---------------------------------------------------------------------------
-- Search: waits for typing to pause, then runs a slice at a time
---------------------------------------------------------------------------
local function RunSearch()
    local q = f.search:GetText() or ""
    if q:gsub("%s", "") == "" or not tree then
        EX.Cancel("search")
        search, mode = nil, "tree"
        RenderTree()
        RenderHead()
        return
    end
    if not Live() then XW.Refresh() end
    if not tree then return end
    local token = searchToken
    EX.Search(tree.root.value, tree.root.path, q, function(result)
        if token ~= searchToken or not (f and f:IsShown()) or not result then return end
        search, mode = result, "results"
        RenderTree()
        RenderHead()
    end)
    RenderHead()
end

local function SearchChanged(box, user)
    f.searchHint:SetShown(box:GetText() == "" and not box:HasFocus())
    if not user then return end
    searchToken = searchToken + 1
    local token = searchToken
    C_Timer.After(0.3, function()
        if token == searchToken and f and f:IsShown() then RunSearch() end
    end)
end

---------------------------------------------------------------------------
-- Copying
---------------------------------------------------------------------------
local function Copy(kind)
    local node = selected or (tree and tree.root)
    if not node then
        f.copy:Set("")
        f.copyNote:SetText("Nothing chosen to copy.")
        return
    end
    if not Live() then XW.Refresh() return end
    local text, note = EX.CopyText(kind, node, reveal)
    f.copy:Set(Esc(text))
    f.copy.edit:SetFocus()
    f.copy.edit:HighlightText()
    f.copyNote:SetText(note .. " Selected: press Ctrl+C to copy.")
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function ToolButton(parent, label, w, onClick, tip)
    local b = L.Button(parent, label, w, "secondary", onClick)
    b:SetHeight(22)
    if tip then
        b:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", GameTooltip_Hide)
    end
    return b
end

local function Build()
    S = R.ChronicleStyle
    L = R.Look
    K = L.pal
    KEY_COLOR, NUM_COLOR, GOLD = Hex(K.bronzeText), Hex(K.tealHi), Hex(K.bronzeText)
    f = CreateFrame("Frame", "TwichUISavedDataExplorer", UIParent, "BackdropTemplate")
    f:Hide()                     -- so the first Show runs OnShow
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
    tinsert(UISpecialFrames, "TwichUISavedDataExplorer")
    L.Shell(f, 34)   -- the rim, a title band, and a fade-in

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(22, 22)
    logo:SetPoint("TOPLEFT", 12, -10)
    logo:SetTexture(R.ICON)
    local title = Text(f, "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("Saved Data Explorer")
    local sub = Text(f, "GameFontDisableSmall")
    sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
    sub:SetText("what TwichUI keeps between sessions · read-only")
    Color(sub, K.stone)
    local close = L.CloseBox(f)
    f.refresh = ToolButton(f, "Refresh", 76, function() XW.Refresh(true) end,
        "Reads the chosen source again (and rebuilds the share preview). Nothing is saved or reloaded.")
    f.refresh:SetPoint("RIGHT", close, "LEFT", -10, 0)
    f.reveal = S.Toggle(f, "Reveal personal values", 160, function()
        reveal = not reveal
        f.reveal:SetOn(reveal)
        XW.Render(true)
    end, K)
    L.Raise(f.reveal)
    f.reveal:SetPoint("RIGHT", f.refresh, "LEFT", -8, 0)
    f.reveal:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Reveal personal values", 1, 1, 1)
        GameTooltip:AddLine("Character and friend names, character ids and your notes are hidden on screen and in copies until you turn this on. For this window only; it turns off when the window closes. Hiding them doesn't change or remove anything.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    f.reveal:HookScript("OnLeave", GameTooltip_Hide)

    -- Left
    local listH = HEIGHT - 48 - 40
    f.sources = List(f, LEFT_W, listH, SOURCE_H, InitSource)
    f.sources:SetPoint("TOPLEFT", 16, -48)
    local foot = Text(f, "GameFontDisableSmall")
    foot:SetPoint("TOPLEFT", f.sources, "BOTTOMLEFT", 2, -8)
    foot:SetWidth(LEFT_W)
    foot:SetText("Read from memory, not the file on disk.")
    Color(foot, K.stone)

    -- Middle
    f.head = Text(f, "GameFontNormalLarge")
    f.head:SetPoint("TOPLEFT", MID_X, -50)
    f.head:SetWidth(MID_W)
    f.head:SetWordWrap(false)
    Color(f.head, K.text)
    f.path = Text(f, "GameFontDisableSmall")
    f.path:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT", 0, -4)
    f.path:SetWidth(MID_W)
    f.path:SetWordWrap(false)
    Color(f.path, K.stone)
    f.summary = Text(f, "GameFontHighlightSmall")
    f.summary:SetPoint("TOPLEFT", f.path, "BOTTOMLEFT", 0, -8)
    f.summary:SetWidth(MID_W)
    f.summary:SetSpacing(3)
    f.summary:SetJustifyV("TOP")
    f.summary:SetHeight(64)
    Color(f.summary, K.textDim)
    f.banner = Text(f, "GameFontHighlightSmall")
    f.banner:SetPoint("TOPLEFT", MID_X, -168)
    f.banner:SetWidth(MID_W)
    f.banner:SetHeight(26)
    f.banner:SetJustifyV("TOP")

    f.search = L.EditBox(f, 170, 22)   -- a recessed field with a teal focus edge
    f.search:SetPoint("TOPLEFT", MID_X, -198)
    f.search:SetAutoFocus(false)
    f.search:SetMaxLetters(100)
    f.search:SetScript("OnEscapePressed", f.search.ClearFocus)
    f.search:SetScript("OnEnterPressed", f.search.ClearFocus)
    f.search:SetScript("OnTextChanged", SearchChanged)
    f.search:SetScript("OnEditFocusGained", function() f.searchHint:Hide() end)
    f.search:SetScript("OnEditFocusLost", function(box) f.searchHint:SetShown(box:GetText() == "") end)
    f.searchHint = Text(f.search, "GameFontDisableSmall")
    f.searchHint:SetPoint("LEFT", 6, 0)
    f.searchHint:SetText("Search keys and values")
    Color(f.searchHint, K.stone)
    local expand = ToolButton(f, "Expand all", 76, function()
        if not Live() then XW.Refresh() return end
        local node = (selected and type(selected.value) == "table") and selected or tree.root
        local stopped = tree:ExpandAll(node)
        mode = "tree"
        RenderTree(true)
        RenderHead()
        if stopped then f.status:SetText(WARN .. ("Opened the first %s tables only. Open the rest one at a time.|r"):format(SD.Num(EX.EXPAND_LIMIT))) end
    end, "Opens everything under the chosen table (or the whole source), the first page of each, up to a limit.")
    expand:SetPoint("LEFT", f.search, "RIGHT", 8, 0)
    local collapse = ToolButton(f, "Collapse", 70, function()
        if not tree then return end
        tree:CollapseAll()
        selected = nil
        mode = "tree"
        RenderTree()
        RenderHead()
        ShowDetails()
    end, "Closes everything and goes back to the top of the source.")
    collapse:SetPoint("LEFT", expand, "RIGHT", 4, 0)
    f.showResults = ToolButton(f, "Results", 64, function()
        if search then mode = "results"; RenderTree(); RenderHead() end
    end, "Back to the search results.")
    f.showResults:SetPoint("LEFT", collapse, "RIGHT", 4, 0)

    f.tree = List(f, MID_W, HEIGHT - 228 - 40, TREE_H, InitTree)
    f.tree:SetPoint("TOPLEFT", MID_X, -228)
    f.status = Text(f, "GameFontDisableSmall")
    f.status:SetPoint("TOPLEFT", f.tree, "BOTTOMLEFT", 2, -8)
    f.status:SetWidth(MID_W)
    f.status:SetWordWrap(false)
    Color(f.status, K.stone)

    -- Right
    local rx = WIDTH - 16 - RIGHT_W
    local dl = Text(f, "GameFontNormalSmall")
    dl:SetPoint("TOPLEFT", rx, -50)
    dl:SetText("DETAILS")
    Color(dl, K.bronzeText)
    f.details = TextBox(f, RIGHT_W, 300)
    f.details:SetPoint("TOPLEFT", rx, -66)
    local cl = Text(f, "GameFontNormalSmall")
    cl:SetPoint("TOPLEFT", rx, -378)
    cl:SetText("COPY")
    Color(cl, K.bronzeText)
    local bw = math.floor((RIGHT_W - 12) / 4)
    local cpath = ToolButton(f, "Path", bw, function() Copy("path") end, "The chosen entry's full path.")
    cpath:SetPoint("TOPLEFT", rx, -394)
    local cvalue = ToolButton(f, "Value", bw, function() Copy("value") end, "The chosen entry's value, in full.")
    cvalue:SetPoint("LEFT", cpath, "RIGHT", 4, 0)
    local cread = ToolButton(f, "Readable", bw, function() Copy("readable") end,
        "The chosen table (or the whole source) as readable text. With Reveal on it is exact; otherwise personal-looking values are hidden and it says so. Not an importable configuration.")
    cread:SetPoint("LEFT", cvalue, "RIGHT", 4, 0)
    local csupport = ToolButton(f, "Support", bw, function() Copy("support") end,
        "A sanitized copy for asking for help: personal-looking values are always left out, and the copy says so. Not the exact data.")
    csupport:SetPoint("LEFT", cread, "RIGHT", 4, 0)
    f.copy = TextBox(f, RIGHT_W, HEIGHT - 424 - 52)
    f.copy:SetPoint("TOPLEFT", rx, -424)
    f.copyNote = Text(f, "GameFontDisableSmall")
    f.copyNote:SetPoint("TOPLEFT", f.copy, "BOTTOMLEFT", 2, -6)
    f.copyNote:SetWidth(RIGHT_W)
    f.copyNote:SetHeight(28)
    f.copyNote:SetJustifyV("TOP")
    f.copyNote:SetText("Choose what to copy; it appears selected in the box for Ctrl+C. Addons can't use the clipboard themselves.")
    Color(f.copyNote, K.stone)

    f:SetScript("OnShow", function()
        RenderSources()
        Load(false)
        XW.Render()
    end)
    -- Nothing is kept: the tables looked at, searches, the preview and any copied text go.
    f:SetScript("OnHide", function()
        EX.Release()
        searchToken = searchToken + 1
        tree, selected, search, mode, readAt, summary = nil, nil, nil, "tree", nil, nil
        reveal = false
        f.reveal:SetOn(false)
        f.search:SetText("")
        f.details:Set("")
        f.copy:Set("")
        SetRows(f.tree, {}, "")
    end)
end

-- Something listed may have changed (a backup deleted, a setup saved or received, the preview
-- measured). Redraws a moment later, at most a few times a second, and only while open.
EX.OnChange(function(what)
    if not (f and f:IsShown()) then return end
    if what ~= "preview" then reread = true end
    if preparing then return end
    preparing = true
    C_Timer.After(0.2, function()
        preparing = false
        local check = reread
        reread = false
        if not (f and f:IsShown()) then return end
        if check and not Live() and (tree or (Source() and Source().Root() ~= nil)) then
            Load(true)
            XW.Render(true)
        else
            -- Transfers report often; the tree stays as it is and only the words around it are redrawn.
            RenderSources()
            RenderHead()
            ShowDetails()
        end
    end)
end)

function XW.Render(keepScroll)
    if not (f and f:IsShown()) then return end
    RenderSources()
    RenderHead()
    RenderTree(keepScroll)
    ShowDetails()
end

-- Reads the chosen source again; force: also rebuilds the share preview.
function XW.Refresh(force)
    if not (f and f:IsShown()) then return end
    if force and Source() and Source().kind == "preview" then EX.ReleasePreview() end
    Load(true)
    XW.Render(true)
end

-- id: a source to show ("settings", "share:preview", "restore:<id>", ...).
function XW.Show(id)
    if not f then Build() end
    if id and EX.Source(id) then
        if f:IsShown() then Choose(id) return end
        sourceId = id
    end
    if f:IsShown() then XW.Refresh() else f:Show() end
    f:Raise()
end

function XW.Toggle()
    if f and f:IsShown() then f:Hide() else XW.Show() end
end
