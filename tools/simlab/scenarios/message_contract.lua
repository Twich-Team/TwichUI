-- Simulator lab diagnostic (docs/simulator-lab.md "Delayed failures"): what C_ChatInfo.SendAddonMessage in
-- wow-ui-sim accepts. Run by diagnose.sh with NO addons loaded, so nothing of TwichUI's can be the cause of what it
-- finds. It is a measurement of the simulator, not of the game: whether the game's own function accepts the same
-- bytes is not something this lab can say.
--
-- Method: call the function under pcall with strings of known byte content and record whether it raised, and what.
-- Expected values come from strict UTF-8 (Lab.Utf8Valid, the rule Rust's str::from_utf8 applies), so a "PASS" below
-- says the simulator refuses exactly the strings that are not UTF-8, at the argument position it names.
--
-- Nothing is received: the function's return value 0 means the simulator accepted the call, and nothing more. No
-- delivery to any other client, and no CHAT_MSG_ADDON, is tested or claimed.
local Check, Say = Lab.Check, Lab.Say

local function Try(fn, ...)
    local ok, result = pcall(fn, ...)
    return ok, result
end

-- [label] = the message bytes (argument 2). All synthetic.
local cases = {
    { "ascii",                           "hello" },
    { "2-byte sequence (U+00E9)",        "caf\xC3\xA9" },
    { "4-byte sequence (U+1F600)",       "\xF0\x9F\x98\x80" },
    { "highest scalar (U+10FFFF)",       "\xF4\x8F\xBF\xBF" },
    { "embedded NUL",                    "a\0b" },
    { "lone continuation byte 0x80",     "a\x80b" },
    { "byte 0xFF",                       "a\xFFb" },
    { "truncated 2-byte sequence",       "a\xC3" },
    { "overlong NUL (C0 80)",            "\xC0\x80" },
    { "overlong 3-byte (E0 80 80)",      "\xE0\x80\x80" },
    { "surrogate (ED A0 80)",            "\xED\xA0\x80" },
    { "above U+10FFFF (F4 90 80 80)",    "\xF4\x90\x80\x80" },
}

Say("window", "none", "no clock is advanced in this run")
for _, c in ipairs(cases) do
    local label, bytes = c[1], c[2]
    local ok, result = Try(C_ChatInfo.SendAddonMessage, "SimLabProbe", bytes, "PARTY")
    local valid = Lab.Utf8Valid(bytes)
    Say("contract", label, "len=" .. #bytes, "hex=" .. Lab.Hex(bytes), "strictUtf8=" .. tostring(valid),
        "accepted=" .. tostring(ok), "result=" .. tostring(result))
    Check("contract", "message arg 2, " .. label .. ": accepted exactly when strict UTF-8", valid, ok)
    if not ok then
        Check("contract", "message arg 2, " .. label .. ": error names argument 2", "string at argument 2 is not valid UTF-8", result)
    end
end

-- The other string arguments, and the sibling function, to see whether this is one check on one argument or the
-- binding layer's general rule for string parameters.
local ok1, r1 = Try(C_ChatInfo.SendAddonMessage, "p\xFF", "x", "PARTY")
Check("contract", "prefix (arg 1) not UTF-8: refused, names argument 1", "false string at argument 1 is not valid UTF-8", tostring(ok1) .. " " .. tostring(r1))
local ok3, r3 = Try(C_ChatInfo.SendAddonMessage, "SimLabProbe", "x", "PA\xFFTY")
Say("contract", "chat type (arg 3) not UTF-8", "accepted=" .. tostring(ok3), "result=" .. tostring(r3))
local ok4, r4 = Try(C_ChatInfo.SendAddonMessage, "SimLabProbe", "x", "WHISPER", "Na\xFFme")
Check("contract", "target (arg 4) not UTF-8: refused, names argument 4", "false string at argument 4 is not valid UTF-8", tostring(ok4) .. " " .. tostring(r4))
local okl, rl = Try(C_ChatInfo.SendAddonMessageLogged, "SimLabProbe", "a\xFFb", "PARTY")
Check("contract", "SendAddonMessageLogged applies the same rule to argument 2", "false string at argument 2 is not valid UTF-8", tostring(okl) .. " " .. tostring(rl))

-- Is the error raised by the function itself, or by something the error handler does? Here no handler is involved:
-- pcall received the message directly from the call.
Say("contract", "origin", "the error text above came back through pcall from the call itself, with no error handler involved")
Lab.Finish()
