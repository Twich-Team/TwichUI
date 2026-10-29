-- TwichUI: layout packages, the core's part
-- The layout engine (package checks, composing, both adapters, the install record's rules, the developer command) is
-- an addon of its own, TwichUI_Layouts, and the setup wizard another, TwichUI_LayoutWizard (which needs the first): both
-- load on demand and keep no saved variables of their own. docs/layouts/ has the contract and the wizard's workflow.
-- Nothing of either is loaded, built or run in ordinary play. The core keeps only:
--
--   L.Load()          loads the engine if needed: true, or false and a reason code
--   L.Command(arg)    /tui layout: opens the wizard. /tui layout <word> ...: loads the engine and hands the words over
--                     (TwichUI_Layouts/Dev.lua says what they do: the developer commands)
--   L.OpenWizard(step)  loads the wizard if needed and opens it (on a step, or where it says); true, or false and a reason
--   L.OpenAuthor()    the same for the authoring workspace (/tui layout author): for the person who makes a layout
--   L.Pending()       read only: the install record's state when it waits for something that happens at a load
--                     ("applying", "applied", "restoring", "undoing"), else nil
--   L.WizardResume()  read only: "install" or "restore" when the wizard started the reload that is just finishing
--
-- And two things at a load, both only while an install record (TwichUIDB.layouts.install) says one is under way:
--   * at EllesmereUI's ADDON_LOADED, EllesmereUI.RegisterExternalInstaller("TwichUI"), so EllesmereUI's own first-run
--     picker (shown at PLAYER_LOGIN + 0.5 s on a new EllesmereUI installation) stays away while TwichUI's install is
--     being finished;
--   * after login, TwichUI_Layouts is loaded and finishes it: it checks what an install or a restore left after the
--     reload (TwichUILayouts' Continue). Nothing is applied or restored then; it only reads and reports.
-- With no record, or one that is finished, the only work here is reading one field at login. The first-install offer of
-- the wizard, and holding EllesmereUI's first run for it, are Onboarding.lua's (it uses L.RegisterInstaller and
-- L.Continued from here).

local R = TwichUI
local L = { attempts = 0 }
R.LayoutsLauncher = L
L.ADDON = "TwichUI_Layouts"
L.WIZARD = "TwichUI_LayoutWizard"
L.CONTINUE_AFTER = 3   -- seconds after login: EllesmereUI finishes its own start-up (migrations, its picker at +0.5 s) first

local WHY = {
    MISSING = "its folder, TwichUI_Layouts, is missing. Reinstall TwichUI to put it back.",
    DISABLED = "TwichUI Layouts is turned off in your AddOns list. Turn it on there, then reload.",
    DEP_DISABLED = "TwichUI Layouts needs TwichUI turned on in your AddOns list.",
    DEP_MISSING = "TwichUI Layouts can't find TwichUI.",
    INTERFACE_VERSION = "TwichUI Layouts is marked for another game version. Reinstall TwichUI, or allow out-of-date addons.",
    CORRUPT = "TwichUI Layouts' files are damaged. Reinstall TwichUI.",
    INCOMPLETE = "TwichUI Layouts loaded but didn't start. /tui diagnostics has the error.",
    ERROR = "TwichUI Layouts ran into an error while loading. /tui diagnostics has the details.",
    NO_API = "this game client can't load it.",
}

function L.Explain(code)
    return "couldn't load the layout tools: " .. (WHY[code] or ("the game says " .. tostring(code) .. "."))
end

local WIZARD_WHY = {
    MISSING = "its folder, TwichUI_LayoutWizard, is missing. Reinstall TwichUI to put it back.",
    DISABLED = "TwichUI Layout Setup is turned off in your AddOns list. Turn it on there, then reload.",
    DEP_DISABLED = "TwichUI Layout Setup needs TwichUI and TwichUI Layouts turned on in your AddOns list.",
    DEP_MISSING = "TwichUI Layout Setup needs TwichUI Layouts, and a folder is missing. Reinstall TwichUI to put it back.",
    INTERFACE_VERSION = "TwichUI Layout Setup is marked for another game version. Reinstall TwichUI, or allow out-of-date addons.",
    CORRUPT = "TwichUI Layout Setup's files are damaged. Reinstall TwichUI.",
    INCOMPLETE = "TwichUI Layout Setup loaded but didn't start. /tui diagnostics has the error.",
    ERROR = "TwichUI Layout Setup ran into an error while loading. /tui diagnostics has the details.",
    NO_API = "this game client can't load it.",
}

function L.ExplainWizard(code)
    return "couldn't open the layout setup: " .. (WIZARD_WHY[code] or ("the game says " .. tostring(code) .. "."))
end

function L.Loaded() return R.Layouts ~= nil and R.Layouts.ready == true end

local function LoadAddOn()
    return pcall(C_AddOns.LoadAddOn, L.ADDON)
end

-- Loads TwichUI_Layouts if it isn't loaded. Returns true, or false and a reason code.
function L.Load()
    if L.Loaded() then return true end
    if not (C_AddOns and C_AddOns.LoadAddOn) then return false, "NO_API" end
    L.attempts = L.attempts + 1
    local ok, loaded, reason = R.Perf.Call("layouts.load", LoadAddOn)
    if not ok then
        R.Fault("layouts", loaded)
        return false, "ERROR"
    end
    if not loaded then return false, reason or "UNKNOWN" end
    if not L.Loaded() then return false, "INCOMPLETE" end
    return true
end

-- The install record's state when a load has something to finish. Reads one field; checks only its type.
local WAITS = { applying = true, applied = true, restoring = true, undoing = true }
function L.Pending()
    local layouts = type(TwichUIDB) == "table" and TwichUIDB.layouts
    local install = type(layouts) == "table" and layouts.install
    local state = type(install) == "table" and install.state
    if type(state) == "string" and WAITS[state] then return state end
    return nil
end

---------------------------------------------------------------------------
-- The wizard
---------------------------------------------------------------------------
function L.WizardLoaded() return R.LayoutWizard ~= nil and R.LayoutWizard.ready == true end

local function LoadWizardAddOn()
    return pcall(C_AddOns.LoadAddOn, L.WIZARD)
end

-- Loads TwichUI_LayoutWizard (and, through its dependency, TwichUI_Layouts) if needed. Returns true, or false and a code.
function L.LoadWizard()
    if L.WizardLoaded() then return true end
    if not (C_AddOns and C_AddOns.LoadAddOn) then return false, "NO_API" end
    L.wizardAttempts = (L.wizardAttempts or 0) + 1
    local ok, loaded, reason = R.Perf.Call("layoutwizard.load", LoadWizardAddOn)
    if not ok then
        R.Fault("layout setup", loaded)
        return false, "ERROR"
    end
    if not loaded then return false, reason or "UNKNOWN" end
    if not L.WizardLoaded() then return false, "INCOMPLETE" end
    return true
end

-- Opens the wizard, loading it first. Says why in chat when it can't. step: where to open it (nil: where it decides).
function L.OpenWizard(step)
    local ok, why = L.LoadWizard()
    if not ok then
        L.wizardFailed = why
        R.Print("%s", L.ExplainWizard(why))
        return false, why
    end
    L.wizardFailed = nil
    local done, opened = pcall(R.LayoutWizard.Window.Open, step)
    if not done then
        R.Fault("layout setup", opened)
        -- an error part way through building or opening: put away whatever got shown (the window and its dimming), so
        -- nothing is left on screen that the player can't close
        local W = R.LayoutWizard.Window
        if W and W.Abort then pcall(W.Abort) end
        L.wizardFailed = "ERROR"
        R.Print("%s", L.ExplainWizard("ERROR"))
        return false, "ERROR"
    end
    return opened ~= false
end

-- Opens the authoring workspace (for the person who makes a layout; /tui layout author), loading the wizard's addon first. It is
-- not linked from the wizard. Says why in chat when it can't.
function L.OpenAuthor()
    local ok, why = L.LoadWizard()
    if not ok then
        L.wizardFailed = why
        R.Print("%s", L.ExplainWizard(why))
        return false, why
    end
    L.wizardFailed = nil
    local W = R.LayoutWizard.AuthorWindow
    if not W then R.Print("%s", L.ExplainWizard("INCOMPLETE")) return false, "INCOMPLETE" end
    local done, opened = pcall(W.Open)
    if not done then
        R.Fault("layout publishing", opened)
        R.Print("%s", L.ExplainWizard("ERROR"))
        return false, "ERROR"
    end
    return opened ~= false
end

-- The note the wizard leaves when the player starts a reload from it (TwichUIDB.layouts.wizard.resume): read only,
-- and only its type is checked.
function L.WizardResume()
    local layouts = type(TwichUIDB) == "table" and TwichUIDB.layouts
    local wizard = type(layouts) == "table" and layouts.wizard
    local resume = type(wizard) == "table" and wizard.resume
    if resume == "install" or resume == "restore" then return resume end
    return nil
end

function L.Command(arg)
    local word, rest = (arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word = (word or ""):lower()
    if word == "" or word == "wizard" or word == "setup" or word == "open" then
        L.OpenWizard()
        return
    end
    -- /tui layout firstrun [reset]: the first-install offer's state, or set it back to a new installation's (for testing;
    -- nothing else is touched: no install record, profile or EllesmereUI data)
    if word == "firstrun" and R.Onboarding then
        R.Onboarding.Command(rest)
        return
    end
    if word == "author" or word == "publish" then
        L.OpenAuthor()
        return
    end
    local ok, why = L.Load()
    if not ok then
        L.failed = why
        R.Print("%s", L.Explain(why))
        return
    end
    L.failed = nil
    local done, err = pcall(R.Layouts.Command, arg)
    if not done then
        R.Fault("layouts command", err)
        R.Print("%s", L.Explain("ERROR"))
    end
end

-- Read only, for /tui diagnostics.
function L.Snapshot()
    return { loaded = L.Loaded(), attempts = L.attempts, failed = L.failed, pending = L.Pending(),
        wizardLoaded = L.WizardLoaded(), wizardAttempts = L.wizardAttempts or 0, wizardFailed = L.wizardFailed,
        registered = L.registered == true }
end

---------------------------------------------------------------------------
-- EllesmereUI's partner-installer registration (EllesmereUI_Profiles.lua RegisterExternalInstaller, 9.6.8): while it
-- is set, EllesmereUI's own first-install picker stays silent this session, and its pending flag stays up until an
-- install's import lands (ImportProfile stamps EllesmereUI's first-install state). There is no way to take it back
-- within a session: it lasts until the next reload. Calls the public function only; never writes EllesmereUI's data.
-- Returns true | false, code ("no-eui", "no-api", "other-installer", "error").
---------------------------------------------------------------------------
L.INSTALLER = "TwichUI"
function L.RegisterInstaller()
    local E = rawget(_G, "EllesmereUI")
    if type(E) ~= "table" then return false, "no-eui" end
    if type(E.RegisterExternalInstaller) ~= "function" then return false, "no-api" end
    local other = rawget(E, "_externalInstaller")
    if other ~= nil and other ~= L.INSTALLER then return false, "other-installer" end
    if L.registered then return true end
    local ok, err = pcall(E.RegisterExternalInstaller, L.INSTALLER)
    if not ok then R.Fault("layouts EllesmereUI installer", err) return false, "error" end
    L.registered = true
    return true
end

-- True once the check after a reload has run this session (or there was none to run).
function L.Continued() return L.continued == true or not L.Pending() end

-- True from the moment this login scheduled the check after a reload until it has run: the result is not final yet (the wizard says
-- the setup is still being checked, rather than that a reload is waiting).
function L.CheckPending() return L.scheduled == true and L.continued ~= true end

---------------------------------------------------------------------------
-- At a load, only while an install is under way
---------------------------------------------------------------------------
local function Continue()
    if not L.Pending() then L.continued = true return end
    local ok, why = L.Load()
    if not ok then
        L.continued = true
        L.failed = why
        R.Print("a layout install waits to be checked, but %s", L.Explain(why))
        return
    end
    local done, err = pcall(R.Layouts.Continue)
    L.continued = true
    if not done then R.Fault("layouts continue", err) return end
    -- The player started this reload from the wizard: show the result (once). A reload the player made themselves
    -- gets the chat line only, and the wizard stays closed until it is asked for (a first-install setup still under
    -- way is Onboarding.lua's to reopen).
    if L.WizardResume() then L.OpenWizard() end
end

local function KeepPickerAway(name)
    if name ~= "EllesmereUI" then return end
    local state = L.Pending()
    if state ~= "applying" and state ~= "applied" then return end
    L.RegisterInstaller()
end

R:On("ADDON_LOADED", KeepPickerAway)
-- EllesmereUI loads after TwichUI (the folder name sorts first), so the line above sees it. Should it ever have loaded
-- first, its ADDON_LOADED came before TwichUI's saved data: look once, now.
R:OnInit(function()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EllesmereUI") then KeepPickerAway("EllesmereUI") end
end)
R:On("PLAYER_LOGIN", function()
    if not L.Pending() then return end
    L.scheduled = true
    C_Timer.After(L.CONTINUE_AFTER, Continue)
end)
