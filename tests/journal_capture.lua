-- A scripted Journal scene for tools/render_fishing_journal.py: TwichUI Fishing's real Journal in the simulated client
-- (tests/fishing_mock.lua, tests/ui_widgets.lua) over records seeded to read like a long-time fisher's, then the resolved
-- layout is written as JSON. Not a test: a capture source. Names and icons are the scene's; the game gives its own.
--
--   lua5.1 -e '...ROOT/TESTS...' journal_capture.lua <out.json> <page> [select]
--   page: overview | sessions | collections | locations | treasures | summary | empty
dofile(TESTS .. "fishing_mock.lua")
local out, page = arg and arg[1] or "journal.json", arg and arg[2] or "overview"
local FISH = {
  { 6291, "Raw Mithril Head Trout", "fish_blue", 1247 }, { 6303, "Raw Greater Sagefish", "fish_silver", 988 },
  { 6299, "Raw Bristle Whisker Catfish", "fish_brown", 764 }, { 6361, "Raw Rainbow Fin Albacore", "fish_green", 612 },
  { 6362, "Raw Rockscale Cod", "fish_orange", 540 }, { 6358, "Oily Blackmouth", "fish_gold", 433 },
  { 6359, "Firefin Snapper", "fish_orange", 387 }, { 4603, "Raw Spotted Yellowtail", "fish_gold", 351 },
  { 13754, "Raw Glossy Mightfish", "fish_blue", 298 }, { 13756, "Raw Summer Bass", "fish_green", 250 },
  { 13758, "Raw Redgill", "fish_brown", 214 }, { 13759, "Raw Nightfin Snapper", "fish_silver", 176 },
  { 13760, "Raw Sunscale Salmon", "fish_orange", 133 }, { 13889, "Raw Whitescale Salmon", "fish_silver", 97 },
  { 8365, "Raw Mithril Head Trout", "fish_blue", 0 }, { 24001, "Giant Mottled Spotted Sagefish of the Southern Reaches", "fish_green", 61 },
}
local NAMES = {
  [PEARL] = { "Golden Pearl", 2, "Interface\\Icons\\pearl" }, [CLAMMEAT] = { "Tangy Clam Meat", 1, "Interface\\Icons\\clam_meat" },
  [CLAM] = { "Small Barnacled Clam", 1, "Interface\\Icons\\clam" }, [BIGCLAM] = { "Big-mouth Clam", 2, "Interface\\Icons\\clam" },
}
for _, f in ipairs(FISH) do NAMES[f[1]] = { f[2], 1, "Interface\\Icons\\" .. f[3] } end
local c, W = FishingClient({ names = NAMES })
c.ITEM_QUALITY_COLORS = { [2] = { hex = "|cff1eff00" }, [3] = { hex = "|cff0070dd" } }
c.UnitName = function() return "Thurin" end
W.bound.F = "CLICK TwichUIFishingButton:LeftButton"
c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
local F = c.TwichUI.Fishing
local UI = F.JournalUI

