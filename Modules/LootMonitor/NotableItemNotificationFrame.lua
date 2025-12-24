local T, W, I, C                = unpack(Twich)
local E                         = ElvUI and select(1, unpack(ElvUI))
---@type LootMonitorModule
local LM                        = T:GetModule("LootMonitor")

---@type ConfigurationModule
local CM                        = T:GetModule("Configuration")
---@type LoggerModule
local Logger                    = T:GetModule("Logger")
---@type ToolsModule
local TM                        = T:GetModule("Tools")
local TT                        = TM.Text
local CT                        = TM.Colors

local CreateFrame               = CreateFrame
local Masque                    = T.Libs.Masque
local MasqueGroup               = Masque and Masque:Group("TwichUI", "Notable Item Notifications")
local LSM                       = T.Libs.LSM

--- @class NotableItemNotificationFrame
--- @field anchorFrame Frame The anchor frame for the notification messages, used as an ElvUI mover, not directly for messages.
--- @field anchorFrameFadeGroup AnimationGroup The animation group for fading the anchor frame in and out.
--- @field activeMessages table ordered list of visible message frames
--- @field framePool table recycled message frames
--- @field activeByItem table<string, {frame:Frame, totalValue:number, totalQuantity:integer}>
--- @field previewFrame Frame
--- @field previewShown boolean
--- @field initialized boolean Whether the notification frame has been initialized.
local NIF                       = LM.NotableItemNotificationFrame or {}
LM.NotableItemNotificationFrame = NIF

function NIF:InitializeAnchorFrame()
    self.anchorFrame = CreateFrame("Frame", "TwichUILootMonitorNotableItemNotificationAnchorFrame",
        E and E.UIParent or UIParent)
    self.anchorFrame:SetClampedToScreen(true)
    self.anchorFrame:ClearAllPoints()
    self.anchorFrame:SetPoint("CENTER", E and E.UIParent or UIParent, "CENTER", 0, 200)
    self.anchorFrame:SetSize(400, 60)

    self.anchorFrame.text = self.anchorFrame:CreateFontString(nil, "OVERLAY")
    self.anchorFrame.text:SetJustifyH("CENTER")
    self.anchorFrame.text:SetAllPoints()
    self.anchorFrame:Hide()

    self.anchorFrame.bg = self.anchorFrame:CreateTexture(nil, "BACKGROUND")
    self.anchorFrame.bg:SetAllPoints()

    if E and E.CreateMover then
        E:CreateMover(self.anchorFrame, "TwichUINotableItemNotificationsMover", "TwichUI Notable Item Notifications",
            nil, nil, nil, "ALL", nil, "TwichUI,Modules,LootMonitor,NotableItems")
    end

    -- animation
    self.anchorFrameFadeGroup = self.anchorFrame:CreateAnimationGroup()
    self.anchorFrameFadeGroup:SetLooping("NONE")

    local anchorFadeIn = self.anchorFrameFadeGroup:CreateAnimation("Alpha")
    anchorFadeIn:SetOrder(1)
    anchorFadeIn:SetFromAlpha(0)
    anchorFadeIn:SetToAlpha(1)

    local anchorHold = self.anchorFrameFadeGroup:CreateAnimation("Alpha")
    anchorHold:SetOrder(2)
    anchorHold:SetFromAlpha(1)
    anchorHold:SetToAlpha(1)

    local anchorFadeOut = self.anchorFrameFadeGroup:CreateAnimation("Alpha")
    anchorFadeOut:SetOrder(3)
    anchorFadeOut:SetFromAlpha(1)
    anchorFadeOut:SetToAlpha(0)

    self.anchorFrameFadeGroup:SetScript("OnFinished", function()
        self.anchorFrame:Hide()
    end)

    -- initialize locals
    self.activeMessages = {}
    self.framePool = {}
    self.activeByItem = {}
    self.previewFrame = nil
    self.previewShown = false
end

