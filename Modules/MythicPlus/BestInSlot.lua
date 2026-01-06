---@diagnostic disable-next-line: undefined-global
local T = unpack(Twich)
local _G = _G

--- @class MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")

--- @class MythicPlusBestInSlotSubmodule
local BestInSlot = MythicPlusModule.BestInSlot or {}
MythicPlusModule.BestInSlot = BestInSlot

--- @type LoggerModule
local Logger = T:GetModule("Logger")

--- @type ConfigurationModule
local CM = T:GetModule("Configuration")

local LSM = T.Libs and T.Libs.LSM

local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local GameTooltip = _G.GameTooltip

-- ElvUI integration
local ElvUI = rawget(_G, "ElvUI")
local E = ElvUI and ElvUI[1]

local SLOT_WIDTH = 270
local SLOT_HEIGHT = 44
local ICON_SIZE = 36

local FALLBACK_CUSTOM_ITEMS = {}

local function GetCustomItemsDB()
    -- Prefer profile-scoped custom items so they differ by profile/character.
    local profile = (T.db and T.db.profile)
    if type(profile) == "table" then
        profile.mythicPlus = profile.mythicPlus or {}
        profile.mythicPlus.bestInSlot = profile.mythicPlus.bestInSlot or {}
        local bis = profile.mythicPlus.bestInSlot
        bis.customItems = bis.customItems or {}

        -- One-time migration from legacy storage (account-wide).
        -- We intentionally do not delete legacy data here.
        local legacyRoot = rawget(_G, "TwichUIDB")
        if not bis.__migratedCustomItems and type(legacyRoot) == "table" and type(legacyRoot.CustomItems) == "table" then
            if #bis.customItems == 0 then
                for _, item in ipairs(legacyRoot.CustomItems) do
                    table.insert(bis.customItems, item)
                end
            end
            bis.__migratedCustomItems = true
        end

        return bis.customItems
    end

    -- Fallback (should be rare): legacy global storage.
    local legacy = rawget(_G, "TwichUIDB")
    if type(legacy) == "table" and type(legacy.CustomItems) == "table" then
        return legacy.CustomItems
    end
    return FALLBACK_CUSTOM_ITEMS
end

