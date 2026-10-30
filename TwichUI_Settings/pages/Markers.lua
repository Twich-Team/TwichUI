-- TwichUI settings: Markers › Target markers and World markers (markers/: Markers.lua keeps each kind's
-- order, Keys.lua the keys and the game's secure buttons they press). Each tab has the switch and its options,
-- then the order (a frame of this window's own, since eight markers to drag and tick don't fit ordinary rows),
-- then the keys. The order frame is built the first time its tab is shown and its eight tiles are reused on every
-- redraw; while a marker is dragged it follows the pointer (only then), and while the frame is shown it redraws
-- after a change, a key press or combat starting or ending. Nothing here places, moves or clears a marker in the
-- game: the preview only reads what the next key press would do, and every change goes through Markers.lua and
-- Keys.lua. Key bindings are the game's own (Key Bindings > TwichUI lists the same six).

local R = TwichUI
local K = R.SettingsKit
local M = R.Markers
local MK = R.MarkerKeys
local P = {}
R.MarkersPage = P

local W = 644                         -- the settings window's content width
local SLOT, TILE_W, TILE_H = 78, 72, 118
local STRIP_TOP, STRIP_H = -34, TILE_H + 12
local LEAD = 8                        -- the first tile's place in the row
local CANCEL_MARGIN = 48              -- this far above or below the row, letting go leaves the order as it was
local HOST_H = 240

local function Wg() return R.SettingsWidgets end
local function InCombat() return InCombatLockdown and InCombatLockdown() end

local NOUN = { target = "target marker", world = "world marker" }

local editors = {}   -- [kind] = the order frame, once made
local drag           -- the drag in progress: { ed, from, gap, cancel }

---------------------------------------------------------------------------
-- Small pieces
---------------------------------------------------------------------------
-- A square button with a left- or right-pointing arrowhead of 1px lines (Look's ArrowButton points up or down).
local function SideArrow(parent, dir, onClick)
    local G = Wg()
    local pal = G.pal
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(18, 18)
    G.Surface(b, pal.well, 1, pal.control, 1)
    local px = {}
    for i = 1, 3 do
        local t = G.Solid(b, "OVERLAY", pal.teal, 0.95)
        t:SetSize(1, dir == "left" and (i * 2 - 1) or ((4 - i) * 2 - 1))
        t:SetPoint("CENTER", b, "CENTER", i - 2, 0)
        px[i] = t
    end
    local function Paint()
        local on = b:IsEnabled()
        for _, t in ipairs(px) do t:SetAlpha(on and 1 or 0.3) end
        local edge = (on and b:IsMouseOver()) and pal.tealHi or pal.control
        b:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    end
    b:SetScript("OnEnable", Paint)
    b:SetScript("OnDisable", Paint)
    b:SetScript("OnClick", onClick)
    b:SetMotionScriptsWhileDisabled(true)
    b.Paint = Paint
    Paint()
    return b
end

-- The markers after the next one, as names: "Cross, Square, Moon and 4 more".
local function Following(kind, list, nextIndex)
    local n = #list
    local names = {}
    for j = 1, math.min(n - 1, 3) do names[j] = M.Name(kind, list[(nextIndex - 1 + j) % n + 1]) end
    local text = table.concat(names, ", ")
    if n - 1 > 3 then text = text .. (" and %d more"):format(n - 4) end
    return text
end

---------------------------------------------------------------------------
-- The order frame
---------------------------------------------------------------------------
local Refresh

local function Say(ed, text, tone)
    ed.said, ed.saidTone = text, tone
    if ed.built then Refresh(ed.kind) end
end

local function EndDrag(apply)
    local d = drag
    if not d then return end
    drag = nil
    local ed = d.ed
    ed:SetScript("OnUpdate", nil)
    ed.ghost:Hide()
    ed.drop:Hide()
    ed.tiles[d.from]:SetAlpha(1)
    ed.said = nil
    if apply and not d.cancel and d.gap then
        local to = M.DropTarget(d.from, d.gap)
        if to ~= d.from then M.Move(ed.kind, d.from, to) end   -- redraws through Markers.OnChange
    end
    Refresh(ed.kind)
end
P.EndDrag = EndDrag

-- While dragging: the ghost follows the pointer, and the gap it would land in is marked (redrawn only when it moves).
local function Track(ed)
    local d = drag
    if not (d and d.ed == ed) then ed:SetScript("OnUpdate", nil) return end
    local strip = ed.strip
    local scale = strip:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local left, right, top, bottom = strip:GetLeft(), strip:GetRight(), strip:GetTop(), strip:GetBottom()
    if not (left and right and top and bottom) then return end
    ed.ghost:ClearAllPoints()
    ed.ghost:SetPoint("CENTER", strip, "BOTTOMLEFT", cx - left, cy - bottom)
    local cancel = cy > top + CANCEL_MARGIN or cy < bottom - CANCEL_MARGIN
        or cx < left - CANCEL_MARGIN or cx > right + CANCEL_MARGIN
    local gap = math.max(0, math.min(M.COUNT, math.floor((cx - left - LEAD + SLOT / 2 + 3) / SLOT)))
    if cancel == d.cancel and gap == d.gap then return end
    d.cancel, d.gap = cancel, gap
    local name = M.Name(ed.kind, ed.tiles[d.from].id)
    if cancel then
        ed.drop:Hide()
        ed.ghost:SetAlpha(0.45)
        ed.said, ed.saidTone = ("Let go here to leave %s where it was."):format(name), nil
    else
        ed.ghost:SetAlpha(0.9)
        local moves = M.DropTarget(d.from, gap) ~= d.from
        ed.drop:ClearAllPoints()
        ed.drop:SetPoint("TOPLEFT", strip, "TOPLEFT", LEAD + gap * SLOT - 4, -4)
        ed.drop:SetShown(moves)
        ed.said, ed.saidTone = moves and ("Let go to move %s to the marked place."):format(name)
            or ("Let go here to leave %s where it was."):format(name), nil
    end
    ed.note:SetText(ed.said)
end

local function StartDrag(ed, i)
    if drag then EndDrag(false) end
    local tile = ed.tiles[i]
    if not tile.id then return end
    R.Interact.HideTip(tile)
    drag = { ed = ed, from = i }
    tile:SetAlpha(0.35)
    ed.ghost.icon:SetTexture(M.Texture(ed.kind, tile.id))
    ed.ghost.icon:SetDesaturated(not M.IsOn(ed.kind, tile.id))
    ed.ghost:Show()
    ed:SetScript("OnUpdate", Track)
    Track(ed)
end

local function NewTile(ed, i)
    local G, I = Wg(), R.Interact
    local pal = G.pal
    local kind = ed.kind
    local t = CreateFrame("Button", nil, ed.strip, "BackdropTemplate")
    t:SetSize(TILE_W, TILE_H)
    t:SetPoint("TOPLEFT", ed.strip, "TOPLEFT", LEAD + (i - 1) * SLOT, -6)
    t:RegisterForDrag("LeftButton")
    t.pos = i
    G.Surface(t, pal.surface, 0.95, pal.bronzeLo, 0.5)   -- recolored on each redraw (Refresh), never rebuilt
    t.nextBar = G.Solid(t, "ARTWORK", pal.teal, 1)        -- the marker the next press uses (the preview says so too)
    t.nextBar:SetHeight(2)
    t.nextBar:SetPoint("TOPLEFT", 1, -1)
    t.nextBar:SetPoint("TOPRIGHT", -1, -1)
    t.number = G.Text(t, "heading")
    t.number:SetPoint("TOPLEFT", 7, -6)
    t.grip = {}                                            -- three short lines: this can be dragged
    for g = 1, 3 do
        local line = G.Solid(t, "ARTWORK", pal.stone, 0.8)
        line:SetSize(10, 1)
        line:SetPoint("TOPRIGHT", -7, -7 - (g - 1) * 3)
        t.grip[g] = line
    end
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(30, 30)
    t.icon:SetPoint("TOP", 0, -22)
    t.name = G.Text(t, "small")
    t.name:SetPoint("TOP", 0, -57)
    t.name:SetWidth(TILE_W - 6)
    t.name:SetJustifyH("CENTER")
    t.name:SetWordWrap(false)
    t.state = G.Text(t, "meta")
    t.state:SetPoint("TOP", 0, -72)
    t.state:SetWidth(TILE_W - 6)
    t.state:SetJustifyH("CENTER")
    t.box = G.Checkbox(t, function(on) if t.id then M.SetOn(kind, t.id, on) end end)
    t.box:SetPoint("BOTTOM", 0, 7)
    t.left = SideArrow(t, "left", function() if t.pos > 1 then M.Move(kind, t.pos, t.pos - 1) end end)
    t.left:SetPoint("BOTTOMLEFT", 6, 7)
    t.right = SideArrow(t, "right", function() if t.pos < M.COUNT then M.Move(kind, t.pos, t.pos + 1) end end)
    t.right:SetPoint("BOTTOMRIGHT", -6, 7)

    I.Tip(t, nil, function()
        if not t.id then return end
        local name = M.Name(kind, t.id)
        if M.IsOn(kind, t.id) then
            return name .. ": number " .. (t.cycleNumber or "?") .. " in the cycle.\n\nDrag it to change when it comes, or use the arrows under it. Untick it to skip it."
        end
        return name .. ": skipped. Presses pass over it.\n\nTick its box to use it again; it comes back in this place. You can still drag it."
    end)
    I.Tip(t.box, "Use this marker", function()
        if t.id and M.IsOn(kind, t.id) then return "Ticked: presses use it, in its place. Untick to skip it; it keeps its place in the order." end
        return "Skipped: presses pass over it. Tick to use it again, in this place."
    end)
    I.Tip(t.left, "Move earlier", function()
        if t.pos <= 1 then return "Already first." end
        return ("Moves %s one place earlier. Whether it is ticked doesn't change."):format(M.Name(kind, t.id))
    end)
    I.Tip(t.right, "Move later", function()
        if t.pos >= M.COUNT then return "Already last." end
        return ("Moves %s one place later. Whether it is ticked doesn't change."):format(M.Name(kind, t.id))
    end)
    -- the arrows' own hover look, kept beside the tooltip
    for _, b in ipairs({ t.left, t.right }) do
        b:HookScript("OnEnter", b.Paint)
        b:HookScript("OnLeave", b.Paint)
    end
    t:SetScript("OnDragStart", function() StartDrag(ed, t.pos) end)
    t:SetScript("OnDragStop", function() EndDrag(true) end)
    return t
end

-- The line under the row: what the next press does, or why it does nothing; then a passing message, if any.
local function Preview(ed)
    local kind = ed.kind
    local seq = M.Sequence(kind)
    if not R:Enabled(M.SWITCH[kind]) then
        return "Off: the keys do nothing. Turn it on above to use this order.", "quiet"
    end
    if #seq == 0 then
        return "Every marker is skipped, so a press does nothing. Tick at least one.", "warn"
    end
    if MK.Pending(kind) then
        return "In combat: your changes are saved and reach your keys when combat ends. Until then the keys keep the order they had.", "reload"
    end
    local a = MK.Active(kind)
    local list = a and a.list or seq
    local step = a and MK.Step(kind) or 0
    local nextId, nextIndex = M.NextAfter(list, step)
    if not nextId then return nil end
    local text = "Next press: " .. M.Tag(kind, nextId)
    if #list == 1 then
        text = text .. ", every time (only one marker is ticked)."
    else
        text = text .. ", then " .. Following(kind, list, nextIndex) .. ". After the last, it starts again at the first."
    end
    return text, "ok", nextId
end

function Refresh(kind)
    local ed = editors[kind]
    if not (ed and ed.built and ed:IsVisible()) then return end   -- shown and in an open window
    local G = Wg()
    local pal = G.pal
    local order, off = M.Order(kind), M.OffSet(kind)
    local text, tone, nextId = Preview(ed)
    local n = 0
    for i, id in ipairs(order) do
        local t = ed.tiles[i]
        t.id, t.pos = id, i
        local on = not off[id]
        if on then n = n + 1 end
        t.cycleNumber = on and n or nil
        t.icon:SetTexture(M.Texture(kind, id))
        t.icon:SetDesaturated(not on)
        t.icon:SetAlpha(on and 1 or 0.45)
        t.name:SetText(M.Name(kind, id))
        G.Color(t.name, on and pal.text or pal.stone)
        t.number:SetText(on and tostring(n) or "-")
        G.Color(t.number, on and pal.bronzeText or pal.stone)
        t.state:SetText(on and "" or "Skipped")
        local fill, edge = on and pal.surface or pal.well, (nextId == id) and pal.teal or pal.bronzeLo
        t:SetBackdropColor(fill[1], fill[2], fill[3], on and 0.95 or 0.9)
        t:SetBackdropBorderColor(edge[1], edge[2], edge[3], (nextId == id) and 0.9 or 0.5)
        t.nextBar:SetShown(nextId == id)
        t.box:SetChecked(on)
        t.left:SetEnabled(i > 1)
        t.right:SetEnabled(i < M.COUNT)
        t.left.Paint()
        t.right.Paint()
        if not (drag and drag.ed == ed and drag.from == i) then t:SetAlpha(1) end
    end
    ed.preview:SetText(text or "")
    G.Color(ed.preview, tone == "warn" and pal.danger.text or (tone == "reload" and pal.bronzeText) or (tone == "quiet" and pal.stone) or pal.text)
    local note, noteTone = ed.said, ed.saidTone
    if not note and kind == "world" and MK.WorldMarkersAvailable() == false then
        note, noteTone = "The game says world markers aren't available here, so these keys can't place any.", "warn"
    end
    ed.note:SetText(note or "")
    G.Color(ed.note, noteTone == "warn" and pal.danger.text or (noteTone == "ok" and pal.sage) or pal.textDim)
    local canRestart = R:Enabled(M.SWITCH[kind]) and MK.Active(kind) ~= nil and #M.Sequence(kind) > 0 and not InCombat()
    ed.restart:SetEnabled(canRestart and true or false)
    ed.default:SetEnabled(not M.IsDefault(kind))
end
P.Refresh = Refresh

local function Build(ed)
    ed.built = true
    local G, I = Wg(), R.Interact
    local pal = G.pal
    local kind = ed.kind
    local noun = NOUN[kind]

    ed.help = G.Text(ed, "small")
    ed.help:SetPoint("TOPLEFT", 4, -2)
    ed.help:SetWidth(W - 8)
    ed.help:SetText("Each press of the key uses the next ticked marker, first to last, then starts again. Drag a marker, or use the arrows under it, to change when it comes. Untick a marker to skip it: it keeps its place.")

    ed.strip = CreateFrame("Frame", nil, ed, "BackdropTemplate")
    ed.strip:SetPoint("TOPLEFT", 0, STRIP_TOP)
    ed.strip:SetSize(W, STRIP_H)
    G.Well(ed.strip)
    ed.tiles = {}
    for i = 1, M.COUNT do ed.tiles[i] = NewTile(ed, i) end

    ed.drop = G.Solid(ed.strip, "OVERLAY", pal.tealHi, 1)   -- where a dragged marker would land
    ed.drop:SetSize(3, STRIP_H - 8)
    ed.drop:Hide()
    ed.ghost = CreateFrame("Frame", nil, ed.strip, "BackdropTemplate")
    ed.ghost:SetSize(40, 40)
    ed.ghost:SetFrameLevel(ed.strip:GetFrameLevel() + 20)
    G.Surface(ed.ghost, pal.surface, 0.95, pal.tealHi, 1)
    ed.ghost.icon = ed.ghost:CreateTexture(nil, "ARTWORK")
    ed.ghost.icon:SetPoint("TOPLEFT", 5, -5)
    ed.ghost.icon:SetPoint("BOTTOMRIGHT", -5, 5)
    ed.ghost:Hide()

    local below = STRIP_TOP - STRIP_H
    ed.first = G.Text(ed, "meta")
    ed.first:SetPoint("TOPLEFT", LEAD, below - 4)
    ed.first:SetText("First")
    ed.last = G.Text(ed, "meta")
    ed.last:SetPoint("TOPRIGHT", -(W - LEAD - (M.COUNT - 1) * SLOT - TILE_W), below - 4)
    ed.last:SetText("Last, then back to the first")
    local rule = G.Solid(ed, "BORDER", pal.bronzeLo, 0.8)
    rule:SetHeight(1)
    rule:SetPoint("LEFT", ed.first, "RIGHT", 8, 0)
    rule:SetPoint("RIGHT", ed.last, "LEFT", -8, 0)

    ed.preview = G.Text(ed, "body")
    ed.preview:SetPoint("TOPLEFT", 4, below - 26)
    ed.preview:SetWidth(W - 270)
    ed.preview:SetWordWrap(true)
    ed.note = G.Text(ed, "small")
    ed.note:SetPoint("TOPLEFT", ed.preview, "BOTTOMLEFT", 0, -6)
    ed.note:SetWidth(W - 270)

    ed.default = G.Button(ed, "Default order", 120, "danger", function()
        local names = {}
        for _, id in ipairs(M.DEFAULT_ORDER[kind]) do names[#names + 1] = M.Name(kind, id) end
        I.Confirm("TWICHUI_MARKERS_DEFAULT", ("Put the %ss back in the default order, every one ticked?\n\n%s.\n\nOnly this order changes. Your keys, the other kind of marker and any markers already in the game are left as they are. The cycle starts again at the first."):format(noun, table.concat(names, ", ")), function()
            M.ResetOrder(kind)
            Say(ed, "The default order is back.", "ok")
        end, { accept = "Put back" })
    end)
    ed.default:SetPoint("TOPRIGHT", -2, below - 24)
    I.Tip(ed.default, "Default order", ("Puts the eight %ss back in the game's order (Skull, Cross, Square, Moon, Triangle, Diamond, Circle, Star) with every one ticked. Asks first. Keys and markers in the game are unchanged."):format(noun))
    ed.restart = G.Button(ed, "Restart cycle", 120, "secondary", function()
        local ok, why = MK.Restart(kind)
        if ok then
            local first = M.Sequence(kind)[1]
            Say(ed, ("Restarted: the next press is %s. Markers already in the game stay where they are."):format(first and M.Name(kind, first) or "the first marker"), "ok")
        elseif why == "combat" then
            Say(ed, "In combat, use your restart key instead.", "warn")
        end
    end)
    ed.restart:SetPoint("RIGHT", ed.default, "LEFT", -8, 0)
    I.Tip(ed.restart, "Restart cycle", function()
        local why
        if InCombat() then why = "In combat, use your restart key instead."
        elseif not R:Enabled(M.SWITCH[kind]) then why = "Turn it on above first."
        elseif #M.Sequence(kind) == 0 then why = "Every marker is skipped." end
        return "Makes the next press use the first ticked marker again, as the restart key does. It removes nothing: markers already in the game stay where they are.", why
    end)
end

-- The tab's frame (the settings window shows it under the switch). Built the first time it is shown.
function P.Frame(kind)
    if editors[kind] then return editors[kind] end
    local ed = CreateFrame("Frame")
    ed.kind = kind
    ed:Hide()
    ed:SetScript("OnShow", function(self)
        if not self.built then Build(self) end
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        Refresh(kind)
    end)
    ed:SetScript("OnHide", function(self)
        self:UnregisterEvent("PLAYER_REGEN_DISABLED")
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if drag and drag.ed == self then EndDrag(false) end   -- the window closed or the page changed mid-drag
        self.said = nil
        if P.capture and P.capture:IsShown() then P.capture:Hide() end
    end)
    ed:SetScript("OnEvent", function() Refresh(kind) end)
    editors[kind] = ed
    return ed
end

-- A change made anywhere (here, a key press, a profile change, an import) redraws a shown frame. A drag under
-- way when the order changes elsewhere is dropped, so it can never move the wrong marker. Registered once.
-- A passing message ("Restarted: ...") is about the moment it was said, so any later change clears it.
local function OnOrderChange(kind)
    if drag and (kind == nil or drag.ed.kind == kind) then EndDrag(false) end
    for k, ed in pairs(editors) do
        if kind == nil or kind == k then
            ed.said = nil
            Refresh(k)
        end
    end
end
local function OnKeysState(what, kind)
    for k, ed in pairs(editors) do
        if kind == nil or kind == k then
            if what ~= "keys" and not (drag and drag.ed == ed) then ed.said = nil end
            Refresh(k)
        end
    end
    if what == "keys" then K.RefreshOverview() end
end
if M and MK then
    M.OnChange(OnOrderChange)
    MK.OnState(OnKeysState)
end

---------------------------------------------------------------------------
-- Choosing a key: a small window that takes the next key (or mouse button 3 to 5, or the wheel), with Shift,
-- Ctrl or Alt held as part of it. Esc cancels, and is never passed on, so it can't close the settings as well.
-- A key that already does something else is only taken after you say so.
---------------------------------------------------------------------------
local function Chosen(id, key)
    local a = MK.Action(id)
    if not a or not key then return end
    local label = MK.KeyLabel(key)
    local bound, over = MK.KeyUse(key)
    local function Apply()
        local ok, why = MK.SetKey(id, key)
        if not ok then
            R.Print(why == "combat" and "keys can't be changed in combat. Nothing was changed." or "the game didn't accept %s for that. Nothing was changed.", label)
            return
        end
        K.RefreshOverview()
    end
    if bound == a.binding then return end
    local warnOver = (over and over ~= a.binding) and ("\n\nRight now another addon has this key for itself (%s), and its keys win until it lets go."):format(MK.ActionName(over)) or ""
    if bound then
        local what = MK.ActionName(bound)
        R.Interact.Confirm("TWICHUI_MARKERS_KEY", ("%s is the key for %s.\n\nUse it for \"%s\" instead? %s will no longer have %s; any other key it has stays.%s"):format(label, what, a.label, what, label, warnOver),
            Apply, { accept = "Use it", combat = true })
    elseif warnOver ~= "" then
        R.Interact.Confirm("TWICHUI_MARKERS_KEY", ("Use %s for \"%s\"?%s"):format(label, a.label, warnOver), Apply, { accept = "Use it", combat = true })
    else
        Apply()
    end
end

local function BuildCapture()
    local G = Wg()
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(380, 164)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    G.Shell(f, 0)
    f:Hide()
    f.title = G.Text(f, "heading")
    f.title:SetPoint("TOPLEFT", 18, -18)
    f.title:SetWidth(344)
    f.text = G.Text(f, "small")
    f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
    f.text:SetWidth(344)
    f.text:SetText("Press the key to use, with Shift, Ctrl or Alt if you like. Mouse buttons 3 to 5 and the wheel work too. Esc cancels.")
    f.now = G.Text(f, "body")
    f.now:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -10)
    f.now:SetWidth(344)
    f.remove = G.Button(f, "Remove key", 120, "danger", function()
        local id = f.id
        f:Hide()
        if id then
            local ok, why = MK.RemoveKeys(id)
            if not ok and why == "combat" then R.Print("keys can't be changed in combat. Nothing was changed.") end
            K.RefreshOverview()
        end
    end)
    f.remove:SetPoint("BOTTOMLEFT", 18, 16)
    R.Interact.Tip(f.remove, "Remove key", "Unbinds this action's keys, here and in the game's Key Bindings. The keys are then free for anything else.")
    f.cancel = G.Button(f, CANCEL or "Cancel", 100, "secondary", function() f:Hide() end)
    f.cancel:SetPoint("BOTTOMRIGHT", -18, 16)

    local function Take(key)
        local id = f.id
        f:Hide()
        if id and key then Chosen(id, CreateKeyChordStringUsingMetaKeyState(key)) end
    end
    f:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then f:Hide() return end
        if IsKeyPressIgnoredForBinding and IsKeyPressIgnoredForBinding(key) then return end   -- Shift, Ctrl, Alt alone
        Take(key)
    end)
    f:SetScript("OnMouseDown", function(_, button)
        local key = GetConvertedKeyOrButton and GetConvertedKeyOrButton(button) or button
        if key == "BUTTON1" or key == "BUTTON2" then return end   -- clicks are for the buttons here
        Take(key)
    end)
    f:SetScript("OnMouseWheel", function(_, delta) Take(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
    f:SetScript("OnEvent", function() f:Hide() end)   -- combat started: keys can't be changed now
    f:SetScript("OnHide", function(self)
        self:UnregisterEvent("PLAYER_REGEN_DISABLED")
        self:EnableKeyboard(false)
        self.id = nil
    end)
    P.capture = f
    return f
end

function P.Capture(id)
    local a = MK.Action(id)
    if not a then return end
    if InCombat() then R.Print("keys can't be changed in combat.") return end
    if not (CreateKeyChordStringUsingMetaKeyState and SetBinding) then R.Print("this client can't change key bindings from here; use the game's Key Bindings > TwichUI.") return end
    local f = P.capture or BuildCapture()
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focus and focus.ClearFocus then focus:ClearFocus() end   -- a box being typed in would take the key first
    f.id = id
    f.title:SetText(a.label)
    local now = MK.KeyText(id)
    f.now:SetText(now and ("Now: " .. now) or "No key yet.")
    f.remove:SetEnabled(now ~= nil)
    local UI = R.SettingsUI
    local win = UI and UI.Frame and UI.Frame()
    f:ClearAllPoints()
    f:SetPoint("CENTER", win or UIParent, "CENTER", 0, 0)
    f:SetScale(win and (win:GetEffectiveScale() / UIParent:GetEffectiveScale()) or 1)
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(false)   -- (out of combat: checked above)
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:Show()
    f:Raise()
end

---------------------------------------------------------------------------
-- The pages
---------------------------------------------------------------------------
-- A key's row: its label, its key on the button (click to choose one), and a line when the key won't reach it.
local function KeyRow(id, tooltip, first)
    local a = MK.Action(id)
    local row = K.Button(a.label, function() return MK.KeyText(id) or "Set a key" end, function() P.Capture(id) end,
        tooltip .. "\n\nClick to choose a key (asks before taking one that already does something). The same action is in the game's Key Bindings, under TwichUI. Keys are the game's: the same in every profile, kept while this is off, and never part of a shared setup.")
    if not row then return end
    row:AddModifyPredicate(function() return not InCombat() end)
    row.why = "Keys can't be changed in combat."
    K.Note(row, function()
        local taken = MK.TakenOver(id)
        if taken[1] then
            return ("Another addon has %s for itself right now (%s), so pressing it does that instead."):format(MK.KeyLabel(taken[1].key), MK.ActionName(taken[1].action)), "warn"
        end
        if first and MK.OtherCycler() then
            return "World Marker Cycler is loaded too. Each keeps its own cycle and its own keys, so give them different keys."
        end
    end)
    return row
end

local function Restarts(kind, label, tooltip, toggle, On)
    local key = kind .. "ClearRestarts"
    return K.Under(K.ProxyToggle("markers" .. kind:sub(1, 1):upper() .. kind:sub(2) .. "ClearRestarts", label, tooltip,
        M.DEFAULTS[key], function() return M.Get(key) end, function(value) M.Set(key, value and true or false) end), toggle, On)
end

local KEYWORDS = "marker markers raid target icon mark skull cross square moon triangle diamond circle star cycle cycler rotate next order key keybind binding restart reset clear remove"

-- The page the three marker tabs (Target markers and World markers here, Marker bar in MarkerBar.lua) sit under.
local function Marks(key) return R:Enabled(key) and true or false end

K.Page({
    key = "markers", icon = "markers", name = "Markers", order = 31, group = "everyday",
    description = "Keys and a bar for marking your target and the ground. Each is off until you turn it on.",
    keywords = KEYWORDS .. " bar",
    when = function() return R.Markers ~= nil and R.MarkerKeys ~= nil end,
    overview = {
        label = "Markers", tip = "Keys to cycle target and world markers, and a bar of target markers to click. Each is off until you turn it on.",
        status = function()
            local on = (Marks("markersTarget") and 1 or 0) + (Marks("markersWorld") and 1 or 0)
            local total = 2
            if R.MarkerBar then
                total = 3
                on = on + (Marks("markersBar") and 1 or 0)
            end
            return K.OnOff(on > 0, ("%d of %d on"):format(on, total), "Off")
        end,
    },
    build = function()
        K.Header("Markers", "Three separate things, each off until you turn it on and each on its own tab. None of them marks anything by itself: a marker is placed only when you press a key you chose, or click the bar.")
        K.Status("Target markers", function() return K.OnOff(Marks("markersTarget")) end, nil,
            "A key that marks your target with the next marker, in an order you choose.")
        K.Button("Target markers", "Open", function() R:OpenSettings("markersTarget") end,
            "The switch, the order of the markers and the keys for cycling target markers.")
        K.Status("World markers", function() return K.OnOff(Marks("markersWorld")) end, nil,
            "A key that places the next world marker at your mouse pointer, in an order you choose.")
        K.Button("World markers", "Open", function() R:OpenSettings("markersWorld") end,
            "The switch, the order of the markers and the keys for placing world markers.")
        if R.MarkerBar then
            K.Status("Marker bar", function() return K.OnOff(Marks("markersBar")) end, nil,
                "A bar of target markers that appears while you hold a key; click one to mark your target.")
            K.Button("Marker bar", "Open", function() R:OpenSettings("markersBar") end,
                "The switch, the key to hold, which markers are on the bar, and where it appears.")
        end
    end,
})

K.Page({
    key = "markersTarget", name = "Target markers", parent = "markers", order = 32,
    description = "A key that marks your target with the next marker, in an order you choose.",
    keywords = KEYWORDS .. " target unit mouseover",
    when = function() return R.Markers ~= nil and R.MarkerKeys ~= nil end,
    host = function() return P.Frame("target") end, hostAfter = "Target markers", hostHeight = HOST_H,
    build = function()
        local Header, Toggle, Under, Choice = K.Header, K.Toggle, K.Under, K.Choice
        Header("Target markers", "Marks over a unit's head, such as Skull or Cross. Off until you turn it on, and nothing is marked until you press a key you chose below.")
        local toggle = Toggle("markersTarget", "Cycle target markers with a key",
            "Each press of the key marks your target with the next ticked marker in the order below; after the last it starts again at the first. A target that already wears that marker keeps it (a press never takes a marker off), and the cycle still moves on. Without a target a press does nothing and the cycle stays put.\n\nThe game decides whether you may mark (in a group that can need the leader or an assistant) and what becomes of that marker if another unit wears it; TwichUI can't see whether a mark was made. Markers placed by other players or addons are left alone and don't change the cycle.")
        local function On() return R:Enabled("markersTarget") end
        Under(Choice("markersTargetUnit", "The key marks", "Which unit a press marks. TwichUI never changes your target.",
            K.STRING, M.DEFAULTS.targetUnit, function() return M.Get("targetUnit") end, function(value) M.Set("targetUnit", value) end, {
                { "target", "Your target", "Only the unit you have targeted." },
                { "mouseover", "An enemy under your mouse, else your target", "A living enemy under your mouse pointer when there is one; otherwise your target." },
            }), toggle, On)
        Under(K.ProxyToggle("markersTargetRestartAfterCombat", "Restart the cycle when combat ends",
            "On: each time combat ends, the next press starts at the first ticked marker again, so every pull begins with the same marker. It only changes which marker comes next: no marker is removed, and nothing is said. Off: the cycle keeps its place until you restart it, remove a marker or reload.\n\nIf you change the order during combat, that is given to your keys first, then the cycle restarts.",
            M.DEFAULTS.targetRestartAfterCombat, function() return M.Get("targetRestartAfterCombat") end,
            function(value) M.Set("targetRestartAfterCombat", value and true or false) end), toggle, On)
        Restarts("target", "Removing your target's marker restarts the cycle",
            "On: pressing \"Remove your target's marker\" also makes the next press start at the first ticked marker. Off: it only removes the marker. Either way, restarting never removes anything.", toggle, On)

        Header("Target marker keys", "Three separate keys, none set until you choose them. The first marks; restarting only changes which marker comes next and removes nothing; removing takes the marker off your target and nothing else.")
        KeyRow("targetNext", "Marks your target with the next ticked marker, then moves the cycle on by one.", true)
        KeyRow("targetRestart", "Makes the next press use the first ticked marker again. No marker is removed.")
        KeyRow("targetClear", "Takes the marker off your target (or the enemy under your mouse, if you chose that). Other units keep theirs.")
    end,
})

K.Page({
    key = "markersWorld", name = "World markers", parent = "markers", order = 33,
    description = "A key that places the next world marker at your mouse pointer, in an order you choose.",
    keywords = KEYWORDS .. " world ground flare place cursor pointer",
    when = function() return R.Markers ~= nil and R.MarkerKeys ~= nil end,
    host = function() return P.Frame("world") end, hostAfter = "World markers", hostHeight = HOST_H,
    build = function()
        local Header, Toggle = K.Header, K.Toggle
        Header("World markers", "Markers placed on the ground. Off until you turn it on, and nothing is placed until you press a key you chose below.")
        local toggle = Toggle("markersWorld", "Cycle world markers with a key",
            "Each press of the key places the next ticked world marker on the ground under your mouse pointer, at once: there is no circle to aim, confirm or cancel. After the last it starts again at the first.\n\nEvery press moves the cycle on, even one the game refuses (not allowed here, nothing under the pointer, not in a group that allows it): TwichUI can't see whether a marker was placed. Press the restart key to start again at the first. Don't press it while aiming a spell: TwichUI can't tell, and the game decides what happens. World markers placed by others are left alone and don't change the cycle.")
        local function On() return R:Enabled("markersWorld") end
        Restarts("world", "Removing all world markers restarts the cycle",
            "On: pressing \"Remove all world markers\" also makes the next press start at the first ticked marker. Off: it only removes them. Either way, restarting never removes anything.", toggle, On)

        Header("World marker keys", "Three separate keys, none set until you choose them. The first places; restarting only changes which marker comes next and removes nothing; removing takes every world marker off the ground.")
        KeyRow("worldNext", "Places the next ticked world marker under your mouse pointer, then moves the cycle on by one.", true)
        KeyRow("worldRestart", "Makes the next press use the first ticked marker again. No marker is removed.")
        KeyRow("worldClear", "Removes every world marker on the ground, yours and other players'. Target markers are not affected.")
    end,
})
