-- TwichUI: Configuration Sharing window (/pack)
-- Two pages: "My configuration" (choose, save, send) and "Shared with me" (receive,
-- apply, undo). Styled by EllesmereUI's skin toolkit when it's available.

local R = TwichUI
local ST, SH = R.Setups, R.Share
local W = {}
R.Window = W

local GOLD, GREY, RED, GREEN = R.GOLD, R.GREY, R.RED, R.GREEN
local WIDTH, HEIGHT = 720, 580
local ROW_H = 24
local f                         -- main frame
local page = "mine"
local expanded = {}             -- [owner] = true on the My setup page
local getSel = {}               -- [sourceKey] = { [owner] = bool }
local sourceIndex = 1
local fontStrings = {}
local toast                      -- transfer toast (built on first use)

---------------------------------------------------------------------------
-- Skin helpers: use EllesmereUI's primitives when present, else plain.
---------------------------------------------------------------------------
local function Skin(kind, obj, ...)
    local S = R.S
    if not (S and S[kind] and obj) then return end
    pcall(S[kind], obj, ...)
end

local function Accent()
    local S = R.S
    if S and S.GetAccentColor then
        local ok, r, g, b = pcall(S.GetAccentColor)
        if ok and r then return r, g, b end
    end
    return 0.79, 0.64, 0.29
end

