-- BugSack on a data bar. Match its native broker's current-session error count;
-- delegate opening and clearing to BugSack, which owns the error data and window.
local R = TwichUI
local B = {}
R.BugSackBroker = B

local obj
local loggedIn = false

local function Sack()
    local sack, grabber = _G.BugSack, _G.BugGrabber
    if type(sack) ~= "table" or type(grabber) ~= "table" then return end
    if type(sack.GetErrors) ~= "function" or type(sack.UpdateDisplay) ~= "function"
        or type(sack.OpenSack) ~= "function" or type(sack.Reset) ~= "function"
        or type(grabber.GetSessionId) ~= "function" then return end
    return sack, grabber
end

local function Update()
    local sack, grabber = Sack()
    if not obj or not sack then return end
    obj.text = tostring(#sack:GetErrors(grabber:GetSessionId()))
end

local function OnUpdate()
    if R.Perf then R.Perf.Call("bugsack.broker.update", Update) else Update() end
end

local function OnClick(_, button)
    local sack = Sack()
    if not sack then return end
    if button == "RightButton" then
        sack:Reset()
    elseif button == "LeftButton" then
        sack:OpenSack()
    end
end

function B.Refresh()
    if obj then return end
    local sack = Sack()
    if not sack or not hooksecurefunc then return end
    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not LDB then return end
    obj = LDB:NewDataObject("TwichUI BugSack", {
        type = "data source",
        label = "BugSack",
        text = "0",
        icon = [[Interface\AddOns\BugSack\Media\icon]],
        OnClick = OnClick,
        OnTooltipShow = function(tip)
            tip:AddLine("BugSack", 1, 1, 1)
            tip:AddLine("Distinct bugs in the current session: " .. obj.text, 0.8, 0.8, 0.8)
            tip:AddLine("Left-click to open", 0.8, 0.7, 0.3)
            tip:AddLine("Right-click to clear all stored bugs", 0.8, 0.7, 0.3)
        end,
    })
    hooksecurefunc(sack, "UpdateDisplay", OnUpdate)
    OnUpdate()
end

function B.Available() return obj ~= nil end

R:On("PLAYER_LOGIN", function()
    loggedIn = true
    B.Refresh()
end)
R:On("ADDON_LOADED", function() if loggedIn then B.Refresh() end end)
