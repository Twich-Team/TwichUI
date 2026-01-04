local T = unpack(Twich)
local _G = _G

local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent

local ElvUI = rawget(_G, "ElvUI")
local E = ElvUI and ElvUI[1]

---@type MythicPlusModule
local MP = T:GetModule("MythicPlus")
---@type ConfigurationModule
local CM = T:GetModule("Configuration")
---@type LoggerModule
local Logger = T:GetModule("Logger")
---@type ToolsModule
local TM = T:GetModule("Tools")
local TT = TM and TM.Text

local Masque = T.Libs and T.Libs.Masque
local MasqueGroup = Masque and Masque:Group("TwichUI", "BiS Notifications")
local LSM = T.Libs and T.Libs.LSM

--- @class BestInSlotNotificationFrame
--- @field anchorFrame Frame
--- @field anchorFrameFadeGroup AnimationGroup
--- @field activeMessages table
--- @field framePool table
--- @field activeByItem table<string, {frame:Frame}>
--- @field previewFrame Frame
--- @field previewShown boolean
--- @field initialized boolean
local NIF = MP.BestInSlotNotificationFrame or {}
MP.BestInSlotNotificationFrame = NIF

local KEY_PREFIX = "mythicplus.bestInSlot.notifications."

-- Store per-frame state without injecting custom fields into Frame/Button objects.
local TooltipItemLinkByOwner = setmetatable({}, { __mode = "k" })
local KindByFrame = setmetatable({}, { __mode = "k" })

local function GetSetting(suffix, default)
    return CM:GetProfileSettingSafe(KEY_PREFIX .. suffix, default)
end

local function NormalizeHexColor(hex)
    if type(hex) ~= "string" or hex == "" then return nil end
    hex = hex:gsub("^|c", ""):gsub("^#", "")
    if #hex == 6 then
        hex = "ff" .. hex
    end
    if #hex ~= 8 then return nil end
    return hex
end

local function GetItemRarityHex(itemLink, itemID)
    if not itemLink then return nil end

    local quality
    if itemID and _G.C_Item and _G.C_Item.GetItemQualityByID then
        quality = _G.C_Item.GetItemQualityByID(itemID)
    end
    if quality == nil and _G.GetItemInfo then
        local _, _, q = _G.GetItemInfo(itemLink)
        quality = q
    end
    if quality == nil then return nil end

    local _, _, _, hex = _G.GetItemQualityColor(quality)
    return NormalizeHexColor(hex)
end

local function ColorizeWithHex(hex, text)
    text = tostring(text or "")
    hex = NormalizeHexColor(hex)
    if not hex then
        return text
    end
    return "|c" .. hex .. text .. "|r"
end

