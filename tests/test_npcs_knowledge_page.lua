dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- The World Knowledge tab of Vendors and trainers (TwichUI_Settings/pages/NpcKnowledge.lua):
--   * it is a hosted tab of the Vendors and trainers page, built the first time it is shown;
--   * an empty list and a search with no match say different things; the count says "Showing X of Y records";
--   * a large list costs a handful of row frames, however long, and scrolling reuses them;
--   * filters (search with a short wait, area, role, source) combine, Reset clears them, the selection is kept while
--     it still shows and dropped when it doesn't;
--   * the actions name their scope: a deleted record, a filtered set held to the entries it was asked about, one area;
--     cancelling changes nothing; the map is told once;
--   * sending offers only what the game allows, and the question names what is sent;
--   * it listens to the group and guild only while shown, opens and closes without adding listeners or rows.
-- Stand-in frames keep their scripts, text and shown state; nothing here is the game.

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

local MAPS = {
  [1429] = { name = "Elwynn Forest", mapType = 3 }, [1453] = { name = "Stormwind City", mapType = 3 },
  [1455] = { name = "Ironforge", mapType = 3 },
}
local function World(c)
  c.CreateFrame = function(kind, name, parent) local f = Fake(kind, parent); if name then c[name] = f end return f end
  c.UIParent = Fake("Frame")
  c.GameTooltip = Fake("GameTooltip")
  c.C_Map = { GetMapInfo = function(id) local m = MAPS[id]; return m and { mapID = id, name = m.name, mapType = m.mapType } or nil end }
  c.ACCEPT, c.CANCEL = "Accept", "Cancel"
  c.GetTime = function() return 1000 end
end

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
GROUP, GUILD = nil, nil

local c, S = SettingsClient({ name = "Rich", beforeInit = World })
local R = c.TwichUI
local NS, KN = R.NpcStore, R.NpcKnowledge
local function Flush() for _ = 1, 4 do FlushTimers() end end
local function ByName(name)
  for _, row in ipairs(KN.Rows()) do if row.name == name then return row end end
end
R:SetEnabled("npcMap", true)

---------------------------------------------------------------------------
-- 1. The tab
---------------------------------------------------------------------------
local tab
for _, p in ipairs(S.pages) do if p.key == "npcsKnowledge" then tab = p end end
Check(tab and tab.parent == "Vendors and trainers" and tab.kind == "hosted", "World Knowledge is a hosted tab of Vendors and trainers")
local P = R.NpcKnowledgePage
local f = P.Frame()
Check(P.Frame() == f, "one frame")
f:Hide()
f:Show()
Check(f.empty and f.empty.shown and f.empty.text:find("Nothing noted yet", 1, true), "an empty list says it is empty")
Check(f.count.text == "", "and shows no count")
Check(not f.forgetAll.enabled and not f.forgetOne.enabled and not f.clearArea.enabled, "no delete is offered with nothing to delete")
Check(f.events.GROUP_ROSTER_UPDATE and f.events.PLAYER_GUILD_UPDATE, "listens while shown")
f:Hide()
Check(not f.events.GROUP_ROSTER_UPDATE and not f.events.PLAYER_GUILD_UPDATE, "and not while hidden")
f:Show()

---------------------------------------------------------------------------
-- 2. A large list
---------------------------------------------------------------------------
local zonesList = { 1429, 1453, 1455 }
local N = 600
for i = 1, N do
  local m = zonesList[i % 3 + 1]
  NS.Observe({ id = 1000 + i, name = (i % 50 == 0 and "Twin" or "Merchant " .. i), map = m, x = (i % 40) / 40, y = math.floor(i / 40) / 20,
    tags = i % 7 == 0 and { innkeeper = true } or { reagents = true } })
