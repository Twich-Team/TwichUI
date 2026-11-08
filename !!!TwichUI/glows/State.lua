-- TwichUI: Action bar glows, what the game says
-- Reads the game into the observation Logic.lua decides from. Every answer that is a secret value, or that the client
-- does not give, is nil (unknown), and Logic never glows on an unknown. Reading is split by what changes it, so the
-- controller (Controller.lua) reads again only what an event made stale; the rest it keeps.
--
-- What the client provides (read from the Forever UI source, Blizzard_APIDocumentationGenerated):
--   C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL") (secret when auras are restricted: then unknown)
--   C_PaperDollInfo.GetTemporaryEnchantmentInfo(INVSLOT_MAINHAND / INVSLOT_OFFHAND): nothing when the slot has none
--   C_Minimap.GetNumTrackingTypes / GetTrackingInfo(i) -> { name, active, type, spellID } ("spell" tracking only)
--   C_Spell.GetSpellCooldown(id) -> { isActive, isOnGCD (both never secret), startTime, duration (secret when restricted) }
--   C_Spell.IsSpellUsable(id) -> usable, notEnoughPower; C_Spell.IsSpellInRange(id, unit) -> true / false / nil
--   C_SpellBook.GetSpellBookItemInfo(i, Player) -> { spellID, name, subName ("Rank 3") }, C_SpellBook.IsSpellKnown(id)
--   C_Item.GetItemCount(id) (the bags you carry), C_Item.GetItemSpell(id) (the spell an item casts)

local R = TwichUI
local C = R.BarGlowCatalog
local BT = R.BarGlowButtons
local ST = {}
R.BarGlowState = ST

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end
local function Lower(s) return type(s) == "string" and s ~= "" and s:lower() or nil end
local function Wipe(t) for k in pairs(t) do t[k] = nil end end
local MAX_AURAS = 40

---------------------------------------------------------------------------
-- Names (kept: the client's names don't change in a session; misses are not kept, the data may arrive later)
---------------------------------------------------------------------------
local spellNames, spellDisplay, itemNames = {}, {}, {}

function ST.Display(id)
    if not id then return nil end
    local n = spellDisplay[id]
    if n then return n end
    if C_Spell and C_Spell.GetSpellName then n = Plain(C_Spell.GetSpellName(id)) end
    if (type(n) ~= "string" or n == "") and GetSpellInfo then n = Plain((GetSpellInfo(id))) end
    if type(n) ~= "string" or n == "" then return nil end
    spellDisplay[id], spellNames[id] = n, n:lower()
    return n
end
function ST.Name(id)
    if not id then return nil end
    if spellNames[id] then return spellNames[id] end
    local n = ST.Display(id)
    return n and n:lower() or nil
end
function ST.ItemDisplay(id)
    if not id then return nil end
    local n = itemNames[id]
    if n then return n end
    if C_Item and C_Item.GetItemNameByID then n = Plain(C_Item.GetItemNameByID(id)) end
    if (type(n) ~= "string" or n == "") and GetItemInfo then n = Plain((GetItemInfo(id))) end
    if type(n) ~= "string" or n == "" then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        return nil
    end
    itemNames[id] = n
    return n
end
function ST.ItemSpell(id)
    if not (id and C_Item and C_Item.GetItemSpell) then return nil end
    local name = Plain(C_Item.GetItemSpell(id))
    return Lower(name)
end

---------------------------------------------------------------------------
-- The spell book: which spells you know (by name too) and the highest rank of each
---------------------------------------------------------------------------
local book = { names = {}, best = {}, read = false }

local function RankOf(sub)
    if type(sub) ~= "string" then return nil end
    return tonumber(sub:match("(%d+)%s*$"))
end

function ST.ReadBook()
    Wipe(book.names); Wipe(book.best)
    book.read = false
    local SB = C_SpellBook
    if not (SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo) then return end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local lines = Plain(SB.GetNumSpellBookSkillLines()) or 0
    for l = 1, lines do
        local line = SB.GetSpellBookSkillLineInfo(l)
        local offset = line and Plain(line.itemIndexOffset)
        local count = line and Plain(line.numSpellBookItems)
        if type(offset) == "number" and type(count) == "number" then
            for i = offset + 1, offset + count do
                local info = SB.GetSpellBookItemInfo(i, bank)
                local id = info and Plain(info.spellID)
                local name = info and Lower(Plain(info.name))
                if id and name and not Plain(info.isPassive) then
                    book.names[name] = true
                    local rank = RankOf(Plain(info.subName))
                    local cur = book.best[name]
                    if rank and (not cur or rank > cur.rank) then book.best[name] = { rank = rank, id = id } end
                end
            end
        end
    end
    book.read = true
