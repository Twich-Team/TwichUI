-- TwichUI: Party pins on a data bar
-- A LibDataBroker data source, "TwichUI Party Pins", for a data bar (for example EllesmereUI's "Broker
-- Plugin" block). Its text is the player's choice: how many pins are on your map ("5 pins, 2 party"), just
-- the number, the words "Map Pins", or nothing; with or without its icon, and in a color of their own
-- (pins/Look.lua, PL.Bar). When a pin arrives from another player the text says so for a few seconds, in a
-- color of its own, and then goes back. A short tooltip; click opens the pin menu (pins/BrokerMenu.lua) and right-click
-- the options. The pin window is one link away from the menu, and /tui pins opens it without any of this.
-- TwichUI doesn't bundle LibDataBroker: the object is made, once the feature is on, only when a data bar
-- addon provides the library. A data object can't be taken away again, so turned off it says "Off" until
-- the next reload.

local R = TwichUI
local PN = R.Pins
local PL = R.PinsLook
local B = {}
R.PinsBroker = B

local NAME = "TwichUI Party Pins"
local obj
local loggedIn = false

local function Enabled() return R:Enabled("partyPins") end

local ICON = R.PATH .. [[media\textures\map-pins-broker]]   -- a map with a gem-set pin and a spark (64 x 64)
local LABEL = "Map Pins"

-- A pin from another player has just arrived: for a few seconds the text says so, in its own color (and the
-- icon is tinted the same, for a data bar that removes color codes from the text). nil when not.
local flash                 -- { count, name }
local flashToken = 0        -- a newer arrival restarts the time; the older timer then does nothing
local NAME_MAX = 24         -- bytes of a pin's name shown on a data bar

local function Short(name)
    if #name <= NAME_MAX then return name end
    local cut = NAME_MAX
    -- never end inside a character: step back over continuation bytes (10xxxxxx)
    while cut > 0 and name:byte(cut + 1) and name:byte(cut + 1) >= 128 and name:byte(cut + 1) < 192 do cut = cut - 1 end
    return name:sub(1, cut) .. "..."
end

local function Text()
    if flash then
        local words = flash.count == 1 and ("New pin: " .. flash.name) or ("%d new pins"):format(flash.count)
        return ("|c%s%s|r"):format(PL.Bar.Get("flashColor"), words)
    end
    local choice = PL.Bar.Get("text")
    if choice == "none" then return "" end
    local text
    if not Enabled() then
        text = "Off"
    elseif choice == "label" then
        text = LABEL
    else
        local total, party = R.PinsWindow.Count()
        if choice == "number" then
            text = tostring(total)
        elseif party > 0 then
            text = ("%d pins, %d party"):format(total, party)
        else
            text = total == 1 and "1 pin" or ("%d pins"):format(total)
        end
    end
    -- A color code, only when the player picked a color: a data bar then keeps its own otherwise. (Some bars
    -- remove color codes from broker text; that is theirs to say.)
    if PL.Bar.Get("customColor") then return ("|c%s%s|r"):format(PL.Bar.Get("color"), text) end
    return text
end

-- No icon is nil, which a data bar reads as none. With no text the icon stays, so there is still something to click.
local function Icon()
    if PL.Bar.Get("icon") or PL.Bar.Get("text") == "none" then return ICON end
    return nil
end

function B.Update()
    if not obj then return end
    obj.text = Text()
    obj.icon = Icon()
    -- the icon's tint, a LibDataBroker convention data bars read; cleared again when the time is up
    if flash then
        obj.iconR, obj.iconG, obj.iconB = PL.Rgb(PL.Bar.Get("flashColor"))
    else
        obj.iconR, obj.iconG, obj.iconB = nil, nil, nil
    end
end

local function EndFlash()
    flashToken = flashToken + 1
    flash = nil
end

-- Pins that arrived from other players (pins/Pins.lua). Several within the time are counted together.
local function OnReceived(pins)
    if not (obj and Enabled() and PL.Bar.Get("flash")) then return end
    local n = #pins
    if n == 0 then return end
    if flash then flash.count = flash.count + n else flash = { count = n } end
    flash.name = Short(pins[n].name)
    flashToken = flashToken + 1
    local mine = flashToken
    B.Update()
    C_Timer.After(PL.Bar.Get("flashSeconds"), function()
        if mine ~= flashToken then return end
        flash = nil
        B.Update()
    end)
end

local function OnTooltipShow(tip)
    local K = R.PinsLook.palette
    tip:AddLine("Map pins", 1, 1, 1)   -- local and party pins both
    if not Enabled() then
        tip:AddLine("Turned off in TwichUI options (Party pins).", K.stone[1], K.stone[2], K.stone[3])
        return
    end
    local _, party = R.PinsWindow.Count()
    tip:AddDoubleLine("Local pins", tostring(PN.LocalCount()), K.textDim[1], K.textDim[2], K.textDim[3], K.text[1], K.text[2], K.text[3])
    tip:AddDoubleLine("Party pins on your map", tostring(party), K.textDim[1], K.textDim[2], K.textDim[3], K.text[1], K.text[2], K.text[3])
    local kept = PN.KeptCount()
    if kept > 0 then
        tip:AddDoubleLine("Kept", tostring(kept), K.textDim[1], K.textDim[2], K.textDim[3], K.text[1], K.text[2], K.text[3])
    end
    local removed = PN.DismissedCount()
    if removed > 0 then
        tip:AddDoubleLine("Removed from your map", tostring(removed), K.textDim[1], K.textDim[2], K.textDim[3], K.text[1], K.text[2], K.text[3])
    end
    local why = R.PinSync.Blocked()
    if why == "paused" or why == "blocked" then tip:AddLine(PN.Reason(why), K.stone[1], K.stone[2], K.stone[3], true) end
    tip:AddLine(" ")
    tip:AddLine("Click to manage your pins", K.gold[1], K.gold[2], K.gold[3])
    tip:AddLine("Right-click for options", K.stone[1], K.stone[2], K.stone[3])
end

local function OnClick(frame, button)
    if GameTooltip then GameTooltip:Hide() end
    if button == "RightButton" then
        if not (InCombatLockdown and InCombatLockdown()) then R:OpenSettings("pins") end
        return
    end
    R.PinsBrokerMenu.Toggle(frame)
end

local function Create()
    if obj or not Enabled() then return end
    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not LDB then return end
    obj = LDB:NewDataObject(NAME, {
        type = "data source",
        label = "Pins",
        text = Text(),
        icon = Icon(),
        OnClick = OnClick,
        OnTooltipShow = OnTooltipShow,
    })
end

-- Whether it is on a data bar's list (false while no addon provides LibDataBroker).
function B.Available() return obj ~= nil end

-- The switch changed (Switches.lua).
function B.Refresh()
    if not Enabled() then EndFlash() end
    if loggedIn then Create() end
    B.Update()
    R.PinsBrokerMenu.Refresh()
end

PN.OnChange(B.Update)
PN.OnReceived(OnReceived)
PL.Bar.Subscribe(function()
    if flash and not PL.Bar.Get("flash") then EndFlash() end   -- turned off while it shows
    B.Update()
end)
R:On("PLAYER_LOGIN", function()
    loggedIn = true
    Create()
end)
-- A data bar addon loaded on demand after login can still bring LibDataBroker.
R:On("ADDON_LOADED", function() if loggedIn and not obj then Create() end end)
