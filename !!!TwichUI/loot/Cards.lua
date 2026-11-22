-- TwichUI: Loot Rolls, the cards
-- One card for each group-loot roll, in a bounded stack, drawn in the framed look (FrameLook's espresso and aged bronze) with
-- painted Need, Greed and Pass icons (media/loot, cut from the approved mockup by tools/make_loot_roll_art.py). Text, bars, buttons and
-- states are real frames and font strings; only the small icons are pictures.
--
--   C.Draw(card, view)       draws a "view" (a plain table, below) into a card: the one renderer, used by the live stack and by the
--                            settings window's preview, so the preview is the card
--   C.NewCard(parent, opts)  a card frame; opts.preview = nothing it does reaches the game
--   C.View(roll)             the view of a live roll (Roll.lua's record)
--   C.Ready()                the stack was built and nothing failed: automatic choices need this (a countdown must be visible)
--   C.Shows(roll)            a card for this roll is on screen
--   C.PreviewStart(rule)     a made-up roll on screen that plays through (settings' "Preview a sample roll"); sends nothing
--
-- A view: state (pending, scheduled, submitted, resolved, ended), name, icon, quality, count, typeText, sellPrice, upgrade (true or nil),
-- canNeed, canGreed, reasonNeed, reasonGreed (words), remaining and duration (seconds), choice, placed, needsConfirm, auto = { name, action,
-- remaining }, autoNote, result = { rolls, winner, allPassed, tied }, endReason, preview.
--
-- Failure: any error while drawing hands every roll back to the game's own frames (loot/Blizzard.lua) and stops automatic choices.
-- Only the player's click sends a choice from a card; a countdown's choice is Auto.lua's, through the same Roll.lua call.

local R = TwichUI
local Ru, LR, Ro = R.LootRules, R.LootRolls, R.LootRoll
local C = {}
R.LootCards = C

local MEDIA = R.PATH .. [[media\loot\]]
local WHITE = [[Interface\Buttons\WHITE8x8]]
local FONT_TITLE = R.PATH .. [[media\fonts\Cinzel-SemiBold.ttf]]
local W_CARD = 384
C.MINI_HEIGHT = 64
local PAD = 16
local ROW_H = 16

local COL = {
    ivory = { 0.93, 0.90, 0.82 }, dim = { 0.74, 0.69, 0.60 }, quiet = { 0.58, 0.54, 0.47 },
    gold = { 0.96, 0.78, 0.36 }, sage = { 0.58, 0.83, 0.36 }, bronze = { 0.58, 0.43, 0.24 }, bronzeHi = { 0.80, 0.63, 0.34 },
    face = { 0.150, 0.112, 0.086 }, faceHot = { 0.215, 0.160, 0.118 }, facePress = { 0.105, 0.078, 0.060 },
    faceOn = { 0.285, 0.190, 0.095 }, track = { 0.055, 0.045, 0.038 }, red = { 0.80, 0.36, 0.30 },
}

-- The card wears the settings look (R.CraftLook: the sculpted bronze frame, quiet leather, painted buttons and chips), with the same
-- ivory, dim, stone and antique gold as the settings window, when the core has them; the colors above are its fallback.
do
    local pal = R.Look and R.Look.pal
    if pal and pal.text then
        COL.ivory, COL.dim, COL.quiet, COL.gold, COL.sage = pal.text, pal.textDim, pal.stone, pal.bronzeText, pal.sage
    end
end

-- A painted sheet (a button, a chip) on a host; a stand-in that draws nothing when the core's look is not there.
local function Sheet(host, skin, opts)
    local CL = R.CraftLook
    if CL and CL.Sheet then return CL.Sheet(host, skin, opts) end
    return { SetSkin = function() end, SetTint = function() end, SetShown = function() end, SetAlpha = function() end }
end

-- Tooltips. Info explains in the card's own quiet words; Tip is the red one for a choice that is not available.
local function Info(btn, title, line)
    btn.onTip = function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, COL.ivory[1], COL.ivory[2], COL.ivory[3])
        if line then GameTooltip:AddLine(line, COL.dim[1], COL.dim[2], COL.dim[3], true) end
        GameTooltip:Show()
    end
end
local function Tip(btn, title, line)
    btn.onTip = function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title)
        if line then GameTooltip:AddLine(line, 1, 0.5, 0.45, true) end
        GameTooltip:Show()
    end
end

-- A part of the card that explains itself on hover: fn(frame, card) fills GameTooltip (SetOwner first) from the card's current view.
local function Hover(frame, fn)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        local card = self:GetParent():GetParent()
        if card and card.view then fn(self, card, card.view) end
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Lines(owner, title, lines, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(title, COL.ivory[1], COL.ivory[2], COL.ivory[3])
    for _, text in ipairs(lines or {}) do GameTooltip:AddLine(text, COL.dim[1], COL.dim[2], COL.dim[3], true) end
    GameTooltip:Show()
end

-- Seconds a card takes to fade in or out (0: it appears or goes at once). "Animate cards" is the master switch.
local function Fade(which)
    if not LR.Get("animate") then return 0 end
    return LR.Get(which) / 1000
end
C.FadeSeconds = Fade

local stack, built, failed
local cards = {}          -- the pool
local shown = {}          -- [roll key] = card
local leaving = {}        -- cards fading out (a card that just lost its roll); not in `shown`, not free
local driver, elapsed = false, 0
local ChoiceLabel = { need = "Need", greed = "Greed", pass = "Pass" }

local function Hex(c) return ("|cff%02x%02x%02x"):format(c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5) end
local function Paint(t, c, a) t:SetColorTexture(c[1], c[2], c[3], a or 1) end

local function Font(parent, size, kind, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local path = STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]]
    fs:SetFont(path, size, "")
    local CL = R.CraftLook
    if CL and CL.Font then
        -- the settings window's type: Spectral for the item's name, Alegreya Sans for the rest (the game's own for Korean, Chinese, Russian)
        CL.Font(fs, size, false, kind == "title" and "serif" or nil)
    elseif kind == "title" then
        local locale = GetLocale and GetLocale()
        if not (locale == "koKR" or locale == "zhCN" or locale == "zhTW" or locale == "ruRU") then fs:SetFont(FONT_TITLE, size, "") end
    end
    local c = color or COL.ivory
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("MIDDLE")
    fs:SetWordWrap(false)
    return fs
end

local function TextSize(fs, size)
    local file, _, flags = fs:GetFont()
    if file then fs:SetFont(file, size, flags or "") end
end

-- Fit only on redraw; tooltips retain the complete item name.
function C.FitItemName(label, name)
    label:SetText(name)
    local last = #name
    while last > 0 and label:GetStringWidth() > label:GetWidth() do
        last = last - 1
        while last > 0 and name:byte(last + 1) >= 128 and name:byte(last + 1) < 192 do last = last - 1 end
        label:SetText(name:sub(1, last) .. "...")
    end
end

-- a 1 unit outline of four textures on a frame (alpha-aware: edges are drawn inside the frame)
local function Outline(frame, layer, sub)
    local o = {}
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local t = frame:CreateTexture(nil, layer or "BORDER", nil, sub or 0)
        o[side] = t
    end
    o.top:SetPoint("TOPLEFT"); o.top:SetPoint("TOPRIGHT"); o.top:SetHeight(1)
    o.bottom:SetPoint("BOTTOMLEFT"); o.bottom:SetPoint("BOTTOMRIGHT"); o.bottom:SetHeight(1)
    o.left:SetPoint("TOPLEFT"); o.left:SetPoint("BOTTOMLEFT"); o.left:SetWidth(1)
    o.right:SetPoint("TOPRIGHT"); o.right:SetPoint("BOTTOMRIGHT"); o.right:SetWidth(1)
    function o:Color(c, a)
        for _, t in pairs(self) do if type(t) == "table" and t.SetColorTexture then Paint(t, c, a) end end
    end
    function o:Width(n)
        self.top:SetHeight(n); self.bottom:SetHeight(n); self.left:SetWidth(n); self.right:SetWidth(n)
    end
    return o
end

-- A price as gold, silver and copper, each a number with the game's own coin picture after it, from the highest coin it has down to
-- copper (zero silver in the middle still shows). The numbers are tinted like the coins.
local COIN_ART = { gold = [[Interface\MoneyFrame\UI-GoldIcon]], silver = [[Interface\MoneyFrame\UI-SilverIcon]], copper = [[Interface\MoneyFrame\UI-CopperIcon]] }
local COIN_INK = { gold = { 1.00, 0.84, 0.30 }, silver = { 0.80, 0.82, 0.86 }, copper = { 0.88, 0.56, 0.36 } }
local function CoinText(copper, size)
    if type(copper) ~= "number" or copper ~= copper or copper <= 0 or copper == math.huge then return nil end
    copper = math.floor(copper)
    size = size or 13
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    local out = {}
    local function Add(kind, n)
        out[#out + 1] = ("%s%s|r|T%s:%d:%d:2:0|t"):format(Hex(COIN_INK[kind]), BreakUpLargeNumbers and gold > 0 and kind == "gold" and BreakUpLargeNumbers(n) or tostring(n),
            COIN_ART[kind], size, size)
    end
    if gold > 0 then Add("gold", gold) end
    if gold > 0 or silver > 0 then Add("silver", silver) end
    Add("copper", rest)
    return table.concat(out, "  ")
end
C.CoinText = CoinText

---------------------------------------------------------------------------
-- A choice button: Need, Greed, Pass, Roll now, Stop auto roll
---------------------------------------------------------------------------
local function Button(parent, icon, label)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(34)
    b.art = Sheet(b, "button", { layer = "ARTWORK", sub = 4, corner = 8 })   -- the settings window's painted button
    b.icon = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.icon:SetSize(26, 26)
    b.icon:SetTexture(MEDIA .. icon)
    b.text = Font(b, 14, "body")
    b.text:SetText(label)
    b.label = label
    b.state = "normal"
    function b:Layout()
        local press = self.press and -1 or 0
        TextSize(self.text, self.compact and 11 or 14)
        self.icon:SetSize(self.compact and 16 or 26, self.compact and 16 or 26)
        self.icon:ClearAllPoints(); self.text:ClearAllPoints()
        if self.compact then
            self.icon:SetPoint("CENTER", self, "CENTER", 0, 6 + press)
            self.text:SetWidth(self:GetWidth() - 4); self.text:SetJustifyH("CENTER")
            self.text:SetPoint("BOTTOM", self, "BOTTOM", 0, 3 + press)
        else
            self.text:SetWidth(0); self.text:SetJustifyH("LEFT")
            local total = 26 + 8 + (self.text:GetStringWidth() or 40)
            self.icon:SetPoint("LEFT", self, "LEFT", math.max(8, (self:GetWidth() - total) / 2), 0)
            self.text:SetPoint("LEFT", self.icon, "RIGHT", 8, press)
        end
    end
    function b:Paint()
        local st = self.state
        local on, hot, press, off = st == "selected", self.hot and st ~= "disabled", self.press and st ~= "disabled", st == "disabled" or st == "unavailable"
        local skin = off and "button-off" or (on and "primary") or (press and "button-down") or (hot and "button-hot") or "button"
        self.art:SetSkin(skin)
        self.icon:SetDesaturated(off)
        self.icon:SetAlpha(off and 0.5 or 1)
        local c = off and COL.quiet or COL.ivory
        self.text:SetTextColor(c[1], c[2], c[3])
        self:Layout()
    end
    function b:SetVisual(state) if self.state ~= state then self.state = state; self:Paint() end end
    b:SetScript("OnEnter", function(self) self.hot = true; self:Paint(); if self.onTip then self:onTip() end end)
    b:SetScript("OnLeave", function(self) self.hot = false; self.press = false; self:Paint(); GameTooltip:Hide() end)
    b:SetScript("OnMouseDown", function(self) self.press = true; self:Paint() end)
    b:SetScript("OnMouseUp", function(self) self.press = false; self:Paint() end)
    b:Paint()
    return b
end

---------------------------------------------------------------------------
-- A pill: a small bordered label with an optional icon ("Potential upgrade", "Auto Greed", "Resolved")
---------------------------------------------------------------------------
local function Pill(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetHeight(20)
    p.art = Sheet(p, "chip", { layer = "ARTWORK", sub = 4, corner = 10 })   -- the settings window's chip
    p.art:SetSkin("chip")
    p.icon = p:CreateTexture(nil, "OVERLAY", nil, 2)
    p.icon:SetSize(14, 14)
    p.text = Font(p, 11, "body")
    p:EnableMouse(true)
    p:SetScript("OnEnter", function(self)
        local card = self:GetParent():GetParent()
        if self.tip and card and card.view then self.tip(self, card, card.view) end
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function p:Set(text, icon, tone)
        local tc = tone == "ok" and COL.sage or (tone == "gold" and COL.gold) or COL.dim
        if tone == "ok" then self.art:SetTint(0.80, 1.0, 0.72, 1) elseif tone == "gold" then self.art:SetTint(1.0, 0.92, 0.68, 1) else self.art:SetTint(1, 1, 1, 1) end
        self.text:SetText(text)
        self.text:SetTextColor(tc[1], tc[2], tc[3])
        self.icon:ClearAllPoints()
        self.text:ClearAllPoints()
        local w = (self.text:GetStringWidth() or 40)
        if icon then
            self.icon:SetTexture(MEDIA .. icon)
            self.icon:Show()
            self.icon:SetPoint("LEFT", self, "LEFT", 6, 0)
            self.text:SetPoint("LEFT", self.icon, "RIGHT", 4, 0)
            self:SetWidth(w + 6 + 14 + 4 + 8)
        else
            self.icon:Hide()
            self.text:SetPoint("LEFT", self, "LEFT", 8, 0)
            self:SetWidth(w + 16)
        end
    end
    return p
end

---------------------------------------------------------------------------
-- A card
---------------------------------------------------------------------------
local ResultRow
function C.NewCard(parent, opts)
    local FL = R.FrameLook
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(W_CARD, 150)
    card.preview = opts and opts.preview or false
    local CL = R.CraftLook
    if CL and CL.Frame and CL.Tile and CL.QuietTile and CL.LegacyRails then
        -- the settings window's materials, as the Workshop's window wears them: neutral espresso, quiet leather, the sculpted bronze frame
        card.shell = FL.Shell(card, { below = true })
        if card.shell.grain then card.shell.grain:Hide() end
        CL.Tile(card.shell, "BACKGROUND", -4, "dark", 1, { 0.90, 0.94, 0.98 }):SetAllPoints(card.shell.interior)
        CL.QuietTile(card.shell, "outer", "BACKGROUND", -3):SetAllPoints(card.shell.interior)
        CL.LegacyRails(card.shell, false)
        card.frameArt = CL.Frame(card.shell)
    else
        card.shell = FL.Shell(card, { below = false, style = { interior = { 0.082, 0.064, 0.052 }, grainInterior = 0.045 } })
    end
    card.body = CreateFrame("Frame", nil, card)
    card.body:SetAllPoints()
    card.body:SetFrameLevel(card:GetFrameLevel() + 3)
    local body = card.body

    -- the item
    card.iconFrame = CreateFrame("Frame", nil, body)
    card.iconFrame:SetSize(46, 46)
    card.iconFrame:SetPoint("TOPLEFT", PAD, -16)
    card.iconBack = card.iconFrame:CreateTexture(nil, "BACKGROUND")
    card.iconBack:SetAllPoints(); Paint(card.iconBack, { 0.04, 0.03, 0.03 })
    card.icon = card.iconFrame:CreateTexture(nil, "ARTWORK")
    card.icon:SetPoint("TOPLEFT", 3, -3); card.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    card.iconRim = Outline(card.iconFrame, "OVERLAY", 1)
    card.iconRim:Width(2)
    card.count = Font(card.iconFrame, 11, "body")
    card.count:SetPoint("BOTTOMRIGHT", -3, 3)
    -- the item's own tooltip, on the icon and the name beside it (a pill or the price line sits over its own part)
    card.iconHit = CreateFrame("Frame", nil, body)
    card.iconHit:SetPoint("TOPLEFT", card.iconFrame, "TOPLEFT", 0, 0)
    card.iconHit:SetPoint("BOTTOMRIGHT", body, "TOPRIGHT", -40, -62)
    card.iconHit:EnableMouse(true)
    card.iconHit:SetScript("OnEnter", function(self)
        local c = self:GetParent():GetParent()
        if c.view then C.ItemTip(self, c.view) end
    end)
    card.iconHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    card.name = Font(body, 15, "title")
    card.name:SetPoint("TOPLEFT", 70, -15)
    card.name:SetWidth(W_CARD - 70 - 36)
    card.sub = Font(body, 12, "body", COL.dim)
    card.sub:SetPoint("TOPLEFT", 70, -35)
    card.sub:SetWidth(170)
    card.line3 = Font(body, 11, "body", COL.dim)
    card.line3:SetPoint("TOPLEFT", 70, -53)
    card.line3:SetWidth(210)
    card.line3Icon = body:CreateTexture(nil, "OVERLAY")
    card.line3Icon:SetSize(14, 14)

    card.close = CreateFrame("Button", nil, body)
    card.close:SetSize(20, 20)
    card.close:SetPoint("TOPRIGHT", -12, -12)
    card.close.art = Sheet(card.close, "button", { layer = "ARTWORK", sub = 4, corner = 6 })
    card.close.art:SetSkin("button")
    card.close.text = Font(card.close, 12, "body"); card.close.text:SetPoint("CENTER", 0, 0); card.close.text:SetText("x")
    card.close:SetScript("OnEnter", function(self)
        self.art:SetSkin("button-hot")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local c = self:GetParent():GetParent()
        if c.live then
            GameTooltip:SetText("Use the game's roll window")
            GameTooltip:AddLine("Closes this card and gives the roll back to the game's own window. A pending automatic choice for it is stopped.", 0.9, 0.85, 0.75, true)
        else
            GameTooltip:SetText("Dismiss")
        end
        GameTooltip:Show()
    end)
    card.close:SetScript("OnLeave", function(self) self.art:SetSkin("button"); GameTooltip:Hide() end)
    card.close:SetScript("OnMouseDown", function(self) self.art:SetSkin("button-down") end)
    card.close:SetScript("OnMouseUp", function(self) self.art:SetSkin(self:IsMouseOver() and "button-hot" or "button") end)
    card.close:SetScript("OnClick", function(self) local c = self:GetParent():GetParent(); if c.onDismiss then c.onDismiss(c) end end)

    card.pillTop = Pill(body)
    card.pillTop:SetPoint("TOPRIGHT", -34, -34)
    card.pillBottom = Pill(body)
    card.pillBottom:SetPoint("TOPRIGHT", -34, -58)

    -- the note under the header (a confirmation to give, a rule that could not decide)
    card.note = Font(body, 11, "body", COL.dim)
    card.note:SetWidth(W_CARD - PAD * 2)

    -- the countdown
    card.timer = CreateFrame("Frame", nil, body)
    card.timer:SetHeight(14)
    card.timer.track = card.timer:CreateTexture(nil, "BACKGROUND"); card.timer.track:SetAllPoints(); Paint(card.timer.track, COL.track)
    card.timer.rim = Outline(card.timer, "BORDER", 1); card.timer.rim:Color({ 0.36, 0.27, 0.16 })
    card.timer.fill = card.timer:CreateTexture(nil, "ARTWORK")
    card.timer.fill:SetPoint("TOPLEFT", 1, -1); card.timer.fill:SetPoint("BOTTOMLEFT", 1, 1)
    card.timer.hi = card.timer:CreateTexture(nil, "OVERLAY")
    card.timer.hi:SetPoint("TOPLEFT", card.timer.fill, "TOPLEFT", 0, 0); card.timer.hi:SetPoint("TOPRIGHT", card.timer.fill, "TOPRIGHT", 0, 0); card.timer.hi:SetHeight(3)
    card.time = Font(body, 13, "body")
    card.time:SetJustifyH("RIGHT")
    Hover(card.timer, function(self, c, v) C.TimerTip(self, v) end)
    card.line3Hit = CreateFrame("Frame", nil, body)
    card.line3Hit:SetSize(210, 16)
    Hover(card.line3Hit, function(self, c, v) C.LineTip(self, v) end)

    -- choices
    card.buttons = {
        need = Button(body, "need", "Need"), greed = Button(body, "greed", "Greed"), pass = Button(body, "pass", "Pass"),
        now = Button(body, "dice", "Roll now"), stop = Button(body, "stop", "Stop auto roll"),
    }
    for key, b in pairs(card.buttons) do
        b.key = key
        b:SetScript("OnClick", function(self) local c = self:GetParent():GetParent(); if c.onChoice then c.onChoice(c, self.key) end end)
    end

    -- after a choice
    card.status = CreateFrame("Frame", nil, body)
    card.status:SetHeight(34)
    if R.CraftLook and R.CraftLook.PanelFace then
        R.CraftLook.PanelFace(card.status, "canvas")   -- the settings window's deep well
    else
        card.status.face = card.status:CreateTexture(nil, "BACKGROUND"); card.status.face:SetAllPoints(); Paint(card.status.face, { 0.12, 0.092, 0.07 })
        card.status.rim = Outline(card.status, "BORDER", 1); card.status.rim:Color({ 0.30, 0.24, 0.17 })
    end
    card.status.icon = card.status:CreateTexture(nil, "OVERLAY"); card.status.icon:SetSize(24, 24); card.status.icon:SetPoint("LEFT", 8, 0)
    card.status.text = Font(card.status, 12, "body")
    card.status.text:SetPoint("LEFT", card.status.icon, "RIGHT", 8, 0)
    card.status.text:SetPoint("RIGHT", -8, 0)

    -- the results
    card.rows = {}
    for i = 1, 5 do card.rows[i] = ResultRow(body) end
    card.divider = body:CreateTexture(nil, "ARTWORK"); card.divider:SetWidth(1); Paint(card.divider, { 0.28, 0.21, 0.15 })
    card.banner = CreateFrame("Frame", nil, body)
    card.banner:SetHeight(28)
    card.banner.art = Sheet(card.banner, "button", { layer = "ARTWORK", sub = 4, corner = 8 })
    card.banner.icon = card.banner:CreateTexture(nil, "OVERLAY"); card.banner.icon:SetSize(20, 20)
    card.banner.icon:SetTexture(MEDIA .. "crown")
    card.banner.text = Font(card.banner, 14, "body")
    card.banner.text:SetJustifyH("CENTER")

    card.toggle = CreateFrame("Button", nil, card)
    card.toggle:SetSize(20, 20); card.toggle:SetFrameLevel(card:GetFrameLevel() + 20)
    card.toggle.art = Sheet(card.toggle, "button", { layer = "ARTWORK", corner = 6 })
    if R.Look and R.Look.Chevron then
        card.toggle.up = R.Look.Chevron(card.toggle, card.toggle, "CENTER", 0, 0, false, COL.gold)
        card.toggle.down = R.Look.Chevron(card.toggle, card.toggle, "CENTER", 0, 0, true, COL.gold)
    else
        card.toggle.text = Font(card.toggle, 13, "body"); card.toggle.text:SetPoint("CENTER")
    end
    card.toggle:SetScript("OnEnter", function(self)
        self.art:SetSkin("button-hot")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(card.view and card.view.displayMode == "collapsed" and "Expand card" or "Collapse card")
        GameTooltip:AddLine("Only changes this roll's presentation. Your roll choice and timer stay the same.", 0.82, 0.77, 0.66, true)
        GameTooltip:Show()
    end)
    card.toggle:SetScript("OnLeave", function(self) self.art:SetSkin("button"); GameTooltip:Hide() end)
    card.toggle:SetScript("OnMouseDown", function(self) self.art:SetSkin("button-down") end)
    card.toggle:SetScript("OnMouseUp", function(self) self.art:SetSkin(self:IsMouseOver() and "button-hot" or "button") end)
    card.toggle:SetScript("OnClick", function() C.ToggleDisplay(card) end)

    -- entrance
    card.enter = 1
    return card
end

ResultRow = function(parent)
    local row = { frame = CreateFrame("Frame", nil, parent) }
    row.frame:SetSize(160, ROW_H)
    row.dot = row.frame:CreateTexture(nil, "ARTWORK"); row.dot:SetSize(6, 6); row.dot:SetPoint("LEFT", 0, 0)
    row.name = Font(row.frame, 12, "body"); row.name:SetPoint("LEFT", 12, 0); row.name:SetWidth(78)
    row.choice = Font(row.frame, 12, "body", COL.dim); row.choice:SetPoint("LEFT", row.name, "RIGHT", 2, 0); row.choice:SetWidth(46)
    row.roll = Font(row.frame, 12, "body", COL.gold); row.roll:SetPoint("RIGHT", 0, 0); row.roll:SetWidth(22); row.roll:SetJustifyH("RIGHT")
    return row
end

function C.DisplayToggle(card, mode, victory)
    local compact = mode == "collapsed"
    card.toggle:ClearAllPoints(); card.toggle:SetPoint("TOPRIGHT", card, "TOPRIGHT", victory and -18 or compact and -12 or -36, victory and (compact and -22 or -15) or -12)
    if card.toggle.up then
        for _, t in ipairs(card.toggle.up) do t:SetShown(compact) end
        for _, t in ipairs(card.toggle.down) do t:SetShown(not compact) end
    elseif card.toggle.text then card.toggle.text:SetText(compact and "+" or "-") end
    card.toggle:Enable(); card.toggle:Show()
end

function C.ToggleDisplay(card)
    local v = card.view
    if not v then return end
    local mode = v.displayMode == "collapsed" and "expanded" or "collapsed"
    if v.victory then return R.LootVictory.SetDisplay(v, mode) end
    if v.preview then
        if card.onDisplay then return card.onDisplay(card, mode) end
        v.displayMode = mode; C.Draw(card, v); return
    end
    local roll = Ro.ByKey(card.rollKey)
    if roll then return Ro.SetDisplay(roll, mode) end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function Quality(view)
    local q = view.quality
    local c = Ru.QUALITY_COLOR[q] or Ru.QUALITY_COLOR[1]
    return c, Ru.QualityName(q)
end

local function Hide(...)
    for i = 1, select("#", ...) do
        local o = select(i, ...)
        if o then o:Hide() end
    end
end

local function Seconds(s)
    if s == nil then return "" end
    if s >= 10 then return ("%ds"):format(math.ceil(s)) end
    return ("%.1fs"):format(math.max(0, s))
end

local function Place(frame, card, x, y, w)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
    if w then frame:SetWidth(w) end
    frame:Show()
end

local WORD = { need = "Need", greed = "Greed", pass = "Pass", transmog = "Transmog", none = "No roll" }

-- "AARRGGBB" as r, g, b (0..1)
local function Rgb(hex)
    local r, g, b = hex:match("^%x%x(%x%x)(%x%x)(%x%x)$")
    if not r then return 1, 1, 1 end
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

-- The bar's file: the player's texture, or a flat fill when it is gone (the choice stays saved; the card never shows a hole).
local function BarFile()
    local id = LR.Get("barTexture")
    local MS = R.MenuStyle
    local file = id ~= "solid" and MS and MS.StatusBars and MS.StatusBars.Resolve and MS.StatusBars.Resolve(id) or nil
    return file or WHITE, file ~= nil and file ~= WHITE
end

-- The bar's color for the time left: the rule's own color while a rule counts down, else one color, or (the default) plenty / half gone /
-- nearly out.
function C.BarColor(frac, scheduled, expired)
    local key
    if expired then key = "barColorExpired"
    elseif scheduled then key = "barColorRule"
    elseif not LR.Get("barShift") or frac > 0.5 then key = "barColorHigh"
    elseif frac > 0.2 then key = "barColorMid"
    else key = "barColorLow" end
    return Rgb(LR.Get(key))
end

-- Colors, texture, height and position of the countdown for the time left.
local function Timer(card, remaining, duration, x, width, y, expired)
    local t = card.timer
    t:SetHeight(card.compact and 6 or LR.Get("barHeight"))
    Place(t, card, x, y, width)
    local frac = duration and duration > 0 and math.max(0, math.min(1, (remaining or 0) / duration)) or 0
    local fill = t.fill
    local file, textured = BarFile()
    fill:SetWidth(math.max(0.001, (width - 2) * frac))
    if t.file ~= file then t.file = file; fill:SetTexture(file) end
    if textured then fill:SetTexCoord(0, math.max(0.001, frac), 0, 1) else fill:SetTexCoord(0, 1, 0, 1) end
    local r, g, b = C.BarColor(frac, card.view and card.view.state == "scheduled", expired)
    fill:SetVertexColor(r, g, b, 1)
    local tr, tg, tb = Rgb(LR.Get("barTrack"))
    t.track:SetColorTexture(tr, tg, tb, 1)
    t.hi:SetColorTexture(1, 1, 1, 0.22)
    t.hi:SetShown(frac > 0 and LR.Get("barShine"))
end

-- The countdown's bar and number (what changes every step; Draw places them, this only refreshes them).
function C.PaintTimer(card, view)
    local body, y = card.body, card.timerY
    local inner = W_CARD - PAD * 2
    local scheduled = view.state == "scheduled" and view.auto
    if card.compact then
        Timer(card, view.remaining, view.duration, 12, W_CARD - 24, 54)
        card.time:ClearAllPoints(); card.time:SetPoint("TOPRIGHT", body, "TOPRIGHT", -8, -31)
        card.time:SetSize(28, 16); card.time:SetJustifyH("RIGHT"); TextSize(card.time, 11)
        card.time:SetText(Seconds(view.remaining)); card.time:Show()
        if scheduled then card.sub:SetText("Auto " .. (ChoiceLabel[view.auto.action] or "") .. " · " .. Seconds(view.auto.remaining)) end
        return
    end
    TextSize(card.time, 13)
    local numberW = scheduled and 176 or 48
    local remaining = scheduled and view.auto.remaining or view.remaining
    local duration = scheduled and (view.auto.delay or 3) or view.duration
    local showBar = LR.Get("timer") ~= "number"
    local showNum = LR.Get("timer") ~= "bar"
    if scheduled then showBar, showNum = true, true end   -- a countdown is always fully visible
    local barW = showNum and (inner - numberW - 8) or inner
    if showBar then Timer(card, remaining, duration, PAD, barW, y) else card.timer:Hide() end
    card.time:ClearAllPoints()
    if showNum and not showBar then
        card.time:SetJustifyH("LEFT")
        card.time:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -(y - 1))
        card.time:SetSize(inner, 16)
    else
        card.time:SetJustifyH("RIGHT")
        card.time:SetPoint("TOPRIGHT", body, "TOPRIGHT", -PAD, -(y - 1))
        card.time:SetSize(numberW, 16)
    end
    if showNum then
        card.time:SetText(scheduled and ("Rolling automatically...  " .. Seconds(remaining)) or Seconds(remaining))
        card.time:Show()
    else
        card.time:Hide()
    end
end

---------------------------------------------------------------------------
-- What hovering explains
---------------------------------------------------------------------------
C.CHOICE_HELP = {
    need = "Roll Need if you intend to use this item yourself. A Need roll beats any Greed roll.",
    greed = "Roll Greed if you would like the item but don't need it. It wins only if nobody rolls Need.",
    pass = "Pass if you don't want it. Nothing is rolled for you.",
}
local WHY_HINT = "From TwichUI's gear comparison (Gear upgrades). A hint to weigh, never a reason to roll Need by itself."

-- The item: the game's own tooltip for the roll (which already carries the gear comparison's line); the item's link when the roll is
-- over; a made-up one on a sample card.
function C.ItemTip(owner, view)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if view.preview then
        local qc = Ru.QUALITY_COLOR[view.quality] or Ru.QUALITY_COLOR[1]
        GameTooltip:SetText(view.name or "Sample item", qc[1], qc[2], qc[3])
        for _, line in ipairs(view.sampleLines or {}) do GameTooltip:AddLine(line, 1, 1, 1) end
        if view.sellPrice then GameTooltip:AddLine("Sell price:  " .. (CoinText(view.sellPrice) or ""), 1, 1, 1) end
        GameTooltip:AddLine("A sample item, made up for the preview.", COL.quiet[1], COL.quiet[2], COL.quiet[3], true)
        GameTooltip:Show()
        return
    end
    local done = false
    if view.rollID and GameTooltip.SetLootRollItem and (view.state == "pending" or view.state == "scheduled" or view.state == "submitted") then
        done = pcall(GameTooltip.SetLootRollItem, GameTooltip, view.rollID)
        if done and GameTooltip.NumLines and GameTooltip:NumLines() == 0 then done = false end
    end
    if not done and view.link and GameTooltip.SetHyperlink then done = pcall(GameTooltip.SetHyperlink, GameTooltip, view.link) end
    if done then GameTooltip:Show() else GameTooltip:Hide() end
end

-- The countdown bar: what it counts, and what ends it.
function C.TimerTip(owner, view)
    if view.state == "scheduled" and view.auto then
        Lines(owner, "Rule countdown", {
            ("%s will choose %s in %s unless you stop it."):format(view.auto.name or "A rule", ChoiceLabel[view.auto.action] or "a choice", Seconds(view.auto.remaining)),
            "Stop auto roll cancels it, Roll now does it at once, and choosing yourself always wins.",
        })
    elseif view.state == "ended" and view.endReason == "expired" then
        Lines(owner, "Ran out", { "The roll closed before you chose, so nothing was rolled for you." })
    else
        Lines(owner, "Time to roll", {
            ("%s left before this roll closes."):format(Seconds(view.remaining)),
            "If you haven't chosen by then, you pass.",
        })
    end
end

-- The line under the name: the rule that is counting down, or what a vendor pays.
function C.LineTip(owner, view)
    if view.displayMode == "collapsed" and view.needsConfirm then
        Lines(owner, "Confirm in game", { "Confirm in the game's window to roll " .. (view.confirmWord or "this") .. "." })
    elseif view.displayMode == "collapsed" and view.autoNote and view.state == "pending" then
        Lines(owner, "Manual choice", { view.autoNote })
    elseif view.state == "scheduled" and view.auto then
        Lines(owner, "Rule: " .. (view.auto.name or ""), {
            ("This rule matched the item and will choose %s after %s second%s."):format(ChoiceLabel[view.auto.action] or "a choice",
                tostring(view.auto.delay or 3), (view.auto.delay or 3) == 1 and "" or "s"),
            "You can stop it or roll at once; the rules are on the Loot rules tab.",
        })
    elseif view.sellPrice then
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText("Vendor price", COL.ivory[1], COL.ivory[2], COL.ivory[3])
        GameTooltip:AddLine(CoinText(view.sellPrice) or "", 1, 1, 1)
        if (view.count or 1) > 1 then
            GameTooltip:AddLine(("%d together: %s"):format(view.count, CoinText(view.sellPrice * view.count) or ""), COL.dim[1], COL.dim[2], COL.dim[3], true)
        end
        GameTooltip:AddLine("What a vendor pays for one. What it sells for elsewhere may be more.", COL.dim[1], COL.dim[2], COL.dim[3], true)
        GameTooltip:Show()
    end
end

C.PillTips = {
    auto = function(self, card, v)
        Lines(self, "Automatic " .. (ChoiceLabel[v.auto and v.auto.action] or "choice"), {
            ("The rule \"%s\" will choose it for you when the countdown ends."):format(v.auto and v.auto.name or ""),
            "Stop auto roll cancels it; choosing yourself always wins.",
        })
    end,
    sent = function(self, card, v)
        Lines(self, v.placed and "Chosen" or "Sending", { v.placed and ("You chose %s. The result shows when everyone has rolled."):format(ChoiceLabel[v.choice] or "a choice")
            or "Sent to the game; it confirms in a moment." })
    end,
    resolved = function(self, card, v) Lines(self, "Resolved", { "Everyone has rolled. Who rolled what, and who won, is below when the game gives it." }) end,
    won = function(self, card, v) Lines(self, "You won", { "The item is yours, or will be in your bags shortly." }) end,
    expired = function(self, card, v) Lines(self, "Expired", { "The roll closed before you chose, so nothing was rolled for you." }) end,
    closed = function(self, card, v) Lines(self, "Closed", { "This roll was closed." }) end,
    -- why the gear comparison thinks it may be an upgrade: its own words, as the item's tooltip shows them when the reveal key is held
    upgrade = function(self, card, v)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Potential upgrade", COL.gold[1], COL.gold[2], COL.gold[3])
        local lines = v.upgradeLines
        if not lines then
            local GH = R.GearHints
            lines = v.judged and GH and GH.DetailLines and GH.DetailLines(v.judged) or nil
        end
        local any = false
        for _, l in ipairs(lines or {}) do
            if type(l[1]) == "string" and l[1] ~= " " then
                GameTooltip:AddLine(l[1], l[2] or 1, l[3] or 1, l[4] or 1, l[5] or false)
                any = true
            end
        end
        if not any then GameTooltip:AddLine("TwichUI's gear comparison thinks this may be better than what you wear.", COL.dim[1], COL.dim[2], COL.dim[3], true) end
        GameTooltip:AddLine(WHY_HINT, COL.quiet[1], COL.quiet[2], COL.quiet[3], true)
        GameTooltip:Show()
    end,
}

local function CompactLayout(card, view)
    local body = card.body
    card.iconFrame:ClearAllPoints(); card.iconFrame:SetPoint("TOPLEFT", 10, -10); card.iconFrame:SetSize(38, 38)
    card.iconHit:ClearAllPoints(); card.iconHit:SetPoint("TOPLEFT", card.iconFrame, "TOPLEFT", 0, 0)
    card.iconHit:SetPoint("BOTTOMRIGHT", body, "TOPLEFT", 198, -50)
    card.name:ClearAllPoints(); card.name:SetPoint("TOPLEFT", 58, -9); card.name:SetSize(144, 18); TextSize(card.name, 14)
    C.FitItemName(card.name, view.name or "Loot")
    card.sub:ClearAllPoints(); card.sub:SetPoint("TOPLEFT", 58, -31); card.sub:SetSize(136, 16); TextSize(card.sub, 11)
    card.sub:SetText(view.needsConfirm and "Confirm in game" or view.autoNote and "Manual choice" or Ru.QualityName(view.quality))
    Hide(card.line3, card.line3Icon, card.line3Hit, card.note, card.pillBottom, card.banner, card.divider, card.close)
    if view.needsConfirm or view.autoNote or view.state == "scheduled" then
        card.line3Hit:ClearAllPoints(); card.line3Hit:SetPoint("TOPLEFT", body, "TOPLEFT", 58, -29)
        card.line3Hit:SetSize(116, 20); card.line3Hit:Show()
    end
    for _, row in ipairs(card.rows) do row.frame:Hide() end
    card.pillTop:Hide()
    if view.upgrade and LR.Get("showUpgrade") then
        card.pillTop:Set("", "upgrade", "gold"); card.pillTop.tip = C.PillTips.upgrade
        card.pillTop:SetWidth(22); card.pillTop:ClearAllPoints(); card.pillTop:SetPoint("TOPLEFT", 176, -29); card.pillTop:Show()
    end
    if card.live then
        C.PaintTimer(card, view)
        local scheduled = view.state == "scheduled" and view.auto
        local keys = scheduled and { "now", "stop" } or { "need", "greed", "pass" }
        for i, key in ipairs(keys) do
            local b = card.buttons[key]; b.compact = true; b:SetHeight(34)
            local width = scheduled and 71 or 44
            b:SetWidth(width); Place(b, card, 208 + (i - 1) * (width + 3), 12)
            b:Layout()
        end
    else
        Hide(card.timer, card.time)
        Place(card.status, card, 204, 18, 146); card.status:SetHeight(28)
        card.status.icon:SetSize(16, 16); TextSize(card.status.text, 11)
    end
    card:SetHeight(C.MINI_HEIGHT)
    return C.MINI_HEIGHT
end

-- Fits the card's height, lays out and fills it. Returns the height.
function C.Draw(card, view)
    if R.LootVictory and view.victory then return R.LootVictory.Draw(card, view) end
    if R.LootVictory then R.LootVictory.ClearCard(card) end
    card.body:EnableMouse(true); card.iconHit:EnableMouse(true); card.close:Enable()
    for _, button in pairs(card.buttons) do button:Enable() end
    card:SetWidth(W_CARD)
    card.compact = view.displayMode == "collapsed"
    C.DisplayToggle(card, view.displayMode, false)
    card.iconFrame:ClearAllPoints(); card.iconFrame:SetPoint("TOPLEFT", PAD, -16); card.iconFrame:SetSize(46, 46)
    card.iconHit:ClearAllPoints(); card.iconHit:SetPoint("TOPLEFT", card.iconFrame, "TOPLEFT", 0, 0)
    card.iconHit:SetPoint("BOTTOMRIGHT", card.body, "TOPRIGHT", -40, -62)
    card.name:ClearAllPoints(); card.name:SetPoint("TOPLEFT", 70, -15); card.name:SetSize(W_CARD - 70 - 60, 20); TextSize(card.name, 15)
    card.sub:ClearAllPoints(); card.sub:SetPoint("TOPLEFT", 70, -35); card.sub:SetHeight(16); TextSize(card.sub, 12); card.sub:Show()
    card.line3:Show(); card.status:SetHeight(34); card.status.icon:SetSize(24, 24); TextSize(card.status.text, 12)
    for _, button in pairs(card.buttons) do button.compact = false; button:SetHeight(34) end
    local body = card.body
    local qc, qname = Quality(view)
    card.live = view.state == "pending" or view.state == "scheduled"
    card.view = view
    card.rollID = view.rollID
    card.sig = (view.state or "") .. "|" .. tostring(view.needsConfirm) .. "|" .. tostring(view.autoNote) .. "|" .. tostring(view.auto and view.auto.name)

    -- header
    card.icon:SetTexture(view.icon or [[Interface\Icons\INV_Misc_QuestionMark]])
    card.iconRim:Color(qc)
    card.count:SetText((view.count or 1) > 1 and tostring(view.count) or "")
    C.FitItemName(card.name, view.name or "Loot")
    card.name:SetTextColor(qc[1], qc[2], qc[3])
    local sub = view.typeText and view.typeText ~= "" and (view.typeText .. "  ·  ") or ""
    card.sub:SetText(sub .. Hex(qc) .. qname .. "|r")
    -- third line: the rule (when a rule is acting), else the vendor price
    local line3, line3Icon
    if view.state == "scheduled" and view.auto then
        line3, line3Icon = "Rule: " .. (view.auto.name or ""), "gear"
    elseif LR.Get("showValue") and view.sellPrice and view.sellPrice > 0 and (view.state == "pending" or view.state == "submitted") then
        line3 = "Vendor:  " .. (CoinText(view.sellPrice) or "")
    end
    card.line3:ClearAllPoints()
    if line3Icon then
        card.line3Icon:SetTexture(MEDIA .. line3Icon); card.line3Icon:Show()
        card.line3Icon:ClearAllPoints(); card.line3Icon:SetPoint("TOPLEFT", body, "TOPLEFT", 70, -52)
        card.line3:SetPoint("TOPLEFT", 88, -53)
    else
        card.line3Icon:Hide()
        card.line3:SetPoint("TOPLEFT", 70, -53)
    end
    card.line3:SetText(line3 or "")
    if line3 then
        card.line3Hit:ClearAllPoints()
        card.line3Hit:SetPoint("TOPLEFT", body, "TOPLEFT", 70, -51)
        card.line3Hit:SetSize(210, 16); card.line3Hit:Show()
    else
        card.line3Hit:Hide()
    end

    -- pills (right of the header)
    local pills = {}
    if view.state == "scheduled" and view.auto then
        pills[#pills + 1] = { ("Auto %s"):format(ChoiceLabel[view.auto.action] or ""), "autocheck", "ok", C.PillTips.auto }
    elseif view.state == "submitted" then
        pills[#pills + 1] = { view.placed and "Chosen" or "Sent", "check", nil, C.PillTips.sent }
    elseif view.state == "resolved" then
        local w = view.result and view.result.winner
        if w and w.self then pills[#pills + 1] = { "Won", "crown", "gold", C.PillTips.won } else pills[#pills + 1] = { "Resolved", "check", nil, C.PillTips.resolved } end
    elseif view.state == "ended" then
        pills[#pills + 1] = { view.endReason == "expired" and "Expired" or "Closed", nil, nil, view.endReason == "expired" and C.PillTips.expired or C.PillTips.closed }
    end
    if view.upgrade and LR.Get("showUpgrade") and (view.state == "pending" or view.state == "scheduled") then
        pills[#pills + 1] = { "Potential upgrade", "upgrade", "gold", C.PillTips.upgrade }
    end
    local top, bottom = card.pillTop, card.pillBottom
    top:ClearAllPoints(); bottom:ClearAllPoints()
    if pills[1] then
        top:Set(pills[1][1], pills[1][2], pills[1][3]); top.tip = pills[1][4]; top:Show()
        top:SetPoint("TOPRIGHT", body, "TOPRIGHT", -PAD, -34)
    else top:Hide() end
    if pills[2] then
        bottom:Set(pills[2][1], pills[2][2], pills[2][3]); bottom.tip = pills[2][4]; bottom:Show()
        bottom:SetPoint("TOPRIGHT", body, "TOPRIGHT", -PAD, -58)
    else bottom:Hide() end
    -- the item's lines stop where a pill begins
    local room = W_CARD - 70 - PAD - 8
    card.sub:SetWidth(math.max(60, room - (pills[1] and top:GetWidth() or 0)))
    card.line3:SetWidth(math.max(60, room - (pills[2] and bottom:GetWidth() or 0) - (line3Icon and 18 or 0)))

    -- body, by state
    Hide(card.timer, card.time, card.status, card.banner, card.divider, card.note)
    for _, b in pairs(card.buttons) do b:Hide() end
    for _, row in ipairs(card.rows) do row.frame:Hide() end
    local y = 76
    local inner = W_CARD - PAD * 2

    local function Note(text, tone)
        card.note:ClearAllPoints()
        card.note:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -y)
        card.note:SetText(text)
        local c = tone == "warn" and { 0.90, 0.70, 0.40 } or COL.dim
        card.note:SetTextColor(c[1], c[2], c[3])
        card.note:Show()
        y = y + 16
    end

    if card.live then
        if view.needsConfirm then
            Note("Confirm in the game's window to roll " .. (view.confirmWord or "this") .. ".", "warn")
        elseif view.autoNote and view.state == "pending" then
            Note(view.autoNote, "warn")
        end
        card.timerY = y
        C.PaintTimer(card, view)
        y = y + LR.Get("barHeight") + 12
        local b = card.buttons
        local scheduled = view.state == "scheduled" and view.auto
        if scheduled then
            local half = (inner - 8) / 2
            for i, key in ipairs({ "now", "stop" }) do
                local btn = b[key]
                btn:SetWidth(half); Place(btn, card, PAD + (i - 1) * (half + 8), y)
                btn:SetVisual("normal"); btn:Layout()
                btn.onTip = nil
            end
            Info(b.now, "Roll now", ("Chooses %s at once instead of waiting out the countdown."):format(ChoiceLabel[view.auto.action] or "the rule's choice"))
            Info(b.stop, "Stop auto roll", "Cancels the automatic choice for this item. The roll stays open so you can choose yourself.")
            b.now.text:SetText("Roll now"); b.stop.text:SetText("Stop auto roll")
            b.now:Layout(); b.stop:Layout()
        else
            local w3 = (inner - 16) / 3
            local avail = { need = view.canNeed, greed = view.canGreed, pass = true }
            local why = { need = view.reasonNeed, greed = view.reasonGreed }
            for i, key in ipairs({ "need", "greed", "pass" }) do
                local btn = b[key]
                btn:SetWidth(w3); Place(btn, card, PAD + (i - 1) * (w3 + 8), y)
                btn:SetVisual(avail[key] == false and "unavailable" or "normal")
                btn.onTip = nil
                if avail[key] == false then Tip(btn, ChoiceLabel[key] .. " isn't available", why[key] or "You can't roll this on this item.")
                else Info(btn, ChoiceLabel[key], C.CHOICE_HELP[key]) end
                btn:Layout()
            end
        end
        y = y + 34
    elseif view.state == "submitted" then
        Place(card.status, card, PAD, y, inner)
        local choice = view.choice
        card.status.icon:SetTexture(MEDIA .. ({ need = "need", greed = "greed", pass = "pass" })[choice or "pass"])
        local word = ChoiceLabel[choice or ""] or "a choice"
        local head = view.placed and ("You chose  " .. Hex(COL.gold) .. word .. "|r") or ("Sending  " .. Hex(COL.gold) .. word .. "|r...")
        card.status.text:SetText(head .. (view.placed and "   waiting for the others" or ""))
        y = y + 34
    elseif view.state == "resolved" then
        local res = view.result
        local mine = res and (function() for _, r in ipairs(res.rolls or {}) do if r.self then return r end end end)()
        Place(card.status, card, PAD, y, (res and #res.rolls > 0) and 172 or inner)
        card.status.icon:SetTexture(MEDIA .. ({ need = "need", greed = "greed", pass = "pass" })[view.choice or "pass"])
        local word = view.choice and ChoiceLabel[view.choice] or "No choice"
        local num = mine and mine.roll and ("  (" .. mine.roll .. ")") or ""
        card.status.text:SetText("Your roll: " .. Hex(COL.gold) .. word .. num .. "|r")
        local listH = 0
        if res and #res.rolls > 0 and LR.Get("showResults") then
            card.divider:ClearAllPoints()
            card.divider:SetPoint("TOPLEFT", body, "TOPLEFT", 198, -y); card.divider:SetHeight(math.min(#res.rolls, 5) * ROW_H + 8)
            card.divider:Show()
            for i = 1, math.min(#res.rolls, 5) do
                local r, row = res.rolls[i], card.rows[i]
                Paint(row.dot, r.winner and COL.gold or COL.bronze)
                row.name:SetText(r.name)
                row.choice:SetText("- " .. (WORD[r.choice] or ""))
                row.roll:SetText(r.roll and tostring(r.roll) or "")
                row.roll:SetTextColor((r.winner and COL.gold or COL.dim)[1], (r.winner and COL.gold or COL.dim)[2], (r.winner and COL.gold or COL.dim)[3])
                row.frame:ClearAllPoints(); row.frame:SetPoint("TOPLEFT", body, "TOPLEFT", 208, -(y + 4 + (i - 1) * ROW_H)); row.frame:Show()
            end
            listH = math.min(#res.rolls, 5) * ROW_H + 8
        end
        y = y + math.max(34, listH) + 8
        local w = res and res.winner
        if res and (w or res.allPassed) then
            local text, strong
            if res.allPassed then text = "Everyone passed"
            elseif w.self then text, strong = "You won  -  " .. (WORD[w.choice] or "") .. (w.roll and (" " .. w.roll) or ""), true
            else text = ("Won by %s  -  %s%s"):format(w.name, WORD[w.choice] or "", w.roll and (" " .. w.roll) or "") end
            Place(card.banner, card, PAD, y, inner)
            card.banner.art:SetSkin(strong and "primary" or "button")   -- antique gold for a win, as the settings reserve it for what matters
            card.banner.text:SetText(text)
            card.banner.icon:SetShown(not res.allPassed)
            card.banner.text:ClearAllPoints(); card.banner.text:SetPoint("CENTER", card.banner, "CENTER", res.allPassed and 0 or 12, 0)
            card.banner.icon:ClearAllPoints(); card.banner.icon:SetPoint("RIGHT", card.banner.text, "LEFT", -6, 0)
            y = y + 28
        end
    else   -- ended
        if view.endReason == "expired" then
            Timer(card, 1, 1, PAD, inner, y, true)   -- a full bar in the run-out color: the time is spent
            y = y + LR.Get("barHeight") + 12
        end
        Place(card.status, card, PAD, y, inner)
        card.status.icon:SetTexture(MEDIA .. "pass")
        card.status.text:SetText(view.endReason == "expired" and "The roll ran out before you chose." or "This roll was closed.")
        y = y + 34
    end
    local h = y + 14
    card:SetHeight(h)
    if card.compact then return CompactLayout(card, view) end
    return h
end

---------------------------------------------------------------------------
-- Views of live rolls
---------------------------------------------------------------------------
-- "Two-handed sword", "Chest", "Recipe": the weapon's kind, the armor's slot, else the item's own type words.
function C.TypeText(roll)
    local o = roll.obs or {}
    local loc = o.equipLoc
    local text
    if o.classID == 2 then text = roll.subTypeText
    elseif o.classID == 4 then text = (type(loc) == "string" and loc ~= "" and _G[loc]) or roll.subTypeText
    else text = (roll.subTypeText and roll.subTypeText ~= "") and roll.subTypeText or roll.typeText end
    if type(text) == "string" and text ~= "" then return text end
end

function C.View(roll)
    local v = {
        displayMode = Ro.DisplayMode(roll), manualDisplay = roll.manualDisplay,
        state = roll.state, rollID = roll.rollID, name = roll.name, icon = roll.icon, quality = roll.quality, count = roll.count,
        typeText = C.TypeText(roll),
        sellPrice = roll.sellPrice, upgrade = roll.upgrade == true or nil, canNeed = roll.canNeed, canGreed = roll.canGreed,
        reasonNeed = roll.reasonNeed and _G["LOOT_ROLL_INELIGIBLE_REASON" .. tostring(roll.reasonNeed)] or nil,
        reasonGreed = roll.reasonGreed and _G["LOOT_ROLL_INELIGIBLE_REASON" .. tostring(roll.reasonGreed)] or nil,
        remaining = Ro.Remaining(roll), duration = roll.duration, choice = roll.choice, placed = roll.placed,
        needsConfirm = roll.needsConfirm, confirmWord = type(roll.needsConfirm) == "number" and ({ [0] = "Pass", "Need", "Greed" })[roll.needsConfirm] or nil,
        autoNote = roll.autoNote, result = roll.result, endReason = roll.endReason,
        link = roll.link, judged = roll.judged,
    }
    if roll.auto and roll.state == "scheduled" then
        v.auto = { name = roll.auto.name, action = roll.auto.action, delay = roll.auto.delay, remaining = math.max(0, roll.auto.fireAt - GetTime()) }
    end
    return v
end

---------------------------------------------------------------------------
-- The stack
---------------------------------------------------------------------------
local function Fail(err)
    if failed then return end
    failed = true
    R.Life.Note("loot-cards-failed")
    R.Fault("loot rolls", err)
    if R.LootBlizzard then R.LootBlizzard.Disable() end
    if R.LootVictory then R.LootVictory.Disable(true) end
    if stack then stack:Hide() end
    if R.LootAuto then R.LootAuto.Refresh() end
end

function C.Ready() return built == true and not failed end
function C.Failed() return failed == true end
function C.Shows(roll) return roll ~= nil and not roll.victoryOwned and shown[roll.key] ~= nil and shown[roll.key]:IsShown() end
function C.Has(rollID)
    for key, card in pairs(shown) do
        if card.rollID == rollID and card:IsShown() then return true end
    end
    return false
end

local function Anchor()
    if not stack then return end
    local scale = LR.Get("scale") / 100
    stack:SetScale(scale)
    local x, y = LR.Place()
    stack:ClearAllPoints()
    stack:SetPoint("TOP", UIParent, "CENTER", x / scale, y / scale)
end
C.Anchor = Anchor

local function Build()
    if built then return end
    stack = CreateFrame("Frame", "TwichUILootCards", UIParent)
    stack:SetSize(W_CARD, 10)
    stack:SetFrameStrata("DIALOG")
    stack:SetClampedToScreen(false)
    stack:Hide()
    built = true
    Anchor()
end

local function Dismiss(card)
    local roll = card.rollKey and Ro.ByKey(card.rollKey)
    if not roll then return end
    roll.dismissed = true
    if R.LootAuto then R.LootAuto.Stop(roll) end
    C.Refresh()
end

local function Choose(card, key)
    local roll = card.rollKey and Ro.ByKey(card.rollKey)
    if not roll then return end
    if key == "now" then R.LootAuto.RollNow(roll) return end
    if key == "stop" then R.LootAuto.Stop(roll) return end
    local ok, why = Ro.Submit(roll, key, "player")
    if not ok and why then R.Life.Note("loot-click-refused") end
end

local function CardFor(i)
    local card = cards[i]
    if not card then
        card = C.NewCard(stack)
        card.onChoice, card.onDismiss = Choose, Dismiss
        cards[i] = card
    end
    return card
end

-- Which rolls have a card: the live ones first, oldest first, then the finished ones, as many as the player allows.
local function Wanted()
    local live, done = {}, {}
    for _, r in ipairs(Ro.Rolls()) do
        if not r.dismissed and not r.victoryOwned then
            if Ro.IsLive(r) then live[#live + 1] = r else done[#done + 1] = r end
        end
    end
    local out, max = {}, LR.Get("maxCards")
    -- A started celebration keeps its slot until it finishes. New wins queue
    -- behind live controls, before ordinary finished results.
    local victories = R.LootVictory and R.LootVictory.Entries() or {}
    for _, r in ipairs(victories) do if r.started and #out < max then out[#out + 1] = r end end
    for _, r in ipairs(live) do if #out < max then out[#out + 1] = r end end
    for _, r in ipairs(victories) do if not r.started and #out < max then out[#out + 1] = r end end
    for i = #done, 1, -1 do if #out < max then out[#out + 1] = done[i] end end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

local function UpdateDriver()
    if not stack then return end
    local need = #leaving > 0
    for _, card in pairs(shown) do
        if card.live or card.enter < 1 then need = true break end
    end
    if need and not driver then
        driver = true
        stack:SetScript("OnUpdate", R.Perf.Wrap("loot.tick", function(self, dt) C.Tick(dt) end))
    elseif not need and driver then
        driver = false
        stack:SetScript("OnUpdate", nil)
    end
end

local newly = {}   -- rolls that just got a card: automation looks at them once the card is on screen (Auto.lua needs one)
local function Layout()
    local growth = LR.Get("growth")
    local gap = LR.Get("spacing")
    local list = Wanted()
    local used = {}
    local before = {}
    for k in pairs(shown) do before[k] = true end
    local y = 0
    for i, roll in ipairs(list) do
        local card = shown[roll.key]
        if not card then
            -- a free card from the pool; one still fading out is taken before a new one is made, and let go at once
            for j = 1, #cards do
                if not cards[j].rollKey and not cards[j].leaving then card = cards[j] break end
            end
            if not card then
                for _, c in ipairs(cards) do
                    if c.leaving then C.FinishLeaving(c) card = c break end
                end
            end
            card = card or CardFor(#cards + 1)
            card.rollKey = roll.key
            card.enter = Fade("fadeIn") > 0 and 0 or 1
            card:SetAlpha(card.enter < 1 and 0 or 1)
            shown[roll.key] = card
        end
        used[roll.key] = true
        card.rollID = roll.rollID
        local h = C.Draw(card, roll.victory and roll or C.View(roll))
        card:ClearAllPoints()
        if growth == "up" then card:SetPoint("BOTTOMLEFT", stack, "TOPLEFT", 0, y) else card:SetPoint("TOPLEFT", stack, "TOPLEFT", 0, -y) end
        card.baseY = y
        card:Show()
        y = y + h + gap
    end
    for key, card in pairs(shown) do
        if not used[key] then
            shown[key] = nil
            local won = card.view and card.view.victory
            if won and R.LootVictory then R.LootVictory.Suspend(card); card.view = nil end
            card.rollKey, card.rollID = nil, nil
            if not won and Fade("fadeOut") > 0 and card:IsShown() and not C.Placing() then
                card.leaving, card.leave = true, 0   -- a fade (Tick), then it is free again
                leaving[#leaving + 1] = card
            else
                card:Hide()
            end
        end
    end
    stack:SetHeight(math.max(10, y - gap))
    stack:SetShown(#list > 0 or #leaving > 0)   -- the last card's fade is drawn on the stack: it stays until the card has gone
    -- a roll that gained or lost its card changes who may act on it
    if R.LootBlizzard then R.LootBlizzard.Sync() end
    for _, roll in ipairs(list) do
        if not before[roll.key] and (roll.state == "pending" or roll.state == "scheduled") then newly[#newly + 1] = roll end
    end
    UpdateDriver()
end

local LayoutScoped
-- Redraws the stack (cheap when nothing is showing). Any error hands the rolls back to the game's frames.
function C.Refresh()
    if not built or failed then return end
    LayoutScoped = LayoutScoped or R.Perf.Wrap("loot.layout", Layout)
    local ok, err = pcall(LayoutScoped)
    if not ok then Fail(err) return end
    C.Flush()
end

-- Automation judges a roll once its card is showing (it would not start a countdown with no card to show it on).
function C.Flush()
    if #newly == 0 then return end
    local list = newly
    newly = {}
    for _, roll in ipairs(list) do
        if R.LootAuto then R.LootAuto.Evaluate(roll) end
    end
end

-- A card that finished fading (or is wanted again): hidden, opaque and free.
function C.FinishLeaving(card)
    card.leaving, card.leave = nil, nil
    card:Hide()
    card:SetAlpha(1)
    for i = #leaving, 1, -1 do if leaving[i] == card then table.remove(leaving, i) end end
    if stack and #leaving == 0 and next(shown) == nil then stack:Hide() end
end

-- One step of the countdowns and the entrance (only while a card is live or coming in).
function C.Tick(dt)
    elapsed = elapsed + dt
    local step = elapsed >= 0.05
    if step then elapsed = 0 end
    local ok, err = pcall(function()
        for i = #leaving, 1, -1 do
            local card = leaving[i]
            local seconds = Fade("fadeOut")
            card.leave = card.leave + (seconds > 0 and dt / seconds or 1)
            if card.leave >= 1 then C.FinishLeaving(card) else card:SetAlpha(1 - card.leave) end
        end
        for key, card in pairs(shown) do
            if card.enter < 1 then
                local seconds = Fade("fadeIn")
                card.enter = math.min(1, card.enter + (seconds > 0 and dt / seconds or 1))
                card:SetAlpha(1 - (1 - card.enter) * (1 - card.enter))
            end
        end
        if step then
            for key, card in pairs(shown) do
                local roll = Ro.ByKey(key)
                if roll and card.live then
                    if roll.state == "pending" and roll.needsConfirm and StaticPopup_Visible and not StaticPopup_Visible("CONFIRM_LOOT_ROLL") then
                        roll.needsConfirm = nil   -- the game's dialog is gone: the roll was not placed, and the card says so no more
                    end
                    local view = C.View(roll)
                    -- only the bar and the number move from step to step: anything else that changed is a redraw of the stack
                    local sig = (view.state or "") .. "|" .. tostring(view.needsConfirm) .. "|" .. tostring(view.autoNote) .. "|" .. tostring(view.auto and view.auto.name)
                    if sig ~= card.sig then card.sig = sig; Layout(); C.Flush() return end
                    C.PaintTimer(card, view)
                end
            end
        end
    end)
    if not ok then Fail(err) end
    UpdateDriver()
end


---------------------------------------------------------------------------
-- Made-up views, for the settings window's preview and the placement sample. Nothing here reads a roll or reaches the game.
---------------------------------------------------------------------------
C.SAMPLES = {
    { "manual", "Waiting for your choice" }, { "auto", "A rule is about to roll" },
    { "sent", "Choice sent" }, { "resolved", "Resolved, with the rolls" }, { "expired", "Ran out of time" },
}
function C.SampleView(kind, rule)
    local v = {
        preview = true, state = "pending", name = "Verdant Scholar's Mantle", quality = 2, count = 1, typeText = "Shoulder",
        icon = [[Interface\Icons\INV_Shoulder_23]], sellPrice = 1850, upgrade = true, canNeed = true, canGreed = true,
        remaining = 7.3, duration = 30,
        sampleLines = { "Binds when picked up", "Shoulder  -  Cloth", "+11 Intellect", "+7 Spirit" },
        upgradeLines = {
            { "Likely upgrade for Arcane", 0.56, 0.70, 0.35, false },
            { "Compared with Weathered Mantle", 0.62, 0.60, 0.56, true },
            { "+11 Intellect", 0.56, 0.70, 0.35, false }, { "+7 Spirit", 0.56, 0.70, 0.35, false }, { "-3 Stamina", 0.80, 0.42, 0.38, false },
            { "Rough estimate, weighed for Arcane", 0.62, 0.60, 0.56, true },
            { "A sample, made up for the preview.", 0.62, 0.60, 0.56, true },
        },
    }
    v.displayMode = rule and rule.display == "collapsed" and "collapsed" or "expanded"
    if kind == "auto" and (not rule or rule.action ~= "none") then
        v.state = "scheduled"
        v.auto = { name = rule and rule.name or "Greed on green gear", action = rule and rule.action or "greed", delay = rule and rule.delay or 3, remaining = 2.8 }
    elseif kind == "sent" then
        v.state, v.choice, v.placed = "submitted", "greed", true
    elseif kind == "resolved" then
        v.state, v.choice = "resolved", "greed"
        v.name, v.quality, v.typeText, v.icon, v.upgrade = "Shieldward Battleplate", 3, "Chest", [[Interface\Icons\INV_Chest_Plate16]], nil
        v.result = { rolls = {
            { name = "Arcanebloom", choice = "greed", roll = 84, winner = true }, { name = "Stoneshield", choice = "need", roll = 67 },
            { name = "You", choice = "greed", roll = 42, self = true }, { name = "Briarfang", choice = "greed", roll = 17 } },
            winner = { name = "Arcanebloom", choice = "greed", roll = 84, winner = true } }
    elseif kind == "expired" then
        v.state, v.endReason, v.upgrade = "ended", "expired", nil
    end
    return v
end

---------------------------------------------------------------------------
-- Placement: a sample card on its own frame that is dragged, saved only when the player says so. The live stack is not shown while this
-- is open, and it is not offered while a roll is open (the player must never lose sight of one).
---------------------------------------------------------------------------
local mover, placeDone

function C.Placing() return mover ~= nil and mover:IsShown() end

function C.PlaceStart(onDone)
    if R.LootVictory and R.LootVictory.Count() > 0 then return false, "A victory is showing right now." end
    if C.Placing() then return false, "Already placing." end
    C.PreviewStop(true)
    if InCombatLockdown and InCombatLockdown() then return false, "Not in combat." end
    for _, r in ipairs(Ro.Rolls()) do
        if Ro.IsLive(r) then return false, "A roll is open right now." end
    end
    if not mover then
        mover = CreateFrame("Frame", "TwichUILootCardsMover", UIParent)
        mover:SetFrameStrata("DIALOG")
        mover:SetMovable(true)
        mover:EnableMouse(true)
        mover:RegisterForDrag("LeftButton")
        mover:SetClampedToScreen(true)
        mover:SetScript("OnDragStart", function(self) self:StartMoving() end)
        mover:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        mover.card = C.NewCard(mover, { preview = true })
        mover.card:SetPoint("TOPLEFT")
        mover.hint = Font(mover, 12, "body", COL.gold)
        mover.hint:SetPoint("BOTTOM", mover, "TOP", 0, 4)
        mover.hint:SetText("Drag to place the loot cards")
    end
    local scale = LR.Get("scale") / 100
    mover:SetScale(scale)
    local h = C.Draw(mover.card, C.SampleView("manual"))
    mover:SetSize(W_CARD, h)
    mover.up = LR.Get("growth") == "up"
    local x, y = LR.Place()
    mover:ClearAllPoints()
    mover:SetPoint(mover.up and "BOTTOM" or "TOP", UIParent, "CENTER", x / scale, y / scale)
    placeDone = onDone
    if stack then stack:SetAlpha(0) end
    mover:Show()
    return true
end

-- save = true keeps the place the sample was dragged to; false leaves the saved place as it was.
function C.PlaceFinish(save)
    if not C.Placing() then return false end
    local ok = true
    if save then
        local es, ues = mover:GetEffectiveScale(), UIParent:GetEffectiveScale()
        local ux, uy = UIParent:GetCenter()
        local edge = mover.up and mover:GetBottom() or mover:GetTop()
        if mover:GetLeft() and edge and ux then
            local cx = (mover:GetLeft() + mover:GetWidth() / 2) * es
            ok = LR.SetPlace((cx - ux * ues) / ues, (edge * es - uy * ues) / ues)
        else
            ok = false
        end
    end
    mover:Hide()
    if stack then stack:SetAlpha(1) end
    Anchor()
    local fn = placeDone
    placeDone = nil
    if fn then pcall(fn, save and ok) end
    return ok
end

---------------------------------------------------------------------------
-- Preview: one made-up roll on screen, in the real place, size and look, that plays through like a real one (a countdown; Need, Greed and
-- Pass; or a rule's countdown with Roll now and Stop) and ends with made-up results. It has its own frame and its own clock. It never
-- reads a roll, never touches Roll.lua or Auto.lua and never sends anything: no roll is made, whatever is pressed. It is not offered while
-- a real roll is open, and a real roll that starts takes its place at once.
---------------------------------------------------------------------------
local pv
local PREVIEW_SECONDS = 20

function C.Previewing() return pv ~= nil and pv.frame:IsShown() and not pv.closing end

local function PreviewResult(choice)
    local rolls = {
        { name = "Arcanebloom", choice = "greed", roll = 84 }, { name = "Stoneshield", choice = "need", roll = 67 },
        { name = "You", choice = choice, roll = choice ~= "pass" and 42 or nil, self = true }, { name = "Briarfang", choice = "greed", roll = 17 },
    }
    if choice == "need" then rolls[3].roll = 91 end
    local winner = choice == "need" and rolls[3] or rolls[1]
    winner.winner = true
    return { rolls = rolls, winner = winner }
end

-- What the card says right now, from the phase and the seconds in it.
local function PreviewView()
    local phase, t = pv.phase, pv.t
    local v
    if phase == "auto" then
        v = C.SampleView("auto", pv.rule)
        v.auto.remaining = math.max(0, v.auto.delay - t)
    elseif phase == "sent" then
        v = C.SampleView("sent"); v.choice = pv.choice
    elseif phase == "resolved" then
        v = C.SampleView("resolved"); v.choice = pv.choice; v.upgrade = nil
        v.result = PreviewResult(pv.choice)
    elseif phase == "expired" then
        v = C.SampleView("expired")
    else
        v = C.SampleView("manual")
        v.remaining = math.max(0, PREVIEW_SECONDS - pv.elapsed)
        if pv.stopped then v.autoNote = "Automatic rolling stopped. The choice is yours." end
    end
    v.duration = PREVIEW_SECONDS
    v.displayMode = pv.manualDisplay or (pv.rule and pv.rule.display) or "expanded"
    return v
end

local function PreviewDraw()
    local view = PreviewView()
    pv.sig = pv.phase .. "|" .. tostring(pv.stopped)
    local h = C.Draw(pv.card, view)
    pv.frame:SetSize(W_CARD, h)
end

local function PreviewPhase(phase, choice)
    pv.phase, pv.t = phase, 0
    if choice then pv.choice = choice end
    if phase == "waiting" then pv.stopped = true end
    PreviewDraw()
end

local function PreviewStep(dt)
    pv.t = pv.t + dt
    pv.elapsed = pv.elapsed + dt
    if pv.closing then
        local seconds = Fade("fadeOut")
        pv.closing = pv.closing + (seconds > 0 and dt / seconds or 1)
        if pv.closing >= 1 then pv.closing = nil; pv.frame:Hide(); pv.frame:SetAlpha(1) else pv.frame:SetAlpha(1 - pv.closing) end
        return
    end
    if pv.enter < 1 then
        local seconds = Fade("fadeIn")
        pv.enter = math.min(1, pv.enter + (seconds > 0 and dt / seconds or 1))
        pv.frame:SetAlpha(1 - (1 - pv.enter) * (1 - pv.enter))
    end
    local phase = pv.phase
    if phase == "auto" and pv.t >= (pv.rule and pv.rule.delay or 3) then return PreviewPhase("sent", pv.rule and pv.rule.action or "greed") end
    if phase == "sent" and pv.t >= 1.2 then return PreviewPhase("resolved") end
    if phase == "waiting" and pv.elapsed >= PREVIEW_SECONDS then return PreviewPhase("expired") end
    if (phase == "resolved" or phase == "expired") and pv.t >= LR.Get("afterResult") then return C.PreviewStop() end
    if pv.card.live then
        pv.step = (pv.step or 0) + dt
        if pv.step >= 0.05 then pv.step = 0; C.PaintTimer(pv.card, PreviewView()) end
    end
end

local function PreviewChoose(card, key)
    if not pv then return end
    if key == "now" then return PreviewPhase("sent", pv.rule and pv.rule.action or "greed") end
    if key == "stop" then return PreviewPhase("waiting") end
    if pv.phase == "auto" or pv.phase == "waiting" then PreviewPhase("sent", key) end
end

-- rule = { name, action, delay } shows a rule's countdown first (its action is what it would roll); nothing = a roll waiting for you.
function C.PreviewStart(rule)
    if R.LootVictory and R.LootVictory.Count() > 0 then return false, "A victory is showing right now." end
    if C.Placing() then return false, "Finish placing the cards first." end
    for _, r in ipairs(Ro.Rolls()) do
        if Ro.IsLive(r) then return false, "A roll is open right now." end
    end
    if not pv then
        local frame = CreateFrame("Frame", "TwichUILootCardsPreview", UIParent)
        frame:SetFrameStrata("DIALOG")
        frame:SetClampedToScreen(false)
        pv = { frame = frame }
        pv.card = C.NewCard(frame, { preview = true })
        pv.card:SetPoint("TOPLEFT")
        pv.card.onChoice = PreviewChoose
        pv.card.onDisplay = function(_, mode) pv.manualDisplay = mode; PreviewDraw() end
        pv.card.onDismiss = function() C.PreviewStop() end
        frame:SetScript("OnUpdate", function(self, dt) if pv then local ok = pcall(PreviewStep, dt) if not ok then C.PreviewStop(true) end end end)
        frame:RegisterEvent("START_LOOT_ROLL")   -- a real roll takes the preview's place, even while the cards are switched off
        frame:SetScript("OnEvent", function() C.PreviewStop(true) end)
        frame:Hide()
    end
    local scale = LR.Get("scale") / 100
    pv.frame:SetScale(scale)
    local x, y = LR.Place()
    pv.frame:ClearAllPoints()
    pv.frame:SetPoint(LR.Get("growth") == "up" and "BOTTOM" or "TOP", UIParent, "CENTER", x / scale, y / scale)
    pv.rule, pv.manualDisplay = rule, nil
    pv.elapsed, pv.stopped, pv.choice = 0, false, nil
    pv.enter = Fade("fadeIn") > 0 and 0 or 1
    pv.closing = nil
    pv.frame:SetAlpha(pv.enter < 1 and 0 or 1)
    pv.phase, pv.t = rule and rule.action ~= "none" and "auto" or "waiting", 0
    if rule then pv.rule = { name = rule.name, action = rule.action, display = rule.display, delay = tonumber(rule.delay) or 3 } end
    PreviewDraw()
    pv.frame:Show()
    return true
end

function C.PreviewCard() return pv and pv.card end   -- for the tests and the simulator

-- now = true takes it away at once (a real roll, placing, switching off); otherwise it fades as a card does.
function C.PreviewStop(now)
    if not (pv and pv.frame:IsShown()) then return end
    if now or pv.closing or Fade("fadeOut") <= 0 then
        pv.closing = nil
        pv.frame:Hide(); pv.frame:SetAlpha(1)
    else
        pv.closing = 0
    end
end

function C.Enable()
    failed = false
    Build()
    if R.LootBlizzard then R.LootBlizzard.SetCardTest(C.Has); R.LootBlizzard.Enable() end
    Anchor()
    C.Refresh()
end

function C.Disable()
    if R.LootVictory then R.LootVictory.Disable(true) end
    if mover and mover:IsShown() then C.PlaceFinish(false) end
    C.PreviewStop(true)
    if stack then stack:Hide(); stack:SetScript("OnUpdate", nil) end
    driver = false
    for key, card in pairs(shown) do shown[key] = nil; card.rollKey, card.rollID = nil, nil; card:Hide() end
    for i = #leaving, 1, -1 do C.FinishLeaving(leaving[i]) end
    if R.LootBlizzard then R.LootBlizzard.Disable() end
end

function C.CardCount() local n = 0 for _ in pairs(shown) do n = n + 1 end return n end
function C.PoolSize() return #cards end
function C.Stack() return stack end
function C.Card(key) return shown[key] end

Ro.Subscribe(function(kind, roll)
    if not built then return end
    C.Refresh()
end)
LR.Subscribe(function(what)
    if not built then return end
    if what == "place" or what == "settings" or what == "profile" then Anchor() end
    C.Refresh()
end)
