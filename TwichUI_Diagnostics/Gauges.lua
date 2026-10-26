-- TwichUI Diagnostics: what the operations are, and the gauges read while recording
-- The operation catalog names the scopes TwichUI's code opens (R.Perf ids): which module, in plain words, and what
-- kind of work, so the window and the findings can say "a rebuild" or "a layout". A module may add its own with
-- R.Perf.Describe; those win.
--
-- Gauges are numbers read at an interval (and when a window cycle ends): listener counts, pools, caches, what is
-- shown. They come from what TwichUI's modules already report about themselves (their Snapshot functions and a few
-- read-only counts); reading one never builds, loads or changes anything. Each is registered with R.Perf.Gauge, the
-- same way a module adds its own:
--   R.Perf.Gauge("npcs.map.pool", { label = "...", unit = "count", kind = "pool", group = "map", read = function() ... end })
-- kind: "listeners" (callbacks registered somewhere), "pool" (frames made and kept for reuse), "cache" (derived data
-- kept), "state" (0 or 1: something shown or running), "work" (a module's own running count of something it did).

local R = TwichUI
local DX = R.DiagnosticsKit
local Perf = R.Perf

DX.OPS = {
    ["core.savedData"] = { module = "core", label = "Saved data check at load (Persist.LoadMain)", kind = "init" },
    ["core.startupHook"] = { module = "core", label = "Start-up hooks (each module's OnInit)", kind = "init" },
    ["npcs.search"] = { module = "npcs", label = "NPC search (map toolbar)", kind = "search" },
    ["npcs.knowledge.rebuild"] = { module = "npcs", label = "NPC knowledge rows rebuilt", kind = "rebuild" },
    ["npcs.map.layout"] = { module = "npcs", label = "NPC markers placed on the world map", kind = "layout", visible = "map.open" },
    ["npcs.import"] = { module = "npcs", label = "NPC reports merged in (a received list)", kind = "bulk" },
    ["npcs.cleanup"] = { module = "npcs", label = "NPC entries removed (World Knowledge cleanup)", kind = "bulk" },
    ["pins.map.layout"] = { module = "pins", label = "Pins placed on the world map", kind = "layout", visible = "map.open" },
    ["reminders.refresh"] = { module = "reminders", label = "Reminders: everything decided again", kind = "rebuild" },
    ["reminders.decide"] = { module = "reminders", label = "Reminders: one reminder decided", kind = "evaluate" },
    ["healer.update"] = { module = "healer", label = "Healer Watch panel update", kind = "update" },
    ["settings.describe"] = { module = "settings", label = "Settings pages described (first open)", kind = "init" },
    ["settings.window.build"] = { module = "settings", label = "Settings window built (first open)", kind = "init" },
    ["settings.page.build"] = { module = "settings", label = "A settings page drawn for the first time", kind = "build" },
    ["settings.page.layout"] = { module = "settings", label = "A settings page laid out", kind = "layout", visible = "settings.shown" },
    ["settings.search"] = { module = "settings", label = "Settings search results drawn", kind = "search", visible = "settings.shown" },
    ["settings.search.index"] = { module = "settings", label = "Settings search index built", kind = "rebuild" },
}

-- The description of an operation id: the module's own (R.Perf.Describe), the catalog's, or one made from the id.
function DX.Op(id)
    local d = Perf.ops[id] or DX.OPS[id]
    if d then return d end
    local event = type(id) == "string" and id:match("^event:(.+)$")
    if event then return { module = "events", label = "Callbacks for " .. event, kind = "event" } end
    return { module = (type(id) == "string" and id:match("^([%w_]+)%.")) or "other", label = id, kind = "other" }
end

---------------------------------------------------------------------------
-- Built-in gauges
---------------------------------------------------------------------------
local scratch = {}
local function Listeners()
    if not R.ListenerCounts then return nil end
    for k in pairs(scratch) do scratch[k] = nil end
    R.ListenerCounts(scratch)
    local total = 0
    for _, n in pairs(scratch) do total = total + n end
    return total
end
local function Events()
    if not R.ListenerCounts then return nil end
    local n = 0
    for _ in pairs(scratch) do n = n + 1 end   -- after Listeners (gauges are read in order)
    return n
end
local function Snap(module)
    local M = R[module]
    if not (M and M.Snapshot) then return nil end
    local ok, s = pcall(M.Snapshot)
    return ok and type(s) == "table" and s or nil
end
local function Field(module, field)
    return function()
        local s = Snap(module)
        return s and DX.Num(s[field]) or nil
    end
end
local function Flag(v) if v == nil then return nil end return v and 1 or 0 end

local G = {
    { "core.listeners", "TwichUI event bus: listeners", "listeners", "core", Listeners },
    { "core.events", "TwichUI event bus: events listened for", "listeners", "core", Events },
    { "core.switchListeners", "Switch change listeners", "listeners", "core", function() return R.Switches and type(R.Switches.listeners) == "table" and #R.Switches.listeners or nil end },
    { "core.settingsClosers", "Settings-closed callbacks", "listeners", "core", function() local L = R.SettingsLauncher return L and type(L.closers) == "table" and #L.closers or nil end },
    { "core.easing", "Window effects easing now", "state", "core", function() local M = R.Look and R.Look.Motion return M and M.Count and DX.Num(M.Count()) or nil end },
    { "settings.shown", "Settings window shown", "state", "settings", function() local UI = R.SettingsUI return Flag(UI ~= nil and UI.IsShown() or false) end },
    { "settings.pagesDrawn", "Settings pages drawn (kept until a reload)", "cache", "settings", function()
        local UI = R.SettingsUI
        if not (UI and UI.Stats) then return nil end
        local ok, s = pcall(UI.Stats)
        return ok and type(s) == "table" and DX.Num(s.drawn) or nil
    end },
    { "settings.searchIndex", "Settings search index made", "cache", "settings", function()
        local UI = R.SettingsUI
        if not (UI and UI.Stats) then return nil end
        local ok, s = pcall(UI.Stats)
        return ok and type(s) == "table" and Flag(s.searchIndex) or nil
    end },
    { "map.open", "World map shown", "state", "map", function() return Flag(WorldMapFrame ~= nil and WorldMapFrame:IsShown() or false) end },
    { "npcs.map.pool", "NPC map markers made (pool)", "pool", "map", Field("NpcMap", "pool") },
    { "npcs.map.drawn", "NPC map markers in use", "pool", "map", Field("NpcMap", "drawn") },
    { "npcs.map.layouts", "NPC map layouts so far (module count)", "work", "map", Field("NpcMap", "layouts") },
    { "pins.map.pool", "Pin markers made (pool)", "pool", "map", Field("PinsMap", "pool") },
    { "pins.map.drawn", "Pin markers in use", "pool", "map", Field("PinsMap", "drawn") },
    { "map.detail.tiles", "Map detail tiles in use", "pool", "map", Field("MapDetail", "tiles") },
    { "map.detail.pooled", "Map detail tiles kept for reuse", "pool", "map", Field("MapDetail", "pooled") },
    { "nav.decodedTiles", "Navigation tiles decoded (cache)", "cache", "map", Field("NavData", "decodedTiles") },
    { "reminders.active", "Reminders running", "state", "group", Field("ReminderController", "active") },
    { "reminders.keys", "Reminders: observations listened for", "listeners", "group", Field("ReminderController", "keys") },
    { "reminders.decisions", "Reminders: decisions so far (module count)", "work", "group", Field("ReminderController", "decisions") },
    { "healer.events", "Healer Watch: events registered", "listeners", "group", Field("HealerWatcher", "events") },
    { "classbars.events", "Class bars: events registered", "listeners", "group", Field("ClassBars", "events") },
}
for _, g in ipairs(G) do
    Perf.Gauge(g[1], { label = g[2], kind = g[3], group = g[4], unit = "count", read = g[5], builtin = true })
end

-- The gauges a capture reads (groups nil: all), in registration order.
function DX.GaugeList(groups)
    local out = {}
    for _, g in ipairs(Perf.gauges) do
        local wanted = not groups
        if groups then
            for _, k in ipairs(groups) do if g.group == k or not g.builtin then wanted = true end end
        end
        if wanted and type(g.read) == "function" then out[#out + 1] = g end
        if #out >= 40 then break end
    end
    return out
end
