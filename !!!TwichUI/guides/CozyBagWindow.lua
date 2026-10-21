-- TwichUI: Cozy Sleeping Bag guide, the window
-- A small movable window: what the guide is, how far along the chain you are, the steps in order with a mark and a word for
-- each state, and the chosen step's instructions, places and pin buttons. It draws what guides/CozyBag.lua says and asks
-- it to do everything else (it reads no quests, makes no pins). Built on first open; while closed it holds nothing and the
-- controller listens to nothing. Drawn with TwichUI's own look (Look.lua), so it looks finished without any other addon.
--
-- State is shown by a word as well as a mark and a color: Done (a check), Current (an arrow), In progress, Later, Optional.
-- Opened with /tui bag, the settings page "Cozy Sleeping Bag", or R.CozyBagWindow.Toggle(). Never opens by itself.

local R = TwichUI
local D = R.CozyBagData
local C = R.CozyBag
local W = {}
R.CozyBagWindow = W

local WIDTH, HEIGHT = 400, 568
local PAD = 14
local ROW_H, MAX_ROWS = 24, 8
local PLACE_H = 24
local BUTTON_H = 24
local CHECK = [[Interface\Buttons\UI-CheckBox-Check]]

local L, K          -- Look and its palette: looked up when first built
local f                -- the window
local rows = {}
local placeRows = {}
local note             -- the last thing an action said, until the step or the window changes

local function Percent(n) return ("%.1f"):format(n) end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
-- The short word beside a step in the list, and the sentence under its title in the detail.
local function Words(entry)
    local state, phase = entry.state, entry.phase
    if state == "done" then
        if entry.inferred then return "Done", "Done: a later step shows you got past this one." end
        return "Done", "Done: the game records this quest as finished."
    elseif state == "optional" then
        return phase and "In progress" or "Optional", "Optional: the bag does not need this step."
    end
    if phase == "ready" then return "Turn in", "Its objectives are complete but the quest is not turned in yet." end
    if phase == "accepted" then
        return "In progress", state == "current" and "You have this quest; it is not finished yet." or "You have this quest already, though an earlier step is still open."
    end
    if state == "current" then return "Current", "This is the step to do now." end
    return "Later", "Not yet: an earlier step comes first."
end

local function Say(text)
    note = text
    if f and f.note then f.note:SetText(text or "") end
end

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------
local function Tip(frame, title, body) R.Interact.Tip(frame, title, body) end

local function NewRow(i)
    local row = CreateFrame("Button", nil, f.list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", f.list, "TOPLEFT", 4, -4 - (i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", f.list, "TOPRIGHT", -4, -4 - (i - 1) * ROW_H)
    row.fill = L.Solid(row, "BACKGROUND", K.tealLo, 0.55)
    row.fill:SetAllPoints()
    row.bar = L.Solid(row, "ARTWORK", K.tealHi, 1)
    row.bar:SetWidth(2)
    row.bar:SetPoint("TOPLEFT", 0, 0)
    row.bar:SetPoint("BOTTOMLEFT", 0, 0)
    row.mark = L.Text(row, "body")
    row.mark:SetPoint("LEFT", 8, 0)
    row.mark:SetWidth(18)
    row.mark:SetJustifyH("CENTER")
    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetTexture(CHECK)
    row.check:SetSize(16, 16)
    row.check:SetPoint("CENTER", row.mark, "CENTER", 0, 0)
    row.status = L.Text(row, "meta")
    row.status:SetPoint("RIGHT", -8, 0)
    row.status:SetJustifyH("RIGHT")
    row.status:SetWidth(78)
    row.title = L.Text(row, "body")
    row.title:SetPoint("LEFT", row.mark, "RIGHT", 6, 0)
    row.title:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
    row.title:SetWordWrap(false)
    L.Hover(row, K.text, 0.05)
    row:SetScript("OnClick", function(self) if self.stepId then C.Pick(self.stepId) end end)
    return row
end

