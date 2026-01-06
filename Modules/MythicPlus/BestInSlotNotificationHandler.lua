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
    elseif kind == "ROLL" then
        label = "BiS Available (Roll)"
    elseif kind == "VAULT" then
        label = "BiS Available (Great Vault)"
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

local function WithTemporaryProfileSetting(key, tempValue, fn)
    if type(fn) ~= "function" then return end
    local previous = CM:GetProfileSettingSafe(key, nil)
    CM:SetProfileSettingSafe(key, tempValue)
    local ok, err = pcall(fn)
    CM:SetProfileSettingSafe(key, previous)
    if not ok then
        Logger.Error(tostring(err))
    end
end

local function WithTemporaryBiSSelection(itemLink, fn)
    if type(fn) ~= "function" then return end

    local db = GetCharacterDB()
    if type(db) ~= "table" then
        fn()
        return
    end

    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then
        fn()
        return
    end

    local key = tonumber(itemID)
    if not key then
        fn()
        return
    end
    local previous = db[key]
    db[key] = { link = itemLink }

    local ok, err = pcall(fn)

    if previous == nil then
        db[key] = nil
    else
        db[key] = previous
    end

    if not ok then
        Logger.Error(tostring(err))
    end
end

local function PlayNotificationSound(settingSuffix, defaultSoundKey)
    local soundKey = CM:GetProfileSettingSafe(KEY_PREFIX .. settingSuffix, defaultSoundKey)
    if soundKey and soundKey ~= "None" then
        local LSM = T.Libs and T.Libs.LSM
        local path = LSM and LSM:Fetch("sound", soundKey)
        if path then
            PlaySoundFile(path, "Master")
        end
    end
end

local function ShowAndLog(kind, itemLink, receivedILvl, previousILvl, quantity)
    if MP.BestInSlotNotificationFrame and MP.BestInSlotNotificationFrame.Initialize then
        MP.BestInSlotNotificationFrame:Initialize()
    end

    if MP.BestInSlotNotificationFrame and MP.BestInSlotNotificationFrame.ShowNotification then
        MP.BestInSlotNotificationFrame:ShowNotification(itemLink, kind, receivedILvl, previousILvl, quantity)
    end

    Logger.Info(RestoreLoggerInfoColor(FormatBiSChatMessage(kind, itemLink, receivedILvl, previousILvl, quantity)))
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

    PlayNotificationSound("notificationSound", "TwichUI Green Dude Gets Loot")
    ShowAndLog(kind, itemLink, currentILvl, tonumber(prevILvl), quantity)
end

