-- TwichUI: Mage refreshments
-- For Mages, off until turned on (Mage options page). Plans the conjured food and water a Mage hands to
-- their party or raid, and keeps a checklist of who has been supplied. The panel is
-- modules/RefreshmentsPanel.lua; the class shares are edited on modules/RefreshmentsShares.lua.
--   Shares: how many single items (never stacks) each class gets, one table for a party and one for a
--   raid, and how many the Mage keeps for themselves. Saved in TwichUIDB.ui.refreshments; only the values
--   the player changed are stored, and each is checked every time it is read.
--   The plan: for each group member, their class's share at the best rank this Mage knows that the
--   member's level can use, less what they were given this session; added up per item with the Mage's
--   own reserve, against what the Mage's bags hold. Nothing is guessed about what anyone else carries.
--   The session: what this Mage has marked as handed to each member, by GUID. Kept in memory only, so a
--   reload, leaving the group or Reset starts it again. Names are shown in the panel and never saved.
-- TwichUI never casts, trades or whispers for the player. The panel's conjure buttons cast only when
-- clicked or their key is pressed, once per press; the game repeats a held cast only from its own
-- action bars (see docs/refreshments.md).
-- Ranks are Mage Conjuring's (modules/MageConjure.lua, Forever's six). The item IDs and the level each
-- item needs are the Classic-era game's; they have not been read from the Forever client (as
-- FoodDrink.CONJURED, which tests/test_refreshments.lua checks them against).

local R = TwichUI
local SM = R.SpellMenu
local RF = {}
R.Refreshments = RF

local Plain = SM.Plain
local function InCombat() return InCombatLockdown and InCombatLockdown() end

local SETTLE = 0.2        -- seconds: a burst of roster or bag events becomes one look
local YIELD_WAIT = 3      -- seconds after a conjure for its items to reach the bags

RF.KINDS = { "water", "food" }
RF.KIND_LABEL = { water = "Water", food = "Food" }
-- Lowest rank first, in step with MageConjure.SPELLS.
RF.ITEMS = {
    food = { 5349, 1113, 1114, 1487, 8075, 8076 },    -- Conjured Muffin ... Conjured Sweet Roll
    water = { 5350, 2288, 2136, 3772, 8077, 8078 },   -- Conjured Water ... Conjured Sparkling Water
}
RF.USE_LEVEL = { 1, 5, 15, 25, 35, 45 }   -- the level each rank's item needs, food and water alike
RF.CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
RF.CONTEXTS = { "party", "raid" }
-- A starting point, not a statement of what a class needs: every number is the player's to change.
RF.DEFAULTS = {
    DRUID = { water = 20, food = 20 }, HUNTER = { water = 20, food = 20 }, MAGE = { water = 0, food = 0 },
    PALADIN = { water = 20, food = 20 }, PRIEST = { water = 20, food = 20 }, ROGUE = { water = 0, food = 20 },
    SHAMAN = { water = 20, food = 20 }, WARLOCK = { water = 20, food = 20 }, WARRIOR = { water = 0, food = 20 },
}
RF.RESERVE_DEFAULT = { water = 20, food = 20 }
RF.MAX = 200               -- the most items one share or the reserve can ask for
RF.MAX_DEPARTED = 40       -- people who left the group whose session record is kept, in case they come back

local BY_SPELL = {}        -- [spellID] = { kind, rank }, built on first use (MageConjure loads first)
local function Spells()
    if next(BY_SPELL) then return BY_SPELL end
    for _, kind in ipairs(RF.KINDS) do
        for rank, id in ipairs(R.MageConjure.SPELLS[kind]) do BY_SPELL[id] = { kind = kind, rank = rank } end
    end
    return BY_SPELL
end

function RF.SpellFor(kind, rank) return R.MageConjure.SPELLS[kind][rank] end

-- rank, kind of a conjure food or water spell; nil for any other spell.
function RF.SpellIndex(spell)
    local what = spell and Spells()[spell]
    if what then return what.rank, what.kind end
    return nil
end

function RF.ForPlayer() return SM.PlayerClass() == "MAGE" end
function RF.Enabled() return RF.ForPlayer() and R:Enabled("mageRefreshments") end

