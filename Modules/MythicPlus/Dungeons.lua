local _G = _G
---@diagnostic disable: need-check-nil
---@diagnostic disable-next-line: undefined-global
local T = unpack(Twich)

--- @type MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")

--- @type ConfigurationModule
local CM = T:GetModule("Configuration")

--- @type LoggerModule
local Logger = T:GetModule("Logger")

---@type ToolsModule
local Tools = T:GetModule("Tools")
---@type ToolsUI|nil
local UI = Tools and Tools.UI

local CreateFrame = _G.CreateFrame
local GetTime = _G.GetTime
local unpackFn = _G.unpack or unpack

-- Forward-declared so helpers above the definition can call it at runtime.
---@type fun(mapId:number):string|nil, number|nil, number|string|nil, number|string|nil
local GetMapUIInfo

-- LSM is backed by ElvUI's media library when available
local LSM = T.Libs and T.Libs.LSM


---@class MythicPlusDungeonsSubmodule
---@field initialized boolean|nil
---@field Refresh fun(self:MythicPlusDungeonsSubmodule)|nil
local Dungeons = MythicPlusModule.Dungeons or {}
MythicPlusModule.Dungeons = Dungeons

local Database = MythicPlusModule.Database

local PANEL_PADDING = 10
local ROW_HEIGHT = 36

local COL_SCORE_W = 46
local COL_KEY_W = 38
local COL_RUNS_W = 46
local COL_GAP = 6

local DEFAULT_ROW_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local ASSUMED_DUNGEON_BG_ASPECT = 2.0

local PORTAL_TEXTURE = "Interface\\AddOns\\TwichUI\\Media\\Textures\\portal.tga"

-- Best-effort: find the player's dungeon teleport spell for a map by scanning the spellbook
-- for a spell whose name contains the dungeon's localized name.
local _portalSpellCache = {}

---@param mapId number|nil
---@return number|nil spellId
local function FindDungeonPortalSpellId(mapId)
    mapId = tonumber(mapId)
    if not mapId then return nil end

    if _portalSpellCache[mapId] ~= nil then
        return _portalSpellCache[mapId] or nil
    end

    local dungeonName = GetMapUIInfo and GetMapUIInfo(mapId) or nil
    if type(dungeonName) ~= "string" or dungeonName == "" then
        return nil
    end

    ---@diagnostic disable-next-line: undefined-field
    local GetNumSpellTabs = _G.GetNumSpellTabs
    ---@diagnostic disable-next-line: undefined-field
    local GetSpellTabInfo = _G.GetSpellTabInfo
    ---@diagnostic disable-next-line: undefined-field
    local GetSpellBookItemInfo = _G.GetSpellBookItemInfo
    ---@diagnostic disable-next-line: undefined-field
    local GetSpellBookItemName = _G.GetSpellBookItemName
    ---@diagnostic disable-next-line: undefined-field
    local IsPassiveSpell = _G.IsPassiveSpell

    if type(GetNumSpellTabs) ~= "function" or type(GetSpellTabInfo) ~= "function" or type(GetSpellBookItemInfo) ~= "function" then
        return nil
    end

    ---@diagnostic disable-next-line: undefined-field
    local BOOKTYPE_SPELL = _G.BOOKTYPE_SPELL or "spell"

    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        offset = tonumber(offset) or 0
        numSpells = tonumber(numSpells) or 0
        for slot = offset + 1, offset + numSpells do
            local itemType, spellId = GetSpellBookItemInfo(slot, BOOKTYPE_SPELL)
            if itemType == "SPELL" and spellId then
                local name = (type(GetSpellBookItemName) == "function") and GetSpellBookItemName(slot, BOOKTYPE_SPELL) or
                    nil
                if type(name) == "string" and name ~= "" then
                    if name:find(dungeonName, 1, true) then
                        spellId = tonumber(spellId)
                        if spellId and (type(IsPassiveSpell) ~= "function" or not IsPassiveSpell(spellId)) then
                            _portalSpellCache[mapId] = spellId
                            return spellId
                        end
                    end
                end
            end
        end
    end

    _portalSpellCache[mapId] = false
    return nil
end

---@param panel Frame
---@param mapId number|nil
local function UpdateActions(panel, mapId)
    ---@cast panel TwichUI_MythicPlus_DungeonsPanel
    if not panel or not panel.__twichuiActions then return end

    local btn = panel.__twichuiActions.portalButton
    local icon = panel.__twichuiActions.portalIcon
    local hover = panel.__twichuiActions.portalHover
    if not btn or not icon then return end

    local spellId = FindDungeonPortalSpellId(mapId)
    local unlocked = (spellId ~= nil)

    -- Secure attributes can't be changed in combat.
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        btn:Disable()
        icon:SetDesaturated(true)
        icon:SetAlpha(0.35)
        if hover then hover:Show() end
        panel.__twichuiActions.portalSpellId = spellId
        panel.__twichuiActions.portalUnlocked = unlocked
        return
    end

    btn:SetAttribute("type", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("type1", nil)
    btn:SetAttribute("spell1", nil)

    if unlocked then
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", spellId)
        btn:SetAttribute("type1", "spell")
        btn:SetAttribute("spell1", spellId)
        btn:Enable()
        icon:SetDesaturated(false)
        icon:SetAlpha(1)
        if hover then hover:Hide() end
    else
        btn:Disable()
        icon:SetDesaturated(true)
        icon:SetAlpha(0.35)
        if hover then hover:Show() end
    end

    panel.__twichuiActions.portalSpellId = spellId
    panel.__twichuiActions.portalUnlocked = unlocked
end

local function GetFontPath()
    local fontName = MythicPlusModule.CONFIGURATION
        and MythicPlusModule.CONFIGURATION.MAIN_WINDOW_FONT
        and CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_FONT)

    if LSM and fontName then
        return LSM:Fetch("font", fontName)
    end

    return nil
end

local function Clamp01(v)
    v = tonumber(v) or 0
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function GetNumberSetting(entry, fallback)
    if not entry or not CM or not CM.GetProfileSettingByConfigEntry then
        return fallback
    end
    return tonumber(CM:GetProfileSettingByConfigEntry(entry)) or fallback
end

local function GetStringSetting(entry, fallback)
    if not entry or not CM or not CM.GetProfileSettingByConfigEntry then
        return fallback
    end
    local v = CM:GetProfileSettingByConfigEntry(entry)
    if type(v) == "string" and v ~= "" then
        return v
    end
    return fallback
end

local function GetLeftColWidth()
    local cfg = MythicPlusModule.CONFIGURATION and MythicPlusModule.CONFIGURATION.DUNGEONS_LEFT_COL_WIDTH
    return math.floor(GetNumberSetting(cfg, 280) + 0.5)
end

local function GetRowTexturePath()
    local cfg = MythicPlusModule.CONFIGURATION and MythicPlusModule.CONFIGURATION.DUNGEONS_ROW_TEXTURE
    local name = GetStringSetting(cfg, "Blizzard")
    if LSM and type(LSM.Fetch) == "function" then
        local ok, path = pcall(LSM.Fetch, LSM, "statusbar", name)
        if ok and path then
            return path
        end
    end
    return DEFAULT_ROW_TEXTURE
end

---@param tex Texture|nil
local function ConfigureSmoothTexture(tex)
    if not tex then return end
    -- TwichUI (or other UI frameworks) may enable pixel snapping / nearest filtering.
    -- Force smooth filtering for large background art to avoid a blocky/pixelated look.
    if tex.SetSnapToPixelGrid then
        pcall(tex.SetSnapToPixelGrid, tex, false)
    end
    if tex.SetTexelSnappingBias then
        pcall(tex.SetTexelSnappingBias, tex, 0)
    end
    ---@diagnostic disable-next-line: undefined-field
    if tex.SetFilterMode then
        ---@diagnostic disable-next-line: undefined-field
        pcall(tex.SetFilterMode, tex, "LINEAR")
    end
end

local function GetRowAlpha()
    local cfg = MythicPlusModule.CONFIGURATION and MythicPlusModule.CONFIGURATION.DUNGEONS_ROW_ALPHA
    return Clamp01(GetNumberSetting(cfg, 0.35))
end

local function GetRowHoverAlpha()
    local cfg = MythicPlusModule.CONFIGURATION and MythicPlusModule.CONFIGURATION.DUNGEONS_ROW_HOVER_ALPHA
    return Clamp01(GetNumberSetting(cfg, 0.06))
end

local function GetRowColor()
    local cfg = MythicPlusModule.CONFIGURATION and MythicPlusModule.CONFIGURATION.DUNGEONS_ROW_COLOR
    local c = (cfg and CM and CM.GetProfileSettingByConfigEntry) and CM:GetProfileSettingByConfigEntry(cfg) or nil
    if type(c) ~= "table" then
        return { r = 1, g = 1, b = 1 }
    end
    return { r = tonumber(c.r) or 1, g = tonumber(c.g) or 1, b = tonumber(c.b) or 1 }
end

local function GetRowHoverColor()
    local cfg = MythicPlusModule.CONFIGURATION and MythicPlusModule.CONFIGURATION.DUNGEONS_ROW_HOVER_COLOR
    local c = (cfg and CM and CM.GetProfileSettingByConfigEntry) and CM:GetProfileSettingByConfigEntry(cfg) or nil
    if type(c) ~= "table" then
        return { r = 1, g = 1, b = 1 }
    end
    return { r = tonumber(c.r) or 1, g = tonumber(c.g) or 1, b = tonumber(c.b) or 1 }
end

local function GetImageZoom()
    local cfg = MythicPlusModule.CONFIGURATION and MythicPlusModule.CONFIGURATION.DUNGEONS_IMAGE_ZOOM
    local z = Clamp01(GetNumberSetting(cfg, 0.06))
    if z > 0.75 then z = 0.75 end
    return z
end

