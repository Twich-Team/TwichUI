-- TwichUI settings: Magic Inventory (inventory/). A feature card with the switch, then a frame of this window's own:
--   * your rules, in priority order: on/off, name, what it matches, where it goes, what it keeps, and Up, Down, Edit,
--     Duplicate, Delete; New rule (from a template) and Preview (the review window, from your bags as they are now);
--   * the destinations: each named place's recipient or guild bank tab ON THIS CHARACTER (another character chooses
--     its own, unless you choose to use a recipient on all your characters);
--   * the Never transfer list;
--   * the rule editor, in four short steps: Items, Destination, Exceptions and keep, Review.
-- Every change goes through inventory/Rules.lua, which checks it; nothing here moves an item, and choosing items from
-- your bags only names the kind of item (inventory/Picker.lua). Built the first time the page is shown; its controls
-- are kept by name and reused on every redraw, so redrawing never makes a second copy of anything.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.MagicInventoryPage = P

local W = 644
local PAD = 6
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local AMBER = { 0.93, 0.72, 0.38 }

local f, built
local height = 400
local queued, relayoutQueued = false, false
local pool = {}               -- [key] = a control, made once
local touched = {}            -- [key] = true for controls used by this draw
local editing                 -- the rule being edited (a copy; saved only by Save), or nil for the list
local step = 1
local turnOn = false          -- the editor's "Turn this rule on" choice
local said, saidTone          -- a sentence under the list or the editor: what just happened, or why it didn't
local newDestName = {}        -- [kind] = text typed for a new destination

local function MI() return R.MagicInventory end
local function Wg() return R.SettingsWidgets end

---------------------------------------------------------------------------
-- Controls kept by name
---------------------------------------------------------------------------
local function Get(key, make)
    local c = pool[key]
    if not c then
        c = make()
        pool[key] = c
    end
    touched[key] = true
    c:Show()
    return c
end

local function Text(key, kind)
    return Get(key, function()
        local t = Wg().Text(f, kind or "body")
        t:SetJustifyH("LEFT")
        t:SetWordWrap(true)
        return t
    end)
end

local function Button(key, label, w, kind, onClick)
    local b = Get(key, function()
        local made = Wg().Button(f, label, w, kind, function(self) if self.onClick then self.onClick() end end)
        return made
    end)
    b.text:SetText(label)
    b:SetWidth(w)
    b.onClick = onClick
    b:SetEnabled(onClick ~= nil)
    return b
end

local function Check(key, onToggle)
    local c = Get(key, function() return Wg().Checkbox(f, function(v) local self = pool[key]; if self.onToggle then self.onToggle(v) end end) end)
    c.onToggle = onToggle
    return c
end

local function Edit(key, w)
    return Get(key, function()
        local e = Wg().EditBox(f, w, 22)
        e:SetMaxLetters(64)
        return e
    end)
end

local function Icon(key)
    return Get(key, function()
        local b = CreateFrame("Button", nil, f, "BackdropTemplate")
        b:SetSize(26, 26)
        Wg().Surface(b, Wg().pal.well, 1, Wg().pal.control, 0.9)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        b:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
        b:SetScript("OnEnter", function(self)
            if not self.itemID then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) end
            if self.hint then GameTooltip:AddLine(self.hint, 0.93, 0.72, 0.38, true) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end)
end

local function At(c, x, y) c:ClearAllPoints(); c:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y) end
local function Wide(t, x, y, w) At(t, x, y); t:SetWidth(w or (W - x - PAD)) end
local function Tone(t, tone)
    local pal = Wg().pal
    Wg().Color(t, tone == "warn" and AMBER or (tone == "dim" and pal.textDim or (tone == "head" and pal.bronzeText or (tone == "quiet" and pal.stone or pal.text))))
end
local function H(t) return math.max(14, t:GetStringHeight() or 14) end

---------------------------------------------------------------------------
-- Redrawing: many changes are one redraw; a change of height asks the window to lay the page out again
---------------------------------------------------------------------------
function P.QueueRefresh()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        local ok, err = pcall(P.Refresh)
        if not ok then R.Fault("magic inventory settings", err) end
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

local function Say(text, tone) said, saidTone = text, tone; P.QueueRefresh() end
P.Say = Say

---------------------------------------------------------------------------
-- Words for a rule
---------------------------------------------------------------------------
local EQUIP_TEXT = { equipment = "equipment", other = "not equipment" }
local BIND_TEXT = { boe = "binds when equipped (not yet bound)", nobind = "doesn't bind" }

