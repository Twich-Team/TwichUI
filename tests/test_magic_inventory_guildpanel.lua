-- Magic Inventory, the panel at the guild bank window (inventory/GuildPanel.lua) with stand-in frames and the scripted guild bank
-- of tests/mi_guildsim.lua. Synthetic data only; a stand-in that does what the test says proves the panel's decisions, not the game.
--   * built once, shown while the bank is open, gone when it closes, nothing added by closing and opening again;
--   * "Set up arrangement" when there is none; "Reading bank..." while it is being read; the summary and both actions once ready;
--   * Deposit / Organize bank make ONE review (every tab it touches) and start nothing; Start is the approval; double clicks are one;
--   * progress, Stop, Continue; the result and its Details; a plan that changed before Start gives a new review, never a start;
--   * a tab that did not answer is said (and can be read again); the panel sits outside the bank window.
dofile(TESTS .. "mi_mock.lua")
dofile(TESTS .. "mi_guildsim.lua")

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local created = 0
local c = MIClient("Rich", {
  db = { modules = { magicInventory = true } },
  beforeFiles = function(cl)
    cl.CreateFrame = function(kind, name, parent)
      local fr = MIFake(kind, parent)
      if name then cl[name] = fr; if name == "TwichUIGuildBankPanel" then created = created + 1 end end
      return fr
    end
    cl.UIParent = MIFake("Frame"); cl.UIParent.w, cl.UIParent.h = 1920, 1080
    cl.UIParent.GetTop = function() return 1080 end
    cl.GameTooltip = MIFake("GameTooltip")
    for _, file in ipairs({ "chronicle/Style.lua", "Look.lua", "FrameLook.lua" }) do
      local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, cl); chunk("!!!TwichUI", {})
    end
  end,
  files = MI_FILES,
})
local S = GuildSim(c)
S.Tabs()
local R = c.TwichUI
local MI = R.MagicInventory
local GR, P, Panel = MI.GuildRun, MI.GuildPrep, MI.GuildPanel
local opened
R.OpenSettings = function(_, key) opened = key end

c.ITEMS[2447] = c.ITEMS[2447] or { name = "Peacebloom", class = 7, sub = 9, maxStack = 20, quality = 1 }
c.GUILD.name = "Night Owls"
local function Tab(name) return { name = name, icon = 133, slots = {}, withdraw = -1, remaining = -1 } end
c.GUILD.tabs = { [1] = Tab("Gear"), [2] = Tab("Cloth"), [3] = Tab("Herbs") }
c.GUILD.current = 1
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2447, 20 } } } })
-- the bank window as the panel finds it: it only reads its edges
c.GuildBankFrame.GetWidth = function() return 640 end
c.GuildBankFrame.GetTop = function() return 900 end
c.GuildBankFrame.GetBottom = function() return 300 end

local function Spin(seconds, answer)
  local t = 0
  while t < seconds do
    S.Tick(0.25)
    if answer ~= false then S.Settle() end
    t = t + 0.25
  end
