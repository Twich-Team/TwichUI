-- Real pages, synthetic Mage/profile, handler-level input only. No game actions or real SavedVariables.
local R = TwichUI
local params = SIMLAB_PARAMS or {}
local key = params.page or "overview"
A_Admin.SetManualClock(GetTime())
Lab.Solo()
UnitClass = function() return "Mage", "MAGE" end
TwichUIDB.ui.settingsWindow = { w = params.narrow and 936 or 1240, h = params.narrow and 660 or 960 }
Lab.Step("open", function()
    Lab.Check("init", "open settings", true, Lab.Open(key))
    local K, UI = R.SettingsKit, R.SettingsUI
    Lab.Check("construct", "selected page", key, UI.Selected())
    for _, page in ipairs(K.NavOrder()) do
        Lab.Say("inventory", page.key, page.name, "rows=" .. #page.rows, "host=" .. tostring(page.def.host ~= nil))
    end
end)
Lab.Step("disclosures and navigation", function()
    local K, UI, W = R.SettingsKit, R.SettingsUI, R.SettingsWidgets
    local view = assert(UI.View(key))
    local changed = #K.Changed()
    Lab.Check("construct", "fixed heading", true, view.chrome ~= nil and view.chrome:IsShown())
    if view.tabs then
        for _, button in ipairs({ view.tabs:GetChildren() }) do
            if button.text and button.text.GetStringWidth then
                Lab.Check("construct", "tab label fits " .. button.text:GetText(), true,
                    button.text:GetStringWidth() <= button.text:GetWidth() + .1)
            end
        end
    end
    for _, section in ipairs(view.sections) do
        if section.toggle then
            local initial = section.expanded
            section.toggle:Click()
            Lab.Check("interact", "disclosure opens " .. section.id, not initial, section.expanded)
            section.toggle:Click()
            Lab.Check("interact", "disclosure restores " .. section.id, initial, section.expanded)
            local target = section.rows[1]
            if target then
                UI.Navigate(key, target.row.id)
                Lab.Check("interact", "direct reveal " .. target.row.id, true, section.expanded)
                section.expanded = initial
            end
        end
    end
    for _, row in ipairs(K.pages[key].rows) do
        local v = view.rows[row.id]
        if v and row.kind == "dropdown" and row:Shown() and row:Enabled() then
            UI.Navigate(key, row.id)
            v.control:Click()
            Lab.Check("interact", "dropdown opens " .. row.id, true, W.MenuShown())
            W.CloseMenu()
            Lab.Check("interact", "dropdown closes " .. row.id, false, W.MenuShown())
            break
        end
    end
    local result = R.SettingsSearch.Run(K.pages[key].name)[1]
    Lab.Check("construct", "page searchable", true, result ~= nil)
    UI.SetQuery("zzzznoexistingfeaturezzzz")
    Lab.Check("interact", "empty search", 0, #R.SettingsSearch.Run("zzzznoexistingfeaturezzzz"))
    UI.SetQuery("")
    UI.Navigate(key)
    local drawn = UI.Stats().drawn
    UI.Close(); UI.Open(key)
    Lab.Check("construct", "reopening reuses page", view, UI.View(key))
    Lab.Check("construct", "no extra page", drawn, UI.Stats().drawn)
    Lab.Check("state", "navigation preserves settings", changed, #K.Changed())
    -- Restore the initial disclosure pose for screenshots; search can reveal a folded row.
    for _, section in ipairs(view.sections) do
        if section.collapsible then section.expanded = false end
    end
    UI.Layout(view)
    local scroll = view.frame:GetParent():GetParent()
    scroll:SetVerticalScroll(0)
    if key == "overview" then
        local hero = view.hero
        hero.find:SetText("zzzznoexistingfeaturezzzz")
        Lab.Settle(.1)
        Lab.Check("interact", "local no-result search", true, hero.empty:IsShown())
        hero.find:SetText("reminders")
        Lab.Settle(.1)
        local shown = 0
        for _, cell in ipairs(hero.grid) do if cell:IsShown() then shown = shown + 1 end end
        Lab.Check("interact", "local feature search", 1, shown)
        hero.find:SetText("")
        Lab.Settle(.1)
        hero.all:Click()
        Lab.Check("interact", "all features", "explore", hero.shown)
        hero.all:Click()
        Lab.Check("interact", "back home", "home", hero.shown)
        for _, mode in ipairs({ "appearance", "changed" }) do
            hero.views[mode]:Click()
            Lab.Check("interact", "home action " .. mode, mode, hero.shown)
        end
        hero.shown = "home"
        UI.Layout(view)
        Lab.Check("state", "Home actions preserve settings", changed, #K.Changed())
        scroll:SetVerticalScroll(0)
    end
    -- Let queued search reveals and their finite highlight settle before the screenshot's top pose.
    Lab.Settle(2.6)
    scroll:SetVerticalScroll(0)
    Lab.Settle(.2)
    if params.search then
        UI.Frame().craftElements.search:SetText("sound")
        Lab.Settle(.3)
        Lab.Check("interact", "search field drives results", false, UI.IsPageActive(key))
    end
end)
-- Keep Blizzard's unrelated PTR feedback button visible beside the capture, not over addon controls.
-- Local Forever source: Blizzard_PTRFeedback_Frames.lua creates PTR_IssueReporter.ReportBug.
-- Fixture positioning only; no simulator code, addon frame or saved state is changed.
if PTR_IssueReporter then
    PTR_IssueReporter:ClearAllPoints()
    PTR_IssueReporter:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 8, -200)
end
Lab.Finish()
