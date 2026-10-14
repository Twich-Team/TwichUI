-- TwichUI: Quality of Life, Mage Conjuring Food & Drink
-- When enabled and the player is a mage with no food or drink items in their bags,
-- shows conjure food and water buttons instead of empty ones.
-- This feature requires the MageConjure module to be active.

local R = TwichUI
local Q = R.QoL
local M = R.MageConjure

local FC = {}
R.QoLMageConjureFoodDrink = FC

-- Check if player is a mage
local function IsPlayerMage()
    return M and M.ForPlayer() or false
end

-- Check if there are any consumable items in bags
local function HasConsumablesInBags()
    local hasFood = false
    local hasDrink = false
    
    -- Iterate through all bags to check for food and drink items
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local itemID = GetContainerItemID(bag, slot)
            if itemID then
                local _, _, _, _, _, itemType, itemSubType, _, _, _, _ = GetItemInfo(itemID)
                if itemType == "Consumable" then
                    if itemSubType == "Food" or itemSubType == "Feast" or itemSubType == "Pet Food" then
                        hasFood = true
                    elseif itemSubType == "Drink" then
                        hasDrink = true
                    end
                end
            end
        end
    end
    
    return hasFood, hasDrink
end

-- Function to check if conjured items should be shown (main logic)
function FC.ShouldShowConjuredItems()
    -- Only enable if player is a mage and has no consumables in bags 
    local food, drink = HasConsumablesInBags()
    return IsPlayerMage() and not (food or drink) and R:Enabled("qolMageConjureFoodDrink")
end

-- Setup the feature with proper event handling
FC.feature = Q.Add({
    key = "qolMageConjureFoodDrink",
    Events = function()
        -- This feature should only run if MageConjure is loaded and available
        if not M then return {} end
        
        local function OnBagsChanged()
            -- In a more complete implementation, this would update the UI
        end

        local function OnPlayerEnterWorld()
            -- In a more complete implementation, this would initialize state
        end

        return {
            ["BAG_UPDATE"] = OnBagsChanged,
            ["PLAYER_ENTERING_WORLD"] = OnPlayerEnterWorld
        }
    end,
    
    Stop = function()
        -- Clean up when feature is disabled
    end,
})

return FC