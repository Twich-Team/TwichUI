-- TwichUI Fishing in the settings window (docs/fishing.md, "Settings")
-- Describing this page never loads TwichUI Fishing: it is a load-on-demand addon whose saved variable (TwichUIFishingDB)
-- exists only once it has loaded. Going to the page loads it (never in combat: the launcher waits for combat to end), and
-- until it has loaded every control is greyed out with the reason, and reads the default it would have. Every change goes
-- through Fishing's own preferences (Store.Set, through Present.Configure so it applies at once); nothing here writes saved
-- data itself, binds a key, casts, equips or uses anything.

local R = TwichUI
local K = R.SettingsKit

-- The core's launcher, and its helpers only where this install's core has them (the core is a folder of its own too).
local NOPE = {}
local function L()
    local l = R.FishingLauncher
    if type(l) ~= "table" then return nil end
    return setmetatable(NOPE, { __index = function(_, k)
        local v = l[k]
        if type(v) == "function" then return v end
        if k == "State" then return function() return l.Loaded and l.Loaded() and "loaded" or "unloaded" end end
        if k == "KeyText" then return function() return nil end end
        if k == "OpenBindings" then return function() return false, "Esc > Options > Key Bindings > TwichUI" end end
        if k == "Explain" then return function(why) return "couldn't load TwichUI Fishing (" .. tostring(why) .. ")." end end
        return v
    end })
end
-- The TwichUI Fishing this page was written for: its settings interface (Present.SETTINGS_API) at least NEED. TwichUI_Fishing
-- and TwichUI_Settings are separate folders, so one can be older than the other after a partial update: then the page
-- uses nothing of it and asks for an update instead.
local NEED = 1
local function Loaded()
    local f = R.Fishing
    return f and f.ready and f or nil
end
local function Compatible(f)
    local P = f.Present
    return type(P) == "table" and (tonumber(P.SETTINGS_API) or 0) >= NEED and type(f.Fade) == "table"
        and type(f.Fade.Inventory) == "function" and type(f.Ellesmere) == "table"
end
local function Mismatch()
    local f = Loaded()
    return f ~= nil and not Compatible(f)
end
local function Fish()
    local f = Loaded()
    return f and Compatible(f) and f or nil
end
local MISMATCH = "TwichUI Fishing's files are older than TwichUI's settings window. Install the same TwichUI build in every TwichUI folder (TwichUI_Fishing included), then reload."
local function Ready()
    local f = Fish()
    return f ~= nil and not f.Store.held
end
local function Why()
    local l = L()
    local f = Fish()
    if Mismatch() then return MISMATCH end
    if f and f.Store.held then return "Your fishing records were saved by a newer TwichUI, so these settings can't be saved here." end
    local state, why = l and l.State() or "unloaded", nil
    if state == "failed" then _, why = l.State() return why end
    if state == "waiting" or (InCombatLockdown and InCombatLockdown()) then return "TwichUI Fishing loads when combat ends." end
    return "TwichUI Fishing is loading. Its settings appear in a moment."
end

local function Get(path, default)
    local f = Fish()
    if not f then return default end
    local v = f.Store.Get(path)
    if v == nil then return default end
    return v
end

local REFUSED = { held = "your fishing records were saved by a newer TwichUI.", invalid = "that value doesn't fit.",
    ["not-ready"] = "not ready yet.", unknown = "unknown setting." }
local function Set(path, value)
    local f = Fish()
    if not f then return end
    local ok, why = f.Present.Configure(path, value)
    if not ok then R.Print("fishing: " .. (REFUSED[why] or tostring(why))) end
    K.RefreshOverview()
end

local function Gate(row)
    if row then
        row:AddModifyPredicate(Ready)
        row.why = Why
    end
    return row
end

local function Toggle(variable, path, label, tip, default)
    return Gate(K.ProxyToggle("fishing" .. variable, label, tip, default,
        function() return Get(path, default) and true or false end, function(v) Set(path, v and true or false) end))
end

local function Choice(variable, path, label, tip, default, options)
    return Gate(K.Choice("fishing" .. variable, label, tip, K.STRING, default,
        function() return tostring(Get(path, default)) end, function(v) Set(path, v) end, options))
end

