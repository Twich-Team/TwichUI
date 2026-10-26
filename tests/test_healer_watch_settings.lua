dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Healer Watch in the settings window (TwichUI_Settings/pages/HealerWatch.lua):
--   * the page: where it sits, its four cards (only the first has a switch), its hosted frame after the last card;
--   * Who to watch: the status, the healer picker (automatic, you, the group), a choice that lasts for the session only;
--   * the hosted frame: the inline preview and scenarios, the on-screen preview's buttons, the phrase list and tester,
--     live diagnostics; nothing made again on a redraw;
--   * nothing sent, nothing saved but settings.
-- Stand-in frames keep their scripts, text, focus and shown state; nothing here is the game.

local made = 0
local function Fake(kind, parent)
  made = made + 1
  local f = { kind = kind, parent = parent, scripts = {}, hooks = {}, points = {}, shown = true, w = 0, h = 0,
    text = "", enabled = true, focus = false, events = {}, children = {} }
  if parent and parent.children then table.insert(parent.children, f) end
  local function Fire(self, name, ...)
    if self.scripts[name] then self.scripts[name](self, ...) end
    for _, h in ipairs(self.hooks[name] or {}) do h(self, ...) end
  end
  f.Fire = Fire
  local methods = {
    SetScript = function(s, n, fn) s.scripts[n] = fn; s.hooks[n] = nil end,
    GetScript = function(s, n) return s.scripts[n] end,
    HookScript = function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end,
    SetSize = function(s, w, h) s.w, s.h = w, h end,
    SetWidth = function(s, w) s.w = w end, SetHeight = function(s, h) s.h = h end,
    GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
    SetPoint = function(s, ...) table.insert(s.points, { ... }) end,
    ClearAllPoints = function(s) s.points = {} end,
    Show = function(s) if not s.shown then s.shown = true; Fire(s, "OnShow") end end,
    Hide = function(s) if s.shown then s.shown = false; Fire(s, "OnHide") end end,
    SetShown = function(s, v) if v then s:Show() else s:Hide() end end,
    IsShown = function(s) return s.shown end,
    IsVisible = function(s) local p = s while p do if not p.shown then return false end p = p.parent end return true end,
    SetText = function(s, t) s.text = t == nil and "" or tostring(t) end,
    GetText = function(s) return s.text end,
    GetStringHeight = function() return 12 end, GetStringWidth = function(s) return #s.text * 6 end,
    SetEnabled = function(s, v) s.enabled = v and true or false end,
    IsEnabled = function(s) return s.enabled end,
    SetFocus = function(s) s.focus = true; Fire(s, "OnEditFocusGained") end,
    ClearFocus = function(s) if s.focus then s.focus = false; Fire(s, "OnEditFocusLost") end end,
    HasFocus = function(s) return s.focus end,
    IsMouseOver = function() return false end,
    GetEffectiveScale = function() return 1 end, GetScale = function(s) return s.scale or 1 end,
    GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end, SetFont = function() return true end,
    SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha or 1 end,
    SetScale = function(s, v) s.scale = v end,
    SetTexture = function(s, t) s.texture = t; return true end,
    RegisterEvent = function(s, e) s.events[e] = true end, UnregisterEvent = function(s, e) s.events[e] = nil end,
    RegisterUnitEvent = function(s, e) s.events[e] = true end,
    CreateTexture = function(s) return Fake("Texture", s) end,
    CreateFontString = function(s) return Fake("FontString", s) end,
    CreateAnimationGroup = function(s)
      local g = Fake("AnimationGroup", s)
      g.Play = function(self) self.playing = true end
      g.Stop = function(self) self.playing = false end
      g.CreateAnimation = function() return Fake("Animation", g) end
      return g
    end,
  }
  return setmetatable(f, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end

-- a party of four: you (no role), a tank, a healer and a namesake of the healer from another realm
local GROUP = {
  player = { "Player-1-ME", "Rich", nil, "NONE" },
  party1 = { "Player-1-TANK", "Borin", nil, "TANK" },
  party2 = { "Player-1-HEAL", "Elyndra", nil, "HEALER" },
  party3 = { "Player-2-TWIN", "Elyndra", "Otherrealm", "NONE" },
}
local sent = {}
local function World(c)
  c.CreateFrame = function(kind, name, parent) local f = Fake(kind, parent); if name then c[name] = f end return f end
  c.UIParent = Fake("Frame")
  c.UIParent.w, c.UIParent.h = 1024, 768
  c.GameTooltip = Fake("GameTooltip")
  c.IsInGroup = function() return true end
  c.GetNumSubgroupMembers = function() return 3 end
  c.UnitGUID = function(u) return GROUP[u] and GROUP[u][1] end
  c.UnitName = function(u) if GROUP[u] then return GROUP[u][2], GROUP[u][3] end end
  c.UnitGroupRolesAssigned = function(u) return GROUP[u] and GROUP[u][4] or "NONE" end
  c.SendChatMessage = function() sent[#sent + 1] = "chat" end
end

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local c, S = SettingsClient({ name = "Rich", beforeInit = World })
c.C_ChatInfo.SendAddonMessage = function() sent[#sent + 1] = "addon" end
local R = c.TwichUI
local K, HW, Wt = S.K, R.HealerWatch, R.HealerWatcher
local P = R.HealerWatchPage
local function Flush() for _ = 1, 6 do FlushTimers() end end

---------------------------------------------------------------------------
-- 1. The page and its cards
---------------------------------------------------------------------------
local page
for _, p in ipairs(S.pages) do if p.key == "healerWatch" then page = p end end
Check(page and page.group == "everyday" and page.kind == "hosted" and page.name == "Healer Watch", "a page of its own under Everyday, with a frame of its own")
Check(K.pages.healerWatch.def.icon == "healerWatch" and R.Icons.Get("healerWatch"), "with the flask as its icon")
local sw = S.variables.TWICHUI_healerWatch
Check(sw and sw:GetValue() == false and sw:GetDefaultValue() == false, "off by default")
Check(K.pages.healerWatch.def.hostAfter == "Appearance and testing", "the frame follows the last card")
local cards, primaries = {}, {}
for _, row in ipairs(K.pages.healerWatch.rows) do
  if row.card then cards[#cards + 1] = row.data.name; primaries[#primaries + 1] = row.primary and row.primary.id or "-" end
end
Check(table.concat(cards, "|") == "Who to watch|What to show|When to show|Appearance and testing", "four cards: " .. table.concat(cards, "|"))
Check(table.concat(primaries, "|") == "healerWatch|-|-|-", "only the first has a switch, the feature's own: " .. table.concat(primaries, "|"))
Check(K.rowsById.healerWatchShowName and K.rowsById.healerWatchShowName.ruleOf, "the rest are rules, tucked under Adjust rules")
for _, row in ipairs(K.pages.healerWatch.rows) do
  if row.kind ~= "header" and row.kind ~= "status" then
    local tip = row:GetTooltip()
    Check(type(tip) == "string" and #tip > 20, (row.id or "?") .. " has a tooltip")
  end
end

---------------------------------------------------------------------------
-- 2. Who to watch
---------------------------------------------------------------------------
local pick = S.variables.TWICHUI_healerWatchHealer
local choices = K.rowsById.healerWatchHealer.choices()
local labels = {}
for _, ch in ipairs(choices) do labels[#labels + 1] = ch.label end
Check(table.concat(labels, "|") == "Automatic (the one with the Healer role)|You (Rich)|Borin|Elyndra - Healer role|Elyndra-Otherrealm",
  "automatic, you, and the group, a namesake told apart by realm: " .. table.concat(labels, "|"))
Check(pick:GetValue() == "auto", "automatic to begin with")
local watching = K.rowsById["healerWatch:watching"]
Check(watching and watching.value() == "Elyndra (the one with the Healer role)", "who it watches: " .. tostring(watching and watching.value()))
pick:SetValue("Player-2-TWIN")
Check(Wt.Choice() == "Player-2-TWIN" and watching.value() == "Elyndra (your choice for this session)", "a choice, by identity: " .. watching.value())
Check(not (c.TwichUIDB.ui.healerWatch and c.TwichUIDB.ui.healerWatch.choice) and not tostring(next(c.TwichUIDB.ui.healerWatch or {}) or ""):find("TWIN"),
  "nothing about who heals is saved")
GROUP.party3 = nil
c.GetNumSubgroupMembers = function() return 2 end
labels = {}
for _, ch in ipairs(K.rowsById.healerWatchHealer.choices()) do labels[#labels + 1] = ch.label end
Check(labels[#labels] == "Elyndra (not in your group)" and watching.value() == "Elyndra isn't in your group", "a choice that left says so: " .. watching.value())
pick:SetValue("auto")
Check(Wt.Choice() == "auto", "back to automatic")

---------------------------------------------------------------------------
-- 3. The hosted frame
---------------------------------------------------------------------------
local f = P.Frame()
f.shown = false
f:Show()
Flush()
Check(f.preview.shown and f.phrases.shown and f.diag.shown, "preview, phrases and diagnostics")
Check(f.surface and f.stage.shown and f.surface.name.text == "Elyndra" and f.surface.value.text == "78%", "the inline sample, drawn by the panel's own layout")
f.scenario.onPick("critical")
Flush()
Check(Wt.Scenario() == "critical" and f.surface.value.text == "9%" and f.surface.status.text:find("Critical mana", 1, true), "scenarios")
f.scenario.onPick("drinkChat")
Flush()
Check(f.surface.drink.shown and f.surface.chat.shown and f.surface.status.text:find("Drinking", 1, true), "drinking and chat together")
f.show.scripts.OnClick(f.show)
Flush()
Check(not Wt.PreviewActive(), "the on-screen preview waits for the switch")
R:SetEnabled("healerWatch", true)
Flush()
f.show.scripts.OnClick(f.show)
Flush()
Check(Wt.PreviewActive() and R.HealerDisplay.Frame().mark.shown and f.show.text.text == "Hide", "the on-screen preview, marked")
f.move.scripts.OnClick(f.move)
Flush()
Check(Wt.PositioningActive() and f.move.text.text == "Lock", "moving")
Wt.PreviewStop()
Flush()

-- phrases
local rows = P.Parts().phraseRows
Check(#rows == 3 and rows[1].text.text == "oom" and rows[1].mode.text.text == "Whole words", "the default three phrases")
f.addBox:SetText("Need a drink")
f.addBox.scripts.OnEnterPressed(f.addBox)
Flush()
Check(#HW.Phrases() == 4 and HW.Phrases()[4].text == "need a drink" and rows[4].shown, "a phrase added, cleaned")
rows[4].mode.scripts.OnClick(rows[4].mode)
Flush()
Check(HW.Phrases()[4].mode == "exact" and rows[4].mode.text.text == "Whole message", "its matching switched")
rows[4].remove.scripts.OnClick(rows[4].remove)
Flush()
Check(#HW.Phrases() == 3 and not rows[4].shown, "and removed")
f.testBox:SetText("boom")
f.testBox.scripts.OnTextChanged(f.testBox)
Flush()
Check(f.testResult.text:find("No phrase matches", 1, true), "the tester: boom isn't oom")
f.testBox:SetText("OOM!")
f.testBox.scripts.OnTextChanged(f.testBox)
Flush()
Check(f.testResult.text:find("Matches \"oom\"", 1, true), "the tester: oom! is: " .. f.testResult.text)
Check(#sent == 0, "the tester sends nothing")

-- diagnostics
Check(not f.diagText.shown, "diagnostics are closed to begin with")
f.diagToggle.scripts.OnClick(f.diagToggle)
Flush()
Check(f.diagText.shown and f.diagText.text:find("Selection:", 1, true) and f.diagText.text:find("Panel:", 1, true), "open: the live diagnostics")

local count = made
for _ = 1, 5 do P.Refresh(); Flush() end
Check(made == count, "redrawing makes nothing new: " .. (made - count))
f:Hide()
Check(next(f.events) == nil, "the frame listens for nothing")
R:SetEnabled("healerWatch", false)
Flush()

if failures == 0 then print("PASSED") else print(failures .. " FAILED") end
