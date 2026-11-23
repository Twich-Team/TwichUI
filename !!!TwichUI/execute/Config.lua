-- Personal, profile-owned health threshold. No class/talent inference or game actions.
local R = TwichUI
local C = {}
R.ExecuteRange = C
C.DEFAULTS = { threshold = 20, target = true, nameplates = true, appearance = "both", color = "ffcc7847", opacity = 25, texture = "solid" }
C.LIMITS = { threshold = { 1, 100 }, opacity = { 0, 100 } }
C.CHOICES = { appearance = {
    { "marker", "Threshold marker" }, { "active", "Active range edge" }, { "both", "Marker and active edge" },
    { "zone", "Execute zone overlay" }, { "highlight", "Active health highlight" },
    { "markerZone", "Marker and execute zone" }, { "markerZoneEdge", "Marker, zone and active edge" },
} }
C.ENUM = { appearance = { marker = true, active = true, both = true, zone = true, highlight = true, markerZone = true, markerZoneEdge = true } }
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
    if key == "color" then return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") ~= nil end
    if key == "texture" then
        return type(value) == "string" and #value > 0 and #value <= 128 and not value:find("[%c/\\]")
    end
    if key == "opacity" then
        return type(value) == "number" and value == value and value >= 0 and value <= 100 and value % 1 == 0
    end
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

-- One fill only: an always-visible zone OR the remaining readable active health.
function C.Style(appearance)
    return appearance == "marker" or appearance == "both" or appearance == "markerZone" or appearance == "markerZoneEdge",
        appearance == "active" or appearance == "both" or appearance == "markerZoneEdge",
        appearance == "zone" or appearance == "markerZone" or appearance == "markerZoneEdge",
        appearance == "highlight"
end
function C.Region(width, height, orientation, reverse, fraction)
    if orientation == "HORIZONTAL" then
        return reverse and width * (1 - fraction) or 0, 0, width * fraction, height
    end
    return 0, reverse and height * (1 - fraction) or 0, width, height * fraction
end
