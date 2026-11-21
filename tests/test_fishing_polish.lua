-- TwichUI Fishing, Stage 2 polish: the damage meters, TwichUI's camping bar, the frames around the minimap, chat never fading,
-- and putting every one of them back. Against the EllesmereUI stand-in plus frames the polish pass names.
dofile(TESTS .. "fishing_mock.lua")
dofile(TESTS .. "ellesmere_mock.lua")
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local KEY = "CLICK TwichUIFishingButton:LeftButton"

local function Fresh(o)
  local c, W = FishingClient()
  local faults = {}
  c.geterrorhandler = function() return function(e) faults[#faults + 1] = tostring(e) end end
  W.faults = faults
  W.Camera()
  local EUI = EllesmereStandIn(c, W, o or {})
  W.bound.F = KEY
  c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
  return c, W, c.TwichUI.Fishing, EUI
end
local function Settle(W) W.Frames(1) end
local function Toggle(c, W) c.TwichUI.RunCommand("fish mode"); Settle(W) end
local function Make(c, W, name, parent) return W.UI.Create("Frame", name, parent or c.UIParent) end

-- 1. EllesmereUI's damage meters, other addons' meters, TwichUI's camping bar, companions, chat
do
  local c, W, F, EUI = Fresh()
  local dm1, dm2 = Make(c, W, "EllesmereUIDMFrame1"), Make(c, W, "EllesmereUIDMFrame2"); dm2:SetAlpha(0.8)
  local details = Make(c, W, "DetailsBaseFrame1")
  local camp = Make(c, W, nil)
  c.TwichUI.Camping = { Frame = function() return camp end }
  local rest = Make(c, W, "TwichUICampingRest"); rest:SetAlpha(0.7)
  local tracking, clock = Make(c, W, "MiniMapTracking"), Make(c, W, "GameTimeFrame")
  local chat, tab, dock = Make(c, W, "ChatFrame1"), Make(c, W, "ChatFrame1Tab"), Make(c, W, "GeneralDockManager")
  local host = Make(c, W, nil)
  EUI.map:SetParent(host)
  Check(F.Ellesmere.MinimapHost() == host, "the frame EllesmereUI parents the minimap to is found")
  Toggle(c, W)
  Check(dm1:GetAlpha() == 0 and dm2:GetAlpha() == 0, "EllesmereUI's damage meters fade")
  Check(details:GetAlpha() == 0, "Details' window fades too")
  Check(camp:GetAlpha() == 0 and rest:GetAlpha() == 0, "the camping bar and the sleeping bag bar fade")
  Check(tracking:GetAlpha() == 0 and clock:GetAlpha() == 0, "the pieces around the minimap fade")
  Check(host:GetAlpha() == 0 and EUI.map:GetAlpha() == 0, "the minimap, and the frame EllesmereUI keeps it in, fade")
  Check(chat:GetAlpha() == 1 and tab:GetAlpha() == 1 and dock:GetAlpha() == 1, "chat is never faded")
  local st = F.Fade.Status()
  for _, n in ipairs(st.names) do Check(not n:find("ChatFrame") and not n:find("GeneralDock"), "chat is not among the frames handled: " .. n) end
  Toggle(c, W)
  Check(dm1:GetAlpha() == 1 and dm2:GetAlpha() == 0.8 and details:GetAlpha() == 1, "the meters are back at their own alpha")
  Check(camp:GetAlpha() == 1 and rest:GetAlpha() == 0.7, "the camping bars are back at their own alpha")
  Check(host:GetAlpha() == 1 and tracking:GetAlpha() == 1 and EUI.map:GetAlpha() == 1, "and the minimap and its companions")
  Check(F.Fade.State() == "idle" and not F.Fade.Status().ticking, "nothing keeps running")
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, " | "))
end

-- 2. A frame that is above chat is never faded; chat can't be added by hand
do
  local c, W, F = Fresh()
  local chat = Make(c, W, "ChatFrame1")
  local parent = Make(c, W, "SomeChatHolder"); chat:SetParent(parent)
  Check(F.Fade.Why("SomeChatHolder", parent) == "chat", "a frame that holds chat is refused")
  Check(F.Fade.Why("ChatFrame3", Make(c, W, "ChatFrame3")) == "chat" and F.Fade.Why("EllesmereUIChatFrame", Make(c, W, "EllesmereUIChatFrame")) == "chat",
    "chat frames are refused by name")
  F.Present.Configure("fade.extra", { "ChatFrame1", "SomeChatHolder" })
  Toggle(c, W)
  Check(chat:GetAlpha() == 1 and parent:GetAlpha() == 1, "named by hand, chat still stays")
  Toggle(c, W)
end

-- 3. The switches: meters and TwichUI's bars each their own, camping bar absent is fine
do
  local c, W, F = Fresh()
  local dm = Make(c, W, "EllesmereUIDMFrame1")
  F.Present.Configure("fade.meters", false)
  Toggle(c, W)
  Check(dm:GetAlpha() == 1, "damage meters switched off: left alone")
  Toggle(c, W)
  F.Present.Configure("fade.meters", true)
  F.Present.Configure("fade.twichui", true)
  Toggle(c, W)
  Check(dm:GetAlpha() == 0 and #W.faults == 0, "no camping bar at all: no error")
  Toggle(c, W)
end

-- 4. Owners writing: the camping bar's own fade animation, the meter's own "show" write
do
  local c, W, F = Fresh()
  local dm = Make(c, W, "EllesmereUIDMFrame1")
  local camp = Make(c, W, nil)
  c.TwichUI.Camping = { Frame = function() return camp end }
  Toggle(c, W)
  dm:SetAlpha(1); camp:SetAlpha(1)
  Check(dm:GetAlpha() == 0 and camp:GetAlpha() == 0, "owners writing 1 are covered at once")
  Toggle(c, W)
  Check(dm:GetAlpha() == 1 and camp:GetAlpha() == 1, "and everything comes back")
  F.Fade.Restore(true, true)
  Check(dm:GetAlpha() == 1, "a forced recovery leaves them as they were")
end

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED test_fishing_polish")
