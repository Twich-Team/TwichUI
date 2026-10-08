dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", {"!!!TwichUI"})
local function Obj()
  local o = {text = "", checked = false, shown = true}
  return setmetatable(o, {__index = function(t, k)
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetText" then return function(s, v) s.text = v or "" end end
    if k == "GetChecked" then return function(s) return s.checked end end
    if k == "SetChecked" then return function(s, v) s.checked = v end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "SetShown" then return function(s, v) s.shown = v end end
    if k == "SetEnabled" then return function(s, v) s.enabled = v and true or false end end
    if k == "IsEnabled" then return function(s) return s.enabled ~= false end end
    if k == "SetScript" then return function(s, n, fn) local t = rawget(s, "scripts"); if not t then t = {}; rawset(s, "scripts", t) end; t[n] = fn end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Obj() end end
    return function() end
  end})
end
local all = {}
c.tinsert = table.insert; c.CreateFrame = function(_, name) local o = Obj(); all[#all + 1] = o; if name then c[name] = o end return o end
c.UISpecialFrames = {}; c.UIParent = Obj(); c.GameTooltip_Hide = function() end
c.StaticPopupDialogs = {}; c.StaticPopup_Show = function(k, text) c.popup = k; c.popupText = text; return {} end
c.CANCEL = "Cancel"; c.Settings = nil
c.GetRealZoneText = function() return "Elwynn Forest" end
c.TwichUIDB = {}
c.SOUNDKIT = { IG_ABILITY_PAGE_TURN = 836 }
c.sounds = {}
c.PlaySound = function(id) c.sounds[#c.sounds + 1] = id end
for _, file in ipairs({"chronicle/Style.lua", "chronicle/Window.lua"}) do
local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local W, C = c.TwichUI.ChronicleWindow, c.TwichUI.Chronicle
W:Toggle()                         -- empty state
assert(W:Toggle() == nil)
W:Show()
C.Add("note", { title = "Note", note = "with |cffff0000 codes", zone = "Elwynn Forest" })
C.Add("level", { title = "Reached level 5", level = 5 })
W:Refresh(); W:Hide(); W:Show()
-- the slash command opens it
c.SlashCmdList.TWICHUI("chronicle"); c.SlashCmdList.TWICHUI("journal")
-- clock: 12-hour by default, 24-hour when chosen
local shown = {}
c.date = function(fmt, t) return os.date(fmt, t) end
c.TwichUIDB.ui = nil; W:Refresh()
c.TwichUIDB.ui = { chronicleClock = "24" }; W:Refresh()
-- opening sound: via the frame's OnShow only; not on refresh; can be turned off
local f = c.TwichUIChronicle
c.sounds = {}
W:Refresh(); W:Refresh()
assert(#c.sounds == 0, "refresh is silent")
f.scripts.OnShow()
assert(#c.sounds == 1 and c.sounds[1] == 836, "one page turn per opening")
c.TwichUIDB.modules = { chronicleSound = false }
f.scripts.OnShow()
assert(#c.sounds == 1, "the setting turns it off")
-- header: placeholder, then a compact time; ignored once the frame is closed
assert(f.played.text == "Journey time: \226\128\148", f.played.text)
W.ShowPlayed(3 * 86400 + 7 * 3600 + 24 * 60)
assert(f.played.text == "Journey time: 3d 7h 24m", f.played.text)
W.ShowPlayed(47 * 60); assert(f.played.text == "Journey time: 47m")
f.shown = false; W.ShowPlayed(60); assert(f.played.text == "Journey time: 47m", "closed frame isn't updated")

-- The note editor: Save is off and Enter explains itself while there is nothing to save; the window
-- stays open rather than throwing the note away.
do
  local printed = {}
  c.print = function(s) printed[#printed + 1] = s end
  local function Find(match) for _, o in ipairs(all) do if match(o) then return o end end end
  local write = Find(function(o) return type(o.text) == "table" and o.text.text == "Write a note" end)
  assert(write, "the Write a note button")
  local before = #C.Entries()
  write.scripts.OnClick()
  local ed = c.TwichUIChronicleNote
  assert(ed and ed.shown, "the editor opens")
  assert(ed.save.enabled == false, "Save is off while the box is empty")
  ed.box.scripts.OnEnterPressed()
  assert(ed.shown and #C.Entries() == before, "Enter on an empty note neither closes nor saves")
  assert(ed.hint.text:find("Write something", 1, true), "and says why: " .. ed.hint.text)
  ed.box:SetText("   "); ed.box.scripts.OnTextChanged(ed.box)
  assert(ed.save.enabled == false, "spaces alone are nothing")
  ed.box.scripts.OnEnterPressed()
  assert(ed.shown and #C.Entries() == before)
  ed.box:SetText("A quiet evening"); ed.box.scripts.OnTextChanged(ed.box)
  assert(ed.save.enabled == true and ed.hint.text == "Press Enter to save, Esc to cancel.", "typing clears the message and enables Save")
  ed.box.scripts.OnEnterPressed()
  assert(not ed.shown and #C.Entries() == before + 1, "saved once, editor closed")
  ed.box.scripts.OnEnterPressed()
  assert(#C.Entries() == before + 1, "a repeated Enter on the closed editor does not add a second copy")
end

-- Deleting names what goes, can be cancelled, and checks the entry is still there when confirmed.
do
  local printed = {}
  c.print = function(s) printed[#printed + 1] = s end
  W:Show()
  local function Row(text)
    for _, o in ipairs(all) do
      if type(rawget(o, "entry")) == "table" and rawget(o, "delete") and (o.entry.note or o.entry.title) == text then return o end
    end
  end
  local row = Row("A quiet evening")
  assert(row, "the new note has a row")
  local id = row.entry.id
  local n = #C.Entries()
  row.delete.scripts.OnClick()
  assert(c.popup == "TWICHUI_CHRONICLE_DELETE" and c.popupText:find("A quiet evening", 1, true)
    and c.popupText:find("note", 1, true) and c.popupText:find("can't be undone", 1, true), "the question says what: " .. tostring(c.popupText))
  local dlg = c.StaticPopupDialogs.TWICHUI_CHRONICLE_DELETE
  dlg.OnCancel(nil, nil, "clicked")
  dlg.OnAccept()
  assert(#C.Entries() == n, "cancelling leaves the Chronicle as it was, even if the old button is pressed after")
  -- gone while the question was open
  row.delete.scripts.OnClick()
  C.Delete(id)
  c.StaticPopupDialogs.TWICHUI_CHRONICLE_DELETE.OnAccept()
  assert(#C.Entries() == n - 1, "nothing else was deleted in its place")
  assert(printed[#printed]:find("already gone", 1, true), "and it says so: " .. tostring(printed[#printed]))
  -- an ordinary delete
  C.Add("note", { title = "Note", note = "Second thoughts" })
  W:Refresh()
  row = Row("Second thoughts")
  local m = #C.Entries()
  row.delete.scripts.OnClick()
  local d2 = c.StaticPopupDialogs.TWICHUI_CHRONICLE_DELETE
  d2.OnAccept(); d2.OnAccept()
  assert(#C.Entries() == m - 1, "confirmed once, applied once")
end
print("CHRONICLE WINDOW OK")
