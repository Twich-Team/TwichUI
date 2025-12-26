local T, W, I, C        = unpack(Twich)
---@type LootMonitorModule
local LM                = T:GetModule("LootMonitor")

---@class ValuationMethodData
---@field name string
---@field description string
---@field uid integer

---@class ValuationMethods
---@field VENDOR ValuationMethodData
---@field IGNORE ValuationMethodData
---@field TSM_PRICE_SOURCE ValuationMethodData
---@field DISENCHANT ValuationMethodData
---@field DISENCHANT_OR_VENDOR ValuationMethodData
---@field TSM_PRICE_SOURCE_WITH_GATE ValuationMethodData

---@class ItemValuator
---@field enabled boolean
local Valuator          = LM.ItemValuator or {}
LM.ItemValuator         = Valuator

---@type ConfigurationModule
local CM                = T:GetModule("Configuration")
---@type LoggerModule
local Logger            = T:GetModule("Logger")
---@type ThirdPartyAPIModule
local TPA               = T:GetModule("ThirdPartyAPI")
local TSM               = TPA.TSM
local callbackID        = nil;

local ARMOR_ITEM_CLASS  = Enum.ItemClass.Armor
local WEAPON_ITEM_CLASS = Enum.ItemClass.Weapon


---@type ValuationMethods
Valuator.VALUATION_METHODS = {
    VENDOR = { name = "Vendor Price", description = "Item will be valued at the price a vendor will pay for it.", uid = 1 },
    IGNORE = { name = "Ignore", description = "Items will not be included in any value calculations. Essentially, the item is worth 0c.", uid = 2 },
    TSM_PRICE_SOURCE = { name = "TSM Price Source", description = "The value will be obtained from the TradeSkillMaster price source chosen in configuration.", uid = 3 },
    DISENCHANT = { name = "Disenchant Value", description = "Item will be valued at its probable disenchant value, according to TSM algorithms. If item cannot be disenchanted, the item will be valued at the price a vendor will pay for it.", uid = 4 },
    DISENCHANT_OR_VENDOR = { name = "Disenchant or Vendor Price", description = "The value of the item will be the greater of either it's vendor value or its disenchanted value.", uid = 5 },
    TSM_PRICE_SOURCE_WITH_GATE = { name = "TSM Price Source with Gate", description = "The value will be obtained from the TradeSkillMaster price source chosen in the Loot Monitor configuration, if the sale rate is above the configured 'Minimum Sale Rate' value. If the sale rate is below the 'Minimum Sale Rate' value, the value of the item will be the greater of either it's vendor value or its disenchanted value.", uid = 6 },
}

--- @return boolean isEnabled true if the item valuator is enabled, false otherwise.
function Valuator:IsEnabled()
    return self.enabled or false
end

-- =====================================================
-- Valuation logic
-- =====================================================

Valuator.DECISIONS = {
    IGNORE = "ignore",
    VENDOR = "vendor",
    DISENCHANT = "disenchant",
    MARKET = "market",
    UNKNOWN = "unknown"
}

