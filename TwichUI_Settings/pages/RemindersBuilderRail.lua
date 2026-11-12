-- The When workspace owns presentation only. Selection and appearance stay with the Reminders page.
local R = TwichUI
local Rail = {}
R.RemindersBuilderRail = Rail

local WIDTH, GAP, INSET = 292, 22, 22
local ROW, LIST_H = 46, 150

function Rail.Build(rightWidth, height, onSelect, onEdit)
    local G, M, D = R.SettingsWidgets, R.SettingsMaterial, R.ReminderDisplay
    local root = CreateFrame("Frame", nil, UIParent)
    root:SetAllPoints(UIParent)
    root:SetFrameStrata("HIGH")
    root:SetToplevel(true)
    root:EnableMouse(true)
    root:Hide()
    local backdrop = G.Solid(root, "BACKGROUND", { 0, 0, 0 }, 0.35)
    backdrop:SetAllPoints()
    local pair = CreateFrame("Frame", nil, root)
    pair:SetPoint("CENTER")
    pair:SetSize(WIDTH + GAP + rightWidth, height)
    local function Fit()
        local uiScale = UIParent:GetEffectiveScale()
        local anchor = R.SettingsAnchor and R.SettingsAnchor()
        local preferred = anchor and anchor:GetEffectiveScale() / uiScale or 1
        pair:SetScale(math.min(preferred, (UIParent:GetWidth() - 24) / pair:GetWidth(),
            (UIParent:GetHeight() - 24) / height))
    end
    root:SetScript("OnShow", function(self)
        self:Raise()
        self:RegisterEvent("UI_SCALE_CHANGED")
        self:RegisterEvent("DISPLAY_SIZE_CHANGED")
        Fit()
    end)
    root:SetScript("OnHide", function(self) self:UnregisterAllEvents() end)
    root:SetScript("OnEvent", Fit)

    local left = CreateFrame("Frame", nil, pair)
    left:SetSize(WIDTH, height)
    left:SetPoint("TOPLEFT")
    M.WorkspaceFrame(left)
    M.HeaderBand(left, 65)
    local right = CreateFrame("Frame", "TwichUIReminderConditions", pair)
    right:SetSize(rightWidth, height)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", GAP, 0)
    right:EnableMouse(true)
    M.WorkspaceFrame(right)
    right.placement = "workspace"

    local hinge = M.FrameConnector(pair, 64)
    hinge:SetPoint("CENTER", left, "TOPRIGHT", GAP / 2, -112)

    local function Heading(parent, label, y, size)
        local fs = M.ReminderFont(G.Text(parent, "title"), size or 17, true)
        fs:SetPoint("TOPLEFT", INSET, -y)
        fs:SetText(label)
        return fs
    end
    local function Divider(y)
        local line = G.Solid(left, "ARTWORK", G.pal.bronzeLo, 0.56)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", INSET, -y)
        line:SetPoint("TOPRIGHT", -INSET, -y)
    end
    local title = Heading(left, "Reminders", 20, 23)
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", 66, -24)
    local crest = left:CreateTexture(nil, "ARTWORK")
    crest:SetSize(36, 36)
    crest:SetPoint("TOPLEFT", 22, -17)
    R.Icons.Apply(crest, "reminders", 36)
    Divider(65)

    local w = WIDTH - INSET * 2
    local scroll, content = G.Scroll(left, w - 12)
    scroll:SetSize(w - 12, LIST_H)
    scroll:SetPoint("TOPLEFT", INSET, -75)
    local fitRail = M.ScrollRail(scroll)
    local rows = {}
    left.rows, left.scroll = rows, scroll
    Divider(241)
    Heading(left, "Reminder", 258)
    local chosen = CreateFrame("Frame", nil, left)
    chosen:SetSize(w, 40)
    chosen:SetPoint("TOPLEFT", INSET, -283)
    M.PanelFace(chosen, "espresso")
    local chosenIcon = chosen:CreateTexture(nil, "ARTWORK")
    chosenIcon:SetPoint("CENTER", chosen, "LEFT", 22, 0)
    local chosenName = M.ReminderFont(G.Text(chosen, "body"), 14, true)
    chosenName:SetPoint("LEFT", 43, 0)
    chosenName:SetWidth(w - 52)
    chosenName:SetMaxLines(2)
    Divider(340)
    Heading(left, "When", 357)
    local summaryScroll, summary = G.Scroll(left, w - 12)
    summaryScroll:SetPoint("TOPLEFT", INSET, -384)
    summaryScroll:SetSize(w - 12, 112)
    local fitSummary = M.ScrollRail(summaryScroll)
    local summaryRows = {}
    Divider(512)
    Heading(left, "Appearance", 529)
    local sample = CreateFrame("Frame", nil, left)
    sample:SetPoint("TOPLEFT", INSET, -557)
    sample:SetSize(w, 111)
    local paper = sample:CreateTexture(nil, "BACKGROUND")
    paper:SetAllPoints()
    paper:SetTexture(R.PATH .. [[media\reminders\preview-parchment.tga]])
    left.sample = sample
    local surface = D.NewSurface(sample)
    left.surface = surface

    local function Row(i)
        if rows[i] then return rows[i] end
        local row = CreateFrame("Button", nil, content)
        row:SetSize(w - 12, ROW - 3)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        M.ReminderRow(row)
        M.MaterialHover(row)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("CENTER", row, "LEFT", 22, 0)
        row.name = M.ReminderFont(G.Text(row, "heading"), 14, true)
        row.name:SetWidth(w - 74)
        row.name:SetMaxLines(2)
        row.name:SetPoint("LEFT", 44, 0)
        M.ContextTip(row, "Reminder", function() return row.name:GetText() end)
        local arrow = M.ReminderFont(G.Text(row, "body"), 18)
        arrow:SetPoint("RIGHT", -9, 0)
        arrow:SetText("›")
        G.Color(arrow, G.pal.bronzeText)
        row:SetScript("OnClick", function(self) if self.id then onSelect(self.id) end end)
        rows[i] = row
        return row
    end

    function left:Draw(saved, draft)
        local reminders = R.Reminders.List()
        local selectedIndex
        for i, view in ipairs(reminders) do
            local row = Row(i)
            row.id = view.id
            row.name:SetText(view.name)
            R.RemindersEditor.Thumb(row.icon, view.display, 30)
            row.sel:SetShown(view.id == saved.id)
            row:Show()
            if view.id == saved.id then selectedIndex = i end
        end
        for i = #reminders + 1, #rows do rows[i]:Hide() end
        local full = math.max(1, #reminders * ROW)
        content:SetHeight(full)
        if fitRail then fitRail(full) end
        if self.selected ~= saved.id and selectedIndex then
            self.selected = saved.id
            local y = (selectedIndex - 1) * ROW
            local old = scroll:GetVerticalScroll() or 0
            if y < old or y + ROW > old + LIST_H then
                scroll:SetVerticalScroll(math.max(0, math.min(y, full - LIST_H)))
            end
        end
        R.RemindersEditor.Thumb(chosenIcon, saved.display, 27)
        chosenName:SetText(saved.name)
        local summaryHeight = R.RemindersPlain.DrawExplanation(summary, summaryRows, draft, w - 12, 0, true)
        summary:SetHeight(summaryHeight)
        if fitSummary then fitSummary(summaryHeight) end
        D.DrawSurface(surface, draft, w - 34, 78)
        surface.text:SetTextColor(.18, .13, .08, 1)
        local file, size = surface.text:GetFont()
        surface.text:SetFont(file, size, "")
        surface.text:SetShadowOffset(0, 0)
        surface:ClearAllPoints()
        surface:SetPoint("CENTER", sample)
    end
    right.workspace, right.rail = root, left
    return right
end
