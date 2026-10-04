-- TwichUI: checks a generated training data file before it replaces modules/TrainingData.lua.
-- Usage: lua5.1 tools/validate_training_data.lua <new file> [<current file>]
-- Loads the file the way the addon does (a chunk that fills TwichUI.TrainingData), then checks every
-- class returns levels and ranks in the shape modules/Training.lua reads, and that nothing looks
-- truncated: a minimum per class and, when a current file is given, no class shrinking below half.
-- Prints one line per class; exits nonzero with the reason on the first problem.

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
local MIN_PER_CLASS = 50
local MIN_FRACTION_OF_CURRENT = 0.5

local function Fail(message)
    io.stderr:write("validate_training_data: " .. message .. "\n")
    os.exit(1)
end

local function Load(path)
    local chunk, err = loadfile(path)
    if not chunk then Fail(err) end
    local addon = {}
    setfenv(chunk, setmetatable({ TwichUI = addon }, { __index = _G }))
    local ok, runError = pcall(chunk)
    if not ok then Fail(path .. ": " .. tostring(runError)) end
    if type(addon.TrainingData) ~= "table" then Fail(path .. ": does not define TwichUI.TrainingData") end
    return addon.TrainingData
end

local function IsId(v) return type(v) == "number" and v > 0 and v == math.floor(v) end

-- Returns the number of spell entries for a class, failing on anything the addon would misread.
local function Check(data, class, where)
    if type(data[class]) ~= "function" then Fail(where .. ": no data function for " .. class) end
    local ok, levels, ranks = pcall(data[class])
    if not ok then Fail(where .. ": " .. class .. " raised " .. tostring(levels)) end
    if type(levels) ~= "table" or type(ranks) ~= "table" then Fail(where .. ": " .. class .. " must return levels and ranks tables") end
    local seen, count = {}, 0
    for level, list in pairs(levels) do
        if type(level) ~= "number" or level < 1 or level > 60 or level ~= math.floor(level) then
            Fail(where .. ": " .. class .. " has level " .. tostring(level))
        end
        if type(list) ~= "table" or #list == 0 then Fail(where .. ": " .. class .. " level " .. level .. " is empty") end
        for _, e in ipairs(list) do
            if type(e) ~= "table" or not IsId(e[1]) then Fail(where .. ": " .. class .. " level " .. level .. " has an entry without a spell id") end
            if seen[e[1]] then Fail(where .. ": " .. class .. " lists spell " .. e[1] .. " twice") end
            seen[e[1]] = true
            count = count + 1
            if e.faction ~= nil and e.faction ~= "Alliance" and e.faction ~= "Horde" then Fail(where .. ": " .. class .. " spell " .. e[1] .. " has faction " .. tostring(e.faction)) end
            if e.talent ~= nil and not IsId(e.talent) then Fail(where .. ": " .. class .. " spell " .. e[1] .. " has a bad talent") end
            for _, key in ipairs({ "req", "race" }) do
                if e[key] ~= nil then
                    if type(e[key]) ~= "table" or #e[key] == 0 then Fail(where .. ": " .. class .. " spell " .. e[1] .. " has a bad " .. key) end
                    for _, v in ipairs(e[key]) do
                        if not IsId(v) then Fail(where .. ": " .. class .. " spell " .. e[1] .. " has a bad " .. key .. " value") end
                    end
                end
            end
        end
    end
    for _, group in ipairs(ranks) do
        if type(group) ~= "table" or #group < 2 then Fail(where .. ": " .. class .. " has a rank group with fewer than two spells") end
        for _, id in ipairs(group) do
            if not IsId(id) then Fail(where .. ": " .. class .. " has a bad spell id in a rank group") end
        end
    end
    return count
end

local path, currentPath = arg[1], arg[2]
if not path then Fail("usage: validate_training_data.lua <new file> [<current file>]") end
local file = io.open(path, "rb")
if not file then Fail("cannot read " .. path) end
local size = file:seek("end")
file:close()
if size == 0 then Fail(path .. " is empty") end

local data = Load(path)
local current
if currentPath then
    local f = io.open(currentPath, "rb")
    if f then f:close(); current = Load(currentPath) end   -- no current file: nothing to compare with
end

local total = 0
for _, class in ipairs(CLASSES) do
    local count = Check(data, class, path)
    if count < MIN_PER_CLASS then Fail(("%s has only %d entries (at least %d expected)"):format(class, count, MIN_PER_CLASS)) end
    if current then
        local before = Check(current, class, currentPath)
        if count < before * MIN_FRACTION_OF_CURRENT then
            Fail(("%s shrank from %d to %d entries; refusing to replace the current data"):format(class, before, count))
        end
    end
    total = total + count
    print(("  %-8s %4d entries"):format(class, count))
end
print(("  %d entries in all"):format(total))