---@param f Frame
local function ApplyVisualsToFrame(f)
    -- frame size
    local width = tonumber(CM:GetProfileSettingSafe("lootMonitor.notableItems.frameWidth", 400))
    local height = tonumber(CM:GetProfileSettingSafe("lootMonitor.notableItems.frameHeight", 60))
    f:SetSize(width, height)

    -- frame background texture
    local textureKey = CM:GetProfileSettingSafe("lootMonitor.notableItems.frameTexture", "Blizzard")
    local texturePath = LSM:Fetch("statusbar", textureKey)
    if texturePath then
        f.bg:SetTexture(texturePath)
    else
        f.bg:SetTexture(nil)
    end

    -- frame background color and alpha
    local frameColor = CM:GetProfileSettingSafe("lootMonitor.notableItems.frameColor", { r = 0, g = 0, b = 0, a = 0.6 })
    f.bg:SetVertexColor(tonumber(frameColor.r), tonumber(frameColor.g), tonumber(frameColor.b), tonumber(frameColor.a))

    -- border color and size
    local bc = CM:GetProfileSettingSafe("lootMonitor.notableItems.frameBorderColor",
        { r = 1, g = 1, b = 1, a = 1 })
    local bs = CM:GetProfileSettingSafe("lootMonitor.notableItems.frameBorderSize", 1)

    local t = f.borderTop
    local b = f.borderBottom
    local l = f.borderLeft
    local r = f.borderRight

    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", f, "TOPLEFT", -bs, bs)
    t:SetPoint("TOPRIGHT", f, "TOPRIGHT", bs, bs)
    t:SetHeight(bs)

    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -bs, -bs)
    b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", bs, -bs)
    b:SetHeight(bs)

    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", f, "TOPLEFT", -bs, bs)
    l:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -bs, -bs)
    l:SetWidth(bs)

    r:ClearAllPoints()
    r:SetPoint("TOPRIGHT", f, "TOPRIGHT", bs, bs)
    r:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", bs, -bs)
    r:SetWidth(bs)

    t:SetColorTexture(tonumber(bc.r), tonumber(bc.g), tonumber(bc.b), tonumber(bc.a))
    b:SetColorTexture(tonumber(bc.r), tonumber(bc.g), tonumber(bc.b), tonumber(bc.a))
    l:SetColorTexture(tonumber(bc.r), tonumber(bc.g), tonumber(bc.b), tonumber(bc.a))
    r:SetColorTexture(tonumber(bc.r), tonumber(bc.g), tonumber(bc.b), tonumber(bc.a))

    -- fonts
    local fontKey = CM:GetProfileSettingSafe("lootMonitor.notableItems.font", "Expressway")
    local itemFontSize = tonumber(CM:GetProfileSettingSafe("lootMonitor.notableItems.itemFontSize", 18))
    local valueFontSize = tonumber(CM:GetProfileSettingSafe("lootMonitor.notableItems.valueFontSize", 14))
    local fontPath = LSM and LSM:Fetch("font", fontKey)

    if fontPath then
        if f.text then
            f.text:SetFont(fontPath, itemFontSize, "OUTLINE")
        end
        if f.itemText then
            f.itemText:SetFont(fontPath, itemFontSize, "OUTLINE")
        end
        if f.valueText then
            f.valueText:SetFont(fontPath, valueFontSize, "OUTLINE")
        end
    else
        if f.text then
            f.text:SetFontObject(GameFontHighlightLarge)
        end
        if f.itemText then
            f.itemText:SetFontObject(GameFontHighlight)
        end
        if f.valueText then
            f.valueText:SetFontObject(GameFontHighlightSmall)
        end
    end

    -- Icon size (button if Masque setup used)
    local iconSize = tonumber(CM:GetProfileSettingSafe("lootMonitor.notableItems.iconSize", 32))
    if f.button then
        f.button:SetSize(iconSize, iconSize)
    elseif f.icon then
        f.icon:SetSize(iconSize, iconSize)
    end

    -- Vertical centering of item/value text relative to icon/button
    local anchor = f.button or f.icon
    if f.itemText and f.valueText and anchor then
        local itemHeight  = select(2, f.itemText:GetFont()) or itemFontSize
        local valueHeight = select(2, f.valueText:GetFont()) or valueFontSize
        local gap         = 2
        local totalBlock  = itemHeight + valueHeight + gap
        local halfBlock   = totalBlock / 2

        f.itemText:ClearAllPoints()
        f.valueText:ClearAllPoints()

        local align = CM:GetProfileSettingSafe("lootMonitor.notableItems.contentAlignment", "LEFT")

        if align == "RIGHT" then
            -- Icon/button on the FAR RIGHT
            if f.button then
                f.button:ClearAllPoints()
                f.button:SetPoint("RIGHT", f, "RIGHT", -8, 0)
            elseif f.icon then
                f.icon:ClearAllPoints()
                f.icon:SetPoint("RIGHT", f, "RIGHT", -8, 0)
            end

            -- Text block directly to the LEFT of the icon, right-justified
            f.itemText:SetJustifyH("RIGHT")
            f.valueText:SetJustifyH("RIGHT")

            f.itemText:SetPoint("RIGHT", anchor, "LEFT", -4, halfBlock / 2)
            f.itemText:SetPoint("LEFT", anchor, "LEFT", -200, halfBlock / 2)

            f.valueText:SetPoint("TOPRIGHT", f.itemText, "BOTTOMRIGHT", 0, -gap)
            f.valueText:SetPoint("LEFT", f.itemText, "LEFT", 0, -gap)
        else
            -- LEFT: icon/button on the FAR LEFT
            if f.button then
                f.button:ClearAllPoints()
                f.button:SetPoint("LEFT", f, "LEFT", 8, 0)
            elseif f.icon then
                f.icon:ClearAllPoints()
                f.icon:SetPoint("LEFT", f, "LEFT", 8, 0)
            end

            -- Text block directly to the RIGHT of the icon, left-justified
            f.itemText:SetJustifyH("LEFT")
            f.valueText:SetJustifyH("LEFT")

            f.itemText:SetPoint("LEFT", anchor, "RIGHT", 4, halfBlock / 2)
            f.itemText:SetPoint("RIGHT", anchor, "RIGHT", 204, halfBlock / 2)

            f.valueText:SetPoint("TOPLEFT", f.itemText, "BOTTOMLEFT", 0, -gap)
            f.valueText:SetPoint("RIGHT", f.itemText, "RIGHT", 0, -gap)
        end
    end
