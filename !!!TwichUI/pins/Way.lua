-- TwichUI: Party pins, waypoint commands
-- /twichway (and /way, when no other addon has it) turns a TomTom/Wowhead style waypoint into a local pin,
-- made by the same Pins.AddLocal that the map click and the pin editor use, so it is saved, drawn, listed
-- and limited exactly like a pin placed by hand:
--   /twichway <x> <y> [name]                  your current map
--   /twichway <zone name> <x> <y> [name]      a zone, continent or dungeon by its full name
--   /twichway #<mapID> <x> <y> [name]         a map by number
--   /twichway paste                           a small window for several lines at once
-- Coordinates are percentages, 0 to 100. Nothing here is sent, no navigation is started and the world
-- map is neither opened nor moved. Pasted text is only ever read as waypoints: it is never run as Lua,
-- as a macro or as another slash command.
--
-- /way belongs to whoever registered it first. The game moves a command into hash_SlashCmdList the first
-- time chat parses a command and the last addon imported wins, so TwichUI looks at both tables, takes
-- /way only when the feature is on and nobody else has it, and never replaces another addon's handler.
-- One opt-in exception (Pins and Pings options, "Also make a pin from /way"): when another addon (WaypointUI,
-- TomTom) has /way, TwichUI runs after that addon's handler, the way WaypointUI itself follows TomTom's,
-- and makes a pin from the same text. The other handler is called first, unchanged and with the same
-- arguments; the pin is skipped for anything that isn't a waypoint (reset, paste, list...) and nothing
-- is said about what the other addon would have said.

local R = TwichUI
local PN = R.Pins
local PL = R.PinsLook
local S = R.ChronicleStyle
local PW = {}
R.PinsWay = PW

local KEY = "TWICHUIWAY"
local MAX_LINES = 250          -- non-blank lines read from one paste
local MAX_LINE_BYTES = 240
local MAX_TEXT_BYTES = 30000
local MAX_PARENTS = 12
local SHOWN_ERRORS = 8

local lower = strlower or string.lower
local stats = { commands = 0, made = 0, failed = 0, pastes = 0, also = 0 }

---------------------------------------------------------------------------
-- Reading a waypoint: pure text handling, no game calls
---------------------------------------------------------------------------
-- A word that is meant as a number (digits and . , + - only), valid or not.
local function Candidate(w)
    return w:find("%d") ~= nil and w:match("^[%d%.,%+%-]+$") ~= nil
end

-- The number a word spells, or nil: 52, 52.3, .5, 52. and a sign.
local function Strict(w)
    if type(w) ~= "string" or #w > 12 then return nil end
    if w:match("^[%+%-]?%d+%.?%d*$") or w:match("^[%+%-]?%.%d+$") then return tonumber(w) end
end

