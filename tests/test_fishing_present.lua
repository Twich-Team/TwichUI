-- TwichUI Fishing, Stage 2: Fishing Mode (TwichUI_Fishing/Present.lua, Camera.lua, Fade.lua; QuietScreen.lua's hold).
-- Lifecycle, the three presentations, the camera recorded and put back, the interface faded and put back, combat, reload and
-- logout recovery, errors part-way, missing client functions, the controller keys and Stage 1 behaving the same underneath.
-- Simulated client (tests/fishing_mock.lua, tests/ui_widgets.lua): proves decisions and bookkeeping, not the real client's
-- camera, rendering, taint or protected behaviour.
dofile(TESTS .. "fishing_mock.lua")
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local KEY = "CLICK TwichUIFishingButton:LeftButton"
local GAME_FRAMES = { "MainMenuBar", "MultiBarBottomLeft", "PlayerFrame", "TargetFrame", "MinimapCluster", "ObjectiveTrackerFrame",
  "UIErrorsFrame", "EllesmereUIUnitFrames_Player" }

-- A client with the fishing key bound, a camera (unless o.camera == false) and some of the game's frames.
local function Fresh(o)
  o = o or {}
  local c, W = FishingClient(o)
  local faults = {}
  c.geterrorhandler = function() return function(e) faults[#faults + 1] = tostring(e) end end
  W.faults = faults
  if o.camera ~= false then W.Camera(o.cam) end
  for _, n in ipairs(GAME_FRAMES) do
    local f = W.UI.Create("Frame", n, c.UIParent)
    f:SetSize(100, 20); f:SetPoint("CENTER")
  end
  c.TargetFrame:Hide()                 -- hidden: left alone
  c.SetBinding = function() error("TwichUI never binds a key") end
  c.SetBindingClick = c.SetBinding
  W.bound.F = KEY
  c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
  return c, W, c.TwichUI.Fishing
end

-- One cast and, unless told otherwise, a catch.
local function Fish(c, W, catch)
  W.Advance(1.2)
  W.Key("F")
  if catch ~= false then
    W.catch = catch or { { FISH1, 1 } }
    W.Interact()
  end
  W.Advance(0.1)
end

local function Settle(W) W.Frames(1); W.Advance(2) end

---------------------------------------------------------------------------
-- 1. Immersive: on with the first cast, everything back at the end of the session
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  local P, Q = F.Present, c.TwichUI.QuietScreen
  c.MainMenuBar:SetAlpha(0.6)
  Check(not P.On(), "off before fishing")
  W.Advance(1.2); W.Key("F")
  Check(P.On() and P.State().mode == "immersive" and P.State().reason == "cast", "the first cast brings Fishing Mode on (immersive)")
  Check(F.CastBar.Shown() and F.CatchList.Shown(), "the cast bar and the catch list show")
  Check(P.BrandShown(), "and the TwichUI Fishing emblem, top left")
  Check(math.abs(W.camera.zoom - 7) < 0.01, "the camera moved once to Fishing Mode's distance (15 -> 7)")
  local zoomCalls = W.camera.calls
  Settle(W)
  Check(c.MainMenuBar:GetAlpha() == 0 and c.PlayerFrame:GetAlpha() == 0 and c.MinimapCluster:GetAlpha() == 0, "bars, unit frames and the minimap fade")
  Check(c.EllesmereUIUnitFrames_Player:GetAlpha() == 0, "EllesmereUI's unit frame (by its own name) fades too")
  Check(c.ObjectiveTrackerFrame:GetAlpha() == 1, "panels stay (off by default)")
  Check(c.TargetFrame:GetAlpha() == 1, "a hidden frame is left alone")
  Check(c.UIErrorsFrame:GetAlpha() == 1 and c.UIParent:GetAlpha() == 1, "errors and UIParent itself are never faded")
  Check(Q.On() and not Q.Player(), "TwichUI's notices are held quiet, and the player's own Quiet screen switch stays off")
  W.Interact(); W.Advance(0.1)
  Check(F.Session.Current().catches == 1, "the catch is recorded by Stage 1 as usual")
  W.camera.zoom = W.camera.zoom   -- the player does nothing to the camera
  Check(W.camera.calls == zoomCalls, "the camera is never corrected while fishing")
  c.TwichUI.RunCommand("fish stop")
  Settle(W)
  Check(not P.On() and not F.CastBar.Shown() and not F.CatchList.Shown(), "the session's end turns Fishing Mode off and hides the pieces")
  Check(not P.BrandShown(), "the emblem too")
  Check(math.abs(W.camera.zoom - 15) < 0.01, "the camera is back where the player had it")
  Check(c.MainMenuBar:GetAlpha() == 0.6 and c.PlayerFrame:GetAlpha() == 1 and c.MinimapCluster:GetAlpha() == 1, "each frame is back at its own alpha")
  Check(not Q.On() and not Q.Player(), "the hold is let go; the player's switch never moved")
  Check(c.TwichUIFishingDB.client.camera == nil, "nothing left to recover")
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, " | "))
end