end

function NIF:RemoveFromActive(frame)
    for i, msg in ipairs(self.activeMessages) do
        if msg == frame then
            table.remove(self.activeMessages, i)
            break
        end
    end
end

function NIF:ReanchorMessages()
    local dir = CM:GetProfileSettingSafe("lootMonitor.notableItems.growDirection", "UP")
    local spacing = tonumber(CM:GetProfileSettingSafe("lootMonitor.notableItems.growSpacing", 4))

    local anchorPoint, relativePoint, offsetSign
    if dir == "DOWN" then
        anchorPoint   = "TOP"
        relativePoint = "BOTTOM"
        offsetSign    = -1
    else
        anchorPoint   = "BOTTOM"
        relativePoint = "TOP"
        offsetSign    = 1
    end

    for index, f in ipairs(self.activeMessages) do
        f:ClearAllPoints()
        if index == 1 then
            f:SetPoint(anchorPoint, self.anchorFrame, anchorPoint, 0, 0)
        else
            local prev = self.activeMessages[index - 1]
            f:SetPoint(anchorPoint, prev, relativePoint, 0, offsetSign * spacing)
        end
    end
end

function NIF:RecycleFrame(frame)
    frame:Hide()
    self:RemoveFromActive(frame)

    -- Clear any activeByItem entry pointing at this frame
    for itemLink, data in pairs(self.activeByItem) do
        if data.frame == frame then
            self.activeByItem[itemLink] = nil
            break
        end
    end

    table.insert(self.framePool, frame)
    self:ReanchorMessages()
