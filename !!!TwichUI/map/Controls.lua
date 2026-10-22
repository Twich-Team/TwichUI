-- TwichUI: world map exploration, the controls
-- Two small pieces on the world map, in the look of the map's tool bar (pins/MapTools.lua: the pins' menu look, the
-- shared window palette's teal):
--   The zoom stack, at the bottom right of the map's canvas, above the game's quest-panel button: + and - (zoom about
--     the middle), Fit (the whole map), Back (the view before a jump, or out of an open cave or dungeon map), and a
--     readout of how far in you are. Its tooltip says what the view shows: the painted map, the painted map with the
--     game's terrain detail, or the painted map enlarged with nothing finer to show. A "Dungeon map" button joins it
--     while you are inside a dungeon whose map is known. The choice "Show the zoom buttons" hides the stack; the wheel,
--     dragging and Back keep working.
--   The context bar, at the top middle of the canvas while a cave's or a dungeon's map is open: its name, what it is,
--     its floors (previous and next, with the floor's name), a note, and Leave.
-- Every label is words or + and -; the tooltips say what each does. Nothing here keeps state of its own.

local R = TwichUI
local MXP, MV = R.MapExplorePrefs, R.MapView
local PL = R.PinsLook
local MC = {}
R.MapControls = MC

local BTN_W, BTN_H, GAP = 40, 20, 2
local GOLD = { 0.86, 0.69, 0.30 }

local function Pal()
    local L = R.Look
    if L and L.pal then return L.pal end
    return { text = { 0.94, 0.91, 0.82 }, textDim = { 0.80, 0.78, 0.72 }, stone = { 0.62, 0.60, 0.56 },
        teal = { 0.36, 0.58, 0.57 }, tealHi = { 0.58, 0.78, 0.76 }, tealLo = { 0.18, 0.33, 0.33 } }
end

local function Solid(f, layer, c, a)
    local t = f:CreateTexture(nil, layer)
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    return t
end

local function Skin(f)
    f.pad = math.max(3, math.ceil(PL.Surface(PL.MenuLook, f)))
    return f.pad
end

local function Text(parent, template, color)
    local fs = PL.Text(parent, template or "GameFontNormalSmall", "meta")
    local c = color or Pal().text
    fs:SetTextColor(c[1], c[2], c[3], 1)
    return fs
end

-- A text button: a word or a sign, a teal wash under the pointer, dimmed (still hoverable) while it can't act.
local function Button(parent, label, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(BTN_W, BTN_H)
    b:RegisterForClicks("LeftButtonUp")
    local fill = Solid(b, "BACKGROUND", Pal().tealLo, 0.55)
    fill:SetAllPoints()
    local hl = Solid(b, "HIGHLIGHT", Pal().tealHi, 0.18)
    hl:SetAllPoints()
    b.text = Text(b, "GameFontHighlightSmall")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetJustifyH("CENTER")
    b.text:SetText(label)
    b.usable = true
    b:SetScript("OnClick", function(self)
        if not self.usable then
            if self.why then MV.Notice(self.why) end
            return
        end
        onClick(self)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local title, lines = tip(self)
        GameTooltip:SetText(title, 1, 1, 1)
        for _, line in ipairs(lines or {}) do
            if line[2] == "gold" then GameTooltip:AddLine(line[1], GOLD[1], GOLD[2], GOLD[3], true)
            else GameTooltip:AddLine(line[1], 0.78, 0.74, 0.66, true) end
        end
        if not self.usable and self.why then GameTooltip:AddLine(self.why, 0.92, 0.55, 0.44, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function SetUsable(b, ok, why)
    b.usable, b.why = ok and true or false, (not ok) and why or nil
    b.text:SetAlpha(ok and 1 or 0.4)
end

---------------------------------------------------------------------------
-- What the view shows, in words (the readout's tooltip, and the settings)
---------------------------------------------------------------------------
function MC.Describe()
    local DV, MCV, MD = R.MapDungeonView, R.MapCaves, R.MapDetail
    if DV and DV.IsOpen() then
        return { title = "Dungeon map", lines = { { "The game's own map of the dungeon, one floor at a time. Your position isn't shown on it." } } }
    end
    if not MV.Ready() then return { title = "World map", lines = { { "The game's own map (this map isn't part of the stitched world)." } } } end
    local lines = {}
    local u, v, zoom = MV.View()
    lines[#lines + 1] = { ("Zoom: %.1f times the whole world (deepest here %.0f)"):format(zoom, MV.MaxZoomAt(u, v)) }
    if MCV and MCV.Surfaced() then
        lines[#lines + 1] = { "A cave's own map, laid where the cave is. Your arrow is the game's own." }
    elseif MD and MD.Showing() then
        lines[#lines + 1] = { "The game's paintings with its terrain detail (its minimap pictures) laid over them." }
    elseif MV.Enlarged() then
        lines[#lines + 1] = { "The game's painting, enlarged: there is no finer detail of it to show here." }
    else
        lines[#lines + 1] = { "The game's paintings of the world, its continents and zones, stitched together." }
    end
    lines[#lines + 1] = { "Wheel: zoom at the pointer. Drag: move. Click: into a map; right-click: out.", "gold" }
    return { title = "Zoom", lines = lines }
end

---------------------------------------------------------------------------
-- The zoom stack
---------------------------------------------------------------------------
local stack, readout, buttons = nil, nil, {}

local function InDungeon()
    local DV = R.MapDungeonView
    if not (DV and GetInstanceInfo) then return nil end
    local ok, _, kind, _, _, _, _, _, inst = pcall(GetInstanceInfo)
    if not ok or (kind ~= "party" and kind ~= "raid") then return nil end
    return DV.Has(inst) and inst or nil
end

local function DungeonOpen() return R.MapDungeonView and R.MapDungeonView.IsOpen() end

function MC.Back()
    if DungeonOpen() then R.MapDungeonView.Close() return true end
    local ok, why = MV.Back()
    if not ok and why == "combat" then MV.Notice(MV.Reason(why)) end
    return ok
end

local function Zoom(n)
    if DungeonOpen() then R.MapDungeonView.ZoomStep(n) else MV.ZoomStep(n) end
end

local function Fit()
    if DungeonOpen() then R.MapDungeonView.Fit() else MV.World() end
end

local function BuildStack()
    if stack then return end
    stack = CreateFrame("Frame", "TwichUIMapZoom", WorldMapFrame, "BackdropTemplate")
    stack:SetFrameStrata("HIGH")
    stack:EnableMouse(true)                 -- a click on the stack is not a click on the map
    stack:Hide()
    readout = Text(stack, "GameFontNormalSmall", Pal().textDim)
    readout:SetJustifyH("CENTER")
    local rf = CreateFrame("Frame", nil, stack)   -- the readout's hover area, for its tooltip
    rf:SetScript("OnEnter", function(self)
        local d = MC.Describe()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(d.title, 1, 1, 1)
        for _, line in ipairs(d.lines) do
            local c = line[2] == "gold" and GOLD or { 0.78, 0.74, 0.66 }
            GameTooltip:AddLine(line[1], c[1], c[2], c[3], true)
        end
        GameTooltip:Show()
    end)
    rf:SetScript("OnLeave", function() GameTooltip:Hide() end)
    stack.readoutFrame = rf
    buttons.zoomIn = Button(stack, "+", function() Zoom(1) end, function()
        return "Zoom in", { { "About the middle of the view. The mouse wheel zooms at the pointer." } }
    end)
    buttons.zoomOut = Button(stack, "-", function() Zoom(-1) end, function()
        return "Zoom out", { { "About the middle of the view, out as far as the whole world." } }
    end)
    buttons.fit = Button(stack, "World", Fit, function()
        if DungeonOpen() then return "Whole floor", { { "The dungeon's whole floor in view." } } end
        return "Whole world", { { "Glides out to the whole world. Back returns." } }
    end)
    buttons.back = Button(stack, "Back", MC.Back, function()
        if DungeonOpen() then return "Back to the map", { { "Closes the dungeon's map." } } end
        return "Back", { { "To the view before your last jump (a travel link, a cave, the whole world), this session." } }
    end)
    buttons.dungeon = Button(stack, "Inside", function()
        local inst = InDungeon()
        if inst then R.MapDungeonView.Open(inst) end
    end, function()
        return "This dungeon's map", { { "You are inside a dungeon whose map is known: shows it, one floor at a time. Your position isn't shown on it." } }
    end)
end

local function LayoutStack()
    local pad = stack.pad or Skin(stack)
    local y = -pad
    readout:ClearAllPoints()
    readout:SetPoint("TOP", stack, "TOP", 0, y - 1)
    stack.readoutFrame:ClearAllPoints()
    stack.readoutFrame:SetPoint("TOPLEFT", stack, "TOPLEFT", pad, y)
    stack.readoutFrame:SetSize(BTN_W, 14)
    y = y - 16
    for _, key in ipairs({ "dungeon", "zoomIn", "zoomOut", "fit", "back" }) do
        local b = buttons[key]
        if b:IsShown() then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", stack, "TOPLEFT", pad, y)
            y = y - BTN_H - GAP
        end
    end
    stack:SetSize(BTN_W + pad * 2, -y + pad - GAP)
    stack:ClearAllPoints()
    -- above the game's quest-panel button at the canvas's bottom right
    stack:SetPoint("BOTTOMRIGHT", WorldMapFrame:GetCanvasContainer(), "BOTTOMRIGHT", -4, 34)
end

function MC.Update()
    local want = MV.Installed() and MV.Shown() and MXP.Get("controls") and (MV.Ready() or DungeonOpen())
    if not want then
        if stack then stack:Hide() end
        return
    end
    BuildStack()
    local dungeon = DungeonOpen()
    if dungeon then
        readout:SetText(("%.1fx"):format(R.MapDungeonView.Factor()))
    elseif MV.Ready() then
        local _, _, zoom = MV.View()
        readout:SetText(zoom < 10 and ("%.1fx"):format(zoom) or ("%dx"):format(math.floor(zoom + 0.5)))
    else
        readout:SetText("")
    end
    buttons.dungeon:SetShown((InDungeon() ~= nil) and not dungeon)
    local canBack = dungeon or MV.CanGoBack()
    SetUsable(buttons.back, canBack, "There is no earlier view to go back to.")
    LayoutStack()
    stack:Show()
end

---------------------------------------------------------------------------
-- The context bar: an open cave's or dungeon's map
---------------------------------------------------------------------------
local bar, owner

local function BuildBar()
    if bar then return end
    bar = CreateFrame("Frame", "TwichUIMapContext", WorldMapFrame, "BackdropTemplate")
    bar:SetFrameStrata("HIGH")
    bar:EnableMouse(true)
    bar:Hide()
    bar.title = Text(bar, "GameFontNormal")
    bar.title:SetWordWrap(false)
    bar.sub = Text(bar, "GameFontNormalSmall", Pal().textDim)
    bar.sub:SetWordWrap(false)
    bar.note = Text(bar, "GameFontNormalSmall", Pal().stone)
    bar.note:SetWordWrap(false)
    bar.prev = Button(bar, "<", function() if bar.spec and bar.spec.onPrev then bar.spec.onPrev() end end, function()
        return "Floor above", { { "The previous floor of this map." } }
    end)
    bar.next = Button(bar, ">", function() if bar.spec and bar.spec.onNext then bar.spec.onNext() end end, function()
        return "Floor below", { { "The next floor of this map." } }
    end)
    bar.floor = Text(bar, "GameFontHighlightSmall")
    bar.floor:SetWordWrap(false)
    bar.leave = Button(bar, "Leave", function() if bar.spec and bar.spec.onLeave then bar.spec.onLeave() end end, function()
        return bar.spec and bar.spec.leaveTitle or "Leave", { { bar.spec and bar.spec.leaveTip or "Closes this map." } }
    end)
    bar.prev:SetWidth(22)
    bar.next:SetWidth(22)
    bar.leave:SetWidth(52)
end

-- spec: { title, sub, note, floors, floor, floorName, onPrev, onNext, onLeave, leaveTitle, leaveTip }. who: its owner.
function MC.ShowContext(who, spec)
    BuildBar()
    owner = who
    bar.spec = spec
    local pad = bar.pad or Skin(bar)
    bar.title:SetText(spec.title or "")
    bar.sub:SetText(spec.sub or "")
    bar.note:SetText(spec.note or "")
    local many = (spec.floors or 1) > 1
    bar.prev:SetShown(many)
    bar.next:SetShown(many)
    bar.floor:SetShown(many)
    if many then
        bar.floor:SetText(("%s (%d/%d)"):format(spec.floorName or "Floor", spec.floor, spec.floors))
        SetUsable(bar.prev, spec.floor > 1, "This is the first floor.")
        SetUsable(bar.next, spec.floor < spec.floors, "This is the last floor.")
    end
    -- row 1: title and Leave; row 2: what it is, and the floors; row 3: the note
    bar.title:ClearAllPoints()
    bar.title:SetPoint("TOPLEFT", bar, "TOPLEFT", pad + 6, -pad - 3)
    bar.leave:ClearAllPoints()
    bar.leave:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -pad - 3, -pad - 2)
    bar.sub:ClearAllPoints()
    bar.sub:SetPoint("TOPLEFT", bar.title, "BOTTOMLEFT", 0, -3)
    local width = math.max(bar.title:GetStringWidth() + 70, bar.sub:GetStringWidth() + 12)
    if many then
        bar.prev:ClearAllPoints()
        bar.prev:SetPoint("LEFT", bar.sub, "RIGHT", 10, 0)
        bar.floor:ClearAllPoints()
        bar.floor:SetPoint("LEFT", bar.prev, "RIGHT", 6, 0)
        bar.next:ClearAllPoints()
        bar.next:SetPoint("LEFT", bar.floor, "RIGHT", 6, 0)
        width = math.max(width, bar.sub:GetStringWidth() + 10 + 22 + 6 + bar.floor:GetStringWidth() + 6 + 22 + 12)
    end
    local height = pad * 2 + 6 + 14 + 3 + 12
    if spec.note and spec.note ~= "" then
        bar.note:ClearAllPoints()
        bar.note:SetPoint("TOPLEFT", bar.sub, "BOTTOMLEFT", 0, -4)
        width = math.max(width, bar.note:GetStringWidth() + 12)
        height = height + 16
    end
    bar:SetSize(math.min(math.ceil(width) + pad * 2 + 12, 560), height + 4)
    bar:ClearAllPoints()
    bar:SetPoint("TOP", WorldMapFrame:GetCanvasContainer(), "TOP", 0, -6)
    bar:Show()
end

function MC.HideContext(who)
    if bar and owner == who then
        bar:Hide()
        bar.spec, owner = nil, nil
    end
end

function MC.ContextShown() return bar ~= nil and bar:IsShown() end

MV.Subscribe(function(event)
    if event == "hide" or event == "off" then
        if stack then stack:Hide() end
        if bar then bar:Hide() bar.spec, owner = nil, nil end
    elseif event ~= "scale" then   -- (a zoom's every step: the view's once-a-frame notice follows)
        MC.Update()
    end
end)
MXP.Subscribe(function() MC.Update() end)
