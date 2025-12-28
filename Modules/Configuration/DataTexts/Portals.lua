local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")
--- @type LoggerModule
local LM = T:GetModule("Logger")

-- WoW globals
local _G = _G
local tinsert = tinsert
local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local select = select
local sort = table.sort

--- @type DataTextsConfigurationModule
local DT = CM.DataTexts or {}
CM.DataTexts = DT

--- @class PortalsDataTextConfigurationModule
local PDT = DT.Portals or {}
DT.Portals = PDT

function PDT:Create()
    ---@return PortalsDataText module
    local function GetModule()
        return T:GetModule("DataTexts").Portals
    end

    local options = {
        displayGroup = {
            type = "group",
            name = "Display",
            inline = true,
            order = 1,
            args = {
                description = CM.Widgets:ComponentDescription(1,
                    "Configure the Portals datatext menu, including which hearthstone is shown first."),
                favoriteHearthstone = {
                    type = "select",
                    name = "Favorite Hearthstone",
                    desc = "If set and available, this hearthstone appears first in the menu.",
                    order = 2,
                    width = "full",
                    values = function()
                        local values = { [0] = "None" }
                        local map = GetModule():GetAvailableHearthstones() or {}

                        local ids = {}
                        for itemID, _ in pairs(map) do
                            tinsert(ids, itemID)
                        end
                        sort(ids, function(a, b)
                            return tostring(map[a] or "") < tostring(map[b] or "")
                        end)

                        for _, itemID in ipairs(ids) do
                            local itemName = map[itemID]
                            local icon
                            if _G.C_Item and _G.C_Item.GetItemIconByID then
                                icon = _G.C_Item.GetItemIconByID(itemID)
                            end
                            if not icon and _G.C_Item and _G.C_Item.GetItemInfo then
                                icon = select(10, _G.C_Item.GetItemInfo(itemID))
                            end

                            if icon then
                                values[itemID] = ("|T%s:14:14|t %s"):format(icon, itemName)
                            else
                                values[itemID] = itemName
                            end
                        end
                        return values
                    end,
                    get = function()
                        local v = CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration()
                            .FAVORITE_HEARTHSTONE_ID)
                        return v or 0
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().FAVORITE_HEARTHSTONE_ID,
                            value or 0)
                    end,
                },
                hideTipText = {
                    type = "toggle",
                    name = "Hide Tip Text",
                    desc = "Hides the footer tip at the bottom of the Portals menu.",
                    order = 3,
                    width = "full",
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().HIDE_TIP_TEXT)
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().HIDE_TIP_TEXT, value and true
                            or false)
                    end,
                },
                color = CM.Widgets:DatatextColorSelectorGroup(
                    5,
                    GetModule():GetConfiguration().COLOR_MODE,
                    GetModule():GetConfiguration().CUSTOM_COLOR,
                    function()
                        GetModule():Refresh()
                    end
                ),
            }
        }
    }

    return options
end
