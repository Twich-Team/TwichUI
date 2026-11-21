-- A deterministic stand-in for the parts of the Forever client TwichUI Fishing uses: spells and channels, bags, worn items,
-- weapon enchants, loot windows, key bindings and override bindings, equipment sets, interaction-targeting settings,
-- combat lockdown and timers. Secure buttons are simulated the way Blizzard_FrameXML/SecureTemplates.lua acts on their
-- attributes (spell, item with "bag slot" and target-slot, macro /equipslot, equipmentset), and attributes cannot be changed
-- in combat. This proves decisions and bookkeeping only: it does not prove the real client's secure behaviour, taint,
-- event order or timing.
dofile(TESTS .. "harness.lua")

local function Link(id) return ("|cffffffff|Hitem:%d::::::::60:::::|h[Item %d]|h|r"):format(id, id) end
FISH_LINK = Link

POLE, POLE2, SWORD, SHIELD, BOW, HAT = 6256, 6365, 2000, 2001, 2002, 2003
FISH1, FISH2, JUNK = 6291, 6303, 6299
LURE25, LURE50, LURE75 = 6529, 6530, 6532
CLAM, BIGCLAM, CRATE, BLOATED = 5523, 7973, 9001, 9002
PEARL, CLAMMEAT = 5498, 5503

