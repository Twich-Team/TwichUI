-- TwichUI settings: World Knowledge (npcs/Knowledge.lua), the third tab of Vendors and trainers. A browsable list of
-- every vendor, trainer and service in your list, with a search and three filters, what is known about the one you
-- pick (where it stands, what it offers, how it became known), and the actions on it: send it, forget it, send or
-- forget the results the filters show, and clear one area. A frame of this window's own, shown as the tab's page,
-- built the first time the tab is shown.
-- The list is drawn with a handful of row frames (the visible ones and two more) that are given new entries as it
-- scrolls, so a full list costs no more frames than an empty one. Filtering reads the rows npcs/Knowledge.lua keeps
-- and builds a new list; nothing here changes what is saved except Forget and Clear area, which go through
-- NpcStore.ForgetMany, and sending goes through NpcShare's own question and protocol.
-- The questions hold to the entries they were asked about: a filtered set or an area is read once, when its button is
-- clicked, so what arrives later, or a changed filter, never widens what is removed or sent.
-- The tab listens (list changes, group and guild changes) only while it is shown.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.NpcKnowledgePage = P

local W = 644                  -- the settings window's content width
local ROW_H, VISIBLE = 24, 8
local ROWS = VISIBLE + 2
local LIST_TOP = -100
local LIST_H = ROW_H * VISIBLE + 8
local LIST_W = W - 12 - 26     -- inside the well, less the scroll bar
local COL_ROLE, COL_ZONE, COL_SOURCE = 214, 372, 540
local DETAIL_TOP = LIST_TOP - LIST_H - 16
local DETAIL_H = 104
local RESULTS_Y = DETAIL_TOP - DETAIL_H - 10
local AREA_Y = RESULTS_Y - 40
local DEBOUNCE = 0.2

local f, built
local rows = {}
local list = {}                -- the rows the filters show
local sel                      -- the selected entry (its table), or nil
local flt = { text = "", map = nil, kind = nil, source = "any" }
local searchToken = 0
local refreshQueued = false
local clearMap                 -- the area chosen for Clear area

local function Wg() return R.SettingsWidgets end
local function KN() return R.NpcKnowledge end
local function Records(n) return ("%d %s"):format(n, n == 1 and "record" or "records") end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
local function Refilter()
    local kn = KN()
    list = kn.Filter(flt)
    if sel then
        local row = kn.Row(sel)
        local found = false
        if row then
            for _, r in ipairs(list) do if r == row then found = true break end end
        end
        if not found then sel = nil end
    end
end

local function IndexOfSelection()
    if not sel then return nil end
    local row = KN().Row(sel)
    for i, r in ipairs(list) do if r == row then return i end end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function Row(i)
    if rows[i] then return rows[i] end
    local G = Wg()
    local pal = G.pal
    local row = CreateFrame("Button", nil, f.content)
    row:SetSize(LIST_W, ROW_H)
    row.bg = G.Solid(row, "BACKGROUND", pal.text, 0)
    row.bg:SetAllPoints()
    row.mark = G.Solid(row, "ARTWORK", pal.teal, 1)
    row.mark:SetSize(2, ROW_H - 6)
    row.mark:SetPoint("LEFT", 0, 0)
    row.name = G.Text(row, "body")
    row.name:SetPoint("LEFT", 8, 0)
    row.name:SetWidth(COL_ROLE - 14)
    row.name:SetWordWrap(false)
    row.role = G.Text(row, "small")
    row.role:SetPoint("LEFT", COL_ROLE, 0)
    row.role:SetWidth(COL_ZONE - COL_ROLE - 6)
    row.role:SetWordWrap(false)
    row.zone = G.Text(row, "small")
    row.zone:SetPoint("LEFT", COL_ZONE, 0)
    row.zone:SetWidth(COL_SOURCE - COL_ZONE - 6)
    row.zone:SetWordWrap(false)
    row.source = G.Text(row, "meta")
    row.source:SetPoint("LEFT", COL_SOURCE, 0)
    row.source:SetWidth(LIST_W - COL_SOURCE - 4)
    row.source:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        if self.row then P.Select(self.row.e) end
    end)
    row:SetScript("OnEnter", function(self) if not self.picked then self.bg:SetAlpha(0.05) end end)
    row:SetScript("OnLeave", function(self) if not self.picked then self.bg:SetAlpha(self.stripe and 0.03 or 0) end end)
    rows[i] = row
    return row
