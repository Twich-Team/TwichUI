-- The player's selected self-status: hover opens only; each explicit click rechecks state and channel.
dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", { "!!!TwichUI" })
local R = c.TwichUI
local open, live, enabled, combat, lockdown, clock = nil, true, true, false, false, 10
local home, instance, raid, sent, notices = false, false, false, {}, {}
c.LE_PARTY_CATEGORY_HOME, c.LE_PARTY_CATEGORY_INSTANCE = 1, 2
c.IsInGroup = function(category) if category == 1 then return home else return instance end end
c.IsInRaid = function() return raid end
c.GetTime = function() return clock end
c.InCombatLockdown = function() return combat end
c.issecretvalue = function(v) return type(v) == "table" and v.secret == true end
c.C_ChatInfo = { InChatMessagingLockdown = function() return lockdown end,
  SendChatMessage = function(text, channel) sent[#sent + 1] = { text, channel } end }
R.Enabled = function() return enabled end
R.Print = function(...) notices[#notices + 1] = {...} end
R.HealerDisplay = { CommunicationLive = function() return live end }
local profileApply, profileChange
R.Profiles = { OnApply = function(_, _, fn) profileApply = fn end, OnChange = function(fn) profileChange = fn end }
R.HealerPicker = {
  IsOpen = function() return open ~= nil end,
  Kind = function() return open and open.options.kind end,
  Close = function(reason) if open then local old = open; open = nil; if old.options.onClose then old.options.onClose(reason or "closed") end end end,
  Open = function(owner, list, chosen, click, options) open = {owner=owner,list=list,click=click,options=options}; return true end,
}
local chunk = assert(loadfile(ROOT .. "healer/Communication.lua")); setfenv(chunk, c); chunk()
local C = R.HealerCommunication
local function hover() assert(R.HealerDisplay.onCommunication({})); assert(open and #open.list == 4) end
local function click(key)
  local callback = open.click
  R.HealerPicker.Close("selected"); callback(key)
end
hover(); assert(#sent == 0 and open.options.title:find("No group channel",1,true)); click("ready"); assert(#sent == 0)
home = true; hover(); assert(#sent == 0); click("drinking"); assert(sent[1][1] == "Drinking." and sent[1][2] == "PARTY")
hover(); click("oom"); assert(#sent == 1, "explicit repeat is rate limited")
clock=14; raid=true; hover(); click("oom"); assert(sent[2][1] == "Out of mana." and sent[2][2] == "RAID")
clock=18; instance=true; hover(); click("moment"); assert(sent[3][2] == "INSTANCE_CHAT")
clock=22; instance=true; raid=true; hover(); click("ready"); assert(sent[4][2] == "INSTANCE_CHAT")
clock=26; instance=false; raid=false; home=true; hover(); combat=true; click("ready"); assert(#sent==4); combat=false
hover(); lockdown=true; click("ready"); assert(#sent==4); lockdown=false
hover(); home=false; click("ready"); assert(#sent==4)
home=true; hover(); local stale=open.click; C.Close(); stale("ready"); assert(#sent==4)
hover(); live=false; click("ready"); assert(#sent==4); live=true
hover(); enabled=false; click("ready"); assert(#sent==4); enabled=true
hover(); c.C_ChatInfo.InChatMessagingLockdown=function() return {secret=true} end; click("ready"); assert(#sent==4)
c.C_ChatInfo.InChatMessagingLockdown=function() return false end
hover(); local profileStale=open.click; profileApply(); profileStale("ready"); assert(#sent==4)
hover(); profileStale=open.click; profileChange("duplicate"); profileStale("ready"); assert(#sent==4)
hover(); c.IsInGroup=function() return {secret=true} end; click("ready"); assert(#sent==4)
c.IsInGroup=function(category) return category == 1 end
combat=true; assert(not C.Open({}) and not open and #sent==4, "combat hover does not create a protected menu"); combat=false
c.InCombatLockdown=function() return nil end
assert(not C.Open({}) and not open and #sent==4, "unknown combat state fails closed")
assert(#notices > 0, "refusals are locally explained")
print("PASSED")
