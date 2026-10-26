-- TwichUI: Vendors and trainers, browsing what is known
-- What the settings' World Knowledge tab reads and does, without any frame: the list's entries as display rows,
-- filtered and ordered, the areas they stand in, how each came to be known, and removing or sending a chosen set.
-- Reading never changes the saved list: rows are small tables of their own that point at the entries, and are
-- rebuilt (not patched) after any change to the list, once, the next time they are asked for.
-- How an entry came to be known is only what the entry itself records (npcs/Store.lua): `own` (you dealt with it
-- yourself, `seen` visits, `at` the last), `rep` (how many reports of it reached you) and `at` (the last report, for one
-- you never saw). The channel a report came through and who sent it are not kept, so they are not shown; an entry with
-- neither `own` nor `rep` is from before reports were counted and is called what it is, a source not recorded.
-- An entry is one NPC in one place. An NPC with several places (or several roles) is several entries (or one entry
-- with several kinds), so removing an area removes exactly the entries standing in it and nothing of the same NPC
-- anywhere else.

local R = TwichUI
local NK, NS = R.NpcKinds, R.NpcStore
local Perf = R.Perf
local KN = {}
R.NpcKnowledge = KN

KN.SOURCES = {
    { "any", "Every source" },
    { "mine", "Seen by you" },
    { "others", "From others" },
    { "unknown", "Source not recorded" },
}

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local rows, byEntry, zones, kinds, built, dirty   -- the derived list; rebuilt on demand

local function Lower(text) return (text or ""):lower() end

local function KindLines(e)
    local NMAP = R.NpcMap
    if NMAP and NMAP.KindLines then return NMAP.KindLines(e) end
    return { NK.Describe(e.tags) }
end

-- "mine", "others" or "unknown": what the entry itself says about how it became known.
function KN.SourceOf(e)
    if e.own then return "mine" end
    if (e.rep or 0) > 0 then return "others" end
    return "unknown"
end

local function Date(at)
    if type(at) ~= "number" or at <= 0 or not date then return nil end
    return date("%d %b %Y", at)
end

local function ZoneName(map)
    local PN = R.Pins
    return PN and PN.MapName(map) or ("Map " .. tostring(map))
end
KN.ZoneName = ZoneName