---@param f Frame
local function ApplyVisualsToFrame(f)
    local width = tonumber(GetSetting("frameWidth", 360)) or 360
    local height = tonumber(GetSetting("frameHeight", 60)) or 60
    f:SetSize(width, height)

    -- Default to ElvUI look & feel when available.
    local textureKey = GetSetting("frameTexture", "ElvUI Norm")
    local texturePath = (LSM and LSM:Fetch("statusbar", textureKey)) or textureKey
    if f.bg then
        f.bg:SetTexture(texturePath)
    end

    local frameColor = GetSetting("frameColor", { r = 0, g = 0, b = 0, a = 0.6 })
    if type(frameColor) == "table" and f.bg then
        f.bg:SetVertexColor(tonumber(frameColor.r) or 0, tonumber(frameColor.g) or 0, tonumber(frameColor.b) or 0,
            tonumber(frameColor.a) or 0.6)
    end

    local kind = KindByFrame[f]
    local isAvailability = (kind == "ROLL" or kind == "VAULT")
    local bc
    if isAvailability then
        -- Distinguish "available" (roll/vault) from "acquired".
        bc = GetSetting("frameBorderColorAvailable", { r = 0.23, g = 0.62, b = 1.00, a = 1 })
    else
        -- Default acquired border remains the current gold.
        bc = GetSetting("frameBorderColor", { r = 0.90, g = 0.72, b = 0.20, a = 1 })
    end
    local bs = tonumber(GetSetting("frameBorderSize", 1)) or 1

    -- Use ElvUI 1px/blank texture for borders when available.
    local borderTexture = (E and E.media and (E.media.blankTex or E.media.normTex)) or "Interface\\Buttons\\WHITE8X8"

    if not f.borderTop then
        f.borderTop = f:CreateTexture(nil, "BORDER")
        f.borderBottom = f:CreateTexture(nil, "BORDER")
        f.borderLeft = f:CreateTexture(nil, "BORDER")
        f.borderRight = f:CreateTexture(nil, "BORDER")
    end

    local function ApplyBorderPiece(tex)
        if borderTexture then
            tex:SetTexture(borderTexture)
            tex:SetVertexColor(tonumber(bc.r) or 1, tonumber(bc.g) or 1, tonumber(bc.b) or 1, tonumber(bc.a) or 1)
        else
            tex:SetColorTexture(tonumber(bc.r) or 1, tonumber(bc.g) or 1, tonumber(bc.b) or 1, tonumber(bc.a) or 1)
        end
    end

    ApplyBorderPiece(f.borderTop)
    ApplyBorderPiece(f.borderBottom)
    ApplyBorderPiece(f.borderLeft)
    ApplyBorderPiece(f.borderRight)

    f.borderTop:Show()
    f.borderBottom:Show()
    f.borderLeft:Show()
    f.borderRight:Show()

    f.borderTop:ClearAllPoints()
    f.borderTop:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.borderTop:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.borderTop:SetHeight(bs)

    f.borderBottom:ClearAllPoints()
    f.borderBottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.borderBottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.borderBottom:SetHeight(bs)

    f.borderLeft:ClearAllPoints()
    f.borderLeft:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.borderLeft:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.borderLeft:SetWidth(bs)

    f.borderRight:ClearAllPoints()
    f.borderRight:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.borderRight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.borderRight:SetWidth(bs)

    local iconSize = tonumber(GetSetting("iconSize", 32)) or 32
    if f.button then
        f.button:SetSize(iconSize, iconSize)
    end
    if f.icon then
        f.icon:SetSize(iconSize, iconSize)
    end

    local itemFont = GetSetting("itemFont", "Expressway")
    local itemFontPath = (LSM and LSM:Fetch("font", itemFont))
    local fallbackFontPath = (GameFontNormal and select(1, GameFontNormal:GetFont())) or _G.STANDARD_TEXT_FONT or
        "Fonts\\FRIZQT__.TTF"
    local itemSize = tonumber(GetSetting("itemFontSize", 14)) or 14
    local itemColor = GetSetting("itemFontColor", { r = 1, g = 1, b = 1, a = 1 })

    if f.itemText then
        f.itemText:SetFont(itemFontPath or fallbackFontPath, itemSize, "OUTLINE")
        f.itemText:SetTextColor(
            tonumber(itemColor.r) or 1,
            tonumber(itemColor.g) or 1,
            tonumber(itemColor.b) or 1,
            tonumber(itemColor.a) or 1
        )
    end

    local detailFont = GetSetting("detailFont", "Expressway")
    local detailFontPath = (LSM and LSM:Fetch("font", detailFont))
    local detailSize = tonumber(GetSetting("detailFontSize", 12)) or 12
    local detailColor = GetSetting("detailFontColor", { r = 0.9, g = 0.9, b = 0.9, a = 1 })

    if f.detailText then
        f.detailText:SetFont(detailFontPath or fallbackFontPath, detailSize, "OUTLINE")
        f.detailText:SetTextColor(
            tonumber(detailColor.r) or 1,
            tonumber(detailColor.g) or 1,
            tonumber(detailColor.b) or 1,
            tonumber(detailColor.a) or 1
        )
    end

    -- (Removed animated background glow)

    -- Ensure default layout (in case old settings existed).
    if f.icon then
        f.icon:ClearAllPoints()
        f.icon:SetPoint("LEFT", f, "LEFT", 8, 0)
    end
    if f.button then
        f.button:ClearAllPoints()
        f.button:SetPoint("LEFT", f, "LEFT", 8, 0)
    end
    if f.itemText then
        f.itemText:SetJustifyH("LEFT")
        f.itemText:ClearAllPoints()
        f.itemText:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, -2)
        f.itemText:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    end
    if f.detailText then
        f.detailText:SetJustifyH("LEFT")
        f.detailText:ClearAllPoints()
        f.detailText:SetPoint("TOPLEFT", f.itemText, "BOTTOMLEFT", 0, -2)
        f.detailText:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        f.detailText:Show()
    end
