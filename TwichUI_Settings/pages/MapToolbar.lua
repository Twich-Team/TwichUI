-- TwichUI settings: Map Toolbar (pins/MapTools.lua). The bar in the world map's title row: its switch, and what its
-- buttons need. The pins, pings and shortcuts the buttons use are set on Pins and Pings; nothing here changes them.

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "mapToolbar", name = "Map Toolbar", order = 71, group = "map",
    description = "The bar in the world map's title row, with buttons for your pins, group pins, group pings and navigation.",
    keywords = "toolbar tool bar tools buttons help group pin ping navigate navigation title row",
    when = function() return R.Pins ~= nil and R.PinsLook ~= nil end,
    build = function()
        local PL = R.PinsLook
        local Header, ProxyToggle, Under = K.Header, K.ProxyToggle, K.Under
        local function PinsOn() return R:Enabled("partyPins") end

        Header("Map tools bar", "Buttons for a personal pin, a group pin, a group ping, Navigate (only while Navigation is on) and Help. The bar is part of Party pins and is greyed out while that is off. The group tools need a party or raid, and the group ping also needs Map pings and Send pings with the gesture, both on Pins and Pings. A button that can't be used says why when the pointer is on it.")
        local bar = Under(ProxyToggle("pinsToolbar", "Show the map tools bar",
            "A small bar in the world map's title row, beside the navigation, with buttons for a personal pin, a group pin and a group ping, and a Help button, so none of the clicks above has to be remembered. A button arms the tool; the next plain click on the map uses it once, and Esc cancels. The shortcuts keep working either way. Group tools show as unavailable, with the reason, while you are not in a group.\n\nOff: the bar is gone and nothing else changes.",
            PL.PREF_DEFAULTS.toolbar, function() return PL.Pref("toolbar") end, function(value) PL.SetPref("toolbar", value and true or false) end),
            K.switchRows.partyPins, PinsOn)

        Header("NPC search", "A search field on the bar for the vendors, trainers and services in your own list. It looks only at what you have noted or been sent (Vendors and trainers), never at the world.")
        Under(ProxyToggle("pinsNpcSearch", "Show NPC search",
            "Search your collected knowledge and locate known NPCs on the map.\n\nA field on the map tools bar, off until you turn it on. Type a name or a role (innkeeper, alchemy) and the nearest matches are listed, with the area and, when it can be told, a straight-line distance (not a walking distance). Choosing one takes the map to its area and rings its marker for a moment. That sets no waypoint or route and sends nothing, and an NPC your marker choices hide is shown only while it is picked out.\n\nThe field never takes the keyboard until you click it. It is left out when the map's title row is too narrow for it.\n\nOff: the field is gone and the bar is as it was.",
            PL.PREF_DEFAULTS.npcSearch, function() return PL.Pref("npcSearch") end, function(value) PL.SetPref("npcSearch", value and true or false) end),
            bar, function() return PinsOn() and PL.Pref("toolbar") and R:Enabled("npcMap") end,
            function()
                if not R:Enabled("npcMap") then return "Greyed out: needs Vendors and trainers turned on, which holds the NPCs this searches." end
                if not PinsOn() then return "Greyed out: needs Party pins turned on, which the map tools bar is part of." end
                return "Greyed out: needs \"Show the map tools bar\" turned on."
            end)
    end,
})