end

-- Gives the row frames the entries now in view.
local function Paint()
    if not (f and built) then return end
    local G = Wg()
    local pal = G.pal
    local offset = f.scroll:GetVerticalScroll() or 0
    local first = math.floor(offset / ROW_H) + 1
    for i = 1, ROWS do
        local row = Row(i)
        local idx = first + i - 1
        local data = list[idx]
        row.row = data
        if data then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(idx - 1) * ROW_H)
            row.name:SetText(data.name)
            row.role:SetText(data.more > 0 and ("%s +%d"):format(data.role, data.more) or data.role)
            row.zone:SetText(data.zone)
            row.source:SetText(R.NpcKnowledge.SourceWord(data))
            local picked = sel ~= nil and rawequal(data.e, sel)
            row.picked = picked
            row.stripe = idx % 2 == 0
            row.mark:SetShown(picked)
            row.bg:SetAlpha(picked and 0.09 or (row.stripe and 0.03 or 0))
            G.Color(row.name, picked and pal.tealHi or pal.text)
            G.Color(row.role, pal.textDim)
            G.Color(row.zone, pal.textDim)
            G.Color(row.source, data.source == "mine" and pal.tealHi or pal.stone)
            row:Show()
        else
            row:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Details and actions
---------------------------------------------------------------------------
local SHARES = {
    { "party", "Group", "Everyone in your party or raid with TwichUI receives it; each of them chooses whether to add it." },
    { "guild", "Guild", "Every online guild member with TwichUI receives it; each of them chooses whether to add it." },
    { "whisper", "Player...", "Asks for the character's name; only they receive it." },
}

