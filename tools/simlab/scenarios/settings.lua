-- Real pages, synthetic Mage/profile, handler-level input only. No game actions or real SavedVariables.
local R = TwichUI
local params = SIMLAB_PARAMS or {}
local key = params.page or "overview"
A_Admin.SetManualClock(GetTime())
Lab.Solo()
UnitClass = function() return "Mage", "MAGE" end
TwichUIDB.ui.settingsWindow = { w = params.narrow and 936 or 1240, h = params.narrow and 660 or 960 }
-- UI contract fixtures only: real integration engines are covered by their dedicated unit tests.
-- These fixtures never call the third-party addon or claim real-addon compatibility.
if params.integration and (key == "speakstone" or key == "restedxp") then
    local skin = key == "speakstone" and R.SpeakStoneSkin or R.RestedXPSkin
    local state = params.integration
    R:SetEnabled(key == "speakstone" and "speakstoneSkin" or "restedxpSkin", state ~= "disabled")
    skin.Status = function()
        local available = state ~= "absent"
        return { code = state == "disabled" and "off" or available and "active" or key .. "-missing",
            addon = available and "ready" or "missing", loaded = available, integrated = available,
            switchOn = available, conflict = false }
    end
end
if params.data and (key == "ammoCustom" or key == "restockItems") then
    local name, info = C_Item.GetItemNameByID, C_Item.GetItemInfo
    local function Fixture(id)
        if id == 2512 or (id >= 2513 and id <= 2520) or (id >= 17020 and id <= 17028) then
            if params.data == "unavailable" then return nil end
            return "Expedition supplies with an exceptionally long descriptive item name " .. id
        end
        return name and name(id)
    end
    C_Item.GetItemNameByID = Fixture
    C_Item.GetItemInfo = function(id)
        if (id >= 2512 and id <= 2520) or (id >= 17020 and id <= 17028) then return Fixture(id) end
        return info(id)
    end
    if key == "restockItems" then
        R.Restock.ScanBags = function(wanted)
            local counts, unknown = {}, {}
            for id in pairs(wanted) do counts[id] = 7; if params.data == "unavailable" or params.data == "inventory" then unknown[id] = true end end
            return { counts = counts, unknown = unknown }
        end
    end
end
if key == "chatCleanChannels" and params.data then
    R.ChatClean.KnownChannels = function()
        local list = {}
        for i = 1, 6 do
            local id = i == 1 and "zone:2" or "custom:fixture" .. i
            list[i] = { key = id, label = "Expedition community channel with a long descriptive name " .. i,
                joined = i % 2 == 1, number = i, kind = "custom",
                choice = R.ChatClean.Channels()[id] or { on = false } }
        end
        return list
    end
