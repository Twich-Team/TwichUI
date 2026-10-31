-- A stand-in guild bank "server" for the guild bank run tests (inventory/GuildRun.lua). It is a script of the Blizzard
-- guild bank UI's behaviour as far as the source shows it (a pickup puts the stack on the cursor and locks the slot, a second
-- pickup on a slot places it, a split puts a part on the cursor), with the server's answer separated from the request so
-- tests decide WHEN and HOW it answers. It is not the game: nothing here shows what the game does.
--
-- GuildSim(c) -> S, on a client from MIClient (tests/mi_mock.lua)
--   S.NOW                      the fake clock (c.GetTime); S.Tick(dt) advances it and runs the timers that fall due
--   S.cursor                   what the cursor holds: { id, count, from = { kind, a, b } } or { other = true, id }
--   S.queue                    requests the server has not answered yet
--   S.Settle(opts)             the server answers every queued request. opts.events = false: answer without any event;
--                              opts.dup = n: n copies of each event; opts.drop = { [i] = true }: request i is lost (never happens)
--   S.Pump(rounds)             timers and answers until nothing is left to do (a cooperative server)
--   S.Open(tab)/S.Show(tab)    the guild bank opens / shows a tab (and the server sends its items)
--   S.Tabs()                   gives the frame its own tab buttons (GuildBankFrame.BankTabs[n]:OnClick, as Blizzard_GuildBankUI.lua
--                              has them: show the tab, then ask the server for it) and QueryGuildBankTab. Without it the addon
--                              cannot show a tab (the older tests rely on that). The answer is a request in S.queue like a move,
--                              so tests decide when (and whether) it comes; the event it fires carries no tab, as in the game.
--                              S.noAnswer[tab] = true: that tab's queries are never answered; S.noQueryAnswer[tab] = true: only a
--                              QueryGuildBankTab call for it goes unanswered (showing the tab still works). S.clicks / S.queries: what was asked.
--   S.offTab                   pickups, splits and places that named a tab other than the one shown (the addon must never do one)
--   S.moves                    what the server actually did: { id, count, from, to, merge }
--   S.calls                    every Pickup/Split call made, in order: { "pickup"|"split", kind, a, b, n }
--   S.swaps                    placements onto a slot holding another item (the run must never cause one)
--   S.bounce = n               the next n placements are silently given back: the item returns to its slot, nothing moves, no word
--   S.refuse, S.requireClick   the game ignores requests / raises ADDON_ACTION_BLOCKED unless S.inClick
--   S.Total(id)                an item's total in the bags and every guild tab, plus what the cursor holds

