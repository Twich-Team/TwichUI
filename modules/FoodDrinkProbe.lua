-- TEMPORARY: remove with the "probe" command in Core.lua and its line in the .toc.
-- /tui probe prints, in your own chat only, what the game says about each consumable in your
-- bags, so we can see whether food and drink can be told apart without an item list: class and
-- subclass, the item's use-spell and that spell's description, and the item tooltip's lines.
-- It changes nothing, uses nothing and sends nothing.

local R = TwichUI
local P = {}
R.FoodDrinkProbe = P

local function Safe(v)
    if v == nil then return "nil" end
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    return (tostring(v):gsub("|", "||"):gsub("\n", " / "))
end

local function Say(fmt, ...) print(R.GOLD .. "probe:|r " .. fmt:format(...)) end

function P.Run()
    if InCombatLockdown and InCombatLockdown() then Say("not in combat.") return end
    Say("locale %s; HEALTH = %s; MANA = %s", Safe(GetLocale()), Safe(HEALTH), Safe(MANA))
    local seen, shown, unloaded = {}, 0, false
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, last do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and not seen[id] then
                seen[id] = true
                local _, _, _, _, _, class, sub = C_Item.GetItemInfoInstant(id)
                if class == 0 then   -- consumables only
                    shown = shown + 1
                    local name, _, _, _, minLevel = C_Item.GetItemInfo(id)
                    local description = select(18, C_Item.GetItemInfo(id))
                    Say("|cffffffff%s|r  id %d  class %s/%s  needs level %s", Safe(name), id, Safe(class), Safe(sub), Safe(minLevel))
                    if description and description ~= "" then Say("  itemDescription: %s", Safe(description)) end
                    local spellName, spellID = C_Item.GetItemSpell(id)
                    if spellID then
                        local text = C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spellID)
                        if text == nil or text == "" then
                            unloaded = true
                            if C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(spellID) end
                        end
                        Say("  use-spell: %s (%s)", Safe(spellName), Safe(spellID))
                        Say("  spell description: %s", (text and text ~= "") and Safe(text) or "(empty: not loaded yet)")
                    else
                        Say("  use-spell: none")
                    end
                    local data = C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bag, slot)
                    for _, line in ipairs(data and data.lines or {}) do
                        local text = line.leftText
                        if text and text ~= "" then Say("  tooltip [%s]: %s", Safe(line.type), Safe(text)) end
                    end
                end
            end
        end
    end
    if shown == 0 then Say("no consumables in your bags.") end
    if unloaded then Say("some spell text was empty: run /tui probe again in a moment.") end
end
