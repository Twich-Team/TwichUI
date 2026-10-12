-- TwichUI: Party pins on a data bar
-- A LibDataBroker data source, "TwichUI Party Pins", for a data bar (for example EllesmereUI's "Broker
-- Plugin" block): how many pins are on your map ("5 pins, 2 party"), a short tooltip, click to open the
-- pin window and right-click for the options. It only reads; /tui pins and the options open the same
-- window without it. TwichUI doesn't bundle LibDataBroker: the object is made, once the feature is on,
-- only when a data bar addon provides the library. A data object can't be taken away again, so turned
-- off it says "Off" until the next reload.

local R = TwichUI
local PN = R.Pins
local B = {}
R.PinsBroker = B

local NAME = "TwichUI Party Pins"
local obj
local loggedIn = false

local function Enabled() return R:Enabled("partyPins") end

local function Text()
    if not Enabled() then return "Off" end
    local total, party = R.PinsWindow.Count()
    if party > 0 then return ("%d pins, %d party"):format(total, party) end
    return total == 1 and "1 pin" or ("%d pins"):format(total)
end

function B.Update() if obj then obj.text = Text() end end

local function OnTooltipShow(tip)
    local K = R.PinsLook.palette
    tip:AddLine("Party pins", 1, 1, 1)
    if not Enabled() then
        tip:AddLine("Turned off in TwichUI options (Party pins).", K.stone[1], K.stone[2], K.stone[3])
        return
    end
    local _, party = R.PinsWindow.Count()
    tip:AddDoubleLine("Local pins", tostring(PN.LocalCount()), K.textDim[1], K.textDim[2], K.textDim[3], K.text[1], K.text[2], K.text[3])
    tip:AddDoubleLine("Party pins on your map", tostring(party), K.textDim[1], K.textDim[2], K.textDim[3], K.text[1], K.text[2], K.text[3])
    local removed = PN.DismissedCount()
    if removed > 0 then
        tip:AddDoubleLine("Removed from your map", tostring(removed), K.textDim[1], K.textDim[2], K.textDim[3], K.text[1], K.text[2], K.text[3])
    end
    local why = R.PinSync.Blocked()
    if why == "paused" or why == "blocked" then tip:AddLine(PN.Reason(why), K.stone[1], K.stone[2], K.stone[3], true) end
    tip:AddLine(" ")
    tip:AddLine("Click to open your pins", K.gold[1], K.gold[2], K.gold[3])
    tip:AddLine("Right-click for options", K.stone[1], K.stone[2], K.stone[3])
end

local function OnClick(_, button)
    if GameTooltip then GameTooltip:Hide() end
    if button == "RightButton" then
        if not (InCombatLockdown and InCombatLockdown()) then R:OpenSettings("pins") end
        return
    end
    R.PinsWindow.Toggle()
end

local function Create()
    if obj or not Enabled() then return end
    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not LDB then return end
    obj = LDB:NewDataObject(NAME, {
        type = "data source",
        label = "Pins",
        text = Text(),
        icon = "Interface\\Icons\\inv_misc_map02",
        OnClick = OnClick,
        OnTooltipShow = OnTooltipShow,
    })
end

-- Whether it is on a data bar's list (false while no addon provides LibDataBroker).
function B.Available() return obj ~= nil end

-- The switch changed (Settings.lua).
function B.Refresh()
    if loggedIn then Create() end
    B.Update()
end

PN.OnChange(B.Update)
R:On("PLAYER_LOGIN", function()
    loggedIn = true
    Create()
end)
-- A data bar addon loaded on demand after login can still bring LibDataBroker.
R:On("ADDON_LOADED", function() if loggedIn and not obj then Create() end end)
