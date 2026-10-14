-- TwichUI: Journey Chronicle, data bar source
-- Publishes the Chronicle as a LibDataBroker data object so a data bar (for
-- example EllesmereUI's "Broker Plugin" block) can show it. TwichUI doesn't
-- bundle LibDataBroker: the object is made once the library exists, and
-- nothing happens when it never does.

local R = TwichUI
local C = R.Chronicle
local Broker = {}
R.ChronicleBroker = Broker

local NAME = "TwichUI Chronicle"
local obj

local function Latest()
    local entries = C.Entries()
    return entries[#entries]
end

local function OnTooltipShow(tip)
    tip:AddLine("Journey Chronicle", 1, 1, 1)
    tip:AddLine(C.CharKey(), 0.8, 0.8, 0.8)
    local count = C.Count()
    tip:AddLine(count == 1 and "1 entry" or (count .. " entries"), 0.8, 0.8, 0.8)
    local last = Latest()
    if last then tip:AddLine("Latest: " .. last.title, 0.8, 0.8, 0.8) end
    if not R:Enabled("chronicle") then tip:AddLine("Automatic entries are off.", 0.6, 0.6, 0.6) end
    tip:AddLine("Click to open", 0.8, 0.7, 0.3)
end

local function Create()
    if obj then return end
    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not LDB then return end
    obj = LDB:NewDataObject(NAME, {
        type = "data source",
        label = "Chronicle",
        icon = (R.ChronicleStyle and R.ChronicleStyle.icons.start) or R.ICON,
        text = "Journey Chronicle",
        OnClick = function()
            if R.ChronicleWindow then R.ChronicleWindow:Toggle() end
        end,
        OnTooltipShow = OnTooltipShow,
    })
end

R:On("ADDON_LOADED", function(name) if name == "EllesmereUI" then Create() end end)
R:On("PLAYER_LOGIN", Create)
