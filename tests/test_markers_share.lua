dofile(TESTS .. "harness.lua")
-- Configuration sharing (markers/Markers.lua): the two orders as data, checked and applied the same way.
-- Covers M.Clean (an imported entry, checked), M.Export (the orders in use), M.ApplyClean (writes the kinds
-- in place, returns undo records) and M.RestoreRecords (puts back what ApplyClean replaced).
-- The contract: Clean returns a clean copy (off sorted, inputs not mutated) or nil plus why ("shape", "invalid",
-- "empty"); Export shares a missing or damaged order as the default it is used as; ApplyClean writes only the
-- kinds present and records each kind's previous entry (had=false when absent); RestoreRecords restores in
-- reverse and returns how many kinds were put back.

local c = MakeClient("Rich", { "!!!TwichUI" })
local chunk = assert(loadfile(ROOT .. "markers/Markers.lua"))
setfenv(chunk, c)
chunk("!!!TwichUI", {})

local R = c.TwichUI
local M = R.Markers

-- Saved values (the profile's): the orders live in TwichUIDB.ui.markerOrder[kind].
c.TwichUIDB = c.TwichUIDB or {}
c.TwichUIDB.ui = c.TwichUIDB.ui or {}

local checks = 0
local function Check(cond, msg)
  checks = checks + 1
  if not cond then error("FAILED: " .. msg, 2) end
end

local function SameList(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

local function ResetSaved()
  c.TwichUIDB.ui.markerOrder = nil
end

---------------------------------------------------------------------------
-- 1. Clean: an imported entry, checked
---------------------------------------------------------------------------
-- non-table raw -> nil, "shape"
do
  local clean, why = M.Clean("nope")
  Check(clean == nil and why == "shape", "Clean: a non-table raw is 'shape'")
  clean, why = M.Clean(nil)
  Check(clean == nil and why == "shape", "Clean: a nil raw is 'shape'")
  clean, why = M.Clean(3)
  Check(clean == nil and why == "shape", "Clean: a number raw is 'shape'")
end

-- unknown kind key -> nil, "invalid"
do
  local clean, why = M.Clean({ target = { order = { 1, 2, 3, 4, 5, 6, 7, 8 }, off = {} }, bogus = { order = { 1, 2, 3, 4, 5, 6, 7, 8 }, off = {} } })
  Check(clean == nil and why == "invalid", "Clean: an unknown kind key is 'invalid'")
end

-- a kind entry that is not a table -> nil, "shape"
do
  local clean, why = M.Clean({ target = "nope" })
  Check(clean == nil and why == "shape", "Clean: a kind entry that is not a table is 'shape'")
end

-- extra field in an entry -> nil, "invalid"
do
  local clean, why = M.Clean({ target = { order = { 1, 2, 3, 4, 5, 6, 7, 8 }, off = {}, extra = 1 } })
  Check(clean == nil and why == "invalid", "Clean: an extra field in an entry is 'invalid'")
end

-- damaged order (missing / duplicate / out-of-range id) -> nil, "invalid"
do
  local clean, why = M.Clean({ target = { order = { 1, 2, 3, 4, 5, 6, 7 }, off = {} } })
  Check(clean == nil and why == "invalid", "Clean: a short order is 'invalid'")
  clean, why = M.Clean({ target = { order = { 1, 1, 3, 4, 5, 6, 7, 8 }, off = {} } })
  Check(clean == nil and why == "invalid", "Clean: a duplicated id is 'invalid'")
  clean, why = M.Clean({ target = { order = { 1, 2, 3, 4, 5, 6, 7, 9 }, off = {} } })
  Check(clean == nil and why == "invalid", "Clean: an out-of-range id is 'invalid'")
end

-- damaged off list -> nil, "invalid"
do
  local clean, why = M.Clean({ target = { order = { 1, 2, 3, 4, 5, 6, 7, 8 }, off = { 3, 3 } } })
  Check(clean == nil and why == "invalid", "Clean: a duplicated off id is 'invalid'")
  clean, why = M.Clean({ target = { order = { 1, 2, 3, 4, 5, 6, 7, 8 }, off = { 9 } } })
  Check(clean == nil and why == "invalid", "Clean: an out-of-range off id is 'invalid'")
end

-- empty table -> nil, "empty"
do
  local clean, why = M.Clean({})
  Check(clean == nil and why == "empty", "Clean: an empty table is 'empty'")
end

-- a valid entry returns a deep copy with off sorted; inputs not mutated; absent kinds stay absent
do
  local raw = { target = { order = { 8, 7, 6, 5, 4, 3, 2, 1 }, off = { 7, 3 } } }
  local clean, why = M.Clean(raw)
  Check(clean ~= nil and why == nil, "Clean: a valid entry is accepted")
  Check(SameList(clean.target.order, { 8, 7, 6, 5, 4, 3, 2, 1 }), "Clean: the order is copied")
  Check(SameList(clean.target.off, { 3, 7 }), "Clean: the off list is sorted")
  Check(clean.world == nil, "Clean: a kind absent from raw is absent from the result")

  -- deep copy: mutating the result leaves the input untouched, and vice versa
  clean.target.order[1] = 99
  clean.target.off[1] = 99
  Check(raw.target.order[1] == 8 and raw.target.off[1] == 7, "Clean: mutating the result leaves the input untouched")
  raw.target.order[1] = 98
  raw.target.off[1] = 98
  Check(clean.target.order[1] == 99 and clean.target.off[1] == 99, "Clean: mutating the input leaves the result untouched")
end

---------------------------------------------------------------------------
-- 2. Export: the orders in use (a missing or damaged one shared as the default it is used as)
---------------------------------------------------------------------------
-- with no saved order it returns the DEFAULT_ORDER copies with empty off
do
  ResetSaved()
  local out = M.Export()
  Check(out ~= nil and type(out) == "table", "Export: returns a table")
  Check(SameList(out.target.order, M.DEFAULT_ORDER.target), "Export: no saved order -> the default target order")
  Check(SameList(out.world.order, M.DEFAULT_ORDER.world), "Export: no saved order -> the default world order")
  Check(SameList(out.target.off, {}) and SameList(out.world.off, {}), "Export: no saved order -> empty off")
end

-- with a damaged saved order it exports the default it is used as
do
  c.TwichUIDB.ui.markerOrder = { target = { order = { 8, 8 }, off = { 3 } } }
  local out = M.Export()
  Check(SameList(out.target.order, M.DEFAULT_ORDER.target), "Export: a damaged target order is shared as the default")
  Check(SameList(out.target.off, { 3 }), "Export: the still-valid off list is kept")
  Check(SameList(out.world.order, M.DEFAULT_ORDER.world), "Export: the other kind is the default too")
  ResetSaved()
end

---------------------------------------------------------------------------
-- 3. ApplyClean: writes only the kinds present; returns one undo record per kind
---------------------------------------------------------------------------
-- a kind that had no previous entry: had=false, entry=nil
do
  ResetSaved()
  local clean = { target = { order = { 1, 2, 3, 4, 5, 6, 7, 8 }, off = { 5 } } }
  local undo = M.ApplyClean(clean)
  Check(#undo == 1, "ApplyClean: one undo record per kind present")
  Check(undo[1].kind == "target" and undo[1].had == false and undo[1].entry == nil, "ApplyClean: a kind with no previous entry is had=false, entry=nil")
  local all = c.TwichUIDB.ui.markerOrder
  Check(all ~= nil and type(all) == "table", "ApplyClean: writes into TwichUIDB.ui.markerOrder")
  Check(SameList(all.target.order, { 1, 2, 3, 4, 5, 6, 7, 8 }) and SameList(all.target.off, { 5 }), "ApplyClean: the clean entry is written in place")
  Check(all.world == nil, "ApplyClean: a kind absent from the clean entry is not written")
  ResetSaved()
end

---------------------------------------------------------------------------
-- 4. ApplyClean + RestoreRecords round-trip
---------------------------------------------------------------------------
-- with pre-existing entries: undo records capture the old order/off copies (had=true); RestoreRecords restores
-- them exactly and returns the number of kinds restored; a kind that was absent is removed again on restore.
do
  local oldTarget = { order = { 8, 7, 6, 5, 4, 3, 2, 1 }, off = { 2 } }
  local oldWorld = { order = { 8, 4, 1, 7, 2, 3, 6, 5 }, off = {} }
  c.TwichUIDB.ui.markerOrder = { target = { order = { 8, 7, 6, 5, 4, 3, 2, 1 }, off = { 2 } },
    world = { order = { 8, 4, 1, 7, 2, 3, 6, 5 }, off = {} } }

  local clean = { target = { order = { 1, 2, 3, 4, 5, 6, 7, 8 }, off = { 5 } },
    world = { order = { 8, 7, 6, 5, 4, 3, 2, 1 }, off = { 8 } } }
  local undo = M.ApplyClean(clean)
  Check(#undo == 2, "round-trip: two undo records for the two kinds present")

  -- the undo records captured the old entries (had=true)
  local byKind = {}
  for _, u in ipairs(undo) do byKind[u.kind] = u end
  Check(byKind.target.had == true and byKind.world.had == true, "round-trip: pre-existing kinds are had=true")
  Check(SameList(byKind.target.entry.order, oldTarget.order) and SameList(byKind.target.entry.off, oldTarget.off), "round-trip: the old target entry is captured")
  Check(SameList(byKind.world.entry.order, oldWorld.order) and SameList(byKind.world.entry.off, oldWorld.off), "round-trip: the old world entry is captured")

  -- restore puts the old entries back, in reverse, and returns how many
  local n = M.RestoreRecords(undo)
  Check(n == 2, "round-trip: RestoreRecords returns how many kinds were put back")
  local all = c.TwichUIDB.ui.markerOrder
  Check(SameList(all.target.order, oldTarget.order) and SameList(all.target.off, oldTarget.off), "round-trip: the old target entry is restored exactly")
  Check(SameList(all.world.order, oldWorld.order) and SameList(all.world.off, oldWorld.off), "round-trip: the old world entry is restored exactly")
  ResetSaved()
end

-- a kind that was absent is removed again on restore
do
  ResetSaved()
  local clean = { target = { order = { 1, 2, 3, 4, 5, 6, 7, 8 }, off = {} } }
  local undo = M.ApplyClean(clean)
  Check(undo[1].had == false and undo[1].entry == nil, "absent kind: the undo record is had=false, entry=nil")
  local n = M.RestoreRecords(undo)
  Check(n == 1, "absent kind: RestoreRecords counts it as put back")
  local all = c.TwichUIDB.ui.markerOrder
  Check(all.target == nil, "absent kind: a kind that was absent is removed again on restore")
  ResetSaved()
end

-- invalid records (wrong kind, non-table) are skipped
do
  ResetSaved()
  local n = M.RestoreRecords({ kind = "bogus", had = true, entry = { order = { 1, 2, 3, 4, 5, 6, 7, 8 }, off = {} } })
  Check(n == 0, "RestoreRecords: a record with a wrong kind is skipped")
  n = M.RestoreRecords({ "not a record" })
  Check(n == 0, "RestoreRecords: a non-table record is skipped")
  n = M.RestoreRecords(nil)
  Check(n == 0, "RestoreRecords: a non-table records list restores nothing")
  ResetSaved()
end

print("TEST_MARKERS_SHARE PASSED")
