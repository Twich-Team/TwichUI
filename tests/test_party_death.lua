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
    if k == "SetTexture" then return function(s, v) s.texture = v end end
    if k == "SetAlpha" then return function(s, v) s.alpha = v end end
    if k == "ClearAllPoints" then return function(s) s.points = {} end end
    if k == "SetPoint" then return function(s, ...) s.points = s.points or {}; s.points[#s.points + 1] = { ... } end end
    if k == "SetOffset" then return function(s, x, y) s.offset = { x, y } end end
    if k == "SetStartDelay" then return function(s, v) s.delay = v end end
    if k == "SetDuration" then return function(s, v) s.duration = v end end
    if k == "Play" then return function(s) s.plays = (s.plays or 0) + 1; s.playing = true end end
    if k == "Stop" then return function(s) s.playing = false end end
    if k == "CreateTexture" then return function() local f = Obj(); t.textures = t.textures or {}; t.textures[#t.textures + 1] = f; return f end end
    if k == "CreateAnimationGroup" then return function() local g = Obj(); t.groups = t.groups or {}; t.groups[#t.groups + 1] = g; return g end end
    if k == "CreateAnimation" then return function(s, kind) local a = Obj(); a.kind = kind; s.anims = s.anims or {}; s.anims[#s.anims + 1] = a; return a end end
    if type(k) == "string" and k:match("^%l") then return nil end
    return function() end
  end })
end

local FILES = { "chronicle/Style.lua", "modules/Notify.lua", "modules/NotifyLook.lua", "modules/Arrival.lua", "modules/PartyDeathMist.lua", "modules/PartyDeath.lua" }

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
  c.UnitGroupRolesAssigned = function(u) local p = c.PARTY[u]; return p and p.role or "NONE" end
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

---------------------------------------------------------------------------
-- Role icon and the mist scene
---------------------------------------------------------------------------
-- The card's frame (the one with text pieces), its role icon (the second texture: the tombstone is the first) and the mist.
local function CardFrame(c) for _, f in ipairs(c.FRAMES) do if f.texts and f.textures then return f end end end
local function RoleIcon(c) return CardFrame(c).textures[2] end
local function Die(c, unit) c.PARTY[unit].dead = true; Fire(c, "UNIT_HEALTH", unit) end
local function Next(c) c.NOW = c.NOW + 7; c.R.Notify.Finished("partydeath") end
local ART = [[Interface\AddOns\!!!TwichUI\media\partydeath\]]

do   -- each role has its own art; the name line stays centred with it; unknown roles give the text-only line
  local c = Client()
  local roles = { { "TANK", "role-tank" }, { "HEALER", "role-healer" }, { "DAMAGER", "role-dps" } }
  Member(c, "party1", "Player-1-A", "Alice", { class = "MAGE" })
  Fire(c, "GROUP_ROSTER_UPDATE")
  for _, r in ipairs(roles) do
    c.PARTY.party1.dead = false; Fire(c, "UNIT_HEALTH", "party1")
    c.PARTY.party1.role = r[1]
    Die(c, "party1")
    local line, name = Body(c)
    local icon = RoleIcon(c)
    Check(line == "Alice has died.", "the wording is unchanged with a role: " .. tostring(line))
    Check(icon.shown and icon.texture == ART .. r[2], r[1] .. " -> " .. r[2] .. ": " .. tostring(icon.texture))
    -- icon + gap + name + rest are one centred group: its left edge is -total/2
    local total = 25 + 40 + 80
    local x = name.points[1][4]
    Check(math.abs(x - (-total / 2 + 25)) < 1e-6, "the name makes room for the icon: " .. tostring(x))
    Check(icon.points[1][1] == "RIGHT" and icon.points[1][2] == name and icon.points[1][3] == "LEFT" and icon.points[1][4] == -5, "the icon sits just before the name")
    Check(icon.alpha == nil and not icon.color, "the icon is not tinted")
    Next(c)
  end
  for _, role in ipairs({ "NONE", "", "GURU", false }) do
    c.PARTY.party1.dead = false; Fire(c, "UNIT_HEALTH", "party1")
    c.PARTY.party1.role = role
    Die(c, "party1")
    local line, name = Body(c)
    Check(not RoleIcon(c).shown and RoleIcon(c).texture == nil, "role " .. tostring(role) .. ": no icon, no placeholder")
    Check(math.abs(name.points[1][4] - (-(40 + 80) / 2)) < 1e-6, "and the original centring: " .. tostring(name.points[1][4]))
    Next(c)
  end
end

do   -- frame reuse: a known role, then an unknown one; queued players keep their own role
  local c = Client()
  Member(c, "party1", "Player-1-A", "Alice", { role = "HEALER" })
  Member(c, "party2", "Player-1-B", "Bobby", { role = "TANK" })
  Member(c, "party3", "Player-1-C", "Carol")
  Fire(c, "GROUP_ROSTER_UPDATE")
  Die(c, "party1"); Die(c, "party2"); Die(c, "party3")
  Check(c.SUBMITS == 3, "three deaths queued")
  -- the roster changes while two of them wait: the tokens now hold other players, with other roles
  Member(c, "party2", "Player-1-Z", "Zed", { role = "DAMAGER" })
  Member(c, "party3", "Player-1-Y", "Yara", { role = "HEALER" })
  Check(RoleIcon(c).texture == ART .. "role-healer", "the first card: its own healer")
  Next(c)
  local line = Body(c)
  Check(line == "Bobby has died." and RoleIcon(c).texture == ART .. "role-tank" and RoleIcon(c).shown, "Bobby keeps his tank role, not the token's new player: " .. tostring(line))
  Next(c)
  line = Body(c)
  Check(line == "Carol has died." and not RoleIcon(c).shown and RoleIcon(c).texture == nil, "Carol had none: the icon is cleared, not Bobby's: " .. tostring(line))
  Next(c)
end

do   -- the role is the exact player's: a token that has changed hands since is not read
  local c = Client()
  Member(c, "party1", "Player-1-A", "Alice", { role = "TANK" })
  Fire(c, "GROUP_ROSTER_UPDATE")
  local guids = 0
  local real = c.UnitGUID
  c.UnitGUID = function(u) guids = guids + 1; if guids > 6 then return "Player-1-OTHER" end return real(u) end
  local before = c.SUBMITS
  Die(c, "party1")
  Check(c.SUBMITS == before + 1, "a death is still announced")
  Check(Shown(c) == 1, "and shown without waiting on role data")
end

do   -- a long name and realm with a role icon stay inside the card
  local c = Client()
  Member(c, "party1", "Player-1-A", "Averyveryveryveryveryverylongcharactername", { realm = "Argentdawnonthesecondrealmofthreerealms", role = "DAMAGER" })
  Fire(c, "GROUP_ROSTER_UPDATE")
  Die(c, "party1")
  local _, name = Body(c)
  Check(RoleIcon(c).shown, "the icon shows")
  local rest = 8 * #" (Argentdawnonthesecondrealmofthreerealms) has died."
  Check(name.width and name.width + rest + 25 <= 560 + 1e-6, "icon, name and the rest fit the card: " .. tostring(name.width))
  Next(c)
end

do   -- the mist: a fixed pool, started with the card, recycled in separate lives, gone with it, never growing
  local c = Client()
  Member(c, "party1", "Player-1-A", "Alice", { role = "TANK" })
  Fire(c, "GROUP_ROSTER_UPDATE")
  local M = c.R.PartyDeathMist
  local seed = 7
  M.SetRandom(function() seed = (seed * 16807) % 2147483647; return seed / 2147483647 end)   -- reproducible
  Check(M.Snapshot().built == 0 and not M.Snapshot().playing, "nothing is built before the first death")
  Die(c, "party1")
  local frame = CardFrame(c)
  Check(#frame.textures == 2 + M.PIECES, "the mist is a fixed set of textures: " .. #frame.textures)
  local snap = M.Snapshot()
  Check(snap.built == M.PIECES and snap.shown == M.PIECES and snap.playing, "all pieces shown and playing")
  local delays, last = {}, 0
  for i = 3, #frame.textures do
    local tex = frame.textures[i]
    local g = tex.groups[1]
    Check(tex.alpha == 0 and tex.points[1][2] == frame and tex.points[1][3] == "TOP", "piece " .. i .. " starts clear and is anchored to the card")
    Check(tex.scripts.OnMouseDown == nil and tex.scripts.OnEnter == nil, "and takes no clicks")
    delays[tostring(g.anims[4].delay)] = true
    local out = g.anims[5]
    last = math.max(last, out.delay + out.duration)
    Check(g.anims[4].delay + g.anims[4].duration < out.delay + out.duration, "piece " .. i .. " fades in before it fades out")
    Check(not g.scripts.OnUpdate and g.scripts.OnFinished, "piece " .. i .. " recycles from its group's finish, not an OnUpdate")
  end
  local n = 0; for _ in pairs(delays) do n = n + 1 end
  Check(n >= 8, "entrances are staggered: " .. n .. " distinct starts")
  Check(last <= 8.1 + 1e-6, "the first lives all end before the card's exit ends: " .. last)

  -- lives recycle with fresh values, never past the end, and stop being started when they could not finish
  local tex3, g3 = frame.textures[6], frame.textures[6].groups[1]     -- a wisp slot
  local before = { x = tex3.points[#tex3.points][4], y = tex3.points[#tex3.points][5], tex = tex3.texture, plays = g3.plays }
  c.NOW = c.NOW + 3.5; g3.scripts.OnFinished(g3)
  Check(g3.plays == before.plays + 1, "a finished life starts the next one")
  Check(tex3.texture ~= before.tex, "the next life has a different shape")
  local p = tex3.points[#tex3.points]
  Check(p[4] ~= before.x or p[5] ~= before.y, "and a different place")
  Check(#frame.textures == 2 + M.PIECES, "no texture was created for it")
  local worst = 0
  for i = 3, #frame.textures do
    local g = frame.textures[i].groups[1]
    local now = c.NOW - 1000
    for _, a in ipairs({ g.anims[4], g.anims[5], g.anims[3] }) do worst = math.max(worst, now + a.delay + a.duration) end
  end
  c.NOW = c.NOW + 4.2; g3.scripts.OnFinished(g3)     -- 7.7 s in: too late for a life
  Check(not tex3.shown, "no life is begun that could not finish: the slot is put away")
  Check(worst <= 8.1 + 1e-6 + 3.5, "recycled lives still end in time")

  -- dismissal puts everything away
  c.R.Notify.Cancel("partydeath")
  snap = M.Snapshot()
  Check(snap.shown == 0 and not snap.playing, "dismissed: nothing shown, nothing playing")
  for i = 3, #frame.textures do Check(frame.textures[i].alpha == 0 and not frame.textures[i].shown, "piece " .. i .. " is reset") end
  Check(not frame.groups[1].playing, "the card's own animation is stopped")
  for i = 3, #frame.textures do Check(not frame.textures[i].groups[1].playing, "no mist animation left running") end
  Check(not frame.scripts.OnUpdate, "no OnUpdate anywhere on the card")
  -- a stale callback after dismissal starts nothing
  local plays = g3.plays
  g3.scripts.OnFinished(g3)
  Check(g3.plays == plays and not tex3.shown, "a finish arriving after dismissal does nothing")
  -- repeated triggers: no new textures, groups restarted, not stacked
  for round = 1, 3 do
    c.PARTY.party1.dead = false; Fire(c, "UNIT_HEALTH", "party1")
    Die(c, "party1")
    Check(#frame.textures == 2 + M.PIECES and #frame.groups == 1, "round " .. round .. ": the same objects, no growth: " .. #frame.textures .. "/" .. #frame.groups)
    Next(c)
  end
  c.PARTY.party1.dead = false; Fire(c, "UNIT_HEALTH", "party1")
  Die(c, "party1")
  Check(M.Snapshot().shown == M.PIECES, "one more death: the scene plays again")
  c.R.Notify.Cancel("partydeath")
  Check(M.Snapshot().shown == 0 and not M.Snapshot().playing, "a dismissed card takes the mist with it")
  M.SetRandom(nil)
end

do   -- reduced motion: the pieces only fade, with no drift, growth, staggering or later lives
  local c = Client()
  c.R:SetEnabled("arrivalReducedMotion", true)
  Member(c, "party1", "Player-1-A", "Alice")
  Fire(c, "GROUP_ROSTER_UPDATE")
  Die(c, "party1")
  local frame = CardFrame(c)
  local shown = 0
  for i = 3, #frame.textures do
    local tex = frame.textures[i]
    if tex.shown then
      shown = shown + 1
      local g = tex.groups[1]
      Check(g.anims[1].offset[1] == 0 and g.anims[1].offset[2] == 0, "no drift")
      Check(g.anims[4].delay == 0, "no staggering")
      local plays = g.plays
      g.scripts.OnFinished(g)
      Check(g.plays == plays, "no second life")
    end
  end
  Check(shown > 0 and shown < c.R.PartyDeathMist.PIECES, "a quiet subset (no motes) fades in and out: " .. shown)
  Next(c)
end

print("PASSED test_party_death")
