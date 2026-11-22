-- Quality of life only: compact feature rows and one inline detail, using the
-- existing settings row views, bindings, preview hosts and outer page scroll.
local R = TwichUI
local W, M, P, I = R.SettingsWidgets, R.SettingsMaterial, R.SettingsPreviews, R.Interact
local pal = W.pal
local Q = {}
R.SettingsQoL = Q
Q.gap = 8

-- Presentation only. Full qualifications remain in source card help/tooltips.
local FEATURES = {
    qolSummons = { "Offers & invitations", "Arrive at the summoner's location after your chosen wait." },
    qolResurrect = { "Offers & invitations", "Accept ordinary offers; combat offers follow the policy below." },
    qolReleasePvP = { "Offers & invitations", "Battlegrounds only. Hold Shift when the wait ends to keep your body." },
    qolDuels = { "Offers & invitations", "Decline requests outside your exceptions, without chat." },
    qolInvites = { "Offers & invitations", "Join the selected inviter's group at once; leave through its menu." },
    qolDeclineInvites = { "Offers & invitations", "Decline others; your Accept invitations audience takes precedence." },
    qolQuickKeybind = { "Interface", "Add Quick Keybind to the Game Menu, near Macros." },
    qolGroupFinderZones = { "Interface", "Show the leader's zone from the last search; mark your zone." },
    qolHideErrors = { "Messages", "Hide red error text and its sound. Important errors can stay." },
    qolHideErrorSpeech = { "Messages", "Silence spoken errors while keeping their text." },
    qolLootSparkles = { "Sparkles", "Keep quest sparkles. Removal needs a full restart; /reload is not enough." },
    qolHerbSparkles = { "Sparkles", "Highlight the nearby herb selected by interaction targeting." },
    qolOreSparkles = { "Sparkles", "Highlight the nearby ore vein selected by interaction targeting." },
}
local views = setmetatable({}, { __mode = "k" })
local function Text(value)
    if type(value) == "function" then local ok, result = pcall(value); value = ok and result or nil end
    return type(value) == "string" and value ~= "" and value or nil
end
local function Inside(frame, owner)
    while frame do
        if frame == owner then return true end
        frame = frame.GetParent and frame:GetParent()
    end
    return false
end
local function ReturnFocus(sec)
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if not focus then return end
    local hidden = Inside(focus, sec.detail) or Inside(focus, sec.helpButton) or Inside(focus, sec.sampleButton)
        or (sec.preview and Inside(focus, sec.preview.frame)) or Inside(focus, sec.play)
    for _, v in ipairs(sec.rows) do
        if v.row.id ~= "qolResurrectCombat" and Inside(focus, v.frame) then hidden = true end
    end
    if hidden then
        if focus.ClearFocus then focus:ClearFocus() end
        if sec.detailsButton.SetFocus then sec.detailsButton:SetFocus() end
    end
end
local function StopSample(sec)
    if sec.preview then sec.preview:Reset(); sec.preview.frame:Hide() end
    if sec.play then sec.play:Hide(); sec.play.text:SetText("Play sample") end
    sec.sampleOpen = false
end
local function CloseDetail(sec)
    if not sec then return end
    ReturnFocus(sec)
    sec.open, sec.helpOpen = false, false
    StopSample(sec)
end
local function Select(view, sec)
    W.CloseMenu()
    local old = view.qol.open and view.sectionsById[view.qol.open]
    if old ~= sec then CloseDetail(old) end
    view.qol.open = sec and sec.id or nil
    if sec then sec.open = true end
end
local function Change(view, sec, action)
    Q.env.Change(view, sec, action)
