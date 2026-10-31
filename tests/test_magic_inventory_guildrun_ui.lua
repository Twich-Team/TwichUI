-- Magic Inventory, the guild bank run in the settings page (TwichUI_Settings/pages/MagicInventoryGuild.lua), driven through the
-- controls' own handlers with stand-in frames over the scripted server of tests/mi_guildsim.lua. Handler-level: it proves what
-- the buttons do and say, not how anything looks or that the real guild bank answers the same way.
--   * Deposit and Organize bank are offered only from a current preview of the SAVED arrangement; unsaved edits offer Save and preview;
--   * pressing one makes a review (action, tab, quantities, what is not included); nothing moves until the second, explicit press;
--   * a changed state withdraws or refuses the confirmation and gives a new review, never a different plan under the old one;
--   * during a run: "N of M moves confirmed", "Waiting for the bank…", editing and previewing off, a Stop; after it, one honest outcome.
dofile(TESTS .. "mi_mock.lua")
dofile(TESTS .. "mi_guildsim.lua")

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local c = MIClient("Rich", {
  db = { modules = { magicInventory = true } },
  beforeFiles = function(cl)
    cl.CreateFrame = function(kind, name, parent) local fr = MIFake(kind, parent); if name then cl[name] = fr end return fr end
    cl.UIParent = MIFake("Frame"); cl.UIParent.w, cl.UIParent.h = 1920, 1080
    cl.GameTooltip = MIFake("GameTooltip")
    for _, file in ipairs({ "chronicle/Style.lua", "Look.lua" }) do
      local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, cl); chunk("!!!TwichUI", {})
    end
  end,
  files = MI_FILES,
})
c.StaticPopupDialogs = {}
c.StaticPopup_Show = function(name, text) c.POPUP = { name = name, text = text }; return {} end
c.GetCursorPosition = function() return 100, 100 end
c.UISpecialFrames = {}
c.tinsert = table.insert
for _, file in ipairs({ "../TwichUI_Settings/Kit.lua", "../TwichUI_Settings/Widgets.lua", "../TwichUI_Settings/pages/MagicInventory.lua",
  "../TwichUI_Settings/pages/MagicInventoryDrag.lua", "../TwichUI_Settings/pages/MagicInventoryGuild.lua" }) do
  local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, c); chunk("TwichUI_Settings", {})
end
local S = GuildSim(c)
local R = c.TwichUI
local MI = R.MagicInventory
local GR = MI.GuildRun
local P = R.MagicInventoryPage
local D = MI.Design

local function Flush() for _ = 1, 8 do S.Tick(0) end end
local function Texts(frame, out)
  out = out or {}
  if type(frame.text) == "string" and frame.text ~= "" then out[#out + 1] = frame.text end
  for _, ch in ipairs(frame.children or {}) do if ch.shown ~= false then Texts(ch, out) end end
  return out
end
local function Has(frame, pattern)
  for _, t in ipairs(Texts(frame)) do if t:find(pattern) then return true end end
  return false
end
local function Ctl(key) local b = P.Control(key); if b and b.shown then return b end end
local function Click(key)
  local b = Ctl(key)
  Check(b ~= nil, "control " .. key .. " is there")
  if b and b.scripts.OnClick then b.scripts.OnClick(b, "LeftButton") end
  Flush()
end

c.ITEMS[2447] = c.ITEMS[2447] or { name = "Peacebloom", class = 7, sub = 9, maxStack = 20, quality = 1 }
c.GUILD.name = "Night Owls"
local function Tab(name) return { name = name, icon = 133, slots = {}, withdraw = -1, remaining = -1 } end
c.GUILD.tabs = { [1] = Tab("Gear"), [2] = Tab("Cloth"), [3] = Tab("Herbs") }
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2589, 20 }, [3] = { 2592, 20 }, [4] = { 2447, 10 } } } })
local ctx = { facts = function(id) return (MI.ItemFacts(id)) end }
do
  local d = D.New("Night Owls", { [1] = { name = "Gear" }, [2] = { name = "Cloth" }, [3] = { name = "Herbs" } }, 3)
  D.AssignTab(d, ctx, 2589, 2); D.AssignTab(d, ctx, 2592, 2); D.AssignTab(d, ctx, 2447, 3)
  assert(D.Save(d))
end
S.Open(2)                 -- tab 2 is read; tabs 1 and 3 have not been (the herbs for tab 3 cannot be part of a run yet)
local f = P.Frame()
f:Hide(); f:Show()
Flush()

