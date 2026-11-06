dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", {"!!!TwichUI"})
-- Permissive frame/font-string mocks, the same way tests/test_window_smoke.lua draws the setup window.
local function Obj()
  local o = {text = "", checked = false, shown = true}
  return setmetatable(o, {__index = function(t, k)
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetText" then return function(s, v) s.text = v or "" end end
    if k == "GetChecked" then return function(s) return s.checked end end
    if k == "SetChecked" then return function(s, v) s.checked = v end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "SetShown" then return function(s, v) s.shown = v end end
    if k == "HasFocus" then return function() return false end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Obj() end end
    if k == "ScrollBar" or k == "ThumbTexture" or k == "ScrollUpButton" or k == "ScrollDownButton" then local sb = Obj(); rawset(t, k, sb); return sb end
    if type(k) == "string" and k:find("^%l") then return nil end   -- a field never set is nil, as on a real frame
    return function() end
  end})
end
local realCreate = c.CreateFrame
c.tinsert = table.insert; c.CreateFrame = function(kind, name, ...) local o = Obj(); local base = realCreate(); for k,v in pairs(base) do rawset(o,k,v) end if name then c[name] = o; rawset(o, "IsShown", function() return true end) end return o end
c.UISpecialFrames = {}
c.GameTooltip = Obj(); c.GameTooltip_Hide = function() end
c.StaticPopupDialogs = {}; c.StaticPopup_Show = function(k, a) return {} end
c.UnitIsPlayer = function() return false end
c.InCombatLockdown = function() return false end
c.ACCEPT, c.CANCEL = "Accept", "Cancel"
c.Settings = nil
for _, f in ipairs({"chronicle/Style.lua", "Look.lua", "FrameLook.lua", "setup/Window.lua"}) do
  local chunk = assert(loadfile(ROOT..f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.TwichUIDB.setup.detected.FooDB = {owner="Foo", bytes=2000}
c.FireEvent("PLAYER_LOGIN")

-- The three text builders are file-locals in setup/Window.lua, reached through the popups that show them:
-- W:ShowEuiImport(src) -> W:Refresh() -> RefreshEuiImport() -> ip.body:SetText(EuiBody(plan)), and the TwichUI
-- settings popup does the same with TwichBody(plan, from). The plan is computed by ES.Plan from the received
-- pack, so a test that checks the wording must control the pack. ES.Plan is read from R.Ellesmere when
-- Window.lua loads, so the test swaps it for a stub that returns a plan the test defines.
local W = c.TwichUI.Window
local R = c.TwichUI
local ES, ST, TC = R.Ellesmere, R.Setups, R.TwichConfig
local realPlan, realSrcPack, realTcPlan = ES.Plan, ST.SourcePack, TC.Plan
local function WithPlan(plan, fn)
  ES.Plan = function() return plan end
  TC.Plan = function() return plan end
  -- RefreshEuiImport calls ES.Plan on any truthy pack; RefreshTwichImport only calls
  -- TC.Plan when pack.twichui is set, so the stub pack carries a truthy twichui entry.
  ST.SourcePack = function() return { twichui = {} } end
  local ok, err = pcall(fn)
  ES.Plan, ST.SourcePack, TC.Plan = realPlan, realSrcPack, realTcPlan
  if not ok then error(err, 0) end
end
local function EuiBodyText(plan)
  WithPlan(plan, function() W:ShowEuiImport({key = "test-eui", from = "Pal"}) end)
  local ip = c.TwichUIEuiImport
  assert(ip and ip.body, "the import popup is built")
  return ip.body:GetText()
end
-- W:ShowTwichImport(src) -> W:Refresh() -> the TwichUI settings popup's body is TwichBody(plan, from).
local function TwichBodyText(plan, from)
  assert(W.ShowTwichImport, "the window has a TwichUI import show method")
  -- W:Refresh() also refreshes the EllesmereUI popup when it has been built, running the same stubbed
  -- plan through EuiBody; give the plan the Eui fields EuiBody formats so that path stays quiet.
  local merged = {
    from = plan.from or "Pal", sourceName = plan.sourceName or "Raid", dest = plan.dest or "Raid (Pal)",
    modules = plan.modules or {{display = "Action Bars"}}, excluded = plan.excluded or "nothing",
    notes = plan.notes or {}, version = plan.version or "1.2.3",
  }
  for k, v in pairs(plan) do merged[k] = v end
  -- RefreshTwichImport's list rows need a string label per group (and a changes table when the
  -- state is "changed"); the test plans only carry what TwichBody reads, so fill the rest in.
  for _, g in ipairs(merged.groups or {}) do
    if not g.label then g.label = g.id or "Feature" end
    if g.state == "changed" and not g.changes then g.changes = {} end
  end
  WithPlan(merged, function() W.ShowTwichImport(W, {key = "test-twich", from = from or "Pal"}) end)
  -- BuildTwichImport names its frame "TwichUITwichImport"; look it up directly, because the
  -- Eui popup's key ("TwichUIEuiImport") also contains "Twich" and "Import" and pairs() order is
  -- not guaranteed, so a name scan could hand back the Eui frame's body.
  local twFrame = c.TwichUITwichImport
  assert(twFrame and twFrame.body, "the TwichUI import popup is built")
  return twFrame.body:GetText()
end
local function Lines(text)
  local out = {}
  for line in (text .. "\n\n"):gmatch("(.-)\n\n") do out[#out + 1] = line end
  return out
end
local function Find(text, pattern)
  return text:find(pattern, 1, true) ~= nil
end
local function NotFind(text, pattern)
  return text:find(pattern, 1, true) == nil
end

---------------------------------------------------------------------------
-- EuiModules (via the Included line of EuiBody): display names joined by ', ',
-- the grey ' (not installed here)' marker, then '  ·  ' and the extra parts,
-- in the order look, layout links, Cooldown Manager spells, overrides.
---------------------------------------------------------------------------
do
  local plan = {
    ok = true, from = "Pal", sourceName = "Raid", dest = "Raid (Pal)", active = "Mine",
    modules = {
      {display = "Action Bars"},
      {display = "Bags", missing = true},
      {display = "Cooldown Manager"},
    },
    look = true, layout = true, cdm = true, overrides = true,
    excluded = "nothing", notes = {}, version = "1.2.3",
  }
  local text = EuiBodyText(plan)
  assert(Find(text, "Action Bars, Bags"), "module display names are joined by ', '")
  assert(Find(text, "Bags" .. c.TwichUI.GREY .. " (not installed here)|r"), "a module missing here is marked")
  assert(NotFind(text, "Action Bars" .. c.TwichUI.GREY), "an installed module is not marked missing")
  -- every extra part, in order, after the '  ·  ' separator
  local iLook, iLayout, iCdm, iOv
  iLook = text:find("look (fonts, colours, dark mode, accent)", 1, true)
  iLayout = text:find("layout links", 1, true)
  iCdm = text:find("Cooldown Manager spells", 1, true)
  iOv = text:find("overrides", 1, true)
  assert(iLook and iLayout and iCdm and iOv, "all four extra parts are named")
  assert(iLook < iLayout and iLayout < iCdm and iCdm < iOv, "the extra parts keep their order")
  local sep = text:find("  ·  ", 1, true)
  assert(sep and sep < iLook, "the extra parts follow the '  ·  ' separator")
  assert(Find(text, "  ·  look (fonts, colours, dark mode, accent), layout links, Cooldown Manager spells, overrides"),
    "the extras are joined by ', ' in one piece")
  -- no extras: no separator at all
  local bare = {ok = true, from = "Pal", sourceName = "Raid", dest = "Raid (Pal)", active = "Mine",
    modules = {{display = "Action Bars"}}, excluded = "nothing", notes = {}}
  local bareText = EuiBodyText(bare)
  assert(NotFind(bareText, "  ·  "), "no '  ·  ' when the plan has no look, layout, cdm or overrides")
  assert(Find(bareText, "Included|r  Action Bars\n\n"), "the Included line is just the module list")
  -- a subset of extras keeps the fixed order and skips the absent ones
  local some = {ok = true, from = "Pal", sourceName = "Raid", dest = "Raid (Pal)", active = "Mine",
    modules = {{display = "Action Bars"}}, layout = true, overrides = true, excluded = "nothing", notes = {}}
  assert(Find(EuiBodyText(some), "  ·  layout links, overrides"), "absent extras are skipped, order kept")
end

---------------------------------------------------------------------------
-- EuiBody: the not-ok red one-liner, and the ok body's lines in order.
---------------------------------------------------------------------------
do
  local text = EuiBodyText({ok = false, why = "That setup is no longer here.", notes = {}})
  assert(text == c.TwichUI.RED .. "That setup is no longer here.|r", "not ok: the red why, nothing else")
  local text2 = EuiBodyText({ok = false, notes = {}})
  assert(text2 == c.TwichUI.RED .. "Nothing to import.|r", "not ok without a why: the red fallback")
end
do
  local plan = {
    ok = true, from = "Pal", sourceName = "Raid", dest = "Raid (Pal)", active = "Mine",
    modules = {{display = "Action Bars"}},
    excluded = "the two addons that are not installed here",
    notes = {"A note about the profile."},
    version = "1.2.3",
  }
  local text = EuiBodyText(plan)
  local lines = Lines(text)
  assert(#lines == 7, "five fixed lines plus one note plus the final line")
  assert(Find(lines[1], "From|r  Pal's profile \"Raid\""), "line 1 names the source and profile")
  assert(Find(lines[2], "Creates|r  a new profile named \"Raid (Pal)\". Your existing profiles are not changed, replaced or renamed."),
    "line 2 is the Creates line")
  assert(Find(lines[3], "Included|r  Action Bars"), "line 3 is the Included line")
  assert(Find(lines[4], "Left out|r  the two addons that are not installed here"), "line 4 is the Left out line")
  assert(Find(lines[5], "In use afterwards|r") and Find(lines[5], "\"Mine\" stays saved exactly as it is"),
    "line 5 is the In use afterwards line naming the profile that stays")
  assert(lines[6] == c.TwichUI.GREY .. "A note about the profile.|r", "the note is its own grey line")
  assert(Find(lines[7], "Your UI reloads when it's done. EllesmereUI 1.2.3 here."), "the final line names the version")
  assert(NotFind(lines[7], "when it was shared"), "no shared-version clause without plan.euiVersion")
  assert(Find(lines[7], c.TwichUI.GREY), "the final line is grey")
  -- a nil active becomes '?'
  local q = {ok = true, from = "Pal", sourceName = "Raid", dest = "Raid (Pal)",
    modules = {{display = "Action Bars"}}, excluded = "nothing", notes = {}}
  local qText = EuiBodyText(q)
  assert(Find(qText, "In use afterwards|r  EllesmereUI has no import that doesn't switch to the new profile, so it becomes the one in use. \"?\" stays saved exactly as it is"),
    "a nil active shows '?'")
  assert(Find(qText, "EllesmereUI ? here."), "a nil version shows '?'")
end
do
  -- a non-empty plan.previous adds the 'Imported before' line; plan.notes entries appear in grey
  local plan = {
    ok = true, from = "Pal", sourceName = "Raid", dest = "Raid (Pal)", active = "Mine",
    modules = {{display = "Action Bars"}}, excluded = "nothing",
    previous = {{dest = "Raid (Pal) (old)"}},
    notes = {"First note.", "Second note."},
    version = "1.2.3",
  }
  local text = EuiBodyText(plan)
  local lines = Lines(text)
  assert(#lines == 9, "five fixed lines plus previous plus two notes plus the final line")
  assert(Find(lines[6], "Imported before|r  TwichUI recorded an earlier import of this profile as \"Raid (Pal) (old)\". It isn't touched; this makes a separate copy."),
    "the Imported before line names previous[1].dest")
  assert(lines[7] == c.TwichUI.GREY .. "First note.|r", "each note is its own grey line")
  assert(lines[8] == c.TwichUI.GREY .. "Second note.|r", "notes keep their order")
  -- euiVersion appends the shared-version clause to the final line
  plan.euiVersion = "2.1.0"
  local text2 = EuiBodyText(plan)
  assert(Find(text2, "EllesmereUI 1.2.3 here, 2.1.0 when it was shared."), "the final line carries the shared version")
end

---------------------------------------------------------------------------
-- TwichBody: the not-ok red one-liner; the scope line with and without a
-- profile; the shared-profile warning; the account-wide line; the absent and
-- unknown lines; the Features line; the reload line; the closing Undo line.
---------------------------------------------------------------------------
do
  -- RefreshTwichImport iterates plan.groups unconditionally, so even a not-ok plan needs a groups table.
  local text = TwichBodyText({ok = false, why = "Nothing to change.", groups = {}}, "Pal")
  assert(text == c.TwichUI.RED .. "Nothing to change.|r", "not ok: the red why, nothing else")
  local text2 = TwichBodyText({ok = false, groups = {}}, "Pal")
  assert(text2 == c.TwichUI.RED .. "Nothing to import.|r", "not ok without a why: the red fallback")
end
do
  local base = {
    ok = true, profile = "Mine", groups = {},
    absent = {}, unknown = 0, turnsOn = {}, turnsOff = {}, spending = {}, reload = {},
  }
  local text = TwichBodyText(base, "Pal")
  assert(Find(text, "From|r  Pal's TwichUI settings"), "the From line names the sender")
  assert(Find(text, "Applies to|r  your profile \"Mine\"."), "a plan.profile names the profile")
  assert(NotFind(text, "also use"), "no shared-profile warning without plan.sharedWith")
  assert(NotFind(text, "Every profile|r"), "no account-wide line without an account-scope change")
  assert(NotFind(text, "Not in this share"), "no absent line with an empty list")
  assert(NotFind(text, "from a newer TwichUI ignored"), "no unknown line at zero")
  assert(NotFind(text, "Features|r"), "no Features line with nothing turned on or off")
  assert(NotFind(text, "Needs a reload"), "no reload line with an empty list")
  assert(Find(text, "Nothing changes until you confirm. The values this replaces are kept, so Undo can put them back; Undo keeps only the last import."),
    "the closing Undo line is always present")
  local noProfile = {ok = true, groups = {}, absent = {}, unknown = 0, turnsOn = {}, turnsOff = {}, spending = {}, reload = {}}
  assert(Find(TwichBodyText(noProfile, "Pal"), "Applies to|r  your profile in use."), "no plan.profile: the profile in use")
end
do
  -- the shared-profile warning: singular and plural
  local one = {ok = true, profile = "Mine", sharedWith = 1, groups = {}, absent = {}, unknown = 0, turnsOn = {}, turnsOff = {}, spending = {}, reload = {}}
  assert(Find(TwichBodyText(one, "Pal"), ", which 1 other character also uses: they would see these changes too. \"Apply to a new profile\" leaves it alone."),
    "one other character: singular")
  local many = {ok = true, profile = "Mine", sharedWith = 3, groups = {}, absent = {}, unknown = 0, turnsOn = {}, turnsOff = {}, spending = {}, reload = {}}
  assert(Find(TwichBodyText(many, "Pal"), ", which 3 other characters also use: they would see these changes too. \"Apply to a new profile\" leaves it alone."),
    "several other characters: plural")
  local zero = {ok = true, profile = "Mine", sharedWith = 0, groups = {}, absent = {}, unknown = 0, turnsOn = {}, turnsOff = {}, spending = {}, reload = {}}
  assert(NotFind(TwichBodyText(zero, "Pal"), "also use"), "sharedWith 0: no warning")
end
do
  -- the account-wide line: only a selected group in state 'changed' with an account-scope change counts
  local function group(sel, state, changes) return {selected = sel, state = state, changes = changes} end
  local acct = {scope = "account"}
  local localOnly = {scope = "profile"}
  local yes = {ok = true, profile = "Mine", groups = {group(true, "changed", {localOnly, acct})}, absent = {}, unknown = 0, turnsOn = {}, turnsOff = {}, spending = {}, reload = {}}
  assert(Find(TwichBodyText(yes, "Pal"), "Every profile|r  stat weights (kept by class and talent tree) and the settings window's motion setting are account-wide: they change for all your profiles."),
    "a selected changed group with an account change warns")
  local unselected = {ok = true, profile = "Mine", groups = {group(false, "changed", {acct})}, absent = {}, unknown = 0, turnsOn = {}, turnsOff = {}, spending = {}, reload = {}}
  assert(NotFind(TwichBodyText(unselected, "Pal"), "Every profile|r"), "an unticked group does not warn")
  local notChanged = {ok = true, profile = "Mine", groups = {group(true, "same", {acct})}, absent = {}, unknown = 0, turnsOn = {}, turnsOff = {}, spending = {}, reload = {}}
  assert(NotFind(TwichBodyText(notChanged, "Pal"), "Every profile|r"), "a group that is not changed does not warn")
  local noAccount = {ok = true, profile = "Mine", groups = {group(true, "changed", {localOnly})}, absent = {}, unknown = 0, turnsOn = {}, turnsOff = {}, spending = {}, reload = {}}
  assert(NotFind(TwichBodyText(noAccount, "Pal"), "Every profile|r"), "profile-scope changes do not warn")
end
do
  -- the absent and unknown lines
  local absent = {ok = true, profile = "Mine", groups = {}, absent = {"Mage Sell", "Cozy Bag"}, unknown = 0, turnsOn = {}, turnsOff = {}, spending = {}, reload = {}}
  assert(Find(TwichBodyText(absent, "Pal"), "Not in this share: Mage Sell, Cozy Bag."), "the absent line lists the features")
  local one = {ok = true, profile = "Mine", groups = {}, absent = {}, unknown = 1, turnsOn = {}, turnsOff = {}, spending = {}, reload = {}}
  assert(Find(TwichBodyText(one, "Pal"), "1 setting from a newer TwichUI ignored."), "one unknown value: singular 'setting'")
  local two = {ok = true, profile = "Mine", groups = {}, absent = {}, unknown = 2, turnsOn = {}, turnsOff = {}, spending = {}, reload = {}}
  assert(Find(TwichBodyText(two, "Pal"), "2 settings from a newer TwichUI ignored."), "two unknown values: plural 'settings'")
end
do
  -- the Features line lists turnsOn and turnsOff; the reload line only when non-empty
  local feats = {ok = true, profile = "Mine", groups = {}, absent = {}, unknown = 0, turnsOn = {"Quiet Login", "Mage Sell"}, turnsOff = {"Party Check"}, spending = {}, reload = {}}
  assert(Find(TwichBodyText(feats, "Pal"), "Features|r  this turns on Quiet Login, Mage Sell and turns off Party Check."),
    "the Features line lists both directions")
  local onOnly = {ok = true, profile = "Mine", groups = {}, absent = {}, unknown = 0, turnsOn = {"Quiet Login"}, turnsOff = {}, spending = {}, reload = {}}
  assert(Find(TwichBodyText(onOnly, "Pal"), "Features|r  this turns on Quiet Login."), "turns on only")
  local offOnly = {ok = true, profile = "Mine", groups = {}, absent = {}, unknown = 0, turnsOn = {}, turnsOff = {"Party Check"}, spending = {}, reload = {}}
  assert(Find(TwichBodyText(offOnly, "Pal"), "Features|r  this turns off Party Check."), "turns off only")
  local reload = {ok = true, profile = "Mine", groups = {}, absent = {}, unknown = 0, turnsOn = {}, turnsOff = {}, spending = {}, reload = {"Mage Sell", "Quiet Login"}}
  assert(Find(TwichBodyText(reload, "Pal"), "Needs a reload|r  Mage Sell, Quiet Login take effect after reloading your UI. Nothing else does, and nothing reloads by itself."),
    "the reload line lists what needs reloading")
  assert(NotFind(TwichBodyText(feats, "Pal"), "Needs a reload"), "no reload line when the list is empty")
end

print("TEST_SETUP_IMPORT_BODY_TEXT PASSED")
