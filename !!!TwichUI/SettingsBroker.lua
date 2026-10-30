-- TwichUI: settings launcher for a data bar
-- A LibDataBroker launcher, "TwichUI", for a data bar (for example EllesmereUI's "Broker Plugin" block). A left click
-- opens the settings window through R:OpenSettings (SettingsLauncher.lua), which loads the window if needed and brings
-- it forward when it is already open; it keeps the page it was left on. Nothing else: no menu, no right-click, no text
-- that changes, no saved state.
-- Made once, at login or when a data bar addon that provides LibDataBroker loads later. TwichUI doesn't bundle
-- LibDataBroker: nothing happens without it, and nothing here is needed to open the settings.

local R = TwichUI
local B = {}
R.SettingsBroker = B

local NAME = "TwichUI"
local obj
local loggedIn = false

local function OnTooltipShow(tip)
    tip:AddLine("TwichUI", 1, 1, 1)
    tip:AddLine("Left-click to open settings.", 0.8, 0.7, 0.3)
end

function B.OnClick(_, button)
    if button ~= "LeftButton" then return end
    R:OpenSettings()
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