local SLOTS = {
    { name = "Head",           slotID = 1,  texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head" },
    { name = "Neck",           slotID = 2,  texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Neck" },
    { name = "Shoulder",       slotID = 3,  texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder" },
    { name = "Back",           slotID = 15, texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest" }, -- Back uses Chest icon usually or specific back icon
    { name = "Chest",          slotID = 5,  texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest" },
    { name = "Wrist",          slotID = 9,  texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Wrists" },
    { name = "Hands",          slotID = 10, texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Hands" },
    { name = "Waist",          slotID = 6,  texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Waist" },
    { name = "Legs",           slotID = 7,  texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Legs" },
    { name = "Feet",           slotID = 8,  texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Feet" },
    { name = "First Ring",     slotID = 11, texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger" },
    { name = "Second Ring",    slotID = 12, texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger" },
    { name = "First Trinket",  slotID = 13, texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket" },
    { name = "Second Trinket", slotID = 14, texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket" },
    { name = "MainHand",       slotID = 16, texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand" },
    { name = "OffHand",        slotID = 17, texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand" },
}

-- Fix Back texture
SLOTS[4].texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest" -- Placeholder, usually distinct

local VALID_EQUIP_LOCS = {
    [1] = { "INVTYPE_HEAD" },
    [2] = { "INVTYPE_NECK" },
    [3] = { "INVTYPE_SHOULDER" },
    [15] = { "INVTYPE_CLOAK" },
    [5] = { "INVTYPE_CHEST", "INVTYPE_ROBE" },
    [9] = { "INVTYPE_WRIST" },
    [10] = { "INVTYPE_HAND" },
    [6] = { "INVTYPE_WAIST" },
    [7] = { "INVTYPE_LEGS" },
    [8] = { "INVTYPE_FEET" },
    [11] = { "INVTYPE_FINGER" },
    [12] = { "INVTYPE_FINGER" },
    [13] = { "INVTYPE_TRINKET" },
    [14] = { "INVTYPE_TRINKET" },
    [16] = { "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_2HWEAPON", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT" },
    [17] = { "INVTYPE_WEAPON", "INVTYPE_WEAPONOFFHAND", "INVTYPE_HOLDABLE", "INVTYPE_SHIELD" },
}

local _, _, PLAYER_CLASS_ID = UnitClass("player")

-- Armor Types: 1=Cloth, 2=Leather, 3=Mail, 4=Plate
local CLASS_ARMOR_TYPE = {
    [1] = 4,  -- Warrior: Plate
    [2] = 4,  -- Paladin: Plate
    [3] = 3,  -- Hunter: Mail
    [4] = 2,  -- Rogue: Leather
    [5] = 1,  -- Priest: Cloth
    [6] = 4,  -- DK: Plate
    [7] = 3,  -- Shaman: Mail
    [8] = 1,  -- Mage: Cloth
    [9] = 1,  -- Warlock: Cloth
    [10] = 2, -- Monk: Leather
    [11] = 2, -- Druid: Leather
    [12] = 2, -- DH: Leather
    [13] = 3, -- Evoker: Mail
}

local CLASS_WEAPON_TYPES = {
    [1] = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [10] = true, [13] = true, [15] = true, [18] = true }, -- Warrior
    [2] = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true },                                                                             -- Paladin
    [3] = { [0] = true, [1] = true, [2] = true, [3] = true, [6] = true, [7] = true, [8] = true, [10] = true, [13] = true, [15] = true, [18] = true },                         -- Hunter
    [4] = { [0] = true, [4] = true, [7] = true, [13] = true, [15] = true, [2] = true, [3] = true, [18] = true },                                                              -- Rogue
    [5] = { [4] = true, [10] = true, [15] = true, [19] = true },                                                                                                              -- Priest
    [6] = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true },                                                                             -- DK
    [7] = { [0] = true, [1] = true, [4] = true, [5] = true, [10] = true, [13] = true, [15] = true },                                                                          -- Shaman
    [8] = { [7] = true, [10] = true, [15] = true, [19] = true },                                                                                                              -- Mage
    [9] = { [7] = true, [10] = true, [15] = true, [19] = true },                                                                                                              -- Warlock
    [10] = { [0] = true, [4] = true, [6] = true, [7] = true, [10] = true, [13] = true },                                                                                      -- Monk
    [11] = { [4] = true, [5] = true, [6] = true, [10] = true, [13] = true, [15] = true },                                                                                     -- Druid
    [12] = { [0] = true, [7] = true, [9] = true, [13] = true, [15] = true },                                                                                                  -- DH
    [13] = { [0] = true, [1] = true, [4] = true, [5] = true, [7] = true, [8] = true, [10] = true, [13] = true, [15] = true },                                                 -- Evoker
}

local function IsItemUsableByPlayer(itemClassID, itemSubClassID, itemEquipLoc)
    if not itemClassID or not itemSubClassID then return true end

    -- Weapons (ClassID 2)
    if itemClassID == 2 then
        local allowed = CLASS_WEAPON_TYPES[PLAYER_CLASS_ID]
        if allowed and allowed[itemSubClassID] then
            return true
        end
        return false
    end

    -- Armor (ClassID 4)
    if itemClassID == 4 then
        -- Always allow Cloaks (15), Rings (11), Necks (2), Trinkets (13, 14), Shields (6)
        -- Note: Shields are SubClass 6. Not all classes can use shields.
        -- Cloak is SubClass 1 (Cloth) usually, but EquipLoc is INVTYPE_CLOAK.

        if itemEquipLoc == "INVTYPE_CLOAK" or
            itemEquipLoc == "INVTYPE_NECK" or
            itemEquipLoc == "INVTYPE_FINGER" or
            itemEquipLoc == "INVTYPE_TRINKET" or
            itemEquipLoc == "INVTYPE_HOLDABLE" then -- Off-hand frill
            return true
        end

        -- Shields (SubClass 6)
        if itemSubClassID == 6 then
            -- Warrior, Paladin, Shaman
            if PLAYER_CLASS_ID == 1 or PLAYER_CLASS_ID == 2 or PLAYER_CLASS_ID == 7 then
                return true
            end
            return false
        end

        -- Main Armor Slots (Head, Chest, etc.)
        -- Check against primary armor type
        local primaryType = CLASS_ARMOR_TYPE[PLAYER_CLASS_ID]
        if itemSubClassID == primaryType then
            return true
        end

        -- Cosmetic / Generic?
        if itemSubClassID == 0 then return true end

        return false
    end

    return true
end

local function IsItemValidForSlot(itemEquipLoc, slotID)
    if not itemEquipLoc or not slotID then return true end -- Allow if unknown
    local validLocs = VALID_EQUIP_LOCS[slotID]
    if not validLocs then return true end                  -- Allow if slot not mapped

    for _, loc in ipairs(validLocs) do
        if loc == itemEquipLoc then return true end
    end
    return false
end

local Chooser = nil

local function GetCharacterDB()
    if not MythicPlusModule.Database or not MythicPlusModule.Database.GetForCurrentCharacter then return nil end
    local entry = MythicPlusModule.Database:GetForCurrentCharacter()
    if not entry then return nil end
    if not entry.BestInSlot then entry.BestInSlot = {} end
    return entry.BestInSlot
end

local ItemSourceCache = {}

local function CleanString(str)
    return string.lower(string.gsub(str, "[^%w]", ""))
end

local function TryPopulateTierSets(instanceLootCache, lootCache, nameCache)
    if type(instanceLootCache) ~= "table" then return false end
    if type(lootCache) ~= "table" then return false end
    if type(nameCache) ~= "table" then return false end

    if C_AddOns and C_AddOns.LoadAddOn and C_AddOns.IsAddOnLoaded then
        if not C_AddOns.IsAddOnLoaded("Blizzard_LootJournal") then
            C_AddOns.LoadAddOn("Blizzard_LootJournal")
        end
    end

    if not C_LootJournal or not C_LootJournal.GetItemSets or not C_LootJournal.GetItemSetItems then
        return false
    end

    local _, _, classID = UnitClass("player")
    local specID = GetSpecializationInfo(GetSpecialization())
    if not classID or not specID then return false end

    local itemSets = C_LootJournal.GetItemSets(classID, specID)
    if type(itemSets) ~= "table" or #itemSets == 0 then
        return false
    end

    if not instanceLootCache["Tier Sets"] then
        instanceLootCache["Tier Sets"] = {}
    end

    local seen = {}
    for _, id in ipairs(instanceLootCache["Tier Sets"]) do
        seen[id] = true
    end

    local addedAny = false

    for _, set in ipairs(itemSets) do
        if set and set.setID then
            local setItems = C_LootJournal.GetItemSetItems(set.setID)
            if type(setItems) == "table" then
                for _, item in ipairs(setItems) do
                    local itemID = item and item.itemID
                    if itemID then
                        if not seen[itemID] then
                            seen[itemID] = true
                            table.insert(instanceLootCache["Tier Sets"], itemID)
                            addedAny = true
                        end

                        if not lootCache[itemID] then
                            lootCache[itemID] = (set.name or "Tier Set") .. " (Tier Set)"

                            local itemName = GetItemInfo(itemID)
                            if itemName then
                                nameCache[CleanString(itemName)] = itemID
                            end
                        end
                    end
                end
            end
        end
    end

    return addedAny
end

local MEGA_DUNGEON_MAPPINGS = {
    ["Tazavesh: So'leah's Gambit"] = "Tazavesh, the Veiled Market",
    ["Tazavesh: Streets of Wonder"] = "Tazavesh, the Veiled Market",
    ["Operation: Mechagon - Junkyard"] = "Operation: Mechagon",
    ["Operation: Mechagon - Workshop"] = "Operation: Mechagon",
    ["Return to Karazhan: Lower"] = "Return to Karazhan",
    ["Return to Karazhan: Upper"] = "Return to Karazhan",
    ["Dawn of the Infinite: Galakrond's Fall"] = "Dawn of the Infinite",
    ["Dawn of the Infinite: Murozond's Rise"] = "Dawn of the Infinite",
}

local TierLootCache = nil
local TierNameCache = nil
local TierInstanceLootCache = nil
local TierItemLinkCache = nil

local function BuildTierCache(force)
    -- Check if we have in-memory cache
    if not force and TierLootCache and TierNameCache and TierInstanceLootCache then
        return
    end

    local currentVersion = select(1, GetBuildInfo())
    local storedVersion = MythicPlusModule.Database:GetGameVersion()
    local storedCache = MythicPlusModule.Database:GetItemCache()

    -- Check if we can load from DB
    if not force and storedCache and storedVersion == currentVersion then
        TierLootCache = storedCache.Loot or {}
        TierNameCache = storedCache.Name or {}
        TierInstanceLootCache = storedCache.InstanceLoot or {}
        TierItemLinkCache = storedCache.ItemLink or {}

        -- Backfill Tier Sets for older caches that predate this feature
        if not TierInstanceLootCache["Tier Sets"] or #TierInstanceLootCache["Tier Sets"] == 0 then
            local added = TryPopulateTierSets(TierInstanceLootCache, TierLootCache, TierNameCache)
            if added then
                MythicPlusModule.Database:SetItemCache({
                    Loot = TierLootCache,
                    Name = TierNameCache,
                    InstanceLoot = TierInstanceLootCache,
                    ItemLink = TierItemLinkCache
                })
            end
        end

        return
    end

    Logger.Info("Updating Mythic+ Item Cache. The game may run slow for a few moments...")

    if not C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    end

    local oldClassID, oldSpecID = EJ_GetLootFilter()
    local oldTier = EJ_GetCurrentTier()
    local oldDifficulty = EJ_GetDifficulty()

    -- EJ_SetLootFilter(0, 0)             -- Clear filters to see all loot
    -- Try setting to player class/spec to ensure we get SOMETHING
    -- local _, _, playerClassID = UnitClass("player")
    -- local playerSpecID = GetSpecializationInfo(GetSpecialization())
    -- EJ_SetLootFilter(playerClassID, playerSpecID)
    EJ_SetLootFilter(0, 0)

    local numTiers = EJ_GetNumTiers()

    -- Identify Valid Instances (Current Season)
    local validInstances = {}

    -- 1. Current Raid (from Current Tier)
    EJ_SelectTier(EJ_GetCurrentTier())
    local index = 1
    while true do
        local instanceID, instanceName = EJ_GetInstanceByIndex(index, true) -- isRaid=true
        if not instanceID then break end
        validInstances[instanceName] = true
        index = index + 1
    end

    -- 2. Current Expansion Dungeons (Always include these)
    index = 1
    while true do
        local instanceID, instanceName = EJ_GetInstanceByIndex(index, false) -- isRaid=false
        if not instanceID then break end
        validInstances[instanceName] = true
        if MEGA_DUNGEON_MAPPINGS[instanceName] then
            validInstances[MEGA_DUNGEON_MAPPINGS[instanceName]] = true
        end
        index = index + 1
    end

    -- 3. Current M+ Dungeons (Includes old dungeons in rotation)
    local dungeonsFound = false
    do
        local mpData = MythicPlusModule and MythicPlusModule.Data
        local maps = (mpData and type(mpData.GetCurrentSeasonMapsCached) == "function" and mpData.GetCurrentSeasonMapsCached())
        if not maps and C_MythicPlus and C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetSeasonMaps then
            local seasonID = C_MythicPlus.GetCurrentSeason()
            maps = seasonID and C_MythicPlus.GetSeasonMaps(seasonID) or nil
        end

        if maps and #maps > 0 then
            for _, mapId in ipairs(maps) do
                local name = (mpData and type(mpData.GetMapNameCached) == "function" and mpData.GetMapNameCached(mapId))
                    or (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapId))
                if name then
                    validInstances[name] = true
                    if MEGA_DUNGEON_MAPPINGS[name] then
                        validInstances[MEGA_DUNGEON_MAPPINGS[name]] = true
                    end
                end
            end
            dungeonsFound = true
        end
    end

    -- 4. Fallback (If API fails)
    -- If we found dungeons via EJ (Step 2), we don't strictly need a fallback list.
    -- The EJ scan ensures we at least have the current expansion's dungeons.

    local newLootCache = {}
    local newNameCache = {}
    local newInstanceLootCache = {}
    local newItemLinkCache = {}
    local processedInstances = {}

    local function ProcessInstance(isRaid)
        local index = 1
        while true do
            local instanceID, instanceName = EJ_GetInstanceByIndex(index, isRaid)
            if not instanceID then break end

            -- Filter: Only process valid instances
            if validInstances[instanceName] then
                -- Skip if already processed (prevents duplicates from multiple tiers)
                if processedInstances[instanceName] then
                    index = index + 1
                else
                    processedInstances[instanceName] = true

                    -- Normalize instance name for the cache key (Merge Mega Dungeons)
                    local cacheKeyName = instanceName
                    if MEGA_DUNGEON_MAPPINGS[instanceName] then
                        cacheKeyName = MEGA_DUNGEON_MAPPINGS[instanceName]
                    end

                    if not newInstanceLootCache[cacheKeyName] then
                        newInstanceLootCache[cacheKeyName] = {}
                    end
                    local instanceItems = newInstanceLootCache[cacheKeyName]
                    local seenInInstance = {}

                    EJ_SelectInstance(instanceID)
                    local encIndex = 1
                    local encCount = 0
                    local lootCount = 0
                    while true do
                        local name, _, encounterID = EJ_GetEncounterInfoByIndex(encIndex, instanceID)
                        if not name then break end
                        encCount = encCount + 1

                        local difficulties = isRaid and { 16, 15, 14, 17 } or { 23, 2, 1, 8 }
                        for _, diff in ipairs(difficulties) do
                            EJ_SetDifficulty(diff)
                            EJ_SelectInstance(instanceID)   -- Ensure instance is selected
                            EJ_SelectEncounter(encounterID) -- Select the encounter to populate loot list

                            local numLoot = EJ_GetNumLoot()
                            for i = 1, numLoot do
                                local item = C_EncounterJournal.GetLootInfoByIndex(i)
                                if item then
                                    lootCount = lootCount + 1
                                    if not newLootCache[item.itemID] then
                                        newLootCache[item.itemID] = instanceName .. " (" .. name .. ")"
                                    end

                                    -- Cache the specific link for each difficulty
                                    if not newItemLinkCache[item.itemID] then
                                        newItemLinkCache[item.itemID] = {}
                                    end
                                    newItemLinkCache[item.itemID][diff] = item.link

                                    local iName = item.name
                                    if not iName and item.link then
                                        iName = item.link:match("%[(.-)%]")
                                    end
                                    if iName then
                                        newNameCache[CleanString(iName)] = item.itemID
                                    end

                                    if not seenInInstance[item.itemID] then
                                        seenInInstance[item.itemID] = true
                                        table.insert(instanceItems, item.itemID)
                                    end
                                end
                            end
                        end
                        encIndex = encIndex + 1
                    end
                end
            end
            index = index + 1
        end
    end

    -- Scan ALL tiers, starting from newest
    for t = numTiers, 1, -1 do
        EJ_SelectTier(t)
        ProcessInstance(false) -- Dungeons
        ProcessInstance(true)  -- Raids
    end

    -- Scan Item Sets (Tier Sets) from Adventure Guide
    if C_AddOns and C_AddOns.LoadAddOn and C_AddOns.IsAddOnLoaded then
        if not C_AddOns.IsAddOnLoaded("Blizzard_LootJournal") then
            C_AddOns.LoadAddOn("Blizzard_LootJournal")
        end
    end
    if C_LootJournal and C_LootJournal.GetItemSets then
        local _, _, classID = UnitClass("player")
        local specID = GetSpecializationInfo(GetSpecialization())
        if classID and specID then
            local itemSets = C_LootJournal.GetItemSets(classID, specID)
            if itemSets then
                for _, set in ipairs(itemSets) do
                    local setItems = C_LootJournal.GetItemSetItems(set.setID)
                    if setItems then
                        for _, item in ipairs(setItems) do
                            -- Add to Instance Loot Cache under "Tier Sets"
                            if not newInstanceLootCache["Tier Sets"] then
                                newInstanceLootCache["Tier Sets"] = {}
                            end

                            local alreadyInList = false
                            for _, id in ipairs(newInstanceLootCache["Tier Sets"]) do
                                if id == item.itemID then
                                    alreadyInList = true
                                    break
                                end
                            end

                            if not alreadyInList then
                                table.insert(newInstanceLootCache["Tier Sets"], item.itemID)
                            end

                            -- If not already in cache, add it
                            if not newLootCache[item.itemID] then
                                newLootCache[item.itemID] = set.name .. " (Tier Set)"

                                -- Try to get item info (might not be cached yet)
                                local itemName = GetItemInfo(item.itemID)
                                if itemName then
                                    newNameCache[CleanString(itemName)] = item.itemID
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    EJ_SetLootFilter(oldClassID, oldSpecID)
    EJ_SelectTier(oldTier)
    EJ_SetDifficulty(oldDifficulty)

    -- Save to DB
    MythicPlusModule.Database:SetItemCache({
        Loot = newLootCache,
        Name = newNameCache,
        InstanceLoot = newInstanceLootCache,
        ItemLink = newItemLinkCache
    })
    MythicPlusModule.Database:SetGameVersion(currentVersion)

    -- Update local cache
    TierLootCache = newLootCache
    TierNameCache = newNameCache
    TierInstanceLootCache = newInstanceLootCache
    TierItemLinkCache = newItemLinkCache

    local count = 0
    for _ in pairs(newLootCache) do count = count + 1 end

    Logger.Info("Mythic+ Item Cache updated.")
end

function BestInSlot:RefreshCache()
    BuildTierCache(true)
end

function BestInSlot:ClearItemCache()
    local wipeFn = _G.wipe or (_G.table and _G.table.wipe)

    if MythicPlusModule.Database and MythicPlusModule.Database.SetItemCache then
        MythicPlusModule.Database:SetItemCache({ Loot = {}, Name = {}, InstanceLoot = {}, ItemLink = {} })
    end
    if MythicPlusModule.Database and MythicPlusModule.Database.SetGameVersion then
        MythicPlusModule.Database:SetGameVersion("")
    end

    if type(wipeFn) == "function" then
        wipeFn(ItemSourceCache)
    else
        for k in pairs(ItemSourceCache) do ItemSourceCache[k] = nil end
    end

    TierLootCache = nil
    TierNameCache = nil
    TierInstanceLootCache = nil
    TierItemLinkCache = nil

    Logger.Info("Best in Slot: Cleared item cache; it will rebuild on demand.")
end

local function ScanEJ(searchType, searchValue, limitTier)
    -- searchType: "ID" (find source of itemID) or "NAME" (find itemID of itemName)
    -- limitTier: if true, only scan the current tier (for performance)

    if limitTier then
        BuildTierCache(false)
        if searchType == "ID" then
            return TierLootCache and TierLootCache[searchValue] or nil
        elseif searchType == "NAME" then
            return TierNameCache and TierNameCache[CleanString(searchValue)] or nil
        end
        return nil
    end

    if not C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    end

    local oldClassID, oldSpecID = EJ_GetLootFilter()
    local oldTier = EJ_GetCurrentTier()
    local oldDifficulty = EJ_GetDifficulty()

    -- Try setting filter to player's class/spec first to ensure we see something
    -- local _, _, playerClassID = UnitClass("player")
    -- local playerSpecID = GetSpecializationInfo(GetSpecialization())
    -- EJ_SetLootFilter(playerClassID, playerSpecID)
    EJ_SetLootFilter(0, 0) -- Clear filters to see all loot

    local numTiers = EJ_GetNumTiers()

    local function ScanTier(tierIndex)
        EJ_SelectTier(tierIndex)

        local function ScanInstances(isRaid)
            local index = 1
            while true do
                local instanceID, instanceName = EJ_GetInstanceByIndex(index, isRaid)
                if not instanceID then break end

                -- 1. Select Instance to get encounters
                EJ_SelectInstance(instanceID)

                -- 2. Collect Encounters
                local encounters = {}
                local encIndex = 1
                while true do
                    local name, _, encounterID = EJ_GetEncounterInfoByIndex(encIndex, instanceID)
                    if not name then break end
                    table.insert(encounters, { name = name, id = encounterID })
                    encIndex = encIndex + 1
                end

                -- 3. Iterate Difficulties
                local difficulties = isRaid and { 16, 15, 14, 17 } or { 23, 2, 1, 8 }

                for _, diff in ipairs(difficulties) do
                    EJ_SetDifficulty(diff)
                    EJ_SelectInstance(instanceID) -- Select Instance AFTER setting difficulty

                    for _, enc in ipairs(encounters) do
                        local loot = C_EncounterJournal.GetLootInfo(enc.id)

                        if loot and #loot > 0 then
                            for _, item in ipairs(loot) do
                                if searchType == "ID" then
                                    if item.itemID == searchValue then
                                        return instanceName .. " (" .. enc.name .. ")"
                                    end
                                elseif searchType == "NAME" then
                                    -- Fuzzy match
                                    local iName = item.name
                                    if not iName and item.link then
                                        iName = item.link:match("%[(.-)%]")
                                    end
                                    if not iName then
                                        iName = GetItemInfo(item.itemID)
                                    end

                                    if iName then
                                        if CleanString(iName) == CleanString(searchValue) then
                                            return item.itemID
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                index = index + 1
            end
            return nil
        end

        -- Scan Dungeons first
        local result = ScanInstances(false)
        if result then return result end

        -- Scan Raids
        return ScanInstances(true)
    end

    -- 1. Scan Current Tier
    local result = ScanTier(numTiers)
    if result then
        -- Restore filters
        EJ_SetLootFilter(oldClassID, oldSpecID)
        EJ_SelectTier(oldTier)
        EJ_SetDifficulty(oldDifficulty)
        return result
    end

    -- If limited, stop here
    if limitTier then
        EJ_SetLootFilter(oldClassID, oldSpecID)
        EJ_SelectTier(oldTier)
        EJ_SetDifficulty(oldDifficulty)
        return nil
    end

    -- 2. Scan Previous Tiers if not found
    for i = numTiers - 1, 1, -1 do
        result = ScanTier(i)
        if result then break end
    end

    -- Restore filters
    EJ_SetLootFilter(oldClassID, oldSpecID)
    EJ_SelectTier(oldTier)
    EJ_SetDifficulty(oldDifficulty)

    return result
end

local function GetItemSource(itemID)
    if ItemSourceCache[itemID] ~= nil then
        if ItemSourceCache[itemID] == false then return nil end
        return ItemSourceCache[itemID]
    end
    if not itemID then return nil end

    -- Limit scan to current tier to prevent freezing
    local source = ScanEJ("ID", itemID, true)
    if source then
        ItemSourceCache[itemID] = source
        return source
    end

    ItemSourceCache[itemID] = false -- Not found
    return nil
end

local function GetSources()
    local dungeons = {}
    local mapIds = {}
    local seen = {}

    -- 1. Try C_MythicPlus.GetSeasonMaps (Current Season)
    do
        local mpData = MythicPlusModule and MythicPlusModule.Data
        local maps = (mpData and type(mpData.GetCurrentSeasonMapsCached) == "function" and mpData.GetCurrentSeasonMapsCached())
        if not maps and C_MythicPlus and C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetSeasonMaps then
            local seasonID = C_MythicPlus.GetCurrentSeason()
            maps = seasonID and C_MythicPlus.GetSeasonMaps(seasonID) or nil
        end

        if maps then
            for _, mapId in ipairs(maps) do
                if not seen[mapId] then
                    seen[mapId] = true
                    table.insert(mapIds, mapId)
                end
            end
        end
    end

    -- 2. Fallback to C_ChallengeMode.GetMapTable (All Challenge Mode Maps)
    -- DISABLED: This causes out-of-season dungeons (like Tazavesh) to appear when the API fails,
    -- creating a mismatch with the cache which only scans current season.
    -- if #mapIds == 0 and C_ChallengeMode and C_ChallengeMode.GetMapTable then
    --     local maps = C_ChallengeMode.GetMapTable()
    --     if maps then
    --         for _, mapId in ipairs(maps) do
    --             if not seen[mapId] then
    --                 seen[mapId] = true
    --                 table.insert(mapIds, mapId)
    --             end
    --         end
    --     end
    -- end

    -- Resolve Names
    local seenDungeons = {}
    for _, mapId in ipairs(mapIds) do
        local mpData = MythicPlusModule and MythicPlusModule.Data
        local name = (mpData and type(mpData.GetMapNameCached) == "function" and mpData.GetMapNameCached(mapId))
            or (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapId))
        if name then
            if MEGA_DUNGEON_MAPPINGS[name] then
                name = MEGA_DUNGEON_MAPPINGS[name]
            end

            if not seenDungeons[name] then
                seenDungeons[name] = true
                table.insert(dungeons, name)
            end
        end
    end
    table.sort(dungeons)

    -- Get Raids from Current Tier
    local raids = {}
    local currentTier = EJ_GetCurrentTier()
    EJ_SelectTier(currentTier)
    local index = 1
    while true do
        local instanceID, instanceName = EJ_GetInstanceByIndex(index, true)
        if not instanceID then break end
        table.insert(raids, instanceName)
        index = index + 1
    end
    table.sort(raids)

    -- 3. Hard Fallback
    if #dungeons == 0 then
        -- Fallback to scanning current EJ tier for dungeons
        local currentTier = EJ_GetCurrentTier()
        EJ_SelectTier(currentTier)
        local index = 1
        while true do
            local instanceID, instanceName = EJ_GetInstanceByIndex(index, false) -- isRaid=false
            if not instanceID then break end

            if MEGA_DUNGEON_MAPPINGS[instanceName] then
                instanceName = MEGA_DUNGEON_MAPPINGS[instanceName]
            end

            if not seenDungeons[instanceName] then
                seenDungeons[instanceName] = true
                table.insert(dungeons, instanceName)
            end
            index = index + 1
        end
        table.sort(dungeons)
    end

    local result = {
        {
            label = "All",
            options = { "All Items" }
        },
        {
            label = "Dungeons",
            options = dungeons
        },
        {
            label = "Raids",
            options = raids
        },
        {
            label = "Other",
            options = { "Custom Item" }
        }
    }

    if TierInstanceLootCache and TierInstanceLootCache["Tier Sets"] then
        -- Insert before "Other"
        table.insert(result, #result, {
            label = "Item Sets",
            options = { "Tier Sets" }
        })
    end

    return result
end

local function CreateChooserFrame(parent)
    local UpdateItemsList -- Forward declaration
    -- Parent to UIParent so it can be moved independently of the main window
    local f = CreateFrame("Frame", "TwichUI_BiS_Chooser", UIParent)

    -- Logic Initialization
    f.selectedSource = nil
    f.selectedItemLink = nil
    f.selectedDifficulty = 16 -- Default Mythic
    f.customSourceValue = "Other"
    f.sourceButtons = {}
    f.itemButtons = {}

    f:SetSize(750, 500)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(100)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    -- Animation Groups
    f.FadeInGroup = f:CreateAnimationGroup()
    f.FadeInAnim = f.FadeInGroup:CreateAnimation("Alpha")
    f.FadeInAnim:SetDuration(0.2)
    f.FadeInAnim:SetToAlpha(1)
    f.FadeInAnim:SetSmoothing("OUT")
    f.FadeInGroup:SetScript("OnFinished", function() f:SetAlpha(1) end)

    f.FadeOutGroup = f:CreateAnimationGroup()
    f.FadeOutAnim = f.FadeOutGroup:CreateAnimation("Alpha")
    f.FadeOutAnim:SetDuration(0.2)
    f.FadeOutAnim:SetToAlpha(0)
    f.FadeOutAnim:SetSmoothing("OUT")
    f.FadeOutGroup:SetScript("OnFinished", function()
        f:Hide()
        f:SetAlpha(1)
    end)

    function f:ShowAnimated()
        f.FadeOutGroup:Stop()
        if not f:IsShown() then
            f:SetAlpha(0)
            f:Show()
        end
        f.FadeInAnim:SetFromAlpha(f:GetAlpha())
        f.FadeInGroup:Play()
    end

    function f:HideAnimated()
        f.FadeInGroup:Stop()
        f.FadeOutAnim:SetFromAlpha(f:GetAlpha())
        f.FadeOutGroup:Play()
    end

    if E then
        f:SetTemplate("Default")
    else
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })
        f:SetBackdropColor(0, 0, 0, 1)
    end

    -- Hook for Shift+Click link insertion
    hooksecurefunc("ChatEdit_InsertLink", function(text)
        if f:IsVisible() and f.Input and f.Input:HasFocus() then
            f.Input:Insert(text)
        end
    end)

    f.Title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.Title:SetPoint("TOP", 0, -15)
    f.Title:SetText("Select Item")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() f:HideAnimated() end)
    if E then E:GetModule("Skins"):HandleCloseButton(close) end

    -- 1. Search Input
    local input = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    input:SetSize(300, 25)
    input:SetPoint("TOP", f.Title, "BOTTOM", 0, -20)
    input:SetAutoFocus(false)
    input:SetTextInsets(5, 5, 0, 0)
    input:SetFontObject("ChatFontNormal")
    input:SetText("Search Item...")
    if E then E:GetModule("Skins"):HandleEditBox(input) end
    f.Input = input

    -- Raid Difficulty Selector
    local diffSelector = CreateFrame("Frame", "TwichUI_BiS_DiffSelector", f, "UIDropDownMenuTemplate")
    diffSelector:SetPoint("LEFT", input, "RIGHT", 20, 0)
    diffSelector:Hide()
    f.DiffSelector = diffSelector
    UIDropDownMenu_SetWidth(diffSelector, 115)
    UIDropDownMenu_SetText(diffSelector, "Mythic")
    -- UIDropDownMenu_JustifyText(diffSelector, "LEFT") -- Removed to fix vertical alignment
    if E then E:GetModule("Skins"):HandleDropDownBox(diffSelector) end

    -- Fix vertical alignment of the main text
    local diffText = _G[diffSelector:GetName() .. "Text"]
    if diffText then
        diffText:ClearAllPoints()
        diffText:SetPoint("CENTER", diffSelector, "CENTER", 0, 2)
    end

    local function OnDiffSelect(self, arg1, arg2, checked)
        f.selectedDifficulty = arg1
        UIDropDownMenu_SetSelectedValue(diffSelector, arg1)
        -- Strip padding for display text
        local text = self:GetText() or ""
        text = text:gsub("^%s+", "")
        UIDropDownMenu_SetText(diffSelector, text)
        UpdateItemsList()
        CloseDropDownMenus()
    end

    local function IsRaid(sourceName)
        if not sourceName then return false end
        local sources = GetSources()
        for _, cat in ipairs(sources) do
            if cat.label == "Raids" then
                for _, raid in ipairs(cat.options) do
                    if raid == sourceName then return true end
                end
            end
        end
        return false
    end

    local function IsDungeon(sourceName)
        if not sourceName then return false end
        local sources = GetSources()
        for _, cat in ipairs(sources) do
            if cat.label == "Dungeons" then
                for _, dungeon in ipairs(cat.options) do
                    if dungeon == sourceName then return true end
                end
            end
        end
        return false
    end

    local function EnsureItemCacheLoaded()
        if TierLootCache and TierNameCache and TierInstanceLootCache and TierItemLinkCache then
            return
        end
        BuildTierCache(false)
    end

    UIDropDownMenu_Initialize(diffSelector, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.func = OnDiffSelect

        -- Add padding to prevent checkbox overlap
        local padding = "   "

        if IsRaid(f.selectedSource) then
            info.text = padding .. "Mythic"
            info.value = 16
            info.arg1 = 16
            info.checked = (f.selectedDifficulty == 16)
            UIDropDownMenu_AddButton(info)

            info.text = padding .. "Heroic"
            info.value = 15
            info.arg1 = 15
            info.checked = (f.selectedDifficulty == 15)
            UIDropDownMenu_AddButton(info)

            info.text = padding .. "Normal"
            info.value = 14
            info.arg1 = 14
            info.checked = (f.selectedDifficulty == 14)
            UIDropDownMenu_AddButton(info)

            info.text = padding .. "Raid Finder"
            info.value = 17
            info.arg1 = 17
            info.checked = (f.selectedDifficulty == 17)
            UIDropDownMenu_AddButton(info)
        elseif IsDungeon(f.selectedSource) then
            info.text = padding .. "Mythic"
            info.value = 23
            info.arg1 = 23
            info.checked = (f.selectedDifficulty == 23)
            UIDropDownMenu_AddButton(info)

            info.text = padding .. "Heroic"
            info.value = 2
            info.arg1 = 2
            info.checked = (f.selectedDifficulty == 2)
            UIDropDownMenu_AddButton(info)

            info.text = padding .. "Normal"
            info.value = 1
            info.arg1 = 1
            info.checked = (f.selectedDifficulty == 1)
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetSelectedValue(diffSelector, 16) -- Default Mythic
    UIDropDownMenu_SetText(diffSelector, "Mythic")

    -- Usable Only Checkbox
    local usableCheck = CreateFrame("CheckButton", nil, f, "ChatConfigCheckButtonTemplate")
    usableCheck:SetPoint("TOPLEFT", f, "TOPLEFT", 25, -45)
    usableCheck.tooltip = "Show only items usable by your class"
    if E then E:GetModule("Skins"):HandleCheckBox(usableCheck) end
    f.UsableCheck = usableCheck

    local usableLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    usableLabel:SetPoint("LEFT", usableCheck, "RIGHT", 5, 0)
    usableLabel:SetText("Usable Only")

    usableCheck:SetScript("OnClick", function(self)
        f.onlyUsable = self:GetChecked()
        UpdateItemsList()
    end)
    f.onlyUsable = true
    usableCheck:SetChecked(true)

    -- 2. Container for Columns
    local container = CreateFrame("Frame", nil, f)
    container:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -80)
    container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 60)

    -- Left Column (Sources)
    local leftCol = CreateFrame("Frame", nil, container)
    leftCol:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    leftCol:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    leftCol:SetWidth(200)

    local leftScroll = CreateFrame("ScrollFrame", nil, leftCol, "UIPanelScrollFrameTemplate")
    leftScroll:SetPoint("TOPLEFT", 0, 0)
    leftScroll:SetPoint("BOTTOMRIGHT", -30, 0)
    if E then E:GetModule("Skins"):HandleScrollBar(leftScroll.ScrollBar) end

    local leftContent = CreateFrame("Frame", nil, leftScroll)
    leftContent:SetSize(170, 1)
    leftScroll:SetScrollChild(leftContent)
    f.LeftContent = leftContent

    -- Right Column (Items)
    local rightCol = CreateFrame("Frame", nil, container)
    rightCol:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    rightCol:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    rightCol:SetPoint("LEFT", leftCol, "RIGHT", 20, 0)

    local rightScroll = CreateFrame("ScrollFrame", nil, rightCol, "UIPanelScrollFrameTemplate")
    rightScroll:SetPoint("TOPLEFT", 0, 0)
    rightScroll:SetPoint("BOTTOMRIGHT", -30, 0)
    if E then E:GetModule("Skins"):HandleScrollBar(rightScroll.ScrollBar) end

    local rightContent = CreateFrame("Frame", nil, rightScroll)
    rightContent:SetSize(400, 1)
    rightScroll:SetScrollChild(rightContent)
    f.RightContent = rightContent

    -- Custom Item Form
    local customForm = CreateFrame("Frame", nil, rightCol)
    customForm:SetPoint("TOPLEFT", 0, 0)
    customForm:SetPoint("TOPRIGHT", 0, 0)
    customForm:SetHeight(300)
    customForm:Hide()
    f.CustomForm = customForm

    -- Description
    local customDesc = customForm:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    customDesc:SetPoint("TOPLEFT", 10, -10)
    customDesc:SetPoint("TOPRIGHT", -10, -10)
    customDesc:SetJustifyH("LEFT")
    customDesc:SetText(
        "The Best in Slot module tracks items from the current Mythic+ season.\n\nIf you want to track an item from a different source (e.g. World Boss, PvP, Crafting, or Legacy Content), you can add it manually here.")
    customDesc:SetTextColor(0.7, 0.7, 0.7)

    -- Input Label
    local customItemLabel = customForm:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    customItemLabel:SetPoint("TOPLEFT", customDesc, "BOTTOMLEFT", 0, -20)
    customItemLabel:SetText("Item Name, ID, or Link:")

    -- Input Box
    local customItemInput = CreateFrame("EditBox", nil, customForm, "InputBoxTemplate")
    customItemInput:SetSize(350, 25)
    customItemInput:SetPoint("TOPLEFT", customItemLabel, "BOTTOMLEFT", 0, -8)
    customItemInput:SetAutoFocus(false)
    customItemInput:SetTextInsets(5, 5, 0, 0)
    if E then E:GetModule("Skins"):HandleEditBox(customItemInput) end
    f.CustomItemInput = customItemInput

    -- Tip
    local customItemTip = customForm:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    customItemTip:SetPoint("LEFT", customItemInput, "RIGHT", 10, 0)
    customItemTip:SetText("(Press Enter to Search)")
    customItemTip:SetTextColor(0.5, 0.5, 0.5)

    -- Result Preview
    local customItemResultBtn = CreateFrame("Button", nil, customForm)
    customItemResultBtn:SetPoint("TOPLEFT", customItemInput, "BOTTOMLEFT", 0, -15)
    customItemResultBtn:SetSize(350, 30)

    -- Result Icon
    local customItemResultIcon = customItemResultBtn:CreateTexture(nil, "ARTWORK")
    customItemResultIcon:SetSize(24, 24)
    customItemResultIcon:SetPoint("LEFT", 0, 0)
    customItemResultIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    f.CustomItemResultIcon = customItemResultIcon

    local customItemResult = customItemResultBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    customItemResult:SetPoint("LEFT", customItemResultIcon, "RIGHT", 10, 0)
    customItemResult:SetText("")
    f.CustomItemResult = customItemResult

    customItemResultBtn:SetScript("OnEnter", function(self)
        local text = f.CustomItemResult:GetText()
        if f.selectedItemLink and text and text ~= "" and text ~= "Item not found" and text ~= "Searching..." then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(f.selectedItemLink)
            GameTooltip:Show()
        end
    end)
    customItemResultBtn:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
    customItemResultBtn:SetScript("OnClick", function()
        local text = f.CustomItemResult:GetText()
        if f.selectedItemLink and text and text ~= "" and text ~= "Item not found" and text ~= "Searching..." then
            ChatEdit_InsertLink(f.selectedItemLink)
        end
    end)

    customItemInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local text = self:GetText()
        if not text or text == "" then return end

        f.CustomItemResult:SetText("Searching...")
        f.CustomItemResultIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        f.selectedItemLink = nil -- Clear previous selection

        local function SetItem(link)
            f.selectedItemLink = link
            f.CustomItemResult:SetText(link)
            f.Preview:SetText(link)
            f.AddBtn:Enable()

            local icon = GetItemIcon(link)
            if icon then
                f.CustomItemResultIcon:SetTexture(icon)
            end
        end

        local name, link = GetItemInfo(text)
        if link then
            SetItem(link)
        else
            -- Try to load it
            local item = Item:CreateFromItemLink(text)
            if not item:IsItemEmpty() then
                item:ContinueOnItemLoad(function()
                    local _, l = GetItemInfo(item:GetItemID())
                    if l then
                        SetItem(l)
                    else
                        f.CustomItemResult:SetText("Item not found")
                        f.AddBtn:Disable()
                        f.selectedItemLink = nil
                    end
                end)
            else
                -- Try ID
                local id = tonumber(text)
                if id then
                    local item = Item:CreateFromItemID(id)
                    item:ContinueOnItemLoad(function()
                        local _, l = GetItemInfo(id)
                        if l then
                            SetItem(l)
                        else
                            f.CustomItemResult:SetText("Item not found")
                            f.AddBtn:Disable()
                            f.selectedItemLink = nil
                        end
                    end)
                else
                    f.CustomItemResult:SetText("Item not found")
                    f.AddBtn:Disable()
                    f.selectedItemLink = nil
                end
            end
        end
    end)

    local customSourceLabel = customForm:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    customSourceLabel:SetPoint("TOPLEFT", customItemResultBtn, "BOTTOMLEFT", 0, -20)
    customSourceLabel:SetText("Source:")

    local customSourceDropdown = CreateFrame("Frame", "TwichUI_BiS_CustomSourceDropdown", f, "UIDropDownMenuTemplate")
    customSourceDropdown:SetPoint("TOPLEFT", customSourceLabel, "BOTTOMLEFT", -15, -5)
    customSourceDropdown:SetFrameLevel(f:GetFrameLevel() + 100) -- Boost frame level significantly
    UIDropDownMenu_SetWidth(customSourceDropdown, 200)
    UIDropDownMenu_SetText(customSourceDropdown, "Select Source")
    UIDropDownMenu_JustifyText(customSourceDropdown, "LEFT")
    if E then E:GetModule("Skins"):HandleDropDownBox(customSourceDropdown) end
    f.CustomSourceDropdown = customSourceDropdown

    -- Create a full-size invisible button to ensure the entire area is clickable
    local fullClick = CreateFrame("Button", nil, customSourceDropdown)
    fullClick:SetAllPoints(customSourceDropdown)
    fullClick:SetFrameLevel(customSourceDropdown:GetFrameLevel() + 10)

    fullClick:SetScript("OnEnter", function(self)
        local b = _G[customSourceDropdown:GetName() .. "Button"]
        if b then
            if b.LockHighlight then b:LockHighlight() end
            -- ElvUI support
            if b.SetBackdropBorderColor and E then
                b:SetBackdropBorderColor(unpack(E.media.rgbvaluecolor))
            end
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Click to select source", 1, 1, 1)
        GameTooltip:Show()
    end)

    fullClick:SetScript("OnLeave", function(self)
        local b = _G[customSourceDropdown:GetName() .. "Button"]
        if b then
            if b.UnlockHighlight then b:UnlockHighlight() end
            -- ElvUI support
            if b.SetBackdropBorderColor and E then
                b:SetBackdropBorderColor(unpack(E.media.bordercolor))
            end
        end
        GameTooltip:Hide()
    end)

    fullClick:SetScript("OnClick", function()
        ToggleDropDownMenu(nil, nil, customSourceDropdown)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    local function OnCustomSourceSelect(self, arg1)
        f.customSourceValue = arg1
        UIDropDownMenu_SetSelectedValue(customSourceDropdown, arg1)
        UIDropDownMenu_SetText(customSourceDropdown, arg1)
    end

    UIDropDownMenu_Initialize(customSourceDropdown, function(self, level)
        level = level or 1
        local info

        -- Dungeons
        info = UIDropDownMenu_CreateInfo()
        info.text = "Dungeons"
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

        local sources = GetSources()
        if sources then
            -- Find Dungeons category
            for _, cat in ipairs(sources) do
                if cat.label == "Dungeons" then
                    for _, dungeon in ipairs(cat.options) do
                        info = UIDropDownMenu_CreateInfo()
                        info.func = OnCustomSourceSelect
                        info.text = "   " .. dungeon
                        info.value = dungeon
                        info.arg1 = dungeon
                        info.checked = (f.customSourceValue == dungeon)
                        UIDropDownMenu_AddButton(info, level)
                    end
                end
            end

            -- Raids
            info = UIDropDownMenu_CreateInfo()
            info.text = "Raids"
            info.isTitle = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)

            for _, cat in ipairs(sources) do
                if cat.label == "Raids" then
                    for _, raid in ipairs(cat.options) do
                        info = UIDropDownMenu_CreateInfo()
                        info.func = OnCustomSourceSelect
                        info.text = "   " .. raid
                        info.value = raid
                        info.arg1 = raid
                        info.checked = (f.customSourceValue == raid)
                        UIDropDownMenu_AddButton(info, level)
                    end
                end
            end
        end

        -- Additional sources for custom items
        info = UIDropDownMenu_CreateInfo()
        info.text = "Other"
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

        local extra = { "Crafted", "World Boss", "Other" }
        for _, opt in ipairs(extra) do
            info = UIDropDownMenu_CreateInfo()
            info.func = OnCustomSourceSelect
            info.text = "   " .. opt
            info.value = opt
            info.arg1 = opt
            info.checked = (f.customSourceValue == opt)
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- 3. Selected Item Info & Add Button
    local bottomPanel = CreateFrame("Frame", nil, f)
    bottomPanel:SetPoint("TOPLEFT", container, "BOTTOMLEFT", 0, -10)
    bottomPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 10)

    local previewFrame = CreateFrame("Button", nil, bottomPanel)
    previewFrame:SetPoint("TOPLEFT", 0, 0)
    previewFrame:SetSize(300, 25)

    local previewLabel = previewFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewLabel:SetPoint("TOPLEFT", 0, 0)
    previewLabel:SetText("Selected Item:")

    local preview = previewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    preview:SetPoint("TOPLEFT", previewLabel, "BOTTOMLEFT", 0, -2)
    preview:SetText("No item selected")
    f.Preview = preview

    previewFrame:SetScript("OnEnter", function(self)
        if f.selectedItemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(f.selectedItemLink)
            GameTooltip:Show()
        end
    end)
    previewFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local addBtn = CreateFrame("Button", nil, bottomPanel, "UIPanelButtonTemplate")
    addBtn:SetSize(120, 25)
    addBtn:SetPoint("RIGHT", 0, 0)
    addBtn:SetText("Select Item")
    if E then E:GetModule("Skins"):HandleButton(addBtn) end
    addBtn:Disable()
    f.AddBtn = addBtn

    local function IsRaid(sourceName)
        if not sourceName then return false end
        local sources = GetSources()
        for _, cat in ipairs(sources) do
            if cat.label == "Raids" then
                for _, raid in ipairs(cat.options) do
                    if raid == sourceName then return true end
                end
            end
        end
        return false
    end

    local function IsDungeon(sourceName)
        if not sourceName then return false end
        local sources = GetSources()
        for _, cat in ipairs(sources) do
            if cat.label == "Dungeons" then
                for _, dungeon in ipairs(cat.options) do
                    if dungeon == sourceName then return true end
                end
            end
        end
        return false
    end

    local DIFF_INFO = {
        [16] = { label = "Mythic", color = { 0.64, 0.21, 0.93 } }, -- Purple
        [15] = { label = "Heroic", color = { 0, 0.7, 1 } },        -- Blue
        [14] = { label = "Normal", color = { 0.2, 1, 0.2 } },      -- Green
        [17] = { label = "Raid Finder", color = { 1, 0.82, 0 } },  -- Gold
        [23] = { label = "Mythic", color = { 0.64, 0.21, 0.93 } }, -- Purple
        [2]  = { label = "Heroic", color = { 0, 0.7, 1 } },        -- Blue
        [1]  = { label = "Normal", color = { 0.2, 1, 0.2 } },      -- Green
    }

    local function UpdateSourceStates()
        EnsureItemCacheLoaded()
        local searchText = input:GetText():lower()
        if searchText == "search item..." then searchText = "" end

        for _, btn in ipairs(f.sourceButtons) do
            local sourceName = btn.Text:GetText()
            local hasItems = false

            if sourceName == "All Items" or sourceName == "Custom Item" then
                hasItems = true
            elseif TierInstanceLootCache and TierInstanceLootCache[sourceName] then
                for _, itemID in ipairs(TierInstanceLootCache[sourceName]) do
                    local _, _, _, itemEquipLoc, _, itemClassID, itemSubClassID = GetItemInfoInstant(itemID)

                    -- If item info is missing, assume it might be valid to avoid false negatives
                    if not itemEquipLoc then
                        hasItems = true
                        break
                    end

                    if itemEquipLoc then
                        local valid = IsItemValidForSlot(itemEquipLoc, f.targetSlotID)
                        if valid then
                            local usable = true
                            if f.onlyUsable then
                                usable = IsItemUsableByPlayer(itemClassID, itemSubClassID, itemEquipLoc)
                            end

                            if usable then
                                if searchText == "" then
                                    hasItems = true
                                    break
                                else
                                    local name = GetItemInfo(itemID)
                                    if name and name:lower():find(searchText, 1, true) then
                                        hasItems = true
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end

            if hasItems then
                btn:Enable()
                btn.Text:SetTextColor(1, 1, 1)
                if sourceName == "Custom Item" then btn.Text:SetTextColor(0, 1, 1) end
            else
                btn:Disable()
                btn.Text:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    end

    UpdateItemsList = function()
        EnsureItemCacheLoaded()
        UpdateSourceStates()

        if f.refreshTimer then
            f.refreshTimer:Cancel()
            f.refreshTimer = nil
        end

        -- Show/Hide Difficulty Selector
        if IsRaid(f.selectedSource) or IsDungeon(f.selectedSource) then
            f.DiffSelector:Show()
            -- Reset difficulty if invalid for current type
            if IsDungeon(f.selectedSource) and (f.selectedDifficulty == 16 or f.selectedDifficulty == 15 or f.selectedDifficulty == 14 or f.selectedDifficulty == 17) then
                f.selectedDifficulty = 23 -- Default to Mythic Dungeon
                UIDropDownMenu_SetSelectedValue(f.DiffSelector, 23)
                UIDropDownMenu_SetText(f.DiffSelector, "Mythic")
            elseif IsRaid(f.selectedSource) and (f.selectedDifficulty == 23 or f.selectedDifficulty == 2 or f.selectedDifficulty == 1) then
                f.selectedDifficulty = 16 -- Default to Mythic Raid
                UIDropDownMenu_SetSelectedValue(f.DiffSelector, 16)
                UIDropDownMenu_SetText(f.DiffSelector, "Mythic")
            end
        else
            f.DiffSelector:Hide()
        end

        -- Clear previous items
        for _, btn in ipairs(f.itemButtons) do
            btn:Hide()
            btn:SetParent(nil)
        end
        f.itemButtons = {}

        local items = {}
        local searchText = input:GetText():lower()
        if searchText == "search item..." then searchText = "" end

        -- Handle Custom Item View
        if f.selectedSource == "Custom Item" then
            customForm:Show()
            f.CustomSourceDropdown:Show()
            f.Input:Hide()

            local sourceText = f.customSourceValue or "Other"
            if type(UIDropDownMenu_SetSelectedValue) == "function" then
                UIDropDownMenu_SetSelectedValue(f.CustomSourceDropdown, sourceText)
            end
            if type(UIDropDownMenu_SetText) == "function" then
                UIDropDownMenu_SetText(f.CustomSourceDropdown, sourceText)
            end

            rightScroll:Hide() -- Hide scroll frame as requested

            preview:SetText("Enter item details above")
            addBtn:Disable()

            -- Populate saved items
            local customItems = GetCustomItemsDB()
            if type(customItems) == "table" then
                for _, item in ipairs(customItems) do
                    local name, link, _, _, _, _, _, _, itemEquipLoc, icon = GetItemInfo(item.link)
                    if link then
                        local valid = IsItemValidForSlot(itemEquipLoc, f.targetSlotID)
                        if valid then
                            table.insert(items, { id = 0, name = name, link = link, icon = icon })
                        end
                    else
                        -- Try to load for next time
                        local itemObj = Item:CreateFromItemLink(item.link)
                        if not itemObj:IsItemEmpty() then
                            itemObj:ContinueOnItemLoad(function() end)
                        end
                    end
                end
            end
        else
            rightScroll:ClearAllPoints()
            rightScroll:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
            rightScroll:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", -30, 0)
            rightScroll:Show()

            customForm:Hide()
            f.CustomSourceDropdown:Hide()
            f.Input:Show()
        end

        -- Debug Log
        if f.selectedSource then
            local count = (TierInstanceLootCache and TierInstanceLootCache[f.selectedSource]) and
                #TierInstanceLootCache[f.selectedSource] or 0
        end

        -- If source selected, get items from cache
        if f.selectedSource == "All Items" then
            if TierLootCache then
                local missingItems = false
                for itemID, source in pairs(TierLootCache) do
                    local versions = {}

                    -- Prefer difficulty versions based on whether the source is a dungeon or raid.
                    local instanceName = (type(source) == "string" and source:match("^(.-) %(")) or nil
                    local preferDungeon = instanceName and IsDungeon(instanceName)
                    local preferRaid = instanceName and IsRaid(instanceName)

                    if TierItemLinkCache and TierItemLinkCache[itemID] and type(TierItemLinkCache[itemID]) == "table" then
                        local function AddDiffs(diffIds)
                            for _, diffID in ipairs(diffIds) do
                                if TierItemLinkCache[itemID][diffID] then
                                    table.insert(versions, { link = TierItemLinkCache[itemID][diffID], diffID = diffID })
                                end
                            end
                        end

                        if preferDungeon then
                            AddDiffs({ 23, 2, 1 })
                        elseif preferRaid then
                            AddDiffs({ 16, 15, 14, 17 })
                        else
                            -- Unknown: try raid first, then dungeon.
                            AddDiffs({ 16, 15, 14, 17 })
                            if #versions == 0 then
                                AddDiffs({ 23, 2, 1 })
                            end
                        end

                        if #versions == 0 then
                            -- Fallback to whatever is there
                            for diffID, link in pairs(TierItemLinkCache[itemID]) do
                                table.insert(versions, { link = link, diffID = diffID })
                                break
                            end
                        end
                    else
                        local l = (TierItemLinkCache and TierItemLinkCache[itemID]) or itemID
                        table.insert(versions, { link = l, diffID = nil })
                    end

                    for _, v in ipairs(versions) do
                        local linkToUse = v.link
                        local name, link, _, _, _, _, _, _, itemEquipLoc, icon, _, itemClassID, itemSubClassID =
                            GetItemInfo(linkToUse)
                        if not name then
                            missingItems = true
                            if type(linkToUse) == "string" then
                                Item:CreateFromItemLink(linkToUse)
                            else
                                Item:CreateFromItemID(linkToUse)
                            end
                        else
                            local valid = IsItemValidForSlot(itemEquipLoc, f.targetSlotID)
                            if valid then
                                local usable = true
                                if f.onlyUsable then
                                    usable = IsItemUsableByPlayer(itemClassID, itemSubClassID, itemEquipLoc)
                                end

                                if usable then
                                    if searchText == "" or name:lower():find(searchText, 1, true) then
                                        table.insert(items,
                                            {
                                                id = itemID,
                                                name = name,
                                                link = link,
                                                icon = icon,
                                                diffID = v.diffID,
                                                source =
                                                    source
                                            })
                                    end
                                end
                            end
                        end
                    end
                    -- Limit results to prevent lag
                    if #items >= 300 then break end
                end

                if missingItems and not f.refreshTimer then
                    f.refreshTimer = C_Timer.NewTimer(1.0, function()
                        f.refreshTimer = nil
                        if f.selectedSource == "All Items" and f:IsVisible() then
                            UpdateItemsList()
                        end
                    end)
                end
            end
        elseif f.selectedSource and TierInstanceLootCache and TierInstanceLootCache[f.selectedSource] then
            local sourceItems = TierInstanceLootCache[f.selectedSource]
            for _, itemID in ipairs(sourceItems) do
                -- Filter by slot
                local linkToUse = itemID
                if TierItemLinkCache and TierItemLinkCache[itemID] then
                    if type(TierItemLinkCache[itemID]) == "table" then
                        -- Use selected difficulty if available, otherwise fallback to a sensible order.
                        if IsDungeon(f.selectedSource) then
                            linkToUse = TierItemLinkCache[itemID][f.selectedDifficulty] or
                                TierItemLinkCache[itemID][23] or -- Mythic Dungeon
                                TierItemLinkCache[itemID][2] or  -- Heroic Dungeon
                                TierItemLinkCache[itemID][1] or  -- Normal Dungeon
                                TierItemLinkCache[itemID][16] or -- Mythic Raid
                                TierItemLinkCache[itemID][15] or -- Heroic Raid
                                TierItemLinkCache[itemID][14] or -- Normal Raid
                                TierItemLinkCache[itemID][17] or -- LFR
                                itemID
                        else
                            linkToUse = TierItemLinkCache[itemID][f.selectedDifficulty] or
                                TierItemLinkCache[itemID][16] or -- Mythic Raid
                                TierItemLinkCache[itemID][15] or -- Heroic Raid
                                TierItemLinkCache[itemID][14] or -- Normal Raid
                                TierItemLinkCache[itemID][17] or -- LFR
                                TierItemLinkCache[itemID][23] or -- Mythic Dungeon
                                TierItemLinkCache[itemID][2] or  -- Heroic Dungeon
                                TierItemLinkCache[itemID][1] or  -- Normal Dungeon
                                itemID
                        end
                    else
                        linkToUse = TierItemLinkCache[itemID]
                    end
                end

                local name, link, _, _, _, _, _, _, itemEquipLoc, icon, _, itemClassID, itemSubClassID = GetItemInfo(
                    linkToUse)
                if not name then
                    -- Request info
                    local item = (type(linkToUse) == "string") and Item:CreateFromItemLink(linkToUse) or
                        Item:CreateFromItemID(linkToUse)
                    item:ContinueOnItemLoad(function()
                        -- Refresh if still on same source
                        if f.selectedSource and TierInstanceLootCache[f.selectedSource] then
                            UpdateItemsList()
                        end
                    end)
                else
                    local valid = IsItemValidForSlot(itemEquipLoc, f.targetSlotID)
                    if valid then
                        local usable = true
                        if f.onlyUsable then
                            usable = IsItemUsableByPlayer(itemClassID, itemSubClassID, itemEquipLoc)
                        end

                        if usable then
                            -- Filter by search
                            if searchText == "" or name:lower():find(searchText, 1, true) then
                                table.insert(items, { id = itemID, name = name, link = link, icon = icon })
                            end
                        end
                    end
                end
            end
        end

        -- Sort items by name
        table.sort(items, function(a, b) return a.name < b.name end)

        -- Render items
        local width = rightScroll:GetWidth()
        if width < 100 then width = 450 end -- Fallback
        rightContent:SetWidth(width)

        local yOffset = 0
        for _, item in ipairs(items) do
            local btn = CreateFrame("Button", nil, rightContent)
            btn:SetHeight(30)
            btn:SetPoint("TOPLEFT", 0, -yOffset)
            btn:SetPoint("RIGHT", 0, 0)

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetSize(24, 24)
            icon:SetPoint("LEFT", 5, 0)
            icon:SetTexture(item.icon)

            local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            text:SetPoint("LEFT", icon, "RIGHT", 10, 0)
            text:SetText(item.link)

            local diffLabel
            if item.diffID and DIFF_INFO[item.diffID] then
                local dInfo = DIFF_INFO[item.diffID]
                diffLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                diffLabel:SetText(dInfo.label)
                diffLabel:SetTextColor(unpack(dInfo.color))
            end

            local sourceLabel
            if item.source then
                sourceLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                sourceLabel:SetTextColor(0.6, 0.6, 0.6)

                -- Extract instance name only to save space
                local instanceName = item.source:match("^(.-)%s*%(") or item.source
                sourceLabel:SetText(instanceName)
            end

            if diffLabel and sourceLabel then
                diffLabel:SetPoint("BOTTOMRIGHT", btn, "RIGHT", -10, 1)
                sourceLabel:SetPoint("TOPRIGHT", btn, "RIGHT", -10, -1)
            elseif diffLabel then
                diffLabel:SetPoint("RIGHT", -10, 0)
            elseif sourceLabel then
                sourceLabel:SetPoint("RIGHT", -10, 0)
            end

            -- Background
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if yOffset % 60 == 0 then -- Alternating every 30px row
                bg:SetColorTexture(0.1, 0.1, 0.1, 0.2)
            else
                bg:SetColorTexture(0.15, 0.15, 0.15, 0.2)
            end

            -- Highlight
            local hl = btn:CreateTexture(nil, "BACKGROUND", nil, 1) -- Layer 1 to be above bg
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.1)
            hl:Hide()
            btn.Highlight = hl

            btn:SetScript("OnEnter", function(self)
                hl:Show()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(item.link)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                if f.selectedItemLink ~= item.link then hl:Hide() end
                GameTooltip:Hide()
            end)
            btn:SetScript("OnClick", function()
                f.selectedItemLink = item.link
                preview:SetText(item.link)
                addBtn:Enable()
                -- Update highlights
                for _, b in ipairs(f.itemButtons) do b.Highlight:Hide() end
                hl:Show()
            end)
            -- Double click to add
            btn:SetScript("OnDoubleClick", function()
                f.selectedItemLink = item.link
                addBtn:Click()
            end)

            table.insert(f.itemButtons, btn)
            yOffset = yOffset + 30
        end
        rightContent:SetHeight(yOffset)
    end

    input:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text and text ~= "" and text ~= "Search Item..." and f.selectedSource ~= "All Items" and f.selectedSource ~= "Custom Item" then
            f.selectedSource = "All Items"
            -- Update source buttons highlighting
            for _, btn in ipairs(f.sourceButtons) do
                btn.Highlight:Hide()
                if btn.Text:GetText() == "All Items" then
                    btn.Highlight:Show()
                end
            end
        end
        UpdateItemsList()
    end)
    input:SetScript("OnEditFocusGained", function(self)
        if self:GetText() == "Search Item..." then self:SetText("") end
    end)
    input:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then self:SetText("Search Item...") end
    end)
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    addBtn:SetScript("OnClick", function()
        if f.selectedSource == "Custom Item" then
            local itemLink = f.selectedItemLink
            local sourceText = f.customSourceValue

            if itemLink then
                -- Save to profile-scoped DB
                local customItems = GetCustomItemsDB()
                if type(customItems) == "table" then
                    local found = false
                    for _, item in ipairs(customItems) do
                        if item.link == itemLink then
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(customItems, { link = itemLink, source = sourceText or "Custom" })
                    end
                end

                if f.callback then
                    f.callback({ link = itemLink, source = (sourceText or "Custom") })
                    f:HideAnimated()
                end
            end
        elseif f.selectedItemLink and f.callback then
            f.callback({ link = f.selectedItemLink, source = f.selectedSource })
            f:HideAnimated()
        end
    end)

    -- Populate Sources (Left Column)
    local yOffset = 0

    -- Ensure caches are loaded before building the source list so "Tier Sets" can appear.
    BuildTierCache(false)
    local sources = GetSources()

    for _, category in ipairs(sources) do
        local catHeader = leftContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        catHeader:SetPoint("TOPLEFT", 10, -yOffset)
        catHeader:SetText(category.label)
        yOffset = yOffset + 20

        for _, src in ipairs(category.options) do
            local btn = CreateFrame("Button", nil, leftContent)
            btn:SetSize(170, 20)
            btn:SetPoint("TOPLEFT", 10, -yOffset)

            local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("LEFT", 5, 0)
            text:SetText(src)
            btn.Text = text

            if src == "Custom Item" then
                text:SetTextColor(0, 1, 1) -- Cyan
            end

            local hl = btn:CreateTexture(nil, "BACKGROUND")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.1)
            hl:Hide()
            btn.Highlight = hl

            btn:SetScript("OnEnter", function()
                if f.selectedSource ~= src then
                    hl:Show()
                    hl:SetColorTexture(1, 1, 1, 0.05) -- Faint hover
                end
            end)

            btn:SetScript("OnLeave", function()
                if f.selectedSource ~= src then
                    hl:Hide()
                else
                    hl:Show()
                    hl:SetColorTexture(1, 1, 1, 0.1) -- Selected state
                end
            end)

            btn:SetScript("OnClick", function()
                for _, b in ipairs(f.sourceButtons) do
                    b.Highlight:Hide()
                    -- Reset color for others just in case
                    b.Highlight:SetColorTexture(1, 1, 1, 0.1)
                end
                hl:Show()
                hl:SetColorTexture(1, 1, 1, 0.1)
                f.selectedSource = src
                UpdateItemsList()
            end)

            table.insert(f.sourceButtons, btn)
            yOffset = yOffset + 20
        end
        yOffset = yOffset + 10
    end
    leftContent:SetHeight(yOffset)

    function f:SetInitialState(link, source, iLevel, slotID)
        self.Input:SetText("Search Item...")
        self.selectedSource = source or "All Items"
        self.targetSlotID = slotID
        self.selectedItemLink = link

        -- Select Source in UI
        for _, btn in ipairs(self.sourceButtons) do
            btn.Highlight:Hide()
            if btn.Text:GetText() == self.selectedSource then
                btn.Highlight:Show()
            end
        end

        -- Ensure cache is built
        BuildTierCache(false)

        UpdateItemsList()

        if link then
            preview:SetText(link)
            addBtn:Enable()
        else
            preview:SetText("No item selected")
            addBtn:Disable()
        end
    end

    f:Hide()
    return f
end

local function GetOwnedStatus(bisItemID, targetSlotID)
    if not bisItemID then return false, false, nil, nil end

    -- Check equipped
    for i = 1, 19 do
        local itemID = GetInventoryItemID("player", i)
        if itemID == bisItemID then
            local link = GetInventoryItemLink("player", i)
            local effectiveILvl = GetDetailedItemLevelInfo(link)
            return true, true, effectiveILvl, link
        end
    end

    -- Check bags
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID == bisItemID then
                local link = C_Container.GetContainerItemLink(bag, slot)
                local effectiveILvl = GetDetailedItemLevelInfo(link)
                return true, false, effectiveILvl, link
            end
        end
    end

    return false, false, nil, nil
end

local function TryLoadTierCacheOnly()
    if TierLootCache and TierNameCache and TierInstanceLootCache and TierItemLinkCache then
        return true
    end
    if not MythicPlusModule.Database or not MythicPlusModule.Database.GetGameVersion or not MythicPlusModule.Database.GetItemCache then
        return false
    end

    local currentVersion = select(1, GetBuildInfo())
    local storedVersion = MythicPlusModule.Database:GetGameVersion()
    local storedCache = MythicPlusModule.Database:GetItemCache()
    if storedCache and storedVersion == currentVersion then
        TierLootCache = storedCache.Loot or {}
        TierNameCache = storedCache.Name or {}
        TierInstanceLootCache = storedCache.InstanceLoot or {}
        TierItemLinkCache = storedCache.ItemLink or {}
        return true
    end

    return false
end

local function NormalizeInstanceName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if MEGA_DUNGEON_MAPPINGS[name] then
        return MEGA_DUNGEON_MAPPINGS[name]
    end
    return name
end

local function GetItemIDFromLink(link)
    if not link then return nil end

    if type(link) == "number" then
        return link
    end

    if C_Item and C_Item.GetItemInfoInstant then
        return select(1, C_Item.GetItemInfoInstant(link))
    end

    if GetItemInfoInstant then
        return select(1, GetItemInfoInstant(link))
    end

    return nil
end

local function GetItemLinkForChat(itemID, fallbackLink)
    if type(fallbackLink) == "string" and fallbackLink:find("|Hitem:") then
        return fallbackLink
    end

    if itemID then
        local link = select(2, GetItemInfo(itemID))
        if link then return link end
        return "|Hitem:" .. tostring(itemID) .. "|h[item:" .. tostring(itemID) .. "]|h"
    end

    return tostring(fallbackLink or "")
end

--- Prints missing BiS items for the current dungeon/raid (if it can be matched to cache data).
function BestInSlot:PrintMissingBiSForCurrentInstance()
    local inInstance, instanceType = IsInInstance()
    if not inInstance then return end
    if instanceType ~= "party" and instanceType ~= "raid" then return end

    local instanceName = NormalizeInstanceName(select(1, GetInstanceInfo()))
    if not instanceName then return end

    local missing = self:GetMissingBiSForInstance(instanceName)
    if not missing then
        -- Cache not ready; message already logged by collector.
        return
    end

    if #missing == 0 then
        return
    end

    Logger.Info(string.format("BiS: Missing %d item(s) for %s:", #missing, instanceName))
    for _, entry in ipairs(missing) do
        if entry.boss then
            Logger.Info(string.format("  - %s (%s)", entry.link, entry.boss))
        else
            Logger.Info(string.format("  - %s", entry.link))
        end
    end
end

--- Returns a list of missing BiS items for a specific instance name.
--- Uses cache-only loading to stay fast on zone-in.
---@param instanceName string
---@return table|nil missing Returns nil if cache not ready or DB not available.
function BestInSlot:GetMissingBiSForInstance(instanceName)
    instanceName = NormalizeInstanceName(instanceName)
    if not instanceName then return nil end

    -- Try to load the item-source cache without forcing a rebuild on zone-in.
    if not TryLoadTierCacheOnly() then
        Logger.Info("BiS: Item cache not ready (open BiS Gear once to build/refresh).")
        return nil
    end

    -- If the instance has no loot table in our cache, don't show entry notifications.
    -- (This is distinct from "no missing BiS" for a dungeon that DOES have loot.)
    local instanceLoot = TierInstanceLootCache and TierInstanceLootCache[instanceName]
    if type(instanceLoot) ~= "table" or next(instanceLoot) == nil then
        return nil
    end

    local db = GetCharacterDB()
    if not db then return nil end

    local missing = {}

    for _, slotData in ipairs(SLOTS) do
        local slotID = slotData.slotID
        local data = db[slotID]
        if data then
            local selectedLink = (type(data) == "table") and data.link or data
            local manualSource = (type(data) == "table") and data.source or nil
            local itemID = GetItemIDFromLink(selectedLink)
            if itemID then
                local owned = select(1, GetOwnedStatus(itemID, slotID))
                if not owned then
                    local sourceText = nil
                    if type(manualSource) == "string" and manualSource ~= "All Items" and manualSource ~= "Custom Item" and manualSource ~= "Custom" then
                        sourceText = manualSource
                    end

                    local ejSource = TierLootCache and TierLootCache[itemID] or nil
                    if ejSource then
                        sourceText = ejSource
                    end

                    local itemInstance = nil
                    if type(sourceText) == "string" then
                        itemInstance = sourceText:match("^(.-) %(") or sourceText
                        itemInstance = NormalizeInstanceName(itemInstance)
                    end

                    if itemInstance == instanceName then
                        local boss = nil
                        if type(ejSource) == "string" then
                            boss = ejSource:match("^.- %((.-)%)$")
                        end
                        table.insert(missing, {
                            slotID = slotID,
                            itemID = itemID,
                            link = GetItemLinkForChat(itemID, selectedLink),
                            boss = boss
                        })
                    end
                end
            end
        end
    end

    return missing
end

local function GetEntryDisplaySetting(key, default)
    if CM and CM.GetProfileSettingSafe then
        return CM:GetProfileSettingSafe("mythicplus.bestInSlot.entryDisplay." .. tostring(key), default)
    end
    return default
end

local function GetEntryDisplayColor(key, default)
    local c = GetEntryDisplaySetting(key, default)
    if type(c) ~= "table" then
        return default
    end
    return {
        r = tonumber(c.r) or tonumber(default.r) or 1,
        g = tonumber(c.g) or tonumber(default.g) or 1,
        b = tonumber(c.b) or tonumber(default.b) or 1,
        a = tonumber(c.a) or tonumber(default.a) or 1,
    }
end

local function FetchStatusbarTexture(key, default)
    local textureKey = GetEntryDisplaySetting(key, default)
    if LSM and type(LSM.Fetch) == "function" then
        local path = LSM:Fetch("statusbar", textureKey)
        if path and path ~= "" then
            return path
        end
    end
    return textureKey
end

local function FetchBorderTexture(key, default)
    local textureKey = GetEntryDisplaySetting(key, default)
    if LSM and type(LSM.Fetch) == "function" then
        local path = LSM:Fetch("border", textureKey)
        if path and path ~= "" then
            return path
        end
    end
    return textureKey
end

local function ApplyFont(fs, fontKeySetting, sizeSetting, outlineSetting, defaultFont, defaultSize)
    if not fs or type(fs.SetFont) ~= "function" then return end

    local fontKey = GetEntryDisplaySetting(fontKeySetting, defaultFont)
    local fontPath = fontKey
    if LSM and type(LSM.Fetch) == "function" then
        fontPath = LSM:Fetch("font", fontKey) or fontKey
    end

    local size = tonumber(GetEntryDisplaySetting(sizeSetting, defaultSize)) or defaultSize
    local outline = tostring(GetEntryDisplaySetting(outlineSetting, "NONE") or "NONE")
    if outline == "NONE" then outline = "" end
    fs:SetFont(fontPath, size, outline)
end

local function ApplyEntryDisplayRowLayout(row)
    if not row then return end

    local width = tonumber(GetEntryDisplaySetting("frameWidth", 420)) or 420
    local height = tonumber(GetEntryDisplaySetting("frameHeight", 50)) or 50
    row:SetSize(width, height)

    local padLeft = tonumber(GetEntryDisplaySetting("padLeft", 10)) or 10
    local padRight = tonumber(GetEntryDisplaySetting("padRight", 10)) or 10
    local iconSize = tonumber(GetEntryDisplaySetting("iconSize", 30)) or 30
    local iconGap = tonumber(GetEntryDisplaySetting("iconGap", 10)) or 10
    -- Center the two-line text block within the row by default.
    local itemFontSize = tonumber(GetEntryDisplaySetting("itemFontSize", 12)) or 12
    local detailFontSize = tonumber(GetEntryDisplaySetting("detailFontSize", 11)) or 11
    local defaultItemTextYOffset = math.floor(detailFontSize / 2) + 1
    local defaultDetailTextYOffset = -(math.floor(itemFontSize / 2) + 1)

    local itemTextYOffset = tonumber(GetEntryDisplaySetting("itemTextYOffset", defaultItemTextYOffset))
        or defaultItemTextYOffset
    local detailTextYOffset = tonumber(GetEntryDisplaySetting("detailTextYOffset", defaultDetailTextYOffset))
        or defaultDetailTextYOffset

    local showIcon = iconSize > 0

    if row.icon then
        row.icon:ClearAllPoints()
        row.icon:SetSize(iconSize, iconSize)
        row.icon:SetPoint("LEFT", row, "LEFT", padLeft, 0)
        if showIcon then
            -- Actual icon visibility is driven by whether we set a texture later.
            row.icon:Show()
        else
            row.icon:Hide()
        end
    end

    local textLeftAnchor = row
    local textLeftPoint = "LEFT"
    local textLeftX = padLeft
    if showIcon and row.icon then
        textLeftAnchor = row.icon
        textLeftPoint = "RIGHT"
        textLeftX = iconGap
    end

    if row.itemText then
        row.itemText:SetJustifyH("LEFT")
        row.itemText:ClearAllPoints()
        row.itemText:SetPoint("LEFT", textLeftAnchor, textLeftPoint, textLeftX, itemTextYOffset)
        row.itemText:SetPoint("RIGHT", row, "RIGHT", -padRight, 0)
    end

    if row.detailText then
        row.detailText:SetJustifyH("LEFT")
        row.detailText:ClearAllPoints()
        row.detailText:SetPoint("LEFT", textLeftAnchor, textLeftPoint, textLeftX, detailTextYOffset)
        row.detailText:SetPoint("RIGHT", row, "RIGHT", -padRight, 0)
    end
end

local function EnsureEntryDisplayRowTextures(row)
    if not row then return end

    if not row.bg then
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
    end

    if not row.borderTop then
        row.borderTop = row:CreateTexture(nil, "BORDER")
        row.borderBottom = row:CreateTexture(nil, "BORDER")
        row.borderLeft = row:CreateTexture(nil, "BORDER")
        row.borderRight = row:CreateTexture(nil, "BORDER")
    end
end

local function ApplyEntryDisplayRowAppearance(row)
    if not row then return end
    EnsureEntryDisplayRowTextures(row)

    local texture = FetchStatusbarTexture("backgroundTexture", "ElvUI Norm")
    if row.bg and type(row.bg.SetTexture) == "function" then
        row.bg:SetTexture(texture)
    end

    -- Darker, more ElvUI-like default.
    local bg = GetEntryDisplayColor("backgroundColor", { r = 0.07, g = 0.07, b = 0.07, a = 0.80 })
    if row.bg and type(row.bg.SetVertexColor) == "function" then
        row.bg:SetVertexColor(bg.r, bg.g, bg.b, bg.a)
    end

    local borderSize = tonumber(GetEntryDisplaySetting("borderSize", 1)) or 1
    if borderSize < 0 then borderSize = 0 end

    -- ElvUI-like border default (near-black).
    local bc = GetEntryDisplayColor("borderColor", { r = 0, g = 0, b = 0, a = 0.9 })

    local defaultBorderTexture = "Interface\\Buttons\\WHITE8X8"
    local borderTexture = FetchBorderTexture("borderTexture", defaultBorderTexture)

    local function applyBorder(tex)
        if not tex then return end
        tex:SetTexture(borderTexture)
        tex:SetVertexColor(bc.r, bc.g, bc.b, bc.a)
        tex:Show()
    end

    if borderSize == 0 then
        if row.borderTop then row.borderTop:Hide() end
        if row.borderBottom then row.borderBottom:Hide() end
        if row.borderLeft then row.borderLeft:Hide() end
        if row.borderRight then row.borderRight:Hide() end
        return
    end

    applyBorder(row.borderTop)
    applyBorder(row.borderBottom)
    applyBorder(row.borderLeft)
    applyBorder(row.borderRight)

    row.borderTop:ClearAllPoints()
    row.borderTop:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.borderTop:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row.borderTop:SetHeight(borderSize)

    row.borderBottom:ClearAllPoints()
    row.borderBottom:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.borderBottom:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.borderBottom:SetHeight(borderSize)

    row.borderLeft:ClearAllPoints()
    row.borderLeft:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.borderLeft:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.borderLeft:SetWidth(borderSize)

    row.borderRight:ClearAllPoints()
    row.borderRight:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row.borderRight:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.borderRight:SetWidth(borderSize)
end

local function ApplyEntryDisplayRowFonts(row)
    if not row then return end

    ApplyFont(row.itemText, "itemFont", "itemFontSize", "itemFontOutline", "Expressway", 12)
    ApplyFont(row.detailText, "detailFont", "detailFontSize", "detailFontOutline", "Expressway", 11)

    local ic = GetEntryDisplayColor("itemFontColor", { r = 1, g = 1, b = 1, a = 1 })
    if row.itemText and type(row.itemText.SetTextColor) == "function" then
        row.itemText:SetTextColor(ic.r, ic.g, ic.b, ic.a)
    end

    local dc = GetEntryDisplayColor("detailFontColor", { r = 0.8, g = 0.8, b = 0.8, a = 1 })
    if row.detailText and type(row.detailText.SetTextColor) == "function" then
        row.detailText:SetTextColor(dc.r, dc.g, dc.b, dc.a)
    end
end

local function ApplyEntryDisplayRowVisuals(row)
    ApplyEntryDisplayRowLayout(row)
    ApplyEntryDisplayRowAppearance(row)
    ApplyEntryDisplayRowFonts(row)
end

function BestInSlot:UpdateEntryDisplayVisuals()
    if not self.__entryDisplay or not self.__entryDisplay.frame then
        return
    end

    local display = self.__entryDisplay
    local anchor = display.anchor
    local f = display.frame

    local width = tonumber(GetEntryDisplaySetting("frameWidth", 420)) or 420
    local height = tonumber(GetEntryDisplaySetting("frameHeight", 50)) or 50
    -- Keep the mover anchor smaller than the rows for easier positioning.
    local anchorWidth = math.min(width, 180)
    local anchorHeight = math.min(height, 30)
    if anchor then
        anchor:SetSize(anchorWidth, anchorHeight)
    end
    if f then
        f:SetSize(width, height)
    end

    -- Update all rows (active + pooled)
    if f and f.activeRows then
        for idx, row in ipairs(f.activeRows) do
            ApplyEntryDisplayRowVisuals(row)
            if f.__PositionRow then
                f.__PositionRow(row, idx)
            end
        end
    end
    if f and f.rowPool then
        for _, row in ipairs(f.rowPool) do
            ApplyEntryDisplayRowVisuals(row)
        end
    end
end

local function GetSlotName(slotID)
    if not slotID then return "" end
    for _, slotData in ipairs(SLOTS) do
        if slotData.slotID == slotID then
            return slotData.name or ""
        end
    end
    return tostring(slotID)
end

function BestInSlot:_EnsureEntryDisplay()
    if self.__entryDisplay and self.__entryDisplay.frame then
        return self.__entryDisplay
    end

    local parent = (E and E.UIParent) or UIParent
    local anchor = CreateFrame("Frame", "TwichUIMythicPlusBiSEntryDisplayAnchorFrame", parent)
    anchor:SetClampedToScreen(true)
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", parent, "CENTER", 0, 200)
    do
        local width = tonumber(GetEntryDisplaySetting("frameWidth", 420)) or 420
        local height = tonumber(GetEntryDisplaySetting("frameHeight", 50)) or 50
        local anchorWidth = math.min(width, 180)
        local anchorHeight = math.min(height, 30)
        anchor:SetSize(anchorWidth, anchorHeight)
    end
    anchor:Show()

    if E and E.CreateMover then
        E:CreateMover(anchor, "TwichUIMythicPlusBiSEntryDisplayMover", "TwichUI BiS Entry Display", nil, nil, nil,
            "ALL", nil, "TwichUI,Modules,MythicPlus,BiSEntryDisplay")
    end

    local f = CreateFrame("Frame", nil, parent)
    f:SetClampedToScreen(true)
    f:ClearAllPoints()
    f:SetPoint("TOP", anchor, "TOP", 0, 0)
    do
        local width = tonumber(GetEntryDisplaySetting("frameWidth", 420)) or 420
        local height = tonumber(GetEntryDisplaySetting("frameHeight", 50)) or 50
        f:SetSize(width, height)
    end
    f:EnableMouse(false)
    f:Hide()

    f.activeRows = {}
    f.rowPool = {}
    f._hoveredCount = 0
    f._pendingDismiss = false
    f._dismissTimer = nil
    f._hoverGraceTimer = nil

    local function PositionRow(row, index)
        local gap = tonumber(GetEntryDisplaySetting("frameSpacing", 6)) or 6
        local grow = tostring(GetEntryDisplaySetting("growDirection", "UP") or "UP")

        row:ClearAllPoints()
        if grow == "DOWN" then
            row:SetPoint("TOP", anchor, "BOTTOM", 0, -((index - 1) * (row:GetHeight() + gap)))
        else
            row:SetPoint("BOTTOM", anchor, "TOP", 0, ((index - 1) * (row:GetHeight() + gap)))
        end
    end

    local function ApplyRowVisuals(row)
        ApplyEntryDisplayRowVisuals(row)
        if row and row.icon and E and E.TexCoords then
            row.icon:SetTexCoord(unpack(E.TexCoords))
        elseif row and row.icon then
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end

    local function RecycleRow(row)
        if not row then return end

        for i, active in ipairs(f.activeRows) do
            if active == row then
                table.remove(f.activeRows, i)
                break
            end
        end

        if row.fadeGroup then row.fadeGroup:Stop() end
        if row.dismissGroup then row.dismissGroup:Stop() end
        row:Hide()
        row.itemText:SetText("")
        row.detailText:SetText("")
        row.icon:SetTexture(nil)
        row.__itemLink = nil
        row.__instanceName = nil
        row.__slotName = nil
        row.__boss = nil
        table.insert(f.rowPool, row)

        -- Reposition remaining rows to keep the stack tidy.
        for idx, r in ipairs(f.activeRows) do
            PositionRow(r, idx)
        end

        if #f.activeRows == 0 then
            f:Hide()
        end
    end

    local function AcquireRow()
        local row = table.remove(f.rowPool)
        if not row then
            row = CreateFrame("Frame", nil, parent)
            row:SetClampedToScreen(true)
            row:EnableMouse(true)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            row.itemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")

            row.detailText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

            row.fadeGroup = row:CreateAnimationGroup()
            row.fadeGroup:SetLooping("NONE")

            row.fadeIn = row.fadeGroup:CreateAnimation("Alpha")
            row.fadeIn:SetOrder(1)
            row.fadeIn:SetFromAlpha(0)
            row.fadeIn:SetToAlpha(1)
            row.fadeIn:SetDuration(0.25)

            row.moveIn = row.fadeGroup:CreateAnimation("Translation")
            row.moveIn:SetOrder(1)
            row.moveIn:SetOffset(0, -10)
            row.moveIn:SetDuration(0.25)

            row.fadeGroup:SetScript("OnFinished", function(anim)
                -- Fade-in only; auto-hide is handled by timers so hover can pause it.
                local r = anim:GetParent()
                if r then
                    r:SetAlpha(1)
                end
            end)

            row.dismissGroup = row:CreateAnimationGroup()
            row.dismissGroup:SetLooping("NONE")

            row.dismissFade = row.dismissGroup:CreateAnimation("Alpha")
            row.dismissFade:SetOrder(1)
            row.dismissFade:SetFromAlpha(1)
            row.dismissFade:SetToAlpha(0)
            row.dismissFade:SetDuration(0.2)

            row.dismissMove = row.dismissGroup:CreateAnimation("Translation")
            row.dismissMove:SetOrder(1)
            row.dismissMove:SetOffset(0, 10)
            row.dismissMove:SetDuration(0.2)

            row.dismissGroup:SetScript("OnFinished", function(anim)
                local r = anim:GetParent()
                RecycleRow(r)
            end)

            row:SetScript("OnEnter", function(self)
                if f then
                    f._hoveredCount = (f._hoveredCount or 0) + 1
                    if f._hoverGraceTimer and f._hoverGraceTimer.Cancel then
                        f._hoverGraceTimer:Cancel()
                    end
                    f._hoverGraceTimer = nil
                end

                if GameTooltip and GameTooltip.SetOwner then
                    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                    local link = rawget(self, "__itemLink")
                    if link and GameTooltip.SetHyperlink then
                        GameTooltip:SetHyperlink(link)
                    else
                        local title = rawget(self, "__instanceName") or ""
                        local slotName = rawget(self, "__slotName") or ""
                        local boss = rawget(self, "__boss")
                        if title ~= "" then GameTooltip:AddLine(title, 1, 1, 1) end
                        if slotName ~= "" then GameTooltip:AddLine("Slot: " .. slotName, 0.8, 0.8, 0.8) end
                        if boss then GameTooltip:AddLine("Boss: " .. tostring(boss), 0.8, 0.8, 0.8) end
                    end
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function()
                if GameTooltip and GameTooltip.Hide then
                    GameTooltip:Hide()
                end

                if f then
                    f._hoveredCount = math.max(0, (f._hoveredCount or 0) - 1)

                    if f._pendingDismiss and f._hoveredCount == 0 then
                        if f._hoverGraceTimer and f._hoverGraceTimer.Cancel then
                            f._hoverGraceTimer:Cancel()
                        end
                        if C_Timer and C_Timer.NewTimer then
                            f._hoverGraceTimer = C_Timer.NewTimer(3, function()
                                if f and f._pendingDismiss and (f._hoveredCount or 0) == 0 then
                                    BestInSlot:_DismissEntryDisplayAnimated()
                                end
                            end)
                        else
                            BestInSlot:_DismissEntryDisplayAnimated()
                        end
                    end
                end
            end)

            row:SetScript("OnMouseDown", function()
                if GameTooltip and GameTooltip.Hide then
                    GameTooltip:Hide()
                end
                -- Dismiss the entire list early (animated).
                BestInSlot:_DismissEntryDisplayAnimated()
            end)
        end

        ApplyRowVisuals(row)
        row:Show()
        row:EnableMouse(true)
        return row
    end

    f.__AcquireRow = AcquireRow
    f.__RecycleRow = RecycleRow
    f.__PositionRow = PositionRow
    f.__ApplyRowVisuals = ApplyRowVisuals

    self.__entryDisplay = { anchor = anchor, frame = f }

    -- Apply settings-driven sizing to anchor/container right away.
    self:UpdateEntryDisplayVisuals()
    return self.__entryDisplay
end

function BestInSlot:TestEntryDisplay()
    local display = self:_EnsureEntryDisplay()
    if not display or not display.frame then return end

    local sample = {
        { link = GetItemLinkForChat(19019, nil), boss = "Test Boss",    slotID = 16 },
        { link = GetItemLinkForChat(18832, nil), boss = "Another Boss", slotID = 13 },
        { link = GetItemLinkForChat(17182, nil), boss = nil,            slotID = 5 },
    }
    self:ShowMissingBiSOnInstanceEntry("Test Instance", sample)
end

function BestInSlot:_DismissEntryDisplayAnimated()
    if not self.__entryDisplay or not self.__entryDisplay.frame then return end
    local f = self.__entryDisplay.frame
    if not f.activeRows or #f.activeRows == 0 then
        f:Hide()
        return
    end

    f._pendingDismiss = false
    if f._dismissTimer and f._dismissTimer.Cancel then
        f._dismissTimer:Cancel()
    end
    f._dismissTimer = nil
    if f._hoverGraceTimer and f._hoverGraceTimer.Cancel then
        f._hoverGraceTimer:Cancel()
    end
    f._hoverGraceTimer = nil

    for _, row in ipairs(f.activeRows) do
        if row.EnableMouse then row:EnableMouse(false) end
        if row.fadeGroup then row.fadeGroup:Stop() end
        if row.dismissGroup then
            row.dismissGroup:Stop()
            row:SetAlpha(1)
            row.dismissGroup:Play()
        else
            if f.__RecycleRow then
                f.__RecycleRow(row)
            else
                row:Hide()
            end
        end
    end
end

function BestInSlot:_HideEntryDisplay(animated)
    if not self.__entryDisplay or not self.__entryDisplay.frame then return end
    local f = self.__entryDisplay.frame

    f._pendingDismiss = false
    if f._dismissTimer and f._dismissTimer.Cancel then
        f._dismissTimer:Cancel()
    end
    f._dismissTimer = nil
    if f._hoverGraceTimer and f._hoverGraceTimer.Cancel then
        f._hoverGraceTimer:Cancel()
    end
    f._hoverGraceTimer = nil

    if f.activeRows then
        while #f.activeRows > 0 do
            local row = f.activeRows[#f.activeRows]
            if row and row.fadeGroup then row.fadeGroup:Stop() end
            if row and row.dismissGroup then row.dismissGroup:Stop() end
            if row and f.__RecycleRow then
                f.__RecycleRow(row)
            elseif row then
                row:Hide()
                table.remove(f.activeRows, #f.activeRows)
            else
                table.remove(f.activeRows, #f.activeRows)
            end
        end
    end

    f:Hide()
end

---@param instanceName string
---@param missing table
function BestInSlot:ShowMissingBiSOnInstanceEntry(instanceName, missing)
    if not GetEntryDisplaySetting("enabled", true) then return end

    if not missing or #missing == 0 then
        -- User preference: don't show the entry display if there are no missing items.
        self:_HideEntryDisplay(false)
        return
    end

    local display = self:_EnsureEntryDisplay()
    local f = display.frame
    if not f then return end

    instanceName = NormalizeInstanceName(instanceName) or instanceName or ""

    self:_HideEntryDisplay(false)

    local duration = tonumber(GetEntryDisplaySetting("durationSec", 45)) or 45
    if duration < 5 then duration = 5 end
    if duration > 120 then duration = 120 end

    f._hoveredCount = 0
    f._pendingDismiss = false
    if f._dismissTimer and f._dismissTimer.Cancel then
        f._dismissTimer:Cancel()
    end
    f._dismissTimer = nil
    if f._hoverGraceTimer and f._hoverGraceTimer.Cancel then
        f._hoverGraceTimer:Cancel()
    end
    f._hoverGraceTimer = nil

    local maxRows = 12
    local toShow = (missing and #missing or 0)

    local shown = 0
    for _, entry in ipairs(missing) do
        if shown >= maxRows then break end
        shown = shown + 1

        local row = f.__AcquireRow and f.__AcquireRow()
        if not row then break end
        table.insert(f.activeRows, row)
        f.__PositionRow(row, shown)

        local slotName = GetSlotName(entry.slotID)
        local boss = entry.boss
        local link = entry.link

        row.__itemLink = link
        row.__instanceName = instanceName
        row.__slotName = slotName
        row.__boss = boss

        local iconTex = nil
        if C_Item and C_Item.GetItemInfoInstant then
            iconTex = select(5, C_Item.GetItemInfoInstant(link))
        end
        if iconTex then
            row.icon:SetTexture(iconTex)
            row.icon:Show()
        else
            row.icon:SetTexture(nil)
            row.icon:Hide()
        end

        row.itemText:SetText(string.format("%s |cffaaaaaa[%s]|r", tostring(link or ""), tostring(slotName)))
        if boss then
            row.detailText:SetText(string.format("%s  |cffaaaaaa- %s|r", tostring(instanceName), tostring(boss)))
        else
            row.detailText:SetText(tostring(instanceName))
        end

        if row.fadeGroup then
            row.fadeGroup:Stop()
            row:SetAlpha(0)
            row.fadeGroup:Play()
        end
    end

    if toShow > maxRows then
        local row = f.__AcquireRow and f.__AcquireRow()
        if row then
            shown = shown + 1
            table.insert(f.activeRows, row)
            f.__PositionRow(row, shown)

            row.__itemLink = nil
            row.__instanceName = instanceName
            row.__slotName = ""
            row.__boss = nil

            row.icon:Hide()
            row.itemText:SetText(string.format("BiS: %s", instanceName))
            row.detailText:SetText(string.format("...and %d more", toShow - maxRows))

            if row.fadeGroup then
                row.fadeGroup:Stop()
                row:SetAlpha(0)
                row.fadeGroup:Play()
            end
        end
    end

    f:Show()

    if C_Timer and C_Timer.NewTimer then
        f._dismissTimer = C_Timer.NewTimer(duration, function()
            if not f then return end
            if (f._hoveredCount or 0) > 0 then
                f._pendingDismiss = true
                return
            end
            BestInSlot:_DismissEntryDisplayAnimated()
        end)
    end
end

local function PopulateChooser(f, slotID)
    -- Clear previous
    local content = f.Content
    for _, child in ipairs({ content:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end
    -- TODO: Populate with dungeon loot
end

local function UpdateSlot(btn, data)
    -- data can be string (legacy) or table { link, source, iLevel }
    local itemLink, manualSource, manualILvl
    if type(data) == "table" then
        itemLink = data.link
        manualSource = data.source
        manualILvl = data.iLevel
    else
        itemLink = data
    end

    if not itemLink then
        btn.Icon:SetTexture(btn.defaultTexture)
        btn.Name:SetText(btn.slotName)
        btn.Name:SetTextColor(1, 0.82, 0)       -- Reset to GameFontNormal (Gold)
        btn.Details:SetText("Select an item...")
        btn.Details:SetTextColor(0.5, 0.5, 0.5) -- Reset to Grey
        btn.Icon:SetDesaturated(true)
        btn.Check:Hide()
        return
    end

    local name, _, quality, iLevel, _, _, _, _, _, icon = GetItemInfo(itemLink)
    if name then
        btn.Icon:SetTexture(icon)
        btn.Name:SetText(name)

        -- Check if owned
        local itemID = GetItemInfoInstant(itemLink)
        local owned, equipped, realILvl, realLink = GetOwnedStatus(itemID, btn.slotID)

        -- Determine Quality Color & Effective Link
        local r, g, b = GetItemQualityColor(quality)
        btn.Name:SetTextColor(r, g, b)

        -- Store effective link for tooltip
        btn.effectiveLink = itemLink

        -- Source Logic
        local source = manualSource
        if source == "All Items" then
            source = GetItemSource(itemID)
        end
        source = source or GetItemSource(itemID)

        if owned then
            btn.Icon:SetDesaturated(false)
            btn.Check:Show()
            local displayILvl = realILvl or iLevel
            if equipped then
                btn.Details:SetText("iLvl: " .. displayILvl .. " (Equipped)")
                btn.Details:SetTextColor(0, 1, 0)
            else
                btn.Details:SetText("iLvl: " .. displayILvl .. " (In Bags)")
                btn.Details:SetTextColor(0, 1, 0)
            end
        else
            btn.Icon:SetDesaturated(true)
            btn.Check:Hide()

            if source then
                btn.Details:SetText(source)
                btn.Details:SetTextColor(1, 0.4, 0.4)
            else
                btn.Details:SetText("Not Collected")
                btn.Details:SetTextColor(0.5, 0.5, 0.5)
            end
            btn.Check:Hide()

            if source then
                btn.Details:SetText(source)
                btn.Details:SetTextColor(1, 0.4, 0.4)
            else
                btn.Details:SetText("Not Collected")
                btn.Details:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    else
        -- Item info not ready, query it
        btn.Name:SetText("Loading...")
        local itemID = GetItemInfoInstant(itemLink)
        local item = Item:CreateFromItemID(itemID)
        item:ContinueOnItemLoad(function()
            UpdateSlot(btn, data)
        end)
    end
end

StaticPopupDialogs["TWICHUI_BIS_RESET"] = {
    text = "Are you sure you want to clear all Best in Slot items?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function(self, callback)
        local db = GetCharacterDB()
        if db then wipe(db) end
        if callback then callback() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["TWICHUI_BIS_COPY"] = {
    text = "Overwrite BiS list with currently equipped gear?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function(self, callback)
        local db = GetCharacterDB()
        if db then
            for _, slotData in ipairs(SLOTS) do
                local link = GetInventoryItemLink("player", slotData.slotID)
                -- Save as simple link for copy, or we could try to infer source
                db[slotData.slotID] = link
            end
        end
        if callback then callback() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function HexToRGB(hex)
    if not hex then return 1, 1, 1 end
    local rhex, ghex, bhex = string.sub(hex, 2, 3), string.sub(hex, 4, 5), string.sub(hex, 6, 7)
    return tonumber(rhex, 16) / 255, tonumber(ghex, 16) / 255, tonumber(bhex, 16) / 255
end

local function CreateBestInSlotPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    -- Background (optional, maybe just clear)

    -- Container for slots
    local container = CreateFrame("Frame", nil, panel)
    container:SetSize(600, 380)
    container:SetPoint("TOP", 0, -15)

    -- Layout: 2 columns
    local leftCol = CreateFrame("Frame", nil, container)
    leftCol:SetSize(SLOT_WIDTH, 400)
    leftCol:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

    local rightCol = CreateFrame("Frame", nil, container)
    rightCol:SetSize(SLOT_WIDTH, 400)
    rightCol:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)

    if not Chooser then
        Chooser = CreateChooserFrame(panel)
    end

    local slotFrames = {}

    local function RefreshAllSlots()
        local db = GetCharacterDB()
        for _, f in ipairs(slotFrames) do
            local link = db and db[f.slotID]
            UpdateSlot(f, link)
        end
    end

    -- Keep the UI accurate as the player equips/moves items.
    -- Without this, the panel can keep showing "(In Bags)" until reopened.
    do
        local refreshPending = false
        local function RequestRefresh()
            if refreshPending then return end
            refreshPending = true

            if C_Timer and C_Timer.After then
                C_Timer.After(0.05, function()
                    refreshPending = false
                    RefreshAllSlots()
                end)
            else
                refreshPending = false
                RefreshAllSlots()
            end
        end

        panel:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        panel:RegisterEvent("BAG_UPDATE_DELAYED")
        panel:SetScript("OnEvent", function()
            RequestRefresh()
        end)
    end

    local function CreateSlotFrame(parentCol, slotData, index)
        local f = CreateFrame("Button", nil, parentCol)
        f:SetSize(SLOT_WIDTH, SLOT_HEIGHT)
        f.slotID = slotData.slotID
        f.slotName = slotData.name
        f.defaultTexture = slotData.texture

        -- Icon
        f.Icon = f:CreateTexture(nil, "ARTWORK")
        f.Icon:SetSize(ICON_SIZE, ICON_SIZE)
        f.Icon:SetPoint("LEFT", f, "LEFT", 4, 0)
        f.Icon:SetTexture(slotData.texture)
        f.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.Icon:SetDesaturated(true)

        -- Border for icon
        f.IconBorder = f:CreateTexture(nil, "OVERLAY")
        f.IconBorder:SetAllPoints(f.Icon)
        f.IconBorder:SetColorTexture(0, 0, 0, 0) -- Placeholder for border

        -- Checkmark for owned
        f.Check = f:CreateTexture(nil, "OVERLAY", nil, 2)
        f.Check:SetSize(16, 16)
        f.Check:SetPoint("BOTTOMRIGHT", f.Icon, "BOTTOMRIGHT", 2, -2)
        f.Check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        f.Check:Hide()

        -- Clear Button (Red X)
        f.ClearButton = CreateFrame("Button", nil, f)
        f.ClearButton:SetSize(16, 16)
        f.ClearButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
        f.ClearButton:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        f.ClearButton:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
        f.ClearButton:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
        f.ClearButton:Hide()

        f.ClearButton:SetScript("OnClick", function(self)
            local btn = self:GetParent()
            local db = GetCharacterDB()
            if db then db[btn.slotID] = nil end
            UpdateSlot(btn, nil)
            self:Hide()
            GameTooltip:Hide() -- Hide tooltip as item is gone
        end)

        f.ClearButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Clear Slot", 1, 1, 1)
            GameTooltip:Show()
        end)
        f.ClearButton:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            if not self:GetParent():IsMouseOver() then
                self:Hide()
            end
        end)

        -- Slot Name / Item Name
        f.Name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.Name:SetPoint("TOPLEFT", f.Icon, "TOPRIGHT", 8, -2)
        f.Name:SetText(slotData.name)
        f.Name:SetJustifyH("LEFT")

        -- Item Level / Source
        f.Details = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.Details:SetPoint("BOTTOMLEFT", f.Icon, "BOTTOMRIGHT", 8, 2)
        f.Details:SetText("Select an item...")
        f.Details:SetTextColor(0.5, 0.5, 0.5)
        f.Details:SetJustifyH("LEFT")

        -- ElvUI Skinning
        if E then
            f:SetTemplate("Transparent")
            f.Icon:SetTexCoord(unpack(E.TexCoords))
        else
            -- Basic backdrop
            f:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true,
                tileSize = 16,
                edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 }
            })
            f:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
            f:SetBackdropBorderColor(0.4, 0.4, 0.4)
        end

        f:SetScript("OnEnter", function(self)
            if E then
                self:SetBackdropBorderColor(unpack(E.media.rgbvaluecolor))
            else
                self:SetBackdropBorderColor(1, 1, 1)
            end

            local db = GetCharacterDB()
            local data = db and db[self.slotID]
            if data then
                self.ClearButton:Show()

                local link = type(data) == "table" and data.link or data
                local manualILvl = type(data) == "table" and data.iLevel

                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

                local itemID = GetItemInfoInstant(link)
                local owned, _, _, realLink = GetOwnedStatus(itemID, self.slotID)

                if owned and realLink then
                    GameTooltip:SetHyperlink(realLink)
                else
                    -- Use effective link if available (from UpdateSlot)
                    if self.effectiveLink then
                        GameTooltip:SetHyperlink(self.effectiveLink)
                    elseif type(link) == "number" then
                        GameTooltip:SetItemByID(link)
                    else
                        GameTooltip:SetHyperlink(link)
                    end

                    if manualILvl then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Target Item Level: " .. manualILvl, 0, 1, 0)
                        GameTooltip:Show()
                    end
                end
                GameTooltip:Show()
            end
        end)
        f:SetScript("OnLeave", function(self)
            if E then
                self:SetBackdropBorderColor(unpack(E.media.bordercolor))
            else
                self:SetBackdropBorderColor(0.4, 0.4, 0.4)
            end
            GameTooltip:Hide()

            if not self.ClearButton:IsMouseOver() then
                self.ClearButton:Hide()
            end
        end)

        f:SetScript("OnClick", function(self)
            Chooser:ShowAnimated()
            Chooser.Title:SetText("Select " .. slotData.name)

            local db = GetCharacterDB()
            local data = db and db[self.slotID]
            local link, source, iLevel
            if type(data) == "table" then
                link = data.link
                source = data.source
                iLevel = data.iLevel
            else
                link = data
            end

            -- If no manual source, try to infer it so it shows up in the UI
            if link and not source then
                local itemID = GetItemInfoInstant(link)
                source = GetItemSource(itemID)
            end

            Chooser:SetInitialState(link, source, iLevel, self.slotID)

            Chooser.callback = function(newData)
                local db = GetCharacterDB()
                if db then db[self.slotID] = newData end
                UpdateSlot(self, newData)
            end
        end)

        -- Load initial data
        local db = GetCharacterDB()
        if db and db[slotData.slotID] then
            UpdateSlot(f, db[slotData.slotID])
        end

        table.insert(slotFrames, f)
        return f
    end

    -- Distribute slots
    -- Left: Head, Neck, Shoulder, Back, Chest, Wrist, MainHand, OffHand
    -- Right: Hands, Waist, Legs, Feet, Finger1, Finger2, Trinket1, Trinket2

    local leftSlots = { 1, 2, 3, 4, 5, 6, 15, 16 } -- Indices in SLOTS table
    local rightSlots = { 7, 8, 9, 10, 11, 12, 13, 14 }

    local yOffset = 0
    for i, idx in ipairs(leftSlots) do
        local slot = CreateSlotFrame(leftCol, SLOTS[idx], idx)
        slot:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 0, -yOffset)
        yOffset = yOffset + SLOT_HEIGHT + 4
    end

    yOffset = 0
    for i, idx in ipairs(rightSlots) do
        local slot = CreateSlotFrame(rightCol, SLOTS[idx], idx)
        slot:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -yOffset)
        yOffset = yOffset + SLOT_HEIGHT + 4
    end

    -- Buttons
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(100, 25)
    resetBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 20)
    resetBtn:SetText("Reset")
    if E then E:GetModule("Skins"):HandleButton(resetBtn) end

    -- Apply Error Color
    local Tools = T:GetModule("Tools")
    if Tools and Tools.Colors and Tools.Colors.TWICH and Tools.Colors.TWICH.TEXT_ERROR then
        local r, g, b = HexToRGB(Tools.Colors.TWICH.TEXT_ERROR)
        resetBtn:GetFontString():SetTextColor(r, g, b)
    end

    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("TWICHUI_BIS_RESET", nil, nil, RefreshAllSlots)
    end)
    resetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Reset BiS List", 1, 1, 1)
        GameTooltip:AddLine("Clears all selected Best in Slot items.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local copyBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    copyBtn:SetSize(100, 25)
    copyBtn:SetPoint("RIGHT", resetBtn, "LEFT", -10, 0)
    copyBtn:SetText("Copy Current")
    if E then E:GetModule("Skins"):HandleButton(copyBtn) end

    copyBtn:SetScript("OnClick", function()
        StaticPopup_Show("TWICHUI_BIS_COPY", nil, nil, RefreshAllSlots)
    end)
    copyBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Copy Equipped Gear", 1, 1, 1)
        GameTooltip:AddLine("Overwrites your BiS list with the gear you are currently wearing.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    copyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return panel
end

function BestInSlot:Initialize()
    if self.initialized then return end
    self.initialized = true

    if MythicPlusModule.MainWindow and MythicPlusModule.MainWindow.RegisterPanel then
        MythicPlusModule.MainWindow:RegisterPanel("bestinslot", function(parent, window)
            return CreateBestInSlotPanel(parent)
        end, nil, nil, {
            label = "BiS Gear",
            order = 99,                 -- Last
            icon = "Interface\\AddOns\\TwichUI\\Media\\Textures\\armor.tga",
            iconCoords = { 0, 1, 0, 1 } -- Full texture
        })
    end

    -- Print/show missing BiS items on dungeon/raid entry (rate-limited per instance).
    if not self.__entryFrame then
        local f = CreateFrame("Frame")
        self.__entryFrame = f
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        f:SetScript("OnEvent", function()
            local chatEnabled = true
            if CM and CM.GetProfileSettingSafe then
                chatEnabled = CM:GetProfileSettingSafe(
                    "mythicplus.bestInSlot.printMissingOnInstanceEntry", true)
            end

            local frameEnabled = GetEntryDisplaySetting("enabled", true)

            if not chatEnabled and not frameEnabled then
                return
            end

            local inInstance, instanceType = IsInInstance()
            if not inInstance then
                self.__lastPrintedInstance = nil
                self:_HideEntryDisplay(false)
                return
            end
            if instanceType ~= "party" and instanceType ~= "raid" then
                return
            end

            local instanceName = NormalizeInstanceName(select(1, GetInstanceInfo()))
            if not instanceName then return end

            if self.__lastPrintedInstance == instanceName then
                return
            end

            self.__lastPrintedInstance = instanceName

            local missing = nil
            if chatEnabled or frameEnabled then
                missing = self:GetMissingBiSForInstance(instanceName)
            end

            if chatEnabled then
                if missing and #missing > 0 then
                    Logger.Info(string.format("BiS: Missing %d item(s) for %s:", #missing, instanceName))
                    for _, entry in ipairs(missing) do
                        if entry.boss then
                            Logger.Info(string.format("  - %s (%s)", entry.link, entry.boss))
                        else
                            Logger.Info(string.format("  - %s", entry.link))
                        end
                    end
                end
            end

            if frameEnabled and missing and #missing > 0 then
                self:ShowMissingBiSOnInstanceEntry(instanceName, missing)
            end
        end)
    end
end
