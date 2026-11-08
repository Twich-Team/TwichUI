-- TwichUI: the data bar entry
-- A LibDataBroker launcher, "TwichUI", for a data bar (for example EllesmereUI's "Broker Plugin" block). A left click
-- opens its menu (modules/SettingsBrokerMenu.lua): Open settings, the Leave me alone switch, and the Guild Locations
-- choices; a second left click closes it. A right click opens the settings window directly, through R:OpenSettings
-- (SettingsLauncher.lua), which loads the window if needed and brings it forward when it is already open; it keeps the
-- page it was left on. Without the menu code a left click opens the settings too. The text never changes and nothing is
-- saved here: the menu's rows read and write the core's own state (qol/QoL.lua, guildloc/State.lua).
-- Made once, at login or when a data bar addon that provides LibDataBroker loads later. TwichUI doesn't bundle
-- LibDataBroker: nothing happens without it, and nothing here is needed to open the settings.

local R = TwichUI
local B = {}
R.SettingsBroker = B

local NAME = "TwichUI"
local obj
local loggedIn = false

local LABEL = { sharing = "Sharing", invisible = "Invisible", off = "Off" }

local function OnTooltipShow(tip)
    tip:AddLine("TwichUI", 1, 1, 1)
    tip:AddLine("Left-click for the menu.", 0.8, 0.7, 0.3)
    tip:AddLine("Right-click to open settings.", 0.8, 0.7, 0.3)
    if R.QoL and R.QoL.LeaveAloneOn then
        tip:AddLine("Leave me alone: " .. (R.QoL.LeaveAloneOn() and "On" or "Off") .. ".", 0.62, 0.58, 0.51)
    end
    local GL = R.GuildLoc
    if GL then
        local state, why = GL.State()
        tip:AddLine("Guild Locations: " .. (why == "held" and "unavailable" or LABEL[state] or "Off") .. ".", 0.62, 0.58, 0.51)
    end
end

function B.OnClick(frame, button)
    if button == "LeftButton" then
        local menu = R.SettingsBrokerMenu
        if menu then
            if GameTooltip then GameTooltip:Hide() end   -- it would sit over the menu
            menu.Toggle(frame)
        else
            R:OpenSettings()
        end
    elseif button == "RightButton" then
        R:OpenSettings()
    end
end

-- Once, when a data bar addon provides LibDataBroker.
function B.Refresh()
    if obj then return end
    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not LDB then return end
    obj = LDB:NewDataObject(NAME, {
        type = "launcher",
        label = "TwichUI",
        text = "TwichUI",
        icon = R.PATH .. [[media\textures\twichui-broker]],   -- the TwichUI badge (64 x 64)
        OnClick = B.OnClick,
        OnTooltipShow = OnTooltipShow,
    })
end

-- Whether it is on a data bar's list (false while no addon provides LibDataBroker).
function B.Available() return obj ~= nil end

R:On("PLAYER_LOGIN", function()
    loggedIn = true
    B.Refresh()
end)
-- A data bar addon loaded on demand after login can still bring LibDataBroker.
R:On("ADDON_LOADED", function() if loggedIn and not obj then B.Refresh() end end)
