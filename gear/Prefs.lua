-- TwichUI: upgrade hints, preferences
-- What you've chosen in the upgrade hints window (/twichui gear): which
-- talent tree to weigh for, how each tree values stats (your stat weights,
-- or your ranked stat priority), and how hints behave.
-- Kept account-wide in TwichUIDB.gear; the talent tree choice is per
-- character. The on/off switches live with TwichUI's other toggles
-- (TwichUIDB.modules.gearHints and gearBagIcons).

local R = TwichUI
local P = {}
R.GearPrefs = P

local DEFAULTS = {
    glancePossible = true,    -- "Possible upgrade" lines too, not only "Likely"
    futureLevels = true,      -- hint at gear you can wear once you reach its level
    reveal = "compare",       -- reasoning on: "compare" (Shift), "alt", "ctrl" or "always"
    strictness = "balanced",  -- how big a gain counts: "cautious", "balanced" or "eager"
    bagStyle = "gilded",      -- bag icon: "gilded", "green" or "badge"
}

-- Gain over what you wear needed for "Likely" and "Possible".
P.STRICTNESS = {
    cautious = { likely = 0.15, possible = 0.06 },
    balanced = { likely = 0.10, possible = 0.03 },
    eager    = { likely = 0.05, possible = 0.01 },
}

local db
local function DB()
    if db then return db end
    TwichUIDB.gear = TwichUIDB.gear or {}
    db = TwichUIDB.gear
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    db.weights = db.weights or {}   -- [classFile][skillLine][stat] = weight
    db.priority = db.priority or {} -- [classFile][skillLine] = { stat, ... } most important first
    db.usePriority = db.usePriority or {} -- [classFile][skillLine] = true: value by priority
    db.trees = db.trees or {}       -- [character] = skillLine of the chosen tree
    return db
end

local listeners = {}
function P:OnChange(fn) listeners[#listeners + 1] = fn end

function P.Changed()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end

function P.Get(key)
    return DB()[key]
end

function P.Set(key, value)
    DB()[key] = value
    P.Changed()
end

local function Character()
    return (UnitName("player") or "?") .. "-" .. (GetNormalizedRealmName() or "?")
end

-- The tree this character's gear is weighed for (a skill line), or nil for
-- automatic: the tree with the most talent points.
function P.TreeChoice()
    return DB().trees[Character()]
end

function P.SetTreeChoice(skillLine)
    DB().trees[Character()] = skillLine
    P.Changed()
end

-- Your changes to one tree's stat weights: { [stat] = weight }, or nil.
function P.CustomWeights(classFile, skillLine)
    local byClass = DB().weights[classFile]
    return byClass and byClass[skillLine]
end

-- A nil weight puts the stat back to its default.
function P.SetWeight(classFile, skillLine, stat, weight)
    local all = DB().weights
    local byClass = all[classFile] or {}
    local tree = byClass[skillLine] or {}
    tree[stat] = weight
    byClass[skillLine] = next(tree) and tree or nil
    all[classFile] = next(byClass) and byClass or nil
    P.Changed()
end

function P.ResetWeights(classFile, skillLine)
    local byClass = DB().weights[classFile]
    if byClass then
        byClass[skillLine] = nil
        if not next(byClass) then DB().weights[classFile] = nil end
    end
    P.Changed()
end

-- [classFile][skillLine] in one of the tables above; nil removes the entry
-- (and the class's table once it's empty).
local function SetTreeValue(all, classFile, skillLine, value)
    local byClass = all[classFile] or {}
    byClass[skillLine] = value
    all[classFile] = next(byClass) and byClass or nil
end

-- Your ranked stats for a class's tree, most important first, or nil.
function P.Priority(classFile, skillLine)
    local byClass = DB().priority[classFile]
    return byClass and byClass[skillLine]
end

function P.SetPriority(classFile, skillLine, list)
    SetTreeValue(DB().priority, classFile, skillLine, list and #list > 0 and list or nil)
    P.Changed()
end

-- Whether a tree values stats by your priority (true) or by its weights.
function P.UsesPriority(classFile, skillLine)
    local byClass = DB().usePriority[classFile]
    return byClass and byClass[skillLine] or false
end

function P.SetUsesPriority(classFile, skillLine, on)
    SetTreeValue(DB().usePriority, classFile, skillLine, on or nil)
    P.Changed()
end