---------------------------------------------------------------------------
-- Shares. Read through Share and Reserve, which fall back to the default for anything unusable
-- without erasing it.
---------------------------------------------------------------------------
local function Saved()
    local ui = TwichUIDB and TwichUIDB.ui
    local saved = ui and ui.refreshments
    return type(saved) == "table" and saved or nil
end

function RF.ValidAmount(n)
    return type(n) == "number" and n == n and n >= 0 and n <= RF.MAX and math.floor(n) == n
end
local ValidAmount = RF.ValidAmount

local function ValidContext(context) return context == "party" or context == "raid" end
local function ValidKind(kind) return kind == "water" or kind == "food" end

function RF.DefaultShare(class, kind)
    local d = RF.DEFAULTS[class]
    return d and d[kind] or 0
end

function RF.Share(context, class, kind)
    local saved = Saved()
    local group = saved and saved[context]
    local row = type(group) == "table" and group[class]
    local value = type(row) == "table" and row[kind]
    if ValidAmount(value) then return value end
    return RF.DefaultShare(class, kind)
end

function RF.Reserve(kind)
    local saved = Saved()
    local reserve = saved and saved.reserve
    local value = type(reserve) == "table" and reserve[kind]
    if ValidAmount(value) then return value end
    return RF.RESERVE_DEFAULT[kind]
end

local function Writable()
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    if type(TwichUIDB.ui.refreshments) ~= "table" then TwichUIDB.ui.refreshments = {} end
    return TwichUIDB.ui.refreshments
end

local Changed   -- below

-- Saves one class's share. An invalid value is refused; the default is stored as nothing at all.
function RF.SetShare(context, class, kind, value)
    if not (ValidContext(context) and RF.DEFAULTS[class] and ValidKind(kind) and ValidAmount(value)) then return false end
    local saved = Writable()
    if type(saved[context]) ~= "table" then saved[context] = {} end
    local group = saved[context]
    if type(group[class]) ~= "table" then group[class] = {} end
    group[class][kind] = value ~= RF.DefaultShare(class, kind) and value or nil
    if not next(group[class]) then group[class] = nil end
    if not next(group) then saved[context] = nil end
    Changed()
    return true
end

function RF.SetReserve(kind, value)
    if not (ValidKind(kind) and ValidAmount(value)) then return false end
    local saved = Writable()
    if type(saved.reserve) ~= "table" then saved.reserve = {} end
    saved.reserve[kind] = value ~= RF.RESERVE_DEFAULT[kind] and value or nil
    if not next(saved.reserve) then saved.reserve = nil end
    Changed()
    return true
end

-- Every share and the reserve back to the defaults. The panel's place is kept.
function RF.ResetShares()
    local saved = Saved()
    if saved then saved.party, saved.raid, saved.reserve = nil, nil, nil end
    Changed()
end

---------------------------------------------------------------------------
-- Ranks and items
---------------------------------------------------------------------------

-- { [rank] = true } for the ranks of a kind this character knows.
function RF.KnownRanks(kind)
    local known = {}
    for rank, id in ipairs(R.MageConjure.SPELLS[kind]) do
        if SM.Known(id) then known[rank] = true end
    end
    return known
end

-- The highest known rank someone of this level can use; with no level, the highest known.
function RF.RankFor(known, level)
    for rank = #RF.USE_LEVEL, 1, -1 do
        if known[rank] and (not level or RF.USE_LEVEL[rank] <= level) then return rank end
    end
    return nil
end

-- How many items fill one bag slot, or nil when the game hasn't said.
function RF.StackSize(item)
    local size = C_Item and C_Item.GetItemMaxStackSizeByID and Plain(C_Item.GetItemMaxStackSizeByID(item))
    return (type(size) == "number" and size > 0) and size or nil
end

function RF.Count(item)
    local n = C_Item and C_Item.GetItemCount and Plain(C_Item.GetItemCount(item))
    return type(n) == "number" and n or 0
end

