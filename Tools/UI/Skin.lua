---@diagnostic disable-next-line: undefined-global
local T = unpack(Twich)

---@type ToolsModule|table
local TM = T:GetModule("Tools")

---@class ToolsUI
---@field GetElvUISkins fun():any|nil
---@field SkinCloseButton fun(btn:Button|nil)
---@field SkinScrollBar fun(scrollFrameOrSlider:any)
---@field SkinEditBox fun(editBox:EditBox|nil)
---@field SkinButton fun(btn:Button|nil)
local UI = TM.UI or {}
TM.UI = UI

local _G = _G

---@return any|nil skins
function UI.GetElvUISkins()
    ---@diagnostic disable-next-line: undefined-field
    local E = _G.ElvUI and _G.ElvUI[1]
    if not E or not E.GetModule then
        return nil
    end

    local ok, skins = pcall(E.GetModule, E, "Skins", true)
    if ok then
        return skins
    end
    return nil
end

---@param scrollFrameOrSlider any
---@return any|nil
local function ResolveScrollBar(scrollFrameOrSlider)
    if not scrollFrameOrSlider then
        return nil
    end

    -- Direct slider
    if type(scrollFrameOrSlider.GetObjectType) == "function" then
        local ok, objType = pcall(scrollFrameOrSlider.GetObjectType, scrollFrameOrSlider)
        if ok and objType == "Slider" then
            return scrollFrameOrSlider
        end
    end

    -- Standard ScrollFrame templates
    local sb = scrollFrameOrSlider.ScrollBar
    if sb then
        return sb
    end

    -- Fallback: named template scrollbar ("<ScrollFrameName>ScrollBar")
    if type(scrollFrameOrSlider.GetName) == "function" then
        local name = scrollFrameOrSlider:GetName()
        if name then
            return _G[name .. "ScrollBar"]
        end
    end

    return nil
end

---@param btn Button|nil
function UI.SkinCloseButton(btn)
    local skins = UI.GetElvUISkins()
    if skins and skins.HandleCloseButton and btn then
        pcall(skins.HandleCloseButton, skins, btn)
    end
end

---@param scrollFrameOrSlider any
function UI.SkinScrollBar(scrollFrameOrSlider)
    local skins = UI.GetElvUISkins()
    if not skins or not skins.HandleScrollBar then
        return
    end

    local sb = ResolveScrollBar(scrollFrameOrSlider)
    if sb then
        pcall(skins.HandleScrollBar, skins, sb)
    end
end

---@param editBox EditBox|nil
function UI.SkinEditBox(editBox)
    local skins = UI.GetElvUISkins()
    if skins and skins.HandleEditBox and editBox then
        pcall(skins.HandleEditBox, skins, editBox)
    end
end

---@param btn Button|nil
function UI.SkinButton(btn)
    local skins = UI.GetElvUISkins()
    if skins and skins.HandleButton and btn then
        pcall(skins.HandleButton, skins, btn)
    end
end

return UI
