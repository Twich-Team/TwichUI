-- TwichUI: the NPC search on the world map's tool bar
-- An optional field on the map tools bar (pins/MapTools.lua) that searches the vendors, trainers and services in your own
-- list (npcs/Search.lua: what you dealt with and what other players sent you; nothing is looked up) and picks the one you
-- choose out on the map (npcs/Map.lua's Locate). A way to consult your notes, not a database of the world.
--   Off until chosen (Map Toolbar settings: "Show NPC search"; ui.partyPins.npcSearch). While it is off, or Vendors and
--     trainers is, nothing is built, listened to or searched: the field is made the first time the bar is laid out with the
--     choice on, and put away (results closed, focus released, text cleared, the pick let go) when it goes off.
--   The field never takes the keyboard by itself: not when the map opens, not when the bar is drawn. Clicking it does.
--   Typing waits a moment (DEBOUNCE) and then searches once; every search reads your place once and ranks every match,
--     so the rows are the nearest ones (npcs/Search.lua says how, and what is not compared). Nothing moves the rows
--     afterwards: no polling, no reordering while you choose. A change to the list while the results are open searches
--     again once, with the place read for those results, so the order only changes where the list did.
--   The results are a capped list under the bar (at most SR.MAX_RESULTS rows, made when first needed and reused): the name, the role, the area and,
--     only when it can be told, how far in a straight line. A row is one place; two of the same name in one area also
--     show their coordinates. Mouse, Up/Down, Enter; Esc closes the list and lets go of the field. An empty field says
--     what it is for instead of listing everything; a search with no match says so.
--   Choosing one goes to NMAP.Locate: the map shows the NPC's area and rings its marker for a moment. It makes no waypoint,
--     route or ping, sends nothing and leaves the chosen kinds alone. An NPC removed meanwhile is said so and the list is
--     searched again.
--   Closes with: the map, the bar, the choice going off, choosing, Esc, a click on the map, another tool on the bar.
-- Saved: nothing here (the choice is PL.Pref("npcSearch")). Held in memory only while open: the results.

local R = TwichUI
local PL = R.PinsLook
local NS, SR, NMAP = R.NpcStore, R.NpcSearch, R.NpcMap
local SB = {}
R.NpcSearchBar = SB

local DEBOUNCE = 0.2
local FIELD_H = 22
local MIN_W, MAX_W, DEFAULT_W = 90, 170, 150      -- the field's width, and what it takes when the room isn't known
local ICON = 18
local CLICK_PRIORITY = 120                          -- above the tool bar's (110); never takes a click, only notes it
local MAX_TEXT = 48
local PLACEHOLDER = "Search known NPCs\226\128\166"
local HINT = "Type a name or a role, like innkeeper. Only NPCs in your list are searched."

local installed = false
local box, edit, list, rows
local open = false
local results, total, query = {}, 0, ""
local spot                                           -- where you were when these results were made
local sel = 0
local token = 0                                      -- bumped by every typed change, close and redraw: older waits do nothing
local lastSay, lastSayAt

local function Pal()
    local T = R.MapTools
    return T and T.Pal and T.Pal() or { text = { 0.94, 0.91, 0.82 }, textDim = { 0.80, 0.78, 0.72 }, stone = { 0.62, 0.60, 0.56 },
        teal = { 0.36, 0.58, 0.57 }, tealHi = { 0.58, 0.78, 0.76 }, tealLo = { 0.18, 0.33, 0.33 } }
end
local function Paint(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end
local function Solid(f, layer, c, a)
    local t = f:CreateTexture(nil, layer)
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    return t
end

local function Say(text)
    local now = GetTime()
    if text == lastSay and lastSayAt and now >= lastSayAt and now - lastSayAt < 3 then return end
    lastSay, lastSayAt = text, now
    if R.PinsMap and R.PinsMap.Notice then R.PinsMap.Notice(text) end
end

function SB.Active()
    return SR ~= nil and NMAP ~= nil and R:Enabled("partyPins") and R:Enabled("npcMap") and PL.Pref("npcSearch") == true
end
function SB.Built() return box ~= nil end
function SB.Open() return open end

---------------------------------------------------------------------------
-- Closing and clearing
---------------------------------------------------------------------------
-- Closes the list and forgets its results. keepFocus: leave the field as it is (typing goes on).
local function CloseList(keepFocus)
    token = token + 1
    open = false
    results, total, sel, spot = {}, 0, 0, nil
    if list and list:IsShown() then list:Hide() end
    if GameTooltip and GameTooltip.Hide and rows then
        for _, row in ipairs(rows) do if GameTooltip:IsOwned(row) then GameTooltip:Hide() end end
    end
    if not keepFocus and edit and edit:HasFocus() then edit:ClearFocus() end
end

function SB.Close() CloseList(false) end

-- The map closed, or the field is going away: also the text and whatever it picked out.
local function PutAway()
    CloseList(false)
    if edit and (edit:GetText() or "") ~= "" then edit:SetText("") end
    if NMAP and NMAP.ClearReveal then NMAP.ClearReveal() end
end
function SB.PutAway() PutAway() end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local function Skin(f)
    f.pad = math.max(4, math.ceil(PL.Surface(PL.MenuLook, f)))
    return f.pad
end

local function LineHeight() return math.ceil(PL.Get("textSize") * 1.25) end
local function RowHeight() return LineHeight() * 2 + 8 end

local function SetSel(i)
    sel = i
    for n, row in ipairs(rows or {}) do row.on:SetShown(n == sel and row:IsShown()) end
end

local function Tip(row)
    local r = results[row.index]
    if not r then return end
    local e = r.e
    GameTooltip:SetOwner(row, "ANCHOR_LEFT", -2, 0)
    GameTooltip:SetText(e.n, 1, 1, 1, 1, true)
    if e.t then GameTooltip:AddLine(e.t, 0.86, 0.69, 0.30, true) end
    for _, line in ipairs(NMAP.KindLines(e)) do GameTooltip:AddLine("\226\128\162 " .. line, 0.78, 0.74, 0.66) end
    GameTooltip:AddLine(("%s (%s)"):format(r.zone, r.place), 0.62, 0.58, 0.51)
    if r.dist then
        GameTooltip:AddLine(("About %s away, in a straight line. Not a walking distance."):format(SR.DistanceText(r.dist)), 0.78, 0.74, 0.66, true)
    end
    GameTooltip:AddLine(NMAP.Provenance(e), 0.62, 0.58, 0.51, true)
    GameTooltip:AddLine("Click to show it on the map", 0.45, 0.43, 0.38)
    GameTooltip:Show()
end

local function Choose(i)
    local r = results[i]
    if not r then return false end
    local ok, why = NMAP.Locate(r.e)
    if ok then
        CloseList(false)
        return true
    end
    if why == "gone" then
        Say("That NPC is no longer in your list.")
        SB.Search(true)   -- the list changed under the results: look again, keeping the place they were made for
    elseif why == "closed" then
        CloseList(false)
    end
    return false
end

local function NewRow(i)
    local pal = Pal()
    local row = CreateFrame("Button", nil, list)
    row:RegisterForClicks("LeftButtonUp")
    row.index = i
    row.on = Solid(row, "BACKGROUND", pal.tealLo, 0.75)
    row.on:SetAllPoints()
    row.on:Hide()
    row.accent = Solid(row, "BORDER", pal.tealHi, 1)       -- the chosen row is marked by more than its color
    row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.accent:SetWidth(2)
    row.accent:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.dist = PL.Text(row, "GameFontNormalSmall", "meta")
    row.dist:SetJustifyH("RIGHT")
    row.dist:SetWordWrap(false)
    row.name = PL.Text(row, "GameFontNormalSmall", "name")
    row.name:SetWordWrap(false)
    row.meta = PL.Text(row, "GameFontNormalSmall", "meta")
    row.meta:SetWordWrap(false)
    row:SetScript("OnEnter", function(self) SetSel(self.index); Tip(self) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self) Choose(self.index) end)
    return row
end

local function Build(bar)
    local pal = Pal()
    box = CreateFrame("Frame", nil, bar)
    box:SetHeight(FIELD_H)
    box.bg = Solid(box, "BACKGROUND", { 0.06, 0.05, 0.04 }, 0.85)
    box.bg:SetAllPoints()
    box.line = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local e = Solid(box, "BORDER", pal.stone, 0.55)
        if i <= 2 then
            e:SetHeight(1)
            e:SetPoint(side .. "LEFT", 0, 0)
            e:SetPoint(side .. "RIGHT", 0, 0)
        else
            e:SetWidth(1)
            e:SetPoint("TOP" .. side, 0, 0)
            e:SetPoint("BOTTOM" .. side, 0, 0)
        end
        box.line[i] = e
    end

    edit = CreateFrame("EditBox", nil, box)
    edit:SetPoint("TOPLEFT", box, "TOPLEFT", 6, 0)
    edit:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -18, 0)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetAutoFocus(false)                 -- the field takes the keyboard only when it is clicked
    edit:SetMaxLetters(MAX_TEXT)
    edit:SetTextInsets(0, 0, 0, 0)
    PL.Edit(edit)
    Paint(edit, pal.text)

    box.hint = PL.Text(box, "GameFontNormalSmall", "meta")
    box.hint:SetPoint("LEFT", box, "LEFT", 6, 0)
    box.hint:SetPoint("RIGHT", box, "RIGHT", -18, 0)
    box.hint:SetWordWrap(false)
    box.hint:SetText(PLACEHOLDER)
    Paint(box.hint, pal.stone)

    box.clear = CreateFrame("Button", nil, box)
    box.clear:SetSize(16, FIELD_H)
    box.clear:SetPoint("RIGHT", box, "RIGHT", -1, 0)
    box.clear.text = PL.Text(box.clear, "GameFontNormalSmall", "meta")
    box.clear.text:SetPoint("CENTER", 0, 1)
    box.clear.text:SetText("x")
    Paint(box.clear.text, pal.textDim)
    box.clear:SetScript("OnEnter", function(self)
        Paint(self.text, Pal().tealHi)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT", 0, -2)
        GameTooltip:SetText("Clear the search", 1, 1, 1)
        GameTooltip:AddLine("Also lets go of the NPC picked out on the map.", 0.78, 0.74, 0.66, true)
        GameTooltip:Show()
    end)
    box.clear:SetScript("OnLeave", function(self) Paint(self.text, Pal().textDim); GameTooltip:Hide() end)
    box.clear:SetScript("OnClick", function()
        edit:SetText("")                      -- programmatic: OnTextChanged is told it wasn't typed
        PutAway()
        edit:SetFocus()
        SB.Show()
    end)
    box.clear:Hide()

    list = CreateFrame("Frame", "TwichUIMapSearch", bar, "BackdropTemplate")
    list:SetFrameStrata("HIGH")
    list:EnableMouse(true)                    -- a click on the list is not a click on the map
    list:Hide()
    list.status = PL.Text(list, "GameFontNormalSmall", "meta")
    list.status:SetJustifyH("LEFT")
    list.status:SetJustifyV("TOP")
    list.status:SetWordWrap(true)
    list.foot = PL.Text(list, "GameFontNormalSmall", "meta")
    list.foot:SetJustifyH("LEFT")
    list.foot:SetWordWrap(true)
    list:SetScript("OnLeave", function(self)
        if not edit:HasFocus() and not self:IsMouseOver() then CloseList(false) end
    end)
    rows = {}                                  -- made as results first need them (never more than SR.MAX_RESULTS)

    edit:SetScript("OnEditFocusGained", function()
        if R.MapTools and R.MapTools.DismissIntro then R.MapTools.DismissIntro() end   -- using the bar counts as seeing the note
        SB.Search(false)
    end)
    edit:SetScript("OnEditFocusLost", function()
        -- a click on a row reaches the row first: keep the list while the pointer is on it
        if list:IsShown() and list:IsMouseOver() then return end
        CloseList(true)
    end)
    edit:SetScript("OnTextChanged", function(self, user)
        local has = (self:GetText() or "") ~= ""
        box.hint:SetShown(not has)
        box.clear:SetShown(has)
        if not user then return end
        if not SB.Active() then return end
        SB.Schedule()
    end)
    edit:SetScript("OnEscapePressed", function() CloseList(false) end)
    edit:SetScript("OnEnterPressed", function()
        if SB.pendingText then SB.Search(false) end   -- typed a moment ago: search first
        if open and sel >= 1 then Choose(sel) end
    end)
    edit:SetScript("OnArrowPressed", function(_, key)
        if not open or #results == 0 then return end
        if key == "UP" then SetSel(sel <= 1 and #results or sel - 1)
        elseif key == "DOWN" then SetSel(sel >= #results and 1 or sel + 1) end
    end)
    edit:SetScript("OnEnter", function(self)
        if open then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT", 0, -2)
        GameTooltip:SetText("Search known NPCs", 1, 1, 1)
        GameTooltip:AddLine("Finds the vendors, trainers and services in your list, nearest first, and shows one on the map. Only NPCs you have noted or been sent are searched; nothing is looked up.", 0.78, 0.74, 0.66, true)
        GameTooltip:Show()
    end)
    edit:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Draws the list for the current results (or the one line that stands in for them).
function SB.Show()
    if not (list and edit) then return end
    local pal = Pal()
    local pad = list.pad or Skin(list)
    local rowH = RowHeight()
    local nav = WorldMapFrame and WorldMapFrame.NavBar
    local room = WorldMapFrame and WorldMapFrame.GetCanvasContainer and WorldMapFrame:GetCanvasContainer()
    room = room and room:GetWidth() or 0
    local width = room > 0 and math.min(340, math.max(260, math.floor(room * 0.4))) or 300
    list:SetWidth(width)
    list:ClearAllPoints()
    if nav then
        list:SetPoint("TOPRIGHT", list:GetParent(), "BOTTOMRIGHT", 0, -3)   -- inside the map, whatever the bar's width
    else
        list:SetPoint("TOPLEFT", list:GetParent(), "BOTTOMLEFT", 0, -3)
    end
    list:SetFrameLevel((list:GetParent():GetFrameLevel() or 1) + 20)
    local y = -(pad + 3)
    local n = #results
    local text
    if query == "" then text = HINT
    elseif n == 0 then text = "No known NPCs match." end
    list.status:SetShown(text ~= nil)
    if text then
        list.status:ClearAllPoints()
        list.status:SetPoint("TOPLEFT", list, "TOPLEFT", pad + 6, y - 3)
        list.status:SetWidth(width - (pad + 6) * 2)
        list.status:SetText(text)
        Paint(list.status, pal.textDim)
        y = y - (list.status:GetStringHeight() or LineHeight()) - 10
    end
    for i = #rows + 1, n do rows[i] = NewRow(i) end
    for i, row in ipairs(rows) do
        local r = results[i]
        if r then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", list, "TOPLEFT", pad + 2, y)
            row:SetSize(width - (pad + 2) * 2, rowH)
            local kind = R.NpcKinds.Primary(r.e.tags)
            row.icon:SetTexture(kind and kind.icon or nil)
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.dist:ClearAllPoints()
            row.dist:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -4)
            row.dist:SetText(r.dist and SR.DistanceText(r.dist) or (r.tier == 2 and "this area" or ""))
            Paint(row.dist, pal.textDim)
            row.name:ClearAllPoints()
            row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 6 + ICON + 6, -4)
            row.name:SetPoint("RIGHT", row.dist, "LEFT", -6, 0)
            row.name:SetText(r.name)
            Paint(row.name, pal.text)
            row.meta:ClearAllPoints()
            row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
            row.meta:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            local role = r.more > 0 and ("%s +%d"):format(r.role, r.more) or r.role
            row.meta:SetText(r.coords and ("%s \194\183 %s (%s)"):format(role, r.zone, r.place) or ("%s \194\183 %s"):format(role, r.zone))
            Paint(row.meta, pal.textDim)
            row.accent:SetShown(i == sel)
            row.on:SetShown(i == sel)
            row:Show()
            y = y - rowH
        else
            row:Hide()
            row.on:Hide()
        end
    end
    local foot
    if n > 0 then
        foot = total > n and ("Nearest %d of %d. Keep typing to narrow it."):format(n, total) or nil
        local anyDist = false
        for _, r in ipairs(results) do if r.dist then anyDist = true break end end
        if anyDist then
            foot = (foot and (foot .. " ") or "") .. "Distances are straight lines."
        end
    end
    list.foot:SetShown(foot ~= nil)
    if foot then
        list.foot:ClearAllPoints()
        list.foot:SetPoint("TOPLEFT", list, "TOPLEFT", pad + 6, y - 4)
        list.foot:SetWidth(width - (pad + 6) * 2)
        list.foot:SetText(foot)
        Paint(list.foot, pal.stone)
        y = y - (list.foot:GetStringHeight() or LineHeight()) - 8
    end
    list:SetHeight(-y + pad + 3)
    list:Show()
    open = true
