-- Profile-owned opt-in settings; no new database or eager default writes.
local R = TwichUI
local C = {}
R.ClassPortrait = C
C.DEFAULTS = { enabled = false, automatic = true, size = 100, x = 0, y = 0, above = false, strata = "inherit", artwork = "original" }
C.LIMITS = { size = { 50, 150 }, x = { -100, 100 }, y = { -100, 100 } }
C.CHOICES = { artwork = { { "original", "Original" }, { "slim", "Slim" } }, strata = {
    { "inherit", "Follow unit frame" }, { "LOW", "Low" }, { "MEDIUM", "Medium" },
    { "HIGH", "High" }, { "DIALOG", "Dialog" },
} }
C.ENUM = { artwork = { original = true, slim = true }, strata = { inherit = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true } }
local listeners = {}
function C.Subscribe(fn) listeners[#listeners + 1] = fn end
function C.Notify()
    for _, fn in ipairs(listeners) do fn() end
end
local function Saved(create)
    if type(TwichUIDB) ~= "table" then return end
    if type(TwichUIDB.ui) ~= "table" then
        if not create then return end
        TwichUIDB.ui = {}
    end
    if type(TwichUIDB.ui.classPortrait) ~= "table" then
        if not create then return end
        TwichUIDB.ui.classPortrait = {}
    end
    return TwichUIDB.ui.classPortrait
end
function C.Valid(key, v)
    local d = C.DEFAULTS[key]
    if d == nil then return false end
    if type(d) == "boolean" then return type(v) == "boolean" end
    if type(d) == "string" then return type(v) == "string" and C.ENUM[key][v] == true end
    local l = C.LIMITS[key]
    return type(v) == "number" and v == v and v >= l[1] and v <= l[2] and v % 1 == 0
end
function C.Get(key)
    local s = Saved(false)
    if s and C.Valid(key, s[key]) then return s[key] end
    return C.DEFAULTS[key]
end
function C.Set(key, value)
    if not C.Valid(key, value) then return false end
    local s = Saved(true)
    if not s then return false end
    if s[key] ~= value then s[key] = value; C.Notify() end
    return true
end
function C.Reset()
    local s = Saved(false)
    if s then s.automatic, s.size, s.x, s.y = nil, nil, nil, nil end
    C.Notify()
end
-- Texture and portrait share their parent's units and scale. Fit both axes by
-- containment (the entire portrait fits inside the opening), preserving aspect.
-- The opening's centre stays on the portrait's centre when size is adjusted.
function C.Art(token, get)
    get = get or C.Get
    if get("artwork") == "slim" then return C.SLIM_ART and C.SLIM_ART[token] end
    return C.ART[token]
end
function C.TexturePath(token)
    if not C.Art(token) then return end
    return R.PATH .. "media\\classportrait\\" .. (C.Get("artwork") == "slim" and "slim\\" or "") .. token
end
function C.Placement(token, width, height, get)
    local a = C.Art(token, get)
    if not a or width <= 0 or height <= 0 then return end
    get = get or C.Get
    local factor = get("automatic") and math.max(width / a.w, height / a.h) or 52 / math.min(a.w, a.h)
    local size = a.canvas * factor * get("size") / 100
    return size, (0.5 - a.x / a.canvas) * size + get("x"),
        (a.y / a.canvas - 0.5) * size + get("y")
end
