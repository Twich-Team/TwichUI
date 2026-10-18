dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Marker cycling (markers/Markers.lua, markers/Keys.lua, TwichUI_Settings/pages/Markers.lua):
--   * the markers' identities and the two kinds kept apart; the saved order with skipped markers keeping their place;
--     damaged and imported orders checked (unknown ids, duplicates, missing ones, extra fields) and repaired narrowly;
--   * the secure buttons' own snippets, run here in a stand-in for the game's restricted environment: forward cycling
--     and wrap-around, skipped markers, empty and single sequences, one step per key press whichever edge the game
--     acts on, no target / an enemy under the mouse, a target already wearing the marker, restart vs clear (restart
--     never removes anything), world markers placed at the pointer with no targeting circle;
--   * combat: a change waits for combat to end and only the latest is given; the keys keep working meanwhile;
--   * keys: only our own actions bound or unbound, a key that does something else is asked about first, a key another
--     addon has taken over is reported, turning the feature off leaves keys alone;
--   * profiles, a reload and configuration sharing (keys never travel);
--   * the order editor: arrows, ticks, drag and drop (the drop place shown, cancelling, closing mid-drag, a scaled
--     window), and that nothing there ever marks or clears in the game.
-- The game's own button code is stood in for from what WoW: Forever's SecureTemplates.lua shows; whether the game
-- then accepts a mark (permission, range) can't be tested here: docs/marker-cycling.md has the in-game checks.

local checks = 0
local function Check(cond, msg)
  checks = checks + 1
  if not cond then error("FAILED: " .. msg, 2) end
end

