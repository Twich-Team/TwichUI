-- TwichUI: the data bar entry
-- A LibDataBroker launcher, "TwichUI", for a data bar (for example EllesmereUI's "Broker Plugin" block). A left click
-- opens its menu (modules/SettingsBrokerMenu.lua): Open settings, the Quiet the screen and Leave me alone switches, and
-- the Guild Locations choices; a second left click closes it. A right click opens the settings window directly, through R:OpenSettings
-- (SettingsLauncher.lua), which loads the window if needed and brings it forward when it is already open; it keeps the
-- page it was left on. Without the menu code a left click opens the settings too. The text never changes and nothing is
-- saved here: the menu's rows read and write the core's own state (qol/QoL.lua, guildloc/State.lua).
-- The icon follows three states, read each time from their own owners (nothing is stored here): Leave me alone
-- (R.QoL.LeaveAloneOn), Quiet the screen (R.QuietScreen.On) and Guild Locations not sharing the player's own position
-- (R.GuildLoc.State: Invisible or Off). None: the compass; exactly one: that mode's icon; two or three: the shield with
-- the crescent. A state whose owner is not loaded, or whose saved data is unavailable (held), counts as not active.
-- Made once, at login or when a data bar addon that provides LibDataBroker loads later. TwichUI doesn't bundle
-- LibDataBroker: nothing happens without it, and nothing here is needed to open the settings.

local R = TwichUI
local B = {}
R.SettingsBroker = B

local NAME = "TwichUI"
local obj
local loggedIn = false

local TEX = R.PATH .. [[media\textures\twichui-broker-]]
local hooked = false

-- Which of the three modes are active now. Owners load after this file, so they are looked up when asked.
local function Modes()
    local m = {}
    if R.QoL and R.QoL.LeaveAloneOn and R.QoL.LeaveAloneOn() then m[#m + 1] = "leave" end
    if R.QuietScreen and R.QuietScreen.On() then m[#m + 1] = "quiet" end
    local GL = R.GuildLoc
    if GL then
        local state, why = GL.State()
        -- "held" / "not-ready": the saved choice cannot be read, so it is unknown, not a decision to hide.
        if (state == "invisible" or state == "off") and why ~= "held" and why ~= "not-ready" then m[#m + 1] = "location" end
    end
    return m
end
B.Modes = Modes

local MODE_FILE = { leave = "leave-alone", quiet = "quiet", location = "location" }
local MODE_NAME = { leave = "Leave me alone", quiet = "Quiet the screen", location = "Guild Locations hidden" }

function B.IconFor(m)
    if #m == 0 then return TEX .. "compass" end
    if #m == 1 then return TEX .. MODE_FILE[m[1]] end
    return TEX .. "multiple"
end

-- Recomputed from all three every time; only sets the icon when it differs.
function B.UpdateIcon()
    if not obj then return end
    local icon = B.IconFor(Modes())
    if obj.icon ~= icon then obj.icon = icon end
end

local LABEL = { sharing = "Sharing", invisible = "Invisible", off = "Off" }

local function OnTooltipShow(tip)
    tip:AddLine("TwichUI", 1, 1, 1)
    tip:AddLine("Left-click for the menu.", 0.8, 0.7, 0.3)
    tip:AddLine("Right-click to open settings.", 0.8, 0.7, 0.3)
    if R.QuietScreen then
        tip:AddLine("Quiet screen: " .. (R.QuietScreen.On() and "On" or "Off") .. ".", 0.62, 0.58, 0.51)
    end
    if R.QoL and R.QoL.LeaveAloneOn then
        tip:AddLine("Leave me alone: " .. (R.QoL.LeaveAloneOn() and "On" or "Off") .. ".", 0.62, 0.58, 0.51)
    end
    local GL = R.GuildLoc
    if GL then
        local state, why = GL.State()
        tip:AddLine("Guild Locations: " .. (why == "held" and "unavailable" or LABEL[state] or "Off") .. ".", 0.62, 0.58, 0.51)
    end
    local m = Modes()
    if #m > 0 then
        local names = {}
        for _, k in ipairs(m) do names[#names + 1] = MODE_NAME[k] end
        tip:AddLine("Active: " .. table.concat(names, ", ") .. ".", 0.9, 0.8, 0.5)
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
        icon = B.IconFor(Modes()),   -- the compass, a mode's icon or the combined shield (64 x 64)
        OnClick = B.OnClick,
        OnTooltipShow = OnTooltipShow,
    })
    B.Hook()
end

-- The owners' own change callbacks, once: Quiet the screen, Guild Locations, and the switches behind Leave me alone
-- (settings, the menu, commands, profile changes all end in one of these).
function B.Hook()
    if hooked then return end
    hooked = true
    if R.QuietScreen and R.QuietScreen.OnChange then R.QuietScreen.OnChange(B.UpdateIcon) end
    if R.GuildLoc and R.GuildLoc.OnChange then R.GuildLoc.OnChange(B.UpdateIcon) end
    if R.Switches and R.Switches.OnChange then R.Switches.OnChange(B.UpdateIcon) end
end

-- Whether it is on a data bar's list (false while no addon provides LibDataBroker).
function B.Available() return obj ~= nil end

R:On("PLAYER_LOGIN", function()
    loggedIn = true
    B.Refresh()
end)
-- A data bar addon loaded on demand after login can still bring LibDataBroker.
R:On("ADDON_LOADED", function() if loggedIn and not obj then B.Refresh() end end)
