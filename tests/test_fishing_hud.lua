-- TwichUI Fishing, Stage 2: the heads-up pieces (CastBar.lua, CatchList.lua, Toast.lua, Hud.lua) on Stage 1's notifications.
-- Cast bar states and timing, the catch list's rows, sorting, overflow, treasures and highlights, notifications and their
-- consolidation, values only from a connected valuation, missing artwork and fonts, late item names, positions, and that
-- hidden pieces do no work. Simulated client with real layout arithmetic (tests/ui_widgets.lua): proves layout and
-- bookkeeping, not the game's rendering.
dofile(TESTS .. "fishing_mock.lua")
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local KEY = "CLICK TwichUIFishingButton:LeftButton"
local NAMES = { [FISH1] = { "Raw Mithril Head Trout", 1 }, [FISH2] = { "Raw Greater Sagefish", 1 }, [JUNK] = { "Raw Bristle Whisker Catfish", 1 },
  [PEARL] = { "Golden Pearl", 2 }, [CLAMMEAT] = { "Tangy Clam Meat", 1 }, [CLAM] = { "Small Barnacled Clam", 1 }, [9100] = { "Old Boot", 0 },
  [9101] = { "Rare Fish", 3 }, [9102] = { "Spotted Yellowtail", 1 }, [9103] = { "Firefin Snapper", 1 }, [9104] = { "Oily Blackmouth", 1 },
  [9105] = { "Stonescale Eel", 1 }, [9106] = { "Raw Whitescale Salmon", 1 } }

local function Fresh(o)
  o = o or {}
  o.names = o.names or NAMES
  local c, W = FishingClient(o)
  local faults = {}
  c.geterrorhandler = function() return function(e) faults[#faults + 1] = tostring(e) end end
  W.faults = faults
  W.Camera()
  -- channel times as the game gives them (milliseconds on the GetTime clock): a 20 s line
  c.UnitChannelInfo = function(unit)
    if unit ~= "player" or not W.channel then return nil end
    local start = W.lineStart or W.clock
    return W.channel[1], W.channel[1], 1, start * 1000, (start + 20) * 1000, false, false, W.channel[2]
  end
  local start = W.StartLine
  W.StartLine = function(id) W.lineStart = W.clock; start(id) end
  W.bound.F = KEY
  c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
  return c, W, c.TwichUI.Fishing
end

local function Cast(W) W.Advance(1.2); W.Key("F") end
local function Catch(W, items) W.catch = items; W.Interact(); W.Advance(0.05) end

---------------------------------------------------------------------------
-- 1. The cast bar: idle, casting, the line's own timing, results, and back to idle
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  local CB = F.CastBar
  c.TwichUI.RunCommand("fish mode")
  local frame, ui = CB.Frame()
  Check(CB.Shown() and CB.State() == "idle" and ui.label:GetText() == "Ready to cast", "on: idle, ready to cast")
  local l, b, w = W.UI.Rect(frame)
  Check(math.abs(l + w / 2 - 683) < 1 and math.abs(b - 150) < 1, "near the bottom middle by default")
  Check(frame:GetScript("OnUpdate") == nil, "no per-frame work while idle")
  c.FireEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-x", 7620)
  Check(CB.State() == "casting" and ui.label:GetText():find("Casting"), "the cast sent: casting")
  Cast(W)
  Check(CB.State() == "line" and frame:GetScript("OnUpdate") ~= nil, "the line is out: the timer runs")
  W.Frames(10)
  local fillW = ui.fill:GetWidth()
  local full = F.Hud.ART.castfill.cw * CB.WIDTH / F.Hud.ART.castbar.cw
  Check(math.abs(fillW / full - 0.5) < 0.03, ("half the line's time: half the fill (%.2f)"):format(fillW / full))
  Check(ui.time:GetText() == "10.0s" or ui.time:GetText() == "9.9s" or ui.time:GetText() == "10.1s", "and the seconds left from the channel's own end: " .. ui.time:GetText())
  Check(ui.label:GetText():find("Fishing"), "labelled as fishing, never as a bite")
  Check(ui.fill:GetTexture():find("castfill", 1, true) and select(2, ui.fill:GetTexCoord()) < 0.36, "the fill's texture is cut to the time, not squeezed")
  Catch(W, { { FISH1, 1 } })
  Check(CB.State() == "caught" and ui.label:GetText() == "Caught!" and frame:GetScript("OnUpdate") == nil, "a catch: caught, and the timer stops")
  W.Advance(2)
  Check(CB.State() == "idle", "then idle again")
  Cast(W); W.bite = false; W.Interact(); W.Advance(1.6)
  Check(CB.State() == "missed" and ui.label:GetText() == "Nothing on the line", "an early reel: nothing on the line")
  W.bite = true; W.Advance(2)
  Cast(W)
  local guid = W.channel[3]
  c.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player", guid, 7620); W.StopLine(); W.Advance(0.1)
  Check(CB.State() == "interrupted", "an interrupted cast says so")
  W.Advance(2)
  -- without channel times the seconds count up and no fill is drawn
  c.UnitChannelInfo = function(unit) if unit == "player" and W.channel then return "Fishing", "Fishing", 1, nil, nil, false, false, 7620 end end
  Cast(W); W.Frames(3)
  Check(not ui.fill:IsShown() and (ui.time:GetText() == "3s" or ui.time:GetText() == "2s"), "no channel times: elapsed seconds, no invented progress")
  Catch(W, { { FISH1, 1 } })
  local text = ui.stats:GetText()
  Check(text:find("2 catches", 1, true) and not text:find("ure", 1, true), "the figures under the bar (no pole: no lure figure): " .. text)
  Check(not text:find("g", 1, true) or not text:match("%d+g"), "no money is shown without a valuation")
  c.TwichUI.RunCommand("fish stop")
  Check(not CB.Shown() and frame:GetScript("OnUpdate") == nil, "hidden: nothing runs")
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, " | "))
end

