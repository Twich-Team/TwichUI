-- A1 revision prototype (throwaway, offline, synthetic): daily + intraday history layouts compared by size, update cost, query cost
-- and saved-file load time. Not production code, not part of the test suite.
-- Usage: lua5.1 history.lua [design|all] [schedule] [sample]
--   design   d14 | d30 | adapt | hybrid | d30ring | d14ring | hybridring | all (default all)
--   schedule casual (1 scan on 80% of days) | active (3 scans a day, 4 h apart) | heavy (8 a day, 90 min apart) (default active)
--   sample   items simulated (default 2000); figures for 10k/20k/40k items are this sample scaled linearly
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local clock = os.clock
local N = function(v) return ("%.0f"):format(v) end

local DESIGNS = {
  d14        = { daily = 14 },
  d30        = { daily = 30 },
  adapt      = { daily = 14, tracked = 30, trackedShare = 0.10 },
  hybrid     = { daily = 30, rangeDays = 14 },   -- 30 daily points for all; the intraday range fields only on the newest 14
  d14ring    = { daily = 14, ring = 4 },
  d30ring    = { daily = 30, ring = 4 },
  hybridring = { daily = 30, rangeDays = 14, ring = 4 },
  hybridring8 = { daily = 30, rangeDays = 14, ring = 8 },
  d30ring8   = { daily = 30, ring = 8 },
}
local SCHED = {
  casual = { perDay = 1, dayProb = 0.8, gapMin = 0 },
  active = { perDay = 3, dayProb = 1.0, gapMin = 240 },
  heavy  = { perDay = 8, dayProb = 1.0, gapMin = 90 },
}
local RING_MIN = 48 * 60
local WEEK, RETAIN, WEEKLY_TO = 7, 120, 60

