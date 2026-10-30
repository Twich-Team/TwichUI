-- TwichUI settings: Reminders, the "When" designer
-- The reminder's rule as something to read: who it is for, its conditions as cards inside bounded groups, and why it would
-- or would not show. It draws and edits the rule the evaluator already reads (reminders/Config.lua's tree, Evaluate.lua's
-- decision); nothing here decides anything or keeps a rule of its own, and every change goes through Config.lua's functions,
-- which check it. RemindersPlain.lua says it in words.
--
--   * Who is this for?     one line, and Edit for the characters and the class (applied as you choose, like every other
--                          setting here).
--   * Show this reminder when...   the tree: a group is a bounded box with "All of these must be true" or "At least one of
--                          these must be true", a condition a card (a sentence, Edit, and a More menu: Duplicate, Move up
--                          and down, Move into another group, Remove). A card opens one editor under it, which works on a
--                          copy: Done writes it, Cancel leaves the saved condition as it was. Add a condition opens a
--                          picker (search, categories) and then the same editor; nothing is saved until Add.
--   * Why would it show?   the rule as short lines, and on request what each condition and group sees right now.
--
-- A node is held by its stored table (the same table wherever it moves to, so a fold or an open editor survives a reorder)
-- and found again by RM.NodeByRaw whenever it is used; nothing keeps a row number. Frames are pooled: a card for each
-- condition a reminder can have, a box for each group, one editor, one picker, one targeting panel. What is open is kept for
-- the session only and is put away when the page is hidden.

local R = TwichUI
local Dz = {}
R.RemindersDesigner = Dz

local function Wg() return R.SettingsWidgets end
local function RM() return R.Reminders end
local function Pl() return R.RemindersPlain end
local function Kit() return R.RemindersEditor.Kit end

local W, PAD = 644, 14
local RAIL, INSET = 3, 11       -- a group's left rail, and how far what is in it moves in from its edge
local HEAD_H = 30
local GAP, SEP_H = 6, 14
local ICON = 20
local LINES = 26                -- summary lines (a heading and a line for each condition and group, with room over)
local EDIT_W = 52           -- a card's right side: the Edit button, and More beside it (MORE_W)
local MORE_W = 64

-- What is open. The reminder it belongs to (ui.id) decides whether it still applies.
local ui = {}
local folded = setmetatable({}, { __mode = "k" })   -- stored group table -> true (kept for the session)
local undo                                           -- the last removal: { id, node, parentRaw, index, label }
local explainOpen = false
local stats = { cards = 0, groups = 0, pickerRows = 0 }

local function Reset(id)
    ui = { id = id }
    undo = nil
end

function Dz.Reset() Reset(nil) end
function Dz.State() return ui, undo, explainOpen end

-- For TwichUI Diagnostics and the tests: what has been built (pools only grow to the sizes a reminder is limited to) and what
-- is open. Counts only: it reads, builds and changes nothing, and names nothing.
function Dz.Snapshot()
    return { cards = stats.cards, groups = stats.groups, pickerRows = stats.pickerRows,
        open = ui.mode and 1 or 0, explain = explainOpen and 1 or 0, undo = undo and 1 or 0 }
end

---------------------------------------------------------------------------
-- Small pieces
---------------------------------------------------------------------------
-- The color of a state (a word beside it always says the same thing): met teal, not met amber, can't tell grey, needs attention red.
local function StateColor(state)
    local pal = Wg().pal
    if state == "met" then return pal.tealHi
    elseif state == "unmet" then return pal.bronzeText
    elseif state == "invalid" then return pal.danger.text end
    return pal.stone
end
local function Color(fs, tone)
    local G = Wg()
    if tone == "met" or tone == "unmet" or tone == "unknown" or tone == "invalid" then G.Color(fs, StateColor(tone)) else Kit().Tone(fs, tone) end
end

-- A tooltip that leaves the control's own hover scripts alone (a tab repaints itself on enter and leave).
local function TipHook(frame, title, text)
    frame:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- A small framed mark that agrees with a word beside it: a check, a dash, a question mark, an exclamation mark.
local function Indicator(parent)
    local G = Wg()
    local pal = G.pal
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(16, 16)
    f:EnableMouse(true)
    G.Surface(f, pal.well, 1, pal.control, 0.9)
    f.check = f:CreateTexture(nil, "OVERLAY")
    f.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    f.check:SetPoint("CENTER", 0, 0)
    f.check:SetSize(20, 20)
    f.dash = G.Solid(f, "OVERLAY", pal.bronzeText, 1)
    f.dash:SetSize(8, 2)
    f.dash:SetPoint("CENTER", 0, 0)
    f.mark = G.Text(f, "small")
    f.mark:SetPoint("CENTER", 0, 0)
    function f:Set(state)
        local c = StateColor(state)
        self.check:SetShown(state == "met")
        self.dash:SetShown(state == "unmet")
        self.mark:SetShown(state == "unknown" or state == "invalid")
        self.mark:SetText(state == "invalid" and "!" or "?")
        self.check:SetVertexColor(c[1], c[2], c[3], 1)
        self.dash:SetColorTexture(c[1], c[2], c[3], 1)
        G.Color(self.mark, c)
        self:SetBackdropBorderColor(c[1], c[2], c[3], 0.8)
    end
    return f
end

local function Truncate(text, n)
    if #text <= n then return text end
    return text:sub(1, n - 3):gsub("[\192-\255][\128-\191]*$", "") .. "..."
end

-- How many levels of lists a stored node needs below the one it sits in (a condition 0, a group 1 and more).
local function Levels(entry)
    if not entry.group then return 0 end
    local deepest = 0
    for _, child in ipairs(entry.children) do
        local l = Levels(child)
        if l > deepest then deepest = l end
    end
    return 1 + deepest
end

