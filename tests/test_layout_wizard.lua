dofile(TESTS .. "harness.lua")
dofile(TESTS .. "layouts_mock.lua")
-- Layout packages, Phase 4: the setup wizard (TwichUI_LayoutWizard; docs/layouts/wizard.md), through the real window with
-- stand-in frames (layouts_mock.lua), the real engine (TwichUI_Layouts) and a stand-in EllesmereUI with the real functions'
-- shape. Covers: packaging and loading on demand; the entries (command, Home, Troubleshooting); that nothing opens or loads
-- by itself; compatibility (a missing, old or other-client EllesmereUI, the screen, combat); every step, going back and
-- cancelling; that choices change the preview and the plan together and change nothing in the game; apply with its
-- confirmation; the result before and after a reload the player started, and after one they made themselves; an
-- interrupted install; restore; a failed apply (clean and partial); combat; a stale plan; reopening without new frames or
-- listeners; saved wizard state that is invalid or newer; the artwork. Nothing here is the game: the in-game checks are
-- listed in docs/layouts/wizard.md.

META = { EllesmereUI = { Version = "9.6.8" } }

local failures = 0
local function Check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local Copy, Same, Heard, Says = LM.Copy, LM.Same, LM.Heard, LM.Says

-- the first visible button with this label under frame
local function Find(frame, label)
  if frame.scripts and frame.scripts.OnClick then
    local hit = frame.text == label
    for _, ch in ipairs(frame.children or {}) do if ch.kind == "FontString" and ch.text == label then hit = true end end
    if hit and frame:IsVisible() then return frame end
  end
  for _, ch in ipairs(frame.children or {}) do
    local b = Find(ch, label)
    if b then return b end
  end
end
local function Click(win, label)
  local b = Find(win, label)
  assert(b, "no visible button '" .. label .. "'")
  assert(b.enabled ~= false, "button '" .. label .. "' is disabled")
  b.scripts.OnClick(b)
end
local function Enabled(win, label)
  local b = Find(win, label)
  return b ~= nil and b.enabled ~= false
end
local function Has(win, label) return Find(win, label) ~= nil end

local function Open(c)
  c.SlashCmdList.TWICHUI("layout")
  return c.TwichUILayoutWizard, c.TwichUI.LayoutWizard
end
local function ToReview(win)
  for i = 1, 4 do Click(win, i == 1 and "Start" or "Next") end
end
-- Forward with the Start and Next buttons until the wizard is on `step` (a reopened session has reached only the first)
local function Advance(win, MK, step)
  while MK.Step() < step do Click(win, MK.Step() == 1 and "Start" or "Next") end
end

