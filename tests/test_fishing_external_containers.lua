-- External container opens: EllesmereUI's next-open pacing can be shorter than
-- Fishing's loot-confirmation wait. Synthetic events, real bookkeeping code;
-- no Fishing BeginOpen/key attribution, and no claim of native-client testing.
dofile(TESTS .. "fishing_mock.lua")
local failures = 0
local function Check(ok, why)
    if not ok then failures = failures + 1; print("FAIL: " .. why) end
end
local function Fresh()
    local c, W = FishingClient()
    c.TwichUI.RunCommand("fish")
    W.Wear(16, POLE)
    return c, W, c.TwichUI.Fishing
end
local function Catch(W, wait)
    W.StartLine()
    W.Loot({{CLAM, 1}}, {fishing = true})
    W.StopLine()
    if wait ~= false then W.Advance(3) end
end
local function Open(W)
    local b, s = W.Find(CLAM)
    assert(b and s, "fixture requires a clam in the bags")
    W.OpenContainer(b, s)
end
local function Contents(F, scope, pearl, meat, opened)
    local p = F.API.Provenance(scope)
    return p and p.contents[PEARL] == pearl and p.contents[CLAMMEAT] == meat
        and p.containers[CLAM] and p.containers[CLAM].opened == opened
        and p.containers[CLAM].unopened == 0 and p.direct[CLAM] == nil
end

-- Two externally opened shells disappear before either two-second settlement.
-- Each open must reserve/consume one shell once, not compare both against the
-- same old aggregate count after both have disappeared.
do
    local c, W, F = Fresh()
    Catch(W); Catch(W)
    local prices = { [CLAM] = 500, [PEARL] = 10000, [CLAMMEAT] = 20 }
    c.TwichUI.Workshop = {
        Active = function() return true end,
        Pricing = {
            Generation = function() return "external-open" end,
            Source = function() return { reference = true, market = { key = "Fixture|Alliance", at = 1800000000 } } end,
            Reference = function(id) return { market = prices[id], at = 1800000000 } end,
            Changed = function() end,
        },
        Market = { Value = function() error("do not mix market sources") end },
    }
    Open(W); W.Advance(0.65); Open(W); W.Advance(3)
    Check(Contents(F, "session", 2, 2, 2), "two rapid external opens retain both pearls/meats and consume two shells")
    Check(#F.Containers.Queue() == 0, "rapid external opens exhaust the queue")
    F.Economy.Scope("session"); W.Advance(1)
    local value = F.Economy.Scope("session")
    Check(value.total == 20040 and value.complete, "rapid external contents replace shells in the session estimate")
    local seen = {}
    for _, row in ipairs(F.CatchList.Model().treasures) do
        if row.kind == "content" then seen[row.id] = row.q end
    end
    Check(seen[PEARL] == 2 and seen[CLAMMEAT] == 2, "rapid external contents reach Today's Catch")
    -- No callback or duplicate close can apply the reserved shell/contents twice.
    c.FireEvent("LOOT_CLOSED")
    c.FireEvent("CHAT_MSG_LOOT", c.LOOT_ITEM_SELF:format(FISH_LINK(PEARL)))
    W.Settle(); W.Advance(5)
    Check(Contents(F, "session", 2, 2, 2), "replayed close/chat/bag events do not duplicate external contents")
end

-- A fresh catch can be opened before the coalesced bag event. In particular,
-- Lua's truthy zero must not preserve an old zero baseline over a witnessed catch.
do
    local c, W, F = Fresh()
    F.Containers.counts[CLAM] = 0
    local fire = c.FireEvent
    c.FireEvent = function(event, ...)
        if event ~= "BAG_UPDATE_DELAYED" then return fire(event, ...) end
    end
    Catch(W, false)
    Open(W)
    c.FireEvent = fire
    W.Settle(); W.Advance(3)
    Check(Contents(F, "session", 1, 1, 1), "fresh caught clam opens correctly before any delayed bag update despite stale zero")
end

-- Same item, different origin sessions and zones: reserve the oldest lot for
-- each distinct external opening, even while the previous capture awaits chat.
do
    local c, W, F = Fresh()
    Catch(W)
    local first, firstZone = F.Session.Current().id, W.map
    c.TwichUI.RunCommand("fish stop")
    W.map, W.zone = 1411, "Durotar"
    Catch(W)
    local second, secondZone = F.Session.Current().id, W.map
    Open(W); W.Advance(0.65); Open(W); W.Advance(3)
    Check(Contents(F, first, 1, 1, 1), "first external opening retains oldest session's shell and contents")
    Check(Contents(F, second, 1, 1, 1), "second external opening retains next session's shell and contents")
    local a, b = F.Session.Find(first), F.Session.Find(second)
    Check(a.ctz[firstZone][CLAM].got[PEARL] == 1 and a.ctz[secondZone] == nil,
        "first lot retains original zone rather than opening zone")
    Check(b.ctz[secondZone][CLAM].got[PEARL] == 1,
        "second lot retains its own original zone")
    Check(F.Journal.Session(first).contents[PEARL] == 1 and F.Journal.Session(second).contents[PEARL] == 1,
        "historical and current Journal details receive only their own external contents")
end

-- Some clients remove the shell only after LOOT_CLOSED. Its bag event must be
-- allowed to establish attribution while content confirmation is still held.
do
    local c, W, F = Fresh()
    Catch(W)
    W.Loot(W.contents[CLAM], {fromItem = true, afterClose = function()
        c.C_Timer.After(0.2, function()
            local b, s = W.Find(CLAM)
            assert(b and s)
            W.Take(b, s, 1)
            W.Settle()
        end)
    end})
    W.Advance(3)
    Check(Contents(F, "session", 1, 1, 1), "post-close shell consumption is attributed from the settling bag event")
end

-- A queued clam is not proof that any item loot came from it. Unrelated crates
-- and partial external windows without a consumed-shell/source witness stay out.
do
    local c, W, F = Fresh()
    Catch(W)
    W.Give(CRATE); W.Settle()
    W.OpenContainer(W.Find(CRATE)); W.Advance(3)
    local p = F.API.Provenance("session")
    Check(p.contents[JUNK] == nil and p.containers[CLAM].opened == 0 and p.containers[CLAM].unopened == 1,
        "unrelated external crate never consumes or inherits a queued clam")
    W.Loot({{PEARL, 1}}, {fromItem = true}); W.Advance(3)
    p = F.API.Provenance("session")
    Check(p.contents[PEARL] == nil and p.containers[CLAM].opened == 0,
        "partial external loot without a shell/source witness remains unattributed")
    Open(W); W.Advance(3)
    Check(Contents(F, "session", 1, 1, 1), "unrelated windows do not strand subsequent confirmed external clam attribution")
end

-- A still-waiting unrelated window cannot borrow a subsequent clam's decrement.
do
    local c, W, F = Fresh()
    Catch(W); Catch(W)
    W.Give(CRATE); W.Settle()
    W.OpenContainer(W.Find(CRATE)); W.Advance(0.65)
    Open(W); W.Advance(3)
    local p = F.API.Provenance("session")
    Check(p.contents[JUNK] == nil and p.contents[PEARL] == 1 and p.containers[CLAM].opened == 1
        and p.containers[CLAM].unopened == 1 and F.Gear.BagCount(CLAM) == 1,
        "unrelated prior capture cannot claim the same shell transition or steal its contents")
end

if failures > 0 then error(failures .. " external-container regression(s) failed") end
print("PASSED external container pacing, fresh baseline, provenance, post-close bags and exclusions")