end
local function Texts(frame, out)
  out = out or {}
  if type(frame.text) == "string" and frame.text ~= "" then out[#out + 1] = frame.text end
  for _, ch in ipairs(frame.children or {}) do if ch.shown ~= false then Texts(ch, out) end end
  return out
end
local function Has(pattern)
  local f = c.TwichUIGuildBankPanel
  if not f then return false end
  for _, t in ipairs(Texts(f)) do if t:find(pattern) then return true end end
  return false
end
local function Button(pattern, frame)
  frame = frame or c.TwichUIGuildBankPanel
  if not frame then return nil end
  for _, ch in ipairs(frame.children or {}) do
    if ch.shown ~= false then
      if type(ch.text) == "table" and type(ch.text.text) == "string" and ch.text.text:find(pattern) then return ch end
      local hit = Button(pattern, ch)
      if hit then return hit end
    end
  end
end
local function Click(pattern)
  local b = Button(pattern)
  Check(b ~= nil, "button " .. pattern .. " is there")
  if b and b.enabled ~= false and b.scripts.OnClick then b.scripts.OnClick(b, "LeftButton") end
  Spin(0.5)
  return b
end

local function Arrange(build)
  local D = MI.Design
  local d = D.New("Night Owls", { [1] = { name = "Gear" }, [2] = { name = "Cloth" }, [3] = { name = "Herbs" } }, 3)
  build(D, d, { facts = function(id) return (MI.ItemFacts(id)) end })
  assert(D.Save(d))
end

---------------------------------------------------------------------------
-- No arrangement: it offers to set one up and nothing else
---------------------------------------------------------------------------
S.Open(1)
Spin(2)
local f = c.TwichUIGuildBankPanel
Check(f and f.shown, "the panel is shown with the guild bank")
Check(Has("No arrangement for <Night Owls> yet"), "no arrangement: it says so")
local setup = Button("Set up arrangement")
Check(setup ~= nil and not Button("^Deposit") and not Button("^Organize bank"), "and offers Set up arrangement, not the actions")
setup.scripts.OnClick(setup, "LeftButton")
Check(opened == "magicInventory", "Set up arrangement opens the arrangement editor's page")
Check(#S.clicks == 0 and #S.queries == 0, "nothing is read for a guild with no arrangement")

---------------------------------------------------------------------------
-- An arrangement: reading, then the summary and the actions
---------------------------------------------------------------------------
Arrange(function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2); D.AssignTab(d, ctx, 2447, 3) end)
c.GUILD.tabs[1].slots[7] = { id = 2592, count = 10 }          -- Wool in tab 1; nothing in the arrangement wants it moved
S.noAnswer = { [2] = true, [3] = true }
Spin(1.5, false)
Check(Has("Reading bank"), "while the tabs are read the panel says Reading bank")
do
  local pr = Panel.Progress()
  Check(pr.shown and pr.text:find("^%d of 3 tabs$") and Panel.Texts().title == "Reading the bank", "with a progress bar of the tabs read: " .. tostring(pr.text))
end
local dep = Button("^Deposit")
Check(dep ~= nil and dep.enabled == false, "and Deposit is off with a reason")
S.noAnswer = nil
Spin(10)
Check(Has("2 stacks ready to deposit"), "ready: " .. table.concat(Texts(c.TwichUIGuildBankPanel), " | "))
Check(not Panel.Progress().shown, "and the reading bar is gone")
dep = Button("^Deposit")
local org = Button("^Organize bank")
Check(dep and dep.enabled == true and org ~= nil and org.enabled == false, "Deposit is on; Organize bank is off because there is nothing for it")
Check(Button("Arrangement") ~= nil, "Arrangement is there")
local arrange = Button("Arrangement")
opened = nil
arrange.scripts.OnClick(arrange, "LeftButton")
Check(opened == "magicInventory", "Arrangement opens the editor")
Check(#S.calls == 0 and #S.moves == 0, "nothing has moved")
Check(c.GUILD.current == 1, "the player is on their own tab")

---------------------------------------------------------------------------
-- One review, one approval
---------------------------------------------------------------------------
local before = #S.clicks
for _ = 1, 4 do
  local b = Button("^Deposit")
  if b and b.enabled ~= false then b.scripts.OnClick(b, "LeftButton") end
end
Spin(1)
local rv = Panel.Review()
Check(rv and rv.ok and rv.mode == "deposit" and #rv.tabs == 2, "four clicks on Deposit made one review of both tabs")
do
  local T = Panel.Texts()
  Check(T.title == "Deposit" and T.sub == "2 stacks into Cloth and Herbs", "the review is one big word and one short line: " .. tostring(T.title) .. " / " .. tostring(T.sub))
  Check(not Has("^Review the plan") and not Has("Nothing moves until"), "no paragraph of explanation")
  local shown = 0
  for _, b in ipairs(Panel.DetailFrame().children or {}) do if b.tex and b.shown then shown = shown + 1 end end
  Check(shown == 2, "one icon for each item that moves (" .. shown .. ")")
end
Check(#S.calls == 0 and not GR.Busy(), "a review moves nothing")
Check(Button("^Start deposit") ~= nil and Button("^Cancel") ~= nil, "Start and Cancel are offered")
Check(Button("^Deposit") == nil or Button("^Deposit").enabled == false, "no second action while reviewing")
Check(not Has("%d+%. Details") and Button("^Details") ~= nil, "Details are collapsed")
Click("^Details")
Check(Has("Linen Cloth \195\1512?0?: bag 0 slot 1") or Has("bag 0 slot 1"), "Details lists every move with its source and destination")
Check(Has("show each tab in turn"), "and says the bank window will show each tab in turn")
Click("^Cancel")
Check(Panel.Review() == nil and Has("Nothing was moved"), "Cancel leaves it as it was")
Check(#S.calls == 0, "(still nothing)")

for _ = 1, 3 do
  local b = Button("^Deposit"); if b and b.enabled ~= false then b.scripts.OnClick(b, "LeftButton") end
end
Spin(1)
local go = Button("^Start deposit")
Check(go ~= nil, "the review is up again")
go.scripts.OnClick(go, "LeftButton")
go.scripts.OnClick(go, "LeftButton")      -- a second click on the same approval
Check(GR.Busy() and GR.ListenerCount() > 0, "one run is going")
S.Tick(0)
Check(Has("Depositing: %d+ of 2 moves confirmed") or Has("Depositing"), "progress is shown: " .. table.concat(Texts(c.TwichUIGuildBankPanel), " | "))
Check(Button("^Stop") ~= nil and not Button("^Deposit"), "Stop is offered while it runs, the actions are not")
do
  local pr = Panel.Progress()
  Check(pr.shown and pr.text == "0 of 2" and pr.fill == 0, "a progress bar is up at 0 of 2: " .. tostring(pr.text))
  local mid
  for _ = 1, 200 do
    S.Tick(0.02); S.Settle()
    local p2 = Panel.Progress()
    if p2.shown and p2.text == "1 of 2" then mid = p2 end
    if not GR.Busy() then break end
  end
  Check(mid and mid.fill > 1 and mid.fill < mid.track, "after one of two moves the bar is partly full: " .. tostring(mid and (mid.fill .. "/" .. mid.track)))
end
S.Pump()
Spin(2)
Check(not Panel.Progress().shown, "the bar is gone when the run is over")
Check(not GR.Busy() and GR.Last().outcome == "completed" and #S.moves == 2, "one run, two moves, Completed")
Check(Panel.Texts().title == "Completed" and Panel.Texts().sub == "2 of 2 stacks moved", "the result is one word and one line: " .. tostring(Panel.Texts().title) .. " / " .. tostring(Panel.Texts().sub))
Check(c.GUILD.current == 1, "and the player's tab is shown")
Click("^Dismiss")
Check(not Has("^Completed$"), "Dismiss removes the result")
Spin(6)
Check(Has("Nothing to move") or Has("ready"), "after the run the bank was read again and the summary rebuilt: " .. table.concat(Texts(c.TwichUIGuildBankPanel), " | "))

---------------------------------------------------------------------------
-- A plan that changed before Start: a new review, never a start
---------------------------------------------------------------------------
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2447, 20 } } } })
c.FireEvent("BAG_UPDATE_DELAYED")
Spin(2)
do
  local b = Click("^Deposit")
  local approve = Button("^Start deposit")
  Check(approve ~= nil, "a review again")
  S.Tick(20)
  c.GUILD.tabs[3].slots[1] = { id = 2770, count = 2 }
  c.GUILD.tabs[3].slots[2] = { id = 2770, count = 2 }
  local calls = #S.calls
  approve.scripts.OnClick(approve, "LeftButton")
  S.Pump()
  Spin(1)
  Check(#S.calls == calls and not GR.Busy(), "the bank changed after the review: nothing was moved")
  Check(Has("changed since the review") and Button("^Start deposit") ~= nil, "the panel says so and shows the NEW plan to read and approve: " .. table.concat(Texts(c.TwichUIGuildBankPanel), " | "))
  Click("^Cancel")
end

---------------------------------------------------------------------------
-- A tab that does not answer: said, and can be read again
---------------------------------------------------------------------------
do
  c.CloseGuildBank()
  Spin(0.5)
  Check(not c.TwichUIGuildBankPanel.shown, "closing the bank hides the panel")
  c.GUILD.tabs[3].slots = {}
  S.noAnswer = { [3] = true }
  S.Open(1)
  Spin(30)
  Check(Has("tab 3 not read"), "a tab that never answered is named: " .. table.concat(Texts(c.TwichUIGuildBankPanel), " | "))
  local read = Button("^Read again")
  Check(read ~= nil, "Read again is offered")
  local asks = #S.clicks + #S.queries
  S.noAnswer = nil
  read.scripts.OnClick(read, "LeftButton")
  Spin(8)
  Check(#S.clicks + #S.queries > asks and not Has("tab 3 not read"), "pressing it reads the tab again and the note goes")
end

---------------------------------------------------------------------------
-- A hold during the read for a review (the player has something on the cursor): it says so instead of waiting for ever
---------------------------------------------------------------------------
do
  S.Tick(130)                                       -- every tab is now older than the review accepts
  S.cursor = { id = 2589, count = 1, from = { "bag", 0, 1 } }
  Panel.Act("deposit")
  Spin(3)
  Check(not Has("Reading bank") and Panel.Review() == nil, "with the cursor held it does not wait for ever (" .. table.concat(Texts(c.TwichUIGuildBankPanel), " | ") .. ")")
  Check(Has("cursor"), "and says what to do about it")
  S.cursor = nil
  c.FireEvent("CURSOR_CHANGED")
  Spin(8)
end

---------------------------------------------------------------------------
-- This client opens and closes the bank through the player interaction manager; the older events may never come
---------------------------------------------------------------------------
do
  c.CloseGuildBank(); Spin(1)
  c.GUILD.tabs[2].slots, c.GUILD.tabs[3].slots = {}, {}
  c.GUILD.current = 1
  local before = #S.clicks
  S.OpenManager(1)                                   -- no GUILDBANKFRAME_OPENED
  Spin(10)
  Check(c.TwichUIGuildBankPanel.shown, "opened through the interaction manager: the panel is shown")
  Check(#S.queries > 0 and #S.clicks == before and MI.GuildBank.Snapshot().tabs[2].slots ~= nil and MI.GuildBank.Snapshot().tabs[3].slots ~= nil, "and every tab was read by itself, without visiting any")
  Check(Has("ready to deposit") or Has("Nothing to move"), "so the actions are ready: " .. table.concat(Texts(c.TwichUIGuildBankPanel), " | "))
  S.CloseManager()                                   -- no GUILDBANKFRAME_CLOSED
  Spin(0.5)
  Check(not c.TwichUIGuildBankPanel.shown, "closed through the interaction manager: the panel is gone")
  local n = #S.clicks
  Spin(30)
  Check(#S.clicks == n, "and nothing is asked of the closed bank")
  -- items arriving with no open event at all (a window another addon drew): still opens, still read
  c.GUILD.tabs[2].slots, c.GUILD.tabs[3].slots = {}, {}
  S.OpenQuiet(1)
  Spin(10)
  Check(c.TwichUIGuildBankPanel.shown and MI.GuildBank.Snapshot().tabs[3].slots ~= nil, "a bank known only from its items is read by itself too")
  S.CloseManager(); Spin(0.5)
end

---------------------------------------------------------------------------
-- Reopening: nothing is built twice
---------------------------------------------------------------------------
do
  local frames = Panel.FrameCount()
  for _ = 1, 3 do c.CloseGuildBank(); Spin(1); S.Open(1); Spin(8) end
  Check(created == 1 and Panel.FrameCount() == frames, "the panel was built once and reused (" .. created .. ")")
  Check(c.TwichUIGuildBankPanel.shown, "and it is shown again")
end

---------------------------------------------------------------------------
-- A client that wants a click: Continue is on the panel
---------------------------------------------------------------------------
do
  c.GUILD.tabs[1].slots = { [7] = { id = 2592, count = 10 } }
  c.GUILD.tabs[2].slots, c.GUILD.tabs[3].slots = {}, {}
  c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 } } } })
  c.FireEvent("BAG_UPDATE_DELAYED")
  c.CloseGuildBank(); S.Open(1); Spin(8)
  Click("^Deposit")
  local approve = Button("^Start deposit")
  Check(approve ~= nil, "review for the click test")
  S.requireClick, S.onlyPlace = true, true
  S.inClick = true
  approve.scripts.OnClick(approve, "LeftButton")
  S.inClick = false
  Spin(4)
  Check(GR.Busy() and GR.Progress().needClick and Button("^Continue") ~= nil, "when the game wants a click the panel offers Continue")
  Check(Has("wants a click"), "and says why")
  for _ = 1, 6 do
    if not GR.Busy() then break end
    S.inClick = true
    local b = Button("^Continue")
    if b then b.scripts.OnClick(b, "LeftButton") end
    S.inClick = false
    Spin(2)
  end
  Check(GR.Last() and GR.Last().outcome == "completed", "Continue finished the run: Completed")
  S.requireClick, S.onlyPlace = false, false
