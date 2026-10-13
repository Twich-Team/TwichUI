-- TwichUI: opening the settings window, and TwichUI's entry in the game's own options
-- The settings window is its own addon, TwichUI_Settings, loaded the first time it is asked for (it is
-- load-on-demand and keeps no saved variables). Everything TwichUI does in play lives here in the core addon
-- and never needs it: defaults, profiles, switches (Switches.lua) and each feature's own Get/Set.
--
--   R:OpenSettings(page, setting)  the one way to open it: loads it if needed, shows the one window (or brings
--                                  it forward), and goes to a page and a setting when named. An unknown page
--                                  opens the start page; an unknown setting opens the page at its top.
--                                  Returns true, or false and a reason code (and says why in chat).
--   R:CloseSettings(), R:ToggleSettings(page)
--   R.SettingsAnchor()             the window while it is shown, for previews that open beside it
--   R.OnSettingsClosed(fn)         fn() whenever the window closes (sample previews put themselves away)
--
-- Esc > Options > AddOns > TwichUI is a single page with a button that opens the window. It holds no settings.

local R = TwichUI
local L = { closers = {}, attempts = 0 }
R.SettingsLauncher = L
L.COMPANION = "TwichUI_Settings"

-- What the game says when it can't load an addon (C_AddOns.LoadAddOn's second value), in plain words.
local WHY = {
    MISSING = "its folder, TwichUI_Settings, is missing. Reinstall TwichUI to put it back.",
    DISABLED = "TwichUI Settings is turned off in your AddOns list. Turn it on there, then reload.",
    DEP_DISABLED = "TwichUI Settings needs TwichUI turned on in your AddOns list.",
    DEP_MISSING = "TwichUI Settings can't find TwichUI.",
    INTERFACE_VERSION = "TwichUI Settings is marked for another game version. Reinstall TwichUI, or allow out-of-date addons.",
    CORRUPT = "TwichUI Settings' files are damaged. Reinstall TwichUI.",
    INCOMPLETE = "TwichUI Settings loaded but didn't start. /tui diagnostics has the error.",
    ERROR = "the settings window ran into an error. /tui diagnostics has the details.",
    NO_API = "this game client can't load it.",
}

-- Loads the settings window's addon if it isn't loaded. Returns true, or false and a reason code.
function L.Load()
    if R.SettingsUI then return true end
    if not (C_AddOns and C_AddOns.LoadAddOn) then return false, "NO_API" end
    L.attempts = L.attempts + 1
    local ok, loaded, reason = pcall(C_AddOns.LoadAddOn, L.COMPANION)
    if not ok then
        R.Fault("settings window", loaded)
        return false, "ERROR"
    end
    if not loaded then return false, reason or "UNKNOWN" end
    if not R.SettingsUI then return false, "INCOMPLETE" end
    return true
end

function L.Explain(code)
    return "couldn't open the settings: " .. (WHY[code] or ("the game says " .. tostring(code) .. "."))
end

function R:OpenSettings(page, setting)
    local ok, why = L.Load()
    if not ok then
        L.failed = why
        if R.Life then R.Life.Note("settings-load-failed") end
        R.Print("%s", L.Explain(why))
        return false, why
    end
    L.failed = nil
    local opened, err = pcall(R.SettingsUI.Open, page, setting)
    if not opened then
        R.Fault("settings window", err)
        R.Print("%s", L.Explain("ERROR"))
        return false, "ERROR"
    end
    return true
end

function R:CloseSettings()
    if R.SettingsUI then R.SettingsUI.Close() end
end

function R:ToggleSettings(page)
    if R.SettingsUI and R.SettingsUI.IsShown() then R.SettingsUI.Close() else R:OpenSettings(page) end
end

function R.SettingsAnchor()
    local UI = R.SettingsUI
    if UI and UI.IsShown() then return UI.Frame() end
    return nil
end

function R.OnSettingsClosed(fn)
    for _, existing in ipairs(L.closers) do if existing == fn then return end end
    L.closers[#L.closers + 1] = fn
end

-- Called by the window as it hides.
function L.Closed()
    for _, fn in ipairs(L.closers) do
        local ok, err = pcall(fn)
        if not ok then R.Fault("settings closed", err) end
    end
end

-- Read only, for /tui diagnostics.
function L.Snapshot()
    local UI = R.SettingsUI
    return {
        loaded = UI ~= nil, shown = UI ~= nil and UI.IsShown() or false, attempts = L.attempts,
        failed = L.failed, launcher = L.category ~= nil,
    }
end

---------------------------------------------------------------------------
-- Esc > Options > AddOns > TwichUI: one page, one button
---------------------------------------------------------------------------
-- The game's options window is closed when TwichUI's opens, the way its own Close button does it but without
-- going back to the Game Menu. With changes of the game's own waiting to be applied, it is left open (closing
-- it would ask about them) and TwichUI's window opens in front.
local function CloseGameOptions()
    local panel = rawget(_G, "SettingsPanel")
    if not (panel and panel:IsShown()) then return end
    if panel.HasUnappliedSettings and panel:HasUnappliedSettings() then return end
    if panel.ExitWithCommit then
        panel:ExitWithCommit(true)
    elseif HideUIPanel then
        HideUIPanel(panel)
    end
end
L.CloseGameOptions = CloseGameOptions

local function BuildLauncher(frame)
    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", 7, -22)
    title:SetText("TwichUI")
    local divider = frame:CreateTexture(nil, "ARTWORK")
    if divider.SetAtlas then divider:SetAtlas("Options_HorizontalDivider", true) end
    divider:SetPoint("TOP", 0, -50)
    local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 16, -72)
    text:SetWidth(520)
    text:SetJustifyH("LEFT")
    text:SetText("TwichUI's settings have a window of their own: every option, a search, and your profile, in one place. Nothing is set on this page.")
    local function Open()
        if R:OpenSettings() then CloseGameOptions() end
    end
    local S = R.ChronicleStyle
    local button
    if S and S.Button then
        button = S.Button(frame, "Open TwichUI Settings", 200, "primary", Open)
        button:SetHeight(26)
    else
        button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(200, 26)
        button:SetText("Open TwichUI Settings")
        button:SetScript("OnClick", Open)
    end
    button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -16)
    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -10)
    hint:SetWidth(520)
    hint:SetJustifyH("LEFT")
    hint:SetText("You can also type /tui options, or right-click TwichUI in the addon list on your minimap.")
end

local function RegisterLauncher()
    if L.category or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local frame = CreateFrame("Frame")
    frame:Hide()
    local built = false
    frame:SetScript("OnShow", function(self)
        if built then return end
        built = true
        BuildLauncher(self)
    end)
    L.category = Settings.RegisterCanvasLayoutCategory(frame, "TwichUI")
    Settings.RegisterAddOnCategory(L.category)
end

R:OnInit(function()
    local ok, err = pcall(RegisterLauncher)
    if not ok then R.Fault("settings launcher", err) end
end)
