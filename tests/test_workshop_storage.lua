-- Workshop bank and guild bank materials (TwichUI_Workshop/Storage.lua, Stock.lua, Bank.lua, and their use in Materials.lua, Shopping.lua,
-- Session.lua): remembered counts of the player's bank and the guild bank, kept apart from the bags, planned with through ONE allocation,
-- collected (never bought), and never part of what a craft costs. A fake game stands in for C_Bank / C_Container / the guild bank API; a
-- seeded save and a new client are NOT a real /reload, and none of this has met the real bank (docs/workshop.md lists the in-game checks).
dofile(TESTS .. "mi_mock.lua")

local function Check(cond, msg) if not cond then error(msg, 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua", "Opportunities.lua",
  "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Session.lua", "Watch.lua", "Bank.lua" }

local ORE, BAR, SWORD, HERB = 10, 20, 90, 11

-- A new game session (client) on the saved data `db`. opts: bankOpen / guildOpen (a bank already showing when the addon loads).
local function Session(name, db, opts)
  opts = opts or {}
  local c = MIClient(name or "Rich", { db = { modules = {} } })
  c.TwichUIDB = db or c.TwichUIDB or {}
  local timers, frames = {}, {}
  c.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
  c.CreateFrame = function(kind) local fr = MIFake(kind); frames[#frames + 1] = fr; return fr end
  c.GetRealmName = function() return "Realm" end
  local g = { time = 1000000, t = 100, bags = {}, calls = { slots = 0, includeBank = 0, tabInfo = 0 }, names = {},
    bank = { ids = { 6, 7 }, tabs = { [6] = { slots = 6, items = {} }, [7] = { slots = 6, items = {} } }, view = true },
    guild = { name = "Raiders", realm = nil, club = 77, current = 1, nt = 3, tabs = {} } }
  c.time = function() return g.time end
  c.GetTime = function() return g.t end
  c.Enum = { CraftingReagentType = { Modifying = 0, Basic = 1, Finishing = 2, Automatic = 3 }, BankType = { Character = 0, Guild = 1, Account = 2 } }
  c.C_Item = {
    GetItemCount = function(id, includeBank)
      if includeBank then g.calls.includeBank = g.calls.includeBank + 1 end
      return g.bags[id] or 0
    end,
    GetItemInfoInstant = function(id) return id, "Trade Goods", "Herb", "", 5000 + id end,
    GetItemInfo = function(id) return g.names[id] or ("Item" .. id) end,
    RequestLoadItemDataByID = function() end,
  }
  c.C_TradeSkillUI = { GetBaseProfessionInfo = function() return nil end, IsTradeSkillReady = function() return false end }
  -- the personal bank: tabs are bags
  c.C_Bank = {
    FetchPurchasedBankTabIDs = function() return g.bank.ids end,
    CanViewBank = function() return g.bank.view end,
  }
  c.C_Container = {
    GetContainerNumSlots = function(bag) local t = g.bank.tabs[bag]; return t and t.slots or 0 end,
    GetContainerItemInfo = function(bag, slot)
      g.calls.slots = g.calls.slots + 1
      local t = g.bank.tabs[bag]
      local it = t and t.items[slot]
      if not it then return nil end
      return { itemID = it.id, stackCount = it.bad and "x" or it.n, isLocked = false }
    end,
  }
  c.BankFrame = MIFake("Frame"); c.BankFrame.shown = opts.bankOpen == true
  -- the guild bank
  c.IsInGuild = function() return g.guild.name ~= nil end
  c.GetGuildInfo = function() return g.guild.name, "Rank", 1, g.guild.realm end
  c.C_Club = { GetGuildClubId = function() return g.guild.club end }
  c.GetNumGuildBankTabs = function() return g.guild.nt end
  c.GetCurrentGuildBankTab = function() return g.guild.current end
  c.GetGuildBankTabInfo = function(i)
    g.calls.tabInfo = g.calls.tabInfo + 1
    local t = g.guild.tabs[i] or {}
    return "Tab" .. i, "icon", t.viewable ~= false, true, t.w == nil and 5 or t.w, t.rem == nil and -1 or t.rem
  end
  c.GetGuildBankItemInfo = function(tab, slot)
    local t = g.guild.tabs[tab]
    local it = t and t.items and t.items[slot]
    if it then return "tex", it.n, false end
  end
  c.GetGuildBankItemLink = function(tab, slot)
    local t = g.guild.tabs[tab]
    local it = t and t.items and t.items[slot]
    if not it or it.nolink then return nil end
    return "|cffffffff|Hitem:" .. it.id .. "::::::::80|h[x]|h|r"
  end
  c.GuildBankFrame = MIFake("Frame"); c.GuildBankFrame.shown = opts.guildOpen == true
  if opts.setup then opts.setup(g, c) end
  for _, f in ipairs(FILES) do
    local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
  end
  local W = c.TwichUI.Workshop
  local s = { c = c, g = g, W = W, S = W.Session, St = W.Storage, K = W.Stock }
  for _, fr in ipairs(frames) do if fr.events.BANKFRAME_OPENED then s.frame = fr end end
  function s.Flush() local n = 0 while #timers > 0 and n < 200 do local t = table.remove(timers, 1); t(); n = n + 1 end end
  function s.Fire(e, ...) s.frame.scripts.OnEvent(s.frame, e, ...) end
  function s.OpenBank() c.BankFrame.shown = true; s.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8) end
  function s.CloseBank() c.BankFrame.shown = false; s.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8) end
  function s.OpenGuild() c.GuildBankFrame.shown = true; s.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10) end
  function s.CloseGuild() c.GuildBankFrame.shown = false; s.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10) end
  function s.Put(bag, slot, id, n) g.bank.tabs[bag].items[slot] = { id = id, n = n } end
  function s.GPut(tab, slot, id, n, extra)
    local t = g.guild.tabs[tab]
    if not t then t = { items = {} } g.guild.tabs[tab] = t end
    t.items = t.items or {}
    t.items[slot] = { id = id, n = n }
    for k, v in pairs(extra or {}) do t.items[slot][k] = v end
  end
  function s.Timers() return #timers end
  function s.Key() return W.Queue.CharKey() end
  function s.Guild() return { key = "Raiders-Realm", name = "Raiders", club = "77" } end
  return s
end

local function SeedQueue(s, entries)
  local slot = s.c.TwichUIDB.workshop and s.c.TwichUIDB.workshop.chars and s.c.TwichUIDB.workshop.chars[s.Key()]
  if not slot then
    s.c.TwichUIDB.workshop = s.c.TwichUIDB.workshop or { v = 1 }
    s.c.TwichUIDB.workshop.chars = s.c.TwichUIDB.workshop.chars or {}
    slot = {}
    s.c.TwichUIDB.workshop.chars[s.Key()] = slot
  end
  slot.queue = entries
  s.W.Queue.Unload()
end
local function Entry(id, name, crafts, mats, outItem)
  return { id = id, name = name, crafts = crafts, prof = 171, profName = "Alchemy", icon = 1, outItem = outItem, outMin = 1, outMax = 1, mats = mats, seen = 5 }
end