---------------------------------------------------------------------------
-- 2. The three presentations, and switching between them while on
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  local P = F.Present
  c.TwichUI.RunCommand("fish mode compact")
  W.Advance(1.2); W.Key("F"); Settle(W)
  Check(P.On() and F.CastBar.Shown() and not F.CatchList.Shown(), "compact: the cast bar, no catch list")
  Check(not P.BrandShown(), "compact: no emblem")
  Check(W.camera.zoom == 15 and c.MainMenuBar:GetAlpha() == 1 and not c.TwichUI.QuietScreen.On(), "compact: no camera, nothing faded, no quiet")
  P.Configure("present.mode", "immersive"); Settle(W)
  Check(P.On() and F.CatchList.Shown() and math.abs(W.camera.zoom - 7) < 0.01 and c.MainMenuBar:GetAlpha() == 0, "switched to immersive while on: applied at once")
  P.Configure("present.mode", "classic"); Settle(W)
  Check(not P.On() and W.camera.zoom == 15 and c.MainMenuBar:GetAlpha() == 1 and not F.CastBar.Shown(), "classic: everything put back and nothing shown")
  Check(P.Enter("player") == false, "classic has no Fishing Mode to turn on")
  W.Interact(); W.Advance(1.2); W.Key("F")
  Check(not P.On() and W.channel ~= nil, "classic: the key still fishes (Stage 1) with nothing more on screen")
  -- each part's own switch only takes a part away
  P.Configure("present.mode", "immersive")
  P.Configure("camera.enabled", false)
  P.Configure("list.enabled", false)
  W.Interact(); W.Advance(1.2); W.Key("F"); Settle(W)
  Check(P.On() and W.camera.zoom == 15 and not F.CatchList.Shown() and c.MainMenuBar:GetAlpha() == 0, "immersive without camera and list")
end

---------------------------------------------------------------------------
-- 3. The camera: the player's own changes win; the offset; the client's cap; a zoom that does nothing
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  local P = F.Present
  P.Configure("camera.offset", 1)
  W.Advance(1.2); W.Key("F")
  Check(W.cvars.test_cameraOverShoulder == "1.00", "the shoulder offset is set when asked for")
  W.camera.zoom = 11            -- the player scrolls the camera
  W.cvars.test_cameraOverShoulder = "0.5"
  c.TwichUI.RunCommand("fish mode")
  Check(not P.On() and P.State().suppressed, "the player turned it off; it stays off for this session")
  Check(W.camera.zoom == 11 and W.cvars.test_cameraOverShoulder == "0.5", "values the player changed are kept, not put back")
  Check(c.TwichUIFishingDB.client.camera == nil, "and the record is cleared")
  W.Interact(); W.Advance(1.2); W.Key("F")
  Check(not P.On(), "the next line doesn't bring it back after the player said no")
  c.TwichUI.RunCommand("fish mode")
  Check(P.On(), "until they ask again")
end
do
  local c, W, F = Fresh({ cam = { zoom = 15, max = 20 } })
  F.Present.Configure("camera.zoom", 30)
  W.Advance(1.2); W.Key("F"); W.Advance(2)
  Check(W.camera.zoom == 20 and c.TwichUIFishingDB.client.camera.zoom.set == 20, "a distance past the client's cap: the reached distance is recorded")
  c.TwichUI.RunCommand("fish stop")
  Check(W.camera.zoom == 15, "and the camera still comes back")
