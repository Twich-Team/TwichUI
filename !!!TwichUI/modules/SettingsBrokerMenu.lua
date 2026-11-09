-- TwichUI: the "TwichUI" data bar entry's menu
-- What a left click on the TwichUI entry opens (SettingsBroker.lua): a small menu in the same style as the Mage
-- launchers' and the RestedXP guide's (modules/SpellMenu.lua, modules/RestedXPBrokerMenu.lua): the same palette,
-- fonts and placement, and the player's own menu background and border (modules/MenuStyle.lua).
--   Open settings...        opens the settings window (R:OpenSettings) and closes the menu.
--   Workshop...             opens or closes the Workshop (R.WorkshopLauncher.Toggle; it loads the addon the first time).
--   Quiet the screen        a temporary switch (QuietScreen.lua, not saved: off again at the next login or reload).
--                           While it is On, the cards, Reminders, action bar glows, Healer Watch panel and Return
--                           the Favor list stay away. The row says On or Off.
--   Leave me alone          one switch for Decline duels and Decline group invitations together (qol/QoL.lua,
--                           Q.SetLeaveAlone). The row says On or Off; it is On when both are on. Turning it on
--                           turns on whichever was off; turning it off turns off only what it turned on. The
--                           exceptions chosen in the settings (friends, guild members) still apply.
--   Guild Locations         Sharing my location / Invisible (still see others), through GL.SetState, the same
--                           call the settings page makes (guildloc/State.lua is the one authority). Greyed out,
--                           with the reason in the row, while the feature is Off or its saved data is held: the
--                           menu never turns sharing on from Off. Outside a guild both stay selectable (a privacy
--                           choice does not need a guild). Then Guild Locations settings... opens its page.
--                           The whole section is absent when the Guild Locations code is not loaded.
-- The switches leave the menu open, so both can be set in one visit, and the rows follow the settings window
-- when it changes them. Nothing in it is secure, so it works in combat too, and it listens for events only while
-- it is open. A click anywhere else, Esc or a second click on the data bar entry closes it. What the rows do is
-- the core's (QoL, GuildLoc); this file only draws.

local R = TwichUI
local SM = R.SpellMenu
local MenuStyle = R.MenuStyle
local M = {}
R.SettingsBrokerMenu = M

local NAME = "TwichUISettingsMenu"
local WIDTH, PAD = 240, 8
local TITLE_H, ROW_H, HEAD_H, DIVIDER_H = 26, 24, 24, 8
local BOX = 14

local menu, title
local rows = {}
local owner                -- the data bar frame it was opened from
local pad = PAD
local listening = false

