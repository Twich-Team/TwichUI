-- Quest rewards as a ledger source (!!!TwichUI/auction/LedgerQuest.lua): QUEST_TURNED_IN is evidence for the exact gold it pays; the balance
-- change stays the only authority for the amount, and anything that does not match exactly stays Unclassified.
dofile(TESTS .. "harness.lua")
local function Check(v, m) if not v then error(m or "check failed", 2) end end
local function Same(a, b, m) if a ~= b then error((m or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local T0 = 20000 * 86400 + 43200

local function Client(opts)
    opts = opts or {}
    local c = MakeClient("Rich", { "!!!TwichUI" })
    c.TwichUIDB = { modules = { chronicle = false }, ui = { workshopEnabled = opts.on ~= false } }
    c.TwichUILedgerDB = opts.db
    c.MONO, c.MONEY = 100, 1000000
    c.GetServerTime = function() return T0 end
    c.GetTime = function() return c.MONO end
    c.GetMoney = function() return c.MONEY end
    c.C_QuestLog = { GetTitleForQuestID = function(id) return c.TITLES and c.TITLES[id] end }
    c.TITLES = { [5001] = "Wolves at the Gate", [5002] = "A | Pipe\nTitle" }
    for _, f in ipairs({ "WorkshopLauncher.lua", "auction/Ledger.lua", "auction/LedgerQuest.lua" }) do
        local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
    end
    c.LOADED["!!!TwichUI"] = true
    c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    c.L, c.Q = c.TwichUI.Ledger, c.TwichUI.QuestGold
    function c.Rec() return c.TwichUILedgerDB.chars["Rich - Forever"] end
    function c.Money(delta, tick) c.MONEY = c.MONEY + delta; if tick ~= false then c.MONO = c.MONO + 1 end; c.FireEvent("PLAYER_MONEY") end
    function c.Turn(id, xp, money) c.FireEvent("QUEST_TURNED_IN", id, xp, money) end
    return c
end

-- the source is defined: income only, with its words
do
    local c = Client()
    Same(c.L.SOURCES.quest.label, "Quest reward"); Same(c.L.SOURCES.quest.dir, 1); Same(c.L.SOURCES.quest.evidence, "questreward"); Check(c.L.EVIDENCE.questreward)
    local found; for _, code in ipairs(c.L.ORDER) do if code == "quest" then found = true end end
    Check(found, "listed with the other sources")
    Same(c.L.Evidence({ kind = "quest", amount = -5 }), false, "a quest never takes gold")
end

-- money after the event, money before it, and the same frame
for _, order in ipairs({ "event-first", "money-first", "same-frame" }) do
    local c = Client()
    if order == "event-first" then c.Turn(5001, 900, 12345); c.Money(12345)
    elseif order == "money-first" then c.Money(12345); c.Turn(5001, 900, 12345)
    else c.Turn(5001, 900, 12345); c.Money(12345, false) end
    local e = c.Rec().entries[1]
    Same(e.k, "quest", order); Same(e.a, 12345); Same(e.n, "Wolves at the Gate"); Same(e.e, "questreward"); Same(e.i, nil, "no item and no quest id is kept"); Same(#c.Rec().entries, 1)
    local day = c.Rec().days[20000]
    Same(day.ci.quest, 12345); Same(day.ci.other, nil, "the amount moved from Unclassified to the quest source"); Same(day.i, 12345)
end

-- what it does not prove stays Unclassified
do
    local c = Client(); c.Turn(5001, 900, 0); c.Money(500)                 -- a turn-in that pays no gold
    Same(c.Rec().entries[1].k, nil); Same(c.Q.Snapshot().ignored, 1)
    c = Client(); c.Turn(5001, 900, 12345); c.Money(12000)                    -- a different gain
    Same(c.Rec().entries[1].k, nil, "a different amount is not this quest")
    c = Client(); c.Money(777); c.Money(777); c.MONO = c.MONO + 1; c.Turn(5001, 900, 777)   -- two equal unclassified gains, a frame later: ambiguous
    Same(c.Rec().entries[1].k, nil); Same(c.Rec().entries[2].k, nil, "two candidates attach nothing")
    c = Client(); c.Turn(5001, 900, "x"); c.Turn("y", 1, 5); c.Turn(nil, nil, nil); Same(c.Q.Snapshot().reported, 0, "damaged payloads are ignored")
    c = Client(); c.Turn(5001, 900, 2 ^ 60); Same(c.Q.Snapshot().reported, 0, "an implausible amount is refused")
end

-- an unreadable title leaves a plain entry; a hostile one is cleaned
do
    local c = Client(); c.Turn(9999, 1, 300); c.Money(300)
    Same(c.Rec().entries[1].k, "quest"); Same(c.Rec().entries[1].n, nil)
    c = Client(); c.Turn(5002, 1, 400); c.Money(400)
    Check(not c.Rec().entries[1].n:find("[|%c]"), "no markup or control characters in a note")
    c.C_QuestLog = nil; c.Turn(5001, 1, 410); c.Money(410); Same(c.Rec().entries[2].k, "quest", "no title API: still evidence")
end

-- the evidence never creates money; the listener exists only while recording; a repeated turn-in is not counted twice
do
    local c = Client(); c.Turn(5001, 900, 12345)
    Same(#c.Rec().entries, 0, "evidence alone records nothing")
    local off = Client({ on = false })
    Same(off.Q.Snapshot().events, 0, "no listener while the ledger is off"); off.Turn(5001, 900, 100)
    local on = Client(); Same(on.Q.Snapshot().events, 1)
    on.TwichUIDB.ui.workshopEnabled = false; on.L.Refresh(); Same(on.Q.Snapshot().events, 0, "turning the Workshop off removes it")
    local d = Client(); d.Turn(5001, 900, 100); d.Money(100); d.Turn(5001, 900, 100); d.Money(100)
    Same(d.Rec().entries[1].k, "quest"); Same(d.Rec().entries[2].k, "quest", "two real turn-ins of the same amount are two rewards")
end

-- it survives a reload and old data is untouched
do
    local c = Client(); c.Turn(5001, 900, 12345); c.Money(12345)
    local d = Client({ db = c.TwichUILedgerDB })
    local e = d.Rec().entries[1]
    Same(e.k, "quest"); Same(e.e, "questreward"); Same(e.n, "Wolves at the Gate"); Same(d.Rec().days[20000].ci.quest, 12345)
    -- an entry naming the source in a history that does not know it falls back to unclassified (older binaries); here it is known
    local bad = { version = 1, chars = { ["Rich - Forever"] = { name = "Rich", realm = "Forever", since = T0, nextId = 3,
        entries = { { id = 1, t = T0, a = -5, k = "quest", e = "questreward" } }, days = {} } } }
    local f = Client({ db = bad }); Same(f.Rec().entries[1].k, nil, "gold out cannot be a quest reward")
end
print("LEDGER QUEST OK")
