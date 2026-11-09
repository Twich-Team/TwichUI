-- Quiet screen (QuietScreen.lua): a session-only switch. The core is checked here, and its effect on the notification
-- coordinator (modules/Notify.lua) with stand-in cards; Reminders, glows, Healer Watch, Return the Favor and the data bar
-- menu are checked in their own tests (test_reminders_enchant_sound.lua, test_bar_glows.lua, test_healer_watch.lua,
-- test_return_the_favor.lua, test_settings_broker.lua).
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
c.NOW = 1000
c.GetTime = function() return c.NOW end
local ERRORS = {}
c.geterrorhandler = function() return function(e) ERRORS[#ERRORS + 1] = tostring(e) end end
c.TwichUIDB = { modules = {} }
local chunk = assert(loadfile(ROOT .. "modules/Notify.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local Q, N = R.QuietScreen, R.Notify

-- 1. The switch: off at the start, not saved, the same state again does nothing, listeners hear changes once each.
do
  assert(Q and Q.On() == false, "starts off")
  local heard = {}
  local function Hear(on) heard[#heard + 1] = on end
  Q.OnChange(Hear); Q.OnChange(Hear)
  Q.OnChange("not a function")
  Q.Set(true); Q.Set(true)
  assert(Q.On() and #heard == 1 and heard[1] == true, "told once, however often it is set")
  assert(Q.Toggle() == false and not Q.On() and #heard == 2 and heard[2] == false, "Toggle returns the new state")
  Q.Set(nil); assert(#heard == 2, "nil is off, and off again changes nothing")
  Q.OnChange(function() error("a failing listener") end)
  local after = 0
  Q.OnChange(function() after = after + 1 end)
  Q.Set(true)
  assert(after == 1 and Q.On(), "a failing listener does not stop the rest")
  assert(#ERRORS == 1 and ERRORS[1]:find("a failing listener", 1, true), "and the failure is reported, not swallowed")
  Q.Set(false)
  ERRORS = {}
  assert(Q.Snapshot().on == false and Q.Snapshot().changes >= 4, "the snapshot has counts only")
  for k in pairs(c.TwichUIDB) do assert(not tostring(k):lower():find("quietscreen"), "nothing saved") end
end

-- 2. Notify: while quiet a real notice is refused; one already waiting or showing is let go when it goes on; a preview is
--    not affected; nothing is held back to be shown afterwards.
do
  local shownLog, dismissed, drops = {}, 0, {}
  N.Register("quiettest", {
    label = "Quiet test",
    show = function(p, ctx) shownLog[#shownLog + 1] = p.id .. (ctx.preview and "*" or ""); return true end,
    dismiss = function() dismissed = dismissed + 1; N.Finished("quiettest") end,
    bounds = function() return 0, 0, 10, 10 end,
    hold = function() return 5 end,
    sample = function() return { id = "sample" } end,
  })
  N.Register("quietother", {
    label = "Quiet other",
    show = function(p) shownLog[#shownLog + 1] = "other:" .. p.id; return true end,
    dismiss = function() N.Finished("quietother") end,
    bounds = function() return 500, 500, 510, 510 end,
    hold = function() return 5 end,
  })
  c.FireEvent("PLAYER_ENTERING_WORLD", false, false)
  local function Send(kind, id, extra)
    local req = { kind = kind, id = id, payload = { id = id }, onDrop = function(why) drops[#drops + 1] = kind .. ":" .. id .. "=" .. why end }
    for k, v in pairs(extra or {}) do req[k] = v end
    return N.Submit(req)
  end

  -- a card is showing and another waits behind it (same place); then the switch goes on
  assert(Send("quiettest", "a"), "shown at once when not quiet")
  assert(Send("quiettest", "b", { replace = false }), "a second one waits behind it")
  assert(#N.State().active == 1 and #N.State().waiting == 1)
  Q.Set(true)
  local s = N.State()
  assert(#s.active == 0 and #s.waiting == 0, "quiet on: the showing and the waiting real notices are let go")
  assert(dismissed == 1 and drops[#drops] == "quiettest:b=quiet", "the showing one is dismissed and the waiting one told why: " .. tostring(drops[#drops]))

  local ok, why = Send("quiettest", "c")
  assert(ok == false and why == "quiet", "a real notice is refused while quiet")
  assert(N.Snapshot().refused.quiet == 1, "and counted")
  assert(#N.State().waiting == 0 and #N.State().active == 0, "nothing queued behind it")

  -- previews are the player asking
  local before = #shownLog
  assert(N.Preview("quiettest"), "a preview is accepted while quiet")
  assert(#shownLog == before + 1 and shownLog[#shownLog]:find("%*$"), "and shown")
  N.ClearPreviews()

  -- off: what was refused does not come back; new ones are shown
  Q.Set(false)
  assert(#N.State().active == 0 and #N.State().waiting == 0, "quiet off: nothing from the quiet is shown afterwards")
  assert(Send("quiettest", "c"), "and new notices are accepted again")
  assert(N.State().active[1] == "quiettest:c")
  N.Cancel("quiettest")

  -- a preview showing when it goes on stays
  assert(N.Preview("quiettest"))
  Q.Set(true)
  assert(N.PreviewShowing("quiettest"), "a preview showing when it goes on stays")
  Q.Set(false)
  N.ClearPreviews()
end

-- 3. Load order: the switch loads before the files that read it at load, and the data bar menu after it.
do
  local f = assert(io.open(ROOT .. "!!!TwichUI.toc", "rb")); local toc = f:read("*a"); f:close()
  local function At(name) return (toc:find(name, 1, true)) end
  assert(At("QuietScreen.lua") and At("QuietScreen.lua") < At("modules\\Notify.lua"), "QuietScreen.lua before Notify.lua")
  assert(At("QuietScreen.lua") < At("reminders\\Display.lua") and At("QuietScreen.lua") < At("glows\\Controller.lua"), "and before Reminders and glows")
  assert(At("QuietScreen.lua") < At("healer\\Watch.lua") and At("QuietScreen.lua") < At("buffback\\Watch.lua"), "and before Healer Watch and Return the Favor")
  assert(At("QuietScreen.lua") < At("modules\\SettingsBrokerMenu.lua"), "and before the menu")
end

print("QUIET SCREEN TESTS PASSED")