local function GetDetailsBGAlpha()
    local cfg = MythicPlusModule.CONFIGURATION and MythicPlusModule.CONFIGURATION.DUNGEONS_DETAILS_BG_ALPHA
    return Clamp01(GetNumberSetting(cfg, 0.25))
end

local function IsDebugEnabled()
    local cfg = MythicPlusModule.CONFIGURATION and MythicPlusModule.CONFIGURATION.DUNGEONS_DEBUG
    return (cfg and CM and CM.GetProfileSettingByConfigEntry) and CM:GetProfileSettingByConfigEntry(cfg) == true
end

local function Dbg(msg)
    if not IsDebugEnabled() then return end
    msg = "[TwichUI][Mythic+][Dungeons] " .. tostring(msg)
    if Logger and Logger.Debug then
        Logger.Debug(msg)
    else
        print(msg)
    end
end

---@class TwichUI_MythicPlus_CoverTexture : Texture
---@field __twichuiBaseTexCoord number[]|nil
---@field __twichuiSourceAspect number|nil
---@field __twichuiCoverContainer Frame|nil
---@field __twichuiCoverDeferred boolean|nil
---@field __twichuiAssumedAspect number|nil

---@param source any
---@return number|nil
local function GetSourceAspect(source)
    local C_Texture = _G.C_Texture
    if not C_Texture then return nil end

    -- fileID or texture path can sometimes be resolved via GetTextureInfo.
    if type(C_Texture.GetTextureInfo) == "function" then
        local ok, a, b, c = pcall(C_Texture.GetTextureInfo, source)
        if ok then
            if IsDebugEnabled() then
                if type(a) == "table" then
                    Dbg(string.format(
                        "GetTextureInfo(%s) -> table w=%s h=%s fileW=%s fileH=%s actualW=%s actualH=%s",
                        tostring(source),
                        tostring(a.width), tostring(a.height),
                        tostring(a.fileWidth), tostring(a.fileHeight),
                        tostring(a.actualWidth), tostring(a.actualHeight)
                    ))
                else
                    Dbg(string.format(
                        "GetTextureInfo(%s) -> a=%s(%s) b=%s(%s) c=%s(%s)",
                        tostring(source),
                        tostring(a), type(a),
                        tostring(b), type(b),
                        tostring(c), type(c)
                    ))
                end
            end
            if type(a) == "table" then
                local w = tonumber(a.width) or tonumber(a.fileWidth) or tonumber(a.actualWidth)
                local h = tonumber(a.height) or tonumber(a.fileHeight) or tonumber(a.actualHeight)
                if w and h and w > 0 and h > 0 then
                    return w / h
                end
            else
                local w = tonumber(a)
                local h = tonumber(b)
                if w and h and w > 0 and h > 0 then
                    return w / h
                end
                w = tonumber(b)
                h = tonumber(c)
                if w and h and w > 0 and h > 0 then
                    return w / h
                end
            end
        end
    end

    return nil
end

---@param tex Texture
---@param texture any
local function SetClampedTexture(tex, texture)
    ---@cast tex TwichUI_MythicPlus_CoverTexture
    if not tex or not tex.SetTexture then return end

    ConfigureSmoothTexture(tex)

    -- Some APIs return atlas names or sub-rect textures; if we always assume 0..1 UVs and
    -- then apply our own SetTexCoord, we can end up zoomed into a corner of the *atlas file*.
    -- Track the "base" UV range so cover/zoom stays centered on the intended image.
    local baseLeft, baseRight, baseTop, baseBottom = 0, 1, 0, 1
    local sourceAspect = nil

    if type(texture) == "string" then
        local C_Texture = _G.C_Texture
        if C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
            local info = C_Texture.GetAtlasInfo(texture)
            if type(info) == "table" and info.leftTexCoord then
                if tex.SetAtlas then
                    pcall(tex.SetAtlas, tex, texture, true)
                    local l = tonumber(info.leftTexCoord) or 0
                    local r = tonumber(info.rightTexCoord) or 1
                    local t = tonumber(info.topTexCoord) or 0
                    local b = tonumber(info.bottomTexCoord) or 1

                    -- Normalize in case a client/API returns reversed coords.
                    baseLeft = math.min(l, r)
                    baseRight = math.max(l, r)
                    baseTop = math.min(t, b)
                    baseBottom = math.max(t, b)
                    tex.__twichuiBaseTexCoord = { baseLeft, baseRight, baseTop, baseBottom }

                    local w = tonumber(info.width)
                    local h = tonumber(info.height)
                    if w and h and w > 0 and h > 0 then
                        sourceAspect = w / h
                    end

                    -- If atlas info doesn't provide dimensions, fall back to the resolved texture.
                    if not sourceAspect then
                        local fileId = nil
                        if tex.GetTextureFileID then
                            local okId, id = pcall(tex.GetTextureFileID, tex)
                            if okId then fileId = id end
                        end
                        sourceAspect = (fileId and GetSourceAspect(fileId)) or nil
                    end
                    if not sourceAspect and tex.GetTexture then
                        sourceAspect = GetSourceAspect(tex:GetTexture())
                    end

                    tex.__twichuiSourceAspect = sourceAspect

                    ConfigureSmoothTexture(tex)

                    Dbg(string.format(
                        "SetAtlas(%s) baseUV=[%.3f %.3f %.3f %.3f] aspect=%s",
                        tostring(texture), baseLeft, baseRight, baseTop, baseBottom, tostring(sourceAspect)
                    ))

                    if tex.SetHorizTile then
                        pcall(tex.SetHorizTile, tex, false)
                    end
                    if tex.SetVertTile then
                        pcall(tex.SetVertTile, tex, false)
                    end
                    return
                end
            end
        end
    end

    -- Prefer wrap-mode clamp when the runtime supports it (prevents visible tiling at edges).
    local ok = pcall(tex.SetTexture, tex, texture, "CLAMPTOBLACK", "CLAMPTOBLACK")
    if not ok then
        pcall(tex.SetTexture, tex, texture)
    end

    ConfigureSmoothTexture(tex)

    tex.__twichuiBaseTexCoord = { baseLeft, baseRight, baseTop, baseBottom }

    sourceAspect = GetSourceAspect(texture)
    if not sourceAspect then
        local fileId = nil
        if tex.GetTextureFileID then
            local okId, id = pcall(tex.GetTextureFileID, tex)
            if okId then fileId = id end
        end
        sourceAspect = (fileId and GetSourceAspect(fileId)) or nil
    end
    if not sourceAspect and tex.GetTexture then
        sourceAspect = GetSourceAspect(tex:GetTexture())
    end

    tex.__twichuiSourceAspect = sourceAspect

    Dbg(string.format(
        "SetTexture(%s) baseUV=[%.3f %.3f %.3f %.3f] aspect=%s",
        tostring(texture), baseLeft, baseRight, baseTop, baseBottom, tostring(sourceAspect)
    ))

    if tex.SetHorizTile then
        pcall(tex.SetHorizTile, tex, false)
    end
    if tex.SetVertTile then
        pcall(tex.SetVertTile, tex, false)
    end
end

---@param tex Texture
---@param zoom number
local function ApplyCoverTexCoord(tex, zoom)
    ---@cast tex TwichUI_MythicPlus_CoverTexture
    if not tex or not tex.SetTexCoord then return end

    local base = tex.__twichuiBaseTexCoord
    local baseLeft = (type(base) == "table" and tonumber(base[1])) or 0
    local baseRight = (type(base) == "table" and tonumber(base[2])) or 1
    local baseTop = (type(base) == "table" and tonumber(base[3])) or 0
    local baseBottom = (type(base) == "table" and tonumber(base[4])) or 1

    -- Normalize base coords if needed.
    if baseRight < baseLeft then baseLeft, baseRight = baseRight, baseLeft end
    if baseBottom < baseTop then baseTop, baseBottom = baseBottom, baseTop end

    local uMin, uMax, vMin, vMax = baseLeft, baseRight, baseTop, baseBottom

    local p = tex.GetParent and tex:GetParent() or nil
    local w = p and p.GetWidth and p:GetWidth() or 0
    local h = p and p.GetHeight and p:GetHeight() or 0
    if not w or not h or w <= 0 or h <= 0 then
        -- Best-effort zoom crop while we don't know sizes yet.
        local z = tonumber(zoom) or 0
        if z > 0 and z < 0.49 then
            local uRange = uMax - uMin
            local vRange = vMax - vMin
            local uInset = uRange * z
            local vInset = vRange * z
            tex:SetTexCoord(uMin + uInset, uMax - uInset, vMin + vInset, vMax - vInset)
        else
            tex:SetTexCoord(uMin, uMax, vMin, vMax)
        end
        return
    end

    local frameRatio = w / h
    local texRatio = tonumber(tex.__twichuiSourceAspect) or ASSUMED_DUNGEON_BG_ASPECT

    if frameRatio > texRatio then
        -- The frame is wider than the texture: crop vertically.
        local scale = texRatio / frameRatio
        local crop = (1 - scale) / 2
        local vRange0 = vMax - vMin
        vMin = vMin + (vRange0 * crop)
        vMax = vMax - (vRange0 * crop)
    elseif frameRatio < texRatio then
        -- The frame is taller/narrower than the texture: crop horizontally.
        local scale = frameRatio / texRatio
        local crop = (1 - scale) / 2
        local uRange0 = uMax - uMin
        uMin = uMin + (uRange0 * crop)
        uMax = uMax - (uRange0 * crop)
    end

    -- Apply zoom as a percentage of the *current* visible range.
    -- This makes the slider scale consistently regardless of the base cover-crop.
    local z = tonumber(zoom) or 0
    if z > 0 then
        if z > 0.49 then z = 0.49 end
        local uRange = uMax - uMin
        local vRange = vMax - vMin
        local uInset = uRange * z
        local vInset = vRange * z
        uMin = uMin + uInset
        uMax = uMax - uInset
        vMin = vMin + vInset
        vMax = vMax - vInset
    end

    if uMin < 0 then uMin = 0 end
    if vMin < 0 then vMin = 0 end
    if uMax > 1 then uMax = 1 end
    if vMax > 1 then vMax = 1 end

    -- If we ever end up inverted/invalid, fall back to the base UVs.
    if uMax <= uMin then uMin, uMax = baseLeft, baseRight end
    if vMax <= vMin then vMin, vMax = baseTop, baseBottom end

    tex:SetTexCoord(uMin, uMax, vMin, vMax)
