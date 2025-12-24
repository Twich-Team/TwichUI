--[[
        TSM Module
        This module provides access to the TradeSkillMasterAPI.
]]
local T, W, I, C = unpack(Twich)

--- @type LoggerModule
local Logger = T:GetModule("Logger")

--- @type ThirdPartyAPIModule
local TPA = T:GetModule("ThirdPartyAPI")

--- @class TradeSkillMasterAPI
local TSM = TPA.TSM or {}
TPA.TSM = TSM

local TSM_API = TSM_API -- thie primary TSM API
-- Expose the raw API reference on the module for callers that need it
TSM.API = TSM_API

--- Checks whether the TradeSkillMaster addon API is available.
--- Logs an error if TSM is not loaded or its API is missing.
--- @param endpoint any the endpoint to access
--- @return boolean available True if the TSM API is available; false otherwise.
function TSM:Available(endpoint)
    if not TSM_API then
        return false
    end

    if (endpoint ~= nil and not endpoint) then
        return false
    end

    return true
end

--- Retrieves the list of available TSM price source keys.
--- Wraps the TSM helper that fills a table with price source keys.
---@return string[] priceSources A list of price source keys (e.g. "dbmarket", "dbregionmarketavg").
function TSM:GetPriceSources()
    local priceSources = {}

    if self:Available(TSM_API.GetPriceSourceKeys) then
        TSM_API.GetPriceSourceKeys(priceSources)
    end

    return priceSources
end

--- Converts an item to a TSM item string.
--- @within Item
--- @param item string Either an item link, TSM item string, or WoW item string
--- @return string | nil tsmItemString TSM item string or nil if the specified item could not be converted
function TSM:ToItemString(item)
    if self:Available(TSM_API.ToItemString) then
        return TSM_API.ToItemString(item)
    end

    return nil
end

--- Gets an item's name from a given TSM item string.
--- @within Item
--- @param itemString string The TSM item string
--- @return string | nil itemName name of the item or nil if it couldn't be determined
function TSM:GetItemName(itemString)
    if self:Available(TSM_API.GetItemName) then
        return TSM_API.GetItemName(itemString)
    end

    return nil
end

--- Gets an item link from a given TSM item string.
--- @within Item
--- @param itemString string The TSM item string
--- @return string | nil itemLink item link or an "[Unknown Item]" link
function TSM:GetItemLink(itemString)
    if self:Available(TSM_API.GetItemLink) then
        return TSM_API.GetItemLink(itemString)
    end

    return nil
end

--- Evalulates a custom price string or price source key for a given item
--- @within Price
--- @param customPriceStr string The custom price string or price source key to get the value of
--- @param itemStr string The TSM item string to get the value for
--- @return number | nil copperValue value in copper or nil if the custom price string is not valid
--- @return string | nil errorMsg (localized) error message if the custom price string is not valid or nil if it is valid
function TSM:GetCustomPriceValue(customPriceStr, itemStr)
    if self:Available(TSM_API.GetCustomPriceValue) then
        return TSM_API.GetCustomPriceValue(customPriceStr, itemStr)
    end

    return nil, nil
end

--- @return number | nil copperValue value in copper or nil if the custom price string is not valid
function TSM:GetSaleRate(itemStr)
    if self:Available(TSM_API.GetCustomPriceValue) then
        local v, err = TSM_API.GetCustomPriceValue("1000 * DBRegionSaleRate(baseitem)", itemStr)
        if v then
            return v / 1000
        else
            return 0
        end
    end

    return nil
end

--- Obtains the human-readable description of a given TSM price source.
---@param priceSource string The price source key (e.g. "dbmarket").
---@return string description The description provided by TSM, or an empty string if unavailable.
function TSM:GetPriceSourceDescription(priceSource)
    local description = ""

    if self:Available(TSM_API.GetPriceSourceDescription) then
        description = TSM_API.GetPriceSourceDescription(priceSource) or ""
    end

    return description
end
