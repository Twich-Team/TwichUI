-- TwichUI settings: Reminders, the "When" designer
-- A draft over the existing Reminders rule tree and targeting. Flat All rules use a trigger and restrictions.
-- Advanced logic exposes other tree structures. Config.lua validates edits and commits the whole draft on Save.
-- Cards and groups follow their draft nodes through reorders, and the page pools frames for the bounded rule tree.
-- The bottom visibility line reflects the running reminder, while cards and situation testing observe the draft.

local R = TwichUI
local Dz = {}
R.RemindersDesigner = Dz

local function Wg() return R.SettingsWidgets end
local function RM() return R.Reminders end
local function Pl() return R.RemindersPlain end
local function Kit() return R.RemindersEditor.Kit end

local W, PAD, PALETTE_W = 640, 16, 228
local PALETTE_PAD = 10
local companion
local function Button(parent, label, width, kind, action)
    local b = Wg().Button(parent, label, width, kind, action)
    if R.SettingsMaterial then R.SettingsMaterial.ReminderControl(b, kind) end
    return b
end
local function Dropdown(...)
    local b = Wg().Dropdown(...)
    if R.SettingsMaterial then R.SettingsMaterial.ReminderControl(b, "dropdown") end
    return b
end
local RAIL, INSET = 3, 11       -- a group's left rail, and how far what is in it moves in from its edge
local HEAD_H = 30
local GAP, SEP_H = 6, 14
local ICON = 20
local MORE_W = 84

-- What is open. The reminder it belongs to (ui.id) decides whether it still applies.
local ui = {}
local folded = setmetatable({}, { __mode = "k" })   -- stored group table -> true (kept for the session)
local session
local explainOpen = false
local stats = { cards = 0, groups = 0, pickerRows = 0 }

local function Reset(id)
    ui = { id = id }
    session = nil
    if not id then explainOpen = false end
    if Dz.CancelDrag then Dz.CancelDrag() end
end

function Dz.Reset()
    Reset(nil)
    if companion then companion:Hide() end
end
function Dz.Shown() return companion ~= nil and companion:IsShown() end
function Dz.Frame() return companion end
function Dz.Say(text, tone)
    if not Dz.Shown() then return end
    companion.message:SetText(text or "")
    Kit().Tone(companion.message, tone)
end
function Dz.Close()
    Reset(nil)
    if companion then companion:Hide() end
    if R.RemindersPage then R.RemindersPage.QueueRefresh() end
end
function Dz.Open()
    if not companion then return end
    if R.RemindersCatalog then R.RemindersCatalog.Hide() end
    if R.RemindersPreview then R.RemindersPreview.Hide() end
    companion.workspace:Show()
    companion:Show()
    Dz.Say(nil)
    if R.RemindersPage then R.RemindersPage.QueueRefresh() end
end
function Dz.State() return ui, nil, explainOpen end
function Dz.DraftView() return RM().RuleEditView(session) end

function Dz.HasUnsaved() return RM().RuleEditState(session) or ui.draft ~= nil end

function Dz.RequestClose(after)
    local function Close()
        Dz.Close()
        if type(after) == "function" then after() end
    end
    if not Dz.HasUnsaved() then Close(); return end
    local current = session
    R.Interact.Confirm("TWICHUI_DISCARD_REMINDER_RULE", "Discard unsaved changes to this reminder's conditions?",
        function() if session == current then Close() end end, { accept = "Discard" })
end

-- For TwichUI Diagnostics and the tests: what has been built (pools only grow to the sizes a reminder is limited to) and what
-- is open. Counts only: it reads, builds and changes nothing, and names nothing.
function Dz.Snapshot()
    local _, undo = RM().RuleEditState(session)
    return { cards = stats.cards, groups = stats.groups, pickerRows = stats.pickerRows,
        open = ui.mode and 1 or 0, explain = explainOpen and 1 or 0, undo = undo and 1 or 0 }
end

---------------------------------------------------------------------------
-- Small pieces
---------------------------------------------------------------------------
-- Evaluation colors accompany read-only state text.
local function StateColor(state)
    local pal = Wg().pal
    if state == "met" then return pal.sage
    elseif state == "unmet" then return pal.danger.text
    elseif state == "invalid" then return pal.bronzeText end
    return pal.stone
end
local function Color(fs, tone)
    local G = Wg()
    if tone == "met" or tone == "unmet" or tone == "unknown" or tone == "invalid" then G.Color(fs, StateColor(tone)) else Kit().Tone(fs, tone) end
end

