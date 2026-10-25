-- TwichUI: Vendors and trainers, saved choices
-- Kept in TwichUIDB.ui.npcMap (in the profile; only stored once changed). Whether the feature is on at all is the switch
-- modules.npcMap (Core.lua; off until turned on). The list of NPCs itself is not a choice and is not here (npcs/Store.lua).
--   show.<kind>    which kinds of NPC the world map shows (npcs/Kinds.lua's list; each kind's own default)
--   trainerClass   "mine": class trainers for your class only; "all": every class's
--   reports        show what other players sent you (dimmed), not only what you saw yourself
--   labels         names under the markers
--   iconSize       marker size in percent
--   minimap        also draw the markers within range on the minimap (npcs/Minimap.lua; off)
--   receive        what happens when another TwichUI user sends you their list: "ask" (the default; you are asked each
--                  time), "auto" (added without asking when it comes from your party or guild; a whisper still asks)
--                  or "off" (ignored)
--   sendReports    what you send includes what others sent you, not only what you saw yourself
--   liveGroup      an NPC you deal with for the first time is passed on to your group as you go (npcs/Share.lua; on)
--   liveGuild      the same to your guild (on)
--   liveReceive    NPCs your group or guild pass on as they find them are added quietly, as reports (on)
-- A saved value that can't be used is read as its default and left as it was. Nothing here is read per frame.

local R = TwichUI
local NK = R.NpcKinds
local NP = {}
R.NpcPrefs = NP

local DEFAULTS = {
    trainerClass = "mine", reports = true, labels = false, minimap = false, iconSize = 100, receive = "ask", sendReports = false,
    liveGroup = true, liveGuild = true, liveReceive = true,
}
for _, k in ipairs(NK.LIST) do DEFAULTS["show." .. k.id] = k.on end
local LIMITS = { iconSize = { 60, 150 } }
local ENUM = {
    trainerClass = { mine = true, all = true },
    receive = { ask = true, auto = true, off = true },
}
NP.DEFAULTS, NP.LIMITS, NP.ENUM = DEFAULTS, LIMITS, ENUM
NP.TRAINER_CLASS = { { "mine", "My class only" }, { "all", "Every class" } }
NP.RECEIVE = {
    { "ask", "Ask each time", "A short question names who sent it and how many are new to you. Nothing is added until you accept." },
    { "auto", "Add from party and guild", "Lists from your party or guild are added without asking, as reports from others. A list whispered to you still asks." },
    { "off", "Don't take any", "Lists sent to you are ignored." },
}

-- What each reset puts back
NP.GROUPS = { show = {}, look = { "trainerClass", "reports", "labels", "minimap", "iconSize" }, sharing = { "receive", "sendReports", "liveGroup", "liveGuild", "liveReceive" } }
for _, k in ipairs(NK.LIST) do table.insert(NP.GROUPS.show, "show." .. k.id) end

local function Valid(key, value)
    local d = DEFAULTS[key]
    if d == nil then return false end
    if type(d) == "boolean" then return type(value) == "boolean" end
    if ENUM[key] then return type(value) == "string" and ENUM[key][value] == true end
    local lim = LIMITS[key]
    return type(value) == "number" and value == value and value % 1 == 0 and value >= lim[1] and value <= lim[2]
end
NP.Valid = Valid

local function Saved()
    local ui = TwichUIDB and TwichUIDB.ui
    local t = ui and ui.npcMap
    return type(t) == "table" and t or nil
end

function NP.Get(key)
    local t = Saved()
    local v = t and t[key]
    if Valid(key, v) then return v end
    return DEFAULTS[key]
end

function NP.Shown(kind) return NP.Get("show." .. kind) == true end

local subscribers = {}
function NP.Subscribe(fn) subscribers[#subscribers + 1] = fn end
local function Notify(key)
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn, key)
        if not ok then geterrorhandler()(err) end
    end
end
NP.Notify = Notify

-- Saves one choice (an unusable one is refused). Returns whether it was kept.
function NP.Set(key, value)
    if not Valid(key, value) or type(TwichUIDB) ~= "table" then return false end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    if type(TwichUIDB.ui.npcMap) ~= "table" then TwichUIDB.ui.npcMap = {} end
    local t = TwichUIDB.ui.npcMap
    if t[key] == value then return true end
    t[key] = value
    Notify(key)
    return true
end

-- Every kind shown, or every kind hidden, in one change (one notice, so the map is drawn once). Only kinds that differ
-- are written. Returns whether it was kept.
function NP.SetAllShown(value)
    if type(value) ~= "boolean" or type(TwichUIDB) ~= "table" then return false end
    local changed = false
    for _, k in ipairs(NK.LIST) do
        local key = "show." .. k.id
        if NP.Get(key) ~= value then
            TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
            if type(TwichUIDB.ui.npcMap) ~= "table" then TwichUIDB.ui.npcMap = {} end
            TwichUIDB.ui.npcMap[key] = value
            changed = true
        end
    end
    if changed then Notify("show") end
    return true
end

-- Puts one scope back ("show", "look", "sharing" or "all"). The list of NPCs and the switch are not touched.
function NP.Reset(scope)
    local t = Saved()
    local groups = scope == "all" and { "show", "look", "sharing" } or { scope }
    for _, g in ipairs(groups) do
        for _, k in ipairs(NP.GROUPS[g] or {}) do
            if t then t[k] = nil end
        end
    end
    Notify(scope)
end

-- A profile change put other choices in place: whatever shows them follows.
if R.Profiles and R.Profiles.OnApply then
    R.Profiles.OnApply("views", "npcMap", function() Notify("profile") end)
end
