-- TwichUI: Party pins, the pin window
-- Every pin you have in one list: your local pins, and the party's while you are in a party. A count in
-- the header, a search box, filters (All, Local, Party, Removed), and for each pin its icon, name, map and
-- coordinates, and who made it. A padlock marks a kept pin (protected from deletion and clearing), and the
-- Kept filter lists them. Right-click a row (or its menu button) for what can be done with it:
--   Show on map, Set waypoint (the game's own, replacing yours, only when you pick it), Edit pin (your
--   own: name, color and Keep), Save to my pins (a party pin, as a local pin of your own, reviewed first),
--   Remove from my map / Restore to my map, Remove pin (a local one; not a kept one), and Remove for
--   entire party (your own party pins, after you confirm; not a kept one).
-- What can be done is asked when the menu opens and again when you pick it, so a pin that changed or
-- went meanwhile is never acted on. Opened with /tui pins, the data bar or the Party pins options; it
-- never opens by itself. TwichUI's own look (pins/Look.lua), which works without EllesmereUI.

local R = TwichUI
local PN = R.Pins
local PL = R.PinsLook
local S = R.ChronicleStyle
local Tip = function(...) return R.Interact.Tip(...) end
local PW = {}
R.PinsWindow = PW

local NAME = "TwichUIPins"
local WIDTH, HEIGHT = 340, 452
local PAD = 12
local LIST_TOP = 104
local pal = PL.palette
local panel, body, list, rows, menu
local filter, search = "all", ""
local dirty, scheduled = false, false
local entries = {}