-- The group entry (nil for the top level) that holds an entry, the list it sits in, and its place there.
local function ParentOf(v, entry)
    local path = entry.path
    local list, owner = v.conditions, nil
    for i = 1, #path - 1 do
        owner = list[path[i]]
        if not owner then return nil end
        list = owner.children
    end
    return owner, list, path[#path]
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function Dz.Build(parent, env)
    local K = Kit()
    local G = Wg()
    local pal = G.pal
    local I = R.Interact
    local s = K.Section(parent, R.Icons and R.Icons.Get("reminderDesigner") and "reminderDesigner" or "reminderWhen", "When",
        "Who it is for, and the conditions that decide when it shows. A reminder shows while its conditions hold, and is hidden the rest of the time.")
    local parts = {}
    local function Add(el) parts[#parts + 1] = el return el end

    local function Did(ok, why)
        if not ok then env.Say(why, "warn") end
        return ok
    end
    local function Poke() env.Changed() end

    ---------------------------------------------------------------- the three block headings
    s.whoHead = Add(G.Text(s, "heading"))
    s.whoHead:SetText("Who is this for?")
    s.ruleHead = Add(G.Text(s, "heading"))
    s.ruleHead:SetText("Show this reminder when...")
    s.whyHead = Add(G.Text(s, "heading"))
    s.whyHead:SetText("Why would it show?")
    s.divs = {}
    for i = 1, 2 do s.divs[i] = Add(G.Solid(s, "ARTWORK", pal.bronzeLo, 0.5)) end

    ---------------------------------------------------------------- who
    s.who = Add(G.Text(s, "body"))
    s.who:SetWidth(W - PAD * 2 - 90)
    s.who:SetWordWrap(true)
    s.whoEdit = Add(G.Button(s, "Edit", 64, "secondary", function()
        if ui.mode == "target" then ui.mode = nil else ui.mode = "target" end
        Poke()
    end))
    I.Tip(s.whoEdit, "Who is this for?", "Which characters this reminder is for, and whether it is only for one class. A reminder for someone else never looks at anything.")

    local tp = CreateFrame("Frame", nil, s, "BackdropTemplate")
    tp:SetWidth(W - PAD * 2)
    G.Surface(tp, pal.band, 1, pal.teal, 0.55)
    Add(tp)
    s.target = tp
    tp.chips = {}
    local WHO = {
        { "all", "Every character", "Every character using this profile." },
        { "me", "This character only", "Only the character you are playing now." },
        { "chosen", "Characters I choose", "Only the characters you add here: log in on each one and press Add this character." },
    }
    local function SetWho(value)
        local id, me = env.id(), RM().CharacterKey()
        if value == "all" then Did(RM().SetScope(id, "who", "all")) return end
        if not me then env.Say("The game hasn't said which character this is yet. Try again in a moment.", "warn") return end
        if value == "me" then
            local view = env.view()
            for _, c in ipairs(view.scope.characters) do if c ~= me then RM().RemoveCharacter(id, c) end end
        end
        Did(RM().AddCharacter(id, me))
        Did(RM().SetScope(id, "who", "characters"))
    end
    for i, w in ipairs(WHO) do
        local chip = G.Tab(tp, w[2], 150, function() SetWho(w[1]) end)
        TipHook(chip, w[2], w[3])
        tp.chips[i] = chip
    end
    tp.names = G.Text(tp, "small")
    tp.names:SetWidth(W - PAD * 4)
    tp.addMe = G.Button(tp, "Add this character", 150, "secondary", function() Did(RM().AddCharacter(env.id(), RM().CharacterKey())) end)
    tp.removeMe = G.Button(tp, "Remove this character", 170, "secondary", function() Did(RM().RemoveCharacter(env.id(), RM().CharacterKey())) end)
    tp.classLabel = G.Text(tp, "body")
    tp.classLabel:SetText("Only for class")
    tp.class = G.Dropdown(tp, 200, function(v) Did(RM().SetScope(env.id(), "class", v ~= "" and v or nil)) end)
    tp.class:SetChoices(function()
        local out = { { value = "", label = "Any class" } }
        for _, c in ipairs(RM().CLASSES) do out[#out + 1] = { value = c, label = RM().ClassName(c) } end
        return out
    end)
    I.Tip(tp.class, "Only for class", "Limits which characters this reminder runs for, whatever its conditions: a reminder for another class never looks at anything. To show for several classes, or for a class only in some situations, add \"Your class\" conditions to the rule instead.")
    tp.note = G.Text(tp, "small")
    tp.note:SetWidth(W - PAD * 4)
    tp.note:SetText("This decides whether the reminder runs at all. A \"Your class\" condition in the rule is part of the rule instead, and is never moved here.")
    tp.done = G.Button(tp, "Done", 90, "primary", function() ui.mode = nil; Poke() end)

    ---------------------------------------------------------------- the tree: group boxes, then cards
    local function MakeGroup(top)
        local g = {}
        g.box = CreateFrame("Frame", nil, s, "BackdropTemplate")
        G.Surface(g.box, pal.ink, 0.12, pal.bronzeLo, 0.5)
        Add(g.box)
        g.rail = G.Solid(g.box, "ARTWORK", pal.bronzeText, 0.6)
        g.rail:SetWidth(RAIL)
        g.rail:SetPoint("TOPLEFT", 1, -1)
        g.rail:SetPoint("BOTTOMLEFT", 1, 1)
        g.heading = Add(G.Text(g.box, "body"))
        g.heading:SetWordWrap(false)
        g.folded = Add(G.Text(g.box, "small"))
        g.folded:SetWordWrap(false)
        g.outcome = Add(G.Text(g.box, "small"))
        g.outcome:SetWordWrap(true)
        g.problem = Add(G.Text(g.box, "small"))
        g.problem:SetWordWrap(true)
        g.empty = Add(G.Text(g.box, "small"))
        g.empty:SetWordWrap(true)
        g.top = top
        if not top then
            g.fold = Add(CreateFrame("Button", nil, g.box))
            g.fold:SetSize(20, 20)
            g.fold.down = G.Chevron(g.fold, g.fold, "CENTER", 0, 0, true, pal.tealHi)
            g.fold.up = G.Chevron(g.fold, g.fold, "CENTER", 0, 0, false, pal.tealHi)
            G.Hover(g.fold, pal.text, 0.06)
            g.fold:SetScript("OnClick", function()
                if not g.raw then return end
                folded[g.raw] = (not folded[g.raw]) or nil
                ui.mode, ui.nodeRaw, ui.groupRaw, ui.draft = nil, nil, nil, nil   -- what was open inside it is put away
                Poke()
            end)
            I.Tip(g.fold, "Fold this group", "Folds the group to one line, or opens it again. Nothing in it changes.")
            g.more = Add(G.Dropdown(g.box, MORE_W, function(value) Dz.MenuPick(g, value) end))
            g.more:SetValue(nil, "More")
            g.more.menuWidth, g.more.menuAlignRight = 340, true
            g.more:SetChoices(function() return Dz.MenuFor(g.raw) end)
            I.Tip(g.more, "More", "Duplicate this group, move it up or down or into another group, or remove it with what is in it.")
        end
        for _, match in ipairs({ "all", "any" }) do
            local seg = Add(G.Tab(g.box, Pl().Words(match).short, 46, function()
                local e = g.raw and RM().NodeByRaw(env.view(), g.raw)
                if top then Did(RM().SetMatch(env.id(), match)) elseif e then Did(RM().SetMatch(env.id(), match, e.path)) end
            end))
            TipHook(seg, Pl().Words(match).technical, Pl().Words(match).tip)
            g["seg" .. match] = seg
        end
        g.add = Add(G.Button(g.box, "Add a condition", 140, "secondary", function()
            ui.mode, ui.groupRaw, ui.nodeRaw, ui.draft = "pick", g.raw or "top", nil, nil
            ui.query = ""
            Poke()
        end))
        return g
    end
    s.rootGroup = MakeGroup(true)
    s.groups = {}
    for j = 1, RM().MAX_GROUPS do s.groups[j] = MakeGroup(false) end
    stats.groups = RM().MAX_GROUPS + 1

    s.seps = {}
    for i = 1, RM().MAX_CONDITIONS + RM().MAX_GROUPS do s.seps[i] = Add(G.Text(s, "meta")) end

    s.cards = {}
    for i = 1, RM().MAX_CONDITIONS do
        local card = CreateFrame("Button", nil, s, "BackdropTemplate")
        G.Surface(card, pal.bg, 0.95, pal.control, 0.55)
        G.Hover(card, pal.text, 0.04)
        Add(card)
        card.icon = card:CreateTexture(nil, "ARTWORK")
        card.icon:SetSize(ICON, ICON)
        card.icon:SetPoint("TOPLEFT", 10, -9)
        card.text = G.Text(card, "body")
        card.text:SetWordWrap(true)
        card.note = G.Text(card, "small")
        card.note:SetWordWrap(true)
        card.state = Indicator(card)
        I.Tip(card.state, "Why", function() return card.stateTip end)
        card.edit = G.Button(card, "Edit", EDIT_W, "secondary", function() Dz.Edit(card.raw) end)
        card.more = G.Dropdown(card, MORE_W, function(value) Dz.MenuPick(card, value) end)
        card.more:SetValue(nil, "More")
        card.more.menuWidth, card.more.menuAlignRight = 340, true
        card.more:SetChoices(function() return Dz.MenuFor(card.raw) end)
        card:SetScript("OnClick", function() Dz.Edit(card.raw) end)
        I.Tip(card, "Edit this condition", function()
            local e = card.raw and RM().NodeByRaw(env.view(), card.raw)
            if e and not e.cond then return "This condition can't be edited here.", Pl().Technical(e) end
            return "Click to change it. Nothing is saved until you press Done."
        end)
        I.Tip(card.more, "More", "Duplicate this condition, move it up or down or into another group, or remove it.")
        s.cards[i] = card
    end
    stats.cards = RM().MAX_CONDITIONS

    s.note = Add(G.Text(s, "small"))
    s.note:SetWidth(W - PAD * 2)
    s.limit = Add(G.Text(s, "small"))
    s.limit:SetWidth(W - PAD * 2)
    s.undoText = Add(G.Text(s, "small"))
    s.undoText:SetWidth(W - PAD * 2 - 90)
    s.undo = Add(G.Button(s, "Undo", 70, "secondary", function() Dz.Undo() end))
    I.Tip(s.undo, "Undo", "Puts back what you just removed, where it was, if that place is still there.")

    ---------------------------------------------------------------- the one editor
    local ep = CreateFrame("Frame", nil, s, "BackdropTemplate")
    G.Surface(ep, pal.band, 1, pal.teal, 0.7)
    Add(ep)
    s.editor = ep
    ep.title = G.Text(ep, "heading")
    ep.subjectLabel = G.Text(ep, "small")
    ep.subjectLabel:SetText("What to check")
    ep.subject = G.Dropdown(ep, 190, function(value)
        if not ui.draft then return end
        local new = Pl().WithSubject(ui.draft, value)
        if new then ui.draft = new end
        Poke()
    end)
    ep.subject:SetChoices(function() return Pl().Subjects() end)
    ep.op = G.Dropdown(ep, 86, function(value)
        if ui.draft then ui.draft = Pl().WithNegate(ui.draft, value == "isnot") end
        Poke()
    end)
    ep.op:SetChoices(function() return { { value = "is", label = "is" }, { value = "isnot", label = "is not" } } end)
    ep.value = G.Dropdown(ep, 200, function(value)
        if ui.draft then ui.draft = Pl().WithValue(ui.draft, value) end
        Poke()
    end)
    ep.value:SetChoices(function() return ui.draft and Pl().ValueChoices(ui.draft) or {} end)
    ep.item = G.EditBox(ep, 110, 22)
    ep.item:SetMaxLetters(200)
    local function TakeItem(text)
        local id = RM().ParseItem(text)
        if not id then env.Say("That isn't an item ID. Type the number from the item's link, paste the link, or drop the item on the box.", "warn") return end
        ep.item:ClearFocus()
        if ui.draft then ui.draft = Pl().WithItem(ui.draft, id) end
        Poke()
    end
    ep.item:SetScript("OnEnterPressed", function(self) TakeItem(self:GetText()) end)
    ep.item:SetScript("OnReceiveDrag", function()
        local kind, id = GetCursorInfo()
        if kind ~= "item" then return end
        ClearCursor()   -- the item goes straight back where it came from; only its ID is noted
        TakeItem(tostring(id or ""))
    end)
    I.Tip(ep.item, "Item", "Its item ID, its link pasted here, or the item dropped here from your bags (it goes straight back). Press Enter.")
    ep.itemInfo = G.Text(ep, "small")
    ep.help = G.Text(ep, "small")
    ep.help:SetWordWrap(true)
    ep.reads = G.Text(ep, "body")
    ep.reads:SetWordWrap(true)
    ep.problem = G.Text(ep, "small")
    ep.problem:SetWordWrap(true)
    ep.done = G.Button(ep, "Done", 100, "primary", function() Dz.Commit() end)
    ep.cancel = G.Button(ep, "Cancel", 90, "secondary", function() ui.mode, ui.nodeRaw, ui.draft = nil, nil, nil; Poke() end)
    I.Tip(ep.cancel, "Cancel", "Closes this without changing anything: the saved condition stays as it was.")

    ---------------------------------------------------------------- the one picker
    local pp = CreateFrame("Frame", nil, s, "BackdropTemplate")
    G.Surface(pp, pal.band, 1, pal.teal, 0.7)
    Add(pp)
    s.picker = pp
    pp.title = G.Text(pp, "heading")
    pp.where = G.Text(pp, "small")
    pp.where:SetWordWrap(true)
    pp.search = G.EditBox(pp, 220, 22)
    pp.search:SetMaxLetters(40)
    pp.search:SetScript("OnTextChanged", function(self, user)
        if user == false then return end
        ui.query = self:GetText()
        Poke()
    end)
    pp.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    I.Tip(pp.search, "Search", "A few letters of what you want to check: combat, ammunition, shield, class...")
    pp.cats = {}
    pp.rows = {}
    pp.none = G.Text(pp, "small")
    pp.cancel = G.Button(pp, "Cancel", 90, "secondary", function() ui.mode, ui.groupRaw = nil, nil; Poke() end)
    pp.back = G.Button(pp, "Back", 90, "secondary", function() ui.mode = "pick"; Poke() end)
    pp.newAny = G.Button(pp, "Allow either condition", 190, "secondary", function() Dz.AddGroup("any") end)
    pp.newAll = G.Button(pp, "Require several together", 190, "secondary", function() Dz.AddGroup("all") end)
    pp.newNote = G.Text(pp, "small")
    pp.newNote:SetWordWrap(true)
    I.Tip(pp.newAny, "Allow either condition", "A new group where at least one of its conditions must be true: \"this, or that\".")
    I.Tip(pp.newAll, "Require several together", "A new group where all of its conditions must be true.")

    local function PickRow(i)
        if pp.rows[i] then return pp.rows[i] end
        local row = CreateFrame("Button", nil, pp, "BackdropTemplate")
        G.Surface(row, pal.bg, 0.9, pal.control, 0.4)
        G.Hover(row, pal.text, 0.05)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON, ICON)
        row.icon:SetPoint("LEFT", 10, 0)
        row.name = G.Text(row, "body")
        row.name:SetPoint("TOPLEFT", ICON + 20, -6)
        row.name:SetWordWrap(false)
        row.blurb = G.Text(row, "small")
        row.blurb:SetPoint("TOPLEFT", ICON + 20, -22)
        row.blurb:SetWordWrap(true)
        row.note = G.Text(row, "small")
        row.note:SetWordWrap(true)
        row:SetScript("OnClick", function(self)
            if self.entry then Dz.Pick(self.entry)
            elseif self.isGroup then ui.mode = "newgroup"; Poke() end
        end)
        pp.rows[i] = row
        stats.pickerRows = #pp.rows
        return row
    end

    ---------------------------------------------------------------- why
    s.lines = {}
    for i = 1, LINES do s.lines[i] = Add(G.Text(s, "small")) end
    s.explain = Add(CreateFrame("Button", nil, s))
    s.explain:SetSize(320, 22)
    s.explain.text = G.Text(s.explain, "small")
    s.explain.text:SetPoint("LEFT", 16, 0)
    G.Color(s.explain.text, pal.tealHi)
    s.explain.down = G.Chevron(s.explain, s.explain, "LEFT", 7, 0, true, pal.tealHi)
    s.explain.up = G.Chevron(s.explain, s.explain, "LEFT", 7, 0, false, pal.tealHi)
    s.explain:SetScript("OnClick", function() explainOpen = not explainOpen; Poke() end)
    I.Tip(s.explain, "Would this show now?", "Checks the rule against what the game reports right now, condition by condition. It only reads: nothing is shown on screen and nothing about you changes. While this is closed, nothing is checked for it.")
    s.exMark = Indicator(s)
    Add(s.exMark)
    s.exHead = Add(G.Text(s, "body"))
    s.exReason = Add(G.Text(s, "small"))
    s.exReason:SetWidth(W - PAD * 2 - 22)
    s.exScope = Add(G.Text(s, "small"))
    s.exScope:SetWidth(W - PAD * 2 - 22)
    s.exStatus = Add(G.Text(s, "small"))
    s.exStatus:SetWidth(W - PAD * 2 - 22)
    s.exNote = Add(G.Text(s, "small"))
    s.exNote:SetWidth(W - PAD * 2 - 22)

    ---------------------------------------------------------------- everything that is placed is hidden first
    local function HideAll()
        for _, el in ipairs(parts) do el:Hide() end
        for _, row in ipairs(pp.rows) do row:Hide() end
        for _, c in ipairs(pp.cats) do c:Hide() end
        for _, c in ipairs(s.cards) do
            for _, k in ipairs({ "text", "note", "state", "edit", "more", "icon" }) do c[k]:Hide() end
        end
        for _, c in ipairs(tp.chips) do c:Hide() end
        for _, el in ipairs({ tp.names, tp.addMe, tp.removeMe, tp.classLabel, tp.class, tp.note, tp.done }) do el:Hide() end
        for _, el in ipairs({ ep.title, ep.subjectLabel, ep.subject, ep.op, ep.value, ep.item, ep.itemInfo, ep.help, ep.reads, ep.problem, ep.done, ep.cancel }) do el:Hide() end
        for _, el in ipairs({ pp.title, pp.where, pp.search, pp.none, pp.cancel, pp.back, pp.newAny, pp.newAll, pp.newNote }) do el:Hide() end
    end

    ---------------------------------------------------------------- actions (the cards' and groups' menus)
    local menuDests   -- the groups the last Move into list offered, by its position
    local function Entry(raw) return raw and RM().NodeByRaw(env.view(), raw) end

    function Dz.Edit(raw)
        local e = Entry(raw)
        if not e then return end
        if not e.cond then
            env.Say(e.provider and "That condition's settings can't be read, so it can't be edited: remove it and add it again." or
                "That kind of condition isn't known to this version of TwichUI, so it is kept as it is. Remove it if you don't want it.", "warn")
            return
        end
        ui.mode, ui.nodeRaw, ui.groupRaw = "edit", raw, nil
        ui.draft = RM().DeepCopy(e.cond)
        ui.before = RM().DeepCopy(e.cond)
        env.Say(nil)
        Poke()
    end

    local function DestLabel(g, v)
        if not g then return "the whole rule: " .. Pl().Words(v.match).heading end
        return ("%s of: %s"):format(Pl().Words(g.match).short, Truncate(Pl().GroupLine(g), 38))
    end

    function Dz.MenuFor(raw)
        local v = env.view()
        local e = Entry(raw)
        if not (v and e) then return {} end
        local owner, list, index = ParentOf(v, e)
        local out, dests = {}, {}
        if not e.group and e.cond then out[#out + 1] = { value = "edit", label = "Edit" } end
        out[#out + 1] = { value = "dup", label = e.group and "Duplicate group" or "Duplicate" }
        if index and index > 1 then out[#out + 1] = { value = "up", label = "Move up" } end
        if index and list and index < #list then out[#out + 1] = { value = "down", label = "Move down" } end
        -- where it could move to: another group, if the depth allows
        local need = Levels(e)
        local function Reach(g, gpath)
            if g == owner then return end
            if e.group then
                if g == e then return end
                -- not into what it holds
                local inside = #gpath >= #e.path
                for i, n in ipairs(e.path) do if gpath[i] ~= n then inside = false break end end
                if inside then return end
            end
            if #gpath + 1 + need > RM().MAX_DEPTH then return end
            local key = "to:" .. (#dests + 1)
            dests[#dests + 1] = g or "top"
            out[#out + 1] = { value = key, label = "Move into: " .. DestLabel(g, v) }
        end
        if owner then Reach(nil, {}) end
        for _, g in ipairs(v.groups) do Reach(g, g.path) end   -- an empty group included: it is where a condition is wanted
        out[#out + 1] = { value = "remove", label = e.group and "Remove group and what is in it" or "Remove" }
        menuDests = dests
        return out
    end

    local function Remove(e)
        local v = env.view()
        local id = env.id()
        local owner, _, index = ParentOf(v, e)
        local record = { id = id, node = e.raw, parentRaw = owner and owner.raw or "top", index = index, label = e.group and "a group" or Pl().Sentence(e) }
        local ok, why = RM().RemoveNode(id, e.path)
        if not ok then env.Say(why, "warn") return end
        undo = record
        if ui.nodeRaw == e.raw then ui.mode, ui.nodeRaw, ui.draft = nil, nil, nil end
        if ui.groupRaw == e.raw then ui.mode, ui.groupRaw = nil, nil end
        Poke()
    end

    -- the number of conditions in a group, those in groups inside it included
    local function CountIn(entry)
        local n = 0
        for _, child in ipairs(entry.children or {}) do n = n + (child.group and CountIn(child) or 1) end
        return n
    end

    function Dz.MenuPick(owner, value)
        local v = env.view()
        local e = Entry(owner.raw)
        if not (v and e) then return end
        local id = env.id()
        local parent, _, index = ParentOf(v, e)
        local parentPath = parent and parent.path or {}
        if value == "edit" then
            Dz.Edit(owner.raw)
        elseif value == "dup" then
            if Did(RM().DuplicateNode(id, e.path)) then env.Say("Made a copy right after it.", "ok") end
        elseif value == "up" or value == "down" then
            Did(RM().MoveNode(id, e.path, parentPath, index + (value == "up" and -1 or 1)))
        elseif value == "remove" then
            local n = e.group and CountIn(e) or 0
            if e.group and n > 0 then
                local raw = e.raw
                local text = ("Remove this group and the %d condition%s in it?\n\nOnly this group is removed; the rest of the reminder stays as it is. You can undo it right afterwards."):format(n, n == 1 and "" or "s")
                I.Confirm("TWICHUI_REMINDER_GROUP_DELETE", text, function()
                    local cur = Entry(raw)
                    if cur then Remove(cur) end
                end, { accept = "Remove", valid = function()
                    if Entry(raw) then return true end
                    return false, "That group is already gone, so nothing was removed."
                end })
            else
                Remove(e)
            end
        else
            local at = tonumber(value:match("^to:(%d+)$"))
            local dest = at and menuDests and menuDests[at]
            if not dest then return end
            local destPath = {}
            local destGroup
            if dest ~= "top" then
                local d = RM().NodeByRaw(v, dest.raw)
                if not d then return end
                destPath, destGroup = d.path, d
            end
            if Did(RM().MoveNode(id, e.path, destPath, nil)) then
                local words = Pl().Words(destGroup and destGroup.match or v.match).heading:lower()
                env.Say(("Moved into the %s, where %s. Where a condition sits changes what it is combined with."):format(destGroup and "group" or "whole rule", words), "ok")
            end
        end
    end

    function Dz.Undo()
        local u = undo
        undo = nil
        if not u or u.id ~= env.id() then Poke() return end
        local v = env.view()
        local dest
        if u.parentRaw == "top" then
            dest = {}
        else
            local g = RM().NodeByRaw(v, u.parentRaw)
            dest = g and g.path
        end
        if not dest then env.Say("It can't be put back: the group it was in is gone.", "warn") Poke() return end
        if Did(RM().InsertNode(u.id, dest, u.index, u.node)) then env.Say("Put back.", "ok") end
        Poke()
    end

    -- Writes the editor's copy: a new condition is added to its group, an edited one replaces the saved one. A copy that
    -- isn't finished, or can't be used, is not written; what is saved stays as it was.
    function Dz.Commit()
        local draft = ui.draft
        if not draft then return end
        local CT = R.ReminderConditions
        local clean, problem = CT.Check(draft)
        if not clean then env.Say(Pl().Problem({ provider = true, why = problem }) or RM().REFUSE.value, "warn") return end
        if problem and not Pl().Capability({ cond = clean }) then env.Say(problem:gsub("^%l", string.upper), "warn") return end
        local id = env.id()
        local v = env.view()
        if ui.mode == "edit" then
            local e = Entry(ui.nodeRaw)
            if not e then
                ui.mode, ui.nodeRaw, ui.draft = nil, nil, nil
                env.Say("That condition has changed since it was opened, so nothing was saved.", "warn")
                Poke()
                return
            end
            local same = true
            for k, val in pairs(clean) do if (ui.before or {})[k] ~= val then same = false end end
            for k, val in pairs(ui.before or {}) do if clean[k] ~= val then same = false end end
            if not same and not Did(RM().SetCondition(id, e.path, clean)) then return end
        else
            local path
            if ui.groupRaw ~= "top" then
                local g = Entry(ui.groupRaw)
                if not g then
                    ui.mode, ui.groupRaw, ui.draft = nil, nil, nil
                    env.Say("The group it was for has changed since, so nothing was added.", "warn")
                    Poke()
                    return
                end
                path = g.path
            end
            if not Did(RM().AddCondition(id, clean.type, path, clean)) then return end
        end
        -- a reminder that shows an item's icon and has none yet uses this one (it can be changed in Show)
        if clean.type == "equipment" and clean.what == "item" and clean.item then
            local d = v and v.display
            if d and d.iconSource == "item" and not d.item then RM().SetDisplay(id, "item", clean.item) end
        end
        ui.mode, ui.nodeRaw, ui.draft, ui.groupRaw = nil, nil, nil, nil
        Poke()
    end

    function Dz.Pick(entry)
        ui.mode, ui.draft, ui.pickedName = "new", entry.make(), entry.name
        ui.entry = entry
        Poke()
    end

    function Dz.AddGroup(match)
        local path
        if ui.groupRaw ~= "top" then
            local g = Entry(ui.groupRaw)
            if not g then ui.mode, ui.groupRaw = nil, nil Poke() return end
            path = g.path
        end
        local ok, newPath = RM().AddGroup(env.id(), path, match)
        if not Did(ok, newPath) then return end
        ui.mode, ui.groupRaw = nil, nil
        env.Say(("Added an empty group where %s. Add its conditions next: it can't be used until it has one."):format(Pl().Words(match).heading:lower()), "ok")
        Poke()
    end

    ---------------------------------------------------------------- panels
    local function LayoutTarget(self, v, x, y, w)
        local me = RM().CharacterKey()
        local sc = v.scope
        local who = "all"
        if sc.who == "characters" then who = (#sc.characters == 1 and sc.characters[1] == me) and "me" or "chosen" end
        tp:SetWidth(w)
        K.Put(tp, self, x, y)
        local h = 10
        local cx = 10
        for i, chip in ipairs(tp.chips) do
            chip:SetSelected(WHO[i][1] == who)
            K.Put(chip, tp, cx, h)
            cx = cx + 158
        end
        h = h + 32
        if who == "chosen" then
            local names = #sc.characters > 0 and table.concat(sc.characters, ", ") or "No character added yet."
            h = h + K.Text(tp.names, names, #sc.characters == 0 and "warn" or nil, 10, h, tp) + 6
            local mine = false
            for _, c in ipairs(sc.characters) do if c == me then mine = true end end
            K.Put(mine and tp.removeMe or tp.addMe, tp, 10, h)
            h = h + 30
        end
        K.Put(tp.classLabel, tp, 10, h + 4)
        tp.class:SetValue(sc.class or "", sc.class and RM().ClassName(sc.class) or "Any class")
        K.Put(tp.class, tp, 120, h)
        h = h + 32
        h = h + K.Text(tp.note, tp.note:GetText(), "quiet", 10, h, tp) + 8
        K.Put(tp.done, tp, 10, h)
        h = h + 32
        tp:SetHeight(h)
        return h
    end

    local function LayoutEditor(self, x, y, w)
        local draft = ui.draft
        ep:SetWidth(w)
        K.Put(ep, self, x, y)
        local isNew = ui.mode == "new"
        local h = 10
        K.Text(ep.title, isNew and ("Add: " .. (ui.pickedName or "a condition")) or "Edit this condition", nil, 12, h, ep)
        G.Color(ep.title, pal.bronzeText)
        h = h + 22
        local cx = 12
        if not isNew then
            K.Put(ep.subjectLabel, ep, cx, h)
            h = h + 14
            local sv, sl = Pl().SubjectOf(draft)
            ep.subject:SetValue(sv, sl)
            K.Put(ep.subject, ep, cx, h)
            cx = cx + 198
        end
        if Pl().HasOperator(draft) then
            ep.op:SetValue(draft.negate and "isnot" or "is", draft.negate and "is not" or "is")
            K.Put(ep.op, ep, cx, h)
            cx = cx + 94
        end
        ep.value:SetValue(Pl().ValueKey(draft), Pl().ValueLabel(draft))
        K.Put(ep.value, ep, cx, h)
        h = h + 32
        if Pl().NeedsItem(draft) then
            if not ep.item:HasFocus() then ep.item:SetText(draft.item and tostring(draft.item) or "") end
            K.Put(ep.item, ep, 12, h)
            local text, tone = K.ItemLine(draft.item)
            K.Text(ep.itemInfo, text, tone, 132, h + 5, ep)
            h = h + 30
        end
        ep.help:SetWidth(w - 24)
        h = h + K.Text(ep.help, Pl().Help(draft), "quiet", 12, h, ep) + 8
        ep.reads:SetWidth(w - 24)
        local sentence = Pl().CondSentence(draft) or "(not finished)"
        h = h + K.Text(ep.reads, "Reads as: " .. sentence, nil, 12, h, ep) + 6
        local clean, problem = R.ReminderConditions.Check(draft)
        local short, long = Pl().Capability({ cond = clean })
        local blocked = (not clean) or (problem and not short)
        ep.problem:SetWidth(w - 24)
        if short then
            h = h + K.Text(ep.problem, short .. " " .. long .. " A reminder that uses it can't be turned on here.", "warn", 12, h, ep) + 6
        elseif problem then
            h = h + K.Text(ep.problem, problem:gsub("^%l", string.upper), "warn", 12, h, ep) + 6
        end
        ep.done.text:SetText(isNew and "Add condition" or "Done")
        ep.done:SetWidth(isNew and 130 or 100)
        ep.done:SetEnabled(not blocked)
        K.Put(ep.done, ep, 12, h)
        K.Put(ep.cancel, ep, 12 + (isNew and 138 or 108), h)
        h = h + 34
        ep:SetHeight(h)
        return h
    end

    local function PickerHeight(self, v, x, y, w, groupEntry)
        pp:SetWidth(w)
        K.Put(pp, self, x, y)
        local match = groupEntry and groupEntry.match or v.match
        local h = 10
        K.Text(pp.title, match == "any" and "Allow another condition" or "Require another condition", nil, 12, h, pp)
        G.Color(pp.title, pal.bronzeText)
        h = h + 20
        pp.where:SetWidth(w - 24)
        h = h + K.Text(pp.where, ("Adding to the group where %s."):format(Pl().Words(match).heading:lower()), "quiet", 12, h, pp) + 8
        if ui.mode == "newgroup" then
            local words = Pl().Words(match).heading
            pp.newNote:SetWidth(w - 24)
            h = h + K.Text(pp.newNote, ("A new group will be added inside \"%s\". It starts empty, and can't be used until you add a condition to it. Choose how its conditions combine:"):format(words), nil, 12, h, pp) + 8
            K.Put(pp.newAny, pp, 12, h)
            K.Put(pp.newAll, pp, 210, h)
            h = h + 32
            K.Put(pp.back, pp, 12, h)
            h = h + 34
            pp:SetHeight(h)
            return h
        end
        K.Put(pp.search, pp, 12, h)
        if not pp.search:HasFocus() then pp.search:SetText(ui.query or "") end
        -- categories that have something to offer
        local entries = Pl().Entries()
        local present, order = {}, {}
        for _, e in ipairs(entries) do
            if not present[e.category] then present[e.category] = true end
        end
        for _, c in ipairs(Pl().CATEGORIES) do if present[c] then order[#order + 1] = c end end
        local cx = 244
        local all = pp.cats[1]
        if not all then
            all = G.Tab(pp, "All", 56, function() ui.category = nil; Poke() end)
            pp.cats[1] = all
        end
        all:SetSelected(ui.category == nil)
        K.Put(all, pp, cx, h - 2)
        cx = cx + 60
        for i, c in ipairs(order) do
            local tab = pp.cats[i + 1]
            if not tab then
                tab = G.Tab(pp, c, 84, function(self) ui.category = self.category; Poke() end)
                pp.cats[i + 1] = tab
            end
            tab.category = c
            tab.text:SetText(c)
            tab:SetSelected(ui.category == c)
            K.Put(tab, pp, cx, h - 2)
            cx = cx + 88
        end
        h = h + 32
        local shown = 0
        for _, e in ipairs(entries) do
            if (ui.category == nil or e.category == ui.category) and Pl().Matches(e, ui.query) then
                shown = shown + 1
                local row = PickRow(shown)
                row.entry, row.isGroup = e, false
                R.Icons.Apply(row.icon, e.icon, ICON)
                row.name:SetText(e.name .. "  -  " .. e.category)
                row.blurb:SetWidth(w - 24 - ICON - 20)
                row.blurb:SetText(e.blurb)
                local bh = row.blurb:GetStringHeight() or 12
                local nh = 0
                if e.note then
                    row.note:SetWidth(w - 24 - ICON - 20)
                    row.note:SetText(e.note)
                    row.note:ClearAllPoints()
                    row.note:SetPoint("TOPLEFT", ICON + 20, -(24 + bh))
                    Color(row.note, "unmet")
                    row.note:Show()
                    nh = (row.note:GetStringHeight() or 12) + 2
                else
                    row.note:Hide()
                end
                row:SetSize(w - 24, 30 + bh + nh)
                K.Put(row, pp, 12, h)
                h = h + 30 + bh + nh + 4
            end
        end
        if shown == 0 then
            h = h + K.Text(pp.none, "Nothing matches. Try fewer letters, or All.", "quiet", 12, h, pp) + 6
        end
        -- a group is a structure, so it is offered apart from the conditions, and says what it will be
        local limit
        local at = groupEntry and #groupEntry.path or 0
        if at + 2 > RM().MAX_DEPTH then limit = RM().REFUSE.tooDeep
        elseif v.counts.groups >= RM().MAX_GROUPS then limit = RM().REFUSE.groupsFull end
        if not limit then
            local row = PickRow(shown + 1)
            row.entry, row.isGroup = nil, true
            R.Icons.Apply(row.icon, "reminderWhen", ICON)
            row.name:SetText("Create a condition group")
            row.blurb:SetWidth(w - 24 - ICON - 20)
            row.blurb:SetText("A group counts as one item inside this one: for \"this, or that\", or \"both of these\". You choose how it combines next.")
            local bh = row.blurb:GetStringHeight() or 12
            row.note:Hide()
            row:SetSize(w - 24, 30 + bh)
            K.Put(row, pp, 12, h)
            h = h + 30 + bh + 4
        else
            h = h + K.Text(pp.newNote, limit, "quiet", 12, h, pp) + 6
        end
        K.Put(pp.cancel, pp, 12, h)
        h = h + 34
        pp:SetHeight(h)
        return h
    end

    ---------------------------------------------------------------- the tree
    -- A list of entries (the top level's, or a group's) in its box, from y. Returns the y below the box.
    local function LayoutGroup(self, v, owner, depth, x, w, y, st, ex)
        local top = owner == nil
        local g
        if top then g = self.rootGroup else
            st.group = st.group + 1
            g = self.groups[st.group]
        end
        if not g then return y end
        local entries = top and v.conditions or owner.children
        local match = top and v.match or owner.match
        local n = #entries
        g.raw = owner and owner.raw or nil
        local boxTop = y
        local cur = y + 6
        local inner = x + RAIL + INSET
        local cw = w - (RAIL + INSET) - 10
        local function Rel(yAbs) return yAbs - boxTop end
        local showHead = not top or n >= 2
        local words = Pl().Words(match)
        local isFolded = (not top) and owner.raw and folded[owner.raw]
        if showHead then
            local hx = 10
            if g.fold then
                K.Put(g.fold, g.box, hx - 2, Rel(cur) + 4)
                for _, t in ipairs(g.fold.down) do t:SetShown(isFolded and true or false) end
                for _, t in ipairs(g.fold.up) do t:SetShown(not isFolded) end
                hx = hx + 22
            end
            g.heading:SetText(words.heading)
            g.heading:SetWidth(w - hx - (top and 120 or 200))
            K.Put(g.heading, g.box, hx, Rel(cur) + 8)
            G.Color(g.heading, pal.text)
            local right = w - 10
            for _, m in ipairs({ "any", "all" }) do
                local seg = g["seg" .. m]
                seg:SetSelected(match == m)
                right = right - 46
                K.Put(seg, g.box, right, Rel(cur) + 2)
            end
            if g.more then
                right = right - MORE_W - 8
                K.Put(g.more, g.box, right, Rel(cur) + 4)
            end
            g.rail:SetColorTexture((match == "any" and pal.teal or pal.bronzeText)[1], (match == "any" and pal.teal or pal.bronzeText)[2], (match == "any" and pal.teal or pal.bronzeText)[3], 0.6)
            cur = cur + HEAD_H + 2
        else
            g.rail:SetColorTexture(pal.bronzeText[1], pal.bronzeText[2], pal.bronzeText[3], 0.6)
        end
        if isFolded then
            K.Text(g.folded, Pl().GroupLine(owner), "quiet", 10 + 22, Rel(cur), g.box)
            g.folded:SetWidth(w - 50)
            cur = cur + 20
            g.box:SetWidth(w)
            g.box:SetHeight(cur - boxTop + 4)
            K.Put(g.box, self, x, boxTop)
            return cur + 4
        end
        if ex and ex.groups then
            local line = top and ex.groups.top or ex.groups[owner.raw]
            if line and n > 0 then
                g.outcome:SetWidth(w - 30)
                local state = top and ex.state or (ex.cards[owner.raw] and ex.cards[owner.raw].state)
                local met = state == "met" or state == "show" or state == "match"
                cur = cur + K.Text(g.outcome, line, met and "ok" or "quiet", 12, Rel(cur), g.box) + 6
            end
        end
        if owner and owner.why then
            g.problem:SetWidth(w - 30)
            cur = cur + K.Text(g.problem, Pl().Problem(owner) or "", "warn", 12, Rel(cur), g.box) + 4
        end
        if n == 0 then
            g.empty:SetWidth(w - 30)
            local text = top and "Nothing yet. A reminder with no conditions never shows: add the first one below."
                or "This group is empty, so the reminder can't be turned on until you add a condition to it or remove the group."
            cur = cur + K.Text(g.empty, text, top and "quiet" or "warn", 12, Rel(cur), g.box) + 6
        end
        for i, entry in ipairs(entries) do
            if i > 1 then
                local sep = self.seps[st.sep + 1]
                st.sep = st.sep + 1
                if sep then
                    sep:SetText(match == "any" and "or" or "and")
                    K.Put(sep, self, inner + 6, cur)
                end
                cur = cur + SEP_H
            end
            if entry.group then
                cur = LayoutGroup(self, v, entry, depth + 1, inner, cw, cur, st, ex) + 2
            else
                st.card = st.card + 1
                local card = self.cards[st.card]
                if not card then break end
                card.raw = entry.raw
                local sentence = Pl().Sentence(entry)
                local capabilityShort = Pl().Capability(entry)
                local textW = cw - (10 + ICON + 10) - (EDIT_W + MORE_W + 8 + 24)
                card.text:SetWidth(textW)
                card.text:SetText(sentence)
                G.Color(card.text, entry.cond and pal.text or pal.stone)
                local th = card.text:GetStringHeight() or 14
                card.text:ClearAllPoints()
                card.text:SetPoint("TOPLEFT", ICON + 20, -9)
                card.text:Show()
                R.Icons.Apply(card.icon, entry.cond and Pl().Icon(entry.cond) or "reminderTest", ICON)
                card.icon:Show()
                -- a second line: what is wrong with it, or (when asked) what it sees now
                local ch = 9 + th
                local cx = ex and ex.cards and ex.cards[entry.raw]
                local line, lineTone, mark
                card.stateTip = nil
                if entry.why or capabilityShort then
                    -- a short state; the longer words are on the mark's tooltip
                    local _, long = Pl().Capability(entry)
                    line, lineTone, mark = Pl().Problem(entry), "invalid", "invalid"
                    card.stateTip = long or Pl().Technical(entry)
                elseif cx then
                    mark, lineTone = cx.state, cx.state
                    line = cx.word
                    if cx.seen then line = line .. "  -  Sees: " .. cx.seen elseif cx.detail then line = line .. "  -  " .. cx.detail end
                    card.stateTip = cx.detail
                end
                if line then
                    card.state:Set(mark)
                    card.state:ClearAllPoints()
                    card.state:SetPoint("TOPLEFT", card, "TOPLEFT", ICON + 20, -(ch + 5))
                    card.state:Show()
                    card.note:SetWidth(textW - 22)
                    card.note:SetText(line)
                    Color(card.note, lineTone)
                    card.note:ClearAllPoints()
                    card.note:SetPoint("TOPLEFT", card, "TOPLEFT", ICON + 20 + 22, -(ch + 6))
                    card.note:Show()
                    ch = ch + 6 + math.max(16, card.note:GetStringHeight() or 12)
                end
                ch = math.max(ch + 10, 38)
                card:SetSize(cw, ch)
                K.Put(card, self, inner, cur)
                K.Put(card.more, card, cw - MORE_W - 10, 7)
                K.Put(card.edit, card, cw - MORE_W - 10 - 8 - EDIT_W, 7)
                if not entry.cond then card.edit:SetEnabled(false) else card.edit:SetEnabled(true) end
                cur = cur + ch + GAP
                if ui.mode == "edit" and ui.nodeRaw == entry.raw and ui.draft then
                    cur = cur + LayoutEditor(self, inner, cur, cw) + GAP
                end
            end
        end
        -- where the next one goes
        if ui.groupRaw == (owner and owner.raw or "top") and (ui.mode == "pick" or ui.mode == "newgroup") then
            cur = cur + PickerHeight(self, v, inner, cur, cw, owner) + GAP
        elseif ui.groupRaw == (owner and owner.raw or "top") and ui.mode == "new" and ui.draft then
            cur = cur + LayoutEditor(self, inner, cur, cw) + GAP
        else
            local limit = v.counts.conditions >= RM().MAX_CONDITIONS
            K.Put(g.add, g.box, RAIL + INSET, Rel(cur))
            g.add:SetEnabled(not limit)
            if limit then
                cur = cur + 30 + K.Text(g.empty, RM().REFUSE.conditionsFull, "quiet", RAIL + INSET + 150, Rel(cur) + 6, g.box) - 12
            else
                cur = cur + 30
            end
        end
        g.box:SetWidth(w)
        g.box:SetHeight(cur - boxTop + 4)
        K.Put(g.box, self, x, boxTop)
        return cur + 4
    end

    ---------------------------------------------------------------- the whole section
    local function Layout(self, v, y)
        if ui.id ~= v.id then Reset(v.id) end
        HideAll()
        local me = RM().CharacterKey()
        local h = K.Top(self)
        local inner = W - PAD * 2

        -- who
        K.Put(self.whoHead, self, PAD, h)
        h = h + 20
        local th = K.Text(self.who, Pl().Targeting(v, me), (v.scope.who == "characters" and #v.scope.characters == 0) and "warn" or nil, PAD, h + 4, self)
        self.whoEdit.text:SetText(ui.mode == "target" and "Close" or "Edit")
        K.Put(self.whoEdit, self, W - PAD - 64, h)
        h = h + math.max(th + 8, 30)
        if ui.mode == "target" then h = h + LayoutTarget(self, v, PAD, h, inner) + 8 end
        K.Put(self.divs[1], self, PAD, h)
        self.divs[1]:SetSize(inner, 1)
        h = h + 12

        -- the rule
        K.Put(self.ruleHead, self, PAD, h)
        h = h + 22
        -- what each condition sees right now, only while asked for
        local ex
        if explainOpen then
            local CT = R.ReminderController
            local out, status = CT.Inspect(v.id)
            ex = Pl().Explain(v, out, status, R.ReminderState and R.ReminderState.Context and R.ReminderState.Context())
        end
        h = LayoutGroup(self, v, nil, 1, PAD, inner, h, { card = 0, group = 0, sep = 0 }, ex)
        if undo and undo.id == v.id then
            h = h + K.Text(self.undoText, ("Removed %s."):format(undo.label), "quiet", PAD, h + 6, self) + 6
            K.Put(self.undo, self, W - PAD - 70, h - (self.undoText:GetStringHeight() or 12) - 8)
            h = h + 6
        end
        -- the shield template's own explanation, while its one condition is what the template made
        local c1 = #v.conditions == 1 and v.conditions[1].cond
        if c1 and c1.type == "equipment" and c1.slot == "offHand" and c1.what == "shield" and c1.negate then
            h = h + K.Text(self.note, RM().SHIELD_NOTE, nil, PAD, h + 4, self) + 8
        end
        for _, p in ipairs(v.problems) do
            if p == RM().PROBLEM.tooMany or p == RM().PROBLEM.tooManyGroups then
                h = h + K.Text(self.limit, p .. " The rest are kept exactly as saved, and are not shown here.", "warn", PAD, h + 4, self) + 8
                break
            end
        end
        K.Put(self.divs[2], self, PAD, h)
        self.divs[2]:SetSize(inner, 1)
        h = h + 12

        -- why
        K.Put(self.whyHead, self, PAD, h)
        h = h + 22
        local lines = Pl().SummaryLines(v)
        for i, line in ipairs(lines) do
            local fs = self.lines[i]
            if not fs then break end
            fs:SetWidth(inner - 12 * line.depth)
            h = h + K.Text(fs, (line.bullet and "-  " or "") .. line.text, line.depth == 0 and (#v.conditions == 0 and "warn" or nil) or nil, PAD + 12 * line.depth, h, self) + 3
        end
        h = h + 8
        self.explain.text:SetText("Would this show now?")
        for _, t in ipairs(self.explain.down) do t:SetShown(not explainOpen) end
        for _, t in ipairs(self.explain.up) do t:SetShown(explainOpen) end
        K.Put(self.explain, self, PAD - 4, h)
        h = h + 28
        if explainOpen and ex then
            local tone = ex.state == "show" and "met" or (ex.state == "match" and "met" or (ex.state == "hidden" and "unmet" or (ex.state == "unknown" and "unknown" or "invalid")))
            self.exMark:Set(tone)
            K.Put(self.exMark, self, PAD, h + 1)
            K.Text(self.exHead, ex.head, nil, PAD + 24, h, self)
            Color(self.exHead, tone)
            h = h + 22
            if ex.reason then h = h + K.Text(self.exReason, ex.reason, "quiet", PAD + 22, h, self) + 4 end
            h = h + K.Text(self.exScope, ex.scope, "quiet", PAD + 22, h, self) + 4
            h = h + K.Text(self.exStatus, ex.status, "quiet", PAD + 22, h, self) + 4
            h = h + K.Text(self.exNote, "Conditions matching is not the same as the reminder being on screen: it also needs to be turned on and for this character. To see how it looks, use Preview appearance below; a preview doesn't mean the conditions match.", "quiet", PAD + 22, h, self) + 6
        end
        h = h + 10
        self:SetHeight(h)
        K.Put(self, parent, 0, y)
        return h
    end
    function s:Layout(v, y)
        local Perf = R.Perf
        if Perf and Perf.Call then return Perf.Call("reminders.designer.layout", Layout, self, v, y) end
        return Layout(self, v, y)
    end
    s.Reset = Dz.Reset
    return s
end