---------------------------------------------------------------------------
-- One allocation: bags, then the bank, then the guild bank
---------------------------------------------------------------------------
do
  local s = Session()
  local Split = s.W.Split
  local function Is(want, bags, bank, guild, eb, ek, eg, er, msg)
    local b, k, g, r = Split(want, bags, bank, guild)
    Same(b, eb, msg .. " (bags)"); Same(k, ek, msg .. " (bank)"); Same(g, eg, msg .. " (guild)"); Same(r, er, msg .. " (missing)")
  end
  Is(10, 4, 12, 3, 4, 6, 0, 0, "bags first, the bank covers the rest and the guild bank is not touched")
  Is(10, 4, 2, 3, 4, 2, 3, 1, "bags, bank, guild bank, then missing")
  Is(10, 12, 12, 12, 10, 0, 0, 0, "the bags alone cover it")
  Is(10, nil, nil, nil, 0, 0, 0, 10, "nothing known is nothing")
  Is(10, -3, "x", 0 / 0, 0, 0, 0, 10, "negative, text and NaN count as none")
  Is(0, 5, 5, 5, 0, 0, 0, 0, "needing nothing takes nothing")

  -- Materials.Rows: the bags apply once, stock only when a function is given
  local M = s.W.Materials
  local entries = { Entry(1, "Sword", 5, { { item = ORE, qty = 2 } }, SWORD) }   -- 10 ore
  local function Have(i) return i == ORE and 4 or 0 end
  local rows, sum = M.Rows(entries, Have)
  Same(rows[1].short, 6, "without stock the rows are the bags alone"); Same(sum.state, "short"); Check(rows[1].fromBank == nil or rows[1].fromBank == 0, "nothing to collect")
  rows, sum = M.Rows(entries, Have, function() return 12, 0 end)
  Same(rows[1].have, 4); Same(rows[1].fromBank, 6, "6 of the bank's 12 are needed"); Same(rows[1].bank, 12, "the row still knows the bank holds 12")
  Same(rows[1].short, 0); Same(sum.state, "collect", "everything held, some of it in the bank"); Same(sum.collectItems, 1); Same(sum.bankItems, 1)
  rows, sum = M.Rows(entries, Have, function() return 2, 3 end)
  Same(rows[1].fromBank, 2); Same(rows[1].fromGuild, 3); Same(rows[1].short, 1); Same(sum.state, "short", "still short after both stores")
  rows, sum = M.Rows(entries, function() return 10 end, function() return 99, 99 end)
  Same(sum.state, "ready", "the bags alone are enough: ready, and stock is not taken from"); Same(rows[1].fromBank, 0)
  rows, sum = M.Rows(entries, function() return nil end, function() return 99, 99 end)
  Same(sum.state, "partial", "an unreadable bag count is unknown, whatever is stored"); Check(rows[1].short == nil, "never zero")
  -- queued crafts are credited first, then the bags, then storage
  local two = { Entry(1, "Sword", 1, { { item = BAR, qty = 5 } }, SWORD), Entry(2, "Bar", 3, { { item = ORE, qty = 2 } }, BAR) }
  rows = M.Rows(two, function() return 0 end, function(i) return i == BAR and 1 or 0, 0 end)
  for _, r in ipairs(rows) do if r.item == BAR then
    Same(r.made, 3, "3 bars come from the queue"); Same(r.fromBank, 1, "1 from the bank"); Same(r.short, 1, "5 - 3 - 0 - 1") end end
end

