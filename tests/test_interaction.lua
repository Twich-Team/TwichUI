dofile(TESTS .. "harness.lua")
-- Shared interaction helpers (modules/Interact.lua): a confirmation says what it is given, can be
-- accepted once, does nothing when cancelled or when its target has changed, and refuses in combat;
-- a tooltip explains why a control is unavailable, follows its state, and goes with its owner.
local c = MakeClient("Rich", {"!!!TwichUI"})
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local I = R.Interact
assert(I and I.Confirm and I.Tip and I.RefreshTip and I.HideTip, "the helpers are there")

local printed = {}
c.print = function(line) printed[#printed + 1] = line end
local function Said(text) return printed[#printed] and printed[#printed]:find(text, 1, true) ~= nil end

---------------------------------------------------------------------------
-- Confirm
---------------------------------------------------------------------------
c.ACCEPT, c.CANCEL = "Accept", "Cancel"
c.StaticPopupDialogs = {}
local asked
c.StaticPopup_Show = function(key, text)
  -- the game formats the dialog's text with the argument
  asked = { key = key, shown = string.format(c.StaticPopupDialogs[key].text, text), dialog = c.StaticPopupDialogs[key] }
  return {}
end

-- The text is shown as written: a percent sign or a pipe in a name can't break it.
I.Confirm("T_TEXT", "Reset 100% of \"Raid|Heal %s\"?", function() end)
assert(asked.shown == "Reset 100% of \"Raid|Heal %s\"?", asked.shown)
assert(asked.dialog.button1 == "Accept" and asked.dialog.button2 == "Cancel" and asked.dialog.hideOnEscape == true)
I.Confirm("T_LABEL", "x", function() end, { accept = "Delete" })
assert(asked.dialog.button1 == "Delete")

-- Accepting applies once, however many times the button is pressed.
local ran = 0
I.Confirm("T_ONCE", "Do it?", function() ran = ran + 1 end)
asked.dialog.OnAccept(); asked.dialog.OnAccept()
assert(ran == 1, "applied once")

-- Cancelling leaves things as they were, and a late accept of the old question does nothing.
ran = 0
local cancelled = 0
I.Confirm("T_CANCEL", "Do it?", function() ran = ran + 1 end, { onCancel = function() cancelled = cancelled + 1 end })
local dialog = asked.dialog
dialog.OnCancel(nil, nil, "clicked")
dialog.OnAccept()
assert(ran == 0 and cancelled == 1, "cancelled: nothing applied")

-- A newer question replacing this one is not the player declining, and only the newer one applies.
ran = 0
local first = 0
I.Confirm("T_REPLACE", "First?", function() first = first + 1 end, { onCancel = function() cancelled = cancelled + 100 end })
local old = asked.dialog
I.Confirm("T_REPLACE", "Second?", function() ran = ran + 1 end)
old.OnCancel(nil, nil, "override")
assert(cancelled == 1, "being replaced is not a cancel")
c.StaticPopupDialogs.T_REPLACE.OnAccept()
assert(ran == 1 and first == 0, "the latest question is the one that applies")

-- The target is checked at the moment of accepting.
ran = 0
local exists = true
I.Confirm("T_VALID", "Delete it?", function() ran = ran + 1 end, {
  valid = function() if not exists then return false, "It is already gone, so nothing was changed." end return true end,
})
exists = false
asked.dialog.OnAccept()
assert(ran == 0 and Said("already gone"), "stale target: nothing applied, and it says so")
exists = true
I.Confirm("T_VALID", "Delete it?", function() ran = ran + 1 end, { valid = function() return exists, "gone" end })
asked.dialog.OnAccept()
assert(ran == 1, "a target that is still there is applied")

-- Combat is refused for actions that reload the UI or change settings.
ran = 0
c.InCombatLockdown = function() return true end
I.Confirm("T_COMBAT", "Apply it?", function() ran = ran + 1 end, { combat = true })
asked.dialog.OnAccept()
assert(ran == 0 and Said("out of combat"), "in combat: nothing happens, and it says why")
c.InCombatLockdown = function() return false end
I.Confirm("T_COMBAT", "Apply it?", function() ran = ran + 1 end, { combat = true })
asked.dialog.OnAccept()
assert(ran == 1)

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
local tip = { lines = {} }
function tip:SetOwner(owner) self.owner, self.lines = owner, {} end
function tip:GetOwner() return self.owner end
function tip:SetText(text) self.lines[#self.lines + 1] = text end
function tip:AddLine(text) self.lines[#self.lines + 1] = text end
function tip:Show() self.shown = true end
function tip:Hide() self.shown = false; self.owner = nil end
function tip:Text() return table.concat(self.lines, "|") end
c.GameTooltip = tip

local function Frame()
  local f = { scripts = {}, hooks = {}, visible = true, over = true }
  function f:SetScript(name, fn) self.scripts[name] = fn end
  function f:HookScript(name, fn) self.hooks[name] = self.hooks[name] or {}; table.insert(self.hooks[name], fn) end
  function f:SetMotionScriptsWhileDisabled(on) self.motion = on end
  function f:IsShown() return self.visible end
  function f:IsMouseOver() return self.over end
  return f
end

-- Shows the title, the text and, when there is one, the reason; works for a disabled control.
local button, reason = Frame(), "Save your setup first."
I.Tip(button, "Send", function() return "Sends it to your friend.", reason end)
assert(button.motion == true, "a disabled button still answers the pointer")
button.scripts.OnEnter(button)
assert(tip.shown and tip.owner == button and tip:Text() == "Send|Sends it to your friend.|Save your setup first.", tip:Text())
button.scripts.OnLeave(button)
assert(not tip.shown, "leaving hides it")

-- Read each time, so it never describes an old state.
reason = nil
button.scripts.OnEnter(button)
assert(tip:Text() == "Send|Sends it to your friend.", tip:Text())

-- A change while the pointer is on it redraws it; if the pointer left, it goes.
reason = "Already sending."
I.RefreshTip(button)
assert(tip.shown and tip:Text():find("Already sending.", 1, true), "redrawn with the new reason")
button.over = false
I.RefreshTip(button)
assert(not tip.shown, "pointer gone: no tooltip left behind")
button.over = true

-- It goes when the control hides, but only if it is the one showing it.
button.scripts.OnEnter(button)
assert(#button.hooks.OnHide == 1, "one hide hook")
button.hooks.OnHide[1](button)
assert(not tip.shown, "hidden with its owner")
local other = Frame()
tip.owner, tip.shown = other, true
button.hooks.OnHide[1](button)
assert(tip.shown and tip.owner == other, "another frame's tooltip is left alone")
tip.owner, tip.shown = nil, false

-- Asking again doesn't stack hooks, and the newest text wins.
I.Tip(button, "Send", "Newer text")
assert(#button.hooks.OnHide == 1, "no duplicate hooks")
button.scripts.OnEnter(button)
assert(tip:Text() == "Send|Newer text", tip:Text())

-- Nothing to say: no empty tooltip.
local quiet = Frame()
I.Tip(quiet, "Post", function() return nil end)
tip.owner, tip.shown = nil, false
quiet.scripts.OnEnter(quiet)
assert(not tip.shown, "no empty tooltip")

print("INTERACTION TESTS PASSED")
