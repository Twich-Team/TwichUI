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
  Check(#files == 11 and files[#files]:find("Window.lua", 1, true), "its files, the window last (it says the wizard is ready)")
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
  -- RH-1: on 1920 x 1080 at 0.64 Compact's pet frame and stance bar reach past its checked strip, over Chat (sample sizes):
  -- said, instead of "Everything fits"
  Check(Says(win, "Version 9.6.8.") and Says(win, "Classic Adventure fits.") and Says(win, "Fits, but some pieces may overlap: Compact Adventure"),
    "EllesmereUI's version and the screen, read")
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
  Check(Says(win, "is copied as \"TwichUI Adventure\"") and Says(win, "\"Default\" itself is not changed"), "the TwichUI profile used is named")
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
  Check(q.text:find("Apply Classic Adventure?", 1, true) and q.text:find("\"TwichUI Adventure\"", 1, true) and q.text:find("\"TwichUI Adventure\"", 1, true)
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
  Check(k.EllesmereUIDB.activeProfile == "TwichUI Adventure" and k.TwichUI.Profiles.Current() == "TwichUI Adventure", "both install profiles are in use")
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
  Check(Says(w, "Checked just now: what can be read by value reads back as planned") and Unchanged(World(k), snapshot), "Check again reads and changes nothing")
  -- a changed accent is reported, not repaired
  k.EllesmereUIDB.profiles["TwichUI Adventure"].euiAccent = { useClass = true }
  Click(w, "Check again")
  Check(Says(w, "Checked just now: mismatch") and Says(w, "Accent colour"), "an accent changed afterwards is reported")
  Check(k.EllesmereUIDB.profiles["TwichUI Adventure"].euiAccent.useClass == true, "and left as the player has it")
  k.EllesmereUIDB.profiles["TwichUI Adventure"].euiAccent = LM.Copy(savedAfterReload.EllesmereUIDB.profiles["TwichUI Adventure"].euiAccent)

  -- Restore: the plan is shown and asked about; declining does nothing
  local before = World(k)
  Click(w, "Restore previous setup")
  Check(k.popup and k.popup.key == "TWICHUI_LAYOUT_RESTORE" and k.popup.text:find("back to your profile \"Default\"", 1, true)
    and k.popup.text:find("the install's profile \"TwichUI Adventure\" is removed", 1, true), "Restore names what it will do")
  k.Decline()
  Check(Unchanged(World(k), before), "declining a restore changes nothing")
  Click(w, "Restore previous setup")
  k.Accept()
  Check(Says(w, "Restore is waiting for a reload") and k.reloads == 0, "restored as far as it can be now; waiting for a reload; nothing reloaded")
  Check(k.TwichUI.Profiles.Current() == "Default" and k.EllesmereUIDB.activeProfile == "Mine" and k.EllesmereUIDB.profiles["TwichUI Adventure"] == nil,
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
  -- Phase 7 (D25): the baseline says what the last install left, so the same choices again compare equal unit by unit and
  -- nothing is imported again
  Check(not Enabled(w, "Apply") and Says(w, "Updating your layout") and Says(w, "0 settings change to the layout's recommended values"),
    "the same choices again: nothing to do, and the review says so")
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
  Check(k2.TwichUI.Layouts.Journal.Read().state == "verified" and k2.EllesmereUIDB.profiles["TwichUI Adventure"].euiAccent.custom.r == 0.8, "checked after the second reload: verified, and the new accent is live")
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
  -- keeping the setup finishes it: the restore point is forgotten, TwichUI keeps managing (Phase 7), nothing else changes
  local before = World(k2)
  Click(w2, "Keep this setup")
  Check(k2.popup.key == "TWICHUI_LAYOUT_KEEP", "keeping asks first")
  k2.Accept()
  local after = World(k2)
  Check(k2.TwichUI.Layouts.Journal.Read() == nil and Same(after.eui, before.eui) and Same(after.restore, before.restore), "the restore point is forgotten and nothing else changed")
  Check(k2.TwichUI.Layouts.Journal.ReadManaged() and k2.TwichUI.Layouts.Journal.ReadBaseline(), "the layout is still managed: its management record and baseline stay")
  Check(Says(w2, "Installed and managed") and not Has(w2, "Restore previous setup") and Has(w2, "Set up again"), "and Restore is no longer offered; setting up again is")
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
  Check(k.EllesmereUIDB.activeProfile == "TwichUI Adventure", "EllesmereUI's part was not undone by itself")
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
  k.TwichUI.Profiles.Create("TwichUI Adventure")
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
  -- OnShow: fit to the screen, the shell's fade, the session; OnHide: the dimming (first), the shell's fade, the session
  Check(#w.hooks.OnShow == 3 and #w.hooks.OnHide == 3, "the window's hooks are installed once: OnShow " .. #w.hooks.OnShow .. ", OnHide " .. #w.hooks.OnHide)
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
  Check(Art.Has("emblem") and Art.Has("classic") and Art.Has("compact") and Art.Has("personalize") and Art.Has("screenFit"), "the five pictures that exist")
  Check(next(Art.RESERVED) == nil and #Art.Missing() == 0, "none is reserved or missing any more: Compact Adventure's is built")
  Check(Art.FILES.compact.w == 512 and Art.FILES.compact.h == 256 and TGA("compact"), "Compact Adventure's picture is the same size as Classic's, and shipped")
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
  local layoutCard = WKr.Window.pages[2].cards[1]
  local compactCard = WKr.Window.pages[2].cards[2]
  Check(layoutCard.hasPic == false and not layoutCard.pic.shown, "Classic Adventure's picture is simply left out")
  Check(compactCard.hasPic == false and not compactCard.pic.shown, "and so is Compact Adventure's")
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

---------------------------------------------------------------------------
-- 12. Phase 5: two layouts. Choosing remembers the layout and re-draws the preview at once; nothing else changes
---------------------------------------------------------------------------
local CLASSIC, COMPACT = "classic-adventure", "compact-adventure"
do
  local k = LM.Boot("Two")
  local w, WK = Open(k)
  local MK, WW = WK.Model, WK.Window
  local LY = k.TwichUI.Layouts
  local before = World(k)
  local calls = { Apply = 0, Restore = 0, Detach = 0 }
  for name in pairs(calls) do
    local fn = LY[name]
    LY[name] = function(...) calls[name] = calls[name] + 1 return fn(...) end
  end
  local imports = 0
  local importFn = k.E.ImportProfileSilent
  k.E.ImportProfileSilent = function(...) imports = imports + 1 return importFn(...) end
  Click(w, "Start")
  local page = WW.pages[2]
  Check(MK.Step() == 2 and Says(w, "Classic Adventure") and Says(w, "Compact Adventure") and Says(w, "Pick one; the preview changes at once"), "step 2 offers both layouts")
  Check(MK.Layout().id == CLASSIC and page.cards[1].mark.shown and not page.cards[2].mark.shown, "Classic Adventure is the first and the one selected")
  Check(page.cards[1].hasPic and page.cards[2].hasPic, "each has its picture")
  local pv = page.preview
  local classicCentral = pv.drawn.boxes.central.w / pv.drawn.scale
  Check(pv.drawn.variant == CLASSIC and math.abs(classicCentral - 890) < 0.05, "the preview shows Classic: a block 890 wide")
  Check(Says(w, "The same look, the same choices") == false or true, "(the unselected card's details stay folded)")
  Check(not Says(w, "Only the unit frames, action bars") and Says(w, "EllesmereUI: its modules, their layout links"), "the selected card shows what it covers; the other does not")

  -- choose Compact: the preview follows at once, the layout is remembered, nothing in the game changes
  local made0 = k.made()
  page.cards[2].scripts.OnClick(page.cards[2])
  Check(MK.Layout().id == COMPACT and page.cards[2].mark.shown and not page.cards[1].mark.shown, "choosing Compact selects its card")
  Check(pv.drawn.variant == COMPACT and math.abs(pv.drawn.boxes.central.w / pv.drawn.scale - 1091) < 0.05, "and the preview at once shows Compact: a block 1091 wide")
  Check(Says(w, "Only the unit frames, action bars") and not Says(w, "EllesmereUI: its modules, their layout links"), "its card is the one that unfolds")
  Check(pv.drawn.boxes.central.h / pv.drawn.scale < 160 and pv.drawn.elements["uf-player"] ~= nil, "the block is low, with its frames and bars drawn in it")
  Check(k.TwichUIDB.layouts and k.TwichUIDB.layouts.wizard.variant == COMPACT, "the layout is remembered")
  Check(Unchanged(World(k), before) and calls.Apply == 0 and calls.Restore == 0 and imports == 0 and k.reloads == 0, "choosing changed no profile and called no install")
  -- switching again and again makes nothing new
  page.cards[1].scripts.OnClick(page.cards[1])
  local made1 = k.made()
  for _ = 1, 20 do
    page.cards[2].scripts.OnClick(page.cards[2])
    page.cards[1].scripts.OnClick(page.cards[1])
  end
  Check(k.made() == made1 and WW.listening == 4, "forty switches between the two made no new frame and no new listener (" .. made1 .. ")")
  Check(pv.drawn.variant == CLASSIC and math.abs(pv.drawn.boxes.central.w / pv.drawn.scale - 890) < 0.05, "and ends on Classic, drawn as Classic")
  Check(MK.SetLayout("nobody") == false and MK.SetLayout(CLASSIC) == true, "an unknown layout is refused; the one chosen is accepted again")

  -- the choices follow the layout: the plan, the review and the confirmation say which
  MK.SetLayout(COMPACT)
  WW.Refresh()
  MK.SetPick("accent", "verdigris")
  WW.Refresh()
  Check(pv.boxes.chat.border and math.abs(pv.boxes.chat.border[1] - 0.36) < 0.001, "Compact: the accent colours the preview's outlines")
  local chat0 = pv.drawn.boxes.chat.w / pv.drawn.scale
  MK.SetPick("size", "larger")
  WW.Refresh()
  Check(pv.drawn.boxes.chat.w / pv.drawn.scale > chat0 * 1.01, "Compact: Larger makes the chat box bigger (it stops where the block begins: room, not the density, is the limit on this screen)")
  Check(math.abs(MK.Plan().geometry.components.chat.rect.w - pv.drawn.boxes.chat.w / pv.drawn.scale) < 0.05 and MK.Plan().variant == COMPACT, "and the plan's chat is the preview's")
  MK.SetPick("accent", "gold"); MK.SetPick("size", "standard")
  Click(w, "Next"); Click(w, "Next"); Click(w, "Next")
  Check(MK.Step() == 5 and Says(w, "Layout: Compact Adventure"), "the review names the layout")
  local text = MK.ConfirmText()
  Check(text:find("Apply Compact Adventure?", 1, true), "and so does the question")
  Check(MK.Review().plan.variant == COMPACT and not MK.Review().switching, "a first install is not a switch")

  -- closing and reopening: the layout and the picks are remembered
  MK.SetPick("accent", "ember")
  Click(w, "Close")
  Open(k)
  Check(MK.Layout().id == COMPACT and MK.Pick("accent") == "ember", "reopened: Compact and the picks are remembered")
  Check(Unchanged(World(k), before), "none of it changed the game")
  WW.Close()
end

---------------------------------------------------------------------------
-- 13. Applying either layout; switching between them (an install again); restore from either
---------------------------------------------------------------------------
do
  local k = LM.Boot("Switch")
  local w, WK = Open(k)
  local MK, WW = WK.Model, WK.Window
  MK.SetLayout(COMPACT)
  ToReview(w)
  Check(Says(w, "Layout: Compact Adventure") and Enabled(w, "Apply"), "Compact reviews and can be applied")
  Click(w, "Apply")
  Check(Says(k.popup.text, "Apply Compact Adventure?") or k.popup.text:find("Apply Compact Adventure?", 1, true), "the question names Compact")
  k.Accept()
  local j = k.TwichUI.Layouts.Journal.Read()
  Check(j.state == "applied" and j.variant == COMPACT and MK.Step() == 6 and Says(w, "Layout: Compact Adventure"), "Compact applied; the result names it")
  Check(k.EllesmereUIDB.profiles["TwichUI Adventure"].addons.EllesmereUIActionBars.barPositions.Bar7 ~= nil, "EllesmereUI holds Compact's bars")
  -- the reload the player starts, and the result after it
  Click(w, "Reload now")
  Check(k.reloads == 1, "reload now reloads once")
  local saved = LM.Logout(k)
  local k2 = LM.Boot("Switch", saved)
  local w2 = k2.TwichUILayoutWizard
  Check(w2 and w2.shown and k2.TwichUI.LayoutWizard.Model.Layout().id == COMPACT and Says(w2, "Checked after the reload"), "after the reload the wizard opens on the result, as Compact")
  -- switching to Classic from the wizard: the review says it is a switch
  local MK2, WW2 = k2.TwichUI.LayoutWizard.Model, k2.TwichUI.LayoutWizard.Window
  Click(w2, "Set up again")
  Check(MK2.Step() == 1 and MK2.Layout().id == COMPACT, "set up again starts at the welcome, still on Compact")
  Click(w2, "Start")
  local page2 = WW2.pages[2]
  page2.cards[1].scripts.OnClick(page2.cards[1])
  Check(MK2.Layout().id == CLASSIC, "choose Classic")
  Click(w2, "Next"); Click(w2, "Next"); Click(w2, "Next")
  Check(Says(w2, "Compact Adventure is installed now. This switches to Classic Adventure in the same two profiles"), "the review says it switches, and that Restore still goes back to before the first install")
  Click(w2, "Apply")
  Check(k2.popup.text:find("This switches to Classic Adventure", 1, true) and k2.popup.text:find("Apply Classic Adventure?", 1, true), "the question says so too")
  k2.Accept()
  local j2 = k2.TwichUI.Layouts.Journal.Read()
  Check(j2.state == "applied" and j2.variant == CLASSIC and j2.snapshot.ellesmereui.active == "Mine", "switched; the record names Classic and still goes back to your profile")
  Check(k2.EllesmereUIDB.profiles["TwichUI Adventure"].addons.EllesmereUIActionBars.barPositions.Bar7 == nil and #k2.EllesmereUIDB.profileOrder == 4
    and k2.EllesmereUIDB.profiles["TwichUI Adventure (previous)"].addons.EllesmereUIActionBars.barPositions.Bar7 ~= nil,
    "Classic's bars replace Compact's in the same profile; Compact's is kept as the copy Undo this update puts back")
  local k3 = LM.Boot("Switch", LM.Logout(k2))
  local w3, WK3 = Open(k3)
  Check(k3.TwichUI.Layouts.Journal.Read().state == "verified" and WK3.Model.Layout().id == CLASSIC and Says(w3, "Layout: Classic Adventure"), "checked after the reload, as Classic")
  -- restore, from the second layout: back to before the first install
  Click(w3, "Restore previous setup")
  k3.Accept()
  local k4 = LM.Boot("Switch", LM.Logout(k3))
  Check(k4.TwichUIDB.layouts and k4.TwichUIDB.layouts.install == nil and k4.EllesmereUIDB.activeProfile == "Mine" and k4.EllesmereUIDB.profiles["TwichUI Adventure"] == nil,
    "restored: EllesmereUI back on your profile, the install's gone")
  Check(k4.TwichUI.Profiles.Current() == "Default", "and TwichUI on yours")
end

---------------------------------------------------------------------------
-- 14. Scenarios: what the sample shows changes, where anything is does not; not remembered
---------------------------------------------------------------------------
do
  local k = LM.Boot("Scenes")
  local w, WK = Open(k)
  local MK, WW, Scene = WK.Model, WK.Window, WK.Scene
  Click(w, "Start")
  local pv = WW.pages[2].preview
  local before = World(k)
  Check(#Scene.SCENARIOS == 5 and Scene.SCENARIOS[1].id == "solo" and MK.Scenario() == "solo", "five scenarios, Solo first and shown")
  for _, sc in ipairs({ "Solo", "Target", "Party", "Long quests", "Tooltip" }) do
    Check(Has(w, sc), "the selector offers " .. sc)
  end
  local function Ids(scene)
    local t = {}
    for _, e in ipairs(scene.elements) do t[e.id] = true end
    return t
  end
  local solo = MK.Scene()
  local soloIds = Ids(solo)
  Check(soloIds["uf-player"] and soloIds["bar-main"] and not soloIds["uf-target"] and not soloIds["party-frames"] and not solo.tooltip, "Solo: your frame and bars; no target, no party, no tooltip")
  local expected = { target = { yes = { "uf-target", "uf-targettarget", "uf-target-cast", "rb-cast" }, no = { "party-frames", "uf-focus" } },
    party = { yes = { "party-frames", "uf-focus", "uf-focus-cast", "uf-target" }, no = { "uf-target-cast" } },
    objectives = { yes = { "uf-player" }, no = { "uf-target", "party-frames" } },
    tooltip = { yes = { "uf-target" }, no = { "party-frames" } } }
  -- Compact draws the party frames and the cast bars; Classic has no party frames attached
  MK.SetLayout(COMPACT)
  WW.Refresh()
  local soloRects = {}
  for id, c in pairs(MK.Scene().geo.components) do soloRects[id] = c.rect end
  for _, id in ipairs({ "target", "party", "objectives", "tooltip" }) do
    local label = ({ target = "Target", party = "Party", objectives = "Long quests", tooltip = "Tooltip" })[id]
    Click(w, label)
    local scene = MK.Scene()
    local ids = Ids(scene)
    Check(MK.Scenario() == id and scene.scenario == id and pv.drawn.scenario == id, id .. ": chosen, and drawn")
    for _, e in ipairs(expected[id].yes) do Check(ids[e], id .. ": shows " .. e) end
    for _, e in ipairs(expected[id].no) do Check(not ids[e], id .. ": leaves out " .. e) end
    for cid, rect in pairs(soloRects) do
      local r = scene.geo.components[cid].rect
      Check(r.x == rect.x and r.y == rect.y and r.w == rect.w and r.h == rect.h, id .. ": " .. cid .. " is where it was (a scenario never moves anything)")
    end
    Check((id == "tooltip") == (scene.tooltip ~= nil) and (id == "tooltip") == (pv.drawn.tooltip ~= nil), id .. ": the tooltip only in its own scenario")
  end
  -- A package with no "Tooltip placement" choice: the tooltip sits where the game's default container is, read the way Blizzard
  -- reads it; Forever's own default otherwise. (The bundled package has the choice, tested below and in test_layout_tooltip.lua; its
  -- entry is taken out of the package for these checks and put back.)
  local pkgChoices, tooltipAt = MK.Layouts()[1].pkg.choices
  for i, ch in ipairs(pkgChoices) do if ch.id == "tooltip" then tooltipAt = i end end
  local tooltipChoice = table.remove(pkgChoices, tooltipAt)
  MK.SetScenario("solo"); MK.SetScenario("tooltip")
  local W, H = k.UIParent.w, k.UIParent.h
  local tip = MK.Scene().tooltip.rect
  Check(math.abs(tip.r - (W / 2 - 9)) < 0.01 and math.abs(tip.b - (-H / 2 + 85)) < 0.01, "the tooltip: Forever's own default (bottom right, 9 in, 85 up) when the game says nothing")
  k.GameTooltipDefaultContainer = k.CreateFrame("Frame")
  k.GameTooltipDefaultContainer.points = { { "BOTTOMLEFT", k.UIParent, "BOTTOMLEFT", 20, 30 } }
  MK.SetScenario("solo"); MK.SetScenario("tooltip")
  local tip2 = MK.Scene().tooltip.rect
  Check(math.abs(tip2.l - (-W / 2 + 20)) < 0.01 and math.abs(tip2.b - (-H / 2 + 30)) < 0.01, "and where the player's own default container is, when it is placed against the screen")
  k.GameTooltipDefaultContainer.points = { { "TOP", k.UIParent, "TOP", 0, 0 }, }
  k.GameTooltipDefaultContainer.points[1][2] = k.GameTooltipDefaultContainer   -- placed against itself: not read
  MK.SetScenario("solo"); MK.SetScenario("tooltip")
  Check(math.abs(MK.Scene().tooltip.rect.r - (W / 2 - 9)) < 0.01, "a container placed against something else is not read; the default stands")
  table.insert(pkgChoices, tooltipAt, tooltipChoice)
  MK.SetScenario("solo"); MK.SetScenario("tooltip")
  -- an unknown scenario is refused; the choice is not remembered
  Check(MK.SetScenario("nobody") == false and MK.Scenario() == "tooltip", "an unknown scenario is refused")
  Check(k.TwichUIDB.layouts == nil or k.TwichUIDB.layouts.wizard == nil or k.TwichUIDB.layouts.wizard.scenario == nil, "the scenario is not saved")
  WW.Close()
  Open(k)
  Check(MK.Scenario() == "solo", "reopened: Solo again")
  Check(Unchanged(World(k), before), "no scenario changed anything in the game")
  -- repeated scenario changes make nothing new
  Click(w, "Start")
  local made = k.made()
  for _ = 1, 10 do
    for _, label in ipairs({ "Target", "Party", "Long quests", "Tooltip", "Solo" }) do Click(w, label) end
  end
  local after = k.made()
  Check(after - made <= 8, "fifty scenario changes: only the few pieces and the tooltip that appeared for the first time were made (" .. (after - made) .. ")")
  made = k.made()
  for _ = 1, 10 do
    for _, label in ipairs({ "Target", "Party", "Long quests", "Tooltip", "Solo" }) do Click(w, label) end
  end
  Check(k.made() == made, "and a second fifty made nothing")
end

---------------------------------------------------------------------------
-- 15. The wizard, the full-size overlay and the install put things in the same places
---------------------------------------------------------------------------
-- where a stored record puts the centre of a frame of w x h (written out independently of the engine)
local function CenterOf(rec, w, h, S)
  local rel = rec.relPoint or rec.point
  local sx = rel:find("LEFT") and -S.w / 2 or (rel:find("RIGHT") and S.w / 2 or 0)
  local sy = rel:find("BOTTOM") and -S.h / 2 or (rel:find("TOP") and S.h / 2 or 0)
  local px, py = sx + rec.x, sy + rec.y
  local cx, cy = px, py
  if rec.point:find("LEFT") then cx = px + w / 2 elseif rec.point:find("RIGHT") then cx = px - w / 2 end
  if rec.point:find("BOTTOM") then cy = py + h / 2 elseif rec.point:find("TOP") then cy = py - h / 2 end
  return cx, cy
end

do
  for _, scr in ipairs({ { 2133.33, 1200 }, { 1920, 1080 }, { 1680, 1050 }, { 2866.67, 1200 } }) do
    for _, variant in ipairs({ CLASSIC, COMPACT }) do
      for _, density in ipairs({ "standard", "larger" }) do
        local S = { w = scr[1], h = scr[2] }
        local name = ("%dx%d %s %s"):format(scr[1], scr[2], variant, density)
        local k = LM.Boot("Same", nil, { screen = { w = S.w, h = S.h } })
        local w, WK = Open(k)
        local MK, WW, OV = WK.Model, WK.Window, WK.Overlay
        MK.SetLayout(variant)
        MK.SetPick("size", density)
        MK.SetPick("accent", "gold")
        Click(w, "Start"); WW.Refresh()
        local scene = MK.Scene()
        -- the scene's components are the plan's geometry
        local plan = MK.Plan()
        Check(plan.ok and plan.variant == variant and plan.geometry.density == density, name .. ": the plan is for this layout and size")
        for id, c in pairs(plan.geometry.components) do
          local sc
          for _, x in ipairs(scene.components) do if x.id == id then sc = x end end
          if c.managed and c.rect.w > 0 then
            Check(sc and sc.rect.x == c.rect.x and sc.rect.y == c.rect.y and sc.rect.w == c.rect.w and sc.rect.h == c.rect.h, name .. ": scene " .. id .. " is the plan's")
          end
        end
        -- the miniature draws the scene, to scale
        local pv = WW.pages[2].preview
        for id, box in pairs(pv.drawn.boxes) do
          local r = plan.geometry.components[id].rect
          Check(math.abs(box.x / pv.drawn.scale - r.x) < 0.05 and math.abs(box.w / pv.drawn.scale - r.w) < 0.05, name .. ": the miniature's " .. id .. " is the plan's, to scale")
        end
        for id, el in pairs(pv.drawn.elements) do
          local piece
          for _, e in ipairs(scene.elements) do if e.id == id then piece = e end end
          Check(piece and math.abs(el.x / pv.drawn.scale - piece.rect.x) < 0.05 and math.abs(el.y / pv.drawn.scale - piece.rect.y) < 0.05, name .. ": the miniature's " .. id .. " is the scene's")
        end
        -- the overlay draws the scene at full size (and every scenario's pieces are in its plan's places)
        MK.SetScenario("party")
        MK.SetScenario("target")
        local ok = OV.Open()
        Check(ok and OV.IsShown(), name .. ": the full-size preview opens")
        local last = OV.last
        local scene2 = MK.Scene()
        for _, sc in ipairs(scene2.components) do
          local l = last.components[sc.id]
          Check(l and l.x == sc.rect.x and l.y == sc.rect.y and l.w == sc.rect.w and l.h == sc.rect.h, name .. ": the overlay's " .. sc.id .. " is the plan's, at full size")
        end
        for _, e in ipairs(scene2.elements) do
          local l = last.elements[e.id]
          Check(l and l.x == e.rect.x and l.y == e.rect.y and l.w == e.rect.w and l.h == e.rect.h, name .. ": the overlay's " .. e.id .. " is the scene's")
        end
        -- the install writes them where the preview shows them
        OV.Close("back")
        for step = 2, 4 do MK.Go(step) end
        Advance(w, MK, 5)
        Click(w, "Apply"); k.Accept()
        Check(k.TwichUI.Layouts.Journal.Read().state == "applied", name .. ": applied")
        local prof = k.EllesmereUIDB.profiles["TwichUI Adventure"]
        local EA = k.TwichUI.Layouts.EllesmereAdapter
        local compared = 0
        local allPieces = k.TwichUI.Layouts.Elements(MK.Layout().pkg, variant, plan.geometry)
        for _, e in ipairs(allPieces) do
          if e.adapter == "ellesmereui" then
            local p = EA.POSITIONS[e.id]
            local rec = prof.addons[p.module]
            for _, key in ipairs(p.path) do rec = rec and rec[key] end
            if type(rec) == "table" then
              local cx, cy = CenterOf(rec, e.rect.w, e.rect.h, S)
              Check(math.abs(cx - e.rect.x) < 0.03 and math.abs(cy - e.rect.y) < 0.03, name .. ": the install wrote " .. e.id .. " where the preview shows it")
              compared = compared + 1
            end
          end
        end
        Check(compared >= 12, name .. ": " .. compared .. " pieces compared with what the install wrote")
        local mm = prof.addons.EllesmereUIMinimap.minimap
        local mrect
        for _, sc in ipairs(scene.components) do if sc.id == "minimap" then mrect = sc.rect end end
        local mx, my = CenterOf(mm.position, mrect.w, mrect.h, S)
        Check(math.abs(mx - mrect.x) < 0.03 and math.abs(my - mrect.y) < 0.03 and mm.mapSize == math.floor(mrect.w + 0.5), name .. ": and the minimap, its size too")
      end
    end
  end
end

---------------------------------------------------------------------------
-- 16. The full-size overlay: what it is, what it never does, and that it cleans up
---------------------------------------------------------------------------
do
  local ovSrc = io.open(REPO .. "TwichUI_LayoutWizard/Overlay.lua"):read("*a")
  for _, bad in ipairs({ "SecureActionButtonTemplate", "SecureHandler", "SetAttribute", "RegisterForClicks", "hooksecurefunc", "CastSpell",
      "UseAction", "loadstring", "RegisterGameMenuEscHandler", "UIParent:Hide", "UIParent:SetAlpha", "C_Timer", "OnUpdate", "ReloadUI", "LY.Apply",
      "LY.Restore", "TwichUIDB" }) do
    Check(not ovSrc:find(bad, 1, true), "the overlay's source has no " .. bad)
  end
  local k = LM.Boot("Overlay")
  local w, WK = Open(k)
  local MK, WW, OV = WK.Model, WK.Window, WK.Overlay
  local LY = k.TwichUI.Layouts
  local calls = { Apply = 0, Restore = 0, Detach = 0 }
  for name in pairs(calls) do
    local fn = LY[name]
    LY[name] = function(...) calls[name] = calls[name] + 1 return fn(...) end
  end
  local imports = 0
  local importFn = k.E.ImportProfileSilent
  k.E.ImportProfileSilent = function(...) imports = imports + 1 return importFn(...) end
  Click(w, "Start")
  local before = World(k)
  local listeners0 = {}
  k.TwichUI.ListenerCounts(listeners0)

  -- not in combat
  k.combat = true
  WW.Refresh()
  Check(not Enabled(w, "See it full size") and Says(w, "needs you out of combat"), "in combat the button is off, and says why")
  Check(OV.Open() == false and not OV.IsShown() and WW.IsShown(), "and the overlay will not open")
  k.combat = false
  WW.Refresh()
  Check(Enabled(w, "See it full size"), "out of combat it is on")

  -- open
  Check(OV.listening == 0 and OV.builds == 0 and k.TwichUILayoutOverlay == nil, "nothing of it exists until it is asked for")
  Click(w, "See it full size")
  local root = k.TwichUILayoutOverlay
  Check(root and root.shown and OV.builds == 1 and OV.listening == 3, "it opens, built once, listening for three events")
  Check(not WW.IsShown() and MK.Active() and MK.Step() == 2, "the wizard is set aside, not ended: its session and step are kept")
  Check(root.mouse == false and root.keyboard == false and root.strata == "FULLSCREEN_DIALOG", "the covering frame takes no mouse and no keyboard (the game stays usable through it)")
  -- every frame under it is inert, except the control bar's controls
  local bar = OV.bar
  local function Walk(f, fn) fn(f) for _, ch in ipairs(f.children or {}) do Walk(ch, fn) end end
  local clickable, mouse = 0, 0
  Walk(root, function(f)
    if f ~= root and f.kind == "Frame" or f.kind == "Button" then
      -- is it under the bar?
      local p, under = f, false
      while p do if p == bar then under = true end p = p.parent end
      if not under then
        if f.mouse == true then mouse = mouse + 1 end
        if f.scripts and (f.scripts.OnClick or f.scripts.OnMouseDown or f.scripts.OnEnter) then clickable = clickable + 1 end
      end
    end
  end)
  Check(mouse == 0 and clickable == 0, "nothing outside the control bar takes the mouse or has a click (" .. mouse .. " frames with the mouse, " .. clickable .. " with scripts)")
  Check(bar.mouse == true and Has(root, "Back") and Has(root, "Switch to Compact") and Has(root, "Exit"), "the control bar takes the mouse: Back, Switch to Compact, Exit")
  Check(Says(root, "PREVIEW   Classic Adventure - nothing is applied") and Says(root, "dimmed behind it, not hidden or moved"), "it says it is a preview, and that nothing is hidden or moved")
  for id, p in pairs(OV.panels) do
    if p.shown then Check(p.tag.text:find("(sample)", 1, true), "the " .. id .. " box says it is a sample") end
  end
  local listed = 0
  for _, n in ipairs(k.UISpecialFrames) do if n == "TwichUILayoutOverlay" then listed = listed + 1 end end
  Check(listed == 1 and k.escRegistered == 0, "Escape: in the game's own list once, and never the Escape handler table")
  Check(Unchanged(World(k), before) and calls.Apply == 0 and calls.Restore == 0 and imports == 0 and k.reloads == 0, "opening it changed nothing and called no install")

  -- the scene it draws: which pieces are in it, what it says about them
  local last = OV.last
  Check(last.components.central and last.components.chat and last.elements["bar-main"] and last.elements["uf-player"], "the block, chat, the bars and your frame are drawn")
  Check(OV.elems["uf-player"].label.text == "Player frame" and OV.elems["class-bars"].label.text == "Class resource bars", "pieces are labelled (a TwichUI marker beside itself)")

  -- switching the layout inside it, and a scenario
  Click(root, "Switch to Compact")
  Check(MK.Layout().id == COMPACT and OV.last.variant == COMPACT and Has(root, "Switch to Classic") and Says(root, "PREVIEW   Compact Adventure"), "Switch layout shows the other layout at once")
  Check(math.abs(OV.last.components.central.w - 1091) < 0.01 and OV.last.elements["bar-7"], "drawn from Compact's own rules")
  Click(root, "Target")
  Check(MK.Scenario() == "target" and OV.last.elements["uf-target"] and OV.last.scenario == "target", "and a scenario tab changes what the sample shows")
  Click(root, "Tooltip")
  Check(OV.last.tooltip and OV.panels.tooltip.shown, "the tooltip scenario draws a tooltip")
  Click(root, "Long quests")
  Check(OV.last.tooltip == nil and not OV.panels.tooltip.shown, "and leaves it out again")
  Check(Unchanged(World(k), before) and calls.Apply == 0 and imports == 0, "none of it changed the game")
  Check(k.TwichUIDB.layouts.wizard.variant == COMPACT, "only the layout choice was remembered, as it is in the wizard")

  -- Back returns to the wizard where it was left
  Click(root, "Back")
  Check(not root.shown and WW.IsShown() and MK.Step() == 2 and MK.Layout().id == COMPACT and OV.listening == 0 and next(OV.evframe.events) == nil, "Back: the overlay is gone, its events with it, and the wizard is where it was, on Compact")
  -- Exit closes both
  Click(w, "See it full size")
  Click(root, "Exit")
  Check(not root.shown and not WW.IsShown() and not MK.Active() and OV.listening == 0, "Exit: both closed, the session over")
  Check(Unchanged(World(k), before), "and nothing changed")
  -- Escape returns to the wizard
  Open(k)
  Advance(w, MK, 2)
  Click(w, "See it full size")
  Check(k.PressEsc(), "Escape does something while it is open")
  Check(not root.shown and WW.IsShown() and MK.Active() and MK.Step() == 2 and OV.listening == 0, "one Escape closes the preview and returns to the wizard, which stays open")
  -- asking for the wizard again while it is open
  Click(w, "See it full size")
  k.SlashCmdList.TWICHUI("layout")
  Check(not root.shown and WW.IsShown(), "/tui layout while the preview is open brings the setup back")

  -- combat starting closes it
  Click(w, "See it full size")
  k.combat = true
  OV.evframe.scripts.OnEvent(OV.evframe, "PLAYER_REGEN_DISABLED")
  Check(not root.shown and WW.IsShown() and OV.listening == 0, "combat starting closes it and returns to the wizard")
  Check(Says(w, "You are in combat") or not Enabled(w, "See it full size"), "which says so")
  k.combat = false
  WW.Refresh()
  -- a profile change closes it, and the wizard re-plans
  Click(w, "See it full size")
  local PF = k.TwichUI.Profiles
  Check(PF.Create("Other"), "(a profile is made)")
  Check(not root.shown and WW.IsShown() and OV.listening == 0, "a profile change closes it, and returns to the wizard")
  Check(OV.profileHooks == 1, "with one listener for the whole session")
  Click(w, "See it full size")
  Check(PF.Switch("Default"), "(and back)")
  Check(not root.shown and WW.IsShown(), "switching profile too")
  -- the wizard closing under it
  Click(w, "See it full size")
  WW.Close()
  Check(not root.shown and not WW.IsShown() and not MK.Active() and OV.listening == 0, "the wizard closing takes the preview with it and ends the session")
  -- the screen changing while it is open: it is drawn again for the new screen
  Open(k)
  Advance(w, MK, 2)
  Click(w, "See it full size")
  local drawsBefore = OV.draws
  k.UIParent.w, k.UIParent.h = 1920, 1080
  OV.evframe.scripts.OnEvent(OV.evframe, "DISPLAY_SIZE_CHANGED")
  Check(OV.draws == drawsBefore + 1 and OV.last.screen.w == 1920 and OV.last.screen.h == 1080, "a new screen: drawn again for it")
  local plan = LY.Plan(MK.Layout().pkg, MK.Layout().variant, { picks = MK.Picks() })
  Check(math.abs(OV.last.components.chat.x - plan.geometry.components.chat.rect.x) < 0.01, "and it is the plan's for that screen")
  OV.evframe.scripts.OnEvent(OV.evframe, "UI_SCALE_CHANGED")
  Click(root, "Back")
  OV.evframe.scripts.OnEvent(OV.evframe, "DISPLAY_SIZE_CHANGED")
  Check(OV.draws == drawsBefore + 2 or OV.draws == drawsBefore + 1, "an event after it closed draws nothing")
  k.UIParent.w, k.UIParent.h = 2133.33, 1200
  MK.Invalidate()

  -- opened and closed again and again: nothing grows
  local made, frames, kept = nil, nil, nil
  for round = 1, 10 do
    Click(w, "See it full size")
    if round == 1 then Click(root, "Target") Click(root, "Party") Click(root, "Long quests") Click(root, "Tooltip") Click(root, "Solo") end
    Check(OV.listening == 3, "round " .. round .. ": three events while open")
    Click(root, "Back")
    Check(OV.listening == 0 and next(OV.evframe.events) == nil, "round " .. round .. ": none when closed")
    if round == 1 then made, frames = k.made(), OV.frames end
  end
  Check(k.made() == made and OV.frames == frames and OV.builds == 1 and OV.profileHooks == 1, "ten more opens and closes made no frame, no texture, no second build and no second listener (" .. made .. ")")
  local listeners1 = {}
  k.TwichUI.ListenerCounts(listeners1)
  Check(Same(listeners0, listeners1), "the core's own event listeners are exactly as before")
  local gaugeIds = {}
  for _, g in ipairs(k.TwichUI.Perf.gauges) do gaugeIds[g.id] = g end
  Check(gaugeIds["layoutwizard.overlay.events"] and gaugeIds["layoutwizard.overlay.events"].read() == 0 and gaugeIds["layoutwizard.overlay.frames"] and gaugeIds["layoutwizard.overlay.frames"].read() == OV.frames,
    "the two gauges are registered and read")
  Check(#root.hooks.OnHide == 1 and root.scripts.OnEvent == nil, "the overlay's own hooks are installed once")
  Check(calls.Apply == 0 and calls.Restore == 0 and calls.Detach == 0 and imports == 0 and k.reloads == 0 and Same(World(k).eui, before.eui), "after all of that (the test made and switched a profile itself): no install, restore, reload or import, and EllesmereUI untouched")
end

do
  -- long text, narrow layouts
  local function OverlayOn(w, h, variant, scenario)
    local k = LM.Boot("Text", nil, { screen = { w = w, h = h } })
    local win, WK = Open(k)
    local MK, OV = WK.Model, WK.Overlay
    MK.SetLayout(variant)
    Click(win, "Start")
    MK.SetScenario(scenario)
    assert(OV.Open())
    return k, WK, OV
  end
  local k, WK, OV = OverlayOn(2133.33, 1200, CLASSIC, "objectives")
  local p = OV.panels.objectives
  local rect = OV.last.components.objectives
  local widest = 0
  for _, fs in ipairs(p.lines) do if fs.shown then widest = math.max(widest, fs.w) end end
  Check(widest > 0 and widest <= rect.w - 12 + 0.01, "long objectives wrap inside their box (the widest line asks for " .. widest .. " of " .. rect.w .. ")")
  Check(not OV.last.overflow.objectives and not p.warn.shown, "and on this screen they fit its height")
  local k2, WK2, OV2 = OverlayOn(1365.33, 768, CLASSIC, "objectives")
  Check(OV2.last.overflow.objectives and OV2.panels.objectives.warn.shown and OV2.panels.objectives.warn.text:find("runs past"), "on a small screen the same text runs past its box, and says so rather than hiding it")
  Check(not OV2.last.overflow.chat, "a box with room says nothing")
  -- Compact on a narrow screen: chat above the block, in the overlay too
  local k3, WK3, OV3 = OverlayOn(1680, 1050, COMPACT, "solo")
  local l = OV3.last.components
  Check(l.chat.y - l.chat.h / 2 >= l.central.y + l.central.h / 2 + 12 - 0.01 and math.abs(l.chat.w - 451) < 0.01, "Compact on a narrow screen: chat above the block at its full width")
  Check(WK3.Model.Scene().fits, "and everything fits")
  -- a screen that doesn't fit: the overlay says what
  local k4, WK4, OV4 = OverlayOn(1365.33, 768, COMPACT, "solo")
  Check(not WK4.Model.Scene().fits and OV4.bar.fit.shown and OV4.bar.fit.text:find("Doesn't fit this screen", 1, true), "a screen the layout doesn't fit: the bar says which")
  local troubled = 0
  for id, p4 in pairs(OV4.panels) do if p4.shown and p4.border and p4.border[1] == k4.TwichUI.Look.pal.danger.border[1] then troubled = troubled + 1 end end
  Check(troubled >= 2, "and the boxes that collide are outlined in the warning colour (" .. troubled .. ")")
end

---------------------------------------------------------------------------
-- 17. Saved state with a layout in it
---------------------------------------------------------------------------
do
  local function Boot1(wizard)
    local k = LM.Boot("State")
    k.TwichUIDB.layouts = { wizard = wizard }
    return k
  end
  local k = Boot1({ v = 1, variant = COMPACT, picks = { accent = "dusk" } })
  local w, WK = Open(k)
  Check(WK.Model.Layout().id == COMPACT and WK.Model.Pick("accent") == "dusk", "a remembered layout and pick are read")
  local k2 = Boot1({ v = 1, variant = "nobody", picks = { accent = "dusk" } })
  local _, WK2 = Open(k2)
  Check(WK2.Model.Layout().id == CLASSIC and WK2.Model.Pick("accent") == "dusk", "a layout that isn't the package's goes back to the first; the picks are kept")
  Check(k2.TwichUIDB.layouts.wizard.variant == "nobody", "and reading it changed nothing")
  local k3 = Boot1({ v = 1, variant = 7, picks = {} })
  local _, WK3 = Open(k3)
  Check(WK3.Model.Layout().id == CLASSIC, "a layout that isn't text is ignored")
  WK3.Model.SetPick("accent", "ember")
  Check(k3.TwichUIDB.layouts.wizard.variant == CLASSIC and k3.TwichUIDB.layouts.wizard.picks.accent == "ember", "the next save is clean")
  local k4 = Boot1({ v = 99, variant = COMPACT })
  local _, WK4 = Open(k4)
  Check(WK4.Model.Layout().id == CLASSIC, "a newer record is not understood: the defaults are used")
  WK4.Model.SetLayout(COMPACT)
  Check(Same(k4.TwichUIDB.layouts.wizard, { v = 99, variant = COMPACT }), "and a choice never overwrites it")
  -- the reload note and the layout travel together
  local k5 = LM.Boot("State")
  local w5, WK5 = Open(k5)
  WK5.Model.SetLayout(COMPACT)
  ToReview(w5)
  Click(w5, "Apply"); k5.Accept()
  Click(w5, "Reload now")
  local st = k5.TwichUIDB.layouts.wizard
  Check(st.resume == "install" and st.variant == COMPACT, "the reload note keeps the layout")
  local k6 = LM.Boot("State", LM.Logout(k5))
  local after = k6.TwichUIDB.layouts.wizard
  Check(after.resume == nil and after.variant == COMPACT and k6.TwichUI.LayoutWizard.Model.Layout().id == COMPACT, "using the note up keeps the layout too")
end

-- Force re-apply: offered on the review only when an earlier install is recorded or everything that blocks Apply is something it can
-- lift; turning it on changes nothing in the game; the question names what it replaces; Apply then installs as a new install
do
  local k = LM.Boot("Force")
  local w, WK = Open(k)
  local MK = WK.Model
  ToReview(w)
  Check(MK.Step() == 5 and Enabled(w, "Apply") and not Has(w, "Force re-apply"), "Force: a first install on a clean account isn't offered it")
  Click(w, "Apply"); k.Accept()
  Click(w, "Reload now")
  local k2 = LM.Boot("Force", LM.Logout(k))
  local w2, WK2 = k2.TwichUILayoutWizard, k2.TwichUI.LayoutWizard
  local M2 = WK2.Model
  Click(w2, "Set up again")
  Advance(w2, M2, 5)
  Check(Has(w2, "Force re-apply"), "   an earlier install is recorded: offered on the review")
  Check(not Enabled(w2, "Apply"), "   and with the same choices Apply has nothing to do")
  -- the install's record is half done, and a Restore that never finished blocks Apply
  k2.TwichUIDB.layouts.install.state = "restore-partial"
  M2.Invalidate()
  WK2.Window.Refresh()
  Check(not Enabled(w2, "Apply") and Has(w2, "Force re-apply"), "   a Restore that didn't finish blocks Apply; Force re-apply is offered")
  local before = World(k2)
  Click(w2, "Force re-apply")
  Check(M2.Forced() and Has(w2, "Stop forcing") and Enabled(w2, "Apply"), "   turning it on enables Apply and the button turns it off again")
  Check(Unchanged(World(k2), before), "   and changes nothing in the game")
  Check(M2.Review().forced ~= nil and Says(w2, "Forced re-apply"), "   the review says what it does")
  local text = M2.ConfirmText()
  Check(text:find("Forced re-apply", 1, true) and text:find("Restore will go back to how things are when you press Apply", 1, true),
    "   and so does the question, including what Restore then goes back to")
  Click(w2, "Stop forcing")
  Check(not M2.Forced() and not Enabled(w2, "Apply"), "   Stop forcing is back to the blocked review")
  Click(w2, "Force re-apply")
  Click(w2, "Back"); Click(w2, "Next")
  Check(not M2.Forced() and Has(w2, "Force re-apply") and not Has(w2, "Stop forcing"), "   leaving the review drops it: it is asked for again each time")
  Click(w2, "Force re-apply")
  Click(w2, "Apply"); k2.Accept()
  Check(not M2.Forced() and k2.TwichUIDB.layouts.install.state == "applied", "   applying it installs again, with a record that can be read, and forgets the request")
end

-- Force re-apply for what a stuck account really shows: another character's record, its Restore never finished, and the
-- profile it would go back to gone
do
  local k = LM.Boot("ForceStuck")
  local w, WK = Open(k)
  ToReview(w)
  Click(w, "Apply"); k.Accept()
  Click(w, "Reload now")
  local k2 = LM.Boot("ForceStuck", LM.Logout(k))
  local j = k2.TwichUIDB.layouts.install
  j.char, j.state = "Someone-Else", "restore-partial"
  j.snapshot.ellesmereui.active = "Gone"
  local w2, WK2 = k2.TwichUILayoutWizard, k2.TwichUI.LayoutWizard
  Click(w2, "Set up again")
  Advance(w2, WK2.Model, 5)
  local r = WK2.Model.Review()
  Check(not r.ok and #r.blocked >= 3, "Force: the review is blocked for several reasons at once")
  Check(not Enabled(w2, "Apply") and Has(w2, "Force re-apply"), "   Apply is off and Force re-apply is offered")
  Click(w2, "Force re-apply")
  Check(WK2.Model.Review().ok and Enabled(w2, "Apply") and Says(w2, "another character"), "   forced, nothing blocks, and the review says the record was another character's")
  Click(w2, "Apply"); k2.Accept()
  local jj = k2.TwichUIDB.layouts.install
  Check(jj and jj.char ~= "Someone-Else" and jj.state == "applied", "   Apply installs, with this character's own record")
end

if failures > 0 then error(failures .. " check(s) failed") end
print("LAYOUT WIZARD TEST PASSED")
