local T = unpack(Twich)
--- @type ToolsModule
local Tools = T:GetModule("Tools")

local CreateFrame = CreateFrame

---@class GenericModule
---@field enabled boolean
---@field frame Frame|nil the frame used to register events
---@field CONFIGURATION table<string, ConfigEntry> configuration entries for this module
---@field EVENTS table<string> event names to register
local GenericModule = Tools.Generics.Module or {}
Tools.Generics.Module = GenericModule

---Initialize a new module with the given configuration and events
---@param CONFIGURATION table<string, ConfigEntry> configuration entries for this module
---@param EVENTS table<string>|nil event names to register
---@return GenericModule module the initialized module
function GenericModule:New(CONFIGURATION, EVENTS)
    local module = {
        enabled = false,
        frame = nil,
        CONFIGURATION = CONFIGURATION,
        EVENTS = EVENTS or {},
    }
    setmetatable(module, { __index = self })
    return module
end

---@return boolean whether the module is enabled
function GenericModule:IsEnabled()
    return self.enabled
end

---@param eventHandler function the event handler function to call when events are triggered
function GenericModule:Enable(eventHandler)
    if self.enabled then return end

    -- clear the frame if for some reason it still exists
    if self.frame then
        self:_ClearFrame(self.frame)
        self.frame = nil
    end

    self.enabled = true

    if #self.EVENTS > 0 and eventHandler then
        for _, event in ipairs(self.EVENTS) do
            if not self.frame then
                self.frame = CreateFrame("Frame")
            end
            self.frame:RegisterEvent(event)
        end
        self.frame:SetScript("OnEvent", eventHandler)
    end
end

---@param onDisableLogic function|nil optional function to run during disable
function GenericModule:Disable(onDisableLogic)
    if not self.enabled then return end

    -- clear the frame if for some reason it still exists
    if self.frame then
        self:_ClearFrame(self.frame)
        self.frame = nil
    end

    self.enabled = false

    if onDisableLogic then
        onDisableLogic()
    end
end

---@param frame Frame the frame to clear events from
function GenericModule:_ClearFrame(frame)
    if not frame then return end
    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", nil)
end

Tools.Generics.Module = GenericModule

return GenericModule
