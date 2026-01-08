local T = unpack(Twich)

--- @type DataTextsModule
local DataTexts = T:GetModule("DataTexts")
--- @type ToolsModule
local Tools = T:GetModule("Tools")
--- @type ConfigurationModule
local Configuration = T:GetModule("Configuration")
--- @type DataModule
local Data = T:GetModule("Data")

-- WoW globals
local _G = _G
local type = type
local tonumber = tonumber
local tostring = tostring
local ipairs = ipairs
local sort = table.sort

--- @class MythicPlusDataText
--- @field name string
--- @field panel any
--- @field displayCache GenericCache|nil
local MythicPlusDataText = DataTexts.MythicPlus or {}
DataTexts.MythicPlus = MythicPlusDataText
MythicPlusDataText.name = "TwichUI_MythicPlus"

local Module = Tools.Generics.Module:New({
    ENABLED = { key = "datatexts.mythicplus.enable", default = false, },

    COLOR_MODE = { key = "datatexts.mythicplus.colorMode", default = DataTexts.ColorMode.ELVUI },
    CUSTOM_COLOR = { key = "datatexts.mythicplus.customColor", default = DataTexts.DefaultColor },

    SHOW_KEYSTONE = { key = "datatexts.mythicplus.showKeystone", default = true, },
    SHOW_SCORE = { key = "datatexts.mythicplus.showScore", default = true, },
})

local DATATEXT_NAME = "TwichUI_MythicPlus"

local function GetMythicPlusScore()
    local C_ChallengeMode = _G.C_ChallengeMode
    if C_ChallengeMode and type(C_ChallengeMode.GetOverallDungeonScore) == "function" then
        local score = C_ChallengeMode.GetOverallDungeonScore()
        return tonumber(score) or 0
    end
    return 0
end

local function GetOwnedKeystoneInfo()
    local C_MythicPlus = _G.C_MythicPlus
    if not C_MythicPlus then
        return nil, nil
    end

    local mapId
    if type(C_MythicPlus.GetOwnedKeystoneChallengeMapID) == "function" then
        local ok, value = pcall(C_MythicPlus.GetOwnedKeystoneChallengeMapID)
        if ok then
            mapId = tonumber(value)
        end
    end

    local level
    if type(C_MythicPlus.GetOwnedKeystoneLevel) == "function" then
        local ok, value = pcall(C_MythicPlus.GetOwnedKeystoneLevel)
        if ok then
            level = tonumber(value)
        end
    end

    return mapId, level
end

local function GetChallengeMapName(mapId)
    mapId = tonumber(mapId)
    if not mapId then return nil end

    local C_ChallengeMode = _G.C_ChallengeMode
    if C_ChallengeMode and type(C_ChallengeMode.GetMapUIInfo) == "function" then
        local ok, name = pcall(C_ChallengeMode.GetMapUIInfo, mapId)
        if ok and name and name ~= "" then
            return name
        end
    end

    local dungeonPortals = Data and rawget(Data, "DungeonPortals") or nil
    local portalData = dungeonPortals and dungeonPortals.GetByMapId and dungeonPortals:GetByMapId(mapId) or nil
    return portalData and portalData.name or nil
end

local function GetOwnedKeystoneLink()
    local C_MythicPlus = _G.C_MythicPlus
    if C_MythicPlus and type(C_MythicPlus.GetOwnedKeystoneLink) == "function" then
        local ok, link = pcall(C_MythicPlus.GetOwnedKeystoneLink)
        if ok and type(link) == "string" and link:find("|Hkeystone:") then
            return link
        end
    end

    -- Bag scan fallback: try to find any keystone hyperlink.
    local C_Container = _G.C_Container
    if C_Container and type(C_Container.GetContainerNumSlots) == "function" and type(C_Container.GetContainerItemLink) == "function" then
        for bag = 0, 4 do
            local slots = C_Container.GetContainerNumSlots(bag)
            if slots and slots > 0 then
                for slot = 1, slots do
                    local link = C_Container.GetContainerItemLink(bag, slot)
                    if type(link) == "string" and link:find("|Hkeystone:") then
                        return link
                    end
                end
            end
        end
    end

    return nil
end

