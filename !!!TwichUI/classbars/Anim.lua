-- TwichUI: class resource bars, the one animation driver
-- Everything the bars animate (a fill easing to a new value, an effect's pulse or motes) is an object with a
-- Step(self, elapsed) function that returns true once it has finished. Add() puts it on this driver; Remove()
-- takes it off. The driver is one frame whose OnUpdate is set only while at least one object is on it and is
-- removed the moment the last one finishes, so nothing runs while the bars are idle, hidden or switched off.
-- Steps are told no more than MAX_STEP seconds at a time (a hitch does not make an effect jump), and the list is
-- bounded: an object that would be the MAX_ACTIVE + 1st is refused (the caller shows its end state at once).
-- A Step that raises an error is taken off the driver and the error reported once; it is never run again.
--
--   A.Add(obj)      true when obj is running (already was, or now is); false when the driver is full
--   A.Remove(obj)   stop obj; safe from inside a Step
--   A.Clear()       stop everything (the bars were switched off)
--   A.Count()       how many are running; 0 means the OnUpdate script is not set (A.Running())

local R = TwichUI
local Perf = R.Perf
local A = {}
R.ClassBarAnim = A

A.MAX_ACTIVE = 24
A.MAX_STEP = 0.1

local active, count = {}, 0
local driver
local inLoop = false

local function Compact()
    local keep = 0
    for i = 1, count do
        local obj = active[i]
        if obj.animating then
            keep = keep + 1
            active[keep] = obj
        end
    end
    for i = keep + 1, count do active[i] = nil end
    count = keep
end

local function Stop()
    if driver and driver:GetScript("OnUpdate") then driver:SetScript("OnUpdate", nil) end
end

local function OnUpdate(_, elapsed)
    if elapsed > A.MAX_STEP then elapsed = A.MAX_STEP end
    inLoop = true
    for i = 1, count do
        local obj = active[i]
        if obj and obj.animating then
            local ok, finished = Perf.Call("classbars.anim", pcall, obj.Step, obj, elapsed)
            if not ok then
                obj.animating = false
                R.Fault("class bar animation", finished)
            elseif finished then
                obj.animating = false
            end
        end
    end
    inLoop = false
    Compact()
    if count == 0 then Stop() end
end

function A.Add(obj)
    if obj.animating then return true end
    if inLoop then   -- stopped and started again inside one pass: it is still on the list, so it is not added twice
        for i = 1, count do
            if active[i] == obj then
                obj.animating = true
                return true
            end
        end
    end
    if count >= A.MAX_ACTIVE then return false end
    obj.animating = true
    count = count + 1
    active[count] = obj
    if not driver then driver = CreateFrame("Frame") end
    if not driver:GetScript("OnUpdate") then driver:SetScript("OnUpdate", OnUpdate) end
    return true
end

function A.Remove(obj)
    if not obj.animating then return end
    obj.animating = false
    if not inLoop then
        Compact()
        if count == 0 then Stop() end
    end
end

function A.Clear()
    for i = 1, count do
        active[i].animating = false
        active[i] = nil
    end
    count = 0
    Stop()
end

function A.Count() return count end

-- Whether the OnUpdate script is set. It must be false whenever Count() is 0.
function A.Running() return driver ~= nil and driver:GetScript("OnUpdate") ~= nil end
