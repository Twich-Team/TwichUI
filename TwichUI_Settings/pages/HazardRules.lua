-- TwichUI settings: Hazard alerts › Rules (hazard/Config.lua). The auras you listed, each with an on/off box, a test,
-- Copy, Edit and Remove; and one editor for adding or changing a rule: the spell ID, a name, what to listen for (applied,
-- stacks grow, fades), the category (which sound) and the cooldown. A frame of this window's own, shown as the tab's page;
-- built the first time it is shown, with list rows made as needed and reused. Every change goes through Config.lua's own
-- functions, which check everything again.
-- Three different things are kept apart in the words here: a rule being configured, the game knowing the spell, and the
-- aura actually happening to you. Saving a rule proves only the first.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.HazardRulesPage = P

local W = 644                  -- the settings window's content width
local ROW_H, VISIBLE = 34, 5
local LIST_TOP = -58
local LIST_H = ROW_H * VISIBLE + 8
local LIST_W = W - 12 - 26
local EDIT_TOP = LIST_TOP - LIST_H - 12

local f, built
local rows = {}
local edit                       -- the editor's state: { id (nil: a new rule), trigger, category, throttle }
local refreshQueued = false

local function Wg() return R.SettingsWidgets end
local function HZ() return R.Hazard end

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

local WHY = {
    spell = "Type the spell ID, a whole number of at least 1.",
    name = "Give the rule a name (up to 60 characters, no | or control characters).",
    throttle = "The cooldown must be 0 to 5 seconds.",
    full = "That is the most rules there can be. Remove one first.",
    unavailable = "The rule could not be saved right now.",
}

