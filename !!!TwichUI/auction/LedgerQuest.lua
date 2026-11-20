-- Quest reward evidence for the gold ledger. Never turns in a quest, never reads a balance and never records money.
-- Forever UI source (QuestLogDocumentation.lua): QUEST_TURNED_IN(questID, xpReward, moneyReward) is a synchronous event that carries the
-- exact copper the turn-in pays. That amount is offered to the ledger as EVIDENCE; Ledger.lua attaches it only to a balance change of
-- exactly that amount (the same frame, or the single unclassified entry of that amount within a few seconds), and a gain that differs,
-- is shared by another equal entry, or never arrives stays Unclassified. Quest items, experience and reputation are not gold and are
-- not read. The quest's title (when the client still knows it) becomes the entry's short note; no quest id is kept.
local R = TwichUI
local Q = {}
R.QuestGold = Q

local active, serial = false, 0
local stats = { reported = 0, ignored = 0 }

local function Plain(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function Whole(v, lo, hi)
    v = Plain(v)
    if type(v) ~= "number" or not tostring(v):find("^[%d%.eE%+%-]+$") or v < lo or v > hi or math.floor(v) ~= v then return nil end
    return v
end

local function Title(questID)
    local C = C_QuestLog
    if not (C and C.GetTitleForQuestID) then return nil end
    local ok, title = pcall(C.GetTitleForQuestID, questID)
    title = ok and Plain(title) or nil
    return type(title) == "string" and title ~= "" and title or nil
end

local function OnTurnedIn(questID, _, money)
    local L = R.Ledger
    questID, money = Whole(questID, 1, 2147483647), Whole(money, 1, L and L.MAX_MONEY or 9007199254740991)
    if not (active and L and questID and money) then stats.ignored = stats.ignored + 1 return end   -- a turn-in that pays no gold proves nothing
    serial = serial + 1
    local ok, err = pcall(L.Evidence, { kind = "quest", amount = money, note = Title(questID), corr = "quest:" .. questID .. ":" .. serial })
    if ok then stats.reported = stats.reported + 1 elseif R.Fault then R.Fault("quest gold", err) end
end

local listening = false
-- Safe to call any time: listens only while the ledger records.
function Q.Refresh()
    local on = R.Ledger and R.Ledger.Active() == true
    active = on
    if on and not listening then listening = true; R:On("QUEST_TURNED_IN", OnTurnedIn)
    elseif not on and listening then listening = false; R:Off("QUEST_TURNED_IN", OnTurnedIn) end
end

function Q.Snapshot() return { active = active, events = listening and 1 or 0, reported = stats.reported, ignored = stats.ignored } end

R:OnInit(Q.Refresh)
