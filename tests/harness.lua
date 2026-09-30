TIMERS = {}
LONG_TIMERS = {}
UPDATERS = {}
function FlushTimers() for fr, fn in pairs(UPDATERS) do for _ = 1, 50 do if UPDATERS[fr] then UPDATERS[fr](fr, 0.016) end end end local t = TIMERS; TIMERS = {}; for _, f in ipairs(t) do f() end end
require("bit")
local ROOT = ROOT
local FILES = {
 "libs/LibStub/LibStub.lua","libs/CallbackHandler-1.0/CallbackHandler-1.0.lua","libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua",
 "libs/AceComm-3.0/ChatThrottleLib.lua","libs/AceComm-3.0/AceComm-3.0.lua","libs/LibSerialize/LibSerialize.lua","libs/LibDeflate/LibDeflate.lua",
 "Core.lua","modules/QuietLogin.lua","modules/Media.lua","modules/AuctionatorSkin.lua","setup/PackFile.lua","setup/Setups.lua","setup/Share.lua","setup/Group.lua","setup/Restore.lua",
}
NET = {}   -- queued deliveries {toEnv, prefix, text, sender}
function MakeClient(charName, addons)
  local env = {}
  setmetatable(env, {__index = _G})
  env._G = env
  local frames = {}
  local function newFrame()
    local fr = {events = {}, scripts = {}, hooks = {}}
    function fr:RegisterEvent(e) self.events[e] = true end
    function fr:UnregisterEvent(e) self.events[e] = nil end
    function fr:UnregisterAllEvents() self.events = {} end
    function fr:SetScript(n, fn) self.scripts[n] = fn; if n == "OnUpdate" then UPDATERS[self] = fn end end
    function fr:GetScript(n) return self.scripts[n] end
    function fr:HookScript(n, fn) self.hooks[n] = self.hooks[n] or {}; table.insert(self.hooks[n], fn) end
    function fr:Show() end function fr:Hide() end function fr:IsShown() return false end
    function fr:SetFrameStrata() end
    table.insert(frames, fr); return fr
  end
  env.CreateFrame = function() return newFrame() end
  env.FireEvent = function(e, ...)
    for _, fr in ipairs(frames) do
      if fr.events[e] then
        if fr.scripts.OnEvent then fr.scripts.OnEvent(fr, e, ...) end
        for _, h in ipairs(fr.hooks.OnEvent or {}) do h(fr, e, ...) end
      end
    end
  end
  env.hooksecurefunc = function() end
  env.GetTime = os.clock
  env.time = os.time
  env.date = os.date
  env.UnitName = function() return (charName:gsub(" .*$", "")) end
  env.GetRealmName = function() return "Forever" end
  env.GetNormalizedRealmName = function() return "Forever" end
  env.Ambiguate = function(n) return (n:gsub("%-.*$", "")) end
  env.GetBuildInfo = function() return "1.60.1", "70009", "Sep", 16001 end
  env.ReloadUI = function() env.reloaded = true end
  env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  env.print = function(s) print("["..charName.."] "..tostring(s)) end
  env.geterrorhandler = function() return function(e) print("["..charName.."] ERROR: "..tostring(e)) end end
  -- Short timers run on the next FlushTimers(); longer ones (timeouts, delayed hellos) wait for RunLongTimers(seconds).
  env.C_Timer = {After = function(d, fn) if d <= 1 then table.insert(TIMERS, fn) else table.insert(LONG_TIMERS, {d = d, fn = fn}) end end, NewTicker = function() return {Cancel = function() end} end}
  env.UnitGUID = function() return "Player-1-" .. charName end
  env.IsInGroup = function() return GROUP ~= nil and GROUP[charName] ~= nil end
  env.IsInRaid = function() return false end
  env.GetNumGroupMembers = function() local n = 0 for _ in pairs(GROUP or {}) do n = n + 1 end return n end
  env.InCombatLockdown = function() return false end
  env.GetBuildInfo = function() return "1.60.1", BUILD or "70009", "Sep", 16001 end
  env.IsInGuild = function() return false end
  env.GetUnitName = function(u, full)
    if u == "player" then return charName end
    local i = tonumber((u or ""):match("^party(%d)$"))
    if i and GROUP then local list = {} for k in pairs(GROUP) do if k ~= charName then table.insert(list, k) end end table.sort(list) return list[i] end
    return charName
  end
  env.C_ChatInfo = {RegisterAddonMessagePrefix = function() return true end, SendAddonMessage = function() end, InChatMessagingLockdown = function() return false end}
  env.LOADED = {}
  env.C_AddOns = {
    GetNumAddOns = function() return #addons end,
    GetAddOnInfo = function(i) local n = type(i)=="number" and addons[i] or i; local off = (OFF or {})[n]; return n, n.." Title", "", not off, off and "DISABLED" or "", "INSECURE" end,
    IsAddOnLoaded = function(i) local n = type(i)=="number" and addons[i] or i; return env.LOADED[n] or false end,
    IsAddOnLoadOnDemand = function(i) local n = type(i)=="number" and addons[i] or i; return (LOD or {})[n] or false end,
    DoesAddOnExist = function(n) for _,a in ipairs(addons) do if a==n then return true end end return false end,
    GetAddOnMetadata = function(n, field) local m = (META or {})[n]; return m and m[field] end,
    GetAddOnDependencies = function(i) local n = type(i)=="number" and addons[i] or i; return unpack((DEPS or {})[n] or {}) end,
    GetAddOnEnableState = function(n) return (OFF or {})[n] and 0 or 2 end,
  }
  env.Enum = {}
  env.GetLocale = function() return "enUS" end
  env.strmatch, env.strsub, env.strlen, env.strbyte, env.strchar, env.strfind, env.strrep, env.format = string.match, string.sub, string.len, string.byte, string.char, string.find, string.rep, string.format
  env.tinsert, env.tremove, env.tconcat = table.insert, table.remove, table.concat
  env.gsub, env.strlower, env.strupper = string.gsub, string.lower, string.upper
  env.max, env.min, env.floor = math.max, math.min, math.floor
  env.debugstack = function() return "" end
  env.securecallfunction = function(f, ...) return f(...) end
  env.GetFramerate = function() return 60 end
  env.BNGetNumFriends = function() return 0 end
  env.SlashCmdList = {}
  env.math = math
  env.DEFAULT_CHAT_FRAME = {AddMessage=function() end}
  env.LibStub = nil
  -- load files
  for _, f in ipairs(FILES) do
    if f == "setup/Share.lua" then
      local AceComm = env.LibStub("AceComm-3.0")
      env._comm = {}
      AceComm.RegisterComm = function(self, prefix, fn) env._comm[prefix] = fn end
      AceComm.SendCommMessage = function(self, prefix, text, dist, target, prio, cb, arg)
        table.insert(NET, {dist = dist, to = target, prefix = prefix, text = text, sender = SENDER_FMT and SENDER_FMT(charName) or charName.."-Forever", from = env})
        if cb then cb(arg, #text, #text) end
      end
    end
    local chunk = assert(loadfile(ROOT..f))
    setfenv(chunk, env)
    chunk("!!!TwichUI", {})
  end
  return env
end
CLIENTS = {}
function Pump()
  local n = 0
  while #NET > 0 do
    local m = table.remove(NET, 1)
    local targets = {}
    if m.dist == "WHISPER" then
      if DROP_SPACED_WHISPERS and m.to:find(" ") then targets = {} else
        local toName = m.to:gsub("%-.*$","")
        for k, v in pairs(CLIENTS) do if k:lower() == toName:lower() then targets = {v} end end
        if #targets == 0 then print("NO PLAYER: "..m.to) end
      end
    else
      for k, v in pairs(CLIENTS) do if (GROUP or {})[k] or v == m.from then table.insert(targets, v) end end
    end
    for _, c in ipairs(targets) do
      local fn = c._comm[m.prefix]
      if fn then fn(m.prefix, m.text, m.dist, m.sender) end
    end
    n = n + 1
  end
  return n
end
-- Fires pending timers that were scheduled with a delay of up to maxDelay seconds.
function RunLongTimers(maxDelay)
  local t = LONG_TIMERS; LONG_TIMERS = {}
  for _, e in ipairs(t) do
    if e.d <= maxDelay then e.fn() else table.insert(LONG_TIMERS, e) end
  end
end