end
do
  local c, W, F = Fresh({ cam = { frozen = true } })
  W.Advance(1.2); W.Key("F"); W.Advance(2)
  Check(c.TwichUIFishingDB.client.camera == nil and F.Camera.Status().noEffect, "a zoom that does nothing is given up and noted")
  Check(F.noteCounts["camera-no-effect"] == 1, "noted once")
  local calls = W.camera.calls
  c.TwichUI.RunCommand("fish stop")
  W.Advance(1.2); W.Key("F"); W.Advance(2)
  Check(W.camera.calls == calls, "and not tried again this session")
end

---------------------------------------------------------------------------
-- 4. Fading: another addon's change wins; reveal; frames the player adds
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  local P = F.Present
  local bar = W.UI.Create("Frame", "SomeAddonBar", c.UIParent); bar:SetSize(10, 10); bar:SetPoint("CENTER")
  c.TwichUI.RunCommand("fish fade add SomeAddonBar")
  W.Advance(1.2); W.Key("F"); Settle(W)
  Check(bar:GetAlpha() == 0, "a frame the player named fades too")
  c.MultiBarBottomLeft:SetAlpha(0.3)     -- another addon changes it while fishing
  P.Reveal(true); Settle(W)
  Check(c.MainMenuBar:GetAlpha() == 1 and c.MultiBarBottomLeft:GetAlpha() == 0.3, "reveal: the interface is back; the other addon's alpha is left")
  Check(not c.TwichUI.QuietScreen.On(), "and TwichUI's notices may show while revealed")
  P.Reveal(false); Settle(W)
  Check(c.MainMenuBar:GetAlpha() == 0 and c.MultiBarBottomLeft:GetAlpha() == 0.3, "let go: faded again, the other addon's frame still theirs")
  c.TwichUI.RunCommand("fish stop"); Settle(W)
  Check(c.MultiBarBottomLeft:GetAlpha() == 0.3 and bar:GetAlpha() == 1, "at the end their value stays; ours comes back")
  Check(F.Fade.Status().kept == 1, "and it is counted as left to its owner")
  -- the moving fade has its own OnUpdate only while something moves
  Check(not F.Fade.Moving(), "nothing runs once the fades are done")
end

