dofile(TESTS .. "harness.lua")
dofile(TESTS .. "layouts_mock.lua")
-- The first-run welcome (FirstRunWelcome.lua, called by Onboarding.lua): shown only for the opening a new installation makes by
-- itself; before the setup is ready it fills the wait; the setup opens once, then the welcome fades out and releases everything;
-- a setup that can't open, a long wait, a dialog of EllesmereUI's, combat or Dismiss end it without marking anything done; reduced
-- motion shows it still. Through the real core and wizard with stand-in frames (layouts_mock.lua); the animation itself is not run.

META = { EllesmereUI = { Version = "9.6.8" } }

local failures = 0
local function Check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local Says = LM.Says

local function Settle() for _ = 1, 4 do FlushTimers(); RunLongTimers(10) end end
local function Boot(name, sv, opts)
  opts = opts or {}
  opts.onboarding = true
  local c, S = LM.Boot(name, sv, opts)
  Settle()
  return c, S
end
-- a new installation whose setup is held back by a flight path (the player is on a taxi) until c.taxi = false
local function Waiting(name, extra)
  local opts = { eui = { firstRun = true }, setup = function(c) c.taxi = true; c.UnitOnTaxi = function() return c.taxi end end }
  for k, v in pairs(extra or {}) do opts[k] = v end
  return Boot(name, nil, opts)
end
local function Ob(c) return c.TwichUIDB.onboarding end
local function Root(c) return c.TwichUIFirstRunWelcome end
local function Up(c) return Root(c) ~= nil and Root(c).shown == true end
local function Snap(c) return c.TwichUI.FirstRunWelcome.Snapshot() end
local function Wizard(c) return c.TwichUILayoutWizard ~= nil and c.TwichUILayoutWizard.shown == true end
-- every frame and texture under f, depth first
local function Each(f, fn) fn(f) for _, ch in ipairs(f.children or {}) do Each(ch, fn) end end
local function Playing(c)
  local n = 0
  Each(Root(c), function(f) if f.groups then for _, g in ipairs(f.groups) do if g.playing then n = n + 1 end end end end)
  return n
end

-- 1. Waiting: the welcome is up before the setup; the setup is not opened by it and nothing is answered
do
  local c = Waiting("Wait")
  Check(Up(c) and Snap(c).phase == "showing", "the welcome shows while the setup waits")
  Check(not Wizard(c) and c.wizardLoads == 0, "the setup is not loaded or opened yet")
  Check(Says(Root(c), "Welcome to TwichUI") and Says(Root(c), "Preparing your setup"), "it says the two lines it is meant to")
  Check(not Says(Root(c), "%"), "no percentage")
  Check(Ob(c).state == "new" and Ob(c).offers == 0 and c.reloads == 0, "it changed no record and started no reload")
  Check(Root(c):GetFrameStrata() == "HIGH" and not Root(c).mouse, "it takes no mouse and sits at the setup's strata")
  Check(c.E._externalInstaller == "TwichUI" and c.E.pickerShown == nil, "EllesmereUI's picker stays held while it is up")
  c.FireEvent("PLAYER_ENTERING_WORLD", false, false); Settle()
  Check(Snap(c).shown == 1 and c.TwichUI.FirstRunWelcome.Show() == false, "one welcome per session, however often it is asked")
  -- the player leaves the flight: the setup opens exactly once, the welcome goes and leaves nothing running
  c.taxi = false
  Settle()
  Check(Wizard(c) and c.wizardLoads == 1 and Ob(c).offers == 1, "once ready the setup opened once")
  Check(not Up(c) and Snap(c).phase == "ended" and Snap(c).why == "handoff", "and the welcome ended by the handoff")
  local dismiss
  Each(Root(c), function(f) if f.kind == "Button" then dismiss = f end end)
  Check(dismiss and not dismiss.shown and not dismiss.mouse, "Dismiss went with it and takes no mouse")
  Check(Playing(c) == 0 and not Snap(c).fading, "no animation or fade left running")
  Check(c.E._externalInstaller == "TwichUI", "EllesmereUI's setup is still held during the setup")
  c.FireEvent("PLAYER_ENTERING_WORLD", false, false); Settle()
  Check(not Up(c) and c.wizardLoads == 1 and Snap(c).shown == 1, "a later loading screen shows and opens nothing more")
