-- TwichUI Fishing: the catch list on the right of the screen (Stage 2)
-- What this session has caught, drawn straight over the world: no panel. The game's own item icons in a thin bronze rim,
-- ivory type with a soft shadow, a bronze rule between sections, and under it all a faint warm shade (media scrim, a
-- feathered oval with no edge), so the text reads over bright water and snow as well as at night.
--
-- From Stage 1's read-only interface only (API.Session and API.Provenance("session")), redrawn on its notifications:
--   header     "This Session" and how long it has lasted (a one-second ticker while shown)
--   catches    what the line brought up directly, each with its icon, name, "N caught" and "xN"; sorted by config list.sort
--              ("count", "recent", "name"), at most list.rows rows, then "+N more"
--   treasures  what came out of fishing containers (clam contents), and the containers themselves ("Clam x3, 1 unopened");
--              Provenance keeps them apart so nothing is counted twice
--   totals     catches, items and the catch rate (catches per cast)
--   value      only when a valuation is connected (Present.Value, Stage 3); otherwise there is no figure and no space for one.
--              Nothing is priced here.
-- A row whose item was just caught glows for a moment; a new row fades in from the right (none with reduced motion).
-- Rows, textures and animations are made once and reused. Hidden, it does nothing.

local R = TwichUI
local F = R.Fishing
local S = F.Store
local H = F.Hud
local L = {}
F.CatchList = L

L.WIDTH = 320
L.ROW_H = 48
L.SMALL_H = 28
L.MAX = 12          -- rows made at most (list.rows is 3..12)
L.TREASURES = 5     -- treasure rows at most

local frame, ui
local rows, small = {}, {}
local ticker
local flashes = {}     -- [itemID] = clock of its last catch (runtime only)
local seen = {}        -- [itemID] = true for rows already shown this session (a new one fades in)
L.builds = 0           -- full redraws (tests, diagnostics)

local function Text(parent, size, role, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    H.Font(fs, size, role)
    H.Color(fs, color or H.IVORY)
    return fs
end

local function Glow(row)
    local g = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    g:SetPoint("TOPLEFT", row, "TOPLEFT", -10, 4)
    g:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 10, -4)
    g:SetBlendMode("ADD")
    H.Texture(g, "rowglow", { 0.9, 0.7, 0.36, 0.25 })
    g:SetAlpha(0)
    local ag = g:CreateAnimationGroup()
    local up = ag:CreateAnimation("Alpha")
    up:SetFromAlpha(0); up:SetToAlpha(0.7); up:SetDuration(0.25); up:SetOrder(1)
    local down = ag:CreateAnimation("Alpha")
    down:SetFromAlpha(0.7); down:SetToAlpha(0); down:SetDuration(1.1); down:SetOrder(2)
    ag:SetScript("OnFinished", function() g:SetAlpha(0) end)
    row.glow, row.glowAnim = g, ag
end

local function Arrive(row)
    local ag = row:CreateAnimationGroup()
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.35)
    local t = ag:CreateAnimation("Translation")
    t:SetOffset(-12, 0); t:SetDuration(0.35)
    row.arrive, row.arriveMove = ag, t
end

