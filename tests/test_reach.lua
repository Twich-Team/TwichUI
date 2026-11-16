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
  sec.IsMouseClickEnabled = function() return "SECRET" end
  e = RC2.Eligibility(sec)
  Check(not e.ok and e.text:find("IsMouseClickEnabled", 1, true), "a secret answer to the question under test is unknown: " .. e.text)
  local sec2 = Btn{ name = "Sec2" }
  sec2.IsMouseEnabled = function() return "SECRET" end
  Check(RC2.Eligibility(sec2).ok, "the aggregate is not the question for a click: a secret IsMouseEnabled does not decide it when the click flag answers")
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
      local ask = fr.IsMouseClickEnabled   -- the scan's first question (Entry asks click and motion, not the aggregate)
      fr.IsMouseClickEnabled = function(...) now = now + 0.001; return ask(...) end
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


---------------------------------------------------------------------------
-- 8. M6.1: what the real client showed (Forever 1.60.1 build 70888; docs/testlab.md "Verified Forever behaviour"). OFFLINE MODEL: these prove the
--    analysis classifies typed-in arrangements; the client's own behaviour is only what the Lab's reports recorded.
--    8a. click and motion are separate questions (IsMouseEnabled reads false for a click-only and for a motion-only frame)
--    8b. a propagating overlay is reachable through propagation; a blocking one blocks; an unreadable one is unknown
--    8c. geometry numbers are finite (a NaN that compares like a number is still not geometry)
---------------------------------------------------------------------------
do
  local function Setup(def)
    local w = World.New()
    local RC = Load(w)
    local win = w:Frame{ name = "Window", x = 100, y = 100, w = 800, h = 600, strata = "HIGH", level = 5 }
    def = def or {}
    def.type, def.name, def.parent, def.x, def.y, def.w, def.h, def.level = def.type or "Button", def.name or "Target", win, 400, 300, 120, 30, 6
    def.onClick = def.onClick or function() end
    def.onEnter = def.onEnter or function() end
    local target = w:Frame(def)
    local function Look(kind, opts)
      opts = opts or {}
      opts.kind = kind
      opts.collected = RC.Collect({ frames = w.frames })
      return RC.Analyze(target, opts)
    end
    local function Over(d)   -- a frame planted over the target's centre (460, 315)
      d.name, d.x, d.y, d.w, d.h = d.name or "Over", 380, 280, 200, 80
      d.strata = d.strata or "DIALOG"; d.level = d.level or 1
      return w:Frame(d)
    end
    return w, RC, target, Look, Over
  end

  -- 8a. click only: IsMouseEnabled reads false, clicks are on, motion is off
  do
    local _, RC, target, Look = Setup{ click = true, motion = false, agg = false }
    Same(target:IsMouseEnabled(), false, "(the stand-in reads mouse false)")
    local e = RC.Eligibility(target, "click")
    Check(e.ok, "a click-only control is eligible for a click although IsMouseEnabled is false: " .. e.text)
    Same(Look("click").verdict, "reachable", "and reachable by the pointer: " .. Look("click").text)
    e = RC.Eligibility(target, "hover")
    Same(Reasons(e), "motion-disabled", "for hover the reason is motion, not 'mouse off'")
    Same(Look("hover").verdict, "ineligible")
  end
  -- 8a. motion only: IsMouseEnabled false, clicks off, motion on
  do
    local _, RC, target, Look = Setup{ click = false, motion = true, agg = false }
    local e = RC.Eligibility(target, "hover")
    Check(e.ok, "a motion-only control is eligible for hover although IsMouseEnabled is false: " .. e.text)
    Same(Look("hover").verdict, "reachable", Look("hover").text)
    Same(Reasons(RC.Eligibility(target, "click")), "click-disabled", "for a click the reason is clicks off")
    Same(Look("click").verdict, "ineligible")
  end
  -- both off is "mouse off" as before; a frame with neither method uses the aggregate, conservatively
  do
    local _, RC, target = Setup{ click = false, motion = false }
    Same(Reasons(RC.Eligibility(target, "click")), "mouse-disabled"); Same(Reasons(RC.Eligibility(target, "hover")), "mouse-disabled")
    local w = World.New()
    local RCo = Load(w)
    local old = w:Frame{ type = "Button", name = "Old", x = 0, y = 0, w = 10, h = 10, noClickEnabled = true, onClick = function() end, onEnter = function() end }
    old.IsMouseMotionEnabled = nil
    Check(RCo.Eligibility(old, "click").ok and RCo.Eligibility(old, "click").state.fallback == "IsMouseEnabled", "no separate methods: the aggregate answers, and the report says so")
    old.EnableMouse(old, false)
    Same(Reasons(RCo.Eligibility(old, "click")), "mouse-disabled", "and off is off")
    old.IsMouseEnabled = function() return nil end
    Check(not RCo.Eligibility(old, "click").ok and RCo.Eligibility(old, "click").unknown[1]:find("IsMouseClickEnabled is missing", 1, true), "no methods and no aggregate answer: unknown, not eligible")
  end
  -- the overlays: mouse off, click off (motion on), click only
  do
    local w, _, target, Look, Over = Setup()
    local o = Over{ click = false, motion = false, agg = false }
    Same(Look("click").verdict, "reachable", "a mouse-disabled overlay does not block a click")
    Same(Look("hover").verdict, "reachable", "nor hover")
    o:SetMouseMotionEnabled(true)   -- click off, motion on, aggregate off: what the client reported
    o.IsMouseEnabled = function() return false end
    Same(Look("click").verdict, "reachable", "a click-disabled overlay lets the click through")
    Same(Look("hover").verdict, "blocked", "but still takes the pointer's motion (its IsMouseEnabled reads false)")
    Same(Look("hover").blocker.label, "Over")
    o:SetMouseMotionEnabled(false); o:SetMouseClickEnabled(true)   -- click only, aggregate still false
    Same(Look("click").verdict, "blocked", "a CLICK-ONLY overlay blocks a click though IsMouseEnabled reads false: " .. Look("click").text)
    Same(Look("hover").verdict, "reachable", "and not hover")
  end
  -- parent hidden, disabled button
  do
    local w, RC, target = Setup{ click = true, motion = false, agg = false }
    target:GetParent():Hide()
    Same(Reasons(RC.Eligibility(target, "click")), "ancestor-hidden", "a hidden parent makes even a click-only control ineligible")
    target:GetParent():Show(); target:Disable()
    Same(Reasons(RC.Eligibility(target, "click")), "disabled")
  end

  -- 8b. propagation: Reachable -> through propagation -> Reachable, for each way the client may expose the flag
  for _, api in ipairs({ "can", "get", "both" }) do
    local w, RC, target, Look, Over = Setup()
    local before = Look("click")
    Same(before.verdict, "reachable"); Check(before.via == nil, "no propagation involved at first")
    local o = Over{ propagateApi = api, mouse = true }
    local blocked = Look("click")
    Same(blocked.verdict, "blocked", api .. ": a mouse-enabled overlay that does not propagate blocks: " .. blocked.text)
    o._propagate = true
    local r = Look("click")
    Same(r.verdict, "reachable", api .. ": propagating overlay: " .. r.text)
    Same(r.via, "propagation", "and says it is through propagation"); Same(r.propagator.label, "Over")
    Check(r.text:find("REACHABLE (through propagation) click on Target", 1, true) and r.text:find("propagating frame: Over", 1, true), r.text)
    Same(r.eligibility.ok, true)
    -- GetMouseFoci would name the overlay first (the model of the pointer here does): the verdict is not taken from it
    w:Cursor(460, 315)
    Same(w:Foci()[1], o, "(the pointer's own stack lists the overlay first)")
    o:Hide()
    local after = Look("click")
    Same(after.verdict, "reachable"); Check(after.via == nil, "removed: reachable again, with no propagation involved")
  end
  -- a propagating overlay does not rescue a click that a NON-propagating frame takes
  do
    local _, _, target, Look, Over = Setup()
    Over{ name = "Passer", propagateApi = "can", mouse = true, propagate = true, level = 5 }
    Over{ name = "Blocker", propagateApi = "can", mouse = true, level = 3 }
    local r = Look("click")
    Same(r.verdict, "blocked", r.text); Same(r.blocker.label, "Blocker")
  end
  -- a propagating frame BELOW the target is just an ordinary lower frame
  do
    local _, _, target, Look, Over = Setup()
    Over{ name = "Under", propagateApi = "can", mouse = true, propagate = true, strata = "LOW" }
    local r = Look("click")
    Same(r.verdict, "reachable"); Check(r.via == nil, "a propagating frame under the control is not 'through propagation'")
  end
  -- hover is not affected by click propagation
  do
    local _, _, target, Look, Over = Setup()
    Over{ propagateApi = "can", mouse = true, propagate = true }
    Same(Look("hover").verdict, "blocked", "an overlay that propagates CLICKS still takes the pointer's motion")
  end
  -- more than one propagating frame is not assumed to pass the click
  do
    local _, _, target, Look, Over = Setup()
    Over{ name = "P1", propagateApi = "can", mouse = true, propagate = true }
    Over{ name = "P2", propagateApi = "can", mouse = true, propagate = true, level = 2 }
    local r = Look("click")
    Same(r.verdict, "unknown", r.text); Check(r.why:find("2 frames", 1, true) and r.via == nil, r.why)
  end
  -- propagation that cannot be read is UNKNOWN, never "does not propagate" (the old reader asked a method this client does not have)
  for _, api in ipairs({ "none", "odd" }) do
    local _, _, target, Look, Over = Setup()
    Over{ propagateApi = api, mouse = true }
    local r = Look("click")
    Same(r.verdict, "unknown", api .. ": " .. r.text)
    Check(r.why:find("cannot be read", 1, true) and r.blocker and r.blocker.label == "Over", r.why)
    Check(r.text:find("UNKNOWN click on Target", 1, true), r.text)
  end
  -- ... but an unreadable frame BELOW the control, or one that cannot take clicks, decides nothing
  do
    local _, _, target, Look, Over = Setup()
    Over{ propagateApi = "none", mouse = true, strata = "LOW" }
    Same(Look("click").verdict, "reachable", "an unreadable frame under the control: the control is on top")
    local _, _, target2, Look2, Over2 = Setup()
    Over2{ propagateApi = "none", click = false, motion = true }
    Same(Look2("click").verdict, "reachable", "an unreadable frame with clicks off cannot take the click")
  end
  -- equal strata and level stays ambiguous, for clicks and for a click-only pair
  do
    local w, RC, target, Look, Over = Setup()
    Over{ name = "Twin", type = "Button", strata = "HIGH", level = 6, parent = nil, mouse = true, propagateApi = "can", onClick = function() end }
    local r = Look("click")
    Same(r.verdict, "ambiguous", "an unrelated frame with the same strata and level: " .. r.text)
    local w2, RC2, t2, Look2, Over2 = Setup{ click = true, motion = false, agg = false }
    Over2{ name = "Twin", strata = "HIGH", level = 6, click = true, motion = false, agg = false, propagateApi = "can" }
    Same(Look2("click").verdict, "ambiguous", "also for click-only frames")
  end
  -- a propagating overlay AND a tied twin: reachable through propagation, and the tie is still said
  do
    local _, _, target, Look, Over = Setup()
    Over{ name = "Passer", propagateApi = "can", mouse = true, propagate = true }
    Over{ name = "Twin", type = "Button", strata = "HIGH", level = 6, parent = nil, mouse = true, propagateApi = "can", onClick = function() end }
    local r = Look("click")
    Same(r.verdict, "ambiguous", r.text); Same(r.via, "propagation")
    Check(r.why:find("also Twin ties", 1, true) or r.why:find("ties with it", 1, true), "the tie is in the reason: " .. r.why)
  end
  -- a client without the separate click / motion methods: the scan falls back to IsMouseEnabled (on takes both, off takes neither)
  do
    local w = World.New()
    local RC = Load(w)
    local on = w:Frame{ type = "Button", name = "On", x = 0, y = 0, w = 10, h = 10, onClick = function() end }
    local off = w:Frame{ type = "Button", name = "Off", x = 50, y = 0, w = 10, h = 10, mouse = false, onClick = function() end }
    for _, f in ipairs({ on, off }) do f.IsMouseClickEnabled, f.IsMouseMotionEnabled = nil, nil end
    local sc = RC.Collect({ frames = w.frames })
    Check(#sc.list == 1 and sc.list[1].frame == on and sc.list[1].click and sc.list[1].motion, "the aggregate decides when the separate methods are missing: " .. #sc.list)
  end
  -- hit-rectangle insets, positive and negative, on the overlay and on the control
  do
    local _, RC, target, Look, Over = Setup()
    local o = Over{ propagateApi = "can", mouse = true }
    o:SetHitRectInsets(150, 0, 0, 0)
    Same(Look("click").verdict, "reachable", "a positive inset on the overlay frees the centre")
    o:SetHitRectInsets(-50, -50, -50, -50)
    Same(Look("click").verdict, "blocked", "a negative inset extends the overlay")
    o:SetHitRectInsets(0, 0, 0, 0); o:Hide()
    target:SetHitRectInsets(-30, 0, 0, 0)
    Same(Look("click", { point = { 380, 315 } }).verdict, "reachable", "a negative inset on the control reaches past its frame")
    target:SetHitRectInsets(30, 0, 0, 0)
    Same(Look("click", { point = { 410, 315 } }).verdict, "outside", "a positive inset removes the strip")
  end

  -- 8c. geometry that is not finite
  do
    local RC = Load(nil)
    for _, v in ipairs({ 0, 1, -1, 1.5, 99999999999, 1e11, -1e11 }) do Check(RC.Num(v), "finite geometry: " .. tostring(v)) end
    for _, v in ipairs({ 0 / 0, -(0 / 0), math.huge, -math.huge, 1e12, -1e12, "5", true }) do Check(not RC.Num(v), "not geometry: " .. tostring(v)) end
    Check(not RC.Num(nil))
    -- a NaN that compares like an ordinary number (it prints "nan"; every comparison stays ordinary): still not geometry
    local RC2 = Load(nil, { tostring = function(v) if v == 7 then return "nan" end return tostring(v) end })
    Check(not RC2.Num(7), "a value that prints as nan is rejected before it is compared")
    Check(RC2.Num(8), "and an ordinary neighbour is accepted")
  end
end

print("PASSED test_reach")
