local _G = _G
---@diagnostic disable-next-line: undefined-global
local T = unpack(Twich)
---@diagnostic disable: undefined-field
local MythicPlusModule = T:GetModule("MythicPlus")

---@type ConfigurationModule
local CM = T:GetModule("Configuration")
---@type ToolsModule
local TM = T:GetModule("Tools")

local CreateFrame = _G.CreateFrame
local CreateVector3D = _G.CreateVector3D
local CreateColor = _G.CreateColor
local UnitName = _G.UnitName
local UnitClass = _G.UnitClass
local UnitGUID = _G.UnitGUID
local GetAverageItemLevel = _G.GetAverageItemLevel
local C_Timer = _G.C_Timer
local IsStealthed = _G.IsStealthed
local UnitIsVisible = _G.UnitIsVisible
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS

---@type LoggerModule
local Logger = T:GetModule("Logger")

-- Set true temporarily when debugging model rendering/overlays.
local SUMMARY_MODEL_DEBUG = false

local LSM = T.Libs and T.Libs.LSM
local TT = (TM and TM.Text) or
    { Color = function(_, text) return text end, ColorByClass = function(_, text) return text end }
local CT = (TM and TM.Colors) or
    { TWICH = { TEXT_PRIMARY = "#FFFFFF", TEXT_MUTED = "#AAAAAA", SECONDARY_ACCENT = "#FFFFFF", PANEL_BG = "#000000" } }
local function HexToRGB(hex)
    if not hex or type(hex) ~= "string" then return 1, 1, 1 end
    if hex:sub(1, 1) == " " then hex = hex:gsub("%s+", "") end
    if hex:sub(1, 1) == "#" then
        local rhex, ghex, bhex = hex:sub(2, 3), hex:sub(4, 5), hex:sub(6, 7)
        local r = tonumber(rhex, 16)
        local g = tonumber(ghex, 16)
        local b = tonumber(bhex, 16)
        if r and g and b then
            return r / 255, g / 255, b / 255
        end
    end
    return 1, 1, 1
end

local DEFAULT_REWARD_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function GetFontPath()
    if not CM or not MythicPlusModule or not MythicPlusModule.CONFIGURATION then
        return nil
    end
    local baseFontName = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_FONT)
    if LSM and baseFontName then
        return LSM:Fetch("font", baseFontName)
    end
    return nil
end

local function GetMythicPlusScore()
    local C_ChallengeMode = _G.C_ChallengeMode
    if C_ChallengeMode and type(C_ChallengeMode.GetOverallDungeonScore) == "function" then
        local score = C_ChallengeMode.GetOverallDungeonScore()
        return tonumber(score) or 0
    end
    return 0
end