end
Flush()
local function Rows() local n = 0 for _, ch in ipairs(f.content.children) do if ch.name and ch.role then n = n + 1 end end return n end
local function Shown() local n = 0 for _, ch in ipairs(f.content.children) do if ch.name and ch.role and ch.shown then n = n + 1 end end return n end
Check(f.count.text == ("Showing %d of %d records"):format(NS.Counts(), NS.Counts()) or f.count.text:find("Showing 600 of 600"), "the count: " .. f.count.text)
Check(Rows() <= 10 and Shown() == 10, "ten row frames for 600 records: " .. Rows())
Check(f.content.h == N * 24, "the scroll height is the whole list")
local first = f.content.children[1]
f.scroll:SetVerticalScroll(24 * 300)
f.scroll:Fire("OnVerticalScroll", 24 * 300)
Check(Rows() <= 10, "scrolling makes no new rows")
local seen = {}
for _, ch in ipairs(f.content.children) do if ch.name and ch.shown then seen[#seen + 1] = ch.name.text end end
Check(seen[1] == KN.Rows()[301].name, "and shows the records at the new place")
f.scroll:SetVerticalScroll(0)
f.scroll:Fire("OnVerticalScroll", 0)

---------------------------------------------------------------------------
-- 3. Filtering and selection
---------------------------------------------------------------------------
f.search:SetText("twin")
f.search:Fire("OnTextChanged", true)
Check(f.count.text:find("Showing 600 of 600"), "typing waits before it filters")
Flush()
Check(f.count.text == "Showing 12 of 600 records", "searched: " .. f.count.text)
for _ = 1, 3 do f.search:SetText("twi"); f.search:Fire("OnTextChanged", true); f.search:SetText("twin"); f.search:Fire("OnTextChanged", true) end
Flush()
Check(f.count.text == "Showing 12 of 600 records", "a burst of typing is one result")
f.search:SetText("zzzz-nothing")
f.search:Fire("OnTextChanged", true)
Flush()
Check(f.count.text == "Showing 0 of 600 records" and f.empty.shown and f.empty.text == "No records match these filters.", "no match says so, differently from empty")
Check(f.reset.enabled, "reset is offered")
f.reset:Fire("OnClick")
Check(f.search.text == "" and f.count.text == "Showing 600 of 600 records", "Reset clears the search")

-- select a record; it stays selected while it still shows, is dropped when it doesn't
local target = ByName("Merchant 14")
P.Select(target.e)
Check(f.dName.text == "Merchant 14" and f.dBody.text:find("Seen by you", 1, true), "details: " .. f.dBody.text)
Check(f.forgetOne.enabled, "and it can be deleted")
f.search:SetText("merchant 1")
f.search:Fire("OnTextChanged", true)
Flush()
Check(f.dName.text == "Merchant 14", "the selection stays while it is still shown")
f.search:SetText("twin")
f.search:Fire("OnTextChanged", true)
Flush()
Check(f.dName.text == "" and not f.forgetOne.enabled, "and goes when it isn't")
f.reset:Fire("OnClick")

-- area + role + source together
f.zoneDrop.onPick(1455)
f.kindDrop.onPick("innkeeper")
f.sourceDrop.onPick("mine")
local expected = #KN.Filter({ map = 1455, kind = "innkeeper", source = "mine" })
Check(f.count.text == ("Showing %d of 600 records"):format(expected) and expected > 0, "area, role and source combine: " .. f.count.text)
Check(f.forgetAll.enabled, "Delete filtered is offered when a filter is on")
f.reset:Fire("OnClick")
Check(not f.forgetAll.enabled, "and not when none is")

---------------------------------------------------------------------------
-- 4. Deleting: one record, a filtered set, an area
---------------------------------------------------------------------------
local changes = 0
NS.OnChange(function() changes = changes + 1 end)
-- the last question asked: { key, text, dialog }
local function Pop()
  local q = S.popup
  return q and { key = q.key, text = q.text, dialog = c.StaticPopupDialogs[q.key] }
end

-- one record
local one = ByName("Merchant 14").e
P.Select(one)
f.forgetOne:Fire("OnClick")
Check(Pop().key == "TWICHUI_NPC_FORGET_ONE" and Pop().text:find("Merchant 14", 1, true) and Pop().text:find("%(%d+%.%d, %d+%.%d%)"), "names the record and its place: " .. Pop().text)
Check(Pop().text:find("only this record", 1, true), "and its scope")
local total0 = KN.Total()
Pop().dialog.OnCancel(nil, nil, "clicked")
Check(KN.Total() == total0, "declined: nothing changes")
f.forgetOne:Fire("OnClick")
c.StaticPopupDialogs.TWICHUI_NPC_FORGET_ONE.OnAccept()
Flush()
Check(KN.Total() == total0 - 1 and ByName("Merchant 14") == nil, "deleted")
Check(f.dName.text == "" and f.count.text == ("Showing %d of %d records"):format(total0 - 1, total0 - 1), "the selection and the count follow: " .. f.count.text)

-- a filtered set is held to what it was when asked
f.search:SetText("twin")
f.search:Fire("OnTextChanged", true)
Flush()
local twins = #KN.Filter({ text = "twin" })
f.forgetAll:Fire("OnClick")
Check(Pop().key == "TWICHUI_NPC_FORGET_SET" and Pop().text:find(("%d records"):format(twins), 1, true) and Pop().text:find('"twin"', 1, true), "names the exact number and the filter: " .. Pop().text)
NS.Observe({ id = 9999, name = "Another Twin", map = 1453, x = 0.3, y = 0.3, tags = { food = true } })
f.search:SetText("")
f.search:Fire("OnTextChanged", true)
Flush()
changes = 0
c.StaticPopupDialogs.TWICHUI_NPC_FORGET_SET.OnAccept()
Flush()
Check(#KN.Filter({ text = "twin" }) == 1 and KN.Filter({ text = "twin" })[1].name == "Another Twin", "only the confirmed twins went; the newcomer and the changed filter did not widen it")
Check(changes == 1, "the map and the tab heard once: " .. changes)

-- one area, whatever the filters show
f.reset:Fire("OnClick")
local areaBefore = #KN.AreaEntries(1455)
local others = KN.Total() - areaBefore
f.areaDrop.onPick(1455)
Check(f.clearArea.enabled, "an area is chosen")
f.clearArea:Fire("OnClick")
Check(Pop().key == "TWICHUI_NPC_CLEAR_AREA" and Pop().text:find("Ironforge", 1, true) and Pop().text:find(("%d records"):format(areaBefore), 1, true), "names the area and the count: " .. Pop().text)
c.StaticPopupDialogs.TWICHUI_NPC_CLEAR_AREA.OnAccept()
Flush()
Check(KN.Total() == others and #KN.AreaEntries(1455) == 0, "only that area went")
Check(not f.clearArea.enabled, "and the cleared area is no longer offered")

---------------------------------------------------------------------------
-- 5. Sending, and reopening
---------------------------------------------------------------------------
local function Buttons(set) local out = {} for _, b in ipairs(set) do out[b.audience] = b end return out end
local sb = Buttons(f.shareAll)
Check(not sb.party.enabled and sb.party.why == "You aren't in a group." and not sb.guild.enabled, "not in a group or guild: refused, with the reason")
Check(sb.whisper.enabled, "a player can still be chosen")
GROUP = { Rich = true }
f:Fire("OnEvent", "GROUP_ROSTER_UPDATE")
Check(sb.party.enabled and not sb.party.why, "a group appears: the button follows")
P.Select(KN.Rows()[1].e)
local one2 = Buttons(f.shareOne)
Check(one2.party.enabled, "a selected record can be sent to the group")
GROUP = nil

local frames, events = #f.children, 0
for _ = 1, 5 do f:Hide(); f:Show() end
for _ in pairs(f.events) do events = events + 1 end
Check(#f.children == frames and events == 2, "reopening adds no frames and no listeners")
Check(Rows() <= 10, "and no rows")

print(failures == 0 and "PASSED" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
