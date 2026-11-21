-- TwichUI Fishing: fishing lures on the pole
--
-- What is on the pole: C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot.MainHand), a list of { hasEnchant, enchantType,
-- timeLeft (milliseconds), charges, enchantID } (Blizzard_APIDocumentationGenerated/ItemDocumentation.lua; the game's buff
-- frame reads it this way), with the older global GetWeaponEnchantInfo() as a fallback. Only the main hand is read, and only
-- while a fishing pole is worn there.
--
-- A temporary enchant on the pole is not assumed to be a lure: an enchant id becomes "a lure" when it appears right after the
-- fishing key applied one (TwichUIFishingDB learned.enchants). Any temporary enchant already on the pole still stops another
-- lure from being used over it, so nothing is wasted; it is reported as unidentified until learned.
--
-- Applying is always the player's key press: the fishing key's secure action is type "item" with the lure and
-- "target-slot" 16, which SecureTemplates.lua answers by using the item and then UseInventoryItem(16) while the spell waits
-- for a target item. A lure is applied only when the pole has no temporary enchant (or, with config lure.early, when the one
-- it has ends within that many seconds), never during a cast: the key reels while a line is out.

local R = TwichUI
local F = R.Fishing
local S = F.Store
local G = F.Gear
local L = {}
F.Lure = L

local pending = nil       -- { item, at, before }: the key just applied a lure
L.APPLY_SECONDS = 4

local function ReadEnchant()
    if C_Item and C_Item.GetWeaponEnchantInfo then
        local E = rawget(_G, "Enum")
        local which = E and E.WeaponSlot and E.WeaponSlot.MainHand or 0
        local ok, list = pcall(C_Item.GetWeaponEnchantInfo, which)
        if ok and type(list) == "table" and F.Readable(list) ~= nil then
            for _, e in pairs(list) do
                if type(e) == "table" and F.Readable(e.hasEnchant) == true then
                    local ms = F.Num(e.timeLeft)
                    return true, ms and ms > 0 and ms / 1000 or nil, F.Count(e.enchantID)
                end
            end
            return false
        end
    end
    if GetWeaponEnchantInfo then
        local ok, has, ms, _, id = pcall(GetWeaponEnchantInfo)
        if not ok then return nil end
        has = F.Readable(has)
        if has == nil then return nil end
        if not has then return false end
        ms = F.Num(ms)
        return true, ms and ms > 0 and ms / 1000 or nil, F.Count(id)
    end
    return nil
end
L.ReadEnchant = ReadEnchant

-- { state, seconds, enchantID, lure, identified }
--   state: "no-pole" | "none" | "active" | "expiring" | "unknown" (the client didn't say)
function L.Status()
    if not G.PoleWorn() then return { state = "no-pole" } end
    local has, seconds, enchantID = ReadEnchant()
    if has == nil then return { state = "unknown" } end
    if not has then return { state = "none" } end
    local lure = S.LureEnchant(enchantID)
    local warn = S.Get("lure.warn") or 60
    local state = (seconds and seconds <= warn) and "expiring" or "active"
    return { state = state, seconds = seconds, enchantID = enchantID, lure = type(lure) == "number" and lure or nil,
        identified = lure ~= nil }
end

-- The lures in the bags, best first: { { item, bag, slot, count, bonus } }.
function L.Available()
    local found, byItem = {}, {}
    G.EachBagItem(function(e)
        local info = F.LURES[e.item]
        if info then
            local have = byItem[e.item]
            if have then have.count = have.count + e.count
            else
                have = { item = e.item, bag = e.bag, slot = e.slot, count = e.count, bonus = info.bonus }
                byItem[e.item] = have
                found[#found + 1] = have
            end
        end
    end)
    table.sort(found, function(a, b)
        if a.bonus ~= b.bonus then return a.bonus > b.bonus end
        return a.item < b.item
    end)
    return found
end

-- Which lure to use: the preferred one if it is in the bags; otherwise, when no lure is preferred or alternatives are
-- allowed, the best one there. Returns the entry, or nil and why ("no-lure" | "preferred-missing").
function L.Choose()
    local list = L.Available()
    local want = S.Get("lure.preferred")
    if want then
        for _, e in ipairs(list) do if e.item == want then return e end end
        if not S.Get("lure.alternative") then return nil, "preferred-missing" end
    end
    if list[1] then return list[1] end
    return nil, "no-lure"
end

-- What the fishing key should do about the lure: { kind = "lure", item, bag, slot } or nil (and why not, for status).
function L.Plan()
    if not S.Get("lure.auto") then return nil, "off" end
    if pending and F.Clock() < pending.at + L.APPLY_SECONDS then return nil, "applying" end
    local st = L.Status()
    if st.state == "no-pole" or st.state == "unknown" then return nil, st.state end
    if st.state == "active" or st.state == "expiring" then
        local early = S.Get("lure.early") or 0
        if not (early > 0 and st.seconds and st.seconds <= early) then return nil, "active" end
    end
    local e, why = L.Choose()
    if not e then return nil, why end
    return { kind = "lure", item = e.item, bag = e.bag, slot = e.slot }
end

-- The key is about to apply a lure.
function L.BeginApply(plan)
    local _, _, before = ReadEnchant()
    pending = { item = plan.item, at = F.Clock(), before = before }
    if C_Timer and C_Timer.After then C_Timer.After(L.APPLY_SECONDS + 0.1, function() L.CheckApply() end) end
end

function L.CheckApply()
    if not pending or F.Clock() < pending.at + L.APPLY_SECONDS then return end
    pending = nil
    F.Note("lure-failed", "no lure appeared on the pole")
    F.Emit("LURE", "failed")
end

-- WEAPON_ENCHANT_CHANGED / UNIT_INVENTORY_CHANGED("player"): learn the enchant a lure the key applied put on the pole.
local lastState
function L.OnEnchantChanged()
    local has, _, enchantID = ReadEnchant()
    if pending and has and enchantID and enchantID ~= pending.before then
        S.LearnEnchant(enchantID, pending.item)
        pending = nil
        F.Emit("LURE", "applied", enchantID)
    end
    local st = L.Status().state
    if st ~= lastState then
        if lastState == "active" or lastState == "expiring" then
            if st == "none" then F.Emit("LURE", "expired") end
        end
        lastState = st
        F.Emit("LURE", "status", st)
    end
end

function L.Pending() return pending ~= nil end