end

---------------------------------------------------------------------------
-- Where it sits: the strip outside the bank window; the review joined to it when there is room, else beside the window
---------------------------------------------------------------------------
do
  local fr = c.TwichUIGuildBankPanel
  local host = c.GuildBankFrame
  host.GetBottom, host.GetTop, host.GetLeft, host.GetRight = function() return 300 end, function() return 900 end, function() return 60 end, function() return 700 end
  c.UIParent.GetRight = function() return 1920 end
  local p = fr.points[1]
  Check(p and p[2] == host and ((p[1] == "TOPLEFT" and p[3] == "BOTTOMLEFT") or (p[1] == "BOTTOMLEFT" and p[3] == "TOPLEFT")), "anchored to an outer edge of the bank window, so it covers none of it")
  c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 } } } })
  c.FireEvent("BAG_UPDATE_DELAYED")
  c.GUILD.tabs[2].slots = {}
  Spin(2)
  Panel.Cancel(); Spin(0.5)
  Click("^Deposit")
  Check(Panel.Review() ~= nil, "(a review is up)")
  local d = Panel.DetailFrame()
  Check(d and d.points[1] and d.points[1][2] == fr and d.points[1][1] == "TOPLEFT" and d.points[1][3] == "BOTTOMLEFT", "with room below, the review is joined under the strip")
  host.GetBottom = function() return 100 end
  Panel.Refresh(); Spin(0.5)
  p, d = fr.points[1], Panel.DetailFrame()
  Check(p and p[1] == "TOPLEFT" and p[3] == "BOTTOMLEFT", "the strip stays where it is (room for it below the window)")
  Check(d.points[1][2] == host and d.points[1][1] == "TOPLEFT" and d.points[1][3] == "TOPRIGHT", "no room for the review below: it opens beside the window, on its right, not on top of it")
  host.GetRight, host.GetLeft = function() return 1900 end, function() return 500 end
  Panel.Refresh(); Spin(0.5)
  d = Panel.DetailFrame()
  Check(d.points[1][2] == host and d.points[1][1] == "TOPRIGHT" and d.points[1][3] == "TOPLEFT", "no room on the right either: on its left")
  host.GetLeft = function() return 20 end
  Panel.Refresh(); Spin(0.5)
  d = Panel.DetailFrame()
  Check(d.points[1][2] == fr, "room nowhere beside the window: the last resort joins the strip (and may overlap), never anywhere else")
  host.GetBottom = function() return 10 end
  Panel.Refresh(); Spin(0.5)
  p = fr.points[1]
  Check(p and p[1] == "BOTTOMLEFT" and p[3] == "TOPLEFT", "with no room below the window the strip goes above it")
  host.GetTop = function() return 1075 end
  Panel.Refresh(); Spin(0.5)
  p = fr.points[1]
  Check(p and p[2] == c.UIParent, "with no room either side the strip takes a quiet place at the top of the screen")
  Panel.Cancel(); Spin(0.5)
end

---------------------------------------------------------------------------
-- Off: nothing is shown
---------------------------------------------------------------------------
do
  c.TwichUIDB.modules.magicInventory = false
  MI.Refresh()
  Spin(1)
  Check(not c.TwichUIGuildBankPanel.shown, "with Magic Inventory off the panel is gone")
  Check(MI.GuildPrep.ListenerCount() == 0, "and its preparation listens to nothing")
end

print(failures == 0 and "PASSED test_magic_inventory_guildpanel" or ("FAILED: " .. failures))
if failures > 0 then os.exit(1) end