-- text: what follows the command word. Returns { x, y, map?, zone?, name? } (x and y in 0..100), or nil,
-- a reason code and a detail. Only the first two numbers are coordinates; anything after them is the name.
function PW.Parse(text)
    if type(text) ~= "string" then return nil, "empty" end
    local words = {}
    for s, w, e in text:gmatch("()(%S+)()") do words[#words + 1] = { w, s, e } end
    if #words == 0 then return nil, "empty" end

    local i, map = 1, nil
    if words[1][1]:sub(1, 1) == "#" then
        local id = words[1][1]:match("^#(%d+)$")
        if not id or #id > 10 then return nil, "bad-map-token", words[1][1] end
        map, i = tonumber(id), 2
    end

    local j = i
    while j <= #words and not Candidate(words[j][1]) do j = j + 1 end
    if j > #words then return nil, "missing-coords" end
    if map and j > i then return nil, "map-and-zone" end
    local zone
    if j > i then
        local parts = {}
        for k = i, j - 1 do parts[#parts + 1] = words[k][1] end
        zone = table.concat(parts, " ")
    end

    -- x, then y: "52.3 40.7", "52.3, 40.7", "52.3,40.7" and "52.3 , 40.7"
    local xs, ys, last = words[j][1], nil, j
    local a, b = xs:match("^([^,]*),([^,]*)$")
    if a then
        -- "52,3 40,7": decimal commas, not an x,y pair followed by a name. Never guessed either way.
        local after = words[j + 1] and words[j + 1][1]
        if b ~= "" and after and after:match("^%d+,%d+$") then return nil, "decimal-comma" end
        xs = a
        if b ~= "" then ys = b end
    elseif xs:find(",", 1, true) then
        return nil, "bad-number", xs
    end
    if not ys then
        local k = j + 1
        if words[k] and words[k][1] == "," then k = k + 1 end
        local w = words[k] and words[k][1]
        w = w and w:gsub("^,+", ""):gsub(",+$", "")
        if not (w and Candidate(w)) then return nil, "missing-y" end
        ys, last = w, k
    end

    local x, y = Strict(xs), Strict(ys)
    if not x then return nil, "bad-number", xs end
    if not y then return nil, "bad-number", ys end
    if x < 0 or x > 100 then return nil, "range", xs end
    if y < 0 or y > 100 then return nil, "range", ys end

    local name = text:sub(words[last][3]):gsub("^[%s,]+", ""):gsub("%s+$", "")
    return { x = x, y = y, map = map, zone = zone, name = name ~= "" and name or nil }
end

---------------------------------------------------------------------------
-- Which map
---------------------------------------------------------------------------
-- The player's own map, never the one open in the world map window.
local function CurrentMap()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or (issecretvalue and issecretvalue(map)) or type(map) ~= "number" then return nil end
    return map
end

-- Zone names, found from the game's own map tree the first time one is asked for and kept: continents,
-- zones and dungeons by their full name, lower case. Micro and orphan maps are reached by #mapID. A tree
-- is read once per top map (a new one when you travel somewhere not yet read), never per command.
local names = {}             -- [lowercase name] = { { id, parent }, ... }
local rootsDone, startsSeen = {}, {}
local primed = false

local function Norm(s) return ((lower(s):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))) end

local function Index(info)
    if type(info) ~= "table" then return end
    local id, name = info.mapID, info.name
    if (issecretvalue and (issecretvalue(id) or issecretvalue(name))) or type(id) ~= "number"
        or type(name) ~= "string" or name == "" then return end
    local T = Enum and Enum.UIMapType
    if T and (info.mapType == T.Micro or info.mapType == T.Orphan) then return end
    local key = Norm(name)
    local list = names[key]
    if not list then
        list = {}
        names[key] = list
    end
    for _, e in ipairs(list) do
        if e.id == id then return end
    end
    list[#list + 1] = { id = id, parent = info.parentMapID }
end

local function RootOf(map)
    local id = map
    for _ = 1, MAX_PARENTS do
        local ok, info = pcall(C_Map.GetMapInfo, id)
        if not ok or type(info) ~= "table" then break end
        local parent = info.parentMapID
        if type(parent) ~= "number" or parent == 0 then break end
        id = parent
    end
    return id
end

-- Reads the tree the map belongs to, once. Returns whether anything new was read.
local function ScanFrom(map)
    if type(map) ~= "number" or startsSeen[map] or not (C_Map and C_Map.GetMapInfo and C_Map.GetMapChildrenInfo) then return false end
    startsSeen[map] = true
    local root = RootOf(map)
    if rootsDone[root] then return false end
    rootsDone[root] = true
    local _, info = pcall(C_Map.GetMapInfo, root)
    Index(info)
    local ok, kids = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
    if not ok or type(kids) ~= "table" then
        rootsDone[root], startsSeen[map] = nil, nil   -- not ready: try again next time
        return false
    end
    for _, kid in ipairs(kids) do Index(kid) end
    return true
end

local function Esc(s) return (tostring(s):gsub("|", "||")) end

local function Candidates(list)
    local out = {}
    for i = 1, math.min(#list, 5) do
        local e = list[i]
        local where = e.parent and e.parent ~= 0 and (", in " .. PN.MapName(e.parent)) or ""
        out[#out + 1] = ("%s (#%d%s)"):format(PN.MapName(e.id), e.id, where)
    end
    if #list > 5 then out[#out + 1] = ("and %d more"):format(#list - 5) end
    return table.concat(out, "; ")
end

-- A map id for a full zone name, or nil, a reason code and a detail. An ambiguous name is never guessed.
function PW.FindZone(name)
    local key = Norm(name)
    local current = CurrentMap()
    if not primed then
        primed = true
        ScanFrom(current)
        local ok, fallback = pcall(C_Map.GetFallbackWorldMapID)
        ScanFrom(ok and fallback or nil)
    end
    local list = names[key]
    if not list and ScanFrom(current) then list = names[key] end
    if not list then return nil, "unknown-zone", name end
    if #list > 1 then return nil, "ambiguous-zone", Candidates(list) end
    if not PN.ValidMap(list[1].id) then return nil, "unknown-zone", name end
    return list[1].id
end

-- ctx keeps the player's map for one command or one paste.
local function Resolve(entry, ctx)
    if entry.map then
        if PN.ValidMap(entry.map) then return entry.map end
        return nil, "unknown-map", entry.map
    end
    if entry.zone then return PW.FindZone(entry.zone) end
    if ctx.current == nil then ctx.current = CurrentMap() or false end
    if not ctx.current then return nil, "no-current-map" end
    if not PN.ValidMap(ctx.current) then return nil, "unknown-map", ctx.current end
    return ctx.current
end

-- A pin from a parsed waypoint, through the same call the map click uses. Percentages become the pin
-- system's 0..10000 steps here, once. Returns the pin, or nil, a reason code and a detail.
local function Place(entry, ctx)
    local map, code, detail = Resolve(entry, ctx)
    if not map then return nil, code, detail end
    local x, y = PN.Quantize(entry.x / 100), PN.Quantize(entry.y / 100)
    if not (x and y) then return nil, "range" end
    local pin, why = PN.AddLocal({ map = map, x = x, y = y, name = entry.name })
    if not pin then return nil, why end
    return pin
end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
local USAGE = {
    "/twichway <x> <y> [name]",
    "/twichway <zone name> <x> <y> [name]",
    "/twichway #<mapID> <x> <y> [name]",
    "/twichway paste",
}

local function Message(code, detail)
    if code == "missing-coords" or code == "empty" then return "Needs two coordinates, like 52.3 40.7." end
    if code == "missing-y" then return "Needs two coordinates; only one number was given." end
    if code == "bad-number" then return ("'%s' isn't a valid number."):format(Esc(detail)) end
    if code == "decimal-comma" then return "Use a point for decimals, like 52.3 40.7 (a comma only separates the two numbers)." end
    if code == "range" then return ("%s is outside 0 to 100."):format(Esc(detail)) end
    if code == "bad-map-token" then return ("'%s' isn't a map number. Use #<mapID>, like #1453."):format(Esc(detail)) end
    if code == "map-and-zone" then return "Give a zone name or a #mapID, not both." end
    if code == "not-waypoint" then return "Only /way and /twichway lines are read here." end
    if code == "too-long" then return "That line is too long to be a waypoint." end
    if code == "no-current-map" then return "Couldn't tell which map you are on. Name a zone, or use #<mapID>." end
    if code == "unknown-map" then return ("The game has no map #%s."):format(Esc(detail)) end
    if code == "unknown-zone" then
        return ("No zone called '%s'. Use its full name, or #<mapID>."):format(Esc(detail))
    end
    if code == "ambiguous-zone" then
        return ("More than one map has that name: %s. Use /twichway #<mapID> <x> <y> to pick one."):format(detail)
    end
    return PN.Reason(code)   -- local-limit and the like
end
PW.Message = Message

local function Grey(text) print(("  %s%s|r"):format(R.GREY or "", text)) end

local function ShowUsage()
    for _, line in ipairs(USAGE) do Grey(line) end
    local way = PW.WayState()
    if way ~= "ours" then
        Grey("/way is used by another addon, so TwichUI answers to /twichway.")
    end
end

---------------------------------------------------------------------------
-- One command
---------------------------------------------------------------------------
local function Off()
    R.Print("Map pins are turned off. Turn them on in /tui options (Pins and Pings).")
end

local function Sentence(pin, entry)
    local note = entry.name and #entry.name > PN.NAME_MAX and " (the name was shortened)" or ""
    return ("Pin made: %s, %s%s."):format(Esc(pin.name), PN.Describe(pin), note)
end

function PW.Run(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local word = lower(msg)
    if word == "" or word == "help" or word == "?" then
        R.Print("Make a pin from a waypoint:")
        ShowUsage()
        return
    end
    if not R:Enabled("partyPins") then Off() return end
    if word == "paste" then PW.OpenPaste() return end
    stats.commands = stats.commands + 1
    local entry, code, detail = PW.Parse(msg)
    if not entry then
        stats.failed = stats.failed + 1
        R.Print("%s", Message(code, detail))
        ShowUsage()
        return
    end
    local pin
    PN.Batch(function()
        pin, code, detail = Place(entry, {})
        if pin then PN.Select("local:" .. pin.id) end   -- the same pick the editor makes: its name shows on the map
    end)
    if pin then
        stats.made = stats.made + 1
        R.Print("%s", Sentence(pin, entry))
    else
        stats.failed = stats.failed + 1
        R.Print("%s", Message(code, detail))
    end
end

---------------------------------------------------------------------------
-- Several lines
---------------------------------------------------------------------------
-- Makes a pin for each waypoint line, in order, each checked on its own; one failing never stops the
-- others. The pins are made inside one batch, so the map and window refresh once.
-- Returns { made = n, failed = n, skipped = n, errors = { { line, text } }, made = { [line] = true } }.
function PW.ImportText(text)
    local out = { count = 0, failed = 0, skipped = 0, errors = {}, done = {} }
    if type(text) ~= "string" then return out end
    if #text > MAX_TEXT_BYTES then text = text:sub(1, MAX_TEXT_BYTES) end
    local ctx = {}
    local read = 0
    local function Fail(n, code, detail)
        out.failed = out.failed + 1
        out.errors[#out.errors + 1] = { line = n, text = Message(code, detail) }
    end
    PN.Batch(function()
        local n, pos, size = 0, 1, #text
        local stopped = false
        while pos <= size + 1 do
            n = n + 1
            local nl = text:find("\n", pos, true)
            local line = text:sub(pos, (nl or size + 1) - 1):gsub("\r", ""):match("^%s*(.-)%s*$")
            pos = (nl or size + 1) + 1
            if line ~= "" then
                if stopped then
                    out.skipped = out.skipped + 1
                else
                    read = read + 1
                    if read > MAX_LINES then
                        stopped = true
                        out.skipped = out.skipped + 1
                        out.errors[#out.errors + 1] = { line = n, text = ("Stopped after %d lines."):format(MAX_LINES) }
                    elseif #line > MAX_LINE_BYTES then
                        Fail(n, "too-long")
                    else
                        local rest = line
                        local ok = true
                        if line:sub(1, 1) == "/" then
                            local cmd, tail = line:match("^(/%S+)%s*(.*)$")
                            cmd = lower(cmd or "")
                            if cmd == "/way" or cmd == "/twichway" then rest = tail else ok = false end
                        end
                        if not ok then
                            Fail(n, "not-waypoint")
                        else
                            local entry, code, detail = PW.Parse(rest)
                            local pin
                            if entry then pin, code, detail = Place(entry, ctx) end
                            if pin then
                                out.count = out.count + 1
                                out.done[n] = true
                            else
                                Fail(n, code, detail)
                                if code == "local-limit" then stopped = true end   -- every line after it would say the same
                            end
                        end
                    end
                end
            end
            if not nl then break end
        end
    end)
    stats.pastes = stats.pastes + 1
    stats.made = stats.made + out.count
    stats.failed = stats.failed + out.failed
    return out
end

-- "Made 4 pins. 2 lines could not be read." and the first few reasons.
local function Summary(result)
    local parts = { ("Made %d %s."):format(result.count, result.count == 1 and "pin" or "pins") }
    if result.failed > 0 then
        parts[#parts + 1] = ("%d %s could not be used."):format(result.failed, result.failed == 1 and "line" or "lines")
    end
    if result.skipped > 0 then parts[#parts + 1] = ("%d not tried."):format(result.skipped) end
    return table.concat(parts, " ")
end
PW.Summary = Summary

local function ErrorLines(result, limit)
    local lines = {}
    for i = 1, math.min(#result.errors, limit) do
        local e = result.errors[i]
        lines[#lines + 1] = ("Line %d: %s"):format(e.line, e.text)
    end
    if #result.errors > limit then lines[#lines + 1] = ("... and %d more."):format(#result.errors - limit) end
    return lines
end

---------------------------------------------------------------------------
-- The paste window: built the first time it is asked for. It draws with the new pin window's look
-- (Pins and Pings options > Appearance > New pin window appearance), so it needs nothing of its own to configure.
---------------------------------------------------------------------------
local NAME = "TwichUIPinPaste"
local WIDTH, HEIGHT = 440, 360
local PAD = 14
local pal = PL.palette
local f, body, edit, well, status

local function Close() if f then f:Hide() end end

local function ShowStatus(text, bad)
    local c = bad and { 0.80, 0.45, 0.35 } or pal.stone
    status:SetText(text)
    status:SetTextColor(c[1], c[2], c[3])
end

-- Lines that made a pin are blanked in place, so the line numbers in the messages still match the box and
-- importing again only tries what is left.
local function Blank(text, done)
    local out, n = {}, 0
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        n = n + 1
        out[#out + 1] = done[n] and "" or line
    end
    return table.concat(out, "\n")
end

local function Import()
    if not R:Enabled("partyPins") then Close() return end
    local text = edit:GetText() or ""
    if text:match("^%s*$") then
        ShowStatus("Paste one waypoint per line first.", true)
        return
    end
    local result = PW.ImportText(text)
    local lines = { Summary(result) }
    for _, l in ipairs(ErrorLines(result, 5)) do lines[#lines + 1] = l end
    ShowStatus(table.concat(lines, "\n"), result.failed > 0 and result.count == 0)
    if result.count > 0 then edit:SetText(Blank(text, result.done)) end
    R.Print("%s", Summary(result))
    for _, l in ipairs(ErrorLines(result, SHOWN_ERRORS)) do Grey(l) end
end

local function Build()
    if f then return end
    f = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    if UISpecialFrames then tinsert(UISpecialFrames, NAME) end
    body = CreateFrame("Frame", nil, f)
    body:SetSize(WIDTH, HEIGHT)
    body:SetPoint("CENTER")
    S.Header(body, 30, pal)
    f.title = PL.Text(body, "GameFontNormal", "name")
    f.title:SetPoint("TOPLEFT", PAD + 2, -12)
    f.title:SetText("Paste waypoints")
    local close = S.Close(body, Close, pal)
    close:SetPoint("TOPRIGHT", -8, -8)

    f.hint = PL.Text(body, "GameFontNormalSmall", "meta")
    f.hint:SetPoint("TOPLEFT", PAD + 2, -42)
    f.hint:SetWidth(WIDTH - PAD * 2 - 4)
    f.hint:SetWordWrap(true)
    f.hint:SetJustifyV("TOP")
    f.hint:SetText("One waypoint per line, as /way or /twichway lines. Each makes its own local pin on the zone or #mapID it names, or on the map you are on.")

    well = CreateFrame("Frame", nil, body, "BackdropTemplate")
    well:SetPoint("TOPLEFT", PAD, -76)
    well:SetPoint("BOTTOMRIGHT", -PAD, 118)
    S.Well(well, WIDTH - PAD * 2, HEIGHT - 76 - 118, pal)

    local scroll = CreateFrame("ScrollFrame", nil, well, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    f.paintBar = S.ScrollBar(scroll, pal)
    edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxBytes(MAX_TEXT_BYTES)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(WIDTH - PAD * 2 - 40)
    edit:SetScript("OnEscapePressed", Close)
    edit:SetScript("OnCursorChanged", function(_, _, y, _, h)
        -- keeps the line being typed or pasted in view
        local top, bottom = -y, -y + h
        local offset, height = scroll:GetVerticalScroll(), scroll:GetHeight()
        if top < offset then scroll:SetVerticalScroll(top)
        elseif bottom > offset + height then scroll:SetVerticalScroll(bottom - height) end
    end)
    scroll:SetScrollChild(edit)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    PL.Edit(edit)

    status = PL.Text(body, "GameFontNormalSmall", "meta")
    status:SetPoint("TOPLEFT", well, "BOTTOMLEFT", 2, -8)
    status:SetWidth(WIDTH - PAD * 2 - 4)
    status:SetHeight(54)
    status:SetWordWrap(true)
    status:SetJustifyV("TOP")

    f.import = S.Button(body, "Make pins", 100, "primary", Import, pal)
    f.import:SetPoint("BOTTOMRIGHT", -PAD, 12)
    local cancel = S.Button(body, "Close", 80, "secondary", Close, pal)
    cancel:SetPoint("RIGHT", f.import, "LEFT", -6, 0)
    R.Interact.Tip(f.import, "Make pins", "Makes one local pin for each line it can read. Lines that can't be used stay in the box with the reason; the rest are cleared so nothing is made twice.")

    f.widgets = { f.import, cancel, close }
end

local function Restyle()
    if not f then return end
    local edge = math.ceil(PL.Surface(PL.EditorLook, f))
    f:SetSize(WIDTH + edge * 2, HEIGHT + edge * 2)
    S.PaintHeader(body, pal)
    S.PaintWell(well, pal)
    if f.paintBar then f.paintBar() end
    for _, w in ipairs(f.widgets) do w:Repaint() end
    f.title:SetTextColor(pal.text[1], pal.text[2], pal.text[3])
    f.hint:SetTextColor(pal.textDim[1], pal.textDim[2], pal.textDim[3])
    edit:SetTextColor(pal.text[1], pal.text[2], pal.text[3])
end

local function OnLookChanged() if f and f:IsShown() then Restyle() end end
PL.Subscribe(OnLookChanged)
PL.EditorLook.Subscribe(OnLookChanged)

function PW.OpenPaste()
    if not R:Enabled("partyPins") then Off() return end
    Build()
    Restyle()
    if not f:IsShown() then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        ShowStatus("Paste with Ctrl+V, then Make pins.", false)
    end
    R.FitToScreen(f)
    f:Show()
    f:Raise()
    edit:SetFocus()
end

function PW.Close() Close() end
function PW.IsOpen() return f ~= nil and f:IsShown() end

---------------------------------------------------------------------------
-- The commands
---------------------------------------------------------------------------
-- /twichway is registered as this file loads. /way is added at login, once every addon that has it has
-- had its turn, and again when the switch is turned on; it is never taken from another addon.
SLASH_TWICHUIWAY1 = "/twichway"
SlashCmdList[KEY] = PW.Run

local TAG = "/WAY"
local claimed = false
local wrapped = {}           -- [key] = true: this entry's handler is already followed by TwichUI's

-- Whether the list entry `key` has /way among its slash names.
local function HasWay(key)
    local i = 1
    local tag = _G["SLASH_" .. key .. i]
    while tag do
        if type(tag) == "string" and tag:upper() == TAG then return true end
        i = i + 1
        tag = _G["SLASH_" .. key .. i]
    end
    return false
end

-- "ours", "other" (some other addon has it) or nil (free).
function PW.WayState()
    local hash = _G.hash_SlashCmdList
    local handler = type(hash) == "table" and hash[TAG]
    if handler then return handler == PW.Run and "ours" or "other" end
    if type(SlashCmdList) == "table" then
        for key in pairs(SlashCmdList) do
            if key ~= KEY and type(key) == "string" and HasWay(key) then return "other" end
        end
    end
    return claimed and "ours" or nil
end

-- The SlashCmdList key of the entry that answers /way now, for an addon other than TwichUI. Entries the
-- game hasn't imported yet are in the list itself; imported ones are in its proxy table. When several
-- name /way, the one whose handler is what the game imported last is the live one.
local function OwnerKey()
    if type(SlashCmdList) ~= "table" then return nil end
    local hash = _G.hash_SlashCmdList
    local live = type(hash) == "table" and hash[TAG] or nil
    local first
    local function Look(tbl)
        for key, fn in pairs(tbl) do
            if key ~= KEY and type(key) == "string" and type(fn) == "function" and HasWay(key) then
                if live == nil or fn == live then return key end
                first = first or key
            end
        end
    end
    local found = Look(SlashCmdList)
    if found then return found end
    local meta = getmetatable(SlashCmdList)
    local proxy = type(meta) == "table" and type(meta.__index) == "table" and meta.__index or nil
    if proxy then
        found = Look(proxy)
        if found then return found end
    end
    return first
end

-- Called after another addon's /way handler with the text it was given. Only for text that reads as a
-- waypoint: the other addon has already said what it had to about anything else.
function PW.AlsoPin(msg)
    if type(msg) ~= "string" or not R:Enabled("partyPins") or not PL.Pref("wayAlso") then return end
    local entry = PW.Parse(msg)
    if not entry then return end
    local pin, code, detail
    PN.Batch(function()
        pin, code, detail = Place(entry, {})
        if pin then PN.Select("local:" .. pin.id) end
    end)
    if pin then
        stats.made, stats.also = stats.made + 1, stats.also + 1
        R.Print("%s", Sentence(pin, entry))
    else
        stats.failed = stats.failed + 1
        R.Print("%s", Message(code, detail))
    end
end

-- Follows the other addon's handler, once per entry. The other handler runs first and untouched; ours is
-- gated on the choice every time, so turning it off needs nothing taken back.
local function Follow()
    local key = OwnerKey()
    if not key or wrapped[key] then return end
    local inner = SlashCmdList[key]
    if type(inner) ~= "function" then return end
    wrapped[key] = true
    SlashCmdList[key] = function(msg, ...)
        inner(msg, ...)
        local ok, err = pcall(PW.AlsoPin, msg)
        if not ok and R.Fault then R.Fault("waypoint commands", err) end
    end
end

function PW.Refresh()
    if not R:Enabled("partyPins") then return end
    if not claimed and PW.WayState() == nil then
        claimed = true
        SLASH_TWICHUIWAY2 = "/way"
        SlashCmdList[KEY] = PW.Run   -- again, so the game reads both names from the pending list
    end
    if not claimed and PL.Pref("wayAlso") and PW.WayState() == "other" then Follow() end
end

R:On("PLAYER_LOGIN", PW.Refresh)
PL.OnPrefChange(PW.Refresh)   -- choosing "Also make a pin from /way"

-- Read only, for /tui diagnostics: counts and who has /way, never what was typed.
function PW.Snapshot()
    local way = PW.WayState()
    return {
        way = way or "free", commands = stats.commands, made = stats.made, failed = stats.failed,
        pastes = stats.pastes, open = PW.IsOpen(), zonesKnown = next(names) ~= nil,
        also = PL.Pref("wayAlso"), followed = next(wrapped) ~= nil, alsoMade = stats.also,
    }
end

-- For the offline tests: a fresh zone list, and a way to forget the claim.
function PW.ResetCache()
    names, rootsDone, startsSeen, primed = {}, {}, {}, false
end
