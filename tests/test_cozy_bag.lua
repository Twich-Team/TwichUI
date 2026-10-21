-- Cozy Sleeping Bag guide (guides/): the data, the progression (State.lua, pure), the controller (CozyBag.lua: waiting for the quest
-- history, events, position, map pins) and the window. A fake client stands in for the game's quest log, so this checks our
-- logic, not the game: the in-game checks are listed in docs/cozy-sleeping-bag.md.
dofile(TESTS .. "harness.lua")

local function Check(cond, msg) if not cond then error(msg, 2) end end

---------------------------------------------------------------------------
-- A fake game
---------------------------------------------------------------------------
local function Obj()
  local o = { text = "", shown = true }
  return setmetatable(o, { __index = function(t, k)
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetText" then return function(s, v) s.text = v or "" end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "Show" then return function(s)
      local was = s.shown
      s.shown = true
      if not was or s.firstShow then
        s.firstShow = nil
        for _, h in ipairs((s.hooks or {}).OnShow or {}) do h(s) end
      end
    end end
    if k == "Hide" then return function(s)
      local was = s.shown
      s.shown = false
      if was then for _, h in ipairs((s.hooks or {}).OnHide or {}) do h(s) end end
    end end
    if k == "SetShown" then return function(s, v) if v then s:Show() else s:Hide() end end end
    if k == "SetEnabled" then return function(s, v) s.enabled = v and true or false end end
    if k == "Enable" then return function(s) s.enabled = true end end
    if k == "Disable" then return function(s) s.enabled = false end end
    if k == "IsEnabled" then return function(s) return s.enabled ~= false end end
    if k == "HasFocus" or k == "IsMouseOver" or k == "IsTruncated" then return function() return false end end
    if k == "GetStringWidth" then return function() return 60 end end
    if k == "GetStringHeight" then return function() return 14 end end
    if k == "GetWidth" then return function(s) return s.width or 372 end end
    if k == "GetHeight" then return function(s) return s.height or 100 end end
    if k == "SetSize" then return function(s, w, h) s.width, s.height = w, h end end
    if k == "SetWidth" then return function(s, w) s.width = w end end
    if k == "SetHeight" then return function(s, h) s.height = h end end
    if k == "SetScale" then return function(s, v) s.scale = v end end
    if k == "GetScale" then return function(s) return s.scale or 1 end end
    if k == "GetFrameLevel" then return function() return 5 end end
    if k == "ClearAllPoints" then return function(s) s.points = {} end end
    if k == "SetPoint" then return function(s, ...) s.points = s.points or {}; s.points[#s.points + 1] = { ... } end end
    if k == "GetCenter" then return function(s) return s.center and s.center[1] or 512, s.center and s.center[2] or 384 end end
    if k == "CreateFontString" then return function() return Obj() end end
    if k == "CreateTexture" then return function() return Obj() end end
    if k == "ScrollBar" then
      local sb = Obj(); rawset(sb, "ThumbTexture", false); rawset(sb, "ScrollUpButton", false); rawset(sb, "ScrollDownButton", false)
      rawset(t, k, sb); return sb
    end
    if type(k) == "string" and k:match("^%l") then return nil end
    return function() end
  end })
end

local MAPS = { [1436] = "Westfall", [1413] = "The Barrens", [1442] = "Stonetalon Mountains", [1432] = "Loch Modan",
  [1417] = "Arathi Highlands", [1424] = "Hillsbrad Foothills" }

local FRAMES
-- A client with the guide loaded. quests: { done = set, log = set, ready = set }; faction. Fires nothing yet.
local function Client(name, faction, quests, opts)
  opts = opts or {}
  local c = MakeClient(name, { "!!!TwichUI" })
  FRAMES = {}
  local realCreate = c.CreateFrame
  c.CreateFrame = function(kind, fname)
    local o = Obj()
    local base = realCreate()
    for k, v in pairs(base) do if k ~= "Show" and k ~= "Hide" and k ~= "IsShown" then rawset(o, k, v) end end
    rawset(o, "kindOf", kind)
    FRAMES[#FRAMES + 1] = o
    if fname then c[fname] = o end
    return o
  end
  c.tinsert = table.insert
  c.UISpecialFrames = {}
  c.UIParent = Obj()
  rawset(c.UIParent, "width", 1024); rawset(c.UIParent, "height", 768)
  c.GameTooltip = Obj(); c.GameTooltip_Hide = function() end
  c.StaticPopupDialogs = {}
  c.POPUPS = {}
  c.StaticPopup_Show = function(key, text) c.POPUPS[#c.POPUPS + 1] = { key = key, text = text }; return {} end
  c.ACCEPT, c.CANCEL = "Accept", "Cancel"
  c.InCombatLockdown = function() return false end
  c.UnitFactionGroup = function() return faction end
  c.UnitLevel = function() return opts.level or 20 end
  c.QUESTS = quests
  c.CALLS = { done = 0, onQuest = 0, ready = 0 }
  c.C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) c.CALLS.done = c.CALLS.done + 1; return c.QUESTS.done[id] == true end,
    IsOnQuest = function(id) c.CALLS.onQuest = c.CALLS.onQuest + 1; return c.QUESTS.log[id] == true end,
    ReadyForTurnIn = function(id) c.CALLS.ready = c.CALLS.ready + 1; return (c.QUESTS.ready or {})[id] == true end,
  }
  c.C_Map = { GetMapInfo = function(id) return MAPS[id] and { mapID = id, name = MAPS[id], parentMapID = 0 } or nil end }
  c.issecretvalue = nil
  c.FitToScreenCalls = 0
  for _, f in ipairs({ "chronicle/Style.lua", "Look.lua", "modules/Interact.lua", "pins/Pins.lua",
    "guides/CozyBagData.lua", "guides/CozyBagState.lua", "guides/CozyBag.lua", "guides/CozyBagWindow.lua" }) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  c.TwichUIDB = { modules = { partyPins = true } }
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  c.R = c.TwichUI
  return c
end

local function Set(...) local s = {} for _, id in ipairs({ ... }) do s[id] = true end return s end
local function Q(done, log, ready) return { done = Set(unpack(done or {})), log = Set(unpack(log or {})), ready = Set(unpack(ready or {})) } end
local function Enter(c) c.FireEvent("PLAYER_ENTERING_WORLD", true, false); c.FireEvent("QUEST_LOG_UPDATE") end

-- The data, the quests in order for each side
local A_CHAIN = { 79008, 79008, 79192, 79980, 79974, 79975, 79976 }
local H_CHAIN = { 79007, 79007, 79192, 79980, 79974, 79975, 79976 }

local function Eval(c, faction)
  local R = c.R
  local reader = {
    ready = true,
    completed = c.C_QuestLog.IsQuestFlaggedCompleted, onQuest = c.C_QuestLog.IsOnQuest, readyToTurnIn = c.C_QuestLog.ReadyForTurnIn,
  }
  return R.CozyBagState.Evaluate(R.CozyBagData, faction, reader)
end
local function States(r)
  local out = {}
  for i, e in ipairs(r.steps) do out[i] = e.state .. (e.phase and (":" .. e.phase) or "") end
  return table.concat(out, " ")
end

---------------------------------------------------------------------------
-- 1. The data: ids, order, factions, places
---------------------------------------------------------------------------
do
  local c = Client("Data", "Alliance", Q())
  local D = c.R.CozyBagData
  local ids, quests = {}, {}
  for _, s in ipairs(D.steps) do
    Check(not ids[s.id], "step ids are unique: " .. s.id)
    ids[s.id] = true
    Check(type(s.title) == "string" and s.title ~= "" and type(s.text) == "string" and s.text ~= "", "a step has a title and instructions")
    Check(type(s.quest) == "number" and (s.kind == "start" or s.kind == "finish"), "a step names its quest and what it proves")
    Check(#s.places >= 1, "a step has a place")
    for _, p in ipairs(s.places) do
      Check(MAPS[p.map], "a known map: " .. s.id)
      Check(p.x > 0 and p.x < 100 and p.y > 0 and p.y < 100, "coordinates are percentages: " .. s.id)
      Check(type(p.label) == "string" and p.label ~= "", "a place is labelled")
    end
  end
  -- Alliance: Westfall then The Barrens; Horde the other way; shared from Stonetalon on
  local function Chain(faction)
    local r = Eval(Client("Chain", faction, Q()), faction)
    local list = {}
    for _, e in ipairs(r.steps) do list[#list + 1] = e.step.quest end
    return list
  end
  local a, h = Chain("Alliance"), Chain("Horde")
  for i, id in ipairs(A_CHAIN) do Check(a[i] == id, "Alliance quest " .. i) end
  for i, id in ipairs(H_CHAIN) do Check(h[i] == id, "Horde quest " .. i) end
  Check(a[1] == 79008 and a[2] == 79008 and h[1] == 79007 and h[2] == 79007, "the Alliance's first two steps share one quest")
  local westfall = D.steps[1].places[1]
  Check(westfall.map == 1436 and westfall.x == 37.5 and westfall.y == 50.7, "the Alliance starts at Alexston Farmstead")
  Check(D.steps[2].places[1].map == 1413 and D.steps[2].places[1].x == 46.4 and D.steps[2].places[1].y == 73.9, "...and finishes south of Camp Taurajo")
  Check(D.steps[3].places[1].map == 1413 and D.steps[4].places[1].map == 1436, "the Horde goes the other way")
  Check(#D.steps[8].places == 2 and D.steps[8].places[2].map == 1424, "one step can have two places (the climb-in cart)")
  Check(D.steps[#D.steps].optional and D.steps[#D.steps].quest == 80001, "the firepit is optional")
  Check(D.item == 211527 and D.level == 14)
end

---------------------------------------------------------------------------
-- 2. Progression from the quest history
---------------------------------------------------------------------------
do
  -- a fresh character: step one is current, nothing is done
  local c = Client("Fresh", "Alliance", Q())
  local r = Eval(c, "Alliance")
  Check(r.status == "ready" and r.current == 1 and r.done == 0 and r.total == 7 and not r.complete, "fresh: step one")
  Check(States(r) == "current upcoming upcoming upcoming upcoming upcoming upcoming optional", "fresh: " .. States(r))

  -- steps completed before TwichUI was installed: only the history says so (nothing in the log, no session events)
  c = Client("Early", "Alliance", Q({ 79008, 79192 }))
  r = Eval(c, "Alliance")
  Check(r.current == 4 and r.done == 3 and States(r):find("^done done done current"), "early steps from history: " .. States(r))

  -- mid-chain with nothing in the log at all
  c = Client("Mid", "Alliance", Q({ 79008, 79192, 79980, 79974 }))
  r = Eval(c, "Alliance")
  Check(r.current == 6 and r.done == 5, "mid-chain, empty log: step 6 is next (" .. States(r) .. ")")

  -- a quest accepted: the start step is done by taking it; the next is current
  c = Client("Accepted", "Alliance", Q({}, { 79008 }))
  r = Eval(c, "Alliance")
  Check(States(r):find("^done current"), "accepting the first quest finishes step one: " .. States(r))
  -- the finish step shows the quest in progress, not done
  c = Client("Accepted2", "Alliance", Q({}, { 79008 }))
  r = Eval(c, "Alliance")
  Check(r.steps[2].phase == "accepted" and r.steps[2].state == "current", "the finish step is in progress")

  -- objectives complete but not turned in: labelled apart from done
  c = Client("Ready", "Alliance", Q({ 79008 }, { 79192 }, { 79192 }))
  r = Eval(c, "Alliance")
  Check(r.steps[3].state == "current" and r.steps[3].phase == "ready", "ready to turn in is its own state")
  Check(r.done == 2, "...and is not counted as done")

  -- an abandoned quest (no longer in the log, never completed) goes back to being next
  c = Client("Abandon", "Alliance", Q({ 79008 }, { 79192 }))
  Check(Eval(c, "Alliance").steps[3].phase == "accepted")
  c.QUESTS.log[79192] = nil
  r = Eval(c, "Alliance")
  Check(r.current == 3 and r.steps[3].phase == nil, "abandoned: next again, no phase")

  -- a start step abandoned before the quest was ever turned in
  c = Client("Abandon2", "Alliance", Q({}, { 79008 }))
  c.QUESTS.log[79008] = nil
  Check(Eval(c, "Alliance").current == 1, "abandoning the first quest puts step one back")

  -- an accepted later quest does not make an earlier open step done or current
  c = Client("Odd", "Alliance", Q({}, { 79192 }))
  r = Eval(c, "Alliance")
  Check(r.current == 1 and r.steps[3].phase == "accepted" and r.steps[3].state == "upcoming", "a later quest in the log is shown, but step one stays current")

  -- the whole chain done before TwichUI was loaded; the reward item is nowhere
  c = Client("Full", "Alliance", Q({ 79008, 79192, 79980, 79974, 79975, 79976 }))
  r = Eval(c, "Alliance")
  Check(r.complete and r.current == nil and r.done == 7, "the whole chain is done: " .. States(r))
  Check(r.steps[8].state == "optional", "the firepit is optional and does not count")
  c.QUESTS.done[80001] = true
  r = Eval(c, "Alliance")
  Check(r.steps[8].state == "done" and r.total == 7 and r.done == 7, "doing the optional step counts for nothing")
  -- an optional step done while the chain is not never makes it current
  c = Client("Opt", "Alliance", Q({ 80001 }))
  Check(Eval(c, "Alliance").current == 1)

  -- Horde: the same quests, the other way round
  c = Client("Horde", "Horde", Q({}, { 79007 }))
  r = Eval(c, "Horde")
  Check(r.steps[1].step.id == "h-barrens" and r.steps[1].state == "done" and r.steps[2].state == "current", "Horde step one is in The Barrens: " .. States(r))
  -- and an Alliance quest does nothing for a Horde character
  c = Client("Horde2", "Horde", Q({ 79008 }))
  Check(Eval(c, "Horde").current == 1, "the other side's quests do not count")

  -- an unknown faction cannot tell the sides apart
  c = Client("Neutral", "Neutral", Q({ 79008 }))
  r = Eval(c, "Neutral")
  Check(r.status == "needs-faction" and #r.steps == 0 and r.current == nil, "no faction, no steps")
end

---------------------------------------------------------------------------
-- 3. A later step that proves an earlier one, only where the data says so
---------------------------------------------------------------------------
do
  local c = Client("Proof", "Alliance", Q({ 3 }))
  local ST = c.R.CozyBagState
  local guide = { steps = {
    { id = "one", kind = "finish", quest = 1, provedBy = { "two" } },
    { id = "two", kind = "finish", quest = 2, provedBy = { "three" } },
    { id = "three", kind = "finish", quest = 3 },
    { id = "four", kind = "finish", quest = 4 },
  } }
  local reader = { ready = true, completed = function(id) return c.QUESTS.done[id] == true end,
    onQuest = function() return false end, readyToTurnIn = function() return false end }
  local r = ST.Evaluate(guide, "Alliance", reader)
  Check(r.steps[1].state == "done" and r.steps[1].inferred and r.steps[2].state == "done" and r.steps[2].inferred, "a later quest carries through a chain that names it")
  Check(r.steps[3].state == "done" and not r.steps[3].inferred and r.current == 4, "the proof stops where the data stops")
  -- steps that do not name each other are never inferred
  guide.steps[1].provedBy, guide.steps[2].provedBy = nil, nil
  r = ST.Evaluate(guide, "Alliance", reader)
  Check(r.current == 1 and r.steps[2].state == "upcoming", "without provedBy, a later quest proves nothing")
  -- the real data infers nothing across quests
  for _, s in ipairs(c.R.CozyBagData.steps) do Check(s.provedBy == nil, "the real chain claims no cross-quest proof: " .. s.id) end
  -- a step cannot be proved by an earlier one
  guide.steps[3].provedBy = { "one" }
  c.QUESTS.done[1] = true
  c.QUESTS.done[3] = nil
  r = ST.Evaluate(guide, "Alliance", reader)
  Check(r.steps[3].state ~= "done", "proof only runs backwards")
end

---------------------------------------------------------------------------
-- 4. The history arrives later: nothing is concluded before it does
---------------------------------------------------------------------------
do
  local c = Client("Late", "Alliance", Q({ 79008, 79192, 79980 }))
  local R = c.R
  local Cz, Win = R.CozyBag, R.CozyBagWindow
  Check(not Cz.HistoryReady(), "not ready at login")
  Check(Cz.Result().status == "loading" and #Cz.Result().steps == 0 and Cz.Result().current == nil, "unknown: no step is done or selected")
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  Check(not Cz.HistoryReady(), "entering the world alone is not enough")
  local reads = c.CALLS.done
  Win.Show()
  local f = Win.Frame()
  Check(f:IsShown(), "the window opened")
  Check(Cz.Result().status == "loading", "still checking while the history has not come")
  Check(c.CALLS.done == reads, "no quest is read while the history is unknown")
  Check(f.progress.text:find("Checking quest progress"), "the window says so: " .. tostring(f.progress.text))
  Check(Cz.View().id == nil and not Cz.SelectedStep(), "no step is selected while checking")
  c.FireEvent("QUEST_LOG_UPDATE")
  Check(Cz.HistoryReady() and Cz.Result().status == "ready" and Cz.Result().current == 5, "the first update brings the answer (history says four steps done)")
  Check(Cz.View().id == "figurine", "the window moved to the detected step, not to step one")
  Check(f.progress.text:find("4 of 7"), "progress shows: " .. f.progress.text)
  -- the safety wait: no QUEST_LOG_UPDATE ever comes
  local c2 = Client("Late2", "Alliance", Q({ 79008 }))
  c2.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  Check(not c2.R.CozyBag.HistoryReady())
  FlushTimers(); RunLongTimers(2)
  Check(not c2.R.CozyBag.HistoryReady(), "a short wait is not enough")
  RunLongTimers(5)
  Check(c2.R.CozyBag.HistoryReady(), "after a few seconds with the world entered, the history is trusted (one timer, not polling)")
  -- an update before the world is entered does not count alone
  local c3 = Client("Late3", "Alliance", Q({ 79008 }))
  c3.FireEvent("QUEST_LOG_UPDATE")
  Check(not c3.R.CozyBag.HistoryReady(), "an update before the world is not enough")
  c3.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  Check(c3.R.CozyBag.HistoryReady(), "but with the world, it is")
end

---------------------------------------------------------------------------
-- 5. Events: nothing while closed, one look for a burst while open, nothing again after closing
---------------------------------------------------------------------------
do
  local c = Client("Events", "Alliance", Q({ 79008 }))
  local R = c.R
  Enter(c)
  local Cz, Win = R.CozyBag, R.CozyBagWindow
  local looks = Cz.Snapshot().looks
  for _ = 1, 20 do c.FireEvent("QUEST_LOG_UPDATE") end
  c.FireEvent("QUEST_TURNED_IN", 79192); FlushTimers()
  Check(Cz.Snapshot().looks == looks and c.CALLS.done == 0, "closed: events do no work and no quest is read")
  Win.Show()
  local opened = Cz.Snapshot().looks
  Check(opened == looks + 1, "opening reads the history once")
  c.QUESTS.done[79192] = true
  for _ = 1, 30 do c.FireEvent("QUEST_LOG_UPDATE") end
  c.FireEvent("QUEST_TURNED_IN", 79192); c.FireEvent("QUEST_REMOVED", 79192); c.FireEvent("QUEST_ACCEPTED", 1, 79980)
  Check(Cz.Snapshot().looks == opened and Cz.Snapshot().queued, "a burst is waiting for one look")
  FlushTimers()
  Check(Cz.Snapshot().looks == opened + 1, "...and gets exactly one")
  Check(Cz.Result().done == 3, "the new answer: " .. tostring(Cz.Result().done))
  -- an event that changes nothing shown does not redraw
  local changes = Cz.Snapshot().changes
  c.FireEvent("QUEST_LOG_UPDATE"); FlushTimers()
  Check(Cz.Snapshot().changes == changes, "nothing changed, so the window is not told")
  -- closed again: listening stops
  Win.Hide()
  local after = Cz.Snapshot().looks
  c.FireEvent("QUEST_LOG_UPDATE"); c.FireEvent("QUEST_TURNED_IN", 1); FlushTimers()
  Check(Cz.Snapshot().looks == after and not Cz.Snapshot().open, "closed: listening stopped")
  -- a look queued just before closing does nothing afterwards
  Win.Show()
  c.FireEvent("QUEST_LOG_UPDATE")
  Check(Cz.Snapshot().queued)
  Win.Hide()
  local n = Cz.Snapshot().looks
  FlushTimers()
  Check(Cz.Snapshot().looks == n, "a queued look is cancelled by closing")
  -- no OnUpdate anywhere in the guide
  for _, fr in ipairs(FRAMES) do Check(not (fr.scripts and fr.scripts.OnUpdate), "no OnUpdate handler") end
  -- a quest finished while the guide was closed is right the moment it opens
  c.QUESTS.done[79980] = true
  Win.Show()
  Check(Cz.Result().done == 4, "finished while closed: right on opening")
  Win.Hide()
end

---------------------------------------------------------------------------
-- 6. Following the current step, and looking elsewhere
---------------------------------------------------------------------------
do
  local c = Client("Follow", "Alliance", Q({ 79008 }))
  local R = c.R
  Enter(c)
  local Cz, Win = R.CozyBag, R.CozyBagWindow
  Win.Show()
  Check(Cz.View().id == "litter" and Cz.View().following, "following the current step")
  -- progress advances while following: the view moves on
  c.QUESTS.done[79192] = true
  c.FireEvent("QUEST_TURNED_IN", 79192); FlushTimers()
  Check(Cz.View().id == "mound" and Cz.View().following, "the view follows progress")
  -- the player looks at a past step: detected progress does not change
  Cz.Pick("a-westfall")
  Check(Cz.View().id == "a-westfall" and not Cz.View().following, "browsing a past step")
  Check(Cz.Result().current == 4 and Cz.Result().done == 3, "...does not touch the detected progress")
  Check(Win.Frame().current.enabled == true, "a way back is offered")
  -- progress advances: the browsing view stays
  c.QUESTS.done[79980] = true
  c.FireEvent("QUEST_TURNED_IN", 79980); FlushTimers()
  Check(Cz.View().id == "a-westfall" and Cz.Result().current == 5, "automatic advancement does not steal a browsed step")
  Check(Win.Frame().progress.text:find("4 of 7"), "but the progress is updated")
  -- a future step too
  Cz.Pick("satchel")
  c.QUESTS.done[79974] = true
  c.FireEvent("QUEST_TURNED_IN", 79974); FlushTimers()
  Check(Cz.View().id == "satchel", "a future step stays too")
  -- back to the current step
  Cz.Follow()
  Check(Cz.View().following and Cz.View().id == "bag", "back to the detected step")
  Check(Win.Frame().current.enabled == false, "...and the button rests")
  -- picking the current step is the same as following
  Cz.Pick("a-westfall"); Cz.Pick("bag")
  Check(Cz.View().following, "choosing the current step follows it")
  -- finishing the chain: the view rests on the last required step and nothing opens or celebrates
  c.QUESTS.done[79975], c.QUESTS.done[79976] = true, true
  c.FireEvent("QUEST_TURNED_IN", 79976); FlushTimers()
  Check(Cz.Result().complete and Cz.View().id == "satchel" and Win.Frame().progress.text:find("All 7 steps done"), "finished state")
  Win.Hide()
  c.FireEvent("QUEST_TURNED_IN", 1); FlushTimers()
  Check(not Win.IsShown(), "it never reopens by itself")
  -- reopening starts by following again
  Win.Show()
  Check(Cz.View().following, "a new opening follows")
  Win.Hide()
end

---------------------------------------------------------------------------
-- 7. Character isolation: nothing about progress is saved
---------------------------------------------------------------------------
do
  local a = Client("Alt1", "Alliance", Q({ 79008, 79192, 79980, 79974, 79975, 79976 }))
  local b = Client("Alt2", "Alliance", Q())
  Enter(a); Enter(b)
  a.R.CozyBagWindow.Show(); b.R.CozyBagWindow.Show()
  Check(a.R.CozyBag.Result().complete and b.R.CozyBag.Result().done == 0, "each character reads its own history")
  a.R.CozyBag.Pick("litter"); a.R.CozyBag.SetLocked(true)
  local saved = a.TwichUIDB.ui and a.TwichUIDB.ui.cozyBag
  Check(saved and saved.locked == true, "the lock is saved")
  for k in pairs(saved) do Check(k == "locked" or k == "x" or k == "y", "only the lock and the place are saved: " .. k) end
  local dump = {}
  local function Walk(t, path) for k, v in pairs(t) do if type(v) == "table" then Walk(v, path .. "." .. tostring(k)) elseif tostring(k):lower():find("cozy") or tostring(v):lower():find("79008") then dump[#dump + 1] = path .. "." .. tostring(k) end end end
  Walk(a.TwichUIDB, "db")
  Check(#dump == 0, "no quest, step or progress in the saved data: " .. table.concat(dump, ","))
  -- a profile change or import does not carry progress: progress is not in the profile
  local TC = a.R.TwichConfig
  Check(TC and TC.LOCAL["ui.cozyBag"] == "place", "the window's place stays on this computer when sharing")
  a.R.CozyBagWindow.Hide(); b.R.CozyBagWindow.Hide()
end

---------------------------------------------------------------------------
-- 8. Position, lock and reset
---------------------------------------------------------------------------
do
  local c = Client("Place", "Alliance", Q())
  local R = c.R
  Enter(c)
  local Cz, Win = R.CozyBag, R.CozyBagWindow
  local x, y, saved = Cz.Position()
  Check(not saved and x == Cz.DEFAULT_POSITION[1] and y == Cz.DEFAULT_POSITION[2], "a sensible default place")
  Check(not Cz.SetPosition(1e9, 0) and not Cz.SetPosition(0 / 0, 0) and not Cz.SetPosition("a", 1), "an unusable place is refused")
  Check(Cz.SetPosition(-100, 50))
  x, y, saved = Cz.Position()
  Check(saved and x == -100 and y == 50, "a place is kept")
  -- a damaged saved place falls back without being erased by reading
  c.TwichUIDB.ui.cozyBag.x = "junk"
  x, y, saved = Cz.Position()
  Check(not saved and x == Cz.DEFAULT_POSITION[1], "a damaged place falls back")
  Check(c.TwichUIDB.ui.cozyBag.x == "junk", "reading does not rewrite it")
  Cz.SetPosition(-100, 50)
  Win.Show()
  local f = Win.Frame()
  local p = f.points[#f.points]
  Check(p[1] == "CENTER" and p[4] == -100 and p[5] == 50, "the window is placed from the centre of the screen")
  -- scaled down to fit: the same screen place, in the frame's own units
  rawset(f, "scale", 0.5)
  Win.Render()
  p = f.points[#f.points]
  Check(p[4] == -200 and p[5] == 100, "a scaled window keeps its screen place")
  rawset(f, "scale", 1)
  -- dragging saves the place; locking stops it
  f.center = { 512 - 40, 384 + 20 }
  f.scripts.OnDragStart(f)
  f.scripts.OnDragStop(f)
  x, y = Cz.Position()
  Check(x == -40 and y == 20, "drag saves the place: " .. x .. "," .. y)
  Cz.SetLocked(true)
  Check(Cz.Locked() and f.lock.text:GetText() == "Unlock", "locked")
  local started = false
  rawset(f, "StartMoving", function() started = true end)
  f.scripts.OnDragStart(f)
  Check(not started, "a locked window does not move")
  Cz.SetLocked(false)
  f.scripts.OnDragStart(f)
  Check(started, "unlocked, it moves")
  Cz.ResetPosition()
  x, y, saved = Cz.Position()
  Check(not saved and x == Cz.DEFAULT_POSITION[1], "reset puts it back")
  Win.Hide()
end

---------------------------------------------------------------------------
-- 9. Map pins
---------------------------------------------------------------------------
do
  local c = Client("Pins", "Alliance", Q({ 79008 }))
  local R = c.R
  Enter(c)
  local Cz, Win, PN, D = R.CozyBag, R.CozyBagWindow, R.Pins, R.CozyBagData
  local sentBefore = #(SENT_LOG or {})
  -- no group traffic, no route
  local navCalls = 0
  R.Nav = { Enabled = function() return false end, StartAt = function() navCalls = navCalls + 1; return true end }
  local stand = {}
  R.PinsMap = { ShowOnMap = function(e) stand[#stand + 1] = e end }

  local litter
  for _, s in ipairs(D.steps) do if s.id == "litter" then litter = s end end
  -- an unrelated pin of the player's first
  local mine = PN.AddLocal({ map = 1442, x = 4080, y = 5260, name = "My camp" })
  local pin, how = Cz.PinPlace(litter, 1)
  Check(pin and how == "made", "pinned")
  Check(pin.map == 1442 and pin.x == 4080 and pin.y == 5260, "map and coordinates are the place's, in whole map steps")
  Check(pin.name == "Cozy Bag: Pocket Litter" and pin.guide == "cozybag:litter:1" and pin.color == "moss", "labelled and tagged: " .. pin.name)
  Check(PN.LocalCount() == 2, "two pins")
  local again, how2 = Cz.PinPlace(litter, 1)
  Check(again == pin and how2 == "existing" and PN.LocalCount() == 2, "pressing it again makes no second pin")
  for _ = 1, 5 do Cz.PinStep(litter) end
  Check(PN.LocalCount() == 2, "repeated Pin this step is idempotent")
  -- a pin that matches by place but is not the guide's is left alone and not mistaken for it
  Check(PN.FindGuide("cozybag:litter:1") == pin and PN.FindGuide("cozybag:litter:2") == nil)
  -- a renamed guide pin is still found; a moved one is not dragged back
  PN.UpdateLocal(pin.id, { name = "Renamed", x = 1000 })
  Check(Cz.PinFor(litter, 1) == pin and pin.x == 1000, "the player's edits stay")
  Cz.PinPlace(litter, 1)
  Check(pin.x == 1000 and pin.name == "Renamed", "pinning again does not undo edits")
  -- a step with two places: a pin for each, labelled apart
  local bag
  for _, s in ipairs(D.steps) do if s.id == "bag" then bag = s end end
  local made, existing, problem = Cz.PinStep(bag)
  Check(made == 2 and existing == 0 and not problem, "both places pinned")
  local p1, p2 = Cz.PinFor(bag, 1), Cz.PinFor(bag, 2)
  Check(p1.map == 1417 and p1.x == 2250 and p1.y == 2420, "the wall")
  Check(p2.map == 1424 and p2.x == 8730 and p2.y == 4960, "the cart")
  Check(p1.name ~= p2.name and p1.name:find("Messenger Bag") and p2.name:find("Cart"), "labelled apart: " .. p1.name .. " / " .. p2.name)
  Check(#p1.name <= PN.NAME_MAX and #p2.name <= PN.NAME_MAX, "names fit")
  made, existing = Cz.PinStep(bag)
  Check(made == 0 and existing == 2 and PN.LocalCount() == 4, "again: none new")
  -- each guide pin has its own tag
  local tags = {}
  for _, p in ipairs(Cz.OwnPins()) do Check(not tags[p.guide], "unique tags"); tags[p.guide] = true end
  Check(#Cz.OwnPins() == 3 and not tags[mine.guide or ""], "three guide pins; yours is not among them")
  -- show on the map is the map's own action; navigation is never started by pinning
  Check(Cz.ShowPlace(bag, 1) and #stand == 1 and stand[1].pin == p1, "show on map")
  Check(not Cz.ShowPlace(litter, 2), "no such place")
  local ok, why = Cz.Navigate(litter, 1)
  Check(not ok and why:find("Navigation is turned off") and navCalls == 0, "navigation is optional and off")
  R.Nav.Enabled = function() return true end
  ok = Cz.Navigate(litter, 1)
  Check(ok and navCalls == 1, "navigation only when asked")
  Check(#(SENT_LOG or {}) == sentBefore, "nothing was sent to anyone")
  Check(PN.SharedCount() == 0 and not PN.SessionOpen(), "no party session or group pin")
  -- the guide's pin is never published as a group pin with its tag
  -- sharing one of them yourself (the existing Share with group) sends the visible fields only, never the tag
  PN.StartSession(1)
  local group = PN.PublishLocal(p1.id)
  Check(group and group.guide == nil, "the tag is never part of a group copy")
  PN.EndSession()
  -- Party pins turned off: the guide says so and makes nothing
  c.TwichUIDB.modules.partyPins = false
  pin, how = Cz.PinPlace(bag, 1)
  Check(pin == nil and how:find("turned off"), "pins off: " .. tostring(how))
  local before = PN.LocalCount()
  local dp, dwhy = Cz.PinPlace(D.steps[5], 1)
  Check(dp == nil and PN.LocalCount() == before, "nothing is made while Party pins are off")
  c.TwichUIDB.modules.partyPins = true
  -- the window's buttons
  Win.Show()
  Cz.Pick("bag")
  local f = Win.Frame()
  Check(f.pinStep.text:GetText() == "Step pinned" and f.pinStep.enabled == false, "everything pinned: the button says so")
  Check(f.remove.enabled == true, "pins can be removed")
  Cz.Pick("mound")
  Check(f.pinStep.text:GetText() == "Pin this step" and f.pinStep.enabled == true, "an unpinned step offers it")
  f.pinStep.scripts.OnClick(f.pinStep)
  Check(Cz.PinFor(D.steps[6], 1) and f.note.text:find("Pinned"), "the button pins and says so: " .. f.note.text)
  f.pinStep.scripts.OnClick(f.pinStep)
  Check(f.pinStep.enabled == false, "and rests")
  Win.Hide()

  -- cleanup: only the guide's own, after asking, never kept pins or yours
  local keptPin = Cz.PinFor(bag, 2)
  PN.UpdateLocal(keptPin.id, { kept = true })
  Win.Show()
  f.remove.scripts.OnClick(f.remove)
  Check(#c.POPUPS == 1 and c.POPUPS[1].text:find("Only pins the Cozy Sleeping Bag guide made"), "it asks first")
  Check(#Cz.OwnPins() == 4 and PN.LocalCount() == 5, "asking removed nothing")
  c.StaticPopupDialogs["TWICHUI_COZYBAG_REMOVE_PINS"].OnAccept()
  Check(PN.FindLocal(mine.id) ~= nil, "your own pin is untouched")
  Check(PN.FindLocal(keptPin.id) ~= nil, "a kept guide pin stays")
  Check(#Cz.OwnPins() == 1 and PN.LocalCount() == 2, "the rest of the guide's pins are gone")
  local ids, n, kept = Cz.OwnPinScope()
  Check(n == 0 and kept == 1, "only the kept one remains")
  -- a pin made after the question is not swept up
  local scope = Cz.OwnPinScope()
  local later = Cz.PinPlace(litter, 1)
  Check(select(2, Cz.RemoveOwnPins({})) == 0 and PN.FindLocal(later.id), "an empty scope removes nothing")
  -- a pin that merely looks like the guide's (no tag) is not the guide's
  local lookalike = PN.AddLocal({ map = 1442, x = 4080, y = 5260, name = "Cozy Bag: Pocket Litter" })
  Cz.RemoveOwnPins()
  Check(PN.FindLocal(lookalike.id) ~= nil, "a pin without the guide's tag is never removed, whatever its name")
  -- a tag typed into another field is not accepted
  Check(PN.ValidGuideTag("cozybag:litter:1") and not PN.ValidGuideTag("a b") and not PN.ValidGuideTag(("x"):rep(100)) and not PN.ValidGuideTag(5), "tags are checked")
  Win.Hide()
end

---------------------------------------------------------------------------
-- 10. The window: rows, labels, long text and scale
---------------------------------------------------------------------------
do
  local c = Client("Window", "Alliance", Q({ 79008 }, { 79192 }, { 79192 }), { level = 10 })
  local R = c.R
  Enter(c)
  local Cz, Win = R.CozyBag, R.CozyBagWindow
  Check(Win.Frame() == nil, "nothing is built until the first open")
  Win.Show()
  local f = Win.Frame()
  Check(f ~= nil and f:IsShown())
  Check(f.intro2.text:find("level 14"), "a character under the level is told: " .. f.intro2.text)
  local seen = {}
  for _, fr in ipairs(FRAMES) do
    if fr.stepId then seen[#seen + 1] = fr end
  end
  Check(#seen == 8, "a row per applicable step: " .. #seen)
  local words = {}
  for _, row in ipairs(seen) do words[#words + 1] = row.status.text end
  Check(words[1] == "Done" and words[2] == "Done" and words[3] == "Turn in" and words[4] == "Later" and words[8] == "Optional", "a word for each state: " .. table.concat(words, ","))
  Check(seen[1].check.shown and not seen[3].check.shown and seen[3].mark.text == ">", "a check for done, an arrow for current")
  Check(f.dStatus.text:find("objectives are complete but the quest is not turned in"), "objectives complete is told apart from turned in: " .. f.dStatus.text)
  -- reopening does not make a second set of widgets or handlers
  local frames = #FRAMES
  Win.Hide(); Win.Show(); Win.Hide(); Win.Show()
  Check(#FRAMES == frames, "reopening builds nothing new")
  Win.Toggle(); Check(not Win.IsShown()); Win.Toggle(); Check(Win.IsShown())
  -- a faction that cannot be read
  c.UnitFactionGroup = function() return nil end
  Cz.Follow(); Win.Render()
  Check(f.listNote.text:find("faction could not be read"), "no faction: said plainly")
  -- opening and closing leaves the controller quiet
  Win.Hide()
  Check(not Cz.Snapshot().open)
  -- the settings page and the launchers exist
  Check(c.R.RunCommand and c.R.CozyBagWindow.Toggle, "the window has an entry point")
  c.R.RunCommand("bag")
  Check(Win.IsShown(), "/tui bag opens it")
  c.R.RunCommand("cozybag")
  Check(not Win.IsShown(), "/tui cozybag is the same command")
end

print("PASSED")
