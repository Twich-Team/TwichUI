-- TwichUI: Action bar glows, the buttons
-- Finds the action buttons on Blizzard's bars and on EllesmereUI's Action Bars, reads what each one holds, and keeps an
-- index: which buttons hold a spell (by its name, so every rank counts) and which hold an item. It only reads: nothing
-- of a button is changed here, no field is written on it and no script is hooked.
--
-- Where the buttons are (read from the Forever UI source and EllesmereUI's own files, ../reference_addons):
--   Blizzard: ActionButton1-12 (bar 1), MultiBarBottomLeftButton (2), MultiBarBottomRightButton (3), MultiBarRightButton (4),
--     MultiBarLeftButton (5), MultiBar5Button (6), MultiBar6Button (7), MultiBar7Button (8); each knows its slot as .action.
--   EllesmereUI: EABButton<n>, named after its bar's first slot and so never renamed by paging (EUI_ActionBars_Secure.lua's
--     BAR_SLOT_OFFSETS); the slot it shows now is its "action" attribute. Its stance bar reuses Blizzard's StanceButtons.
--   The stance bar: StanceButton1-10, each the form GetShapeshiftFormInfo(i) names.
-- What a slot holds: GetActionInfo(slot) -> "spell", id | "macro", id (GetMacroSpell / GetMacroItem) | "item", id.
--
--   BT.Map()            reads every button again (cheap: at most a few hundred calls); BT.Dirty() asks for it soon
--   BT.ForSpell(name)   the buttons holding a spell, by its lower-case name (a list; do not change it)
--   BT.ForItem(id)      the buttons holding an item
--   BT.Bar(button)      which bar a button is on ("bar1" ... "bar10", "stance")
--   BT.Spells()         { { button, spell, name } } of the buttons holding a spell directly (not a macro): for old ranks
--   BT.Each(fn)         fn(button, bar) for every button found

local R = TwichUI
local Perf = R.Perf
local BT = { generation = 0, mapped = 0 }
R.BarGlowButtons = BT

local BLIZZARD = {
    { "ActionButton", "bar1" }, { "MultiBarBottomLeftButton", "bar2" }, { "MultiBarBottomRightButton", "bar3" },
    { "MultiBarRightButton", "bar4" }, { "MultiBarLeftButton", "bar5" }, { "MultiBar5Button", "bar6" },
    { "MultiBar6Button", "bar7" }, { "MultiBar7Button", "bar8" },
}
-- EllesmereUI's bars by their first slot (its Bar9 and Bar10 are bars of its own, pages 2 and 10)
local ELLESMERE = {
    { 1, "bar1" }, { 61, "bar2" }, { 49, "bar3" }, { 25, "bar4" }, { 37, "bar5" },
    { 145, "bar6" }, { 157, "bar7" }, { 169, "bar8" }, { 13, "bar9" }, { 109, "bar10" },
}
local PER_BAR, STANCES = 12, 10

local bySpell, byItem, barOf, direct = {}, {}, {}, {}
local all = {}            -- { { button, bar } } every button found
local G = _G

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end
local function Wipe(t) for k in pairs(t) do t[k] = nil end end

local function SpellName(id)
    if not id then return nil end
    local name
    if C_Spell and C_Spell.GetSpellName then name = Plain(C_Spell.GetSpellName(id)) end
    if (type(name) ~= "string" or name == "") and GetSpellInfo then name = Plain((GetSpellInfo(id))) end
    if type(name) ~= "string" or name == "" then return nil end
    return name:lower()
end
BT.SpellName = SpellName

local function Push(map, key, button)
    local list = map[key]
    if not list then
        list = {}
        map[key] = list
    end
    for i = 1, #list do if list[i] == button then return end end
    list[#list + 1] = button
end

-- The slot a button shows now, or nil.
local function SlotOf(button)
    local slot = Plain(button.action)
    if type(slot) ~= "number" or slot <= 0 then
        local ok, v = pcall(button.GetAttribute, button, "action")
        slot = ok and Plain(v) or nil
        slot = tonumber(slot)
    end
    if type(slot) == "number" and slot > 0 then return slot end
    return nil
end

local function ItemFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- Adds what one action slot holds for this button.
local function AddSlot(button, slot)
    if not (GetActionInfo and slot) then return end
    local kind, id = GetActionInfo(slot)
    kind, id = Plain(kind), Plain(id)
    if kind == "spell" and type(id) == "number" then
        local name = SpellName(id)
        if name then
            Push(bySpell, name, button)
            direct[#direct + 1] = { button = button, spell = id, name = name }
        end
    elseif kind == "macro" and id then
        local spell = GetMacroSpell and Plain(GetMacroSpell(id))
        local name = spell and SpellName(spell)
        if name then Push(bySpell, name, button) end
        if GetMacroItem then
            local _, link = GetMacroItem(id)
            local item = ItemFromLink(Plain(link))
            if item then Push(byItem, item, button) end
        end
    elseif kind == "item" and type(id) == "number" then
        Push(byItem, id, button)
    end
end

local function Found(button, bar)
    if not button or barOf[button] then return false end
    barOf[button] = bar
    all[#all + 1] = { button = button, bar = bar }
    return true
end

function BT.Map()
    local pt = Perf.on and Perf.Start("glows.map")
    Wipe(bySpell); Wipe(byItem); Wipe(barOf); Wipe(direct); Wipe(all)
    for _, b in ipairs(BLIZZARD) do
        for i = 1, PER_BAR do
            local button = G[b[1] .. i]
            if Found(button, b[2]) then AddSlot(button, SlotOf(button)) end
        end
    end
    for _, b in ipairs(ELLESMERE) do
        for i = 0, PER_BAR - 1 do
            local button = G["EABButton" .. (b[1] + i)]
            if Found(button, b[2]) then AddSlot(button, SlotOf(button)) end
        end
    end
    local forms = GetNumShapeshiftForms and Plain(GetNumShapeshiftForms()) or 0
    for i = 1, math.min(STANCES, type(forms) == "number" and forms or 0) do
        local button = G["StanceButton" .. i]
        if Found(button, "stance") and GetShapeshiftFormInfo then
            local _, _, _, spell = GetShapeshiftFormInfo(i)
            local name = SpellName(Plain(spell))
            if name then Push(bySpell, name, button) end
        end
    end
    BT.generation = BT.generation + 1
    BT.mapped = #all
    BT.dirty = false
    if pt then Perf.Stop(pt) end
end

-- Asks for the buttons to be read again at the next look (coalesced by the controller).
function BT.Dirty() BT.dirty = true end

local NONE = {}
function BT.ForSpell(name) return name and bySpell[name] or NONE end
function BT.ForItem(id) return id and byItem[id] or NONE end
function BT.Bar(button) return barOf[button] end
function BT.Spells() return direct end
function BT.HasSpell(name) return name ~= nil and bySpell[name] ~= nil end
function BT.HasItem(id) return id ~= nil and byItem[id] ~= nil end
function BT.Each(fn) for _, b in ipairs(all) do fn(b.button, b.bar) end end

function BT.Snapshot()
    local spells, items = 0, 0
    for _ in pairs(bySpell) do spells = spells + 1 end
    for _ in pairs(byItem) do items = items + 1 end
    return { buttons = #all, spells = spells, items = items, generation = BT.generation }
end
