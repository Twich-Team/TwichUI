-- TwichUI: Attune skin
-- Gives Attune's windows the EllesmereUI look through EllesmereUI's skinning
-- API: the main window (/attune), the quest-reward side panel and the quest
-- detail panel, with their buttons, close buttons and scroll bars.
-- The attunement tree, the detail pane and the node graph are built from
-- AceGUI widgets and Attune's own textures and keep their own look.
--
-- Attune builds every one of these frames lazily (the main window on the
-- first /attune, the side panels on the first quest click) and keeps them,
-- so we post-hook the functions that build them and skin what exists.
--
-- Toggles: /twichui > "Skin Attune", and EllesmereUI's own
-- Blizzard Window Skins > Third-Party Addons > TwichUI.

local R = TwichUI

local S                                  -- EllesmereUI skin facade, set when EUI dispatches us
local skinned = setmetatable({}, { __mode = "k" })
local hooked = false

local function ModuleOn() return R:Enabled("attuneSkin") end

local function Call(kind, ...)
    local fn = S and S[kind]
    if fn then pcall(fn, ...) end
end

local function FadeTextures(frame)
    for i = 1, select("#", frame:GetRegions()) do
        local region = select(i, frame:GetRegions())
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then region:SetAlpha(0) end
    end
end

-- UIPanelScrollFrameTemplate uses the old UIPanelScrollBarTemplate (Slider
-- with ScrollUp/ScrollDownButton and a ThumbTexture), which S.ScrollBar
-- doesn't recognise. Flatten it to the same thin white thumb by hand.
local function SkinLegacyScrollBar(scroll)
    if not scroll then return end
    local bar = scroll.ScrollBar
    if not bar and scroll.GetName and scroll:GetName() then bar = _G[scroll:GetName() .. "ScrollBar"] end
    if not bar or skinned[bar] then return end
    skinned[bar] = true
    for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
        local button = bar[key]
        if button then
            for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
                local texture = button[getter] and button[getter](button)
                if texture then texture:SetAlpha(0) end
            end
        end
    end
    FadeTextures(bar)
    local thumb = bar.ThumbTexture
    if thumb then
        thumb:SetTexCoord(0, 1, 0, 1)
        thumb:SetColorTexture(1, 1, 1, 0.3)
        thumb:SetSize(4, 24)
    end
end

-- Attune keeps no reference to most of its stock buttons, so find the
-- UIPanelButtonTemplate ones (they carry Left/Middle/Right art) among a
-- frame's children.
local function SkinStockButtons(parent)
    if not parent then return end
    for i = 1, select("#", parent:GetChildren()) do
        local child = select(i, parent:GetChildren())
        if child and not skinned[child] and child:GetObjectType() == "Button"
            and (child.Left or child.Middle or child.Right) then
            skinned[child] = true
            Call("Button", child)
            Call("StateButtonLabel", child)
        end
    end
end

-- UIPanelCloseButton has no key either; it is the one using the minimize art.
local function FindCloseButton(frame)
    for i = 1, select("#", frame:GetChildren()) do
        local child = select(i, frame:GetChildren())
        if child and child:GetObjectType() == "Button" then
            local normal = child:GetNormalTexture()
            local path = normal and normal:GetTexture()
            if type(path) == "string" and path:lower():find("minimizebutton", 1, true) then return child end
        end
    end
end

-- Attune draws the window border on a PortraitFrameTemplate frame laid over
-- the AceGUI window. Skin that frame: fade its border and portrait, put the
-- EllesmereUI shell on it.
local function SkinMainWindow()
    local chrome = _G.AttuneBronzeChrome
    if not chrome or skinned[chrome] then return end
    skinned[chrome] = true
    Call("Shell", chrome)
    Call("FadeNineSlice", chrome.NineSlice)
    if chrome.Inset then Call("Inset", chrome.Inset) end
    for _, key in ipairs({ "PortraitContainer", "portrait" }) do
        local piece = chrome[key]
        if piece and piece.SetAlpha then piece:SetAlpha(0) end
    end
    local title = chrome.TitleContainer and chrome.TitleContainer.TitleText or chrome.TitleText
    if title then Call("White", title) end
    Call("CloseButton", chrome.CloseButton)
    SkinStockButtons(chrome:GetParent())
end

-- Same ButtonFrameTemplate chrome, without a portrait, around the reward panel.
local function SkinRewardPanel()
    local panel = _G.AttuneQuestRewardFrame
    local chrome = panel and panel.bronze
    if not chrome or skinned[chrome] then return end
    skinned[chrome] = true
    Call("Shell", chrome)
    Call("FadeNineSlice", chrome.NineSlice)
    if chrome.Inset then Call("Inset", chrome.Inset) end
    local title = chrome.TitleContainer and chrome.TitleContainer.TitleText or chrome.TitleText
    if title then Call("White", title) end
    Call("CloseButton", chrome.CloseButton)
    if panel.title then Call("White", panel.title) end
    if panel.urlBtn then
        skinned[panel.urlBtn] = true
        Call("Button", panel.urlBtn)
        Call("StateButtonLabel", panel.urlBtn)
    end
    SkinLegacyScrollBar(panel.scroll)
end

local function SkinDetailPanel()
    local panel = _G.AttuneQuestDetail
    if not panel or skinned[panel] then return end
    skinned[panel] = true
    panel:SetBackdrop(nil)
    Call("Panel", panel)
    if panel.title then Call("White", panel.title) end
    Call("CloseButton", FindCloseButton(panel))
    local map = panel.map
    if map then
        map:SetBackdrop(nil)
        Call("Panel", map, { inset = true })
        SkinStockButtons(map)   -- the zoom buttons
    end
end

local function SkinAll()
    if not S then return end
    SkinMainWindow()
    SkinRewardPanel()
    SkinDetailPanel()
end

local function Install()
    if hooked then return end
    hooked = true
    for _, name in ipairs({ "Attune_Frame", "Attune_ShowQuestRewards", "Attune_ShowQuestDetail" }) do
        if type(_G[name]) == "function" then hooksecurefunc(name, SkinAll) end
    end
    SkinAll()   -- in case the windows already exist
end

R:OnInit(function()
    if not ModuleOn() then return end
    R:On("ADDON_LOADED", function(name)
        if name == "Attune" then Install() end
    end)
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Attune") then Install() end
end)

R:OnSkin(function(facade)
    if not ModuleOn() then return end
    S = facade
    Install()
    SkinAll()
end)
