-- Attune on a data bar: an icon-only source using the same window toggle as /attune
-- and Attune's own minimap button. Its handler owns lazy creation and close cleanup.
-- Neither Attune nor LibDataBroker is required for TwichUI to load.
local R = TwichUI
local B = {}
R.AttuneBroker = B

local obj
local loggedIn = false

function B.Ready()
    return type(_G.Attune_SlashCommandHandler) == "function"
end

function B.Toggle()
    if B.Ready() then _G.Attune_SlashCommandHandler("") end
end

function B.Refresh()
    if obj or not B.Ready() then return end
    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not LDB then return end
    obj = LDB:NewDataObject("TwichUI Attune", {
        type = "data source",
        label = "Attune",
        text = "",
        icon = R.PATH .. [[media\textures\attune-broker]],
        OnClick = B.Toggle,
        OnTooltipShow = function(tip)
            tip:AddLine("Attune", 1, 1, 1)
            tip:AddLine("Click to open or close", 0.8, 0.7, 0.3)
        end,
    })
end

function B.Available() return obj ~= nil end

R:On("PLAYER_LOGIN", function()
    loggedIn = true
    B.Refresh()
end)
R:On("ADDON_LOADED", function() if loggedIn then B.Refresh() end end)