local function Notice(text) R.PinsMap.Notice(text) end
local function Paint(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

---------------------------------------------------------------------------
-- The action menu (also opened from a pin on the map)
---------------------------------------------------------------------------
local MENU = "TwichUIPinActions"
local items = {}

local function CloseMenu()
    if menu and menu:IsShown() then menu:Hide() end
end
PW.CloseMenu = CloseMenu

local function OnGlobalMouseDown()
    if menu and menu:IsShown() and not menu:IsMouseOver() then CloseMenu() end
end

local function MenuItem(i)
    local b = items[i]
    if b then return b end
    b = CreateFrame("Button", nil, menu)
    b:SetHeight(20)
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(pal.gold[1], pal.gold[2], pal.gold[3], 0.12)
    b.hl:Hide()
    b.text = PL.Text(b, "GameFontHighlightSmall", "control")
    b.text:SetPoint("LEFT", 8, 0)
    b.text:SetPoint("RIGHT", -8, 0)
    b.text:SetWordWrap(false)
    b:SetScript("OnClick", function(self)
        local run = self.run
        CloseMenu()
        if run then run() end
    end)
    b:HookScript("OnEnter", function(self) if self:IsEnabled() then self.hl:Show() end end)
    b:HookScript("OnLeave", function(self) self.hl:Hide() end)
    items[i] = b
    return b
end

local function BuildMenu()
    if menu then return end
    menu = CreateFrame("Frame", MENU, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetToplevel(true)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:Hide()
    S.Popover(menu, pal)
    menu.title = PL.Text(menu, "GameFontNormalSmall", "meta")
    menu.title:SetPoint("TOPLEFT", 8, -7)
    menu.title:SetPoint("RIGHT", -8, 0)
    menu.title:SetWordWrap(false)
    menu:SetScript("OnShow", function() R:On("GLOBAL_MOUSE_DOWN", OnGlobalMouseDown) end)
    menu:SetScript("OnHide", function() R:Off("GLOBAL_MOUSE_DOWN", OnGlobalMouseDown) end)
    if UISpecialFrames then tinsert(UISpecialFrames, MENU) end
end

-- choices: { { label, run, enabled, why, tip, danger }, ... }; anchor: the row or pin it is for.
local function OpenMenu(anchor, title, choices)
    BuildMenu()
    S.PaintPopover(menu, pal)
    menu.title:SetText(title or "")
    Paint(menu.title, pal.stone)
    local y, width = -24, 170
    for i, item in ipairs(choices) do
        local b = MenuItem(i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 2, y)
        b:SetPoint("RIGHT", -2, 0)
        b.text:SetText(item.label)
        b:SetEnabled(item.enabled ~= false)
        local tone = item.enabled == false and pal.stone or (item.danger and { 0.92, 0.55, 0.44 } or pal.text)
        Paint(b.text, tone)
        b.hl:SetColorTexture(pal.gold[1], pal.gold[2], pal.gold[3], 0.12)
        b.run = item.run
        Tip(b, nil, function() return item.tip, item.enabled == false and item.why or nil end, "ANCHOR_RIGHT")
        b:Show()
        width = math.max(width, b.text:GetStringWidth() + 24)
        y = y - 20
    end
    for i = #choices + 1, #items do items[i]:Hide() end
    menu:SetSize(math.min(width, 260), -y + 6)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMRIGHT", -12, 4)
    menu:Show()
    menu:Raise()
end

local function Can(action, e)
    local ok, why = PN.Can(action, e)
    return ok, why
end

-- Runs fn only if the action is still allowed for the pin as it is now.
local function Guard(action, e, fn)
    return function()
        local ok, why = Can(action, e)
        if not ok then Notice(why) return end
        fn()
    end
end

local function ConfirmRemoveForParty(e)
    local pin = PN.Fresh(e)
    if not pin then return end
    R.Interact.Confirm("TWICHUI_PINS_REMOVE_PARTY",
        ("Remove \"%s\" for the entire party?\n\nParty members with TwichUI have it taken off their maps when your message reaches them. Local copies they kept stay theirs."):format(pin.name),
        function()
            local ok, why = R.PinSync.RemoveForParty(e.pin.key)
            if ok then Notice("Removal sent to your party.") else Notice(why) end
        end,
        { valid = function() return Can("removeParty", e) end, accept = "Remove for party" })
end
PW.ConfirmRemoveForParty = ConfirmRemoveForParty   -- the data bar menu asks the same question

-- The actions for one pin, in a fixed order. Owner-only actions are left out for someone else's pin.
function PW.Actions(e)
    local out = {}
    local function Add(action, label, run, tip, danger)
        local ok, why = Can(action, e)
        out[#out + 1] = { label = label, run = Guard(action, e, run), enabled = ok, why = why, tip = tip, danger = danger }
    end
    local pin = PN.Fresh(e)
    if not pin then return out end
    local party = e.kind == "party"
    local dismissed = party and PN.IsDismissed(pin.key)
    if not dismissed then
        Add("show", "Show on map", function() R.PinsMap.ShowOnMap(e) end,
            "Moves your open map to it and picks it out. With the map closed, it is shown the next time you open it.")
    end
    Add("waypoint", "Set waypoint", function() R.PinsMap.SetWaypoint(e) end,
        "Puts the game's own waypoint here. It replaces the waypoint you had, as setting one on the map does.")
    if not party or pin.mine then
        Add("edit", "Edit pin...", function() R.PinsEditor.OpenEdit(e) end,
            party and "Changes its name or color for everyone in the party who has it, and whether you keep it." or "Changes this pin's name or color, and whether it is kept: protected from deletion and cleanup.")
    end
    if party then
        Add("copy", "Save to my pins...", function()
            local fields, why = PN.CopyFields(pin.key)
            if fields then R.PinsEditor.OpenCopy(fields) else Notice(PN.Reason(why)) end
        end, "Opens a new local pin of your own here, kept by default, for you to review and save. It isn't linked to this one: it stays when this party pin is removed or you leave the party, and nothing is sent.")
        if dismissed then
            Add("restore", "Restore to my map", function() PN.Restore(pin.key) end, "Shows it on your map again.")
        else
            Add("dismiss", "Remove from my map", function() PN.Dismiss(pin.key) end,
                "Takes it off your map only. Nothing is sent: everyone else keeps it. It stays off when the party's pins are brought up to date; find it under Removed to restore it.")
        end
        if pin.mine then
            Add("removeParty", "Remove for entire party...", function() ConfirmRemoveForParty(e) end,
                "Asks first. Then removes it from your map and tells party members with TwichUI to remove it from theirs.", true)
        end
    else
        Add("delete", "Remove pin", function()
            local ok = PN.RemoveLocal(pin.id)
            if not ok then Notice(PN.Reason("gone")) end
        end, "Deletes this local pin.", true)
    end
    return out
end

function PW.OpenActions(e, anchor)
    local pin = PN.Fresh(e)
    if not pin then return end
    OpenMenu(anchor, pin.name, PW.Actions(e))
end

-- Asks first, with the counts of what it will delete; only those pins are deleted, each judged again when
-- the question is accepted, so one that became kept in between stays.
local function ConfirmDeleteLocal()
    local ids, n, kept = PN.LocalClearScope()
    if n == 0 then
        Notice(kept > 0 and "Every local pin you have is kept, so there is nothing to delete." or "You have no local pins.")
        return
    end
    local text = ("Delete %d unprotected local %s? This can't be undone. Party pins are not touched."):format(n, n == 1 and "pin" or "pins")
    if kept > 0 then
        text = text .. ("\n\nYour %d kept %s will remain."):format(kept, kept == 1 and "pin" or "pins")
    end
    R.Interact.Confirm("TWICHUI_PINS_CLEAR_LOCAL", text, function() PN.ClearLocal(ids) end, { accept = "Delete", valid = function()
        local _, now = PN.LocalClearScope()
        if now == 0 then return false, "Nothing is left to delete now. Nothing was changed." end
        return true
    end })
end

local function OpenMore(anchor)
    local scope = PN.ClearScope()
    OpenMenu(anchor, "Pins", {
        { label = "Remove all party pins from my map", enabled = scope.partyHide > 0,
          why = scope.kept > 0 and "The party pins on your map are all kept." or "No party pins are on your map.",
          tip = "Takes every party pin off your map, yours included, except kept ones. Nothing is sent; each can be restored under Removed.",
          run = function() PN.DismissAll() end },
        { label = "Delete unprotected local pins...", enabled = scope.localDelete > 0,
          why = scope.kept > 0 and "Every local pin you have is kept." or "You have no local pins.", danger = true,
          tip = "Asks first. Kept pins, party pins and anything shared are not touched; nothing is sent.",
          run = ConfirmDeleteLocal },
        { label = "Party pins options", run = function()
            if not (InCombatLockdown and InCombatLockdown()) then R:OpenSettings("pins") end
        end },
    })
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function Match(e)
    if filter == "local" and e.kind ~= "local" then return false end
    if filter == "party" and (e.kind ~= "party" or e.dismissed) then return false end
    if filter == "kept" and (not e.kept or e.dismissed) then return false end
    if filter == "dismissed" and not e.dismissed then return false end
    if filter == "all" and e.dismissed then return false end
    if search == "" then return true end
    local needle = search:lower()
    return e.pin.name:lower():find(needle, 1, true) ~= nil or PN.MapName(e.pin.map):lower():find(needle, 1, true) ~= nil
end

local function Owner(e)
    local pin = e.pin
    if e.kind == "local" then return pin.copiedFrom and "copy" or "local" end
    if pin.mine then return "you" end
    local SH = R.Share
    return SH and SH.Short(pin.owner) or pin.owner
end

local function RowClick(row, button)
    local e = row.entry
    if not e then return end
    if button == "RightButton" then
        PW.OpenActions(e, row)
    else
        CloseMenu()
        PN.Select(PN.selected == e.token and nil or e.token)
    end
end

local function NewRow(i)
    local row = CreateFrame("Button", nil, list.content)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    S.RowArt(row, pal)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    row.sel:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexture(PL.PIN_TEXTURE)
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 6, 0)
    row.badgeEdge = row:CreateTexture(nil, "OVERLAY", nil, 1)
    row.badgeEdge:SetColorTexture(0.06, 0.04, 0.03, 1)
    row.badgeEdge:SetSize(7, 7)
    row.badgeEdge:SetPoint("CENTER", row.icon, "TOPLEFT", PL.BadgePoint(18))
    row.badge = row:CreateTexture(nil, "OVERLAY", nil, 2)
    row.badge:SetColorTexture(0.93, 0.87, 0.71, 1)
    row.badge:SetSize(5, 5)
    row.badge:SetPoint("CENTER", row.badgeEdge, "CENTER")
    row.more = S.Link(row, "...", function(self) PW.OpenActions(self:GetParent().entry, self) end, pal.stone, pal.text)
    row.more:SetSize(22, 16)
    row.more:SetPoint("RIGHT", -4, 0)
    row.more.text:SetJustifyH("CENTER")
    Tip(row.more, nil, "Actions for this pin (or right-click the row).")
    row.lock = row:CreateTexture(nil, "ARTWORK")
    row.lock:SetTexture(PL.LOCK_TEXTURE)
    row.lock:SetSize(12, 12)
    row.lock:SetPoint("RIGHT", row.more, "LEFT", -4, 0)
    local t = PL.LOCK_TINT
    row.lock:SetVertexColor(t[1], t[2], t[3], t[4])
    row.lock:Hide()
    row.owner = PL.Text(row, "GameFontNormalSmall", "meta")
    row.owner:SetPoint("RIGHT", row.more, "LEFT", -4, 0)
    row.owner:SetJustifyH("RIGHT")
    row.owner:SetWidth(70)
    row.owner:SetWordWrap(false)
    row.name = PL.Text(row, "GameFontHighlight", "name")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.owner, "LEFT", -6, 0)
    row.name:SetWordWrap(false)
    row.sub = PL.Text(row, "GameFontNormalSmall", "meta")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
    row.sub:SetPoint("RIGHT", row.owner, "LEFT", -6, 0)
    row.sub:SetWordWrap(false)
    row:SetScript("OnClick", RowClick)
    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        if self.name:IsTruncated() and self.entry then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.entry.pin.name, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        R.Interact.HideTip(self)
    end)
    rows[i] = row
    return row
