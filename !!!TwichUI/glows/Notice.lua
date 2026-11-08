-- TwichUI: Action bar glows, the message cards
-- The short message a reminder may show as it starts (and with each repeat), drawn as a small card in the zone arrival
-- card's look: its fonts (Cinzel title, Alegreya line), its bronze rule, the colors, text size, outline, opacity, accent
-- and backdrop the player chose under Notifications > Notification appearance (modules/NotifyLook.lua, through
-- Arrival.lua's A.Typeset / A.PaintRule / A.Backdrop), and its rise-and-fade entrance (none with Reduced motion).
-- Optionally the reminder's spell or item icon beside the title. Never in chat.
--
-- Not through the notification coordinator (modules/Notify.lua): that one takes turns at the top of the screen and holds
-- cards back in combat, and these come in combat, several at once. So they stack under the arrival card's place instead
-- (at most MAX, the newest on top), and never cover it.
--
-- A card goes when its reminder is no longer due (you cast the buff, used the cooldown ...), and otherwise after the
-- seconds chosen, or stays until then when "fade out" is off. A repeat shows the same card again; it is never doubled.
--
--   NT.Show(id, r, preview)   a reminder's card (r: Logic's reminder: label, kind, detail, icon, notOnBars)
--   NT.Done(id)               its reminder is no longer due: the card fades out
--   NT.HideAll()              every card gone at once (the feature turned off, leaving the world)
--   NT.Restyle()              the notification appearance changed: cards that are up are drawn again
--   NT.Preview()              a sample card, for the settings

local R = TwichUI
local C = R.BarGlowCatalog
local BG = R.BarGlows
local NT = { made = 0 }
R.BarGlowNotice = NT

local MAX = 3
local WIDTH, HEIGHT = 460, 62
local GAP = 6
local TOP = -282           -- under the arrival card (it ends 270 below the top of the screen)
local ICON = 26
local RISE = 6
local FADE_IN, FADE_OUT, GONE = 0.35, 0.9, 0.35
local LOOK_KIND = "arrival"   -- the cards follow the zone arrival card's look (the shared one, or its own)

local cards = {}     -- shown, the newest first: { frame, id }
local pool = {}      -- frames not in use

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

local function A() return R.Arrival end
local function Grow() local a = A() return a and a.Grow and a.Grow(LOOK_KIND) or 1 end

-- Drawn with the arrival card's helpers; plain game text where those are not there.
local function Typeset(fs, role, size)
    local a = A()
    if a and a.Typeset then
        local path = role == "title" and a.FONT_TITLE or a.FONT_LINE
        a.Typeset(LOOK_KIND, fs, { role = role, path = path, size = size, fallback = role == "title" and "ZoneTextFont" or "SubZoneTextFont" })
    else
        fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    end
end

local function TextWidth(fs, limit)
    local a = A()
    if a and a.TextWidth then return a.TextWidth(fs, limit) end
    local w = fs.GetStringWidth and fs:GetStringWidth() or 0
    if type(w) ~= "number" or w ~= w then w = 0 end
    return math.min(w, limit)
end

