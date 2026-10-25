-- TwichUI: the world map's tool bar for pins and pings
-- A small bar in the world map's header (the empty stretch of the title row, to the right of the map's navigation
-- breadcrumbs) that offers what Party pins and Map pings already do with modifier clicks, as four icon buttons: Pin (a
-- personal pin), Group pin, Group ping and Help. Their tooltips name them. The shortcuts stay as they were and stay the
-- fast path; this is how a player finds them, or does without them. While Navigation is on (nav/Nav.lua) a fifth, Navigate,
-- plans a walking route to the clicked spot; it has no shortcut of its own, so the map's clicks keep their meanings.
-- While Vendors and trainers is on, a funnel button (the NPC filter, npcs/FilterMenu.lua) opens a menu of the kinds of NPC
-- the map shows. It is not a tool: nothing is armed, and the menu is closed by anything that arms or opens something else.
--   A tool is one-shot. Clicking its button arms it (the button stays lit and a strip under the bar says what the next
--     click does); the next plain left-click on the map does the action once and puts the tool away. Arming sends and
--     makes nothing.
--   One path. The click is the map's own canvas click (a handler at priority 110, above the ping click at 105, the pin
--     clicks at 95 and WaypointUI's at 100), so it never fires with another handler on the same input. It only takes a
--     plain left-click while a tool is armed, and then does exactly what the shortcut does through the same helpers:
--     PinsMap.PlacePin (opens the new pin window; nothing is made or sent until Save) and MapPingView.PingAt (the ping
--     checks, limits and message). A shortcut click made while a tool is armed is that shortcut's, once, and puts the
--     tool away. The map hands handlers a click only when the pointer stayed within a few pixels (a pan is not one).
--   Put away when: Esc (a keyboard catcher that exists only while a tool or the help is up, and lets every other key
--     through), the same button again, another tool, the map closing, the feature or the bar going off,
--     a profile change, or the tool no longer being possible (you left the group). A map change does not cancel it: the
--     strip stays in view and the place is read from the map being viewed at the moment of the click.
--   Unavailable tools (a group tool alone, a ping with Map pings off) stay on the bar, dimmed; the tooltip says why and
--     a click says it again. They are never disabled, so the reason can always be read.
--   Everything said about shortcuts is read from the saved choices when shown (Look.lua: localClick, partyClick, the ping
--     gesture); no shortcut is written into this file.
-- Saved: ui.partyPins.toolbar (Look.lua; shared and in the profile), and ui.mapToolsIntro, the
-- once-only note's "seen" (account-wide, never shared, never part of a profile). Nothing else: no armed tool, no help.
-- The bar is made when the map is first shown. It has no OnUpdate and no timer; it listens for GROUP_ROSTER_UPDATE
-- only while it is on the map.

local R = TwichUI
local PN = R.Pins
local PL = R.PinsLook
local PG = PL.Ping
local PM = R.PinsMap
local MP = R.MapPing
local V = R.MapPingView
local T = {}
R.MapTools = T

local CLICK_PRIORITY = 110
local BUTTON_H, ICON, GAP = 24, 18, 3
local NOTICE_GAP = 3
local CURSOR = "MAP_PIN_CURSOR"                       -- the game's own, as its waypoint tool uses it
local ICON_PATH = R.PATH .. [[media\textures\maptool-]]
T.ICON_PATH = ICON_PATH

-- id, the name in a tooltip and the help, the icon file, what the strip says while it is armed
local TOOLS = {
    { id = "pin", name = "Personal pin", icon = "pin",
        prompt = "Click the map to place a personal pin. Esc to cancel." },
    { id = "group", name = "Group pin", icon = "group-pin",
        prompt = "Click the map to place a group pin. Esc to cancel." },
    { id = "ping", name = "Group ping", icon = "ping",
        prompt = "Click the map to ping your group. Esc to cancel." },
    -- last: on the bar and in the help only while Navigation is on (nav/Nav.lua)
    { id = "nav", name = "Navigate", icon = "navigate",
        prompt = "Click the map to navigate there. Esc to cancel." },
}
local BY_ID = {}
for _, t in ipairs(TOOLS) do BY_ID[t.id] = t end
local HELP = { id = "help", name = "Map tools help", icon = "help" }
T.TOOLS, T.HELP = TOOLS, HELP

-- The look's colors. The shared window look has the teal accent; without it (a test, a broken load) a copy stands in.
local function Pal()
    local L = R.Look
    if L and L.pal then return L.pal end
    return { text = { 0.94, 0.91, 0.82 }, textDim = { 0.80, 0.78, 0.72 }, stone = { 0.62, 0.60, 0.56 },
        teal = { 0.36, 0.58, 0.57 }, tealHi = { 0.58, 0.78, 0.76 }, tealLo = { 0.18, 0.33, 0.33 }, danger = { text = { 0.90, 0.64, 0.56 } } }