local ch = F.Store.Char()
if page ~= "empty" then
  ch.zoneNames = { [1434] = "Stranglethorn Vale", [15] = "Dustwallow Marsh", [26] = "The Hinterlands", [1444] = "Feralas", [1946] = "Zangarmarsh", [0] = nil }
  local species = {}
  local total, n = 0, 0
  for i, f in ipairs(FISH) do
    if f[4] > 0 then
      species[f[1]] = { q = f[4], c = math.floor(f[4] * 0.86), f = 1798000000 + i * 91000, l = 1800900000 - i * 17000 }
      total = total + f[4]; n = n + math.floor(f[4] * 0.86)
    end
  end
  species[CLAM] = { q = 41, c = 41, f = 1798500000, l = 1800800000 }
  ch.totals = { casts = 7400, catches = 6182, items = total + 41, failed = 31, interrupted = 22, missed = 1140, sessions = 188, seconds = 62 * 3600 + 14 * 60,
    line = 150000, first = 1797000000, last = 1800900000, species = species,
    zones = { [1434] = { casts = 2600, catches = 2210, items = 2900, line = 52000 }, [15] = { casts = 1800, catches = 1490, items = 1760, line = 36000 },
      [26] = { casts = 1500, catches = 1250, items = 1480, line = 30000 }, [1444] = { casts = 900, catches = 700, items = 760, line = 19000 },
      [1946] = { casts = 340, catches = 292, items = 320, line = 8000 }, [0] = { casts = 260, catches = 240, items = 150, line = 5000 } },
    containers = { [CLAM] = { caught = 41, opened = 36, failed = 2, got = { [PEARL] = 3, [CLAMMEAT] = 52 } },
      [BIGCLAM] = { caught = 9, opened = 7, failed = 0, got = { [PEARL] = 5, [CLAMMEAT] = 11 } } },
    contents = { [PEARL] = 8, [CLAMMEAT] = 63 } }
  -- where fish were caught since location recording began (the rest of each species is "earlier")
  local SVz, DMz, HLz, FRz, ZGz = 1434, 15, 26, 1444, 1946
  local function Z(q, c, d1, d2) return { q = q, c = c, f = 1799000000 + d1 * 86400, l = 1800800000 - d2 * 86400 } end
  ch.totals.spz = {
    [SVz] = { [6291] = Z(410, 360, 1, 2), [6303] = Z(220, 190, 3, 4), [6299] = Z(140, 120, 6, 1), [6358] = Z(95, 80, 2, 9), [24001] = Z(30, 26, 12, 3) },
    [DMz] = { [6291] = Z(300, 260, 4, 1), [6303] = Z(210, 180, 8, 2), [6361] = Z(150, 130, 10, 5) },
    [HLz] = { [6291] = Z(180, 160, 9, 3), [6362] = Z(120, 100, 11, 6), [6359] = Z(97, 80, 15, 8), [6303] = Z(60, 50, 20, 7) },
    [FRz] = { [6291] = Z(40, 36, 30, 10), [6361] = Z(70, 60, 22, 4) },
    [ZGz] = { [6299] = Z(55, 50, 14, 2) },
    [0] = { [6291] = Z(12, 12, 5, 20) },
  }
  ch.totals.ctz = { [SVz] = { [CLAM] = { caught = 22, opened = 20, failed = 1, got = { [PEARL] = 2, [CLAMMEAT] = 30 } } },
    [DMz] = { [CLAM] = { caught = 12, opened = 11, failed = 1, got = { [PEARL] = 1, [CLAMMEAT] = 20 } }, [BIGCLAM] = { caught = 9, opened = 7, failed = 0, got = { [PEARL] = 5, [CLAMMEAT] = 11 } } } }
  ch.locSince = 1799000000

  local zones = { 1434, 15, 26, 1444, 1946 }
  local sessions = {}
  for i = 1, 24 do
    local zone = zones[(i * 3) % 5 + 1]
    local catches = 20 + (i * 7) % 60
    local sp = { [6291] = { q = math.floor(catches / 2), c = math.floor(catches / 2), f = 1, l = 2 }, [6303] = { q = math.floor(catches / 3), c = math.floor(catches / 3), f = 1, l = 2 },
      [6299] = { q = math.floor(catches / 6), c = math.floor(catches / 6), f = 1, l = 2 } }
    local start = 1800900000 - (25 - i) * 86400 * 1.3
    local secs = 1500 + (i * 211) % 2400
    sessions[i] = { id = 164 + i, start = math.floor(start), stop = math.floor(start) + secs, seconds = secs, last = math.floor(start) + secs,
      ended = i % 4 == 0 and "idle" or "command", reason = "cast", zone = zone, casts = catches + 9, catches = catches, items = catches + 4,
      failed = 0, interrupted = 0, missed = 9, sessions = 0, line = secs * 0.6, species = sp,
      zones = { [zone] = { casts = catches + 9, catches = catches, items = catches + 4, line = secs * 0.6 } },
      containers = i % 5 == 0 and { [CLAM] = { caught = 2, opened = 2, failed = 0, got = { [PEARL] = 1, [CLAMMEAT] = 3 } } } or {},
      contents = i % 5 == 0 and { [PEARL] = 1, [CLAMMEAT] = 3 } or {}, first = 1, last = 2 }
  end
  -- the newest session fished three zones; the one before it two
  local last = sessions[#sessions]
  last.zones = { [1434] = { casts = 31, catches = 26, items = 29, line = 700 }, [15] = { casts = 24, catches = 21, items = 22, line = 520 }, [26] = { casts = 18, catches = 14, items = 15, line = 380 } }
  last.casts, last.catches, last.items = 73, 61, 66
  last.spz = { [1434] = { [6291] = { q = 14, c = 12, f = 1, l = 2 }, [6303] = { q = 9, c = 8, f = 1, l = 2 }, [6299] = { q = 6, c = 6, f = 1, l = 2 } },
    [15] = { [6291] = { q = 11, c = 9, f = 1, l = 2 }, [6361] = { q = 8, c = 7, f = 1, l = 2 } }, [26] = { [6362] = { q = 9, c = 8, f = 1, l = 2 }, [6359] = { q = 6, c = 6, f = 1, l = 2 } } }
  last.species = { [6291] = { q = 25, c = 21, f = 1, l = 2 }, [6303] = { q = 9, c = 8, f = 1, l = 2 }, [6299] = { q = 6, c = 6, f = 1, l = 2 },
    [6361] = { q = 8, c = 7, f = 1, l = 2 }, [6362] = { q = 9, c = 8, f = 1, l = 2 }, [6359] = { q = 6, c = 6, f = 1, l = 2 }, [24001] = { q = 3, c = 3, f = 1, l = 2 } }
  last.zone = 1434
  last.ctz = { [1434] = { [CLAM] = { caught = 2, opened = 2, failed = 0, got = { [PEARL] = 1, [CLAMMEAT] = 3 } } } }
  last.containers = { [CLAM] = { caught = 2, opened = 2, failed = 0, got = { [PEARL] = 1, [CLAMMEAT] = 3 } } }
  last.contents = { [PEARL] = 1, [CLAMMEAT] = 3 }
  ch.sessions = sessions
  ch.nextSession = 189
  ch.queue = { { id = 1, item = CLAM, n = 5, sid = 187, t = 1800800000 }, { id = 2, item = BIGCLAM, n = 2, sid = 188, t = 1800850000 } }
  F.Emit("CATCH")
end
W.Advance(0.1)
if page == "summary" then
  UI.Summary(ch.sessions[#ch.sessions].id)
elseif page == "empty" then
  UI.Open("overview")
else
  UI.Open(page)
  if arg[3] and arg[3] ~= "" then UI.Select(page, tonumber(arg[3]), arg[4] and arg[4] ~= "" and tonumber(arg[4]) or nil) end
end
W.Advance(0.1)

local function J(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" then return tostring(v) end
  if t == "number" then return (v ~= v or v == math.huge or v == -math.huge) and "null" or string.format("%.4f", v) end
  if t == "string" then return '"' .. v:gsub('[%c"\\]', function(chr) return string.format("\\u%04x", chr:byte()) end) .. '"' end
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
f:write(J({ screen = { 1366, 768 }, scene = page, regions = W.UI.Dump(), facts = { page = UI.Page(), notes = #F.notes, faults = 0 } }))
f:close()
for _, n in ipairs(F.notes) do print("note", n.code, n.detail) end
print("wrote " .. out)
