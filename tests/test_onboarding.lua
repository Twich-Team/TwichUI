dofile(TESTS .. "harness.lua")
dofile(TESTS .. "layouts_mock.lua")
-- The first-install experience (Onboarding.lua, docs/onboarding.md): the layout setup offered on a new installation in place of
-- the old welcome dialog; its record and how older installations are migrated; opening by itself (once, out of the way, never
-- on a reload once put off, bounded); Do this later, Escape, the close box, Skip, EllesmereUI's own setup; an install made from
-- it waiting, failing, finishing; holding EllesmereUI's first-run module picker for it, never its look picker, and handing the
-- first run back when the setup is skipped or can't open; the dimming behind the window (layering, click-through, fade and
-- reduced motion, combat, the full-size preview, a failed open, reopening). Through the real core, engine and wizard with stand-in
-- frames and a stand-in EllesmereUI shaped as 9.6.8's first-run loaders are (layouts_mock.lua). Nothing here is the game.

META = { EllesmereUI = { Version = "9.6.8" } }

local failures = 0
local function Check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local Copy, Same, Heard, Says = LM.Copy, LM.Same, LM.Heard, LM.Says

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
-- Apply's label says what accepting does: "Apply & Reload" when the plan needs a reload, "Apply" when it doesn't
local function ApplyLabel(win) return Find(win, "Apply & Reload") and "Apply & Reload" or "Apply" end
local function Click(win, label)
  local b = Find(win, label)
  assert(b, "no visible button '" .. label .. "'")
  assert(b.enabled ~= false, "button '" .. label .. "' is disabled")
  b.scripts.OnClick(b)
end
-- Do this later: the footer's button on the six steps; on the compact result dialog (no footer) the window's own close, which the
-- first-install record reads the same way
local function Later(c)
  local w = c.TwichUILayoutWizard
  if Find(w, "Do this later") then Click(w, "Do this later") else c.TwichUI.LayoutWizard.Window.Close("later") end
end
local function Enabled(win, label) local b = Find(win, label) return b ~= nil and b.enabled ~= false end
local function Has(win, label) return Find(win, label) ~= nil end

local function Settle() for _ = 1, 4 do FlushTimers(); RunLongTimers(10) end end
local function Boot(name, sv, opts)
  opts = opts or {}
  opts.onboarding = true
  local c, S = LM.Boot(name, sv, opts)
  Settle()
  return c, S
end
local function Ob(c) return c.TwichUIDB.onboarding end
local function Win(c) return c.TwichUILayoutWizard end
local function Shown(c) return Win(c) ~= nil and Win(c).shown == true end
local function Scrim(c) return c.TwichUILayoutWizardScrim end
local function Dimmed(c) return Scrim(c) ~= nil and Scrim(c).shown == true end
local function WZ(c) return c.TwichUI.LayoutWizard end
local function Step(c) return WZ(c).Model.Step() end
local function ToReview(w) for i = 1, 4 do Click(w, i == 1 and "Get started" or "Next") end end
-- the saved variables as a later session finds them (a reload when reload = true, else a login)
local function Again(c, name, opts)
  local sv = LM.Logout(c)
  return Boot(name, sv, opts)
end
local function Without(sv, path)   -- a copy of saved variables without TwichUIDB.<path>
  local out = Copy(sv)
  out.TwichUIDB[path] = nil
  return out
end
local function NewSaid(c) local n = #c.said return function(text) for i = n + 1, #c.said do if c.said[i]:find(text, 1, true) then return true end end return false end end