end

local function StartSequence(frame, fadeInT, holdT, fadeOutT, moveInT, moveOutT)
    frame.fadeIn:SetDuration(fadeInT)
    frame.hold:SetDuration(holdT)
    frame.fadeOut:SetDuration(fadeOutT)

    frame.moveIn:SetDuration(moveInT)
    frame.moveOut:SetDuration(moveOutT)

    frame:SetAlpha(0)
    frame.fadeGroup:Stop()
    frame.fadeGroup:Play()
end

local function PositionFrame(f, index)
    local gap = tonumber(GetSetting("frameSpacing", 8)) or 8
    local grow = GetSetting("growDirection", "UP")

    f:ClearAllPoints()

    if grow == "DOWN" then
        f:SetPoint("TOP", NIF.anchorFrame, "BOTTOM", 0, -((index - 1) * (f:GetHeight() + gap)))
    else
        f:SetPoint("BOTTOM", NIF.anchorFrame, "TOP", 0, ((index - 1) * (f:GetHeight() + gap)))
    end
end

function NIF:InitializeAnchorFrame()
    self.anchorFrame = CreateFrame("Frame", "TwichUIMythicPlusBiSNotificationAnchorFrame", E and E.UIParent or UIParent)
    self.anchorFrame:SetClampedToScreen(true)
    self.anchorFrame:ClearAllPoints()
    self.anchorFrame:SetPoint("CENTER", E and E.UIParent or UIParent, "CENTER", 0, 200)
    self.anchorFrame:SetSize(360, 60)

    self.anchorFrame.text = self.anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.anchorFrame.text:SetJustifyH("CENTER")
    self.anchorFrame.text:SetAllPoints()
    self.anchorFrame.text:SetText("")
    self.anchorFrame.text:Hide()

    self.anchorFrame.bg = self.anchorFrame:CreateTexture(nil, "BACKGROUND")
    self.anchorFrame.bg:SetAllPoints()

    if E and E.CreateMover then
        E:CreateMover(self.anchorFrame, "TwichUIMythicPlusBiSNotificationsMover", "TwichUI BiS Notifications", nil, nil,
            nil, "ALL", nil, "TwichUI,Modules,MythicPlus,BiSNotifications")
    end

    self.anchorFrameFadeGroup = self.anchorFrame:CreateAnimationGroup()
    self.anchorFrameFadeGroup:SetLooping("NONE")

    local aIn = self.anchorFrameFadeGroup:CreateAnimation("Alpha")
    aIn:SetOrder(1)
    aIn:SetFromAlpha(0)
    aIn:SetToAlpha(1)

    local aHold = self.anchorFrameFadeGroup:CreateAnimation("Alpha")
    aHold:SetOrder(2)
    aHold:SetFromAlpha(1)
    aHold:SetToAlpha(1)

    local aOut = self.anchorFrameFadeGroup:CreateAnimation("Alpha")
    aOut:SetOrder(3)
    aOut:SetFromAlpha(1)
    aOut:SetToAlpha(0)

    self.anchorFrameFadeGroup:SetScript("OnFinished", function()
        self.anchorFrame:Hide()
    end)

    self.activeMessages = {}
    self.framePool = {}
    self.activeByItem = {}
    self.previewFrame = nil
    self.previewShown = false
