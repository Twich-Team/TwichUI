local T, W, I, C = unpack(Twich)
--- Precise typings for the Tools module to satisfy Lua diagnostics and enable
--- autocompletion across the addon.
--- @class TextTool
--- @field Color fun(hex:string, text:string):string
--- @field ColorRGB fun(r:number, g:number, b:number, text:string):string
--- @field CreateIconStr fun(iconPath:string):string
--- @field ResolveIconPath fun(self:any, primaryPath:string, fallbackPath:string):string
--- @field ColorByClass fun(classFile:string, text:string):string
--- @field ColorByFaction fun(faction:string, text:string):string
--- @field PrintToChatFrame fun(text:string)

--- @class CallbackInstance
--- @field Register fun(self:any, func:function):number
--- @field Unregister fun(self:any, id:number)
--- @field Invoke fun(self:any, ...:any)

--- @class CallbackPrototype
--- @field Prototype table
--- @field New fun():CallbackInstance

--- @class ToolsModule
--- @field Money MoneyTool
--- @field Callback CallbackPrototype\
--- @field Textures TexturesTool
--- @field Game GameTool
local TM = T:GetModule("Tools")

--- @class GenericsTool
--- @field Module GenericModule
--- @field Cache GenericCache
local Generics = TM.Generics or {}
TM.Generics = Generics

local _G = _G
