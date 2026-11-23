-- Personal, profile-owned health threshold. No class/talent inference or game actions.
local R = TwichUI
local C = {}
R.ExecuteRange = C
C.DEFAULTS = { threshold = 20, target = true, nameplates = true, appearance = "both" }
C.LIMITS = { threshold = { 1, 100 } }
C.CHOICES = { appearance = {
    { "marker", "Threshold marker" }, { "active", "Active range edge" }, { "both", "Marker and active edge" },
} }
C.ENUM = { appearance = { marker = true, active = true, both = true } }
local listeners = {}
function C.Subscribe(fn) listeners[#listeners + 1] = fn end
function C.Notify()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then R.Fault("execute range", err) end
    end
end
local function Saved(create)
    if type(TwichUIDB) ~= "table" then return end
    if type(TwichUIDB.ui) ~= "table" then
        if not create then return end
        TwichUIDB.ui = {}
    end
    if type(TwichUIDB.ui.executeRange) ~= "table" then
        if not create then return end
        TwichUIDB.ui.executeRange = {}
    end
    return TwichUIDB.ui.executeRange
end
function C.Valid(key, value)
    if issecretvalue and issecretvalue(value) then return false end
    if key == "threshold" then
        return type(value) == "number" and value == value and value >= 1 and value <= 100 and value % 1 == 0
    end
    if key == "target" or key == "nameplates" then return type(value) == "boolean" end
    return key == "appearance" and type(value) == "string" and C.ENUM.appearance[value] == true
end
function C.Get(key)
    local saved = Saved(false)
    if saved and C.Valid(key, saved[key]) then return saved[key] end
    return C.DEFAULTS[key]
end
function C.Set(key, value)
    if not C.Valid(key, value) then return false end
    local saved = Saved(true)
    if not saved then return false end
    if saved[key] ~= value then saved[key] = value; C.Notify() end
    return true
end
function C.ResetSettings()
    local saved = Saved(false)
    if saved then for key in pairs(C.DEFAULTS) do saved[key] = nil end end
    C.Notify()
end
-- StatusBar normal vertical fill starts at the bottom; reverse starts at the top.
-- Coordinates are in the actual bar's units, inherited by its texture children.
function C.Marker(width, height, orientation, reverse, threshold)
    local fraction = threshold / 100
    if reverse then fraction = 1 - fraction end
    if orientation == "HORIZONTAL" then
        local thickness = math.min(1, width)
        return math.max(0, math.min(width - thickness, width * fraction - thickness / 2)), 0, thickness, height
    end
    local thickness = math.min(1, height)
    return 0, math.max(0, math.min(height - thickness, height * fraction - thickness / 2)), width, thickness
end
