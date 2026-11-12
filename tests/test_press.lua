-- Press (tests/press.lua): the opt-in helper that checks a control may receive a click before it runs the control's handler.
-- OFFLINE: it proves what the helper refuses and runs, on stand-in frames. It is not evidence about the game's input.
dofile(TESTS .. "mi_mock.lua")
local Press = dofile(TESTS .. "press.lua")

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local function Make(kind, parent, name)
  local f = Press.Instrument(MIFake(kind, parent), name)
  return f
end
local function Reasons(r) local t = {} for _, x in ipairs(r.reasons) do t[#t + 1] = x end table.sort(t) return table.concat(t, ",") end

-- a window with a button whose handler counts calls and keeps what it was given
local win = Make("Frame", nil, "Win")
local btn = Make("Button", win, "Add")
local calls, got = 0, nil
btn:SetScript("OnClick", function(self, button, down) calls = calls + 1; got = { self = self, button = button, down = down } end)

---------------------------------------------------------------------------
-- A valid press runs the real handler, with the control and the click arguments
---------------------------------------------------------------------------
local r = Press(btn)
Check(r.invoked and r.outcome == "invoked" and #r.reasons == 0, r.text)
Same(calls, 1, "the handler ran once")
Check(got.self == btn, "with the control itself first")
Same(got.button, "LeftButton"); Same(got.down, false)
Check(r.evidence:find("handler invoked (offline)", 1, true) and r.evidence:find("geometry not checked", 1, true) and r.evidence:find("not confirmed under a real pointer", 1, true),
  "the evidence label says what it is and is not: " .. r.evidence)
Same(Press.Click(btn, { button = "RightButton", down = true }).invoked, true)
Same(got.button, "RightButton", "the button identity is passed on"); Same(got.down, true, "and the direction")
Same(Press.Must(btn).calls[1], "OnClick")

-- the game's order: PreClick, OnClick, PostClick, and a hook runs after the script it hooks
local order = {}
local b2 = Make("Button", win, "Ordered")
b2:SetScript("PreClick", function() order[#order + 1] = "pre" end)
b2:SetScript("OnClick", function() order[#order + 1] = "click" end)
b2:HookScript("OnClick", function() order[#order + 1] = "hook" end)
b2:SetScript("PostClick", function() order[#order + 1] = "post" end)
Press(b2)
Same(table.concat(order, ","), "pre,click,hook,post", "PreClick, the script, its hook, PostClick")
-- a control with only a hook (no script of its own) still has a handler
local b3 = Make("Button", win, "HookOnly")
local hooked = 0
b3:HookScript("OnClick", function() hooked = hooked + 1 end)
Check(Press(b3).invoked and hooked == 1, "a hook alone counts as a handler")

---------------------------------------------------------------------------
-- Every refusal: the handler is not run, and the outcome says why
---------------------------------------------------------------------------
local function Refused(frame, codes, what)
  local before = calls
  local res = Press(frame)
  Check(not res.invoked and res.outcome == "refused", what .. ": it must refuse (" .. res.text .. ")")
  Same(Reasons(res), codes, what)
  Same(calls, before, what .. ": the handler was not run")
  Check(res.text:find("REFUSED", 1, true) and res.evidence:find("refused", 1, true), what .. ": the text says refused")
  return res
end

btn:Hide()
Check(Refused(btn, "hidden", "hidden frame").text:find("hidden", 1, true))
btn:Show()
win:Hide()
local res = Refused(btn, "ancestor-hidden", "hidden ancestor")
Check(res.text:find("Win", 1, true), "it names the hidden ancestor: " .. res.text)
win:Show()
btn:SetEnabled(false); Refused(btn, "disabled", "disabled by SetEnabled")
btn:SetEnabled(true)
btn:Disable(); Refused(btn, "disabled", "disabled by Disable"); btn:Enable()
btn:EnableMouse(false); Refused(btn, "mouse-disabled", "mouse input off"); btn:EnableMouse(true)
btn:SetMouseClickEnabled(false); Refused(btn, "click-disabled", "mouse clicks off"); btn:SetMouseClickEnabled(true)
local saved = btn:GetScript("OnClick")
btn:SetScript("OnClick", nil); Refused(btn, "no-click-handler", "no handler"); btn:SetScript("OnClick", saved)
Check(Press(btn).invoked, "and when everything is restored it presses again")

-- a Frame (not a Button) does not take the mouse by default, and is pressed through OnMouseUp, not OnClick
local plain = Make("Frame", win, "Plain")
local up = 0
plain:SetScript("OnMouseUp", function() up = up + 1 end)
Refused(plain, "mouse-disabled", "a plain Frame does not take the mouse until EnableMouse(true)")
plain:EnableMouse(true)
Check(Press(plain).invoked and up == 1, "a mouse-enabled Frame is pressed through OnMouseUp")
Same(Press(plain).calls[1], "OnMouseUp")
Check(Press.Click(plain, { script = "OnMouseUp" }).invoked)

-- several reasons at once
btn:Hide(); btn:Disable(); btn:EnableMouse(false)
Same(Reasons(Press(btn)), "disabled,hidden,mouse-disabled", "every reason, not the first")
btn:Show(); btn:Enable(); btn:EnableMouse(true)

---------------------------------------------------------------------------
-- The stand-in's silence is not success
---------------------------------------------------------------------------
local lazy = MIFake("Button")   -- not instrumented: IsMouseEnabled and the rest answer nothing
lazy:SetScript("OnClick", function() calls = calls + 1 end)
local before = calls
res = Press(lazy)
Check(not res.invoked and Reasons(res):find("unknown", 1, true), "an un-instrumented MIFake is refused as unknown: " .. res.text)
Same(calls, before, "its handler did not run")
Check(res.text:find("unknown", 1, true) and res.text:find("IsMouseEnabled", 1, true), "and the text says which question had no answer: " .. res.text)
Check(not pcall(Press.Must, lazy), "Must raises for it")
local ok, err = pcall(Press.Must, lazy)
Check(not ok and tostring(err):find("REFUSED", 1, true), "with the explanation: " .. tostring(err))
-- a frame whose OnClick exists on a table that is not a frame at all
Check(not Press({ GetScript = function() return function() end end }).invoked, "a bare table with a script is not a control")
Check(not Press(nil).invoked, "nil is not a control")

---------------------------------------------------------------------------
-- Hover
---------------------------------------------------------------------------
local row = Make("Button", win, "Row")
local entered = 0
row:SetScript("OnEnter", function() entered = entered + 1 end)
Check(Press.Hover(row).invoked and entered == 1, "a row with OnEnter is hovered")
row:SetMouseMotionEnabled(false)
Check(not Press.Hover(row).invoked and Reasons(Press.Hover(row)) == "motion-disabled" and entered == 1, "motion off: refused, OnEnter not run")
row:SetMouseMotionEnabled(true)
row:SetScript("OnEnter", nil)
Same(Reasons(Press.Hover(row)), "no-enter-handler")
-- clicks off does not stop hover
row:SetScript("OnEnter", function() entered = entered + 1 end); row:SetMouseClickEnabled(false)
Check(Press.Hover(row).invoked, "click-disabled still hovers")

-- the helper is opt-in: loading it changed nothing in MIFake itself
local fresh = MIFake("Button")
Check(rawget(fresh, "IsMouseClickEnabled") == nil and fresh.mouseClick == nil, "an un-instrumented MIFake is exactly as before")
print("PASSED test_press")