end

-- 2. Ready at once: shown, then handed off without the wait
do
  local c = Boot("Ready", nil, {})
  Check(Wizard(c) and not Up(c) and Snap(c).phase == "ended" and Snap(c).why == "handoff", "a ready setup: the welcome came and handed off")
  Check(Snap(c).shown == 1 and Playing(c) == 0, "shown once, nothing running")
end

-- 3. Not for ordinary starts: a finished setup, a reload of a started one, a skipped one
do
  local c = Boot("Ready2", nil, {})
  local sv = LM.Logout(c)
  local r = Boot("Ready2", sv, {})   -- state "started": offered again at a login, but it is not a new installation
  Check(Wizard(r) and Root(r) == nil, "a started setup offered again: no welcome (never even built)")
  for _, state in ipairs({ "done", "skipped", "existing" }) do
    local s = LM.Logout(c)
    s.TwichUIDB.onboarding = { v = 1, state = state, offers = 0 }
    local d = Boot("Ready2", s, {})
    Check(Root(d) == nil and not Wizard(d), "state " .. state .. ": no welcome and no setup")
  end
end

-- 4. A setup that can't open: the welcome ends at once, nothing is marked done
do
  local c = Waiting("Broken", { wizardBroken = true })
  Check(Up(c), "shown while waiting")
  c.taxi = false
  Settle()
  Check(not Up(c) and Snap(c).why == "failed" and Playing(c) == 0, "a setup that doesn't come up ends the welcome at once")
  Check(Ob(c).state == "new" or Ob(c).state == "started", "and nothing is marked done")
  Check(Ob(c).state ~= "done" and Ob(c).state ~= "skipped", "or skipped")
end

-- 5. Never ready: the looks run out, the welcome goes, the record is untouched
do
  local c = Waiting("Never")
  for _ = 1, 40 do FlushTimers(); RunLongTimers(10) end
  Check(not Up(c) and Snap(c).why == "gave-up" and Ob(c).state == "new", "the waits run out: the welcome is gone, setup still owed")
  Check(Playing(c) == 0, "nothing running")
end

-- 6. Dismiss: appears only after a wait, ends the welcome and nothing else; the setup still opens later
do
  local c = Waiting("Dismiss")
  local d = Root(c)
  local btn
  Each(d, function(f) if f.kind == "Button" then btn = f end end)
  Check(btn ~= nil and btn.shown == true and btn.mouse == true, "after the simulated wait Dismiss is offered (the only thing that takes the mouse)")
  btn.scripts.OnClick(btn)
  Check(not Up(c) and Snap(c).why == "dismissed" and Ob(c).state == "new" and Playing(c) == 0, "Dismiss ends it, touches no record")
  c.taxi = false
  Settle()
  Check(Wizard(c) and c.wizardLoads == 1, "the setup still opens once when ready")
end

-- 7. Combat or EllesmereUI's own dialogs in the way: not shown (nothing to hide behind)
do
  local c = Boot("Combat", nil, { setup = function(c) c.combat = true end })
  Check(Root(c) == nil and not Wizard(c), "in combat at the first world entry: no welcome")
  local e = Boot("EUI", nil, { eui = { firstRun = true, installer = false }, noEUI = false })
  Check(not (Root(e) and Root(e).shown) or Wizard(e), "with EllesmereUI's first run held for the setup the welcome is allowed (checked, not required)")
end

-- 8. Reduced motion: shown still, ended at once
do
  local sv = LM.Logout((Boot("Still0", nil, {})))
  sv.TwichUIDB.onboarding = { v = 1, state = "new", offers = 0 }
  sv.TwichUIDB.ui = sv.TwichUIDB.ui or {}
  sv.TwichUIDB.ui.reduceSettingsMotion = true
  local c = Boot("Still", sv, { setup = function(c) c.taxi = true; c.UnitOnTaxi = function() return c.taxi end end })
  Check(Up(c) and Playing(c) == 0 and Root(c).alpha == 1, "reduced motion: shown at full opacity, nothing animating")
  c.taxi = false
  Settle()
  Check(not Up(c) and Wizard(c), "and it goes at once with the setup")
end

if failures == 0 then print("PASSED") else print(failures .. " failure(s)"); os.exit(1) end
