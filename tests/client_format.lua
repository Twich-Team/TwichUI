-- Makes string.format refuse what the WoW: Forever client's refuses, so a mistake that only the client reports fails offline too.
-- OBSERVED (Test Lab run, client 1.60.1 build 70888, 2026-11-12): ("%d"):format(99999999999) and ("%d"):format(0/0) raise
-- "integer overflow attempting to store <value>"; plain Lua 5.1 prints a number for both without complaint. The exact limits are NOT known: this
-- uses the 32-bit range as the conservative reading (a Lab probe of the boundary is a client-API-probe item, testing roadmap M6). Use "%.0f" for
-- copper, seeds and anything else that can exceed 2^31 or be NaN (the Workshop's price and history code already does).
-- Loaded by the Lab and Workshop reference tests; it changes string.format for that test process only.
local real = string.format
function string.format(fmt, ...)
  if type(fmt) == "string" then
    local args, argi, i = { ... }, 0, 1
    while true do
      local s, e, conv = fmt:find("%%[%-%+ #0]*%d*%.?%d*([%a%%])", i)
      if not s then break end
      i = e + 1
      if conv ~= "%" then
        argi = argi + 1
        if conv == "d" or conv == "i" or conv == "c" or conv == "x" or conv == "X" or conv == "o" or conv == "u" then
          local v = args[argi]
          if type(v) == "number" and (v ~= v or v >= 2147483648 or v < -2147483648) then
            error("integer overflow attempting to store " .. tostring(v) .. " (format \"" .. fmt .. "\"; the client refuses this)", 2)
          end
        end
      end
    end
  end
  return real(fmt, ...)
end