-- A small text button for a place: Pin / Show / Navigate.
local function NewPlaceRow()
    local row = CreateFrame("Frame", nil, f.content)
    row:SetHeight(PLACE_H)
    row.label = L.Text(row, "small")
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.go = L.Button(row, "Go", 40, "secondary", function() W.Act("go", row.place) end)
    row.go:SetPoint("RIGHT", 0, 0)
    row.go:SetHeight(BUTTON_H - 4)
    row.show = L.Button(row, "Show", 46, "secondary", function() W.Act("show", row.place) end)
    row.show:SetPoint("RIGHT", row.go, "LEFT", -4, 0)
    row.show:SetHeight(BUTTON_H - 4)
    row.pin = L.Button(row, "Pin", 40, "secondary", function() W.Act("pin", row.place) end)
    row.pin:SetPoint("RIGHT", row.show, "LEFT", -4, 0)
    row.pin:SetHeight(BUTTON_H - 4)
    Tip(row.pin, "Pin this place", "Saves a pin of your own on the world map here. It is one of your saved pins: you can rename, keep or delete it like any other. Nothing is sent.")
    Tip(row.show, "Show on map", "Moves your world map to this pin and picks it out. Pin the place first.")
    Tip(row.go, "Navigate", "Plans a walking route here and guides you along it (Navigation, when it is turned on). Only when you press it.")
    return row
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function RenderProgress(r)
    local label, fillTo
    fillTo = 0
    if r.status == "loading" then
        label = "Checking quest progress..."
    elseif r.status == "needs-faction" then
        label = "Your faction could not be read."
    elseif r.complete then
        label, fillTo = ("All %d steps done"):format(r.total), 1
    else
        label, fillTo = ("%d of %d steps done"):format(r.done, r.total), r.total > 0 and r.done / r.total or 0
    end
    f.progress:SetText(label)
    local w = math.max(0, (f.barBack:GetWidth() or 0) * fillTo)
    f.barFill:SetWidth(math.max(0.001, w))
    f.barFill:SetShown(fillTo > 0)
    f.intro2:SetText(UnitLevel and UnitLevel("player") and UnitLevel("player") < D.level
        and ("The chain needs level %d."):format(D.level) or "")
end

local function RenderList(r)
    local count = (r.status == "ready") and #r.steps or 0
    for i = #rows + 1, count do rows[i] = NewRow(i) end
    local selectedId = C.View().id
    for i, row in ipairs(rows) do
        local entry = r.steps[i]
        if i > count or not entry then
            row:Hide()
            row.stepId = nil
        else
            local word = Words(entry)
            row.stepId = entry.step.id
            row.title:SetText(entry.step.title)
            row.status:SetText(word)
            local done, current = entry.state == "done", entry.state == "current"
            row.check:SetShown(done)
            if done then row.mark:SetText("")
            elseif current then row.mark:SetText(">")
            elseif entry.step.optional then row.mark:SetText("+")
            else row.mark:SetText(tostring(i)) end
            local chosen = entry.step.id == selectedId
            row.fill:SetShown(chosen)
            row.bar:SetShown(chosen)
            local c = K.text
            if done then c = K.stone elseif current then c = K.tealHi elseif entry.state == "upcoming" then c = K.textDim end
            L.Color(row.title, c)
            L.Color(row.mark, c)
            L.Color(row.status, current and K.tealHi or K.stone)
            row:Show()
        end
    end
    f.listNote:SetShown(count == 0)
    if r.status == "loading" then f.listNote:SetText("Checking quest progress...\nThe steps appear once the game has told TwichUI which quests you have finished.")
    elseif r.status == "needs-faction" then f.listNote:SetText("The two sides of the chain start in different places, and your faction could not be read, so no steps are shown.")
    else f.listNote:SetText("") end
end

local function PinCounts(step)
    local pinned = 0
    for i = 1, #step.places do if C.PinFor(step, i) then pinned = pinned + 1 end end
    return pinned
end

