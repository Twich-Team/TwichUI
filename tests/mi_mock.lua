-- A client for Magic Inventory's tests (inventory/): TwichUI's core with the feature's files loaded, and stand-ins
-- for the game's items, bags, cursor, mailbox, bank and guild bank. Nothing here is the game: whether the game
-- attaches, sends, deposits or refuses is the mock's, set by each test.
--
-- MIClient(name) -> c
--   c.ITEMS[id] = { name, quality, class, sub, equipLoc, bind, maxStack }   what the game knows of an item
--   c.UNLOADED[id] = true                                                 not loaded yet (GetItemInfo returns nothing)
--   c.Bags({ [bag] = { size, slots = { [slot] = { id, count, bound, locked, quest, inSet, conjured } } } })
--   c.CURSOR: what is on the cursor ({ bag, slot, id, count } from a bag, or { other = true })
--   c.MAIL: the send-mail state { open, sendShown, name, subject, body, money, cod, attach = { [i] = {id,count,bag,slot} } }
--   c.BANK: { open, bags = { [bagID] = size } } (bank tabs are ordinary bag IDs in c.BAGS)
--   c.GUILD: { name, open, current, tabs = { [tab] = { name, canDeposit, slots = { [slot] = { id, count } } } } }
--   c.SENT: mails the "server" took: { to, subject, items = { {id, count} } }
--   c.DEPOSITS: moves into the bank or guild bank
--   c.Settle(): the "server" answers: queued bag/mail/guild events fire (BAG_UPDATE_DELAYED etc.)

dofile(TESTS .. "harness.lua")

local INVENTORY = { "inventory/Rules.lua", "inventory/Items.lua", "inventory/Plan.lua", "inventory/Run.lua", "inventory/Window.lua", "inventory/Picker.lua" }

