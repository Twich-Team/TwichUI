-- TwichUI: setup sharing window (/tui share)
-- Three pages: "Share setup" (choose, save, send; recommendations and the party
-- check open from it), "Received setups" (review, apply, undo) and "Backups".
-- Styled by EllesmereUI's skin toolkit when it's available.

local R = TwichUI
local ST, SH, ES = R.Setups, R.Share, R.Ellesmere
local W = {}
R.Window = W

local GOLD, GREY, RED, GREEN = R.GOLD, R.GREY, R.RED, R.GREEN
local WIDTH, HEIGHT = 720, 580
local ROW_H = 24
local POPUP_HEADER = 32       -- the title band of a popup
local f                         -- main frame
local page = "share"
local expanded = {}             -- [owner] = true in the Choose addons popup
local getSel = {}               -- [sourceKey] = { [owner] = bool }
local sourceIndex = 1
local toast                      -- transfer toast (built on first use)

---------------------------------------------------------------------------
-- The look: TwichUI's own (Look.lua), the same family as the settings window, whether or not EllesmereUI is
-- installed. It is looked up when something is first built (this file loads before it).
---------------------------------------------------------------------------
local function Look() return R.Look end

-- A font string's color from the palette's role ("text", "textDim", "stone", "bronzeText"), dimmed by k.
local function Ink(fs, role, k)
    local c = Look().pal[role]
    k = k or 1
    fs:SetTextColor(c[1] * k, c[2] * k, c[3] * k)
end

-- The role each of the game's font objects takes in this look (the sizes stay the game's own).
local ROLE = {
    GameFontNormalLarge = "text", GameFontNormal = "bronzeText", GameFontHighlight = "text",
    GameFontHighlightSmall = "textDim", GameFontDisableSmall = "stone", GameFontDisable = "stone",
}

-- A heading inside running text ("What it does"): the palette's bronze text, as an inline color. (GOLD stays
-- for the states that mean "pay attention": newer, older, turned off.)
local function Head()
    local c = Look().pal.bronzeText
    return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

local function Text(parent, template, size)
    template = template or "GameFontHighlight"
    local fs
    if template == "GameFontNormalLarge" then
        fs = Look().Text(parent, "title")   -- the title face, as the settings window's
    else
        fs = parent:CreateFontString(nil, "OVERLAY", template)
    end
    fs:SetJustifyH("LEFT")
    Ink(fs, ROLE[template] or "text")
    return fs
end

-- A button. kind: nil for an ordinary one, "danger" for one that puts things back. It is Look's raised button;
-- SetText and GetText are the window's (the old buttons were the game's template and had them).
local function Btn(parent, label, w, onClick, tooltip, kind)
    -- (Delete is the one action here that can't be taken back: the rust button, as Reset is in the settings)
    local b = Look().Button(parent, label, w, kind or (label == "Delete" and "danger") or "secondary", onClick)
    function b:SetText(t) self.text:SetText(t) end
    function b:GetText() return self.text:GetText() end
    -- tooltip: text, or a function giving the text and, when the button can't be used now, the reason
    if tooltip then R.Interact.Tip(b, label, tooltip) end
    return b
end

-- A check box with the game's CheckButton behaviour: a click flips it and then runs OnClick, which reads
-- GetChecked; SetEnabled greys it. Look's checkbox is the drawing.
local function Check(parent, label)
    local c = Look().Checkbox(parent, nil)
    local enabled = true
    local nativeEnabled, nativeScript = c.SetEnabled, c.SetScript
    function c:SetEnabled(v)
        enabled = v and true or false
        nativeEnabled(self, enabled)
        self:SetActive(enabled)
    end
    function c:SetScript(name, fn)
        if name == "OnClick" then
            nativeScript(self, "OnClick", function(box, ...)
                if not enabled then return end
                box:SetChecked(not box:GetChecked())
                if fn then fn(box, ...) end
            end)
        else
            nativeScript(self, name, fn)
        end
    end
    c:SetScript("OnClick", nil)   -- the flip alone, until a caller adds to it
    if label then
        c.label = Text(parent, "GameFontHighlightSmall")
        c.label:SetPoint("LEFT", c, "RIGHT", 6, 0)
        c.label:SetText(label)
    end
    return c
end

local function Section(parent, num, title, y)
    local n = Text(parent, "GameFontNormalLarge")
    n:SetPoint("TOPLEFT", 16, y)
    n:SetText(num)
    Ink(n, "bronzeText")
    local t = Text(parent, "GameFontNormal")
    t:SetPoint("LEFT", n, "RIGHT", 8, 0)
    t:SetText(title)
    Ink(t, "text")
    return n, t
end

local function ProgressBar(parent)
    local L = Look()
    local bar = CreateFrame("StatusBar", nil, parent, "BackdropTemplate")
    bar:SetSize(WIDTH - 32, 8)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local c = L.pal.teal
    bar:SetStatusBarColor(c[1], c[2], c[3])
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    L.Well(bar, 1)
    return bar
end

local function ListBox(parent, height, width)
    width = width or (WIDTH - 32)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(width, height)
    Look().Well(box, 0.9)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    Look().ScrollBar(scroll)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width - 38, 1)
    scroll:SetScrollChild(content)
    box.content, box.rows, box.scroll, box.rowW = content, {}, scroll, width - 38
    local empty = Text(box, "GameFontDisableSmall")
    empty:SetPoint("CENTER")
    empty:SetWidth(width - 68)
    empty:SetJustifyH("CENTER")
    box.empty = empty
    return box
end

local function ListRow(box, i)  -- box from ListBox
    local r = box.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, box.content)
    r:SetSize(box.rowW, ROW_H)
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
    r.label:SetWidth(box.rowW - 290)
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

-- See modules/Interact.lua: names what changes, accepts once, and can recheck the target on accepting.
local function Confirm(key, text, onAccept, opts)
    return R.Interact.Confirm(key, text, onAccept, opts)
end

local function NoCombat()
    if InCombatLockdown() then R.Print("that has to wait until you're out of combat.") return false end
    return true
end

local function When(t) return t and date("%b %d, %H:%M", t) or "?" end

---------------------------------------------------------------------------
-- Popups share one frame builder
---------------------------------------------------------------------------
local function MakePopup(name, w, h, title, dx, dy)
    local p = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    p:SetSize(w, h)
    p:SetPoint("CENTER", dx or 0, dy or 0)
    p:SetFrameStrata("DIALOG")
    p:SetToplevel(true)
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    p:SetClampedToScreen(true)
    p:HookScript("OnShow", R.FitToScreen)
    tinsert(UISpecialFrames, name)
    Look().Shell(p, POPUP_HEADER)
    p.title = Text(p, "GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT", 16, -12)
    p.title:SetText(title)
    Look().CloseBox(p)
    return p
end

local POPUP_W = 640
local POPUP_LIST_W = POPUP_W - 32

local function AskScan()
    if not NoCombat() then return end
    Confirm("TWICHUI_FIND", "Scan your installed addons for their settings? Your UI reloads once. Nothing is saved or sent by scanning.", function() ST:FindSettings() end, { combat = true })
end

-- Addons ticked, their size, and how many were found.
local function Chosen()
    local groups = ST:DetectedByAddon()
    local n, bytes = 0, 0
    local total = 0
    for _, g in ipairs(groups) do
        if not g.backupOnly then
            total = total + 1
            if g.selected > 0 then n = n + 1; bytes = bytes + g.bytes end
        end
    end
    return n, bytes, total
end

---------------------------------------------------------------------------
-- Popup: choose addons (which addons' settings go into the setup)
---------------------------------------------------------------------------
local cp                         -- choose-addons popup
local search = ""

local function BuildChoose()
    cp = MakePopup("TwichUIChooseAddons", POPUP_W, 520, "Choose addons", 0, 0)
    cp.help = Text(cp, "GameFontHighlightSmall")
    cp.help:SetPoint("TOPLEFT", 16, -40)
    cp.help:SetWidth(POPUP_LIST_W)

    cp.search = Look().EditBox(cp, 100, 24)
    cp.search:SetSize(260, 24)
    cp.search:SetPoint("TOPLEFT", 22, -74)
    cp.search:SetAutoFocus(false)
    cp.search:SetScript("OnEscapePressed", cp.search.ClearFocus)
    cp.search:SetScript("OnTextChanged", function(e)
        search = (e:GetText() or ""):lower()
        cp.hint:SetShown(search == "" and not e:HasFocus())
        W:Refresh()
    end)
    cp.search:SetScript("OnEditFocusGained", function() cp.hint:Hide() end)
    cp.search:SetScript("OnEditFocusLost", function(e) cp.hint:SetShown(e:GetText() == "") end)
    cp.hint = Text(cp.search, "GameFontDisableSmall")
    cp.hint:SetPoint("LEFT", 6, 0)
    cp.hint:SetText("Search addons")

    cp.suggest = Btn(cp, "Recommended", 110, function() ST:SelectSuggested(); W:Refresh() end,
        "Tick the settings most people want to share, and skip big data like price history, caches and logs.")
    cp.suggest:SetPoint("TOPRIGHT", -16, -72)

    cp.all = Btn(cp, "Select all", 90, function()
        ST:SelectAll()
        local TC = R.TwichConfig
        if TC then
            TC.SetIncluded(true)
            for _, gi in ipairs(TC.GroupList()) do
                if gi.usable then TC.SetGroupSelected(gi.id, true) end
            end
        end
        W:Refresh()
    end, "Tick every addon and every part of each, including TwichUI's own settings. Tables too big to share stay unticked.")
    cp.all:SetPoint("RIGHT", cp.suggest, "LEFT", -8, 0)

    cp.list = ListBox(cp, 340, POPUP_LIST_W)
    cp.list:SetPoint("TOPLEFT", 16, -106)
    cp.summary = Text(cp, "GameFontDisableSmall")
    cp.summary:SetPoint("TOPLEFT", cp.list, "BOTTOMLEFT", 2, -6)

    cp.scan = Btn(cp, "Scan installed addons", 170, AskScan,
        "Reloads your UI once and lists every addon that has saved settings, exactly as they're saved right now. Scanning never saves or sends anything.")
    cp.scan:SetPoint("BOTTOMLEFT", 16, 14)
    cp.done = Btn(cp, "Done", 90, function() cp:Hide() end)
    cp.done:SetPoint("BOTTOMRIGHT", -16, 14)
end

local TWICHUI_KEY = "TwichUI settings"

-- The first row of the list: TwichUI's own settings, by feature (setup/TwichConfig.lua). They are live data, so
-- they can be ticked without a scan.
local function TwichChooseRows()
    local TC = R.TwichConfig
    if not TC then return 0 end
    if search ~= "" and not ("twichui settings"):find(search, 1, true) then return 0 end
    local lines = 0
    local included = TC.Included()
    local list = TC.GroupList()
    local ticked, usable = 0, 0
    for _, gi in ipairs(list) do
        if gi.usable then usable = usable + 1 end
        if gi.usable and gi.selected then ticked = ticked + 1 end
    end
    lines = lines + 1
    local r = ListRow(cp.list, lines)
    r.check:Show()
    r.check:SetChecked(included)
    r.check:SetEnabled(usable > 0)
    r.check:SetScript("OnClick", function(c) TC.SetIncluded(c:GetChecked()); W:Refresh() end)
    r.arrow:SetText(expanded[TWICHUI_KEY] and "-" or "+")
    r.label:SetText("TwichUI's own settings")
    Ink(r.label, "text")
    r.right:SetText(GREY .. (included and ("%d of %d features"):format(ticked, usable) or "Not included") .. "|r")
    r:SetScript("OnClick", function() expanded[TWICHUI_KEY] = not expanded[TWICHUI_KEY]; W:Refresh() end)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("TwichUI's own settings", 1, 1, 1)
        GameTooltip:AddLine("How TwichUI's features behave and look, as they are on this profile right now. Click to choose features.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Never included: backups, Undo copies, received setups, the Journey Chronicle, map pins, positions, and anything that acts for you in the game or decides what you send to others.", 0.9, 0.8, 0.5, true)
        GameTooltip:Show()
    end)
    r:Show()
    if expanded[TWICHUI_KEY] then
        for _, gi in ipairs(list) do
            lines = lines + 1
            local c = ListRow(cp.list, lines)
            c.check:Show()
            c.check:SetChecked(included and gi.selected and gi.usable)
            c.check:SetEnabled(included and gi.usable)
            c.check:SetScript("OnClick", function(cb) TC.SetGroupSelected(gi.id, cb:GetChecked()); W:Refresh() end)
            c.arrow:SetText("")
            c.label:SetText("    " .. gi.label)
            Ink(c.label, "textDim", gi.usable and 1 or 0.55)
            local right = not gi.usable and "not available" or (gi.scope == "account" and "every profile")
                or (gi.custom and "by class and tree") or ("%d settings"):format(gi.count)
            c.right:SetText(GREY .. right .. "|r")
            c:SetScript("OnClick", nil)
            c:SetScript("OnEnter", gi.note and function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(gi.label, 1, 1, 1)
                GameTooltip:AddLine(gi.note, 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end or nil)
            c:Show()
        end
    end
    return lines
end

local function RefreshChoose()
    local groups = ST:DetectedByAddon()
    local lines = TwichChooseRows()
    local n, bytes = Chosen()
    for _, g in ipairs(groups) do
        if search == "" or g.title:lower():find(search, 1, true) then
            lines = lines + 1
            local r = ListRow(cp.list, lines)
            r.check:Show()
            r.check:SetChecked(g.selected > 0)
            r.check:SetEnabled(ST.capture ~= nil)
            r.check:SetScript("OnClick", function(c) ST:SetAddonSelected(g.owner, c:GetChecked()); W:Refresh() end)
            r.arrow:SetText(expanded[g.owner] and "-" or "+")
            r.label:SetText(g.title)
            r.right:SetText(GREY .. (g.backupOnly and "Backups only" or (g.selected > 0 and ST.FormatSize(g.bytes) or "")) .. "|r")
            r:SetScript("OnClick", function() expanded[g.owner] = not expanded[g.owner]; W:Refresh() end)
            r:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(g.title, 1, 1, 1)
                if g.backupOnly then
                    GameTooltip:AddLine("Kept in your backups, never sent to friends. Share one EllesmereUI profile with the EllesmereUI profile button on the Share setup page.", 0.9, 0.8, 0.5, true)
                end
                GameTooltip:AddLine("Click the name to see each part.", 0.7, 0.7, 0.7)
                for _, t in ipairs(g.tables) do
                    GameTooltip:AddDoubleLine((t.selected and "|cff8FB35A+|r " or "|cff8a857c-|r ") .. t.name,
                        ST.FormatSize(t.bytes), 1, 1, 1, 0.6, 0.6, 0.6)
                end
                GameTooltip:Show()
            end)
            r:Show()

            if expanded[g.owner] then
                for _, t in ipairs(g.tables) do
                    lines = lines + 1
                    local c = ListRow(cp.list, lines)
                    c.check:Show()
                    c.check:SetChecked(t.selected)
                    c.check:SetEnabled(ST.capture ~= nil and not t.huge)   -- too big to share
                    c.check:SetScript("OnClick", function(cb) ST:SetTableSelected(t.name, cb:GetChecked()); W:Refresh() end)
                    c.arrow:SetText("")
                    c.label:SetText("    " .. t.name)
                    Ink(c.label, "textDim")
                    c.right:SetText((t.huge and RED or GREY) .. ST.FormatSize(t.bytes) .. "|r")
                    c:SetScript("OnClick", nil)
                    c:SetScript("OnEnter", nil)
                    c:Show()
                end
            end
        end
    end
    FinishList(cp.list, lines, #groups == 0 and "Nothing found yet. Click \"Scan installed addons\" to start."
        or "No addon matches your search.")

    if ST.capture then
        cp.help:SetText("Tick the addons whose settings you want to share. Click an addon's name to pick individual parts. Big data like price history and caches is left out unless you tick it.")
    elseif #groups > 0 then
        cp.help:SetText(GREY .. "These are the results of your last scan, so ticking is paused. Scan again to change what's included and to save the newest settings.|r")
    else
        cp.help:SetText("Scan installed addons first to find which of them have settings you can share.")
    end
    cp.all:SetEnabled(ST.capture ~= nil)
    local TC = R.TwichConfig
    cp.summary:SetText(("%d addons ticked, about %s%s"):format(n, ST.FormatSize(bytes),
        (TC and TC.Included()) and "; and TwichUI's own settings" or ""))