local function ThrottleChoices()
    local out = {}
    for s = HZ().THROTTLE[1], HZ().THROTTLE[2] do out[#out + 1] = { value = s, label = s == 0 and "No cooldown" or (s .. " s") } end
    return out
end
local function ThrottleLabel(s) return s == 0 and "No cooldown" or (s .. " s") end

local function TriggerChoices()
    local out = {}
    for i, t in ipairs(HZ().TRIGGERS) do out[i] = { value = t[1], label = t[2] } end
    return out
end

local function CategoryChoices()
    local out = {}
    for i, c in ipairs(HZ().CATEGORIES) do out[i] = { value = c[1], label = c[2] } end
    return out
end

function P.Say(text, tone)
    P.lastSaid, P.lastTone = text, tone
    if not (f and f.note) then return end
    local pal = Wg().pal
    f.note:SetText(text or "")
    Wg().Color(f.note, tone == "warn" and pal.danger.text or (tone == "ok" and pal.sage or pal.textDim))
end

-- The game's name for a spell, when it has one cached. Never waits for one.
local function SpellName(id)
    local name = C_Spell and C_Spell.GetSpellName and Plain(C_Spell.GetSpellName(id))
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

---------------------------------------------------------------------------
-- The editor
---------------------------------------------------------------------------
-- The line under the editor's fields: what the game says about the spell, what the trigger means, and any overlap.
local function Hint()
    local hz = HZ()
    local text = f.spell:GetText() or ""
    local id = tonumber(text:match("^%s*(%d+)%s*$"))
    if not (id and hz.ValidSpell(id)) then
        return "The spell ID is the number in the spell's link on a database site or in its tooltip. Saving a rule only records it; it does not prove the game plays anything.", false
    end
    local parts = {}
    local name = SpellName(id)
    if name then
        parts[#parts + 1] = ("The game knows spell %d as \"%s\"."):format(id, name)
    else
        parts[#parts + 1] = ("The game has no name for spell %d yet: it may be uncached or specific to this server. The rule can still be saved."):format(id)
    end
    parts[#parts + 1] = hz.TRIGGER[edit.trigger][4] .. " Whether that aura really reaches you cannot be checked here; only the game's sound will tell."
    local twin = hz.Duplicate(id, edit.trigger, edit.id)
    if twin then
        parts[#parts + 1] = ("Your rule \"%s\" already listens for this."):format(twin.name)
    else
        local shadow = R.HazardRules.Shadows(id, edit.trigger)
        if shadow then parts[#parts + 1] = ("The built-in rule \"%s\" uses the same spell and trigger; yours takes its place while it is on."):format(shadow.name) end
    end
    return table.concat(parts, " "), twin ~= nil
end

local function PaintEditor()
    if not (f and built) then return end
    local open = edit ~= nil
    for _, part in ipairs(f.editorParts) do part:SetShown(open) end
    f.examples:SetShown(not open)
    if not open then return end
    f.editTitle:SetText(edit.id and "Edit rule" or "New rule")
    f.trigger:SetValue(edit.trigger, HZ().TRIGGER[edit.trigger][2])
    f.category:SetValue(edit.category, HZ().CATEGORY[edit.category][2])
    f.throttle:SetValue(edit.throttle, ThrottleLabel(edit.throttle))
    f.hint:SetText((Hint()))
end

function P.Open(id, copy)
    local hz = HZ()
    local rule = id and hz.Find(id)
    if id and not rule then
        P.Say("That rule isn't there any more.", "warn")
        return false
    end
    edit = { id = id, trigger = rule and rule.trigger or "applied", category = rule and rule.category or "low",
        throttle = rule and rule.throttle or hz.THROTTLE_DEFAULT }
    if not built then return true end
    f.spell:SetText(rule and tostring(rule.spell) or "")
    f.name:SetText(rule and rule.name or "")
    f.problem:SetText("")
    PaintEditor()
    f.spell:SetFocus()
    return true
end

function P.Close()
    edit = nil
    if not built then return end
    f.spell:ClearFocus(); f.name:ClearFocus()
    f.problem:SetText("")
    PaintEditor()
end

-- Saves the editor's rule. Returns true, or false and why.
function P.Save()
    if not edit then return false, "closed" end
    local hz = HZ()
    local fields = { spell = f.spell:GetText(), name = f.name:GetText(), trigger = edit.trigger, category = edit.category, throttle = edit.throttle }
    local ok, a, twin
    if edit.id then ok, a, twin = hz.Update(edit.id, fields) else ok, a, twin = hz.Add(fields) end
    if ok then
        P.Say(("%s \"%s\". It is registered with the game when the alerts are on."):format(edit.id and "Saved" or "Added", fields.name), "ok")
        P.Close()
        P.Refresh()
        return true
    end
    if a == "duplicate" then
        f.problem:SetText(("Your rule \"%s\" already listens for this spell and trigger. Edit that one instead."):format(twin and twin.name or "?"))
    else
        f.problem:SetText(WHY[a] or "That rule could not be saved.")
    end
    return false, a
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local TEST_WORDS = {
    none = "That category's sound is set to None, so there is nothing to play.",
    missing = "That sound is not available, so nothing played.",
    unavailable = "The game offers no way to play it right now.",
    refused = "The game refused to play that sound.",
}

local function Row(i)
    if rows[i] then return rows[i] end
    local G, I = Wg(), R.Interact
    local pal = G.pal
    local row = CreateFrame("Frame", nil, f.content)
    row:SetSize(LIST_W, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row.bg = G.Solid(row, "BACKGROUND", pal.text, (i % 2 == 0) and 0.035 or 0)
    row.bg:SetAllPoints()
    row.check = G.Checkbox(row, function(on) if row.rule then HZ().SetRuleEnabled(row.rule.id, on) end end)
    row.check:SetPoint("LEFT", 8, 0)
    I.Tip(row.check, "On", "On: the game plays this category's sound for the aura, while the alerts and the category are on. Off: kept, and not registered.")
    row.name = G.Text(row, "body")
    row.name:SetPoint("TOPLEFT", 36, -3)
    row.name:SetWidth(310)
    row.name:SetWordWrap(false)
    row.detail = G.Text(row, "meta")
    row.detail:SetPoint("TOPLEFT", 36, -18)
    row.detail:SetWidth(310)
    row.detail:SetWordWrap(false)
    row.test = G.Button(row, "Test", 48, "secondary", function()
        if not row.rule then return end
        local ok, why = R.HazardAlerts.TestSound(row.rule.category)
        if not ok then P.Say(TEST_WORDS[why] or "Nothing played.", "warn") end
    end)
    row.test:SetPoint("RIGHT", -222, 0)
    I.Tip(row.test, "Test", "Plays this rule's category sound once. It registers nothing and does not touch the rule's cooldown.")
    row.copy = G.Button(row, "Copy", 52, "secondary", function()
        if not row.rule then return end
        local ok, id, twin = HZ().DuplicateRule(row.rule.id)
        if ok then
            P.Say("Copied. The copy is off and listens for a different trigger; edit it, then turn it on.", "ok")
            P.Refresh()
            P.Open(id)
        else
            P.Say("This spell already has a rule for every trigger, so there is nothing left to copy to.", "warn")
        end
    end)
    row.copy:SetPoint("RIGHT", -164, 0)
    I.Tip(row.copy, "Copy", "Makes a switched-off copy for another trigger on the same spell, so you can change it before it plays.")
    row.edit = G.Button(row, "Edit", 52, "secondary", function() if row.rule then P.Open(row.rule.id) end end)
    row.edit:SetPoint("RIGHT", -106, 0)
    row.remove = G.Button(row, "Remove", 72, "secondary", function()
        if not row.rule then return end
        local id, name = row.rule.id, row.rule.name
        if HZ().Remove(id) then
            if edit and edit.id == id then P.Close() end
            P.Say(("Removed \"%s\"."):format(name), "ok")
        end
    end)
    row.remove:SetPoint("RIGHT", -6, 0)
    I.Tip(row.remove, "Remove", "Deletes this rule. Nothing else is changed.")
    rows[i] = row
    return row
end

function P.Refresh()
    if not (f and built and f:IsShown()) then return end
    local G, hz = Wg(), HZ()
    local pal = G.pal
    local list = hz.List()
    for i, rule in ipairs(list) do
        local row = Row(i)
        row.rule = rule
        row.name:SetText(rule.name)
        G.Color(row.name, rule.enabled and pal.text or pal.stone)
        local known = SpellName(rule.spell)
        row.detail:SetText(("Spell %d%s · %s · %s · %s"):format(rule.spell, known and (" (" .. known .. ")") or "",
            hz.TRIGGER[rule.trigger][2]:lower(), hz.CATEGORY[rule.category][2], ThrottleLabel(rule.throttle):lower()))
        row.check:SetChecked(rule.enabled)
        row:Show()
    end
    for i = #list + 1, #rows do
        rows[i].rule = nil
        rows[i]:Hide()
    end
    f.content:SetHeight(math.max(1, #list * ROW_H))
    f.empty:SetShown(#list == 0)
    f.count:SetText(("%d of %d"):format(#list, hz.MAX_CUSTOM))
    f.add:SetEnabled(#list < hz.MAX_CUSTOM)
    if edit and edit.id and not hz.Find(edit.id) then
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
    f.help:SetText("Auras that play a sound when they land on you, grow or fade. Only you: never your pets, group or other players. The game decides when a sound plays; TwichUI cannot see damage, so a rule says \"this aura happened to me\", not \"this hit was avoidable\".")
    f.add = G.Button(f, "Add a rule", 120, "secondary", function() P.Open(nil) end)
    f.add:SetPoint("TOPRIGHT", -2, -4)
    I.Tip(f.add, "Add a rule", function()
        if #HZ().List() >= HZ().MAX_CUSTOM then return "Opens the editor below.", WHY.full end
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
    f.empty:SetText("No rules yet. Add the spell ID of an aura you want to hear about; nothing is guessed for you.")

    -- the editor
    local y = EDIT_TOP
    G.Card(f, 0, y, W, y - 200)
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
    f.examples:SetText("Add a rule to hear a sound for an aura you choose.\n  Spell ID: the number from the aura's tooltip or database link.\n  Aura applied to me: when it is put on you. Stacks grow: each time its stack count rises. Fades from me: when it leaves.\n  Category: picks the sound (set on the General tab). Cooldown: the game's own wait between two plays, up to 5 seconds.")

    f.editTitle = Part(G.Text(f, "heading"))
    f.editTitle:SetPoint("TOPLEFT", 12, y - 10)

    local spellLabel = Part(G.Text(f, "meta"))
    spellLabel:SetPoint("TOPLEFT", 12, y - 38)
    spellLabel:SetText("Spell ID")
    f.spell = Part(G.EditBox(f, 90, 22))
    f.spell:SetPoint("TOPLEFT", 78, y - 34)
    f.spell:SetMaxLetters(10)
    f.spell:SetScript("OnEnterPressed", function() P.Save() end)
    f.spell:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.spell:SetScript("OnTextChanged", function() if edit and f.hint then f.hint:SetText((Hint())) end end)
    I.Tip(f.spell, "Spell ID", "The aura's spell ID on this client. IDs can differ between clients and servers, so check it in the game's own tooltip.")
    local nameLabel = Part(G.Text(f, "meta"))
    nameLabel:SetPoint("TOPLEFT", 190, y - 38)
    nameLabel:SetText("Name")
    f.name = Part(G.EditBox(f, 220, 22))
    f.name:SetPoint("TOPLEFT", 232, y - 34)
    f.name:SetMaxLetters(HZ().MAX_NAME)
    f.name:SetScript("OnEnterPressed", function() P.Save() end)
    I.Tip(f.name, "Name", "How the rule is listed. It is not sent anywhere.")

    local whenLabel = Part(G.Text(f, "meta"))
    whenLabel:SetPoint("TOPLEFT", 12, y - 72)
    whenLabel:SetText("When")
    f.trigger = Part(G.Dropdown(f, 190, function(value)
        if not edit then return end
        edit.trigger = value
        PaintEditor()
    end))
    f.trigger:SetChoices(TriggerChoices)
    f.trigger:SetPoint("TOPLEFT", 78, y - 68)
    local catLabel = Part(G.Text(f, "meta"))
    catLabel:SetPoint("TOPLEFT", 290, y - 72)
    catLabel:SetText("Category")
    f.category = Part(G.Dropdown(f, 170, function(value)
        if not edit then return end
        edit.category = value
        PaintEditor()
    end))
    f.category:SetChoices(CategoryChoices)
    f.category:SetPoint("TOPLEFT", 352, y - 68)
    I.Tip(f.category, "Category", "Picks the sound. It says how urgent you consider this, not how much damage it does.")
    local coolLabel = Part(G.Text(f, "meta"))
    coolLabel:SetPoint("TOPLEFT", 12, y - 106)
    coolLabel:SetText("Cooldown")
    f.throttle = Part(G.Dropdown(f, 130, function(value)
        if not edit then return end
        edit.throttle = value
        PaintEditor()
    end))
    f.throttle:SetChoices(ThrottleChoices)
    f.throttle:SetPoint("TOPLEFT", 78, y - 102)
    I.Tip(f.throttle, "Cooldown", "The least time the game waits between two plays of this one sound. The game allows 0 to 5 seconds, and no longer.")

    f.hint = Part(G.Text(f, "small"))
    f.hint:SetPoint("TOPLEFT", 12, y - 134)
    f.hint:SetWidth(W - 24)
    f.problem = Part(G.Text(f, "small"))
    f.problem:SetPoint("TOPLEFT", 12, y - 174)
    f.problem:SetWidth(W - 24 - 220)
    G.Color(f.problem, pal.danger.text)
    f.save = Part(G.Button(f, "Save", 96, "secondary", function() P.Save() end))
    f.save:SetPoint("TOPRIGHT", -112, y - 170)
    f.cancel = Part(G.Button(f, "Cancel", 90, "secondary", function() P.Close() end))
    f.cancel:SetPoint("TOPRIGHT", -12, y - 170)
    if edit then P.Open(edit.id) else PaintEditor() end
end

-- The page's frame (the settings window shows it under Hazard alerts). Built the first time it is shown.
function P.Frame()
    if f then return f end
    f = CreateFrame("Frame")
    f:Hide()
    f:SetScript("OnShow", function()
        if not built then Build() end
        P.Refresh()
    end)
    f:SetScript("OnHide", function()
        if f.spell then f.spell:ClearFocus(); f.name:ClearFocus() end
    end)
    return f
end

-- A change made anywhere (here, another tab, a profile change, an import) redraws the list if it is shown. Registered once.
if R.Hazard then R.Hazard.Subscribe(QueueRefresh) end

K.Page({
    key = "hazardRules", name = "Hazard alert rules", nav = "Rules", parent = "hazard", order = 43,
    description = "The auras you listed, by spell ID, with the category that picks each one's sound.",
    keywords = "hazard alert rule rules custom spell id aura debuff trigger cooldown category sound list",
    when = function() return R.Hazard ~= nil end,
    host = function() return P.Frame() end,
})
