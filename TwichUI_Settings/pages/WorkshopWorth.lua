-- TwichUI settings: the Workshop's "What's it worth?" tooltip designer (hosted by the Workshop page)
-- A small list of the lines a tooltip section can hold, and a mockup of the tooltip. Drag a line into the mockup to add it, drag a row of
-- the mockup to move it, or use the buttons: click a line to add it, click a row to select it, then Move up / Move down / Remove, and
-- Always / Hold Shift for when it shows. "Enable tooltip" turns the section off; "Reset layout" puts the short default back.
--
-- ONE BUILDER: the mockup is made by the same code as the real tooltip (TwichUI_Workshop/WorthLayout.lua: WL.Rows, WL.Style, WL.COLORS),
-- over made-up items (WL.Example) that are labelled as preview data. Nothing is scanned or read from the game, and nothing here changes
-- a figure: the layout only chooses which lines appear, in what order, and when.
--
-- LOAD ON DEMAND: the Workshop is not loaded at login. Until it is, this shows one sentence and one button; the button loads the Workshop
-- through its normal safe launcher (never in combat, opens no window). Hovering an item never loads anything.
--
-- THE DRAG is the same virtual drag Magic Inventory's editor uses (MagicInventoryDrag.lua): a label follows the pointer while the button
-- is held and where it is let go decides; the game's cursor is never touched; letting go outside the mockup changes nothing. Every
-- drag has a click alternative. The handlers (D.Drop, D.GapAt ...) are reachable without a pointer, so they can be driven by tests; real
-- pointer-driven dragging has to be checked in the game (docs/workshop.md, "What's it worth?").
--
-- What is saved is the layout and the on/off choice in the profile in use (WL.SetLines / WL.SetEnabled), after every change.

local R = TwichUI
local D = {}
R.WorkshopWorthDesigner = D

local W = 644
local LIST_W, COL_X, MOCK_W = 196, 212, 304
local SIDE_X = COL_X + MOCK_W + 12
local SIDE_W = W - SIDE_X
local INNER, PAD_IN, ROW_H = MOCK_W - 20, 10, 16
local TOP = 64                          -- where the body starts under the header
local AMBER = { 0.93, 0.72, 0.38 }
local NEWER = "These settings were saved by a newer TwichUI, so they are left alone."

local function Wg() return R.SettingsWidgets end
local function WL() return R.Workshop and R.Workshop.WorthLayout end
local function Launcher() return R.WorkshopLauncher end
local function DragKit() local P = R.MagicInventoryPage return P and P.Drag end

local f, built
local shiftMode = false      -- the preview: false = Normal, true = Hold Shift
local exampleKey = "ordinary"
local selected               -- the id of the selected line, or nil
local said, saidTone         -- what just happened, or why it did not
local height = 120
local model                  -- the last mockup drawn: { sec, layout, tops, bottoms, gaps }
local rows, listButtons = {}, {}
local queued = false

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function Say(text, tone) said, saidTone = text, tone end

local function Tip(frame, title, text)
    frame:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        if text then GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function Toggle(parent, label, w, onClick)
    if R.SettingsMaterial then
        local b = R.SettingsMaterial.Segment(parent, label, w, onClick)
        b.SetOn = b.SetSelected
        return b
    end
    local F = R.FrameLook
    if F and F.Ready() then return F.Toggle(parent, label, w, onClick) end
    return R.ChronicleStyle.Toggle(parent, label, w, onClick, Wg().pal)
end

local function Label(id)
    local L = WL()
    local t = L and L.BY_ID[id]
    return t and t.label or tostring(id)
end

local function Relayout()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        local UI = R.SettingsUI
        if UI and UI.Refresh then UI.Refresh() end
    end)
end

function D.Height() return height end
function D.Mode() return shiftMode end
function D.Selected() return selected end
function D.Said() return said, saidTone end
function D.Model() return model end
function D.Row(i) return rows[i] end              -- the i-th row of the mockup (a Button), for tests and the simulator
function D.ListButton(i) return listButtons[i] end