local function MakeRow(i)
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(L.WIDTH, L.ROW_H)
    row.rim, row.icon = H.FramedIcon(row, 38)
    row.rim:SetPoint("LEFT", row, "LEFT", 0, 0)
    -- the quantity on the icon's corner, as on an item button
    row.badge = Text(row, 12, "strong", H.IVORY, "OVERLAY")
    row.badge:SetPoint("BOTTOMRIGHT", row.rim, "BOTTOMRIGHT", -4, 4)
    row.badge:SetJustifyH("RIGHT")
    row.name = Text(row, 17, "strong")
    row.name:SetPoint("TOPLEFT", row.rim, "TOPRIGHT", 10, -2)
    row.name:SetPoint("RIGHT", row, "RIGHT", -62, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.sub = Text(row, 14, "body", H.AMBERTEXT)
    row.sub:SetPoint("BOTTOMLEFT", row.rim, "BOTTOMRIGHT", 10, 3)
    row.count = Text(row, 23, "serif")
    row.count:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.count:SetJustifyH("RIGHT")
    -- the fine bronze rule under the row (the texture pack's rule, faint)
    row.rule = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.rule:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, 6)
    row.rule:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", 0, 6)
    row.rule:SetHeight(12)
    H.Texture(row.rule, "rule", { 0.6, 0.45, 0.26, 0.4 })
    row.rule:SetAlpha(0.5)
    Glow(row)
    Arrive(row)
    row:Hide()
    rows[i] = row
    return row
end

local function MakeSmall(i)
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(L.WIDTH, L.SMALL_H)
    row.rim, row.icon = H.FramedIcon(row, 24)
    row.rim:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.name = Text(row, 15, "body")
    row.name:SetPoint("LEFT", row.rim, "RIGHT", 12, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    Glow(row)
    row:Hide()
    small[i] = row
    return row
end

local function Build()
    if frame then return frame end
    local f, u
    f = CreateFrame("Frame", "TwichUIFishingCatchList", UIParent)
    f:SetSize(L.WIDTH, 200)
    f:SetFrameStrata("LOW")
    f:EnableMouse(false)
    f:Hide()
    u = {}
    -- the shade: a feathered oval larger than the list, darkest under the text, no edge anywhere
    u.scrim = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    u.scrim:SetPoint("TOPLEFT", f, "TOPLEFT", -110, 70)
    u.scrim:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 110, -60)
    H.Texture(u.scrim, "scrim", { 0.06, 0.04, 0.03, 0.35 })
    u.scrim:SetAlpha(H.SHADE)
    u.title = Text(f, 23, "serif")
    u.title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    u.title:SetText("Today's Catch")
    u.since = Text(f, 14, "body", H.SOFT)
    u.since:SetPoint("TOPLEFT", u.title, "BOTTOMLEFT", 0, -3)
    u.valueLabel = Text(f, 13, "body", H.SOFT)
    u.valueLabel:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -2)
    u.valueLabel:SetText("Estimated Value")
    u.value = Text(f, 23, "serif", H.GOLD)
    u.value:SetPoint("TOPRIGHT", u.valueLabel, "BOTTOMRIGHT", 0, -2)
    -- the fine bronze rule with its small centre ornament (the pack's divider_upper), as under the mockup's heading
    u.rule = f:CreateTexture(nil, "ARTWORK")
    u.rule:SetSize(L.WIDTH, L.WIDTH * 30 / 256)
    H.Texture(u.rule, "rule", { 0.7, 0.52, 0.3, 0.5 })
    u.more = Text(f, 12, "body", H.MUTED)
    u.treasures = Text(f, 18, "serif")
    u.treasures:SetText("Other Treasures")
    u.rule2 = f:CreateTexture(nil, "ARTWORK")
    u.rule2:SetSize(L.WIDTH, L.WIDTH * 30 / 256)
    H.Texture(u.rule2, "rule", { 0.7, 0.52, 0.3, 0.5 })
    u.totals = Text(f, 13, "strong", H.SOFT)
    u.empty = Text(f, 14, "body", H.SOFT)
    u.empty:SetText("Nothing caught yet this session.")
    H.Movable(f, "list", "RIGHT")
    -- kept only once every part exists: a build that fails part-way leaves nothing half-made in use
    frame, ui = f, u
    return frame
end

---------------------------------------------------------------------------
-- The data, from Stage 1's read-only interface
---------------------------------------------------------------------------
local function SortKey(mode)
    if mode == "recent" then return function(a, b) if a.l ~= b.l then return a.l > b.l end return a.id < b.id end end
    if mode == "name" then
        return function(a, b)
            local an, bn = a.name or "", b.name or ""
            if an ~= bn then return an < bn end
            return a.id < b.id
        end
    end
    return function(a, b)
        if a.q ~= b.q then return a.q > b.q end
        if a.l ~= b.l then return a.l > b.l end
        return a.id < b.id
    end
end

-- The rows to draw: { catches = { {id, q, c, l, name, icon, quality} }, treasures = { {id, q, label} }, session = copy }
function L.Model()
    if L.preview then return L.PreviewModel() end
    local API = F.API
    local s = API.Session()
    if not s then return nil end
    local prov = API.Provenance("session") or { direct = {}, containers = {}, contents = {} }
    local catches = {}
    for id, q in pairs(prov.direct) do
        local e = s.species[id] or {}
        local name, icon, quality = H.Item(id)
        catches[#catches + 1] = { id = id, q = q, c = e.c or q, l = e.l or 0, name = name, icon = icon, quality = quality }
    end
    table.sort(catches, SortKey(S.Get("list.sort")))
    local treasures = {}
    for id, q in pairs(prov.contents) do
        local name, icon, quality = H.Item(id)
        treasures[#treasures + 1] = { id = id, q = q, name = name, icon = icon, quality = quality, kind = "content" }
    end
    for id, e in pairs(prov.containers) do
        local name, icon, quality = H.Item(id)
        treasures[#treasures + 1] = { id = id, q = e.caught, unopened = e.unopened, name = name, icon = icon, quality = quality,
            kind = "container" }
    end
    table.sort(treasures, function(a, b)
        if a.kind ~= b.kind then return a.kind == "content" end
        if a.q ~= b.q then return a.q > b.q end
        return a.id < b.id
    end)
    return { catches = catches, treasures = treasures, session = s }
end

-- Move mode only: sample rows so the list can be placed (never shown as a record).
function L.PreviewModel()
    local q = H.QUESTION
    return {
        catches = { { id = 1, q = 24, c = 24, l = 3, name = "First catch", icon = q }, { id = 2, q = 18, c = 18, l = 2, name = "Second catch", icon = q },
            { id = 3, q = 12, c = 12, l = 1, name = "Third catch", icon = q } },
        treasures = { { id = 4, q = 1, name = "A treasure", icon = q, kind = "content" } },
        session = { start = F.Now() - 2537, catches = 56, items = 60, casts = 70 },
    }
end

local function Label(e)
    local name = e.name or ("Item " .. e.id)
    -- the game's own quality color for rare and better only: common and uncommon stay ivory, as the rest of the list
    if e.quality and e.quality >= 3 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality] then
        local c = ITEM_QUALITY_COLORS[e.quality]
        if c.hex then return c.hex .. name .. "|r" end
    end
    return name
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function Since(s)
    if L.preview then return "Fishing for 42 minutes" end
    local sec = F.Session.Elapsed() or 0
    if sec < 60 then return "Fishing for under a minute" end
    if sec < 3600 then local m = math.floor(sec / 60) return ("Fishing for %d minute%s"):format(m, m == 1 and "" or "s") end
    return "Fishing for " .. H.Duration(sec)
end

local function Flash(row, id, isNew)
    local at = flashes[id]
    if at and F.Clock() - at < 1.5 then
        row.glowAnim:Stop()
        row.glowAnim:Play()
        flashes[id] = nil
    end
    if isNew and row.arrive and L.Motion() then
        row.arrive:Stop()
        row.arrive:Play()
    end
end

function L.Motion()
    if S.Get("present.motion") == false then return false end
    return not (R.Enabled and R:Enabled("arrivalReducedMotion"))
end

function L.Refresh()
    if not (frame and frame:IsShown()) then return end
    local pt = R.Perf.on and R.Perf.Start("fishing.list")
    L.builds = L.builds + 1
    local m = L.Model()
    for _, r in ipairs(rows) do r:Hide() end
    for _, r in ipairs(small) do r:Hide() end
    ui.more:Hide(); ui.treasures:Hide(); ui.rule2:Hide(); ui.empty:Hide()
    local P = F.Present
    local value = not L.preview and P and P.Value and P.Value("session") or nil
    -- the value area keeps its place: a connected valuation's figure, or plainly "not available" (list.value "hide" drops it)
    local has = value ~= nil and value.text ~= nil
    local showArea = has or S.Get("list.value") ~= "hide"
    ui.valueLabel:SetShown(showArea)
    ui.value:SetShown(showArea)
    if has then
        ui.value:SetText(value.text); H.Font(ui.value, 23, "serif"); H.Color(ui.value, H.GOLD)
    else
        ui.value:SetText("Not available yet"); H.Font(ui.value, 13, "body"); H.Color(ui.value, H.MUTED)
    end
    if not m then
        ui.since:SetText("No session in progress")
        ui.rule:ClearAllPoints(); ui.rule:SetPoint("TOPLEFT", ui.since, "BOTTOMLEFT", 0, -4)
        ui.totals:SetText("")
        frame:SetHeight(60)
        if pt then R.Perf.Stop(pt) end
        return
    end
    ui.since:SetText(Since(m.session))
    -- "Today's Catch" (the mockup's words) when the session began today, else what it is
    local today = not m.session.start or (date and date("%Y%m%d", m.session.start) == date("%Y%m%d", F.Now()))
    ui.title:SetText(today and "Today's Catch" or "This Session's Catch")
    ui.rule:ClearAllPoints()
    ui.rule:SetPoint("TOPLEFT", ui.since, "BOTTOMLEFT", 0, -4)
    local y = -(23 + 3 + 16 + 4 + ui.rule:GetHeight() + 2)
    local limit = math.floor(S.Get("list.rows") or 6)
    local shown = math.min(#m.catches, limit, L.MAX)
    for i = 1, shown do
        local e = m.catches[i]
        local row = rows[i] or MakeRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
        row.icon:SetTexture(e.icon or H.QUESTION)
        row.name:SetText(Label(e))
        row.sub:SetText(e.q .. " caught")
        local per = value and value.items and value.items[e.id]
        if per then row.sub:SetText(row.sub:GetText() .. " \226\128\148 " .. per) end
        row.count:SetText("\195\151" .. e.q)
        row.badge:SetText(e.q > 1 and e.q or "")
        row.rule:SetShown(i < shown)
        row:Show()
        Flash(row, e.id, not seen[e.id] and not L.preview)
        seen[e.id] = true
        y = y - L.ROW_H
    end
    if #m.catches == 0 then
        ui.empty:ClearAllPoints(); ui.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y - 4); ui.empty:Show()
        y = y - 24
    elseif #m.catches > shown then
        local n = #m.catches - shown
        ui.more:ClearAllPoints(); ui.more:SetPoint("TOPRIGHT", frame, "TOPLEFT", L.WIDTH, y - 2)
        ui.more:SetText(("+%d more kind%s"):format(n, n == 1 and "" or "s")); ui.more:Show()
        y = y - 18
    end
    if #m.treasures > 0 then
        y = y - 8
        ui.treasures:ClearAllPoints(); ui.treasures:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y); ui.treasures:Show()
        y = y - 22
        ui.rule2:ClearAllPoints(); ui.rule2:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y); ui.rule2:Show()
        y = y - ui.rule2:GetHeight()
        for i = 1, math.min(#m.treasures, L.TREASURES) do
            local e = m.treasures[i]
            local row = small[i] or MakeSmall(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
            row.icon:SetTexture(e.icon or H.QUESTION)
            local text = Label(e) .. "  |cffe0bd85\195\151" .. e.q .. "|r"
            if e.kind == "container" and (e.unopened or 0) > 0 then text = text .. "  |cffa89a84(" .. e.unopened .. " unopened)|r" end
            local per = value and value.items and value.items[e.id]
            if per then text = text .. "  |cffa89a84\226\128\148 " .. per .. "|r" end
            row.name:SetText(text)
            row:Show()
            Flash(row, e.id, false)
            y = y - L.SMALL_H
        end
        if #m.treasures > L.TREASURES then
            local n = #m.treasures - L.TREASURES
            ui.more:ClearAllPoints(); ui.more:SetPoint("TOPRIGHT", frame, "TOPLEFT", L.WIDTH, y - 2)
            ui.more:SetText(("+%d more"):format(n)); ui.more:Show()
            y = y - 18
        end
    end
    local s = m.session
    local parts = { (s.catches or 0) == 1 and "1 catch" or ((s.catches or 0) .. " catches") }
    if (s.items or 0) ~= (s.catches or 0) then parts[#parts + 1] = (s.items or 0) .. " items" end
    if (s.casts or 0) > 0 then parts[#parts + 1] = ("%d%% catch rate"):format(math.min(100, math.floor(100 * (s.catches or 0) / s.casts + 0.5))) end
    ui.totals:ClearAllPoints()
    ui.totals:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y - 8)
    ui.totals:SetText(table.concat(parts, "  \194\183  "))
    frame:SetHeight(-(y - 8 - 16))
    if pt then R.Perf.Stop(pt) end
end

local function Tick()
    if frame and frame:IsShown() and ui then ui.since:SetText(Since()) end
end

---------------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------------
F.Subscribe("ITEM", function(_, itemID)
    flashes[itemID] = F.Clock()
    L.Refresh()
end)
for _, e in ipairs({ "CONTAINER", "QUEUE", "CATCH" }) do F.Subscribe(e, function() L.Refresh() end) end
F.Subscribe("SESSION_START", function() seen, flashes = {}, {}; L.Refresh() end)
F.Subscribe("SESSION_END", function() L.Refresh() end)
F.Subscribe("CONFIG", function(_, path)
    if type(path) == "string" and (path == "list.sort" or path == "list.rows") then L.Refresh() end
end)
H.OnItem(function() L.Refresh() end)

---------------------------------------------------------------------------
-- Shown and hidden by Present.lua
---------------------------------------------------------------------------
function L.Show()
    Build()
    H.Place(frame, "list", "RIGHT")
    frame:Show()
    -- rows already caught this session don't arrive again when the list comes back
    local s = F.API.Session()
    if s then for id in pairs(s.species) do seen[id] = true end end
    L.Refresh()
    if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(1, Tick) end
end

function L.Hide()
    if ticker then ticker:Cancel(); ticker = nil end
    if frame then frame:Hide() end
end

function L.Shown() return frame ~= nil and frame:IsShown() end
function L.Frame() return frame, ui, rows, small end

function L.Preview(on)
    L.preview = on and true or nil
    Build()
    H.SetUnlocked(frame, on)
    if on then frame:Show() end
    L.Refresh()
end

function L.Relayout() if frame then H.Place(frame, "list", "RIGHT") end end
