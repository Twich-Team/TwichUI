-- A client for the layout wizard's tests (test_layout_wizard.lua): TwichUI with its features, a stand-in EllesmereUI with
-- the real functions' shape (EllesmereUI_Profiles.lua, 9.6.8), stand-in frames that keep their size, points, text, colours,
-- scripts, events and shown state, and the two layout addons loaded on demand from their own .toc files, as the game does:
-- TwichUI_Layouts (the engine) and TwichUI_LayoutWizard (the window; it requires the engine).
--
-- LM.Boot(name, sv, opts) -> c, S (S: the settings client's own view of the pages, see settings_mock.lua)
--   sv: saved variables to load (as LM.Logout(c) returns them: a reload or a later session)
--   opts.noEUI, opts.eui (stand-in options: retail, failImport, encodeFails, specLocked, defaults, ...), opts.euiVersion,
--   opts.screen = { w, h, physW, physH, scale } (UIParent's size in its own units; default 2133.33 x 1200: 1920 x 1080 at
--   UI scale 0.64), opts.wizardMissing / opts.layoutsMissing ("MISSING" from LoadAddOn), opts.wizardDisabled,
--   opts.refuseTextures(path) -> true to have SetTexture say the game refused that file
--   c.said (chat), c.combat, c.reloads (ReloadUI calls), c.popup / c.Accept() / c.Decline() (the last question asked),
--   c.PressEsc(), c.escRegistered, c.made (frames and regions made), c.E (the stand-in EllesmereUI), c.layoutLoads, c.wizardLoads
-- LM.Logout(c) -> the saved variables, as the game would write them.

dofile(TESTS .. "settings_mock.lua")

LM = {}
LM.SV = { "TwichUIDB", "TwichUIBackupDB", "TwichUIShareDB", "TwichUIRestoreDB", "TwichUIChronicleDB", "EllesmereUIDB" }

function LM.Copy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local o = {}
  seen[t] = o
  for k, v in pairs(t) do o[LM.Copy(k, seen)] = LM.Copy(v, seen) end
  return setmetatable(o, getmetatable(t))
end

function LM.Same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not LM.Same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

---------------------------------------------------------------------------
-- A stand-in EllesmereUI (as test_layouts.lua has it: it proves TwichUI's side only)
---------------------------------------------------------------------------
local STRINGS, NSTR = {}, 0
local function Encode(payload)
  NSTR = NSTR + 1
  local s = ("!EUI_w%d_"):format(NSTR) .. ("x"):rep(12)
  STRINGS[s] = LM.Copy(payload)
  return s
end

function LM.EUIDB()
  return {
    activeProfile = "Mine",
    profiles = {
      Mine = { addons = { EllesmereUIMinimap = { minimap = { enabled = true, coordsPosition = "topLeft" } },
                          EllesmereUIActionBars = { bars = { 1, 2 } }, EllesmereUIDataBars = { characters = { x = 1 }, keep = 1 } },
               fonts = { global = "Mine font" }, euiAccent = { useClass = false, custom = { r = 0.1, g = 0.2, b = 0.3 } },
               unlockLayout = { anchors = { a = 1 } } },
      Raid = { addons = { EllesmereUINameplates = { w = 5 } } },
    },
    profileOrder = { "Mine", "Raid" }, specProfiles = { [62] = "Raid" }, ppUIScale = 0.8, clickCast = { bind = 1 },
  }
end

function LM.InstallEUI(env, db, opts)
  opts = opts or {}
  local E = { IS_FOREVER = not opts.retail, calls = {} }
  env.EllesmereUIDB = db
  local function Call(name, a) E.calls[#E.calls + 1] = { name, a } end
  function E.GetProfilesDB() db.profiles = db.profiles or {}; db.profileOrder = db.profileOrder or {}; db.specProfiles = db.specProfiles or {}; return db end
  function E.GetActiveProfileName() return db.activeProfile or "Default" end
  function E.GetProfileList() return db.profileOrder, db.profiles end
  function E.IsModuleAddonLoaded() return true end
  function E.ExportProfile(name) Call("ExportProfile", name) return nil end
  function E.EncodePayload(p) Call("EncodePayload"); if opts.encodeFails then return nil end return Encode(p) end
  function E.DecodeImportString(s)
    local p = STRINGS[s]
    if not p then return nil, "Failed to decode string" end
    return LM.Copy(p)
  end
  function E.ImportProfile() error("TwichUI never calls ImportProfile directly") end
  function E.SwitchProfile(name) Call("SwitchProfile", name); if db.profiles[name] then db.activeProfile = name end end
  function E.DeleteProfile(name)
    Call("DeleteProfile", name)
    db.profiles[name] = nil
    for i, n in ipairs(db.profileOrder) do if n == name then table.remove(db.profileOrder, i) break end end
    for spec, n in pairs(db.specProfiles) do if n == name then db.specProfiles[spec] = nil end end
    if db.activeProfile == name then db.activeProfile = "Default" end
  end
  -- as the real one (EllesmereUI_Profiles.lua RenameProfile): the same table under the new name; order, spec assignments
  -- and the active profile follow it
  function E.RenameProfile(old, new)
    Call("RenameProfile", { old, new })
    if not db.profiles[old] then return end
    db.profiles[new], db.profiles[old] = db.profiles[old], nil
    for i, n in ipairs(db.profileOrder) do if n == old then db.profileOrder[i] = new break end end
    for spec, n in pairs(db.specProfiles) do if n == old then db.specProfiles[spec] = new end end
    if db.activeProfile == old then db.activeProfile = new end
  end
  function E.ImportProfileSilent(o)
    Call("ImportProfileSilent", LM.Copy(o))
    if env.InCombatLockdown() then return false, "in combat" end
    local payload = E.DecodeImportString(o.importString)
    if type(payload) ~= "table" then return false, "could not decode import string" end
    if o.applyUIScale == false then payload.data.uiScale, payload.data.applyUIScale = nil, nil end
    if not o.autoAssignSpecs then payload.data.assignedSpecs = nil end
    if o.cleanSlate ~= false and db.profiles[o.profileName] then E.DeleteProfile(o.profileName) end
    E.imported = LM.Copy(payload)
    if opts.failImport then return false, "Unknown profile type" end
    local merged = LM.Copy(db.profiles[db.activeProfile] or {})
    merged.addons = merged.addons or {}
    for k, v in pairs(payload.data.addons or {}) do merged.addons[k] = LM.Copy(v) end
    for _, k in ipairs({ "fonts", "customColors", "darkMode", "euiAccent", "_migrations", "unlockLayout" }) do if payload.data[k] then merged[k] = LM.Copy(payload.data[k]) end end
    db.profiles[o.profileName] = merged
    table.insert(db.profileOrder, o.profileName)
    if type(payload.data.uiScale) == "number" then db.ppUIScale = payload.data.uiScale end
    if opts.specLocked then return true, nil, "spec_locked" end
    db.activeProfile = o.profileName
    return true, nil
  end
  function E.RegisterExternalInstaller(name) E.installer = name end
  -- opts.defaults: what the real one does as it loads, fill its defaults into every profile's blobs (test_layout_update.lua)
  function E.Loaded()
    if not opts.defaults then return end
    for _, p in pairs(db.profiles or {}) do
      local m = p.addons and p.addons.EllesmereUIMinimap
      if m then m.minimap = m.minimap or {}; if m.minimap.loadDefault == nil then m.minimap.loadDefault = 1 end end
    end
  end
  function E.called(name) local n = 0 for _, c in ipairs(E.calls) do if c[1] == name then n = n + 1 end end return n end
  env.EllesmereUI = E
  return E
end

---------------------------------------------------------------------------
-- Stand-in frames: they keep what a test reads back (size, points, text, colours, scripts, events, shown) and count how
-- many were made. The game gives a frame its backdrop methods only when it was made with BackdropTemplate.
---------------------------------------------------------------------------
local BACKDROP = { SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true, GetBackdrop = true }

local function MakeFake(c)
  local made = 0
  local function Fake(kind, parent, template, name)
    made = made + 1
    local f = { kind = kind, parent = parent, scripts = {}, hooks = {}, points = {}, shown = true, w = 0, h = 0, name = name,
      text = "", value = 0, min = 0, max = 1, enabled = true, scroll = 0, children = {}, events = {}, alpha = 1, scale = 1 }
    if parent and parent.children then table.insert(parent.children, f) end
    local function Fire(self, ev, ...)
      if self.scripts[ev] then self.scripts[ev](self, ...) end
      for _, h in ipairs(self.hooks[ev] or {}) do h(self, ...) end
    end
    f.Fire = Fire
    local methods = {
      SetScript = function(s, n, fn) s.scripts[n] = fn end,
      GetScript = function(s, n) return s.scripts[n] end,
      HookScript = function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end,
      SetSize = function(s, w, h) s.w, s.h = w, h end,
      SetWidth = function(s, w) s.w = w end, SetHeight = function(s, h) s.h = h end,
      GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
      SetPoint = function(s, ...) table.insert(s.points, { ... }) end,
      ClearAllPoints = function(s) s.points = {} end,
      GetPoint = function(s, i) local p = s.points[i or 1]; if p then return unpack(p) end end,
      Show = function(s) if not s.shown then s.shown = true; Fire(s, "OnShow") end end,
      Hide = function(s) if s.shown then s.shown = false; Fire(s, "OnHide") end end,
      SetShown = function(s, v) if v then s:Show() else s:Hide() end end,
      IsShown = function(s) return s.shown end,
      IsVisible = function(s) local p = s while p do if not p.shown then return false end p = p.parent end return true end,
      SetText = function(s, t) s.text = t == nil and "" or tostring(t) end,
      GetText = function(s) return s.text end,
      GetStringHeight = function(s)
        local width = s.w > 0 and s.w or 400
        return 12 * math.max(1, math.ceil(#s.text * 6 / width))
      end,
      GetStringWidth = function(s) return #s.text * 6 end,
      IsTruncated = function() return false end,
      SetEnabled = function(s, v) v = v and true or false; if s.enabled ~= v then s.enabled = v; Fire(s, v and "OnEnable" or "OnDisable") end end,
      Enable = function(s) s:SetEnabled(true) end, Disable = function(s) s:SetEnabled(false) end,
      IsEnabled = function(s) return s.enabled end,
      SetMinMaxValues = function(s, lo, hi) s.min, s.max = lo, hi end,
      SetValue = function(s, v) s.value = v end, GetValue = function(s) return s.value end,
      GetThumbTexture = function(s) s.thumb = s.thumb or Fake("Texture", s); return s.thumb end,
      SetScrollChild = function(s, child) s.child = child end,
      SetVerticalScroll = function(s, v) s.scroll = v end, GetVerticalScroll = function(s) return s.scroll end,
      GetVerticalScrollRange = function(s) return math.max(0, (s.child and s.child.h or 0) - s.h) end,
      IsMouseOver = function() return false end,
      GetEffectiveScale = function(s) return s.effectiveScale or 1 end,
      GetCenter = function(s) return s.centerX or 0, s.centerY or 0 end,
      SetScale = function(s, v) s.scale = v end, GetScale = function(s) return s.scale end,
      EnableMouse = function(s, v) s.mouse = v and true or false end,
      IsMouseEnabled = function(s) return s.mouse == true end,
      EnableKeyboard = function(s, v) s.keyboard = v and true or false end,
      SetFrameStrata = function(s, v) s.strata = v end, GetFrameStrata = function(s) return s.strata end,
      SetAllPoints = function(s, to) s.allPoints = to or true end,
      GetFrameLevel = function() return 1 end,
      GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
      SetFont = function() return true end,
      SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha end,
      CreateTexture = function(s) return Fake("Texture", s) end,
      CreateLine = function(s) return Fake("Line", s) end,
      CreateFontString = function(s) return Fake("FontString", s) end,
      RegisterEvent = function(s, e) s.events[e] = true end,
      UnregisterEvent = function(s, e) s.events[e] = nil end,
      UnregisterAllEvents = function(s) s.events = {} end,
      IsEventRegistered = function(s, e) return s.events[e] == true end,
      SetColorTexture = function(s, r, g, b, a) s.color = { r, g, b, a } end,
      SetBackdropBorderColor = function(s, r, g, b, a) s.border = { r, g, b, a } end,
      SetBackdropColor = function(s, r, g, b, a) s.fill = { r, g, b, a } end,
      SetBackdrop = function(s, b) s.backdrop = b end,
      SetTexture = function(s, path)
        s.texture = path
        if c.refuseTexture and c.refuseTexture(path) then return false end
        return true
      end,
      SetTexCoord = function(s, ...) s.coords = { ... } end,
      SetVertexColor = function(s, r, g, b, a) s.vertex = { r, g, b, a } end,
      SetTextColor = function(s, r, g, b, a) s.textColor = { r, g, b, a } end,
      CreateAnimationGroup = function()
        local g = setmetatable({}, { __index = function() return function() end end })
        function g:Play() self.playing = true end
        function g:Stop() self.playing = false end
        function g:CreateAnimation() return setmetatable({}, { __index = function() return function() end end }) end
        return g
      end,
    }
    if kind == "ScrollFrame" then f.ScrollBar = Fake("Slider", f); f.ScrollBar.ThumbTexture = Fake("Texture", f.ScrollBar) end
    local backdrop = type(template) == "string" and template:find("BackdropTemplate", 1, true) ~= nil
    return setmetatable(f, { __index = function(_, k)
      if BACKDROP[k] and not backdrop then return nil end
      if methods[k] then return methods[k] end
      if type(k) == "string" and k:find("^%u") then return function() end end
    end })
  end
  return Fake, function() return made end
end

---------------------------------------------------------------------------
-- The client
---------------------------------------------------------------------------
local function TocFiles(folder)
  local list = {}
  for line in io.lines(REPO .. folder .. "/" .. folder .. ".toc") do
    line = line:gsub("\r", ""):gsub("%s+$", "")
    if line ~= "" and not line:find("^#") then list[#list + 1] = REPO .. folder .. "/" .. (line:gsub("\\", "/")) end
  end
  return list
end
LM.TocFiles = TocFiles

function LM.Boot(name, sv, opts)
  opts = opts or {}
  META = META or {}
  META.EllesmereUI = { Version = opts.euiVersion or "9.6.8" }   -- every boot, so one test's version doesn't leak into the next
  local E, fake, made
  local c, S = SettingsClient({ name = name, beforeInit = function(c)
    c.said = {}
    c.print = function(s) c.said[#c.said + 1] = tostring(s) end
    c.combat = false
    c.reloads = 0
    c.InCombatLockdown = function() return c.combat end
    c.ReloadUI = function() c.reloads = c.reloads + 1 end
    c.refuseTexture = opts.refuseTextures
    fake, made = MakeFake(c)
    c.CreateFrame = function(kind, fname, parent, template)
      local f = fake(kind, parent, template, fname)
      if fname then c[fname] = f end
      return f
    end
    local screen = opts.screen or { w = 2133.33, h = 1200 }
    c.UIParent = fake("Frame")
    c.UIParent.w, c.UIParent.h = screen.w, screen.h
    c.UIParent.effectiveScale = screen.scale or 0.64
    if screen.physW then c.GetPhysicalScreenSize = function() return screen.physW, screen.physH end end
    c.GameTooltip = fake("GameTooltip")
    c.UISpecialFrames = { "ColorPickerFrame" }
    c.escRegistered = 0   -- calls an addon made into the game's own Escape handler table (it taints it)
    c.GameMenuEscPriority = { Dialog = 1, Menu = 2, AddOn = 8 }
    c.RegisterGameMenuEscHandler = function() c.escRegistered = c.escRegistered + 1 end
    c.tinsert = table.insert
    c.GetLocale = function() return "enUS" end
    c.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
    for _, n in ipairs(LM.SV) do if sv and sv[n] ~= nil then c[n] = LM.Copy(sv[n]) end end
    if not opts.noEUI then
      E = LM.InstallEUI(c, c.EllesmereUIDB or LM.EUIDB(), opts.eui)
      local fire = c.FireEvent
      c.FireEvent = function(e, a, ...)
        fire(e, a, ...)
        if e == "ADDON_LOADED" and a == "!!!TwichUI" then E.Loaded(); c.LOADED.EllesmereUI = true; fire("ADDON_LOADED", "EllesmereUI") end
      end
    end
  end })
  -- a question asked of the player (R.Interact.Confirm): kept, and answered by Accept / Decline
  c.popup = nil
  c.StaticPopup_Show = function(key, text) c.popup = { key = key, text = text } return {} end
  function c.Accept()
    local p = assert(c.popup, "no question was asked")
    c.popup = nil
    c.StaticPopupDialogs[p.key].OnAccept()
  end
  function c.Decline()
    local p = assert(c.popup, "no question was asked")
    c.popup = nil
    local d = c.StaticPopupDialogs[p.key]
    if d.OnCancel then d.OnCancel() end
  end
  -- The game's CloseSpecialWindows: every listed frame that is shown is hidden.
  function c.PressEsc()
    local found = false
    for _, fname in ipairs(c.UISpecialFrames) do
      local f = c[fname]
      if f and f:IsShown() then f:Hide(); found = true end
    end
    return found
  end
  c.layoutLoads, c.wizardLoads = 0, 0
  c.E = E
  c.made = function() return made() end
  local settingsLoad = c.C_AddOns.LoadAddOn
  local function LoadFolder(folder)
    if c.LOADED[folder] then return true end
    for _, f in ipairs(TocFiles(folder)) do
      local chunk = assert(loadfile(f)); setfenv(chunk, c); chunk(folder, {})
    end
    c.LOADED[folder] = true
    return true
  end
  c.C_AddOns.LoadAddOn = function(addon)
    if addon == "TwichUI_Layouts" then
      c.layoutLoads = c.layoutLoads + 1
      if opts.layoutsMissing then return false, "MISSING" end
      return LoadFolder("TwichUI_Layouts")
    elseif addon == "TwichUI_LayoutWizard" then
      c.wizardLoads = c.wizardLoads + 1
      if opts.wizardMissing then return false, "MISSING" end
      if opts.wizardDisabled then return false, "DISABLED" end
      if opts.wizardBroken then
        c.LOADED.TwichUI_LayoutWizard = true   -- it loaded but never said it was ready
        return true
      end
      -- the game loads a dependency first (RequiredDeps: !!!TwichUI, TwichUI_Layouts)
      local ok = c.C_AddOns.LoadAddOn("TwichUI_Layouts")
      if not ok then return false, "DEP_MISSING" end
      return LoadFolder("TwichUI_LayoutWizard")
    end
    return settingsLoad(addon)
  end
  RunLongTimers(5)
  return c, S
end

function LM.Logout(c)
  c.FireEvent("PLAYER_LOGOUT")
  local s = {}
  for _, n in ipairs(LM.SV) do s[n] = LM.Copy(c[n]) end
  return s
end

function LM.Heard(c, text)
  for _, s in ipairs(c.said) do if s:find(text, 1, true) then return true end end
  return false
end

-- Every text drawn in a frame and the frames under it that are shown (visible), for reading a page.
function LM.Texts(frame, out)
  out = out or {}
  if frame.shown == false then return out end
  if type(frame.text) == "string" and frame.text ~= "" then out[#out + 1] = frame.text end
  for _, ch in ipairs(frame.children or {}) do LM.Texts(ch, out) end
  return out
end

function LM.Says(frame, text)
  for _, t in ipairs(LM.Texts(frame)) do if t:find(text, 1, true) then return true end end
  return false
end

-- A button (a frame with scripts.OnClick) whose label is `label`, anywhere under frame, shown or not.
function LM.Button(frame, label)
  if frame.scripts and frame.scripts.OnClick then
    if frame.text == label then return frame end
    for _, ch in ipairs(frame.children or {}) do
      if ch.kind == "FontString" and ch.text == label then return frame end
    end
  end
  for _, ch in ipairs(frame.children or {}) do
    local b = LM.Button(ch, label)
    if b then return b end
  end
end

-- True when the button and everything above it is shown.
function LM.Visible(f) return f ~= nil and f:IsVisible() end