end

local function StartFadeSequence(frame, fadeInT, holdT, fadeOutT)
    frame.fadeIn:SetDuration(fadeInT)
    frame.hold:SetDuration(holdT)
    frame.fadeOut:SetDuration(fadeOutT)
    frame.fadeOutDuration = fadeOutT

    frame:SetAlpha(0)
    frame.pendingFadeOut = false
    frame.fadeGroup:Stop()
    frame.fadeGroup:Play()
end

local function StartShortFadeOut(frame)
    local d = 0.2
    frame.fadeIn:SetDuration(0)
    frame.hold:SetDuration(0)
    frame.fadeOut:SetDuration(d)
    frame.fadeOutDuration = d
    frame:SetAlpha(1)
    frame.pendingFadeOut = false
    frame.fadeGroup:Stop()
    frame.fadeGroup:Play()
end

function NIF:AcquireMessageFrame()
    local f = table.remove(self.framePool)
    if not f then
        f = CreateFrame("Frame", nil, self.anchorFrame:GetParent())
        f:SetClampedToScreen(true)
        f:EnableMouse(true)

        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints()

        -- Masque button (if Masque present), otherwise use a plain icon texture
        local iconSize = tonumber(CM:GetProfileSettingSafe("lootMonitor.notableItems.iconSize", 32))

        if MasqueGroup then
            f.button = CreateFrame("Button", nil, f)
            f.button:SetSize(iconSize, iconSize)
            f.button:SetPoint("LEFT", f, "LEFT", 8, 0)

            f.icon = f.button:CreateTexture(nil, "ARTWORK")
            f.icon:SetAllPoints()
            f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            f.button.Icon = f.icon
            MasqueGroup:AddButton(f.button, {
                Icon = f.button.Icon,
            })
        else
            f.icon = f:CreateTexture(nil, "ARTWORK")
            f.icon:SetSize(iconSize, iconSize)
            f.icon:SetPoint("LEFT", f, "LEFT", 8, 0)
        end

        -- Item link text (top line)
        f.itemText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

        f.itemText:SetScript("OnEnter", function(self)
            local link = self.itemLink
            if not link then return end
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink(link)
            GameTooltip:Show()
        end)

        f.itemText:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- Value text (bottom line)
        f.valueText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

        -- Basic initial placement (will be overridden by ApplyVisualsToFrame)
        local anchor = f.button or f.icon
        f.itemText:ClearAllPoints()
        f.itemText:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
        f.itemText:SetPoint("RIGHT", f, "RIGHT", -8, 0)

        f.valueText:ClearAllPoints()
        f.valueText:SetPoint("TOPLEFT", f.itemText, "BOTTOMLEFT", 0, -2)
        f.valueText:SetPoint("RIGHT", f, "RIGHT", -8, 0)

        -- Optional full-frame text
        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetJustifyH("CENTER")
        f.text:SetAllPoints()
        f.text:Hide()

        -- Border pieces
        f.borderTop      = f:CreateTexture(nil, "BORDER")
        f.borderBottom   = f:CreateTexture(nil, "BORDER")
        f.borderLeft     = f:CreateTexture(nil, "BORDER")
        f.borderRight    = f:CreateTexture(nil, "BORDER")

        -- Hover-aware fade behavior
        f.isMouseOver    = false
        f.pendingFadeOut = false

        f:SetScript("OnEnter", function(self)
            self.isMouseOver = true
            -- Ensure fully visible when hovered
            self:SetAlpha(1)
        end)

        f:SetScript("OnLeave", function(self)
            self.isMouseOver = false
            if self.pendingFadeOut then
                -- Fade out now after user leaves
                StartShortFadeOut(self)
            end
        end)

        -- Fade animations (show/hold/fade)
        f.fadeGroup = f:CreateAnimationGroup()
        f.fadeGroup:SetLooping("NONE")

        f.fadeIn = f.fadeGroup:CreateAnimation("Alpha")
        f.fadeIn:SetOrder(1)
        f.fadeIn:SetFromAlpha(0)
        f.fadeIn:SetToAlpha(1)

        f.hold = f.fadeGroup:CreateAnimation("Alpha")
        f.hold:SetOrder(2)
        f.hold:SetFromAlpha(1)
        f.hold:SetToAlpha(1)

        f.fadeOut = f.fadeGroup:CreateAnimation("Alpha")
        f.fadeOut:SetOrder(3)
        f.fadeOut:SetFromAlpha(1)
        f.fadeOut:SetToAlpha(0)

        f.fadeGroup:SetScript("OnFinished", function(self)
            local frame = self:GetParent()

            -- If the mouse is still over the frame when fade ends, keep it visible.
            if frame:IsMouseOver() then
                frame.pendingFadeOut = true
                frame:SetAlpha(1)
                return
            end

            NIF:RecycleFrame(frame)
        end)
    end

    f.isMouseOver    = false
    f.pendingFadeOut = false

    f:Show()
    return f
