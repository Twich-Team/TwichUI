-- The Test Lab's client UI API probes (milestone 6): TwichUI_TestLab/Probe.lua, cases/Api.lua, the key-binding probe in Guided.lua, the opt-in
-- category flag, the setup line in the report, and the numeric-guard cases.
-- OFFLINE MODEL, and what that means: the stand-in frames below answer the way the TEST says they do (several different ways on purpose: a
-- client that lets a click through a disabled button and one that does not, one that applies hit-rectangle insets to the pointer and one that
-- ignores them, ...). These tests prove that the probes MEASURE and REPORT whatever the frames did, that they never claim an answer the frames
-- did not give (a missing or refused method is reported as missing or refused), and that every temporary frame, script, prompt and binding is
-- released on every path. They do NOT assert how the Forever client behaves: that is what the cases are for, when you run them in the game.
dofile(TESTS .. "mi_mock.lua")
dofile(TESTS .. "client_format.lua")
local World = dofile(TESTS .. "reach_world.lua")

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function DeepSame(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not DeepSame(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
local function DeepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = DeepCopy(x) end
  return out
end

local LAB = ROOT .. "../TwichUI_TestLab/"
local function LabFiles()
  local list = {}
  for line in io.lines(LAB .. "TwichUI_TestLab.toc") do
    line = line:gsub("\r", ""):gsub("%s+$", "")
    if line ~= "" and not line:find("^#") then list[#list + 1] = (line:gsub("\\", "/")) end
  end
  return list
end

---------------------------------------------------------------------------
-- A client with the Lab loaded, a virtual clock, a stand-in frame world for the Lab's own probe frames, and the binding API recorded
---------------------------------------------------------------------------
local function Setup(opts)
  opts = opts or {}
  local now, timers, reads = 0, 0, 0
  local c = MIClient("Zzchar", {
    db = { modules = {} },
    beforeFiles = function(cl)
      cl.CreateFrame = function(kind, name, parent)
        local fr = MIFake(kind, parent)
        for _, m in ipairs({ "SetColorTexture", "SetVertexColor", "SetBackdropColor", "SetBackdropBorderColor", "SetTexCoord", "SetFontObject", "SetMaxLetters",
          "SetAutoFocus", "SetTextInsets", "SetJustifyV", "SetJustifyH", "SetWordWrap", "EnableMouse", "SetToplevel", "SetMovable", "SetClampedToScreen",
          "RegisterForDrag", "SetDontSavePosition", "SetFrameStrata", "SetMotionScriptsWhileDisabled", "UnregisterAllEvents" }) do
          fr[m] = function() end
        end
        fr.UnregisterAllEvents = function(s) s.events = {} end
        fr.SetTexture = function(s, v) s.texture = v end
        fr.IsEventRegistered = function(s, e) return s.events[e] == true end
        fr.CreateTexture = function(s) local t = MIFake("Texture", s); t.SetColorTexture = function() end t.SetVertexColor = function() end t.SetTexCoord = function() end t.SetTexture = function(x, v) x.texture = v end return t end
        fr.CreateFontString = function(s) local t = MIFake("FontString", s); t.SetFont = function() return true end t.SetJustifyV = function() end t.SetWordWrap = function() end t.SetTextColor = function() end t.SetJustifyH = function() end return t end
        if name then cl[name] = fr; fr.frameName = name end
        return fr
      end
      cl.UIParent = MIFake("Frame"); cl.UIParent.w, cl.UIParent.h = 1920, 1080
      cl.GameTooltip = MIFake("GameTooltip")
      cl.UISpecialFrames = {}
      for _, file in ipairs({ "chronicle/Style.lua", "Look.lua", "FrameLook.lua", "CraftLook.lua" }) do
        local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, cl); chunk("!!!TwichUI", {})
      end
    end,
    files = {},
  })
  c.TwichUIDB = c.TwichUIDB or {}
  c.TwichUIDB.probeMarker = { a = 1, b = { 2, 3 } }
  c.GetRealmName = function() return "Zzrealm" end
  c.GetNormalizedRealmName = function() return "Zzrealm" end
  c.UnitName = function() return "Zzchar" end
  c.GetGuildInfo = function() return "Zzguild" end
  c.GetTimePreciseSec = function() reads = reads + 1 return now + reads * 0.00002 end
  c.C_Timer = { After = function() timers = timers + 1 end, NewTicker = function() timers = timers + 1 return { Cancel = function() end } end }
  local t = { c = c, bindings = {}, binds = 0, clears = 0, combat = false, timers = function() return timers end, mock = {} }
  c.InCombatLockdown = function() return t.combat end
  -- the binding API: records who owns what; GetBindingAction(key, true) answers like the game does for an override
  if not opts.noBinding then
    c.SetOverrideBindingClick = function(owner, priority, key, name, button)
      if t.mock.bindRaises then error("binding refused") end
      t.binds = t.binds + 1
      t.last = { owner = owner, priority = priority, key = key, name = name, button = button }
      t.bindings[owner] = t.bindings[owner] or {}
      t.bindings[owner][key] = name .. ":" .. button
    end
    c.ClearOverrideBindings = function(owner) t.clears = t.clears + 1; t.bindings[owner] = nil end
  end
  if not opts.noAction then
    c.GetBindingAction = function(key, override)
      if t.mock.actionRaises then error("no") end
      if override then for _, keys in pairs(t.bindings) do if keys[key] then return "CLICK " .. keys[key] end end end
      return t.mock.baseAction or ""
    end
  end
  function t.Advance(sec) now = now + sec end
  function t.Clock() return c.GetTimePreciseSec() end
  function t.Bound() local n = 0 for _, keys in pairs(t.bindings) do for _ in pairs(keys) do n = n + 1 end end return n end
  local made = {}
  local create = c.CreateFrame
  c.CreateFrame = function(...) local f = create(...); made[#made + 1] = f; return f end
  for _, file in ipairs(LabFiles()) do
    local chunk = assert(loadfile(LAB .. file), file); setfenv(chunk, c); chunk("TwichUI_TestLab", {})
  end
  t.TL, t.R = c.TwichUI.TestLab, c.TwichUI
  local RN = t.TL.Runner
  function t.Frame()
    for _, f in ipairs(made) do if f.events.PLAYER_REGEN_DISABLED and f.scripts.OnUpdate then return f end end
  end
  function t.Frames(n, dt)
    for _ = 1, n do
      if not RN.Active() then return end
      t.Advance(dt or 0.016)
      local fr = t.Frame()
      fr.scripts.OnUpdate(fr, dt or 0.016)
    end
  end
  function t.Run(ids, cats)
    local list = {}
    for _, id in ipairs(ids) do list[#list + 1] = assert(t.TL.cases[id], id) end
    t.done = nil
    Check(RN.Start(list, { cats = cats or { "api" }, clock = t.Clock, onDone = function(s) t.done = s end }), "the run starts")
  end
  function t.Result(i) return t.done.results[i or 1] end
  function t.Facts(i)
    local out = {}
    for _, f in ipairs(t.Result(i).facts) do out[f[1]] = f[2] end
    return out
  end
  function t.Notes(i) return table.concat(t.Result(i).notes or {}, "\n") end
  function t.Key() local b = c[t.TL.Guided.NAME]; b.scripts.OnClick(b) end
  return t
end

---------------------------------------------------------------------------
-- The stand-in frame world for the Lab's probe frames (names "TwichUITestLabProbe..."). opts says how THIS client behaves:
--   noEnableMouseMotion / noMouseClickEnabled / noPropagate / propagateRaises / setterRaises = { SetHitRectInsets = true } / noHitRect
--   click = "always" | "guarded" | "never" | "raises"   what Button:Click() does
--   insetsIgnoredByPointer, insetsRoundTrip = function(v) -> v'   what the hit rectangle and its read-back do
--   tie = "created" | "shown"                              which of two frames of equal strata and level is on top
--   route(stack, default) -> receivers                     which frames get a real click
---------------------------------------------------------------------------
local function ProbeWorld(t, opts)
  opts = opts or {}
  local w = World.New()
  w:Install(t.c)
  w.shownCount = 0
  local UIP = t.c.UIParent
  local orig = t.c.CreateFrame
  local function Center(f)
    if f == UIP or f == nil then return 960, 540 end
    if f._anchor then
      local rx, ry = Center(f._anchor.rel)
      return rx + f._anchor.dx, ry + f._anchor.dy
    end
    return f._x + f._w / 2, f._y + f._h / 2
  end
  t.c.CreateFrame = function(kind, name, parent)
    if not (type(name) == "string" and name:find("^TwichUITestLabProbe")) then return orig(kind, name, parent) end
    local f = w:Frame{ type = kind, name = name, parent = parent, w = 0, h = 0 }
    t.c[name] = f
    function f:ClearAllPoints() self._anchor = nil end
    function f:SetPoint(_, rel, _, dx, dy) self._anchor = { rel = rel or UIP, dx = dx or 0, dy = dy or 0 } end
    function f:SetSize(a, b) self._w, self._h = a, b end
    function f:SetParent(p) self._parent = p end
    function f:IsVisible() local p = self while p do if p._shown == false then return false end p = p._parent end return true end   -- UIParent is a plain stand-in
    function f:GetEffectiveScale() return 1 end
    function f:GetRect() local cx, cy = Center(self) return cx - self._w / 2, cy - self._h / 2, self._w, self._h end
    function f:SetAlpha() end
    function f:SetToplevel() end
    function f:RegisterForClicks() end
    function f:CreateTexture() local x = MIFake("Texture", self) return x end
    function f:CreateFontString() local x = MIFake("FontString", self) x.SetFont = function() return true end return x end
    local show = f.Show
    function f:Show() if not self._shown then w.shownCount = w.shownCount + 1; self._shownAt = w.shownCount end show(self) end
    f._shownAt = 0
    if not opts.noEnableMouseMotion then function f:EnableMouseMotion(v) self._motion = v and true or false end end
    if opts.noMouseClickEnabled then f.SetMouseClickEnabled = nil; f.IsMouseClickEnabled = nil end
    if not opts.noPropagate then
      function f:SetPropagateMouseClicks(v)
        if opts.propagateRaises then error("restricted") end
        self._propagate = v
      end
    end
    if opts.noHitRect then f.SetHitRectInsets = nil; f.GetHitRectInsets = nil end
    if opts.setterRaises then
      for name in pairs(opts.setterRaises) do
        f[name] = function() error("protected function " .. name) end
      end
    end
    if opts.insetsRoundTrip then
      local raw = f.GetHitRectInsets
      function f:GetHitRectInsets() local a, b, c2, d = raw(self) return opts.insetsRoundTrip(a), opts.insetsRoundTrip(b), opts.insetsRoundTrip(c2), opts.insetsRoundTrip(d) end
    end
    if kind == "Button" then
      function f:Click(button, down)
        local mode = opts.click or "always"
        if mode == "raises" then error("Click is restricted here") end
        if mode == "never" then return end
        if mode == "guarded" and not (self:IsVisible() and self._enabled and self._click) then return end
        if self.scripts.PreClick then self.scripts.PreClick(self, button or "LeftButton", down) end
        if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton", down) end
        if self.scripts.PostClick then self.scripts.PostClick(self, button or "LeftButton", down) end
      end
    end
    return f
  end
  if opts.tie == "shown" then   -- equal strata and level: the frame shown last is on top
    local foci = w.Foci
    function w:Foci()
      local out = foci(self)
      table.sort(out, function(a, b)
        local RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
        if RANK[a._strata] ~= RANK[b._strata] then return RANK[a._strata] > RANK[b._strata] end
        if a._level ~= b._level then return a._level > b._level end
        return (a._shownAt or 0) > (b._shownAt or 0)
      end)
      return out
    end
  end
  if opts.tie == "A" then   -- equal strata and level: whichever frame is called A is on top, whatever the creation or show order
    local foci = w.Foci
    function w:Foci()
      local out = foci(self)
      table.sort(out, function(a, b)
        local RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
        if RANK[a._strata] ~= RANK[b._strata] then return RANK[a._strata] > RANK[b._strata] end
        if a._level ~= b._level then return a._level > b._level end
        local aa, bb = (a._name or ""):find("arena%.A") ~= nil, (b._name or ""):find("arena%.A") ~= nil
        if aa ~= bb then return aa end
        return a.order > b.order
      end)
      return out
    end
  end
  if opts.insetsIgnoredByPointer then
    local foci = w.Foci
    function w:Foci()   -- a client whose pointer region is the whole painted rectangle, whatever the insets say
      local saved = {}
      for _, f in ipairs(self.frames) do saved[f] = f._insets; f._insets = { 0, 0, 0, 0 } end
      local out = foci(self)
      for f, v in pairs(saved) do f._insets = v end
      return out
    end
  end
  -- a real click at (x, y): the frames the (stand-in) client gives it to get the press, the release and, for a Button, OnClick
  function w:Press(x, y)
    self:Cursor(x, y)
    local stack = self:Foci()
    local receivers = {}
    for _, f in ipairs(stack) do
      if f._click then
        receivers[#receivers + 1] = f
        if not f._propagate then break end
      end
    end
    if opts.route then receivers = opts.route(stack, receivers) end
    for _, f in ipairs(receivers) do
      if f.scripts.OnMouseDown then f.scripts.OnMouseDown(f, "LeftButton") end
      if f.scripts.OnMouseUp then f.scripts.OnMouseUp(f, "LeftButton") end
      if f._kind == "Button" and f._enabled and f.scripts.OnClick then f.scripts.OnClick(f, "LeftButton", false) end
    end
    return receivers
  end
  function w:Mark()   -- the middle of the highlighted square, in screen units
    local m = t.c["TwichUITestLabProbearena.mark"]
    local l, b, ww, hh = m:GetRect()
    return l + ww / 2, b + hh / 2
  end
  return w
end

-- a fact is cut at 60 characters by the Lab; none of the probes' facts may reach that (a cut value would hide the answer)
local function NoCut(t, what)
  for _, r in ipairs(t.done.results) do
    for _, f in ipairs(r.facts or {}) do
      Check(#f[2] < 60 and #f[1] < 60, (what or "") .. ": fact " .. f[1] .. " is not cut (" .. #f[2] .. " characters)")
    end
  end
end

local function Released(t, what)
  local ps = t.TL.Probe.Snapshot()
  Check(ps.shown == 0 and ps.mouse == 0 and ps.scripted == 0 and not ps.trial, what .. ": the probe frames are released (" .. ps.shown .. " shown, " .. ps.mouse .. " mouse, " .. ps.scripted .. " scripted)")
  local gs = t.TL.Guided.Snapshot()
  Check(not gs.active and gs.bound == nil and not gs.proxyShown and not gs.promptShown, what .. ": nothing of the guided request is left")
  Same(t.Bound(), 0, what .. ": no binding is left")
  local rs = t.TL.Runner.Snapshot()
  Check(not rs.active and not rs.updating and not rs.listening, what .. ": the runner is idle")
end

---------------------------------------------------------------------------
-- 1. Registration, safety classes, opt-in
---------------------------------------------------------------------------
do
  local t = Setup()
  local TL = t.TL
  Same(#TL.rejected, 0, "no case was refused")
  Check(TL.categories.api and TL.categories.api.optin and not TL.categories.api.guided, "api is an opt-in group that is not guided")
  Check(TL.categories.apiguided and TL.categories.apiguided.guided and TL.categories.apiguided.optin, "apiguided is guided, and guided groups are opt-in")
  local owned, guided = TL.Select({ api = true }), TL.Select({ apiguided = true })
  local ids = {}
  for _, c in ipairs(owned) do ids[c.id] = c.class; Same(c.class, "owned", c.id .. " is an owned case"); Check(c.budget <= 10, c.id .. " is short") end
  for _, id in ipairs({ "api.binding.override", "api.mouse.states", "api.click.programmatic", "api.hitrect.insets" }) do Check(ids[id], id .. " is registered") end
  Same(#owned, 4)
  local gids = {}
  for _, c in ipairs(guided) do gids[c.id] = true; Same(c.class, "guided", c.id .. " is a guided case"); Check(c.budget >= 100 and c.budget <= TL.MAX_GUIDED_BUDGET) end
  for _, id in ipairs({ "api.binding.keypress", "api.click.overlap", "api.order.equal-level", "api.hitrect.pointer" }) do Check(gids[id], id .. " is registered") end
  Same(#guided, 4)
  for _, c in ipairs(TL.Select()) do
    Check(c.cat ~= "api" and c.cat ~= "apiguided", c.id .. ": an unqualified run leaves both probe groups out")
  end
  Same(TL.Label(owned[1]), "client", "an owned case is labelled as client evidence")
  Same(TL.Label(guided[1]), "guided")
  -- an unqualified run creates no probe frame, no prompt and no binding
  local fr = ProbeWorld(t)
  local list = TL.Select()
  t.done = nil
  Check(TL.Runner.Start(list, { cats = { "core", "client", "ui" }, clock = t.Clock, onDone = function(s) t.done = s end }))
  t.Frames(900, 0.016)
  Check(t.done, "the default run ended")
  Same(TL.Probe.Snapshot().frames, 0, "and made no probe frame")
  Check(t.c["TwichUITestLabProbearena.back"] == nil and t.c.TwichUITestLabPrompt == nil, "no arena and no prompt")
  Same(t.binds, 0, "and bound nothing")
  Check(t.done.counts.fail == 0 and t.done.counts.error == 0, "with no failure")
end

---------------------------------------------------------------------------
-- 2. api.mouse.states: the probe reports what the frame says, and never claims what is missing
---------------------------------------------------------------------------
do
  local t = Setup()
  ProbeWorld(t)
  local before = DeepCopy(t.c.TwichUIDB)
  t.Run({ "api.mouse.states" })
  t.Frames(20)
  local r = t.Result()
  Same(r.status, "pass", tostring(r.detail))
  local f = t.Facts()
  -- the stand-in sets both flags with EnableMouse and each flag separately: the facts are what it said
  Same(f["api.mouse.frame.enable-true"], "m=T c=T mo=T sh=T vis=T en=-", "a plain frame has no IsEnabled: reported as -, not as a value")
  Same(f["api.mouse.frame.enable-false"], "m=F c=F mo=F sh=T vis=T en=-")
  Same(f["api.mouse.frame.motion-only-by-clicks-off"], "m=T c=F mo=T sh=T vis=T en=-")
  Same(f["api.mouse.frame.clicks-only-by-motion-off"], "m=T c=T mo=F sh=T vis=T en=-")
  Same(f["api.mouse.frame.hidden"], "m=T c=T mo=T sh=F vis=F en=-")
  Same(f["api.mouse.button.disabled"], "m=T c=T mo=T sh=T vis=T en=F", "a disabled Button: the flags and IsEnabled are reported separately")
  Same(f["api.mouse.button.disabled-then-enabled"], "m=T c=T mo=T sh=T vis=T en=T")
  Same(f["api.mouse.method.EnableMouseMotion"], "function"); Same(f["api.mouse.method.EnableMouseClicks"], "nil", "a method the frame lacks is reported as nil")
  Same(f["api.mouse.frame.fresh_read"], "when made in this run")
  Same(f["api.mouse.flags_consistent"], "24 of 24 steps", "this stand-in's IsMouseEnabled is click-or-motion, so the probe finds every step consistent")
  Check(DeepSame(t.c.TwichUIDB, before), "no saved data changed")
  NoCut(t, "api.mouse.states"); Released(t, "after api.mouse.states")
  -- a second run reuses the same frames (a frame cannot be deleted) and says what a fresh one reported when first made
  local made = t.c["TwichUITestLabProbemouse.frame"]
  t.Run({ "api.mouse.states" }); t.Frames(20)
  Check(t.c["TwichUITestLabProbemouse.frame"] == made, "the frame is made once per session")
  Same(t.Facts()["api.mouse.frame.fresh_read"], "when first made, earlier this session")
  Same(t.Facts()["api.mouse.frame.fresh"], f["api.mouse.frame.fresh"], "and the fresh state is the one read at creation")
end

do
  -- a client without the newer methods: reported as missing, never as supported; the case still finishes and cleans up
  local t = Setup()
  ProbeWorld(t, { noEnableMouseMotion = true, noMouseClickEnabled = true })
  t.Run({ "api.mouse.states" }); t.Frames(20)
  local r = t.Result()
  Same(r.status, "pass", tostring(r.detail))
  local f = t.Facts()
  Same(f["api.mouse.method.EnableMouseMotion"], "nil"); Same(f["api.mouse.method.SetMouseClickEnabled"], "nil"); Same(f["api.mouse.method.IsMouseClickEnabled"], "nil")
  Same(f["api.mouse.frame.motion-only-EnableMouseMotion"], "m=F c=- mo=F sh=T vis=T en=-", "an absent setter changed nothing and an absent getter is -")
  Check(t.Notes():find("EnableMouseMotion missing", 1, true) and t.Notes():find("SetMouseClickEnabled missing", 1, true), "the missing calls are listed: " .. t.Notes())
  Check(not t.Notes():find("supported", 1, true), "no claim of support")
  Released(t, "a client without the newer methods")
end

do
  -- IsMouseEnabled disagreeing with click-or-motion is reported, not hidden and not fixed
  local t = Setup()
  local w = ProbeWorld(t)
  local create = t.c.CreateFrame
  t.c.CreateFrame = function(...)
    local f = create(...)
    if f.IsMouseEnabled then function f:IsMouseEnabled() return true end end   -- always true, whatever the flags say
    return f
  end
  t.Run({ "api.mouse.states" }); t.Frames(20)
  -- (a frame that still says "mouse on" after the release is also caught by the case's own cleanup check, which is why it fails here)
  Same(t.Result().status, "fail"); Check(t.Result().detail:find("the probe frames were released", 1, true), t.Result().detail)
  Check(t.Notes():find("IsMouseEnabled is T but click is F and motion is F", 1, true), "the disagreement is listed: " .. t.Notes())
  Check(not t.Facts()["api.mouse.flags_consistent"]:find("^24 of 24"), t.Facts()["api.mouse.flags_consistent"])
end

---------------------------------------------------------------------------
-- 3. api.click.programmatic: the counters report what Click() did; a broken harness fails its control; Click may raise
---------------------------------------------------------------------------
do
  local t = Setup()
  ProbeWorld(t, { click = "always" })
  t.Run({ "api.click.programmatic" }); t.Frames(20)
  Same(t.Result().status, "pass", tostring(t.Result().detail) .. " / " .. t.Notes())
  local f = t.Facts()
  for _, name in ipairs({ "visible-enabled", "disabled", "hidden", "mouse-disabled", "click-disabled", "parent-hidden" }) do
    Same(f["api.click." .. name], "OnClick +1 PreClick +1 PostClick +1, Click() ok", name .. ": this stand-in runs the scripts in every state, and the probe says so")
  end
  Same(f["api.click.disabled.state"], "m=T c=T mo=T sh=T vis=T en=F", "the state at the moment of the Click is recorded")
  Same(f["api.click.hidden.state"], "m=T c=T mo=T sh=F vis=F en=T")
  Same(f["api.click.parent-hidden.state"], "m=T c=T mo=T sh=T vis=F en=T", "a shown button under a hidden parent")
  Same(f["api.click.mouse-disabled.state"], "m=F c=F mo=F sh=T vis=T en=T")
  Check(t.Notes():find("NOT a physical click", 1, true), "the report says a programmatic Click is not a physical click")
  NoCut(t, "api.click.programmatic"); Released(t, "api.click.programmatic")
end

do
  -- a strict client: the counters show zero where the stand-in refused, and the probe restores the button between states
  local t = Setup()
  ProbeWorld(t, { click = "guarded" })
  t.Run({ "api.click.programmatic" }); t.Frames(20)
  Same(t.Result().status, "pass", tostring(t.Result().detail))
  local f = t.Facts()
  Same(f["api.click.visible-enabled"], "OnClick +1 PreClick +1 PostClick +1, Click() ok")
  for _, name in ipairs({ "disabled", "hidden", "mouse-disabled", "click-disabled", "parent-hidden" }) do
    Same(f["api.click." .. name], "OnClick +0 PreClick +0 PostClick +0, Click() ok", name .. ": nothing ran, and the call itself did not raise")
  end
  Released(t, "a strict client")
end

do
  -- a broken harness: Click() never runs the script, so the control row fails and the other rows are not to be trusted
  local t = Setup()
  ProbeWorld(t, { click = "never" })
  t.Run({ "api.click.programmatic" }); t.Frames(20)
  Same(t.Result().status, "fail", "the control fails")
  Check(t.Result().detail:find("control: Click() on a visible, enabled", 1, true), t.Result().detail)
  Released(t, "a broken Click")
  -- Click() that raises (restricted) is recorded, not fatal and not retried another way
  local t2 = Setup()
  ProbeWorld(t2, { click = "raises" })
  t2.Run({ "api.click.programmatic" }); t2.Frames(20)
  Check(t2.Facts()["api.click.hidden"]:find("Click() raised", 1, true), t2.Facts()["api.click.hidden"])
  Check(t2.Notes():find("restricted here", 1, true), "the error text is kept: " .. t2.Notes())
  Same(t2.Result().status, "fail", "and the control row fails because nothing ran")
  Released(t2, "a Click that raises")
end

---------------------------------------------------------------------------
-- 4. api.hitrect.insets
---------------------------------------------------------------------------
do
  local t = Setup()
  ProbeWorld(t)
  t.Run({ "api.hitrect.insets" }); t.Frames(20)
  local r = t.Result()
  Same(r.status, "pass", tostring(r.detail))
  local f = t.Facts()
  Same(f["api.hitrect.set2"], "set 10,20,30,40 read 10,20,30,40 same", "asymmetric values show the order of the four numbers")
  Same(f["api.hitrect.set3"], "set -10,-20,-30,-40 read -10,-20,-30,-40 same", "negative values")
  Same(f["api.hitrect.roundtrip"], "5 of 5 reads equal what was set")
  Same(f["api.hitrect.combat_at_start"], "false")
  NoCut(t, "api.hitrect.insets"); Released(t, "api.hitrect.insets")
  -- a client that rounds what it reports
  local t2 = Setup()
  ProbeWorld(t2, { insetsRoundTrip = function(v) return math.floor(v / 8) * 8 end })
  t2.Run({ "api.hitrect.insets" }); t2.Frames(20)
  Check(t2.Facts()["api.hitrect.set2"]:find("DIFFERENT", 1, true), t2.Facts()["api.hitrect.set2"])
  Check(t2.Facts()["api.hitrect.roundtrip"]:find("^%d+ of 5 reads"), t2.Facts()["api.hitrect.roundtrip"])
  Same(t2.Result().status, "pass", "a difference is a finding, not a failure of the probe: " .. tostring(t2.Result().detail))
  -- a client that refuses the call (protected): recorded as a restriction
  local t3 = Setup()
  ProbeWorld(t3, { setterRaises = { SetHitRectInsets = true } })
  t3.Run({ "api.hitrect.insets" }); t3.Frames(20)
  Same(t3.Result().status, "pass", tostring(t3.Result().detail))
  Check(t3.Notes():find("refused at least once", 1, true) and t3.Notes():find("protected function SetHitRectInsets", 1, true), t3.Notes())
  Check(t3.Facts()["api.hitrect.set1"]:find(": raised", 1, true), t3.Facts()["api.hitrect.set1"])
  Released(t3, "a refused SetHitRectInsets")
  -- a client without the method: skipped with a sentence
  local t4 = Setup()
  ProbeWorld(t4, { noHitRect = true })
  t4.Run({ "api.hitrect.insets" }); t4.Frames(20)
  Same(t4.Result().status, "skipped"); Check(t4.Result().detail:find("no SetHitRectInsets", 1, true), t4.Result().detail)
  Released(t4, "no SetHitRectInsets")
end

---------------------------------------------------------------------------
-- 5. api.binding.override: made, cleared, made again, cleared; combat; missing API; a refused call; nothing saved
---------------------------------------------------------------------------
do
  local t = Setup()
  ProbeWorld(t)
  t.mock.baseAction = "TOGGLEBACKPACK"
  local before = DeepCopy(t.c.TwichUIDB)
  t.Run({ "api.binding.override" }); t.Frames(10)
  local r = t.Result()
  Same(r.status, "pass", tostring(r.detail))
  local f = t.Facts()
  Same(t.binds, 2, "made twice"); Same(t.clears, 2, "cleared once after each binding, and not again when nothing is bound")
  Check(t.last.owner == t.c[t.TL.Guided.NAME] and t.last.owner ~= t.c.UIParent, "owned by the Lab's own button, never UIParent")
  Same(t.last.key, "F9"); Same(t.last.name, t.TL.Guided.NAME)
  Same(f["api.binding.action_before"], "TOGGLEBACKPACK"); Same(f["api.binding.action_after"], "TOGGLEBACKPACK", "the key reports what it did before")
  Check(f["api.binding.action_bound"]:find(t.TL.Guided.NAME, 1, true), "while bound the key names the Lab's button"); Same(f["api.binding.bound_names_lab_button"], "true")
  Same(f["api.binding.action_cleared"], "TOGGLEBACKPACK"); Check(f["api.binding.action_bound_again"]:find("CLICK", 1, true))
  Same(f["api.binding.bind_ok"], "yes"); Same(f["api.binding.rebind_ok"], "yes")
  Check(f["api.binding.combat"]:find("not attempted", 1, true), "the combat answer says it was not attempted")
  Check(not t.TL.Guided.Snapshot().bound and not t.TL.Guided.Snapshot().proxyShown, "nothing bound, key's button hidden")
  Check(DeepSame(t.c.TwichUIDB, before), "no saved data changed (and no SaveBindings call exists: the static scan checks the source)")
  NoCut(t, "api.binding.override"); Released(t, "api.binding.override")
  Same(t.c.TwichUITestLabPrompt, nil, "no prompt was built")
end

do
  local t2 = Setup()
  ProbeWorld(t2)
  t2.done = nil
  Check(t2.TL.Runner.Start({ t2.TL.cases["api.binding.override"] }, { cats = { "api" }, clock = t2.Clock, onDone = function(s) t2.done = s end }))
  t2.combat = true
  t2.Frames(5)
  Check(t2.done and t2.done.ended == "combat", "combat ends the run")
  Same(t2.binds, 0, "and nothing was bound")
  -- the probe itself refuses in combat
  Same(t2.TL.Guided.BindingProbe().refused, "in combat: nothing was attempted")
  Same(t2.binds, 0)
  t2.combat = false
  -- and while a guided request holds the key
  Check(t2.TL.Guided.Begin{ title = "x", lines = {}, capture = function() return {} end })
  Same(t2.TL.Guided.BindingProbe().refused, "a guided request holds the key")
  t2.TL.Guided.End()
  Released(t2, "after combat")
end

do
  -- no binding API at all: the first bind is refused with a sentence, recorded as a restriction; nothing is claimed
  local t = Setup({ noBinding = true })
  ProbeWorld(t)
  t.Run({ "api.binding.override" }); t.Frames(10)
  local r = t.Result()
  Same(r.status, "pass", tostring(r.detail))
  local f = t.Facts()
  Check(f["api.binding.bind_ok"]:find("^no: this client has no SetOverrideBindingClick"), f["api.binding.bind_ok"])
  Check(t.Notes():find("recorded as an observed restriction", 1, true), t.Notes())
  Same(f["api.binding.fn.SetOverrideBindingClick"], "nil")
  Released(t, "no binding API")
  -- the call raises: the same
  local t2 = Setup()
  ProbeWorld(t2)
  t2.mock.bindRaises = true
  t2.Run({ "api.binding.override" }); t2.Frames(10)
  Same(t2.Result().status, "pass", tostring(t2.Result().detail))
  Check(t2.Facts()["api.binding.bind_ok"]:find("^no: the client refused the key binding"), t2.Facts()["api.binding.bind_ok"])
  Released(t2, "a refused binding")
  -- GetBindingAction missing or raising: "n/a" / "raised", not an error
  local t3 = Setup({ noAction = true })
  ProbeWorld(t3)
  t3.Run({ "api.binding.override" }); t3.Frames(10)
  Same(t3.Result().status, "pass", tostring(t3.Result().detail)); Same(t3.Facts()["api.binding.action_before"], "n/a")
  local t4 = Setup()
  ProbeWorld(t4)
  t4.mock.actionRaises = true
  t4.Run({ "api.binding.override" }); t4.Frames(10)
  Same(t4.Facts()["api.binding.action_before"], "raised"); Released(t4, "GetBindingAction raising")
end

---------------------------------------------------------------------------
-- 6. Every route that ends a case or a run releases the probe frames: error, Stop, timeout, combat, a closed window
---------------------------------------------------------------------------
do
  local function Fresh()
    local t = Setup()
    local w = ProbeWorld(t)
    local TL = t.TL
    TL.Category{ id = "zz", label = "ZZ", optin = true }
    return t, w, TL
  end
  local function Build(tt, TL)   -- what a probe case holds: shown frames with scripts, a trial
    local P = TL.Probe
    local f = P.Get("leak.button", "Button")
    P.Do(f, "SetScript", "OnClick", function() end); P.Do(f, "Show"); P.Do(f, "EnableMouse", true)
    P.Overlap("frame"); P.NewTrial()
    local ps = P.Snapshot()
    Check(ps.shown >= 3 and ps.mouse >= 3 and ps.scripted >= 3 and ps.trial, "the case holds live frames")
  end
  -- an error mid-case
  do
    local t, w, TL = Fresh()
    TL.Case{ id = "zz.error", cat = "zz", class = "owned", run = function(tt) Build(tt, TL); error("boom", 0) end }
    t.Run({ "zz.error" }, { "zz" }); t.Frames(5)
    Same(t.Result().status, "error"); Released(t, "an error")
  end
  -- a case that finishes normally without cleaning up after itself
  do
    local t, w, TL = Fresh()
    TL.Case{ id = "zz.forgot", cat = "zz", class = "owned", run = function(tt) Build(tt, TL); tt:Check(true) end }
    t.Run({ "zz.forgot" }, { "zz" }); t.Frames(5)
    Same(t.Result().status, "pass"); Released(t, "a case that did not clean up")
  end
  -- Stop while waiting at a yield point
  do
    local t, w, TL = Fresh()
    TL.Case{ id = "zz.wait", cat = "zz", class = "owned", budget = 30, run = function(tt) Build(tt, TL); tt:Wait(20) end }
    t.Run({ "zz.wait" }, { "zz" }); t.Frames(5)
    Check(TL.Runner.Active() and TL.Probe.Snapshot().shown >= 3, "waiting with live frames")
    TL.Runner.Stop("user")
    Same(t.done.results[1].status, "stopped"); Released(t, "Stop")
  end
  -- a timeout
  do
    local t, w, TL = Fresh()
    TL.Case{ id = "zz.slow", cat = "zz", class = "owned", budget = 1, run = function(tt) Build(tt, TL); for _ = 1, 100 do tt:Wait(0.2) end end }
    t.Run({ "zz.slow" }, { "zz" }); t.Frames(200, 0.05)
    Same(t.done.results[1].status, "timeout"); Released(t, "a timeout")
  end
  -- combat
  do
    local t, w, TL = Fresh()
    TL.Case{ id = "zz.fight", cat = "zz", class = "owned", budget = 30, run = function(tt) Build(tt, TL); tt:Wait(20) end }
    t.Run({ "zz.fight" }, { "zz" }); t.Frames(3)
    t.combat = true; t.Frames(2)
    Same(t.done.ended, "combat"); Released(t, "combat")
  end
  -- the window closed
  do
    local t, w, TL = Fresh()
    TL.Case{ id = "zz.window", cat = "zz", class = "owned", budget = 30, run = function(tt) Build(tt, TL); tt:Wait(20) end }
    t.Run({ "zz.window" }, { "zz" }); t.Frames(3)
    TL.Runner.Stop("closed")
    Same(t.done.ended, "closed"); Released(t, "a closed window")
  end
end

---------------------------------------------------------------------------
-- 7. The click arrangement: the trial records what the frames received, not what anyone expected
---------------------------------------------------------------------------
do
  local t = Setup()
  local w = ProbeWorld(t)
  local P = t.TL.Probe
  local info = P.Overlap("frame")
  Same(info.status.enable, "ok"); Check(info.readback:find("^m=T c=T mo=T"), info.readback)
  local zone = P.Zone()
  Check(zone and zone[1] < zone[3], "the highlighted square has a rectangle in screen units")
  local cx, cy = w:Mark()
  P.NewTrial()
  w:Press(cx, cy)
  Check(not P.TrialDone(), "a click is not finished until it has been quiet for a moment")
  t.Advance(0.5)
  Check(P.TrialDone(), "and is finished after it")
  local s = P.Summarize(P.Trial(), zone)
  Same(table.concat(s.foci, ">"), "U>L>back", "the stack GetMouseFoci gave, by piece name, top first")
  Same(table.concat(s.ups, "+"), "U", "the press went to U (a plain Frame: no OnClick)"); Same(#s.clicks, 0)
  Check(s.inZone == true and s.hasFoci and s.hasCursor)
  -- a click outside the square is recognised as outside
  P.NewTrial()
  w:Press(cx + 200, cy + 100)
  t.Advance(0.5)
  local out = P.Summarize(P.Trial(), zone)
  Check(out.inZone == false and out.away[1] > 0, "a click outside the square is not inside it (" .. tostring(out.away and out.away[1]) .. " px)")
  -- the trial is bounded
  P.NewTrial()
  for _ = 1, 100 do w:Press(cx, cy) end
  Check(#P.Trial().events <= P.MAX_EVENTS and (P.Trial().dropped or 0) > 0, "at most " .. P.MAX_EVENTS .. " records are kept")
  P.Release()
  Same(P.Trial(), nil, "Release forgets the trial")
  -- a hit-area arrangement leaves no inset behind on its button, or a propagating flag on the upper frame
  local ha = P.HitArea()
  Same(select(2, ha.target:GetHitRectInsets()), -50, "the arrangement set a negative inset")
  P.Overlap("propagate")
  P.Release()
  local l, r, tp, b = ha.target:GetHitRectInsets()
  Check(l == 0 and r == 0 and tp == 0 and b == 0, "Release put the insets back to zero")
  Same(t.c["TwichUITestLabProbearena.U"]:GetPropagateMouseClicks(), false, "and the propagating flag back to off")
  Check(not t.c["TwichUITestLabProbearena.back"]:IsShown(), "and hides the backdrop")
end


---------------------------------------------------------------------------
-- 8. api.binding.keypress: a button press is not a key press; two key presses with a clear and a new binding between them
---------------------------------------------------------------------------
local function Prompt(t) return t.c.TwichUITestLabPrompt end
local function Press(btn) btn.scripts.OnClick(btn) end

do
  local t = Setup()
  ProbeWorld(t)
  local G = t.TL.Guided
  t.mock.baseAction = "TOGGLEBACKPACK"
  local before = DeepCopy(t.c.TwichUIDB)
  t.Run({ "api.binding.keypress" }, { "apiguided" }); t.Frames(5)
  Check(t.TL.Runner.Active(), "it waits for the player: nothing happens by itself")
  Check(G.Snapshot().bound == "F9" and t.binds == 1, "the first binding is live")
  Same(t.last.owner, t.c[G.NAME])
  Press(Prompt(t).sample); t.Frames(4)   -- the prompt's own button: not a key press
  Check(Prompt(t).status:GetText():find("that was the button, not the key", 1, true), Prompt(t).status:GetText())
  Check(t.TL.Runner.Active() and G.Status() == "waiting", "and it asked again")
  t.Key(); t.Frames(6)
  Check(t.TL.Runner.Active(), "the second step is waiting")
  Same(t.binds, 2, "the binding was registered again")
  Check(G.Snapshot().bound == "F9", "and is live again")
  Check(Prompt(t).title:GetText():find("Binding probe 2 of 2", 1, true), Prompt(t).title:GetText())
  t.Key(); t.Frames(6)
  Check(not t.TL.Runner.Active(), "the case ended")
  Same(t.Result().status, "pass", tostring(t.Result().detail))
  local f = t.Facts()
  Same(f["api.keypress.first"], "key press arrived (attempt 2)", "the button press counted as an attempt but not as a key")
  Same(f["api.keypress.second"], "key press arrived (attempt 1)")
  Same(f["api.keypress.action_before"], "TOGGLEBACKPACK"); Same(f["api.keypress.action_after_clear"], "TOGGLEBACKPACK"); Same(f["api.keypress.action_after_final_clear"], "TOGGLEBACKPACK")
  Check(f["api.keypress.action_while_bound"]:find(G.NAME, 1, true), "while bound the key names the Lab's button")
  Check(t.Notes():find("never listens to the keyboard", 1, true), "the report says an unbound key's press cannot be observed")
  Check(DeepSame(t.c.TwichUIDB, before), "no saved data changed")
  NoCut(t, "api.binding.keypress"); Released(t, "api.binding.keypress")
end

do   -- the client will not bind the key: skipped with a sentence and the fact; Skip; Cancel; combat; a timeout
  local t = Setup({ noBinding = true })
  ProbeWorld(t)
  t.Run({ "api.binding.keypress" }, { "apiguided" }); t.Frames(5)
  Same(t.Result().status, "skipped"); Check(t.Result().detail:find("would not bind the key", 1, true), t.Result().detail)
  Same(t.Facts()["api.keypress.bind_refused"], "yes"); Released(t, "no binding API")

  local t2 = Setup()
  ProbeWorld(t2)
  t2.Run({ "api.binding.keypress" }, { "apiguided" }); t2.Frames(5)
  Press(Prompt(t2).skip); t2.Frames(4)
  Same(t2.Result().status, "skipped"); Released(t2, "Skip")

  local t3 = Setup()
  ProbeWorld(t3)
  t3.Run({ "api.binding.keypress" }, { "apiguided" }); t3.Frames(5)
  t3.Key(); t3.Frames(5)   -- second step is up
  Press(Prompt(t3).cancel)
  Check(t3.done.results[1].status == "stopped", "Cancel stops the run: " .. t3.done.results[1].status); Released(t3, "Cancel in the second step")

  local t4 = Setup()
  ProbeWorld(t4)
  t4.Run({ "api.binding.keypress" }, { "apiguided" }); t4.Frames(5)
  t4.combat = true; t4.Frames(2)
  Same(t4.done.ended, "combat"); Released(t4, "combat during the key request")

  local t5 = Setup()
  ProbeWorld(t5)
  t5.Run({ "api.binding.keypress" }, { "apiguided" }); t5.Frames(5)
  t5.Frames(40, 5)   -- 200 s of nobody pressing anything
  Same(t5.done.results[1].status, "timeout"); Released(t5, "a timeout")
end

---------------------------------------------------------------------------
-- 9. api.click.overlap: a click outside the square is not counted; GetMouseFoci, OnClick and what you saw are reported separately
---------------------------------------------------------------------------
do
  local t = Setup()
  local w = ProbeWorld(t, { route = function(stack, default)   -- this stand-in client gives the click to the lowest Button in the stack, whatever is on top
    if #stack >= 2 and stack[1]._name and stack[1]._name:find("arena%.U") then
      for i = #stack, 1, -1 do if stack[i]._kind == "Button" then return { stack[i] } end end
    end
    return default
  end })
  local G = t.TL.Guided
  local before = DeepCopy(t.c.TwichUIDB)
  t.Run({ "api.click.overlap" }, { "apiguided" }); t.Frames(5)
  local prompt = Prompt(t)
  Check(t.TL.Runner.Active() and prompt:IsShown(), "the prompt is up and waiting for a click")
  Same(t.binds, 0, "a click request binds no key"); Check(G.Snapshot().bound == nil)
  Check(not prompt.sample:IsShown() and not prompt.count:IsShown() and prompt.skip:IsShown(), "no Sample buttons, only Skip and Cancel")
  Check(prompt.title:GetText():find("Click probe: 1 of 4, the upper frame's mouse is OFF", 1, true), prompt.title:GetText())
  Check(prompt.choiceBtns[1]:IsShown() and prompt.choiceBtns[3]:IsShown(), "the answer buttons are up")
  Check(prompt.choiceBtns[1].text:GetText() == "Orange is on top", prompt.choiceBtns[1].text:GetText())
  local cx, cy = w:Mark()
  w:Press(cx + 220, cy); t.Frames(30)   -- on the backdrop, outside the highlighted square
  Check(prompt.status:GetText():find("Not counted (1 of 8)", 1, true) and prompt.status:GetText():find("Click inside it", 1, true), prompt.status:GetText())
  w:Press(cx, cy); t.Frames(30)
  Check(prompt.status:GetText():find("Now answer", 1, true), prompt.status:GetText())
  Check(t.TL.Runner.Active(), "it waits for the answer as well")
  Press(prompt.choiceBtns[2]); t.Frames(5)   -- "Blue is on top"
  -- step 2: the upper frame's mouse is ON, but this client gives the click to the lowest Button
  Check(prompt.title:GetText():find("2 of 4, the upper frame's mouse is ON", 1, true), prompt.title:GetText())
  Check(not prompt.choiceBtns[1]:IsShown(), "no question in the later steps (the colours do not change)")
  cx, cy = w:Mark()
  w:Press(cx, cy); t.Frames(30)
  Check(prompt.title:GetText():find("3 of 4", 1, true), "the step moved on after one click: " .. prompt.title:GetText())
  cx, cy = w:Mark(); w:Press(cx, cy); t.Frames(30)
  cx, cy = w:Mark(); w:Press(cx, cy); t.Frames(30)
  Check(not t.TL.Runner.Active(), "all four steps done")
  local r = t.Result()
  Same(r.status, "pass", tostring(r.detail) .. t.Notes())
  local f = t.Facts()
  Same(f["api.overlap.mouse-off.onclick"], "L"); Same(f["api.overlap.mouse-off.foci"], "L>back"); Same(f["api.overlap.mouse-off.visual"], "L", "the answer is stored as the colour you chose")
  Same(f["api.overlap.mouse-off.model"], "reachable"); Same(f["api.overlap.mouse-off.model_agrees_with_onclick"], "yes")
  -- the three pieces of evidence differ here, and the report says so rather than merging them
  Same(f["api.overlap.mouse-on.foci_top"], "U", "GetMouseFoci says U is under the pointer")
  Same(f["api.overlap.mouse-on.onclick"], "L", "but OnClick ran on L")
  Same(f["api.overlap.mouse-on.foci_top_ran_onclick_or_up"], "NO", "the report says the topmost frame did not get the click")
  Same(f["api.overlap.mouse-on.model_agrees_with_onclick"], "NO", "the model said U blocks L: that disagrees with this client, and is reported as such")
  Check(f["api.overlap.mouse-on.model"]:find("blocked by U", 1, true), f["api.overlap.mouse-on.model"])
  Same(f["api.overlap.clicks-off.onclick"], "L"); Same(f["api.overlap.clicks-off.foci_top"], "U", "a frame with clicks off is still under the pointer")
  Same(f["api.overlap.propagate.mouseup"], "L", "this client's routing gives the click to the lowest Button here too: whatever the frames did is what is reported")
  Check(t.Notes():find("model vs OnClick on L: NO", 1, true) and t.Notes():find("you saw: blue on top", 1, true), t.Notes())
  Check(DeepSame(t.c.TwichUIDB, before), "no saved data changed")
  NoCut(t, "api.click.overlap"); Released(t, "api.click.overlap")
  -- the report: labelled guided, the facts present, no private name
  local text = t.TL.Report.Build(t.done)
  Check(text:find("api.overlap.mouse-on.foci_top=U", 1, true) and text:find("guided", 1, true), "the facts and the label are in the report")
  Check(not text:find("Zzchar", 1, true) and not text:find("Zzrealm", 1, true) and not text:find("Zzguild", 1, true), "no private name")
end

do   -- a client that routes by the stack (the first click-enabled frame, passing it on when it propagates): each configuration reports what it did
  local t = Setup()
  local w = ProbeWorld(t)
  t.Run({ "api.click.overlap" }, { "apiguided" }); t.Frames(5)
  local prompt = Prompt(t)
  for i = 1, 4 do
    local cx, cy = w:Mark(); w:Press(cx, cy); t.Frames(30)
    if i == 1 then Press(prompt.choiceBtns[1]); t.Frames(5) end
  end
  Check(not t.TL.Runner.Active())
  local f = t.Facts()
  Same(f["api.overlap.mouse-on.onclick"], "none", "a plain Frame has no OnClick"); Same(f["api.overlap.mouse-on.mouseup"], "U"); Same(f["api.overlap.mouse-on.foci_top_ran_onclick_or_up"], "yes")
  Same(f["api.overlap.mouse-on.model_agrees_with_onclick"], "yes", "the model said U blocks L, and L did not run")
  Same(f["api.overlap.clicks-off.onclick"], "L"); Same(f["api.overlap.clicks-off.foci_top"], "U"); Same(f["api.overlap.clicks-off.foci_top_ran_onclick_or_up"], "NO")
  Same(f["api.overlap.propagate.mouseup"], "U+L"); Same(f["api.overlap.propagate.onclick"], "L")
  Same(f["api.overlap.clicks-off.model_agrees_with_onclick"], "yes"); Same(f["api.overlap.propagate.model_agrees_with_onclick"], "yes")
  Same(f["api.overlap.mouse-off.visual"], "U")
  Same(t.Result().status, "pass", tostring(t.Result().detail)); Released(t, "a stack-routing client")
end

do   -- skipping a step, an API the client lacks, and Cancel
  local t = Setup()
  local w = ProbeWorld(t, { noPropagate = true, noMouseClickEnabled = true })
  t.Run({ "api.click.overlap" }, { "apiguided" }); t.Frames(5)
  local prompt = Prompt(t)
  Press(prompt.skip); t.Frames(4)   -- skip step 1
  Check(prompt.title:GetText():find("2 of 4", 1, true), "the next step is up after a skip: " .. prompt.title:GetText())
  local cx, cy = w:Mark(); w:Press(cx, cy); t.Frames(30)
  Check(not t.TL.Runner.Active(), "steps 3 and 4 need methods this client lacks: they are not asked")
  local f = t.Facts()
  Same(f["api.overlap.mouse-off.result"], "skipped by you")
  Same(f["api.overlap.clicks-off.unsupported"], "SetMouseClickEnabled missing", "an absent method is reported as absent")
  Same(f["api.overlap.propagate.unsupported"], "SetPropagateMouseClicks missing")
  Check(f["api.overlap.mouse-on.mouseup"] == "U", "the measured step is there")
  Same(t.Result().status, "pass", tostring(t.Result().detail)); Released(t, "skipped and unsupported steps")

  local t2 = Setup()
  local w2 = ProbeWorld(t2, { propagateRaises = true })
  t2.Run({ "api.click.overlap" }, { "apiguided" }); t2.Frames(5)
  Press(Prompt(t2).skip); t2.Frames(8); Press(Prompt(t2).skip); t2.Frames(8); Press(Prompt(t2).skip); t2.Frames(8)
  Check(not t2.TL.Runner.Active(), "ended: " .. tostring(Prompt(t2).title:GetText()) .. " / " .. tostring(Prompt(t2).status:GetText()))
  Check(t2.Facts()["api.overlap.propagate.unsupported"]:find("^SetPropagateMouseClicks raised"), t2.Facts()["api.overlap.propagate.unsupported"])
  Released(t2, "a refused SetPropagateMouseClicks")

  local t3 = Setup()
  ProbeWorld(t3)
  t3.Run({ "api.click.overlap" }, { "apiguided" }); t3.Frames(5)
  Check(t3.c["TwichUITestLabProbearena.back"]:IsShown(), "the arena is up")
  Press(Prompt(t3).cancel)
  Same(t3.done.results[1].status, "stopped"); Released(t3, "Cancel")
  Check(not t3.c["TwichUITestLabProbearena.back"]:IsShown() and not t3.c["TwichUITestLabProbearena.mark"]:IsShown(), "the arena is hidden")
end

---------------------------------------------------------------------------
-- 10. api.order.equal-level: the observation is computed from the scenarios, and the analyzer keeps its ambiguous verdict
---------------------------------------------------------------------------
local function Order(opts, pick)
  local t = Setup()
  local w = ProbeWorld(t, opts)
  t.Run({ "api.order.equal-level" }, { "apiguided" }); t.Frames(5)
  for i = 1, 4 do
    local cx, cy = w:Mark()
    w:Press(cx, cy); t.Frames(30)
    Press(Prompt(t).choiceBtns[pick or 3]); t.Frames(5)
  end
  Check(not t.TL.Runner.Active(), "all four arrangements done")
  return t
end

do
  local t = Order({}, 3)   -- this client: the frame created last is on top, whatever the show order or the parents
  Same(t.Result().status, "pass", tostring(t.Result().detail))
  local f = t.Facts()
  Same(f["api.order.s1.foci_top"], "B"); Same(f["api.order.s2.foci_top"], "B"); Same(f["api.order.s3.foci_top"], "A", "B was created before A in the second pair"); Same(f["api.order.s4.foci_top"], "B")
  Same(f["api.order.s1.onclick"], "B", "the frame that ran OnClick")
  Same(f["api.order.s1.visual"], "?", "what the person saw is a separate answer")
  Same(f["api.order.s1.visual_equals_foci"], "not answered")
  Same(f["api.order.top_is_createdLast"], "4 of 4 scenarios"); Same(f["api.order.top_is_lastShown"], "2 of 4 scenarios"); Same(f["api.order.top_is_parentCreatedLast"], "1 of 1 scenarios")
  Check(f["api.order.observation"]:find("last frame created", 1, true), f["api.order.observation"])
  for i = 1, 4 do Same(f["api.order.s" .. i .. ".model"], "ambiguous", "the analyzer calls equal strata and level ambiguous") end
  Check(f["api.order.analyzer"]:find("unchanged", 1, true) and f["api.order.analyzer"]:find("ambiguous", 1, true))
  Check(t.Notes():find("NOT a universal rule", 1, true), "the report says it is not a universal rule")
  Check(t.Notes():find("created B first", 1, true) or t.Notes():find("pair 2 (A created last)", 1, true), t.Notes())
  NoCut(t, "api.order.equal-level"); Released(t, "api.order.equal-level")
end

do
  local t = Order({ tie = "shown" }, 1)   -- a client where the frame shown last is on top
  local f = t.Facts()
  Same(f["api.order.top_is_lastShown"], "4 of 4 scenarios"); Same(f["api.order.top_is_createdLast"], "2 of 4 scenarios")
  Check(f["api.order.observation"]:find("last frame shown", 1, true), f["api.order.observation"])
  Same(f["api.order.s1.visual"], "B", "the first answer button is Orange (B)")
  Same(f["api.order.s1.visual_equals_foci"], "yes")
  Same(f["api.order.s2.foci_top"], "A")
  Released(t, "a show-order client")
end

do
  local t = Order({ tie = "A" }, 2)   -- a client that follows neither: no single rule is claimed
  local f = t.Facts()
  Check(f["api.order.observation"]:find("no single rule", 1, true), f["api.order.observation"])
  Same(f["api.order.s1.visual"], "A"); Same(f["api.order.s1.visual_equals_foci"], "yes")
  Released(t, "a mixed client")
end

---------------------------------------------------------------------------
-- 11. api.hitrect.pointer: the model is compared with the pointer, and a disagreement fails the case with the evidence
---------------------------------------------------------------------------
local function Hit(opts)
  local t = Setup()
  local w = ProbeWorld(t, opts)
  t.Run({ "api.hitrect.pointer" }, { "apiguided" }); t.Frames(5)
  return t, w
end

do
  local t, w = Hit({})
  if t.TL.Runner.Active() then
    for _ = 1, 3 do
      local cx, cy = w:Mark()
      w:Press(cx, cy); t.Frames(30)
    end
  end
  Check(not t.TL.Runner.Active(), "all three zones done")
  Same(t.Result().status, "pass", tostring(t.Result().detail) .. t.Notes())
  local f = t.Facts()
  Same(f["api.hitrect.pointer.set_insets"], "ok"); Same(f["api.hitrect.pointer.read_back"], "70,-50,0,0")
  Same(f["api.hitrect.pointer.centre.onclick_on_T"], "true"); Same(f["api.hitrect.pointer.left-strip.onclick_on_T"], "false", "inside the paint but outside the hit rectangle")
  Same(f["api.hitrect.pointer.right-extension.onclick_on_T"], "true", "outside the paint, inside the extended hit rectangle")
  Same(f["api.hitrect.pointer.left-strip.model_says_inside"], "false"); Same(f["api.hitrect.pointer.right-extension.model_says_inside"], "true")
  NoCut(t, "api.hitrect.pointer"); Released(t, "api.hitrect.pointer")
end

do   -- a client whose pointer ignores the insets: the model disagrees, the case fails and says where
  local t, w = Hit({ insetsIgnoredByPointer = true })
  for _ = 1, 3 do
    if t.TL.Runner.Active() then local cx, cy = w:Mark(); w:Press(cx, cy); t.Frames(30) end
  end
  local r = t.Result()
  Same(r.status, "fail", "the model and the pointer disagree")
  Check(r.detail:find("the model said outside the hit rectangle and OnClick ran on the button", 1, true), r.detail)
  Same(t.Facts()["api.hitrect.pointer.left-strip.onclick_on_T"], "true")
  Released(t, "a client that ignores the insets")
end

do   -- the client refuses SetHitRectInsets: skipped with the observed restriction, nothing left on screen
  local t, w = Hit({ setterRaises = { SetHitRectInsets = true } })
  Same(t.Result().status, "skipped"); Check(t.Result().detail:find("did not take SetHitRectInsets", 1, true) and t.Result().detail:find("observed restriction", 1, true), t.Result().detail)
  Released(t, "a refused SetHitRectInsets"); Check(not t.c["TwichUITestLabProbearena.back"]:IsShown())
end

---------------------------------------------------------------------------
-- 12. The numeric guards (client.lua.nan-guards, numeric.guards.held-counts) pass offline and report; the report stays bounded and private
---------------------------------------------------------------------------
do
  local t = Setup()
  ProbeWorld(t)
  for _, c in ipairs({ "Core", "Market", "Crafting" }) do end
  Check(t.TL.cases["client.lua.nan-guards"] and t.TL.cases["numeric.guards.held-counts"], "both numeric cases are registered")
  Same(t.TL.cases["client.lua.nan-guards"].class, "readonly"); Same(t.TL.cases["numeric.guards.held-counts"].class, "pure")
end

print("PASSED test_testlab_api")