end

function W:ShowChoose()
    if not cp then BuildChoose() end
    cp:Show()
    W:Refresh()
end

---------------------------------------------------------------------------
-- Popup: recommend addons to friends
---------------------------------------------------------------------------
local rc

local function BuildRecommend()
    rc = MakePopup("TwichUIRecommend", POPUP_W, 520, "Recommend addons to friends", 10, -10)
    rc.help = Text(rc, "GameFontHighlightSmall")
    rc.help:SetPoint("TOPLEFT", 16, -40)
    rc.help:SetWidth(POPUP_LIST_W)
    rc.help:SetText("Tick the addons you'd suggest your friends install. They get this list with your setup, with a download link for each one they're missing. Recommendations only name addons: their settings aren't included unless you chose them in Choose addons. Addons you've turned off start unticked.")

    rc.list = ListBox(rc, 290, POPUP_LIST_W)
    rc.list:SetPoint("TOPLEFT", 16, -102)
    rc.summary = Text(rc, "GameFontDisableSmall")
    rc.summary:SetPoint("TOPLEFT", rc.list, "BOTTOMLEFT", 2, -6)
    rc.none = Btn(rc, "None", 60, function()
        for _, g in ipairs(ST.InstalledAddons()) do ST:SetRecommended(g.key, false) end
        W:Refresh()
    end)
    rc.none:SetPoint("TOPRIGHT", rc.list, "BOTTOMRIGHT", 0, -2)
    rc.all = Btn(rc, "All", 60, function()
        for _, g in ipairs(ST.InstalledAddons()) do ST:SetRecommended(g.key, true) end
        W:Refresh()
    end)
    rc.all:SetPoint("RIGHT", rc.none, "LEFT", -6, 0)

    rc.update = Btn(rc, "Update my saved setup", 190, function()
        if ST:UpdateSavedAddonList() then
            R.Print("recommendations updated in your saved setup. Send it again to share the change.")
        end
        W:Refresh()
    end, function()
        return ST.Mine() and "Puts this list into your saved setup without touching its settings. Saving your setup also includes it."
            or "Save your setup first on the Share setup page; the list is included when you do."
    end)
    rc.update:SetPoint("TOPLEFT", rc.list, "BOTTOMLEFT", 0, -40)
    rc.status = Text(rc, "GameFontHighlightSmall")
    rc.status:SetPoint("LEFT", rc.update, "RIGHT", 12, 0)
    rc.status:SetWidth(POPUP_LIST_W - 210)
    rc.legend = Text(rc, "GameFontDisableSmall")
    rc.legend:SetPoint("BOTTOMLEFT", 16, 14)
    rc.legend:SetWidth(POPUP_LIST_W - 100)
    rc.legend:SetText("Where it comes from: CurseForge, Wago or WoWInterface when the addon says so; otherwise friends get a CurseForge search link.")
    rc.done = Btn(rc, "Done", 80, function() rc:Hide() end)
    rc.done:SetPoint("BOTTOMRIGHT", -16, 12)
end

