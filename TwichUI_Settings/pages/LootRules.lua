-- TwichUI settings: Loot Rolls › Loot rules (loot/Rules.lua, loot/Config.lua). The switches for automatic rolling above, then a frame of
-- this window's own: your rules in the order they are read (each with its choice, whether it is on, and what is wrong with it), and the
-- chosen rule's editor: its name, a sentence saying what it does, the conditions ("when an item matches"), the choice ("then roll"), the
-- countdown ("auto roll") and, at the bottom, the sentence again. The live preview beside the window is Companion.lua's: the real card,
-- showing the chosen rule's countdown over a made-up item.
-- Every change goes through loot/Config.lua's functions, which check everything again. Nothing here rolls, and nothing is rolled by
-- previewing: the preview is a made-up card that reads no roll. Which rule is open is kept for the session only.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.LootRulesPage = P

local PAD, GAP = 14, 8
local LIST_W = 224
local ROW_H = 54
local STRIP_H = 40
local COND_H = 62
local W_MIN = 644

local f, built
local selected                 -- the rule open in the editor
local rows, conds = {}, {}
local relayout = false
local epoch = 0
local say, sayTone

local function Wg() return R.SettingsWidgets end
local function LR() return R.LootRolls end
local function Ru() return R.LootRules end

local ACTION_ICON = { need = "lootNeed", greed = "lootGreed", pass = "lootPass" }
local ACTION_WORD = { none = "No change", need = "Need", greed = "Greed", pass = "Pass" }

local function Tone(fs, tone)
    local G = Wg()
    local pal = G.pal
    G.Color(fs, tone == "warn" and pal.danger.text or (tone == "ok" and pal.sage or (tone == "quiet" and pal.stone or pal.textDim)))
end

local function Put(item, parent, x, y)
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    item:Show()
end

function P.Selected() return selected and LR().Rule(selected) or nil end

function P.Say(text, tone)
    say, sayTone = text, tone
    if f and f.say then
        f.say:SetText(text or "")
        Tone(f.say, tone)
    end
end

function P.Active()
    local UI = R.SettingsUI
    return f ~= nil and f:IsVisible() and UI ~= nil and UI.IsPageActive("lootRules")
end

local queued = false
function P.QueueRefresh()
    if not P.Active() or queued then return end
    queued = true
    local mine = epoch
    C_Timer.After(0, function()
        if mine ~= epoch then return end
        queued = false
        P.Refresh()
    end)
end

function P.Select(id)
    selected = id
    P.Say(nil)
    P.QueueRefresh()
    if R.SettingsCompanion and R.SettingsCompanion.Refresh then R.SettingsCompanion.Refresh() end
end

