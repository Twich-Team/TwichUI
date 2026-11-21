-- TwichUI Test Lab: fishing (category "fishing"; docs/fishing.md, "In-game verification")
-- What TwichUI Fishing relies on, observed in the running client, and its fishing key's decision table run in the client's Lua.
-- Read only: nothing is cast, equipped, used, bound or changed. Values the client is not documented to give are REPORTED (t:Fact).

local R = TwichUI
local TL = R.TestLab

TL.Category{ id = "fishing", label = "Fishing", blurb = "What TwichUI Fishing relies on in this client, and its key's decisions (read only)" }

local function Has(t, k) return type(t) == "table" and type(t[k]) == "function" end

TL.Case{ id = "fishing.client.api", cat = "fishing", class = "readonly", budget = 3, run = function(t)
    t:Fact("fishing.api.weaponEnchantInfo", tostring(Has(C_Item, "GetWeaponEnchantInfo")))
    t:Fact("fishing.api.equipItemByName", tostring(Has(C_Item, "EquipItemByName")))
    t:Fact("fishing.api.isFishingLoot", tostring(type(IsFishingLoot) == "function"))
    t:Fact("fishing.api.lootSlotType", tostring(type(GetLootSlotType) == "function"))
    t:Fact("fishing.api.containerItemInfo", tostring(Has(C_Container, "GetContainerItemInfo")))
    t:Fact("fishing.api.equipmentSets", tostring(Has(C_EquipmentSet, "GetEquipmentSetID")))
    t:Fact("fishing.api.interactUnit", tostring(Has(C_PlayerInteractionManager, "InteractUnit")))
    t:Fact("fishing.api.softInteractUnit", tostring(type(UnitIsGameObject) == "function"))
    local E = rawget(_G, "Enum")
    t:Fact("fishing.enum.fishingpole", tostring(E and E.ItemWeaponSubclass and E.ItemWeaponSubclass.Fishingpole))
    t:Fact("fishing.slash.equipslot", tostring(rawget(_G, "SLASH_EQUIP_TO_SLOT1")))
    t:Fact("fishing.loot.selfFormat", tostring(rawget(_G, "LOOT_ITEM_SELF_MULTIPLE")))
    if C_CVar and C_CVar.GetCVar then
        for _, name in ipairs({ "SoftTargetInteract", "SoftTargetInteractArc", "SoftTargetInteractRange", "autoLootDefault" }) do
            local ok, v = pcall(C_CVar.GetCVar, name)
            t:Fact("fishing.cvar." .. name, ok and tostring(v) or "unreadable")
        end
    end
    if GetBindingKey then
        t:Fact("fishing.binding.interacttarget", tostring(GetBindingKey("INTERACTTARGET")))
        t:Fact("fishing.binding.twichui", tostring(GetBindingKey("CLICK TwichUIFishingButton:LeftButton")))
    end
    -- which Fishing spell id this client knows (seed list in TwichUI_Fishing/Data.lua)
    local known = {}
    for _, id in ipairs({ 7620, 7731, 7732, 18248, 33095, 51294, 88868, 110410, 131474, 131490, 131476, 158743, 377895, 1224771 }) do
        if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id) then known[#known + 1] = tostring(id) end
    end
    t:Fact("fishing.spell.known", #known > 0 and table.concat(known, ",") or "none")
    -- does a bag item's info carry hasLoot (how a container from fishing is recognised)?
    local seen = "no items"
    if Has(C_Container, "GetContainerItemInfo") then
        for slot = 1, 36 do
            local info = C_Container.GetContainerItemInfo(0, slot)
            if type(info) == "table" then seen = tostring(info.hasLoot ~= nil) break end
        end
    end
    t:Fact("fishing.container.hasLootField", seen)
    -- the main hand and its temporary enchant, as TwichUI Fishing reads them
    local F = R.Fishing
    if F and F.Gear and F.Lure then
        t:Fact("fishing.pole.worn", tostring(F.Gear.PoleWorn()))
        local st = F.Lure.Status()
        t:Fact("fishing.lure.state", tostring(st.state) .. (st.seconds and (" " .. math.floor(st.seconds) .. "s") or ""))
        t:Fact("fishing.next", F.API.Next().kind .. ":" .. tostring(F.API.Next().why))
    else
        t:Note("TwichUI Fishing is not loaded (type /tui fish, or bind its key): the module facts are not read.")
    end
    t:Check(true, "read")
end }

-- The decision table (pure: explicit contexts, nothing read from the game). Needs TwichUI Fishing loaded.
TL.Case{ id = "fishing.decide.table", cat = "fishing", class = "pure", budget = 2, run = function(t)
    local F = R.Fishing
    if not (F and F.Action and F.Action.Decide) then t:Skip("TwichUI Fishing is not loaded") return end
    local D = F.Action.Decide
    local equip = { kind = "equip", bag = 0, slot = 1 }
    local lure = { kind = "lure", bag = 0, slot = 2 }
    t:Same(D({ enabled = true, spell = 1 }).kind, "cast", "nothing to prepare: cast")
    t:Same(D({ enabled = true, spell = 1, combat = true, gear = equip }).why, "combat", "combat: nothing")
    t:Same(D({ enabled = true, spell = 1, line = "fishing", gear = equip }).why, "line-out", "a line out: never another cast")
    t:Same(D({ enabled = true, spell = 1, guard = true }).why, "guard", "just after a line: nothing")
    t:Same(D({ enabled = true, spell = 1, gear = equip, lure = lure }).kind, "equip", "the pole before the lure")
    t:Same(D({ enabled = true, spell = 1, lure = lure }).kind, "lure", "the lure before the cast")
end }
