dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Known ammunition in the settings window (TwichUI_Settings/pages/AmmoItems.lua, a tab of Reminders):
--   * where it sits: a hosted tab of Reminders;
--   * typing an ID or pasting a link, dropping an item (it goes back; anything else is refused and left on the cursor),
--     a repeat, what the game says about an item that is loading or unknown, correcting what an item is, Remove,
--     nothing made again on a redraw, nothing listened for while hidden.
-- Stand-in frames keep their scripts, text, focus and shown state; nothing here is the game.

local made = 0
local function Fake(kind, parent)
  made = made + 1
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
    RegisterEvent = function(s, e) s.events[e] = true end, UnregisterEvent = function(s, e) s.events[e] = nil end,
    CreateTexture = function(s) return Fake("Texture", s) end,
    CreateFontString = function(s) return Fake("FontString", s) end,
  }
  if kind == "ScrollFrame" then f.ScrollBar = Fake("Slider", f); f.ScrollBar.ThumbTexture = Fake("Texture", f.ScrollBar) end
  return setmetatable(f, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end


local ITEMS = {   -- name, class, subclass
  [2512] = { "Rough Arrow", 6, 2 }, [2516] = { "Light Shot", 6, 3 }, [7000] = { "Odd Shot", 6, 0 }, [4242] = { "Mystery Thing", 0, 0 },
}
local function World(c)
  c.CreateFrame = function(kind, name, parent) local f = Fake(kind, parent); if name then c[name] = f end return f end
  c.UIParent = Fake("Frame")
  c.GameTooltip = Fake("GameTooltip")
  c.UNLOADED, c.REQUESTED = {}, {}
  c.C_Item = {
    GetItemInfoInstant = function(id) if ITEMS[id] then return id, "", "", "", 1000 + id, ITEMS[id][2], ITEMS[id][3] end end,
    GetItemIconByID = function(id) if ITEMS[id] then return 1000 + id end end,
    GetItemNameByID = function(id) if ITEMS[id] and not c.UNLOADED[id] then return ITEMS[id][1] end end,
    GetItemInfo = function(id) if ITEMS[id] and not c.UNLOADED[id] then return ITEMS[id][1], "[" .. ITEMS[id][1] .. "]" end end,
    RequestLoadItemDataByID = function(id) c.REQUESTED[id] = (c.REQUESTED[id] or 0) + 1 end,
    GetItemSpell = function() return nil end, GetItemCount = function() return 0 end,
  }
  c.CURSOR = nil
  c.CLEARED = 0
  c.GetCursorInfo = function() if c.CURSOR then return c.CURSOR[1], c.CURSOR[2] end end
  c.ClearCursor = function() c.CLEARED = c.CLEARED + 1; c.CURSOR = nil end
end

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local c, S = SettingsClient({ name = "Rich", beforeInit = World })
local R = c.TwichUI
local AI, K = R.AmmoItems, S.K
local function Flush() for _ = 1, 4 do FlushTimers() end end

local tab
for _, p in ipairs(S.pages) do if p.key == "ammoCustom" then tab = p end end
Check(tab and tab.parent == "Reminders" and tab.kind == "hosted" and tab.name == "Known ammunition", "the list is a tab of Reminders")
Check(S.variables.TWICHUI_ammoWarning == nil, "the old warning's switch is gone")
AI.Remove(90001)

---------------------------------------------------------------------------
-- The Known ammunition tab
---------------------------------------------------------------------------
local P = R.AmmoItemsPage
local f = P.Frame()
Check(P.Frame() == f, "one frame")
f:Hide()
f:Show()   -- built the first time it is shown
Check(f.empty and f.empty.shown and f.count.text == "0 of " .. AI.MAX, "an empty list says what it is for")
Check(f.events.ITEM_DATA_LOAD_RESULT and f.events.GET_ITEM_INFO_RECEIVED, "listens while shown")
Check(f.events.BAG_UPDATE_DELAYED == nil, "and not to the bags: nothing here counts anything")

local function RowFor(id)
  for _, ch in ipairs(f.content.children) do
    if ch.kind_ == nil and ch.remove and ch.id == id and ch.shown then return ch end
  end
end
local function Rows()
  local n = 0
  for _, ch in ipairs(f.content.children) do if ch.remove and ch.shown then n = n + 1 end end
  return n
end

-- input
Check(not P.AddFromText("12x") and P.lastTone == "warn", "not a number")
Check(not P.AddFromText("0") and P.lastTone == "warn", "zero")
f.idBox:SetText("2512")
f.idBox:Fire("OnEnterPressed")
Flush()
Check(AI.Count() == 1 and AI.Entry(2512).kind == "arrow", "typed: added as what the game says it is")
Check(f.idBox.text == "" and P.lastSaid:find("Registered Rough Arrow as arrows", 1, true), "the box is cleared and it says what happened (" .. tostring(P.lastSaid) .. ")")
local row = RowFor(2512)
Check(Rows() == 1 and row and row.name.text == "Rough Arrow" and row.status.text:find("The game lists it as arrows too", 1, true), "drawn with its name and what the game says")
Check(row.kind.value == "arrow" and row.kind.text.text == "Arrows", "and what it is")

-- a pasted link, with the choice on the box
f.addKind.onPick("bullet")
P.AddFromText("|cff9d9d9d|Hitem:2512::::::::60:::::|h[Rough Arrow]|h|r")
Check(AI.Count() == 1 and P.lastSaid:find("already registered", 1, true), "a repeat changes nothing, whatever the choice")
P.AddFromText("|cff9d9d9d|Hitem:2516::::::::60:::::|h[Light Shot]|h|r")
Flush()
Check(AI.Entry(2516) and AI.Entry(2516).kind == "bullet" and Rows() == 2, "a link works, registered as the box said")
f.addKind.onPick("auto")

-- dropping: anything but an item is refused and left on the cursor; an item goes back
c.CURSOR = { "spell", 133 }
Check(not P.AddFromCursor() and c.CURSOR and c.CLEARED == 0 and P.lastTone == "warn", "a spell is refused and left alone")
c.CURSOR = { "item", 7000 }
f.drop:Fire("OnReceiveDrag")
Flush()
Check(AI.Entry(7000) and AI.Entry(7000).kind == "arrow" and c.CURSOR == nil and c.CLEARED == 1, "an item dropped is registered and goes back where it came from")
Check(RowFor(7000).status.text:find("another kind of projectile", 1, true), "and the game's other kind of projectile is said")
c.CURSOR = { "item", 7000 }
f.drop:Fire("OnClick")
Check(AI.Count() == 3 and c.CLEARED == 2, "dropped again: no second entry")
Check(not P.AddFromCursor(), "an empty cursor does nothing")

-- correcting what an item is
local r7 = RowFor(7000)
r7.kind.onPick("bullet")
Flush()
Check(AI.Entry(7000).kind == "bullet" and RowFor(7000).status.text:find("Your registration as bullets decides", 1, true), "corrected, and the page says whose word decides")
RowFor(2512).kind.onPick("bullet")
Flush()
Check(AI.Entry(2512).kind == "bullet" and RowFor(2512).status.text:find("The game lists it as arrows", 1, true), "a registration that differs from the game's is said")

-- items the game has not loaded, or does not have
P.AddFromText("90001")   -- a server item the client has nothing for
Flush()
local r9 = RowFor(90001)
Check(AI.Entry(90001) and r9, "an item the client has no data for is still registered")
Check(r9.status.text:find("Loading", 1, true) and (c.REQUESTED[90001] or 0) >= 1, "its details are asked for and it shows as loading")
for _ = 1, 5 do P.Refresh() end
Check(c.REQUESTED[90001] == 2, "asked for at most twice (" .. tostring(c.REQUESTED[90001]) .. ")")
f:Fire("OnEvent", "ITEM_DATA_LOAD_RESULT", 90001, false)
Flush()
Check(RowFor(90001).status.text:find("no item with this ID yet", 1, true) and AI.Entry(90001), "the game saying there is none is said, and the entry is kept")
ITEMS[90001] = { "Server Shot", 6, 3 }
f:Fire("OnEvent", "GET_ITEM_INFO_RECEIVED", 90001, true)
Flush()
Check(RowFor(90001).name.text == "Server Shot" and RowFor(90001).status.text:find("The game lists it as bullets. Your registration as arrows decides", 1, true), "details that arrive are used: " .. RowFor(90001).status.text)

-- remove: only the registration
local before = AI.Count()
RowFor(2516).remove:Fire("OnClick")
Check(not AI.Entry(2516) and AI.Count() == before - 1 and P.lastSaid:find("Nothing in your bags or equipment was touched", 1, true), "removed")
Flush()

-- a change made anywhere redraws it
AI.Add(8888, "arrow")
Flush()
Check(RowFor(8888), "an entry added elsewhere appears")
c.TwichUIDB.ui.ammoCustom = { items = { { id = 2512, kind = "arrow" } } }
R.Profiles.Refresh("test")
Flush()
Check(Rows() == 1 and RowFor(2512) and RowFor(2512).kind.value == "arrow", "a profile change redraws it")

-- redraws make nothing new
local count = made
for _ = 1, 5 do P.Refresh() end
f:Hide(); f:Show(); Flush()
Check(made == count, "redrawing and reopening make no new frames")
f:Hide()
Check(not f.events.ITEM_DATA_LOAD_RESULT and not f.events.GET_ITEM_INFO_RECEIVED, "nothing is listened for while hidden")
f:Show()

-- the list is bounded
for i = 1, AI.MAX do AI.Add(200000 + i, "arrow") end
Check(not P.AddFromText("999999") and P.lastSaid:find("holds " .. AI.MAX, 1, true), "a full list says so")

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED")
