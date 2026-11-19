-- A1 prototype 2 (throwaway): packed accumulator memory, and history variants by size/cost. Lua 5.1.
local floor, max, min = math.floor, math.max, math.min
local clock = os.clock
local s = 12345
local function rnd() s = (s * 16807) % 2147483647 return s / 2147483647 end
local function rint(a, b) return a + floor(rnd() * (b - a + 1)) end
local N = function(v) return ("%.0f"):format(v) end

local mode = arg[1] or "acc"
if mode == "acc" then
  local NI, NR, WIDE = tonumber(arg[2]) or 30000, tonumber(arg[3]) or 250000, arg[4] ~= "narrow"
  local base, sig = {}, {}
  for i = 1, NI do base[i] = floor(10 ^ (1 + rnd() * 6.7)) sig[i] = 0.02 + rnd() * 0.25 end
  local STACK = { 1, 1, 1, 1, 1, 5, 10, 20, 20, 200 }
  collectgarbage("collect")
  local m0 = collectgarbage("count")
  local t0 = clock()
  local acc = {}
  -- packed: acc[item][unit] = qty * 65536 + listings ; acc[item].n distinct
  for _ = 1, NR do
    local i = 1 + floor(NI * rnd() ^ 1.6)
    local c = STACK[rint(1, #STACK)]
    local u
    if WIDE then u = max(1, floor(base[i] * (1 + sig[i] * (rnd() * 2 - 1) * 2)))
    else u = base[i] + rint(0, 40) end   -- FX.Bulk-like narrow spread
    local a = acc[i]
    if not a then a = {} acc[i] = a end
    a[u] = (a[u] or 0) + c * 65536 + 1
  end
  local t = clock() - t0
  collectgarbage("collect")
  local n, tiers = 0, 0
  for _, a in pairs(acc) do n = n + 1 for _ in pairs(a) do tiers = tiers + 1 end end
  print(("ACC packed %s: items %d, tiers %d (%.1f/item), add %.2fs, transient %.1f MB"):format(WIDE and "wide" or "narrow", n, tiers, tiers / n, t, (collectgarbage("count") - m0) / 1024))
  return
end

-- history variants
local SAMPLE, DAY0 = 3000, 20000
local function sim(cfg)
  s = 777
  local base, sig, pres = {}, {}, {}
  for i = 1, SAMPLE do
    base[i] = floor(10 ^ (1 + rnd() * 6.7)) sig[i] = 0.02 + rnd() * 0.25
    local r = rnd() pres[i] = r < cfg.pDaily[1] and 0.9 or (r < cfg.pDaily[2] and 0.35 or 0.06)
  end
  local st, hot, cold = {}, {}, {}
  for i = 1, SAMPLE do st[i] = { d = {}, w = {} } end
  local out, worstStep = {}, 0
  for day = DAY0, DAY0 + 119 do
    local cs = clock()
    for i = 1, SAMPLE do
      local S = st[i]
      if hot[i] then for _ in hot[i]:gmatch("[^;]+") do end end   -- decode stand-in
      if rnd() < pres[i] then
        local p = floor(base[i] * (1 + sig[i] * (rnd() - 0.5) * 0.4))
        local r = floor(p * (1 + sig[i] * 0.6))
        S.d[#S.d + 1] = { day, p, r, floor(r * 1.1), rint(1, 400), rint(1, 30) }
      end
      while #S.d > 0 and S.d[1][1] < day - cfg.daily - 6 do
        local wk = floor(S.d[1][1] / 7)
        local b = { wk, 0, nil, 0, 0, nil, nil, 0 }
        while #S.d > 0 and floor(S.d[1][1] / 7) == wk and S.d[1][1] <= day - cfg.daily do
          local q = table.remove(S.d, 1)
          b[2] = b[2] + 1 b[3] = b[3] and min(b[3], q[2]) or q[2] b[4] = b[4] + q[2] b[5] = b[5] + q[3]
          b[6] = b[6] and min(b[6], q[3]) or q[3] b[7] = b[7] and max(b[7], q[3]) or q[3] b[8] = b[8] + q[5]
        end
        if b[2] == 0 then break end
        S.w[#S.w + 1] = b
      end
      if cfg.fort then
        -- merge weekly buckets older than 60 days into two-week buckets (key wk//2, flagged by size 14)
        local k = 1
        while k <= #S.w do
          local b = S.w[k]
          if not b.f and (b[1] + 1) * 7 - 1 < day - 60 then
            local fk = floor(b[1] / 2)
            local prev = S.w[k - 1]
            if prev and prev.f and prev[1] == fk then
              local n = prev[2] + b[2]
              prev[3] = min(prev[3], b[3]) prev[6] = min(prev[6], b[6]) prev[7] = max(prev[7], b[7])
              prev[4] = prev[4] + b[4] prev[5] = prev[5] + b[5] prev[8] = prev[8] + b[8] prev[2] = n
              table.remove(S.w, k)
            else b.f = true b[1] = fk k = k + 1 end
          else k = k + 1 end
        end
      end
      while #S.w > 0 and (S.w[1][1] + 1) * (S.w[1].f and 14 or 7) - 1 < day - 120 do table.remove(S.w, 1) end
      local parts, last = {}, nil
      for k = 1, #S.d do
        local q = S.d[k]
        local f = { N(last and q[1] - last or q[1]), N(q[2]) }
        if cfg.rep then f[#f + 1] = cfg.relr and N(q[3] - q[2]) or N(q[3]) end
        if cfg.spread then f[#f + 1] = N(q[4] - q[3]) end
        f[#f + 1] = N(q[5])
        if cfg.listings then f[#f + 1] = N(q[6]) end
        parts[k] = table.concat(f, ",") last = q[1]
      end
      hot[i] = table.concat(parts, ";")
      local wp = {}
      for k = 1, #S.w do
        local b = S.w[k]
        local n = b[2]
        local f = { N(b[1]), N(n), N(b[3]), N(floor(b[4] / n)) }
        if cfg.rep then f[#f + 1] = N(floor(b[5] / n)) f[#f + 1] = N(b[6]) f[#f + 1] = N(b[7]) end
        f[#f + 1] = N(floor(b[8] / n))
        wp[k] = table.concat(f, ",")
      end
      cold[i] = table.concat(wp, ";")
    end
    local d = clock() - cs
    if d > worstStep then worstStep = d end
    local age = day - DAY0 + 1
    if age == 7 or age == 30 or age == 60 or age == 120 then
      local tot, worst = 0, 0
      for i = 1, SAMPLE do local b = #hot[i] + #cold[i] + (cold[i] ~= "" and 1 or 0) tot = tot + b worst = max(worst, b) end
      out[#out + 1] = ("d%d %.0fB (max %d)"):format(age, tot / SAMPLE, worst)
      if age == 120 then out[#out + 1] = ("=> 40k items %.1f MB; step(120 items) ~%.1f ms"):format(tot / SAMPLE * 40000 / 1048576, worstStep * 1000 * 120 / SAMPLE) end
    end
  end
  return table.concat(out, "  ")
end
local mix = { 0.3, 0.7 }
local sparse = { 0.1, 0.4 }
local V = {
  { "current v1 (min only, 7 exact + 3x28d)  [analytic: measured 72 B avg, 175 max]", nil },
  { "RICH  daily30 d,p,r,h,t,l + weekly", { daily = 30, rep = true, spread = true, listings = true, pDaily = mix } },
  { "MID   daily30 d,p,r,t + weekly", { daily = 30, rep = true, pDaily = mix } },
  { "LEAN  daily14 d,p,r,t + weekly", { daily = 14, rep = true, pDaily = mix } },
  { "LEAN-rel daily14 d,p,(r-p),t + weekly", { daily = 14, rep = true, relr = true, pDaily = mix } },
  { "LEAN-rel, sparse market (10% daily, 30% often)", { daily = 14, rep = true, relr = true, pDaily = sparse } },
  { "LEAN-rel-fort daily14 + weekly to 60 + 2-week to 120", { daily = 14, rep = true, relr = true, fort = true, pDaily = mix } },
  { "LEAN-rel-fort, sparse market", { daily = 14, rep = true, relr = true, fort = true, pDaily = sparse } },
  { "MID-rel daily30 d,p,(r-p),t + weekly", { daily = 30, rep = true, relr = true, pDaily = mix } },
}
for _, v in ipairs(V) do
  if v[2] then print(("%-48s %s"):format(v[1], sim(v[2]))) else print(v[1]) end
end
