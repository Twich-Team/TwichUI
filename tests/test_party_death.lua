dofile(TESTS .. "harness.lua")
-- Party member fallen (modules/PartyDeath.lua): when a death is announced and when it is not, the identity rules, the
-- two settings, the one-copy sound, and the card through the real notification coordinator. A fake party stands in for
-- the game, so this checks our logic, not the game: the real-client checks are listed in docs/notification-appearance.md.

local function Check(cond, msg) if not cond then error(msg, 2) end end

-- A fake frame that records what a feature asks of it.
local function Obj()
  local o = { text = "", shown = false, unitEvents = {}, events = {}, scripts = {} }
  return setmetatable(o, { __index = function(t, k)
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetText" then return function(s, v) s.text = v or "" end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "SetFont" then return function(s, path) s.font = path; return true end end
    if k == "SetTextColor" then return function(s, r, g, b) s.color = { r, g, b } end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "RegisterUnitEvent" then return function(s, e, ...) s.unitEvents[e] = { ... } end end
    if k == "RegisterEvent" then return function(s, e) s.events[e] = true end end
    if k == "UnregisterAllEvents" then return function(s) s.events, s.unitEvents = {}, {} end end
    if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
    if k == "GetStringWidth" or k == "GetUnboundedStringWidth" then return function(s) return #(s.text or "") * 8 end end
    if k == "GetStringHeight" then return function() return 14 end end
    if k == "GetWidth" then return function(s) return s.width or 372 end end
    if k == "GetHeight" then return function(s) return s.height or 100 end end
    if k == "SetSize" then return function(s, w, h) s.width, s.height = w, h end end
    if k == "SetWidth" then return function(s, w) s.width = w end end
    if k == "SetHeight" then return function(s, h) s.height = h end end
    if k == "CreateFontString" then return function() local f = Obj(); f.isText = true; t.texts = t.texts or {}; t.texts[#t.texts + 1] = f; return f end end
    if k == "CreateTexture" or k == "CreateAnimationGroup" or k == "CreateAnimation" then return function() return Obj() end end
    if type(k) == "string" and k:match("^%l") then return nil end
    return function() end
  end })
end

local FILES = { "chronicle/Style.lua", "modules/Notify.lua", "modules/NotifyLook.lua", "modules/Arrival.lua", "modules/PartyDeath.lua" }

-- A client with the card and the coordinator loaded, in the world, with an empty party.
local function Client(db)
  local c = MakeClient("Rich", { "!!!TwichUI" })
  c.FRAMES = {}
  c.CreateFrame = function() local o = Obj(); c.FRAMES[#c.FRAMES + 1] = o; return o end
  c.UIParent = Obj(); c.UIParent.width, c.UIParent.height = 1024, 768
  c.GameTooltip = Obj()
  c.NOW = 1000
  c.GetTime = function() return c.NOW end
  c.issecretvalue = nil
  c.UNKNOWNOBJECT = "Unknown"
  c.SOUNDS = {}
  c.PlaySoundFile = function(path, channel) c.SOUNDS[#c.SOUNDS + 1] = { path = path, channel = channel }; return c.PLAYS ~= false end
  c.PARTY, c.RAID = {}, false
  c.IsInRaid = function() return c.RAID end
  c.UnitExists = function(u) return c.PARTY[u] ~= nil end
  c.UnitIsPlayer = function(u) return c.PARTY[u].npc ~= true end
  c.UnitIsUnit = function(u, other) return other == "player" and c.PARTY[u].self == true end
  c.UnitGUID = function(u) return c.PARTY[u] and c.PARTY[u].guid end
  c.UnitIsConnected = function(u) return c.PARTY[u].offline ~= true end
  c.UnitHealthMax = function(u) local m = c.PARTY[u].max; if m == nil then return 100 end return m end
  c.UnitIsDeadOrGhost = function(u) return c.PARTY[u].dead == true end
  c.UnitIsFeignDeath = function(u) return c.PARTY[u].feign == true end
  local baseName = c.UnitName
  c.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 } }
  c.UnitClass = function(u) local p = c.PARTY[u]; if not p or not p.class then return nil end return p.class:sub(1, 1) .. p.class:sub(2):lower(), p.class end
  c.UnitName = function(u) local p = c.PARTY[u]; if not p then return baseName(u) end return p.name, p.realm end
  c.SUBMITS = 0
  for _, f in ipairs(FILES) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  c.TwichUIDB = db or { modules = {} }
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.R = c.TwichUI
  local N = c.R.Notify
  local submit = N.Submit
  N.Submit = function(request) if request.kind == "partydeath" and not request.preview then c.SUBMITS = c.SUBMITS + 1 end return submit(request) end
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false)   -- the coordinator is in the world; the card's own baseline is taken
  return c
