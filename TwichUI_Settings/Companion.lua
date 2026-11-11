-- One settings-only sample workspace. It never pins a live notification, starts navigation, reads journal entries
-- or enables a feature. Feature renderers/style APIs draw private surfaces; only the open page may refresh them.
local R = TwichUI
local W, M = R.SettingsWidgets, R.SettingsMaterial
local C = {}
R.SettingsCompanion = C
local families = { notifications = "notification", notificationsLook = "notification", healerWatch = "healer",
    chronicle = "journal", chronicleLook = "journal", navigation = "navigation", navigationLook = "navigation" }
local scenes, muted = {}, {}
local f, active, current, updating
local WIDTH, PAD = 318, 16

function C.Supports(key) return families[key] ~= nil end
function C.Frame() return f end
function C.Active() return active end
function C.SceneCount() local n = 0; for _ in pairs(scenes) do n = n + 1 end; return n end
function C.Hits() return current and scenes[current] and scenes[current].hits end
function C.PlayHealerParticles(cfg)
    if active ~= "healerWatch" or not scenes.healer then return false, "page" end
    return R.HealerDisplay.PreviewParticles(scenes.healer.surface, cfg)
end

local function Build()
    f = CreateFrame("Frame", "TwichUISettingsSample", UIParent)
    f:SetSize(WIDTH, 490); f.companionHeight = 490
    f:SetFrameStrata("DIALOG"); f:SetToplevel(true); f:SetClampedToScreen(true); f:EnableMouse(true); f:Hide()
    M.Companion(f); M.HeaderBand(f, 64)
    f.connector = M.FrameConnector(f, 44)
    f.title = M.ReminderFont(W.Text(f, "heading"), 21, true)
    f.title:SetPoint("TOPLEFT", PAD, -16); f.title:SetText("Live sample")
    f.sub = W.Text(f, "small"); f.sub:SetPoint("TOPLEFT", PAD, -43); f.sub:SetWidth(WIDTH - PAD * 2)
    f.close = W.Button(f, "×", 24, "secondary", function()
        if current then muted[current] = true end
        C.Hide()
        if R.SettingsUI then R.SettingsUI.Refresh() end
    end)
    f.close:SetPoint("TOPRIGHT", -12, -12)
    f.pick = W.Dropdown(f, WIDTH - PAD * 2, function(value)
        local s = scenes[current]
        if s then s.choice = value end
        if current == "healer" then R.HealerWatcher.SetScenario(value) end
        C.Refresh()
    end)
    f.pick:SetPoint("TOPLEFT", PAD, -78)
    f.canvas = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.canvas:SetPoint("TOPLEFT", PAD, -116); f.canvas:SetSize(WIDTH - PAD * 2, 238)
    M.PanelFace(f.canvas, "canvas"); f.canvas:SetClipsChildren(true)
    f.caption = W.Text(f, "small"); f.caption:SetPoint("TOPLEFT", f.canvas, "BOTTOMLEFT", 2, -12)
    f.caption:SetWidth(WIDTH - PAD * 2 - 4); f.caption:SetWordWrap(true)
    f.jump = W.Button(f, "Adjust appearance", WIDTH - PAD * 2, "secondary", function()
        local key = current == "notification" and "notificationsLook" or current == "journal" and "chronicleLook"
            or current == "navigation" and "navigationLook" or "healerWatch"
        R.SettingsUI.Navigate(key)
        local view = R.SettingsUI.View(key)
        if current == "healer" and view and view.taskButtons then view.taskButtons[3]:Click() end
    end)
    f.jump:SetPoint("BOTTOMLEFT", PAD, 20)
end

function C.Hide()
    if not active then return end
    active = nil
    if f then f:Hide() end
    if scenes.healer and scenes.healer.surface then R.HealerDisplay.StopSurfaceEffects(scenes.healer.surface) end
    if R.RemindersPreview then R.RemindersPreview.RestoreAnchor() end
end
function C.Toggle(view)
    local family = families[view.page.key]
    muted[family] = active and current == family or false
    C.Hide()
    R.SettingsUI.Layout(view)
end

