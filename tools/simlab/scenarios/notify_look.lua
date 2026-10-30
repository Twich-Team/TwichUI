-- Simulator lab scenario (docs/simulator-lab.md): the "Notification appearance" page, driven through its real
-- controls. interact.sh runs it from a clean synthetic profile (--no-saved-vars, an empty WTF folder).
--
-- Why this page: the whole page is appearance (no gameplay action, no other addon, no combat rule, no protected
-- frame), it has one control of each kind (a drop-down, a checkbox, sliders with a range), and it has a greyed-out
-- state to test: a card's settings are locked until "Give this card its own look" is on. Values land in
-- TwichUIDB.ui.notifyLook* through modules/NotifyLook.lua.
--
-- Expected values below are typed from the page's source (NotifyLook.lua: DEFAULTS, LIMITS, LABELS), not read from
-- it, so a changed default fails here instead of agreeing with itself.
local R = TwichUI
local NL = R.NotifyLook
local function UI() return R.SettingsUI end   -- the companion loads on the first open
local PAGE = "notificationsLook"
local Check, Step, Row = Lab.Check, Lab.Step, Lab.Row

local function Ui() return TwichUIDB and TwichUIDB.ui or {} end
local function Saved(key) return Ui()[key] end
local function Text(v) return v.control.text:GetText() end
local function Box(v) return v.control.box:GetText() end

A_Admin.SetManualClock(GetTime())

-- This page has nothing to do with a party, so the character is solo (interact.sh starts the simulator with
-- WOW_SIM_NO_PARTY=1), and the scenario checks it (the sample party would otherwise bring TwichUI's group hello into a
-- settings test). Lab.Solo() leaves a party if there is one and is a no-op otherwise. The group case is not
-- avoided: diagnose.sh runs it on purpose. WatchSends only records; it calls the simulator's own function.
local group = Lab.Solo()
Lab.WatchSends()

local scope, own, scale, outline, view, rowCount

Step("initial", function()
    local life = R.Life and R.Life.Snapshot() or {}
    Check("init", "saved variables ready", "ready", life.savedVariables)
    Check("init", "config ready", true, life.configReady)
    Check("init", "no failed hook", 0, life.hookFailures)
    Check("init", "solo: the game reports no group", false, group.inGroup)
    Check("init", "solo: no members counted, none seen by TwichUI", "0/0", group.count .. "/" .. group.twichMembers)
    -- a clean synthetic start: nothing of this page is saved yet
    for _, key in ipairs({ "notifyLook", "notifyLookArrival", "notifyLookTraining", "notifyLookFriend", "notifyLookWelcome" }) do
        Check("init", "clean start: ui." .. key, nil, Saved(key))
    end

    local ok, why, v = Lab.Open(PAGE)
    Check("construct", "R:OpenSettings(" .. PAGE .. ") opened", true, ok)
    Check("construct", "the page is the one selected", PAGE, (UI().Selected()))
    Check("construct", "the page has a drawn view", true, v ~= nil)
    Check("construct", "the window finished fading in", 1, UI().Frame():GetAlpha())
    view = v
    scope, own = Row(PAGE, "notifyLookScope"), Row(PAGE, "notifyLookOwn")
    scale, outline = Row(PAGE, "notifyLookTextScale"), Row(PAGE, "notifyLookOutline")
    rowCount = 0
    for _ in pairs(view.rows) do rowCount = rowCount + 1 end
    Check("construct", "the page drew rows", true, rowCount > 10)

    Check("state", "initial: scope shows the shared look", "Shared look (all cards)", Text(scope))
    Check("state", "initial: text size box", "100", Box(scale))
    Check("state", "initial: text size slider", 100, scale.control.slider:GetValue())
    Check("state", "initial: text size range", "80-140",
        select(1, scale.control.slider:GetMinMaxValues()) .. "-" .. select(2, scale.control.slider:GetMinMaxValues()))
    Check("state", "initial: outline shows the default", "Shadow (default)", Text(outline))
    Check("state", "initial: text size is editable", true, scale.control.slider:IsEnabled())
    Check("state", "initial: 'own look' row is hidden while editing the shared look", false, Lab.RowShown(own))
    Lab.Reveal(PAGE, "notifyLookTextScale")   -- scroll only, so the screenshot shows the text size and outline rows
end)

Step("choose a card", function()
    local ok, why = Lab.PickChoice(scope, "arrival")
    Check("interact", "scope list opened and the card was picked", true, ok)
    Check("interact", "the list closed after the pick", false, Lab.MenuShown())
    Check("state", "scope is the Zone arrival card", "arrival", NL.Scope())
    Check("state", "scope shows its label", "Zone arrival", Text(scope))
    Check("state", "choosing saved nothing", nil, Saved("notifyLookArrival"))
    Check("state", "'own look' row is now shown", true, Lab.RowShown(own))
    Check("state", "'own look' starts off", false, own.control:GetChecked())
    -- a card that follows the shared look cannot be edited: the controls are locked and refuse input
    Check("state", "locked: slider disabled", false, scale.control.slider:IsEnabled())
    Check("state", "locked: it still shows the shared value", "100", Box(scale))
    Lab.TypeInBox(scale, "120")
    Check("state", "locked: typed 120 is refused (nothing saved)", nil, Saved("notifyLookArrival"))
    Check("state", "locked: the card still draws 100", 100, NL.Get("arrival", "textScale"))
    Check("state", "locked: the box goes back to 100", "100", Box(scale))
end)

