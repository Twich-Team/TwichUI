dofile(TESTS .. "harness.lua")
-- The status snapshot and support information (diag/Status.lua, diag/SupportWindow.lua, the Troubleshooting page's
-- status rows). Version metadata, optional addons absent / turned off / not loaded / available, different
-- capabilities of one addon, no setting changed and nothing loaded while reading, the report's allowlist and
-- format, repeated refreshes, the page opening and closing and a profile changing, and the copy window's
-- selection and cleanup. The game's own answers (a real addon list, a real clipboard) are for the game.
dofile(TESTS .. "settings_mock.lua")

local function Has(text, needle) return text:find(needle, 1, true) ~= nil end
local EXTRA = {}   -- addons the addon list knows of (the test adds them as it needs them)

local c, S = SettingsClient({
  name = "Zzyzx Qwerty",
  beforeInit = function(c)
    local exists = c.C_AddOns.DoesAddOnExist
    c.C_AddOns.DoesAddOnExist = function(n) return EXTRA[n] or exists(n) end
    c.LOAD_ATTEMPTS = {}
    local load = c.C_AddOns.LoadAddOn
    c.C_AddOns.LoadAddOn = function(n, ...) c.LOAD_ATTEMPTS[#c.LOAD_ATTEMPTS + 1] = n return load and load(n, ...) end
  end,
})
local R, K = c.TwichUI, S.K
local St = R.DiagStatus
assert(St and R.SupportWindow, "the status module and the copy window are part of the core addon")
-- the settings addon is loaded by this client's own LoadCompanion; what is counted below is what happens after
local loadsAtStart = #c.LOAD_ATTEMPTS

local function Fresh() St.Invalidate() return St.Current() end
local function Cap(id) return Fresh().caps[id] end
local function Reset()
  META, OFF = nil, nil
  c.LOADED.EllesmereUI, c.LOADED.EllesmereUIBags, c.LOADED.RXPGuides = nil, nil, nil
  c.EllesmereUI, c.EUI_CategoryManager, c.EllesmereUIDB = nil, nil, nil
  R.S, R.euiRegistered = nil, nil
  c.TwichUIDB.modules.mageSell, c.TwichUIDB.ui.mageSellMode = false, nil
end

---------------------------------------------------------------------------
-- Version, channel and client: missing, placeholder, development, alpha, beta, stable and hostile metadata
---------------------------------------------------------------------------
local function Version(v)
  META = { ["!!!TwichUI"] = { Version = v, Interface = "16001" } }
  return Fresh().version
end
assert(Version(nil).text == nil and Version(nil).channel == nil, "no version recorded: unknown")
assert(Version("@project-version@").text == nil, "a packager placeholder is not a version")
assert(Version("").text == nil)
local dev = Version("1.0.0")
assert(dev.text == "1.0.0" and dev.channel == nil, "a plain version does not say alpha, beta or stable (an unpackaged copy shows the same)")
assert(Version("1.0.1-alpha.23.g3e8a397").channel == "alpha")
assert(Version("1.0.1-beta.4.gabcdef0").channel == "beta")
assert(Version("1.0.1-alpha.23.g3e8a397").text == "1.0.1-alpha.23.g3e8a397")
assert(Version("1.0.1-nightly.2.g3e8a397").channel == nil, "only the channels the release tool writes")
assert(Version("1.0.1-alpha.x.g3e8a397").channel == nil, "the suffix must have the shape the release tool writes")
assert(Version("1.0.0; rm -rf /").text == nil, "a value with anything but version characters is dropped, not shown")
assert(Version(("9"):rep(60)).text == nil, "a long value is dropped")
local rows = St.Summary(Fresh())
local byId = {}
for _, r in ipairs(rows) do byId[r.id] = r end
assert(byId.channel.value == "Unknown" and Has(byId.channel.detail, "not guessed"), "channel: Unknown, and why")
Version("1.0.1-beta.4.gabcdef0")
rows = St.Summary(Fresh())
for _, r in ipairs(rows) do byId[r.id] = r end
assert(byId.version.value == "1.0.1-beta.4.gabcdef0" and byId.channel.value == "beta" and byId.channel.detail == nil)
Version(nil)
rows = St.Summary(Fresh())
for _, r in ipairs(rows) do byId[r.id] = r end
assert(byId.version.value == "Unknown" and Has(byId.version.detail, "no version"))
local client = Fresh().client
assert(client.version == "1.60.1" and client.build == "70009" and client.interface == "16001" and client.locale == "enUS", "the client's own answer")
assert(byId.client.value == "1.60.1 (build 70009)")
BUILD = "70010"
assert(Fresh().client.build == "70010", "read each time, not remembered")
BUILD = nil

---------------------------------------------------------------------------
-- Core and the settings window: start-up states, and available versus loaded
---------------------------------------------------------------------------
assert(Fresh().core.state == "started" and Fresh().core.savedVariables == "ready")
local L = R.Life
local was = L.configReady
L.configReady = false
assert(Fresh().core.state == "starting")
L.configReady = was
L.hookFailures = 1
assert(Fresh().core.state == "problem" and St.Summary(Fresh())[4].warn == true, "a failed start-up step is the one core state shown in warning color")
L.hookFailures = 0

assert(Fresh().settings.state == "loaded" and Has(St.Summary(Fresh())[5].detail, "does not show it was loaded at startup"),
  "loaded is said as loaded this session, never as proof of start-up")
local ui = R.SettingsUI
R.SettingsUI = nil
c.LOADED.TwichUI_Settings = false
assert(Fresh().settings.state == "installed", "installed and not loaded is available, not loaded")
OFF = { TwichUI_Settings = true }
assert(Fresh().settings.state == "disabled")
OFF = nil
local exists = c.C_AddOns.DoesAddOnExist
c.C_AddOns.DoesAddOnExist = function(n) return n ~= "TwichUI_Settings" and exists(n) end
assert(Fresh().settings.state == "not-installed")
c.C_AddOns.DoesAddOnExist = exists
c.LOADED.TwichUI_Settings = true
assert(Fresh().settings.state == "incomplete", "loaded by the game but never started: said so")
R.SettingsUI = ui
R.SettingsLauncher.failed = "MISSING"
assert(Fresh().settings.failed == "MISSING")
R.SettingsLauncher.failed = nil
assert(#c.LOAD_ATTEMPTS == loadsAtStart, "reading the settings window's state never loads it")

---------------------------------------------------------------------------
-- Optional addons: absent, turned off, not loaded, available (EllesmereUI)
---------------------------------------------------------------------------
Reset()
local EUI_IDS = { "eui-skin", "eui-borders", "eui-colorpicker", "eui-junk", "eui-unlock" }
for _, id in ipairs({ "eui-skin", "eui-borders", "eui-colorpicker" }) do
  local cap = Cap(id)
  assert(cap.state == "not-installed" and not cap.actionable and not cap.wanted, id .. ": an absent addon is not a problem")
  assert(Has(cap.detail, "Optional") and Has(cap.detail, "Affects"), id .. " says what it affects")
end
assert(Fresh().groups.ellesmereui.presence == "missing")
assert(Has(St.GroupDetail(Fresh().groups.ellesmereui), "Optional; TwichUI works without it."), "the folded line explains the fallbacks")
EXTRA.EllesmereUI = true
OFF = { EllesmereUI = true }
assert(Cap("eui-skin").state == "disabled" and Fresh().groups.ellesmereui.presence == "disabled", "turned off in the addon list")
assert(not Cap("eui-skin").actionable, "turned off on purpose is not a warning")
OFF = nil
assert(Cap("eui-skin").state == "not-loaded" and Fresh().groups.ellesmereui.presence == "not-loaded", "installed, not loaded")

c.LOADED.EllesmereUI = true
c.EllesmereUI = {}
META = { EllesmereUI = { Version = "9.5.5" }, EllesmereUIBags = { Version = "1.2.3; rm -rf /" } }
assert(Cap("eui-skin").state == "unavailable" and Cap("eui-skin").code == "no-register-api", "loaded without the registration call")
assert(Fresh().groups.ellesmereui.version == "9.5.5", "a version-shaped value is kept")
R.euiRegistered = true
assert(Cap("eui-skin").state == "not-initialized" and Cap("eui-skin").code == "toolkit-not-received",
  "registered, the toolkit not handed over yet: not initialized, not broken")
R.S = {}
assert(Cap("eui-skin").state == "available")

-- different capabilities of the one addon, in one snapshot
c.EllesmereUI = { PP = {}, ApplyBorderStyle = function() end, GetBorderTextureList = function() return {} end,
  ResolveBorderTexture = function() end, BorderPxStep = 1, BorderLegacyPx = 1, EnsureLoaded = function() c.ENSURED = (c.ENSURED or 0) + 1 end }
c.TwichUIDB.modules.mageSell = true
c.TwichUIDB.ui.mageSellMode = "ellesmere"
c.LOADED.EllesmereUIBags = true
local snap = Fresh()
assert(snap.caps["eui-skin"].state == "available" and snap.caps["eui-borders"].state == "available")
assert(snap.caps["eui-colorpicker"].state == "not-initialized" and snap.caps["eui-colorpicker"].code == "loads-on-use",
  "the picker loads on the first swatch click: not initialized, and not loaded just to find out")
assert(snap.caps["eui-junk"].state == "unavailable" and snap.caps["eui-junk"].code == "not-ready",
  "the Bags are loaded but offer no Junk Marker: unavailable, though the toolkit and borders are available")
assert(snap.caps["eui-junk"].actionable and snap.caps["eui-junk"].wanted, "the player chose this mode, so it is the one warning")
assert(Has(snap.caps["eui-junk"].detail, "Your selected mode is kept") and Has(snap.caps["eui-junk"].detail, "not selling these items directly"),
  "the fallback in plain words")
assert(not snap.caps["eui-skin"].actionable and not snap.caps["eui-colorpicker"].actionable)
assert(c.ENSURED == nil, "the picker's loader was not called to find out")
c.EllesmereUI.ShowColorPicker = function() end
assert(Cap("eui-colorpicker").state == "available", "the picker is there")
c.EllesmereUI.ShowColorPicker, c.EllesmereUI.EnsureLoaded = nil, nil
assert(Cap("eui-colorpicker").state == "unavailable" and Cap("eui-colorpicker").code == "no-picker-api", "no picker and no way to load one")
local CP = R.SettingsWidgets.ColorPicker
local realStatus = CP.Status
CP.Status = function() return "load-failed" end
assert(Cap("eui-colorpicker").state == "unavailable" and Cap("eui-colorpicker").code == "load-failed")
CP.Status = realStatus
local saved = R.SettingsWidgets
R.SettingsWidgets = nil
assert(Cap("eui-colorpicker").state == "not-initialized" and Cap("eui-colorpicker").code == "settings-not-loaded", "settings not loaded: not checked, said so")
R.SettingsWidgets = saved

-- the junk marker: each state the adapter reports, and where it does not apply
c.EUI_CategoryManager = { AssignItem = function() end, IsJunk = function() return false end, IsJunkMarkerEnabled = function() return false end, JUNK_KEY = "junk" }
c.EllesmereUIDB = { bagItemAssignments = {} }
assert(Cap("eui-junk").state == "unavailable" and Cap("eui-junk").code == "marker-off" and Has(Cap("eui-junk").why, "Junk Icon"), "the marker switched off in EllesmereUI's Bags")
c.EUI_CategoryManager.IsJunkMarkerEnabled = function() return true end
c.EUI_Bags = { SellJunk = function() end }
assert(Cap("eui-junk").state == "available" and Cap("eui-junk").code == "ready" and Has(Cap("eui-junk").why, "only when you press Sell Junk"),
  "available, and how marked items sell is EllesmereUI's own setting")
c.LOADED.EllesmereUIQoL = true
assert(Has(Cap("eui-junk").why, "Auto Sell Junk"))
c.LOADED.EllesmereUIQoL = nil
EXTRA.EllesmereUIBags = true
c.LOADED.EllesmereUIBags = nil
assert(Cap("eui-junk").state == "not-loaded" and not Cap("eui-junk").actionable, "not loaded yet is not a warning")
EXTRA.EllesmereUIBags = nil
assert(Cap("eui-junk").state == "not-installed" and Cap("eui-junk").actionable, "absent while the player chose it: the one absent addon that is a warning")
EXTRA.EllesmereUIBags = true
OFF = { EllesmereUIBags = true }
assert(Cap("eui-junk").state == "disabled" and Cap("eui-junk").actionable)
OFF = nil
c.LOADED.EllesmereUIBags = true
c.TwichUIDB.ui.mageSellMode = "direct"
assert(Cap("eui-junk").state == "not-applicable" and Cap("eui-junk").code == "mode-direct", "not set to use it: not applicable")
c.TwichUIDB.ui.mageSellMode = "ellesmere"
c.TwichUIDB.modules.mageSell = false
assert(Cap("eui-junk").state == "off", "mode chosen, selling off")
c.TwichUIDB.modules.mageSell = true
local unitClass = c.UnitClass
c.UnitClass = function() return "Warrior", "WARRIOR" end
assert(Cap("eui-junk").state == "not-applicable" and Cap("eui-junk").code == "not-a-mage", "not a Mage: not applicable")
c.UnitClass = unitClass

-- Unlock Mode: off by choice, then each adapter code
assert(Cap("eui-unlock").state == "off", "its choice is off")
c.TwichUIDB.modules.foodDrinkUnlock = true
assert(Cap("eui-unlock").wanted, "chosen")
assert(Cap("eui-unlock").state == "unavailable" and Cap("eui-unlock").code == "no-api" and Cap("eui-unlock").actionable, "EllesmereUI without the registration calls")
c.EllesmereUI.RegisterUnlockElements, c.EllesmereUI.MakeUnlockElement = function() end, function() end
assert(Cap("eui-unlock").state == "not-initialized" and Cap("eui-unlock").code == "waiting")
c.TwichUIDB.modules.foodDrinkUnlock = false

---------------------------------------------------------------------------
-- RestedXP and the others: off, wanted but missing, and the plain-addon skins
---------------------------------------------------------------------------
Reset()
EXTRA.EllesmereUI = nil
assert(Cap("rxp-skin").state == "off" and Cap("rxp-timers").state == "off" or Cap("rxp-timers").state == "not-applicable")
c.TwichUIDB.modules.restedxpSkin = true
EXTRA.RXPGuides = nil
assert(Cap("rxp-skin").state == "not-installed" and Cap("rxp-skin").wanted and not Cap("rxp-skin").actionable,
  "the skin switched on without RestedXP: said plainly, not a warning color")
EXTRA.RXPGuides = true
assert(Cap("rxp-broker").state == "not-installed" or Cap("rxp-broker").state == "not-loaded")
c.TwichUIDB.modules.restedxpSkin = false
assert(Cap("rxp-broker").detail and Has(Cap("rxp-broker").detail, "RestedXP's own controls are unchanged"))
assert(Cap("databar-ldb").state == "not-installed" and Cap("databar-ldb").stateLabel == "Not provided" and not Cap("databar-ldb").actionable)
c.LibStub:NewLibrary("LibDataBroker-1.1", 4)
assert(Cap("databar-ldb").state == "available")

-- an addon being skinned that is not here; EllesmereUI missing while it is; the toolkit missing while both are
assert(Cap("auctionator-skin").state == "not-installed" and not Cap("auctionator-skin").actionable, "nothing to skin")
assert(Cap("attune-skin").state == "not-loaded", "Attune is in the addon list here but has not loaded")
c.LOADED.Attune = true
assert(Cap("attune-skin").state == "unavailable" and Cap("attune-skin").code == "needs-ellesmereui" and not Cap("attune-skin").actionable,
  "works through EllesmereUI, which is not installed: unavailable, in the quiet color")
EXTRA.EllesmereUI = true
c.LOADED.EllesmereUI = true
assert(Cap("attune-skin").state == "unavailable" and Cap("attune-skin").code == "toolkit-not-received" and Cap("attune-skin").actionable, "installed, loaded, no toolkit at login")
R.S = {}
assert(Cap("attune-skin").state == "available")
c.TwichUIDB.modules.attuneSkin = false
assert(Cap("attune-skin").state == "off")
c.TwichUIDB.modules.attuneSkin = true
c.LOADED.Attune = nil

---------------------------------------------------------------------------
-- Reading changes nothing and loads nothing
---------------------------------------------------------------------------
Reset()
c.LOADED.EllesmereUI = true
c.EllesmereUI = { EnsureLoaded = function() c.ENSURED = (c.ENSURED or 0) + 1 end }
c.TwichUIDB.modules.mageSell = true
c.TwichUIDB.ui.mageSellMode = "ellesmere"
local function Dump(v, seen, out)
  out, seen = out or {}, seen or {}
  if type(v) == "table" then
    if seen[v] then return out end
    seen[v] = true
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do out[#out + 1] = k; Dump(v[k] == nil and v[tonumber(k)] or v[k], seen, out) end
  else
    out[#out + 1] = tostring(v)
  end
  return out
end
local before = table.concat(Dump(c.TwichUIDB), "|")
local loads, frames = #c.LOAD_ATTEMPTS, 0
local createFrame = c.CreateFrame
c.CreateFrame = function(...) frames = frames + 1 return createFrame(...) end
for _ = 1, 25 do St.Refresh(); St.Report(); St.Summary(St.Current()) end
c.CreateFrame = createFrame
assert(table.concat(Dump(c.TwichUIDB), "|") == before, "no saved setting changed")
assert(#c.LOAD_ATTEMPTS == loads and c.ENSURED == nil, "no addon was loaded and no addon's loader was called")
assert(frames == 0, "no frame was made")
assert(R.MageSell.Mode() == "ellesmere" and R.MageSell.Enabled(), "the selected mode is preserved while its integration is unavailable")

---------------------------------------------------------------------------
-- Pending reloads
---------------------------------------------------------------------------
Reset()
local W = R.Switches
assert(#W.PendingReloads() == 0 and not W.ReloadPending() and #Fresh().pending.reloads == 0)
assert(byId.pending.value == "None" or St.Summary(Fresh())[6].value == "None")
W.Set("media", not R:Enabled("media"))
assert(W.ReloadPending() == (#W.PendingReloads() > 0), "the list and the window's own test agree")
assert(W.PendingReloads()[1] == "media" and Fresh().pending.reloads[1] == "Custom fonts and sounds", "named for people")
assert(Has(St.Summary(Fresh())[6].value, "Custom fonts and sounds") and Has(St.Report(), "Reload needed: Custom fonts and sounds"))
W.wantsReload.mageTravel = true
assert(W.ReloadPending() and #W.PendingReloads() == 2 and Fresh().pending.reloads[2] == "Mage Travel" or Fresh().pending.reloads[1] == "Mage Travel")
W.wantsReload.mageTravel = nil
W.Set("media", not R:Enabled("media"))
assert(#W.PendingReloads() == 0 and not W.ReloadPending(), "switched back: nothing waits")
for key, def in pairs(W.defs) do
  if def.reload then assert(St.RELOAD_NAMES[key], key .. " has a readable name for a pending reload") end
end
for _, key in ipairs({ "mageTravel", "mageConjure" }) do assert(St.RELOAD_NAMES[key], key .. " can wait for a reload") end
for _, f in ipairs(St.FEATURES) do assert(R.DEFAULT_MODULES[f[1]] ~= nil, f[1] .. " is a real switch") end

---------------------------------------------------------------------------
-- The report: allowlist, privacy, format, stability
---------------------------------------------------------------------------
Reset()
-- canaries in every place a personal record could be
c.GetGuildInfo = function() return "Canary Guildhall" end
c.TwichUIDB.canary = "SECRET-CANARY-SETTING"
c.TwichUIDB.ui.mageSellMode = "ellesmere"
c.TwichUIDB.modules.mageSell = true
c.TwichUIChronicleDB = { characters = { ["Zzyzx Qwerty - Forever"] = { entries = { { text = "CHRONICLE-CANARY" } } } } }
c.TwichUIBackupDB = { points = { { name = "BACKUP-CANARY" } } }
c.TwichUIShareDB = { pack = { sourceName = "SHARE-CANARY" } }
c.BNGetNumFriends = function() return 1 end
c.BNGetFriendInfo = function() return 1, "FriendAccountCanary", "BattleCanary#1234", nil, "FriendChar" end
META = { ["!!!TwichUI"] = { Version = "1.0.1-alpha.23.g3e8a397", Interface = "16001" }, EllesmereUI = { Version = "9.5.5", Notes = "NOTES-CANARY" } }
c.LOADED.EllesmereUI = true
c.EllesmereUI = {}
local text = St.Report()
for _, secret in ipairs({ "Zzyzx", "Qwerty", "Forever -", "Canary", "CANARY", "BattleCanary", "FriendChar", "Interface\\AddOns", "\\", "|" }) do
  assert(not Has(text, secret), "the report leaves out " .. secret)
end
assert(not text:find("[^\n\32-\126]"), "plain printable text only")
assert(#text < 6000, "concise: " .. #text)
for _, field in ipairs({ "TwichUI version: 1.0.1-alpha.23.g3e8a397", "Release channel: alpha", "Game client: version 1.60.1, build 70009, interface 16001, locale enUS",
  "Core: started", "Settings window addon: loaded", "Reload needed: none", "Optional integrations", "  Skin toolkit:", "  Bag junk marking: installed, not loaded",
  "EllesmereUI: loaded, version 9.5.5", "Features (switches only", "  on: ", "  off: ", "Mage selling handling: mark as junk with EllesmereUI", "Left out on purpose" }) do
  assert(Has(text, field), "the report has: " .. field)
end
assert(not Has(text, "healthy") and not Has(text, "all good") and not Has(text, "working correctly"), "no verdict")
assert(Has(text, "does not show that any feature works"))
-- every line is one of the fixed forms
local labels = { "TwichUI support information", "A snapshot", "TwichUI version:", "Release channel:", "Game client:", "TwichUI interface:", "Core:",
  "Settings window addon:", "Reload needed:", "Work held back", "Optional integrations", "Features (", "Left out on purpose" }
local titles = {}
for _, g in ipairs(St.GROUPS) do titles[g.title] = true end
for line in (text .. "\n"):gmatch("(.-)\n") do
  if line ~= "" then
    local ok = line:find("^  [%w%p ]+: ") ~= nil
    for _, label in ipairs(labels) do if line:sub(1, #label) == label then ok = true end end
    for title in pairs(titles) do if line:sub(1, #title) == title then ok = true end end
    assert(ok, "a line outside the allowlist: " .. line)
  end
end
-- features are listed by readable name only, and nothing of a switch's key
assert(not Has(text, "gearBagIcons") and not Has(text, "qolSummons") and Has(text, "Accept summons"))
-- stable and repeatable
assert(St.Report() == text and St.Report(St.Collect()) == text, "the same state gives the same text (no clock, no counter)")
-- another profile's switch shows in it
c.TwichUIDB.modules.partyPins = false
assert(Has(St.Report(), "off: ") and select(2, St.Report():gsub("Party pins", "")) == 1)
c.TwichUIDB.modules.partyPins = true
-- held-back codes are listed as codes and counts only
R.Life.Note("deferred-combat"); R.Life.Note("deferred-combat")
assert(Has(St.Report(), "Work held back since the game started (counts, not pending now): deferred-combat x2"))
-- a broken adapter costs its own line only
local junk = R.EllesmereJunk.Status
R.EllesmereJunk.Status = function() error("boom NAME-CANARY") end
local broken = St.Report()
assert(Has(broken, "Bag junk marking: unknown (check-failed)") and not Has(broken, "NAME-CANARY") and Has(broken, "  Skin toolkit:"), "a failing check is reported as unknown, its message left out")
R.EllesmereJunk.Status = junk

---------------------------------------------------------------------------
-- The page: rows, opening and closing, a profile change, no stacking callbacks
---------------------------------------------------------------------------
local page = K.pages.troubleshooting
assert(page and page.def.onShow, "the page takes its snapshot when it opens")
local statusRows, shown = {}, {}
for _, row in ipairs(page.rows) do if row.kind == "status" then statusRows[#statusRows + 1] = row end end
assert(#statusRows == 6 + 2 + (5 + 6 + 1 + 4 + 1) + 1, "six summary lines, a folded line for each of the two multi-capability addons, each capability, and TwichUI Diagnostics' state: " .. #statusRows)
local function Value(row) return row.value() end
St.Invalidate()
page.def.onShow()
local first = St.Current()
for _, row in ipairs(statusRows) do assert(type(Value(row)) == "string" and Value(row) ~= "", row.data.name .. " has a value") end
assert(St.Current() == first, "drawing the rows takes no new snapshot")
page.def.onShow()
assert(St.Current() ~= first, "opening the page takes a new one")
local closers, listeners = #R.SettingsLauncher.closers, #R.Switches.listeners
for _ = 1, 20 do page.def.onShow(); for _, row in ipairs(statusRows) do row.value(); if row.detail then row.detail() end end end
assert(#R.SettingsLauncher.closers == closers and #R.Switches.listeners == listeners, "opening the page again adds no callbacks")
local held = St.Current()
R.SettingsLauncher.Closed()
assert(St.Current() ~= held, "closing the settings drops the snapshot")
-- folded lines: shown while the addon is not there and nothing is wanted, replaced by its capabilities when it is
local group, caps = nil, {}
for _, row in ipairs(statusRows) do
  local name = row.data.name
  if name == "EllesmereUI" then group = row elseif name:find("^EllesmereUI: ") then caps[#caps + 1] = row end
end
Reset()
EXTRA.EllesmereUI = nil
Fresh()
assert(group:Shown() and not caps[1]:Shown(), "EllesmereUI absent: one line, its capabilities folded away")
assert(Value(group) == "Not installed" and group.tone() == "quiet" and Has(group.detail(), "Optional"), "in the quiet color, with its fallbacks")
c.TwichUIDB.modules.mageSell, c.TwichUIDB.ui.mageSellMode = true, "ellesmere"
Fresh()
assert(group:Shown() and not caps[1]:Shown(), "folded")
local junkRow
for _, row in ipairs(caps) do if row.data.name:find("junk", 1, true) then junkRow = row end end
assert(junkRow:Shown() and junkRow.tone() == "warn" and Value(junkRow) == "Not installed", "but what the player chose that needs it is shown, in warning color")
Reset()
EXTRA.EllesmereUI = true
c.LOADED.EllesmereUI = true
c.EllesmereUI = {}
Fresh()
assert(not group:Shown() and caps[1]:Shown() and caps[5]:Shown(), "loaded: its capabilities, each on its own line")
-- a profile change takes the snapshot again
local P = R.Profiles
c.TwichUIDB.modules.partyPins = false
St.Current()
local original = P.Current()
local ok = P.Create("Plain")
assert(ok, "a second profile")
assert(St.Current() ~= nil)
local function Feature(snap, name) for _, f in ipairs(snap.features) do if f.name == name then return f.state end end end
assert(Feature(St.Current(), "Party pins") == "on", "after the change the snapshot is of the new profile (defaults: on)")
assert(P.Switch(original), "back to the first profile")
assert(Feature(St.Current(), "Party pins") == "off", "and back")
assert(#R.Switches.listeners == listeners, "profile changes add no switch listeners")
Reset()

---------------------------------------------------------------------------
-- The copy window: selection, read-only, cleanup
---------------------------------------------------------------------------
local made, calls = {}, {}
local function Rec(name)
  local o = { shown = false, scripts = {}, hooks = {}, text = "", name = name }
  local obj = setmetatable(o, { __index = function(_, k)
    if k == "Show" then return function(s) local was = s.shown; s.shown = true; if not was then for _, h in ipairs(s.hooks.OnShow or {}) do h(s) end end end end
    if k == "Hide" then return function(s) local was = s.shown; s.shown = false; if was then for _, h in ipairs(s.hooks.OnHide or {}) do h(s) end end end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
    if k == "HookScript" then return function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end end
    if k == "SetText" then return function(s, t) s.text = t or ""; calls.settext = (calls.settext or 0) + 1 end end
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetFocus" then return function(s) s.focused = true; calls.focus = (calls.focus or 0) + 1 end end
    if k == "ClearFocus" then return function(s) s.focused = false end end
    if k == "HighlightText" then return function(s) s.highlighted = true; calls.highlight = (calls.highlight or 0) + 1 end end
    if k == "GetWidth" or k == "GetHeight" then return function() return 100 end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Rec() end end
    return function() end
  end })
  made[#made + 1] = obj
  return obj
end
local FRAME = "TwichUISupportWindow"
local framesMade = 0
local w = MakeClient("Pal", { "!!!TwichUI" })
w.CreateFrame = function(kind, name, ...)
  local o = Rec(name)
  if name then w[name] = o; framesMade = framesMade + 1 end
  if kind == "EditBox" then o.isEdit = true end
  return o
end
w.UIParent, w.UISpecialFrames = Rec(), {}
w.TwichUIDB = {}
-- Core is already loaded by MakeClient; load the status module and the window on it
for _, f in ipairs({ "diag/Diagnostics.lua", "diag/Status.lua", "diag/SupportWindow.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, w); chunk("!!!TwichUI", {})
end
local WR = w.TwichUI
w.LOADED["!!!TwichUI"] = true
w.FireEvent("ADDON_LOADED", "!!!TwichUI")
w.FireEvent("PLAYER_LOGIN")
-- the look helpers, as recording stand-ins (Look.lua needs the full frame API)
WR.Look = {
  pal = {},
  Shell = function(f) return f end, Text = function() return Rec() end, CloseBox = function() return Rec() end,
  Button = function(_, label, _, _, onClick) local b = Rec(label); b.click = onClick; b.label = label; return b end,
  Well = function() end, ScrollBar = function() end,
}
local SW = WR.SupportWindow
local button = {}
local lookButton = WR.Look.Button
WR.Look.Button = function(...) local b = lookButton(...); button[b.label] = b; return b end
WR.Print = function(...) end
assert(not SW.IsShown() and SW.Text() == nil, "nothing is built or held while the window has never been opened")
assert(SW.Show() == true)
assert(framesMade == 1 and SW.IsShown(), "the window is built on the first open")
local report = SW.Text()
assert(report and report:find("TwichUI support information", 1, true) and report == WR.DiagStatus.Report(), "it shows the report as it would be shared")
local edit
for _, o in ipairs(made) do if o.scripts.OnTextChanged then edit = o end end
assert(edit and edit.text == report and edit.focused and edit.highlighted, "the text is in the box, selected, for Ctrl+C")
local intro
for _, o in ipairs(made) do if o.text and o.text:find("Ctrl+C", 1, true) then intro = o end end
-- typing puts the report back
edit.text = "typed over"
edit.scripts.OnTextChanged(edit, true)
assert(edit.text == report, "read-only: typing restores the report")
edit.text = "set by code"
edit.scripts.OnTextChanged(edit, false)
assert(edit.text == "set by code", "only the player's typing is undone")
edit.scripts.OnEditFocusGained(edit)
assert(edit.highlighted)
-- Select all and Refresh
edit.highlighted, edit.focused = false, false
button["Select all"].click()
assert(edit.focused and edit.highlighted, "Select all selects the text")
w.TwichUIDB.modules = { partyPins = false }
button["Refresh"].click()
assert(SW.Text() == WR.DiagStatus.Report() and edit.text == SW.Text(), "Refresh builds it again")
-- opening it again does not stack
for _ = 1, 5 do SW.Show() end
local listed = 0
for _, name in ipairs(w.UISpecialFrames) do if name == FRAME then listed = listed + 1 end end
assert(framesMade == 1 and listed == 1, "opened again: still one window, one Esc entry")
-- closing releases the text
w[FRAME]:Hide()
assert(not SW.IsShown() and SW.Text() == nil and edit.text == "" and not edit.focused, "closing drops the report and the selection")
-- a report that cannot be built is said, not shown half-built
local errors = {}
WR.Fault = function(...) errors[#errors + 1] = { ... } end
local report0 = WR.DiagStatus.Report
WR.DiagStatus.Report = function() error("boom") end
SW.Show()
assert(SW.Text() == nil and #errors == 1, "a failing report is reported to the error handler and nothing half-built is shown")
WR.DiagStatus.Report = report0
SW.Refresh()
assert(SW.Text() ~= nil, "and works again")
w[FRAME]:Hide()
-- no clipboard claimed
assert(not Has(table.concat(Dump(intro and intro.text or ""), ""), "copied to your clipboard"), "the window never says it copied anything for you")

print("PASSED")