end

function NIF:AcquireMessageFrame()
    local f = table.remove(self.framePool)
    if not f then
        f = CreateFrame("Frame", nil, self.anchorFrame:GetParent())
        f:SetClampedToScreen(true)
        f:EnableMouse(true)

        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints()

        local iconSize = tonumber(GetSetting("iconSize", 32)) or 32

        if MasqueGroup then
            f.button = CreateFrame("Button", nil, f)
            f.button:SetSize(iconSize, iconSize)
            f.button:SetPoint("LEFT", f, "LEFT", 8, 0)

            f.icon = f.button:CreateTexture(nil, "ARTWORK")
            f.icon:SetAllPoints()
            f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            f.button.Icon = f.icon
            MasqueGroup:AddButton(f.button, { Icon = f.button.Icon })
        else
            f.icon = f:CreateTexture(nil, "ARTWORK")
            f.icon:SetSize(iconSize, iconSize)
            f.icon:SetPoint("LEFT", f, "LEFT", 8, 0)
            f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end

        f.itemText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.itemText:SetJustifyH("LEFT")
        f.itemText:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, -2)
        f.itemText:SetPoint("RIGHT", f, "RIGHT", -8, 0)

        f.detailText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.detailText:SetJustifyH("LEFT")
        f.detailText:SetPoint("TOPLEFT", f.itemText, "BOTTOMLEFT", 0, -2)
        f.detailText:SetPoint("RIGHT", f, "RIGHT", -8, 0)

        -- Reserved for future styles.

        local function ShowItemTooltip(owner)
            local link = owner and TooltipItemLinkByOwner[owner]
            if not link or type(link) ~= "string" or link == "" then return end

            if _G.GameTooltip and _G.GameTooltip.SetOwner and _G.GameTooltip.SetHyperlink then
                _G.GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
                _G.GameTooltip:SetHyperlink(link)
                _G.GameTooltip:Show()
            end
        end

        local function HideItemTooltip()
            if _G.GameTooltip and _G.GameTooltip.Hide then
                _G.GameTooltip:Hide()
            end
        end

        local function DismissMessageFrame(frame)
            if not frame then return end
            HideItemTooltip()

            -- Preview is controlled by a config toggle; keep its state consistent.
            if NIF.previewFrame and frame == NIF.previewFrame then
                NIF:HidePreview()
                return
            end

            if frame.fadeGroup then
                frame.fadeGroup:Stop()
            end
            NIF:RecycleFrame(frame)
        end

        f:SetScript("OnEnter", function(self)
            self:SetAlpha(1)
            ShowItemTooltip(self)
        end)

        f:SetScript("OnLeave", function(self)
            -- no hover-pause; keep behavior simple
            HideItemTooltip()
        end)

        f:SetScript("OnMouseDown", function(self)
            DismissMessageFrame(self)
        end)

        if f.button then
            f.button:RegisterForClicks("AnyUp")
            f.button:SetScript("OnEnter", function(btn)
                ShowItemTooltip(btn)
            end)
            f.button:SetScript("OnLeave", function()
                HideItemTooltip()
            end)
            f.button:SetScript("OnClick", function(btn)
                DismissMessageFrame(btn and btn:GetParent())
            end)
        end

        f.fadeGroup = f:CreateAnimationGroup()
        f.fadeGroup:SetLooping("NONE")

        f.fadeIn = f.fadeGroup:CreateAnimation("Alpha")
        f.fadeIn:SetOrder(1)
        f.fadeIn:SetFromAlpha(0)
        f.fadeIn:SetToAlpha(1)

        f.moveIn = f.fadeGroup:CreateAnimation("Translation")
        f.moveIn:SetOrder(1)
        f.moveIn:SetOffset(0, -10)

        f.hold = f.fadeGroup:CreateAnimation("Alpha")
        f.hold:SetOrder(2)
        f.hold:SetFromAlpha(1)
        f.hold:SetToAlpha(1)

        f.fadeOut = f.fadeGroup:CreateAnimation("Alpha")
        f.fadeOut:SetOrder(3)
        f.fadeOut:SetFromAlpha(1)
        f.fadeOut:SetToAlpha(0)

        f.moveOut = f.fadeGroup:CreateAnimation("Translation")
        f.moveOut:SetOrder(3)
        f.moveOut:SetOffset(0, 10)

        f.fadeGroup:SetScript("OnFinished", function(self)
            local frame = self:GetParent()
            NIF:RecycleFrame(frame)
        end)
    end

    ApplyVisualsToFrame(f)
    f:Show()
    return f
