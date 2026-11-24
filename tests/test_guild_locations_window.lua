-- The on-demand Guild Locations diagnostic view: inspection sends nothing, only the explicit peer-test action starts
-- networking, automatic results update the open report, and closing cancels work and clears transient identity/text.
-- The diagnostic engine and UI rendering are recording stand-ins; real message delivery and pixels are not established.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Alice Stone", { "!!!TwichUI" })
local made, buttons, listeners, calls = {}, {}, {}, { report = 0, start = 0, stop = 0, inspect = 0, self = 0, markerStop = 0 }
local function Rec(name)
  local o = { name = name, shown = false, text = "", scripts = {}, hooks = {}, enabled = true }
  setmetatable(o, { __index = function(_, k)
    if k == "Show" or k == "Hide" then return function(s)
      local show = k == "Show"
      local was = s.shown; s.shown = show
      if was ~= show then
        local event = show and "OnShow" or "OnHide"
        if s.scripts[event] then s.scripts[event](s) end
        for _, h in ipairs(s.hooks[event] or {}) do h(s) end
      end
    end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "SetScript" then return function(s, event, fn) s.scripts[event] = fn end end
    if k == "HookScript" then return function(s, event, fn)
      s.hooks[event] = s.hooks[event] or {}; table.insert(s.hooks[event], fn)
    end end
    if k == "SetText" then return function(s, text) s.text = text or "" end end
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetEnabled" then return function(s, on) s.enabled = on end end
    if k == "SetHeight" then return function(s, height) s.height = height end end
    if k == "SetFocus" then return function(s) s.focused = true end end
    if k == "ClearFocus" then return function(s) s.focused = false end end
    if k == "HighlightText" then return function(s) s.highlighted = true end end
    if k == "GetWidth" or k == "GetHeight" then return function() return 100 end end
    if k == "CreateTexture" or k == "CreateFontString" then return function() return Rec() end end
    return function() end
  end })
  made[#made + 1] = o
  return o
end

c.CreateFrame = function(kind, name)
  local o = Rec(name)
  o.kind = kind
  if name then c[name] = o end
  return o
end
c.UIParent, c.UISpecialFrames = Rec(), {}
local R = c.TwichUI
local running, revision = false, 1
local function Changed() for _, fn in ipairs(listeners) do fn() end end
R.GuildLoc = { Diagnostics = {
  OnChange = function(fn) listeners[#listeners + 1] = fn end,
  IsRunning = function() return running end,
  Report = function(name) calls.report = calls.report + 1; return "Report for " .. name .. "\nrevision " .. revision end,
  Inspect = function(name) calls.inspect = calls.inspect + 1; calls.inspected = name; Changed() end,
  Start = function(name)
    calls.start = calls.start + 1
    if name == "" then return false, "missing-name" end
    calls.target = name; running = true; Changed(); return true
  end,
  Stop = function() calls.stop = calls.stop + 1; running = false; Changed() end,
  Describe = function(code) return "Reason: " .. tostring(code) end,
  SelfTest = function() calls.self = calls.self + 1; return "SYNTHETIC local self-test: passed" end,
}, Map = { StopSelfTest = function() calls.markerStop = calls.markerStop + 1 end } }
R.Print = function() end
local chunk = assert(loadfile(ROOT .. "guildloc/Window.lua")); setfenv(chunk, c); chunk()
local W = R.GuildLoc.Window
assert(not W.IsShown() and W.Text() == nil and #listeners == 1, "one callback and no UI while never opened")
assert(c.TwichUIGuildLocationsDiagnostics == nil and calls.start == 0 and calls.report == 0)
assert(W.Show() == false, "missing style helpers fail without building half a window")

local styled = { shell = 0, craft = 0, fit = 0 }
R.FitToScreen = function() styled.fit = styled.fit + 1 end
R.Look = { Text = function() return Rec() end, Well = function() end, ScrollBar = function() end,
  EditBox = function() local o = Rec(); o.member = true; return o end }
R.FrameLook = {
  Ready = function() return true end,
  ContentInsets = function() return 12, 12, 12, 13 end,
  Shell = function() styled.shell = styled.shell + 1; return { Header = function() return Rec() end } end,
  FadeIn = function() end,
  Close = function(_, close) local o = Rec(); buttons.Close = { click = close }; return o end,
  Button = function(_, label, _, _, click)
    local o = Rec(label); o.click = click; buttons[label] = o; return o
  end,
}
R.CraftLook = { Window = function() styled.craft = styled.craft + 1 end }

assert(W.Show("Bob Reeve") and W.IsShown())
local f = c.TwichUIGuildLocationsDiagnostics
assert(styled.shell == 1 and styled.craft == 1 and styled.fit == 1, "shared shell, crafted look and screen fit")
assert(calls.start == 0 and calls.inspect == 0 and W.Text():find("Bob Reeve", 1, true), "opening is read-only")
assert(f.edit:GetText() == W.Text() and f.member:GetText() == "Bob Reeve")
assert(f.edit.height and f.edit.height > 0 and f.measure:GetText() == W.Text(), "the report scroll child has explicit text bounds")
assert(not f.stop.enabled and f.test.enabled, "only applicable peer controls are enabled")
assert(f.scripts.OnUpdate == nil, "no frame loop")

f.member:SetText("  Cara Dunn  ")
buttons["Inspect / refresh"].click()
assert(calls.inspected == "Cara Dunn" and calls.inspect == 1 and calls.start == 0, "only explicit inspection starts the local watch")
assert(W.Text():find("Cara Dunn", 1, true))
buttons["Local self-test"].click()
assert(calls.self == 1 and calls.start == 0 and W.Text():find("SYNTHETIC", 1, true), "self-test stays local")
buttons["Test with member"].click()
assert(calls.start == 1 and calls.target == "Cara Dunn" and running, "network request only from the test button")
assert(f.stop.enabled and not f.test.enabled)
revision = 2; Changed()
assert(W.Text():find("revision 2", 1, true), "automatic peer-result changes redraw an open report")
buttons.Stop.click()
assert(not running and W.Text():find("Peer test stopped.", 1, true))

-- Read-only report and Escape leave no edit focus; input Enter is an explicit inspection.
local report = W.Text()
f.edit:SetText("typed over"); f.edit.scripts.OnTextChanged(f.edit, true)
assert(f.edit:GetText() == report and f.edit.highlighted)
f.edit.focused = true; f.edit.scripts.OnEscapePressed(f.edit)
assert(not f.edit.focused)
f.member:SetText("Bob Reeve"); f.member.scripts.OnEnterPressed(f.member)
assert(calls.inspected == "Bob Reeve" and calls.start == 1)
f.member:SetText(""); buttons["Test with member"].click()
assert(W.Text():find("Reason: missing-name", 1, true), "rejected starts explain the reason")

local frames = #made
for _ = 1, 5 do W.Show() end
assert(#made == frames and #listeners == 1 and #c.UISpecialFrames == 1, "reopening never stacks frames or listeners")
assert(c.UISpecialFrames[1] == "TwichUIGuildLocationsDiagnostics", "Escape can close the named window")
buttons.Close.click()
assert(not W.IsShown() and W.Text() == nil and f.member:GetText() == "" and f.edit:GetText() == "", "closing drops member and report")
assert(f.measure:GetText() == "", "closing also clears the hidden text measurement")
assert(not running and calls.markerStop == 1, "closing cancels the peer test and local preview")
local reports = calls.report
Changed()
assert(calls.report == reports and W.Text() == nil, "late callbacks after close do not rebuild a report")
assert(W.Show() and not W.Text():find("Cara Dunn", 1, true) and not W.Text():find("SYNTHETIC", 1, true), "new open has no earlier identity or test result")
W.Hide()
print("GUILD LOCATIONS WINDOW TESTS PASSED")
