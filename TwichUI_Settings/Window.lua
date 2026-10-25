-- TwichUI Settings: the settings window
-- One window, made the first time it opens: a header (title, search, close), the pages on the left grouped by
-- what they are for, the page on the right, and a footer with the profile in use and any reload a change waits
-- for. A page's rows are made the first time the page is shown and kept for the session; a page is drawn again
-- (values, what is greyed out and why) each time it is shown and after a change. Nothing runs while it is shut.
--
-- Esc: the dropdown list first, then the window (the search box, while typing, clears itself first). The window
-- never takes keys while no box has focus, so play keys keep working with it open.

local R = TwichUI
local K = R.SettingsKit
local Wg = R.SettingsWidgets
local Search = R.SettingsSearch
local I = R.Interact
local S = R.ChronicleStyle
local Cards, Previews, Home, Icons = R.SettingsCards, R.SettingsPreviews, R.SettingsHome, R.Icons
local pal = Wg.pal
local Motion = Wg.Motion
local T = Motion.TIME   -- every duration used here is in Widgets.lua's table
local UI = {}

local WIDTH, HEIGHT = 920, 660
local HEADER_H, FOOTER_H, NAV_W, PAD = 54, 38, 212, 14
local CONTENT_W = WIDTH - PAD - NAV_W - 12 - 24 - PAD
local CONTROL_W = 236
local ROW_MIN, SECTION_PAD, GAP = 30, 14, 14
local RESET_H, PAGE_BOTTOM = 52, 12   -- the page's own Reset area, and the room under the last thing on a page
local NAV_ROW, NAV_GROUP = 30, 24
local NAV_ICON = 20   -- a page's icon beside its name in the list (the 32 px file)
local TAB_H = 28
local HOST_H = 540
local HIGHLIGHT_SECONDS = 2.5

local win, nav, scroll, content, resultsView, footer, searchBox
local state = { views = {}, results = {}, selected = 1, suspend = 0, navItems = {}, scrollOf = {} }

-- The profile in use and who else uses it, in words: the footer and the top of a page of feature cards say the
-- same. nil when profiles aren't available.
local function ProfileShare()
    local P = R.Profiles
    local current = P and P.Current and P.Current()
    if not current then return nil end
    local others = #P.UsedBy(current, true)
    return current, others == 0 and "used only by this character"
        or ("shared with " .. (others == 1 and "1 other character" or (others .. " other characters")))
end

local function Place()
    local saved = TwichUIDB.ui.settingsWindow
    win:ClearAllPoints()
    if type(saved) == "table" and type(saved.point) == "string" and type(saved.relativePoint) == "string"
        and type(saved.x) == "number" and type(saved.y) == "number" and saved.x == saved.x and saved.y == saved.y then
        win:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
end

local function SavePlace()
    local point, _, relativePoint, x, y = win:GetPoint(1)
    if not point then return end
    TwichUIDB.ui.settingsWindow = { point = point, relativePoint = relativePoint, x = x, y = y }
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function ShowTipOf(frame)
    local fn = frame:GetScript("OnEnter")
    if fn then fn(frame) end
end

local function LinkTip(frame, control)
    control:HookScript("OnEnter", function() ShowTipOf(frame) end)
    control:HookScript("OnLeave", function() I.HideTip(frame) end)
end

local function ButtonText(row)
    local text = row.data.buttonText
    if type(text) == "function" then text = text() end
    return text or ""
end

-- The label of a dropdown's value (looked up again only when the value changes).
local function ChoiceLabel(v, value)
    if v.lastValue == value and v.lastLabel then return v.lastLabel end
    local label
    for _, choice in ipairs(v.row.choices and v.row.choices() or {}) do
        if choice.value == value then label = choice.label break end
    end
    v.lastValue, v.lastLabel = value, label or tostring(value or "")
    return v.lastLabel
end

-- The colors a row's note can take (K.Note): quiet by default, bronze for a change waiting on a reload, the
-- warning color for something chosen that can't work as set. The words say the same, so color is never the
-- only signal.
local TONE = { reload = pal.bronzeText, warn = pal.danger.text }

-- The line a row shows under its label when it is not greyed out, and its tone: a pending reload first (read
-- from Switches.lua, the one record of it), then the row's own note.
local function Note(row)
    if row.switch and R.Switches.IsPending(row.switch) then
        return "Reload your UI to apply this change.", "reload"
    end
    if row.note then
        local ok, text, tone = pcall(row.note)
        if ok and type(text) == "string" and text ~= "" then return text, tone end
    end
    return nil
end

