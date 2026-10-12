-- TwichUI options: Troubleshooting (diag/: the report to copy, and optional temporary tracing).

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "troubleshooting", name = "Troubleshooting", order = 110,
    when = function() return R.Diag ~= nil and R.DiagWindow ~= nil end,
    overview = {
        label = "Troubleshooting", tip = "A report to copy when something does not work, and optional temporary tracing.",
        status = function() return R.Diag.Tracing() and (R.GREEN .. "Tracing on|r") or (R.GREY .. "Tracing off|r") end,
    },
    build = function()
        local Header, Button = K.Header, K.Button
        local Diag, Window = R.Diag, R.DiagWindow
        Header("Troubleshooting", "A report of how TwichUI is set up and what each part says about itself, to copy and share when something does not work. It is built on your computer when you ask for it. Nothing is sent anywhere.")
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
                if SettingsPanel and SettingsPanel:IsShown() and SettingsPanel.RepairDisplay then SettingsPanel:RepairDisplay() end
            end)
        end
        Button("Collected records", "Clear", function() Window.Command("clear") end,
            "Forgets the trace records and recent errors kept so far, on this computer only. Tracing, if on, carries on. Same as /tui diagnostics clear.")
    end,
})
