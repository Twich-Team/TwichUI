-- TwichUI settings: Reminders, the editor's sections (Reminders.lua draws the list and puts these under it)
-- Show (what appears), When (who it is for and its conditions, read as a sentence), Placement (where, how big, and
-- behind "More placement and appearance options" the rest), Preview (drawn here by the reminder's own layout code, or on
-- the screen where it sits) and Test (what it sees right now, and the same decision for situations you pick). Each
-- section's widgets are made once, the first time the page is shown, and only placed and filled after that; condition
-- rows and test lines come from pools of RM.MAX_CONDITIONS. Every change goes through Config.lua's functions, which
-- check it; nothing here writes saved data, reads the game's equipment for itself or changes it.
--
--   Ed.Build(parent, env) -> sections    env: { id() (the reminder shown), view(), Say(text, tone), Changed() }
--   section:Layout(view, y) -> height    placed at y on parent; hidden when the reminder isn't there

local R = TwichUI
local Ed = {}
R.RemindersEditor = Ed

local W = 644              -- the settings window's content width
local PAD, ICON = 14, 28
local LABEL_X, CTRL_X = 14, 190
local ROW = 30
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local MAX_REQUESTS = 2

local function Wg() return R.SettingsWidgets end
local function RM() return R.Reminders end

local function Choices(list)
    local out = {}
    for i, c in ipairs(list) do out[i] = { value = c[1], label = c[2], tooltip = c[3] } end
    return out
end

local function LabelOf(list, value)
    for _, c in ipairs(list) do if c[1] == value then return c[2] end end
    return tostring(value)
end

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

-- An item's name, and "ok" | "loading" | "missing", asking the game at most twice while this is open.
local requested = {}
function Ed.ItemInfo(id)
    if not id then return nil, "none" end
    local name = C_Item.GetItemNameByID and Plain(C_Item.GetItemNameByID(id))
    if type(name) == "string" and name ~= "" then return name, "ok" end
    if C_Item.GetItemInfoInstant and Plain((C_Item.GetItemInfoInstant(id))) == nil and (requested[id] or 0) >= MAX_REQUESTS then
        return nil, "missing"
    end
    if (requested[id] or 0) < MAX_REQUESTS and C_Item.RequestLoadItemDataByID then
        requested[id] = (requested[id] or 0) + 1
        C_Item.RequestLoadItemDataByID(id)
    end
    return nil, "loading"
end

local function ItemLine(id)
    if not id then return "No item chosen yet.", "warn" end
    local name, state = Ed.ItemInfo(id)
    if state == "ok" then return ("%s (item %d)"):format(name, id), "ok" end
    if state == "missing" then return ("The game has no item %d. Check the number."):format(id), "warn" end
    return ("Item %d: loading its details..."):format(id), nil
end

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------
local function Section(parent, icon, title, blurb)
    local G = Wg()
    local s = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    s:SetWidth(W)
    G.Panel(s)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetSize(ICON, ICON)
    s.icon:SetPoint("TOPLEFT", PAD - 2, -10)
    if not (R.Icons and R.Icons.Apply(s.icon, icon, ICON) ~= "fallback") then s.icon:Hide() end
    s.title = G.Text(s, "heading")
    s.title:SetPoint("TOPLEFT", PAD + ICON + 8, -12)
    s.title:SetText(title)
    s.blurb = G.Text(s, "small")
    s.blurb:SetPoint("TOPLEFT", PAD + ICON + 8, -30)
    s.blurb:SetWidth(W - PAD * 2 - ICON - 8)
    s.blurb:SetText(blurb)
    s:Hide()
    return s
end

-- Where a section's rows start: under its title and its blurb, however many lines that takes.
local function Top(s)
    s.top = math.max(ICON + 16, 30 + (s.blurb:GetStringHeight() or 12) + 12)
    return s.top
end

local function Label(parent, text)
    local fs = Wg().Text(parent, "body")
    fs:SetText(text)
    fs:SetWidth(CTRL_X - LABEL_X - 8)
    fs:SetWordWrap(false)
    return fs
end

local function Put(item, parent, x, y)
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    item:Show()
end

-- A label and its control on one row; returns the next row's y.
local function Line(parent, label, control, y, dy)
    Put(label, parent, LABEL_X, y + 4)
    Put(control, parent, CTRL_X, y)
    return y + (dy or ROW)
end

local function Note(parent, width)
    local fs = Wg().Text(parent, "small")
    fs:SetWidth(width or (W - LABEL_X - PAD))
    fs:SetWordWrap(true)
    return fs
end

local function Tone(fs, tone)
    local G = Wg()
    local pal = G.pal
    G.Color(fs, tone == "warn" and pal.danger.text or (tone == "ok" and pal.tealHi or (tone == "quiet" and pal.stone or pal.textDim)))
end

-- Text on a row, placed, its height returned.
local function Text(fs, text, tone, x, y, parent)
    fs:SetText(text or "")
    Tone(fs, tone)
    Put(fs, parent, x, y)
    return fs:GetStringHeight() or 12
end

local function HideAll(list) for _, x in ipairs(list) do x:Hide() end end

local function Dropdown(parent, w, choices, onPick, tipTitle, tip)
    local d = Wg().Dropdown(parent, w, onPick)
    d:SetChoices(choices)
    if tip then R.Interact.Tip(d, tipTitle, tip) end
    return d
end

local function Checkbox(parent, label, onToggle, tip)
    local box = Wg().Checkbox(parent, onToggle)
    box.label = Wg().Text(parent, "body")
    box.label:SetText(label)
    box.label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    if tip then R.Interact.Tip(box, label, tip) end
    return box