function FishingClient(opts)
  opts = opts or {}
  local c = MakeClient(opts.name or "Rich", { "!!!TwichUI", "TwichUI_Fishing" })
  local W = {
    clock = 1000, epoch = opts.epoch or 1800000000, combat = false,
    known = { [7620] = true }, channel = nil, guid = 0,
    items = {
      [POLE] = { class = 2, sub = 20, loc = "INVTYPE_2HWEAPON" }, [POLE2] = { class = 2, sub = 20, loc = "INVTYPE_2HWEAPON" },
      [SWORD] = { class = 2, sub = 7, loc = "INVTYPE_WEAPONMAINHAND" }, [SHIELD] = { class = 4, sub = 6, loc = "INVTYPE_SHIELD" },
      [BOW] = { class = 2, sub = 2, loc = "INVTYPE_RANGED" }, [HAT] = { class = 4, sub = 1, loc = "INVTYPE_HEAD" },
    },
    equipped = {}, bags = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} }, bagSize = opts.bagSize or 16,
    enchant = nil, lureEnchant = { [LURE25] = 263, [LURE50] = 264, [LURE75] = 265 },
    contents = { [CLAM] = { { PEARL, 1 }, { CLAMMEAT, 1 } }, [BIGCLAM] = { { PEARL, 2 } }, [CRATE] = { { JUNK, 1 } } },
    lootable = { [CLAM] = true, [BIGCLAM] = true, [CRATE] = true, [BLOATED] = true },
    locked = {}, bound = {}, overrides = {}, cvars = { SoftTargetInteract = "1", SoftTargetInteractArc = "0", SoftTargetInteractRange = "10" },
    sets = {}, softUnit = false, softObject = false, errors = {}, timers = {}, blocked = {}, calls = { equip = 0, use = 0, setOverride = 0, casts = 0 },
    loot = nil, map = 1429, zone = "Elwynn Forest", blockInsecure = {},
  }
  c.W = W
  c.UIParent = {}
  c.Enum = { LootSlotType = { Item = 1, Money = 2 }, WeaponSlot = { MainHand = 0, OffHand = 1 }, ItemClass = { Weapon = 2 },
    ItemWeaponSubclass = { Fishingpole = 20 } }
  c.ERR_ITEM_LOCKED, c.ERR_INV_FULL = "Item is locked.", "Inventory is full."
  c.LOOT_ITEM_SELF, c.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %s.", "You receive loot: %sx%d."
  c.LOOT_ITEM_PUSHED_SELF, c.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %s.", "You receive item: %sx%d."
  c.GetTime = function() return W.clock end
  c.time = function(t) if type(t) == "table" then return os.time(t) end return W.epoch end
  c.InCombatLockdown = function() return W.combat end
  c.issecretvalue = function() return false end
  c.UIErrorsFrame = { AddMessage = function(_, text) W.errors[#W.errors + 1] = text end }

  -- timers on the simulated clock
  local function Schedule(d, fn, every)
    local t = { at = W.clock + d, fn = fn, every = every }
    function t:Cancel() self.cancelled = true end
    W.timers[#W.timers + 1] = t
    return t
  end
  c.C_Timer = { After = function(d, fn) Schedule(d, fn) end, NewTicker = function(d, fn) return Schedule(d, fn, d) end,
    NewTimer = function(d, fn) return Schedule(d, fn) end }
  function W.Advance(sec, epochToo)
    local target = W.clock + sec
    while true do
      local best
      for _, t in ipairs(W.timers) do
        if not t.cancelled and t.at <= target and (not best or t.at < best.at) then best = t end
      end
      if not best then break end
      W.epoch = W.epoch + (best.at - W.clock)
      W.clock = best.at
      if best.every then best.at = best.at + best.every else best.cancelled = true end
      best.fn()
    end
    W.epoch = W.epoch + (target - W.clock)
    W.clock = target
    local live = {}
    for _, t in ipairs(W.timers) do if not t.cancelled then live[#live + 1] = t end end
    W.timers = live
  end

  -- frames: secure buttons keep attributes (refused in combat) and scripts
  local baseCreate = c.CreateFrame
  W.frames = {}
  c.CreateFrame = function(kind, name, parent, template)
    if kind ~= "Button" then return baseCreate(kind, name, parent, template) end
    local fr = { name = name, template = template, attrs = {}, scripts = {} }
    function fr:SetAttribute(k, v) assert(not W.combat, "a secure attribute is never set in combat (" .. tostring(k) .. ")"); self.attrs[k] = v end
    function fr:GetAttribute(k) return self.attrs[k] end
    function fr:RegisterForClicks(...) self.clicks = { ... } end
    function fr:SetScript(n, fn) self.scripts[n] = fn end
    function fr:HookScript() end
    if name then W.frames[name] = fr; c[name] = fr end
    return fr
  end

  -- spells
  c.C_SpellBook = { IsSpellKnown = function(id) return W.known[id] == true end }
  c.C_Spell = { GetSpellName = function(id) if id == 7620 or id == 7731 then return "Fishing" end end }
  c.UnitChannelInfo = function(unit)
    if unit ~= "player" or not W.channel then return nil end
    return W.channel[1], W.channel[1], 1, 0, 0, false, false, W.channel[2]
  end

  -- items
  local function Info(id) return W.items[id] end
  c.C_Item = {
    GetItemInfoInstant = function(id)
      local i = Info(id); if not i then return id, "Misc", "Misc", "", 0, 15, 0 end
      return id, "Weapon", "Pole", i.loc, 0, i.class, i.sub
    end,
    GetWeaponEnchantInfo = function(which)
      if which ~= 0 then return {} end
      local e = W.enchant
      if not e then return { { hasEnchant = false, timeLeft = 0, charges = 0, enchantID = 0 } } end
      return { { hasEnchant = true, timeLeft = e.ms, charges = 0, enchantID = e.id, enchantType = 0 } }
    end,
    GetItemCount = function(id) return W.Count(id) end,
    EquipItemByName = function(item, slot)
      W.calls.equip = W.calls.equip + 1
      if W.combat or W.blockInsecure.equip then c.FireEvent("ADDON_ACTION_BLOCKED", "TwichUI_Fishing", "EquipItemByName()") return end
      local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
      local b, s = W.Find(id)
      if b then W.EquipFromBag(b, s, slot) end
    end,
  }
  c.GetInventoryItemID = function(_, slot) return W.equipped[slot] end
  c.GetInventoryItemLink = function(_, slot) local id = W.equipped[slot]; return id and Link(id) or nil end

  -- bags
  function W.Count(id)
    local n = 0
    for b = 0, 4 do for _, e in pairs(W.bags[b]) do if e.id == id then n = n + e.count end end end
    return n
  end
  function W.Find(id)
    for b = 0, 4 do for s = 1, W.bagSize do local e = W.bags[b][s]; if e and e.id == id then return b, s end end end
  end
  function W.Free()
    for b = 0, 4 do for s = 1, W.bagSize do if not W.bags[b][s] then return b, s end end end
  end
  function W.FreeCount()
    local n = 0
    for b = 0, 4 do for s = 1, W.bagSize do if not W.bags[b][s] then n = n + 1 end end end
    return n
  end
  function W.Put(id, count)
    count = count or 1
    for b = 0, 4 do for s = 1, W.bagSize do local e = W.bags[b][s]; if e and e.id == id and not Info(id) and not W.lootable[id] then e.count = e.count + count return b, s end end end
    local b, s = W.Free()
    if not b then return nil end
    W.bags[b][s] = { id = id, count = count }
    return b, s
  end
  function W.Take(b, s, n)
    local e = W.bags[b][s]
    e.count = e.count - (n or 1)
    if e.count <= 0 then W.bags[b][s] = nil end
  end
  c.C_Container = {
    GetContainerNumSlots = function(b) return W.bags[b] and W.bagSize or 0 end,
    GetContainerItemInfo = function(b, s)
      local e = W.bags[b] and W.bags[b][s]
      if not e then return nil end
      return { itemID = e.id, stackCount = e.count, hyperlink = Link(e.id), hasLoot = W.lootable[e.id] == true, isLocked = false, quality = e.quality or 1 }
    end,
    GetContainerNumFreeSlots = function(b) local n = 0; for s = 1, W.bagSize do if not W.bags[b][s] then n = n + 1 end end; return n, 0 end,
    UseContainerItem = function(b, s)
      W.calls.use = W.calls.use + 1
      if W.combat or W.blockInsecure.use then c.FireEvent("ADDON_ACTION_BLOCKED", "TwichUI_Fishing", "UseContainerItem()") return end
      W.UseBagItem(b, s)
    end,
  }
  function W.Settle() c.FireEvent("BAG_UPDATE_DELAYED") end

  -- equipping
  local function Changed(slot) c.FireEvent("PLAYER_EQUIPMENT_CHANGED", slot, true) end
  function W.EquipFromBag(b, s, slot)
    local e = W.bags[b][s]
    if not e then return false end
    local i = Info(e.id) or {}
    slot = slot or (i.loc == "INVTYPE_RANGED" and 18) or (i.loc == "INVTYPE_HEAD" and 1) or (i.loc == "INVTYPE_SHIELD" and 17) or 16
    local old = W.equipped[slot]
    if i.loc == "INVTYPE_2HWEAPON" and W.equipped[17] then
      local fb, fs = W.Free()
      if not fb then c.FireEvent("UI_ERROR_MESSAGE", 0, c.ERR_INV_FULL) return false end
      W.bags[fb][fs] = { id = W.equipped[17], count = 1 }
      W.equipped[17] = nil
      Changed(17)
    end
    if slot == 17 and W.equipped[16] and (Info(W.equipped[16]) or {}).loc == "INVTYPE_2HWEAPON" then
      local fb, fs = W.Free()
      if not fb then return false end
      W.bags[fb][fs] = { id = W.equipped[16], count = 1 }
      W.equipped[16] = nil
      Changed(16)
    end
    W.equipped[slot] = e.id
    W.bags[b][s] = old and { id = old, count = 1 } or nil
    Changed(slot)
    W.Settle()
    return true
  end
  function W.Wear(slot, id) W.equipped[slot] = id end
  function W.Give(id, count, quality)
    local b, s = W.Put(id, count)
    if quality then W.bags[b][s].quality = quality end
    return b, s
  end

  c.C_EquipmentSet = {
    CanUseEquipmentSets = function() return true end,
    GetEquipmentSetID = function(name) return W.sets[name] and W.sets[name].id or nil end,
    GetEquipmentSetInfo = function(id)
      for name, set in pairs(W.sets) do
        if set.id == id then
          local worn = true
          for slot, item in pairs(set.items) do if W.equipped[slot] ~= item then worn = false end end
          return name, 0, id, worn
        end
      end
    end,
  }
  function W.UseSet(name)
    local set = W.sets[name]
    for _, slot in ipairs({ 16, 17, 18, 1 }) do
      local item = set.items[slot]
      if item and W.equipped[slot] ~= item then local b, s = W.Find(item); if b then W.EquipFromBag(b, s, slot) end end
    end
  end

  -- the map
  c.C_Map = { GetBestMapForUnit = function() return W.map end, GetMapInfo = function(id) return { name = W.zone, mapID = id } end }
  c.GetRealZoneText = function() return W.zone end

  -- loot windows
  c.IsFishingLoot = function() return W.loot ~= nil and W.loot.fishing == true end
  c.GetNumLootItems = function() return W.loot and #W.loot.slots or 0 end
  c.GetLootSlotType = function(i) local e = W.loot and W.loot.slots[i]; return e and (e.money and 2 or 1) or 0 end
  c.GetLootSlotLink = function(i) local e = W.loot and W.loot.slots[i]; return e and not e.money and not e.gone and Link(e.id) or nil end
  c.GetLootSlotInfo = function(i) local e = W.loot and W.loot.slots[i]; if not e then return nil end; return 0, "Item", e.q, nil, 1 end

  -- One loot window, as the client delivers it (o: { fishing, fromItem, auto (default true), take = function(i) -> bool,
  -- noClearEvents, chat, ready = false to skip LOOT_READY, twice = duplicate every event }).
  function W.Loot(slots, o)
    o = o or {}
    local list = {}
    for _, s in ipairs(slots) do list[#list + 1] = { id = s[1], q = s[2] or 1, money = s.money } end
    W.loot = { fishing = o.fishing, slots = list }
    local function Fire(...) c.FireEvent(...); if o.twice then c.FireEvent(...) end end
    if o.ready ~= false then Fire("LOOT_READY", o.auto ~= false) end
    Fire("LOOT_OPENED", o.auto ~= false, o.fromItem == true)
    for i, e in ipairs(list) do
      local take = not e.money and (not o.take or o.take(i))
      if take and W.Put(e.id, e.q) then
        e.taken = true
        if not o.noClearEvents then Fire("LOOT_SLOT_CLEARED", i) end
      end
    end
    Fire("LOOT_CLOSED")
    if o.chat then
      for _, e in ipairs(list) do
        if e.taken then c.FireEvent("CHAT_MSG_LOOT", e.q > 1 and c.LOOT_ITEM_SELF_MULTIPLE:format(Link(e.id), e.q) or c.LOOT_ITEM_SELF:format(Link(e.id)), "") end
      end
    end
    W.loot = nil
    W.Settle()
  end

  -- using an item from a bag slot, as SECURE_ACTIONS.item and UseContainerItem do it
  function W.UseBagItem(b, s, targetSlot)
    local e = W.bags[b][s]
    if not e then return end
    if Info(e.id) and W.equipped[16] ~= e.id then W.EquipFromBag(b, s) return end
    if targetSlot and W.lureEnchant[e.id] then
      if W.equipped[16] ~= nil then
        W.Take(b, s, 1)
        W.enchant = { ms = 600000, id = W.lureEnchant[e.id] }
        c.FireEvent("WEAPON_ENCHANT_CHANGED")
        c.FireEvent("UNIT_INVENTORY_CHANGED", "player")
        W.Settle()
      end
      return
    end
    if W.lootable[e.id] then
      if W.locked[e.id] then c.FireEvent("UI_ERROR_MESSAGE", 0, c.ERR_ITEM_LOCKED) return end
      if W.holdContainers then W.held = { b = b, s = s, id = e.id } return end
      W.OpenContainer(b, s)
    end
  end
  function W.OpenContainer(b, s, o)
    local e = W.bags[b][s]
    local id = e.id
    local slots = W.contents[id] or {}
    o = o or {}
    -- the container goes as its last item is taken (after the window closes, as the bags settle)
    W.Take(b, s, 1)
    W.Loot(slots, { fromItem = true, take = o.take })
    if o.keep then W.Put(id, 1) end
  end

  -- casting, the line, and reeling in
  function W.StartLine(id)
    W.guid = W.guid + 1
    W.channel = { "Fishing", id or 7620, "Cast-" .. W.guid }
    W.calls.casts = W.calls.casts + 1
    c.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player", W.channel[3], W.channel[2])
  end
  function W.StopLine()
    local ch = W.channel
    W.channel = nil
    if ch then c.FireEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player", ch[3], ch[2]) end
  end
  W.catch = { { FISH1, 1 } }
  W.bite = true
  -- INTERACTTARGET with the line out: the bobber's loot (or nothing, before a bite)
  function W.Interact()
    if not W.channel then return end
    if W.bite then
      local catch = W.catch
      W.Loot(catch, { fishing = true })
      W.StopLine()
    else
      W.StopLine()
    end
  end

  local function Macro(text)
    for line in text:gmatch("[^\n]+") do
      local slot, id = line:match("^/equipslot (%d+) item:(%d+)$")
      assert(slot, "only /equipslot lines are expected: " .. line)
      local b, s = W.Find(tonumber(id))
      if b then W.EquipFromBag(b, s, tonumber(slot)) end
    end
  end

  -- A click on a secure button: PreClick, the secure action its attributes name, PostClick.
  function W.Click(name)
    local b = W.frames[name]
    assert(b, "no button " .. name)
    if b.scripts.PreClick then b.scripts.PreClick(b, "LeftButton", false) end
    local t = b.attrs.type
    if t == "spell" then
      if W.failCast then
        W.guid = W.guid + 1
        c.FireEvent("UNIT_SPELLCAST_FAILED", "player", "Cast-" .. W.guid, b.attrs.spell)
      else
        W.StartLine(b.attrs.spell)
      end
    elseif t == "item" then
      local bag, slot = tostring(b.attrs.item):match("^(%d+) (%d+)$")
      W.UseBagItem(tonumber(bag), tonumber(slot), b.attrs["target-slot"])
    elseif t == "macro" then
      Macro(b.attrs.macrotext)
    elseif t == "equipmentset" then
      W.UseSet(b.attrs.equipmentset)
    end
    if b.scripts.PostClick then b.scripts.PostClick(b, "LeftButton", false) end
    return t
  end

  -- bindings
  c.GetBindingKey = function(action)
    local keys = {}
    for key, a in pairs(W.bound) do if a == action then keys[#keys + 1] = key end end
    table.sort(keys)
    return keys[1], keys[2]
  end
  c.SetOverrideBinding = function(_, _, key, command)
    assert(not W.combat, "an override is never set in combat")
    W.calls.setOverride = W.calls.setOverride + 1
    W.overrides[key] = command
  end
  c.SetOverrideBindingClick = function(_, _, key, button)
    assert(not W.combat, "an override is never set in combat")
    W.overrides[key] = "CLICK " .. button
  end
  c.ClearOverrideBindings = function()
    assert(not W.combat, "overrides are never cleared in combat")
    W.overrides = {}
  end
  -- A key press as the game dispatches it: an override wins, otherwise the key's binding.
  function W.Key(key)
    local o = W.overrides[key]
    if o == "INTERACTTARGET" or o == "INTERACTMOUSEOVER" then W.Interact() return "reel" end
    if o and o:match("^CLICK ") then return W.Click(o:match("^CLICK (%S+)")) end
    local a = W.bound[key]
    if a and a:match("^CLICK ") then return W.Click(a:match("^CLICK ([^:]+)")) end
  end
  c.UnitExists = function(u) return u == "softinteract" and W.softUnit end
  c.UnitIsGameObject = function(u) return u == "softinteract" and W.softObject end
  c.C_CVar = { GetCVar = function(n) return W.cvars[n] end, SetCVar = function(n, v) W.cvars[n] = v; return true end }

  -- combat begins and ends as the game reports it: REGEN_DISABLED arrives just before the lockdown is on
  function W.Fight() c.FireEvent("PLAYER_REGEN_DISABLED"); W.combat = true end
  function W.Peace() W.combat = false; c.FireEvent("PLAYER_REGEN_ENABLED") end

  -- the addon itself
  c.TwichUIFishingDB = opts.db
  local function LoadToc()
    for line in io.lines(ROOT .. "../TwichUI_Fishing/TwichUI_Fishing.toc") do
      line = line:gsub("\r", ""):gsub("%s+$", "")
      if line ~= "" and not line:find("^#") then
        local chunk = assert(loadfile(ROOT .. "../TwichUI_Fishing/" .. line:gsub("\\", "/")))
        setfenv(chunk, c)
        chunk("TwichUI_Fishing", {})
      end
    end
  end
  W.loads = 0
  c.C_AddOns.LoadAddOn = function(name)
    assert(name == "TwichUI_Fishing", "only the fishing addon is loaded here")
    assert(not W.combat, "never loaded in combat")
    if opts.missing then return false, "MISSING" end
    W.loads = W.loads + 1
    LoadToc()
    c.LOADED.TwichUI_Fishing = true
    c.FireEvent("ADDON_LOADED", "TwichUI_Fishing")
    return true
  end
  local chunk = assert(loadfile(ROOT .. "FishingLauncher.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
  c.LOADED["!!!TwichUI"] = true
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  W.Advance(1)
  return c, W
end

-- What the game would write to SavedVariables and read back: plain values only (a function, frame or userdata fails).
function FishRoundTrip(v, path)
  path = path or "TwichUIFishingDB"
  local t = type(v)
  if t == "table" then
    local out = {}
    for k, x in pairs(v) do
      assert(type(k) == "string" or type(k) == "number", path .. ": a key that can't be saved")
      out[k] = FishRoundTrip(x, path .. "." .. tostring(k))
    end
    return out
  end
  assert(t == "string" or t == "number" or t == "boolean" or t == "nil", path .. " holds a " .. t)
  return v
end
