--[[
    Menu
    The menu frame is used to create advanced menus within the interface, allowing for submenus, icons, colors,
    and actionable entries (allow user to cast spells and use items).

    The menu appearance is configurable via the Addon Configuration.
]]
local T = unpack(Twich)

--- @type DataTextsModule
local DataTextsModule = T:GetModule("DataTexts")

--- @class Menu
local Menu = DataTextsModule.Menu or {}
DataTextsModule.Menu = Menu
