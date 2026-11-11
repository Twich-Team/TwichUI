-- Reminders' artwork library and picture catalog (reminders/ArtData.lua, generated; reminders/Gallery.lua): every catalogued picture
-- is a real texture, ids and categories are consistent, search and categories work, and the three player-facing modes are a lossless
-- view of the five stored ones (every saved reminder keeps its picture, words and values). tests/test_reminder_gallery.py checks the
-- source images and that the tool rebuilds what is shipped.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

c.CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end
c.UIParent = c.CreateFrame()
for _, f in ipairs({ "Icons.lua", "reminders/AmmoItems.lua", "reminders/ArtData.lua", "reminders/Config.lua", "reminders/Gallery.lua", "setup/TwichConfig.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local RM, G, DATA = R.Reminders, R.Reminders.Gallery, R.ReminderArtData

local function TGA(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local h = fh:read(18)
  local size = fh:seek("end")
  local body
  fh:seek("set", 18)
  body = fh:read("*a")
  fh:close()
  local b = { h:byte(1, 18) }
  return { type = b[3], w = b[13] + b[14] * 256, h = b[15] + b[16] * 256, bpp = b[17], desc = b[18], size = size, body = body }
end

---------------------------------------------------------------------------
-- The data and the files
---------------------------------------------------------------------------
Check(DATA and #DATA.gallery >= 60, "the library has its pictures")
Check(#DATA.categories == 6, "six categories")
local seen, perCategory = {}, {}
local categorySet = {}
for _, cat in ipairs(DATA.categories) do categorySet[cat] = true; perCategory[cat] = 0 end
for _, e in ipairs(DATA.gallery) do
  local id, name, category, description, keywords, related = e[1], e[2], e[3], e[4], e[5], e[6]
  Check(not seen[id], "id " .. id .. " is unique")
  seen[id] = true
  Check(id:match("^reminder%-[a-z0-9%-]+$") and #id <= 40, id .. ": a readable stable id that fits display.art (40 characters)")
  Check(type(name) == "string" and name ~= "" and #name <= 40, id .. ": a display name")
  Check(categorySet[category], id .. ": a known category (" .. tostring(category) .. ")")
  perCategory[category] = (perCategory[category] or 0) + 1
  Check(type(description) == "string" and #description > 8, id .. ": a description")
  Check(type(keywords) == "string" and keywords:match("^[%l%d ]+$") and select(2, keywords:gsub("%S+", "")) >= 3, id .. ": lower-case search keywords, at least three")
  Check(RM.Art(id) ~= nil, id .. ": registered as artwork")
  for _, rel in ipairs(related) do
    Check(seen[rel] or rel == "wellfed" or rel == "ammo" or rel == "shield" or rel == "enchant" or (function()
      for _, g in ipairs(DATA.gallery) do if g[1] == rel then return true end end end)(), id .. ": related id " .. rel .. " exists")
  end
  local large, small = TGA(ROOT .. "media/reminders/gallery/" .. id .. ".tga"), TGA(ROOT .. "media/reminders/gallery/" .. id .. "-small.tga")
  Check(large and large.type == 2 and large.bpp == 32 and large.desc == 8 and large.w == DATA.large and large.h == DATA.large
    and large.size == 18 + large.w * large.h * 4, id .. ".tga: an uncompressed 32-bit square TGA with alpha at the large size")
  Check(small and small.type == 2 and small.bpp == 32 and small.desc == 8 and small.w == DATA.small and small.h == DATA.small
    and small.size == 18 + small.w * small.h * 4, id .. "-small.tga: the same at the small size")
  for _, t in ipairs({ large or false, small or false }) do
    if t then
      -- real transparency: some clear pixels, some opaque ones, a clear one-pixel edge all round, and the picture is not empty
      local clear, solid, edge = 0, 0, 0
      local body, w = t.body, t.w
      for y = 0, t.h - 1 do
        for x = 0, w - 1 do
          local a = body:byte((y * w + x) * 4 + 4)
          if a == 0 then clear = clear + 1 elseif a >= 250 then solid = solid + 1 end
          if (x == 0 or y == 0 or x == w - 1 or y == t.h - 1) and a ~= 0 then edge = edge + 1 end
        end
      end
      Check(clear > 0.2 * w * w and solid > 0.03 * w * w and edge == 0, id .. ": real alpha (" .. clear .. " clear, " .. solid .. " solid, " .. edge .. " on the edge)")
    end
  end
  local file, l, r, tt, b, aspect = RM.ArtTexture(id, 128)
  Check(file:find("gallery\\" .. id, 1, true) and file:sub(-#id) == id and aspect == 1 and l > 0 and r < 1 and tt > 0 and b < 1, id .. ": texture path and coordinates")
  local smallFile = RM.ArtTexture(id, 48)
  Check(smallFile:sub(-#"-small") == "-small", id .. ": small drawing uses the small file")
end
for _, cat in ipairs(DATA.categories) do Check(perCategory[cat] > 0, "category " .. cat .. " is not empty") end

---------------------------------------------------------------------------
-- The catalog
---------------------------------------------------------------------------
local entries = G.Entries()
local cats = G.Categories()
Check(cats[1] == "All" and #cats == 7, "All and the six categories")
Check(#entries == #DATA.gallery + 12, "the library, the four artworks that were here first and the eight icons: " .. #entries)
local ids = {}
for _, e in ipairs(entries) do
  Check(not ids[e.id], "catalog id " .. e.id .. " is unique")
  ids[e.id] = true
  Check(e.kind == "art" and RM.Art(e.target) or (e.kind == "icon" and RM.ValidIcon(e.target)), e.id .. ": it resolves to artwork or a TwichUI icon")
end
for _, id in ipairs({ "shield", "ammo", "wellfed", "enchant" }) do Check(G.Get(id) and G.Get(id).kind == "art" and G.Get(id).legacy, id .. " keeps its id in the catalog") end
for _, e in ipairs(RM.ICONS) do Check(G.ForIcon(e[1]) and G.ForIcon(e[1]).kind == "icon", "icon " .. e[1] .. " is in the catalog") end
Check(G.ForArt("reminder-low-mana").name == "Low mana" and G.ForArt("reminder-low-mana").category == "Character", "an entry reads back")
Check(G.ForArt("shield").id == "shield" and G.ForIcon("mage").id == "icon-mage", "stored values find their entries")
Check(G.Count() == #entries and G.Count("Equipment") > 5 and G.Count("General") >= 1, "counts")

local function Names(list) local out = {} for i, e in ipairs(list) do out[i] = e.id end return out end
Check(#G.Search("", "All") == #entries and #G.Search(nil, nil) == #entries, "nothing typed lists everything")
for _, cat in ipairs(DATA.categories) do
  local found = G.Search("", cat)
  Check(#found == G.Count(cat) and #found > 0, cat .. ": its pictures")
  for _, e in ipairs(found) do Check(e.category == cat, e.id .. " is in " .. cat) end
end
local mana = G.Search("mana")
Check(#mana >= 3, "mana finds the flask, the crystal and the empty vessel")
Check(mana[1].nameLower:find("mana", 1, true), "a name match comes first")
Check(#G.Search("MANA") == #mana, "case is ignored")
Check(#G.Search("low mana", "Character") >= 1 and G.Search("low mana", "Character")[1].id == "reminder-low-mana", "words combine, in a category")
Check(#G.Search("low mana", "Equipment") == 0, "a category narrows search")
Check(#G.Search("zzzzqq") == 0, "no match is an empty list")
Check(#G.Search("sword")[1] ~= nil and G.Search("sword")[1].id == "reminder-enchanted-sword", "search by name")
Check(#G.Search("rage") > 0 and #G.Search("poison") >= 3, "search by keyword")
Check(#G.Search("  ") == #entries, "blank is nothing typed")
Check(table.concat(Names(G.Search("potion")), ",") == table.concat(Names(G.Search("potion")), ","), "stable order")
Check(#G.Search("a b c d e f g h i j k") <= #entries, "very long queries are bounded")

---------------------------------------------------------------------------
-- The three modes are a view of the five stored ones; nothing saved changes
---------------------------------------------------------------------------
c.TwichUIDB.ui = { reminders = { version = 1, nextId = 1, list = {} } }
local function Make(display)
  local ok, id = RM.Create("custom")
  Check(ok, "a reminder is made")
  for k, v in pairs(display) do Check(RM.SetDisplay(id, k, v), "set " .. k) end
  return id
end
local function D(id) return RM.Get(id).display end

Check(G.UIMode("artworkText") == "imageText" and G.UIMode("iconText") == "imageText", "both picture-and-words modes are Image + text")
Check(G.UIMode("artwork") == "image" and G.UIMode("icon") == "image" and G.UIMode("text") == "text", "the others map as they read")
Check(G.UIMode("something else") == "imageText", "an unknown stored mode reads as the default")

-- every legacy mode: the picture is what it was, whatever the mode
local legacy = {
  { mode = "artworkText", art = "enchant", text = "Apply oil" },
  { mode = "artwork", art = "ammo" },
  { mode = "iconText", iconSource = "bundled", icon = "mage", text = "Staff" },
  { mode = "icon", iconSource = "item", item = 6948 },
  { mode = "text", text = "Only words" },
}
for _, spec in ipairs(legacy) do
  local id = Make(spec)
  local d = D(id)
  local e, source, name, from = G.Current(d)
  if spec.mode == "artworkText" or spec.mode == "artwork" then
    Check(source == "art" and e and e.target == spec.art and from == "TwichUI artwork", spec.mode .. ": artwork is what it was")
  elseif spec.icon then
    Check(source == "icon" and e and e.target == "mage" and name == "Arcane staff", spec.mode .. ": a TwichUI icon is what it was")
  elseif spec.item then
    Check(source == "item" and e == nil and from == "Game icon", spec.mode .. ": an item's icon is a game icon")
  end
  -- every mode and back again changes nothing but the stored mode
  local before = {}
  for k, v in pairs(d) do before[k] = v end
  for _, ui in ipairs({ "text", "image", "imageText", "text", "imageText" }) do
    Check(G.SetUIMode(id, ui), spec.mode .. " to " .. ui)
    local now = D(id)
    Check(G.UIMode(now.mode) == ui, spec.mode .. ": " .. ui .. " reads back")
    for k, v in pairs(before) do
      if k ~= "mode" then Check(now[k] == v, spec.mode .. " -> " .. ui .. ": " .. k .. " is kept") end
    end
  end
  if spec.mode ~= "text" then
    local final = D(id)
    local was = spec.mode
    -- coming back from Text only finds the same kind of picture
    local wasKind = (was == "artworkText" or was == "artwork") and "art" or "icon"
    Check(G.Source(final) == (wasKind == "icon" and spec.item and "item" or wasKind), was .. ": the picture's kind survives a round trip through Text only")
  end
end

-- text kept by every mode; image kept in Text only; size and colour untouched
local id = Make({ mode = "artworkText", art = "reminder-low-mana", text = "Drink up", size = 96, textColor = "ff112233" })
G.SetUIMode(id, "text")
Check(D(id).text == "Drink up" and D(id).art == "reminder-low-mana" and D(id).size == 96 and D(id).textColor == "ff112233", "Text only keeps the picture, size and colour")
G.SetUIMode(id, "image")
Check(D(id).mode == "artwork" and D(id).text == "Drink up" and D(id).art == "reminder-low-mana", "Image only keeps the words")
Check(not G.SetUIMode(id, "sideways") and D(id).mode == "artwork", "an unknown mode is refused")
Check(not G.SetUIMode("r999", "text"), "a reminder that is gone is refused")

---------------------------------------------------------------------------
-- Choosing is one checked change
---------------------------------------------------------------------------
local rev = RM.Rev and RM.Rev()
local told = 0
if RM.Subscribe then RM.Subscribe(function() told = told + 1 end) end
local before = told
id = Make({ mode = "artworkText", art = "shield", text = "Words", size = 80 })
before = told
local pick = G.ForArt("reminder-healing-light")
Check(G.Choose(id, pick), "choose artwork")
Check(D(id).art == "reminder-healing-light" and D(id).mode == "artworkText" and D(id).text == "Words" and D(id).size == 80, "artwork: set, the mode and the rest kept")
Check(told - before == 1, "one notification for the whole choice")
Check(G.Choose(id, G.ForIcon("mage")), "choose a TwichUI icon")
Check(D(id).mode == "iconText" and D(id).iconSource == "bundled" and D(id).icon == "mage" and D(id).art == "reminder-healing-light", "icon: the mode follows its source and the hidden artwork stays")
Check(G.Choose(id, G.ItemCandidate(6948)), "choose an item's icon")
Check(D(id).mode == "iconText" and D(id).iconSource == "item" and D(id).item == 6948, "item: stored the way the old editor stored it")
Check(G.Current(D(id)) == nil and select(2, G.Current(D(id))) == "item", "an item is a game icon")
Check(G.Choose(id, G.ForArt("ammo")), "back to artwork")
Check(D(id).mode == "artworkText" and D(id).art == "ammo" and D(id).item == 6948, "the item is kept hidden")
G.SetUIMode(id, "image")
G.Choose(id, G.ForArt("reminder-low-health"))
Check(D(id).mode == "artwork", "Image only stays image only")
G.SetUIMode(id, "text")
Check(G.Choose(id, G.ForArt("reminder-low-health")) and D(id).mode == "artworkText" and D(id).text == "Words", "a words-only reminder gets a picture and keeps its words")
local bad = D(id).art
Check(not G.Choose(id, { kind = "item", item = -5 }) and D(id).art == bad, "an item that can't be is refused")
Check(not G.Choose(id, { kind = "wat" }) and not G.Choose(id, nil) and not G.Choose("r999", pick), "nonsense is refused")
Check(G.ItemCandidate(0) == nil and G.ItemCandidate("12") == nil and G.ItemCandidate(2147483647) ~= nil, "item candidates are checked")
Check(G.SameCandidate(pick, G.ForArt("reminder-healing-light")) and not G.SameCandidate(pick, G.ForArt("ammo")) and G.SameCandidate(G.ItemCandidate(5), G.ItemCandidate(5))
  and not G.SameCandidate(G.ItemCandidate(5), G.ItemCandidate(6)) and G.SameCandidate(nil, nil) and not G.SameCandidate(nil, pick), "candidates compare")
Check(G.CandidateOf({ mode = "artwork", art = "ammo" }).id == "ammo" and G.CandidateOf({ mode = "icon", iconSource = "item", item = 9 }).item == 9, "the picker starts from what is stored")

-- the all-or-nothing change leaves a reminder alone when one value is refused
local keep = D(id).art
Check(not RM.SetDisplayMany(id, { art = "reminder-bedroll", size = 9999 }) and D(id).art == keep, "SetDisplayMany writes nothing when one value is refused")
Check(RM.SetDisplayMany(id, { art = "reminder-bedroll", size = 90 }) and D(id).art == "reminder-bedroll" and D(id).size == 90, "and everything when all are fine")
before = told
Check(RM.SetDisplayMany(id, { art = "reminder-bedroll" }) and told == before, "an unchanged value is not told")

-- artwork from a newer version (an id this one doesn't have) is reported, not changed
local gone = Make({ mode = "artwork", art = "reminder-not-in-this-version" })
local e, source, name = G.Current(D(gone))
Check(e == nil and source == "art" and name == "Artwork unavailable" and D(gone).art == "reminder-not-in-this-version", "unknown artwork keeps its id and reads as unavailable")

if failures == 0 then print("PASSED") else print(failures .. " FAILED") end
