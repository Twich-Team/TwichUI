-- TwichUI settings: Reminders (reminders/). A feature card with the switch, then a frame of this window's own: your
-- reminders as a list (each with a thumbnail, its rule as a sentence, what it is doing now and its own switch), ways to
-- start one, and the chosen reminder's editor (RemindersEditor.lua: Show, When (RemindersDesigner.lua, in RemindersPlain.lua's
-- words), Placement, Preview appearance, Test). Built the
-- first time the page is shown; list rows are made as they are first needed and reused on every redraw. Which reminder
-- is open, and which situations the Test section tries, are kept for the session only.
-- Every change goes through reminders/Config.lua's own functions, which check it. Nothing here is needed for reminders
-- to work, and nothing here equips, uses or casts anything.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.RemindersPage = P

local W = 644                -- the settings window's content width
local PAD, GAP = 14, 12
local ROW_H, THUMB = 44, 30
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local f, built
local rows = {}
local sections
local selected               -- the reminder open in the editor (this session only)
local height = 420           -- what the window gives this frame (P.Height); follows the content
local queued, relayoutQueued = false, false

-- A reminder's state in a word or two, for its list row (the words carry the meaning; the color only agrees).
local SHORT = {
    showing = "Showing", holding = "Showing", hidden = "Hidden", disabled = "Off", notApplicable = "Not for this character",
    waiting = "Waiting", pending = "Waiting out its delay", invalid = "Needs attention", off = "Reminders off", world = "Waiting",
}

local function Wg() return R.SettingsWidgets end
local function RM() return R.Reminders end

local function Tone(fs, tone)
    local G = Wg()
    local pal = G.pal
    G.Color(fs, tone == "warn" and pal.danger.text or (tone == "ok" and pal.tealHi or (tone == "quiet" and pal.stone or pal.textDim)))
end

local function Put(item, parent, x, y)
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    item:Show()
end

---------------------------------------------------------------------------
-- Redrawing: many changes at once are one redraw; a change of height asks the window to place things again
---------------------------------------------------------------------------
function P.QueueRefresh(delay)
    if queued then return end
    queued = true
    C_Timer.After(delay or 0, function()
        queued = false
        P.Refresh()
    end)
end

local function QueueRelayout()
    if relayoutQueued then return end
    relayoutQueued = true
    C_Timer.After(0, function()
        relayoutQueued = false
        local UI = R.SettingsUI
        if UI and UI.Refresh then UI.Refresh() end
    end)
end

function P.Height() return height end

-- The line under the chosen reminder's name: what just happened, or why it didn't.
function P.Say(text, tone)
    P.lastSaid, P.lastTone = text, tone
    if f and f.say then
        f.say:SetText(text or "")
        Tone(f.say, tone)
    end
    P.QueueRefresh()
end

function P.Selected() return selected end
-- What has been built, read only (for the tests): the list rows and the editor's sections.
function P.Parts() return { frame = f, rows = rows, sections = sections } end
function P.Select(id)
    selected = id
    P.lastSaid = nil
    P.QueueRefresh()
end

-- A new reminder from a template, opened in the editor. It starts turned off.
function P.Create(kind)
    local ok, id = RM().Create(kind)
    if not ok then P.Say(id, "warn") return false, id end
    selected = id
    local v = RM().Get(id)
    P.Say(("Made \"%s\". It stays off until you turn it on%s."):format(v.name, v.valid and "" or ", once what is listed below is done"), "ok")
    return true, id
end

