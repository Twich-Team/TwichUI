local T = unpack(Twich)
local _G = _G

local CreateFrame = _G.CreateFrame

---@type MythicPlusModule
local MP = T:GetModule("MythicPlus")
---@type ConfigurationModule
local CM = T:GetModule("Configuration")
---@type LoggerModule
local Logger = T:GetModule("Logger")

local function NormalizeHexColor(hex)
    if type(hex) ~= "string" or hex == "" then return nil end
    hex = hex:gsub("^|c", ""):gsub("^#", "")
    if #hex == 6 then
        hex = "ff" .. hex
    end
    if #hex ~= 8 then return nil end
    return hex
end

local function GetItemRarityHex(itemLink)
    if not itemLink then return nil end

    local quality
    local itemID = GetItemInfoInstant(itemLink)
    if itemID and _G.C_Item and _G.C_Item.GetItemQualityByID then
        quality = _G.C_Item.GetItemQualityByID(itemID)
    end
    if quality == nil then
        local _, _, q = GetItemInfo(itemLink)
        quality = q
    end
    if quality == nil then return nil end

    local _, _, _, hex = GetItemQualityColor(quality)
    return NormalizeHexColor(hex)
end

local function ColorizeWithHex(hex, text)
    if type(text) ~= "string" then
        text = tostring(text or "")
    end
    hex = NormalizeHexColor(hex)
    if not hex then
        return text
    end
    return "|c" .. hex .. text .. "|r"
end

local function RestoreLoggerInfoColor(text)
    text = tostring(text or "")

    local infoHex = Logger and Logger.LEVELS and Logger.LEVELS.INFO and Logger.LEVELS.INFO.hexColor
    infoHex = NormalizeHexColor(infoHex)
    if not infoHex then
        return text
    end

    -- Logger.Info wraps the full message, but embedded item links and colored segments include "|r",
    -- which would otherwise reset the remaining text back to default chat color.
    return text:gsub("|r", "|r|c" .. infoHex)
end

local function FormatBiSChatMessage(kind, itemLink, receivedILvl, previousILvl, quantity)
    local label
    if kind == "UPGRADE" then
        label = "BiS Upgrade"
    elseif kind == "NEW" then
        label = "BiS Acquired"
    else
        label = "BiS Found"
    end

    local qty = tonumber(quantity) or 1
    if qty < 1 then qty = 1 end

    local itemText = tostring(itemLink or "")
    if qty > 1 then
        itemText = itemText .. string.format(" x%d", qty)
    end

    local ilvlText = ""
    local r = tonumber(receivedILvl)
    local p = tonumber(previousILvl)

    local hex = GetItemRarityHex(itemLink)
    local function Ilvl(n)
        return ColorizeWithHex(hex, tostring(n))
    end
    if r and p and r > 0 and p > 0 then
        ilvlText = string.format(" (iLvl %s -> %s)", Ilvl(p), Ilvl(r))
    elseif r and r > 0 then
        ilvlText = string.format(" (iLvl %s)", Ilvl(r))
    end

    return string.format("%s: %s%s", label, itemText, ilvlText)
end

--- @class BestInSlotNotificationHandler
--- @field enabled boolean
--- @field frame Frame|nil
local NIH = MP.BestInSlotNotificationHandler or {}
MP.BestInSlotNotificationHandler = NIH

local KEY_PREFIX = "mythicplus.bestInSlot.notifications."

-- Keys for mapping GetItemInfo() returns into a table
local ITEMINFO_KEYS = {
    "name", "link", "quality", "iLevel", "minLevel", "type", "subType",
    "maxStack", "equipLoc", "icon", "sellPrice", "classID", "subClassID",
    "bindType", "expansionID", "setID", "isCraftingReagent"
}

---@param item string|number
---@param callback fun(info:table|nil)|nil
---@return table|nil
local function GetItemInfoTable(item, callback)
    local results = { GetItemInfo(item) }
    if not results[1] then
        if type(callback) == "function" then
            local itemID
            if type(item) == "number" then
                itemID = item
            elseif type(item) == "string" then
                itemID = tonumber(item:match("item:(%d+):"))
            end

            local waiter = CreateFrame("Frame")
            local function OnGetItemInfoReceived(_, _, gotItemID, success)
                if not success then
                    waiter:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
                    waiter:SetScript("OnEvent", nil)
                    callback(nil)
                    return
                end

                if not itemID or tonumber(gotItemID) == tonumber(itemID) then
                    waiter:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
                    waiter:SetScript("OnEvent", nil)
                    local filled = GetItemInfoTable(item, nil)
                    callback(filled)
                end
            end

            waiter:RegisterEvent("GET_ITEM_INFO_RECEIVED")
            waiter:SetScript("OnEvent", OnGetItemInfoReceived)
        end
        return nil
    end

    local t = {}
    for i = 1, #results do
        t[ITEMINFO_KEYS[i] or ("field" .. i)] = results[i]
    end
    return t
