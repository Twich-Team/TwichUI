-- TwichUI: Cozy Sleeping Bag guide, the unlock card
-- "A new journey awaits": a quiet title card in the new-training card's manner, with no frame, shown once when the bag
-- becomes available (guides/CozyBagOffer.lua decides that and when to ask). It takes no clicks, so the world beneath it stays
-- clickable; it plays no sound and says nothing in chat. It points to the guide's button (or /tui bag) rather than opening
-- anything. The coordinator (modules/Notify.lua) lets it wait for combat, banners and other cards, and for the first-install
-- setup (the offer holds back while that is under way).
--
-- Look: it follows the New training card's appearance (modules/NotifyLook.lua scope "training"), the nearest in kind, so it
-- adds no appearance scope of its own. Its place is that card's place (R.Training.Position), so the two take turns.
-- Only a real showing marks the character as told (O.MarkAnnounced); a settings preview records nothing.

local R = TwichUI
local D = R.CozyBagData
local N = R.Notify
local Z = {}
R.CozyBagNotice = Z

local KIND = "cozybag"
local LOOK = "training"        -- the appearance scope it borrows
local FADE_IN, FADE_OUT = 0.8, 1.4
local HOLD = 6
local RISE = 8
local WIDTH = 460
local TOP_OFFSET = -260        -- the new-training card's default place
local ICON = 40
local TITLE = "A new journey awaits"

local card

local function Place(frame)
    local x, y = 0, TOP_OFFSET
    if R.Training and R.Training.Position then x, y = R.Training.Position() end
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "TOP", x, y)
end

local function Grow() return R.Arrival.Grow(LOOK) end
local function CardWidth() return math.ceil(WIDTH * Grow()) end
local function CardHeight() return math.ceil(132 * Grow()) end

