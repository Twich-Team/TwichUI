-- TwichUI: Quality of Life, Quick Keybind button
-- Adds a "Quick Keybind" button to the Game Menu (Escape) that opens the game's own Quick Keybind
-- Mode. Off until turned on. It is only a shortcut: the mode, its instructions, Okay / Cancel /
-- Reset to Default and every binding change are the game's.
--
-- What the game gives us (WoW: Forever UI source):
--   Blizzard_QuickKeybind creates QuickKeybindFrame (a protected frame); showing it is the mode:
--   KeybindFrames_InQuickKeybindMode() is just QuickKeybindFrame:IsShown(). Both of the game's own
--   entry points (Settings > Keybindings > Quick Keybind Mode, and the Edit Mode action bar
--   button) end in QuickKeybindFrame:Show(), so that is what we call. Nothing is bound by
--   entering; bindings change only through the frame's own key handling, and Cancel reloads the
--   saved ones. When the frame hides, the game opens the Settings panel again unless the Game
--   Menu is up; that is the game's normal way out and is left as it is.
--   GameMenuFrame rebuilds its buttons every time it is shown or its store/trial state changes
--   (InitButtons -> Reset releases the whole pool) and only then lays them out. We add ours from
--   a hook on InitButtons, from the same button pool, so it is there for that one layout (and for
--   skinning addons hooking the same function after us), the game clears it on the next rebuild
--   and it can never be duplicated. A button has a layoutIndex and the frame lays them out (and sizes
--   itself) when marked dirty; AddButton marks it, and so do we. We slot ours in after the last of AddOns / Edit Mode / Support / Macros by shifting the later buttons'
--   indices by one, which keeps whatever other addons added.
--
-- Combat: the frame is protected, so it can't be shown from addon code in combat. The button is
-- disabled in combat (with the reason as its tooltip) and re-enabled when combat ends. Nothing
-- bypasses that. If the frame doesn't exist in the client, no button is added.

local R = TwichUI
local Q = R.QoL
local K = {}
R.QoLQuickKeybind = K

K.LABEL = "Quick Keybind"
local attached = false
local button

-- Is Quick Keybind Mode there to enter? Asks the game to load its addon if it hasn't yet.
function K.Available()
    if not QuickKeybindFrame and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_QuickKeybind") end
    return QuickKeybindFrame ~= nil and type(QuickKeybindFrame.Show) == "function"
end

local function Click()
    if InCombatLockdown() or not K.Available() then return end
    if GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
    QuickKeybindFrame:Show()
end

local function ShowCombatReason(self)
    local tooltip = GetAppropriateTooltip and GetAppropriateTooltip() or GameTooltip
    tooltip:SetOwner(self, "ANCHOR_RIGHT")
    tooltip:SetText(K.LABEL)
    tooltip:AddLine("Not available in combat.", 1, 0.2, 0.2)
    tooltip:Show()
end

local function HideTooltip()
    local tooltip = GetAppropriateTooltip and GetAppropriateTooltip() or GameTooltip
    tooltip:Hide()
end

-- Enabled out of combat; in combat it looks off and says why.
function K.Refresh()
    if not button then return end
    if InCombatLockdown() then
        button:SetEnabled(false)
        button:SetScript("OnEnter", ShowCombatReason)
        button:SetScript("OnLeave", HideTooltip)
    else
        button:SetEnabled(true)
        button:SetScript("OnEnter", nil)
        button:SetScript("OnLeave", nil)
    end
end

-- The button the new one follows: the last of the menu's utility group (AddOns, Edit Mode, Support,
-- Macros) that is present, which sits just above the Log Out section. Matched by text since the
-- menu has no keys. Not Options: addons that hand-place their own button under Options (EllesmereUI)
-- push everything below it by a fixed amount that assumes a section gap there.
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
    if not (R:Enabled("qolQuickKeybind") and menu and menu.buttonPool and K.Available()) then return end
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
    button:SetScript("OnClick", Click)
    button:SetMotionScriptsWhileDisabled(true)
    button:Show()
    K.Refresh()
end

-- Hooked once (a hook can't be removed); K.OnMenuShown does nothing while the feature is off.
local function Attach()
    if attached or not (GameMenuFrame and GameMenuFrame.InitButtons) then return end
    attached = true
    hooksecurefunc(GameMenuFrame, "InitButtons", K.OnMenuShown)
end

function K.Stop() K.Remove() end

K.feature = Q.Add({
    key = "qolQuickKeybind",
    Events = function()
        Attach()
        return { PLAYER_LOGIN = Attach, PLAYER_REGEN_DISABLED = K.Refresh, PLAYER_REGEN_ENABLED = K.Refresh }
    end,
    Stop = K.Stop,
})