local function Palette() return SM.Palette() end
local function Paint(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

---------------------------------------------------------------------------
-- What the rows say and do
---------------------------------------------------------------------------
local function GL() return R.GuildLoc end
local function GLShown() return GL() ~= nil end
-- Why Guild Locations' choices can't be made right now, or nil: "Off" (turn it on in the settings) or "Unavailable"
-- (its saved data is held).
local function GLWhy()
    local state, why = GL().State()
    if why == "held" then return "Unavailable" end
    if state == "off" then return "Off" end
end

local LEAVE_TIP = "Declines duel requests and group invitations, except from the friends and guild members you "
    .. "allowed in the settings. Turning it off turns off only what it turned on."

local QUIET_TIP = "Keeps notification cards, reminders, action bar glows, the Healer Watch panel and Return the "
    .. "Favor's list off the screen, with their sounds, until you turn this off or log out. Nothing in the settings "
    .. "changes, and what happens meanwhile is not shown afterwards."

local SPEC = {
    {
        key = "settings", label = "Open settings...", plain = true,
        act = function() M.Close(); R:OpenSettings() end,
    },
    {
        key = "workshop", label = "Workshop...", plain = true,
        shown = function() return R.WorkshopLauncher ~= nil end,
        act = function() M.Close(); R.WorkshopLauncher.Toggle() end,
    },
    { kind = "divider" },
    {
        key = "quiet", label = "Quiet the screen",
        state = function() return R.QuietScreen ~= nil and R.QuietScreen.On() end,
        words = { [true] = "On", [false] = "Off" },
        enabled = function() return R.QuietScreen ~= nil end,
        why = "Unavailable",
        tip = QUIET_TIP,
        act = function() R.QuietScreen.Toggle() end,
    },
    {
        key = "leave", label = "Leave me alone",
        state = function() return R.QoL and R.QoL.LeaveAloneOn() or false end,
        words = { [true] = "On", [false] = "Off" },
        enabled = function() return R.QoL ~= nil end,
        why = "Unavailable",
        tip = LEAVE_TIP,
        act = function() local Q = R.QoL; Q.SetLeaveAlone(not Q.LeaveAloneOn()) end,
    },
    { kind = "divider", shown = GLShown },
    { kind = "heading", label = "Guild Locations", shown = GLShown },
    {
        key = "sharing", label = "Sharing my location", shown = GLShown,
        state = function() return GL().State() == "sharing" end,
        words = { [true] = "Current", [false] = "" },
        enabled = function() return GLWhy() == nil end,
        why = GLWhy,
        act = function() GL().SetState("sharing") end,
    },
    {
        key = "invisible", label = "Invisible (still see others)", shown = GLShown,
        state = function() return GL().State() == "invisible" end,
        words = { [true] = "Current", [false] = "" },
        enabled = function() return GLWhy() == nil end,
        why = GLWhy,
        act = function() GL().SetState("invisible") end,
    },
    {
        key = "glsettings", label = "Guild Locations settings...", plain = true, shown = GLShown,
        act = function() M.Close(); R:OpenSettings("guildLocations") end,
    },
}

---------------------------------------------------------------------------
-- The rows. A switch has a label, a box that is filled when it is on, and a note on the right that says it in
-- words, so the state never rests on color alone.
---------------------------------------------------------------------------
local function NewRow(spec)
    local K = Palette()
    if spec.kind == "divider" then
        local row = CreateFrame("Frame", nil, menu)
        row.spec = spec
        row:SetHeight(DIVIDER_H)
        row.line = SM.Solid(row, "ARTWORK", K.bronzeLo, 0.8)
        row.line:SetHeight(1)
        row.line:SetPoint("LEFT", 4, 0)
        row.line:SetPoint("RIGHT", -4, 0)
        return row
    end
    if spec.kind == "heading" then
        local row = CreateFrame("Frame", nil, menu)
        row.spec = spec
        row:SetHeight(HEAD_H)
        row.name = SM.Text(row, SM.FONTS.header, 12, "GameFontNormalSmall")
        row.name:SetPoint("BOTTOMLEFT", 6, 3)
        row.name:SetText(spec.label)
        Paint(row.name, K.gold)
        return row
    end
    local row = CreateFrame("Button", nil, menu)
    row:SetHeight(ROW_H)
    row.spec = spec
    local hover = SM.Solid(row, "HIGHLIGHT", K.gold, 0.08)
    hover:SetAllPoints()
    row.note = SM.Text(row, SM.FONTS.note, 12, "GameFontNormalSmall")
    row.note:SetPoint("RIGHT", -6, 0)
    row.note:SetJustifyH("RIGHT")
    row.name = SM.Text(row, SM.FONTS.row, 14, "GameFontNormal")
    if spec.plain then
        row.name:SetPoint("LEFT", 6, 0)
    else
        row.rim = SM.Solid(row, "ARTWORK", K.bronzeLo)
        row.rim:SetSize(BOX, BOX)
        row.rim:SetPoint("LEFT", 5, 0)
        row.well = SM.Solid(row, "ARTWORK", K.well)
        row.well:SetDrawLayer("ARTWORK", 1)
        row.well:SetPoint("TOPLEFT", row.rim, 1, -1)
        row.well:SetPoint("BOTTOMRIGHT", row.rim, -1, 1)
        row.fill = SM.Solid(row, "ARTWORK", K.gold)
        row.fill:SetDrawLayer("ARTWORK", 2)
        row.fill:SetPoint("TOPLEFT", row.rim, 3, -3)
        row.fill:SetPoint("BOTTOMRIGHT", row.rim, -3, 3)
        row.name:SetPoint("LEFT", row.rim, "RIGHT", 8, 0)
    end
    row.name:SetPoint("RIGHT", row.note, "LEFT", -6, 0)
    row:SetScript("OnClick", function(self)
        local s = self.spec
        if s.enabled and not s.enabled() then return end
        s.act()
        if menu and menu:IsShown() then M.Refresh() end
    end)
    if spec.tip then
        row:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.spec.label, 1, 1, 1)
            GameTooltip:AddLine(self.spec.tip, 0.8, 0.7, 0.3, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    return row
end

-- A row's reason for being greyed out: a string, or a function that returns one (nil when there is none).
local function Why(s)
    if type(s.why) == "function" then return s.why() end
    return s.why
end

local function Fill(row)
    local K = Palette()
    local s = row.spec
    local enabled = not s.enabled or s.enabled()
    row.name:SetText(s.label)
    Paint(row.name, enabled and K.text or K.stone)
    if s.plain then
        row.note:SetText("")
    else
        local on = s.state()
        row.fill:SetShown(on == true)
        local rim = on and K.bronze or K.bronzeLo
        row.rim:SetColorTexture(rim[1], rim[2], rim[3])
        -- A greyed switch says why instead of its state; the box still shows the state.
        local why = not enabled and Why(s)
        row.note:SetText(why or s.words[on] or "")
    end
    Paint(row.note, K.stone)
    row:SetEnabled(enabled and true or false)
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
local function Build()
    if menu then return end
    local K = Palette()
    menu = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
    menu:SetWidth(WIDTH)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:Hide()
    title = SM.Text(menu, SM.FONTS.title, 13, "GameFontNormal")
    title:SetText("TwichUI")
    Paint(title, K.text)
    for i, spec in ipairs(SPEC) do rows[i] = NewRow(spec) end
    menu:SetScript("OnHide", function()
        owner = nil
        if GameTooltip then
            local tipOwner = GameTooltip:GetOwner()
            if tipOwner and tipOwner:GetParent() == menu then GameTooltip:Hide() end
        end
        M.Listen(false)
    end)
    if UISpecialFrames then tinsert(UISpecialFrames, NAME) end
end

-- The player's background and border, and a margin that clears a thick one.
local function Restyle()
    pad = math.max(PAD, math.ceil(MenuStyle.Apply(menu)))
end

local function Render()
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", pad + 4, -pad - 2)
    local y = -(pad + TITLE_H)
    for _, row in ipairs(rows) do
        local s = row.spec
        local shown = not s.shown or s.shown()
        row:SetShown(shown)
        if shown then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", menu, "TOPLEFT", pad, y)
            row:SetPoint("RIGHT", menu, "RIGHT", -pad, 0)
            if not s.kind then Fill(row) end
            y = y - (s.kind == "divider" and DIVIDER_H or (s.kind == "heading" and HEAD_H or ROW_H))
        end
    end
    menu:SetHeight(-y + pad)
end

---------------------------------------------------------------------------
-- Opening, closing, following the settings
---------------------------------------------------------------------------
function M.IsOpen() return menu ~= nil and menu:IsShown() end

function M.Open(frame)
    Build()
    owner = frame
    Restyle()
    Render()
    SM.PlaceNear(menu, frame)
    menu:Show()
    M.Listen(true)
end

function M.Close()
    if M.IsOpen() then menu:Hide() end
end

function M.Toggle(frame)
    if M.IsOpen() then M.Close() else M.Open(frame) end
end

-- A switch or Guild Locations' state changed (here, in the settings window or by a profile change), or the
-- player's menu look did: draw it again.
function M.Refresh()
    if M.IsOpen() then Render() end
end

local function OnLook()
    if not menu then return end
    Restyle()
    M.Refresh()
end

-- A click anywhere but the menu or the data bar entry closes it.
local function OnMouseDown()
    if not M.IsOpen() or menu:IsMouseOver() then return end
    if owner and owner.IsMouseOver and owner:IsMouseOver() then return end
    M.Close()
end

local HANDLERS = {
    GLOBAL_MOUSE_DOWN = OnMouseDown,
    UI_SCALE_CHANGED = OnLook,           -- a border is a whole number of screen pixels
    DISPLAY_SIZE_CHANGED = OnLook,
}

function M.Listen(on)
    if on == listening then return end
    listening = on
    for event, handler in pairs(HANDLERS) do
        if on then R:On(event, handler) else R:Off(event, handler) end
    end
end

-- Switches changed in the settings window while the menu is open: the rows follow.
if R.Switches and R.Switches.OnChange then
    R.Switches.OnChange(function() M.Refresh() end)
end

-- Quiet screen turned on or off by something else while the menu is open.
if R.QuietScreen then R.QuietScreen.OnChange(function() M.Refresh() end) end

MenuStyle.Subscribe(OnLook)
