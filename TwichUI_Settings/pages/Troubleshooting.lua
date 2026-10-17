-- TwichUI settings: Troubleshooting (diag/: a status snapshot and support information to copy, the full report,
-- and optional temporary tracing).

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "troubleshooting", name = "Troubleshooting", order = 110, group = "config",
    description = "How TwichUI and its optional addons look right now, support information to copy when something does not work, and optional temporary tracing. Nothing is sent anywhere.",
    keywords = "diagnostics report bug error debug trace log status support version integration ellesmere restedxp copy",
    when = function() return R.Diag ~= nil and R.DiagWindow ~= nil end,
    overview = {
        label = "Troubleshooting", tip = "Status, support information to copy when something does not work, and optional temporary tracing.",
        status = function() return R.Diag.Tracing() and (R.GREEN .. "Tracing on|r") or (R.GREY .. "Tracing off|r") end,
    },
    -- The snapshot is taken here, each time the window goes to this page (and again on Refresh, or after a profile or
    -- switch change while the page is shown); the settings closing drops it.
    onShow = function()
        if R.DiagStatus then R.DiagStatus.Invalidate() end
    end,
    build = function()
        local Header, Button = K.Header, K.Button
        local Diag, Window = R.Diag, R.DiagWindow
        local St, Support = R.DiagStatus, R.SupportWindow

        if St and Support then
            -- One snapshot at a time (St.Current), and the summary worked out from it once.
            local summarized, rows
            local function Summary()
                local snap = St.Current()
                if snap ~= summarized then summarized, rows = snap, St.Summary(snap) end
                return rows
            end
            local function Line(id)
                for _, r in ipairs(Summary()) do if r.id == id then return r end end
                return {}
            end
            local function Drop()
                summarized, rows = nil, nil
                St.Invalidate()
            end
            -- A profile or switch change can change what the snapshot says: take it again, and redraw if this page is up.
            local function Changed()
                Drop()
                local UI = R.SettingsUI
                if UI and UI.IsShown() and UI.Selected() == "troubleshooting" then K.RefreshOverview() end
            end
            R.OnSettingsClosed(Drop)
            R.Switches.OnChange(Changed)
            if R.Profiles and R.Profiles.OnChange then R.Profiles.OnChange(Changed) end

            Header("Status", "A snapshot of how TwichUI and its optional addons look from here, taken when this page opens or when you press Refresh. Reading it changes no setting, turns no addon on and loads nothing. It says what the game and each addon report, not that every feature works.")
            local function Info(id, label, tip, tone)
                K.Status(label, function() return Line(id).value end, function() return Line(id).detail end, tip,
                    function()
                        local line = Line(id)
                        if line.warn then return "warn" end
                        return tone and tone(line) or nil
                    end)
            end
            Info("version", "TwichUI version", "The version the addon list records for TwichUI.")
            Info("channel", "Release channel", "alpha or beta when the version carries the build suffix those builds are given; otherwise Unknown (a plain version could be a stable release or an unpackaged copy).",
                function(line) return line.value == "Unknown" and "quiet" or nil end)
            Info("client", "Game client", "The game version and build the client reports.")
            Info("core", "Core", "Whether TwichUI's own start-up finished: saved data loaded, configuration ready, start-up steps run without errors.",
                function(line) return line.value == "Started" and "ok" or nil end)
            Info("settings", "Settings window", "TwichUI_Settings is a separate addon loaded the first time the settings open. Seeing this page means it is loaded now; it says nothing about start-up.")
            Info("pending", "Reload needed", "Changes that take effect only after a reload, as the settings window tracks them. Work held back for combat is not tracked as pending.",
                function(line) return line.value == "None" and "quiet" or nil end)
            Button("Status snapshot", "Refresh", function()
                St.Refresh()
                K.RefreshOverview()
            end, "Takes the snapshot again from how things are now. Nothing is changed, turned on or loaded.")
            Button("Support information", "Copy support information", function()
                K.CloseOptions()
                Support.Show()
            end, "Opens a short report of this status in a window you can read first and then copy from (it is selected; press Ctrl+C). The game gives an addon no clipboard, so nothing is copied for you. It lists versions, integration states and which features are on, and leaves out character, realm, guild and friend names, chat, Chronicle entries, saved data, file paths and anything you typed. Nothing is sent anywhere.")

            Header("Optional integrations", "What TwichUI can see of the addons it works with. None of them is required, and one that is not installed is not a problem. Each line says what the game and the addon report, not that the feature works; a line shows in the warning color only when something you chose can't work as set.")
            local function Cap(id)
                return St.Current().caps[id] or {}
            end
            local function Group(key)
                return St.Current().groups[key] or {}
            end
            for _, g in ipairs(St.GROUPS) do
                if g.fold then
                    local row = K.Status(g.title,
                        function() return St.PresenceLabel(Group(g.key)) end,
                        function() return St.GroupDetail(Group(g.key)) end,
                        g.title .. " as the addon list shows it. While it is not loaded, the lines for what it provides are folded into this one, unless you have chosen something that needs it.",
                        function() return "quiet" end)
                    if row then row:AddShownPredicate(function() return Group(g.key).presence ~= "loaded" end) end
                end
                for _, cap in ipairs(g.caps) do
                    local label = g.fold and (g.title .. ": " .. cap.label) or cap.label
                    local row = K.Status(label,
                        function() return Cap(cap.id).stateLabel end,
                        function() return Cap(cap.id).detail end,
                        cap.label .. ": " .. cap.affects .. ". A read-only status; nothing is changed or loaded to read it.",
                        function()
                            local rec = Cap(cap.id)
                            if rec.actionable then return "warn" end
                            if rec.state == "available" then return "ok" end
                            if rec.state == "not-installed" or rec.state == "off" or rec.state == "not-applicable" then return "quiet" end
                            return nil
                        end)
                    if row and g.fold then
                        row:AddShownPredicate(function() return Group(g.key).presence == "loaded" or Cap(cap.id).wanted == true end)
                    end
                end
            end
        end

        Header("Full report", "A report of how TwichUI is set up and what each part says about itself, to copy and share when something does not work. It is built on your computer when you ask for it. Nothing is sent anywhere.")
        Button("Troubleshooting report", "Open", function()
            K.CloseOptions()
            Window.Show()
        end, "Opens the report in a window you can read and copy from (click in the text, Ctrl+A, Ctrl+C). It lists settings, module states, counts and reason codes. It leaves out character, realm, guild, friend and BattleTag names, chat, Chronicle entries and your configuration. Same as typing /tui diagnostics.")
        Header("Temporary tracing", "Off until you start it. While on, TwichUI records short notes about its own decisions (why a friend card was skipped, what the food buttons chose) in memory, to include in the report. It stops by itself after 15 minutes, is never saved, and is gone after a reload.")
        local function TracingName() return "Tracing   " .. (Diag.Tracing() and (R.GREEN .. "On|r") or (R.GREY .. "Off|r")) end
        local tracing = Button(TracingName(), "Start", function()
            if Diag.Tracing() then Diag.Stop("manual") else Diag.Start() end
        end, "Starts or stops tracing. Start it, reproduce the problem, then open the report. Same as /tui diagnostics start and /tui diagnostics stop.")
        if tracing and tracing.data then
            tracing.data.buttonText = function() return Diag.Tracing() and "Stop" or "Start" end
            Diag.OnChange(function()
                tracing.data.name = TracingName()
                K.RefreshOverview()
            end)
        end
        Button("Collected records", "Clear", function() Window.Command("clear") end,
            "Forgets the trace records and recent errors kept so far, on this computer only. Tracing, if on, carries on. Same as /tui diagnostics clear.")
    end,
})
