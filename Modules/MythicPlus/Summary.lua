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
