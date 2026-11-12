-- The Test Lab's interface cases (TwichUI_TestLab/cases/UI.lua) and the guided mechanism (Guided.lua): the read-only scan, the guided pointer
-- probe (a sample at the key, a retry when the pointer is elsewhere, skip, cancel, combat, a closed window, the countdown), the hover
-- adapter, the report, and that no binding, prompt or event outlives a run.
-- OFFLINE MODEL: the fake world (tests/reach_world.lua) answers GetMouseFoci by the simple rule the analysis assumes. This proves the Lab's
-- own logic and what it reports; WHAT THE REAL CLIENT PUTS UNDER THE POINTER is what the guided cases measure in the game, and nothing here.
dofile(TESTS .. "mi_mock.lua")
dofile(TESTS .. "client_format.lua")
local World = dofile(TESTS .. "reach_world.lua")

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local LAB = ROOT .. "../TwichUI_TestLab/"

local function LabFiles()
  local list = {}
  for line in io.lines(LAB .. "TwichUI_TestLab.toc") do
    line = line:gsub("\r", ""):gsub("%s+$", "")
    if line ~= "" and not line:find("^#") then list[#list + 1] = (line:gsub("\\", "/")) end
  end
  return list
end

-- A client with the Lab loaded, a virtual clock, the fake world installed, and recorders for the one input API the Lab uses.
local function Setup(opts)
  opts = opts or {}
  local now, timers, reads = 0, 0, 0
  local c = MIClient("Zzchar", {
    db = { modules = {} },
    beforeFiles = function(cl)
      cl.CreateFrame = function(kind, name, parent)
        local fr = MIFake(kind, parent)
        for _, m in ipairs({ "SetColorTexture", "SetVertexColor", "SetBackdropColor", "SetBackdropBorderColor", "SetTexCoord", "SetFontObject", "SetMaxLetters",
          "SetAutoFocus", "SetTextInsets", "SetJustifyV", "SetJustifyH", "SetWordWrap", "EnableMouse", "SetToplevel", "SetMovable", "SetClampedToScreen",
          "RegisterForDrag", "SetDontSavePosition", "SetFrameStrata", "SetMotionScriptsWhileDisabled", "UnregisterAllEvents" }) do
          fr[m] = function() end
        end
        fr.UnregisterAllEvents = function(s) s.events = {} end
        fr.SetTexture = function(s, v) s.texture = v end
        fr.IsEventRegistered = function(s, e) return s.events[e] == true end
        fr.CreateTexture = function(s) local t = MIFake("Texture", s); t.SetColorTexture = function() end t.SetVertexColor = function() end t.SetTexCoord = function() end t.SetTexture = function(x, v) x.texture = v end return t end
        fr.CreateFontString = function(s) local t = MIFake("FontString", s); t.SetFont = function() return true end t.SetJustifyV = function() end t.SetWordWrap = function() end t.SetTextColor = function() end t.SetJustifyH = function() end return t end
        if name then cl[name] = fr; fr.frameName = name end
        return fr
      end
      cl.UIParent = MIFake("Frame"); cl.UIParent.w, cl.UIParent.h = 1920, 1080
      cl.GameTooltip = MIFake("GameTooltip")
      cl.UISpecialFrames = {}
      for _, file in ipairs({ "chronicle/Style.lua", "Look.lua", "FrameLook.lua", "CraftLook.lua" }) do
        local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, cl); chunk("!!!TwichUI", {})
      end
    end,
    files = {},
  })
  c.TwichUIDB = c.TwichUIDB or {}
  c.GetRealmName = function() return "Zzrealm" end
  c.GetNormalizedRealmName = function() return "Zzrealm" end
  c.UnitName = function() return "Zzchar" end
  c.GetGuildInfo = function() return "Zzguild" end
  c.GetTimePreciseSec = function() reads = reads + 1 return now + reads * 0.00002 end
  c.C_Timer = { After = function() timers = timers + 1 end, NewTicker = function() timers = timers + 1 return { Cancel = function() end } end }
  -- the one input API the Lab uses: recorded, so a leak is a number
  local t = { c = c, bindings = {}, binds = 0, clears = 0, combat = false, timers = function() return timers end }
  c.InCombatLockdown = function() return t.combat end
  if not opts.noBinding then
    c.SetOverrideBindingClick = function(owner, priority, key, name, button)
      t.binds = t.binds + 1
      t.last = { owner = owner, priority = priority, key = key, name = name, button = button }
      t.bindings[owner] = t.bindings[owner] or {}
      t.bindings[owner][key] = name
    end
    c.ClearOverrideBindings = function(owner) t.clears = t.clears + 1; t.cleared = owner; t.bindings[owner] = nil end
  end
  function t.Advance(sec) now = now + sec end
  function t.Clock() return c.GetTimePreciseSec() end
  function t.Bound() local n = 0 for _, keys in pairs(t.bindings) do for _ in pairs(keys) do n = n + 1 end end return n end
  -- the runner keeps its frame private; find it as the frame with the OnUpdate and the regen event
  local made = {}
  local create = c.CreateFrame
  c.CreateFrame = function(...) local f = create(...); made[#made + 1] = f; return f end
  for _, file in ipairs(LabFiles()) do
    local chunk = assert(loadfile(LAB .. file), file); setfenv(chunk, c); chunk("TwichUI_TestLab", {})
  end
  t.TL, t.R = c.TwichUI.TestLab, c.TwichUI
  local RN = t.TL.Runner
  function t.Frame()
    for _, f in ipairs(made) do if f.events.PLAYER_REGEN_DISABLED and f.scripts.OnUpdate then return f end end
  end
  function t.Frames(n, dt)
    for _ = 1, n do
      if not RN.Active() then return end
      t.Advance(dt or 0.016)
      local fr = t.Frame()
      fr.scripts.OnUpdate(fr, dt or 0.016)
    end
  end
  function t.Run(ids, cats)
    local list = {}
    for _, id in ipairs(ids) do list[#list + 1] = t.TL.cases[id] end
    t.done = nil
    Check(RN.Start(list, { cats = cats or { "pointer" }, clock = t.Clock, onDone = function(s) t.done = s end }), "the run starts")
  end
  function t.Key() local b = c[t.TL.Guided.NAME]; b.scripts.OnClick(b) end   -- the bound key, as the game would click the Lab's button
  function t.Result(i) return t.done.results[i or 1] end
  return t
end

-- The fake Workshop window in a world: a window frame, the Add button in its details, and a list of rows with a picture each
local function Scene(t)
  local w = World.New()
  w:Install(t.c)
  local S = { w = w, clicks = 0 }
  S.ws = w:Frame{ name = "TwichUIWorkshop", x = 300, y = 150, w = 1000, h = 700, strata = "HIGH", level = 5, mouse = true }
  local detail = w:Frame{ parent = S.ws, x = 900, y = 200, w = 380, h = 500 }
  S.add = w:Frame{ type = "Button", parent = detail, x = 920, y = 240, w = 340, h = 36, onClick = function() S.clicks = S.clicks + 1 end }   -- centre (1090, 258)
  S.list = w:Frame{ type = "ScrollFrame", parent = S.ws, x = 320, y = 200, w = 560, h = 500 }
  S.rows = {}
  local function Part(a) return { alpha = a, GetAlpha = function(s) return s.alpha end, IsVisible = function() return true end } end
  for i, y in ipairs({ 620, 570, 520, 120 }) do   -- the fourth is scrolled out of the list's viewport
    local row = w:Frame{ type = "Button", parent = S.list, x = 320, y = y, w = 560, h = 50, onClick = function() end, onEnter = function() end }
    row.iconBtn = w:Frame{ type = "Button", parent = row, x = 330, y = y + 6, w = 38, h = 38, onClick = function() end, onEnter = function() end }
    row.hovered, row.selected = false, false
    row.twichHot, row.twichRim, row.twichSel = { parts = { Part(0) } }, { parts = { Part(0) } }, { parts = { Part(0) } }
    function row:Light(on, hot, rim) self.hovered = on; self.twichHot.parts[1].alpha = hot or 0; self.twichRim.parts[1].alpha = rim or 0 end
    S.rows[i] = row
  end
  t.R.Workshop = { ready = true, Window = {
    Frame = function() return S.ws end,
    Opps = function() return { detail = { add = S.add } } end,
    Lists = function() return { opps = { rows = S.rows } } end,
  } }
  return S
end

local function Notes(r) return table.concat(r.notes or {}, "\n") end

---------------------------------------------------------------------------
-- 1. Registry: the guided category starts off, an unqualified run leaves it out, and the cases are registered as guided
---------------------------------------------------------------------------
do
  local t = Setup()
  local TL = t.TL
  Check(TL.categories.pointer.guided and not TL.categories.ui.guided, "pointer is the guided category")
  local all = TL.Select()
  for _, c in ipairs(all) do Check(c.class ~= "guided", c.id .. ": an unqualified run asks for nothing") end
  Same(#TL.Select({ pointer = true }), 3, "the three pointer cases when chosen by name")
  for _, c in ipairs(TL.Select({ pointer = true })) do Same(c.class, "guided"); Check(c.budget >= 100 and c.budget <= TL.MAX_GUIDED_BUDGET, c.id .. " budget " .. c.budget) end
  Same(#TL.rejected, 0, "no case was refused")
  -- the window leaves the guided box unticked and a default run starts no request
  t.Scene = Scene(t)
  local win = TL.Window.Frame()
  Check(not win.boxes.pointer:GetChecked() and win.boxes.core:GetChecked() and win.boxes.ui:GetChecked(), "pointer is unticked, the rest ticked")
  Check(TL.Window.Run(), "a default run starts")
  t.Frames(400)
  Check(not TL.Runner.Active(), "and ends")
  Same(t.binds, 0, "it bound nothing"); Check(not t.TL.Guided.Snapshot().active); Check(t.c.TwichUITestLabPrompt == nil, "and never built the prompt")
  Check(t.c[TL.Guided.NAME] == nil, "nor the key's button")
  local sum = TL.Runner.last
  Check(sum.counts.fail == 0 and sum.counts.error == 0, "no failure in the default run: " .. TL.Report.Build(sum))
end

---------------------------------------------------------------------------
-- 2. The Add button: the key takes the sample, the case passes, everything is released
---------------------------------------------------------------------------
do
  local t = Setup()
  local S = Scene(t)
  local G = t.TL.Guided
  t.c.TwichUITestLabPrompt = nil
  t.Run({ "ui.pointer.add-button" })
  t.Frames(5)
  Check(t.TL.Runner.Active(), "it waits for the player: nothing happens by itself")
  local snap = G.Snapshot()
  Check(snap.active and snap.status == "waiting" and snap.bound == "F9" and snap.proxyShown and snap.promptShown, "the key, the proxy and the prompt are live while it waits")
  Same(t.binds, 1, "one binding"); Same(t.last.key, "F9"); Same(t.last.name, G.NAME); Check(t.last.priority == true); Same(t.last.button, "LeftButton")
  Check(t.last.owner == t.c[G.NAME], "owned by the Lab's own button, not UIParent")
  Check(t.last.owner ~= t.c.UIParent, "(never UIParent)")
  Check(t.c[G.NAME].mouseEnabled == nil and not t.c[G.NAME]:IsMouseOver(), "the key's button is not a mouse target")
  local prompt = t.c.TwichUITestLabPrompt
  Check(prompt.body:GetText():find("Add to crafting plan", 1, true) and prompt.body:GetText():find("Press F9", 1, true), prompt.body:GetText())
  local p = t.TL.Runner.Progress()
  Same(p.results[1].status, "running", "the pending guided step is a running one")
  S.w:Cursor(1090, 258)
  t.Frames(3)
  Check(t.TL.Runner.Active(), "the pointer being there is not enough: nothing is sampled without the key")
  Same(S.clicks, 0, "and nothing was clicked")
  t.Key()
  Same(G.Status(), "sample", "the key took the sample at once")
  local snapA = select(2, G.Status())
  t.Key()
  Check(select(2, G.Status()) == snapA, "a second key press before the case has read the first changes nothing")
  t.Frames(10)
  Check(not t.TL.Runner.Active(), "the case ended")
  local r = t.Result()
  Same(r.status, "pass", tostring(r.detail))
  Same(r.class, "guided"); Same(r.label, "guided")
  local facts = {}
  for _, f in ipairs(r.facts) do facts[f[1]] = f[2] end
  Same(facts["ui.add.topmost_relation"], "self"); Same(facts["ui.add.in_hit_rect"], "true"); Same(facts["ui.add.foci_count"], "2")
  Same(facts["ui.add.source"], "key"); Same(facts["ui.add.attempts"], "1"); Same(facts["ui.add.target_eligible"], "true")
  Check(Notes(r):find("focus 1 (self, workshop)", 1, true) and Notes(r):find("focus 2 (contains, workshop)", 1, true), Notes(r))
  Check(Notes(r):find("evidence: client-foci", 1, true), "the evidence class is written beside the measurement")
  Same(S.clicks, 0, "the probe never clicked the button")
  local after = G.Snapshot()
  Check(not after.active and after.bound == nil and not after.proxyShown and not after.promptShown and not after.countdown, "everything is released")
  Same(t.Bound(), 0, "no binding is left"); Check(t.clears >= 1 and t.cleared == t.c[G.NAME], "cleared for the Lab's own button only")
  local rs = t.TL.Runner.Snapshot()
  Check(not rs.active and not rs.updating and not rs.listening, "the runner is idle")
  Same(t.timers(), 0, "no timer was made")
  -- a second guided run reuses the one button and the one prompt
  local made = t.c[G.NAME]
  t.Run({ "ui.pointer.add-button" }); t.Frames(2); t.Key(); t.Frames(10)
  Check(t.c[G.NAME] == made and t.c.TwichUITestLabPrompt == prompt, "the key's button and the prompt are made once")
  Same(t.Result().status, "pass"); Same(t.Bound(), 0)
end

---------------------------------------------------------------------------
-- 3. A planted overlay: the case FAILS and names the blocker; the report keeps no private name; removed, it passes
---------------------------------------------------------------------------
do
  local t = Setup()
  local S = Scene(t)
  local G = t.TL.Guided
  S.w:Frame{ name = "ZzcharsOverlay_Zzrealm_Zzguild", x = 1000, y = 230, w = 200, h = 60, strata = "DIALOG", mouse = true }
  S.w:Cursor(1090, 258)
  t.Run({ "ui.pointer.add-button" }); t.Frames(2); t.Key(); t.Frames(10)
  local r = t.Result()
  Same(r.status, "fail", "an overlay over the button fails the case: " .. tostring(r.detail))
  Check(r.detail:find("another frame", 1, true) and r.detail:find("[private]", 1, true), "it says another frame, with the name redacted: " .. r.detail)
  local facts = {}
  for _, f in ipairs(r.facts) do facts[f[1]] = f[2] end
  Same(facts["ui.add.topmost_relation"], "other"); Same(facts["ui.add.foci_count"], "3")
  Check(Notes(r):find("focus 1 (other, other)", 1, true) and Notes(r):find("DIALOG", 1, true), "the blocker is described: " .. Notes(r))
  local text = t.TL.Report.Build(t.done)
  Check(text:find("FAIL    ui.pointer.add-button  guided", 1, true), "the report line is FAIL and labelled guided")
  Check(not text:find("Zzchar", 1, true) and not text:find("Zzrealm", 1, true) and not text:find("Zzguild", 1, true), "no character, realm or guild name in the report")
  Check(text:find("        focus 1", 1, true), "the evidence lines are printed under the case")
  Check(not text:find("|H", 1, true), "no link")
  Same(t.Bound(), 0)
end

---------------------------------------------------------------------------
-- 4. The pointer is not where it was asked: not counted, asked again; the Lab's own window under the pointer; the control not on screen
---------------------------------------------------------------------------
do
  local t = Setup()
  local S = Scene(t)
  local G = t.TL.Guided
  t.Run({ "ui.pointer.add-button" }); t.Frames(2)
  S.w:Cursor(100, 100)                       -- nowhere near
  t.Key(); t.Frames(6)
  Same(G.Status(), "waiting", "an unusable sample is not counted: it waits again")
  Check(t.c.TwichUITestLabPrompt.status:GetText():find("Not counted (1 of 8)", 1, true) and t.c.TwichUITestLabPrompt.status:GetText():find("not over the Add to crafting plan button", 1, true),
    "and says why: " .. t.c.TwichUITestLabPrompt.status:GetText())
  Check(t.c.TwichUITestLabPrompt.status:GetText():find("to the left of it", 1, true) and t.c.TwichUITestLabPrompt.status:GetText():find("below", 1, true), "with where the pointer was")
  S.w:Cursor(1000, 270)
  S.w:Frame{ name = "TwichUITestLabPrompt", x = 900, y = 240, w = 400, h = 100, strata = "DIALOG", mouse = true }   -- the Lab's own prompt over the button
  t.Key(); t.Frames(6)
  Same(G.Status(), "waiting"); Check(t.c.TwichUITestLabPrompt.status:GetText():find("Test Lab's own window", 1, true), t.c.TwichUITestLabPrompt.status:GetText())
  S.w.frames[#S.w.frames]:Hide()
  S.add:Hide()                               -- the button is not on screen (no recipe chosen)
  t.Key(); t.Frames(6)
  Same(G.Status(), "waiting"); Check(t.c.TwichUITestLabPrompt.status:GetText():find("is not on screen", 1, true), t.c.TwichUITestLabPrompt.status:GetText())
  S.add:Show()
  t.Key(); t.Frames(10)
  local r = t.Result()
  Same(r.status, "pass", tostring(r.detail))
  local facts = {}
  for _, f in ipairs(r.facts) do facts[f[1]] = f[2] end
  Same(facts["ui.add.attempts"], "4", "it counted the attempts, three of them unusable")
  Same(t.Bound(), 0)
end

---------------------------------------------------------------------------
-- 5. The hit rectangle: the pointer on the painted button but outside its hit area is a FAILURE, not a retry
---------------------------------------------------------------------------
do
  local t = Setup()
  local S = Scene(t)
  S.add:SetHitRectInsets(300, 0, 0, 0)       -- only x 1220..1260 can be hit
  S.w:Cursor(1090, 258)
  t.Run({ "ui.pointer.add-button" }); t.Frames(2); t.Key(); t.Frames(10)
  local r = t.Result()
  Same(r.status, "fail", tostring(r.detail))
  Check(r.detail:find("OUTSIDE its hit rectangle", 1, true), r.detail)
  Check(Notes(r):find("insets L300", 1, true), "the insets are in the evidence: " .. Notes(r))
  -- a disabled button is reported as not eligible, and still the topmost frame
  S.add:SetHitRectInsets(0, 0, 0, 0); S.add:Disable()
  t.Run({ "ui.pointer.add-button" }); t.Frames(2); t.Key(); t.Frames(10)
  r = t.Result()
  Same(r.status, "fail"); Check(r.detail:find("not eligible: disabled", 1, true), r.detail)
  S.add:Enable()
  -- nothing takes the pointer here: the client gives it to the world
  S.add:EnableMouse(false); S.ws:EnableMouse(false)
  t.Run({ "ui.pointer.add-button" }); t.Frames(2); t.Key(); t.Frames(10)
  r = t.Result()
  Same(r.status, "fail"); Check(r.detail:find("NO frame takes the pointer", 1, true), r.detail)
end

---------------------------------------------------------------------------
-- 6. Skip, Cancel, combat, a closed window, a timeout, an error: each ends the observation and releases the key
---------------------------------------------------------------------------
do
  local t = Setup()
  local S = Scene(t)
  local G, RN = t.TL.Guided, t.TL.Runner
  S.w:Cursor(1090, 258)
  local function Waiting(ids)
    t.Run(ids or { "ui.pointer.add-button" }); t.Frames(3)
    Check(RN.Active() and G.Snapshot().bound == "F9", "waiting with the key bound")
  end
  local function Released(what)
    local s = G.Snapshot()
    Check(not s.active and s.bound == nil and not s.proxyShown and not s.promptShown, what .. ": released")
    Same(t.Bound(), 0, what .. ": no binding"); Check(not RN.Active(), what .. ": the run is over")
    local rs = RN.Snapshot()
    Check(not rs.updating and not rs.listening, what .. ": the runner is idle")
  end

  -- the prompt's Skip button
  Waiting()
  local skip = t.c.TwichUITestLabPrompt.skip
  skip:GetScript("OnClick")(skip)
  t.Key()
  Same(G.Status(), "skipped", "a key pressed after Skip does not bring the step back")
  t.Frames(5)
  local r = t.Result()
  Same(r.status, "skipped"); Check(r.detail:find("you skipped this step", 1, true), tostring(r.detail)); Released("skip")
  Check(t.TL.Report.Build(t.done):find("SKIP    ui.pointer.add-button", 1, true), "reported as skipped, not as a measurement")

  -- the prompt's Cancel button (Stop)
  Waiting()
  local cancel = t.c.TwichUITestLabPrompt.cancel
  cancel:GetScript("OnClick")(cancel)
  r = t.Result()
  Same(r.status, "stopped"); Check(r.detail:find("Stop was pressed", 1, true) and r.detail:find("not resumed", 1, true), r.detail); Released("cancel")
  Check(t.TL.Report.Build(t.done):find("CANCEL  ui.pointer.add-button", 1, true), "reported as cancelled")

  -- Stop in the Lab window
  Waiting(); Check(RN.Stop("user")); Released("Stop")

  -- combat starts while it waits (the runner sees it each frame)
  Waiting()
  t.combat = true
  t.Frames(2)
  Same(RN.last.ended, "combat"); Same(t.Result().status, "stopped"); Released("combat")
  t.combat = false

  -- the Lab window closed
  Waiting()
  t.TL.Window.Frame():Hide()
  Same(RN.last.ended, "closed"); Released("closed window")
  t.TL.Window.Frame():Show()

  -- the budget runs out
  Waiting()
  t.Advance(200); t.Frames(2)
  Same(t.Result().status, "timeout"); Released("timeout")

  -- an error in the capture ends the case as an error, and releases
  t.TL.Guided.End()
  local broken = t.TL.cases["ui.pointer.add-button"]
  local keep = t.R.Workshop
  t.R.Workshop = { Window = { Frame = function() error("boom") end, Opps = function() end, Lists = function() end } }
  Waiting(); t.Key(); t.Frames(5)
  Same(t.Result().status, "error", "a capture that raises ends the case as an error"); Check(t.Result().detail:find("could not be taken", 1, true) and t.Result().detail:find("boom", 1, true), tostring(t.Result().detail))
  Released("a failing capture")
  t.R.Workshop = keep
end

---------------------------------------------------------------------------
-- 6b. Whatever ends a guided case (a result, a skip, an error, a timeout), the NEXT case in the same run sees no binding and no prompt
---------------------------------------------------------------------------
do
  local t = Setup()
  local S = Scene(t)
  local G, RN = t.TL.Guided, t.TL.Runner
  local seen
  t.TL.Case{ id = "probe.after", cat = "ui", class = "pure", run = function(c)
    local s = G.Snapshot()
    seen = { bound = s.bound, active = s.active, prompt = s.promptShown, proxy = s.proxyShown, n = t.Bound() }
    c:Check(true, "ran")
  end }
  local function After(what, setup)
    seen = nil
    t.Run({ "ui.pointer.add-button", "probe.after" }, { "pointer", "ui" })
    t.Frames(3)
    Check(RN.Active() and G.Snapshot().bound == "F9", what .. ": waiting with the key bound")
    setup()
    t.Frames(20)
    Check(seen, what .. ": the next case ran")
    Check(seen.bound == nil and not seen.active and not seen.prompt and not seen.proxy and seen.n == 0, what .. ": it saw no binding, no prompt, no key button")
    Check(not RN.Active(), what .. ": the run is over")
  end
  S.w:Cursor(1090, 258)
  After("a result", function() t.Key() end)
  After("a skip", function() local b = t.c.TwichUITestLabPrompt.skip; b:GetScript("OnClick")(b) end)
  After("a timeout", function() t.Advance(200) end)
  local keep = t.R.Workshop
  t.R.Workshop = { Window = { Frame = function() error("boom") end, Opps = function() end, Lists = function() end } }
  After("an error", function() t.Key() end)
  t.R.Workshop = keep
  -- a case that crashes while its request is open (nothing of its own cleans up): the runner does
  t.TL.Case{ id = "probe.crash", cat = "pointer", class = "guided", run = function(c)
    Check(G.Begin{ title = "x", capture = function() return {} end }, "opened")
    c:Wait(0)
    error("the case crashed")
  end }
  seen = nil
  t.Run({ "probe.crash", "probe.after" }, { "pointer", "ui" })
  t.Frames(20)
  Same(t.Result(1).status, "error"); Check(t.Result(1).detail:find("the case crashed", 1, true), tostring(t.Result(1).detail)); Check(seen, "the next case ran")
  Check(seen.bound == nil and not seen.active and not seen.prompt and seen.n == 0, "a crash while a request was open: the runner released it before the next case")
end

---------------------------------------------------------------------------
-- 7. A request in combat is refused with a sentence; a client without the binding function uses the countdown
---------------------------------------------------------------------------
do
  local t = Setup()
  local S = Scene(t)
  local G, RN = t.TL.Guided, t.TL.Runner
  t.combat = true
  Check(not RN.Start(t.TL.Select({ pointer = true }), { clock = t.Clock }), "a run is refused in combat")
  local ok, why = G.Begin{ title = "x", capture = function() return {} end }
  Check(ok == false and why == "not during combat", "and so is a request (" .. tostring(why) .. ")")
  Same(t.binds, 0, "no key was bound in combat"); Check(not G.Snapshot().active and t.c.TwichUITestLabPrompt == nil, "and no prompt was opened")
  t.combat = false
  Check(not G.Begin(), "a request without a capture function is refused"); Check(not G.Snapshot().active)

  local n = Setup({ noBinding = true })
  local S2 = Scene(n)
  S2.w:Cursor(1090, 258)
  n.Run({ "ui.pointer.add-button" }); n.Frames(3)
  local snap = n.TL.Guided.Snapshot()
  Check(snap.active and snap.bound == nil, "no key is bound when the client has no such function")
  local prompt = n.c.TwichUITestLabPrompt
  Check(prompt.body:GetText():find("No key is available", 1, true) and prompt.body:GetText():find("Sample in 5 s", 1, true), prompt.body:GetText())
  local count = prompt.count
  count:GetScript("OnClick")(count)
  Check(n.TL.Guided.Snapshot().countdown, "the countdown started")
  n.Frames(100)
  Check(n.TL.Runner.Active() and n.TL.Guided.Status() == "waiting", "1.6 s in: not yet")
  n.Frames(300)
  Check(not n.TL.Runner.Active(), "after 5 s the sample was taken and the case ended")
  Same(n.Result().status, "pass", tostring(n.Result().detail))
  local facts = {}
  for _, f in ipairs(n.Result().facts) do facts[f[1]] = f[2] end
  Same(facts["ui.add.source"], "countdown")
  Same(n.binds, 0, "no binding was ever made"); Check(not n.TL.Guided.Snapshot().countdown and not n.TL.Guided.Snapshot().active)
end

---------------------------------------------------------------------------
-- 8. The hover cases: a row, a selected row, hover that disappears, a child picture
---------------------------------------------------------------------------
do
  local function Sample(t, id, x, y)
    t.w:Cursor(x, y)
    t.Run({ id }); t.Frames(2); t.Key(); t.Frames(10)
    return t.Result()
  end
  local t = Setup()
  local S = Scene(t)
  t.w = S.w
  local row = S.rows[1]            -- x 320..880, y 620..670; its picture x 330..368, y 626..664

  row:Light(true, 1, 1)
  local r = Sample(t, "ui.pointer.opportunity-row", 600, 645)
  Same(r.status, "pass", tostring(r.detail))
  local facts = {}
  for _, f in ipairs(r.facts) do facts[f[1]] = f[2] end
  Same(facts["ui.row.hovered"], "true"); Same(facts["ui.row.hot_alpha"], "1.00"); Same(facts["ui.row.topmost_relation"], "self")
  Check(Notes(r):find("NOT verified: look at it", 1, true), "the report says the animation is not verified")

  -- a selected row is dimmer by design (hot 0.4, rim 0.6) and still counts as lit
  row.selected = true; row:Light(true, 0.4, 0.6)
  r = Sample(t, "ui.pointer.opportunity-row", 600, 645)
  Same(r.status, "pass", "a selected row, hovered: " .. tostring(r.detail))
  Same(({ (function() local f = {} for _, x in ipairs(r.facts) do f[x[1]] = x[2] end return f end)() })[1]["ui.row.selected"], "true")

  -- selected but the hover never arrived (OnEnter did not run): the selection does not stand in for it
  row:Light(false, 0, 0)
  r = Sample(t, "ui.pointer.opportunity-row", 600, 645)
  Same(r.status, "fail"); Check(r.detail:find("not marked hovered", 1, true), r.detail)
  row.selected = false

  -- hovered, but the highlight is still fading in: asked again twice, then a failure
  row:Light(true, 0.05, 0.05)
  t.w:Cursor(600, 645)
  t.Run({ "ui.pointer.opportunity-row" }); t.Frames(2)
  t.Key(); t.Frames(6)
  Same(t.TL.Guided.Status(), "waiting"); Check(t.c.TwichUITestLabPrompt.status:GetText():find("still fading in", 1, true), t.c.TwichUITestLabPrompt.status:GetText())
  row:Light(true, 1, 1)             -- the player waited a moment
  t.Key(); t.Frames(10)
  Same(t.Result().status, "pass", "lit on the second try: " .. tostring(t.Result().detail))
  row:Light(true, 0.05, 0.05)
  t.Run({ "ui.pointer.opportunity-row" }); t.Frames(2)
  t.Key(); t.Frames(6); t.Key(); t.Frames(6); t.Key(); t.Frames(10)
  Same(t.Result().status, "fail"); Check(t.Result().detail:find("not lit", 1, true), tostring(t.Result().detail))

  -- a frame over the row: blocked
  row:Light(true, 1, 1)
  local cover = S.w:Frame{ name = "Cover", x = 320, y = 620, w = 560, h = 50, strata = "DIALOG", mouse = true }
  r = Sample(t, "ui.pointer.opportunity-row", 600, 645)
  Same(r.status, "fail", "a frame over the row takes the pointer: " .. tostring(r.detail))
  Check(r.detail:find("another frame", 1, true), r.detail)
  cover:Hide()

  -- the pointer on the picture is a child of the row: the row case asks to aim at the name; the picture case wants the row to stay lit
  r = Sample(t, "ui.pointer.opportunity-row", 350, 645)
  Same(r.status, "fail"); Check(r.detail:find("a child frame of the row", 1, true), r.detail)
  r = Sample(t, "ui.pointer.row-picture", 350, 645)
  Same(r.status, "pass", tostring(r.detail))
  facts = {}
  for _, f in ipairs(r.facts) do facts[f[1]] = f[2] end
  Same(facts["ui.picture.topmost_relation"], "self"); Same(facts["ui.picture.hovered"], "true")
  Check(Notes(r):find("focus 2 (contains, workshop)", 1, true), "the row is next in the stack: " .. Notes(r))
  -- the child takes the pointer and the row's light goes out: the failure the third pass saw in the simulator
  row:Light(false, 0, 0)
  r = Sample(t, "ui.pointer.row-picture", 350, 645)
  Same(r.status, "fail"); Check(r.detail:find("not marked hovered", 1, true), r.detail)
  -- no OnEnter on the picture
  row:Light(true, 1, 1); row.iconBtn.scripts.OnEnter = nil
  r = Sample(t, "ui.pointer.row-picture", 350, 645)
  Same(r.status, "fail"); Check(r.detail:find("no OnEnter", 1, true) or r.detail:find("not eligible", 1, true), r.detail)
  Same(t.Bound(), 0)
end

---------------------------------------------------------------------------
-- 9. The read-only scan: a window with a planted overlay fails and names it; removed, it passes; a closed window is skipped
---------------------------------------------------------------------------
do
  local t = Setup()
  local S = Scene(t)
  local RN = t.TL.Runner
  local function Scan()
    t.done = nil
    Check(RN.Start({ t.TL.cases["ui.workshop.reach-scan"] }, { cats = { "ui" }, clock = t.Clock, onDone = function(s) t.done = s end }))
    t.Frames(50)
    Check(t.done, "the scan finished")
    return t.Result()
  end
  local facts = function(r) local f = {} for _, x in ipairs(r.facts) do f[x[1]] = x[2] end return f end
  local r = Scan()
  Same(r.status, "pass", tostring(r.detail) .. Notes(r))
  local f = facts(r)
  -- add + three rows' buttons + three pictures + the scrolled-out row and its picture = 9 buttons with a click script; the fourth row is clipped
  Same(f["ui.scan.controls"], "9"); Same(f["ui.scan.reachable"], "7"); Same(f["ui.scan.clipped"], "2"); Same(f["ui.scan.blocked"], "0")
  Same(f["ui.scan.truncated"], "false")
  Same(r.class, "readonly"); Same(r.label, "client")

  local overlay = S.w:Frame{ name = "PlantedOverlay", x = 1000, y = 230, w = 200, h = 60, strata = "DIALOG", mouse = true }
  r = Scan()
  Same(r.status, "fail", "the planted overlay fails the scan"); f = facts(r)
  Same(f["ui.scan.blocked"], "1"); Same(f["ui.scan.reachable"], "6")
  Check(r.detail:find("blocked on", 1, true), r.detail)
  Check(Notes(r):find("blocking frame: PlantedOverlay", 1, true) and Notes(r):find("expected hit point: x 1090 y 258", 1, true), "the blocker and the point: " .. Notes(r))
  overlay:Hide()
  r = Scan(); Same(r.status, "pass", "after removal it passes again")

  S.add:Disable()
  r = Scan(); f = facts(r)
  Same(f["ui.scan.disabled"], "1"); Same(f["ui.scan.controls"], "8"); Same(r.status, "pass", "a disabled button is counted, not flagged")
  S.add:Enable()
  S.ws:Hide()
  r = Scan()
  Same(r.status, "skipped"); Check(r.detail:find("not open", 1, true), tostring(r.detail))
  t.R.Workshop = nil
  r = Scan()
  Same(r.status, "skipped"); Check(r.detail:find("not loaded", 1, true), tostring(r.detail))
  Check(not RN.Active() and not RN.Snapshot().updating)
end

---------------------------------------------------------------------------
-- 10. The API report, and no work when idle
---------------------------------------------------------------------------
do
  local t = Setup()
  local RN = t.TL.Runner
  Check(RN.Start({ t.TL.cases["ui.pointer.api"] }, { cats = { "ui" }, clock = t.Clock, onDone = function(s) t.done = s end }), "the api case starts")
  t.Scene = Scene(t)
  t.Frames(10)
  local r = t.Result()
  local f = {}
  for _, x in ipairs(r.facts) do f[x[1]] = x[2] end
  Same(r.status, "pass", tostring(r.detail))
  Same(f["ui.api.GetMouseFoci"], "function"); Same(f["ui.api.SetOverrideBindingClick"], "function"); Same(f["ui.pointer.key"], "F9")
  local before = t.timers()
  -- idle: nothing is registered, no frame has an OnUpdate, the guided state is empty
  local snap = t.TL.Guided.Snapshot()
  Check(not snap.active and not snap.bound and not snap.proxyShown, "idle: nothing live")
  Same(before, 0)
  Check(not RN.Snapshot().updating)
end

print("PASSED test_testlab_ui")