-- A problem as the player reads it: one that is only a limit of this client ("Condition 2: this game client doesn't say
-- whether...") is said in its short form ("Cannot check ammunition on this client."), the rest as Config.lua words them.
local function Friendly(v, problem)
    local label = problem:match("^Condition ([%d%.]+): ")
    local Pl = R.RemindersPlain
    if label and Pl then
        for _, e in ipairs(v.leaves) do
            if table.concat(e.path, ".") == label then
                local short = Pl.Capability(e)
                if short then return short end
            end
        end
    end
    return problem
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local function Thumb(tex, v)
    local d = v.display
    local m = d.mode
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetAlpha(1)
    if (m == "artwork" or m == "artworkText") and RM().Art(d.art) then
        local file, l, r, t, b, aspect = RM().ArtTexture(d.art, THUMB)
        tex:SetTexture(file)
        tex:SetTexCoord(l, r, t, b)
        tex:SetSize(math.max(1, math.floor(THUMB * math.min(1, aspect) + 0.5)), math.floor(THUMB / math.max(1, aspect) + 0.5))
        return
    end
    tex:SetSize(THUMB, THUMB)
    if (m == "icon" or m == "iconText") and d.iconSource == "item" then
        local icon = d.item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(d.item)
        tex:SetTexture(icon or QUESTION)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    elseif (m == "icon" or m == "iconText") and R.Icons then
        R.Icons.Apply(tex, d.icon, THUMB)
    elseif R.Icons then
        R.Icons.Apply(tex, "reminders", THUMB)   -- words only: the feature's bell, quieter
        tex:SetAlpha(0.55)
    end
end

local function Row(i)
    if rows[i] then return rows[i] end
    local G = Wg()
    local pal = G.pal
    local row = CreateFrame("Button", nil, f.list)
    row:SetSize(W - PAD * 2, ROW_H)
    row.sel = G.Solid(row, "BACKGROUND", pal.bronzeText, 0.10)
    row.sel:SetAllPoints()
    row.bar = G.Solid(row, "ARTWORK", pal.bronzeText, 1)
    row.bar:SetWidth(2)
    row.bar:SetPoint("TOPLEFT", 0, 0)
    row.bar:SetPoint("BOTTOMLEFT", 0, 0)
    G.Hover(row, pal.text, 0.05)
    row.thumb = row:CreateTexture(nil, "ARTWORK")
    row.thumb:SetPoint("CENTER", row, "LEFT", 8 + THUMB / 2, 0)
    row.name = G.Text(row, "body")
    row.name:SetPoint("TOPLEFT", 16 + THUMB, -6)
    row.name:SetWidth(330)
    row.name:SetWordWrap(false)
    row.rule = G.Text(row, "meta")
    row.rule:SetPoint("TOPLEFT", 16 + THUMB, -24)
    row.rule:SetWidth(400)
    row.rule:SetWordWrap(false)
    row.check = G.Checkbox(row, function(on)
        if not row.id then return end
        local ok, why = RM().SetEnabled(row.id, on)
        if not ok then
            selected = row.id
            P.Say(why, "warn")
        end
    end)
    row.check:SetPoint("RIGHT", -8, 0)
    R.Interact.Tip(row.check, "Turned on", function()
        local v = row.id and RM().Get(row.id)
        if v and not v.valid then return "Turns this reminder on or off.", "It can't be turned on yet: " .. (v.problems[1] or "") end
        return "Turns this reminder on or off. Off, it never shows and reads nothing; on, it shows while its conditions are true."
    end)
    row.state = G.Text(row, "small")
    row.state:SetPoint("RIGHT", row.check, "LEFT", -10, 0)
    row.state:SetJustifyH("RIGHT")
    row:SetScript("OnClick", function() if row.id then P.Select(row.id) end end)
    rows[i] = row
    return row
end

local function LayoutList(list, y)
    local G = Wg()
    local CT, E = R.ReminderController, R.ReminderEval
    local card = f.list
    local h = 12
    f.count:SetText(("%d of %d"):format(#list, RM().MAX))
    h = h + 26
    f.startLabel:ClearAllPoints()
    f.startLabel:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -(h + 4))
    local x = PAD + (f.startLabel:GetStringWidth() or 80) + 10
    for _, b in ipairs(f.templates) do
        if x + b:GetWidth() > W - PAD then   -- the buttons that don't fit go on the next line, from the left
            x = PAD
            h = h + 32
        end
        Put(b, card, x, h)
        x = x + b:GetWidth() + 8
    end
    h = h + 32
    if not RM().Writable() then
        f.newer:SetText(RM().PROBLEM.newer)
        Tone(f.newer, "warn")
        Put(f.newer, card, PAD, h)
        h = h + (f.newer:GetStringHeight() or 12) + 8
    else
        f.newer:Hide()
    end
    if #list == 0 then
        f.empty:SetText("No reminders yet. Start one from the buttons above: \"Missing shield\" and \"Ammunition\" are ready to use once you turn them on; the others are starting points to finish. Each starts turned off, so nothing appears until you say so.")
        Put(f.empty, card, PAD, h)
        h = h + (f.empty:GetStringHeight() or 24) + 10
    else
        f.empty:Hide()
    end
    for i, v in ipairs(list) do
        local row = Row(i)
        row.id = v.id
        Thumb(row.thumb, v)
        row.name:SetText(v.name)
        local status = CT.Status(v.id)
        if v.valid then
            row.rule:SetText(E.RuleSentence(v))
            Tone(row.rule, "quiet")
        else
            row.rule:SetText(v.problems[1] and Friendly(v, v.problems[1]) or "")
            Tone(row.rule, "warn")
        end
        row.state:SetText(SHORT[status] or "")
        Tone(row.state, (status == "showing" or status == "holding") and "ok" or (status == "invalid" and "warn" or "quiet"))
        row.check:SetChecked(v.enabled)
        row.check:SetActive(RM().Writable())
        local isSel = v.id == selected
        row.sel:SetShown(isSel)
        row.bar:SetShown(isSel)
        G.Color(row.name, isSel and G.pal.text or G.pal.textDim)
        Put(row, card, PAD, h)
        h = h + ROW_H + 2
    end
    for i = #list + 1, #rows do
        rows[i].id = nil
        rows[i]:Hide()
    end
    h = h + 8
    card:SetHeight(h)
    Put(card, f, 0, y)
    return h
end

---------------------------------------------------------------------------
-- The chosen reminder's head: its name, its switch, copy and delete, and what is wrong with it
---------------------------------------------------------------------------
local function Delete(id)
    local v = RM().Get(id)
    if not v then return end
    local text = ("Delete the reminder \"%s\"?\n\nOnly this reminder is removed (it is taken off the screen at once). Your other reminders and settings are not changed. This can't be undone."):format(v.name)
    R.Interact.Confirm("TWICHUI_REMINDER_DELETE", text, function()
        local ok, why = RM().Delete(id)
        if ok then
            if selected == id then selected = nil end
            P.Say(("Deleted \"%s\"."):format(v.name), "ok")
        else
            P.Say(why, "warn")
        end
    end, { accept = DELETE or "Delete", valid = function()
        if RM().Get(id) then return true end
        return false, "That reminder is already gone, so nothing was deleted."
    end })
end

local function LayoutHead(v, y)
    local head = f.head
    local h = 14
    Put(f.nameLabel, head, PAD, h + 4)
    if not f.nameBox:HasFocus() then f.nameBox:SetText(v.name) end
    Put(f.nameBox, head, PAD + 60, h)
    f.onBox:SetChecked(v.enabled)
    f.onBox:SetActive(RM().Writable() and not v.broken)
    f.onText:SetText(v.enabled and "On" or (v.valid and "Off" or "Off (not ready)"))
    Tone(f.onText, v.enabled and "ok" or "quiet")
    Put(f.onBox, head, PAD + 330, h + 2)
    Put(f.onText, head, PAD + 356, h + 6)
    Put(f.delete, head, W - PAD - 90, h)
    Put(f.duplicate, head, W - PAD - 90 - 8 - 100, h)
    h = h + 32
    if #v.problems > 0 then
        local lines = {}
        for i, p in ipairs(v.problems) do lines[i] = "-  " .. Friendly(v, p) end
        f.problems:SetText((v.enabled and "It is turned on but can't show until this is fixed:\n" or "Before it can be turned on:\n") .. table.concat(lines, "\n"))
        Tone(f.problems, "warn")
        Put(f.problems, head, PAD, h)
        h = h + (f.problems:GetStringHeight() or 12) + 8
    else
        f.problems:Hide()
    end
    if P.lastSaid then
        f.say:SetText(P.lastSaid)
        Tone(f.say, P.lastTone)
        Put(f.say, head, PAD, h)
        h = h + (f.say:GetStringHeight() or 12) + 8
    else
        f.say:Hide()
    end
    h = h + 4
    head:SetHeight(h)
    Put(head, f, 0, y)
    return h
end

---------------------------------------------------------------------------
-- Building and drawing
---------------------------------------------------------------------------
local function Build()
    built = true
    local G = Wg()
    local I = R.Interact

    -- your reminders, and ways to start one
    f.list = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.list:SetWidth(W)
    G.Panel(f.list)
    f.listTitle = G.Text(f.list, "heading")
    f.listTitle:SetPoint("TOPLEFT", PAD, -14)
    f.listTitle:SetText("Your reminders")
    f.count = G.Text(f.list, "meta")
    f.count:SetPoint("TOPRIGHT", -PAD, -16)
    f.count:SetJustifyH("RIGHT")
    f.startLabel = G.Text(f.list, "small")
    f.startLabel:SetText("Start a new one:")
    f.templates = {}
    for i, t in ipairs(RM().TEMPLATES) do
        local kind = t[1]
        local b = G.Button(f.list, t[2], 120, "secondary", function() P.Create(kind) end)
        b:SetWidth(math.max(100, math.ceil(b.text:GetStringWidth() or 90) + 28))
        I.Tip(b, t[2], t[3] .. " It starts turned off.")
        f.templates[i] = b
    end
    f.newer = G.Text(f.list, "small")
    f.newer:SetWidth(W - PAD * 2)
    f.empty = G.Text(f.list, "small")
    f.empty:SetWidth(W - PAD * 2)

    -- the chosen one's head
    f.head = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.head:SetWidth(W)
    G.Panel(f.head)
    f.nameLabel = G.Text(f.head, "body")
    f.nameLabel:SetText("Name")
    f.nameBox = G.EditBox(f.head, 250, 22)
    f.nameBox:SetMaxLetters(RM().NAME_MAX * 4)
    local function SaveName(self)
        if not selected then return end
        local ok, why = RM().SetName(selected, self:GetText())
        if not ok then
            self:SetText(RM().Get(selected) and RM().Get(selected).name or "")
            P.Say(why, "warn")
        end
    end
    f.nameBox:SetScript("OnEnterPressed", function(self) SaveName(self); self:ClearFocus() end)
    f.nameBox:HookScript("OnEditFocusLost", SaveName)
    I.Tip(f.nameBox, "Name", "Only for you, in this list. It is never shown on screen and never sent anywhere.")
    f.onBox = G.Checkbox(f.head, function(on)
        if not selected then return end
        local ok, why = RM().SetEnabled(selected, on)
        if not ok then P.Say(why, "warn") end
    end)
    I.Tip(f.onBox, "Turned on", "On, it shows while its conditions are true (Test below says what they see now). A new reminder starts off, so it never covers the world before it is ready.")
    f.onText = G.Text(f.head, "body")
    f.duplicate = G.Button(f.head, "Duplicate", 100, "secondary", function()
        if not selected then return end
        local ok, id = RM().Duplicate(selected)
        if not ok then P.Say(id, "warn") return end
        local name = RM().Get(id).name
        selected = id
        P.Say(("Made a copy, \"%s\". It is off until you turn it on; the original is unchanged."):format(name), "ok")
    end)
    I.Tip(f.duplicate, "Duplicate", "A copy with its own identity, right after this one, turned off. Changing either never changes the other.")
    f.delete = G.Button(f.head, "Delete", 90, "danger", function() if selected then Delete(selected) end end)
    I.Tip(f.delete, "Delete", "Removes this reminder, after asking. Nothing else changes.")
    f.problems = G.Text(f.head, "small")
    f.problems:SetWidth(W - PAD * 2)
    f.say = G.Text(f.head, "small")
    f.say:SetWidth(W - PAD * 2)

    sections = R.RemindersEditor.Build(f, {
        id = function() return selected end,
        view = function() return selected and RM().Get(selected) end,
        Say = P.Say,
        Changed = function() P.QueueRefresh() end,
    })
end

function P.Refresh()
    if not (f and built and f:IsShown()) then return end
    local list = RM().List()
    if selected and not RM().Get(selected) then selected = nil end
    if not selected and list[1] then selected = list[1].id end
    local y = LayoutList(list, 0) + GAP
    local v = selected and RM().Get(selected)
    if v then
        y = y + LayoutHead(v, y) + GAP
        for _, s in ipairs(sections) do y = y + s:Layout(v, y) + GAP end
    else
        f.head:Hide()
        for _, s in ipairs(sections) do s:Hide() end
    end
    local h = math.max(1, y - GAP)
    f:SetHeight(h)
    if h ~= height then
        height = h
        QueueRelayout()
    end
end

-- Only while the page is shown: the game telling of changes the Test section's "Right now" reads (for a reminder that
-- isn't running it is read when drawn), and answers about items named here.
local EVENTS = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE",
    "PLAYER_UNGHOST", "PLAYER_MOUNT_DISPLAY_CHANGED", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }

-- The page's frame (the settings window shows it under the Reminders card). Built the first time it is shown.
function P.Frame()
    if f then return f end
    f = CreateFrame("Frame")
    f:SetWidth(W)
    f:Hide()
    f:SetScript("OnShow", function(self)
        if not built then Build() end
        for _, e in ipairs(EVENTS) do self:RegisterEvent(e) end
        P.Refresh()
    end)
    f:SetScript("OnHide", function(self)
        for _, e in ipairs(EVENTS) do self:UnregisterEvent(e) end
        if f.nameBox then f.nameBox:ClearFocus() end
        if R.RemindersDesigner then R.RemindersDesigner.Reset() end   -- an open editor, picker or undo is put away
    end)
    f:SetScript("OnEvent", function() P.QueueRefresh(0.2) end)
    return f
end

-- A change made anywhere (here, a profile change, a decision of the live reminders) redraws the page if it is shown.
-- Registered once: this file is loaded once a session.
if R.Reminders then R.Reminders.Subscribe(function() P.QueueRefresh() end) end
if R.ReminderController then R.ReminderController.OnChange(function() P.QueueRefresh(0.05) end) end

local function Count()
    local n, on = 0, 0
    for _, v in ipairs(R.Reminders.List()) do
        n = n + 1
        if v.enabled then on = on + 1 end
    end
    return n, on
end

K.Page({
    key = "reminders", icon = "reminders", name = "Reminders", order = 22, group = "everyday",
    description = "Artwork, an icon or a few words on screen while conditions you choose are true, such as an empty off hand. Nothing appears until you make a reminder and turn it on.",
    keywords = "reminder reminders shield equip equipment gear off hand offhand main hand weapon two-handed fishing pole item missing artwork icon picture words text alert notice condition conditions rule rules when combat dead ghost alive mounted mount preview test simulate simulation position move character class ammo ammunition arrows bullets quiver ranged bow gun crossbow hunter out of ammo no ammo wrong ammo",
    overview = {
        label = "Reminders", tip = "Artwork, an icon or words on screen while conditions you choose are true, such as a missing shield.",
        when = function() return R.Reminders ~= nil end,
        status = function()
            if not R:Enabled("reminders") then return K.OnOff(false) end
            local n, on = Count()
            if n == 0 then return K.OnOff(false, nil, "None yet") end
            return K.OnOff(on > 0, ("%d of %d on"):format(on, n), ("%d, none on"):format(n))
        end,
    },
    when = function() return R.Reminders ~= nil and R.ReminderController ~= nil and R.RemindersEditor ~= nil and R.RemindersDesigner ~= nil and R.RemindersPlain ~= nil end,
    build = function()
        K.Card({
            title = "Reminders", icon = "reminders",
            what = "Shows artwork, an icon or a few words while conditions you choose are true, such as an empty off hand, and hides it the rest of the time.",
            summary = function()
                local n, on = Count()
                if n == 0 then return "None made yet." end
                return ("%d made, %d turned on."):format(n, on)
            end,
            consequence = "A reminder only reads what is equipped, what you carry as ammunition and what you are doing: TwichUI never equips, uses or casts anything for you, says nothing in chat and sends nothing. Each new reminder starts turned off. Turning this off hides every reminder at once and stops listening; your reminders are kept.",
            details = {
                { "What can a reminder watch?", "Your equipment: a slot that is empty or not, a specific item equipped or not, or the kind of item in a slot (a shield, a weapon, a two-handed weapon, an item held in the off hand, a fishing pole). The ammunition for your ranged weapon: none selected, used up, or the wrong kind. And you: in combat, alive or dead (a ghost counts as dead), mounted." },
                { "Why would one wait instead of showing?", "Right after logging in, or with an item the game hasn't described yet, a condition can't be checked. The reminder then stays hidden rather than guess, and its Test section says what it is waiting for." },
                { "Who sees them?", "Only you. Reminders are saved in your profile; each one can be limited to some of your characters, or to a class." },
            },
        })
        K.Toggle("reminders", "Show my reminders",
            "On: each reminder you turned on appears while its conditions are true. Off: none appears and nothing is listened for. Your reminders are kept either way.")
    end,
    host = function() return P.Frame() end, hostAfter = "Reminders", hostHeight = function() return P.Height() end,
})