end
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
-- Focused hosted-page exercises use disposable settings and never open a merchant or move items.
if key == "ammoCustom" or key == "restockItems" or key == "chatCleanChannels" then
    Lab.Step("hosted editor", function()
        local page = key == "ammoCustom" and R.AmmoItemsPage or key == "restockItems" and R.RestockItemsPage or R.ChatCleanChannelsPage
        local frame = page.Frame()
        Lab.Check("construct", "host visible", true, frame:IsShown())
        Lab.Check("construct", "list and scroll exist", true, frame.content ~= nil and frame.scroll ~= nil)
        if key == "ammoCustom" then
            local ok = page.AddFromText("2512")
            Lab.Check("interact", "register ammunition", true, ok == true)
            Lab.Settle(.3)
            Lab.Check("state", "registration exists", true, R.AmmoItems.Entry(2512) ~= nil)
            for _, row in ipairs({ frame.content:GetChildren() }) do
                if row.id == 2512 then row.kind.onPick("bullet") end
            end
            Lab.Check("state", "classification saved", "bullet", R.AmmoItems.Entry(2512).kind)
            for id = 2513, 2520 do R.AmmoItems.Add(id, "arrow") end
            page.Refresh(); Lab.Settle(.2)
            Lab.Check("state", "long ammunition list scrolls", true, frame.scroll:GetVerticalScrollRange() > 0)
            if params.data ~= "stress" then for id = 2513, 2520 do R.AmmoItems.Remove(id) end end
            if not params.filled then R.AmmoItems.Remove(2512); page.Say("") end
        elseif key == "restockItems" then
            local ok = page.AddFromText("17020")
            Lab.Check("interact", "add restock item", true, ok == true)
            Lab.Settle(.3)
            Lab.Check("state", "restock item exists", true, R.Restock.Rule(17020) ~= nil)
            for _, row in ipairs({ frame.content:GetChildren() }) do
                if row.id == 17020 and row.target then row.target:ClearFocus() end
            end
            for _, row in ipairs({ frame.content:GetChildren() }) do
                if row.id == 17020 and row.target then
                    row.target:SetFocus(); row.target:SetText("45"); row.target:ClearFocus()
                end
            end
            Lab.Check("state", "target saved", 45, R.Restock.Rule(17020).target)
            for _, row in ipairs({ frame.content:GetChildren() }) do
                if row.id == 17020 and row.target then
                    row.target:SetFocus(); row.target:SetText("0"); row.target:ClearFocus()
                    Lab.Check("interact", "invalid field restored", "45", row.target:GetText())
                end
            end
            Lab.Check("state", "invalid target refused", false, R.Restock.SetTarget(17020, 0))
            for id = 17021, 17028 do R.Restock.Add(id) end
            page.Refresh(); Lab.Settle(.2)
            Lab.Check("state", "long restock list scrolls", true, frame.scroll:GetVerticalScrollRange() > 0)
            if params.data ~= "stress" then for id = 17021, 17028 do R.Restock.Remove(id) end end
            if not params.filled then R.Restock.Remove(17020); page.Say("") end
        else
            local known = R.ChatClean.KnownChannels
            R.ChatClean.KnownChannels = function() return {} end
            page.Refresh()
            Lab.Check("state", "empty channels explained", true, frame.empty:IsShown())
            R.ChatClean.KnownChannels = known
            page.Refresh()
            local ok = R.ChatClean.SetChannel("zone:2", "on", true, "Trade")
            Lab.Check("interact", "enable channel", true, ok == true)
            Lab.Check("state", "channel choice saved", true, R.ChatClean.Channels()["zone:2"].on)
            Lab.Check("interact", "change filter", true, R.ChatClean.SetChannel("zone:2", "spam", false, "Trade"))
            Lab.Check("state", "filter choice saved", false, R.ChatClean.Channels()["zone:2"].spam)
            Lab.Settle(.3)
            for _, row in ipairs({ frame.content:GetChildren() }) do
                if row.ch and row.ch.key == "zone:2" then row.cats.spam:Click() end
            end
            Lab.Check("interact", "filter control changes choice", true, R.ChatClean.Channels()["zone:2"].spam)
            R.ChatClean.KnownChannels = function()
                local result = {}
                for i = 1, 5 do
                    result[i] = { key = "custom:fixture" .. i, label = "Channel " .. i, joined = true, choice = { on = true } }
                end
                return result
            end
            page.Refresh(); Lab.Settle(.2)
            Lab.Check("state", "long channel list scrolls", true, frame.scroll:GetVerticalScrollRange() > 0)
            R.ChatClean.KnownChannels = params.data == "empty" and function() return {} end or known
            page.Refresh()
        end
        Lab.Settle(.3)
        for _, row in ipairs({ frame.content:GetChildren() }) do
            if params.data == "inventory" and key == "restockItems" and row.id == 17020 then
                Lab.Check("state", "unknown inventory never shown as zero", true, row.status:GetText():find("Couldn't count", 1, true) ~= nil)
            end
            if row.name and row.status and row:IsShown() then
                Lab.Check("construct", "name clears status", true, row.name:GetBottom() >= row.status:GetTop())
            end
        end
        frame.scroll:SetVerticalScroll(frame.scroll:GetVerticalScrollRange() or 0)
        Lab.Check("interact", "scroll remains in range", true, (frame.scroll:GetVerticalScroll() or 0) >= 0)
        frame.scroll:SetVerticalScroll(0)
        R.SettingsUI.Navigate("overview")
        Lab.Check("state", "host hidden on navigation", false, frame:IsVisible())
        R.SettingsUI.Navigate(key)
        Lab.Settle(.3)
        Lab.Check("state", "host reopens", true, frame:IsShown())
        if params.filled and params.editor then
            for _, row in ipairs({ frame.content:GetChildren() }) do
                if key == "ammoCustom" and row.id == 2512 then
                    row.kind:Click()
                    Lab.Check("interact", "classification menu opens", true, R.SettingsWidgets.MenuShown())
                elseif key == "restockItems" and row.id == 17020 then
                    row.target:SetFocus()
                    Lab.Check("interact", "quantity field focused", true, row.target:HasFocus())
                end
            end
        end
    end)
