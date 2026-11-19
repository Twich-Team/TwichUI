-- Junk marking: the rule being edited. One draft over WorkshopLauncher's saved rules and condition tree, with undo
-- and redo, validation and the sentence that describes it. No frames: the rule builder window (JunkBuilder.lua)
-- draws this, and the tests drive it directly. Nothing here changes a saved rule until Save, and the tree helpers
-- (copy, move, evaluate, summary) are the launcher's, so the editor, the sentence and the marking engine agree.
local R = TwichUI
local S = {}
R.JunkSession = S

local MAX_HISTORY, MAX_RULES = 100, 8
local st          -- nil while closed: { index, baseline, draft, base, saved, undo, redo, target, revision, new }

local function L() return R.WorkshopLauncher end
local function T() return L().JunkTree end

-- What a stored rule keeps besides its tree: the pre-tree fields stay untouched so older saved data still reads.
local function Snap()
    return { name = st.draft.name, on = st.draft.on, tree = T().Copy(st.draft.tree) }
end
local function Same(a, b)
    return a.name == b.name and a.on == b.on and T().Equal(a.tree, b.tree)
end
local function Restore(snap)
    st.draft.name, st.draft.on, st.draft.tree = snap.name, snap.on, T().Copy(snap.tree)
end
local function Changed()
    st.revision = st.revision + 1
