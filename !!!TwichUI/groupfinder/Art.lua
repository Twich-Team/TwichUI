-- Packaged original dungeon art. No activity IDs or client texture filenames.
local R = TwichUI
R.GroupFinder = R.GroupFinder or {}
local A = {}
R.GroupFinder.Art = A
local DIR = R.PATH .. [[media\groupfinder\]]

-- Instance/map IDs are verified in map/Data.lua, generated from Forever
-- 1.60.1.70450. Do not fill missing IDs using another client version.
local MAPS = {
    [33] = "shadowfang-keep", [34] = "stockade", [36] = "deadmines",
    [43] = "wailing-caverns", [47] = "razorfen-kraul", [48] = "blackfathom-deeps",
    [70] = "uldaman", [90] = "gnomeregan", [129] = "razorfen-downs",
    [289] = "scholomance", [309] = "ancient-zul-gurub", [349] = "maraudon",
    [389] = "ragefire-chasm", [429] = "dire-maul",
}
-- Public English names cover entries absent from the verified map inventory.
-- Full and short activity names may differ; wings share their parent dungeon's
-- entrance unless dedicated artwork exists. Unmatched localized names retain
-- a neutral entrance rather than guessing identity from a substring.
local NAMES = {
    ["Blackrock Depths"] = "blackrock-depths", ["Scholomance"] = "scholomance",
    ["Maraudon"] = "maraudon", ["Zul'Farrak"] = "zul-farrak", ["Zul’Farrak"] = "zul-farrak", ["Uldaman"] = "uldaman",
    ["Deadmines"] = "deadmines", ["The Deadmines"] = "deadmines",
    ["Wailing Caverns"] = "wailing-caverns", ["Ragefire Chasm"] = "ragefire-chasm",
    ["Shadowfang Keep"] = "shadowfang-keep", ["Blackfathom Deeps"] = "blackfathom-deeps",
    ["Stockade"] = "stockade", ["The Stockade"] = "stockade", ["Stormwind Stockade"] = "stockade",
    ["Gnomeregan"] = "gnomeregan", ["Razorfen Kraul"] = "razorfen-kraul", ["Razorfen Downs"] = "razorfen-downs",
    ["Scarlet Monastery"] = "scarlet-monastery",
    ["Scarlet Monastery Graveyard"] = "scarlet-monastery", ["Scarlet Monastery Library"] = "scarlet-monastery",
    ["Scarlet Monastery Armory"] = "scarlet-monastery", ["Scarlet Monastery Cathedral"] = "scarlet-monastery",
    ["Sunken Temple"] = "sunken-temple", ["The Temple of Atal'Hakkar"] = "sunken-temple", ["Temple of Atal'Hakkar"] = "sunken-temple",
    ["Dire Maul"] = "dire-maul", ["Dire Maul East"] = "dire-maul", ["Dire Maul West"] = "dire-maul", ["Dire Maul North"] = "dire-maul",
    ["Dire Maul (East)"] = "dire-maul", ["Dire Maul (West)"] = "dire-maul", ["Dire Maul (North)"] = "dire-maul",
    ["Stratholme"] = "stratholme", ["Stratholme Live"] = "stratholme", ["Stratholme Undead"] = "stratholme",
    ["Lower Blackrock Spire"] = "lower-blackrock-spire", ["Upper Blackrock Spire"] = "upper-blackrock-spire",
    ["Blackrock Spire"] = "lower-blackrock-spire", ["Ancient Zul'Gurub"] = "ancient-zul-gurub",
    -- Exact activity names confirmed by the owner's Forever picker screenshot.
    -- Their map IDs have not been verified and are deliberately not guessed.
    ["Alcaz Prison"] = "alcaz-prison", ["Blackmaw Hold"] = "blackmaw-hold",
    ["City of Dalaran"] = "city-of-dalaran", ["Excavation Site: Wetlands"] = "excavation-site-wetlands",
}
local function Plain(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end
local function Name(value)
    value = Plain(value)
    if type(value) ~= "string" then return nil end
    local art = NAMES[value]
    if not art and value:match("^Scarlet Monastery[%s%-:]") then art = "scarlet-monastery" end
    return art
end

-- true selects the 64px detail asset; a numeric size selects 32/64/128.
function A.ForActivity(info, small)
    info = Plain(info)
    local art
    if type(info) == "table" then
        local mapID = Plain(info.mapID)
        if type(mapID) == "number" then art = MAPS[mapID] end
        art = art or Name(info.fullName) or Name(info.shortName) or Name(info.name)
    end
    local suffix = small == true and "-small" or ""
    if type(small) == "number" then suffix = small <= 32 and "-tiny" or small <= 64 and "-small" or "" end
    return DIR .. (art or "dungeon-entrance") .. suffix
end
