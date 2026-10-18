dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- The marker bar (markers/Bar.lua, TwichUI_Settings/pages/MarkerBar.lua), with stand-in frames:
--   * nothing is built while it is off; turning it on builds two secure bars out of combat, and off drives both hidden;
--   * the conditions the bars are shown by for every "Place the bar" and "In combat" choice, run through a stand-in for the
--     game's macro conditions (combat, a modifier held, a target): the near bar only out of combat, the fixed one where
--     chosen, and in combat only the fixed one can ever be shown;
--   * each icon is a secure button whose attributes, run through the game's raidtarget action, mark the target with that
--     marker, never take one off, and clear on a right-click or the Remove button;
--   * which markers are on the bar, in the cycle's order; size, spacing and scale lay the bar out;
--   * a change in combat is saved and waits (the bars keep what they had), only the latest is given afterwards;
--   * following the nameplate: the bar is placed from the plate's screen position (scale, side, offsets, kept on screen),
--     never anchored to it, only while shown and out of combat; a missing, forbidden, restricted or secret plate uses the
--     fixed place;
--   * events and the per-frame follow run only while a bar is shown;
--   * the preview is an ordinary copy: dragging it moves the fixed place, it closes in combat, and it marks nothing;
--   * the settings page, profiles and configuration sharing.
-- The game's own button code is stood in for from SecureTemplates.lua. Whether a real click marks, and how the bar sits
-- on a real nameplate, is what docs/marker-cycling.md lists for the game.

local checks = 0
local function Check(cond, msg)
  checks = checks + 1
  if not cond then error("FAILED: " .. msg, 2) end
end