local function Scene(family)
    if scenes[family] then return scenes[family] end
    local s = { frame = CreateFrame("Frame", nil, f.canvas) }
    s.frame:SetAllPoints()
    if family == "healer" then
        s.surface = R.HealerDisplay.NewSurface(s.frame)
        s.surface:SetPoint("CENTER")
    elseif family == "notification" then
        s.card = CreateFrame("Frame", nil, s.frame)
        s.card:SetPoint("CENTER"); s.card:SetSize(264, 180)
        s.title = W.Text(s.card, "heading"); s.title:SetPoint("TOP", 0, -12); s.title:SetWidth(250)
        s.title:SetJustifyH("CENTER"); s.title:SetWordWrap(true)
        s.rule = R.Arrival.Rule(s.card, R.ChronicleStyle.palette)
        s.rule:SetPoint("TOP", s.title, "BOTTOM", 0, -10); s.rule:SetWidth(240)
        s.body = W.Text(s.card, "body"); s.body:SetPoint("TOP", s.rule, "BOTTOM", 0, -12)
        s.body:SetWidth(250); s.body:SetJustifyH("CENTER"); s.body:SetWordWrap(true)
        s.detail = W.Text(s.card, "small"); s.detail:SetPoint("TOP", s.body, "BOTTOM", 0, -8)
        s.detail:SetWidth(250); s.detail:SetJustifyH("CENTER"); s.detail:SetWordWrap(true)
        s.choice = "arrival"
    elseif family == "journal" then
        local A = R.ChronicleAppearance
        s.card = CreateFrame("Frame", nil, s.frame, "BackdropTemplate")
        s.card:SetPoint("TOPLEFT", 10, -14); s.card:SetPoint("BOTTOMRIGHT", -10, 14)
        R.ChronicleStyle.Frame(s.card, 266, 210, A.palette)
        R.ChronicleStyle.Header(s.card, 44, A.palette)
        s.title = A.Text(s.card, "GameFontNormal", "title", A.palette.titleText)
        s.title:SetPoint("TOPLEFT", 14, -18); s.title:SetWidth(230); s.title:SetText("Journey Chronicle")
        s.heading = A.Text(s.card, "GameFontNormal", "heading", A.palette.text)
        s.heading:SetPoint("TOPLEFT", s.title, "BOTTOMLEFT", 0, -24); s.heading:SetWidth(230); s.heading:SetText("Arrived in Sample Vale")
        s.body = A.Text(s.card, "GameFontHighlight", "body", A.palette.textDim)
        s.body:SetPoint("TOPLEFT", s.heading, "BOTTOMLEFT", 0, -12); s.body:SetWidth(230)
        s.body:SetText("A place for the moments you choose to keep.")
        s.meta = A.Text(s.card, "GameFontHighlightSmall", "meta", A.palette.stone)
        s.meta:SetPoint("BOTTOMLEFT", 14, 18); s.meta:SetWidth(230); s.meta:SetText("Example entry · no history read")
    elseif family == "navigation" then
        s.nav = R.NavFrame.New(true, "TwichUISettingsNavigationSample")
        s.nav.f:SetParent(s.frame); s.nav.f:SetFrameStrata("DIALOG")
    end
    s.hits = {}
    local function Hit(name, parent, region, page, row)
        local hit = CreateFrame("Button", nil, parent)
        hit:SetAllPoints(region); hit:SetFrameLevel(parent:GetFrameLevel() + 2)
        M.MaterialHover(hit)
        hit:SetScript("OnClick", function()
            if family == "notification" and active == "notifications" then
                if not R.NotifyLook.SetScope(s.choice) then R.NotifyLook.SetScope("shared") end
            end
            R.SettingsUI.Navigate(page, row)
        end)
        R.Interact.Tip(hit, "Adjust this part", "Opens its setting. Clicking the sample changes no saved value.")
        s.hits[name] = hit
    end
    if family == "notification" then
        Hit("title", s.card, s.title, "notificationsLook", "notifyLookTitleFont")
        Hit("text", s.card, s.body, "notificationsLook", "notifyLookTextFont")
    elseif family == "journal" then
        Hit("title", s.card, s.title, "chronicleLook", "chronicleHeadingFont")
        Hit("text", s.card, s.body, "chronicleLook", "chronicleFont")
    elseif family == "healer" then Hit("panel", s.frame, s.surface, "healerWatch", "healerWatchPreset")
    elseif family == "navigation" then Hit("panel", s.nav.f, s.nav.f, "navigationLook", "navigationFrameScale") end
    scenes[family] = s
    return s
end

local EXAMPLES = {
    arrival = { "Sample Vale", "A made-up place for previews", "New places, at a glance" },
    training = { "New Training Available", "Example ability · Rank 2", "Visit a class trainer" },
    friend = { "A friend comes online", "Example character", "Made-up friend, no roster read" },
    welcome = { "Welcome Back", "Last noted: Sample Vale", "Example bookmark, no history read" },
    partydeath = { "Party member fallen", "Example healer", "Made-up party member" },
}

function C.Refresh()
    if updating then return end
    local UI = R.SettingsUI
    if not (active and f and f:IsShown() and UI and UI.IsPageActive(active)) then return end
    local view = UI.View(active)
    if view then C.Update(view) end