---------------------------------------------------------------------------
-- Changing the layout (each saves at once; the buttons, the drag and the tests all come through here)
---------------------------------------------------------------------------
local function Commit(list, text)
    local L = WL()
    if not L then return false end
    local ok, why = L.SetLines(list)
    if not ok then
        Say(why == "newer" and NEWER or "That couldn't be saved.", "warn")
        D.Refresh()
        return false
    end
    if text then Say(text) end
    D.Refresh()
    return true
end

-- at: the place in the layout (nil = the end). A new line shows in the preview you are looking at: Always in the Normal preview, its
-- usual choice in the Hold Shift preview.
function D.AddLine(id, at)
    local L = WL()
    if not L then return false end
    local list = L.Get().lines
    local t = L.BY_ID[id]
    if not t then return false end
    if L.IndexOf(list, id) then
        selected = id
        Say(t.label .. " is already in the preview.", "warn")
        D.Refresh()
        return false
    end
    local out = L.Add(list, id, at, shiftMode and t.when or "always")
    if not out then return false end
    selected = id
    return Commit(out, "Added " .. t.label .. ".")
end

function D.RemoveLine(id)
    local L = WL()
    if not L then return false end
    local out = L.Remove(L.Get().lines, id)
    if not out then return false end
    if selected == id then selected = nil end
    return Commit(out, "Removed " .. Label(id) .. ".")
end

function D.MoveLine(id, before)
    local L = WL()
    if not L then return false end
    local list = L.Get().lines
    local out = L.Move(list, id, before)
    if not out then return false end
    local same = true
    for i = 1, #list do if list[i].id ~= out[i].id then same = false break end end
    if same then Say("It stays where it is."); D.Refresh(); return true end
    selected = id
    return Commit(out, "Moved " .. Label(id) .. ".")
end

function D.StepLine(id, dir)
    local L = WL()
    if not L then return false end
    local out = L.Step(L.Get().lines, id, dir, shiftMode)
    if not out then return false end
    return Commit(out, nil)
end

function D.SetWhen(id, when)
    local L = WL()
    if not L then return false end
    local out = L.SetWhen(L.Get().lines, id, when)
    if not out then return false end
    local text = when == "always" and (Label(id) .. " shows always.") or (Label(id) .. " shows while you hold Shift.")
    if when == "shift" and not shiftMode then
        shiftMode = true   -- otherwise the row would vanish from the preview you are looking at
        text = text .. " Showing the Hold Shift preview."
    end
    return Commit(out, text)
end

function D.Select(id)
    selected = (selected ~= id) and id or nil
    D.Refresh()
end

function D.SetMode(shift)
    shiftMode = shift == true
    D.Refresh()
end

function D.SetExample(key)
    local L = WL()
    exampleKey = (L and L.EXAMPLE_BY_KEY[key]) and key or "ordinary"
    D.Refresh()
end

function D.SetEnabled(on)
    local L = WL()
    if not L then return false end
    local ok, why = L.SetEnabled(on and true or false)
    if not ok then
        Say(why == "newer" and NEWER or "That couldn't be saved.", "warn")
    else
        Say(on and "Tooltip on." or "Tooltip off. Your layout is kept.")
    end
    D.Refresh()
    return ok
end

function D.ResetLayout()
    local L = WL()
    if not L then return false end
    local ok, why = L.Reset()
    if not ok then
        Say(why == "newer" and NEWER or "That couldn't be saved.", "warn")
    else
        selected = nil
        Say("The short default layout is back.")
    end
    D.Refresh()
    return ok
end

---------------------------------------------------------------------------
-- Where a drop lands
---------------------------------------------------------------------------
-- The gap (0 = before the first row, n = after the last) nearest to `rel`, the distance down from the top of the mockup.
function D.GapAt(rel)
    if not model then return nil end
    for i = 1, #model.sec.rows do
        if rel < (model.tops[i] + model.bottoms[i]) / 2 then return i - 1 end
    end
    return #model.sec.rows
end

