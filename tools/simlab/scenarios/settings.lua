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
    if params.filled and key == "magicInventory" then
        local mi = R.MagicInventory
        mi.SaveRule({ name = "Keep herbs ready for the next adventure", kind = "keep", cats = { "7:9" }, keep = 20, enabled = true })
        mi.SaveRule({ name = "Cloth for the bank", kind = "bank", cats = { "7:5" }, keep = 40, enabled = false })
        local dest = mi.DestNamed("mail", "Crafting materials")
        mi.SaveRule({ name = "Extra materials for my other character", kind = "mail", cats = { "7:7" }, dest = dest, keep = 10, enabled = false })
        Lab.Settle(.3)
    end
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
    if view.taskButtons then
        for i, button in ipairs(view.taskButtons) do
            button:Click()
            Lab.Check("interact", "task choice " .. i, view.tasks[i][1], view.task)
            Lab.Check("construct", "task label fits " .. i, true, button.text:GetStringWidth() <= button.text:GetWidth() + .1)
        end
        view.taskButtons[1]:Click()
    end
    local companion = R.SettingsCompanion
    if companion and companion.Supports(key) then
        UI.Layout(view)
        Lab.Check("state", "isolated companion", key, companion.Active())
        view.sampleButton:Click()
        Lab.Check("state", "sample dismissed", nil, companion.Active())
        view.sampleButton:Click()
        Lab.Check("state", "sample restored", key, companion.Active())
        local hits = companion.Hits()
        local hit = hits and (hits.title or hits.panel)
        if hit then
            hit:Click()
            Lab.Check("interact", "sample opens its appearance page", true, UI.Selected() == "notificationsLook" or UI.Selected() == "chronicleLook" or UI.Selected() == "navigationLook" or UI.Selected() == "healerWatch")
            UI.Navigate(key)
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
    if companion then Lab.Check("state", "search hides companion", nil, companion.Active()) end
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
    if view.taskButtons then view.taskButtons[1]:Click() end
    if params.task and view.taskButtons and view.taskButtons[params.task] then view.taskButtons[params.task]:Click() end
    if key == "magicInventory" then
        local page = R.MagicInventoryPage
        for _, task in ipairs({ "destinations", "guild", "protected", "rules" }) do
            Lab.Check("interact", "inventory task " .. task, true, page.SetTask(task)); Lab.Settle(.1)
            Lab.Check("state", "inventory selected task", task, page.Task())
        end
        if params.task then page.SetTask(({ "rules", "destinations", "guild", "protected" })[params.task] or "rules"); Lab.Settle(.2) end
        if params.editor then
            page.NewFromTemplate("cloth"); Lab.Settle(.2)
            local choose = assert(page.Control("e1chooseCats"))
            choose:Click(); Lab.Settle(.2)
            local cats = R.MagicInventory.Categories()
            for i = 1, #cats - 3 do
                local label, nextRow = page.Control("e1cat" .. i .. "t"), page.Control("e1cat" .. (i + 3))
                Lab.Check("construct", "category rows do not overlap " .. i, true, label:GetBottom() >= nextRow:GetTop() + 5)
            end
            choose:Click(); Lab.Settle(.2)
            Lab.Check("state", "category disclosure retains draft", true, page.Editing() ~= nil)
            if params.categories then choose:Click(); Lab.Settle(.2) end
        end
    elseif params.editor and key == "chatCleanRules" then
        R.ChatCleanRulesPage.Open(nil)
        local editor = R.ChatCleanRulesPage.Frame()
        for _, mode in ipairs({ "contains", "wildcard", "pattern" }) do
            editor.mode.onPick(mode); Lab.Settle(.1)
            Lab.Say("match geometry", mode, "textTop=" .. tostring(editor.modeHelp:GetTop()), "regionBottom=" .. tostring(editor.modeHelp:GetBottom()),
                "textHeight=" .. tostring(editor.modeHelp:GetStringHeight()), "fieldTop=" .. tostring(editor.name:GetTop()))
            Lab.Check("construct", "match help clears name field " .. mode, true,
                editor.modeHelp:GetTop() - editor.modeHelp:GetStringHeight() >= editor.name:GetTop() + 5)
        end
        editor.mode.onPick(params.editor == "pattern" and "pattern" or "contains")
    elseif params.editor and key == "hazardRules" then R.HazardRulesPage.Open(nil)
    elseif params.editor and key == "barGlowsSpells" then R.BarGlowsSpellsPage.Edit("missingBuff", nil, "All missing buffs") end
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