--- @param itemLink string The item looted (full item link).
--- @param quantity integer The quantity looted (stack size).
--- @param copperValue integer The per-item value in copper from the configured TSM price source.
--- @param saleRate number The per-item sale rate from TSM (0–1).
--- @param valuationMethod ValuationMethodData The valuation method to use.
--- @param isJunk boolean Whether the item is junk (poor quality).
--- @param vendorCopperValue integer Vendor sell value per item in copper.
--- @param minSaleRate number|nil The minimum sale rate threshold for the TSM price source with gate.
--- @return integer copperPerItem The per-item value in copper determined by the valuation.
--- @return integer totalCopper The total value in copper for this loot event.
--- @return string decision A normalized decision string: "ignore","vendor","disenchant","market", or "unknown".
local function RunValuationOnItem(
    itemLink, quantity, copperValue, saleRate, valuationMethod,
    isJunk, vendorCopperValue, minSaleRate
)
    -- Normalize
    quantity = quantity or 1
    if quantity <= 0 then quantity = 1 end
    copperValue = copperValue or 0
    saleRate = saleRate or 0
    vendorCopperValue = vendorCopperValue or 0

    -- Short helper for safe fallback to vendor value
    local function FallbackToVendor(reason)
        Logger.Error(("Valuation fallback to vendor for %s: %s"):format(itemLink or "nil", reason or "unknown"))
        return vendorCopperValue, vendorCopperValue * quantity, Valuator.DECISIONS.VENDOR
    end

    -- IGNORE: treat as worth 0
    if valuationMethod.uid == Valuator.VALUATION_METHODS.IGNORE.uid then
        Logger.Debug(("Item valuation: %s valued at 0c (ignored)."):format(itemLink or "nil"))
        return 0, 0, Valuator.DECISIONS.IGNORE
    end

    -- VENDOR: always vendor price
    if valuationMethod.uid == Valuator.VALUATION_METHODS.VENDOR.uid then
        Logger.Debug(("Item valuation: %s valued at %dc each (vendor)."):format(
            itemLink or "nil", vendorCopperValue
        ))
        return vendorCopperValue, vendorCopperValue * quantity, Valuator.DECISIONS.VENDOR
    end

    -- Helper to get TSM destroy value once
    local function GetDestroyValue()
        if not TSM then
            return nil, "TSM API not available"
        end

        local tsmItemString = TSM.ToItemString and TSM:ToItemString(itemLink)
        if not tsmItemString then
            return nil, "failed to create TSM itemString"
        end

        local destroyValue = TSM:GetCustomPriceValue("Destroy", tsmItemString)
        if not destroyValue or destroyValue <= 0 then
            return nil, "TSM destroy price is nil or 0"
        end

        return destroyValue, nil
    end

    -- DISENCHANT: use TSM Destroy value (or vendor if missing)
    if valuationMethod.uid == Valuator.VALUATION_METHODS.DISENCHANT.uid then
        local destroyValue, err = GetDestroyValue()
        if not destroyValue then
            return FallbackToVendor(err or "no destroy value")
        end

        Logger.Debug(("Item valuation: %s valued at %dc each (disenchant)."):format(
            itemLink or "nil", destroyValue
        ))
        return destroyValue, destroyValue * quantity, Valuator.DECISIONS.DISENCHANT
    end

    -- DISENCHANT OR VENDOR: choose higher of destroy and vendor
    if valuationMethod.uid == Valuator.VALUATION_METHODS.DISENCHANT_OR_VENDOR.uid then
        local destroyValue, err = GetDestroyValue()
        if not destroyValue then
            return FallbackToVendor(err or "no destroy value")
        end

        if destroyValue > vendorCopperValue then
            Logger.Debug(("Item valuation: %s should be disenchanted (%dc each > %dc vendor)."):format(
                itemLink or "nil", destroyValue, vendorCopperValue
            ))
            return destroyValue, destroyValue * quantity, Valuator.DECISIONS.DISENCHANT
        end

        Logger.Debug(("Item valuation: %s should be vended (%dc each >= %dc destroy)."):format(
            itemLink or "nil", vendorCopperValue, destroyValue
        ))
        return vendorCopperValue, vendorCopperValue * quantity, Valuator.DECISIONS.VENDOR
    end

    -- TSM SOURCE WITH RESALE GATE:
    if valuationMethod.uid == Valuator.VALUATION_METHODS.TSM_PRICE_SOURCE_WITH_GATE.uid then
        local minSaleRate = minSaleRate or 0

        if saleRate >= minSaleRate and copperValue > 0 then
            Logger.Debug(("Item valuation: %s sold via market (saleRate=%.4f >= %.4f) at %dc each."):format(
                itemLink or "nil", saleRate, minSaleRate, copperValue
            ))
            return copperValue, copperValue * quantity, Valuator.DECISIONS.MARKET
        end

        -- Below gate: use DE vs vendor comparison
        local destroyValue, err = GetDestroyValue()
        if not destroyValue then
            return FallbackToVendor(err or "no destroy value")
        end

        if destroyValue > vendorCopperValue then
            Logger.Debug(
                ("Item valuation: %s below sale gate; should be disenchanted (%dc each > %dc vendor).")
                :format(itemLink or "nil", destroyValue, vendorCopperValue)
            )
            return destroyValue, destroyValue * quantity, Valuator.DECISIONS.DISENCHANT
        end

        Logger.Debug(
            ("Item valuation: %s below sale gate; should be vended (%dc each >= %dc destroy).")
            :format(itemLink or "nil", vendorCopperValue, destroyValue)
        )
        return vendorCopperValue, vendorCopperValue * quantity, Valuator.DECISIONS.VENDOR
    end

    -- TSM SOURCE: simply use the configured TSM price source.
    if valuationMethod.uid == Valuator.VALUATION_METHODS.TSM_PRICE_SOURCE.uid then
        Logger.Debug(("Item valuation: %s valued at %dc each (TSM source)."):format(
            itemLink or "nil", copperValue
        ))
        -- If copperValue is 0, this is effectively worthless; still call it "market" so you can see intent
        local decision = (copperValue > 0) and Valuator.DECISIONS.MARKET or Valuator.DECISIONS.VENDOR
        if copperValue > 0 then
            return copperValue, copperValue * quantity, decision
        else
            return vendorCopperValue, vendorCopperValue * quantity, decision
        end
    end

    -- Fallback: unsupported method, use raw TSM source
    Logger.Warn((
        "GoldPerHourTracker:RunValuationOnItem received unsupported valuationMethod '%s'. Using TSM price source."
    ):format(tostring(valuationMethod)))
    return copperValue, copperValue * quantity, Valuator.DECISIONS.UNKNOWN
end