-- offered only from a current preview
P.SetView("preview"); Flush()
Check(Has(f, "Carry out the saved arrangement") and Ctl("gRunAct") and Ctl("gRunAct").text.text == "Deposit\226\128\166", "the Preview offers Deposit\226\128\166")
Check(Ctl("gRunAct").scripts.OnClick and Ctl("gRunAct").enabled, "it is on once the preview is current")
Check(#S.calls == 0 and not GR.Busy(), "nothing has moved")

-- an unsaved edit: Save and preview instead
P.SetView("design"); Flush()
local d = P.GuildDraft()
D.AssignTab(d, ctx, 2592, 3)
P.SetView("preview"); Flush()
Check(Ctl("gRunSave") and not Ctl("gRunAct"), "unsaved edits offer Save and preview, not Deposit")
Check(Has(f, "saved arrangement only"), "and say the run uses the saved arrangement only")
Click("gRevert"); Flush()
P.SetView("preview"); Click("gPreview")
Check(Ctl("gRunAct") ~= nil, "after reverting, Deposit is offered again")

-- review: nothing moves yet
Click("gRunAct")
Check(Ctl("gRevHead") and Ctl("gRevGo") and Ctl("gRevNo"), "pressing it opens the review with Start and Cancel")
Check(Has(f, "from your bags into tab 2 \"Cloth\"") and Has(f, "items in %d+ moves"), "the review names the action, the tab and the quantities")
Check(Has(f, "Not read: tabs 1, 3") and Has(f, "Can't be told yet"), "and what is not done (the herbs for tab 3, which was never read, and the line saying so)")
Check(#S.calls == 0 and not GR.Busy(), "still nothing moved")
Check(Ctl("gRevGo").text.text:find("^Do these %d+ moves$") ~= nil, "a partial review says exactly how many moves will be done")
Click("gRevNo")
Check(not Ctl("gRevGo") and #S.calls == 0, "Cancel leaves the bank as it was")

-- a changed bag withdraws the review
Click("gRunAct")
Check(Ctl("gRevGo") ~= nil, "(review again)")
c.BAGS[0].slots[1].count = 19
c.FireEvent("BAG_UPDATE_DELAYED"); f.scripts.OnEvent(f, "BAG_UPDATE_DELAYED"); Flush()
Check(not Ctl("gRevGo") and Has(f, "review was withdrawn"), "a bag change withdraws the review and says so")
c.BAGS[0].slots[1].count = 20
-- ... and a confirmation that outlived a change is refused at the click
Click("gPreview"); Click("gRunAct")
local stale = Ctl("gRevGo")
c.BAGS[0].slots[2].count = 18               -- changes without any event reaching the page
stale.scripts.OnClick(stale, "LeftButton"); Flush()
Check(#S.calls == 0 and not GR.Busy(), "a confirmation after an unseen change starts nothing")
Check(Has(f, "changed since the review") and Ctl("gRevGo") ~= nil, "it says so and shows a NEW review to read and confirm")
c.BAGS[0].slots[2].count = 20
Click("gPreview")

-- the run
Click("gRunAct")
local goBtn = Ctl("gRevGo")
goBtn.scripts.OnClick(goBtn, "LeftButton")
Flush()
Check(GR.Busy() and not Ctl("gRevGo"), "the second press starts exactly one run")
Check(Has(f, "Depositing in tab 2 \"Cloth\": 0 of %d+ moves confirmed"), "progress is confirmed moves, not dispatched ones: 0 so far")
Check(Has(f, "Waiting for the bank\226\128\166"), "and it says it is waiting for the bank")
Check(Ctl("gRunStop") ~= nil and Ctl("gRunStop").enabled, "Stop is offered")
Check(Ctl("gPreview") and not Ctl("gPreview").enabled, "Preview changes is off during the run")
Check(not Ctl("gRunAct"), "and so is starting another one")
P.SetView("design"); Flush()
Check(P.GuildView() == "preview", "the editor can't be opened during a run")
local before = P.GuildDraft() and MI.Design.Digest(P.GuildDraft())
S.Settle(); Flush()
Check(Has(f, "1 of %d+ moves confirmed") or Has(f, "2 of %d+ moves confirmed"), "a confirmed move is counted")
local active = false
for slot = 1, 98 do local b = Ctl("gSlot" .. slot); if b and (b.mark.text == "=" or b.mark.text == "\226\128\166") then active = true end end
Check(active, "the grid shows a restrained marker on the slots the run touched")
S.Pump(); Flush()
Check(not GR.Busy() and GR.Last().outcome == "partial", "the run ends: Partially completed, because the herbs for tab 3 were not part of it")
Check(Has(f, "^Partially completed: %d+ of %d+ moves confirmed"), "the result says so in one line")
Check(Has(f, "2 tabs not read"), "and counts the tabs that were not read")
Check(Has(f, "Refresh the preview first") and Ctl("gRunAct") and not Ctl("gRunAct").enabled, "the old preview is stale after a run: Deposit is off until it is refreshed")
Check(Ctl("gPreview") and Ctl("gPreview").enabled, "the page's controls come back")
local confirmedMarks = 0
for slot = 1, 98 do local b = Ctl("gSlot" .. slot); if b and b.mark.text == "=" then confirmedMarks = confirmedMarks + 1 end end
Check(confirmedMarks >= 1, "confirmed work stays marked")

-- Stop
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2589, 20 }, [3] = { 2592, 20 } } } })
for s = 1, 98 do c.GUILD.tabs[2].slots[s] = nil end
S.Show(2); Flush()
Click("gPreview"); Click("gRunAct")
goBtn = Ctl("gRevGo")
goBtn.scripts.OnClick(goBtn, "LeftButton"); Flush()
Click("gRunStop")
Check(Has(f, "Stopping after the move in progress"), "Stop says it waits for the move in progress")
S.Settle(); S.Pump(); Flush()
Check(GR.Last().outcome == "stopped" and Has(f, "^Stopped: 1 of %d+ moves confirmed"), "the result is Stopped with the confirmed count")
Check(Has(f, "Why: you stopped it"), "and why")

Click("gDetails")
Check(Has(f, "Last run: Stopped"), "Details holds the evidence of the last run")

print(failures == 0 and "PASSED test_magic_inventory_guildrun_ui" or ("FAILED: " .. failures))
if failures > 0 then os.exit(1) end