-- What a color swatch opens (Widgets.lua's ColorPicker.Status): EllesmereUI's picker when it is there, else the
-- game's own. Not an error either way.
local PICKER_NOTE = {
    ready = "Opens EllesmereUI's color picker.",
    ["on-demand"] = "Opens EllesmereUI's color picker, which loads the first time you click.",
    ["load-failed"] = "EllesmereUI's color picker couldn't be loaded, so the game's own color picker is used. Colors are saved the same way.",
    unsupported = "Opens the game's own color picker (EllesmereUI's isn't available). Colors are saved the same way.",
}

local function MakeRow(parent, row, width)
    local v = { row = row }
    local f = CreateFrame("Button", nil, parent)
    f:SetWidth(width)
    f:SetHeight(ROW_MIN)
    v.frame = f
    f.bg = Wg.Solid(f, "BACKGROUND", pal.text, 0)   -- the landing highlight from a search result
    f.bg:SetAllPoints()
    local wash = Wg.Solid(f, "BACKGROUND", pal.text, 0.04)   -- the pointer's wash, eased
    wash:SetAllPoints()
    v.wash = Motion.Fader(function(x) wash:SetAlpha(x) end, 0)
    local indent = row.parent and 18 or 0
    if row.parent then
        -- the rail a child setting hangs from: the whole height of the row, so rows in a run join up
        local guide = Wg.Solid(f, "BORDER", pal.bronzeLo, 0.7)
        guide:SetWidth(1)
        guide:SetPoint("TOPLEFT", 7, 0)
        guide:SetPoint("BOTTOMLEFT", 7, 0)
    end
    local labelW = width - CONTROL_W - indent - 16
    v.label = Wg.Text(f, "body")
    v.label:SetPoint("TOPLEFT", indent + 6, -8)
    v.label:SetWidth(labelW)
    v.label:SetWordWrap(true)
    v.reason = Wg.Text(f, "meta")
    v.reason:SetPoint("TOPLEFT", v.label, "BOTTOMLEFT", 0, -3)
    v.reason:SetWidth(labelW)
    if row.badge then
        v.badge = Wg.Tag(f, row.badge)   -- information, not an action: flat, with no edge
    end

    local setting = row.data.setting
    local controlX = width - CONTROL_W
    local kind = row.kind

    -- The tooltip first (a script set later would drop hooks added before it), then each kind's own hover.
    I.Tip(f, nil, function()
        local tip = row:GetTooltip()
        if kind == "swatch" then
            -- which picker a click opens, read now (nothing is loaded or asked of EllesmereUI to say it)
            local note = PICKER_NOTE[Wg.ColorPicker.Status()]
            if note then tip = (tip and (tip .. "\n\n") or "") .. note end
        end
        if kind ~= "link" then
            local why = not row:Enabled() and row:DisabledReason() or nil
            if why and tip and tip:lower():find(why:lower(), 1, true) then why = nil end   -- said already
            return tip, why
        end
        return tip
    end)
    local show = f:GetScript("OnEnter")
    f:SetScript("OnEnter", function(self)
        -- the tooltip's title is the row's label as it is now
        self.twichuiTip.title = (row:GetName() or ""):gsub("%s%s%s.*$", "")
        -- (a row greyed out gets none: it does nothing)
        if kind == "link" or (kind == "checkbox" and row:Enabled()) then v.wash:To(1, T.hover) end
        show(self)
    end)
    f:HookScript("OnLeave", function() v.wash:To(0, T.hover) end)
    f:HookScript("OnHide", function() v.wash:Set(0) end)
    if kind == "checkbox" then
        v.control = Wg.Checkbox(f, function(on) setting:SetValue(on) end)
        v.control:SetPoint("TOPLEFT", f, "TOPLEFT", controlX, -6)
        -- the whole row is the checkbox's label
        f:SetScript("OnClick", function()
            if row:Enabled() then setting:SetValue(not setting:GetValue()) end
        end)
        f:HookScript("OnEnter", function() v.control:SetHot(true) end)
        f:HookScript("OnLeave", function() v.control:SetHot(false) end)
    elseif kind == "dropdown" then
        v.control = Wg.Dropdown(f, CONTROL_W - 8, function(value) setting:SetValue(value) end)
        v.control:SetChoices(row.choices)
        v.control:SetPoint("TOPLEFT", f, "TOPLEFT", controlX, -4)
    elseif kind == "slider" then
        v.control = Wg.Slider(f, CONTROL_W - 8, function(value) setting:SetValue(value) end)
        v.control:SetRange(row.options.min, row.options.max, row.options.step)
        v.control:SetPoint("TOPLEFT", f, "TOPLEFT", controlX, -4)
    elseif kind == "swatch" then
        v.control = Wg.Swatch(f, function(hex) setting:SetValue(hex) end)
        v.control:SetPoint("TOPLEFT", f, "TOPLEFT", controlX, -6)
    elseif kind == "button" then
        v.control = Wg.Button(f, ButtonText(row), 110, row.reset and "danger" or "secondary", function()
            if row:Enabled() and row.click then row.click() end
        end)
        v.control:SetPoint("TOPLEFT", f, "TOPLEFT", controlX, -4)
    elseif kind == "status" then
        v.status = Wg.Text(f, "small")
        v.status:SetPoint("TOPLEFT", f, "TOPLEFT", controlX, -9)
        v.status:SetWidth(CONTROL_W - 8)
        v.status:SetWordWrap(true)
    elseif kind == "link" then
        v.status = Wg.Text(f, "small")
        v.status:SetPoint("TOPLEFT", f, "TOPLEFT", controlX, -9)
        v.status:SetWidth(CONTROL_W - 30)
        v.status:SetWordWrap(false)
        v.chevron = Wg.Text(f, "meta")
        v.chevron:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -9)
        v.chevron:SetText("Open")
        f:SetScript("OnClick", function() if row.click then row.click() end end)
        f:HookScript("OnEnter", function() Wg.Color(v.chevron, pal.tealHi) end)
        f:HookScript("OnLeave", function() Wg.Color(v.chevron, pal.stone) end)
    end
    if row.extra and v.control then
        local ok, extra = pcall(row.extra, f, v.control)
        if ok then v.extra = extra else R.Fault("settings row " .. row.id, extra) end
    end

    if v.control then
        LinkTip(f, v.control)
        if v.control.slider then LinkTip(f, v.control.slider) end
    end

    -- What it shows now. Cheap: values and states only.
    function v.RefreshValue()
        local enabled = row:Enabled()
        if kind == "checkbox" then
            v.control:SetChecked(setting:GetValue() and true or false)
            v.control:SetActive(enabled)
        elseif kind == "dropdown" then
            local value = setting:GetValue()
            v.control:SetValue(value, ChoiceLabel(v, value))
            v.control:SetActive(enabled)
        elseif kind == "slider" then
            v.control:SetValue(setting:GetValue() or row.options.min)
            v.control:SetActive(enabled)
        elseif kind == "swatch" then
            v.control:SetValue(setting:GetValue())
            v.control:SetActive(enabled)
        elseif kind == "button" then
            local text = ButtonText(row)
            v.control.text:SetText(text)
            v.control:SetWidth(math.min(CONTROL_W - 8, math.max(110, v.control.text:GetStringWidth() + 28)))
            v.control:SetEnabled(enabled)
        elseif kind == "link" then
            local ok, status = pcall(row.status or function() return "" end)
            v.status:SetText(ok and status or "")
        elseif kind == "status" then
            local ok, text = pcall(row.value or function() return "" end)
            v.status:SetText(ok and tostring(text or "") or "")
            local toneOk, tone = true, nil
            if row.tone then toneOk, tone = pcall(row.tone) end
            local c = pal.text
            if toneOk and tone == "ok" then c = pal.tealHi
            elseif toneOk and tone == "warn" then c = pal.danger.text
            elseif toneOk and tone == "quiet" then c = pal.stone end
            Wg.Color(v.status, c)
        end
        if v.extra and row.refreshExtra then pcall(row.refreshExtra, v.extra) end
        return enabled
    end

    -- Everything, and its height (which can change with the label or the reason).
    function v.Refresh()
        v.lastLabel = nil   -- a choice's label can change (a tree's name in "Automatic (...)", a renamed profile)
        local enabled = v.RefreshValue()
        local label = row:GetName() or ""
        if kind == "link" then label = label:gsub("%s%s%s.*$", "") end
        v.label:SetText(label)
        Wg.Color(v.label, (enabled or kind == "link") and pal.text or pal.stone)
        local reason = kind ~= "link" and kind ~= "status" and not enabled and row:DisabledReason() or nil
        if kind == "status" and row.detail then
            local ok, text = pcall(row.detail)
            if ok and type(text) == "string" and text ~= "" then reason = text end
        end
        -- Not greyed out: a change waiting on a reload, or the row's own note (a fallback in use, an
        -- integration missing). A greyed-out row says why it is greyed out instead.
        local tone, noted
        if not reason and kind ~= "link" and kind ~= "status" then
            reason, tone = Note(row)
            noted = reason ~= nil
        end
        v.reason:SetText(reason or "")
        Wg.Color(v.reason, TONE[tone] or (noted and pal.textDim or pal.stone))
        v.reason:SetShown(reason ~= nil)
        if v.badge then
            v.badge:ClearAllPoints()
            v.badge:SetPoint("LEFT", v.label, "LEFT", math.min(v.label:GetStringWidth(), v.label:GetWidth()) + 8, 0)
        end
        local h = (v.label:GetStringHeight() or 12) + 16
        if reason then h = h + (v.reason:GetStringHeight() or 10) + 3 end
        if kind == "status" then h = math.max(h, (v.status:GetStringHeight() or 12) + 18) end   -- a value that wraps
        f:SetHeight(math.max(ROW_MIN, h))
        return f:GetHeight()
    end
    return v
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local function SectionId(page, header) return header and header.id or (page.key .. ":intro") end

-- A page's own frame (def.host) is HOST_H tall and comes before its rows, unless the page gives def.hostHeight
-- and def.hostAfter (the name of the section it follows: rows on either side of it, such as a switch above a
-- list and its keys below).
local function HostHeight(page)
    local h = page.def.hostHeight
    return (type(h) == "number" and h > 0) and h or HOST_H