--- Resolve TSM value and sale rate for an item link.
--- Returns nils if TSM is unavailable or the item cannot be resolved.
---@param itemLink string
---@return integer|nil copperValue
---@return number|nil saleRate
local function GetTSMValue(itemLink)
    -- Ensure TSM API is available
    if not TSM then
        Logger.Warn("Item valuator cannot value item as TradeSkillMaster API is not available.")
        return nil, nil
    end

    local priceSource = CM:GetProfileSettingSafe("lootMonitor.itemValuation.priceSource", "DBRegionMarketAvg")

    local tsmItemString = TSM:ToItemString(itemLink)
    if not tsmItemString then
        return nil, nil
    end

    local value    = TSM:GetCustomPriceValue(priceSource, tsmItemString)
    local saleRate = TSM:GetSaleRate(tsmItemString)

    return value, saleRate
end

--- Handles Loot Receved events, valuating the items and sending the results to the callback.
--- @param quantity number the quantity of the item received.
--- @param itemInfo table the information about the item received.
--- @return integer copperPerItem the per-item value in copper
--- @return integer totalCopper the total value of the loot event in copper
--- @return string descision the decision made by the valuator when determining loot value
--- @return integer saleRate the sale rate of the item as reported by TSM
local function HandleLootReceivedEvent(quantity, itemInfo)
    local copperValue, saleRate = GetTSMValue(itemInfo.link)

    copperValue = copperValue or 0
    saleRate = saleRate or 0

    -- junk
    if itemInfo.quality == Enum.ItemQuality.Poor then
        local valuationMethod = CM:GetProfileSettingSafe("lootMonitor.itemValuation.junkItems.valuationMethod",
            Valuator.VALUATION_METHODS.VENDOR)
        local copperPerItem, totalCopper, decision = RunValuationOnItem(itemInfo.link, quantity, copperValue, saleRate,
            valuationMethod, true,
            itemInfo.sellPrice)
        return copperPerItem, totalCopper, decision, saleRate
    end

    -- armor/weapons
    if (itemInfo.classID == ARMOR_ITEM_CLASS or itemInfo.classID == WEAPON_ITEM_CLASS) then
        local valuationMethod = CM:GetProfileSettingSafe("lootMonitor.itemValuation.armorAndWeaponItems.valuationMethod",
            Valuator.VALUATION_METHODS.TSM_PRICE_SOURCE)
        local minSaleRate = CM:GetProfileSettingSafe(
            "lootMonitor.itemValuation.armorAndWeaponItems.minimumSaleRate", 0.010)
        local copperPerItem, totalCopper, decision = RunValuationOnItem(itemInfo.link, quantity, copperValue, saleRate,
            valuationMethod, false,
            itemInfo.sellPrice, minSaleRate)
        return copperPerItem, totalCopper, decision, saleRate
    end

    -- remaining items
    local valuationMethod = CM:GetProfileSettingSafe("lootMonitor.itemValuation.remainingItems.valuationMethod",
        Valuator.VALUATION_METHODS.TSM_PRICE_SOURCE)
    local minSaleRate = CM:GetProfileSettingSafe(
        "lootMonitor.itemValuation.remainingItems.minimumSaleRate", 0.010)
    local copperPerItem, totalCopper, decision = RunValuationOnItem(itemInfo.link, quantity, copperValue, saleRate,
        valuationMethod, false,
        itemInfo.sellPrice, minSaleRate)
    return copperPerItem, totalCopper, decision, saleRate
end

--- Handles events received from the callback
local function HandleEvents(event, ...)
    if event == LM.EVENTS.LOOT_RECEIVED then
        ---@type LootReceievedEventData
        local receivedEventData = ...
        local copperPerItem, totalCopper, decision, saleRate = HandleLootReceivedEvent(receivedEventData.quantity,
            receivedEventData.itemInfo)

        ---@class LootValuatedEventData
        ---@field itemInfo LootMonitorItemInfo
        ---@field quantity number
        ---@field totalValueCopper number
        ---@field copperPerItem number
        ---@field saleRate number
        ---@field decision string
        local eventData = {
            itemInfo = receivedEventData.itemInfo,
            quantity = receivedEventData.quantity,
            totalValueCopper = totalCopper,
            copperPerItem = copperPerItem,
            saleRate = saleRate,
            decision = decision
        }

        LM:GetCallbackHandler():Invoke(LM.EVENTS.LOOT_VALUATED, eventData)
    end
end

--- Call to initialize the item valuator, hooking into the callback and sending events after items have been valuated.
function Valuator:Enable()
    if self:IsEnabled() then return end
    self.enabled = true

    callbackID = LM:GetCallbackHandler():Register(HandleEvents)
    Logger.Debug("Item valuator enabled")
end

--- Call to disable the item valuator, unhooking from the callback.
function Valuator:Disable()
    if not self:IsEnabled() then return end
    self.enabled = false

    if callbackID then
        LM:GetCallbackHandler():Unregister(callbackID)
        callbackID = nil
    end

    Logger.Debug("Item valuator disabled")
end
