-- Market data foundation 2.0, milestone A4 (docs/workshop/market-data-foundation-v2.md, "A4 as built"): the version-2 history.
--   1. hand-worked cases: the brief's three-scan day, the ring's unchanged rule (and what breaks it), 8 vs 9 changes, the 48-hour reach,
--      missing Recent Price (never 0, never the minimum), UTC day boundaries, leap and year boundaries;
--   2. the strict reader (every refused spelling is absent, never repaired);
--   3. the tiers against an INDEPENDENT model (TwichUI_TestLab/Reference.lua section 5: every scan kept in full, tiers derived naively, its own
--      writer), byte for byte, over seeded calendars that cross every retention boundary; the append path and the full path both exercised;
--   4. the same through the real commit pipeline (records -> batch -> distribution -> stepped commit -> Apply), fed to the model from
--      Prices.Observation (the A3 contract), two markets interleaved;
--   5. Market.History: points only where something was observed, labelled tiers, gap reasons equal to the model's, the legacy join;
--   6. atomicity: a failing or dropped commit at every new phase leaves the database deep-equal;
--   7. the budget guard: ladder order, protected evidence, the record, the unresolved case;
--   8. compatibility: a later history format, malformed strings, the developer switch, the frozen legacy history, 1.3 still held.
-- Synthetic: offline logic only; nothing here says how the client loads a large saved file (the A4 load gate, docs/testlab.md).
dofile(TESTS .. "mi_mock.lua")

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local function Ser(v)
  local t = type(v)
  if t == "number" then return ("%.17g"):format(v) end
  if t == "string" then return ("%q"):format(v) end
  if t == "boolean" or t == "nil" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) if type(a) ~= type(b) then return type(a) < type(b) end return a < b end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = "[" .. Ser(k) .. "]=" .. Ser(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end
local function Clone(v) return assert(loadstring("return " .. Ser(v)))() end   -- test-only: the text is this file's own output

local FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua" }
local LAB = ROOT .. "../TwichUI_TestLab/"

local function Setup(db)
  local c = MIClient("Rich", { db = { modules = {} } })
  c.TwichUIDB = c.TwichUIDB or {}
  c.GetRealmName = function() return "Realm" end
  c.TwichUIWorkshopDB = db
  for _, f in ipairs(FILES) do
    local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
  end
  for _, f in ipairs({ "Fixtures.lua", "Reference.lua" }) do
    local chunk = assert(loadfile(LAB .. f), f); setfenv(chunk, c); chunk("TwichUI_TestLab", {})
  end
  return { c = c, W = c.TwichUI.Workshop, TL = c.TwichUI.TestLab, DB = function() return c.TwichUIWorkshopDB end }
end

local base = Setup(nil)
local W, H2, REF, FX = base.W, base.W.History2, base.TL.Reference, base.TL.Fixtures
local DAY = 86400
local D0 = 20000                 -- 2024-10-04 (a Friday); day // 7 weeks start on Thursdays
local function At(day, hour, min) return day * DAY + (hour or 0) * 3600 + (min or 0) * 60 end
local function Ctx(at, prevAt) return { T = math.floor(at / DAY), M = math.floor(at / 60), prevM = prevAt and math.floor(prevAt / 60) or nil } end
local function O(at, p, r, t, l, pf) return assert(H2.Obs(at, p, r, t, l, pf), "a valid observation") end

---------------------------------------------------------------------------
-- 1. Hand-worked cases
---------------------------------------------------------------------------
do
  -- the brief's day: morning Recent 1000 (10 silver) / 100 items, afternoon 600 / 70, evening 1100 / 120
  local a1, a2, a3 = At(D0, 8), At(D0, 14), At(D0, 20)
  local h, c, path = H2.Update(nil, nil, O(a1, 900, 1000, 100, 10), Ctx(a1)); Same(path, "new")
  h, c, path = H2.Update(h, c, O(a2, 500, 600, 70, 8), Ctx(a2, a1)); Same(path, "fast", "a second scan the same day takes the append path")
  h, c, path = H2.Update(h, c, O(a3, 1000, 1100, 120, 12), Ctx(a3, a2)); Same(path, "fast")
  local m0 = math.floor(a1 / 60)
  -- ring: three real observations; daily: closing 1000 / 1100 / 120 / 12, three scans, minimum low 500 (dpl 500), Recent low 600 (drl 500),
  -- items fewest 70 (dtl 50); nothing above the closing values (dph, drh, dth 0)
  Same(h, ("%d,0,900,100,100,10;360,0,500,100,70,8;360,0,1000,100,120,12|%d:%d,1000,100,120,12,3,500,0,500,0,50,0"):format(m0, D0, D0), "the brief's day, by hand")
  Same(c, nil)
  local ring, days = H2.DecodeH2(h)
  Same(#ring, 3); Same(days[1].r, 1100); Same(days[1].rlo, 600); Same(days[1].rhi, 1100); Same(days[1].tlo, 70); Same(days[1].thi, 120); Same(days[1].n, 3)
  -- a later spike is kept as the day's high even though the day closes lower
  local a4 = At(D0, 22)
  local h2 = H2.Update(h, c, O(a4, 950, 1050, 110, 11), Ctx(a4, a3))
  local _, d2 = H2.DecodeH2(h2)
  Same(d2[1].r, 1050); Same(d2[1].rhi, 1100, "the evening's 1100 survives a later, lower close"); Same(d2[1].rlo, 600); Same(d2[1].phi, 1000); Same(d2[1].n, 4)

  -- the unchanged rule: identical values seen by consecutive recorded scans extend one point (dm = minutes to the last sighting)
  local b1, b2, b3 = At(D0, 1), At(D0, 2), At(D0, 3)
  h = H2.Update(nil, nil, O(b1, 500, 520, 9, 3), Ctx(b1))
  h = H2.Update(h, nil, O(b2, 500, 520, 9, 3), Ctx(b2, b1))
  h = H2.Update(h, nil, O(b3, 500, 520, 9, 3), Ctx(b3, b2))
  Same(h, ("%d,120,500,20,9,3|%d:%d,500,20,9,3,3"):format(math.floor(b1 / 60), D0, D0), "seen three times, nothing moved: one point, short daily form")
  -- an observed absence breaks it: the scan at b2 did not list the item (it is the previous recorded scan at b3), so b3 is a new point
  h = H2.Update(nil, nil, O(b1, 500, 520, 9, 3), Ctx(b1))
  h = H2.Update(h, nil, O(b3, 500, 520, 9, 3), Ctx(b3, b2))
  Same(#H2.DecodeH2(h), 2, "an absence in between is never hidden inside a flat segment")
  -- each value, and the flag, is part of "unchanged": supply only, listings only, the partial flag, Recent Price known vs not
  for _, var in ipairs({ { 500, 520, 10, 3 }, { 500, 520, 9, 4 }, { 500, 520, 9, 3, true }, { 500, nil, 9, 3 }, { 500, 521, 9, 3 }, { 501, 520, 9, 3 } }) do
    h = H2.Update(nil, nil, O(b1, 500, 520, 9, 3), Ctx(b1))
    h = H2.Update(h, nil, O(b2, var[1], var[2], var[3], var[4], var[5]), Ctx(b2, b1))
    Same(#H2.DecodeH2(h), 2, "a change of any observed value makes a new point: " .. table.concat({ tostring(var[1]), tostring(var[2]), tostring(var[3]), tostring(var[4]), tostring(var[5]) }, "/"))
  end

  -- eight changes are all kept; a ninth pushes out the oldest
  h = nil
  local prev
  for i = 1, 9 do
    local at = At(D0, i)
    h = H2.Update(h, nil, O(at, 100 + i, nil, 5, 1), Ctx(at, prev))
    prev = at
    local ring = H2.DecodeH2(h)
    Same(#ring, math.min(i, 8), "ring size after " .. i .. " changes")
    Same(ring[1].p, i <= 8 and 101 or 102, "the oldest change is the one that goes")
  end
  -- the 48-hour reach, to the minute: a last sighting exactly 2880 minutes before the new scan stays, 2881 goes
  for _, back, keep in pairs({}) do end
  local t0 = At(D0, 0)
  for _, case in ipairs({ { 2880, 2 }, { 2881, 1 } }) do
    local t1 = t0 + case[1] * 60
    h = H2.Update(nil, nil, O(t0, 100, nil, 5, 1), Ctx(t0))
    h = H2.Update(h, nil, O(t1, 101, nil, 5, 1), Ctx(t1, t0))
    Same(#H2.DecodeH2(h), case[2], case[1] .. " minutes back")
  end
  -- ... and an old point is never extended into a long flat line: identical values 49 hours apart are two observations (the first expired)
  h = H2.Update(nil, nil, O(t0, 100, nil, 5, 1), Ctx(t0))
  h = H2.Update(h, nil, O(t0 + 49 * 3600, 100, nil, 5, 1), Ctx(t0 + 49 * 3600, t0))
  local r49 = H2.DecodeH2(h); Same(#r49, 1); Same(r49[1].dm, 0, "a new point, not a 49-hour segment")
  -- time passing without a scan never touches anything: Retain with the same scan's context changes nothing
  local same = select(3, H2.Retain(h, nil, Ctx(t0 + 49 * 3600)))
  Same(same, "same")

  -- missing Recent Price: an empty field, never 0 and never the minimum; a genuine one-price item says r = p (dr 0)
  h = H2.Update(nil, nil, O(b1, 700, nil, 4, 2), Ctx(b1))
  Same(h, ("%d,0,700,,4,2|%d:%d,700,,4,2"):format(math.floor(b1 / 60), D0, D0))
  local hs = H2.Update(nil, nil, O(b1, 700, 700, 4, 2), Ctx(b1))
  Same(hs, ("%d,0,700,0,4,2|%d:%d,700,0,4,2"):format(math.floor(b1 / 60), D0, D0))
  -- a day whose closing scan had no Recent Price keeps the range of the scans that did, as absolute values
  h = H2.Update(nil, nil, O(b1, 700, 800, 4, 2), Ctx(b1))
  h = H2.Update(h, nil, O(b2, 710, 900, 4, 2), Ctx(b2, b1))
  h = H2.Update(h, nil, O(b3, 705, nil, 4, 2), Ctx(b3, b2))
  local _, dm = H2.DecodeH2(h)
  Same(dm[1].r, nil, "closing Recent Price unknown"); Same(dm[1].rlo, 800); Same(dm[1].rhi, 900)
  Check(h:find(("|%d:%d,705,,4,2,3,5,5,800,900,0,0"):format(D0, D0), 1, true), "absolute Recent range after an unknown close: " .. h)
  Same(H2.Obs(b1, 700, 699, 4, 2), nil, "a Recent Price below the same scan's minimum is not an A3 value and is refused")
  Same(H2.Obs(b1, 700, 0, 4, 2), nil); Same(H2.Obs(b1, 0, nil, 4, 2), nil); Same(H2.Obs(b1, 700, nil, 0, 2), nil); Same(H2.Obs(0 / 0, 700, nil, 4, 2), nil)

  -- UTC day boundaries: a minute before midnight and midnight are two days
  local late, mid = D0 * DAY + DAY - 60, (D0 + 1) * DAY
  h = H2.Update(nil, nil, O(late, 100, nil, 1, 1), Ctx(late))
  h = H2.Update(h, nil, O(mid, 100, nil, 1, 1), Ctx(mid, late))
  local rr, dd = H2.DecodeH2(h)
  Same(#dd, 2); Same(dd[1].d, D0); Same(dd[2].d, D0 + 1); Same(#rr, 1, "the ring merges across midnight (consecutive, identical)"); Same(rr[1].dm, 1)

  -- the clock moved back: an older observation than the item holds changes nothing
  local hBack, _, pBack = H2.Update(h, nil, O(late - 600, 100, nil, 1, 1), Ctx(late - 600, mid))
  Same(pBack, "stale"); Same(hBack, h)

  -- leap day and year boundary (2028-02-29 is day 21243; 2027-12-31 is 21183): plain day arithmetic, no calendar month logic
  for _, d in ipairs({ 21242, 21243, 21244, 21183, 21184 }) do
    local at = At(d, 12)
    local x = H2.Update(nil, nil, O(at, 50, 60, 2, 1), Ctx(at))
    Same(select(2, H2.DecodeH2(x))[1].d, d, "day " .. d)
  end
end

---------------------------------------------------------------------------
-- 1b. Retention boundaries, by hand: daily 30 guaranteed (up to 36), weekly to 60, two-week to 120
---------------------------------------------------------------------------
do
  -- one item listed once a day for 140 days; after each new day the tiers must hold exactly what the rules say
  local h, c, prev
  for k = 0, 139 do
    local d = D0 + k
    local at = At(d, 12)
    h, c = H2.Update(h, c, O(at, 1000 + k, 1100 + k, 10, 2), Ctx(at, prev))
    prev = at
    local _, days, bks = H2.Read(h, c)
    local T = d
    -- every listed day of ages 0..29 is a daily point; none is older than 35 days; the oldest daily day starts a calendar week (or is the first day)
    for age = 0, math.min(29, k) do
      local found = false
      for _, x in ipairs(days) do if x.d == T - age then found = true end end
      Check(found, ("day of age %d is a daily point (T %d)"):format(age, T))
    end
    Check(T - days[1].d <= 35, "no daily point older than 35 days: " .. (T - days[1].d))
    Check(days[1].d == D0 or days[1].d % 7 == 0, "the daily tier starts on a week boundary")
    if k >= 37 then Check(T - days[1].d >= 29 and days[1].d % 7 == 0, "by day 37 a whole week was folded, and the daily tier still reaches back to age 29") end
    for _, b in ipairs(bks or {}) do
      local e = b.k * b.s + b.s - 1
      if b.s == 7 then Check(14 * math.floor(b.k / 2) + 13 >= T - 60, "a weekly bucket whose pair ended more than 60 days back was merged") end
      if b.s == 14 then Check(e < T - 60 + 14, "two-week buckets only beyond the weekly reach") end
      Check(e >= T - 120, "nothing ending more than 120 days back")
      Check(b.n == math.min(b.s, b.n), "observed days within the bucket's days")
    end
  end
  -- a bucket ending exactly 120 days back stays, 121 goes (T chosen so a two-week bucket ends on the boundary)
  local kEnd = 14 * 1500 + 13
  for _, case in ipairs({ { 119, true }, { 120, true }, { 121, false } }) do
    local x = H2.Update(nil, nil, O(At(kEnd, 6), 10, nil, 1, 1), Ctx(At(kEnd, 6)))
    local T = kEnd + case[1]
    local a, b = H2.Retain(x, nil, Ctx(At(T, 6), At(kEnd, 6)))
    Same(b ~= nil, case[2], ("a bucket ending %d days back"):format(case[1]))
    Same(a, nil, "its daily point folded")
  end
end

---------------------------------------------------------------------------
-- 2. The strict reader: everything the writer never makes is refused (absent)
---------------------------------------------------------------------------
do
  local good = ("%d,0,900,100,100,10;360,0,500,100,70,8|%d:%d,1000,100,120,12,3,500,0,500,0,50,0"):format(D0 * 1440, D0, D0)
  Check(H2.DecodeH2(good), "the reference string reads")
  local bad = {
    "", "|", "x|1:1,1,,1,1", "1,0,5,,1,1", "|20000:", "|20000:20000,5,,1,1;", "|20001:20000,5,,1,1", "|20000:020000,5,,1,1",
    "|20000:20000,0,,1,1", "|20000:20000,5,,0,1", "|20000:20000,5,,1,0", "|20000:20000,5,,1,1!!", "|20000:20000,5,,1,1~", "|20000:20000,5,,1,1,1",
    "|20000:20000,5,,1,1,2,0,0,,,0,0", "|20000:20000,5,0,1,1,2,0,0,0,0,0,0", "|20000:20000,5,0,1,1,2,0,0,,0,0,0", "|20000:20000,5,,1,1,2,0,0,5,,0,0",
    "|20000:20000,5,,1,1,2,0,0,9,5,0,0", "|20000:20000,5,,1,1,2,6,0,,,0,0", "|20001:20000,5,,1,1;0,5,,1,1", "|20000:20000,5,,1,1|",
    "1,0,5,,1,1;0,0,5,,1,1;0,0,5,,1,1;0,0,5,,1,1;0,0,5,,1,1;0,0,5,,1,1;0,0,5,,1,1;0,0,5,,1,1;0,0,5,,1,1|20000:20000,5,,1,1",
    "28800000,5,5,,1,1;3,0,5,,1,1|20000:20000,5,,1,1", ("%d,0,5,,1,1|20000:20000,5,,1,1"):format(20001 * 1440),
    "|20000:20000,5, ,1,1", "|20000:20000,5,,1,1,2,0,0,,,1,0!~", "|20000:20000,5,,1,1,2~!", "|20000:20000,1e3,,1,1", "|20000:20000,-5,,1,1",
  }
  for _, s in ipairs(bad) do Same(H2.DecodeH2(s), nil, "refused: " .. s) end
  local goodC = "1428,14,5,4,400,10,20,450,5,5,3,1,1,2;2858,7,4,0,380,20,30,,,,2,1,1,3!~"
  Check(H2.DecodeC2(goodC), "a reference bucket list reads")
  local badC = { "", "1,7,0,0,5,0,0,,,,1,0,0,1", "1,7,8,0,5,0,0,,,,1,0,0,1", "1,7,2,3,5,0,0,5,0,0,1,0,0,1", "1,21,2,0,5,0,0,,,,1,0,0,1",
    "1,7,2,1,5,0,0,,,,1,0,0,1", "1,7,2,0,5,0,0,6,0,0,1,0,0,1", "1,7,2,1,5,0,0,6,7,0,1,0,0,1", "1,7,2,0,5,0,0,,7,,1,0,0,1", "1,7,2,0,5,0,0,,7,6,1,0,0,1",
    "1,7,2,0,5,0,0,,,,1,2,0,1", "1,7,2,0,5,0,0,,,,1,0,,1", "1,7,2,0,5,0,0,,,,0,0,0,1", "1,7,2,0,5,0,0,,,,1,0,0,0", "2,7,1,0,5,0,0,,,,1,0,0,1;2,7,1,0,5,0,0,,,,1,0,0,1",
    "4,7,1,0,5,0,0,,,,1,0,0,1;2,14,1,0,5,0,0,,,,1,0,0,1", "1,7,2,0,5,0,0,,,,1,0,0,1~!", "1,7,2,0,6,0,0,,,,1,0,0,1;", "01,7,2,0,5,0,0,,,,1,0,0,1" }
  for _, s in ipairs(badC) do Same(H2.DecodeC2(s), nil, "refused bucket text: " .. s) end
  -- the append path refuses what the full reader refuses: a day sequence that does not add up to the header, a broken first or newest point
  local at = At(D0 + 3, 9)
  for _, txt in ipairs({ ("|%d:%d,5,,1,1;2,5,,1,1"):format(D0 + 3, D0), ("|%d:%d,5,,1,1;x,5,,1,1"):format(D0 + 3, D0), ("|%d:%d,5,,1;3,5,,1,1"):format(D0 + 3, D0),
      ("|%d:%d,5,,1,1;3,5,,1"):format(D0 + 3, D0), ("|%d:%d,5,,1,1;;3,5,,1,1"):format(D0 + 3, D0), ("1,0,5,,1|%d:%d,5,,1,1;3,5,,1,1"):format(D0 + 3, D0) }) do
    local out, _, path = H2.Update(txt, nil, O(at, 9, nil, 1, 1), Ctx(at, at - 600))
    Same(path, "replaced", "a damaged string is replaced, never appended to: " .. txt)
    Same(out, ("%d,0,9,,1,1|%d:%d,9,,1,1"):format(math.floor(at / 60), D0 + 3, D0 + 3))
  end
  -- a bucket list that overlaps the daily points is refused (the newer evidence, the daily points, wins)
  local h = ("|%d:%d,5,,1,1"):format(D0, D0)
  local _, days, bks, why = H2.Read(h, ("%d,7,1,0,5,0,0,,,,1,0,0,1"):format(math.floor(D0 / 7)))
  Check(days ~= nil); Same(bks, nil); Same(why, "c2")
end

---------------------------------------------------------------------------
-- 3. The tiers against the independent model, through History2 directly (byte for byte)
---------------------------------------------------------------------------
local function Calendar(rng, nItems)
  -- a market's accepted scans: bursts of several scans a day, quiet days, long gaps (crossing 30, 60 and 120 days), cut scans, partial scans,
  -- items that come and go, prices and supply that move or stay, Recent Price sometimes unknown
  local scans, day, at = {}, D0 + rng:Int(0, 6), 0
  local state = {}
  for id = 1, nItems do state[id] = { p = rng:Int(10, 5000), t = rng:Int(1, 40), l = rng:Int(1, 6), live = rng:Chance(0.7) } end
  local n = rng:Int(20, 140)
  for _ = 1, n do
    local gap = rng:Pick({ 0, 0, 0, 1, 1, 1, 2, 3, 6, 9, 25, 40, 70, 130 })
    day = day + gap
    local per = rng:Pick({ 1, 1, 2, 3, 5 })
    local minute = rng:Int(0, 200)
    for _ = 1, per do
      minute = minute + rng:Pick({ 0, 1, 30, 60, 240 })
      if minute >= 1440 then break end
      local sc = { at = day * DAY + minute * 60 + rng:Int(0, 59), whole = not rng:Chance(0.12), partial = rng:Chance(0.15) and rng:Int(1, 5) or 0, items = {} }
      for id, s in pairs(state) do
        if rng:Chance(0.12) then s.live = not s.live end
        if s.live then
          if rng:Chance(0.4) then s.p = math.max(1, s.p + rng:Int(-50, 50)) end
          if rng:Chance(0.4) then s.t = math.max(1, s.t + rng:Int(-5, 5)) end
          if rng:Chance(0.2) then s.l = math.max(1, s.l + rng:Int(-1, 1)) end
          local r = s.p + rng:Pick({ 0, 0, 3, 40, 200 })
          if rng:Chance(0.15) then r = nil end
          sc.items[id] = { p = s.p, r = r, t = s.t, l = s.l }
        end
      end
      scans[#scans + 1] = sc
    end
  end
  return scans
end

local paths = { fast = 0, full = 0, new = 0, replaced = 0, stale = 0, same = 0, malformed = 0 }
do
  local SEEDS = tonumber(os.getenv("H2_SEEDS") or "") or 120
  local compared = 0
  for seed = 1, SEEDS do
    local rng = FX.Rng(9100000 + seed)
    local nItems = rng:Int(1, 6)
    local model = REF.H2New()
    local h2, c2, lastAt = {}, {}, nil
    for _, sc in ipairs(Calendar(rng, nItems)) do
      if REF.H2Scan(model, sc) then
        local ctx = Ctx(sc.at, lastAt)
        for id = 1, nItems do
          local o = sc.items[id]
          local a, b, path
          if o then a, b, path = H2.Update(h2[id], c2[id], O(sc.at, o.p, o.r, o.t, o.l, sc.partial > 0), ctx)
          elseif h2[id] or c2[id] then a, b, path = H2.Retain(h2[id], c2[id], ctx) end
          if path then paths[path] = paths[path] + 1 h2[id], c2[id] = a, b end
        end
        lastAt = sc.at
        -- compare after every recorded scan, every item: the whole saved text
        for id = 1, nItems do
          local eh, ec = REF.H2Text(REF.H2Expect(model, id))
          if eh ~= h2[id] or ec ~= c2[id] then
            error(("seed %d item %d after the scan at %d (day %d):\n  h2   %s\n  want %s\n  c2   %s\n  want %s"):format(9100000 + seed, id, sc.at, math.floor(sc.at / DAY),
              tostring(h2[id]), tostring(eh), tostring(c2[id]), tostring(ec)))
          end
          compared = compared + 1
          -- invariants that hold whatever the model says
          local ring, days, bks = H2.Read(h2[id], c2[id])
          Check(not ring or #ring <= 8, "ring bound")
          for _, b in ipairs(bks or {}) do
            Check(b.plo <= b.pm and b.pm <= b.phi and b.tlo <= b.tm and b.tm <= b.thi, "lo <= mean <= hi")
            if b.rm then Check(b.rlo <= b.rm and b.rm <= b.rhi, "Recent lo <= mean <= hi") end
            local e = REF.H2Expect(model, id)
            for _, eb in ipairs(e.buckets) do
              if eb.k == b.k and eb.s == b.s then
                Check(math.abs(b.pm - eb.exact.pm) <= 1 and math.abs(b.tm - eb.exact.tm) <= 1 and math.abs(b.lm - eb.exact.lm) <= 1, "means within 1 of the exact mean of the days")
                if b.rm then Check(math.abs(b.rm - eb.exact.rm) <= 1, "Recent mean within 1 of exact") end
              end
            end
          end
        end
      end
    end
  end
  Check(paths.fast > 1000 and paths.full > 100 and paths.new > 50, ("both paths exercised: fast %d, full %d, new %d"):format(paths.fast, paths.full, paths.new))
  print(("  model comparison (History2 direct): %d seeds, %d item states compared byte for byte; paths fast %d, full %d, new %d, same %d"):format(SEEDS, compared, paths.fast, paths.full, paths.new, paths.same))
end

---------------------------------------------------------------------------
-- 4. The same through the real commit pipeline (records, distribution, stepped commit), from Prices.Observation
---------------------------------------------------------------------------
local KEYS = { "Realm|Alliance", "Realm|Horde" }
local function Records(rng, sc)
  -- listings that reproduce each item's minimum p, items t and listings l, with a second price for some (so a distribution and a Recent Price exist)
  local recs = {}
  for id, o in pairs(sc.items) do
    local l, t = o.l, o.t
    if l > t then l = t end
    local multi = l >= 2 and o.r ~= nil and o.r > o.p
    for k = 1, l do
      local count = (k == l) and (t - (l - 1)) or 1
      local unit = (multi and k == l) and (o.p + rng:Int(1, 400)) or o.p
      recs[#recs + 1] = { item = id, count = count, buyout = unit * count }
    end
  end
  return recs
end

local function CommitScan(t, key, sc, rng)
  local PR = t.W.Prices
  local b = PR.NewBatch()
  for _, r in ipairs(Records(rng, sc)) do b:Add(r.item, r.count, r.buyout, true) end
  local items, n, _, _, dist = b:Items()
  local scan = { realm = "Realm", side = key:match("|(.*)$"), at = sc.at, complete = sc.whole and sc.partial == 0, cut = not sc.whole or nil, read = b.read, used = b.used,
    partial = sc.partial, n = n, items = items, dist = dist, alg = dist and 1 or nil }
  local job, why = PR.BeginCommit(key, scan)
  if not job then return false, why end
  local limit = rng:Pick({ 1, 3, 17, 120, math.huge })
  while not job:Step(limit) do end
  return job:Apply()
end

do
  local t = Setup(nil)
  local PR, MK = t.W.Prices, t.W.Market
  local SEEDS = tonumber(os.getenv("H2_PIPE_SEEDS") or "") or 25
  local checked = 0
  for seed = 1, SEEDS do
    t.c.TwichUIWorkshopDB = nil
    local rng = FX.Rng(9200000 + seed)
    local nItems = rng:Int(2, 8)
    local models = { REF.H2New(), REF.H2New() }
    local cals = { Calendar(rng, nItems), Calendar(rng, nItems) }
    -- interleave the two markets' scans by time
    local all = {}
    for mi = 1, 2 do for _, sc in ipairs(cals[mi]) do all[#all + 1] = { mi = mi, sc = sc } end end
    table.sort(all, function(a, b) if a.sc.at ~= b.sc.at then return a.sc.at < b.sc.at end return a.mi < b.mi end)
    for _, e in ipairs(all) do
      local key, model = KEYS[e.mi], models[e.mi]
      local otherBefore = Ser(t.DB() and t.DB().markets[KEYS[3 - e.mi]])
      local ok, why = CommitScan(t, key, e.sc, rng)
      if ok then
        -- what the history must have recorded: the A3 observation of the saved scan, item by item
        local info = PR.Market(key)
        local scan = { at = e.sc.at, whole = e.sc.whole, partial = e.sc.partial, items = {} }
        for id = 1, nItems do
          local obs = PR.Observation(info, id)
          if obs then
            scan.items[id] = { p = obs.p, r = obs.r, t = obs.t, l = obs.l }
            if obs.r then Check(obs.rsrc == "dist" or (obs.rsrc == "single" and obs.r == obs.p), "rsrc says where r came from") end
          end
        end
        local fed = REF.H2Scan(model, scan)
        local flags = tonumber(t.DB().markets[key].scans[#t.DB().markets[key].scans]:match("^%d+,%d+,(%d+),"))
        Same(math.floor(flags / 64) % 2 == 1, fed, "scan log flag 64 says whether the scan was recorded")
        for id = 1, nItems do
          local eh, ec = REF.H2Text(REF.H2Expect(model, id))
          local m = t.DB().markets[key]
          if eh ~= (m.h2 and m.h2[id]) or ec ~= (m.c2 and m.c2[id]) then
            error(("pipeline seed %d market %s item %d at %d:\n  h2   %s\n  want %s\n  c2   %s\n  want %s"):format(9200000 + seed, key, id, e.sc.at,
              tostring(m.h2 and m.h2[id]), tostring(eh), tostring(m.c2 and m.c2[id]), tostring(ec)))
          end
          checked = checked + 1
        end
        -- the newest ring point of a listed item IS the observation (nothing recalculated)
        if fed then
          for id, o in pairs(scan.items) do
            local ring = H2.DecodeH2(t.DB().markets[key].h2[id])
            local x = ring[#ring]
            Check(x.p == o.p and x.r == o.r and x.t == o.t and x.l == o.l, "the ring's newest point is Prices.Observation's")
          end
          local hi = t.DB().markets[key].h2info
          local bytes = 0
          for _, s in pairs(t.DB().markets[key].h2) do bytes = bytes + #s end
          for _, s in pairs(t.DB().markets[key].c2) do bytes = bytes + #s end
          Same(hi.bytes, bytes, "h2info.bytes is the text's size"); Same(hi.at, e.sc.at)
        end
      else
        Same(why, "kept", "the only refusal in these calendars: an incomplete scan over a complete one")
      end
      Same(Ser(t.DB().markets[KEYS[3 - e.mi]]), otherBefore, "the other market is untouched (isolation)")
    end
  end
  print(("  model comparison (commit pipeline): %d seeds, two interleaved markets, %d item states compared byte for byte"):format(SEEDS, checked))
end

---------------------------------------------------------------------------
-- 4b. A distribution that fails its check records NO Recent Price (the minimum is never written in its place)
---------------------------------------------------------------------------
do
  local t = Setup(nil)
  local PR = t.W.Prices
  local b = PR.NewBatch()
  b:Add(10, 1, 500, true); b:Add(10, 1, 900, true); b:Add(11, 2, 400, true)
  local items, n, _, _, dist = b:Items()
  Check(dist[10], "item 10 has two prices")
  dist[10] = "1,600,500,500,500,900,900,1|500:1:1;900:1:1"   -- r 600 claimed with the wrong 'near' figure: refused by the checked decoder
  local ok = PR.Commit("Realm|Alliance", { realm = "Realm", side = "Alliance", at = At(D0, 10), complete = true, read = 3, used = 3, n = n, items = items, dist = dist, alg = 1 })
  Check(ok)
  local m = t.DB().markets["Realm|Alliance"]
  Same(m.snap.alg, nil, "the distribution was not saved")
  Check(m.h2[10]:find("^%d+,0,500,,2,2|"), "item 10: Recent Price unknown, written as an empty field: " .. m.h2[10])
  Check(m.h2[11]:find("^%d+,0,200,,2,1|"), "item 11 (one price) also unknown: without checked evidence even a one-price item has no Recent Price")
  Same(PR.Observation(PR.Market("Realm|Alliance"), 10).noRecent, "noevidence")
  -- a checked distribution that lacks the entry of an item with a second price (A3's "missing"): that item has NO Recent Price, while a
  -- genuine one-price item of the same scan has r = p
  local b2 = PR.NewBatch()
  b2:Add(20, 1, 500, true); b2:Add(20, 1, 900, true); b2:Add(21, 1, 300, true); b2:Add(22, 1, 50, true); b2:Add(22, 1, 70, true)
  local items2, n2, _, _, dist2 = b2:Items()
  Check(dist2[20] and dist2[22] and not dist2[21])
  dist2[20] = nil
  Check(PR.Commit("Realm|Horde", { realm = "Realm", side = "Horde", at = At(D0, 10), complete = true, read = 5, used = 5, n = n2, items = items2, dist = dist2, alg = 1 }))
  local mh = t.DB().markets["Realm|Horde"]
  Same(mh.snap.alg, 1, "the rest of the distribution passed its check")
  Same(PR.Observation(PR.Market("Realm|Horde"), 20).noRecent, "missing")
  Check(mh.h2[20]:find("^%d+,0,500,,2,2|"), "the item missing its entry: no Recent Price, never the minimum: " .. mh.h2[20])
  Check(mh.h2[21]:find("^%d+,0,300,0,1,1|"), "the one-price item: Recent Price = minimum (dr 0): " .. mh.h2[21])
  Check(mh.h2[22]:find("^%d+,0,50,%d+,2,2|"), "the item with its entry: its Recent Price")
  -- the chart API: the minimum has a point that day, the Recent Price has none and says why
  local MK = t.W.Market
  local hmin = assert(MK.History(10, "min", { market = "Realm|Alliance", now = At(D0, 12) }))
  local hrec = assert(MK.History(10, "recent", { market = "Realm|Alliance", now = At(D0, 12) }))
  Same(#hmin.points, 2, "a day point and an observation"); Same(#hrec.points, 0, "no Recent Price point, and no made-up one")
  Same(hrec.gaps[#hrec.gaps].reason, "norecent"); Same(hrec.gaps[#hrec.gaps].from, D0)
end

---------------------------------------------------------------------------
-- 5. Market.History: chart-ready, nothing invented, gap reasons agree with the model
---------------------------------------------------------------------------
do
  local t = Setup(nil)
  local PR, MK = t.W.Prices, t.W.Market
  local gapDays = {}
  for seed = 1, 12 do
    t.c.TwichUIWorkshopDB = nil
    local rng = FX.Rng(9300000 + seed)
    local nItems = rng:Int(2, 5)
    local model = REF.H2New()
    local key = KEYS[1]
    local lastAt
    for _, sc in ipairs(Calendar(rng, nItems)) do
      local ok = CommitScan(t, key, sc, rng)
      if ok then
        local info = PR.Market(key)
        local scan = { at = sc.at, whole = sc.whole, partial = sc.partial, items = {} }
        for id = 1, nItems do local o = PR.Observation(info, id) if o then scan.items[id] = { p = o.p, r = o.r, t = o.t, l = o.l } end end
        REF.H2Scan(model, scan)
        lastAt = sc.at
      end
    end
    local now = lastAt + 3600
    local info = PR.Market(key)
    for id = 1, nItems do
      local e = REF.H2Expect(model, id)
      for _, metric in ipairs({ "min", "recent", "supply", "listings" }) do
        local hs = assert(MK.History(id, metric, { market = key, now = now }))
        Same(hs.unit, metric == "min" and "copper" or (metric == "recent" and "copper" or metric == "supply" and "items" or "listings"))
        Check(hs.basis and hs.basis:find(metric == "supply" and "Listed" or "isting"), "basis says listing")
        local byDay = {}
        for _, x in ipairs(e and e.days or {}) do byDay[x.d] = x end
        local covered = {}
        for _, p in ipairs(hs.points) do
          if p.kind == "day" then
            local x = byDay[p.from]
            Check(x, "a day point exists only for a listed day")
            local want = ({ min = x.p, recent = x.r, supply = x.t, listings = x.l })[metric]
            Same(p.v, want, "closing value")
            Check(p.exact == true and p.provenance == "local")
            if metric == "min" then Same(p.lo, x.plo) Same(p.hi, x.phi) end
            covered[p.from] = true
          elseif p.kind == "week" or p.kind == "fortnight" then
            Same(p.exact, false, "a bucket is never exact"); Check(p.to - p.from + 1 == (p.kind == "week" and 7 or 14))
            for d = p.from, p.to do covered[d] = true end
          elseif p.kind == "obs" then
            Check(p.v ~= nil and p.at % 60 == 0 and p.exact)
          else
            error("no legacy point without legacy history: " .. p.kind)
          end
          Check(p.v ~= 0 or metric == "supply", "never a made-up zero")
        end
        -- every day without a point has the model's reason (recent: "norecent" for a listed day without a Recent Price)
        local reasons = {}
        for _, g in ipairs(hs.gaps) do for d = g.from, g.to do reasons[d] = g.reason end end
        local first = info.h2info.from
        for d = first, math.floor(now / DAY) do
          if not covered[d] then
            local why = REF.H2DayReason(model, id, d)
            if metric == "recent" and byDay[d] and not byDay[d].r and not byDay[d].rlo then why = "norecent" end
            if why == nil and not byDay[d] then why = reasons[d] end   -- a listed day already folded into a bucket that is out of range: n/a here
            local inBucket = false
            for _, b in ipairs(e and e.buckets or {}) do if d >= b.k * b.s and d <= b.k * b.s + b.s - 1 then inBucket = true end end
            if not inBucket and why then
              local beyond = d < first or d < math.floor(now / DAY) - 119
              if not beyond then Same(reasons[d], why, ("seed %d item %d %s day %d"):format(9300000 + seed, id, metric, d)) gapDays[why] = (gapDays[why] or 0) + 1 end
            end
          end
        end
      end
    end
  end

  for _, why in ipairs({ "noscan", "unlisted" }) do Check((gapDays[why] or 0) > 20, "gap reason compared with the model: " .. why .. " " .. tostring(gapDays[why])) end
  print(("  Market.History gap reasons compared with the model: noscan %d, unlisted %d, incomplete %d, unknown %d, norecent %d days"):format(gapDays.noscan or 0,
    gapDays.unlisted or 0, gapDays.incomplete or 0, gapDays.unknown or 0, gapDays.norecent or 0))
  -- the legacy join: the minimum series shows legacy days before recording began, labelled; Recent Price never does
  local t2 = Setup(nil)
  local PR2, MK2 = t2.W.Prices, t2.W.Market
  PR2.FEED_LEGACY_HISTORY, PR2.RECORD_HISTORY = true, false
  for d = 0, 3 do Check(PR2.Commit(KEYS[1], { realm = "Realm", side = "Alliance", at = At(D0 + d, 9), complete = true, read = 1, used = 1, n = 1, items = { [5] = ("%d,1,1,1,0"):format(300 + d) } })) end
  -- (the test switch also feeds the legacy history on the first recorded day, so the same day exists in both: it must be shown once)
  PR2.FEED_LEGACY_HISTORY, PR2.RECORD_HISTORY = true, true
  Check(PR2.Commit(KEYS[1], { realm = "Realm", side = "Alliance", at = At(D0 + 5, 9), complete = true, read = 1, used = 1, n = 1, items = { [5] = "400,1,1,1,0" } }))
  PR2.FEED_LEGACY_HISTORY = false
  Check(t2.DB().markets[KEYS[1]].hist[5]:find(("%d,400"):format(D0 + 5), 1, true), "the legacy history holds the recorded day too")
  local hs = assert(MK2.History(5, "min", { market = KEYS[1], now = At(D0 + 5, 12) }))
  local kinds = {}
  for _, p in ipairs(hs.points) do kinds[#kinds + 1] = p.kind .. ":" .. tostring(p.from or p.at) .. ":" .. tostring(p.v) .. ":" .. (p.provenance or "") end
  Same(table.concat(kinds, " "), ("legacy-day:%d:300:legacy legacy-day:%d:301:legacy legacy-day:%d:302:legacy legacy-day:%d:303:legacy day:%d:400:local obs:%d:400:local")
    :format(D0, D0 + 1, D0 + 2, D0 + 3, D0 + 5, math.floor(At(D0 + 5, 9) / 60) * 60))
  Same(hs.recordedFrom, D0 + 5)
  local gaps = {}
  for _, g in ipairs(hs.gaps) do gaps[#gaps + 1] = g.from .. "-" .. g.to .. ":" .. g.reason end
  Same(gaps[#gaps], ("%d-%d:beforev2"):format(D0 + 4, D0 + 4), "the day between: before version-2 recording, the legacy history had no point")
  local hr = assert(MK2.History(5, "recent", { market = KEYS[1], now = At(D0 + 5, 12) }))
  for _, p in ipairs(hr.points) do Check(p.provenance == "local", "Recent Price never uses the legacy minimum history") end
  local hsrc = assert(MK2.History(5, "min", { market = KEYS[1], now = At(D0 + 5, 12), sources = { "local" } }))
  for _, p in ipairs(hsrc.points) do Check(p.provenance == "local", "sources = local leaves the legacy points out") end
  Same(select(2, MK2.History(5, "price", { market = KEYS[1] })), "badmetric"); Same(select(2, MK2.History(5, "min", { market = "Realm|Nowhere" })), "nomarket")
  Same(select(2, MK2.History(5, "min", { market = KEYS[1], variant = true })), "variant")

  -- intraday marks: a recorded scan that did not list the item is "unlisted", a cut scan "incomplete"; a full ring makes older ones "notretained"
  local t3 = Setup(nil)
  local PR3, MK3 = t3.W.Prices, t3.W.Market
  local function S(at, items, extra)
    local sc = { realm = "Realm", side = "Alliance", at = at, complete = true, read = 1, used = 1, n = 1, items = items }
    for k, v in pairs(extra or {}) do sc[k] = v end
    return assert(PR3.Commit(KEYS[1], sc))
  end
  -- (whole reads that were not complete, so the cut scan at 4:00 is accepted: an incomplete scan never replaces a complete one)
  local inc = { complete = false }
  S(At(D0, 1), { [7] = "100,1,1,1,0" }, inc); S(At(D0, 2), { [8] = "100,1,1,1,0" }, inc); S(At(D0, 3), { [7] = "100,1,1,1,0" }, inc)
  S(At(D0, 4), { [7] = "100,1,1,1,0" }, { complete = false, cut = true })
  local hm = assert(MK3.History(7, "min", { market = KEYS[1], now = At(D0, 5) }))
  local marks = {}
  for _, mk in ipairs(hm.marks) do marks[#marks + 1] = (mk.at - At(D0, 0)) / 3600 .. ":" .. mk.reason end
  Same(table.concat(marks, " "), "2:unlisted 4:incomplete")
  local obs = 0
  for _, p in ipairs(hm.points) do if p.kind == "obs" then obs = obs + 1 end end
  Same(obs, 2, "two observations: the absence at 2:00 separates them")
  -- day-level reasons: a day with only a cut scan is "incomplete"; a whole read that was not recorded (the developer switch here) "unknown";
  -- a day without any scan "noscan"; a recorded day without the item "unlisted"
  S(At(D0 + 1, 4), { [7] = "100,1,1,1,0" }, { complete = false, cut = true })
  PR3.RECORD_HISTORY = false
  S(At(D0 + 2, 4), { [7] = "100,1,1,1,0" }, inc)
  PR3.RECORD_HISTORY = true
  S(At(D0 + 4, 4), { [8] = "100,1,1,1,0" }, inc)
  local hd = assert(MK3.History(7, "min", { market = KEYS[1], now = At(D0 + 4, 5) }))
  local g = {}
  for _, x in ipairs(hd.gaps) do g[#g + 1] = (x.from - D0) .. "-" .. (x.to - D0) .. ":" .. x.reason end
  Same(g[#g - 3] .. " " .. g[#g - 2] .. " " .. g[#g - 1] .. " " .. g[#g], "1-1:incomplete 2-2:unknown 3-3:noscan 4-4:unlisted")
end

---------------------------------------------------------------------------
-- 6. Atomicity: a failing or dropped commit at every new phase leaves the database deep-equal
---------------------------------------------------------------------------
do
  local t = Setup(nil)
  local PR = t.W.Prices
  local rng = FX.Rng(9400001)
  local function Items(nItems, k) local o = {} for id = 1, nItems do o[id] = ("%d,1,1,1,0"):format(100 + id + k) end return o end
  for d = 0, 45, 3 do Check(PR.Commit(KEYS[1], { realm = "Realm", side = "Alliance", at = At(D0 + d, 9), complete = true, read = 40, used = 40, n = 40, items = Items(40, d) })) end
  local before = Ser(t.DB())
  local scan = { realm = "Realm", side = "Alliance", at = At(D0 + 49, 9), complete = true, read = 20, used = 20, n = 20, items = Items(20, 99) }
  -- an error inside each kind of history work, at several points of the job
  for _, fname in ipairs({ "Update", "Retain" }) do
    for _, after in ipairs({ 0, 1, 7, 15 }) do
      local real, calls = H2[fname], 0
      local H2t = t.W.History2
      local realT = H2t[fname]
      H2t[fname] = function(...) calls = calls + 1 if calls > after then error("history step failed") end return realT(...) end
      local job = assert(PR.BeginCommit(KEYS[1], scan))
      local good = pcall(function() while not job:Step(rng:Int(1, 30)) do end return job:Apply() end)
      H2t[fname] = realT
      Check(not good, fname .. " failure raised after " .. after)
      Same(Ser(t.DB()), before, ("a failing %s after %d calls leaves the database deep-equal"):format(fname, after))
    end
  end
  -- a job dropped in each phase, and one ready but never applied
  local job = assert(PR.BeginCommit(KEYS[1], scan))
  local seen = {}
  while true do
    seen[job.phase] = true
    Same(Ser(t.DB()), before, "nothing is written while in phase " .. job.phase)
    if job:Step(2) then break end
  end
  Check(seen.hist and seen.sweep and seen.sweepc, "the job went through the history phases")
  Same(Ser(t.DB()), before, "ready, not applied: nothing written")
  -- another commit got in first: the stale job refuses instead of undoing it
  Check(PR.Commit(KEYS[1], scan))
  local after = Ser(t.DB())
  local ok, why = job:Apply()
  Same(ok, false); Same(why, "changed"); Same(Ser(t.DB()), after, "the refused Apply wrote nothing")
end

---------------------------------------------------------------------------
-- 7. The budget guard
---------------------------------------------------------------------------
do
  local t = Setup(nil)
  local PR, MK = t.W.Prices, t.W.Market
  -- 60 items: 10 dense (listed every scan, prices moving within the day), 50 sparse (listed on a few days only); three scans a day
  local function Day(d, k)
    local items = {}
    for id = 1, 60 do
      local dense = id <= 10
      if dense or (d % 13 == id % 13 and k == 1) then items[id] = ("%d,1,%d,%d,0"):format(100 + (d * 7 + k * 3 + id) % 50, 1 + k, 3 + (d + k) % 4) end
    end
    return items
  end
  for d = 0, 70 do
    for k = 1, 3 do
      local it = Day(d, k)
      local n = 0 for _ in pairs(it) do n = n + 1 end
      Check(PR.Commit(KEYS[1], { realm = "Realm", side = "Alliance", at = At(D0 + d, 4 * k), complete = true, read = n, used = n, n = n, items = it }))
    end
  end
  local m0 = Clone(t.DB().markets[KEYS[1]])
  local bytes0 = m0.h2info.bytes
  Same(m0.compact, nil, "no compaction under the real budget")
  -- the ladder, step by step: a budget just under the market's size takes step 1 only
  local function Run(budget)
    t.c.TwichUIWorkshopDB = Clone({ v = 2, markets = { [KEYS[1]] = m0 } })
    PR.HISTORY_BUDGET = budget
    local it = Day(71, 1)
    local n = 0 for _ in pairs(it) do n = n + 1 end
    Check(PR.Commit(KEYS[1], { realm = "Realm", side = "Alliance", at = At(D0 + 71, 4), complete = true, read = n, used = n, n = n, items = it }))
    PR.HISTORY_BUDGET = 48 * 1024 * 1024
    return t.DB().markets[KEYS[1]]
  end
  local m1 = Run(bytes0 - 1)
  Same(m1.compact.level, 1, "step 1 (condensing old day ranges) was enough"); Check(m1.compact.bytes <= bytes0 - 1 and m1.compact.before >= bytes0 - 50)
  Same(m1.compact.over, nil)
  local T = D0 + 71
  for id = 1, 10 do
    local ring, days = H2.DecodeH2(m1.h2[id])
    local r0, d0 = H2.DecodeH2(m0.h2[id])
    for _, x in ipairs(days) do
      if T - x.d < 14 then Check(not x.cf and x.plo, "the last 14 days keep their ranges") else Check(x.cf or x.n == 1 or (x.plo == x.p and x.phi == x.p), "older days condensed") end
    end
    -- closing values of every day are intact
    local closing = {}
    for _, x in ipairs(d0) do closing[x.d] = x.p .. "/" .. tostring(x.r) .. "/" .. x.t .. "/" .. x.l end
    for _, x in ipairs(days) do if closing[x.d] then Same(x.p .. "/" .. tostring(x.r) .. "/" .. x.t .. "/" .. x.l, closing[x.d], "closing values survive") end end
  end
  Same(Ser(m1.hist), Ser(m0.hist), "legacy history untouched"); Same(Ser(m1.items), Ser(t.DB().markets[KEYS[1]].items))
  local info = MK.Info({ market = KEYS[1], now = At(T, 5) })
  Same(info.compact.level, 1); Check(info.history and info.history.bytes == m1.h2info.bytes, "Market.Info reports the history's size and the compaction")
  -- a budget only step 2 can meet: sparse items fold their old weeks early
  local m2 = Run(m1.compact.bytes - 1)
  Check(m2.compact.level >= 2, "the ladder went on to step 2")
  local folded = 0
  for id = 11, 60 do
    local _, days, bks = H2.Read(m2.h2[id], m2.c2[id])
    for _, x in ipairs(days or {}) do Check(T - x.d < 14 or (x.d >= 7 * math.floor((T - 13) / 7)), "sparse items keep only their protected days daily") end
    for _, b in ipairs(bks or {}) do if b.s == 7 and b.k * 7 + 6 >= T - 30 then folded = folded + 1 end end
  end
  Check(folded > 0, "some sparse weeks were folded early")
  for id = 1, 10 do
    local _, days = H2.DecodeH2(m2.h2[id])
    local recent = 0 for _, x in ipairs(days) do if x.d >= T - 29 then recent = recent + 1 end end
    Same(recent, 30, "dense items are not folded early")
  end
  -- an impossible budget: the whole ladder runs, then it is reported, and nothing protected is removed
  local mRef = Run(2 ^ 40)
  Same(mRef.compact, nil)
  local m3 = Run(10)
  Same(m3.compact.level, 3); Same(m3.compact.over, true, "the unresolved budget is recorded")
  -- against the same commit without a budget: the ring, the protected days and every closing value are identical; buckets that both have
  -- keep their price figures
  for id = 1, 60 do
    local ra, da, ba = H2.Read(mRef.h2[id], mRef.c2[id])
    local rb, db, bb = H2.Read(m3.h2[id], m3.c2[id])
    Same(Ser(rb or {}), Ser(ra or {}), "the ring is never compacted (item " .. id .. ")")
    local keep = {}
    for _, x in ipairs(db or {}) do keep[x.d] = x end
    for _, x in ipairs(da or {}) do
      local y = keep[x.d]
      if T - x.d < 14 then Same(Ser(y), Ser(x), "a protected day is identical") end
      if y then Same(y.p .. "/" .. tostring(y.r) .. "/" .. y.t .. "/" .. y.l .. "/" .. y.n, x.p .. "/" .. tostring(x.r) .. "/" .. x.t .. "/" .. x.l .. "/" .. x.n, "closing values and scan count") end
    end
    local bk = {}
    for _, b in ipairs(bb or {}) do bk[b.k .. "/" .. b.s] = b end
    for _, b in ipairs(ba or {}) do
      local y = bk[b.k .. "/" .. b.s]
      Check(y, "a bucket is never deleted by the guard")
      Same(table.concat({ y.n, y.nr, y.plo, y.pm, y.phi, tostring(y.rm), tostring(y.rlo), tostring(y.rhi), y.tm, y.lm }, "/"),
        table.concat({ b.n, b.nr, b.plo, b.pm, b.phi, tostring(b.rm), tostring(b.rlo), tostring(b.rhi), b.tm, b.lm }, "/"), "bucket price and mean figures kept")
    end
  end
  for _, s in pairs(m3.c2) do
    for _, b in ipairs(H2.DecodeC2(s)) do if b.k * b.s + b.s - 1 < T - 60 then Same(b.tlo, nil, "old supply ranges dropped") else Check(b.tlo, "newer supply ranges kept") end end
  end
  Same(MK.Info({ market = KEYS[1], now = At(T, 5) }).compact.over, true)
  -- the account budget counts the other markets from their own records
  t.c.TwichUIWorkshopDB = Clone({ v = 2, markets = { [KEYS[1]] = m0, [KEYS[2]] = { f = 3, scope = "full", realm = "Realm", side = "Horde", at = At(D0, 1), items = {}, h2info = { v = 1, bytes = 2 ^ 31 } } } })
  PR.ACCOUNT_BUDGET = 2 ^ 31
  Check(PR.Commit(KEYS[1], { realm = "Realm", side = "Alliance", at = At(D0 + 71, 4), complete = true, read = 1, used = 1, n = 1, items = { [1] = "100,1,1,1,0" } }))
  PR.ACCOUNT_BUDGET = 96 * 1024 * 1024
  Check(t.DB().markets[KEYS[1]].compact, "over the account budget because of another market: this market is compacted")
end

---------------------------------------------------------------------------
-- 8. Compatibility: a later format, malformed strings, the developer switch, the frozen legacy history, 1.3
---------------------------------------------------------------------------
do
  local t = Setup(nil)
  local PR, MK = t.W.Prices, t.W.Market
  local function S(at, items, extra)
    local n = 0 for _ in pairs(items) do n = n + 1 end
    local sc = { realm = "Realm", side = "Alliance", at = at, complete = true, read = n, used = n, n = n, items = items }
    for k, v in pairs(extra or {}) do sc[k] = v end
    return PR.Commit(KEYS[1], sc)
  end
  Check(S(At(D0, 1), { [1] = "100,1,1,1,0", [2] = "200,1,1,1,0" }))
  -- a later build's format: carried, never read, never written
  local db = t.DB()
  db.markets[KEYS[1]].h2info.v = 2
  local h2Before, c2Before = Ser(db.markets[KEYS[1]].h2), Ser(db.markets[KEYS[1]].c2)
  Same(select(2, MK.History(1, "min", { market = KEYS[1], now = At(D0, 2) })), "format")
  Same(MK.Info({ market = KEYS[1], now = At(D0, 2) }).history.state, "future")
  Check(S(At(D0, 2), { [1] = "110,1,1,1,0" }))
  Same(Ser(t.DB().markets[KEYS[1]].h2), h2Before); Same(Ser(t.DB().markets[KEYS[1]].c2), c2Before); Same(t.DB().markets[KEYS[1]].h2info.v, 2)
  Same(t.DB().markets[KEYS[1]].scans[2]:match("^%d+,%d+,(%d+),"), "3", "not recorded")
  t.DB().markets[KEYS[1]].h2info.v = 1
  -- malformed strings: absent to the reader, left alone by the sweep, replaced by the item's next observation
  t.DB().markets[KEYS[1]].h2[2] = "garbage|1:1"
  t.DB().markets[KEYS[1]].h2[3] = { "not a string" }
  local hs = assert(MK.History(2, "min", { market = KEYS[1], now = At(D0, 3) }))
  Same(hs.damaged, "h2"); Same(#hs.points, 0)
  Check(S(At(D0, 3), { [1] = "120,1,1,1,0" }))
  Same(t.DB().markets[KEYS[1]].h2[2], "garbage|1:1", "the sweep never rewrites what it cannot read")
  Same(t.DB().markets[KEYS[1]].h2[3], nil, "a value that is not a string is not carried")
  Check(S(At(D0, 4), { [2] = "130,1,1,1,0" }))
  Check(t.DB().markets[KEYS[1]].h2[2]:find("^%d+,0,130,,1,1|%d+:%d+,130,,1,1$"), "replaced by the next observation")
  -- the developer switch: off = carried forward untouched, not recorded
  PR.RECORD_HISTORY = false
  local snap = Ser(t.DB().markets[KEYS[1]].h2)
  Check(S(At(D0, 5), { [1] = "140,1,1,1,0" }))
  Same(Ser(t.DB().markets[KEYS[1]].h2), snap); PR.RECORD_HISTORY = true
  -- cut and changed scans add nothing (on a market whose saved scan is incomplete, so they are accepted at all); the log says they happened
  local K3 = "Realm|Neutral"
  local function S3(at, items, extra)
    local sc = { realm = "Realm", side = "Neutral", at = at, complete = false, read = 1, used = 1, n = 1, items = items, partial = 2 }
    for k, v in pairs(extra or {}) do sc[k] = v end
    return PR.Commit(K3, sc)
  end
  Check(S3(At(D0, 6), { [1] = "150,1,1,1,0" }))   -- a whole read with records lacking information: recorded, marked "!"
  Check(S3(At(D0, 7), { [1] = "160,1,1,1,0" }, { cut = true }))
  Check(S3(At(D0, 8), { [1] = "170,1,1,1,0" }, { changed = true }))
  local ring = H2.DecodeH2(t.DB().markets[K3].h2[1])
  Same(#ring, 1); Same(ring[1].p, 150, "cut / changed scans never reach the ring"); Same(ring[1].pf, true, "the partial-information flag")
  Same(PR.Market(K3).h2info.at, At(D0, 6)); Same(#t.DB().markets[K3].scans, 3, "all three are in the scan log")
  -- the legacy history stays frozen while the version-2 history records
  Same(next(t.DB().markets[KEYS[1]].hist), nil, "no legacy history was written by a format 3 commit")
  -- a database the released 1.3 code wrote is still held after A4 data exists (the full five-step proof is test_workshop_schema.lua section 9)
  Same(PR.Held(), false); Same(t.DB().v, 2)
end

print(("PASSED test_workshop_history2 (paths: fast %d, full %d, new %d, same %d)"):format(paths.fast, paths.full, paths.new, paths.same))