end

-- A feature's notice (its K.Page def's notice: { tag, text }): a rust card above each of its pages, tabs included.
-- The tag is a chip, the words sit under it, and a thin rust edge runs down the left. Its height is set in Layout.
local NOTICE_PAD, NOTICE_EDGE, NOTICE_TAG_H, NOTICE_GAP = 12, 3, 15, 8
local function Notice(parent, notice)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Wg.Surface(card, pal.danger.bg, 0.92, pal.danger.border, 1)
    card:SetWidth(CONTENT_W)
    local edge = Wg.Solid(card, "ARTWORK", pal.danger.hotBorder, 1)
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(NOTICE_EDGE)
    card.tag = Wg.Tag(card, notice.tag:upper())
    card.tag:SetPoint("TOPLEFT", NOTICE_PAD + NOTICE_EDGE, -NOTICE_PAD)
    Wg.Color(card.tag.text, pal.danger.hotText)
    card.body = Wg.Text(card, "body")
    card.body:SetPoint("TOPLEFT", NOTICE_PAD + NOTICE_EDGE, -NOTICE_PAD - NOTICE_TAG_H - NOTICE_GAP)
    card.body:SetWidth(CONTENT_W - NOTICE_PAD * 2 - NOTICE_EDGE)
    card.body:SetText(notice.text)
    Wg.Color(card.body, pal.text)
    return card
end

-- A feature's tabs: one per page of the family (Look's Tab: the shown one has a faint bronze fill and a bar on
-- the rule below). Choosing one goes to that page (a stable page key, as search and direct links use); its rows
-- are made the first time.
local function TabStrip(parent, tabs, current)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(TAB_H)
    strip:SetWidth(CONTENT_W)
    local x = 0
    for _, tab in ipairs(tabs) do
        local selected = tab.key == current
        local b = Wg.Tab(strip, K.TabLabel(tab), 24, not selected and function() UI.Navigate(tab.key) end or nil)
        b:SetSize(b.text:GetStringWidth() + 24, TAB_H)
        b:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", x, 0)
        b:SetSelected(selected)
        x = x + b:GetWidth() + 2
    end
    return strip
end

local Layout   -- (below)

-- Places a section's rows from `inner` down, drawing each as it goes; a row not shown with the current choices
-- is hidden. Returns the new `inner` and how many rows are shown. A feature card places its rules through this too.
function UI.PlaceRows(sec, rows, inner)
    local visible = 0
    for _, v in ipairs(rows) do
        if v.row:Shown() then
            v.frame:ClearAllPoints()
            v.frame:SetPoint("TOPLEFT", sec.card, "TOPLEFT", SECTION_PAD - 4, -inner)
            v.y = sec.top + inner
            inner = inner + v.Refresh()
            v.frame:Show()
            visible = visible + 1
        else
            v.frame:Hide()
            v.y = nil
        end
    end
    return inner, visible
end

-- What a feature card (Cards.lua) is given to draw with: the window's own row placing, row notes and tones.
UI.cardEnv = {
    PAD = SECTION_PAD,
    TONE = TONE,
    Note = Note,
    PlaceRows = function(sec, rows, inner) return (UI.PlaceRows(sec, rows, inner)) end,
    Relayout = function()
        local view = state.views[state.page]
        if view and not state.searching then Layout(view) end
    end,
}