end
if key == "statWeights" then
    Lab.Step("stat group browsing", function()
        local frame = R.GearWindow.Frame()
        local group, mode
        for _, control in ipairs({ frame:GetChildren() }) do
            if type(control.choices) == "function" then
                for _, choice in ipairs(control.choices()) do
                    if choice.value == "all" then group = control end
                    if choice.value == "weights" then mode = control end
                end
            end
        end
        Lab.Check("construct", "stat group selector", true, group ~= nil)
        mode.onPick("weights")
        local choices = group.choices()
        group.onPick(choices[2].value)
        Lab.Check("interact", "selected stat group", choices[2].value, group.value)
        group.onPick("all")
        Lab.Check("interact", "all groups restored", "all", group.value)
        local class = UnitClass
        UnitClass = function() return "Unsupported", "UNSUPPORTED" end
        R.GearWindow:Refresh()
        Lab.Check("state", "unsupported class explained", true, frame.noClass:IsShown())
        UnitClass = class
        R.GearWindow:Refresh()
        Lab.Check("state", "class controls restored", false, frame.noClass:IsShown())
        if params.editor then group.onPick(choices[2].value); group:Click() end
    end)
end
if key == "speakstone" or key == "restedxp" then
    Lab.Step("integration preferences", function()
        local skin = key == "speakstone" and R.SpeakStoneSkin or R.RestedXPSkin
        local style = skin.Style or skin.Text
        local property = key == "speakstone" and "textSize" or "lineSpacing"
        local before = style.Get(property)
        style.Set(property, before + 1)
        Lab.Check("state", "appearance preference saved", before + 1, style.Get(property))
        style.Set(property, before)
        Lab.Check("state", "preference restored", before, style.Get(property))
        local view = R.SettingsUI.View(key)
        local status
        for _, row in ipairs(R.SettingsKit.pages[key].rows) do
            if row.kind == "status" and row:GetName():find("availability", 1, true) then status = row end
        end
        Lab.Check("construct", "integration status row", true, status ~= nil)
        if params.integration then
            Lab.Check("state", "availability is accurate", params.integration ~= "absent" and "Loaded" or "Not installed", status.value())
        end
        R.SettingsUI.Navigate("overview")
        R.SettingsUI.Navigate(key)
        Lab.Check("state", "navigation reuses integration page", view, R.SettingsUI.View(key))
        if params.editor then
            for _, row in ipairs(R.SettingsKit.pages[key].rows) do
                if row.kind == "dropdown" and row:Enabled() then
                    R.SettingsUI.Navigate(key, row.id)
                    view.rows[row.id].control:Click()
                    Lab.Check("interact", "appearance menu opens", true, R.SettingsWidgets.MenuShown())
                    break
                end
            end
        end
    end)
end
-- Keep Blizzard's unrelated PTR feedback button visible beside the capture, not over addon controls.
-- Local Forever source: Blizzard_PTRFeedback_Frames.lua creates PTR_IssueReporter.ReportBug.
-- Fixture positioning only; no simulator code, addon frame or saved state is changed.
if PTR_IssueReporter then
    PTR_IssueReporter:ClearAllPoints()
    PTR_IssueReporter:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 8, -200)
end
Lab.Finish()