end
T.Pal = Pal                                           -- npcs/SearchBar.lua draws its field in the same colors
local GOLD = { 0.86, 0.69, 0.30 }                     -- as the map's other tooltips say what a click does

local installed = false
local provider
local bar, strip, help, callout, keys
local buttons = {}                                    -- buttons[id]
local armed                                           -- a tool's id, or nil
local helpOpen = false
local styleDirty = true
local avail = {}                                      -- [id] = { ok, why }
local lastSay, lastSayAt
local calloutSession = false                          -- the once-only note was shown this session
local stats = { arms = 0, placed = 0, pinged = 0, cancels = 0, refused = 0 }

local function MapOpen() return WorldMapFrame and WorldMapFrame:IsShown() end
local function Now() return GetTime() end

local function Say(text)
    local now = Now()
    if text == lastSay and lastSayAt and now >= lastSayAt and now - lastSayAt < NOTICE_GAP then return end
    lastSay, lastSayAt = text, now
    PM.Notice(text)
end

---------------------------------------------------------------------------
-- The saved choices
---------------------------------------------------------------------------
local function IntroSeen()
    local ui = TwichUIDB and TwichUIDB.ui
    return type(ui) == "table" and ui.mapToolsIntro == true
end

-- The once-only note's "seen": its own key, outside the profile and the shared settings (Profiles.lua, TwichConfig.lua).
local function MarkIntroSeen()
    if type(TwichUIDB) ~= "table" or IntroSeen() then return end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    TwichUIDB.ui.mapToolsIntro = true
end

---------------------------------------------------------------------------
-- What each tool says and whether it can be used now
---------------------------------------------------------------------------
-- The shortcut for a tool as a phrase ("Alt-click the map"), or nil when it has none. Read from the saved choices.
function T.Shortcut(id)
    local choice
    if id == "pin" then
        choice = PL.Pref("localClick")
        if choice ~= "none" then return PL.ClickLabel(choice) .. " the map" end
    elseif id == "group" then
        choice = PL.Pref("partyClick")
        if choice ~= "none" then return PL.ClickLabel(choice) .. " the map" end
    elseif id == "ping" then
        choice = PG.Get("gesture")
        if choice ~= "none" then return PG.GestureLabel(choice) .. " the map" end
    end
    return nil
end

local function NavOn() return R.Nav ~= nil and R.Nav.Enabled() end
T.NavOn = NavOn

-- The NPC filter button is on the bar while Vendors and trainers and the choice are (npcs/FilterMenu.lua).
local function FilterOn()
    local FM = R.NpcFilterMenu
    return FM ~= nil and FM.Wanted()
end

-- true, or false and one sentence. Asked when the bar is drawn and again at the moment of a click.
function T.Available(id)
    if not (R:Enabled("partyPins") and PL.Pref("toolbar")) then return false, PN.Reason("off") end
    if id == "nav" then
        if not NavOn() then return false, "Navigation is turned off. Turn it on in TwichUI's settings (Navigation)." end
        return true
    end
    if id == "pin" then
        if PN.LocalCount() >= PN.MAX_LOCAL then return false, PN.Reason("local-limit") end
        return true
    elseif id == "group" then
        local blocked = PN.SendBlocked()
        if blocked == "no-party" then return false, "Join a party to place a group pin." end
        if blocked then return false, PN.Reason(blocked) end
        if PN.OwnCount() >= PN.MAX_PER_OWNER then return false, PN.Reason("owner-limit") end
        if PN.SharedCount() >= PN.MAX_SHARED then return false, PN.Reason("session-limit") end
        return true
    elseif id == "ping" then
        if not R:Enabled("mapPings") then return false, "Map pings are turned off in the Pins and Pings options." end
        if not R:Enabled("mapPingsSend") then return false, "Sending map pings is turned off in the Pins and Pings options." end
        local dist, why = MP.Route()
        if not dist then
            if why == "no-group" then return false, "Join a party or raid to send a group ping." end
            return false, MP.Reason(why)
        end
        return true
    end
    return false, "That can't be done right now."
end

