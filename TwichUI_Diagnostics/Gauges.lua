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

-- file: the TwichUI file that opens the scope (relative to the AddOns folder's TwichUI folders; the core is
-- "!!!TwichUI/", the settings window "TwichUI_Settings/"), where: the function, so a report can name what to read.
-- every = how often it is expected to run, so a report can tell "runs often" from "runs on demand".
DX.OPS = {
    ["core.savedData"] = { module = "core", label = "Saved data check at load (Persist.LoadMain)", kind = "init", file = "Core.lua", where = "ADDON_LOADED handler > Persist.LoadMain", every = "once per load" },
    ["core.startupHook"] = { module = "core", label = "Start-up hooks (each module's OnInit)", kind = "init", file = "Core.lua", where = "R.initHooks loop", every = "once per load, per module" },
    ["npcs.search"] = { module = "npcs", label = "NPC search (map toolbar)", kind = "search", file = "npcs/Search.lua", where = "SR.Run", every = "per search typed" },
    ["npcs.knowledge.rebuild"] = { module = "npcs", label = "NPC knowledge rows rebuilt", kind = "rebuild", file = "npcs/Knowledge.lua", where = "Build", every = "when the NPC list changes" },
    ["npcs.map.layout"] = { module = "npcs", label = "NPC markers placed on the world map", kind = "layout", visible = "map.open", file = "npcs/Map.lua", where = "NMAP.Layout", every = "per map change, zoom or pan" },
    ["npcs.import"] = { module = "npcs", label = "NPC reports merged in (a received list)", kind = "bulk", file = "npcs/Store.lua", where = "NS.MergeReported", every = "per received list" },
    ["npcs.cleanup"] = { module = "npcs", label = "NPC entries removed (World Knowledge cleanup)", kind = "bulk", file = "npcs/Store.lua", where = "NS.ForgetMany", every = "on request" },
    ["npcs.minimap.tick"] = { module = "npcs", label = "NPC markers on the minimap, one update", kind = "update", file = "npcs/Minimap.lua", where = "Update > Step", every = "10 times a second (25 when the minimap rotates) while the feature is on" },
    ["npcs.map.pulse"] = { module = "npcs", label = "Ring pulse on a found NPC, one frame", kind = "update", file = "npcs/Map.lua", where = "PulseTick", every = "every frame for a few seconds after a find" },
    ["pins.map.layout"] = { module = "pins", label = "Pins placed on the world map", kind = "layout", visible = "map.open", file = "pins/Map.lua", where = "PM.Layout", every = "per map change, zoom or pan" },
    ["pins.minimap.tick"] = { module = "pins", label = "Pins on the minimap, one update", kind = "update", file = "pins/Minimap.lua", where = "Update > Step", every = "10 times a second (25 when rotating) while a pin is eligible" },
    ["pins.ping.tick"] = { module = "pins", label = "A map ping animating, one frame", kind = "update", file = "pins/PingMap.lua", where = "Tick > Step", every = "every frame while a ping shows" },
    ["nav.load"] = { module = "nav", label = "Navigation data addon loaded (first route)", kind = "init", file = "nav/Data.lua", where = "ND.Load > C_AddOns.LoadAddOn", every = "once per session, when the first route is asked for" },
    ["layouts.load"] = { module = "layouts", label = "Layout tools addon loaded", kind = "init", file = "LayoutsLauncher.lua", where = "L.Load > C_AddOns.LoadAddOn", every = "once per session, for /tui layout or after a reload while an install is being finished" },
    ["layouts.plan"] = { module = "layouts", label = "Layout install planned (package checked, layers composed, each addon read)", kind = "rebuild", file = "TwichUI_Layouts/Engine.lua", where = "LY.Plan", every = "on request (/tui layout plan, and again inside apply)" },
    ["layouts.apply"] = { module = "layouts", label = "Layout install applied (EllesmereUI import, TwichUI profile and values)", kind = "bulk", file = "TwichUI_Layouts/Engine.lua", where = "LY.Apply", every = "on request" },
    ["layouts.verify"] = { module = "layouts", label = "Layout install or restore checked", kind = "evaluate", file = "TwichUI_Layouts/Engine.lua", where = "LY.Verify, LY.VerifyRestore", every = "on request, and once after the reload that finishes an install or a restore" },
    ["layouts.restore"] = { module = "layouts", label = "Layout install restored", kind = "bulk", file = "TwichUI_Layouts/Engine.lua", where = "LY.Restore", every = "on request" },
    ["nav.search"] = { module = "nav", label = "Route search, one slice", kind = "update", file = "nav/Nav.lua", where = "StepJob", every = "every frame while a route is being searched" },
    ["nav.position"] = { module = "nav", label = "Navigation: position read and announced", kind = "update", file = "nav/Nav.lua", where = "OnUpdate > ReadPosition + Emit(position)", every = "POS_EVERY seconds while navigating" },
    ["nav.progress"] = { module = "nav", label = "Navigation: progress along the route", kind = "update", file = "nav/Nav.lua", where = "Progress", every = "PROGRESS_EVERY seconds while navigating" },
    ["nav.ticker"] = { module = "nav", label = "Navigation: a trail or arrow updater, one frame", kind = "update", file = "nav/Nav.lua", where = "OnUpdate > tickers (nav/MapTrail.lua, nav/MinimapTrail.lua, nav arrow)", every = "every frame while navigating" },
    ["map.view.step"] = { module = "map", label = "Map glide or zoom animation, one frame", kind = "update", file = "map/View.lua", where = "Step", every = "every frame during a glide" },
    ["map.view.follow"] = { module = "map", label = "Map following the view, one frame", kind = "update", file = "map/View.lua", where = "FollowStep", every = "every frame after the view moved, until still" },
    ["map.view.notify"] = { module = "map", label = "Map view change announced", kind = "update", file = "map/View.lua", where = "Notified", every = "once after a view change" },
    ["classbars.anim"] = { module = "classbars", label = "Class bar animation, one step", kind = "update", file = "classbars/Anim.lua", where = "OnUpdate > obj.Step", every = "every frame while a bar animates" },
    ["reminders.refresh"] = { module = "reminders", label = "Reminders: everything decided again", kind = "rebuild", file = "reminders/Controller.lua", where = "Refresh", every = "when a setting or the situation changes" },
    ["reminders.decide"] = { module = "reminders", label = "Reminders: one reminder decided", kind = "evaluate", file = "reminders/Controller.lua", where = "Decide (local)", every = "when an observation it uses changes" },
    ["reminders.event"] = { module = "reminders", label = "Reminders: a game event reached the state watcher", kind = "event", file = "reminders/State.lua", where = "OnEvent (its own frame, not the event bus)", every = "per event the active reminders listen for (aura and bag events can be frequent)" },
    ["healer.update"] = { module = "healer", label = "Healer Watch panel update", kind = "update", file = "healer/Watch.lua", where = "Update (local)", every = "when the watched healer's state changes" },
    ["healer.event"] = { module = "healer", label = "Healer Watch: a game event (chat, roster)", kind = "event", file = "healer/Watch.lua", where = "OnEvent (its own frame)", every = "per chat or roster event while watching" },
    ["healer.unitEvent"] = { module = "healer", label = "Healer Watch: a unit event for the watched healer", kind = "event", file = "healer/Watch.lua", where = "OnUnitEvent (its own frame)", every = "per power, health or aura event of that one unit" },
    ["targetart.event"] = { module = "targetart", label = "Target artwork: a target event", kind = "event", file = "targetart/Display.lua", where = "OnEvent (its own frame)", every = "per target change or classification change" },
    ["refreshments.cast"] = { module = "refreshments", label = "Mage refreshments: a cast by the player", kind = "event", file = "modules/Refreshments.lua", where = "castFrame OnEvent (UNIT_SPELLCAST_SUCCEEDED, player)", every = "per spell the player casts (builds a small closure each time)" },
    ["rxp.skin.render"] = { module = "restedxp", label = "RestedXP skin: RestedXP drew its frame", kind = "hook", file = "modules/RestedXPSkin.lua", where = "OnRender (hooksecurefunc RXP.RenderFrame)", every = "whenever RestedXP renders its guide frame" },
    ["rxp.skin.stepText"] = { module = "restedxp", label = "RestedXP skin: current step text updated", kind = "hook", file = "modules/RestedXPSkin.lua", where = "OnStepText (hook CurrentStepFrame.UpdateText)", every = "whenever RestedXP updates the step text" },
    ["rxp.skin.arrow"] = { module = "restedxp", label = "RestedXP skin: arrow redrawn, resized or re-fonted", kind = "hook", file = "modules/RestedXPSkin.lua", where = "Arrow.OnVisuals / OnSize / OnFont (hooks on RestedXP's arrow)", every = "whenever RestedXP updates its arrow (can be many times a second while moving)" },
    ["rxp.skin.tray"] = { module = "restedxp", label = "RestedXP skin: a tray's visuals updated", kind = "hook", file = "modules/RestedXPSkin.lua", where = "OnTrayVisuals (hook tray.UpdateVisuals)", every = "whenever RestedXP updates a tray" },
    ["rxp.skin.scale"] = { module = "restedxp", label = "RestedXP skin: a frame was scaled", kind = "hook", file = "modules/RestedXPSkin.lua", where = "OnScale (hooks on SetScale)", every = "when RestedXP rescales" },
    ["rxp.skin.fontSize"] = { module = "restedxp", label = "RestedXP skin: guide font size changed", kind = "hook", file = "modules/RestedXPSkin.lua", where = "OnFontSize (hook RXP.UpdateGuideFontSize)", every = "when the font size changes" },
    ["rxp.skin.currentTick"] = { module = "restedxp", label = "RestedXP skin: current-step button hover check", kind = "update", file = "modules/RestedXPSkin.lua", where = "Current.Tick (button OnUpdate)", every = "several times a second while the button shows" },
    ["rxp.timers.start"] = { module = "restedxp", label = "RestedXP timers: a timer started", kind = "hook", file = "modules/RestedXPTimers.lua", where = "OnStart (hook RXP.StartTimer)", every = "per RestedXP timer" },
    ["rxp.timers.show"] = { module = "restedxp", label = "RestedXP timers: timers shown", kind = "hook", file = "modules/RestedXPTimers.lua", where = "OnShow (hook RXP.ShowTimers)", every = "per RestedXP timer display" },
    ["rxp.waypoint.sync"] = { module = "restedxp", label = "RestedXP waypoint sync", kind = "hook", file = "qol/GuideWaypoint.lua", where = "W.Sync (hooks UpdateMap, UpdateGotoSteps, ResetArrowPosition)", every = "whenever RestedXP updates its map or goto steps" },
    ["settings.describe"] = { module = "settings", label = "Settings pages described (first open)", kind = "init", file = "TwichUI_Settings/Window.lua", where = "K.Describe", every = "once, first open" },
    ["settings.window.build"] = { module = "settings", label = "Settings window built (first open)", kind = "init", file = "TwichUI_Settings/Window.lua", where = "BuildWindow", every = "once, first open" },
    ["settings.page.build"] = { module = "settings", label = "A settings page drawn for the first time", kind = "build", file = "TwichUI_Settings/Window.lua", where = "BuildView", every = "once per page, first visit" },
    ["settings.page.layout"] = { module = "settings", label = "A settings page laid out", kind = "layout", visible = "settings.shown", file = "TwichUI_Settings/Window.lua", where = "Layout(view)", every = "per page shown or resized" },
    ["settings.search"] = { module = "settings", label = "Settings search results drawn", kind = "search", visible = "settings.shown", file = "TwichUI_Settings/Window.lua", where = "DrawResults", every = "per search typed" },
    ["settings.search.index"] = { module = "settings", label = "Settings search index built", kind = "rebuild", file = "TwichUI_Settings/Search.lua", where = "Search.Build", every = "once, first search" },
}

