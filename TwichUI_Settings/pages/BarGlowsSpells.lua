-- TwichUI settings: Action bar glows › Spells and looks (glows/Config.lua). One kind at a time: its defaults row (the
-- kind on or off and its look), then each of its spells or items with an on/off box, a look of its own, a reset and,
-- for what you added, Remove. One editor below for whichever row is chosen, with a sample button that glows as you
-- change it, and a way to add a spell or item by its ID, a link or by dragging it here. A frame of this window's own,
-- built the first time it is shown; rows are made as needed and reused. Every change goes through Config.lua.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.BarGlowsSpellsPage = P

local W = 644
local ROW_H, VISIBLE = 30, 8
local LIST_TOP = -104
local LIST_H = ROW_H * VISIBLE + 8
local LIST_W = W - 12 - 26
local EDIT_TOP = -44
local EDIT_H = 262
local ADD_TOP = -44
local HOST_H = -ADD_TOP + 150

local f, built
local rows = {}
local kind = "missingBuff"
local task = "list"
local target                     -- the row being edited: { kind, key } (key nil: the kind's defaults)
local addKind, addAs, addSlot = "readyCooldown", "spell", "both"
local refreshQueued = false

local function Wg() return R.SettingsWidgets end
local function BG() return R.BarGlows end
local function Cat() return R.BarGlowCatalog end
local function ST() return R.BarGlowState end

local function MyClass()
    local _, class = UnitClass("player")
    return class
end

function P.Say(text, tone)
    P.lastSaid, P.lastTone = text, tone
    if not (f and f.note) then return end
    local pal = Wg().pal
    f.note:SetText(text or "")
    Wg().Color(f.note, tone == "warn" and pal.danger.text or (tone == "ok" and pal.sage or pal.textDim))
end

---------------------------------------------------------------------------
-- The rows of a kind: its defaults, then its entries
---------------------------------------------------------------------------
local function SpellLabel(id, fallback)
    return (id and ST().Display(id)) or fallback or (id and ("Spell " .. id)) or "?"
end
local function ItemLabel(id, fallback)
    return (id and ST().ItemDisplay(id)) or fallback or (id and ("Item " .. id)) or "?"
end

-- { key, label, known (nil: can't tell), added, spell, item, icon }
local function EntriesOf(k)
    local bg, C = BG(), Cat()
    local out = {}
    if k == "oldRank" then
        local seen = {}
        for _, r in ipairs(ST().Ranks() or {}) do
            seen[r.key] = true
            out[#out + 1] = { key = r.key, label = r.display, known = true, found = true }
        end
        for _, key in ipairs(bg.StoredKeys("oldRank")) do
            if not seen[key] then out[#out + 1] = { key = key, label = key, known = nil } end
        end
        return out
    end
    for _, e in ipairs(C.For(k, MyClass())) do
        local label = e.spell and SpellLabel(e.spell, e.label) or (e.reagent and ItemLabel(e.reagent, e.label)) or e.label
        local known
        if e.spell then known = ST().Known(e.spell)
        elseif e.items then
            local n = 0
            for _, id in ipairs(e.items) do n = n + (ST().Count(id) or 0) end
            known = n > 0
        elseif e.spells then
            known = false
            for _, id in ipairs(e.spells) do if ST().Known(id) then known = true end end
        end
        out[#out + 1] = { key = e.key, label = label, known = known, spell = e.spell, item = e.reagent or (e.items and e.items[1]), entry = e }
    end
    for _, a in ipairs(bg.Added()) do
        if a.kind == k then
            local key = bg.AddedKey(a)
            local label = a.spell and SpellLabel(a.spell) or ItemLabel(a.item)
            out[#out + 1] = { key = key, label = label, known = a.spell and ST().Known(a.spell) or nil, added = true,
                spell = a.spell, item = a.item, slot = a.slot }
        end
    end
    return out
end

local function KindChoices()
    local C, out = Cat(), {}
    for _, k in ipairs(C.LIST_ORDER) do
        local info = C.TYPE_INFO[k]
        out[#out + 1] = { value = k, label = ("%s (%d)"):format(info.label, #EntriesOf(k)), tooltip = info.tip }
    end
    return out
end

-- The style a target is drawn with: a kind's defaults, or an entry's resolved look.
local function TargetStyle(t)
    local bg = BG()
    if not t then return nil end
    if t.key then return bg.Style(t.kind, t.key) end
    local s = {}
    for _, field in ipairs(bg.STYLE_ORDER) do s[field] = bg.TypeField(t.kind, field) end
    return s
end

---------------------------------------------------------------------------
-- The editor
---------------------------------------------------------------------------
local function Choices(list)
    local out = {}
    for _, c in ipairs(list) do out[#out + 1] = { value = c[1], label = c[2], tooltip = c[3] } end
    return out
end
local function SecondsChoices(list, zero)
    local out = {}
    for _, n in ipairs(list) do out[#out + 1] = { value = n, label = n == 0 and zero or (n .. " s") } end
    return out
end
local function LabelIn(list, v)
    for _, c in ipairs(list) do if c.value == v then return c.label end end
    return tostring(v)
end

local function SetField(field, v)
    if not target then return end
    local bg = BG()
    local ok
    if target.key then ok = bg.SetSpellField(target.kind, target.key, field, v)
    else ok = bg.SetTypeField(target.kind, field, v) end
    if not ok then P.Say("That value can't be used here.", "warn") end
end

local function PaintEditor()
    if not (f and built) then return end
    local bg, C = BG(), Cat()
    local open = target ~= nil
    for _, part in ipairs(f.editorParts) do part:SetShown(open) end
    f.editHint:Hide()
    f.listHost:SetShown(not open and task == "list")
    f.editorHost:SetShown(open)
    f.addHost:SetShown(not open and task == "add")
    f.browse:SetSelected(not open and task == "list"); f.addTask:SetSelected(not open and task == "add")
    local mode = open and "edit" or task
    if f.mode ~= mode then
        f.mode = mode
        C_Timer.After(0, function() if f:IsShown() and R.SettingsUI and R.SettingsUI.Refresh then R.SettingsUI.Refresh() end end)
    end
    if not open then
        if f.sample then R.BarGlowDraw.Clear(f.sample) end
        return
    end
    local s = TargetStyle(target)
    local info = C.TYPE_INFO[target.kind]
    if target.key then
        f.editTitle:SetText(("Look of %s"):format(target.label or target.key))
        f.editSub:SetText(bg.SpellHasOwnLook(target.kind, target.key) and "It has a look of its own; what you leave alone follows the defaults."
            or ("It follows the %s defaults until you change something here."):format(info.label:lower()))
    else
        f.editTitle:SetText(("Defaults for %s"):format(info.label:lower()))
        f.editSub:SetText("The look of every row of this kind, unless a row has its own.")
    end
    f.look:SetValue(s.look, LabelIn(f.lookChoices, s.look))
    f.motion:SetValue(s.motion, LabelIn(f.motionChoices, s.motion))
    f.color:SetValue(s.color)
    f.opacity:SetValue(s.opacity)
    f.size:SetValue(s.size)
    f.speed:SetValue(s.speed)
    f.thickness:SetValue(s.thickness)
    f.thickness:SetActive(s.look == "pixel")
    f.speed:SetActive(s.motion ~= "still")
    f.when:SetValue(s.when, LabelIn(Choices(bg.WHENS), s.when))
    f.glowTime:SetValue(s.glowTime, LabelIn(SecondsChoices(bg.GLOW_TIMES, "Until done"), s.glowTime))
    f["repeat"]:SetValue(s["repeat"], LabelIn(SecondsChoices(bg.REPEATS, "Off"), s["repeat"]))
    f.message:SetChecked(s.message)
    f.sound:SetValue(s.sound, s.sound == bg.NO_SOUND and "None" or s.sound)
    local limits = target.kind == "lowReagent" or target.kind == "lowStock"
    f.belowLabel:SetShown(limits and target.key ~= nil)
    f.below:SetShown(limits and target.key ~= nil)
    if limits and target.key then f.below:SetValue(bg.Below(target.kind, target.key)) end
    f.reset:SetText(target.key and "Use the defaults" or "Reset the defaults")
    -- the sample: this entry's icon, glowing as it would
    local icon
    if target.key then
        local e = C.Find(target.kind, target.key)
        local a = bg.FindAdded(target.kind, target.key)
        local spell = (e and (e.spell or (e.spells and e.spells[1]))) or (a and a.spell)
        local item = (e and (e.reagent or (e.items and e.items[1]))) or (a and a.item)
        if spell and C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(spell) end
        if not icon and item and C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(item) end
    end
    f.sampleIcon:SetTexture(icon or 134400)
    R.BarGlowDraw.Set(f.sample, s)
end

function P.Edit(k, key, label)
    target = { kind = k, key = key, label = label }
    if built then PaintEditor() end
end

function P.CloseEditor()
    target = nil
    if built then PaintEditor() end
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
    row.check = G.Checkbox(row, function(on)
        if not row.data then return end
        local bg = BG()
        if row.data.defaults then bg.SetTypeEnabled(kind, on) else bg.SetSpellEnabled(kind, row.data.key, on) end
    end)
    row.check:SetPoint("LEFT", 8, 0)
    I.Tip(row.check, "On", function()
        if row.data and row.data.defaults then return "Turns the whole kind on or off. While it is off, none of its rows glow (their own choices are kept)." end
        return "Turns this one on or off. It glows only while its kind is on too."
    end)
    row.chip = G.Solid(row, "ARTWORK", { 1, 1, 1 }, 1)
    row.chip:SetSize(12, 12)
    row.chip:SetPoint("LEFT", 34, 0)
    row.name = G.Text(row, "body")
    row.name:SetPoint("TOPLEFT", 54, -3)
    row.name:SetWidth(330)
    row.name:SetWordWrap(false)
    row.detail = G.Text(row, "meta")
    row.detail:SetPoint("TOPLEFT", 54, -17)
    row.detail:SetWidth(330)
    row.detail:SetWordWrap(false)
    row.look = G.Button(row, "Look", 58, "secondary", function()
        if not row.data then return end
        if row.data.defaults then P.Edit(kind, nil) else P.Edit(kind, row.data.key, row.data.label) end
    end)
    row.look:SetPoint("RIGHT", -146, 0)
    I.Tip(row.look, "Look", "Opens the editor below for this row: the glow's art, color, strength, size, speed and motion, when it shows, its timing, message and sound.")
    row.reset = G.Button(row, "Reset", 60, "secondary", function()
        if not row.data then return end
        local bg = BG()
        if row.data.defaults then bg.ResetType(kind) else bg.ResetSpell(kind, row.data.key) end
        P.Say(("%s: back to the defaults."):format(row.data.label), "ok")
    end)
    row.reset:SetPoint("RIGHT", -80, 0)
    I.Tip(row.reset, "Reset", "Forgets this row's own look (and limit). Its on/off is kept.")
    row.remove = G.Button(row, "Remove", 70, "secondary", function()
        if not row.data or not row.data.added then return end
        local label = row.data.label
        if BG().Remove(kind, row.data.key) then
            if target and target.key == row.data.key then P.CloseEditor() end
            P.Say(("Removed %s."):format(label), "ok")
        end
    end)
    row.remove:SetPoint("RIGHT", -6, 0)
    I.Tip(row.remove, "Remove", "Removes what you added, with its look. Built-in rows can only be turned off.")
    rows[i] = row
    return row
end

local function Paint(row, data)
    local G, bg = Wg(), BG()
    local pal = G.pal
    row.data = data
    local s = data.defaults and TargetStyle({ kind = kind }) or bg.Style(kind, data.key)
    local r, g, b = R.BarGlowDraw.Rgb(s.color)
    row.chip:SetColorTexture(r, g, b, 1)
    local on = data.defaults and bg.TypeEnabled(kind) or (not data.defaults and bg.SpellEnabled(kind, data.key))
    row.check:SetChecked(on)
    row.check:SetActive(data.defaults or bg.TypeEnabled(kind))
    row.name:SetText(data.label)
    local faded = data.known == false or not on or (not data.defaults and not bg.TypeEnabled(kind))
    G.Color(row.name, faded and pal.stone or pal.text)
    local parts = {}
    if data.defaults then
        parts[#parts + 1] = "Defaults for every row of this kind"
    else
        parts[#parts + 1] = bg.SpellHasOwnLook(kind, data.key) and "Own look" or "Follows the defaults"
        if data.added then parts[#parts + 1] = "added by you" end
        if data.known == false then parts[#parts + 1] = (data.spell and "not learned") or "none carried" end
        if kind == "lowReagent" or kind == "lowStock" then parts[#parts + 1] = ("low below %d"):format(bg.Below(kind, data.key)) end
        if kind == "oldRank" and data.found then parts[#parts + 1] = "on your bars now" end
    end
    row.detail:SetText(table.concat(parts, "  \194\183  "))
    row.reset:SetShown(data.defaults or bg.SpellHasOwnLook(kind, data.key))
    row.remove:SetShown(data.added == true)
end

function P.Refresh()
    if not (f and built and f:IsShown()) then return end
    local G, C = Wg(), Cat()
    local list = { { defaults = true, label = ("All %s"):format(C.TYPE_INFO[kind].label:lower()) } }
    for _, e in ipairs(EntriesOf(kind)) do list[#list + 1] = e end
    for i, data in ipairs(list) do
        local row = Row(i)
        Paint(row, data)
        row:Show()
    end
    for i = #list + 1, #rows do
        rows[i].data = nil
        rows[i]:Hide()
    end
    f.content:SetHeight(math.max(1, #list * ROW_H))
    f.kind:SetValue(kind, C.TYPE_INFO[kind].label)
    f.kindTip:SetText(C.TYPE_INFO[kind].tip)
    f.empty:SetShown(#list == 1)
    if target and target.key and target.kind == kind then
        local still = false
        for _, e in ipairs(list) do if e.key == target.key then still = true; target.label = e.label end end
        if not still then target = nil end
    end
    PaintEditor()
    P.PaintAdd()
end

local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.1, function()
        refreshQueued = false
        P.Refresh()
    end)
end

---------------------------------------------------------------------------
-- Adding a spell or item
---------------------------------------------------------------------------
local ADD_WHY = {
    invalid = "Type a spell or item ID (a whole number), paste a link, or drag a spell or item here.",
    duplicate = "That is already in the list.",
    full = "That is the most there can be. Remove one first.",
}

-- The ID typed, pasted (a link) or dropped, and whether it is a spell or an item (nil: as chosen).
function P.ParseId(text)
    if type(text) ~= "string" then return nil end
    local spell = text:match("|Hspell:(%d+)") or text:match("^%s*spell:(%d+)%s*$")
    if spell then return tonumber(spell), "spell" end
    local item = text:match("|Hitem:(%d+)") or text:match("^%s*item:(%d+)%s*$")
    if item then return tonumber(item), "item" end
    local n = text:match("^%s*(%d+)%s*$")
    if n then return tonumber(n), nil end
    return nil
end

local function AddKinds()
    local C, bg, out = Cat(), BG(), {}
    for _, k in ipairs(bg.ADDABLE_ORDER) do out[#out + 1] = { value = k, label = C.TYPE_INFO[k].label, tooltip = C.TYPE_INFO[k].tip } end
    return out
end

function P.PaintAdd()
    if not (f and built) then return end
    local bg, C = BG(), Cat()
    if not bg.ADDABLE[addKind] then addKind = "readyCooldown" end
    local can = bg.ADDABLE[addKind]
    if not can[addAs] then addAs = can.spell and "spell" or "item" end
    f.addKind:SetValue(addKind, C.TYPE_INFO[addKind].label)
    f.addAs:SetValue(addAs, addAs == "spell" and "Spell" or "Item")
    f.addAs:SetActive(can.spell and can.item)
    f.addSlot:SetShown(addKind == "weaponBuff")
    f.addSlotLabel:SetShown(addKind == "weaponBuff")
    f.addSlot:SetValue(addSlot, addSlot == "both" and "Either hand" or (addSlot == "mainHand" and "Main hand" or "Off hand"))
    local auraField = addKind == "missingBuff" and addAs == "item"
    f.addAura:SetShown(auraField)
    f.addAuraLabel:SetShown(auraField)
end

function P.Add()
    local bg = BG()
    local id, as = P.ParseId(f.addId:GetText())
    if not id then P.Say(ADD_WHY.invalid, "warn") return false, "invalid" end
    as = as or addAs
    if not bg.ADDABLE[addKind][as] then
        P.Say(("A %s takes %s, not %s."):format(Cat().TYPE_INFO[addKind].label:lower(), as == "spell" and "an item" or "a spell", as == "spell" and "a spell" or "an item"), "warn")
        return false, "kind"
    end
    local entry = { kind = addKind }
    local label
    if as == "spell" then
        label = ST().Display(id)
        if not label then P.Say(("The game knows no spell %d."):format(id), "warn") return false, "unknown" end
        entry.spell = id
    else
        local known = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(id)
        if not known then P.Say(("The game knows no item %d."):format(id), "warn") return false, "unknown" end
        entry.item = id
        label = ST().ItemDisplay(id) or ("Item " .. id)
        if addKind == "missingBuff" then
            local aura = P.ParseId(f.addAura:GetText())
            if aura then entry.aura = aura end
        end
    end
    if addKind == "weaponBuff" then entry.slot = addSlot end
    local ok, why, builtin = bg.Add(entry)
    if not ok then
        if why == "builtin" and builtin then
            P.Say(("%s is already listed under %s; turn it on or off on its row."):format(label, Cat().TYPE_INFO[addKind].label:lower()), "warn")
        else
            P.Say(ADD_WHY[why] or "That could not be added.", "warn")
        end
        return false, why
    end
    f.addId:SetText("")
    f.addAura:SetText("")
    f.addId:ClearFocus()
    kind = addKind
    task = "list"
    P.Say(("Added %s under %s."):format(label, Cat().TYPE_INFO[addKind].label:lower()), "ok")
    P.Refresh()
    return true
end

-- A spell or item dropped on the field: its ID goes in as text (nothing is used or picked up for good).
local function TakeCursor(box)
    if not GetCursorInfo then return end
    local what, a, _, c = GetCursorInfo()
    if what == "spell" and c then box:SetText("spell:" .. c)
    elseif what == "item" and a then box:SetText("item:" .. a)
    else return end
    if ClearCursor then ClearCursor() end
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Build()
    built = true
    local G, I, bg = Wg(), R.Interact, BG()
    local pal = G.pal

    f.listHost = CreateFrame("Frame", nil, f); f.listHost:SetAllPoints()
    f.editorHost = CreateFrame("Frame", nil, f); f.editorHost:SetAllPoints()
    f.addHost = CreateFrame("Frame", nil, f); f.addHost:SetAllPoints()
    local function Choose(value) target = nil; task = value; P.Refresh() end
    f.browse = G.Tab(f, "Your spells and items", 310, function() Choose("list") end)
    f.browse:SetPoint("TOPLEFT", 0, -2)
    f.addTask = G.Tab(f, "Add a spell or item", 322, function() Choose("add") end)
    f.addTask:SetPoint("TOPLEFT", 316, -2)
    f.help = G.Text(f.listHost, "small")
    f.help:SetPoint("TOPLEFT", 4, -42)
    f.help:SetWidth(W - 230)
    f.help:SetText("Pick a kind, then choose a row's Look. The first row sets its defaults.")
    I.Tip(f, "Spells and looks", "Each spell or item can be turned off or given its own look. Faded names are spells you haven't learned or items you don't carry. The first row controls the shared defaults for this kind.")
    f.kind = G.Dropdown(f.listHost, 200, function(value)
        kind = value
        if target and target.kind ~= kind then target = nil end
        P.Refresh()
    end)
    f.kind:SetChoices(KindChoices)
    f.kind:SetPoint("TOPRIGHT", -2, -44)
    I.Tip(f.kind, "Kind", "Which kind of glow to list.")
    f.kindTip = G.Text(f.listHost, "meta")
    f.kindTip:SetPoint("TOPLEFT", 4, -84)
    f.kindTip:SetWidth(W - 8)
    f.kindTip:SetWordWrap(false)

    f.well = CreateFrame("Frame", nil, f.listHost, "BackdropTemplate")
    f.well:SetPoint("TOPLEFT", 0, LIST_TOP)
    f.well:SetSize(W, LIST_H)
    G.Well(f.well)
    f.scroll, f.content = G.Scroll(f.well, LIST_W)
    f.scroll:SetPoint("TOPLEFT", 6, -4)
    f.scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    f.empty = G.Text(f.well, "small")
    f.empty:SetPoint("TOPLEFT", 12, -ROW_H - 10)
    f.empty:SetWidth(W - 24)
    f.empty:SetText("Nothing of this kind for your class. Add a spell or item below.")

    -- the editor
    local y = EDIT_TOP
    G.Card(f.editorHost, 0, y, W, y - EDIT_H)
    f.editorParts = {}
    local function Part(x) f.editorParts[#f.editorParts + 1] = x; return x end
    f.editHint = G.Text(f.editorHost, "small")
    f.editHint:SetPoint("TOPLEFT", 12, y - 14)
    f.editHint:SetWidth(W - 24)
    f.editHint:SetText("Click Look on a row to change how it glows. The sample button here glows as you change it.")
    f.editTitle = Part(G.Text(f.editorHost, "heading"))
    f.editTitle:SetPoint("TOPLEFT", 12, y - 10)
    f.editTitle:SetWidth(W - 120)
    f.editSub = Part(G.Text(f.editorHost, "meta"))
    f.editSub:SetPoint("TOPLEFT", 12, y - 26)
    f.editSub:SetWidth(W - 120)

    -- the sample: an icon in the shape of an action button, glowing as the look is set
    f.sample = Part(CreateFrame("Frame", nil, f.editorHost))
    f.sample:SetSize(40, 40)
    f.sample:SetPoint("TOPRIGHT", f, "TOPLEFT", W - 30, y - 16)
    f.sampleIcon = f.sample:CreateTexture(nil, "ARTWORK")
    f.sampleIcon:SetAllPoints()
    I.Tip(f.sample, "Sample", "This glows the way the look is set now. Your bars follow the same look.")

    local function Label(text, x, dy)
        local t = Part(G.Text(f.editorHost, "meta"))
        t:SetPoint("TOPLEFT", x, y - dy)
        t:SetText(text)
        return t
    end
    local function Drop(x, dy, w, choices, field, tip)
        local d = Part(G.Dropdown(f.editorHost, w, function(v) SetField(field, v) end))
        d:SetChoices(choices)
        d:SetPoint("TOPLEFT", x, y - dy)
        I.Tip(d, field, tip)
        return d
    end
    local function Slide(x, dy, lo, hi, step, field, tip)
        local s = Part(G.Slider(f.editorHost, 220, function(v) SetField(field, math.floor(v + 0.5)) end))
        s:SetRange(lo, hi, step)
        s:SetPoint("TOPLEFT", x, y - dy)
        I.Tip(s, field, tip)
        return s
    end

    f.lookChoices = Choices(bg.LOOKS)
    f.motionChoices = Choices(bg.MOTIONS)
    Label("Art", 12, 54)
    f.look = Drop(70, 50, 150, function() return f.lookChoices end, "look", "The glow's art: the game's spell alert, marching ants, a soft frame or a crisp pixel border.")
    Label("Motion", 236, 54)
    f.motion = Drop(290, 50, 130, function() return f.motionChoices end, "motion", "Moving: it runs around the button. Breathing: it stands still and fades out and in. Still: no movement at all.")
    Label("Color", 436, 54)
    f.color = Part(G.Swatch(f.editorHost, function(hex) SetField("color", hex) end))
    f.color:SetPoint("TOPLEFT", 480, y - 52)
    I.Tip(f.color, "Color", "The glow's color, and its message's. Click to choose another.")

    Label("Strength %", 12, 88)
    f.opacity = Slide(90, 84, 10, 100, 5, "opacity", "How strong the glow is, 10 to 100%.")
    Label("Size %", 330, 88)
    f.size = Slide(390, 84, 70, 170, 5, "size", "How far past the button's edge the glow reaches, 70 to 170% of its usual size.")
    Label("Speed %", 12, 122)
    f.speed = Slide(90, 118, 25, 300, 5, "speed", "How fast it runs around or breathes, 25 to 300%. Not used while it stands still.")
    Label("Thickness", 330, 122)
    f.thickness = Slide(390, 118, 1, 6, 1, "thickness", "The pixel border's thickness in screen pixels. Only for the pixel border.")

    Label("When", 12, 156)
    f.when = Drop(70, 152, 150, function()
        local out = {}
        for _, c in ipairs(Choices(bg.WHENS)) do
            if target and bg.WhenFits(target.kind, c.value) then out[#out + 1] = c end
        end
        return out
    end, "when", "When it may show: always, only in combat, only out of combat, or only while a living enemy is your target. Low reagents and low stock also have Alert in town: the button glows anywhere, and the message and sound come only in a town or an inn.")
    Label("Glow time", 236, 156)
    f.glowTime = Drop(300, 152, 110, function() return SecondsChoices(bg.GLOW_TIMES, "Until done") end, "glowTime",
        "How long the glow shows once it is due, and again with each repeat. Until done: the whole time, until you cast the buff, use the cooldown ...")
    Label("Repeat", 426, 156)
    f["repeat"] = Drop(476, 152, 100, function() return SecondsChoices(bg.REPEATS, "Off") end, "repeat",
        "Every so many seconds while it is still due, the glow, message and sound come again. Off: once, as it starts.")

    f.message = Part(G.Checkbox(f.editorHost, function(on) SetField("message", on) end))
    f.message:SetPoint("TOPLEFT", 12, y - 188)
    I.Tip(f.message, "Message", "A small card in the zone arrival card's look as it starts (and with each repeat), with the spell's name and what is wanted. How long it stays and whether it shows the icon are on the General tab. Never in chat.")
    local msgLabel = Label("Show a message", 54, 190)
    msgLabel:SetWidth(140)
    Label("Sound", 236, 190)
    f.sound = Part(G.Dropdown(f.editorHost, 220, function(v) SetField("sound", v) end))
    f.sound:SetChoices(function()
        local out = { { value = bg.NO_SOUND, label = "None" } }
        local s = target and TargetStyle(target)
        for _, c in ipairs(R:SoundChoices(s and s.sound ~= bg.NO_SOUND and s.sound or nil)) do out[#out + 1] = { value = c[1], label = c[2] } end
        return out
    end)
    f.sound:SetPoint("TOPLEFT", 290, y - 186)
    I.Tip(f.sound, "Sound", "A sound as it starts (and with each repeat). TwichUI's sounds and any LibSharedMedia sound.")
    f.testSound = Part(G.Button(f.editorHost, "Play", 60, "secondary", function()
        local s = target and TargetStyle(target)
        if not s or s.sound == bg.NO_SOUND then P.Say("No sound is chosen.", "warn") return end
        local path = R:ResolveSound(s.sound)
        if path and PlaySoundFile then PlaySoundFile(path, "SFX") else P.Say("That sound isn't available.", "warn") end
    end))
    f.testSound:SetPoint("TOPLEFT", 520, y - 186)

    f.belowLabel = Part(Label("Low below", 12, 224))
    f.below = Part(G.Slider(f.editorHost, 220, function(v)
        if target and target.key then BG().SetBelow(target.kind, target.key, math.floor(v + 0.5)) end
    end))
    f.below:SetRange(0, 200, 1)
    f.below:SetPoint("TOPLEFT", 90, y - 220)
    I.Tip(f.below, "Low below", "It counts as low when you carry fewer than this. Reset puts back the shipped limit.")
    f.reset = Part(G.Button(f.editorHost, "Use the defaults", 150, "secondary", function()
        if not target then return end
        if target.key then BG().ResetSpell(target.kind, target.key) else BG().ResetType(target.kind) end
        P.Say("Back to the defaults.", "ok")
    end))
    f.reset:SetPoint("TOPRIGHT", f, "TOPLEFT", W - 112, y - 222)
    f.close = Part(G.Button(f.editorHost, "Close", 90, "secondary", function() P.CloseEditor() end))
    f.close:SetPoint("TOPRIGHT", f, "TOPLEFT", W - 12, y - 222)

    -- adding
    local ay = ADD_TOP
    G.Card(f.addHost, 0, ay, W, ay - 120)
    local addTitle = G.Text(f.addHost, "heading")
    addTitle:SetPoint("TOPLEFT", 12, ay - 10)
    addTitle:SetText("Add a spell or item")
    local function ALabel(text, x, dy)
        local t = G.Text(f.addHost, "meta")
        t:SetPoint("TOPLEFT", x, ay - dy)
        t:SetText(text)
        return t
    end
    ALabel("As", 12, 40)
    f.addKind = G.Dropdown(f.addHost, 160, function(v) addKind = v; P.PaintAdd() end)
    f.addKind:SetChoices(AddKinds)
    f.addKind:SetPoint("TOPLEFT", 40, ay - 36)
    I.Tip(f.addKind, "As", "What kind of glow it is. A low stock is an item; a seal, tracking, cooldown or proc a spell; a missing buff or weapon buff either.")
    f.addAs = G.Dropdown(f.addHost, 80, function(v) addAs = v; P.PaintAdd() end)
    f.addAs:SetChoices(function() return { { value = "spell", label = "Spell" }, { value = "item", label = "Item" } } end)
    f.addAs:SetPoint("TOPLEFT", 210, ay - 36)
    ALabel("ID", 302, 40)
    f.addId = G.EditBox(f.addHost, 140, 22)
    f.addId:SetPoint("TOPLEFT", 324, ay - 36)
    f.addId:SetMaxLetters(200)
    f.addId:SetScript("OnEnterPressed", function() P.Add() end)
    f.addId:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.addId:SetScript("OnReceiveDrag", function(self) TakeCursor(self) end)
    f.addId:SetScript("OnMouseDown", function(self) if GetCursorInfo and GetCursorInfo() then TakeCursor(self) end end)
    I.Tip(f.addId, "ID", "A spell or item ID, a link (shift-click one into this field), or drag a spell from your spellbook or an item from your bags here.")
    f.add = G.Button(f.addHost, "Add", 80, "secondary", function() P.Add() end)
    f.add:SetPoint("TOPRIGHT", f, "TOPLEFT", W - 12, ay - 35)
    f.addSlotLabel = ALabel("Hand", 12, 74)
    f.addSlot = G.Dropdown(f.addHost, 130, function(v) addSlot = v; P.PaintAdd() end)
    f.addSlot:SetChoices(function() return { { value = "both", label = "Either hand" }, { value = "mainHand", label = "Main hand" }, { value = "offHand", label = "Off hand" } } end)
    f.addSlot:SetPoint("TOPLEFT", 50, ay - 70)
    f.addAuraLabel = ALabel("Buff ID (optional)", 200, 74)
    f.addAura = G.EditBox(f.addHost, 110, 22)
    f.addAura:SetPoint("TOPLEFT", 310, ay - 70)
    f.addAura:SetMaxLetters(200)
    I.Tip(f.addAura, "Buff ID", "The buff the item gives, when it is not the item's own spell: for a food, the Well Fed buff's spell ID. Empty: the item's own spell.")
    f.note = G.Text(f, "small")
    f.note:SetPoint("BOTTOMLEFT", 12, 6)
    f.note:SetWidth(W - 24)
    f.note:SetWordWrap(false)
    P.Say(P.lastSaid, P.lastTone)
    PaintEditor()
end

function P.Frame()
    if f then return f end
    f = CreateFrame("Frame")
    f:SetSize(W, HOST_H)
    f:Hide()
    f:SetScript("OnShow", function()
        if not built then Build() end
        P.Refresh()
    end)
    f:SetScript("OnHide", function()
        if f.addId then f.addId:ClearFocus(); f.addAura:ClearFocus() end
        if f.sample then R.BarGlowDraw.Clear(f.sample) end
    end)
    return f
end

-- A change made anywhere (here, the General tab, a profile change) redraws the list if it is shown. Registered once.
if R.BarGlows then R.BarGlows.Subscribe(QueueRefresh) end

K.Page({
    key = "barGlowsSpells", name = "Action bar glow spells and looks", nav = "Spells and looks", parent = "barGlows", order = 64,
    description = "Every kind of glow and each of its spells or items: on or off, and how each one looks, when it shows, its message and sound.",
    keywords = "glow look color colour strength opacity size speed motion breathing ants pixel border spell alert sound message repeat glow time when combat add spell item id",
    when = function() return R.BarGlows ~= nil and R.BarGlowDraw ~= nil end,
    host = function() return P.Frame() end, hostHeight = function() return target and 340 or task == "add" and 204 or 382 end,
})
