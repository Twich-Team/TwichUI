-- Reminders: the optional action button glow (reminders/ButtonGlow.lua) and the glow owners it shares with Action bar
-- glows (glows/Draw.lua). Both features are loaded, as in the game, over a fake world: action slots (Blizzard's bar 1 and
-- EllesmereUI's bar 2), spells and ranks, a macro, combat, auras (secret or not), the Quiet screen. This checks our
-- logic, not the game: the in-game checks are in docs/reminders.md ("Action button glows").
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

---------------------------------------------------------------------------
-- Fake frames: they record what they were told; animation groups count their plays
---------------------------------------------------------------------------
local frames = {}
local Methods
local function Fake(kind)
  local o = { kind = kind, shown = kind ~= "Frame" and kind ~= "Button", scripts = {}, events = {}, unitEvents = {}, points = {}, attrs = {},
    alpha = 1, scale = 1, w = 36, h = 36, level = 5, children = {} }
  frames[#frames + 1] = o
  return setmetatable(o, { __index = function(_, k)
    if Methods[k] then return Methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end
local function Anim()
  local a = Fake("anim")
  a.playing, a.plays = false, 0
  a.CreateAnimation = function(self) local x = Fake("animation"); x.group = self; return x end
  a.Play = function(self) self.playing = true; self.plays = self.plays + 1 end
  a.Stop = function(self) self.playing = false end
  a.Finish = function(self) self.playing = false; if self.scripts.OnFinished then self.scripts.OnFinished(self) end end
  a.IsPlaying = function(self) return self.playing end
  return a
end
Methods = {
  Show = function(s) s.shown = true end, Hide = function(s) s.shown = false end,
  IsShown = function(s) return s.shown end, SetShown = function(s, v) s.shown = v and true or false end,
  IsVisible = function(s) return s.shown end,
  SetScript = function(s, n, fn) s.scripts[n] = fn end, GetScript = function(s, n) return s.scripts[n] end,
  HookScript = function(s, n, fn) s.scripts[n] = s.scripts[n] or fn end,
  RegisterEvent = function(s, e) s.events[e] = true end,
  RegisterUnitEvent = function(s, e, u) s.events[e] = true; s.unitEvents[e] = u end,
  UnregisterEvent = function(s, e) s.events[e] = nil; s.unitEvents[e] = nil end,
  UnregisterAllEvents = function(s) s.events = {}; s.unitEvents = {} end,
  IsEventRegistered = function(s, e) return s.events[e] == true end,
  CreateTexture = function(s) local t = Fake("texture"); t.parent = s; s.children[#s.children + 1] = t; return t end,
  CreateFontString = function(s) local t = Fake("font"); t.parent = s; return t end,
  CreateAnimationGroup = function(s) local a = Anim(); a.parent = s; return a end,
  SetText = function(s, v) s.text = v end, GetText = function(s) return s.text end,
  GetStringWidth = function(s) return #(s.text or "") * 8 end, GetStringHeight = function(s) return s.fontSize or 18 end,
  SetPoint = function(s, ...) s.points[#s.points + 1] = { ... } end, ClearAllPoints = function(s) s.points = {}; s.allPoints = nil end,
  SetSize = function(s, w, h) s.w, s.h = w, h end, SetWidth = function(s, w) s.w = w end, SetHeight = function(s, h) s.h = h end,
  GetWidth = function(s) return s.allPoints and s.allPoints:GetWidth() or s.w end, GetHeight = function(s) return s.allPoints and s.allPoints:GetHeight() or s.h end,
  SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha end,
  SetScale = function(s, v) s.scale = v end, GetEffectiveScale = function() return 1 end,
  SetFrameLevel = function(s, l) s.level = l end, GetFrameLevel = function(s) return s.level end,
  SetFrameStrata = function(s, v) s.strata = v end, EnableMouse = function(s, v) s.mouse = v and true or false end,
  SetAtlas = function(s, a) s.atlas = a end, SetTexture = function(s, p) s.texture = p; return true end,
  SetTexCoord = function(s, ...) s.coords = { ... } end,
  SetAllPoints = function(s, target) s.allPoints = target end,
  SetVertexColor = function(s, r, g, b) s.color = { r, g, b } end, SetColorTexture = function(s, r, g, b) s.color = { r, g, b } end,
  SetTextColor = function(s, r, g, b) s.color = { r, g, b } end,
  SetFont = function(s, path, size, flags) s.font = { path, size, flags }; s.fontSize = size; return true end,
  StartMoving = function(s) s.moving = true end, StopMovingOrSizing = function(s) s.moving = false end,
  GetAttribute = function(s, k) return s.attrs[k] end, SetAttribute = function(s, k, v) s.attrs[k] = v end,
}
c.CreateFrame = function(kind, name, parent)
  local f = Fake(kind)
  f.name, f.parent = name, parent
  if name then c[name] = f end
  return f
end
c.UIParent = Fake("UIParent")
c.UIParent.w, c.UIParent.h = 1024, 768
c.C_Texture = { GetAtlasInfo = function()
  return { leftTexCoord = 0.1, rightTexCoord = 0.9, topTexCoord = 0.2, bottomTexCoord = 0.8 }
end }
c.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
c.Enum = { PowerType = { ComboPoints = 4, Mana = 0 }, ItemClass = { Weapon = 2, Armor = 4 }, ItemArmorSubclass = { Shield = 6 },
  ItemWeaponSubclass = { Fishingpole = 20 }, SpellBookSpellBank = { Player = 0 } }

local SECRET_MT = { __lt = function() error("compared a secret value") end, __le = function() error("compared a secret value") end,
  __eq = function() error("compared a secret value") end, __concat = function() error("formatted a secret value") end,
  __index = function() error("indexed a secret value") end }
local secrets = setmetatable({}, { __mode = "k" })
c.issecretvalue = function(v) return type(v) == "table" and secrets[v] == true end
local function Secret() local s = setmetatable({}, SECRET_MT); secrets[s] = true; return s end

local NOW = 1000
c.GetTime = function() return NOW end

---------------------------------------------------------------------------
-- The world: a shaman
---------------------------------------------------------------------------
local SPELLS = {
  [403] = { "Lightning Bolt", 1 }, [529] = { "Lightning Bolt", 2 }, [324] = { "Lightning Shield", 1 },
  [8042] = { "Earth Shock", 1 }, [51530] = { "Maelstrom Weapon" }, [5730] = { "Stoneclaw Totem", 1 },
}
local G
local function World()
  G = { class = "SHAMAN", known = { [403] = true, [529] = true, [324] = true, [8042] = true }, auras = {}, combat = false,
    slots = {}, secretAuras = false, cooldowns = {} }
end
World()
c.UnitClass = function(u) if u == "player" then return G.class, G.class end end
c.UnitClassBase = function() return G.class end
c.UnitName = function(u) if u == "player" then return "Rich" end end
c.GetRealmName = function() return "Forever" end
c.InCombatLockdown = function() return G.combat end
c.UnitAffectingCombat = function() return G.combat end
c.IsResting = function() return false end
c.UnitIsDeadOrGhost = function() return false end
c.UnitIsGhost = function() return false end
c.UnitOnTaxi = function() return false end
c.IsMounted = function() return false end
c.IsInInstance = function() return false, "none" end
c.UnitExists = function(u) return u == "player" end
c.UnitCanAttack = function() return false end
c.UnitIsDead = function() return false end
c.IsInRaid = function() return false end
c.IsInGroup = function() return false end
c.UnitIsUnit = function(a, b) return a == b end
c.UnitPower = function() return 0 end
c.GetInventoryItemID = function() return nil end
c.C_SpellBook = {
  IsSpellKnown = function(id) return G.known[id] == true end,
  GetNumSpellBookSkillLines = function() return 1 end,
  GetSpellBookSkillLineInfo = function() local n = 0 for _ in pairs(G.known) do n = n + 1 end return { itemIndexOffset = 0, numSpellBookItems = n } end,
  GetSpellBookItemInfo = function(i)
    local ids = {}
    for id in pairs(G.known) do ids[#ids + 1] = id end
    table.sort(ids)
    local id = ids[i]
    local s = id and SPELLS[id]
    if not s then return nil end
    return { spellID = id, name = s[1], subName = s[2] and ("Rank " .. s[2]) or "", isPassive = false }
  end,
}
c.C_Spell = {
  GetSpellName = function(id) local s = SPELLS[id]; return s and s[1] end,
  GetSpellSubtext = function(id) local s = SPELLS[id]; return s and s[2] and ("Rank " .. s[2]) or nil end,
  GetSpellTexture = function(id) return SPELLS[id] and (100000 + id) or nil end,
  GetSpellCooldown = function() return { isEnabled = true, isActive = false, startTime = 0, duration = 0 } end,
  IsSpellUsable = function() return false, false end,
  IsSpellInRange = function() return true end,
}
c.C_Secrets = { ShouldAurasBeSecret = function() return G.secretAuras end }
-- auras: { spellId, applications }
c.C_UnitAuras = {
  GetAuraDataByIndex = function(u, i)
    if G.secretAuras then return Secret() end
    if u ~= "player" then return nil end
    local a = G.auras[i]
    if a then return { name = SPELLS[a[1]] and SPELLS[a[1]][1] or "?", spellId = a[1], applications = a[2], duration = 0, expirationTime = 0 } end
  end,
}
c.C_Item = {
  GetItemCount = function() return 0 end, GetItemNameByID = function() return nil end,
  GetItemInfoInstant = function() return nil end, GetItemIconByID = function() return nil end,
  RequestLoadItemDataByID = function() end,
}
c.C_PaperDollInfo = { GetTemporaryEnchantmentInfo = function() return nil end }
c.C_Minimap = { GetNumTrackingTypes = function() return 0 end, GetTrackingInfo = function() return nil end }
c.GetNumShapeshiftForms = function() return 0 end
-- action slots: slot -> { "spell", id } | { "macro", id, spell }
c.GetActionInfo = function(slot) local s = G.slots[slot]; if s then return s[1], s[2] end end
c.GetMacroSpell = function(id) for _, s in pairs(G.slots) do if s[1] == "macro" and s[2] == id then return s[3] end end end
c.GetMacroItem = function() return nil end
c.PlaySoundFile = function() return true end
-- nothing may ever act for the player
local acted = {}
for _, name in ipairs({ "CastSpellByName", "CastSpellByID", "UseAction", "UseItemByName", "SendChatMessage", "TargetUnit",
  "PickupAction", "PlaceAction", "PickupSpell", "SetBinding", "ClearOverrideBindings" }) do
  c[name] = function() acted[#acted + 1] = name end
end

local function Fire(event, ...)
  c.FireEvent(event, ...)
  local arg1 = ...
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent and (not f.unitEvents[event] or f.unitEvents[event] == arg1) then
      f.scripts.OnEvent(f, event, ...)
    end
  end
end
local function Settle() for _ = 1, 6 do FlushTimers() end end

-- Buttons: Blizzard's bar 1 (slots 1-12) and EllesmereUI's bar 2 (EABButton61-72, the slot in its attribute)
local function Button(name, slot, attr)
  local b = Fake("CheckButton")
  b.shown, b.name = true, name
  if attr then b.attrs.action = slot else b.action = slot end
  c[name] = b
  return b
end
local AB, EAB = {}, {}
for i = 1, 12 do AB[i] = Button("ActionButton" .. i, i) end
for i = 0, 11 do EAB[i + 1] = Button("EABButton" .. (61 + i), 61 + i, true) end
local function Slots(t)
  G.slots = {}
  for k, v in pairs(t) do G.slots[k] = v end
end
-- Lightning Bolt rank 1 on button 1, rank 2 on button 3, a macro casting it on EllesmereUI's first button; Lightning Shield on 2
Slots({ [1] = { "spell", 403 }, [2] = { "spell", 324 }, [3] = { "spell", 529 }, [4] = { "spell", 8042 }, [61] = { "macro", 7, 403 } })

for _, f in ipairs({ "QuietScreen.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/Media.lua", "Icons.lua",
  "chronicle/Style.lua", "Look.lua", "FrameLook.lua", "modules/Notify.lua", "modules/NotifyLook.lua", "modules/Arrival.lua",
  "reminders/AmmoItems.lua", "reminders/ArtData.lua", "artwork/Catalog.lua", "reminders/Config.lua", "reminders/Gallery.lua", "reminders/Conditions.lua",
  "reminders/Ammunition.lua", "reminders/Evaluate.lua", "reminders/State.lua", "reminders/Auras.lua", "reminders/Display.lua",
  "reminders/ButtonGlow.lua", "reminders/Controller.lua",
  "glows/Catalog.lua", "glows/Config.lua", "glows/Logic.lua", "glows/Buttons.lua", "glows/State.lua", "glows/Draw.lua",
  "glows/Notice.lua", "glows/Controller.lua", "setup/TwichConfig.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local RM, CT, D, GW, RD = R.Reminders, R.ReminderController, R.BarGlowDraw, R.ReminderGlow, R.ReminderDisplay
local BG, BCT, BT, Q = R.BarGlows, R.BarGlowController, R.BarGlowButtons, R.QuietScreen
local OnUpdates = 0
for _, f in ipairs(frames) do if f.scripts.OnUpdate then OnUpdates = OnUpdates + 1 end end

local function Lit(b) return D.IsShown(b) end
local function Owner(b) return D.WinnerOf(b) end
local function Mine(b) return D.IsGlowing(b, "reminders") end
local function LitCount() local n = 0 for _ in pairs(D.Owned("reminders")) do n = n + 1 end return n end
local function Overlay(b) for _, f in ipairs(frames) do if f.parent == b and f.inner then return f end end end
local function Shown(id) local f = RD.Frame(id) return f ~= nil and f.shown end

-- A reminder made the way the editor makes one: "Player is in combat", turned on, with a glow on Lightning Bolt.
local function Combat(name, spell, extra)
  local ok, id = RM.Create("custom")
  assert(ok, id)
  RM.SetName(id, name)
  RM.AddCondition(id, "player")
  if spell then RM.SetGlow(id, "spell", spell); RM.SetGlow(id, "enabled", true) end
  for k, v in pairs(extra or {}) do RM.SetGlow(id, k, v) end
  return id
end
local function Fight(on)
  G.combat = on
  Fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
  Settle()
end

---------------------------------------------------------------------------
-- 1. What is stored: optional, checked, normalized; reading never writes
---------------------------------------------------------------------------
c.TwichUIDB.modules.barGlows = false   -- Action bar glows off: Reminders' glows must not need it
c.TwichUIDB.ui = { reminders = { version = 1, nextId = 3, list = {
  { id = "r1", name = "Old reminder", enabled = false, match = "all", conditions = { { type = "player", state = "combat" } },
    display = { mode = "text", text = "Old" }, place = { preset = "belowCenter" } },
  { id = "r2", name = "Broken glow", enabled = false, match = "all", conditions = { { type = "player", state = "combat" } },
    display = { mode = "text", text = "Hi" }, place = { preset = "belowCenter" },
    glow = { enabled = "yes", spell = -4, look = "laser", color = "red", motion = 7 } },
} } }
RM.Invalidate()
local old, broken = RM.Get("r1"), RM.Get("r2")
Check(old.valid and old.glow and old.glow.enabled == false and old.glow.on == false, "an existing reminder loads with no glow")
Check(c.TwichUIDB.ui.reminders.list[1].glow == nil, "reading added nothing to the saved reminder")
Check(broken.valid and broken.glow.on == false and broken.glow.look == "proc" and broken.glow.color == RM.GLOW_DEFAULTS.color
  and broken.glow.motion == "moving" and broken.glow.spell == nil, "unusable glow values read as defaults; the reminder stays valid")
Check(c.TwichUIDB.ui.reminders.list[2].glow.look == "laser", "and the stored values are left as they were")
c.TwichUIDB.ui.reminders.list[2].glow = "a string"
RM.Invalidate()
Check(RM.Get("r2").valid and RM.Get("r2").glow.on == false, "a glow that isn't a table: no glow, no problem")
Check(not RM.SetGlow("r1", "look", "laser") and not RM.SetGlow("r1", "spell", 1.5) and not RM.SetGlow("r1", "color", "red")
  and not RM.SetGlow("r1", "enabled", "yes") and not RM.SetGlow("r1", "size", 100), "bad values and unknown keys are refused")
Check(RM.SetGlow("r1", "enabled", true) and RM.Get("r1").valid and RM.Get("r1").glow.enabled and not RM.Get("r1").glow.on,
  "turned on without a spell: valid, but nothing glows")
Check(RM.SetEnabled("r1", true), "a glow without a spell never stops the reminder being turned on")
RM.SetEnabled("r1", false)
Check(RM.SetGlow("r1", "spell", 403) and RM.Get("r1").glow.on, "with a spell it is on")
Check(RM.SetGlow("r1", "spell", nil) and RM.Get("r1").glow.spell == nil, "the spell can be cleared")
for _, choice in ipairs(RM.GLOW_CHOICES.look) do
  local known = false
  for _, l in ipairs(BG.LOOKS) do if l[1] == choice[1] then known = true end end
  Check(known, "the look " .. choice[1] .. " is one Draw.lua draws")
end
c.TwichUIDB.ui.reminders = nil
RM.Invalidate()

---------------------------------------------------------------------------
-- 2. Live: shows with the reminder, every rank and the macro; goes with it. Action bar glows is off.
---------------------------------------------------------------------------
c.FireEvent("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD"); Settle()
Check(not BCT.running, "Action bar glows is off")
local bolt = Combat("Bolt", 403)
Check(GW.Snapshot().events == 0, "a reminder that isn't showing: no bar events listened for")
RM.SetEnabled(bolt, true)
Check(not Shown(bolt) and LitCount() == 0, "out of combat: nothing")
Fight(true)
Check(Shown(bolt), "in combat: the reminder shows")
Check(Mine(AB[1]) and Mine(AB[3]) and Mine(EAB[1]) and not Lit(AB[2]) and not Lit(AB[4]),
  "rank 1, rank 2 and the macro casting it glow; other buttons don't")
Check(LitCount() == 3 and CT.Snapshot().glowing == 3, "three buttons, as the diagnostics count says")
Check(GW.Snapshot().events > 0, "while it glows, bar events are listened for")
local o1 = Overlay(AB[1])
Check(o1 and o1.flip and o1.flip.tex.atlas == "UI-HUD-ActionBar-Proc-Loop-Flipbook" and o1.flip.group.playing, "the spell alert look, running")
Fight(false)
Check(not Shown(bolt) and LitCount() == 0 and not Lit(AB[1]) and not Lit(EAB[1]), "out of combat: the reminder and its glows go")
Check(GW.Snapshot().events == 0, "and nothing is listened for any more")

---------------------------------------------------------------------------
-- 3. Delay and minimum
---------------------------------------------------------------------------
RM.SetDisplay(bolt, "delay", 3)
Fight(true)
Check(not Shown(bolt) and not Lit(AB[1]) and CT.Status(bolt) == "pending", "with a delay: neither the reminder nor its glow yet")
NOW = NOW + 3; RunLongTimers(5); Settle()
Check(Shown(bolt) and Mine(AB[1]), "after the delay: both")
RM.SetDisplay(bolt, "delay", 0)
RM.SetDisplay(bolt, "minShow", 10)
Fight(false)
Check(Shown(bolt) and Mine(AB[1]) and CT.Status(bolt) == "holding", "kept up for its minimum: the glow too")
NOW = NOW + 11; RunLongTimers(15); Settle()
Check(not Shown(bolt) and not Lit(AB[1]), "the minimum over: both go")
Fight(true); Fight(false)
Check(Mine(AB[1]) and CT.Status(bolt) == "holding", "holding again")
RM.SetEnabled(bolt, false)
Check(not Lit(AB[1]) and LitCount() == 0, "turned off during its minimum: the glow goes at once")
NOW = NOW + 20; RunLongTimers(30); Settle()
Check(not Lit(AB[1]), "the old timer can't bring it back")
RM.SetDisplay(bolt, "minShow", 0)
RM.SetEnabled(bolt, true)

---------------------------------------------------------------------------
-- 4. A setting changed while it glows: drawn again, nothing decided again; no restart for the same look
---------------------------------------------------------------------------
Fight(true)
local refreshes, decisions = CT.Snapshot().refreshes, CT.Snapshot().decisions
local made = D.made
local plays = o1.flip.group.plays
RM.SetGlow(bolt, "color", "ff40a0ff")
Check(o1.flip.tex.color[3] == 1 and math.abs(o1.flip.tex.color[1] - 0x40 / 255) < 0.01 and math.abs(o1.flip.tex.color[2] - 0xa0 / 255) < 0.01, "a new color, at once")
Check(CT.Snapshot().refreshes == refreshes and CT.Snapshot().decisions == decisions, "nothing decided again for a glow setting")
plays = o1.flip.group.plays
Fire("SPELLS_CHANGED"); Settle()
Check(o1.flip.group.plays == plays and D.made == made, "the same look again: no new frame, the animation is not restarted")
RM.SetGlow(bolt, "look", "pixel")
Check(not o1.flip.tex.shown and o1.lines and o1.lines[1].shown, "another look on the same overlay")
-- Every look uses the button's own bounds at 100%, including rectangular EllesmereUI buttons.
-- Anchors follow later button resizes without restarting the animation or allocating frames.
for _, button in ipairs({ AB[1], EAB[1] }) do
  local overlay = Overlay(button)
  local oldW, oldH = button.w, button.h
  for _, look in ipairs({ "proc", "ants", "soft", "pixel" }) do
    RM.SetGlow(bolt, "look", look)
    for _, motion in ipairs({ "still", "breathing", "moving" }) do
      RM.SetGlow(bolt, "motion", motion)
      local beforePlays = overlay.flip and overlay.flip.group.plays
      local beforeMade = D.made
      for _, size in ipairs({ { 24, 24 }, { 48, 32 }, { 36, 36 } }) do
        button:SetSize(size[1], size[2])
        Check(overlay:GetWidth() == size[1] and overlay:GetHeight() == size[2],
          look .. "/" .. motion .. " stays within the resized button")
      end
      Check(D.made == beforeMade and (not overlay.flip or overlay.flip.group.plays == beforePlays),
        "resizing reuses the overlay without restarting its animation")
      if look == "proc" or look == "ants" then
        local coords = overlay.flip.tex.coords
        local moving = motion == "moving"
        Check(coords and math.abs(coords[2] - (moving and 0.9 or 0.26)) < 0.001
          and math.abs(coords[4] - (moving and 0.8 or 0.3)) < 0.001,
          look .. "/" .. motion .. " uses the full flipbook only while moving")
      end
    end
  end
  button:SetSize(oldW, oldH)
end
RM.SetGlow(bolt, "motion", "moving")
RM.SetGlow(bolt, "look", "proc"); RM.SetGlow(bolt, "color", RM.GLOW_DEFAULTS.color)
RM.SetGlow(bolt, "enabled", false)
Check(Shown(bolt) and not Lit(AB[1]), "glow turned off: the reminder stays, the glow goes")
RM.SetGlow(bolt, "enabled", true)
Check(Mine(AB[1]), "turned on again while it shows: back")

---------------------------------------------------------------------------
-- 5. Bars change: spells moved, a page switched, a macro edited
---------------------------------------------------------------------------
Slots({ [5] = { "spell", 403 }, [2] = { "spell", 324 }, [4] = { "spell", 8042 }, [61] = { "macro", 7, 403 } })
Fire("ACTIONBAR_SLOT_CHANGED", 1); Fire("ACTIONBAR_SLOT_CHANGED", 5)
Check(Mine(AB[1]), "before the coalesced look nothing moves")
Settle()
Check(not Lit(AB[1]) and not Lit(AB[3]) and Mine(AB[5]) and Mine(EAB[1]), "moved to button 5: the glow follows")
-- EllesmereUI pages its bar: the button now shows another slot
EAB[1].attrs.action = 73
Fire("ACTIONBAR_PAGE_CHANGED"); Settle()
Check(not Lit(EAB[1]), "page switched away: that button no longer glows")
EAB[1].attrs.action = 61
Fire("ACTIONBAR_PAGE_CHANGED"); Settle()
Check(Mine(EAB[1]), "paged back: it glows again")
G.slots[61] = { "macro", 7, 8042 }
Fire("UPDATE_MACROS"); Settle()
Check(not Lit(EAB[1]), "the macro edited to cast something else: no glow")
Slots({ [1] = { "spell", 403 }, [2] = { "spell", 324 }, [3] = { "spell", 529 }, [4] = { "spell", 8042 }, [61] = { "macro", 7, 403 } })
Fire("ACTIONBAR_SLOT_CHANGED", 1); Fire("UPDATE_MACROS"); Settle()
Check(Mine(AB[1]) and Mine(AB[3]) and Mine(EAB[1]) and not Lit(AB[5]), "back as it was")
Fight(false)

---------------------------------------------------------------------------
-- 6. A spell on no button; a spell the game doesn't know
---------------------------------------------------------------------------
local totem = Combat("Totem", 5730)
RM.SetEnabled(totem, true)
Fight(true)
Check(Shown(totem) and GW.Buttons(5730) == 0, "a spell on no button: the reminder shows all the same")
Check(GW.Buttons(403) == 3 and GW.Buttons(999999) == nil and GW.Buttons(nil) == nil, "the editor's count: 3, unknown, none")
Fight(false)
RM.Delete(totem)

---------------------------------------------------------------------------
-- 7. Two reminders on one button: the first in the list gives the look; the second takes over without a gap
---------------------------------------------------------------------------
local second = Combat("Second", 403, { color = "ff20ff20", look = "soft" })
RM.SetEnabled(second, true)
Fight(true)
Check(Shown(bolt) and Shown(second) and Mine(AB[1]) and LitCount() == 3, "both show; one request per button")
Check(o1.flip.tex.shown and not (o1.soft and o1.soft.shown), "the first reminder's look shows")
local made2 = D.made
RM.SetEnabled(bolt, false)
Check(Mine(AB[1]) and o1.soft and o1.soft.shown and not o1.flip.tex.shown and D.made == made2, "the first goes: the second's look, on the same overlay")
RM.SetEnabled(bolt, true)
Check(o1.flip.tex.shown, "back: the first again")
RM.Delete(second)
Check(Mine(AB[1]) and o1.flip.tex.shown and LitCount() == 3, "the second deleted: the first stays")
Fight(false)

---------------------------------------------------------------------------
-- 8. Quiet screen and preview
---------------------------------------------------------------------------
Fight(true)
Q.Set(true)
Check(Shown(bolt) == false and not Lit(AB[1]) and CT.Status(bolt) == "showing", "quiet: the reminder and its glow are held back, still decided")
Q.Set(false)
Check(Mine(AB[1]), "quiet over: the glow comes back")
Fight(false)
RM.SetEnabled(bolt, false)
Check(RD.PreviewStart(RM.Get(bolt)) and Mine(AB[1]), "a preview of a reminder that is off shows its glow on the bars")
Check(CT.Status(bolt) == "disabled" and not RM.Get(bolt).enabled, "and changes nothing about it")
Q.Set(true)
Check(Mine(AB[1]), "a preview ignores the Quiet screen")
Q.Set(false)
RD.PreviewStop()
Check(not Lit(AB[1]) and GW.Snapshot().events == 0, "preview over: gone, nothing listened for")
RM.SetEnabled(bolt, true)

---------------------------------------------------------------------------
-- 9. Unknown is never a match: Maelstrom Weapon at 5 stacks, with auras readable and hidden
---------------------------------------------------------------------------
local ok, mw = RM.Create("custom")
RM.SetName(mw, "Maelstrom")
RM.AddCondition(mw, "aura", nil, { type = "aura", spells = { 51530 }, harmful = false, what = "stacks", compare = "atLeast", stacks = 5 })
RM.SetGlow(mw, "spell", 403); RM.SetGlow(mw, "enabled", true)
Check(RM.SetEnabled(mw, true), "the Maelstrom reminder turns on")
G.auras = { { 51530, 4 } }; Fire("UNIT_AURA", "player"); Settle()
Check(not Shown(mw) and not Lit(AB[1]), "4 stacks: nothing")
G.auras = { { 51530, 5 } }; Fire("UNIT_AURA", "player"); Settle()
Check(Shown(mw) and Mine(AB[1]), "5 stacks, readable: shows and glows")
G.secretAuras = true; Fire("UNIT_AURA", "player"); Settle()
Check(not Shown(mw) and not Lit(AB[1]) and CT.Status(mw) == "waiting", "auras hidden from addons: unknown, never a match; the glow goes")
G.secretAuras = false; G.auras = {}; Fire("UNIT_AURA", "player"); Settle()
RM.Delete(mw)

---------------------------------------------------------------------------
-- 10. Sharing: the glow goes with the reminder; a bad one is refused whole; an older sender's arrives without one
---------------------------------------------------------------------------
RM.SetGlow(bolt, "look", "ants")
local p = RM.Export(bolt)
Check(p and p.glow and p.glow.spell == 403 and p.glow.enabled == true and p.glow.look == "ants", "the export carries the glow")
local okA, got = RM.Admit(p)
Check(okA and RM.Get(got).glow.on and RM.Get(got).glow.look == "ants" and not RM.Get(got).enabled, "admitted with its glow, turned off")
RM.Delete(got)
local bad = RM.DeepCopy(p); bad.glow.look = "laser"
Check(not RM.Admit(bad), "an unusable glow look: refused")
bad = RM.DeepCopy(p); bad.glow.spell = "403"
Check(not RM.Admit(bad), "a spell that isn't an ID: refused")
bad = RM.DeepCopy(p); bad.glow = 7
Check(not RM.Admit(bad), "a glow that isn't a table: refused")
local older = RM.DeepCopy(p); older.glow = nil
local okO, gotO = RM.Admit(older)
Check(okO and RM.Get(gotO).glow.on == false and c.TwichUIDB.ui.reminders.list[#c.TwichUIDB.ui.reminders.list].glow == nil, "from an older TwichUI: no glow")
RM.Delete(gotO)
local plain = Combat("Plain", nil)
Check(RM.Export(plain).glow == nil, "a reminder never given a glow exports none")
RM.Delete(plain)
local okD, dup = RM.Duplicate(bolt)
Check(okD and RM.Get(dup).glow.spell == 403 and RM.Get(dup).glow.look == "ants", "a duplicate keeps the glow")
RM.Delete(dup)
RM.SetGlow(bolt, "look", "proc")

---------------------------------------------------------------------------
-- 11. With Action bar glows: one overlay, the reminder's look first, neither clears the other
---------------------------------------------------------------------------
c.TwichUIDB.modules.barGlows = true
BCT.Refresh(); Settle()
Check(BCT.running and D.IsGlowing(AB[2], "barGlows") and Owner(AB[2]) == "barGlows", "Action bar glows: Lightning Shield is missing, its button glows")
local shield = Combat("Shield", 324, { look = "pixel", color = "ff2080ff" })
RM.SetEnabled(shield, true)
local made3 = D.made
Fight(true)
Check(D.IsGlowing(AB[2], "barGlows") and Mine(AB[2]) and Owner(AB[2]) == "reminders" and D.made == made3, "both want it: one overlay, the reminder's look")
local o2 = Overlay(AB[2])
Check(o2.lines and o2.lines[1].shown and not (o2.soft and o2.soft.shown) and not (o2.flip and o2.flip.tex.shown), "only the reminder's look is drawn")
G.auras = { { 324, 1 } }; Fire("UNIT_AURA", "player"); Settle()
Check(not D.IsGlowing(AB[2], "barGlows") and Mine(AB[2]), "Action bar glows lets go (Lightning Shield cast): the reminder's glow stays")
G.auras = {}; Fire("UNIT_AURA", "player"); Settle()
c.TwichUIDB.modules.barGlows = false
BCT.Refresh(); Settle()
Check(not BCT.running and Mine(AB[2]) and Mine(AB[1]), "Action bar glows switched off: the reminders' glows stay")
c.TwichUIDB.modules.barGlows = true
BCT.Refresh(); Settle()
Fight(false)
Check(not Mine(AB[2]) and D.IsGlowing(AB[2], "barGlows") and Owner(AB[2]) == "barGlows" and o2.flip and o2.flip.tex.shown and not o2.lines[1].shown,
  "the reminder goes: Action bar glows' own look is back")
-- faded bars: a button lit by a reminder is not faded
BG.SetFaded("bar1", true); Settle()
-- (button 1 glows for Action bar glows too: it holds Lightning Bolt at a lower rank than the one known)
Check(AB[1].alpha == 1 and AB[2].alpha == 1 and math.abs(AB[3].alpha - 0.5) < 0.001 and math.abs(AB[4].alpha - 0.5) < 0.001,
  "faded bar: Action bar glows' buttons in full, the rest faded")
Fight(true)
Check(AB[3].alpha == 1 and math.abs(AB[4].alpha - 0.5) < 0.001, "a reminder lights button 3: not faded; button 4 still is")
Fight(false)
Check(math.abs(AB[3].alpha - 0.5) < 0.001, "the reminder goes: faded again")
BG.SetFaded("bar1", false); Settle()
Check(AB[3].alpha == 1 and AB[4].alpha == 1, "not faded any more: alpha back")

-- Reminders switched off while Action bar glows runs: only the reminders' glows go
Fight(true)
R:SetEnabled("reminders", false)
CT.Refresh()
Check(LitCount() == 0 and not Shown(bolt) and D.IsGlowing(AB[2], "barGlows") and Lit(AB[2]), "Reminders off: its glows go, Action bar glows' stays")
Check(GW.Snapshot().events == 0, "and Reminders listens for no bar event")
R:SetEnabled("reminders", true)
CT.Refresh(); Settle()
Check(Mine(AB[1]), "Reminders on again in combat: back")
Fight(false)
RM.Delete(shield)

---------------------------------------------------------------------------
-- 12. Deleted, a profile change (another profile's reminder with the same id), the settings sample
---------------------------------------------------------------------------
Fight(true)
Check(Mine(AB[1]), "showing")
local store = c.TwichUIDB.ui.reminders
c.TwichUIDB.ui.reminders = { version = 1, nextId = 2, list = {
  { id = bolt, name = "Other profile", enabled = true, match = "all", conditions = { { type = "player", state = "combat" } },
    display = { mode = "text", text = "Other" }, place = { preset = "belowCenter" } } } }
RM.Invalidate(); Settle()
Check(not Mine(AB[1]) and LitCount() == 0, "a profile whose reminder (same id) has no glow: nothing glows for Reminders")
c.TwichUIDB.ui.reminders = store
RM.Invalidate(); Settle()
Check(Mine(AB[1]), "back to the first profile: its glow again")
RM.Delete(bolt)
Check(LitCount() == 0 and not Mine(AB[1]) and not Lit(EAB[1]) and not Lit(AB[3]), "deleted while it glows: gone at once")
Fight(false)
local sample = c.CreateFrame("Frame")
GW.Sample(sample, RM.ReadGlow({ enabled = true, spell = 403, look = "soft" }))
Check(D.IsGlowing(sample, "reminderSample") and Lit(sample) and LitCount() == 0, "the editor's sample glows on its own frame, not a button")
BCT.Refresh(); Settle()
Check(Lit(sample), "Action bar glows' drawing doesn't clear the sample")
GW.Sample(sample, nil)
Check(not Lit(sample), "sample stopped")
-- Action bar glows still honors its explicit size setting when reusing a default-size overlay.
local sized = BG.Style("proc", "overpower")
local custom = {}
for k, v in pairs(sized) do custom[k] = v end
custom.size = 140
D.Set(sample, custom)
local sizedOverlay = Overlay(sample)
Check(sizedOverlay:GetWidth() == sample:GetWidth() * 1.4, "an explicit larger size is honored")
custom.size = 100
D.Set(sample, custom)
Check(sizedOverlay:GetWidth() == sample:GetWidth(), "resetting the size restores button bounds")
D.Clear(sample)


---------------------------------------------------------------------------
-- 13. Never acts; no per-frame Lua
---------------------------------------------------------------------------
Check(#acted == 0, "nothing was cast, used, picked up or placed: " .. table.concat(acted, ", "))
local n = 0
for _, f in ipairs(frames) do if f.scripts.OnUpdate then n = n + 1 end end
Check(n == OnUpdates, "no OnUpdate added")
local toc = io.open(ROOT .. "!!!TwichUI.toc"):read("*a")
Check(toc:find("reminders\\ButtonGlow.lua", 1, true) and toc:find("reminders\\ButtonGlow.lua", 1, true) < toc:find("reminders\\Controller.lua", 1, true),
  "the .toc lists ButtonGlow.lua before the controller")

if failures == 0 then print("PASSED") else print(failures .. " FAILED") end