function MIClient(name, opts)
  opts = opts or {}
  local c = MakeClient(name or "Rich", { "!!!TwichUI" })
  c.R_OUT = {}
  c.print = function(s) table.insert(c.R_OUT, tostring(s)) end
  c.COMBAT = false
  c.InCombatLockdown = function() return c.COMBAT end
  c.UnitClass = function() return "Warrior", "WARRIOR" end
  c.NUM_BAG_SLOTS = 4
  c.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4
  c.ATTACHMENTS_MAX_SEND = 12
  c.ITEM_CONJURED = "Conjured Item"
  c.MONEY = 100000
  c.GetMoney = function() return c.MONEY end
  c.issecretvalue = nil

  -- items
  c.ITEMS, c.UNLOADED, c.REQUESTED = {}, {}, {}
  c.C_Item = {
    GetItemInfoInstant = function(id)
      local i = c.ITEMS[id]
      if i then return id, "", "", i.equipLoc or "", 1000 + id, i.class or 15, i.sub or 0 end
    end,
    GetItemInfo = function(id)
      local i = c.ITEMS[id]
      if not i or c.UNLOADED[id] then return nil end
      return i.name, "|cff|Hitem:" .. id .. "|h[" .. i.name .. "]|h|r", i.quality or 1, 1, 1, "", "", i.maxStack or 20,
        i.equipLoc or "", 1000 + id, 1, i.class or 15, i.sub or 0, i.bind or 0
    end,
    GetItemMaxStackSizeByID = function(id) local i = c.ITEMS[id]; return i and (i.maxStack or 20) end,
    RequestLoadItemDataByID = function(id) c.REQUESTED[id] = (c.REQUESTED[id] or 0) + 1 end,
    GetItemSubClassInfo = function(cls, sub)
      local names = { ["7:5"] = "Cloth", ["7:9"] = "Herb", ["7:7"] = "Metal & Stone", ["7:6"] = "Leather", ["0:5"] = "Food & Drink" }
      return names[cls .. ":" .. sub]
    end,
    GetItemClassInfo = function(cls) return ({ [7] = "Trade Goods", [0] = "Consumable", [5] = "Reagent", [9] = "Recipe", [3] = "Gem", [6] = "Projectile", [15] = "Miscellaneous" })[cls] end,
    GetItemFamily = function() return 0 end,
  }
  c.C_AuctionHouse = { GetAuctionItemSubClasses = function(cls) if cls == 7 then return { 5, 6, 7, 9 } elseif cls == 0 then return { 5 } end return {} end }
  c.ITEMS[2589] = { name = "Linen Cloth", class = 7, sub = 5, maxStack = 20, quality = 1 }
  c.ITEMS[2592] = { name = "Wool Cloth", class = 7, sub = 5, maxStack = 20, quality = 1 }
  c.ITEMS[2447] = { name = "Peacebloom", class = 7, sub = 9, maxStack = 20, quality = 1 }
  c.ITEMS[2770] = { name = "Copper Ore", class = 7, sub = 7, maxStack = 20, quality = 1 }
  c.ITEMS[4306] = { name = "Silk Cloth", class = 7, sub = 5, maxStack = 20, quality = 1 }
  c.ITEMS[6948] = { name = "Hearthstone", class = 15, sub = 0, maxStack = 1, quality = 1, bind = 1 }
  c.ITEMS[9001] = { name = "Green Sword", class = 2, sub = 7, maxStack = 1, quality = 2, bind = 2, equipLoc = "INVTYPE_WEAPON" }
  c.ITEMS[9002] = { name = "Green Boots", class = 4, sub = 2, maxStack = 1, quality = 2, bind = 2, equipLoc = "INVTYPE_FEET" }
  c.ITEMS[9003] = { name = "Blue Ring", class = 4, sub = 0, maxStack = 1, quality = 3, bind = 2, equipLoc = "INVTYPE_FINGER" }
  c.ITEMS[9004] = { name = "Green Cloak BoP", class = 4, sub = 1, maxStack = 1, quality = 2, bind = 1, equipLoc = "INVTYPE_CLOAK" }
  c.ITEMS[5175] = { name = "Earth Totem", class = 15, sub = 0, maxStack = 1, quality = 1, bind = 0 }
  c.ITEMS[8079] = { name = "Conjured Crystal Water", class = 0, sub = 5, maxStack = 20, quality = 1 }
  c.ITEMS[1179] = { name = "Ice Cold Milk", class = 0, sub = 5, maxStack = 20, quality = 1 }
  c.ITEMS[5000] = { name = "Quest Thing", class = 12, sub = 0, maxStack = 20, quality = 1, bind = 4 }

  -- bags: [bag] = { size, slots = { [slot] = { id, count, bound, locked, quest, inSet, conjured } } }
  c.BAGS = {}
  function c.Bags(spec)
    c.BAGS = {}
    for bag, b in pairs(spec) do
      c.BAGS[bag] = { size = b.size or 16, family = b.family or 0, slots = {} }
      for slot, s in pairs(b.slots or {}) do
        c.BAGS[bag].slots[slot] = { id = s[1], count = s[2], bound = s.bound or false, locked = s.locked or false,
          quest = s.quest, inSet = s.inSet, conjured = s.conjured }
      end
    end
  end
  c.Bags({ [0] = { size = 16 } })
  c.TOOLTIP_UNREADABLE = {}
  c.C_TooltipInfo = { GetBagItem = function(bag, slot)
    local s = c.BAGS[bag] and c.BAGS[bag].slots[slot]
    if not s or c.TOOLTIP_UNREADABLE[s.id] then return nil end
    local lines = { { leftText = c.ITEMS[s.id] and c.ITEMS[s.id].name or "?" } }
    if s.conjured then lines[2] = { leftText = "Conjured Item" } end
    return { lines = lines }
  end }
  c.C_Container = {
    GetContainerNumSlots = function(bag) return c.BAGS[bag] and c.BAGS[bag].size or 0 end,
    GetContainerItemInfo = function(bag, slot)
      local s = c.BAGS[bag] and c.BAGS[bag].slots[slot]
      if not s then return nil end
      local i = c.ITEMS[s.id] or {}
      local locked = s.locked
      if c.CURSOR and c.CURSOR.bag == bag and c.CURSOR.slot == slot then locked = true end
      for _, a in pairs(c.MAIL.attach) do if a.bag == bag and a.slot == slot then locked = true end end
      if c.UNKNOWN_BOUND and c.UNKNOWN_BOUND[s.id] then return { itemID = s.id, stackCount = s.count, isLocked = locked, iconFileID = 1, hyperlink = "[" .. (i.name or "?") .. "]" } end
      return { itemID = s.id, stackCount = s.count, isBound = s.bound, isLocked = locked, iconFileID = 1,
        hyperlink = "|cff|Hitem:" .. s.id .. "|h[" .. (i.name or "?") .. "]|h|r" }
    end,
    GetContainerItemQuestInfo = function(bag, slot)
      local s = c.BAGS[bag] and c.BAGS[bag].slots[slot]
      if not s then return nil end
      return { isQuestItem = s.quest or false, isActive = false }
    end,
    GetContainerItemEquipmentSetInfo = function(bag, slot)
      local s = c.BAGS[bag] and c.BAGS[bag].slots[slot]
      if not s then return nil end
      return s.inSet or false, ""
    end,
    GetContainerNumFreeSlots = function(bag)
      local b = c.BAGS[bag]
      if not b then return 0, 0 end
      local free = 0
      for slot = 1, b.size do if not b.slots[slot] then free = free + 1 end end
      return free, b.family
    end,
  }

  -- the cursor
  c.CURSOR = nil
  c.PICKUPS = {}
  c.CursorHasItem = function() return c.CURSOR ~= nil end
  c.GetCursorInfo = function()
    if not c.CURSOR then return nil end
    if c.CURSOR.other then return "item", 1234 end
    return "item", c.CURSOR.id
  end
  c.ClearCursor = function()
    c.CURSOR = nil
    c.CLEARED = (c.CLEARED or 0) + 1
  end
  -- PickupContainerItem: from a bag (or onto a bag slot when something is held)
  c.C_Container.PickupContainerItem = function(bag, slot)
    table.insert(c.PICKUPS, { bag = bag, slot = slot })
    local b = c.BAGS[bag]
    if not b then return end
    local s = b.slots[slot]
    if not c.CURSOR then
      if s and not s.locked then c.CURSOR = { bag = bag, slot = slot, id = s.id, count = s.count } end
      return
    end
    if c.CURSOR.other then return end
    -- dropping what is held
    if c.CURSOR.bag == bag and c.CURSOR.slot == slot then c.CURSOR = nil return end   -- put back
    if c.BANK_REFUSES then return end   -- the item stays on the cursor
    local held = c.CURSOR
    local src = c.BAGS[held.bag].slots[held.slot]
    if s == nil then
      c.PENDING_MOVES = c.PENDING_MOVES or {}
      table.insert(c.PENDING_MOVES, { from = { held.bag, held.slot }, to = { bag, slot }, id = held.id, count = held.count })
      c.CURSOR = nil
    elseif s.id == held.id and s.count + held.count <= (c.ITEMS[s.id].maxStack or 20) then
      c.PENDING_MOVES = c.PENDING_MOVES or {}
      table.insert(c.PENDING_MOVES, { from = { held.bag, held.slot }, to = { bag, slot }, id = held.id, count = held.count, merge = true })
      c.CURSOR = nil
    end
    local _ = src
  end
  -- the "server" carries out queued moves and the game says the bags settled
  function c.Settle()
    for _, m in ipairs(c.PENDING_MOVES or {}) do
      if not m.lost then
        c.BAGS[m.from[1]].slots[m.from[2]] = nil
        if m.guild then
          c.GUILD.tabs[m.to[1]].slots[m.to[2]] = { id = m.id, count = m.count }
        elseif m.merge then
          c.BAGS[m.to[1]].slots[m.to[2]].count = c.BAGS[m.to[1]].slots[m.to[2]].count + m.count
        else
          c.BAGS[m.to[1]].slots[m.to[2]] = { id = m.id, count = m.count, bound = false, locked = false }
        end
        table.insert(c.DEPOSITS, m)
      end
    end
    local had = c.PENDING_MOVES and #c.PENDING_MOVES > 0
    c.PENDING_MOVES = {}
    if had and c.GUILD.open then c.FireEvent("GUILDBANKBAGSLOTS_CHANGED") end
    c.FireEvent("BAG_UPDATE_DELAYED")
  end
  c.DEPOSITS = {}

  -- mail
  c.MAIL = { open = false, sendShown = true, name = "", subject = "", body = "", money = 0, cod = 0, attach = {} }
  c.SENT = {}
  local function EditBox(field) return { GetText = function() return c.MAIL[field] end, SetText = function(_, t) c.MAIL[field] = t end, IsShown = function() return true end } end
  c.SendMailNameEditBox = EditBox("name")
  c.SendMailSubjectEditBox = EditBox("subject")
  c.SendMailBodyEditBox = EditBox("body")
  c.SendMailFrame = { IsVisible = function() return c.MAIL.open and c.MAIL.sendShown end, IsShown = function() return c.MAIL.open and c.MAIL.sendShown end, previousItem = "" }
  c.MailFrame = { IsShown = function() return c.MAIL.open end, IsVisible = function() return c.MAIL.open end }
  c.SendMailMoney = {}
  c.MoneyInputFrame_GetCopper = function() return c.MAIL.money end
  c.HasSendMailItem = function(i) return c.MAIL.attach[i] ~= nil end
  c.GetSendMailItem = function(i)
    local a = c.MAIL.attach[i]
    if not a then return nil end
    return c.ITEMS[a.id].name, a.id, 1, a.count, c.ITEMS[a.id].quality or 1
  end
  c.GetSendMailPrice = function()
    local n = 0
    for _ in pairs(c.MAIL.attach) do n = n + 1 end
    return 30 * math.max(1, n)
  end
  c.GetSendMailCOD = function() return c.MAIL.cod end
  c.GetSendMailMoney = function() return c.MAIL.money end
  c.ClickSendMailItemButton = function(i)
    if not c.CURSOR or c.CURSOR.other then return end
    if c.MAIL_REFUSES_ATTACH then return end
    local i2 = i
    if not i2 then for k = 1, 12 do if not c.MAIL.attach[k] then i2 = k break end end end
    c.MAIL.attach[i2] = { id = c.CURSOR.id, count = c.CURSOR.count, bag = c.CURSOR.bag, slot = c.CURSOR.slot }
    c.CURSOR = nil
    c.MAIL.subject = c.MAIL.subject ~= "" and c.MAIL.subject or c.ITEMS[c.MAIL.attach[i2].id].name
    c.SendMailFrame.previousItem = c.MAIL.subject
    c.ATTACH_EVENTS = (c.ATTACH_EVENTS or 0) + 1
  end
  c.SENDMAIL_CALLS = 0
  c.SendMail = function(to, subject, body)
    c.SENDMAIL_CALLS = c.SENDMAIL_CALLS + 1
    c.LAST_SEND = { to = to, subject = subject, body = body }
  end
  -- the "server" answers a send: "success", "failed", "secure", or nothing (an ambiguous outcome)
  function c.AnswerSend(how)
    if how == "success" then
      local items = {}
      for i = 1, 12 do
        local a = c.MAIL.attach[i]
        if a then
          table.insert(items, { id = a.id, count = a.count })
          c.BAGS[a.bag].slots[a.slot] = nil
        end
      end
      table.insert(c.SENT, { to = c.LAST_SEND.to, subject = c.LAST_SEND.subject, items = items })
      c.MAIL.attach = {}
      c.MAIL.name, c.MAIL.subject, c.MAIL.body = "", "", ""
      c.FireEvent("MAIL_SEND_SUCCESS")
      c.FireEvent("BAG_UPDATE_DELAYED")
    elseif how == "failed" then
      c.FireEvent("MAIL_FAILED")
    elseif how == "secure" then
      c.FireEvent("SECURE_TRANSFER_CONFIRM_SEND_MAIL")
    elseif how == "cancel" then
      c.FireEvent("SECURE_TRANSFER_CANCEL")
    end
  end
  function c.OpenMail() c.MAIL.open = true; c.FireEvent("MAIL_SHOW") end
  function c.CloseMail()
    c.MAIL.open = false
    -- the game hands attachments back when the mailbox closes
    c.MAIL.attach = {}
    c.FireEvent("MAIL_CLOSED")
  end

  -- bank: tabs are bag IDs 6.. (Enum.BagIndex.CharacterBankTab_1 = 6 on Forever)
  c.Enum.BankType = { Character = 0, Account = 2 }
  c.BANK = { open = false, tabs = { 6 } }
  c.C_Bank = {
    FetchPurchasedBankTabIDs = function(t) if t == 0 then return c.BANK.tabs end return {} end,
    CanUseBank = function() return c.BANK.open end,
  }
  c.BankFrame = { IsShown = function() return c.BANK.open end, IsVisible = function() return c.BANK.open end }
  function c.OpenBank() c.BANK.open = true; c.FireEvent("BANKFRAME_OPENED") end
  function c.CloseBank() c.BANK.open = false; c.FireEvent("BANKFRAME_CLOSED") end

  -- guild bank
  c.GUILD = { name = nil, open = false, current = 1, tabs = {} }
  c.IsInGuild = function() return c.GUILD.name ~= nil end
  c.GetGuildInfo = function() return c.GUILD.name, "Member", 3 end
  c.GetCurrentGuildBankTab = function() return c.GUILD.current end
  c.GetNumGuildBankTabs = function() local n = 0 for _ in pairs(c.GUILD.tabs) do n = n + 1 end return n end
  c.GetGuildBankTabInfo = function(tab)
    local t = c.GUILD.tabs[tab]
    if not t then return nil end
    return t.name, 1, true, t.canDeposit ~= false, 0, 0
  end
  c.GetGuildBankItemInfo = function(tab, slot)
    local s = c.GUILD.tabs[tab] and c.GUILD.tabs[tab].slots[slot]
    if not s then return nil, 0, false end
    return 1, s.count, false
  end
  c.GetGuildBankItemLink = function(tab, slot)
    local s = c.GUILD.tabs[tab] and c.GUILD.tabs[tab].slots[slot]
    return s and ("|Hitem:" .. s.id .. "|h") or nil
  end
  c.PickupGuildBankItem = function(tab, slot)
    if not c.CURSOR or c.CURSOR.other then return end
    if c.GUILD_REFUSES then return end
    local t = c.GUILD.tabs[tab]
    if not t or t.slots[slot] then return end
    c.PENDING_MOVES = c.PENDING_MOVES or {}
    table.insert(c.PENDING_MOVES, { from = { c.CURSOR.bag, c.CURSOR.slot }, to = { tab, slot }, id = c.CURSOR.id, count = c.CURSOR.count, guild = true })
    c.CURSOR = nil
  end
  c.GuildBankFrame = { IsShown = function() return c.GUILD.open end, IsVisible = function() return c.GUILD.open end }
  function c.OpenGuildBank() c.GUILD.open = true; c.FireEvent("GUILDBANKFRAME_OPENED") end
  function c.CloseGuildBank() c.GUILD.open = false; c.FireEvent("GUILDBANKFRAME_CLOSED") end

  c.UIErrorsFrame = { AddMessage = function() end }
  c.StaticPopupDialogs = {}
  c.StaticPopup_Show = function() return {} end
  c.StaticPopup_Hide = function() end
  c.UISpecialFrames = {}
  c.GameTooltip = setmetatable({}, { __index = function() return function() end end })

  if opts.beforeFiles then opts.beforeFiles(c) end
  local files = opts.files or { "inventory/Rules.lua", "inventory/Items.lua", "inventory/Plan.lua", "inventory/Run.lua" }
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(ROOT .. f))
    setfenv(chunk, c)
    chunk("!!!TwichUI", {})
  end
  -- the saved variables arrive
  c.TwichUIDB = opts.db or { modules = {} }
  c.LOADED["!!!TwichUI"] = true
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  return c
end
MI_FILES = INVENTORY