local function GetAffixNamesFromKeystoneLink(link)
    if type(link) ~= "string" or link == "" then
        return nil
    end

    local C_TooltipInfo = _G.C_TooltipInfo
    if not (C_TooltipInfo and type(C_TooltipInfo.GetHyperlink) == "function") then
        return nil
    end

    local ok, tip = pcall(C_TooltipInfo.GetHyperlink, link)
    if not ok or type(tip) ~= "table" or type(tip.lines) ~= "table" then
        return nil
    end

    local names = {}
    local seen = {}

    for _, line in ipairs(tip.lines) do
        local leftText = line and line.leftText
        local leftColor = line and line.leftColor
        if type(leftText) == "string" and leftText ~= "" and type(leftColor) == "table" then
            local r = tonumber(leftColor.r) or 0
            local g = tonumber(leftColor.g) or 0
            local b = tonumber(leftColor.b) or 0

            -- Keystone affixes appear as green lines in the item tooltip.
            local looksGreen = (g >= 0.85) and (r <= 0.35) and (b <= 0.35)
            if looksGreen then
                local trimmed = leftText:gsub("^%s+", ""):gsub("%s+$", "")
                if trimmed ~= "" and not seen[trimmed] then
                    seen[trimmed] = true
                    names[#names + 1] = trimmed
                end
            end
        end
    end

    if #names == 0 then
        return nil
    end

    return names
end

local function GetOwnedKeystoneAffixNames()
    local link = GetOwnedKeystoneLink()
    local names = link and GetAffixNamesFromKeystoneLink(link) or nil
    if names then
        return names
    end

    -- Fallback: use owned keystone affix IDs.
    local C_MythicPlus = _G.C_MythicPlus
    local C_ChallengeMode = _G.C_ChallengeMode
    if not (C_MythicPlus and C_ChallengeMode) then
        return nil
    end

    local out = {}
    local function AddAffixName(affixId)
        affixId = tonumber(affixId)
        if not affixId or affixId <= 0 then return end
        if type(C_ChallengeMode.GetAffixInfo) ~= "function" then return end
        local ok, name = pcall(C_ChallengeMode.GetAffixInfo, affixId)
        if ok and name and name ~= "" then
            out[#out + 1] = name
        end
    end

    if type(C_MythicPlus.GetOwnedKeystoneAffixID) == "function" then
        for i = 1, 4 do
            local ok, affixId = pcall(C_MythicPlus.GetOwnedKeystoneAffixID, i)
            if ok then
                AddAffixName(affixId)
            end
        end
    elseif type(C_MythicPlus.GetOwnedKeystoneAffixes) == "function" then
        local ok, affixes = pcall(C_MythicPlus.GetOwnedKeystoneAffixes)
        if ok and type(affixes) == "table" then
            for _, entry in ipairs(affixes) do
                local id = entry
                if type(entry) == "table" then
                    id = entry.id or entry.affixID or entry.affixId
                end
                AddAffixName(id)
            end
        end
    end

    if #out == 0 then
        return nil
    end
    return out
end

local function GetMythicPlusVaultActivities()
    local C_WeeklyRewards = _G.C_WeeklyRewards
    if not (C_WeeklyRewards and type(C_WeeklyRewards.GetActivities) == "function" and type(C_WeeklyRewards.GetActivityInfo) == "function") then
        return nil
    end

    local activities

    -- Prefer requesting mythic-plus activities specifically (type 3 on most clients).
    do
        local ok, result = pcall(C_WeeklyRewards.GetActivities, 3)
        if ok and type(result) == "table" then
            activities = result
        end
    end

    -- Fallback: try the no-arg variant.
    if not activities then
        local ok, result = pcall(C_WeeklyRewards.GetActivities)
        if ok and type(result) == "table" then
            activities = result
        end
    end

    if type(activities) ~= "table" or #activities == 0 then
        return nil
    end

    local rows = {}

    for _, activityId in ipairs(activities) do
        local id = tonumber(activityId)
        if id then
            local ok, a, b, c, d, e, f = pcall(C_WeeklyRewards.GetActivityInfo, id)
            if ok then
                local info
                if type(a) == "table" then
                    info = a
                else
                    info = {
                        activityType = a,
                        index = b,
                        progress = c,
                        threshold = d,
                        level = e,
                        unused1 = f,
                    }
                end

                local progress = tonumber(info.progress)
                local threshold = tonumber(info.threshold)

                -- Keep only rows that look like Great Vault progress thresholds.
                if progress and threshold and threshold > 0 then
                    rows[#rows + 1] = {
                        activityId = id,
                        progress = progress,
                        threshold = threshold,
                    }
                end
            end
        end
    end

    if #rows == 0 then
        return nil
    end

    sort(rows, function(x, y)
        return (tonumber(x.threshold) or 0) < (tonumber(y.threshold) or 0)
    end)

    return rows
end

function MythicPlusDataText:GetConfiguration()
    return Module.CONFIGURATION
end

function MythicPlusDataText:Refresh()
    if self.displayCache then
        self.displayCache:invalidate()
    end
    if self.panel and self.panel.text then
        self.panel.text:SetText(self:GetDisplayText())
    end
end

function MythicPlusDataText:GetDisplayText()
    if not self.displayCache then
        self.displayCache = Tools.Generics.Cache.New("TwichUIMythicPlusDataTextDisplayCache")
    end

    return self.displayCache:get(function()
        local colorMode = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.COLOR_MODE)
        local showKey = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.SHOW_KEYSTONE) ~= false
        local showScore = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.SHOW_SCORE) ~= false

        local mapId, level = GetOwnedKeystoneInfo()
        local score = GetMythicPlusScore()

        local parts = {}
        if showKey then
            if mapId and level then
                local name = GetChallengeMapName(mapId) or "Keystone"
                parts[#parts + 1] = ("+%d %s"):format(level, name)
            else
                parts[#parts + 1] = "No Keystone"
            end
        end

        if showScore then
            parts[#parts + 1] = tostring(score)
        end

        if #parts == 0 then
            parts[1] = "Mythic+"
        end

        local label = table.concat(parts, " | ")
        return DataTexts:ColorTextByElvUISetting(colorMode, label, Module.CONFIGURATION.CUSTOM_COLOR)
    end)
end

function MythicPlusDataText:OpenMythicPlusFrame()
    --- @type MythicPlusModule
    local MythicPlusModule = T:GetModule("MythicPlus")
    if not MythicPlusModule then return end

    -- Ensure the module is enabled/initialized.
    if MythicPlusModule.Enable then
        pcall(MythicPlusModule.Enable, MythicPlusModule)
    end

    local window = MythicPlusModule.MainWindow
    if window and window.Enable then
        pcall(window.Enable, window, true)
    elseif window and window.ShowAnimated then
        pcall(window.ShowAnimated, window)
    end
end

function MythicPlusDataText:ShowDungeonPortalsMenu()
    if not self.panel then return end

    local C_MythicPlus = _G.C_MythicPlus
    if not (C_MythicPlus and type(C_MythicPlus.GetCurrentSeason) == "function" and type(C_MythicPlus.GetSeasonMaps) == "function") then
        return
    end

    local okSeason, seasonId = pcall(C_MythicPlus.GetCurrentSeason)
    seasonId = okSeason and tonumber(seasonId) or nil

    local maps
    if seasonId then
        local ok, result = pcall(C_MythicPlus.GetSeasonMaps, seasonId)
        if ok and type(result) == "table" then
            maps = result
        end
    end

    if not maps or #maps == 0 then
        return
    end

    local dungeonPortals = Data and rawget(Data, "DungeonPortals") or nil
    local byMapId = dungeonPortals and dungeonPortals.byMapId or nil
    
    local menuList = {}
    menuList[#menuList + 1] = { text = "Dungeon Portals", isTitle = true, notClickable = true }
    
    if type(byMapId) ~= "table" then
        menuList[#menuList + 1] = { text = "No portal data loaded.", isDescription = true, notClickable = true }
        local instance = DataTexts.Menu:Acquire("twitchui_mythicplus_portals")
        DataTexts.Menu:Show(instance, self.panel, menuList)
        return
    end
    
    local entries = {}
    for mapId, entry in pairs(byMapId) do
        if type(entry) == "table" and (entry.spellId or entry.spellID) then
            entries[#entries + 1] = {
                mapId = tonumber(entry.mapId or mapId),
                name = tostring(entry.name or GetChallengeMapName(entry.mapId or mapId) or ("Map " .. tostring(mapId))),
                spellId = tonumber(entry.spellId or entry.spellID),
            }
        end
    end
    
    sort(entries, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)
    
    local C_Spell = _G.C_Spell
    for _, e in ipairs(entries) do
        local spellId = tonumber(e.spellId)
        if spellId then
            local known = false
            if C_Spell and type(C_Spell.IsSpellKnown) == "function" then
                local ok, result = pcall(C_Spell.IsSpellKnown, spellId)
                known = ok and result == true
            else
                ---@diagnostic disable-next-line: deprecated
                local IsSpellKnownLegacy = _G.IsSpellKnown
                if type(IsSpellKnownLegacy) == "function" then
                    local ok, result = pcall(IsSpellKnownLegacy, spellId)
                    known = ok and result == true
                end
            end
    
            menuList[#menuList + 1] = {
                text = e.name,
                spell = spellId,
                notClickable = not known,
                color = (not known) and "|cff888888" or nil,
            }
        end
    end
    
    if #menuList == 1 then
        menuList[#menuList + 1] = { text = "No portals configured.", isDescription = true, notClickable = true }
    end
    
    local instance = DataTexts.Menu:Acquire("twitchui_mythicplus_portals")
    DataTexts.Menu:Show(instance, self.panel, menuList)
end

function MythicPlusDataText:OnEnter(panel)
    if panel then
        self.panel = panel
    end

    if not self.panel then return end

    local GameTooltip = _G.GameTooltip
    if not (GameTooltip and GameTooltip.SetOwner) then
        return
    end

    GameTooltip:SetOwner(self.panel, "ANCHOR_TOP")
    GameTooltip:ClearLines()

    GameTooltip:AddLine("Mythic+", 1, 1, 1)

    local score = GetMythicPlusScore()
    GameTooltip:AddLine(("Score: %d"):format(score), 0.9, 0.9, 0.9)

    local mapId, level = GetOwnedKeystoneInfo()
    if mapId and level then
        local name = GetChallengeMapName(mapId) or "Keystone"
        GameTooltip:AddLine(("Keystone: %s +%d"):format(name, level), 1, 1, 1)

        local affixes = GetOwnedKeystoneAffixNames()
        if type(affixes) == "table" and #affixes > 0 then
            for _, affixName in ipairs(affixes) do
                GameTooltip:AddLine(tostring(affixName), 0.1, 1.0, 0.1)
            end
        end
    else
        GameTooltip:AddLine("Keystone: None", 0.7, 0.7, 0.7)
    end

    -- Great Vault progress (Mythic+)
    local vaultRows = GetMythicPlusVaultActivities()
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Great Vault", 1, 0.82, 0)
    if type(vaultRows) == "table" and #vaultRows > 0 then
        for _, row in ipairs(vaultRows) do
            local p = tonumber(row.progress) or 0
            local t = tonumber(row.threshold) or 0
            if t > 0 then
                GameTooltip:AddLine(("Mythic+: %d/%d"):format(p, t), 0.9, 0.9, 0.9)
            end
        end
    else
        GameTooltip:AddLine("Mythic+: unavailable", 0.7, 0.7, 0.7)
    end

    -- Season progress
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Season Progress", 1, 0.82, 0)
    local thresholds = { 2000, 2500, 3000 }
    for _, t in ipairs(thresholds) do
        local done = score >= t
        local r, g, b = done and 0.1 or 0.7, done and 1.0 or 0.7, done and 0.1 or 0.7
        GameTooltip:AddLine(("%d: %s"):format(t, done and "Complete" or "Incomplete"), r, g, b)
    end

    GameTooltip:Show()
end

function MythicPlusDataText:OnLeave()
    if _G.GameTooltip and _G.GameTooltip.Hide then
        _G.GameTooltip:Hide()
    end
end

function MythicPlusDataText:OnEvent(panel, event, ...)
    if panel then
        self.panel = panel
    end

    if event == "ELVUI_FORCE_UPDATE" then
        if self.displayCache then
            self.displayCache:invalidate()
        end
    end

    if self.panel and self.panel.text then
        self.panel.text:SetText(self:GetDisplayText())
    end
end

function MythicPlusDataText:Enable()
    if Module:IsEnabled() then return end
    if DataTexts:IsDataTextRegistered(DATATEXT_NAME) then
        return
    end

    self:GetDisplayText() -- warm cache

    Module:Enable(nil)

    DataTexts:NewDataText(
        DATATEXT_NAME,
        "TwichUI: Mythic+",
        {
            "PLAYER_ENTERING_WORLD",
            "BAG_UPDATE_DELAYED",
            "CHALLENGE_MODE_COMPLETED",
            "CHALLENGE_MODE_MAPS_UPDATE",
            "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE",
            "WEEKLY_REWARDS_UPDATE",
        },
        function(panel, event, ...) self:OnEvent(panel, event, ...) end,
        nil,
        function(panel, button)
            if panel then
                self.panel = panel
            end
            button = tostring(button or "")
            if button:find("LeftButton", 1, true) then
                self:OpenMythicPlusFrame()
            elseif button:find("RightButton", 1, true) then
                self:ShowDungeonPortalsMenu()
            end
        end,
        function(panel) self:OnEnter(panel) end,
        function() self:OnLeave() end
    )
end

function MythicPlusDataText:Disable()
    Module:Disable()
    if DataTexts:IsDataTextRegistered(DATATEXT_NAME) then
        DataTexts:RemoveDataText(DATATEXT_NAME)
    end
end

function MythicPlusDataText:OnInitialize()
    if Module:IsEnabled() then return end
    if Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.ENABLED) then
        self:Enable()
    end
end