local function UpdateButtons()
    if not (f and built) then return end
    local kn = KN()
    for _, set in ipairs({ f.shareOne, f.shareAll }) do
        for _, b in ipairs(set) do
            local why = kn.Unavailable(b.audience)
            if not set.has() then why = why or "There is nothing to send." end
            b.why = why
            b:SetEnabled(not why)
        end
    end
    f.forgetOne:SetEnabled(sel ~= nil)
    f.forgetAll:SetEnabled(#list > 0 and kn.Active(flt))
    f.clearArea:SetEnabled(clearMap ~= nil)
end

local function PaintDetails()
    if not (f and built) then return end
    local G = Wg()
    local pal = G.pal
    local row = sel and KN().Row(sel)
    if not row then
        f.dName:SetText("")
        f.dBody:SetText(#KN().Rows() == 0 and "" or "Choose a record to see where it stands, what it offers and how it became known.")
        G.Color(f.dBody, pal.stone)
        UpdateButtons()
        return
    end
    local d = KN().Details(row)
    f.dName:SetText(row.name)
    local text = {}
    if d.title then text[#text + 1] = '"' .. d.title .. '"' end
    text[#text + 1] = table.concat(d.roles, ", ")
    text[#text + 1] = d.place
    text[#text + 1] = table.concat(d.sources, " ")
    f.dBody:SetText(table.concat(text, "\n"))
    G.Color(f.dBody, pal.textDim)
    UpdateButtons()
end

function P.Select(e)
    sel = e
    Paint()
    PaintDetails()
end

local function Place(e)
    local PN = R.Pins
    return PN and PN.Describe({ map = e.m, x = e.x, y = e.y }) or KN().ZoneName(e.m)
end

local function ForgetSelected()
    local e = sel
    if not e then return end
    local row = KN().Row(e)
    if not row then return end
    local same = 0
    for _, other in ipairs(R.NpcStore.Entries()) do
        if other.id == e.id and other ~= e then same = same + 1 end
    end
    local text = ("Delete %s at %s?\n\nThis removes only this record%s. %s"):format(row.name, Place(e),
        same > 0 and (" (the same NPC's %d other %s stay)"):format(same, same == 1 and "place" or "places") or "",
        e.own and "It is noted again the next time you deal with it."
            or "It comes back if another TwichUI user sends it again.")
    R.Interact.Confirm("TWICHUI_NPC_FORGET_ONE", text, function()
        if R.NpcKnowledge.Forget({ e }) > 0 then P.Say(("Deleted %s."):format(row.name)) end
    end, { accept = "Delete", valid = function()
        for _, x in ipairs(R.NpcStore.Entries()) do if rawequal(x, e) then return true end end
        return false, "It's no longer in your list."
    end })
end

local function ForgetResults()
    local kn = KN()
    if not kn.Active(flt) or #list == 0 then return end
    local set = kn.Entries(list)   -- this set, as it is now
    local text = ("Delete the %s these filters show (%s)?\n\nOnly these %d go. Records that arrive later, or that the filters would show after a change, are not part of this. Nothing else in your list, your settings or your pins changes. Deleted records are noted again when you deal with them, or if another TwichUI user sends them."):format(
        Records(#set), kn.Describe(flt), #set)
    R.Interact.Confirm("TWICHUI_NPC_FORGET_SET", text, function()
        local n = R.NpcKnowledge.Forget(set)
        P.Say(("Deleted %s."):format(Records(n)))
    end, { accept = "Delete " .. #set })
end

local function ClearArea()
    local kn = KN()
    if not clearMap then return end
    local set = kn.AreaEntries(clearMap)
    local name = kn.ZoneName(clearMap)
    if #set == 0 then P.Say(("Nothing is noted in %s."):format(name)) P.Refresh() return end
    local text = ("Clear everything noted in %s?\n\nThis deletes all %s standing on that map, whatever the filters above show. The same NPCs noted in other areas stay, and so do maps inside it (a dungeon, a district) and the area around it. Records that arrive later are not part of this. Other TwichUI users can send these again."):format(
        name, Records(#set))
    R.Interact.Confirm("TWICHUI_NPC_CLEAR_AREA", text, function()
        local n = R.NpcKnowledge.Forget(set)
        P.Say(("Cleared %s from %s."):format(Records(n), name))
    end, { accept = "Clear " .. #set })
end

-- The line under the filters: what just happened.
function P.Say(text)
    P.lastSaid = text
    if f and built then f.note:SetText(text or "") end
end

local function Share(entries, audience, scope)
    if #entries == 0 then return end
    R.NpcKnowledge.Share(entries, audience, scope)
end

local function ShareSelected(audience)
    if not sel then return end
    local row = KN().Row(sel)
    Share({ sel }, audience, ("%s"):format(row and row.name or "this NPC"))
end

local function ShareResults(audience)
    if #list == 0 then return end
    Share(KN().Entries(list), audience, ("the %s shown"):format(Records(#list)))
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function ZoneChoices(withAll)
    local out = {}
    if withAll then out[1] = { value = "all", label = "Every area" } end
    for _, z in ipairs(KN().Zones()) do
        out[#out + 1] = { value = z.map, label = ("%s (%d)"):format(z.name, z.count) }
    end
    return out
end

local function KindChoices()
    local out = { { value = "all", label = "Every role" } }
    for _, k in ipairs(KN().Kinds()) do out[#out + 1] = { value = k.id, label = ("%s (%d)"):format(k.label, k.count) } end
    return out
end

local function SourceChoices()
    local out = {}
    for _, s in ipairs(KN().SOURCES) do out[#out + 1] = { value = s[1], label = s[2] } end
    return out
end

local function SourceLabel(value)
    for _, s in ipairs(KN().SOURCES) do if s[1] == value then return s[2] end end
    return value
end

-- Everything on the tab from the data as it is now. Keeps the selection while it is still shown.
function P.Refresh(toTop)
    if not (f and built and f:IsShown()) then return end
    local kn = KN()
    local total = kn.Total()
    -- a filter on an area or role that no longer has any records shows nothing for ever: drop it
    local counts = {}
    for _, z in ipairs(kn.Zones()) do counts[z.map] = z.count end
    if flt.map and not counts[flt.map] then flt.map = nil end
    if flt.kind then
        local any = false
        for _, k in ipairs(kn.Kinds()) do if k.id == flt.kind then any = true end end
        if not any then flt.kind = nil end
    end
    if clearMap and not counts[clearMap] then clearMap = nil end
    Refilter()
    f.content:SetHeight(math.max(1, #list * ROW_H))
    local idx = IndexOfSelection()
    if toTop then
        local target = 0
        if idx then target = (idx - 1) * ROW_H end
        f.scroll:SetVerticalScroll(math.max(0, math.min(target, f.scroll:GetVerticalScrollRange() or 0)))
    else
        local most = f.scroll:GetVerticalScrollRange() or 0
        if (f.scroll:GetVerticalScroll() or 0) > most then f.scroll:SetVerticalScroll(most) end
    end
    f.zoneDrop:SetValue(flt.map or "all", flt.map and kn.ZoneName(flt.map) or "Every area")
    local kindLabel = "Every role"
    if flt.kind then kindLabel = R.NpcKinds.BY_ID[flt.kind] and R.NpcKinds.BY_ID[flt.kind].label or flt.kind end
    f.kindDrop:SetValue(flt.kind or "all", kindLabel)
    f.sourceDrop:SetValue(flt.source, SourceLabel(flt.source))
    f.areaDrop:SetValue(clearMap or "none", clearMap and kn.ZoneName(clearMap) or "Choose an area...")
    f.count:SetText(total == 0 and "" or ("Showing %d of %d records"):format(#list, total))
    f.reset:SetEnabled(kn.Active(flt))
    if total == 0 then
        f.empty:SetText("Nothing noted yet. Vendors, trainers and services you deal with are written down here, and so are those other TwichUI users send you.")
    elseif #list == 0 then
        f.empty:SetText("No records match these filters.")
    end
    f.empty:SetShown(#list == 0)
    f.off:SetShown(not R:Enabled("npcMap"))
    f.note:SetText(P.lastSaid or "")
    Paint()
    PaintDetails()
end

local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.1, function()
        refreshQueued = false
        P.Refresh()
    end)
end

local function FilterChanged()
    P.Refresh(true)
end

function P.ResetFilters()
    flt.text, flt.map, flt.kind, flt.source = "", nil, nil, "any"
    if f and f.search then f.search:SetText("") end
    P.Refresh(true)
end

local EVENTS = { "GROUP_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" }

local function Build()
    built = true
    local G, I = Wg(), R.Interact
    local pal = G.pal

    f.help = G.Text(f, "small")
    f.help:SetPoint("TOPLEFT", 4, -2)
    f.help:SetWidth(W - 8)
    f.help:SetText("Your field notes: the vendors, trainers and services you have dealt with, and those other TwichUI users sent you. Only what has been noted appears; nothing is looked up or guessed.")

    f.off = G.Text(f, "small")
    f.off:SetPoint("TOPLEFT", 4, -34)
    f.off:SetWidth(W - 8)
    f.off:SetText("Noting vendors and trainers is off (the first tab). You can still browse and tidy what was noted.")
    G.Color(f.off, pal.stone)
    f.off:Hide()

    -- search and filters
    f.search = G.EditBox(f, 250, 22)
    f.search:SetPoint("TOPLEFT", 0, -50)
    f.search:SetMaxLetters(48)
    f.search:SetScript("OnTextChanged", function(self, user)
        if user == false then return end
        local text = self:GetText() or ""
        if text == flt.text then return end
        flt.text = text
        searchToken = searchToken + 1
        local token = searchToken
        C_Timer.After(DEBOUNCE, function() if token == searchToken then FilterChanged() end end)
    end)
    f.search:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then
            self:SetText("")
            if flt.text ~= "" then flt.text = "" searchToken = searchToken + 1 FilterChanged() end
        end
        self:ClearFocus()
    end)
    I.Tip(f.search, "Search", "Finds records by name, area, role, title or profession. Every word you type has to match somewhere, in any order. Esc clears it.")

    f.reset = G.Button(f, "Reset filters", 100, "secondary", P.ResetFilters)
    f.reset:SetPoint("TOPLEFT", 258, -49)
    I.Tip(f.reset, "Reset filters", "Clears the search and the three filters. Nothing is removed.")

    f.count = G.Text(f, "meta")
    f.count:SetPoint("TOPRIGHT", -8, -55)
    f.count:SetJustifyH("RIGHT")

    f.zoneDrop = G.Dropdown(f, 204, function(value)
        flt.map = value ~= "all" and value or nil
        FilterChanged()
    end)
    f.zoneDrop:SetChoices(function() return ZoneChoices(true) end)
    f.zoneDrop:SetPoint("TOPLEFT", 0, -76)
    I.Tip(f.zoneDrop, "Area", "Only records standing on this map. Each area shows how many records it has.")
    f.kindDrop = G.Dropdown(f, 204, function(value)
        flt.kind = value ~= "all" and value or nil
        FilterChanged()
    end)
    f.kindDrop:SetChoices(KindChoices)
    f.kindDrop:SetPoint("TOPLEFT", 212, -76)
    I.Tip(f.kindDrop, "Role", "Only records that offer this: a merchant by what it sold, a trainer, a service. One NPC can be several.")
    f.sourceDrop = G.Dropdown(f, 204, function(value)
        flt.source = value
        FilterChanged()
    end)
    f.sourceDrop:SetChoices(SourceChoices)
    f.sourceDrop:SetPoint("TOPLEFT", 424, -76)
    I.Tip(f.sourceDrop, "Source", "Seen by you: you dealt with it yourself. From others: only reports from other TwichUI users. Source not recorded: older records that don't say.")

    -- the list
    local function Column(text, x)
        local t = G.Text(f, "meta")
        t:SetPoint("TOPLEFT", 6 + x, LIST_TOP + 14)
        t:SetText(text)
        return t
    end
    f.well = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.well:SetPoint("TOPLEFT", 0, LIST_TOP)
    f.well:SetSize(W, LIST_H)
    G.Well(f.well)
    f.scroll, f.content = G.Scroll(f.well, LIST_W)
    f.scroll:SetPoint("TOPLEFT", 6, -4)
    f.scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    f.scroll:HookScript("OnVerticalScroll", function() Paint() end)
    Column("Name", 8)
    Column("Role", COL_ROLE)
    Column("Area", COL_ZONE)
    Column("Source", COL_SOURCE)
    f.empty = G.Text(f.well, "small")
    f.empty:SetPoint("TOPLEFT", 12, -14)
    f.empty:SetWidth(W - 24)

    f.note = G.Text(f, "small")
    f.note:SetPoint("TOPLEFT", 4, LIST_TOP - LIST_H - 3)
    f.note:SetWidth(W - 8)
    f.note:SetWordWrap(false)
    G.Color(f.note, pal.tealHi)

    -- the chosen record
    G.Card(f, 0, DETAIL_TOP, W, DETAIL_TOP - DETAIL_H)
    f.dName = G.Text(f, "heading")
    f.dName:SetPoint("TOPLEFT", 12, DETAIL_TOP - 8)
    f.dName:SetWidth(W - 250)
    f.dName:SetWordWrap(false)
    f.dBody = G.Text(f, "small")
    f.dBody:SetPoint("TOPLEFT", 12, DETAIL_TOP - 28)
    f.dBody:SetWidth(W - 250)
    f.dBody:SetJustifyH("LEFT")
    f.dBody:SetJustifyV("TOP")

    local function ShareButtons(x, y, label, run, has)
        local set = { has = has }
        local t = G.Text(f, "meta")
        t:SetPoint("TOPLEFT", x, y)
        t:SetText(label)
        for i, s in ipairs(SHARES) do
            local b = G.Button(f, s[2], 66, "secondary", function(self)
                if not self.why then run(self.audience) end
            end)
            b.audience = s[1]
            b:SetPoint("TOPLEFT", x + (i - 1) * 70, y - 16)
            I.Tip(b, "Send to " .. (s[1] == "party" and "your group" or (s[1] == "guild" and "your guild" or "a player")),
                function(self) return s[3], self.why end)
            set[#set + 1] = b
        end
        return set
    end
    f.shareOne = ShareButtons(W - 214, DETAIL_TOP - 10, "Send this record", ShareSelected, function() return sel ~= nil end)
    f.forgetOne = G.Button(f, "Delete...", 206, "secondary", ForgetSelected)
    f.forgetOne:SetPoint("TOPLEFT", W - 214, DETAIL_TOP - 68)
    I.Tip(f.forgetOne, "Delete this record", "Deletes only the chosen record. Asks first.")

    -- the results the filters show
    f.resultsLabel = G.Text(f, "meta")
    f.resultsLabel:SetPoint("TOPLEFT", 4, RESULTS_Y - 16)
    f.resultsLabel:SetText("The records shown")
    f.shareAll = ShareButtons(130, RESULTS_Y + 6, "Send these", ShareResults, function() return #list > 0 end)
    f.forgetAll = G.Button(f, "Delete filtered...", 150, "secondary", ForgetResults)
    f.forgetAll:SetPoint("TOPLEFT", W - 150, RESULTS_Y - 10)
    I.Tip(f.forgetAll, "Delete filtered", function()
        if KN().Active(flt) then return "Deletes the records the filters show now, and only those. Asks first, with the exact number." end
        return "Deletes the records the filters show now, and only those.", "Choose a filter first. To empty the whole list, use Remove on the Your list and sharing tab."
    end)

    -- one area
    f.areaTitle = G.Text(f, "heading")
    f.areaTitle:SetPoint("TOPLEFT", 4, AREA_Y)
    f.areaTitle:SetText("Clear an area")
    f.areaDrop = G.Dropdown(f, 250, function(value)
        clearMap = value ~= "none" and value or nil
        P.Refresh()
    end)
    f.areaDrop:SetChoices(function() return ZoneChoices(false) end)
    f.areaDrop:SetPoint("TOPLEFT", 130, AREA_Y + 4)
    I.Tip(f.areaDrop, "Area", "Any area that has records, with how many. Only that map is cleared, not the ones inside it.")
    f.clearArea = G.Button(f, "Clear area...", 120, "secondary", ClearArea)
    f.clearArea:SetPoint("TOPLEFT", 388, AREA_Y + 3)
    I.Tip(f.clearArea, "Clear area", "Deletes every record on the chosen map, whatever the filters show. Asks first, with the exact number.")
    f.areaHelp = G.Text(f, "meta")
    f.areaHelp:SetPoint("TOPLEFT", 4, AREA_Y - 24)
    f.areaHelp:SetWidth(W - 8)
    f.areaHelp:SetJustifyH("LEFT")
    f.areaHelp:SetText("Independent of the filters above. An NPC noted in other areas keeps those. What other TwichUI users send you can bring records back.")
end

-- The page's frame (the settings window shows it as World Knowledge). Built the first time it is shown.
function P.Frame()
    if f then return f end
    f = CreateFrame("Frame")
    f:Hide()
    f:SetScript("OnShow", function(self)
        if not built then Build() end
        P.lastSaid = nil
        for _, e in ipairs(EVENTS) do self:RegisterEvent(e) end
        P.Refresh(true)
    end)
    f:SetScript("OnHide", function(self)
        for _, e in ipairs(EVENTS) do self:UnregisterEvent(e) end
        searchToken = searchToken + 1   -- a search waiting to run is dropped
        if f.search then f.search:ClearFocus() end
        if R.SettingsWidgets and R.SettingsWidgets.CloseMenu then R.SettingsWidgets.CloseMenu() end
    end)
    f:SetScript("OnEvent", function() UpdateButtons() end)
    return f
end

-- A change anywhere (a visit, a received list, a forget on the map) redraws the tab if it is shown. Registered once.
if R.NpcStore then R.NpcStore.OnChange(QueueRefresh) end

K.Page({
    key = "npcsKnowledge", name = "World Knowledge", nav = "World Knowledge", parent = "npcs", order = 77,
    description = "Browse the vendors, trainers and services you have noted or been sent, send or forget one, and clear an area.",
    keywords = "knowledge npc npcs vendor vendors trainer trainers merchant list browse filter search delete forget remove clear area zone share send source seen others field notes",
    when = function() return R.NpcStore ~= nil and R.NpcKnowledge ~= nil end,
    host = function() return P.Frame() end, hostHeight = 560,
})
