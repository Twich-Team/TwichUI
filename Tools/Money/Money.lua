local T, W, I, C = unpack(Twich)
---@type ToolsModule
local TM = T:GetModule("Tools")

---@class MoneyTool
local MoneyTool = TM.Money or {}
TM.Money = MoneyTool

--- Converts a copper value to a gold value.
--- @param copperValue integer The value in copper.
--- @return number goldValue The value in gold.
function MoneyTool.CopperToGold(copperValue)
    return copperValue / (100 * 100)
end

--- Converts a gold value to a copper value.
--- @param goldValue number The value in gold.
--- @return integer copperValue The value in copper.
function MoneyTool.GoldToCopper(goldValue)
    return math.floor(goldValue * 100 * 100)
end