---------------------------------------------------------------------------
-- 2. The catch list: rows from Stage 1's records, sorting, limits, treasures, highlights, totals
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  local Lst = F.CatchList
  c.TwichUI.RunCommand("fish mode")
  local frame, ui, rows, small = Lst.Frame()
  Check(Lst.Shown() and ui.since:GetText() == "No session in progress", "turned on before fishing: no session yet")
  Cast(W)
  Check(ui.empty:IsShown() and ui.since:GetText():find("Fishing for", 1, true), "the first cast starts the session; nothing caught yet: it says so")
  Catch(W, { { FISH1, 1 } })
  local l, b, w = W.UI.Rect(frame)
  Check(math.abs(l + w - (1366 - 36)) < 1, "on the right side of the screen")
  Check(not frame:IsMouseEnabled(), "it never takes the mouse (clicks reach the world)")
  Cast(W); Catch(W, { { FISH2, 2 } })
  Cast(W); Catch(W, { { FISH1, 1 } })
  Check(rows[1]:IsShown() and rows[1].name:GetText() == "Raw Mithril Head Trout" and rows[1].count:GetText() == "\195\1512", "most caught first, with the game's name")
  Check(rows[1].sub:GetText() == "2 caught" and rows[2].sub:GetText() == "2 caught", "how many were caught")
  Check(rows[1].icon:GetTexture() == "Interface\\Icons\\item" .. FISH1, "the game's own icon")
  Check(rows[1].glowAnim.plays >= 1, "the row just caught glows")
  Check((rows[1].arrive.plays or 0) + (rows[2].arrive.plays or 0) == 2, "each new row arrived once with a short fade")
  Check(not ui.value:IsShown() and not ui.valueLabel:IsShown(), "no value and no space for one without a valuation")
  F.Present.Configure("list.sort", "name")
  Check(rows[1].name:GetText() == "Raw Greater Sagefish", "sorted by name when asked")
  F.Present.Configure("list.sort", "recent")
  Check(rows[1].name:GetText() == "Raw Mithril Head Trout", "sorted by the most recent")
  -- overflow
  F.Present.Configure("list.rows", 3)
  for _, id in ipairs({ 9102, 9103, 9104 }) do Cast(W); Catch(W, { { id, 1 } }) end
  local n = 0 for _, r in ipairs(rows) do if r:IsShown() then n = n + 1 end end
  Check(n == 3 and ui.more:IsShown() and ui.more:GetText() == "+2 more kinds", "no more rows than asked, then how many more")
  -- clam contents as treasures, apart from the catches
  Cast(W); Catch(W, { { CLAM, 1 } })
  Check(small[1]:IsShown() and small[1].name:GetText():find("Small Barnacled Clam", 1, true) and small[1].name:GetText():find("1 unopened", 1, true),
    "a caught clam shows under Other Treasures, unopened")
  W.Advance(1.2); W.Key("F")     -- the key opens it between casts (Stage 1)
  W.Advance(3)
  local texts = {}
  for _, r in ipairs(small) do if r:IsShown() then texts[#texts + 1] = r.name:GetText() end end
  local all = table.concat(texts, " / ")
  Check(all:find("Golden Pearl", 1, true) and all:find("Tangy Clam Meat", 1, true), "its contents are treasures: " .. all)
  Check(not all:find("unopened", 1, true), "and the clam is no longer unopened")
  for _, r in ipairs(rows) do Check(not (r:IsShown() and r.name:GetText():find("Pearl", 1, true)), "contents never count as catches") end
  Check(ui.totals:GetText():find("7 catches", 1, true), "the session's totals: " .. ui.totals:GetText())
  -- a valuation connected (Stage 3): values appear; it is asked on redraws, not per frame
  local asked = 0
  F.Present.SetValueProvider(function(kind, id)
    asked = asked + 1
    if kind == "session" then return { text = "18g 42s", items = { [FISH1] = "8g 40s" } } end
    if kind == "item" then return "70s" end
  end)
  Check(ui.value:IsShown() and ui.value:GetText() == "18g 42s", "with a valuation the estimated value shows")
  local before = asked
  local serial = F.Hud.serial
  W.Frames(5)
  Check(F.Hud.serial == serial, "(no record changed meanwhile)")
  Check(asked == before, "the valuation is never asked from an animation or timer")
  F.Present.SetValueProvider(function() error("broken valuation") end)
  Check(not ui.value:IsShown() and F.noteCounts["value-error"] >= 1, "a failing valuation shows nothing and is noted")
  F.Present.SetValueProvider(nil)
  -- the session's length ticks once a second, without a redraw
  local builds = Lst.builds
  W.Advance(5)
  Check(Lst.builds == builds and ui.since:GetText():find("Fishing for", 1, true), "the duration updates without redrawing the rows")
  c.TwichUI.RunCommand("fish stop")
  Check(not Lst.Shown(), "hidden when the session ends")
  builds = Lst.builds
  c.FireEvent("GET_ITEM_INFO_RECEIVED", FISH1, true)
  W.Advance(1)
  Check(Lst.builds == builds, "hidden: no redraws")
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, " | "))
end