end

local function Slider(parent, key, onSet)
    local lim = RM().LIMITS[key]
    local s = Wg().Slider(parent, 300, onSet)
    s:SetRange(lim[1], lim[2], 1)
    return s
end

---------------------------------------------------------------------------
-- Show: what appears
---------------------------------------------------------------------------
local function ShowSection(parent, env)
    local s = Section(parent, "reminderShow", "Show", "What appears on screen: a picture from TwichUI's gallery, an icon, your words, or a picture or icon with words.")
    local function Set(key, value) local ok, why = RM().SetDisplay(env.id(), key, value) if not ok then env.Say(why, "warn") end end

    s.modeLabel = Label(s, "Display")
    s.mode = Dropdown(s, 220, function() return Choices(RM().CHOICES.mode) end, function(v) Set("mode", v) end,
        "Display", "A picture, an icon, your words, or a picture or icon with words. What it shows is separate from when it shows.")
    s.artLabel = Label(s, "Artwork")
    s.art = Dropdown(s, 220, function() return Choices(RM().CHOICES.art) end, function(v) Set("art", v) end,
        "Artwork", "Pictures that come with TwichUI. New ones are added to TwichUI itself (tools/make_reminder_art.py); pictures can't be imported in the game.")
    s.srcLabel = Label(s, "Icon from")
    s.src = Dropdown(s, 220, function() return Choices(RM().CHOICES.iconSource) end, function(v) Set("iconSource", v) end,
        "Icon from", "One of TwichUI's own icons, or the icon of an item you choose. The item doesn't need to be equipped or carried: a reminder about a missing shield can't use the icon of a shield that isn't there.")
    s.iconLabel = Label(s, "Icon")
    s.icon = Dropdown(s, 220, function() return Choices(RM().CHOICES.icon) end, function(v) Set("icon", v) end)
    s.itemLabel = Label(s, "Item")
    s.itemBox = Wg().EditBox(s, 120, 22)
    s.itemBox:SetMaxLetters(200)
    local function TakeItem(text)
        local id = RM().ParseItem(text)
        if not id then env.Say("That isn't an item ID. Type the number from the item's link, paste the link, or drop the item on the box.", "warn") return end
        s.itemBox:SetText("")
        s.itemBox:ClearFocus()
        Set("item", id)
    end
    s.itemBox:SetScript("OnEnterPressed", function(self) TakeItem(self:GetText()) end)
    s.itemBox:SetScript("OnReceiveDrag", function()
        local kind, id = GetCursorInfo()
        if kind ~= "item" then return end
        ClearCursor()   -- the item goes straight back where it came from; only its ID is noted
        TakeItem(tostring(Plain(id) or ""))
    end)
    R.Interact.Tip(s.itemBox, "Item", "Type its item ID, paste its link, or drop it here from your bags (it goes straight back). Press Enter.")
    s.itemInfo = Note(s, W - CTRL_X - 140 - PAD)
    s.textLabel = Label(s, "Words")
    s.textBox = Wg().EditBox(s, 300, 22)
    s.textBox:SetMaxLetters(RM().TEXT_MAX * 4)
    local function SaveText(self)
        local ok, why = RM().SetDisplay(env.id(), "text", self:GetText())
        if not ok then env.Say(why, "warn") end
    end
    s.textBox:SetScript("OnEnterPressed", function(self) SaveText(self); self:ClearFocus() end)
    s.textBox:HookScript("OnEditFocusLost", SaveText)
    R.Interact.Tip(s.textBox, "Words", ("Plain text, up to %d characters. Shown as you type it: nothing in it is read as a command or a code."):format(RM().TEXT_MAX))
    s.parts = { s.modeLabel, s.mode, s.artLabel, s.art, s.srcLabel, s.src, s.iconLabel, s.icon, s.itemLabel, s.itemBox, s.itemInfo, s.textLabel, s.textBox }

    function s:Layout(v, y)
        HideAll(self.parts)
        local d = v.display
        local C = RM().CHOICES
        local h = Top(self)
        self.mode:SetValue(d.mode, LabelOf(C.mode, d.mode))
        h = Line(self, self.modeLabel, self.mode, h)
        local m = d.mode
        if m == "artwork" or m == "artworkText" then
            self.art:SetValue(d.art, RM().Art(d.art) and LabelOf(C.art, d.art) or (tostring(d.art) .. " (not available)"))
            h = Line(self, self.artLabel, self.art, h)
        end
        if m == "icon" or m == "iconText" then
            self.src:SetValue(d.iconSource, LabelOf(C.iconSource, d.iconSource))
            h = Line(self, self.srcLabel, self.src, h)
            if d.iconSource == "item" then
                Put(self.itemLabel, self, LABEL_X, h + 4)
                Put(self.itemBox, self, CTRL_X, h)
                local text, tone = ItemLine(d.item)
                Text(self.itemInfo, text, tone, CTRL_X + 130, h + 4, self)
                h = h + ROW
            else
                self.icon:SetValue(d.icon, LabelOf(C.icon, d.icon))
                h = Line(self, self.iconLabel, self.icon, h)
            end
        end
        if m == "text" or m == "artworkText" or m == "iconText" then
            if not self.textBox:HasFocus() then self.textBox:SetText(d.text) end
            h = Line(self, self.textLabel, self.textBox, h)
        end
        h = h + 6
        self:SetHeight(h)
        Put(self, parent, 0, y)
        return h
    end
    return s
end

