-- Production cave contracts on synthetic geometry; actual-art review is separate.
local R, objects, frames = {}, {}, {}
local function Object(parent)
    local o = { parent = parent, shown = true, alpha = 1, scripts = {} }; objects[#objects + 1] = o
    function o:SetAllPoints(p) self.allPoints = p end
    function o:SetPoint(...) self.point = { ... } end
    function o:ClearAllPoints() self.point = nil end
    function o:SetSize(w, h) self.width, self.height = w, h end
    function o:SetColorTexture(...) self.fill = { ... } end
    function o:SetTexture(v) self.texture = v; return true end
    function o:SetTexCoord(...) self.coord = { ... } end
    function o:SetAlpha(v) self.alpha = v end
    function o:GetAlpha() return self.alpha end
    function o:Show() self.shown = true end
    function o:Hide() self.shown = false end
    function o:IsShown() return self.shown end
    function o:SetFrameLevel(v) self.level = v end
    function o:EnableMouse(v) self.mouse = v end
    function o:SetScript(n, fn) self.scripts[n] = fn end
    function o:CreateTexture() return Object(self) end
    return o
end
local root = Object()
local view, size, ready, active, prefs = { .3, .3, .45, .45 }, { 1000, 666 }, true, true, { caves = true }
local context
local scopeCalls, scopes, detailUpdates, pending, async, trace = {}, {}, 0, {}, false, {}
R.MapTrace = function(...) trace[#trace + 1] = { ... } end
R.Perf = { Wrap = function(name, fn)
    scopes[name] = true
    return function(...) scopeCalls[name] = (scopeCalls[name] or 0) + 1; return fn(...) end
end }
R.MapDetail = { Update = function() detailUpdates = detailUpdates + 1 end }
R.MapExplorePrefs = { Get = function(k) return prefs[k] end, Subscribe = function(fn) R.PreferenceListener = fn end }
R.MapView = { Ready = function() return ready end, Active = function() return active end,
    ViewRect = function() return unpack(view) end, ViewSize = function() return unpack(size) end,
    RectZoom = function(u0, v0, u1, v1) return 1 / math.max(u1 - u0, v1 - v0) end,
    ArtLevel = function(n) return n + 10 end, FrameMap = function(id) R.framed = id end,
    Subscribe = function(fn) R.ViewListener = fn end }
R.MapWorld = { Size = function() return 1002, 668 end, YardsRect = function(_, ...) return ... end, Deepest = function() return 1429 end }
R.MapArt = { Root = function() return root end }
R.MapControls = { ShowContext = function(_, spec) context = spec end, HideContext = function() context = nil end }
R.MapPictures = { Forget = function(tex) pending[tex] = nil end, BindIdentity = function() end,
    Show = function(tex, s)
        if s <= .005 then pending[tex] = nil; tex:Hide()
        elseif async then pending[tex] = s; tex:Hide()
        else pending[tex] = nil; tex:SetAlpha(s); tex:Show() end
    end,
    Create = function(parent) return { parent = parent } end,
    Set = function(set, record) set.record = record end,
    Update = function(set, _, _, _, _, s) set.alpha = s end }
local function Tiles(first) local out = {}; for i = 1, 12 do out[i] = first + i end; return out end
R.MapExploreData = { caves = {
    { 1, "Chart one", 0, .25, .25, .5, .5, Tiles(100) },
    { 2, "Chart two", 0, .4375, .25, .6875, .5, Tiles(200) },
    { 3, "Two floors", 0, .75, .25, .875, .375, Tiles(300), 10, 1, "Upper" },
    { 4, "Two floors", 0, .75, .25, .875, .375, Tiles(400), 10, 2, "Lower" } } }
R.MapExploreLocalData = { caves = { { 0, .125, .75, .25, .875, { 1001, 0, 0, 1, 0, 1, 0 } } } }
local env = setmetatable({ TwichUI = R, CreateFrame = function(_, _, p)
    local o = Object(p); frames[#frames + 1] = o; return o end }, { __index = _G })
for _, name in ipairs({ "map/ViewMath.lua", "map/Caves.lua" }) do
    local fn = assert(loadfile((ROOT or "../!!!TwichUI/") .. name)); setfenv(fn, env); fn()
end
local C, count = R.MapCaves, 0
local function check(v, why) assert(v, why); count = count + 1 end
local function near(a, b) return math.abs(a - b) < 1e-8 end
local function Box(cx, cy, w, h) return { cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2 } end
local function Strength(rect) return C.StrengthAt(unpack(rect)) end
local function Tick(elapsed)
    for _, frame in ipairs(frames) do
        if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, elapsed) end
    end
end
local function Idle()
    for _, frame in ipairs(frames) do if frame.scripts.OnUpdate then return false end end
    return true
end
for _, cx in ipairs({ .375, .49, .5 }) do
    C.Sink(); local g, s = Strength(Box(cx, .375, .0625, .0625))
    check(g and g.id == "cave:1" and s == 1, "close cave readable through center boundary")
end
-- Isolate one chart to measure the pan fade rather than a neighboring handoff.
C.Sink(); local neighbor = C.Get("cave:2"); local saved = neighbor.v0; neighbor.v0 = .8
view = Box(.5, .375, .0625, .0625); C.Update()
local previous, maxStep = 1, 0
for i = 0, 200 do
    local _, s = Strength(Box(.5 + .03125 * i / 200, .375, .0625, .0625))
    check(s <= previous + 1e-8, "monotone visible-artwork exit")
    maxStep = math.max(maxStep, previous - s); previous = s
end
neighbor.v0 = saved
check(previous == 0 and maxStep < .02, "continuous fade until actual viewport exit")
C.Sink(); view = Box(.73, .375, .125, .125); C.Update()
check(not C.Surfaced() and select(1, C.Current()) == nil, "off-center cave cannot unexpectedly dim an outdoor view")
C.Sink()
check(select(2, Strength(Box(.375, .375, .01, .01))) == 1, "tiny view inside chart")
check(select(2, Strength(Box(.375, .375, .1, 2))) == 0, "tall view cannot surface tiny chart")
check(select(2, Strength(Box(.375, .375, 2, .1))) == 0, "wide view cannot surface tiny chart")
view = Box(.375, .375, .125, .125); C.Update()
check(select(1, C.Current()).id == "cave:1", "first chart selected")
check(trace[#trace][1] == "cave-transition" and trace[#trace][2] == "entry-start"
    and trace[#trace][3] == "cave:1" and trace[#trace][4] == 0 and trace[#trace][5] == 1, "bounded entry-start trace reports actual and target")
check(select(3, C.Current()) == 0 and C.Snapshot().targetStrength == 1 and C.Snapshot().entryFading,
    "fresh close entry starts transparent with explicit target")
check(C.Veil().alpha == 0 and not C.Tile(1).shown and context == nil, "entry veil/art/context start at actual zero")
check(scopes["map.cave.fade"] and scopes["map.cave.update"] and not Idle(), "single existing-layer driver uses registered scopes")
local traceBefore = #trace; Tick(.075)
check(#trace == traceBefore, "fade ticks do not generate per-frame trace")
check(near(select(3, C.Current()), .5) and near(C.Tile(1).alpha, .5) and near(C.Veil().alpha, .325), "entry midpoint updates actual displayed alpha")
check(context == nil, "context bar waits for actual readability")
local age = C.Snapshot().entryElapsedSeconds
for _ = 1, 5 do C.Update() end
check(C.Snapshot().entryElapsedSeconds == age and near(select(3, C.Current()), .5), "repeated view updates cannot restart entry")
view = Box(.515, .375, .0625, .0625); C.Update()
local target = select(2, Strength(view))
check(near(C.Snapshot().targetStrength, target) and near(select(3, C.Current()), target * .5), "view geometry and target tracked during entry")
view = Box(.375, .375, .125, .125); C.Update()
local completedBefore = detailUpdates; Tick(.075)
check(select(3, C.Current()) == 1 and not C.Snapshot().entryFading and Idle(), "entry completes and removes updater")
check(detailUpdates == completedBefore + 1, "completion refreshes covered terrain exactly once")
check(trace[#trace][2] == "entry-end" and trace[#trace][4] == 1, "entry-end trace reports actual completion")
local ticksBefore = scopeCalls["map.cave.fade"]; Tick(1)
check(scopeCalls["map.cave.fade"] == ticksBefore and detailUpdates == completedBefore + 1, "no idle fade or repeated terrain refresh")
view = Box(.49, .375, .125, .125); for _ = 1, 5 do C.Update() end
check(select(1, C.Current()).id == "cave:1", "overlapping candidates retain incumbent")
check(context and context.sub == "Local cave chart", "intentional chart context")
check(C.Snapshot().presentation == "local-chart" and C.Snapshot().selection == "center-entry-visible-exit", "diagnostic provenance")
local first, last = C.Tile(1), C.Tile(12)
local captured = C.Snapshot(true)
check(#captured.textures == 12 and captured.textures[1].fileId == 101 and captured.textures[12].texCoord[2] == 234 / 256,
    "optional support capture retains actual painted tile identities and crops")
check(#C.Snapshot().textures == 0 and C.Snapshot().coordinates == "withheld", "artwork coordinates remain opt-in")
check(near(first.point[4], .25 * 1002) and near(-first.point[5], .25 * 668), "original top-left geography")
check(near(last.point[4] + last.width, .5 * 1002) and near(-last.point[5] + last.height, .5 * 668), "original bottom-right geography")
check(first.coord[1] == 0 and first.coord[2] == 1 and last.coord[2] == 234 / 256, "tile crops unchanged")
local made = #objects
for i = 1, 100 do view = Box(.375 + i / 10000, .375, .125, .125); C.Update() end
check(#objects == made, "bounded/reused decoration")
for _, f in ipairs(frames) do check(not f.scripts.OnUpdate, "no idle polling") end
-- Distinct overlapping cave charts keep a stable incumbent through a fine pan.
-- A new chart after the viewport exit gets the same entry fade, avoiding an
-- opaque handoff without keeping a second set of twelve textures alive.
local prior, swaps, handoffStep = select(1, C.Current()).id, 0, 0
local previousStrength = select(3, C.Current())
for i = 0, 200 do
    view = Box(.49 + i * .0008, .375, .125, .125); C.Update(); Tick(.001)
    local g, _, s = C.Current()
    if g and g.id ~= prior then
        swaps, handoffStep = swaps + 1, math.max(handoffStep, math.abs(s - previousStrength))
        prior = g.id
    end
    previousStrength = s
end
check(swaps == 1 and prior == "cave:2", "one stable handoff after prior chart leaves view")
check(handoffStep < .02, "entry fade prevents an opaque candidate handoff")
C.Sink(); view = Box(.1875, .8125, .05, .05); C.Update()
check(select(1, C.Current()).id == "wmo:1" and C.Snapshot().presentation == "interior", "WMO remains frameless")
for _, o in ipairs(objects) do if o.fill and o.fill[1] == .51 then check(not o.shown, "chart frame hidden on WMO") end end
C.Sink(); view = Box(.8125, .3125, .05, .05); C.Update()
check(C.SetFloor(2) and C.Tile(1).texture == 401, "floor switching")
check(not C.SetFloor(0) and not C.SetFloor(99), "invalid floor rejected")
for _, rect in ipairs({ { 0, 0, 0, 1 }, { 0, 0, 1, 0 }, { 0, 0, math.huge, 1 }, { 0, 0, 0/0, 1 } }) do
    check(select(2, Strength(rect)) == 0, "invalid view safe")
end
check(select(2, C.StrengthAt(nil, 0, 1, 1)) == 0 and C.At(nil, 0) == nil, "missing geometry safe")
size = { 0, 666 }; C.Update(); size = { 1000, 666 }
prefs.caves = false; R.PreferenceListener()
check(not C.Surfaced() and C.Tile(1).texture == nil, "disable releases artwork")
prefs.caves = true; C.Update(); R.ViewListener("hide")
check(not C.Surfaced() and C.Tile(1).texture == nil and context == nil, "close releases context/artwork")
C.Update(); Tick(.15); check(C.Surfaced(), "reopen")
R.MapDungeonView = { IsOpen = function() return true end }; C.Update(); check(not C.Surfaced(), "dungeon suspends cave")
check(Idle() and not C.Snapshot().entryFading and C.Snapshot().targetStrength == 0, "dungeon cancellation releases transition state")
R.MapDungeonView = nil
-- Async loading cannot bring back artwork after an entry was closed/cancelled.
async = true; C.Update(); Tick(.075)
check(next(pending) ~= nil and C.Snapshot().entryFading, "pending load during entry")
R.ViewListener("hide")
check(next(pending) == nil and Idle(), "close forgets pending textures and entry driver")
async = false; Tick(1)
check(not C.Tile(1).shown and C.Tile(1).texture == nil, "late load cannot reveal closed artwork")
C.Update(); Tick(.05); ready = false; Tick(.01)
check(Idle() and not C.Surfaced(), "readiness loss cancels active entry")
ready = true; C.Update(); Tick(.05); prefs.caves = false; Tick(.01)
check(Idle() and not C.Surfaced(), "disable cancels entry even before preference listener")
prefs.caves = true; C.Update(); Tick(.05); active = false; Tick(.01)
check(Idle() and not C.Surfaced(), "inactive map cancels entry")
active = true; C.Update(); C.SetFloor(1); Tick(.15)
check(C.Surfaced() and Idle(), "floor update during entry preserves completion")
C.Sink(); check(trace[#trace][2] == "sink" and trace[#trace][3] == "cave:3", "sink trace only for a current cave")
traceBefore = #trace; C.Sink(); C.Sink(); check(#trace == traceBefore, "idle sinks do not record events")
print("MAP CAVE POLISH PASSED: " .. count .. " assertions")