---------------------------------------------------------------------------
-- 1. A new installation, with EllesmereUI's first run too: one setup, opened once, EllesmereUI's picker held for it
---------------------------------------------------------------------------
do
  local c = Boot("Fresh", nil, { eui = { firstRun = true } })
  local E = c.E
  Check(Ob(c) and Ob(c).v == 1, "a new installation has an onboarding record")
  Check(Shown(c) and c.wizardLoads == 1, "the setup opened by itself once the game was ready")
  Check(Ob(c).state == "started" and Ob(c).offers == 1, "opening it is 'started', never 'done'")
  Check(c.TwichUIWelcome == nil, "the old welcome dialog did not appear (nor was it built)")
  Check(E._externalInstaller == "TwichUI" and Ob(c).held == true, "EllesmereUI's first run is held for TwichUI's setup")
  Check(E.pickerShown == nil, "EllesmereUI's module picker did not appear (nor flash: the registration came before its timer)")
  Check(E.styleShown == nil and E.styleStamped == nil and c.EllesmereUIDB.styleChoicePending == true,
    "its look picker waits for its first run by its own rule: not shown, and not stamped as answered")
  local w = Win(c)
  Check(Says(w, "Make yourself at home") and Says(w, "backed up when you do") and Says(w, "every character on this account"),
    "the first page greets and says what it does, the backup made when you apply and the account-wide part")
  Check(Says(w, "Nothing changes until you apply"), "and that nothing applies until confirmed")
  Check(Has(w, "Do this later") and not Has(w, "Close") and Has(w, "Skip setup") and Has(w, "Use EllesmereUI's setup instead"),
    "Do this later, Skip setup and EllesmereUI's own setup are offered")
  Check(Says(w, "EllesmereUI's first-run setup is waiting for this one") and not Says(w, "Blocked"), "EllesmereUI's pending first run is said, not a block")
  Check(Enabled(w, "Get started"), "so setup can start: no deadlock on EllesmereUI's pending flag")
  -- once a session: more world entries and time open nothing more
  c.FireEvent("PLAYER_ENTERING_WORLD", false, false); Settle()
  Check(Ob(c).offers == 1 and c.wizardLoads == 1, "a loading screen doesn't offer it again")

  -- through to an install: the plan isn't blocked, the import answers EllesmereUI's first run
  ToReview(w)
  Check(Enabled(w, ApplyLabel(w)), "Apply is offered (EllesmereUI's first run held for TwichUI doesn't block the plan)")
  Click(w, ApplyLabel(w))
  Check(c.popup and c.popup.key == "TWICHUI_LAYOUT_APPLY" and Dimmed(c), "the question is the game's own dialog, over the dimming")
  c.Accept()
  Check(Step(c) == 6 and c.TwichUI.Layouts.Journal.Read().state == "applied", "applied, waiting for the reload")
  Check(E._firstInstallPending == nil and c.EllesmereUIDB.firstInstallPopupShown == true and c.EllesmereUIDB.styleChoicePending == nil,
    "EllesmereUI's import stamped its own first-install state (the supported completion)")
  Check(Ob(c).state == "started", "not done before the reload and its check")
  Check(c.reloads == 1 and Ob(c).state == "started", "Apply & Reload reloaded once, and the first install is not done by a reload alone")

  -- the reload: EllesmereUI stays held, the check runs, the setup shows its result, and only now is onboarding done
  local r = Again(c, "Fresh", { reload = true })
  Check(r.E._externalInstaller == "TwichUI" and r.E.pickerShown == nil and r.E.styleShown == nil, "no native picker during the setup's own reload")
  Check(Shown(r) and Step(r) == 6 and Says(Win(r), "Your interface is ready"), "the result is shown after the reload")
  Check(Ob(r).state == "done" and Ob(r).why == "verified" and Ob(r).held == nil, "done once the install checked out")
  Check(r.wizardLoads == 1, "loaded once")
  Check(not Has(Win(r), "Do this later") and not Has(Win(r), "Skip setup") and Has(Win(r), "Done"), "no first-run choices once done, and Done closes the compact result")

  -- later logins: nothing, and the wizard isn't loaded to find that out
  local l = Again(r, "Fresh")
  Check(not Shown(l) and l.wizardLoads == 0 and l.layoutLoads == 0, "a finished setup: a login loads nothing")
  Check(l.E._externalInstaller == nil and Ob(l).state == "done", "and holds nothing of EllesmereUI's")
  -- asked for by hand: opens, and changes nothing about onboarding
  l.SlashCmdList.TWICHUI("layout")
  Check(Shown(l) and Ob(l).state == "done", "opened by hand after it is done: still done")
  l.PressEsc()
  Check(Ob(l).state == "done" and not Heard(l, "put off"), "and closing it is not a deferral")
end