---------------------------------------------------------------------------
-- Stand-in frames
---------------------------------------------------------------------------
local function Fake(kind, parent)
  local f = { kind = kind, parent = parent, scripts = {}, hooks = {}, points = {}, shown = false, w = 0, h = 0,
    text = "", enabled = true, focus = false, scroll = 0, attrs = {}, scale = 1, children = {} }
  if parent and parent.children then table.insert(parent.children, f) end
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
    IsEnabled = function(s) return s.enabled end,
    SetMinMaxValues = function() end, SetValue = function() end, GetValue = function() return 0 end,
    GetThumbTexture = function(s) s.thumb = s.thumb or Fake("Texture", s); return s.thumb end,
    SetFocus = function(s) s.focus = true end, ClearFocus = function(s) s.focus = false end, HasFocus = function(s) return s.focus end,
    SetScrollChild = function(s, child) s.child = child end,
    SetVerticalScroll = function(s, v) s.scroll = v end, GetVerticalScroll = function(s) return s.scroll end,
    GetVerticalScrollRange = function() return 0 end,
    IsMouseOver = function() return false end,
    SetScale = function(s, v) s.scale = v end,
    GetScale = function(s) return s.scale end,
    GetEffectiveScale = function(s) return s.scale * (s.parent and s.parent.GetEffectiveScale and s.parent:GetEffectiveScale() or 1) end,
    GetFrameLevel = function() return 1 end,
    IsOwned = function() return false end, GetOwner = function(s) return s.owner end, SetOwner = function(s, o) s.owner = o end,
    GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end, SetFont = function() return true end,
    SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha or 1 end,
    CreateTexture = function(s) local t = Fake("Texture", s); t.shown = true; return t end,
    CreateFontString = function(s) return Fake("FontString", s) end,
    SetTexture = function(s, p) s.texture = p end, SetDesaturated = function(s, v) s.desaturated = v end,
    SetParent = function(s, p) s.parent = p end, GetParent = function(s) return s.parent end,
    SetAttribute = function(s, k, v) s.attrs[k] = v end, GetAttribute = function(s, k) return s.attrs[k] end,
    RegisterForClicks = function(s, ...) s.clicks = { ... } end,
    RegisterForDrag = function(s, b) s.dragButton = b end,
    EnableMouse = function(s, v) s.mouse = v and true or false end,
    SetMovable = function(s, v) s.movable = v end,
    StartMoving = function(s) s.moving = true end,
    StopMovingOrSizing = function(s) s.moving = false end,
    GetCenter = function(s) return s.cx, s.cy end,
    GetTop = function(s) return s.top end, GetBottom = function(s) return s.bottom end,
    SetFrameStrata = function(s, v) s.strata = v end,
    SetBackdrop = function(s, info) s.backdrop = info end,
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
-- The game, as far as the bar reaches it
---------------------------------------------------------------------------
local game = { combat = false, hasTarget = true, mod = "shift", index = nil, plate = nil, marks = {}, calls = {}, drivers = {} }
local SECRET = -777.5
local function Call(...) game.calls[#game.calls + 1] = { ... } end
local function Count(name) local n = 0 for _, c in ipairs(game.calls) do if c[1] == name then n = n + 1 end end return n end

-- A macro condition string "[cond,cond] show; hide" as the game would evaluate it.
local function Eval(str, env)
  for clause in str:gmatch("[^;]+") do
    local conds, result = clause:match("^%s*%[(.-)%]%s*(%a+)%s*$")
    if conds then
      local ok = true
      for cond in conds:gmatch("[^,]+") do
        cond = (cond:gsub("%s", ""))
        if cond == "combat" then ok = ok and env.combat
        elseif cond == "nocombat" then ok = ok and not env.combat
        elseif cond == "@target" then -- (the unit)
        elseif cond == "exists" then ok = ok and env.target
        elseif cond:find("^mod:") then ok = ok and env.mod == cond:sub(5)
        else error("a condition the test doesn't know: " .. cond) end
      end
      if ok then return result end
    else
      return (clause:match("^%s*(%a+)%s*$"))
    end
  end
end

local uiParent
local c, S = SettingsClient({ beforeInit = function(c)
  c.CreateFrame = function(kind, name, parent, template)
    local f = Fake(kind, parent or uiParent)
    f.template = template
    if name then c[name] = f end
    f.shown = true   -- the game makes every frame shown
    return f
  end
  uiParent = Fake("Frame"); uiParent.shown = true
  uiParent.w, uiParent.h, uiParent.cx, uiParent.cy = 1920, 1080, 960, 540
  c.UIParent = uiParent
  c.GameTooltip = Fake("GameTooltip")
  c.UISpecialFrames = {}
  c.InCombatLockdown = function() return game.combat end
  c.GetRaidTargetIndex = function() return game.index end
  c.issecretvalue = function(v) return v == SECRET end
  c.RegisterStateDriver = function(frame, state, cond) game.drivers[frame] = { state = state, cond = cond } end
  c.UnregisterStateDriver = function(frame) game.drivers[frame] = nil end
  c.C_NamePlate = { GetNamePlateForUnit = function() return game.plate end }
  -- anything that would mark or place from the addon's own code is an error: the bar only builds secure buttons
  c.SetRaidTarget = function() error("the bar must never call SetRaidTarget itself") end
  c.PlaceRaidMarker = function() error("never") end
  c.ClearRaidMarker = function() error("never") end
  c.RAID_TARGET_8 = "Skull"
end })
local R, K = c.TwichUI, S.K
local M, B = R.Markers, R.MarkerBar

local function Plate(cx, top, bottom, scale)
  local p = Fake("Frame"); p.shown = true
  p.cx, p.cy, p.top, p.bottom, p.scale = cx, (top + bottom) / 2, top, bottom, scale or 1
  return p
end

-- The game's secure raidtarget action for a click on one of the bar's buttons (SecureTemplates.lua). The edge matters:
-- SecureActionButton_OnClick treats a mouse click on an addon's button as a key press, so with "cast on key down" on
-- (ActionButtonUseKeyDown, on by default) it acts on the press edge only, unless the button says useOnKeyDown = false.
game.keyDownCVar = true
local function Attr(b, name, suffix) local v = b.attrs["*" .. name .. suffix]; if v == nil then v = b.attrs[name] end return v end
local function Perform(b, suffix)
  if Attr(b, "type", suffix) ~= "raidtarget" then return end
  local unit = b.attrs.unit or "target"
  local marker, action = tonumber(Attr(b, "marker", suffix)) or 1, Attr(b, "action", suffix) or "toggle"
  if action == "set" and game.marks[unit] ~= marker then Call("SetRaidTarget", unit, marker); game.marks[unit] = marker
  elseif action == "clear" then Call("SetRaidTarget", unit, 0); game.marks[unit] = nil end
end
local function Click(b, mouse)
  local suffix = mouse == "right" and "2" or "1"
  -- the edges the button is registered for reach it: a press, a release, or both
  local registered = {}
  for _, r in ipairs(b.clicks or {}) do registered[r] = true end
  for _, down in ipairs({ true, false }) do
    if (down and (registered.AnyDown or registered.LeftButtonDown)) or (not down and (registered.AnyUp or registered.LeftButtonUp)) then
      local useOnKeyDown = b.attrs.useOnKeyDown
      if useOnKeyDown == nil then useOnKeyDown = game.keyDownCVar end
      if (down and useOnKeyDown) or (not down and not useOnKeyDown) then Perform(b, suffix) end
    end
  end
end

local function Bars() local all = B.Bars() return all.near, all.fixed end
local function Drive(env)
  -- what the state driver does: shows or hides each bar by its condition
  for _, key in ipairs({ "near", "fixed" }) do
    local bar = (B.Bars())[key]
    local d = bar and game.drivers[bar.root]
    local want = d and Eval(d.cond, env) or "hide"
    bar.root:SetShown(want == "show")
  end
end

---------------------------------------------------------------------------
-- 1. Off: nothing built; on: two secure bars; off again: both hidden
---------------------------------------------------------------------------
Check(not B.Built() and c.TwichUIMarkerBarNear == nil and next(game.drivers) == nil, "off: no frame is made and no driver is registered")
R:SetEnabled("markersBar", true)
Check(B.Built() and c.TwichUIMarkerBarNear and c.TwichUIMarkerBarFixed, "on: both bars are made, out of combat")
local nearBar, fixedBar = Bars()
for _, bar in ipairs({ nearBar, fixedBar }) do
  Check(bar.root.template:find("SecureHandlerStateTemplate") and bar.root.strata == "HIGH" and bar.root.mouse, bar.name .. " is a protected frame that takes the mouse")
  for id = 0, 8 do
    Check(bar.buttons[id].template == "SecureActionButtonTemplate", bar.name .. " button " .. id .. " is the game's secure button")
    Check(bar.buttons[id].clicks[1] == "AnyUp", "a mouse click acts as the button comes up")
  end
end
Check(game.drivers[nearBar.root] and game.drivers[fixedBar.root], "both are driven by a visibility condition")
R:SetEnabled("markersBar", false)
Check(next(game.drivers) == nil and not nearBar.root:IsShown() and not fixedBar.root:IsShown(), "off: no driver, both hidden")
R:SetEnabled("markersBar", true)

---------------------------------------------------------------------------
-- 2. The conditions: where, in combat, modifier, target
---------------------------------------------------------------------------
local function Shown(env)
  Drive(env)
  return nearBar.root:IsShown(), fixedBar.root:IsShown()
end
local function Case(where, combat, mod, expect)
  B.Set("where", where); B.Set("combat", combat); B.Set("modifier", mod)
  local lines = {}
  for _, st in ipairs({ { false, false }, { true, false }, { false, true }, { true, true } }) do
    game.hasTarget = st[1]
    local n, f = Shown({ combat = st[2], target = st[1], mod = mod })
    local key = (st[2] and "combat" or "calm") .. (st[1] and "+target" or "+none")
    lines[key] = (n and "N" or "-") .. (f and "F" or "-")
  end
  game.hasTarget = true
  for key, want in pairs(expect) do
    Check(lines[key] == want, ("%s/%s/%s %s: wanted %s, got %s"):format(where, combat, mod, key, want, lines[key]))
  end
  -- holding another modifier shows nothing
  local other = mod == "shift" and "ctrl" or "shift"
  local n, f = Shown({ combat = false, target = true, mod = other })
  Check(not n and not f, "another modifier shows nothing")
  local n2, f2 = Shown({ combat = false, target = true, mod = nil })
  Check(not n2 and not f2, "no modifier held shows nothing")
end
Case("nameplate", "show", "shift", { ["calm+target"] = "N-", ["combat+target"] = "-F", ["calm+none"] = "--", ["combat+none"] = "--" })
Case("nameplate", "hide", "ctrl", { ["calm+target"] = "N-", ["combat+target"] = "--" })
Case("fixed", "show", "alt", { ["calm+target"] = "-F", ["combat+target"] = "-F", ["calm+none"] = "--" })
Case("fixed", "hide", "shift", { ["calm+target"] = "-F", ["combat+target"] = "--" })
for _, where in ipairs({ "nameplate", "fixed" }) do
  for _, combat in ipairs({ "show", "hide" }) do
    B.Set("where", where); B.Set("combat", combat)
    local near = B.Conditions()
    Check(near == "hide" or near:find("^%[nocombat,"), "the near bar can only ever show out of combat (" .. where .. "/" .. combat .. ")")
  end
end
Check(not B.Set("modifier", "meta") and not B.Set("where", "somewhere") and not B.Set("scale", 5) and not B.Set("scale", 120.5) and not B.Set("show9", true),
  "only known choices and whole numbers in range are accepted")
B.Set("where", "nameplate"); B.Set("combat", "show"); B.Set("modifier", "shift")

---------------------------------------------------------------------------
-- 3. The icons: secure buttons that mark the target, never take a marker off
---------------------------------------------------------------------------
for id = 0, 8 do
  for _, bar in ipairs({ nearBar, fixedBar }) do
    local b = bar.buttons[id]
    Check(b.attrs.unit == "target", "the bar acts on your target")
    Check(b.attrs["*type1"] == "raidtarget" and b.attrs["*type2"] == "raidtarget" and b.attrs["*action2"] == "clear", "left click uses the game's raidtarget action; right-click clears")
    if id == 0 then Check(b.attrs["*action1"] == "clear" and b.attrs["*marker1"] == nil, "the Remove button clears")
    else Check(b.attrs["*action1"] == "set" and b.attrs["*marker1"] == id, "marker " .. id .. " sets itself (never toggle)") end
  end
end
for id = 0, 8 do
  Check(nearBar.buttons[id].attrs.useOnKeyDown == false and fixedBar.buttons[id].attrs.useOnKeyDown == false,
    "button " .. id .. " acts as the mouse button comes up, whatever the game's cast-on-key-down setting")
end
do   -- the model has teeth: a button registered for the release without that attribute does nothing while the setting is on
  local bare = { clicks = { "AnyUp" }, attrs = { unit = "target", ["*type1"] = "raidtarget", ["*action1"] = "set", ["*marker1"] = 8 } }
  game.calls, game.marks, game.keyDownCVar = {}, {}, true
  Click(bare, "left")
  Check(#game.calls == 0, "(control) without useOnKeyDown = false, a release-only button does nothing with cast on key down on")
end
for _, cvar in ipairs({ true, false }) do
  game.keyDownCVar = cvar
  game.calls, game.marks = {}, {}
  Click(nearBar.buttons[8], "left")
  Check(Count("SetRaidTarget") == 1 and game.marks.target == 8, "a click marks the target, with cast on key down " .. (cvar and "on" or "off"))
  Click(nearBar.buttons[6], "right")
  Check(game.marks.target == nil, "and a right-click removes it, with cast on key down " .. (cvar and "on" or "off"))
end
game.keyDownCVar = true
game.calls, game.marks = {}, {}
Click(nearBar.buttons[8], "left")
Check(Count("SetRaidTarget") == 1 and game.calls[1][3] == 8 and game.marks.target == 8, "a click on Skull marks the target with Skull")
Click(nearBar.buttons[8], "left")
Check(Count("SetRaidTarget") == 1, "clicking the marker it already wears changes nothing (it isn't taken off)")
Click(nearBar.buttons[6], "left")
Check(game.marks.target == 6, "another marker replaces it")
Click(nearBar.buttons[6], "right")
Check(game.marks.target == nil and game.calls[#game.calls][3] == 0, "right-click removes the target's marker")
Click(nearBar.buttons[3], "left"); Click(nearBar.buttons[0], "left")
Check(game.marks.target == nil, "the Remove button removes it")
Check(Count("SetRaidTarget") == 5, "each click made exactly one request: " .. Count("SetRaidTarget"))
Check(next(nearBar.buttons[1].attrs, nil) ~= nil and nearBar.buttons[1].attrs.type == nil, "no plain 'type': only a click on the bar does anything")

---------------------------------------------------------------------------
-- 4. What is on the bar, and how it is laid out
---------------------------------------------------------------------------
local function Ids() return table.concat(B.Items(), ",") end
Check(Ids() == "8,7,6,5,4,3,2,1,0", "all eight in the cycle's order, then Remove")
M.Move("target", 1, 4)
Check(Ids() == "7,6,5,8,4,3,2,1,0", "the cycle's order is the bar's")
Check(M.SetOn("target", 7, false) and Ids() == "7,6,5,8,4,3,2,1,0", "a marker skipped in the cycle is still on the bar")
M.SetOn("target", 7, true); M.ResetOrder("target")
B.Set("show6", false); B.Set("show3", false); B.Set("remove", false)
Check(Ids() == "8,7,5,4,2,1", "unticked markers and Remove are left off")
local function Hidden(bar) local t = {} for id = 0, 8 do if not bar.buttons[id].shown then t[#t + 1] = id end end return table.concat(t, ",") end
Check(Hidden(nearBar) == "0,3,6" and Hidden(fixedBar) == "0,3,6", "the buttons not offered are hidden")
Check(nearBar.buttons[8].points[1][4] < nearBar.buttons[7].points[1][4], "Skull is first, to the left")
B.Set("iconSize", 40); B.Set("spacing", 10); B.Set("scale", 150)
local pad = (nearBar.buttons[8].points[1][4])
Check(nearBar.buttons[8].w == 40 and nearBar.root.w == pad * 2 + 6 * 40 + 5 * 10 and nearBar.root.h == pad * 2 + 40, "size and spacing lay the bar out")
Check(nearBar.root.scale == 1.5 and fixedBar.root.scale == 1.5, "the scale applies to the whole bar")
B.ResetSettings()
Check(B.Get("iconSize") == 28 and Ids() == "8,7,6,5,4,3,2,1,0" and B.Get("modifier") == "shift", "resetting puts every bar setting back")
Check(nearBar.buttons[8].icon.texture:find("UI%-RaidTargetingIcon_8") and nearBar.buttons[0].icon.texture:find("Pass"), "icons: the game's marker icons, and its red cross for Remove")

---------------------------------------------------------------------------
-- 5. Combat: changes wait; the latest is given afterwards
---------------------------------------------------------------------------
local condBefore = game.drivers[nearBar.root].cond
local sizeBefore = nearBar.buttons[8].w
game.combat = true
B.Set("iconSize", 36)
B.Set("modifier", "ctrl")
B.Set("show8", false)
Check(B.Get("iconSize") == 36 and B.Get("modifier") == "ctrl", "a change in combat is saved at once")
Check(B.Pending(), "... and waits")
Check(nearBar.buttons[8].w == sizeBefore and game.drivers[nearBar.root].cond == condBefore and nearBar.buttons[8].shown, "... the bars keep what they had")
B.Set("iconSize", 20)
B.Set("modifier", "alt")
game.combat = false
c.FireEvent("PLAYER_REGEN_ENABLED")
Check(not B.Pending() and nearBar.buttons[7].w == 20 and not nearBar.buttons[8].shown, "combat over: the latest settings are given")
Check(game.drivers[nearBar.root].cond:find("mod:alt") and not game.drivers[nearBar.root].cond:find("ctrl"), "... including the key to hold")
B.ResetSettings()
-- turning it off in combat waits too
game.combat = true
R:SetEnabled("markersBar", false)
Check(B.Pending() and game.drivers[nearBar.root] ~= nil, "switched off in combat: the bars are driven hidden after combat")
game.combat = false
c.FireEvent("PLAYER_REGEN_ENABLED")
Check(not B.Pending() and next(game.drivers) == nil, "... and then they are")
R:SetEnabled("markersBar", true)

---------------------------------------------------------------------------
-- 6. Sitting on the nameplate (the near bar)
---------------------------------------------------------------------------
-- A nameplate's position is not read: the bar is anchored to the plate, which the game moves. Only while the near bar
-- is shown (out of combat), re-anchored when the target or its plate changes, and let go of as it hides.
local function Point(root) return root.points[1] end
local fx, fy = B.Position()
local plateA, plateB = Fake("Frame"), Fake("Frame")
game.plate = plateA
nearBar.root:Show()
local p = Point(nearBar.root)
Check(p[1] == "BOTTOM" and p[2] == plateA and p[3] == "TOP" and p[4] == 0 and p[5] == B.Get("offsetY"),
  "shown: anchored to the top of the target's nameplate, offsets from the settings")
Check(#nearBar.root.points == 1, "one anchor, and nothing else")
local L1, L2 = B.LastPlacement()
Check(L1 == "nameplate" and L2 == nil, "remembered: on the nameplate")
Check(c.TwichUI.frame.events.PLAYER_TARGET_CHANGED and c.TwichUI.frame.events.NAME_PLATE_UNIT_ADDED and c.TwichUI.frame.events.NAME_PLATE_UNIT_REMOVED,
  "while shown it listens for target, nameplate and marker changes")
-- nothing per frame
for _, fr in pairs(c) do
  if type(fr) == "table" and fr.scripts and fr.scripts.OnUpdate and (fr == nearBar.root or fr == fixedBar.root) then error("the bars have an OnUpdate") end
end
-- same plate again: not re-anchored
local pointsBefore = nearBar.root.points
c.FireEvent("PLAYER_TARGET_CHANGED")
c.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate3")
Check(nearBar.root.points == pointsBefore, "the same plate and settings are not anchored again")
-- another target, another plate
game.plate = plateB
c.FireEvent("PLAYER_TARGET_CHANGED")
p = Point(nearBar.root)
Check(p[2] == plateB and #nearBar.root.points == 1, "a new target: the bar moves to its plate")
-- side, offsets, scale
B.Set("side", "below"); B.Set("offsetX", 30); B.Set("offsetY", 10)
p = Point(nearBar.root)
Check(p[1] == "TOP" and p[2] == plateB and p[3] == "BOTTOM" and p[4] == 30 and p[5] == -10, "below the plate, shifted sideways")
B.Set("side", "above"); B.Set("offsetX", 0); B.Set("offsetY", 24)
B.Set("scale", 200)
p = Point(nearBar.root)
Check(p[4] == 0 and p[5] == 12, "the bar's own scale divides the offsets (they are in its units): " .. tostring(p[5]))
B.Set("scale", 100)
Check(Point(nearBar.root)[5] == 24, "and back")
-- the plate goes away
game.plate = nil
c.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate3")
p = Point(nearBar.root)
Check(p[1] == "CENTER" and p[2] == uiParent and p[4] == fx and p[5] == fy, "no nameplate: the fixed place")
local w1, why1 = B.LastPlacement()
Check(w1 == "fixed" and why1 == "none" and B.WHY.none, "... and the reason is remembered: " .. tostring(why1))
game.plate = plateA
c.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
Check(Point(nearBar.root)[2] == plateA and B.LastPlacement() == "nameplate", "the plate comes back: the bar goes to it")
-- a plate that can't be used, or a lookup that fails, or an anchor the game refuses: the fixed place, with the reason
local forbidden = Fake("Frame"); forbidden.IsForbidden = function() return true end
for name, setup in pairs({
  forbidden = function() game.plate = forbidden end,
  lookup = function() game.plate = "boom" end,
}) do
  setup()
  local realGet = c.C_NamePlate.GetNamePlateForUnit
  if name == "lookup" then c.C_NamePlate.GetNamePlateForUnit = function() error("bad unit") end end
  c.FireEvent("PLAYER_TARGET_CHANGED")
  c.C_NamePlate.GetNamePlateForUnit = realGet
  local where, why = B.LastPlacement()
  Check(where == "fixed" and why == name and Point(nearBar.root)[2] == uiParent, name .. ": at the fixed place, and says why")
end
game.plate = plateA
c.FireEvent("PLAYER_TARGET_CHANGED")
nearBar.root.SetPoint = function(self, point, rel, ...)
  if rel == plateB then error("blocked") end
  table.insert(self.points, { point, rel, ... })
end
game.plate = plateB
c.FireEvent("PLAYER_TARGET_CHANGED")
local rw, rwhy = B.LastPlacement()
Check(rw == "fixed" and rwhy == "refused" and Point(nearBar.root)[2] == uiParent, "an anchor the game refuses: the fixed place, and says so")
nearBar.root.SetPoint = nil
game.plate = plateA
c.FireEvent("PLAYER_TARGET_CHANGED")
-- in combat nothing is re-anchored
local before = Point(nearBar.root)
game.combat = true
game.plate = plateB
c.FireEvent("PLAYER_TARGET_CHANGED")
Check(Point(nearBar.root) == before, "nothing is moved in combat")
game.combat = false
game.plate = plateA
-- hiding lets go of the plate
nearBar.root:Hide()
p = Point(nearBar.root)
Check(p[1] == "CENTER" and p[2] == uiParent, "hidden: no longer attached to the nameplate")
Check(c.TwichUI.frame.events.NAME_PLATE_UNIT_ADDED == nil and c.TwichUI.frame.events.PLAYER_TARGET_CHANGED == nil, "hidden: it listens for nothing")
-- the fixed bar says why it is there
B.Set("where", "nameplate")
fixedBar.root:Show()
local fw, fwhy = B.LastPlacement()
Check(fw == "fixed" and fwhy == "combat", "the fixed bar shown while placement is the nameplate: because of combat")
fixedBar.root:Hide()
B.Set("where", "fixed")
fixedBar.root:Show()
fw, fwhy = B.LastPlacement()
Check(fw == "fixed" and fwhy == "chosen", "... or because it was chosen")
fixedBar.root:Hide()
B.Set("where", "nameplate")
-- the highlight
nearBar.root:Show()
game.index = 6
c.FireEvent("RAID_TARGET_UPDATE")
local function Ring(bar, id) for _, line in pairs(bar.buttons[id].ring) do return line.shown end end
Check(Ring(nearBar, 6) and not Ring(nearBar, 8), "the marker your target wears has a ring")
game.index = SECRET
c.FireEvent("RAID_TARGET_UPDATE")
Check(not Ring(nearBar, 6), "a secret answer rings nothing (and errors nothing)")
game.index = nil
nearBar.root:Hide()

---------------------------------------------------------------------------
-- 7. The fixed place and the preview
---------------------------------------------------------------------------
fixedBar.root:Show()
local f1 = Point(fixedBar.root)
Check(f1[1] == "CENTER" and f1[4] == 0 and f1[5] == 160, "the fixed bar is at the default place, from the middle of the screen")
Check(B.SetPosition(-300, 120) and Point(fixedBar.root)[4] == -300 and Point(fixedBar.root)[5] == 120, "moving the fixed place moves the fixed bar")
B.Set("scale", 200)
Check(Point(fixedBar.root)[4] == -150 and Point(fixedBar.root)[5] == 60, "at 200%, the place is in the same screen spot")
B.Set("scale", 100)
Check(not B.SetPosition("x", 1) and not B.SetPosition(99999, 0) and not B.SetPosition(0 / 0, 0), "a place off the screen or not a number is refused")
fixedBar.root:Hide()

game.calls = {}
Check(not B.Previewing() and c.TwichUIMarkerBarPreview == nil, "no preview until asked for")
Check(B.ShowPreview(true) and B.Previewing(), "the preview shows")
local _, preBar = B.Bars()
local pre = c.TwichUIMarkerBarPreview
Check(pre.template == "BackdropTemplate" and pre.movable, "it is an ordinary frame, movable")
for id = 0, 8 do Check(preBar.buttons[id].mouse == false and preBar.buttons[id].template == nil and preBar.buttons[id].attrs["*type1"] == nil, "preview button " .. id .. " can't be clicked and does nothing") end
Check(Point(pre)[1] == "CENTER" and Point(pre)[4] == -300, "at the fixed place")
-- drag it
pre.scripts.OnDragStart(pre)
Check(pre.moving, "dragging moves it")
pre.cx, pre.cy = 960 + 200, 540 - 100
pre.scripts.OnDragStop(pre)
Check(not pre.moving, "and letting go stops")
local x, y = B.Position()
Check(x == 200 and y == -100, "the fixed place is where it was dropped: " .. x .. "," .. y)
Check(Point(fixedBar.root)[4] == 200 and Point(fixedBar.root)[5] == -100, "and the fixed bar follows")
-- the look and settings reach it
B.Set("iconSize", 50)
Check(preBar.buttons[8].w == 50, "the preview follows the settings")
B.ResetSettings()
-- combat closes it
game.combat = true
c.FireEvent("PLAYER_REGEN_DISABLED")
Check(not B.Previewing(), "combat closes the preview")
Check(select(2, B.ShowPreview(true)) == "combat" and not B.Previewing(), "and it can't be opened in combat")
game.combat = false
Check(B.ResetPosition() and select(1, B.Position()) == 0 and select(2, B.Position()) == 160, "the fixed place can be put back")
Check(#game.calls == 0 and Count("SetRaidTarget") == 0, "showing, moving and closing the preview marked nothing")

---------------------------------------------------------------------------
-- 7b. An EllesmereUI border (Pixels Textured): padding clears the line, not the whole cell; scale is set before it is drawn
---------------------------------------------------------------------------
-- A stand-in for the EllesmereUI calls MenuStyle and Borders make. Its textured edge is drawn in a cell `edgePx` thick
-- centred on the frame's edge, and the line starts 0.321 of the way in (EllesmereUI_PixelPerfect.lua, _borderInk), so it
-- reaches 0.5 - 0.321 = 0.179 of the cell past the edge (BorderReach).
local euiDraws = {}
local eui
eui = {
  PP = { mult = 1 },
  ApplyBorderStyle = function(frame, _, _, _, _, _, key, _, _, _, _, _, _, normalize, edgePx)
    euiDraws[#euiDraws + 1] = { key = key, scale = frame:GetEffectiveScale(), normalize = normalize, edgePx = edgePx }
  end,
  GetBorderTextureList = function() return {} end,
  ResolveBorderTexture = function(key) return key == "pixels-textured" end,
  BorderPxStep = function() return 2 end,
  BorderLegacyPx = function() return 12 end,
  BorderReach = function(_, _, _, _, _, _, _, _, edgePx) return 0.179 * edgePx end,
}
-- At startup TwichUI loads (and draws the bar) before EllesmereUI exists, so a saved EllesmereUI border can't be resolved: the
-- look falls back to a plain line, at the saved (textured) thickness. That was a thick white border after every reload.
B.Style.Set("borderTexture", "eui:pixels-textured")
Check(#euiDraws == 0 and nearBar.root.backdrop and nearBar.root.backdrop.edgeFile, "(no EllesmereUI yet) the plain line is what is drawn")
c.EllesmereUI = eui   -- now every addon has loaded
c.FireEvent("PLAYER_LOGIN")
Check(#euiDraws > 0 and euiDraws[#euiDraws].key == "pixels-textured", "at login the bar is drawn again, now with EllesmereUI's border")
Check(B.Style.Get("borderSize") == 12, "choosing Pixels Textured seeds a thickness that suits it: " .. B.Style.Get("borderSize"))
local lastDraw = euiDraws[#euiDraws]
Check(lastDraw and lastDraw.key == "pixels-textured" and lastDraw.normalize and lastDraw.edgePx == 12, "drawn by EllesmereUI at the exact size, normalized to the bar's scale")
local function Pad() return nearBar.buttons[8].points[1][4] end
local cell = B.Style.Get("borderSize")
Check(Pad() <= 7 and Pad() < cell, "12 pixel cell: the padding clears the line (about 3 px), not the whole cell: " .. Pad())
for _, size in ipairs({ 6, 16 }) do
  B.Style.Set("borderSize", size)
  Check(Pad() <= 7, ("a %d pixel cell: the padding stays about the same (%s), it doesn't follow the cell"):format(size, tostring(Pad())))
end
B.Style.Set("borderSize", 12)
-- the plain line still clears its whole thickness
B.Style.Set("borderTexture", "solid"); B.Style.Set("borderSize", 4)
Check(Pad() == 7, "a plain 4 px line: its whole thickness plus the gap: " .. Pad())
B.Style.Set("borderTexture", "eui:pixels-textured"); B.Style.Set("borderSize", 12)
-- scale before drawing: the border is drawn at the scale the bar will have
euiDraws = {}
B.Set("scale", 200)
local sawBoth = {}
for _, d in ipairs(euiDraws) do sawBoth[d.scale] = true end
Check(sawBoth[2] and not sawBoth[1], "the scale is set before the border is drawn (it was drawn at " .. (sawBoth[1] and "the old scale" or "the new one") .. ")")
B.Set("scale", 100)
B.Style.Reset()
c.EllesmereUI = nil

---------------------------------------------------------------------------
-- 8. The settings page
---------------------------------------------------------------------------
local chunk = assert(loadfile(ROOT .. "../TwichUI_Settings/Window.lua")); setfenv(chunk, c); chunk("TwichUI_Settings", {})
local UI = R.SettingsUI
UI.Open("markersBar")
local P = R.MarkerBarPage
local page = K.pages.markersBar
Check(page and page.parent == "markers", "Marker bar is a tab of Markers")
local function Row(name) for _, r in ipairs(page.rows) do if r.data.name == name or (r.data.setting and r.data.setting.name == name) then return r end end error("no row " .. name) end
local frame = P.Frame()
Check(frame:IsVisible(), "the markers frame is shown with the page")
local tiles = {}
for _, ch in ipairs(frame.children) do if ch.kind == "Button" and ch.scripts.OnClick then tiles[#tiles + 1] = ch end end
Check(#tiles == 8, "eight tiles, one per marker")
Check(B.Get("show1") == true and Ids() == "8,7,6,5,4,3,2,1,0", "the Star starts on the bar")
tiles[1].scripts.OnClick(tiles[1])
Check(B.Get("show1") == false and Ids() == "8,7,6,5,4,3,2,0", "clicking a tile takes that marker off the bar, and the bar follows: " .. Ids())
tiles[1].scripts.OnClick(tiles[1])
Check(B.Get("show1") == true, "clicking again puts it back")
-- rows
Check(Row("Place the bar"):Enabled() and Row("Side of the nameplate"):Enabled(), "nameplate placement: its offsets are available")
B.Set("where", "fixed")
Check(not Row("Side of the nameplate"):Enabled() and not Row("Distance from the nameplate"):Enabled(), "fixed placement: the nameplate settings are greyed out, with their reason")
Check(Row("Distance from the nameplate"):DisabledReason():find("nameplate"), "... and say so")
local labels = {}
for _, ch in ipairs(Row("In combat").choices()) do labels[#labels + 1] = ch.label end
Check(table.concat(labels, "|") == "Show it|Hide it in combat", "in combat: the choices fit fixed placement")
B.Set("where", "nameplate")
labels = {}
for _, ch in ipairs(Row("In combat").choices()) do labels[#labels + 1] = ch.label end
Check(table.concat(labels, "|") == "Show it at the fixed place|Hide it", "... and nameplate placement")
R:SetEnabled("markersBar", false)
Check(not Row("Place the bar"):Enabled() and Row("Place the bar"):DisabledReason(), "switched off: the rest is greyed out, with a reason")
R:SetEnabled("markersBar", true)
local move = Row("Fixed place")
Check(move.data.buttonText() == "Show and move", "the move button")
move.click()
Check(B.Previewing() and move.data.buttonText() == "Done", "Show and move opens the preview")
game.combat = true
Check(not move:Enabled() and move:DisabledReason(), "the button is greyed out in combat")
game.combat = false
move.click()
Check(not B.Previewing(), "Done closes it")
move.click()
frame:Hide()
Check(not B.Previewing(), "leaving the page closes the preview")
S.popup = nil
Row("Put the fixed place back").click()
Check(S.popup and S.popup.key == "TWICHUI_MARKERBAR_PLACE", "putting the place back asks first")
UI.Close()

---------------------------------------------------------------------------
-- 9. Profiles and configuration sharing
---------------------------------------------------------------------------
local PF = R.Profiles
B.Set("modifier", "alt"); B.Set("show5", false); B.SetPosition(40, 50)
Check(PF.Create("Tank"), "a new profile")
Check(B.Get("modifier") == "shift" and B.Get("show5") and not R:Enabled("markersBar"), "its own bar settings: the defaults, off")
Check(next(game.drivers) == nil and not nearBar.root:IsShown(), "the bars follow: hidden and undriven")
Check(select(1, B.Position()) == 0, "and its own fixed place")
Check(PF.Switch("Default"), "back")
Check(B.Get("modifier") == "alt" and not B.Get("show5") and R:Enabled("markersBar") and game.drivers[nearBar.root].cond:find("mod:alt"), "the first profile's bar is as it was, and driven")
Check(select(1, B.Position()) == 40, "with its fixed place")

local TC = R.TwichConfig
local g = TC.Group("markerBar")
Check(g and g.complete and TC.Usable(g), "the bar is part of configuration sharing")
local entry = TC.Build({ all = true })
local shared = entry.groups.markerBar
Check(shared and shared.modules.markersBar == true and shared.markerBar.modifier == "alt" and shared.markerBar.show5 == false, "its settings are shared")
Check(shared.markerBarStyle and shared.markerBarStyle.bgColor == "ff1f1812", "and its look")
do
  local function Walk(t, out) for k, v in pairs(t) do out[#out + 1] = tostring(k); if type(v) == "table" then Walk(v, out) else out[#out + 1] = tostring(v) end end return out end
  local all = table.concat(Walk(shared, {}), " ")
  Check(not all:find("Position") and not all:find("pos"), "the fixed place stays on this computer")
end
local theirs = TC.Build({ all = true })
theirs.groups.markerBar.markerBar.modifier = "ctrl"
theirs.groups.markerBar.markerBar.combat = "hide"
local ok = TC.Apply(theirs, { from = "Pal" })
Check(ok and B.Get("modifier") == "ctrl" and B.Get("combat") == "hide", "an import applies")
Check(game.drivers[nearBar.root].cond:find("mod:ctrl"), "the bars follow the import")
Check(select(1, B.Position()) == 40, "an import never moves the fixed place")
local bad = TC.Build({ all = true })
bad.groups.markerBar.markerBar.modifier = "meta"
local clean = TC.CleanEntry(bad)
Check(clean.rejected and clean.rejected.markerBar, "an unknown key to hold rejects the whole group")
Check(TC.Undo() and B.Get("modifier") == "alt", "undo")

print(("MARKER BAR TESTS PASSED (%d checks)"):format(checks))