end

function NIF:UpdateFrame()
    if self.anchorFrame then
        if not self.anchorFrame.borderTop then
            self.anchorFrame.borderTop    = self.anchorFrame:CreateTexture(nil, "BORDER")
            self.anchorFrame.borderBottom = self.anchorFrame:CreateTexture(nil, "BORDER")
            self.anchorFrame.borderLeft   = self.anchorFrame:CreateTexture(nil, "BORDER")
            self.anchorFrame.borderRight  = self.anchorFrame:CreateTexture(nil, "BORDER")
        end
        ApplyVisualsToFrame(self.anchorFrame)
    end

    for _, f in ipairs(self.activeMessages) do
        ApplyVisualsToFrame(f)
    end

    if self.previewFrame and self.previewShown then
        ApplyVisualsToFrame(self.previewFrame)
    end
end

---@param itemLink string
---@param value integer  -- total value for this event
---@param quantity integer|nil
function NIF:ShowFloatingMessage(itemLink, value, quantity)
    quantity = quantity or 1

    -- If this item already has a visible message, update it in place
    local existing = self.activeByItem[itemLink]
    if existing and existing.frame and existing.frame:IsShown() then
        local f                = existing.frame
        existing.totalQuantity = existing.totalQuantity + quantity
        existing.totalValue    = existing.totalValue + value

        -- Update text to show quantity and new value
        f.itemText:SetText(itemLink .. string.format(" x%d", existing.totalQuantity))
        local formattedValue = TT and TT.FormatCopper(existing.totalValue) or tostring(existing.totalValue)
        f.valueText:SetText(formattedValue)

        -- Restart fade timer so the merged message stays up
        local total    = tonumber(CM:GetProfileSettingSafe("lootMonitor.notableItems.displayDuration", 5))
        local fadeInT  = tonumber(CM:GetProfileSettingSafe("lootMonitor.notableItems.fadeInTime", 0.3))
        local fadeOutT = tonumber(CM:GetProfileSettingSafe("lootMonitor.notableItems.fadeOutTime", 0.3))
        if fadeInT < 0 then fadeInT = 0 end
        if fadeOutT < 0 then fadeOutT = 0 end

        local maxFade = total
        if fadeInT + fadeOutT > maxFade then
            local scale = maxFade / (fadeInT + fadeOutT)
            fadeInT     = fadeInT * scale
            fadeOutT    = fadeOutT * scale
        end
        local holdT = math.max(0, total - fadeInT - fadeOutT)

        f.fadeIn:SetDuration(fadeInT)
        f.hold:SetDuration(holdT)
        f.fadeOut:SetDuration(fadeOutT)

        f:SetAlpha(0)
        f.pendingFadeOut = false
        f.fadeGroup:Stop()
        f.fadeGroup:Play()

        return
    end

    -- Otherwise, create a new message frame

    local maxMessages = tonumber(CM:GetProfileSettingSafe("lootMonitor.notableItems.maxMessages", 5))
    if #self.activeMessages >= maxMessages then
        local oldest = table.remove(self.activeMessages, 1)
        if oldest.fadeGroup then
            oldest.fadeGroup:Stop()
        end
        self:RecycleFrame(oldest)
    end

    local f = self:AcquireMessageFrame()

    -- Icon
    local iconTex = select(5, C_Item.GetItemInfoInstant(itemLink))
    if iconTex then
        f.icon:SetTexture(iconTex)
        f.icon:Show()
    else
        f.icon:Hide()
    end

    -- Item link text: show quantity when > 1
    f.itemText:Show()
    if quantity > 1 then
        f.itemText:SetText(itemLink .. string.format(" x%d", quantity))
    else
        f.itemText:SetText(itemLink or "")
    end
    f.itemText.itemLink = itemLink

    -- Value text (total for this event)
    local formattedValue = TT and TT.FormatCopper(value or 0) or tostring(value or 0)
    f.valueText:Show()
    f.valueText:SetText(formattedValue)

    -- Hide generic text
    if f.text then
        f.text:Hide()
    end

    -- Layout after content
    ApplyVisualsToFrame(f)

    -- Timing
    local total    = tonumber(CM:GetProfileSettingSafe("lootMonitor.notableItems.displayDuration", 5))
    local fadeInT  = tonumber(CM:GetProfileSettingSafe("lootMonitor.notableItems.fadeInTime", 0.3))
    local fadeOutT = tonumber(CM:GetProfileSettingSafe("lootMonitor.notableItems.fadeOutTime", 0.3))

    if fadeInT < 0 then fadeInT = 0 end
    if fadeOutT < 0 then fadeOutT = 0 end

    local maxFade = total
    if fadeInT + fadeOutT > maxFade then
        local scale = maxFade / (fadeInT + fadeOutT)
        fadeInT     = fadeInT * scale
        fadeOutT    = fadeOutT * scale
    end
    local holdT = math.max(0, total - fadeInT - fadeOutT)

    StartFadeSequence(f, fadeInT, holdT, fadeOutT)

    table.insert(self.activeMessages, f)

    -- Track by item so repeats merge
    self.activeByItem[itemLink] = {
        frame         = f,
        totalQuantity = quantity,
        totalValue    = value,
    }

    self:ReanchorMessages()