end

function ST.Known(id)
    if not id then return false end
    local SB = C_SpellBook
    if SB and SB.IsSpellKnown and Plain(SB.IsSpellKnown(id)) == true then return true end
    if IsPlayerSpell and Plain(IsPlayerSpell(id)) == true then return true end
    if IsSpellKnown and Plain(IsSpellKnown(id)) == true then return true end
    local n = ST.Name(id)
    return n ~= nil and book.names[n] == true
end

-- Buttons holding a lower rank than the highest in your book (only a spell placed directly, never a macro: a macro
-- names its rank on purpose). Each spell once, with all its buttons that hold a lower rank.
function ST.Ranks()
    if not book.read then return nil end
    local byName, out = {}, {}
    for _, b in ipairs(BT.Spells()) do
        local best = book.best[b.name]
        if best and best.id ~= b.spell then
            local sub = C_Spell and C_Spell.GetSpellSubtext and Plain(C_Spell.GetSpellSubtext(b.spell))
            local rank = RankOf(sub)
            if rank and rank < best.rank then
                local r = byName[b.name]
                if not r then
                    local key = b.name:gsub("[^%w]", "")
                    r = { key = key ~= "" and key or "spell" .. b.spell, name = b.name, display = ST.Display(b.spell) or b.name, spell = b.spell, buttons = {} }
                    byName[b.name] = r
                    out[#out + 1] = r
                end
                r.buttons[#r.buttons + 1] = b.button
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Context
---------------------------------------------------------------------------
function ST.Context()
    local ctx = {}
    ctx.combat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and Plain(UnitAffectingCombat("player"))) or false
    ctx.combat = ctx.combat and true or false
    ctx.resting = IsResting and Plain(IsResting()) == true or false
    ctx.dead = UnitIsDeadOrGhost and Plain(UnitIsDeadOrGhost("player")) == true or false
    ctx.taxi = UnitOnTaxi and Plain(UnitOnTaxi("player")) == true or false
    local enemy = false
    if UnitExists and Plain(UnitExists("target")) then
        enemy = UnitCanAttack and Plain(UnitCanAttack("player", "target")) == true
            and not (UnitIsDead and Plain(UnitIsDead("target")) == true)
    end
    ctx.enemy = enemy and true or false
    if IsInRaid and IsInRaid() then ctx.group = "raid"
    elseif IsInGroup and IsInGroup() then ctx.group = "party"
    else ctx.group = "none" end
    return ctx
end

---------------------------------------------------------------------------
-- Auras: the lower-case names of the helpful auras on a unit, or nil when any of it is secret
---------------------------------------------------------------------------
function ST.AuraNames(unit)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local set = {}
    for i = 1, MAX_AURAS do
        local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if a == nil then break end
        if issecretvalue and issecretvalue(a) then return nil end
        local name = Plain(a.name)
        if name == nil then return nil end
        set[name:lower()] = true
    end
    return set
end

---------------------------------------------------------------------------
-- Weapons: whether each hand has a temporary enchant, and whether there is a weapon in the off hand
---------------------------------------------------------------------------
local MAIN, OFF = rawget(_G, "INVSLOT_MAINHAND") or 16, rawget(_G, "INVSLOT_OFFHAND") or 17

local function HasEnchant(slot)
    local PD = C_PaperDollInfo
    -- the game's own buff frame reads them this way (Blizzard_BuffFrame/BuffFrame.lua): a list per weapon slot
    if C_Item and C_Item.GetWeaponEnchantInfo then
        local ws = Enum and Enum.WeaponSlot
        local which = slot == MAIN and (ws and ws.MainHand or 0) or (ws and ws.OffHand or 1)
        local ok, list = pcall(C_Item.GetWeaponEnchantInfo, which)
        if ok and type(list) == "table" and not (issecretvalue and issecretvalue(list)) then
            for _, e in pairs(list) do
                if type(e) == "table" and Plain(e.hasEnchant) == true then return true end
            end
            return false
        end
    end
    if PD and PD.GetTemporaryEnchantmentInfo then
        local info = PD.GetTemporaryEnchantmentInfo(slot)
        if issecretvalue and issecretvalue(info) then return nil end
        return info ~= nil
    end
    -- the old global is a compatibility wrapper on this client and may call what is not there: guarded
    if GetWeaponEnchantInfo then
        local ok, hasMain, _, _, _, hasOff = pcall(GetWeaponEnchantInfo)
        if not ok then return nil end
        if slot == MAIN then return Plain(hasMain) and true or false end
        return Plain(hasOff) and true or false
    end
    return nil
end

local function IsWeapon(slot)
    local id = GetInventoryItemID and Plain(GetInventoryItemID("player", slot))
    if not id then return false end
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
    classID = Plain(classID)
    if classID == nil then return nil end
    local weapon = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
    return classID == weapon
end

function ST.Weapon()
    local main = IsWeapon(MAIN)
    if main == nil then return nil end
    local w = { offHandWeapon = IsWeapon(OFF) == true }
    -- no weapon in the main hand: nothing to enchant there
    if main then w.mainHand = HasEnchant(MAIN) end
    if w.offHandWeapon then w.offHand = HasEnchant(OFF) end
    return w
end

---------------------------------------------------------------------------
-- Tracking: whether any spell tracking is on (nil while the list can't be read)
---------------------------------------------------------------------------
function ST.Tracking()
    local M = C_Minimap
    if not (M and M.GetNumTrackingTypes and M.GetTrackingInfo) then return nil end
    local n = Plain(M.GetNumTrackingTypes())
    if type(n) ~= "number" then return nil end
    local anySpell = false
    for i = 1, n do
        local info = M.GetTrackingInfo(i)
        if type(info) == "table" and Plain(info.type) == "spell" then
            anySpell = true
            if Plain(info.active) == true then return true end
        end
    end
    if anySpell then return false end
    return nil
end

---------------------------------------------------------------------------
-- Cooldowns and usability
---------------------------------------------------------------------------
-- ready (true/false/nil), and when it ends (a GetTime value) if that can be read.
function ST.Cooldown(id)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local info = C_Spell.GetSpellCooldown(id)
    if type(info) ~= "table" then return nil end
    if info.isEnabled == false then return false end            -- on hold (starts when something else ends)
    if info.isActive == false or info.isOnGCD == true then return true end
    if info.isActive ~= true then return nil end
    local start, duration = Plain(info.startTime), Plain(info.duration)
    if type(start) == "number" and type(duration) == "number" then return false, start + duration end
    return false
end

function ST.Usable(id)
    if not (C_Spell and C_Spell.IsSpellUsable) then return nil end
    local usable, noPower = C_Spell.IsSpellUsable(id)
    usable, noPower = Plain(usable), Plain(noPower)
    if usable == nil and noPower == nil then return nil end
    -- a reactive spell whose moment has come but rage is short still counts: the moment is what matters
    return usable == true or noPower == true
end

function ST.Count(id)
    if not id then return nil end
    if C_Item and C_Item.GetItemCount then return Plain(C_Item.GetItemCount(id)) end
    if GetItemCount then return Plain(GetItemCount(id)) end
    return nil
end

---------------------------------------------------------------------------
-- Group members in range (out of combat; each unit's auras kept until that unit's auras change)
---------------------------------------------------------------------------
local memberAuras = {}   -- [unit] = set or false (unknown)

function ST.UnitAurasChanged(unit) memberAuras[unit] = nil end
function ST.RosterChanged() Wipe(memberAuras) end

function ST.Members(group)
    local out = {}
    if not (UnitExists and UnitIsUnit and UnitIsConnected and UnitIsDeadOrGhost and UnitName and UnitClass) then return out end
    local prefix, max = "party", 4
    if group == "raid" then prefix, max = "raid", 40 end
    for i = 1, max do
        local unit = prefix .. i
        if Plain(UnitExists(unit)) and not Plain(UnitIsUnit(unit, "player"))
            and Plain(UnitIsConnected(unit)) and not Plain(UnitIsDeadOrGhost(unit))
            and (not UnitCanAssist or Plain(UnitCanAssist("player", unit))) then
            local name = Plain(UnitName(unit))
            local _, class = UnitClass(unit)
            class = Plain(class)
            if name and class then
                local auras = memberAuras[unit]
                if auras == nil then
                    auras = ST.AuraNames(unit) or false
                    memberAuras[unit] = auras
                end
                out[#out + 1] = {
                    unit = unit, name = name, class = class, mana = C.MANA[class] == true, auras = auras or nil,
                    inRange = function(spell)
                        if not (C_Spell and C_Spell.IsSpellInRange) then return nil end
                        return Plain(C_Spell.IsSpellInRange(spell, unit))
                    end,
                }
            end
        end
    end
    return out
end

function ST.Snapshot()
    local n = 0
    for _ in pairs(memberAuras) do n = n + 1 end
    local names = 0
    for _ in pairs(spellNames) do names = names + 1 end
    return { memberAuras = n, names = names, bookRead = book.read }
end