local function Text(parent, template, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fontStrings[#fontStrings + 1] = fs
    return fs
end

local function Btn(parent, label, w, onClick, tooltip)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    if tooltip then
        b:SetMotionScriptsWhileDisabled(true)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(type(tooltip) == "function" and tooltip() or tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
    end
    Skin("Button", b)
    Skin("StateButtonLabel", b)
    return b
end

local function Check(parent, label)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(22, 22)
    if label then
        c.label = Text(parent, "GameFontHighlightSmall")
        c.label:SetPoint("LEFT", c, "RIGHT", 4, 0)
        c.label:SetText(label)
    end
    Skin("Checkbox", c)
    return c
end

local function Section(parent, num, title, y)
    local n = Text(parent, "GameFontNormalLarge")
    n:SetPoint("TOPLEFT", 16, y)
    n:SetText(num)
    n:SetTextColor(Accent())
    local t = Text(parent, "GameFontNormal")
    t:SetPoint("LEFT", n, "RIGHT", 8, 0)
    t:SetText(title)
    t:SetTextColor(1, 1, 1)
    n.isAccent = true
    return n, t
end

local function ProgressBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent, "BackdropTemplate")
    bar:SetSize(WIDTH - 32, 8)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetStatusBarColor(Accent())
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(1, 1, 1, 0.08)
    Skin("ApplyBarFill", bar)
    return bar
end

local function ListBox(parent, height)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(WIDTH - 32, height)
    if R.S then
        Skin("Panel", box, { inset = true })
    else
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        box:SetBackdropColor(0, 0, 0, 0.35)
        box:SetBackdropBorderColor(1, 1, 1, 0.08)
    end
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    Skin("ScrollBar", scroll.ScrollBar)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 70, 1)
    scroll:SetScrollChild(content)
    box.content, box.rows, box.scroll = content, {}, scroll
    local empty = Text(box, "GameFontDisableSmall")
    empty:SetPoint("CENTER")
    empty:SetWidth(WIDTH - 100)
    empty:SetJustifyH("CENTER")
    box.empty = empty
    return box
end

local function ListRow(box, i)
    local r = box.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, box.content)
    r:SetSize(WIDTH - 70, ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.05)
    r.check = Check(r)
    r.check:SetPoint("LEFT", 2, 0)
    r.arrow = Text(r, "GameFontHighlightSmall")
    r.arrow:SetPoint("LEFT", r.check, "RIGHT", 2, 0)
    r.arrow:SetWidth(12)
    r.label = Text(r, "GameFontHighlight")
    r.label:SetPoint("LEFT", r.arrow, "RIGHT", 2, 0)
    r.label:SetWidth(360)
    r.label:SetWordWrap(false)
    r.right = Text(r, "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -8, 0)
    r.right:SetJustifyH("RIGHT")
    r:SetScript("OnLeave", GameTooltip_Hide)
    box.rows[i] = r
    return r
end

local function FinishList(box, count, emptyText)
    for i = count + 1, #box.rows do box.rows[i]:Hide() end
    box.content:SetHeight(math.max(1, count * ROW_H))
    box.empty:SetText(count == 0 and emptyText or "")
end

local function Confirm(key, text, onAccept)
    StaticPopupDialogs[key] = {
        text = text, button1 = ACCEPT, button2 = CANCEL, OnAccept = onAccept,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show(key)
end

local function NoCombat()
    if InCombatLockdown() then R.Print("that has to wait until you're out of combat.") return false end
    return true
end

local function When(t) return t and date("%b %d, %H:%M", t) or "?" end

---------------------------------------------------------------------------
-- Page: My setup
---------------------------------------------------------------------------
local mine = {}

local function BuildMine(p)
    Section(p, "1", "Choose what to share", -4)
    mine.help = Text(p, "GameFontHighlightSmall")
    mine.help:SetPoint("TOPLEFT", 16, -28)
    mine.help:SetWidth(WIDTH - 190)
    mine.find = Btn(p, "Find my addon settings", 160, function()
        if not NoCombat() then return end
        Confirm("TWICHUI_FIND", "Look through your addons for their settings? Your UI reloads once.", function() ST:FindSettings() end)
    end, "Reloads your UI once and lists every addon that has saved settings. Settings are picked up exactly as they're saved right now.")
    mine.find:SetPoint("TOPRIGHT", -16, -22)

    mine.list = ListBox(p, 190)
    mine.list:SetPoint("TOPLEFT", 16, -58)
    mine.summary = Text(p, "GameFontDisableSmall")
    mine.summary:SetPoint("TOPLEFT", mine.list, "BOTTOMLEFT", 2, -4)
    mine.suggest = Btn(p, "Recommended", 100, function() ST:SelectSuggested(); W:Refresh() end,
        "Tick the settings most people want to share, and skip big data like price history, caches and logs.")
    mine.suggest:SetPoint("TOPRIGHT", mine.list, "BOTTOMRIGHT", 0, -2)

    Section(p, "2", "Save", -290)
    mine.em = Check(p, "Include my Edit Mode layout")
    mine.em:SetPoint("TOPLEFT", 14, -314)
    mine.em:SetChecked(true)
    mine.save = Btn(p, "Save my configuration", 170, function()
        ST:SaveMine(mine.em:GetChecked())
        R.Print("saved your addon configuration: %d addons.", ST.CountAddons(ST.Mine()))
        W:Refresh()
    end, function()
        return ST:CanSave() and "Saves the ticked settings as your addon configuration. You can send it straight away."
            or "Click \"Find my addon settings\" first. Saving uses the settings found in that session."
    end)
    mine.save:SetPoint("TOPRIGHT", -16, -312)
    mine.saved = Text(p, "GameFontHighlightSmall")
    mine.saved:SetPoint("TOPLEFT", 16, -342)
    mine.saved:SetWidth(WIDTH - 120)
    mine.delete = Btn(p, "Delete", 70, function()
        Confirm("TWICHUI_DELETE_MINE", "Delete your saved configuration?\n\nFriends keep the copy they already have. You can save a new one any time.", function()
            ST:DeleteMine(); W:Refresh()
        end)
    end)
    mine.delete:SetPoint("TOPRIGHT", -16, -337)

    Section(p, "3", "Send to a friend", -372)
    mine.selfTest = Btn(p, "Test on myself", 120, function()
        local ok, why = SH:SendToSelf()
        if not ok then R.Print(why) end
        W:Refresh()
    end, "Sends your configuration to your own character through the real in-game channel: you get the accept prompt, the progress bars and the received copy under Shared with me, exactly like a friend would.")
    mine.selfTest:SetPoint("TOPRIGHT", -16, -368)
    mine.channels = Btn(p, "Sending options", 130, function() W:ShowChannels() end,
        "Choose how configurations travel: direct messages, your group, or your guild. Explains why Forever needs the group or guild for now.")
    mine.channels:SetPoint("RIGHT", mine.selfTest, "LEFT", -8, 0)
    mine.name = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    mine.name:SetSize(230, 24)
    mine.name:SetPoint("TOPLEFT", 22, -398)
    mine.name:SetAutoFocus(false)
    mine.name:SetScript("OnEnterPressed", function() mine.send:Click() end)
    mine.name:SetScript("OnEscapePressed", mine.name.ClearFocus)
    mine.name:SetScript("OnTextChanged", function() W:Refresh() end)
    Skin("EditBox", mine.name)
    mine.hint = Text(mine.name, "GameFontDisableSmall")
    mine.hint:SetPoint("LEFT", 6, 0)
    mine.hint:SetText(SH.NameHint())
    mine.target = Btn(p, "Use my target", 110, function()
        if UnitIsPlayer("target") then
            mine.name:SetText(GetUnitName("target", true) or "")
        else
            R.Print("target your friend first.")
        end
    end)
    mine.target:SetPoint("LEFT", mine.name, "RIGHT", 8, 0)
    mine.send = Btn(p, "Send", 90, function()
        local ok, why = SH:SendTo(mine.name:GetText())
        if not ok then R.Print(why) end
        mine.name:ClearFocus()
        W:Refresh()
    end, "They get a prompt to accept. After the first time, only the addons you changed are sent again.")
    mine.send:SetPoint("LEFT", mine.target, "RIGHT", 8, 0)
    mine.cancel = Btn(p, "Stop", 70, function() SH:CancelSend() end)
    mine.cancel:SetPoint("LEFT", mine.send, "RIGHT", 8, 0)

    mine.bar = ProgressBar(p)
    mine.bar:SetPoint("TOPLEFT", 16, -434)
    mine.status = Text(p, "GameFontHighlightSmall")
    mine.status:SetPoint("TOPLEFT", mine.bar, "BOTTOMLEFT", 0, -6)
    mine.status:SetWidth(WIDTH - 32)

    mine.fileTip = Text(p, "GameFontDisableSmall")
    mine.fileTip:SetPoint("BOTTOMLEFT", 16, 8)
    mine.fileTip:SetWidth(WIDTH - 32)
    mine.fileTip:SetText("Friend on another realm? Save, log out, and run tools\\make_pack.bat in the TwichUI folder to make a file instead.")
end

local function RefreshMine()
    local groups = ST:DetectedByAddon()
    local lines = 0
    local totalBytes, totalAddons = 0, 0
    for _, g in ipairs(groups) do
        lines = lines + 1
        local r = ListRow(mine.list, lines)
        r.check:Show()
        r.check:SetChecked(g.selected > 0)
        r.check:SetEnabled(ST.capture ~= nil)
        r.check:SetScript("OnClick", function(c) ST:SetAddonSelected(g.owner, c:GetChecked()); W:Refresh() end)
        r.arrow:SetText(expanded[g.owner] and "-" or "+")
        r.label:SetText(g.title)
        r.label:SetTextColor(1, 1, 1)
        local sizeText = g.selected > 0 and ST.FormatSize(g.bytes) or ""
        r.right:SetText(GREY .. sizeText .. "|r")
        r:SetScript("OnClick", function() expanded[g.owner] = not expanded[g.owner]; W:Refresh() end)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(g.title, 1, 1, 1)
            GameTooltip:AddLine("Click the name to see each part.", 0.7, 0.7, 0.7)
            for _, t in ipairs(g.tables) do
                GameTooltip:AddDoubleLine((t.selected and "|cff8FB35A+|r " or "|cff8a857c-|r ") .. t.name,
                    ST.FormatSize(t.bytes), 1, 1, 1, 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end)
        r:Show()
        if g.selected > 0 then totalAddons = totalAddons + 1; totalBytes = totalBytes + g.bytes end

        if expanded[g.owner] then
            for _, t in ipairs(g.tables) do
                lines = lines + 1
                local c = ListRow(mine.list, lines)
                c.check:Show()
                c.check:SetChecked(t.selected)
                c.check:SetEnabled(ST.capture ~= nil and not t.huge)   -- too big to share
                c.check:SetScript("OnClick", function(cb) ST:SetTableSelected(t.name, cb:GetChecked()); W:Refresh() end)
                c.arrow:SetText("")
                c.label:SetText("    " .. t.name)
                c.label:SetTextColor(0.75, 0.75, 0.75)
                c.right:SetText((t.huge and RED or GREY) .. ST.FormatSize(t.bytes) .. "|r")
                c:SetScript("OnClick", nil)
                c:SetScript("OnEnter", nil)
                c:Show()
            end
        end
    end
    FinishList(mine.list, lines, "Nothing found yet. Click \"Find my addon settings\" to start.")

    if ST.capture then
        mine.help:SetText("Tick the addons you want to share. Big data like price history and caches is left out unless you tick it.")
    elseif #groups > 0 then
        mine.help:SetText(GREY .. "This is your last search. Search again before saving so the newest settings are used.|r")
    else
        mine.help:SetText("Start by finding the addons that have settings.")
    end
    mine.summary:SetText(("%d addons ticked, about %s"):format(totalAddons, ST.FormatSize(totalBytes)))
    mine.save:SetEnabled(ST.capture ~= nil and totalAddons > 0)

    local m = ST.Mine()
    if m then
        mine.saved:SetText(("%sSaved|r %s  ·  version %d  ·  %d addons%s"):format(GREEN, When(m.created), m.version or 1,
            ST.CountAddons(m), m.editMode and "  ·  Edit Mode layout" or ""))
    else
        mine.saved:SetText(GREY .. "Not saved yet.|r")
    end
    mine.delete:SetShown(m ~= nil)

    mine.hint:SetShown(mine.name:GetText() == "" and not mine.name:HasFocus())
    local o = SH.outgoing
    local busy = o and (o.stage == "offered" or o.stage == "packing" or o.stage == "sending" or o.stage == "delivered")
    mine.send:SetEnabled(m ~= nil and not busy and mine.name:GetText() ~= "")
    mine.selfTest:SetEnabled(m ~= nil and not busy)
    mine.cancel:SetShown(busy and true or false)
    mine.bar:SetShown(o ~= nil)
    if not o then
        local tip
        if SH.Realmless() and not R:Enabled("shareGroup") and not R:Enabled("shareGuild") then
            tip = GOLD .. "Forever can't deliver direct addon messages yet. Open Sending options to allow your group channel.|r"
        elseif SH.Realmless() then
            tip = "Group up with your friend" .. (R:Enabled("shareGuild") and " (or be in the same guild)" or "") .. ", type their full name, and press Send."
        else
            tip = "Type a name and press Send. You both need to be online."
        end
        mine.status:SetText(m and GREY .. tip .. "|r" or "")
    else
        local who = SH.Short(o.target)
        if o.stage == "offered" then
            mine.bar:SetValue(0)
            mine.status:SetText(("Waiting for %s to accept..."):format(who))
        elseif o.stage == "packing" then
            mine.bar:SetValue(0)
            mine.status:SetText(("%s accepted. Packing your configuration..."):format(who))
        elseif o.stage == "sending" or o.stage == "delivered" then
            local frac = (o.total or 0) > 0 and (o.sent or 0) / o.total or 0
            mine.bar:SetValue(frac)
            if (o.parts or 0) == 0 then
                mine.status:SetText(("%s already has everything. Updating their list..."):format(who))
            else
                mine.status:SetText(("Sending to %s: %d%%  (%s of %s, %d addons changed)"):format(who, frac * 100,
                    ST.FormatSize(o.sent or 0), ST.FormatSize(o.total or 0), o.parts or 0))
            end
        elseif o.stage == "done" then
            mine.bar:SetValue(1)
            mine.status:SetText(("%sDone.|r %s has your addon configuration."):format(GREEN, who))
        elseif o.stage == "failed" then
            mine.bar:SetValue(0)
            mine.status:SetText(RED .. (o.reason or "That didn't work.") .. "|r")
        end
    end
end

---------------------------------------------------------------------------
-- Page: My addon list
---------------------------------------------------------------------------
local al = {}

local function BuildAddons(p)
    al.help = Text(p, "GameFontHighlightSmall")
    al.help:SetPoint("TOPLEFT", 16, -4)
    al.help:SetWidth(WIDTH - 32)
    al.help:SetText("Tick the addons you recommend. Friends get this list with your configuration, with a download link for each one they're missing. Addons you've turned off start unticked.")
    al.list = ListBox(p, 318)
    al.list:SetPoint("TOPLEFT", 16, -40)
    al.summary = Text(p, "GameFontDisableSmall")
    al.summary:SetPoint("TOPLEFT", al.list, "BOTTOMLEFT", 2, -4)
    al.all = Btn(p, "All", 60, function()
        for _, g in ipairs(ST.InstalledAddons()) do ST:SetRecommended(g.key, true) end
        W:Refresh()
    end)
    al.none = Btn(p, "None", 60, function()
        for _, g in ipairs(ST.InstalledAddons()) do ST:SetRecommended(g.key, false) end
        W:Refresh()
    end)
    al.none:SetPoint("TOPRIGHT", al.list, "BOTTOMRIGHT", 0, -2)
    al.all:SetPoint("RIGHT", al.none, "LEFT", -6, 0)

    al.update = Btn(p, "Update my saved configuration", 220, function()
        if ST:UpdateSavedAddonList() then
            R.Print("addon list updated in your saved configuration. Send it again to share the change.")
        end
        W:Refresh()
    end, function()
        return ST.Mine() and "Puts this list into your saved configuration without touching the settings. Saving on the My configuration page also includes it."
            or "Save your configuration first on the My configuration page; the list is included when you do."
    end)
    al.update:SetPoint("TOPLEFT", 16, -396)
    al.status = Text(p, "GameFontHighlightSmall")
    al.status:SetPoint("LEFT", al.update, "RIGHT", 12, 0)
    al.status:SetWidth(WIDTH - 270)
    al.legend = Text(p, "GameFontDisableSmall")
    al.legend:SetPoint("BOTTOMLEFT", 16, 8)
    al.legend:SetWidth(WIDTH - 32)
    al.legend:SetText("Where it comes from: CurseForge, Wago or WoWInterface when the addon says so; otherwise friends get a CurseForge search link.")
end

local function RefreshAddons()
    local groups = ST.InstalledAddons()
    local ticked = 0
    for i, g in ipairs(groups) do
        local r = ListRow(al.list, i)
        local on = ST:IsRecommended(g)
        if on then ticked = ticked + 1 end
        r.check:Show()
        r.check:SetEnabled(true)
        r.check:SetChecked(on)
        r.check:SetScript("OnClick", function(c) ST:SetRecommended(g.key, c:GetChecked()); W:Refresh() end)
        r.arrow:SetText("")
        r.label:SetText(g.title)
        local c = g.enabled and 1 or 0.55
        r.label:SetTextColor(c, c, c)
        local _, where = ST.AddonLink(g)
        r.right:SetText(GREY .. (g.version and (g.version .. "  ·  ") or "") .. where .. "|r")
        r:SetScript("OnClick", nil)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(g.title, 1, 1, 1)
            local url = ST.AddonLink(g)
            GameTooltip:AddLine(url, 0.6, 0.6, 0.6, true)
            if #g.folders > 1 then GameTooltip:AddLine("Includes: " .. table.concat(g.folders, ", "), 0.7, 0.7, 0.7, true) end
            if not g.enabled then GameTooltip:AddLine("Turned off on this character.", 0.8, 0.64, 0.29) end
            GameTooltip:Show()
        end)
        r:Show()
    end
    FinishList(al.list, #groups, "No addons found.")
    al.summary:SetText(("%d of %d addons recommended"):format(ticked, #groups))

    local mine = ST.Mine()
    al.update:SetEnabled(mine ~= nil)
    if not mine then
        al.status:SetText(GREY .. "Not saved yet. Save on the My configuration page.|r")
    else
        local n = 0
        for _ in pairs(mine.addons or {}) do n = n + 1 end
        al.status:SetText(("%sIn your saved configuration:|r %d addons (version %d)"):format(GREY, n, mine.version or 1))
    end
end

---------------------------------------------------------------------------
-- Popup: addons a shared configuration recommends
---------------------------------------------------------------------------
local ap
local STATE_LABEL = { missing = RED .. "Not installed|r", off = GOLD .. "Turned off|r", installed = GREEN .. "Installed|r" }

local function BuildAddonPopup()
    ap = CreateFrame("Frame", "TwichUIAddonList", UIParent, "BackdropTemplate")
    ap:SetSize(560, 500)
    ap:SetPoint("CENTER", 40, -20)
    ap:SetFrameStrata("DIALOG")
    ap:SetToplevel(true)
    ap:SetMovable(true)
    ap:EnableMouse(true)
    ap:RegisterForDrag("LeftButton")
    ap:SetScript("OnDragStart", ap.StartMoving)
    ap:SetScript("OnDragStop", ap.StopMovingOrSizing)
    ap:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "TwichUIAddonList")
    if R.S then Skin("Shell", ap) else
        ap:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        ap:SetBackdropColor(0.07, 0.065, 0.06, 0.98)
        ap:SetBackdropBorderColor(0.25, 0.23, 0.2, 1)
    end
    ap.title = Text(ap, "GameFontNormalLarge")
    ap.title:SetPoint("TOPLEFT", 16, -12)
    ap.title:SetTextColor(1, 1, 1)
    local close = CreateFrame("Button", nil, ap, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    Skin("CloseButton", close)
    ap.sub = Text(ap, "GameFontHighlightSmall")
    ap.sub:SetPoint("TOPLEFT", 16, -38)
    ap.sub:SetWidth(528)

    -- list (own scroll box; rows get a Link button)
    local box = CreateFrame("Frame", nil, ap, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 16, -64)
    box:SetSize(528, 250)
    if R.S then Skin("Panel", box, { inset = true }) else
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        box:SetBackdropColor(0, 0, 0, 0.35)
        box:SetBackdropBorderColor(1, 1, 1, 0.08)
    end
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    Skin("ScrollBar", scroll.ScrollBar)
    ap.content = CreateFrame("Frame", nil, scroll)
    ap.content:SetSize(490, 1)
    scroll:SetScrollChild(ap.content)
    ap.rows = {}

    ap.copyLabel = Text(ap, "GameFontHighlightSmall")
    ap.copyLabel:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -10)
    ap.copyLabel:SetText("Links: click a row's Link, or Copy all missing. Then Ctrl+C and paste in your browser.")

    local copyBox = CreateFrame("Frame", nil, ap, "BackdropTemplate")
    copyBox:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -28)
    copyBox:SetSize(528, 110)
    if R.S then Skin("Panel", copyBox, { inset = true }) else
        copyBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        copyBox:SetBackdropColor(0, 0, 0, 0.5)
        copyBox:SetBackdropBorderColor(1, 1, 1, 0.08)
    end
    local cs = CreateFrame("ScrollFrame", nil, copyBox, "UIPanelScrollFrameTemplate")
    cs:SetPoint("TOPLEFT", 6, -6)
    cs:SetPoint("BOTTOMRIGHT", -26, 6)
    Skin("ScrollBar", cs.ScrollBar)
    ap.edit = CreateFrame("EditBox", nil, cs)
    ap.edit:SetMultiLine(true)
    ap.edit:SetAutoFocus(false)
    ap.edit:SetFontObject("ChatFontNormal")
    ap.edit:SetWidth(490)
    ap.edit:SetScript("OnEscapePressed", ap.edit.ClearFocus)
    ap.edit:SetScript("OnEditFocusGained", function(e) e:HighlightText() end)
    cs:SetScrollChild(ap.edit)

    ap.copyAll = Btn(ap, "Copy all missing", 140, function()
        local lines = {}
        for _, e in ipairs(ap.items or {}) do
            if e.state ~= "installed" then
                local url = ST.AddonLink(e)
                lines[#lines + 1] = e.title .. "  " .. url
            end
        end
        ap.edit:SetText(#lines > 0 and table.concat(lines, "\n") or "Nothing missing.")
        ap.edit:SetFocus()
        ap.edit:HighlightText()
    end)
    ap.copyAll:SetPoint("BOTTOMLEFT", 16, 12)
    ap.recheck = Btn(ap, "Check again", 110, function() W:ShowAddonList(ap.sourceKey) end,
        "Installed something? The game only notices new addons after you restart it; then check again.")
    ap.recheck:SetPoint("LEFT", ap.copyAll, "RIGHT", 8, 0)
end

local function AddonRow(i)
    local r = ap.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, ap.content)
    r:SetSize(490, ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r.state = Text(r, "GameFontHighlightSmall")
    r.state:SetPoint("LEFT", 6, 0)
    r.state:SetWidth(90)
    r.title = Text(r, "GameFontHighlight")
    r.title:SetPoint("LEFT", r.state, "RIGHT", 6, 0)
    r.title:SetWidth(250)
    r.title:SetWordWrap(false)
    r.where = Text(r, "GameFontDisableSmall")
    r.where:SetPoint("LEFT", r.title, "RIGHT", 6, 0)
    r.where:SetWidth(80)
    r.link = Btn(r, "Link", 50, function(b)
        ap.edit:SetText(b.item.title .. "  " .. (ST.AddonLink(b.item)))
        ap.edit:SetFocus()
        ap.edit:HighlightText()
    end)
    r.link:SetHeight(20)
    r.link:SetPoint("RIGHT", -4, 0)
    ap.rows[i] = r
    return r
end

function W:ShowAddonList(sourceKey)
    local pack = ST.SourcePack(sourceKey)
    if not pack then return end
    if not ap then BuildAddonPopup() end
    ap.sourceKey = sourceKey
    ap.items = ST.SortedRecommended(pack)
    local missing = 0
    for i, e in ipairs(ap.items) do
        local r = AddonRow(i)
        local _, where = ST.AddonLink(e)
        r.state:SetText(STATE_LABEL[e.state])
        r.title:SetText(e.title)
        r.where:SetText(where)
        r.link.item = e
        r.link:SetShown(e.state ~= "installed")
        r:Show()
        if e.state ~= "installed" then missing = missing + 1 end
    end
    for i = #ap.items + 1, #ap.rows do ap.rows[i]:Hide() end
    ap.content:SetHeight(math.max(1, #ap.items * ROW_H))
    ap.title:SetText(("%s's addons"):format(pack.sourceName or "Shared"))
    ap.sub:SetText(missing > 0
        and ("%d recommended, %s%d to install|r. Install them in the CurseForge app, then restart the game."):format(#ap.items, RED, missing)
        or ("%d recommended, %sall installed|r."):format(#ap.items, GREEN))
    ap.edit:SetText("")
    ap:Show()
end

---------------------------------------------------------------------------
-- Page: Get a setup
---------------------------------------------------------------------------
local get = {}

local STATE_TEXT = { ready = GREEN .. "Ready|r", missing = RED .. "Not installed|r", disabled = GOLD .. "Turned off|r", unknown = GREY .. "?|r" }

local function CurrentSource()
    local sources = ST.Sources()
    if #sources == 0 then return nil, sources end
    if sourceIndex > #sources then sourceIndex = 1 end
    return sources[sourceIndex], sources
end

local function SelectedNames(src)
    local sel = getSel[src.key] or {}
    local names = {}
    for _, g in ipairs(ST.PackByAddon(src.pack)) do
        if sel[g.owner] ~= false and g.state ~= "missing" then
            for _, n in ipairs(g.tables) do names[#names + 1] = n end
        end
    end
    return names
end

local function BuildGet(p)
    get.incoming = Text(p, "GameFontHighlightSmall")
    get.incoming:SetPoint("TOPLEFT", 16, -4)
    get.incoming:SetWidth(WIDTH - 32)
    get.bar = ProgressBar(p)
    get.bar:SetPoint("TOPLEFT", 16, -24)

    get.title = Text(p, "GameFontNormalLarge")
    get.title:SetPoint("TOPLEFT", 16, -44)
    get.title:SetTextColor(1, 1, 1)
    get.sub = Text(p, "GameFontHighlightSmall")
    get.sub:SetPoint("TOPLEFT", get.title, "BOTTOMLEFT", 0, -4)
    get.sub:SetWidth(WIDTH - 200)
    get.prev = Btn(p, "<", 28, function() sourceIndex = sourceIndex - 1; if sourceIndex < 1 then sourceIndex = #ST.Sources() end; W:Refresh() end)
    get.next = Btn(p, ">", 28, function() sourceIndex = sourceIndex + 1; W:Refresh() end)
    get.remove = Btn(p, "Delete", 80, function()
        local src = CurrentSource()
        if src and src.key ~= "file" then
            Confirm("TWICHUI_REMOVE", ("Delete the addon configuration from %s?\n\nSettings you already applied stay. They can send it again if you want it back."):format(src.from), function()
                ST:RemoveReceived(src.key:match("^recv:(.+)$")); sourceIndex = 1; W:Refresh()
            end)
        end
    end)
    get.remove:SetPoint("TOPRIGHT", -16, -44)
    get.next:SetPoint("RIGHT", get.remove, "LEFT", -8, 0)
    get.prev:SetPoint("RIGHT", get.next, "LEFT", -4, 0)

    get.list = ListBox(p, 230)
    get.list:SetPoint("TOPLEFT", 16, -92)
    get.missing = Text(p, "GameFontHighlightSmall")
    get.missing:SetPoint("TOPLEFT", get.list, "BOTTOMLEFT", 2, -6)
    get.missing:SetWidth(WIDTH - 250)
    get.addonsBtn = Btn(p, "Recommended addons", 210, function()
        local src = CurrentSource()
        if src then W:ShowAddonList(src.key) end
    end, "The addons your friend uses, with download links for the ones you don't have yet.")
    get.addonsBtn:SetPoint("TOPRIGHT", get.list, "BOTTOMRIGHT", 0, -4)

    get.apply = Btn(p, "Apply to this character", 170, function()
        local src = CurrentSource(); if not src or not NoCombat() then return end
        local names = SelectedNames(src)
        if #names == 0 then R.Print("nothing ticked.") return end
        Confirm("TWICHUI_APPLY", ("Use %s's settings for the ticked addons? What you have now is backed up, so you can undo. Your UI reloads."):format(src.from),
            function() ST:Queue("apply", names, src.key) end)
    end, "Replaces your settings for the ticked addons with this configuration. Your current settings are backed up first.")
    get.apply:SetPoint("TOPLEFT", 16, -372)
    get.alt = Btn(p, "Use on this alt", 130, function()
        local src = CurrentSource(); if not src or not NoCombat() then return end
        Confirm("TWICHUI_ALT", "Switch this character to the shared configuration's profiles? Nothing is copied again. Your UI reloads.",
            function() ST:Queue("alt", SelectedNames(src), src.key) end)
    end, "Already applied this configuration on another character? This points this character at the same profiles without copying anything.")
    get.alt:SetPoint("LEFT", get.apply, "RIGHT", 8, 0)
    get.undo = Btn(p, "Undo", 80, function()
        if not NoCombat() then return end
        Confirm("TWICHUI_UNDO", "Put back the settings you had on this character before the last apply? Your UI reloads.",
            function() ST:Queue("undo", ST:BackupNames(), nil) end)
    end, "Restores what you had on this character before you last applied a configuration.")
    get.undo:SetPoint("LEFT", get.alt, "RIGHT", 8, 0)
    get.em = Btn(p, "Edit Mode layout", 130, function() W:ShowEditMode() end,
        "Shows the layout text. Copy it, open Edit Mode, and use Import in the layout menu.")
    get.em:SetPoint("LEFT", get.undo, "RIGHT", 8, 0)

    get.report = Text(p, "GameFontHighlightSmall")
    get.report:SetPoint("TOPLEFT", 16, -406)
    get.report:SetWidth(WIDTH - 32)

    get.trusted = Text(p, "GameFontDisableSmall")
    get.trusted:SetPoint("BOTTOMLEFT", 16, 10)
    get.trusted:SetWidth(WIDTH - 140)
    get.clearTrust = Btn(p, "Clear", 70, function() wipe(ST.db.trusted); W:Refresh() end,
        "Ask again before accepting a configuration from anyone.")
    get.clearTrust:SetPoint("BOTTOMRIGHT", -16, 6)
end

local function RefreshGet()
    -- Incoming transfer
    local inc, incFrom
    for sender, i in pairs(SH.incoming) do
        if i.stage ~= "declined" then inc, incFrom = i, sender end
    end
    get.bar:SetShown(inc ~= nil and (inc.stage == "receiving" or inc.stage == "waiting" or inc.stage == "unpacking"))
    if inc then
        local who = SH.Short(incFrom)
        if inc.stage == "asking" then
            get.incoming:SetText(("%s wants to share their addon configuration with you. Answer the prompt."):format(who))
        elseif inc.stage == "waiting" then
            get.bar:SetValue(0)
            get.incoming:SetText(("Getting ready to receive from %s..."):format(who))
        elseif inc.stage == "receiving" then
            local frac = (inc.expected or 0) > 0 and math.min(1, inc.got / inc.expected) or 0
            get.bar:SetValue(frac)
            get.incoming:SetText(("Receiving %s's addon configuration: %d%%"):format(who, frac * 100))
        elseif inc.stage == "unpacking" then
            get.bar:SetValue(1)
            get.incoming:SetText(("Unpacking %s's addon configuration..."):format(who))
        elseif inc.stage == "done" then
            get.incoming:SetText(("%sReceived|r %s's addon configuration."):format(GREEN, who))
        elseif inc.stage == "failed" then
            get.incoming:SetText(RED .. (inc.reason or "Receiving failed.") .. "|r")
        end
    else
        get.incoming:SetText(GREY .. "When a friend sends you their addon configuration, it shows up here.|r")
    end

    local src, sources = CurrentSource()
    get.prev:SetShown(#sources > 1)
    get.next:SetShown(#sources > 1)
    get.remove:SetShown(src ~= nil and src.key ~= "file")
    local lines = 0
    local missing = {}
    if src then
        local pack = src.pack
        get.title:SetText(("%s's addon configuration"):format(src.from))
        get.sub:SetText(("Version %d  ·  updated %s  ·  %d addons%s%s"):format(pack.version or 1, When(pack.created),
            ST.CountAddons(pack), pack.editMode and "  ·  Edit Mode layout" or "",
            #sources > 1 and ("  ·  %d of %d"):format(sourceIndex, #sources) or ""))
        getSel[src.key] = getSel[src.key] or {}
        local sel = getSel[src.key]
        for _, g in ipairs(ST.PackByAddon(pack)) do
            lines = lines + 1
            local r = ListRow(get.list, lines)
            local usable = g.state ~= "missing"
            if not usable then missing[#missing + 1] = g.title end
            r.check:Show()
            r.check:SetChecked(usable and sel[g.owner] ~= false)
            r.check:SetEnabled(usable)
            r.check:SetScript("OnClick", function(c) sel[g.owner] = c:GetChecked() and true or false end)
            r.arrow:SetText("")
            r.label:SetText(g.title)
            r.label:SetTextColor(usable and 1 or 0.5, usable and 1 or 0.5, usable and 1 or 0.5)
            r.right:SetText(STATE_TEXT[g.state] or "")
            r:SetScript("OnClick", nil)
            -- Show exactly which settings tables applying would replace.
            r:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(g.title, 1, 1, 1)
                GameTooltip:AddLine("Applying replaces:", 0.7, 0.7, 0.7)
                for _, name in ipairs(g.tables) do GameTooltip:AddLine(name, 1, 1, 1) end
                GameTooltip:Show()
            end)
            r:Show()
        end
    else
        get.title:SetText("Nothing shared with you yet")
        get.sub:SetText(GREY .. "Ask a friend with TwichUI to send you theirs from their My configuration page.|r")
    end
    FinishList(get.list, lines, "")
    get.missing:SetText(#missing > 0 and (RED .. "Install first to get these settings: " .. table.concat(missing, ", ") .. "|r") or "")
    local recCount, recMissing = 0, 0
    if src and src.pack.addons then
        for _, e in ipairs(ST.SortedRecommended(src.pack)) do
            recCount = recCount + 1
            if e.state ~= "installed" then recMissing = recMissing + 1 end
        end
    end
    get.addonsBtn:SetShown(recCount > 0)
    get.addonsBtn:SetText(recMissing > 0 and ("Recommended addons (%d missing)"):format(recMissing) or "Recommended addons")

    get.apply:SetEnabled(src ~= nil)
    get.alt:SetEnabled(src ~= nil)
    get.undo:SetEnabled(ST:HasBackup() and true or false)
    get.em:SetShown(src ~= nil and src.pack.editMode ~= nil)

    local rep = ST.report
    get.report:SetText(rep and (GREY .. ("Last change: %d settings updated%s.|r"):format(#rep.done,
        #rep.skipped > 0 and (", %d skipped"):format(#rep.skipped) or "")) or "")

    local names = {}
    for n in pairs(ST.db.trusted) do names[#names + 1] = SH.Short(n) end
    table.sort(names)
    get.trusted:SetText(#names > 0 and ("Accepts automatically from: " .. table.concat(names, ", ")) or "Always asks before accepting a configuration.")
    get.clearTrust:SetShown(#names > 0)
end

---------------------------------------------------------------------------
-- Page: Group (version + recommended addons for everyone in your group)
---------------------------------------------------------------------------
local gp = {}
local GROUP_STATE = {
    ok = GREEN .. "Up to date|r", ahead = GOLD .. "Newer than yours|r", behind = GOLD .. "Older than yours|r",
    old = RED .. "Too old to share with|r", none = GREY .. "No TwichUI detected|r", waiting = GREY .. "Asking...|r",
}

local function BuildGroup(p)
    gp.help = Text(p, "GameFontHighlightSmall")
    gp.help:SetPoint("TOPLEFT", 16, -4)
    gp.help:SetWidth(WIDTH - 200)
    gp.help:SetText("Checks everyone in your group: which TwichUI they run, and which addons from your addon list they're missing. Off by default; uses only the group channel, and only a few bytes.")
    gp.run = Btn(p, "Check my group", 140, function() R.Group:RunCheck(true); W:Refresh() end)
    gp.run:SetPoint("TOPRIGHT", -16, -4)
    gp.enable = Btn(p, "Turn on group check", 170, function()
        TwichUIDB.modules.groupCheck = true
        R.Group:SayHello()
        W:Refresh()
    end, "Lets TwichUI trade version numbers with other TwichUI users in your group (a few bytes, group channel only). Everyone who wants to show up here needs it on too. You can turn it off again in /twichui.")
    gp.enable:SetPoint("TOPRIGHT", -16, -4)
    gp.list = ListBox(p, 330)
    gp.list:SetPoint("TOPLEFT", 16, -44)
    gp.you = Text(p, "GameFontHighlightSmall")
    gp.you:SetPoint("TOPLEFT", gp.list, "BOTTOMLEFT", 2, -8)
    gp.you:SetWidth(WIDTH - 32)
    gp.dm = Text(p, "GameFontDisableSmall")
    gp.dm:SetPoint("TOPLEFT", gp.you, "BOTTOMLEFT", 0, -6)
    gp.dm:SetWidth(WIDTH - 32)
end

local function RefreshGroup()
    local G = R.Group
    local rows = G:CheckRows()
    for i, r in ipairs(rows) do
        local row = ListRow(gp.list, i)
        row.check:Hide()
        row.arrow:SetText("")
        row.label:SetText(r.short .. (r.version and (GREY .. "   TwichUI " .. r.version .. "|r") or ""))
        row.label:SetTextColor(1, 1, 1)
        local right = GROUP_STATE[r.state] or ""
        if r.missing and #r.missing > 0 then right = right .. RED .. ("  ·  missing %d|r"):format(#r.missing) end
        row.right:SetText(right)
        row:SetScript("OnClick", nil)
        row:SetScript("OnEnter", function(self)
            if not (r.missing and #r.missing > 0) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(("%s is missing"):format(r.short), 1, 1, 1)
            for _, t in ipairs(r.missing) do GameTooltip:AddLine(t, 0.9, 0.9, 0.9) end
            GameTooltip:Show()
        end)
        row:Show()
    end
    local empty
    if not R:Enabled("groupCheck") then empty = "Group check is off. Turn it on to see your group's TwichUI versions and missing addons; your friends need it on too."
    elseif not IsInGroup() then empty = "You're not in a group."
    elseif not G.check then empty = "Click \"Check my group\"." end
    if G.check or #rows == 0 then FinishList(gp.list, #rows, empty or "Nobody else is in your group.")
    else FinishList(gp.list, 0, empty or "") end
    gp.run:SetShown(R:Enabled("groupCheck"))
    gp.enable:SetShown(not R:Enabled("groupCheck"))
    gp.run:SetEnabled(R:Enabled("groupCheck") and IsInGroup())
    gp.you:SetText(("You: TwichUI %s"):format(G.Version()))
    gp.dm:SetText("Direct messages on Forever: " .. G.WhisperStatus())
end

---------------------------------------------------------------------------
-- Page: Restore points
---------------------------------------------------------------------------
local rp = {}

local function BuildRestore(p)
    rp.help = Text(p, "GameFontHighlightSmall")
    rp.help:SetPoint("TOPLEFT", 16, -4)
    rp.help:SetWidth(WIDTH - 32)
    rp.help:SetText("Save your own settings before you change things, and go back any time. A restore point covers the addons ticked on My configuration, exactly as they're saved right now. Restoring backs up your current settings first, so Undo still works.")
    rp.name = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    rp.name:SetSize(260, 24)
    rp.name:SetPoint("TOPLEFT", 22, -48)
    rp.name:SetAutoFocus(false)
    rp.name:SetScript("OnEscapePressed", rp.name.ClearFocus)
    rp.name:SetScript("OnTextChanged", function() rp.hint:SetShown(rp.name:GetText() == "") end)
    Skin("EditBox", rp.name)
    rp.hint = Text(rp.name, "GameFontDisableSmall")
    rp.hint:SetPoint("LEFT", 6, 0)
    rp.hint:SetText("Name (optional), e.g. before EllesmereUI rework")
    rp.create = Btn(p, "Create restore point", 170, function()
        local status, why = R.Restore:Create(rp.name:GetText())
        if status == "created" then
            R.Print("restore point \"%s\" saved (%d addons).", why.name, ST.CountAddons(why))
            rp.name:SetText("")
        elseif not status then
            R.Print(why)
        end
        W:Refresh()
    end, function()
        return ST.capture and "Saves the ticked addons' settings from this session's search."
            or "Reloads your UI once to read your settings exactly as they're saved, then saves the point."
    end)
    rp.create:SetPoint("LEFT", rp.name, "RIGHT", 10, 0)

    rp.list = ListBox(p, 320)
    rp.list:SetPoint("TOPLEFT", 16, -84)
    rp.list.content:SetHeight(1)
end

local function RestoreRow(i)
    local r = rp.list.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, rp.list.content)
    r:SetSize(WIDTH - 70, 40)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * 42)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0.03)
    r.label = Text(r, "GameFontHighlight")
    r.label:SetPoint("TOPLEFT", 8, -5)
    r.label:SetWidth(380)
    r.label:SetWordWrap(false)
    r.detail = Text(r, "GameFontDisableSmall")
    r.detail:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -3)
    r.detail:SetWidth(380)
    r.del = Btn(r, "Delete", 70, function(b)
        local point = b.point
        Confirm("TWICHUI_RP_DELETE", ("Delete restore point \"%s\"?"):format(point.name), function()
            R.Restore:Delete(point.id); W:Refresh()
        end)
    end)
    r.del:SetPoint("RIGHT", -6, 0)
    r.go = Btn(r, "Restore", 80, function(b)
        local point = b.point
        if InCombatLockdown() then R.Print("not in combat, please.") return end
        Confirm("TWICHUI_RP_RESTORE", ("Go back to \"%s\"? Your current settings are backed up first (Undo on Shared with me). Your UI reloads."):format(point.name),
            function() R.Restore:Restore(point.id) end)
    end)
    r.go:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
    rp.list.rows[i] = r
    return r
end

local function RefreshRestore()
    local points = R.Restore.List()
    for i, point in ipairs(points) do
        local r = RestoreRow(i)
        r.label:SetText(point.name)
        r.detail:SetText(("%s  ·  %s  ·  %d addons  ·  %s"):format(When(point.created), point.sourceName or "?",
            ST.CountAddons(point), ST.FormatSize(R.Restore.Size(point))))
        r.go.point, r.del.point = point, point
        r:Show()
    end
    for i = #points + 1, #rp.list.rows do rp.list.rows[i]:Hide() end
    rp.list.content:SetHeight(math.max(1, #points * 42))
    rp.list.empty:SetText(#points == 0 and "No restore points yet." or "")
    rp.hint:SetShown(rp.name:GetText() == "" and not rp.name:HasFocus())
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function SetPage(which)
    page = which
    f.pageMine:SetShown(which == "mine")
    f.pageGet:SetShown(which == "get")
    f.pageAddons:SetShown(which == "addons")
    f.pageGroup:SetShown(which == "group")
    f.pageRestore:SetShown(which == "restore")
    local tabs = { mine = f.tabMine, addons = f.tabAddons, get = f.tabGet, group = f.tabGroup, restore = f.tabRestore }
    for key, tab in pairs(tabs) do
        if R.S and R.S.SetTabSelection then
            pcall(R.S.SetTabSelection, tab, which == key)
        else
            tab.line:SetShown(which == key)
            tab:SetEnabled(which ~= key)
        end
    end
    W:Refresh()
end

local function Build()
    f = CreateFrame("Frame", "TwichUISetupWindow", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "TwichUISetupWindow")

    if R.S then
        Skin("Shell", f)
    else
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.07, 0.065, 0.06, 0.97)
        f:SetBackdropBorderColor(0.25, 0.23, 0.2, 1)
    end

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(26, 26)
    logo:SetPoint("TOPLEFT", 12, -8)
    logo:SetTexture(R.ICON)
    local title = Text(f, "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("TwichUI")
    title:SetTextColor(1, 1, 1)
    local sub = Text(f, "GameFontDisableSmall")
    sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
    sub:SetText("addon configuration")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    Skin("CloseButton", close)
    local storage = Btn(f, "Saved data", 100, function() W:ShowStorage() end,
        "See and delete what Configuration Sharing keeps: your saved configuration, ones friends sent you, and Undo backups.")
    storage:SetPoint("TOPRIGHT", -36, -9)

    -- Tabs are plain buttons with no Blizzard template: UIPanelButtonTemplate
    -- repaints its own art on every mouse down/up, which briefly showed through
    -- EllesmereUI's tab skin.
    local function TabBtn(label, onClick, width)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(width or 130, 24)
        b:SetNormalFontObject("GameFontNormal")
        b:SetHighlightFontObject("GameFontHighlight")
        b:SetDisabledFontObject("GameFontHighlight")
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        if R.S then
            Skin("Tab", b)
        else
            -- Plain fallback: dark plate, accent underline on the active tab.
            b.bg = b:CreateTexture(nil, "BACKGROUND")
            b.bg:SetAllPoints()
            b.bg:SetColorTexture(1, 1, 1, 0.04)
            b.line = b:CreateTexture(nil, "ARTWORK")
            b.line:SetHeight(2)
            b.line:SetPoint("BOTTOMLEFT")
            b.line:SetPoint("BOTTOMRIGHT")
            b.line:SetColorTexture(Accent())
            b.line:Hide()
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.05)
        end
        return b
    end
    f.tabMine = TabBtn("My configuration", function() SetPage("mine") end)
    f.tabMine:SetPoint("TOPLEFT", 14, -40)
    f.tabAddons = TabBtn("My addon list", function() SetPage("addons") end)
    f.tabAddons:SetPoint("LEFT", f.tabMine, "RIGHT", 4, 0)
    f.tabGet = TabBtn("Shared with me", function() SetPage("get") end)
    f.tabGet:SetPoint("LEFT", f.tabAddons, "RIGHT", 4, 0)
    f.tabGroup = TabBtn("Group", function() SetPage("group") end, 90)
    f.tabGroup:SetPoint("LEFT", f.tabGet, "RIGHT", 4, 0)
    f.tabRestore = TabBtn("Restore points", function() SetPage("restore") end, 130)
    f.tabRestore:SetPoint("LEFT", f.tabGroup, "RIGHT", 4, 0)

    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 12, -66)
    line:SetPoint("TOPRIGHT", -12, -66)

    f.pageMine = CreateFrame("Frame", nil, f)
    f.pageMine:SetPoint("TOPLEFT", 0, -74)
    f.pageMine:SetPoint("BOTTOMRIGHT")
    f.pageAddons = CreateFrame("Frame", nil, f)
    f.pageAddons:SetPoint("TOPLEFT", 0, -74)
    f.pageAddons:SetPoint("BOTTOMRIGHT")
    f.pageGet = CreateFrame("Frame", nil, f)
    f.pageGet:SetPoint("TOPLEFT", 0, -74)
    f.pageGet:SetPoint("BOTTOMRIGHT")
    f.pageGroup = CreateFrame("Frame", nil, f)
    f.pageGroup:SetPoint("TOPLEFT", 0, -74)
    f.pageGroup:SetPoint("BOTTOMRIGHT")
    f.pageRestore = CreateFrame("Frame", nil, f)
    f.pageRestore:SetPoint("TOPLEFT", 0, -74)
    f.pageRestore:SetPoint("BOTTOMRIGHT")
    BuildMine(f.pageMine)
    BuildAddons(f.pageAddons)
    BuildGet(f.pageGet)
    BuildGroup(f.pageGroup)
    BuildRestore(f.pageRestore)

    if R.S then for _, fs in ipairs(fontStrings) do Skin("Font", fs) end end

    f:SetScript("OnShow", function() W:Refresh() end)
    -- Transfers report progress per chunk; redraw at most a few times a second,
    -- and not at all on pages that show nothing about transfers or the group.
    local refreshQueued = false
    local function QueueRefresh()
        if refreshQueued or not f:IsShown() or page == "addons" or page == "restore" then return end
        refreshQueued = true
        C_Timer.After(0.25, function() refreshQueued = false; W:Refresh() end)
    end
    SH:OnChange(QueueRefresh)
    R.Group:OnChange(QueueRefresh)
end

function W:Refresh()
    if not f or not f:IsShown() then return end
    if page == "mine" then RefreshMine()
    elseif page == "addons" then RefreshAddons()
    elseif page == "group" then RefreshGroup()
    elseif page == "restore" then RefreshRestore()
    else RefreshGet() end
end

function W:Show(which)
    if not f then Build() end
    f:Show()
    if toast then toast:Hide() end
    SetPage(which or page)
end

function W:Toggle()
    if f and f:IsShown() then f:Hide() return end
    local startPage = page
    if not f then
        -- First open: friends land on "Get a setup", setup makers on "My setup".
        startPage = (ST.Mine() or ST.capture or next(ST.db.detected)) and "mine" or "get"
        if #ST.Sources() > 0 and not ST.Mine() then startPage = "get" end
    end
    W:Show(startPage)
end

---------------------------------------------------------------------------
-- Prompts
---------------------------------------------------------------------------
function W:AskAccept(sender, offer)
    local who = SH.Short(sender)
    -- There's one prompt. If someone else's offer is still waiting on it,
    -- answer that one "not now" so they aren't left hanging when it's replaced.
    for other, inc in pairs(SH.incoming) do
        if other ~= sender and inc.stage == "asking" then SH:Respond(other, false) end
    end
    StaticPopupDialogs.TWICHUI_OFFER = {
        text = "%s",
        button1 = "Accept", button2 = "Not now", button3 = ("Always accept from %s"):format(who),
        -- Newer clients pass the data as an argument and no longer set
        -- dialog.data, so keep the sender in this closure instead.
        OnAccept = function() SH:Respond(sender, true) end,
        OnCancel = function(_, _, reason) if reason ~= "override" then SH:Respond(sender, false) end end,
        OnAlt = function() SH:Respond(sender, true, true) end,
        timeout = 110, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    local text = ("%s wants to share their addon configuration with you: %d addons, about %s.\n\nAccepting just downloads it. You choose what to apply afterwards."):format(
        who, offer.addons or 0, ST.FormatSize(offer.bytes or 0))
    StaticPopup_Show("TWICHUI_OFFER", text, nil, sender)
end

function W:Received(sender)
    local who = SH.Short(sender)
    R.Print("%s's addon configuration arrived. Type /pack to look it over and apply it.", who)
    for i, s in ipairs(ST.Sources()) do if s.key == "recv:" .. sender then sourceIndex = i end end
    if f and f:IsShown() then SetPage("get") return end
    StaticPopupDialogs.TWICHUI_RECEIVED = {
        text = "%s's addon configuration arrived. Open it now?",
        button1 = "Open", button2 = "Later",
        OnAccept = function() W:Show("get") end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("TWICHUI_RECEIVED", who)
end

---------------------------------------------------------------------------
-- Transfer toast: when the window is closed, a small bar at the top of the
-- screen shows sending/receiving progress. Click it to open the window.
---------------------------------------------------------------------------
local function BuildToast()
    toast = CreateFrame("Button", "TwichUITransferToast", UIParent, "BackdropTemplate")
    toast:SetSize(340, 50)
    toast:SetPoint("TOP", 0, -140)
    toast:SetFrameStrata("DIALOG")
    toast:SetClampedToScreen(true)
    if R.S then Skin("Panel", toast) else
        toast:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        toast:SetBackdropColor(0.07, 0.065, 0.06, 0.95)
        toast:SetBackdropBorderColor(0.25, 0.23, 0.2, 1)
    end
    toast.icon = toast:CreateTexture(nil, "ARTWORK")
    toast.icon:SetSize(30, 30)
    toast.icon:SetPoint("LEFT", 10, 0)
    toast.icon:SetTexture(R.ICON)
    toast.text = Text(toast, "GameFontHighlightSmall")
    toast.text:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 10, -2)
    toast.text:SetPoint("RIGHT", -10, 0)
    toast.text:SetWordWrap(false)
    toast.bar = ProgressBar(toast)
    toast.bar:SetWidth(280)
    toast.bar:SetPoint("BOTTOMLEFT", toast.icon, "BOTTOMRIGHT", 10, 2)
    toast.bar:SetPoint("RIGHT", -10, 0)
    if R.S then Skin("Font", toast.text) end
    toast:SetScript("OnClick", function(self) self:Hide(); W:Show(self.page) end)
    toast:Hide()
end

function W:UpdateToast()
    if f and f:IsShown() then if toast then toast:Hide() end return end
    local text, frac, pagename, finished
    local o = SH.outgoing
    if o and not o.toasted then
        local who = SH.Short(o.target)
        pagename = "mine"
        if o.stage == "offered" then text, frac = ("Waiting for %s to accept..."):format(who), 0
        elseif o.stage == "packing" then text, frac = "Packing your configuration...", 0
        elseif o.stage == "sending" or o.stage == "delivered" then
            frac = (o.total or 0) > 0 and (o.sent or 0) / o.total or 0
            text = ("Sending to %s: %d%%"):format(who, frac * 100)
        elseif o.stage == "done" then text, frac, finished = ("%s has your addon configuration."):format(who), 1, o
        elseif o.stage == "failed" then text, frac, finished = RED .. (o.reason or "Sending failed.") .. "|r", 0, o end
    end
    for sender, inc in pairs(SH.incoming) do
        if inc.stage == "unpacking" then
            text, frac, pagename, finished = ("Unpacking %s's addon configuration..."):format(SH.Short(sender)), 1, "get", nil
        elseif inc.stage == "waiting" or inc.stage == "receiving" then
            local who = SH.Short(sender)
            frac = (inc.expected or 0) > 0 and math.min(1, inc.got / inc.expected) or 0
            text, pagename, finished = ("Receiving %s's addon configuration: %d%%"):format(who, frac * 100), "get", nil
        elseif (inc.stage == "done" or inc.stage == "failed") and not inc.toasted then
            local who = SH.Short(sender)
            text = inc.stage == "done" and ("%s's addon configuration arrived. Click to open."):format(who)
                or (RED .. (inc.reason or "Receiving failed.") .. "|r")
            frac, pagename, finished = inc.stage == "done" and 1 or 0, "get", inc
        end
    end
    if not text then if toast then toast:Hide() end return end
    if not toast then BuildToast() end
    toast.page = pagename
    toast.text:SetText(text)
    toast.bar:SetValue(frac or 0)
    toast:Show()
    if finished and not finished.toastTimer then
        finished.toastTimer = true
        C_Timer.After(6, function()
            finished.toasted = true
            W:UpdateToast()
        end)
    end
end
SH:OnChange(function() W:UpdateToast() end)

---------------------------------------------------------------------------
-- Popup: saved data (everything TwichUI stores, with Delete)
---------------------------------------------------------------------------
local sp

local function BuildStorage()
    sp = CreateFrame("Frame", "TwichUIStorage", UIParent, "BackdropTemplate")
    sp:SetSize(560, 420)
    sp:SetPoint("CENTER", 30, -10)
    sp:SetFrameStrata("DIALOG")
    sp:SetToplevel(true)
    sp:SetMovable(true)
    sp:EnableMouse(true)
    sp:RegisterForDrag("LeftButton")
    sp:SetScript("OnDragStart", sp.StartMoving)
    sp:SetScript("OnDragStop", sp.StopMovingOrSizing)
    sp:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "TwichUIStorage")
    if R.S then Skin("Shell", sp) else
        sp:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        sp:SetBackdropColor(0.07, 0.065, 0.06, 0.98)
        sp:SetBackdropBorderColor(0.25, 0.23, 0.2, 1)
    end
    local title = Text(sp, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText("Saved data")
    title:SetTextColor(1, 1, 1)
    local close = CreateFrame("Button", nil, sp, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    Skin("CloseButton", close)
    sp.sub = Text(sp, "GameFontHighlightSmall")
    sp.sub:SetPoint("TOPLEFT", 16, -38)
    sp.sub:SetWidth(528)
    sp.sub:SetText("Everything Configuration Sharing keeps between sessions. The game loads all of it each time you log in, so delete what you no longer need.")

    local box = CreateFrame("Frame", nil, sp, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 16, -76)
    box:SetSize(528, 280)
    if R.S then Skin("Panel", box, { inset = true }) else
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        box:SetBackdropColor(0, 0, 0, 0.35)
        box:SetBackdropBorderColor(1, 1, 1, 0.08)
    end
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    Skin("ScrollBar", scroll.ScrollBar)
    sp.content = CreateFrame("Frame", nil, scroll)
    sp.content:SetSize(490, 1)
    scroll:SetScrollChild(sp.content)
    sp.empty = Text(box, "GameFontDisableSmall")
    sp.empty:SetPoint("CENTER")
    sp.rows = {}

    sp.total = Text(sp, "GameFontHighlightSmall")
    sp.total:SetPoint("BOTTOMLEFT", 18, 20)
    sp.total:SetWidth(360)
    sp.note = Text(sp, "GameFontDisableSmall")
    sp.note:SetPoint("BOTTOMLEFT", 18, 6)
    sp.note:SetText("Deleted data leaves the saved file the next time you reload or log out.")
end

local function StorageRow(i)
    local r = sp.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, sp.content)
    r:SetSize(490, 40)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * 42)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0.03)
    r.label = Text(r, "GameFontHighlight")
    r.label:SetPoint("TOPLEFT", 8, -5)
    r.label:SetWidth(300)
    r.label:SetWordWrap(false)
    r.detail = Text(r, "GameFontDisableSmall")
    r.detail:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -3)
    r.detail:SetWidth(300)
    r.size = Text(r, "GameFontHighlightSmall")
    r.size:SetPoint("RIGHT", -84, 0)
    r.size:SetJustifyH("RIGHT")
    r.del = Btn(r, "Delete", 70, function(b)
        local item = b.item
        Confirm("TWICHUI_DELETE", ("Delete %s?\n\n%s"):format(item.label, item.warn or ""), function()
            item.remove()
            W:ShowStorage()
            W:Refresh()
        end)
    end)
    r.del:SetPoint("RIGHT", -6, 0)
    sp.rows[i] = r
    return r
end

function W:ShowStorage()
    if not sp then BuildStorage() end
    local items = ST.StorageItems()
    local total = 0
    for i, item in ipairs(items) do
        local r = StorageRow(i)
        r.label:SetText(item.label)
        r.detail:SetText(item.kind .. "  ·  " .. item.detail)
        r.size:SetText(ST.FormatSize(item.bytes))
        r.del.item = item
        r:Show()
        total = total + item.bytes
    end
    for i = #items + 1, #sp.rows do sp.rows[i]:Hide() end
    sp.content:SetHeight(math.max(1, #items * 42))
    sp.empty:SetText(#items == 0 and "Nothing saved." or "")
    sp.total:SetText(("Total: about %s"):format(ST.FormatSize(total)))
    sp:Show()
end

---------------------------------------------------------------------------
-- Popup: sending options (which channels configurations may use)
---------------------------------------------------------------------------
local cp

local function BuildChannels()
    cp = CreateFrame("Frame", "TwichUISendingOptions", UIParent, "BackdropTemplate")
    cp:SetSize(540, 430)
    cp:SetPoint("CENTER", 20, 0)
    cp:SetFrameStrata("DIALOG")
    cp:SetToplevel(true)
    cp:SetMovable(true)
    cp:EnableMouse(true)
    cp:RegisterForDrag("LeftButton")
    cp:SetScript("OnDragStart", cp.StartMoving)
    cp:SetScript("OnDragStop", cp.StopMovingOrSizing)
    cp:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "TwichUISendingOptions")
    if R.S then Skin("Shell", cp) else
        cp:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        cp:SetBackdropColor(0.07, 0.065, 0.06, 0.98)
        cp:SetBackdropBorderColor(0.25, 0.23, 0.2, 1)
    end
    local title = Text(cp, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText("Sending options")
    title:SetTextColor(1, 1, 1)
    local close = CreateFrame("Button", nil, cp, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    Skin("CloseButton", close)

    local why = Text(cp, "GameFontHighlightSmall")
    why:SetPoint("TOPLEFT", 16, -42)
    why:SetWidth(508)
    why:SetSpacing(2)
    why:SetText(GOLD .. "Why Forever needs this|r\n" .. SH.WHY_FOREVER
        .. "\n\nGroup and guild messages are hidden addon traffic: no chat text appears. Everyone in that group or guild with TwichUI does receive the data, but it's addressed to one person and everyone else's TwichUI ignores it. The data is your addon settings, which can include character names. Direct messages will work again once Blizzard fixes them, and TwichUI will use them first.")

    local y = -180
    local function Option(key, label, desc)
        local c = Check(cp, label)
        c:SetPoint("TOPLEFT", 14, y)
        c.label:SetFontObject("GameFontHighlight")
        c:SetScript("OnClick", function(self)
            TwichUIDB.modules[key] = self:GetChecked() and true or false
            W:Refresh()
        end)
        local d = Text(cp, "GameFontDisableSmall")
        d:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 26, 0)
        d:SetWidth(470)
        d:SetText(desc)
        c.key = key
        y = y - 58
        return c
    end
    cp.opts = {
        Option("shareWhisper", "Allow direct messages",
            "Straight to one player; only they receive it. Doesn't work on Forever yet."),
        Option("shareGroup", "Allow group channel",
            "Everyone in your party or raid receives it; only the named friend's TwichUI reads it. Best choice on Forever."),
        Option("shareGuild", "Allow guild channel",
            "Every online guild member receives it; only the named friend's TwichUI reads it. Uses guild-wide bandwidth."),
    }
    cp.status = Text(cp, "GameFontHighlightSmall")
    cp.status:SetPoint("BOTTOMLEFT", 16, 44)
    cp.status:SetWidth(508)
    local note = Text(cp, "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 16, 12)
    note:SetWidth(508)
    note:SetText("These apply to receiving too: a friend's configuration only reaches you over channels you allow here. Test on myself stays on your computer when no allowed channel is available.")
end

function W:ShowChannels()
    if not cp then BuildChannels() end
    for _, c in ipairs(cp.opts) do c:SetChecked(R:Enabled(c.key)) end
    cp.status:SetText(GOLD .. "Status:|r " .. R.Group.WhisperStatus())
    cp:Show()
end

---------------------------------------------------------------------------
-- Edit Mode layout text
---------------------------------------------------------------------------
local em
function W:ShowEditMode()
    local src = CurrentSource()
    local pack = src and src.pack
    if not (pack and pack.editMode) then return end
    if not em then
        em = CreateFrame("Frame", "TwichUIEditModeText", UIParent, "BackdropTemplate")
        em:SetSize(480, 140)
        em:SetPoint("CENTER", 0, 140)
        em:SetFrameStrata("DIALOG")
        if R.S then Skin("Panel", em) else
            em:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            em:SetBackdropColor(0.07, 0.065, 0.06, 0.98)
            em:SetBackdropBorderColor(0.25, 0.23, 0.2, 1)
        end
        em.text = Text(em, "GameFontHighlightSmall")
        em.text:SetPoint("TOPLEFT", 14, -12)
        em.text:SetPoint("TOPRIGHT", -14, -12)
        em.box = CreateFrame("EditBox", nil, em, "InputBoxTemplate")
        em.box:SetSize(440, 24)
        em.box:SetPoint("TOP", 0, -66)
        em.box:SetAutoFocus(false)
        em.box:SetScript("OnEditFocusGained", function(b) b:HighlightText() end)
        em.box:SetScript("OnEscapePressed", function() em:Hide() end)
        Skin("EditBox", em.box)
        local done = Btn(em, "Done", 90, function() em:Hide() end)
        done:SetPoint("BOTTOM", 0, 12)
    end
    em.text:SetText(("Layout: %s%s|r\nClick the box and press Ctrl+C. Then open Edit Mode, open the layout menu, choose Import, and paste."):format(GOLD, pack.editModeName or "shared layout"))
    em.box:SetText(pack.editMode)
    em.box:SetCursorPosition(0)
    em:Show()
    em.box:SetFocus()
end

-- Friends: mention once when a setup is waiting and hasn't been applied.
R:On("PLAYER_LOGIN", function()
    if not R:Enabled("setupSharing") then return end
    if #ST.Sources() > 0 and not ST:HasBackup() and not ST.report and not ST.Mine() then
        C_Timer.After(4, function() R.Print("a shared addon configuration is waiting. Type /pack to look it over.") end)
    end
end)