end

function NIF:RecycleFrame(f)
    if not f then return end

    for idx, active in ipairs(self.activeMessages) do
        if active == f then
            table.remove(self.activeMessages, idx)
            break
        end
    end

    if f.fadeGroup then
        f.fadeGroup:Stop()
    end

    f:Hide()
    f.itemText:SetText("")
    f.detailText:SetText("")
    TooltipItemLinkByOwner[f] = nil
    if f.button then TooltipItemLinkByOwner[f.button] = nil end
    KindByFrame[f] = nil

    table.insert(self.framePool, f)

    for i, frame in ipairs(self.activeMessages) do
        PositionFrame(frame, i)
    end
end

function NIF:UpdateFrame()
    if self.anchorFrame then
        ApplyVisualsToFrame(self.anchorFrame)
    end
    if self.previewFrame and self.previewFrame:IsShown() then
        ApplyVisualsToFrame(self.previewFrame)
    end
    for _, f in ipairs(self.activeMessages or {}) do
        ApplyVisualsToFrame(f)
    end
end

---@param itemLink string
---@param kind "NEW"|"UPGRADE"|"FOUND"|string
---@param receivedILvl number|nil
---@param previousILvl number|nil
---@param quantity number|nil
function NIF:ShowNotification(itemLink, kind, receivedILvl, previousILvl, quantity)
    if not self.initialized then
        self:Initialize()
    end

    local maxMessages = tonumber(GetSetting("maxMessages", 5)) or 5
    if #self.activeMessages >= maxMessages then
        local oldest = table.remove(self.activeMessages, 1)
        if oldest and oldest.fadeGroup then
            oldest.fadeGroup:Stop()
        end
        self:RecycleFrame(oldest)
    end

    local f = self:AcquireMessageFrame()
    TooltipItemLinkByOwner[f] = itemLink
    if f.button then TooltipItemLinkByOwner[f.button] = itemLink end
    KindByFrame[f] = kind

    local itemID, _, _, equipLoc, iconTex = C_Item.GetItemInfoInstant(itemLink)
    local rarityHex = GetItemRarityHex(itemLink, itemID)
    if iconTex then
        f.icon:SetTexture(iconTex)
        f.icon:Show()
    else
        f.icon:Hide()
    end

    if quantity and tonumber(quantity) and tonumber(quantity) > 1 then
        f.itemText:SetText(tostring(itemLink) .. string.format(" x%d", tonumber(quantity)))
    else
        f.itemText:SetText(itemLink or "")
    end

    local label
    if kind == "UPGRADE" then
        label = "BiS Upgrade"
    elseif kind == "NEW" then
        label = "BiS Acquired"
    elseif kind == "ROLL" then
        label = "BiS Available - Roll"
    elseif kind == "VAULT" then
        label = "BiS Available - Great Vault"
    else
        label = tostring(kind or "BiS")
    end

    local slotName = equipLoc and _G[equipLoc]
    if slotName and slotName ~= "" then
        label = string.format("%s - %s", label, slotName)
    end

    local r = tonumber(receivedILvl)
    local p = tonumber(previousILvl)
    if r and p and r > 0 and p > 0 then
        -- Avoid unicode arrows here; some fonts won't render them.
        f.detailText:SetText(string.format(
            "%s  (iLvl %s -> %s)",
            label,
            ColorizeWithHex(rarityHex, tostring(p)),
            ColorizeWithHex(rarityHex, tostring(r))
        ))
    elseif r and r > 0 then
        f.detailText:SetText(string.format("%s  (iLvl %s)", label, ColorizeWithHex(rarityHex, tostring(r))))
    else
        f.detailText:SetText(label)
    end

    ApplyVisualsToFrame(f)

    local total = tonumber(GetSetting("displayDuration", 15)) or 15
    local fadeInT = tonumber(GetSetting("fadeInTime", 0.25)) or 0.25
    local fadeOutT = tonumber(GetSetting("fadeOutTime", 0.3)) or 0.3
    local moveInT = tonumber(GetSetting("moveInTime", 0.18)) or 0.18
    local moveOutT = tonumber(GetSetting("moveOutTime", 0.18)) or 0.18

    if fadeInT < 0 then fadeInT = 0 end
    if fadeOutT < 0 then fadeOutT = 0 end
    if moveInT < 0 then moveInT = 0 end
    if moveOutT < 0 then moveOutT = 0 end

    local maxFade = total
    if fadeInT + fadeOutT > maxFade then
        local scale = maxFade / (fadeInT + fadeOutT)
        fadeInT = fadeInT * scale
        fadeOutT = fadeOutT * scale
    end

    local holdT = math.max(0, total - fadeInT - fadeOutT)

    table.insert(self.activeMessages, f)
    PositionFrame(f, #self.activeMessages)

    StartSequence(f, fadeInT, holdT, fadeOutT, moveInT, moveOutT)
end

function NIF:ShowPreview()
    if not self.initialized then
        self:Initialize()
    end

    if not self.previewFrame then
        self.previewFrame = self:AcquireMessageFrame()
    end

    -- Ensure the preview is visible and positioned; an unanchored frame can appear off-screen.
    self.previewFrame:ClearAllPoints()
    self.previewFrame:SetPoint("CENTER", self.anchorFrame, "CENTER", 0, 0)
    self.previewFrame:SetFrameStrata("DIALOG")

    self.previewFrame.itemText:SetText("|cffa335ee|Hitem:19019::::::::80:::::|h[Preview BiS Item]|h|r")
    local previewLink = "|cffa335ee|Hitem:19019::::::::80:::::|h[Preview BiS Item]|h|r"
    local previewItemID = _G.GetItemInfoInstant and _G.GetItemInfoInstant(previewLink)
    local previewHex = GetItemRarityHex(previewLink, previewItemID)
    self.previewFrame.detailText:SetText(string.format("BiS Acquired  (iLvl %s)", ColorizeWithHex(previewHex, "999")))

    TooltipItemLinkByOwner[self.previewFrame] = previewLink
    if self.previewFrame.button then TooltipItemLinkByOwner[self.previewFrame.button] = previewLink end

    ApplyVisualsToFrame(self.previewFrame)

    if self.previewFrame.fadeGroup then
        self.previewFrame.fadeGroup:Stop()
    end

    self.previewFrame:SetAlpha(1)
    self.previewFrame:Show()
    self.previewShown = true
end

function NIF:HidePreview()
    if self.previewFrame then
        if self.previewFrame.fadeGroup then
            self.previewFrame.fadeGroup:Stop()
        end
        self.previewFrame:Hide()
        TooltipItemLinkByOwner[self.previewFrame] = nil
        if self.previewFrame.button then TooltipItemLinkByOwner[self.previewFrame.button] = nil end
    end
    self.previewShown = false
end

function NIF:IsPreviewShown()
    return self.previewShown
end

function NIF:Initialize()
    if self.initialized then return end
    self:InitializeAnchorFrame()
    self.initialized = true
    Logger.Debug("BestInSlotNotificationFrame initialized")
end