-- What a tool's tooltip says: { title, lines = { { text, tone } } }, tone "dim", "gold" or "warn". Built each time it
-- is shown, so a changed shortcut or a changed group is never out of date.
function T.Describe(id)
    local out = { lines = {} }
    local function Add(text, tone) out.lines[#out.lines + 1] = { text, tone or "dim" } end
    if id == "pin" then
        out.title = "Personal pin"
        Add("A private place on your map: only you see it, and it is kept between sessions.")
        Add("It opens the pin window for a name and a color. Nothing is made until you press Save.")
    elseif id == "group" then
        out.title = "Group pin"
        Add("A place shared with your party (a party pin). Members who have TwichUI with Party pins on see it; others see nothing.")
        Add("It lasts while you stay in the party and is gone when the party is. It is sent only when you press Save.")
    elseif id == "ping" then
        out.title = "Group ping"
        Add("A temporary signal: a marker with your name shows on your group's maps for a few seconds. It is not saved and makes no pin.")
        Add("It goes to your party, raid or instance group. Members need TwichUI with Party pins and Map pings on; others see nothing.")
    elseif id == "nav" then
        out.title = "Navigate"
        Add("Plans a walking route from where you are to the spot you click, and guides you along it with the navigation frame, the arrow and the route on your maps.")
        Add("It replaces any destination you were navigating to. Nothing is sent to anyone and no pin is made.")
    elseif id == "help" then
        out.title = "Map tools help"
        Add("What each tool does and the shortcut for it.")
        return out
    elseif id == "filter" then
        out.title = "NPC Filters"
        Add("Choose which kinds of NPC the map shows: vendors, trainers and services. Nothing is deleted; the NPCs you know are kept either way.")
        return out
    else
        return out
    end
    Add(armed == id and "Armed. Click the map to use it, or click here again to cancel." or "Click this button, then click the map. Esc cancels.", "gold")
    local shortcut = T.Shortcut(id)
    if id == "nav" then
        Add("It has no map shortcut: the map's own clicks stay as they are. A pin's menu has Navigate here too.")
    else
        Add(shortcut and ("Shortcut: " .. shortcut .. ".") or "No shortcut is set. You can choose one in the Pins and Pings options.")
    end
    local ok, why = T.Available(id)
    if not ok then Add(why, "warn") end
    return out
end

-- The help panel's rows: { id, name, how, shortcut line }, from the same sources as the tooltips.
function T.HelpRows()
    local rows = {}
    for _, t in ipairs(TOOLS) do
        if t.id ~= "nav" or NavOn() then
            local shortcut = T.Shortcut(t.id)
            rows[#rows + 1] = { id = t.id, name = t.name, how = "Click the button, then click the map.",
                shortcut = t.id == "nav" and "No map shortcut" or (shortcut and ("Shortcut: " .. shortcut) or "No shortcut set") }
        end
    end
    return rows
end

function T.Armed() return armed end
function T.HelpOpen() return helpOpen end
function T.Installed() return installed end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function Paint(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end

local function Skin(f)
    f.pad = math.max(4, math.ceil(PL.Surface(PL.MenuLook, f)))
    return f.pad
end

local function Solid(f, layer, c, a)
    local t = f:CreateTexture(nil, layer)
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    return t
end

local function Tip(b)
    local id = b.toolId
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOMLEFT", 0, -2)
    local d = T.Describe(id)
    GameTooltip:SetText(d.title, 1, 1, 1)
    for _, line in ipairs(d.lines) do
        if line[2] == "gold" then GameTooltip:AddLine(line[1], GOLD[1], GOLD[2], GOLD[3], true)
        elseif line[2] == "warn" then GameTooltip:AddLine(line[1], 0.92, 0.55, 0.44, true)
        else GameTooltip:AddLine(line[1], 0.78, 0.74, 0.66, true) end
    end
    GameTooltip:Show()
end

local function NewButton(parent, id)
    local b = CreateFrame("Button", nil, parent)
    b.toolId = id
    b:SetHeight(BUTTON_H)
    b:RegisterForClicks("LeftButtonUp")
    b.fill = Solid(b, "BACKGROUND", Pal().tealLo, 0.9)
    b.fill:SetAllPoints()
    b.fill:Hide()
    b.edge = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local e = Solid(b, "BORDER", Pal().tealHi, 1)
        if i <= 2 then
            e:SetHeight(1)
            e:SetPoint(side .. "LEFT", 0, 0)
            e:SetPoint(side .. "RIGHT", 0, 0)
        else
            e:SetWidth(1)
            e:SetPoint("TOP" .. side, 0, 0)
            e:SetPoint("BOTTOM" .. side, 0, 0)
        end
        e:Hide()
        b.edge[i] = e
    end
    local hl = Solid(b, "HIGHLIGHT", Pal().tealHi, 0.16)
    hl:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ICON, ICON)
    b:SetScript("OnEnter", Tip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- One button's look from the state: armed (lit, with an outline: not by color alone), unavailable (dim, still hoverable).
local function PaintButton(b, id)
    local FM = R.NpcFilterMenu
    local on = (id == armed) or (id == "help" and helpOpen) or (id == "filter" and FM ~= nil and FM.IsOpen())
    local a = avail[id]
    local usable = id == "help" or id == "filter" or not a or a.ok
    b.fill:SetShown(on)
    for _, e in ipairs(b.edge) do e:SetShown(on) end
    b.icon:SetDesaturated(not usable)
    b.icon:SetAlpha(usable and 1 or 0.4)
end

local function PaintAll()
    for id, b in pairs(buttons) do PaintButton(b, id) end
end

local function Evaluate()
    for _, t in ipairs(TOOLS) do
        local ok, why = T.Available(t.id)
        avail[t.id] = { ok = ok, why = why }
    end
end

local function BuildBar()
    if bar then return end
    bar = CreateFrame("Frame", "TwichUIMapTools", WorldMapFrame, "BackdropTemplate")
    bar:SetFrameStrata("HIGH")
    bar:EnableMouse(true)         -- a click on the bar is not a click on the map
    bar:Hide()
    for _, t in ipairs(TOOLS) do
        local b = NewButton(bar, t.id)
        b.icon:SetTexture(ICON_PATH .. t.icon)
        b:SetScript("OnClick", function() T.Click(t.id) end)
        buttons[t.id] = b
    end
    local fb = NewButton(bar, "filter")
    fb.icon:SetTexture(ICON_PATH .. "filter")
    fb:SetScript("OnClick", function() T.ToggleFilter() end)
    buttons.filter = fb
    local hb = NewButton(bar, "help")
    hb.icon:SetTexture(ICON_PATH .. HELP.icon)
    hb:SetScript("OnClick", function() T.ToggleHelp() end)
    buttons.help = hb
    -- keyboard: only while a tool or the help is up (see UpdateKeys); every key but Esc goes on to the game
    keys = CreateFrame("Frame", nil, bar)
    keys:SetSize(1, 1)
    keys:SetPoint("TOPLEFT")
    keys:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and (armed or helpOpen) then
            pcall(self.SetPropagateKeyboardInput, self, false)   -- this Esc is ours: the map stays open
            if armed then T.Cancel() else T.CloseHelp() end
        else
            pcall(self.SetPropagateKeyboardInput, self, true)
        end
    end)
end

-- Where the strip and the help sit: the top left of the map's canvas, below the floor list, clear of the top right where
-- the recent-pings list and the game's buttons are. The once-only note hangs from the bar itself, to point at it.
local function Under(f)
    f:ClearAllPoints()
    if f == callout then
        f:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -3)
    else
        f:SetPoint("TOPLEFT", WorldMapFrame:GetCanvasContainer(), "TOPLEFT", 4, -30)
    end