-- what a test may not see change: everything the game or another addon would keep (the wizard's own remembered picks aside)
local function World(c)
  local tw = Copy(c.TwichUIDB)
  if tw.layouts then tw.layouts.wizard = nil; if next(tw.layouts) == nil then tw.layouts = nil end end
  return { tw = tw, eui = Copy(c.EllesmereUIDB), restore = Copy(c.TwichUIRestoreDB), share = Copy(c.TwichUIShareDB),
    chron = Copy(c.TwichUIChronicleDB) }
end
local function Unchanged(a, b) return Same(a.tw, b.tw) and Same(a.eui, b.eui) and Same(a.restore, b.restore) and Same(a.share, b.share) and Same(a.chron, b.chron) end

---------------------------------------------------------------------------
-- 1. Packaging: the folder, its .toc, its files, the artwork and what the source does not contain
---------------------------------------------------------------------------
do
  local toc = io.open(REPO .. "TwichUI_LayoutWizard/TwichUI_LayoutWizard.toc"):read("*a")
  Check(toc:find("## LoadOnDemand: 1", 1, true), "the wizard is load on demand")
  Check(toc:find("## RequiredDeps: !!!TwichUI, TwichUI_Layouts", 1, true), "and needs the core and the layout engine")
  Check(not toc:find("SavedVariables", 1, true), "it keeps no saved variables of its own")
  local files = LM.TocFiles("TwichUI_LayoutWizard")
  Check(#files == 6 and files[#files]:find("Window.lua", 1, true), "its files, the window last (it says the wizard is ready)")
  for _, f in ipairs(files) do Check(io.open(f), f .. " exists") end
  local core = io.open(REPO .. "!!!TwichUI/!!!TwichUI.toc"):read("*a")
  Check(not core:find("TwichUI_LayoutWizard\\", 1, true) and core:find("LayoutsLauncher.lua", 1, true), "the core lists no file of the wizard")

  -- the source: no broker or minimap button, no Escape handler of the game's, no code loaded from text
  for _, f in ipairs(files) do
    local text = io.open(f):read("*a")
    local name = f:match("([^/]+)$")
    Check(not text:find("LibDBIcon", 1, true) and not text:find("LibDataBroker", 1, true) and not text:find("MinimapButton", 1, true)
      and not text:find("Minimap", 1, true), name .. ": no minimap button or broker")
    Check(not text:find("RegisterGameMenuEscHandler%s*%("), name .. ": never calls the game's Escape handler table")
    Check(not text:find("loadstring", 1, true) and not text:find("[^%w_]load%(") , name .. ": nothing is run from text")
    Check(not text:find("PLAYER_ENTERING_WORLD", 1, true) and not text:find("PLAYER_LOGIN", 1, true), name .. ": no event of its own at login")
  end
end

---------------------------------------------------------------------------
-- 2. Nothing of it runs or loads by itself; the command opens it; the entries; failures are explained
---------------------------------------------------------------------------
local c, S = LM.Boot("Rich")
local R = c.TwichUI
Check(c.wizardLoads == 0 and c.layoutLoads == 0 and R.LayoutWizard == nil and R.Layouts == nil, "at login, neither layout addon is loaded")
Check(c.TwichUILayoutWizard == nil, "no window is made")
Check(R.LayoutsLauncher.WizardResume() == nil, "no resume note")

c.SlashCmdList.TWICHUI("layout plan classic")
Check(c.layoutLoads >= 1 and c.wizardLoads == 0, "the developer command loads the engine and not the wizard")
local win, WZ = Open(c)
Check(c.wizardLoads == 1 and win and win.shown, "/tui layout loads and opens the wizard")
Check(WZ.ready and R.Layouts.ready and WZ.Window.IsShown(), "it says it is ready, and so does the engine it needs")
local M = WZ.Model
local made1 = c.made()
c.SlashCmdList.TWICHUI("layout")
Check(c.wizardLoads == 1 and c.TwichUILayoutWizard == win and c.made() == made1, "typing it again makes nothing new")
Check(R.LayoutsLauncher.Snapshot().wizardLoaded and R.LayoutsLauncher.Snapshot().wizardAttempts == 1, "the troubleshooting snapshot knows")
-- the registered icons
Check(R.Icons.Get("layoutEmblem") and R.Icons.Get("layoutPersonalize") and R.Icons.Get("layoutScreenFit"), "the small pictures are in the icon registry")

-- the entries: Home and Troubleshooting
do
  local ov, ts
  for _, p in ipairs(S.pages) do
    if p.key == "overview" then ov = p elseif p.key == "troubleshooting" then ts = p end
  end
  local function Row(page, name)
    for _, r in ipairs(page.rows) do if r.data and r.data.name == name and r.click then return r end end
  end
  local h = ov and Row(ov, "Layout setup")
  Check(h, "Home has a Layout setup button")
  local t = ts and Row(ts, "Layout setup")
  Check(t, "and so does Troubleshooting")
  local c2, S2 = LM.Boot("Entry")
  local page
  for _, p in ipairs(S2.pages) do if p.key == "overview" then page = p end end
  local row = Row(page, "Layout setup")
  Check(c2.wizardLoads == 0, "building the settings loads nothing")
  row.click()
  Check(c2.TwichUILayoutWizard and c2.TwichUILayoutWizard.shown and c2.wizardLoads == 1, "the Home button opens the wizard")
end

-- failures: missing, turned off, broken; each is said, nothing opens, the core goes on
for _, case in ipairs({ { { wizardMissing = true }, "TwichUI_LayoutWizard, is missing" },
    { { wizardDisabled = true }, "turned off in your AddOns list" }, { { wizardBroken = true }, "loaded but didn't start" },
    { { layoutsMissing = true }, "needs TwichUI Layouts, and a folder is missing" } }) do
  local f = LM.Boot("Fail", nil, case[1])
  f.SlashCmdList.TWICHUI("layout")
  Check(Heard(f, case[2]), "explained: " .. case[2])
  Check(f.TwichUILayoutWizard == nil and f.TwichUI.LayoutsLauncher.Snapshot().wizardFailed ~= nil, "no window, and the reason is kept")
  Check(f.TwichUI:Enabled("chronicle"), "the core is unaffected")
end

-- nothing opens by itself: a new installation, a login with a note left behind, a login with an install waiting
do
  local fresh = LM.Boot("Fresh", nil, {})
  RunLongTimers(60)
  Check(fresh.wizardLoads == 0 and fresh.TwichUILayoutWizard == nil, "a new installation does not open or load it")
  local stale = LM.Boot("Stale", nil, {})
  stale.TwichUIDB.layouts = { wizard = { v = 1, picks = {}, resume = "install" } }
  local sv = LM.Logout(stale)
  local again = LM.Boot("Stale", sv, {})
  RunLongTimers(60)
  Check(again.wizardLoads == 0 and again.TwichUILayoutWizard == nil, "a leftover resume note with nothing waiting opens nothing")
end

---------------------------------------------------------------------------
-- 3. The steps: compatibility, forward and back, cancelling, reopening
---------------------------------------------------------------------------
do
  Check(M.Step() == 1 and Says(win, "Set up TwichUI's interface layout") and Says(win, "Does it work here?"), "the welcome, with its compatibility check")
  Check(Says(win, "Version 9.6.8.") and Says(win, "Everything fits."), "EllesmereUI's version and the screen, read")
  Check(Says(win, "A preview build") and Says(win, "Applying and restoring are refused during combat"), "a preview build is said to be one; combat is explained")
  Check(Enabled(win, "Start") and not Has(win, "Back") and Has(win, "Close"), "Start is offered, Back isn't, Close is")
  Check(not Enabled(win, "2  Layout") and not Enabled(win, "3  Helpers"), "later steps can't be jumped to")
  local before = World(c)

  -- forward, one step at a time, with what each one shows
  Click(win, "Start")
  Check(M.Step() == 2 and Says(win, "Choose a layout") and Says(win, "Classic Adventure") and Says(win, "Preview build"), "the layout")
  Click(win, "Next")
  Check(M.Step() == 3 and Says(win, "Choose TwichUI's helpers") and Says(win, "On-screen helpers") and Says(win, "Helpers and navigation"), "the helpers")
  Click(win, "Next")
  Check(M.Step() == 4 and Says(win, "Make it yours") and Says(win, "Accent colour") and Says(win, "Larger"), "personalize")
  Click(win, "Next")
  Check(M.Step() == 5 and Says(win, "Review before you apply") and Has(win, "Apply") and Has(win, "Back"), "the review, with Apply")
  Check(Says(win, "Nothing has changed yet") and Says(win, "Left alone") and Says(win, "Objectives isn't applied"), "what is left alone and what isn't placed")
  Check(Says(win, "after a reload that you start, for every character on this account"), "the account-wide EllesmereUI change is named")
  Check(Says(win, "is copied as \"Classic Adventure\"") and Says(win, "\"Default\" itself is not changed"), "the TwichUI profile used is named")
  Check(Says(win, "If something goes wrong"), "and what happens on a failure")
  -- back, and the stepper goes anywhere already reached
  Click(win, "Back")
  Check(M.Step() == 4, "Back")
  Click(win, "2  Layout")
  Check(M.Step() == 2, "a reached step can be chosen from the stepper")
  Click(win, "Next"); Click(win, "Next"); Click(win, "Next")
  Check(M.Step() == 5, "and forward again")
  Check(Unchanged(World(c), before) and c.reloads == 0, "walking through the steps changed nothing in the game, and nothing reloaded")

  -- cancelling at every step: close, reopen; the game is as it was and the wizard starts over at the welcome
  for step = 1, 5 do
    Advance(win, M, step)
    Click(win, "Close")
    Check(not win.shown and not M.Active(), "closed at step " .. step .. ", the session ends")
    Check(Unchanged(World(c), before), "nothing changed by closing at step " .. step)
    Open(c)
    Check(win.shown and M.Step() == 1, "reopened at the welcome after step " .. step)
  end
  -- Escape closes it, through the game's own list
  Check(c.PressEsc() and not win.shown, "Escape closes it")
  Check(c.escRegistered == 0, "the game's Escape handler table is never written to (taint)")
  local listed = 0
  for _, n in ipairs(c.UISpecialFrames) do if n == "TwichUILayoutWizard" then listed = listed + 1 end end
  Check(listed == 1, "it is in the list of frames Escape closes, once")
  Open(c)
end

---------------------------------------------------------------------------
-- 4. Compatibility: what a client without the right EllesmereUI is told, and what it can't do
---------------------------------------------------------------------------
do
  local cases = {
    { "no EllesmereUI", { noEUI = true }, "EllesmereUI isn't installed or isn't turned on" },
    { "an old EllesmereUI", { euiVersion = "9.0.0" }, "older than the package needs" },
  }
  for _, case in ipairs(cases) do
    local k = LM.Boot("Compat", nil, case[2])
    local w = Open(k)
    Check(Says(w, case[3]) and Says(w, "Blocked"), case[1] .. ": said, and marked Blocked")
    Check(not Enabled(w, "Start"), case[1] .. ": Start is not offered")
    local MK = k.TwichUI.LayoutWizard.Model
    Check(MK.Next() == 1 and MK.Go(5) == 1, case[1] .. ": the steps can't be entered")
    Check(not k.EllesmereUI or k.EllesmereUI.calls == nil or #k.EllesmereUI.calls == 0, case[1] .. ": EllesmereUI was not called")
  end
  -- an EllesmereUI that isn't the Forever build: a preview package may be tried, and is told it proves nothing
  local k = LM.Boot("Compat", nil, { eui = { retail = true } })
  local w = Open(k)
  Check(Says(w, "isn't the WoW: Forever build") and Enabled(w, "Start"), "another client's EllesmereUI: a warning, not a block, for a preview build")
  -- tested with another version
  local t = LM.Boot("Compat", nil, { euiVersion = "9.7.0" })
  Check(Says(Open(t), "tested with 9.6.8"), "a newer EllesmereUI is allowed with a note")
  -- EllesmereUI's own first-run setup waiting
  local f = LM.Boot("Compat")
  f.EllesmereUI._firstInstallPending = true
  Check(Says(Open(f), "first-run setup is still waiting") and not Enabled(f.TwichUILayoutWizard, "Start"), "EllesmereUI's own setup waiting blocks it, with the reason")
  -- a screen that can't be read
  local s = LM.Boot("Compat")
  local ws = Open(s)
  s.UIParent.w = nil
  s.TwichUI.LayoutWizard.Window.Refresh()
  Check(Says(ws, "couldn't read the size of the screen") and not Enabled(ws, "Start"), "an unreadable screen blocks it")
  s.UIParent.w = 100
  s.TwichUI.LayoutWizard.Window.Refresh()
  Check(Says(ws, "couldn't work out where things would go") and Enabled(ws, "Start"), "a screen too small to work with is said, and the review will explain")
  -- a screen it does not fit (1024 x 768 units): a warning that says which, never a block
  local n = LM.Boot("Narrow", nil, { screen = { w = 1365, h = 768, scale = 1 } })
  local wn = Open(n)
  Check(Says(wn, "Not everything fits") and Enabled(wn, "Start"), "a screen the layout doesn't fit: said, with the overlaps, and not blocked")
  -- combat: said at the welcome
  local b = LM.Boot("Compat")
  b.combat = true
  Check(Says(Open(b), "You are in combat"), "combat is said at the welcome")
end

---------------------------------------------------------------------------
-- 5. Choices change the preview and the plan together, and nothing else
---------------------------------------------------------------------------
do
  local k = LM.Boot("Choices")
  local w, WK = Open(k)
  local MK, WW = WK.Model, WK.Window
  local before = World(k)
  local applies, E = 0, k.E
  local LY = k.TwichUI.Layouts
  local engineApply = LY.Apply
  LY.Apply = function(...) applies = applies + 1 return engineApply(...) end

  -- the preview's proportions are the viewport's, for several screens
  for _, scr in ipairs({ { 2133.33, 1200 }, { 2866.67, 1200 }, { 1920, 1080 }, { 1600, 1200 }, { 4266.67, 1200 } }) do
    k.UIParent.w, k.UIParent.h = scr[1], scr[2]
    MK.Invalidate()
    Click(w, "Start")
    local pv = WW.pages[2].preview
    local d = pv.drawn
    Check(d and math.abs(d.w / d.h - scr[1] / scr[2]) < 0.001, ("the preview of %dx%d has the viewport's proportions"):format(scr[1], scr[2]))
    Check(d.w <= WK.Preview.MAX_W + 0.01 and d.h <= WK.Preview.MAX_H + 0.01, "and fits its place")
    Check(math.abs(pv.frame.w - d.w) < 0.001 and math.abs(pv.frame.h - d.h) < 0.001, "the viewport frame is that size")
    MK.Go(1); WW.Refresh()
  end
  k.UIParent.w, k.UIParent.h = 2133.33, 1200
  MK.Invalidate()
  Click(w, "Start")
  local pv = WW.pages[2].preview
  local geo = MK.Preview()
  for id, box in pairs(pv.drawn.boxes) do
    local r = geo.components[id].rect
    Check(math.abs(box.w / pv.drawn.scale - r.w) < 0.05 and math.abs(box.x / pv.drawn.scale - r.x) < 0.05 and math.abs(box.y / pv.drawn.scale - r.y) < 0.05,
      "the preview's " .. id .. " is the resolved geometry, to scale")
  end
  Check(pv.drawn.boxes.central and pv.drawn.boxes.chat and pv.drawn.boxes.meter and pv.drawn.boxes.minimap, "the managed components are drawn")
  Check(pv.boxes.objectives and Says(w, "Shown, but not applied: Objectives"), "the preview says the objectives are shown but not applied")
  Check(Says(w, "An illustration"), "and the preview says what it is")

  -- size: the preview and the plan agree, and the density reaches the text sizes
  local standardChat = pv.drawn.boxes.chat.w / pv.drawn.scale
  local planStd = MK.Plan()
  local textStd = 0
  for _, row in ipairs(planStd.parts.ellesmereui.rows) do if row.text then textStd = textStd + 1 end end
  Check(planStd.density == "standard" and textStd == 0, "standard: no text sizes scaled")
  Check(MK.SetPick("size", "larger"), "pick Larger")
  WW.Refresh()
  local largerChat = pv.drawn.boxes.chat.w / pv.drawn.scale
  Check(largerChat > standardChat * 1.1, "Larger: the chat box in the preview is bigger (" .. standardChat .. " -> " .. largerChat .. ")")
  local planLg = MK.Plan()
  local textLg = 0
  for _, row in ipairs(planLg.parts.ellesmereui.rows) do if row.text then textLg = textLg + 1 end end
  Check(planLg.density == "larger" and textLg > 0, "Larger: the plan's density is larger and it scales text sizes")
  Check(math.abs(planLg.geometry.components.chat.rect.w - largerChat) < 0.05, "the plan's chat is the preview's chat")
  Check(planStd.key ~= planLg.key, "and the plan's key changed")

  -- accent: the preview's outline, the plan's unit and the payload are one colour
  Check(MK.SetPick("accent", "verdigris"))
  WW.Refresh()
  local border = pv.boxes.chat.border
  Check(border and math.abs(border[1] - 0.36) < 0.001 and math.abs(border[2] - 0.58) < 0.001 and math.abs(border[3] - 0.57) < 0.001, "the preview is outlined in the picked accent")
  local planAcc = MK.Plan()
  local unit = planAcc.parts.ellesmereui.composed.units["ellesmereui:root.euiAccent"]
  Check(unit and unit.useClass == false and unit.custom.r == 0.36 and unit.custom.g == 0.58 and unit.custom.b == 0.57, "the plan's accent unit is that colour")
  local pd = planAcc.parts.ellesmereui.payload.data.euiAccent
  Check(pd and pd.custom.r == 0.36, "and the payload would import it")
  Check(planAcc.key ~= planLg.key, "a new accent is a new key")
  MK.SetPick("accent", "class")
  WW.Refresh()
  local cb = pv.boxes.chat.border
  Check(math.abs(cb[1] - 0.25) < 0.001 and math.abs(cb[3] - 0.92) < 0.001, "the class colour is the player's own")
  Check(MK.Plan().parts.ellesmereui.composed.units["ellesmereui:root.euiAccent"].useClass == true, "and the plan says follow the class")
  MK.SetPick("accent", "gold")

  -- helpers: only switches, only on, and listed
  MK.SetPick("size", "standard")
  local function Switches(plan)
    local out = {}
    for _, row in ipairs(plan.parts.twichui.rows) do
      if row.unit:find("^twichui:modules%.") and row.layer == "preset" then out[row.unit:match("%.(.+)$")] = row.new end
    end
    return out
  end
  local none = Switches(MK.Plan())
  Check(next(none) == nil, "'leave them as they are' turns nothing on or off")
  MK.SetPick("helpers", "on-screen")
  local onScreen = Switches(MK.Plan())
  Check(onScreen.classBars == true and onScreen.markersBar == true and onScreen.foodDrink == true and onScreen.navigation == nil, "on-screen helpers: three switches, on")
  Check(Same(MK.Review().helpers, { "Class resource bars", "Marker bar", "Food and drink buttons" }) or #MK.Review().helpers == 3, "the review lists them")
  MK.SetPick("helpers", "finding-my-way")
  local nav = Switches(MK.Plan())
  Check(nav.navigation == true and nav.classBars == true, "and navigation as well")
  for key, value in pairs(nav) do Check(value == true, key .. " is only ever turned on") end
  -- none of the preset's switches is one that shares, plays a sound or acts for you
  local LOCAL = k.TwichUI.TwichConfig.LOCAL
  for key in pairs(nav) do Check(not LOCAL["modules." .. key], key .. " is a switch the layout may manage (not kept local)") end
  Check(planAcc.key ~= MK.Plan().key, "helpers change the key")
  MK.ResetPicks()
  Check(MK.IsDefault() and MK.Pick("helpers") == "as-is" and MK.Pick("accent") == "gold" and MK.Pick("size") == "standard", "Start over returns the defaults")

  -- deterministic: the same picks, the same key
  local a = MK.Plan(true).key
  local b = MK.Plan(true).key
  Check(a == b, "the same picks give the same plan key")

  -- through all of it, nothing in the game changed and the engine's Apply was never called
  Check(applies == 0 and Unchanged(World(k), before), "choosing, previewing and planning changed nothing and applied nothing")
  Check(E:called("ImportProfileSilent") == 0 and E:called("SwitchProfile") == 0 and E:called("DeleteProfile") == 0 and E:called("EncodePayload") >= 0,
    "EllesmereUI was never asked to import, switch or delete")
  -- an unknown pick is refused
  Check(not MK.SetPick("accent", "neon") and not MK.SetPick("nothing", "x"), "an option or choice the package doesn't have is refused")

  -- the picks are remembered: closing, reopening, and a later session
  MK.SetPick("accent", "ember"); MK.SetPick("size", "larger"); MK.SetPick("helpers", "on-screen")
  WW.Close()
  Open(k)
  Check(MK.Pick("accent") == "ember" and MK.Pick("size") == "larger" and MK.Pick("helpers") == "on-screen", "reopened with the same choices")
  local sv = LM.Logout(k)
  local k2 = LM.Boot("Choices", sv)
  Open(k2)
  local M2 = k2.TwichUI.LayoutWizard.Model
  Check(M2.Pick("accent") == "ember" and M2.Pick("size") == "larger", "and in a later session")
end

---------------------------------------------------------------------------
-- 6. Apply: the confirmation, the result, the reload the player starts, the check after it
---------------------------------------------------------------------------
local savedAfterReload
do
  local k = LM.Boot("Apply")
  local w, WK = Open(k)
  local MK, WW = WK.Model, WK.Window
  local LY = k.TwichUI.Layouts
  MK.SetPick("helpers", "on-screen"); MK.SetPick("accent", "dusk"); MK.SetPick("size", "larger")
  ToReview(w)
  local before = World(k)
  Check(Enabled(w, "Apply") and Says(w, "Accent colour: Dusk blue") and Says(w, "Turned on: Class resource bars, Marker bar, Food and drink buttons"), "the review names the choices and what is turned on")

  -- the confirmation names the exact scope; declining changes nothing
  Click(w, "Apply")
  local q = k.popup
  Check(q and q.key == "TWICHUI_LAYOUT_APPLY", "Apply asks first")
  Check(q.text:find("Apply Classic Adventure?", 1, true) and q.text:find("\"Classic Adventure\"", 1, true) and q.text:find("\"TwichUI Classic\"", 1, true)
    and q.text:find("every character on this account", 1, true) and q.text:find("Nothing reloads by itself", 1, true)
    and q.text:find("Restore puts your previous profiles back", 1, true), "the question names both profiles, the account-wide effect, the reload and the way back")
  k.Decline()
  Check(Unchanged(World(k), before) and M.Active() and MK.Step() == 5, "declining changes nothing and stays on the review")
  Check(k.E:called("ImportProfileSilent") == 0, "EllesmereUI was not asked to import")

  -- accepting
  Click(w, "Apply")
  k.Accept()
  Check(MK.Step() == 6 and Says(w, "Waiting for a reload"), "applied: the result step, waiting for a reload")
  Check(k.reloads == 0, "nothing reloaded by itself")
  local j = LY.Journal.Read()
  Check(j and j.state == "applied" and j.picks.helpers == "on-screen" and j.picks.accent == "dusk" and j.picks.size == "larger", "the record says applied and what was chosen")
  Check(k.EllesmereUIDB.activeProfile == "TwichUI Classic" and k.TwichUI.Profiles.Current() == "Classic Adventure", "both install profiles are in use")
  Check(k.EllesmereUIDB.ppUIScale == 0.8 and Same(k.EllesmereUIDB.profiles.Mine, before.eui.profiles.Mine), "UI scale and the player's own EllesmereUI profile untouched")
  Check(k.TwichUIDB.modules.classBars == true and k.TwichUIDB.modules.markersBar == true and k.TwichUIDB.modules.foodDrink == true and not k.TwichUIDB.modules.navigation,
    "the three helpers are on in the install's TwichUI profile, and navigation is not")
  Check(Says(w, "Accent colour: Dusk blue") and Says(w, "TwichUI: done") and Says(w, "EllesmereUI: done"), "the result lists the choices and each step")
  Check(Enabled(w, "Reload now") and Enabled(w, "Restore previous setup") and not Has(w, "Keep this setup"), "Reload now and Restore, and not 'keep' until it is checked")
  Check(k.E.imported.data.euiAccent.custom.r == 0.47, "the payload carried the picked accent")
  Check(k.E.called("ImportProfileSilent") == 1, "EllesmereUI imported once")

  -- reopening while it waits shows where things are
  WW.Close()
  Open(k)
  Check(MK.Step() == 6 and Says(w, "Waiting for a reload"), "reopened on the result while it waits")

  -- the reload, from the button: it leaves a note, and the result is shown when the game is back
  Click(w, "Reload now")
  Check(k.reloads == 1, "the reload happened once, from the click")
  Check(k.TwichUIDB.layouts.wizard.resume == "install", "and left the note")
  savedAfterReload = LM.Logout(k)
end

do
  -- the game comes back: the engine checks, and the wizard shows the result without being asked
  local k = LM.Boot("Apply", savedAfterReload)
  local LY = k.TwichUI.Layouts
  Check(LY and LY.Journal.Read().state == "verified", "checked after the reload: verified")
  local w = k.TwichUILayoutWizard
  Check(w and w.shown, "the wizard opens on its own, because the player started this reload from it")
  local WK = k.TwichUI.LayoutWizard
  Check(WK.Model.Step() == 6 and Says(w, "Checked after the reload") and Says(w, "reads back as planned"), "showing the result")
  Check(Enabled(w, "Restore previous setup") and Enabled(w, "Keep this setup") and Enabled(w, "Check again") and Has(w, "Set up again"), "the actions that make sense now")
  Check(k.TwichUIDB.layouts.wizard.resume == nil, "the note is used up")
  Check(k.reloads == 0, "and nothing reloaded")
  -- the accent was read back by its value
  local exp = LY.Journal.Read().expect.ellesmereui["ellesmereui:root.euiAccent"]
  Check(exp == "accent:rgb:0.470,0.600,0.800", "the record expects the accent by value (" .. tostring(exp) .. ")")
  -- check again, read only
  local snapshot = World(k)
  Click(w, "Check again")
  Check(Says(w, "Checked just now: every managed value reads back as planned") and Unchanged(World(k), snapshot), "Check again reads and changes nothing")
  -- a changed accent is reported, not repaired
  k.EllesmereUIDB.profiles["TwichUI Classic"].euiAccent = { useClass = true }
  Click(w, "Check again")
  Check(Says(w, "Checked just now: mismatch") and Says(w, "Accent colour"), "an accent changed afterwards is reported")
  Check(k.EllesmereUIDB.profiles["TwichUI Classic"].euiAccent.useClass == true, "and left as the player has it")
  k.EllesmereUIDB.profiles["TwichUI Classic"].euiAccent = LM.Copy(savedAfterReload.EllesmereUIDB.profiles["TwichUI Classic"].euiAccent)

  -- Restore: the plan is shown and asked about; declining does nothing
  local before = World(k)
  Click(w, "Restore previous setup")
  Check(k.popup and k.popup.key == "TWICHUI_LAYOUT_RESTORE" and k.popup.text:find("back to your profile \"Default\"", 1, true)
    and k.popup.text:find("the install's profile \"TwichUI Classic\" is removed", 1, true), "Restore names what it will do")
  k.Decline()
  Check(Unchanged(World(k), before), "declining a restore changes nothing")
  Click(w, "Restore previous setup")
  k.Accept()
  Check(Says(w, "Restore is waiting for a reload") and k.reloads == 0, "restored as far as it can be now; waiting for a reload; nothing reloaded")
  Check(k.TwichUI.Profiles.Current() == "Default" and k.EllesmereUIDB.activeProfile == "Mine" and k.EllesmereUIDB.profiles["TwichUI Classic"] == nil,
    "the profiles are back (the engine's own switch and delete)")
  Click(w, "Reload now")
  Check(k.reloads == 1 and k.TwichUIDB.layouts.wizard.resume == "restore", "the reload for a restore leaves its own note")
  local sv = LM.Logout(k)
  local k2 = LM.Boot("Apply", sv)
  local w2 = k2.TwichUILayoutWizard
  Check(w2 and w2.shown and Says(w2, "Restored") and Says(w2, "back as it was"), "after the reload: restored, shown")
  Check(k2.TwichUIDB.layouts == nil or k2.TwichUIDB.layouts.install == nil, "the record is gone once the restore checked out")
  Check(Has(w2, "Set up again") and not Has(w2, "Restore previous setup"), "and there is nothing left to restore")
  Check(k2.EllesmereUIDB.activeProfile == "Mine" and Same(k2.EllesmereUIDB.profiles.Mine, savedAfterReload.EllesmereUIDB.profiles.Mine), "the player's EllesmereUI profile is as it was")
  Check(k2.TwichUIDB.modules.classBars == nil or k2.TwichUIDB.modules.classBars == false, "and the helpers are off again in the profile in use")
end

do
  -- setting up again on a verified install: with the same choices there is nothing to do; a new accent installs again
  local k = LM.Boot("Apply", savedAfterReload)
  local w, WK = k.TwichUILayoutWizard, k.TwichUI.LayoutWizard
  Check(WK.Model.Step() == 6 and Has(w, "Set up again"), "a verified install, back at the result")
  Click(w, "Set up again")
  Check(WK.Model.Step() == 1, "Set up again starts over")
  Check(WK.Model.Pick("accent") == "dusk" and WK.Model.Pick("size") == "larger" and WK.Model.Pick("helpers") == "on-screen", "with the choices that were remembered")
  Advance(w, WK.Model, 5)
  -- the install's profile is made again from the package (the package is module blobs, so it is always imported whole):
  -- the review says what that replaces
  Check(Enabled(w, "Apply") and Says(w, "is made again from the package and put in use") and Says(w, "Anything you changed in it since the last install is replaced"),
    "the same choices again: the profile is made again, and the review says that changes made in it since are replaced")
  local before = World(k)
  Click(w, "Back"); Click(w, "Back")
  Check(WK.Model.Step() == 3, "back to the helpers")
  WK.Model.SetPick("accent", "ember")
  Advance(w, WK.Model, 5)
  Check(Enabled(w, "Apply") and Says(w, "Accent colour: Ember"), "a new accent can be applied")
  Click(w, "Apply"); k.Accept()
  Check(WK.Model.Step() == 6 and Says(w, "Waiting for a reload") and Says(w, "Accent colour: Ember"), "applied again, waiting for a reload")
  Check(k.TwichUI.Layouts.Journal.Read().picks.accent == "ember", "the record has the new accent")
  Check(Same(k.EllesmereUIDB.profiles.Mine, before.eui.profiles.Mine), "the player's own EllesmereUI profile is still untouched")
  -- the first install's restore point is kept: restoring goes back to before the FIRST install
  local sv = LM.Logout(k)
  local k2 = LM.Boot("Apply", sv)
  Check(k2.TwichUI.Layouts.Journal.Read().state == "verified" and k2.EllesmereUIDB.profiles["TwichUI Classic"].euiAccent.custom.r == 0.8, "checked after the second reload: verified, and the new accent is live")
  local w2 = Open(k2)
  Click(w2, "Restore previous setup"); k2.Accept()
  Check(k2.TwichUI.Profiles.Current() == "Default" and k2.EllesmereUIDB.activeProfile == "Mine", "Restore goes back to before the first install")
end

do
  -- a reload the player made themselves: the engine checks and says so in chat; the wizard stays closed
  local k = LM.Boot("Own")
  local w, WK = Open(k)
  ToReview(w)
  Click(w, "Apply"); k.Accept()
  Check(WK.Model.Step() == 6 and k.reloads == 0, "applied")
  local sv = LM.Logout(k)
  local k2 = LM.Boot("Own", sv)
  Check(k2.TwichUI.Layouts.Journal.Read().state == "verified" and Heard(k2, "checked after the reload"), "checked, and said in chat")
  Check(k2.TwichUILayoutWizard == nil and k2.wizardLoads == 0, "the wizard did not open or load")
  local w2 = Open(k2)
  Check(Says(w2, "Checked after the reload"), "asked for, it shows the result")
  -- keeping the setup forgets the restore point and changes nothing else
  local before = World(k2)
  Click(w2, "Keep this setup")
  Check(k2.popup.key == "TWICHUI_LAYOUT_KEEP", "keeping asks first")
  k2.Accept()
  local after = World(k2)
  Check(k2.TwichUI.Layouts.Journal.Read() == nil and Same(after.eui, before.eui) and Same(after.restore, before.restore), "the record is forgotten and nothing else changed")
  Check(Says(w2, "Nothing is installed") and not Has(w2, "Restore previous setup"), "and Restore is no longer offered")
end

---------------------------------------------------------------------------
-- 7. Interrupted, failed (cleanly and part way), combat, and a plan that went stale
---------------------------------------------------------------------------
do
  -- interrupted: the game stopped between writing the record and finishing
  local k = LM.Boot("Cut")
  local w = Open(k)
  ToReview(w)
  Click(w, "Apply"); k.Accept()
  local LY = k.TwichUI.Layouts
  local j = LY.Journal.Read()
  j.state = "applying"
  LY.Journal.Write(j)
  local sv = LM.Logout(k)
  local k2 = LM.Boot("Cut", sv)
  Check(k2.TwichUI.Layouts.Journal.Read().state == "interrupted", "found at the next load: interrupted")
  local w2, WK2 = Open(k2)
  Check(WK2.Model.Step() == 6 and Says(w2, "An install was interrupted") and Enabled(w2, "Restore previous setup"), "the wizard says so and offers Restore")
  Click(w2, "Restore previous setup"); k2.Accept()
  Check(k2.TwichUI.Profiles.Current() == "Default" and Says(w2, "Restore is waiting for a reload"), "and Restore works")
end

do
  -- a clean failure: EllesmereUI refuses; nothing changed and no record
  local k = LM.Boot("Fail", nil, { eui = { failImport = true } })
  local w, WK = Open(k)
  ToReview(w)
  local before = World(k)
  Click(w, "Apply"); k.Accept()
  Check(WK.Model.Step() == 6 and Says(w, "Nothing was changed") and Says(w, "EllesmereUI refused the import"), "a refused import: said, with the reason")
  Check(Unchanged(World(k), before) and k.TwichUI.Layouts.Journal.Read() == nil, "and nothing changed, with no record left behind")
  Check(Has(w, "Set up again") and not Has(w, "Restore previous setup"), "nothing to restore; it can be tried again")
  Click(w, "Set up again")
  Check(WK.Model.Step() == 1, "Set up again goes back to the start")
end

do
  -- a failure part way: EllesmereUI imported, TwichUI's part fails. Nothing is undone behind the player's back.
  local k = LM.Boot("Part")
  local w = Open(k)
  local LY = k.TwichUI.Layouts
  LY.ADAPTERS.twichui.Apply = function() return { state = "failed", code = "write", rollback = "clean" } end
  ToReview(w)
  Click(w, "Apply"); k.Accept()
  Check(LY.Journal.Read().state == "partial", "the record says partial")
  Check(Says(w, "Only partly applied") and Says(w, "Nothing was undone for you") and Says(w, "EllesmereUI: done") and Says(w, "TwichUI: failed"), "the result says what was done and what failed")
  Check(Enabled(w, "Restore previous setup") and Enabled(w, "Reload now"), "Restore is offered, and the reload for the part that was done")
  Check(k.EllesmereUIDB.activeProfile == "TwichUI Classic", "EllesmereUI's part was not undone by itself")
  Click(w, "Restore previous setup"); k.Accept()
  Check(k.EllesmereUIDB.activeProfile == "Mine" and Says(w, "waiting for a reload"), "Restore puts it back")
end

do
  -- combat: refused in the model, in the window and in the engine; allowed again afterwards
  local k = LM.Boot("Combat")
  local w, WK = Open(k)
  local MK, WW = WK.Model, WK.Window
  local LY = k.TwichUI.Layouts
  ToReview(w)
  Check(Enabled(w, "Apply"), "Apply is available out of combat")
  k.combat = true
  WW.evframe.scripts.OnEvent(WW.evframe, "PLAYER_REGEN_DISABLED")
  Check(not Enabled(w, "Apply") and Says(w, "Not during combat"), "in combat Apply is disabled and says why")
  local before = World(k)
  WW.Actions.apply()
  Check(k.popup == nil, "pressing it anyway asks nothing")
  Check(select(2, MK.Apply("x")) == "combat", "the model refuses")
  local plan = LY.Plan(MK.Layout().pkg, MK.Layout().variant, { picks = MK.Picks() })
  Check(select(2, LY.Apply(MK.Layout().pkg, MK.Layout().variant, plan.key, { picks = MK.Picks() })) == "combat", "and the engine refuses, whoever asks")
  Check(Unchanged(World(k), before), "nothing changed")
  k.combat = false
  WW.evframe.scripts.OnEvent(WW.evframe, "PLAYER_REGEN_ENABLED")
  Check(Enabled(w, "Apply"), "out of combat again, Apply is back")
  -- a reload and a restore are refused in combat too
  Click(w, "Apply"); k.Accept()
  k.combat = true
  WW.evframe.scripts.OnEvent(WW.evframe, "PLAYER_REGEN_DISABLED")
  Check(not Enabled(w, "Reload now") and Says(w, "wait until combat ends"), "the reload isn't offered in combat")
  Check(select(2, MK.Reload()) == "combat" and k.reloads == 0, "and the model refuses it")
  Check(select(2, MK.Restore("x")) == "combat", "Restore is refused in combat")
  k.combat = false
  -- an Apply confirmation answered during combat does nothing
  local k2 = LM.Boot("Combat2")
  local w2 = Open(k2)
  ToReview(w2)
  Click(w2, "Apply")
  k2.combat = true
  local b2 = World(k2)
  k2.Accept()
  Check(Unchanged(World(k2), b2) and k2.TwichUI.Layouts.Journal.Read() == nil, "a question answered after combat began changes nothing")
end

do
  -- stale: the screen changed while the question was open; what was described is not what would happen
  local k = LM.Boot("Stale")
  local w, WK = Open(k)
  ToReview(w)
  local before = World(k)
  -- the model's own rule, apart from the confirmation's check: only the plan that was shown is applied
  local shown = WK.Model.Plan().key
  Check(select(2, WK.Model.Apply(nil)) == "stale" and select(2, WK.Model.Apply("not the key")) == "stale", "no key, or another key, is refused")
  k.UIParent.w = 2000
  Check(select(2, WK.Model.Apply(shown)) == "stale", "a plan shown for another screen is refused by the model")
  k.UIParent.w = 2133.33
  WK.Model.Invalidate()
  Check(Unchanged(World(k), before) and k.E:called("ImportProfileSilent") == 0, "and nothing was applied")
  Click(w, "Apply")
  k.UIParent.w = 1920
  k.Accept()
  Check(Unchanged(World(k), before) and k.E:called("ImportProfileSilent") == 0, "nothing was applied")
  Check(WK.Model.Step() == 5 and Says(w, "changed since it was shown"), "and it says why, staying on the review")
  Check(Enabled(w, "Apply"), "the new review can be applied")
  Click(w, "Apply")
  local fresh = k.popup.text
  Check(fresh ~= nil, "a fresh question")
  k.Accept()
  Check(WK.Model.Step() == 6, "and then it is applied")
end

do
  -- a package target that isn't ours: the review says it can't, with the reason, and Apply is off
  local k = LM.Boot("Taken")
  k.TwichUI.Profiles.Create("Classic Adventure")
  k.TwichUI.Profiles.Switch("Default")
  local w = Open(k)
  ToReview(w)
  Check(Says(w, "Can't apply yet") and Says(w, "profile with the package's name already exists") and not Enabled(w, "Apply"), "a profile of the package's name that isn't ours blocks Apply, with the reason")
end

---------------------------------------------------------------------------
-- 8. Opening again and again: no new frames, no new listeners; the gauges and scopes
---------------------------------------------------------------------------
do
  local k = LM.Boot("Again")
  local spy = {}
  local Perf = k.TwichUI.Perf
  Perf.on = true
  Perf.Start = function(id) spy[id] = (spy[id] or 0) + 1 return id end
  local listeners0 = {}
  k.TwichUI.ListenerCounts(listeners0)
  local w, WK = Open(k)
  local WW, MK = WK.Window, WK.Model
  Check(spy["layoutwizard.load"] == 1 and spy["layoutwizard.build"] == 1, "the load and the build were each scoped once")
  Check(WW.listening == 4 and w.scripts and WW.evframe.events.PLAYER_REGEN_DISABLED and WW.evframe.events.DISPLAY_SIZE_CHANGED, "four events are registered while it is open")
  -- every page once
  for step = 1, 4 do Click(w, step == 1 and "Start" or "Next") end
  local gaugeIds = {}
  for _, g in ipairs(Perf.gauges) do gaugeIds[g.id] = g end
  Check(gaugeIds["layoutwizard.events"] and gaugeIds["layoutwizard.events"].read() == 4 and gaugeIds["layoutwizard.frames"], "the gauges are registered and read")
  Click(w, "Apply")
  k.Decline()
  MK.Go(1); WW.Refresh()
  local made, frames, previewBoxes = k.made(), WW.frames, 0
  for _ in pairs(WW.pages[2].preview.boxes) do previewBoxes = previewBoxes + 1 end
  for round = 1, 6 do
    WW.Close()
    Check(WW.listening == 0 and next(WW.evframe.events) == nil and gaugeIds["layoutwizard.events"].read() == 0, "closed: no events registered (round " .. round .. ")")
    Check(not MK.Active() and not MK.Session(), "closed: the session and what it worked out are gone (round " .. round .. ")")
    Open(k)
    Advance(w, MK, 5)
    for step = 4, 1, -1 do MK.Go(step); WW.Refresh() end
  end
  Check(k.made() == made and WW.frames == frames, "opening, closing and visiting every step six times made no new frames (" .. made .. " -> " .. k.made() .. ")")
  local after = 0
  for _ in pairs(WW.pages[2].preview.boxes) do after = after + 1 end
  Check(after == previewBoxes, "and no new preview boxes")
  Check(WW.builds == 1 and spy["layoutwizard.build"] == 1, "the window was built once")
  Check((spy["layoutwizard.preview"] or 0) >= 6, "the preview's drawing is scoped")
  local listeners1 = {}
  k.TwichUI.ListenerCounts(listeners1)
  Check(Same(listeners0, listeners1), "the core's event listeners are exactly as before")
  Check(#w.hooks.OnShow == 3 and #w.hooks.OnHide == 2, "the window's hooks are installed once: OnShow " .. #w.hooks.OnShow .. ", OnHide " .. #w.hooks.OnHide)
  -- the screen changing while open: what was worked out is dropped, the plan follows the new screen
  MK.Go(5); WW.Refresh()
  local key1 = MK.Plan().key
  k.UIParent.w, k.UIParent.h = 1920, 1080
  WW.evframe.scripts.OnEvent(WW.evframe, "DISPLAY_SIZE_CHANGED")
  Check(MK.Plan().key ~= key1 and WW.pages[2].preview.drawn and math.abs(WW.pages[2].preview.drawn.aspect - 1920 / 1080) < 0.001, "a new screen gives a new plan and a new preview")
  -- an event while closed does nothing
  WW.Close()
  WW.evframe.scripts.OnEvent(WW.evframe, "UI_SCALE_CHANGED")
  Check(not MK.Active(), "an event after closing does nothing")
  Perf.on = false
end

---------------------------------------------------------------------------
-- 9. Saved wizard state: invalid, repaired narrowly, newer left alone; and a damaged install record
---------------------------------------------------------------------------
do
  local function Boot1() return LM.Boot("Saved") end
  -- not a table
  local a = Boot1()
  a.TwichUIDB.layouts = { wizard = "junk" }
  local w, WK = Open(a)
  Check(w.shown and WK.Model.Pick("accent") == "gold" and WK.Model.Pick("size") == "standard" and WK.Model.Pick("helpers") == "as-is", "state that isn't a table: the defaults")
  Check(a.TwichUIDB.layouts.wizard == "junk", "and reading it wrote nothing")
  -- a picked option that doesn't exist, an unknown choice, wrong types; the valid pick is kept
  local b = Boot1()
  b.TwichUIDB.layouts = { wizard = { v = 1, picks = { accent = "neon", size = "larger", bogus = "z", helpers = 5 }, resume = "maybe" } }
  local copy = Copy(b.TwichUIDB.layouts.wizard)
  local _, WKb = Open(b)
  Check(WKb.Model.Pick("accent") == "gold" and WKb.Model.Pick("size") == "larger" and WKb.Model.Pick("helpers") == "as-is", "an invalid pick goes back to its default; the valid one stays")
  Check(Same(b.TwichUIDB.layouts.wizard, copy), "reading wrote nothing")
  Check(WKb.Model.Step() == 1 and b.wizardLoads == 1, "and it opened normally")
  WKb.Model.SetPick("accent", "ember")
  local saved = b.TwichUIDB.layouts.wizard
  Check(saved.v == 1 and saved.picks.accent == "ember" and saved.picks.size == "larger" and saved.picks.bogus == nil and saved.picks.helpers == "as-is" and saved.resume == nil,
    "a pick then saves a clean state")
  -- other junk
  for _, junk in ipairs({ { v = "x" }, { v = 0 }, { v = 1.5 }, { v = 1, picks = "no" }, { picks = { accent = "dusk" } }, {}, { v = 1, picks = { accent = {} } } }) do
    local k = Boot1()
    k.TwichUIDB.layouts = { wizard = junk }
    local _, WKk = Open(k)
    Check(WKk.Model.Pick("accent") ~= nil and WKk.Model.Pick("size") == "standard", "junk state opens with usable picks")
  end
  -- newer: understood by nobody here, and never overwritten
  local n = Boot1()
  n.TwichUIDB.layouts = { wizard = { v = 99, picks = { size = "larger" }, extra = true } }
  local newer = Copy(n.TwichUIDB.layouts.wizard)
  local _, WKn = Open(n)
  Check(WKn.Model.Pick("size") == "standard", "a newer state is not used")
  WKn.Model.SetPick("accent", "dusk")
  Check(Same(n.TwichUIDB.layouts.wizard, newer), "and a pick doesn't overwrite it")
  -- a resume note for a restore, with no record: shows "Restored" once
  local r = Boot1()
  r.TwichUIDB.layouts = { wizard = { v = 1, picks = {}, resume = "restore" } }
  local wr, WKr = Open(r)
  Check(WKr.Model.Step() == 6 and Says(wr, "Restored"), "a restore note with no record shows the restored result")
  Check(r.TwichUIDB.layouts.wizard.resume == nil, "and uses the note up")

  -- a damaged install record
  local d = Boot1()
  d.TwichUIDB.layouts = { install = "junk", wizard = { v = 1, picks = { accent = "dusk" } } }
  local wd, WKd = Open(d)
  Check(WKd.Model.Step() == 6 and Says(wd, "The install record can't be read") and Enabled(wd, "Forget the record") and not Has(wd, "Restore previous setup"), "a damaged install record: said, and only Forget is offered")
  Check(d.TwichUIDB.layouts.install == "junk", "reading it changed nothing")
  Click(wd, "Forget the record")
  Check(d.popup.key == "TWICHUI_LAYOUT_FORGET", "forgetting asks first")
  d.Accept()
  Check(d.TwichUIDB.layouts.install == nil and d.TwichUIDB.layouts.wizard.picks.accent == "dusk", "the record is forgotten; the remembered picks stay")
  -- a newer install record
  local nr = Boot1()
  nr.TwichUIDB.layouts = { install = { v = 99 } }
  local wnr = Open(nr)
  Check(Says(wnr, "written by a newer TwichUI") and not Has(wnr, "Restore previous setup") and not Has(wnr, "Forget the record"), "a newer install record: said, and nothing is offered")
  Check(Same(nr.TwichUIDB.layouts.install, { v = 99 }), "and it is left exactly as it was")
  -- an install made on another character
  local oc = LM.Boot("Mine")
  local wo0 = Open(oc)
  ToReview(wo0)
  Click(wo0, "Apply"); oc.Accept()
  local sv = LM.Logout(oc)
  local other = LM.Boot("Someone", sv)
  local wother = Open(other)
  Check(Says(wother, "made on another character") and not Has(wother, "Restore previous setup"), "an install made on another character can't be checked or restored from here")
end

---------------------------------------------------------------------------
-- 10. Artwork: built from the sources, registered, and never needed
---------------------------------------------------------------------------
do
  local k = LM.Boot("Art")
  local _, WK = Open(k)
  local Art = WK.Art
  local function TGA(name)
    local f = io.open(REPO .. "TwichUI_LayoutWizard/media/" .. name .. ".tga", "rb")
    if not f then return nil end
    local d = f:read("*a"); f:close()
    local typ, bpp, desc = d:byte(3), d:byte(17), d:byte(18)
    local width, height = d:byte(13) + d:byte(14) * 256, d:byte(15) + d:byte(16) * 256
    return { type = typ, bpp = bpp, desc = desc, w = width, h = height, size = #d }
  end
  for id, e in pairs(Art.FILES) do
    local file = e.file:match("([^\\]+)$")
    local t = TGA(file)
    Check(t and t.type == 2 and t.bpp == 32 and t.desc == 8 and t.w == e.w and t.h == e.h and t.size == 18 + e.w * e.h * 4, id .. ": a 32-bit uncompressed TGA of the registered size")
    Check(e.w % 2 == 0 and math.floor(math.log(e.w) / math.log(2) + 0.0001) == math.log(e.w) / math.log(2) or e.w == 512 or e.w == 128, id .. ": a power-of-two width")
  end
  Check(Art.Has("emblem") and Art.Has("classic") and Art.Has("personalize") and Art.Has("screenFit"), "the four pictures that exist")
  Check(not Art.Has("compact") and Art.RESERVED.compact and #Art.Missing() == 1 and Art.Missing()[1].id == "compact", "Compact Adventure's is reserved, and reported as missing, not made up")
  Check(io.open(REPO .. "TwichUI_LayoutWizard/media/compact.tga") == nil, "and no file for it is shipped")
  for _, f in ipairs({ "layout-wizard-emblem-source.png", "layout-wizard-classic-source.png", "layout-wizard-personalize-screenfit-source.png", "layout-wizard-compact-source.png" }) do
    Check(io.open(REPO .. "assets/" .. f), "the source " .. f .. " is kept in assets/")
  end
  local dummy = k.CreateFrame("Frame"):CreateTexture()
  Check(Art.Apply(dummy, "nope") == false and dummy.shown == false, "an unknown picture hides its texture and says so")

  -- the game refusing every file (or the files missing): the wizard still works, start to finish
  local r = LM.Boot("NoArt", nil, { refuseTextures = function(path) return tostring(path):find("TwichUI_LayoutWizard", 1, true) ~= nil end })
  local wr, WKr = Open(r)
  Check(wr.shown and Says(wr, "Set up TwichUI's interface layout"), "with every picture refused, the welcome still draws")
  ToReview(wr)
  Check(WKr.Model.Step() == 5 and Says(wr, "Review before you apply") and Enabled(wr, "Apply"), "and so does the review")
  Click(wr, "Apply"); r.Accept()
  Check(r.TwichUI.Layouts.Journal.Read().state == "applied", "and an install made without any picture works")
  local layoutCard = WKr.Window.pages[2].card
  Check(layoutCard.hasPic == false and not layoutCard.pic.shown, "Classic Adventure's picture is simply left out")
end

---------------------------------------------------------------------------
-- 11. What the model never does by itself
---------------------------------------------------------------------------
do
  local k = LM.Boot("Calls")
  local LY
  local w, WK = Open(k)
  LY = k.TwichUI.Layouts
  local calls = { Apply = 0, Restore = 0, Detach = 0 }
  for name in pairs(calls) do
    local fn = LY[name]
    LY[name] = function(...) calls[name] = calls[name] + 1 return fn(...) end
  end
  local reloads = 0
  k.ReloadUI = function() reloads = reloads + 1 end
  for _ = 1, 3 do
    Advance(w, WK.Model, 5)
    for step = 4, 1, -1 do WK.Model.Go(step); WK.Window.Refresh() end
    WK.Model.SetPick("accent", "dusk"); WK.Model.SetPick("accent", "gold")
    WK.Model.Plan(true); WK.Model.Review(); WK.Model.Result(); WK.Model.Compat(); WK.Model.Preview()
    WK.Window.Close()
    Open(k)
  end
  Check(calls.Apply == 0 and calls.Restore == 0 and calls.Detach == 0 and reloads == 0, "visiting, choosing, planning and reviewing apply, restore, forget and reload nothing")
end

if failures > 0 then error(failures .. " check(s) failed") end
print("LAYOUT WIZARD TEST PASSED")