local function sim(cfg, sched, SAMPLE)
  local s = 4242
  local function rnd() s = (s * 16807) % 2147483647 return s / 2147483647 end
  local function rint(a, b) return a + floor(rnd() * (b - a + 1)) end
  local items = {}
  for i = 1, SAMPLE do
    local r = rnd()
    items[i] = { base = floor(10 ^ (1 + rnd() * 6.7)), sig = 0.02 + rnd() * 0.25,
      pres = r < 0.3 and 0.9 or (r < 0.7 and 0.35 or 0.06), keep = (cfg.tracked and rnd() < cfg.trackedShare) and cfg.tracked or cfg.daily,
      d = {}, w = {}, ring = {}, hot = nil, cold = "", p = nil, t = nil }
  end
  local DAY0, MIN0 = 20000, 20000 * 1440
  local stats = { upd = 0, updT = 0, foldT = 0, folds = 0 }
  local out = {}

  local function encodeHot(it, today)
    local parts, last = {}, nil
    for k = 1, #it.ring do
      local q = it.ring[k]
      parts[#parts + 1] = N(last and q.m0 - last or q.m0) .. "," .. N(q.m1 - q.m0) .. "," .. N(q.p) .. "," .. N(q.r - q.p) .. "," .. N(q.t) .. "," .. N(q.l) .. (q.flag or "")
      last = q.m0
    end
    local ring = table.concat(parts, ";")
    parts, last = {}, nil
    local newest = it.d[#it.d] and it.d[#it.d].day or 0
    for k = 1, #it.d do
      local q = it.d[k]
      local e = N(last and q.day - last or q.day) .. "," .. N(q.p) .. "," .. N(q.r - q.p) .. "," .. N(q.t) .. "," .. N(q.l)
      local rangeOk = not cfg.rangeDays or q.day > today - cfg.rangeDays
      if rangeOk and q.n > 1 and (q.plo ~= q.p or q.rlo ~= q.r or q.rhi ~= q.r or q.tlo ~= q.t or q.thi ~= q.t) then
        e = e .. "," .. N(q.n) .. "," .. N(q.p - q.plo) .. "," .. N(q.r - q.rlo) .. "," .. N(q.rhi - q.r) .. "," .. N(q.t - q.tlo) .. "," .. N(q.thi - q.t)
      end
      parts[#parts + 1] = e .. (q.partial and "!" or "")
      last = q.day
    end
    return ring .. "|" .. N(newest) .. ":" .. table.concat(parts, ";")
  end
  -- the incremental path production would use: only the last daily segment and the (small) ring are rewritten; a fold re-encodes
  local function segment(q, prevDay, today)
    local e = N(prevDay and q.day - prevDay or q.day) .. "," .. N(q.p) .. "," .. N(q.r - q.p) .. "," .. N(q.t) .. "," .. N(q.l)
    local rangeOk = not cfg.rangeDays or q.day > today - cfg.rangeDays
    if rangeOk and q.n > 1 and (q.plo ~= q.p or q.rlo ~= q.r or q.rhi ~= q.r or q.tlo ~= q.t or q.thi ~= q.t) then
      e = e .. "," .. N(q.n) .. "," .. N(q.p - q.plo) .. "," .. N(q.r - q.rlo) .. "," .. N(q.rhi - q.r) .. "," .. N(q.t - q.tlo) .. "," .. N(q.thi - q.t)
    end
    return e .. (q.partial and "!" or "")
  end
  local function incremental(it, old, sameDay, today, ringStr)
    -- old: the previous hot string. Cut the ring off, read the header, drop the last segment when it is today's, append.
    local bar = old:find("|", 1, true)
    local body = old:sub(bar + 1)
    local colon = body:find(":", 1, true)
    local newestOld = tonumber(body:sub(1, colon - 1))
    local pts = body:sub(colon + 1)
    local q = it.d[#it.d]
    if sameDay then
      local i = #pts
      while i > 0 and pts:byte(i) ~= 59 do i = i - 1 end
      local prev = it.d[#it.d - 1]
      pts = (i > 0 and pts:sub(1, i) or "") .. segment(q, prev and prev.day, today)
    else
      pts = (pts ~= "" and (pts .. ";") or "") .. segment(q, newestOld ~= 0 and newestOld or nil, today)
    end
    return ringStr .. "|" .. N(q.day) .. ":" .. pts
  end
  local function ringOnly(it)
    local parts, last = {}, nil
    for k = 1, #it.ring do
      local q = it.ring[k]
      parts[#parts + 1] = N(last and q.m0 - last or q.m0) .. "," .. N(q.m1 - q.m0) .. "," .. N(q.p) .. "," .. N(q.r - q.p) .. "," .. N(q.t) .. "," .. N(q.l) .. (q.flag or "")
      last = q.m0
    end
    return table.concat(parts, ";")
  end
  local function encodeCold(it)
    local parts = {}
    for k = 1, #it.w do
      local b = it.w[k]
      -- k,s,n, plo, pmean-plo, phi-pmean, rmean, rmean-rlo, rhi-rmean, tmean, tmean-tlo, thi-tmean, lmean (deltas keep it short)
      parts[k] = N(b.k) .. "," .. N(b.s) .. "," .. N(b.n) .. "," .. N(b.plo) .. "," .. N(max(0, b.pm - b.plo)) .. "," .. N(max(0, b.phi - b.pm)) .. "," ..
        N(b.rm) .. "," .. N(max(0, b.rm - b.rlo)) .. "," .. N(max(0, b.rhi - b.rm)) .. "," .. N(b.tm) .. "," .. N(max(0, b.tm - b.tlo)) .. "," ..
        N(max(0, b.thi - b.tm)) .. "," .. N(b.lm)
    end
    return table.concat(parts, ";")
  end
  local function decodeHot(str)   -- the cost of a real decode: every number read into arrays
    local ring, daily = str:match("^([^|]*)|(.*)$")
    local a = {}
    for v in ring:gmatch("%d+") do a[#a + 1] = tonumber(v) end
    for v in daily:gmatch("%d+") do a[#a + 1] = tonumber(v) end
    return a
  end
  local function wmerge(m1, n1, m2, n2) return floor((m1 * n1 + m2 * n2) / (n1 + n2) + 0.5) end

  for day = DAY0, DAY0 + 119 do
    if rnd() < sched.dayProb then
      for sIdx = 1, sched.perDay do
        local now = (day - DAY0) * 1440 + MIN0 + 8 * 60 + (sIdx - 1) * sched.gapMin
        local partial = rnd() < 0.15     -- some scans had records without all their information
        for i = 1, SAMPLE do
          local it = items[i]
          -- is it listed in this scan? the day's presence decides; later scans the same day keep it listed mostly
          if (sIdx == 1 and rnd() < it.pres) or (sIdx > 1 and it.listedToday and rnd() < 0.92) then
            it.listedToday = true
            -- a random walk: half the scans change the minimum, the Recent Price moves less, supply changes most scans
            if not it.p or rnd() < 0.5 then it.p = max(1, floor(it.base * (1 + it.sig * (rnd() - 0.5) * 0.6))) end
            local r = floor(it.p * (1 + it.sig * 0.6))
            if not it.t or rnd() < 0.7 then it.t = rint(1, 400) it.l = rint(1, 30) end
            local t, l = it.t, it.l
            local t0 = clock()
            if it.hot then decodeHot(it.hot) end
            if cfg.ring then
              while #it.ring > 0 and it.ring[1].m1 < now - RING_MIN do table.remove(it.ring, 1) end
              local q = it.ring[#it.ring]
              local flag = partial and "!" or nil
              if q and q.p == it.p and q.r == r and q.t == t and q.l == l and q.flag == flag then q.m1 = now
              else
                it.ring[#it.ring + 1] = { m0 = now, m1 = now, p = it.p, r = r, t = t, l = l, flag = flag }
                while #it.ring > cfg.ring do table.remove(it.ring, 1) end
              end
            end
            local q = it.d[#it.d]
            local sameDay = q and q.day == day
            if q and q.day == day then
              q.n = q.n + 1
              q.p, q.r, q.t, q.l = it.p, r, t, l
              q.plo, q.rlo, q.rhi, q.tlo, q.thi = min(q.plo, it.p), min(q.rlo, r), max(q.rhi, r), min(q.tlo, t), max(q.thi, t)
              q.partial = q.partial or partial
            else
              it.d[#it.d + 1] = { day = day, p = it.p, r = r, t = t, l = l, n = 1, plo = it.p, rlo = r, rhi = r, tlo = t, thi = t, partial = partial }
            end
            -- fold whole weeks once the daily tier spans more than keep + 6 days
            local folded = false
            local tf = clock()
            while #it.d > 0 and it.d[1].day < day - it.keep - 6 do
              local wk = floor(it.d[1].day / WEEK)
              local b
              while #it.d > 0 and floor(it.d[1].day / WEEK) == wk and it.d[1].day <= day - it.keep do
                local x = table.remove(it.d, 1)
                if not b then b = { k = wk, s = 7, n = 0, plo = x.plo, pm = 0, phi = x.p, rlo = x.rlo, rm = 0, rhi = x.rhi, tlo = x.tlo, tm = 0, thi = x.thi, lm = 0 } end
                b.pm = wmerge(b.pm, b.n, x.p, 1) b.rm = wmerge(b.rm, b.n, x.r, 1) b.tm = wmerge(b.tm, b.n, x.t, 1) b.lm = wmerge(b.lm, b.n, x.l, 1)
                b.n = b.n + 1
                b.plo, b.phi, b.rlo, b.rhi = min(b.plo, x.plo), max(b.phi, x.p), min(b.rlo, x.rlo), max(b.rhi, x.rhi)
                b.tlo, b.thi = min(b.tlo, x.tlo), max(b.thi, x.thi)
              end
              if not b then break end
              it.w[#it.w + 1] = b
              folded = true
            end
            -- weekly buckets older than 60 days merge pairwise into two-week buckets
            local k = 1
            while k <= #it.w do
              local b = it.w[k]
              if b.s == 7 and (b.k + 1) * 7 - 1 < day - WEEKLY_TO then
                local fk = floor(b.k / 2)
                local prev = it.w[k - 1]
                if prev and prev.s == 14 and prev.k == fk then
                  local n = prev.n + b.n
                  prev.pm, prev.rm, prev.tm, prev.lm = wmerge(prev.pm, prev.n, b.pm, b.n), wmerge(prev.rm, prev.n, b.rm, b.n),
                    wmerge(prev.tm, prev.n, b.tm, b.n), wmerge(prev.lm, prev.n, b.lm, b.n)
                  prev.plo, prev.phi, prev.rlo, prev.rhi = min(prev.plo, b.plo), max(prev.phi, b.phi), min(prev.rlo, b.rlo), max(prev.rhi, b.rhi)
                  prev.tlo, prev.thi, prev.n = min(prev.tlo, b.tlo), max(prev.thi, b.thi), n
                  table.remove(it.w, k)
                else b.s, b.k = 14, fk k = k + 1 end
                folded = true
              else k = k + 1 end
            end
            while #it.w > 0 and (it.w[1].k + 1) * it.w[1].s - 1 < day - RETAIN do table.remove(it.w, 1) folded = true end
            if folded then it.cold = encodeCold(it) stats.folds = stats.folds + 1 stats.foldT = stats.foldT + (clock() - tf) end
            local full = encodeHot(it, day)
            if it.hot and not folded and not cfg.rangeDays then
              local ti = clock()
              local inc = incremental(it, it.hot, sameDay, day, ringOnly(it))
              stats.incT = (stats.incT or 0) + (clock() - ti)
              stats.inc = (stats.inc or 0) + 1
              if inc ~= full then stats.mismatch = (stats.mismatch or 0) + 1 end
            end
            it.hot = full
            stats.upd = stats.upd + 1
            stats.updT = stats.updT + (clock() - t0)
          end
        end
      end
    end
    for i = 1, SAMPLE do items[i].listedToday = nil end
    -- the ring expires by time even for items not listed again: re-encode lazily in production; here only for the size reading
    local age = day - DAY0 + 1
    if age == 1 or age == 2 or age == 7 or age == 14 or age == 30 or age == 60 or age == 120 then
      local tot, worst = 0, 0
      for i = 1, SAMPLE do
        local it = items[i]
        if cfg.ring then
          local nowEnd = (day - DAY0) * 1440 + MIN0 + 23 * 60
          while #it.ring > 0 and it.ring[1].m1 < nowEnd - RING_MIN do table.remove(it.ring, 1) end
          if it.hot then it.hot = encodeHot(it, day) end
        end
        local b = (it.hot and #it.hot or 0) + #it.cold
        tot, worst = tot + b, max(worst, b)
      end
      out[#out + 1] = { age = age, avg = tot / SAMPLE, worst = worst }
    end
  end
  return out, stats, items
end

-- query cost: decode one item's strings and build chart points (the History() shape) for the largest item
local function queryCost(items)
  local big
  for _, it in ipairs(items) do if it.hot and (not big or #it.hot + #it.cold > #big.hot + #big.cold) then big = it end end
  local reps = 2000
  local t0 = clock()
  for _ = 1, reps do
    local pts = {}
    local ring, daily = big.hot:match("^([^|]*)|(.*)$")
    for e in daily:gmatch("[^;]+") do
      local f = {}
      for v in e:gmatch("%d+") do f[#f + 1] = tonumber(v) end
      pts[#pts + 1] = { kind = "day", v = f[2], r = f[2] + f[3], t = f[4], l = f[5] }
    end
    for e in big.cold:gmatch("[^;]+") do
      local f = {}
      for v in e:gmatch("%d+") do f[#f + 1] = tonumber(v) end
      pts[#pts + 1] = { kind = f[2] == 7 and "week" or "fortnight", n = f[3], lo = f[4], v = f[5], hi = f[6] }
    end
    for e in ring:gmatch("[^;]+") do local f = {} for v in e:gmatch("%d+") do f[#f + 1] = tonumber(v) end pts[#pts + 1] = f end
  end
  return (clock() - t0) / reps * 1e6, #big.hot + #big.cold
end

-- saved-file load: write a SavedVariables-shaped file of `count` items (sample strings repeated with distinct keys) and dofile it
local function loadCost(items, count, path)
  local f = assert(io.open(path, "w"))
  f:write("TwichUIWorkshopDB = {\n[\"v\"] = 2,\n[\"markets\"] = {\n[\"Realm|Alliance\"] = {\n[\"h2\"] = {\n")
  local n = #items
  for i = 1, count do local it = items[(i - 1) % n + 1] if it.hot then f:write("[", 100000 + i, "] = \"", it.hot, ";", i, "\",\n") end end
  f:write("},\n[\"c2\"] = {\n")
  for i = 1, count do local it = items[(i - 1) % n + 1] if it.cold ~= "" then f:write("[", 100000 + i, "] = \"", it.cold, ";", i, "\",\n") end end
  f:write("},\n},\n},\n}\n")
  f:close()
  local size = io.open(path):seek("end")
  collectgarbage("collect")
  local m0 = collectgarbage("count")
  local t0 = clock()
  dofile(path)                       -- what the client's saved-variables loader does with the file (a different loader in the game)
  local t = clock() - t0
  collectgarbage("collect")
  local mem = collectgarbage("count") - m0
  TwichUIWorkshopDB = nil
  os.remove(path)
  return size, t, mem
end

local which, schedName, SAMPLE = arg[1] or "all", arg[2] or "active", tonumber(arg[3]) or 2000
local sched = assert(SCHED[schedName], "schedule")
local order = { "d14", "d30", "adapt", "hybrid", "d14ring", "d30ring", "hybridring", "hybridring8", "d30ring8" }
print(("schedule %s, sample %d items (scaled linearly to 40,000), mixed listing frequency"):format(schedName, SAMPLE))
for _, name in ipairs(order) do
  if which == "all" or which == name then
    local out, st, items = sim(DESIGNS[name], sched, SAMPLE)
    local line = {}
    for _, o in ipairs(out) do line[#line + 1] = ("d%d %.0f/%d"):format(o.age, o.avg, o.worst) end
    local last = out[#out]
    local qus, qbytes = queryCost(items)
    local size, lt, mem = loadCost(items, 40000, os.tmpname())
    print(("%-12s B/item avg/worst: %s"):format(name, table.concat(line, "  ")))
    print(("%-12s 10k %.1f MB, 20k %.1f MB, 40k %.1f MB text; update %.1f us/item (=> %.1f ms per 120 items); folds %.0f%% of updates; query %.0f us (%d B item)"):format(
      "", last.avg * 10000 / 1048576, last.avg * 20000 / 1048576, last.avg * 40000 / 1048576, st.updT / st.upd * 1e6, st.updT / st.upd * 120 * 1000,
      100 * st.folds / st.upd, qus, qbytes))
    if st.inc then print(("%-12s incremental update (no full decode): %.1f us/item (=> %.2f ms per 120 items), %d of %d updates, mismatches vs full encode: %d"):format(
      "", st.incT / st.inc * 1e6, st.incT / st.inc * 120 * 1000, st.inc, st.upd, st.mismatch or 0)) end
    print(("%-12s saved file 40k items: %.1f MB, dofile %.2f s offline, resident after load %.1f MB"):format("", size / 1048576, lt, mem / 1024))
  end
end