end

local BUTTON_W = 6 + ICON + 6
local SEARCH_CRUMBS = 220                                 -- room left for the breadcrumbs when the search field is on

-- The buttons in a row, and the bar in the header: its right end at the right end of the navigation bar (the breadcrumbs
-- fill it from the left), so it takes the empty stretch beside them. Without a navigation bar (this client or another
-- addon changed the header) it sits at the top left of the canvas, as the strip does.
local function LayoutBar()
    if not bar then return end
    local pad = bar.pad or Skin(bar)
    local x = pad + 2
    if buttons.nav then buttons.nav:SetShown(NavOn()) end   -- Navigate only while Navigation is on
    local filter = FilterOn()
    if buttons.filter then buttons.filter:SetShown(filter) end   -- the NPC filter only while Vendors and trainers is on
    if not filter and R.NpcFilterMenu then R.NpcFilterMenu.Close() end
    -- the NPC search field (npcs/SearchBar.lua), when it is chosen, to the left of the buttons: it takes what the
    -- navigation bar has left after the buttons and some room for the breadcrumbs, and is put away when that is too little
    local S = R.NpcSearchBar
    if S then
        local nav = WorldMapFrame.NavBar
        local room
        if nav and nav.GetWidth then
            local count = 4 + (NavOn() and 1 or 0) + (filter and 1 or 0)
            room = nav:GetWidth() - 6 - (count * (BUTTON_W + GAP) + pad * 2 + 4 + 4) - SEARCH_CRUMBS
        end
        -- the search is an extra: a fault in it is reported and the bar is laid out without it
        local ok, nx = pcall(S.Layout, bar, x, pad, GAP, room)
        if ok and type(nx) == "number" then x = nx
        elseif not ok then R.Fault("map tools search", nx) end
    end
    for _, id in ipairs({ "pin", "group", "ping", "nav", "filter", "help" }) do
        local b = buttons[id]
        if b and (id ~= "nav" or NavOn()) and (id ~= "filter" or filter) then
            b:ClearAllPoints()
            b:SetPoint("LEFT", bar, "LEFT", x, 0)
            b:SetWidth(BUTTON_W)
            b.icon:ClearAllPoints()
            b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
            b:Show()
            x = x + BUTTON_W + GAP
        end
    end
    bar:SetSize(x - GAP + pad + 2, BUTTON_H + pad * 2)
    bar:ClearAllPoints()
    local nav = WorldMapFrame.NavBar
    if nav then
        bar:SetPoint("RIGHT", nav, "RIGHT", -6, 0)
        bar:SetFrameLevel((nav:GetFrameLevel() or 1) + 5)   -- above the header's own art
    else
        bar:SetPoint("TOPLEFT", WorldMapFrame:GetCanvasContainer(), "TOPLEFT", 4, -30)
    end
    PaintAll()
end

