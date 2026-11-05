-- Reminders: the plain-text and display-value checks (reminders/Config.lua's RM.PlainText and RM.ValidDisplay).
-- The contract is Config.lua's own comments: PlainText trims, takes no control characters and no "|" (the game reads
-- "|" as markup, so it would change how the text is drawn), and counts whole characters, never part of one, against
-- max, returning the trimmed text or nil and a reason code ("empty", "characters", "long"). ValidDisplay says whether
-- a display value is usable per key. Pure functions, so a bare client is enough.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

for _, f in ipairs({ "reminders/Config.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
local R = c.TwichUI
local RM = R.Reminders
local MAX = RM.TEXT_MAX

---------------------------------------------------------------------------
-- 1. RM.PlainText: trims, rejects non-strings and empty text, rejects "|" and control characters
---------------------------------------------------------------------------
Check(RM.PlainText("  hello  ", MAX) == "hello", "leading and trailing whitespace is trimmed off")
Check(RM.PlainText("\t\nhi\n", MAX) == "hi", "tabs and newlines trim too")
local t, reason = RM.PlainText(nil, MAX)
Check(t == nil and reason == "empty", "a non-string (nil) is not text: nil, \"empty\"")
t, reason = RM.PlainText(42, MAX)
Check(t == nil and reason == "empty", "a non-string (number) is not text: nil, \"empty\"")
t, reason = RM.PlainText("", MAX)
Check(t == nil and reason == "empty", "empty text is refused: nil, \"empty\"")
t, reason = RM.PlainText("   ", MAX)
Check(t == nil and reason == "empty", "whitespace only is empty: nil, \"empty\"")
t, reason = RM.PlainText("", 120, true)
Check(t == "", "allowEmpty accepts the empty text and returns \"\"")
t, reason = RM.PlainText("   ", 120, true)
Check(t == "", "allowEmpty trims first, so whitespace only is \"\" too")
t, reason = RM.PlainText("a|b", MAX)
Check(t == nil and reason == "characters", "a \"|\" is markup to the game: nil, \"characters\"")
t, reason = RM.PlainText("a\1b", MAX)
Check(t == nil and reason == "characters", "a control character is refused: nil, \"characters\"")
t, reason = RM.PlainText(" a | ", MAX)
Check(t == nil and reason == "characters", "trimming first, then the \"|\" is still refused: nil, \"characters\"")

---------------------------------------------------------------------------
-- 2. RM.PlainText: whole characters, never part of one
---------------------------------------------------------------------------
local han = string.char(0xE4, 0xB8, 0xAD)   -- 汉, one code point in 3 bytes
Check(RM.PlainText(han, 1) == han, "one multibyte character fits a limit of 1 whole character")
t, reason = RM.PlainText(han .. han, 1)
Check(t == nil and reason == "long", "two whole characters exceed a limit of 1: nil, \"long\"")
t, reason = RM.PlainText(han:rep(RM.TEXT_MAX), MAX)
Check(t ~= nil and t == han:rep(RM.TEXT_MAX), "exactly RM.TEXT_MAX code points pass (360 bytes, so bytes are not counted)")
t, reason = RM.PlainText(han:rep(RM.TEXT_MAX + 1), MAX)
Check(t == nil and reason == "long", "one code point over RM.TEXT_MAX is too long: nil, \"long\"")
Check(RM.PlainText(string.rep("a", RM.TEXT_MAX), MAX) ~= nil, "exactly RM.TEXT_MAX ASCII characters pass")
t, reason = RM.PlainText(string.rep("a", RM.TEXT_MAX + 1), MAX)
Check(t == nil and reason == "long", "one ASCII character over RM.TEXT_MAX is too long: nil, \"long\"")

---------------------------------------------------------------------------
-- 3. RM.ValidDisplay: booleans only for boolean keys, whole numbers in RM.LIMITS for numeric keys
---------------------------------------------------------------------------
Check(RM.ValidDisplay("fade", true) and RM.ValidDisplay("fade", false), "fade (boolean default) accepts true and false")
Check(not RM.ValidDisplay("fade", 1) and not RM.ValidDisplay("fade", "true"), "fade refuses a number and a string")
Check(RM.ValidDisplay("keepAspect", true) and not RM.ValidDisplay("keepAspect", 0), "keepAspect is boolean too")
Check(RM.ValidDisplay("size", 16) and RM.ValidDisplay("size", 256), "size accepts its RM.LIMITS ends: 16 and 256")
Check(not RM.ValidDisplay("size", 15) and not RM.ValidDisplay("size", 257), "size refuses 15 and 257, outside its limits")
Check(not RM.ValidDisplay("size", 16.5), "size refuses a fractional number")
Check(not RM.ValidDisplay("size", "16") and not RM.ValidDisplay("size", nil), "size refuses a string and nil")
Check(RM.ValidDisplay("opacity", 10) and RM.ValidDisplay("opacity", 100), "opacity accepts its RM.LIMITS ends: 10 and 100")
Check(not RM.ValidDisplay("opacity", 9) and not RM.ValidDisplay("opacity", 101), "opacity refuses 9 and 101")
Check(RM.ValidDisplay("delay", 0) and RM.ValidDisplay("delay", 30), "delay accepts its RM.LIMITS ends: 0 and 30")
Check(not RM.ValidDisplay("delay", 31), "delay refuses 31, above its limit")
Check(RM.ValidDisplay("minShow", 0) and RM.ValidDisplay("minShow", 60), "minShow accepts its RM.LIMITS ends: 0 and 60")
Check(not RM.ValidDisplay("minShow", 60.5), "minShow refuses a fractional number")

---------------------------------------------------------------------------
-- 4. RM.ValidDisplay: textColor is 8-digit hex, enum keys accept only their CHOICES members
---------------------------------------------------------------------------
Check(RM.ValidDisplay("textColor", "fff0e8d2"), "textColor accepts an 8-digit hex string")
Check(not RM.ValidDisplay("textColor", "fff0e8"), "textColor refuses a 6-digit string")
Check(not RM.ValidDisplay("textColor", "fff0e8d"), "textColor refuses an odd-length string")
Check(not RM.ValidDisplay("textColor", "zzf0e8d2") and not RM.ValidDisplay("textColor", 0xfff0e8d2), "textColor refuses non-hex and a number")
Check(RM.ValidDisplay("mode", "artworkText") and RM.ValidDisplay("mode", "text"), "mode accepts its CHOICES members")
Check(not RM.ValidDisplay("mode", "nope") and not RM.ValidDisplay("mode", 1), "mode refuses a member it doesn't have and a number")
Check(RM.ValidDisplay("textPlace", "below") and RM.ValidDisplay("textPlace", "left"), "textPlace accepts its CHOICES members")
Check(not RM.ValidDisplay("textPlace", "BELOW"), "textPlace is case-sensitive: \"BELOW\" is not a member")
Check(RM.ValidDisplay("outline", "thick") and RM.ValidDisplay("outline", "none"), "outline accepts its CHOICES members")
Check(not RM.ValidDisplay("outline", "heavy"), "outline refuses a member it doesn't have")
Check(RM.ValidDisplay("panel", "framed") and RM.ValidDisplay("panel", "shade"), "panel accepts its CHOICES members")
Check(not RM.ValidDisplay("panel", "glass"), "panel refuses a member it doesn't have")
Check(RM.ValidDisplay("strata", "LOW") and RM.ValidDisplay("strata", "HIGH"), "strata accepts its CHOICES members")
Check(not RM.ValidDisplay("strata", "TOP"), "strata refuses a member it doesn't have")
Check(RM.ValidDisplay("font", "default"), "font (a string key) accepts a clean string")
Check(not RM.ValidDisplay("font", "") and not RM.ValidDisplay("font", "a|b"), "font refuses the empty string and a \"|\"")
Check(not RM.ValidDisplay("font", string.rep("f", 101)), "font refuses a string longer than 100 characters")

---------------------------------------------------------------------------
-- 5. RM.ValidDisplay: art and icon take a clean string (an unknown one is a reported problem, not a value changed);
--    text takes what PlainText allows; an unknown key is never usable
---------------------------------------------------------------------------
Check(RM.ValidDisplay("art", "shield") and RM.ValidDisplay("art", "ammo"), "art accepts a clean string")
Check(RM.ValidDisplay("art", "notInTheGallery"), "an unknown art id is still a usable string here: the reminder reports it, it is not quietly changed")
Check(not RM.ValidDisplay("art", "") and not RM.ValidDisplay("art", "a|b") and not RM.ValidDisplay("art", "a\1b"), "art refuses the empty string, a \"|\" and a control character")
Check(RM.ValidDisplay("icon", "reminderShow"), "icon accepts a clean string")
Check(not RM.ValidDisplay("icon", "") and not RM.ValidDisplay("icon", "a|b"), "icon refuses the empty string and a \"|\"")
Check(RM.ValidDisplay("text", "hi") and RM.ValidDisplay("text", ""), "text accepts clean text and the empty text (the default is \"\")")
Check(not RM.ValidDisplay("text", "a|b"), "text refuses a \"|\"")
Check(not RM.ValidDisplay("text", string.rep("a", RM.TEXT_MAX + 1)), "text refuses more than RM.TEXT_MAX characters")
Check(not RM.ValidDisplay("bogus", true) and not RM.ValidDisplay("item", 123), "an unknown display key is never usable")

if failures > 0 then print(failures .. " FAILED") os.exit(1) end
print("TEST_REMINDERS_TEXT PASSED")