-- The place in the layout a gap means: before the line now shown after it, or after the last line shown.
function D.PositionOf(gap)
    if not model then return nil end
    local rws = model.sec.rows
    if rws[gap + 1] then return rws[gap + 1].index end
    local last = rws[#rws]
    return last and (last.index + 1) or (#model.layout.lines + 1)
end

-- Which gap the pointer is over, or nil when it is not over the mockup.
function D.Find()
    local mock = f and f.mock
    if not (mock and model and GetCursorPosition) then return nil end
    local x, y = GetCursorPosition()
    local scale = mock:GetEffectiveScale() or 1
    if not (x and y and scale > 0) then return nil end
    x, y = x / scale, y / scale
    local l, t, r, b = mock:GetLeft(), mock:GetTop(), mock:GetRight(), mock:GetBottom()
    if not (l and t and r and b) or x < l or x > r or y > t or y < b then return nil end
    return D.GapAt(t - y)
end

local function ShowMarker(gap)
    if not (f and f.marker) then return end
    if gap == nil or not model or model.gaps[gap] == nil then f.marker:Hide() return end
    f.marker:ClearAllPoints()
    f.marker:SetPoint("TOPLEFT", f.mock, "TOPLEFT", 6, -model.gaps[gap])
    f.marker:SetPoint("TOPRIGHT", f.mock, "TOPRIGHT", -6, -model.gaps[gap])
    f.marker:Show()
end

-- Let go over gap `gap`: a line from the list is added there, a row of the mockup is moved there.
function D.Drop(src, gap)
    if type(src) ~= "table" or gap == nil then return false end
    local pos = D.PositionOf(gap)
    if src.kind == "list" then return D.AddLine(src.id, pos) end
    if src.kind == "row" then return D.MoveLine(src.id, pos) end
    return false
end

local function DragCancelled()
    Say("Nothing changed.")
    D.Refresh()
end

function D.StartDrag(src)
    local Dr = DragKit()
    local L = WL()
    if not (Dr and L and model) then return false end
    if src.kind == "list" and L.IndexOf(model.layout.lines, src.id) then return false end   -- already in the preview
    if src.kind == "row" then
        for _, fr in ipairs(rows) do if fr.rowId == src.id then fr:SetAlpha(0.4) end end   -- the row being carried
    end
    Dr.Start({ src = src, label = Label(src.id), find = D.Find, hover = ShowMarker, drop = D.Drop, cancel = DragCancelled })
    return true
end

---------------------------------------------------------------------------
-- The mockup's rows
---------------------------------------------------------------------------
local function MakeRow(i)
    local fr = CreateFrame("Button", nil, f.mock)
    fr:SetHeight(ROW_H)
    fr.wash = fr:CreateTexture(nil, "BACKGROUND")
    fr.wash:SetAllPoints()
    fr.wash:SetColorTexture(1, 1, 1, 0.07)
    fr.wash:Hide()
    fr.sel = fr:CreateTexture(nil, "BACKGROUND")
    fr.sel:SetAllPoints()
    fr.sel:SetColorTexture(0.80, 0.65, 0.36, 0.22)
    fr.sel:Hide()
    fr.bar = fr:CreateTexture(nil, "ARTWORK")   -- marks a Hold Shift line in the Hold Shift preview
    fr.bar:SetColorTexture(0.80, 0.65, 0.36, 0.9)
    fr.bar:SetPoint("TOPLEFT", -6, -2)
    fr.bar:SetPoint("BOTTOMLEFT", -6, 2)
    fr.bar:SetWidth(2)
    fr.bar:Hide()
    fr.left = fr:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    fr.left:SetJustifyH("LEFT")
    fr.left:SetPoint("TOPLEFT", 0, -1)
    fr.right = fr:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    fr.right:SetJustifyH("RIGHT")
    fr.right:SetPoint("TOPRIGHT", 0, -1)
    fr.wide = fr:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    fr.wide:SetJustifyH("LEFT")
    fr.wide:SetPoint("TOPLEFT", 0, -1)
    fr.wide:SetWidth(INNER)
    fr:RegisterForDrag("LeftButton")
    fr:SetScript("OnEnter", function(self) self.wash:Show() end)
    fr:SetScript("OnLeave", function(self) self.wash:Hide() end)
    fr:SetScript("OnClick", function(self) if self.rowId then D.Select(self.rowId) end end)
    fr:SetScript("OnDragStart", function(self) if self.rowId then D.StartDrag({ kind = "row", id = self.rowId }) end end)
    fr:SetScript("OnDragStop", function() local Dr = DragKit() if Dr then Dr.Stop() end end)
    rows[i] = fr
    return fr
end

local function Color(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end

-- Draws one row of the section; returns its height
local function PaintRow(fr, row)
    local L = WL()
    local C = L.COLORS
    fr.rowId, fr.rowIndex = row.id, row.index
    fr.left:Hide(); fr.right:Hide(); fr.wide:Hide()
    local h = ROW_H
    if not row.line then
        -- a line with nothing to say for this example: it keeps its place so it can still be moved or removed
        fr.wide:SetText("(" .. Label(row.id) .. ": nothing to show for this example)")
        Color(fr.wide, C.quiet, 0.8)
        fr.wide:Show()
        h = math.max(ROW_H, (fr.wide:GetStringHeight() or 12) + 4)
    else
        local kind, a, b = L.Style(row.line)
        if kind == "double" then
            fr.right:SetText(b)
            Color(fr.right, C.right)
            fr.right:Show()
            fr.left:SetWidth(math.max(60, INNER - (fr.right:GetStringWidth() or 0) - 8))
            fr.left:SetText(a)
            Color(fr.left, C.left)
            fr.left:Show()
            h = math.max(ROW_H, (fr.left:GetStringHeight() or 12) + 4)
        else
            fr.wide:SetText(a)
            Color(fr.wide, C[kind] or C.plain)
            fr.wide:Show()
            h = math.max(ROW_H, (fr.wide:GetStringHeight() or 12) + 4)
        end
    end
    fr.sel:SetShown(row.id == selected)
    fr.bar:SetShown(shiftMode and row.when == "shift")
    fr.wash:Hide()
    fr:SetAlpha(1)
    fr:SetHeight(h)
    return h
end

local function PaintMock(L, layout)
    local mock = f.mock
    local r, ctx = L.Example(exampleKey)
    local sec = L.Rows(r, ctx, layout, shiftMode, true)
    local y = PAD_IN
    mock.name:ClearAllPoints(); mock.name:SetPoint("TOPLEFT", PAD_IN, -y)
    y = y + ROW_H + 8   -- the blank line a real tooltip leaves
    mock.title:SetText(sec.title)
    mock.title:ClearAllPoints(); mock.title:SetPoint("TOPLEFT", PAD_IN, -y)
    y = y + ROW_H + 2
    local m = { sec = sec, layout = layout, tops = {}, bottoms = {}, gaps = {} }
    m.gaps[0] = y - 1
    for i, row in ipairs(sec.rows) do
        local fr = rows[i] or MakeRow(i)
        fr:ClearAllPoints()
        fr:SetPoint("TOPLEFT", mock, "TOPLEFT", PAD_IN, -y)
        fr:SetWidth(INNER)
        local h = PaintRow(fr, row)
        fr:Show()
        m.tops[i], m.bottoms[i] = y, y + h
        y = y + h
        m.gaps[i] = y
    end
    for i = #sec.rows + 1, #rows do rows[i].rowId = nil; rows[i]:Hide() end
    if #sec.rows == 0 then
        mock.empty:ClearAllPoints(); mock.empty:SetPoint("TOPLEFT", PAD_IN, -y)
        mock.empty:Show()
        y = y + 30
    else
        mock.empty:Hide()
    end
    if sec.hint then
        mock.hint:SetText(sec.hint)
        mock.hint:ClearAllPoints(); mock.hint:SetPoint("TOPLEFT", PAD_IN, -y)
        mock.hint:Show()
        y = y + ROW_H
    else
        mock.hint:Hide()
    end
    y = y + PAD_IN
    mock:SetHeight(math.max(y, 120))
    model = m
    return sec
end

---------------------------------------------------------------------------
-- Painting the whole designer
---------------------------------------------------------------------------
local function At(c, x, y) c:ClearAllPoints(); c:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y) end

local function ShowGroup(on)
    for _, c in ipairs(f.group) do c:SetShown(on) end
    f.invite:SetShown(not on)
    f.inviteButton:SetShown(not on)
end

-- The list needs the line types, which the Workshop provides: made the first time the Workshop is loaded.
local function BuildList(L)
    if #listButtons > 0 then return end
    local G = Wg()
    local pal = G.pal
    for i, t in ipairs(L.TYPES) do
        local b = CreateFrame("Button", nil, f, "BackdropTemplate")
        b:SetSize(LIST_W, 28)
        G.Well(b)
        if R.SettingsMaterial then R.SettingsMaterial.MaterialHover(b) end
        At(b, 4, TOP + 22 + (i - 1) * 32)
        b.label = G.Text(b, "body")
        b.label:SetPoint("LEFT", 10, 0)
        b.label:SetWidth(LIST_W - 40)
        b.label:SetWordWrap(false)
        b.check = b:CreateTexture(nil, "OVERLAY")
        b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        b.check:SetSize(18, 18)
        b.check:SetPoint("RIGHT", -6, 0)
        b.check:SetDesaturated(true)
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnClick", function(self)
            if self.added then D.Select(self.id) else D.AddLine(self.id) end
        end)
        b:SetScript("OnDragStart", function(self) if not self.added then D.StartDrag({ kind = "list", id = self.id }) end end)
        b:SetScript("OnDragStop", function() local Dr = DragKit() if Dr then Dr.Stop() end end)
        b:HookScript("OnEnter", function(self)
            if not R.SettingsMaterial then self:SetBackdropColor(pal.hoverFill[1], pal.hoverFill[2], pal.hoverFill[3], 1) end
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(t.label, 1, 1, 1)
            GameTooltip:AddLine(t.what, 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(self.hint or "", 0.93, 0.72, 0.38, true)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function(self)
            if not R.SettingsMaterial then self:SetBackdropColor(pal.well[1], pal.well[2], pal.well[3], 1) end
            if GameTooltip then GameTooltip:Hide() end
        end)
        listButtons[i] = b
        f.group[#f.group + 1] = b
    end
end

function D.Refresh()
    if not f then return end
    if not built then D.Build() end
    local L = WL()
    local G = Wg()
    local pal = G.pal
    local old = height
    if not L then
        ShowGroup(false)
        if f.marker then f.marker:Hide() end
        At(f.invite, 4, 4)
        f.invite:SetWidth(W - 8)
        f.invite:SetText("The tooltip designer needs the Workshop, which loads the first time you ask for it. This loads it; it opens no window and does nothing else.")
        At(f.inviteButton, 4, 4 + (f.invite:GetStringHeight() or 24) + 10)
        f.said:SetText(said or "")
        f.said:SetWidth(W - 8)
        f.said:Show()
        At(f.said, 4, 4 + (f.invite:GetStringHeight() or 24) + 44)
        G.Color(f.said, saidTone == "warn" and AMBER or pal.textDim)
        height = 100 + ((said and said ~= "") and 20 or 0)
        if height ~= old then Relayout() end
        return
    end
    BuildList(L)
    ShowGroup(true)
    f.said:Show()
    local layout = L.Get()
    if selected and not L.IndexOf(layout.lines, selected) then selected = nil end

    -- header
    f.enable:SetChecked(layout.enabled)
    f.reset:SetEnabled(not L.IsDefault())
    f.modeNormal:SetOn(not shiftMode)
    f.modeShift:SetOn(shiftMode)
    local ex = L.EXAMPLE_BY_KEY[exampleKey] or L.EXAMPLES[1]
    f.example:SetValue(exampleKey, ex.label)

    -- the list of lines
    for i, t in ipairs(L.TYPES) do
        local b = listButtons[i]
        local added = L.IndexOf(layout.lines, t.id) ~= nil
        b.id, b.added = t.id, added
        b.label:SetText(t.label)
        G.Color(b.label, added and pal.stone or pal.text)
        b.check:SetShown(added)
        b.hint = added and "In the preview. Click to select it." or "Click to add it, or drag it into the preview."
    end

    -- the mockup
    local sec = PaintMock(L, layout)
    local mockH = f.mock:GetHeight() or 120
    At(f.mock, COL_X, TOP + 36)
    f.mock:SetSize(MOCK_W, mockH)

    -- what the preview is
    f.caption:SetText(sec.empty and "For this example the tooltip would show nothing." or
        (shiftMode and "Preview data: a made-up item. A bar marks lines that show only while you hold Shift." or "Preview data: a made-up item. Nothing is read from your game."))
    At(f.caption, COL_X, TOP + 36 + mockH + 6)
    f.caption:SetWidth(MOCK_W)

    -- the selected line
    local entry
    for _, e in ipairs(layout.lines) do if e.id == selected then entry = e end end
    f.selTitle:SetWidth(SIDE_W)
    if entry then
        f.selTitle:SetText(Label(entry.id))
        G.Color(f.selTitle, pal.bronzeText)
        f.up:SetEnabled(L.Step(layout.lines, entry.id, -1, shiftMode) ~= nil)
        f.down:SetEnabled(L.Step(layout.lines, entry.id, 1, shiftMode) ~= nil)
        f.remove:SetEnabled(true)
        f.visLabel:SetText("Shows")
        f.always:SetOn(entry.when == "always")
        f.holdShift:SetOn(entry.when == "shift")
    else
        f.selTitle:SetText("Click a line in the preview to move it, remove it or change when it shows.")
        G.Color(f.selTitle, pal.textDim)
    end
    for _, c in ipairs({ f.up, f.down, f.remove, f.visLabel, f.always, f.holdShift }) do c:SetShown(entry ~= nil) end
    At(f.selTitle, SIDE_X, TOP + 36)
    local sy = TOP + 36 + math.max(24, (f.selTitle:GetStringHeight() or 24)) + 8
    At(f.up, SIDE_X, sy); At(f.down, SIDE_X, sy + 30); At(f.remove, SIDE_X, sy + 60)
    At(f.visLabel, SIDE_X, sy + 94)
    At(f.always, SIDE_X, sy + 112); At(f.holdShift, SIDE_X, sy + 142)

    -- the sentence at the bottom
    local listBottom = TOP + 22 + #L.TYPES * 32
    local bottom = math.max(listBottom, TOP + 36 + mockH + 6 + (f.caption:GetStringHeight() or 12), sy + 172)
    f.said:SetText(said or "")
    G.Color(f.said, saidTone == "warn" and AMBER or pal.textDim)
    f.said:SetWidth(W - 8)
    At(f.said, 4, bottom + 8)
    height = bottom + 8 + ((said and said ~= "") and 22 or 4)
    if height ~= old then Relayout() end
end

---------------------------------------------------------------------------
-- Building the controls (once)
---------------------------------------------------------------------------
function D.Build()
    if built then return end
    built = true
    local G = Wg()
    local pal = G.pal
    local group = {}
    f.group = group
    local function Add(c) group[#group + 1] = c return c end

    -- header
    f.enable = Add(G.Checkbox(f, function(v) D.SetEnabled(v) end))
    At(f.enable, 4, 4)
    f.enableText = Add(G.Text(f, "body"))
    f.enableText:SetText("Enable tooltip")
    f.enableText:SetPoint("LEFT", f.enable, "RIGHT", 8, 0)
    Tip(f.enable, "Enable tooltip", "Off: items show no \"What's it worth?\" section. Your layout is kept either way.")
    f.reset = Add(G.Button(f, "Reset layout", 112, "secondary", function() D.ResetLayout() end))
    At(f.reset, W - 112, 0)
    Tip(f.reset, "Reset layout", "Puts back the short default: the suggestion and the values, with the details under Hold Shift.")
    f.instruction = Add(G.Text(f, "small"))
    f.instruction:SetText("Drag lines into the preview.")
    G.Color(f.instruction, pal.textDim)
    At(f.instruction, 4, 36)

    f.listTitle = Add(G.Text(f, "meta"))
    f.listTitle:SetText("Lines")
    At(f.listTitle, 4, TOP)

    -- the preview's choices
    f.modeNormal = Add(Toggle(f, "Normal", 84, function() D.SetMode(false) end))
    At(f.modeNormal, COL_X, TOP)
    f.modeShift = Add(Toggle(f, "Hold Shift", 96, function() D.SetMode(true) end))
    At(f.modeShift, COL_X + 88, TOP)
    Tip(f.modeShift, "Hold Shift", "How the tooltip looks while you hold Shift: the Always lines and the Hold Shift lines, in your order.")
    f.example = Add(G.Dropdown(f, 168, function(value) D.SetExample(value) end))
    f.example:SetChoices(function()
        local out = {}
        for _, e in ipairs(WL().EXAMPLES) do out[#out + 1] = { value = e.key, label = e.label } end
        return out
    end)
    At(f.example, COL_X + 204, TOP)
    f.example:SetWidth(W - COL_X - 204)
    Tip(f.example, "Example", "Which made-up item the preview shows, so you can see how a missing price or an action that can't be done reads.")

    -- the mockup: a tooltip
    f.mock = Add(CreateFrame("Frame", nil, f, "BackdropTemplate"))
    local mock = f.mock
    mock:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    mock:SetBackdropColor(0.07, 0.07, 0.12, 0.96)
    mock:SetBackdropBorderColor(0.62, 0.62, 0.62, 1)
    mock:SetSize(MOCK_W, 160)
    mock.name = mock:CreateFontString(nil, "OVERLAY", "GameTooltipHeaderText")
    mock.name:SetText("Example item")
    mock.name:SetTextColor(1, 1, 1)
    mock.title = mock:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    mock.title:SetTextColor(1, 0.82, 0)
    mock.hint = mock:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    mock.hint:SetTextColor(0.55, 0.55, 0.55)
    mock.empty = mock:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    mock.empty:SetWidth(INNER)
    mock.empty:SetJustifyH("LEFT")
    mock.empty:SetText("Drag lines here.")
    mock.empty:SetTextColor(0.55, 0.55, 0.55)
    f.marker = mock:CreateTexture(nil, "OVERLAY")   -- where a dropped line would go
    f.marker:SetColorTexture(0.80, 0.65, 0.36, 1)
    f.marker:SetHeight(2)
    f.marker:Hide()
    f.caption = Add(G.Text(f, "meta"))
    f.caption:SetJustifyH("LEFT")
    f.caption:SetWordWrap(true)

    -- the selected line
    f.selTitle = Add(G.Text(f, "body"))
    f.selTitle:SetJustifyH("LEFT")
    f.selTitle:SetWordWrap(true)
    f.up = Add(G.Button(f, "Move up", SIDE_W, "secondary", function() if selected then D.StepLine(selected, -1) end end))
    f.down = Add(G.Button(f, "Move down", SIDE_W, "secondary", function() if selected then D.StepLine(selected, 1) end end))
    f.remove = Add(G.Button(f, "Remove", SIDE_W, "secondary", function() if selected then D.RemoveLine(selected) end end))
    f.visLabel = Add(G.Text(f, "meta"))
    f.always = Add(Toggle(f, "Always", SIDE_W, function() if selected then D.SetWhen(selected, "always") end end))
    f.holdShift = Add(Toggle(f, "Hold Shift", SIDE_W, function() if selected then D.SetWhen(selected, "shift") end end))

    -- the status sentence
    f.said = G.Text(f, "small")   -- not in the group: it speaks in both states
    f.said:SetJustifyH("LEFT")
    f.said:SetWordWrap(true)

    -- before the Workshop is loaded
    f.invite = G.Text(f, "body")
    f.invite:SetJustifyH("LEFT")
    f.invite:SetWordWrap(true)
    f.inviteButton = G.Button(f, "Open the designer", 160, "primary", function()
        local launcher = Launcher()
        if not launcher then Say("The Workshop can't be loaded here.", "warn") D.Refresh() return end
        local ok, why = launcher.Load()
        if not ok then Say(launcher.Explain(why), "warn") else Say(nil) end
        D.Refresh()
    end)
end

---------------------------------------------------------------------------
-- The hosted frame
---------------------------------------------------------------------------
function D.Frame()
    if f then return f end
    f = CreateFrame("Frame")
    f:SetWidth(W)
    f:Hide()
    f:SetScript("OnShow", function() D.Refresh() end)
    f:SetScript("OnHide", function()
        local Dr = DragKit()
        if Dr and Dr.Active() then Dr.Cancel() end
        if Wg().CloseMenu then Wg().CloseMenu() end
        said = nil
    end)
    return f
end

-- A profile change brings another profile's layout: the selection belongs to the old one.
if R.Profiles and R.Profiles.OnApply then
    R.Profiles.OnApply("views", "workshop-worth-designer", function()
        selected = nil
        D.Refresh()
    end)
end
