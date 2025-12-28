local T, W, I, C = unpack(Twich)
---@type ToolsModule
local TM = T:GetModule("Tools")

---@class MoneyTool
local MoneyTool = TM.Money or {}
TM.Money = MoneyTool

TwichUIGoldDB = TwichUIGoldDB or {}



local UnitName = UnitName
local GetRealmName = GetRealmName
local GetMoney = GetMoney
local FetchDepositedMoney = C_Bank.FetchDepositedMoney
local BANK_TYPE = (Enum.BankType and Enum.BankType.Account) or 2

-- Internal callback dispatcher for gold updates
MoneyTool._goldUpdate = MoneyTool._goldUpdate or TM.Callback.New()

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

--- Registers a callback invoked when gold totals change.
--- @param func fun() The function to call on gold updates.
--- @return number id The registration id.
function MoneyTool:RegisterGoldUpdateCallback(func)
    return self._goldUpdate:Register(func)
end

--- Unregisters a previously registered gold update callback.
--- @param id number The id returned from RegisterGoldUpdateCallback.
function MoneyTool:UnregisterGoldUpdateCallback(id)
    self._goldUpdate:Unregister(id)
end

--- Notifies listeners that gold totals have changed.
function MoneyTool:NotifyGoldUpdated()
    self._goldUpdate:Invoke()
end

function MoneyTool:GetWarbankCopper()
    return FetchDepositedMoney(BANK_TYPE) or 0
end

--- Computes account-wide gold statistics from TwichUIGoldDB.
--- @return table stats { total:number, warbank:number, character:number }
function MoneyTool:GetAccountGoldStats()
    local total = 0
    local warbank = self:GetWarbankCopper()

    local name, realm = UnitName("player"), GetRealmName()
    local characterCopper = GetMoney() or 0

    if TwichUIGoldDB then
        for realmName, chars in pairs(TwichUIGoldDB) do
            for charName, data in pairs(chars) do
                if type(data) == "table" and data.totalCopper then
                    total = total + (data.totalCopper or 0)
                end
                if realmName == realm and charName == name and type(data) == "table" and data.totalCopper then
                    characterCopper = data.totalCopper or characterCopper
                end
            end
        end
    else
        -- Fallback: use current character only
        total = characterCopper
    end

    return {
        total = total,
        warbank = warbank,
        character = characterCopper,
    }
end

--- Returns top-N characters by gold across TwichUIGoldDB.
--- @param n number How many characters to return.
--- @return table[] list Array of { name, realm, class, faction, copper } sorted desc.
function MoneyTool:GetTopCharactersByGold(n)
    n = n or 5
    local list = {}
    local name, realm = UnitName("player"), GetRealmName()

    if _G.TwichUIGoldDB then
        local Logger = T:GetModule("Logger")
        for realmName, chars in pairs(_G.TwichUIGoldDB) do
            for charName, data in pairs(chars) do
                if type(data) == "table" and not (realmName == realm and charName == name) then
                    table.insert(list, {
                        name = charName,
                        realm = realmName,
                        class = data.class,
                        faction = data.faction,
                        copper = data.totalCopper or 0,
                    })
                end
            end
        end
    end

    table.sort(list, function(a, b) return (a.copper or 0) > (b.copper or 0) end)
    while #list > n do table.remove(list) end
    return list
end

--- Formats a copper amount into a human-readable gold/silver/copper string (e.g., "12g 34s 56c").
--- @param copper integer The amount in copper.
--- @return string formatted The formatted currency string.
function MoneyTool:FormatCopper(copper)
    if not copper or copper < 0 then copper = 0 end

    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100

    if g > 0 then
        return string.format("%dg %ds %dc", g, s, c)
    elseif s > 0 then
        return string.format("%ds %dc", s, c)
    else
        return string.format("%dc", c)
    end
end

--- Formats a copper amount into a short string prioritizing the largest unit (e.g., "12g" or "34s").
--- @param copper integer The amount in copper.
--- @return string formatted The formatted short currency string.
function MoneyTool:FormatCopperShort(copper)
    if not copper or copper < 0 then copper = 0 end

    local g = math.floor(copper / 10000)
    if g > 0 then return string.format("%dg", g) end

    local s = math.floor((copper % 10000) / 100)
    if s > 0 then return string.format("%ds", s) end

    local c = copper % 100
    return string.format("%dc", c)
end