end

local function Member(c, unit, guid, name, extra)
  local m = { guid = guid, name = name }
  for k, v in pairs(extra or {}) do m[k] = v end
  c.PARTY[unit] = m
  return m
end
-- The card's private event frame: the one with unit events.
local function Frame(c) for _, f in ipairs(c.FRAMES) do if next(f.unitEvents) or next(f.events) then return f end end end
local function Fire(c, event, unit) c.R.PartyDeath.OnEvent(event, unit) end
local function Shown(c) local s = c.R.Notify.Snapshot().shown; return (s.partydeath or 0) end
-- The card's line: its name piece and the rest, as one string. Also returns the name piece itself.
local function Body(c)
  for _, f in ipairs(c.FRAMES) do
    local texts = f.texts
    if texts and texts[3] and texts[3].text:find("died") then return texts[2].text .. texts[3].text, texts[2] end
  end
end

---------------------------------------------------------------------------
-- Defaults and settings
---------------------------------------------------------------------------
do
  local c = Client({ modules = {} })
  Check(c.TwichUIDB.modules.partyDeath ~= false and c.R:Enabled("partyDeath"), "the card is on for a new profile")
  Check(c.R:Enabled("partyDeathSound"), "the sound is on for a new profile")
  Check(c.R.DEFAULT_MODULES.partyDeath == true and c.R.DEFAULT_MODULES.partyDeathSound == true, "both are on in the defaults")
  local f = Frame(c)
  Check(f, "events are registered when it is on")
  for _, e in ipairs({ "UNIT_HEALTH", "UNIT_FLAGS", "UNIT_CONNECTION" }) do
    Check(table.concat(f.unitEvents[e] or {}, ",") == "party1,party2,party3,party4", e .. " is for the four party units only")
  end
  Check(f.events.GROUP_ROSTER_UPDATE and f.events.PLAYER_ENTERING_WORLD, "roster events registered")
  Check(c.R.PartyDeath.Snapshot().events == 6, "diagnostics sees six events")
  Check(not (f.scripts.OnUpdate), "no OnUpdate")
end

do   -- saved false is kept, whatever else is missing
  local c = Client({ modules = { partyDeath = false } })
  Check(c.TwichUIDB.modules.partyDeath == false, "a saved false stays false")
  Check(c.TwichUIDB.modules.partyDeathSound == true, "a missing sound switch is filled with its default")
  Check(c.R.PartyDeath.Snapshot().events == 0, "off: nothing registered")
end

