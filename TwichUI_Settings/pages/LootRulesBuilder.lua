-- TwichUI settings: Loot Rolls › the "When an item matches" builder, in the Reminders builder's way of working.
-- A palette of condition kinds (click one to add it to the rule, or drag it to the place you want), the rule as a tree of cards and
-- boxes (a box is an all-of / any-of block, with its rail, fold and More menu), a grip on every card and box to drag it to another
-- place or into another box (a marker shows where it would land and nothing lands where it can't), and a More menu (or a right-click)
-- on each to duplicate, move up or down, move into a box, or remove. The geometry of a drag is RemindersRuleDrag's, over the virtual
-- drag of MagicInventoryDrag.lua; what a drop means is this file's, and every change goes through loot/Config.lua, which checks it again.
-- Edits are live, as in the rest of the Loot rules page: there is no draft to save. Nothing here rolls anything.

local R = TwichUI
local B = {}
R.LootRulesBuilder = B

local RAIL, INSET, HEAD_H, SEP_H, COND_H, ICON = 3, 11, 30, 16, 62, 22
local PALETTE_ROW_H, PALETTE_GAP = 30, 6
local MORE_W = 70
local BLOCK = "block"   -- the palette's own entry for an all-of / any-of block

local function Wg() return R.SettingsWidgets end
local function M() return R.SettingsMaterial end
local function LR() return R.LootRolls end
local function Ru() return R.LootRules end

local built, env
local parent
local palette, cards, groups, seps, hints = {}, {}, {}, {}, {}
local drag
local folded = {}                       -- path text -> true: boxes folded to one line (session only; cleared when the shape of the rule changes)
local state = { path = nil }
B.cards, B.groups, B.seps, B.hints, B.palette = cards, groups, seps, hints, palette

local function Key(path) return table.concat(path, ".") end
local function Copy(path) local out = {} for i, k in ipairs(path) do out[i] = k end return out end
local function Child(path, i) local out = Copy(path) out[#out + 1] = i return out end

-- the node of a view's tree at a path, with the list it sits in and its place there
local function NodeAt(view, path)
    local list = view.conditions
    local node, index
    for depth, k in ipairs(path) do
        node, index = list and list[k], k
        if depth < #path then list = node and node.type == "group" and node.conditions or nil end
    end
    return node, list, index
end

local function Truncate(text, n)
    text = tostring(text or "")
    if #text <= n then return text end
    return text:sub(1, n - 1) .. "…"
end

local function Say(text, tone) if env.Say then env.Say(text, tone) end end

-- Anything that changes the shape of the rule puts away what was folded (the places folded belong to are not the same any more).
local function Reshaped() folded = {} end

local function Changed() env.Changed() end

local function Did(ok, why)
    if not ok then Say(why or "That can't be done.", "warn") end
    return ok
end

---------------------------------------------------------------------------
-- What a drop means
---------------------------------------------------------------------------
-- The place a drag may land: nil when not (the rule changed since the drag began, the limits, a block into itself).
local function DropPlace(src, destination, slot)
    local id = env.Selected()
    if not (id and src and src.id == id and src.rev == LR().Rev()) then return nil end
    local v = LR().Rule(id)
    if not v then return nil end
    local Rules = Ru()
    if src.kind == BLOCK then
        if v.counts.groups >= Rules.MAX_GROUPS or #destination + 2 > Rules.MAX_DEPTH then return nil end
        return slot
    elseif src.kind then
        if v.counts.conditions >= Rules.MAX_CONDITIONS then return nil end
        return slot
    end
    if LR().CanMoveNode(id, src.path, destination, slot) then return slot end
end

local function Commit(src, destination, slot)
    local place = DropPlace(src, destination, slot)
    if not place then return end
    local id = env.Selected()
    if src.kind == BLOCK then
        Did(LR().AddGroup(id, destination, nil, place))
    elseif src.kind then
        local ok, why = LR().AddCondition(id, src.kind, destination, place)
        Did(ok, why)
    else
        Did(LR().MoveNode(id, src.path, destination, place))
    end
    Reshaped()
    Say(nil)
    Changed()
end

local function Payload(path, kind)
    local id = env.Selected()
    if not id then return end
    local v = LR().Rule(id)
    if not v then return end
    local label, icon
    if kind then
        if kind == BLOCK then label, icon = "All / any block", "lootRolls"
        else local t = Ru().TYPES[kind]; label, icon = t.label, t.icon end
    else
        local node = NodeAt(v, path)
        if not node then return end
        if node.type == "group" then label, icon = (node.match == "any" and "Any of these" or "All of these"), "lootRolls"
        else local t = Ru().TYPES[node.type]; label, icon = t and t.label or "Condition", t and t.icon end
    end
    return { id = id, rev = LR().Rev(), path = path and Copy(path) or nil, kind = kind, raw = path ~= nil or nil,
        art = function(tex, size) R.Icons.Apply(tex, icon or "lootRolls", size) end }, label
end

---------------------------------------------------------------------------
-- The More menu
---------------------------------------------------------------------------
local function Groups(list, path, out, depth)
    for i, node in ipairs(list) do
        if node.type == "group" then
            local at = Child(path, i)
            out[#out + 1] = { path = at, node = node }
            Groups(node.conditions or {}, at, out, depth + 1)
        end
    end
    return out
end

local function MenuFor(path)
    local id = env.Selected()
    local v = id and LR().Rule(id)
    if not (v and path) then return {} end
    local node, list, index = NodeAt(v, path)
    if not node then return {} end
    local out = {}
    local isGroup = node.type == "group"
    out[#out + 1] = { value = "dup", label = isGroup and "Duplicate block" or "Duplicate" }
    if index > 1 then out[#out + 1] = { value = "up", label = "Move up" } end
    if index < #list then out[#out + 1] = { value = "down", label = "Move down" } end
    local here = { unpack(path, 1, #path - 1) }
    if #path > 1 and LR().CanMoveNode(id, path, {}, #v.conditions + 1) then
        out[#out + 1] = { value = "to:", label = "Move out to the rule" }
    end
    for _, g in ipairs(Groups(v.conditions, {}, {}, 1)) do
        local key = Key(g.path)
        if Key(here) ~= key and LR().CanMoveNode(id, path, g.path, #(g.node.conditions or {}) + 1) then
            local phrase = Ru().Phrase(g.node) or "an empty block"
            out[#out + 1] = { value = "to:" .. key, label = ("Move into %s: %s"):format(g.node.match == "any" and "any of" or "all of", Truncate(phrase, 30)) }
        end
    end
    out[#out + 1] = { value = "remove", label = isGroup and "Remove block and what is in it" or "Remove" }
    return out
end

local function MenuPick(path, value)
    local id = env.Selected()
    if not (id and path and value) then return end
    local v = LR().Rule(id)
    if not v then return end
    local node, list, index = NodeAt(v, path)
    if not node then return end
    if value == "dup" then Did(LR().CopyNode(id, path))
    elseif value == "up" then Did(LR().MoveNode(id, path, { unpack(path, 1, #path - 1) }, index - 1))
    elseif value == "down" then Did(LR().MoveNode(id, path, { unpack(path, 1, #path - 1) }, index + 2))
    elseif value == "remove" then Did(LR().RemoveCondition(id, path))
    elseif value:sub(1, 3) == "to:" then
        local to = {}
        for k in value:sub(4):gmatch("%d+") do to[#to + 1] = tonumber(k) end
        local target = #to > 0 and NodeAt(v, to)
        local count = #to == 0 and #v.conditions or #((target and target.conditions) or {})
        Did(LR().MoveNode(id, path, to, count + 1))
    end
    Reshaped()
    Say(nil)
    Changed()
end
B.MenuFor, B.MenuPick = MenuFor, MenuPick

---------------------------------------------------------------------------
-- Building the frames
---------------------------------------------------------------------------
local function Grip(owner, getPath, label)
    local G = Wg()
    local grip = CreateFrame("Button", nil, owner)
    grip:SetSize(20, 24)
    for i = 1, 6 do
        local dot = G.Solid(grip, "ARTWORK", G.pal.bronzeText, 0.8)
        dot:SetTexture(R.PATH .. [[media\style-v2\switch-thumb.tga]])
        dot:SetVertexColor(0.64, 0.52, 0.34, 0.85)
        dot:SetSize(3, 3)
        dot:SetPoint("CENTER", i % 2 == 0 and 2 or -2, 5 - 5 * math.floor((i - 1) / 2))
    end
    G.Hover(grip, G.pal.text, 0.12)
    M().ContextTip(grip, label, "Drag to a highlighted edge or into a box. You can also move it with More.")
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function()
        local payload, name = Payload(getPath(), nil)
        if payload then drag:Start(payload, name) end
    end)
    grip:SetScript("OnDragStop", function() drag:Stop() end)
    return grip
end

local function MoreMenu(owner, getPath, width, compact)
    local G = Wg()
    local more = G.Dropdown(owner, width, function(value) MenuPick(getPath(), value) end, compact)
    more:SetValue(nil, compact and "···" or "More")
    more.menuWidth, more.menuAlignRight = 340, true
    more:SetChoices(function() return MenuFor(getPath()) end)
    return more
end

local function AddMenu(anchor, groupPath)
    local id = env.Selected()
    if not id then return end
    local choices = {}
    for _, kind in ipairs(Ru().ORDER) do choices[#choices + 1] = { value = kind, label = Ru().TYPES[kind].label } end
    Wg().ContextMenu(anchor, choices, function(kind)
        Did(LR().AddCondition(id, kind, groupPath))
        Changed()
    end)
end

local function AddBlock(groupPath)
    local id = env.Selected()
    if not id then return end
    Did(LR().AddGroup(id, groupPath))
    Reshaped()
    Changed()
end

local function MakeCard(i)
    local G = Wg()
    local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
    c.frame = c
    M().PanelFace(c, "walnut")
    M().MaterialHover(c)
    c.grip = Grip(c, function() return c.path end, "Move this condition")
    c.grip:SetPoint("TOPLEFT", 3, -6)
    c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetSize(ICON, ICON); c.icon:SetPoint("TOPLEFT", 28, -8)
    c.label = G.Text(c, "body"); c.label:SetPoint("TOPLEFT", 56, -8); c.label:SetWidth(170); c.label:SetWordWrap(false)
    c.op = G.Dropdown(c, 112, function(value) if c.path then env.Apply(env.Selected(), c.path, { op = value }) end end)
    c.value = G.Dropdown(c, 150, function(value)
        if not c.path then return end
        local kind, id = c.kind, env.Selected()
        if kind == "quality" or kind == "class" or kind == "armor" then
            env.Apply(id, c.path, { value = (value == "equipment") and value or tonumber(value) })
        elseif kind == "recipe" then env.Apply(id, c.path, { mode = value })
        elseif kind == "upgrade" or kind == "equippable" then env.Apply(id, c.path, { value = value == "true" })
        else env.Apply(id, c.path, { value = value }) end
    end)
    c.id = G.EditBox(c, 150, 22)
    c.id:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local item = env.ParseItem(self:GetText())
        if not (item and c.path) then Say("Type or paste an item link, or its number.", "warn") Changed() return end
        local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(item)
        env.Apply(env.Selected(), c.path, { id = item, name = type(name) == "string" and name or false })
    end)
    c.id:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Changed() end)
    c.neg = G.Checkbox(c, function(on) if c.path then env.Apply(env.Selected(), c.path, { negate = on or nil }) end end)
    c.negText = G.Text(c, "small"); c.negText:SetText("not")
    c.more = MoreMenu(c, function() return c.path end, 28, true)
    c.more:SetPoint("TOPRIGHT", -4, -5)
    c.remove = c.more   -- the one control at the right of a card: Remove is in its menu
    R.Interact.Tip(c.neg, "Not", "Turns the condition around: the rule applies when the item does NOT match it. An item the game hasn't described yet is still unknown, never a match.")
    M().ContextTip(c.more, "Condition actions", "Duplicate, move or remove this condition.")
    c:RegisterForClicks("RightButtonUp")
    c:SetScript("OnClick", function(_, button) if button == "RightButton" and c.path then c.more:OpenMenu() end end)
    cards[i] = c
    return c
end

local function MakeGroup(i, top)
    local G = Wg()
    local g = {}
    g.top = top
    g.box = CreateFrame("Frame", nil, parent)
    M().PanelFace(g.box, top and "espresso" or "well")
    g.frame = g.box
    g.rail = G.Solid(g.box, "ARTWORK", G.pal.bronzeText, 0.6)
    g.rail:SetWidth(RAIL)
    g.rail:SetPoint("TOPLEFT", 1, -1)
    g.rail:SetPoint("BOTTOMLEFT", 1, 1)
    g.heading = G.Text(g.box, "body"); g.heading:SetWordWrap(false)
    g.folded = G.Text(g.box, "small"); g.folded:SetWordWrap(false)
    g.empty = G.Text(g.box, "small"); g.empty:SetWordWrap(true)
    if not top then
        g.grip = Grip(g.box, function() return g.path end, "Move this block")
        g.fold = CreateFrame("Button", nil, g.box)
        g.fold:SetSize(20, 20)
        g.fold.down = G.Chevron(g.fold, g.fold, "CENTER", 0, 0, true, G.pal.tealHi)
        g.fold.up = G.Chevron(g.fold, g.fold, "CENTER", 0, 0, false, G.pal.tealHi)
        G.Hover(g.fold, G.pal.text, 0.06)
        g.fold:SetScript("OnClick", function()
            if not g.path then return end
            local key = Key(g.path)
            folded[key] = (not folded[key]) or nil
            Changed()
        end)
        M().ContextTip(g.fold, "Fold this block", "Folds the block to one line, or opens it again. Nothing in it changes.")
        g.more = MoreMenu(g.box, function() return g.path end, MORE_W, false)
        M().ContextTip(g.more, "More", "Duplicate this block, move it up or down or into another block, or remove it with what is in it.")
    end
    for _, match in ipairs({ "all", "any" }) do
        local seg = M().Segment(g.box, match == "all" and "All" or "Any", 46, function()
            if not env.Selected() then return end
            local ok = LR().SetMatch(env.Selected(), match, (not top) and g.path or nil)
            Did(ok)
            Changed()
        end)
        seg.SetOn = seg.SetSelected
        R.Interact.Tip(seg, match == "all" and "All of these" or "Any of these",
            match == "all" and "This is true when every one of the conditions in it is true." or "This is true when at least one of the conditions in it is true.")
        g["seg" .. match] = seg
    end
    g.add = G.Button(g.box, "+ Condition", 100, "secondary", function() AddMenu(g.add, (not top) and g.path or nil) end)
    g.addBlock = G.Button(g.box, "+ Block", 76, "secondary", function() AddBlock((not top) and g.path or nil) end)
    R.Interact.Tip(g.add, "Add a condition", "Adds a condition at the end of this " .. (top and "rule" or "block") .. ". Or click or drag one from the palette above.")
    R.Interact.Tip(g.addBlock, "Add a block", "Adds an all-of / any-of block here, up to three levels deep. Put conditions in it to combine them differently from the rest.")
    groups[i] = g
    return g
end

local function MakePaletteRow(i, kind)
    local G = Wg()
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    M().PanelFace(row, "walnut")
    M().MaterialHover(row)
    row.kind = kind
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(ICON, ICON); row.icon:SetPoint("LEFT", 8, 0)
    row.name = G.Text(row, "body"); row.name:SetPoint("LEFT", 8 + ICON + 8, 0); row.name:SetWordWrap(false)
    if kind == BLOCK then
        R.Icons.Apply(row.icon, "lootRolls", ICON)
        row.name:SetText("All / any block")
    else
        local t = Ru().TYPES[kind]
        R.Icons.Apply(row.icon, t.icon or "lootRolls", ICON)
        row.name:SetText(t.label)
    end
    row:SetScript("OnClick", function()
        local id = env.Selected()
        if not id then return end
        if kind == BLOCK then AddBlock(nil) else Did(LR().AddCondition(id, kind)); Changed() end
    end)
    M().ContextTip(row, kind == BLOCK and "All / any block" or Ru().TYPES[kind].label,
        kind == BLOCK and "Click to add a block to the rule, or drag it where you want it. A block combines the conditions in it as all-of or any-of."
            or "Click to add this condition to the end of the rule, or drag it where you want it.")
    drag:Bind(row, function() return Payload(nil, kind) end)
    palette[i] = row
    return row
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
local function Pooled(pool, i, make)
    local item = pool[i]
    if not item then item = make(); pool[i] = item end
    return item
end

local function Place(item, x, y)
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    item:Show()
end

local function LayoutCard(cond, path, c, x, y, w)
    local Rules = Ru()
    local t = Rules.TYPES[cond.type]
    c.path, c.kind, c.index = Copy(path), cond.type, path[#path]
    c:SetSize(w, COND_H - 4)
    Place(c, x, y)
    R.Icons.Apply(c.icon, t and t.icon or "lootRolls", ICON)
    c.label:SetText(t and t.label or "?")
    local cx = 30
    local hasOp = cond.type == "quality"
    c.op:SetShown(hasOp)
    if hasOp then
        local ops = env.Choices("op")
        c.op:SetWidth(112)
        c.op:SetChoices(ops); c.op:SetValue(cond.op, env.LabelOf(ops, cond.op))
        c.op:ClearAllPoints(); c.op:SetPoint("TOPLEFT", c, "TOPLEFT", cx, -30)
        cx = cx + 118
    end
    local width = math.max(90, w - cx - 12)
    if cond.type == "item" then
        c.value:Hide(); c.id:Show()
        c.id:SetWidth(width)
        c.id:ClearAllPoints(); c.id:SetPoint("TOPLEFT", c, "TOPLEFT", cx, -30)
        if not c.id:HasFocus() then
            c.id:SetText(cond.id and cond.id > 0 and ((type(cond.name) == "string" and cond.name ~= "" and cond.name) or ("item #" .. cond.id)) or "")
        end
    else
        c.id:Hide(); c.value:Show()
        local choices = env.Choices(cond.type, cond)
        c.value:SetWidth(width)
        c.value:SetChoices(choices)
        local value = env.ValueText(cond)
        c.value:SetValue(value, env.LabelOf(choices, value))
        c.value:ClearAllPoints(); c.value:SetPoint("TOPLEFT", c, "TOPLEFT", cx, -30)
    end
    c.neg:ClearAllPoints(); c.neg:SetPoint("TOPRIGHT", c, "TOPRIGHT", -(28 + 8 + 34), -8)
    c.neg:SetChecked(cond.negate == true)
    c.negText:ClearAllPoints(); c.negText:SetPoint("LEFT", c.neg, "RIGHT", 4, 0)
    c.more:SetShown(true)
end

-- One list of conditions: the rule's, or a box's. Returns the y below it. st counts what has been placed, so frames are reused in order.
local function LayoutList(list, match, path, depth, x, y, w, st, v)
    local G = Wg()
    for i, node in ipairs(list) do
        if i > 1 then
            st.sep = st.sep + 1
            local sep = Pooled(seps, st.sep, function() return G.Text(parent, "meta") end)
            sep:SetText(match == "any" and "or" or "and")
            Place(sep, x + 34, y + 1)
            y = y + SEP_H
        end
        local at = Child(path, i)
        if node.type == "group" then
            st.group = st.group + 1
            y = B.LayoutGroup(node, at, depth + 1, x, y, w, st, v, path, i) + 4
        else
            st.card = st.card + 1
            local c = Pooled(cards, st.card, function() return MakeCard(st.card) end)
            LayoutCard(node, at, c, x, y, w)
            drag:Row(c, path, i)
            y = y + COND_H
        end
    end
    return y
end

-- A box (or, with node == nil, the rule's own): its header, what is in it, and its buttons. Returns the y below it.
function B.LayoutGroup(node, path, depth, x, y, w, st, v, parentPath, indexInParent)
    local Rules = Ru()
    local top = node == nil
    -- the rule's own box is groups[1]; the boxes in it follow in reading order (st.group counts those already placed, this one included)
    local at = top and 1 or st.group + 1
    local g = Pooled(groups, at, function() return MakeGroup(at, top) end)
    local match = top and v.match or node.match
    local list = top and v.conditions or (type(node.conditions) == "table" and node.conditions or {})
    g.path = (not top) and Copy(path) or nil
    local key = (not top) and Key(path)
    local isFolded = (not top) and folded[key] == true
    g.box:SetWidth(w)
    Place(g.box, x, y)
    local rail = match == "any" and { 0.46, 0.53, 0.42 } or { 0.57, 0.46, 0.32 }
    g.rail:SetColorTexture(rail[1], rail[2], rail[3], 0.63)
    g.segall:SetOn(match ~= "any"); g.segany:SetOn(match == "any")
    -- the header
    local hx = 8
    g.segany:ClearAllPoints(); g.segall:ClearAllPoints()
    if top then
        g.heading:Hide(); g.folded:Hide()
        g.segany:SetPoint("TOPRIGHT", g.box, "TOPRIGHT", -8, -4)
        g.segall:SetPoint("RIGHT", g.segany, "LEFT", -4, 0)
        g.seglabel = g.seglabel or Wg().Text(g.box, "small")
        g.seglabel:SetText("Match")
        g.seglabel:ClearAllPoints(); g.seglabel:SetPoint("RIGHT", g.segall, "LEFT", -8, 0)
        g.seglabel:Show()
        g.heading:SetText("")
    else
        g.grip:ClearAllPoints(); g.grip:SetPoint("TOPLEFT", g.box, "TOPLEFT", 6, -3); g.grip:Show()
        g.fold:ClearAllPoints(); g.fold:SetPoint("TOPLEFT", g.box, "TOPLEFT", 28, -5); g.fold:Show()
        for _, t in ipairs(g.fold.down) do t:SetShown(isFolded) end
        for _, t in ipairs(g.fold.up) do t:SetShown(not isFolded) end
        g.more:ClearAllPoints(); g.more:SetPoint("TOPRIGHT", g.box, "TOPRIGHT", -6, -3); g.more:Show()
        g.segany:SetPoint("RIGHT", g.more, "LEFT", -10, 0)
        g.segall:SetPoint("RIGHT", g.segany, "LEFT", -4, 0)
        g.heading:SetText(match == "any" and "Any of these" or "All of these")
        g.heading:ClearAllPoints(); g.heading:SetPoint("TOPLEFT", g.box, "TOPLEFT", 54, -8); g.heading:Show()
    end
    g.segall:Show(); g.segany:Show()
    local cur = y + HEAD_H + 2
    local inner = x + INSET
    local cw = w - INSET - 8
    local n = #list
    if isFolded then
        g.folded:SetWidth(w - 64)
        g.folded:SetText(Truncate(Rules.Phrase(node) or "Not finished", 60))
        g.folded:ClearAllPoints(); g.folded:SetPoint("TOPLEFT", g.box, "TOPLEFT", 54, -HEAD_H - 4); g.folded:Show()
        g.empty:Hide(); g.add:Hide(); g.addBlock:Hide()
        cur = cur + 20
        g.box:SetHeight(cur - y + 2)
        drag:Group(g.box, path, n, depth)
        return cur + 2
    end
    g.folded:Hide()
    if n == 0 then
        g.empty:SetWidth(w - 30)
        g.empty:SetText(top and "Nothing yet. A rule with no conditions never acts: add the first one from the palette or below."
            or "Empty. Add a condition or remove this block: the rule stays unfinished until you do.")
        Wg().Color(g.empty, Wg().pal.stone)
        g.empty:ClearAllPoints(); g.empty:SetPoint("TOPLEFT", g.box, "TOPLEFT", 14, -(cur - y))
        g.empty:Show()
        cur = cur + math.max(16, g.empty:GetStringHeight() or 16) + 8
    else
        g.empty:Hide()
        cur = LayoutList(list, match, top and {} or path, depth, inner + 2, cur, cw - 2, st, v)
    end
    -- the box's own buttons
    g.add:ClearAllPoints(); g.add:SetPoint("TOPLEFT", g.box, "TOPLEFT", INSET + 2, -(cur - y))
    g.addBlock:ClearAllPoints(); g.addBlock:SetPoint("LEFT", g.add, "RIGHT", 6, 0)
    g.add:SetEnabled(v.counts.conditions < Rules.MAX_CONDITIONS)
    g.addBlock:SetEnabled(v.counts.groups < Rules.MAX_GROUPS and depth + 1 <= Rules.MAX_DEPTH)
    g.add:Show(); g.addBlock:Show()
    cur = cur + 34
    g.box:SetHeight(cur - y)
    drag:Group(g.box, top and {} or path, n, depth)
    if not top then drag:Row(g.box, parentPath, indexInParent, true) end
    return cur
end

-- The palette: every kind of condition, two to a row. Returns the y below it.
local function LayoutPalette(x, y, w)
    local G = Wg()
    local order = {}
    for _, kind in ipairs(Ru().ORDER) do order[#order + 1] = kind end
    order[#order + 1] = BLOCK
    B.paletteHelp = B.paletteHelp or G.Text(parent, "small")
    B.paletteHelp:SetText("Click, or drag into the rule")
    G.Color(B.paletteHelp, G.pal.stone)
    Place(B.paletteHelp, x, y)
    y = y + 20
    local cols = w >= 360 and 2 or 1
    local cw = (w - (cols - 1) * PALETTE_GAP) / cols
    for i, kind in ipairs(order) do
        local row = Pooled(palette, i, function() return MakePaletteRow(i, kind) end)
        local col, r = (i - 1) % cols, math.floor((i - 1) / cols)
        row:SetSize(cw, PALETTE_ROW_H)
        Place(row, x + col * (cw + PALETTE_GAP), y + r * (PALETTE_ROW_H + PALETTE_GAP))
        local full = false
        if kind == BLOCK then
            local v = state.view
            full = v.counts.groups >= Ru().MAX_GROUPS
        else
            full = state.view.counts.conditions >= Ru().MAX_CONDITIONS
        end
        row:SetEnabled(not full)
        row:SetAlpha(full and 0.5 or 1)
    end
    local rows = math.ceil(#order / cols)
    return y + rows * (PALETTE_ROW_H + PALETTE_GAP)
end

---------------------------------------------------------------------------
-- The public part
---------------------------------------------------------------------------
-- Makes the pieces. `host` is the frame everything is placed in; e is what the page lends: Selected(), Changed(), Say(text, tone), Apply(id, path,
-- fields), Choices(kind, cond), LabelOf(choices, value), ValueText(cond), ParseItem(text) and `clip` (the frame a drop may land in).
function B.Build(host, e)
    if built then return B end
    parent, env = host, e
    drag = R.RemindersRuleDrag.New(e.clip or host, DropPlace, Commit)
    B.drag = drag
    -- the top box is made first so the boxes after it, and the cards, draw above it
    MakeGroup(1, true)
    for i = 1, Ru().MAX_GROUPS do MakeGroup(i + 1, false) end
    for i = 1, Ru().MAX_CONDITIONS do MakeCard(i) end
    local order = {}
    for _, kind in ipairs(Ru().ORDER) do order[#order + 1] = kind end
    order[#order + 1] = BLOCK
    for i, kind in ipairs(order) do MakePaletteRow(i, kind) end
    built = true
    return B
end

-- Lays the builder out for a rule's view from y down; returns the y below it. w is the width it may use, x its left edge.
function B.Layout(v, x, y, w)
    state.view = v
    drag:ClearTargets()
    local st = { card = 0, group = 0, sep = 0 }
    y = LayoutPalette(x, y, w) + 4
    -- the rule's own box holds the whole tree
    local bottom = B.LayoutGroup(nil, {}, 1, x, y, w, st, v)
    for i = st.card + 1, #cards do cards[i].path = nil; cards[i].index = nil; cards[i]:Hide() end
    -- groups[1] is the rule's own box; the boxes in it are groups[2...]
    for i = st.group + 2, #groups do groups[i].path = nil; groups[i].box:Hide() end
    for _, g in ipairs(groups) do
        if not g.box:IsShown() then
            if g.grip then g.grip:Hide() end
            if g.fold then g.fold:Hide() end
            if g.more then g.more:Hide() end
        end
    end
    for i = st.sep + 1, #seps do seps[i]:Hide() end
    return bottom
end

-- Everything the builder drew is put away (no rule is open).
function B.Hide()
    if not built then return end
    if drag then drag:Cancel() end
    for _, c in ipairs(cards) do c.path = nil; c:Hide() end
    for _, g in ipairs(groups) do g.path = nil; g.box:Hide() end
    for _, s in ipairs(seps) do s:Hide() end
    for _, p in ipairs(palette) do p:Hide() end
    if B.paletteHelp then B.paletteHelp:Hide() end
end

B.DropPlace, B.Commit = DropPlace, Commit   -- for the tests: what a drop means, apart from where the pointer is

function B.CancelDrag()
    if drag then drag:Cancel() end
end

-- A different rule is open: what was folded was in the other.
function B.Reset() folded = {}; if drag then drag:Cancel() end end

function B.Folded(path) return folded[Key(path)] == true end
function B.Built() return built end
