-- The Test Lab's reachability analysis (TwichUI_TestLab/Reach.lua): eligibility, hit rectangles, insets, strata and levels, clipping, ties,
-- a planted blocking overlay (seen, then removed), the redaction of names and the bounded scan.
-- OFFLINE MODEL (tests/reach_world.lua): it proves the analysis does what it says on typed-in rectangles. It does not show how the game
-- orders frames or routes the pointer; only the guided probe in the client (cases/UI.lua) observes that.
local World = dofile(TESTS .. "reach_world.lua")

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local function Load(world, extra)
  local env = setmetatable({ TwichUI = {} }, { __index = _G })
  env._G = env
  if world then world:Install(env) end
  for k, v in pairs(extra or {}) do env[k] = v end
  local chunk = assert(loadfile(ROOT .. "../TwichUI_TestLab/Reach.lua"))
  setfenv(chunk, env)
  chunk("TwichUI_TestLab", {})
  return env.TwichUI.TestLab.Reach, env
end

local function Reasons(e) local out = {} for _, r in ipairs(e.reasons) do out[#out + 1] = r.code end table.sort(out) return table.concat(out, ",") end

---------------------------------------------------------------------------
-- 1. Eligibility: one reason at a time, then together; what a stand-in cannot answer is unknown, never success
---------------------------------------------------------------------------
do
  local w = World.New()
  local RC = Load(w)
  local win = w:Frame{ name = "Win", x = 0, y = 0, w = 1000, h = 800 }
  local function Btn(def) def.type = "Button"; def.parent = def.parent or win; def.x, def.y, def.w, def.h = 10, 10, 100, 30; def.onClick = def.onClick or function() end return w:Frame(def) end

  local ok = Btn{ name = "Ok" }
  local e = RC.Eligibility(ok, "click")
  Check(e.ok and #e.reasons == 0 and #e.unknown == 0, "a shown, enabled, mouse-on button with a handler is eligible: " .. e.text)
  Same(e.text, "eligible according to the frame's own state")

  local hidden = Btn{ name = "Hidden", shown = false }
  Same(Reasons(RC.Eligibility(hidden)), "hidden", "a hidden frame")

  local panel = w:Frame{ name = "Panel", parent = win, x = 0, y = 0, w = 500, h = 500 }
  local inPanel = Btn{ name = "InPanel", parent = panel }
  panel:Hide()
  e = RC.Eligibility(inPanel)
  Same(Reasons(e), "ancestor-hidden", "a hidden ancestor, not the frame itself")
  Check(e.reasons[1].text:find("Panel", 1, true), "and the report names the hidden ancestor: " .. e.reasons[1].text)
  Same(e.state.shown, true, "the frame itself reports shown")
  panel:Show()

  local off = Btn{ name = "Off" }; off:Disable()
  Same(Reasons(RC.Eligibility(off)), "disabled")
  local nomouse = Btn{ name = "NoMouse", mouse = false }
  Same(Reasons(RC.Eligibility(nomouse)), "mouse-disabled", "mouse input off: one reason, not three")
  local noclick = Btn{ name = "NoClick", click = false }
  Same(Reasons(RC.Eligibility(noclick, "click")), "click-disabled", "mouse clicks off while motion is on")
  Same(Reasons(RC.Eligibility(noclick, "hover")), "no-enter-handler", "clicks off does not stop hover (only the missing OnEnter shows)")
  local nomotion = Btn{ name = "NoMotion", motion = false, onEnter = function() end }
  Same(Reasons(RC.Eligibility(nomotion, "hover")), "motion-disabled")
  Check(RC.Eligibility(nomotion, "click").ok, "motion off does not stop a click")
  local nohandler = w:Frame{ type = "Button", name = "NoHandler", parent = win, x = 10, y = 10, w = 50, h = 20 }
  Same(Reasons(RC.Eligibility(nohandler)), "no-click-handler", "no OnClick script")
  Check(RC.Eligibility(nohandler).state.handler == false)
  local many = Btn{ name = "Many", shown = false, enabled = false, mouse = false }
  many.scripts.OnClick = nil
  Same(Reasons(RC.Eligibility(many)), "disabled,hidden,mouse-disabled,no-click-handler", "every reason is listed (not-visible is not repeated for a frame that is itself hidden)")

  -- an older client without IsMouseClickEnabled: not applicable, not a failure; a plain Frame has no IsEnabled
  local old = Btn{ name = "Old", noClickEnabled = true }
  Check(RC.Eligibility(old).ok, "no IsMouseClickEnabled: not applicable")
  local plain = w:Frame{ name = "Plain", parent = win, x = 0, y = 0, w = 10, h = 10, mouse = true, onClick = function() end }
  Check(RC.Eligibility(plain).ok, "a plain Frame has no IsEnabled and needs none")

  -- a stand-in that does not model the questions: every answer is unknown and the frame is NOT eligible
  local lazy = setmetatable({}, { __index = function(_, k) if k:find("^%u") then return function() end end end })
  e = RC.Eligibility(lazy, "click")
  Check(not e.ok and #e.unknown >= 3, "an un-modelled stand-in is unknown, not eligible: " .. e.text)
  Check(e.text:find("unknown", 1, true), "and says unknown")
  local bare = {}
  Check(not RC.Eligibility(bare).ok, "a table with no widget methods is not eligible")
  Check(not RC.Eligibility(nil).ok, "nil is not eligible")
  -- a method that raises, and one that answers a secret value, are unknown
  local boom = setmetatable({ IsShown = function() error("boom") end }, { __index = function() return nil end })
  Check(not RC.Eligibility(boom).ok)
  local RC2 = Load(w, { issecretvalue = function(v) return v == "SECRET" end })
  local sec = Btn{ name = "Sec" }
  sec.IsMouseEnabled = function() return "SECRET" end
  e = RC2.Eligibility(sec)
  Check(not e.ok and e.text:find("IsMouseEnabled", 1, true), "a secret answer is unknown: " .. e.text)
  -- the caller's own script test
  local hooked = w:Frame{ type = "Button", name = "Hooked", parent = win, x = 0, y = 0, w = 10, h = 10 }
  Check(RC.Eligibility(hooked, "click", { hasScript = function() return true end }).ok, "hasScript answers for a stand-in")
end

---------------------------------------------------------------------------
-- 2. The hit rectangle: scale, insets (negative extends), the empty case
---------------------------------------------------------------------------
do
  local w = World.New()
  local RC = Load(w)
  local win = w:Frame{ name = "Win", x = 0, y = 0, w = 1000, h = 800, scale = 2 }
  local b = w:Frame{ type = "Button", name = "B", parent = win, x = 200, y = 100, w = 100, h = 40, onClick = function() end }
  local hr = RC.HitRect(b)
  -- the frame reports x 100 (= 200 / 2) in its own units; times its effective scale 2 gives the screen units back
  Same(hr.scale, 2); Same(hr.rect[1], 200); Same(hr.rect[2], 100); Same(hr.rect[3], 300); Same(hr.rect[4], 140)
  Same(hr.hit[1], 200, "no insets: the hit rectangle is the frame")
  -- insets are in the frame's own units: left 10 and right 20 and top 5 and bottom 5, at scale 2 = 20 / 40 / 10 / 10 screen units
  b:SetHitRectInsets(10, 20, 5, 5)
  hr = RC.HitRect(b)
  Same(hr.hit[1], 220, "left inset 10 x scale 2"); Same(hr.hit[3], 260, "right inset 20 x 2"); Same(hr.hit[2], 110, "bottom inset 5 x 2"); Same(hr.hit[4], 130, "top inset 5 x 2")
  Same(hr.rect[1], 200, "the frame's own rectangle is unchanged")
  -- a negative inset extends the hit area past the frame (UI.Switch does this to include its label)
  b:SetHitRectInsets(-30, 0, -3, -3)
  hr = RC.HitRect(b)
  Same(hr.hit[1], 140, "-30 x 2 = 60 to the left"); Same(hr.hit[4], 146, "-3 x 2 = 6 above")
  b:SetHitRectInsets(60, 60, 0, 0)   -- 60 + 60 = 120 frame units > width 50
  hr = RC.HitRect(b)
  Check(hr.empty, "insets that consume the whole width leave nothing")
  local res = RC.Analyze(b, { collected = RC.Collect({ frames = w.frames }) })
  Same(res.verdict, "unhittable"); Check(res.why:find("empty", 1, true) and res.text:find("insets", 1, true), res.text)
  -- no rectangle at all
  local naked = { GetRect = function() return nil end }
  local none, why = RC.HitRect(naked)
  Check(none == nil and why:find("no rectangle", 1, true), "an unanchored frame has no hit rectangle: " .. tostring(why))
  Check(not RC.HitRect({}), "a table with no GetRect")
  local nan = { GetRect = function() return 0 / 0, 0, 10, 10 end }
  Check(not RC.HitRect(nan), "NaN is not a rectangle")
end

---------------------------------------------------------------------------
-- 3. Reachability: reachable, then a planted overlay blocks it, then the overlay is removed
---------------------------------------------------------------------------
do
  local w = World.New()
  local RC = Load(w)
  local win = w:Frame{ name = "Window", x = 100, y = 100, w = 800, h = 600, strata = "HIGH", level = 5, mouse = true }
  local add = w:Frame{ type = "Button", name = "AddButton", parent = win, x = 400, y = 300, w = 120, h = 30, level = 6, onClick = function() end }
  -- the centre of the button: x 460, y 315
  local function Look(opts)
    opts = opts or {}
    opts.collected = RC.Collect({ frames = w.frames })
    return RC.Analyze(add, opts)
  end
  local r = Look()
  Same(r.verdict, "reachable", r.text)
  Same(r.point[1], 460); Same(r.point[2], 315)
  Same(r.relation, "self"); Same(r.top.label, "AddButton")
  Check(r.chain == "Window > AddButton", r.chain)

  -- the planted overlay: a mouse-enabled frame in a higher strata over the button
  local overlay = w:Frame{ name = "PlantedOverlay", parent = nil, x = 380, y = 280, w = 200, h = 80, strata = "DIALOG", level = 1, mouse = true }
  r = Look()
  Same(r.verdict, "blocked", r.text)
  Same(r.relation, "other"); Same(r.blocker.label, "PlantedOverlay")
  Check(r.text:find("BLOCKED click on AddButton", 1, true), r.text)
  Check(r.text:find("blocking frame: PlantedOverlay", 1, true) and r.text:find("DIALOG level 1", 1, true), "the blocker, its strata and level: " .. r.text)
  Check(r.text:find("expected hit point: x 460 y 315", 1, true), "the expected point")
  Check(r.text:find("effective hit rect: x 400..520 y 300..330", 1, true), "the effective hit rectangle")
  Check(r.text:find("hierarchy: Window > AddButton", 1, true), "the hierarchy")
  Check(r.text:find("control state: eligible", 1, true), "the control's own state is listed: it is eligible, and still blocked")
  Check(r.text:find("evidence:", 1, true), "an evidence line")
  Same(r.eligibility.ok, true, "eligible by its own state while unreachable: the two are different questions")

  -- the same overlay does not block the other kind of input when it is click-disabled (hover is still taken)
  overlay:SetMouseClickEnabled(false)
  Same(Look().verdict, "reachable", "a click-disabled overlay lets clicks through")
  Same(Look({ kind = "hover" }).verdict, "ineligible", "(the button has no OnEnter, so hover is ineligible whatever lies over it)")
  add.scripts.OnEnter = function() end
  Same(Look({ kind = "hover" }).verdict, "blocked", "a click-disabled overlay still takes the pointer's motion")
  overlay:SetMouseClickEnabled(true)
  -- an overlay that propagates clicks hands them on
  overlay._propagate = true
  Same(Look().verdict, "reachable", "an overlay that propagates clicks does not block them")
  overlay._propagate = false
  -- a control that itself propagates clicks to what is under it still takes them: it is not excluded from the stack
  add._propagate = true
  overlay:Hide()
  Same(Look().verdict, "reachable", "a control that propagates clicks is still the frame under the pointer"); Same(Look().relation, "self")
  add._propagate = false; overlay:Show()
  -- an overlay with mouse off, hidden, or elsewhere is no blocker
  overlay:EnableMouse(false); Same(Look().verdict, "reachable", "mouse off: not a blocker"); overlay:EnableMouse(true)
  Same(Look().verdict, "blocked")
  overlay:Hide(); Same(Look().verdict, "reachable", "hidden: not a blocker (REMOVED: reachable again)"); overlay:Show()
  overlay._x = 600; Same(Look().verdict, "reachable", "beside the button: not a blocker"); overlay._x = 380
  -- below the button is not a blocker either
  overlay._strata = "MEDIUM"; Same(Look().verdict, "reachable", "a lower strata is under the button"); overlay._strata = "DIALOG"
  Same(Look().verdict, "blocked")
  -- the overlay's hit rectangle, not its frame, decides: insets that leave the button's centre uncovered
  overlay:SetHitRectInsets(150, 0, 0, 0)   -- hit x 530..580 only
  Same(Look().verdict, "reachable", "the overlay's insets leave the button's centre free")
  overlay:SetHitRectInsets(0, 0, 0, 0)
  Same(Look().verdict, "blocked")
  -- removal: a hidden then discarded overlay
  overlay:Hide()
  r = Look()
  Same(r.verdict, "reachable", "after removal"); Same(r.top.label, "AddButton")

  -- a point given by the caller
  r = Look({ point = { 410, 305 } })
  Same(r.verdict, "reachable"); Same(r.pointSource, "given")
  r = Look({ point = { 399, 315 } })
  Same(r.verdict, "outside"); Check(r.why:find("not over the control", 1, true), r.why)
end

---------------------------------------------------------------------------
-- 4. The button's own insets (the pointer in the painted area but outside the hit rectangle), parent/child, ties, clipping
---------------------------------------------------------------------------
do
  local w = World.New()
  local RC = Load(w)
  local win = w:Frame{ name = "Window", x = 0, y = 0, w = 1000, h = 800, strata = "HIGH", level = 5, mouse = true }
  local b = w:Frame{ type = "Button", name = "B", parent = win, x = 100, y = 100, w = 100, h = 40, level = 6, onClick = function() end }
  local function Look(target, opts)
    opts = opts or {}
    opts.collected = RC.Collect({ frames = w.frames })
    return RC.Analyze(target, opts)
  end
  b:SetHitRectInsets(0, 60, 0, 0)   -- only x 100..140 can be hit
  local r = Look(b, { point = { 180, 120 } })
  Same(r.verdict, "outside", r.text)
  Check(r.why:find("inside the frame but outside its hit rectangle", 1, true), "the inset is named as the cause: " .. r.why)
  Same(Look(b, { point = { 120, 120 } }).verdict, "reachable", "inside the hit rectangle")
  Same(Look(b).point[1], 120, "the default point is the centre of the HIT rectangle (x 100..140), not of the frame")
  b:SetHitRectInsets(0, 0, 0, 0)

  -- parent over child: the window at a higher level than its button hides it
  win:SetFrameLevel(9)
  r = Look(b)
  Same(r.verdict, "blocked", r.text); Same(r.relation, "parent"); Check(r.why:find("parent frame", 1, true), r.why)
  win:SetFrameLevel(5)
  Same(Look(b).verdict, "reachable")

  -- a child that takes the pointer from its button (a mouse-enabled picture on the button)
  local pic = w:Frame{ name = "Picture", parent = b, x = 100, y = 100, w = 100, h = 40, mouse = true }
  r = Look(b)
  Same(r.verdict, "blocked", r.text); Same(r.relation, "child"); Same(r.blocker.label, "Picture")
  Check(r.why:find("child frame takes the pointer", 1, true), r.why)
  pic:EnableMouse(false)
  Same(Look(b).verdict, "reachable", "a mouse-off child does not take it")
  -- a child over only part of the button: the centre of the button is free
  pic:EnableMouse(true); pic._x, pic._w = 100, 20
  Same(Look(b).verdict, "reachable", "the child covers the left fifth only")
  Same(Look(b, { point = { 105, 120 } }).verdict, "blocked", "but the pointer there is the child's")
  pic:Hide()

  -- ties: an unrelated frame with the same strata and level is reported ambiguous, never decided
  local rival = w:Frame{ name = "Rival", parent = nil, x = 90, y = 90, w = 200, h = 80, strata = "HIGH", level = 6, mouse = true }
  r = Look(b)
  Same(r.verdict, "ambiguous", r.text); Check(r.why:find("ties", 1, true) and r.tie.label == "Rival", r.why)
  rival._level = 7
  Same(Look(b).verdict, "blocked", "one level higher is a definite block")
  rival._level = 5
  Same(Look(b).verdict, "reachable", "one level lower is a definite pass")
  rival:Hide()
  -- a child at the same level as its parent is above it, not tied
  local kid = w:Frame{ type = "Button", name = "Kid", parent = b, x = 100, y = 100, w = 100, h = 40, level = 6, onClick = function() end }
  Same(Look(kid).verdict, "reachable", "equal level, child over parent: decided, not ambiguous")
  Same(Look(b).verdict, "blocked", "and the parent button is then under its child"); kid:Hide()

  -- clipping by a scroll frame: a row scrolled out of view cannot be reached where it would be
  local scroll = w:Frame{ type = "ScrollFrame", name = "List", parent = win, x = 400, y = 300, w = 200, h = 100 }
  local row = w:Frame{ type = "Button", name = "RowInside", parent = scroll, x = 400, y = 320, w = 200, h = 20, onClick = function() end }
  local out = w:Frame{ type = "Button", name = "RowScrolledOut", parent = scroll, x = 400, y = 150, w = 200, h = 20, onClick = function() end }
  Same(Look(row).verdict, "reachable", "a row inside the viewport")
  r = Look(out)
  Same(r.verdict, "clipped", r.text); Check(r.why:find("List", 1, true), r.why)
  -- a blocker that is clipped away does not block: an overlay row of the list, outside the viewport, over a button underneath
  local under = w:Frame{ type = "Button", name = "Under", parent = win, x = 400, y = 130, w = 100, h = 40, level = 6, onClick = function() end }
  local ghost = w:Frame{ name = "GhostRow", parent = scroll, x = 400, y = 120, w = 200, h = 60, level = 20, mouse = true }
  Same(Look(under).verdict, "reachable", "a row scrolled out of the viewport does not catch the pointer")
  ghost:Hide()
  -- clipsChildren behaves the same
  local clip = w:Frame{ name = "Clip", parent = win, x = 700, y = 300, w = 50, h = 50, clips = true }
  local inClip = w:Frame{ type = "Button", name = "Clipped", parent = clip, x = 700, y = 300, w = 200, h = 50, onClick = function() end }
  Same(Look(inClip, { point = { 800, 320 } }).verdict, "clipped")
  Same(Look(inClip, { point = { 710, 320 } }).verdict, "reachable")

  -- hidden controls and pooled rows: a hidden row is ineligible AND not collected as a pointer taker
  row:Hide()
  r = Look(row)
  Same(r.verdict, "ineligible"); Check(r.text:find("hidden", 1, true))
  local seen = {}
  for _, c in ipairs(RC.Collect({ frames = w.frames }).list) do seen[c.frame:GetName() or "?"] = true end
  Check(not seen.RowInside and seen.RowScrolledOut ~= nil, "a hidden pooled row is not among the frames that take the pointer")
  row:Show()

  -- a disabled button still takes the pointer: it blocks what is under it and is itself ineligible
  b:Disable()
  r = Look(b)
  Same(r.verdict, "ineligible"); Same(r.relation, "self", "it is still the topmost frame there")
  local below = w:Frame{ type = "Button", name = "BelowDisabled", parent = win, x = 100, y = 100, w = 100, h = 40, level = 3, onClick = function() end }
  r = Look(below)
  Same(r.verdict, "blocked", "under a disabled button is blocked"); Same(r.blocker.label, "B")
end

---------------------------------------------------------------------------
-- 5. Hover: the same geometry with motion instead of clicks
---------------------------------------------------------------------------
do
  local w = World.New()
  local RC = Load(w)
  local win = w:Frame{ name = "Window", x = 0, y = 0, w = 1000, h = 800, strata = "HIGH", level = 5, mouse = true }
  local row = w:Frame{ type = "Button", name = "Row", parent = win, x = 100, y = 100, w = 400, h = 30, level = 6, onClick = function() end, onEnter = function() end }
  local icon = w:Frame{ type = "Button", name = "Icon", parent = row, x = 104, y = 104, w = 22, h = 22, level = 7, onClick = function() end, onEnter = function() end }
  local function Look(t, o) o = o or {}; o.kind = "hover"; o.collected = RC.Collect({ frames = w.frames }); return RC.Analyze(t, o) end
  Same(Look(row).verdict, "reachable", "the row's centre is the row")
  local r = Look(row, { point = { 110, 115 } })
  Same(r.verdict, "blocked", "on the icon the row is not the frame under the pointer (the row must follow the child)")
  Same(r.relation, "child")
  -- the row's lit state is not the question here; a SELECTED row is as reachable as any (selection is painting, not input)
  row.selected = true
  Same(Look(row).verdict, "reachable", "a selected row is still hoverable")
  -- no OnEnter: ineligible for hover, though clicks are fine
  row.scripts.OnEnter = nil
  Same(Look(row).verdict, "ineligible"); Same(RC.Analyze(row, { collected = RC.Collect({ frames = w.frames }) }).verdict, "reachable")
end

---------------------------------------------------------------------------
-- 6. Names are safe to paste; the scan is bounded; the sample reads the client's own answer
---------------------------------------------------------------------------
do
  local w = World.New()
  local RC = Load(w, { UnitName = function() return "Zzchar" end, GetRealmName = function() return "Zzrealm" end, GetGuildInfo = function() return "Zzguild" end })
  local win = w:Frame{ name = "Window", x = 0, y = 0, w = 1000, h = 800, mouse = true }
  local named = w:Frame{ type = "Button", name = "ZzcharsButton_Zzrealm", parent = win, x = 0, y = 0, w = 100, h = 30, onClick = function() end }
  local d = RC.Describe(named)
  Check(not d.label:find("Zzchar") and not d.label:find("Zzrealm") and d.label:find("[private]", 1, true), "the player's name and realm are taken out: " .. d.label)
  Check(not d.chain:find("Zzchar"), "and out of the hierarchy line")
  Same(RC.Redact("Zzguild bank|Hitem:19019::::::|h[Thunderfury]|h |cff0070ddx|r\n"), "[private] bank[link] x ", "guild name, link, colour and control characters")
  Check(#RC.Redact(("x"):rep(500)) == 83, "cut at 80 and marked")
  -- an unnamed frame is its type; no text is ever read
  local anon = w:Frame{ type = "Button", parent = win, x = 0, y = 0, w = 10, h = 10 }
  Same(RC.Label(anon), "<Button>")
  Same(RC.Label(anon, { label = function() return "Add to crafting plan" end }), "Add to crafting plan", "a caller's label (the simulator uses it)")
  Same(RC.Label(anon, { label = function() error("x") end }), "<Button>", "a failing label function falls back")
  anon.GetText = function() error("the analysis must not read frame text") end
  RC.Describe(anon)

  -- the scan is bounded and says so; hidden frames are counted, not described
  local many = World.New()
  local RC2 = Load(many)
  local top = many:Frame{ name = "Top", x = 0, y = 0, w = 100, h = 100, mouse = true }
  for i = 1, 50 do many:Frame{ type = "Button", parent = top, x = 0, y = 0, w = 10, h = 10, shown = i % 2 == 0, onClick = function() end } end
  local sc = RC2.Collect({ frames = many.frames, limit = 20 })
  Check(sc.truncated and sc.scanned == 20, "a limit of 20 stops at 20 and says it was cut: " .. sc.scanned)
  sc = RC2.Collect({ frames = many.frames })
  Check(not sc.truncated and sc.scanned == 51 and #sc.list == 26 and sc.hidden == 25, ("51 scanned, 26 take the pointer, 25 hidden: %d %d %d"):format(sc.scanned, #sc.list, sc.hidden))
  local yields = 0
  RC2.Collect({ frames = many.frames, chunk = 10, yield = function() yields = yields + 1 end })
  Same(yields, 5, "it yields every chunk of frames (51 / 10)")
  -- a time budget: every frame costs a virtual millisecond (its first question advances the clock), so the yields follow the clock, not a count
  do
    local now, wrapped = 0, many.frames
    for _, fr in ipairs(wrapped) do
      local ask = fr.IsMouseEnabled
      fr.IsMouseEnabled = function(...) now = now + 0.001; return ask(...) end
    end
    local clock = function() return now end
    local spans, last, count = {}, nil, 0
    sc = RC2.Collect({ frames = wrapped, clock = clock, budget = 0.004, check = 1, yield = function() count = count + 1; spans[#spans + 1] = now - (last or 0); last = now; now = now + 5 end })
    -- (the 5 s the yield adds stands for the frames the runner lets pass; Collect must not count it as scan time)
    Check(not sc.truncated and sc.scanned == 51, "the walk still covers every frame")
    Same(sc.yields, count, "it counts its yields")
    Check(count >= 10 and count <= 14, "about one yield per 4 ms of scanning (51 frames at 1 ms): " .. count)
    Check(sc.longest <= 0.0051, "no stretch between yields is longer than the budget plus one frame: " .. sc.longest)
    Check(math.abs(sc.work - 0.051) < 0.0011, "the scan time excludes the waiting at yields: " .. sc.work)
    -- a clock that never moves cannot hold a yield back for ever: the frame count still bounds a stretch
    count = 0
    RC2.Collect({ frames = wrapped, clock = function() return 1 end, budget = 0.004, check = 4, chunk = 10, yield = function() count = count + 1 end })
    Same(count, 5, "a stopped clock still yields every chunk of frames")
    -- no yield function and a clock: nothing to call, nothing raised
    sc = RC2.Collect({ frames = wrapped, clock = clock })
    Same(sc.yields, 0); Check(sc.scanned == 51)
    -- the clock is read every `check` frames, not on every one (it must cost next to nothing)
    local reads = 0
    RC2.Collect({ frames = wrapped, clock = function() reads = reads + 1; return now end, budget = 1000, check = 32, yield = function() end })
    Check(reads <= 5, "a clock read every 32 frames: " .. reads)
  end
  local viaEnum = Load(many)
  sc = viaEnum.Collect({})
  Same(sc.scanned, 51, "EnumerateFrames is used when no list is given"); Check(not sc.truncated)
  sc = viaEnum.Collect({ limit = 12 })
  Check(sc.truncated and sc.scanned == 12, "the EnumerateFrames walk is bounded too, and says so: " .. sc.scanned)

  -- the sample: the client's own list, bounded, with the pointer
  w:Cursor(50, 15)
  local s = RC.Sample()
  Check(s.ok and s.count >= 2, "the sample reads GetMouseFoci")
  Same(s.x, 50); Same(s.y, 15)
  Check(not s.foci[1].desc.label:find("Zzchar"), "and the sample's names are redacted too")
  Check(s.foci[1].frame == named, "topmost first")
  local capped = RC.Sample({ max = 1 })
  Same(#capped.foci, 1); Check(capped.truncated, "bounded to max and says so")
  local none = Load(nil)
  Check(none.Sample().ok == false and none.Sample().why:find("not available", 1, true), "without GetMouseFoci it says so")
  local broken = Load(nil, { GetMouseFoci = function() error("x") end })
  Check(broken.Sample().ok == false, "a failing GetMouseFoci is reported, not raised")
end

print("PASSED test_reach")
