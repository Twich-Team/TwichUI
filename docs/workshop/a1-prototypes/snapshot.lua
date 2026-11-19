-- A1 prototype (throwaway, not production): synthetic market -> v3 snapshot entries + hybrid history; measures size and time.
-- Usage: lua5.1 snapshot.lua [items] [records]
local floor, max, min = math.floor, math.max, math.min
local clock = os.clock
local NI = tonumber(arg[1]) or 30000
local NR = tonumber(arg[2]) or 250000

-- deterministic PRNG (LCG)
local s = 12345
local function rnd() s = (s * 16807) % 2147483647 return s / 2147483647 end
local function rint(a, b) return a + floor(rnd() * (b - a + 1)) end

-- items: Zipf-like popularity, base price log-uniform 1c..5000g, per-item dispersion
local base, sig = {}, {}
for i = 1, NI do base[i] = floor(10 ^ (1 + rnd() * 6.7)) sig[i] = 0.02 + rnd() * 0.25 end
local STACK = { 1, 1, 1, 1, 1, 5, 10, 20, 20, 200 }
local function pick() return 1 + floor(NI * rnd() ^ 1.6) end

-- Batch v3: per item a map unit -> {qty, listings} (distinct whole-copper unit prices)
collectgarbage("collect")
local m0 = collectgarbage("count")
local t0 = clock()
local acc = {}
for _ = 1, NR do
  local i = pick()
  local c = STACK[rint(1, #STACK)]
  local f = 1 + sig[i] * (rnd() * 2 - 1) * 2
  if rnd() < 0.01 then f = f * (rnd() < 0.5 and 0.1 or 8) end -- outliers
  local u = max(1, floor(base[i] * f))
  local buyout = u * c
  local unit = math.ceil(buyout / c)
  local a = acc[i]
  if not a then a = { n = 0 } acc[i] = a end
  local tq = a[unit]
  if tq then tq[1], tq[2] = tq[1] + c, tq[2] + 1 else a[unit] = { c, 1 } a.n = a.n + 1 end
end
local tAdd = clock() - t0
collectgarbage("collect")
local mAcc = collectgarbage("count") - m0
local nItems, nTiers = 0, 0
for _, a in pairs(acc) do nItems = nItems + 1 nTiers = nTiers + a.n end

-- Recent Price v1 ("lower-quarter band mean" with half-anchor gap rule), integer-weighted in tenths of a unit
local function Recent(ps, qs, T)
  -- anchor: weighted quantile at 25%
  local need, cum, anchor = T * 0.25, 0, ps[#ps]
  for k = 1, #ps do cum = cum + qs[k] if cum >= need then anchor = ps[k] break end end
  local lo = anchor / 2
  local Te = 0
  for k = 1, #ps do if ps[k] >= lo then Te = Te + qs[k] end end
  local want, got, sum = Te * 0.30, 0, 0
  for k = 1, #ps do
    if ps[k] >= lo then
      local take = min(qs[k], want - got)
      if take <= 0 then break end
      got, sum = got + take, sum + take * ps[k]
    end
  end
  return floor(sum / got + 0.5), anchor
end
local function Quant(ps, qs, T, a)
  local need, cum = T * a, 0
  for k = 1, #ps do cum = cum + qs[k] if cum >= need then return ps[k] end end
  return ps[#ps]
end

local N = function(v) return ("%.0f"):format(v) end
local TIERS = 8
local t1 = clock()
local items, dist = {}, {}
local worstStep, stepT, inStep = 0, clock(), 0
local bytesV1, bytesDist, nDist = 0, 0, 0
for id, a in pairs(acc) do
  local ps = {}
  for u, v in pairs(a) do if u ~= "n" then ps[#ps + 1] = u end end
  table.sort(ps)
  local qs, ls, T, L = {}, {}, 0, 0
  for k = 1, #ps do local v = a[ps[k]] qs[k], ls[k] = v[1], v[2] T, L = T + v[1], L + v[2] end
  local x = ps[2] or 0
  items[id] = N(ps[1]) .. "," .. N(qs[1]) .. "," .. N(L) .. "," .. N(T) .. "," .. N(x)
  bytesV1 = bytesV1 + #items[id]
  if #ps > 1 then
    local r = Recent(ps, qs, T)
    local q25, q50, q75 = Quant(ps, qs, T, .25), Quant(ps, qs, T, .5), Quant(ps, qs, T, .75)
    local near = 0
    for k = 1, #ps do if ps[k] <= r * 1.1 then near = near + qs[k] end end
    local parts = { "1", N(r), N(q25), N(q50), N(q75), N(ps[#ps]), N(near) }
    local tiers = {}
    for k = 1, min(TIERS, #ps) do tiers[#tiers + 1] = N(ps[k]) .. ":" .. N(qs[k]) .. ":" .. N(ls[k]) end
    local tailQ, tailL = 0, 0
    for k = TIERS + 1, #ps do tailQ, tailL = tailQ + qs[k], tailL + ls[k] end
    local e = table.concat(parts, ",") .. "|" .. table.concat(tiers, ";") .. (tailQ > 0 and ("|" .. N(tailQ) .. ":" .. N(tailL)) or "")
    dist[id] = e
    bytesDist, nDist = bytesDist + #e, nDist + 1
  end
  inStep = inStep + 1
  if inStep == 400 then local d = clock() - stepT if d > worstStep then worstStep = d end stepT, inStep = clock(), 0 end
end
local tFin = clock() - t1
acc = nil
collectgarbage("collect")
local mSnap = collectgarbage("count") - m0

print(("SNAPSHOT items=%d records=%d distinct-tiers=%d (%.1f per item)"):format(nItems, NR, nTiers, nTiers / nItems))
print(("  add %.2fs  transient acc %.1f MB  finalize %.2fs  worst 400-item step %.1f ms"):format(tAdd, mAcc / 1024, tFin, worstStep * 1000))
print(("  v1 entries %.2f MB text (%.1f B/item); dist entries %d items (%.0f%%) %.2f MB text (%.1f B each); resident items+dist %.1f MB"):format(
  bytesV1 / 1048576, bytesV1 / nItems, nDist, 100 * nDist / nItems, bytesDist / 1048576, bytesDist / max(1, nDist), mSnap / 1024))

-------------------------------------------------------------------------------
-- History: hybrid (daily 30 days + weekly buckets to 120 days); simulate a sample and scale
-------------------------------------------------------------------------------
local SAMPLE = 3000
local presence = {}
for i = 1, SAMPLE do local r = rnd() presence[i] = r < 0.3 and 0.9 or (r < 0.7 and 0.35 or 0.06) end
local DAILY, WEEK, RETAIN = 30, 7, 120
local function EncodeH(daily, weeks)
  local d, w, last = {}, {}, nil
  for k = 1, #daily do local p = daily[k]
    d[#d + 1] = N(last and (p[1] - last) or p[1]) .. "," .. N(p[2]) .. "," .. N(p[3]) .. "," .. N(p[4]) .. "," .. N(p[5]) .. "," .. N(p[6])
    last = p[1] end
  for k = 1, #weeks do local b = weeks[k]
    w[#w + 1] = N(b[1]) .. "," .. N(b[2]) .. "," .. N(b[3]) .. "," .. N(b[4]) .. "," .. N(b[5]) .. "," .. N(b[6]) .. "," .. N(b[7]) .. "," .. N(b[8]) end
  return table.concat(d, ";"), table.concat(w, ";")
end
local state = {}
for i = 1, SAMPLE do state[i] = { daily = {}, weeks = {} } end
local DAY0 = 20000
local report = { [7] = true, [30] = true, [60] = true, [120] = true, [150] = true }
local hotT, coldT = {}, {}
local worstCommit = 0
for day = DAY0, DAY0 + 149 do
  local cs = clock()
  for i = 1, SAMPLE do
    local st = state[i]
    if hotT[i] then for a,b,c,d,e,f in hotT[i]:gmatch('(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)') do end end
    if rnd() < presence[i] then
      local p = base[i]
      local r = floor(p * (1 + sig[i] * 0.5))
      st.daily[#st.daily + 1] = { day, p, r, floor(r * 1.08), rint(1, 400), rint(1, 30) }
    end
    -- fold whole weeks once the daily tier spans more than DAILY + WEEK days
    while #st.daily > 0 and st.daily[1][1] < day - DAILY - WEEK + 1 do
      local wk = floor(st.daily[1][1] / WEEK)
      local n, plo, psum, rsum, rlo, rhi, tsum = 0, nil, 0, 0, nil, nil, 0
      while #st.daily > 0 and floor(st.daily[1][1] / WEEK) == wk and st.daily[1][1] < day - DAILY + 1 do
        local q = table.remove(st.daily, 1)
        n = n + 1 psum = psum + q[2] rsum = rsum + q[3] tsum = tsum + q[5]
        plo = plo and min(plo, q[2]) or q[2] rlo = rlo and min(rlo, q[3]) or q[3] rhi = rhi and max(rhi, q[3]) or q[3]
      end
      if n == 0 then break end
      st.weeks[#st.weeks + 1] = { wk, n, plo, floor(psum / n), floor(rsum / n), rlo, rhi, floor(tsum / n) }
    end
    while #st.weeks > 0 and (st.weeks[1][1] + 1) * WEEK - 1 < day - RETAIN do table.remove(st.weeks, 1) end
    hotT[i], coldT[i] = EncodeH(st.daily, st.weeks)
  end
  local d = clock() - cs
  if d > worstCommit then worstCommit = d end
  local age = day - DAY0 + 1
  if report[age] then
    local hb, cb, worst = 0, 0, 0
    for i = 1, SAMPLE do local b = #hotT[i] + #coldT[i] hb, cb = hb + #hotT[i], cb + #coldT[i] if b > worst then worst = b end end
    print(("HISTORY day %3d: hot %.0f B/item, cold %.0f B/item, total %.0f B/item, worst %d B; x40,000 items = %.1f MB text"):format(
      age, hb / SAMPLE, cb / SAMPLE, (hb + cb) / SAMPLE, worst, (hb + cb) / SAMPLE * 40000 / 1048576))
  end
end
-- per-item commit cost estimate (decode is not modelled; encode of all sample items)
print(("  encode of %d items per scan: worst %.1f ms -> per 120-item step about %.2f ms (encode only)"):format(SAMPLE, worstCommit * 1000, worstCommit * 1000 * 120 / SAMPLE))
-- memory of the history strings, as a saved-variables load would make them (fresh string objects)
local blob = {}
for i = 1, SAMPLE do blob[#blob+1] = hotT[i] .. "#" blob[#blob+1] = coldT[i] .. "#" end
blob = table.concat(blob)
hotT, coldT, state = nil, nil, nil
collectgarbage("collect")
local mh0 = collectgarbage("count")
local H, C, pos = {}, {}, 1
for i = 1, SAMPLE do
  local e = blob:find("#", pos, true) H[1000000 + i * 7] = blob:sub(pos, e - 1) .. "" pos = e + 1
  e = blob:find("#", pos, true) local c = blob:sub(pos, e - 1) if c ~= "" then C[1000000 + i * 7] = c end pos = e + 1
end
collectgarbage("collect")
print(("  resident Lua memory of hot+cold strings in two id-keyed tables: %.0f B/item (text was %.0f B/item)"):format((collectgarbage("count") - mh0) * 1024 / SAMPLE, (#blob - 2 * SAMPLE) / SAMPLE))
