dofile(TESTS .. "harness.lua")
-- Quality of Life: Hide error messages, Silence error speech (qol/ErrorMessages.lua).
-- The game is simulated: this checks the decisions, the event wiring and the CVar bookkeeping, not
-- the game's own behaviour (whether the voice really stops has to be checked in the game).
local c = MakeClient("Rich", {"!!!TwichUI"})

local cvar, cvarSets = { Sound_EnableErrorSpeech = "1" }, {}
c.GetCVar = function(name) return cvar[name] end
c.SetCVar = function(name, value) cvar[name] = tostring(value); cvarSets[#cvarSets + 1] = name .. "=" .. tostring(value) end
c.ERR_INV_FULL, c.ERR_QUEST_LOG_FULL, c.ERR_PLAYER_DEAD, c.ERR_RAID_GROUP_ONLY = "Inventory is full.", "Quest log is full.", "You are dead.", "Raid only."
local shown, registered = {}, { UI_ERROR_MESSAGE = true }
c.UIErrorsFrame = {
  RegisterEvent = function(_, e) registered[e] = true end,
  UnregisterEvent = function(_, e) registered[e] = nil end,
  TryDisplayMessage = function(_, kind, text) shown[#shown + 1] = kind .. ":" .. text end,
}

local chunk = assert(loadfile(ROOT .. "qol/ErrorMessages.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R, E = c.TwichUI, c.TwichUI.QoLErrors
local DB = c.TwichUIDB
local function Listening() return R.frame.events.UI_ERROR_MESSAGE == true end
local function Set(key, on) DB.modules[key] = on; E.Refresh() end

-- Off by default: the frame keeps its event, nobody listens, the CVar is untouched.
assert(DB.modules.qolHideErrors == false and DB.modules.qolHideErrorSpeech == false and DB.modules.qolHideErrorsKeep == true)
assert(registered.UI_ERROR_MESSAGE and not Listening() and cvar.Sound_EnableErrorSpeech == "1" and #cvarSets == 0)

-- Hide errors: the frame lets go of the event; ours shows only the important few.
Set("qolHideErrors", true)
assert(not registered.UI_ERROR_MESSAGE, "the game's error frame no longer hears errors")
assert(Listening(), "ours does, to keep the important ones")
c.FireEvent("UI_ERROR_MESSAGE", 5, "Out of range.")
c.FireEvent("UI_ERROR_MESSAGE", 6, "Inventory is full.")
assert(#shown == 1 and shown[1] == "6:Inventory is full.", "only the bag-full message passes: " .. table.concat(shown, "|"))
assert(E.IsImportant("You are dead.") and E.IsImportant("Quest log is full.") and not E.IsImportant("Not enough rage") and not E.IsImportant(nil) and not E.IsImportant(5))
c.issecretvalue = function() return true end
assert(not E.IsImportant("Inventory is full."), "a secret value is never compared")
c.issecretvalue = nil

-- Without the exception nothing passes, and we stop listening.
Set("qolHideErrorsKeep", false)
assert(not Listening() and not registered.UI_ERROR_MESSAGE)
Set("qolHideErrorsKeep", true); assert(Listening())

-- Calling it again changes nothing.
Set("qolHideErrors", true); assert(not registered.UI_ERROR_MESSAGE and Listening())

-- Off again: the game's frame hears errors, ours stops.
Set("qolHideErrors", false)
assert(registered.UI_ERROR_MESSAGE and not Listening())
Set("qolHideErrors", false); assert(registered.UI_ERROR_MESSAGE, "turning off when already off does nothing")

-- Speech: the CVar goes to 0, the old value is remembered, and it is put back.
Set("qolHideErrorSpeech", true)
assert(cvar.Sound_EnableErrorSpeech == "0" and DB.ui.qol.errorSpeechWas == "1")
Set("qolHideErrorSpeech", true); assert(DB.ui.qol.errorSpeechWas == "1", "a second Refresh does not remember our own 0")
Set("qolHideErrorSpeech", false)
assert(cvar.Sound_EnableErrorSpeech == "1" and DB.ui.qol.errorSpeechWas == nil, "restored, and the record is cleared")

-- A player who changed it meanwhile keeps their choice.
Set("qolHideErrorSpeech", true); cvar.Sound_EnableErrorSpeech = "1"
Set("qolHideErrorSpeech", false)
assert(cvar.Sound_EnableErrorSpeech == "1" and DB.ui.qol.errorSpeechWas == nil)

-- A CVar that was already off is not turned on again.
cvar.Sound_EnableErrorSpeech = "0"; DB.ui.qol.errorSpeechWas = nil; for i = #cvarSets, 1, -1 do cvarSets[i] = nil end
Set("qolHideErrorSpeech", true); Set("qolHideErrorSpeech", false)
assert(cvar.Sound_EnableErrorSpeech == "0" and #cvarSets == 0, "it was off before, so it stays off and is never written")

-- A damaged record is never written back.
cvar.Sound_EnableErrorSpeech = "1"; Set("qolHideErrorSpeech", true)
DB.ui.qol.errorSpeechWas = "not a value at all"; Set("qolHideErrorSpeech", false)
assert(cvar.Sound_EnableErrorSpeech == "0" and DB.ui.qol.errorSpeechWas == nil)

-- A client without the setting does nothing.
cvar.Sound_EnableErrorSpeech = nil; for i = #cvarSets, 1, -1 do cvarSets[i] = nil end
Set("qolHideErrorSpeech", true); assert(#cvarSets == 0)

print("PASSED test_qol_errors")
