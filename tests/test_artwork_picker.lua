dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Reminders in the settings window (TwichUI_Settings/pages/Reminders.lua and RemindersEditor.lua):
--   * the page: where it sits, its switch, its hosted frame;
--   * the list and the templates: a new reminder is a draft, opened in the editor;
--   * the editor: rules read as a sentence, field-specific choices, an item by link, names, duplicate, delete (asks);
--   * Test: what it sees right now (also for a draft), and simulations that never touch the live state;
--   * Preview and moving through the buttons; progressive disclosure; nothing made again on a redraw; events only
--     while shown.
-- Stand-in frames keep their scripts, text, focus and shown state; nothing here is the game.

local made = 0
local created = {}
local function Fake(kind, parent)
  made = made + 1
  local f = { kind = kind, parent = parent, scripts = {}, hooks = {}, points = {}, shown = true, w = 0, h = 0,
    text = "", enabled = true, focus = false, events = {}, children = {} }
  if parent and parent.children then table.insert(parent.children, f) end
  local function Fire(self, name, ...)
    if self.scripts[name] then self.scripts[name](self, ...) end
    for _, h in ipairs(self.hooks[name] or {}) do h(self, ...) end
  end
  created[#created + 1] = f
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
    SetEnabled = function(s, v) s.enabled = v and true or false end,
    IsEnabled = function(s) return s.enabled end,
    SetFocus = function(s) s.focus = true; Fire(s, "OnEditFocusGained") end,
    ClearFocus = function(s) if s.focus then s.focus = false; Fire(s, "OnEditFocusLost") end end,
    HasFocus = function(s) return s.focus end,
    IsMouseOver = function() return false end,
    GetEffectiveScale = function() return 1 end, GetScale = function() return 1 end,
    GetOwner = function(s) return s.owner end, SetOwner = function(s, o) s.owner = o end,
    GetFont = function(s) return unpack(s.font or { "Fonts\\FRIZQT__.TTF", 12, "" }) end,
    SetFont = function(s, file, size, flags) s.font = { file, size, flags }; return true end,
    SetScrollChild = function(s, child) s.child = child end,
    GetScrollChild = function(s) return s.child end,
    SetVerticalScroll = function(s, value) s.scroll = value end,
    GetVerticalScroll = function(s) return s.scroll or 0 end,
    SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha or 1 end,
    SetScale = function(s, v) s.scale = v end,
    SetTexture = function(s, t) s.texture = t; return true end,
    RegisterEvent = function(s, e) s.events[e] = true end, UnregisterEvent = function(s, e) s.events[e] = nil end,
    CreateTexture = function(s) return Fake("Texture", s) end,
    CreateFontString = function(s) return Fake("FontString", s) end,
    GetThumbTexture = function(s) s.thumbTex = s.thumbTex or Fake("Texture", s) return s.thumbTex end,
    CreateAnimationGroup = function(s)
      local g = Fake("AnimationGroup", s)
      g.Play = function(self) self.playing = true end
      g.Stop = function(self) self.playing = false end
      g.CreateAnimation = function() return Fake("Animation", g) end
      return g
    end,
  }
  return setmetatable(f, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end

local EQUIP = {}
local ITEMS = { [1201] = { "Dull Heater Shield", 4, 6, "INVTYPE_SHIELD" }, [6948] = { "Hearthstone", 15, 0, "" }, [2139] = { "Dirk", 2, 7, "INVTYPE_WEAPONOFFHAND" } }
local function World(c)
  c.CreateFrame = function(kind, name, parent) local f = Fake(kind, parent); if name then c[name] = f end return f end
  c.UIParent = Fake("Frame")
  c.UIParent.w, c.UIParent.h = 1024, 768
  c.GameTooltip = Fake("GameTooltip")
  c.Enum = { ItemClass = { Weapon = 2, Armor = 4 }, ItemArmorSubclass = { Shield = 6 }, ItemWeaponSubclass = { Fishingpole = 20 } }
  c.C_Item = {
    GetItemInfoInstant = function(id) local it = ITEMS[id] if it then return id, "", "", it[4], 1000 + id, it[2], it[3] end end,
    GetItemIconByID = function(id) if ITEMS[id] then return 1000 + id end end,
    GetItemNameByID = function(id) if ITEMS[id] then return ITEMS[id][1] end end,
    GetItemInfo = function(id) if ITEMS[id] then return ITEMS[id][1] end end,
    RequestLoadItemDataByID = function() end,
    GetItemSpell = function() return nil end, GetItemCount = function() return 0 end,
  }
  c.GetInventoryItemID = function(_, slot) return EQUIP[slot] end
  c.UnitClassBase = function() return "WARRIOR" end
  c.UnitIsGhost = function() return false end
  c.GetCursorInfo = function() return nil end
  c.ClearCursor = function() end
end


local c = SettingsClient({ name = "Rich", beforeInit = World })
local R = c.TwichUI
-- Exercise the thin Reminder adapter against the real catalog before isolated
-- caller lifecycle checks. All edits still go through Reminder setters.
do
  local page, rm, ip = R.RemindersPage, R.Reminders, R.RemindersImagePicker
  R.SettingsUI.IsPageActive = function(key) return key == "reminders" end
  local owner = page.Frame(); owner:Show()
  assert(page.Create("shield")); page.Refresh()
  local id = page.Selected()
  assert(rm.SetDisplayMany(id,{art="ammo",mode="artworkText",text="Keep words"}))
  local function tile(key)
    ip.SetQuery(""); ip.SetCategory("All")
    for _, t in ipairs(ip.Frame().tiles) do if t:IsShown() and t.entry.key == key then return t end end
    error("missing actual artwork tile: "..key)
  end
  local function choose(key) local t=tile(key); t:GetScript("OnClick")(t) end
  assert(ip.Open(id)); assert(ip.Candidate().id=="ammo")
  assert(ip.Frame()==R.SettingsArtworkPicker.Frame(),"Reminder uses the one shared frame")
  assert(ip.Frame().sub:GetText()=="Select an illustration for your reminder.")
  assert(not ip.Frame().automatic:IsShown(),"Reminder footer keeps existing controls")
  choose("reminder-low-mana"); assert(rm.Get(id).display.art=="ammo","selection is only staged")
  ip.Cancel(); assert(rm.Get(id).display.art=="ammo")
  assert(ip.Open(id)); choose("art-herbs"); assert(ip.Apply())
  assert(rm.Get(id).display.art=="art-herbs","approved standalone art saves through Reminder adapter")
  assert(ip.Open(id)); choose("icon-auctionHouse"); assert(ip.Apply())
  assert(rm.Get(id).display.icon=="auctionHouse" and rm.Get(id).display.iconSource=="bundled","approved registry choice saves with its original key")
  assert(ip.Open(id)); choose("reminder-low-mana")
  local changes=0; rm.Subscribe(function() changes=changes+1 end)
  assert(ip.Apply()); assert(changes==1,"Apply is one atomic Reminder notification")
  assert(rm.Get(id).display.art=="reminder-low-mana" and rm.Get(id).display.text=="Keep words")
  assert(rm.SetDisplay(id,"mode","text")); assert(ip.Open(id));choose("shield");assert(ip.Apply())
  assert(rm.Get(id).display.mode=="artworkText","existing text-only promotion is retained")
  assert(ip.Open(id)); ip.SetSource("game"); ip.TakeItem("|Hitem:6948:0|h[Hearthstone]|h")
  assert(ip.Candidate().kind=="item" and ip.Candidate().item==6948)
  assert(ip.Apply() and rm.Get(id).display.iconSource=="item" and rm.Get(id).display.item==6948)
  assert(ip.Open(id)); assert(ip.Source()=="game"); ip.Cancel()
  assert(rm.SetDisplayMany(id,{mode="iconText",iconSource="bundled",icon="mage"}))
  assert(ip.Open(id));assert(ip.Candidate().id=="icon-mage" and ip.Candidate().target=="mage");ip.Cancel()
  assert(rm.SetDisplayMany(id,{mode="artworkText",art="future-art"}))
  assert(ip.Open(id)); assert(ip.Candidate().target=="future-art")
  assert(ip.Frame().details.name:GetText():find("Artwork unavailable",1,true))
  assert(not ip.Frame().apply:IsEnabled() and not ip.Apply())
  ip.Cancel(); assert(rm.Get(id).display.art=="future-art","unknown valid art is never rewritten")
  assert(rm.SetDisplayMany(id,{mode="iconText",iconSource="bundled",icon="futureIcon"}))
  assert(ip.Open(id));assert(ip.Candidate().target=="futureIcon" and not ip.Frame().apply:IsEnabled());ip.Cancel()
  assert(rm.Get(id).display.icon=="futureIcon","unknown valid registered ref is not rewritten")
  assert(rm.SetDisplayMany(id,{art="shield",mode="artworkText"}));assert(ip.Open(id));ip.SetQuery("potion");ip.SetCategory("Supplies");ip.Cancel()
  assert(ip.Open(id));assert(ip.Frame().search:GetText()=="");assert(R.SettingsArtworkPicker.State(owner).category=="All")
  owner:Hide();assert(not ip.Shown());owner:Show();page.Refresh()
  assert(ip.Open(id));assert(R.Profiles.Duplicate("Artwork copy"));assert(not ip.Shown(),"profile duplicate closes old binding")
  page.Refresh();assert(page.Selected()==id);assert(ip.Open(id));assert(R.Profiles.Create("Artwork empty"))
  assert(not ip.Shown() and not R.SettingsArtworkPicker.Shown(),"profile switch discards candidate")
  assert(not ip.Apply(),"late Reminder Apply cannot write a replacement profile")
  assert(page.Create("shield"));page.Refresh();id=page.Selected()
  assert(ip.Open(id));R.SettingsArtworkPicker.Frame():Hide();assert(not ip.Shown())
  assert(ip.Open(id)); assert(page.Create("custom"));page.Refresh();assert(not ip.Shown(),"selection change discards candidate")
  owner:Hide()
end

-- Isolate the picker lifecycle while the core catalog is supplied independently.
local entry = { ref = { kind = "art", id = "shield" }, name = "Shield", category = "Equipment", description = "Shield" }
R.Artwork = {
  Check = function(ref)
    if type(ref) ~= "table" then return nil end
    if ref.kind == "automatic" then return { kind = "automatic" } end
    if ref.kind == "item" and type(ref.id) == "number" and ref.id > 0 and ref.id <= 2147483647 and ref.id % 1 == 0 then return { kind = "item", id = ref.id } end
    if (ref.kind == "art" or ref.kind == "icon") and type(ref.id) == "string" then return { kind = ref.kind, id = ref.id } end
  end,
  Categories = function() return { "All", "Equipment" } end,
  Search = function() return { entry } end,
  Get = function(ref) if ref.kind == "art" and ref.id == "shield" then return entry end end,
  Draw = function(tex, ref) if ref.kind == "art" and ref.id ~= "shield" then return false, "unavailable" end; tex:SetTexture("art"); return true, "ready" end,
}
local P = R.SettingsArtworkPicker
local owner, other = Fake("Frame"), Fake("Frame")
local closed, applied, current = {}, 0, true
local opts = { key = 1, selection = {kind="art",id="shield"}, IsCurrent = function() return current end,
 OnApply = function() applied = applied + 1; return false, "refused" end,
 OnClosed = function(reason) closed[#closed+1] = reason end }
assert(P.Open(owner, opts)); assert(P.Shown()); assert(P.State(owner).candidate.id == "shield")
for _, malformed in ipairs({1, true, "owner", function() end, {}}) do
  local ok, reason=P.Open(malformed,opts);assert(not ok and reason=="invalid_owner" and P.Shown())
end
local badRef={key=1,selection=false,IsCurrent=opts.IsCurrent,OnApply=opts.OnApply}
local ok, reason=P.Open(owner,badRef);assert(not ok and reason=="invalid_ref" and P.Shown(),"false is not an automatic/default reference")
assert(P.State(other)==nil and not P.Apply(other) and applied==0,"a different owner cannot inspect or accept this session")
local snapshot=P.State(owner);snapshot.candidate.id="changed";assert(P.State(owner).candidate.id=="shield")
assert(P.Frame().events.GET_ITEM_INFO_RECEIVED and P.Frame().events.ITEM_DATA_LOAD_RESULT)
assert(not P.Apply() and P.Shown() and applied == 1); assert(P.Frame().say:GetText() == "refused")
P.TakeItem("|Hitem:6948:0|h[Hearthstone]|h"); assert(P.State().candidate.id == 6948)
opts.OnApply = function(ref) applied = applied + 1; assert(ref.kind == "item" and ref.id == 6948); return true end
assert(P.Apply()); assert(not P.Shown() and closed[#closed] == "applied")
assert(not P.Frame().events.GET_ITEM_INFO_RECEIVED and not P.Frame().events.ITEM_DATA_LOAD_RESULT,"hidden picker retains no metadata listener")
local fallbackDrawn = 0
opts.fallback = { name = "Default artwork", Draw = function(tex) fallbackDrawn = fallbackDrawn + 1; tex:SetTexture("fallback") end }
opts.selection = {kind="art",id="missing"}; assert(P.Open(owner, opts)); assert(not P.Frame().apply:IsEnabled())
assert(P.State().candidate.id == "missing" and fallbackDrawn > 0 and P.Frame().details.name:GetText():find("Default artwork", 1, true))
assert(not P.Apply() and P.Shown()); P.Close(owner)
assert(P.Open(owner, opts)); local ok, why = P.Open(owner, opts); assert(not ok and why == "toggled" and not P.Shown())
opts.selection = nil; opts.automatic = {label="Use automatic icon",name="Automatic",Draw=function() end}
opts.OnApply = function(ref) assert(ref.kind == "automatic"); return true end
assert(P.Open(owner, opts)); assert(P.State().candidate.kind == "automatic"); assert(P.Apply())
assert(P.Open(owner, opts)); current = false; assert(not P.Apply() and not P.Shown() and closed[#closed] == "invalidated"); current = true
assert(P.Open(owner, opts)); local opts2 = {key=2,IsCurrent=function() return true end,OnApply=function() return true end}
assert(P.Open(other, opts2)); assert(closed[#closed] == "replaced"); other:Hide(); assert(not P.Shown())
assert(P.Open(owner, opts)); owner:Hide(); assert(not P.Shown() and closed[#closed] == "owner_hidden")
owner:Show()
opts.OnApply = function() assert(not P.Apply()); return true end
assert(P.Open(owner, opts)); assert(P.Apply())
assert(P.Open(owner, opts)); local bad, reason = P.Open(other, {key=3}); assert(not bad and reason == "invalid_options" and P.Shown()); P.Close(owner)
-- A callback may indirectly replace/close a page; cleanup must not hide its successor.
other:Show()
local faults=0;local fault=R.Fault;R.Fault=function() faults=faults+1 end
opts.OnApply=function() error("synthetic callback refusal") end
assert(P.Open(owner,opts));assert(not P.Apply(owner) and P.Shown() and faults==1);P.Close(owner)
opts.OnApply=function() assert(P.Open(other,opts2));return true end
assert(P.Open(owner,opts));assert(P.Apply(owner) and P.State(other) and P.Shown());P.Close(other)
R.Fault=fault
opts.OnApply=function() return true end
assert(P.Open(owner,opts));R.SettingsLauncher.Closed();assert(not P.Shown() and closed[#closed]=="settings_closed")
-- Repeated opens reuse the one frame/pool and install one hide hook per owner.
local before=made;local frame=P.Frame()
local reminders=R.Reminders;R.Reminders=nil
for i=1,12 do assert(P.Open(owner,opts));assert(P.Frame()==frame);P.Close(owner) end
R.Reminders=reminders
assert(made==before and #owner.hooks.OnHide==1,"picker reuse is bounded and independent of Reminders")
print("PASSED: shared artwork picker lifecycle")