Step("toggle own look", function()
    Lab.ClickCheckbox(own)
    Check("interact", "checkbox shows checked", true, own.control:GetChecked())
    Check("state", "NotifyLook.Own('arrival')", true, NL.Own("arrival"))
    local t = Saved("notifyLookArrival") or {}
    Check("state", "saved own flag", true, t.own)
    Check("state", "saved a complete look: textScale", 100, t.textScale)
    Check("state", "saved a complete look: outline", "shadow", t.outline)
    Check("state", "shared look not written", nil, Saved("notifyLook"))
    Check("state", "unlocked: slider enabled", true, scale.control.slider:IsEnabled())
    Check("state", "scope label gains '(own look)'", "Zone arrival (own look)", Text(scope))
end)

Step("slider and number box", function()
    Lab.TypeInBox(scale, "500")
    Check("state", "slider-clamp-max: typed 500 saved as", 140, (Saved("notifyLookArrival") or {}).textScale)
    Check("state", "slider-clamp-max: box shows", "140", Box(scale))
    Check("state", "slider-clamp-max: slider value", 140, scale.control.slider:GetValue())
    Lab.TypeInBox(scale, "10")
    Check("state", "slider-clamp-min: typed 10 saved as", 80, (Saved("notifyLookArrival") or {}).textScale)
    Lab.SetSlider(scale, 120)
    Check("state", "slider-drag: set to 120 saved as", 120, (Saved("notifyLookArrival") or {}).textScale)
    Check("state", "slider-drag: box shows", "120", Box(scale))
    Lab.TypeInBox(scale, "abc")
    Check("state", "slider-junk: typed text leaves 120", 120, (Saved("notifyLookArrival") or {}).textScale)
    Check("state", "slider-junk: box goes back to 120", "120", Box(scale))
    -- the model's own refusal (not a control): an out-of-range value is rejected, not clamped
    Check("state", "model refuses 500 (NotifyLook.Set)", false, NL.Set("arrival", "textScale", 500))
    Check("state", "model refusal left 120", 120, NL.Get("arrival", "textScale"))
    Check("state", "shared look still not written", nil, Saved("notifyLook"))
    Check("state", "shared text size still 100", 100, NL.Shared("textScale"))
end)

Step("dropdown", function()
    local ok = Lab.PickChoice(outline, "thick")
    Check("interact", "outline list opened and 'thick' was picked", true, ok)
    Check("state", "saved outline", "thick", (Saved("notifyLookArrival") or {}).outline)
    Check("state", "outline shows its label", "Thick outline", Text(outline))
    Check("state", "shared outline unchanged", "shadow", NL.Shared("outline"))
end)

Step("close and reopen", function()
    local before = UI().Stats().drawn
    UI().Close()
    Check("interact", "window closed", false, UI().IsShown())
    -- changed behind the window's back while it is shut: reopening must show what is in memory, not what it drew last
    Check("state", "model set while closed", true, NL.Set("arrival", "textScale", 90))
    local ok, why, v = Lab.Open(PAGE)
    Check("construct", "reopened", true, ok)
    Check("construct", "same drawn page reused (no second copy)", true, v == view)
    Check("construct", "pages drawn unchanged", before, UI().Stats().drawn)
    local rows = 0
    for _ in pairs(v.rows) do rows = rows + 1 end
    Check("construct", "same number of rows", rowCount, rows)
    Check("state", "reopen: text size box matches memory", tostring(NL.Get("arrival", "textScale")), Box(scale))
    Check("state", "reopen: text size box shows 90", "90", Box(scale))
    Check("state", "reopen: outline matches memory", "Thick outline", Text(outline))
    Check("state", "reopen: 'own look' checked", true, own.control:GetChecked())
    Check("state", "reopen: scope label", "Zone arrival (own look)", Text(scope))
    local t = Saved("notifyLookArrival") or {}
    -- compared between runs by the runner: the same start must give the same end
    Lab.Say("digest", Lab.Digest(t))
    Lab.Say("digest-shared", tostring(Saved("notifyLook")))
    Lab.Reveal(PAGE, "notifyLookTextScale")
end)

-- The window crosses the timers that used to be kept out of reach (see lib.lua): TwichUI's group hello (about 3 s) and
-- Blizzard's voice-settings ticker (about 4.5 s and 9.5 s). Solo, the hello's timer still runs and sends nothing; the
-- ticker's error is classified by the runner (known_failures.py). The page must be exactly as the last step left it.
Step("time passes", function()
    local saved = Lab.Digest(Saved("notifyLookArrival") or {})
    local steps = Lab.RunUntil((P and P.window) or 12, 0.5)
    Lab.Say("clock", "simSeconds=" .. Lab.simSeconds, "advanceSteps=" .. steps)
    Check("state", "time passes: no addon message was attempted while solo", 0, #Lab.sends)
    Check("state", "time passes: the saved look is unchanged", saved, Lab.Digest(Saved("notifyLookArrival") or {}))
    Check("state", "time passes: the window is still shown", true, UI().IsShown())
    Check("state", "time passes: the text size box still shows 90", "90", Box(scale))
    Check("state", "time passes: the group is still solo", false, IsInGroup())
end)

Lab.Finish()
