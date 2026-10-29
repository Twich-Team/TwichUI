dofile(TESTS .. "harness.lua")
dofile(TESTS .. "layouts_mock.lua")
-- The end of the layout wizard: the short question before Apply, "Apply & Reload" as one authorised action, the progress and the
-- fallbacks when the reload does not start, and the compact result dialog that follows (docs/layouts/wizard.md, "Applying and
-- finishing"). Driven through the real window with stand-in frames (layouts_mock.lua) and the real engine; the engine's own safety
-- (snapshots, ownership, Undo, Restore) is test_layouts.lua / test_layout_update.lua / test_layout_force.lua and the wizard's
-- test_layout_wizard.lua; this file is about what the player is asked, when the game reloads, and what the result says.

META = { EllesmereUI = { Version = "9.6.8" } }

local failures = 0
local function Check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local Copy, Same, Says = LM.Copy, LM.Same, LM.Says

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
local function ApplyLabel(win) return Find(win, "Apply & Reload") and "Apply & Reload" or "Apply" end
local function Click(win, label)
  local b = Find(win, label)
  assert(b, "no visible button '" .. label .. "'")
  assert(b.enabled ~= false, "button '" .. label .. "' is disabled")
  b.scripts.OnClick(b)
end
local function Enabled(win, label) local b = Find(win, label) return b ~= nil and b.enabled ~= false end
local function Has(win, label) return Find(win, label) ~= nil end
local function Expand(win, label)
  local b = Find(win, label)
  assert(b, "no visible disclosure '" .. label .. "'")
  if not b.open then b.scripts.OnClick(b) end
  return b
end
local function Open(c)
  c.SlashCmdList.TWICHUI("layout")
  return c.TwichUILayoutWizard, c.TwichUI.LayoutWizard
end
local function ToReview(win) for i = 1, 4 do Click(win, i == 1 and "Get started" or "Next") end end
local function Advance(win, MK, step) while MK.Step() < step do Click(win, MK.Step() == 1 and "Get started" or "Next") end end
local function World(c)
  local tw = Copy(c.TwichUIDB)
  if tw.layouts then tw.layouts.wizard = nil; if next(tw.layouts) == nil then tw.layouts = nil end end
  return { tw = tw, eui = Copy(c.EllesmereUIDB), restore = Copy(c.TwichUIRestoreDB), share = Copy(c.TwichUIShareDB), chron = Copy(c.TwichUIChronicleDB) }
end
local function Unchanged(a, b) return Same(a.tw, b.tw) and Same(a.eui, b.eui) and Same(a.restore, b.restore) and Same(a.share, b.share) and Same(a.chron, b.chron) end
local function Lines(text) local n = 1 for _ in text:gmatch("\n") do n = n + 1 end return n end

-- A client that has applied the bundled layout and been through the reload: the result dialog of a checked setup
local function Installed(name, picks)
  local k = LM.Boot(name)
  local w, WK = Open(k)
  for id, v in pairs(picks or {}) do WK.Model.SetPick(id, v) end
  ToReview(w)
  Click(w, ApplyLabel(w))
  k.Accept()
  return LM.Boot(name, LM.Logout(k))
end

---------------------------------------------------------------------------
-- 1. The question: short, structured, in a player's words; nothing from the adapters' plan text
---------------------------------------------------------------------------
do
  local k = LM.Boot("Ask")
  local w, WK = Open(k)
  local MK = WK.Model
  ToReview(w)
  local c = MK.Confirmation()
  Check(c.title == "Apply Classic Adventure?", "the title names the layout")
  Check(c.reload == true and c.accept == "Apply & Reload" and c.intro == "Your interface will reload to finish setup.", "the reload is said before accepting, and is what the button says")
  Check(#c.rows >= 2 and #c.rows <= 4 and #c.warnings == 0, "an ordinary apply: a few consequence rows and no warnings (" .. #c.rows .. " rows, " .. #c.warnings .. " warnings)")
  local text = MK.ConfirmText()
  Check(Lines(text) <= 9 and #text < 520, "short enough to fit a dialog without scrolling (" .. Lines(text) .. " lines, " .. #text .. " characters)")
  -- none of the review's detail, and none of the adapters' own plan text
  local review = MK.Review()
  for _, sec in ipairs({ review.twichui, review.ellesmereui }) do
    for _, l in ipairs(sec.lines) do Check(not text:find(l, 1, true), "the question does not repeat the review's line: " .. l:sub(1, 40)) end
  end
  Check(not text:find("TwichUI Adventure", 1, true) and not text:find("\"", 1, true) and not text:find("%d+ %a+ settings?") and not text:find("EllesmereUI:", 1, true),
    "no profile name, field count or adapter heading")
  Check(text:find("backed up", 1, true) and text:find("every character on this account", 1, true), "the backup and the account-wide scope are said")
  Check(not text:find("Restore", 1, true), "an ordinary apply does not need to explain Restore")
  -- the footer says the same
  Check(Enabled(w, "Apply & Reload") and not Has(w, "Apply"), "the footer's action is Apply & Reload")

  -- the question is bound to this plan
  Click(w, "Apply & Reload")
  local q = k.popup
  local dlg = k.StaticPopupDialogs[q.key]
  Check(dlg.button1 == "Apply & Reload" and dlg.button3 == "View details", "its buttons: Apply & Reload, Cancel, View details")
  -- cancelling: nothing written, nothing reloaded
  local before = World(k)
  k.Decline()
  Check(Unchanged(World(k), before) and k.reloads == 0 and MK.Step() == 5 and k.E:called("ImportProfileSilent") == 0, "Cancel writes nothing and reloads nothing")
  -- View details: the review's account of every change, nothing applied
  Click(w, "Apply & Reload")
  k.Alt()
  Check(MK.Step() == 5 and Says(w, "Left alone") and Unchanged(World(k), before) and k.reloads == 0, "View details opens the review's changes and applies nothing")
  -- stale: a choice changed while the question was open
  Click(w, "Apply & Reload")
  MK.SetPick("accent", "ember")
  k.Accept()
  Check(Unchanged(World(k), before) and k.reloads == 0 and k.TwichUI.Layouts.Journal.Read() == nil and MK.Step() ~= 6, "a plan that changed under the question is refused: nothing written, no reload")
  -- the model refuses the old key itself, before the engine is asked (the question's own check and the engine's are the other two)
  local LYk = k.TwichUI.Layouts
  local engineCalls, realApply = 0, LYk.Apply
  LYk.Apply = function(...) engineCalls = engineCalls + 1 return realApply(...) end
  local oldKey = MK.Review().key
  MK.SetPick("accent", "dusk")
  local okS, whyS = MK.ApplyAndReload(oldKey, true)
  Check(okS == false and whyS == "stale" and engineCalls == 0 and k.reloads == 0, "the model refuses a key the plan no longer has, without asking the engine")
  LYk.Apply = realApply
  MK.SetPick("accent", "gold")
  -- the screen changed under it
  Click(w, "Apply & Reload")
  k.UIParent.w, k.UIParent.h = 1920, 1080
  WK.Window.evframe.scripts.OnEvent(WK.Window.evframe, "DISPLAY_SIZE_CHANGED")
  k.Accept()
  Check(Unchanged(World(k), before) and k.reloads == 0, "so is a screen that changed: nothing written, no reload")
end

---------------------------------------------------------------------------
-- 2. Exceptional confirmations keep their warnings, in short sentences
---------------------------------------------------------------------------
do
  -- an earlier install left stuck: Force re-apply
  local k = Installed("Forced", { accent = "dusk" })
  local w, WK = k.TwichUILayoutWizard, k.TwichUI.LayoutWizard
  local MK = WK.Model
  k.TwichUIDB.layouts.install.state = "restore-partial"
  MK.Invalidate()
  WK.Window.Actions.again()   -- the record was changed behind the page's back, so the button the page drew is not offered now
  Advance(w, MK, 5)
  Expand(w, "Advanced")
  Click(w, "Force re-apply")
  local c = MK.Confirmation()
  local joined = table.concat(c.warnings, " ")
  Check(joined:find("Forced re-apply", 1, true) and joined:find("Restore will go back to how things are now, not to before it", 1, true), "forced: it says so, and where Restore then goes")
  Check(#c.warnings >= 1 and #c.warnings <= 5, "in a few short sentences (" .. #c.warnings .. ": " .. table.concat(c.warnings, " | ") .. ")")
  Check(not MK.ConfirmText():find("backed up", 1, true), "and does not promise the ordinary backup")
  Check(c.reload == true and c.accept == "Apply & Reload", "the reload is still announced")
end

do
  -- a TwichUI profile with the layout's name that no record claims: taking it over, in ordinary words and not as "recognised"
  local k = LM.Boot("Taken")
  k.TwichUI.Profiles.Create("TwichUI Adventure")
  k.TwichUI.Profiles.Switch("Default")
  local w, WK = Open(k)
  local MK = WK.Model
  ToReview(w)
  Expand(w, "Advanced")
  Click(w, "Force re-apply")
  local c = MK.Confirmation()
  local joined = table.concat(c.warnings, " ")
  Check(joined:find("isn't recorded as made by this install", 1, true) and not joined:find("recognised", 1, true) and not joined:find("owned", 1, true),
    "a profile taken over is said to be one this install didn't make")
  Check(joined:find("written into", 1, true) or joined:find("replaced", 1, true), "and what happens to it")
end

do
  -- an update: customizations kept (a row), or replaced by the recommended values (a warning); consecutive updates say the earlier one can't be undone
  local k = Installed("Update", { accent = "dusk" })
  local w, WK = k.TwichUILayoutWizard, k.TwichUI.LayoutWizard
  local MK = WK.Model
  Expand(w, "Manage layout") ; Click(w, "Set up again")
  Advance(w, MK, 4)
  MK.SetPick("accent", "ember")
  Click(w, "Next")
  local c = MK.Confirmation()
  local text = MK.ConfirmText()
  Check(Says(w, "Ready to update"), "an update review")
  Check(text:find("personal customizations will be kept", 1, true) and text:find("undo this update", 1, true) and #c.warnings == 0, "keeping my customizations: a row, no warning")
  MK.SetUpdateMode("recommended")
  c = MK.Confirmation()
  local joined = table.concat(c.warnings, " ")
  Check(joined:find("replaced by its recommended values", 1, true) and not MK.ConfirmText():find("personal customizations will be kept", 1, true),
    "the recommended configuration: a warning that my own changes are replaced, and no promise to keep them")
  MK.SetUpdateMode("keep")
  Click(w, ApplyLabel(w)); k.Accept()
  local k2 = LM.Boot("Update", LM.Logout(k))
  -- a second update replaces the copy the first kept: the first can no longer be undone
  local w2, WK2 = Open(k2)
  local M2 = WK2.Model
  Expand(w2, "Manage layout") ; Click(w2, "Set up again")
  Advance(w2, M2, 4)
  M2.SetPick("accent", "verdigris")
  Click(w2, "Next")
  local c2 = M2.Confirmation()
  Check(table.concat(c2.warnings, " "):find("last update can no longer be undone", 1, true), "an earlier way back that this replaces is a warning")
end

---------------------------------------------------------------------------
-- 3. Apply & Reload: one authorised action, with its safety conditions
---------------------------------------------------------------------------
do
  -- what is on record at the moment the interface is asked to reload
  local k = LM.Boot("Reload")
  local w, WK = Open(k)
  local MK = WK.Model
  local LY = k.TwichUI.Layouts
  local seen
  local applies = 0
  local realApply = LY.Apply
  LY.Apply = function(...) applies = applies + 1 return realApply(...) end
  k.ReloadUI = function()
    k.reloads = k.reloads + 1
    local j = LY.Journal.Read()
    seen = { state = j and j.state, snapshot = j and j.snapshot ~= nil, reload = j and j.reload, note = k.TwichUIDB.layouts.wizard and k.TwichUIDB.layouts.wizard.resume }
  end
  ToReview(w)
  Click(w, "Apply & Reload")
  k.Accept()
  Check(k.reloads == 1 and applies == 1, "the interface reloaded once, after one apply")
  Check(seen and seen.state == "applied" and seen.snapshot and seen.reload == true and seen.note == "install", "with the record, its restore point and the note for the result already written when it reloaded")
  -- whatever timers exist (other modules' included) run out: none of them reloads or applies again
  for _ = 1, 4 do FlushTimers(); RunLongTimers(120) end
  Check(k.reloads == 1 and applies == 1, "no timer, countdown or deferred callback reloads or applies a second time")
  Check(MK.Reloading() and not Has(w, "Reload now") and not Enabled(w, "Apply & Reload") and Says(w, "Your interface will reload shortly."), "meanwhile the dialog says so and offers nothing to press twice")
  -- a second click on the old question's buttons, a second Apply, and a second call to the model do nothing
  k.popup = nil
  local ok, why = MK.ApplyAndReload("x", true)
  Check(ok == false and why == "busy", "the model refuses a second apply while the reload is under way")
  WK.Window.Actions.apply()
  Check(k.popup == nil and k.reloads == 1 and applies == 1, "so does the window")
  -- the source: no timer and no polling in the finishing path
  for _, f in ipairs({ "Model.lua", "Window.lua", "Pages.lua" }) do
    local text = io.open(REPO .. "TwichUI_LayoutWizard/" .. f):read("*a")
    Check(not text:find("C_Timer", 1, true) and not text:find("NewTicker", 1, true) and not text:find("SetScript%(\"OnUpdate\""), f .. ": no timer, ticker or OnUpdate")
  end
end

do
  -- no reload when the apply failed, was partial, or was refused
  local function Run(name, opts, setup)
    local k = LM.Boot(name, nil, opts)
    local w, WK = Open(k)
    if setup then setup(k, WK) end
    ToReview(w)
    return k, w, WK
  end
  -- failed (nothing changed)
  local k, w, WK = Run("F1", { eui = { failImport = true } })
  Click(w, "Apply & Reload"); k.Accept()
  Check(k.reloads == 0 and WK.Model.Step() == 6 and Says(w, "Setup could not be completed") and not WK.Model.Reloading(), "a failed apply: no reload, said")
  Check(Says(w, "Nothing was changed") and Has(w, "Set up again") and not Has(w, "Done") and not Says(w, "Your interface is ready"), "with a way to try again and no success dialog")
  -- partial
  k, w, WK = Run("P1", nil, function(c) c.TwichUI.Layouts.ADAPTERS.twichui.Apply = function() return { state = "failed", code = "write", rollback = "clean" } end end)
  Click(w, "Apply & Reload"); k.Accept()
  Check(k.reloads == 0 and k.TwichUI.Layouts.Journal.Read().state == "partial" and not WK.Model.Reloading(), "a partly applied setup: no reload")
  Check(Says(w, "Setup needs attention") and Says(w, "Part of the setup didn't finish: TwichUI.") and Enabled(w, "Restore previous setup") and not Says(w, "Your interface is ready"), "it names the part and offers Restore")
  Expand(w, "Details")
  Check(Says(w, "TwichUI: failed"), "the detail is under Details")
  -- combat at the moment of accepting: refused, nothing written
  k, w, WK = Run("C1")
  Click(w, "Apply & Reload")
  k.combat = true
  local before = World(k)
  k.Accept()
  Check(k.reloads == 0 and Unchanged(World(k), before), "accepted in combat: nothing written, no reload")
end

do
  -- the record is not as an apply that is waiting for a reload leaves it (here: no restore point in it): the reload does not start
  local k = LM.Boot("NoSnap")
  local w, WK = Open(k)
  local MK = WK.Model
  local LY = k.TwichUI.Layouts
  local realRead = LY.Journal.Read
  ToReview(w)
  Click(w, "Apply & Reload")
  local realApply = LY.Apply
  LY.Apply = function(...)
    local a, b, c = realApply(...)
    LY.Journal.Read = function() local j, why = realRead() if j then j = LM.Copy(j) j.snapshot = nil end return j, why end
    return a, b, c
  end
  k.Accept()
  LY.Journal.Read = realRead
  Check(k.reloads == 0 and not MK.Reloading() and MK.Step() == 6, "applied but the record has no restore point: no reload")
  Check(Says(w, "One more step") and Enabled(w, "Reload now"), "the dialog says one more step")
end

do
  -- the apply goes through and combat begins before the reload: the reload does not start, now or when combat ends
  local k = LM.Boot("Combat")
  local w, WK = Open(k)
  local MK = WK.Model
  local LY = k.TwichUI.Layouts
  local realApply = LY.Apply
  LY.Apply = function(...) local a, b, c = realApply(...) k.combat = true return a, b, c end
  ToReview(w)
  Click(w, "Apply & Reload")
  k.Accept()
  Check(k.reloads == 0 and LY.Journal.Read().state == "applied" and not MK.Reloading(), "applied, and combat began before the reload: nothing reloaded")
  WK.Window.evframe.scripts.OnEvent(WK.Window.evframe, "PLAYER_REGEN_DISABLED")
  Check(Says(w, "One more step") and Says(w, "You're in combat") and Has(w, "Reload now") and not Enabled(w, "Reload now"), "the dialog says one more step, why, and the button waits")
  k.combat = false
  WK.Window.evframe.scripts.OnEvent(WK.Window.evframe, "PLAYER_REGEN_ENABLED")
  Check(k.reloads == 0, "combat ending does not reload by itself")
  Check(Enabled(w, "Reload now"), "Reload now is the player's, and works again")
  Click(w, "Reload now")
  Check(k.reloads == 1 and k.TwichUIDB.layouts.wizard.resume == "install", "pressed: one reload, with its note")
end

do
  -- the note for the result cannot be saved: no reload (the game would come back to nothing), and the way forward is said
  local k = LM.Boot("NoNote")
  k.TwichUIDB.layouts = { wizard = { v = 99 } }   -- a newer TwichUI's record: the wizard writes nothing over it
  local w, WK = Open(k)
  ToReview(w)
  Click(w, "Apply & Reload")
  k.Accept()
  Check(k.reloads == 0 and k.TwichUI.Layouts.Journal.Read().state == "applied", "applied, the note could not be saved: no reload")
  Check(Says(w, "One more step") and Says(w, "didn't start") and Enabled(w, "Reload now"), "the dialog says one more step, with the player's own button")
  Click(w, "Reload now")
  Check(k.reloads == 0 and Says(w, "couldn't save where to pick up"), "and that button says why it does not reload either, instead of reloading blind")
  Check(Same(k.TwichUIDB.layouts.wizard, { v = 99 }), "the newer record is untouched")
end

do
  -- the call itself refused: the note taken back, one more step, no retry
  local k = LM.Boot("Refused")
  local w, WK = Open(k)
  ToReview(w)
  Click(w, "Apply & Reload")
  local calls = 0
  k.ReloadUI = function() calls = calls + 1 error("blocked") end
  k.Accept()
  Check(calls == 1 and not WK.Model.Reloading(), "a refused reload is tried once, not retried")
  Check(k.TwichUIDB.layouts.wizard.resume == nil, "and the note for after the reload is taken back")
  Check(Says(w, "One more step") and Enabled(w, "Reload now"), "the dialog says one more step, with Reload now")
  k.ReloadUI = function() k.reloads = k.reloads + 1 end
  Click(w, "Reload now")
  Check(k.reloads == 1 and k.TwichUIDB.layouts.wizard.resume == "install", "pressed by the player: it reloads and leaves the note")
end

do
  -- a question that did not announce a reload does not reload; a plan with no reload applies and checks at once
  local k = LM.Boot("Quiet")
  local w, WK = Open(k)
  local MK = WK.Model
  ToReview(w)
  local expect = MK.Review().key
  local ok, result = MK.ApplyAndReload(expect, false)
  Check(ok and result.state == "applied" and k.reloads == 0 and not MK.Reloading(), "a question that did not say 'reload' never reloads")

  local k2 = LM.Boot("NoReload")
  local w2, WK2 = Open(k2)
  local LY = k2.TwichUI.Layouts
  local M2 = WK2.Model
  -- the stand-in EllesmereUI part takes effect at once, so the engine can check at once (no reload pending)
  local ea = LY.ADAPTERS.ellesmereui
  local realApply = ea.Apply
  ea.Apply = function(...) local r = realApply(...) r.reload = nil return r end
  local realPlan = LY.Plan
  LY.Plan = function(...) local p = realPlan(...) p.reload = false return p end
  ToReview(w2)
  Check(M2.Confirmation().reload == false and M2.Confirmation().accept == "Apply" and M2.Confirmation().intro:find("No reload is needed", 1, true), "a plan with no reload says so, and the button is Apply")
  Check(Enabled(w2, "Apply") and not Has(w2, "Apply & Reload"), "the footer says Apply")
  Click(w2, "Apply")
  k2.Accept()
  Check(k2.reloads == 0, "and nothing reloads")
  local st = LY.Journal.Read().state
  Check(st == "verified" or st == "mismatch", "it was checked at once (" .. tostring(st) .. ")")
  Check(M2.Step() == 6 and (st ~= "verified" or Says(w2, "Your interface is ready")), "and the result is the compact dialog for what the check found")
end

---------------------------------------------------------------------------
-- 4. The compact result: sized to its content, honest about what was checked, nothing contradictory
---------------------------------------------------------------------------
do
  local k = Installed("Done", { accent = "dusk" })
  local w, WK = k.TwichUILayoutWizard, k.TwichUI.LayoutWizard
  local MK, WW = WK.Model, WK.Window
  local LY = k.TwichUI.Layouts
  Check(w.shown and MK.Step() == 6 and WW.IsCompact(), "after the reload the result opens as the compact dialog")
  Check(Says(w, "Your interface is ready") and Says(w, "Classic Adventure") and Says(w, "Make yourself at home"), "success is plain: heading, layout, one sentence")
  Check(Has(w, "Done") and Has(w, "Open settings") and Has(w, "Details") and Has(w, "Manage layout"), "Done and Open settings; Details and Manage layout folded")
  Check(not Says(w, "settings checked") and not Says(w, "read back by value") and not Says(w, "What was chosen"), "no counts or breakdowns on its face")
  Check(Says(w, "Some addon settings could not be fully verified."), "a limited check is a quiet note, not an error")
  Check(not Has(w, "Get started") and not Has(w, "Back") and not Has(w, "Close") and not Find(w, "1  Welcome"), "no stepper and no footer")
  Check(w.w == 520 and w.h < 590 and w.h >= 240, "a window of its own size (" .. w.w .. " x " .. w.h .. "), not the six-step one")
  Check(WW.Scrim() and WW.Scrim():IsShown(), "the screen is dimmed once, as for the wizard")
  -- sized by content: expanding Details grows it, collapsing shrinks it back
  local h0 = w.h
  Expand(w, "Details")
  Check(w.h > h0 and Says(w, "read back by value as planned") and Says(w, "checked only that"), "Details grows the dialog and says exactly what was checked, including the presence-only parts")
  Click(w, "Details")   -- closed again
  Check(w.h == h0, "and closing it brings it back")
  -- the page is not scrolled: its content fits the window
  local page = WW.pages[6]
  Check(page.frame:GetHeight() <= w.h - 44 - 32 + 1, "the content fits without a scroll bar")

  -- Done only closes: still managed, still restorable, nothing finished or discarded, no Finish call
  local finishes = 0
  local realFinish = LY.Finish
  LY.Finish = function(...) finishes = finishes + 1 return realFinish(...) end
  local realDetach = LY.Detach
  LY.Detach = function(...) finishes = finishes + 100 return realDetach(...) end
  local before = World(k)
  Click(w, "Done")
  Check(not w.shown and not WW.Scrim():IsShown(), "Done closes the dialog and its dimming")
  Check(finishes == 0 and Unchanged(World(k), before), "and finishes, detaches and discards nothing")
  Check(LY.Journal.Read().state == "verified" and LY.Journal.ReadManaged() ~= nil and LY.PlanRestore().ok, "the install is still managed and Restore is still possible")
  -- reopened by hand it is the same dialog, with Restore still under Manage layout
  Open(k)
  Expand(k.TwichUILayoutWizard, "Manage layout")
  Check(Enabled(k.TwichUILayoutWizard, "Restore previous setup") and Enabled(k.TwichUILayoutWizard, "Keep this setup"), "recovery is still offered until the player chooses Keep this setup")
  WW.Close()
  -- an acknowledged completion does not come back by itself
  local k2 = LM.Boot("Done", LM.Logout(k))
  Check(k2.TwichUILayoutWizard == nil and k2.wizardLoads == 0, "the next login opens nothing")
  local k3 = LM.Boot("Done", LM.Logout(k2))
  Check(k3.TwichUILayoutWizard == nil and k3.wizardLoads == 0 and k3.layoutLoads == 0, "nor the one after, and loads nothing")
end

do
  -- Escape: the same close, the dimming goes; the frame count is steady
  local k = Installed("Esc")
  local w, WK = k.TwichUILayoutWizard, k.TwichUI.LayoutWizard
  local WW = WK.Window
  Check(k.PressEsc() and not w.shown and not WW.Scrim():IsShown(), "Escape closes the dialog and its dimming")
  Check(WK.Model.Active() == false, "and the session ends")
  local made, frames
  for i = 1, 9 do
    if i == 2 then made, frames = k.made(), WW.frames end   -- the first round builds the six steps' pages, once
    Open(k)
    Expand(w, "Details") ; Expand(w, "Manage layout")
    WW.Close()
    Open(k)
    Expand(w, "Manage layout")
    Click(w, "Set up again")   -- into the six steps and back out
    Check(not WW.IsCompact() and w.w == 780 and w.h == 590, "Set up again is the full six-step window")
    WW.Close()
  end
  Check(k.made() == made and WW.frames == frames and WW.listening == 0, "eight more open-and-close cycles made no frames and left no listeners")
  Check(not WW.Scrim():IsShown(), "and no dimming behind")
end

do
  -- states: each has its own heading; only a read-back setup is the success dialog
  local k = Installed("States")
  local w, WK = k.TwichUILayoutWizard, k.TwichUI.LayoutWizard
  local MK, WW = WK.Model, WK.Window
  local LY = k.TwichUI.Layouts
  local j = LY.Journal.Read()
  local function Show() MK.Go(6) WW.Refresh() end
  local function State(s, verify)
    j = LY.Journal.Read()
    j.state = s
    if verify then j.verify = verify end
    LY.Journal.Write(j)
    MK.Invalidate()
    Show()
  end
  State("mismatch", { state = "mismatch", checked = 3, presence = 2, diffs = { { adapter = "ellesmereui", unit = "ellesmereui:root.euiAccent", code = "changed" } } })
  Check(Says(w, "Setup needs attention") and Says(w, "A few settings did not match after reloading.") and not Says(w, "Your interface is ready") and not Has(w, "Done"), "a mismatch is not a success")
  Check(Says(w, "Accent colour") and Enabled(w, "Check again") and Enabled(w, "Restore previous setup"), "it names what differs and offers the recovery actions")
  State("mismatch", { state = "unverifiable", checked = 3, presence = 0, diffs = {} })
  Check(Says(w, "couldn't be read back") and Says(w, "Setup needs attention"), "settings that could not be read are not 'matching'")
  State("partial")
  Check(Says(w, "Setup needs attention") and not Says(w, "Your interface is ready") and Enabled(w, "Restore previous setup"), "a partial install: attention, Restore")
  State("applied")
  Check(Says(w, "One more step") and Enabled(w, "Reload now"), "waiting for a reload: one more step")
  -- real asynchronous checking: the check after a reload is scheduled and has not run
  local L = k.TwichUI.LayoutsLauncher
  L.scheduled, L.continued = true, nil
  WK.Model.Session().appliedHere = nil
  Show()
  Check(Says(w, "Setup is still being checked") and not Has(w, "Reload now") and not Says(w, "Your interface is ready"), "while the check after a reload is genuinely still to run: still being checked")
  L.continued = true
  Show()
  Check(Says(w, "One more step"), "once it has run (and left it waiting), that is no longer said")
  -- restored and undone
  MK.Session().restored = true
  LY.Journal.Clear()
  LY.Journal.Forget()
  MK.Invalidate()
  Show()
  Check(Says(w, "Previous setup restored") and Has(w, "Done") and not Says(w, "Your interface is ready"), "restored: its own heading, Done")
  MK.Session().restored = false
  MK.Session().undone = true
  local k2 = Installed("Undone")
  local WK2 = k2.TwichUI.LayoutWizard
  WK2.Model.Session().undone = true
  WK2.Window.Refresh()
  Check(Says(k2.TwichUILayoutWizard, "Update undone") and not Says(k2.TwichUILayoutWizard, "Your interface is ready"), "an undone update: its own heading")
end

do
  -- Check again that finds a difference turns the dialog into "needs attention" without rewriting the record
  local k = Installed("Recheck", { accent = "dusk" })
  local w, WK = k.TwichUILayoutWizard, k.TwichUI.LayoutWizard
  local LY = k.TwichUI.Layouts
  k.EllesmereUIDB.profiles["TwichUI Adventure"].euiAccent = { useClass = true }
  local before = Copy(LY.Journal.Read())
  Expand(w, "Manage layout")
  Click(w, "Check again")
  Check(Says(w, "Setup needs attention") and Says(w, "Checked just now: mismatch") and not Says(w, "Your interface is ready") and not Has(w, "Done"), "a difference found by Check again is not shown as success")
  Check(Same(LY.Journal.Read(), before), "and the record is not rewritten by a read")
end

do
  -- Keep this setup is the explicit act that finishes recovery; Done never was
  local k = Installed("Keep")
  local w, WK = k.TwichUILayoutWizard, k.TwichUI.LayoutWizard
  local LY = k.TwichUI.Layouts
  Expand(w, "Manage layout")
  Click(w, "Keep this setup")
  Check(k.popup.text:find("Restore", 1, true) and k.popup.text:find("no longer be offered", 1, true), "Keep says what it discards before it does it")
  k.Decline()
  Check(LY.PlanRestore().ok, "declined: the way back is still there")
  Click(w, "Keep this setup"); k.Accept()
  Check(not LY.PlanRestore().ok and LY.Journal.ReadManaged() ~= nil, "accepted: the way back is gone, the layout is still managed")
  Check(Says(w, "Your interface is ready") and not Has(w, "Restore previous setup"), "and the dialog no longer offers what is gone")
end

---------------------------------------------------------------------------
-- 5. Small screens, and the first-install setup
---------------------------------------------------------------------------
do
  local k = Installed("Small")
  local w, WK = k.TwichUILayoutWizard, k.TwichUI.LayoutWizard
  k.UIParent.w, k.UIParent.h = 1024, 576
  WK.Window.Refresh()
  Expand(w, "Details") ; Expand(w, "Manage layout")
  local scale = w.scale or 1
  Check(w.h * scale <= k.UIParent.h - 48 + 0.5 and w.w * scale <= k.UIParent.w - 48 + 0.5, "even with Details and Manage layout open it is fitted inside a small screen (scale " .. string.format("%.2f", scale) .. ")")
end

if failures > 0 then error(failures .. " check(s) failed") end
print("LAYOUT COMPLETE TEST PASSED")
