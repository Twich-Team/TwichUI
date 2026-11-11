-- Synthetic Reminders state only; real settings, renderer, validated templates and button handlers.
-- No gear, bag, combat or messaging behavior is faked to obtain a visual result.
local R, view = TwichUI, SIMLAB_PARAMS.view
local RM, P, PV, C, Dz, Ed = R.Reminders, R.RemindersPage, R.RemindersPreview, R.RemindersCatalog, R.RemindersDesigner, R.RemindersEditor
A_Admin.SetManualClock(GetTime())
Lab.Solo()
local id
local function At(frame, bottom)
    local scale = frame:GetEffectiveScale()
    return (frame:GetLeft() + frame:GetRight()) * scale / 2,
        (bottom and frame:GetBottom() + 3 or (frame:GetTop() + frame:GetBottom()) / 2) * scale
end
local function DragTo(grip, x, y, release)
    local cursor = GetCursorPosition
    GetCursorPosition = function() return x, y end
    grip:GetScript("OnDragStart")(grip)
    Lab.Settle(0.1)
    if release then
        grip:GetScript("OnDragStop")(grip)
        GetCursorPosition = cursor
        Lab.Settle(0.1)
    end
end
local function Location()
    local ok, path = RM.AddCondition(id, "player")
    Lab.Check("state", "location condition created", true, ok)
    RM.SetCondition(id, path, { type = "player", state = "dungeon" })
