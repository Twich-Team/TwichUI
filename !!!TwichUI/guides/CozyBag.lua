-- TwichUI: Cozy Sleeping Bag guide, the controller
-- Reads the character's quest history, asks guides/CozyBagState.lua what it means, keeps what the window is looking at, and
-- makes, finds and removes this guide's map pins. The window (CozyBagWindow.lua) only draws what this says.
--
-- Quest history (WoW: Forever UI source, Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua):
--   C_QuestLog.IsQuestFlaggedCompleted(questID)   the character's own record of a turned-in quest, answered at once from
--                                                  what the client holds. There is no request call in this client's
--                                                  documentation (nothing like QueryQuestsCompleted), so nothing is asked for.
--   C_QuestLog.IsOnQuest(questID), C_QuestLog.ReadyForTurnIn(questID)   the quest log now.
--   events QUEST_LOG_UPDATE, QUEST_ACCEPTED, QUEST_REMOVED, QUEST_TURNED_IN.
-- Whether the history is complete the moment the world loads is not shown by the documentation, so nothing is concluded
-- until the world has been entered AND the first QUEST_LOG_UPDATE has come (or, failing that, a few seconds have passed):
-- until then the window says "Checking quest progress..." and shows no step as done or current. That wait is two events
-- listened to from login until the first of them has been answered, then none; there is no polling.
--
-- Lifecycle: while the window is closed, nothing listens and nothing runs. Opening it reads the history afresh (so a quest
-- finished while it was closed, or with TwichUI off, is already right) and listens for the four quest events, which only
-- note that a look is due; a burst of them is one look after COALESCE seconds, and the window is told only when something it
-- shows changed. Closing it stops the listening and cancels the look.
--
-- Nothing is saved but where the window sits and whether it is locked (TwichUIDB.ui.cozyBag = { locked, x, y }). Progress is
-- never saved: it is read from the game each time, so a profile change, an import or a different character cannot carry it.

local R = TwichUI
local D = R.CozyBagData
local ST = R.CozyBagState
local C = {}
R.CozyBag = C

