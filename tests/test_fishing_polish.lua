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

-- 5. The minimap is concealed (a real Hide: alpha can't remove the engine's blips), and put back
local function Protected(m, W)
  -- the real minimap is protected in combat: its Show and Hide refuse then
  local show, hide = m.Show, m.Hide
  m.IsProtected = function() return true end
  m.Show = function(self) assert(not W.combat, "Minimap:Show in combat"); show(self) end
  m.Hide = function(self) assert(not W.combat, "Minimap:Hide in combat"); hide(self) end
end
do
  local c, W, F, EUI = Fresh()
  local map, child = EUI.map, Make(c, W, nil, EUI.map)
  Protected(map, W)
  local x0, y0 = map:GetPoint(1)
  Toggle(c, W)
  Check(not map:IsShown() and not W.UI.Visible(child), "immersive: the minimap and everything on it is hidden, not just faded")
  Check(F.Conceal.State().concealed, "and it says so")
  -- reveal key
  c.TwichUI.Fishing.Present.Reveal(true); Settle(W)
  Check(map:IsShown(), "reveal held: the minimap is back")
  c.TwichUI.Fishing.Present.Reveal(false); Settle(W)
  Check(not map:IsShown(), "released: concealed again")
  -- EllesmereUI shows it again (a layout pass): it is hidden again at once, and wants to be shown after
  map:Show()
  Check(not map:IsShown() and F.Conceal.State().ownerWants, "the owner's Show while concealed is covered")
  Toggle(c, W)
  Check(map:IsShown() and not F.Conceal.State().concealed, "leaving: the minimap is back")
  Check(select(1, map:GetPoint(1)) == x0 and #map.points >= 0, "no anchor was touched")
end
do
  -- a map its owner hides stays hidden after; a map its owner hides meanwhile stays hidden
  local c, W, F, EUI = Fresh()
  local map = EUI.map
  map:Hide()
  Toggle(c, W); Toggle(c, W)
  Check(not map:IsShown(), "a map hidden by its owner is never shown by Fishing Mode")
  map:Show()
  Toggle(c, W)
  map:Hide()           -- the owner's visibility rule hides it while concealed
  Toggle(c, W)
  Check(not map:IsShown(), "the owner's own Hide while concealed is respected on the way back")
end
do
  -- combat: concealing never happens in combat; leaving in combat waits for the end of combat on a protected map
  local c, W, F, EUI = Fresh()
  local map = EUI.map
  Protected(map, W)
  Toggle(c, W)
  Check(not map:IsShown(), "concealed")
  W.combat = true
  c.FireEvent("PLAYER_REGEN_DISABLED"); Settle(W)
  Check(not F.Present.On(), "combat ended Fishing Mode")
  Check(F.Conceal.State().waiting and #W.faults == 0, "the protected map is not touched in combat; the restoration waits: " .. table.concat(W.faults, "|"))
  W.combat = false
  c.FireEvent("PLAYER_REGEN_ENABLED"); Settle(W)
  Check(map:IsShown() and not F.Conceal.State().waiting, "and the map is back when combat ends")
  W.combat = true
  Toggle(c, W)
  Check(map:IsShown() and not F.Conceal.State().concealed, "Fishing Mode can't start in combat: the map is untouched")
  W.combat = false
end
do
  -- an unprotected map is restored at once even in combat
  local c, W, F, EUI = Fresh()
  Toggle(c, W)
  W.combat = true
  c.FireEvent("PLAYER_REGEN_DISABLED"); Settle(W)
  Check(EUI.map:IsShown(), "unprotected map: back at once on combat")
  W.combat = false
end
do
  -- repeated cycles, recovery, and a reload
  local c, W, F, EUI = Fresh()
  local map = EUI.map
  local hooks = 0
  for _ = 1, 6 do Toggle(c, W); Check(not map:IsShown(), "cycle: concealed"); Toggle(c, W); Check(map:IsShown(), "cycle: back") end
  Toggle(c, W)
  c.TwichUI.RunCommand("fish recover"); Settle(W)
  Check(map:IsShown() and not F.Conceal.State().concealed, "/tui fish recover brings the map back")
  Check(F.Conceal.State().refused == 0 and #W.faults == 0, "nothing refused")
  local c2, W2, F2, EUI2 = Fresh()
  Check(EUI2.map:IsShown() and not F2.Conceal.State().concealed, "after a reload the map is simply there, and nothing is saved")
  Check(c2.TwichUIFishingDB.client.minimap == nil, "no record of it is kept")
end
do
  -- the switch, other presentations, absent map
  local c, W, F, EUI = Fresh()
  F.Present.Configure("fade.minimap", false)
  Toggle(c, W)
  Check(EUI.map:IsShown(), "minimap switch off: the map stays")
  Toggle(c, W)
  F.Present.Configure("fade.minimap", true)
  c.TwichUI.RunCommand("fish mode compact"); Settle(W)
  c.TwichUI.RunCommand("fish mode"); Settle(W)
  Check(EUI.map:IsShown(), "compact: the minimap is unchanged")
  c.TwichUI.RunCommand("fish mode"); Settle(W)
  c.TwichUI.RunCommand("fish mode classic"); Settle(W)
  c.TwichUI.RunCommand("fish mode"); Settle(W)
  Check(EUI.map:IsShown() and #W.faults == 0, "classic: the minimap is unchanged")
  local c3, W3, F3 = Fresh({ absent = true })
  Toggle(c3, W3)
  Check(not F3.Conceal.State().present and not F3.Conceal.State().concealed and #W3.faults == 0, "no minimap at all: nothing happens, no error")
  Toggle(c3, W3)
end

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED test_fishing_polish")