-- A tooltip that leaves the control's own hover scripts alone (a tab repaints itself on enter and leave).
local function TipHook(frame, title, text)
    R.SettingsMaterial.ContextTip(frame, title, text)
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
    local M = R.SettingsMaterial
    local function View() return Dz.DraftView() end
    local function Revision() return RM().RuleEditRevision(session) end
    local s = CreateFrame("Frame", nil, parent)
    local summary = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    M.PanelFace(summary, "espresso")
    summary.title = M.ReminderFont(G.Text(summary, "heading"), 17, true, "serif")
    summary.title:SetPoint("TOPLEFT", PAD, -12); summary.title:SetText("When")
    summary.rule = G.Text(summary, "body")
    summary.rule:SetPoint("TOPLEFT", PAD, -36)
    summary.restriction = G.Text(summary, "small")
    summary.status = G.Text(summary, "small")
    summary.edit = Button(summary, "Edit conditions", 140, "secondary", Dz.Open)
    s.summary = summary

    companion = R.RemindersBuilderRail.Build(W + PALETTE_W + 64, 800, function(id)
        local page = R.RemindersPage
        if page.Selected() == id then return end
        if Dz.HasUnsaved() then
            Dz.RequestClose(function() page.Select(id); Dz.Open() end)
        else
            page.Select(id)
        end
    end, function()
        if s.picker.search:IsShown() then s.picker.search:SetFocus() end
    end)
    companion:Hide()
    companion:SetScript("OnShow", function()
        R.RemindersPreview.RestoreAnchor()
        R.SettingsUI.SetWorkspaceVisible(true)
    end)
    M.HeaderBand(companion, 96)
    companion.title = G.Text(companion, "title")
    companion.title:SetPoint("TOPLEFT", 23, -18); companion.title:SetWidth(W + PALETTE_W - 45)
    companion.title:SetMaxLines(1)
    M.ReminderFont(companion.title, 26, true)
    companion.subtitle = M.ReminderFont(G.Text(companion, "body"), 14)
    companion.subtitle:SetPoint("TOPLEFT", 23, -53)
    companion.subtitle:SetText("Choose when this reminder appears.")
    companion.close = R.FrameLook.Close(companion, Dz.RequestClose)
    companion.close:SetSize(27, 27)
    M.ReminderControl(companion.close, "action")
    companion.close:SetPoint("TOPRIGHT", -17, -16)
    local function Disclosure(parent, label, width, click)
        local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
        button:SetSize(width, 26)
        G.Hover(button, pal.bronzeText, 0.12)
        button.mark = M.ReminderFont(G.Text(button, "heading"), 19)
        button.mark:SetPoint("LEFT", 6, 0)
        button.text = M.ReminderFont(G.Text(button, "body"), 14)
        button.text:SetPoint("LEFT", 23, 0)
        button.text:SetText(label)
        button.down = G.Chevron(button, button, "LEFT", 10, 0, true, pal.bronzeText)
        button:SetScript("OnClick", click)
        function button:Paint(open)
            self.mark:SetText(open and "" or "›")
            for _, piece in ipairs(self.down) do piece:SetShown(open and true or false) end
            G.Color(self.mark, pal.bronzeText)
            G.Color(self.text, self:IsEnabled() and pal.textDim or pal.stone)
        end
        button:Paint(false)
        return button
    end

    local function Band(parent)
        local line = G.Solid(parent, "ARTWORK", { 0.53, 0.41, 0.26 }, 0.63)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT")
        line:SetPoint("TOPRIGHT")
    end
    local footer = CreateFrame("Frame", nil, companion)
    footer:SetPoint("BOTTOMLEFT", 10, 11)
    footer:SetPoint("BOTTOMRIGHT", -10, 11)
    footer:SetHeight(56)
    M.QuietTile(footer, "header")
    Band(footer)
    local function Action(label, width, kind, callback)
        local button = Button(footer, label, width, kind, callback)
        button:SetHeight(38)
        M.ReminderFont(button.text, 14)
        return button
    end
    companion.cancel = Action("Cancel", 108, "action", Dz.Close)
    companion.save = Action("Save", 116, "confirmation", function() Dz.Save() end)
    companion.save:SetPoint("RIGHT", -13, 0)
    companion.cancel:SetPoint("RIGHT", companion.save, "LEFT", -10, 0)
    companion.dirty = M.ReminderFont(G.Text(footer, "small"), 13)
    companion.dirty:SetPoint("CENTER")
    M.ContextTip(companion.cancel, "Cancel", "Discards the unsaved conditions and targeting changes.")
    M.ContextTip(companion.save, "Save", "Applies conditions and targeting together.")

    local feedback = CreateFrame("Frame", nil, companion)
    feedback:SetHeight(116)
    M.PanelFace(feedback, "espresso")
    Band(feedback)
    companion.message = M.ReminderFont(G.Text(feedback, "small"), 13)
    companion.message:SetPoint("TOPLEFT", 165, -84)
    companion.message:SetWidth(W + PALETTE_W - 144)
    companion.message:SetMaxLines(2)
    companion.result = M.ReminderFont(G.Text(feedback, "body"), 15, true)
    companion.result:SetPoint("TOPLEFT", 45, -11)
    companion.result:SetWidth(W + PALETTE_W - 1)
    companion.result:SetMaxLines(2)
    local summaryEye = feedback:CreateTexture(nil, "ARTWORK")
    summaryEye:SetSize(22, 22)
    summaryEye:SetPoint("TOPLEFT", 16, -10)
    summaryEye:SetTexture(R.PATH .. [[media\guildloc\eye-open-small.tga]])
    companion.eye = feedback:CreateTexture(nil, "ARTWORK")
    companion.eye:SetSize(22, 22)
    companion.eye:SetPoint("TOPLEFT", 16, -44)
    companion.live = M.ReminderFont(G.Text(feedback, "heading"), 15, true)
    companion.live:SetPoint("TOPLEFT", 45, -47)
    companion.live:SetWidth(124)
    companion.reason = M.ReminderFont(G.Text(feedback, "body"), 14)
    companion.reason:SetPoint("TOPLEFT", 178, -48)
    companion.reason:SetWidth(350)
    companion.reason:SetMaxLines(2)
    companion.try = Disclosure(feedback, "Try a situation", 146, function()
        ui.try = not ui.try
        explainOpen = false
        companion.diagnosticsScroll:SetVerticalScroll(0)
        env.Changed()
    end)
    companion.try:SetPoint("TOPLEFT", 12, -76)

    local function Pane(x, right)
        local pane = CreateFrame("Frame", nil, companion)
        pane:SetPoint("TOPLEFT", x, -96)
        M.PanelFace(pane, "editor")
        return pane, right
    end
    local palettePane, paletteRight = Pane(14, PALETTE_W + 21)
    local rulePane, ruleRight = Pane(PALETTE_W + 28, W + PALETTE_W + 50)
    companion.paletteScroll, companion.paletteContent = G.Scroll(companion, PALETTE_W)
    companion.paletteScroll:SetPoint("TOPLEFT", 16, -97)
    local paletteHelp = G.Text(companion, "small")
    paletteHelp:SetText("Click or drag into the rule")
    G.Color(paletteHelp, pal.stone)
    companion.scroll, companion.content = G.Scroll(companion, W)
    companion.scroll:SetPoint("TOPLEFT", PALETTE_W + 30, -97)
    local diagnostics = CreateFrame("Frame", nil, companion)
    diagnostics:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 0)
    diagnostics:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)
    diagnostics:SetHeight(150)
    M.PanelFace(diagnostics, "espresso")
    companion.diagnostics = diagnostics
    local diagWidth = W + PALETTE_W + 4
    local diagnosticScroll, diagnosticContent = G.Scroll(diagnostics, diagWidth)
    diagnosticScroll:SetPoint("TOPLEFT", 11, -8)
    diagnosticScroll:SetPoint("BOTTOMRIGHT", -23, 8)
    companion.diagnosticsScroll = diagnosticScroll
    local fitDiagnosticRail = M.ScrollRail(diagnosticScroll)
    local baseline = CreateFrame("Frame", nil, companion)
    baseline:SetSize(1, 1)
    palettePane:SetPoint("BOTTOMRIGHT", baseline, "BOTTOMLEFT", paletteRight, 0)
    rulePane:SetPoint("BOTTOMRIGHT", baseline, "BOTTOMLEFT", ruleRight, 0)
    companion.paletteScroll:SetPoint("BOTTOMRIGHT", baseline, "BOTTOMLEFT", PALETTE_W + 12, 30)
    companion.scroll:SetPoint("BOTTOMRIGHT", baseline, "BOTTOMLEFT", W + PALETTE_W + 31, 32)
    paletteHelp:SetPoint("BOTTOMLEFT", baseline, "BOTTOMLEFT", 28, 11)
    local revealHeight = 0
    local function PlaceFeedback(extra)
        if extra ~= nil then revealHeight = extra end
        extra = revealHeight
        diagnostics:SetShown(extra > 0)
        diagnostics:SetHeight(math.max(1, extra))
        feedback:ClearAllPoints()
        feedback:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, extra)
        feedback:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, extra)
        baseline:ClearAllPoints()
        baseline:SetPoint("BOTTOMLEFT", companion, "BOTTOMLEFT", 0, 75 + feedback:GetHeight() + extra)
    end
    local fitPaletteRail = M.ScrollRail(companion.paletteScroll)
    local fitRuleRail = M.ScrollRail(companion.scroll)
    s:SetParent(companion.content)
    companion:SetScript("OnHide", function()
        companion.workspace:Hide()
        R.SettingsUI.SetWorkspaceVisible(false)
        G.CloseMenu()
        Reset(nil)
        if R.RemindersPage then R.RemindersPage.QueueRefresh() end
    end)
    local parts, drag, pickInline = {}, nil, nil
    local function Add(el) parts[#parts + 1] = el return el end

    local function Did(ok, why)
        if not ok then Dz.Say(why, "warn") end
        return ok
    end
    local function Poke() env.Changed() end
    local function Mutate(action, ...)
        local ok, why = RM().ChangeRuleEdit(session, action, ...)
        if not Did(ok, why) then Poke(); return false end
        Dz.Say(nil)
        Poke()
        return true, why
    end
    function Dz.Save()
        if ui.draft then Dz.Say("Finish or cancel the condition first.", "warn"); return false end
        if not Did(RM().SaveRuleEdit(session)) then return false end
        Dz.Close()
        return true
    end
    function Dz.SetAdvanced(on)
        ui.advanced = on and true or nil
        companion.scroll:SetVerticalScroll(0)
        Poke()
    end
    s.advanced = Disclosure(companion, "Advanced logic", 168, function()
        local v = View()
        if v and Pl().Basic(v) and not ui.draft then Dz.SetAdvanced(not ui.advanced) end
    end)
    s.advanced:SetPoint("BOTTOMLEFT", baseline, "BOTTOMLEFT", PALETTE_W + 44, 5)
    M.ContextTip(s.advanced, "Advanced logic", "Edit All/Any groups and nested conditions.")

    ---------------------------------------------------------------- the three block headings
    s.ruleHead = Add(G.Text(s, "title"))
    s.ruleHead:SetText("Show a reminder when")
    R.SettingsMaterial.ReminderFont(s.ruleHead, 18, true)
    s.ruleHead:SetWidth(300)
    s.onlyHead = Add(M.ReminderFont(G.Text(s, "title"), 18, true))
    s.onlyHead:SetWidth(270)
    s.onlyHead:SetText("Only while")

    ---------------------------------------------------------------- who
    s.who = Add(G.Text(s, "body"))
    s.who:SetWidth(W - PAD * 2 - 90)
    s.who:SetWordWrap(true)
    local function SetWho(value)
        if ui.draft then return end
        if value == "manage" then
            if ui.mode == "target" then ui.mode = nil else ui.mode = "target" end
            companion.scroll:SetVerticalScroll(0)
            Poke()
            return
        end
        if value ~= "all" and value ~= "me" and value ~= "chosen" then return end
        local me = RM().CharacterKey()
        local function Apply(handle)
            if value == "all" then return RM().SetScope(handle, "who", "all") end
            local view = View()
            if value == "me" then
                if not me then return false, "Your character is not available yet." end
                for _, c in ipairs(view.scope.characters) do
                    if c ~= me then
                        local ok, why = RM().RemoveCharacter(handle, c)
                        if not ok then return false, why end
                    end
                end
            end
            if value == "me" or #view.scope.characters == 0 then
                local ok, why = RM().AddCharacter(handle, me)
                if not ok then return false, why end
            end
            return RM().SetScope(handle, "who", "characters")
        end
        if Mutate(Apply) and value == "chosen" then ui.mode = "target" end
    end
    s.whoLabel = M.ReminderFont(G.Text(companion, "body"), 14, true)
    s.whoLabel:SetPoint("TOPRIGHT", -260, -52)
    s.whoLabel:SetWidth(24)
    s.whoLabel:SetText("For")
    s.whoEdit = Dropdown(companion, 226, SetWho)
    s.whoEdit:SetHeight(32)
    M.ReminderFont(s.whoEdit.text, 14, true)
    M.Edge(s.whoEdit, "control", 8):SetBackdropBorderColor(0.57, 0.47, 0.33, 0.8)
    s.whoEdit:SetPoint("TOPRIGHT", -21, -44)
    s.whoEdit:SetChoices(function()
        return { { value = "all", label = "Every character" }, { value = "me", label = "This character" },
            { value = "chosen", label = "Chosen characters" }, { value = "manage", label = "Targeting options..." } }
    end)
    M.ContextTip(s.whoEdit, "Who can see this reminder?", function() return s.who:GetText() end)

    local tp = CreateFrame("Frame", nil, s, "BackdropTemplate")
    tp:SetWidth(W - PAD * 2)
    M.PanelFace(tp, "card")
    Add(tp)
    s.target = tp
    tp.names = G.Text(tp, "small")
    tp.names:SetWidth(W - PAD * 4)
    tp.addMe = Button(tp, "Add this character", 150, "secondary", function() Mutate(RM().AddCharacter, RM().CharacterKey()) end)
    tp.removeMe = Button(tp, "Remove this character", 170, "secondary", function() Mutate(RM().RemoveCharacter, RM().CharacterKey()) end)
    tp.classLabel = G.Text(tp, "body")
    tp.classLabel:SetText("Only for class")
    tp.class = Dropdown(tp, 200, function(v) Mutate(RM().SetScope, "class", v ~= "" and v or nil) end)
    tp.class:SetChoices(function()
        local out = { { value = "", label = "Any class" } }
        for _, c in ipairs(RM().CLASSES) do out[#out + 1] = { value = c, label = RM().ClassName(c) } end
        return out
    end)
    M.ContextTip(tp.class, "Only for class", "Limits which characters this reminder runs for, whatever its conditions: a reminder for another class never looks at anything. To show for several classes, or for a class only in some situations, add \"Your class\" conditions to the rule instead.")
    tp.note = G.Text(tp, "small")
    tp.note:SetWidth(W - PAD * 4)
    tp.note:SetText("Sets who can see this reminder. Class conditions stay in the rule.")
    tp.done = Button(tp, "Done", 90, "primary", function() ui.mode = nil; Poke() end)

    local function Payload(raw, entry, label)
        if not Dz.Shown() or ui.draft or not RM().Writable() or not (raw or entry) then return end
        local node = raw and RM().NodeByRaw(View(), raw)
        return { id = env.id(), rev = Revision(), raw = raw, entry = entry,
            condition = entry and entry.make() or (node and (node.cond
                or (Pl().LocationValues(node) and { type = "player", state = "dungeon" }))) }, label
    end

    local function Grip(parent, raw, label)
        local grip = CreateFrame("Button", nil, parent)
        grip:SetSize(20, 24)
        for i = 1, 6 do
            local dot = G.Solid(grip, "ARTWORK", pal.bronzeText, 0.8)
            dot:SetTexture(R.PATH .. [[media\style-v2\switch-thumb.tga]])
            dot:SetVertexColor(0.64, 0.52, 0.34, 0.85)
            dot:SetSize(3, 3)
            dot:SetPoint("CENTER", i % 2 == 0 and 2 or -2, 5 - 5 * math.floor((i - 1) / 2))
        end
        G.Hover(grip, pal.text, 0.12)
        M.ContextTip(grip, "Move condition or group", "Drag to a highlighted edge or into a group. You can also move it through Actions.")
        grip:RegisterForDrag("LeftButton")
        grip:SetScript("OnDragStart", function()
            local payload, name = Payload(raw(), nil, label())
            drag:Start(payload, name)
        end)
        grip:SetScript("OnDragStop", function() drag:Stop() end)
        return grip
    end

    function Dz.LocationPick(raw, state, remove)
        local function Apply(handle)
            local view = RM().RuleEditView(handle)
            local entry = RM().NodeByRaw(view, raw)
            local values = Pl().LocationValues(entry)
            if not values or (state ~= "dungeon" and state ~= "raid") then return false, RM().REFUSE.value end
            local exists
            for _, value in ipairs(values) do if value == state then exists = true end end
            if remove then
                if not exists then return false, RM().REFUSE.value end
                if not entry.group or #entry.children == 1 then return RM().RemoveNode(handle, entry.path) end
                for _, child in ipairs(entry.children) do
                    if child.cond.state == state then return RM().RemoveNode(handle, child.path) end
                end
            else
                if exists or (entry.cond and entry.cond.negate) then return false, RM().REFUSE.value end
                local cond = { type = "player", state = state, negate = false }
                if entry.group then return RM().AddCondition(handle, "player", entry.path, cond) end
                local at = entry.path[1]
                local ok, groupPath = RM().AddGroup(handle, nil, "any")
                if not ok then return false, groupPath end
                local groupRaw = RM().Node(RM().RuleEditView(handle), groupPath).raw
                local why
                ok, why = RM().MoveNode(handle, entry.path, groupPath)
                if not ok then return false, why end
                local group = RM().NodeByRaw(RM().RuleEditView(handle), groupRaw)
                ok, why = RM().AddCondition(handle, "player", group.path, cond)
                if not ok then return false, why end
                return RM().MoveNode(handle, group.path, {}, at)
            end
        end
        return Mutate(Apply)
    end

    ---------------------------------------------------------------- the tree: group boxes, then cards
    local function MakeGroup(top)
        local g = {}
        g.box = CreateFrame("Frame", nil, s)
        M.PanelFace(g.box, top and "espresso" or "well")
        Add(g.box)
        g.rail = G.Solid(g.box, "ARTWORK", pal.bronzeText, 0.6)
        g.rail:SetWidth(RAIL)
        g.rail:SetPoint("TOPLEFT", 1, -1)
        g.rail:SetPoint("BOTTOMLEFT", 1, 1)
        g.heading = Add(G.Text(g.box, "body"))
        g.heading:SetWordWrap(false)
        g.folded = Add(G.Text(g.box, "small"))
        g.folded:SetWordWrap(false)
        g.problem = Add(G.Text(g.box, "small"))
        g.problem:SetWordWrap(true)
        g.empty = Add(G.Text(g.box, "small"))
        g.empty:SetWordWrap(true)
        g.top = top
        if not top then
            g.grip = Add(Grip(g.box, function() return g.raw end, function() return g.heading:GetText() end))
            g.fold = Add(CreateFrame("Button", nil, g.box))
            g.fold:SetSize(20, 20)
            g.fold.down = G.Chevron(g.fold, g.fold, "CENTER", 0, 0, true, pal.tealHi)
            g.fold.up = G.Chevron(g.fold, g.fold, "CENTER", 0, 0, false, pal.tealHi)
            G.Hover(g.fold, pal.text, 0.06)
            g.fold:SetScript("OnClick", function()
                if not g.raw or ui.draft then return end
                folded[g.raw] = (not folded[g.raw]) or nil
                ui.mode, ui.nodeRaw, ui.groupRaw, ui.draft = nil, nil, nil, nil   -- what was open inside it is put away
                Poke()
            end)
            M.ContextTip(g.fold, "Fold this group", "Folds the group to one line, or opens it again. Nothing in it changes.")
            g.more = Add(Dropdown(g.box, MORE_W, function(value) Dz.MenuPick(g, value) end))
            g.more:SetValue(nil, "More")
            g.more.menuWidth, g.more.menuAlignRight = 340, true
            g.more:SetChoices(function() return Dz.MenuFor(g.raw) end)
            M.ContextTip(g.more, "More", "Duplicate this group, move it up or down or into another group, or remove it with what is in it.")
        end
        for _, match in ipairs({ "all", "any" }) do
            local seg = Add(R.SettingsMaterial.Segment(g.box, Pl().Words(match).short, 46, function()
                local e = g.raw and RM().NodeByRaw(View(), g.raw)
                if top then Mutate(RM().SetMatch, match) elseif e then Mutate(RM().SetMatch, match, e.path) end
            end))
            TipHook(seg, Pl().Words(match).technical, Pl().Words(match).tip)
            g["seg" .. match] = seg
        end
        g.add = Add(Button(g.box, "Add a condition", 140, "secondary", function()
            if ui.draft then return end
            ui.mode, ui.groupRaw, ui.nodeRaw, ui.draft = "pick", g.raw or "top", nil, nil
            ui.query, ui.category = "", nil
            companion.paletteScroll:SetVerticalScroll(0)
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

    -- Whatever is on the cursor can be dropped on a card, the open editor or the rule panel (Dz.TakeDrop below). Both the
    -- drop of a drag and a click with the thing on the cursor count, as with the game's own slots.
    local function Accept(frame, raw)
        frame:SetScript("OnReceiveDrag", function() Dz.TakeDrop(raw and raw()) end)
        frame:HookScript("OnMouseUp", function(_, button)
            if button == "LeftButton" and GetCursorInfo and GetCursorInfo() then Dz.TakeDrop(raw and raw()) end
        end)
    end
    s:EnableMouse(true)
    Accept(s)

    s.cards = {}
    for i = 1, RM().MAX_CONDITIONS do
        local card = CreateFrame("Button", nil, s, "BackdropTemplate")
        M.PanelFace(card, "walnut")
        M.MaterialHover(card)
        Add(card)
        card.icon = card:CreateTexture(nil, "ARTWORK")
        card.icon:SetSize(ICON, ICON)
        card.icon:SetPoint("TOPLEFT", 28, -9)
        card.grip = Grip(card, function() return card.raw end, function() return card.title:IsShown() and card.title:GetText() or card.text:GetText() end)
        card.grip:SetPoint("TOPLEFT", 3, -6)
        card.text = G.Text(card, "body")
        card.title = M.ReminderFont(G.Text(card, "title"), 18, true)
        card.title:SetWidth(196)
        card.text:SetWordWrap(true)
        card.note = M.ReminderFont(G.Text(card, "heading"), 15, true, "strong")
        card.note:SetWordWrap(true)
        card.more = Dropdown(card, 28, function(value) Dz.MenuPick(card, value) end, true)
        card.more:SetValue(nil, "···")
        card.more.menuWidth, card.more.menuAlignRight = 340, true
        card.more:SetChoices(function() return Dz.MenuFor(card.raw) end)
        card.artWell = CreateFrame("Frame", nil, card)
        M.PanelFace(card.artWell, "canvas")
        card.artWell:SetSize(58, 58)
        card.artWell:SetPoint("TOPLEFT", 30, -18)
        M.Rim(card.artWell):SetTint(1, 1, 1, 0.55)
        card.art = card.artWell:CreateTexture(nil, "OVERLAY")
        card.art:SetPoint("CENTER", 0, 0)
        card.fields = {}
        card.item = Button(card, "Choose item", 119, "secondary", function() Dz.Edit(card.raw) end)
        M.ContextTip(card.item, "Choose by dragging", function()
            local entry = card.raw and RM().NodeByRaw(View(), card.raw)
            local need = entry and entry.cond and Pl().NeedsId(entry.cond)
            if need == "spell" then return "Drag a spell from your spellbook onto this card, or click to type its spell ID." end
            return "Drag an item from your bags onto this card, or click to type its item ID or paste its link."
        end)
        for j = 1, 3 do
            local field = Dropdown(card, 110, function(value) pickInline(card, j, value) end)
            field:SetChoices(function() return card.inline and card.inline[j] and card.inline[j].choices or {} end)
            card.fields[j] = field
        end
        for _, target in ipairs({ card, card.item, card.more, card.grip, card.fields[1], card.fields[2], card.fields[3] }) do
            Accept(target, function() return card.raw end)
        end
        card.chips = {}
        for j = 1, 2 do
            local chip = Button(card, "", 108, "chip", function()
                local value = card.locations and card.locations[j]
                if value then Dz.LocationPick(card.raw, value, true) end
            end)
            chip:SetHeight(28)
            M.ReminderFont(chip.text, 14, true)
            card.chips[j] = chip
        end
        card.choose = Dropdown(card, 102, function(value) Dz.LocationPick(card.raw, value) end, true)
        card.choose:SetHeight(28)
        M.ContextTip(card.choose, "Choose locations", "Dungeon and Raid are the supported location checks. Both are selected when this control is unavailable.")
        card.choose:SetChoices(function()
            local choices, have = {}, {}
            for _, value in ipairs(card.locations or {}) do have[value] = true end
            for _, place in ipairs({ { "dungeon", "Dungeon" }, { "raid", "Raid" } }) do
                if not have[place[1]] then choices[#choices + 1] = { value = place[1], label = place[2] } end
            end
            return choices
        end)
        card.locationNote = M.ReminderFont(G.Text(card, "small"), 12)
        card:RegisterForClicks("RightButtonUp")
        card:SetScript("OnClick", function(_, mouse)
            if mouse == "RightButton" and not ui.draft then
                card.more:Show()
                card.more:OpenMenu()
            end
        end)
        M.ContextTip(card, "Condition actions", function()
            local entry = card.raw and RM().NodeByRaw(View(), card.raw)
            local need = entry and entry.cond and Pl().NeedsId(entry.cond)
            return "Right-click to remove, duplicate or move.",
                need and ("Drag %s onto this card to use it."):format(need == "item" and "an item from your bags" or "a spell from your spellbook") or nil
        end)
        card:HookScript("OnEnter", function()
            if not ui.draft and RM().Writable() then card.more:Show() end
        end)
        card:HookScript("OnLeave", function()
            if not card:IsMouseOver() and not card.more:IsMouseOver() then card.more:Hide() end
        end)
        card.more:HookScript("OnLeave", function()
            if not card:IsMouseOver() then card.more:Hide() end
        end)
        M.ContextTip(card.more, "Condition actions", "Remove, duplicate or move.")
        s.cards[i] = card
    end
    stats.cards = RM().MAX_CONDITIONS
    s.addBasic = Add(G.Button(s, "+ Add restriction", W - PAD * 2, "secondary", function()
        ui.mode, ui.groupRaw = "pick", "top"
        companion.paletteScroll:SetVerticalScroll(0)
        s.picker.search:SetFocus()
        Poke()
    end))
    M.ReminderControl(s.addBasic, "target")
    s.addBasic:SetHeight(42)
    M.ReminderFont(s.addBasic.text, 14)
    M.DashedBorder(s.addBasic, W - PAD * 2, 42)

    s.limit = Add(G.Text(s, "small"))
    s.limit:SetWidth(W - PAD * 2)
    local function HistoryButton(label, reverse, callback)
        local button = Action(label, 98, "action", callback)
        button.craftLabelInset = 35
        local icon = button:CreateTexture(nil, "OVERLAY")
        icon:SetAtlas("common-icon-undo")
        if reverse then
            local ulx, uly, llx, lly, urx, ury, lrx, lry = icon:GetTexCoord()
            if lry then icon:SetTexCoord(urx, ury, lrx, lry, ulx, uly, llx, lly) end
        end
        icon:SetSize(17, 17)
        icon:SetPoint("LEFT", 12, 0)
        button.text:ClearAllPoints()
        button.text:SetWidth(0)
        button.text:SetPoint("LEFT", 35, 0)
        function button:PaintIcon()
            local c = self:IsEnabled() and pal.bronzeText or pal.stone
            icon:SetVertexColor(c[1], c[2], c[3], self:IsEnabled() and 1 or 0.55)
        end
        return button
    end
    s.undo = HistoryButton("Undo", false, function() Dz.Undo() end)
    s.undo:SetPoint("LEFT", 13, 0)
    s.redo = HistoryButton("Redo", true, function() Dz.Redo() end)
    s.redo:SetPoint("LEFT", s.undo, "RIGHT", 10, 0)
    M.ContextTip(s.undo, "Undo", "Reverses the most recent draft change.")

    ---------------------------------------------------------------- the one editor
    local ep = CreateFrame("Frame", nil, s, "BackdropTemplate")
    R.SettingsMaterial.Card(ep, G.Panel(ep))
    Add(ep)
    s.editor = ep
    ep.title = G.Text(ep, "heading")
    local function DraftField(key)
        return ui.draft and Pl().EditField(ui.draft, key)
    end
    local function DraftControl(key, width)
        local control = Dropdown(ep, width, function(value)
            local spec = DraftField(key)
            local nextCond = spec and Pl().WithCardField(ui.draft, spec, value)
            if nextCond then ui.draft = nextCond; Poke() end
        end)
        control:SetChoices(function()
            local spec = DraftField(key)
            return spec and spec.choices or {}
        end)
        return control
    end
    ep.subject = DraftControl("subject", 166)
    ep.op = DraftControl("op", 122)
    ep.value = DraftControl("value", 178)
    M.ContextTip(ep.value, "Condition value", function() return ui.draft and Pl().Help(ui.draft) end)
    ep.item = G.EditBox(ep, 110, 24)
    ep.item:SetMaxLetters(200)
    M.ReminderControl(ep.item, "field")
    -- An item (its ID, link or a drop from the bags) or a spell (its ID or link, a drop from the spellbook; a buff takes
    -- several, separated by commas): whichever the draft asks for.
    local function TakeItem(text)
        local draft = ui.draft
        local kind = draft and Pl().NeedsId(draft)
        if kind == "spell" then
            local many = draft.type == "aura" and R.ReminderAuras.MAX_SPELLS or 1
            local ids, why = Pl().ParseSpells(text, many)
            if not ids then
                Dz.Say(why == "many" and ("At most %d spell IDs: one for each rank that should count."):format(many)
                    or "That isn't a spell ID. Type the number from the spell's link, paste the link, or drop the spell from your spellbook on the box.", "warn")
                return
            end
            ep.item:ClearFocus()
            ui.draft = Pl().WithIds(draft, ids)
            Dz.Say(nil)
            Poke()
            return
        end
        local id = RM().ParseItem(text)
        if not id then Dz.Say("That isn't an item ID. Type the number from the item's link, paste the link, or drop the item on the box.", "warn") return end
        ep.item:ClearFocus()
        if ui.draft then ui.draft = Pl().WithItem(ui.draft, id) end
        Poke()
    end
    ep.item:SetScript("OnEnterPressed", function(self) TakeItem(self:GetText()) end)
    -- (a drop on the box, the editor around it or anywhere in the rule panel goes through Dz.TakeDrop: the item goes
    -- straight back where it came from and only its ID is noted)
    ep:EnableMouse(true)
    Accept(ep)
    Accept(ep.item)
    M.ContextTip(ep.item, "Item or spell", function()
        if ui.draft and Pl().NeedsId(ui.draft) == "spell" then
            return ui.draft.type == "aura" and "Its spell ID or link, or several separated by commas (each rank of a spell has an ID of its own). Press Enter."
                or "Its spell ID or link, or the spell dropped here from your spellbook. Press Enter."
        end
        return "Its item ID, its link pasted here, or the item dropped here from your bags (it goes straight back). Press Enter."
    end)
    -- a number for the condition's amount field (any whole number in its range; the card offers quick choices)
    ep.amount = G.EditBox(ep, 70, 24)
    ep.amount:SetMaxLetters(6)
    M.ReminderControl(ep.amount, "field")
    ep.amount:SetNumeric(true)
    ep.amountWords = G.Text(ep, "small")
    local function TakeAmount(text)
        local spec = ui.draft and Pl().EditField(ui.draft, "amount")
        local n = tonumber(text)
        if not (spec and n and n % 1 == 0 and n >= spec.min and n <= spec.max) then
            Dz.Say(("Type a whole number from %d to %d."):format(spec and spec.min or 1, spec and spec.max or 1), "warn")
            return
        end
        ep.amount:ClearFocus()
        ui.draft = Pl().WithNumber(ui.draft, spec.field, n)
        Dz.Say(nil)
        Poke()
    end
    ep.amount:SetScript("OnEnterPressed", function(self) TakeAmount(self:GetText()) end)
    M.ContextTip(ep.amount, "Amount", function()
        local spec = ui.draft and Pl().EditField(ui.draft, "amount")
        return spec and ("A whole number from %d to %d. Press Enter."):format(spec.min, spec.max) or ""
    end)
    ep.itemInfo = G.Text(ep, "small")
    ep.reads = G.Text(ep, "body")
    ep.reads:SetWordWrap(true)
    ep.problem = G.Text(ep, "small")
    ep.problem:SetWordWrap(true)
    ep.done = Button(ep, "Done", 100, "primary", function() Dz.Commit() end)
    ep.cancel = Button(ep, "Cancel", 90, "secondary", function()
        ui.mode, ui.nodeRaw, ui.draft = nil, nil, nil
        Dz.Say(nil)
        Poke()
    end)
    M.ContextTip(ep.cancel, "Cancel", "Closes this without changing anything: the saved condition stays as it was.")

    ---------------------------------------------------------------- the one picker
    local pp = CreateFrame("Frame", nil, companion.paletteContent, "BackdropTemplate")
    s.picker = pp
    pp.title = M.ReminderFont(G.Text(pp, "title"), 18, true)
    pp.where = G.Text(pp, "small")
    pp.where:SetWordWrap(true)
    pp.search = G.EditBox(pp, PALETTE_W - PALETTE_PAD * 2, 30)
    M.ReminderControl(pp.search, "field")
    pp.searchHint = M.SearchDecoration(pp.search, "Search...")
    pp.search:SetMaxLetters(40)
    pp.search:SetScript("OnTextChanged", function(self, user)
        if user == false then return end
        ui.query = self:GetText()
        companion.paletteScroll:SetVerticalScroll(0)
        Poke()
    end)
    pp.search:HookScript("OnEditFocusGained", function() pp.searchHint:Hide() end)
    pp.search:HookScript("OnEditFocusLost", function() pp.searchHint:SetShown(pp.search:GetText() == "") end)
    pp.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    pp.search:HookScript("OnHide", function(self) self:ClearFocus() end)
    M.ContextTip(pp.search, "Search", "A few letters of what you want to check: combat, ammunition, shield, class...")
    pp.categories, pp.dividers = {}, {}
    pp.category = Dropdown(pp, PALETTE_W - PALETTE_PAD * 2, function(value)
        ui.category = value ~= "all" and value or nil
        companion.paletteScroll:SetVerticalScroll(0)
        Poke()
    end)
    pp.category:SetHeight(27)
    M.ReminderFont(pp.category.text, 13)
    pp.category:SetChoices(function()
        local options = { { value = "all", label = "All categories" } }
        for _, category in ipairs(Pl().CATEGORIES) do options[#options + 1] = { value = category, label = category } end
        return options
    end)
    pp.rows = {}
    pp.none = G.Text(pp, "small")
    pp.cancel = Button(pp, "Cancel", 90, "secondary", function() ui.mode, ui.groupRaw = nil, nil; Poke() end)
    pp.back = Button(pp, "Back", 90, "secondary", function() ui.mode = "pick"; Poke() end)
    pp.newAny = Button(pp, "Allow either condition", PALETTE_W - PALETTE_PAD * 2, "secondary", function() Dz.AddGroup("any") end)
    pp.newAll = Button(pp, "Require several together", PALETTE_W - PALETTE_PAD * 2, "secondary", function() Dz.AddGroup("all") end)
    pp.newNote = G.Text(pp, "small")
    pp.newNote:SetWordWrap(true)
    M.ContextTip(pp.newAny, "Allow either condition", "A new group where at least one of its conditions must be true: \"this, or that\".")
    M.ContextTip(pp.newAll, "Require several together", "A new group where all of its conditions must be true.")

    local function PickRow(i)
        if pp.rows[i] then return pp.rows[i] end
        local row = CreateFrame("Button", nil, pp, "BackdropTemplate")
        M.MaterialHover(row)
        row.icon = row:CreateTexture(nil, "OVERLAY")
        row.icon:SetSize(30, 30)
        row.icon:SetPoint("CENTER", row, "LEFT", 20, 0)
        row.name = M.ReminderFont(G.Text(row, "body"), 14, true)
        row.name:SetPoint("LEFT", 43, 0)
        row.name:SetWidth(PALETTE_W - 2 * PALETTE_PAD - 45)
        row.name:SetWordWrap(true)
        row.name:SetMaxLines(2)
        row.blurb = G.Text(row, "small")
        row.blurb:SetPoint("TOPLEFT", ICON + 20, -22)
        row.blurb:SetWordWrap(true)
        row.note = G.Text(row, "small")
        row.note:SetWordWrap(true)
        row:SetScript("OnClick", function(self)
            if self.entry then Dz.Pick(self.entry)
            elseif self.isGroup then ui.groupRaw = ui.groupRaw or "top"; ui.mode = "newgroup"; Poke() end
        end)
        M.ContextTip(row, "Condition palette", function(self)
            local e = self.entry
            if e then return e.name .. "\n" .. e.blurb, e.note end
            return "Combine conditions with All or Any."
        end)
        drag:Bind(row, function() return Payload(nil, row.entry, row.name:GetText()) end)
        pp.rows[i] = row
        stats.pickerRows = #pp.rows
        return row
    end

    ---------------------------------------------------------------- why
    s.explain = Disclosure(feedback, "Details", 88, function()
        explainOpen = not explainOpen
        ui.try = nil
        diagnosticScroll:SetVerticalScroll(0)
        Poke()
    end)
    M.ReminderControl(s.explain, "drop")
    s.explain:SetHeight(28)
    s.explain.text:SetWidth(58)
    s.explain:SetPoint("TOPLEFT", 541, -40)
    local function DiagnosticText(kind, size, width)
        local fs = Add(M.ReminderFont(G.Text(diagnosticContent, kind), size))
        fs:SetWidth(width or diagWidth - 2 * PAD)
        fs:SetWordWrap(true)
        return fs
    end
    s.exHead = DiagnosticText("heading", 15)
    s.exReason = DiagnosticText("body", 13)
    s.exScope = DiagnosticText("body", 13)
    s.exStatus = DiagnosticText("body", 13)
    local detailRows = {}
    for i = 1, RM().MAX_CONDITIONS + RM().MAX_GROUPS do
        detailRows[i] = Add(R.RemindersEditor.ResultRow(diagnosticContent))
    end
    diagnosticContent.editorWidth = diagWidth

    local samples = { rows = {} }
    samples.result = DiagnosticText("body", 14)
    for i = 1, RM().MAX_CONDITIONS do
        local row = {}
        row.label = DiagnosticText("body", 13, 330)
        row.label:SetMaxLines(2)
        row.pick = Add(Dropdown(diagnosticContent, diagWidth - 348 - 2 * PAD, function(value)
            ui.picks = ui.picks or {}
            ui.picks[i] = value
            Poke()
        end))
        row.pick:SetHeight(28)
        row.pick:SetChoices(function() return row.choices or {} end)
        samples.rows[i] = row
    end

    local function LayoutSamples(v, h)
        local E = R.ReminderEval
        for i, input in ipairs(E.SimInputs(v)) do
            local row = samples.rows[i]
            row.choices = {}
            local chosen = input.scenarios[1]
            for _, option in ipairs(input.scenarios) do
                row.choices[#row.choices + 1] = { value = option.key, label = option.label }
                if ui.picks and ui.picks[i] == option.key then chosen = option end
            end
            if chosen then
                row.pick:SetValue(chosen.key, chosen.label)
                K.Text(row.label, input.label or E.Summary(input.entry), nil, PAD, h + 4, diagnosticContent)
                K.Put(row.pick, diagnosticContent, PAD + 348, h)
                h = h + 30
            end
        end
        local out = E.Simulate(v, ui.picks)
        h = h + K.Text(samples.result, "Simulated · " .. (E.STATUS_WORDS[out.status] or out.status), "quiet", PAD, h + 5, diagnosticContent) + 16
        return R.RemindersEditor.DrawResults(diagnosticContent, detailRows, out, "Simulated", h)
    end

    local function LayoutDiagnostics(v, ex, out)
        if not (ui.try or explainOpen) then return 0 end
        local h = 5
        if ui.try then
            h = LayoutSamples(v, h)
        else
            local tone = ex.state == "hidden" and "unmet" or (ex.state == "invalid" and "invalid"
                or (ex.state == "unknown" and "unknown" or "met"))
            h = h + K.Text(s.exHead, ex.head, nil, PAD, h, diagnosticContent) + 8
            Color(s.exHead, tone)
            if ex.reason then h = h + K.Text(s.exReason, ex.reason, "quiet", PAD, h, diagnosticContent) + 5 end
            h = h + K.Text(s.exScope, ex.scope, "quiet", PAD, h, diagnosticContent) + 5
            h = h + K.Text(s.exStatus, ex.status, "quiet", PAD, h, diagnosticContent) + 9
            h = R.RemindersEditor.DrawResults(diagnosticContent, detailRows, out, "Observed", h)
        end
        diagnosticContent:SetHeight(h + 6)
        if fitDiagnosticRail then fitDiagnosticRail(h + 6) end
        return math.min(150, h + 22)
    end

    ---------------------------------------------------------------- everything that is placed is hidden first
    local function HideAll()
        for _, el in ipairs(parts) do el:Hide() end
        for _, row in ipairs(pp.rows) do row:Hide() end
        for _, c in pairs(pp.categories) do c:Hide() end
        for _, c in pairs(pp.dividers) do c:Hide() end
        for _, c in ipairs(s.cards) do
            for _, k in ipairs({ "text", "title", "note", "more", "icon", "artWell", "item" }) do c[k]:Hide() end
            for _, field in ipairs(c.fields) do field:Hide() end
            for _, chip in ipairs(c.chips) do chip:Hide() end
            c.choose:Hide(); c.locationNote:Hide()
            c.inline, c.locations = nil, nil
        end
        for _, el in ipairs({ tp.names, tp.addMe, tp.removeMe, tp.classLabel, tp.class, tp.note, tp.done }) do el:Hide() end
        for _, el in ipairs({ ep.title, ep.subject, ep.op, ep.value, ep.item, ep.itemInfo, ep.amount, ep.amountWords, ep.reads, ep.problem, ep.done, ep.cancel }) do el:Hide() end
        for _, el in ipairs({ pp.none, pp.cancel, pp.back, pp.newAny, pp.newAll, pp.newNote }) do el:Hide() end
    end

    ---------------------------------------------------------------- actions (the cards' and groups' menus)
    local menuDests   -- the groups the last Move into list offered, by its position
    local function Entry(raw) return raw and RM().NodeByRaw(View(), raw) end

    pickInline = function(card, index, value)
        local entry = Entry(card.raw)
        local field = card.inline and card.inline[index]
        if not (entry and entry.cond and field) or value == field.value or ui.draft then return end
        local Pln = Pl()
        if field.kind == "number" and value == Pln.OTHER then Dz.Edit(card.raw) return end
        local nextCond = Pln.WithCardField(entry.cond, field, value)
        if not nextCond then return end
        if Pln.NeedsId(nextCond) and not Pln.HasId(nextCond) then
            Dz.Edit(card.raw)
            ui.draft = nextCond
            return
        end
        local clean, problem = R.ReminderConditions.Check(nextCond)
        if not clean or (problem and not Pln.Capability({ cond = clean })) then
            Dz.Say(problem or RM().REFUSE.value, "warn")
        else
            Mutate(RM().SetCondition, entry.path, clean, true)
        end
    end

    function Dz.Edit(raw)
        local e = Entry(raw)
        if not e then return end
        if not e.cond then
            Dz.Say(e.provider and "That condition's settings can't be read, so it can't be edited: remove it and add it again." or
                "That kind of condition isn't known to this version of TwichUI, so it is kept as it is. Remove it if you don't want it.", "warn")
            return
        end
        ui.mode, ui.nodeRaw, ui.groupRaw = "edit", raw, nil
        ui.draft = RM().DeepCopy(e.cond)
        Dz.Say(nil)
        Poke()
    end

    -- A spell or item dropped on a card (raw), or on the open editor or the rule panel (nil). With an editor open the
    -- drop goes into it; otherwise onto the card's own condition, saved to the draft through the same checked path as
    -- Done. A refusal says why and leaves what is held on the cursor. Returns false when nothing is held.
    function Dz.TakeDrop(raw)
        if not GetCursorInfo then return false end
        local what, a, b, c = GetCursorInfo()
        if what == nil then return false end
        local target
        if ui.draft then
            target = ui.draft
        else
            local entry = raw and Entry(raw)
            if not (entry and entry.cond) then
                Dz.Say("Drop it on a condition that asks for an item or a spell.", "quiet")
                return true
            end
            target = entry.cond
        end
        local new, text = Pl().Drop(target, what, a, b, c)
        if not new then Dz.Say(text, "warn") return true end
        if ClearCursor then ClearCursor() end
        if ui.draft then
            ui.draft = new
            Dz.Say(text, "ok")
            Poke()
            return true
        end
        ui.mode, ui.nodeRaw, ui.groupRaw, ui.draft = "edit", raw, nil, new
        Dz.Commit()
        if ui.draft == new then   -- refused: no editor is left open that wasn't asked for (Commit said why)
            ui.mode, ui.nodeRaw, ui.draft = nil, nil, nil
            Poke()
        else
            Dz.Say(text, "ok")
        end
        return true
    end

    local function GroupPath(v, raw)
        if raw == "top" then return {} end
        local entry = RM().NodeByRaw(v, raw)
        return entry and entry.group and entry.path or nil
    end

    local function RememberMove(raw, destination, position)
        local v, entry = View(), Entry(raw)
        local path = v and GroupPath(v, destination)
        if not (entry and path) then return false end
        return Mutate(RM().MoveNode, entry.path, path, position)
    end

    local function DropPosition(src, destination, slot)
        if not Dz.Shown() or env.id() ~= src.id or Revision() ~= src.rev or ui.draft then return end
        local v = View()
        local path = v and GroupPath(v, destination)
        if not path then return end
        if src.entry then
            if v.counts.conditions < RM().MAX_CONDITIONS then return slot end
            return
        end
        local entry = Entry(src.raw)
        if not entry then return end
        local parent, _, index = ParentOf(v, entry)
        if (parent and parent.raw or "top") == destination then
            if index < slot then slot = slot - 1 end
            if index == slot then return end
        end
        if RM().CanMoveNode(session, entry.path, path, slot) then return slot end
    end

    drag = R.RemindersRuleDrag.New(companion.scroll, DropPosition, function(src, destination, slot)
        local position = DropPosition(src, destination, slot)
        if not position then return end
        if src.entry then Dz.Pick(src.entry, destination, position)
        elseif RememberMove(src.raw, destination, position) then Dz.Say(nil) end
    end)
    companion.ruleDrag = drag
    function Dz.CancelDrag()
        local active = drag.source ~= nil
        drag:Cancel()
        return active
    end

    local function DestLabel(g, v)
        if not g then return "the whole rule: " .. Pl().Words(v.match).heading end
        return ("%s of: %s"):format(Pl().Words(g.match).short, Truncate(Pl().GroupLine(g), 38))
    end

    function Dz.MenuFor(raw)
        local v = View()
        local e = Entry(raw)
        if not (v and e) then return {} end
        local owner, list, index = ParentOf(v, e)
        local out, dests = {}, {}
        if not e.group and e.cond and s.isAdvanced then out[#out + 1] = { value = "edit", label = "Edit condition" } end
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
            local label = g and Pl().LocationValues(g) and "Move into Location"
                or "Move into: " .. Truncate(DestLabel(g, v), 24)
            out[#out + 1] = { value = key, label = label, tooltip = g and Pl().GroupLine(g) or Pl().Words(v.match).heading }
        end
        if owner then Reach(nil, {}) end
        for _, g in ipairs(v.groups) do Reach(g, g.path) end   -- an empty group included: it is where a condition is wanted
        out[#out + 1] = { value = "remove", label = e.group and "Remove group and what is in it" or "Remove" }
        menuDests = dests
        return out
    end

    local function Remove(e)
        if not Mutate(RM().RemoveNode, e.path) then return end
        if ui.nodeRaw == e.raw then ui.mode, ui.nodeRaw, ui.draft = nil, nil, nil end
        if ui.groupRaw == e.raw then ui.mode, ui.groupRaw = nil, nil end
    end

    -- the number of conditions in a group, those in groups inside it included
    local function CountIn(entry)
        local n = 0
        for _, child in ipairs(entry.children or {}) do n = n + (child.group and CountIn(child) or 1) end
        return n
    end

    function Dz.MenuPick(owner, value)
        local v = View()
        local e = Entry(owner.raw)
        if not (v and e) or ui.draft then return end
        local parent, _, index = ParentOf(v, e)
        if value == "edit" then
            Dz.Edit(owner.raw)
        elseif value == "dup" then
            Mutate(RM().DuplicateNode, e.path)
        elseif value == "up" or value == "down" then
            RememberMove(e.raw, parent and parent.raw or "top", index + (value == "up" and -1 or 1))
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
            local destGroup
            if dest ~= "top" then
                local d = RM().NodeByRaw(v, dest.raw)
                if not d then return end
                destGroup = d
            end
            RememberMove(e.raw, destGroup and destGroup.raw or "top")
        end
    end

    local function History(redo)
        if ui.draft or not RM().StepRuleEdit(session, redo) then return end
        ui.mode, ui.nodeRaw, ui.groupRaw = nil, nil, nil
        Dz.Say(nil)
        Poke()
    end

    function Dz.Undo() History(false) end
    function Dz.Redo() History(true) end

    -- Accepting a secondary editor stages a single change in the builder.
    function Dz.Commit()
        local draft = ui.draft
        if not draft then return end
        local clean, problem = R.ReminderConditions.Check(draft)
        if not clean or (problem and not Pl().Capability({ cond = clean })) then
            Dz.Say(problem or RM().REFUSE.value, "warn")
            return
        end
        local editing = ui.mode == "edit"
        local entry = editing and Entry(ui.nodeRaw)
        local path = not editing and GroupPath(View(), ui.groupRaw)
        if (editing and not entry) or (not editing and (not path or (ui.insertRev and ui.insertRev ~= Revision()))) then
            Dz.Say("The rule changed. Cancel this edit and try again.", "warn")
            return
        end
        local function Apply(handle)
            local ok, why
            if editing then
                ok, why = RM().SetCondition(handle, entry.path, clean, true)
            else
                ok, why = RM().AddCondition(handle, clean.type, path, clean, ui.insert)
            end
            if ok and clean.type == "equipment" and clean.what == "item" then RM().StageRuleItem(handle, clean.item) end
            return ok, why
        end
        if not Mutate(Apply) then return end
        ui.mode, ui.nodeRaw, ui.draft, ui.groupRaw = nil, nil, nil, nil
    end

    function Dz.Pick(entry, destination, index)
        if ui.draft then Dz.Say("Finish or cancel the current condition first.", "warn"); return end
        ui.groupRaw = destination or ui.groupRaw or "top"
        ui.mode, ui.draft, ui.pickedName = "new", entry.make(), entry.name
        ui.insert = index
        ui.insertRev = index and Revision()
        if s.picker.search:HasFocus() then s.picker.search:ClearFocus() end
        Poke()
    end

    function Dz.AddGroup(match)
        local path
        if ui.groupRaw ~= "top" then
            local g = Entry(ui.groupRaw)
            if not g then ui.mode, ui.groupRaw = nil, nil Poke() return end
            path = g.path
        end
        if not Mutate(RM().AddGroup, path, match) then return end
        ui.mode, ui.groupRaw = nil, nil
        Dz.Say(nil)
        Poke()
    end

    ---------------------------------------------------------------- panels
    local function LayoutTarget(self, v, x, y, w)
        local me = RM().CharacterKey()
        local sc = v.scope
        tp:SetWidth(w)
        K.Put(tp, self, x, y)
        local h = 10
        if sc.who == "characters" then
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
        -- In the basic view the card already has the choices: opened from it, the editor holds only what the card
        -- can't (the item or spell, a number of your own).
        local compact = not isNew and not self.isAdvanced
        local idKind = Pl().NeedsId(draft)
        local amount = Pl().EditField(draft, "amount")
        local h = 10
        local title = "Edit this condition"
        if isNew then title = "Add: " .. (ui.pickedName or "a condition")
        elseif compact and idKind then title = idKind == "spell" and (draft.type == "aura" and ("Choose the " .. (draft.harmful and "debuff" or "buff")) or "Choose the spell") or "Choose the item"
        elseif compact and amount then title = "Choose the amount" end
        K.Text(ep.title, title, nil, 12, h, ep)
        G.Color(ep.title, pal.bronzeText)
        h = h + 22
        local cx = 12
        local placed = false
        for _, spec in ipairs(compact and {} or Pl().CardFields(draft)) do
            if spec.kind ~= "number" then
                local control = ep[spec.key]
                if cx + control:GetWidth() + 12 > w then cx, h = 12, h + 29 end
                control:SetValue(spec.value, spec.label)
                K.Put(control, ep, cx, h)
                cx = cx + control:GetWidth() + 8
                placed = true
            end
        end
        if placed then h = h + 32 end
        if amount then
            if not ep.amount:HasFocus() then ep.amount:SetText(amount.value and tostring(amount.value) or "") end
            K.Put(ep.amount, ep, 12, h)
            K.Text(ep.amountWords, amount.value and amount.words(amount.value) or ("A whole number from %d to %d"):format(amount.min, amount.max), amount.value and nil or "quiet", 92, h + 5, ep)
            h = h + 30
        end
        if idKind then
            if not ep.item:HasFocus() then ep.item:SetText(Pl().IdText(draft)) end
            ep.item:SetWidth(draft.type == "aura" and 170 or 110)
            K.Put(ep.item, ep, 12, h)
            local text, tone
            if idKind == "spell" then
                text = Pl().SpellLine(draft)
                tone = text and nil or "quiet"
                text = text or (draft.type == "aura" and "Drag a spell here, or type IDs separated by commas" or "Drag a spell here, or type its ID")
            elseif not draft.item then
                text, tone = "Drag an item here from your bags, or type its ID", "quiet"
            else
                text, tone = K.ItemLine(draft.item)
            end
            ep.itemInfo:SetWidth(math.max(80, w - ep.item:GetWidth() - 40))
            K.Text(ep.itemInfo, text, tone, ep.item:GetWidth() + 22, h + 5, ep)
            h = h + 30
        end
        ep.reads:SetWidth(w - 24)
        local sentence = Pl().CondSentence(draft) or "(not finished)"
        h = h + K.Text(ep.reads, "Reads as: " .. sentence, nil, 12, h, ep) + 6
        local clean, problem = R.ReminderConditions.Check(draft)
        local short = Pl().Capability({ cond = clean })
        local blocked = (not clean) or (problem and not short)
        ep.problem:SetWidth(w - 24)
        if short then
            h = h + K.Text(ep.problem, short, "warn", 12, h, ep) + 6
        elseif problem then
            h = h + K.Text(ep.problem, problem:gsub("^%l", string.upper), "warn", 12, h, ep) + 6
        end
        ep.done.text:SetText(isNew and "Add condition" or "Done")
        ep.done:SetWidth(isNew and 130 or 100)
        ep.done:SetEnabled(not blocked)
        K.Put(ep.done, ep, 12, h)
        K.Put(ep.cancel, ep, 12 + (isNew and 138 or 108), h)
        h = h + 37
        ep:SetHeight(h)
        return h
    end

    local function LayoutPalette(v)
        local w, pad = PALETTE_W, PALETTE_PAD
        local group = ui.groupRaw ~= "top" and Entry(ui.groupRaw)
        local match = group and group.match or v.match
        local picking = ui.mode == "pick" or ui.mode == "newgroup"
        local title = "Add a condition"
        pp:SetWidth(w)
        pp.title:SetWidth(w - pad * 2)
        local h = 12 + K.Text(pp.title, title, nil, pad, 10, pp) + 5
        pp.where:SetWidth(w - pad * 2)
        if picking then
            local context = group and "Adding to this group" or "Choose a condition"
            h = h + K.Text(pp.where, context, "quiet", pad, h, pp) + 8
        else
            pp.where:Hide()
        end
        if ui.mode == "newgroup" then
            pp.search:Hide()
            pp.category:Hide()
            pp.newNote:SetWidth(w - pad * 2)
            local words = Pl().Words(match).heading
            h = h + K.Text(pp.newNote, ("Create a group inside \"%s\". Choose how its conditions combine."):format(words), nil, pad, h, pp) + 8
            K.Put(pp.newAny, pp, pad, h)
            K.Put(pp.newAll, pp, pad, h + 30)
            K.Put(pp.back, pp, pad, h + 62)
            h = h + 94
        else
            K.Put(pp.search, pp, pad, h)
            if not pp.search:HasFocus() and pp.search:GetText() ~= (ui.query or "") then pp.search:SetText(ui.query or "") end
            pp.searchHint:SetShown((ui.query or "") == "" and not pp.search:HasFocus())
            pp.category:SetValue(ui.category or "all", ui.category or "All categories")
            K.Put(pp.category, pp, pad, h + 36)
            h = h + 74
            local depth = group and #group.path or 0
            local canGroup = s.isAdvanced and depth + 2 <= RM().MAX_DEPTH and v.counts.groups < RM().MAX_GROUPS
            if canGroup then
                local row = PickRow(1)
                row.entry, row.isGroup = nil, true
                R.Icons.Apply(row.icon, "reminderWhen", ICON)
                row.name:SetText("Create a condition group")
                row.blurb:Hide(); row.note:Hide()
                row:SetSize(w - pad * 2, 36)
                K.Put(row, pp, pad, h)
                h = h + 43
            elseif picking and s.isAdvanced then
                local why = depth + 2 > RM().MAX_DEPTH and RM().REFUSE.tooDeep or RM().REFUSE.groupsFull
                pp.newNote:SetWidth(w - pad * 2)
                h = h + K.Text(pp.newNote, why, "quiet", pad, h, pp) + 6
            end
            local entries, shown, locationShown = Pl().Entries(), 0, false
            local priority = { weaponEnchant = 1, equipment = 2, ammunition = 3, ["player:dungeon"] = 4,
                ["player:raid"] = 5, class = 6, talent = 7 }
            table.sort(entries, function(a, b)
                local x, y = priority[a.key] or 8, priority[b.key] or 8
                if x ~= y then return x < y end
                return a.name < b.name
            end)
            for _, category in ipairs(Pl().PALETTE_ORDER) do
                local header
                if not ui.category or ui.category == category then
                    for _, e in ipairs(entries) do
                        local location = e.key == "player:dungeon" or e.key == "player:raid"
                        if e.category == category and Pl().Matches(e, ui.query) and not (location and locationShown) then
                            if location then locationShown = true end
                            if not header then
                                if not pp.categories[category] then
                                    pp.categories[category] = M.ReminderFont(G.Text(pp, "title"), 16, true)
                                    pp.categories[category]:SetWidth(w - pad * 2)
                                    pp.dividers[category] = G.Solid(pp, "ARTWORK", { 0.42, 0.34, 0.24 }, 0.65)
                                    pp.dividers[category]:SetSize(w - pad * 2, 1)
                                end
                                header = pp.categories[category]
                                K.Put(pp.dividers[category], pp, pad, h + 1)
                                h = h + K.Text(header, category, nil, pad, h + 7, pp) + 13
                                G.Color(header, { 0.85, 0.76, 0.62 })
                            end
                            shown = shown + 1
                            local row = PickRow(shown + (canGroup and 1 or 0))
                            row.entry, row.isGroup = e, false
                            local cond = e.make()
                            Pl().ApplyArt(row.icon, cond, 30)
                            local title = Pl().CardTitle(cond)
                            row.name:SetText(title or e.name)
                            row.blurb:Hide(); row.note:Hide()
                            row:SetSize(w - pad * 2, 34)
                            K.Put(row, pp, pad, h)
                            h = h + 37
                        end
                    end
                end
            end
            if shown == 0 then
                pp.none:SetWidth(w - pad * 2)
                h = h + K.Text(pp.none, "No matching conditions.", "quiet", pad, h, pp) + 6
            end
            if picking then K.Put(pp.cancel, pp, pad, h); h = h + 32 end
        end
        pp:SetHeight(h + 8)
        K.Put(pp, companion.paletteContent, 0, 0)
        companion.paletteContent:SetHeight(h + 8)
        if fitPaletteRail then fitPaletteRail(h + 8) end
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
                K.Put(g.grip, g.box, hx - 5, Rel(cur) + 1)
                hx = hx + 19
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
            local rail = match == "any" and { 0.46, 0.53, 0.42 } or { 0.57, 0.46, 0.32 }
            g.rail:SetColorTexture(rail[1], rail[2], rail[3], 0.63)
            cur = cur + HEAD_H + 2
        else
            g.rail:SetColorTexture(0.57, 0.46, 0.32, 0.63)
        end
        if isFolded then
            K.Text(g.folded, Pl().GroupLine(owner), "quiet", 10 + 22, Rel(cur), g.box)
            g.folded:SetWidth(w - 50)
            cur = cur + 20
            g.box:SetWidth(w)
            g.box:SetHeight(cur - boxTop + 4)
            K.Put(g.box, self, x, boxTop)
            drag:Group(g.box, owner.raw, n, depth)
            return cur + 4
        end
        if owner and owner.why and n > 0 then
            g.problem:SetWidth(w - 30)
            cur = cur + K.Text(g.problem, Pl().Problem(owner) or "", "warn", 12, Rel(cur), g.box) + 4
        end
        if n == 0 then
            g.empty:SetWidth(w - 30)
            local text = top and "Nothing yet. A reminder with no conditions never shows: add the first one below."
                or "Add a condition or remove this group."
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
                local groupBox = self.groups[st.group + 1]
                cur = LayoutGroup(self, v, entry, depth + 1, inner, cw, cur, st, ex) + 2
                if groupBox then drag:Row(groupBox.box, owner and owner.raw or "top", i, true) end
            else
                st.card = st.card + 1
                local card = self.cards[st.card]
                if not card then break end
                card.raw = entry.raw
                local sentence = Pl().Sentence(entry)
                local capabilityShort = Pl().Capability(entry)
                local textW = cw - (28 + ICON + 10) - (MORE_W + 24)
                card.text:SetWidth(textW)
                card.text:SetText(sentence)
                G.Color(card.text, entry.cond and pal.text or pal.stone)
                local th = card.text:GetStringHeight() or 14
                card.text:ClearAllPoints()
                card.text:SetPoint("TOPLEFT", ICON + 38, -9)
                card.text:Show()
                card.grip:ClearAllPoints()
                card.grip:SetPoint("TOPLEFT", 3, -6)
                Pl().ApplyArt(card.icon, entry.cond, ICON)
                card.icon:Show()
                -- a second line: what is wrong with it, or (when asked) what it sees now
                local ch = 9 + th
                local cx = ex and ex.cards and ex.cards[entry.raw]
                local line, lineTone
                if entry.why or capabilityShort then
                    line, lineTone = Pl().Problem(entry), "invalid"
                elseif cx then
                    line, lineTone = cx.state == "unknown" and "Unknown" or cx.word, cx.state
                end
                if line then
                    card.note:SetWidth(textW)
                    card.note:SetText(line)
                    Color(card.note, lineTone)
                    card.note:ClearAllPoints()
                    card.note:SetPoint("TOPLEFT", card, "TOPLEFT", ICON + 38, -(ch + 6))
                    card.note:Show()
                    ch = ch + 6 + math.max(16, card.note:GetStringHeight() or 12)
                end
                ch = math.max(ch + 10, 38)
                card:SetSize(cw, ch)
                K.Put(card, self, inner, cur)
                drag:Row(card, owner and owner.raw or "top", i)
                card.more:SetWidth(28)
                card.more:SetValue(nil, "···")
                card.more:ClearAllPoints()
                card.more:SetPoint("TOPRIGHT", -10, -7)
                card.more:SetShown(card:IsMouseOver() and not ui.draft)
                cur = cur + ch + GAP
                if ui.mode == "edit" and ui.nodeRaw == entry.raw and ui.draft then
                    cur = cur + LayoutEditor(self, inner, cur, cw) + GAP
                end
            end
        end
        -- where the next one goes
        if ui.groupRaw == (owner and owner.raw or "top") and ui.mode == "new" and ui.draft then
            cur = cur + LayoutEditor(self, inner, cur, cw) + GAP
        else
            local limit = v.counts.conditions >= RM().MAX_CONDITIONS
            K.Put(g.add, g.box, RAIL + INSET, Rel(cur))
            g.add.text:SetText(top and match == "all" and n > 0 and "Add restriction" or "Add a condition")
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
        drag:Group(g.box, owner and owner.raw or "top", n, depth)
        return cur + 4
    end

    local function LayoutBasic(self, v, y, w, ex)
        local n = #v.conditions
        local h = y
        local function Draft(index)
            if ui.mode == "new" and ui.draft and (ui.insert or n + 1) == index then
                h = h + LayoutEditor(self, PAD, h, w) + 8
                return true
            end
        end
        -- Where the cards' fields start: 300, or (when a card in this rule has three fields) just past the widest title,
        -- the same for every card so the fields line up down the rule.
        local fieldX = 300
        for i, entry in ipairs(v.conditions) do
            local cond = entry.cond
            if cond and not Pl().LocationValues(entry) and #Pl().CardFields(cond) >= 3 then fieldX = nil end
        end
        if not fieldX then
            local widest = 0
            for i, entry in ipairs(v.conditions) do
                local cond = entry.cond or { type = "player", state = "dungeon" }
                local title = self.cards[i].title
                title:SetText(Pl().CardTitle(cond) or "")
                widest = math.max(widest, math.ceil(title:GetStringWidth() or 196))
            end
            fieldX = math.max(236, math.min(300, 99 + widest + 16))
        end
        for i, entry in ipairs(v.conditions) do
            if i == 2 then
                K.Put(self.onlyHead, self, PAD, h + 6)
                h = h + 37
            end
            Draft(i)
            local card = self.cards[i]
            local locations = Pl().LocationValues(entry)
            local cond = entry.cond or { type = "player", state = locations and locations[1] }
            card.raw, card.locations = entry.raw, locations
            card:SetSize(w, locations and 128 or 96)
            K.Put(card, self, PAD, h)
            card.grip:ClearAllPoints()
            card.grip:SetPoint("LEFT", 3, 0)
            card.artWell:Show()
            Pl().ApplyArt(card.art, cond, 45)
            K.Text(card.title, Pl().CardTitle(cond), nil, 99, 20, card)
            local observed = ex and ex.cards[entry.raw]
            local state = entry.why and "invalid" or (observed and observed.state or "unknown")
            local word = state == "unknown" and "Unknown" or Pl().STATE_WORDS[state]
            K.Text(card.note, word, nil, 99, 46, card)
            card.note:SetWidth(110)
            Color(card.note, state)
            card.more:SetWidth(28)
            card.more:SetValue(nil, "···")
            card.more:ClearAllPoints()
            card.more:SetPoint("TOPRIGHT", -10, -9)
            card.more:SetShown(card:IsMouseOver() and not ui.draft)
            local needsItem = Pl().NeedsId(cond) ~= nil
            if needsItem then
                card.item.text:SetText(Pl().IdButton(cond))
                K.Put(card.item, card, fieldX, 11)
            end
            if locations then
                local x = 99
                for j, value in ipairs(locations) do
                    local chip = card.chips[j]
                    chip.text:SetText((value == "dungeon" and "Dungeon" or "Raid") .. "  ×")
                    chip:SetEnabled(not ui.draft and RM().Writable())
                    K.Put(chip, card, x, 69)
                    x = x + 115
                end
                if not cond.negate then
                    card.choose:SetValue(nil, "+ Choose")
                    card.choose:SetActive(#locations < 2 and not ui.draft and RM().Writable())
                    K.Put(card.choose, card, x, 69)
                end
                if entry.group then
                    K.Text(card.locationNote, "Any selected location", "quiet", 99, 105, card)
                elseif cond.negate then
                    K.Text(card.locationNote, "Outside the selected location", "quiet", 99, 105, card)
                end
                if not entry.group then
                    local field = Pl().EditField(cond, "op")
                    card.inline = { field }
                    card.fields[1]:SetSize(105, 26)
                    card.fields[1]:SetValue(field.value, field.label)
                    card.fields[1]:SetActive(not ui.draft and RM().Writable())
                    K.Put(card.fields[1], card, w - 132, 21)
                end
            else
                local fields = Pl().CardFields(cond)
                card.inline = fields
                local x = fieldX
                local fieldWidth = math.floor((w - x - 18 - (#fields - 1) * 7) / #fields)
                for j, spec in ipairs(fields) do
                    local field = card.fields[j]
                    field:SetSize(fieldWidth, 30)
                    field:SetValue(spec.value, spec.label)
                    field:SetActive(RM().Writable() and not ui.draft)
                    K.Put(field, card, x, needsItem and 49 or 33)
                    M.ReminderFont(field.text, 14, true)
                    x = x + fieldWidth + 7
                end
            end
            drag:Row(card, "top", i)
            h = h + (locations and 141 or 109)
            if ui.mode == "edit" and ui.nodeRaw == entry.raw and ui.draft then
                h = h + LayoutEditor(self, PAD, h, w) + 8
            end
        end
        if n == 1 then
            K.Put(self.onlyHead, self, PAD, h + 6)
            h = h + 37
        end
        if not Draft(n + 1) then
            local available = v.counts.conditions < RM().MAX_CONDITIONS
            self.addBasic.text:SetText(available and (n > 0 and "+ Add restriction" or "+ Add a condition") or "Condition limit reached")
            self.addBasic:SetEnabled(available and not ui.draft and RM().Writable())
            G.Color(self.addBasic.text, self.addBasic:IsEnabled() and pal.bronzeText or pal.stone)
            K.Put(self.addBasic, self, PAD, h)
            drag:Row(self.addBasic, "top", n + 1, nil, true)
            h = h + 50
        end
        return h
    end

    ---------------------------------------------------------------- the whole section
    local function Layout(self, v, y)
        if ui.id ~= v.id then Reset(v.id) end
        HideAll()
        drag:ClearTargets()
        local me = RM().CharacterKey()
        local canUseBasic = Pl().Basic(v)
        self.isAdvanced = not canUseBasic or ui.advanced == true
        local h = 14
        local inner = W - PAD * 2

        -- who
        local target = Pl().Targeting(v, me)
        self.who:SetText(target)
        local scope = v.scope
        local choice = scope.who == "all" and "all" or (#scope.characters == 1 and scope.characters[1] == me and "me" or "chosen")
        local whoLabel = choice == "all" and "Every character" or (choice == "me" and "This character" or "Chosen characters")
        if scope.class then
            local class = RM().ClassName(scope.class)
            whoLabel = choice == "all" and (class .. " characters") or (whoLabel .. " · " .. class)
        end
        self.whoEdit:SetValue(choice, whoLabel)
        self.whoEdit:SetActive(not ui.draft and RM().Writable())
        if ui.mode == "target" then h = h + LayoutTarget(self, v, PAD, h, inner) + 8 end

        -- Observe the isolated draft. The controller continues to run the saved rule.
        local ST, E = R.ReminderState, R.ReminderEval
        local context = ST.Context()
        local out = E.Run(v, ST.Peek(v), context)
        local dirty, undo, redo = RM().RuleEditState(session)
        local status = dirty and out.status or R.ReminderController.Status(v.id)
        local ex = Pl().Explain(v, out, status, context)
        self.ruleHead:SetText(self.isAdvanced and "Advanced logic" or "Show a reminder when")
        K.Put(self.ruleHead, self, PAD, h)
        h = h + 32
        if self.isAdvanced then
            h = LayoutGroup(self, v, nil, 1, PAD, inner, h, { card = 0, group = 0, sep = 0 }, ex)
        else
            h = LayoutBasic(self, v, h, inner, ex)
        end
        self.advanced.text:SetText(self.isAdvanced and (canUseBasic and "Basic view" or "Uses Advanced logic") or "Advanced logic")
        self.advanced:SetEnabled(canUseBasic and not ui.draft)
        self.advanced:Paint(self.isAdvanced)
        self.undo:SetEnabled(undo and not ui.draft)
        self.redo:SetEnabled(redo and not ui.draft)
        self.undo:PaintIcon(); self.redo:PaintIcon()
        companion.save:SetEnabled(dirty and not ui.draft and RM().Writable())
        companion.dirty:SetText(dirty and "Unsaved changes" or "No unsaved changes")
        G.Color(companion.dirty, dirty and pal.bronzeText or pal.stone)
        companion.subtitle:SetText("Choose what matters. See when it will show.")
        companion.try:Paint(ui.try)
        self.explain:Paint(explainOpen)
        PlaceFeedback(LayoutDiagnostics(v, ex, out))
        for _, p in ipairs(v.problems) do
            if p == RM().PROBLEM.tooMany or p == RM().PROBLEM.tooManyGroups then
                h = h + K.Text(self.limit, p .. " The rest are kept exactly as saved, and are not shown here.", "warn", PAD, h + 4, self) + 8
                break
            end
        end
        h = h + 10
        self:SetHeight(h)
        K.Put(self, companion.content, 0, y)
        return h
    end
    function s:Layout(v, y)
        local width = parent:GetWidth()
        summary:SetWidth(width)
        summary.rule:SetWidth(width - PAD * 2)
        local trigger, restriction = Pl().CompactRule(v)
        summary.rule:SetText(trigger)
        summary.edit:ClearAllPoints()
        summary.edit:SetPoint("TOPRIGHT", summary, "TOPRIGHT", -PAD, -7)
        summary.edit:Show()
        local h = 37 + (summary.rule:GetStringHeight() or 14)
        summary.explanation = summary.explanation or {}
        for _, row in ipairs(summary.explanation) do row:Hide() end
        local structured = Pl().Basic(v) and #v.conditions > 2
        if structured then
            summary.rule:Hide()
            summary.restriction:Hide()
            summary.explanationHost = summary.explanationHost or CreateFrame("Frame", nil, summary)
            summary.explanationHost:ClearAllPoints()
            summary.explanationHost:SetPoint("TOPLEFT", PAD, -37)
            summary.explanationHost:SetWidth(width - PAD * 2)
            h = 37 + Pl().DrawExplanation(summary.explanationHost, summary.explanation, v, width - PAD * 2, 0)
            summary.explanationHost:SetHeight(h - 37)
        else summary.rule:Show() end
        if restriction and not structured then
            summary.restriction:SetWidth(width - PAD * 2)
            h = h + K.Text(summary.restriction, "Only while · " .. restriction, "quiet", PAD, h + 3, summary) + 6
        else
            summary.restriction:Hide()
        end
        local live, tone = Pl().Visibility(v.id)
        summary.status:SetWidth(width - PAD * 2)
        h = h + K.Text(summary.status, live, tone, PAD, h + 3, summary) + 10
        summary:SetHeight(h); K.Put(summary, parent, 0, y)
        if not Dz.Shown() then self:Hide(); return h end
        self:SetWidth(W)
        companion.title:SetText("When — " .. v.name)
        if companion.reminderRaw ~= v.raw or not session then
            Reset(v.id)
            local why
            session, why = RM().BeginRuleEdit(v.id)
            if not session then Dz.Close(); env.Say(why, "warn"); return h end
            companion.reminderRaw = v.raw; companion.scroll:SetVerticalScroll(0)
            companion.paletteScroll:SetVerticalScroll(0)
        end
        local saved = v
        v = View()
        if not v then Dz.Close(); return h end
        local Perf = R.Perf
        local full
        if Perf and Perf.Call then full = Perf.Call("reminders.designer.layout", Layout, self, v, 0)
        else full = Layout(self, v, 0) end
        companion.content:SetHeight(full)
        if fitRuleRail then fitRuleRail(full) end
        LayoutPalette(v)
        companion.result:SetText(Pl().RuleSummary(v))
        local label, state, reason, visible = Pl().LiveFeedback(saved)
        companion.live:SetText(label)
        Color(companion.live, state)
        companion.reason:SetText(reason or "")
        local liveTop = math.max(47, 18 + (companion.result:GetStringHeight() or 18))
        companion.live:ClearAllPoints()
        companion.live:SetPoint("TOPLEFT", feedback, "TOPLEFT", 45, -liveTop)
        companion.reason:ClearAllPoints()
        companion.reason:SetPoint("TOPLEFT", feedback, "TOPLEFT", 178, -(liveTop + 1))
        companion.eye:ClearAllPoints()
        companion.eye:SetPoint("TOPLEFT", feedback, "TOPLEFT", 16, -(liveTop - 3))
        local detailX = 178 + math.min(350, companion.reason:GetStringWidth() or 0) + 18
        self.explain:ClearAllPoints()
        self.explain:SetPoint("TOPLEFT", feedback, "TOPLEFT", detailX, -(liveTop - 7))
        companion.try:ClearAllPoints()
        companion.try:SetPoint("TOPLEFT", feedback, "TOPLEFT", 12, -(liveTop + 29))
        companion.message:ClearAllPoints()
        companion.message:SetPoint("TOPLEFT", feedback, "TOPLEFT", 165, -(liveTop + 37))
        feedback:SetHeight(liveTop + 69)
        PlaceFeedback()
        companion.eye:SetVertexColor(unpack(StateColor(state)))
        companion.eye:SetTexture(R.PATH .. [[media\guildloc\]] .. (visible and "eye-open-small.tga" or "eye-hidden-small.tga"))
        companion.rail:Draw(saved, v)
        return h
    end
    s.Reset = Dz.Reset
    return s
end