local function RenderDetail(r)
    local step, at = C.SelectedStep()
    local entry = at and r.steps[at]
    if not entry then
        f.dTitle:SetText(r.status == "loading" and "Checking quest progress..." or "")
        f.dStatus:SetText("")
        f.dText:SetText(r.status == "loading" and "Reading which quests this character has finished. This only takes a moment." or "")
        for _, p in ipairs(placeRows) do p:Hide() end
        f.pinStep:Disable()
        f.content:SetHeight(1)
        f.current:Disable()
        return
    end
    local _, long = Words(entry)
    f.dTitle:SetText(step.title)
    f.dStatus:SetText(long)
    L.Color(f.dStatus, entry.state == "current" and K.tealHi or K.stone)
    local text = step.text
    local last = #r.steps - (r.steps[#r.steps].step.optional and 1 or 0)
    if r.complete and step.id == r.steps[last].step.id then text = text .. "\n\nEvery step of the chain is done." end
    f.dText:SetText(text)
    local y = 8 + math.ceil(f.dTitle:GetStringHeight() or 18) + 4
    y = y + math.ceil(f.dStatus:GetStringHeight() or 14) + 6
    y = y + math.ceil(f.dText:GetStringHeight() or 14) + 10
    f.dStatus:ClearAllPoints()
    f.dStatus:SetPoint("TOPLEFT", f.dTitle, "BOTTOMLEFT", 0, -4)
    f.dText:ClearAllPoints()
    f.dText:SetPoint("TOPLEFT", f.dStatus, "BOTTOMLEFT", 0, -6)
    local many = #step.places > 1
    for i = #placeRows + 1, #step.places do placeRows[i] = NewPlaceRow() end
    for i, row in ipairs(placeRows) do
        local place = step.places[i]
        if not place then
            row:Hide()
        else
            row.place = i
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", 0, -y)
            row.label:SetText(("%s (%s, %s)"):format(place.label, Percent(place.x), Percent(place.y)))
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", 0, 0)
            row.label:SetPoint("RIGHT", row.pin, "LEFT", -6, 0)
            row.pin:SetShown(many)
            if not many then
                row.label:SetPoint("RIGHT", row.show, "LEFT", -6, 0)
            end
            local pinned = C.PinFor(step, i) ~= nil
            row.pin.text:SetText(pinned and "Pinned" or "Pin")
            if pinned then row.pin:Disable() else row.pin:Enable() end
            if pinned then row.show:Enable() else row.show:Disable() end
            if C.CanNavigate() then row.go:Enable() else row.go:Disable() end
            row:Show()
            y = y + PLACE_H + 2
        end
    end
    f.content:SetHeight(y + 4)
    local pinned = PinCounts(step)
    if pinned >= #step.places then f.pinStep.text:SetText("Step pinned") f.pinStep:Disable()
    else f.pinStep.text:SetText("Pin this step") f.pinStep:Enable() end
    if f.current then
        if C.View().following or not r.current then f.current:Disable() else f.current:Enable() end
    end
end

