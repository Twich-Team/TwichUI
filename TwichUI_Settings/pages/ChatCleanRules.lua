-- TwichUI settings: Chat cleaning › Custom rules (modules/ChatClean.lua). Your rules in the order they are checked,
-- each with an on/off box, its place in the order, Edit and Remove; and one editor for adding or changing a rule: the
-- text, how it is matched (with that kind's syntax explained under it, so the expert pattern syntax appears only when
-- chosen), an optional name, match case, and the channels it applies to. A rule that would hide everything, or text
-- so short it is in many messages, asks before it is saved. A frame of this window's own, shown as the tab's page;
-- built the first time it is shown, with list rows made as needed and reused. Every change goes through
-- ChatClean.lua's own functions, which check everything again.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.ChatCleanRulesPage = P

local W = 644                  -- the settings window's content width
local ROW_H, VISIBLE = 34, 5
local LIST_TOP = -58
local LIST_H = ROW_H * VISIBLE + 8
local LIST_W = W - 12 - 26
local EDIT_TOP = LIST_TOP - LIST_H - 12
local CHANNEL_COLS, CHANNEL_ROWS = 4, 3

local f, built
local rows, channelBoxes = {}, {}
local edit                       -- the editor's state: { id (nil: a new rule), mode, channels = { [key] = true } }
local refreshQueued = false

local function Wg() return R.SettingsWidgets end
local function CC() return R.ChatClean end
local function Match() return R.ChatCleanMatch end

local MODES = {
    { value = "contains", label = "Contains text" },
    { value = "wildcard", label = "Wildcard (* and ?)" },
    { value = "pattern", label = "Lua pattern (expert)" },
}
local MODE_LABEL = {}
for _, m in ipairs(MODES) do MODE_LABEL[m.value] = m.label end

local MODE_HELP = {
    contains = "Hides messages that contain this text anywhere. Every character is literal: \"wts boost\", \"50%\" or \"[gold]\" mean exactly that. Example: cheap gold",
    wildcard = "* is any run of characters (or none) and ? is one character; everything else is literal. Matches anywhere in the message. Example: wts*boost hides \"WTS mythic boost\". To find a real * or ?, use Contains text.",
    pattern = "A Lua pattern (not a regular expression), matched as written, case included, against the text you see. %d is a digit, %a a letter, . any character, [abc] a set; * + - repeat, ? is optional. At most 2 repeats, 80 characters, no %1. Example: %d+%s*g%f[%A] finds a price such as \"500 g\".",
}

function P.Say(text, tone)
    P.lastSaid, P.lastTone = text, tone
    if not (f and f.note) then return end
    local pal = Wg().pal
    f.note:SetText(text or "")
    Wg().Color(f.note, tone == "warn" and pal.danger.text or (tone == "ok" and pal.tealHi or pal.textDim))
end

