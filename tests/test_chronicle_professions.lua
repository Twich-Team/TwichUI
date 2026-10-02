dofile(TESTS .. "harness.lua")
local function boot(saved)
  local c = MakeClient("Alpha", {"!!!TwichUI"})
  c.print = function() end
  c.TwichUIDB = saved and saved.db or {}
  c.TwichUIChronicleDB = saved and saved.chron or nil
  c.GetRealZoneText = function() return "Elwynn Forest" end
  c.GetZoneText = c.GetRealZoneText
  c.UnitLevel = function() return 20 end
  c.GetMoney = function() return 0 end
  c.UnitOnTaxi = function() return false end
  c.IsSpellKnown = function() return false end
  c.RequestTimePlayed = function() end
  -- PROFS: { { name, rank }, ... } in index order; skill line = 100 + index key
  c.PROFS = (saved and saved.profs) or {}
  c.GetProfessions = function()
    local idx = {}
    for i in ipairs(c.PROFS) do idx[#idx + 1] = i end
    return unpack(idx)
  end
  c.GetProfessionInfo = function(i)
    local p = c.PROFS[i]
    return p.name, 1000 + p.line, p.rank, 450, 0, 0, p.line
  end
  c.LOADED["!!!TwichUI"] = true
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  RunLongTimers(10)            -- the first look, after the profession list has settled
  return c
end
local function titles(C)
  local t = {}
  for _, e in ipairs(C.Entries()) do if e.kind == "profession" then t[#t + 1] = e.title end end
  return t
end
local function settle(c) c.FireEvent("SKILL_LINES_CHANGED"); FlushTimers() end

-- existing professions at the start: no entries, no backlog of milestones
local a = boot({ profs = { { name = "Alchemy", line = 171, rank = 160 }, { name = "Cooking", line = 185, rank = 300 } } })
local C = a.TwichUI.Chronicle
assert(#titles(C) == 0, "nothing for what already exists")
settle(a); assert(#titles(C) == 0, "repeated event, still nothing")
local st = C.Record().journey.professions
assert(st.baselined and st[171][75] and st[171][150] and not st[171][225] and st[185][300])

-- a milestone is a genuine future crossing, written once
a.PROFS[1].rank = 224; settle(a); assert(#titles(C) == 0)
a.PROFS[1].rank = 225; settle(a); settle(a)
assert(#titles(C) == 1 and titles(C)[1] == "Alchemy reached 225", titles(C)[1])
a.PROFS[1].rank = 100; settle(a); a.PROFS[1].rank = 230; settle(a)
assert(#titles(C) == 1, "a drop and recovery doesn't repeat it")
a.PROFS[1].rank = 460; settle(a)    -- crosses 300, 375, 450 together
assert(#titles(C) == 4)

-- the entry carries the profession's icon
local e = C.Entries()[#C.Entries()]
assert(e.kind == "profession" and e.icon == 1171)

-- learning a profession: one entry, with the stable key stored; unlearn/relearn adds nothing
a.PROFS[3] = { name = "Fishing", line = 356, rank = 1 }; settle(a)
assert(titles(C)[5] == "Learned Fishing" and #titles(C) == 5)
a.PROFS[3] = nil; settle(a); a.PROFS[3] = { name = "Fishing", line = 356, rank = 1 }; settle(a)
assert(#titles(C) == 5, "relearning isn't a new acquisition")
a.PROFS[3].rank = 75; settle(a)
assert(titles(C)[6] == "Fishing reached 75")

-- reload / relog: nothing repeated
local b = boot({ db = a.TwichUIDB, chron = a.TwichUIChronicleDB, profs = a.PROFS })
settle(b); assert(#titles(b.TwichUI.Chronicle) == 6)

-- chat line: only when an entry was written
local lines = {}
a.print = function(s) lines[#lines + 1] = s end
a.PROFS[3].rank = 150; settle(a); assert(#lines == 1)
settle(a); assert(#lines == 1, "no chat line without a new entry")
a.TwichUIDB.modules.chronicleChat = false
a.PROFS[3].rank = 225; settle(a); assert(#lines == 1 and #titles(C) == 8, "recorded, but silent when chat is off")

-- off: nothing watched; progress while off is not recorded later
a.TwichUIDB.modules.chronicleProfessions = false; a.TwichUI.ChronicleRecorder.Refresh()
assert(not a.TwichUI.frame.events.SKILL_LINES_CHANGED)
a.PROFS[3].rank = 300; a.PROFS[4] = { name = "First Aid", line = 129, rank = 1 }
a.TwichUIDB.modules.chronicleProfessions = true; a.TwichUI.ChronicleRecorder.Refresh()
settle(a); assert(#titles(C) == 8, "what happened while off isn't added")
a.PROFS[3].rank = 375; settle(a); assert(titles(C)[9] == "Fishing reached 375")

-- played time for the header: delivered once, late answers and timeouts are safe
local got = {}
local Rec = a.TwichUI.ChronicleRecorder
Rec.RequestPlayed(function(t) got[#got + 1] = t end)
Rec.RequestPlayed(function(t) got[#got + 1] = t end)
assert(#got == 0, "nothing until the game answers")
a.FireEvent("TIME_PLAYED_MSG", 5000, 100)
assert(#got == 2 and got[1] == 5000, "answered once")
a.FireEvent("TIME_PLAYED_MSG", 6000, 100); assert(#got == 2, "a stray answer is ignored")
Rec.RequestPlayed(function(t) got[#got + 1] = t end)
RunLongTimers(60); a.FireEvent("TIME_PLAYED_MSG", 7000, 1)
assert(#got == 2, "a timed-out request never calls back")

-- no API: nothing happens
local n = boot(); n.GetProfessions = nil
settle(n)
print("PASSED chronicle professions")
