local T, W, I, C = unpack(Twich)
---@type ToolsModule
local TM = T:GetModule("Tools")

--- Callback typing for diagnostics
--- @class CallbackInstance
--- @field Register fun(self:any, func:function):number
--- @field Unregister fun(self:any, id:number)
--- @field Invoke fun(self:any, ...:any)

--- @class CallbackPrototype
--- @field New fun():CallbackInstance


-- Generic callback container
-- Usage:
-- local cb = TM.Callback.New()
-- local id = cb:Register(function(...) end)
-- cb:Invoke(...)
-- cb:Unregister(id)

local Callback = {}
Callback.__index = Callback

--- Create a new Callback object
function Callback:New()
    local o = setmetatable({}, self)
    o._nextId = 0
    o._callbacks = {}
    return o
end

--- Register a callback function. Returns an id that can be used to unregister.
---@param func function
---@return number id
function Callback:Register(func)
    if type(func) ~= "function" then error("Callback:Register requires a function") end
    self._nextId = self._nextId + 1
    local id = self._nextId
    self._callbacks[id] = func
    return id
end

--- Unregister a previously registered callback by id.
---@param id number
function Callback:Unregister(id)
    if not id then return end
    self._callbacks[id] = nil
end

--- Invoke all registered callbacks with supplied arguments.
--- If a callback errors, it will be caught and logged but other callbacks continue.
function Callback:Invoke(...)
    for id, fn in pairs(self._callbacks) do
        local ok, err = pcall(fn, ...)
        if not ok then
            if T and T.Logger and T.Logger.Error then
                T.Logger.Error(("Callback id=%s error: %s"):format(tostring(id), tostring(err)))
            end
        end
    end
end

-- expose into Tools module
TM.Callback = TM.Callback or {}
TM.Callback.Prototype = Callback
TM.Callback.New = function() return Callback:New() end