end
-- Record the state before an edit. Called only once the edit is known to be valid.
local function Remember(before)
    st.undo[#st.undo + 1] = before
    if #st.undo > MAX_HISTORY then table.remove(st.undo, 1) end
    st.redo = {}
    Changed()
end

local REFUSE = {
    full = "A rule holds at most 32 conditions and groups, four levels deep.",
    place = "That cannot go there.",
    closed = "No rule is open.",
    root = "The top level cannot be removed.",
}
S.REFUSE = REFUSE

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------
function S.Active() return st ~= nil end
function S.Index() return st and st.index end
function S.IsNew() return st ~= nil and st.new == true end
function S.Revision() return st and st.revision or 0 end
function S.Tree() return st and st.draft.tree end
function S.Name() return st and st.draft.name end
function S.On() return st and st.draft.on end

local function Open(index, rule, new, rows)
    local draft = {}
    for k, v in pairs(rule) do if k ~= "tree" then draft[k] = v end end
    draft.tree = T().FromRule(rule)
    if not draft.tree then return false end
    st = { index = index, baseline = rows, draft = draft, undo = {}, redo = {}, revision = 0, new = new, target = {} }
    st.saved = Snap()
    return true
end

-- Edit a saved rule.
function S.Begin(index)
    local rows, held = L().JunkRules()
    if held or not rows[index] then return false end
    return Open(index, rows[index], false, rows)
end

-- A new rule: off and empty, so unfinished work cannot mark anything.
function S.BeginNew(name)
    local rows, held = L().JunkRules()
    if held or #rows >= MAX_RULES then return false end
    local rule = L().NewJunkRule(name)
    return Open(#rows + 1, rule, true, rows)
end

-- A new rule that starts as a copy of the rule on screen (including unsaved edits). Off.
function S.BeginCopy()
    if not st then return false end
    local rows, held = L().JunkRules()
    if held or #rows >= MAX_RULES then return false end
    local rule = {}
    for k, v in pairs(st.draft) do rule[k] = v end
    rule.tree = T().Copy(st.draft.tree)
    rule.on = false
    local name = ((st.draft.name or "Rule") .. " copy"):sub(1, 60):gsub("[\192-\255][\128-\191]*$", "")
    rule.name = name
    if not Open(#rows + 1, rule, true, rows) then return false end
    -- The copy has content that exists nowhere yet, so it always counts as unsaved.
    st.saved = { name = nil, on = false, tree = { type = "group", match = "all", children = { { type = "empty" } } } }
    return true
end

function S.Cancel() st = nil end

function S.Dirty()
    return st ~= nil and not Same(Snap(), st.saved)
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
function S.Problems() return st and T().Problems(st.draft.tree) or {} end
function S.Summary() return T().Summary(st and st.draft.tree) end

-- "Its type is Gear and its quality is Poor" for the rail: the sentence without its lead-in.
function S.Brief(rule)
    local tree = rule and (rule.tree or T().FromRule(rule))
    if not tree or (tree.type == "group" and #tree.children == 0) then return "Nothing chosen yet" end
    local text = T().Summary(tree):gsub("^Mark an item as junk when ", ""):gsub("%.$", "")
    return text:sub(1, 1):upper() .. text:sub(2)
end

-- What the tester and the marking engine are given: the rule as drawn, switched on, on the live tree so a trace
-- can be read back node by node.
function S.TestRule()
    if not st then return nil end
    return { on = true, tree = st.draft.tree, kind = st.draft.kind }
end

-- Rows for the saved-rule list.
function S.Rows()
    local rows, held = L().JunkRules()
    local out = {}
    for i, r in ipairs(rows) do
        out[i] = { index = i, name = r.name or (r.kind and r.kind:sub(1, 1):upper() .. r.kind:sub(2)) or "Rule", on = r.on, brief = S.Brief(r) }
    end
    return out, held
end

---------------------------------------------------------------------------
-- Targets: the group a clicked condition is added to, kept as a path so it follows undo and redo.
---------------------------------------------------------------------------
local function ByPath(path)
    local node = st.draft.tree
    for _, i in ipairs(path or {}) do
        node = node.children and node.children[i]
        if not node or node.type ~= "group" then return nil end
    end
    return node
end
local function PathOf(node)
    local root = st.draft.tree
    if node == root then return {} end
    local function Walk(n, path)
        for i, c in ipairs(n.children or {}) do
            local p = { unpack(path) }
            p[#p + 1] = i
            if c == node then return p end
            local found = Walk(c, p)
            if found then return found end
        end
    end
    return Walk(root, {})
end
function S.Target()
    if not st then return nil end
    return ByPath(st.target) or st.draft.tree
end
function S.SetTarget(node)
    if not st or not node or node.type ~= "group" then return false end
    local path = PathOf(node)
    if not path then return false end
    st.target = path
    return true
end

---------------------------------------------------------------------------
-- Editing. Each returns true (or the new node) or false and a reason; a refused edit changes nothing.
---------------------------------------------------------------------------
-- New conditions start on the careful side: "is not" for the yes/no facts, Poor to Common for quality.
local function Make(key)
    if key == "all" or key == "any" then return { type = "group", match = key, children = {} } end
    if key == "kind" then return { type = "kind", value = "gear" } end
    if key == "quality" then return { type = "quality", min = 0, max = 1 } end
    if key == "wearable" or key == "upgrade" or key == "classReagent" or key == "profession" then
        return { type = key, value = false }
    end
end
S.Make = Make

local function Fits() return T().Copy(st.draft.tree) ~= nil end

function S.Add(key, group, slot)
    if not st then return false, REFUSE.closed end
    group = group or S.Target()
    if not T().Contains(st.draft.tree, group) or group.type ~= "group" then return false, REFUSE.place end
    local node = Make(key)
    if not node then return false, REFUSE.place end
    slot = slot or #group.children + 1
    if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > #group.children + 1 then return false, REFUSE.place end
    local before = Snap()
    table.insert(group.children, slot, node)
    if not Fits() then
        table.remove(group.children, slot)
        return false, REFUSE.full
    end
    Remember(before)
    -- A new group becomes the place the next condition goes: the natural next step after making one.
    if node.type == "group" then S.SetTarget(node) end
    return node
end

function S.Remove(node)
    if not st then return false, REFUSE.closed end
    if node == st.draft.tree then return false, REFUSE.root end
    local parent, at = T().Find(st.draft.tree, node)
    if not parent then return false, REFUSE.place end
    local before, targetNode = Snap(), S.Target()
    table.remove(parent.children, at)
    -- The group being added to may have gone with it.
    if T().Contains(node, targetNode) then S.SetTarget(parent) else S.SetTarget(targetNode) end
    Remember(before)
    return true
end

function S.Move(node, group, slot)
    if not st then return false, REFUSE.closed end
    local before, targetNode = Snap(), S.Target()
    if not T().Move(st.draft.tree, node, group, slot, true) then return false, REFUSE.place end
    S.SetTarget(targetNode)
    Remember(before)
    return true
end

-- One place up or down inside the same group.
function S.Shift(node, delta)
    if not st then return false, REFUSE.closed end
    local parent, at = T().Find(st.draft.tree, node)
    if not parent then return false, REFUSE.place end
    local to = at + delta
    if to < 1 or to > #parent.children then return false, REFUSE.place end
    -- Move takes the slot as it is before the node is lifted out.
    return S.Move(node, parent, delta > 0 and to + 1 or to)
end

-- Groups a condition could move into, with a readable label, for the Move menu.
function S.Destinations(node)
    local out = {}
    if not st then return out end
    local parent = T().Find(st.draft.tree, node)
    local count = 0
    local function Walk(n, depth)
        if n.type ~= "group" then return end
        local label
        if n == st.draft.tree then
            label = "Top level"
        else
            count = count + 1
            label = ("Group %d"):format(count)
        end
        if n ~= parent and T().Move(st.draft.tree, node, n, #n.children + 1, false) then
            out[#out + 1] = { node = n, label = string.rep("  ", depth) .. label .. (n.match == "any" and " (any of)" or " (all of)") }
        end
        for _, c in ipairs(n.children) do Walk(c, depth + 1) end
    end
    Walk(st.draft.tree, 0)
    return out
end

function S.Duplicate(node)
    if not st then return false, REFUSE.closed end
    if node == st.draft.tree then return false, REFUSE.root end
    local parent, at = T().Find(st.draft.tree, node)
    if not parent then return false, REFUSE.place end
    local copy = T().Copy(node)
    if not copy then return false, REFUSE.full end
    local before = Snap()
    table.insert(parent.children, at + 1, copy)
    if not Fits() then table.remove(parent.children, at + 1); return false, REFUSE.full end
    Remember(before)
    return copy
end

function S.SetMatch(group, match)
    if not st then return false, REFUSE.closed end
    if group.type ~= "group" or (match ~= "all" and match ~= "any") or not T().Contains(st.draft.tree, group) then return false, REFUSE.place end
    if group.match == match then return true end
    local before, targetNode = Snap(), S.Target()
    group.match, group.strict = match, nil
    S.SetTarget(targetNode)
    Remember(before)
    return true
end

local KIND = {}
for _, k in ipairs({ "gear", "materials", "recipes", "consumables", "other" }) do KIND[k] = true end
-- field: "value" (an item type, or yes/no as true/false), "min" or "max" for a quality range.
function S.Set(node, field, value)
    if not st then return false, REFUSE.closed end
    if not T().Contains(st.draft.tree, node) then return false, REFUSE.place end
    local before, targetNode = Snap(), S.Target()
    if node.type == "kind" and field == "value" and KIND[value] then
        if node.value == value then return true end
        node.value = value
    elseif node.type == "quality" and (field == "min" or field == "max") and type(value) == "number"
        and value % 1 == 0 and value >= 0 and value <= 5 then
        if node[field] == value then return true end
        node[field] = value
        -- Keep the range sensible by moving the other end along: choosing "from Rare" in Poor to Common gives Rare to Rare.
        if node.min > node.max then
            if field == "min" then node.max = value else node.min = value end
        end
    elseif (node.type == "wearable" or node.type == "upgrade" or node.type == "classReagent" or node.type == "profession")
        and field == "value" and type(value) == "boolean" then
        if node.value == value then return true end
        node.value = value
    else
        return false, REFUSE.place
    end
    S.SetTarget(targetNode)
    Remember(before)
    return true
end

function S.SetName(text)
    if not st or type(text) ~= "string" then return false, REFUSE.closed end
    text = text:gsub("[%c|]", ""):sub(1, 60):gsub("[\192-\255][\128-\191]*$", "")
    if text == "" or text == st.draft.name then return false end
    local before = Snap()
    st.draft.name = text
    Remember(before)
    return true
end

function S.SetOn(on)
    if not st or type(on) ~= "boolean" then return false, REFUSE.closed end
    if st.draft.on == on then return true end
    if on and #S.Problems() > 0 then return false, S.Problems()[1].text end
    local before = Snap()
    st.draft.on = on
    Remember(before)
    return true
end

---------------------------------------------------------------------------
-- History
---------------------------------------------------------------------------
function S.CanUndo() return st ~= nil and #st.undo > 0 end
function S.CanRedo() return st ~= nil and #st.redo > 0 end
local function Step(from, to)
    if not st or #from == 0 then return false end
    local targetNode = S.Target()
    local path = PathOf(targetNode)
    to[#to + 1] = Snap()
    Restore(table.remove(from))
    st.target = ByPath(path) and path or {}
    Changed()
    return true
end
function S.Undo() return st ~= nil and Step(st.undo, st.redo) end
function S.Redo() return st ~= nil and Step(st.redo, st.undo) end

---------------------------------------------------------------------------
-- Save and delete
---------------------------------------------------------------------------
local REASON = {
    held = "Saved rules are held for a newer version and cannot be changed.",
    stale = "Your saved rules changed somewhere else. Cancel, then reopen the rule.",
    invalid = "This rule could not be saved: check its name and conditions.",
    incomplete = "Add a condition to every group, or switch the rule off, then save.",
}
S.REASON = REASON

function S.Save()
    if not st then return false, REFUSE.closed end
    local rule = {}
    for k, v in pairs(st.draft) do rule[k] = v end
    rule.tree = T().Copy(st.draft.tree)
    if not rule.name or rule.name == "" then rule.name = "New rule" end
    local ok, why = L().SaveJunkRule(st.index, rule, st.baseline)
    if not ok then return false, REASON[why] or REASON.invalid end
    st.baseline = L().JunkRules()
    st.saved, st.new, st.undo, st.redo = Snap(), false, {}, {}
    Changed()
    return true
end

function S.Delete()
    if not st then return false, REFUSE.closed end
    if st.new then st = nil; return true end
    if not L().RemoveJunkRule(st.index, st.baseline) then return false, REASON.stale end
    st = nil
    return true
end