-- How many more of an item the bags can take: empty slots in ordinary bags at a full stack each, and
-- the room left on part stacks. nil when the stack size isn't known.
function RF.Room(item)
    local stack = RF.StackSize(item)
    if not (stack and C_Container) then return nil end
    local room = 0
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, last do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        free, family = Plain(free), Plain(family)
        if type(free) == "number" and (family or 0) == 0 then room = room + free * stack end
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and Plain(info.itemID) == item then
                local count = Plain(info.stackCount)
                if type(count) == "number" and count < stack then room = room + stack - count end
            end
        end
    end
    return room
end

---------------------------------------------------------------------------
-- The plan. Pure: everything it reads comes in through `input`, so it can be checked on its own.
-- input = {
--   context  "party" | "raid" | "solo"
--   members  { { guid, name, class, level (nil when unknown), connected, given = { water, food } }, ... }
--   myLevel  the Mage's level, or nil
--   known    { water = { [rank] = true }, food = { ... } }
--   share    function(context, class, kind) -> items
--   reserve  { water = n, food = n }
--   have     function(itemID) -> count in the bags
-- }
-- Returns { context, rows, items = { water = { line, ... }, food = ... } best rank first, totals, counts,
-- next }. A line is { kind, rank, item, spell, group, reserve, recipients, need, have, short }.
---------------------------------------------------------------------------
function RF.BuildPlan(input)
    local plan = {
        context = input.context, rows = {}, items = { water = {}, food = {} }, totals = {},
        counts = { supplied = 0, partial = 0, pending = 0, nothing = 0 },
    }
    local lines = { water = {}, food = {} }
    local function Line(kind, rank)
        local line = lines[kind][rank]
        if not line then
            line = { kind = kind, rank = rank, item = RF.ITEMS[kind][rank], spell = RF.SpellFor(kind, rank),
                group = 0, reserve = 0, recipients = 0 }
            lines[kind][rank] = line
        end
        return line
    end
    local sharing = input.context == "party" or input.context == "raid"
    for _, m in ipairs(sharing and input.members or {}) do
        local row = { guid = m.guid, name = m.name, class = m.class, level = m.level, connected = m.connected,
            want = {}, given = {}, remaining = {}, rank = {}, noRank = {} }
        local wantsAny, hasAll, hasAny = false, true, false
        for _, kind in ipairs(RF.KINDS) do
            local want = m.class and input.share(input.context, m.class, kind) or 0
            local given = (m.given and m.given[kind]) or 0
            row.want[kind], row.given[kind] = want, given
            row.remaining[kind] = math.max(0, want - given)
            if want > 0 then wantsAny = true end
            if given < want then hasAll = false end
            if given > 0 then hasAny = true end
            if row.remaining[kind] > 0 then
                local rank = RF.RankFor(input.known[kind], m.level)
                row.rank[kind] = rank
                if rank then
                    local line = Line(kind, rank)
                    line.group = line.group + row.remaining[kind]
                    line.recipients = line.recipients + 1
                else
                    row.noRank[kind] = true
                end
            end
        end
        if not wantsAny then row.status = "nothing"
        elseif hasAll then row.status = "supplied"
        elseif hasAny then row.status = "partial"
        else row.status = "pending" end
        plan.counts[row.status] = plan.counts[row.status] + 1
        if not plan.next and m.connected ~= false and (row.status == "pending" or row.status == "partial") then
            plan.next = m.guid
        end
        plan.rows[#plan.rows + 1] = row
    end
    for _, kind in ipairs(RF.KINDS) do
        local keep = input.reserve[kind] or 0
        local mine = RF.RankFor(input.known[kind], input.myLevel)
        if keep > 0 and mine then Line(kind, mine).reserve = keep end
        local total = { need = 0, covered = 0, short = 0 }
        for rank = #RF.USE_LEVEL, 1, -1 do
            local line = lines[kind][rank]
            if line then
                line.need = line.group + line.reserve
                line.have = input.have(line.item)
                line.short = math.max(0, line.need - line.have)
                total.need = total.need + line.need
                total.covered = total.covered + math.min(line.have, line.need)
                total.short = total.short + line.short
                plan.items[kind][#plan.items[kind] + 1] = line
            end
        end
        plan.totals[kind] = total
    end
    return plan
end

---------------------------------------------------------------------------
-- The group
---------------------------------------------------------------------------
local function ReadMember(unit)
    local guid = Plain(UnitGUID(unit))
    if type(guid) ~= "string" then return nil end
    local name = Plain(GetUnitName and GetUnitName(unit, true) or UnitName(unit))
    local _, class = UnitClass(unit)
    class = Plain(class)
    local level = Plain(UnitLevel(unit))
    local connected = Plain(UnitIsConnected(unit))
    return {
        guid = guid, name = type(name) == "string" and name or nil,
        class = RF.DEFAULTS[class] and class or nil,
        level = (type(level) == "number" and level > 0) and level or nil,
        connected = connected ~= false,
    }
end

local function Same(unit)
    local same = Plain(UnitIsUnit(unit, "player"))
    return same == true
end

-- context, members, and how many members could not be read (their GUID was hidden or not there yet).
function RF.ReadRoster()
    local members, unreadable = {}, 0
    local function Add(unit)
        if not Plain(UnitExists(unit)) or Same(unit) then return end
        local m = ReadMember(unit)
        if m then members[#members + 1] = m else unreadable = unreadable + 1 end
    end
    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() or 0 do Add("raid" .. i) end
        return "raid", members, unreadable
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do Add("party" .. i) end
        return "party", members, unreadable
    end
    return "solo", members, unreadable
end

---------------------------------------------------------------------------
-- The session: what has been handed to whom, by GUID, in memory only.
-- entries[guid] = { water = n, food = n, name, class, level, inGroup, seen }
---------------------------------------------------------------------------
local entries, departed, serial = {}, 0, 0
local resets = 0

local function Track(members)
    serial = serial + 1
    local present = {}
    for _, m in ipairs(members) do
        present[m.guid] = true
        local e = entries[m.guid]
        if not e then
            e = { water = 0, food = 0 }
            entries[m.guid] = e
        end
        e.name, e.class, e.level, e.inGroup, e.seen = m.name, m.class, m.level, true, serial
        m.given = e
    end
    departed = 0
    local oldest
    for guid, e in pairs(entries) do
        if not present[guid] then
            e.inGroup = false
            if e.water == 0 and e.food == 0 then
                entries[guid] = nil   -- nothing to remember about them
            else
                departed = departed + 1
                if not oldest or e.seen < entries[oldest].seen then oldest = guid end
            end
        end
    end
    while departed > RF.MAX_DEPARTED and oldest do
        entries[oldest] = nil
        departed = departed - 1
        oldest = nil
        for guid, e in pairs(entries) do
            if not e.inGroup and (not oldest or e.seen < entries[oldest].seen) then oldest = guid end
        end
    end
end

---------------------------------------------------------------------------
-- What the panel reads, kept current by the events below while the feature is on.
---------------------------------------------------------------------------
local state = { context = "solo", members = {}, unreadable = 0 }
local plan
local scheduled, generation = false, 0
local rosterAfterCombat = false
local listeners = {}

function RF.OnChange(fn) listeners[#listeners + 1] = fn end

local function Notify()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then R.Fault("refreshments", err) end
    end
end

local function MyLevel()
    local level = Plain(UnitLevel("player"))
    return (type(level) == "number" and level > 0) and level or nil
end

local function Compute()
    return RF.BuildPlan({
        context = state.context, members = state.members, myLevel = MyLevel(),
        known = { water = RF.KnownRanks("water"), food = RF.KnownRanks("food") },
        share = RF.Share, reserve = { water = RF.Reserve("water"), food = RF.Reserve("food") }, have = RF.Count,
    })
end

local function Look()
    scheduled = false
    if not RF.Enabled() then return end
    if not R.Life.InWorld() then
        R.Life.Note("waiting-for-world")
        return
    end
    local context, members, unreadable = RF.ReadRoster()
    if unreadable > 0 and InCombat() then
        -- The roster's identities can be hidden in combat: keep the last good one until it ends.
        rosterAfterCombat = true
        R.Life.Note("deferred-combat")
    else
        -- Out of the group (GROUP_LEFT may not have been seen, e.g. across a loading screen): a new session.
        if context == "solo" and state.context ~= "solo" then RF.ResetSession("left-group") end
        state.context, state.members, state.unreadable = context, members, unreadable
        Track(members)
    end
    plan = Compute()
    Notify()
end

local function Schedule()
    if scheduled or not RF.Enabled() then return end
    scheduled = true
    local mine = generation
    C_Timer.After(SETTLE, function()
        if mine ~= generation then
            scheduled = false
            R.Life.Note("cancelled-stale-refreshments")
            return
        end
        Look()
    end)
end

function Changed()
    if RF.Enabled() then Schedule() end
    Notify()
end

-- The plan as it stands (worked out now if there is none yet), or nil while the feature is off.
function RF.Plan()
    if not RF.Enabled() then return nil end
    if not plan then plan = Compute() end
    return plan
end

function RF.Context() return state.context end
function RF.Unreadable() return state.unreadable end

-- A session record for the panel, or nil.
function RF.Entry(guid) return guid and entries[guid] end

local function Given(guid)
    local e = entries[guid]
    if not e then return nil end
    return e
end

local function Clamp(n) return math.max(0, math.min(9999, n)) end

local function Corrected()
    plan = Compute()
    Notify()
end

-- Everything this member's share asks for, marked as handed over.
function RF.MarkSupplied(guid)
    local e = Given(guid)
    if not (e and plan) then return false end
    for _, row in ipairs(plan.rows) do
        if row.guid == guid then
            for _, kind in ipairs(RF.KINDS) do e[kind] = math.max(e[kind], row.want[kind]) end
        end
    end
    Corrected()
    return true
end

function RF.ClearGiven(guid)
    local e = Given(guid)
    if not e then return false end
    e.water, e.food = 0, 0
    Corrected()
    return true
end

-- Handed a few more (or fewer, by hand) of one kind. Never below 0.
function RF.Adjust(guid, kind, delta)
    local e = Given(guid)
    if not (e and ValidKind(kind) and type(delta) == "number") then return false end
    e[kind] = Clamp(e[kind] + delta)
    Corrected()
    return true
end

-- Forgets what everyone was handed. Records of people still in the group are zeroed where they are
-- (the plan's rows point at them); those of people who left go. why: a reason code for diagnostics.
function RF.ResetSession(why)
    for guid, e in pairs(entries) do
        if e.inGroup then e.water, e.food = 0, 0 else entries[guid] = nil end
    end
    departed = 0
    resets = resets + 1
    R.Life.Note("refreshments-reset-" .. (why or "manual"))
    if RF.Enabled() then Corrected() end
end

---------------------------------------------------------------------------
-- What the conjure buttons cast: for a kind, the best rank still short of what the plan needs, else
-- the best rank known (conjuring more is the player's choice). spellID, rank, item; nil when no rank
-- of the kind is known.
---------------------------------------------------------------------------
function RF.ConjureChoice(kind, forPlan)
    forPlan = forPlan or plan
    for _, line in ipairs(forPlan and forPlan.items[kind] or {}) do
        if line.short > 0 then return line.spell, line.rank, line.item end
    end
    local rank = RF.RankFor(RF.KnownRanks(kind), MyLevel())
    if rank then return RF.SpellFor(kind, rank), rank, RF.ITEMS[kind][rank] end
    return nil
end

---------------------------------------------------------------------------
-- Items per cast, as seen: when a conjure lands, its items reach the bags a moment later. The gain in
-- that item's count by the next conjure (or after a few seconds) is one cast's worth, at this level.
-- Only shown as "about"; eating or trading meanwhile can upset it, so a value outside 1-60 is ignored.
---------------------------------------------------------------------------
local yields = {}     -- [spellID] = { n, level }
local watch
local lastConjured   -- GetTime() of the last conjure food or water seen

local function FinishWatch(w)
    if watch ~= w then return end
    watch = nil
    local n = RF.Count(w.item) - w.before
    if n >= 1 and n <= 60 then
        yields[w.spell] = { n = n, level = w.level }
        Schedule()
    end
end

local function OnConjured(spell)
    local what = Spells()[spell]
    if not what then return end
    lastConjured = GetTime()
    if watch then FinishWatch(watch) end
    local w = { spell = spell, item = RF.ITEMS[what.kind][what.rank], level = MyLevel() }
    w.before = RF.Count(w.item)
    watch = w
    C_Timer.After(YIELD_WAIT, function() FinishWatch(w) end)
end

-- Seconds since the last conjure food or water, or nil when none has been seen.
function RF.SinceConjure()
    return lastConjured and (GetTime() - lastConjured) or nil
end

-- Items one cast of this spell made at this level, or nil until one has been seen.
function RF.Yield(spell)
    local y = yields[spell]
    if y and y.level == MyLevel() then return y.n end
    return nil
end

local castFrame = CreateFrame("Frame")
castFrame:SetScript("OnEvent", function(_, _, unit, _, spell)
    local ok, err = pcall(function()
        if Plain(unit) ~= "player" then return end
        spell = Plain(spell)
        if type(spell) == "number" then OnConjured(spell) end
    end)
    if not ok then R.Fault("refreshments cast watch", err) end
end)

local function WatchCasts(on)
    if on then
        if castFrame.RegisterUnitEvent then castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        else castFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED") end
    else
        castFrame:UnregisterAllEvents()
    end
end

---------------------------------------------------------------------------
-- Listening, only while the feature is on for a Mage.
---------------------------------------------------------------------------
local active = {}

local function Want(event, handler, wanted)
    if wanted and not active[event] then
        active[event] = handler
        R:On(event, handler)
    elseif not wanted and active[event] then
        R:Off(event, active[event])
        active[event] = nil
    end
end

local function OnUnit(unit)
    unit = Plain(unit)
    if type(unit) == "string" and (unit:find("^party%d") or unit:find("^raid%d")) then Schedule() end
end

local function OnGroupLeft()
    RF.ResetSession("left-group")
    state.context = "solo"   -- already reset: the next look must not count it again
    Schedule()
end

local function OnRegenEnabled()
    if rosterAfterCombat then
        rosterAfterCombat = false
        Schedule()
    end
end

-- Registers what is wanted and lets go of the rest. Safe to call any number of times.
function RF.Refresh()
    local on = RF.Enabled()
    Want("GROUP_ROSTER_UPDATE", Schedule, on)
    Want("GROUP_LEFT", OnGroupLeft, on)
    Want("UNIT_LEVEL", OnUnit, on)
    Want("UNIT_CONNECTION", OnUnit, on)
    Want("PLAYER_ENTERING_WORLD", Schedule, on)
    Want("BAG_UPDATE_DELAYED", Schedule, on)
    Want("SPELLS_CHANGED", Schedule, on)
    Want("PLAYER_LEVEL_UP", Schedule, on)
    Want("PLAYER_REGEN_ENABLED", OnRegenEnabled, on)
    WatchCasts(on)
    if on then
        Schedule()
    else
        generation = generation + 1
        scheduled, rosterAfterCombat, watch, plan, lastConjured = false, false, nil, nil, nil
        wipe(entries)
        wipe(yields)
        departed = 0
        state.context, state.members, state.unreadable = "solo", {}, 0
    end
    Notify()
end

R:On("PLAYER_LOGIN", RF.Refresh)   -- the class is certain by then

---------------------------------------------------------------------------
-- For /tui diagnostics (diag/Refreshments.lua): counts and codes, never names.
---------------------------------------------------------------------------
function RF.Snapshot()
    local events = {}
    for event in pairs(active) do events[#events + 1] = event end
    table.sort(events)
    local inGroup, seen = 0, {}
    for _, e in pairs(entries) do if e.inGroup then inGroup = inGroup + 1 end end
    for spell, y in pairs(yields) do seen[#seen + 1] = { spell = spell, n = y.n, level = y.level } end
    table.sort(seen, function(a, b) return a.spell < b.spell end)
    return {
        mage = RF.ForPlayer(), enabled = RF.Enabled(), switchOn = R:Enabled("mageRefreshments"),
        context = state.context, members = #state.members, unreadable = state.unreadable,
        sessionInGroup = inGroup, sessionDeparted = departed, resets = resets,
        scheduled = scheduled, rosterAfterCombat = rosterAfterCombat, watching = watch ~= nil,
        events = events, yields = seen, plan = RF.Enabled() and RF.Plan() or nil,
    }
end
