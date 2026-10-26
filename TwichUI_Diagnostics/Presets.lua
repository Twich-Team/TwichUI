-- TwichUI Diagnostics: capture presets
-- A preset chooses what is collected, how often, and which operations are timed. It never changes a TwichUI setting,
-- turns a feature on or off, equips or uses anything, sends anything to a group, or makes up events: you do the thing
-- you want measured, the capture watches. Every preset shows what it costs before it starts.
--
--   mode           "standard" or "focused" (a focused trace also takes call paths for slow calls)
--   minutes        default length; the capture stops by itself then (MAX_MINUTES at most)
--   memorySeconds  between per-addon memory reads (UpdateAddOnMemoryUsage is costly: never under 5)
--   gaugeSeconds   between reads of the gauges (listener counts, pools, caches) and the profiler's counters
--   filter         operation id prefixes timed (nil: all); event callbacks are "event:"
--   gauges         gauge groups read (nil: all)

local R = TwichUI
local DX = R.DiagnosticsKit

DX.MAX_MINUTES = 30
DX.MIN_MEMORY_SECONDS = 5

DX.PRESETS = {
    {
        key = "general", name = "General performance", mode = "standard", minutes = 5, memorySeconds = 15, gaugeSeconds = 5,
        what = "Play normally. Frame intervals, the time the client puts down to TwichUI each frame, TwichUI's own operations and events, and memory.",
        cost = "Low: four client reads each frame, a little bookkeeping per TwichUI operation, a memory read every 15 seconds (the costly part).",
    },
    {
        key = "map", name = "Map and NPC tracking", mode = "standard", minutes = 3, memorySeconds = 15, gaugeSeconds = 2,
        filter = { "npcs.", "pins.", "map.", "nav.", "event:" }, gauges = { "core", "map" },
        what = "Open the world map, move around it, search vendors and trainers, change what is shown, close it; repeat.",
        cost = "Low: as General, with the map's pools and marker counts read every 2 seconds and each map close.",
    },
    {
        key = "settings", name = "Settings responsiveness", mode = "standard", minutes = 3, memorySeconds = 10, gaugeSeconds = 2,
        filter = { "settings.", "event:", "core." }, gauges = { "core", "settings" },
        what = "Open the settings, move between pages, search, close them; do it several times.",
        cost = "Low: listener and page counts read every 2 seconds and each time the settings close; memory every 10 seconds.",
    },
    {
        key = "group", name = "Group combat", mode = "standard", minutes = 10, memorySeconds = 30, gaugeSeconds = 5,
        gauges = { "core", "group" },
        what = "Start before a pull and play: reminders, Healer Watch, class bars and the event bus in combat. Nothing is sent to your group.",
        cost = "Low: memory only every 30 seconds so it disturbs combat as little as it can; nothing heavy runs until combat ends.",
    },
    {
        key = "memory", name = "Memory and lifecycle", mode = "standard", minutes = 10, memorySeconds = 5, gaugeSeconds = 5,
        what = "Do one thing several times (open and close a window, change a page) and watch memory, listeners, pools and caches over the cycles.",
        cost = "Moderate: the client's memory update every 5 seconds, which can show as a small hitch each time.",
    },
    {
        key = "focused", name = "Focused trace", mode = "focused", minutes = 2, memorySeconds = 15, gaugeSeconds = 5, stacks = true,
        what = "One subsystem in detail: only its operations are timed, and the slowest calls keep the call path that led to them.",
        cost = "Higher for that subsystem: a call path for a new slowest call, at most one a second. Optionally the client's own allocation measurement around each call.",
    },
    {
        key = "startup", name = "Start-up (armed)", mode = "standard", minutes = 1, memorySeconds = 10, gaugeSeconds = 2, hidden = true,
        what = "Recorded from TwichUI's ADDON_LOADED after a reload you made, for one minute.",
        cost = "As General, from the first moment TwichUI's code can watch. TwichUI's files loading before that are not seen.",
    },
}

-- A focused trace's subsystems: operation prefixes and the gauges that go with them.
DX.SUBSYSTEMS = {
    { key = "npcs", label = "Vendors and trainers", filter = { "npcs." }, gauges = { "core", "map" } },
    { key = "map", label = "Pins and the world map", filter = { "pins.", "map.", "nav." }, gauges = { "core", "map" } },
    { key = "reminders", label = "Reminders", filter = { "reminders." }, gauges = { "core", "group" } },
    { key = "healer", label = "Healer Watch", filter = { "healer." }, gauges = { "core", "group" } },
    { key = "settings", label = "Settings window", filter = { "settings." }, gauges = { "core", "settings" } },
    { key = "events", label = "Event bus and start-up", filter = { "event:", "core." }, gauges = { "core" } },
}

function DX.Preset(key)
    for _, p in ipairs(DX.PRESETS) do if p.key == key then return p end end
    return nil
end

function DX.Subsystem(key)
    for _, s in ipairs(DX.SUBSYSTEMS) do if s.key == key then return s end end
    return nil
end