local function FindItemLinkInBagsOrEquipment(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil, nil end

    -- Bags (Retail API)
    if _G.C_Container and type(_G.C_Container.GetContainerNumSlots) == "function" and type(_G.C_Container.GetContainerItemInfo) == "function" then
        local maxBags = tonumber(_G.NUM_BAG_SLOTS) or 4
        for bag = 0, maxBags do
            local okSlots, slots = pcall(_G.C_Container.GetContainerNumSlots, bag)
            slots = okSlots and tonumber(slots) or 0
            for slot = 1, slots do
                local okInfo, info = pcall(_G.C_Container.GetContainerItemInfo, bag, slot)
                if okInfo and type(info) == "table" then
                    local link = info.hyperlink
                    if type(link) == "string" and link ~= "" then
                        local id = GetItemInfoInstant(link)
                        if tonumber(id) == itemID then
                            return link, tonumber(info.stackCount) or 1
                        end
                    end
                end
            end
        end
    end

    -- Legacy bag APIs (fallback)
    if type(_G.GetContainerNumSlots) == "function" and type(_G.GetContainerItemLink) == "function" then
        local maxBags = tonumber(_G.NUM_BAG_SLOTS) or 4
        for bag = 0, maxBags do
            local slots = tonumber(_G.GetContainerNumSlots(bag)) or 0
            for slot = 1, slots do
                local link = _G.GetContainerItemLink(bag, slot)
                if type(link) == "string" and link ~= "" then
                    local id = GetItemInfoInstant(link)
                    if tonumber(id) == itemID then
                        return link, 1
                    end
                end
            end
        end
    end

    -- Equipped (vault rewards can be auto-equipped by some UI flows)
    if type(_G.GetInventoryItemLink) == "function" then
        for slot = 1, 19 do
            local link = _G.GetInventoryItemLink("player", slot)
            if type(link) == "string" and link ~= "" then
                local id = GetItemInfoInstant(link)
                if tonumber(id) == itemID then
                    return link, 1
                end
            end
        end
    end

    return nil, nil
end

local function MaybeNotifyPendingVaultClaim()
    local pending = NIH and NIH.__vaultPendingClaim
    if type(pending) ~= "table" then return end

    local now = (_G.GetTime and _G.GetTime()) or 0
    local startedAt = tonumber(pending.at) or 0
    if now > 0 and startedAt > 0 and (now - startedAt) > 120 then
        NIH.__vaultPendingClaim = nil
        return
    end

    pending.attempts = (tonumber(pending.attempts) or 0) + 1
    if pending.attempts > 30 then
        NIH.__vaultPendingClaim = nil
        return
    end

    local itemID = tonumber(pending.itemID)
    if not itemID then
        NIH.__vaultPendingClaim = nil
        return
    end

    local link, qty = FindItemLinkInBagsOrEquipment(itemID)
    if type(link) == "string" and link ~= "" then
        ProcessLootItem(link, qty or 1, nil)
        NIH.__vaultPendingClaim = nil
        return
    end

    -- If we can't find the exact bag/equip link yet, fall back to the stored link.
    if type(pending.link) == "string" and pending.link ~= "" then
        ProcessLootItem(pending.link, 1, nil)
        NIH.__vaultPendingClaim = nil
    end
end

local function OnStartLootRoll(rollID)
    if not rollID then return end
    if not CM:GetProfileSettingSafe(KEY_PREFIX .. "availabilityRollEnabled", true) then
        return
    end

    NIH.__rollNotified = NIH.__rollNotified or {}
    if NIH.__rollNotified[tonumber(rollID)] then
        return
    end

    local link = _G.GetLootRollItemLink and _G.GetLootRollItemLink(rollID)
    if type(link) ~= "string" or link == "" then
        return
    end

    local itemID = GetItemInfoInstant(link)
    if not itemID then return end
    local selected = GetSelectedBiSItemIDs()
    if not selected[tonumber(itemID)] then
        return
    end

    NIH.__rollNotified[tonumber(rollID)] = true

    local count = 1
    if _G.GetLootRollItemInfo then
        local _, _, c = _G.GetLootRollItemInfo(rollID)
        count = tonumber(c) or 1
        if count < 1 then count = 1 end
    end

    local ilvl = GetEffectiveItemLevel(link, nil)

    PlayNotificationSound("availabilityRollSound", "TwichUI Notification 8")
    ShowAndLog("ROLL", link, ilvl, nil, count)
end

local __lastVaultCheckAt = 0
local function CheckGreatVaultForBiS()
    if not CM:GetProfileSettingSafe(KEY_PREFIX .. "availabilityVaultEnabled", true) then
        return
    end

    local C_WeeklyRewards = _G.C_WeeklyRewards
    if not C_WeeklyRewards or type(C_WeeklyRewards.GetActivities) ~= "function" then
        return
    end

    local function IsVaultDebugEnabled()
        return CM:GetProfileSettingSafe("developer.testing.mythicPlus.greatVaultDebug.enabled", false) == true
    end

    local function DebugGate(lines)
        if not IsVaultDebugEnabled() then return end
        NIH.__vaultApiGateDebugLast = NIH.__vaultApiGateDebugLast or 0
        local now2 = (type(_G.GetTime) == "function" and _G.GetTime()) or 0
        if now2 > 0 and (now2 - (NIH.__vaultApiGateDebugLast or 0)) < 1.0 then
            return
        end
        NIH.__vaultApiGateDebugLast = now2

        Logger.Debug("VaultAPI Debug: gate")
        if type(lines) == "table" then
            for _, line in ipairs(lines) do
                Logger.Debug("  " .. tostring(line))
            end
        end
    end

    -- Prefer not spamming notifications when rewards aren't claimable yet, but still scan.
    local hasAvailableRewards
    if type(C_WeeklyRewards.HasAvailableRewards) == "function" then
        local ok, has = pcall(C_WeeklyRewards.HasAvailableRewards)
        if ok then
            hasAvailableRewards = (has == true)
        end
    end

    local weeklyRewardsFrame = rawget(_G, "WeeklyRewardsFrame")
    local vaultUIShown = weeklyRewardsFrame and type(weeklyRewardsFrame.IsShown) == "function" and
        weeklyRewardsFrame:IsShown() == true
    local allowNotify = (hasAvailableRewards == true) or vaultUIShown

    -- When the vault UI is open, we want our delayed retries to actually run.
    local now = (_G.GetTime and _G.GetTime()) or 0
    local cooldown = vaultUIShown and 0.15 or 5
    if now > 0 and (now - __lastVaultCheckAt) < cooldown then
        return
    end
    __lastVaultCheckAt = now

    DebugGate({
        "hasAvailableRewards=" .. tostring(hasAvailableRewards),
        "vaultUIShown=" .. tostring(vaultUIShown),
        "allowNotify=" .. tostring(allowNotify),
    })

    if type(C_WeeklyRewards.RequestRewards) == "function" then
        pcall(C_WeeklyRewards.RequestRewards)
    end
    if type(C_WeeklyRewards.RequestActivities) == "function" then
        pcall(C_WeeklyRewards.RequestActivities)
    end

    local function TryActivities(...)
        local ok, res = pcall(C_WeeklyRewards.GetActivities, ...)
        if ok and type(res) == "table" then
            return res
        end
        return nil
    end

    local best
    local function Consider(t)
        if type(t) ~= "table" then return end
        if not best or #t > #best then
            best = t
        end
    end

    Consider(TryActivities())
    -- Some clients require a threshold type. Prefer Mythic+ (2), but also try the others.
    ---@type table<string, number>|nil
    local chestTypes = _G.Enum and _G.Enum.WeeklyRewardChestThresholdType
    local mythicPlusType = (chestTypes and chestTypes["MythicPlus"]) or 2
    local raidType = (chestTypes and chestTypes["Raid"]) or 1
    local pvpType = (chestTypes and (chestTypes["RatedPvP"] or chestTypes["PvP"] or chestTypes["Pvp"])) or 3

    Consider(TryActivities(mythicPlusType))
    Consider(TryActivities(raidType))
    Consider(TryActivities(pvpType))

    local activities = best
    if type(activities) ~= "table" then
        return
    end

    if type(C_WeeklyRewards.GetActivityItemRewards) ~= "function" then
        return
    end

    NIH.__vaultNotified = NIH.__vaultNotified or {}

    local selected = GetSelectedBiSItemIDs()

    local function GetRewardItemDBID(reward)
        if type(reward) ~= "table" then return nil end
        return tonumber(
            reward.itemDBID
            or reward.itemDbID
            or reward.itemDBId
            or reward.itemdbid
            or (type(reward.rewards) == "table" and (reward.rewards.itemDBID or reward.rewards.itemDbID))
        )
    end

    local function ResolveWeeklyRewardItemLink(itemDBID)
        itemDBID = tonumber(itemDBID)
        if not itemDBID then return nil end

        local C_WeeklyRewards2 = _G.C_WeeklyRewards
        if not C_WeeklyRewards2 then return nil end

        local candidates = {
            { name = "GetItemHyperlink", fn = C_WeeklyRewards2.GetItemHyperlink },
            { name = "GetItemLink",      fn = C_WeeklyRewards2.GetItemLink },
        }

        NIH.__vaultItemDBIDDebug = NIH.__vaultItemDBIDDebug or {}
        local debugKey = tostring(itemDBID)
        local didDebug = NIH.__vaultItemDBIDDebug[debugKey] == true

        for i = 1, #candidates do
            local entry = candidates[i]
            local fn = entry and entry.fn
            if type(fn) == "function" then
                local ok, linkOrErr = pcall(fn, itemDBID)
                if ok and type(linkOrErr) == "string" and linkOrErr ~= "" then
                    local link = linkOrErr
                    -- Basic sanity: should look like an item hyperlink.
                    if link:find("|Hitem:", 1, true) then
                        if IsVaultDebugEnabled() and not didDebug then
                            NIH.__vaultItemDBIDDebug[debugKey] = true
                            Logger.Debug("VaultAPI Debug: itemDBID=" ..
                                debugKey .. " resolvedVia=" .. tostring(entry.name) .. " link=" .. link)
                        end
                        return link
                    end
                    -- Some clients may return a raw item string; still accept if parseable.
                    if link:find("item:", 1, true) then
                        if IsVaultDebugEnabled() and not didDebug then
                            NIH.__vaultItemDBIDDebug[debugKey] = true
                            Logger.Debug("VaultAPI Debug: itemDBID=" ..
                                debugKey .. " resolvedVia=" .. tostring(entry.name) .. " link=" .. link)
                        end
                        return link
                    end
                elseif IsVaultDebugEnabled() and not didDebug then
                    -- Only log the first failure for this DBID.
                    local errText = ok and tostring(linkOrErr) or ("error: " .. tostring(linkOrErr))
                    NIH.__vaultItemDBIDDebug[debugKey] = true
                    Logger.Debug("VaultAPI Debug: itemDBID=" ..
                        debugKey .. " tried=" .. tostring(entry and entry.name) .. " result=" .. errText)
                end
            end
        end

        if IsVaultDebugEnabled() and not didDebug then
            NIH.__vaultItemDBIDDebug[debugKey] = true
            Logger.Debug("VaultAPI Debug: itemDBID=" .. debugKey .. " resolvedVia=<none>")
        end
        return nil
    end

    local function GetActivityId(entry)
        if type(entry) == "table" then
            return tonumber(entry.id or entry.activityID or entry.activityId)
        end
        return tonumber(entry)
    end

    local function GetArrayLikeTableCount(t)
        if type(t) ~= "table" then return 0 end
        return #t
    end

    local function NormalizeRewardsTable(rewards)
        if type(rewards) ~= "table" then
            return nil
        end
        -- Ensure we can iterate in a consistent, array-like way.
        if #rewards > 0 then
            return rewards
        end
        local out = {}
        for _, v in pairs(rewards) do
            out[#out + 1] = v
        end
        return out
    end

    local function DebugActivityOnce(activityID, lines)
        if not IsVaultDebugEnabled() then return end
        activityID = tonumber(activityID)
        if not activityID then return end
        NIH.__vaultActivityDebugSeen = NIH.__vaultActivityDebugSeen or {}
        if NIH.__vaultActivityDebugSeen[activityID] then return end
        NIH.__vaultActivityDebugSeen[activityID] = true

        Logger.Debug("VaultAPI Debug: activity=" .. tostring(activityID))
        if type(lines) == "table" then
            for _, line in ipairs(lines) do
                Logger.Debug("  " .. tostring(line))
            end
        end
    end

    for _, entry in ipairs(activities) do
        local activityID = GetActivityId(entry)
        if activityID then
            local ok2, rewards = pcall(C_WeeklyRewards.GetActivityItemRewards, activityID)
            local fromAPI = (ok2 and type(rewards) == "table") and NormalizeRewardsTable(rewards) or nil
            local fromEntry
            if (not fromAPI or #fromAPI == 0) and type(entry) == "table" then
                fromEntry = NormalizeRewardsTable(entry.rewards)
            end

            local rewardList = (fromAPI and #fromAPI > 0) and fromAPI or fromEntry

            DebugActivityOnce(activityID, {
                "getActivityItemRewards_ok=" .. tostring(ok2),
                "rewardsFromAPI=" .. tostring(GetArrayLikeTableCount(fromAPI)),
                "rewardsFromEntry=" .. tostring(GetArrayLikeTableCount(fromEntry)),
                "entryType=" .. tostring(type(entry)),
                "entryRewardsType=" .. tostring(type(type(entry) == "table" and entry.rewards or nil)),
            })

            if type(rewardList) == "table" then
                for _, r in ipairs(rewardList) do
                    local link
                    local itemID
                    if type(r) == "string" then
                        link = r
                        itemID = GetItemInfoInstant(link)
                    elseif type(r) == "number" then
                        itemID = tonumber(r)
                    elseif type(r) == "table" then
                        link = r.itemLink or r.hyperlink or r.link
                        local itemDBID = GetRewardItemDBID(r)
                        if (type(link) ~= "string" or link == "") and itemDBID then
                            link = ResolveWeeklyRewardItemLink(itemDBID)
                        end

                        itemID = tonumber(r.itemID or r.itemId or r.id)
                            or (type(link) == "string" and GetItemInfoInstant(link))
                    end

                    if itemID and selected[tonumber(itemID)] and not NIH.__vaultNotified[tonumber(itemID)] then
                        NIH.__vaultNotified[tonumber(itemID)] = true

                        if allowNotify then
                            PlayNotificationSound("availabilityVaultSound", "TwichUI Notification 8")
                        end

                        -- Prefer a real item link for display/ilvl; resolve asynchronously if needed.
                        if allowNotify then
                            -- Prefer a real item link for display/ilvl; resolve asynchronously if needed.
                            if type(link) == "string" and link ~= "" then
                                local ilvl = GetEffectiveItemLevel(link, nil)
                                ShowAndLog("VAULT", link, ilvl, nil, 1)
                            else
                                GetItemInfoTable(itemID, function(info)
                                    local resolvedLink = info and info.link
                                    if type(resolvedLink) == "string" and resolvedLink ~= "" then
                                        local ilvl = GetEffectiveItemLevel(resolvedLink, nil)
                                        ShowAndLog("VAULT", resolvedLink, ilvl, nil, 1)
                                    else
                                        -- Last resort: still show something rather than being silent.
                                        ShowAndLog("VAULT", "item:" .. tostring(itemID), nil, nil, 1)
                                    end
                                end)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function IsGreatVaultDebugEnabled()
    return CM:GetProfileSettingSafe("developer.testing.mythicPlus.greatVaultDebug.enabled", false) == true
end

local function VaultDebugOnce(tag, lines)
    if not IsGreatVaultDebugEnabled() then return end
    NIH.__vaultUiDebugOnce = NIH.__vaultUiDebugOnce or {}
    local key = tostring(tag or "")
    if NIH.__vaultUiDebugOnce[key] then return end
    NIH.__vaultUiDebugOnce[key] = true

    Logger.Debug("VaultUI Debug: " .. key)
    if type(lines) == "table" then
        for _, line in ipairs(lines) do
            Logger.Debug("  " .. tostring(line))
        end
    end
end

local function VaultDebugThrottled(tag, lines, interval)
    if not IsGreatVaultDebugEnabled() then return end
    interval = tonumber(interval) or 0.75
    NIH.__vaultUiDebugLast = NIH.__vaultUiDebugLast or {}

    local now = (type(_G.GetTime) == "function" and _G.GetTime()) or 0
    local key = tostring(tag or "")
    local last = NIH.__vaultUiDebugLast[key] or 0
    if (now - last) < interval then
        return
    end
    NIH.__vaultUiDebugLast[key] = now

    Logger.Debug("VaultUI Debug: " .. key)
    if type(lines) == "table" then
        for _, line in ipairs(lines) do
            Logger.Debug("  " .. tostring(line))
        end
    end
end

local VAULT_FRAME_CANDIDATES = {
    "WeeklyRewardsFrame",
    "GreatVaultFrame",
    "GreatVault",
    "WeeklyRewards",
}

local function GetVaultRootFrame()
    local fallback = rawget(_G, "WeeklyRewardsFrame")
    for i = 1, #VAULT_FRAME_CANDIDATES do
        local name = VAULT_FRAME_CANDIDATES[i]
        local f = rawget(_G, name)
        if f and type(f.IsShown) == "function" and f:IsShown() then
            return f, name
        end
        if f and type(f.IsShown) ~= "function" then
            -- If it doesn't have IsShown but exists, keep it as a fallback.
            fallback = fallback or f
        end
    end
    return fallback, fallback and "WeeklyRewardsFrame" or nil
end

-- Great Vault UI highlight: animated pixel glow around BiS rewards when the vault window is open.
local function CreatePixelGlow(parent)
    if not parent or not parent.CreateTexture then return nil end

    local ElvUI = rawget(_G, "ElvUI")
    local E = ElvUI and ElvUI[1]
    local borderTexture = (E and E.media and (E.media.blankTex or E.media.normTex)) or "Interface\\Buttons\\WHITE8X8"

    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 20)

    local thickness = 2
    local offset = 2

    local function NewEdge()
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetTexture(borderTexture)
        t:SetBlendMode("ADD")
        return t
    end

    f.top = NewEdge()
    f.bottom = NewEdge()
    f.left = NewEdge()
    f.right = NewEdge()

    f.top:SetPoint("TOPLEFT", parent, "TOPLEFT", -offset, offset)
    f.top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", offset, offset)
    f.top:SetHeight(thickness)

    f.bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -offset, -offset)
    f.bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", offset, -offset)
    f.bottom:SetHeight(thickness)

    f.left:SetPoint("TOPLEFT", parent, "TOPLEFT", -offset, offset)
    f.left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -offset, -offset)
    f.left:SetWidth(thickness)

    f.right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", offset, offset)
    f.right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", offset, -offset)
    f.right:SetWidth(thickness)

    f.anim = f:CreateAnimationGroup()
    f.anim:SetLooping("BOUNCE")
    local a = f.anim:CreateAnimation("Alpha")
    a:SetFromAlpha(0.15)
    a:SetToAlpha(1.0)
    a:SetDuration(0.85)
    a:SetSmoothing("IN_OUT")

    return f
end

local VaultHighlight = {
    hooked = false,
    glowByTarget = setmetatable({}, { __mode = "k" }),
    active = setmetatable({}, { __mode = "k" }),
    listener = nil,
}

-- Forward declaration (used by vault-open hooks defined below).
local EnsureVaultHooks

local __vaultOpenHooksInstalled = false
local function HookVaultOpenFunctions()
    if __vaultOpenHooksInstalled then return end
    __vaultOpenHooksInstalled = true

    local function OnVaultMaybeOpened()
        if _G.C_Timer and type(_G.C_Timer.After) == "function" then
            _G.C_Timer.After(0, function()
                EnsureVaultHooks()
                if MP and MP.BestInSlotNotificationHandler then
                    if MP.BestInSlotNotificationHandler.__ScanVaultForBiS then
                        MP.BestInSlotNotificationHandler:__ScanVaultForBiS()
                    end
                    if MP.BestInSlotNotificationHandler.__UpdateVaultHighlights then
                        MP.BestInSlotNotificationHandler:__UpdateVaultHighlights()
                    end
                end
            end)
        else
            EnsureVaultHooks()
            if MP and MP.BestInSlotNotificationHandler then
                if MP.BestInSlotNotificationHandler.__ScanVaultForBiS then
                    MP.BestInSlotNotificationHandler:__ScanVaultForBiS()
                end
                if MP.BestInSlotNotificationHandler.__UpdateVaultHighlights then
                    MP.BestInSlotNotificationHandler:__UpdateVaultHighlights()
                end
            end
        end
    end

    -- These are the most common entry points for opening the Great Vault.
    if type(_G.WeeklyRewards_ShowUI) == "function" then
        hooksecurefunc("WeeklyRewards_ShowUI", OnVaultMaybeOpened)
    end
    if type(_G.ToggleWeeklyRewardsPanel) == "function" then
        hooksecurefunc("ToggleWeeklyRewardsPanel", OnVaultMaybeOpened)
    end

    -- If the frame already exists, hook its Show call too.
    local frame = rawget(_G, "WeeklyRewardsFrame")
    if frame and type(frame.Show) == "function" then
        hooksecurefunc(frame, "Show", OnVaultMaybeOpened)
    end
end

local function SetGlowColor(glow, r, g, b, a)
    if not glow then return end
    if glow.top then glow.top:SetVertexColor(r, g, b, a) end
    if glow.bottom then glow.bottom:SetVertexColor(r, g, b, a) end
    if glow.left then glow.left:SetVertexColor(r, g, b, a) end
    if glow.right then glow.right:SetVertexColor(r, g, b, a) end
end

local function GetAvailabilityColor()
    local c = CM:GetProfileSettingSafe(KEY_PREFIX .. "frameBorderColorAvailable", { r = 0.23, g = 0.62, b = 1.00, a = 1 })
    return tonumber(c.r) or 1, tonumber(c.g) or 1, tonumber(c.b) or 1, tonumber(c.a) or 1
end

local GetCandidateItemLink

local function GetCandidateItemID(frame)
    if not frame then return nil end
    if frame.itemID and tonumber(frame.itemID) then
        return tonumber(frame.itemID)
    end

    if frame.itemId and tonumber(frame.itemId) then
        return tonumber(frame.itemId)
    end

    if type(frame.itemInfo) == "table" and frame.itemInfo.itemID and tonumber(frame.itemInfo.itemID) then
        return tonumber(frame.itemInfo.itemID)
    end

    if type(frame.rewardInfo) == "table" and frame.rewardInfo.itemID and tonumber(frame.rewardInfo.itemID) then
        return tonumber(frame.rewardInfo.itemID)
    end

    if type(frame.data) == "table" and frame.data.itemID and tonumber(frame.data.itemID) then
        return tonumber(frame.data.itemID)
    end

    -- Some WeeklyRewards widgets expose an itemDBID (not an itemID).
    local itemDBID = tonumber(frame.itemDBID or frame.itemDbID or frame.itemDBId)
    if not itemDBID and type(frame.rewardInfo) == "table" then
        itemDBID = tonumber(frame.rewardInfo.itemDBID or frame.rewardInfo.itemDbID or frame.rewardInfo.itemDBId)
    end
    if itemDBID and _G.C_WeeklyRewards then
        local fn = _G.C_WeeklyRewards.GetItemHyperlink or _G.C_WeeklyRewards.GetItemLink
        if type(fn) == "function" then
            local ok, l = pcall(fn, itemDBID)
            if ok and type(l) == "string" and l ~= "" then
                local itemID = GetItemInfoInstant(l)
                if type(itemID) == "number" then
                    return itemID
                end
                local id = tonumber(itemID)
                if id then return id end
            end
        end
    end

    do
        -- Many reward widgets store item data on a nested item/button/frame.
        local sub = frame.Item or frame.item or frame.ItemFrame or frame.itemFrame or frame.ItemButton or
            frame.itemButton or frame.Reward or frame.reward
        if type(sub) == "table" and sub ~= frame then
            local id = GetCandidateItemID(sub)
            if id then return id end
        end
    end

    local link = frame.itemLink or frame.hyperlink or frame.link
    if type(link) == "string" and link ~= "" then
        local id = GetItemInfoInstant(link)
        if type(id) == "number" then
            return id
        end
        return tonumber(id)
    end

    if type(frame.GetHyperlink) == "function" then
        local ok, h = pcall(frame.GetHyperlink, frame)
        if ok and type(h) == "string" and h ~= "" then
            local id = GetItemInfoInstant(h)
            if type(id) == "number" then
                return id
            end
            return tonumber(id)
        end
    end

    if type(frame.GetItemLocation) == "function" and _G.C_Item and type(_G.C_Item.GetItemLink) == "function" then
        local ok, loc = pcall(frame.GetItemLocation, frame)
        if ok and loc then
            local ok2, l = pcall(_G.C_Item.GetItemLink, loc)
            if ok2 and type(l) == "string" and l ~= "" then
                local id = GetItemInfoInstant(l)
                if type(id) == "number" then
                    return id
                end
                return tonumber(id)
            end
        end
    end

    do
        local l = GetCandidateItemLink(frame)
        if type(l) == "string" and l ~= "" then
            local id = GetItemInfoInstant(l)
            if type(id) == "number" then
                return id
            end
            return tonumber(id)
        end
    end

    return nil
end

GetCandidateItemLink = function(frame)
    if not frame then return nil end

    local link = frame.itemLink or frame.hyperlink or frame.link
    if type(link) == "string" and link ~= "" then
        return link
    end

    if type(frame.GetHyperlink) == "function" then
        local ok, h = pcall(frame.GetHyperlink, frame)
        if ok and type(h) == "string" and h ~= "" then
            return h
        end
    end

    if type(frame.GetItemLocation) == "function" and _G.C_Item and type(_G.C_Item.GetItemLink) == "function" then
        local ok, loc = pcall(frame.GetItemLocation, frame)
        if ok and loc then
            local ok2, l = pcall(_G.C_Item.GetItemLink, loc)
            if ok2 and type(l) == "string" and l ~= "" then
                return l
            end
        end
    end

    local itemDBID = tonumber(frame.itemDBID or frame.itemDbID or frame.itemDBId)
    if not itemDBID and type(frame.rewardInfo) == "table" then
        itemDBID = tonumber(frame.rewardInfo.itemDBID or frame.rewardInfo.itemDbID or frame.rewardInfo.itemDBId)
    end
    if itemDBID and _G.C_WeeklyRewards then
        local fn = _G.C_WeeklyRewards.GetItemHyperlink or _G.C_WeeklyRewards.GetItemLink
        if type(fn) == "function" then
            local ok, l = pcall(fn, itemDBID)
            if ok and type(l) == "string" and l ~= "" then
                return l
            end
        end
    end

    -- Some vault reward buttons expose a displayedItemDBID (often a large/opaque value).
    -- Try resolving it through C_WeeklyRewards without converting it.
    local displayed = frame.displayedItemDBID or frame.displayedItemDbID or frame.displayedItemDBId
    if displayed ~= nil and _G.C_WeeklyRewards then
        local fn = _G.C_WeeklyRewards.GetItemHyperlink or _G.C_WeeklyRewards.GetItemLink
        if type(fn) == "function" then
            local ok, l = pcall(fn, displayed)
            if ok and type(l) == "string" and l ~= "" then
                return l
            end
        end
    end

    do
        local sub = frame.Item or frame.item or frame.ItemFrame or frame.itemFrame or frame.ItemButton or
            frame.itemButton or frame.Reward or frame.reward
        if type(sub) == "table" and sub ~= frame then
            local l = GetCandidateItemLink(sub)
            if l then return l end
        end
    end

    return nil
end

local function RequestWeeklyRewardsData()
    local C_WeeklyRewards = _G.C_WeeklyRewards
    if not C_WeeklyRewards then return end
    if type(C_WeeklyRewards.RequestRewards) == "function" then
        pcall(C_WeeklyRewards.RequestRewards)
    end
    if type(C_WeeklyRewards.RequestActivities) == "function" then
        pcall(C_WeeklyRewards.RequestActivities)
    end
end

local function ClearVaultHighlights()
    for target in pairs(VaultHighlight.active) do
        local glow = VaultHighlight.glowByTarget[target]
        if glow then
            if glow.anim then glow.anim:Stop() end
            glow:Hide()
        end
        VaultHighlight.active[target] = nil
    end
end

EnsureVaultHooks = function()
    if VaultHighlight.hooked then return end
    local frame
    for i = 1, #VAULT_FRAME_CANDIDATES do
        local name = VAULT_FRAME_CANDIDATES[i]
        local f = rawget(_G, name)
        if f and type(f.HookScript) == "function" then
            frame = f
            break
        end
    end
    if not frame then return end

    VaultHighlight.hooked = true
    frame:HookScript("OnShow", function()
        if IsGreatVaultDebugEnabled() then
            -- Reset per-open so async population doesn't get hidden by "once" logging.
            NIH.__vaultUiDebugOnce = {}
            NIH.__vaultUiDebugLast = {}
        end
        -- Delay one frame so the reward buttons are populated.
        if _G.C_Timer and type(_G.C_Timer.After) == "function" then
            local function Refresh()
                RequestWeeklyRewardsData()
                CheckGreatVaultForBiS()
                if MP and MP.BestInSlotNotificationHandler then
                    if MP.BestInSlotNotificationHandler.__UpdateVaultHighlights then
                        MP.BestInSlotNotificationHandler:__UpdateVaultHighlights()
                    end
                    if MP.BestInSlotNotificationHandler.__ScanVaultForBiS then
                        MP.BestInSlotNotificationHandler:__ScanVaultForBiS()
                    end
                end
            end

            -- The vault UI often populates asynchronously; retry a couple times.
            _G.C_Timer.After(0, Refresh)
            _G.C_Timer.After(0.2, Refresh)
            _G.C_Timer.After(1.0, Refresh)
            _G.C_Timer.After(2.5, Refresh)
        end
    end)
    frame:HookScript("OnHide", function()
        ClearVaultHighlights()
    end)

    if type(frame.Update) == "function" then
        hooksecurefunc(frame, "Update", function()
            RequestWeeklyRewardsData()
            CheckGreatVaultForBiS()
            if MP and MP.BestInSlotNotificationHandler then
                if MP.BestInSlotNotificationHandler.__UpdateVaultHighlights then
                    MP.BestInSlotNotificationHandler:__UpdateVaultHighlights()
                end
                if MP.BestInSlotNotificationHandler.__ScanVaultForBiS then
                    MP.BestInSlotNotificationHandler:__ScanVaultForBiS()
                end
            end
        end)
    end
end

function NIH:__ScanVaultForBiS()
    local frame, frameName = GetVaultRootFrame()
    if not frame or type(frame.IsShown) ~= "function" or not frame:IsShown() then
        if IsGreatVaultDebugEnabled() then
            local lines = { "vaultRoot=" .. tostring(frameName) }
            for i = 1, #VAULT_FRAME_CANDIDATES do
                local name = VAULT_FRAME_CANDIDATES[i]
                local f = rawget(_G, name)
                lines[#lines + 1] = string.format(
                    "%s exists=%s shown=%s",
                    tostring(name),
                    tostring(f ~= nil),
                    tostring(f and type(f.IsShown) == "function" and f:IsShown() or false)
                )
            end
            VaultDebugOnce("scan:frame-not-shown", lines)
        end
        return
    end

    EnsureVaultHooks()

    local selected = GetSelectedBiSItemIDs()
    if type(selected) ~= "table" then
        return
    end

    local selectedCount = 0
    for _ in pairs(selected) do selectedCount = selectedCount + 1 end

    NIH.__vaultNotified = NIH.__vaultNotified or {}

    local seen = {}
    local visited = 0
    local iconNodes = 0
    local itemNodes = 0
    local matched = 0
    local samples = {}
    local function Visit(node)
        if not node or seen[node] then return end
        seen[node] = true
        visited = visited + 1

        local hasIcon = node.Icon or node.icon or node.IconTexture
        if not hasIcon and type(node.Item) == "table" then
            hasIcon = node.Item.Icon or node.Item.icon or node.Item.IconTexture
        end
        if hasIcon then
            iconNodes = iconNodes + 1
        end

        local itemID = GetCandidateItemID(node)
        if itemID then
            itemNodes = itemNodes + 1
            if #samples < 12 and hasIcon then
                local name = (type(node.GetName) == "function" and node:GetName()) or nil
                local otype = (type(node.GetObjectType) == "function" and node:GetObjectType()) or type(node)
                local link = GetCandidateItemLink(node)
                samples[#samples + 1] = string.format(
                    "node=%s type=%s itemID=%s link=%s",
                    tostring(name or "<unnamed>"),
                    tostring(otype),
                    tostring(itemID),
                    tostring(link)
                )
            end
        elseif IsGreatVaultDebugEnabled() and hasIcon and #samples < 12 then
            local name = (type(node.GetName) == "function" and node:GetName()) or nil
            local otype = (type(node.GetObjectType) == "function" and node:GetObjectType()) or type(node)
            local itemDBID = tonumber(node.itemDBID or node.itemDbID or node.itemDBId)
            if not itemDBID and type(node.rewardInfo) == "table" then
                itemDBID = tonumber(node.rewardInfo.itemDBID or node.rewardInfo.itemDbID or node.rewardInfo.itemDBId)
            end
            if not itemDBID and type(node.data) == "table" then
                itemDBID = tonumber(node.data.itemDBID or node.data.itemDbID or node.data.itemDBId)
            end
            local link = GetCandidateItemLink(node)
            samples[#samples + 1] = string.format(
                "node=%s type=%s itemID=<nil> itemDBID=%s link=%s",
                tostring(name or "<unnamed>"),
                tostring(otype),
                tostring(itemDBID),
                tostring(link)
            )
        end
        if itemID and selected[itemID] and not NIH.__vaultNotified[itemID] then
            NIH.__vaultNotified[itemID] = true
            matched = matched + 1
            PlayNotificationSound("availabilityVaultSound", "TwichUI Notification 8")

            local link = GetCandidateItemLink(node)
            if type(link) == "string" and link ~= "" then
                local ilvl = GetEffectiveItemLevel(link, nil)
                ShowAndLog("VAULT", link, ilvl, nil, 1)
            else
                GetItemInfoTable(itemID, function(info)
                    local resolved = info and info.link
                    if type(resolved) == "string" and resolved ~= "" then
                        local ilvl = GetEffectiveItemLevel(resolved, nil)
                        ShowAndLog("VAULT", resolved, ilvl, nil, 1)
                    else
                        ShowAndLog("VAULT", "item:" .. tostring(itemID), nil, nil, 1)
                    end
                end)
            end
        end

        if type(node.GetChildren) == "function" then
            local children = { node:GetChildren() }
            for i = 1, #children do
                Visit(children[i])
            end
        end
    end

    Visit(frame)

    VaultDebugThrottled("scan:summary", {
        "selectedBiSCount=" .. tostring(selectedCount),
        "visitedNodes=" .. tostring(visited),
        "nodesWithIconField=" .. tostring(iconNodes),
        "nodesWithItemID=" .. tostring(itemNodes),
        "matchedBiSInVault=" .. tostring(matched),
        "sampleCount=" .. tostring(#samples),
        unpack(samples),
    }, 0.9)
end

function NIH:__UpdateVaultHighlights()
    local frame = select(1, GetVaultRootFrame())
    if not frame or not frame.IsShown or not frame:IsShown() then
        ClearVaultHighlights()
        return
    end

    EnsureVaultHooks()

    local selected = GetSelectedBiSItemIDs()
    if type(selected) ~= "table" then
        ClearVaultHighlights()
        return
    end

    local r, g, b, a = GetAvailabilityColor()

    local newActive = {}
    local seen = {}

    local function Visit(node)
        if not node or seen[node] then return end
        seen[node] = true

        local hasIcon = node.Icon or node.icon or node.IconTexture
        if not hasIcon and type(node.Item) == "table" then
            hasIcon = node.Item.Icon or node.Item.icon or node.Item.IconTexture
        end

        if hasIcon then
            local itemID = GetCandidateItemID(node)
            if itemID and selected[itemID] then
                -- Track vault reward selection so we can still notify "BiS Acquired/Upgrade"
                -- even when loot chat messages are disabled.
                if type(node.HookScript) == "function" and type(node.GetScript) == "function" then
                    local onClick = node:GetScript("OnClick")
                    if type(onClick) == "function" then
                        NIH.__vaultClickHooked = NIH.__vaultClickHooked or setmetatable({}, { __mode = "k" })
                        if not NIH.__vaultClickHooked[node] then
                            NIH.__vaultClickHooked[node] = true
                            local capturedItemID = tonumber(itemID)
                            node:HookScript("OnClick", function(btn)
                                if not capturedItemID then return end
                                local link = GetCandidateItemLink(btn) or GetCandidateItemLink(node)
                                NIH.__vaultPendingClaim = {
                                    itemID = capturedItemID,
                                    link = (type(link) == "string" and link ~= "" and link) or nil,
                                    at = (_G.GetTime and _G.GetTime()) or 0,
                                    attempts = 0,
                                }
                            end)
                        end
                    end
                end

                local glow = VaultHighlight.glowByTarget[node]
                if not glow then
                    glow = CreatePixelGlow(node)
                    VaultHighlight.glowByTarget[node] = glow
                end
                if glow then
                    SetGlowColor(glow, r, g, b, a)
                    glow:Show()
                    if glow.anim and not glow.anim:IsPlaying() then
                        glow.anim:Play()
                    end
                    newActive[node] = true
                end
            end
        end

        if type(node.GetChildren) == "function" then
            local children = { node:GetChildren() }
            for i = 1, #children do
                Visit(children[i])
            end
        end
    end

    Visit(frame)

    -- Remove glows that are no longer active.
    for target in pairs(VaultHighlight.glowByTarget) do
        if VaultHighlight.glowByTarget[target] and not newActive[target] then
            local glow = VaultHighlight.glowByTarget[target]
            if glow then
                if glow.anim then glow.anim:Stop() end
                glow:Hide()
            end
        end
    end

    VaultHighlight.active = setmetatable(newActive, { __mode = "k" })
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
    elseif event == "BAG_UPDATE_DELAYED" then
        MaybeNotifyPendingVaultClaim()
    elseif event == "START_LOOT_ROLL" then
        local rollID = ...
        OnStartLootRoll(rollID)
    elseif event == "WEEKLY_REWARDS_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        CheckGreatVaultForBiS()
        if NIH then
            if NIH.__ScanVaultForBiS then
                NIH:__ScanVaultForBiS()
            end
            if NIH.__UpdateVaultHighlights then
                NIH:__UpdateVaultHighlights()
            end
        end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        -- The Great Vault is most often opened via the bank interaction, which can bypass WeeklyRewards_ShowUI.
        -- We don't need to identify the interaction type; just probe for WeeklyRewardsFrame visibility.
        if IsGreatVaultDebugEnabled() then
            local arg1 = select(1, ...)
            local arg2 = select(2, ...)
            VaultDebugThrottled("event:" .. tostring(event), {
                "arg1=" .. tostring(arg1),
                "arg2=" .. tostring(arg2),
            }, 0.9)
        end

        if _G.C_Timer and type(_G.C_Timer.After) == "function" then
            local function Refresh()
                if not NIH then return end
                RequestWeeklyRewardsData()
                EnsureVaultHooks()
                if NIH.__ScanVaultForBiS then NIH:__ScanVaultForBiS() end
                if NIH.__UpdateVaultHighlights then NIH:__UpdateVaultHighlights() end
            end

            _G.C_Timer.After(0, Refresh)
            _G.C_Timer.After(0.2, Refresh)
            _G.C_Timer.After(1.0, Refresh)
            _G.C_Timer.After(2.5, Refresh)
        end
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
    self.frame:RegisterEvent("BAG_UPDATE_DELAYED")
    self.frame:RegisterEvent("START_LOOT_ROLL")
    self.frame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
    self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- Opening the vault via the bank uses the interaction manager.
    self.frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    self.frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")

    -- Hook Great Vault UI when Blizzard_WeeklyRewards loads.
    if not self.__vaultHighlightListener then
        self.__vaultHighlightListener = CreateFrame("Frame")
        self.__vaultHighlightListener:RegisterEvent("ADDON_LOADED")
        self.__vaultHighlightListener:SetScript("OnEvent", function(_, _, addonName)
            addonName = tostring(addonName or "")
            if addonName:lower():find("weeklyrewards", 1, true) then
                if Logger and type(Logger.Debug) == "function" then
                    Logger.Debug("WeeklyRewards addon loaded: " .. addonName)
                end
                EnsureVaultHooks()
                HookVaultOpenFunctions()
                if self.__UpdateVaultHighlights then
                    self:__UpdateVaultHighlights()
                end
                if self.__ScanVaultForBiS then
                    self:__ScanVaultForBiS()
                end
            end
        end)
    end

    -- If it's already loaded, hook immediately.
    if rawget(_G, "WeeklyRewardsFrame") then
        EnsureVaultHooks()
    end

    -- Also hook the most common open-vault functions so we refresh even if ADDON_LOADED isn't observed.
    HookVaultOpenFunctions()

    -- reset per-session availability caches
    self.__rollNotified = {}
    self.__vaultNotified = {}

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

    if self.__vaultHighlightListener then
        self.__vaultHighlightListener:UnregisterAllEvents()
        self.__vaultHighlightListener:SetScript("OnEvent", nil)
        self.__vaultHighlightListener = nil
    end
    ClearVaultHighlights()

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

        PlayNotificationSound("notificationSound", "TwichUI Green Dude Gets Loot")
        ShowAndLog(kind or "FOUND", link, tonumber(receivedILvl) or nil, tonumber(previousILvl) or nil, quantity)
    end

    local info = GetItemInfoTable(normalized, function(filled)
        Fire(filled and filled.link)
    end)

    if info and info.link then
        Fire(info.link)
    end
end

--- Developer/testing helper: simulate a START_LOOT_ROLL event for an item.
--- This uses the same internal path as the real event handler, including GetLootRollItemLink/GetLootRollItemInfo.
--- @param item string|number itemID or itemLink
--- @param quantity number|nil
--- @param ensureSelected boolean|nil Temporarily add the item to the BiS selection list for the test.
--- @param ensureEnabled boolean|nil Temporarily enable the Roll availability setting for the test.
function NIH:TestSimulateAvailabilityRoll(item, quantity, ensureSelected, ensureEnabled)
    quantity = tonumber(quantity) or 1
    if quantity < 1 then quantity = 1 end

    if ensureSelected == nil then ensureSelected = true end
    if ensureEnabled == nil then ensureEnabled = true end

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
            Logger.Error("BestInSlotNotificationHandler:TestSimulateAvailabilityRoll failed to resolve item: " ..
                tostring(item))
            return
        end

        local function DoSim()
            self.__rollNotified = self.__rollNotified or {}
            self.__testRollCounter = (tonumber(self.__testRollCounter) or 90000) + 1
            local rollID = self.__testRollCounter
            self.__rollNotified[rollID] = nil

            local oldLinkFn = GetLootRollItemLink
            local oldInfoFn = GetLootRollItemInfo

            GetLootRollItemLink = function(id)
                if tonumber(id) == tonumber(rollID) then
                    return link
                end
                if type(oldLinkFn) == "function" then
                    return oldLinkFn(id)
                end
                return nil
            end

            GetLootRollItemInfo = function(id)
                if tonumber(id) == tonumber(rollID) then
                    -- texture, name, count, ...; only count is used by our handler.
                    return nil, nil, quantity
                end
                if type(oldInfoFn) == "function" then
                    return oldInfoFn(id)
                end
                return nil
            end

            local ok, err = pcall(function()
                OnStartLootRoll(rollID)
            end)

            GetLootRollItemLink = oldLinkFn
            GetLootRollItemInfo = oldInfoFn

            if not ok then
                Logger.Error("TestSimulateAvailabilityRoll error: " .. tostring(err))
            end
        end

        local function Run()
            if ensureSelected then
                WithTemporaryBiSSelection(link, DoSim)
            else
                DoSim()
            end
        end

        if ensureEnabled then
            WithTemporaryProfileSetting(KEY_PREFIX .. "availabilityRollEnabled", true, Run)
        else
            Run()
        end
    end

    local info = GetItemInfoTable(normalized, function(filled)
        Fire(filled and filled.link)
    end)
    if info and info.link then
        Fire(info.link)
    end
end

--- Developer/testing helper: simulate Great Vault availability containing a BiS item.
--- This uses the same internal scanning path as the real WEEKLY_REWARDS_UPDATE handler.
--- @param item string|number itemID or itemLink
--- @param ensureSelected boolean|nil Temporarily add the item to the BiS selection list for the test.
--- @param ensureEnabled boolean|nil Temporarily enable the Vault availability setting for the test.
function NIH:TestSimulateAvailabilityVault(item, ensureSelected, ensureEnabled)
    if ensureSelected == nil then ensureSelected = true end
    if ensureEnabled == nil then ensureEnabled = true end

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
            Logger.Error("BestInSlotNotificationHandler:TestSimulateAvailabilityVault failed to resolve item: " ..
                tostring(item))
            return
        end

        local function DoSim()
            self.__vaultNotified = self.__vaultNotified or {}
            local itemID = GetItemInfoInstant(link)
            if itemID then
                self.__vaultNotified[tonumber(itemID)] = nil
            end
            __lastVaultCheckAt = 0

            local oldWeekly = C_WeeklyRewards
            C_WeeklyRewards = {
                HasAvailableRewards = function() return true end,
                RequestRewards = function() end,
                RequestActivities = function() end,
                GetActivities = function()
                    return { { id = 424242 } }
                end,
                GetActivityItemRewards = function(_, _)
                    return { link }
                end,
            }

            local ok, err = pcall(function()
                CheckGreatVaultForBiS()
            end)

            C_WeeklyRewards = oldWeekly

            if not ok then
                Logger.Error("TestSimulateAvailabilityVault error: " .. tostring(err))
            end
        end

        local function Run()
            if ensureSelected then
                WithTemporaryBiSSelection(link, DoSim)
            else
                DoSim()
            end
        end

        if ensureEnabled then
            WithTemporaryProfileSetting(KEY_PREFIX .. "availabilityVaultEnabled", true, Run)
        else
            Run()
        end
    end

    local info = GetItemInfoTable(normalized, function(filled)
        Fire(filled and filled.link)
    end)
    if info and info.link then
        Fire(info.link)
    end
end