end

---@param tex Texture
---@param zoom number
local function ApplyCoverLayout(tex, zoom)
    ---@cast tex TwichUI_MythicPlus_CoverTexture
    if not tex then return end

    local container = tex.__twichuiCoverContainer
        or (tex.GetParent and tex:GetParent())
        or nil

    if container and container.SetClipsChildren then
        pcall(container.SetClipsChildren, container, true)
    end

    -- Ensure we keep the texture's intended base UV mapping (e.g., atlas sub-rect).
    local base = tex.__twichuiBaseTexCoord
    local baseLeft = (type(base) == "table" and tonumber(base[1])) or 0
    local baseRight = (type(base) == "table" and tonumber(base[2])) or 1
    local baseTop = (type(base) == "table" and tonumber(base[3])) or 0
    local baseBottom = (type(base) == "table" and tonumber(base[4])) or 1
    if baseRight < baseLeft then baseLeft, baseRight = baseRight, baseLeft end
    if baseBottom < baseTop then baseTop, baseBottom = baseBottom, baseTop end
    if tex.SetTexCoord then
        pcall(tex.SetTexCoord, tex, baseLeft, baseRight, baseTop, baseBottom)
    end

    -- Always anchor centered first. When the container/frame isn't sized yet (common right after /reload
    -- or on initial panel creation), this avoids the texture defaulting to a corner.
    if tex.ClearAllPoints then
        tex:ClearAllPoints()
    end
    if tex.SetPoint and container then
        tex:SetPoint("CENTER", container, "CENTER", 0, 0)
    end

    local w = container and container.GetWidth and container:GetWidth() or 0
    local h = container and container.GetHeight and container:GetHeight() or 0
    if not w or not h or w <= 0 or h <= 0 then
        -- Layout can happen before frames are sized (especially right after /reload).
        -- Defer a single retry so we size/crop using real dimensions.
        if not tex.__twichuiCoverDeferred and _G.C_Timer and type(_G.C_Timer.After) == "function" then
            tex.__twichuiCoverDeferred = true
            _G.C_Timer.After(0, function()
                tex.__twichuiCoverDeferred = false
                ApplyCoverLayout(tex, zoom)
            end)
        end
        if IsDebugEnabled() then
            Dbg(string.format(
                "ApplyCoverLayout deferred (w/h not ready). zoom=%.3f",
                tonumber(zoom) or 0
            ))
        end
        return
    end

    local frameRatio = w / h
    local texRatio
    local ratioSource = "assumedDefault"
    if tonumber(tex.__twichuiSourceAspect) then
        texRatio = tonumber(tex.__twichuiSourceAspect)
        ratioSource = "source"
    elseif tonumber(tex.__twichuiAssumedAspect) then
        texRatio = tonumber(tex.__twichuiAssumedAspect)
        ratioSource = "assumedOverride"
    else
        texRatio = ASSUMED_DUNGEON_BG_ASPECT
    end

    -- Calculate a centered "cover" size for the texture.
    local drawW, drawH
    if frameRatio > texRatio then
        drawW = w
        drawH = w / texRatio
    else
        drawH = h
        drawW = h * texRatio
    end

    local z = Clamp01(tonumber(zoom) or 0)
    if z > 0.75 then z = 0.75 end
    -- Convert existing zoom slider into a scale multiplier.
    -- Keeps zoom centered (no corner bias) and avoids stretching.
    local scale = 1 + (z * 2.2)
    drawW = drawW * scale
    drawH = drawH * scale

    if tex.SetSize then
        pcall(tex.SetSize, tex, drawW, drawH)
    end

    if IsDebugEnabled() then
        Dbg(string.format(
            "CoverLayout w=%.1f h=%.1f frameR=%.3f texR=%s(%s) zoom=%.3f size=(%.1f,%.1f)",
            w, h, frameRatio, tostring(texRatio), ratioSource, tonumber(zoom) or 0, drawW, drawH
        ))
    end
end

---@param tex Texture
---@param zoom number
local function ApplyRowLayout(tex, zoom)
    ---@cast tex TwichUI_MythicPlus_CoverTexture
    if not tex then return end

    local container = tex.__twichuiCoverContainer
        or (tex.GetParent and tex:GetParent())
        or nil

    local h = container and container.GetHeight and container:GetHeight() or 0
    local w = container and container.GetWidth and container:GetWidth() or 0
    if h <= 0 or w <= 0 then
        if not tex.__twichuiCoverDeferred and _G.C_Timer and type(_G.C_Timer.After) == "function" then
            tex.__twichuiCoverDeferred = true
            _G.C_Timer.After(0, function()
                tex.__twichuiCoverDeferred = false
                ApplyRowLayout(tex, zoom)
            end)
        end
        return
    end

    -- Default to 16:9 if unknown.
    local aspect = tonumber(tex.__twichuiSourceAspect) or 1.777

    local z = Clamp01(tonumber(zoom) or 0)

    -- Scale factor: Increased base to 1.15 to help clip borders by default.
    -- Range: 1.15 -> ~1.9
    local scale = 1.15 + (z * 0.75)

    local drawW = w
    local drawH = (w / aspect) * scale

    -- Calculate UVs.
    local uMin, uMax, vMin, vMax = 0, 1, 0, 1
    local base = tex.__twichuiBaseTexCoord
    if type(base) == "table" then
        uMin, uMax, vMin, vMax = base[1], base[2], base[3], base[4]
    end

    local uRange = uMax - uMin
    local vRange = vMax - vMin

    -- Clip edges to remove borders (User requested Left and Bottom).
    -- We clip a small percentage from the edges.
    local CROP_LEFT = 0.06
    local CROP_BOTTOM = 0.08
    -- Also clip top slightly to keep it somewhat centered vertically relative to the content
    local CROP_TOP = 0.02

    uMin = uMin + (uRange * CROP_LEFT)
    vMax = vMax - (vRange * CROP_BOTTOM)
    vMin = vMin + (vRange * CROP_TOP)

    -- Recalculate range after crop
    uRange = uMax - uMin

    -- Apply zoom/scale cropping (horizontal only, since we fit width).
    local uVisible = uRange / scale
    local uRight = uMin + uVisible

    -- Apply UVs
    pcall(tex.SetTexCoord, tex, uMin, uRight, vMin, vMax)

    if tex.ClearAllPoints then
        tex:ClearAllPoints()
    end
    if tex.SetPoint and container then
        -- Anchor Left-Center.
        tex:SetPoint("LEFT", container, "LEFT", 0, 0)
    end
    if tex.SetSize then
        pcall(tex.SetSize, tex, drawW, drawH)
    end

    -- Apply fade-to-transparent gradient.
    -- Fading to transparent BLACK (0,0,0,0) instead of white often creates a visually "stronger" fade
    -- as it darkens the mid-tones slightly while fading out.
    if tex.SetGradient and _G.CreateColor then
        local startAlpha = tex:GetAlpha() or 1
        pcall(tex.SetGradient, tex, "HORIZONTAL", _G.CreateColor(1, 1, 1, startAlpha), _G.CreateColor(0, 0, 0, 0))
    end

    if IsDebugEnabled() then
        Dbg(string.format(
            "RowLayout w=%.1f h=%.1f aspect=%.3f zoom=%.3f scale=%.3f size=(%.1f,%.1f)",
            w, h, aspect, z, scale, drawW, drawH
        ))
    end
end

---@param tex Texture
---@param zoom number
local function ApplyHeaderLayout(tex, zoom)
    ---@cast tex TwichUI_MythicPlus_CoverTexture
    if not tex then return end

    local container = tex.__twichuiCoverContainer
        or (tex.GetParent and tex:GetParent())
        or nil

    local w = container and container.GetWidth and container:GetWidth() or 0
    local h = container and container.GetHeight and container:GetHeight() or 0
    if w <= 0 or h <= 0 then
        if not tex.__twichuiCoverDeferred and _G.C_Timer and type(_G.C_Timer.After) == "function" then
            tex.__twichuiCoverDeferred = true
            _G.C_Timer.After(0, function()
                tex.__twichuiCoverDeferred = false
                ApplyHeaderLayout(tex, zoom)
            end)
        end
        return
    end

    -- Default to 16:9 to mimic row behavior.
    local aspect = tonumber(tex.__twichuiSourceAspect) or 1.777

    local z = Clamp01(tonumber(zoom) or 0)

    -- Scale factor: Increased base to 1.55 to help clip borders by default.
    -- Range: 1.55 -> ~2.3
    local scale = 1.55 + (z * 0.75)

    local drawW = w
    local drawH = (w / aspect) * scale

    -- Crop borders (Copy from ApplyRowLayout)
    local uMin, uMax, vMin, vMax = 0, 1, 0, 1
    local base = tex.__twichuiBaseTexCoord
    if type(base) == "table" then
        uMin, uMax, vMin, vMax = base[1], base[2], base[3], base[4]
    end

    local uRange = uMax - uMin
    local vRange = vMax - vMin

    local CROP_LEFT = 0.15
    local CROP_RIGHT = 0.15
    local CROP_BOTTOM = 0.25
    local CROP_TOP = 0.05

    uMin = uMin + (uRange * CROP_LEFT)
    uMax = uMax - (uRange * CROP_RIGHT)
    vMax = vMax - (vRange * CROP_BOTTOM)
    vMin = vMin + (vRange * CROP_TOP)

    uRange = uMax - uMin

    -- Apply zoom/scale cropping (horizontal only, since we fit width).
    local uVisible = uRange / scale
    local uRight = uMin + uVisible

    pcall(tex.SetTexCoord, tex, uMin, uRight, vMin, vMax)

    if tex.ClearAllPoints then
        tex:ClearAllPoints()
    end
    if tex.SetPoint and container then
        -- Anchor Left to mimic row.
        tex:SetPoint("LEFT", container, "LEFT", 0, 0)
    end
    if tex.SetSize then
        pcall(tex.SetSize, tex, drawW, drawH)
    end

    -- Apply fade-to-transparent gradient (mimic row).
    if tex.SetGradient and _G.CreateColor then
        local startAlpha = tex:GetAlpha() or 1
        -- Fade from Opaque (Left) to Transparent (Right)
        -- Using white (1,1,1) base to avoid darkening/blackening the image during fade.
        pcall(tex.SetGradient, tex, "HORIZONTAL", _G.CreateColor(1, 1, 1, startAlpha), _G.CreateColor(1, 1, 1, 0))
    end

    if IsDebugEnabled() then
        Dbg(string.format(
            "HeaderLayout w=%.1f h=%.1f aspect=%.3f drawH=%.1f UV=[%.2f,%.2f,%.2f,%.2f]",
            w, h, aspect, drawH, uMin, uMax, vMin, vMax
        ))
    end
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end

    local ok, a, b, c, d, e = pcall(fn, ...)
    if not ok then
        return nil
    end
    return a, b, c, d, e