---------------------------------------------------------------------------
-- When: who it is for, and its conditions as a sentence
---------------------------------------------------------------------------
local function Subjects()
    local C = R.ReminderConditions
    local out = {}
    for _, slot in ipairs(C.SLOTS) do out[#out + 1] = { value = "slot:" .. slot[1], label = slot[3] } end
    out[#out + 1] = { value = "player", label = "You (the player)" }
    return out
end

local function SubjectOf(cond)
    if type(cond) ~= "table" then return nil, "?" end
    local C = R.ReminderConditions
    if cond.type == "equipment" then
        local s = C.Slot(cond.slot)
        return "slot:" .. tostring(cond.slot), s and s[3] or tostring(cond.slot)
    elseif cond.type == "player" then
        return "player", "You (the player)"
    end
    return nil, "Unknown kind"
end

local function ValueChoices(cond)
    local C = R.ReminderConditions
    local out = {}
    if cond.type == "equipment" then
        for _, c in ipairs(C.SlotChoices(cond.slot)) do out[#out + 1] = { value = c[1], label = c[2] } end
    elseif cond.type == "player" then
        for _, st in ipairs(C.STATES) do
            if C.StateSupported(st[1]) or cond.state == st[1] then
                out[#out + 1] = { value = st[1], label = st[3]:gsub("^%l", string.upper) .. (C.StateSupported(st[1]) and "" or " (not reported by this client)") }
            end
        end
    end
    return out
end

local function ValueLabel(cond)
    for _, c in ipairs(ValueChoices(cond)) do if c.value == (cond.what or cond.state) then return c.label end end
    return tostring(cond.what or cond.state)
end

local WHO = {
    { "all", "Every character", "Every character using this profile." },
    { "me", "This character only", "Only the character you are playing now." },
    { "chosen", "Characters I choose", "Only the characters you add here: log in on each one and press Add this character." },
}

local function WhenSection(parent, env)
    local s = Section(parent, "reminderWhen", "When", "Shown while its conditions are true, for the characters it is for; hidden the rest of the time.")
    local function Did(ok, why) if not ok then env.Say(why, "warn") end end

    s.whoLabel = Label(s, "For")
    s.who = Dropdown(s, 220, function() return Choices(WHO) end, function(v)
        local id, me = env.id(), RM().CharacterKey()
        if v == "all" then Did(RM().SetScope(id, "who", "all")) return end
        if not me then env.Say("The game hasn't said which character this is yet. Try again in a moment.", "warn") return end
        if v == "me" then
            local view = env.view()
            for _, c in ipairs(view.scope.characters) do if c ~= me then RM().RemoveCharacter(id, c) end end
        end
        Did(RM().AddCharacter(id, me))
        Did(RM().SetScope(id, "who", "characters"))
    end, "For", "Which characters it applies to. It is saved in the profile, so other characters using the profile see the same list.")
    s.chars = Note(s, W - CTRL_X - PAD)
    s.addMe = Wg().Button(s, "Add this character", 150, "secondary", function() Did(RM().AddCharacter(env.id(), RM().CharacterKey())) end)
    s.removeMe = Wg().Button(s, "Remove this character", 170, "secondary", function() Did(RM().RemoveCharacter(env.id(), RM().CharacterKey())) end)
    s.classLabel = Label(s, "Class")
    s.class = Dropdown(s, 220, function()
        local out = { { value = "", label = "Any class" } }
        for _, c in ipairs(RM().CLASSES) do out[#out + 1] = { value = c, label = RM().ClassName(c) } end
        return out
    end, function(v) Did(RM().SetScope(env.id(), "class", v ~= "" and v or nil)) end,
        "Class", "Limits it to one class, whatever its conditions. Separate from its equipment conditions: a Warrior isn't assumed to carry a shield.")

    s.matchLabel = Label(s, "Show when")
    s.match = Dropdown(s, 220, function()
        return { { value = "all", label = "All conditions match" }, { value = "any", label = "Any condition matches" } }
    end, function(v) Did(RM().SetMatch(env.id(), v)) end, "Show when", "All: every condition below must be true. Any: one is enough.")
    s.single = Label(s, "Show when")

    s.rows = {}
    for i = 1, RM().MAX_CONDITIONS do
        local row = {}
        local function Cond() local v = env.view() local e = v and v.conditions[i] return e and (e.cond or e.raw) end
        local function SetCond(new)
            local ok, why = RM().SetCondition(env.id(), i, new)
            if not ok then env.Say(why, "warn") end
            return ok
        end
        row.subject = Dropdown(s, 170, Subjects, function(value)
            local cur = Cond()
            if value == "player" then
                if type(cur) == "table" and cur.type == "player" then return end
                SetCond(R.ReminderConditions.Get("player").New())
                return
            end
            local key = value:match("^slot:(.+)$")
            local new = { type = "equipment", slot = key, negate = type(cur) == "table" and cur.negate == true or false }
            local allowed = {}
            for _, c in ipairs(R.ReminderConditions.SlotChoices(key)) do allowed[c[1]] = true end
            local what = type(cur) == "table" and cur.type == "equipment" and cur.what or nil
            new.what = allowed[what] and what or (key == "any" and "item" or "empty")
            if new.what == "item" and type(cur) == "table" then new.item = cur.item end
            SetCond(new)
        end)
        row.op = Dropdown(s, 86, function() return { { value = "is", label = "is" }, { value = "isnot", label = "is not" } } end, function(value)
            local cur = Cond()
            if type(cur) ~= "table" then return end
            local new = RM().DeepCopy(cur)
            new.negate = value == "isnot"
            SetCond(new)
        end)
        row.value = Dropdown(s, 176, function() local cur = Cond() return type(cur) == "table" and ValueChoices(cur) or {} end, function(value)
            local cur = Cond()
            if type(cur) ~= "table" then return end
            local new = RM().DeepCopy(cur)
            if new.type == "player" then new.state = value else new.what = value end
            SetCond(new)
        end)
        row.item = Wg().EditBox(s, 88, 22)
        row.item:SetMaxLetters(200)
        local function TakeItem(text)
            local id = RM().ParseItem(text)
            if not id then env.Say("That isn't an item ID. Type the number from the item's link, paste the link, or drop the item on the box.", "warn") return end
            local cur = Cond()
            if type(cur) ~= "table" then return end
            local new = RM().DeepCopy(cur)
            new.item = id
            row.item:ClearFocus()
            if SetCond(new) then
                -- a reminder that shows an item's icon and has none yet uses this one (it can be changed in Show)
                local d = env.view() and env.view().display
                if d and d.iconSource == "item" and not d.item then RM().SetDisplay(env.id(), "item", id) end
            end
        end
        row.item:SetScript("OnEnterPressed", function(self) TakeItem(self:GetText()) end)
        row.item:SetScript("OnReceiveDrag", function()
            local kind, id = GetCursorInfo()
            if kind ~= "item" then return end
            ClearCursor()
            TakeItem(tostring(Plain(id) or ""))
        end)
        R.Interact.Tip(row.item, "Item", "Its item ID, its link pasted here, or the item dropped here from your bags (it goes straight back). Press Enter.")
        row.remove = Wg().Button(s, "Remove", 70, "secondary", function()
            local ok, why = RM().RemoveCondition(env.id(), i)
            if not ok then env.Say(why, "warn") end
        end)
        R.Interact.Tip(row.remove, "Remove", "Removes this condition from the reminder. Nothing else changes.")
        row.problem = Note(s)
        row.itemName = Note(s, W - CTRL_X - PAD)
        s.rows[i] = row
    end
    s.addEquip = Wg().Button(s, "Add an equipment condition", 210, "secondary", function()
        local ok, why = RM().AddCondition(env.id(), "equipment")
        if not ok then env.Say(why, "warn") end
    end)
    s.addPlayer = Wg().Button(s, "Add a condition about you", 200, "secondary", function()
        local ok, why = RM().AddCondition(env.id(), "player")
        if not ok then env.Say(why, "warn") end
    end)
    R.Interact.Tip(s.addPlayer, "A condition about you", "In combat, alive or dead (a ghost counts as dead), or mounted.")
    s.sentence = Note(s)
    s.scope = Note(s)
    s.note = Note(s)

    local parts = { s.whoLabel, s.who, s.chars, s.addMe, s.removeMe, s.classLabel, s.class, s.matchLabel, s.match, s.single,
        s.addEquip, s.addPlayer, s.sentence, s.scope, s.note }
    for _, row in ipairs(s.rows) do
        for _, k in ipairs({ "subject", "op", "value", "item", "remove", "problem", "itemName" }) do parts[#parts + 1] = row[k] end
    end

    function s:Layout(v, y)
        HideAll(parts)
        local E = R.ReminderEval
        local me = RM().CharacterKey()
        local h = Top(self)
        local sc = v.scope
        local who = "all"
        if sc.who == "characters" then
            who = (#sc.characters == 1 and sc.characters[1] == me) and "me" or "chosen"
        end
        self.who:SetValue(who, LabelOf(WHO, who))
        h = Line(self, self.whoLabel, self.who, h)
        if who == "chosen" then
            local names = #sc.characters > 0 and table.concat(sc.characters, ", ") or "No character added yet."
            h = h + Text(self.chars, names, #sc.characters == 0 and "warn" or nil, CTRL_X, h, self) + 6
            local mine = false
            for _, c in ipairs(sc.characters) do if c == me then mine = true end end
            Put(mine and self.removeMe or self.addMe, self, CTRL_X, h)
            h = h + ROW
        end
        self.class:SetValue(sc.class or "", sc.class and RM().ClassName(sc.class) or "Any class")
        h = Line(self, self.classLabel, self.class, h) + 4

        -- "Show when" (and, with two or more, all or any), then one row per condition read as a sentence:
        -- [Off hand] [is not] [Shield]
        local n = #v.conditions
        if n >= 2 then
            self.match:SetValue(v.match, v.match == "any" and "Any condition matches" or "All conditions match")
            h = Line(self, self.matchLabel, self.match, h)
        elseif n == 1 then
            Put(self.single, self, LABEL_X, h)
            h = h + 20
        end
        for i, entry in ipairs(v.conditions) do
            local row = self.rows[i]
            if not row then break end
            local cond = entry.cond or entry.raw
            local x = LABEL_X
            if type(cond) == "table" and entry.provider then
                local sv, sl = SubjectOf(cond)
                row.subject:SetValue(sv, sl)
                Put(row.subject, self, x, h)
                row.op:SetValue(cond.negate and "isnot" or "is", cond.negate and "is not" or "is")
                Put(row.op, self, x + 176, h)
                row.value:SetValue(cond.what or cond.state, ValueLabel(cond))
                Put(row.value, self, x + 268, h)
                if cond.type == "equipment" and cond.what == "item" then
                    if not row.item:HasFocus() then row.item:SetText(cond.item and tostring(cond.item) or "") end
                    Put(row.item, self, x + 450, h)
                end
            else
                Text(row.problem, "A condition TwichUI can't read.", "warn", x, h + 4, self)
            end
            Put(row.remove, self, W - PAD - 70, h)
            h = h + ROW
            if type(cond) == "table" and cond.type == "equipment" and cond.what == "item" and cond.item then
                local text, tone = ItemLine(cond.item)
                h = h + Text(row.itemName, text, tone, x + 4, h - 4, self) + 2
            end
            if entry.why then
                h = h + Text(row.problem, entry.why:gsub("^%l", string.upper), "warn", x + 4, h - 2, self) + 4
            end
        end
        if n < RM().MAX_CONDITIONS then
            Put(self.addEquip, self, n == 0 and CTRL_X or LABEL_X, h + 2)
            Put(self.addPlayer, self, (n == 0 and CTRL_X or LABEL_X) + 218, h + 2)
            h = h + ROW + 4
        end
        h = h + Text(self.sentence, E.RuleSentence(v), n == 0 and "warn" or "quiet", LABEL_X, h, self) + 4
        h = h + Text(self.scope, "For: " .. E.ScopeSentence(v, me) .. ".", "quiet", LABEL_X, h, self) + 4
        -- the shield template's own explanation, while its one condition is what the template made
        local c1 = n == 1 and v.conditions[1].cond
        if c1 and c1.type == "equipment" and c1.slot == "offHand" and c1.what == "shield" and c1.negate then
            h = h + 4 + Text(self.note, RM().SHIELD_NOTE, nil, LABEL_X, h + 4, self) + 4
        end
        h = h + 10
        self:SetHeight(h)
        Put(self, parent, 0, y)
        return h
    end
    return s
end

---------------------------------------------------------------------------
-- Placement: where, how big; the rest behind one disclosure
---------------------------------------------------------------------------
local function PlacementSection(parent, env)
    local s = Section(parent, "reminderPlacement", "Placement", "Where it sits and how big it is. It never takes a click, so it can't get in the way of the world.")
    local function Set(key, value) local ok, why = RM().SetDisplay(env.id(), key, value) if not ok then env.Say(why, "warn") end end
    local function Whole(fn) return function(v) fn(math.floor(v + 0.5)) end end
    local D = R.ReminderDisplay

    s.presetLabel = Label(s, "Position")
    s.preset = Dropdown(s, 220, function()
        local out = {}
        for i, p in ipairs(RM().PRESETS) do out[i] = { value = p[1], label = p[2], tooltip = p[6] } end
        return out
    end, function(v)
        local ok, why = RM().SetPreset(env.id(), v)
        if not ok then env.Say(why, "warn") end
    end, "Position", "A place on the screen, or where you moved it. Below the middle sits under your character, clear of it.")
    s.move = Wg().Button(s, "Move on screen", 150, "secondary", function()
        local v = env.view()
        if not v then return end
        if D.Positioning() and D.PreviewId() == v.id then D.PositionEnd() env.Changed() return end
        local ok = D.PreviewStart(v, true)
        if not ok then env.Say("It can be moved when you are out of combat.", "warn") end
        env.Changed()
    end)
    R.Interact.Tip(s.move, "Move on screen", "Shows it where it sits, with a handle to drag. Right-click the handle, or press Done, to finish. Moving ends by itself in combat. The offsets below follow.")
    s.sizeLabel = Label(s, "Size")
    s.size = Slider(s, "size", Whole(function(v) Set("size", v) end))
    s.opacityLabel = Label(s, "Opacity")
    s.opacity = Slider(s, "opacity", Whole(function(v) Set("opacity", v) end))
    s.textSizeLabel = Label(s, "Text size")
    s.textSize = Slider(s, "textSize", Whole(function(v) Set("textSize", v) end))
    s.placeLabel = Label(s, "Words go")
    s.textPlace = Dropdown(s, 220, function() return Choices(RM().CHOICES.textPlace) end, function(v) Set("textPlace", v) end)

    -- the rest, closed until asked for (kept for the session only)
    s.more = CreateFrame("Button", nil, s)
    s.more:SetSize(320, 22)
    s.more.text = Wg().Text(s.more, "small")
    s.more.text:SetPoint("LEFT", 16, 0)
    Wg().Color(s.more.text, Wg().pal.tealHi)
    s.more.down = Wg().Chevron(s.more, s.more, "LEFT", 7, 0, true, Wg().pal.tealHi)
    s.more.up = Wg().Chevron(s.more, s.more, "LEFT", 7, 0, false, Wg().pal.tealHi)
    s.more:SetScript("OnClick", function() Ed.moreOpen = not Ed.moreOpen; env.Changed() end)

    s.keep = Checkbox(s, "Keep its proportions", function(on) Set("keepAspect", on and true or false) end,
        "On: one size, and the picture keeps its own shape. Off: a width and a height of their own (the picture is stretched to them).")
    s.widthLabel = Label(s, "Width")
    s.width = Slider(s, "width", Whole(function(v) Set("width", v) end))
    s.heightLabel = Label(s, "Height")
    s.height = Slider(s, "height", Whole(function(v) Set("height", v) end))
    s.fontLabel = Label(s, "Font")
    s.font = Dropdown(s, 220, function()
        local v = env.view()
        local out = {}
        for i, c in ipairs(R.MenuStyle.Fonts.Choices(v and v.display.font or "default", { { "default", "Game font (default)" } })) do
            out[i] = { value = c[1], label = c[2] }
        end
        return out
    end, function(v) Set("font", v) end, "Font", "Fonts come from LibSharedMedia, so TwichUI's, EllesmereUI's and any other addon's are listed. A font that has gone is drawn with the game's own and stays chosen.")
    s.outlineLabel = Label(s, "Outline")
    s.outline = Dropdown(s, 220, function() return Choices(RM().CHOICES.outline) end, function(v) Set("outline", v) end)
    s.colorLabel = Label(s, "Text color")
    s.color = Wg().Swatch(s, function(hex) Set("textColor", hex) end)
    s.panelLabel = Label(s, "Background")
    s.panel = Dropdown(s, 220, function() return Choices(RM().CHOICES.panel) end, function(v) Set("panel", v) end)
    s.pointLabel = Label(s, "Anchored to")
    s.point = Dropdown(s, 220, function() return Choices(RM().POINTS) end, function(v)
        local view = env.view()
        if view then
            local ok, why = RM().SetPosition(env.id(), v, view.place.x, view.place.y)
            if not ok then env.Say(why, "warn") end
        end
    end, "Anchored to", "The point of the screen its offsets are measured from, and the point of the reminder that sits there.")
    s.offsetLabel = Label(s, "Offset (x, y)")
    local function Offset(axis)
        local box = Wg().EditBox(s, 70, 22)
        box:SetMaxLetters(6)
        box:SetScript("OnEnterPressed", function(self)
            local view = env.view()
            local n = tonumber(self:GetText())
            self:ClearFocus()
            if not (view and n) then return end
            local x, y = view.place.x, view.place.y
            if axis == "x" then x = n else y = n end
            local ok, why = RM().SetPosition(env.id(), view.place.point, x, y)
            if not ok then env.Say(("Offsets can be up to %d either way."):format(RM().POSITION_LIMIT), "warn") end
            env.Changed()
        end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); env.Changed() end)
        return box
    end
    s.x = Offset("x")
    s.y = Offset("y")
    R.Interact.Tip(s.x, "Horizontal offset", "Screen units from the anchor point: more is further right. Press Enter.")
    R.Interact.Tip(s.y, "Vertical offset", "Screen units from the anchor point: more is higher. Press Enter.")
    s.strataLabel = Label(s, "Layer")
    s.strata = Dropdown(s, 220, function() return Choices(RM().CHOICES.strata) end, function(v) Set("strata", v) end,
        "Layer", "Whether it is drawn under or over the game's windows. Medium suits most setups.")
    s.fade = Checkbox(s, "Fade in and out", function(on) Set("fade", on and true or false) end,
        "A quarter-second fade as it appears and goes. Off: it simply appears and goes. Off while Notifications' Reduced motion is on.")
    s.pulse = Checkbox(s, "Pulse gently when it appears", function(on) Set("pulse", on and true or false) end,
        "Three slow breaths of its opacity when it appears, then still. Off while Notifications' Reduced motion is on.")
    s.delayLabel = Label(s, "Wait before showing")
    s.delay = Slider(s, "delay", Whole(function(v) Set("delay", v) end))
    s.minLabel = Label(s, "Keep up at least")
    s.min = Slider(s, "minShow", Whole(function(v) Set("minShow", v) end))
    s.timing = Note(s)
    s.motion = Note(s)

    s.parts = { s.presetLabel, s.preset, s.move, s.sizeLabel, s.size, s.opacityLabel, s.opacity, s.textSizeLabel, s.textSize,
        s.placeLabel, s.textPlace, s.more, s.keep, s.keep.label, s.widthLabel, s.width, s.heightLabel, s.height, s.fontLabel, s.font,
        s.outlineLabel, s.outline, s.colorLabel, s.color, s.panelLabel, s.panel, s.pointLabel, s.point, s.offsetLabel, s.x, s.y,
        s.strataLabel, s.strata, s.fade, s.fade.label, s.pulse, s.pulse.label, s.delayLabel, s.delay, s.minLabel, s.min, s.timing, s.motion }

    function s:Layout(v, y)
        HideAll(self.parts)
        local d, p = v.display, v.place
        local m = d.mode
        local visual = m ~= "text"
        local words = m == "text" or m == "artworkText" or m == "iconText"
        local h = Top(self)
        local presetLabel
        for _, pr in ipairs(RM().PRESETS) do if pr[1] == p.preset then presetLabel = pr[2] end end
        self.preset:SetValue(p.preset, presetLabel)
        h = Line(self, self.presetLabel, self.preset, h, 0)
        local moving = D.Positioning() and D.PreviewId() == v.id
        self.move.text:SetText(moving and "Done" or "Move on screen")
        Put(self.move, self, CTRL_X + 232, h)
        h = h + ROW
        if visual and d.keepAspect then
            self.size:SetValue(d.size)
            h = Line(self, self.sizeLabel, self.size, h)
        end
        self.opacity:SetValue(d.opacity)
        h = Line(self, self.opacityLabel, self.opacity, h)
        if words then
            self.textSize:SetValue(d.textSize)
            h = Line(self, self.textSizeLabel, self.textSize, h)
        end
        if visual and words then
            self.textPlace:SetValue(d.textPlace, LabelOf(RM().CHOICES.textPlace, d.textPlace))
            h = Line(self, self.placeLabel, self.textPlace, h)
        end

        local open = Ed.moreOpen and true or false
        for _, t in ipairs(self.more.down) do t:SetShown(not open) end
        for _, t in ipairs(self.more.up) do t:SetShown(open) end
        self.more.text:SetText(open and "Fewer options" or "More placement and appearance options")
        Put(self.more, self, LABEL_X - 4, h + 2)
        h = h + 28
        if open then
            if visual then
                self.keep:SetChecked(d.keepAspect)
                Put(self.keep, self, CTRL_X, h + 2)
                self.keep.label:Show()
                h = h + ROW
                if not d.keepAspect then
                    self.width:SetValue(d.width)
                    h = Line(self, self.widthLabel, self.width, h)
                    self.height:SetValue(d.height)
                    h = Line(self, self.heightLabel, self.height, h)
                end
            end
            if words then
                local fontLabel = d.font == "default" and "Game font (default)" or d.font
                self.font:SetValue(d.font, fontLabel)
                h = Line(self, self.fontLabel, self.font, h)
                self.outline:SetValue(d.outline, LabelOf(RM().CHOICES.outline, d.outline))
                h = Line(self, self.outlineLabel, self.outline, h)
                self.color:SetValue(d.textColor)
                h = Line(self, self.colorLabel, self.color, h)
            end
            self.panel:SetValue(d.panel, LabelOf(RM().CHOICES.panel, d.panel))
            h = Line(self, self.panelLabel, self.panel, h)
            self.point:SetValue(p.point, LabelOf(RM().POINTS, p.point))
            h = Line(self, self.pointLabel, self.point, h)
            Put(self.offsetLabel, self, LABEL_X, h + 4)
            if not self.x:HasFocus() then self.x:SetText(tostring(p.x)) end
            if not self.y:HasFocus() then self.y:SetText(tostring(p.y)) end
            Put(self.x, self, CTRL_X, h)
            Put(self.y, self, CTRL_X + 80, h)
            h = h + ROW
            self.strata:SetValue(d.strata, LabelOf(RM().CHOICES.strata, d.strata))
            h = Line(self, self.strataLabel, self.strata, h)
            self.fade:SetChecked(d.fade)
            Put(self.fade, self, CTRL_X, h + 2); self.fade.label:Show()
            h = h + ROW
            self.pulse:SetChecked(d.pulse)
            Put(self.pulse, self, CTRL_X, h + 2); self.pulse.label:Show()
            h = h + ROW
            if R:Enabled("arrivalReducedMotion") then
                h = h + Text(self.motion, "Reduced motion is on (Notifications), so it neither fades nor pulses.", "quiet", CTRL_X, h, self) + 6
            end
            self.delay:SetValue(d.delay)
            h = Line(self, self.delayLabel, self.delay, h)
            self.min:SetValue(d.minShow)
            h = Line(self, self.minLabel, self.min, h)
            h = h + Text(self.timing, ("In seconds. Waiting %d: its conditions must stay true that long before it shows; if they stop first, nothing shows. Keeping it up %d: once shown it stays at least that long, unless you turn it off, delete it, or it stops applying to this character."):format(d.delay, d.minShow), "quiet", LABEL_X, h, self) + 6
        end
        h = h + 8
        self:SetHeight(h)
        Put(self, parent, 0, y)
        return h
    end
    return s
end

---------------------------------------------------------------------------
-- Preview: drawn here by the reminder's own layout code, or shown where it sits
---------------------------------------------------------------------------
local BOX_H = 150

local function PreviewSection(parent, env)
    local s = Section(parent, "reminderPreview", "Preview", "How it looks, drawn here, or on your screen where it sits. A preview shows it whatever its conditions say, and changes nothing.")
    local D = R.ReminderDisplay
    s.box = CreateFrame("Frame", nil, s, "BackdropTemplate")
    s.box:SetSize(W - PAD * 2, BOX_H)
    Wg().Well(s.box)
    s.surface = D.NewSurface(s.box)
    s.surface:SetPoint("CENTER", s.box, "CENTER", 0, 0)
    s.tag = Wg().Tag(s.box, "PREVIEW")
    s.tag:SetPoint("TOPLEFT", 6, -6)
    s.caption = Note(s)
    s.show = Wg().Button(s, "Show on screen", 150, "secondary", function()
        local v = env.view()
        if not v then return end
        if D.PreviewId() == v.id then D.PreviewStop() env.Changed() return end
        local ok = D.PreviewStart(v, false)
        if not ok then env.Say("The preview waits until you are out of combat.", "warn") end
        env.Changed()
    end)
    R.Interact.Tip(s.show, "Show on screen", "Shows it where it sits, marked Preview, whatever its conditions say. Nothing about your equipment or its rules changes. It ends when you close these settings, enter combat, turn Reminders off or delete it.")
    s.state = Note(s, W - CTRL_X - 170)

    function s:Layout(v, y)
        local h = Top(self)
        Put(self.box, self, PAD, h)
        local _, _, scale = D.DrawSurface(self.surface, v, W - PAD * 2 - 24, BOX_H - 24)
        self.surface:Show()
        h = h + BOX_H + 8
        local words = scale < 1 and ("Shown here at %d%% of its size, to fit the box."):format(math.floor(scale * 100)) or "Shown here at its own size."
        if not v.valid then words = words .. " It can't show in the world until what is listed above is fixed." end
        h = h + Text(self.caption, words, "quiet", PAD, h, self) + 8
        local on = D.PreviewId() == v.id
        self.show.text:SetText(on and "Hide preview" or "Show on screen")
        Put(self.show, self, PAD, h)
        local stateText = on and (D.Positioning() and "On screen now, with a handle to drag." or "On screen now, marked Preview.") or ""
        Text(self.state, stateText, "ok", PAD + 162, h + 4, self)
        h = h + ROW + 6
        self:SetHeight(h)
        Put(self, parent, 0, y)
        return h
    end
    return s
end

---------------------------------------------------------------------------
-- Test: what it sees right now, and the same decision for situations you pick
---------------------------------------------------------------------------
local function ResultTone(result)
    if result == "match" then return "ok" end
    if result == "invalid" then return "warn" end
    if result == "unknown" then return "quiet" end
    return nil
end

local function StatusTone(status)
    if status == "showing" or status == "holding" then return "ok" end
    if status == "invalid" then return "warn" end
    return "quiet"
end

local function ConditionLine(c, observedWord)
    local E = R.ReminderEval
    local text = ("%s  -  %s  -  %s: %s"):format(c.summary, E.RESULT_WORDS[c.result] or c.result, observedWord, c.observed ~= "" and c.observed or "nothing")
    if c.reason then text = text .. ". " .. c.reason end
    return text
end

local function TestSection(parent, env)
    local s = Section(parent, "reminderTest", "Test", "What it decides right now and why, and the same decision for situations you choose, without changing your equipment.")
    s.liveHead = Wg().Text(s, "body")
    s.liveHead:SetText("Right now")
    s.liveResult = Note(s)
    s.live = {}
    s.simHead = Wg().Text(s, "body")
    s.simHead:SetText("Try a situation")
    s.simTag = Wg().Tag(s, "SIMULATED")
    s.simIntro = Note(s)
    s.picks, s.pickLabels, s.sim = {}, {}, {}
    for i = 1, RM().MAX_CONDITIONS do
        s.live[i] = Note(s, W - PAD * 2 - 10)
        s.sim[i] = Note(s, W - PAD * 2 - 10)
        s.pickLabels[i] = Note(s, 300)
        s.pickLabels[i]:SetWordWrap(false)
        s.picks[i] = Dropdown(s, 240, function()
            local v = env.view()
            local entry = v and v.conditions[i]
            local out = {}
            for j, sc in ipairs(entry and R.ReminderEval.Scenarios(entry) or {}) do out[j] = { value = sc.key, label = sc.label } end
            return out
        end, function(value)
            local id = env.id()
            Ed.picks = Ed.picks or {}
            Ed.picks[id] = Ed.picks[id] or {}
            Ed.picks[id][i] = value
            env.Changed()
        end)
    end
    s.simResult = Note(s)
    s.manualHead = Wg().Text(s, "body")
    s.manualHead:SetText("Check it in the game")
    s.manual = Note(s)
    local parts = { s.liveHead, s.liveResult, s.simHead, s.simTag, s.simIntro, s.simResult, s.manualHead, s.manual }
    for i = 1, RM().MAX_CONDITIONS do
        parts[#parts + 1] = s.live[i]; parts[#parts + 1] = s.sim[i]; parts[#parts + 1] = s.picks[i]; parts[#parts + 1] = s.pickLabels[i]
    end

    function s:Layout(v, y)
        HideAll(parts)
        local E, CT = R.ReminderEval, R.ReminderController
        local h = Top(self)
        Put(self.liveHead, self, PAD, h)
        h = h + 18
        local out, status = CT.Inspect(v.id)
        for i, c in ipairs(out and out.conditions or {}) do
            if self.live[i] then h = h + Text(self.live[i], ConditionLine(c, "Observed"), ResultTone(c.result), PAD + 10, h, self) + 4 end
        end
        local words = E.STATUS_WORDS[status] or tostring(status)
        local why = out and (out.reason or out.explain) or ""
        if status == "disabled" then why = "Turn it on to use it. " .. (out and out.explain or "")
        elseif status == "off" then why = "Turn Reminders on (above) to use it."
        elseif status == "world" then why = "It decides once you are in the world." end
        h = h + 2 + Text(self.liveResult, ("Result: %s. %s"):format(words, why), StatusTone(status), PAD, h + 2, self) + 12

        Put(self.simHead, self, PAD, h)
        Put(self.simTag, self, PAD + (self.simHead:GetStringWidth() or 100) + 10, h)
        h = h + 20
        if #v.conditions == 0 then
            h = h + Text(self.simIntro, "Add a condition first; then you can try situations here.", "quiet", PAD, h, self) + 8
        else
            h = h + Text(self.simIntro, "Choose what each condition would see. The decision below is made by the same rules as the live one, from these made-up facts only: your equipment, the live result and your settings are not touched.", "quiet", PAD, h, self) + 8
            local picks = Ed.picks and Ed.picks[v.id] or {}
            for i, entry in ipairs(v.conditions) do
                if not self.picks[i] then break end
                local list = E.Scenarios(entry)
                local chosen = list[1]
                for _, sc in ipairs(list) do if sc.key == picks[i] then chosen = sc end end
                Text(self.pickLabels[i], ("%d. %s"):format(i, E.Summary(entry)), nil, PAD + 10, h + 4, self)
                if chosen then
                    self.picks[i]:SetValue(chosen.key, chosen.label)
                    Put(self.picks[i], self, W - PAD - 240, h)
                end
                h = h + ROW
            end
            local sim = E.Simulate(v, picks)
            for i, c in ipairs(sim.conditions) do
                if self.sim[i] then h = h + Text(self.sim[i], ConditionLine(c, "Simulated"), ResultTone(c.result), PAD + 10, h, self) + 4 end
            end
            local simWords = E.STATUS_WORDS[sim.status] or sim.status
            h = h + 2 + Text(self.simResult, ("Simulated result: %s. %s"):format(simWords, sim.reason or sim.explain), StatusTone(sim.status), PAD, h + 2, self) + 12
        end

        Put(self.manualHead, self, PAD, h)
        h = h + 18
        h = h + Text(self.manual, "Turn it on, then take off (or put on) the equipment it is about: within a moment it appears or goes, and Right now says why. Your gear is never changed by TwichUI.", "quiet", PAD, h, self) + 10
        self:SetHeight(h)
        Put(self, parent, 0, y)
        return h
    end
    return s
end

function Ed.Build(parent, env)
    return {
        ShowSection(parent, env),
        WhenSection(parent, env),
        PlacementSection(parent, env),
        PreviewSection(parent, env),
        TestSection(parent, env),
    }
end