---------------------------------------------------------------------------
-- Stand-in frames (as tests/test_settings_window.lua's), with attributes, frame refs and a place on screen
---------------------------------------------------------------------------
local function Fake(kind, parent)
  local f = { kind = kind, parent = parent, scripts = {}, hooks = {}, points = {}, shown = true, w = 0, h = 0,
    text = "", enabled = true, focus = false, scroll = 0, attrs = {}, refs = {} }
  local function Fire(self, name, ...)
    if self.scripts[name] then self.scripts[name](self, ...) end
    for _, h in ipairs(self.hooks[name] or {}) do h(self, ...) end
  end
  f.Fire = Fire
  local methods = {
    SetScript = function(s, n, fn) s.scripts[n] = fn; s.hooks[n] = nil end,
    GetScript = function(s, n) return s.scripts[n] end,
    HookScript = function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end,
    SetSize = function(s, w, h) s.w, s.h = w, h end,
    SetWidth = function(s, w) s.w = w end, SetHeight = function(s, h) s.h = h end,
    GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
    SetPoint = function(s, ...) table.insert(s.points, { ... }) end,
    ClearAllPoints = function(s) s.points = {} end,
    GetPoint = function(s, i) local p = s.points[i or 1]; if p then return unpack(p) end end,
    Show = function(s) if not s.shown then s.shown = true; Fire(s, "OnShow") end end,
    Hide = function(s) if s.shown then s.shown = false; Fire(s, "OnHide") end end,
    SetShown = function(s, v) if v then s:Show() else s:Hide() end end,
    IsShown = function(s) return s.shown end,
    IsVisible = function(s) local p = s while p do if not p.shown then return false end p = p.parent end return true end,
    SetText = function(s, t) s.text = t == nil and "" or tostring(t) end,
    GetText = function(s) return s.text end,
    GetStringHeight = function(s) return 12 * math.max(1, math.ceil(#s.text * 6 / (s.w > 0 and s.w or 400))) end,
    GetStringWidth = function(s) return #s.text * 6 end,
    IsTruncated = function() return false end,
    SetEnabled = function(s, v) s.enabled = v and true or false; Fire(s, v and "OnEnable" or "OnDisable") end,
    Enable = function(s) s:SetEnabled(true) end, Disable = function(s) s:SetEnabled(false) end,
    IsEnabled = function(s) return s.enabled end,
    SetMinMaxValues = function() end, SetValue = function() end, GetValue = function() return 0 end,
    GetThumbTexture = function(s) s.thumb = s.thumb or Fake("Texture", s); return s.thumb end,
    SetFocus = function(s) s.focus = true end, ClearFocus = function(s) s.focus = false end, HasFocus = function(s) return s.focus end,
    SetScrollChild = function(s, child) s.child = child end,
    SetVerticalScroll = function(s, v) s.scroll = v end, GetVerticalScroll = function(s) return s.scroll end,
    GetVerticalScrollRange = function() return 0 end,
    IsMouseOver = function() return false end,
    GetEffectiveScale = function(s) return s.scale or (s.parent and s.parent.GetEffectiveScale and s.parent:GetEffectiveScale()) or 1 end,
    GetScale = function() return 1 end,
    GetFrameLevel = function() return 1 end,
    IsOwned = function() return false end, GetOwner = function(s) return s.owner end, SetOwner = function(s, o) s.owner = o end,
    GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end, SetFont = function() return true end,
    SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha or 1 end,
    CreateTexture = function(s) return Fake("Texture", s) end,
    CreateFontString = function(s) return Fake("FontString", s) end,
    SetTexture = function(s, p) s.texture = p end, SetDesaturated = function(s, v) s.desaturated = v end,
    SetParent = function(s, p) s.parent = p end, GetParent = function(s) return s.parent end,
    SetAttribute = function(s, k, v) s.attrs[k] = v end, GetAttribute = function(s, k) return s.attrs[k] end,
    GetFrameRef = function(s, label) return s.refs[label] end,
    RegisterForClicks = function(s, ...) s.clicks = { ... } end,
    RegisterForDrag = function(s, b) s.dragButton = b end,
    RegisterEvent = function(s, e) s.events = s.events or {}; s.events[e] = true end,
    UnregisterEvent = function(s, e) if s.events then s.events[e] = nil end end,
    EnableKeyboard = function(s, v) s.keyboard = v end,
    SetPropagateKeyboardInput = function(s, v) s.propagate = v end,
    GetLeft = function(s) return s.geom and s.geom.left end, GetRight = function(s) return s.geom and s.geom.right end,
    GetTop = function(s) return s.geom and s.geom.top end, GetBottom = function(s) return s.geom and s.geom.bottom end,
    CreateAnimationGroup = function()
      local g = setmetatable({}, { __index = function() return function() end end })
      function g:CreateAnimation() return setmetatable({}, { __index = function() return function() end end }) end
      return g
    end,
  }
  return setmetatable(f, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end

---------------------------------------------------------------------------
-- The game, as far as these keys reach it
---------------------------------------------------------------------------
local game = { target = nil, mouseover = nil, marks = {}, calls = {}, keyDown = true, combat = false }
local function Call(...) game.calls[#game.calls + 1] = { ... } end
local function Calls(name)
  local n = 0
  for _, c in ipairs(game.calls) do if c[1] == name then n = n + 1 end end
  return n
end
local said = {}
local binds, overrides, setBindingCalls, saves = {}, {}, 0, 0
local cursor = { x = 0, y = 0 }
local shiftDown = false

local c, S = SettingsClient({ beforeInit = function(c)
  c.CreateFrame = function(kind, name, parent) local f = Fake(kind, parent); if name then c[name] = f end return f end
  c.UIParent = Fake("Frame"); c.UIParent.w, c.UIParent.h = 1920, 1080
  c.GameTooltip = Fake("GameTooltip")
  c.UISpecialFrames = {}
  c.InCombatLockdown = function() return game.combat end
  -- the restricted API's set-up calls (SecureHandlers.lua): recorded, run below by Press
  c.SecureHandlerWrapScript = function(frame, script, header, pre) frame.wrapped = frame.wrapped or {}; frame.wrapped[script] = pre; frame.header = header end
  c.SecureHandlerSetFrameRef = function(frame, label, ref) frame.refs[label] = ref end
  c.UIErrorsFrame = { AddMessage = function(_, text) said[#said + 1] = text end }
  c.IsRaidMarkerSystemEnabled = function() return true end
  -- key bindings: one action per key (the game's rule), and override bindings another addon may hold
  c.GetBindingKey = function(action)
    local keys = {}
    for k, a in pairs(binds) do if a == action then keys[#keys + 1] = k end end
    table.sort(keys)
    return unpack(keys)
  end
  c.GetBindingAction = function(key, checkOverride)
    if checkOverride and overrides[key] then return overrides[key] end
    return binds[key] or ""
  end
  c.SetBinding = function(key, action) setBindingCalls = setBindingCalls + 1; binds[key] = action; return true end
  c.SaveBindings = function() saves = saves + 1 end
  c.GetCurrentBindingSet = function() return 2 end
  c.GetBindingText = function(key) return (key:gsub("SHIFT%-", "Shift-")) end
  c.GetBindingName = function(action) return c["BINDING_NAME_" .. action] or action end
  c.BINDING_NAME_MOVEFORWARD = "Move Forward"
  c.CreateKeyChordStringUsingMetaKeyState = function(key) return (shiftDown and "SHIFT-" or "") .. key end
  c.IsKeyPressIgnoredForBinding = function(key) return key == "LSHIFT" or key == "RSHIFT" end
  c.GetConvertedKeyOrButton = function(b) return ({ LeftButton = "BUTTON1", RightButton = "BUTTON2", Button4 = "BUTTON4" })[b] or b end
  c.GetCursorPosition = function() return cursor.x, cursor.y end
  c.GetCurrentKeyBoardFocus = function() return nil end
  c.SLASH_WORLD_MARKER1 = "/wm"
  c.RAID_TARGET_8 = "Skull"   -- the rest fall back to their English names
end })
local R, K = c.TwichUI, S.K
local M, MK = R.Markers, R.MarkerKeys

-- What the game's restricted environment offers the snippets here, and nothing more.
local function Restricted()
  return {
    SecureCmdOptionParse = function(text)
      if text:find("@mouseover", 1, true) and game.mouseover then return "mouseover" end
      if game.target then return "target" end
      return nil
    end,
  }
end

-- The game's own button code on the edge it acts on (SecureTemplates.lua: raidtarget "set" marks only a unit not
-- already wearing that marker; "clear" sets 0; a unit that doesn't exist does nothing; worldmarker "clear" with no
-- marker is every world marker; macro runs its text).
local function Act(b)
  local t = b.attrs.type
  if t == "raidtarget" then
    local unit = b.attrs.unit or "target"
    local who = game[unit]
    if not who then return end
    local marker = tonumber(b.attrs.marker) or 1
    if b.attrs.action == "set" then
      if game.marks[who] ~= marker then Call("SetRaidTarget", who, marker); if not game.refuse then game.marks[who] = marker end end
    elseif b.attrs.action == "clear" then
      Call("SetRaidTarget", who, 0); game.marks[who] = nil
    elseif b.attrs.action == "toggle" then
      Call("toggle")
    end
  elseif t == "macro" then
    Call("macro", b.attrs.macrotext)
  elseif t == "worldmarker" then
    Call(b.attrs.action == "clear" and "ClearRaidMarker" or "PlaceRaidMarker", b.attrs.marker)
  end
end

-- One key press: the snippet on each edge the game sends, the action on the edge "cast on key down" picks, then
-- the button's PostClick (as the game's Click runs PreClick, OnClick, PostClick).
local function Press(name, edges)
  local b = assert(c[name], name .. " exists")
  local function Edge(down)
    local fn = assert(loadstring("local self, button, down = ...\n" .. b.wrapped.PreClick))
    setfenv(fn, Restricted())
    fn(b, "LeftButton", down)
    if down == game.keyDown then Act(b) end
    if b.scripts.PostClick then b.scripts.PostClick(b, "LeftButton", down) end
  end
  if edges ~= "up" then Edge(true) end
  if edges ~= "down" then Edge(false) end
end

local function LastMark(who)
  for i = #game.calls, 1, -1 do
    local call = game.calls[i]
    if call[1] == "SetRaidTarget" and call[2] == who then return call[3] end
  end
end

local function Reset()
  game.calls, game.marks, said = {}, {}, {}
end

---------------------------------------------------------------------------
-- 1. The markers: two kinds, kept apart
---------------------------------------------------------------------------
Check(table.concat(M.Order("target"), ",") == "8,7,6,5,4,3,2,1", "target markers start Skull, Cross, Square, Moon, Triangle, Diamond, Circle, Star")
Check(table.concat(M.Order("world"), ",") == "8,4,1,7,2,3,6,5", "world markers start in the same icons' order (their own numbers)")
Check(M.Name("target", 8) == "Skull" and M.Name("target", 1) == "Star", "target names, the game's where it has one")
Check(M.Name("world", 1) == "Square" and M.Name("world", 5) == "Star" and M.Name("world", 8) == "Skull", "world marker 1 is the Square, 5 the Star")
Check(M.Texture("world", 1):find("UI%-RaidTargetingIcon_6$") and M.Texture("target", 6):find("UI%-RaidTargetingIcon_6$"), "the same icon file for the same symbol")
do
  local seen = {}
  for id = 1, 8 do seen[M.Icon("world", id)] = true end
  local n = 0 for _ in pairs(seen) do n = n + 1 end
  Check(n == 8, "each world marker shows a different icon")
  for i = 1, 8 do Check(M.Name("world", M.Order("world")[i]) == M.Name("target", M.Order("target")[i]), "both kinds' defaults show the same icons in the same order (" .. i .. ")") end
end
Check(M.Name("target", 9) == "?" and M.Texture("target", 0) == nil, "an unknown id has no identity")

---------------------------------------------------------------------------
-- 2. The saved order: skipping keeps a marker's place; moving keeps its tick
---------------------------------------------------------------------------
Check(M.SetOn("target", 7, false) and not M.IsOn("target", 7), "Cross is skipped")
Check(table.concat(M.Order("target"), ",") == "8,7,6,5,4,3,2,1", "... and keeps its place in the order")
Check(table.concat(M.Sequence("target"), ",") == "8,6,5,4,3,2,1", "... and presses pass over it")
Check(M.Move("target", 2, 5), "move Cross from 2 to 5")
Check(table.concat(M.Order("target"), ",") == "8,6,5,4,7,3,2,1" and not M.IsOn("target", 7), "moved, still skipped")
Check(table.concat(M.Order("world"), ",") == "8,4,1,7,2,3,6,5", "the other kind is untouched")
Check(M.DropTarget(1, 3) == 3 and M.DropTarget(5, 1) == 2 and M.DropTarget(3, 2) == 3 and M.DropTarget(3, 3) == 3 and M.DropTarget(8, 0) == 1 and M.DropTarget(1, 8) == 8,
  "a drop gap gives the place it lands in (a gap beside itself changes nothing)")
Check(not M.Move("target", 0, 2) and not M.Move("target", 1, 9), "a move outside the eight is refused")
Check(M.SetOn("target", 7, true) and M.ResetOrder("target") and M.IsDefault("target"), "the default order back")

-- checking orders
Check(M.ValidOrder({ 8, 7, 6, 5, 4, 3, 2, 1 }), "a whole order")
Check(not M.ValidOrder({ 8, 8, 6, 5, 4, 3, 2, 1 }), "a duplicate is refused")
Check(not M.ValidOrder({ 8, 7, 6, 5, 4, 3, 2 }), "seven is refused")
Check(not M.ValidOrder({ 8, 7, 6, 5, 4, 3, 2, 9 }), "an unknown id is refused")
Check(not M.ValidOrder({ 8, 7, 6, 5, 4, 3, 2, 1.5 }), "a fraction is refused")
Check(not M.ValidOrder({ 8, 7, 6, 5, 4, 3, 2, "1" }), "text is refused")
Check(not M.ValidOrder({ 8, 7, 6, 5, 4, 3, 2, 1, x = 1 }), "a named key is refused")
Check(not M.SetOrder("target", { 1, 1, 1, 1, 1, 1, 1, 1 }) and M.IsDefault("target"), "a bad order saves nothing")
Check(M.ValidOff({}) and M.ValidOff({ 3, 1 }) and not M.ValidOff({ 3, 3 }) and not M.ValidOff({ 0 }) and not M.ValidOff({ [2] = 4 }), "the skipped list: known ids, once each")

-- damaged saved data: repaired narrowly, never the other kind
c.TwichUIDB.ui.markerOrder = { target = { order = { 8, 8 }, off = { 3 } }, world = { order = { 1, 2, 3, 4, 5, 6, 7, 8 }, off = "x" } }
Check(table.concat(M.Order("target"), ",") == "8,7,6,5,4,3,2,1" and not M.IsOn("target", 3), "a damaged order is used as the default; its skipped list still counts")
Check(table.concat(M.Order("world"), ",") == "1,2,3,4,5,6,7,8" and next(M.OffSet("world")) == nil, "a damaged skipped list counts as none skipped; the order is kept")
c.TwichUIDB.ui.markerOrder = nil

-- the cycle's arithmetic
do
  local seq = { 8, 7, 6 }
  local got, step = {}, 0
  for i = 1, 7 do got[i], step = M.NextAfter(seq, step) end
  Check(table.concat(got, ",") == "8,7,6,8,7,6,8", "forward, and back to the first after the last")
  Check(M.NextAfter({}, 0) == nil, "an empty sequence gives nothing")
  Check(M.NextAfter({ 4 }, 0) == 4 and M.NextAfter({ 4 }, 1) == 4, "one marker: the same every time")
  Check(M.NextAfter(seq, 0) == 8, "step 0 (restarted) is the first marker")
end

---------------------------------------------------------------------------
-- 3. The keys' buttons: off until turned on; then forward, wrap-around, one step per press
---------------------------------------------------------------------------
Check(MK.Built(), "the buttons were made at load (out of combat)")
local T, TR, TC_, WN, WR, WC = "TwichUIMarkTargetNext", "TwichUIMarkTargetRestart", "TwichUIMarkTargetClear",
  "TwichUIMarkWorldNext", "TwichUIMarkWorldRestart", "TwichUIMarkWorldClear"
for _, name in ipairs({ T, TR, TC_, WN, WR, WC }) do
  local b = c[name]
  Check(b and b.wrapped and b.wrapped.PreClick and b.header == b, name .. " is a secure button with its own snippet")
  Check(b.clicks and #b.clicks == 2, name .. " hears both edges of a key")
  Check(b.points[1] == nil, name .. " is never placed on screen")
end
Check(c[T].attrs.action == "set", "the target key uses the game's 'set', which never takes a marker off (not 'toggle')")
Check(c[TC_].attrs.action == "clear" and c[WC].attrs.action == "clear" and c[WC].attrs.marker == nil, "the clear keys: one target's marker, every world marker")
Check(c[TR].refs.cycle == c[T] and c[TC_].refs.cycle == c[T] and c[WR].refs.cycle == c[WN], "restart and clear reach their own kind's cycle")
Check(c["BINDING_NAME_CLICK " .. T .. ":LeftButton"]:find("^Target markers") and c["BINDING_NAME_CLICK " .. WN .. ":LeftButton"]:find("^World markers"), "the game's Key Bindings list names them")
Check(next(binds) == nil and setBindingCalls == 0, "no key is bound by itself")

-- off (the default)
game.target = "Ogre"
Reset()
Press(T)
Check(#game.calls == 0 and MK.Step("target") == 0, "off: a press marks nothing and the cycle stays put")
Check(said[1] and said[1]:find("off"), "off: a press says so, once, where the game shows its own messages: " .. tostring(said[1]))
Check(#said == 1, "one line for the press and the release")

R:SetEnabled("markersTarget", true)
Check(c[T].attrs["twichui-on"] == true and c[T].attrs["twichui-count"] == 8, "on: the button has the eight markers")
Reset()
local marks = {}
for i = 1, 9 do Press(T); marks[i] = LastMark("Ogre") end
Check(table.concat(marks, ",") == "8,7,6,5,4,3,2,1,8", "eight presses in order, the ninth is the first again: " .. table.concat(marks, ","))
Check(Calls("toggle") == 0 and #said == 0, "no toggling, and nothing said for a working press")

-- one step per press, whichever edge the game sends and whichever it acts on
for _, keyDown in ipairs({ true, false }) do
  game.keyDown = keyDown
  MK.Restart("target")
  Reset()
  Press(T); Press(T); Press(T)
  Check(MK.Step("target") == 3 and Calls("SetRaidTarget") == 3, "press and release: one step and one mark each (act on " .. (keyDown and "down" or "up") .. ")")
end
game.keyDown = false
MK.Restart("target")
Reset()
Press(T, "up"); Press(T, "up")
Check(MK.Step("target") == 2 and Calls("SetRaidTarget") == 2, "a key that only sends its release still steps once per press")
game.keyDown = true
MK.Restart("target")
Reset()
Press(T, "down"); Press(T, "down")
Check(MK.Step("target") == 2 and Calls("SetRaidTarget") == 2, "... and one that only sends its press")

-- skipped markers, a single one, none
MK.Restart("target")
M.SetOn("target", 7, false); M.SetOn("target", 5, false)
Reset()
marks = {}
for i = 1, 7 do Press(T); marks[i] = LastMark("Ogre") end
Check(table.concat(marks, ",") == "8,6,4,3,2,1,8", "skipped markers are passed over: " .. table.concat(marks, ","))
for _, id in ipairs({ 8, 6, 4, 3, 2 }) do M.SetOn("target", id, false) end
Check(table.concat(M.Sequence("target"), ",") == "1", "only the Star left")
Reset()
Press(T); Press(T); Press(T)
Check(Calls("SetRaidTarget") == 1 and LastMark("Ogre") == 1, "one marker: the target keeps it; later presses change nothing on it")
M.SetOn("target", 1, false)
Check(#M.Sequence("target") == 0, "every marker skipped is a valid choice")
Reset()
Press(T)
Check(#game.calls == 0 and MK.Step("target") == 0 and said[1] and said[1]:find("every target marker is turned off"), "nothing to place: nothing happens, and it says why")
M.ResetOrder("target")
Check(MK.Step("target") == 0, "a new sequence starts at its first marker")

-- no target, an enemy under the mouse, a target already wearing the marker, a refused mark
game.target = nil
Reset()
Press(T)
Check(#game.calls == 0 and MK.Step("target") == 0 and #said == 0, "no target: nothing happens, the cycle stays put, nothing is said (as the game's own keys)")
game.target = "Ogre"
game.marks.Ogre = 8
Press(T)
Check(Calls("SetRaidTarget") == 0 and MK.Step("target") == 1, "a target already wearing the next marker keeps it, and the cycle moves on")
Press(T)
Check(LastMark("Ogre") == 7, "the next press gives it the next marker")
M.Set("targetUnit", "mouseover")
Check(MK.Step("target") == 2, "changing which unit is marked keeps the cycle's place")
game.mouseover = "Imp"
Reset()
Press(T)
Check(LastMark("Imp") == 6 and LastMark("Ogre") == nil, "an enemy under the mouse first")
game.mouseover = nil
Press(T)
Check(LastMark("Ogre") == 5, "no enemy under the mouse: the target")
M.Set("targetUnit", "target")
game.refuse = true
Reset()
local before = MK.Step("target")
Press(T)
Check(MK.Step("target") == before + 1, "a mark the game refuses (no permission) still uses its turn: the press is all a key can see")
game.refuse = nil

-- restart vs clear
Reset()
Press(TR)
Check(MK.Step("target") == 0 and #game.calls == 0, "restart: the next press is the first again, and nothing is removed")
Check(said[1] and said[1]:find("restarted") and said[1]:find("Skull"), "restart says which marker is next: " .. tostring(said[1]))
Press(T)
Check(LastMark("Ogre") == 8, "after a restart: the first marker")
Press(T)
Reset()
Press(TC_)
Check(LastMark("Ogre") == 0 and MK.Step("target") == 0, "clear: your target's marker is removed and (by default) the cycle restarts")
M.Set("targetClearRestarts", false)
Press(T); Press(T)
Press(TC_)
Check(MK.Step("target") == 2, "with restarting off, clearing only removes")
M.Set("targetClearRestarts", true)
game.target = nil
Reset()
Press(TC_)
Check(#game.calls == 0 and MK.Step("target") == 2, "clear with no target: nothing removed, the cycle not restarted")
game.target = "Ogre"

---------------------------------------------------------------------------
-- 4. World markers: placed at the pointer, at once
---------------------------------------------------------------------------
Reset()
Press(WN)
Check(#game.calls == 0 and said[1]:find("world marker cycling is off"), "world markers have their own switch (off)")
R:SetEnabled("markersWorld", true)
Reset()
local texts = {}
for i = 1, 9 do Press(WN); texts[i] = game.calls[#game.calls][2] end
Check(texts[1] == "/wm [@cursor] 8" and texts[2] == "/wm [@cursor] 4" and texts[3] == "/wm [@cursor] 1" and texts[9] == "/wm [@cursor] 8",
  "the world key places the next marker at the pointer, in world numbers, and wraps: " .. table.concat(texts, " | "))
Check(Calls("PlaceRaidMarker") == 0, "no targeting circle (nothing to confirm or cancel, so nothing pending)")
Check(MK.Step("target") == 2, "the target cycle is its own")
Reset()
Press(WR)
Check(MK.Step("world") == 0 and #game.calls == 0, "world restart removes nothing")
Press(WN); Press(WN)
Press(WC)
Check(Calls("ClearRaidMarker") == 1 and game.calls[#game.calls][2] == nil and MK.Step("world") == 0, "remove all world markers, and restart")
M.Set("worldClearRestarts", false)
Press(WN)
Press(WC)
Check(MK.Step("world") == 1, "with restarting off, removing world markers keeps the cycle's place")
M.Set("worldClearRestarts", true)

---------------------------------------------------------------------------
-- 5. Combat: changes wait, the latest one is given, the keys keep working
---------------------------------------------------------------------------
MK.Restart("target")
game.combat = true
M.SetOn("target", 8, false)
Check(not M.IsOn("target", 8), "a change in combat is saved at once")
Check(MK.Pending("target") and c[T].attrs["twichui-count"] == 8, "... and waits: the button still has the old sequence")
Check(not MK.Pending("world"), "only the kind that changed waits")
Reset()
Press(T)
Check(LastMark("Ogre") == 8, "the keys keep working in combat, with what they had")
Press(TR)
Check(MK.Step("target") == 0, "the restart key works in combat")
Check(not MK.Restart("target"), "the settings' restart can't touch a secure button in combat")
M.SetOn("target", 7, false)
game.combat = false
c.FireEvent("PLAYER_REGEN_ENABLED")
Check(not MK.Pending("target") and c[T].attrs["twichui-count"] == 6, "combat over: the latest sequence is given")
Check(MK.Step("target") == 0 and MK.NextMarker("target") == 6, "... starting at its first marker (Square)")
game.combat = true
M.SetOn("target", 8, true)
Check(MK.Pending("target"), "waiting again")
M.SetOn("target", 8, false)
Check(not MK.Pending("target"), "changed back before combat ended: nothing waits")
game.combat = false
c.FireEvent("PLAYER_REGEN_ENABLED")
M.ResetOrder("target")
Check(c[T].attrs["twichui-count"] == 8, "out of combat a change is given at once")

---------------------------------------------------------------------------
-- 6. Keys: only ours, asked about first when taken, kept while off
---------------------------------------------------------------------------
binds["SHIFT-F"] = "MOVEFORWARD"
binds["G"] = "SOMETHING_ELSE"
Check(MK.SetKey("targetNext", "F") and binds.F == "CLICK " .. T .. ":LeftButton" and saves == 1, "a free key is bound and saved")
Check(MK.KeyText("targetNext") == "F", "its key, as the game names it")
Check(MK.SetKey("targetNext", "H") and binds.F == nil and binds.H ~= nil, "a new key replaces our own first key")
Check(binds.G == "SOMETHING_ELSE" and binds["SHIFT-F"] == "MOVEFORWARD", "other bindings are untouched")
game.combat = true
Check(select(2, MK.SetKey("targetNext", "J")) == "combat" and binds.J == nil, "no binding changes in combat")
Check(select(2, MK.RemoveKeys("targetNext")) == "combat" and binds.H ~= nil, "... nor removing")
game.combat = false
Check(not MK.SetKey("nope", "K") and not MK.SetKey("targetNext", "BAD KEY"), "only our actions, and plain key names")
local bound = MK.KeyUse("SHIFT-F")
Check(bound == "MOVEFORWARD" and MK.ActionName(bound) == "Move Forward", "what a key does now, in words")
overrides.H = "CLICK WorldMarkerCyclerButton:LeftButton"
local taken = MK.TakenOver("targetNext")
Check(taken[1] and taken[1].key == "H" and MK.ActionName(taken[1].action):find("World Marker Cycler"), "a key another addon has taken over is found, and named")
overrides.H = nil
local callsBefore = setBindingCalls
R:SetEnabled("markersTarget", false)
R:SetEnabled("markersTarget", true)
Check(setBindingCalls == callsBefore and binds.H ~= nil, "turning the feature off and on leaves keys alone")
Check(MK.RemoveKeys("targetNext") and binds.H == nil and binds["SHIFT-F"] == "MOVEFORWARD", "removing unbinds only ours")
Check(not MK.OtherCycler(), "World Marker Cycler isn't loaded here")
c.LOADED.WorldMarkerCycler = true
Check(MK.OtherCycler(), "... and is seen when it is (never called)")
c.LOADED.WorldMarkerCycler = nil
Check(c.WMC_Saved == nil and c.WorldMarkerCyclerAPI == nil, "its saved data and functions are never touched or made")

---------------------------------------------------------------------------
-- 7. Profiles, a reload, configuration sharing
---------------------------------------------------------------------------
local PF = R.Profiles
M.SetOn("target", 3, false)
M.Move("world", 1, 8)
Check(PF.Create("Raid nights"), "a new profile (defaults)")
Check(M.IsDefault("target") and M.IsDefault("world") and not R:Enabled("markersTarget"), "its own orders and switches: the defaults")
Check(c[T].attrs["twichui-on"] == false and c[T].attrs["twichui-count"] == 8, "the buttons follow the new profile")
Check(PF.Switch("Default"), "back")
Check(not M.IsOn("target", 3) and M.Order("world")[8] == 8 and R:Enabled("markersTarget"), "the first profile's orders are as they were")
Check(c[T].attrs["twichui-count"] == 7 and c[T].attrs["twichui-on"] == true, "and so are the buttons")
do
  local function Has(t, word)
    for k, v in pairs(t) do
      if type(k) == "string" and k:lower():find(word) then return true end
      if type(v) == "table" and Has(v, word) then return true end
    end
    return false
  end
  Check(not Has(c.TwichUIDB, "step") and not Has(c.TwichUIDB, "pending"), "the cycle's place and anything waiting are never saved (a reload starts at the first marker)")
end

local TC = R.TwichConfig
local g = TC.Group("markerOrder")
Check(g and g.custom and TC.Group("markers"), "the orders and the switches are part of configuration sharing")
local entry = TC.Build({ all = true })
local shared = entry.groups.markerOrder
Check(shared and table.concat(shared.target.off, ",") == "3" and shared.world.order[8] == 8, "the orders in use are shared")
Check(entry.groups.markers.modules.markersTarget == true and entry.groups.markers.markers.targetUnit == "target", "the switches and options too")
do
  local function Text(t, out)
    for k, v in pairs(t) do
      out[#out + 1] = tostring(k)
      if type(v) == "table" then Text(v, out) else out[#out + 1] = tostring(v) end
    end
    return out
  end
  local all = table.concat(Text(entry.groups.markerOrder, {}), " ") .. table.concat(Text(entry.groups.markers, {}), " ")
  Check(not all:find("CLICK") and not all:find("step"), "no key binding and no cycle position travels")
end
-- imports are checked
Check(g.custom.clean({ target = { order = { 8, 8, 6, 5, 4, 3, 2, 1 }, off = {} } }) == nil, "an import with a duplicate is refused")
Check(g.custom.clean({ target = { order = { 8, 7, 6, 5, 4, 3, 2, 9 }, off = {} } }) == nil, "an unknown id is refused")
Check(g.custom.clean({ target = { order = { 8, 7, 6, 5, 4, 3, 2, 1 }, off = { 3, 3 } } }) == nil, "a skipped marker twice is refused")
Check(g.custom.clean({ target = { order = { 8, 7, 6, 5, 4, 3, 2, 1 }, extra = 1 } }) == nil, "an extra field is refused")
Check(g.custom.clean({ raid = {} }) == nil and g.custom.clean({}) == nil and g.custom.clean("x") == nil, "an unknown kind, nothing, or not a table")
local partial = g.custom.clean({ world = { order = { 1, 2, 3, 4, 5, 6, 7, 8 } } })
Check(partial and partial.world and partial.target == nil and #partial.world.off == 0, "one kind alone, with nothing skipped")
local everyOff = g.custom.clean({ target = { order = { 8, 7, 6, 5, 4, 3, 2, 1 }, off = { 1, 2, 3, 4, 5, 6, 7, 8 } } })
Check(everyOff and #everyOff.target.off == 8, "every marker skipped is a valid order to share")
-- applying someone's orders, and undoing it
local theirs = TC.Build({ all = true })
theirs.groups.markerOrder = { target = { order = { 1, 2, 3, 4, 5, 6, 7, 8 }, off = { 2 } } }
local ok = TC.Apply(theirs, { from = "Pal" })
Check(ok, "an import applies")
Check(table.concat(M.Order("target"), ",") == "1,2,3,4,5,6,7,8" and not M.IsOn("target", 2) and M.IsOn("target", 3), "their target order replaced ours, whole")
Check(M.Order("world")[8] == 8, "the world order (not in it) is kept")
Check(c[T].attrs["twichui-m1"] == 1 and c[T].attrs["twichui-count"] == 7, "the buttons follow the import")
Check(binds["SHIFT-F"] == "MOVEFORWARD" and setBindingCalls == callsBefore + 1, "an import never touches key bindings")
Check(TC.Undo(), "undo")
Check(table.concat(M.Order("target"), ",") == "8,7,6,5,4,3,2,1" and not M.IsOn("target", 3), "our own order back")

---------------------------------------------------------------------------
-- 8. The order editor (the settings window, drawn with stand-in frames)
---------------------------------------------------------------------------
local chunk = assert(loadfile(ROOT .. "../TwichUI_Settings/Window.lua")); setfenv(chunk, c); chunk("TwichUI_Settings", {})
local UI = R.SettingsUI
Reset()
UI.Open("markersTarget")
local ed = R.MarkersPage.Frame("target")
Check(ed.built and ed:IsShown(), "the target markers tab shows its order")
Check(K.pages.markersTarget.parent == "qol" and K.pages.markersWorld.parent == "qol", "both are tabs of Quality of life")
local function Order() return table.concat(M.Order("target"), ",") end
local tiles = ed.tiles
Check(tiles[1].name.text == "Skull" and tiles[1].number.text == "1" and tiles[1].icon.texture:find("_8$"), "each marker shows its icon, name and number")
local skipped
for i, t in ipairs(tiles) do if t.id == 3 then skipped = t end end
Check(skipped.state.text == "Skipped" and skipped.number.text == "-" and skipped.icon.desaturated and not skipped.box:GetChecked(),
  "a skipped marker stays in view, says so (not only by color) and has no number")
Check(tiles[8].number.text == "7", "numbers count the ticked markers")
Check(ed.preview.text:find("Next press:") and ed.preview.text:find("Skull"), "the preview names the next marker: " .. ed.preview.text)

-- ticking and the arrows
skipped.box:Fire("OnClick")
Check(M.IsOn("target", 3) and skipped.box:GetChecked(), "ticking a marker turns it back on, in its place")
Check(not tiles[1].left.enabled and tiles[1].right.enabled and not tiles[8].right.enabled, "the arrows stop at the ends")
tiles[1].right:Fire("OnClick")
Check(Order() == "7,8,6,5,4,3,2,1", "Move later")
tiles[2].left:Fire("OnClick")
Check(Order() == "8,7,6,5,4,3,2,1", "Move earlier")
M.SetOn("target", 6, false)
tiles[3].right:Fire("OnClick")
Check(Order() == "8,7,5,6,4,3,2,1" and not M.IsOn("target", 6), "a skipped marker moves and stays skipped")
M.ResetOrder("target")

-- dragging: the drop place is shown, letting go moves it
ed.strip.geom = { left = 100, right = 744, top = 600, bottom = 470 }
local function DragTo(x, y, scale)
  ed.strip.scale = scale
  cursor.x, cursor.y = x * (scale or 1), y * (scale or 1)
  ed.scripts.OnUpdate(ed, 0.016)
end
tiles[1].scripts.OnDragStart(tiles[1])
Check(ed.scripts.OnUpdate ~= nil and ed.ghost.shown, "dragging: the pointer is followed (only now) by the marker")
DragTo(308, 530)   -- over the third tile's left half: the gap after the third
Check(ed.drop.shown, "the place it would land is marked")
Check(ed.note.text:find("Let go to move Skull"), "and said: " .. ed.note.text)
tiles[1].scripts.OnDragStop(tiles[1])
Check(Order() == "7,6,8,5,4,3,2,1" and ed.scripts.OnUpdate == nil and not ed.ghost.shown and not ed.drop.shown, "dropped: Skull is third, and the drag is over")
-- dropping beside where it was changes nothing
tiles[3].scripts.OnDragStart(tiles[3])
DragTo(100 + 8 + 2 * 78 + 30, 530)
Check(not ed.drop.shown, "no place is marked where letting go changes nothing")
tiles[3].scripts.OnDragStop(tiles[3])
Check(Order() == "7,6,8,5,4,3,2,1", "unchanged")
-- cancelled: let go well away from the row
tiles[1].scripts.OnDragStart(tiles[1])
DragTo(400, 530)
DragTo(400, 600 + 120)
Check(not ed.drop.shown and ed.note.text:find("leave Cross where it was"), "far from the row: letting go cancels, and it says so")
tiles[1].scripts.OnDragStop(tiles[1])
Check(Order() == "7,6,8,5,4,3,2,1", "a cancelled drag changes nothing")
-- a scaled window: the same place under the pointer gives the same result
tiles[1].scripts.OnDragStart(tiles[1])
DragTo(100 + 8 + 7 * 78 + 60, 520, 0.8)
tiles[1].scripts.OnDragStop(tiles[1])
Check(Order() == "6,8,5,4,3,2,1,7", "at 80% scale the drop lands where the pointer is: " .. Order())
ed.strip.scale = nil
-- closing mid-drag
tiles[1].scripts.OnDragStart(tiles[1])
DragTo(600, 530)
ed:Hide()
Check(ed.scripts.OnUpdate == nil and Order() == "6,8,5,4,3,2,1,7", "closing the settings mid-drag changes nothing and stops following the pointer")
ed:Show()
-- a drag dropped when the order changes elsewhere
tiles[1].scripts.OnDragStart(tiles[1])
M.ResetOrder("target")
Check(ed.scripts.OnUpdate == nil and not ed.ghost.shown, "an order changed elsewhere (a profile, an import) ends a drag")
if tiles[1].scripts.OnDragStop then tiles[1].scripts.OnDragStop(tiles[1]) end
Check(Order() == "8,7,6,5,4,3,2,1", "and that drag moves nothing")

-- restart and default order buttons
ed.restart:Fire("OnClick")
Check(MK.Step("target") == 0 and ed.note.text:find("Restarted"), "Restart cycle: the next press is the first")
game.combat = true
c.FireEvent("PLAYER_REGEN_DISABLED")
ed.scripts.OnEvent(ed)
Check(not ed.restart.enabled, "Restart cycle waits out of combat (the restart key works then)")
game.combat = false
ed.scripts.OnEvent(ed)
M.Move("target", 1, 2)
S.popup = nil
ed.default:Fire("OnClick")
Check(S.popup and S.popup.key == "TWICHUI_MARKERS_DEFAULT" and S.popup.text:find("Your keys"), "Default order asks first, and says what it leaves alone")
Check(Order() == "7,8,6,5,4,3,2,1", "nothing changes until it is accepted")
c.StaticPopupDialogs.TWICHUI_MARKERS_DEFAULT.OnAccept()
Check(M.IsDefault("target"), "accepted: the default order")

-- choosing a key
R.MarkersPage.Capture("targetNext")
local cap = R.MarkersPage.capture
Check(cap and cap.shown and cap.keyboard and cap.propagate == false, "the key window takes the next key, and passes none on")
cap.scripts.OnKeyDown(cap, "ESCAPE")
Check(not cap.shown and binds.ESCAPE == nil and MK.KeyText("targetNext") == nil, "Esc cancels and binds nothing")
UI.Open("markersTarget")
Check(UI.IsShown(), "and the settings window is still open")
R.MarkersPage.Capture("targetNext")
cap.scripts.OnKeyDown(cap, "LSHIFT")
Check(cap.shown, "Shift alone isn't a key")
shiftDown = true
S.popup = nil
cap.scripts.OnKeyDown(cap, "F")
shiftDown = false
Check(not cap.shown and S.popup and S.popup.key == "TWICHUI_MARKERS_KEY" and S.popup.text:find("Move Forward"), "a key that does something else is asked about first, naming it")
Check(binds["SHIFT-F"] == "MOVEFORWARD", "nothing is bound until it is accepted")
c.StaticPopupDialogs.TWICHUI_MARKERS_KEY.OnAccept()
Check(binds["SHIFT-F"] == "CLICK " .. T .. ":LeftButton" and MK.KeyText("targetNext") == "Shift-F", "accepted: the key is ours")
R.MarkersPage.Capture("targetNext")
cap.scripts.OnMouseDown(cap, "LeftButton")
Check(cap.shown, "a left click isn't taken as a key")
cap.scripts.OnMouseDown(cap, "Button4")
Check(binds.BUTTON4 == "CLICK " .. T .. ":LeftButton" and binds["SHIFT-F"] == nil, "mouse button 4, free: bound at once, in place of the first key")
R.MarkersPage.Capture("targetNext")
cap.remove:Fire("OnClick")
Check(MK.KeyText("targetNext") == nil and not cap.shown, "Remove key")

-- nothing in the editor ever marked or cleared anything
Check(#game.calls == 0, "the editor, its preview, drags and buttons never mark, place or clear in the game")

-- the world tab
M.ResetOrder("world")
UI.Open("markersWorld")
local wed = R.MarkersPage.Frame("world")
Check(wed.built and wed.tiles[3].name.text == "Square" and wed.tiles[3].icon.texture:find("_6$"), "the world tab has its own markers (world marker 1 is the Square)")
M.Move("world", 1, 2)
Check(table.concat(M.Order("target"), ",") == "8,7,6,5,4,3,2,1", "and its own order")
UI.Close()
Check(not wed:IsVisible(), "closed with the window")
wed.preview.text = "untouched"
M.Move("world", 2, 1)
Check(wed.preview.text == "untouched", "a closed window isn't redrawn")

print(("MARKER CYCLING TESTS PASSED (%d checks)"):format(checks))
