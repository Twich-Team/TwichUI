-- TwichUI: Saved Data Explorer window (/tui saved)
-- Sources on the left (settings, backups, sharing, feature data), the chosen one as a tree in the
-- middle, opened a level and a page at a time, and the chosen entry's details and copy box on the
-- right. Read-only unless the person turns advanced cleanup on (setup/Cleanup.lua decides what may be
-- removed and how; this file only asks, shows and confirms). Opening the window, searching, copying and
-- looking for cleanup candidates never change anything. Drawn with TwichUI's own look (Look.lua, the
-- settings window's), so it looks finished without any other addon.
-- Built on first open; while closed it holds nothing and does nothing. Closing it ends advanced cleanup.

local R = TwichUI
local EX, SD, ST, SH, CL = R.Explorer, R.StoredData, R.Setups, R.Share, R.Cleanup
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
local mode = "tree"              -- "tree", "results" (a search's) or "candidates" (cleanup suggestions)
local candidate                  -- the chosen suggestion
local dlg                        -- the confirmation dialog's frame (built on first use)
local dialog                     -- what it is showing now
local RenderCleanup, SelectCandidate, TogglePick   -- defined with the cleanup controls below
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
-- Advanced cleanup: questions about the chosen entry and the suggestions (nothing here changes data)
---------------------------------------------------------------------------
-- The saved variable and keys of the chosen entry, and the policy's answer for it: plan, var, keys; or nil
-- and why.
local function PlanAt(node)
    local s = Source()
    if not s then return nil, "That source isn't there any more." end
    local var, prefix = CL.SourceAddress(s)
    if not var then return nil, prefix end
    local keys = {}
    for i, k in ipairs(prefix) do keys[i] = k end
    local value = s.Root()
    if node and not node.isRoot then
        for _, k in ipairs(EX.KeysOf(node)) do keys[#keys + 1] = k end
        value = node.value
    end
    if value == nil then return nil, "It isn't there any more." end
    return CL.Policy(var, keys, value), var, keys
end

-- What the details say about deleting, only while advanced cleanup is on.
local function CleanupLines(add, node)
    if not CL.Enabled() then return end
    add("")
    add("CLEANUP")
    local plan, why = PlanAt(node)
    if not plan then
        add("Not available: " .. tostring(why))
    elseif plan.ok then
        add("Can be deleted, after a review and your confirmation.")
        add(plan.effect)
        add("Done by " .. plan.via .. ".")
    else
        add("Protected: " .. plan.reason)
    end
end

local function DateText(t) return date("%b %d %Y, %H:%M", t) end

local function Subject(c)
    if not c.subject then return "" end
    return reveal and c.subject or EX.Hidden("a character's name")
end

-- A suggestion as it is explained on the right.
local function CandidateReport(c)
    local lines = {}
    local function Add(s) lines[#lines + 1] = s end
    Add(CL.TIER_LABEL[c.tier]:upper())
    Add(c.category)
    Add("")
    Add("WHAT")
    Add(c.title .. (c.subject and (": " .. Subject(c)) or ""))
    Add("")
    Add("WHY IT WAS SUGGESTED")
    Add(c.reason)
    Add("")
    Add("EVIDENCE")
    Add(c.evidence)
    if c.uncertainty and c.uncertainty ~= "" then
        Add("")
        Add("WHAT IS NOT KNOWN")
        Add(c.uncertainty)
    end
    if c.date then
        Add("")
        Add("DATE")
        Add(("%s %s"):format(c.date.label, DateText(c.date.t)))
        Add("A date in saved data says when something was made, received or seen. It is not when it was last used, and it is not used to call anything unused.")
    end
    Add("")
    Add("WHERE")
    for _, t in ipairs(c.targets) do
        Add(EX.MaskedPath(t.var, t.keys, reveal))
    end
    Add("")
    if c.tier == "info" then
        Add("This is information, not a recommendation to delete anything.")
    else
        Add("A suggestion is not proof that something is unused, and nothing is selected for you.")
    end
    Add("Inspect shows it in the explorer.")
    return table.concat(lines, "\n")
end

-- What was looked at and what can't be told, for the right-hand side and an empty result.
local function ScanReport()
    local res = CL.results
    if not res then return "" end
    local label = {}
    for _, r in ipairs(CL.RULES) do label[r.id] = r end
    local lines = {}
    local function Add(t) lines[#lines + 1] = t end
    Add("WHAT WAS CHECKED")
    for _, c in ipairs(res.checked) do
        local r = label[c.rule]
        Add(("- %s: %d looked at"):format(r and r.label or c.rule, c.count))
        if r and r.limit ~= "" then Add("    " .. r.limit) end
    end
    Add("")
    Add("WHAT CAN'T BE TOLD")
    for _, t in ipairs(CL.NOT_DETECTED) do Add("- " .. t) end
    Add("")
    Add(("Looked at %s. Suggestions are a snapshot; each entry is checked again, and you confirm it, before anything is removed."):format(DateText(res.at)))
    return table.concat(lines, "\n")
end

-- The suggestions as list rows: a heading per tier, then its entries.
local function CandidateRows()
    local rows = {}
    local res = CL.results
    if not res then return rows end
    for _, tier in ipairs({ "strong", "possible", "info" }) do
        local first = true
        local n = 0
        for _, c in ipairs(res.list) do if c.tier == tier then n = n + 1 end end
        for _, c in ipairs(res.list) do
            if c.tier == tier then
                if first then
                    rows[#rows + 1] = { cgroup = CL.TIER_LABEL[tier], count = n, tier = tier }
                    first = false
                end
                rows[#rows + 1] = { candidate = c }
            end
        end
    end
    return rows
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
    if c.twichui then
        Add(("TwichUI's own settings: %s (about %s)."):format(table.concat(c.twichui.features, ", "), ST.FormatSize(c.twichui.bytes)))
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
    CleanupLines(function(text) lines[#lines + 1] = text end, nil)
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
    CleanupLines(Add, node)
    return table.concat(lines, "\n")
end

local function ShowDetails()
    if not f then return end
    local ok, text = pcall(function()
        if mode == "candidates" then
            if candidate then return CandidateReport(candidate) end
            if CL.results then return ScanReport() end
            return "Looking through TwichUI's saved data..."
        end
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
    if mode == "candidates" then
        if CL.Enabled() then
            return GREY .. "Suggestions are not proof that anything is unused. Nothing is picked for you, and each entry is checked again before it is removed.|r"
        end
        return GREY .. "Suggestions only. Turn on advanced cleanup to pick entries and review them; nothing here changes data.|r"
    end
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
    if mode == "candidates" then
        if CL.scanning then return "Looking through saved data... " .. (CL.scanning.step or "") end
        local res = CL.results
        if not res then return "" end
        local n = #res.list
        local text = ("%d %s from %s."):format(n, n == 1 and "suggestion" or "suggestions", When(res.at))
        if res.extra > 0 then text = text .. (" %d more not listed."):format(res.extra) end
        return text .. " They are a snapshot; each is checked again before removal."
    end
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

local function ScanSummary()
    local res = CL.results
    if CL.scanning then return "Looking through TwichUI's own saved data, a little at a time." end
    if not res then return "" end
    local counts = { strong = 0, possible = 0, info = 0 }
    for _, c in ipairs(res.list) do counts[c.tier] = counts[c.tier] + 1 end
    return ("%s%s:|r %d\n%s%s:|r %d\n%s%s:|r %d"):format(
        GREY, CL.TIER_LABEL.strong, counts.strong, GREY, CL.TIER_LABEL.possible, counts.possible,
        GREY, CL.TIER_LABEL.info, counts.info)
end

local function RenderHead()
    if mode == "candidates" then
        f.head:SetText("Cleanup candidates")
        f.path:SetText("What TwichUI's own saved data itself shows. Nothing was changed.")
        f.summary:SetText(ScanSummary())
        f.banner:SetText(Banner())
        f.status:SetText(Status())
        f.showResults:SetShown(false)
        return
    end
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
    if mode == "candidates" then
        if CL.scanning then return {}, "Looking through TwichUI's saved data..." end
        if not CL.results then return {}, "" end
        local rows = CandidateRows()
        return rows, "Nothing in TwichUI's saved data matched a cleanup rule, so there is nothing to suggest. The checks and what they can't tell are listed on the right."
    end
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
    if mode == "candidates" then mode, candidate = "tree", nil end
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
    if d.candidate then SelectCandidate(d.candidate) return end
    if d.cgroup then return end
    if not Live() then XW.Refresh() return end
    if d.result then OpenResult(d.result) return end
    if d.more then
        tree:More(d.more)
    elseif d.node then
        selected = d.node
        if type(d.node.value) == "table" then tree:Toggle(d.node) end
        ShowDetails()
        RenderCleanup()
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
    if not row.pick then
        -- the box a suggestion is picked with; only shown while advanced cleanup is on
        row.pick = CreateFrame("Button", nil, row)
        row.pick:SetSize(30, TREE_H)
        row.pick:SetPoint("LEFT", 2, 0)
        row.pick.text = Text(row.pick, "GameFontHighlightSmall")
        row.pick.text:SetPoint("CENTER", 0, 0)
        row.pick:SetScript("OnClick", function(b)
            local data = b:GetParent().data
            if data and data.candidate then TogglePick(data.candidate) end
        end)
    end
    row.pick:Hide()
    if d.cgroup then
        row.sel:Hide()
        row.label:SetPoint("LEFT", 6, 0)
        row.label:SetText(("%s%s (%d)|r"):format(GOLD, Esc(d.cgroup):upper(), d.count))
        return
    end
    if d.candidate then
        local c = d.candidate
        local gone = CL.CandidateGone(c)
        row.sel:SetShown(c == candidate)
        local on = CL.Enabled() and not gone
        row.pick:SetShown(on)
        if on then
            local picked = CL.picks[c.id]
            row.pick.text:SetText((picked and NUM_COLOR .. "[x]" or GREY .. "[ ]") .. "|r")
        end
        row.label:SetPoint("LEFT", on and 34 or 8, 0)
        local who = c.subject and (" " .. GREY .. "·|r " .. Esc(Subject(c))) or ""
        local note = gone and (GREY .. "  (not there any more)|r") or ("  " .. GREY .. Esc(c.reason) .. "|r")
        row.label:SetText(Esc(c.title) .. who .. note)
        return
    end
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

---------------------------------------------------------------------------
-- Advanced cleanup: the mode, the confirmation dialog, reviewing, undoing
-- Nothing below deletes by itself: turning the mode on, finding candidates and opening a review change
-- nothing. A removal needs the mode, a review that has finished counting, and the confirm button.
---------------------------------------------------------------------------
local DLG_W, DLG_H = 600, 480

local function CloseDialog()
    if dlg and dlg:IsShown() then dlg:Hide() end
    dialog = nil
end

-- The confirm button's label, or nil when there is none now. (A function that answers nil must not fall
-- back to the function itself, which `f() or f` would.)
local function ConfirmLabel(spec)
    local c = spec.confirm
    if type(c) == "function" then return c() end
    return c
end

-- Whether the confirm button may act now: it has a label, the work it waits for has finished, and any
-- acknowledgment asked for is ticked. Asked again when the button is pressed, not only when it is drawn.
local function CanConfirm(spec)
    local confirm = ConfirmLabel(spec)
    if confirm == nil then return false end
    if spec.ready and not spec.ready() then return false end
    if spec.ackLabel and spec.ackLabel() ~= nil and spec.ackOn ~= true then return false end
    return true
end

local function RefreshDialog()
    if not (dlg and dialog and dlg:IsShown()) then return end
    local spec = dialog
    local text = type(spec.text) == "function" and spec.text() or spec.text
    dlg.title:SetText(Esc(type(spec.title) == "function" and spec.title() or spec.title))
    dlg.body:Set(Esc(text or ""))
    local ack = spec.ackLabel and spec.ackLabel() or nil
    dlg.ack:SetShown(ack ~= nil)
    if ack then
        dlg.ack.text:SetText(ack)
        dlg.ack:SetOn(spec.ackOn == true)
    end
    local confirm = ConfirmLabel(spec)
    local can = CanConfirm(spec)
    local button = spec.danger and dlg.confirmDanger or dlg.confirmPlain
    dlg.confirmDanger:SetShown(confirm ~= nil and spec.danger == true)
    dlg.confirmPlain:SetShown(confirm ~= nil and not spec.danger)
    if confirm then
        button.text:SetText(confirm)
        button:SetEnabled(can)
    end
    dlg.again:SetShown(spec.again ~= nil and spec.again.show())
    dlg.cancel.text:SetText(spec.cancelLabel and spec.cancelLabel() or "Cancel")
    dlg.status:SetText(spec.status and spec.status() or "")
end

local function BuildDialog()
    dlg = CreateFrame("Frame", "TwichUIExplorerCleanupDialog", f, "BackdropTemplate")
    dlg:Hide()
    dlg:SetSize(DLG_W, DLG_H)
    dlg:SetPoint("CENTER", f, "CENTER", 0, 0)
    dlg:SetFrameStrata("FULLSCREEN_DIALOG")
    dlg:SetToplevel(true)
    dlg:EnableMouse(true)
    dlg:EnableKeyboard(true)
    L.Shell(dlg, 34)

    -- A dim layer over the explorer, so nothing behind is clicked by accident.
    dlg.dim = CreateFrame("Frame", nil, f)
    dlg.dim:SetAllPoints(f)
    dlg.dim:SetFrameStrata("DIALOG")
    dlg.dim:EnableMouse(true)
    dlg.dim:Hide()
    local wash = dlg.dim:CreateTexture(nil, "BACKGROUND")
    wash:SetAllPoints()
    wash:SetColorTexture(0, 0, 0, 0.6)

    dlg.title = Text(dlg, "GameFontNormalLarge")
    dlg.title:SetPoint("TOPLEFT", 16, -9)
    dlg.body = TextBox(dlg, DLG_W - 32, DLG_H - 44 - 128)
    dlg.body:SetPoint("TOPLEFT", 16, -44)

    dlg.ack = S.Toggle(dlg, "", DLG_W - 32, function()
        if dialog then
            dialog.ackOn = not dialog.ackOn
            RefreshDialog()
        end
    end, K)
    dlg.ack:SetPoint("BOTTOMLEFT", 16, 56)
    dlg.ack:SetHeight(24)

    dlg.status = Text(dlg, "GameFontDisableSmall")
    dlg.status:SetPoint("BOTTOMLEFT", 16, 40)
    dlg.status:SetWidth(DLG_W - 32)
    dlg.status:SetWordWrap(false)
    Color(dlg.status, K.stone)

    dlg.cancel = L.Button(dlg, "Cancel", 110, "secondary", function() CloseDialog() end)
    dlg.cancel:SetPoint("BOTTOMRIGHT", -16, 12)
    dlg.confirmPlain = L.Button(dlg, "Confirm", 230, "primary", function()
        if dialog and dialog.onConfirm and CanConfirm(dialog) then dialog.onConfirm() end
    end)
    dlg.confirmPlain:SetPoint("RIGHT", dlg.cancel, "LEFT", -10, 0)
    dlg.confirmDanger = L.Button(dlg, "Delete", 230, "danger", function()
        if dialog and dialog.onConfirm and CanConfirm(dialog) then dialog.onConfirm() end
    end)
    dlg.confirmDanger:SetPoint("RIGHT", dlg.cancel, "LEFT", -10, 0)
    dlg.again = L.Button(dlg, "Review again", 120, "secondary", function()
        if dialog and dialog.again then dialog.again.run() end
    end)
    dlg.again:SetPoint("BOTTOMLEFT", 16, 12)

    -- Escape closes only this dialog (it is a cancel, never a confirm); no key confirms anything.
    dlg:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            CloseDialog()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    dlg:SetScript("OnShow", function() dlg.dim:Show() end)
    dlg:SetScript("OnHide", function()
        dlg.dim:Hide()
        EX.Cancel("cleanup-measure")
        dialog = nil
    end)
end

-- spec: { title, text (string or function), confirm (label or function), danger, ackLabel (function),
--   ready (function), onConfirm, cancelLabel, status, again = { show, run } }
local function ShowDialog(spec)
    if not dlg then BuildDialog() end
    spec.ackOn = false
    dialog = spec
    dlg:Show()
    RefreshDialog()
end

---------------------------------------------------------------------------
-- Turning the mode on and off
---------------------------------------------------------------------------
local ENABLE_TEXT = table.concat({
    "Advanced cleanup can remove saved data and affect settings or features. Only delete entries you understand. Suggested candidates are not proof that data is unused.",
    "",
    "WHAT IT ADDS",
    "- A Delete action for entries TwichUI knows how to remove safely. Each one is reviewed first: the exact path, what it holds, what follows and whether it can be undone. Then you confirm it.",
    "- Entries that are required or in use right now stay protected, and say why.",
    "- Removals use TwichUI's own actions where they exist (the same as Delete in Backups, Profiles and Saved data).",
    "",
    "WHAT STAYS THE SAME",
    "- Nothing is chosen or deleted for you. Finding candidates only suggests.",
    "- It turns itself off when this window closes, and it is never saved.",
    "- A removal reaches the saved file when you reload or log out.",
}, "\n")

local function AskEnable()
    ShowDialog({
        title = "Enable advanced cleanup?",
        text = ENABLE_TEXT,
        ackLabel = function() return "I understand this can remove data, and that suggestions are not proof." end,
        confirm = "Enable advanced cleanup",
        onConfirm = function()
            CloseDialog()
            CL.Enable(true)
        end,
    })
end

---------------------------------------------------------------------------
-- Reviewing, counting and removing
---------------------------------------------------------------------------
local function Num(n) return SD.Num(n) end

-- Exact path and key of a target, hiding personal-looking keys unless revealed.
local function TargetPath(t) return EX.MaskedPath(t.var, t.keys, reveal) end

local function TargetKey(t)
    local k = t.keys[#t.keys]
    if k == nil then return "(the whole saved variable)" end
    local why = not reveal and EX.PersonalKey(k, t.keys[#t.keys - 1])
    return why and EX.Hidden(why) or EX.PathPart(k)
end

local function TargetPreview(t)
    local v = t.value
    if type(v) ~= "table" then
        local k = t.keys[#t.keys]
        local why = not reveal and EX.PersonalValue(k, v, t.parent)
        return why and EX.Hidden(why) or EX.ValueText(v, 120)
    end
    if not EX.IsSecret(v) and canaccesstable and not canaccesstable(v) then return "a table the game hides from addons" end
    local n, more, shape = EX.Shape(v)
    local text = "a table: " .. EX.ShapeText(n, more, shape)
    if n > 0 then
        local names, keys = {}, SD.Keys(v)
        for i = 1, math.min(#keys, 6) do
            local k = keys[i]
            local why = not reveal and EX.PersonalKey(k, t.keys[#t.keys])
            names[#names + 1] = why and EX.Hidden(why) or (EX.PathPart(k):gsub("^%.", ""))
        end
        text = text .. "\n    holds: " .. table.concat(names, ", ") .. (#keys > 6 and ", ..." or "")
    end
    return text
end

local function CountText(t, r)
    if t.print then
        local p = t.print
        local more = p.cut and "at least " or ""
        if type(t.value) ~= "table" then return "just this value" end
        local text = ("this entry and everything under it: %s%s %s in %s%s nested %s"):format(
            more, Num(p.values), p.values == 1 and "value" or "values", more, Num(p.tables - 1), (p.tables - 1) == 1 and "table" or "tables")
        for _, a in ipairs(t.alsoTargets or {}) do
            if a.print then
                text = text .. ("\n    and %s%s more in the related list it also takes"):format(more, Num(a.print.values))
            end
        end
        return text
    end
    return ("counting... %s values so far"):format(Num(r.progress.current and r.progress.current.values or 0))
end

local function UndoText(t)
    if t.recoverable then return "Undo is available" end
    if t.print and (t.print.cut or t.print.hidden > 0) then return "CAN'T BE UNDONE: it is too large to keep a copy of, or part of it is hidden" end
    if t.print then return "CAN'T BE UNDONE: it is too large to keep a copy of alongside the others in this review" end
    return "worked out after counting"
end

local function TargetBlock(add, t, r, number)
    local plan = t.plan
    local head = number and ("%d. "):format(number) or ""
    add(("%s%s"):format(head, plan.what or plan.dataset or "Entry"))
    add("    Dataset: " .. (plan.dataset or "?"))
    add("    Path: " .. TargetPath(t))
    add("    Key: " .. TargetKey(t))
    add("    Stored: " .. (plan.persisted == false and "runtime only, not saved" or "saved data (kept in the saved file)"))
    add("    Holds: " .. TargetPreview(t))
    for _, fact in ipairs(plan.facts or {}) do add("    - " .. fact) end
    add("    Removes: " .. CountText(t, r))
    add("    Done by: " .. plan.via)
    add("    Effect: " .. plan.effect)
    for _, c in ipairs(plan.consequences or {}) do add("    ! " .. c) end
    add("    Recovery: " .. UndoText(t))
end

local function ReviewText(r)
    local lines = {}
    local function Add(text) lines[#lines + 1] = text end
    local n = #r.list
    if n == 0 then
        Add("NOTHING CAN BE DELETED FROM THIS SELECTION")
    else
        Add(n == 1 and "THIS ENTRY WILL BE DELETED PERMANENTLY" or ("%d ENTRIES WILL BE DELETED PERMANENTLY"):format(n))
    end
    Add("Deleting a table deletes everything under it, not just the row you see. Review the exact path below; nothing is removed until you press Delete.")
    Add("")
    for i, t in ipairs(r.list) do
        TargetBlock(Add, t, r, n > 1 and i or nil)
        Add("")
    end
    if #r.covered > 0 then
        Add(("%d selected %s inside an entry that is already being deleted, so %s not counted separately."):format(
            #r.covered, #r.covered == 1 and "entry is" or "entries are", #r.covered == 1 and "it is" or "they are"))
        Add("")
    end
    if #r.skipped > 0 then
        Add("LEFT AS THEY ARE")
        for _, t in ipairs(r.skipped) do
            Add(("- %s: %s"):format(TargetPath(t), t.plan.reason or "protected"))
        end
        Add("")
    end
    if n > 0 then
        Add("RELOAD")
        Add(r.list[1].plan.reload)
        Add("")
        Add("Each entry is checked again just before it is removed. If anything has changed since this review, nothing is deleted and you review it again.")
    end
    return table.concat(lines, "\n")
end

local function ResultText(r)
    local rep = r.report
    local lines = {}
    local function Add(text) lines[#lines + 1] = text end
    if rep.status == "done" then
        Add(("DELETED %d %s"):format(rep.removed, rep.removed == 1 and "ENTRY" or "ENTRIES"))
    elseif rep.status == "partial" then
        Add(("PARTLY DONE: %d deleted, %d NOT deleted"):format(rep.removed, rep.failed))
    elseif rep.status == "failed" then
        Add("NOTHING WAS DELETED")
    else
        Add("NOTHING WAS DELETED")
        if rep.reason then Add(rep.reason) end
    end
    Add("")
    for _, res in ipairs(rep.results) do
        local t = res.target
        Add(("%s %s"):format(res.ok and "Deleted:" or "NOT deleted:", TargetPath(t)))
        if not res.ok and res.why then Add("    " .. res.why) end
        if res.ok and not res.undoable then Add("    This can't be undone.") end
    end
    if rep.removed > 0 then
        Add("")
        Add("The explorer has read the data again. No reload is needed; the change reaches the saved file when you reload or log out.")
        if rep.undoable > 0 then
            Add(("Undo last cleanup puts back %d of these, while advanced cleanup is on, until you reload, log out or delete something else. The copy is in memory only."):format(rep.undoable))
        end
    end
    return table.concat(lines, "\n")
end

local function AfterRemoval()
    for _, c in ipairs(CL.results and CL.results.list or {}) do
        if CL.CandidateGone(c) then CL.picks[c.id] = nil end
    end
    local s = Source()
    if mode == "tree" or mode == "results" then
        if not s or s.Root() == nil then
            Choose("settings")
        else
            XW.Refresh()
        end
    else
        RenderSources()
        RenderTree(true)
        RenderHead()
        ShowDetails()
    end
    RenderCleanup()
end

-- Starts a review of targets (from CL.NewTarget / CL.TargetsFor): shows the dialog at once, counts in the
-- background, and enables Delete only when counting has finished.
local StartReview
StartReview = function(targets, heading)
    local deletable, skipped = {}, {}
    for _, t in ipairs(targets) do
        if t.plan.ok then deletable[#deletable + 1] = t else skipped[#skipped + 1] = t end
    end
    local list, covered = CL.Normalize(deletable)
    local r = { list = list, covered = covered, skipped = skipped, progress = {}, counted = false, source = targets }
    local function Poll()
        if dialog == r.spec and EX.Busy("cleanup-measure") then
            RefreshDialog()
            C_Timer.After(0.25, Poll)
        end
    end
    r.spec = {
        title = heading,
        text = function()
            if r.report then return ResultText(r) end
            if r.stale then
                return "NOTHING WAS DELETED\n\nThis changed after it was reviewed:\n" .. r.stale ..
                    "\n\nTo be safe, TwichUI does not delete something other than what you reviewed. Press Review again to look at it as it is now."
            end
            return ReviewText(r)
        end,
        danger = true,
        confirm = function()
            if r.report or r.stale then return nil end
            if #list == 0 then return nil end
            return ("Delete %d %s permanently"):format(#list, #list == 1 and "entry" or "entries")
        end,
        ready = function() return r.counted and #list > 0 and not r.report and not r.stale and CL.Enabled() end,
        ackLabel = function()
            if r.report or r.stale or not r.counted then return nil end
            for _, t in ipairs(list) do
                if not t.recoverable then return "I understand that at least one of these can't be undone." end
            end
            return nil
        end,
        cancelLabel = function() return (r.report or r.stale) and "Close" or "Cancel" end,
        status = function()
            if r.report or r.stale then return "" end
            if not r.counted then return ("Counting what would be removed... (%d of %d)"):format(r.progress.index or 0, #list) end
            return ""
        end,
        again = {
            show = function() return r.stale ~= nil end,
            run = function()
                local fresh = {}
                for _, t in ipairs(r.source) do
                    -- a suggested backup is found again by its id, never by the position it had
                    local keys = CL.LocateTarget({ var = t.var, keys = t.keys, byId = t.byId })
                    local nt = keys and CL.NewTarget(t.var, keys)
                    if nt then
                        nt.candidate, nt.byId = t.candidate, t.byId
                        fresh[#fresh + 1] = nt
                    end
                end
                CloseDialog()
                StartReview(fresh, heading)
            end,
        },
        onConfirm = function()
            if not (r.counted and CL.Enabled()) then return end
            local report = CL.Commit(list)
            if report.status == "changed" then
                r.stale = report.reason or "It no longer matches."
            else
                r.report = report
                if report.removed > 0 then AfterRemoval() end
            end
            RefreshDialog()
        end,
    }
    ShowDialog(r.spec)
    if #list == 0 then
        r.counted = true
        RefreshDialog()
        return r
    end
    CL.Count(list, r.progress, function(ok)
        if dialog ~= r.spec then return end
        if ok then
            CL.PlanRecovery(list)
            r.counted = true
        else
            r.stale = "Counting what would be removed did not finish."
        end
        RefreshDialog()
    end)
    C_Timer.After(0.25, Poll)
    return r
end

-- Delete…: the chosen entry.
local function DeleteChosen()
    if not CL.Enabled() or mode == "candidates" then return end
    local plan, var, keys = PlanAt(selected)
    if not plan then return end
    local t = CL.NewTarget(var, keys)
    if not t then return end
    StartReview({ t }, "Delete this entry?")
end

local function ReviewPicked()
    if not CL.Enabled() then return end
    local picked = CL.PickedCandidates()
    if #picked == 0 then return end
    local targets = CL.TargetsFor(picked)
    StartReview(targets, ("Delete %d suggested %s?"):format(#picked, #picked == 1 and "item" or "items"))
end

local function AskUndo()
    if not CL.Enabled() then return end
    local info = CL.RecoveryInfo()
    if not info then return end
    local report
    ShowDialog({
        title = "Undo the last cleanup?",
        text = function()
            if report then
                local lines = { ("PUT BACK %d OF %d"):format(report.restored, report.restored + #report.failed) }
                for _, f_ in ipairs(report.failed) do lines[#lines + 1] = "NOT put back: " .. (f_.why or "") end
                if report.blocked then lines[#lines + 1] = report.blocked end
                return table.concat(lines, "\n")
            end
            return ("This puts back what the last cleanup removed: %d %s, removed at %s.\n\nEach one is put back only where nothing new has taken its place. The copy was kept in memory only; it is never saved and ends when you reload or log out.")
                :format(info.items, info.items == 1 and "entry" or "entries", When(info.at))
        end,
        confirm = function() return (not report) and "Put it back" or nil end,
        ready = function() return CL.Enabled() end,
        cancelLabel = function() return report and "Close" or "Cancel" end,
        onConfirm = function()
            report = CL.Undo()
            AfterRemoval()
            RefreshDialog()
        end,
    })
end

---------------------------------------------------------------------------
-- Suggestions
---------------------------------------------------------------------------
local function PollScan()
    if mode ~= "candidates" or not (f and f:IsShown()) then return end
    if EX.Busy("cleanup-scan") then
        RenderHead()
        C_Timer.After(0.25, PollScan)
    end
end

local function FindCandidates()
    CloseDialog()
    EX.Cancel("search")
    mode, candidate = "candidates", nil
    CL.picks = {}
    CL.results = nil
    CL.Scan({}, function()
        if not (f and f:IsShown()) then return end
        RenderTree()
        RenderHead()
        ShowDetails()
        RenderCleanup()
    end)
    RenderTree()
    RenderHead()
    ShowDetails()
    RenderCleanup()
    C_Timer.After(0.25, PollScan)
end

SelectCandidate = function(c)
    candidate = c
    RenderTree(true)
    ShowDetails()
    RenderCleanup()
end

TogglePick = function(c)
    if not CL.Enabled() then return end
    CL.Pick(c.id, not CL.picks[c.id])
    RenderTree(true)
    RenderCleanup()
end

-- Shows a suggestion's entry in the explorer.
local function InspectCandidate()
    local c = candidate
    if not c then return end
    CL.CancelScan()
    mode = "tree"
    if not EX.Source(c.inspect.source) then
        Load(false)
        XW.Render()
        f.status:SetText(WARN .. "That entry isn't there any more.|r")
        return
    end
    Choose(c.inspect.source)
    local node = tree and tree:Reveal(c.inspect.keys)
    if node then
        selected = node
        RenderTree()
        ScrollTo(node)
        RenderHead()
        ShowDetails()
        RenderCleanup()
    end
end

local function BackToTree()
    CL.CancelScan()
    mode, candidate = "tree", nil
    XW.Render()
end

-- Shows or hides what only advanced cleanup (or the suggestions list) uses.
RenderCleanup = function()
    if not f then return end
    local on = CL.Enabled()
    local inCand = mode == "candidates"
    f.advOn:SetShown(not on)
    f.advOff:SetShown(on)
    f.chip:SetShown(on)
    f.advLine:SetShown(on)
    f.sub:SetShown(not on)
    f.search:SetShown(not inCand)
    f.expand:SetShown(not inCand)
    f.collapse:SetShown(not inCand)
    f.cBack:SetShown(inCand)
    f.cClear:SetShown(inCand and on)
    f.cReview:SetShown(inCand and on)
    local picked = #CL.PickedCandidates()
    f.cReview.text:SetText(("Review picked (%d)..."):format(picked))
    f.cReview:SetEnabled(picked > 0)
    f.cClear:SetEnabled(picked > 0)
    f.details:SetHeight((on or inCand) and 262 or 300)
    local plan = (on and not inCand) and PlanAt(selected) or nil
    f.delete:SetShown(on and not inCand)
    f.delete:SetEnabled(plan ~= nil and plan.ok == true)
    f.inspect:SetShown(inCand)
    f.inspect:SetEnabled(candidate ~= nil)
    f.undo:SetShown(on and CL.RecoveryInfo() ~= nil)
    f.advHint:SetShown(not on and inCand)
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
    f.sub = sub
    -- Shown for as long as advanced cleanup is on, instead of "read-only": rust, and a rust line under the band.
    f.chip = CreateFrame("Frame", nil, f)
    f.chip:SetSize(330, 20)
    f.chip:SetPoint("LEFT", title, "RIGHT", 10, 0)
    local chipBg = f.chip:CreateTexture(nil, "BACKGROUND")
    chipBg:SetAllPoints()
    chipBg:SetColorTexture(K.danger.bg[1], K.danger.bg[2], K.danger.bg[3], 1)
    local chipText = Text(f.chip, "GameFontNormalSmall")
    chipText:SetPoint("CENTER", 0, 0)
    chipText:SetText("ADVANCED CLEANUP ENABLED · deleting is on")
    Color(chipText, K.danger.text)
    f.chip:Hide()
    f.advLine = f:CreateTexture(nil, "OVERLAY")
    f.advLine:SetPoint("TOPLEFT", 1, -34)
    f.advLine:SetPoint("TOPRIGHT", -1, -34)
    f.advLine:SetHeight(2)
    f.advLine:SetColorTexture(K.danger.border[1], K.danger.border[2], K.danger.border[3], 1)
    f.advLine:Hide()
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
    local listH = HEIGHT - 48 - 40 - 74
    f.sources = List(f, LEFT_W, listH, SOURCE_H, InitSource)
    f.sources:SetPoint("TOPLEFT", 16, -48)
    -- Finding candidates only looks; it works in read-only mode, and picking or deleting needs the mode.
    f.find = ToolButton(f, "Find cleanup candidates", LEFT_W, FindCandidates,
        "Looks through TwichUI's saved data for entries its own code can't use, and for records worth a look. It only suggests: nothing is selected for you and nothing is changed.")
    f.find:SetPoint("TOPLEFT", f.sources, "BOTTOMLEFT", 0, -8)
    f.advOn = ToolButton(f, "Enable advanced cleanup...", LEFT_W, AskEnable,
        "Opens a warning first. Turning it on deletes nothing; it adds a reviewed, confirmed Delete for entries TwichUI can remove safely.")
    f.advOn:SetPoint("TOPLEFT", f.find, "BOTTOMLEFT", 0, -6)
    f.advOff = L.Button(f, "Return to read-only", LEFT_W, "primary", function() CL.Disable() end)
    f.advOff:SetHeight(22)
    f.advOff:SetPoint("TOPLEFT", f.find, "BOTTOMLEFT", 0, -6)
    f.advOff:Hide()
    local foot = Text(f, "GameFontDisableSmall")
    foot:SetPoint("TOPLEFT", f.advOn, "BOTTOMLEFT", 2, -8)
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
    f.expand = expand
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
    f.collapse = collapse
    f.showResults = ToolButton(f, "Results", 64, function()
        if search then mode = "results"; RenderTree(); RenderHead() end
    end, "Back to the search results.")
    f.showResults:SetPoint("LEFT", collapse, "RIGHT", 4, 0)
    -- The same row while suggestions are shown.
    f.cBack = ToolButton(f, "Back to tree", 100, BackToTree, "Leaves the suggestions and shows the saved data as a tree.")
    f.cBack:SetPoint("TOPLEFT", MID_X, -198)
    f.cClear = ToolButton(f, "Clear picks", 90, function()
        CL.picks = {}
        RenderTree(true)
        RenderCleanup()
    end, "Unpicks everything. Nothing is picked unless you pick it.")
    f.cClear:SetPoint("LEFT", f.cBack, "RIGHT", 6, 0)
    f.cReview = ToolButton(f, "Review picked (0)...", 160, ReviewPicked,
        "Shows exactly what would be deleted for the entries you picked, and what follows. Nothing is deleted until you confirm there.")
    f.cReview:SetPoint("LEFT", f.cClear, "RIGHT", 6, 0)
    f.advHint = Text(f, "GameFontDisableSmall")
    f.advHint:SetPoint("LEFT", f.cBack, "RIGHT", 12, 0)
    f.advHint:Hide()
    for _, b in ipairs({ f.cBack, f.cClear, f.cReview }) do b:Hide() end

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
    -- Destructive and recovery actions sit under the details, only while advanced cleanup is on.
    f.delete = L.Button(f, "Delete...", 130, "danger", DeleteChosen)
    f.delete:SetHeight(22)
    f.delete:SetPoint("TOPLEFT", rx, -336)
    f.delete:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local plan, why = PlanAt(selected)
        if plan and plan.ok then
            GameTooltip:SetText("Delete this entry", 1, 1, 1)
            GameTooltip:AddLine("Opens a review: exact path, what it holds, what follows and whether it can be undone. Nothing is deleted until you confirm there.", nil, nil, nil, true)
        else
            GameTooltip:SetText("Can't be deleted", 1, 1, 1)
            GameTooltip:AddLine(Esc((plan and plan.reason) or why or "Choose an entry first."), 0.9, 0.6, 0.5, true)
        end
        GameTooltip:Show()
    end)
    f.delete:HookScript("OnLeave", GameTooltip_Hide)
    f.undo = ToolButton(f, "Undo last cleanup", 150, AskUndo,
        "Puts back what the last cleanup removed, where nothing new has taken its place. Kept in memory only, until you reload or log out.")
    f.undo:SetPoint("LEFT", f.delete, "RIGHT", 8, 0)
    f.inspect = ToolButton(f, "Inspect in explorer", 150, InspectCandidate, "Shows the suggested entry in the tree. Changes nothing.")
    f.inspect:SetPoint("TOPLEFT", rx, -336)
    for _, b in ipairs({ f.delete, f.undo, f.inspect }) do b:Hide() end
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
    f.advHint:SetText("Turn on advanced cleanup to pick suggestions.")
    Color(f.advHint, K.stone)
    -- Nothing is kept: the tables looked at, searches, the preview and any copied text go.
    f:SetScript("OnHide", function()
        if dlg then dlg:Hide() end
        dialog = nil
        EX.Release()          -- also ends advanced cleanup (setup/Cleanup.lua) and drops the suggestions
        searchToken = searchToken + 1
        tree, selected, search, mode, readAt, summary = nil, nil, nil, "tree", nil, nil
        candidate = nil
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

-- Advanced cleanup turned on or off: the controls, the rows' pick boxes and the details follow.
CL.OnChange(function(what)
    if not (f and f:IsShown()) then return end
    if what == "mode" and not CL.Enabled() then
        if dlg and dialog then dlg:Hide() end
        if mode == "candidates" and not CL.results then mode = "tree" end
    end
    if what == "mode" then
        RenderTree(true)
        RenderHead()
        ShowDetails()
        RenderCleanup()
    end
end)

function XW.Render(keepScroll)
    if not (f and f:IsShown()) then return end
    RenderSources()
    RenderHead()
    RenderTree(keepScroll)
    ShowDetails()
    RenderCleanup()
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