end

local LOOT_SELF_PATTERN = string.gsub(LOOT_ITEM_SELF, "%%s", "(.+)")

local function GetCharacterDB()
    if not MP.Database or not MP.Database.GetForCurrentCharacter then return nil end
    local entry = MP.Database:GetForCurrentCharacter()
    if not entry then return nil end
    if not entry.BestInSlot then entry.BestInSlot = {} end
    return entry.BestInSlot
end

local function GetSelectedBiSItemIDs()
    local db = GetCharacterDB()
    if type(db) ~= "table" then return {} end

    local set = {}
    for k, v in pairs(db) do
        if tonumber(k) then
            local link = (type(v) == "table" and v.link) or v
            if link then
                local itemID = GetItemInfoInstant(link)
                if itemID then
                    set[tonumber(itemID)] = true
                end
            end
        end
    end
    return set
end

local function GetOwnedTable(db)
    if type(db) ~= "table" then return nil end
    db.__ownedBiS = db.__ownedBiS or {}
    return db.__ownedBiS
end

local function GetEffectiveItemLevel(itemLink, fallback)
    if not itemLink then return tonumber(fallback) end
    local effective = GetDetailedItemLevelInfo(itemLink)
    if effective and tonumber(effective) then
        return tonumber(effective)
    end
    return tonumber(fallback)
end

local function ProcessLootItem(itemLink, quantity, overrideILvl)
    if not itemLink then return end

    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then return end

    local selected = GetSelectedBiSItemIDs()
    if not selected[tonumber(itemID)] then
        return
    end

    local db = GetCharacterDB()
    local owned = GetOwnedTable(db)
    if not owned then return end

    local currentILvl = GetEffectiveItemLevel(itemLink, nil)
    if overrideILvl and tonumber(overrideILvl) and tonumber(overrideILvl) > 0 then
        currentILvl = tonumber(overrideILvl)
    end

    local prevILvl = owned[tonumber(itemID)]

    local shouldShow = false
    local kind = "FOUND"

    if not prevILvl then
        shouldShow = true
        kind = "NEW"
    elseif currentILvl and tonumber(prevILvl) and currentILvl > tonumber(prevILvl) then
        shouldShow = true
        kind = "UPGRADE"
    end

    if currentILvl and (not prevILvl or currentILvl > (tonumber(prevILvl) or 0)) then
        owned[tonumber(itemID)] = currentILvl
    elseif not prevILvl then
        owned[tonumber(itemID)] = currentILvl or 0
    end

    if not shouldShow then
        return
    end

    if MP.BestInSlotNotificationFrame and MP.BestInSlotNotificationFrame.Initialize then
        MP.BestInSlotNotificationFrame:Initialize()
    end

    local soundKey = CM:GetProfileSettingSafe(KEY_PREFIX .. "notificationSound", "TwichUI Green Dude Gets Loot")
    if soundKey and soundKey ~= "None" then
        local LSM = T.Libs and T.Libs.LSM
        local path = LSM and LSM:Fetch("sound", soundKey)
        if path then
            PlaySoundFile(path, "Master")
        end
    end

    if MP.BestInSlotNotificationFrame and MP.BestInSlotNotificationFrame.ShowNotification then
        MP.BestInSlotNotificationFrame:ShowNotification(itemLink, kind, currentILvl, tonumber(prevILvl), quantity)
    end

    Logger.Info(RestoreLoggerInfoColor(FormatBiSChatMessage(kind, itemLink, currentILvl, tonumber(prevILvl), quantity)))
end

local function OnChatMsgLoot(message)
    local raw = type(message) == "string" and message:match(LOOT_SELF_PATTERN)
    if not raw then return end

    local quantity = 1
    local qtyMatch = raw:match("x(%d+)%.?$")
    if not qtyMatch then
        qtyMatch = raw:match("%sx(%d+)%s*%.?$")
    end
    if qtyMatch then
        quantity = tonumber(qtyMatch) or 1
        raw = raw:gsub("%s*x%d+%.?$", "")
    end

    local itemLink = raw:match("(|c%x+|Hitem:[^|]+|h%[[^]]+%]|h|r)") or raw
    if not itemLink then return end

    local info = GetItemInfoTable(itemLink, nil)
    if info and info.link then
        ProcessLootItem(info.link, quantity, nil)
        return
    end

    GetItemInfoTable(itemLink, function(filled)
        if not filled or not filled.link then
            Logger.Error("BestInSlotNotificationHandler: Failed to resolve item info for: " .. tostring(itemLink))
            return
        end
        ProcessLootItem(filled.link, quantity, nil)
    end)