local function RefreshRecommend()
    local groups = ST.InstalledAddons()
    local ticked = 0
    for i, g in ipairs(groups) do
        local r = ListRow(rc.list, i)
        local on = ST:IsRecommended(g)
        if on then ticked = ticked + 1 end
        r.check:Show()
        r.check:SetEnabled(true)
        r.check:SetChecked(on)
        r.check:SetScript("OnClick", function(c) ST:SetRecommended(g.key, c:GetChecked()); W:Refresh() end)
        r.arrow:SetText("")
        r.label:SetText(g.title)
        local c = g.enabled and 1 or 0.55
        Ink(r.label, "text", c)
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
    FinishList(rc.list, #groups, "No addons found.")
    rc.summary:SetText(("%d of %d addons recommended"):format(ticked, #groups))

    local mine = ST.Mine()
    rc.update:SetEnabled(mine ~= nil)
    if not mine then
        rc.status:SetText(GREY .. "Not saved yet. Save your setup on the Share setup page.|r")
    else
        local n = 0
        for _ in pairs(mine.addons or {}) do n = n + 1 end
        rc.status:SetText(("%sIn your saved setup:|r %d addons (version %d)"):format(GREY, n, mine.version or 1))
    end
end

function W:ShowRecommend()
    if not rc then BuildRecommend() end
    rc:Show()
    W:Refresh()
end

---------------------------------------------------------------------------
-- Popup: party compatibility check
---------------------------------------------------------------------------
local gp
local GROUP_STATE = {
    ok = GREEN .. "Up to date|r", ahead = GOLD .. "Newer than yours|r", behind = GOLD .. "Older than yours|r",
    old = RED .. "Too old to share with|r", none = GREY .. "No TwichUI detected|r", waiting = GREY .. "Asking...|r",
}

local function BuildParty()
    gp = MakePopup("TwichUIPartyCheck", POPUP_W, 540, "Party compatibility check", -10, 10)
    gp.help = Text(gp, "GameFontHighlightSmall")
    gp.help:SetPoint("TOPLEFT", 16, -40)
    gp.help:SetWidth(POPUP_LIST_W)
    gp.help:SetSpacing(2)
    gp.help:SetText(Head() .. "What it does|r\nShows which TwichUI version each person in your party or raid runs, and which of the addons you recommend they're missing. It only runs when you press Check this party.\n\n"
        .. Head() .. "What it sends|r\nYour TwichUI version and the names and folders of your recommended addons, over the hidden party or raid addon channel (no chat text). Each reply carries only that person's TwichUI version and which of those addons they lack.\n\n"
        .. Head() .. "What it needs|r\nEveryone must run TwichUI with \"Version and group check\" turned on. Once it's on, TwichUI also says hello with its version when you join a group, and may test once per game build whether direct messages work again.")
    gp.run = Btn(gp, "Check this party", 150, function() R.Group:RunCheck(true); W:Refresh() end, function()
        local why
        if not R:Enabled("groupCheck") then why = "Version and group check is turned off in the options."
        elseif not IsInGroup() then why = "Join a group first." end
        return "Asks the other TwichUI users in your group for their version, over the group channel only. Nobody else sees it.", why
    end)
    gp.run:SetPoint("TOPLEFT", 16, -222)
    gp.enable = Btn(gp, "Turn on group check", 170, function()
        R:SetEnabled("groupCheck", true, true)
        R.Group:SayHello()
        W:Refresh()
    end, "Lets TwichUI trade version numbers with other TwichUI users in your group (a few bytes, group channel only). Everyone who wants to show up here needs it on too. You can turn it off again in TwichUI's settings, on the Configuration sharing page.")
    gp.enable:SetPoint("TOPLEFT", 16, -222)
    gp.list = ListBox(gp, 210, POPUP_LIST_W)
    gp.list:SetPoint("TOPLEFT", 16, -254)
    gp.you = Text(gp, "GameFontHighlightSmall")
    gp.you:SetPoint("TOPLEFT", gp.list, "BOTTOMLEFT", 2, -8)
    gp.you:SetWidth(POPUP_LIST_W)
    gp.dm = Text(gp, "GameFontDisableSmall")
    gp.dm:SetPoint("TOPLEFT", gp.you, "BOTTOMLEFT", 0, -4)
    gp.dm:SetWidth(POPUP_LIST_W - 100)
    gp.done = Btn(gp, "Done", 80, function() gp:Hide() end)
    gp.done:SetPoint("BOTTOMRIGHT", -16, 12)
end

local function RefreshParty()
    local G = R.Group
    local rows = G:CheckRows()
    for i, r in ipairs(rows) do
        local row = ListRow(gp.list, i)
        row.check:Hide()
        row.arrow:SetText("")
        row.label:SetText(r.short .. (r.version and (GREY .. "   TwichUI " .. r.version .. "|r") or ""))
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
    if not R:Enabled("groupCheck") then empty = "Group check is off. Turn it on to see your party's TwichUI versions and missing addons; your friends need it on too."
    elseif not IsInGroup() then empty = "You're not in a group."
    elseif not G.check then empty = "Click \"Check this party\"." end
    if G.check or #rows == 0 then FinishList(gp.list, #rows, empty or "Nobody else is in your group.")
    else FinishList(gp.list, 0, empty or "") end
    gp.run:SetShown(R:Enabled("groupCheck"))
    gp.enable:SetShown(not R:Enabled("groupCheck"))
    gp.run:SetEnabled(R:Enabled("groupCheck") and IsInGroup())
    gp.you:SetText(("You: TwichUI %s"):format(G.Version()))
    gp.dm:SetText("Direct messages on Forever: " .. G.WhisperStatus())
end

function W:ShowParty()
    if not gp then BuildParty() end
    gp:Show()
    W:Refresh()
end

---------------------------------------------------------------------------
-- Page: Share setup
---------------------------------------------------------------------------
local mine = {}

local function BuildShare(p)
    mine.intro = Text(p, "GameFontHighlightSmall")
    mine.intro:SetPoint("TOPLEFT", 16, -4)
    mine.intro:SetWidth(WIDTH - 32)
    mine.intro:SetText("Send your selected addon settings and optional layout to a friend. They can review everything before applying it.")

    -- The three steps each sit on a card, as the settings window's sections do.
    local L = Look()
    L.Card(p, 8, -34, WIDTH - 8, -124)
    L.Card(p, 8, -130, WIDTH - 8, -252)
    L.Card(p, 8, -258, WIDTH - 8, -378)

    Section(p, "1", "Choose what to include", -40)
    mine.summary = Text(p, "GameFontHighlight")
    mine.summary:SetPoint("TOPLEFT", 16, -70)
    mine.choose = Btn(p, "Choose addons", 130, function() W:ShowChoose() end,
        "Pick which addons' settings go into your setup. You can search the list and open an addon to pick individual parts.")
    mine.choose:SetPoint("TOPRIGHT", -16, -62)
    mine.scan = Btn(p, "Scan installed addons", 170, AskScan,
        "Reloads your UI once and lists every addon that has saved settings. Scanning never saves or sends anything; it's needed before you can save a setup or create a backup.")
    mine.scan:SetPoint("RIGHT", mine.choose, "LEFT", -8, 0)
    mine.help = Text(p, "GameFontDisableSmall")
    mine.help:SetPoint("TOPLEFT", 16, -92)
    mine.help:SetWidth(WIDTH - 32)

    Section(p, "2", "Save", -136)
    mine.em = Check(p, "Include my Edit Mode layout")
    mine.em:SetPoint("TOPLEFT", 14, -162)
    mine.em:SetChecked(true)
    mine.eui = Btn(p, "EllesmereUI profile: none", 270, function() W:ShowEuiShare() end, function()
        local _, why = ES.Api()
        return why or "Choose one EllesmereUI profile to send with your setup. It reaches your friend as a new profile; nothing of theirs is replaced."
    end)
    mine.eui:SetPoint("TOPLEFT", 214, -158)
    mine.save = Btn(p, "Save setup", 150, function()
        ST:SaveMine(mine.em:GetChecked())
        local saved = ST.Mine()
        R.Print("saved your setup: %d addons%s%s.", ST.CountAddons(saved), saved.eui and ", an EllesmereUI profile" or "",
            saved.twichui and " and TwichUI's own settings" or "")
        if ST.euiError then R.Print("couldn't include the EllesmereUI profile: %s", ST.euiError) end
        W:Refresh()
    end, function()
        local TC = R.TwichConfig
        if ST:CanSave() then return "Saves the ticked settings as your setup. You can send it straight away." end
        if TC and TC.WillInclude() then
            return "Saves TwichUI's own settings (and the EllesmereUI profile, if you chose one) as they are now. The addon settings already in your saved setup stay as they were; scan first to bring those up to date."
        end
        return "Click \"Scan installed addons\" first. Saving uses the settings found in that scan."
    end)
    mine.save:SetPoint("TOPRIGHT", -16, -158)
    mine.saved = Text(p, "GameFontHighlightSmall")
    mine.saved:SetPoint("TOPLEFT", 16, -192)
    mine.saved:SetWidth(WIDTH - 260)
    mine.delete = Btn(p, "Delete", 70, function()
        Confirm("TWICHUI_DELETE_MINE", "Delete your saved setup?\n\nFriends keep the copy they already have. This can't be undone, but you can save a new one any time.", function()
            ST:DeleteMine(); W:Refresh()
        end, { accept = DELETE })
    end)
    mine.delete:SetPoint("TOPRIGHT", -16, -187)
    mine.review = Btn(p, "Review", 70, function()
        if R.ExplorerWindow then R.ExplorerWindow.Show("share:preview") end
    end, "Opens the Saved Data Explorer on exactly what Send sends from your saved setup: every message, what is in it, what is left out, and its size. Nothing is sent.")
    mine.review:SetPoint("RIGHT", mine.delete, "LEFT", -6, 0)
    mine.recommend = Btn(p, "Recommend addons to friends", 220, function() W:ShowRecommend() end,
        "Optional. Lists addons your friends may want to install, with download links. It doesn't include their settings.")
    mine.recommend:SetPoint("TOPLEFT", 16, -222)
    mine.recommendHelp = Text(p, "GameFontDisableSmall")
    mine.recommendHelp:SetPoint("LEFT", mine.recommend, "RIGHT", 12, 0)
    mine.recommendHelp:SetWidth(WIDTH - 280)
    mine.recommendHelp:SetText("Optional. Names addons to install; it doesn't include their settings.")

    Section(p, "3", "Send to a friend", -264)
    mine.name = Look().EditBox(p, 100, 24)
    mine.name:SetSize(230, 24)
    mine.name:SetPoint("TOPLEFT", 22, -294)
    mine.name:SetAutoFocus(false)
    mine.name:SetScript("OnEnterPressed", function() mine.send:Click() end)
    mine.name:SetScript("OnEscapePressed", mine.name.ClearFocus)
    mine.name:SetScript("OnTextChanged", function() W:Refresh() end)
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
    end, function()
        return "They get a prompt to accept. After the first time, only the addons you changed are sent again.", mine.sendWhy
    end)
    mine.send:SetPoint("LEFT", mine.target, "RIGHT", 8, 0)
    mine.cancel = Btn(p, "Stop", 70, function() SH:CancelSend() end)
    mine.cancel:SetPoint("LEFT", mine.send, "RIGHT", 8, 0)

    mine.bar = ProgressBar(p)
    mine.bar:SetPoint("TOPLEFT", 16, -330)
    mine.status = Text(p, "GameFontHighlightSmall")
    mine.status:SetPoint("TOPLEFT", mine.bar, "BOTTOMLEFT", 0, -6)
    mine.status:SetWidth(WIDTH - 32)

    -- Secondary tools, kept apart from the three-step path.
    local rule = p:CreateTexture(nil, "ARTWORK")
    local rc = Look().pal.bronzeLo
    rule:SetColorTexture(rc[1], rc[2], rc[3], 0.6)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 16, -396)
    rule:SetPoint("TOPRIGHT", -16, -396)
    mine.more = Text(p, "GameFontDisableSmall")
    mine.more:SetPoint("TOPLEFT", 16, -408)
    mine.more:SetText("More tools")
    mine.selfTest = Btn(p, "Test on myself", 130, function()
        local ok, why = SH:SendToSelf()
        if not ok then R.Print(why) end
        W:Refresh()
    end, function()
        return "A rehearsal, not a send to someone else: sends your setup to your own character through the real in-game channel, so you get the accept prompt, the progress bars and the received copy under Received setups, exactly like a friend would.", mine.testWhy
    end)
    mine.selfTest:SetPoint("TOPLEFT", 16, -428)
    mine.channels = Btn(p, "Sending options", 130, function() W:ShowChannels() end,
        "Choose how setups are sent: Direct to one character, over your Party, or over your Guild.")
    mine.channels:SetPoint("LEFT", mine.selfTest, "RIGHT", 8, 0)
    mine.party = Btn(p, "Party compatibility check", 200, function() W:ShowParty() end,
        "See which TwichUI version your party runs and which of your recommended addons they're missing. Only runs when you press Check this party.")
    mine.party:SetPoint("LEFT", mine.channels, "RIGHT", 8, 0)
    mine.moreHelp = Text(p, "GameFontDisableSmall")
    mine.moreHelp:SetPoint("TOPLEFT", mine.selfTest, "BOTTOMLEFT", 0, -8)
    mine.moreHelp:SetWidth(WIDTH - 32)
    mine.moreHelp:SetText("Test on myself sends the setup to your own character as a rehearsal. It doesn't go to anyone else.")
end

local function RefreshShare()
    local n, bytes, total = Chosen()
    local profile = ES.ChosenProfile()
    local TC = R.TwichConfig
    local twich = TC and TC.WillInclude()
    local what = {}
    if n > 0 then what[#what + 1] = ("%d %s · %s"):format(n, n == 1 and "addon" or "addons", ST.FormatSize(bytes)) end
    if profile then what[#what + 1] = "EllesmereUI profile" end
    if twich then what[#what + 1] = "TwichUI settings" end
    if #what == 0 then
        mine.summary:SetText(GREY .. "Included settings: nothing chosen yet|r")
    else
        mine.summary:SetText("Included settings: " .. table.concat(what, " · "))
    end
    mine.eui:SetText(profile and ("EllesmereUI profile: " .. profile:sub(1, 20)) or "EllesmereUI profile: none")
    mine.eui:SetEnabled(ES.Api() ~= nil)
    if ST.capture then
        mine.help:SetText("Scanned this session, so you can choose addons and save.")
    elseif total > 0 then
        mine.help:SetText("Showing the results of your last scan. Scan again before saving so the newest settings are used; scanning reloads your UI once and never saves on its own.")
    else
        mine.help:SetText("Start with Scan installed addons to find which of them have settings you can share. It reloads your UI once and never saves on its own.")
    end
    mine.save:SetEnabled((ST.capture ~= nil and (n > 0 or profile ~= nil or twich)) or (ST.capture == nil and twich and true or false))
    if twich and not ST.capture then
        mine.help:SetText(mine.help:GetText() .. " TwichUI's own settings need no scan.")
    end

    local m = ST.Mine()
    if m then
        mine.saved:SetText(("%sSaved|r %s  ·  version %d  ·  %d addons%s%s%s"):format(GREEN, When(m.created), m.version or 1,
            ST.CountAddons(m), m.eui and "  ·  EllesmereUI profile" or "",
            (type(m.twichui) == "table" and m.twichui.status == "ok") and "  ·  TwichUI settings" or "",
            m.editMode and "  ·  Edit Mode layout" or ""))
    else
        mine.saved:SetText(GREY .. "Not saved yet.|r")
    end
    mine.delete:SetShown(m ~= nil)
    mine.review:SetShown(m ~= nil)

    mine.hint:SetShown(mine.name:GetText() == "" and not mine.name:HasFocus())
    local o = SH.outgoing
    local busy = o and (o.stage == "offered" or o.stage == "packing" or o.stage == "sending" or o.stage == "delivered")
    mine.send:SetEnabled(m ~= nil and not busy and mine.name:GetText() ~= "")
    mine.selfTest:SetEnabled(m ~= nil and not busy)
    -- Why a button is dimmed, for its tooltip.
    mine.testWhy = (not m and "Save your setup first.") or (busy and ("Already sending to " .. SH.Short(o.target) .. ". Stop that first.")) or nil
    mine.sendWhy = mine.testWhy or (mine.name:GetText() == "" and "Type your friend's name first.") or nil
    R.Interact.RefreshTip(mine.send)
    R.Interact.RefreshTip(mine.selfTest)
    mine.cancel:SetShown(busy and true or false)
    mine.bar:SetShown(o ~= nil)
    if not o then
        local tip
        if not m then
            tip = "Save your setup first, then type your friend's name and press Send."
        else
            local t = SH.Transport()
            local name = SH.Realmless() and "their full name (first and last)" or "their name"
            if t == "PARTY" then
                tip = ("Sending by Party: they need to be in your group. Type %s and press Send."):format(name)
            elseif t == "GUILD" then
                tip = ("Sending by Guild: they need to be in your guild and online. Type %s and press Send."):format(name)
            else
                tip = ("Sending Direct: type %s and press Send. You both need to be online."):format(name)
            end
            tip = tip .. " Change this in Sending options."
        end
        mine.status:SetText(GREY .. tip .. "|r")
    else
        local who = SH.Short(o.target)
        if o.stage == "offered" then
            mine.bar:SetValue(0)
            mine.status:SetText(("Waiting for %s to accept..."):format(who))
        elseif o.stage == "packing" then
            mine.bar:SetValue(0)
            mine.status:SetText(("%s accepted. Packing your setup..."):format(who))
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
            mine.status:SetText(("%sDone.|r %s has your setup."):format(GREEN, who))
        elseif o.stage == "failed" then
            mine.bar:SetValue(0)
            mine.status:SetText(RED .. (o.reason or "That didn't work.") .. "|r")
        end
    end
end

---------------------------------------------------------------------------
-- Popup: addons a shared setup recommends
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
    ap:HookScript("OnShow", R.FitToScreen)
    tinsert(UISpecialFrames, "TwichUIAddonList")
    Look().Shell(ap, POPUP_HEADER)
    ap.title = Text(ap, "GameFontNormalLarge")
    ap.title:SetPoint("TOPLEFT", 16, -12)
    Look().CloseBox(ap)
    ap.sub = Text(ap, "GameFontHighlightSmall")
    ap.sub:SetPoint("TOPLEFT", 16, -38)
    ap.sub:SetWidth(528)

    -- list (own scroll box; rows get a Link button)
    local box = CreateFrame("Frame", nil, ap, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 16, -64)
    box:SetSize(528, 250)
    Look().Well(box, 0.9)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    Look().ScrollBar(scroll)
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
    Look().Well(copyBox, 0.9)
    local cs = CreateFrame("ScrollFrame", nil, copyBox, "UIPanelScrollFrameTemplate")
    cs:SetPoint("TOPLEFT", 6, -6)
    cs:SetPoint("BOTTOMRIGHT", -26, 6)
    Look().ScrollBar(cs)
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
    R.Interact.TipTruncated(r, r.title, function(row) return row.fullTitle end)   -- a title from another player's list
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
        r.fullTitle = e.title
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
-- Popup: which EllesmereUI profile to share (one at a time, never the whole database)
---------------------------------------------------------------------------
local ep

local function BuildEuiShare()
    ep = MakePopup("TwichUIEuiShare", POPUP_W, 440, "Share an EllesmereUI profile", 20, 0)
    ep.help = Text(ep, "GameFontHighlightSmall")
    ep.help:SetPoint("TOPLEFT", 16, -40)
    ep.help:SetWidth(POPUP_LIST_W)
    ep.help:SetSpacing(2)
    ep.help:SetText("Pick one of your EllesmereUI profiles to include when you press Save setup. TwichUI asks EllesmereUI to export it, so your friend's EllesmereUI reads it like any of its own exports. It reaches them as a new profile; nothing of theirs is replaced.\n\n"
        .. Head() .. "Included|r  The profile's module settings, look (fonts, custom colours, dark mode, accent), layout links, Cooldown Manager spells and overrides.\n"
        .. Head() .. "Left out|r  UI scale, window and tooltip skins, which specs use a profile, click-cast, your other profiles, and your characters' names and gold.")
    ep.list = ListBox(ep, 190, POPUP_LIST_W)
    ep.list:SetPoint("TOPLEFT", 16, -176)
    ep.note = Text(ep, "GameFontDisableSmall")
    ep.note:SetPoint("TOPLEFT", ep.list, "BOTTOMLEFT", 2, -8)
    ep.note:SetWidth(POPUP_LIST_W - 100)
    ep.done = Btn(ep, "Done", 80, function() ep:Hide() end)
    ep.done:SetPoint("BOTTOMRIGHT", -16, 12)
end

local function RefreshEuiShare()
    local E, why = ES.Api()
    local names = ES.ProfileNames()
    local chosen = ES.ChosenProfile()
    local active = E and E.GetActiveProfileName()
    local lines = 0
    local function Row(label, value, right)
        lines = lines + 1
        local r = ListRow(ep.list, lines)
        local function pick() ES.Choose(value); W:Refresh() end
        r.check:Show()
        r.check:SetChecked(chosen == value)
        r.check:SetScript("OnClick", pick)
        r:SetScript("OnClick", pick)
        r:SetScript("OnEnter", nil)
        r.arrow:SetText("")
        r.label:SetText(label)
        r.right:SetText(right or "")
        r:Show()
    end
    if E and #names > 0 then
        Row("Don't share a profile", nil, nil)
        for _, n in ipairs(names) do Row(n, n, n == active and (GREY .. "in use|r") or nil) end
    end
    FinishList(ep.list, lines, why or "EllesmereUI has no profiles to share.")
    ep.note:SetText(chosen and ("Included the next time you press Save setup: \"" .. chosen .. "\".")
        or "No profile chosen. Your setup is saved without one.")
end

function W:ShowEuiShare()
    if not ep then BuildEuiShare() end
    ep:Show()
    W:Refresh()
end

---------------------------------------------------------------------------
-- Popup: import a friend's EllesmereUI profile (always as a new profile)
---------------------------------------------------------------------------
local ip

local function EuiModules(plan)
    local names = {}
    for _, m in ipairs(plan.modules or {}) do
        names[#names + 1] = m.display .. (m.missing and (GREY .. " (not installed here)|r") or "")
    end
    local more = {}
    if plan.look then more[#more + 1] = "look (fonts, colours, dark mode, accent)" end
    if plan.layout then more[#more + 1] = "layout links" end
    if plan.cdm then more[#more + 1] = "Cooldown Manager spells" end
    if plan.overrides then more[#more + 1] = "overrides" end
    local out = table.concat(names, ", ")
    if #more > 0 then out = out .. "  ·  " .. table.concat(more, ", ") end
    return out
end

local function EuiBody(plan)
    if not plan.ok then return RED .. (plan.why or "Nothing to import.") .. "|r" end
    local lines = {
        ("%sFrom|r  %s's profile \"%s\""):format(Head(), plan.from, plan.sourceName),
        ("%sCreates|r  a new profile named \"%s\". Your existing profiles are not changed, replaced or renamed."):format(Head(), plan.dest),
        ("%sIncluded|r  %s"):format(Head(), EuiModules(plan)),
        ("%sLeft out|r  %s"):format(Head(), plan.excluded),
        ("%sIn use afterwards|r  EllesmereUI has no import that doesn't switch to the new profile, so it becomes the one in use. \"%s\" stays saved exactly as it is; switch back any time in EllesmereUI > Profiles. If this spec has its own assigned profile, the new one is saved but not switched to. Spec assignments are never changed."):format(Head(), plan.active or "?"),
    }
    if plan.previous and #plan.previous > 0 then
        lines[#lines + 1] = ("%sImported before|r  TwichUI recorded an earlier import of this profile as \"%s\". It isn't touched; this makes a separate copy. Delete the one you don't want in EllesmereUI > Profiles."):format(Head(), plan.previous[1].dest)
    end
    for _, n in ipairs(plan.notes) do lines[#lines + 1] = GREY .. n .. "|r" end
    lines[#lines + 1] = GREY .. ("Your UI reloads when it's done. EllesmereUI %s here%s."):format(plan.version or "?",
        plan.euiVersion and (", " .. plan.euiVersion .. " when it was shared") or "") .. "|r"
    return table.concat(lines, "\n\n")
end

local function BuildEuiImport()
    ip = MakePopup("TwichUIEuiImport", POPUP_W, 540, "Import an EllesmereUI profile", -20, 0)
    ip.body = Text(ip, "GameFontHighlightSmall")
    ip.body:SetPoint("TOPLEFT", 16, -40)
    ip.body:SetWidth(POPUP_LIST_W)
    ip.body:SetJustifyV("TOP")
    ip.body:SetSpacing(2)
    ip.result = Text(ip, "GameFontHighlightSmall")
    ip.result:SetPoint("BOTTOMLEFT", 16, 50)
    ip.result:SetWidth(POPUP_LIST_W)
    ip.go = Btn(ip, "Import as a new profile", 200, function()
        local plan, pack = ip.plan, ST.SourcePack(ip.sourceKey)
        if not (plan and plan.ok and pack) or not NoCombat() then return end
        local text = ("Import %s's profile \"%s\" as a new EllesmereUI profile named \"%s\" and switch to it?\n\n\"%s\" and your other profiles stay as they are. Your UI reloads."):format(
            plan.from, plan.sourceName, plan.dest, plan.active or "?")
        Confirm("TWICHUI_EUI_IMPORT", text, function()
            local ok, report = ES.Apply(pack, plan.from, plan.dest)
            if not ok then
                ip.failed = report
                R.Print("%s", report)
                W:Refresh()
                return
            end
            ReloadUI()
        end, {
            combat = true,
            valid = function()
                if ST.SourcePack(ip.sourceKey) ~= pack then return false, "That setup is no longer here, so nothing was imported." end
                return true
            end,
        })
    end, "Adds the profile to EllesmereUI under the name shown, then reloads. Nothing you have is replaced.")
    ip.go:SetPoint("BOTTOMLEFT", 16, 12)
    ip.close = Btn(ip, "Close", 80, function() ip:Hide() end)
    ip.close:SetPoint("BOTTOMRIGHT", -16, 12)
    ip:SetScript("OnHide", function() ip.failed = false; ES.ReleaseCache() end)
end

local function RefreshEuiImport()
    local pack = ST.SourcePack(ip.sourceKey)
    local plan = pack and ES.Plan(pack, ip.from) or { why = "That setup is no longer here.", notes = {} }
    ip.plan = plan
    ip.body:SetText(EuiBody(plan))
    ip.result:SetText(ip.failed and (RED .. ip.failed .. "|r") or "")
    ip.go:SetEnabled(plan.ok and true or false)
end

function W:ShowEuiImport(src)
    if not ip then BuildEuiImport() end
    ip.sourceKey, ip.from, ip.failed = src.key, src.from, false
    ip:Show()
    W:Refresh()
end

---------------------------------------------------------------------------
-- Popup: TwichUI's own settings from a friend's setup (setup/TwichConfig.lua)
-- Reviewed by feature, applied to the profile in use or to a new copy of it, one Undo.
---------------------------------------------------------------------------
local tw
local twSel = {}                 -- [sourceKey] = { [groupId] = false } for the features left unticked

local STATE_WORD = {
    same = GREY .. "no change|r", invalid = RED .. "can't be used|r", unavailable = GREY .. "not available here|r",
}

local function TwichBody(plan, from)
    if not plan.ok then return RED .. (plan.why or "Nothing to import.") .. "|r" end
    local TC = R.TwichConfig
    local lines = {}
    lines[#lines + 1] = ("%sFrom|r  %s's TwichUI settings%s%s"):format(Head(), from or "?",
        plan.addon and (", made with TwichUI " .. plan.addon) or "", plan.made and (", " .. When(plan.made)) or "")
    local scope = plan.profile and ("%sApplies to|r  your profile \"%s\""):format(Head(), plan.profile) or (Head() .. "Applies to|r  your profile in use")
    if plan.sharedWith and plan.sharedWith > 0 then
        scope = scope .. (", which %d other %s also use%s: they would see these changes too. \"Apply to a new profile\" leaves it alone."):format(
            plan.sharedWith, plan.sharedWith == 1 and "character" or "characters", plan.sharedWith == 1 and "s" or "")
    else
        scope = scope .. "."
    end
    lines[#lines + 1] = scope
    lines[#lines + 1] = ("%sReplaces|r  only the values listed for each ticked feature (hover one to see them, yours first, then theirs). Every other setting in the profile keeps its value."):format(Head())
    local account = false
    for _, g in ipairs(plan.groups) do
        if g.selected and g.state == "changed" then
            for _, c in ipairs(g.changes) do if c.scope == "account" then account = true end end
        end
    end
    if account then
        lines[#lines + 1] = ("%sEvery profile|r  stat weights (kept by class and talent tree) and the settings window's motion setting are account-wide: they change for all your profiles."):format(Head())
    end
    lines[#lines + 1] = ("%sStays yours|r  selling and anything that acts for you, what you send or accept, where windows sit, RestedXP's on/off switch, your Journey Chronicle, pins and backups."):format(Head())
    if plan.absent and #plan.absent > 0 then
        lines[#lines + 1] = GREY .. ("Not in this share: %s."):format(table.concat(plan.absent, ", ")) .. "|r"
    end
    if plan.unknown and plan.unknown > 0 then
        lines[#lines + 1] = GREY .. ("%d %s from a newer TwichUI ignored."):format(plan.unknown, plan.unknown == 1 and "setting" or "settings") .. "|r"
    end
    if (plan.turnsOn and #plan.turnsOn > 0) or (plan.turnsOff and #plan.turnsOff > 0) then
        local parts = {}
        if #plan.turnsOn > 0 then parts[#parts + 1] = "turns on " .. table.concat(plan.turnsOn, ", ") end
        if #plan.turnsOff > 0 then parts[#parts + 1] = "turns off " .. table.concat(plan.turnsOff, ", ") end
        lines[#lines + 1] = ("%sFeatures|r  this %s."):format(GOLD, table.concat(parts, " and "))
    end
    if #plan.reload > 0 then
        lines[#lines + 1] = ("%sNeeds a reload|r  %s take effect after reloading your UI. Nothing else does, and nothing reloads by itself."):format(GOLD, table.concat(plan.reload, ", "))
    end
    lines[#lines + 1] = GREY .. "Nothing changes until you confirm. The values this replaces are kept, so Undo can put them back; Undo keeps only the last import." .. "|r"
    return table.concat(lines, "\n\n")
end

local function TwichSelection()
    twSel[tw.sourceKey] = twSel[tw.sourceKey] or {}
    return twSel[tw.sourceKey]
end

local function TwichApply(newProfile)
    local TC = R.TwichConfig
    local plan, pack = tw.plan, ST.SourcePack(tw.sourceKey)
    if not (plan and plan.ok and pack and pack.twichui) or not NoCombat() then return end
    if plan.changed == 0 then R.Print("nothing to change.") return end
    local stamp, entry, from = pack.created, pack.twichui, tw.from
    local sel = TwichSelection()
    local where
    if newProfile then
        where = ("a new profile named \"%s\", a copy of \"%s\"; this character switches to it. \"%s\" stays exactly as it is"):format(
            TC.NewProfileName(from) or "?", plan.profile or "?", plan.profile or "?")
    else
        where = ("your profile \"%s\"%s"):format(plan.profile or "?",
            plan.sharedWith > 0 and (" (also used by %d other %s)"):format(plan.sharedWith, plan.sharedWith == 1 and "character" or "characters") or "")
    end
    local account = false
    for _, g in ipairs(plan.groups) do
        if g.selected and g.state == "changed" then
            for _, c in ipairs(g.changes) do if c.scope == "account" then account = true end end
        end
    end
    local features = {}
    if #plan.turnsOn > 0 then features[#features + 1] = "Turns on: " .. table.concat(plan.turnsOn, ", ") .. "." end
    if #plan.turnsOff > 0 then features[#features + 1] = "Turns off: " .. table.concat(plan.turnsOff, ", ") .. "." end
    local reviewed = TC.PlanKey(plan)   -- the review this approval is for: refused if it is not true any more
    local text = ("Apply %d %s from %s's TwichUI settings to %s?\n\n%s%s%s\n\nThe values this replaces are kept so Undo can put them back (it keeps only the last import)."):format(plan.changed,
        plan.changed == 1 and "setting" or "settings", from, where,
        #features > 0 and (table.concat(features, " ") .. "\n\n") or "",
        #plan.reload > 0 and ("Reload needed afterwards for: " .. table.concat(plan.reload, ", ") .. ". Nothing reloads by itself.") or "No reload is needed.",
        account and "\n\nStat weights and the window-motion setting are account-wide: they change for every profile." or "")
    Confirm("TWICHUI_TWICH_APPLY", text, function()
        local ok, report, extra = TC.Apply(entry, { selection = sel, from = from, newProfile = newProfile, expect = reviewed })
        if not ok then
            tw.failed = TC.Explain(report, extra)
            R.Print("%s", tw.failed)
            W:Refresh()
            return
        end
        tw.failed, tw.report = false, report
        R.Print("%s's TwichUI settings applied: %d changed in profile \"%s\".%s", from, report.changed, report.profile or "?",
            #report.reload > 0 and (" Reload your UI for: " .. table.concat(report.reload, ", ") .. ".") or "")
        if #report.failed > 0 then
            R.Print("%s didn't update; see /tui diagnostics.", table.concat(report.failed, ", "))
        end
        W:Refresh()
    end, {
        combat = true,
        valid = function()
            local now = ST.SourcePack(tw.sourceKey)
            if not now or now.created ~= stamp or now.twichui ~= entry then
                return false, "That setup was replaced or removed while you were deciding, so nothing was applied. Review it again."
            end
            return true
        end,
    })
end

local function BuildTwichImport()
    tw = MakePopup("TwichUITwichImport", POPUP_W, 600, "TwichUI settings from a friend", 0, 0)
    tw.body = Text(tw, "GameFontHighlightSmall")
    tw.body:SetPoint("TOPLEFT", 16, -40)
    tw.body:SetWidth(POPUP_LIST_W)
    tw.body:SetJustifyV("TOP")
    tw.body:SetSpacing(2)
    tw.list = ListBox(tw, 150, POPUP_LIST_W)
    tw.list:SetPoint("BOTTOMLEFT", 16, 92)
    tw.result = Text(tw, "GameFontHighlightSmall")
    tw.result:SetPoint("BOTTOMLEFT", 16, 66)
    tw.result:SetWidth(POPUP_LIST_W)
    tw.go = Btn(tw, "Apply to this profile", 190, function() TwichApply(false) end,
        "Changes the profile you are using now: the ticked features take the shared values. Asks first; Undo puts them back.")
    tw.go:SetPoint("BOTTOMLEFT", 16, 12)
    tw.copy = Btn(tw, "Apply to a new profile", 190, function() TwichApply(true) end,
        "Makes a copy of your profile, switches this character to it, and applies the shared values there. Your current profile stays exactly as it is.")
    tw.copy:SetPoint("LEFT", tw.go, "RIGHT", 8, 0)
    tw.undo = Btn(tw, "Undo last import", 140, function()
        if not NoCombat() then return end
        local info = R.TwichConfig.UndoInfo()
        if not info then return end
        Confirm("TWICHUI_TWICH_UNDO", ("Put back the %d TwichUI %s the last import replaced%s?\n\nWhat they are now is replaced and not kept."):format(
            info.count, info.count == 1 and "setting" or "settings", info.from and (" (from " .. info.from .. ")") or ""),
            function()
                local ok, report, extra = R.TwichConfig.Undo()
                if ok then
                    tw.failed = false
                    R.Print("put back %d TwichUI settings.%s", report.restored, report.reloadPending and " Some take effect after a reload." or "")
                else
                    tw.failed = R.TwichConfig.Explain(report, extra)
                    if report == "profile" then
                        tw.failed = ("That import changed the profile \"%s\". Switch to it (Profiles) to undo it."):format(tostring(extra))
                    end
                    R.Print("%s", tw.failed)
                end
                W:Refresh()
            end, { combat = true })
    end, "Puts back what the last import of TwichUI settings replaced.")
    tw.undo:SetPoint("LEFT", tw.copy, "RIGHT", 8, 0)
    tw.close = Btn(tw, "Close", 80, function() tw:Hide() end)
    tw.close:SetPoint("BOTTOMRIGHT", -16, 12)
    tw:SetScript("OnHide", function() tw.failed, tw.report = false, nil end)
end

local function RefreshTwichImport()
    local TC = R.TwichConfig
    local pack = ST.SourcePack(tw.sourceKey)
    local plan
    if pack and pack.twichui then
        plan = TC.Plan(pack.twichui, { selection = TwichSelection() })
    else
        plan = { why = "That setup is no longer here.", groups = {}, reload = {}, absent = {} }
    end
    tw.plan = plan
    tw.body:SetText(TwichBody(plan, tw.from))
    local sel = TwichSelection()
    local lines = 0
    for _, g in ipairs(plan.groups) do
        lines = lines + 1
        local r = ListRow(tw.list, lines)
        local usable = g.state == "changed" or g.state == "same"
        r.check:Show()
        r.check:SetChecked(usable and sel[g.id] ~= false)
        r.check:SetEnabled(g.state == "changed")
        r.check:SetScript("OnClick", function(c) sel[g.id] = c:GetChecked() and nil or false; W:Refresh() end)
        r.arrow:SetText("")
        r.label:SetText(g.label .. (g.scope == "account" and (GREY .. "  (every profile)|r") or ""))
        Ink(r.label, "text", usable and 1 or 0.55)
        if g.state == "changed" then
            r.right:SetText(("%d %s"):format(#g.changes, #g.changes == 1 and "change" or "changes"))
        else
            r.right:SetText(STATE_WORD[g.state] or "")
        end
        r:SetScript("OnClick", nil)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(g.label, 1, 1, 1)
            if g.note then GameTooltip:AddLine(g.note, 0.9, 0.8, 0.5, true) end
            if g.state == "invalid" then
                GameTooltip:AddLine("This feature holds values this version can't use, so none of it is applied.", 0.9, 0.5, 0.4, true)
            elseif g.state == "unavailable" then
                GameTooltip:AddLine("This feature isn't loaded here.", 0.7, 0.7, 0.7, true)
            elseif g.state == "same" then
                GameTooltip:AddLine("Already the same as yours.", 0.7, 0.7, 0.7, true)
            else
                for i, c in ipairs(g.changes) do
                    if i > 14 then GameTooltip:AddLine(("... and %d more"):format(#g.changes - 14), 0.7, 0.7, 0.7) break end
                    GameTooltip:AddDoubleLine(c.label .. (c.reload and " (reload)" or ""), ("%s > %s"):format(c.old, c.new), 1, 1, 1, 0.7, 0.8, 0.6)
                end
            end
            GameTooltip:Show()
        end)
        r:Show()
    end
    FinishList(tw.list, lines, "")
    local info = TC.UndoInfo()
    tw.undo:SetShown(info ~= nil)
    local count = 0
    for _, g in ipairs(plan.groups) do if g.selected and g.state == "changed" then count = count + #g.changes end end
    plan.changed = count
    local can = plan.ok and count > 0 and plan.profilesAvailable
    tw.go:SetEnabled(can and true or false)
    tw.copy:SetEnabled(can and true or false)
    if tw.failed then
        tw.result:SetText(RED .. tw.failed .. "|r")
    elseif tw.report then
        tw.result:SetText(GREEN .. ("Applied: %d changed in \"%s\"."):format(tw.report.changed, tw.report.profile or "?") .. "|r")
    elseif plan.ok and not plan.profilesAvailable then
        tw.result:SetText(GREY .. "Profiles aren't available this session, so nothing can be applied now." .. "|r")
    elseif plan.ok and count == 0 then
        tw.result:SetText(GREY .. "Nothing ticked would change anything." .. "|r")
    else
        tw.result:SetText("")
    end
end

function W:ShowTwichImport(src)
    if not tw then BuildTwichImport() end
    tw.sourceKey, tw.from, tw.failed, tw.report = src.key, src.from, false, nil
    tw:Show()
    W:Refresh()
end

---------------------------------------------------------------------------
-- Page: Received setups
---------------------------------------------------------------------------
local get = {}
local reviewing = false          -- summary card (false) or the review step (true)

local STATE_TEXT = { ready = GREEN .. "Ready|r", missing = RED .. "Not installed|r", disabled = GOLD .. "Turned off|r", unknown = GREY .. "?|r" }
local EFFECT_TEXT = { replace = "Replaces yours", new = GREEN .. "New|r" }

local function CurrentSource()
    local sources = ST.Sources()
    if #sources == 0 then return nil, sources end
    if sourceIndex > #sources then sourceIndex = 1 end
    return sources[sourceIndex], sources
end

-- For a confirmation: still the same setup that was on screen when the question was asked?
-- A friend's newer copy may have arrived, or it may have been deleted, while the question was open.
local function SameSetup(src)
    local stamp = src.pack and src.pack.created
    return function()
        local pack = ST.SourcePack(src.key)
        if not pack then return false, "That setup is no longer here, so nothing was applied." end
        if pack.created ~= stamp then return false, "That setup was replaced by a newer one while you were deciding, so nothing was applied. Review it again." end
        return true
    end
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

-- What applying the ticked addons would change, in a sentence or two (used on
-- the page and in the confirmation). Returns nil when nothing is ticked.
local function Preview(src)
    local sel = getSel[src.key] or {}
    local titles, replace, new = {}, 0, 0
    for _, g in ipairs(ST.PackByAddon(src.pack)) do
        if sel[g.owner] ~= false and g.state ~= "missing" then
            titles[#titles + 1] = g.title
            if ST.ApplyEffect(g) == "new" then new = new + 1 else replace = replace + 1 end
        end
    end
    if #titles == 0 then return nil end
    local function Addons(n) return n == 1 and "1 addon" or (n .. " addons") end
    local what
    if replace > 0 and new > 0 then
        what = ("Replaces your settings for %s and adds settings for %s"):format(Addons(replace), Addons(new))
    elseif new > 0 then
        what = "Adds settings for " .. Addons(new)
    else
        what = "Replaces your settings for " .. Addons(replace)
    end
    local list = table.concat(titles, ", ", 1, math.min(#titles, 4))
    if #titles > 4 then list = list .. (" and %d more"):format(#titles - 4) end
    return ("%s: %s. TwichUI changes nothing else: not its own options, your game settings or any other addon. What you have now is backed up first, so Undo can put it back."):format(what, list)
end

local function AskUndo()
    if not NoCombat() then return end
    local RS = R.Restore
    local addons, own = RS.UndoPlan()
    local parts = {}
    if addons then
        local count = #ST:BackupNames()
        parts[#parts + 1] = ("the addon settings you had on this character before the last apply or restore (%d %s)"):format(count, count == 1 and "addon" or "addons")
    end
    if own then
        local u = RS.OwnUndo()
        parts[#parts + 1] = ("TwichUI's own settings from before you restored %s"):format(u and u.from and ("\"" .. u.from .. "\"") or "a backup")
    end
    if #parts == 0 then R.Print("there is nothing left to put back.") return end
    Confirm("TWICHUI_UNDO", ("Put back %s? What you have now for them is replaced and not kept. Your UI reloads."):format(table.concat(parts, ", and ")),
        function()
            local ok, why = RS:UndoLast()
            if not ok then R.Print("%s", why) end
        end, {
            combat = true,
            valid = function()
                if not RS.CanUndo() then return false, "There is nothing left to put back, so nothing was changed." end
                return true
            end,
        })
end

local function OpenRecommended()
    local src = CurrentSource()
    if src then W:ShowAddonList(src.key) end
end

local function Shown(list, on)
    for _, w in ipairs(list) do w:SetShown(on) end
end

local function BuildGet(p)
    get.incoming = Text(p, "GameFontHighlightSmall")
    get.incoming:SetPoint("TOPLEFT", 16, -4)
    get.incoming:SetWidth(WIDTH - 32)
    get.bar = ProgressBar(p)
    get.bar:SetPoint("TOPLEFT", 16, -24)

    -- Empty state
    get.emptyTitle = Text(p, "GameFontNormalLarge")
    get.emptyTitle:SetPoint("CENTER", 0, 40)
    get.emptyTitle:SetWidth(460)
    get.emptyTitle:SetJustifyH("CENTER")
    get.emptyTitle:SetText("No setups received")
    get.emptySub = Text(p, "GameFontDisable")
    get.emptySub:SetPoint("TOP", get.emptyTitle, "BOTTOM", 0, -10)
    get.emptySub:SetWidth(460)
    get.emptySub:SetJustifyH("CENTER")
    get.emptySub:SetText("When a friend sends you a TwichUI setup, it will appear here. You can review it before anything is applied.")
    get.emptyW = { get.emptyTitle, get.emptySub }

    -- Card (both states)
    get.title = Text(p, "GameFontNormalLarge")
    get.title:SetPoint("TOPLEFT", 16, -52)
    get.sub = Text(p, "GameFontHighlightSmall")
    get.sub:SetPoint("TOPLEFT", get.title, "BOTTOMLEFT", 0, -4)
    get.sub:SetWidth(WIDTH - 330)
    get.prev = Btn(p, "<", 28, function() sourceIndex = sourceIndex - 1; if sourceIndex < 1 then sourceIndex = #ST.Sources() end; reviewing = false; W:Refresh() end)
    get.next = Btn(p, ">", 28, function() sourceIndex = sourceIndex + 1; reviewing = false; W:Refresh() end)
    get.remove = Btn(p, "Delete", 80, function()
        local src = CurrentSource()
        if src and src.key ~= "file" then
            Confirm("TWICHUI_REMOVE", ("Delete the setup from %s?\n\nSettings you already applied stay. This can't be undone, but they can send it again if you want it back."):format(src.from), function()
                ST:RemoveReceived(src.key:match("^recv:(.+)$")); sourceIndex = 1; reviewing = false; W:Refresh()
            end, { accept = DELETE })
        end
    end, "Removes this received setup from your saved data. Settings you already applied stay.")
    get.remove:SetPoint("TOPRIGHT", -16, -52)
    get.next:SetPoint("RIGHT", get.remove, "LEFT", -8, 0)
    get.prev:SetPoint("RIGHT", get.next, "LEFT", -4, 0)
    get.back = Btn(p, "Back", 80, function() reviewing = false; W:Refresh() end, "Back to the summary. Nothing has been applied.")
    get.back:SetPoint("TOPRIGHT", -172, -52)

    -- Summary state
    get.includes = Text(p, "GameFontHighlightSmall")
    get.includes:SetPoint("TOPLEFT", 16, -118)
    get.includes:SetWidth(WIDTH - 32)
    get.lead = Text(p, "GameFontDisableSmall")
    get.lead:SetPoint("TOPLEFT", 16, -176)
    get.lead:SetWidth(WIDTH - 32)
    get.lead:SetText("Review shows exactly which of your settings would be replaced or added, and lets you leave addons out. Nothing is applied until you confirm.")
    get.review = Btn(p, "Review setup", 170, function() reviewing = true; W:Refresh() end,
        "See what applying would change before anything happens.")
    get.review:SetPoint("TOPLEFT", 16, -216)
    get.addonsBtn = Btn(p, "Recommended addons", 210, OpenRecommended,
        "The addons your friend uses, with download links for the ones you don't have yet.")
    get.addonsBtn:SetPoint("LEFT", get.review, "RIGHT", 8, 0)
    get.undo = Btn(p, "Undo last change", 150, AskUndo,
        "Restores what you had on this character before you last applied a setup or restored a backup.")
    get.undo:SetPoint("LEFT", get.addonsBtn, "RIGHT", 8, 0)
    get.sumW = { get.includes, get.lead, get.review, get.addonsBtn, get.undo }
    local function OpenEuiImport()
        local src = CurrentSource()
        if src then W:ShowEuiImport(src) end
    end
    get.eui = Btn(p, "EllesmereUI profile...", 190, OpenEuiImport,
        "See the EllesmereUI profile in this setup. It is only ever added as a new profile; nothing you have is replaced.")
    get.eui:SetPoint("TOPLEFT", 16, -248)
    local function OpenTwichImport()
        local src = CurrentSource()
        if src then W:ShowTwichImport(src) end
    end
    get.twich = Btn(p, "TwichUI settings...", 190, OpenTwichImport,
        "See TwichUI's own settings in this setup, by feature. You choose what to apply, and Undo puts back what it replaced.")
    get.twich:SetPoint("TOPLEFT", 214, -248)

    -- Review state
    get.list = ListBox(p, 200)
    get.list:SetPoint("TOPLEFT", 16, -92)
    get.missing = Text(p, "GameFontHighlightSmall")
    get.missing:SetPoint("TOPLEFT", get.list, "BOTTOMLEFT", 2, -6)
    get.missing:SetWidth(WIDTH - 36)
    get.preview = Text(p, "GameFontHighlightSmall")
    get.preview:SetPoint("TOPLEFT", 16, -334)
    get.preview:SetWidth(WIDTH - 32)

    get.apply = Btn(p, "Apply to this character", 170, function()
        local src = CurrentSource(); if not src or not NoCombat() then return end
        local names = SelectedNames(src)
        local preview = Preview(src)
        if #names == 0 or not preview then R.Print("nothing ticked.") return end
        local text = ("Apply %s's setup to this character?\n\n%s\n\nYour UI reloads."):format(src.from, preview)
        Confirm("TWICHUI_APPLY", text, function() ST:Queue("apply", names, src.key) end, { combat = true, valid = SameSetup(src) })
    end, "Replaces your settings for the ticked addons with this setup. You see what changes and confirm first; your current settings are backed up.")
    get.apply:SetPoint("TOPLEFT", 16, -392)
    get.addonsBtnR = Btn(p, "Recommended addons", 210, OpenRecommended,
        "The addons your friend uses, with download links for the ones you don't have yet.")
    get.addonsBtnR:SetPoint("LEFT", get.apply, "RIGHT", 8, 0)
    get.em = Btn(p, "Edit Mode layout", 130, function() W:ShowEditMode() end,
        "Shows the layout text. Copy it, open Edit Mode, and use Import in the layout menu.")
    get.em:SetPoint("LEFT", get.addonsBtnR, "RIGHT", 8, 0)
    get.alt = Btn(p, "Use profiles already applied on another character", 340, function()
        local src = CurrentSource(); if not src or not NoCombat() then return end
        Confirm("TWICHUI_ALT", ("Switch this character to the profiles from %s's setup? Nothing is copied again; this character just uses the same profiles. This isn't backed up, so Undo can't reverse it. Your UI reloads."):format(src.from),
            function() ST:Queue("alt", SelectedNames(src), src.key) end, { combat = true, valid = SameSetup(src) })
    end, "Already applied this setup on another of your characters? This points this character at the same profiles without copying anything.")
    get.alt:SetPoint("TOPLEFT", 16, -424)
    get.undoR = Btn(p, "Undo last change", 150, AskUndo,
        "Restores what you had on this character before you last applied a setup or restored a backup.")
    get.undoR:SetPoint("LEFT", get.alt, "RIGHT", 8, 0)
    get.revW = { get.list, get.missing, get.preview, get.apply, get.addonsBtnR, get.em, get.alt, get.undoR, get.back }

    get.euiR = Btn(p, "EllesmereUI profile...", 190, OpenEuiImport,
        "See the EllesmereUI profile in this setup. It is only ever added as a new profile; nothing you have is replaced.")
    get.euiR:SetPoint("TOPLEFT", 16, -490)
    get.twichR = Btn(p, "TwichUI settings...", 190, OpenTwichImport,
        "See TwichUI's own settings in this setup, by feature. You choose what to apply, and Undo puts back what it replaced.")
    get.twichR:SetPoint("TOPLEFT", 214, -490)
    get.report = Text(p, "GameFontHighlightSmall")
    get.report:SetPoint("TOPLEFT", 16, -458)
    get.report:SetWidth(WIDTH - 32)

    get.trusted = Text(p, "GameFontDisableSmall")
    get.trusted:SetPoint("BOTTOMLEFT", 16, 10)
    get.trusted:SetWidth(WIDTH - 140)
    get.clearTrust = Btn(p, "Clear", 70, function() wipe(ST.db.trusted); W:Refresh() end,
        "Ask again before accepting a setup from anyone.")
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
            get.incoming:SetText(("%s wants to share their setup with you. Answer the prompt."):format(who))
        elseif inc.stage == "waiting" then
            get.bar:SetValue(0)
            get.incoming:SetText(("Getting ready to receive from %s..."):format(who))
        elseif inc.stage == "receiving" then
            local frac = (inc.expected or 0) > 0 and math.min(1, inc.got / inc.expected) or 0
            get.bar:SetValue(frac)
            get.incoming:SetText(("Receiving %s's setup: %d%%"):format(who, frac * 100))
        elseif inc.stage == "unpacking" then
            get.bar:SetValue(1)
            get.incoming:SetText(("Unpacking %s's setup..."):format(who))
        elseif inc.stage == "done" then
            get.incoming:SetText(("%sReceived|r %s's setup."):format(GREEN, who))
        elseif inc.stage == "failed" then
            get.incoming:SetText(RED .. (inc.reason or "Receiving failed.") .. "|r")
        end
    else
        get.incoming:SetText("")
    end

    local src, sources = CurrentSource()
    if not src then reviewing = false end

    -- Which state are we in?
    Shown(get.emptyW, src == nil)
    get.title:SetShown(src ~= nil)
    get.sub:SetShown(src ~= nil)
    Shown(get.sumW, src ~= nil and not reviewing)
    Shown(get.revW, src ~= nil and reviewing)
    get.prev:SetShown(#sources > 1)
    get.next:SetShown(#sources > 1)
    get.remove:SetShown(src ~= nil and src.key ~= "file")

    local hasBackup = ST:HasBackup() and true or false
    get.undo:SetShown(src ~= nil and not reviewing and hasBackup)
    get.undoR:SetShown(src ~= nil and reviewing and hasBackup)

    local lines = 0
    local missing = {}
    local offersEui, offersTwich = false, false
    if src then
        local pack = src.pack
        get.title:SetText(("%s's setup"):format(src.from))
        local recCount, recMissing = 0, 0
        if pack.addons then
            for _, e in ipairs(ST.SortedRecommended(pack)) do
                recCount = recCount + 1
                if e.state ~= "installed" then recMissing = recMissing + 1 end
            end
        end
        local euiSrc, euiWhy = ES.Source(pack)
        offersEui = euiSrc ~= nil or euiWhy ~= nil
        offersTwich = type(pack.twichui) == "table"
        local bits = {
            ("%d addon %s"):format(ST.CountAddons(pack), ST.CountAddons(pack) == 1 and "setting" or "settings"),
            euiSrc and "EllesmereUI profile" or nil,
            offersTwich and "TwichUI settings" or nil,
            pack.editMode and "Edit Mode layout" or nil,
            recCount > 0 and ("%d recommended addons"):format(recCount) or nil,
        }
        local sub = {}
        for i = 1, 5 do if bits[i] then sub[#sub + 1] = bits[i] end end
        get.sub:SetText(("Updated %s  ·  version %d  ·  %s%s"):format(When(pack.created), pack.version or 1,
            table.concat(sub, "  ·  "), #sources > 1 and ("  ·  %d of %d"):format(sourceIndex, #sources) or ""))

        getSel[src.key] = getSel[src.key] or {}
        local sel = getSel[src.key]
        local groups = ST.PackByAddon(pack)
        local titles = {}
        for _, g in ipairs(groups) do
            titles[#titles + 1] = g.title
            if reviewing then
                lines = lines + 1
                local r = ListRow(get.list, lines)
                local usable = g.state ~= "missing"
                if not usable then missing[#missing + 1] = g.title end
                r.check:Show()
                r.check:SetChecked(usable and sel[g.owner] ~= false)
                r.check:SetEnabled(usable)
                r.check:SetScript("OnClick", function(c) sel[g.owner] = c:GetChecked() and true or false; W:Refresh() end)
                r.arrow:SetText("")
                r.label:SetText(g.title)
                Ink(r.label, "text", usable and 1 or 0.55)
                local effect = ST.ApplyEffect(g)
                r.right:SetText(EFFECT_TEXT[effect] or STATE_TEXT[g.state] or "")
                r:SetScript("OnClick", nil)
                -- Show exactly which settings tables applying would change.
                r:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(g.title, 1, 1, 1)
                    GameTooltip:AddLine(effect == "new" and "Applying adds:" or "Applying replaces your:", 0.7, 0.7, 0.7)
                    for _, name in ipairs(g.tables) do GameTooltip:AddLine(name, 1, 1, 1) end
                    GameTooltip:Show()
                end)
                r:Show()
            end
        end
        local list = table.concat(titles, ", ", 1, math.min(#titles, 8))
        if #titles > 8 then list = list .. (" and %d more"):format(#titles - 8) end
        get.includes:SetText("Includes settings for: " .. list)
        get.addonsBtn:SetShown(not reviewing and recCount > 0)
        get.addonsBtnR:SetShown(reviewing and recCount > 0)
        local label = recMissing > 0 and ("Recommended addons (%d missing)"):format(recMissing) or "Recommended addons"
        get.addonsBtn:SetText(label)
        get.addonsBtnR:SetText(label)
        get.em:SetShown(reviewing and pack.editMode ~= nil)
    end
    FinishList(get.list, lines, "")
    get.eui:SetShown(offersEui and not reviewing)
    get.euiR:SetShown(offersEui and reviewing)
    get.twich:ClearAllPoints()
    get.twich:SetPoint("TOPLEFT", offersEui and 214 or 16, -248)
    get.twichR:ClearAllPoints()
    get.twichR:SetPoint("TOPLEFT", offersEui and 214 or 16, -490)
    get.twich:SetShown(offersTwich and not reviewing)
    get.twichR:SetShown(offersTwich and reviewing)
    get.missing:SetText(#missing > 0 and (RED .. "Install first to get these settings: " .. table.concat(missing, ", ") .. "|r") or "")

    local preview = src and Preview(src)
    get.preview:SetText(src and (preview or (GREY .. ((offersEui or offersTwich) and "No addon settings ticked. The EllesmereUI profile and TwichUI's own settings are imported with their own buttons below.|r"
        or "Nothing ticked. Tick the addons whose settings you want to use.|r"))) or "")
    get.apply:SetEnabled(preview ~= nil)
    get.alt:SetEnabled(src ~= nil)

    local rep = ST.report
    get.report:SetText((src and reviewing and rep) and (GREY .. ("Last change: %d settings updated%s.|r"):format(#rep.done,
        #rep.skipped > 0 and (", %d skipped"):format(#rep.skipped) or "")) or "")

    local names = {}
    for n in pairs(ST.db.trusted) do names[#names + 1] = SH.Short(n) end
    table.sort(names)
    get.trusted:SetText(#names > 0 and ("Accepts automatically from: " .. table.concat(names, ", ")) or "Always asks before accepting a setup.")
    get.clearTrust:SetShown(#names > 0)
end

---------------------------------------------------------------------------
-- Popup: export a backup as text / import one from text
---------------------------------------------------------------------------
local tp

local EXPORT_HELP = "Press Ctrl+C to copy the whole string, then paste it into a text file (Notepad, for instance) to keep it or move it to another computer. WoW can't save files itself, so the text file is yours to make. Nothing is sent to anyone."
local IMPORT_HELP = "Paste a backup string you exported earlier (Ctrl+V), then press Check backup. You'll see what's in it before anything is added."
local DETAILS = "Format: TUIBK2:<length>:<check>:<size>:<data> (TUIBK1 strings from earlier versions still import). The data is compressed settings (LibSerialize + LibDeflate), read only as data and never run as code. The check number only catches accidental damage, like a cut-off paste; it doesn't prove who made the string. A backup holds the settings of the addons you chose and TwichUI's own settings, plus its name, date and character. It never holds other backups, Undo copies, received setups, map pins or your Chronicle. Imports up to 8 MB, 20 backups and 32 MB in total."

local function CloseTransfer() if tp then tp:Hide() end end

local function SetTransferStatus(text) tp.status:SetText(text or "") end

local function PreviewText(r)
    local p = r.point
    local lines = {
        ("%s%s|r"):format(Head(), p.name),
        ("Saved %s%s  ·  %d addons (%d settings tables)%s  ·  about %s"):format(When(p.created),
            p.sourceName and (" by " .. p.sourceName) or "", r.addons, r.count, r.own and " and TwichUI's settings" or "", ST.FormatSize(r.bytes)),
    }
    if r.addonVersion and r.addonVersion ~= "?" then lines[#lines + 1] = "Made with TwichUI " .. r.addonVersion end
    if r.own then
        lines[#lines + 1] = "Also holds TwichUI's own settings: every switch, place and look, your profiles and stat weights. Restoring it replaces yours, including the switches that sell, fill trades or accept things for you, and whom you accept setups from."
    end
    if #r.missing > 0 then
        lines[#lines + 1] = ("%sNot installed or turned off on this client:|r %s. Their settings stay in the backup and apply if you install them."):format(GOLD, table.concat(r.missing, ", "))
    end
    if r.skipped > 0 then
        lines[#lines + 1] = ("%s%d settings table(s) can't be applied on this client|r and would be skipped when you restore."):format(GOLD, r.skipped)
    end
    if r.blocked then
        lines[#lines + 1] = RED .. r.blocked .. "|r"
    else
        lines[#lines + 1] = GREEN .. "Ready.|r Import as backup only adds it to your Backups list. It does not change your current settings; only Restore does."
    end
    return table.concat(lines, "\n")
end

-- The status line sits above the buttons, or above the Details text when shown.
local function PlaceTransferStatus()
    tp.status:ClearAllPoints()
    if tp.detailsText:IsShown() then
        tp.status:SetPoint("BOTTOMLEFT", tp.detailsText, "TOPLEFT", 0, 6)
    else
        tp.status:SetPoint("BOTTOMLEFT", 18, 44)
    end
end

local function BuildTransfer()
    tp = CreateFrame("Frame", "TwichUIBackupTransfer", UIParent, "BackdropTemplate")
    tp:SetSize(560, 470)
    tp:SetPoint("CENTER", 40, -20)
    tp:SetFrameStrata("DIALOG")
    tp:SetToplevel(true)
    tp:SetMovable(true)
    tp:EnableMouse(true)
    tp:RegisterForDrag("LeftButton")
    tp:SetScript("OnDragStart", tp.StartMoving)
    tp:SetScript("OnDragStop", tp.StopMovingOrSizing)
    tp:SetClampedToScreen(true)
    tp:HookScript("OnShow", R.FitToScreen)
    tinsert(UISpecialFrames, "TwichUIBackupTransfer")
    Look().Shell(tp, POPUP_HEADER)
    tp.title = Text(tp, "GameFontNormalLarge")
    tp.title:SetPoint("TOPLEFT", 16, -12)
    Look().CloseBox(tp)
    tp.sub = Text(tp, "GameFontHighlightSmall")
    tp.sub:SetPoint("TOPLEFT", 16, -38)
    tp.sub:SetWidth(528)

    -- Stacked from the bottom so the string box takes whatever height is left:
    -- buttons, then the Details text (when shown), then the status line, then the box.
    tp.status = Text(tp, "GameFontHighlightSmall")
    tp.status:SetPoint("BOTTOMLEFT", 18, 44)
    tp.status:SetWidth(524)
    tp.status:SetHeight(110)
    tp.status:SetJustifyV("TOP")
    tp.detailsText = Text(tp, "GameFontDisableSmall")
    tp.detailsText:SetPoint("BOTTOMLEFT", 18, 44)
    tp.detailsText:SetWidth(524)
    tp.detailsText:SetJustifyV("TOP")
    tp.detailsText:SetText(DETAILS)
    tp.detailsText:Hide()

    local box = CreateFrame("Frame", nil, tp, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 16, -88)
    box:SetPoint("BOTTOMRIGHT", tp.status, "TOPRIGHT", 2, 10)
    Look().Well(box, 0.9)
    local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -26, 6)
    Look().ScrollBar(sf)
    tp.edit = CreateFrame("EditBox", nil, sf)
    tp.edit:SetMultiLine(true)
    tp.edit:SetAutoFocus(false)
    tp.edit:SetFontObject("ChatFontNormal")
    tp.edit:SetWidth(490)
    sf:SetScript("OnSizeChanged", function(_, w) tp.edit:SetWidth(w) end)
    tp.edit:SetScript("OnEscapePressed", tp.edit.ClearFocus)
    tp.edit:SetScript("OnEditFocusGained", function(e) if tp.mode == "export" then e:HighlightText() end end)
    tp.edit:SetScript("OnTextChanged", function(e, user)
        if tp.mode == "export" then
            -- Read-only: put the string back if someone types in it.
            if user and tp.exported and e:GetText() ~= tp.exported then
                e:SetText(tp.exported)
                e:HighlightText()
            end
        elseif user ~= false then
            tp.result = nil
            tp.importBtn:Disable()
            if not R.Portable.Busy() then SetTransferStatus("") end
        end
    end)
    sf:SetScrollChild(tp.edit)
    tp.scroll = sf

    -- Import never lets an edit box hold the string. A paste arrives one character at a time and the box's work
    -- grows with its length, so a backup of hundreds of KB locks the client. The field is capped at no text at all
    -- (one byte is only the terminator); each character arriving through OnChar goes into a plain table instead, and
    -- on the first frame where no more arrived, the table is joined into the string Check backup reads.
    tp.line = Look().EditBox(box, 100, 24)
    tp.line:SetPoint("TOPLEFT", 6, -6)
    tp.line:SetPoint("TOPRIGHT", -6, -6)
    tp.line:SetMaxBytes(1)
    tp.pasted = Text(box, "GameFontDisableSmall")
    tp.pasted:SetPoint("TOPLEFT", tp.line, "BOTTOMLEFT", 2, -8)
    tp.pasted:SetWidth(480)
    tp.pasted:SetJustifyH("LEFT")
    local chars, n, seen, pasted = {}, 0, 0, nil
    function tp.PastedText() return pasted end
    local function ShowPasted()
        local size = pasted and #pasted or 0
        tp.pasted:SetText(size > 0 and ("%s of text pasted. Click Check backup."):format(ST.FormatSize(size))
            or "Click the box above and press Ctrl+V.")
    end
    local function Absorbed()
        tp.line:SetScript("OnUpdate", nil)
        pasted = table.concat(chars, "", 1, n)
        chars, n, seen = {}, 0, 0
        ShowPasted()
    end
    tp.line:SetScript("OnChar", function(_, c)
        if n == 0 then
            -- a new paste replaces the last one
            pasted, tp.result = nil, nil
            tp.importBtn:Disable()
            if not R.Portable.Busy() then SetTransferStatus("") end
            tp.pasted:SetText("Reading the paste...")
            seen = 0
            tp.line:SetScript("OnUpdate", function()
                if n == seen then Absorbed() else seen = n end
            end)
        end
        n = n + 1
        chars[n] = c
    end)
    function tp.ResetPaste()
        tp.line:SetScript("OnUpdate", nil)
        chars, n, seen, pasted = {}, 0, 0, nil
        tp.line:SetText("")
        ShowPasted()
    end

    tp.details = Btn(tp, "Details", 80, function()
        tp.detailsText:SetShown(not tp.detailsText:IsShown())
        PlaceTransferStatus()
    end)
    tp.details:SetPoint("BOTTOMLEFT", 16, 12)

    tp.copy = Btn(tp, "Copy export string", 160, function()
        tp.edit:SetFocus()
        tp.edit:HighlightText()
        SetTransferStatus(EXPORT_HELP)
    end, "Selects the whole string. Then press Ctrl+C.")
    tp.copy:SetPoint("BOTTOMRIGHT", -16, 12)

    tp.check = Btn(tp, "Check backup", 120, function()
        local text = tp.PastedText()
        tp.result = nil
        tp.importBtn:Disable()
        tp.check:Disable()
        SetTransferStatus("Checking...")
        R.Portable.Check(text, function(result)
            text = nil
            if not tp:IsShown() then return end
            tp.result = result
            tp.check:Enable()
            SetTransferStatus(PreviewText(result))
            if result.blocked then tp.importBtn:Disable() else tp.importBtn:Enable() end
        end, function(msg)
            text = nil
            if not tp:IsShown() then return end
            tp.check:Enable()
            SetTransferStatus(RED .. msg .. "|r Nothing was changed.")
        end)
    end, "Reads the pasted string and shows what's in it. Nothing is saved yet.")
    tp.check:SetPoint("BOTTOMRIGHT", -16, 12)
    tp.importBtn = Btn(tp, "Import as backup", 150, function()
        local point, why = R.Portable.Commit(tp.result)
        if not point then SetTransferStatus(RED .. (why or "That couldn't be imported.") .. "|r") return end
        R.Print("backup \"%s\" imported (%s). It hasn't been applied; use Restore on the Backups page when you want it.", point.name, R.Restore.Contents(point))
        CloseTransfer()
        W:Refresh()
    end, function()
        local why
        if not tp.result then why = "Check the backup first."
        elseif tp.result.blocked then why = tp.result.blocked end
        return "Adds the backup to your Backups list. It does not restore it or change your current settings.", why
    end)
    tp.importBtn:SetPoint("RIGHT", tp.check, "LEFT", -8, 0)
    tp.cancel = Btn(tp, "Cancel", 80, CloseTransfer)
    tp.cancel:SetPoint("RIGHT", tp.importBtn, "LEFT", -8, 0)

    tp:SetScript("OnHide", function()
        R.Portable.Cancel()
        tp.exported, tp.result = nil, nil
        tp.edit:SetText("")
        tp.edit:ClearFocus()
        tp.ResetPaste()
        tp.line:ClearFocus()
        SetTransferStatus("")
    end)
end

local function OpenTransfer(mode)
    if not tp then BuildTransfer() end
    R.Portable.Cancel()
    tp.mode, tp.exported, tp.result = mode, nil, nil
    tp.edit:SetText("")
    tp.ResetPaste()
    tp.detailsText:Hide()
    local exporting = mode == "export"
    tp.scroll:SetShown(exporting)
    tp.line:SetShown(not exporting)
    tp.pasted:SetShown(not exporting)
    tp.status:SetHeight(exporting and 30 or 110)   -- import shows a longer preview
    PlaceTransferStatus()
    tp.copy:SetShown(exporting)
    tp.check:SetShown(not exporting)
    tp.importBtn:SetShown(not exporting)
    tp.cancel:SetShown(not exporting)
    tp.check:Enable()
    tp.importBtn:Disable()
    tp.title:SetText(exporting and "Export backup" or "Import backup")
    tp.sub:SetText(exporting and EXPORT_HELP or IMPORT_HELP)
    SetTransferStatus("")
    tp:Show()
    tp:Raise()
end

function W:ExportBackup(point)
    OpenTransfer("export")
    SetTransferStatus("Preparing...")
    tp.copy:Disable()
    R.Portable.Export(point, function(text)
        if not tp:IsShown() or tp.mode ~= "export" then return end
        tp.exported = text
        tp.edit:SetText(text)
        tp.copy:Enable()
        SetTransferStatus(("%s  ·  %s of text. Click Copy export string, then press Ctrl+C."):format(point.name, ST.FormatSize(#text)))
        tp.edit:SetFocus()
        tp.edit:HighlightText()
    end, function(msg)
        if tp:IsShown() then SetTransferStatus(RED .. msg .. "|r") end
    end)
end

function W:ImportBackup()
    OpenTransfer("import")
    tp.line:SetFocus()
end

---------------------------------------------------------------------------
-- Page: Backups
---------------------------------------------------------------------------
local rp = {}

local function BuildBackups(p)
    rp.help = Text(p, "GameFontHighlightSmall")
    rp.help:SetPoint("TOPLEFT", 16, -4)
    rp.help:SetWidth(WIDTH - 32)
    rp.help:SetText("Save your own settings before you change things, and go back any time. A backup covers TwichUI's own settings and the addons you chose in Share setup, exactly as they're saved right now. It leaves out other backups, Undo copies, setups you received, map pins and your Chronicle.")
    rp.name = Look().EditBox(p, 100, 24)
    rp.name:SetSize(260, 24)
    rp.name:SetPoint("TOPLEFT", 22, -52)
    rp.name:SetAutoFocus(false)
    rp.name:SetScript("OnEscapePressed", rp.name.ClearFocus)
    rp.name:SetScript("OnTextChanged", function() rp.hint:SetShown(rp.name:GetText() == "") end)
    rp.hint = Text(rp.name, "GameFontDisableSmall")
    rp.hint:SetPoint("LEFT", 6, 0)
    rp.hint:SetWidth(248)   -- inside the box, whatever the font or language
    rp.hint:SetWordWrap(false)
    rp.hint:SetText("Name (optional), e.g. before EllesmereUI rework")
    local function CreateBackup()
        local status, why = R.Restore:Create(rp.name:GetText())
        if status == "created" then
            R.Print("backup \"%s\" saved (%s).", why.name, R.Restore.Contents(why))
            rp.name:SetText("")
        elseif not status then
            R.Print(why)
        end
        W:Refresh()
    end
    rp.create = Btn(p, "Create backup", 150, function()
        if not R.Restore.NeedsReload() then CreateBackup() return end
        -- Without this session's scan the backup is finished after a reload; say so before reloading.
        Confirm("TWICHUI_RP_CREATE", "Save a backup of TwichUI's settings and the addons chosen in Share setup?\n\nYour UI reloads once so TwichUI can read your addons' settings exactly as they're saved. Nothing is changed, sent or applied.",
            CreateBackup, { combat = true })
    end, function()
        if ST.capture then return "Saves TwichUI's settings and the ticked addons' settings from this session's scan." end
        if not R.Restore.NeedsReload() then return "Saves TwichUI's own settings. Tick addons in Share setup to back theirs up too." end
        return "Reloads your UI once to read your addons' settings exactly as they're saved, then saves the backup with TwichUI's settings."
    end)
    rp.create:SetPoint("LEFT", rp.name, "RIGHT", 10, 0)
    rp.import = Btn(p, "Import backup", 130, function() W:ImportBackup() end,
        "Paste a backup string you exported earlier. You'll see what's in it first; importing only adds it to this list.")
    rp.import:SetPoint("LEFT", rp.create, "RIGHT", 8, 0)

    rp.list = ListBox(p, 300)
    rp.list:SetPoint("TOPLEFT", 16, -92)
    rp.list.content:SetHeight(1)

    rp.safe = Text(p, "GameFontDisableSmall")
    rp.safe:SetPoint("TOPLEFT", rp.list, "BOTTOMLEFT", 2, -12)
    rp.safe:SetWidth(WIDTH - 230)
    rp.safe:SetText("Restoring saves your current settings first, so you can undo it. Applying a received setup does the same.")
    rp.undo = Btn(p, "Undo last change", 150, AskUndo,
        "Puts back what you had before you last restored a backup or applied a setup: that character's addon settings, and TwichUI's own if a backup replaced them.")
    rp.undo:SetPoint("TOPRIGHT", rp.list, "BOTTOMRIGHT", 0, -6)
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
    R.Interact.TipTruncated(r, r.label, function(row) return row.fullName end)   -- a long name you typed or imported
    r.detail = Text(r, "GameFontDisableSmall")
    r.detail:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -3)
    r.detail:SetWidth(380)
    r.del = Btn(r, "Delete", 70, function(b)
        local point = b.point
        Confirm("TWICHUI_RP_DELETE", ("Delete backup \"%s\" (%s)?\n\nThis can't be undone: you won't be able to go back to it."):format(point.name, R.Restore.Contents(point)), function()
            R.Restore:Delete(point.id); W:Refresh()
        end, { accept = DELETE })
    end)
    r.del:SetPoint("RIGHT", -6, 0)
    r.go = Btn(r, "Restore", 80, function(b)
        local point = b.point
        if InCombatLockdown() then R.Print("not in combat, please.") return end
        local eui = ""
        for name in pairs(point.tables or {}) do
            if ES.IsTable(name) then
                eui = "\n\nThis backup holds EllesmereUI's whole saved data: every profile and setting. Restoring it replaces all of yours."
                break
            end
        end
        local own = ""
        if R.Restore.HasOwn(point) then
            local blocked = R.Restore.OwnBlocked(point)
            own = blocked and ("\n\nTwichUI's settings in it won't be restored: " .. blocked)
                or "\n\nTwichUI's own settings are replaced too: every switch (including those that sell, fill trades or accept things for you), place and look, your profiles, and whom you accept setups from. Your map pins, Chronicle, backups and received setups stay as they are."
        end
        Confirm("TWICHUI_RP_RESTORE", ("Go back to \"%s\" (%s)?%s%s\n\nWhat you have now is saved first, so you can Undo from Backups. Your UI reloads."):format(point.name, R.Restore.Contents(point), eui, own),
            function()
                local ok, why = R.Restore:Restore(point.id)
                if not ok then R.Print("%s Nothing was restored.", why or "That couldn't be restored.")
                elseif why then R.Print("%s", why) end
            end, {
                combat = true,
                valid = function()
                    if not R.Restore.Get(point.id) then return false, "That backup is no longer there, so nothing was restored." end
                    return true
                end,
            })
    end)
    r.go:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
    r.export = Btn(r, "Export", 70, function(b) W:ExportBackup(b.point) end,
        "Turns this backup into text you can copy and keep, or paste into TwichUI on another computer.")
    r.export:SetPoint("RIGHT", r.go, "LEFT", -6, 0)
    rp.list.rows[i] = r
    return r
end

local function RefreshBackups()
    local points = R.Restore.List()
    for i, point in ipairs(points) do
        local r = RestoreRow(i)
        r.label:SetText(point.name)
        r.fullName = point.name
        r.detail:SetText(("%s  ·  %s  ·  %s  ·  %s"):format(When(point.created), point.sourceName or "?",
            R.Restore.Contents(point), ST.FormatSize(R.Restore.Size(point))))
        r.go.point, r.del.point, r.export.point = point, point, point
        r:Show()
    end
    for i = #points + 1, #rp.list.rows do rp.list.rows[i]:Hide() end
    rp.list.content:SetHeight(math.max(1, #points * 42))
    rp.list.empty:SetText(#points == 0 and "No backups yet. Create one before you change things, and you can come back to it any time." or "")
    rp.hint:SetShown(rp.name:GetText() == "" and not rp.name:HasFocus())
    rp.undo:SetShown(R.Restore.CanUndo() and true or false)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
-- Older names (slash commands, other modules, saved habits) map to the new pages.
local PAGE_ALIAS = { mine = "share", addons = "share", group = "share", get = "received", restore = "backups" }

local function SetPage(which)
    which = PAGE_ALIAS[which] or which
    if which ~= "share" and which ~= "received" and which ~= "backups" then which = "share" end
    page = which
    f.pageShare:SetShown(which == "share")
    f.pageReceived:SetShown(which == "received")
    f.pageBackups:SetShown(which == "backups")
    local tabs = { share = f.tabShare, received = f.tabReceived, backups = f.tabBackups }
    for key, tab in pairs(tabs) do
        tab:SetSelected(which == key)
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
    f:HookScript("OnShow", R.FitToScreen)
    tinsert(UISpecialFrames, "TwichUISetupWindow")

    -- the rim, and a title band that holds the name and the tabs (its lower line is the tabs' rule)
    Look().Shell(f, 62)

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(26, 26)
    logo:SetPoint("TOPLEFT", 12, -8)
    logo:SetTexture(R.ICON)
    local title = Look().Text(f, "brand")   -- the name, as the settings window shows it
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("TwichUI")
    local sub = Text(f, "GameFontDisableSmall")
    sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
    sub:SetText("share and back up your addon setup")

    Look().CloseBox(f)
    local storage = Btn(f, "Saved data", 100, function() W:ShowStorage() end,
        "See and delete what TwichUI keeps: your saved setup, setups friends sent you, backups, and Undo copies.")
    storage:SetPoint("TOPRIGHT", -36, -9)

    -- Tabs are plain buttons with no Blizzard template (Look.Tab): UIPanelButtonTemplate repaints its own art
    -- on every mouse down and up.
    local function TabBtn(label, onClick, width)
        return Look().Tab(f, label, width, onClick)
    end
    f.tabShare = TabBtn("Share setup", function() SetPage("share") end, 160)
    f.tabShare:SetPoint("TOPLEFT", 14, -38)
    f.tabReceived = TabBtn("Received setups", function() SetPage("received") end, 170)
    f.tabReceived:SetPoint("LEFT", f.tabShare, "RIGHT", 4, 0)
    f.tabBackups = TabBtn("Backups", function() SetPage("backups") end, 130)
    f.tabBackups:SetPoint("LEFT", f.tabReceived, "RIGHT", 4, 0)

    f.pageShare = CreateFrame("Frame", nil, f)
    f.pageShare:SetPoint("TOPLEFT", 0, -74)
    f.pageShare:SetPoint("BOTTOMRIGHT")
    f.pageReceived = CreateFrame("Frame", nil, f)
    f.pageReceived:SetPoint("TOPLEFT", 0, -74)
    f.pageReceived:SetPoint("BOTTOMRIGHT")
    f.pageBackups = CreateFrame("Frame", nil, f)
    f.pageBackups:SetPoint("TOPLEFT", 0, -74)
    f.pageBackups:SetPoint("BOTTOMRIGHT")
    BuildShare(f.pageShare)
    BuildGet(f.pageReceived)
    BuildBackups(f.pageBackups)

    f:SetScript("OnShow", function() W:Refresh() end)
    -- Transfers report progress per chunk; redraw at most a few times a second,
    -- and not at all on the page that shows nothing about transfers or the group.
    local refreshQueued = false
    local function QueueRefresh()
        if refreshQueued or (not f:IsShown() and not (gp and gp:IsShown())) or page == "backups" then return end
        refreshQueued = true
        C_Timer.After(0.25, function() refreshQueued = false; W:Refresh() end)
    end
    SH:OnChange(QueueRefresh)
    R.Group:OnChange(QueueRefresh)
end

function W:Refresh()
    if f and f:IsShown() then
        if page == "share" then RefreshShare()
        elseif page == "backups" then RefreshBackups()
        else RefreshGet() end
    end
    if cp and cp:IsShown() then RefreshChoose() end
    if rc and rc:IsShown() then RefreshRecommend() end
    if gp and gp:IsShown() then RefreshParty() end
    if ep and ep:IsShown() then RefreshEuiShare() end
    if ip and ip:IsShown() then RefreshEuiImport() end
    if tw and tw:IsShown() then RefreshTwichImport() end
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
        -- First open: friends land on Received setups, setup makers on Share setup.
        startPage = (ST.Mine() or ST.capture or next(ST.db.detected)) and "share" or "received"
        if #ST.Sources() > 0 and not ST.Mine() then startPage = "received" end
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
    local also = type(offer.twichui) == "table" and " and TwichUI's own settings" or ""
    local text = ("%s wants to share their setup with you: %d addons%s, about %s.\n\nAccepting just downloads it. You choose what to apply afterwards."):format(
        who, offer.addons or 0, also, ST.FormatSize(offer.bytes or 0))
    StaticPopup_Show("TWICHUI_OFFER", text, nil, sender)
end

function W:Received(sender)
    local who = SH.Short(sender)
    R.Print("%s's setup arrived. Type /tui share to review it before applying.", who)
    for i, s in ipairs(ST.Sources()) do if s.key == "recv:" .. sender then sourceIndex = i end end
    reviewing = false
    if f and f:IsShown() then SetPage("received") return end
    StaticPopupDialogs.TWICHUI_RECEIVED = {
        text = "%s's setup arrived. Open it now?",
        button1 = "Open", button2 = "Later",
        OnAccept = function() W:Show("received") end,
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
    Look().Surface(toast, Look().pal.band, 0.97, Look().pal.bronze, 0.85)
    Look().Recess(toast, 0.6)
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
    toast:SetScript("OnClick", function(self) self:Hide(); W:Show(self.page) end)
    toast:Hide()
end

function W:UpdateToast()
    if f and f:IsShown() then if toast then toast:Hide() end return end
    local text, frac, pagename, finished
    local o = SH.outgoing
    if o and not o.toasted then
        local who = SH.Short(o.target)
        pagename = "share"
        if o.stage == "offered" then text, frac = ("Waiting for %s to accept..."):format(who), 0
        elseif o.stage == "packing" then text, frac = "Packing your setup...", 0
        elseif o.stage == "sending" or o.stage == "delivered" then
            frac = (o.total or 0) > 0 and (o.sent or 0) / o.total or 0
            text = ("Sending to %s: %d%%"):format(who, frac * 100)
        elseif o.stage == "done" then text, frac, finished = ("%s has your setup."):format(who), 1, o
        elseif o.stage == "failed" then text, frac, finished = RED .. (o.reason or "Sending failed.") .. "|r", 0, o end
    end
    for sender, inc in pairs(SH.incoming) do
        if inc.stage == "unpacking" then
            text, frac, pagename, finished = ("Unpacking %s's setup..."):format(SH.Short(sender)), 1, "received", nil
        elseif inc.stage == "waiting" or inc.stage == "receiving" then
            local who = SH.Short(sender)
            frac = (inc.expected or 0) > 0 and math.min(1, inc.got / inc.expected) or 0
            text, pagename, finished = ("Receiving %s's setup: %d%%"):format(who, frac * 100), "received", nil
        elseif (inc.stage == "done" or inc.stage == "failed") and not inc.toasted then
            local who = SH.Short(sender)
            text = inc.stage == "done" and ("%s's setup arrived. Click to open."):format(who)
                or (RED .. (inc.reason or "Receiving failed.") .. "|r")
            frac, pagename, finished = inc.stage == "done" and 1 or 0, "received", inc
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
    sp:HookScript("OnShow", R.FitToScreen)
    tinsert(UISpecialFrames, "TwichUIStorage")
    Look().Shell(sp, POPUP_HEADER)
    local title = Text(sp, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText("Saved data")
    Look().CloseBox(sp)
    sp.sub = Text(sp, "GameFontHighlightSmall")
    sp.sub:SetPoint("TOPLEFT", 16, -38)
    sp.sub:SetWidth(528)
    sp.sub:SetText("Everything setup sharing keeps between sessions. The game loads all of it each time you log in, so delete what you no longer need.")

    local box = CreateFrame("Frame", nil, sp, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 16, -76)
    box:SetSize(528, 280)
    Look().Well(box, 0.9)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    Look().ScrollBar(scroll)
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
    local explore = Btn(sp, "Look inside", 100, function()
        if R.ExplorerWindow then R.ExplorerWindow.Show() end
    end, "Opens the Saved Data Explorer: a read-only look at everything listed here and the rest of what TwichUI keeps. Advanced cleanup there is off until you turn it on.")
    explore:SetPoint("BOTTOMRIGHT", -16, 12)
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
        Confirm("TWICHUI_DELETE", ("Delete %s?\n\n%s"):format(item.label, item.warn or "This can't be undone."), function()
            item.remove()
            W:ShowStorage()
            W:Refresh()
        end, { accept = DELETE })
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
-- Popup: sending options (how setups are sent)
---------------------------------------------------------------------------
local sop

local function BuildChannels()
    sop = CreateFrame("Frame", "TwichUISendingOptions", UIParent, "BackdropTemplate")
    sop:SetSize(540, 430)
    sop:SetPoint("CENTER", 20, 0)
    sop:SetFrameStrata("DIALOG")
    sop:SetToplevel(true)
    sop:SetMovable(true)
    sop:EnableMouse(true)
    sop:RegisterForDrag("LeftButton")
    sop:SetScript("OnDragStart", sop.StartMoving)
    sop:SetScript("OnDragStop", sop.StopMovingOrSizing)
    sop:SetClampedToScreen(true)
    sop:HookScript("OnShow", R.FitToScreen)
    tinsert(UISpecialFrames, "TwichUISendingOptions")
    Look().Shell(sop, POPUP_HEADER)
    local title = Text(sop, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText("Sending options")
    Look().CloseBox(sop)

    local why = Text(sop, "GameFontHighlightSmall")
    why:SetPoint("TOPLEFT", 16, -42)
    why:SetWidth(508)
    why:SetSpacing(2)
    why:SetText(Head() .. "How to send|r\n" .. SH.TRANSPORT_EXPLAIN)

    local y = -150
    sop.opts = {}
    local function Refresh()
        for _, c in ipairs(sop.opts) do c:SetChecked(SH.Transport() == c.key) end
    end
    for _, key in ipairs(SH.TRANSPORTS) do
        local c = Check(sop, SH.TRANSPORT_LABEL[key])
        c:SetPoint("TOPLEFT", 14, y)
        c.label:SetFontObject("GameFontHighlight")
        Ink(c.label, "text")
        c.key = key
        c:SetScript("OnClick", function()
            SH.SetTransport(key)
            Refresh()
            W:Refresh()
        end)
        local d = Text(sop, "GameFontDisableSmall")
        d:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 26, 0)
        d:SetWidth(470)
        d:SetText(SH.TRANSPORT_HELP[key])
        y = y - 58
        sop.opts[#sop.opts + 1] = c
    end
    sop.refreshChecks = Refresh
    sop.status = Text(sop, "GameFontHighlightSmall")
    sop.status:SetPoint("BOTTOMLEFT", 16, 44)
    sop.status:SetWidth(508)
    local note = Text(sop, "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 16, 12)
    note:SetWidth(508)
    note:SetText("This only controls how you send. A friend's configuration reaches you over any of the three, and you're always asked before anything is accepted or applied. If a send fails, nothing else is tried.")
end

function W:ShowChannels()
    if not sop then BuildChannels() end
    sop.refreshChecks()
    sop.status:SetText(Head() .. "Direct test:|r " .. R.Group.WhisperStatus())
    sop:Show()
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
        em:HookScript("OnShow", R.FitToScreen)
        Look().Shell(em, 0)
        em.text = Text(em, "GameFontHighlightSmall")
        em.text:SetPoint("TOPLEFT", 14, -12)
        em.text:SetPoint("TOPRIGHT", -14, -12)
        em.box = Look().EditBox(em, 100, 24)
        em.box:SetSize(440, 24)
        em.box:SetPoint("TOP", 0, -66)
        em.box:SetAutoFocus(false)
        em.box:SetScript("OnEditFocusGained", function(b) b:HighlightText() end)
        em.box:SetScript("OnEscapePressed", function() em:Hide() end)
        local done = Btn(em, "Done", 90, function() em:Hide() end)
        done:SetPoint("BOTTOM", 0, 12)
    end
    em.text:SetText(("Layout: %s%s|r\nClick the box and press Ctrl+C. Then open Edit Mode, open the layout menu, choose Import, and paste."):format(Head(), pack.editModeName or "shared layout"))
    em.box:SetText(pack.editMode)
    em.box:SetCursorPosition(0)
    em:Show()
    em.box:SetFocus()
end

-- Friends: mention once when a setup is waiting and hasn't been applied.
R:On("PLAYER_LOGIN", function()
    if not R:Enabled("setupSharing") then return end
    if #ST.Sources() > 0 and not ST:HasBackup() and not ST.report and not ST.Mine() then
        C_Timer.After(4, function() R.Print("a shared addon setup is waiting. Type /tui share to review it.") end)
    end
end)