end
Lab.Step("open and populate", function()
    local ok = Lab.Open("reminders")
    P, PV, C, Dz, Ed = R.RemindersPage, R.RemindersPreview, R.RemindersCatalog, R.RemindersDesigner, R.RemindersEditor
    Lab.Check("init", "settings opened", true, ok)
    local made
    made, id = P.Create("enchant")
    Lab.Check("state", "validated template created", true, made)
    RM.SetName(id, "Weapon enchant — preparation")
    RM.SetDisplay(id, "text", "Apply your weapon oil")
    Lab.Check("state", "Well Fed template created", true, P.Create("wellFed"))
    P.Select(id)
    Lab.Settle(0.2)
    Lab.Check("construct", "preview visible", true, PV.Shown())
    Lab.Check("state", "disabled reminder preserved", false, RM.Get(id).enabled)
end)
Lab.Step("navigation and handoffs", function()
    local size = Ed.sections[1].size
    size.slider:SetValue(80)
    Lab.Check("interact", "styled slider keeps its native value callback", 80, RM.Get(id).display.size)
    size.box:SetText("72")
    size.box:GetScript("OnEnterPressed")(size.box)
    Lab.Check("interact", "styled value box commits a typed number", 72, RM.Get(id).display.size)
    local before = RM.Rev()
    size:SetActive(false)
    size.slider:SetValue(88)
    Lab.Check("state", "a disabled slider cannot edit configuration", before, RM.Rev())
    size:SetActive(true)
    RM.SetDisplay(id, "size", 256)
    Lab.Settle(0.1)
    local preview = PV.Parts()
    local saved = RM.Rev()
    preview.actual:Click()
    local actual = preview.surface:GetEffectiveScale()
    Lab.Check("interact", "actual preview matches world scale", true, math.abs(actual - UIParent:GetEffectiveScale()) < 0.001)
    preview.fit:Click()
    Lab.Check("interact", "fit shrinks an oversized reminder", true, preview.surface:GetEffectiveScale() < actual)
    Lab.Check("state", "sizing modes wrote nothing", saved, RM.Rev())
    RM.SetDisplay(id, "size", 64)
    Lab.Settle(0.1)
    local rev = RM.Rev()
    PV.Parts().visualHit:Click()
    Lab.Settle(0.1)
    Lab.Check("interact", "art navigation has a target", true, Ed.revealed ~= nil)
    Lab.Check("state", "navigation wrote nothing", rev, RM.Rev())
    PV.Parts().textHit:Click()
    Lab.Check("interact", "words reveal correct control", Ed.sections[1].textBox, Ed.revealed)
    C.Toggle()
    Lab.Check("interact", "catalog owns companion", true, C.Shown() and not PV.Shown() and not Dz.Shown())
    local catalog = C.Frame()
    catalog.tabs[2]:Click()
    Lab.Check("interact", "preparation filters equipment", false, catalog.cards[3]:IsShown())
    catalog.search:SetText("oil")
    catalog.search:GetScript("OnTextChanged")(catalog.search, true)
    Lab.Check("interact", "catalog combines search with category", true, catalog.cards[1]:IsShown() and not catalog.cards[2]:IsShown())
    catalog.search:SetText("no matching template")
    catalog.search:GetScript("OnTextChanged")(catalog.search, true)
    Lab.Check("interact", "empty catalog search is explained", true, catalog.none:IsShown())
    Lab.Check("state", "catalog filters wrote nothing", rev, RM.Rev())
    TwichUISettingsEsc:Hide(); Lab.Settle(0.2)
    Lab.Check("state", "catalog cancel keeps selection", id, P.Selected())
    Lab.Check("interact", "Escape from catalog restores preview", true, R.SettingsUI.IsShown() and PV.Shown() and not C.Shown())
    Dz.Open(); Lab.Settle(0.2)
    Lab.Check("interact", "conditions own companion", true, Dz.Shown() and not PV.Shown() and not C.Shown())
    Lab.Check("construct", "dedicated workspace suspends Settings presentation", true,
        Dz.Frame().workspace:IsShown() and Dz.Frame().rail:IsVisible() and R.SettingsUI.Frame():GetAlpha() == 0)
    Lab.Check("geometry", "Settings input sits below the modal", true,
        R.SettingsUI.Frame():GetFrameStrata() == "LOW" and Dz.Frame().workspace:GetFrameStrata() == "HIGH")
    local when = Ed.sections[2]
    Lab.Check("construct", "flat All rule uses basic cards", true, not when.isAdvanced and when.cards[1].fields[1]:IsShown())
    local saved = RM.Get(id)
    local original = Dz.DraftView().conditions[1].raw
    when.cards[1].fields[1]:OpenMenu()
    TwichUISettingsMenu.rows[2]:Click()
    when.whoEdit.onPick("all")
    Lab.Settle(0.1)
    Lab.Check("state", "inline hand updates the same draft node", true,
        Dz.DraftView().conditions[1].raw == original and Dz.DraftView().conditions[1].cond.hand == "offHand")
    Lab.Check("state", "inline edit leaves the live rule and scope alone", true,
        RM.Rev() == rev and RM.Get(id).raw == saved.raw and RM.Get(id).scope.who == "characters")
    Lab.Check("construct", "targeting did not create a rule card", #saved.conditions, #Dz.DraftView().conditions)
    when.undo:Click(); Lab.Settle(0.1)
    Lab.Check("state", "undo restores targeting in the draft", "characters", Dz.DraftView().scope.who)
    when.redo:Click(); Lab.Settle(0.1)
    Lab.Check("state", "redo reapplies targeting in the draft", "all", Dz.DraftView().scope.who)
    Dz.Frame().try:Click(); Lab.Settle(0.1)
    Lab.Check("construct", "situation reveal belongs to the bottom region", true,
        Dz.Frame().diagnostics:IsShown() and Dz.Frame().diagnosticsScroll:GetParent() == Dz.Frame().diagnostics)
    Lab.Check("state", "trying a situation leaves the saved rule alone", rev, RM.Rev())
    Dz.Frame().cancel:Click(); Lab.Settle(0.2)
    Lab.Check("state", "Cancel restores preview with saved rule", true, PV.Shown() and not Dz.Shown() and RM.Rev() == rev)
    Lab.Check("construct", "Cancel restores the same Settings window", true,
        not Dz.Frame().workspace:IsShown() and R.SettingsUI.Frame():GetAlpha() == 1
        and R.SettingsUI.Frame():GetFrameStrata() == "HIGH")
    Dz.Open(); Lab.Settle(0.1)
    when.cards[1].fields[1].onPick("enchant:offHand")
    when.whoEdit.onPick("all")
    Lab.Settle(0.1)
    Dz.Frame().save:Click(); Lab.Settle(0.2)
    Lab.Check("state", "Save applies rule and scope once with the same reminder identity", true,
        RM.Rev() == rev + 1 and RM.Get(id).raw == saved.raw and RM.Get(id).scope.who == "all"
        and RM.Get(id).conditions[1].cond.hand == "offHand" and PV.Shown() and not Dz.Shown())
    RM.SetCondition(id, 1, { type = "weaponEnchant", hand = "mainHand", what = "missing" })
    RM.SetScope(id, "who", "characters")
    Dz.Open(); Lab.Settle(0.1)
    local rows = Dz.Frame().rail.rows
    rows[2]:Click(); Lab.Settle(0.1)
    Lab.Check("state", "builder rail changes the selected reminder in place", true,
        Dz.Shown() and P.Selected() == rows[2].id and Dz.DraftView().id == P.Selected())
    rows[1]:Click(); Lab.Settle(0.1)
    Dz.Frame().cancel:Click(); Lab.Settle(0.1)
end)
Lab.Step("rule moves and drag cancellation", function()
    Location()
    Dz.Open(); Lab.Settle(0.15)
    local when = Ed.sections[2]
    local first = Dz.DraftView().conditions[1].raw
    local rev = RM.Rev()
    local left, high = At(when.cards[1])
    high = (when.cards[1]:GetTop() - 3) * when.cards[1]:GetEffectiveScale()
    DragTo(when.picker.rows[1], left, high, true)
    Lab.Check("state", "palette insertion waits for confirmation", 2, #Dz.DraftView().conditions)
    when.editor.done:Click(); Lab.Settle(0.1)
    Lab.Check("state", "confirmed palette drop uses the insertion slot", first, Dz.DraftView().conditions[2].raw)
    when.undo:Click(); Lab.Settle(0.1)
    first = Dz.DraftView().conditions[1].raw
    DragTo(when.cards[1].grip, 0, 0, true)
    Lab.Check("state", "outside drop leaves the first draft node in place", first, Dz.DraftView().conditions[1].raw)
    local x, y = At(when.cards[2], true)
    DragTo(when.cards[1].grip, x, y, true)
    Lab.Check("state", "drop reorders the original draft node", first, Dz.DraftView().conditions[2].raw)
    when.undo:Click(); Lab.Settle(0.1)
    Lab.Check("state", "undo restores enchant to the first slot", "weaponEnchant", Dz.DraftView().conditions[1].cond.type)
    when.redo:Click(); Lab.Settle(0.1)
    Lab.Check("state", "redo restores the move", "weaponEnchant", Dz.DraftView().conditions[2].cond.type)
    when.undo:Click(); Lab.Settle(0.1)
    first = Dz.DraftView().conditions[1].raw
    Dz.SetAdvanced(true); Lab.Settle(0.1)
    when.rootGroup.add:Click()
    Dz.AddGroup("any")
    Lab.Settle(0.15)
    local group = when.groups[1]
    local gx, gy = At(group.box)
    gy = group.box:GetTop() * group.box:GetEffectiveScale() - 14 * group.box:GetEffectiveScale()
    DragTo(group.grip, gx, gy, true)
    Lab.Check("state", "group cannot drop into itself", 0, #Dz.DraftView().groups[1].children)
    DragTo(when.picker.rows[2], gx, gy, true)
    Lab.Check("interact", "palette drop opens a condition draft", true, when.editor.cancel:IsShown())
    when.editor.cancel:Click(); Lab.Settle(0.1)
    DragTo(when.cards[1].grip, gx, gy, true)
    local moved = RM.NodeByRaw(Dz.DraftView(), first)
    Lab.Check("state", "drop into Any keeps the draft node", true, moved and #moved.path == 2)
    when.undo:Click(); Lab.Settle(0.1)
    Lab.Check("state", "undo restores condition to the root", "weaponEnchant", Dz.DraftView().conditions[1].cond.type)
    when.cards[1].grip:GetScript("OnDragStart")(when.cards[1].grip)
    TwichUISettingsEsc:Hide(); Lab.Settle(0.1)
    Lab.Check("state", "Escape cancels the ghost", nil, Dz.Frame().ruleDrag.source)
    Lab.Check("interact", "Escape during drag keeps the builder open", true, Dz.Shown())
    Lab.Check("state", "draft moves never wrote to the live rule", rev, RM.Rev())
    R.SettingsUI.Close(); Lab.Settle(0.1)
    Lab.Check("state", "closing Settings discards the workspace draft", true,
        not Dz.Shown() and not Dz.Frame().workspace:IsShown() and RM.Rev() == rev)
    Lab.Open("reminders"); P.Select(id); Lab.Settle(0.1)
    Lab.Check("construct", "Settings reopens at full opacity", 1, R.SettingsUI.Frame():GetAlpha())
end)
Lab.Step("required item and cleanup", function()
    local ok, draft = P.Create("item")
    Lab.Check("state", "item draft created", true, ok)
    Lab.Check("state", "item draft invalid", false, RM.Get(draft).valid)
    Lab.Check("state", "item draft cannot enable", false, RM.SetEnabled(draft, true))
    RM.Delete(draft); P.Select(id); Lab.Settle(0.1)
    PV.Parts().show:Click(); Lab.Settle(0.1)
    Lab.Check("interact", "disabled draft shows on screen on request", id, R.ReminderDisplay.PreviewId())
    R.SettingsUI.Close(); Lab.Settle(0.1)
    Lab.Check("state", "all companions closed", false, PV.Shown() or C.Shown() or Dz.Shown())
    Lab.Check("state", "no world preview left", nil, R.ReminderDisplay.PreviewId())
    local name = RM.Get(id).name
    for i = 1, 3 do
        RM.SetName(id, "Gameplay update " .. i)
        P.QueueRefresh(0.2); P.Refresh(); Lab.Settle(0.3)
        PV.Show(RM.Get(id)); PV.Update(RM.Get(id))
        Lab.Check("state", "closed editor resists subsequent refresh " .. i, false, PV.Shown())
    end
    RM.SetName(id, name)
    Lab.Open("reminders"); P.Select(id); Lab.Settle(0.2)
    PV.SetEnabled(false); P.Refresh(); Lab.Settle(0.2)
    Lab.Check("state", "disabled editor preview stays hidden", false, PV.Shown())
    R.SettingsUI.Navigate("notifications"); P.Refresh(); Lab.Settle(0.2)
    PV.Show(RM.Get(id))
    Lab.Check("state", "another Settings page cannot show the companion", false, PV.Shown())
    Lab.Open("reminders"); P.Select(id); PV.SetEnabled(true); Lab.Settle(0.2)
    Lab.Check("state", "explicit editor re-enable restores the companion", true, PV.Shown())
end)
Lab.Step("polish transactions and header ownership", function()
    local D, UI = R.ReminderDisplay, R.SettingsUI
    local page = UI.View("reminders")
    local scroll = page.frame:GetParent():GetParent()
    local titleTop, rev = page.title:GetTop(), RM.Rev()
    Lab.Check("geometry", "body viewport starts below fixed tabs", true,
        scroll:GetTop() <= page.tabs:GetBottom() - 4)
    Ed.placementOpen, Ed.moreOpen = true, true
    P.Refresh(); UI.Refresh(); Lab.Settle(.1)
    scroll:GetScript("OnMouseWheel")(scroll, -1); Lab.Settle(.2)
    Lab.Check("geometry", "wheel leaves the page heading fixed", titleTop, page.title:GetTop())
    Lab.Check("interact", "bounded scroll finishes its update work", nil, scroll.motionDriver:GetScript("OnUpdate"))
    UI.RevealFrame(page.frame); Lab.Settle(.1)
    local preview = PV.Parts()
    for _, mode in ipairs({ "transparent", "landscape", "parchment", "dark" }) do
        PV.SetBackground(mode)
        Lab.Check("state", mode .. " background preserves configuration", rev, RM.Rev())
    end
    local placementWidth, placementHeight = UI.Frame():GetWidth(), UI.Frame():GetHeight()
    local position = RM.Get(id).place
    local x, y, point = position.x, position.y, position.point
    Lab.Check("interact", "placement starts explicitly", true, R.RemindersPlacement.Start(RM.Get(id)))
    Lab.Check("geometry", "settings is genuinely hidden for placement", false, UI.Frame():IsShown())
    Lab.Check("state", "companion cannot appear in placement", false, PV.Show(RM.Get(id)))
    local f = D.Frame(id)
    f:ClearAllPoints(); f:SetPoint(point, UIParent, point, x + 40, y + 25)
    f.handle:GetScript("OnDragStop")(f.handle)
    Lab.Check("state", "moving writes no saved coordinates before Finish", rev, RM.Rev())
    R.RemindersPlacement.Parts().cancel:Click(); Lab.Settle(.1)
    Lab.Check("state", "placement Cancel discards movement", true,
        RM.Rev() == rev and RM.Get(id).place.x == x and UI.IsShown() and PV.Shown())
    Lab.Check("geometry", "placement preserves current window dimensions", true,
        UI.Frame():GetWidth() == placementWidth and UI.Frame():GetHeight() == placementHeight)
    R.RemindersPlacement.Start(RM.Get(id)); UI.Close(); Lab.Settle(.1)
    Lab.Check("state", "closing during placement leaves every editing surface closed", true,
        not UI.IsShown() and not PV.Shown() and not R.RemindersPlacement.Active())
    Lab.Open("reminders"); Lab.Settle(.1)
    Lab.Check("state", "reopening after placement restores one companion", true, PV.Shown())
    local font = Ed.sections[3].font
    Ed.placementOpen, Ed.moreOpen = true, true
    P.Refresh(); UI.Refresh(); Lab.Settle(.1)
    UI.RevealFrame(font); font:OpenMenu(); Lab.Settle(.1)
    Lab.Check("construct", "font choices carry individual preview files", true, TwichUISettingsMenu.rows[1].choice.font ~= nil)
    local menu, oldFont = TwichUISettingsMenu, RM.Get(id).display.font
    if #menu.choices > #menu.rows then
        menu.bar:SetValue(2)
        Lab.Check("interact", "font popup native thumb changes its row window", 2, menu.offset)
    end
    local pickedFont = menu.rows[1].choice.value
    menu.rows[1]:Click(); Lab.Settle(.1)
    Lab.Check("state", "font menu keeps its canonical selection callback", pickedFont, RM.Get(id).display.font)
    RM.SetDisplay(id, "font", oldFont)
    R.SettingsWidgets.CloseMenu()
    P.Refresh(); Lab.Settle(.1)
    local row = P.Parts().rows[1]
    row:GetScript("OnClick")(row, "RightButton")
    TwichUISettingsMenu.rows[1]:Click(); Lab.Settle(.1)
    local copy = P.Selected()
    Lab.Check("state", "context Duplicate selects a unique disabled copy", true, copy ~= id and not RM.Get(copy).enabled)
    local copyRow
    for _, item in ipairs(P.Parts().rows) do if item.id == copy then copyRow = item end end
    copyRow:GetScript("OnClick")(copyRow, "RightButton")
    TwichUISettingsMenu.rows[2]:Click()
    StaticPopupDialogs.TWICHUI_REMINDER_DELETE.OnCancel()
    StaticPopup_Hide("TWICHUI_REMINDER_DELETE")
    Lab.Check("state", "context Delete cancellation keeps its source", true, RM.Get(copy) ~= nil)
    copyRow:GetScript("OnClick")(copyRow, "RightButton")
    TwichUISettingsMenu.rows[2]:Click()
    StaticPopupDialogs.TWICHUI_REMINDER_DELETE.OnAccept()
    StaticPopup_Hide("TWICHUI_REMINDER_DELETE"); Lab.Settle(.1)
    Lab.Check("state", "confirmed context Delete removes only the copy", true, not RM.Get(copy) and RM.Get(id) ~= nil)
    P.Select(id)
    Ed.placementOpen, Ed.moreOpen = false, false
    P.Refresh(); UI.Refresh(); UI.RevealFrame(page.frame); Lab.Settle(.1)
end)
Lab.Step("primary placement and scoped reset", function()
    local UI, data = R.SettingsUI, RM.Get(id)
    local enabled, before = data.enabled, RM.Rev()
    Ed.placementOpen = false; P.Refresh(); Lab.Settle(.1)
    local main = P.Parts().frame.place
    Lab.Check("construct", "Place is visible with Advanced closed", true, main:IsVisible() and main:GetParent() == P.Parts().frame.head)
    main:Click(); Lab.Settle(.1)
    Lab.Check("interact", "primary Place opens the existing focused workflow", true, R.RemindersPlacement.Active() and not UI.IsShown())
    R.RemindersPlacement.Parts().cancel:Click(); Lab.Settle(.1)
    PV.Parts().place:Click(); Lab.Settle(.1)
    Lab.Check("interact", "companion Place opens the same focused workflow", true, R.RemindersPlacement.Active() and R.ReminderDisplay.PreviewId() == id)
    R.RemindersPlacement.Parts().cancel:Click(); Lab.Settle(.1)
    Lab.Check("state", "both canceled entry points preserve data", true, RM.Rev() == before and RM.Get(id).enabled == enabled and PV.Shown())
    local reset = UI.View("reminders").reset.button
    Lab.Check("construct", "Reset is the scoped destructive painted control", true, reset.twichCraft and reset.twichCraft.skin == "danger")
    R:SetEnabled("reminders", false); reset:Click()
    StaticPopupDialogs.TWICHUI_SETTINGS_RESET_PAGE.OnCancel(); StaticPopup_Hide("TWICHUI_SETTINGS_RESET_PAGE")
    Lab.Check("state", "Reset cancellation leaves the master switch off", false, R:Enabled("reminders"))
    reset:Click(); StaticPopupDialogs.TWICHUI_SETTINGS_RESET_PAGE.OnAccept(); StaticPopup_Hide("TWICHUI_SETTINGS_RESET_PAGE")
    Lab.Check("state", "Reset retains its scope and every reminder", true, R:Enabled("reminders") and RM.Get(id) ~= nil and not RM.Get(id).enabled)
    P.Refresh(); UI.Refresh(); Lab.Settle(.1)
end)
Lab.Step("Advanced layout and accordion regression", function()
    if not view:find("^advanced") then return end
    local UI, a, diagnostics = R.SettingsUI, Ed.sections[3], Ed.sections[5]
    UI.Frame():SetSize(936, 820)
    Ed.placementOpen, Ed.moreOpen, Ed.testOpen = false, false, false
    P.Refresh(); UI.Refresh(); Lab.Settle(.1)
    local collapsed = P.Height()
    a.toggle:Click(); Lab.Settle(.1)
    Lab.Check("geometry", "Opacity is the first row without a visible Position overlay", true,
        a.opacity:IsVisible() and not a.preset:IsShown() and not a.presetLabel:IsShown()
        and a.opacity:GetTop() < a.toggle:GetBottom() - 8)
    Lab.Check("geometry", "primary Advanced rows have consistent vertical gaps", true,
        math.abs(a.opacity:GetTop() - a.textSize:GetTop() - 32) < .1
        and math.abs(a.textSize:GetTop() - a.textPlace:GetTop() - 32) < .1)
    Lab.Check("geometry", "numeric boxes and Words go share aligned geometry", true,
        math.abs(a.opacity.box:GetRight() - a.textSize.box:GetRight()) < .1
        and math.abs(a.opacity:GetLeft() - a.textPlace:GetLeft()) < .1
        and a.opacity.box:GetRight() <= a:GetRight() - 13)
    a.opacity.box:SetText("73"); a.opacity.box:GetScript("OnEnterPressed")(a.opacity.box)
    a.textSize.box:SetText("24"); a.textSize.box:GetScript("OnEnterPressed")(a.textSize.box)
    a.textPlace.onPick("below"); Lab.Settle(.1)
    Lab.Check("interact", "Advanced numeric entries and Words go persist through Config", true,
        RM.Get(id).display.opacity == 73 and RM.Get(id).display.textSize == 24 and RM.Get(id).display.textPlace == "below")
    RM.SetDisplay(id, "opacity", 100); RM.SetDisplay(id, "textSize", 18); RM.SetDisplay(id, "textPlace", "right")
    a.more:Click(); Lab.Settle(.1)
    Lab.Check("geometry", "secondary Position has a full row before Anchored to", true,
        a.preset:IsVisible() and a.preset:GetTop() <= a.panel:GetBottom() - 6
        and a.point:GetTop() <= a.preset:GetBottom() - 6)
    local expanded = P.Height()
    a.diagnostics:Click(); Lab.Settle(.1)
    Lab.Check("geometry", "Diagnostics and lower actions reflow below Advanced", true,
        diagnostics:IsVisible() and diagnostics:GetTop() < a:GetBottom()
        and P.Parts().frame.duplicate:GetTop() < diagnostics:GetBottom() and P.Height() > expanded)
    local page = UI.View("reminders")
    local content = page.frame:GetParent()
    local scroll = content:GetParent()
    UI.RevealFrame(page.reset.button); Lab.Settle(.1)
    Lab.Check("geometry", "expanded content reaches Reset within a bounded scroll range", true,
        scroll:GetVerticalScroll() > 0 and scroll:GetVerticalScroll() <= scroll:GetVerticalScrollRange() + 1)
    a.more:Click(); a.toggle:Click(); a.diagnostics:Click(); Lab.Settle(.1)
    Lab.Check("state", "collapse removes all secondary controls and restores page height", true,
        not a.opacity:IsShown() and not a.presetLabel:IsShown() and not a.font:IsShown()
        and not diagnostics:IsShown() and P.Height() == collapsed)
    Lab.Check("geometry", "collapsed scroll is clamped to its new content height", true,
        scroll:GetVerticalScroll() <= math.max(0, content:GetHeight() - scroll:GetHeight()) + 1)
    -- Repeated changes must reuse controls and retain session-only nested state safely.
    for _ = 1, 3 do a.toggle:Click(); a.more:Click(); a.more:Click(); a.toggle:Click() end
    Lab.Settle(.1)
    Lab.Check("state", "repeated disclosure cycles retain clean collapsed geometry", true,
        P.Height() == collapsed and not a.presetLabel:IsShown())
end)
Lab.Step("pose", function()
    if view == "itemAppearance" or view == "artAppearance" then
        RM.SetDisplay(id, "mode", view == "itemAppearance" and "iconText" or "artwork")
        if view == "itemAppearance" then
            RM.SetDisplay(id, "iconSource", "item")
            RM.SetDisplay(id, "item", 6948)
        end
        Lab.Settle(0.2)
        local appearance = Ed.sections[1]
        local right = view == "itemAppearance" and appearance.itemBox or appearance.size
        Lab.Check("geometry", "artwork does not overlap its direct-edit controls", true,
            right:GetLeft() >= appearance.artTile:GetRight() + 8)
        if view == "itemAppearance" then
            Lab.Check("state", "item source and identity survive layout", 6948, RM.Get(id).display.item)
        end
    end
    if view == "editorTall" then
        R.SettingsUI.Frame():SetSize(936, 820)
        R.SettingsUI.Refresh(); Lab.Settle(0.2)
        Lab.Check("geometry", "preview follows a taller editor without changing display scale", true,
            PV.Parts():GetHeight() == 820 and RM.Get(id).display.size == 64)
    end
    if view == "narrow" then
        R.SettingsUI.Frame():SetSize(936, 480)
        R.SettingsUI.Refresh(); Lab.Settle(0.2)
    end
    R.SettingsUI.RevealFrame(R.SettingsUI.View("reminders").frame); Lab.Settle(0.2)
    local UI = R.SettingsUI
    if view:find("^advanced") then
        local UI, a = R.SettingsUI, Ed.sections[3]
        UI.Frame():SetSize(936, (view == "advancedNested" or view == "advancedNestedBottom") and 950 or 820)
        UI.Frame():ClearAllPoints()
        UI.Frame():SetPoint("TOPLEFT", UIParent, "TOPLEFT", 326, -100)
        if view == "advancedScaled" then UI.Frame():SetScale(.85) end
        Ed.placementOpen = view ~= "advancedCollapsed" and view ~= "advancedDiagnostics"
        Ed.moreOpen = view == "advancedNested" or view == "advancedNestedBottom"
        Ed.testOpen = view == "advancedDiagnostics"
        P.Refresh(); UI.Refresh(); Lab.Settle(.1)
        if view == "advancedNestedBottom" or view == "advancedExpanded" then UI.RevealFrame(UI.View("reminders").reset.button)
        elseif view == "advancedDiagnostics" then UI.RevealFrame(Ed.sections[5])
        elseif Ed.placementOpen then UI.RevealFrame(a) end
        Lab.Settle(.1)
    end
    local mode = ({ previewDark = "dark", previewTransparent = "transparent", previewLandscape = "landscape", previewParchment = "parchment" })[view]
    if mode then PV.SetBackground(mode) end
    if view == "previewTransparent" then
        -- Explicit test fixture: the simulator has no terrain renderer. A labelled image
        -- BEHIND the real companion proves its transparent well exposes lower strata.
        local underlay = CreateFrame("Frame", nil, UIParent)
        underlay:SetFrameStrata("BACKGROUND")
        local box = PV.Parts().box
        underlay:SetPoint("TOPLEFT", box, "TOPLEFT", -6, 6)
        underlay:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 6, -6)
        local image = underlay:CreateTexture(nil, "BACKGROUND")
        image:SetAllPoints()
        image:SetTexture(R.PATH .. [[media\reminders\preview-landscape.tga]])
        local note = CreateFrame("Frame", nil, UIParent)
        note:SetFrameStrata("DIALOG"); note:SetSize(318, 18)
        note:SetPoint("TOP", PV.Parts(), "BOTTOM", 0, -7)
        local label = R.SettingsWidgets.Text(note, "small")
        label:SetAllPoints()
        label:SetText("Transparency test underlay · simulator only")
        Lab.Check("construct", "Transparent has no image or opaque canvas fill", true,
            not PV.Parts().backgroundArt:IsShown() and not PV.Parts().boxFace.parts[1]:IsShown())
    end
    if view == "previewHover" then PV.Parts().visualHit:GetScript("OnEnter")(PV.Parts().visualHit) end
    if view == "destination" then PV.Parts().textHit:Click(); Lab.Settle(.1) end
    if view == "reminderMenu" then
        local row = P.Parts().rows[1]
        row:GetScript("OnClick")(row, "RightButton")
        Lab.Check("geometry", "context popup is content sized", true, TwichUISettingsMenu:GetWidth() < 180)
    end
    if view == "fontMenu" then
        Ed.placementOpen, Ed.moreOpen = true, true
        P.Refresh(); UI.Refresh(); Lab.Settle(.1)
        UI.RevealFrame(Ed.sections[3].font)
        Ed.sections[3].font:OpenMenu()
        Lab.Settle(.1)
        local menu, font = TwichUISettingsMenu, Ed.sections[3].font
        local _, _, fontBottom = R.SettingsWidgets.VisibleRect(font)
        local delta = math.abs(menu:GetTop() * menu:GetEffectiveScale() - fontBottom * font:GetEffectiveScale())
        Lab.Check("geometry", "font popup follows visible scrolled owner", true, delta < 5)
    end
    if view == "placement" then PV.Parts().place:Click() end
    if view == "placementPrimary" then P.Parts().frame.place:Click() end
    if view == "scrollHeader" or view == "editorDiagnostics" or view == "editorSituation" then
        Ed.placementOpen, Ed.moreOpen = view == "scrollHeader", view == "scrollHeader"
        if view ~= "scrollHeader" then Ed.testOpen = true end
        if view == "editorSituation" then
            Ed.situationOpen = true
            UI.Frame():SetSize(936, 900)
        end
        P.Refresh(); UI.Refresh(); Lab.Settle(.1)
        UI.RevealFrame(view == "scrollHeader" and Ed.sections[3].font or Ed.sections[5])
    end
    if view == "structured" then
        RM.AddCondition(id, "player", nil, { type = "player", state = "mounted", negate = true })
        P.Refresh(); UI.Refresh(); Lab.Settle(.1)
    end
    if view == "narrowEditor" then
        UI.Frame():SetSize(936, 480); UI.Refresh(); Lab.Settle(.1)
    end
    if view == "ammoTab" then
        UI.Navigate("ammoCustom"); Lab.Settle(.1)
        Lab.Check("construct", "Known ammunition shares fixed family chrome", true,
            UI.View("ammoCustom").chrome:IsVisible() and not PV.Shown())
    end
    if view == "resetNormal" or view == "resetHover" then
        local reset = UI.View("reminders").reset.button
        UI.RevealFrame(reset); Lab.Settle(.1)
        if view == "resetHover" then reset:GetScript("OnEnter")(reset) end
    end
    if view == "conditionIcons" or view == "mountedPalette" then
        RM.RemoveCondition(id, 2) -- this synthetic pose isolates the three audited types
        RM.AddCondition(id, "player", nil, { type = "player", state = "combat" })
        RM.AddCondition(id, "player", nil, { type = "player", state = "mounted" })
        Dz.Open(); Lab.Settle(.1)
        if view == "mountedPalette" then
            local box = Ed.sections[2].picker.search
            box:SetText("mounted"); box:GetScript("OnTextChanged")(box, true); Lab.Settle(.1)
        end
    end
    if view == "conditionAudit" then
        UI.Close()
        local G, M = R.SettingsWidgets, R.SettingsMaterial
        local panel = CreateFrame("Frame", "TwichUIConditionAudit", UIParent)
        panel:SetSize(930, 660); panel:SetPoint("CENTER"); panel:SetFrameStrata("HIGH")
        M.Companion(panel)
        local heading = M.ReminderFont(G.Text(panel, "heading"), 24, true)
        heading:SetPoint("TOPLEFT", 24, -20); heading:SetText("Condition artwork · palette / card sizes")
        local entries = R.RemindersPlain.Entries()
        local cols = #entries > 14 and 3 or 2
        local rowH = math.min(72, math.floor((1100 - 68) / math.ceil(#entries / cols)) - 6)
        panel:SetSize(cols == 3 and 1380 or 930, math.max(660, 68 + math.ceil(#entries / cols) * (rowH + 6) + 16))
        Lab.Check("construct", "every palette entry is in the audit", 28, #entries)
        for i, entry in ipairs(entries) do
            local row = CreateFrame("Frame", nil, panel)
            local colW = cols == 3 and 440 or 430
            row:SetSize(colW, rowH); row:SetPoint("TOPLEFT", 24 + ((i-1)%cols)*(colW+12), -(68+math.floor((i-1)/cols)*(rowH+6)))
            M.PanelFace(row, "card")
            local small, big = row:CreateTexture(nil,"ARTWORK"), row:CreateTexture(nil,"ARTWORK")
            small:SetPoint("LEFT", 10, 0); big:SetPoint("LEFT", 57, 0)
            R.RemindersPlain.ApplyArt(small, entry.make(), 30)
            R.RemindersPlain.ApplyArt(big, entry.make(), 45)
            local label = M.ReminderFont(G.Text(row,"body"),14,true)
            label:SetPoint("LEFT", 118, 0); label:SetWidth(300)
            label:SetText(R.RemindersPlain.CardTitle(entry.make()) or entry.name)
        end
    end
    if view == "craftProof" then
        R.SettingsUI.Close()
        local G, M, Art = R.SettingsWidgets, R.SettingsMaterial, R.SettingsCraft
        local proof = CreateFrame("Frame", "TwichUICraftProof", UIParent)
        proof:SetSize(980, 620); proof:SetPoint("CENTER"); proof:SetFrameStrata("HIGH")
        M.QuietTile(proof, "outer", "BACKGROUND", -7)
        Art.Frame(proof)
        local function Label(parent, text, x, y, size)
            local fs = M.ReminderFont(G.Text(parent, "body"), size or 14, true)
            fs:SetPoint("TOPLEFT", x, -y); fs:SetText(text)
            return fs
        end
        Label(proof, "Painted component proof", 28, 26, 25)
        Label(proof, "Normal    /    Hover    /    Pressed    /    Disabled    /    Selected    /    Primary    /    Primary hover    /    Destructive", 28, 77)
        local specs = { { "Normal" }, { "Hover", nil, "OnEnter" }, { "Pressed", nil, "OnMouseDown" },
            { "Disabled", nil, false }, { "Selected", "segment" }, { "Save", "confirmation" },
            { "Save hover", "confirmation", "OnEnter" }, { "Delete", "danger" } }
        for i, spec in ipairs(specs) do
            local button = G.Button(proof, spec[1], 104, "secondary", function() end)
            button:SetHeight(38); button:SetPoint("TOPLEFT", 28 + (i - 1) * 116, -108)
            Art.Control(button, spec[2]); M.ReminderFont(button.text, 14, true)
            if spec[2] == "segment" then button:SetSelected(true) end
            if spec[3] == false then button:SetEnabled(false)
            elseif spec[3] then button:GetScript(spec[3])(button) end
        end
        local row = CreateFrame("Frame", nil, proof)
        row:SetPoint("TOPLEFT", 28, -194); row:SetSize(260, 62)
        Art.Sheet(row, "selection", { layer = "BACKGROUND", corner = 12 })
        local icon = row:CreateTexture(nil, "ARTWORK"); icon:SetPoint("LEFT", 14, 0)
        icon:SetSize(34, 34)
        R.Icons.Apply(icon, "reminders", 34)
        Label(row, "Weapon enchant", 60, 14, 17); Label(row, "Off", 60, 37)
        local card = CreateFrame("Frame", nil, proof)
        card:SetPoint("TOPLEFT", 318, -194); card:SetSize(630, 112)
        M.PanelFace(card, "card")
        Label(card, "Weapon enchant", 78, 20, 18); Label(card, "Met", 78, 48)
        local art = card:CreateTexture(nil, "ARTWORK"); art:SetSize(48, 48); art:SetPoint("TOPLEFT", 18, -20)
        art:SetTexture([[Interface\Icons\Ability_DualWield]])
        for i, label in ipairs({ "Main hand", "Is missing" }) do
            local field = G.Dropdown(card, 146, function() end)
            field:SetPoint("TOPLEFT", 308 + (i - 1) * 156, -36); field:SetHeight(32)
            field:SetValue(label); Art.Control(field, "dropdown")
            M.ReminderFont(field.text, 14, true)
        end
        local field = G.Dropdown(proof, 260, function() end)
        field:SetPoint("TOPLEFT", 28, -350); field:SetHeight(34)
        field:SetChoices(function() return { { value = "a", label = "This character" }, { value = "b", label = "Every character" } } end)
        field:SetValue("a", "This character"); Art.Control(field, "dropdown"); field.twichReminderMaterial = true
        Label(proof, "Slider and exact numeric input", 318, 342, 17)
        local slider = G.Slider(proof, 360, function() end, true)
        slider:SetPoint("TOPLEFT", 318, -378); slider:SetRange(16, 256, 1); slider:SetValue(64)
        Art.Thumb(slider.slider:GetThumbTexture())
        local extra = {
            { "Save pressed", "confirmation", "OnMouseDown" }, { "Delete hover", "danger", "OnEnter" },
            { "Delete pressed", "danger", "OnMouseDown" }, { "Field focus", "field", "focus" },
            { "Field disabled", "field", false }, { "Tab", "segment" }, { "Tab hover", "segment", "OnEnter" },
            { "Tab pressed", "segment", "OnMouseDown" }, { "Tab disabled", "segment", false },
            { "Selected hover", "segment", "OnEnter", true }, { "Dungeon", "chip" },
            { "Raid hover", "chip", "OnEnter" }, { "Chip pressed", "chip", "OnMouseDown" }, { "Chip disabled", "chip", false },
        }
        for i, spec in ipairs(extra) do
            local field = spec[2] == "field"
            local button = field and G.EditBox(proof, 118, 32) or G.Button(proof, spec[1], 118, "secondary", function() end)
            button:SetHeight(32); button:SetPoint("TOPLEFT", 28 + ((i - 1) % 7) * 132, -(454 + math.floor((i - 1) / 7) * 64))
            Art.Control(button, spec[2])
            Label(proof, spec[1], 28 + ((i - 1) % 7) * 132, 436 + math.floor((i - 1) / 7) * 64, 12)
            if field then button:SetText("64"); M.ReminderFont(button, 14, true)
            else M.ReminderFont(button.text, 13, true) end
            if spec[4] then button:SetSelected(true) end
            if spec[3] == false then button:SetEnabled(false)
            elseif spec[3] == "focus" then button:SetFocus()
            elseif spec[3] then local fn = button:GetScript(spec[3]); if fn then fn(button) end end
        end
        Lab.Check("construct", "painted proof owns no configuration", true, proof:IsShown())
        Lab.Settle(0.2)
        return
    end
    if view == "conditions" or view == "conditionsEditor" or view == "conditionsPalette" or view == "conditionsNarrow" then
        -- A flat All rule made of the library's kinds: a buff as the trigger, three restrictions.
        while #RM.Get(id).conditions > 0 do RM.RemoveCondition(id, { 1 }) end
        Lab.Check("state", "buff trigger added", true, (RM.AddCondition(id, "aura", nil, { type = "aura", spells = { 1459 }, what = "missing" })))
        Lab.Check("state", "mana restriction added", true, (RM.AddCondition(id, "power", nil, { type = "power", power = "MANA", compare = "below", percent = 30 })))
        Lab.Check("state", "bag space restriction added", true, (RM.AddCondition(id, "bagSpace", nil, { type = "bagSpace", compare = "atLeast", count = 5 })))
        Lab.Check("state", "enchant running out added", true, (RM.AddCondition(id, "weaponEnchant", nil, { type = "weaponEnchant", hand = "mainHand", what = "expiring", seconds = 300 })))
        Lab.Check("state", "the library rule is valid", true, RM.Get(id).valid)
        P.Select(id); Lab.Settle(0.1)
        Dz.Open(); Lab.Settle(0.2)
        local when = Ed.sections[2]
        Lab.Check("construct", "a flat library rule uses the basic view", false, when.isAdvanced)
        local titles = {}
        for i = 1, 4 do titles[i] = when.cards[i].title:GetText() end
        Lab.Check("construct", "card titles name each kind", "Buff|Resource|Bag space|Weapon enchant", table.concat(titles, "|"))
        Lab.Check("construct", "the amount reads as a share", "30%", when.cards[2].fields[3].text:GetText())
        Lab.Check("construct", "the enchant's time fits its field", "5 min", when.cards[4].fields[3].text:GetText())
        Lab.Check("construct", "the enchant's choice fits its field", "Expiring", when.cards[4].fields[2].text:GetText())
        Lab.Check("geometry", "fields line up down the rule", true, math.abs(when.cards[2].fields[1]:GetLeft() - when.cards[3].fields[1]:GetLeft()) < 1)
        Lab.Check("geometry", "three fields start beside the title, inside the card", true,
            when.cards[4].fields[1]:GetLeft() >= when.cards[4].title:GetLeft() + when.cards[4].title:GetStringWidth()
            and when.cards[4].fields[3]:GetRight() <= when.cards[4]:GetRight())
        Lab.Check("construct", "a buff card asks for its spell", "Change buff", when.cards[1].item.text:GetText())
        local words = { Met = true, ["Not met"] = true, Unknown = true, ["Needs attention"] = true }
        local ok = true
        for i = 1, 4 do ok = ok and words[when.cards[i].note:GetText()] == true end
        Lab.Check("construct", "each card states Met, Not met or Unknown", true, ok)
        local summary = R.RemindersPlain.RuleSummary(Dz.DraftView())
        -- the simulator's spell-name stub answers "Unknown"; a client answers the name, or nothing ("spell 1459")
        summary = summary:gsub("Arcane Intellect", "<buff>"):gsub("spell 1459", "<buff>"):gsub("missing Unknown", "missing <buff>")
        Lab.Check("construct", "the rule reads naturally",
            "Shows when you are missing <buff>, but only while your mana is below 30% and you have at least 5 free bag slots and your main hand weapon enchant has less than 5 minutes left.",
            summary)
        if view == "conditions" or view == "conditionsNarrow" then
            local before = RM.Rev()
            when.cards[2].fields[3].onPick(50); Lab.Settle(0.1)
            Lab.Check("interact", "a quick amount edits the draft", 50, Dz.DraftView().conditions[2].cond.percent)
            Lab.Check("state", "the saved rule is untouched until Save", before, RM.Rev())
            when.cards[3].fields[2].onPick(R.RemindersPlain.OTHER); Lab.Settle(0.1)
            Lab.Check("interact", "Other amount opens the editor's number box", true, when.editor:IsShown() and when.editor.amount:IsShown())
            when.editor.amount:SetText("7")
            when.editor.amount:GetScript("OnEnterPressed")(when.editor.amount); Lab.Settle(0.1)
            when.editor.done:Click(); Lab.Settle(0.1)
            Lab.Check("interact", "a typed amount reaches the draft", 7, Dz.DraftView().conditions[3].cond.count)
            when.undo:Click(); Lab.Settle(0.1)
            Lab.Check("interact", "undo restores the earlier amount", 5, Dz.DraftView().conditions[3].cond.count)
            when.redo:Click(); Lab.Settle(0.1)
            Dz.Frame().save:Click(); Lab.Settle(0.1)
            local saved = RM.Get(id)
            Lab.Check("state", "Save writes both edits", "50/7", saved.conditions[2].cond.percent .. "/" .. saved.conditions[3].cond.count)
            Lab.Check("state", "and the rule is still valid", true, saved.valid)
            Lab.Check("state", "nothing was turned on", false, saved.enabled)
            if view == "conditions" then
                -- leave the When workspace open on the saved rule for the screenshot
                if not Dz.Shown() then Dz.Open(); Lab.Settle(0.2) end
            end
        elseif view == "conditionsEditor" then
            local entry
            for _, e in ipairs(R.RemindersPlain.Entries()) do if e.key == "aura" then entry = e end end
            Lab.Check("construct", "the palette offers a buff", true, entry ~= nil)
            Dz.Pick(entry); Lab.Settle(0.1)
            local box = when.editor.item
            Lab.Check("construct", "the new buff asks for its spell IDs", true, when.editor:IsShown() and box:IsShown())
            box:SetText("1459, 10157")
            box:GetScript("OnEnterPressed")(box); Lab.Settle(0.1)
            local draft = Dz.State().draft
            Lab.Check("interact", "two spell IDs are taken", 2, draft and #draft.spells or 0)
            Lab.Check("construct", "the editor reads the sentence back", true, when.editor.reads:GetText():find("Reads as:", 1, true) ~= nil)
            local rev = RM.Rev()
            box:SetText("Arcane Intellect")
            box:GetScript("OnEnterPressed")(box); Lab.Settle(0.1)
            Lab.Check("interact", "a name is refused, never matched", 2, #Dz.State().draft.spells)
            Lab.Check("state", "nothing saved while editing", rev, RM.Rev())
            Dz.Say(nil)
            -- bring the new condition's editor into view for the screenshot (its place in the rule, not the range's end)
            local frame, ed = Dz.Frame(), when.editor
            local offset = frame.content:GetTop() - ed:GetTop() - 12
            frame.scroll:SetVerticalScroll(math.max(0, offset)); Lab.Settle(0.1)
            -- (the simulator doesn't move a scrolled child's reported position, so the screenshot is the evidence of where it is)
            Lab.Check("interact", "the rule panel scrolled to the editor", true, frame.scroll:GetVerticalScroll() > 0)
        elseif view == "conditionsPalette" then
            when.picker.category.onPick("Buffs"); Lab.Settle(0.1)
            local names = {}
            for _, row in ipairs(when.picker.rows) do if row:IsShown() and row.entry then names[#names + 1] = row.name:GetText() end end
            table.sort(names)
            Lab.Check("construct", "Buffs lists buff and debuff", "Buff|Debuff", table.concat(names, "|"))
        end
    end
    if view == "catalog" or view == "empty" or view == "hover" then
        C.Toggle()
        if view == "empty" then
            local search = C.Frame().search
            search:SetText("no matching template")
            search:GetScript("OnTextChanged")(search, true)
        end
    elseif view == "when" or view == "nested" or view == "narrow" or view == "drag"
        or view == "dirty" or view == "error" or view == "palette" or view == "situation"
        or view == "details" or view == "actions" or view == "menu" or view == "scale" or view == "wellfed" or view == "conditionMenu" then
        if view == "wellfed" then
            P.Select(RM.List()[2].id); Lab.Settle(0.1)
        else
        local _, group = RM.AddGroup(id, nil, "any")
        RM.MoveNode(id, { 2 }, group)
        RM.AddCondition(id, "player", { 2 }, { type = "player", state = view == "nested" and "combat" or "raid" })
        end
        Dz.Open()
    end
    Lab.Settle(0.2)
    if view == "hover" then
        local use = C.Frame().cards[1].use
        use:GetScript("OnEnter")(use)
    end
    if view == "menu" or view == "scale" then
        if view == "scale" then Dz.Frame().rail:GetParent():SetScale(0.72); Lab.Settle(0.1) end
        local control = view == "menu" and Ed.sections[2].whoEdit or Ed.sections[2].cards[1].fields[1]
        control:Click(); Lab.Settle(0.1)
        local menu = TwichUISettingsMenu
        Lab.Check("geometry", "menu and owner have the same effective scale", true,
            math.abs(menu:GetEffectiveScale() - control:GetEffectiveScale()) < 0.0001)
        Lab.Check("construct", "material menu is visible above the modal", true,
            menu:IsShown() and menu.materialMode and menu:GetFrameStrata() == "DIALOG")
        local menuScale = menu:GetEffectiveScale()
        Lab.Check("geometry", "menu edge follows the visible control", true,
            math.abs(menu:GetLeft() * menuScale - control:GetLeft() * control:GetEffectiveScale()) < 1)
    end
    if view == "wellfed" then
        Lab.Check("construct", "Well Fed wording describes the player's state", true,
            Dz.Frame().result:GetText():find("you are not well fed", 1, true) ~= nil)
    end
    if view == "situation" then Dz.Frame().try:Click(); Lab.Settle(0.1) end
    if view == "details" then Ed.sections[2].explain:Click(); Lab.Settle(0.1) end
    if view == "conditionMenu" then
        local card = Ed.sections[2].cards[1]
        card.more:OpenMenu()
    end
    if view == "actions" then
        local card = Ed.sections[2].cards[1]
        card:GetScript("OnEnter")(card)
        Lab.Check("construct", "hover reveals compact contextual actions", true, card.more:IsShown() and card.more:GetWidth() == 28)
    end
    if view == "drag" then
        local when = Ed.sections[2]
        when.picker.category.onPick("Combat")
        Lab.Settle(0.1)
        local x, y = At(when.addBasic)
        DragTo(when.picker.rows[1], x, y, false)
        local drag = Dz.Frame().ruleDrag
        Lab.Check("interact", "artwork ghost and valid drop feedback are visible", true, drag.marker:IsShown() and drag.ghost:IsShown() and when.addBasic.dropHot)
    end
    if view == "dirty" then
        local before = RM.Rev()
        local when = Ed.sections[2]
        when.cards[1].fields[1].onPick("enchant:offHand")
        Lab.Settle(0.1)
        Lab.Check("construct", "dirty footer exposes Save and Undo", true,
            Dz.Frame().dirty:IsShown() and Dz.Frame().save:IsEnabled() and when.undo:IsEnabled())
        Lab.Check("state", "the displayed draft still has no live revision", before, RM.Rev())
    end
    if view == "error" then
        local before = RM.Rev()
        local when = Ed.sections[2]
        Dz.SetAdvanced(true); Lab.Settle(0.1)
        when.rootGroup.add:Click()
        Dz.AddGroup("any"); Lab.Settle(0.1)
        Dz.Frame().save:Click(); Lab.Settle(0.1)
        Lab.Check("construct", "validation stays visible above the footer", true, Dz.Frame().message:GetText():find("has no conditions", 1, true) ~= nil)
        Lab.Check("state", "validation failure writes nothing", before, RM.Rev())
    end
    if view == "nested" then
        local before = RM.Rev()
        Lab.Check("construct", "nested rule opens advanced automatically", true, Ed.sections[2].isAdvanced and Ed.sections[2].groups[1].box:IsShown())
        Ed.sections[2].advanced:Click()
        Lab.Check("state", "advanced rule stays intact", before, RM.Rev())
    end
    if view == "palette" then
        Ed.sections[2].picker.category.onPick("Other")
        Lab.Settle(0.1)
    end
    if view == "narrow" then
        Lab.Check("construct", "conditions use dedicated workspace at constrained width", "workspace", Dz.Frame().placement)
    end
    Lab.Check("state", "pose still disabled", false, RM.Get(id).enabled)
end)
-- Screenshot fixture only: move Blizzard's PTR feedback button beside the addon.
if PTR_IssueReporter then
    PTR_IssueReporter:ClearAllPoints()
    PTR_IssueReporter:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 8, -200)
end
Lab.Finish()