---------------------------------------------------------------------------
-- Transitions
---------------------------------------------------------------------------
do
  local c = Client()
  local P = c.R.PartyDeath
  Member(c, "party1", "Player-1-A", "Alice")
  Member(c, "party2", "Player-1-B", "Bob", { dead = true })   -- already dead when first seen
  Fire(c, "GROUP_ROSTER_UPDATE")
  Check(c.SUBMITS == 0, "a member first seen dead is not announced")
  Fire(c, "UNIT_HEALTH", "party2"); Fire(c, "UNIT_FLAGS", "party2")
  Check(c.SUBMITS == 0, "events for a member who was already dead announce nothing")

  c.PARTY.party1.dead = true
  Fire(c, "UNIT_HEALTH", "party1")
  Check(c.SUBMITS == 1 and Shown(c) == 1, "a confirmed death gives one card")
  Check(#c.SOUNDS == 1, "and one sound")
  Check(c.SOUNDS[1].path == [[Interface\AddOns\!!!TwichUI\media\sounds\LAMENT.mp3]], "the lament: " .. tostring(c.SOUNDS[1].path))
  Check(c.SOUNDS[1].channel == "SFX", "on the Sound Effects channel")
  Check(Body(c) == "Alice has died.", tostring(Body(c)))
  Fire(c, "UNIT_HEALTH", "party1"); Fire(c, "UNIT_FLAGS", "party1"); Fire(c, "GROUP_ROSTER_UPDATE"); Fire(c, "UNIT_CONNECTION", "party1")
  Check(c.SUBMITS == 1 and #c.SOUNDS == 1, "duplicate death events add nothing")

  -- resurrection, then another death: a new notice (it waits behind the card still showing)
  c.PARTY.party1.dead = false
  Fire(c, "UNIT_HEALTH", "party1")
  Check(c.SUBMITS == 1, "the resurrection announces nothing")
  c.PARTY.party1.dead = true
  Fire(c, "UNIT_HEALTH", "party1")
  Check(c.SUBMITS == 2, "a death after a resurrection is announced again")
  local state = c.R.Notify.State()
  Check(#state.waiting == 1 and #state.active == 1, "the second card waits its turn in the queue, not dropped")
  Check(#c.SOUNDS == 1, "and its lament is not played over the first, still playing")
  c.NOW = c.NOW + 7
  c.R.Notify.Finished("partydeath")
  Check(Shown(c) == 2 and #c.SOUNDS == 2, "when the first has finished the second shows, with the lament again")
  c.R.Notify.Finished("partydeath")
end

do   -- unknown is not alive
  local c = Client()
  Member(c, "party1", "Player-1-A", "Alice", { max = 0 })       -- the game has not given its health yet
  Fire(c, "GROUP_ROSTER_UPDATE")
  c.PARTY.party1.max, c.PARTY.party1.dead = 100, true
  Fire(c, "UNIT_HEALTH", "party1")
  Check(c.SUBMITS == 0, "unknown then dead is not a confirmed transition")
  c.PARTY.party1.dead = false
  Fire(c, "UNIT_HEALTH", "party1")
  c.PARTY.party1.dead = true
  Fire(c, "UNIT_HEALTH", "party1")
  Check(c.SUBMITS == 1, "once seen alive, a death counts")
  c.R.Notify.Finished("partydeath")

  Member(c, "party2", "Player-1-B", "Bob")
  Fire(c, "GROUP_ROSTER_UPDATE")
  c.PARTY.party2.offline = true
  Fire(c, "UNIT_CONNECTION", "party2")
  c.PARTY.party2.dead = true
  c.PARTY.party2.offline = false
  Fire(c, "UNIT_CONNECTION", "party2")
  Check(c.SUBMITS == 1, "a member who went offline is unknown, not alive: coming back dead is not announced")
end

do   -- feigning death is not dying
  local c = Client()
  Member(c, "party1", "Player-1-H", "Hunter")
  Fire(c, "GROUP_ROSTER_UPDATE")
  c.PARTY.party1.dead, c.PARTY.party1.feign = true, true
  Fire(c, "UNIT_FLAGS", "party1")
  Check(c.SUBMITS == 0, "a feigned death announces nothing")
  c.PARTY.party1.feign = false
  Fire(c, "UNIT_FLAGS", "party1")
  Check(c.SUBMITS == 1, "dead without the feign is a real death, seen alive a moment before")
end

do   -- a loading screen starts over
  local c = Client()
  Member(c, "party1", "Player-1-A", "Alice")
  Fire(c, "GROUP_ROSTER_UPDATE")
  c.FireEvent("PLAYER_LEAVING_WORLD"); c.PARTY.party1.dead = true; c.FireEvent("PLAYER_ENTERING_WORLD", false, true)
  Check(c.SUBMITS == 0, "a member dead when the world is entered is a baseline, not a death")
end

---------------------------------------------------------------------------
-- Identity and who counts
---------------------------------------------------------------------------
do
  local c = Client()
  Member(c, "party1", "Player-1-A", "Alice")
  Member(c, "party2", "Player-1-B", "Bob")
  Fire(c, "GROUP_ROSTER_UPDATE")
  Check(c.R.PartyDeath.Snapshot().tracked == 2, "two members tracked")

  -- Alice leaves; Carol takes the unit token, already dead
  c.PARTY.party1 = { guid = "Player-1-C", name = "Carol", dead = true }
  Fire(c, "UNIT_HEALTH", "party1")
  Check(c.SUBMITS == 0, "a new player on a reused token is not taken for the one who was there")
  Fire(c, "GROUP_ROSTER_UPDATE")
  Check(c.R.PartyDeath.Snapshot().tracked == 2, "the member who left is forgotten")

  -- Bob and Carol swap tokens, Bob dying at the same time: he is named, once
  c.PARTY.party1, c.PARTY.party2 = { guid = "Player-1-B", name = "Bob", dead = true }, { guid = "Player-1-C", name = "Carol", dead = true }
  Fire(c, "GROUP_ROSTER_UPDATE")
  Check(c.SUBMITS == 1 and Body(c) == "Bob has died.", "identity follows the player, not the token: " .. tostring(Body(c)))
end

do
  local c = Client()
  Member(c, "party1", "Player-1-S", "Me", { self = true })
  Member(c, "party2", "Player-1-N", "Guard", { npc = true })
  Member(c, "party3", "Player-1-A", "Alice")
  Fire(c, "GROUP_ROSTER_UPDATE")
  c.PARTY.party1.dead, c.PARTY.party2.dead = true, true
  Fire(c, "UNIT_HEALTH", "party1"); Fire(c, "UNIT_HEALTH", "party2")
  Fire(c, "UNIT_HEALTH", "partypet1"); Fire(c, "UNIT_HEALTH", "raid5"); Fire(c, "UNIT_HEALTH", "target"); Fire(c, "UNIT_HEALTH", nil)
  Check(c.SUBMITS == 0, "yourself, an NPC, pets and other units are not announced")

  c.RAID = true
  c.PARTY.party3.dead = true
  Fire(c, "UNIT_HEALTH", "party3")
  Check(c.SUBMITS == 0, "a raid group is not covered")
  Fire(c, "GROUP_ROSTER_UPDATE")
  Check(c.R.PartyDeath.Snapshot().tracked == 0, "nothing is tracked in a raid")
  c.RAID = false
  Fire(c, "GROUP_ROSTER_UPDATE")
  Check(c.SUBMITS == 0, "back in a party, the member found dead is a baseline")
end

do   -- names
  local c = Client()
  Member(c, "party1", "Player-1-A", "Alice", { realm = "Area 52", class = "MAGE" })
  Member(c, "party2", "Player-1-B", nil)
  Member(c, "party3", "Player-1-C", "Averyveryveryveryveryverylongcharactername", { realm = "Argentdawnonthesecondrealmofthreerealms" })
  Fire(c, "GROUP_ROSTER_UPDATE")
  for _, u in ipairs({ "party1" }) do c.PARTY[u].dead = true; Fire(c, "UNIT_HEALTH", u) end
  local line, name = Body(c)
  Check(line == "Alice (Area 52) has died.", "another realm is shown: " .. tostring(line))
  Check(name.text == "Alice" and name.font:find("AlegreyaSans%-Bold"), "the name is its own piece, in a bold face: " .. tostring(name.font))
  Check(math.abs(name.color[1] - 0.25) < 1e-6 and math.abs(name.color[2] - 0.78) < 1e-6, "in the class color")
  c.R.Notify.Finished("partydeath")
  c.PARTY.party2.dead = true; Fire(c, "UNIT_HEALTH", "party2")
  Check(Body(c) == "A party member has died.", "an unknown name still gives a card: " .. tostring(Body(c)))
  c.R.Notify.Finished("partydeath")
  c.PARTY.party3.dead = true; Fire(c, "UNIT_HEALTH", "party3")
  Check(Body(c):find("^Averyvery") and Body(c):find("%(Argentdawn"), "a long name and realm reach the card")
  local _, longName = Body(c)
  Check(longName.color == nil or longName.color[1] ~= 0.25, "no known class: not a class color")
  Check(longName.width and longName.width <= 560, "a long name is held inside the card: " .. tostring(longName.width))
end

---------------------------------------------------------------------------
-- Settings: the card and the sound are independent
---------------------------------------------------------------------------
do
  local c = Client()
  Member(c, "party1", "Player-1-A", "Alice")
  Fire(c, "GROUP_ROSTER_UPDATE")
  c.R:SetEnabled("partyDeathSound", false)
  c.PARTY.party1.dead = true; Fire(c, "UNIT_HEALTH", "party1")
  Check(Shown(c) == 1 and #c.SOUNDS == 0, "sound off: the card still shows, silently")
  c.R.Notify.Finished("partydeath")

  c.R:SetEnabled("partyDeathSound", true)
  c.R:SetEnabled("partyDeath", false)
  Check(Frame(c) == nil and c.R.PartyDeath.Snapshot().events == 0, "card off: events are given back")
  c.PARTY.party1.dead = true   -- dies while the card is off
  c.R:SetEnabled("partyDeath", true)
  Check(Frame(c) ~= nil, "card on again: events are back")
  Fire(c, "UNIT_HEALTH", "party1")
  Check(Shown(c) == 1 and #c.SOUNDS == 0, "turned on while a member is dead: that is a baseline, not an announcement")
  c.PARTY.party1.dead = false; Fire(c, "UNIT_HEALTH", "party1")
  c.PARTY.party1.dead = true; Fire(c, "UNIT_HEALTH", "party1")
  Check(Shown(c) == 2 and #c.SOUNDS == 1, "and then a real death shows and plays")
  c.R.Notify.Finished("partydeath")

  -- off while a card waits: both go
  c.NOW = c.NOW + 7
  c.PARTY.party1.dead = false; Fire(c, "UNIT_HEALTH", "party1")
  c.PARTY.party1.dead = true; Fire(c, "UNIT_HEALTH", "party1")
  local before = #c.SOUNDS
  c.R:SetEnabled("partyDeath", false)
  Check(#c.R.Notify.State().active == 0 and #c.R.Notify.State().waiting == 0, "turning it off puts away a card showing or waiting")
  Check(before == 2, "the death while on had its sound")
end

---------------------------------------------------------------------------
-- Previews
---------------------------------------------------------------------------
do
  local c = Client({ modules = { partyDeath = false } })   -- a preview works with the card off
  local N = c.R.Notify
  local kinds = {}
  for _, k in ipairs(N.Kinds()) do kinds[k.kind] = k end
  Check(kinds.partydeath and kinds.partydeath.sample and kinds.partydeath.label == "Party member fallen", "registered with a sample")
  Check(N.Preview("partydeath"), "the preview is accepted")
  Check(N.PreviewShowing("partydeath") and #c.SOUNDS == 0, "previews are silent unless previews are allowed sound")
  local line, name = Body(c)
  Check(line == "Aldric Stormveil has died." and math.abs(name.color[1] - 0.96) < 1e-6, tostring(line))
  N.ClearPreviews()
  N.SetPreviewSounds(true)
  N.Preview("partydeath")
  Check(#c.SOUNDS == 1, "previews allowed sound and the card's sound on: one lament")
  N.ClearPreviews()
  c.R:SetEnabled("partyDeathSound", false)
  c.NOW = c.NOW + 7
  N.Preview("partydeath")
  Check(#c.SOUNDS == 1, "the card's sound off: a preview is silent too")
  N.ClearPreviews()
  Check(c.SUBMITS == 0, "a preview announces no death")
end

print("PASSED test_party_death")