-- Stand-in frames for the windows (the same kind tests/test_restock_prompt.lua uses): they keep their scripts, text,
-- colors and shown state.
MI_MADE = 0
function MIFake(kind, parent)
  MI_MADE = MI_MADE + 1
  local f = { kind = kind, parent = parent, scripts = {}, hooks = {}, points = {}, shown = true, w = 0, h = 0,
    text = "", enabled = true, focus = false, scroll = 0, events = {}, children = {} }
  if parent and parent.children then table.insert(parent.children, f) end
  local function Fire(self, name, ...)
    if self.scripts[name] then self.scripts[name](self, ...) end
    for _, h in ipairs(self.hooks[name] or {}) do h(self, ...) end
  end
  f.Fire = Fire
  local methods = {
    SetScript = function(s, n, fn) s.scripts[n] = fn; s.hooks[n] = nil end,
    GetScript = function(s, n) return s.scripts[n] end,
    HookScript = function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end,
    SetSize = function(s, w, h) s.w, s.h = w, h end,
    SetWidth = function(s, w) s.w = w end, SetHeight = function(s, h) s.h = h end,
    GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
    SetPoint = function(s, ...) table.insert(s.points, { ... }) end,
    ClearAllPoints = function(s) s.points = {} end,
    Show = function(s) if not s.shown then s.shown = true; Fire(s, "OnShow") end end,
    Hide = function(s) if s.shown then s.shown = false; Fire(s, "OnHide") end end,
    SetShown = function(s, v) if v then s:Show() else s:Hide() end end,
    IsShown = function(s) return s.shown end,
    IsVisible = function(s) local p = s while p do if not p.shown then return false end p = p.parent end return true end,
    SetText = function(s, t) s.text = t == nil and "" or tostring(t) end,
    GetText = function(s) return s.text end,
    GetStringHeight = function() return 12 end, GetStringWidth = function(s) return #s.text * 6 end,
    IsTruncated = function() return false end,
    SetEnabled = function(s, v) s.enabled = v and true or false; Fire(s, v and "OnEnable" or "OnDisable") end,
    IsEnabled = function(s) return s.enabled end,
    SetFocus = function(s) s.focus = true; Fire(s, "OnEditFocusGained") end,
    ClearFocus = function(s) if s.focus then s.focus = false; Fire(s, "OnEditFocusLost") end end,
    HasFocus = function(s) return s.focus end,
    SetScrollChild = function(s, child) s.child = child end,
    SetVerticalScroll = function(s, v) s.scroll = v end,
    GetVerticalScroll = function(s) return s.scroll end,
    GetVerticalScrollRange = function(s) return math.max(0, (s.child and s.child.h or 0) - s.h) end,
    IsMouseOver = function() return false end,
    GetEffectiveScale = function() return 1 end, GetScale = function() return 1 end,
    GetOwner = function(s) return s.owner end, SetOwner = function(s, o) s.owner = o end,
    GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end, SetFont = function() return true end,
    SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha or 1 end,
    SetTexture = function(s, t) s.texture = t end,
    SetTextColor = function(s, r, g, b) s.color = { r, g, b } end,
    RegisterEvent = function(s, e) s.events[e] = true end, UnregisterEvent = function(s, e) s.events[e] = nil end,
    CreateTexture = function(s) return MIFake("Texture", s) end,
    CreateFontString = function(s) return MIFake("FontString", s) end,
  }
  if kind == "ScrollFrame" then f.ScrollBar = MIFake("Slider", f); f.ScrollBar.ThumbTexture = MIFake("Texture", f.ScrollBar) end
  return setmetatable(f, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end