-- Code that carries no scope yet. A report whose TwichUI CPU is mostly outside every scope names these as the places
-- to add one next (a scope is `local pt = Perf.on and Perf.Start(id) ... if pt then Perf.Stop(pt) end`, or Perf.Wrap(id, fn)
-- for a hook or a frame's OnEvent, or Perf.Call(id, fn, ...)).
DX.UNSCOPED = {
    "hooksecurefunc / HookScript callbacks on other addons' or Blizzard's frames, except the RestedXP ones named rxp.* (Look.lua, AuctionatorSkin.lua, Arrival.lua, SpeakStoneSkin.lua, WhatsTrainingSkin.lua, gear/Tooltip.lua, gear/Rolls.lua, markers/Bar.lua)",
    "private event frames not listed above: hazard/Alerts.lua, reminders/Display.lua, modules/Training.lua, modules/FriendLogin.lua, chronicle/Recorder.lua, auction/Window.lua, auction/Scan.lua",
    "C_Timer callbacks (modules/Restock.lua, setup/Share.lua, npcs/Share.lua, setup/Group.lua, pins/PingMap.lua, chronicle/Recorder.lua, qol/Guide*.lua)",
    "other OnUpdate scripts: Look.lua (settings-window easing), guides/CozyBagWindow.lua, setup/Window.lua (transfer line), setup/Share.lua, setup/StoredData.lua, setup/Explorer.lua (background jobs), classbars on-bar scripts",
    "tooltip post-calls and bag/inventory scans in gear/, auction/ and modules/ that run from game callbacks rather than TwichUI's event bus",
}

-- The description of an operation id: the module's own (R.Perf.Describe), the catalog's, or one made from the id.
function DX.Op(id)
    local d = Perf.ops[id] or DX.OPS[id]
    if d then return d end
    local event = type(id) == "string" and id:match("^event:(.+)$")
    if event then
        return { module = "events", label = "Callbacks for " .. event, kind = "event", file = "Core.lua",
            where = "R.frame's OnEvent dispatch; the listeners are each module's R:On(\"" .. event .. "\", fn)", every = "per event the client sends" }
    end
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
