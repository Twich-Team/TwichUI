-- Workshop "What's it worth?" layout (TwichUI_Workshop/WorthLayout.lua and Worth.lua's recommendation): the pure parts of the tooltip designer.
--   * the recommendation: a pick only when the estimates prove it; known, unknown, tied and unavailable options; an unknown auction cut
--     and missing disenchant data stay explicit; disenchant is never invented (a test INPUT stands in where the product has no data);
--   * adding, removing, reordering, stepping and the Always / Hold Shift choice, and duplicates refused;
--   * Always versus Shift-only visibility, order, no repeats, the hint and the empty section;
--   * the qualifications that keep a figure honest survive any layout, and hiding rows never changes a figure or the recommendation;
--   * saved settings: defaults, validation, damaged and older saves, a newer schema left alone, presentation only.
-- The preview/live equivalence and the tooltip reuse checks are in test_workshop_worth.lua. Proves our logic, not what Forever returns.
dofile(TESTS .. "mi_mock.lua")

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "Prices.lua", "Opportunities.lua",
  "Vendor.lua", "Shopping.lua", "Worth.lua", "WorthLayout.lua" }
local function Load(c, file)
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. file))
  setfenv(chunk, c)
  chunk("TwichUI_Workshop", {})
end
local NOW = 1000000
local function Money(n) return "[" .. n .. "]" end

local c = MIClient("Rich", { db = { modules = {} } })
c.TwichUIDB = c.TwichUIDB or {}
c.time = function() return NOW end
c.CreateFrame = function(kind) return MIFake(kind) end
c.GetRealmName = function() return "Realm" end
c.C_Timer = { After = function() end }
for _, f in ipairs(FILES) do Load(c, f) end
local W = c.TwichUI.Workshop
local WO, WL, PR = W.Worth, W.WorthLayout, W.Prices

local function F(t)
  local f = { sell = 50, quality = 1, classID = 7, bindType = 0, bound = false, now = NOW,
    market = { label = "the Alliance auction house on Realm", side = "Alliance", at = NOW - 60, complete = true },
    price = { price = 200, qty = 1, listings = 1, total = 1, at = NOW - 60, complete = true } }
  for k, v in pairs(t or {}) do if v == "nil" then f[k] = nil else f[k] = v end end
  return f
end
local function Ctx(extra)
  local x = { money = Money, ageText = PR.AgeText, now = NOW, count = 1, market = { label = "the Alliance auction house on Realm", at = NOW - 60, complete = true } }
  for k, v in pairs(extra or {}) do x[k] = v end
  return x
