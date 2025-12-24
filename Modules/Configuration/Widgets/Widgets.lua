--[[
        Configuration Widgets
        This submodule contains generic or pre-made widgets to help keep configuration simple and uniform across the addon.
]]
local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")

--- @class Widgets
local Widgets = CM.Widgets or {}
CM.Widgets = Widgets

--- Creates a basic widget that provides blank space between other widgets.
--- @param order integer The order of the widget in the configuration.
--- @return table A configuration widget.
function Widgets:Spacer(order)
    return {
        type = "description",
        name = "",
        order = order,
        fontSize = "large",
    }
end

--- Creates a widget that provides a description for a configuration component.
--- @param order integer The order of the widget in the configuration.
--- @param text string The text to display in the description.
--- @return table A component description configuration widget.
function Widgets:ComponentDescription(order, text)
    return {
        type = "description",
        name = TM.Text.Color(TM.Colors.TWICH.TEXT_SECONDARY, CM:ColorTextKeywords(text)),
        order = order,
        fontSize = "medium",
    }
end

function Widgets:SubmoduleDescription(text)
    return {
        type = "group",
        inline = true,
        name = "",
        order = 0,
        args = {
            description = {
                type = "description",
                name = TM.Text.Color(TM.Colors.TWICH.TEXT_SECONDARY, CM:ColorTextKeywords(text)),
                order = 0,
                fontSize = "medium",
            },
            spacer = self:Spacer(1),
            configHeader = {
                type = "header",
                name = "Configuration",
                order = 2
            }
        }
    }
end

--- Creates a module group for the configuration.
--- @param order integer The order of the module group in the configuration.
--- @param moduleName string The name of the module.
--- @param moduleDescription string The description of the module.
--- @param args table The arguments for the module group.
--- @return table A module group configuration widget.
function Widgets:ModuleGroup(order, moduleName, moduleDescription, args)
    local group = {
        type = "group",
        name = TM.Text.Color(TM.Colors.TWICH.SECONDARY_ACCENT, moduleName),
        order = order,
        args = {
            _moduleDescription = {
                type = "description",
                name = TM.Text.Color(TM.Colors.TWICH.TEXT_SECONDARY, CM:ColorTextKeywords(moduleDescription)),
                order = 0,
                fontSize = "large",
            },
            _moduleSpacer = self:Spacer(0.01),
        }
    }

    if type(args) == "table" then
        for k, v in pairs(args) do
            group.args[k] = v
        end
    end

    return group
end

--- Creates a submodule group for the configuration.
--- @param order integer The order of the submodule group in the configuration.
--- @param submoduleName string The name of the submodule.
--- @param description string The description of the submodule.
--- @param args table The arguments for the submodule group.
--- @return table A submodule group configuration widget.
function Widgets:SubmoduleGroup(order, submoduleName, description, args)
    local group = {
        type = "group",
        name = TM.Text.Color(TM.Colors.TWICH.TERTIARY_ACCENT, submoduleName),
        order = order,
        childGroups = "tab",
        args = {
            _submoduleDescription = {
                type = "description",
                name = TM.Text.Color(TM.Colors.TWICH.TEXT_SECONDARY, CM:ColorTextKeywords(description)),
                order = 0,
                fontSize = "medium",
            },
            _submoduleSpacer = self:Spacer(0.01),
            _submoduleConfigurationHeader = {
                type = "header",
                name = "Configuration",
                order = 0.02
            },
            _submoduleSpacer2 = self:Spacer(0.03),
        }
    }

    if type(args) == "table" then
        for k, v in pairs(args) do
            group.args[k] = v
        end
    end

    return group
end
