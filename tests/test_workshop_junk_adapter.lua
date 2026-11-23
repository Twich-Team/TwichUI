-- The real shared adapter over the assignment contract used by EllesmereUI Bags.
local c = { TwichUI = {}, TwichUIDB = {}, EllesmereUIDB = { bagItemAssignments = {} } }
setmetatable(c, { __index = _G }); c._G = c
local assignments = c.EllesmereUIDB.bagItemAssignments
local hooks, changes, calls = 0, {}, 0
function c.hooksecurefunc(object, key, hook)
    hooks = hooks + 1
    local original = object[key]
    object[key] = function(...) local out = { original(...) }; hook(...); return unpack(out) end
end
c.C_AddOns = { IsAddOnLoaded = function() return true end }
local cm = { JUNK_KEY = 'Junk' }
c.EUI_CategoryManager = cm
function cm:IsJunkMarkerEnabled() return true end
function cm:IsJunk(id, quality) return assignments[id] == self.JUNK_KEY or not assignments[id] and quality == 0 end
function cm:AssignItem(id, key) calls = calls + 1; assignments[id] = key end
function cm:UnassignItem(id) calls = calls + 1; assignments[id] = nil end
local init, events
function c.TwichUI:OnInit(fn) init = fn end
function c.TwichUI:On(_, fn) events = fn end
local function Load()
    local chunk = assert(loadfile(ROOT .. 'modules/EllesmereJunk.lua')); setfenv(chunk, c); chunk()
    return c.TwichUI.EllesmereJunk
end
local ej = Load()
local allowed = {}
ej.OnManual(function(id) changes[id] = (changes[id] or 0) + 1 end)
assert(ej.Guard(function(id) return allowed[id] == true end) and hooks == 2)
assert(ej.Guard(function(id) return allowed[id] == true end) and hooks == 2, 'one hook pair per manager')
cm:UnassignItem(99)
cm:AssignItem(100, 'Keep')
assert(changes[99] == 1 and changes[100] == 1, 'manual decisions before the first auto scan are reported')
calls = 0
assert(ej.MarkOwned(101, 1) == 'marked' and ej.Owned(101))
assert(not cm:IsJunk(101, 1) and assignments[101] == 'Junk', 'pending owned marks cannot be sold')
assert(ej.Peek(101, 1) == 'already' and ej.MarkOwned(101, 1) == 'already' and calls == 1, 'guard cannot cause repeat marking')
allowed[101] = true; assert(cm:IsJunk(101, 1))
allowed[101] = nil; assert(not cm:IsJunk(101, 1))
assert(ej.UnmarkOwned(101) == 'unmarked' and not assignments[101] and not ej.Owned(101))
assert(not changes[101], 'system reconciliation is not a manual override')
assert(ej.MarkOwned(102, 1) == 'marked')
cm:AssignItem(102, 'Junk')
assert(not ej.Owned(102) and changes[102] == 1 and cm:IsJunk(102, 1), 'same-value manual Junk assignment takes ownership')
assert(ej.UnmarkOwned(102) == 'unowned' and assignments[102] == 'Junk')
assert(ej.MarkOwned(103, 1) == 'marked')
cm:UnassignItem(103)
assert(not ej.Owned(103) and changes[103] == 1, 'manual unmark takes ownership')
assert(ej.MarkOwned(104, 1) == 'marked')
cm:AssignItem(104, 'Keep')
assert(not ej.Owned(104) and ej.UnmarkOwned(104) == 'unowned' and assignments[104] == 'Keep')
assert(ej.MarkOwned(104, 1) == 'filed-elsewhere', 'Keep decisions remain filed')
assignments[105] = 'Junk'; assert(ej.MarkOwned(105, 1) == 'already' and not ej.Owned(105))
assert(ej.Mark(106, 1) == 'marked' and not ej.Owned(106) and cm:IsJunk(106, 1), 'Mage marks stay ordinary')
assert(ej.MarkOwned(107, 0) == 'already' and not ej.Owned(107), 'implicit grey junk is never claimed')
-- Reload means persisted flags with a fresh third-party manager and adapter.
assert(ej.MarkOwned(108, 1) == 'marked')
local saved = c.TwichUIDB.workshopJunkOwned
cm = { JUNK_KEY = 'Junk',
    AssignItem = function(_, id, key) assignments[id] = key end,
    UnassignItem = function(_, id) assignments[id] = nil end,
    IsJunkMarkerEnabled = cm.IsJunkMarkerEnabled,
    IsJunk = function(self, id) return assignments[id] == self.JUNK_KEY end }
c.EUI_CategoryManager = cm
ej = Load(); init()
assert(c.TwichUIDB.workshopJunkOwned == saved and ej.Owned(108) and not cm:IsJunk(108), 'reload withholds persisted marks before Advisor loads')
ej.Guard(function() return true end); assert(cm:IsJunk(108))
assert(ej.UnmarkOwned(108) == 'unmarked', 'persisted automatic marks can reconcile')
assert(ej.MarkOwned(113, 1) == 'marked')
assignments = { [113] = 'Junk', [114] = 'Keep' }
c.EllesmereUIDB.bagItemAssignments = assignments
assert(not ej.Owned(113) and ej.UnmarkOwned(113) == 'unowned' and assignments[113] == 'Junk',
    'same-ID assignments in a replacement table are not mistaken for owned marks')
assert(ej.MarkOwned(114, 1) == 'filed-elsewhere' and assignments[114] == 'Keep')
-- An assignment can complete before EllesmereUI notification code throws.
local assign, unassign = cm.AssignItem, cm.UnassignItem
ej.Guard(function() return false end)
cm.AssignItem = function(self, id, key) assign(self, id, key); error('notification after assignment') end
assert(ej.MarkOwned(115, 1) == 'marked' and ej.Owned(115))
assert(not cm:IsJunk(115) and assignments[115] == 'Junk', 'notification failure lost the selling guard')
cm.AssignItem = assign
assert(ej.UnmarkOwned(115) == 'unmarked', 'notification failure lost reconciliation ownership')
assert(ej.MarkOwned(116, 1) == 'marked')
cm.UnassignItem = function(self, id) unassign(self, id); error('notification after unassignment') end
assert(ej.UnmarkOwned(116) == 'unmarked' and not ej.Owned(116) and not assignments[116])
cm.UnassignItem = unassign

-- Missing optional integration methods fail closed without changing ordinary marking.
c.EUI_CategoryManager.UnassignItem = nil
assert(ej.MarkOwned(109, 1) == 'unavailable' and not assignments[109])
assert(ej.Mark(109, 1) == 'marked', 'legacy Mage marking needs no ownership support')
c.EUI_CategoryManager.UnassignItem = function(_, id) assignments[id] = nil end
local hook = c.hooksecurefunc
c.hooksecurefunc = nil
assert(ej.MarkOwned(110, 1) == 'unavailable' and not assignments[110])
c.hooksecurefunc = hook
c.TwichUIDB.workshopJunkOwned = 'future-or-invalid'
assert(ej.MarkOwned(111, 1) == 'unavailable' and c.TwichUIDB.workshopJunkOwned == 'future-or-invalid')
c.TwichUIDB.workshopJunkOwned = {}
for id = 1000, 3047 do c.TwichUIDB.workshopJunkOwned[id] = true end
assert(ej.MarkOwned(112, 1) == 'unavailable' and not assignments[112], 'ownership cannot grow past its bound')
print('PASSED Workshop junk adapter ownership, pending selling guard, manual Junk/Keep, reload and legacy compatibility')