local function RenderPosition()
    if not f then return end
    local x, y = C.Position()
    local s = f:GetScale() or 1
    if s <= 0 then s = 1 end
    local sw, sh = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    if sw > 0 and sh > 0 then
        local mx, my = math.max(0, sw / 2 - 40), math.max(0, sh / 2 - 40)
        x, y = math.max(-mx, math.min(mx, x)), math.max(-my, math.min(my, y))
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x / s, y / s)
    local locked = C.Locked()
    f.lock.text:SetText(locked and "Unlock" or "Lock")
    f.remove:SetEnabled(#C.OwnPins() > 0)
end

function W.Render()
    if not (f and f:IsShown()) then return end
    local r = C.Result()
    RenderProgress(r)
    RenderList(r)
    RenderDetail(r)
    RenderPosition()
    f.note:SetText(note or "")
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
function W.Act(what, place)
    local step = C.SelectedStep()
    if not step then return end
    if what == "pin" then
        local pin, how = C.PinPlace(step, place)
        Say(pin and (how == "made" and "Pinned on your map." or "Already pinned.") or how)
    elseif what == "show" then
        local ok, why = C.ShowPlace(step, place)
        Say(ok and "" or why)
    elseif what == "go" then
        local ok, why = C.Navigate(step, place)
        Say(ok and "Navigating." or why)
    elseif what == "pinStep" then
        local made, existing, problem = C.PinStep(step)
        if problem and made == 0 and existing == 0 then Say(problem)
        elseif made > 0 then Say(made == 1 and "Pinned on your map." or ("Pinned %d places on your map."):format(made))
        else Say("Already pinned.") end
    end
    W.Render()
end

local function ConfirmRemove()
    local ids, n, kept = C.OwnPinScope()
    if n == 0 then
        Say(kept > 0 and "Every guide pin is kept, so none were removed." or "There are no guide pins.")
        W.Render()
        return
    end
    local text = ("Remove %d %s this guide made? Only pins the Cozy Sleeping Bag guide made are touched; your other pins stay. This can't be undone."):format(n, n == 1 and "pin" or "pins")
    if kept > 0 then text = text .. ("\n\n%d kept %s will remain."):format(kept, kept == 1 and "pin" or "pins") end
    R.Interact.Confirm("TWICHUI_COZYBAG_REMOVE_PINS", text, function()
        local removed = C.RemoveOwnPins(ids)
        Say(("Removed %d %s."):format(removed, removed == 1 and "pin" or "pins"))
        W.Render()
    end, { accept = "Remove", valid = function()
        local _, now = C.OwnPinScope()
        if now == 0 then return false, "Nothing is left to remove. Nothing was changed." end
        return true
    end })
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Build()
    L = R.Look
    K = L.pal
    f = CreateFrame("Frame", "TwichUICozyBagGuide", UIParent, "BackdropTemplate")
    f:Hide()
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end   -- TwichUI keeps the place, not the game's layout cache
    f:SetScript("OnDragStart", function(self) if not C.Locked() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local px, py = UIParent:GetCenter()
        local s = self:GetScale() or 1
        if cx and cy and px and py then C.SetPosition(math.floor(cx * s - px + 0.5), math.floor(cy * s - py + 0.5)) end
        RenderPosition()
    end)
    f:HookScript("OnShow", function(self)
        R.FitToScreen(self)
        note = nil
        C.Opened()
        W.Render()
    end)
    f:HookScript("OnHide", function() note = nil C.Closed() end)
    L.Shell(f, 34)

    local title = L.Text(f, "title")
    title:SetPoint("TOPLEFT", PAD, -9)
    title:SetText(D.title)
    local close = L.CloseBox(f)
    f.lock = L.Button(f, "Lock", 56, "secondary", function() C.SetLocked(not C.Locked()) W.Render() end)
    f.lock:SetHeight(BUTTON_H - 2)
    f.lock:SetPoint("RIGHT", close, "LEFT", -8, 0)
    Tip(f.lock, "Lock or unlock", "Locked, the window stays where it is. Unlocked, drag it by any empty part.")

    -- Intro and progress
    f.intro = L.Text(f, "small")
    f.intro:SetPoint("TOPLEFT", PAD, -46)
    f.intro:SetWidth(WIDTH - PAD * 2)
    f.intro:SetWordWrap(true)
    f.intro:SetText(D.intro)
    f.intro2 = L.Text(f, "meta")
    f.intro2:SetPoint("TOPLEFT", f.intro, "BOTTOMLEFT", 0, -2)
    f.intro2:SetWidth(WIDTH - PAD * 2)
    f.progress = L.Text(f, "heading")
    f.progress:SetPoint("TOPLEFT", PAD, -98)
    f.barBack = CreateFrame("Frame", nil, f)
    f.barBack:SetPoint("TOPLEFT", PAD, -118)
    f.barBack:SetSize(WIDTH - PAD * 2, 6)
    L.Solid(f.barBack, "BACKGROUND", K.well, 1):SetAllPoints()
    f.barFill = L.Solid(f.barBack, "ARTWORK", K.teal, 1)
    f.barFill:SetPoint("TOPLEFT", 0, 0)
    f.barFill:SetPoint("BOTTOMLEFT", 0, 0)

    -- The steps
    f.list = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.list:SetPoint("TOPLEFT", PAD, -134)
    f.list:SetSize(WIDTH - PAD * 2, MAX_ROWS * ROW_H + 8)
    L.Well(f.list, 0.9)
    f.listNote = L.Text(f.list, "small")
    f.listNote:SetPoint("TOPLEFT", 12, -12)
    f.listNote:SetWidth(WIDTH - PAD * 2 - 24)
    f.listNote:SetWordWrap(true)

    -- The chosen step, in a scroll so long text or a large font never hides the buttons below
    local detailTop = -134 - (MAX_ROWS * ROW_H + 8) - 10
    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", PAD, detailTop)
    f.scroll:SetPoint("BOTTOMRIGHT", -PAD - 18, 92)
    L.ScrollBar(f.scroll)
    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(WIDTH - PAD * 2 - 22, 200)
    f.scroll:SetScrollChild(f.content)
    f.dTitle = L.Text(f.content, "heading")
    f.dTitle:SetPoint("TOPLEFT", 0, -8)
    f.dTitle:SetWidth(WIDTH - PAD * 2 - 22)
    f.dStatus = L.Text(f.content, "meta")
    f.dStatus:SetWidth(WIDTH - PAD * 2 - 22)
    f.dStatus:SetWordWrap(true)
    f.dText = L.Text(f.content, "body")
    f.dText:SetWidth(WIDTH - PAD * 2 - 22)
    f.dText:SetWordWrap(true)

    -- Buttons and the line an action answers on
    f.pinStep = L.Button(f, "Pin this step", 130, "primary", function() W.Act("pinStep") end)
    f.pinStep:SetPoint("BOTTOMLEFT", PAD, 56)
    Tip(f.pinStep, "Pin this step", "Saves a pin of your own on the world map for each place in this step. Pressing it again does not make another. Nothing is sent and no route starts.")
    f.current = L.Button(f, "Back to current step", 122, "secondary", function() C.Follow() end)
    f.current:SetPoint("LEFT", f.pinStep, "RIGHT", 8, 0)
    Tip(f.current, "Back to current step", "Goes back to the step your quests say is next. Looking at another step never changes your progress.")
    f.remove = L.Button(f, "Remove pins...", 100, "danger", ConfirmRemove)
    f.remove:SetPoint("BOTTOMRIGHT", -PAD, 56)
    Tip(f.remove, "Remove this guide's pins", "Asks first. Removes only the pins this guide made. Pins you made yourself, and kept pins, stay.")
    f.reset = L.Button(f, "Reset position", 110, "secondary", function() C.ResetPosition() W.Render() end)
    f.reset:SetPoint("BOTTOMLEFT", PAD, 24)
    Tip(f.reset, "Reset position", "Puts the window back where it starts.")
    f.note = L.Text(f, "meta")
    f.note:SetPoint("BOTTOMLEFT", f.reset, "BOTTOMRIGHT", 10, 6)
    f.note:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    f.note:SetWordWrap(false)

    C.OnChange(W.Render)
    if R.Pins then R.Pins.OnChange(function() if f and f:IsShown() then W.Render() end end) end
    return f
end

---------------------------------------------------------------------------
-- Opening
---------------------------------------------------------------------------
function W.Show()
    if not f then Build() end
    f:Show()
end

function W.Hide() if f then f:Hide() end end

function W.Toggle()
    if f and f:IsShown() then f:Hide() else W.Show() end
end

function W.IsShown() return f ~= nil and f:IsShown() end

-- The window, for the tests.
function W.Frame() return f end