end
local function Rec(t) local r = WO.Recommend(WO.Evaluate(F(t))); return r and r.text, r and r.kind end
local function Flat(lines) local t = {} for _, l in ipairs(lines or {}) do t[#t + 1] = l[1] .. (l[2] and (" | " .. l[2]) or "") end return table.concat(t, "\n") end
local function Layout(ids) local l = {} for _, e in ipairs(ids) do l[#l + 1] = { id = e[1], when = e[2] or "always" } end return { enabled = true, lines = l } end
local function Ids(list) local t = {} for _, e in ipairs(list) do t[#t + 1] = e.id .. (e.when == "shift" and "*" or "") end return table.concat(t, ",") end
local function Keys(t) local n = {} for k in pairs(t) do n[#n + 1] = k end table.sort(n) return table.concat(n, ",") end

---------------------------------------------------------------------------
-- Recommendations
---------------------------------------------------------------------------
-- known: the auction value is before fees (the product's state), so only the vendor can be proven
Same(Rec({ sell = 300 }), "Suggested: Vendor", "vendor is at least the auction's ceiling")
Same(Rec({ sell = 200 }), "Suggested: Vendor", "equal to the ceiling: still at least as good after any cut")
do
  local text, kind = Rec({ sell = 50 })
  Same(text, "No suggestion: auction fee unknown"); Same(kind, "fee")
  Check(not text:find("Suggested", 1, true), "an unproven auction is never suggested")
end
-- a confirmed cut (a TEST INPUT: PR.CUT is empty in the product)
Same(Rec({ rate = 0.05, sell = 150 }), "Suggested: Auction house")
Same(Rec({ rate = 0.05, sell = 191 }), "Suggested: Vendor")
do local text, kind = Rec({ rate = 0.05, sell = 190 }); Same(text, "Similar value"); Same(kind, "tie") end
-- the cut can never be taken from a price that is not known
Same(Rec({ price = "nil" }), "More prices needed")
Same(Rec({ market = "nil", price = "nil" }), "More prices needed", "no scan at all")
Same(Rec({ sell = "nil" }), "More prices needed", "the vendor value is unknown too")
Same(Rec({ variant = "suffix" }), "No suggestion: this variant isn't priced")
Same(Rec({ bindType = 9 }), "No suggestion: can't tell if it can be listed")
-- unavailable is not unknown: a bound item cannot be auctioned, an item without a sell value cannot be sold to a vendor
Same(Rec({ bound = true }), nil, "one real option, nothing unknown: nothing to compare")
Same(Rec({ sell = 0 }), nil, "no sell value: not a zero estimate, and not a competitor")
Same(Rec({ bindType = 4 }), nil, "quest item")
-- old prices and a partial scan are part of the recommendation when it leans on them
Same(Rec({ sell = 300, price = { price = 200, at = NOW - 3 * 86400, complete = false } }), "Suggested: Vendor (old prices, partial scan)")
Same(Rec({ rate = 0.05, sell = 150, price = { price = 200, at = NOW - 60, complete = false } }), "Suggested: Auction house (partial scan)")
-- disenchant: relevant for green-to-epic armor, but there is no outcome data, so it is never valued
do
  local r = WO.Evaluate(F({ classID = 4, quality = 2, rate = 0.05, sell = 150 }))
  Same(r.disenchant.state, "unknown"); Same(r.disenchant.value, nil, "never a number")
  Same(WO.Recommend(r).text, "Auction beats vendor (disenchant unknown)", "a qualified comparison that does not claim disenchant was weighed")
  Check(WO.Recommend(r).kind == "beats" and not WO.Recommend(r).text:find("Suggested", 1, true), "not an overall winner")
  Same(WO.Recommend(WO.Evaluate(F({ classID = 4, quality = 2, sell = 300 }))).text, "Vendor beats auction (disenchant unknown)")
  Same(WO.Recommend(WO.Evaluate(F({ classID = 4, quality = 2, sell = 50 }))).text, "Disenchant value unknown", "unproven comparison: only what is unknown is said")
  Same(WO.Recommend(WO.Evaluate(F({ classID = 4, quality = 2, rate = 0.05, sell = 190 }))).text, "Disenchant value unknown", "a tie of the two known options is not claimed either")
  Same(WO.Recommend(WO.Evaluate(F({ classID = 4, quality = 2, bound = true }))).text, "Disenchant value unknown", "auction unavailable: disenchant is the unknown competitor")
  Same(WO.Recommend(WO.Evaluate(F({ classID = 4, quality = 2, price = "nil" }))).text, "More prices needed", "a missing price comes first")
  Same(WO.Recommend(WO.Evaluate(F({ classID = 4, quality = 2, sell = 300, price = { price = 200, at = NOW - 3 * 86400, complete = true } }))).text,
    "Vendor beats auction (old prices, disenchant unknown)")
end
-- the pure comparison with a disenchant value supplied as a TEST INPUT (the product has none): it can be suggested, tied or beaten
do
  local function With(de, t)
    local r = WO.Evaluate(F(t or { rate = 0.05, sell = 100 }))   -- auction 190 after the cut, vendor 100
    r.disenchant = de
    return WO.Recommend(r)
  end
  Same(With({ state = "ok", value = 400 }).text, "Suggested: Disenchant")
  Same(With({ state = "ok", value = 190 }).text, "Similar value", "disenchant and auction tie")
  Same(With({ state = "ok", value = 20 }).text, "Suggested: Auction house")
  Same(With({ state = "ok", value = 100 }, { rate = 0.05, sell = 100, bound = true }).text, "Similar value", "disenchant and vendor tie when the auction is unavailable")
  -- before fees: disenchant must reach the auction ceiling to be proven better
  Same(With({ state = "ok", value = 150 }, { sell = 100 }).text, "No suggestion: auction fee unknown")
  Same(With({ state = "ok", value = 250 }, { sell = 100 }).text, "Suggested: Disenchant")
end

---------------------------------------------------------------------------
-- Changing a layout
---------------------------------------------------------------------------
do
  local base = WL.DefaultLines()
  Same(Ids(base), "recommend,vendor,auction,disenchant,status*,source*,note*", "the short default")
  Same(Keys(WL.BY_ID), "auction,disenchant,note,outcomes,recommend,source,status,vendor", "eight line types")
  -- add: at a place, at the end, refused twice, unknown refused
  local l, why = WL.Add(base, "outcomes", 2)
  Same(Ids(l), "recommend,outcomes*,vendor,auction,disenchant,status*,source*,note*", "added at 2, starting where the type starts (Hold Shift)")
  Same(Ids(base), "recommend,vendor,auction,disenchant,status*,source*,note*", "the argument is never changed")
  l, why = WL.Add(base, "vendor", 1); Same(l, nil); Same(why, "duplicate", "no duplicate line types")
  l, why = WL.Add(base, "colors", 1); Same(l, nil); Same(why, "unknown")
  Same(Ids(WL.Add({}, "vendor")), "vendor", "into an empty layout")
  Same(Ids(WL.Add({ { id = "vendor", when = "always" } }, "note", nil, "always")), "vendor,note", "at the end, with the chosen visibility")
  Same(Ids(WL.Add({ { id = "vendor", when = "always" } }, "auction", -4)), "auction,vendor", "a place before the first is the first")
  Same(Ids(WL.Add({ { id = "vendor", when = "always" } }, "auction", 99)), "vendor,auction", "a place past the end is the end")
  -- remove
  l = WL.Remove(base, "auction"); Same(Ids(l), "recommend,vendor,disenchant,status*,source*,note*")
  l, why = WL.Remove(l, "auction"); Same(l, nil); Same(why, "missing")
  -- move: before the line now at that position
  Same(Ids(WL.Move(base, "note", 1)), "note*,recommend,vendor,auction,disenchant,status*,source*", "to the top")
  Same(Ids(WL.Move(base, "recommend", 4)), "vendor,auction,recommend,disenchant,status*,source*,note*", "down, before the 4th line")
  Same(Ids(WL.Move(base, "recommend", 8)), "vendor,auction,disenchant,status*,source*,note*,recommend", "to the end")
  Same(Ids(WL.Move(base, "vendor", 2)), Ids(base), "dropped where it already is: unchanged")
  Same(Ids(WL.Move(base, "vendor", 3)), Ids(base), "dropped just after itself: unchanged")
  Same(Ids(WL.Move(base, "auction", 2)), "recommend,auction,vendor,disenchant,status*,source*,note*")
  l, why = WL.Move(base, "colors", 1); Same(l, nil); Same(why, "missing")
  -- step: one step among the lines SHOWN in that mode
  Same(Ids(WL.Step(base, "auction", -1, false)), "recommend,auction,vendor,disenchant,status*,source*,note*")
  l, why = WL.Step(base, "recommend", -1, false); Same(l, nil); Same(why, "edge")
  -- the Normal preview: stepping "note*" is not possible (it is not shown), but in the Hold Shift preview it is
  l, why = WL.Step(base, "disenchant", 1, false); Same(l, nil); Same(why, "edge", "Normal: nothing visible below it (the rest is Shift-only), so no step")
  local hid = { { id = "vendor", when = "always" }, { id = "status", when = "shift" }, { id = "auction", when = "always" } }
  Same(Ids(WL.Step(hid, "vendor", 1, false)), "status*,auction,vendor", "Normal: a step passes the next SHOWN line, the hidden one stays behind")
  Same(Ids(WL.Step(hid, "vendor", 1, true)), "status*,vendor,auction", "Hold Shift: the next line is shown, so one step")
  Same(Ids(WL.Step(base, "disenchant", 1, true)), "recommend,vendor,auction,status*,disenchant,source*,note*", "Hold Shift: one visible step")
  -- visibility
  l = WL.SetWhen(base, "vendor", "shift"); Same(Ids(l), "recommend,vendor*,auction,disenchant,status*,source*,note*")
  l, why = WL.SetWhen(base, "vendor", "sometimes"); Same(l, nil); Same(why, "bad")
  -- every operation keeps a valid layout
  local ops = { WL.Add(base, "outcomes", 3), WL.Remove(base, "note"), WL.Move(base, "auction", 1), WL.Step(base, "vendor", 1, true), WL.SetWhen(base, "note", "always") }
  for _, o in ipairs(ops) do Same(Ids(WL.Clean(o)), Ids(o), "an operation's result is already clean") end
  Check(#WL.Add(WL.Remove(base, "note"), "note") == 7, "removed and added back")
end

---------------------------------------------------------------------------
-- Always versus Hold Shift
---------------------------------------------------------------------------
do
  local r = WO.Evaluate(F({ sell = 300 }))
  local def = { enabled = true, lines = WL.DefaultLines() }
  local ids = function(s) local t = {} for _, row in ipairs(s.rows) do t[#t + 1] = row.id end return table.concat(t, ",") end
  local normal, shift = WL.Rows(r, Ctx(), def, false), WL.Rows(r, Ctx(), def, true)
  Same(ids(normal), "recommend,vendor,auction,disenchant", "Normal: the Always lines")
  Same(ids(shift), "recommend,vendor,auction,disenchant,status,source,note", "Hold Shift: the Always lines and the Shift lines, in the configured order, none twice")
  Same(normal.hint, "Hold Shift for details", "details exist: the hint")
  Same(shift.hint, nil, "no hint while Shift is held")
  -- Shift lines in the middle keep their place
  local mixed = Layout({ { "status", "shift" }, { "vendor" }, { "source", "shift" }, { "auction" } })
  Same(ids(WL.Rows(r, Ctx(), mixed, false)), "vendor,auction")
  Same(ids(WL.Rows(r, Ctx(), mixed, true)), "status,vendor,source,auction", "the Shift lines slot in where they were put")
  -- no hint when Shift would add nothing: no Shift-only line, or only ones with nothing to say
  Same(WL.Rows(r, Ctx(), Layout({ { "vendor" }, { "auction" } }), false).hint, nil, "no Shift-only line")
  Same(WL.Rows(r, Ctx(), Layout({ { "vendor" }, { "outcomes", "shift" } }), false).hint, nil, "a Shift line with nothing to say adds no hint")
  Same(WL.Rows(WO.Evaluate(F({ bound = true })), Ctx(), Layout({ { "vendor" }, { "source", "shift" } }), false).hint, nil, "source of an unlistable item: nothing, so no hint")
  -- the section never repeats a line, and an empty section has no heading
  local lines = WL.Lines(r, Ctx(), def, true)
  Same(select(2, Flat(lines):gsub("What's it worth%?", "")), 1, "one heading")
  Same(WL.Lines(r, Ctx(), { enabled = true, lines = {} }, false), nil, "no lines chosen: nothing, not an empty heading")
  Same(WL.Lines(r, Ctx(), Layout({ { "outcomes" } }), false), nil, "only lines with nothing to say: nothing")
  Same(WL.Lines(WO.Evaluate(F()), Ctx(), Layout({ { "disenchant" } }), true), nil, "a disenchant row on an item that cannot be disenchanted: nothing, not 'not applicable'")
  Same(Flat(WL.Lines(r, Ctx(), Layout({ { "status", "shift" } }), false)), "What's it worth?\n~Hold Shift for details", "only Shift lines, Shift not held: the heading and the hint")
  Same(Flat(WL.Lines(r, Ctx(), Layout({ { "vendor" } }), false)), "What's it worth?\nVendor | [300]", "just the vendor value, no hint")
  -- a stack
  Check(WL.Lines(r, Ctx({ count = 5 }), def, false)[1][1] == "What's it worth? (each)")
  -- the rows the designer shows include empty places (they have no line), so a line without content can still be moved
  local d = WL.Rows(WO.Evaluate(F()), Ctx(), def, false)
  Check(d.rows[4].id == "disenchant" and d.rows[4].line == nil and d.rows[4].index == 4, "an empty place is a row without a line")
end

---------------------------------------------------------------------------
-- Qualifications survive any layout; hiding rows changes presentation only
---------------------------------------------------------------------------
do
  local ALL = {}
  for _, t in ipairs(WL.TYPES) do ALL[#ALL + 1] = t.id end
  -- every subset of the line types, each both ways: whatever is shown carries its own qualifications
  local scenes = {
    { "fee", F({ classID = 4, quality = 2, sell = 50 }) },
    { "old", F({ classID = 4, quality = 2, sell = 300, price = { price = 200, at = NOW - 3 * 86400, complete = false } }) },
    { "cut", F({ classID = 4, quality = 2, rate = 0.05, sell = 150 }) },
    { "plain", F({ sell = 300 }) },
  }
  for _, scene in ipairs(scenes) do
    local f = scene[2]
    local r = WO.Evaluate(f)
    local want = WO.Recommend(r).text
    local snapshot = Flat(WL.Lines(r, Ctx(), WL.Get(), true))
    for mask = 1, 2 ^ #ALL - 1 do
      local list = {}
      for i, id in ipairs(ALL) do if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then list[#list + 1] = { id, (mask + i) % 2 == 0 and "shift" or "always" } end end
      local lay = Layout(list)
      for _, shift in ipairs({ false, true }) do
        local s = WL.Rows(r, Ctx(), lay, shift)
        for _, row in ipairs(s and s.rows or {}) do
          local line = row.line and Flat({ row.line }) or ""
          if row.id == "recommend" and row.line then
            Check(line:find(want, 1, true), scene[1] .. ": the recommendation is unchanged by hiding other rows: " .. line)
            if want:find("disenchant unknown", 1, true) then Check(line:find("(disenchant unknown)", 1, true) or line:find("disenchant unknown)", 1, true), "the qualification is in the recommendation's own line") end
          elseif row.id == "auction" and r.auction.state == "ok" then
            Check(line:find("before fees", 1, true) or line:find("after fees", 1, true), scene[1] .. ": 'before fees' stays on the value: " .. line)
            if r.auction.old then Check(line:find("old prices", 1, true), "old prices stay on the value") end
            if not r.auction.complete then Check(line:find("partial scan", 1, true), "partial scan stays on the value") end
          elseif row.id == "disenchant" and r.disenchant then
            Check(line:find("Disenchant (average)", 1, true) and line:find("no data", 1, true), "'average' and the unknown stay on the value: " .. line)
          end
        end
      end
    end
    -- the figures do not depend on what is shown: the same evaluation, byte for byte
    Same(Flat(WL.Lines(r, Ctx(), WL.Get(), true)), snapshot, "building lines does not change the evaluation")
    Same(WO.Recommend(r).text, want)
    -- hiding the price rows leaves the suggestion exactly as it was
    local only = WL.Lines(r, Ctx(), Layout({ { "recommend" } }), false)
    Check(only and Flat(only):find(want, 1, true), "recommendation alone: " .. Flat(only or {}))
  end
  -- the limits note cannot carry a qualification the auction row lacks: with the note hidden the auction row still says 'before fees'
  local r = WO.Evaluate(F())
  Check(Flat(WL.Lines(r, Ctx(), Layout({ { "auction" } }), false)):find("Auction (before fees) | [200]", 1, true))
  -- one brief exclusion note, only when an auction estimate exists
  Check(WL.Lines(WO.Evaluate(F({ price = "nil" })), Ctx(), Layout({ { "note" } }), false) == nil, "no estimate, no note")
  -- the market is named once, on its own line; the age line does not repeat it
  local text = Flat(WL.Lines(r, Ctx(), Layout({ { "status" }, { "source" }, { "auction" } }), false))
  Same(select(2, text:gsub("auction house on Realm", "")), 1)
  -- scan state words
  Same(Flat(WL.Lines(WO.Evaluate(F({ market = "nil", price = "nil" })), Ctx({ market = false }), Layout({ { "status" } }), false)), "What's it worth?\nScanned | not yet")
  Same(Flat(WL.Lines(WO.Evaluate(F({ price = "nil" })), Ctx(), Layout({ { "status" }, { "source" } }), false)),
    "What's it worth?\nScanned | 1 minute ago\nPrices from | the Alliance auction house on Realm", "no listing of this item, but the scan is still described")
  Same(WL.Lines(WO.Evaluate(F({ bound = true })), Ctx(), Layout({ { "status" }, { "source" } }), false), nil, "an unlistable item: no price detail")
  Same(WL.Lines(WO.Evaluate(F({ variant = "bonus" })), Ctx(), Layout({ { "status" }, { "source" } }), false), nil, "a variant is not priced: no price detail")
  -- styles
  local kind, t = WL.Style({ "*Suggested: Vendor" }); Same(kind, "good"); Same(t, "Suggested: Vendor")
  kind = WL.Style({ "~x" }); Same(kind, "quiet"); kind = WL.Style({ "!x" }); Same(kind, "warn"); kind = WL.Style({ "x" }); Same(kind, "plain")
  kind = WL.Style({ "Vendor", "5" }); Same(kind, "double")
end

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------
do
  local function Fresh() c.TwichUIDB = { ui = {}, modules = {} } end
  Fresh()
  -- defaults when nothing is saved; a copy each time
  local g = WL.Get()
  Same(g.enabled, true); Same(Ids(g.lines), Ids(WL.DEFAULT_LINES))
  g.lines[1].id = "note"; g.lines[2] = nil
  Same(Ids(WL.Get().lines), "recommend,vendor,auction,disenchant,status*,source*,note*", "changing a copy never changes the defaults")
  Same(Ids(WL.DEFAULT_LINES), "recommend,vendor,auction,disenchant,status*,source*,note*")
  Check(WL.IsDefault())
  Same(c.TwichUIDB.ui.workshopWorth, nil, "reading writes nothing")
  c.TwichUIDB = nil
  Same(WL.Get().enabled, true, "no saved variables at all: defaults")
  Same(select(2, WL.SetLines({})), "nosave"); Fresh()
  -- save and read back, validated
  Check(WL.SetLines({ { id = "vendor", when = "shift" }, { id = "recommend" }, { id = "vendor" }, { id = "bogus" }, "x", { id = "note", when = "later" } }))
  Same(Ids(WL.Get().lines), "vendor*,recommend,note", "duplicates and unknown types dropped, a bad 'when' reads as Always")
  Same(c.TwichUIDB.ui.workshopWorth.v, 1)
  Check(not WL.IsDefault())
  -- the player's empty choice is kept (not replaced by the defaults)
  Check(WL.SetLines({})); Same(#WL.Get().lines, 0); Check(not WL.IsDefault())
  -- the switch: a saved false is a value
  Check(WL.SetEnabled(false)); Same(WL.Enabled(), false); Same(WL.Get().enabled, false)
  Check(WL.SetEnabled(true)); Same(WL.Enabled(), true)
  local ok, why = WL.SetEnabled("yes"); Same(ok, false); Same(why, "bad")
  ok, why = WL.SetLines("nope"); Same(ok, false); Same(why, "bad")
  -- reset: the layout only; the switch stays
  WL.SetEnabled(false); Check(WL.Reset())
  Check(WL.IsDefault()); Same(WL.Enabled(), false, "Reset layout does not turn the tooltip on")
  Same(c.TwichUIDB.ui.workshopWorth.lines, nil)
  -- damaged saves read narrowly: a good entry survives a bad neighbour; nothing is rewritten by reading
  Fresh()
  c.TwichUIDB.ui.workshopWorth = { v = 1, enabled = "maybe", lines = { { id = "auction", when = "shift" }, 7, { id = 5 }, { id = "vendor", when = false }, { id = "auction" } } }
  Same(Ids(WL.Get().lines), "auction*,vendor"); Same(WL.Get().enabled, true, "an unusable switch value reads as the default")
  Same(#c.TwichUIDB.ui.workshopWorth.lines, 5, "reading left the saved table as it was")
  c.TwichUIDB.ui.workshopWorth = { v = 1, lines = "not a list" }; Same(Ids(WL.Get().lines), Ids(WL.DEFAULT_LINES), "a damaged list reads as the default")
  c.TwichUIDB.ui.workshopWorth = "garbage"; Same(Ids(WL.Get().lines), Ids(WL.DEFAULT_LINES), "a damaged table reads as the default")
  Check(WL.SetLines({ { id = "vendor" } }) and Ids(WL.Get().lines) == "vendor", "and a save replaces it")
  local big = {}
  for i = 1, 5000 do big[i] = { id = "vendor" } end
  c.TwichUIDB.ui.workshopWorth = { v = 1, lines = big }; Same(Ids(WL.Get().lines), "vendor", "a huge damaged list is bounded")
  -- an older save: before this feature nothing was saved; a table without a version is read as version 1
  c.TwichUIDB.ui.workshopWorth = { lines = { { id = "note", when = "always" } } }
  Same(Ids(WL.Get().lines), "note"); Check(WL.SetEnabled(true)); Same(c.TwichUIDB.ui.workshopWorth.v, 1)
  c.TwichUIDB.ui = nil; Same(Ids(WL.Get().lines), Ids(WL.DEFAULT_LINES)); Check(WL.SetLines({ { id = "vendor" } }), "saving builds the container"); Same(Ids(WL.Get().lines), "vendor")
  -- written by a NEWER TwichUI: read as defaults, never overwritten
  c.TwichUIDB.ui.workshopWorth = { v = 2, enabled = false, lines = { { id = "vendor" } }, future = { 1 } }
  Same(Ids(WL.Get().lines), Ids(WL.DEFAULT_LINES)); Same(WL.Get().enabled, true)
  ok, why = WL.SetLines({ { id = "note" } }); Same(ok, false); Same(why, "newer")
  ok, why = WL.SetEnabled(false); Same(ok, false); Same(why, "newer")
  ok, why = WL.Reset(); Same(ok, false); Same(why, "newer")
  Same(c.TwichUIDB.ui.workshopWorth.v, 2); Same(c.TwichUIDB.ui.workshopWorth.lines[1].id, "vendor"); Check(c.TwichUIDB.ui.workshopWorth.future, "the newer data is untouched")
  -- presentation only: no price, scan or item data is ever put in it
  Fresh(); WL.SetLines(WL.DefaultLines()); WL.SetEnabled(true)
  Same(Keys(c.TwichUIDB.ui.workshopWorth), "enabled,lines,v", "only the layout and the switch")
  Same(c.TwichUIDB.workshop, nil, "nothing is written to the account-wide Workshop record")
  -- where it lives is a profile group, so a profile carries it
  Check(c.TwichUIDB.ui.workshopWorth ~= nil)
end

---------------------------------------------------------------------------
-- The examples (preview data, no game)
---------------------------------------------------------------------------
do
  Same(#WL.EXAMPLES, 4)
  local def = { enabled = true, lines = WL.DefaultLines() }
  local want = {
    ordinary = "*Suggested: Vendor", higher = "~No suggestion: auction fee unknown", missing = "~More prices needed",
    unavailable = "~Disenchant value unknown",
  }
  for _, e in ipairs(WL.EXAMPLES) do
    local r, ctx = WL.Example(e.key)
    local text = Flat(WL.Lines(r, ctx, def, true))
    Check(text:find(want[e.key], 1, true), e.key .. ": " .. text)
    Check(not text:find("%d+ copper"), "no scan or real item needed")
    Check(WL.Lines(r, ctx, def, false) ~= nil)
  end
  local r = WL.Example("unavailable")
  Same(r.auction.state, "unavailable"); Same(r.disenchant.state, "unknown", "an unavailable action and an unknown estimate side by side")
  Same(WL.Example("missing").auction.state, "unknown")
  Same(WL.Example("nonsense") ~= nil, true, "an unknown example key reads as the first")
  -- the examples are the product's own state: no confirmed cut, so never 'Suggested: Auction house'
  for _, e in ipairs(WL.EXAMPLES) do
    local rr = WL.Example(e.key)
    Check(not (WO.Recommend(rr) and WO.Recommend(rr).text == "Suggested: Auction house"), "no preview shows what the live tooltip cannot")
  end
end

print("PASSED")