local function GetCurrentWeeklyAffixes()
    local C_MythicPlus = _G.C_MythicPlus
    if C_MythicPlus and type(C_MythicPlus.GetCurrentAffixes) == "function" then
        local ok, affixes = pcall(C_MythicPlus.GetCurrentAffixes)
        if ok and type(affixes) == "table" then
            local entries = {}
            for _, entry in ipairs(affixes) do
                ---@type any
                local id = entry
                local level
                if type(entry) == "table" then
                    ---@type any
                    local entryAny = entry
                    id = entryAny.id or entryAny.affixID or entryAny.affixId
                    level = entryAny.startingLevel or entryAny.startingKeystoneLevel or entryAny.requiredLevel or
                        entryAny.level
                end
                id = tonumber(id)
                level = tonumber(level)
                if id then
                    entries[#entries + 1] = { id = id, level = level }
                end
            end
            return entries
        end
    end
    return {}
end

local function GetAffixInfo(affixID)
    local C_ChallengeMode = _G.C_ChallengeMode
    if C_ChallengeMode and type(C_ChallengeMode.GetAffixInfo) == "function" then
        local ok, name, desc, icon = pcall(C_ChallengeMode.GetAffixInfo, affixID)
        if ok then
            return name, desc, icon
        end
    end
    return nil, nil, nil
end

local function GetNextRewardTarget(currentScore, markers, obtainedByScore)
    currentScore = tonumber(currentScore) or 0

    local best
    if type(markers) == "table" then
        for _, m in ipairs(markers) do
            local t = m and tonumber(m.__twichuiScoreTarget)
            local obtained = (type(obtainedByScore) == "table") and (obtainedByScore[t] == true) or false
            if t and not obtained and t > currentScore and (best == nil or t < best) then
                best = t
            end
        end
    end

    -- Fallback to the default marker scores if markers aren't built yet.
    if best == nil then
        local defaults = { 2000, 2500, 3000 }
        for _, t in ipairs(defaults) do
            if t > currentScore and (best == nil or t < best) then
                best = t
            end
        end
    end

    return best
end

local function GetSeasonProgressSimulation()
    if not CM or type(CM.GetProfileSettingSafe) ~= "function" then
        return false, nil, nil
    end

    local enabled = CM:GetProfileSettingSafe("developer.testing.mythicPlus.summarySimulation.enabled", false)
    if not enabled then
        return false, nil, nil
    end

    local simScore = tonumber(CM:GetProfileSettingSafe("developer.testing.mythicPlus.summarySimulation.score", 0)) or 0
    if simScore < 0 then simScore = 0 end

    local obtainedByScore = {
        [2000] = CM:GetProfileSettingSafe("developer.testing.mythicPlus.summarySimulation.obtained2000", false) == true,
        [2500] = CM:GetProfileSettingSafe("developer.testing.mythicPlus.summarySimulation.obtained2500", false) == true,
        [3000] = CM:GetProfileSettingSafe("developer.testing.mythicPlus.summarySimulation.obtained3000", false) == true,
    }

    return true, simScore, obtainedByScore
end

-- Season reward mapping is intentionally empty by default.
-- If you want markers to show real reward icons/links, populate this per-season.
-- Shape: SEASON_REWARDS_BY_SEASON[seasonID][scoreTarget] = { achievementID = number|nil, itemID = number|nil }
local SEASON_REWARDS_BY_SEASON = {}

-- Manual fallback rewards (useful if you just want to hardcode the current season's rewards).
-- Fill in `itemID` (and/or `achievementID`) for the score targets you care about.
-- Example:
--   [2000] = { itemID = 123456 },
-- Note: if both are nil, the UI will show a placeholder icon.
local MANUAL_REWARDS_BY_SCORE = {
    [2000] = { itemID = 248248, achievementID = 41973 },
    [2500] = { itemID = 246737, achievementID = 42171 },
    [3000] = { itemID = 247822, achievementID = 42172 },
}

local function GetCurrentMythicPlusSeasonID()
    local C_MythicPlus = _G.C_MythicPlus
    if C_MythicPlus and type(C_MythicPlus.GetCurrentSeason) == "function" then
        local ok, seasonID = pcall(C_MythicPlus.GetCurrentSeason)
        if ok then
            seasonID = tonumber(seasonID)
            if seasonID then return seasonID end
        end
    end
    return nil
end

local function GetAchievementInfoSafe(achievementID)
    achievementID = tonumber(achievementID)
    if not achievementID then return nil, nil end

    local name
    local description
    if type(_G.GetAchievementInfo) == "function" then
        local ok, a1, a2 = pcall(_G.GetAchievementInfo, achievementID)
        if ok then
            name = a1
            description = a2
        end
    end

    local rewardText
    if type(_G.GetAchievementReward) == "function" then
        local ok, text = pcall(_G.GetAchievementReward, achievementID)
        if ok then rewardText = text end
    end

    -- Prefer explicit reward text; fall back to description.
    return name, rewardText or description
end

local function GetItemRewardPresentationSafe(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil, nil end

    local icon
    local link
    if _G.C_Item then
        if type(_G.C_Item.GetItemIconByID) == "function" then
            icon = _G.C_Item.GetItemIconByID(itemID)
        end
        if type(_G.C_Item.GetItemLinkByID) == "function" then
            link = _G.C_Item.GetItemLinkByID(itemID)
        end
    end
    return icon, link
end

local function GetAchievementRewardPresentationSafe(achievementID)
    achievementID = tonumber(achievementID)
    if not achievementID then return nil, nil end

    local icon
    local link
    if type(_G.GetAchievementInfo) == "function" then
        local ok, _, _, _, _, _, _, _, _, tex = pcall(_G.GetAchievementInfo, achievementID)
        if ok then icon = tex end
    end
    if type(_G.GetAchievementLink) == "function" then
        local ok, aLink = pcall(_G.GetAchievementLink, achievementID)
        if ok then link = aLink end
    end
    return icon, link
end

local function ColorizeDungeonScore(score, text)
    local C_ChallengeMode = _G.C_ChallengeMode
    if C_ChallengeMode and type(C_ChallengeMode.GetDungeonScoreRarityColor) == "function" then
        local ok, a, b, c = pcall(C_ChallengeMode.GetDungeonScoreRarityColor, score)
        if ok then
            if type(a) == "table" then
                local color = a
                if type(color.WrapTextInColorCode) == "function" then
                    return color:WrapTextInColorCode(text)
                end
                if type(color.GenerateHexColor) == "function" then
                    return ("|c%s%s|r"):format(color:GenerateHexColor(), text)
                end
                if type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number" then
                    local r = math.max(0, math.min(1, color.r))
                    local g = math.max(0, math.min(1, color.g))
                    local b2 = math.max(0, math.min(1, color.b))
                    return ("|c%02x%02x%02x%02x%s|r"):format(255, r * 255, g * 255, b2 * 255, text)
                end
            elseif type(a) == "number" and type(b) == "number" and type(c) == "number" then
                local r = math.max(0, math.min(1, a))
                local g = math.max(0, math.min(1, b))
                local b2 = math.max(0, math.min(1, c))
                return ("|c%02x%02x%02x%02x%s|r"):format(255, r * 255, g * 255, b2 * 255, text)
            end
        end
    end

    -- Fallback if the API isn't available / returns an unexpected shape.
    return TT.Color(CT.TWICH.SECONDARY_ACCENT, text)
end

local function GetClassRGB(classFile)
    if RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return tonumber(c.r) or 1, tonumber(c.g) or 1, tonumber(c.b) or 1
    end
    return 1, 1, 1
end

local function ForceModelVisible(model)
    if not model then return end
    if type(model.SetIgnoreParentAlpha) == "function" then
        model:SetIgnoreParentAlpha(true)
    end
    if type(model.SetAlpha) == "function" then
        model:SetAlpha(1)
    end
    -- Some clients expose model-alpha separately from frame alpha.
    if type(model.SetModelAlpha) == "function" then
        model:SetModelAlpha(1)
    end
end

local function ApplyModelLighting(model)
    if not model or type(model.SetLight) ~= "function" then return end

    -- Prefer Blizzard default lighting; custom SetLight has been causing "washed out"/"too dark"
    -- results depending on zone/UI scale. Best-effort reset.
    pcall(function() model:SetLight(false) end)
end

local function ApplyKeyMasterCamera(model)
    if not model then return end
    pcall(function()
        if type(model.SetCamera) == "function" then
            model:SetCamera(0)
        end
        if type(model.SetPortraitZoom) == "function" then
            model:SetPortraitZoom(0.5)
        end
        if type(model.SetPosition) == "function" then
            model:SetPosition(0, 0, -0.15)
        end
        if type(model.SetFacing) == "function" then
            model:SetFacing(0.40)
        end
        if type(model.RefreshCamera) == "function" then
            model:RefreshCamera()
        end
    end)
end

local function SafeGetNumber(fn, default)
    if type(fn) ~= "function" then return default end
    local ok, v = pcall(fn)
    if not ok then return default end
    v = tonumber(v)
    if v == nil then return default end
    return v
end

local function ComputeEffectiveAlpha(region)
    if not region then return -1 end
    if type(region.GetEffectiveAlpha) == "function" then
        return SafeGetNumber(function() return region:GetEffectiveAlpha() end, -1)
    end

    local alpha = 1
    local current = region
    for _ = 1, 20 do
        if not current then break end

        if type(current.GetAlpha) == "function" then
            alpha = alpha * SafeGetNumber(function() return current:GetAlpha() end, 1)
        end

        if type(current.GetParent) ~= "function" then break end
        local ok, parent = pcall(current.GetParent, current)
        if not ok then break end
        current = parent
    end
    return alpha
end

local function RectsIntersect(aL, aR, aT, aB, bL, bR, bT, bB)
    if not (aL and aR and aT and aB and bL and bR and bT and bB) then return false end
    if aR <= bL or bR <= aL then return false end
    if aB >= bT or bB >= aT then return false end
    return true
end

local function GetRegionRect(region)
    if not region then return nil end
    if type(region.GetLeft) ~= "function" then return nil end
    local okL, l = pcall(region.GetLeft, region)
    local okR, r = pcall(region.GetRight, region)
    local okT, t = pcall(region.GetTop, region)
    local okB, b = pcall(region.GetBottom, region)
    if not (okL and okR and okT and okB) then return nil end
    if not (l and r and t and b) then return nil end
    return l, r, t, b
end

local function StrataRank(strata)
    local order = {
        BACKGROUND = 1,
        LOW = 2,
        MEDIUM = 3,
        HIGH = 4,
        DIALOG = 5,
        FULLSCREEN = 6,
        FULLSCREEN_DIALOG = 7,
        TOOLTIP = 8,
    }
    return order[tostring(strata or "") or ""] or 0
end

local function IsFrameAbove(aStrata, aLevel, bStrata, bLevel)
    local ar = StrataRank(aStrata)
    local br = StrataRank(bStrata)
    if ar ~= br then
        return ar > br
    end
    return (tonumber(aLevel) or 0) >= (tonumber(bLevel) or 0)
end

local function DebugOverlays(panel, label)
    if not SUMMARY_MODEL_DEBUG then return end
    if not Logger or type(Logger.Debug) ~= "function" then return end
    if not panel or not panel.__twichuiHeader or not panel.__twichuiModel then return end

    -- Rate limit: run once per open unless user re-opens Summary.
    panel.__twichuiOverlayDebugCount = (panel.__twichuiOverlayDebugCount or 0) + 1
    if panel.__twichuiOverlayDebugCount > 2 then
        return
    end

    local header = panel.__twichuiHeader
    local model = panel.__twichuiModel

    local mL, mR, mT, mB = GetRegionRect(model)
    if not mL then
        Logger.Debug("Summary Overlay[" .. tostring(label) .. "]: no model rect")
        return
    end

    local modelLevel = SafeGetNumber(function() return model:GetFrameLevel() end, -1)
    local modelStrata = (type(model.GetFrameStrata) == "function" and model:GetFrameStrata()) or "n/a"
    local modelAlpha = SafeGetNumber(function() return model:GetAlpha() end, -1)
    local modelEffAlpha = ComputeEffectiveAlpha(model)

    local uiAlpha = -1
    if _G.UIParent and type(_G.UIParent.GetAlpha) == "function" then
        uiAlpha = SafeGetNumber(function() return _G.UIParent:GetAlpha() end, -1)
    end

    Logger.Debug(
        ("Summary Overlay[%s]: modelRect=(%.0f,%.0f,%.0f,%.0f) modelLevel=%d strata=%s alpha=%.2f effAlpha=%.2f UIParentAlpha=%.2f")
        :format(tostring(label), mL, mR, mT, mB, modelLevel, tostring(modelStrata), modelAlpha, modelEffAlpha, uiAlpha)
    )

    -- Check parent regions (textures/fontstrings) that may be drawn above child frames.
    if type(header.GetRegions) == "function" then
        local regions = { header:GetRegions() }
        for _, reg in ipairs(regions) do
            if reg and type(reg.IsShown) == "function" and reg:IsShown() then
                local a = SafeGetNumber(function() return reg:GetAlpha() end, 1)
                if a > 0.001 then
                    local rL, rR, rT, rB = GetRegionRect(reg)
                    if rL and RectsIntersect(mL, mR, mT, mB, rL, rR, rT, rB) then
                        local drawLayer = (type(reg.GetDrawLayer) == "function" and reg:GetDrawLayer()) or "n/a"
                        local blend = (type(reg.GetBlendMode) == "function" and reg:GetBlendMode()) or "n/a"
                        local vertexA = "n/a"
                        if reg.GetObjectType and reg:GetObjectType() == "Texture" and type(reg.GetVertexColor) == "function" then
                            local ok, _, _, _, aV = pcall(reg.GetVertexColor, reg)
                            if ok then
                                vertexA = string.format("%.2f", tonumber(aV) or 0)
                            end
                        end
                        Logger.Debug(
                            ("Summary Overlay[%s]: header region overlap type=%s layer=%s blend=%s alpha=%.2f vAlpha=%s effAlpha=%.2f rect=(%.0f,%.0f,%.0f,%.0f)")
                            :format(tostring(label), tostring(reg:GetObjectType()), tostring(drawLayer), tostring(blend),
                                a,
                                tostring(vertexA), ComputeEffectiveAlpha(reg), rL, rR, rT, rB)
                        )
                    end
                end
            end
        end
    end

    -- Check sibling child frames over/near the model.
    if type(header.GetChildren) == "function" then
        local children = { header:GetChildren() }
        for _, child in ipairs(children) do
            if child and child ~= model and type(child.IsShown) == "function" and child:IsShown() then
                local cL, cR, cT, cB = GetRegionRect(child)
                if cL and RectsIntersect(mL, mR, mT, mB, cL, cR, cT, cB) then
                    local cAlpha = SafeGetNumber(function() return child:GetAlpha() end, 1)
                    if cAlpha > 0.001 then
                        local cLevel = SafeGetNumber(function() return child:GetFrameLevel() end, -1)
                        local cStrata = (type(child.GetFrameStrata) == "function" and child:GetFrameStrata()) or "n/a"
                        local name = (type(child.GetName) == "function" and child:GetName()) or "<unnamed>"
                        local above = IsFrameAbove(cStrata, cLevel, modelStrata, modelLevel)
                        if above then
                            local dbgName = (child.__twichuiDebugName and tostring(child.__twichuiDebugName)) or nil
                            Logger.Debug(
                                ("Summary Overlay[%s]: child overlap name=%s dbg=%s type=%s level=%d strata=%s aboveModel=%s alpha=%.2f effAlpha=%.2f rect=(%.0f,%.0f,%.0f,%.0f)")
                                :format(tostring(label), tostring(name), dbgName or "<nil>",
                                    tostring(child:GetObjectType()), cLevel, tostring(cStrata),
                                    tostring(above), cAlpha, ComputeEffectiveAlpha(child), cL, cR, cT, cB)
                            )
                        end
                    end
                end
            end
        end
    end
end

---@param panel TwichUI_MythicPlus_SummaryPanel
---@param label string
local function DebugModel(panel, label)
    if not SUMMARY_MODEL_DEBUG then return end
    if not Logger or type(Logger.Debug) ~= "function" then return end
    if not panel or not panel.__twichuiModel then return end

    -- Prevent chat spam: only print the first time per session unless explicitly re-opened.
    panel.__twichuiDebugCount = (panel.__twichuiDebugCount or 0) + 1
    if panel.__twichuiDebugCount > 6 then
        return
    end

    local model = panel.__twichuiModel
    local frameAlpha = SafeGetNumber(function() return model:GetAlpha() end, -1)
    local effectiveAlpha = ComputeEffectiveAlpha(model)
    local modelAlpha = SafeGetNumber(function() return model:GetModelAlpha() end, -1)
    local ignoreParentAlpha = "n/a"
    if type(model.GetIgnoreParentAlpha) == "function" then
        local ok, v = pcall(model.GetIgnoreParentAlpha, model)
        if ok then ignoreParentAlpha = tostring(v) end
    end

    local parentEffectiveAlpha = -1
    if panel.__twichuiHeader and type(panel.__twichuiHeader.GetEffectiveAlpha) == "function" then
        parentEffectiveAlpha = SafeGetNumber(function() return panel.__twichuiHeader:GetEffectiveAlpha() end, -1)
    end

    local windowAlpha = nil
    if CM and MythicPlusModule and MythicPlusModule.CONFIGURATION and MythicPlusModule.CONFIGURATION.MAIN_WINDOW_ALPHA then
        windowAlpha = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_ALPHA)
    end

    local stealth = (type(IsStealthed) == "function" and IsStealthed()) and "true" or "false"
    local visible = (type(UnitIsVisible) == "function" and UnitIsVisible("player")) and "true" or "false"

    local loaded = "n/a"
    if type(model.IsLoaded) == "function" then
        local ok, v = pcall(model.IsLoaded, model)
        if ok then loaded = tostring(v) end
    end

    local geoReady = "n/a"
    if type(model.IsGeoReady) == "function" then
        local ok, v = pcall(model.IsGeoReady, model)
        if ok then geoReady = tostring(v) end
    end

    local path = "n/a"
    if type(model.GetModelPath) == "function" then
        local ok, v = pcall(model.GetModelPath, model)
        if ok then path = tostring(v) end
    end

    local sceneShown = "n/a"
    local camPos = "n/a"
    local sceneAlpha = "n/a"
    local sceneEffAlpha = "n/a"

    local actorScale = "n/a"
    if type(model.GetScale) == "function" then
        actorScale = string.format("%.2f", SafeGetNumber(function() return model:GetScale() end, -1))
    end

    local actorPos = "n/a"
    if type(model.GetPosition) == "function" then
        local ok, x, y, z = pcall(model.GetPosition, model)
        if ok then
            actorPos = string.format("(%.2f,%.2f,%.2f)", tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
        end
    end

    local bbox = "n/a"
    if type(model.GetActiveBoundingBox) == "function" then
        local ok, minX, maxX, minY, maxY, minZ, maxZ = pcall(model.GetActiveBoundingBox, model)
        if ok then
            bbox = string.format("x(%.2f..%.2f) y(%.2f..%.2f) z(%.2f..%.2f)",
                tonumber(minX) or 0, tonumber(maxX) or 0,
                tonumber(minY) or 0, tonumber(maxY) or 0,
                tonumber(minZ) or 0, tonumber(maxZ) or 0
            )
        end
    end

    Logger.Debug(
        ("Summary Model[%s]: frameAlpha=%.2f effectiveAlpha=%.2f modelAlpha=%.2f ignoreParentAlpha=%s parentEffAlpha=%.2f windowAlpha=%s stealthed=%s unitVisible=%s loaded=%s geoReady=%s path=%s sceneShown=%s sceneAlpha=%s sceneEffAlpha=%s cam=%s scale=%s pos=%s bbox=%s")
        :format(tostring(label), frameAlpha, effectiveAlpha, modelAlpha, tostring(ignoreParentAlpha),
            parentEffectiveAlpha,
            windowAlpha == nil and "<nil>" or tostring(windowAlpha), stealth, visible, loaded, geoReady, path, sceneShown,
            sceneAlpha, sceneEffAlpha, camPos, actorScale, actorPos, bbox)
    )

    -- Only run the overlay scan on the first couple logs.
    if panel.__twichuiDebugCount <= 2 then
        DebugOverlays(panel, label)
    end
end

local function ForcePanelVisible(panel)
    if not panel then return end

    -- Panels are shown with a fade-in animation by the window manager (alpha starts at 0).
    -- Ensure Summary content is readable immediately.
    if panel.FadeInGroup and type(panel.FadeInGroup.Stop) == "function" then
        panel.FadeInGroup:Stop()
    end
    if panel.FadeOutGroup and type(panel.FadeOutGroup.Stop) == "function" then
        panel.FadeOutGroup:Stop()
    end
    if type(panel.SetAlpha) == "function" then
        panel:SetAlpha(1)
    end

    if panel.__twichuiHeader then
        if type(panel.__twichuiHeader.SetIgnoreParentAlpha) == "function" then
            panel.__twichuiHeader:SetIgnoreParentAlpha(true)
        end
        if type(panel.__twichuiHeader.SetAlpha) == "function" then
            panel.__twichuiHeader:SetAlpha(1)
        end
    end
end

--- @class MythicPlusSummarySubmodule
local Summary = MythicPlusModule.Summary or {}
MythicPlusModule.Summary = Summary

---@param panel Frame
function Summary:Refresh(panel)
    ---@cast panel TwichUI_MythicPlus_SummaryPanel
    if not panel or not panel.__twichuiHeader then return end

    local name = UnitName("player") or "Player"
    local className, classFile = UnitClass("player")
    className = className or "Unknown"
    classFile = classFile or "PRIEST"

    do
        ---@type Texture|nil
        local tex = panel.__twichuiHeaderClassAccent
        if tex then
            local r, g, b = GetClassRGB(classFile)
            -- Prefer SetGradient with Color objects when available.
            if type(tex.SetGradient) == "function" and type(CreateColor) == "function" then
                -- Client appears to interpret this gradient opposite of expected; keep bottom=class, top=transparent.
                tex:SetGradient("VERTICAL", CreateColor(r, g, b, 1), CreateColor(0, 0, 0, 0))
            elseif type(tex.SetGradientAlpha) == "function" then
                -- Fallback if SetGradient isn't available.
                tex:SetGradientAlpha("VERTICAL", r, g, b, 1.0, r, g, b, 0.0)
            elseif type(tex.SetColorTexture) == "function" then
                tex:SetColorTexture(r, g, b, 1.0)
            end
        end
    end

    if panel.__twichuiNameText then
        panel.__twichuiNameText:SetText(TT.ColorByClass(classFile, name))
    end
    if panel.__twichuiClassText then
        panel.__twichuiClassText:SetText(TT.Color(CT.TWICH.TEXT_MUTED, className))
    end

    local score = GetMythicPlusScore()
    if panel.__twichuiScoreValue then
        panel.__twichuiScoreValue:SetText(ColorizeDungeonScore(score, string.format("%d", score)))
    end

    do
        local bar = panel.__twichuiSeasonBar
        if bar and type(bar.SetValue) == "function" then
            local simEnabled, simScore, simObtained = GetSeasonProgressSimulation()
            local seasonScore = simEnabled and simScore or score

            local maxScore = 3000
            if type(bar.SetMinMaxValues) == "function" then
                bar:SetMinMaxValues(0, maxScore)
            end

            local clamped = seasonScore
            if clamped < 0 then clamped = 0 end
            if clamped > maxScore then clamped = maxScore end
            bar:SetValue(clamped)

            if type(bar.SetStatusBarColor) == "function" then
                local r, g, b = HexToRGB(CT.TWICH.SECONDARY_ACCENT)
                bar:SetStatusBarColor(r, g, b, 1)
            end

            if panel.__twichuiSeasonScoreText then
                local nextTarget = GetNextRewardTarget(seasonScore, panel.__twichuiSeasonMarkers, simObtained)
                if nextTarget then
                    local remaining = nextTarget - seasonScore
                    if remaining < 0 then remaining = 0 end
                    panel.__twichuiSeasonScoreText:SetText(string.format("%d to next reward", remaining))
                else
                    panel.__twichuiSeasonScoreText:SetText("All rewards earned")
                end
            end

            local markers = panel.__twichuiSeasonMarkers
            if type(markers) == "table" and type(bar.GetWidth) == "function" then
                local seasonID = GetCurrentMythicPlusSeasonID()
                local seasonRewards = seasonID and SEASON_REWARDS_BY_SEASON[seasonID] or nil
                if seasonRewards == nil then
                    seasonRewards = MANUAL_REWARDS_BY_SCORE
                end
                local w = bar:GetWidth() or 0
                if w > 0 then
                    for _, m in ipairs(markers) do
                        if m and m.__twichuiScoreTarget then
                            local pct = m.__twichuiScoreTarget / maxScore
                            local x = math.floor((w * pct) + 0.5)

                            -- Keep the marker button (icon+label) within the bar bounds.
                            -- The rightmost (3,000) marker otherwise centers on the bar edge and hangs off.
                            local markerW = (type(m.GetWidth) == "function" and m:GetWidth()) or 44
                            local halfMarkerW = math.max(1, math.floor((markerW / 2) + 0.5))
                            local markerX = x
                            if markerX < halfMarkerW then
                                markerX = halfMarkerW
                            elseif markerX > (w - halfMarkerW) then
                                markerX = w - halfMarkerW
                            end

                            -- Keep the thin marker line on/inside the bar.
                            local lineX = x
                            if lineX < 1 then lineX = 1 end
                            if lineX > (w - 1) then lineX = w - 1 end
                            m:ClearAllPoints()
                            m:SetPoint("BOTTOM", bar, "TOPLEFT", markerX, 0)

                            if m.__twichuiMarkerLine then
                                local line = m.__twichuiMarkerLine
                                line:ClearAllPoints()
                                line:SetPoint("CENTER", bar, "LEFT", lineX, 1)
                                local barH = (type(bar.GetHeight) == "function" and bar:GetHeight()) or 26
                                line:SetSize(2, barH + 10)
                            end

                            if m.__twichuiLabel then
                                m.__twichuiLabel:ClearAllPoints()
                                m.__twichuiLabel:SetPoint("CENTER", bar, "LEFT", markerX, 1)
                            end

                            -- Optional: attach Blizzard achievement info for the current season.
                            local ach
                            local itemID
                            if seasonRewards and type(seasonRewards) == "table" then
                                local entry = seasonRewards[m.__twichuiScoreTarget]
                                if type(entry) == "table" then
                                    ach = entry.achievementID
                                    itemID = entry.itemID
                                end
                            end
                            m.__twichuiAchievementID = ach
                            if ach then
                                local achName, rewardText = GetAchievementInfoSafe(ach)
                                m.__twichuiAchievementName = achName
                                m.__twichuiAchievementRewardText = rewardText
                            else
                                m.__twichuiAchievementName = nil
                                m.__twichuiAchievementRewardText = nil
                            end

                            m.__twichuiRewardItemID = tonumber(itemID)
                            do
                                local rewardIcon, rewardLink
                                if m.__twichuiRewardItemID then
                                    if _G.C_Item and type(_G.C_Item.RequestLoadItemDataByID) == "function" then
                                        _G.C_Item.RequestLoadItemDataByID(m.__twichuiRewardItemID)
                                    end
                                    rewardIcon, rewardLink = GetItemRewardPresentationSafe(m.__twichuiRewardItemID)
                                elseif ach then
                                    rewardIcon, rewardLink = GetAchievementRewardPresentationSafe(ach)
                                end

                                if m.__twichuiRewardItemID then
                                    local itemLink
                                    if _G.C_Item and type(_G.C_Item.GetItemLinkByID) == "function" then
                                        itemLink = _G.C_Item.GetItemLinkByID(m.__twichuiRewardItemID)
                                    end
                                    if itemLink then
                                        rewardLink = itemLink
                                    end
                                end

                                m.__twichuiRewardIcon = rewardIcon
                                m.__twichuiRewardLink = rewardLink
                                if m.__twichuiRewardIconTex and rewardIcon then
                                    m.__twichuiRewardIconTex:SetTexture(rewardIcon)
                                    m.__twichuiRewardIconTex:Show()
                                    if m.__twichuiRewardIconFrameTex then
                                        m.__twichuiRewardIconFrameTex:Show()
                                    end
                                elseif m.__twichuiRewardIconTex then
                                    -- If we don't know the reward for this season yet, keep the UI stable.
                                    -- Show a placeholder icon instead of hiding the marker.
                                    m.__twichuiRewardIconTex:SetTexture(DEFAULT_REWARD_ICON)
                                    m.__twichuiRewardIconTex:Show()
                                    if m.__twichuiRewardIconFrameTex then
                                        m.__twichuiRewardIconFrameTex:Show()
                                    end
                                end
                            end

                            -- Apply simulated obtained state (developer testing) with minimal UI impact.
                            if simEnabled and type(simObtained) == "table" then
                                m.__twichuiIsObtained = simObtained[m.__twichuiScoreTarget] == true
                            else
                                m.__twichuiIsObtained = (seasonScore >= (tonumber(m.__twichuiScoreTarget) or 0))
                            end

                            if m.__twichuiRewardIconTex then
                                if type(m.__twichuiRewardIconTex.SetDesaturated) == "function" then
                                    m.__twichuiRewardIconTex:SetDesaturated(not m.__twichuiIsObtained)
                                end
                                if type(m.__twichuiRewardIconTex.SetAlpha) == "function" then
                                    m.__twichuiRewardIconTex:SetAlpha(m.__twichuiIsObtained and 1.0 or 0.6)
                                end
                            end
                            if m.__twichuiRewardIconFrameTex and type(m.__twichuiRewardIconFrameTex.SetAlpha) == "function" then
                                m.__twichuiRewardIconFrameTex:SetAlpha(m.__twichuiIsObtained and 1.0 or 0.6)
                            end

                            -- Make completed rewards pop a bit more: accent frame + brighter marker line.
                            if m.__twichuiRewardIconFrameTex and type(m.__twichuiRewardIconFrameTex.SetVertexColor) == "function" then
                                if m.__twichuiIsObtained then
                                    local rr, rg, rb = HexToRGB(CT.TWICH.SECONDARY_ACCENT)
                                    m.__twichuiRewardIconFrameTex:SetVertexColor(rr, rg, rb, 1.0)
                                else
                                    m.__twichuiRewardIconFrameTex:SetVertexColor(1, 1, 1, 1)
                                end
                            end
                            if m.__twichuiMarkerLine and type(m.__twichuiMarkerLine.SetColorTexture) == "function" then
                                if m.__twichuiIsObtained then
                                    local rr, rg, rb = HexToRGB(CT.TWICH.SECONDARY_ACCENT)
                                    m.__twichuiMarkerLine:SetColorTexture(rr, rg, rb, 0.95)
                                else
                                    local rr, rg, rb = HexToRGB(CT.TWICH.TEXT_MUTED)
                                    m.__twichuiMarkerLine:SetColorTexture(rr, rg, rb, 0.75)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    do
        local buttons = panel.__twichuiAffixButtons
        if type(buttons) == "table" then
            local affixes = GetCurrentWeeklyAffixes()
            local fallbackLevels = { 2, 4, 7, 10 }

            -- Ensure we can sort by keystone level even if the API doesn't provide it.
            for i, entry in ipairs(affixes) do
                if type(entry) == "table" and type(entry.level) ~= "number" then
                    entry.level = fallbackLevels[i]
                end
            end

            table.sort(affixes, function(a, b)
                local la = (type(a) == "table" and tonumber(a.level)) or 999
                local lb = (type(b) == "table" and tonumber(b.level)) or 999
                if la == lb then
                    local ia = (type(a) == "table" and tonumber(a.id)) or 0
                    local ib = (type(b) == "table" and tonumber(b.id)) or 0
                    return ia < ib
                end
                return la < lb
            end)

            for i = 1, #buttons do
                local btn = buttons[i]
                local affixEntry = affixes[i]
                local affixID = affixEntry and affixEntry.id
                if btn and affixID then
                    local name, desc, icon = GetAffixInfo(affixID)
                    local level = (affixEntry and affixEntry.level) or fallbackLevels[i]

                    btn.__twichuiAffixID = affixID
                    btn.__twichuiAffixName = name
                    btn.__twichuiAffixDesc = desc
                    btn.__twichuiAffixLevel = level
                    if btn.__twichuiIcon and type(btn.__twichuiIcon.SetTexture) == "function" then
                        btn.__twichuiIcon:SetTexture(icon)
                    end
                    if btn.__twichuiLevelText and level then
                        btn.__twichuiLevelText:SetText(string.format("+%d", level))
                        btn.__twichuiLevelText:Show()
                    elseif btn.__twichuiLevelText then
                        btn.__twichuiLevelText:Hide()
                    end
                    btn:Show()
                elseif btn then
                    btn.__twichuiAffixID = nil
                    btn.__twichuiAffixName = nil
                    btn.__twichuiAffixDesc = nil
                    btn.__twichuiAffixLevel = nil
                    if btn.__twichuiLevelText then
                        btn.__twichuiLevelText:Hide()
                    end
                    btn:Hide()
                end
            end
        end
    end

    local _, equippedIlvl = 0, 0
    if type(GetAverageItemLevel) == "function" then
        local ok, avg, eq = pcall(GetAverageItemLevel)
        if ok then
            equippedIlvl = tonumber(eq) or tonumber(avg) or 0
        end
    end
    if panel.__twichuiIlvlValue then
        panel.__twichuiIlvlValue:SetText(TT.Color(CT.TWICH.SECONDARY_ACCENT, string.format("%.1f", equippedIlvl)))
    end

    if panel.__twichuiModel then
        local model = panel.__twichuiModel

        -- Unit/model data can be unavailable on the very first show; clear+set is more reliable.
        if type(model.ClearModel) == "function" then
            model:ClearModel()
        end

        if type(model.Show) == "function" then
            model:Show()
        end

        if type(model.SetDesaturation) == "function" then
            pcall(function() model:SetDesaturation(0) end)
        end

        if type(model.SetUnit) ~= "function" then
            return
        end

        model:SetUnit("player")
        if type(model.Dress) == "function" then
            pcall(function() model:Dress() end)
        end
        -- Key Master style camera setup tends to produce the expected in-game lighting.
        ApplyKeyMasterCamera(model)

        ForceModelVisible(model)
        ApplyModelLighting(model)
        DebugModel(panel, "after SetUnit")

        -- Reduce distracting idle animations (e.g. shrugging) by pinning to the base idle.
        if type(model.SetAnimation) == "function" then
            model:SetAnimation(0)
        end

        -- If available, pause once geometry is ready (prevents extra idles).
        if type(model.IsGeoReady) == "function" and type(model.SetPaused) == "function" then
            local ok, ready = pcall(model.IsGeoReady, model)
            if ok and ready then
                pcall(function() model:SetPaused(true) end)
            end
        end

        -- Model loads can complete asynchronously and reset alpha; re-assert visibility shortly after.
        if C_Timer and type(C_Timer.After) == "function" then
            panel.__twichuiModelRefreshToken = (panel.__twichuiModelRefreshToken or 0) + 1
            local token = panel.__twichuiModelRefreshToken
            C_Timer.After(0, function()
                if panel and panel.__twichuiModel == model and panel.__twichuiModelRefreshToken == token then
                    ForceModelVisible(model)
                    ApplyModelLighting(model)
                    ApplyKeyMasterCamera(model)
                    if type(model.SetAnimation) == "function" then model:SetAnimation(0) end
                    if type(model.IsGeoReady) == "function" and type(model.SetPaused) == "function" then
                        local ok, ready = pcall(model.IsGeoReady, model)
                        if ok and ready then pcall(function() model:SetPaused(true) end) end
                    end
                    DebugModel(panel, "after 0s")
                end
            end)
            C_Timer.After(0.15, function()
                if panel and panel.__twichuiModel == model and panel.__twichuiModelRefreshToken == token then
                    ForceModelVisible(model)
                    ApplyModelLighting(model)
                    ApplyKeyMasterCamera(model)
                    if type(model.SetAnimation) == "function" then model:SetAnimation(0) end
                    if type(model.IsGeoReady) == "function" and type(model.SetPaused) == "function" then
                        local ok, ready = pcall(model.IsGeoReady, model)
                        if ok and ready then pcall(function() model:SetPaused(true) end) end
                    end
                    DebugModel(panel, "after 0.15s")
                end
            end)
        end
    end
end

function Summary:_EnableEvents(panel)
    ---@cast panel TwichUI_MythicPlus_SummaryPanel
    if not panel or panel.__twichuiEventsEnabled then return end
    panel.__twichuiEventsEnabled = true

    panel:SetScript("OnEvent", function()
        self:Refresh(panel)
    end)

    panel:RegisterEvent("PLAYER_ENTERING_WORLD")
    panel:RegisterEvent("UNIT_NAME_UPDATE")
    panel:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    panel:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")
    panel:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
    panel:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    panel:RegisterEvent("UNIT_MODEL_CHANGED")
    panel:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
end

---@param panel Frame
function Summary:_DisableEvents(panel)
    ---@cast panel TwichUI_MythicPlus_SummaryPanel
    if not panel or not panel.__twichuiEventsEnabled then return end
    panel.__twichuiEventsEnabled = false
    panel:UnregisterAllEvents()
    panel:SetScript("OnEvent", nil)
end

local function CreateSummaryPanel(parent)
    ---@class TwichUI_MythicPlus_SummaryPanel : Frame
    ---@field __twichuiHeader Frame
    ---@field __twichuiHeaderClassAccent Texture|nil
    ---@field __twichuiModel any
    ---@field __twichuiModelAnchor Frame|nil
    ---@field __twichuiNameText FontString
    ---@field __twichuiClassText FontString
    ---@field __twichuiScoreValue FontString
    ---@field __twichuiIlvlValue FontString
    ---@field __twichuiAffixButtons table|nil
    ---@field __twichuiSeasonBar StatusBar|nil
    ---@field __twichuiSeasonScoreText FontString|nil
    ---@field __twichuiSeasonMarkers table|nil
    ---@field __twichuiEventsEnabled boolean
    ---@field __twichuiModelRefreshToken number|nil
    ---@field __twichuiDebugCount number|nil
    ---@field __twichuiOverlayDebugCount number|nil

    ---@type TwichUI_MythicPlus_SummaryPanel
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel:Hide() -- Ensure OnShow fires when the window manager shows it

    local fontPath = GetFontPath()

    local header = CreateFrame("Frame", nil, panel)
    -- Stretch across the full content width (from the nav/tabs edge to the window edge).
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -10)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -10)
    header:SetHeight(100)
    panel.__twichuiHeader = header

    local baseStrata = (type(header.GetFrameStrata) == "function" and header:GetFrameStrata()) or "DIALOG"
    local baseLevel = header:GetFrameLevel() or 0

    -- Background on a separate low-level frame to ensure it never draws over the PlayerModel.
    local bgFrame = CreateFrame("Frame", nil, header)
    bgFrame:SetAllPoints()
    bgFrame:SetFrameStrata(baseStrata)
    bgFrame:SetFrameLevel(math.max(0, baseLevel - 2))
    bgFrame.__twichuiDebugName = "SummaryHeaderBGFrame"

    local bg = bgFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local br, bgc, bb = HexToRGB(CT.TWICH.PANEL_BG)
    bg:SetColorTexture(br, bgc, bb, 0.35)

    -- Bottom accent: class-color bar that fades upward.
    local classAccent = bgFrame:CreateTexture(nil, "BORDER")
    classAccent:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    classAccent:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    classAccent:SetHeight(30)
    -- Use a real texture so SetGradientAlpha works reliably across clients.
    classAccent:SetTexture("Interface\\Buttons\\WHITE8x8")
    classAccent:SetTexCoord(0, 1, 0, 1)
    panel.__twichuiHeaderClassAccent = classAccent

    -- Model (upper-body) via PlayerModel (matches Key Master behavior; avoids DressUpModel ghosting)
    local modelFrame = CreateFrame("PlayerModel", nil, header)
    -- Align model bottom with the header bottom accent baseline.
    modelFrame:SetPoint("TOPLEFT", header, "TOPLEFT", 8, -16)
    modelFrame:SetSize(100, 84)
    -- Use the same strata as the header (often DIALOG) so it renders above header children.
    modelFrame:SetFrameStrata(baseStrata)
    modelFrame:SetFrameLevel(baseLevel + 10)
    ForceModelVisible(modelFrame)
    ApplyModelLighting(modelFrame)
    panel.__twichuiModel = modelFrame

    modelFrame:SetScript("OnShow", function(self)
        ForceModelVisible(self)
        ApplyModelLighting(self)
        ApplyKeyMasterCamera(self)
    end)

    panel.__twichuiModelAnchor = modelFrame

    -- Text area
    local nameText = header:CreateFontString(nil, "OVERLAY")
    nameText:SetPoint("TOPLEFT", modelFrame, "TOPRIGHT", 14, -2)
    nameText:SetJustifyH("LEFT")
    nameText:SetFontObject(_G.GameFontNormalLarge)
    if fontPath and nameText.SetFont then
        nameText:SetFont(fontPath, 18, "OUTLINE")
    end
    panel.__twichuiNameText = nameText

    local ilvlLabel = header:CreateFontString(nil, "OVERLAY")
    ilvlLabel:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)
    ilvlLabel:SetJustifyH("LEFT")
    ilvlLabel:SetFontObject(_G.GameFontNormal)
    if fontPath and ilvlLabel.SetFont then
        ilvlLabel:SetFont(fontPath, 12, "OUTLINE")
    end
    do
        local label = _G.ITEM_LEVEL_ABBR or "iLvl"
        if _G.HIGHLIGHT_FONT_COLOR and type(_G.HIGHLIGHT_FONT_COLOR.WrapTextInColorCode) == "function" then
            ilvlLabel:SetText(_G.HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(label))
        else
            ilvlLabel:SetText(label)
        end
    end

    local ilvlValue = header:CreateFontString(nil, "OVERLAY")
    ilvlValue:SetPoint("LEFT", ilvlLabel, "RIGHT", 4, 0)
    ilvlValue:SetJustifyH("LEFT")
    ilvlValue:SetFontObject(_G.GameFontHighlight)
    if fontPath and ilvlValue.SetFont then
        ilvlValue:SetFont(fontPath, 12, "OUTLINE")
    end
    panel.__twichuiIlvlValue = ilvlValue

    local classText = header:CreateFontString(nil, "OVERLAY")
    classText:SetPoint("TOPLEFT", ilvlLabel, "BOTTOMLEFT", 0, -3)
    classText:SetJustifyH("LEFT")
    classText:SetFontObject(_G.GameFontNormal)
    if fontPath and classText.SetFont then
        classText:SetFont(fontPath, 12, "OUTLINE")
    end
    panel.__twichuiClassText = classText

    local scoreWrap = CreateFrame("Frame", nil, header)
    scoreWrap:SetPoint("CENTER", header, "CENTER", 0, -2)
    scoreWrap:SetSize(220, 54)

    local scoreValue = scoreWrap:CreateFontString(nil, "OVERLAY")
    scoreValue:SetPoint("TOP", scoreWrap, "TOP", 0, -2)
    scoreValue:SetJustifyH("CENTER")
    scoreValue:SetFontObject(_G.GameFontHighlightHuge or _G.GameFontHighlightLarge)
    if fontPath and scoreValue.SetFont then
        scoreValue:SetFont(fontPath, 28, "OUTLINE")
    end
    panel.__twichuiScoreValue = scoreValue

    -- Weekly affixes (right side)
    local affixWrap = CreateFrame("Frame", nil, header)
    affixWrap:SetPoint("RIGHT", header, "RIGHT", -12, 0)
    affixWrap:SetSize(130, 40)

    local affixLabel = header:CreateFontString(nil, "OVERLAY")
    affixLabel:SetPoint("BOTTOM", affixWrap, "TOP", 0, 2)
    affixLabel:SetJustifyH("CENTER")
    affixLabel:SetFontObject(_G.GameFontNormalSmall)
    if fontPath and affixLabel.SetFont then
        affixLabel:SetFont(fontPath, 11, "OUTLINE")
    end
    affixLabel:SetText(TT.Color(CT.TWICH.TEXT_MUTED, "This week's affixes"))

    panel.__twichuiAffixButtons = panel.__twichuiAffixButtons or {}
    local iconSize = 28
    local iconPad = 6
    for i = 1, 4 do
        local btn = CreateFrame("Button", nil, affixWrap)
        btn:SetSize(iconSize, iconSize)
        if i == 1 then
            btn:SetPoint("LEFT", affixWrap, "LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", panel.__twichuiAffixButtons[i - 1], "RIGHT", iconPad, 0)
        end

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.__twichuiIcon = icon

        local levelText = btn:CreateFontString(nil, "OVERLAY")
        levelText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
        levelText:SetJustifyH("RIGHT")
        levelText:SetFontObject(_G.GameFontNormalSmall)
        if fontPath and levelText.SetFont then
            levelText:SetFont(fontPath, 12, "OUTLINE")
        end
        if type(levelText.SetTextColor) == "function" then
            levelText:SetTextColor(1, 1, 1, 1)
        end
        btn.__twichuiLevelText = levelText
        levelText:Hide()

        btn:SetScript("OnEnter", function(self)
            if not _G.GameTooltip or not self.__twichuiAffixName then return end
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            _G.GameTooltip:SetText(self.__twichuiAffixName, 1, 1, 1)
            if self.__twichuiAffixLevel then
                _G.GameTooltip:AddLine(string.format("Applies at +%d", self.__twichuiAffixLevel), 1, 1, 1)
            end
            if self.__twichuiAffixDesc and self.__twichuiAffixDesc ~= "" then
                _G.GameTooltip:AddLine(self.__twichuiAffixDesc, nil, nil, nil, true)
            end
            _G.GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)

        btn:Hide()
        panel.__twichuiAffixButtons[i] = btn
    end

    -- Season progress (bottom of panel)
    do
        local season = CreateFrame("Frame", nil, panel)
        season:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 10)
        season:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 10)
        season:SetHeight(84)

        local seasonBg = season:CreateTexture(nil, "BACKGROUND")
        seasonBg:SetAllPoints()
        do
            local r, g, b = HexToRGB(CT.TWICH.PANEL_BG)
            seasonBg:SetColorTexture(r, g, b, 0.25)
        end

        local title = season:CreateFontString(nil, "OVERLAY")
        title:SetPoint("TOPLEFT", season, "TOPLEFT", 12, -8)
        title:SetJustifyH("LEFT")
        title:SetFontObject(_G.GameFontNormal)
        if fontPath and title.SetFont then
            title:SetFont(fontPath, 13, "OUTLINE")
        end
        title:SetText(TT.Color(CT.TWICH.TEXT_PRIMARY, "Season progress"))

        local bar = CreateFrame("StatusBar", nil, season)
        bar:SetPoint("BOTTOMLEFT", season, "BOTTOMLEFT", 12, 14)
        bar:SetPoint("BOTTOMRIGHT", season, "BOTTOMRIGHT", -12, 14)
        bar:SetHeight(26)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        panel.__twichuiSeasonBar = bar

        local barBg = bar:CreateTexture(nil, "BACKGROUND")
        barBg:SetAllPoints()
        do
            local r, g, b = HexToRGB(CT.TWICH.TEXT_MUTED)
            barBg:SetColorTexture(r, g, b, 0.18)
        end

        local barText = bar:CreateFontString(nil, "OVERLAY")
        barText:ClearAllPoints()
        barText:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 1)
        barText:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 1)
        barText:SetJustifyH("CENTER")
        if type(barText.SetJustifyV) == "function" then
            barText:SetJustifyV("MIDDLE")
        end
        barText:SetFontObject(_G.GameFontNormalSmall)
        if fontPath and barText.SetFont then
            barText:SetFont(fontPath, 13, "OUTLINE")
        end

        do
            local r, g, b = HexToRGB(CT.TWICH.TEXT_PRIMARY)
            if type(barText.SetTextColor) == "function" then
                barText:SetTextColor(r, g, b, 1)
            end
        end
        panel.__twichuiSeasonScoreText = barText

        panel.__twichuiSeasonMarkers = panel.__twichuiSeasonMarkers or {}
        local rewardMarkers = {
            { score = 2000, title = "2,000 rating", desc = "2,000 rating mount/achievement" },
            { score = 2500, title = "2,500 rating", desc = "2,500 rating tier visual enhance/achievement" },
            { score = 3000, title = "3,000 rating", desc = "3,000 rating mount/achievement" },
        }

        for i = 1, #rewardMarkers do
            local data = rewardMarkers[i]
            local m = panel.__twichuiSeasonMarkers[i]
            if not m then
                m = CreateFrame("Button", nil, season)
                m:SetSize(44, 54)
                if type(m.SetFrameLevel) == "function" and type(bar.GetFrameLevel) == "function" then
                    m:SetFrameLevel(bar:GetFrameLevel() + 5)
                end
                if type(m.RegisterForClicks) == "function" then
                    m:RegisterForClicks("AnyUp")
                end

                local line = m:CreateTexture(nil, "ARTWORK")
                line:SetPoint("TOP", m, "BOTTOM", 0, -6)
                line:SetSize(2, 32)
                local r, g, b = HexToRGB(CT.TWICH.TEXT_MUTED)
                line:SetColorTexture(r, g, b, 0.75)
                m.__twichuiMarkerLine = line

                local rewardIcon = m:CreateTexture(nil, "OVERLAY")
                rewardIcon:SetPoint("BOTTOM", m, "BOTTOM", 0, 12)
                rewardIcon:SetSize(28, 28)
                rewardIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                rewardIcon:SetTexture(DEFAULT_REWARD_ICON)
                rewardIcon:Show()
                m.__twichuiRewardIconTex = rewardIcon

                local rewardFrame = m:CreateTexture(nil, "ARTWORK")
                rewardFrame:SetPoint("CENTER", rewardIcon, "CENTER", 0, 0)
                rewardFrame:SetSize(40, 40)
                rewardFrame:SetTexture("Interface\\AddOns\\TwichUI\\Media\\Textures\\reward-background.tga")
                rewardFrame:Show()
                m.__twichuiRewardIconFrameTex = rewardFrame

                local label = m:CreateFontString(nil, "OVERLAY")
                label:SetPoint("TOP", rewardIcon, "BOTTOM", 0, -2)
                label:SetJustifyH("CENTER")
                label:SetFontObject(_G.GameFontNormalSmall)
                if fontPath and label.SetFont then
                    label:SetFont(fontPath, 13, "OUTLINE")
                end
                if type(label.SetTextColor) == "function" then
                    label:SetTextColor(1, 1, 1, 1)
                end
                m.__twichuiLabel = label

                m:SetScript("OnEnter", function(self)
                    do
                        local markerLine = self.__twichuiMarkerLine
                        if markerLine and type(markerLine.SetColorTexture) == "function" then
                            local rr, rg, rb = HexToRGB(CT.TWICH.SECONDARY_ACCENT)
                            markerLine:SetColorTexture(rr, rg, rb, 1.0)
                        end
                    end

                    do
                        local frameTex = self.__twichuiRewardIconFrameTex
                        if frameTex and frameTex:IsShown() and type(frameTex.SetVertexColor) == "function" then
                            local rr, rg, rb = HexToRGB(CT.TWICH.SECONDARY_ACCENT)
                            frameTex:SetVertexColor(rr, rg, rb, 1.0)
                        end
                    end

                    if not _G.GameTooltip then return end
                    _G.GameTooltip:SetOwner(self, "ANCHOR_TOP")

                    if self.__twichuiRewardItemID and _G.C_Item and type(_G.C_Item.RequestLoadItemDataByID) == "function" then
                        _G.C_Item.RequestLoadItemDataByID(self.__twichuiRewardItemID)
                        if type(_G.C_Item.GetItemLinkByID) == "function" then
                            local itemLink = _G.C_Item.GetItemLinkByID(self.__twichuiRewardItemID)
                            if itemLink then
                                self.__twichuiRewardLink = itemLink
                            end
                        end
                    end

                    if self.__twichuiRewardItemID and type(_G.GameTooltip.SetItemByID) == "function" then
                        pcall(_G.GameTooltip.SetItemByID, _G.GameTooltip, self.__twichuiRewardItemID)
                        if self.__twichuiAchievementName then
                            _G.GameTooltip:AddLine(self.__twichuiAchievementName, 1, 1, 1)
                        end
                        if self.__twichuiTitle then
                            _G.GameTooltip:AddLine(self.__twichuiTitle, 1, 1, 1)
                        end
                    elseif self.__twichuiRewardLink and type(_G.GameTooltip.SetHyperlink) == "function" then
                        pcall(_G.GameTooltip.SetHyperlink, _G.GameTooltip, self.__twichuiRewardLink)
                        if self.__twichuiAchievementName then
                            _G.GameTooltip:AddLine(self.__twichuiAchievementName, 1, 1, 1)
                        end
                        if self.__twichuiTitle then
                            _G.GameTooltip:AddLine(self.__twichuiTitle, 1, 1, 1)
                        end
                    else
                        _G.GameTooltip:SetText(self.__twichuiTitle or "Season reward", 1, 1, 1)
                        if self.__twichuiAchievementName then
                            _G.GameTooltip:AddLine(self.__twichuiAchievementName, 1, 1, 1)
                        end
                        if self.__twichuiAchievementRewardText then
                            _G.GameTooltip:AddLine(self.__twichuiAchievementRewardText, nil, nil, nil, true)
                        elseif self.__twichuiDesc then
                            _G.GameTooltip:AddLine(self.__twichuiDesc, nil, nil, nil, true)
                        end
                    end
                    _G.GameTooltip:Show()
                end)

                if type(m.EnableMouse) == "function" then
                    m:EnableMouse(true)
                end

                m:SetScript("OnClick", function(self)
                    local function InsertLinkIntoChat(chatLink)
                        if type(chatLink) ~= "string" or not chatLink:find("|H") then
                            return false
                        end

                        if type(_G.ChatEdit_InsertLink) == "function" then
                            if _G.ChatEdit_InsertLink(chatLink) then
                                return true
                            end
                        end

                        if type(_G.ChatFrame_OpenChat) == "function" then
                            _G.ChatFrame_OpenChat("")
                        end
                        if type(_G.ChatEdit_InsertLink) == "function" then
                            return _G.ChatEdit_InsertLink(chatLink) and true or false
                        end
                        return false
                    end

                    local itemID = tonumber(self.__twichuiRewardItemID)
                    local link = self.__twichuiRewardLink

                    if itemID and _G.C_Item then
                        if type(_G.C_Item.RequestLoadItemDataByID) == "function" then
                            _G.C_Item.RequestLoadItemDataByID(itemID)
                        end

                        if type(_G.C_Item.GetItemLinkByID) == "function" then
                            link = _G.C_Item.GetItemLinkByID(itemID) or link
                        end
                    end

                    -- Ctrl+Click preview (DressUp) should work even when item links aren't cached yet.
                    local wantsDressUp = false
                    if type(_G.IsModifiedClick) == "function" and _G.IsModifiedClick("DRESSUP") then
                        wantsDressUp = true
                    elseif type(_G.IsControlKeyDown) == "function" and _G.IsControlKeyDown() then
                        wantsDressUp = true
                    end

                    if wantsDressUp then
                        local function PreviewNow(id, hyperlink)
                            id = tonumber(id)

                            -- Mount items: resolve to mountID and preview immediately.
                            if id and _G.C_MountJournal and type(_G.C_MountJournal.GetMountFromItem) == "function" then
                                local ok, mountID = pcall(_G.C_MountJournal.GetMountFromItem, id)
                                mountID = ok and tonumber(mountID) or nil
                                if mountID and mountID > 0 then
                                    if type(_G.DressUpMount) == "function" then
                                        pcall(_G.DressUpMount, mountID)
                                        return true
                                    end
                                end
                            end

                            -- Regular items: need a real hyperlink to reliably preview.
                            if type(_G.DressUpItemLink) == "function" and type(hyperlink) == "string" and hyperlink:find("|H") then
                                pcall(_G.DressUpItemLink, hyperlink)
                                return true
                            end

                            return false
                        end

                        if PreviewNow(itemID, link) then
                            return
                        end

                        -- If item link isn't cached yet, retry briefly while item data loads.
                        if itemID and _G.C_Timer and type(_G.C_Timer.After) == "function" then
                            local attempts = 0
                            local function tryDressUp()
                                attempts = attempts + 1
                                if not self or (type(self.IsShown) == "function" and not self:IsShown()) then return end

                                local liveLink = self.__twichuiRewardLink
                                if _G.C_Item and type(_G.C_Item.GetItemLinkByID) == "function" then
                                    liveLink = _G.C_Item.GetItemLinkByID(itemID) or liveLink
                                end
                                if type(liveLink) == "string" and liveLink:find("|H") then
                                    self.__twichuiRewardLink = liveLink
                                end

                                if PreviewNow(itemID, liveLink) then
                                    return
                                end

                                if attempts < 8 then
                                    _G.C_Timer.After(0.1, tryDressUp)
                                end
                            end
                            tryDressUp()
                            return
                        end

                        return
                    end

                    if type(link) == "string" and link:find("|H") then
                        self.__twichuiRewardLink = link
                    end

                    -- If Blizzard can handle this modified click (chat-link, dressup, etc), let it.
                    if type(_G.HandleModifiedItemClick) == "function" and type(link) == "string" and link:find("|H") then
                        if _G.HandleModifiedItemClick(link) then
                            return
                        end
                    end

                    -- Make Shift+Click reliably insert into chat.
                    if type(_G.IsModifiedClick) == "function" and _G.IsModifiedClick("CHATLINK") then
                        -- If we don't have a real hyperlink yet, retry briefly while item data loads.
                        if (type(link) ~= "string" or not link:find("|H")) and itemID and _G.C_Item
                            and type(_G.C_Item.GetItemLinkByID) == "function" and _G.C_Timer
                            and type(_G.C_Timer.After) == "function" then
                            local attempts = 0
                            local function tryInsert()
                                attempts = attempts + 1
                                if not self or (type(self.IsShown) == "function" and not self:IsShown()) then return end

                                local liveLink = _G.C_Item.GetItemLinkByID(itemID) or self.__twichuiRewardLink
                                local ok = InsertLinkIntoChat(liveLink)
                                if Logger and type(Logger.Debug) == "function" then
                                    self.__twichuiLinkDebugCount = (self.__twichuiLinkDebugCount or 0) + 1
                                    if self.__twichuiLinkDebugCount <= 16 then
                                        Logger.Debug(
                                            "SeasonReward ShiftClick tryInsert(" ..
                                            tostring(attempts) .. "): ok=" .. tostring(ok)
                                            .. " liveLink=" .. tostring(liveLink)
                                        )
                                    end
                                end

                                if ok then
                                    return
                                end
                                if attempts < 8 then
                                    _G.C_Timer.After(0.1, tryInsert)
                                end
                            end
                            tryInsert()
                            return
                        end

                        if Logger and type(Logger.Debug) == "function" then
                            self.__twichuiLinkDebugCount = (self.__twichuiLinkDebugCount or 0) + 1
                            if self.__twichuiLinkDebugCount <= 8 then
                                Logger.Debug(
                                    "SeasonReward ShiftClick: itemID=" .. tostring(itemID)
                                    .. " link=" .. tostring(link)
                                    .. " hasHyper=" .. tostring(type(link) == "string" and link:find("|H") ~= nil)
                                )
                            end
                        end

                        -- Item links may not be cached yet; retry briefly if needed.
                        if itemID and _G.C_Item and type(_G.C_Item.GetItemLinkByID) == "function" and _G.C_Timer and type(_G.C_Timer.After) == "function" then
                            local attempts = 0
                            local function tryInsert()
                                attempts = attempts + 1
                                if not self or (type(self.IsShown) == "function" and not self:IsShown()) then return end

                                local liveLink = _G.C_Item.GetItemLinkByID(itemID) or self.__twichuiRewardLink
                                local handled = false
                                if type(_G.HandleModifiedItemClick) == "function" then
                                    handled = _G.HandleModifiedItemClick(liveLink) and true or false
                                end
                                local ok = handled or InsertLinkIntoChat(liveLink)
                                if Logger and type(Logger.Debug) == "function" then
                                    self.__twichuiLinkDebugCount = (self.__twichuiLinkDebugCount or 0) + 1
                                    if self.__twichuiLinkDebugCount <= 16 then
                                        Logger.Debug(
                                            "SeasonReward ShiftClick tryInsert(" ..
                                            tostring(attempts) .. "): ok=" .. tostring(ok)
                                            .. " handled=" .. tostring(handled)
                                            .. " liveLink=" .. tostring(liveLink)
                                        )
                                    end
                                end

                                if ok then
                                    return
                                end
                                if attempts < 8 then
                                    _G.C_Timer.After(0.1, tryInsert)
                                end
                            end
                            tryInsert()
                            return
                        end

                        local handled = false
                        if type(_G.HandleModifiedItemClick) == "function" then
                            handled = _G.HandleModifiedItemClick(link) and true or false
                        end
                        local ok = handled or InsertLinkIntoChat(link)
                        if Logger and type(Logger.Debug) == "function" then
                            self.__twichuiLinkDebugCount = (self.__twichuiLinkDebugCount or 0) + 1
                            if self.__twichuiLinkDebugCount <= 16 then
                                Logger.Debug(
                                    "SeasonReward ShiftClick immediate: ok=" .. tostring(ok)
                                    .. " handled=" .. tostring(handled)
                                    .. " link=" .. tostring(link)
                                )
                            end
                        end
                        return
                    end

                    -- No special modifier: nothing else to do.
                end)

                m:SetScript("OnLeave", function(self)
                    do
                        local markerLine = self.__twichuiMarkerLine
                        if markerLine and type(markerLine.SetColorTexture) == "function" then
                            if self.__twichuiIsObtained then
                                local rr, rg, rb = HexToRGB(CT.TWICH.SECONDARY_ACCENT)
                                markerLine:SetColorTexture(rr, rg, rb, 0.95)
                            else
                                local rr, rg, rb = HexToRGB(CT.TWICH.TEXT_MUTED)
                                markerLine:SetColorTexture(rr, rg, rb, 0.75)
                            end
                        end
                    end

                    do
                        local frameTex = self.__twichuiRewardIconFrameTex
                        if frameTex and frameTex:IsShown() and type(frameTex.SetVertexColor) == "function" then
                            if self.__twichuiIsObtained then
                                local rr, rg, rb = HexToRGB(CT.TWICH.SECONDARY_ACCENT)
                                frameTex:SetVertexColor(rr, rg, rb, 1.0)
                            else
                                frameTex:SetVertexColor(1, 1, 1, 1)
                            end
                        end
                    end
                    if _G.GameTooltip then _G.GameTooltip:Hide() end
                end)

                panel.__twichuiSeasonMarkers[i] = m
            end

            m.__twichuiScoreTarget = data.score
            m.__twichuiTitle = data.title
            m.__twichuiDesc = data.desc
            if m.__twichuiLabel then
                m.__twichuiLabel:SetText(tostring(data.score))
            end
            m:Show()
        end
    end

    panel:SetScript("OnShow", function()
        ForcePanelVisible(panel)
        panel.__twichuiDebugCount = 0
        panel.__twichuiOverlayDebugCount = 0
        Summary:_EnableEvents(panel)
        Summary:Refresh(panel)

        -- One extra refresh shortly after first show improves reliability for score/ilvl and model visibility.
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, function() if panel and panel:IsShown() then Summary:Refresh(panel) end end)
            C_Timer.After(0.2, function() if panel and panel:IsShown() then Summary:Refresh(panel) end end)
            C_Timer.After(1.0, function() if panel and panel:IsShown() then Summary:Refresh(panel) end end)

            -- Re-assert visibility after the window manager's fade logic would normally complete.
            C_Timer.After(0.25, function() if panel and panel:IsShown() then ForcePanelVisible(panel) end end)
        end
    end)
    panel:SetScript("OnHide", function()
        Summary:_DisableEvents(panel)
    end)

    return panel
end

function Summary:Initialize()
    if self.initialized then return end
    self.initialized = true

    if MythicPlusModule.MainWindow and MythicPlusModule.MainWindow.RegisterPanel then
        MythicPlusModule.MainWindow:RegisterPanel("summary", function(parent, window)
            return CreateSummaryPanel(parent)
        end, nil, nil, { label = "Summary", order = 10 })
    end
end