end

local function DressRow(row, e, y, h)
    local pin = e.pin
    row.entry = e
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -y)
    row:SetPoint("RIGHT", list.content, "RIGHT", 0, 0)
    row:SetHeight(h)
    local c = PN.ColorRGB(pin.color)
    row.icon:SetVertexColor(c[1], c[2], c[3], 1)
    local party = e.kind == "party"
    row.badge:SetShown(party)
    row.badgeEdge:SetShown(party)
    row.name:SetText(pin.name)
    row.sub:SetText(PN.Describe(pin))
    row.sub:SetShown(h >= 30)
    row.name:ClearAllPoints()
    row.name:SetPoint(h >= 30 and "TOPLEFT" or "LEFT", row.icon, h >= 30 and "TOPRIGHT" or "RIGHT", 6, h >= 30 and 2 or 0)
    row.name:SetPoint("RIGHT", row.owner, "LEFT", -6, 0)
    row.owner:SetText(e.dismissed and "removed" or Owner(e))
    -- a kept pin's padlock sits where the owner's name ends, which moves left to make room
    local kept = PN.IsKept(pin)
    row.lock:SetShown(kept)
    row.owner:ClearAllPoints()
    if kept then
        row.owner:SetPoint("RIGHT", row.lock, "LEFT", -4, 0)
    else
        row.owner:SetPoint("RIGHT", row.more, "LEFT", -4, 0)
    end
    Paint(row.name, pal.text)
    Paint(row.sub, pal.stone)
    Paint(row.owner, party and pal.gold or pal.stone)
    row:SetAlpha(e.dismissed and 0.6 or 1)
    S.PaintRow(row, pal)
    row.sel:SetColorTexture(pal.gold[1], pal.gold[2], pal.gold[3], 0.14)
    row.sel:SetShown(PN.selected == e.token)
    row:Show()