-- A percentage slider over a fraction (0.6 -> 60).
local function Percent(variable, path, label, tip, default, lo, hi)
    local setting = K.Proxy("fishing" .. variable, K.NUMBER, label, math.floor(default * 100 + 0.5),
        function() return math.floor((Get(path, default) or default) * 100 + 0.5) end,
        function(v) Set(path, (tonumber(v) or 0) / 100) end)
    return Gate(K.Slider(setting, lo, hi, tip))
end

local function Number(variable, path, label, tip, default, lo, hi)
    local setting = K.Proxy("fishing" .. variable, K.NUMBER, label, default,
        function() return math.floor((Get(path, default) or default) + 0.5) end,
        function(v) Set(path, tonumber(v)) end)
    return Gate(K.Slider(setting, lo, hi, tip))
end

---------------------------------------------------------------------------
-- Words for the status rows (read whenever the page is drawn)
---------------------------------------------------------------------------
local function Duration(sec)
    sec = math.floor(sec or 0)
    if sec >= 3600 then return ("%dh %02dm"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    return ("%dm"):format(math.floor(sec / 60))
end

local function StatusText()
    local l = L()
    local f = Fish()
    if not f then
        if Mismatch() then return "Needs updating" end
        local state = l and l.State() or "unloaded"
        return state == "failed" and "Couldn't load" or (state == "waiting" and "Waiting for combat to end" or "Not loaded yet")
    end
    if f.Store.held then return "Records held (newer TwichUI)" end
    if not f.Store.Get("enabled") then return "Off" end
    local P = f.Present
    if P.Previewing() then return "Previewing Fishing Mode" end
    local s = f.Session.Current()
    local mode = P.On() and "Fishing Mode on" or "On"
    if s then return ("%s · fishing %s, %d catch%s"):format(mode, Duration(f.Session.Elapsed()), s.catches, s.catches == 1 and "" or "es") end
    return mode
end

local function StatusTone()
    local f = Fish()
    if not f then return Mismatch() and "warn" or "quiet" end
    if f.Store.held then return "warn" end
    return f.Store.Get("enabled") and "ok" or "quiet"
end

local function GearText()
    local f = Fish()
    if not f then return "—" end
    local g = f.Gear.Status()
    if g.state == "pending" then return "Waiting to go back on" end
    if g.state == "fishing" then return "Fishing gear on" end
    return "Your own gear"
end

-- Choices of the poles and lures in the bags (and the one chosen, wherever it is).
local function ItemName(id)
    local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id) or (GetItemInfo and GetItemInfo(id))
    return type(name) == "string" and name or ("Item " .. id)