function P.ItemsText(rule)
    local mi = MI()
    local parts = {}
    local cats = {}
    for _, key in ipairs(rule.cats) do cats[#cats + 1] = mi.CategoryName(key) or "a category this client doesn't name" end
    if #cats > 0 then parts[#parts + 1] = table.concat(cats, " or ") end
    local q = {}
    for _, n in ipairs(mi.QUALITY_ORDER) do if rule.qualities[n] then q[#q + 1] = mi.QualityName(n) end end
    if #q > 0 then parts[#parts + 1] = table.concat(q, " or ") .. " quality" end
    if EQUIP_TEXT[rule.equip] then parts[#parts + 1] = EQUIP_TEXT[rule.equip] end
    if BIND_TEXT[rule.bind] then parts[#parts + 1] = BIND_TEXT[rule.bind] end
    local text = table.concat(parts, " + ")
    local inc = 0
    for _ in pairs(rule.include) do inc = inc + 1 end
    if inc > 0 then text = text .. (text ~= "" and ", and " or "") .. ("%d listed %s"):format(inc, inc == 1 and "item" or "items") end
    local exc = 0
    for _ in pairs(rule.exclude) do exc = exc + 1 end
    if exc > 0 then text = text .. ("; never %d listed %s"):format(exc, exc == 1 and "item" or "items") end
    return text ~= "" and text or "Nothing chosen yet"
end

function P.DestText(rule)
    local mi = MI()
    local kind = mi.KIND_LABEL[rule.kind]
    if not mi.NEEDS_DEST[rule.kind] then return kind end
    local d = rule.dest and mi.Dest(rule.dest)
    if not d then return kind .. " \226\134\146 (choose one)", "warn" end
    local where = mi.Resolve(d.id)
    if not where then
        return ("%s \226\134\146 %s (choose %s on this character)"):format(kind, d.label, rule.kind == "mail" and "the recipient" or "the tab"), "warn"
    end
    if rule.kind == "mail" then return ("%s \226\134\146 %s%s"):format(kind, where.recipient, where.shared and " (all your characters)" or "") end
    return ("%s \226\134\146 <%s>, tab %d \"%s\""):format(kind, where.guild, where.tab, where.tabName or "?")
end

function P.KeepText(rule)
    if rule.kind == "never" then return "Never moved by any rule" end
    if rule.keep and rule.keep > 0 then return ("%d of each matching item"):format(rule.keep) end
    return rule.kind == "keep" and "Choose how many" or "None"
end

-- The whole rule as one plain sentence (the editor's Review step).
function P.Sentence(rule)
    local items = P.ItemsText(rule)
    if rule.kind == "never" then return ("Never move: %s. No rule, list or template moves these."):format(items) end
    if rule.kind == "keep" then return ("Keep in your bags: %s, %s. Other rules move only what is above that."):format(P.KeepText(rule):lower(), items) end
    local dest = P.DestText(rule)
    local keep = rule.keep > 0 and (" Keep %d of each in your bags."):format(rule.keep) or ""
    return ("%s: %s.%s It only moves when you open the %s, review it and press the action yourself."):format(dest, items, keep,
        rule.kind == "mail" and "mailbox" or (rule.kind == "bank" and "bank" or "guild bank"))
        .. (rule.kind == "mail" and " Whether a player can receive these, or who plays that character, isn't something TwichUI can check." or "")
        .. (rule.bind == "boe" and rule.kind == "mail" and " Whether an item can be disenchanted isn't checked." or "")
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local function TemplateChoices()
    local out = {}
    for _, t in ipairs(MI().TEMPLATES) do
        local rule = MI().FromTemplate(t.key)
        out[#out + 1] = { value = t.key, label = rule and rule.name or t.key, tooltip = t.about }
    end
    return out
end

local function StartEdit(rule)
    editing = rule
    step = 1
    turnOn = rule.enabled == true
    said = nil
    P.QueueRefresh()
    QueueRelayout()
end

local function NewFromTemplate(key)
    local mi = MI()
    local rule, destLabel = mi.FromTemplate(key)
    if not rule then return end
    if destLabel then
        local id, why = mi.DestNamed(rule.kind, destLabel)
        if not id then Say(why, "warn") return end
        rule.dest = id
    end
    StartEdit(rule)
end

local function ItemStrip(prefix, set, x, y, hint, onRemove)
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    table.sort(ids)
    local perRow = math.floor((W - x - PAD) / 30)
    for i, id in ipairs(ids) do
        local b = Icon(prefix .. i)
        local facts = MI().ItemFacts(id)
        b.tex:SetTexture(facts and facts.icon or QUESTION)
        b.itemID, b.hint = id, hint
        b.onClick = function() onRemove(id) end
        At(b, x + ((i - 1) % perRow) * 30, y + math.floor((i - 1) / perRow) * 30)
    end
    return #ids == 0 and 0 or (math.ceil(#ids / perRow) * 30)
end

local function AddById(box, onAdd)
    local id = MI().ParseItem(box:GetText() or "")
    if not id then Say("That isn't an item: paste its link or type its item ID.", "warn") return end
    box:SetText("")
    box:ClearFocus()
    onAdd(id)
end

local function DrawNever(y)
    local mi = MI()
    local t = Text("neverHead", "heading")
    Wide(t, PAD, y)
    t:SetText("Never transfer")
    Tone(t, "head")
    y = y + 18
    local d = Text("neverText", "small")
    Wide(d, PAD, y)
    d:SetText("Items on this list are never moved by any rule, even one that lists them. Kept for your whole account. Click an item to take it off.")
    Tone(d, "dim")
    y = y + H(d) + 6
    local set = {}
    for _, id in ipairs(mi.NeverList()) do set[id] = true end
    local h = ItemStrip("never", set, PAD, y, "Click to take it off the Never transfer list.", function(id) mi.SetNever(id, false) end)
    y = y + h + (h > 0 and 6 or 0)
    Button("neverPick", "Choose from bags", 140, "secondary", function()
        mi.Picker.Open({ purpose = "Never transfer: these kinds of item are never moved by any rule.", selected = set,
            onDone = function(chosen)
                for id in pairs(set) do if not chosen[id] then mi.SetNever(id, false) end end
                for id in pairs(chosen) do
                    local ok, why = mi.SetNever(id, true)
                    if not ok then Say(why, "warn") break end
                end
            end })
    end)
    At(pool.neverPick, PAD, y)
    local box = Edit("neverId", 160)
    At(box, PAD + 150, y + 1)
    box:SetScript("OnEnterPressed", function(self) AddById(self, function(id) local ok, why = mi.SetNever(id, true); if not ok then Say(why, "warn") end end) end)
    Button("neverAdd", "Add by ID or link", 140, "secondary", function()
        AddById(pool.neverId, function(id) local ok, why = mi.SetNever(id, true); if not ok then Say(why, "warn") end end)
    end)
    At(pool.neverAdd, PAD + 320, y)
    return y + 34
end

local function DrawDests(y)
    local mi = MI()
    local t = Text("destHead", "heading")
    Wide(t, PAD, y)
    t:SetText("Destinations on this character")
    Tone(t, "head")
    y = y + 18
    local d = Text("destText", "small")
    Wide(d, PAD, y)
    d:SetText("A rule sends to a named place. Who or which tab that is, is chosen here for this character only, so another character never mails to your choice unless you tick \"All my characters\". TwichUI checks a name's form, not whether the character exists or who plays it.")
    Tone(d, "dim")
    y = y + H(d) + 8
    local dests = mi.Dests()
    if #dests == 0 then
        local none = Text("destNone", "small")
        Wide(none, PAD, y)
        none:SetText("None yet: a mail or guild bank rule makes one.")
        Tone(none, "quiet")
        y = y + 20
    end
    for i, dest in ipairs(dests) do
        local key = "dest" .. i
        local name = Text(key .. "name", "body")
        Wide(name, PAD, y + 4, 150)
        name:SetText(dest.label)
        local where = mi.Resolve(dest.id)
        local value = Text(key .. "value", "small")
        Wide(value, PAD + 156, y + 5, 210)
        if dest.kind == "mail" then
            value:SetText(where and ("Mail to: |cffffffff" .. where.recipient .. "|r" .. (where.shared and " (all your characters)" or "")) or "No recipient on this character")
            Tone(value, where and "dim" or "warn")
            local box = Edit(key .. "box", 130)
            At(box, PAD + 370, y + 1)
            if not box:HasFocus() then box:SetText(where and where.recipient or "") end
            local all = Check(key .. "all", function(v) pool[key .. "all"].want = v; pool[key .. "all"]:SetChecked(v) end)
            At(all, PAD + 506, y + 3)
            if all.want == nil then all.want = where and where.shared or false end
            all:SetChecked(all.want)
            local allText = Text(key .. "allText", "small")
            Wide(allText, PAD + 528, y + 5, 90)
            allText:SetText("All my characters")
            Tone(allText, "dim")
            local function Set()
                local text = pool[key .. "box"]:GetText() or ""
                local ok, why
                if text:match("^%s*$") then ok, why = mi.SetRecipient(dest.id, nil)
                else ok, why = mi.SetRecipient(dest.id, text, pool[key .. "all"].want) end
                pool[key .. "box"]:ClearFocus()
                if ok then
                    Say(why and ("\"%s\" now mails to %s%s."):format(dest.label, why, pool[key .. "all"].want and " on all your characters" or " on this character") or ("\"%s\" has no recipient now."):format(dest.label))
                else Say(why, "warn") end
                pool[key .. "all"].want = nil
            end
            box:SetScript("OnEnterPressed", Set)
            y = y + 28
            Button(key .. "set", "Save recipient", 120, "secondary", Set)
            At(pool[key .. "set"], PAD + 370, y)
            R.Interact.Tip(pool[key .. "set"], "Save recipient", "Saves exactly this name for this destination. An empty box clears it. Mail always shows the recipient before anything is sent.")
        else
            value:SetText(where and ("<%s>, tab %d \"%s\""):format(where.guild, where.tab, where.tabName or "?") or "No guild bank tab on this character")
            Tone(value, where and "dim" or "warn")
            local open = mi.Run.IsOpen("guild")
            local b = Button(key .. "use", "Use the tab shown now", 170, "secondary", open and function()
                local guild = MI().Plain((GetGuildInfo("player")))
                local tab = MI().Plain(GetCurrentGuildBankTab and GetCurrentGuildBankTab())
                local tabName = tab and MI().Plain((GetGuildBankTabInfo(tab)))
                local ok, why = mi.SetGuildTab(dest.id, guild, tab, tabName)
                if ok then Say(("\"%s\" is now <%s>, tab %d \"%s\" on this character."):format(dest.label, guild, tab, tabName or "?"))
                else Say(why, "warn") end
            end or nil)
            At(b, PAD + 370, y)
            R.Interact.Tip(b, "Use the tab shown now", open and "Saves the guild and the tab the guild bank shows now." or "Open the guild bank on the tab you want, then press this. (Whether guild vaults exist on your realm isn't known to TwichUI.)")
            y = y + 28
        end
        Button(key .. "rename", "Rename", 80, "secondary", function()
            local text = pool[key .. "renameBox"] and pool[key .. "renameBox"]:GetText()
            local ok, why = mi.RenameDest(dest.id, text)
            if not ok then Say(why, "warn") end
        end)
        local rb = Edit(key .. "renameBox", 140)
        At(rb, PAD, y + 1)
        if not rb:HasFocus() then rb:SetText(dest.label) end
        At(pool[key .. "rename"], PAD + 146, y)
        Button(key .. "clear", "Clear here", 90, "secondary", where and function()
            if dest.kind == "mail" then mi.SetRecipient(dest.id, nil) else mi.SetGuildTab(dest.id, nil) end
            Say(("\"%s\" has nothing chosen on this character now."):format(dest.label))
        end or nil)
        At(pool[key .. "clear"], PAD + 232, y)
        Button(key .. "delete", "Remove", 80, "danger", function()
            R.Interact.Confirm("TWICHUI_MI_DEST_DELETE", ("Remove the destination \"%s\"?\n\nRules that send to it stay in your list, turned off, until you choose another destination for them. Other characters' choices for it are left in your saved data."):format(dest.label),
                function() mi.DeleteDest(dest.id) end, { accept = "Remove" })
        end)
        At(pool[key .. "delete"], W - PAD - 80, y)
        y = y + 36
    end
    return y
end

local function DrawList(y)
    local mi = MI()
    local rules = mi.Rules()
    local head = Text("listHead", "heading")
    Wide(head, PAD, y)
    head:SetText("Your rules")
    Tone(head, "head")
    local new = Get("newRule", function()
        local dd = Wg().Dropdown(f, 200, function(v) NewFromTemplate(v) end)
        return dd
    end)
    new:SetChoices(TemplateChoices)
    new:SetValue(nil, "New rule from a template...")
    At(new, W - PAD - 200 - 108, y - 4)
    Button("preview", "Preview", 100, "secondary", function() mi.Window.Show(true) end)
    At(pool.preview, W - PAD - 100, y - 4)
    R.Interact.Tip(pool.preview, "Preview", "Opens the review with what your rules would move from your bags now, and what stays and why. Nothing moves from the preview.")
    y = y + 26
    local d = Text("listText", "small")
    Wide(d, PAD, y)
    d:SetText("The first rule in the list that matches an item decides where it goes; the rules below it don't move that item. Keep amounts from every matching rule count. Nothing moves until you open a mailbox, bank or guild bank, review it and press the action yourself.")
    Tone(d, "dim")
    y = y + H(d) + 8
    if #rules == 0 then
        local none = Text("listNone", "body")
        Wide(none, PAD, y)
        none:SetText("No rules yet. Start from a template above: \"Cloth to bank alt\", \"Herbs to bank\", ... Each starts turned off.")
        Tone(none, "quiet")
        y = y + 28
    end
    for i, rule in ipairs(rules) do
        local key = "rule" .. i
        local box = Check(key .. "on", function(v)
            local ok, why = mi.SetRuleEnabled(rule.id, v)
            if not ok then Say(why, "warn") end
        end)
        At(box, PAD, y + 2)
        box:SetChecked(rule.enabled)
        local name = Text(key .. "name", "body")
        Wide(name, PAD + 28, y + 3, 330)
        name:SetText(("%d.  %s"):format(i, rule.name))
        local lines = Text(key .. "lines", "small")
        Wide(lines, PAD + 28, y + 21, 360)
        local dest, tone = P.DestText(rule)
        local problem = select(2, mi.Problem(rule, false))
        lines:SetText(("Items: %s\nDestination: %s\nKeep: %s%s"):format(P.ItemsText(rule), dest, P.KeepText(rule),
            problem and ("\n|cffedb861" .. problem .. "|r") or ""))
        Tone(lines, "dim")
        local _ = tone
        local bx = W - PAD - 238
        Button(key .. "up", "Up", 44, "secondary", i > 1 and function() mi.MoveRule(rule.id, -1) end or nil)
        At(pool[key .. "up"], bx, y)
        Button(key .. "down", "Down", 52, "secondary", i < #rules and function() mi.MoveRule(rule.id, 1) end or nil)
        At(pool[key .. "down"], bx + 48, y)
        Button(key .. "edit", "Edit", 60, "secondary", function() StartEdit(rule) end)
        At(pool[key .. "edit"], bx + 104, y)
        Button(key .. "dup", "Duplicate", 70, "secondary", function()
            local id, why = mi.DuplicateRule(rule.id)
            if not id then Say(why, "warn") end
        end)
        At(pool[key .. "dup"], bx + 168, y)
        Button(key .. "del", "Delete", 70, "danger", function()
            R.Interact.Confirm("TWICHUI_MI_RULE_DELETE", ("Delete the rule \"%s\"?\n\nOnly the rule goes: nothing in your bags, bank or mail changes."):format(rule.name),
                function() mi.DeleteRule(rule.id) end, { accept = "Delete" })
        end)
        At(pool[key .. "del"], bx + 168, y + 28)
        y = y + math.max(66, 24 + H(lines)) + 8
    end
    return y
end

---------------------------------------------------------------------------
-- The editor
---------------------------------------------------------------------------
local STEPS = { "1  Items", "2  Destination", "3  Exceptions and keep", "4  Review" }

local function Radio(key, x, y, label, on, onPick, w)
    local c = Check(key, function() onPick() end)
    c:SetChecked(on)
    At(c, x, y)
    local t = Text(key .. "t", "body")
    Wide(t, x + 24, y + 2, w or 200)
    t:SetText(label)
    Tone(t, on and nil or "dim")
    return c
end

local function DrawItemsStep(y)
    local mi, r = MI(), editing
    local t = Text("e1cats", "heading")
    Wide(t, PAD, y)
    t:SetText("Categories (as the game files items)")
    Tone(t, "head")
    y = y + 20
    local cats = mi.Categories()
    local chosen = {}
    for _, k in ipairs(r.cats) do chosen[k] = true end
    local colW = math.floor((W - PAD * 2) / 3)
    for i, c in ipairs(cats) do
        local x = PAD + ((i - 1) % 3) * colW
        local yy = y + math.floor((i - 1) / 3) * 24
        Radio("e1cat" .. i, x, yy, c.label .. (c.group ~= c.label and ("  |cff8a857c" .. c.group .. "|r") or ""), chosen[c.key], function()
            if chosen[c.key] then
                for j = #r.cats, 1, -1 do if r.cats[j] == c.key then table.remove(r.cats, j) end end
            elseif #r.cats < mi.MAX_CATS then
                r.cats[#r.cats + 1] = c.key
            end
            P.QueueRefresh()
        end, colW - 30)
    end
    y = y + math.ceil(#cats / 3) * 24 + 8
    t = Text("e1q", "heading")
    Wide(t, PAD, y)
    t:SetText("Quality (none ticked: any)")
    Tone(t, "head")
    y = y + 20
    for i, q in ipairs(mi.QUALITY_ORDER) do
        Radio("e1q" .. i, PAD + (i - 1) * 120, y, mi.QualityName(q), r.qualities[q] == true, function()
            r.qualities[q] = (not r.qualities[q]) or nil
            P.QueueRefresh()
        end, 90)
    end
    y = y + 30
    t = Text("e1eq", "heading")
    Wide(t, PAD, y)
    t:SetText("Equipment")
    Tone(t, "head")
    y = y + 20
    for i, o in ipairs({ { "any", "Any item" }, { "equipment", "Equipment only" }, { "other", "Not equipment" } }) do
        Radio("e1eq" .. i, PAD + (i - 1) * 180, y, o[2], r.equip == o[1], function() r.equip = o[1]; P.QueueRefresh() end, 150)
    end
    y = y + 30
    t = Text("e1b", "heading")
    Wide(t, PAD, y)
    t:SetText("Binding")
    Tone(t, "head")
    y = y + 20
    for i, o in ipairs({ { "any", "Any" }, { "boe", "Binds when equipped, not yet bound" }, { "nobind", "Doesn't bind" } }) do
        Radio("e1b" .. i, PAD + (i - 1) * 200, y, o[2], r.bind == o[1], function() r.bind = o[1]; P.QueueRefresh() end, 175)
    end
    y = y + 34
    t = Text("e1inc", "heading")
    Wide(t, PAD, y)
    t:SetText("Also include these items")
    Tone(t, "head")
    y = y + 18
    local d = Text("e1incText", "small")
    Wide(d, PAD, y)
    d:SetText("Matched even when they aren't in the categories above. They are still never moved when they are protected (quest items, soulbound for mail, the Never transfer list...). Click one to take it off.")
    Tone(d, "dim")
    y = y + H(d) + 6
    local h = ItemStrip("e1incI", r.include, PAD, y, "Click to take it off this rule's list.", function(id) r.include[id] = nil; P.QueueRefresh() end)
    y = y + h + (h > 0 and 6 or 0)
    Button("e1incPick", "Choose from bags", 140, "secondary", function()
        mi.Picker.Open({ purpose = ("Also include in \"%s\": these kinds of item match the rule."):format(r.name), selected = r.include,
            onDone = function(set) r.include = set; P.QueueRefresh() end })
    end)
    At(pool.e1incPick, PAD, y)
    local box = Edit("e1incId", 160)
    At(box, PAD + 150, y + 1)
    local function Add(id) r.include[id] = true; r.exclude[id] = nil; P.QueueRefresh() end
    box:SetScript("OnEnterPressed", function(self) AddById(self, Add) end)
    Button("e1incAdd", "Add by ID or link", 140, "secondary", function() AddById(pool.e1incId, Add) end)
    At(pool.e1incAdd, PAD + 320, y)
    return y + 34
end

local function DrawDestStep(y)
    local mi, r = MI(), editing
    local t = Text("e2head", "heading")
    Wide(t, PAD, y)
    t:SetText("What happens to matching items")
    Tone(t, "head")
    y = y + 22
    local ABOUT = {
        mail = "Mailed to a recipient you name, at a mailbox, one recipient per mail.",
        bank = "Deposited in your own bank (never taken out, and no bank space is bought).",
        guild = "Deposited in a guild bank tab you choose (never taken out). Not yet checked on Forever's realms.",
        keep = "Kept in your bags: other rules move only what is above the amount you set.",
        never = "Never moved by any rule.",
    }
    for _, kind in ipairs(mi.KIND_ORDER) do
        Radio("e2k" .. kind, PAD, y, mi.KIND_LABEL[kind], r.kind == kind, function()
            r.kind = kind
            if not mi.NEEDS_DEST[kind] then r.dest = nil
            elseif r.dest then local d = mi.Dest(r.dest); if not d or d.kind ~= kind then r.dest = nil end end
            P.QueueRefresh()
        end, 170)
        local a = Text("e2a" .. kind, "small")
        Wide(a, PAD + 200, y + 2, W - PAD * 2 - 200)
        a:SetText(ABOUT[kind])
        Tone(a, "dim")
        y = y + math.max(24, H(a) + 8)
    end
    if mi.NEEDS_DEST[r.kind] then
        y = y + 6
        t = Text("e2dest", "heading")
        Wide(t, PAD, y)
        t:SetText(r.kind == "mail" and "Send to" or "Which tab")
        Tone(t, "head")
        y = y + 22
        local dd = Get("e2dd", function() return Wg().Dropdown(f, 240, function(v) editing.dest = v; P.QueueRefresh() end) end)
        dd:SetChoices(function()
            local out = {}
            for _, d in ipairs(MI().Dests()) do
                if d.kind == editing.kind then
                    local w = MI().Resolve(d.id)
                    out[#out + 1] = { value = d.id, label = d.label .. (w and (d.kind == "mail" and (": " .. w.recipient) or (": " .. (w.tabName or "?"))) or " (nothing chosen here)") }
                end
            end
            return out
        end)
        local cur = r.dest and mi.Dest(r.dest)
        dd:SetValue(r.dest, cur and cur.label or "Choose...")
        At(dd, PAD, y)
        local nb = Edit("e2new", 150)
        At(nb, PAD + 252, y + 1)
        if not nb:HasFocus() and (nb:GetText() or "") == "" then nb:SetText(newDestName[r.kind] or "") end
        nb:SetScript("OnTextChanged", function(self) newDestName[editing.kind] = self:GetText() end)
        Button("e2add", "Add destination", 130, "secondary", function()
            local id, why = mi.AddDest(editing.kind, pool.e2new:GetText())
            if not id then Say(why, "warn") return end
            editing.dest = id
            pool.e2new:SetText("")
            newDestName[editing.kind] = nil
        end)
        At(pool.e2add, PAD + 408, y)
        y = y + 32
        local where = r.dest and mi.Resolve(r.dest)
        local s = Text("e2where", "small")
        Wide(s, PAD, y)
        if not cur then s:SetText("Choose a destination, or name a new one (for example \"Bank alt\").")
        elseif not where then s:SetText(("\"%s\" has nothing chosen on this character yet. Set it under Destinations on this character, after saving."):format(cur.label))
        elseif r.kind == "mail" then s:SetText(("On this character \"%s\" is |cffffffff%s|r%s."):format(cur.label, where.recipient, where.shared and " (all your characters)" or ""))
        else s:SetText(("On this character \"%s\" is <%s>, tab %d \"%s\"."):format(cur.label, where.guild, where.tab, where.tabName or "?")) end
        Tone(s, where and "dim" or "warn")
        y = y + H(s) + 8
    end
    return y
end

local function DrawKeepStep(y)
    local mi, r = MI(), editing
    local t = Text("e3exc", "heading")
    Wide(t, PAD, y)
    t:SetText("Never include these items")
    Tone(t, "head")
    y = y + 18
    local d = Text("e3excText", "small")
    Wide(d, PAD, y)
    d:SetText("This rule never matches these, whatever else is true; another rule may still. For items no rule should ever move, use the Never transfer list. Click one to take it off.")
    Tone(d, "dim")
    y = y + H(d) + 6
    local h = ItemStrip("e3excI", r.exclude, PAD, y, "Click to take it off this rule's list.", function(id) r.exclude[id] = nil; P.QueueRefresh() end)
    y = y + h + (h > 0 and 6 or 0)
    Button("e3excPick", "Choose from bags", 140, "secondary", function()
        mi.Picker.Open({ purpose = ("Never include in \"%s\": this rule never matches these."):format(r.name), selected = r.exclude,
            onDone = function(set) r.exclude = set; for id in pairs(set) do r.include[id] = nil end; P.QueueRefresh() end })
    end)
    At(pool.e3excPick, PAD, y)
    local box = Edit("e3excId", 160)
    At(box, PAD + 150, y + 1)
    local function Add(id) r.exclude[id] = true; r.include[id] = nil; P.QueueRefresh() end
    box:SetScript("OnEnterPressed", function(self) AddById(self, Add) end)
    Button("e3excAdd", "Add by ID or link", 140, "secondary", function() AddById(pool.e3excId, Add) end)
    At(pool.e3excAdd, PAD + 320, y)
    y = y + 40
    if r.kind == "never" then return y end
    t = Text("e3keep", "heading")
    Wide(t, PAD, y)
    t:SetText("Keep in bags")
    Tone(t, "head")
    y = y + 22
    local on = Check("e3keepOn", function(v)
        editing.keep = v and math.max(1, editing.keep) or 0
        if v and editing.keep == 0 then editing.keep = 20 end
        P.QueueRefresh()
    end)
    on:SetChecked(r.keep > 0)
    At(on, PAD, y + 2)
    local kt = Text("e3keepT", "body")
    Wide(kt, PAD + 24, y + 4, 60)
    kt:SetText("Keep")
    local kb = Edit("e3keepN", 60)
    kb:SetMaxLetters(4)
    At(kb, PAD + 64, y + 1)
    if not kb:HasFocus() then kb:SetText(r.keep > 0 and tostring(r.keep) or "") end
    local function Read()
        if not editing then return end
        local n = tonumber(kb:GetText() or "")
        if n and n >= 0 and n <= mi.MAX_KEEP and math.floor(n) == n then editing.keep = n
        else Say(("Type a whole number from 0 to %d."):format(mi.MAX_KEEP), "warn") end
        kb:ClearFocus()
        P.QueueRefresh()
    end
    kb.read = Read
    kb:SetScript("OnEnterPressed", Read)
    if not kb.hooked then
        kb.hooked = true
        -- hooked once: the field's focus ring is a hook of the same script, and the page may be closing
        kb:HookScript("OnEditFocusLost", function(self)
            if editing and self:IsVisible() and (self:GetText() or "") ~= tostring(editing.keep) then self.read() end
        end)
    end
    local kt2 = Text("e3keepT2", "body")
    Wide(kt2, PAD + 132, y + 4, 300)
    kt2:SetText("of each matching item in my bags")
    y = y + 28
    local note = Text("e3keepNote", "small")
    Wide(note, PAD, y)
    note:SetText("Counted for each kind of item over every stack you carry (not one amount shared by the whole category), and never in your bank or mail. Only whole stacks move, so sometimes a few more than this stay.")
    Tone(note, "dim")
    return y + H(note) + 8
end

local function DrawReviewStep(y)
    local mi, r = MI(), editing
    local t = Text("e4s", "body")
    Wide(t, PAD, y)
    t:SetText(P.Sentence(r))
    y = y + H(t) + 10
    local probe = mi.CleanRule((function() local c = {} for k, v in pairs(r) do c[k] = v end c.id = c.id or "rnew" return c end)())
    local code, why = mi.Problem(probe, false)
    if code then
        local p = Text("e4p", "small")
        Wide(p, PAD, y)
        p:SetText("Can't be turned on yet: " .. why)
        Tone(p, "warn")
        y = y + H(p) + 8
        turnOn = false
    end
    local c = Check("e4on", function(v) if not code then turnOn = v; P.QueueRefresh() end end)
    c:SetChecked(turnOn and not code)
    c:SetActive(not code)
    At(c, PAD, y)
    local ct = Text("e4onT", "body")
    Wide(ct, PAD + 24, y + 2, 400)
    ct:SetText("Turn this rule on when I save")
    Tone(ct, code and "quiet" or nil)
    return y + 30
end

local function DrawEditor(y)
    local r = editing
    local head = Text("eHead", "heading")
    Wide(head, PAD, y)
    head:SetText(r.id and "Edit rule" or "New rule")
    Tone(head, "head")
    y = y + 22
    local nt = Text("eNameT", "body")
    Wide(nt, PAD, y + 4, 60)
    nt:SetText("Name")
    local nb = Edit("eName", 300)
    nb:SetMaxLetters(MI().MAX_NAME)
    At(nb, PAD + 60, y)
    if not nb:HasFocus() then nb:SetText(r.name or "") end
    nb:SetScript("OnTextChanged", function(self) if editing then editing.name = self:GetText() end end)
    y = y + 32
    for i, label in ipairs(STEPS) do
        local tab = Get("eTab" .. i, function()
            local b = Wg().Tab(f, label, 150, function() step = i; P.QueueRefresh() end)
            return b
        end)
        tab:SetSelected(step == i)
        At(tab, PAD + (i - 1) * 156, y)
    end
    y = y + 34
    if step == 1 then y = DrawItemsStep(y)
    elseif step == 2 then y = DrawDestStep(y)
    elseif step == 3 then y = DrawKeepStep(y)
    else y = DrawReviewStep(y) end
    y = y + 6
    Button("eBack", "Back", 80, "secondary", step > 1 and function() step = step - 1; P.QueueRefresh() end or nil)
    At(pool.eBack, PAD, y)
    Button("eNext", "Next", 80, "secondary", step < #STEPS and function() step = step + 1; P.QueueRefresh() end or nil)
    At(pool.eNext, PAD + 86, y)
    Button("eCancel", "Cancel", 90, "secondary", function()
        editing = nil
        said = nil
        P.QueueRefresh()
        QueueRelayout()
    end)
    At(pool.eCancel, W - PAD - 190, y)
    Button("eSave", "Save", 90, "primary", function()
        local rule = editing
        rule.enabled = turnOn
        local id, why = MI().SaveRule(rule)
        if not id then Say(why, "warn") return end
        local saved = MI().Rule(id)
        editing = nil
        if turnOn and saved and not saved.enabled then Say(("Saved \"%s\", turned off: %s"):format(saved.name, select(2, MI().Problem(saved, false)) or ""), "warn")
        else Say(("Saved \"%s\"%s."):format(saved and saved.name or "", saved and saved.enabled and ", turned on" or ", turned off")) end
        QueueRelayout()
    end)
    At(pool.eSave, W - PAD - 90, y)
    R.Interact.Tip(pool.eSave, "Save", "Saves the rule. It starts moving items only when you open a mailbox, bank or guild bank, review and press the action yourself.")
    return y + 34
end

function P.Refresh()
    if not (f and f:IsShown() and built) then return end
    for k in pairs(touched) do touched[k] = nil end
    local y = 4
    if said then
        local s = Text("said", "small")
        Wide(s, PAD, y)
        s:SetText(said)
        Tone(s, saidTone == "warn" and "warn" or "dim")
        y = y + H(s) + 8
    end
    if editing then
        y = DrawEditor(y)
    else
        y = DrawList(y)
        y = DrawDests(y + 10)
        y = DrawNever(y + 10)
    end
    for k, c in pairs(pool) do if not touched[k] then c:Hide() end end
    local newHeight = math.max(120, y + 8)
    f:SetHeight(newHeight)
    if newHeight ~= height then
        height = newHeight
        QueueRelayout()
    end
end

local function Build()
    built = true
end

-- Only while the page is shown: answers about items named here, and the bags and guild bank for the destinations.
local EVENTS = { "GET_ITEM_INFO_RECEIVED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANK_UPDATE_TABS" }

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
        for _, c in pairs(pool) do if c.ClearFocus then c:ClearFocus() end end
        said = nil
        local mi = MI()
        if mi and mi.Picker and mi.Picker.IsShown() then mi.Picker.Cancel() end
    end)
    f:SetScript("OnEvent", function() P.QueueRefresh() end)
    return f
end

function P.Editing() return editing end
function P.ControlCount() local n = 0 for _ in pairs(pool) do n = n + 1 end return n end
P.NewFromTemplate = NewFromTemplate   -- the New rule list's choice, by template key
function P.Control(key) return pool[key] end

-- A change made anywhere (here, the review, a profile change) redraws the page if it is shown. Registered once.
if R.MagicInventory then R.MagicInventory.OnChange(function() P.QueueRefresh() end) end
-- A rule being edited belongs to the profile it came from: a profile change puts the editor away, unsaved.
if R.Profiles and R.Profiles.OnApply then
    R.Profiles.OnApply("views", "magic-inventory-page", function()
        editing = nil
        P.QueueRefresh()
    end)
end

local function Count()
    local n, on = 0, 0
    for _, r in ipairs(R.MagicInventory.Rules()) do
        n = n + 1
        if r.enabled then on = on + 1 end
    end
    return n, on
end

K.Page({
    key = "magicInventory", icon = "diagCompare", name = "Magic Inventory", order = 47, group = "everyday",
    description = "Rules that pick out items to mail to a character you name, or deposit in your bank or a guild bank tab. Nothing moves until you review it and press the action yourself.",
    keywords = "magic inventory mail mailbox send bank deposit guild bank tab bank alt alt cloth herbs ore materials mats disenchant boe bind on equip greens transfer move route rules keep never transfer recipient",
    when = function() return R.MagicInventory ~= nil and R.MagicInventory.Run ~= nil end,
    overview = {
        label = "Magic Inventory", tip = "Rules that prepare items to mail or deposit; nothing moves until you review and click.",
        when = function() return R.MagicInventory ~= nil end,
        status = function()
            if not R:Enabled("magicInventory") or not R.MagicInventory.Enabled() then return K.OnOff(false) end
            local n, on = Count()
            if n == 0 then return K.OnOff(false, nil, "No rules yet") end
            return K.OnOff(on > 0, ("%d of %d rules on"):format(on, n), ("%d, none on"):format(n))
        end,
    },
    build = function()
        K.Card({
            title = "Magic Inventory", icon = "diagCompare",
            what = "Picks out items by rules you make (cloth for your bank alt, herbs for your bank, green gear for a friend) and lists them when you open a mailbox, bank or guild bank.",
            summary = function()
                local n, on = Count()
                if n == 0 then return "No rules yet." end
                return ("%d %s, %d turned on."):format(n, n == 1 and "rule" or "rules", on)
            end,
            consequence = "Nothing moves by itself. At the mailbox, bank or guild bank a small Magic Inventory button opens a review of exactly what would move and where; you prepare and send each mail, or deposit, with your own click. Sent mail and deposits can't be undone. No money is sent, C.O.D. is never used, and nothing is taken out of a bank.",
            details = {
                { "Which items are never moved?", "Quest items, conjured items, items in an equipment set, locked items, anything on the Never transfer list, and soulbound items by mail or to a guild bank (your own bank can take them). An item the game hasn't fully described yet is left where it is." },
                { "Who gets my recipients?", "Only the character you set them on, unless you tick \"All my characters\". Recipients are kept out of shared settings and backups. TwichUI checks a name's form, not whether the character exists or who plays it." },
                { "What about guild banks?", "The game has the guild bank window, but whether Forever's realms have guild vaults isn't known to TwichUI. If one opens, its button appears there too." },
            },
        })
        K.Toggle("magicInventory", "Use Magic Inventory",
            "On: the Magic Inventory button appears at a mailbox, bank or guild bank, and its review lists what your rules would move. Nothing moves until you press an action there. Off: no button and nothing is listened for. Your rules are kept either way.")
    end,
    host = function() return P.Frame() end, hostAfter = "Magic Inventory", hostHeight = function() return P.Height() end,
})
