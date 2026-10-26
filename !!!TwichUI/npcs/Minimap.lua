-- TwichUI: Vendors and trainers on the minimap
-- The same small square markers as on the world map, for the NPCs within range of you, when "Also show on the minimap"
-- is chosen (npcs/Prefs.lua's minimap; off by default) and the Vendors and trainers switch is on.
--   Which: the world map's own choice (npcs/Map.lua's ShownKind: the kinds you chose, class trainers, reports), and only
--     NPCs noted on the minimap's map or one of its parents. At most MAX_SHOWN at a time. Names are in the tooltip; a
--     click opens the same actions as on the world map. Nothing points at an NPC that is out of range.
--   Where: as the party pins are placed (pins/Minimap.lua): the minimap's map, view radius, width and rotation come from
--     its Gather, the player's place on an NPC's map from C_Map.GetPlayerMapPosition and that map's size from
--     C_Map.GetMapWorldSize. A marker is moved only when its place changed by half a pixel or more.
--   When it works: one throttled updater (as the pins' one: 25 times a second while the minimap rotates, 10 otherwise),
--     present only while the feature is on, the minimap is shown and an NPC could be on it. The list of NPCs for the
--     minimap's map is made again only when that map, the list or a choice changes.

local R = TwichUI
local Perf = R.Perf
local NK, NS, NP, NMAP = R.NpcKinds, R.NpcStore, R.NpcPrefs, R.NpcMap
local MM = {}
R.NpcMinimap = MM

local SIZE = 14               -- a marker's side in pixels before the size choice
local MAX_SHOWN = 40
local FAST, SLOW = 0.04, 0.10
local INSET = 3               -- a marker whose middle is nearer the rim than this isn't drawn
local MAX_PARENTS = 8
local REPORT_ALPHA = 0.6

local driver
local active = false
local near = {}               -- { entry, kind } for the NPCs on the minimap's map and its parents
local nearFor                 -- the minimap map `near` was made for (nil: stale)
local relate = {}
local slots = {}
local wait = 0
local view = {}
local sizeW, sizeH = {}, {}
local tickX, tickY = {}, {}
local stats = { ticks = 0, moves = 0, rebuilds = 0, shown = 0, errors = 0, reported = false, last = "none" }

local function Enabled()
    return Minimap ~= nil and R.PinsMinimap ~= nil and R:Enabled("npcMap") and NP.Get("minimap") == true
end

local function Readable(v)
    if type(v) ~= "number" then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    if canaccessvalue and not canaccessvalue(v) then return nil end
    if v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

---------------------------------------------------------------------------
-- The markers
---------------------------------------------------------------------------
local function Size() return SIZE * NP.Get("iconSize") / 100 end

local function NewSlot()
    local b = CreateFrame("Button", nil, Minimap)
    b:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetBlendMode("ADD")
    b.hl:SetAlpha(0.3)
    b:SetScript("OnEnter", function(self) NMAP.Tooltip(self) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if not self.entry then return end
        GameTooltip:Hide()
        NMAP.Menu(self.entry, self)
    end)
    b:Hide()
    return b
end

local function Dress(b, e, kind)
    b.entry = e
    if b.kind ~= kind then
        b.kind = kind
        b.icon:SetTexture(kind.icon)
        b.hl:SetTexture(kind.icon)
    end
    local reported = not e.own
    if b.reported ~= reported then
        b.reported = reported
        b.icon:SetDesaturated(reported)
        b:SetAlpha(reported and REPORT_ALPHA or 1)
    end
    local size = Size()
    if b.size ~= size then
        b.size = size
        b:SetSize(size, size)
    end
end

local function HideSlot(b)
    if b.on then
        b.on = false
        b:Hide()
        if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
    end
    b.px, b.py = nil, nil
end

local function HideAll()
    for _, b in ipairs(slots) do HideSlot(b) end
    stats.shown = 0
end

---------------------------------------------------------------------------
-- Which NPCs could be here
---------------------------------------------------------------------------
-- The minimap's map and its parents, and the list of the NPCs on them. Made again only when the map changes or
-- something that decides who shows does (MM.Rebuild).
local function Relate(map)
    wipe(relate)
    local id = map
    for _ = 1, MAX_PARENTS do
        if not id or id == 0 then break end
        relate[id] = true
        local ok, info = pcall(C_Map.GetMapInfo, id)
        if not (ok and type(info) == "table") then break end
        id = info.parentMapID
    end
end

local function Collect(map)
    nearFor = map
    wipe(near)
    Relate(map)
    for _, e in ipairs(NS.Entries()) do
        if relate[e.m] then
            local kind = NMAP.ShownKind(e)
            if kind then near[#near + 1] = { e = e, kind = kind } end
        end
    end
    for _, b in ipairs(slots) do b.entry = nil; HideSlot(b) end
end

local function WorldSize(map)
    local w = sizeW[map]
    if w == nil then
        local ok, width, height = pcall(C_Map.GetMapWorldSize, map)
        width, height = Readable(width), Readable(height)
        if ok and width and height and width > 0 and height > 0 then
            sizeW[map], sizeH[map] = width, height
        else
            sizeW[map], sizeH[map] = false, false
        end
        w = sizeW[map]
    end
    if w then return w, sizeH[map] end
end

local function PlayerOn(map)
    local x = tickX[map]
    if x == nil then
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
        if ok and type(pos) == "table" and pos.GetXY then
            local px, py = pos:GetXY()
            px, py = Readable(px), Readable(py)
            if px and py then
                tickX[map], tickY[map] = px, py
                return px, py
            end
        end
        tickX[map], tickY[map] = false, false
        return nil
    end
    if x then return x, tickY[map] end
end

---------------------------------------------------------------------------
-- The updater
---------------------------------------------------------------------------
local Update

local function Place(b, x, y)
    x = math.floor(x * 2 + 0.5) / 2
    y = math.floor(y * 2 + 0.5) / 2
    if x ~= b.px or y ~= b.py then
        b.px, b.py = x, y
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", x, y)
        stats.moves = stats.moves + 1
    end
    if not b.on then
        b.on = true
        b:Show()
    end
end

local function Step()
    local reason = R.PinsMinimap.Gather(view)
    if reason then
        HideAll()
        stats.last = reason
        return
    end
    if nearFor ~= view.map then Collect(view.map) end
    wipe(tickX); wipe(tickY)
    local halfWidth, radius, facing, rotating = view.halfWidth, view.radius, view.facing, view.rotating
    local perYard = halfWidth / radius
    local limit = halfWidth - INSET
    local sin, cos = math.sin(facing), math.cos(facing)
    local shown = 0
    for i = 1, #near do
        if shown >= MAX_SHOWN then break end
        local e, kind = near[i].e, near[i].kind
        local width, height = WorldSize(e.m)
        local ux, uy = PlayerOn(e.m)
        if width and ux then
            local east = (e.x / NS.COORD - ux) * width
            local north = -(e.y / NS.COORD - uy) * height
            local sx, sy = east, north
            if rotating then
                sx = east * cos + north * sin
                sy = north * cos - east * sin
            end
            local px, py = sx * perYard, sy * perYard
            if px * px + py * py <= limit * limit then
                shown = shown + 1
                local b = slots[shown]
                if not b then
                    b = NewSlot()
                    slots[shown] = b
                end
                if b.entry ~= e then b.px, b.py = nil, nil end
                Dress(b, e, kind)
                Place(b, px, py)
            end
        end
    end
    for i = shown + 1, #slots do
        slots[i].entry = nil
        HideSlot(slots[i])
    end
    stats.shown = shown
    stats.last = "ok"
end

function Update(_, seconds)
    wait = wait - (seconds or 0)
    if wait > 0 then return end
    wait = view.rotating and FAST or SLOW
    stats.ticks = stats.ticks + 1
    if not Minimap:IsVisible() then
        stats.last = "minimap-hidden"
        return
    end
    local ok, err = Perf.Call("npcs.minimap.tick", pcall, Step)
    if not ok then
        stats.errors = stats.errors + 1
        stats.last = "error"
        HideAll()
        if not stats.reported then
            stats.reported = true
            R.Fault("npc minimap", err)   -- once; later ones are only counted
        end
    end
end
MM.Update = Update

---------------------------------------------------------------------------
-- On and off
---------------------------------------------------------------------------
-- Run when the list, a choice or the switch changes.
function MM.Refresh()
    stats.rebuilds = stats.rebuilds + 1
    local want = Enabled()
    nearFor = nil
    wipe(near)
    if want then
        if not driver then driver = CreateFrame("Frame") end
        active = true
        driver:SetScript("OnUpdate", Update)
    else
        active = false
        for _, b in ipairs(slots) do b.entry = nil end
        HideAll()
        if driver then driver:SetScript("OnUpdate", nil) end
    end
    wait = 0
end

NS.OnChange(function() if active then MM.Refresh() end end)
NP.Subscribe(function() if active or Enabled() then MM.Refresh() end end)
R:On("PLAYER_LOGIN", MM.Refresh)

-- For tests and diagnostics: where each marker is now. No names or places beyond what a test asks for.
function MM.State()
    local out = {}
    for i, b in ipairs(slots) do
        if b.on then out[#out + 1] = { id = b.entry and b.entry.id, x = b.px, y = b.py, size = b.size } end
    end
    return out
end
function MM.Active() return active end
function MM.Slot(i) return slots[i] end