---------------------------------------------------------------------------
-- 5. Combat: off at once, never on in combat, no secure change
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  local P = F.Present
  P.Configure("camera.offset", 1)
  W.Advance(1.2); W.Key("F"); Settle(W)
  W.Fight()
  Check(not P.On() and c.MainMenuBar:GetAlpha() == 1 and W.camera.zoom == 15, "combat: everything back at once, before the lockdown")
  Check(W.cvars.test_cameraOverShoulder == "0", "the offset too (set while still allowed)")
  Check(P.Enter("player") == false and select(2, P.Enter("player")) == "combat", "it can't come on during combat")
  Check(F.CastBar.Shown() == false, "no pieces in combat")
  W.Peace()
  W.StopLine(); W.Advance(2)
  W.Key("F")
  Check(P.On(), "after combat the next line brings it back")
  Check(#W.faults == 0, "no errors in combat: " .. table.concat(W.faults, " | "))
end
do
  -- the offset can't be put back once the lockdown is on: it waits for combat to end
  local c, W, F = Fresh()
  F.Present.Configure("camera.offset", -1)
  W.Advance(1.2); W.Key("F")
  W.combat = true
  F.Camera.Restore("test")
  Check(W.cvars.test_cameraOverShoulder == "-1.00", "no camera setting is changed in lockdown")
  W.Peace()
  Check(W.cvars.test_cameraOverShoulder == "0", "it is put back as combat ends")
end

---------------------------------------------------------------------------
-- 6. Reload, logout and disconnect: the camera comes back at the next start-up
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  F.Present.Configure("camera.offset", 1)
  W.Advance(1.2); W.Key("F"); W.Advance(2)
  local db = FishRoundTrip(c.TwichUIFishingDB)
  Check(db.client.camera and db.client.camera.zoom.before == 15, "the values to put back are saved before anything changes")
  -- a reload with the camera as Fishing Mode left it
  local c2, W2 = Fresh({ db = db, cam = { zoom = 7, offset = "1.00" } })
  c2.TwichUI.RunCommand("fish")
  c2.FireEvent("PLAYER_ENTERING_WORLD", false, true)
  Check(W2.camera.zoom == 15 and W2.cvars.test_cameraOverShoulder == "0", "after a reload the camera is put back")
  Check(c2.TwichUIFishingDB.client.camera == nil and not c2.TwichUI.Fishing.Present.On(), "the record is gone and Fishing Mode is off")
  -- the player changed the camera before the reload finished: theirs stays
  local c3, W3 = Fresh({ db = FishRoundTrip(db), cam = { zoom = 12 } })
  c3.TwichUI.RunCommand("fish")
  c3.FireEvent("PLAYER_ENTERING_WORLD", false, true)
  Check(W3.camera.zoom == 12, "a distance the player chose since is kept")
end
do
  local c, W, F = Fresh()
  F.Present.Configure("camera.offset", 1)
  W.Advance(1.2); W.Key("F"); W.Advance(2)
  c.FireEvent("PLAYER_LOGOUT")
  Check(W.cvars.test_cameraOverShoulder == "0", "logout: the offset is put back before the game saves its settings")
  Check(c.TwichUIFishingDB.client.camera and c.TwichUIFishingDB.client.camera.zoom, "the zoom's record is kept for the next start-up (the move may not finish)")
  local c2, W2 = Fresh({ db = FishRoundTrip(c.TwichUIFishingDB), cam = { zoom = 7 } })
  c2.TwichUI.RunCommand("fish")
  c2.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  Check(W2.camera.zoom == 15 and c2.TwichUIFishingDB.client.camera == nil, "and the next login finishes it")
end

---------------------------------------------------------------------------
-- 7. An error part-way puts everything back; /tui fish recover always does
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  local apply = F.Fade.Apply
  F.Fade.Apply = function() error("boom") end
  W.Advance(1.2); W.Key("F")
  Check(not F.Present.On() and W.camera.zoom == 15 and not F.CastBar.Shown(), "a failing step: Fishing Mode off, the camera back, the pieces hidden")
  Check(F.noteCounts["present-error"] == 1 and #W.faults == 1, "the error is noted and reported, not swallowed")
  F.Fade.Apply = apply
  -- recovery after another addon interfered with the camera
  c.TwichUI.RunCommand("fish mode"); W.Advance(2)
  W.camera.zoom = 9
  c.TwichUI.RunCommand("fish recover"); Settle(W)
  Check(W.camera.zoom == 15 and c.MainMenuBar:GetAlpha() == 1 and not F.Present.On(), "recover: the camera and interface back whatever changed them")
  Check(not c.TwichUI.QuietScreen.On(), "and the hold is let go")
end

---------------------------------------------------------------------------
-- 8. Missing client functions: no camera, no gamepad, no Quiet screen
---------------------------------------------------------------------------
do
  local c, W, F = Fresh({ camera = false })
  F.Present.Configure("present.vibrate", true)
  W.Advance(1.2); W.Key("F"); W.Interact(); W.Advance(0.1); Settle(W)
  Check(F.Present.On() and c.MainMenuBar:GetAlpha() == 0, "no camera functions: the rest of Fishing Mode works")
  Check(F.noteCounts["camera-unsupported"] == 1 and not F.Camera.Status().supported.zoom, "the camera is reported unsupported")
  Check(#W.faults == 0, "nothing fails without a camera or a gamepad: " .. table.concat(W.faults, " | "))
  c.TwichUI.QuietScreen = nil
  c.TwichUI.RunCommand("fish stop"); Settle(W)
  Check(c.MainMenuBar:GetAlpha() == 1 and #W.faults == 0, "and without the Quiet screen")
end

---------------------------------------------------------------------------
-- 9. The controller: its keys, gamepad names, vibration only on a confirmed catch, nothing bound or pressed
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  local L = c.TwichUI.FishingLauncher
  local H = F.Hud
  W.bound.PAD1 = KEY; W.bound.PADFORWARD = "TWICHUI_FISHING_MODE"; W.bound.PADLSHOULDER = "TWICHUI_FISHING_REVEAL"
  local vib = {}
  c.C_GamePad = { IsEnabled = function() return true end, GetActiveDeviceID = function() return 0 end,
    SetVibration = function(kind, s) vib[#vib + 1] = kind .. s end, StopVibration = function() vib[#vib + 1] = "stop" end }
  Check(H.Key(KEY) == "A" and H.Key("TWICHUI_FISHING_MODE") == "Start", "gamepad buttons are named for the prompts while a gamepad is in use")
  L.Mode()
  Check(F.Present.On(), "the Fishing Mode key turns it on")
  Settle(W)
  L.Reveal("down"); Settle(W)
  Check(c.MainMenuBar:GetAlpha() == 1, "the reveal key, held, brings the interface back")
  L.Reveal("up"); Settle(W)
  Check(c.MainMenuBar:GetAlpha() == 0, "released, it fades again")
  local text = F.CastBar.NoteText()
  Check(text:find("A to fish", 1, true) and text:find("hold LB", 1, true) and text:find("Start to leave", 1, true), "the prompts name the pad buttons: " .. text)
  W.Advance(1.2); W.Key("PAD1")
  Check(W.channel ~= nil and #vib == 0, "the pad casts through Stage 1's key; casting never vibrates (no bite signal exists)")
  W.Interact(); W.Advance(0.5)
  Check(#vib == 0, "vibration is off unless asked for")
  F.Present.Configure("present.vibrate", true)
  W.Advance(1.2); W.Key("PAD1"); W.Interact(); W.Advance(0.5)
  Check(vib[1] == "Low0.35" and vib[2] == "stop", "asked for: a short pulse on a confirmed catch only")
  L.Mode()
  Check(not F.Present.On(), "the same key turns it off")
  local n = 0 for _ in pairs(W.bound) do n = n + 1 end
  Check(n == 4, "no key was bound or changed by TwichUI")
  -- Stage 2's files never touch secure attributes, bindings or actions
  for _, file in ipairs({ "Hud", "Camera", "Fade", "CastBar", "CatchList", "Toast", "Present" }) do
    local src = io.open(ROOT .. "../TwichUI_Fishing/" .. file .. ".lua"):read("*a")
    for _, word in ipairs({ "SetAttribute", "SetOverrideBinding", "SetBinding", "CastSpell", "InteractUnit", "UseContainerItem",
        "EquipItemByName", "UseAction", "RegisterGameMenuEscHandler", "SetView", "SaveView" }) do
      Check(not src:find(word .. "(", 1, true) and not src:find(word .. " (", 1, true), file .. ".lua never calls " .. word)
    end
  end
end

---------------------------------------------------------------------------
-- 10. Stage 1 underneath: the same records with and without Fishing Mode; held data and pending gear are shown
---------------------------------------------------------------------------
do
  local function Run(mode)
    local c, W, F = Fresh()
    c.TwichUI.RunCommand("fish mode " .. mode)
    Fish(c, W); Fish(c, W, { { FISH2, 2 } }); Fish(c, W, false); W.StopLine(); W.Advance(2)
    local s = F.Session.Current()
    return { s.casts, s.catches, s.items, s.missed, W.calls.casts }
  end
  local a, b = Run("immersive"), Run("classic")
  Check(table.concat(a, ",") == table.concat(b, ","), "Stage 1 records the same with Fishing Mode on as off: " .. table.concat(a, ",") .. " / " .. table.concat(b, ","))
end
do
  local c, W, F = Fresh({ db = { schema = 99, chars = {} } })
  c.TwichUI.RunCommand("fish mode")
  Check(F.Present.On() and F.Store.held, "held saved data: Fishing Mode still works")
  local text, warn = F.CastBar.NoteText()
  Check(warn and text:find("read-only", 1, true), "and the cast bar says the records are held")
  W.Advance(2)
  Check(c.TwichUIFishingDB.client == nil, "nothing is written to held data (the camera record stays in memory)")
  c.TwichUI.RunCommand("fish mode")
  Check(W.camera.zoom == 15, "and the camera still comes back")
end
do
  local c, W, F = Fresh()
  W.Wear(16, SWORD); W.Wear(17, SHIELD); W.Give(POLE)
  c.TwichUI.RunCommand("fish mode")
  W.Advance(1.2); W.Key("F")           -- equips the pole
  W.blockInsecure.equip = true
  c.TwichUI.RunCommand("fish stop"); W.Advance(3)
  Check(F.Gear.State() == "pending", "restoration is pending (addon code was blocked)")
  c.TwichUI.RunCommand("fish mode")
  local text, warn = F.CastBar.NoteText()
  Check(warn and text:find("press F", 1, true), "the cast bar shows the pending gear and the key that puts it back: " .. text)
end

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED test_fishing_present")