end
local function Help(def)
    local parts = { Text(def.what) or "" }
    for _, qa in ipairs(def.details or {}) do
        local answer = Text(qa[2])
        if answer then parts[#parts + 1] = qa[1] .. "\n" .. answer end
    end
    return table.concat(parts, "\n\n")
end

function Q.Build(view, sec, width, env)
    Q.env = env
    views[view] = true
    view.qol = view.qol or { sections = {}, groups = {} }
    local key = sec.header.primary.switch
    local feature = assert(FEATURES[key], "Quality of life feature: " .. tostring(key))
    sec.qolKey, sec.qolGroup, sec.qolPurpose = key, feature[1], feature[2]
    view.qol.sections[key] = sec
    if view.qol.lastGroup ~= feature[1] then
        sec.groupLabel = W.Text(view.frame, "heading")
        sec.groupLabel:SetText(feature[1]); W.Color(sec.groupLabel, pal.bronzeText)
        view.qol.groups[#view.qol.groups + 1] = sec.groupLabel
        view.qol.lastGroup = feature[1]
    end
    sec.isCard, sec.isQoL = true, true
    sec.head = CreateFrame("Button", nil, sec.card)
    sec.head.bg = W.Solid(sec.head, "BACKGROUND", pal.text, 0); sec.head.bg:SetAllPoints()
    sec.title:SetParent(sec.head); M.ReminderFont(sec.title, 16, true)
    sec.desc:SetParent(sec.head); M.ReminderFont(sec.desc, 14)
    sec.icon = sec.head:CreateTexture(nil, "ARTWORK"); sec.icon:SetSize(32, 32)
    sec.icon:SetPoint("TOPLEFT", 0, -2); R.Icons.Apply(sec.icon, sec.header.card.icon, 32)
    sec.note = W.Text(sec.head, "small"); M.ReminderFont(sec.note, 13)
    local function ToggleDetail()
        Change(view, sec, function()
            if view.qol.open == sec.id then CloseDetail(sec); view.qol.open = nil else Select(view, sec) end
        end)
    end
    sec.detailsButton = W.Button(sec.card, "Details", 68, "secondary", ToggleDetail)
    sec.detailsButton:SetHeight(30)
    sec.head:SetScript("OnClick", ToggleDetail)
    I.Tip(sec.head, sec.header:GetName(), function() return sec.header.card.what .. "\n\n" .. (Text(sec.header.card.consequence) or "") end)
    sec.detail = CreateFrame("Frame", nil, sec.card); M.PanelFace(sec.detail, "canvas"); sec.detail:Hide()
    sec.summary = W.Text(sec.detail, "small")
    sec.consequence = W.Text(sec.detail, "body")
    sec.helpText = W.Text(sec.detail, "body"); sec.helpText:SetText(Help(sec.header.card)); sec.helpText:Hide()
    sec.helpButton = W.Button(sec.detail, "More about this", 144, "secondary", function()
        Change(view, sec, function() sec.helpOpen = not sec.helpOpen end)
    end)
    sec.helpButton:SetHeight(30); sec.helpButton:Hide()
    if sec.header.card.preview then
        sec.sampleButton = W.Button(sec.detail, "Show sample", 128, "secondary", function()
            Change(view, sec, function()
                if sec.sampleOpen then StopSample(sec) else
                    if not sec.preview then
                        sec.preview = P.Host(sec.detail, sec.header.card.preview, view.w - 56)
                        if sec.preview and not sec.preview.def.static then
                            sec.play = W.Button(sec.detail, "Play sample", 116, "secondary", function()
                                sec.preview:Play(); sec.play.text:SetText("Play again")
                            end)
                            sec.play:SetHeight(30)
                            I.Tip(sec.play, "Play sample", "Plays a sample using your current rules. It changes nothing and does nothing in the game.")
                        end
                    end
                    sec.sampleOpen = sec.preview ~= nil
                    if sec.preview then sec.preview:Reset() end
                end
            end)
        end)
        sec.sampleButton:SetHeight(30); sec.sampleButton:Hide()
    end
    sec.selected = W.Solid(sec.card, "BORDER", pal.bronzeText, .7)
    sec.selected:SetWidth(2); sec.selected:SetPoint("TOPLEFT", 1, -1); sec.selected:SetPoint("BOTTOMLEFT", 1, 1); sec.selected:Hide()
    sec.card:HookScript("OnHide", function() StopSample(sec) end)
    Q.Resize(sec, width, env)
end

function Q.Primary(sec, row, env)
    local v = R.SettingsCards.Primary(sec, row, env)
    -- Keep the stock switch/On-Off hit region clear of the separate disclosure.
    sec.saved:ClearAllPoints(); sec.saved:SetPoint("TOPRIGHT", sec.head, "TOPRIGHT", -4, -31)
    return v
end
function Q.Resize(sec, width)
    local disclosureWidth = math.max(68, sec.detailsButton.text:GetStringWidth() + 24)
    sec.detailsButton:SetWidth(disclosureWidth)
    local headWidth = width - 28 - disclosureWidth - 14
    sec.head:SetWidth(headWidth)
    local toggleWidth = math.max(100, (sec.state and sec.state:GetStringWidth() or 0) +
        (sec.primaryView and sec.primaryView.control:GetWidth() or 42) + 24)
    local textWidth = math.max(80, headWidth - 44 - toggleWidth)
    sec.title:SetWidth(textWidth); sec.desc:SetWidth(textWidth); sec.note:SetWidth(headWidth - 44)
    sec.summary:SetWidth(width - 56); sec.consequence:SetWidth(width - 56); sec.helpText:SetWidth(width - 56)
    if sec.groupLabel then sec.groupLabel:SetWidth(width - 8) end
    if sec.preview then
        local previewWidth = width - 56
        sec.preview.width = previewWidth
        sec.preview.frame:SetWidth(previewWidth); sec.preview.stage:SetWidth(previewWidth)
        sec.preview.caption:SetWidth(previewWidth - 4)
    end
end
function Q.BeforeSection(view, sec, y)
    if sec.groupLabel then
        sec.groupLabel:ClearAllPoints(); sec.groupLabel:SetPoint("TOPLEFT", view.frame, "TOPLEFT", 2, -y)
        y = y + sec.groupLabel:GetStringHeight() + 12
    end
    return y
end
local function PutText(fs, sec, y, value)
    fs:SetText(value or ""); fs:SetShown(value ~= nil)
    if not value then return y end
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", sec.card, "TOPLEFT", 28, -y)
    return y + fs:GetStringHeight() + 10
end
-- Reflow only these existing row views when a label/value outgrows the normal
-- column. Ordinary settings pages and their shared row renderer are untouched.
local function PlaceRows(sec, rows, inner, env)
    local width = sec.card:GetWidth() - 20
    for _, v in ipairs(rows) do
        v.Resize(width)
        if v.row.kind == "dropdown" then
            v.qolControlWidth = v.qolControlWidth or v.control:GetWidth()
            v.qolControlHeight = v.qolControlHeight or v.control:GetHeight()
            v.control:SetSize(v.qolControlWidth, v.qolControlHeight)
            v.control.text:SetWordWrap(false)
            v.control.text:SetWidth(v.qolControlWidth - 36)
        end
    end
    env.PlaceRows(sec, rows, inner)
    for _, v in ipairs(rows) do
        if v.y then
            local dropdown = v.row.kind == "dropdown"
            local valueWidth = dropdown and v.control.text:GetStringWidth() or 0
            local stacked = v.label:GetStringWidth() > v.label:GetWidth()
                or (dropdown and valueWidth + 36 > v.control:GetWidth())
            if stacked then
                local left = v.row.parent and 24 or 6
                local available = width - left - 12
                v.label:SetWidth(available); v.reason:SetWidth(available)
                local controlTop = v.label:GetStringHeight() + 12
                if v.reason:IsShown() and v.reason:GetText() ~= "" then controlTop = controlTop + v.reason:GetStringHeight() + 3 end
                if dropdown then
                    v.control:SetWidth(math.max(236, math.min(available, valueWidth + 36)))
                    v.control.text:SetWidth(v.control:GetWidth() - 36); v.control.text:SetWordWrap(true)
                    v.control:SetHeight(math.max(28, v.control.text:GetStringHeight() + 12))
                end
                v.control:ClearAllPoints(); v.control:SetPoint("TOPLEFT", v.frame, "TOPLEFT", left, -controlTop)
                v.frame:SetHeight(controlTop + v.control:GetHeight() + 8)
            end
            v.stacked = stacked
            v.frame:ClearAllPoints(); v.frame:SetPoint("TOPLEFT", sec.card, "TOPLEFT", 10, -inner)
            v.y = sec.top + inner
            inner = inner + v.frame:GetHeight()
        end
    end
    return inner
end

function Q.Layout(view, sec, inner, env)
    local def = sec.header.card
    local opened = view.qol.open == sec.id
    sec.open = opened
    sec.selected:SetShown(opened)
    sec.head:ClearAllPoints(); sec.head:SetPoint("TOPLEFT", sec.card, "TOPLEFT", 14, -inner)
    sec.title:SetText(sec.header:GetName()); sec.title:ClearAllPoints(); sec.title:SetPoint("TOPLEFT", sec.head, "TOPLEFT", 44, 0)
    sec.desc:SetText(sec.qolPurpose); sec.desc:ClearAllPoints(); sec.desc:SetPoint("TOPLEFT", sec.title, "BOTTOMLEFT", 0, -3)
    sec.primaryView.Refresh()
    Q.Resize(sec, view.w)
    local h = math.max(44, 31 + sec.saved:GetStringHeight(), sec.title:GetStringHeight() + 3 + sec.desc:GetStringHeight())
    local note, tone = env.Note(sec.header.primary)
    if R.QoL.LEATRIX[sec.qolKey] and R.QoL.LeatrixOverlap(sec.qolKey) then note = "Also on in Leatrix Plus" end
    if sec.qolKey == "qolHideErrorSpeech" and R:Enabled("qolHideErrors") then note = "Error hiding already removes the voice with its messages." end
    sec.note:SetShown(note ~= nil)
    if note then
        sec.note:SetText(note); W.Color(sec.note, env.TONE[tone] or pal.textDim)
        sec.note:ClearAllPoints(); sec.note:SetPoint("TOPLEFT", sec.head, "TOPLEFT", 44, -(h + 4))
        h = h + 4 + sec.note:GetStringHeight()
    end
    sec.head:SetHeight(h); sec.primaryView.y = sec.top + inner
    sec.detailsButton:ClearAllPoints(); sec.detailsButton:SetPoint("TOPRIGHT", sec.card, "TOPRIGHT", -14, -inner)
    sec.detailsButton.text:SetText(opened and "Less" or "Details")
    inner = inner + h + 4
    -- This existing child control never disappears behind the detail disclosure.
    for _, v in ipairs(sec.rows) do
        if v.row.id == "qolResurrectCombat" then
            inner = PlaceRows(sec, {v}, inner, env)
            sec.combatWarning = sec.combatWarning or W.Text(sec.card, "small")
            sec.combatWarning:SetWidth(view.w - 56)
            inner = PutText(sec.combatWarning, sec, inner, "In combat: " .. (R:Enabled("qolResurrectCombat") and "accepted too" or "waits for you") .. ". Combat resurrection can return you to a fight with low health.")
        end
    end
    sec.overviewHeight = inner
    sec.detail:SetShown(opened); sec.helpButton:SetShown(opened)
    if sec.sampleButton then sec.sampleButton:SetShown(opened) end
    if not opened then
        sec.summary:Hide(); sec.consequence:Hide(); sec.helpText:Hide()
        StopSample(sec)
        for _, v in ipairs(sec.rows) do if v.row.id ~= "qolResurrectCombat" then v.frame:Hide(); v.y = nil end end
        return inner
    end
    local top = inner
    inner = PutText(sec.consequence, sec, inner + 14, Text(def.consequence))
    inner = PutText(sec.summary, sec, inner, Text(def.summary))
    local children = {}
    for _, v in ipairs(sec.rows) do if v.row.id ~= "qolResurrectCombat" then children[#children + 1] = v end end
    inner = PlaceRows(sec, children, inner, env)
    inner = inner + 10
    sec.helpButton:ClearAllPoints(); sec.helpButton:SetPoint("TOPLEFT", sec.card, "TOPLEFT", 28, -inner)
    sec.helpButton.text:SetText(sec.helpOpen and "Less about this" or "More about this")
    sec.helpButton:SetWidth(math.max(144, sec.helpButton.text:GetStringWidth() + 28))
    local actionHeight = 30
    if sec.sampleButton then
        sec.sampleButton.text:SetText(sec.sampleOpen and "Hide sample" or "Show sample")
        sec.sampleButton:SetWidth(math.max(128, sec.sampleButton.text:GetStringWidth() + 28))
        sec.sampleButton:ClearAllPoints()
        if sec.helpButton:GetWidth() + 12 + sec.sampleButton:GetWidth() > view.w - 56 then
            sec.sampleButton:SetPoint("TOPLEFT", sec.helpButton, "BOTTOMLEFT", 0, -8)
            actionHeight = actionHeight + 38
        else sec.sampleButton:SetPoint("TOPLEFT", sec.helpButton, "TOPRIGHT", 12, 0) end
    end
    inner = inner + actionHeight + 10
    sec.helpText:SetShown(sec.helpOpen == true)
    if sec.helpOpen then inner = PutText(sec.helpText, sec, inner, Help(def)) end
    if sec.preview then
        sec.preview.frame:SetShown(sec.sampleOpen == true)
        if sec.sampleOpen then
            sec.preview.frame:ClearAllPoints(); sec.preview.frame:SetPoint("TOPLEFT", sec.card, "TOPLEFT", 28, -inner)
            inner = inner + P.HostHeight(sec.preview) + 10
            if sec.play then
                sec.play:ClearAllPoints(); sec.play:SetPoint("TOPLEFT", sec.card, "TOPLEFT", 28, -inner); sec.play:Show()
                inner = inner + 40
            end
        elseif sec.play then sec.play:Hide() end
    end
    sec.detail:ClearAllPoints(); sec.detail:SetPoint("TOPLEFT", sec.card, "TOPLEFT", 14, -top)
    sec.detail:SetSize(view.w - 28, inner - top + 4)
    return inner + 4
end
function Q.Reveal(view, _, row)
    if row.id == "qolResurrectCombat" then return false end
    local target = view.rows[row.id]
    local sec = target and target.section or view.sectionsById[row.id]
    if not sec then return false end
    Select(view, sec)
    return true
end
function Q.PageReset(view)
    W.CloseMenu()
    for _, sec in ipairs(view.sections) do StopSample(sec) end
end
function Q.Hide(view)
    for _, sec in ipairs(view.sections) do ReturnFocus(sec); StopSample(sec) end
end
local function ProfileChanged()
    for view in pairs(views) do
        Q.Hide(view)
        for _, sec in ipairs(view.sections) do CloseDetail(sec) end
        view.qol.open = nil
    end
    if R.SettingsUI then R.SettingsUI.Refresh() end
end
if R.Profiles then
    R.Profiles.OnApply("views", "qol-settings-details", ProfileChanged)
    R.Profiles.OnChange(function(kind) if kind == "duplicate" then ProfileChanged() end end)
end
