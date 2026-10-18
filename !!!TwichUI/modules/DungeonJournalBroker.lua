-- TwichUI: Forever Dungeon Journal on a data bar
-- A LibDataBroker data source, "TwichUI Dungeon Journal", for a data bar (for example EllesmereUI's "Broker
-- Plugin" block). Icon only; a click opens the Forever Dungeon Journal if it is closed and closes it if it is
-- open. Nothing else: no text, no menu.
-- The journal is its own addon (ForeverDungeonJournal, /fj). It publishes a global
-- ForeverDungeonJournal_Toggle, which its own minimap button also calls, and its window is the global
-- ForeverDungeonJournalFrame, built at its PLAYER_LOGIN. Nothing else of the journal is touched.
-- Made only when the journal is loaded and a data bar addon provides LibDataBroker, and only once the
-- switch is on (Switches.lua). TwichUI doesn't bundle LibDataBroker: nothing happens without it.
-- A data object can't be taken away again, so turned off it does nothing when clicked until the next reload.

local R = TwichUI
local B = {}
R.DungeonJournalBroker = B

local NAME = "TwichUI Dungeon Journal"
local ICON = R.PATH .. [[media\textures\dungeon-journal-broker]]   -- a leather-bound journal with a gate (64 x 64)
local obj
local loggedIn = false

local function Enabled() return R:Enabled("dungeonJournalBroker") end

-- The journal's own frame, once it has built it. nil before its PLAYER_LOGIN, which can run after ours (TwichUI
-- loads first), so a click checks it rather than the broker's creation.
local function Frame() return _G.ForeverDungeonJournalFrame end

-- Whether the journal is loaded: its toggle is defined from the start of its load.
function B.Ready()
    return type(_G.ForeverDungeonJournal_Toggle) == "function"
end

function B.IsOpen()
    local frame = Frame()
    return frame ~= nil and frame:IsShown() and true or false
end

local function Color()
    local K = R.ChronicleStyle and R.ChronicleStyle.color
    return K or { text = { 1, 1, 1 }, textDim = { 0.8, 0.8, 0.8 }, stone = { 0.6, 0.6, 0.6 }, gold = { 0.8, 0.7, 0.3 } }
end

local function OnTooltipShow(tip)
    local K = Color()
    tip:AddLine("Forever Dungeon Journal", 1, 1, 1)
    if not B.Ready() or type(Frame()) ~= "table" then
        tip:AddLine("The journal's window isn't ready yet.", K.stone[1], K.stone[2], K.stone[3])
        return
    end
    if not Enabled() then
        tip:AddLine("Turned off in TwichUI. Clicks do nothing until the next reload.", K.stone[1], K.stone[2], K.stone[3])
        return
    end
    tip:AddDoubleLine("Window", B.IsOpen() and "Open" or "Closed", K.textDim[1], K.textDim[2], K.textDim[3], K.text[1], K.text[2], K.text[3])
    tip:AddLine(" ")
    tip:AddLine(B.IsOpen() and "Click to close" or "Click to open", K.gold[1], K.gold[2], K.gold[3])
end

-- Opens or closes the journal. Does nothing when the switch is off or the journal isn't ready; it never
-- builds anything itself.
function B.Toggle()
    if not Enabled() or not B.Ready() or type(Frame()) ~= "table" then return end
    _G.ForeverDungeonJournal_Toggle()
end

-- Once, when the journal is loaded and a data bar addon provides LibDataBroker, and only while the switch is on.
function B.Refresh()
    if obj or not Enabled() or not B.Ready() then return end
    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not LDB then return end
    obj = LDB:NewDataObject(NAME, {
        type = "data source",   -- not "launcher": many data bars show the icon for a data source only
        label = "Dungeon Journal",
        text = "",
        icon = ICON,
        OnClick = B.Toggle,
        OnTooltipShow = OnTooltipShow,
    })
end

-- Whether it is on a data bar's list (false without the journal, the switch, or LibDataBroker).
function B.Available() return obj ~= nil end

R:On("PLAYER_LOGIN", function()
    loggedIn = true
    B.Refresh()
end)
-- A data bar addon loaded on demand after login can still bring LibDataBroker.
R:On("ADDON_LOADED", function() if loggedIn then B.Refresh() end end)