end

---@param seconds number|nil
---@return string
local function FormatTime(seconds)
    local s = tonumber(seconds)
    if not s or s <= 0 then
        return "—"
    end
    s = math.floor(s + 0.5)
    local m = math.floor(s / 60)
    local r = s % 60
    return string.format("%d:%02d", m, r)
end

---@param mapId number
---@return string|nil name
---@return number|nil timeLimitSeconds
---@return number|string|nil texture
---@return number|string|nil backgroundTexture
GetMapUIInfo = function(mapId)
    mapId = tonumber(mapId)
    if not mapId then return nil, nil, nil, nil end

    local C_ChallengeMode = _G.C_ChallengeMode
    if not C_ChallengeMode then return nil, nil, nil, nil end

    if type(C_ChallengeMode.GetMapUIInfo) == "function" then
        local name, _, timeLimitSeconds, texture, backgroundTexture = C_ChallengeMode.GetMapUIInfo(mapId)
        if IsDebugEnabled() then
            Dbg(string.format(
                "GetMapUIInfo(%d) -> texture=%s (%s) bg=%s (%s)",
                tonumber(mapId) or -1,
                tostring(texture), type(texture),
                tostring(backgroundTexture), type(backgroundTexture)
            ))
        end
        return name, tonumber(timeLimitSeconds), texture, backgroundTexture
    end

    if type(C_ChallengeMode.GetMapInfo) == "function" then
        local info = C_ChallengeMode.GetMapInfo(mapId)
        if type(info) == "table" then
            if IsDebugEnabled() then
                Dbg(string.format(
                    "GetMapInfo(%d) -> texture=%s (%s) bg=%s (%s)",
                    tonumber(mapId) or -1,
                    tostring(info.texture), type(info.texture),
                    tostring(info.backgroundTexture), type(info.backgroundTexture)
                ))
            end
            return info.name, tonumber(info.timeLimitSeconds or info.timeLimit), info.texture, info.backgroundTexture
        end
    end

    return nil, nil, nil, nil
end

local function GetRunHistoryTable()
    local C_MythicPlus = _G.C_MythicPlus
    if not C_MythicPlus or type(C_MythicPlus.GetRunHistory) ~= "function" then
        return nil
    end

    local ok, history = pcall(C_MythicPlus.GetRunHistory)
    if ok and type(history) == "table" then
        return history
    end

    local tries = {
        { true,  true },
        { true,  false },
        { false, false },
    }
    for _, args in ipairs(tries) do
        ok, history = pcall(C_MythicPlus.GetRunHistory, unpackFn(args))
        if ok and type(history) == "table" then
            return history
        end
    end

    return nil
end

local function GetRunMapId(run)
    if type(run) ~= "table" then return nil end
    return tonumber(run.mapChallengeModeID)
        or tonumber(run.mapChallengeModeId)
        or tonumber(run.challengeModeID)
        or tonumber(run.challengeModeId)
        or tonumber(run.mapID)
        or tonumber(run.mapId)
end

local function GetRunLevel(run)
    if type(run) ~= "table" then return nil end
    return tonumber(run.level)
        or tonumber(run.keystoneLevel)
        or tonumber(run.mythicLevel)
end

local function GetRunScore(run)
    if type(run) ~= "table" then return nil end
    return tonumber(run.mapScore)
        or tonumber(run.runScore)
        or tonumber(run.score)
        or tonumber(run.mythicRating)
end

---@param mapId number
---@param runHistory table|nil
---@return number bestScore
---@return number bestLevel
---@return number attempts
local function GetDungeonStats(mapId, runHistory)
    mapId = tonumber(mapId)
    if not mapId then return 0, 0, 0 end

    local bestScore = 0
    local bestLevel = 0
    local attempts = 0

    local C_MythicPlus = _G.C_MythicPlus
    if C_MythicPlus and type(C_MythicPlus.GetSeasonBestForMap) == "function" then
        local seasonBest = SafeCall(C_MythicPlus.GetSeasonBestForMap, mapId)
        if type(seasonBest) == "table" then
            for _, run in ipairs(seasonBest) do
                local lvl = GetRunLevel(run)
                local score = GetRunScore(run)
                if lvl and lvl > bestLevel then bestLevel = lvl end
                if score and score > bestScore then bestScore = score end
            end
        end
    end

    if type(runHistory) == "table" then
        for _, run in ipairs(runHistory) do
            if GetRunMapId(run) == mapId then
                attempts = attempts + 1
                local lvl = GetRunLevel(run)
                local score = GetRunScore(run)
                if lvl and lvl > bestLevel then bestLevel = lvl end
                if score and score > bestScore then bestScore = score end
            end
        end
    end

    return bestScore, bestLevel, attempts
end