end

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------
-- Searches now. keepSpot: for the same results again after the list changed (the place is not read again, so only the
-- list's change can move a row).
function SB.Search(keepSpot)
    SB.pendingText = nil
    if not (edit and SB.Active()) then return end
    token = token + 1
    local text = edit:GetText() or ""
    local keep = results[sel] and results[sel].key
    if not (keepSpot and spot) then spot = SR.Where() end
    results, total, query = SR.Run(text, spot, SR.MAX_RESULTS)
    sel = #results > 0 and 1 or 0
    if keep then
        for i, r in ipairs(results) do if r.key == keep then sel = i break end end
    end
    SB.Show()
end

-- A change was typed: one search after a pause, however many keys came.
function SB.Schedule()
    token = token + 1
    local mine = token
    local text = SR.Clean(edit:GetText() or "")
    if text == "" then
        -- nothing to search for: the hint stands in, and nothing stays picked out
        query, results, total, sel = "", {}, 0, 0
        if NMAP.Revealed() then NMAP.ClearReveal() end
        SB.Show()
        return
    end
    SB.pendingText = true
    C_Timer.After(DEBOUNCE, function()
        if token == mine and edit and SB.Active() then SB.Search(false) end
    end)
end

-- The list changed (a record arrived, was updated or removed): while the results are open they are made again, once.
NS.OnChange(function()
    if not (open and edit and SB.Active()) then return end
    token = token + 1
    local mine = token
    C_Timer.After(DEBOUNCE, function()
        if token == mine and open and edit and SB.Active() then SB.Search(true) end
    end)
end)

---------------------------------------------------------------------------
-- On the bar
---------------------------------------------------------------------------
-- A click on the map closes the list (the map still gets the click: this never takes it). Only while the field is on.
local function OnCanvasClick()
    if open then
        if edit and edit:HasFocus() then edit:ClearFocus() end
        CloseList(false)
    end
    return false
end

local function Install()
    if installed or not WorldMapFrame then return end
    WorldMapFrame:AddCanvasClickHandler(OnCanvasClick, CLICK_PRIORITY)
    installed = true
end

local function Uninstall()
    if not installed then return end
    if WorldMapFrame then WorldMapFrame:RemoveCanvasClickHandler(OnCanvasClick, CLICK_PRIORITY) end
    installed = false
end

-- Called by the tool bar each time it lays itself out: puts the field at x (the bar's left, after its padding) when it is
-- wanted and there is room, and returns where the buttons start. room: the width the field may take (nil: not known).
-- With the choice off, or no room, the field is put away and x comes back unchanged.
function SB.Layout(bar, x, pad, gap, room)
    local width = room == nil and DEFAULT_W or math.min(MAX_W, math.floor(room))
    if not SB.Active() or width < MIN_W then
        if box then
            box:Hide()
            PutAway()
        end
        Uninstall()
        return x
    end
    if not box then Build(bar) end
    box:ClearAllPoints()
    box:SetPoint("LEFT", bar, "LEFT", x, 0)
    box:SetWidth(width)
    box:Show()
    local stone = Pal().stone
    for _, e in ipairs(box.line) do e:SetColorTexture(stone[1], stone[2], stone[3], 0.55) end
    Install()
    return x + width + gap + 4
end

-- The map closed, or the bar went: nothing stays open or picked out.
function SB.Hide()
    if not box then return end
    PutAway()
    Uninstall()
end

-- The choice or the switch changed: the bar lays itself out again.
function SB.Refresh()
    local T = R.MapTools
    if T and T.Refresh then T.Refresh() end
end

local function LookChanged()
    if open and list then
        list.pad = nil
        SB.Show()
    end
end
PL.Subscribe(LookChanged)
PL.MenuLook.Subscribe(LookChanged)

-- Read only, for /tui diagnostics and the tests: states and counts, never a query or a place.
function SB.Snapshot()
    return { active = SB.Active(), built = box ~= nil, shown = box ~= nil and box:IsShown() or false, open = open,
        results = #results, rows = rows and #rows or 0, handler = installed, focused = edit ~= nil and edit:HasFocus() or false }
end
