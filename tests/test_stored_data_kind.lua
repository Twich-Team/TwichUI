-- Addon data (read-only): SD.Kind's core decision - which globals count as
-- saved data and which are code. Saved data is plain: string, number and
-- boolean keys and values, and tables of those, with no metatable; a table
-- bigger than the look limit that is plain that far counts as data. Scalar
-- globals named ^SLASH_ or ^BINDING_ are code, not data.
dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", { "!!!TwichUI" })
for _, f in ipairs({"setup/StoredData.lua"}) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
local R = c.TwichUI
local SD = R.StoredData

---------------------------------------------------------------------------
-- Tables
---------------------------------------------------------------------------
-- plain: string, number and boolean keys and values, nested, no metatable
assert(SD.Kind("FooDB", {a = "x", b = {c = 1, d = {e = true}}, f = 2.5}) == "table",
  "a plain nested table of strings, numbers and booleans is data")
assert(SD.Kind("FooEmpty", {}) == "table", "an empty table is data")
assert(SD.Kind("FooMeta", setmetatable({}, {__index = {}})) == nil,
  "a table with a metatable is code, not data")
assert(SD.Kind("FooFn", {a = function() end}) == nil,
  "a table with a function value is code, not data")
assert(SD.Kind("FooKey", {[{}] = 1}) == nil,
  "a table with a table key is code, not data")
assert(SD.Kind("FooUd", {a = newproxy()}) == nil,
  "a table with a userdata value is code, not data")
local loop = {}; loop.self = loop
assert(SD.Kind("FooLoop", loop) == "table", "a table that contains itself is data, not an error")

-- LOOK_LIMIT is 5000 (setup/StoredData.lua:59): a bigger table that is plain
-- up to the limit counts as data, so the 5001st entry may be anything
local big = {}
for i = 1, 5000 do big[i] = i end
big[5001] = function() end
assert(SD.Kind("FooBig", big) == "table", "a table past the look limit that is plain that far is data")

---------------------------------------------------------------------------
-- Loose values and other types
---------------------------------------------------------------------------
assert(SD.Kind("FooSpeed", 1.5) == "value", "a number global is a loose value")
assert(SD.Kind("FooName", "hi") == "value", "a string global is a loose value")
assert(SD.Kind("FooFlag", false) == "value", "a boolean global is a loose value")
assert(SD.Kind("SLASH_FOO1", "/foo") == nil, "a SLASH_ name is a slash command, not data")
assert(SD.Kind("BINDING_HEADER_FOO", "Foo") == nil, "a BINDING_ name is a binding, not data")
assert(SD.Kind("FooFn", function() end) == nil, "a function global is not data")
assert(SD.Kind("FooNil", nil) == nil, "a nil global is not data")

print("TEST_STORED_DATA_KIND PASSED")