---------------------------------------------------------------------------
-- Choices for a condition's controls (strings, since the drop-down hands strings back)
---------------------------------------------------------------------------
local function Choices(kind, cond)
    local Rules = Ru()
    local out = {}
    if kind == "quality" then
        for q = 0, 5 do out[#out + 1] = { value = tostring(q), label = Rules.QualityName(q) } end
    elseif kind == "class" then
        for _, c in ipairs(Rules.CLASS_CHOICES) do out[#out + 1] = { value = tostring(c[1]), label = Rules.ClassName(c[1]) } end
    elseif kind == "armor" then
        for _, c in ipairs(Rules.ARMOR_CHOICES) do out[#out + 1] = { value = tostring(c[1]), label = Rules.ArmorName(c[1]) } end
    elseif kind == "equippable" then
        out = { { value = "true", label = "I can equip it" }, { value = "false", label = "I can't equip it" } }
    elseif kind == "equip" then
        for _, c in ipairs(Rules.EQUIP_CHOICES) do out[#out + 1] = { value = c[1], label = Rules.EquipName(c[1]) } end
    elseif kind == "recipe" then
        for _, c in ipairs(Rules.RECIPE_CHOICES) do out[#out + 1] = { value = c[1], label = c[2] } end
    elseif kind == "bind" then
        for _, c in ipairs(Rules.BIND_CHOICES) do out[#out + 1] = { value = c[1], label = c[2] } end
    elseif kind == "context" then
        for _, c in ipairs(Rules.CONTEXT_CHOICES) do out[#out + 1] = { value = c[1], label = c[2] } end
    elseif kind == "upgrade" then
        out = { { value = "true", label = "Is a potential upgrade" }, { value = "false", label = "Is not a potential upgrade" } }
    elseif kind == "op" then
        for _, c in ipairs(Rules.QUALITY_OPS) do out[#out + 1] = { value = c[1], label = c[2] } end
    end
    return out
end

local function LabelOf(choices, value)
    for _, c in ipairs(choices) do if c.value == value then return c.label end end
    return tostring(value or "")
end

-- The value a condition holds, as the drop-down's string.
local function ValueText(c)
    if c.type == "quality" or c.type == "class" or c.type == "armor" then return tostring(c.value) end
    if c.type == "recipe" then return c.mode end
    if c.type == "upgrade" or c.type == "equippable" then return tostring(c.value) end
    return c.value
end

local function Apply(id, index, fields)
    local ok, why = LR().SetCondition(id, index, fields)
    if not ok then P.Say(why or "That isn't a valid choice.", "warn") end
    P.QueueRefresh()
end

-- An item link or a number, as the number: "item:6948", "[Hearthstone]" links and plain ids.
local function ParseItem(text)
    if type(text) ~= "string" then return nil end
    local id = text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$")
    return id and tonumber(id) or nil
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local function Row(i)
    if rows[i] then return rows[i] end
    local G = Wg()
    local row = CreateFrame("Button", nil, f.list)
    row:SetSize(LIST_W - 12, ROW_H)
    row.sel = G.Solid(row, "BACKGROUND", G.pal.selectedFill, 1)
    row.sel:SetAllPoints()
    row.hover = G.Solid(row, "BACKGROUND", G.pal.hoverFill, 0.6)
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.edge = G.Solid(row, "ARTWORK", G.pal.bronzeText, 1)
    row.edge:SetPoint("TOPLEFT", 0, 0); row.edge:SetPoint("BOTTOMLEFT", 0, 0); row.edge:SetWidth(2)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", 8, 0)
    row.name = G.Text(row, "body")
    row.name:SetPoint("TOPLEFT", 46, -10)
    row.name:SetWidth(LIST_W - 12 - 46 - 18)
    row.name:SetMaxLines(1)
    row.name:SetWordWrap(false)
    row.state = G.Text(row, "small")
    row.state:SetPoint("BOTTOMLEFT", 46, 7)
    row.state:SetWidth(LIST_W - 12 - 46 - 18)
    row.state:SetWordWrap(false)
    row.arrow = G.Text(row, "meta")
    row.arrow:SetPoint("RIGHT", -8, 0)
    row.arrow:SetText(">")
    row:SetScript("OnEnter", function() row.hover:SetShown(not row.sel:IsShown()) end)
    row:SetScript("OnLeave", function() row.hover:Hide() end)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(_, button)
        if not row.id then return end
        if button == "RightButton" then
            local id = row.id
            G.ContextMenu(row, { { value = "up", label = "Move up" }, { value = "down", label = "Move down" },
                { value = "copy", label = "Duplicate" }, { value = "delete", label = "Delete..." } }, function(action)
                if action == "up" then LR().Move(id, -1) elseif action == "down" then LR().Move(id, 1)
                elseif action == "copy" then
                    local ok, copy = LR().Duplicate(id)
                    if ok then P.Select(copy) else P.Say(copy, "warn") end
                elseif action == "delete" then P.Delete(id) end
            end)
        else G.CloseMenu(); P.Select(row.id) end
    end)
    R.Interact.Tip(row, "Loot rule", function() return (row.name:GetText() or "") .. "\n" .. (row.summary or "") end)
    rows[i] = row
    return row
end

function P.Delete(id)
    local v = LR().Rule(id)
    if not v then return end
    local text = ("Delete the rule \"%s\"?\n\nOnly this rule is removed. Any countdown it started stops, and nothing is rolled. This can't be undone."):format(v.name)
    R.Interact.Confirm("TWICHUI_LOOTRULE_DELETE", text, function()
        local ok = LR().Delete(id)
        if ok then
            if selected == id then selected = nil end
            P.Say(("Deleted \"%s\"."):format(v.name), "ok")
        end
    end, { accept = DELETE or "Delete", valid = function()
        if LR().Rule(id) then return true end
        return false, "That rule is already gone, so nothing was deleted."
    end })
end

local function LayoutList(list)
    local G = Wg()
    f.count:SetText(("%d of %d rules"):format(#list, LR().MAX_RULES))
    local y = 44
    if #list == 0 then
        f.empty:SetText("No rules yet. Choose New to start from an example. Each starts off.")
        Put(f.empty, f.list, 12, y)
        y = y + 52
    else
        f.empty:Hide()
    end
    for i, v in ipairs(list) do
        local row = Row(i)
        row.id = v.id
        row.summary = v.summary
        row.name:SetText(v.name)
        R.Icons.Apply(row.icon, ACTION_ICON[v.action] or "lootRolls", 30)
        local state
        if v.incomplete then state = "Needs attention"
        elseif v.enabled then state = "On  ·  " .. Ru().ActionSummary(v)
        else state = "Off  ·  " .. Ru().ActionSummary(v) end
        row.state:SetText(state)
        Tone(row.state, v.incomplete and "warn" or (v.enabled and "ok" or "quiet"))
        local isSel = v.id == selected
        row.sel:SetShown(isSel)
        row.edge:SetShown(isSel)
        row.arrow:SetShown(isSel)
        G.Color(row.name, isSel and G.pal.text or G.pal.textDim)
        Put(row, f.list, 6, y)
        y = y + ROW_H + 3
    end
    for i = #list + 1, #rows do rows[i].id = nil; rows[i]:Hide() end
    return y + 10
end

---------------------------------------------------------------------------
-- The editor
---------------------------------------------------------------------------
local function CondRow(i)
    if conds[i] then return conds[i] end
    local G = Wg()
    local c = { frame = CreateFrame("Frame", nil, f.editor) }
    c.frame:SetHeight(COND_H)
    c.icon = c.frame:CreateTexture(nil, "ARTWORK"); c.icon:SetSize(26, 26); c.icon:SetPoint("TOPLEFT", 0, 0)
    c.label = G.Text(c.frame, "body"); c.label:SetPoint("TOPLEFT", 34, -6); c.label:SetWidth(220); c.label:SetWordWrap(false)
    c.op = G.Dropdown(c.frame, 84, function(value)
        if c.index and selected then Apply(selected, c.index, { op = value }) end
    end)
    c.value = G.Dropdown(c.frame, 150, function(value)
        if not (c.index and selected) then return end
        local kind = c.kind
        if kind == "quality" or kind == "class" or kind == "armor" then
            Apply(selected, c.index, { value = (value == "equipment") and value or tonumber(value) })
        elseif kind == "recipe" then Apply(selected, c.index, { mode = value })
        elseif kind == "upgrade" or kind == "equippable" then Apply(selected, c.index, { value = value == "true" })
        else Apply(selected, c.index, { value = value }) end
    end)
    c.id = G.EditBox(c.frame, 150, 22)
    c.id:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local id = ParseItem(self:GetText())
        if not (id and c.index and selected) then P.Say("Type or paste an item link, or its number.", "warn") P.QueueRefresh() return end
        local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)
        Apply(selected, c.index, { id = id, name = type(name) == "string" and name or false })
    end)
    c.id:SetScript("OnEscapePressed", function(self) self:ClearFocus(); P.QueueRefresh() end)
    c.neg = G.Checkbox(c.frame, function(on)
        if c.index and selected then Apply(selected, c.index, { negate = on or nil }) end
    end)
    c.negText = G.Text(c.frame, "small"); c.negText:SetText("not")
    c.remove = G.Button(c.frame, "x", 24, "secondary", function()
        if c.index and selected then LR().RemoveCondition(selected, c.index); P.QueueRefresh() end
    end)
    R.Interact.Tip(c.remove, "Remove this condition", "Takes this one condition out of the rule.")
    R.Interact.Tip(c.neg, "Not", "Turns the condition around: the rule applies when the item does NOT match it. An item the game hasn't described yet is still unknown, never a match.")
    conds[i] = c
    return c
end

local function LayoutConds(v, y, w)
    local G = Wg()
    local Rules = Ru()
    for i, cond in ipairs(v.conditions) do
        local c = CondRow(i)
        local t = Rules.TYPES[cond.type]
        c.index, c.kind = i, cond.type
        R.Icons.Apply(c.icon, t and t.icon or "lootRolls", 26)
        c.label:SetText(t and t.label or "?")
        local hasOp = cond.type == "quality"
        local inner = w - PAD * 2
        c.frame:SetWidth(inner)
        Put(c.frame, f.editor, PAD, y)
        local x = 34
        c.op:SetShown(hasOp)
        if hasOp then
            local ops = Choices("op")
            c.op:SetWidth(112)
            c.op:SetChoices(ops); c.op:SetValue(cond.op, LabelOf(ops, cond.op))
            c.op:ClearAllPoints(); c.op:SetPoint("TOPLEFT", c.frame, "TOPLEFT", x, -30)
            x = x + 118
        end
        local width = math.max(90, inner - x)
        if cond.type == "item" then
            c.value:Hide(); c.id:Show()
            c.id:SetWidth(width)
            c.id:ClearAllPoints(); c.id:SetPoint("TOPLEFT", c.frame, "TOPLEFT", x, -30)
            if not c.id:HasFocus() then
                c.id:SetText(cond.id and cond.id > 0 and ((type(cond.name) == "string" and cond.name ~= "" and cond.name) or ("item #" .. cond.id)) or "")
            end
        else
            c.id:Hide(); c.value:Show()
            local choices = Choices(cond.type, cond)
            c.value:SetWidth(width)
            c.value:SetChoices(choices)
            local value = ValueText(cond)
            c.value:SetValue(value, LabelOf(choices, value))
            c.value:ClearAllPoints(); c.value:SetPoint("TOPLEFT", c.frame, "TOPLEFT", x, -30)
        end
        c.neg:ClearAllPoints(); c.neg:SetPoint("TOPRIGHT", c.frame, "TOPRIGHT", -(24 + 8 + 34), -4)
        c.neg:SetChecked(cond.negate == true)
        c.negText:ClearAllPoints(); c.negText:SetPoint("LEFT", c.neg, "RIGHT", 4, 0)
        c.remove:ClearAllPoints(); c.remove:SetPoint("TOPRIGHT", c.frame, "TOPRIGHT", 0, -3)
        y = y + COND_H
    end
    for i = #v.conditions + 1, #conds do conds[i].index = nil; conds[i].frame:Hide() end
    return y
end

local function LayoutEditor(v, w)
    local G = Wg()
    local Rules = Ru()
    local y = 12
    R.Icons.Apply(f.headIcon, ACTION_ICON[v.action] or "lootRolls", 36)
    Put(f.headIcon, f.editor, PAD, y)
    f.nameBox:SetWidth(w - PAD * 2 - 44 - 104)
    Put(f.nameBox, f.editor, PAD + 44, y)
    if not f.nameBox:HasFocus() then f.nameBox:SetText(v.name) end
    f.onBox:SetChecked(v.enabled)
    Put(f.onBox, f.editor, w - PAD - 92, y + 2)
    f.onText:SetText(v.enabled and "On" or "Off")
    Tone(f.onText, v.enabled and "ok" or "quiet")
    Put(f.onText, f.editor, w - PAD - 40, y + 6)
    f.summary:SetWidth(w - PAD * 2 - 44)
    f.summary:SetText(v.summary or "")
    Put(f.summary, f.editor, PAD + 44, y + 28)
    y = y + 28 + math.max(26, f.summary:GetStringHeight() or 26) + 8
    local bw = (w - PAD * 2 - 3 * 6) / 4
    for i, b in ipairs(f.tools) do
        b:SetWidth(bw)
        Put(b, f.editor, PAD + (i - 1) * (bw + 6), y)
    end
    f.tools[1]:SetEnabled(v.index > 1)
    f.tools[2]:SetEnabled(v.index < LR().Count())
    y = y + 34

    -- when an item matches
    f.whenTitle:SetText("When an item matches")
    Put(f.whenTitle, f.editor, PAD, y)
    f.matchAll:SetOn(v.match == "all"); f.matchAny:SetOn(v.match == "any")
    Put(f.matchAny, f.editor, w - PAD - 96, y - 3)
    Put(f.matchAll, f.editor, w - PAD - 96 - 100, y - 3)
    y = y + 22
    f.whenHelp:SetWidth(w - PAD * 2)
    f.whenHelp:SetText(v.match == "any" and "The rule applies when any one of these is true." or "The rule applies when all of these are true.")
    Put(f.whenHelp, f.editor, PAD, y)
    y = y + 18
    y = LayoutConds(v, y, w)
    f.addCond:SetEnabled(#v.conditions < Rules.MAX_CONDITIONS)
    Put(f.addCond, f.editor, PAD, y + 4)
    y = y + 40

    -- then roll
    f.thenTitle:SetText("Roll")
    Put(f.thenTitle, f.editor, PAD, y)
    y = y + 22
    local aw = (w - PAD * 2 - 3 * 8) / 4
    for i, key in ipairs({ "none", "need", "greed", "pass" }) do
        local b = f.actions[key]
        b:SetWidth(aw)
        if b.text then b.text:SetWidth(aw - (key == "none" and 8 or 30)) end
        b:SetOn(v.action == key)
        Put(b, f.editor, PAD + (i - 1) * (aw + 8), y)
    end
    y = y + 40
    f.displayTitle:SetText("Card display"); Put(f.displayTitle, f.editor, PAD, y); y = y + 22
    local dw = (w - PAD * 2 - 16) / 3
    for i, key in ipairs({ "none", "expanded", "collapsed" }) do
        local b = f.displays[key]; b:SetWidth(dw); b:SetOn(v.display == key)
        Put(b, f.editor, PAD + (i - 1) * (dw + 8), y)
    end
    y = y + 40
    local gate = v.action == "none" and "Display only; other roll rules still apply." or nil
    if v.action == "need" and not LR().Get("autoNeed") then gate = "Need is only chosen automatically once you allow it, in the switches above." end
    if v.action ~= "none" and v.usesUpgrade and not LR().Get("autoUpgrade") then gate = "A rule that asks about upgrades acts only once you allow that, in the switches above." end
    if gate then
        f.gate:SetWidth(w - PAD * 2); f.gate:SetText(gate); Tone(f.gate, v.action == "none" and "quiet" or "warn"); Put(f.gate, f.editor, PAD, y)
        y = y + math.max(14, f.gate:GetStringHeight() or 14) + 6
    else f.gate:Hide() end

    -- Countdown/result controls belong only to the roll action.
    if v.action ~= "none" then
    f.autoTitle:SetText("Auto roll")
    Put(f.autoTitle, f.editor, PAD, y)
    y = y + 22
    R.Icons.Apply(f.delayIcon, "lootDelay", 24)
    Put(f.delayIcon, f.editor, PAD, y)
    f.delayLabel:SetText("Wait before rolling")
    Put(f.delayLabel, f.editor, PAD + 30, y + 5)
    f.delay:SetWidth(w - PAD * 2 - 170)
    f.delay:SetRange(1, 15, 1)
    f.delay:SetValue(math.floor(v.delay + 0.5))
    Put(f.delay, f.editor, PAD + 170, y + 1)
    y = y + 32
    R.Icons.Apply(f.resultIcon, "lootResult", 24)
    Put(f.resultIcon, f.editor, PAD, y)
    f.resultLabel:SetText("Show the result afterward")
    Put(f.resultLabel, f.editor, PAD + 30, y + 5)
    f.resultBox:SetChecked(v.result)
    Put(f.resultBox, f.editor, w - PAD - 32, y + 4)   -- the switch is 32 wide: its right edge sits on the padding
    y = y + 34

    else
        for _, part in ipairs({ f.autoTitle, f.delayIcon, f.delayLabel, f.delay, f.resultIcon, f.resultLabel, f.resultBox }) do part:Hide() end
    end

    -- the sentence
    f.bar:SetWidth(w - PAD * 2)
    Put(f.bar, f.editor, PAD, y)
    local text, tone, icon = v.summary, "ok", "check"
    if v.incomplete then text, tone = "Needs attention: " .. v.incomplete, "warn" end
    f.barText:SetWidth(w - PAD * 2 - 44)
    f.barText:SetText(text or "")
    Tone(f.barText, tone == "warn" and "warn" or nil)
    f.barIcon:SetTexture(R.PATH .. [[media\loot\]] .. (v.incomplete and "stop" or "autocheck"))
    local bh = math.max(34, (f.barText:GetStringHeight() or 14) + 20)
    f.bar:SetHeight(bh)
    y = y + bh + 8
    Put(f.previewRule, f.editor, PAD, y)
    y = y + 34
    f.say:SetWidth(w - PAD * 2)
    Put(f.say, f.editor, PAD, y)
    f.say:SetText(say or "")
    Tone(f.say, sayTone)
    y = y + 18
    return y + 8
end

---------------------------------------------------------------------------
-- Redrawing
---------------------------------------------------------------------------
function P.Refresh()
    if not (f and built) then return end
    local list = LR().List()
    local found = false
    for _, v in ipairs(list) do if v.id == selected then found = true end end
    if not found then selected = list[1] and list[1].id or nil end
    local w = math.max(W_MIN, f:GetWidth() or W_MIN)
    local ew = w - LIST_W - GAP
    f.strip:SetSize(w, STRIP_H - 6)
    Put(f.strip, f, 0, 0)
    f.stripBox:SetChecked(LR().Get("auto"))
    local state = LR().Get("paused") and "Paused" or (LR().Get("auto") and (LR().Get("autoNeed") and "On, Need allowed" or "On, Need stays yours") or "Off: nothing is chosen for you")
    f.stripState:SetText(state)
    Tone(f.stripState, (LR().Get("auto") and not LR().Get("paused")) and "ok" or "quiet")
    f.list:SetSize(LIST_W, 100)
    Put(f.list, f, 0, STRIP_H)
    local lh = LayoutList(list)
    local v = selected and LR().Rule(selected)
    local eh = 0
    f.editor:SetWidth(ew)
    Put(f.editor, f, LIST_W + GAP, STRIP_H)
    if v then
        f.noRule:Hide()
        for _, part in ipairs(f.editorParts) do part:Show() end
        eh = LayoutEditor(v, ew)
    else
        for _, part in ipairs(f.editorParts) do part:Hide() end
        for _, c in ipairs(conds) do c.frame:Hide() end
        f.noRule:SetWidth(ew - PAD * 2)
        Put(f.noRule, f.editor, PAD, 20)
        eh = 80
    end
    local h = math.max(lh, eh, 360)
    f.list:SetHeight(h)
    f.editor:SetHeight(h)
    if f.height ~= h + STRIP_H then
        f.height = h + STRIP_H
        f:SetHeight(h + STRIP_H)
        local UI = R.SettingsUI
        if UI and UI.Refresh and P.Active() then C_Timer.After(0, function() if P.Active() then UI.Refresh() end end) end
    end
    if R.SettingsCompanion and R.SettingsCompanion.Refresh then R.SettingsCompanion.Refresh() end
end

function P.Height() return (f and f.height) or 420 end

local function Segment(parent, label, onClick)
    local FL = R.FrameLook
    return FL.Toggle(parent, label, 96, onClick)
end

local function Build()
    local G, M = Wg(), R.SettingsMaterial
    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(W_MIN, 420)
    f.height = 420
    -- the automatic rolling switch, within reach of the rules it governs (the rest of its options are below)
    f.strip = CreateFrame("Frame", nil, f, "BackdropTemplate")
    M.PanelFace(f.strip, "canvas")
    f.stripBox = G.Checkbox(f.strip, function(on) LR().Set("auto", on and true or false) end)
    f.stripBox:SetPoint("LEFT", 12, 0)
    f.stripText = G.Text(f.strip, "body"); f.stripText:SetPoint("LEFT", f.stripBox, "RIGHT", 12, 0)   -- a clear gap after the switch (it is 32 units wide)
    f.stripState = G.Text(f.strip, "small"); f.stripState:SetPoint("RIGHT", -12, 0); f.stripState:SetJustifyH("RIGHT")
    f.stripText:SetText("Roll automatically using these rules")
    R.Interact.Tip(f.stripBox, "Roll automatically", "The same switch as \"Roll automatically using my rules\" below. Off: no rule chooses anything. On: a matching rule starts a countdown on its card that you can stop.")
    f.list = CreateFrame("Frame", nil, f, "BackdropTemplate")
    M.PanelFace(f.list, "card")
    f.editor = CreateFrame("Frame", nil, f, "BackdropTemplate")
    M.PanelFace(f.editor, "card")

    -- list
    f.listTitle = G.Text(f.list, "heading"); f.listTitle:SetPoint("TOPLEFT", 12, -12); f.listTitle:SetText("Your rules")
    f.count = G.Text(f.list, "meta"); f.count:SetPoint("TOPLEFT", 12, -29)
    f.new = G.Button(f.list, "+ New", 64, "secondary", function()
        local choices = {}
        for _, t in ipairs(LR().TEMPLATES) do choices[#choices + 1] = { value = t.key, label = t.label } end
        G.ContextMenu(f.new, choices, function(key)
            local ok, id = LR().Create(key)
            if ok then
                P.Select(id)
                P.Say("Made a rule. It starts off: turn it on once it says what you mean.", "ok")
            else P.Say(id, "warn") end
        end)
    end)
    f.new:SetPoint("TOPRIGHT", -8, -10)
    f.empty = G.Text(f.list, "small"); f.empty:SetWidth(LIST_W - 24); f.empty:SetWordWrap(true)
    R.Interact.Tip(f.new, "New rule", "Starts a rule from an example. It starts switched off, so nothing is chosen until you turn it on and turn automatic rolling on.")

    -- editor
    local e = f.editor
    f.editorParts = {}
    local function Part(o) f.editorParts[#f.editorParts + 1] = o; return o end
    f.noRule = G.Text(e, "small"); f.noRule:SetWordWrap(true)
    f.noRule:SetText("Choose a rule on the left, or make a new one.")
    f.headIcon = Part(e:CreateTexture(nil, "ARTWORK")); f.headIcon:SetSize(36, 36)
    f.nameBox = Part(G.EditBox(e, 200, 24))
    f.nameBox:SetMaxLetters(R.LootRules.MAX_NAME)
    local function CommitName(box)
        if not selected then return end
        local ok, why = LR().SetName(selected, box:GetText())
        if not ok then P.Say(why or "That name can't be used.", "warn"); box:SetText((LR().Rule(selected) or {}).name or "") end
        P.QueueRefresh()
    end
    f.nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); CommitName(self) end)
    f.nameBox:SetScript("OnEditFocusLost", function(self) CommitName(self) end)
    f.nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); P.QueueRefresh() end)
    R.Interact.Tip(f.nameBox, "Rule name", "What this rule is called in the list. Only for you; it changes nothing about what it does.")
    f.onBox = Part(G.Checkbox(e, function(on)
        if not selected then return end
        local ok, why = LR().SetEnabled(selected, on)
        if not ok then P.Say(why, "warn") end
        P.QueueRefresh()
    end))
    R.Interact.Tip(f.onBox, "Turned on", "Off, this rule is never used. On, it can choose for you while automatic rolling is on, with a countdown you can stop. An incomplete rule does nothing either way.")
    f.onText = Part(G.Text(e, "small"))
    f.summary = Part(G.Text(e, "small")); f.summary:SetWordWrap(true); f.summary:SetJustifyV("TOP")
    f.tools = {}
    local tools = {
        { "Move up", function() LR().Move(selected, -1) end, "Moves this rule up: rules are read from the top, and the first that applies decides." },
        { "Move down", function() LR().Move(selected, 1) end, "Moves this rule down." },
        { "Duplicate", function()
            local ok, copy = LR().Duplicate(selected)
            if ok then P.Select(copy); P.Say("Made an independent copy. It starts off.", "ok") else P.Say(copy, "warn") end
        end, "Makes a copy of this rule, switched off, under it." },
        { "Delete...", function() P.Delete(selected) end, "Deletes this rule, after asking." },
    }
    for i, t in ipairs(tools) do
        local b = Part(G.Button(e, t[1], 90, i == 4 and "danger" or "secondary", function() if selected then t[2]() P.QueueRefresh() end end))
        R.Interact.Tip(b, t[1], t[3])
        f.tools[i] = b
    end
    f.whenTitle = Part(G.Text(e, "heading"))
    f.whenHelp = Part(G.Text(e, "small")); f.whenHelp:SetWordWrap(true)
    f.matchAll = Part(Segment(e, "All of these", function() if selected then LR().SetMatch(selected, "all"); P.QueueRefresh() end end))
    f.matchAny = Part(Segment(e, "Any of these", function() if selected then LR().SetMatch(selected, "any"); P.QueueRefresh() end end))
    f.addCond = Part(G.Button(e, "+ Add condition...", 150, "secondary", function()
        if not selected then return end
        local choices = {}
        for _, kind in ipairs(R.LootRules.ORDER) do choices[#choices + 1] = { value = kind, label = R.LootRules.TYPES[kind].label } end
        G.ContextMenu(f.addCond, choices, function(kind)
            local ok, why = LR().AddCondition(selected, kind)
            if not ok then P.Say(why, "warn") end
            P.QueueRefresh()
        end)
    end))
    f.thenTitle = Part(G.Text(e, "heading"))
    f.actions = {}
    for _, key in ipairs({ "none", "need", "greed", "pass" }) do
        local b = Part(R.FrameLook.Toggle(e, ACTION_WORD[key], 120, function()
            if selected then LR().SetAction(selected, key); P.QueueRefresh() end
        end))
        b:SetHeight(32)
        if b.text then
            if b.text.SetFont then b.text:SetFont(STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]], 14, "") end
            b.text:ClearAllPoints(); b.text:SetPoint("CENTER", b, "CENTER", 14, 0); b.text:SetWidth(80); b.text:SetJustifyH("CENTER"); b.text:SetWordWrap(false)   -- beside the icon, not under it
        end
        b.icon = b:CreateTexture(nil, "OVERLAY"); b.icon:SetSize(22, 22); b.icon:SetPoint("LEFT", 14, 0)
        if key == "none" then
            b.icon:Hide(); b.text:ClearAllPoints(); b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
        else R.Icons.Apply(b.icon, ACTION_ICON[key], 22) end
        f.actions[key] = b
    end
    R.Interact.Tip(f.actions.none, "No change to rolling", "This rule makes no roll decision. Other matching roll rules can still choose.")
    R.Interact.Tip(f.actions.need, "Need", "Chooses Need. Only done automatically once you allow Need above, and never when the game doesn't offer it.")
    R.Interact.Tip(f.actions.greed, "Greed", "Chooses Greed.")
    R.Interact.Tip(f.actions.pass, "Pass", "Chooses Pass.")
    f.displayTitle = Part(G.Text(e, "heading")); f.displays = {}
    for _, key in ipairs({ "none", "expanded", "collapsed" }) do
        local b = Part(R.FrameLook.Toggle(e, Ru().DISPLAY_LABEL[key], 120, function()
            if selected then LR().SetDisplay(selected, key); P.QueueRefresh() end
        end))
        b:SetHeight(32); f.displays[key] = b
    end
    R.Interact.Tip(f.displays.none, "No change to display", "Skip this rule for presentation; the next applicable display rule can decide.")
    R.Interact.Tip(f.displays.expanded, "Expanded", "Use the full card for this roll and its victory notification. Does not choose a roll.")
    R.Interact.Tip(f.displays.collapsed, "Collapsed (Mini)", "Use a compact card with normal roll controls. A manual toggle overrides it for this roll only.")
    f.gate = Part(G.Text(e, "small")); f.gate:SetWordWrap(true)
    f.autoTitle = Part(G.Text(e, "heading"))
    f.delayIcon = Part(e:CreateTexture(nil, "ARTWORK")); f.delayIcon:SetSize(24, 24)
    f.delayLabel = Part(G.Text(e, "body"))
    f.delay = Part(G.Slider(e, 200, function(value)
        if selected then LR().SetDelay(selected, math.floor(value + 0.5)); P.QueueRefresh() end
    end))
    R.Interact.Tip(f.delay, "Wait before rolling", "How long the card counts down before the rule chooses, in seconds. You can stop it, roll at once, or choose another way at any time before it ends. A countdown never ends in the last second of a roll.")
    f.resultIcon = Part(e:CreateTexture(nil, "ARTWORK")); f.resultIcon:SetSize(24, 24)
    f.resultLabel = Part(G.Text(e, "body"))
    f.resultBox = Part(G.Checkbox(e, function(on) if selected then LR().SetShowResult(selected, on); P.QueueRefresh() end end))
    R.Interact.Tip(f.resultBox, "Show the result afterward", "Off: the card goes soon after the choice. On: it stays a while with the result, when the game gives one.")
    f.bar = Part(CreateFrame("Frame", nil, e, "BackdropTemplate"))
    M.PanelFace(f.bar, "canvas")
    f.barIcon = f.bar:CreateTexture(nil, "ARTWORK"); f.barIcon:SetSize(22, 22); f.barIcon:SetPoint("LEFT", 12, 0)
    f.barText = G.Text(f.bar, "body"); f.barText:SetPoint("LEFT", 44, 0); f.barText:SetWordWrap(true)
    f.previewRule = Part(G.Button(e, "Preview this rule", 150, "secondary", function()
        local v = selected and LR().Rule(selected)
        if not v then return end
        if v.incomplete then P.Say("Finish the rule first: " .. v.incomplete, "warn") P.QueueRefresh() return end
        local ok, why = R.LootCards.PreviewStart({ name = v.name, action = v.action, display = v.display, delay = v.delay })
        if not ok then P.Say(why or "Can't preview now.", "warn") else P.Say(nil) end
        P.QueueRefresh()
    end))
    R.Interact.Tip(f.previewRule, "Preview this rule", "Shows a made-up roll with this rule's independent roll and display actions. Display-only rules leave the sample choice manual. Nothing is actually rolled.")
    f.say = Part(G.Text(e, "small")); f.say:SetWordWrap(true)
    built = true
    f:SetScript("OnSizeChanged", function() P.QueueRefresh() end)
    f:SetScript("OnHide", function()
        epoch = epoch + 1
        queued = false
        local G2 = Wg()
        if G2.CloseMenu then G2.CloseMenu() end
    end)
    return f
end

function P.Frame()
    if not f then Build() end
    return f
end
-- What has been built, read only (for the tests and the simulator).
function P.Parts() return { frame = f, rows = rows, conds = conds } end

if R.OnSettingsClosed then R.OnSettingsClosed(function() epoch = epoch + 1; queued = false end) end
if R.LootRolls then R.LootRolls.Subscribe(function(what) if what == "rules" or what == "profile" then P.QueueRefresh() end end) end

local function Count()
    local n, on = 0, 0
    for _, v in ipairs(R.LootRolls.List()) do
        n = n + 1
        if v.enabled then on = on + 1 end
    end
    return n, on
end

K.Page({
    key = "lootRules", name = "Loot rules", nav = "Loot rules", parent = "lootRolls", order = 27,
    description = "Rules that choose Need, Greed or Pass for you, with a countdown you can stop.",
    keywords = "loot rule rules automatic auto roll need greed pass recipe quality green uncommon equipment equippable wear armor type cloth leather mail plate profession known duplicate item upgrade condition countdown pause stop",
    when = function() return R.LootRolls ~= nil and R.LootCards ~= nil end,
    build = function()
        local lr = R.LootRolls
        local Under = K.Under
        local BOOL, NUMBER = K.BOOL, K.NUMBER
        local function Setting(key, varType, label, set)
            local name = "lootRolls" .. key:sub(1, 1):upper() .. key:sub(2)
            return K.Proxy(name, varType, label, lr.DEFAULTS[key], function() return lr.Get(key) end, set or function(v) lr.Set(key, v) end)
        end
        K.Card({
            title = "Automatic rolling", icon = "lootRolls", switch = false,
            what = "Lets your rules choose Need, Greed or Pass for you. Off until you turn it on. Every choice starts as a visible countdown on the card, which you can stop, roll at once, or answer yourself.",
            summary = function()
                if lr.Get("paused") then return "Paused" end
                if not lr.Get("auto") then return "Off: nothing is chosen for you" end
                return lr.Get("autoNeed") and "On, Need allowed" or "On, Need stays yours"
            end,
            consequence = "Needs loot cards turned on (a countdown must be shown). With nothing matching, or anything unclear (an item the game hasn't described, a recipe's tooltip missing), the roll is left to you. Stopping a countdown never passes. Choosing yourself always wins.",
            details = {
                { "Who decides when rules overlap?", "Rules are read from the top; the first that applies decides, and two rules are never combined. A rule that can't be checked stops the search, so a rule below it never speaks for it." },
                { "Why is Need a separate switch?", "Need can take an item from someone else, so a rule may choose it only when you allow that here, and never when the game doesn't offer it." },
                { "Why are upgrade rules separate too?", "\"Potential upgrade\" is a hint from the gear comparison, not a decision. A rule that asks about it counts only when you allow that here." },
            },
        })
        local auto = K.Checkbox(Setting("auto", BOOL, "Roll automatically using my rules", function(v) lr.Set("auto", v and true or false) end),
            "On: a rule that matches an item starts a countdown on its card, and when it ends (and everything still holds) sends its choice once. Off: nothing is chosen for you.")
        local function On() return lr.Get("auto") end
        local why = "Greyed out: turn on \"Roll automatically\" first."
        Under(K.Checkbox(Setting("paused", BOOL, "Pause automatic rolling", function(v) lr.Set("paused", v and true or false) end),
            "Stops every countdown now and starts none, without changing a rule. Rolling by hand still works. It stays paused after a reload until you turn it off."), auto, On, why)
        Under(K.Checkbox(Setting("autoNeed", BOOL, "Allow rules to choose Need", function(v) lr.Set("autoNeed", v and true or false) end),
            "Off (the default): a rule that would choose Need does nothing and says so on the card. On: it counts down like any other, and only when the game offers Need for that item."), auto, On, why)
        Under(K.Checkbox(Setting("autoUpgrade", BOOL, "Allow rules that ask about upgrades", function(v) lr.Set("autoUpgrade", v and true or false) end),
            "Off (the default): a rule with a \"Potential upgrade\" condition does nothing. On: it counts, using TwichUI's gear comparison, which is a hint and not a promise."), auto, On, why)
    end,
    host = function() return P.Frame() end, hostHeight = function() return P.Height() end,
})
