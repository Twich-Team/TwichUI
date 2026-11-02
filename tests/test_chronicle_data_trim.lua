dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", { "!!!TwichUI" })
c.TwichUIDB = { modules = { chronicle = false } }   -- tracking off: nothing auto-recorded while we test
c.LOADED["!!!TwichUI"] = true
c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local C = c.TwichUI.Chronicle
local NOW = 100000
c.time = function() return NOW end   -- controllable clock: C.Add stamps entries with time()

-- a full record: the given head entries (oldest first) plus filler level entries up to C.MAX_ENTRIES
local MAX = C.MAX_ENTRIES
local function fullRecord(head)
  local rec = C.Record()
  local entries, id = {}, 1
  for i = 1, #head do
    local e = head[i]
    e.id, e.t = id, e.t or (100 + i)
    entries[i] = e
    id = id + 1
  end
  while #entries < MAX do
    entries[#entries + 1] = { id = id, t = 100 + #entries + 1, kind = "level", title = "filler " .. id, level = 1 }
    id = id + 1
  end
  rec.entries, rec.nextId = entries, id
  return rec
end
local function byId(entries)
  local m = {}
  for _, e in ipairs(entries) do m[e.id] = e end
  return m
end

-- duplicate window: the same automatic entry (same kind and title) inside DUPLICATE_SECONDS is
-- refused, the same entry after the window is recorded again
local e1 = C.Add("level", { title = "Reached level 40", level = 40 })
assert(e1, "first add is recorded")
local dup, why = C.Add("level", { title = "Reached level 40", level = 40 })
assert(not dup and why == "duplicate", "the same automatic entry inside the window is refused")
NOW = NOW + C.DUPLICATE_SECONDS + 1   -- one second past the window
local e2 = C.Add("level", { title = "Reached level 40", level = 40 })
assert(e2 and e2.id ~= e1.id, "the same entry after the window is recorded again")

-- eviction via C.Add on a full record: a zone arrival goes before other automatic entries
fullRecord({
  { kind = "note", title = "Note", note = "keep me" },
  { kind = "level", title = "Reached level 10", level = 10 },
  { kind = "zone", title = "Arrived in Duskwood", zone = "Duskwood" },
  { kind = "start", title = "Chronicle begun" },
})
local added = C.Add("level", { title = "Reached level 99", level = 99 })
assert(added, "a full record makes room for a new entry")
local m = byId(C.Entries())
assert(m[1] and m[1].kind == "note" and m[2] and m[2].kind == "level" and m[4] and m[4].kind == "start",
  "the note, the older level entry and the first start line survive")
assert(not m[3], "the zone arrival is removed before other automatic entries")
assert(C.Count() == MAX, "one entry in, one out")

-- with no zone: the oldest other automatic entry goes, the player's notes and the first
-- 'start' line stay
fullRecord({
  { kind = "note", title = "Note", note = "keep me" },
  { kind = "start", title = "Chronicle begun" },
  { kind = "start", title = "Tracking resumed" },
})
added = C.Add("level", { title = "Reached level 98", level = 98 })
assert(added, "a full record makes room for a new entry")
m = byId(C.Entries())
assert(m[1] and m[1].kind == "note" and m[2] and m[2].kind == "start" and m[2].title == "Chronicle begun",
  "the note and the first 'start' line stay")
assert(m[3] and m[3].kind == "start" and m[3].title == "Tracking resumed",
  "the 'Tracking resumed' line stays while an older automatic entry can go")
assert(not m[4], "the oldest other automatic entry (filler) is removed before the resumed line")
assert(C.Count() == MAX, "one entry in, one out")

-- when only notes and the first 'start' remain, a later 'start' ('Tracking resumed') goes
do
  local rec = C.Record()
  local entries, id = {}, 1
  for i = 1, MAX - 3 do
    entries[i] = { id = id, t = 100 + i, kind = "note", title = "Note", note = "n" .. i }
    id = id + 1
  end
  entries[MAX - 2] = { id = id, t = 100 + MAX - 2, kind = "start", title = "Chronicle begun" }; id = id + 1
  entries[MAX - 1] = { id = id, t = 100 + MAX - 1, kind = "start", title = "Tracking resumed" }; id = id + 1
  entries[MAX] = { id = id, t = 100 + MAX, kind = "start", title = "Tracking resumed" }; id = id + 1
  rec.entries, rec.nextId = entries, id
  added = C.Add("level", { title = "Reached level 97", level = 97 })
  assert(added, "a full record makes room for a new entry")
  m = byId(C.Entries())
  assert(m[MAX - 2] and m[MAX - 2].kind == "start" and m[MAX - 2].title == "Chronicle begun",
    "the first 'start' line stays")
  assert(not m[MAX - 1], "the later 'Tracking resumed' line is removed")
  assert(m[MAX] and m[MAX].kind == "start" and m[MAX].title == "Tracking resumed",
    "the newer 'Tracking resumed' line stays")
  assert(C.Count() == MAX, "one entry in, one out")
end

-- when only notes and the first 'start' line remain, nothing may go: Add refuses with 'full'
do
  local rec = C.Record()
  local entries, id = {}, 1
  for i = 1, MAX - 1 do
    entries[i] = { id = id, t = 100 + i, kind = "note", title = "Note", note = "n" .. i }
    id = id + 1
  end
  entries[MAX] = { id = id, t = 100 + MAX, kind = "start", title = "Chronicle begun" }; id = id + 1
  rec.entries, rec.nextId = entries, id
  local refused, why = C.Add("level", { title = "Reached level 96", level = 96 })
  assert(not refused and why == "full", "nothing may be removed: Add refuses with 'full'")
  assert(C.Count() == MAX, "the record is unchanged")
end

-- SetDetails: adds a trimmed note and the played times to an existing automatic entry
for i = 1, 5 do C.Delete(C.Record().entries[1].id) end   -- free room left over from the full record
local target = C.Add("level", { title = "Reached level 41", level = 41 })
local set = C.SetDetails(target.id, { note = "  a long night  ", secsAtLevel = 120, secsTotal = 3600 })
assert(set and set.id == target.id, "SetDetails returns the automatic entry")
assert(set.note == "a long night", "the note is trimmed")
assert(set.secsAtLevel == 120 and set.secsTotal == 3600, "the played times are stored")
-- non-numeric values leave the stored ones; an empty note leaves the stored note
set = C.SetDetails(target.id, { note = "   ", secsAtLevel = "soon", secsTotal = nil })
assert(set.note == "a long night" and set.secsAtLevel == 120 and set.secsTotal == 3600,
  "non-numeric or empty values keep what was stored")
-- a note id and a missing id are refused with a reason
local note = C.Add("note", { title = "Note", note = "mine" })
local refused, why = C.SetDetails(note.id, { note = "no", secsAtLevel = 1, secsTotal = 1 })
assert(not refused and why == "not found", "SetDetails refuses a note id")
refused, why = C.SetDetails(999999, { note = "no" })
assert(not refused and why == "not found", "SetDetails refuses a missing id")

-- notes are never duplicate-suppressed: the same note twice in the same second keeps both
local n1 = C.Add("note", { title = "Note", note = "same second" })
local n2 = C.Add("note", { title = "Note", note = "same second" })
assert(n1 and n2 and n1.id ~= n2.id, "notes are never duplicate-suppressed")

print("TEST_CHRONICLE_DATA_TRIM PASSED")
