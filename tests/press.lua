-- Press: an OPT-IN test helper that asks whether a control could receive a click or a hover before it runs the control's real handler.
--
--   local Press = dofile(TESTS .. "press.lua")
--   Press.Instrument(frame, name)       -- once, when the test's CreateFrame makes a frame: it then records the mouse state the game keeps
--   local r = Press(button)             -- or Press.Click(button, { button = "RightButton", down = false })
--   Check(r.invoked, r.text)            -- a refusal explains itself; Press.Must(button) raises with that text instead
--   Press.Hover(row)                    -- the same for OnEnter (motion instead of clicks)
--
-- WHAT IT GUARANTEES (OFFLINE, against the stand-in's recorded state):
--   * a control that is hidden, under a hidden ancestor, disabled, mouse-off, click-off (where the stand-in models it) or without a handler
--     is REFUSED, and its handler is not run;
--   * a stand-in that does not model a question (an un-instrumented MIFake answers every capitalised method with nothing) is UNKNOWN and is
--     refused too, never taken as success;
--   * a control that passes has its REAL scripts run in the game's order (PreClick, OnClick, PostClick, each with the script set by the
--     code and the hooks added after it), with the control itself first and the click arguments (button, down) after it.
-- WHAT IT DOES NOT TELL YOU (the result says so in `evidence`):
--   * not where the pointer is: another frame over the control, a hit rectangle that excludes the centre, scroll clipping, strata and
--     frame levels are not looked at here (tools/simlab/ and the Lab's pointer probe do that, each with its own evidence label);
--   * not what the real client does with a disabled or hidden control. OBSERVED (Forever 1.60.1 build 70888, Test Lab api.click.programmatic): a
--     native Button's Click() ran its handlers when the button was HIDDEN or its mouse was OFF, and did not when it was DISABLED. Press is
--     deliberately stricter: it models a click a person could make, so a hidden or mouse-off control is still refused. Click() evidence and
--     pointer evidence are different things; neither is a substitute for the other;
--   * the evidence of a pass is "handler invoked (offline)", of a refusal "refused by the stand-in's recorded state".
-- Nothing is replaced globally: an uninstrumented test is exactly as before.
local Reach = (function()
  local env = setmetatable({ TwichUI = {} }, { __index = _G })
  local chunk = assert(loadfile(ROOT .. "../TwichUI_TestLab/Reach.lua"))
  setfenv(chunk, env)
  chunk("TwichUI_TestLab", {})
  return env.TwichUI.TestLab.Reach
end)()

local Press = { Reach = Reach }

Press.EVIDENCE = {
  invoked = "handler invoked (offline); eligible according to the stand-in's recorded state; geometry not checked; not confirmed under a real pointer",
  refused = "refused by the stand-in's recorded state (offline); the handler was not run",
}

local MOUSE_BY_DEFAULT = { Button = true, CheckButton = true, EditBox = true, Slider = true }
local BUTTONS = { Button = true, CheckButton = true }

-- Gives a freshly made MIFake frame the state a real frame keeps: its type and name, its parent, mouse click / motion, hit rectangle
-- insets, Enable / Disable. The defaults are the game's: a Button takes the mouse, a plain Frame does not until EnableMouse(true).
function Press.Instrument(f, name)
  local on = MOUSE_BY_DEFAULT[f.kind] or false
  f.mouseClick, f.mouseMotion, f.insets, f.frameName = on, on, { 0, 0, 0, 0 }, name
  f.GetName = function(s) return s.frameName end
  f.GetObjectType = function(s) return s.kind end
  f.GetParent = function(s) return s.parent end
  f.EnableMouse = function(s, v) s.mouseClick, s.mouseMotion = v ~= false, v ~= false end
  f.IsMouseEnabled = function(s) return s.mouseClick or s.mouseMotion end
  f.SetMouseClickEnabled = function(s, v) s.mouseClick = v ~= false end
  f.IsMouseClickEnabled = function(s) return s.mouseClick end
  f.SetMouseMotionEnabled = function(s, v) s.mouseMotion = v ~= false end
  f.IsMouseMotionEnabled = function(s) return s.mouseMotion end
  f.SetHitRectInsets = function(s, l, r, t, b) s.insets = { l, r, t, b } end
  f.GetHitRectInsets = function(s) return s.insets[1], s.insets[2], s.insets[3], s.insets[4] end
  f.Enable = function(s) s:SetEnabled(true) end
  f.Disable = function(s) s:SetEnabled(false) end
  return f
end

local function HasScript(f, name)
  local ok, fn = pcall(function() return f:GetScript(name) end)
  if ok and type(fn) == "function" then return true end
  local hooks = type(f) == "table" and rawget(f, "hooks")
  return type(hooks) == "table" and type(hooks[name]) == "table" and #hooks[name] > 0
end

local function LabelOf(f)
  local text = type(f) == "table" and type(f.text) == "table" and f.text.GetText and f.text:GetText()
  return Reach.Label(f, { label = (type(text) == "string" and text ~= "") and function() return text end or nil })
end

local function Codes(e)
  local out = {}
  for _, r in ipairs(e.reasons) do out[#out + 1] = r.code end
  for _ in ipairs(e.unknown) do out[#out + 1] = "unknown" end
  return out
end

local function Refuse(f, e, kind)
  return { target = LabelOf(f), kind = kind, invoked = false, outcome = "refused", reasons = Codes(e), eligibility = e,
    evidence = Press.EVIDENCE.refused, text = ("Press REFUSED on %s (%s): %s"):format(LabelOf(f), kind, e.text) }
end

local function Run(f, name, calls, ...)
  local main = f:GetScript(name)
  if type(main) == "function" then main(f, ...); calls[#calls + 1] = name end
  local hooks = type(f) == "table" and rawget(f, "hooks")
  for _, h in ipairs(type(hooks) == "table" and hooks[name] or {}) do h(f, ...); calls[#calls + 1] = name .. "(hook)" end
end

function Press.Click(f, opts)
  opts = opts or {}
  local button, down = opts.button or "LeftButton", opts.down == true
  local isButton = BUTTONS[type(f) == "table" and f.kind or ""]
  local script = opts.script or (not isButton and "OnMouseUp" or nil)   -- only a Button has OnClick; any other frame is pressed through OnMouseUp
  local e = Reach.Eligibility(f, "click", { hasScript = HasScript, script = script })
  if not e.ok then return Refuse(f, e, "click") end
  local calls = {}
  if script then
    Run(f, script, calls, button)
  else
    Run(f, "PreClick", calls, button, down)
    Run(f, "OnClick", calls, button, down)
    Run(f, "PostClick", calls, button, down)
  end
  return { target = LabelOf(f), kind = "click", invoked = true, outcome = "invoked", reasons = {}, calls = calls, button = button, down = down,
    eligibility = e, evidence = Press.EVIDENCE.invoked, text = ("Press invoked %s on %s"):format(table.concat(calls, ", "), LabelOf(f)) }
end

function Press.Hover(f, opts)
  local e = Reach.Eligibility(f, "hover", { hasScript = HasScript })
  if not e.ok then return Refuse(f, e, "hover") end
  local calls = {}
  Run(f, "OnEnter", calls, (opts or {}).motion ~= false)
  return { target = LabelOf(f), kind = "hover", invoked = true, outcome = "invoked", reasons = {}, calls = calls, eligibility = e,
    evidence = Press.EVIDENCE.invoked, text = ("Press invoked %s on %s"):format(table.concat(calls, ", "), LabelOf(f)) }
end

-- Press, but a refusal is an error carrying the explanation (for a test that has no use for the outcome table)
function Press.Must(f, opts)
  local r = Press.Click(f, opts)
  if not r.invoked then error(r.text, 2) end
  return r
end

setmetatable(Press, { __call = function(_, f, opts) return Press.Click(f, opts) end })
return Press
