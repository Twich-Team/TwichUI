-- TwichUI: Journey Chronicle, date filter
-- Which entries the window shows for a chosen local calendar day. Nothing here
-- touches the saved entries; it only reads their stored timestamps (entry.t).
-- A day is a number y*10000 + m*100 + d in the player's local time, taken from
-- date("*t", t). Days are compared and stepped as calendar dates, never by
-- adding 86400 seconds, so daylight-saving changes can't move a boundary.
-- The filter itself is kept in memory only; it is not saved.

local R = TwichUI
local C = R.Chronicle

local floor = math.floor

C.MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
local SHORT = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

function C.MakeDay(y, m, d) return y * 10000 + m * 100 + d end
function C.DayParts(day) return floor(day / 10000), floor(day / 100) % 100, day % 100 end

function C.DaysInMonth(y, m)
    if m == 2 then return (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)) and 29 or 28 end
    return (m == 4 or m == 6 or m == 9 or m == 11) and 30 or 31
end

-- Whole days since 1970-01-01 for a calendar date, and back.
local function ToDays(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = floor(y / 400)
    local yoe = y - era * 400
    local doy = floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
    return era * 146097 + yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy - 719468
end
local function FromDays(z)
    z = z + 719468
    local era = floor(z / 146097)
    local doe = z - era * 146097
    local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
    local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
    local mp = floor((5 * doy + 2) / 153)
    local d = doy - floor((153 * mp + 2) / 5) + 1
    local m = mp < 10 and mp + 3 or mp - 9
    local y = yoe + era * 400
    if m <= 2 then y = y + 1 end
    return y, m, d
end

-- The day n days after (or before, when negative) a day.
function C.AddDays(day, n)
    local y, m, d = C.DayParts(day)
    return C.MakeDay(FromDays(ToDays(y, m, d) + n))
end

-- 0 = Sunday ... 6 = Saturday.
function C.Weekday(y, m, d) return (ToDays(y, m, d) + 4) % 7 end

-- The local calendar day of a stored timestamp, or nil when it can't be read as a date.
function C.DayKey(t)
    if type(t) ~= "number" or t ~= t or t < 0 or t > 253370764800 then return nil end
    local ok, parts = pcall(date, "*t", t)
    if not ok or type(parts) ~= "table" then return nil end
    local y, m, d = parts.year, parts.month, parts.day
    if type(y) ~= "number" or type(m) ~= "number" or type(d) ~= "number" or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    return C.MakeDay(y, m, d)
end

function C.Today() return C.DayKey(time()) end

-- "Oct 02, 2026"
function C.FormatDay(day)
    local y, m, d = C.DayParts(day)
    return ("%s %02d, %d"):format(SHORT[m] or "?", d, y)
end

-- How many entries fall on each day: { [day] = count }, and how many have no usable date.
function C.DayCounts()
    local counts, undated = {}, 0
    local entries = C.Entries()
    for i = 1, #entries do
        local day = C.DayKey(entries[i].t)
        if day then counts[day] = (counts[day] or 0) + 1 else undated = undated + 1 end
    end
    return counts, undated
end

---------------------------------------------------------------------------
-- The filter (in memory only)
---------------------------------------------------------------------------
-- mode: "all", "day" (only that day) or "since" (that day and every later one)
local filter = { mode = "all", day = nil }

function C.GetFilter() return filter.mode, filter.day end
function C.FilterActive() return filter.mode ~= "all" end

function C.SetFilter(mode, day)
    if (mode == "day" or mode == "since") and type(day) == "number" then
        filter.mode, filter.day = mode, day
    else
        filter.mode, filter.day = "all", nil
    end
end
function C.ClearFilter() C.SetFilter("all") end

-- Whether an entry belongs in the current view. Entries without a usable date
-- are shown only under All time; they are never given an invented date.
function C.Matches(entry)
    if filter.mode == "all" then return true end
    local day = C.DayKey(entry.t)
    if not day then return false end
    if filter.mode == "day" then return day == filter.day end
    return day >= filter.day
end

-- "All time", "On Oct 02, 2026" or "Since Oct 02, 2026".
function C.FilterLabel()
    if filter.mode == "day" then return "On " .. C.FormatDay(filter.day) end
    if filter.mode == "since" then return "Since " .. C.FormatDay(filter.day) end
    return "All time"
end
