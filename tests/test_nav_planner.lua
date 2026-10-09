dofile(TESTS .. "harness.lua")
-- Navigation's route choice (nav/Planner.lua): walking in a straight line as a minimum, one flight between
-- known flight points when it is quicker (with the boarding allowance), never two flights in a row, and
-- nothing planned from numbers that aren't usable. No game calls are involved.
local c = MakeClient("Rich", {"!!!TwichUI"})
local chunk = assert(loadfile(ROOT .. "nav/Planner.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
local NP = c.TwichUI.NavPlanner
local B = NP.BOARDING

local function Near(a, b, msg) assert(math.abs(a - b) < 1e-6, ("%s: expected %s, got %s"):format(msg, tostring(b), tostring(a))) end

-- costs[a][b] = seconds of flying, or nil for no flight
local function Query(from, to, nodes, costs, extra)
  local calls = 0
  local q = {
    fromX = from[1], fromY = from[2], toX = to[1], toY = to[2], runSpeed = 7, nodes = nodes,
    flightCost = function(a, b) calls = calls + 1; return costs[a] and costs[a][b] end,
    flightDetail = function(a, b)
      local s = costs[a] and costs[a][b]
      if not s then return nil end
      return { seconds = s, confirmed = false, learned = false, points = { 0, 0, 1, 1 } }
    end,
  }
  for k, v in pairs(extra or {}) do q[k] = v end
  return q, function() return calls end
end

-- 1) Nothing to fly between: one straight walk, a minimum.
do
  local plan = NP.Plan(Query({ 0, 0 }, { 700, 0 }, {}, {}))
  assert(plan and #plan.legs == 1 and plan.legs[1].mode == "walk" and plan.legs[1].minimum and plan.minimum, "walk only")
  Near(plan.seconds, 100, "700 yards at 7 a second")
  assert(plan.legs[1].toNode == nil, "the walk leads to the goal")
end

-- 2) A long way with flight points at both ends: walk, fly, walk.
local A, Bn, C = { id = 1, x = 50, y = 0, name = "A" }, { id = 2, x = 9950, y = 0, name = "B" }, { id = 3, x = 5000, y = 0, name = "C" }
do
  local plan = NP.Plan(Query({ 0, 0 }, { 10000, 0 }, { A, Bn }, { [1] = { [2] = 300 } }))
  assert(plan and #plan.legs == 3, "three steps")
  local w1, f, w2 = plan.legs[1], plan.legs[2], plan.legs[3]
  assert(w1.mode == "walk" and w1.toNode == A and f.mode == "flight" and f.fromNode == A and f.toNode == Bn and w2.mode == "walk" and w2.toNode == nil, "walk to A, fly to B, walk on")
  Near(f.seconds, 300 + B, "a flight includes the boarding allowance")
  Near(plan.seconds, 50 / 7 + 300 + B + 50 / 7, "total")
  assert(plan.minimum, "still a minimum: it has walking in it")
  assert(f.points and #f.points == 4, "the flight's stops come from the detail")
end

-- 3) Close by: walking beats any flight once boarding is counted.
do
  -- walking: 200 / 7 = 28.6 s; flying: 50 / 7 + 15 + B + 10 / 7 = 33.6 s
  local plan = NP.Plan(Query({ 0, 0 }, { 200, 0 }, { A, { id = 2, x = 190, y = 0 } }, { [1] = { [2] = 15 } }))
  assert(#plan.legs == 1 and plan.legs[1].mode == "walk", "a short way is walked")
end

-- 4) No flight between the points: walk.
do
  local plan = NP.Plan(Query({ 0, 0 }, { 10000, 0 }, { A, Bn }, {}))
  assert(#plan.legs == 1 and plan.legs[1].mode == "walk", "no flight, no flying")
end

-- 5) The quicker of two flights.
do
  local D = { id = 4, x = 9900, y = 0 }
  local plan = NP.Plan(Query({ 0, 0 }, { 10000, 0 }, { A, Bn, D }, { [1] = { [2] = 400, [4] = 250 } }))
  assert(plan.legs[2].toNode == D, "the faster flight wins, even with a little more walking")
end

-- 6) Never two flights in a row: A -> C -> B would be quicker on paper, but only one flight is taken.
do
  local plan = NP.Plan(Query({ 0, 0 }, { 10000, 0 }, { A, C, Bn }, { [1] = { [3] = 10 }, [3] = { [2] = 10 } }))
  local flights = 0
  for i, leg in ipairs(plan.legs) do
    if leg.mode == "flight" then
      flights = flights + 1
      assert(not (plan.legs[i + 1] and plan.legs[i + 1].mode == "flight"), "no flight straight after another")
    end
  end
  assert(flights == 1, "one flight: " .. flights)
  assert(plan.legs[2].toNode == C and plan.legs[3].mode == "walk", "flies to C and walks the rest")
end

-- 7) Flight costs are asked for only from flight points the search reaches, each pair at most once.
do
  local nodes = {}
  for i = 1, 30 do nodes[i] = { id = i, x = i * 300, y = 0 } end
  local q, calls = Query({ 0, 0 }, { 9000, 0 }, nodes, {})
  NP.Plan(q)
  assert(calls() <= 30 * 29, "bounded: " .. calls())
end

-- 8) Numbers that can't be used plan nothing.
for _, bad in ipairs({ { runSpeed = 0 }, { runSpeed = -1 }, { fromX = 0 / 0 }, { toY = 1 / 0 }, { fromY = "x" } }) do
  local q = Query({ 0, 0 }, { 700, 0 }, {}, {}, bad)
  assert(NP.Plan(q) == nil, "unusable input plans nothing")
end
assert(NP.Plan(nil) == nil and NP.Plan("x") == nil)

-- 9) A flight whose detail can't be read after it was chosen: no half route.
do
  local q = Query({ 0, 0 }, { 10000, 0 }, { A, Bn }, { [1] = { [2] = 300 } })
  q.flightDetail = function() return nil end
  assert(NP.Plan(q) == nil, "nothing rather than a broken route")
end

-- 10) Standing at the goal: one walk of no time.
do
  local plan = NP.Plan(Query({ 5, 5 }, { 5, 5 }, { A }, {}))
  assert(plan and #plan.legs == 1 and plan.seconds == 0)
end

print("NAV PLANNER TESTS PASSED")