local COALESCE = 0.2       -- seconds a burst of quest events waits to be one look
local HISTORY_WAIT = 3     -- seconds after entering the world before the history is trusted without a QUEST_LOG_UPDATE
local PIN_COLOR = "moss"
local PIN_PREFIX = "Cozy Bag: "
local EVENTS = { "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }

C.stats = { looks = 0, changes = 0, pinsMade = 0 }

---------------------------------------------------------------------------
-- What the window is looking at
---------------------------------------------------------------------------
local view = { following = true }   -- { id, following }; never saved
local result                        -- the last evaluation
local signature                     -- what the window showed last, to tell it only when it changed
local listeners = {}
local open = false
local token = 0                     -- bumped on close: a look queued earlier does nothing
local queued = false
local worldSeen, logSeen, historyReady = false, false, false

function C.OnChange(fn) listeners[#listeners + 1] = fn end

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Faction()
    local group = UnitFactionGroup and Plain(UnitFactionGroup("player"))
    if group == "Alliance" or group == "Horde" then return group end
    return nil
end

local reader = {
    completed = function(id) return C_QuestLog.IsQuestFlaggedCompleted(id) end,
    onQuest = function(id) return C_QuestLog.IsOnQuest(id) end,
    readyToTurnIn = function(id) return C_QuestLog.ReadyForTurnIn(id) end,
}
reader.ready = false

local function Reader()
    reader.ready = historyReady and C_QuestLog ~= nil and C_QuestLog.IsQuestFlaggedCompleted ~= nil
    return reader
end

local function Sign(r)
    if r.status ~= "ready" then return r.status end
    local parts = { r.status }
    for _, e in ipairs(r.steps) do parts[#parts + 1] = e.state .. (e.phase or "") .. (e.inferred and "i" or "") end
    return table.concat(parts, ",")
end

local function Tell()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok and R.Fault then R.Fault("cozy bag guide", err) end
    end
end

-- Looks at the history now. Returns whether anything the window shows changed.
local function Look()
    C.stats.looks = C.stats.looks + 1
    result = ST.Evaluate(D, Faction(), Reader())
    local id = ST.Select(view, result)
    local sign = Sign(result) .. "|" .. tostring(id) .. "|" .. tostring(view.following)
    if sign == signature then return false end
    signature = sign
    C.stats.changes = C.stats.changes + 1
    return true
end

function C.Result()
    if not result then Look() end
    return result
end

function C.View() return view end

-- A fresh reading of the chain that leaves what the window is looking at alone (no view, no signature, no Tell). The offer
-- (guides/CozyBagOffer.lua) asks this while the guide is closed, when `result` is not kept current. Same rules as Look.
function C.Progress() return ST.Evaluate(D, Faction(), Reader()) end

-- Whether a quest ID belongs to the chain (either side, optional step included): lets a listener drop every other turn-in
-- without reading anything.
local chainQuests = {}
for _, step in ipairs(D.steps) do chainQuests[step.quest] = true end
function C.IsChainQuest(id) return chainQuests[id] == true end

-- Told once the history can be trusted (Trust), and when the window opens or closes. Nothing polls.
local readyWatchers, openWatchers = {}, {}
function C.OnReady(fn) readyWatchers[#readyWatchers + 1] = fn end
function C.OnOpenChange(fn) openWatchers[#openWatchers + 1] = fn end

local function Call(list)
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn)
        if not ok and R.Fault then R.Fault("cozy bag guide", err) end
    end
end

function C.SelectedStep()
    local r = C.Result()
    local at = view.id and ST.IndexOf(r, view.id)
    return at and r.steps[at].step, at
end

function C.Pick(id)
    C.Result()
    if ST.Pick(view, result, id) then
        Look()
        Tell()
    end
end

function C.Follow()
    ST.Follow(view)
    Look()
    Tell()
end

local function Due()
    if not open or queued then return end
    queued = true
    local mine = token
    C_Timer.After(COALESCE, function()
        if mine ~= token then return end
        queued = false
        if Look() then Tell() end
    end)
end

---------------------------------------------------------------------------
-- Waiting for the history
---------------------------------------------------------------------------
local function Trust()
    if historyReady then return end
    historyReady = true
    R:Off("PLAYER_ENTERING_WORLD", C.OnWorld)
    R:Off("QUEST_LOG_UPDATE", C.OnLog)
    if open and Look() then Tell() end    -- a closed guide reads the history when it opens
    Call(readyWatchers)
end

function C.OnLog()
    logSeen = true
    if worldSeen then Trust() end
end

function C.OnWorld()
    if worldSeen then return end
    worldSeen = true
    if logSeen then Trust() return end
    C_Timer.After(HISTORY_WAIT, Trust)
end

function C.HistoryReady() return historyReady end

---------------------------------------------------------------------------
-- Opening and closing (the window calls these as it shows and hides)
---------------------------------------------------------------------------
local function OnQuestEvent() Due() end

function C.Opened()
    if open then return end
    open = true
    token = token + 1
    queued = false
    for _, e in ipairs(EVENTS) do R:On(e, OnQuestEvent) end
    if Look() then Tell() end
    Call(openWatchers)
end

function C.Closed()
    if not open then return end
    open = false
    token = token + 1
    queued = false
    for _, e in ipairs(EVENTS) do R:Off(e, OnQuestEvent) end
    -- the next opening starts by following the detected step
    view = { following = true }
    signature = nil
    Call(openWatchers)
end

function C.IsOpen() return open end

---------------------------------------------------------------------------
-- Where the window sits and whether it moves (the only things saved)
---------------------------------------------------------------------------
C.POSITION_LIMIT = 8192
C.DEFAULT_POSITION = { -330, 60 }   -- from the centre of the screen: left of the middle, a little above it

local function Finite(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end
local function Usable(v) return Finite(v) and math.abs(v) <= C.POSITION_LIMIT end

local function Ui(create)
    local db = TwichUIDB
    if type(db) ~= "table" then return nil end
    if type(db.ui) ~= "table" then
        if not create then return nil end
        db.ui = {}
    end
    local t = db.ui.cozyBag
    if type(t) ~= "table" then
        if not create then return nil end
        t = {}
        db.ui.cozyBag = t
    end
    return t
end

function C.Locked()
    local t = Ui(false)
    return t ~= nil and t.locked == true
end

function C.SetLocked(on)
    local t = Ui(true)
    if not t then return false end
    t.locked = on == true or nil
    Tell()
    return true
end

-- The compact view: the same window with the intro, the step list and the housekeeping buttons folded away.
function C.Compact()
    local t = Ui(false)
    return t ~= nil and t.compact == true
end

function C.SetCompact(on)
    local t = Ui(true)
    if not t then return false end
    t.compact = on == true or nil
    Tell()
    return true
end

function C.Position()
    local t = Ui(false)
    if t and Usable(t.x) and Usable(t.y) then return t.x, t.y, true end
    return C.DEFAULT_POSITION[1], C.DEFAULT_POSITION[2], false
end

function C.SetPosition(x, y)
    if x ~= nil and not (Usable(x) and Usable(y)) then return false end
    local t = Ui(x ~= nil)
    if t then
        if x == nil then t.x, t.y = nil, nil else t.x, t.y = x, y end
    end
    Tell()
    return true
end

function C.ResetPosition() return C.SetPosition(nil, nil) end

---------------------------------------------------------------------------
-- Map pins: ordinary saved pins (pins/Pins.lua), tagged so this guide can find and remove its own
---------------------------------------------------------------------------
local PN = R.Pins
if PN then PN.guideNames[D.id] = "Cozy Sleeping Bag guide" end

local function Pins()
    if not (PN and R:Enabled("partyPins")) then
        return nil, "Pins are turned off. Turn on Party pins in TwichUI's settings to pin guide places."
    end
    return PN
end

function C.PinTag(step, place) return ("%s:%s:%d"):format(D.id, step.id, place) end

-- The saved pin for one place of a step, or nil.
function C.PinFor(step, place)
    if not PN then return nil end
    return PN.FindGuide(C.PinTag(step, place))
end

local function PinName(step, place)
    local p = step.places[place]
    if #step.places > 1 then return PIN_PREFIX .. (p.label:match("^[^,]+") or step.title) end
    return PIN_PREFIX .. step.title
end

-- Pins one place of a step, or finds the pin made for it before. Never starts navigation, sends nothing and leaves other pins
-- alone. Returns the pin, "made" or "existing"; or nil and a sentence.
function C.PinPlace(step, place)
    local pins, why = Pins()
    if not pins then return nil, why end
    local p = step and step.places and step.places[place]
    if not p then return nil, "That place isn't part of this step." end
    local existing = C.PinFor(step, place)
    if existing then return existing, "existing" end
    local pin, reason = pins.AddLocal({
        map = p.map, x = pins.Quantize(p.x / 100), y = pins.Quantize(p.y / 100),
        name = PinName(step, place), color = PIN_COLOR, guide = C.PinTag(step, place),
    })
    if not pin then return nil, pins.Reason(reason) end
    C.stats.pinsMade = C.stats.pinsMade + 1
    return pin, "made"
end

-- Pins every place of a step. Returns how many were made, how many were already there, and the first problem.
function C.PinStep(step)
    local made, existing, problem = 0, 0, nil
    local function Run()
        for i = 1, #step.places do
            local pin, how = C.PinPlace(step, i)
            if not pin then problem = problem or how
            elseif how == "made" then made = made + 1
            else existing = existing + 1 end
        end
    end
    if PN then PN.Batch(Run) else Run() end
    return made, existing, problem
end

-- Brings an existing pin forward on the world map (the map's own "Show on map"). Returns true, or false and a sentence.
function C.ShowPlace(step, place)
    local pins, why = Pins()
    if not pins then return false, why end
    local pin = C.PinFor(step, place)
    if not pin then return false, "Pin this place first." end
    if not (R.PinsMap and R.PinsMap.ShowOnMap) then return false, "The world map isn't ready yet." end
    local entry = { kind = "local", pin = pin, token = "local:" .. pin.id }
    local ok, reason = pins.Can("show", entry)
    if not ok then return false, reason end
    R.PinsMap.ShowOnMap(entry)
    return true
end

function C.CanNavigate() return R.Nav ~= nil and R.Nav.Enabled and R.Nav.Enabled() end

-- A walking route to a place (Navigation, when it is on). Only when asked; nothing else starts it.
function C.Navigate(step, place)
    if not C.CanNavigate() then return false, "Navigation is turned off. Turn it on in TwichUI's settings (Navigation)." end
    local p = step and step.places and step.places[place]
    if not p then return false, "That place isn't part of this step." end
    local name = PinName(step, place):sub(#PIN_PREFIX + 1)
    return R.Nav.StartAt(p.map, p.x / 100, p.y / 100, name, "guide")
end

-- The pins this guide made that are still there (the tag is the proof; a pin of yours without it is never listed).
function C.OwnPins()
    return PN and PN.GuidePins(D.id .. ":") or {}
end

-- Removes the guide's pins that aren't kept (a kept pin is yours to unprotect first). `only` is a set of pin ids from the
-- confirmation, so a pin made since the question isn't swept up. Returns how many were removed and how many kept ones remain.
function C.RemoveOwnPins(only)
    if not PN then return 0, 0 end
    local removed, kept = 0, 0
    PN.Batch(function()
        for _, pin in ipairs(C.OwnPins()) do
            if only == nil or only[pin.id] then
                if PN.IsKept(pin) then kept = kept + 1
                else
                    local ok = PN.RemoveLocal(pin.id)
                    if ok then removed = removed + 1 end
                end
            end
        end
    end)
    return removed, kept
end

-- What a removal would cover now: a set of ids, a count, and how many kept pins it would leave.
function C.OwnPinScope()
    local ids, n, kept = {}, 0, 0
    for _, pin in ipairs(C.OwnPins()) do
        if PN.IsKept(pin) then kept = kept + 1 else ids[pin.id] = true; n = n + 1 end
    end
    return ids, n, kept
end

---------------------------------------------------------------------------
-- Start-up: only the wait for the history, until it is over
---------------------------------------------------------------------------
R:On("PLAYER_ENTERING_WORLD", C.OnWorld)
R:On("QUEST_LOG_UPDATE", C.OnLog)

-- Read only, for /tui diagnostics and the tests: counts and states, never names or places.
function C.Snapshot()
    return { open = open, historyReady = historyReady, queued = queued, looks = C.stats.looks, changes = C.stats.changes,
        pinsMade = C.stats.pinsMade, following = view.following, status = result and result.status or "unread" }
end