---@return number[] mapIds
local function GetCurrentSeasonMapIds()
    local mapIds = {}
    local seen = {}

    local C_MythicPlus = _G.C_MythicPlus
    if C_MythicPlus and type(C_MythicPlus.GetCurrentSeason) == "function" and type(C_MythicPlus.GetSeasonMaps) == "function" then
        local seasonId = SafeCall(C_MythicPlus.GetCurrentSeason)
        local seasonMaps = seasonId and SafeCall(C_MythicPlus.GetSeasonMaps, seasonId) or nil
        if type(seasonMaps) == "table" then
            for _, id in ipairs(seasonMaps) do
                id = tonumber(id)
                if id and id > 0 and not seen[id] then
                    seen[id] = true
                    mapIds[#mapIds + 1] = id
                end
            end
        end
    end

    if #mapIds == 0 then
        local C_ChallengeMode = _G.C_ChallengeMode
        if C_ChallengeMode and type(C_ChallengeMode.GetMapTable) == "function" then
            local tbl = SafeCall(C_ChallengeMode.GetMapTable)
            if type(tbl) == "table" then
                for _, id in ipairs(tbl) do
                    id = tonumber(id)
                    if id and id > 0 and not seen[id] then
                        seen[id] = true
                        mapIds[#mapIds + 1] = id
                    end
                end
            end
        end
    end

    if #mapIds == 0 then
        local history = GetRunHistoryTable()
        if type(history) == "table" then
            for _, run in ipairs(history) do
                local id = GetRunMapId(run)
                if id and id > 0 and not seen[id] then
                    seen[id] = true
                    mapIds[#mapIds + 1] = id
                end
            end
        end

        if C_MythicPlus and type(C_MythicPlus.GetOwnedKeystoneChallengeMapID) == "function" then
            local ownedId = SafeCall(C_MythicPlus.GetOwnedKeystoneChallengeMapID)
            ownedId = tonumber(ownedId)
            if ownedId and ownedId > 0 and not seen[ownedId] then
                seen[ownedId] = true
                mapIds[#mapIds + 1] = ownedId
            end
        end
    end

    do
        local nameCache = {}
        local function GetName(id)
            id = tonumber(id)
            if not id then return "" end
            local cached = nameCache[id]
            if cached ~= nil then
                return cached
            end
            local name = GetMapUIInfo(id)
            name = tostring(name or id)
            nameCache[id] = name
            return name
        end

        table.sort(mapIds, function(a, b)
            return GetName(a) < GetName(b)
        end)
    end

    return mapIds
end

---@class TwichUI_MythicPlus_DungeonRow : Button
---@field Name FontString
---@field NameBG TwichUI_MythicPlus_CoverTexture
---@field NameBGContainer Frame
---@field Bar Texture
---@field Hover Texture
---@field Score FontString
---@field Key FontString
---@field Runs FontString
---@field __twichuiMapId number|nil

---@class TwichUI_MythicPlus_Dungeons_TimeFrame : Frame
---@field Text FontString

---@class TwichUI_MythicPlus_DungeonsActions
---@field frame Frame
---@field portalButton Button
---@field portalIcon Texture
---@field portalHover Frame
---@field portalSpellId number|nil
---@field portalUnlocked boolean

---@class TwichUI_MythicPlus_DungeonsPanel : Frame
---@field __twichuiFontPath string|nil
---@field __twichuiRowsParent Frame|nil
---@field __twichuiRows TwichUI_MythicPlus_DungeonRow[]|nil
---@field __twichuiSelectedMapId number|nil
---@field __twichuiEmptyText FontString|nil
---@field __twichuiRetryCount number|nil
---@field __twichuiRetryPending boolean|nil
---@field __twichuiDetailsBG TwichUI_MythicPlus_CoverTexture|nil
---@field __twichuiDetailsTitle FontString|nil
---@field __twichuiTime1 TwichUI_MythicPlus_Dungeons_TimeFrame|nil
---@field __twichuiTime2 TwichUI_MythicPlus_Dungeons_TimeFrame|nil
---@field __twichuiTime3 TwichUI_MythicPlus_Dungeons_TimeFrame|nil
---@field __twichuiActions TwichUI_MythicPlus_DungeonsActions|nil
---@field __twichuiEvents Frame|nil
---@field __twichuiLastUpdate number|nil

---@param parent Frame
---@param fontPath string|nil
---@return TwichUI_MythicPlus_DungeonRow
local function CreateDungeonRow(parent, fontPath)
    ---@class TwichUI_MythicPlus_DungeonRow
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    row.Bar = row:CreateTexture(nil, "BACKGROUND")
    row.Bar:SetAllPoints(row)
    row.Bar:SetAlpha(GetRowAlpha())
    row.Bar:SetTexture(GetRowTexturePath())
    do
        local c = GetRowColor()
        if row.Bar.SetVertexColor then
            row.Bar:SetVertexColor(c.r, c.g, c.b, 1)
        end
    end

    -- Hover highlight should not cover the dungeon image (NameBG). Put it above the base bar,
    -- but below the NameBG/artwork layer.
    row.Hover = row:CreateTexture(nil, "BACKGROUND")
    if row.Hover.SetDrawLayer then
        row.Hover:SetDrawLayer("BACKGROUND", 1)
    end
    row.Hover:SetAllPoints(row)
    row.Hover:SetAlpha(GetRowHoverAlpha())
    row.Hover:SetTexture(GetRowTexturePath())
    do
        local c = GetRowHoverColor()
        if row.Hover.SetVertexColor then
            row.Hover:SetVertexColor(c.r, c.g, c.b, 1)
        end
    end
    row.Hover:Hide()
    row:SetScript("OnEnter", function(self)
        if not self.Hover then return end
        -- Re-apply the latest hover settings on-demand.
        local texturePath = GetRowTexturePath()
        local hoverAlpha = GetRowHoverAlpha()
        local hoverColor = GetRowHoverColor()

        self.Hover:SetTexture(texturePath)
        self.Hover:SetAlpha(hoverAlpha)
        if self.Hover.SetVertexColor then
            self.Hover:SetVertexColor(hoverColor.r, hoverColor.g, hoverColor.b, 1)
        end
        self.Hover:Show()
    end)
    row:SetScript("OnLeave", function(self)
        if self.Hover then self.Hover:Hide() end
    end)

    row.NameBGContainer = CreateFrame("Frame", nil, row)
    row.NameBGContainer:SetAllPoints(row)
    if row.NameBGContainer.SetClipsChildren then
        row.NameBGContainer:SetClipsChildren(true)
    end

    row.NameBG = row.NameBGContainer:CreateTexture(nil, "ARTWORK")
    row.NameBG.__twichuiCoverContainer = row.NameBGContainer
    row.NameBG:SetAlpha(0.38)
    ConfigureSmoothTexture(row.NameBG)
    if row.NameBG.SetHorizTile then
        row.NameBG:SetHorizTile(false)
    end
    if row.NameBG.SetVertTile then
        row.NameBG:SetVertTile(false)
    end
    row.NameBG:Hide()

    if not row.__twichuiCoverHooked then
        row.__twichuiCoverHooked = true
        local onSize = function(self)
            if self.NameBG and self.NameBG.IsShown and self.NameBG:IsShown() then
                ApplyRowLayout(self.NameBG, GetImageZoom())
            end
        end
        if row.HookScript then
            row:HookScript("OnSizeChanged", onSize)
        else
            row:SetScript("OnSizeChanged", onSize)
        end
    end

    -- Create a container for text to ensure it sits above the background image container.
    -- row.NameBGContainer is a child frame, so it renders on top of row's regions.
    -- We need another child frame on top of that for the text.
    row.TextContainer = CreateFrame("Frame", nil, row)
    row.TextContainer:SetAllPoints(row)
    -- Ensure it's above the BG container.
    if row.NameBGContainer.GetFrameLevel then
        row.TextContainer:SetFrameLevel(row.NameBGContainer:GetFrameLevel() + 5)
    end

    row.Name = row.TextContainer:CreateFontString(nil, "OVERLAY")
    if row.Name.SetFontObject then
        row.Name:SetFontObject(_G.GameFontHighlight)
    end
    if fontPath and row.Name.SetFont then
        row.Name:SetFont(fontPath, 12, "OUTLINE")
    end
    row.Name:SetJustifyH("LEFT")
    row.Name:SetPoint("LEFT", row.TextContainer, "LEFT", 6, 0)

    row.Runs = row.TextContainer:CreateFontString(nil, "OVERLAY")
    if row.Runs.SetFontObject then
        row.Runs:SetFontObject(_G.GameFontNormalSmall)
    end
    if fontPath and row.Runs.SetFont then
        row.Runs:SetFont(fontPath, 12, "OUTLINE")
    end
    row.Runs:SetJustifyH("RIGHT")
    row.Runs:SetPoint("RIGHT", row.TextContainer, "RIGHT", -6, 0)
    if row.Runs.SetWidth then
        row.Runs:SetWidth(COL_RUNS_W)
    end

    row.Key = row.TextContainer:CreateFontString(nil, "OVERLAY")
    if row.Key.SetFontObject then
        row.Key:SetFontObject(_G.GameFontNormalSmall)
    end
    if fontPath and row.Key.SetFont then
        row.Key:SetFont(fontPath, 12, "OUTLINE")
    end
    row.Key:SetJustifyH("RIGHT")
    row.Key:SetPoint("RIGHT", row.Runs, "LEFT", -COL_GAP, 0)
    if row.Key.SetWidth then
        row.Key:SetWidth(COL_KEY_W)
    end

    row.Score = row.TextContainer:CreateFontString(nil, "OVERLAY")
    if row.Score.SetFontObject then
        row.Score:SetFontObject(_G.GameFontNormalSmall)
    end
    if fontPath and row.Score.SetFont then
        row.Score:SetFont(fontPath, 12, "OUTLINE")
    end
    row.Score:SetJustifyH("RIGHT")
    row.Score:SetPoint("RIGHT", row.Key, "LEFT", -COL_GAP, 0)
    if row.Score.SetWidth then
        row.Score:SetWidth(COL_SCORE_W)
    end

    -- Row background image spans the full row (left-to-right) and is clipped vertically.

    row.Name:SetPoint("RIGHT", row.Score, "LEFT", -10, 0)

    return row
end

---@param seconds number|nil
---@return string
local function FormatTime(seconds)
    if not seconds then return "—" end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%d:%02d", m, s)
end

local function FormatDate(timestamp)
    if not timestamp then return "—" end
    return date("%m/%d/%Y", timestamp)
end

local function EnsureEasyMenu()
    local easyMenuFunc = rawget(_G, "EasyMenu")
    if type(easyMenuFunc) == "function" then
        return easyMenuFunc
    end

    if InCombatLockdown and InCombatLockdown() then return nil end
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_Deprecated")
    elseif UIParentLoadAddOn then
        pcall(UIParentLoadAddOn, "Blizzard_Deprecated")
    end

    return rawget(_G, "EasyMenu")
end

-- Forward declaration: ShowContextMenu() creates closures that call this.
-- If we only use `local function UpdateDetailsRuns()` below, earlier references
-- resolve to a global (nil at runtime).
local UpdateDetailsRuns

local function ShowContextMenu(runData, panel, mapId)
    if not runData then return end

    local details = string.format("%s (+%s)\nDate: %s\nScore: %s",
        runData.mapId and GetMapUIInfo(runData.mapId) or "Unknown",
        runData.level,
        FormatDate(runData.timestamp),
        runData.score or 0)

    local callback = function()
        -- Don't trust the captured `mapId` from row creation time; rows are reused.
        local selected = (panel and panel.__twichuiSelectedMapId) or mapId or (runData and runData.mapId)
        UpdateDetailsRuns(panel, selected)
    end

    if MenuUtil then
        MenuUtil.CreateContextMenu(UIParent, function(owner, root)
            root:CreateTitle("Run Options")
            root:CreateButton("|cffff0000Delete Run|r", function()
                StaticPopup_Show("TWICHUI_CONFIRM_DELETE_RUN", details, nil, { runId = runData.id, callback = callback })
            end)
            root:CreateButton("Cancel", function() end)
        end)
        return
    end

    local easyMenuFunc = EnsureEasyMenu()
    if not easyMenuFunc then return end

    local menu = {
        { text = "Run Options", isTitle = true,      notCheckable = true },
        {
            text = "|cffff0000Delete Run|r",
            notCheckable = true,
            func = function()
                StaticPopup_Show("TWICHUI_CONFIRM_DELETE_RUN", details, nil, { runId = runData.id, callback = callback })
            end
        },
        { text = "Cancel",      notCheckable = true, func = function() end }
    }

    local menuFrame = CreateFrame("Frame", "TwichUIDungeonsContextMenu", UIParent, "UIDropDownMenuTemplate")
    easyMenuFunc(menu, menuFrame, "cursor", 0, 0, "MENU")
end

UpdateDetailsRuns = function(panel, mapId)
    if not panel.__twichuiDetailsRuns then return end

    local content = panel.__twichuiDetailsRuns.content
    local rows = panel.__twichuiDetailsRuns.rows or {}
    panel.__twichuiDetailsRuns.rows = rows

    -- Clear existing
    for _, row in ipairs(rows) do row:Hide() end

    if not mapId then return end

    local Database = MythicPlusModule.Database
    if not Database then return end

    local allRuns = Database:GetRuns()
    local runs = {}
    for _, run in ipairs(allRuns) do
        if run.mapId == mapId then
            table.insert(runs, run)
        end
    end

    -- Sort
    local sortBy = panel.__twichuiDetailsRuns.sortBy or "score"
    local sortAsc = panel.__twichuiDetailsRuns.sortAsc
    if panel.__twichuiDetailsRuns.sortBy == nil then sortAsc = false end -- Default desc for score

    table.sort(runs, function(a, b)
        local vA, vB
        if sortBy == "date" then
            vA = a.timestamp
            vB = b.timestamp
        else
            vA = a[sortBy]
            vB = b[sortBy]
        end

        if vA == nil then vA = 0 end
        if vB == nil then vB = 0 end

        if vA == vB then
            return a.timestamp > b.timestamp
        end

        if sortAsc then
            return vA < vB
        else
            return vA > vB
        end
    end)

    local ROW_HEIGHT = 20
    local yOffset = 0

    for i, run in ipairs(runs) do
        local row = rows[i]
        if not row then
            row = CreateFrame("Frame", nil, content)
            row:SetHeight(ROW_HEIGHT)
            row:SetWidth(content:GetWidth())

            row.cells = {}
            -- Date
            local date = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            date:SetPoint("LEFT", row, "LEFT", 0, 0)
            date:SetWidth(80)
            date:SetJustifyH("LEFT")
            row.cells.date = date

            -- Key
            local key = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            key:SetPoint("LEFT", date, "RIGHT", 5, 0)
            key:SetWidth(40)
            key:SetJustifyH("CENTER")
            row.cells.key = key

            -- Time
            local time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            time:SetPoint("LEFT", key, "RIGHT", 5, 0)
            time:SetWidth(60)
            time:SetJustifyH("RIGHT")
            row.cells.time = time

            -- Score
            local score = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            score:SetPoint("LEFT", time, "RIGHT", 5, 0)
            score:SetWidth(50)
            score:SetJustifyH("RIGHT")
            row.cells.score = score

            -- Up
            local up = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            up:SetPoint("LEFT", score, "RIGHT", 5, 0)
            up:SetWidth(30)
            up:SetJustifyH("CENTER")
            row.cells.up = up

            -- BG
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(row)
            bg:SetColorTexture(1, 1, 1, 0.05)
            row.bg = bg

            -- Highlight
            local highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
            highlight:SetAllPoints(row)
            highlight:SetColorTexture(1, 1, 1, 0.1)
            highlight:Hide()
            row.highlight = highlight

            row:SetScript("OnEnter", function(self)
                self.highlight:Show()
            end)
            row:SetScript("OnLeave", function(self)
                self.highlight:Hide()
            end)

            row:EnableMouse(true)
            row:SetScript("OnMouseUp", function(self, button)
                if button == "RightButton" and self.runData then
                    -- Rows are reused across dungeon selections; always consult current panel state.
                    ShowContextMenu(self.runData, panel, panel.__twichuiSelectedMapId or mapId or self.runData.mapId)
                end
            end)

            rows[i] = row
        end

        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOffset)
        row:SetWidth(content:GetWidth())
        row:Show()

        row.runData = run

        row.cells.date:SetText(FormatDate(run.timestamp))
        row.cells.key:SetText("+" .. tostring(run.level))
        row.cells.time:SetText(FormatTime(run.time))
        row.cells.score:SetText(tostring(run.score or 0))

        local upgrade = run.upgrade
        row.cells.up:SetText(upgrade and ("+" .. upgrade) or "—")
        if upgrade == 3 then
            row.cells.up:SetTextColor(0.64, 0.21, 0.93)
        elseif upgrade == 2 then
            row.cells.up:SetTextColor(0, 0.44, 0.87)
        elseif upgrade == 1 then
            row.cells.up:SetTextColor(0, 1, 0)
        else
            row.cells.up:SetTextColor(0.5, 0.5, 0.5)
        end

        -- Alternating row colors
        if i % 2 == 0 then
            row.bg:SetColorTexture(1, 1, 1, 0.02)
        else
            row.bg:SetColorTexture(1, 1, 1, 0.05)
        end

        yOffset = yOffset + ROW_HEIGHT + 1
    end
end

local function UpdateDetails(panel, mapId)
    UpdateDetailsRuns(panel, mapId)
    ---@cast panel TwichUI_MythicPlus_DungeonsPanel
    mapId = tonumber(mapId)

    UpdateActions(panel, mapId)

    local name, timeLimit, texture, backgroundTexture = GetMapUIInfo(mapId)
    local bg = backgroundTexture or texture

    if panel.__twichuiDetailsTitle then
        panel.__twichuiDetailsTitle:SetText(name or "Select a dungeon")
    end

    if panel.__twichuiDetailsBG then
        if bg then
            SetClampedTexture(panel.__twichuiDetailsBG, bg)
            panel.__twichuiDetailsBG:SetAlpha(GetDetailsBGAlpha())
            ApplyHeaderLayout(panel.__twichuiDetailsBG, GetImageZoom())
            panel.__twichuiDetailsBG:Show()
        else
            panel.__twichuiDetailsBG:Hide()
        end
    end

    if panel.__twichuiTime1 then
        local t = panel.__twichuiTime1.Text or panel.__twichuiTime1
        t:SetText("+1: " .. FormatTime(timeLimit))
        if t.SetTextColor then t:SetTextColor(0, 1, 0) end
    end
    if panel.__twichuiTime2 then
        local t = panel.__twichuiTime2.Text or panel.__twichuiTime2
        t:SetText("+2: " .. FormatTime(timeLimit and (timeLimit * 0.8) or nil))
        if t.SetTextColor then t:SetTextColor(0, 0.44, 0.87) end
    end
    if panel.__twichuiTime3 then
        local t = panel.__twichuiTime3.Text or panel.__twichuiTime3
        t:SetText("+3: " .. FormatTime(timeLimit and (timeLimit * 0.6) or nil))
        if t.SetTextColor then t:SetTextColor(0.64, 0.21, 0.93) end
    end
end

---@param panel Frame
local function RefreshPanel(panel)
    ---@cast panel TwichUI_MythicPlus_DungeonsPanel
    if not panel or not panel.__twichuiRowsParent then return end

    -- Ensure we have width before rendering
    local width = panel.__twichuiRowsParent:GetWidth()

    if width <= 1 then
        C_Timer.After(0.1, function() RefreshPanel(panel) end)
        return
    end

    local mapIds = GetCurrentSeasonMapIds()

    if panel.__twichuiEmptyText then
        panel.__twichuiEmptyText:Hide()
    end

    panel.__twichuiRows = panel.__twichuiRows or {}
    local rows = panel.__twichuiRows

    local fontPath = panel.__twichuiFontPath
    local rowTexture = GetRowTexturePath()
    local rowAlpha = GetRowAlpha()
    local hoverAlpha = GetRowHoverAlpha()
    local rowColor = GetRowColor()
    local hoverColor = GetRowHoverColor()
    local zoom = GetImageZoom()

    if #mapIds == 0 then
        Logger.Debug("Dungeons:RefreshPanel - No maps found, entering retry loop")
        -- After /reload, the panel can be created after the relevant events already fired.
        -- If the season map list isn't ready yet, retry a few times.
        if not panel.__twichuiRetryPending then
            local C_Timer = _G.C_Timer
            if C_Timer and type(C_Timer.After) == "function" then
                panel.__twichuiRetryPending = true
                panel.__twichuiRetryCount = (tonumber(panel.__twichuiRetryCount) or 0) + 1
                local attempt = panel.__twichuiRetryCount
                local delay = math.min(0.2 + (attempt * 0.15), 1.25)

                Logger.Debug("Dungeons:RefreshPanel - Scheduling retry #" .. attempt .. " in " .. delay .. "s")

                C_Timer.After(delay, function()
                    if not panel or not panel.IsShown or not panel:IsShown() then return end
                    panel.__twichuiRetryPending = false
                    -- Stop retrying after a handful of attempts to avoid any runaway loops.
                    if (tonumber(panel.__twichuiRetryCount) or 0) > 10 then
                        Logger.Debug("Dungeons:RefreshPanel - Max retries reached")
                        return
                    end
                    RefreshPanel(panel)
                end)
            end
        end

        for _, row in ipairs(rows) do
            if row then row:Hide() end
        end
        if panel.__twichuiEmptyText then
            panel.__twichuiEmptyText:SetText("No dungeon data available yet")
            panel.__twichuiEmptyText:Show()
        end
        UpdateDetails(panel, nil)
        return
    end

    -- Data is present: reset retry state.
    panel.__twichuiRetryCount = 0
    panel.__twichuiRetryPending = false

    -- Gather and sort data
    local history = GetRunHistoryTable()
    local data = {}
    for _, mapId in ipairs(mapIds) do
        local name, _, texture, backgroundTexture = GetMapUIInfo(mapId)
        local bestScore, bestLevel, attempts = GetDungeonStats(mapId, history)
        table.insert(data, {
            id = mapId,
            name = name or ("Dungeon " .. tostring(mapId)),
            score = bestScore or 0,
            level = bestLevel or 0,
            runs = attempts or 0,
            bg = backgroundTexture or texture
        })
    end

    Logger.Debug("Dungeons:RefreshPanel - Processing " .. #data .. " rows")

    local sortBy = panel.__twichuiSortBy or "score"
    local sortAsc = panel.__twichuiSortAsc
    if panel.__twichuiSortBy == nil then sortAsc = false end -- Default desc

    table.sort(data, function(a, b)
        local vA = a[sortBy]
        local vB = b[sortBy]
        if vA == vB then
            return a.name < b.name
        end
        if sortAsc then
            return vA < vB
        else
            return vA > vB
        end
    end)

    for i = 1, math.max(#data, #rows) do
        local row = rows[i]
        if not row then
            row = CreateDungeonRow(panel.__twichuiRowsParent, fontPath)
            rows[i] = row
            if i == 1 then
                row:SetPoint("TOPLEFT", panel.__twichuiRowsParent, "TOPLEFT", 0, 0)
                row:SetPoint("TOPRIGHT", panel.__twichuiRowsParent, "TOPRIGHT", 0, 0)
            else
                local prev = rows[i - 1]
                if prev then
                    row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
                    row:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -2)
                else
                    row:SetPoint("TOPLEFT", panel.__twichuiRowsParent, "TOPLEFT", 0, 0)
                    row:SetPoint("TOPRIGHT", panel.__twichuiRowsParent, "TOPRIGHT", 0, 0)
                end
            end

            row:SetScript("OnClick", function(self)
                local id = self.__twichuiMapId
                panel.__twichuiSelectedMapId = id
                UpdateDetails(panel, id)
            end)
        end

        local info = data[i]
        if info then
            row.__twichuiMapId = info.id
            row.Name:SetText(info.name)

            -- Keep row styling in sync with settings.
            if row.Bar then
                row.Bar:SetTexture(rowTexture)
                row.Bar:SetAlpha(rowAlpha)
                if row.Bar.SetVertexColor then
                    row.Bar:SetVertexColor(rowColor.r, rowColor.g, rowColor.b, 1)
                end
            end
            if row.Hover then
                row.Hover:SetTexture(rowTexture)
                row.Hover:SetAlpha(hoverAlpha)
                if row.Hover.SetVertexColor then
                    row.Hover:SetVertexColor(hoverColor.r, hoverColor.g, hoverColor.b, 1)
                end
            end

            if info.bg then
                SetClampedTexture(row.NameBG, info.bg)
                ApplyRowLayout(row.NameBG, zoom)
                row.NameBG:Show()
            else
                row.NameBG:Hide()
            end

            row.Score:SetText(info.score > 0 and string.format("%d", math.floor(info.score + 0.5)) or "—")
            row.Key:SetText(info.level > 0 and ("+" .. tostring(info.level)) or "—")
            row.Runs:SetText(info.runs > 0 and tostring(info.runs) or "0")

            row:Show()
        else
            row.__twichuiMapId = nil
            row:Hide()
        end
    end

    if not panel.__twichuiSelectedMapId and data[1] then
        panel.__twichuiSelectedMapId = data[1].id
    end

    UpdateDetails(panel, panel.__twichuiSelectedMapId)
end

---@param parent Frame
---@return Frame
local function CreateDungeonsPanel(parent)
    ---@class TwichUI_MythicPlus_DungeonsPanel
    local panel = CreateFrame("Frame", nil, parent)
    panel:Hide()

    local fontPath = GetFontPath()
    panel.__twichuiFontPath = fontPath

    local left = CreateFrame("Frame", nil, panel)
    left:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, -PANEL_PADDING)
    left:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PANEL_PADDING, PANEL_PADDING)
    left:SetWidth(GetLeftColWidth())

    local right = CreateFrame("Frame", nil, panel)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", PANEL_PADDING, 0)
    right:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PANEL_PADDING, PANEL_PADDING)

    local headerContainer = CreateFrame("Frame", nil, left)
    headerContainer:SetHeight(16)
    headerContainer:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -2)
    headerContainer:SetPoint("TOPRIGHT", left, "TOPRIGHT", 0, -2)

    local function CreateHeaderButton(text, key, justify, width)
        local btn = CreateFrame("Button", nil, headerContainer)
        btn:SetHeight(16)
        if width then
            btn:SetWidth(width)
        else
            -- Auto width if not specified (will be anchored)
            btn:SetWidth(100)
        end

        local fs = btn:CreateFontString(nil, "OVERLAY")
        if fs.SetFontObject then
            fs:SetFontObject(_G.GameFontNormal)
        end
        if fontPath and fs.SetFont then
            fs:SetFont(fontPath, 12, "OUTLINE")
        end
        fs:SetText(text)
        fs:SetJustifyH(justify)
        fs:SetAllPoints(btn)
        btn.Text = fs

        btn:SetScript("OnEnter", function(self)
            if self.Text and self.Text.SetTextColor then
                self.Text:SetTextColor(1, 1, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self.Text and self.Text.SetTextColor then
                self.Text:SetTextColor(1, 0.82, 0)
            end
        end)
        btn:SetScript("OnClick", function()
            local currentSort = panel.__twichuiSortBy
            local currentAsc = panel.__twichuiSortAsc

            if currentSort == key then
                panel.__twichuiSortAsc = not currentAsc
            else
                panel.__twichuiSortBy = key
                -- Default to descending for numbers, ascending for name
                if key == "name" then
                    panel.__twichuiSortAsc = true
                else
                    panel.__twichuiSortAsc = false
                end
            end
            RefreshPanel(panel)
        end)

        return btn
    end

    local headerRuns = CreateHeaderButton("Runs", "runs", "RIGHT", COL_RUNS_W)
    headerRuns:SetPoint("RIGHT", headerContainer, "RIGHT", -6, 0)

    local headerKey = CreateHeaderButton("Key", "level", "RIGHT", COL_KEY_W)
    headerKey:SetPoint("RIGHT", headerRuns, "LEFT", -COL_GAP, 0)

    local headerScore = CreateHeaderButton("Score", "score", "RIGHT", COL_SCORE_W)
    headerScore:SetPoint("RIGHT", headerKey, "LEFT", -COL_GAP, 0)

    local headerDungeon = CreateHeaderButton("Dungeon", "name", "LEFT")
    headerDungeon:SetPoint("LEFT", headerContainer, "LEFT", 6, 0)
    headerDungeon:SetPoint("RIGHT", headerScore, "LEFT", -10, 0)

    local rowsParent = CreateFrame("Frame", nil, left)
    rowsParent:SetPoint("TOPLEFT", headerContainer, "BOTTOMLEFT", 0, -6)
    rowsParent:SetPoint("TOPRIGHT", headerContainer, "BOTTOMRIGHT", 0, -6)
    rowsParent:SetPoint("BOTTOM", left, "BOTTOM", 0, 0)

    local emptyText = left:CreateFontString(nil, "OVERLAY")
    if emptyText.SetFontObject then
        emptyText:SetFontObject(_G.GameFontDisable)
    end
    if fontPath and emptyText.SetFont then
        emptyText:SetFont(fontPath, 12, "OUTLINE")
    end
    emptyText:SetPoint("TOPLEFT", rowsParent, "TOPLEFT", 6, -6)
    emptyText:SetPoint("RIGHT", left, "RIGHT", -6, 0)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetText("Loading…")
    emptyText:Hide()

    local detailsHeader = CreateFrame("Frame", nil, right)
    detailsHeader:SetHeight(80)
    detailsHeader:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0)
    detailsHeader:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, 0)
    if detailsHeader.SetClipsChildren then
        detailsHeader:SetClipsChildren(true)
    end

    ---@type TwichUI_MythicPlus_CoverTexture
    local detailsBG = detailsHeader:CreateTexture(nil, "BACKGROUND")
    detailsBG.__twichuiCoverContainer = detailsHeader
    -- Details backgrounds are closer to "standard" dungeon splash art.
    detailsBG.__twichuiAssumedAspect = 2.0
    detailsBG:SetAlpha(GetDetailsBGAlpha())
    ConfigureSmoothTexture(detailsBG)
    if detailsBG.SetHorizTile then
        detailsBG:SetHorizTile(false)
    end
    if detailsBG.SetVertTile then
        detailsBG:SetVertTile(false)
    end
    detailsBG:Hide()

    local rightOnSize = function()
        if detailsBG and detailsBG.IsShown and detailsBG:IsShown() then
            ApplyHeaderLayout(detailsBG, GetImageZoom())
        end
    end
    if detailsHeader.HookScript then
        detailsHeader:HookScript("OnSizeChanged", rightOnSize)
    else
        detailsHeader:SetScript("OnSizeChanged", rightOnSize)
    end

    local titleBG = detailsHeader:CreateTexture(nil, "ARTWORK", nil, 2)
    titleBG:SetHeight(24)
    titleBG:SetPoint("TOPLEFT", detailsHeader, "TOPLEFT", 0, 0)
    titleBG:SetPoint("TOPRIGHT", detailsHeader, "TOPRIGHT", 0, 0)
    titleBG:SetColorTexture(0, 0, 0, 0.6)

    local detailsTitle = detailsHeader:CreateFontString(nil, "OVERLAY")
    if detailsTitle.SetFontObject then
        detailsTitle:SetFontObject(_G.GameFontHighlight)
    end
    if fontPath and detailsTitle.SetFont then
        detailsTitle:SetFont(fontPath, 14, "OUTLINE")
    end
    detailsTitle:SetPoint("CENTER", titleBG, "CENTER", 0, 0)
    detailsTitle:SetJustifyH("CENTER")
    detailsTitle:SetText("Select a dungeon")

    local function CreateTimeFrame(id)
        local f = CreateFrame("Frame", nil, detailsHeader)
        f:SetSize(80, 20)
        local fs = f:CreateFontString(nil, "OVERLAY")
        if fs.SetFontObject then fs:SetFontObject(_G.GameFontNormal) end
        if fontPath and fs.SetFont then fs:SetFont(fontPath, 12, "OUTLINE") end
        fs:SetJustifyH("CENTER")
        fs:SetAllPoints(f)
        f.Text = fs

        f:SetScript("OnEnter", function(self)
            if not _G.GameTooltip then return end
            _G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
            _G.GameTooltip:AddLine("+" .. id .. " Chest Timer")
            _G.GameTooltip:AddLine("Complete the dungeon within this time to upgrade your key by " .. id .. " level(s).",
                1, 1, 1, true)
            _G.GameTooltip:Show()
        end)
        f:SetScript("OnLeave", function(self)
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)
        return f
    end

    local time1 = CreateTimeFrame(1)
    local time2 = CreateTimeFrame(2)
    local time3 = CreateTimeFrame(3)

    -- Place times below the dungeon name/title, all visible
    time1:SetPoint("TOPLEFT", detailsHeader, "TOPLEFT", 10, -22)
    time2:SetPoint("TOP", detailsHeader, "TOP", 0, -22)
    time3:SetPoint("TOPRIGHT", detailsHeader, "TOPRIGHT", -10, -22)

    -- Actions (below header, above runs table)
    -- Portal button now in header area (detailsHeader)
    local portalButton = CreateFrame("Button", nil, detailsHeader, "SecureActionButtonTemplate")
    portalButton:SetSize(26, 26)
    -- Place portal button at the right, below the times, with some padding
    portalButton:SetPoint("BOTTOMRIGHT", detailsHeader, "BOTTOMRIGHT", -6, 6)
    portalButton:RegisterForClicks("LeftButtonUp")

    local portalIcon = portalButton:CreateTexture(nil, "ARTWORK")
    portalIcon:SetAllPoints(portalButton)
    portalIcon:SetTexture(PORTAL_TEXTURE)
    portalIcon:SetAlpha(0.35)
    portalIcon:SetDesaturated(true)

    local portalHL = portalButton:CreateTexture(nil, "HIGHLIGHT")
    portalHL:SetAllPoints(portalButton)
    portalHL:SetColorTexture(1, 1, 1, 0.12)

    portalButton:SetScript("OnEnter", function(btn)
        if not _G.GameTooltip or not _G.GameTooltip.SetOwner then return end
        _G.GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")

        local st = panel.__twichuiActions
        if st and st.portalUnlocked and st.portalSpellId then
            ---@diagnostic disable-next-line: undefined-field
            local GetSpellInfo = _G.GetSpellInfo
            local name = (type(GetSpellInfo) == "function" and GetSpellInfo(st.portalSpellId)) or "Portal"
            _G.GameTooltip:AddLine(tostring(name))
            _G.GameTooltip:AddLine("Click to teleport.", 1, 1, 1, true)
        else
            _G.GameTooltip:AddLine("Portal")
            _G.GameTooltip:AddLine("You haven't unlocked this portal yet.", 1, 1, 1, true)
        end
        _G.GameTooltip:Show()
    end)
    portalButton:SetScript("OnLeave", function()
        if _G.GameTooltip and _G.GameTooltip.Hide then
            _G.GameTooltip:Hide()
        end
    end)

    -- Tooltip support for the disabled state: disabled Buttons do not receive OnEnter/OnLeave.
    local portalHover = CreateFrame("Frame", nil, detailsHeader)
    portalHover:SetAllPoints(portalButton)
    portalHover:EnableMouse(true)
    portalHover:Hide()
    if portalHover.SetFrameLevel and portalButton.GetFrameLevel then
        portalHover:SetFrameLevel((portalButton:GetFrameLevel() or 1) + 5)
    end

    portalHover:SetScript("OnEnter", function(f)
        if not _G.GameTooltip or not _G.GameTooltip.SetOwner then return end
        _G.GameTooltip:SetOwner(f, "ANCHOR_RIGHT")

        local st = panel.__twichuiActions
        _G.GameTooltip:AddLine("Portal")
        if st and st.portalUnlocked then
            _G.GameTooltip:AddLine("Unavailable while in combat.", 1, 1, 1, true)
        else
            _G.GameTooltip:AddLine("You haven't unlocked this portal yet.", 1, 1, 1, true)
        end
        _G.GameTooltip:Show()
    end)
    portalHover:SetScript("OnLeave", function()
        if _G.GameTooltip and _G.GameTooltip.Hide then
            _G.GameTooltip:Hide()
        end
    end)

    -- Runs Table Container
    local runsContainer = CreateFrame("Frame", nil, right)
    runsContainer:SetPoint("TOPLEFT", detailsHeader, "BOTTOMLEFT", 0, -16)
    runsContainer:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)

    -- Headers
    local function CreateSortHeader(text, key, width, justify, point, relativeTo, relativePoint, x, y)
        local btn = CreateFrame("Button", nil, runsContainer)
        btn:SetSize(width, 20)
        btn:SetPoint(point, relativeTo, relativePoint, x, y)

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetText(text)
        fs:SetAllPoints(btn)
        fs:SetJustifyH(justify)
        btn.Text = fs

        btn:SetScript("OnClick", function()
            local currentSort = panel.__twichuiDetailsRuns.sortBy
            local currentAsc = panel.__twichuiDetailsRuns.sortAsc

            if currentSort == key then
                panel.__twichuiDetailsRuns.sortAsc = not currentAsc
            else
                panel.__twichuiDetailsRuns.sortBy = key
                -- Default sort direction
                if key == "date" then
                    panel.__twichuiDetailsRuns.sortAsc = false -- Newest first
                else
                    panel.__twichuiDetailsRuns.sortAsc = false -- Highest first
                end
            end
            UpdateDetailsRuns(panel, panel.__twichuiSelectedMapId)
        end)

        btn:SetScript("OnEnter", function(self) self.Text:SetTextColor(1, 1, 1) end)
        btn:SetScript("OnLeave", function(self) self.Text:SetTextColor(1, 0.82, 0) end)

        return btn
    end

    local hDate = CreateSortHeader("Date", "date", 80, "LEFT", "TOPLEFT", runsContainer, "TOPLEFT", 10, 0)
    local hKey = CreateSortHeader("Key", "level", 40, "CENTER", "LEFT", hDate, "RIGHT", 5, 0)
    local hTime = CreateSortHeader("Time", "time", 60, "RIGHT", "LEFT", hKey, "RIGHT", 5, 0)
    local hScore = CreateSortHeader("Score", "score", 50, "RIGHT", "LEFT", hTime, "RIGHT", 5, 0)
    local hUp = CreateSortHeader("Up", "upgrade", 30, "CENTER", "LEFT", hScore, "RIGHT", 5, 0)

    -- Scroll Frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, runsContainer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", runsContainer, "TOPLEFT", 10, -20)
    scrollFrame:SetPoint("BOTTOMRIGHT", runsContainer, "BOTTOMRIGHT", -26, 10)

    -- ElvUI scrollbar skinning (best-effort)
    if UI then
        UI.SkinScrollBar(scrollFrame)
    end

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)

    scrollFrame:SetScript("OnSizeChanged", function(self, w, h)
        content:SetWidth(w)
        if panel.__twichuiDetailsRuns and panel.__twichuiDetailsRuns.rows then
            for _, row in ipairs(panel.__twichuiDetailsRuns.rows) do
                row:SetWidth(w)
            end
        end
    end)

    panel.__twichuiDetailsRuns = {
        frame = runsContainer,
        content = content
    }

    panel.__twichuiActions = {
        frame = detailsHeader, -- actions bar removed, use header for reference
        portalButton = portalButton,
        portalIcon = portalIcon,
        portalHover = portalHover,
        portalSpellId = nil,
        portalUnlocked = false,
    }

    panel.__twichuiLeft = left
    panel.__twichuiRight = right
    panel.__twichuiRowsParent = rowsParent
    panel.__twichuiEmptyText = emptyText
    panel.__twichuiDetailsBG = detailsBG
    panel.__twichuiDetailsTitle = detailsTitle
    panel.__twichuiTime1 = time1
    panel.__twichuiTime2 = time2
    panel.__twichuiTime3 = time3

    local events = CreateFrame("Frame", nil, panel)
    panel.__twichuiEvents = events
    events:SetScript("OnEvent", function(_, event)
        if not panel:IsShown() then return end

        local now = (type(GetTime) == "function") and GetTime() or 0
        local last = panel.__twichuiLastUpdate or 0

        -- Allow critical events to bypass throttle
        local bypassThrottle = (event == "PLAYER_ENTERING_WORLD" or event == "CHALLENGE_MODE_MAPS_UPDATE")

        if not bypassThrottle and (now - last) < 0.5 then
            return
        end
        panel.__twichuiLastUpdate = now

        RefreshPanel(panel)
    end)

    local evs = {
        "PLAYER_ENTERING_WORLD",
        "CHALLENGE_MODE_MAPS_UPDATE",
        "CHALLENGE_MODE_COMPLETED",
        "BAG_UPDATE_DELAYED",
    }
    for _, ev in ipairs(evs) do
        pcall(events.RegisterEvent, events, ev)
    end

    panel:SetScript("OnShow", function()
        panel.__twichuiRetryCount = 0
        panel.__twichuiRetryPending = false
        -- Delay refresh slightly to allow layout to settle
        C_Timer.After(0.05, function()
            RefreshPanel(panel)
        end)
    end)

    return panel
end

function Dungeons:Refresh()
    if not MythicPlusModule.MainWindow or not MythicPlusModule.MainWindow.GetPanelFrame then
        return
    end

    local panel = MythicPlusModule.MainWindow:GetPanelFrame("dungeons")
    if not panel then return end

    ---@cast panel TwichUI_MythicPlus_DungeonsPanel
    if panel.__twichuiLeft and panel.__twichuiLeft.SetWidth then
        panel.__twichuiLeft:SetWidth(GetLeftColWidth())
    end

    if panel.__twichuiDetailsBG then
        panel.__twichuiDetailsBG:SetAlpha(GetDetailsBGAlpha())
        ApplyCoverLayout(panel.__twichuiDetailsBG, GetImageZoom())
    end

    RefreshPanel(panel)
end

function Dungeons:Initialize()
    if self.initialized then return end
    self.initialized = true

    -- Register the panel with the main window registry.
    if MythicPlusModule.MainWindow and MythicPlusModule.MainWindow.RegisterPanel then
        MythicPlusModule.MainWindow:RegisterPanel("dungeons", function(parent, window)
            return CreateDungeonsPanel(parent)
        end, nil, nil, { label = "Dungeons", order = 20 })
    end
end