end

local function HandleEvent(_, event, ...)
    if event == "CHAT_MSG_LOOT" then
        local msg = ...
        OnChatMsgLoot(msg)
    end
end

function NIH:IsEnabled()
    return self.enabled
end

function NIH:Enable()
    if self.enabled then return end
    self.enabled = true

    if self.frame then
        self.frame:UnregisterAllEvents()
        self.frame:SetScript("OnEvent", nil)
        self.frame = nil
    end

    self.frame = CreateFrame("Frame", "TwichUIMythicPlusBiSNotificationListener")
    self.frame:SetScript("OnEvent", HandleEvent)
    self.frame:RegisterEvent("CHAT_MSG_LOOT")

    if MP.BestInSlotNotificationFrame and MP.BestInSlotNotificationFrame.Initialize then
        MP.BestInSlotNotificationFrame:Initialize()
    end

    Logger.Debug("BestInSlot notifications enabled")
end

function NIH:Disable()
    if not self.enabled then return end
    self.enabled = false

    if self.frame then
        self.frame:UnregisterAllEvents()
        self.frame:SetScript("OnEvent", nil)
        self.frame = nil
    end

    Logger.Debug("BestInSlot notifications disabled")
end

function NIH:Initialize()
    if self.initialized then return end
    self.initialized = true

    local enabled = CM:GetProfileSettingSafe(KEY_PREFIX .. "enabled", true)
    if enabled then
        self:Enable()
    else
        self:Disable()
    end
end

--- Developer/testing helper: simulate looting an item.
--- @param item string|number itemID or itemLink
--- @param quantity number|nil
--- @param overrideILvl number|nil
function NIH:TestSimulateLoot(item, quantity, overrideILvl)
    quantity = tonumber(quantity) or 1
    if quantity < 1 then quantity = 1 end

    local normalized = item
    if type(item) == "string" then
        local trimmed = item:match("^%s*(.-)%s*$")
        local asNumber = tonumber(trimmed)
        if asNumber then
            normalized = asNumber
        else
            normalized = trimmed
        end
    end

    local function Fire(link)
        if not link then
            Logger.Error("BestInSlotNotificationHandler:TestSimulateLoot failed to resolve item: " .. tostring(item))
            return
        end
        ProcessLootItem(link, quantity, overrideILvl)
    end

    local info = GetItemInfoTable(normalized, function(filled)
        Fire(filled and filled.link)
    end)

    if info and info.link then
        Fire(info.link)
    end
end

--- Developer/testing helper: force-show a notification (bypasses BiS selection / owned upgrade logic).
--- @param item string|number itemID or itemLink
--- @param kind "NEW"|"UPGRADE"|"FOUND"|string|nil
--- @param receivedILvl number|nil
--- @param previousILvl number|nil
--- @param quantity number|nil
function NIH:TestForceNotification(item, kind, receivedILvl, previousILvl, quantity)
    quantity = tonumber(quantity) or 1
    if quantity < 1 then quantity = 1 end

    local normalized = item
    if type(item) == "string" then
        local trimmed = item:match("^%s*(.-)%s*$")
        local asNumber = tonumber(trimmed)
        if asNumber then
            normalized = asNumber
        else
            normalized = trimmed
        end
    end

    local function Fire(link)
        if not link then
            Logger.Error("BestInSlotNotificationHandler:TestForceNotification failed to resolve item: " .. tostring(item))
            return
        end

        if MP.BestInSlotNotificationFrame and MP.BestInSlotNotificationFrame.Initialize then
            MP.BestInSlotNotificationFrame:Initialize()
        end

        local soundKey = CM:GetProfileSettingSafe(KEY_PREFIX .. "notificationSound", "TwichUI Green Dude Gets Loot")
        if soundKey and soundKey ~= "None" then
            local LSM = T.Libs and T.Libs.LSM
            local path = LSM and LSM:Fetch("sound", soundKey)
            if path then
                PlaySoundFile(path, "Master")
            end
        end

        if MP.BestInSlotNotificationFrame and MP.BestInSlotNotificationFrame.ShowNotification then
            MP.BestInSlotNotificationFrame:ShowNotification(
                link,
                kind or "FOUND",
                tonumber(receivedILvl) or nil,
                tonumber(previousILvl) or nil,
                quantity
            )
        end

        Logger.Info(RestoreLoggerInfoColor(FormatBiSChatMessage(kind or "FOUND", link, receivedILvl, previousILvl,
            quantity)))
    end

    local info = GetItemInfoTable(normalized, function(filled)
        Fire(filled and filled.link)
    end)

    if info and info.link then
        Fire(info.link)
    end
end
