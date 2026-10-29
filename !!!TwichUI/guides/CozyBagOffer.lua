-- TwichUI: Cozy Sleeping Bag guide, the invitation
-- Decides when to invite the player to the guide, and says so quietly: a small launcher button (CozyBagButton.lua) and, once,
-- a card (CozyBagNotice.lua) through the notification coordinator. It never opens the guide, pins, routes or waypoints,
-- sends nothing and plays no sound. The rule itself is CozyBagState.Offer (pure); this file reads the facts, keeps the
-- character's own record, and listens for the few things that can change the answer.
--
-- The answer is "available" when the character is at least D.level, the quest history can be trusted, the chain is not
-- finished (CozyBag.Progress, the guide's own model), the reward is not owned now, and no earlier look found it done. Not
-- knowing is never read as "not done": a history that has not loaded, or a faction that cannot be read, is "loading" or
-- "unknown" and offers nothing; it is asked again when the history arrives (CozyBag.OnReady), not by polling.
--
-- The record (TwichUIDB.ui.cozyBagOffer[guid], account-wide, never in a profile, never shared or published; Profiles.ACCOUNT
-- and TwichConfig.LOCAL name it), one small table per character with three separate booleans:
--   announced  the card was actually put on screen (set when it is shown, not when it is queued; never by a preview)
--   hidden     the player took the button away from its menu; it also ends the card for good
--   acquired   the chain was found done, or the item found owned, so selling or banking the item never re-opens the offer
-- Switching profiles, applying a layout, or turning the two switches off and on again changes none of it.
--
-- Events, while either switch is on and the bag is not known to be got: PLAYER_LEVEL_UP, PLAYER_ENTERING_WORLD (a loading
-- screen empties the card queue, so the card is asked for again) and QUEST_TURNED_IN, which is dropped at once unless the
-- quest is one of the chain's. A look is a few dozen quest and item reads, once per such event, coalesced.

local R = TwichUI
local D = R.CozyBagData
local ST = R.CozyBagState
local C = R.CozyBag
local O = {}
R.CozyBagOffer = O

local DELAY = { login = 8, level = 6, other = 3 }   -- seconds before asking for the card: after the zone, Welcome Back and training cards
local COALESCE = 0.5                                -- seconds a turn-in waits (the game's flag may follow the event)
local TTL = 90                                      -- seconds the card may wait for another card in its way

O.stats = { looks = 0, asked = 0, shown = 0 }

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

---------------------------------------------------------------------------
-- The character's record
---------------------------------------------------------------------------
local function Guid()
    local guid = UnitGUID and Plain(UnitGUID("player"))
    return type(guid) == "string" and guid or nil
end

-- This character's table; with create, made when there is none. Anything stored that is not a table is replaced only then.
local function Record(create)
    local db = TwichUIDB
    if type(db) ~= "table" then return nil end
    local guid = Guid()
    if not guid then return nil end
    if create then
        if type(db.ui) ~= "table" then db.ui = {} end
        if type(db.ui.cozyBagOffer) ~= "table" then db.ui.cozyBagOffer = {} end
        if type(db.ui.cozyBagOffer[guid]) ~= "table" then db.ui.cozyBagOffer[guid] = {} end
    end
    local all = db.ui and db.ui.cozyBagOffer
    local rec = type(all) == "table" and all[guid]
    return type(rec) == "table" and rec or nil
end

local function Flag(name)
    local rec = Record(false)
    return rec ~= nil and rec[name] == true
end

function O.Announced() return Flag("announced") end
function O.Hidden() return Flag("hidden") end
function O.Acquired() return Flag("acquired") end

-- Sets or clears one flag (cleared is stored as absent). Returns whether it could be kept.
local function SetFlag(name, on)
    local rec = Record(on)
    if not rec then return on ~= true end   -- clearing what was never there is already done
    local new = on == true or nil
    if rec[name] == new then return true end
    rec[name] = new
    return true
end

---------------------------------------------------------------------------
-- The facts
---------------------------------------------------------------------------
local knownLevel = 0   -- the highest level seen this session (PLAYER_LEVEL_UP can come before UnitLevel moves)

local function Level()
    local n = UnitLevel and Plain(UnitLevel("player"))
    if type(n) ~= "number" or n ~= n then n = 0 end
    n = math.max(n, knownLevel)
    return n > 0 and n or nil
end

-- True only when the game says the item is in the bags or bank. Zero, or no answer, proves nothing.
local function Owned()
    local count = C_Item and C_Item.GetItemCount and Plain(C_Item.GetItemCount(D.item, true))
    return type(count) == "number" and count > 0
end

local function Facts()
    local progress = C.Progress()
    local complete                                   -- nil unless the chain could be read (false is an answer, not a gap)
    if progress.status == "ready" then complete = progress.complete == true end
    return {
        level = Level(), historyReady = C.HistoryReady(), complete = complete,
        owned = Owned(), acquired = O.Acquired(),
    }
end

local state = { offer = false, reason = "loading" }   -- the last look; the button and the card's validity read this

-- The answer now, freshly looked at: { offer, reason }. Read only.
function O.Status()
    local offer, reason = ST.Offer(D, Facts())
    return { offer = offer, reason = reason }
end

function O.Reason() return state.reason end

---------------------------------------------------------------------------
-- What the answer asks for
---------------------------------------------------------------------------
local watchers = {}
function O.OnChange(fn) watchers[#watchers + 1] = fn end

local function Tell()
    for _, fn in ipairs(watchers) do
        local ok, err = pcall(fn)
        if not ok and R.Fault then R.Fault("cozy bag offer", err) end
    end
end

-- The card applies to this character now (it may already have been shown), and may still be asked for.
local function Applies() return R:Enabled("cozyBagNotice") and state.offer and not O.Hidden() end
local function Wanted() return Applies() and not O.Announced() end

-- The first-install setup is under way or waiting on a reload: the card holds back (the button does not). Put off
-- ("deferred") does not hold: the player has already said not now.
local function SetupOwed()
    local OB = R.Onboarding
    local st = OB and OB.State and OB.State()
    return st == "new" or st == "started" or st == "installing"
end

-- Whether the button may show: on, wanted, not taken away, and the guide not open (it would only repeat it).
function O.ButtonWanted()
    return R:Enabled("cozyBagButton") and state.offer and not O.Hidden() and not (C.IsOpen and C.IsOpen())
end

local token, scheduled = 0, false

local function Unschedule()
    token = token + 1
    scheduled = false
end

local function Present()
    if not Wanted() or SetupOwed() then return end
    local N = R.Notify
    if not N then return end
    O.stats.asked = O.stats.asked + 1
    N.Submit({ kind = "cozybag", id = "unlock", ttl = TTL, priority = N.PRIORITY.low, valid = Wanted, payload = {} })
end

local function Schedule(delay)
    if scheduled then return end
    scheduled = true
    local mine = token
    C_Timer.After(delay, function()
        if mine ~= token then return end
        scheduled = false
        Present()
    end)
end

-- Called by the card as it is put on screen for real; the only place `announced` is set.
function O.MarkAnnounced()
    O.stats.shown = O.stats.shown + 1
    SetFlag("announced", true)
end

local function CancelCard()
    Unschedule()
    if R.Notify then R.Notify.Cancel("cozybag") end
end

---------------------------------------------------------------------------
-- Looking again
---------------------------------------------------------------------------
local Want

-- origin: "login", "level" or anything else, for how long the card waits behind the cards a login or a level-up brings.
function O.Update(origin)
    O.stats.looks = O.stats.looks + 1
    local offer, reason = ST.Offer(D, Facts())
    state = { offer = offer, reason = reason }
    if reason == "complete" or reason == "owned" then SetFlag("acquired", true) end
    if Applies() then
        if Wanted() then Schedule(DELAY[origin] or DELAY.other) end
    else
        CancelCard()
    end
    Want()
    Tell()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local coalescing = false

local function Later(origin)
    if coalescing then return end
    coalescing = true
    C_Timer.After(COALESCE, function()
        coalescing = false
        O.Update(origin)
    end)
end

local function OnLevelUp(level)
    if type(level) == "number" and level == level and level > knownLevel then knownLevel = level end
    Later("level")
end

local function OnTurnIn(questID)
    if C.IsChainQuest(questID) then Later("quest") end
end

local function OnWorld() Later("login") end

local listening = {}

local function Listen(event, fn, on)
    if on and not listening[event] then
        listening[event] = fn
        R:On(event, fn)
    elseif not on and listening[event] then
        R:Off(event, listening[event])
        listening[event] = nil
    end
end

-- Listens only while there is something left to offer: a switch is on and the bag is not known to be got.
function Want()
    local any = (R:Enabled("cozyBagNotice") or R:Enabled("cozyBagButton")) and not O.Acquired()
    Listen("PLAYER_LEVEL_UP", OnLevelUp, any)
    Listen("PLAYER_ENTERING_WORLD", OnWorld, any)
    Listen("QUEST_TURNED_IN", OnTurnIn, any)
end

-- The switches' update (Switches.lua), and a profile change: listen or stop, then look. A card that no longer applies is
-- taken back; a button that no longer applies goes away.
function O.Refresh()
    if not (R:Enabled("cozyBagNotice") or R:Enabled("cozyBagButton")) then
        CancelCard()
        Want()
        Tell()
        return
    end
    Want()
    if C.HistoryReady() then O.Update("other") else Tell() end
end

---------------------------------------------------------------------------
-- The player's choices about the button
---------------------------------------------------------------------------
-- Takes the button away for this character (and with it the card), or brings it back. The switch is untouched.
function O.SetHidden(on)
    local kept = SetFlag("hidden", on == true)
    if not kept then return false end
    if C.HistoryReady() then O.Update("other") else Tell() end
    return true
end

-- Opens the guide through its own window. Returns true, or false and a sentence; opening is not completing anything and
-- hides nothing for good.
function O.OpenGuide()
    local W = R.CozyBagWindow
    if not (W and W.Show) then return false, "The guide isn't available this session." end
    local ok, err = pcall(W.Show)
    if not ok then
        if R.Fault then R.Fault("cozy bag guide", err) end
        return false, "The guide couldn't be opened just now. /tui bag tries again."
    end
    return true
end

---------------------------------------------------------------------------
-- Preview of the card (settings). Made-up text; nothing is recorded.
---------------------------------------------------------------------------
function O.PreviewCard()
    local N = R.Notify
    if not N then return false, "unknown" end
    return N.Preview("cozybag")
end

-- Read only, for /tui diagnostics and the tests: counts and states, never names.
function O.Snapshot()
    return {
        offer = state.offer, reason = state.reason, announced = O.Announced(), hidden = O.Hidden(), acquired = O.Acquired(),
        scheduled = scheduled, events = (listening.PLAYER_LEVEL_UP and 1 or 0) + (listening.PLAYER_ENTERING_WORLD and 1 or 0)
            + (listening.QUEST_TURNED_IN and 1 or 0), looks = O.stats.looks,
        asked = O.stats.asked, shown = O.stats.shown, level = Level() or 0,
    }
end

---------------------------------------------------------------------------
-- Start-up: nothing is read until the world is entered and the history can be trusted
---------------------------------------------------------------------------
C.OnReady(function() O.Update("login") end)
C.OnOpenChange(Tell)   -- the launcher steps aside while the guide is open

R:OnInit(function()
    Want()
    if C.HistoryReady() then O.Update("login") end
end)

-- (A profile change reaches the two switches through Switches.lua, which calls O.Refresh; the record is account-wide and stays.)