local function Text(parent, path, size, fallback, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    R.Arrival.SetFont(fs, path, size, fallback)
    fs:SetShadowColor(0, 0, 0, 0.85)
    fs:SetShadowOffset(1, -1)
    fs:SetTextColor(color[1], color[2], color[3])
    return fs
end

local function Stop()
    card.anim:Stop()
    card:Hide()
    card.payload = nil
    R:Off("PLAYER_REGEN_DISABLED", Z.OnCombat)
end

local function Hide()
    if not card then return end
    Stop()
    N.Finished(KIND)
end

function Z.OnCombat() Hide() end   -- a real card makes way for a fight

function Z.IsShowing() return card ~= nil and card:IsShown() end

local function Build()
    local S, A = R.ChronicleStyle, R.Arrival
    if not (S and A and A.Rule and A.SetFont) then return false end
    local K = S.color
    card = CreateFrame("Frame", nil, UIParent)
    card:SetSize(WIDTH, CardHeight())
    Place(card)
    card:SetClampedToScreen(true)
    card:SetFrameStrata("LOW")
    card:EnableMouse(false)
    card:Hide()
    card.K = K

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(ICON, ICON)
    card.icon:SetPoint("TOP", 0, 0)
    if R.Icons and R.Icons.Apply then R.Icons.Apply(card.icon, "sleepingBag", ICON) end
    card.title = Text(card, A.FONT_TITLE, 18, "SubZoneTextFont", K.text)
    card.title:SetPoint("TOP", card.icon, "BOTTOM", 0, -4)
    card.rule = A.Rule(card, K)
    card.rule:SetWidth(110)
    card.rule:SetPoint("TOP", card.title, "BOTTOM", 0, -6)
    card.body = Text(card, A.FONT_LINE, 15, "GameFontHighlight", K.text)
    card.body:SetPoint("TOP", card.rule, "BOTTOM", 0, -10)
    card.foot = Text(card, A.FONT_LINE, 13, "GameFontHighlightSmall", K.stone)
    card.foot:SetPoint("TOP", card.body, "BOTTOM", 0, -6)

    -- The training card's motion: lowered at once, rising into place as it fades in, then fading away.
    local anim = card:CreateAnimationGroup()
    anim:SetToFinalAlpha(true)
    card.drop = anim:CreateAnimation("Translation")
    card.drop:SetDuration(0)
    card.drop:SetOrder(1)
    card.rise = anim:CreateAnimation("Translation")
    card.rise:SetSmoothing("OUT")
    card.rise:SetDuration(FADE_IN)
    card.rise:SetOrder(1)
    local fadeIn = anim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetSmoothing("OUT")
    fadeIn:SetDuration(FADE_IN)
    fadeIn:SetOrder(1)
    card.fadeOut = anim:CreateAnimation("Alpha")
    card.fadeOut:SetFromAlpha(1)
    card.fadeOut:SetToAlpha(0)
    card.fadeOut:SetSmoothing("IN")
    card.fadeOut:SetDuration(FADE_OUT)
    card.fadeOut:SetOrder(2)
    anim:SetScript("OnFinished", Hide)
    card.anim = anim
    return true
end

-- Where the guide is, said as the player can act on it now: its button when that is on screen, the command otherwise.
local function Pointer(preview)
    local O = R.CozyBagOffer
    if preview or (O and O.ButtonWanted()) then return "Open the guide from its button when you're ready." end
    return "Open the guide with /tui bag when you're ready."
end

-- Puts the text and the look on the card, for the look as it is now (the entrance is not touched).
local function Fill(preview)
    local A = R.Arrival
    local K = card.K
    card:SetWidth(CardWidth())
    card:SetHeight(CardHeight())
    A.Typeset(LOOK, card.title, { role = "title", path = A.FONT_TITLE, size = 18, fallback = "SubZoneTextFont", color = K.text })
    card.title:SetText(TITLE)
    A.PaintRule(LOOK, card.rule, 1)
    A.Typeset(LOOK, card.body, { role = "body", path = A.FONT_LINE, size = 15, fallback = "GameFontHighlight", color = K.text })
    card.body:SetText(("The %s can now be acquired."):format(D.title))
    A.Typeset(LOOK, card.foot, { role = "detail", path = A.FONT_LINE, size = 13, fallback = "GameFontHighlightSmall", color = K.stone })
    card.foot:SetText(Pointer(preview))
    local width = math.max(A.TextWidth(card.title, CardWidth()), A.TextWidth(card.body, CardWidth()), A.TextWidth(card.foot, CardWidth()), 110)
    A.Backdrop(LOOK, card, { top = card.icon, bottom = card.foot, width = width })
end

function Z.Restyle()
    if card and card:IsShown() then Fill(card.preview) end
end

local function Show(preview)
    if not card and not Build() then return false end
    Stop()
    Place(card)
    card.preview = preview
    Fill(preview)
    local rise = R:Enabled("arrivalReducedMotion") and 0 or RISE
    card.drop:SetOffset(0, -rise)
    card.rise:SetOffset(0, rise)
    card.fadeOut:SetStartDelay(HOLD)
    card:SetFrameStrata(preview and N.PREVIEW_STRATA or "LOW")
    card:SetAlpha(0)
    card:Show()
    card.anim:Play()
    if not preview then R:On("PLAYER_REGEN_DISABLED", Z.OnCombat) end
    return true
end

-- Where the card is, for the coordinator: left, bottom, right, top in screen units.
local function Bounds()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if type(width) ~= "number" or type(height) ~= "number" then return nil end
    local x, y = 0, TOP_OFFSET
    if R.Training and R.Training.Position then x, y = R.Training.Position() end
    local top, half = height + y, CardWidth() / 2
    return width / 2 + x - half, top - CardHeight(), width / 2 + x + half, top
end

local function Toasting()
    local toast = EventToastManagerFrame
    return toast and toast.IsCurrentlyToasting and toast:IsCurrentlyToasting() and true or false
end

local function Ready()
    if InCombatLockdown and InCombatLockdown() then return false end
    return not Toasting()
end

N.Register(KIND, {
    label = "Cozy Sleeping Bag",
    show = function(_, ctx)
        local shown = Show(ctx.preview)
        -- told of only when it is really on screen; a preview records nothing
        if shown and not ctx.preview and R.CozyBagOffer then R.CozyBagOffer.MarkAnnounced() end
        return shown
    end,
    dismiss = Hide,
    bounds = Bounds,
    restyle = Z.Restyle,
    hold = function() return FADE_IN + HOLD + FADE_OUT end,
    ready = Ready,
    sample = function() return { preview = true } end,
})

if R.OnSettingsClosed then R.OnSettingsClosed(function() N.DropPreviews(KIND) end) end   -- a preview never outlives the settings window