-- "All channels being cleaned", or the names of the channels a rule names.
local function AppliesText(rule)
    if rule.all then return "All channels being cleaned" end
    local names = {}
    for key in pairs(rule.channels) do names[#names + 1] = CC().ChannelLabel(key) end
    table.sort(names)
    return table.concat(names, ", ")
end

---------------------------------------------------------------------------
-- The editor
---------------------------------------------------------------------------
local function EditorChannels()
    local list = {}
    for _, ch in ipairs(CC().KnownChannels()) do
        list[#list + 1] = ch
        if #list >= CHANNEL_COLS * CHANNEL_ROWS then break end
    end
    return list
end

local function PaintEditor()
    if not (f and built) then return end
    local G = Wg()
    local pal = G.pal
    local open = edit ~= nil
    for _, part in ipairs(f.editorParts) do part:SetShown(open) end
    f.examples:SetShown(not open)
    if not open then
        for _, box in ipairs(channelBoxes) do box:Hide(); box.label:Hide() end
        return
    end
    f.editTitle:SetText(edit.id and "Edit rule" or "New rule")
    f.mode:SetValue(edit.mode, MODE_LABEL[edit.mode])
    f.modeHelp:SetText(MODE_HELP[edit.mode])
    local pattern = edit.mode == "pattern"
    f.case:SetShown(not pattern)
    f.caseLabel:SetShown(not pattern)
    f.all:SetChecked(edit.all)
    local list = EditorChannels()
    for i, ch in ipairs(list) do
        local box = channelBoxes[i]
        if not box then
            box = G.Checkbox(f, function(on)
                local key = channelBoxes[i].key
                if not (edit and key) then return end
                edit.channels[key] = on or nil
                PaintEditor()
            end)
            local col, line = (i - 1) % CHANNEL_COLS, math.floor((i - 1) / CHANNEL_COLS)
            box:SetPoint("TOPLEFT", 16 + col * ((W - 24) / CHANNEL_COLS), f.channelTop - line * 22)
            box.label = G.Text(f, "small")
            box.label:SetPoint("LEFT", box, "RIGHT", 6, 0)
            box.label:SetWidth((W - 24) / CHANNEL_COLS - 30)
            box.label:SetWordWrap(false)
            channelBoxes[i] = box
        end
        box.key = ch.key
        box.label:SetText(Match().Plain(ch.label))
        box:SetChecked(edit.channels[ch.key] == true)
        box:SetActive(not edit.all)
        G.Color(box.label, edit.all and pal.stone or pal.text)
        box:Show(); box.label:Show()
    end
    for i = #list + 1, #channelBoxes do channelBoxes[i].key = nil; channelBoxes[i]:Hide(); channelBoxes[i].label:Hide() end
    f.noChannels:SetShown(#list == 0)
end

function P.Open(id)
    local rule = id and CC().Rule(id)
    if id and not rule then
        P.Say("That rule isn't there any more.", "warn")
        return false
    end
    edit = { id = id, mode = rule and rule.mode or "contains", all = not rule or rule.all, channels = {} }
    if rule then for key in pairs(rule.channels) do edit.channels[key] = true end end
    if not built then return true end
    f.text:SetText(rule and rule.text or "")
    f.name:SetText(rule and rule.name or "")
    f.case:SetChecked(rule and rule.case or false)
    f.problem:SetText("")
    PaintEditor()
    f.text:SetFocus()
    return true
end

function P.Close()
    edit = nil
    if not built then return end
    f.text:ClearFocus(); f.name:ClearFocus()
    f.problem:SetText("")
    PaintEditor()
end

-- What the editor holds, as a rule definition.
local function Definition()
    local rule = edit.id and CC().Rule(edit.id)
    return {
        name = f.name:GetText(), mode = edit.mode, text = f.text:GetText(), case = f.case:GetChecked(),
        enabled = not rule or rule.enabled, all = edit.all, channels = edit.channels,
    }
end

-- Saves the editor's rule. force: the player accepted the warning. Returns true, or false and why.
function P.Save(force)
    if not edit then return false, "closed" end
    local def = Definition()
    local ok, a, code
    if edit.id then ok, a, code = CC().UpdateRule(edit.id, def, force) else ok, a, code = CC().AddRule(def, force) end
    if ok then
        local rule = CC().Rule(a)
        P.Say(("%s \"%s\". It applies to messages from now on."):format(edit.id and "Saved" or "Added", rule and CC().RuleName(rule) or ""), "ok")
        P.Close()
        P.Refresh()
        return true
    end
    if code then
        R.Interact.Confirm("TWICHUI_CHATCLEAN_RULE", ("Save this rule anyway?\n\n%s"):format(a), function() P.Save(true) end,
            { accept = "Save anyway" })
        f.problem:SetText(a)
        return false, code
    end
    f.problem:SetText(a or "")
    return false, a
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local function Row(i)
    if rows[i] then return rows[i] end
    local G, I = Wg(), R.Interact
    local pal = G.pal
    local row = CreateFrame("Frame", nil, f.content)
    row:SetSize(LIST_W, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row.bg = G.Solid(row, "BACKGROUND", pal.text, (i % 2 == 0) and 0.035 or 0)
    row.bg:SetAllPoints()
    row.check = G.Checkbox(row, function(on) if row.rule then CC().SetRuleEnabled(row.rule.id, on) end end)
    row.check:SetPoint("LEFT", 8, 0)
    I.Tip(row.check, "On", "On: messages matching this rule are hidden in the channels it applies to. Off: kept, and not used.")
    row.name = G.Text(row, "body")
    row.name:SetPoint("TOPLEFT", 36, -3)
    row.name:SetWidth(330)
    row.name:SetWordWrap(false)
    row.detail = G.Text(row, "meta")
    row.detail:SetPoint("TOPLEFT", 36, -18)
    row.detail:SetWidth(330)
    row.detail:SetWordWrap(false)
    row.up = G.ArrowButton(row, "up", function() if row.rule then CC().MoveRule(row.rule.id, -1) end end)
    row.up:SetPoint("LEFT", 380, 0)
    I.Tip(row.up, "Move up", "Rules are checked from the top; the first that matches is named in the live view.")
    row.down = G.ArrowButton(row, "down", function() if row.rule then CC().MoveRule(row.rule.id, 1) end end)
    row.down:SetPoint("LEFT", 402, 0)
    I.Tip(row.down, "Move down", "Rules are checked from the top; the first that matches is named in the live view.")
    row.edit = G.Button(row, "Edit", 70, "secondary", function() if row.rule then P.Open(row.rule.id) end end)
    row.edit:SetPoint("RIGHT", -92, 0)
    row.remove = G.Button(row, "Remove", 80, "secondary", function()
        if not row.rule then return end
        local id, name = row.rule.id, CC().RuleName(row.rule)
        if CC().RemoveRule(id) then
            if edit and edit.id == id then P.Close() end
            P.Say(("Removed \"%s\". Messages it hid before stay hidden; new ones are shown."):format(name), "ok")
        end
    end)
    row.remove:SetPoint("RIGHT", -6, 0)
    I.Tip(row.remove, "Remove", "Deletes this rule. Messages it already hid can't be brought back; new ones are shown.")
    rows[i] = row
    return row
end

function P.Refresh()
    if not (f and built and f:IsShown()) then return end
    local G, M = Wg(), Match()
    local pal = G.pal
    local list = CC().Rules()
    for i, rule in ipairs(list) do
        local row = Row(i)
        row.rule = rule
        row.name:SetText(M.Plain(CC().RuleName(rule)))
        G.Color(row.name, rule.enabled and pal.text or pal.stone)
        local how = rule.name and M.Summary(rule) or M.MODE_WORDS[rule.mode]
        if rule.case then how = how .. ", match case" end
        row.detail:SetText(M.Plain(how .. " · " .. AppliesText(rule)))
        row.check:SetChecked(rule.enabled)
        row.up:SetEnabled(i > 1)
        row.down:SetEnabled(i < #list)
        row:Show()
    end
    for i = #list + 1, #rows do
        rows[i].rule = nil
        rows[i]:Hide()
    end
    f.content:SetHeight(math.max(1, #list * ROW_H))
    f.empty:SetShown(#list == 0)
    f.count:SetText(("%d of %d"):format(#list, CC().MAX_RULES))
    f.add:SetEnabled(#list < CC().MAX_RULES)
    -- the rule being edited went away (a profile change, an import, another tab)
    if edit and edit.id and not CC().Rule(edit.id) then
        P.Close()
        P.Say("The rule you were editing isn't there any more, so the editor was closed.", "warn")
    else
        PaintEditor()
    end
end

local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.1, function()
        refreshQueued = false
        P.Refresh()
    end)
end

local function Build()
    built = true
    local G, I = Wg(), R.Interact
    local pal = G.pal

    f.help = G.Text(f, "small")
    f.help:SetPoint("TOPLEFT", 4, -2)
    f.help:SetWidth(W - 140)
    f.help:SetText("Words or patterns to hide, each in the channels you choose (only channels being cleaned). Checked from the top, before the built-in filters. Messages from you, friends, your guild and group are never hidden.")
    f.add = G.Button(f, "Add a rule", 120, "secondary", function() P.Open(nil) end)
    f.add:SetPoint("TOPRIGHT", -2, -4)
    I.Tip(f.add, "Add a rule", function()
        if #CC().Rules() >= CC().MAX_RULES then return "Opens the editor below.", ("You have %d rules, the most there can be. Remove one first."):format(CC().MAX_RULES) end
        return "Opens the editor below for a new rule."
    end)

    local function Column(text, x)
        local t = G.Text(f, "meta")
        t:SetPoint("TOPLEFT", 6 + x, -42)
        t:SetText(text)
        return t
    end
    Column("On", 4)
    Column("Rule", 36)
    Column("Order", 380)
    f.count = G.Text(f, "meta")
    f.count:SetPoint("TOPRIGHT", -8, -42)
    f.count:SetJustifyH("RIGHT")
    f.well = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.well:SetPoint("TOPLEFT", 0, LIST_TOP)
    f.well:SetSize(W, LIST_H)
    G.Well(f.well)
    f.scroll, f.content = G.Scroll(f.well, LIST_W)
    f.scroll:SetPoint("TOPLEFT", 6, -4)
    f.scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    f.empty = G.Text(f.well, "small")
    f.empty:SetPoint("TOPLEFT", 12, -14)
    f.empty:SetWidth(W - 24)
    f.empty:SetText("No custom rules yet. The built-in filters work without any; add a rule for anything else you'd rather not see.")

    -- the editor
    local y = EDIT_TOP
    G.Card(f, 0, y, W, -540)
    f.note = G.Text(f, "small")
    f.note:SetPoint("TOPLEFT", 4, y + 12)
    f.note:SetWidth(W - 8)
    f.note:SetWordWrap(false)
    P.Say(P.lastSaid, P.lastTone)
    f.editorParts = {}
    local function Part(x) f.editorParts[#f.editorParts + 1] = x; return x end

    f.examples = G.Text(f, "small")
    f.examples:SetPoint("TOPLEFT", 12, y - 12)
    f.examples:SetWidth(W - 24)
    f.examples:SetText("Add a rule to hide messages with words you choose. Examples:\n  Contains text: cheap gold  (hides any message containing those words; punctuation is literal)\n  Wildcard: wts*boost  (* is anything, ? is one character)\nRules don't bring back messages already hidden, and changes apply to messages from then on.")

    f.editTitle = Part(G.Text(f, "heading"))
    f.editTitle:SetPoint("TOPLEFT", 12, y - 10)
    local findLabel = Part(G.Text(f, "meta"))
    findLabel:SetPoint("TOPLEFT", 12, y - 32)
    findLabel:SetText("Find")
    f.text = Part(G.EditBox(f, W - 24 - 180 - 44, 22))
    f.text:SetPoint("TOPLEFT", 52, y - 28)
    f.text:SetMaxLetters(Match().TEXT_MAX)
    f.text:SetScript("OnEnterPressed", function() P.Save() end)
    f.text:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    I.Tip(f.text, "Find", "The text or pattern to look for in the text people see (link details are not searched).")
    f.mode = Part(G.Dropdown(f, 180, function(value)
        if not edit then return end
        edit.mode = value
        PaintEditor()
    end))
    f.mode:SetChoices(function() return MODES end)
    f.mode:SetPoint("TOPRIGHT", -12, y - 28)
    I.Tip(f.mode, "How it is matched", "Contains text: the text anywhere, every character literal. Wildcard: * and ? stand for any characters. Lua pattern: for people who know Lua patterns.")
    f.modeHelp = Part(G.Text(f, "small"))
    f.modeHelp:SetPoint("TOPLEFT", 12, y - 56)
    f.modeHelp:SetWidth(W - 24)

    local nameLabel = Part(G.Text(f, "meta"))
    nameLabel:SetPoint("TOPLEFT", 12, y - 108)
    nameLabel:SetText("Name")
    f.name = Part(G.EditBox(f, 220, 22))
    f.name:SetPoint("TOPLEFT", 52, y - 104)
    f.name:SetMaxLetters(Match().NAME_MAX)
    f.name:SetScript("OnEnterPressed", function() P.Save() end)
    I.Tip(f.name, "Name (optional)", "Shown in the list and the live view. Left empty, the rule is described by what it matches.")
    f.case = Part(G.Checkbox(f, function(on) f.case:SetChecked(on) end))
    f.case:SetPoint("TOPLEFT", 300, y - 106)
    f.caseLabel = Part(G.Text(f, "small"))
    f.caseLabel:SetPoint("LEFT", f.case, "RIGHT", 6, 0)
    f.caseLabel:SetText("Match case")
    I.Tip(f.case, "Match case", "Off (usual): \"WTS\" also finds \"wts\". Only the letters A to Z have a case here; accented and other letters are compared as typed.")

    local appliesLabel = Part(G.Text(f, "meta"))
    appliesLabel:SetPoint("TOPLEFT", 12, y - 138)
    appliesLabel:SetText("Applies to")
    f.all = Part(G.Checkbox(f, function(on)
        if not edit then return end
        edit.all = on
        PaintEditor()
    end))
    f.all:SetPoint("TOPLEFT", 90, y - 136)
    f.allLabel = Part(G.Text(f, "small"))
    f.allLabel:SetPoint("LEFT", f.all, "RIGHT", 6, 0)
    f.allLabel:SetText("All channels being cleaned")
    I.Tip(f.all, "All channels being cleaned", "On: the rule applies in every channel you clean, now and later. Off: only in the channels ticked below (and only while they are cleaned).")
    f.channelTop = y - 160
    f.noChannels = Part(G.Text(f, "small"))
    f.noChannels:SetPoint("TOPLEFT", 16, f.channelTop)
    f.noChannels:SetText("No channels to choose from yet: join one, or use All channels being cleaned.")

    f.problem = Part(G.Text(f, "small"))
    f.problem:SetPoint("TOPLEFT", 12, y - 232)
    f.problem:SetWidth(W - 24 - 220)
    G.Color(f.problem, pal.danger.text)
    f.save = Part(G.Button(f, "Save", 96, "secondary", function() P.Save() end))
    f.save:SetPoint("TOPRIGHT", -112, y - 232)
    f.cancel = Part(G.Button(f, "Cancel", 90, "secondary", function() P.Close() end))
    f.cancel:SetPoint("TOPRIGHT", -12, y - 232)
    if edit then P.Open(edit.id) else PaintEditor() end
end

-- The page's frame (the settings window shows it under Chat cleaning). Built the first time it is shown.
function P.Frame()
    if f then return f end
    f = CreateFrame("Frame")
    f:Hide()
    f:SetScript("OnShow", function()
        if not built then Build() end
        P.Refresh()
    end)
    f:SetScript("OnHide", function()
        if f.text then f.text:ClearFocus(); f.name:ClearFocus() end
    end)
    return f
end

-- A change made anywhere (here, another tab, a profile change, an import) redraws the list if it is shown. Registered once.
if R.ChatClean then R.ChatClean.OnChange(QueueRefresh) end

K.Page({
    key = "chatCleanRules", name = "Chat cleaning rules", nav = "Custom rules", parent = "chatClean", order = 37,
    description = "Your own words or patterns to hide, each with the channels it applies to.",
    keywords = "chat rule rules custom word words keyword phrase text wildcard pattern lua regex filter hide block",
    when = function() return R.ChatClean ~= nil end,
    host = function() return P.Frame() end,
})
