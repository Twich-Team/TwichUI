---@diagnostic disable-next-line: undefined-global
local T = unpack(Twich)
local _G = _G

--- @class MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")

--- @class MythicPlusBestInSlotSubmodule
local BestInSlot = MythicPlusModule.BestInSlot or {}
MythicPlusModule.BestInSlot = BestInSlot

local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local GameTooltip = _G.GameTooltip

-- ElvUI integration
local ElvUI = rawget(_G, "ElvUI")
local E = ElvUI and ElvUI[1]

local SLOT_WIDTH = 270
local SLOT_HEIGHT = 44
local ICON_SIZE = 36

local SLOTS = {
    { name = "Head",     slotID = 1,  texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head" },
    { name = "Neck",     slotID = 2,  texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Neck" },
    { name = "Shoulder", slotID = 3,  texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder" },
    { name = "Back",     slotID = 15, texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest" }, -- Back uses Chest icon usually or specific back icon
    { name = "Chest",    slotID = 5,  texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest" },
    { name = "Wrist",    slotID = 9,  texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Wrists" },
    { name = "Hands",    slotID = 10, texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Hands" },
    { name = "Waist",    slotID = 6,  texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Waist" },
    { name = "Legs",     slotID = 7,  texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Legs" },
    { name = "Feet",     slotID = 8,  texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Feet" },
    { name = "Finger1",  slotID = 11, texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger" },
    { name = "Finger2",  slotID = 12, texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger" },
    { name = "Trinket1", slotID = 13, texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket" },
    { name = "Trinket2", slotID = 14, texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket" },
    { name = "MainHand", slotID = 16, texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand" },
    { name = "OffHand",  slotID = 17, texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand" },
}

-- Fix Back texture
SLOTS[4].texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest" -- Placeholder, usually distinct

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

local function ScanEJ(searchType, searchValue, limitTier)
    -- searchType: "ID" (find source of itemID) or "NAME" (find itemID of itemName)
    -- limitTier: if true, only scan the current tier (for performance)
    -- print("DEBUG: ScanEJ called with", searchType, searchValue)

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
    -- print("DEBUG: NumTiers:", numTiers)

    local function ScanTier(tierIndex)
        EJ_SelectTier(tierIndex)
        -- print("DEBUG: Scanning Tier:", tierIndex)

        local function ScanInstances(isRaid)
            local index = 1
            while true do
                local instanceID, instanceName = EJ_GetInstanceByIndex(index, isRaid)
                if not instanceID then break end
                -- print("DEBUG: Scanning Instance:", instanceName, "ID:", instanceID)

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
    if C_MythicPlus and C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetSeasonMaps then
        local seasonID = C_MythicPlus.GetCurrentSeason()
        if seasonID then
            local maps = C_MythicPlus.GetSeasonMaps(seasonID)
            if maps then
                for _, mapId in ipairs(maps) do
                    if not seen[mapId] then
                        seen[mapId] = true
                        table.insert(mapIds, mapId)
                    end
                end
            end
        end
    end

    -- 2. Fallback to C_ChallengeMode.GetMapTable (All Challenge Mode Maps)
    if #mapIds == 0 and C_ChallengeMode and C_ChallengeMode.GetMapTable then
        local maps = C_ChallengeMode.GetMapTable()
        if maps then
            for _, mapId in ipairs(maps) do
                if not seen[mapId] then
                    seen[mapId] = true
                    table.insert(mapIds, mapId)
                end
            end
        end
    end

    -- Resolve Names
    for _, mapId in ipairs(mapIds) do
        local name = C_ChallengeMode.GetMapUIInfo(mapId)
        if name then
            table.insert(dungeons, name)
        end
    end
    table.sort(dungeons)

    -- 3. Hard Fallback
    if #dungeons == 0 then
        dungeons = {
            "Ara-Kara, City of Echoes",
            "City of Threads",
            "The Stonevault",
            "The Dawnbreaker",
            "Mists of Tirna Scithe",
            "The Necrotic Wake",
            "Siege of Boralus",
            "Grim Batol"
        }
    end

    return {
        {
            label = "Dungeons",
            options = dungeons
        },
        {
            label = "Raids",
            options = {
                "Nerub-ar Palace",
                "Liberation of Undermine"
            }
        },
        {
            label = "Other",
            options = {
                "Crafted",
                "Delve",
                "World Boss",
                "PvP",
                "Other"
            }
        }
    }
end

local function CreateChooserFrame(parent)
    local f = CreateFrame("Frame", "TwichUI_BiS_Chooser", parent)
    f:SetSize(320, 500)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(100)
    f:EnableMouse(true)

    if E then
        f:SetTemplate("Transparent")
    else
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })
    end

    f.Title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.Title:SetPoint("TOP", 0, -15)
    f.Title:SetText("Add Item")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    if E then E:GetModule("Skins"):HandleCloseButton(close) end

    -- 1. Item Input
    local input = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    input:SetSize(280, 20)
    input:SetPoint("TOP", f.Title, "BOTTOM", 0, -20)
    input:SetAutoFocus(false)
    input:SetTextInsets(5, 5, 0, 0)
    input:SetFontObject("ChatFontNormal")
    input:SetText("Ara-Kara Sacbrood")
    if E then E:GetModule("Skins"):HandleEditBox(input) end
    f.Input = input

    local instr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instr:SetPoint("TOP", input, "BOTTOM", 0, -5)
    instr:SetText("Enter Item ID, Link, or Name (Dungeon/Raid)")
    instr:SetTextColor(0.7, 0.7, 0.7)

    -- 2. Selected Item Preview
    local preview = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    preview:SetPoint("TOP", instr, "BOTTOM", 0, -15)
    preview:SetText("No item selected")
    f.Preview = preview

    -- 3. Source Selection
    local sourceLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sourceLabel:SetPoint("TOP", preview, "BOTTOM", 0, -20)
    sourceLabel:SetText("Select Source (Optional)")

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -150)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 50)
    if E then E:GetModule("Skins"):HandleScrollBar(scroll.ScrollBar) end

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(270, 1)
    scroll:SetScrollChild(content)
    f.Content = content

    -- Populate Sources
    local yOffset = 0
    f.selectedSource = nil
    f.sourceButtons = {}

    local sources = GetSources()

    for _, category in ipairs(sources) do
        local catHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        catHeader:SetPoint("TOPLEFT", 10, -yOffset)
        catHeader:SetText(category.label)
        yOffset = yOffset + 20

        for _, src in ipairs(category.options) do
            local btn = CreateFrame("Button", nil, content)
            btn:SetSize(250, 20)
            btn:SetPoint("TOPLEFT", 10, -yOffset)

            local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("LEFT", 5, 0)
            text:SetText(src)
            btn.Text = text

            local check = btn:CreateTexture(nil, "OVERLAY", nil, 7)
            check:SetSize(20, 20)
            check:SetPoint("RIGHT", -5, 0)
            check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            check:Hide()
            btn.Check = check

            -- Highlight texture
            local hl = btn:CreateTexture(nil, "BACKGROUND")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.1)
            hl:Hide()
            btn.Highlight = hl

            -- Hover texture
            local hover = btn:CreateTexture(nil, "BACKGROUND")
            hover:SetAllPoints()
            hover:SetColorTexture(1, 1, 1, 0.05)
            hover:Hide()
            btn.Hover = hover

            btn:SetScript("OnEnter", function()
                btn.Hover:Show()
            end)

            btn:SetScript("OnLeave", function()
                btn.Hover:Hide()
            end)

            btn:SetScript("OnClick", function()
                -- print("DEBUG: Source clicked:", src)
                for _, b in ipairs(f.sourceButtons) do
                    b.Check:Hide()
                    b.Highlight:Hide()
                end
                btn.Check:Show()
                btn.Highlight:Show()
                f.selectedSource = src
            end)

            table.insert(f.sourceButtons, btn)
            yOffset = yOffset + 20
        end
        yOffset = yOffset + 10
    end
    content:SetHeight(yOffset)

    -- 4. Add Button
    local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addBtn:SetSize(120, 25)
    addBtn:SetPoint("BOTTOM", 0, 15)
    addBtn:SetText("Add Item")
    if E then E:GetModule("Skins"):HandleButton(addBtn) end

    -- Logic
    local currentLink = nil

    input:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text and text ~= "" then
            local _, link = GetItemInfo(text)
            if not link then
                local id = tonumber(text) or GetItemInfoInstant(text)
                if id then
                    _, link = GetItemInfo(id)
                    if not link then link = "item:" .. id end -- Fallback
                else
                    -- Try searching EJ for name (Current Tier Only)
                    preview:SetText("Searching Dungeon Journal...")
                    preview:SetTextColor(1, 1, 0)

                    local ejItemID = ScanEJ("NAME", text, true)
                    if ejItemID then
                        _, link = GetItemInfo(ejItemID)
                        if not link then link = "item:" .. ejItemID end
                    end
                end
            end

            if link then
                currentLink = link
                local name = GetItemInfo(link) or "Unknown Item"
                preview:SetText(name)
                preview:SetTextColor(0, 1, 0)
            else
                preview:SetText("Item not found. Try using Item ID (e.g. from Wowhead).")
                preview:SetTextColor(1, 0, 0)
                currentLink = nil
            end
        end
        self:ClearFocus()
    end)

    addBtn:SetScript("OnClick", function()
        if currentLink and f.callback then
            -- print("DEBUG: Saving Item", currentLink, "Source:", f.selectedSource)
            f.callback({ link = currentLink, source = f.selectedSource })
            f:Hide()
        end
    end)

    function f:SetInitialState(link, source)
        self.Input:SetText(link or "")
        self.selectedSource = source
        currentLink = link

        -- Update Preview
        if link then
            local name = GetItemInfo(link) or link
            self.Preview:SetText(name)
            self.Preview:SetTextColor(0, 1, 0)
        else
            self.Preview:SetText("No item selected")
            self.Preview:SetTextColor(1, 1, 1)
        end

        -- Update Source Buttons
        for _, btn in ipairs(self.sourceButtons) do
            btn.Check:Hide()
            btn.Highlight:Hide()
            if btn.Text:GetText() == source then
                btn.Check:Show()
                btn.Highlight:Show()
            end
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
        btn.Icon:SetDesaturated(false)
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
        local source = manualSource or GetItemSource(itemID)
        local sourceText = source and (" - " .. source) or (manualSource == nil and " - ???" or "")

        if owned then
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
            btn.Check:Hide()
            local details = source or manualSource or "Not Collected"
            btn.Details:SetText(details)
            btn.Details:SetTextColor(0.5, 0.5, 0.5)
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
        end)

        f:SetScript("OnClick", function(self)
            Chooser:Show()
            Chooser.Title:SetText("Add " .. slotData.name)

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

            Chooser:SetInitialState(link, source, iLevel)

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
        GameTooltip:SetText("Reset BiS List")
        GameTooltip:AddLine("Clears all selected Best in Slot items.", 1, 1, 1)
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
        GameTooltip:SetText("Copy Equipped Gear")
        GameTooltip:AddLine("Overwrites your BiS list with the gear you are currently wearing.", 1, 1, 1)
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
end