local function BuildStrip()
    if strip then return end
    strip = CreateFrame("Frame", nil, WorldMapFrame, "BackdropTemplate")
    strip:SetFrameStrata("HIGH")
    strip:EnableMouse(true)
    strip:Hide()
    strip.accent = Solid(strip, "ARTWORK", Pal().teal, 1)
    strip.text = PL.Text(strip, "GameFontNormalSmall", "meta")
    strip.text:SetWordWrap(false)
    Paint(strip.text, Pal().text)
end

local function ShowStrip(text)
    BuildStrip()
    local pad = strip.pad or Skin(strip)
    strip.text:SetText(text)
    strip.accent:ClearAllPoints()
    strip.accent:SetPoint("TOPLEFT", strip, "TOPLEFT", pad, -pad)
    strip.accent:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", pad, pad)
    strip.accent:SetWidth(3)
    strip.text:ClearAllPoints()
    strip.text:SetPoint("LEFT", strip, "LEFT", pad + 9, 0)
    local w = math.ceil(strip.text:GetStringWidth() or 200)
    strip:SetSize(w + pad * 2 + 14, 18 + pad * 2)
    Under(strip)
    strip:Show()
end

local function HideStrip() if strip and strip:IsShown() then strip:Hide() end end

local function UpdateKeys()
    if not keys then return end
    local want = (armed ~= nil or helpOpen) and bar and bar:IsShown() and not (InCombatLockdown and InCombatLockdown())
    if want then pcall(keys.SetPropagateKeyboardInput, keys, true) end   -- every key goes on until Esc is pressed
    keys:EnableKeyboard(want and true or false)
end

---------------------------------------------------------------------------
-- The help panel
---------------------------------------------------------------------------
local helpRows = {}

local function BuildHelp()
    if help then return end
    help = CreateFrame("Frame", "TwichUIMapToolsHelp", WorldMapFrame, "BackdropTemplate")
    help:SetFrameStrata("HIGH")
    help:EnableMouse(true)
    help:Hide()
    help.title = PL.Text(help, "GameFontNormalSmall", "meta")
    help.title:SetText("Map tools")
    help.close = CreateFrame("Button", nil, help)
    help.close.label = PL.Text(help.close, "GameFontNormalSmall", "meta")
    help.close.label:SetText("Close")
    help.close.label:SetPoint("CENTER")
    help.close:SetScript("OnClick", function() T.CloseHelp() end)
    help.close:SetScript("OnEnter", function(self) Paint(self.label, Pal().tealHi) end)
    help.close:SetScript("OnLeave", function(self) Paint(self.label, Pal().stone) end)
    help.foot = PL.Text(help, "GameFontNormalSmall", "meta")
    help.foot:SetWordWrap(true)
    help.foot:SetJustifyV("TOP")
    for i, t in ipairs(TOOLS) do
        local row = {}
        row.icon = help:CreateTexture(nil, "ARTWORK")
        row.icon:SetTexture(ICON_PATH .. t.icon)
        row.icon:SetSize(ICON, ICON)
        row.name = PL.Text(help, "GameFontNormalSmall", "name")
        row.name:SetWordWrap(false)
        row.how = PL.Text(help, "GameFontNormalSmall", "meta")
        row.how:SetWordWrap(false)
        helpRows[i] = row
    end
end

local HELP_WIDTH = 300

local function LayoutHelp()
    local pad = help.pad or Skin(help)
    local size = PL.Get("textSize")
    local line = math.ceil(size * 1.25)
    local rowH = line * 2 + 8
    local width = math.floor(HELP_WIDTH * size / PL.DEFAULTS.textSize + 0.5)
    local container = WorldMapFrame:GetCanvasContainer()
    local room = container and container:GetWidth() or 0
    if room > 0 then width = math.min(width, math.max(220, math.floor(room * 0.45))) end   -- clear of the recent list
    help:SetWidth(width)
    help.title:ClearAllPoints()
    help.title:SetPoint("TOPLEFT", help, "TOPLEFT", pad + 6, -pad - 2)
    Paint(help.title, PL.palette.gold)
    help.close:ClearAllPoints()
    help.close:SetPoint("TOPRIGHT", help, "TOPRIGHT", -pad - 4, -pad - 2)
    help.close:SetSize(44, line)
    Paint(help.close.label, Pal().stone)
    local y = -(pad + line + 8)
    for i, row in ipairs(T.HelpRows()) do
        local r = helpRows[i]
        r.icon:ClearAllPoints()
        r.icon:SetPoint("TOPLEFT", help, "TOPLEFT", pad + 6, y - 2)
        r.name:ClearAllPoints()
        r.name:SetPoint("TOPLEFT", help, "TOPLEFT", pad + 6 + ICON + 8, y)
        r.name:SetPoint("RIGHT", help, "RIGHT", -(pad + 6), 0)
        r.name:SetText(row.name)
        Paint(r.name, Pal().text)
        r.how:ClearAllPoints()
        r.how:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -1)
        r.how:SetPoint("RIGHT", help, "RIGHT", -(pad + 6), 0)
        r.how:SetText(row.how .. " " .. row.shortcut .. ".")
        Paint(r.how, Pal().textDim)
        local a = avail[row.id]
        local usable = not a or a.ok
        r.icon:SetDesaturated(not usable)
        r.icon:SetAlpha(usable and 1 or 0.4)
        y = y - rowH
        r.icon:Show(); r.name:Show(); r.how:Show()
    end
    for i = #T.HelpRows() + 1, #helpRows do   -- a tool not offered now (Navigate while Navigation is off)
        local r = helpRows[i]
        r.icon:Hide(); r.name:Hide(); r.how:Hide()
    end
    help.foot:ClearAllPoints()
    help.foot:SetPoint("TOPLEFT", help, "TOPLEFT", pad + 6, y - 2)
    help.foot:SetWidth(width - (pad + 6) * 2)
    help.foot:SetText("Esc, or the same button again, cancels a tool. The group tools need a party or raid. Shortcuts can be changed in the Pins and Pings options (/tui).")
    Paint(help.foot, Pal().stone)
    help:SetHeight(-y + (help.foot:GetStringHeight() or 30) + pad + 8)