---------------------------------------------------------------------------
-- 2. Do this later, Escape, the close box: put off, not again this session or on a reload, again at a login, bounded
---------------------------------------------------------------------------
do
  local c = Boot("Later", nil, { eui = { firstRun = true } })
  Check(Shown(c) and Dimmed(c), "opened, dimmed")
  local said = NewSaid(c)
  Later(c)
  Check(not Shown(c) and not Dimmed(c), "Do this later closes it, and the dimming goes with it")
  Check(Ob(c).state == "deferred" and Ob(c).why == "later", "put off")
  Check(said("layout setup put off") and said("next time you log in") and said("held back for it"), "said once, with when and where, and EllesmereUI's held setup")
  Check(c.E.nativeShown == nil and c.E._externalInstaller == "TwichUI", "EllesmereUI's setup is not shown on a deferral (it stays held this session)")
  c.FireEvent("PLAYER_ENTERING_WORLD", false, false); Settle()
  c.FireEvent("PLAYER_REGEN_ENABLED"); Settle()
  Check(not Shown(c) and Ob(c).offers == 1, "not again this session")

  -- a reload (any addon's): nothing
  local r = Again(c, "Later", { reload = true })
  Check(not Shown(r) and r.wizardLoads == 0 and Ob(r).state == "deferred", "a reload doesn't bring it back")
  Check(r.E._externalInstaller == nil, "and holds nothing of EllesmereUI's")
  -- EllesmereUI's look picker (armed by its first run, never stamped by TwichUI) comes up by itself now; the player answers it
  Check(r.E.styleShown == 1 and r.E.styleStamped == nil, "EllesmereUI's own look picker shows after the deferral, unsuppressed")
  r.EllesmereUIDB.styleChoicePending = nil

  -- (with nothing else in the way) a reload never brings back a put-off or unanswered setup; a login does
  for _, st in ipairs({ "deferred", "started" }) do
    local rl = Boot("Reload-" .. st, { TwichUIDB = { schema = 2, modules = {}, onboarding = { v = 1, state = st, offers = 1, why = "later" } } }, { reload = true })
    Check(not Shown(rl) and rl.wizardLoads == 0 and Ob(rl).offers == 1, st .. ": a reload opens nothing and loads nothing")
    local li = Boot("Login-" .. st, { TwichUIDB = { schema = 2, modules = {}, onboarding = { v = 1, state = st, offers = 1, why = "later" } } })
    Check(Shown(li) and Ob(li).offers == 2, st .. ": a login offers it")
  end

  -- a login: again, and Escape is a deferral too
  local l2 = Again(r, "Later")
  Check(Shown(l2) and Ob(l2).offers == 2, "the next login offers it again")
  Check(Has(Win(l2), "Use EllesmereUI's setup instead"), "EllesmereUI's own setup is still offered (held earlier, not run since)")
  l2.PressEsc()
  Check(Ob(l2).state == "deferred" and Ob(l2).why == "closed" and not Dimmed(l2), "Escape puts it off and lifts the dimming")

  -- third login: the close box (it hides the window) is the same; and that was the last automatic offer
  local l3 = Again(l2, "Later")
  Check(Shown(l3) and Ob(l3).offers == 3, "a third offer")
  local said3 = NewSaid(l3)
  Win(l3):Hide()
  Check(Ob(l3).state == "deferred" and said3("won't open it by itself again"), "the close box too; and it says no more offers come")
  local l4 = Again(l3, "Later")
  Check(not Shown(l4) and l4.wizardLoads == 0, "after the bound, nothing opens by itself")
  l4.SlashCmdList.TWICHUI("layout")
  Check(Shown(l4) and Has(Win(l4), "Do this later"), "it still opens when asked, as the first-install setup")
end

---------------------------------------------------------------------------
-- 3. Skip setup, and EllesmereUI's own setup instead: never an install; the first run handed back to EllesmereUI
---------------------------------------------------------------------------
do
  local c = Boot("Skip", nil, { eui = { firstRun = true } })
  local before = Copy(c.EllesmereUIDB)
  local tw = Copy(c.TwichUIDB.modules)
  Click(Win(c), "Skip setup")
  Check(c.popup and c.popup.key == "TWICHUI_LAYOUT_SKIP" and c.popup.text:find("Nothing is applied", 1, true)
    and c.popup.text:find("EllesmereUI's own first-run setup was held back", 1, true), "Skip asks, and says EllesmereUI's setup follows")
  c.Decline()
  Check(Shown(c) and Ob(c).state == "started", "declining changes nothing")
  Click(Win(c), "Skip setup"); c.Accept()
  Check(not Shown(c) and not Dimmed(c) and Ob(c).state == "skipped" and Ob(c).why == "user", "skipped: closed, not deferred")
  Check(c.E.nativeShown == 1 and Heard(c, "EllesmereUI's own first-run setup is shown instead"), "EllesmereUI's own picker is shown (fail-open)")
  Check(not Heard(c, "put off"), "not called a deferral")
  Check(c.E.called("ImportProfileSilent") == 0 and Same(c.EllesmereUIDB.profiles, before.profiles) and Same(c.TwichUIDB.modules, tw),
    "nothing was applied: no import, no profile, no switch")
  Check(c.TwichUI.Layouts.Journal.Read() == nil, "no install record")
  local l = Again(c, "Skip", { eui = { firstRun = false } })
  Check(not Shown(l) and l.wizardLoads == 0 and l.E._externalInstaller == nil, "a later login: nothing opens, nothing held")

  -- EllesmereUI's setup instead (it asks, refuses in combat)
  local n = Boot("Native", nil, { eui = { firstRun = true } })
  Click(Win(n), "Use EllesmereUI's setup instead")
  Check(n.popup and n.popup.key == "TWICHUI_LAYOUT_NATIVE", "asks first")
  n.combat = true
  n.Accept()
  Check(Shown(n) and Ob(n).state == "started" and n.E.nativeShown == nil, "in combat: refused, nothing changed")
  n.combat = false
  Click(Win(n), "Use EllesmereUI's setup instead"); n.Accept()
  Check(Ob(n).state == "skipped" and Ob(n).why == "native" and n.E.nativeShown == 1 and not Shown(n), "EllesmereUI's own setup, TwichUI's closed")

  -- Skip with nothing of EllesmereUI's held: no native picker
  local p = Boot("Plain", nil, {})
  Check(Shown(p) and p.E._externalInstaller == nil and not Has(Win(p), "Use EllesmereUI's setup instead"), "EllesmereUI already set up: nothing held, no native offer")
  Click(Win(p), "Skip setup"); p.Accept()
  Check(Ob(p).state == "skipped" and p.E.nativeShown == nil and Heard(p, "skipped. Type /tui layout"), "skipped, said, nothing of EllesmereUI's shown")
  -- an EllesmereUI without the exported picker: said, nothing called
  local q = Boot("NoNative", nil, { eui = { firstRun = true, noNative = true } })
  Check(not Has(Win(q), "Use EllesmereUI's setup instead"), "no exported picker: not offered")
  Click(Win(q), "Skip setup"); q.Accept()
  Check(Heard(q, "isn't available from here") and Ob(q).state == "skipped", "Skip says where its choices are instead")
end

---------------------------------------------------------------------------
-- 4. EllesmereUI: which picker is held, when, and when not
---------------------------------------------------------------------------
do
  -- loads before TwichUI: still held (registration is at login, when every addon's first-run flags are up)
  local a = Boot("Before", nil, { eui = { firstRun = true, euiFirst = true } })
  Check(a.E._externalInstaller == "TwichUI" and a.E.pickerShown == nil and Shown(a), "EllesmereUI loaded first: held, and the setup opens")

  -- a session where only its look picker is due (the login after a deferral): never held, so never stamped as answered;
  -- the setup waits for it
  local s = Boot("Style", { TwichUIDB = { onboarding = { v = 1, state = "deferred", offers = 1, why = "later", held = true } } }, { eui = { stylePending = true } })
  Check(s.E._externalInstaller == nil and s.E.styleShown == 1 and s.E.styleStamped == nil, "its look picker shows, and is not stamped by a registration")
  Check(not Shown(s) and s.TwichUI.Onboarding.Snapshot().lastWait == "ellesmereui-style", "the setup waits for EllesmereUI's look picker")
  s.EllesmereUIDB.styleChoicePending = nil   -- the player answered it (every close of it stamps)
  s.FireEvent("PLAYER_ENTERING_WORLD", false, false); Settle()
  Check(Shown(s) and Ob(s).offers == 2, "then the setup opens")

  -- not a new installation: EllesmereUI's own first run is left alone
  local e = Boot("Existing", { TwichUIDB = { schema = 2, modules = {}, welcome = { state = "seen" } } }, { eui = { firstRun = true } })
  Check(Ob(e).state == "existing" and e.E._externalInstaller == nil and e.E.pickerShown == 1, "an existing user: EllesmereUI's picker shows as it always did")
  Check(not Shown(e) and e.wizardLoads == 0, "and nothing of TwichUI's opens")

  -- the setup can't load: EllesmereUI is not held, its own picker shows; nothing opens
  for _, case in ipairs({ { wizardMissing = true }, { wizardDisabled = true }, { layoutsMissing = true } }) do
    case.eui = { firstRun = true }
    local m = Boot("Missing", nil, case)
    Check(m.E._externalInstaller == nil and m.E.pickerShown == 1, "a setup that can't load: EllesmereUI's picker is not held")
    local snap = m.TwichUI.Onboarding.Snapshot()
    Check(snap.reasons[1] == "hold-missing" or snap.reasons[1] == "hold-disabled", "the reason is kept (" .. tostring(snap.reasons[1]) .. ")")
  end
  -- loads, but fails to open: the held first run is handed back at once, and said
  local b = Boot("Broken", nil, { eui = { firstRun = true }, wizardBroken = true })
  Check(b.E._externalInstaller == "TwichUI" and b.E.nativeShown == 1, "a setup that loaded but didn't start: EllesmereUI's own picker is shown instead")
  Check(Heard(b, "couldn't open the layout setup") and Heard(b, "EllesmereUI's own first-run setup is shown instead"), "both said")
  Check(Ob(b).state == "new" and b.TwichUI.Life.Snapshot().notes["onboarding-load-failed"] == 1, "not started; counted for the report")

  -- an EllesmereUI without the partner API, or with another installer registered: not held, and the setup waits
  local n = Boot("NoApi", nil, { eui = { firstRun = true, noInstallerApi = true } })
  Check(n.E.pickerShown == 1 and n.TwichUI.Onboarding.Snapshot().reasons[1] == "hold-no-api", "no RegisterExternalInstaller: EllesmereUI's picker shows")
  Check(not Shown(n) and n.TwichUI.Onboarding.Snapshot().lastWait == "ellesmereui-setup", "and the setup waits rather than open over it")
  local o = Boot("Other", nil, { eui = { firstRun = true, installer = "Someone" } })
  Check(o.E._externalInstaller == "Someone" and o.TwichUI.Onboarding.Snapshot().reasons[1] == "hold-other-installer", "another installer's registration is not taken over")
  Check(not Shown(o), "and the setup doesn't open over its first run")
  o.SlashCmdList.TWICHUI("layout")
  Check(Says(Win(o), "first-run setup is still waiting") and not Enabled(Win(o), "Get started"), "opened by hand: the other installer's pending first run still blocks, with its reason")
end

---------------------------------------------------------------------------
-- 5. Older installations: migrated, never put through a fresh first run
---------------------------------------------------------------------------
do
  -- a finished, managed install from before onboarding
  local k = LM.Boot("Old")
  k.SlashCmdList.TWICHUI("layout")
  ToReview(Win(k)); Click(Win(k), ApplyLabel(Win(k))); k.Accept()
  local k2 = LM.Boot("Old", LM.Logout(k))
  Settle()
  Check(k2.TwichUI.Layouts.Journal.Read().state == "verified", "an install checked out (without onboarding loaded)")
  local managedSv = Without(LM.Logout(k2), "onboarding")
  local m = Boot("Old", managedSv)
  Check(Ob(m).state == "done" and Ob(m).why == "migrated-managed" and not Shown(m) and m.wizardLoads == 0, "a managed install: done, nothing opens")

  -- a welcome-only user (the old dialog seen): existing, not offered
  local w = Boot("Seen", { TwichUIDB = { schema = 2, modules = {}, welcome = { state = "seen" } } })
  Check(Ob(w).state == "existing" and Ob(w).why == "migrated" and not Shown(w), "the old welcome seen: an existing user, not offered by itself")
  -- an older new installation still owed the old welcome: a new user
  local p = Boot("Pending", { TwichUIDB = { schema = 2, modules = {}, welcome = { state = "pending" } } })
  Check(Shown(p) and Ob(p).state == "started" and Ob(p).offers == 1, "still owed the old welcome, nothing installed: offered as a new installation")
  -- an install left unfinished before onboarding: existing (its result is where it always was)
  local j = Copy(managedSv)
  j.TwichUIDB.layouts.managed = nil
  local u = Boot("Unfinished", j)
  Check(Ob(u).state == "existing" and not Shown(u), "an install record without management: existing, nothing opens")
  -- damaged and newer records
  local d = Boot("Damaged", { TwichUIDB = { schema = 2, modules = {}, onboarding = "junk" } })
  Check(Ob(d).state == "existing" and Ob(d).why == "repaired" and not Shown(d), "an unreadable record: existing, never a fresh offer")
  local bad = Boot("BadState", { TwichUIDB = { schema = 2, modules = {}, onboarding = { v = 1, state = "maybe", offers = "x" } } })
  Check(Ob(bad).state == "existing" and Ob(bad).offers == 0, "an unknown state, narrowly repaired")
  local newer = { v = 2, state = "something", extra = { 1 } }
  local nv = Boot("Newer", { TwichUIDB = { schema = 2, modules = {}, onboarding = Copy(newer) } })
  Check(Same(Ob(nv), newer) and not Shown(nv), "a newer TwichUI's record: left exactly as it is, nothing opens")
  nv.SlashCmdList.TWICHUI("layout firstrun reset")
  Check(Same(Ob(nv), newer) and Heard(nv, "made by a newer TwichUI"), "and reset refuses to write over it")
  -- an addon update never resets it
  local up = Boot("Update", { TwichUIDB = { schema = 2, modules = {}, onboarding = { v = 1, state = "skipped", offers = 1, why = "user" } } })
  Check(Ob(up).state == "skipped" and not Shown(up), "a later version keeps the state as it was")
  -- the record is the account's: another character finds the same state
  local alt = Boot("Alt", { TwichUIDB = { schema = 2, modules = {}, onboarding = { v = 1, state = "deferred", offers = 1, why = "later" } } })
  Check(Shown(alt) and Ob(alt).offers == 2, "another character, at a login: a put-off setup is offered (one record per account)")
  local alt2 = Boot("Alt2", { TwichUIDB = { schema = 2, modules = {}, onboarding = { v = 1, state = "done", offers = 0, why = "verified" } } })
  Check(not Shown(alt2) and alt2.wizardLoads == 0, "a finished account: a new character isn't offered it")
end

---------------------------------------------------------------------------
-- 6. An install made from it: waiting, a reload the player made, a clean failure, a part-way failure, restore
---------------------------------------------------------------------------
do
  -- applied and closed without the button's reload: 'installing', not put off; the player's own /reload finishes it
  local c = Boot("Wait", nil, {})
  ToReview(Win(c)); Click(Win(c), ApplyLabel(Win(c))); c.AcceptHeld()   -- the reload didn't start; the player's own /reload follows
  Later(c)
  Check(Ob(c).state == "installing" and Ob(c).why == "applied" and not Heard(c, "put off"), "closed after Apply: an install is waiting, not a deferral")
  local r = Again(c, "Wait", { reload = true })
  Check(r.TwichUI.Layouts.Journal.Read().state == "verified" and Ob(r).state == "done" and not Shown(r), "checked after the player's own reload: done, chat only")

  -- a clean failure: nothing changed, still the first-install setup
  local f = Boot("Fail", nil, { eui = { failImport = true } })
  ToReview(Win(f)); Click(Win(f), ApplyLabel(Win(f))); f.Accept()
  Check(Says(Win(f), "Nothing was changed") and Ob(f).state == "started", "a refused import: still started")
  Later(f)
  Check(Ob(f).state == "deferred", "and closing puts it off as usual")

  -- part way: the setup reopens on its result (recovery), never on the layout choice
  local p = Boot("Part", nil, {})
  p.TwichUI.Layouts.ADAPTERS.twichui.Apply = function() return { state = "failed", code = "write", rollback = "clean" } end
  ToReview(Win(p)); Click(Win(p), ApplyLabel(Win(p))); p.Accept()
  Check(p.TwichUI.Layouts.Journal.Read().state == "partial", "partial")
  Later(p)
  Check(Ob(p).state == "installing", "closed: an install under way")
  local p2 = Again(p, "Part", { reload = true })
  Check(Shown(p2) and Step(p2) == 6 and Says(Win(p2), "Setup needs attention") and Enabled(Win(p2), "Restore previous setup"),
    "after a reload it opens on the result, with Restore (not the first step)")
  Check(not Has(Win(p2), "Skip setup") and Ob(p2).offers == 1, "no Skip over an install under way; one offer counted")
  Click(Win(p2), "Restore previous setup"); p2.Accept(); Click(Win(p2), "Reload now")
  local p3 = Again(p2, "Part", { reload = true })
  Check(p3.TwichUI.Layouts.Journal.Read() == nil and Ob(p3).state == "skipped" and Ob(p3).why == "restored", "restored: the player went back; not offered again")

  -- interrupted (the game stopped part way): opens on the result at the next login
  local i = Boot("Cut", nil, {})
  ToReview(Win(i)); Click(Win(i), ApplyLabel(Win(i))); i.Accept()
  local LY = i.TwichUI.Layouts
  local j = LY.Journal.Read(); j.state = "applying"; LY.Journal.Write(j)
  local i2 = Again(i, "Cut")
  Check(Shown(i2) and Step(i2) == 6 and Says(Win(i2), "The game stopped before the setup finished.") and Ob(i2).state == "installing", "interrupted: the result, with what to do")
end

---------------------------------------------------------------------------
-- 7. Waiting for the game: combat, flights, a hidden interface, cards, the check after a reload; bounded
---------------------------------------------------------------------------
do
  for name, set in pairs({
    combat = function(cl, on) cl.combat = on end,
    flight = function(cl, on) cl.UnitOnTaxi = function() return on end end,
    interface = function(cl, on) cl.UIParent.shown = not on end,
  }) do
    local cl = Boot("Wait-" .. name, nil, { setup = function(x) set(x, true) end })
    local O = cl.TwichUI.Onboarding
    Check(not Shown(cl) and O.Snapshot().lastWait ~= nil and Ob(cl).state == "new", name .. ": held back, still new (" .. tostring(O.Snapshot().lastWait) .. ")")
    Check(cl.TwichUI.Life.Snapshot().notes["onboarding-waited"], name .. ": counted for the report")
    set(cl, false)
    cl.FireEvent("PLAYER_REGEN_ENABLED"); Settle()
    Check(Shown(cl) and Ob(cl).offers == 1, name .. ": opened when clear, once")
  end

  -- bounded: constant combat makes a fixed number of looks, then waits for the end of combat
  local cl = Boot("Bound", nil, { setup = function(x) x.combat = true end })
  local O = cl.TwichUI.Onboarding
  for _ = 1, 60 do
    if not O.Snapshot().waiting then break end
    FlushTimers(); RunLongTimers(10)
  end
  local s = O.Snapshot()
  Check(not s.waiting and s.tries == O.MAX_TRIES and not Shown(cl), "stops looking after a fixed number of looks (" .. tostring(s.tries) .. ")")
  cl.combat = false
  cl.FireEvent("PLAYER_REGEN_ENABLED"); Settle()
  Check(Shown(cl), "the end of the fight starts it again")
  -- combat while it is open: the window stays (the setup's own policy), the dimming lifts, nothing is put off or changed
  -- (the window's own event frame is a stand-in the harness doesn't send events to: given them directly)
  local ev = WZ(cl).Window.evframe
  cl.combat = true
  cl.FireEvent("PLAYER_REGEN_DISABLED")
  ev.scripts.OnEvent(ev, "PLAYER_REGEN_DISABLED")
  Check(Shown(cl) and not Dimmed(cl) and Ob(cl).state == "started", "combat with it open: still open, undimmed, still started")
  cl.combat = false
  cl.FireEvent("PLAYER_REGEN_ENABLED")
  ev.scripts.OnEvent(ev, "PLAYER_REGEN_ENABLED")
  Check(Dimmed(cl) and Ob(cl).offers == 1, "dimmed again after, and not offered a second time")

  -- a TwichUI card up: it waits; the card is neither dropped nor hurried
  local dismissed = 0
  local cd = Boot("Card", nil, { setup = function(x)
    local N = x.TwichUI.Notify
    N.Register("obtest", { label = "test", show = function() return true end, dismiss = function() dismissed = dismissed + 1 end,
      bounds = function() return 0, 0, 10, 10 end, hold = function() return 100 end })
    x.cardUp = N.Submit({ kind = "obtest", id = "one", payload = {} })
  end })
  Check(cd.cardUp and not Shown(cd) and dismissed == 0 and cd.TwichUI.Onboarding.Snapshot().lastWait == "cards", "it waits for a card, which is left alone")
  cd.TwichUI.Notify.Finished("obtest")
  cd.FireEvent("PLAYER_ENTERING_WORLD", false, false); Settle()
  Check(Shown(cd), "and opens once the card is gone")
end

do
  -- the check after a layout reload runs first, and a result it opens is this session's offer
  local c = Boot("Order", nil, {})
  ToReview(Win(c)); Click(Win(c), ApplyLabel(Win(c))); c.Accept()
  local r = Again(c, "Order", { reload = true })
  Check(Shown(r) and r.wizardLoads == 1 and Ob(r).state == "done", "one window: the result, opened by the check; onboarding then done")
  -- even when the check is late: the setup waits for it rather than open on a record that is about to change
  local d = Boot("Late", nil, {})
  ToReview(Win(d)); Click(Win(d), ApplyLabel(Win(d))); d.AcceptHeld()   -- the wizard's own reload didn't start: no note
  Later(d)   -- closed after Apply: installing
  local late = Again(d, "Late", { reload = true, setup = function(x) x.TwichUI.LayoutsLauncher.CONTINUE_AFTER = 60 end })
  Check(not Shown(late) and late.TwichUI.Onboarding.Snapshot().lastWait == "layouts" and Ob(late).state == "installing", "it waits for the check after the reload")
  RunLongTimers(60); Settle()
  Check(late.TwichUI.Layouts.Journal.Read().state == "verified" and Ob(late).state == "done" and not Shown(late), "the check ran; done, nothing opened over it")
end

---------------------------------------------------------------------------
-- 8. The dimming: layering, click-through, fade and reduced motion, combat, the screen, the preview, failures, reopening
---------------------------------------------------------------------------
do
  local c = Boot("Dim", nil, {})
  local w, sc = Win(c), Scrim(c)
  local W = WZ(c).Window
  Check(sc and Dimmed(c) and W.Scrim() == sc, "the scrim is up with the window")
  Check(sc.parent == c.UIParent and sc.allPoints == c.UIParent, "it covers UIParent, so it follows the screen size and UI scale by itself")
  Check(sc.strata == "HIGH" and w.strata == "HIGH" and sc:GetFrameLevel() < w:GetFrameLevel(), "below the window (same strata, lower level)")
  Check(sc.mouse ~= true and sc.keyboard ~= true, "click-through and keyboard-through")
  local tex = sc.tex
  Check(tex.color and math.abs(tex.color[4] - 0.40) < 1e-9 and tex.color[1] < 0.06 and tex.color[1] >= tex.color[3], "a warm charcoal at 40%")
  Check(not Find(sc, "Get started") and #sc.children == 1, "nothing on it but its texture: no ornament, no controls")
  -- the fade: from clear, to full, through the shared motion (no animation of its own)
  local Motion = c.TwichUI.Look.Motion
  W.Close("later")
  c.SlashCmdList.TWICHUI("layout")
  Check(sc.alpha < 1, "it fades in")
  Motion.Settle()
  Check(sc.alpha == 1, "to its full strength")
  W.Close("later")
  c.TwichUIDB.ui = c.TwichUIDB.ui or {}
  c.TwichUIDB.ui.reduceSettingsMotion = true
  c.SlashCmdList.TWICHUI("layout")
  Check(sc.alpha == 1, "with Reduce window motion: at once")
  c.TwichUIDB.ui.reduceSettingsMotion = nil
  -- the screen changing: still anchored, nothing rebuilt (the full-size preview is built once first, below it is reused)
  local Ov = WZ(c).Overlay
  Click(w, "Get started"); Click(w, "Next")
  Ov.Open(); Ov.Close("back")
  local made = c.made()
  c.UIParent.w, c.UIParent.h = 1600, 900
  W.evframe.scripts.OnEvent(W.evframe, "DISPLAY_SIZE_CHANGED")
  W.evframe.scripts.OnEvent(W.evframe, "UI_SCALE_CHANGED")
  Check(sc.allPoints == c.UIParent and Dimmed(c), "a screen or UI scale change: still covering the screen")
  -- combat lifts it (the window stays, as before); the end of combat brings it back
  c.combat = true
  W.evframe.scripts.OnEvent(W.evframe, "PLAYER_REGEN_DISABLED")
  Check(Shown(c) and not Dimmed(c), "combat: the window stays, the dimming lifts")
  c.combat = false
  W.evframe.scripts.OnEvent(W.evframe, "PLAYER_REGEN_ENABLED")
  Check(Dimmed(c), "after combat: dimmed again")
  -- the full-size preview has its own dimming: never both
  local ok = Ov.Open()
  Check(ok and Ov.IsShown() and not Dimmed(c) and not Shown(c), "the full-size preview: the window and its dimming are set aside (one scrim)")
  Ov.Close("back")
  Check(Shown(c) and Dimmed(c) and sc.alpha == 1, "back: the window and its dimming return, without fading again")
  Ov.Open(); Ov.Close("exit")
  Check(not Shown(c) and not Dimmed(c) and not Ov.IsShown(), "exit from the preview: both gone")
  Check(c.made() == made, "no frame was made by any of that")
  -- reopening: no new frames, no new listeners, no new hooks
  local listeners0 = {}
  c.TwichUI.ListenerCounts(listeners0)
  local frames0, hide0, show0 = c.made(), #(sc.hooks.OnHide or {}) + #(w.hooks.OnHide or {}), #(w.hooks.OnShow or {})
  for _ = 1, 8 do c.SlashCmdList.TWICHUI("layout"); c.PressEsc() end
  local listeners1 = {}
  c.TwichUI.ListenerCounts(listeners1)
  Check(c.made() == frames0 and Same(listeners0, listeners1) and #(w.hooks.OnShow or {}) == show0
    and #(sc.hooks.OnHide or {}) + #(w.hooks.OnHide or {}) == hide0, "eight opens and closes: no frame, listener or hook added")
  Check(W.listening == 0 and not Dimmed(c), "closed: nothing listening, nothing dimmed")
end

do
  -- an error while opening: nothing left on screen, the session ended, no deferral recorded
  local c = LM.Boot("Boom", { TwichUIDB = { schema = 2, modules = {}, onboarding = { v = 1, state = "existing", offers = 0 } } }, { onboarding = true })
  c.faults = 0
  c.geterrorhandler = function() return function() c.faults = c.faults + 1 end end   -- the error is expected: counted, not printed
  c.SlashCmdList.TWICHUI("layout")
  c.PressEsc()
  local WZc = WZ(c)
  local real = WZc.Pages.Build
  WZc.Pages.Build = function() error("boom") end
  -- a page not built yet fails as it is drawn (the third step's)
  WZc.Window.Open(1)
  WZc.Model.Session().reached = 3
  WZc.Window.Close()
  c.said = {}
  local okOpen = c.TwichUI.LayoutsLauncher.OpenWizard(3)
  Check(okOpen == false and Heard(c, "couldn't open the layout setup") and c.faults == 1, "the failure is said, and goes to the error handler once")
  Check(not Shown(c) and not Dimmed(c) and not WZc.Model.Active() and WZc.Window.listening == 0, "and the window, the dimming and the session are gone")
  Check(Ob(c).state == "existing" and not Heard(c, "put off"), "not taken as an answer")
  WZc.Pages.Build = real
  Check(c.TwichUI.LayoutsLauncher.OpenWizard() and Shown(c) and Dimmed(c), "it opens normally afterwards")
end

---------------------------------------------------------------------------
-- 9. The command, the report, and what the source never does
---------------------------------------------------------------------------
do
  local c = Boot("Cmd", { TwichUIDB = { schema = 2, modules = {}, onboarding = { v = 1, state = "done", offers = 0, why = "verified" } } })
  c.said = {}
  c.SlashCmdList.TWICHUI("layout firstrun")
  Check(Heard(c, "first-run setup: done (verified)") and c.wizardLoads == 0, "/tui layout firstrun: the state, without loading anything")
  local layoutsBefore = Copy(c.TwichUIDB.layouts)
  c.SlashCmdList.TWICHUI("layout firstrun reset")
  Check(Ob(c).state == "new" and Ob(c).why == "reset" and Same(c.TwichUIDB.layouts, layoutsBefore), "reset: new again, nothing else touched")
  local r = Again(c, "Cmd")
  Check(Shown(r), "offered again at the next login")
  local snap = r.TwichUI.Onboarding.Snapshot()
  Check(snap.state == "started" and snap.offered and snap.reasons[#snap.reasons] == "open", "the snapshot has states and codes")
  -- the troubleshooting report's start-up section (diag/Lifecycle.lua) says it, with codes and no name
  local chunk = assert(loadfile(ROOT .. "diag/Lifecycle.lua")); setfenv(chunk, r); chunk("!!!TwichUI", {})
  local text = r.TwichUI.Diag.Build()
  text = type(text) == "table" and (text.text or "") or text
  Check(type(text) == "string" and text:find("first-install setup: started (opened); automatic offers 1", 1, true) ~= nil, "the report says the state, why and the offers")
  Check(text:find("offered yes", 1, true) ~= nil and text:find("open", 1, true) ~= nil, "and this session's codes")
  local _, at = text:find("first-install setup", 1, true)
  local section = at and text:sub(at, at + 400) or ""
  Check(not section:find("Cmd", 1, true), "no character name in it")

  -- what the source never does: no hiding of other frames, no global dialog hooks, no polling, no frame scans
  for _, f in ipairs({ ROOT .. "Onboarding.lua", ROOT .. "LayoutsLauncher.lua", REPO .. "TwichUI_LayoutWizard/Window.lua" }) do
    local src = io.open(f):read("*a")
    local name = f:match("([^/]+)$")
    Check(not src:find("hooksecurefunc", 1, true) and not src:find("StaticPopup_Show%s*=") and not src:find("EnumerateFrames", 1, true)
      and not src:find("GetChildren", 1, true) and not src:find("OnUpdate", 1, true), name .. ": no global hooks, frame scans or per-frame work")
    Check(not src:find("_firstInstallPending%s*=[^=]") and not src:find("styleChoicePending%s*=[^=]") and not src:find("firstInstallPopupShown%s*=[^=]")
      and not src:find("_externalInstaller%s*=[^=]"), name .. ": never writes EllesmereUI's first-run flags")
  end
  local ob = io.open(ROOT .. "Onboarding.lua"):read("*a")
  Check(not ob:find("EUIFirstInstall", 1, true) and not ob:find("EUIStyleChoice", 1, true), "no EllesmereUI frame is looked up by name, let alone hidden")
  local toc = io.open(ROOT .. "!!!TwichUI.toc"):read("*a")
  local a, b = toc:find("LayoutsLauncher.lua", 1, true), toc:find("Onboarding.lua", 1, true)
  Check(a and b and a < b, "Onboarding.lua loads after the launcher it uses")
end

if failures > 0 then error(failures .. " onboarding check(s) failed") end
print("ONBOARDING TESTS PASSED")
