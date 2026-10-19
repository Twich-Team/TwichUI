-- TwichUI: Navigation, the frame
-- A compact frame while navigating: the destination's name, the next instruction, the distances (each labelled with what
-- it measures), the state when it isn't simply "following", and two controls: Stop and Recalculate. The arrow can sit in
-- it (Arrow attached) or on its own.
--   Distances: "Route" is what is left along the route; "Next" is the distance to its next corner; "Straight" is the
--     straight line to the destination. With no route only the straight line is given, and said to be one. No travel time
--     is shown: mounts, speed and the way you walk make any figure a guess.
--   Click-through: locked (the default), only the two buttons take the mouse; unlocked, the frame can be dragged and its
--     place is kept (ui.navigation.position, this screen's, not shared). Reset position in the settings puts it back.
--   Look: the frame's background and border are a MenuStyle look (ui.navigationLook: works without EllesmereUI); text in
--     the chosen font, size and colours; a teal accent rule on the left. Nothing flashes; state changes are words.
--   Text is set only when it changed, and the layout redone only when the look or a line's height changed. Updated on
--     Nav.lua's events (four times a second at most while moving), never per frame.
-- The settings preview is a second frame from the same code (NF.New(true)): it shows sample values, says "Preview", and
-- never touches navigation.

local R = TwichUI
local NV, NP = R.Nav, R.NavPrefs
local NF = {}
R.NavFrame = NF

local WIDTH = 250
local PAD = 8

local STATE_WORDS = {
    loading = "Loading walking maps…", calculating = "Calculating route…", recalculating = "Recalculating route…",
    unavailable = "Position unavailable", noroute = "No way there", arrived = "Arrived",
}

local Frame = {}
Frame.__index = Frame

local function Paint(fs, hex, mult)
    local r, g, b = NP.Rgb(hex)
    mult = mult or 1
    fs:SetTextColor(r * mult, g * mult, b * mult)
end

local function NewButton(parent, label, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp")
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        local r, g, bl = NP.Rgb(NP.Get("accentColor"))
        self.label:SetTextColor(math.min(1, r + 0.25), math.min(1, g + 0.25), math.min(1, bl + 0.25))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(tip, 0.80, 0.78, 0.72, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        Paint(self.label, NP.Get("textColor"), 0.8)
        GameTooltip:Hide()
    end)
    return b
end

function NF.New(preview)
    local self = setmetatable({ preview = preview, last = {} }, Frame)
    local f = CreateFrame("Frame", preview and "TwichUINavigationPreview" or "TwichUINavigation", UIParent, "BackdropTemplate")
    self.f = f
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(false)
    f:Hide()
    f.accent = f:CreateTexture(nil, "ARTWORK")
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.line = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.line:SetJustifyH("LEFT")
    f.line:SetWordWrap(true)
    f.meta = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.meta:SetJustifyH("LEFT")
    f.meta:SetWordWrap(true)
    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.note:SetJustifyH("LEFT")
    f.note:SetWordWrap(true)
    if not preview then
        f.stop = NewButton(f, "Stop", function() NV.Stop("stopped") end, "Ends navigation. Your pins and waypoint are not changed.")
        f.again = NewButton(f, "Recalculate", function() NV.Recalculate() end, "Plans the route again from where you are now.")
        f:SetScript("OnDragStart", function(fr) if not NP.Get("locked") then fr:StartMoving() end end)
        f:SetScript("OnDragStop", function(fr)
            fr:StopMovingOrSizing()
            local cx, cy = fr:GetCenter()
            local ux, uy = UIParent:GetCenter()
            local s = fr:GetScale() / UIParent:GetScale()
            if cx and ux then NP.Set("position", { x = math.floor(cx * s - ux + 0.5), y = math.floor(cy * s - uy + 0.5) }) end
        end)
    else
        f.tag = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.tag:SetText("Preview")
    end
    self.dirty = true
    return self
end

-- The look, the fonts and the place. Called when a preference or the profile changed, not per update.
function Frame:Style()
    local f = self.f
    f:SetScale(NP.Get("frameScale") / 100)          -- before the border: it is drawn for the frame's scale
    local inset = math.max(PAD, math.ceil(NP.Look.ApplyInset(f) + 4))
    self.inset = inset
    local font, size = NP.Font(), NP.Get("textSize")
    f.title:SetFont(font, size + 1, "")
    f.line:SetFont(font, size + 1, "")
    f.meta:SetFont(font, math.max(9, size - 1), "")
    f.note:SetFont(font, math.max(9, size - 1), "")
    Paint(f.title, NP.Get("titleColor"))
    Paint(f.line, NP.Get("textColor"))
    Paint(f.meta, NP.Get("textColor"), 0.78)
    Paint(f.note, NP.Get("textColor"), 0.78)
    local ar, ag, ab = NP.Rgb(NP.Get("accentColor"))
    f.accent:SetColorTexture(ar, ag, ab, 0.9)
    for _, b in ipairs({ f.stop, f.again }) do
        b.label:SetFont(font, math.max(9, size - 1), "")
        Paint(b.label, NP.Get("textColor"), 0.8)
        b:SetSize(math.ceil(b.label:GetStringWidth() + 8), size + 6)
    end
    if f.tag then
        f.tag:SetFont(font, math.max(9, size - 2), "")
        f.tag:SetTextColor(ar, ag, ab)
    end
    local width = math.floor(WIDTH * size / 12 + 0.5)
    f:SetWidth(width)
    if not self.preview then
        local unlocked = not NP.Get("locked")
        f:EnableMouse(unlocked)                        -- locked: only the buttons take the mouse
        if unlocked then f:RegisterForDrag("LeftButton") else f:RegisterForDrag() end
        self:Place()
    end
    self.dirty = true
    self.last = {}
end

function Frame:Place()
    local f = self.f
    f:ClearAllPoints()
    local p = NP.Get("position")
    if p then
        local s = UIParent:GetScale() / f:GetScale()
        f:SetPoint("CENTER", UIParent, "CENTER", p.x * s, p.y * s)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -140 / f:GetScale())
    end
end

local function Set(self, fs, key, text)
    if self.last[key] ~= text then
        self.last[key] = text
        fs:SetText(text or "")
        self.dirty = true
    end
end

-- The words for a snapshot (Nav.Snapshot(), or the preview's sample). Returns title, line, meta, note.
function NF.Words(s)
    local dest = s.dest
    local title = dest and dest.name or ""
    local line, meta, note = "", "", nil
    local Y, J = NV.Yards, R.NavJourney
    local legs = s.legs
    local L = legs and legs[s.leg or 1] or nil
    -- the lines about the journey as a whole: what comes next, the step, the time left (an estimate)
    local function Journey(first)
        local parts = {}
        if first then parts[#parts + 1] = first end
        if s.nextText then parts[#parts + 1] = "Then " .. s.nextText end
        if (s.steps or 0) > 1 and s.eta and J then
            parts[#parts + 1] = ("Step %d of %d · %s in all (estimate)"):format(s.leg or 1, s.steps, J.Minutes(s.eta))
        end
        return #parts > 0 and table.concat(parts, "\n") or nil
    end
    if s.state == "navigating" or (s.state == "recalculating" and (s.route or L)) then
        line = s.instruction or ""
        if L and L.kind ~= "walk" then
            meta = NV.LegDetail(L)
        else
            local bits = { ("Route %s"):format(Y(s.remaining or 0)), ("Next %s"):format(Y(s.toNext or 0)) }
            if s.straight then bits[#bits + 1] = ("Straight %s"):format(Y(s.straight)) end
            meta = table.concat(bits, "  ·  ")
        end
        note = Journey(s.state == "recalculating" and "Recalculating route…" or nil)
    elseif s.state == "riding" then
        line = (s.reason == "taxi") and "In flight" or "Under way"
        meta = (s.reason == "taxi") and "Nothing to follow until you land." or "Nothing to follow until you arrive."
        note = Journey(s.instruction)
    elseif s.state == "noroute" then
        line = "No way there"
        note = NV.ReasonText(s.reason)
        if s.fallback then meta = ("Straight line %s (a direct bearing, not a route)"):format(Y(s.straight or 0)) end
    elseif s.state == "arrived" then
        line = "Arrived"
    elseif s.state == "loading" and s.reason == "combat" then
        line = STATE_WORDS.loading
        note = NV.ReasonText("combat")
    else
        line = STATE_WORDS[s.state] or ""
        if s.state == "unavailable" then note = "Navigation continues when your position can be read again." end
    end
    return title, line, meta, note
end

function Frame:Update(s)
    local f = self.f
    local title, line, meta, note = NF.Words(s)
    Set(self, f.title, "title", title)
    Set(self, f.line, "line", line)
    Set(self, f.meta, "meta", meta)
    Set(self, f.note, "note", note)
    if f.again then
        local can = s.dest ~= nil and s.state ~= "calculating" and s.state ~= "recalculating" and s.state ~= "arrived"
        if self.last.again ~= can then self.last.again = can; f.again:SetShown(can); self.dirty = true end
    end
    if self.dirty then self:Layout() end
end

function Frame:Layout()
    self.dirty = false
    local f = self.f
    local inset = self.inset or PAD
    local w = f:GetWidth()
    local left = inset + 8
    local attached = self.arrowSlot ~= nil and self.arrowSlot:IsShown()
    local arrowW = attached and (self.arrowSlot:GetWidth() + 8) or 0
    f.accent:ClearAllPoints()
    f.accent:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
    f.accent:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset)
    f.accent:SetWidth(2)
    -- the controls, top right
    local right = inset
    local top = -inset
    for _, b in ipairs({ f.stop, f.again }) do
        if b and b:IsShown() then
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -right, top + 2)
            right = right + b:GetWidth() + 2
        end
    end
    if f.tag then
        f.tag:ClearAllPoints()
        f.tag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inset, top)
        right = right + (f.tag:GetStringWidth() or 40) + 6
    end
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", left, top)
    f.title:SetWidth(math.max(40, w - left - right - 4))
    local y = top - (f.title:GetStringHeight() or 14) - 4
    if attached then
        self.arrowSlot:ClearAllPoints()
        self.arrowSlot:SetPoint("TOPLEFT", f, "TOPLEFT", left, y)
    end
    local textW = w - left - inset - arrowW
    for _, fs in ipairs({ f.line, f.meta, f.note }) do
        fs:ClearAllPoints()
        fs:SetWidth(textW)
        if (fs:GetText() or "") ~= "" then
            fs:SetPoint("TOPLEFT", f, "TOPLEFT", left + arrowW, y)
            fs:Show()
            y = y - (fs:GetStringHeight() or 12) - 3
        else
            fs:Hide()
        end
    end
    local h = -y + inset
    if attached then h = math.max(h, -(top - (f.title:GetStringHeight() or 14) - 4) + self.arrowSlot:GetHeight() + inset) end
    f:SetHeight(math.ceil(h))
end

function Frame:Show() self.f:Show() end
function Frame:Hide() self.f:Hide() end
function Frame:IsShown() return self.f:IsShown() end

---------------------------------------------------------------------------
-- The real frame
---------------------------------------------------------------------------
local main

local function Wanted()
    return NV.Enabled() and NP.Get("frame") and NV.Active()
end

function NF.Main() return main end

function NF.Refresh()
    if not Wanted() then
        if main then main:Hide() end
        return
    end
    if not main then
        main = NF.New(false)
        main:Style()
    end
    if R.NavArrow then R.NavArrow.Attach(main) end
    main:Update(NV.Snapshot())
    main:Show()
end

NV.Subscribe(function(event)
    if event == "prefs" then
        if main then main:Style() end
        NF.Refresh()
    elseif event == "position" then
        return
    elseif main and main:IsShown() and NV.Active() then
        main:Update(NV.Snapshot())
    else
        NF.Refresh()
    end
end)

---------------------------------------------------------------------------
-- The preview (settings): sample values from the real renderer, labelled, never navigating
---------------------------------------------------------------------------
local preview
NF.SAMPLE = {
    state = "navigating", dest = { name = "Sample destination" }, instruction = "In 40 yd, turn left",
    remaining = 820, toNext = 40, straight = 610, seg = 1,
}

function NF.ShowPreview(anchor)
    if not preview then preview = NF.New(true) end
    preview:Style()
    if R.NavArrow then R.NavArrow.AttachPreview(preview) end
    preview:Update(NF.SAMPLE)
    local f = preview.f
    f:ClearAllPoints()
    if anchor then f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 12, 0) else f:SetPoint("CENTER", UIParent, "CENTER", 0, 120) end
    f:SetFrameStrata("DIALOG")
    preview:Show()
end

function NF.HidePreview()
    if preview then preview:Hide() end
    if R.NavArrow then R.NavArrow.HidePreview() end
end

function NF.PreviewShown() return preview ~= nil and preview:IsShown() end

if R.OnSettingsClosed then R.OnSettingsClosed(NF.HidePreview) end