end

function NIF:ShowPreview()
    if not self.previewFrame then
        self.previewFrame = self:AcquireMessageFrame()
    end

    self.previewFrame:ClearAllPoints()
    self.previewFrame:SetPoint("CENTER", self.anchorFrame, "CENTER", 0, 0)

    local fakeLink  = "|cffa335ee|Hitem:19019::::::::80:::::|h[Preview Thunderfury]|h|r"
    local fakeValue = TT and TT.FormatCopper(12345678) or "1234g 56s 78c"

    local iconTex   = select(5, C_Item.GetItemInfoInstant(fakeLink))
    if iconTex then
        self.previewFrame.icon:SetTexture(iconTex)
        self.previewFrame.icon:Show()
    else
        self.previewFrame.icon:Hide()
    end

    self.previewFrame.itemText.itemLink = fakeLink
    self.previewFrame.itemText:SetText(fakeLink)
    self.previewFrame.itemText:Show()

    self.previewFrame.valueText:SetText(fakeValue)
    self.previewFrame.valueText:Show()

    if self.previewFrame.text then
        self.previewFrame.text:Hide()
    end

    if self.previewFrame.fadeGroup then
        self.previewFrame.fadeGroup:Stop()
    end

    self.previewFrame.isMouseOver    = false
    self.previewFrame.pendingFadeOut = false

    -- Layout after content
    ApplyVisualsToFrame(self.previewFrame)

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
    Logger.Debug("Notable item notification frame initialized")
end