end

---------------------------------------------------------------------------
-- The note shown once
---------------------------------------------------------------------------
local function BuildCallout()
    if callout then return end
    callout = CreateFrame("Frame", "TwichUIMapToolsNote", WorldMapFrame, "BackdropTemplate")
    callout:SetFrameStrata("HIGH")
    callout:EnableMouse(true)
    callout:Hide()
    callout.title = PL.Text(callout, "GameFontNormalSmall", "name")
    callout.title:SetText("Map tools")
    callout.body = PL.Text(callout, "GameFontNormalSmall", "meta")
    callout.body:SetWordWrap(true)
    callout.body:SetJustifyV("TOP")
    callout.body:SetText("Add personal pins, share locations, or ping your group. Use these buttons or hover to learn shortcuts.")
    callout.ok = CreateFrame("Button", nil, callout)
    callout.ok.fill = Solid(callout.ok, "BACKGROUND", Pal().tealLo, 0.9)
    callout.ok.fill:SetAllPoints()
    callout.ok.label = PL.Text(callout.ok, "GameFontNormalSmall", "meta")
    callout.ok.label:SetText("Got it")
    callout.ok.label:SetPoint("CENTER")
    callout.ok:SetScript("OnClick", function() T.DismissIntro() end)
    local hl = Solid(callout.ok, "HIGHLIGHT", Pal().tealHi, 0.2)
    hl:SetAllPoints()
end

local function ShowCallout()
    BuildCallout()
    local pad = callout.pad or Skin(callout)
    local container = WorldMapFrame:GetCanvasContainer()
    local room = container and container:GetWidth() or 0
    local width = room > 0 and math.min(250, math.max(200, math.floor(room * 0.45))) or 250   -- clear of the recent list
    callout:SetWidth(width)
    callout.title:ClearAllPoints()
    callout.title:SetPoint("TOPLEFT", callout, "TOPLEFT", pad + 6, -pad - 4)
    Paint(callout.title, PL.palette.gold)
    callout.body:ClearAllPoints()
    callout.body:SetPoint("TOPLEFT", callout.title, "BOTTOMLEFT", 0, -4)
    callout.body:SetWidth(width - (pad + 6) * 2)
    Paint(callout.body, Pal().text)
    local bodyH = callout.body:GetStringHeight() or 30
    local titleH = callout.title:GetStringHeight() or 14
    callout.ok:ClearAllPoints()
    callout.ok:SetSize(64, 20)
    callout.ok:SetPoint("BOTTOMRIGHT", callout, "BOTTOMRIGHT", -(pad + 6), pad + 6)
    Paint(callout.ok.label, Pal().text)
    callout:SetHeight(pad * 2 + 4 + titleH + 4 + bodyH + 8 + 20 + 6)
    Under(callout)
    callout:Show()
    calloutSession = true
end

local function HideCallout() if callout and callout:IsShown() then callout:Hide() end end

-- Shown once per session until it is acknowledged (Got it, or using any control on the bar), never while the strip or the
-- help is under the bar. It does not have to be dismissed to use the map.
local function MaybeShowCallout()
    if IntroSeen() or calloutSession or armed or helpOpen then return end
    if not (bar and bar:IsShown()) then return end
    ShowCallout()
end

function T.DismissIntro()
    MarkIntroSeen()
    HideCallout()
end

---------------------------------------------------------------------------
-- States: arming, cancelling, help, folding
---------------------------------------------------------------------------
function T.CloseHelp()
    if not helpOpen then return false end
    helpOpen = false
    if help then help:Hide() end
    if bar then PaintAll() end
    UpdateKeys()
    return true
end

-- Puts the armed tool away. Returns whether one was armed.
function T.Cancel()
    if not armed then return false end
    armed = nil
    stats.cancels = stats.cancels + 1
    HideStrip()
    if bar then PaintAll() end
    UpdateKeys()
    return true
