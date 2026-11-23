-- Read-only adapter for EllesmereUI 9.9.1, commit 8abfcbf6afa4129369cdc9fb5e03e96d1fdd94e5.
-- Source links, lifecycle and supported fields: docs/design/execute-range.md.
-- No provider code is copied; no settings, unit attributes or provider regions are written.
local R = TwichUI
local E = {}
R.ExecuteRangeEllesmere = E
function E.Plain(value) return not (issecretvalue and issecretvalue(value)) end
local function Frame(frame)
    return E.Plain(frame) and type(frame) == "table" and type(frame.GetObjectType) == "function"
        and type(frame.GetParent) == "function" and type(frame.IsShown) == "function"
        and type(frame.GetWidth) == "function" and type(frame.GetHeight) == "function"
        and not (frame.IsForbidden and frame:IsForbidden())
end
local function Bar(bar, owner)
    if not Frame(bar) or type(bar.CreateTexture) ~= "function" or type(bar.HookScript) ~= "function"
        or type(bar.GetOrientation) ~= "function" or type(bar.GetReverseFill) ~= "function" then return end
    local kind = bar:GetObjectType()
    if not E.Plain(kind) or kind ~= "StatusBar" then return end
    -- EUI can put target.Health inside its clipping frame; direct parent equality is insufficient.
    local parent = bar
    for _ = 1, 6 do
        if parent == owner then return bar end
        parent = parent:GetParent()
        if not Frame(parent) then return end
    end
end
function E.Enemy(unit)
    if not UnitCanAttack then return false end
    local enemy = UnitCanAttack("player", unit)
    return E.Plain(enemy) and enemy == true
end
function E.Target()
    local frame = _G.EllesmereUIUnitFrames_Target
    if not Frame(frame) or type(frame.GetAttribute) ~= "function" then return end
    local unit = frame:GetAttribute("unit")
    if not E.Plain(unit) or unit ~= "target" then return end
    return Bar(frame.Health, frame), frame
end
function E.NameplateToken(unit)
    return E.Plain(unit) and type(unit) == "string" and #unit <= 16 and unit:match("^nameplate%d+$") ~= nil
end
function E.Registry()
    local ns = _G.EllesmereNameplates_NS
    if E.Plain(ns) and type(ns) == "table" and E.Plain(ns.plates) and type(ns.plates) == "table" then return ns.plates end
end
function E.Nameplate(unit)
    if not E.NameplateToken(unit) or not E.Enemy(unit) then return end
    local registry = E.Registry()
    local plate = registry and registry[unit]
    if not Frame(plate) or not E.Plain(plate.unit) or plate.unit ~= unit then return end
    local base = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not Frame(base) or not E.Plain(plate.nameplate) or plate.nameplate ~= base then return end
    local token = base.namePlateUnitToken
    if not E.Plain(token) or token ~= unit then return end
    return Bar(plate.health, plate), plate
end
function E.Geometry(bar)
    local w, h, orientation, reverse = bar:GetWidth(), bar:GetHeight(), bar:GetOrientation(), bar:GetReverseFill()
    if not E.Plain(w) or not E.Plain(h) or not E.Plain(orientation) or not E.Plain(reverse) then return end
    if type(w) ~= "number" or type(h) ~= "number" or w ~= w or h ~= h
        or w <= 0 or h <= 0 or w == math.huge or h == math.huge then return end
    if orientation ~= "HORIZONTAL" and orientation ~= "VERTICAL" then return end
    if type(reverse) ~= "boolean" then return end
    return w, h, orientation, reverse
end
-- Never compare, format, persist or perform arithmetic with restricted health.
-- The marker remains useful when the client withholds health from addon Lua.
function E.InRange(unit, threshold)
    if not UnitHealth or not UnitHealthMax then return end
    local health, maximum = UnitHealth(unit), UnitHealthMax(unit)
    if not E.Plain(health) or not E.Plain(maximum) then return end
    if type(health) ~= "number" or type(maximum) ~= "number" or health ~= health or maximum ~= maximum
        or health < 0 or maximum <= 0 or health > maximum or maximum == math.huge then return end
    return health > 0 and health / maximum <= threshold / 100
end
