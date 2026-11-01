-- TwichUI: settings launcher for a data bar
-- A LibDataBroker launcher, "TwichUI", for a data bar (for example EllesmereUI's "Broker Plugin" block). A left click
-- opens the settings window through R:OpenSettings (SettingsLauncher.lua), which loads the window if needed and brings
-- it forward when it is already open; it keeps the page it was left on. A right click opens the Guild Locations menu
-- (guildloc/State.lua is the only authority on the choice; this file keeps no state of its own): Sharing or Invisible,
-- and a way to its settings page. Without the game's MenuUtil, a right click opens that page instead. No text that
-- changes, no saved state.
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
    tip:AddLine("Left-click to open settings.", 0.8, 0.7, 0.3)
    local GL = R.GuildLoc
    if GL then
        local state, why = GL.State()
        tip:AddLine("Right-click for Guild Locations (" .. (why == "held" and "unavailable" or LABEL[state] or "Off") .. ").", 0.8, 0.7, 0.3)
    end
end

-- The Guild Locations menu. Sharing and Invisible go through GL.SetState, the same call the settings page makes. While
-- the feature is Off, or its saved data is held, they are not offered: the menu never turns sharing on from Off. Outside a
-- guild they stay selectable (a privacy choice does not need a guild).
function B.BuildMenu(root)
    local GL = R.GuildLoc
    root:CreateTitle("Guild Locations")
    local state, why = GL.State()
    if state == "off" then
        local line = root:CreateButton(why and "Unavailable right now" or "Off", function() end)
        if line and line.SetEnabled then line:SetEnabled(false) end
        if not why then
            root:CreateButton("Turn on in settings...", function() R:OpenSettings("guildLocations") end)
        end
    else
        for _, choice in ipairs({ { "sharing", "Sharing my location" }, { "invisible", "Invisible (still see others)" } }) do
            local value = choice[1]
            root:CreateRadio(choice[2], function() return GL.State() == value end, function() GL.SetState(value) end)
        end
    end
    root:CreateButton("Guild Locations settings...", function() R:OpenSettings("guildLocations") end)
end

function B.OnClick(frame, button)
    if button == "LeftButton" then
        R:OpenSettings()
    elseif button == "RightButton" and R.GuildLoc then
        if MenuUtil and MenuUtil.CreateContextMenu and frame then
            MenuUtil.CreateContextMenu(frame, function(_, root) B.BuildMenu(root) end)
        else
            R:OpenSettings("guildLocations")
        end
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
