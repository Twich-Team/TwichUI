-- TwichUI: WhatsTraining skin
-- Gives WhatsTraining's windows the EllesmereUI look through EllesmereUI's
-- skinning API: the floating window (/wt, and the Broker click on Forever)
-- with its grouping popup, and the ledger panel it adds to the spellbook.
-- The spellbook panel already picks EllesmereUI's dark colours by itself;
-- this covers its search box, dropdowns, page buttons and scroll bars.
--
-- WhatsTraining builds the floating window on first use and keeps no global
-- to hook, so we watch the two ways it is opened (the /wt command and the
-- Broker object's click) and skin once the frame exists. The spellbook panel
-- is skinned whenever the spellbook page is shown.
--
-- Toggles: /twichui > "Skin WhatsTraining", and EllesmereUI's own
-- Blizzard Window Skins > Third-Party Addons > TwichUI.

local R = TwichUI

local FRAME_NAME = "WhatsTrainingFloatingFrame"
local POPUP_NAME = FRAME_NAME .. "GroupingPopup"

local S                                  -- EllesmereUI skin facade, set when EUI dispatches us
local skinned = setmetatable({}, { __mode = "k" })
local hooked = false

local function ModuleOn() return R:Enabled("whatsTrainingSkin") end

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

-- FauxScrollFrameTemplate uses the old UIPanelScrollBarTemplate (Slider with
-- ScrollUp/ScrollDownButton and a ThumbTexture), which S.ScrollBar doesn't
-- recognise. Flatten it to the same thin white thumb by hand.
local function SkinLegacyScrollBar(scroll)
    local bar = scroll and scroll.ScrollBar
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

local function SkinPopup(popup)
    if not popup or skinned[popup] then return end
    skinned[popup] = true
    popup:SetBackdrop(nil)
    Call("Panel", popup)
    for _, region in ipairs({ popup:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then Call("White", region) end
    end
    -- Radio buttons keep Blizzard's round art; only their labels change.
    for _, radio in ipairs(popup.radios or {}) do
        local text = radio.text or radio.Text
        if text then Call("White", text) end
    end
    local showKnown = _G[POPUP_NAME .. "ShowKnown"]
    if showKnown then
        Call("Checkbox", showKnown)
        local text = showKnown.text or showKnown.Text
        if text then Call("White", text) end
    end
    local done = _G[POPUP_NAME .. "Done"]
    if done then
        Call("Button", done)
        Call("StateButtonLabel", done)
    end
end

local function SkinWindow()
    local frame = _G[FRAME_NAME]
    if not S or not frame or skinned[frame] then return end
    skinned[frame] = true
    Call("Shell", frame)
    if frame.Title then Call("White", frame.Title) end
    Call("CloseButton", _G[FRAME_NAME .. "Close"])
    Call("EditBox", frame.searchBox)
    Call("Button", frame.weaponSkillToggleButton, { "Icon" })
    Call("Button", frame.groupingButton, { "Icon" })
    SkinLegacyScrollBar(frame.scrollBar)
    SkinPopup(frame.groupingPopup)
end

-- The settings dropdown is a 15x16 arrow button, not a wide dropdown, so it
-- is skinned as a flat button (S.Dropdown would add an arrow anchored for a
-- wide box). Blizzard's Icon texture is swapped for EllesmereUI's white
-- arrow, centred; its mouse-down nudge keeps working since it moves the Icon.
local function SkinArrowDropdown(dropdown)
    if not dropdown or skinned[dropdown] then return end
    skinned[dropdown] = true
    Call("Button", dropdown, { "Icon" })
    local icon = dropdown.Icon
    if icon then
        icon:SetAtlas("Azerite-PointingArrow")
        icon:SetSize(12, 8)
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", dropdown, "CENTER", 0, 0)
        icon:SetVertexColor(1, 1, 1, 0.9)
    end
end

local function SkinPage(page)
    if not page or not page.scrollFrame then return end
    Call("ScrollBar", page.scrollFrame.ScrollBar)
end

local function SkinSpellBook()
    local main = _G.WhatsTrainingFrame
    if not S or not main or not main.pagingControls or skinned[main] then return end
    skinned[main] = true
    Call("EditBox", main.searchBox)
    SkinArrowDropdown(main.displayDropdown)
    local arrow = main.priceDropdown
    if arrow then
        for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
            local texture = arrow[getter] and arrow[getter](arrow)
            if texture then texture:SetDesaturated(true) end
        end
    end
    local controls = main.pagingControls
    Call("PageButton", controls.PrevPageButton, "<")
    Call("PageButton", controls.NextPageButton, ">")
    SkinPage(main)
    SkinPage(main.weaponPage)
end

local function Install()
    if hooked then return end
    hooked = true
    -- Both entry points build the frame before returning, so a post-hook sees it.
    if SlashCmdList and SlashCmdList.WHATSTRAINING then
        hooksecurefunc(SlashCmdList, "WHATSTRAINING", SkinWindow)
    end
    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    local object = ldb and ldb:GetDataObjectByName("WhatsTraining")
    if object and type(object.OnClick) == "function" then
        hooksecurefunc(object, "OnClick", SkinWindow)
    end
    SkinWindow()   -- in case the window already exists
end

local owner = {}
local function HookSpellBook()
    -- Fires from the spellbook's own Show, after WhatsTraining has built its panel.
    EventRegistry:RegisterCallback("PlayerSpellsFrame.SpellBookFrame.Show", function()
        RunNextFrame(SkinSpellBook)
    end, owner)
end

R:OnInit(function()
    if not ModuleOn() then return end
    R:On("ADDON_LOADED", function(name)
        if name == "WhatsTraining" then Install() end
    end)
    HookSpellBook()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("WhatsTraining") then Install() end
end)

R:OnSkin(function(facade)
    if not ModuleOn() then return end
    S = facade
    SkinWindow()
    SkinSpellBook()
end)
