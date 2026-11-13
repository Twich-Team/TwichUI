-- A1: the three candidate representative-price rules on hand-made listing sets (copper). Throwaway.
local floor = math.floor
local function prep(L)
  table.sort(L, function(a, b) return a[1] < b[1] end)
  local T = 0 for _, l in ipairs(L) do T = T + l[2] end
  return L, T
end
local function WP(L, T, a)  -- smallest price whose cumulative quantity reaches a*T
  local cum = 0
  for _, l in ipairs(L) do cum = cum + l[2] if cum > a * T then return l[1] end end
end
local function A(L, T) return WP(L, T, 0.25) end
local function B(L, T)      -- cluster mode: clusters of prices within 5% of the cluster's first price
  local cl, cum = {}, 0
  for _, l in ipairs(L) do
    local c = cl[#cl]
    if not c or l[1] > c.first * 1.05 then c = { first = l[1], q = 0, s = 0, before = cum } cl[#cl + 1] = c end
    c.q, c.s = c.q + l[2], c.s + l[1] * l[2]
    cum = cum + l[2]
  end
  local best
  for _, c in ipairs(cl) do if c.before < 0.5 * T and (not best or c.q > best.q) then best = c end end
  return floor(best.s / best.q + 0.5)
end
local function C(L, T)      -- band mean: anchor = WP25; ignore prices below anchor/2; mean of the cheapest 30% of the rest
  local anchor = WP(L, T, 0.25)
  local Te = 0
  for _, l in ipairs(L) do if l[1] * 2 >= anchor then Te = Te + l[2] end end
  local want, got, sum = Te * 0.3, 0, 0
  for _, l in ipairs(L) do
    if l[1] * 2 >= anchor and got < want then
      local take = math.min(l[2], want - got)
      got, sum = got + take, sum + take * l[1]
    end
  end
  return floor(sum / got + 0.5), anchor
end
local S = {
  { "1 healthy spread", { { 9500, 5 }, { 9800, 5 }, { 10000, 10 }, { 10200, 10 }, { 10500, 10 }, { 11000, 5 } } },
  { "2 one 1c listing in a deep market", { { 1, 1 }, { 5000, 40 }, { 5200, 10 } } },
  { "3 thin market, one cheap unit", { { 1000, 1 }, { 5000, 3 } } },
  { "4 one absurd high listing", { { 5000, 10 }, { 9990000, 1 } } },
  { "5a big wall just below", { { 4900, 200 }, { 5200, 5 } } },
  { "5b big wall above a few cheap", { { 4500, 5 }, { 6000, 200 } } },
  { "6 two clusters 10g / 20g", { { 100000, 10 }, { 200000, 90 } } },
  { "7 one listing", { { 300000, 1 } } },
  { "8 100 x 1c steps", (function() local t = {} for i = 0, 99 do t[#t + 1] = { 5000 + i, 1 } end return t end)() },
  { "9 one 200-stack vs singles", { { 4000, 200 }, { 6000, 5 } } },
  { "10 rare, 3 far-apart listings", { { 800000, 1 }, { 1500000, 1 }, { 4000000, 1 } } },
  { "11 bait volume 8@20s vs 20@50s", { { 2000, 8 }, { 5000, 20 } } },
  { "12 bait volume 5@20s vs 20@50s", { { 2000, 5 }, { 5000, 20 } } },
  -- adversarial cases (A1 revision)
  { "13 thin, two far apart", { { 10000, 1 }, { 40000, 1 } } },
  { "14 thin, 1c among three", { { 1, 1 }, { 9000, 1 }, { 9500, 1 } } },
  { "15 separated clusters 1g/100g", { { 10000, 50 }, { 1000000, 50 } } },
  { "16 cheap wall 1000@40s, 20@50s", { { 4000, 1000 }, { 5000, 20 } } },
  { "17 expensive wall 20@50s, 1000@90s", { { 5000, 20 }, { 9000, 1000 } } },
  { "18 manipulator 24% just over half", { { 2510, 12 }, { 5000, 38 } } },
  { "19 manipulator 26% just over half", { { 2510, 13 }, { 5000, 37 } } },
  { "20 manipulator 24% just under half", { { 2490, 12 }, { 5000, 38 } } },
  { "21 one 1000-stack cheap, singles", { { 3000, 1000 }, { 5000, 1 }, { 5100, 1 } } },
  { "22 one huge stack dear, singles", { { 5000, 3 }, { 9000, 1000 } } },
}
print(("%-36s %8s %8s %8s %8s %8s"):format("case", "min", "A:P25", "B:mode", "C:band", "anchor"))
for _, sc in ipairs(S) do
  local L, T = prep(sc[2])
  local c, anchor = C(L, T)
  print(("%-36s %8d %8d %8d %8d %8d   T=%d"):format(sc[1], L[1][1], A(L, T), B(L, T), c, anchor, T))
end