local function Build()
    local pt = Perf.on and Perf.Start("npcs.knowledge.rebuild")
    local entries = NS.Entries()
    rows, byEntry, built, dirty = {}, {}, entries, false
    local names, zoneCount, kindCount = {}, {}, {}
    for _, e in ipairs(entries) do
        local zone = names[e.m]
        if not zone then zone = ZoneName(e.m) names[e.m] = zone end
        local lines = KindLines(e)
        local row = { e = e, name = e.n, lname = Lower(e.n), zone = zone, lzone = Lower(zone), lines = lines,
            role = lines[1] or "NPC", more = math.max(0, #lines - 1), source = KN.SourceOf(e) }
        row.hay = table.concat({ row.lname, row.lzone, Lower(table.concat(lines, " ")), Lower(e.t), Lower(e.prof) }, " ")
        rows[#rows + 1] = row
        byEntry[e] = row
        zoneCount[e.m] = (zoneCount[e.m] or 0) + 1
        for tag in pairs(e.tags) do kindCount[tag] = (kindCount[tag] or 0) + 1 end
    end
    -- a fixed order: name, then area, then place, then creature (so identical names never swap places)
    table.sort(rows, function(a, b)
        if a.lname ~= b.lname then return a.lname < b.lname end
        if a.lzone ~= b.lzone then return a.lzone < b.lzone end
        local x, y = a.e, b.e
        if x.m ~= y.m then return x.m < y.m end
        if x.id ~= y.id then return x.id < y.id end
        if x.x ~= y.x then return x.x < y.x end
        return x.y < y.y
    end)
    zones = {}
    for map, n in pairs(zoneCount) do zones[#zones + 1] = { map = map, name = names[map], count = n } end
    table.sort(zones, function(a, b)
        local x, y = Lower(a.name), Lower(b.name)
        if x ~= y then return x < y end
        return a.map < b.map
    end)
    kinds = {}
    for _, k in ipairs(NK.LIST) do
        if kindCount[k.id] then kinds[#kinds + 1] = { id = k.id, label = k.label, count = kindCount[k.id] } end
    end
    if pt then Perf.Stop(pt) end
end

local function Ready()
    if not rows or dirty or built ~= NS.Entries() then Build() end
end

-- Every entry as a row, in order. Do not change it.
function KN.Rows() Ready() return rows end
function KN.Total() Ready() return #rows end
function KN.Row(e) Ready() return byEntry[e] end
-- The areas that have entries: { map, name, count }, by name. And the kinds that have: { id, label, count }, in the
-- order the settings list them.
function KN.Zones() Ready() return zones end
function KN.Kinds() Ready() return kinds end

NS.OnChange(function() dirty = true end)

---------------------------------------------------------------------------
-- Filtering
---------------------------------------------------------------------------
-- f: { text, map, kind, source } (each optional). Every word of the text has to appear in the name, area, role, title
-- or profession, in any order, without regard to case. Returns a new list of rows in the rows' order.
function KN.Active(f)
    return f ~= nil and ((f.text and f.text:find("%S") ~= nil) or f.map ~= nil or f.kind ~= nil
        or (f.source ~= nil and f.source ~= "any"))
end

function KN.Filter(f)
    Ready()
    local out = {}
    f = f or {}
    local words = {}
    for w in Lower(f.text):gmatch("%S+") do words[#words + 1] = w end
    local source = f.source ~= "any" and f.source or nil
    for _, row in ipairs(rows) do
        local e = row.e
        local ok = (f.map == nil or e.m == f.map) and (f.kind == nil or e.tags[f.kind] == true)
            and (source == nil or row.source == source)
        if ok then
            for i = 1, #words do
                if not row.hay:find(words[i], 1, true) then ok = false break end
            end
        end
        if ok then out[#out + 1] = row end
    end
    return out
end

-- A phrase for what a filter is, for the questions that name it: `"inn" in Elwynn Forest, Innkeeper, Seen by you`.
function KN.Describe(f)
    if not KN.Active(f) then return "no filters" end
    local parts = {}
    local text = f.text and f.text:match("^%s*(.-)%s*$")
    if text and text ~= "" then parts[#parts + 1] = ('"%s"'):format(text) end
    if f.map then parts[#parts + 1] = "in " .. ZoneName(f.map) end
    if f.kind then parts[#parts + 1] = NK.BY_ID[f.kind] and NK.BY_ID[f.kind].noun or f.kind end
    if f.source and f.source ~= "any" then
        for _, s in ipairs(KN.SOURCES) do if s[1] == f.source then parts[#parts + 1] = s[2] end end
    end
    return table.concat(parts, ", ")
end

-- The entries of a list of rows, as a list of their own, which a question holds to: the set it names stays that set.
function KN.Entries(list)
    local out = {}
    for i, row in ipairs(list) do out[i] = row.e end
    return out
end

---------------------------------------------------------------------------
-- What is known about one
---------------------------------------------------------------------------
-- The short word for the list's source column.
function KN.SourceWord(row)
    if row.source == "mine" then return "You" end
    if row.source == "others" then return "Others" end
    return "Not recorded"
end

-- Lines for the details: where it stands, what it is, how it became known. Only what the entry holds.
function KN.Details(row)
    local e = row.e
    local lines = {}
    local PN = R.Pins
    lines.place = PN and PN.Describe({ map = e.m, x = e.x, y = e.y }) or row.zone
    lines.title = e.t
    lines.roles = row.lines
    local sources = {}
    if e.own then
        sources[#sources + 1] = (e.seen or 1) > 1 and ("Seen by you on %d visits."):format(e.seen) or "Seen by you."
        if (e.rep or 0) > 0 then
            sources[#sources + 1] = ("Also reported to you by others (%d %s)."):format(e.rep, e.rep == 1 and "time" or "times")
        end
        local when = Date(e.at)
        if when then sources[#sources + 1] = "You last saw it on " .. when .. "." end
    elseif (e.rep or 0) > 0 then
        sources[#sources + 1] = ("Reported to you by others (%d %s); you haven't seen it yourself."):format(e.rep, e.rep == 1 and "time" or "times")
        local when = Date(e.at)
        if when then sources[#sources + 1] = "Last reported on " .. when .. "." end
    else
        sources[#sources + 1] = "How this one became known was not recorded."
        local when = Date(e.at)
        if when then sources[#sources + 1] = "Last noted on " .. when .. "." end
    end
    if not e.own or (e.rep or 0) > 0 then
        sources[#sources + 1] = "Who sent it and through which channel isn't kept."
    end
    lines.sources = sources
    return lines
end

---------------------------------------------------------------------------
-- Areas
---------------------------------------------------------------------------
-- The entries standing on exactly this map (not the maps inside it: a dungeon or a city district is an area of its own).
function KN.AreaEntries(map)
    local out = {}
    for _, e in ipairs(NS.Entries()) do
        if e.m == map then out[#out + 1] = e end
    end
    return out
end

---------------------------------------------------------------------------
-- Removing and sending
---------------------------------------------------------------------------
-- Exactly these entries (a list from KN.Entries or AreaEntries). Returns how many went.
function KN.Forget(entries) return NS.ForgetMany(entries) end

-- Sends exactly these entries, through the same question and the same protocol as the whole list. scope: the words for
-- them ("this NPC", "the 28 NPCs shown"). Returns false and prints why when it can't be offered.
function KN.Share(entries, audience, scope)
    local NSH = R.NpcShare
    if not NSH then return false end
    if audience == "whisper" then
        NSH.AskName(entries, scope)
        return true
    end
    return NSH.Offer(audience, nil, entries, scope)
end

-- Why a destination can't be used right now, or nil.
function KN.Unavailable(audience)
    if not R:Enabled("npcMap") then return "Vendors and trainers is turned off." end
    if audience == "party" and not IsInGroup() then return "You aren't in a group." end
    if audience == "guild" and not IsInGuild() then return "You aren't in a guild." end
    return nil
end
