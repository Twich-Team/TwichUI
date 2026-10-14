-- TwichUI: Forever Dungeon Journal skin
-- Gives the journal window (/fj) the EllesmereUI look through EllesmereUI's
-- skinning API: the window shell, close button, the Dungeons / Bosses /
-- Quests / Map buttons, the quest and route buttons, and the scroll bars.
-- The dungeon pages keep their own per-dungeon panels, parchment and artwork,
-- because the journal recolours them itself every time you change dungeon.
--
-- The journal builds its window once, at PLAYER_LOGIN, and keeps it (no
-- rebuilds), so we skin it once it exists and top up on every OnShow for the
-- few buttons it creates later (route steps).
--
-- Toggles: /twichui > "Skin Dungeon Journal", and EllesmereUI's own
-- Blizzard Window Skins > Third-Party Addons > TwichUI.

local R = TwichUI

local FRAME_NAME = "ForeverDungeonJournalFrame"

local S                                  -- EllesmereUI skin facade, set when EUI dispatches us
local skinned = setmetatable({}, { __mode = "k" })
local hooked = false

local function ModuleOn() return R:Enabled("foreverDungeonJournalSkin") end

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

-- The journal keeps no reference to its close button; find the stock one.
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

local SCROLLS = { "homeScroll", "bossListScroll", "lootScroll", "questListScroll", "questDetailScroll", "routeStepScroll" }
local BUTTONS = {
    "backButton", "bossesTab", "questsTab", "mapTab", "dungeonRouteButton", "routeBackButton",
    "questMapButton", "questChainButton", "questStartLinkButton", "questLeadsToButton",
}

-- Safe to repeat: every primitive is a no-op on a frame it already skinned.
local function SkinAll()
    local frame = _G[FRAME_NAME]
    if not S or not frame then return end
    if not skinned[frame] then
        skinned[frame] = true
        Call("Shell", frame)
        if frame.mainTitle then Call("White", frame.mainTitle) end
        Call("CloseButton", FindCloseButton(frame))
    end
    for _, key in ipairs(BUTTONS) do
        local button = frame[key]
        if button and not skinned[button] then
            skinned[button] = true
            -- The Bosses / Quests tabs carry an icon texture; keep it.
            Call("Button", button, { "fdjIcon" })
        end
    end
    for _, key in ipairs(SCROLLS) do SkinLegacyScrollBar(frame[key]) end
    -- Route step rows are created when a route is first opened.
    local content = frame.routeStepContent
    if content then
        for i = 1, select("#", content:GetChildren()) do
            local row = select(i, content:GetChildren())
            local button = row and row.mapButton
            if button and not skinned[button] then
                skinned[button] = true
                Call("Button", button)
            end
        end
    end
end

local function Hook()
    local frame = _G[FRAME_NAME]
    if hooked or not frame then return end
    hooked = true
    frame:HookScript("OnShow", SkinAll)
    SkinAll()
end

R:OnInit(function()
    if not ModuleOn() then return end
    -- The journal builds its window in its own PLAYER_LOGIN handler; run after it.
    R:On("PLAYER_LOGIN", function() RunNextFrame(Hook) end)
    R:On("ADDON_LOADED", function(name)
        if name == "ForeverDungeonJournal" then RunNextFrame(Hook) end
    end)
end)

R:OnSkin(function(facade)
    if not ModuleOn() then return end
    S = facade
    Hook()
    SkinAll()
end)