---------------------------------------------------------------------------
-- The service: the bank by default, the guild bank by choice, permissions, freshness, identity
---------------------------------------------------------------------------
do
  local s = Session()
  local St, K = s.St, s.K
  local me = s.Key()
  local guild = s.Guild()
  St.StoreBank({ ids = { 6, 7 }, tabs = { [6] = { [ORE] = 25, [HERB] = 4 }, [7] = { [ORE] = 5 } }, incomplete = 0 }, 1000)
  Same(St.Bank().tabs[6].n[ORE], 25)
  local function View(use, g, live, now) return K.Sources({ char = me, guild = g == nil and guild or g }, use, live, now or 2000) end
  local v = View(false)
  local b, gu = K.Counted(v, ORE)
  Same(b, 30, "the bank is planned with by default, tabs added"); Same(gu, 0, "the guild bank is not, by default")
  Same(K.Scope(v), "bags and bank")
  -- a bank never seen counts nothing and says how to fix that
  local blank = Session()
  local bv = blank.K.Sources({ char = blank.Key() }, false, nil, 1)
  Same(select(1, blank.K.Counted(bv, ORE)), 0); Same(blank.K.Notes(bv)[1], "Open your bank with Workshop loaded to update.")
  Same(blank.K.Scope(bv), "bags only")
  -- a bank that may have changed is shown but not planned with
  St.MarkBankUncertain()
  v = View(false)
  Same((K.Counted(v, ORE)), 0, "uncertain stock is not counted"); Check(v.bank.items[ORE] == 30, "but it is still known"); Check(v.bank.uncertain, "and marked")
  Check(K.Notes(v)[1]:find("may have changed", 1, true), "the note says so")
  St.StoreBank({ ids = { 6, 7 }, tabs = { [6] = { [ORE] = 25, [HERB] = 4 }, [7] = { [ORE] = 5 } }, incomplete = 0 }, 1000)
  Same((K.Counted(View(false, nil, { bankPending = true }), ORE)), 0, "a pending read (live) is uncertain too")
  Same((K.Counted(View(false), ORE)), 30, "and a complete read clears it")

  -- guild bank: tab 1 seen by me, rank may take items (5 = the game's withdrawal count, -1 unlimited today)
  St.StoreGuildTab(guild, 1, { n = { [ORE] = 8 }, by = me, w = 1, lim = 5, rem = -1 }, 1500, 3)
  v = View(true)
  b, gu = K.Counted(v, ORE)
  Same(gu, 8, "chosen, in the guild, tab read, rank can withdraw: counted"); Check(not v.guild.limited[ORE], "unlimited today: not flagged")
  Same(K.Scope(v), "bags, bank and guild bank")
  Same((select(2, K.Counted(View(false), ORE))), 0, "the choice off: the guild bank adds nothing")
  Same(v.guild.unread, 2, "two of three tabs were never read: unread, not empty")
  Check(table.concat(K.Notes(v), " "):find("2 guild bank tabs not seen yet", 1, true), table.concat(K.Notes(v), " "))
  -- viewing is not withdrawing
  local function Guild1(extra, now)
    local t = { n = { [ORE] = 8 }, by = me, w = 1, lim = 5, rem = -1 }
    for k, val in pairs(extra) do t[k] = val end
    St.StoreGuildTab(guild, 1, t, 1500, 3)
    return View(true, nil, nil, now)
  end
  v = Guild1({ w = 0 })
  Same(select(2, K.Counted(v, ORE)), 0, "viewable but the rank cannot withdraw: information only"); Same(v.guild.info[ORE], 8)
  Check(K.Lines(v, ORE, 1, function() return "x" end)[3]:find("can't take items", 1, true), "and the reason is given")
  v = Guild1({ w = false })
  Same(select(2, K.Counted(v, ORE)), 0, "rights not established (no withdrawal count seen): information only")
  v = Guild1({ by = "Alt - Realm" })
  Same(select(2, K.Counted(v, ORE)), 0, "a tab seen only by another character: its rights are not mine"); Same(v.guild.reason[ORE], "rights")
  v = Guild1({ rem = 0 }, 1500 + 3600)
  Same(select(2, K.Counted(v, ORE)), 0, "no withdrawals left when it was seen an hour ago: not counted"); Same(v.guild.reason[ORE], "limit")
  v = Guild1({ rem = 0 }, 1500 + 7 * 3600)
  Same(select(2, K.Counted(v, ORE)), 8, "the same reading hours later may have reset: counted, limited"); Check(v.guild.limited[ORE], "and flagged: not promised")
  v = Guild1({ rem = 3 })
  Same(select(2, K.Counted(v, ORE)), 8, "a finite allowance is potentially withdrawable"); Check(v.guild.limited[ORE], "but flagged limited")
  Check(K.Lines(v, ORE, 0, function() return "just now" end)[4]:find("limit may apply", 1, true), "the tooltip says the quantity is not promised")
  v = Guild1({ rem = -1 })
  Check(not v.guild.limited[ORE], "unlimited is not flagged")
  -- uncertain tabs, pending reads
  St.MarkGuildTabUncertain(guild, 1)
  v = View(true)
  Same(select(2, K.Counted(v, ORE)), 0, "a tab that may have changed is not counted"); Same(v.guild.uncertain, 1)
  Check(table.concat(K.Notes(v), " "):find("may have changed", 1, true), "and the notes say so")
  Guild1({})
  Same(select(2, K.Counted(View(true, nil, { guildPending = true }), ORE)), 0, "a pending guild read is uncertain")
  -- the choice is saved and only counts for the guild it was seen in
  v = View(true, { key = "Others-Realm", name = "Others", club = "5" })
  Same(select(2, K.Counted(v, ORE)), 0, "another guild's stock is not used"); Check(not v.guild.seen, "it is simply unseen")
  v = View(true, { key = "Raiders-Realm", name = "Raiders", club = "99" })
  Same(select(2, K.Counted(v, ORE)), 0, "the same name with another community id is another guild")
  v = View(true, { key = "Raiders-Realm", name = "Raiders", club = nil })
  Same(select(2, K.Counted(v, ORE)), 8, "an id that is not known yet does not hide the guild")
  v = K.Sources({ char = me, guild = nil }, true, nil, 2000)
  Same(select(2, K.Counted(v, ORE)), 0, "not in a guild (or leaving one): nothing"); Check(not v.guild.inGuild)
  Check(table.concat(K.Notes(v), " "):find("not in a guild", 1, true), "and it is said")
  Same(K.Notes(View(true, { key = "New-Realm", name = "New" }))[1], "Open your guild bank with Workshop loaded to update.", "the first note is about the bank here")
end

---------------------------------------------------------------------------
-- Records: bounds, bad data, a newer version, duplicate snapshots
---------------------------------------------------------------------------
do
  local s = Session()
  local St = s.St
  local guild = s.Guild()
  -- a tab with too many different items, or a bad count, is refused whole
  local many = {}
  for i = 1, St.MAX_TAB_ITEMS + 1 do many[1000 + i] = 1 end
  local ok = St.StoreBank({ ids = { 6 }, tabs = { [6] = many }, incomplete = 0 }, 1000)
  Same(ok, false, "an oversized tab is not saved cut short (it would look complete)"); Check(St.Bank() == nil, "nothing was saved")
  Same((St.StoreBank({ ids = { 6 }, tabs = { [6] = { [ORE] = -4 } }, incomplete = 0 }, 1000)), false, "a negative count is refused")
  Same((St.StoreBank({ ids = { 6 }, tabs = { [6] = { [ORE] = 1.5 } }, incomplete = 0 }, 1000)), false, "so is a fraction")
  Same((St.StoreBank({ ids = { 6 }, tabs = { [6] = { [ORE] = 3 } }, incomplete = 0 }, 0)), false, "and a time that is not a time")
  -- saved garbage is never a number
  s.c.TwichUIDB.workshop = s.c.TwichUIDB.workshop or { v = 1 }
  s.c.TwichUIDB.workshop.storage = { v = 1, chars = { [s.Key()] = { bank = { tabs = { [6] = { at = 5, n = { [ORE] = "lots", [12] = 7, [13] = -1 } }, ["x"] = { at = 5, n = {} },
    [7] = "no", [8] = { at = "now", n = {} } } } } }, guilds = { Raiders = "junk" } }
  local b = St.Bank()
  Same(b.tabs[6].n[12], 7); Check(b.tabs[6].n[ORE] == nil and b.tabs[6].n[13] == nil, "bad counts dropped")
  Check(b.tabs[7] == nil and b.tabs[8] == nil, "bad tabs dropped")
  Check(St.Guild(guild) == nil, "a junk guild record is nothing")
  -- two characters of one guild: one snapshot per tab, the newer replaces, nothing is added
  local a = Session("Rich"); local db = a.c.TwichUIDB
  a.St.StoreGuildTab(a.Guild(), 2, { n = { [ORE] = 10 }, by = a.Key(), w = 1 }, 1000, 3)
  local alt = Session("Alt", db)
  alt.St.StoreGuildTab(alt.Guild(), 2, { n = { [ORE] = 7 }, by = alt.Key(), w = 1 }, 1100, 3)
  local rec = alt.St.Guild(alt.Guild())
  Same(rec.tabs[2].n[ORE], 7, "the newer observation of a tab replaces the older"); Same(rec.tabs[2].by, alt.Key())
  local v = alt.K.Sources({ char = alt.Key(), guild = alt.Guild() }, true, nil, 2000)
  Same(select(2, alt.K.Counted(v, ORE)), 7, "never 17")
  local va = a.K.Sources({ char = a.Key(), guild = a.Guild() }, true, nil, 2000)
  Same(select(2, a.K.Counted(va, ORE)), 0, "the first character no longer holds the rights record of that tab: information only")
  -- banks belong to a character
  a.St.StoreBank({ ids = { 6 }, tabs = { [6] = { [ORE] = 40 } }, incomplete = 0 }, 1000)
  Check(alt.St.Bank() == nil, "an alt does not see the main's bank"); Same(a.St.Bank().tabs[6].n[ORE], 40)
  -- a tab the game no longer lists goes; tabs that were not read stay
  a.St.StoreBank({ ids = { 6, 7 }, tabs = { [7] = { [HERB] = 2 } }, incomplete = 1 }, 1100)
  b = a.St.Bank()
  Same(b.tabs[6].n[ORE], 40, "tab 6 was not read this time: kept"); Same(b.tabs[7].n[HERB], 2); Check(b.u, "and the record is uncertain while a tab is unread")
  a.St.StoreBank({ ids = { 7 }, tabs = { [7] = { [HERB] = 3 } }, incomplete = 0 }, 1200)
  b = a.St.Bank()
  Check(b.tabs[6] == nil and b.tabs[7].n[HERB] == 3 and not b.u, "a tab the game stopped listing is dropped; a complete read clears the doubt")
  a.St.StoreBank({ ids = nil, tabs = {}, incomplete = 0 }, 1300)
  Same(a.St.Bank().tabs[7].n[HERB], 3, "an empty tab list is not read as 'all tabs gone'")
  -- the guild limit
  for i = 1, 5 do
    local e = Session("Rich", db)
    e.St.StoreGuildTab({ key = "G" .. i .. "-Realm", name = "G" .. i }, 1, { n = { [ORE] = i }, by = "x" }, 2000 + i, 1)
  end
  local n = 0
  for _ in pairs(db.workshop.storage.guilds) do n = n + 1 end
  Check(n <= a.St.MAX_GUILDS, "at most " .. a.St.MAX_GUILDS .. " guilds are remembered")
  Check(db.workshop.storage.guilds["G5-Realm"] ~= nil, "the newest stays")
  -- a newer TwichUI's data is left alone
  db.workshop.storage.v = 99
  local okb, why = a.St.StoreBank({ ids = { 7 }, tabs = { [7] = { [HERB] = 9 } }, incomplete = 0 }, 1400)
  Same(okb, false); Same(why, "held")
  local okc, whyc = a.St.SetUseGuild(true)
  Same(okc, false); Same(whyc, "held")
  Same(a.St.MarkBankUncertain(), false)
  Same(a.St.Bank().tabs[7].n[HERB], 3, "untouched")
end

---------------------------------------------------------------------------
-- The choice is saved (and off by default)
---------------------------------------------------------------------------
do
  local s = Session()
  Same(s.S.UseGuild(), false, "off by default")
  Same(s.S.SetUseGuild(true), true)
  local again = Session("Rich", s.c.TwichUIDB)
  Same(again.S.UseGuild(), true, "it survives a new session")
  Same(again.S.SetUseGuild(false), true)
  Same(Session("Rich", s.c.TwichUIDB).S.UseGuild(), false)
  Check(s.c.TwichUIDB.workshop.storage.useGuild == nil, "off is stored as nothing, not as a copy of the default")
  local changed = 0
  s.St.OnChange = function() changed = changed + 1 end
  s.S.SetUseGuild(true); s.S.SetUseGuild(true)
  Same(changed, 1, "a change is news once")
end

---------------------------------------------------------------------------
-- Shopping: collect rows, stored materials lower what is bought, nothing is spent twice
---------------------------------------------------------------------------
local function Plan(s, t)
  local W = s.W
  local Have = function(i) return (t.have or {})[i] or 0 end
  local Stock = function(i) local x = (t.stock or {})[i]; if x then return x[1] or 0, x[2] or 0 end return 0, 0 end
  local rows = W.Materials.Rows(t.entries, Have, Stock)
  local inp = {
    rows = rows, picks = t.picks or {}, have = Have, stock = Stock,
    stockMeta = function(_, where) return { at = 900, limited = where == "guild" or nil } end,
    auction = function(i) local p = (t.auction or {})[i]; return p and { price = p[1], qty = p[2], total = p[3], at = 999000, complete = true } end,
    vendor = function() return nil end, sells = function() return false end,
    recipes = function(i) return (t.recipes or {})[i] or {} end, queued = function() return nil end,
  }
  return W.Shopping.Plan(inp), rows
end
local function Rows(plan, kind, item)
  local out = {}
  for _, r in ipairs(plan.rows) do if (kind == nil or r.kind == kind) and (item == nil or r.item == item) then out[#out + 1] = r end end
  return out
end

do
  local s = Session()
  local entries = { Entry(1, "Sword", 5, { { item = ORE, qty = 2 } }, SWORD) }   -- 10 ore
  -- bank covers the rest: collect, nothing to buy
  local plan = Plan(s, { entries = entries, have = { [ORE] = 4 }, stock = { [ORE] = { 6 } }, auction = { [ORE] = { 10, 100, 1000 } } })
  Same(#Rows(plan, "buy"), 0, "nothing to buy"); Same(#Rows(plan, "make"), 0)
  local c = Rows(plan, "collect")
  Same(#c, 1); Same(c[1].where, "bank"); Same(c[1].qty, 6, "6 to collect from the bank"); Same(c[1].at, 900, "with when it was seen")
  Same(plan.totals.collect, 1); Same(plan.totals.cash, 0, "collecting costs nothing")
  Same(plan.rows[1].kind, "collect", "collect rows come first")
  -- bank short, so buy the rest
  plan = Plan(s, { entries = entries, have = { [ORE] = 4 }, stock = { [ORE] = { 3 } }, auction = { [ORE] = { 10, 100, 1000 } } })
  c = Rows(plan, "collect"); Same(c[1].qty, 3)
  local buy = Rows(plan, "buy", ORE)[1]
  Same(buy.qty, 3, "10 - 4 in bags - 3 in the bank = 3 to buy"); Same(buy.cash, 30, "priced for 3, not 6"); Same(plan.totals.cash, 30)
  Check(Rows(plan, "buy", ORE)[1].fromBank == 3, "the buy row remembers the stored part for its tooltip")
  -- both stores: the bank first, then the guild bank, a row each
  plan = Plan(s, { entries = entries, have = { [ORE] = 4 }, stock = { [ORE] = { 3, 5 } } })
  c = Rows(plan, "collect")
  Same(#c, 2); Same(c[1].where, "bank"); Same(c[1].qty, 3); Same(c[2].where, "guild"); Same(c[2].qty, 3, "10 - 4 - 3 = 3 of the guild's 5")
  Check(c[2].limited, "guild stock is flagged from the service"); Same(#Rows(plan, "buy"), 0)
  -- the Basis lines name the store and do not promise
  local lines = s.W.Shopping.Basis(c[2], function(i) return "Ore" end, function(x) return tostring(x) end, function(a) return a .. "s" end, 1000)
  local joined = {}
  for _, l in ipairs(lines) do joined[#joined + 1] = l[1] end
  joined = table.concat(joined, "|")
  Check(joined:find("Collect 3 from the guild bank", 1, true) and joined:find("limit may apply", 1, true) and joined:find("Nothing is taken out for you", 1, true), joined)

  -- one pool for the queue and its subcraft: the main craft takes first, a made material draws on what is left, nothing is spent twice
  -- Sword needs 2 bars and 2 ore; a bar is made from 1 ore. Ore: 1 in the bags, 2 in the bank.
  local two = { Entry(1, "Sword", 1, { { item = BAR, qty = 2 }, { item = ORE, qty = 2 } }, SWORD) }
  local make = { id = 200, name = "Make Bar", outItem = BAR, outMin = 1, outMax = 1, mats = { { item = ORE, qty = 1 } } }
  plan = Plan(s, { entries = two, have = { [ORE] = 1 }, stock = { [ORE] = { 2 } }, recipes = { [BAR] = { make } }, picks = { [BAR] = "make" } })
  local mk = Rows(plan, "make", BAR)[1]
  Check(mk, "the bars are made"); Same(mk.make.crafts, 2)
  -- ore: main craft needs 2: 1 bag + 1 bank. The bars' 2 ore: 1 left in the bank, 1 must be bought.
  c = Rows(plan, "collect", ORE)
  Same(#c, 1); Same(c[1].where, "bank"); Same(c[1].qty, 2, "1 for the sword and 1 for the bars, together exactly what the bank holds")
  Same(c[1].forNames[1], "Make Bar")
  local ore = Rows(plan, "buy", ORE)[1]
  Same(ore.qty, 1, "the second ore for the bars is bought"); Same(ore.extra, 1)
  -- economic cost: the reagent is worth its price wherever it lies
  local line
  for _, r in ipairs(mk.make.reagents) do if r.item == ORE then line = r end end
  Same(line.qty, 2); Same(line.owned, 1, "1 owned"); Same(line.bank, 1); Same(line.bags, 0); Same(line.buy, 1)
  local priced = { [ORE] = { 10, 100, 1000 }, [BAR] = { 100, 100, 1000 } }
  local inBags = Plan(s, { entries = two, have = { [ORE] = 3 }, recipes = { [BAR] = { make } }, picks = { [BAR] = "make" }, auction = priced })
  local inBank = Plan(s, { entries = two, have = { [ORE] = 1 }, stock = { [ORE] = { 2 } }, recipes = { [BAR] = { make } }, picks = { [BAR] = "make" }, auction = priced })
  local a, b = Rows(inBags, "make", BAR)[1].make, Rows(inBank, "make", BAR)[1].make
  Check(a.cost ~= nil, "priced")
  Same(b.cost, a.cost, "the same materials cost the same whether they lie in the bags or in the bank")
  Same(b.cash, a.cash, "and need the same cash")
  -- a stored reagent is never promised twice: with only 1 ore in the bank for the sword's 2 + the bars' 2
  plan = Plan(s, { entries = two, have = { [ORE] = 0 }, stock = { [ORE] = { 1 } }, recipes = { [BAR] = { make } }, picks = { [BAR] = "make" } })
  c = Rows(plan, "collect", ORE)
  Same(c[1].qty, 1, "never more than the bank holds"); Same(Rows(plan, "buy", ORE)[1].qty, 3, "4 ore needed - 1 stored = 3 bought")
end

---------------------------------------------------------------------------
-- The window's numbers (Session): bags versus stored materials, readiness, Opportunities
---------------------------------------------------------------------------
do
  local s = Session()
  SeedQueue(s, { Entry(1, "Sword", 2, { { item = ORE, qty = 3 } }, SWORD) })   -- 6 ore
  local S = s.S
  s.g.bags[ORE] = 2
  local rows, sum, view = S.Materials()
  Same(sum.state, "short"); Same(S.Headline(sum), "Still needed: 1 material."); Same(rows[1].short, 4)
  Same(S.StockNote(sum, view), "Open your bank with Workshop loaded to update.", "unobserved storage is explained")
  s.St.StoreBank({ ids = { 6 }, tabs = { [6] = { [ORE] = 9 } }, incomplete = 0 }, 1000)
  rows, sum, view = S.Materials()
  Same(sum.state, "collect", "bags are not enough, the bank covers it: not 'ready'"); Same(S.Headline(sum), "Collect materials: 1 from your bank.")
  Same(rows[1].have, 2, "the bags are still just the bags"); Same(rows[1].fromBank, 4); Same(rows[1].short, 0); Check(S.StockNote(sum, view) == nil, "nothing to explain")
  s.g.bags[ORE] = 6
  rows, sum = S.Materials()
  Same(sum.state, "ready"); Same(S.Headline(sum), "Ready to craft: all the materials are in your bags.")
  Same(rows[1].fromBank, 0, "with the bags enough the bank is left alone")
  s.g.bags[ORE] = 1
  s.St.StoreBank({ ids = { 6 }, tabs = { [6] = { [ORE] = 2 } }, incomplete = 0 }, 1000)
  rows, sum = S.Materials()
  Same(S.Headline(sum), "Still needed: 1 material. 1 to collect from storage."); Same(rows[1].short, 3, "6 - 1 - 2")
  Same(s.g.calls.includeBank, 0, "the game's bank-inclusive counts were never asked for")
  -- the guild bank only when chosen
  s.St.StoreGuildTab(s.Guild(), 1, { n = { [ORE] = 10 }, by = s.Key(), w = 1, lim = 5, rem = -1 }, 1000, 1)
  rows, sum = S.Materials()
  Same(rows[1].short, 3, "the guild bank is ignored until the player chooses it (a guild is not even looked up for it)")
  S.SetUseGuild(true)
  rows, sum, view = S.Materials()
  Check(view.guild.enabled, "the choice is on")
  Same(rows[1].fromBank, 2); Same(rows[1].fromGuild, 3, "the rest, 3, from the guild bank"); Same(rows[1].short, 0, "and then nothing is missing")
  Same(sum.state, "collect"); Same(S.Headline(sum), "Collect materials: 1 from your bank and 1 from the guild bank.")
  -- someone else's rights on the tab: shown, not planned with
  s.St.StoreGuildTab(s.Guild(), 1, { n = { [ORE] = 10 }, by = "Alt - Realm", w = 1, lim = 5, rem = -1 }, 1000, 1)
  rows, sum, view = S.Materials()
  Same(rows[1].fromGuild, 0); Same(rows[1].short, 3, "viewing is not withdrawing")
  -- a source is chosen on the buy row, never on the collect row of the same material
  s.W.Vendor.Observe({ { id = ORE, price = 7, stack = 1, avail = -1 } }, { [ORE] = true }, 5)
  Check(S.CycleSource(ORE), "the click found the row")
  Same(S.picks[ORE], "vendor", "the source click reaches the buy row although a collect row for the same material comes first")
  S.PickSource(ORE, nil)
  -- Shopping: the same numbers, as rows
  local plan, ctx = S.Shopping()
  local kinds = {}
  for _, r in ipairs(plan.rows) do kinds[#kinds + 1] = r.kind .. ":" .. r.item .. ":" .. r.qty end
  Same(table.concat(kinds, ","), "collect:10:2,buy:10:3", "2 to collect from the bank, 3 to buy")
  Same(ctx.stock.guild.enabled, true)
end

-- Opportunities: stored materials never change a cost, a sell price or a profit; the row only says whether the craft can start
do
  local function Market(s)
    local P = s.W.Prices
    s.c.TwichUIDB.workshop = s.c.TwichUIDB.workshop or { v = 1 }
    s.c.TwichUIDB.workshop.prices = { v = 1, markets = { ["Realm|Alliance"] = { realm = "Realm", side = "Alliance", at = s.W.Queue.Now(), complete = true, read = 1,
      used = 1, n = 2, items = { [ORE] = { 100, 50, 5, 50 }, [SWORD] = { 1000, 5, 5, 5 } } } } }
  end
  local function Run(stocked)
    local s = Session()
    Market(s)
    local rec = { id = 1, name = "Sword", prof = 171, profName = "Alchemy", icon = 1, outItem = SWORD, outMin = 1, outMax = 1, mats = { { item = ORE, qty = 3 } },
      filled = true, remembered = true }
    s.c.TwichUIDB.workshop.chars = { [s.Key()] = { known = { [171] = { name = "Alchemy", at = 5, complete = true, r = { { 1, "Sword", 1, SWORD, 1, 1, 1, ORE, 3 } } } } } }
    s.g.bags[ORE] = 1
    if stocked then s.St.StoreBank({ ids = { 6 }, tabs = { [6] = { [ORE] = 20 } }, incomplete = 0 }, 1000) end
    local v = s.S.Opportunities()
    return v, s
  end
  local plain, stocked = Run(false), Run(true)
  local pr, sr = plain.rows[1], stocked.rows[1]
  Check(pr and sr, "a row each")
  Same(sr.est.state, "ok", tostring(sr.est.why))
  Same(sr.est.cost, 300, "3 ore at 100 each, however many are stored"); Same(sr.est.cost, pr.est.cost, "the cost is the same with and without stored materials")
  Same(sr.est.profitLow, pr.est.profitLow, "so is the profit"); Same(sr.est.sellLow, pr.est.sellLow)
  Same(sr.est.profitLow, 700, "1000 - 300")
  local a = stocked.avail(sr.rec)
  Same(a.state, "collect", "3 ore: 1 in the bags and 2 in the bank: collect"); Same(a.bags, 1); Same(a.bank, 2)
  Same(plain.avail(pr.rec).state, "short", "without the bank it is short")
  Same(stocked.source ~= nil, true)
  local s2 = Session()
  Market(s2)
  s2.g.bags[ORE] = 3
  local ready = s2.K.Craft({ { item = ORE, qty = 3 } }, s2.W.Observe.BagCount, s2.S.Stock())
  Same(ready.state, "ready", "all in the bags: ready to craft")
  Same(s2.W.Opps.AvailWord(ready), "Ready to craft"); Same(s2.W.Opps.AvailWord(a), "Collect materials"); Check(s2.W.Opps.AvailWord({ state = "short" }) == nil, "short says nothing")
  Same(s2.K.Craft({ { item = ORE, qty = 3 } }, function() return nil end, s2.S.Stock()).state, "unknown", "an unreadable bag count is unknown, never ready")
  -- the estimate's own lines never mention storage: it prices the full list
  local lines = s2.W.Opps.Basis({ rec = sr.rec, est = sr.est, avail = a }, nil, function() return "Ore" end, function(x) return tostring(x) end, 1000)
  local joined = {}
  for _, l in ipairs(lines) do joined[#joined + 1] = l[1] .. "|" .. tostring(l[2]) end
  joined = table.concat(joined, "\n")
  Check(joined:find("1 in bags, 2 in storage", 1, true) and joined:find("not free", 1, true), joined)
end

---------------------------------------------------------------------------
-- The recorder: the personal bank
---------------------------------------------------------------------------
do
  local s = Session()
  local Bk = s.W.Bank
  Same(Bk.Events(), 8, "eight events listened to from load: opened, closed, interaction, leaving, and the guild bank's items")
  Check(not s.frame.events.BAG_UPDATE_DELAYED and not s.frame.events.PLAYERBANKSLOTS_CHANGED and not s.frame.events.BANK_TABS_CHANGED,
    "the content events are not registered while no bank is open")
  s.Flush()   -- (the profession watcher's own start-up read is the one timer a fresh load has)
  Same(s.Timers(), 0, "and nothing is waiting or polling")
  s.Put(6, 1, ORE, 20); s.Put(6, 2, ORE, 5); s.Put(6, 3, HERB, 4); s.Put(7, 1, ORE, 5)
  s.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 68)
  Same(Bk.IsOpen().bank, false, "the warband bank (AccountBanker) is not the personal bank")
  s.OpenBank()
  Check(s.frame.events.BAG_UPDATE_DELAYED and s.frame.events.PLAYERBANKSLOTS_CHANGED and s.frame.events.BANK_TABS_CHANGED, "content events while it is open")
  Same(Bk.Events(), 11)
  Same(s.g.calls.slots, 0, "nothing is read until the burst settles")
  s.Fire("BANKFRAME_OPENED"); s.Fire("PLAYERBANKSLOTS_CHANGED", 1)
  s.Flush()
  local b = s.St.Bank()
  Same(b.tabs[6].n[ORE], 25, "two stacks of one item in one tab are added"); Same(b.tabs[6].n[HERB], 4); Same(b.tabs[7].n[ORE], 5)
  Same(b.tabs[6].at, 1000000, "with the time it was seen"); Check(not b.u)
  Same(Bk.reads, 1, "opened twice and changed once, read once")
  Same(s.g.calls.slots, 12, "6 slots of 2 tabs")
  Same(s.Timers(), 0)
  Check(s.W.Window == nil, "the window was never built or shown")
  -- closed: no more events, no more reads, even if the game talks
  s.CloseBank()
  Check(not s.frame.events.BAG_UPDATE_DELAYED and not s.frame.events.PLAYERBANKSLOTS_CHANGED, "events let go when it closes")
  s.Put(7, 2, HERB, 50)
  s.Fire("PLAYERBANKSLOTS_CHANGED", 2); s.Fire("BAG_UPDATE_DELAYED"); s.Flush()
  Same(s.g.calls.slots, 12, "a closed bank is not read"); Check(s.St.Bank().tabs[7].n[HERB] == nil, "and its remembered contents do not follow the game")

  -- a tab that cannot be read completely keeps its old record; the record is uncertain until a complete read
  s.OpenBank(); s.Flush()
  Same(s.St.Bank().tabs[7].n[HERB], 50, "reopened: read")
  s.g.bank.tabs[6].items[4] = { id = ORE, n = 1, bad = true }   -- a stack count the Workshop cannot read
  s.Put(7, 1, ORE, 9)
  s.Fire("BANK_TABS_CHANGED", 0); s.Flush()
  b = s.St.Bank()
  Same(b.tabs[6].n[ORE], 25, "tab 6 could not be read completely: its old record stays"); Same(b.tabs[7].n[ORE], 9, "tab 7 was: replaced"); Check(b.u, "uncertain")
  Same(select(1, s.K.Counted(s.S.Stock(), ORE)), 0, "an uncertain bank is not planned with")
  s.g.bank.tabs[6].items[4] = nil
  s.Fire("BANK_TABS_CHANGED", 0); s.Flush()
  b = s.St.Bank()
  Check(not b.u, "a complete read clears it"); Same(b.tabs[6].n[ORE], 25); Same(select(1, s.K.Counted(s.S.Stock(), ORE)), 34, "25 + 9")
  s.Fire("BANK_TABS_CHANGED", 2); s.Flush()   -- the warband bank's tabs changing is not ours
  Same(Bk.reads, 4, "(a different bank type's change reads nothing)")

  -- withdrawing: the bags gain what the bank loses, and the two must never both count
  SeedQueue(s, { Entry(1, "Sword", 11, { { item = ORE, qty = 3 } }, SWORD) })   -- 33 ore
  s.g.bags[ORE] = 0
  local rows, sum = s.S.Materials()
  Same(rows[1].fromBank, 33, "34 in the bank cover 33"); Same(sum.state, "collect")
  s.g.bags[ORE] = 5; s.g.bank.tabs[7].items[1] = nil   -- 5 of the 9 move to the bags... (the game shows 4 left in tab 7 after the move: 9 - 5)
  s.Put(7, 1, ORE, 4)
  s.Fire("PLAYERBANKSLOTS_CHANGED", 1); s.Fire("BAG_UPDATE_DELAYED")
  Check(Bk.Pending().bankPending, "a bag change with the bank open: the remembered bank is pending")
  rows, sum = s.S.Materials()
  Same(rows[1].fromBank, 0, "while pending the old 34 are not added to the 5 now in the bags (that would be 39 for a need of 33)")
  Same(rows[1].short, 28); Same(sum.state, "short", "no false 'collect', and never 'ready'")
  s.Flush()
  Check(not Bk.Pending().bankPending, "read again")
  rows, sum = s.S.Materials()
  Same(rows[1].have, 5); Same(rows[1].fromBank, 28, "bags 5 + bank 29 now: 28 to collect"); Same(rows[1].short, 0); Same(sum.state, "collect")
  Same(s.St.Bank().tabs[7].n[ORE], 4)
  -- a bank that closes before the read can happen is saved as uncertain, not as unchanged
  s.Fire("BAG_UPDATE_DELAYED"); s.CloseBank(); s.Flush()
  Check(s.St.Bank().u, "closed with a change unread: uncertain")
  Same(Bk.reads, 5, "and nothing was read after it closed")
  rows = s.S.Materials()
  Same(rows[1].fromBank, 0, "uncertain stock is not collected from")
  s.OpenBank(); s.Flush()
  Check(not s.St.Bank().u, "the next visit makes it certain again")
  Same(s.g.calls.includeBank, 0, "the bank-inclusive game count was never used")

  -- the game gives no tab list, or the bank cannot be viewed: not an empty bank
  s.g.bank.ids = {}
  s.Fire("BANK_TABS_CHANGED", 0); s.Flush()
  Same(s.St.Bank().tabs[7].n[ORE], 4, "nothing is erased"); Check(s.St.Bank().u, "but what is remembered is doubted")
  s.g.bank.ids = { 6, 7 }
  s.Fire("BANK_TABS_CHANGED", 0); s.Flush()
  s.g.bank.view = false
  local calls = s.g.calls.slots
  s.Fire("BAG_UPDATE_DELAYED"); s.Flush()
  Same(s.g.calls.slots, calls, "a bank the game says cannot be viewed is not read")
  Check(s.St.Bank().u, "and the record is doubted")
  s.Fire("PLAYER_LEAVING_WORLD")
  Same(Bk.IsOpen().bank, false, "leaving the world closes it")
  Same(s.Timers(), 0, "no timers left")
end

-- a bank that is already open when the addon loads is read at load, with no event
do
  local s = Session("Rich", nil, { bankOpen = true })
  Same(s.W.Bank.IsOpen().bank, true); Same(s.St.Bank(), nil, "nothing yet: the read waits for the burst to settle")
  s.Put(6, 1, ORE, 7)
  s.Flush()
  Same(s.St.Bank().tabs[6].n[ORE], 7, "read at load")
  Check(s.frame.events.BAG_UPDATE_DELAYED, "and its changes are followed")
end
-- no bank ever opens: nothing is read, saved or registered
do
  local s = Session()
  s.Put(6, 1, ORE, 7)
  s.Flush()
  Same(s.g.calls.slots, 0); Check(s.c.TwichUIDB.workshop == nil or s.c.TwichUIDB.workshop.storage == nil, "nothing saved")
end

---------------------------------------------------------------------------
-- The recorder: the guild bank
---------------------------------------------------------------------------
do
  local s = Session()
  local Bk, St = s.W.Bank, s.St
  local guild = s.Guild()
  s.OpenGuild()
  Check(s.frame.events.BAG_UPDATE_DELAYED, "content events while it is open")
  s.GPut(1, 1, ORE, 12); s.GPut(1, 2, ORE, 8); s.GPut(1, 3, HERB, 2)
  s.Fire("GUILDBANKBAGSLOTS_CHANGED")
  local rec = St.Guild(guild)
  Same(rec.tabs[1].n[ORE], 20); Same(rec.tabs[1].n[HERB], 2); Same(rec.tabs[1].by, s.Key(), "who saw it, and so whose rights these are")
  Same(rec.tabs[1].w, 1); Same(rec.tabs[1].rem, -1); Same(rec.nt, 3, "the guild bank has three tabs")
  Same(rec.tabs[1].at, 1000000)
  Same(Bk.guildReads, 1)
  -- an empty answer right after a tab change is not believed (an unsent tab looks the same); a non-empty one is
  s.g.guild.current = 2
  s.g.guild.tabs[2] = { items = {} }
  s.Fire("GUILDBANKBAGSLOTS_CHANGED")
  rec = St.Guild(guild)
  Check(rec.tabs[2] == nil, "tab 2 stays unread: the first answer after the switch was empty and cannot be told from 'not sent yet'")
  s.Fire("GUILDBANKBAGSLOTS_CHANGED")
  rec = St.Guild(guild)
  Check(rec.tabs[2] and next(rec.tabs[2].n) == nil, "the same tab answering empty again is a real change: now it is an empty tab")
  s.g.guild.current = 3
  s.GPut(3, 1, HERB, 6)
  s.Fire("GUILDBANKBAGSLOTS_CHANGED")
  Same(St.Guild(guild).tabs[3].n[HERB], 6, "a non-empty answer is believed at once")
  -- emptying the tab you are looking at is believed (same tab twice)
  s.g.guild.tabs[3].items = {}
  s.Fire("GUILDBANKBAGSLOTS_CHANGED")
  Check(next(St.Guild(guild).tabs[3].n) == nil, "taking out the last item of the shown tab")
  -- a tab the player cannot view is never read, and nothing is erased
  s.g.guild.current = 2; s.g.guild.tabs[2].viewable = false
  s.Fire("GUILDBANKBAGSLOTS_CHANGED")
  Check(St.Guild(guild).tabs[2] ~= nil, "an existing record stays"); Same(Bk.guildReads, 4, "(a tab that cannot be viewed is not a read)")
  -- a slot whose item cannot be identified: the tab is not replaced
  s.g.guild.current = 1
  s.GPut(1, 4, 99, 3, { nolink = true })
  s.Fire("GUILDBANKBAGSLOTS_CHANGED")
  Same(St.Guild(guild).tabs[1].n[ORE], 20, "a partial read replaces nothing"); Check(St.Guild(guild).tabs[1].n[99] == nil)
  s.g.guild.tabs[1].items[4] = nil
  -- withdrawing: the bag change may come first; the answer clears it
  s.g.t = 200
  s.g.bags[ORE] = 4; s.g.guild.tabs[1].items[2] = nil   -- 8 taken
  s.Fire("BAG_UPDATE_DELAYED")
  Check(Bk.Pending().guildPending, "bag change first: the guild stock is pending")
  s.Fire("GUILDBANKBAGSLOTS_CHANGED")
  Check(not Bk.Pending().guildPending, "answered"); Same(St.Guild(guild).tabs[1].n[ORE], 12, "20 - 8")
  s.Flush()
  Check(not St.Guild(guild).tabs[1].u, "and a late timer from the move changes nothing")
  -- the answer may come first; a bag change right after is the same move
  s.g.t = 300
  s.Fire("GUILDBANKBAGSLOTS_CHANGED"); s.g.t = 300.4
  s.Fire("BAG_UPDATE_DELAYED")
  Check(not Bk.Pending().guildPending, "answer first, bag change within a second: the same move, not a doubt")
  -- a bag change nobody answers: the shown tab is saved as uncertain, and not planned with
  s.g.t = 400
  s.Fire("BAG_UPDATE_DELAYED")
  s.Flush()
  Check(St.Guild(guild).tabs[1].u, "no answer followed: that tab may have changed")
  Check(not Bk.Pending().guildPending)
  local v = s.K.Sources({ char = s.Key(), guild = guild }, true, nil, 2000)
  Same(select(2, s.K.Counted(v, ORE)), 0, "uncertain guild stock is not counted"); Same(v.guild.uncertain, 1)
  s.g.t = 500
  s.Fire("GUILDBANKBAGSLOTS_CHANGED")
  Check(not St.Guild(guild).tabs[1].u, "the next answer is a fresh read")
  Same(select(2, s.K.Counted(s.K.Sources({ char = s.Key(), guild = guild }, true, nil, 2000), ORE)), 12)
  -- closing with a bag change unanswered
  s.g.t = 600
  s.Fire("BAG_UPDATE_DELAYED"); s.CloseGuild()
  Check(St.Guild(guild).tabs[1].u, "closed before the answer: uncertain")
  Check(not s.frame.events.BAG_UPDATE_DELAYED, "events let go")
  s.g.guild.tabs[1].items[1].n = 1
  s.Fire("GUILDBANKBAGSLOTS_CHANGED")
  Same(St.Guild(guild).tabs[1].n[ORE], 12, "a closed guild bank is not read")
  s.Flush()
  Same(s.Timers(), 0, "no timers left")

  -- another guild: its own record, the first one untouched, never mixed
  s.g.guild.name, s.g.guild.club = "Others", 5
  s.OpenGuild()
  s.g.guild.current = 1; s.g.guild.tabs = { [1] = { items = {} } }
  s.GPut(1, 1, ORE, 3)
  s.Fire("GUILDBANKBAGSLOTS_CHANGED")
  local other = { key = "Others-Realm", name = "Others", club = "5" }
  Same(St.Guild(other).tabs[1].n[ORE], 3); Same(St.Guild(guild).tabs[1].n[ORE], 12, "the first guild's record is kept")
  Same(select(2, s.K.Counted(s.K.Sources({ char = s.Key(), guild = other }, true, nil, 2000), ORE)), 3, "the guild you are in now")
  -- the planning asks the game which guild this is, and uses only that guild's record
  s.S.SetUseGuild(true)
  local cur = s.S.Stock()
  Same(select(2, s.K.Counted(cur, ORE)), 3, "in Others now: Others' stock, not Raiders'")
  s.g.guild.name = nil
  cur = s.S.Stock()
  Same(select(2, s.K.Counted(cur, ORE)), 0, "after leaving the guild no guild's stock counts"); Check(not cur.guild.inGuild)
  s.g.guild.name, s.g.guild.club = "Raiders", 77
  cur = s.S.Stock()
  Same(cur.guild.info[ORE], 12, "and back in the first guild its remembered stock is back, as information: that tab was left uncertain above")
  Same(select(2, s.K.Counted(cur, ORE)), 0, "and not counted until it is seen again")
end

-- the guild bank can answer before any "opened" event; and a guild bank already open at load
do
  local s = Session()
  s.c.GuildBankFrame.shown = true
  s.GPut(1, 1, ORE, 5)
  s.Fire("GUILDBANKBAGSLOTS_CHANGED")
  Same(s.W.Bank.IsOpen().guild, true, "a guild bank that is showing is open, whatever the events said")
  Same(s.St.Guild(s.Guild()).tabs[1].n[ORE], 5)
  local hidden = Session()
  hidden.GPut(1, 1, ORE, 5)
  hidden.Fire("GUILDBANKBAGSLOTS_CHANGED")
  Check(hidden.St.Guild(hidden.Guild()) == nil, "an answer with no guild bank showing is ignored")
  local atLoad = Session("Rich", nil, { guildOpen = true, setup = function(g)
    g.guild.tabs[1] = { items = { [1] = { id = ORE, n = 9 } } }
  end })
  Same(atLoad.St.Guild(atLoad.Guild()).tabs[1].n[ORE], 9, "read at load, the item list being non-empty")
  local emptyAtLoad = Session("Rich", nil, { guildOpen = true })
  Check(emptyAtLoad.St.Guild(emptyAtLoad.Guild()) == nil, "an empty tab at load is not believed")
  -- not in a guild: nothing is recorded
  local lone = Session("Rich", nil, { guildOpen = true, setup = function(g) g.guild.name = nil; g.guild.tabs[1] = { items = { [1] = { id = ORE, n = 9 } } } end })
  Check(lone.c.TwichUIDB.workshop == nil or lone.c.TwichUIDB.workshop.storage == nil, "no guild, no record")
end

---------------------------------------------------------------------------
-- Records come back with their times (a new client on the saved data)
---------------------------------------------------------------------------
do
  local a = Session()
  a.Put(6, 1, ORE, 30)
  a.OpenBank(); a.Flush()
  a.c.GuildBankFrame.shown = true
  a.GPut(1, 1, ORE, 11)
  a.Fire("GUILDBANKBAGSLOTS_CHANGED")
  a.S.SetUseGuild(true)
  SeedQueue(a, { Entry(1, "Sword", 5, { { item = ORE, qty = 3 } }, SWORD) })
  local db = a.c.TwichUIDB
  local b = Session("Rich", db)
  b.g.time = 1000000 + 2 * 86400 + 100
  b.g.bags[ORE] = 1
  local rows, sum, view = b.S.Materials()
  Same(rows[1].have, 1); Same(rows[1].fromBank, 14, "15 ore needed: 1 in bags, 14 from the bank's remembered 30")
  Same(rows[1].fromGuild, 0, "the bank covers it")
  Same(view.bank.at, 1000000, "the observation time came back with the record")
  local plan, ctx = b.S.Shopping()
  Same(plan.rows[1].kind, "collect"); Same(plan.rows[1].qty, 14); Same(plan.rows[1].at, 1000000)
  local lines = b.K.Lines(view, ORE, 1, function(at) return b.W.Prices.AgeText(b.W.Queue.Now() - at) end)
  Check(lines[2]:find("Bank 30, seen 2 days ago", 1, true), lines[2])
  Check(lines[3]:find("Guild bank 11, seen 2 days ago", 1, true), lines[3])
  Check(b.S.UseGuild(), "the choice came back")
  Same(b.S.StockNote(sum, view), "2 guild bank tabs not seen yet.", "the bank was seen; the guild bank's other two tabs were not: unread, not empty")
  -- corrupt saved records are skipped, not used and not repaired into zeros
  db.workshop.storage.chars[b.Key()].bank.tabs[6].n[ORE] = "many"
  db.workshop.storage.guilds["Raiders-Realm"].tabs[1].at = "yesterday"
  local c2 = Session("Rich", db)
  local v2 = c2.S.Stock()
  Same(v2.bank.items[ORE], nil, "a bad count is no count"); Check(not v2.guild.seen, "a tab with no usable time is no tab")
  -- nothing in all this scanned idly
  Same(a.Timers(), 0)
end

print("PASSED")