local function BuildView(page)
    local view = { page = page, sections = {}, rows = {} }
    local frame = CreateFrame("Frame", nil, content)
    frame:SetPoint("TOPLEFT", 0, 0)
    frame:SetWidth(CONTENT_W)
    view.frame = frame
    state.views[page.key] = view

    -- the page's own header: title, status, one line of what it is for. A feature with pages under it
    -- (K.Tabs) is titled with the feature's name and shows its tabs between the title and the line, which then
    -- describes the tab shown.
    local tabs = K.Tabs(page.key)
    local root = K.Root(page.key)
    view.title = Wg.Text(frame, "title")
    view.title:SetPoint("TOPLEFT", 2, -4)
    view.title:SetText(#tabs > 0 and root.name or (page.group == "home" and page.nav or page.name))
    if #tabs > 0 then view.tabs = TabStrip(frame, tabs, page.key) end
    view.status = Wg.Text(frame, "small")
    view.status:SetPoint("TOPRIGHT", -4, -8)
    view.status:SetJustifyH("RIGHT")
    view.desc = Wg.Text(frame, "small")
    view.desc:SetWidth(CONTENT_W - 8)
    view.desc:SetText(page.def.description or (page.def.overview and page.def.overview.tip) or "")
    view.rule = Wg.Solid(frame, "BORDER", pal.bronzeLo, 0.75)
    view.rule:SetHeight(1)
    view.rule:SetPoint("LEFT", frame, "LEFT", 0, 0)
    view.rule:SetPoint("RIGHT", frame, "RIGHT", 0, 0)

    -- a feature's notice, above every one of its pages (its tabs too)
    local root = K.Root(page.key)
    local notice = root and root.def.notice
    if notice then view.notice = Notice(frame, notice) end

    if page.failed then
        view.failed = Wg.Text(frame, "small")
        view.failed:SetWidth(CONTENT_W - 8)
        view.failed:SetText("Part of this page couldn't be built, so some of its settings may be missing. /tui diagnostics has the error. The rest of TwichUI is unaffected.")
        Wg.Color(view.failed, pal.danger.text)
    end

    if page.def.host then
        local ok, hosted = pcall(page.def.host)
        if ok and hosted then
            hosted:SetParent(frame)
            hosted:ClearAllPoints()
            hosted:SetSize(CONTENT_W, HostHeight(page))
            view.hosted = hosted
        else
            R.Fault("settings page " .. page.key, hosted)
            view.failed = view.failed or Wg.Text(frame, "small")
            view.failed:SetWidth(CONTENT_W - 8)
            view.failed:SetText("This page couldn't be shown. /tui diagnostics has the error. The rest of TwichUI is unaffected.")
            Wg.Color(view.failed, pal.danger.text)
        end
    end

    -- sections, in the order their headers come; rows in theirs
    local byId = {}
    local function Section(header)
        local id = SectionId(page, header)
        local sec = byId[id]
        if sec then return sec end
        sec = { id = id, header = header, rows = {} }
        byId[id] = sec
        view.sections[#view.sections + 1] = sec
        sec.card = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        Wg.Panel(sec.card)
        sec.card:SetWidth(CONTENT_W)
        if header then
            local titled = (header:GetName() or ""):lower() ~= page.name:lower()
            sec.titled = titled
            sec.title = Wg.Text(sec.card, "heading")
            sec.title:SetWidth(CONTENT_W - SECTION_PAD * 2 - 90)
            sec.desc = Wg.Text(sec.card, "small")
            sec.desc:SetWidth(CONTENT_W - SECTION_PAD * 2)
            if header.badge then
                sec.badge = Wg.Text(sec.card, "meta")
                sec.badge:SetText(header.badge)
            end
            if header.card and Cards then
                Cards.Build(view, sec, CONTENT_W, UI.cardEnv)
                view.hasCards = true
            end
        end
        return sec
    end
    view.sectionsById = byId
    for _, row in ipairs(page.rows) do
        if row.kind == "header" then
            Section(row)
        else
            local sec = Section(row.section)
            local v
            if row.primaryOf and sec.isCard then
                v = Cards.Primary(sec, row, UI.cardEnv)   -- a card's switch is drawn in its head
                sec.primaryView = v
            else
                v = MakeRow(sec.card, row, CONTENT_W - SECTION_PAD * 2 + 8)
                v.rule = sec.isCard and row.ruleOf ~= nil
                sec.rows[#sec.rows + 1] = v
            end
            v.section = sec
            view.rows[row.id] = v
        end
    end

    -- Home's three ways in (Home.lua), above its sections
    if page.def.hero and Home then
        view.hero = Home.Build(frame, CONTENT_W, {
            Navigate = function(key, rowId) UI.Navigate(key, rowId) end,
            Relayout = function() Layout(view) end,
        })
    end
    -- a page of feature cards says which profile its changes are saved in, and who else that profile is for
    if view.hasCards then
        view.scope = Wg.Text(frame, "meta")
        view.scope:SetWidth(CONTENT_W - 8)
    end

    -- Reset this page: every setting on it back to its default, after saying exactly what that covers
    local resettable = K.Resettable(page.key)
    if #resettable > 0 then
        view.reset = CreateFrame("Frame", nil, frame)
        view.reset:SetSize(CONTENT_W, RESET_H)
        local rule = Wg.Solid(view.reset, "BORDER", pal.bronzeLo, 0.45)   -- neutral: Reset is not the page's headline
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", 0, 0)
        rule:SetPoint("TOPRIGHT", 0, 0)
        local text = Wg.Text(view.reset, "small")
        text:SetPoint("TOPLEFT", 2, -17)
        text:SetWidth(CONTENT_W - 170)
        text:SetText("Reset this page's settings to their defaults. It asks first and lists what would change. Other pages and saved data are unchanged.")
        local button = Wg.Button(view.reset, "Reset this page", 140, "danger", function()
            -- counted now, from the settings as they are: only what differs is changed, and the question says what
            local plan = K.ResetPagePlan(page.key)
            if plan.count == 0 then
                R.Print("everything on the %s page is already at its default.", page.name)
                return
            end
            I.Confirm("TWICHUI_SETTINGS_RESET_PAGE", K.ResetPageText(page, plan),
                function()
                    state.suspend = state.suspend + 1
                    local ok, err = pcall(K.ResetPage, page.key)
                    state.suspend = state.suspend - 1
                    if not ok then R.Fault("reset page " .. page.key, err) end
                    Layout(view)
                    UI.RefreshFooter()
                end, { accept = "Reset" })
        end)
        button:SetPoint("TOPRIGHT", -2, -12)
    end

    -- What arrives when the page does: the cards, the hosted frame, Reset. The title and tabs stay put, so
    -- moving between a feature's tabs changes only what is under them. Alpha only; nothing moves.
    local body = {}
    for _, sec in ipairs(view.sections) do body[#body + 1] = sec.card end
    if view.hero then body[#body + 1] = view.hero.frame end
    if view.hosted then body[#body + 1] = view.hosted end
    if view.reset then body[#body + 1] = view.reset end
    if view.notice then body[#body + 1] = view.notice end
    view.fade = Motion.Fader(function(a)
        for i = 1, #body do body[i]:SetAlpha(a) end
    end, 1)
    return view
end

-- Places every visible row, section and the reset area, top to bottom; draws each row as it goes.
function Layout(view)
    local frame, page = view.frame, view.page
    local ok, status = true, ""
    if page.def.overview and page.def.overview.status then ok, status = pcall(page.def.overview.status) end
    view.status:SetText(ok and status or "")
    local y = 4 + (view.title:GetStringHeight() or 18) + 6
    local hasDesc = view.desc:GetText() ~= ""
    local function Desc()
        view.desc:ClearAllPoints()
        view.desc:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -y)
        if hasDesc then y = y + (view.desc:GetStringHeight() or 12) + 10 else y = y + 4 end
        if view.scope then
            local current, shared = ProfileShare()
            view.scope:SetText(current and ("Saved in the profile \"%s\", %s."):format(current, shared)
                or "Profiles aren't available right now.")
            view.scope:ClearAllPoints()
            view.scope:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -(y - 4))
            y = y - 4 + (view.scope:GetStringHeight() or 12) + 10
        end
    end
    local function Rule()
        view.rule:ClearAllPoints()
        view.rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
        view.rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
    end
    if view.tabs then
        -- title, tabs resting on the rule, then the line about the tab shown
        view.tabs:ClearAllPoints()
        view.tabs:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(y + 4))
        y = y + 4 + TAB_H
        Rule()
        y = y + 10
        Desc()
        y = y + (hasDesc and 4 or 0)
    else
        -- title, the line about the page, then the rule
        Desc()
        Rule()
        y = y + 14
    end
    if view.notice then
        view.notice:ClearAllPoints()
        view.notice:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
        local h = NOTICE_PAD * 2 + NOTICE_TAG_H + NOTICE_GAP + (view.notice.body:GetStringHeight() or 14)
        view.notice:SetHeight(h)
        y = y + h + 14
    end
    if view.failed then
        view.failed:ClearAllPoints()
        view.failed:SetPoint("TOPLEFT", 2, -y)
        y = y + (view.failed:GetStringHeight() or 12) + 12
    end
    if view.hero then y = y + view.hero:Layout(y) + GAP end
    local after = view.hosted and page.def.hostAfter or nil
    local function PlaceHost(gap)
        view.hosted:ClearAllPoints()
        view.hosted:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
        view.hosted:Show()
        y = y + HostHeight(page) + gap
    end
    if view.hosted and not after then PlaceHost(0) end
    local placed = false
    for _, sec in ipairs(view.sections) do
        local card, inner = sec.card, SECTION_PAD
        local visible = 0
        sec.top = y
        if sec.isCard then
            inner = Cards.Layout(view, sec, inner, UI.cardEnv)
            visible = 1
        elseif sec.header and sec.titled then
            sec.title:SetText(sec.header:GetName() or "")
            sec.title:ClearAllPoints()
            sec.title:SetPoint("TOPLEFT", SECTION_PAD, -inner)
            sec.title:Show()
            if sec.badge then
                sec.badge:ClearAllPoints()
                sec.badge:SetPoint("LEFT", sec.title, "LEFT", math.min(sec.title:GetStringWidth(), sec.title:GetWidth()) + 10, 0)
            end
            inner = inner + (sec.title:GetStringHeight() or 14) + 4
        elseif sec.title then
            sec.title:Hide()
            if sec.badge then sec.badge:Hide() end
        end
        if sec.desc and not sec.isCard then
            local desc = sec.header:GetTooltip() or ""
            sec.desc:SetText(desc)
            sec.desc:ClearAllPoints()
            sec.desc:SetPoint("TOPLEFT", SECTION_PAD, -inner)
            sec.desc:SetShown(desc ~= "")
            if desc ~= "" then inner = inner + (sec.desc:GetStringHeight() or 12) + 8 end
        end
        if not sec.isCard then
            local shown
            inner, shown = UI.PlaceRows(sec, sec.rows, inner)
            visible = visible + shown
        end
        inner = inner + SECTION_PAD - 6
        local empty = visible == 0 and not sec.header
        card:SetShown(not empty)
        if not empty then
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
            card:SetHeight(inner)
            y = y + inner + GAP
            placed = true
        end
        if after and sec.header and sec.header:GetName() == after then
            PlaceHost(GAP)
            after = nil
        end
    end
    if after then   -- the section it follows isn't on the page: after the last one
        PlaceHost(GAP)
        placed = true
    end
    if placed then y = y - GAP end   -- the gap belongs between two things, not after the last
    if view.reset then
        view.reset:ClearAllPoints()
        view.reset:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(y + 18))
        y = y + 18 + RESET_H
    end
    -- exactly what is drawn, so the scroll range (and its bar) is there only when something is out of view
    frame:SetHeight(y + PAGE_BOTTOM)
    content:SetHeight(y + PAGE_BOTTOM)
end
UI.Layout = Layout

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------
-- A row of the left-hand list: shown (gold, a bar and a lighter band), hovered (ivory, a faint wash) or at rest
-- (muted). A feature stays shown while one of its tabs is.
local function PaintItem(item, selected)
    item.bar:SetShown(selected)
    item.fill:SetShown(selected)
    item.wash:SetShown(selected)
    item.edge:SetShown(selected)
    item.hoverFade:To((item.hovered and not selected) and 1 or 0, T.hover)
    Wg.Color(item.text, (selected or item.hovered) and pal.text or pal.textDim)
    item.icon:SetAlpha((selected or item.hovered) and 1 or 0.82)
end

local function PaintNav()
    local root = K.Root(state.page)
    for _, item in ipairs(state.navItems) do
        PaintItem(item, not state.searching and root ~= nil and item.page.key == root.key)
    end
end

local function ScrollTo(offset)
    local most = math.max(0, (content:GetHeight() or 0) - (scroll:GetHeight() or 0))
    scroll:SetVerticalScroll(math.max(0, math.min(offset, most)))
end

-- Marks a row once: a teal band for a few seconds that then fades (at once where motion is reduced). A newer mark
-- makes an older one's timer stale.
local function Highlight(v)
    state.token = (state.token or 0) + 1
    local token = state.token
    v.highlighted = true
    v.markFade = v.markFade or Motion.Fader(function(a) v.frame.bg:SetAlpha(a) end, 1)
    v.markFade:Set(1)
    v.frame.bg:SetColorTexture(pal.teal[1], pal.teal[2], pal.teal[3], 0.16)
    C_Timer.After(HIGHLIGHT_SECONDS, function()
        if state.token ~= token then return end
        v.highlighted = false
        v.markFade:To(0, T.highlight)
    end)
end

local function ShowResults(on)
    state.searching = on
    resultsView:SetShown(on)
    for key, view in pairs(state.views) do view.frame:SetShown(not on and key == state.page) end
    PaintNav()
end

-- Goes to a page, and to one of its rows: scrolls to it and marks it briefly. Changes nothing.
function UI.Navigate(key, rowId)
    local page = K.pages[key] or K.pages.overview
    if not page then return end
    Wg.CloseMenu()
    local changed = state.page ~= page.key
    if state.searching then
        state.leavingSearch = true   -- the scroll offset is the results', not the page's
        state.clearing = true
        searchBox:SetText("")
        state.clearing = false
        ShowResults(false)
        changed = true
    end
    if changed then
        Wg.ColorPicker.Cancel()   -- a color being picked belongs to the page it was opened on
        if Previews then Previews.StopAll() end   -- and a sample playing, to the page it plays on
    end
    local leavingSearch = state.leavingSearch
    state.leavingSearch = nil
    local arriving = state.page ~= page.key or leavingSearch
    -- (the page's offset was kept when the search began: what is scrolled now is the results)
    if state.page ~= page.key and state.page and not leavingSearch then state.scrollOf[state.page] = scroll:GetVerticalScroll() end
    state.page = page.key
    local view = state.views[page.key] or BuildView(page)
    for k, other in pairs(state.views) do
        other.frame:SetShown(k == page.key)
        -- a page left (or interrupted mid-arrival) goes back to full opacity, so it is never found dim later
        if k ~= page.key and other.fade then other.fade:Set(1) end
    end
    local row = rowId and K.rowsById[rowId]
    if row and row.page ~= page.key then row = nil end
    -- a card's rule asked for by search or a link: its card opens first, so the row can be shown and marked
    if row and row.ruleOf and Cards then Cards.Reveal(view, view.sectionsById[row.ruleOf.id], row) end
    if page.def.onShow then
        local ok, err = pcall(page.def.onShow)
        if not ok then R.Fault("settings page " .. page.key, err) end
    end
    Layout(view)
    PaintNav()
    -- a page returned to is where it was left; a row asked for is scrolled to below
    if arriving and not row then ScrollTo(state.scrollOf[page.key] or 0) end
    -- The new page's content eases in; the page is already there and answering. Not while the window itself
    -- is still opening (one fade, not two), and not for a row on the page already shown.
    if changed and view.fade then
        if Motion.Enabled() and not (state.winFade and state.winFade:Active()) then
            view.fade:Set(0)
            view.fade:To(1, T.page)
        else
            view.fade:Set(1)
        end
    end
    if row then
        local v = view.rows[row.id]
        local y
        if v and v.y then
            y = v.y
            Highlight(v)
        else
            for _, sec in ipairs(view.sections) do
                if sec.id == SectionId(page, row.kind == "header" and row or row.section) and sec.card:IsShown() then
                    local _, _, _, _, top = sec.card:GetPoint(1)
                    y = top and -top or nil
                end
            end
        end
        if y then
            local target = math.max(0, y - 60)
            ScrollTo(target)
            C_Timer.After(0, function() if state.page == page.key then ScrollTo(target) end end)
        end
    end
end

local function BuildNav()
    local list = CreateFrame("ScrollFrame", nil, nav)
    list:SetPoint("TOPLEFT", 6, -8)
    list:SetPoint("BOTTOMRIGHT", -6, 8)
    list:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, list)
    child:SetWidth(NAV_W - 12)
    list:SetScrollChild(child)
    local labels = {}
    for _, group in ipairs(K.GROUPS) do labels[group.key] = group.label end
    local y, lastGroup = 0, nil
    for _, page in ipairs(K.SidebarOrder()) do
        if page.group ~= lastGroup then
            lastGroup = page.group
            if labels[page.group] then
                y = y + 8
                local rule = Wg.Solid(child, "BORDER", pal.bronzeLo, 0.30)   -- a quiet hairline between groups
                rule:SetHeight(1)
                rule:SetPoint("TOPLEFT", 10, -y + 2)
                rule:SetPoint("TOPRIGHT", -10, -y + 2)
                local g = Wg.Text(child, "meta")
                g:SetPoint("TOPLEFT", 10, -y - 6)
                g:SetText(labels[page.group]:upper())
                y = y + NAV_GROUP - 8
            end
        end
        local item = CreateFrame("Button", nil, child)
        item:SetHeight(NAV_ROW)
        item:SetPoint("TOPLEFT", 0, -y)
        item:SetPoint("TOPRIGHT", 0, -y)
        item.page = page
        -- shown: a teal wash fading to the right over the band, a crisp bronze bar at the left and a lit top edge
        item.fill = Wg.Solid(item, "BACKGROUND", pal.band, 1)
        item.fill:SetAllPoints()
        item.wash = item:CreateTexture(nil, "BORDER")
        item.wash:SetAllPoints()
        Wg.Fade(item.wash, pal.teal, 0.30, 0, "HORIZONTAL")
        item.edge = Wg.Solid(item, "ARTWORK", pal.tealHi, 0.14)
        item.edge:SetHeight(1)
        item.edge:SetPoint("TOPLEFT", 0, 0)
        item.edge:SetPoint("TOPRIGHT", 0, 0)
        item.hover = Wg.Solid(item, "BORDER", pal.text, 0.05)
        item.hover:SetAllPoints()
        item.hoverFade = Motion.Fader(function(x) item.hover:SetAlpha(x) end, 0)
        item.bar = Wg.Solid(item, "ARTWORK", pal.bronzeText, 1)
        item.bar:SetWidth(3)
        item.bar:SetPoint("TOPLEFT", 0, -2)
        item.bar:SetPoint("BOTTOMLEFT", 0, 2)
        -- the page's icon beside its name (never instead of it); a page without one keeps its name in line
        item.icon = item:CreateTexture(nil, "ARTWORK")
        item.icon:SetSize(NAV_ICON, NAV_ICON)
        item.icon:SetPoint("LEFT", 10, 0)
        local drawn = Icons and page.def.icon and Icons.Apply(item.icon, page.def.icon, NAV_ICON)
        item.icon:SetShown(drawn and true or false)
        item.text = Wg.Text(item, "body")
        item.text:SetPoint("LEFT", 10 + NAV_ICON + 8, 0)
        item.text:SetPoint("RIGHT", -6, 0)
        item.text:SetWordWrap(false)
        item.text:SetText(page.nav)
        item:SetScript("OnEnter", function(self)
            self.hovered = true
            PaintNav()
        end)
        item:SetScript("OnLeave", function(self)
            self.hovered = false
            PaintNav()
        end)
        item:SetScript("OnClick", function(self) UI.Navigate(self.page.key) end)
        state.navItems[#state.navItems + 1] = item
        y = y + NAV_ROW
    end
    child:SetHeight(y + 4)
    list:SetScript("OnMouseWheel", function(self, delta)
        local most = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(most, self:GetVerticalScroll() - delta * NAV_ROW * 2)))
    end)
end

---------------------------------------------------------------------------
-- Search results
---------------------------------------------------------------------------
local resultRows = {}

local function ResultRow(i)
    local row = resultRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, resultsView)
    row:SetSize(CONTENT_W, 42)
    row.bg = Wg.Solid(row, "BACKGROUND", pal.teal, 0)
    row.bg:SetAllPoints()
    row.bar = Wg.Solid(row, "ARTWORK", pal.bronzeText, 1)
    row.bar:SetWidth(2)
    row.bar:SetPoint("TOPLEFT", 0, -4)
    row.bar:SetPoint("BOTTOMLEFT", 0, 4)
    row.label = Wg.Text(row, "body")
    row.label:SetPoint("TOPLEFT", 12, -6)
    row.label:SetWidth(CONTENT_W - 220)
    row.label:SetWordWrap(false)
    row.context = Wg.Text(row, "meta")
    row.context:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
    row.context:SetWidth(CONTENT_W - 220)
    row.context:SetWordWrap(false)
    -- what the feature does, in its own sentence (a card's, a section's or a page's), when there is one
    row.desc = Wg.Text(row, "small")
    row.desc:SetPoint("TOPLEFT", row.context, "BOTTOMLEFT", 0, -3)
    row.desc:SetWidth(CONTENT_W - 24)
    row.desc:SetWordWrap(false)
    row.note = Wg.Text(row, "meta")
    row.note:SetPoint("TOPRIGHT", -10, -8)
    row.note:SetWidth(196)
    row.note:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetColorTexture(pal.text[1], pal.text[2], pal.text[3], 0.05) end end)
    row:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetColorTexture(pal.text[1], pal.text[2], pal.text[3], 0) end end)
    row:SetScript("OnClick", function(self) UI.Go(self.result) end)
    resultRows[i] = row
    return row
end

local function PaintSelection()
    for i, row in ipairs(resultRows) do
        local selected = row:IsShown() and i == state.selected
        row.selected = selected
        row.bar:SetShown(selected)
        row.bg:SetColorTexture(pal.teal[1], pal.teal[2], pal.teal[3], selected and 0.16 or 0)
    end
end

local function DrawResults(query)
    local results = Search.Run(query)
    state.results, state.selected = results, 1
    local y = 4
    resultsView.title:SetText(#results == 0
        and ("Nothing matches \"" .. query .. "\".")
        or (#results == 1 and "1 result" or (#results .. " results")))
    resultsView.help:SetText(#results == 0
        and "Try fewer or shorter words, or a feature's name, such as \"pins\", \"chronicle\" or \"sound\"."
        or "Enter opens the highlighted one; Up and Down move between them. Choosing one shows it on its page and changes nothing.")
    y = y + (resultsView.title:GetStringHeight() or 16) + 4 + (resultsView.help:GetStringHeight() or 12) + 14
    local alsoShown = false
    resultsView.also:Hide()
    for i, result in ipairs(results) do
        if result.tipOnly and not alsoShown then
            alsoShown = true
            resultsView.also:ClearAllPoints()
            resultsView.also:SetPoint("TOPLEFT", 4, -y - 4)
            resultsView.also:Show()
            y = y + 24
        end
        local row = ResultRow(i)
        local e = result.entry
        row.result = result
        row.label:SetText(e.label)
        row.context:SetText(e.kind == "page" and ("Page" .. Search.SEP .. (e.context or "")) or e.context)
        row.desc:SetText(e.desc or "")
        row.desc:SetShown(e.desc ~= nil)
        row:SetHeight(e.desc and 58 or 42)
        local note = Search.Note(e)
        row.note:SetText(note or "")
        Wg.Color(row.note, note and pal.danger.text or pal.stone)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:Show()
        y = y + row:GetHeight() + 2
    end
    for i = #results + 1, #resultRows do resultRows[i]:Hide() end
    resultsView:SetHeight(y + 8)
    content:SetHeight(y + 8)
    scroll:SetVerticalScroll(0)
    PaintSelection()
end

function UI.Go(result)
    if not result then return end
    local e = result.entry
    searchBox:ClearFocus()
    UI.Navigate(e.page, e.row and e.row.id or nil)
end

function UI.SetQuery(text)
    if state.clearing then return end
    text = (text or ""):gsub("^%s+", "")
    if text == "" then
        if state.searching then
            ShowResults(false)
            local view = state.views[state.page]
            if view then
                Layout(view)
                ScrollTo(state.scrollOf[state.page] or 0)
            end
        end
        return
    end
    if not state.searching then
        if state.page then state.scrollOf[state.page] = scroll:GetVerticalScroll() end
        ShowResults(true)
    end
    DrawResults(text)
end

local function MoveSelection(delta)
    local n = #state.results
    if n == 0 then return end
    state.selected = math.max(1, math.min(n, state.selected + delta))
    PaintSelection()
    local row = resultRows[state.selected]
    local _, _, _, _, top = row:GetPoint(1)
    if top then
        local y, visible = -top, scroll:GetHeight()
        local now = scroll:GetVerticalScroll()
        local h = row:GetHeight() + 2
        if y < now then ScrollTo(y) elseif y + h > now + visible then ScrollTo(y + h - visible) end
    end
end

---------------------------------------------------------------------------
-- Footer: the profile in use, and a reload a change waits for
---------------------------------------------------------------------------
function UI.RefreshFooter()
    if not footer then return end
    local current, shared = ProfileShare()
    if current then
        footer.profile.text:SetText("Profile: |c" .. Wg.Hex(pal.text[1], pal.text[2], pal.text[3]) .. current .. "|r" .. Search.SEP .. shared)
    else
        footer.profile.text:SetText("Profiles aren't available right now.")
    end
    footer.profile:SetWidth(footer.profile.text:GetStringWidth() + 8)
    local pending = R.Switches.ReloadPending()
    footer.reloadText:SetShown(pending)
    footer.reload:SetShown(pending)
    if pending then footer.reloadText:SetText(UI.ReloadSummary()) end
end

-- What a pending reload is for, in words, from Switches.lua (the one record of it, which Troubleshooting reads
-- too): the first named, then a count (the footer is narrow; the Reload now tooltip lists them all). Without a
-- name for one, "another setting".
function UI.PendingNames()
    local W, names = R.Switches, {}
    for _, key in ipairs(W.PendingReloads()) do names[#names + 1] = W.ReloadName(key) or "another setting" end
    return names
end

function UI.ReloadSummary()
    local names = UI.PendingNames()
    if #names == 0 then return "" end
    local text = names[1]
    if #names > 1 then text = text .. (" and %d more"):format(#names - 1) end
    return "Reload your UI to apply: " .. text .. "."
end

function UI.ReloadNotice() UI.RefreshFooter() end

local function BuildFooter()
    footer = CreateFrame("Frame", nil, win)
    footer:SetPoint("BOTTOMLEFT", PAD, 8)
    footer:SetPoint("BOTTOMRIGHT", -PAD, 8)
    footer:SetHeight(FOOTER_H - 12)
    local rule = Wg.Solid(win, "BORDER", pal.bronzeLo, 0.6)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 4)
    rule:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 4)
    footer.profile = CreateFrame("Button", nil, footer)
    footer.profile:SetHeight(20)
    footer.profile:SetPoint("LEFT", 0, 0)
    footer.profile.text = Wg.Text(footer.profile, "small")
    footer.profile.text:SetPoint("LEFT", 4, 0)
    footer.profile:SetScript("OnClick", function() UI.Navigate("profiles") end)
    I.Tip(footer.profile, "Profile", "The saved set of TwichUI options this character uses. Choose another, or make one, on the Profiles page.")
    footer.reload = Wg.Button(footer, "Reload now", 100, "primary", function() ReloadUI() end)
    footer.reload:SetPoint("RIGHT", 0, 0)
    footer.reloadText = Wg.Text(footer, "small")
    footer.reloadText:SetPoint("RIGHT", footer.reload, "LEFT", -10, 0)
    footer.reloadText:SetText("Some changes take effect after you reload your UI.")
    footer.reloadText:SetWordWrap(false)
    Wg.Color(footer.reloadText, pal.bronzeText)
    -- the button reloads only when pressed; the tooltip lists everything that waits
    I.Tip(footer.reload, "Reload now", function()
        local names = UI.PendingNames()
        local list = #names > 0 and ("\n\nWaiting for it: " .. table.concat(names, ", ") .. ".") or ""
        return "Reloads your UI so these changes take effect. TwichUI never reloads for you; turning a change back before you reload clears it." .. list
    end)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function BuildSearch(header)
    searchBox = Wg.EditBox(header, 260, 24)
    searchBox:SetPoint("RIGHT", header, "RIGHT", -40, 0)
    searchBox:SetTextInsets(24, 22, 0, 0)
    searchBox:SetMaxLetters(60)
    local icon = searchBox:CreateTexture(nil, "OVERLAY")
    icon:SetAtlas("common-search-magnifyingglass")   -- the game's own search glass (SearchBoxTemplate's)
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 6, -1)
    icon:SetVertexColor(pal.stone[1], pal.stone[2], pal.stone[3])
    local hint = Wg.Text(searchBox, "meta")
    hint:SetPoint("LEFT", 24, 0)
    hint:SetText("Search settings")
    local clear = CreateFrame("Button", nil, searchBox)
    clear:SetSize(18, 18)
    clear:SetPoint("RIGHT", -3, 0)
    clear.text = Wg.Text(clear, "small")
    clear.text:SetPoint("CENTER", 0, 1)
    clear.text:SetText("x")
    clear:SetScript("OnClick", function() searchBox:SetText(""); searchBox:ClearFocus() end)
    clear:SetScript("OnEnter", function(self) Wg.Color(self.text, pal.tealHi) end)
    clear:SetScript("OnLeave", function(self) Wg.Color(self.text, pal.textDim) end)
    local function Hints()
        local empty = (searchBox:GetText() or "") == ""
        hint:SetShown(empty and not searchBox:HasFocus())
        clear:SetShown(not empty)
    end
    searchBox:SetScript("OnTextChanged", function(self)
        Hints()
        UI.SetQuery(self:GetText())
    end)
    searchBox:HookScript("OnEditFocusGained", Hints)
    searchBox:HookScript("OnEditFocusLost", Hints)
    -- Esc while typing clears the search first; a second Esc lets go of the box.
    searchBox:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then self:SetText("") else self:ClearFocus() end
    end)
    searchBox:SetScript("OnEnterPressed", function()
        if state.searching then UI.Go(state.results[state.selected]) end
    end)
    searchBox:SetScript("OnArrowPressed", function(_, key)
        if not state.searching then return end
        if key == "UP" then MoveSelection(-1) elseif key == "DOWN" then MoveSelection(1) end
    end)
    I.Tip(searchBox, "Search settings", "Finds settings on every page by their name, their page and the words in their description. Enter opens the highlighted result; Esc clears the search.")
    Hints()