end

-- Arms a tool (the toolbar button's click). Returns whether it is armed.
function T.Arm(id)
    if not (installed and bar and bar:IsShown() and BY_ID[id]) then return false end
    MarkIntroSeen(); HideCallout()
    local ok, why = T.Available(id)
    if not ok then
        Evaluate(); PaintAll()
        Say(why)
        return false
    end
    T.CloseHelp()
    if R.NpcFilterMenu then R.NpcFilterMenu.Close() end
    if R.NpcSearchBar then R.NpcSearchBar.Close() end   -- the search list and a tool don't share the map's attention
    if PM.Disarm then PM.Disarm() end        -- the older "Place a pin" and "Ping the map" arms: one armed click at a time
    if V and V.Disarm then V.Disarm() end
    armed = id
    stats.arms = stats.arms + 1
    ShowStrip(BY_ID[id].prompt)
    PaintAll()
    UpdateKeys()
    return true
end

-- A click on a tool's button: arms it, or puts it away when it is the armed one.
function T.Click(id)
    if not (installed and bar and bar:IsShown() and BY_ID[id]) then return false end
    if armed == id then
        MarkIntroSeen(); HideCallout()
        T.Cancel()
        return false
    end
    return T.Arm(id)
end

function T.ToggleHelp()
    if not (installed and bar and bar:IsShown()) then return false end
    MarkIntroSeen(); HideCallout()
    if helpOpen then T.CloseHelp() return false end
    T.Cancel()
    if R.NpcFilterMenu then R.NpcFilterMenu.Close() end
    if R.NpcSearchBar then R.NpcSearchBar.Close() end
    BuildHelp()
    Evaluate()
    helpOpen = true
    LayoutHelp()
    Under(help)
    help:Show()
    PaintAll()
    UpdateKeys()
    return true
end

-- The NPC filter button: opens the menu, or closes it. Opening puts away what shouldn't share the map's attention with it
-- (an armed tool, the help, the search list). Changes no filter by itself.
function T.ToggleFilter()
    local FM = R.NpcFilterMenu
    if not (installed and bar and bar:IsShown() and buttons.filter and FM) then return false end
    MarkIntroSeen(); HideCallout()
    if FM.IsOpen() then
        FM.Close()
        return false
    end
    T.Cancel()
    T.CloseHelp()
    if R.NpcSearchBar then R.NpcSearchBar.Close() end
    local opened = FM.Open(buttons.filter)
    PaintAll()
    return opened
end

-- The buttons painted again (the filter menu closed by itself: the button is lit only while it is open).
function T.Repaint()
    if bar then PaintAll() end
end

---------------------------------------------------------------------------
-- The click
---------------------------------------------------------------------------
-- The map's own canvas click, before the others. It takes one thing: a plain left-click while a tool is armed. A click
-- that is another handler's (a shortcut) is left to it, and puts the tool away so nothing stays armed unseen.
local function OnCanvasClick(_, button, cx, cy)
    if not (installed and armed) then return false end
    local plain = not (IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown())
    if not (button == "LeftButton" and plain) then
        if PL.Matches("localClick", button) or PL.Matches("partyClick", button) or PG.Matches(button) then T.Cancel() end
        return false
    end
    local id = armed
    local ok, why = T.Available(id)   -- asked again now: the group may have changed since the button was pressed
    if not ok then
        T.Cancel()
        Say(why)
        return true
    end
    local done, reason
    if id == "nav" then
        local map, x, y = PM.ClickPlace(cx, cy)
        local why
        done, why = R.Nav.StartAt(map, x, y, nil, "map")
        if done then stats.navigated = (stats.navigated or 0) + 1 else Say(why) reason = "unsupported-map" end
    elseif id == "ping" then
        done, reason = V.PingAt(cx, cy)
        if done then stats.pinged = stats.pinged + 1 end
    else
        done, reason = PM.PlacePin(id == "group" and "party" or "local", cx, cy)
        if done then stats.placed = stats.placed + 1 end
    end
    if done then
        T.Cancel()    -- placed, or handed to the pin window: back to the plain map
    elseif reason == "unknown-map" or reason == "bad-coordinates" or reason == "unsupported-map" or reason == "rate" then
        stats.refused = stats.refused + 1   -- the helper said why; the tool stays armed so another spot can be tried
    else
        stats.refused = stats.refused + 1
        T.Cancel()
    end
    return true   -- this click was the tool's: the map doesn't also zoom, move or set a waypoint
end

local function Cursor()
    if armed then return CURSOR end
    return nil
end

---------------------------------------------------------------------------
-- Keeping up with the game
---------------------------------------------------------------------------
-- The group, the switches or the choices changed: what can be done, drawn again, and an armed tool that no longer can
-- be is put away with the reason. No rebuild.
function T.Update()
    if not installed then return end
    Evaluate()
    if armed and not avail[armed].ok then
        local why = avail[armed].why
        T.Cancel()
        Say(why)
    end
    if not (bar and bar:IsShown()) then return end
    PaintAll()
    if helpOpen and help then LayoutHelp() end
    for _, b in pairs(buttons) do
        if GameTooltip:IsOwned(b) then Tip(b) end
    end
end

-- The group changed. Other listeners of the same event (Party pins' session) may not have run yet, whatever order they were
-- registered in, so this looks one tick later; one look for any number of events.
local updateWaiting = false
local function UpdateSoon()
    if updateWaiting then return end
    updateWaiting = true
    C_Timer.After(0, function()
        updateWaiting = false
        T.Update()
    end)
end

-- Draws everything the map shows: the bar, drawn again if the look or the scale changed.
local function Show()
    if not (installed and MapOpen()) then return end
    BuildBar()
    if styleDirty then
        styleDirty = false
        for _, f in ipairs({ bar, strip, help, callout }) do if f then Skin(f) end end
    end
    Evaluate()
    LayoutBar()
    bar:Show()
    if armed then ShowStrip(BY_ID[armed].prompt) end
    if helpOpen then LayoutHelp(); Under(help); help:Show() end
    PaintAll()
    UpdateKeys()
    MaybeShowCallout()
end

local function Hide()
    -- nothing carries over a closed map: no armed tool, no help, no note on screen
    T.Cancel()
    T.CloseHelp()
    HideStrip()
    HideCallout()
    if R.NpcFilterMenu then R.NpcFilterMenu.Close() end
    if R.NpcSearchBar then R.NpcSearchBar.Hide() end   -- the search list closes, its focus is let go, what it picked out is let go
    if bar then bar:Hide() end
    UpdateKeys()
end

local function Build()
    if provider or not WorldMapFrame or not MapCanvasDataProviderMixin then return false end
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RemoveAllData() end
    function provider:RefreshAllData() end
    function provider:OnShow()
        C_Timer.After(0, function() Show() end)   -- after the map has finished laying itself out
    end
    function provider:OnHide() Hide() end
    function provider:OnCanvasSizeChanged()
        styleDirty = true    -- the map's size can change the scale the border is drawn at
        if bar and bar:IsShown() then Show() end
    end
    return true
end

-- On with Party pins and the toolbar choice, off without them. The game's own pins and handlers are not touched.
function T.Refresh()
    if not WorldMapFrame then return end
    local want = R:Enabled("partyPins") and PL.Pref("toolbar")
    if not Build() and not provider then return end
    if want and not installed then
        WorldMapFrame:AddDataProvider(provider)
        WorldMapFrame:AddCanvasClickHandler(OnCanvasClick, CLICK_PRIORITY)
        if WorldMapFrame.AddCursorHandler then WorldMapFrame:AddCursorHandler(Cursor, CLICK_PRIORITY) end
        R:On("GROUP_ROSTER_UPDATE", UpdateSoon)
        installed = true
        if MapOpen() then Show() end
    elseif not want and installed then
        Hide()
        WorldMapFrame:RemoveCanvasClickHandler(OnCanvasClick, CLICK_PRIORITY)
        if WorldMapFrame.RemoveCursorHandler then WorldMapFrame:RemoveCursorHandler(Cursor, CLICK_PRIORITY) end
        R:Off("GROUP_ROSTER_UPDATE", UpdateSoon)
        WorldMapFrame:RemoveDataProvider(provider)
        installed = false
    elseif installed and bar and bar:IsShown() then
        Show()   -- a choice changed (folded, a shortcut): the bar and its words again
        T.Update()
    end
end

-- Listeners that outlive being off do nothing then.
PN.OnChange(function() if installed then T.Update() end end)
MP.Subscribe(function(event) if installed and (event == "clear" or event == "prefs") then T.Update() end end)
PL.OnPrefChange(function() T.Refresh() end)
local function LookChanged()
    styleDirty = true
    if installed and bar and bar:IsShown() then Show() end
end
PL.Subscribe(LookChanged)
PL.MenuLook.Subscribe(LookChanged)
R.Profiles.OnApply("look", "map-tools", function()
    -- another profile: nothing armed or open from the last one, the choices as they are now
    T.Cancel(); T.CloseHelp()
    T.Refresh()
end)

R:On("PLAYER_LOGIN", T.Refresh)
R:On("ADDON_LOADED", function(name) if name == "Blizzard_WorldMap" then T.Refresh() end end)

-- Read only, for /tui diagnostics: states and counts, never a place.
function T.Snapshot()
    return {
        installed = installed, built = bar ~= nil, shown = bar ~= nil and bar:IsShown() or false,
        armed = armed, helpOpen = helpOpen,
        introSeen = IntroSeen(), keyboard = keys ~= nil and keys:IsKeyboardEnabled() or false,
        arms = stats.arms, placed = stats.placed, pinged = stats.pinged, cancels = stats.cancels, refused = stats.refused,
    }
end