end
function C.Update(view)
    local key, UI = view.page.key, R.SettingsUI
    local family = families[key]
    if not (family and UI and UI.IsPageActive(key)) then return end
    if view.sampleButton then view.sampleButton.text:SetText(muted[family] and "Show sample" or "Hide sample") end
    if muted[family] then C.Hide(); return end
    local pt = R.Perf.on and R.Perf.Start("settings.companion")
    updating = true
    if not f then Build() end
    current, active = family, key
    for _, s in pairs(scenes) do s.frame:Hide() end
    local s = Scene(family); s.frame:Show()
    f.pick:SetShown(family == "notification" or family == "healer")
    f.canvas:ClearAllPoints()
    f.canvas:SetPoint("TOPLEFT", PAD, (family == "notification" or family == "healer") and -116 or -78)
    if family == "healer" then
        local watcher = R.HealerWatcher
        local choices = {}
        for _, entry in ipairs(R.HealerLogic.SCENARIOS) do choices[#choices + 1] = { value = entry[1], label = entry[2] } end
        local label = watcher.Scenario()
        for _, choice in ipairs(choices) do if choice.value == watcher.Scenario() then label = choice.label end end
        f.pick:SetChoices(choices); f.pick:SetValue(watcher.Scenario(), label)
        R.HealerDisplay.DrawSurface(s.surface, watcher.ScenarioView(watcher.Scenario()), watcher.Config(), 264, 216)
        f.sub:SetText("Healer Watch · chosen scenario")
        f.caption:SetText("Made-up readings, drawn with your settings. Silent; no group is read and no feature is enabled.")
    elseif family == "notification" then
        local NL = R.NotifyLook
        if key == "notifications" and s.task ~= view.task then
            s.choice = ({ Arrivals = "arrival", Training = "training", Friends = "friend", Party = "partydeath" })[view.task] or s.choice
            s.task = view.task
        end
        local choices = {}
        for _, info in ipairs(R.Notify.Kinds()) do choices[#choices + 1] = { value = info.kind, label = info.label } end
        local label = s.choice
        for _, choice in ipairs(choices) do if choice.value == s.choice then label = choice.label end end
        f.pick:SetChoices(choices); f.pick:SetValue(s.choice, label)
        local scope = key == "notificationsLook" and NL.Scope() or s.choice
        local example = EXAMPLES[scope] or EXAMPLES[s.choice] or EXAMPLES.arrival
        for i, fs in ipairs({ s.title, s.body, s.detail }) do
            fs:SetText(example[i]); NL.Style(scope, fs, { role = ({ "title", "body", "detail" })[i],
                path = i == 1 and R.Arrival.FONT_TITLE or R.Arrival.FONT_LINE, size = i == 1 and 23 or 15,
                fallback = i == 1 and "ZoneTextFont" or "GameFontHighlight" })
        end
        NL.PaintRule(scope, s.rule, 1)
        NL.Fit(scope, s.card, { top = s.title, bottom = s.detail, width = 250 })
        f.sub:SetText("Notifications · " .. (scope == "shared" and "shared look" or (NL.LABELS[scope] or "sample")))
        f.caption:SetText("Click the text to adjust it. Compact style sample; Try it shows the full card in its real position. Always silent, even while disabled.")
    elseif family == "journal" then
        local A = R.ChronicleAppearance
        A.Sync(); A.Prepare(); A.Surface(s.card)
        R.ChronicleStyle.PaintHeader(s.card, A.palette, 4, 44)
        local recording = R:Enabled("chronicle")
        local title = not recording and "A note of your own" or R:Enabled("chronicleZones") and "Arrived in Sample Vale"
            or R:Enabled("chronicleLevels") and "Reached a new level" or "An example journal entry"
        s.heading:SetText(title)
        f.sub:SetText("Journey Chronicle · example entry")
        f.caption:SetText((recording and "Automatic entries on. " or "Notes only. ") .. "Click the text to adjust its look. Example text; no entries or notes are read or written.")
    else
        s.nav:Style(); s.nav:Update(R.NavFrame.SAMPLE)
        local n = s.nav.f
        n:SetScale(math.min(n:GetScale(), 264 / n:GetWidth(), 214 / n:GetHeight()))
        n:ClearAllPoints(); n:SetPoint("CENTER", s.frame, "CENTER"); s.nav:Show()
        f.sub:SetText("Navigation · sample directions")
        f.caption:SetText("Click the sample to adjust its size. Real frame renderer, fitted here; no route is started or changed. Display keeps the placement and arrow previews.")
    end
    f:Show()
    R.RemindersPreview.Place(f)
    f.connector:SetShown(f.placement ~= "overlay")
    f.connector:ClearAllPoints()
    f.connector:SetPoint(f.placement == "left" and "LEFT" or "RIGHT", f, f.placement == "left" and "RIGHT" or "LEFT", 0, -80)
    if pt then R.Perf.Stop(pt) end
    updating = false
end

if R.OnSettingsClosed then R.OnSettingsClosed(C.Hide) end
for _, model in ipairs({ R.HealerWatch, R.NavPrefs, R.ChronicleAppearance }) do
    if model and model.Subscribe then model.Subscribe(C.Refresh) end
end
