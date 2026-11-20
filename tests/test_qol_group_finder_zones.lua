dofile(TESTS .. "harness.lua")
-- Quality of Life: Group Finder zones (qol/GroupFinderZones.lua). The game's Group Finder, its rows and the
-- C_LFGList results are simulated: this checks what is read, compared and drawn, not the game's layout or
-- fonts, which have to be checked in the game.
local c = MakeClient("Rich", { "!!!TwichUI" })

local hooks = {}
c.hooksecurefunc = function(name, fn)
  assert(type(name) == "string", "hooks the global function by name, never a frame's script")
  hooks[#hooks + 1] = { name = name, fn = fn }
end
c.issecretvalue = function(v) return type(v) == "table" and v.secret == true end
local SECRET = { secret = true }

local W = { zone = "Elwynn Forest", sub = "Goldshire", results = {} }
c.GetRealZoneText = function() return W.zone end
c.GetZoneText = function() return W.zone end
c.GetSubZoneText = function() return W.sub end
c.GetMinimapZoneText = function() return W.sub ~= "" and W.sub or W.zone end
c.C_LFGList = {
  GetSearchResultInfo = function(id) local r = W.results[id]; return r and { isDelisted = r.delisted or false } end,
  GetSearchResultLeaderInfo = function(id) local r = W.results[id]; return r and { areaName = r.area, isLeader = true } end,
  GetSearchResultPlayerInfo = function(id, i) local r = W.results[id]; if r and i == 1 then return { areaName = r.area, isLeader = r.soloLeader ~= false } end end,
}

local chunk = assert(loadfile(ROOT .. "qol/GroupFinderZones.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R, DB = c.TwichUI, c.TwichUIDB
local Z = R.QoLGroupFinderZones
R.Look = R.Look or { pal = { sage = { 0.60, 0.74, 0.55 } } }

-- The game's rows, with only what the module reads.
local made = setmetatable({}, { __mode = "k" })   -- [row] = font strings made on it
local function FontString()
  local fs = { shown = false, width = 0 }
  function fs:SetFontObject(f) self.font = f end
  function fs:SetJustifyH() end
  function fs:SetWordWrap(on) self.wrap = on end
  function fs:ClearAllPoints() self.point = nil end
  function fs:SetPoint(...) self.point = { ... } end
  function fs:SetText(t) self.text = t end
  function fs:SetTextColor(r, g, b) self.color = { r, g, b } end
  function fs:SetWidth(w) self.width = w end
  function fs:GetStringWidth() return #(self.text or "") * 6 end
  function fs:Show() self.shown = true end
  function fs:Hide() self.shown = false end
  return fs
end
local function Region(left, shown) return { IsShown = function() return shown ~= false end, GetLeft = function() return left end } end
local function Row(resultID, o)
  o = o or {}
  local row = { resultID = resultID }
  row.ActivityName = { GetRight = function() return o.activityRight end, GetTextColor = function() return 0.5, 0.5, 0.5 end,
    GetFontObject = function() return "ActivityFont" end }
  row.DataDisplay = {
    IsShown = function() return true end,
    Solo = { IsShown = function() return o.solo ~= false end, RolesText = Region(o.rolesLeft or 250), Roles = { Region(o.rolesLeft and o.rolesLeft + 30 or 280) } },
    Enumerate = { IsShown = function() return o.enumerate == true end, Icons = { Region(160), Region(187), Region(214, false) } },
    PlayerCount = { IsShown = function() return false end },
    RoleCount = { IsShown = function() return o.roleCount == true end },
    Comment = Region(110, false),
    DelistButton = Region(280, false),
  }
  function row:GetRight() return 312 end
  function row:CreateFontString()
    local fs = FontString()
    made[self] = (made[self] or 0) + 1
    return fs
  end
  return row
end
local function Keys(t) local n = {} for k in pairs(t) do n[#n + 1] = tostring(k) end table.sort(n) return table.concat(n, ",") end

local rows = {}
c.LFGBrowseFrame = { ScrollBox = { ForEachFrame = function(_, fn) for _, row in ipairs(rows) do fn(row) end end } }
local function Hook() return hooks[1] and hooks[1].fn end
local function Draw(row) local fn = Hook(); if fn then fn(row) end end
local last = setmetatable({}, { __mode = "k" })
-- Capture the font string a row was given, by wrapping CreateFontString.
local function Track(row)
  local create = row.CreateFontString
  row.CreateFontString = function(self, ...) local fs = create(self, ...); last[self] = fs; return fs end
  return row
end

-- Off by default: no hook, nothing listening, nothing drawn.
assert(DB.modules.qolGroupFinderZones == false, "off by default")
c.LFGBrowseSearchEntry_Update = function() end
c.FireEvent("ADDON_LOADED", Z.ADDON)
assert(#hooks == 0 and not Z.Hooked(), "nothing is hooked while the switch has never been on")

-- On before the game's Group Finder is loaded: waits for it, then hooks once.
c.LFGBrowseSearchEntry_Update = nil
R:SetEnabled("qolGroupFinderZones", true)
assert(#hooks == 0, "no Group Finder yet")
c.FireEvent("ADDON_LOADED", "SomethingElse")
assert(#hooks == 0)
c.LFGBrowseSearchEntry_Update = function() end
c.FireEvent("ADDON_LOADED", Z.ADDON)
assert(#hooks == 1 and hooks[1].name == "LFGBrowseSearchEntry_Update" and Z.Hooked(), "hooked when the Group Finder loads")
c.FireEvent("ADDON_LOADED", Z.ADDON)
R:SetEnabled("qolGroupFinderZones", false); R:SetEnabled("qolGroupFinderZones", true)
assert(#hooks == 1, "hooked only once, however often it is turned on")

-- A single player in another zone: the zone after the activity, in the activity's color.
W.results[1] = { area = "Westfall" }
local a = Track(Row(1, { activityRight = 100 }))
local before = Keys(a)
Draw(a)
local fs = last[a]
assert(fs and fs.shown and fs.text == "Westfall", tostring(fs and fs.text))
assert(fs.point[1] == "LEFT" and fs.point[2] == a.ActivityName and fs.point[3] == "RIGHT" and fs.point[4] == Z.GAP, "after the activity")
assert(fs.color[1] == 0.5 and fs.font == "ActivityFont" and fs.wrap == false, "the activity's look; one line")
assert(fs.width == 48, "as wide as its text when there is room")
local function Without(keys) return (keys:gsub("CreateFontString,?", "")) end
assert(Without(Keys(a)) == Without(before), "nothing is written on the game's row: " .. Keys(a))

-- Redrawn on the same row: the same font string, not another.
Draw(a); Draw(a)
assert(made[a] == 1, "one font string per row")

-- In your zone: marked with a check and the on color.
W.results[2] = { area = "Elwynn Forest" }
local b = Track(Row(2, { activityRight = 100 }))
Draw(b)
assert(last[b].text:find("status%-done%-small") and last[b].text:find("Elwynn Forest$"), last[b].text)
assert(last[b].color[1] == 0.60 and last[b].color[2] == 0.74, "the on color")
-- By the subzone the game gives too.
W.results[3] = { area = "Goldshire" }
local s = Track(Row(3, { activityRight = 100 }))
Draw(s)
assert(last[s].text:find("Goldshire$") and last[s].text:find("|T"), "a subzone you are in counts as here")
-- A delisted listing is never marked.
W.results[4] = { area = "Elwynn Forest", delisted = true }
local d = Track(Row(4, { activityRight = 100 }))
Draw(d)
assert(last[d].text == "Elwynn Forest" and last[d].color[1] == 0.5, "delisted: dimmed like the row, no mark")

-- Moving: the shown rows are redrawn with the new place.
rows = { a, b }
W.zone, W.sub = "Westfall", ""
c.FireEvent("ZONE_CHANGED_NEW_AREA")
assert(last[a].text:find("|T") and last[b].text == "Elwynn Forest", "the mark follows you")
W.zone, W.sub = "Elwynn Forest", "Goldshire"
c.FireEvent("ZONE_CHANGED")
assert(last[a].text == "Westfall" and last[b].text:find("|T"))

-- Nothing readable: nothing shown.
W.results[5] = { area = nil }
local n = Track(Row(5, { activityRight = 100 }))
Draw(n)
assert(not last[n], "no zone: no font string is made")
W.results[1].area = SECRET
Draw(a)
assert(not last[a].shown, "a secret zone is never shown or compared")
W.results[1].area = "Westfall"
W.zone, W.sub = SECRET, SECRET
c.GetMinimapZoneText = function() return SECRET end
c.FireEvent("ZONE_CHANGED")
assert(last[a].shown and last[a].text == "Westfall" and last[b].text == "Elwynn Forest", "your place unreadable: nothing is marked")
W.zone, W.sub = "Elwynn Forest", "Goldshire"
c.GetMinimapZoneText = function() return W.sub ~= "" and W.sub or W.zone end
c.FireEvent("ZONE_CHANGED")
Draw({ resultID = 1 })   -- a row without the regions the module needs is left alone
Draw(nil)

-- Without the leader call: member 1, when it is the leader.
local leader = c.C_LFGList.GetSearchResultLeaderInfo
c.C_LFGList.GetSearchResultLeaderInfo = nil
assert(Z.LeaderZone(1) == "Westfall", "falls back to member 1")
W.results[1].soloLeader = false
assert(Z.LeaderZone(1) == nil, "never another member's zone")
W.results[1].soloLeader = nil
c.C_LFGList.GetSearchResultLeaderInfo = function() error("blocked") end
assert(Z.LeaderZone(1) == "Westfall", "an error from the game falls back too")
c.C_LFGList.GetSearchResultLeaderInfo = leader
assert(Z.LeaderZone(SECRET) == nil and Z.LeaderZone("1") == nil, "a result id we can't read")

-- Room: held to the space before the right-hand block, left out when there is too little.
W.results[6] = { area = "Stranglethorn Vale" }      -- 18 characters: 108 wide in this stub
local tight = Track(Row(6, { activityRight = 150, rolesLeft = 230 }))
Draw(tight)
assert(last[tight].shown and last[tight].width == 230 - 150 - 2 * Z.GAP, "narrowed to the room: " .. last[tight].width)
local none = Track(Row(6, { activityRight = 220, rolesLeft = 250 }))
Draw(none)
assert(not last[none], "too little room: left out")
local grp = Track(Row(6, { activityRight = 100, solo = false, enumerate = true }))
Draw(grp)
assert(last[grp].width == 160 - 100 - 2 * Z.GAP, "a group's member icons bound it (hidden icons don't)")
local unknown = Track(Row(6, { activityRight = 100, solo = false, roleCount = true }))
Draw(unknown)
assert(last[unknown].width == math.min(108, Z.CAP), "a layout we don't know: the cap")
local unlaid = Track(Row(6, {}))
Draw(unlaid)
assert(last[unlaid].width == math.min(108, Z.CAP), "not laid out yet: the cap")

-- Off: every zone hidden at once, the hook does nothing; on again: the shown rows are drawn again.
rows = { a, b, tight }
R:SetEnabled("qolGroupFinderZones", false)
assert(not last[a].shown and not last[b].shown and not last[tight].shown, "turned off: hidden at once")
Draw(a)
assert(not last[a].shown, "the hook draws nothing while off")
c.FireEvent("ZONE_CHANGED")
assert(not last[a].shown, "no zone listening while off")
R:SetEnabled("qolGroupFinderZones", true)
assert(last[a].shown and last[b].shown and last[tight].shown and #hooks == 1, "on again without a reload, same hook")
assert(made[a] == 1, "and still one font string per row")

-- The diagnostics gauge counts the font strings made.
local gauge
for _, g in ipairs(R.Perf.gauges) do if g.id == "qol.groupFinderZones.labels" then gauge = g end end
assert(gauge and gauge.kind == "pool" and gauge.read() == 8, "gauge: " .. tostring(gauge and gauge.read()))

print("test_qol_group_finder_zones: OK")