---------------------------------------------------------------------------
-- 3. Notifications: one per catch, consolidated, treasures apart, at most three at once
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  local T = F.Toast
  c.TwichUI.RunCommand("fish mode")
  Cast(W); Catch(W, { { FISH1, 1 }, { FISH1, 2 } })
  local active, queue = T.Active()
  Check(#active == 1 and active[1].entry.q == 3 and active[1].name:GetText() == "Raw Mithril Head Trout \195\1513", "two stacks of one item: one notice, x3")
  Check(active[1].title:GetText() == "Caught!" and active[1].icon:GetTexture() == "Interface\\Icons\\item" .. FISH1, "with the item's own icon")
  Check(not active[1].value:IsShown(), "no value line without a valuation")
  Cast(W); Catch(W, { { FISH1, 1 } })
  Check(#active == 1 and active[1].entry.q == 4, "the same fish again while its notice is up adds to it")
  Cast(W); Catch(W, { { 9101, 1 } })
  Check(#active == 2 and active[2].title:GetText() == "Treasure!" and active[2].glint:IsShown(), "an item the game rates rare is a treasure")
  for _, id in ipairs({ 9102, 9103, 9104, 9105 }) do Cast(W); Catch(W, { { id, 1 } }) end
  active, queue = T.Active()
  Check(#active == 3 and #queue == 3, "three at once; the rest wait")
  -- notices stack upwards from the anchor, left of the middle: never over the middle of the screen or the cast bar
  for _, f in ipairs(active) do
    local l, b, w = W.UI.Rect(f)
    Check(l + w < 683 - 60, "left of the bobber's area")
    Check(b > 150 + 80, "above the cast bar")
  end
  W.Frames(40)
  active, queue = T.Active()
  Check(#active == 0 and #queue == 0 and T.shown == 6, "all shown in turn, then gone")
  -- nothing runs once they are gone
  for _, f in ipairs(({ T.Active() })[1]) do Check(f:GetScript("OnUpdate") == nil, "no OnUpdate on a hidden notice") end
  -- clam contents are treasures
  Cast(W); Catch(W, { { CLAM, 1 } }); W.Frames(8)
  W.Advance(1.2); W.Key("F"); W.Advance(2.5)
  active = T.Active()
  local kinds = {}
  for _, f in ipairs(active) do kinds[#kinds + 1] = f.entry.kind .. ":" .. f.entry.id end
  Check(table.concat(kinds, ","):find("treasure:" .. PEARL, 1, true), "a pearl from a clam is a treasure: " .. table.concat(kinds, ","))
  -- turned off
  F.Present.Configure("toast.enabled", false)
  W.Frames(10)
  Cast(W); Catch(W, { { FISH2, 1 } })
  Check(#({ T.Active() })[1] == 0, "notifications can be turned off")
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, " | "))
end
do
  -- reduced motion: no slide, only the fade
  local c, W, F = Fresh()
  F.Present.Configure("present.motion", false)
  c.TwichUI.RunCommand("fish mode")
  Cast(W); Catch(W, { { FISH1, 1 } })
  local f = F.Toast.Active()[1]
  Check(f.slide == 0 and not f.moves, "reduced motion: the notice doesn't slide")
  Check(F.CatchList.Frame() and select(3, F.CatchList.Frame())[1].arrive.plays == nil, "nor does a new row")
end

---------------------------------------------------------------------------
-- 4. Missing or damaged artwork and fonts, and names that arrive late
---------------------------------------------------------------------------
do
  local MEDIA = "Interface\\AddOns\\TwichUI_Fishing\\media\\"
  local missing = { [MEDIA .. "castbar"] = true, [MEDIA .. "castfill"] = true, [MEDIA .. "toast"] = true,
    [MEDIA .. "scrim"] = true, ["Interface\\AddOns\\!!!TwichUI\\media\\fonts\\Spectral-SemiBold.ttf"] = true }
  local names = {}
  for k, v in pairs(NAMES) do names[k] = v end
  names[FISH1] = nil       -- not described by the game yet
  local c, W, F = Fresh({ missingArt = missing, names = names })
  c.TwichUI.RunCommand("fish mode")
  local frame, ui = F.CastBar.Frame()
  Check(F.CastBar.Shown() and ui.art.color ~= nil and ui.art.file == nil, "a missing cast bar file is drawn as a plain shape, not a hole")
  Check(ui.label.font ~= nil and not ui.label.font:find("Spectral", 1, true), "a refused font falls back to the game's")
  Check(F.noteCounts["art-missing"] >= 2, "and the missing files are noted")
  Cast(W); W.Frames(5)
  Check(ui.fill:IsShown() and ui.fill.color ~= nil, "the fill still shows progress")
  Catch(W, { { FISH1, 1 } })
  local _, _, rows = F.CatchList.Frame()
  Check(rows[1].name:GetText() == "Item " .. FISH1 and rows[1].icon:GetTexture() ~= nil, "an item the game hasn't described yet: a placeholder")
  names[FISH1] = NAMES[FISH1]
  W.names = names
  c.FireEvent("GET_ITEM_INFO_RECEIVED", FISH1, true); W.Advance(0.2)
  Check(rows[1].name:GetText() == "Raw Mithril Head Trout", "and its name when it arrives")
  Check(F.Toast.Active()[1].name:GetText() == "Raw Mithril Head Trout", "on the notice too")
  Check(F.Hud.Waiting() == 0, "nothing left waiting")
  Check(#W.faults == 0, "no errors with missing art: " .. table.concat(W.faults, " | "))
end

---------------------------------------------------------------------------
-- 5. Moving and scaling the pieces
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  local P = F.Present
  c.TwichUI.RunCommand("fish move")
  local frame = F.CastBar.Frame()
  Check(P.Unlocked() and frame:IsMouseEnabled() and frame.twichMove.label:IsShown(), "move mode: the pieces take the mouse and say so")
  Check(F.CastBar.Shown() and F.CatchList.Shown() and #({ F.Toast.Active() })[1] == 1, "all three show sample figures to place")
  -- the player drags the bar 100 to the right and 40 up
  frame.scripts.OnDragStart(frame)
  frame:ClearAllPoints(); frame:SetPoint("BOTTOMLEFT", c.UIParent, "BOTTOMLEFT", 683 - 180 + 100, 190)
  frame.scripts.OnDragStop(frame)
  Check(F.Store.Get("castbar.x") == 100 and F.Store.Get("castbar.y") == 190, "the new place is saved: " .. F.Store.Get("castbar.x") .. "," .. F.Store.Get("castbar.y"))
  c.TwichUI.RunCommand("fish move")
  Check(not frame:IsMouseEnabled() and not F.CastBar.Shown(), "locked again: no mouse, and hidden while Fishing Mode is off")
  c.TwichUI.RunCommand("fish scale castbar 1.25")
  c.TwichUI.RunCommand("fish mode")
  local l, b, w = W.UI.Rect(frame)
  Check(math.abs(w - 360 * 1.25) < 0.5 and math.abs(l + w / 2 - (683 + 125)) < 1, "scaled, and still where it was put")
  c.TwichUI.RunCommand("fish scale castbar 3")
  Check(F.Store.Get("castbar.scale") == 1.25, "a scale out of range is refused")
end

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED test_fishing_hud")
