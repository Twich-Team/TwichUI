-- TwichUI: Game Menu button for TwichUI Settings
-- Adds a "TwichUI" button to the Game Menu (Escape) that opens the TwichUI settings window.
-- This is always available (no toggle needed) since it's a core feature.
--
-- The GameMenuFrame rebuilds its buttons every time it is shown or its store/trial state changes
-- (InitButtons -> Reset releases the whole pool) and only then lays them out. We add ours from
-- a hook on InitButtons, from the same button pool, so it is there for that one layout (and for
-- skinning addons hooking the same function after us), the game clears it on the next rebuild
-- and it can never be duplicated. A button has a layoutIndex and the frame lays them out (and sizes
-- itself) when marked dirty; AddButton marks it, and so do we. We slot ours in after the last of AddOns / Edit Mode / Support / Macros by shifting the later buttons'
-- indices by one, which keeps whatever other addons added.

local R = TwichUI
local Q = R.QoL
local K = {}
R.QoLTwichUISettingsButton = K

K.LABEL = "TwichUI"
local attached = false
local button

local function OpenSettings()
    if GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
    R:OpenSettings()
end

-- The button the new one follows: the last of the menu's utility group (AddOns, Edit Mode, Support,
-- Macros) that is present, which sits just above the Log Out section. Matched by text since the
-- menu has no keys.
local function FindAfter(menu)
    local names = { [_G.ADDONS] = true, [_G.HUD_EDIT_MODE_MENU] = true, [_G.GAMEMENU_SUPPORT] = true, [_G.MACROS] = true }
    local last
    for existing in menu.buttonPool:EnumerateActive() do
        if existing ~= button and existing.layoutIndex and names[existing:GetText()]
            and (not last or existing.layoutIndex > last.layoutIndex) then last = existing end
    end
    return last
end

function K.Remove()
    local menu = GameMenuFrame
    if button and menu and menu.buttonPool and menu.buttonPool:IsActive(button) then
        local at = button.layoutIndex
        menu.buttonPool:Release(button)
        for existing in menu.buttonPool:EnumerateActive() do
            if at and existing.layoutIndex and existing.layoutIndex > at then existing.layoutIndex = existing.layoutIndex - 1 end
        end
        if menu.nextLayoutIndex and menu.nextLayoutIndex > 1 then menu.nextLayoutIndex = menu.nextLayoutIndex - 1 end
        if menu.MarkDirty then menu:MarkDirty() end
    end
    button = nil
end

-- Runs each time the Game Menu has built its buttons, before it lays them out.
function K.OnMenuShown()
    local menu = GameMenuFrame
    button = nil     -- the game released last time's with the rest of its pool
    if not (menu and menu.buttonPool) then return end
    local after = FindAfter(menu)
    if not after then return end
    button = menu.buttonPool:Acquire()
    local index = after.layoutIndex + 1
    for existing in menu.buttonPool:EnumerateActive() do
        if existing ~= button and existing.layoutIndex and existing.layoutIndex >= index then existing.layoutIndex = existing.layoutIndex + 1 end
    end
    if menu.nextLayoutIndex then menu.nextLayoutIndex = menu.nextLayoutIndex + 1 end
    button.layoutIndex = index
    button.topPadding = nil
    button:SetText(K.LABEL)
    button:SetScript("OnClick", OpenSettings)
    button:SetMotionScriptsWhileDisabled(true)
    button:Show()
end

-- Hooked once (a hook can't be removed); the button is always shown.
local function Attach()
    if attached or not (GameMenuFrame and GameMenuFrame.InitButtons) then return end
    attached = true
    hooksecurefunc(GameMenuFrame, "InitButtons", K.OnMenuShown)
end

function K.Stop() K.Remove() end

K.feature = Q.Add({
    key = "qolTwichUISettingsButton",
    Events = function()
        Attach()
        return { PLAYER_LOGIN = Attach }
    end,
    Stop = K.Stop,
})