end

local function Count()
    local n, party = PN.LocalCount(), 0
    for _, p in ipairs(PN.SharedPins()) do if not PN.IsDismissed(p.key) then party = party + 1 end end
    return n + party, party
end
PW.Count = Count

local EMPTY = {
    all = "No pins yet.\n\n%s",
    ["local"] = "No local pins.\n\n%s",
    party = "No party pins on your map.",
    kept = "No kept pins. Keep a pin from its Edit pin window to protect it from deletion and cleanup.",
    dismissed = "Nothing removed from your map. Party pins you remove from your map wait here until you leave the party.",
}

function PW.Refresh()
    dirty = false
    if not (panel and panel:IsShown()) then return end
    local total, party = Count()
    panel.count:SetText(party > 0 and ("%d pins, %d party"):format(total, party) or (total == 1 and "1 pin" or ("%d pins"):format(total)))
    local sync = R.PinSync and R.PinSync.Blocked()
    local partyNote = (sync == "paused" and "Paused in a raid.") or (sync == "blocked" and "Addon messages are held here.")
        or (sync == "no-party" and "Not in a party.") or nil
    panel.state:SetText(partyNote or "")
    wipe(entries)
    for _, e in ipairs(PN.Entries()) do
        if Match(e) then entries[#entries + 1] = e end
    end
    local h = PL.RowHeight()
    for i, e in ipairs(entries) do DressRow(rows[i] or NewRow(i), e, (i - 1) * h, h) end
    for i = #entries + 1, #rows do rows[i]:Hide(); rows[i].entry = nil end
    list.content:SetHeight(math.max(1, #entries * h))
    if #entries == 0 then
        local text = EMPTY[filter] or EMPTY.all
        if search ~= "" then text = "No pins match." end
        list.empty:SetText(text:find("%%s") and text:format(PL.HowToPlace()) or text)
        list.empty:Show()
    else
        list.empty:Hide()
    end
    panel.hint:SetText(PL.HowToPlace())
    for key, b in pairs(panel.filters) do b:SetOn(filter == key) end
    panel.place:SetEnabled(R:Enabled("partyPins"))
end

-- Coalesced: several changes in one frame redraw once.
local function Request()
    dirty = true
    if scheduled or not (panel and panel:IsShown()) then return end
    scheduled = true
    C_Timer.After(0, function()
        scheduled = false
        if dirty then PW.Refresh() end
    end)
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Position()
    local p = PL.Pref("position")
    if type(p) == "table" then return p.x, p.y end
    return 260, 40
end

local function SavePosition()
    local cx, cy = panel:GetCenter()
    local px, py = UIParent:GetCenter()
    if cx and px then PL.SetPref("position", { x = math.floor(cx - px + 0.5), y = math.floor(cy - py + 0.5) }) end
end

local function Restyle()
    if not panel then return end
    local edge = math.ceil(PL.Surface(PL.Look, panel))
    panel:SetSize(WIDTH + edge * 2, HEIGHT + edge * 2)
    S.PaintHeader(body, pal)
    S.PaintWell(list, pal)
    if list.paintBar then list.paintBar() end
    Paint(panel.title, pal.text)
    Paint(panel.count, pal.stone)
    Paint(panel.state, pal.stone)
    Paint(panel.hint, pal.stone)
    Paint(list.empty, pal.stone)
    for _, w in ipairs(panel.widgets) do if w.Repaint then w:Repaint() end end
    Request()
end
PW.Restyle = Restyle

local function Build()
    if panel then return end
    panel = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetFrameStrata("HIGH")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
    panel:Hide()
    if UISpecialFrames then tinsert(UISpecialFrames, NAME) end
    panel.widgets = {}
    local function W(w) panel.widgets[#panel.widgets + 1] = w return w end

    body = CreateFrame("Frame", nil, panel)
    body:SetSize(WIDTH, HEIGHT)
    body:SetPoint("CENTER")
    S.Header(body, 30, pal)
    panel.title = PL.Text(body, "GameFontNormal", "title")
    panel.title:SetPoint("TOPLEFT", PAD + 2, -12)
    panel.title:SetText("Party pins")
    panel.count = PL.Text(body, "GameFontNormalSmall", "meta")
    panel.count:SetPoint("LEFT", panel.title, "RIGHT", 8, -1)
    local close = W(S.Close(body, function() PW.Hide() end, pal))
    close:SetPoint("TOPRIGHT", -8, -7)

    -- search and Place a pin
    local well = CreateFrame("Frame", nil, body)
    well:SetSize(WIDTH - PAD * 2 - 104, 22)
    well:SetPoint("TOPLEFT", PAD + 4, -44)
    panel.search = CreateFrame("EditBox", nil, well, "InputBoxTemplate")
    panel.search:SetAllPoints()
    panel.search:SetAutoFocus(false)
    panel.search:SetMaxLetters(40)
    PL.Edit(panel.search)
    panel.search.placeholder = PL.Text(well, "GameFontDisableSmall", "meta")
    panel.search.placeholder:SetPoint("LEFT", 2, 0)
    panel.search.placeholder:SetText("Search names and places")
    panel.search:SetScript("OnTextChanged", function(self)
        search = (self:GetText() or ""):match("^%s*(.-)%s*$")
        self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
        Request()
    end)
    panel.search:SetScript("OnEditFocusGained", function(self) self.placeholder:Hide() end)
    panel.search:SetScript("OnEditFocusLost", function(self) self.placeholder:SetShown(self:GetText() == "") end)
    panel.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    panel.search:SetScript("OnEnterPressed", panel.search.ClearFocus)
    panel.place = W(S.Button(body, "Place a pin", 96, "primary", function()
        CloseMenu()
        R.PinsMap.Arm()
    end, pal))
    panel.place:SetHeight(22)
    panel.place:SetPoint("TOPRIGHT", -PAD, -44)
    Tip(panel.place, "Place a pin", "The next click on your world map, within a minute, places a pin there. You can choose local or party before saving it. (The map isn't opened for you.)")

    -- filters
    panel.filters = {}
    local x = PAD
    for _, def in ipairs({ { "all", "All", 40, "Every pin on your map." }, { "local", "Local", 50, "Only you see these; they are kept between sessions." },
        { "party", "Party", 50, "Shared with party members who have TwichUI, for this party only." },
        { "kept", "Kept", 46, "Pins you kept: protected from deletion and clearing until you turn Keep off." },
        { "dismissed", "Removed", 66, "Party pins you removed from your map. Restore them from here." } }) do
        local key = def[1]
        local b = W(S.Toggle(body, def[2], def[3], function()
            filter = key
            Request()
        end, pal))
        b:SetPoint("TOPLEFT", x, -74)
        Tip(b, def[2], def[4])
        panel.filters[key] = b
        x = x + def[3] + 4
    end
    -- on the title row: the filter row is full now
    panel.state = PL.Text(body, "GameFontNormalSmall", "meta")
    panel.state:SetPoint("LEFT", panel.count, "RIGHT", 8, 0)
    panel.state:SetPoint("RIGHT", close, "LEFT", -6, 0)
    panel.state:SetJustifyH("RIGHT")
    panel.state:SetWordWrap(false)

    -- the list
    local listH = HEIGHT - LIST_TOP - 44
    list = CreateFrame("Frame", nil, body, "BackdropTemplate")
    list:SetSize(WIDTH - PAD * 2, listH)
    list:SetPoint("TOPLEFT", PAD, -LIST_TOP)
    S.Well(list, WIDTH - PAD * 2, listH, pal)
    local scroll = CreateFrame("ScrollFrame", nil, list, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -24, 4)
    list.paintBar = S.ScrollBar(scroll, pal)
    list.content = CreateFrame("Frame", nil, scroll)
    list.content:SetSize(WIDTH - PAD * 2 - 28, 1)
    scroll:SetScrollChild(list.content)
    list.empty = PL.Text(list, "GameFontNormalSmall", "meta")
    list.empty:SetPoint("TOPLEFT", 12, -12)
    list.empty:SetPoint("RIGHT", -12, 0)
    list.empty:SetWordWrap(true)
    rows = {}

    -- footer
    local more = W(S.Link(body, "More", function(self) OpenMore(self) end, pal.gold, pal.text))
    more:SetSize(40, 14)
    more:SetPoint("BOTTOMRIGHT", -PAD - 2, 16)
    Tip(more, "More", "Remove every party pin from your map, delete all local pins, or open the options.")
    panel.hint = PL.Text(body, "GameFontNormalSmall", "meta")
    panel.hint:SetPoint("BOTTOMLEFT", PAD + 2, 16)
    panel.hint:SetPoint("RIGHT", more, "LEFT", -8, 0)
    panel.hint:SetWordWrap(false)
    local hintArea = CreateFrame("Frame", nil, body)
    hintArea:SetAllPoints(panel.hint)
    R.Interact.TipTruncated(hintArea, panel.hint, function() return PL.HowToPlace() end)

    panel:SetScript("OnShow", function(self)
        Restyle()
        R.FitToScreen(self)
        PW.Refresh()
    end)
    panel:SetScript("OnHide", CloseMenu)
    local px, py = Position()
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", UIParent, "CENTER", px, py)
end

function PW.Show()
    if not R:Enabled("partyPins") then
        R.Print("Party pins are turned off. Turn them on in /tui options (Party pins).")
        return false
    end
    Build()
    panel:Show()
    panel:Raise()
    return true
end

function PW.Hide() if panel then panel:Hide() end end
function PW.Toggle() if panel and panel:IsShown() then PW.Hide() else PW.Show() end end
function PW.IsOpen() return panel ~= nil and panel:IsShown() end

PN.OnChange(Request)
PL.OnPrefChange(Request)
PL.Subscribe(function() if panel and panel:IsShown() then Restyle() end end)

-- Read only, for /tui diagnostics.
function PW.Snapshot()
    return { built = panel ~= nil, open = PW.IsOpen(), rows = rows and #rows or 0, filter = filter, searching = search ~= "" }
end
