-- A scripted fishing scene for tools/render_fishing_hud.py: TwichUI Fishing's real code in the simulated client
-- (tests/fishing_mock.lua, tests/ui_widgets.lua), driven through Stage 1 like a player would (casts, catches, a clam opened
-- by the key), then the resolved layout of everything Fishing Mode draws is written as JSON. Not a test: a capture source.
-- The item names and qualities are the scene's; the game would give its own. The session's start is moved back so the
-- figures read like a 42-minute session.
--
--   lua5.1 -e '...ROOT/TESTS...' fishing_capture.lua <out.json> <scene>
--   scene: immersive (default), compact, castbar
dofile(TESTS .. "fishing_mock.lua")
local out, scene = arg and arg[1] or "capture.json", arg and arg[2] or "immersive"
local KEY = "CLICK TwichUIFishingButton:LeftButton"
local TROUT, SAGE, CATFISH = 6291, 6303, 6299
local NAMES = {
  [TROUT] = { "Raw Mithril Head Trout", 1, "Interface\\Icons\\fish_blue" },
  [SAGE] = { "Raw Greater Sagefish", 1, "Interface\\Icons\\fish_silver" },
  [CATFISH] = { "Raw Bristle Whisker Catfish", 1, "Interface\\Icons\\fish_brown" },
  [PEARL] = { "Golden Pearl", 2, "Interface\\Icons\\pearl" },
  [CLAMMEAT] = { "Tangy Clam Meat", 1, "Interface\\Icons\\clam_meat" },
  [CLAM] = { "Small Barnacled Clam", 1, "Interface\\Icons\\clam" },
  [BIGCLAM] = { "Big-mouth Clam", 1, "Interface\\Icons\\clam" },
}
local c, W = FishingClient({ names = NAMES })
W.Camera()
c.ITEM_QUALITY_COLORS = { [2] = { hex = "|cff1eff00" }, [3] = { hex = "|cff0070dd" } }
c.UnitChannelInfo = function(unit)
  if unit ~= "player" or not W.channel then return nil end
  return W.channel[1], W.channel[1], 1, W.lineStart * 1000, (W.lineStart + 30) * 1000, false, false, W.channel[2]
end
local start = W.StartLine
W.StartLine = function(id) W.lineStart = W.clock - (W.staged or 0); start(id) end
W.bound.F = KEY
W.bound["SHIFT-F"] = "TWICHUI_FISHING_MODE"
W.bound.R = "TWICHUI_FISHING_REVEAL"
c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
local F = c.TwichUI.Fishing
if scene == "compact" then F.Store.Set("present.mode", "compact") end
W.Give(POLE); W.Give(LURE50, 1)
W.Advance(1.2); W.Key("F"); W.Advance(1.2); W.Key("F")   -- the key equips the pole, then puts the lure on

local function Catch(items) W.Advance(1.2); W.Key("F"); W.catch = items; W.Interact(); W.Advance(0.05) end
for _ = 1, 12 do Catch({ { TROUT, 2 } }) end
for _ = 1, 9 do Catch({ { SAGE, 2 } }) end
for _ = 1, 6 do Catch({ { CATFISH, 2 } }) end
W.bite = false
for _ = 1, 8 do W.Advance(1.2); W.Key("F"); W.Interact(); W.Advance(2) end   -- reeled too early: nothing on the line
W.bite = true
Catch({ { CLAM, 1 } })
W.Advance(1.2); W.Key("F"); W.Advance(3)           -- the key opens the clam: a pearl and clam meat
for _ = 1, 4 do Catch({ { CLAM, 1 } }); W.Advance(1.2); W.Key("F"); W.Advance(3) end
W.Frames(12)                                        -- earlier notices gone
local s = F.Session.Current()
s.start = s.start - 2537 + math.floor(F.Session.Elapsed())   -- reads as 42m 17s
-- the moment captured: a pearl just came out of a clam, a trout was just caught, and the next line is 60% through
F.Store.Set("toast.hold", 8)                        -- held a little longer than usual so both notices are in the frame
Catch({ { BIGCLAM, 1 } }); W.Frames(5)
W.Key("F"); W.Frames(2.2)                           -- the key opens it: two pearls
Catch({ { TROUT, 2 } })
W.staged = 16.5                                     -- the next line has been out a while (staged: the channel's times only)
W.Frames(1.2); W.Key("F")
W.Frames(0.6)
if scene == "castbar" then
  F.CatchList.Hide(); F.Toast.Clear()
end

-- plain JSON (numbers, strings, booleans, arrays, objects)
local function J(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" then return tostring(v) end
  if t == "number" then return (v ~= v or v == math.huge or v == -math.huge) and "null" or string.format("%.4f", v) end
  if t == "string" then return '"' .. v:gsub('[%c"\\]', function(ch) return string.format("\\u%04x", ch:byte()) end) .. '"' end
  local n = #v
  if n > 0 or next(v) == nil then
    local parts = {}
    for i = 1, n do parts[i] = J(v[i]) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local parts = {}
  for k, x in pairs(v) do parts[#parts + 1] = J(tostring(k)) .. ":" .. J(x) end
  return "{" .. table.concat(parts, ",") .. "}"
end
local f = assert(io.open(out, "w"))
f:write(J({ screen = { 1366, 768 }, scene = scene, regions = W.UI.Dump(),
  facts = { mode = F.Present.Mode(), on = F.Present.On(), castbar = F.CastBar.State(), toasts = #({ F.Toast.Active() })[1],
    zoom = W.camera.zoom, notes = #F.notes } }))
f:close()
print("wrote " .. out)