function GuildSim(c)
  local S = { NOW = 100, timers = {}, queue = {}, moves = {}, calls = {}, swaps = 0 }
  -- the run's pacing (a pause after each move, and before a second try) is off here so the older tests stay in step with the clock;
  -- the pacing tests turn it on (GuildRun.GAP / .SETTLE)
  local GRm = c.TwichUI and c.TwichUI.MagicInventory and c.TwichUI.MagicInventory.GuildRun
  if GRm then GRm.GAP, GRm.SETTLE = 0, 0 end
  c.GetTime = function() return S.NOW end
  c.C_Timer.After = function(d, fn) S.timers[#S.timers + 1] = { due = S.NOW + d, fn = fn } end

  function S.Tick(dt)
    local target = S.NOW + (dt or 0)
    local ran = 0
    while true do
      local best, bi
      for i, t in ipairs(S.timers) do if t.due <= target and (not best or t.due < best.due) then best, bi = t, i end end
      if not best then break end
      table.remove(S.timers, bi)
      if best.due > S.NOW then S.NOW = best.due end
      best.fn()
      ran = ran + 1
    end
    S.NOW = target
    return ran
  end

  -- runs only the timers that are due now (not the ones they schedule): the gap between two steps of a run
  function S.Step()
    local due = {}
    for i = #S.timers, 1, -1 do
      if S.timers[i].due <= S.NOW then table.insert(due, 1, table.remove(S.timers, i)) end
    end
    for _, t in ipairs(due) do t.fn() end
    return #due
  end

  local function Cell(kind, a, b)
    if kind == "bag" then return c.BAGS[a] and c.BAGS[a].slots[b] end
    return c.GUILD.tabs[a] and c.GUILD.tabs[a].slots[b]
  end
  local function SetCell(kind, a, b, v)
    if kind == "bag" then c.BAGS[a].slots[b] = v else c.GUILD.tabs[a].slots[b] = v end
  end
  S.Cell = Cell

  c.CursorHasItem = function() return S.cursor ~= nil end
  c.GetCursorInfo = function() if not S.cursor then return nil end return "item", S.cursor.id end
  c.ClearCursor = function() S.cleared = (S.cleared or 0) + 1 end   -- the run must never call it

  local function Blocked()
    -- S.requireClick: the game wants a click for these calls (S.onlyPlace: only for placing what the cursor holds)
    if S.requireClick and not S.inClick and (not S.onlyPlace or S.cursor ~= nil) then
      c.FireEvent("ADDON_ACTION_BLOCKED", "!!!TwichUI", "PickupGuildBankItem")
      return true
    end
  end

  local Pickup0
  local function Pickup(kind, a, b)
    Pickup0(kind, a, b)
    if S.hook then S.hook(#S.calls, S.calls[#S.calls]) end   -- a test can act right after a call (a player's click, a change)
  end
  Pickup0 = function(kind, a, b)
    S.calls[#S.calls + 1] = { "pickup", kind, a, b }
    if kind == "guild" and a ~= c.GUILD.current then S.offTab = (S.offTab or 0) + 1 end
    if Blocked() or S.refuse then return end
    local cell = Cell(kind, a, b)
    if not S.cursor then
      if cell and not cell.locked then
        S.cursor = { id = cell.id, count = cell.count, from = { kind, a, b } }
        cell.locked = true
        c.FireEvent("GUILDBANK_ITEM_LOCK_CHANGED"); c.FireEvent("CURSOR_CHANGED")
      end
      return
    end
    local cur = S.cursor
    if cur.other then return end
    local f = cur.from
    if f[1] == kind and f[2] == a and f[3] == b then   -- dropped back on its own slot
      if cell then cell.locked = false end
      S.cursor = nil
      c.FireEvent("CURSOR_CHANGED")
      return
    end
    if kind ~= "guild" or S.destRefuses then return end   -- the item stays on the cursor
    if S.bounce and S.bounce > 0 then
      S.bounce = S.bounce - 1
      local from = Cell(f[1], f[2], f[3])
      if from then from.locked = false end
      S.cursor = nil
      c.FireEvent("CURSOR_CHANGED"); c.FireEvent("GUILDBANK_ITEM_LOCK_CHANGED")
      return
    end
    local to = { kind, a, b }
    if cell and cell.id ~= cur.id then S.swaps = S.swaps + 1 end
    S.queue[#S.queue + 1] = { id = cur.id, count = cur.count, from = f, to = to, swap = cell and cell.id ~= cur.id or nil }
    S.cursor = nil
    c.FireEvent("CURSOR_CHANGED")
  end
  c.C_Container.PickupContainerItem = function(bag, slot) Pickup("bag", bag, slot) end
  c.PickupGuildBankItem = function(tab, slot) Pickup("guild", tab, slot) end

  local function Split(kind, a, b, n)
    S.calls[#S.calls + 1] = { "split", kind, a, b, n }
    if kind == "guild" and a ~= c.GUILD.current then S.offTab = (S.offTab or 0) + 1 end
    if not (Blocked() or S.refuse or S.cursor) then
      local cell = Cell(kind, a, b)
      if cell and not cell.locked and n < cell.count then
        S.cursor = { id = cell.id, count = n + (S.splitDelta or 0), from = { kind, a, b }, split = true }   -- splitDelta: the server splits off the wrong amount
        cell.locked = true
        c.FireEvent("GUILDBANK_ITEM_LOCK_CHANGED"); c.FireEvent("CURSOR_CHANGED")
      end
    end
    if S.hook then S.hook(#S.calls, S.calls[#S.calls]) end
  end
  c.C_Container.SplitContainerItem = function(bag, slot, n) Split("bag", bag, slot, n) end
  c.SplitGuildBankItem = function(tab, slot, n) Split("guild", tab, slot, n) end

  local function Fire(opts, bags)
    if opts.events == false then return end
    for _ = 1, opts.dup or 1 do
      c.FireEvent("GUILDBANKBAGSLOTS_CHANGED")
      c.FireEvent("GUILDBANK_ITEM_LOCK_CHANGED")
      if bags then c.FireEvent("BAG_UPDATE_DELAYED") end
    end
  end

  -- the server answers every request that is waiting
  function S.Settle(opts)
    opts = opts or {}
    local q = S.queue
    S.queue = {}
    local bags = false
    local answered = 0
    for i, r in ipairs(q) do
      if r.query then
        if not (S.noAnswer and S.noAnswer[r.query]) and not (r.viaQuery and S.noQueryAnswer and S.noQueryAnswer[r.query]) then answered = answered + 1 end
      else
        answered = answered + 1
        local src = Cell(r.from[1], r.from[2], r.from[3])
        local dst = Cell(r.to[1], r.to[2], r.to[3])
        if src then src.locked = false end
        if dst then dst.locked = false end
        if r.from[1] == "bag" then bags = true end
        if not (opts.drop and opts.drop[i]) and not (S.reject and S.reject(r)) and src and not r.swap then
          local maxStack = c.ITEMS[r.id].maxStack or 20
          local take = src and math.min(r.count, src.count) or r.count
          if dst then take = math.min(take, maxStack - dst.count) end
          if take > 0 then
            if take >= src.count then SetCell(r.from[1], r.from[2], r.from[3], nil) else src.count = src.count - take end
            if dst then dst.count = dst.count + take else SetCell(r.to[1], r.to[2], r.to[3], { id = r.id, count = take }) end
            S.moves[#S.moves + 1] = { id = r.id, count = take, from = r.from, to = r.to, merge = dst ~= nil }
          end
        end
      end
    end
    if answered > 0 then Fire(opts, bags) end
    return #q
  end

  -- the frame's own tab buttons and QueryGuildBankTab (see the header)
  function S.Tabs()
    local f = c.GuildBankFrame
    f.mode = "bank"
    f.BankTabs = {}
    S.clicks, S.queries = {}, {}
    for i = 1, 8 do
      f.BankTabs[i] = { OnClick = function(_, button)
        S.clicks[#S.clicks + 1] = i
        c.GUILD.current = i
        S.queue[#S.queue + 1] = { query = i }
        if S.tabHook then S.tabHook(i) end
      end }
    end
    c.QueryGuildBankTab = function(tab)
      S.queries[#S.queries + 1] = tab
      S.queue[#S.queue + 1] = { query = tab, viaQuery = true }
    end
  end

  function S.Pump(rounds)
    for _ = 1, rounds or 60 do
      local ran = S.Tick(0)
      local settled = S.Settle()
      if ran == 0 and settled == 0 then return end
    end
  end

  function S.Open(tab)
    c.GUILD.current = tab or c.GUILD.current
    c.GUILD.open = true
    c.FireEvent("GUILDBANKFRAME_OPENED")
    c.FireEvent("GUILDBANKBAGSLOTS_CHANGED")
  end
  -- This client opens and closes the guild bank through the player interaction manager (type 10) and may never send
  -- GUILDBANKFRAME_OPENED / _CLOSED. S.OpenManager / S.CloseManager do only that; S.OpenQuiet sends nothing but the items.
  function S.OpenManager(tab)
    c.GUILD.current = tab or c.GUILD.current
    c.GUILD.open = true
    c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
    c.FireEvent("GUILDBANKBAGSLOTS_CHANGED")
  end
  function S.CloseManager()
    c.GUILD.open = false
    c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10)
  end
  function S.OpenQuiet(tab)
    c.GUILD.current = tab or c.GUILD.current
    c.GUILD.open = true
    c.FireEvent("GUILDBANKBAGSLOTS_CHANGED")
  end
  function S.Show(tab)
    c.GUILD.current = tab
    c.FireEvent("GUILDBANKBAGSLOTS_CHANGED")
  end

  function S.Total(id)
    local n = 0
    for _, b in pairs(c.BAGS) do for _, s in pairs(b.slots) do if s.id == id then n = n + s.count end end end
    for _, t in pairs(c.GUILD.tabs) do for _, s in pairs(t.slots) do if s.id == id then n = n + s.count end end end
    -- an item on the cursor is still in its slot until the server answers
    return n
  end
  function S.TabCount(tab, id)
    local n = 0
    for _, s in pairs(c.GUILD.tabs[tab].slots) do if s.id == id then n = n + s.count end end
    return n
  end

  return S
end