end

local function BuildWindow()
    win = CreateFrame("Frame", "TwichUISettingsWindow", UIParent, "BackdropTemplate")
    win:SetSize(WIDTH, HEIGHT)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    if win.SetDontSavePosition then win:SetDontSavePosition(true) end
    win:Hide()
    Wg.Frame(win, WIDTH, HEIGHT, HEADER_H - 4)
    Wg.Header(win, HEADER_H - 4)

    local header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", -4, -4)
    header:SetHeight(HEADER_H - 4)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() win:StartMoving() end)
    header:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        SavePlace()
    end)
    -- the addon's own icon, small, as the sharing and report windows show it
    local crest = header:CreateTexture(nil, "ARTWORK")
    crest:SetSize(24, 24)
    crest:SetPoint("LEFT", 16, 0)
    crest:SetTexture(R.ICON)
    local brand = Wg.Text(header, "brand")
    brand:SetPoint("LEFT", crest, "RIGHT", 8, 0)
    brand:SetText("TwichUI")
    local sub = Wg.Text(header, "meta")
    sub:SetPoint("BOTTOMLEFT", brand, "BOTTOMRIGHT", 10, 2)
    sub:SetText("Settings")
    local close = S.Close(header, function() UI.Close() end, pal)
    close:SetPoint("RIGHT", header, "RIGHT", -10, 0)
    Wg.Raise(close)
    I.Tip(close, "Close", "Closes the settings. Your changes are already saved.")
    BuildSearch(header)

    nav = CreateFrame("Frame", nil, win, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", PAD, -(HEADER_H + 10))
    nav:SetPoint("BOTTOMLEFT", PAD, FOOTER_H + 8)
    nav:SetWidth(NAV_W)
    Wg.Surface(nav, pal.nav, 0.97, pal.bronzeLo, 0.5)
    Wg.Recess(nav, 1.3)   -- the list sits pressed into the window

    local area = CreateFrame("Frame", nil, win)
    area:SetPoint("TOPLEFT", nav, "TOPRIGHT", 12, 0)
    area:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_H + 8)
    scroll, content = Wg.Scroll(area, CONTENT_W)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -24, 0)

    resultsView = CreateFrame("Frame", nil, content)
    resultsView:SetPoint("TOPLEFT", 0, 0)
    resultsView:SetWidth(CONTENT_W)
    resultsView:Hide()
    resultsView.title = Wg.Text(resultsView, "title")
    resultsView.title:SetPoint("TOPLEFT", 2, -4)
    resultsView.help = Wg.Text(resultsView, "small")
    resultsView.help:SetPoint("TOPLEFT", resultsView.title, "BOTTOMLEFT", 0, -4)
    resultsView.help:SetWidth(CONTENT_W - 8)
    resultsView.also = Wg.Text(resultsView, "meta")
    resultsView.also:SetText("ALSO MENTIONED IN")

    BuildNav()
    BuildFooter()

    -- The window fades in as it opens (opacity only: its position, anchors and scale are the game's and the
    -- player's). Opening is not delayed: the content is built and answering from the first frame.
    state.winFade = Motion.Fader(function(a) win:SetAlpha(a) end, 1)
    win:SetScript("OnShow", function(self)
        R.FitToScreen(self)
        UI.RefreshFooter()
        if Motion.Enabled() then
            state.winFade:Set(0)
            state.winFade:To(1, T.window)
        else
            state.winFade:Set(1)
        end
    end)
    win:SetScript("OnHide", function()
        -- Closing is immediate; whatever was easing is put where it was going, so a reopened window is never
        -- found dim, and no hover is left lit for a pointer that has gone.
        Motion.Settle()
        if Previews then Previews.StopAll() end
        for _, item in ipairs(state.navItems) do
            item.hovered = false
            item.hoverFade:Set(0)
        end
        Wg.CloseMenu()
        Wg.ColorPicker.Cancel()
        if searchBox:HasFocus() then searchBox:ClearFocus() end
        if GameTooltip and GameTooltip:IsOwned(win) then GameTooltip:Hide() end
        R.SettingsLauncher.Closed()
    end)
    Place()
end

---------------------------------------------------------------------------
-- What the rest of TwichUI calls (SettingsLauncher.lua)
---------------------------------------------------------------------------
function UI.IsShown() return win ~= nil and win:IsShown() end

-- Where the window is: the page shown (a tab, for a feature with tabs) and the left-hand row it sits under.
function UI.Selected()
    local root = K.Root(state.page)
    return state.page, root and root.key or nil
end
function UI.Frame() return win end
-- A page as drawn (its sections, rows, cards, Home's ways in), or nil before it is first shown. Read only: for
-- tests and diagnostics.
function UI.View(key) return state.views[key] end

-- What has been made so far, for /tui diagnostics: pages described, pages drawn (kept until a reload), and
-- whether search has its index. Read only; it builds nothing.
function UI.Stats()
    local drawn = 0
    for _ in pairs(state.views) do drawn = drawn + 1 end
    return { described = #K.list, drawn = drawn, window = win ~= nil, searchIndex = Search.Built() }
end

-- page: a page key (unknown or nil: the start page, or the page shown last time); setting: a setting's name
-- (TWICHUI_ prefix optional) or a row id, to go to and mark.
function UI.Open(page, setting)
    K.Describe()
    if not win then BuildWindow() end
    if type(setting) == "string" then setting = setting:gsub("^TWICHUI_", "") end
    local row = setting and K.rowsById[setting]
    local key
    if row then key = row.page
    elseif page ~= nil then key = K.pages[page] and page or "overview"   -- an unknown page: the start page
    else key = state.page or "overview" end                              -- none named: where it was left
    win:Show()
    win:Raise()
    UI.Navigate(key, row and row.id or nil)
end

function UI.Close()
    if win and win:IsShown() then win:Hide() end
end

function UI.Toggle(page)
    if UI.IsShown() then UI.Close() else UI.Open(page) end
end

-- The page shown, drawn again (after a change somewhere else).
function UI.Refresh()
    if not UI.IsShown() then return end
    if state.searching then
        DrawResults(searchBox:GetText() or "")
    else
        local view = state.views[state.page]
        if view then Layout(view) end
    end
    UI.RefreshFooter()
end
UI.RefreshValues = UI.Refresh

-- A setting changed through its control (or a Reset told it to show its value again): a slider or a color
-- redraws its own row (they change many times a second while dragged); anything else redraws the page, since
-- other rows may be greyed out or shown because of it.
K.onSettingChanged = function(setting)
    if not UI.IsShown() then return end
    if setting.kind:find("^switch:modules") then return end   -- Switches.lua's listener below redraws
    if state.suspend > 0 then return end
    local view = state.views[state.page]
    if not view or state.searching then return end
    if setting.slider or setting.swatch then
        for _, v in pairs(view.rows) do
            if v.row.data.setting == setting and v.frame:IsShown() then v.RefreshValue() end
        end
        return
    end
    Layout(view)
end
K.onRefresh = UI.Refresh
-- Rows greyed out for combat (profile changes, key bindings) follow it: redrawn as it starts and ends. Nothing
-- runs for this while the window is shut.
local function OnCombatChange() if UI.IsShown() then UI.Refresh() end end
R:On("PLAYER_REGEN_DISABLED", OnCombatChange)
R:On("PLAYER_REGEN_ENABLED", OnCombatChange)
R.Switches.OnChange(function()
    if state.suspend > 0 then return end
    UI.Refresh()
end)

---------------------------------------------------------------------------
-- Esc: the open list, then the window. Through the game's list of frames Esc closes (UISpecialFrames), as an
-- addon's window should: RegisterGameMenuEscHandler is the game's own, and an addon calling it writes into the
-- game's handler table and re-sorts it from insecure code, which taints the Esc path (SpellStopCasting then
-- reports ADDON_ACTION_FORBIDDEN). The one entry is a stand-in answering the two calls the game makes of a
-- frame there, so the list is put away before the window, and a color picker that is open is left to close
-- first (it is in the same list and closes itself; this entry is first, so it is asked while the picker is up).
---------------------------------------------------------------------------
local ESC_NAME = "TwichUISettingsEsc"
local escape = {}
function escape:IsShown()
    if Wg.ColorPicker.Shown() then return false end
    return Wg.MenuShown() or UI.IsShown()
end
function escape:Hide()
    if Wg.MenuShown() then
        Wg.CloseMenu()
    else
        UI.Close()
    end
end
if UISpecialFrames then
    _G[ESC_NAME] = escape
    local listed
    for _, name in ipairs(UISpecialFrames) do
        if name == ESC_NAME then listed = true end
    end
    if not listed then tinsert(UISpecialFrames, 1, ESC_NAME) end   -- before the picker: it is asked while the picker is still up
    UI.escape = "special-frames"
end

-- Last: the rest of TwichUI knows the settings window is here once every file of it has loaded.
R.SettingsUI = UI