---------------------------------------------------------------------------
-- A card
---------------------------------------------------------------------------
local function Release(card)
    for i = #cards, 1, -1 do
        if cards[i].frame == card then table.remove(cards, i) end
    end
    card.enter:Stop(); card.leave:Stop()
    card:Hide()
    card.id = nil
    pool[#pool + 1] = card
    NT.Layout()
end

local function Make()
    local card = table.remove(pool)
    if card then return card end
    card = CreateFrame("Frame", nil, UIParent)
    card:SetSize(WIDTH, HEIGHT)
    card:EnableMouse(false)
    card:Hide()
    -- the title line: the icon and the title, centred together
    card.head = CreateFrame("Frame", nil, card)
    card.head:SetPoint("TOP", card, "TOP", 0, 0)
    card.head:SetSize(WIDTH, 24)
    card.icon = card.head:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(ICON, ICON)
    card.icon:SetPoint("LEFT", card.head, "LEFT", 0, 0)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card.title = card.head:CreateFontString(nil, "OVERLAY")
    card.title:SetPoint("RIGHT", card.head, "RIGHT", 0, 0)
    card.title:SetJustifyH("CENTER")
    card.title:SetWordWrap(false)
    local a = A()
    if a and a.Rule then
        card.rule = a.Rule(card, (R.ChronicleStyle and R.ChronicleStyle.color) or {
            text = { 0.93, 0.88, 0.76 }, stone = { 0.62, 0.58, 0.51 }, bronze = { 0.55, 0.43, 0.22 },
            bronzeLo = { 0.30, 0.23, 0.13 }, gold = { 0.79, 0.64, 0.29 } })
    else
        card.rule = CreateFrame("Frame", nil, card)
        card.rule:SetSize(100, 2)
    end
    card.rule:SetPoint("TOP", card.head, "BOTTOM", 0, -5)
    card.detail = card:CreateFontString(nil, "OVERLAY")
    card.detail:SetPoint("TOP", card.rule, "BOTTOM", 0, -4)
    card.detail:SetJustifyH("CENTER")
    card.detail:SetWordWrap(false)

    -- entering: lowered at once, then rising back to its place as it fades in (the two moves add to nothing)
    local enter = card:CreateAnimationGroup()
    enter:SetToFinalAlpha(true)
    card.drop = enter:CreateAnimation("Translation")
    card.drop:SetDuration(0)
    card.drop:SetOrder(1)
    card.rise = enter:CreateAnimation("Translation")
    card.rise:SetDuration(FADE_IN)
    card.rise:SetSmoothing("OUT")
    card.rise:SetOrder(1)
    local fadeIn = enter:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(FADE_IN); fadeIn:SetSmoothing("OUT"); fadeIn:SetOrder(1)
    card.enter = enter
    -- leaving: after its time (or at once, when its reminder is done)
    local leave = card:CreateAnimationGroup()
    leave:SetToFinalAlpha(true)
    card.fadeOut = leave:CreateAnimation("Alpha")
    card.fadeOut:SetFromAlpha(1); card.fadeOut:SetToAlpha(0); card.fadeOut:SetSmoothing("IN")
    leave:SetScript("OnFinished", function() Release(card) end)
    card.leave = leave
    NT.made = NT.made + 1
    return card
end

-- The words and look of a card, for what it says; its animation is not touched (a restyle redraws it as it is).
local function Fill(card)
    local d = card.data
    local grow = Grow()
    local titleSize, detailSize = 20, 14
    Typeset(card.title, "title", titleSize)
    Typeset(card.detail, "detail", detailSize)
    card.title:SetText(d.title)
    card.detail:SetText(d.detail or "")
    card.detail:SetShown(d.detail ~= nil)
    local iconShown = d.icon ~= nil and BG.Get("noticeIcon")
    local iconSize = math.floor(ICON * grow + 0.5)
    card.icon:SetSize(iconSize, iconSize)
    card.icon:SetTexture(iconShown and d.icon or nil)
    card.icon:SetShown(iconShown and true or false)
    local titleWidth = TextWidth(card.title, WIDTH - iconSize - 10)
    card.title:SetWidth(math.max(1, titleWidth))
    local headWidth = titleWidth + (iconShown and (iconSize + 8) or 0)
    card.head:SetSize(math.max(1, headWidth), math.max(iconShown and iconSize or 0, math.ceil(24 * grow)))
    local ruleWidth = math.max(60, math.min(140, titleWidth))
    card.rule:SetWidth(ruleWidth)
    local a = A()
    if a and a.PaintRule then a.PaintRule(LOOK_KIND, card.rule, 0.8) end
    card:SetHeight(math.ceil(HEIGHT * grow))
    local widest = math.max(headWidth, ruleWidth, d.detail and TextWidth(card.detail, WIDTH) or 0)
    if a and a.Backdrop then a.Backdrop(LOOK_KIND, card, { top = card.head, bottom = d.detail and card.detail or card.rule, width = widest }) end
end

-- The cards one under another, the newest on top, in the space under the arrival card.
function NT.Layout()
    local y = TOP
    local step = math.ceil(HEIGHT * Grow()) + GAP
    for _, c in ipairs(cards) do
        c.frame:ClearAllPoints()
        c.frame:SetPoint("TOP", UIParent, "TOP", 0, y)
        y = y - step
    end
end

local function IconOf(r)
    local icon = r.icon
    if type(icon) ~= "table" then return nil end
    if icon.spell and C_Spell and C_Spell.GetSpellTexture then return Plain(C_Spell.GetSpellTexture(icon.spell)) end
    if icon.item and C_Item and C_Item.GetItemIconByID then return Plain(C_Item.GetItemIconByID(icon.item)) end
    return nil
end

-- The second line: what kind of reminder it is, or its own words (who is missing it, how many are left ...).
local function DetailOf(r)
    if r.notOnBars then return "Missing buff, not on your action bars" end
    if r.detail then return r.detail end
    local info = C.TYPE_INFO[r.kind]
    return info and info.text or nil
end

-- Starts a card's time: it fades after the chosen seconds, or stays while fading is off.
local function Time(card, preview)
    card.leave:Stop()
    if preview or BG.Get("noticeFade") then
        card.fadeOut:SetStartDelay(FADE_IN + (preview and 6 or BG.Get("noticeSeconds")))
        card.fadeOut:SetDuration(FADE_OUT)
        card.leave:Play()
    end
end

function NT.Show(id, r, preview)
    if type(id) ~= "string" or type(r) ~= "table" then return end
    local card
    for i, c in ipairs(cards) do
        if c.id == id then
            card = c.frame
            table.remove(cards, i)   -- shown again: it moves to the top
            break
        end
    end
    if not card then
        while #cards >= MAX do Release(cards[#cards].frame) end
        card = Make()
    end
    card.id = id
    card.data = { title = r.label or "?", detail = DetailOf(r), icon = IconOf(r) }
    table.insert(cards, 1, { frame = card, id = id })
    Fill(card)
    NT.Layout()
    card:SetFrameStrata(preview and (R.Notify and R.Notify.PREVIEW_STRATA or "FULLSCREEN_DIALOG") or "LOW")
    local rise = R:Enabled("arrivalReducedMotion") and 0 or RISE
    card.drop:SetOffset(0, -rise)
    card.rise:SetOffset(0, rise)
    card.enter:Stop()
    card:SetAlpha(0)
    card:Show()
    card.enter:Play()
    Time(card, preview)
end

function NT.Done(id)
    for _, c in ipairs(cards) do
        if c.id == id then
            local card = c.frame
            card.leave:Stop()
            card.fadeOut:SetStartDelay(0)
            card.fadeOut:SetDuration(GONE)
            card.leave:Play()
            return
        end
    end
end

function NT.HideAll()
    for i = #cards, 1, -1 do Release(cards[i].frame) end
end

function NT.Restyle()
    for _, c in ipairs(cards) do Fill(c.frame) end
    NT.Layout()
end

-- A sample, drawn above the settings window; it fades after a few seconds whatever the setting.
function NT.Preview()
    local id = "preview:sample"
    local spell = 1459
    local name = C_Spell and C_Spell.GetSpellName and Plain(C_Spell.GetSpellName(spell)) or "Arcane Intellect"
    NT.Show(id, { label = name, kind = "missingBuff", detail = "Missing buff (a sample)", icon = { spell = spell } }, true)
    return true
end

-- Read only.
function NT.Shown()
    local out = {}
    for i, c in ipairs(cards) do out[i] = { id = c.id, title = c.frame.data.title, detail = c.frame.data.detail, icon = c.frame.data.icon,
        frame = c.frame, fading = c.frame.leave:IsPlaying() } end
    return out
end

function NT.Snapshot() return { shown = #cards, made = NT.made } end

-- The notification appearance changed: the cards that are up follow it (NotifyLook asks Notify.Restyle).
if R.Notify and R.Notify.Restyle and hooksecurefunc then
    hooksecurefunc(R.Notify, "Restyle", function() if #cards > 0 then NT.Restyle() end end)
end
BG.Subscribe(function(what) if what == "settings" and #cards > 0 then NT.Restyle() end end)