end
local function PoleChoices()
    local list = { { "0", "The best in my bags" } }
    local f = Fish()
    if not f then return list end
    local seen = {}
    local function Add(id) if id and not seen[id] then seen[id] = true; list[#list + 1] = { tostring(id), ItemName(id) } end end
    local worn = f.Gear.Worn(f.MAINHAND)
    if worn and f.Gear.IsPole(worn) then Add(worn) end
    f.Gear.EachBagItem(function(e) if f.Gear.IsPole(e.item) then Add(e.item) end end)
    local want = f.Store.Get("gear.pole")
    if want then Add(want) end
    return list
end
local function LureChoices()
    local list = { { "0", "The best in my bags" } }
    local f = Fish()
    if not f then return list end
    local seen = {}
    for _, e in ipairs(f.Lure.Available()) do
        if not seen[e.item] then seen[e.item] = true; list[#list + 1] = { tostring(e.item), ItemName(e.item) .. " (+" .. e.bonus .. ")" } end
    end
    local want = f.Store.Get("lure.preferred")
    if want and not seen[want] then list[#list + 1] = { tostring(want), ItemName(want) .. " (not in your bags)" } end
    return list
end

local function FadeSummary()
    local f = Fish()
    if not f then return "—" end
    local inv = f.Fade.Inventory()
    local game, eui, added = 0, 0, 0
    for _, g in pairs(inv) do game, eui, added = game + (g.game or 0), eui + (g.EllesmereUI or 0), added + (g.added or 0) end
    local parts = { game .. " of the game's" }
    if eui > 0 then parts[#parts + 1] = eui .. " of EllesmereUI's" end
    if added > 0 then parts[#parts + 1] = added .. " you added" end
    return table.concat(parts, " · ")
end

local function EllesmereText()
    local f = Fish()
    local E = f and f.Ellesmere
    if not E then return "—" end
    local st = E.Status()
    if not st.detected then return "Not installed" end
    local mods = {}
    for _, m in ipairs(st.modules) do if m.loaded then mods[#mods + 1] = m.label end end
    return ("%s%s"):format(st.version and ("Version " .. st.version) or "Detected", #mods > 0 and (": " .. table.concat(mods, ", ")) or "")
end

local function EllesmereDetail()
    local f = Fish()
    local E = f and f.Ellesmere
    if not (E and E.Detected()) then return "Fishing Mode fades the game's own frames. With EllesmereUI installed, it fades EllesmereUI's too." end
    local st = E.Status()
    return ("Found: %d bar frame%s, %s, %s. EllesmereUI's own mouse-over and visibility settings keep working: Fishing Mode never changes them, and while it is on a bar under your pointer still shows.")
        :format(st.found.bars, st.found.bars == 1 and "" or "s", st.found.units > 0 and "unit frames" or "no unit frames",
            st.found.minimap > 0 and "the minimap (hidden completely)" or "no minimap")
end

local function LastFade()
    local f = Fish()
    local l = f and f.Fade.last
    if not l then return "Not faded yet this session" end
    if l.contested > 0 or l.stale > 0 then
        return ("%d put back · %d left to their addon"):format(l.restored, l.contested + l.stale)
    end
    return ("All %d put back"):format(l.restored)
end

local function AddedText()
    local list = Get("fade.extra", false)
    if type(list) ~= "table" or #list == 0 then return "None" end
    return table.concat(list, ", ")
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local function OnShow()
    local l = L()
    if l and not l.Loaded() and not (InCombatLockdown and InCombatLockdown()) then
        local ok, why = l.Load()
        if not ok and why ~= "COMBAT" then R.Print("%s", l.Explain(why)) end
    end
end

K.Page({
    key = "fishing", icon = "fishing", name = "Fishing", order = 47, group = "everyday",
    description = "One key that fishes for you to press, Fishing Mode's calm, immersive view, and a record of your catches.",
    keywords = "fishing fish fisher angling pole rod lure bait clam pearl bobber cast reel key binding immersive compact classic "
        .. "camera zoom shoulder offset fade fading hide interface ellesmere ellesmereui action bars unit frames minimap hud cast bar "
        .. "catch list notifications toast controller gamepad vibration preview move recover restore gear",
    overview = { label = "Fishing", tip = "One key to fish with, Fishing Mode, and your catches.",
        when = function() return L() ~= nil end, status = StatusText },
    when = function() return L() ~= nil end,
    onShow = OnShow,
    build = function()
        -------------------------------------------------------------------------------------------------------------
        K.Header("Fishing", "Press your Fishing key to equip your pole, apply a lure, cast, reel in, or open a clam: one step for each press, always your own press. TwichUI never binds a key or acts on its own.")
        K.Status("Status", StatusText, function()
            local f = Fish()
            if not f then return Why() end
            return "Type /tui fish for the full report."
        end, nil, StatusTone)
        Gate(K.ProxyToggle("fishingEnabled", "TwichUI Fishing",
            "The fishing key, Fishing Mode and your fishing records. Off: the key does nothing and nothing is recorded; your records are kept.", true,
            function() return Get("enabled", true) and true or false end,
            function(on)
                local f = Fish()
                if not f then return end
                local ok, why = f.Main.SetEnabled(on)
                if not ok then R.Print("fishing: " .. (REFUSED[why] or tostring(why))) end
                K.RefreshOverview()
            end))
        K.Status("Your Fishing key", function() local l = L(); return l and l.KeyText() or "Not bound" end,
            function()
                local l = L()
                if l and l.KeyText() then return "Press it to equip your pole, apply a lure, cast, reel in, or open a clam." end
                return "Bind \"Fishing: the next step\" in Key Bindings > TwichUI to fish with one key (a gamepad button works too)."
            end, nil, function() local l = L(); return (l and l.KeyText()) and "ok" or "warn" end)
        K.Status("Fishing Mode keys", function()
            local l = L()
            local mode = l and l.KeyText("TWICHUI_FISHING_MODE")
            local reveal = l and l.KeyText("TWICHUI_FISHING_REVEAL")
            if not mode and not reveal then return "Not bound" end
            return ("%s to start or leave · %s to show the interface"):format(mode or "—", reveal or "—")
        end, function() return "Optional: \"Fishing Mode: on or off\" and \"Fishing Mode: reveal the interface (hold)\"." end)
        K.Button("Key bindings", "Open Key Bindings", function()
            local l = L()
            local ok, where = l.OpenBindings()
            if ok then K.CloseOptions() else R.Print("fishing: open the game's key bindings at %s.", where) end
        end, "Opens the game's own Key Bindings. Fishing's keys are under TwichUI. TwichUI never binds a key for you.")
        local mode = K.Button("Fishing Mode", function()
            local f = Fish()
            return f and (f.Present.On() or f.Present.Previewing()) and "Leave Fishing Mode" or "Start Fishing Mode"
        end, function()
            local f = Fish()
            if not f then return end
            local ok, why = f.Present.Toggle()
            if ok == false and why == "combat" then R.Print("fishing: not during combat.") end
            if ok == false and why == "classic" then R.Print("fishing: choose Immersive or Compact under Fishing Mode first.") end
            K.RefreshOverview()
        end, "Starts or leaves Fishing Mode now. It also starts by itself with your first cast, if you allow that below.")
        Gate(mode)
        Gate(K.Button("Fishing Journal", "Open Fishing Journal", function()
            local f = Fish()
            if not (f and f.JournalUI) then R.Print("fishing: the journal isn't available; reload so TwichUI Fishing and TwichUI match.") return end
            if f.JournalUI.Open() then K.CloseOptions() end
        end, "Your catches, sessions, places and treasures, with the game's own icons. Also /tui fish journal."))
        K.Status("Your gear", GearText, function()
            local f = Fish()
            if f and f.Gear.State() == "pending" then
                local key = L().KeyText()
                return key and ("Press " .. key .. ", or use Put things back, to wear your own gear again.") or "Use Put things back to wear your own gear again."
            end
        end, nil, function() local f = Fish(); return f and f.Gear.State() == "pending" and "warn" or nil end)
        Gate(K.Button("Put things back", "Put things back", function()
            local f = Fish()
            if not f then return end
            f.Present.Recover()
            local g = f.Gear.State() ~= "none" and f.Gear.Restore("command") or nil
            R.Print("fishing: the camera and the interface are back%s.", g == "combat" and "; your gear goes back after combat"
                or (g == "unsupported" and "; press your Fishing key to put your gear back" or (g and "; your own gear is going back on" or "")))
            K.RefreshOverview()
        end, "Puts the camera and the interface back as you had them, whatever changed them since, leaves Fishing Mode, and puts your own gear back on (or tells you how)."))

        -------------------------------------------------------------------------------------------------------------
        K.Header("Fishing assistance", "What the Fishing key prepares before it casts. Each is one press of your own key.")
        Toggle("ManageGear", "gear.manage", "Manage fishing equipment",
            "Equip your fishing pole (or your fishing outfit) on a press of the key, and keep track of the gear it replaced.", true)
        Gate(K.Choice("fishingPole", "Preferred fishing pole", "The pole the key equips. The best one in your bags is used when it is missing.", K.STRING, "0",
            function() local v = Get("gear.pole", false); return v and tostring(v) or "0" end,
            function(v) local id = tonumber(v); Set("gear.pole", (id and id > 0) and id or false) end, PoleChoices))
        Toggle("RestoreGear", "gear.restoreOnEnd", "Put my own gear back when I stop fishing",
            "When the session ends your own weapons and gear go back on. If the game doesn't allow it at that moment, your next press of the key does it.", true)
        Toggle("CombatWeapons", "gear.combatWeapons", "Weapons back on a press in combat",
            "In combat with the pole on, a press of the Fishing key puts your weapons back.", true)
        Toggle("LureAuto", "lure.auto", "Apply a lure when needed",
            "When the pole has no lure, the next press applies one from your bags before casting.", true)
        Gate(K.Choice("fishingLure", "Preferred lure", "The lure the key applies.", K.STRING, "0",
            function() local v = Get("lure.preferred", false); return v and tostring(v) or "0" end,
            function(v) local id = tonumber(v); Set("lure.preferred", (id and id > 0) and id or false) end, LureChoices))
        Toggle("LureAlternative", "lure.alternative", "Use another lure when mine runs out",
            "When your preferred lure isn't in your bags, use the best one that is.", false)
        Choice("Containers", "containers.mode", "Clams and other containers",
            "Queued: they open on a press of your key between casts. Automatic: they open by themselves after a catch, where the game allows it (if it refuses once, TwichUI goes back to the queue). Off: they're only recorded.",
            "queue", { { "queue", "Queued for my key" }, { "auto", "Automatic, if allowed" }, { "off", "Off (record only)" } })
        Toggle("OpenWithKey", "containers.openWithKey", "Open queued clams with the Fishing key",
            "Between casts, a press of the Fishing key opens the oldest queued clam first.", true)

        -------------------------------------------------------------------------------------------------------------
        K.Header("Estimated values", "Current listing estimates, not income. Workshop stays optional and is never loaded by a catch. Missing prices remain unavailable; * marks a known subtotal.")
        Toggle("Economy", "economy.enabled", "Display estimated values", "Show current-market estimates in Fishing Mode and the Journal.", true)
        Choice("Valuation", "economy.method", "Valuation method", "Workshop listing methodologies. All items use one selected reference market or one local auction house; missing reference prices are not mixed with local prices.", "market",
            { { "market", "Market Value (14 days)" }, { "recent", "Recent Price" }, { "historical", "Historical Value (60 days)" }, { "min", "Lowest listing" } })
        Toggle("VendorValue", "economy.vendor", "Display vendor values", "Vendor sell value is shown separately from auction estimates when the item data is available.", false)
        Toggle("GoldHour", "economy.perHour", "Display estimated gold per hour", "Known estimated value divided by fishing duration, not realized earnings.", true)
        Toggle("Provisional", "economy.provisional", "Value unopened containers provisionally", "Untouched queued containers only. Opened and partially opened shells are excluded; confirmed contents replace their estimates.", true)
        K.Status("Pricing source", function()
            local w = R.Workshop
            if not (w and w.Pricing and w.Active and w.Active()) then return "Workshop unavailable or not loaded" end
            local source = w.Pricing.Source()
            local m = source.market
            return (source.label or "No market observations") .. (m and m.at and (" · " .. Duration(math.max(0, time() - m.at)) .. " old") or "")
        end, function() return "Load Workshop separately to make pricing available. References follow the Companion-selected market; local observations are used only when no eligible reference market exists. Stale or missing reference data is explained by Workshop. Lure purchase costs were not recorded, so net income cannot be reconstructed." end)

        K.Header("Fishing Mode", "How fishing looks: an immersive view with a calmer screen, a compact cast bar, or nothing extra.")
        Choice("Mode", "present.mode", "Presentation",
            "Immersive: the camera comes closer, the interface fades, and the cast bar, your catches and notices show. Compact: the cast bar and notices only. Classic: the Fishing key alone.",
            "immersive", { { "immersive", "Immersive" }, { "compact", "Compact" }, { "classic", "Classic" } })
        Toggle("Auto", "present.auto", "Start Fishing Mode when I cast",
            "Fishing Mode starts with your first line. Off: only when you ask (the key or the button above).", true)
        local camera = Toggle("Camera", "camera.enabled", "Move the camera",
            "Immersive only: the camera moves once to a fishing distance, and back afterwards. Your own zooming is never corrected, and a distance you chose meanwhile is kept.", true)
        K.Note(camera, function()
            local f = Fish()
            if f and not f.Camera.Supported().zoom then return "This game client doesn't let addons move the camera's distance, so the camera is left alone.", "warn" end
        end)
        Number("Zoom", "camera.zoom", "Camera distance (yards)", "How far the camera sits from you while fishing. The game's own limit applies.", 7, 1, 30)
        local offset = Gate(K.Choice("fishingOffset", "Camera to the side",
            "Moves the view over your shoulder, using the game's shoulder-offset setting. The game may ask you once to confirm an experimental camera setting; TwichUI never answers it for you. Put back when Fishing Mode ends.",
            K.STRING, "0", function() return tostring(Get("camera.offset", 0)) end, function(v) Set("camera.offset", tonumber(v) or 0) end,
            { { "0", "Off" }, { "0.5", "A little to the right" }, { "1", "To the right" }, { "-0.5", "A little to the left" }, { "-1", "To the left" } }))
        K.Note(offset, function()
            local f = Fish()
            if f and not f.Camera.Supported().offset then return "Not offered by this game client.", "warn" end
        end)
        Toggle("Fade", "fade.enabled", "Fade the interface", "Immersive only: the parts of the interface you don't need while fishing fade out, and come back afterwards. Choose which below.", true)
        Toggle("Motion", "present.motion", "Smooth transitions", "Fades and notices move gently. Off: they change at once (also off with Reduce motion).", true)
        Toggle("Prompts", "present.prompts", "Show key prompts", "The keys to fish, show the interface and leave, under the cast bar. Gamepad buttons are named while you use a gamepad.", true)
        local vibrate = Toggle("Vibrate", "present.vibrate", "Gamepad pulse on a catch",
            "A short, light pulse when a catch is confirmed (never on a bite: the game gives no bite signal). Not yet checked on WoW: Forever.", false)
        K.Note(vibrate, function()
            if not (rawget(_G, "C_GamePad") and C_GamePad.SetVibration) then return "This game client offers no gamepad vibration to addons." end
        end)
        Toggle("Brand", "present.brand", "Show the TwichUI Fishing emblem", "The emblem at the top left in immersive Fishing Mode.", true)

        -------------------------------------------------------------------------------------------------------------
        K.Header("Interface fading", "What fades in immersive Fishing Mode. Only how visible a frame is changes, never its settings; each frame returns as its addon wants it, and a frame under your pointer still shows.")
        Toggle("FadeBars", "fade.bars", "Action bars", "Action, stance and pet bars, the micro menu and bags, and the experience bar.", true)
        Toggle("FadeUnits", "fade.units", "Unit frames", "Your own, your target's and your focus's frames, your pet's, and party frames.", true)
        Toggle("FadeMinimap", "fade.minimap", "Minimap", "Hides the minimap completely in Immersive Fishing Mode (map, arrow, markers, buttons). It comes back when you reveal the interface or leave.", true)
        Toggle("FadeMeters", "fade.meters", "Damage meters", "EllesmereUI's damage meters, and Details, Recount and Skada if you use them. Chat always stays visible.", true)
        Toggle("FadeTwichui", "fade.twichui", "TwichUI camping bar", "The camping bar and its sleeping bag bar, if they are on.", true)
        Toggle("FadePanels", "fade.panels", "Other panels", "The quest tracker, buffs and debuffs, and the durability figure.", false)
        Toggle("FadeNotices", "fade.notices", "Quiet TwichUI's own notices",
            "TwichUI's notification cards, reminders and glows stay away while you fish. Your own Quiet screen switch is not changed.", true)
        Percent("FadeAlpha", "fade.alpha", "Faded opacity (%)", "How visible faded parts stay: 0 is gone, 60 is still easy to see.", 0, 0, 60)
        local eui = Toggle("Ellesmere", "fade.ellesmere", "Include EllesmereUI",
            "Fades EllesmereUI's action bars, unit frames, minimap and the rest, found automatically. You don't need to know any frame names.", true)
        K.Note(eui, function()
            local f = Fish()
            if f and f.Ellesmere and not f.Ellesmere.Detected() then return "EllesmereUI isn't installed or enabled." end
        end)
        K.Status("EllesmereUI", EllesmereText, EllesmereDetail)
        K.Status("Fishing Mode can fade", FadeSummary, function()
            return "Frames found now, counting only the groups switched on. /tui fish fade lists each one."
        end)
        K.Status("Last time", LastFade, function() return "How the interface came back the last time Fishing Mode ended." end)
        K.Status("Frames you added", AddedText, function()
            return "Another addon's frame, by its name: /tui fish fade add <FrameName> (or remove)."
        end)
        local clear = Gate(K.Button("Frames you added", "Clear the list", function() Set("fade.extra", false) end,
            "Stops fading the frames you added by name."))
        if clear then clear:AddShownPredicate(function() local v = Get("fade.extra", false); return type(v) == "table" and #v > 0 end) end

        -------------------------------------------------------------------------------------------------------------
        K.Header("Fishing HUD", "The cast bar, your catches and the catch notices. Move them where you like, and try them here without fishing.")
        Toggle("CastBar", "castbar.enabled", "Show the cast bar", "The fishing timer near the bottom of the screen, with your session's figures.", true)
        Toggle("List", "list.enabled", "Show this session's catches", "Your catches on the right of the screen (immersive only).", true)
        Toggle("Toasts", "toast.enabled", "Show catch notifications", "A short notice for each catch, left of the middle of the screen.", true)
        Toggle("JournalSummary", "journal.summary", "Show a summary when a session ends", "A Session Summary card with the catches of a session you stopped or left idle (never during combat). Open the whole Journal from the Fishing tab.", true)
        Percent("JournalScale", "journal.scale", "Journal size", "How large the Fishing Journal window and the session summary are. Drag the Journal by its title to move it; its place is remembered.", 1, 60, 140)
        Gate(K.Button("Journal position", "Reset Journal position", function()
            local f = Fish()
            if not (f and f.JournalUI) then return end
            f.JournalUI.ResetPosition()
            R.Print("fishing: the Journal is back in the middle of the screen.")
        end, "Puts the Fishing Journal back in the middle of the screen, at the same size. Use it if you moved the window somewhere awkward."))
        Percent("CastScale", "castbar.scale", "Cast bar size (%)", "The cast bar's size.", 1, 60, 160)
        Percent("ListScale", "list.scale", "Catch list size (%)", "The catch list's size.", 1, 60, 160)
        Percent("ToastScale", "toast.scale", "Notification size (%)", "The notices' size.", 1, 60, 160)
        Number("Rows", "list.rows", "Catches shown", "At most this many kinds of catch; then \"+N more\".", 6, 3, 12)
        Choice("Sort", "list.sort", "Order catches by", "Most caught first, the latest first, or by name.", "count",
            { { "count", "Most caught" }, { "recent", "Latest" }, { "name", "Name" }, { "value", "Highest estimated value" } })
        -- list.value is stored as "show" / "hide"
        Gate(K.ProxyToggle("fishingValueArea", "Show the catch-list value area",
            "Shows estimated value when Workshop pricing is available. Off: no value area.", true,
            function() return Get("list.value", "show") ~= "hide" end, function(v) Set("list.value", v and "show" or "hide") end))
        Gate(K.Button("Place on screen", function()
            local f = Fish(); return f and f.Present.Unlocked() and "Lock in place" or "Move on screen"
        end, function()
            local f = Fish()
            if not f then return end
            local unlock = not f.Present.Unlocked()
            if not f.Present.Unlock(unlock) then R.Print("fishing: not during combat.") return end
            if unlock then K.CloseOptions(); R.Print("fishing: drag the cast bar, catch list and notice; then /tui fish move, or this button, to lock them.") end
            K.RefreshOverview()
        end, "Shows the cast bar, catch list and a notice with sample figures so you can drag them."))
        Gate(K.Button("Starting places", "Reset positions", function()
            local f = Fish()
            if not f then return end
            local D = f.Store.DEFAULTS
            for _, group in ipairs({ "castbar", "list", "toast" }) do
                Set(group .. ".x", D[group].x)
                Set(group .. ".y", D[group].y)
            end
        end, "Puts the cast bar, catch list and notices back where they start."))
        Gate(K.Button("Try Fishing Mode", function()
            local f = Fish(); return f and f.Present.Previewing() and "Stop the preview" or "Preview Fishing Mode"
        end, function()
            local f = Fish()
            if not f then return end
            if f.Present.Previewing() then f.Present.EndPreview("player") K.RefreshOverview() return end
            local ok, why = f.Present.Preview({ done = function(how)
                if how == "timeout" or how == "player" then R:OpenSettings("fishing") end
            end })
            if ok then
                K.CloseOptions()
                R.Print("fishing: previewing Fishing Mode for %d seconds with sample figures (nothing is cast or used). Your Fishing Mode key or /tui fish preview stops it.", f.Present.PREVIEW)
            else
                R.Print("fishing: %s", ({ live = "Fishing Mode is on: what you see is the real thing.", combat = "not during combat.",
                    classic = "choose Immersive or Compact first: Classic shows nothing extra.", off = "turn TwichUI Fishing on first." })[why] or tostring(why))
            end
        end, "Shows Fishing Mode for 15 seconds with sample figures: the camera, the faded interface and the HUD. Nothing is cast, equipped or used, and everything goes back afterwards."))
    end,
})
