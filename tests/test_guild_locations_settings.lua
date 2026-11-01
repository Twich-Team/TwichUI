dofile(TESTS .. "harness.lua")
-- Guild Locations, M2: the settings page (TwichUI_Settings/pages/GuildLocations.lua). The choice is guildloc/State.lua's
-- alone; the page reads it and changes it only through GL.SetState, has no default for it (so "Reset this page" cannot
-- restore Sharing), and describing or drawing the page writes nothing. The interval is separate from the choice.
dofile(TESTS .. "settings_mock.lua")

local function Row(S, label)
  for _, page in ipairs(S.pages) do
    if page.key == "guildLocations" then
      for _, r in ipairs(page.rows) do if r:GetName() == label then return r end end
    end
  end
end
local function Page(S) for _, p in ipairs(S.pages) do if p.key == "guildLocations" then return p end end end

-- 1. The page exists in the Map group; describing it saved nothing; it starts nothing.
do
  local c, S = SettingsClient()
  local p = Page(S)
  assert(p and p.group == "map" and not p.parent, "a top-level page in the Map group")
  assert(p and Row(S, "Guild Locations") and Row(S, "Update interval while moving"), "both controls are on the page")
  assert(c.TwichUIDB.guildLoc == nil, "the default is not written by describing the page")
  assert(c.TwichUI.GuildLoc.State() == "sharing", "the default state is unchanged")
  local state = S.variables.TWICHUI_guildLocationsState
  assert(state and state.default == nil, "the choice has no default, so a page reset leaves it alone")
  local iv = S.variables.TWICHUI_guildLocationsInterval
  assert(iv and iv.default == 15 and iv.get() == 15)
  local opts = state.options()
  assert(#opts == 3 and opts[1].value == "sharing" and opts[2].value == "invisible" and opts[3].value == "off", "three states")
  local io = iv.options()
  assert(#io == 4 and io[1].value == 10 and io[2].value == 15 and io[3].value == 30 and io[4].value == 60, "four intervals")
  -- reading every row's status text writes nothing
  for _, r in ipairs(Page(S).rows) do
    if r.kind == "status" then
      assert(type(r.value()) == "string" and (r.detail == nil or type(r.detail()) == "string"))
      if r.tone then r.tone() end
    end
  end
  assert(c.TwichUIDB.guildLoc == nil, "drawing the status writes nothing")
end

-- 2. Choosing a state goes through the core (saved, withdrawn); the interval never changes it, and vice versa.
do
  local c, S = SettingsClient()
  local GL = c.TwichUI.GuildLoc
  local state, iv = S.variables.TWICHUI_guildLocationsState, S.variables.TWICHUI_guildLocationsInterval
  local told = {}
  GL.OnChange(function(kind, new) told[#told + 1] = kind .. ":" .. tostring(new) end)
  state:SetValue("invisible")
  assert(GL.State() == "invisible" and c.TwichUIDB.guildLoc.state == "invisible" and state.get() == "invisible")
  assert(told[1] == "state:invisible", "the core's listeners heard it (that is how a withdrawal starts)")
  iv:SetValue(60)
  assert(GL.Interval() == 60 and GL.State() == "invisible", "the interval did not touch the privacy state")
  assert(told[#told] == "interval:60")
  state:SetValue("off")
  assert(GL.State() == "off" and GL.Interval() == 60, "the state did not touch the interval")
  state:SetValue("sharing")
  assert(GL.State() == "sharing" and c.TwichUIDB.guildLoc.interval == 60)
end

-- 3. "Reset this page" puts the interval back and leaves the choice (and the record) alone.
do
  local c, S = SettingsClient()
  local GL, K = c.TwichUI.GuildLoc, S.K
  S.variables.TWICHUI_guildLocationsState:SetValue("off")
  S.variables.TWICHUI_guildLocationsInterval:SetValue(30)
  local n = K.ResetPage("guildLocations")
  assert(n == 1, "only the interval is reset")
  assert(GL.Interval() == 15, "interval back to 15")
  assert(GL.State() == "off" and c.TwichUIDB.guildLoc.state == "off", "the choice stays Off")
  S.variables.TWICHUI_guildLocationsState:SetValue("invisible")
  K.ResetPage("guildLocations")
  assert(GL.State() == "invisible", "and Invisible stays Invisible: a reset never restores Sharing")
  assert(c.TwichUIDB.guildLoc.lastEpoch == nil, "no epoch was spent")
end

-- 4. Held saved data: both controls greyed with a reason, nothing written, the status says why.
do
  local c, S = SettingsClient()
  c.TwichUI.Persist = { IsHeld = function(key) return key == "TwichUIDB" end }
  local choice, interval = Row(S, "Guild Locations"), Row(S, "Update interval while moving")
  assert(not choice:Enabled() and not interval:Enabled(), "both controls are greyed out while held")
  assert(choice:DisabledReason():find("newer version"), choice:DisabledReason())
  local before = c.TwichUIDB.guildLoc
  S.variables.TWICHUI_guildLocationsState:SetValue("sharing")
  S.variables.TWICHUI_guildLocationsInterval:SetValue(10)
  assert(c.TwichUIDB.guildLoc == before and before == nil, "nothing was written")
  local status = Row(S, "Status")
  assert(status.value() == "Inactive" and status.detail():find("newer version"))
end

-- 5. An unusable saved record reads as Invisible and the controls stay usable (choosing replaces it).
do
  local c, S = SettingsClient()
  c.TwichUIDB.guildLoc = { state = "banana" }
  local choice = Row(S, "Guild Locations")
  assert(choice:Enabled() and S.variables.TWICHUI_guildLocationsState.get() == "invisible")
  assert(Row(S, "Your choice").detail():find("could not be read"))
  assert(c.TwichUIDB.guildLoc.state == "banana", "reading it did not rewrite it")
  S.variables.TWICHUI_guildLocationsState:SetValue("sharing")
  assert(c.TwichUIDB.guildLoc.state == "sharing", "the player's choice replaces it")
end

-- 6. Outside a guild a privacy choice can still be made, and the status says there is no one to send to.
do
  local c, S = SettingsClient()
  c.IsInGuild = function() return false end
  S.variables.TWICHUI_guildLocationsState:SetValue("invisible")
  assert(c.TwichUI.GuildLoc.State() == "invisible" and Row(S, "Guild Locations"):Enabled())
  S.variables.TWICHUI_guildLocationsState:SetValue("sharing")
  assert(Row(S, "Status").value() == "Not in a guild" and Row(S, "Status").detail():find("kept"))
end

print("GUILD LOCATIONS SETTINGS TESTS PASSED")
