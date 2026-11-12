-- TwichUI settings: Magic Inventory (inventory/). A feature card with the switch, then a frame of this window's own:
--   * your rules, in priority order: on/off, name, what it matches, where it goes, what it keeps, and Up, Down, Edit,
--     Duplicate, Delete; New rule (from a template) and Preview (the review window, from your bags as they are now);
--   * the destinations: each named place's recipient or guild bank tab ON THIS CHARACTER (another character chooses
--     its own, unless you choose to use a recipient on all your characters);
--   * the Never transfer list;
--   * the private rule builder: items, destination, movement, limits and live review, with detailed disclosures.
-- Every change goes through inventory/Rules.lua, which checks it; nothing here moves an item, and choosing items from
-- your bags only names the kind of item (inventory/Picker.lua). Built the first time the page is shown; its controls
-- are kept by name and reused on every redraw, so redrawing never makes a second copy of anything.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.MagicInventoryPage = P

local W = 644
local PAD = 6
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local AMBER = { 0.93, 0.72, 0.38 }

local f, built
local height = 400
local queued, relayoutQueued = false, false
local task, actionsFor = "rules", nil
local pool = {}               -- [key] = a control, made once
local touched = {}            -- [key] = true for controls used by this draw
local selectedRule
local ruleGhost
local editing                 -- the rule being edited (a copy; saved only by Save), or nil for the list
local filterTab, filterQuery = "filters", ""
local itemAdvanced, destAdvanced, limitsAdvanced = false, false, false
local turnOn = false          -- the editor's "Turn this rule on" choice
local said, saidTone          -- a sentence under the list or the editor: what just happened, or why it didn't
local newDestName = {}        -- [kind] = text typed for a new destination

local function MI() return R.MagicInventory end
local function Wg() return R.SettingsWidgets end

---------------------------------------------------------------------------
-- Controls kept by name
---------------------------------------------------------------------------
local function Get(key, make)
    local c = pool[key]
    if not c then
        c = make()
        pool[key] = c
    end
    touched[key] = true
    c:Show()
    return c
end

local function Text(key, kind)
    return Get(key, function()
        local t = Wg().Text(f, kind or "body")
        t:SetJustifyH("LEFT")
        t:SetWordWrap(true)
        return t
    end)
end

local function Button(key, label, w, kind, onClick)
    local b = Get(key, function()
        local made = Wg().Button(f, label, w, kind, function(self) if self.onClick then self.onClick() end end)
        return made
    end)
    b.text:SetText(label)
    b:SetWidth(w)
    b.onClick = onClick
    b:SetEnabled(onClick ~= nil)
    return b
end

local function Check(key, onToggle, art)
    local c = Get(key, function()
        local toggle = function(v) local self = pool[key]; if self.onToggle then self.onToggle(v) end end
        if art and R.SettingsMaterial then return R.SettingsMaterial.Pill(f, toggle) end
        return Wg().Checkbox(f, toggle)
    end)
    c.onToggle = onToggle
    return c
end

local function Edit(key, w)
    return Get(key, function()
        local e = Wg().EditBox(f, w, 22)
        e:SetMaxLetters(64)
        return e
    end)
end

local function Icon(key)
    return Get(key, function()
        local b = CreateFrame("Button", nil, f, "BackdropTemplate")
        b:SetSize(26, 26)
        Wg().Surface(b, Wg().pal.well, 1, Wg().pal.control, 0.9)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        b:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
        b:SetScript("OnEnter", function(self)
            if not self.itemID then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) end
            if self.hint then GameTooltip:AddLine(self.hint, 0.93, 0.72, 0.38, true) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end)
end

local function At(c, x, y) c:ClearAllPoints(); c:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y) end
local function Wide(t, x, y, w) At(t, x, y); t:SetWidth(w or (W - x - PAD)) end
local function Tone(t, tone)
    local pal = Wg().pal
    Wg().Color(t, tone == "warn" and AMBER or (tone == "dim" and pal.textDim or (tone == "head" and pal.bronzeText or (tone == "quiet" and pal.stone or pal.text))))
end
local function H(t) return math.max(14, t:GetStringHeight() or 14) end

---------------------------------------------------------------------------
-- Redrawing: many changes are one redraw; a change of height asks the window to lay the page out again
---------------------------------------------------------------------------
function P.QueueRefresh()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        local ok, err = pcall(P.Refresh)
        if not ok then R.Fault("magic inventory settings", err) end
    end)
end

local function QueueRelayout()
    if relayoutQueued then return end
    relayoutQueued = true
    C_Timer.After(0, function()
        relayoutQueued = false
        local UI = R.SettingsUI
        if UI and UI.Refresh then UI.Refresh() end
    end)
end

function P.Height() return height end

-- The page's own drawing helpers, for MagicInventoryGuild.lua (the guild bank placement preview, drawn in this frame).
P.Kit = { Get = Get, Text = Text, Button = Button, Icon = Icon, At = At, Wide = Wide, Tone = Tone, H = H, W = W, PAD = PAD,
    Frame = function() return f end, Relayout = function() QueueRelayout() end }

local function Say(text, tone) said, saidTone = text, tone; P.QueueRefresh() end
P.Say = Say

---------------------------------------------------------------------------
-- Words for a rule
---------------------------------------------------------------------------
local EQUIP_TEXT = { equipment = "equipment", other = "not equipment" }
local BIND_TEXT = { boe = "binds when equipped (not yet bound)", nobind = "doesn't bind" }

function P.ItemsText(rule)
    local mi = MI()
    local parts = {}
    local cats = {}
    for _, key in ipairs(rule.cats) do cats[#cats + 1] = mi.CategoryName(key) or "a category this client doesn't name" end
    if #cats > 0 then parts[#parts + 1] = table.concat(cats, " or ") end
    local q = {}
    for _, n in ipairs(mi.QUALITY_ORDER) do if rule.qualities[n] then q[#q + 1] = mi.QualityName(n) end end
    if #q > 0 then parts[#parts + 1] = table.concat(q, " or ") .. " quality" end
    if EQUIP_TEXT[rule.equip] then parts[#parts + 1] = EQUIP_TEXT[rule.equip] end
    if BIND_TEXT[rule.bind] then parts[#parts + 1] = BIND_TEXT[rule.bind] end
    local text = table.concat(parts, " + ")
    local inc = 0
    for _ in pairs(rule.include) do inc = inc + 1 end
    if inc > 0 then text = text .. (text ~= "" and ", and " or "") .. ("%d listed %s"):format(inc, inc == 1 and "item" or "items") end
    local exc = 0
    for _ in pairs(rule.exclude) do exc = exc + 1 end
    if exc > 0 then text = text .. ("; never %d listed %s"):format(exc, exc == 1 and "item" or "items") end
    return text ~= "" and text or "Nothing chosen yet"
end

-- What a rule does, as a label: "Send by mail", "Deposit in bank", "Withdraw from bank", "Balance with guild bank" ...
local FLOW_KIND = {
    bank = { deposit = "Deposit in bank", withdraw = "Withdraw from bank", balance = "Balance with bank" },
    guild = { deposit = "Deposit in guild bank", withdraw = "Withdraw from guild bank", balance = "Balance with guild bank" },
}
function P.KindLabel(rule)
    local byFlow = FLOW_KIND[rule.kind]
    return byFlow and byFlow[rule.flow or "deposit"] or MI().KIND_LABEL[rule.kind]
end

function P.DestText(rule)
    local mi = MI()
    local kind = P.KindLabel(rule)
    if not mi.NEEDS_DEST[rule.kind] then return kind end
    local d = rule.dest and mi.Dest(rule.dest)
    if not d then return kind .. " \226\134\146 (choose one)", "warn" end
    local where = mi.Resolve(d.id)
    if not where then
        return ("%s \226\134\146 %s (choose %s on this character)"):format(kind, d.label, rule.kind == "mail" and "the recipient" or "the tab"), "warn"
    end
    if rule.kind == "mail" then return ("%s \226\134\146 %s%s"):format(kind, where.recipient, where.shared and " (all your characters)" or "") end
    return ("%s \226\134\146 <%s>, tab %d \"%s\""):format(kind, where.guild, where.tab, where.tabName or "?")
end

function P.KeepText(rule)
    if rule.kind == "never" then return "Never moved by any rule" end
    local withdraws = MI().Withdraws(rule)
    if rule.keep and rule.keep > 0 then
        if rule.flow == "withdraw" then return ("Topped up to %d of each matching item"):format(rule.keep) end
        if rule.flow == "balance" then return ("Kept at %d of each matching item, both ways"):format(rule.keep) end
        return ("%d of each matching item"):format(rule.keep)
    end
    return (rule.kind == "keep" or withdraws) and "Choose how many" or "None"
end

-- The whole rule as one plain sentence (the editor's Review step).
function P.Sentence(rule)
    local items = P.ItemsText(rule)
    if rule.kind == "never" then return ("Never move: %s. No rule, list or template moves these."):format(items) end
    if rule.kind == "keep" then return ("Keep in your bags: %s, %s. Other rules move only what is above that."):format(P.KeepText(rule):lower(), items) end
    local dest = P.DestText(rule)
    local keep = rule.keep > 0 and (" Keep %d of each in your bags."):format(rule.keep) or ""
    if rule.flow == "withdraw" then
        keep = rule.keep > 0 and (" Take out whole stacks until you carry %d of each, never more; what isn't there stays missing."):format(rule.keep) or ""
    elseif rule.flow == "balance" then
        keep = rule.keep > 0 and (" Keep %d of each in your bags: deposit what is above it, and take out whole stacks to reach it, never more."):format(rule.keep) or ""
    end
    if rule.kind == "guild" and rule.flow ~= "withdraw" and (rule.stack or 0) > 0 then keep = keep .. (" Stacks end at %d, and one smaller stack holds the rest."):format(rule.stack) end
    return ("%s: %s.%s It only moves when you open the %s, review it and press the action yourself."):format(dest, items, keep,
        rule.kind == "mail" and "mailbox" or (rule.kind == "bank" and "bank" or "guild bank"))
        .. (rule.kind == "mail" and " Whether a player can receive these, or who plays that character, isn't something TwichUI can check." or "")
        .. (rule.bind == "boe" and rule.kind == "mail" and " Whether an item can be disenchanted isn't checked." or "")
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local function TemplateChoices()
    local out = {}
    for _, t in ipairs(MI().TEMPLATES) do
        local rule = MI().FromTemplate(t.key)
        out[#out + 1] = { value = t.key, label = rule and rule.name or t.key, tooltip = t.about }
    end
    return out
end

local function StartEdit(rule)
    task = "rules"
    editing = rule
    selectedRule = rule.id
    filterTab, filterQuery = "filters", ""
    itemAdvanced, destAdvanced, limitsAdvanced = false, false, false
    turnOn = rule.enabled == true
    said = nil
    P.QueueRefresh()
    QueueRelayout()
end

local function NewFromTemplate(key)
    local mi = MI()
    local rule, destLabel = mi.FromTemplate(key)
    if not rule then return end
    if destLabel then
        local id, why = mi.DestNamed(rule.kind, destLabel)
        if not id then Say(why, "warn") return end
        rule.dest = id
    end
    StartEdit(rule)
end

local function ItemStrip(prefix, set, x, y, hint, onRemove)
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    table.sort(ids)
    local perRow = math.floor((W - x - PAD) / 30)
    for i, id in ipairs(ids) do
        local b = Icon(prefix .. i)
        local facts = MI().ItemFacts(id)
        b.tex:SetTexture(facts and facts.icon or QUESTION)
        b.itemID, b.hint = id, hint
        b.onClick = function() onRemove(id) end
        At(b, x + ((i - 1) % perRow) * 30, y + math.floor((i - 1) / perRow) * 30)
    end
    return #ids == 0 and 0 or (math.ceil(#ids / perRow) * 30)
end

local function AddById(box, onAdd)
    local id = MI().ParseItem(box:GetText() or "")
    if not id then Say("That isn't an item: paste its link or type its item ID.", "warn") return end
    box:SetText("")
    box:ClearFocus()
    onAdd(id)
end

local function DrawNever(y)
    local mi = MI()
    local t = Text("neverHead", "heading")
    Wide(t, PAD, y)
    t:SetText("Never transfer")
    Tone(t, "head")
    y = y + 18
    local d = Text("neverText", "small")
    Wide(d, PAD, y)
    d:SetText("Items on this list are never moved by any rule, even one that lists them. Kept for your whole account. Click an item to take it off.")
    Tone(d, "dim")
    y = y + H(d) + 6
    local set = {}
    for _, id in ipairs(mi.NeverList()) do set[id] = true end
    local h = ItemStrip("never", set, PAD, y, "Click to take it off the Never transfer list.", function(id) mi.SetNever(id, false) end)
    y = y + h + (h > 0 and 6 or 0)
    Button("neverPick", "Choose from bags", 140, "secondary", function()
        mi.Picker.Open({ purpose = "Never transfer: these kinds of item are never moved by any rule.", selected = set,
            onDone = function(chosen)
                for id in pairs(set) do if not chosen[id] then mi.SetNever(id, false) end end
                for id in pairs(chosen) do
                    local ok, why = mi.SetNever(id, true)
                    if not ok then Say(why, "warn") break end
                end
            end })
    end)
    At(pool.neverPick, PAD, y)
    local box = Edit("neverId", 160)
    At(box, PAD + 150, y + 1)
    box:SetScript("OnEnterPressed", function(self) AddById(self, function(id) local ok, why = mi.SetNever(id, true); if not ok then Say(why, "warn") end end) end)
    Button("neverAdd", "Add by ID or link", 140, "secondary", function()
        AddById(pool.neverId, function(id) local ok, why = mi.SetNever(id, true); if not ok then Say(why, "warn") end end)
    end)
    At(pool.neverAdd, PAD + 320, y)
    return y + 34
end

local function DrawDests(y)
    local mi = MI()
    local t = Text("destHead", "heading")
    Wide(t, PAD, y)
    t:SetText("Destinations on this character")
    Tone(t, "head")
    y = y + 18
    local d = Text("destText", "small")
    Wide(d, PAD, y)
    d:SetText("A rule sends to a named place. Who or which tab that is, is chosen here for this character only, so another character never mails to your choice unless you tick \"All my characters\". TwichUI checks a name's form, not whether the character exists or who plays it.")
    Tone(d, "dim")
    y = y + H(d) + 8
    local dests = mi.Dests()
    if #dests == 0 then
        local none = Text("destNone", "small")
        Wide(none, PAD, y)
        none:SetText("None yet: a mail or guild bank rule makes one.")
        Tone(none, "quiet")
        y = y + 20
    end
    for i, dest in ipairs(dests) do
        local key = "dest" .. i
        local name = Text(key .. "name", "body")
        Wide(name, PAD, y + 4, W - PAD * 2 - 20)
        name:SetText(dest.label)
        local where = mi.Resolve(dest.id)
        local value = Text(key .. "value", "small")
        Wide(value, PAD, y + 27, W - PAD * 2 - 20)
        if dest.kind == "mail" then
            value:SetText(where and ("Mail to: |cffffffff" .. where.recipient .. "|r" .. (where.shared and " (all your characters)" or "")) or "No recipient on this character")
            Tone(value, where and "dim" or "warn")
            y = y + 54
            local box = Edit(key .. "box", 140)
            At(box, PAD, y + 1)
            if not box:HasFocus() then box:SetText(where and where.recipient or "") end
            local all = Check(key .. "all", function(v) pool[key .. "all"].want = v; pool[key .. "all"]:SetChecked(v) end)
            At(all, PAD + 156, y + 3)
            if all.want == nil then all.want = where and where.shared or false end
            all:SetChecked(all.want)
            local allText = Text(key .. "allText", "small")
            allText:ClearAllPoints(); allText:SetPoint("LEFT", all, "RIGHT", 8, 0); allText:SetWidth(150)
            allText:SetText("All my characters")
            Tone(allText, "dim")
            local function Set()
                local text = pool[key .. "box"]:GetText() or ""
                local ok, why
                if text:match("^%s*$") then ok, why = mi.SetRecipient(dest.id, nil)
                else ok, why = mi.SetRecipient(dest.id, text, pool[key .. "all"].want) end
                pool[key .. "box"]:ClearFocus()
                if ok then
                    Say(why and ("\"%s\" now mails to %s%s."):format(dest.label, why, pool[key .. "all"].want and " on all your characters" or " on this character") or ("\"%s\" has no recipient now."):format(dest.label))
                else Say(why, "warn") end
                pool[key .. "all"].want = nil
            end
            box:SetScript("OnEnterPressed", Set)
            y = y + 28
            Button(key .. "set", "Save recipient", 120, "secondary", Set)
            At(pool[key .. "set"], PAD + 370, y - 28)
            R.Interact.Tip(pool[key .. "set"], "Save recipient", "Saves exactly this name for this destination. An empty box clears it. Mail always shows the recipient before anything is sent.")
        else
            y = y + 28
            -- the tab's own icon beside its name (a texture, so it shows wherever a texture does)
            local ic = Icon(key .. "tabIcon")
            ic:SetSize(20, 20)
            At(ic, PAD, y + 2)
            ic.itemID = nil
            ic.tex:SetTexture(where and where.tabIcon or QUESTION)
            ic:SetShown(where ~= nil)
            Wide(value, PAD + (where and 24 or 0), y + 5, 332)
            value:SetWordWrap(where == nil)   -- one line beside the icon: a long tab name is cut, not wrapped into the next row
            value:SetText(where and ("<%s>, tab %d \"%s\""):format(where.guild, where.tab, where.tabName or "?") or "No guild bank tab on this character")
            Tone(value, where and "dim" or "warn")
            local open = mi.Run.IsOpen("guild")
            local b = Button(key .. "use", "Use the tab shown now", 170, "secondary", open and function()
                local guild = MI().Plain((GetGuildInfo("player")))
                local tab = MI().Plain(GetCurrentGuildBankTab and GetCurrentGuildBankTab())
                local tabName, tabIcon
                if tab then tabName, tabIcon = GetGuildBankTabInfo(tab); tabName, tabIcon = MI().Plain(tabName), MI().Plain(tabIcon) end
                local ok, why = mi.SetGuildTab(dest.id, guild, tab, tabName, tabIcon)
                if ok then Say(("\"%s\" is now <%s>, tab %d \"%s\" on this character."):format(dest.label, guild, tab, tabName or "?"))
                else Say(why, "warn") end
            end or nil)
            At(b, PAD + 370, y)
            R.Interact.Tip(b, "Use the tab shown now", open and "Saves the guild and the tab the guild bank shows now." or "Open the guild bank on the tab you want, then press this. (Whether guild vaults exist on your realm isn't known to TwichUI.)")
            y = y + 28
        end
        Button(key .. "rename", "Rename", 80, "secondary", function()
            local text = pool[key .. "renameBox"] and pool[key .. "renameBox"]:GetText()
            local ok, why = mi.RenameDest(dest.id, text)
            if not ok then Say(why, "warn") end
        end)
        local rb = Edit(key .. "renameBox", 140)
        At(rb, PAD, y + 1)
        if not rb:HasFocus() then rb:SetText(dest.label) end
        At(pool[key .. "rename"], PAD + 146, y)
        Button(key .. "clear", "Clear here", 90, "secondary", where and function()
            if dest.kind == "mail" then mi.SetRecipient(dest.id, nil) else mi.SetGuildTab(dest.id, nil) end
            Say(("\"%s\" has nothing chosen on this character now."):format(dest.label))
        end or nil)
        At(pool[key .. "clear"], PAD + 232, y)
        if dest.kind == "guild" then
            -- a tab of this character's guild, from what the guild bank showed (now, or when it was last open)
            local dd = Get(key .. "tabs", function() return Wg().Dropdown(f, 200, function(v) pool[key .. "tabs"].onPick(v) end) end)
            local guildName = mi.Plain((IsInGuild and IsInGuild() and GetGuildInfo and (GetGuildInfo("player"))) or nil)
            dd:SetChoices(function()
                local out = {}
                local tabs = type(guildName) == "string" and mi.GuildTabsSeen(guildName) or {}
                for i = 1, mi.MAX_GUILD_TABS do
                    local t = tabs[i]
                    if t then
                        out[#out + 1] = { value = i, label = ("%d  %s"):format(i, t.name),
                            tooltip = "Tab names as the guild bank last showed them." }
                    end
                end
                return out
            end)
            dd.onPick = function(i)
                local t = type(guildName) == "string" and mi.GuildTabsSeen(guildName)[i]
                if not t then Say("Open the guild bank once so its tabs are known.", "warn") return end
                local ok, why = mi.SetGuildTab(dest.id, guildName, i, t.name, t.icon)
                if ok then Say(("\"%s\" is now <%s>, tab %d \"%s\" on this character."):format(dest.label, guildName, i, t.name))
                else Say(why, "warn") end
            end
            dd:SetValue(nil, type(guildName) ~= "string" and "Not in a guild" or (next(mi.GuildTabsSeen(guildName)) and "Choose a tab..." or "Open the guild bank once"))
            At(dd, PAD + 330, y)
        end
        Button(key .. "delete", "Remove", 80, "danger", function()
            R.Interact.Confirm("TWICHUI_MI_DEST_DELETE", ("Remove the destination \"%s\"?\n\nRules that send to it stay in your list, turned off, until you choose another destination for them. Other characters' choices for it are left in your saved data."):format(dest.label),
                function() mi.DeleteDest(dest.id) end, { accept = "Remove" })
        end)
        At(pool[key .. "delete"], W - PAD - 80, y)
        y = y + 36
    end
    return y
end

---------------------------------------------------------------------------
-- The rules table: one row a rule, in priority order, with columns, banding and drag to reorder
---------------------------------------------------------------------------
local ROW_H = 70
local query, ruleFilter = "", "all"
local priorities, filtered = {}, false
local COL = {                    -- x, width (left edge of the page frame); the buttons start at BTN_X
    grip = { 8, 10 }, num = { 22, 22 }, on = { 44, 18 }, name = { 68, 104 }, items = { 176, 108 },
    action = { 288, 54 }, to = { 346, 76 }, keep = { 426, 26 },
}
local ACTION_SHORT = { mail = "Mail", keep = "Keep", never = "Never" }
local FLOW_SHORT = { deposit = "Deposit", withdraw = "Withdraw", balance = "Balance" }
local dropAt                     -- the row a drag would put the rule in, or nil

-- Short cells for the table; the row's tooltip has the full words (P.ItemsText, P.DestText, P.KeepText).
function P.RowCells(rule)
    local mi = MI()
    local to, tone = rule.kind == "bank" and "Bank" or "-", nil
    if mi.NEEDS_DEST[rule.kind] then
        local d = rule.dest and mi.Dest(rule.dest)
        local where = d and mi.Resolve(d.id)
        if not d then to, tone = "Choose one", "warn"
        elseif not where then to, tone = d.label, "warn"
        elseif rule.kind == "mail" then to = where.recipient
        else to = ("Tab %d"):format(where.tab) end
    end
    local keep = "-"
    if rule.kind == "never" then keep = "All"
    elseif rule.keep and rule.keep > 0 then keep = tostring(rule.keep)
    elseif rule.kind == "keep" or mi.Withdraws(rule) then keep, tone = "?", tone or "warn" end
    local action = mi.HAS_FLOW[rule.kind] and FLOW_SHORT[rule.flow or "deposit"] or ACTION_SHORT[rule.kind] or rule.kind
    return action, to, keep, tone
end

-- Presentation-only art adapters. These never classify items or change category keys.
local function Painted(name) return [[media\icons\magic-]] .. name .. "-small" end
local NPC = [[media\npcs\]]
local QUALITY_ART = { [0] = Painted("quality-poor"), [1] = Painted("quality-common"), [2] = Painted("quality-uncommon"), [3] = Painted("quality-rare"), [4] = Painted("quality-epic") }
local CATEGORY_ART = {
    ["7:5"] = NPC .. "cloth-bolts-small", ["7:6"] = Painted("leather"), ["7:7"] = Painted("ore"), ["7:9"] = Painted("herbs"),
    ["0:1"] = [[media\healerwatch\vessel-small]], ["0:2"] = Painted("elixir"), ["0:3"] = Painted("elixir"),
    ["0:4"] = NPC .. "sealed-scroll-small", ["0:5"] = NPC .. "bread-and-tankard-small", ["0:7"] = NPC .. "cloth-bolts-small",
    ["3"] = Painted("quality-rare"), ["6"] = NPC .. "arrow-and-cartridge-small", ["5"] = NPC .. "reagent-pouch-small",
    ["9"] = NPC .. "sealed-scroll-small", ["15"] = NPC .. "leather-backpack-small",
}
function P.CategoryArtwork(key)
    if CATEGORY_ART[key] then return CATEGORY_ART[key] end
    local class = key:match("^(%d+)")
    if class == "9" then return CATEGORY_ART["9"] end
    -- Other available subclasses are named by this client. Family artwork is optional; unknown or
    -- localized names use a neutral class illustration rather than inventing a category identity.
    local name = (MI().CategoryName(key) or ""):lower()
    if name:find("inscription", 1, true) then return NPC .. "sealed-scroll-small" end
    local families = { { "enchant", "enchanting" }, { "element", "elemental" }, { "explos", "explosives" }, { "device", "parts" }, { "part", "parts" }, { "cooking", "food" }, { "meat", "food" }, { "potion", "potion" }, { "elixir", "elixir" }, { "flask", "elixir" }, { "cloth", "cloth" }, { "leather", "leather" }, { "herb", "herbs" }, { "metal", "ore" }, { "stone", "ore" }, { "jewel", "gem" } }
    for _, family in ipairs(families) do
        if name:find(family[1], 1, true) then
            if family[2] == "cloth" then return NPC .. "cloth-bolts-small" end
            if family[2] == "food" then return NPC .. "bread-and-tankard-small" end
            if family[2] == "potion" then return [[media\healerwatch\vessel-small]] end
            if family[2] == "gem" then return QUALITY_ART[3] end
            return Painted(family[2])
        end
    end
    return CATEGORY_ART[class] or NPC .. "reagent-pouch-small"
end

local function RuleArtwork(rule)
    local id = next(rule.include or {})
    local facts = id and MI().ItemFacts(id)
    local icon = facts and facts.icon or (id and C_Item.GetItemIconByID(id))
    if icon then return icon end
    if rule.kind == "never" or rule.equip == "equipment" then return R.PATH .. [[media\npcs\sword-and-shield]] end
    if #(rule.cats or {}) == 1 then return R.PATH .. P.CategoryArtwork(rule.cats[1]):gsub("%-small$", "") end
    if rule.kind == "keep" and #(rule.cats or {}) == 0 then return R.PATH .. [[media\npcs\leather-backpack]] end
    return R.PATH .. [[media\icons\magicReagents]]
end

-- Native item art has an opaque square tile. Keep the recognizable item in a portrait silhouette;
-- the transparent TwichUI illustrations retain their own shape. Item-picker wells keep the full icon.
local function PaintRuleArtwork(texture, rule)
    local path = RuleArtwork(rule)
    texture:SetTexture(path)
    local native = type(path) == "number" or (type(path) == "string" and path:sub(1, #R.PATH) ~= R.PATH)
    if native and not texture.itemMask then
        local mask = texture:GetParent():CreateMaskTexture(nil, "ARTWORK")
        if mask then
            mask:SetTexture([[Interface\CharacterFrame\TempPortraitAlphaMask]], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(texture)
            texture.itemMask = mask
        end
    end
    if texture.itemMask and native ~= texture.maskApplied then
        if native then texture:AddMaskTexture(texture.itemMask) else texture:RemoveMaskTexture(texture.itemMask) end
        texture.maskApplied = native
    end
end

local function RowTip(self)
    local rule = self.rule
    if not rule then return end
    local mi = MI()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(("%d.  %s"):format(self.index or 0, rule.name))
    GameTooltip:AddLine("Items: " .. P.ItemsText(rule), 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine("Destination: " .. (P.DestText(rule)), 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine("Keep: " .. P.KeepText(rule), 0.9, 0.9, 0.9, true)
    if rule.kind == "guild" and (rule.stack or 0) > 0 then GameTooltip:AddLine("Target stack size: " .. rule.stack, 0.9, 0.9, 0.9, true) end
    local problem = select(2, mi.Problem(rule, false))
    if problem then GameTooltip:AddLine(problem, AMBER[1], AMBER[2], AMBER[3], true) end
    GameTooltip:AddLine("Drag the row to change its priority.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function RowFrame(i)
    return Get("tr" .. i, function()
        local row = CreateFrame("Button", nil, f)
        row:SetHeight(ROW_H)
        if R.SettingsMaterial then R.SettingsMaterial.PanelFace(row, "walnut"); R.SettingsMaterial.ReminderRow(row) end
        row:SetFrameLevel(f:GetFrameLevel() + 1)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.hover:SetAllPoints()
        row.hover:Hide()
        row.grip = {}
        for k = 0, 5 do
            local g = row:CreateTexture(nil, "ARTWORK")
            g:SetSize(2, 2)
            g:SetPoint("LEFT", row, "LEFT", COL.grip[1] + (k % 2) * 5, 5 - math.floor(k / 2) * 5)
            row.grip[k + 1] = g
        end
        row:SetScript("OnClick", function(self)
            StartEdit(MI().Rule(self.rule.id))
        end)
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnEnter", function(self) if self.sel then self.sel:Show() end; RowTip(self) end)
        row:SetScript("OnLeave", function(self) self.hover:Hide(); if self.sel then self.sel:SetShown(selectedRule == (self.rule and self.rule.id)) end; GameTooltip:Hide() end)
        row:SetScript("OnDragStart", function(self) if self.rule then P.StartRuleDrag(self) end end)
        row:SetScript("OnDragStop", function() P.Drag.Stop() end)
        return row
    end)
end

local function DropMark()
    return Get("dropMark", function()
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(Wg().pal.teal[1], Wg().pal.teal[2], Wg().pal.teal[3], 1)
        t:SetHeight(2)
        return t
    end)
end

local rowCount = 0
local function RowUnderPointer()
    for i = 1, rowCount do
        local row = pool["tr" .. i]
        if row and row:IsShown() and row:IsMouseOver() then return i end
    end
end

-- Near the top or bottom edge of the view while dragging, the page scrolls so a far row can be reached.
local function AutoScroll()
    local p = f:GetParent()
    while p and not p.GetVerticalScroll do p = p.GetParent and p:GetParent() or nil end
    if not (p and p.GetTop and p:GetTop()) then return end
    local _, cy = GetCursorPosition()
    cy = cy / (p:GetEffectiveScale() or 1)
    local top, bottom = p:GetTop(), p:GetBottom()
    local speed = 0
    if cy > top - 28 then speed = -((cy - (top - 28)) / 28 * 14)
    elseif cy < bottom + 28 then speed = ((bottom + 28) - cy) / 28 * 14 end
    if speed == 0 then return end
    local most = p:GetVerticalScrollRange() or 0
    p:SetVerticalScroll(math.max(0, math.min(most, p:GetVerticalScroll() + speed)))
end

local function ShowDropMark(place, from)
    dropAt = place
    local mark = DropMark()
    local row = place and pool["tr" .. place]
    if not row then mark:Hide(); return end
    mark:Show()
    mark:ClearAllPoints()
    -- moving up lands above that row, moving down lands below it: the line is where the rule will be
    local y = row.y + ((place > from) and row:GetHeight() or 0)
    mark:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y + 1)
    mark:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y + 1)
end

function P.StartRuleDrag(row)
    if filtered then Say("Clear search and filters before changing priority.", "warn"); return end
    if GetCursorInfo and GetCursorInfo() then
        Say("You are holding an item. Put it down first; nothing was changed.", "warn")
        return
    end
    local rule, from = row.rule, row.index
    GameTooltip:Hide()
    local ghost, offset
    local x, y
    if GetCursorPosition then x, y = GetCursorPosition() end
    local left, top = row:GetLeft(), row:GetTop()
    if x and y and left and top then
        if not ruleGhost then
            ruleGhost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            if R.SettingsMaterial then R.SettingsMaterial.PanelFace(ruleGhost, "walnut") end
            if R.SettingsCraft then R.SettingsCraft.Sheet(ruleGhost, "selection", { layer = "BACKGROUND", sub = 1, corner = 12 }) end
            ruleGhost:SetFrameStrata("TOOLTIP"); ruleGhost:EnableMouse(false)
            ruleGhost.icon = ruleGhost:CreateTexture(nil, "ARTWORK"); ruleGhost.icon:SetPoint("LEFT", 45, 0); ruleGhost.icon:SetSize(36, 36)
            ruleGhost.priority = Wg().Text(ruleGhost, "small"); ruleGhost.priority:SetPoint("LEFT", 22, 0)
            ruleGhost.name = Wg().Text(ruleGhost, "body"); ruleGhost.name:SetPoint("TOPLEFT", 85, -2); ruleGhost.name:SetHeight(32)
            ruleGhost.detail = Wg().Text(ruleGhost, "small"); ruleGhost.detail:SetPoint("TOPLEFT", 85, -36)
            ruleGhost.badges = {}
            for _, suffix in ipairs({ "action", "to", "keep" }) do
                local badge = CreateFrame("Frame", nil, ruleGhost)
                if R.SettingsCraft then R.SettingsCraft.Sheet(badge, "chip", { layer = "BACKGROUND", corner = 6 }) end
                badge.label = Wg().Text(badge, "small"); badge.label:SetPoint("LEFT", 23, 0); badge.label:SetWordWrap(false)
                badge.icon = badge:CreateTexture(nil, "ARTWORK"); badge.icon:SetPoint("LEFT", 4, 0); badge.icon:SetSize(18, 18)
                ruleGhost.badges[suffix] = badge
            end
        end
        ruleGhost:SetSize(row:GetWidth(), row:GetHeight()); ruleGhost:SetAlpha(.9)
        PaintRuleArtwork(ruleGhost.icon, rule)
        ruleGhost.priority:SetText(from)
        ruleGhost.name:SetText(rule.name)
        local sourceName = pool["rule" .. from .. "name"]
        ruleGhost.name:SetFont(sourceName:GetFont())
        ruleGhost.name:SetWidth(sourceName:GetWidth()); ruleGhost.detail:SetWidth(sourceName:GetWidth())
        ruleGhost.detail:SetText(P.ItemsText(rule))
        for suffix, badge in pairs(ruleGhost.badges) do
            local key = "rule" .. from .. suffix
            local source, label, icon = pool[key .. "badge"], pool[key], pool[key .. "icon"]
            local visible = source and source:IsShown()
            badge:SetShown(visible)
            if visible then
                badge:ClearAllPoints(); badge:SetPoint("TOPLEFT", ruleGhost, "TOPLEFT", source:GetLeft() - left, source:GetTop() - top)
                badge:SetSize(source:GetWidth(), source:GetHeight())
                badge.label:SetText(label:GetText()); badge.label:SetWidth(label:GetWidth()); badge.label:SetFont(label:GetFont()); badge.label:SetTextColor(label:GetTextColor())
                badge.icon:SetTexture(icon:GetTexture())
                badge.icon:SetRotation(suffix == "action" and MI().HAS_FLOW[rule.kind] and rule.flow ~= "balance" and (rule.flow == "withdraw" and math.pi / 2 or -math.pi / 2) or 0)
            end
        end
        ghost = ruleGhost
        local scale = ghost:GetEffectiveScale()
        offset = { left - x / scale, top - y / scale }
    end
    P.Drag.Start({
        ghost = ghost, ghostOffset = offset,
        src = { kind = "rule", id = rule.id, from = from }, label = ("%d.  %s"):format(from, rule.name),
        find = RowUnderPointer,
        hover = function(place) ShowDropMark(place, from); if place then AutoScroll() end end,
        drop = function(src, place)
            if place == src.from then return end
            local ok = MI().MoveRuleTo(src.id, place)
            if ok then Say(("Moved \"%s\" to place %d."):format(rule.name, place)) end
        end,
    })
end

-- Rules read from top to bottom, with one visible Edit action. Secondary actions belong to the selected card.
local function DrawTable(y, rules)
    local mi = MI()
    rowCount = #rules
    local width = math.max(W, f:GetWidth() or W) - PAD * 2
    for i, rule in ipairs(rules) do
        local key, row = "rule" .. i, RowFrame(i)
        local priority = priorities[rule.id] or i
        row.rule, row.index, row.y = rule, priority, y
        if row.sel then row.sel:SetShown(selectedRule == rule.id) end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
        row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y)
        row:SetHeight(ROW_H)
        row.bg:SetColorTexture(0, 0, 0, 0)
        row.hover:SetColorTexture(.85, .72, .49, .04)
        for _, g in ipairs(row.grip) do g:SetColorTexture(.65, .60, .51, filtered and .2 or .7) end
        local function Label(suffix, text, x, top, w, kind)
            local t = Text(key .. suffix, kind or "small")
            t:SetParent(row); t:ClearAllPoints(); t:SetPoint("TOPLEFT", row, "TOPLEFT", x, -top)
            t:SetWidth(w); t:SetWordWrap(false); t:SetText(text)
            Tone(t, rule.enabled and nil or "dim")
            return t
        end
        Label("priority", tostring(priority), 22, 26, 24)
        local art = Get(key .. "art", function() return row:CreateTexture(nil, "ARTWORK") end)
        art:SetParent(row); art:ClearAllPoints(); art:SetPoint("LEFT", row, "LEFT", 45, 0); art:SetSize(36, 36)
        PaintRuleArtwork(art, rule)
        local chipX = width >= 850 and math.floor(width * .44) or 85
        local title = Label("name", rule.name, 85, 2, width >= 850 and chipX - 100 or width - 270, "body")
        if R.SettingsMaterial then R.SettingsMaterial.ReminderFont(title, 15, rule.enabled, "serif") end
        title:SetWordWrap(true); title:SetHeight(32)
        Label("items", P.ItemsText(rule) .. (MI().Problem(rule, false) and " · Needs attention" or ""), 85, 36, width >= 850 and chipX - 100 or width - 270)
        local action, to, keep = P.RowCells(rule)
        local chipY = width >= 850 and 21 or 49
        local function Badge(suffix, text, x, w)
            if text == "" then return end
            local badge = Get(key .. suffix .. "badge", function()
                local b = CreateFrame("Frame", nil, row)
                if R.SettingsCraft then R.SettingsCraft.Sheet(b, "chip", { layer = "BACKGROUND", corner = 6 }) end
                return b
            end)
            badge:SetParent(row); badge:ClearAllPoints(); badge:SetPoint("TOPLEFT", row, "TOPLEFT", x, -chipY); badge:SetSize(w, width >= 850 and 28 or 20)
            local label = Label(suffix, text, x + 6, chipY + 2, w - 26)
            label:SetParent(badge); label:ClearAllPoints(); label:SetPoint("LEFT", badge, "LEFT", 23, 0)
            label:SetAlpha(1); label:SetDrawLayer("OVERLAY", 7)
            if R.SettingsMaterial then R.SettingsMaterial.ReminderFont(label, width >= 850 and 13 or 12, false) end
            local icon = Get(key .. suffix .. "icon", function() return badge:CreateTexture(nil, "ARTWORK") end)
            icon:ClearAllPoints(); icon:SetPoint("LEFT", badge, "LEFT", 4, 0); icon:SetSize(width >= 850 and 18 or 15, width >= 850 and 18 or 15)
            local image = suffix == "keep" and "leather-backpack" or suffix == "to" and (rule.kind == "guild" and "tabard" or rule.kind == "mail" and "sealed-scroll" or "coins") or rule.kind == "never" and "sword-and-shield" or rule.kind == "keep" and "leather-backpack" or rule.kind == "mail" and "sealed-scroll" or "balance-scales"
            icon:SetTexture(R.PATH .. "media\\npcs\\" .. image .. "-small")
            if suffix == "to" and rule.kind == "bank" then icon:SetTexture(R.PATH .. [[media\icons\magicBank-small]]) end
            icon:SetRotation(0)
            if suffix == "action" and MI().HAS_FLOW[rule.kind] and rule.flow ~= "balance" then
                icon:SetTexture(R.PATH .. [[media\guides\status-current-small]])
                icon:SetRotation(rule.flow == "withdraw" and math.pi / 2 or -math.pi / 2)
            end
            if suffix == "action" and rule.enabled then
                if rule.flow == "balance" or rule.flow == "withdraw" then label:SetTextColor(.72, .83, .86)
                elseif MI().Deposits(rule) then label:SetTextColor(.80, .84, .62) end
            end
        end
        Badge("action", rule.kind == "keep" and "Keep in bags" or rule.kind == "never" and "Never transfer" or action, chipX, (rule.kind == "keep" or rule.kind == "never") and 146 or 90)
        Badge("to", to ~= "-" and to or "", chipX + 96, 100)
        Badge("keep", rule.kind ~= "never" and keep ~= "-" and ("Keep " .. keep) or "", chipX + 202, 100)
        local box = Check(key .. "on", function(v)
            local ok, why = mi.SetRuleEnabled(rule.id, v); if not ok then Say(why, "warn") end
        end, true)
        box:SetParent(row); box:ClearAllPoints(); box:SetPoint("RIGHT", row, "RIGHT", -138, 0); box:SetChecked(rule.enabled)
        box:SetFrameLevel(row:GetFrameLevel() + 2)
        local edit = Button(key .. "edit", "Edit", 70, "secondary", function() StartEdit(mi.Rule(rule.id)) end)
        edit:SetParent(row); edit:ClearAllPoints(); edit:SetPoint("RIGHT", row, "RIGHT", -56, 0)
        edit:SetHeight(32)
        local more = Button(key .. "more", "...", 38, "secondary", function()
            local choices = {
                { value = "up", label = "Move up", disabled = filtered or priority == 1 },
                { value = "down", label = "Move down", disabled = filtered or priority == #mi.Rules() },
                { value = "duplicate", label = "Duplicate" }, { value = "delete", label = "Delete" },
            }
            if filtered then table.remove(choices, 2); table.remove(choices, 1)
            else
                if priority == #mi.Rules() then table.remove(choices, 2) end
                if priority == 1 then table.remove(choices, 1) end
            end
            Wg().ContextMenu(pool[key .. "more"], choices, function(value)
                if value == "up" and not filtered then mi.MoveRule(rule.id, -1)
                elseif value == "down" and not filtered then mi.MoveRule(rule.id, 1)
                elseif value == "duplicate" then mi.DuplicateRule(rule.id)
                elseif value == "delete" then
                    R.Interact.Confirm("TWICHUI_MI_RULE_DELETE", "Delete the rule " .. rule.name .. "? Only the rule is removed; no items move.",
                        function() mi.DeleteRule(rule.id) end, { accept = "Delete" })
                end
            end)
        end)
        more:SetParent(row); more:ClearAllPoints(); more:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        more:SetHeight(32)
        y = y + ROW_H + 6
    end
    for i = #rules + 1, mi.MAX_RULES do local row = pool["tr" .. i]; if row then row.rule = nil end end
    return y
end

local function DrawList(y)
    local mi = MI()
    local all, rules = mi.Rules(), {}
    priorities = {}
    filtered = query ~= "" or ruleFilter ~= "all"
    for i, rule in ipairs(all) do
        priorities[rule.id] = i
        local text = (rule.name .. " " .. P.ItemsText(rule) .. " " .. P.DestText(rule)):lower()
        if (query == "" or text:find(query, 1, true)) and
            (ruleFilter == "all" or (ruleFilter == "enabled" and rule.enabled) or (ruleFilter == "disabled" and not rule.enabled)) then
            rules[#rules + 1] = rule
        end
    end
    local full = math.max(W, f:GetWidth() or W) - PAD * 2
    local enabled = 0; for _, rule in ipairs(all) do if rule.enabled then enabled = enabled + 1 end end
    local d = Text("listText", "small"); Wide(d, PAD, y, full)
    d:SetText(("%d of %d rules on. First matching rule wins. Nothing moves until you review and confirm."):format(enabled, #all))
    Tone(d, "dim"); y = y + H(d) + 12
    local findWidth = full - 386
    local new = Button("newRule", "+ New rule", 180, "primary", function()
        Wg().ContextMenu(pool.newRule, TemplateChoices(), function(value) NewFromTemplate(value) end)
    end)
    new:SetHeight(32); At(new, PAD, y)
    Button("rulesHelp", "?", 32, "secondary", function() local enter = pool.rulesHelp:GetScript("OnEnter"); if enter then enter(pool.rulesHelp) end end)
    At(pool.rulesHelp, PAD + full - 32, y)
    R.Interact.Tip(pool.rulesHelp, "Rule priority", "The first matching rule wins. Keep safeguards still apply. Clear filters before reordering; nothing moves until you review and confirm.")
    local find = Edit("findRule", findWidth)
    find:SetWidth(findWidth)
    At(find, PAD + 188, y)
    find:SetHeight(32); find:SetTextInsets(24, 6, 0, 0)
    local glass = Get("findGlass", function() return find:CreateTexture(nil, "OVERLAY") end)
    glass:SetAtlas("common-search-magnifyingglass"); glass:ClearAllPoints(); glass:SetPoint("LEFT", find, "LEFT", 6, 0); glass:SetSize(14, 14)
    if not find:HasFocus() then find:SetText(query) end
    find:SetScript("OnTextChanged", function(self)
        local value = (self:GetText() or ""):lower()
        if value ~= query then query = value; P.QueueRefresh() end
    end)
    if query == "" then local hint = Text("findHint", "small"); hint:SetParent(find); hint:ClearAllPoints(); hint:SetPoint("LEFT", find, "LEFT", 24, 0); hint:SetWidth(findWidth - 30); hint:SetText("Find a rule..."); Tone(hint, "quiet") end
    R.Interact.Tip(find, "Find a rule", "Search rule names, item criteria and destinations. Priority stays unchanged.")
    local filter = Get("ruleFilter", function() return Wg().Dropdown(f, 180, function(value) ruleFilter = value; P.QueueRefresh() end) end)
    filter:SetChoices(function() return { { value = "all", label = "All rules" }, { value = "enabled", label = "Enabled rules" }, { value = "disabled", label = "Disabled rules" } } end)
    filter:SetValue(ruleFilter, ruleFilter == "all" and "All rules" or ruleFilter == "enabled" and "Enabled rules" or "Disabled rules")
    filter:SetWidth(150); filter:SetHeight(32); At(filter, PAD + full - 190, y)
    R.Interact.Tip(new, "Rule priority", "Keep amounts from every matching rule still count. Templates start turned off. Clear search and filters before reordering.")
    y = y + 42
    if #rules == 0 then
        local none = Text("listNone", "body")
        Wide(none, PAD, y)
        none:SetText(#all == 0 and "No rules yet. Create a custom rule or choose a template above." or "No matching rules. Clear search or change the filter.")
        Tone(none, "quiet")
        y = y + 28
    end
    if #rules > 0 then y = DrawTable(y, rules) end
    Button("preview", "Review items", 116, "secondary", #all > 0 and function() mi.Window.Show(true) end or nil)
    At(pool.preview, PAD, y + 8)
    pool.preview:SetHeight(28)
    R.Interact.Tip(pool.preview, "Review items", "Opens the existing read-only item review. Nothing moves until you confirm an action there.")
    return y + 46
end

---------------------------------------------------------------------------
-- The editor
---------------------------------------------------------------------------

local function Radio(key, x, y, label, on, onPick, w)
    local c = Check(key, function() onPick() end)
    c:SetChecked(on)
    At(c, x, y)
    local t = Text(key .. "t", "body")
    Wide(t, x + c:GetWidth() + 8, y + 2, w or 200)
    t:SetText(label)
    Tone(t, on and nil or "dim")
    return c, math.max(c:GetHeight(), H(t) + 2)
end

-- The item editor changes the existing private rule draft. Done/Escape only close this surface.
-- Save rule / Cancel rule delegate to the builder's canonical actions; there is no second persisted draft.
function P.OpenItemFilters(tab)
    if not editing then return end
    itemAdvanced = true
    if tab then filterTab = tab end
    if pool.filterScroll then pool.filterScroll:SetVerticalScroll(0) end
    P.QueueRefresh()
end

function P.CloseItemFilters()
    if not itemAdvanced then return false end
    itemAdvanced = false
    if pool.filterEditor then pool.filterEditor:Hide(); pool.filterShade:Hide() end
    P.QueueRefresh()
    return true
end

local function HasItemFilters(r)
    return #r.cats > 0 or next(r.qualities) ~= nil or r.equip ~= "any" or r.bind ~= "any"
end

function P.FilterSummary(r)
    local parts, quality = {}, {}
    for _, q in ipairs(MI().QUALITY_ORDER) do if r.qualities[q] then quality[#quality + 1] = MI().QualityName(q) end end
    if #quality > 0 then parts[#parts + 1] = table.concat(quality, " or ") end
    if r.equip ~= "any" then parts[#parts + 1] = r.equip == "equipment" and "Equipment only" or "Not equipment" end
    if r.bind ~= "any" then parts[#parts + 1] = r.bind == "boe" and "Unbound bind-on-equip" or "Doesn't bind" end
    return parts
end

local function DrawItemFilters()
    local r, mi = editing, MI()
    local view = R.SettingsUI and R.SettingsUI.View and R.SettingsUI.View("magicInventory")
    local viewport = view and view.frame:GetParent():GetParent() or f
    local shade = Get("filterShade", function()
        local frame = CreateFrame("Frame", nil, viewport)
        frame:EnableMouse(true)
        frame:EnableMouseWheel(true)
        frame:SetScript("OnMouseWheel", function() end) -- scrolling outside the editor must not move the parent builder
        local tint = frame:CreateTexture(nil, "BACKGROUND"); tint:SetAllPoints(); tint:SetColorTexture(.025, .020, .016, .64)
        return frame
    end)
    shade:SetParent(viewport); shade:ClearAllPoints(); shade:SetAllPoints(viewport); shade:SetFrameStrata("DIALOG"); shade:SetFrameLevel(f:GetFrameLevel() + 20)
    local panel = Get("filterEditor", function()
        local frame = CreateFrame("Frame", "TwichUIMagicItemFilters", shade, "BackdropTemplate")
        Wg().Panel(frame); frame:EnableMouse(true)
        frame:Hide()
        frame:SetScript("OnHide", function()
            for _, key in ipairs({ "filterCategorySearch", "e1incId" }) do if pool[key] then pool[key]:ClearFocus() end end
            if itemAdvanced then itemAdvanced = false; P.QueueRefresh() end
        end)
        return frame
    end)
    panel:SetFrameStrata("DIALOG"); panel:SetFrameLevel(shade:GetFrameLevel() + 1)
    local width = math.max(420, math.min(720, viewport:GetWidth() - 24))
    local tall = math.max(280, math.min(500, viewport:GetHeight() - 24))
    panel:ClearAllPoints(); panel:SetPoint("CENTER", viewport, "CENTER"); panel:SetSize(width, tall)
    local function Place(control, parent, x, y, w, h)
        control:SetParent(parent); control:ClearAllPoints(); control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        if w then control:SetWidth(w) end
        if h then control:SetHeight(h) end
        return control
    end
    local function Label(key, parent, text, x, y, w, kind)
        local label = Place(Text(key, kind or "small"), parent, x, y, w)
        label:SetText(text)
        return label
    end
    local function Help(owner, title, body)
        local material = R.SettingsMaterial
        if material and material.ContextTip then
            owner.itemFilterHelp = title .. "\n" .. body
            if not owner.itemFilterHelpBound then
                owner.itemFilterHelpBound = true
                material.ContextTip(owner, "Item filter", function(self) return self.itemFilterHelp end)
            end
        else R.Interact.Tip(owner, title, body) end
    end
    local title = Label("filterTitle", panel, "Choose items", 48, 14, width - 100, "heading"); Tone(title, "head")
    local emblem = Get("filterEmblem", function() return panel:CreateTexture(nil, "ARTWORK") end)
    emblem:ClearAllPoints(); emblem:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -10); emblem:SetSize(28, 28); emblem:SetTexture(R.PATH .. [[media\icons\magicReagents-small]])
    local function Close() P.CloseItemFilters() end
    Place(Button("filterClose", "x", 28, "secondary", Close), panel, width - 40, 10, nil, 28)
    local tabWidth = math.floor((width - 40) / 3)
    for i, tab in ipairs({ { "filters", "Filters" }, { "categories", "Categories" }, { "include", "Also include" } }) do
        local button = Get("filterTab" .. tab[1], function() return Wg().Tab(panel, tab[2], tabWidth, function() end) end)
        Place(button, panel, 14 + (i - 1) * (tabWidth + 6), 48, tabWidth, 34)
        button.text:SetText(tab[2]); button:SetSelected(filterTab == tab[1])
        button:SetScript("OnClick", function() filterTab = tab[1]; pool.filterScroll:SetVerticalScroll(0); P.QueueRefresh() end)
    end
    local scroll = Get("filterScroll", function()
        local sc, content = Wg().Scroll(panel, width - 56)
        sc.content = content
        -- Pooled controls from another tab can extend the native child rectangle. Bound input to
        -- this tab's explicit content height, as the shared wheel-motion helper does.
        local clamping
        function sc:LimitFilters()
            if clamping then return end
            clamping = true
            local most = math.max(0, self.content:GetHeight() - self:GetHeight())
            if self.ScrollBar then self.ScrollBar:SetMinMaxValues(0, most) end
            local value = math.max(0, math.min(most, self:GetVerticalScroll()))
            if value ~= self:GetVerticalScroll() then self:SetVerticalScroll(value) end
            clamping = nil
        end
        sc:HookScript("OnScrollRangeChanged", sc.LimitFilters)
        sc:HookScript("OnSizeChanged", sc.LimitFilters)
        sc:HookScript("OnVerticalScroll", sc.LimitFilters)
        Wg().ScrollMotion(sc)
        return sc
    end)
    scroll:ClearAllPoints(); scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -92); scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 92)
    local body, contentWidth = scroll.content, width - 56
    body:SetWidth(contentWidth)
    local function Choice(key, label, selected, x, y, w, callback, icon)
        local button = Get(key, function() return Wg().Tab(body, label, w, function() end) end)
        Place(button, body, x, y, w, 36); button.text:SetText(label); button:SetSelected(selected)
        button:SetScript("OnClick", callback)
        local art = Get(key .. "art", function()
            local frame = CreateFrame("Frame", nil, button); frame.tex = frame:CreateTexture(nil, "ARTWORK"); frame.tex:SetAllPoints(); return frame
        end)
        art:SetFrameLevel(button:GetFrameLevel() + 4); art:ClearAllPoints(); art:SetPoint("LEFT", button, "LEFT", 6, 0); art:SetSize(26, 26); art.tex:SetTexture(R.PATH .. icon)
        local mark = Get(key .. "mark", function() return art:CreateTexture(nil, "OVERLAY") end)
        mark:ClearAllPoints(); mark:SetPoint("RIGHT", button, "RIGHT", -5, 0); mark:SetSize(15, 15); mark:SetTexture(R.PATH .. [[media\guides\status-done-small]]); mark:SetShown(selected)
        button.text:ClearAllPoints(); button.text:SetPoint("LEFT", button, "LEFT", 38, 0); button.text:SetPoint("RIGHT", button, "RIGHT", -24, 0)
        return button
    end
    local y, third = 0, math.floor((contentWidth - 12) / 3)
    if filterTab == "filters" then
        Label("filterQualityTitle", body, "Quality · choose any combination", 0, y, contentWidth, "body"); y = y + 28
        local qualities = { { any = true, label = "Any quality" } }
        for _, q in ipairs(mi.QUALITY_ORDER) do qualities[#qualities + 1] = { value = q, label = mi.QualityName(q) } end
        for i, q in ipairs(qualities) do
            local selected = q.any and next(r.qualities) == nil or r.qualities[q.value] == true
            local b = Choice("e1q" .. i, q.label, selected, ((i - 1) % 3) * (third + 6), y + math.floor((i - 1) / 3) * 42, third,
                function() if q.any then r.qualities = {} else r.qualities[q.value] = not r.qualities[q.value] or nil end; P.QueueRefresh() end,
                q.any and NPC .. "reagent-pouch-small" or QUALITY_ART[q.value])
            Help(b, q.label, q.any and "No quality restriction. Other filters and explicit inclusions are unchanged." or "Select several qualities to match any of them. Explicit inclusions still bypass filters.")
        end
        y = y + math.ceil(#qualities / 3) * 42 + 14
        Label("filterEquipmentTitle", body, "Equipment · choose one", 0, y, contentWidth, "body"); y = y + 26
        for i, choice in ipairs({ { "any", "Any item" }, { "equipment", "Equipment only" }, { "other", "Not equipment" } }) do
            Choice("e1eq" .. i, choice[2], r.equip == choice[1], (i - 1) * (third + 6), y, third, function() r.equip = choice[1]; P.QueueRefresh() end, choice[1] == "equipment" and NPC .. "sword-and-shield-small" or choice[1] == "other" and NPC .. "cloth-bolts-small" or NPC .. "leather-backpack-small")
        end
        y = y + 54
        Label("filterBindingTitle", body, "Binding · choose one", 0, y, contentWidth, "body"); y = y + 26
        for i, choice in ipairs({ { "any", "Any binding" }, { "boe", "Bind on equip" }, { "nobind", "Doesn't bind" } }) do
            local b = Choice("e1b" .. i, choice[2], r.bind == choice[1], (i - 1) * (third + 6), y, third, function() r.bind = choice[1]; P.QueueRefresh() end, choice[1] == "nobind" and Painted("unbound") or choice[1] == "boe" and NPC .. "tabard-small" or NPC .. "sealed-scroll-small")
            if choice[1] == "boe" then Help(b, "Bind on equip", "Matches bind-on-equip items only while they are known to be unbound. Already-bound or unknown binding is excluded.") end
        end
        y = y + 52
    elseif filterTab == "categories" then
        Label("filterCategoriesHelp", body, "Match any selected category, then apply the filters. No category selected: other filters or specific items decide.", 0, 0, contentWidth)
        y = H(pool.filterCategoriesHelp) + 10
        local search = Place(Edit("filterCategorySearch", contentWidth), body, 0, y, contentWidth, 28)
        search:SetTextInsets(24, 6, 0, 0)
        local glass = Get("filterCategoryGlass", function() return search:CreateTexture(nil, "OVERLAY") end)
        glass:ClearAllPoints(); glass:SetPoint("LEFT", search, "LEFT", 6, 0); glass:SetSize(14, 14); glass:SetAtlas("common-search-magnifyingglass")
        if not search:HasFocus() then search:SetText(filterQuery) end
        if filterQuery == "" then
            local hint = Label("filterCategoryHint", search, "Find a category...", 24, 6, contentWidth - 30); Tone(hint, "dim")
        end
        search:SetScript("OnTextChanged", function(self)
            local q = self:GetText():lower()
            if pool.filterCategoryHint then pool.filterCategoryHint:SetShown(q == "") end
            if q ~= filterQuery then filterQuery = q; P.QueueRefresh() end
        end)
        R.Interact.Tip(search, "Find a category", "Filter the category names without changing any saved choices.")
        y = y + 40
        local chosen, count = {}, 0
        for _, key in ipairs(r.cats) do chosen[key] = true end
        for i, cat in ipairs(mi.Categories()) do
            if filterQuery == "" or (cat.label .. " " .. cat.group):lower():find(filterQuery, 1, true) then
                local caption = cat.label .. (cat.group ~= cat.label and ("\n|cff8a857c" .. cat.group .. "|r") or "")
                Choice("e1cat" .. i, caption, chosen[cat.key] == true, count % 2 * math.floor((contentWidth + 6) / 2), y + math.floor(count / 2) * 44, math.floor((contentWidth - 6) / 2), function()
                    if chosen[cat.key] then
                        for j = #r.cats, 1, -1 do if r.cats[j] == cat.key then table.remove(r.cats, j) end end
                    elseif #r.cats < mi.MAX_CATS then r.cats[#r.cats + 1] = cat.key
                    else Say("Category limit reached; remove a category first.", "warn") end
                    P.QueueRefresh()
                end, P.CategoryArtwork(cat.key))
                Help(pool["e1cat" .. i], cat.label, cat.group .. " · category " .. cat.key)
                count = count + 1
            end
        end
        if count == 0 then Label("filterNoCategories", body, "No matching categories. Your selections are unchanged.", 0, y, contentWidth); y = y + 28
        else y = y + math.ceil(count / 2) * 44 end
    else
        Label("filterIncludeHelp", body, "These specific items match even when they fail the filters. Exclusions and global protections still take precedence.", 0, 0, contentWidth)
        y = H(pool.filterIncludeHelp) + 12
        Place(Button("e1incPick", "Choose from bags", 164, "secondary", function()
            mi.Picker.Open({ purpose = "Also include these items, regardless of filters", selected = r.include, onDone = function(set) r.include = set; P.QueueRefresh() end })
        end), body, 0, y, nil, 30)
        local idBox = Place(Edit("e1incId", contentWidth - 268), body, 174, y, contentWidth - 268, 30)
        if idBox:GetText() == "" then
            local hint = Label("filterItemIdHint", idBox, "Item ID or link", 6, 7, contentWidth - 280); Tone(hint, "dim")
        end
        if not idBox.filterHintHook then
            idBox.filterHintHook = true
            idBox:HookScript("OnTextChanged", function(self) if pool.filterItemIdHint then pool.filterItemIdHint:SetShown(self:GetText() == "" and itemAdvanced and filterTab == "include") end end)
        end
        local function Add(id) r.include[id] = true; r.exclude[id] = nil; P.QueueRefresh() end
        idBox:SetScript("OnEnterPressed", function(self) AddById(self, Add) end)
        R.Interact.Tip(idBox, "Also include", "Enter an item ID or paste an item link.")
        Place(Button("e1incAdd", "Add item", 84, "secondary", function() AddById(idBox, Add) end), body, contentWidth - 84, y, nil, 30)
        y = y + 42
        local ids = {}; for id in pairs(r.include) do ids[#ids + 1] = id end; table.sort(ids)
        for i, id in ipairs(ids) do
            local facts = mi.ItemFacts(id)
            local row = Get("filterIncludeRow" .. i, function() local frame = CreateFrame("Frame", nil, body, "BackdropTemplate"); Wg().Panel(frame); return frame end)
            Place(row, body, 0, y, contentWidth, 44)
            local icon = Place(Icon("filterIncludeIcon" .. i), row, 6, 7); icon.itemID = id; icon.tex:SetTexture(facts and facts.icon or QUESTION)
            local text = Label("filterIncludeName" .. i, row, facts and facts.name or ("Item " .. id .. " (data unavailable)"), 42, 6, contentWidth - 84, "body"); text:SetHeight(34)
            R.Interact.Tip(row, facts and facts.name or ("Item " .. id), "Explicit inclusion. Exclusions and protections still apply.")
            Place(Button("filterIncludeRemove" .. i, "x", 28, "secondary", function() r.include[id] = nil; P.QueueRefresh() end), row, contentWidth - 34, 8, nil, 28)
            y = y + 50
        end
        if #ids == 0 then Label("filterIncludeEmpty", body, "No explicit inclusions. Add items here to match them regardless of filters.", 0, y, contentWidth); y = y + 40 end
    end
    body:SetHeight(y + 8)
    scroll:LimitFilters()
    Label("filterDraftNote", panel, "Changes stay in this rule draft until Save rule.", 14, tall - 78, width - 28)
    Place(Button("filterCancelRule", "Cancel rule", 104, "secondary", function() itemAdvanced = false; pool.eCancel.onClick() end), panel, 14, tall - 44, nil, 32)
    Place(Button("filterDone", "Done", 104, "secondary", Close), panel, math.floor((width - 104) / 2), tall - 44, nil, 32)
    Place(Button("filterSaveRule", "Save rule", 104, "primary", function() itemAdvanced = false; pool.eSave.onClick() end), panel, width - 118, tall - 44, nil, 32)
end

local function DrawDestStep(y)
    local mi, r = MI(), editing
    local t = Text("e2head", "heading")
    Wide(t, PAD, y)
    t:SetText("What happens to matching items")
    Tone(t, "head")
    y = y + 22
    local ABOUT = {
        mail = "Mailed to a recipient you name, at a mailbox, one recipient per mail.",
        bank = "Your own bank: deposit, withdraw, or both (no bank space is bought).",
        guild = "A guild bank tab you choose: deposit, withdraw, or both. Not yet checked on Forever's realms.",
        keep = "Kept in your bags: other rules move only what is above the amount you set.",
        never = "Never moved by any rule.",
    }
    for _, kind in ipairs(mi.KIND_ORDER) do
        Radio("e2k" .. kind, PAD, y, kind == "bank" and "Your bank" or (kind == "guild" and "A guild bank" or mi.KIND_LABEL[kind]), r.kind == kind, function()
            r.kind = kind
            if mi.HAS_FLOW[kind] then r.flow = r.flow or "deposit" end
            if not mi.NEEDS_DEST[kind] then r.dest = nil
            elseif r.dest then local d = mi.Dest(r.dest); if not d or d.kind ~= kind then r.dest = nil end end
            P.QueueRefresh()
        end, 170)
        local a = Text("e2a" .. kind, "small")
        Wide(a, PAD + 200, y + 2, W - PAD * 2 - 200)
        a:SetText(ABOUT[kind])
        Tone(a, "dim")
        y = y + math.max(24, H(a) + 8)
    end
    if mi.HAS_FLOW[r.kind] and not r.design then
        y = y + 6
        local ft = Text("e2flow", "heading")
        Wide(ft, PAD, y)
        ft:SetText("Which way")
        Tone(ft, "head")
        y = y + 22
        local FLOW_ABOUT = {
            deposit = "Moves what is above your keep amount from your bags into it.",
            withdraw = "Takes whole stacks out of it until you carry your target, never more. What isn't there stays missing.",
            balance = "Both: deposits what is above the target and takes out whole stacks to reach it, never more.",
        }
        for _, flow in ipairs(mi.FLOW_ORDER) do
            Radio("e2f" .. flow, PAD, y, mi.FLOW_LABEL[flow], (r.flow or "deposit") == flow, function()
                r.flow = flow
                if flow ~= "deposit" and (r.keep or 0) <= 0 then r.keep = 20 end
                P.QueueRefresh()
            end, 170)
            local a = Text("e2fa" .. flow, "small")
            Wide(a, PAD + 200, y + 2, W - PAD * 2 - 200)
            a:SetText(FLOW_ABOUT[flow])
            Tone(a, "dim")
            y = y + math.max(24, H(a) + 8)
        end
    end
    if mi.NEEDS_DEST[r.kind] then
        y = y + 6
        t = Text("e2dest", "heading")
        Wide(t, PAD, y)
        t:SetText(r.kind == "mail" and "Send to" or "Which tab")
        Tone(t, "head")
        y = y + 22
        local dd = Get("e2dd", function() return Wg().Dropdown(f, 240, function(v) editing.dest = v; P.QueueRefresh() end) end)
        dd:SetChoices(function()
            local out = {}
            for _, d in ipairs(MI().Dests()) do
                if d.kind == editing.kind then
                    local w = MI().Resolve(d.id)
                    out[#out + 1] = { value = d.id, label = d.label .. (w and (d.kind == "mail" and (": " .. w.recipient) or (": " .. (w.tabName or "?"))) or " (nothing chosen here)") }
                end
            end
            return out
        end)
        local cur = r.dest and mi.Dest(r.dest)
        dd:SetValue(r.dest, cur and cur.label or "Choose...")
        At(dd, PAD, y)
        local nb = Edit("e2new", 150)
        At(nb, PAD + 252, y + 1)
        if not nb:HasFocus() and (nb:GetText() or "") == "" then nb:SetText(newDestName[r.kind] or "") end
        nb:SetScript("OnTextChanged", function(self) newDestName[editing.kind] = self:GetText() end)
        Button("e2add", "Add destination", 130, "secondary", function()
            local id, why = mi.AddDest(editing.kind, pool.e2new:GetText())
            if not id then Say(why, "warn") return end
            editing.dest = id
            pool.e2new:SetText("")
            newDestName[editing.kind] = nil
        end)
        At(pool.e2add, PAD + 408, y)
        y = y + 32
        local where = r.dest and mi.Resolve(r.dest)
        local s = Text("e2where", "small")
        Wide(s, PAD, y)
        if not cur then s:SetText("Choose a destination, or name a new one (for example \"Bank alt\").")
        elseif not where then s:SetText(("\"%s\" has nothing chosen on this character yet. Set it under Destinations on this character, after saving."):format(cur.label))
        elseif r.kind == "mail" then s:SetText(("On this character \"%s\" is |cffffffff%s|r%s."):format(cur.label, where.recipient, where.shared and " (all your characters)" or ""))
        else s:SetText(("On this character \"%s\" is <%s>, tab %d \"%s\"."):format(cur.label, where.guild, where.tab, where.tabName or "?")) end
        Tone(s, where and "dim" or "warn")
        if where and where.kind == "guild" then
            local ic = Icon("e2tabIcon")
            ic:SetSize(20, 20)
            At(ic, PAD, y - 2)
            ic.itemID = nil
            ic.tex:SetTexture(where.tabIcon or QUESTION)
            Wide(s, PAD + 26, y)
        end
        y = y + math.max(H(s), 20) + 8
    end
    return y
end

local function DrawKeepStep(y)
    local mi, r = MI(), editing
    local t = Text("e3exc", "heading")
    Wide(t, PAD, y)
    t:SetText("Never include these items")
    Tone(t, "head")
    y = y + 18
    local d = Text("e3excText", "small")
    Wide(d, PAD, y)
    d:SetText("This rule never matches these, whatever else is true; another rule may still. For items no rule should ever move, use the Never transfer list. Click one to take it off.")
    Tone(d, "dim")
    y = y + H(d) + 6
    local h = ItemStrip("e3excI", r.exclude, PAD, y, "Click to take it off this rule's list.", function(id) r.exclude[id] = nil; P.QueueRefresh() end)
    y = y + h + (h > 0 and 6 or 0)
    Button("e3excPick", "Choose from bags", 140, "secondary", function()
        mi.Picker.Open({ purpose = ("Never include in \"%s\": this rule never matches these."):format(r.name), selected = r.exclude,
            onDone = function(set) r.exclude = set; for id in pairs(set) do r.include[id] = nil end; P.QueueRefresh() end })
    end)
    At(pool.e3excPick, PAD, y)
    local box = Edit("e3excId", 160)
    At(box, PAD + 150, y + 1)
    local function Add(id) r.exclude[id] = true; r.include[id] = nil; P.QueueRefresh() end
    box:SetScript("OnEnterPressed", function(self) AddById(self, Add) end)
    Button("e3excAdd", "Add by ID or link", 140, "secondary", function() AddById(pool.e3excId, Add) end)
    At(pool.e3excAdd, PAD + 320, y)
    y = y + 40
    if r.kind == "never" then return y end
    local withdraws = mi.Withdraws(r)
    t = Text("e3keep", "heading")
    Wide(t, PAD, y)
    t:SetText(withdraws and "Target in bags" or "Keep in bags")
    Tone(t, "head")
    y = y + 22
    local on = Check("e3keepOn", function(v)
        editing.keep = v and math.max(1, editing.keep) or 0
        if v and editing.keep == 0 then editing.keep = 20 end
        P.QueueRefresh()
    end)
    on:SetChecked(r.keep > 0)
    At(on, PAD, y + 2)
    local kt = Text("e3keepT", "body")
    Wide(kt, PAD + 24, y + 4, 60)
    kt:SetText("Keep")
    local kb = Edit("e3keepN", 60)
    kb:SetMaxLetters(4)
    At(kb, PAD + 64, y + 1)
    if not kb:HasFocus() then kb:SetText(r.keep > 0 and tostring(r.keep) or "") end
    local function Read()
        if not editing then return end
        local n = tonumber(kb:GetText() or "")
        if n and n >= 0 and n <= mi.MAX_KEEP and math.floor(n) == n then editing.keep = n
        else Say(("Type a whole number from 0 to %d."):format(mi.MAX_KEEP), "warn") end
        kb:ClearFocus()
        P.QueueRefresh()
    end
    kb.read = Read
    kb:SetScript("OnEnterPressed", Read)
    if not kb.hooked then
        kb.hooked = true
        -- hooked once: the field's focus ring is a hook of the same script, and the page may be closing
        kb:HookScript("OnEditFocusLost", function(self)
            if editing and self:IsVisible() and (self:GetText() or "") ~= tostring(editing.keep) then self.read() end
        end)
    end
    local kt2 = Text("e3keepT2", "body")
    Wide(kt2, PAD + 132, y + 4, 300)
    kt2:SetText("of each matching item in my bags")
    y = y + 28
    local note = Text("e3keepNote", "small")
    Wide(note, PAD, y)
    if withdraws then
        note:SetText("Counted for each kind of item over every stack you carry. Withdrawing takes whole stacks only and never goes over this amount, so you may end a little under it; the review says by how much. Other rules never send away what this rule keeps.")
    else
        note:SetText("Counted for each kind of item over every stack you carry (not one amount shared by the whole category), and never in your bank or mail. Only whole stacks move, so sometimes a few more than this stay.")
    end
    Tone(note, "dim")
    y = y + H(note) + 8
    if r.kind == "guild" and r.flow ~= "withdraw" then y = P.DrawStackSize(y) end
    return y
end

-- A guild bank rule's target stack size (the guild bank previews place stacks of this size and one smaller one).
function P.DrawStackSize(y)
    local mi, r = MI(), editing
    local t = Text("e3stack", "heading")
    Wide(t, PAD, y + 4)
    t:SetText("Target stack size")
    Tone(t, "head")
    y = y + 26
    local on = Check("e3stackOn", function(v)
        editing.stack = v and ((editing.stack or 0) > 0 and editing.stack or 20) or 0
        P.QueueRefresh()
    end)
    on:SetChecked((r.stack or 0) > 0)
    At(on, PAD, y + 2)
    local st = Text("e3stackT", "body")
    Wide(st, PAD + 24, y + 4, 140)
    st:SetText("Stacks of")
    local sb = Edit("e3stackN", 60)
    sb:SetMaxLetters(4)
    At(sb, PAD + 90, y + 1)
    if not sb:HasFocus() then sb:SetText((r.stack or 0) > 0 and tostring(r.stack) or "") end
    local function Read()
        if not editing then return end
        local n = tonumber(sb:GetText() or "")
        if n and n >= 0 and n <= mi.MAX_STACK and math.floor(n) == n then editing.stack = n
        else Say(("Type a whole number from 0 to %d."):format(mi.MAX_STACK), "warn") end
        sb:ClearFocus()
        P.QueueRefresh()
    end
    sb:SetScript("OnEnterPressed", Read)
    if not sb.hooked then
        sb.hooked = true
        sb:HookScript("OnEditFocusLost", function(self)
            if editing and editing.kind == "guild" and self:IsVisible() and (self:GetText() or "") ~= ((editing.stack or 0) > 0 and tostring(editing.stack) or "") then Read() end
        end)
    end
    local st2 = Text("e3stackT2", "body")
    Wide(st2, PAD + 160, y + 4, 300)
    st2:SetText("each, and one smaller stack for the rest")
    y = y + 28
    local note = Text("e3stackNote", "small")
    Wide(note, PAD, y)
    note:SetText("The size every stack of a matching item should end at. It can't be above what an item stacks to (that item is then left alone and the preview says so); unstackable items stay one to a slot. Only the previews use it for now: nothing is moved.")
    Tone(note, "dim")
    return y + H(note) + 8
end

local function DrawEditor(y)
    local r = editing
    local head = Text("eHead", "heading")
    Wide(head, PAD, y)
    head:SetText(r.id and "Editing rule" or "New rule")
    Wide(head, PAD + 94, y, W - 110)
    Button("builderBack", "< Back", 84, "secondary", function()
        R.Interact.Confirm("TWICHUI_MI_DISCARD_DRAFT", "Discard this unsaved rule draft? Your saved rules are unchanged.", function()
            editing = nil; said = nil; P.QueueRefresh(); QueueRelayout()
        end, { accept = "Discard" })
    end)
    At(pool.builderBack, PAD, y - 3)
    Tone(head, "head")
    y = y + 22
    local nt = Text("eNameT", "body")
    Wide(nt, PAD, y + 4, 60)
    nt:SetText("Name")
    local nb = Edit("eName", 300)
    nb:SetMaxLetters(MI().MAX_NAME)
    At(nb, PAD + 60, y)
    if not nb:HasFocus() then nb:SetText(r.name or "") end
    nb:SetScript("OnTextChanged", function(self)
        if editing and editing.name ~= self:GetText() then editing.name = self:GetText(); P.QueueRefresh() end
    end)
    local full = math.max(W, f:GetWidth() or W) - PAD * 2
    local wide = full >= 870
    local bannerX, bannerY, bannerW = wide and 380 or PAD, wide and y - 8 or y + 30, wide and full - 386 or full
    local banner = Get("summaryBanner", function()
        local frame = CreateFrame("Frame", nil, f)
        if R.SettingsMaterial then R.SettingsMaterial.PanelFace(frame, "card") end
        if R.SettingsCraft then R.SettingsCraft.Sheet(frame, "selection", { layer = "BACKGROUND", sub = 1, corner = 12 }) end
        return frame
    end)
    At(banner, bannerX, bannerY); banner:SetSize(bannerW, 64); banner:SetFrameLevel(f:GetFrameLevel() + 1)
    local art = Get("summaryArt", function() return banner:CreateTexture(nil, "ARTWORK") end)
    art:ClearAllPoints(); art:SetPoint("LEFT", banner, "LEFT", 10, 0); art:SetSize(40, 40); PaintRuleArtwork(art, r)
    local live = Text("builderSummary", "heading"); live:SetParent(banner); live:ClearAllPoints(); live:SetPoint("TOPLEFT", banner, "TOPLEFT", 60, -9); live:SetWidth(bannerW - 74)
    local firstItem = next(r.include)
    local oneItem = firstItem and not next(r.include, firstItem) and not HasItemFilters(r) and MI().ItemFacts(firstItem)
    live:SetText((r.kind == "keep" or MI().Withdraws(r)) and ("Carry up to " .. (r.keep or 0) .. (oneItem and #oneItem.name <= 32 and (" " .. oneItem.name) or " of each matching item")) or P.KindLabel(r)); live:SetHeight(22); live:SetMaxLines(1); live:SetWordWrap(false)
    local detail = Text("summaryDetail", "small"); detail:SetParent(banner); detail:ClearAllPoints(); detail:SetPoint("TOPLEFT", banner, "TOPLEFT", 60, -34); detail:SetWidth(bannerW - 74); detail:SetHeight(25)
    detail:SetText(P.ItemsText(r) .. " · " .. P.DestText(r):gsub(" \226\134\146 ", ": "))
    R.Interact.Tip(banner, "Rule summary", P.Sentence(r))
    local cols = wide and 3 or 2
    local col = math.floor((full - (cols - 1) * 12) / cols)
    y = y + (wide and 68 or 106)
    local top = y
    local function Panel(key, title, x, py, w, h)
        local panel = Get(key, function()
            local p = CreateFrame("Frame", nil, f, "BackdropTemplate"); Wg().Panel(p); return p
        end)
        At(panel, x, py); panel:SetSize(w, h)
        panel:SetFrameLevel(f:GetFrameLevel())
        local art = Get(key .. "headingArt", function() return panel:CreateTexture(nil, "ARTWORK") end)
        local icons = { itemsPanel = [[media\npcs\leather-backpack-small]], destinationPanel = [[media\icons\magicBank-small]], flowPanel = [[media\guides\status-current-small]], limitsPanel = [[media\npcs\coins-small]], reviewPanel = [[media\npcs\sealed-scroll-small]] }
        art:ClearAllPoints(); art:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10); art:SetSize(23, 23); art:SetTexture(R.PATH .. icons[key])
        local t = Text(key .. "title", "heading"); t:SetParent(panel); Wide(t, x + 40, py + 12, w - 50); t:SetText(title); Tone(t, "head")
        return py + 44
    end
    local left, mid = PAD, PAD + col + 12
    local iy = Panel("itemsPanel", "What items?", left, top, col, 320)
    local criteria, active = P.ItemsText(r), P.FilterSummary(r)
    local names = {}; for _, key in ipairs(r.cats) do names[#names + 1] = MI().CategoryName(key) or "Unnamed category" end
    local included = 0; for _ in pairs(r.include) do included = included + 1 end
    local categoryText = #names > 0 and table.concat(names, " + ") or included > 0 and (included .. (included == 1 and " specific item" or " specific items")) or "Choose items"
    if #categoryText > 24 then categoryText = #names .. (#names == 1 and " category" or " categories") end
    local qualityNames, qualityIcon = {}, nil
    for _, q in ipairs(MI().QUALITY_ORDER) do if r.qualities[q] then qualityNames[#qualityNames + 1] = MI().QualityName(q); qualityIcon = qualityIcon or QUALITY_ART[q] end end
    local filterText = #qualityNames > 0 and (#qualityNames <= 2 and table.concat(qualityNames, " / ") or #qualityNames .. " qualities")
        or r.equip == "equipment" and "Equipment" or r.equip == "other" and "Not gear" or r.bind == "boe" and "Bind on equip" or r.bind == "nobind" and "Doesn't bind" or "Any quality"
    if #active > 1 then filterText = filterText .. " +" .. (#active - 1) end
    local function SummaryChip(key, text, iconPath, x, width, tab)
        local chip = Get(key .. "face", function()
            local frame = CreateFrame("Button", nil, f)
            if R.SettingsCraft then R.SettingsCraft.Sheet(frame, "chip", { layer = "BACKGROUND", corner = 6 }) end
            return frame
        end)
        At(chip, x, top + 44); chip:SetSize(width, 25); chip:SetFrameLevel(f:GetFrameLevel() + 1)
        chip:SetScript("OnClick", function() filterQuery = ""; P.OpenItemFilters(tab) end)
        local label = Text(key, "small"); label:SetParent(chip); label:ClearAllPoints(); label:SetPoint("LEFT", chip, "LEFT", 27, 0); label:SetWidth(width - 34); label:SetWordWrap(false); label:SetText(text); Tone(label, "head")
        local art = Get(key .. "art", function() return chip:CreateTexture(nil, "ARTWORK") end)
        art:ClearAllPoints(); art:SetPoint("LEFT", chip, "LEFT", 5, 0); art:SetSize(18, 18); art:SetTexture(R.PATH .. iconPath)
        chip.itemSummary = criteria .. "\nListed inclusions bypass filters; exclusions and protections still apply."
        if R.SettingsMaterial and not chip.summaryHelp then
            chip.summaryHelp = true; R.SettingsMaterial.ContextTip(chip, "Item criteria", function(self) return self.itemSummary end)
        end
    end
    local tagWidth = math.floor((col - 30) / 2)
    SummaryChip("itemsSummary", categoryText, #r.cats == 1 and P.CategoryArtwork(r.cats[1]) or [[media\icons\magicReagents-small]], left + 12, tagWidth, "categories")
    SummaryChip("activeItemFilters", filterText, qualityIcon or (r.equip ~= "any" and NPC .. "sword-and-shield-small" or r.bind ~= "any" and Painted("unbound") or NPC .. "reagent-pouch-small"), left + 18 + tagWidth, tagWidth, "filters")
    local consumables = false; for _, key in ipairs(r.cats) do if key == "0" or key:match("^0:") then consumables = true end end
    local quick = {
        { "Categories", "categories", #r.cats > 0, [[media\icons\magicReagents-small]] },
        { "Consumables", "categories", consumables, [[media\healerwatch\vessel-small]], MI().CategoryName("0") or "" },
        { "Equipment", "filters", r.equip ~= "any", NPC .. "sword-and-shield-small" },
        { "Specific items", "include", next(r.include) ~= nil, NPC .. "sealed-scroll-small" },
    }
    for i, choice in ipairs(quick) do
        local button = Get("quickCategory" .. i, function() return Wg().Tab(f, "", tagWidth, function() end) end)
        button.text:SetText(choice[1]); button:SetSelected(choice[3])
        button:SetScript("OnClick", function() filterQuery = choice[5] or ""; P.OpenItemFilters(choice[2]) end)
        button:SetSize(tagWidth, 34)
        At(button, left + 12 + ((i - 1) % 2) * (tagWidth + 6), top + 82 + math.floor((i - 1) / 2) * 40)
        local art = Get("quickArtFrame" .. i, function() local frame = CreateFrame("Frame", nil, button); frame.tex = frame:CreateTexture(nil, "ARTWORK"); frame.tex:SetAllPoints(); return frame end)
        art:SetFrameLevel(button:GetFrameLevel() + 4); art:ClearAllPoints(); art:SetPoint("LEFT", button, "LEFT", 4, 0); art:SetSize(20, 20); art.tex:SetTexture(R.PATH .. choice[4])
        local mark = Get("quickSelected" .. i, function() return art:CreateTexture(nil, "OVERLAY") end)
        mark:SetTexture(R.PATH .. [[media\guides\status-done-small]]); mark:ClearAllPoints(); mark:SetPoint("RIGHT", button, "RIGHT", -4, 0); mark:SetSize(13, 13); mark:SetShown(choice[3])
        button.text:ClearAllPoints(); button.text:SetPoint("LEFT", button, "LEFT", 26, 0); button.text:SetPoint("RIGHT", button, "RIGHT", choice[3] and -18 or -4, 0)
    end
    iy = top + 164
    local function SelectedItem(prefix, set, x, py, width, empty)
        local ids = {}; for id in pairs(set) do ids[#ids + 1] = id end; table.sort(ids)
        local id = ids[1]
        local face = Get(prefix .. "face", function()
            local frame = CreateFrame("Frame", nil, f)
            if R.SettingsMaterial then R.SettingsMaterial.PanelFace(frame, "canvas") end
            return frame
        end)
        At(face, x, py); face:SetSize(width, 34); face:SetFrameLevel(f:GetFrameLevel())
        local name = Text(prefix .. "name", "small"); name:SetParent(face); name:ClearAllPoints(); name:SetPoint("LEFT", face, "LEFT", id and 38 or 8, 0); name:SetWidth(width - (id and 76 or 16)); name:SetHeight(30)
        name:SetMaxLines(2)
        if id then
            local facts = MI().ItemFacts(id)
            name:SetText((facts and facts.name or ("Item " .. id)) .. (#ids > 1 and (" (+" .. (#ids - 1) .. " more)") or ""))
            face:EnableMouse(true); R.Interact.Tip(face, facts and facts.name or ("Item " .. id), prefix == "selectedInclude" and "Explicit inclusion: matches regardless of filters. Exclusions and protections still apply." or "Rule-specific exclusion: never matches this rule, even if explicitly included.")
            local icon = Icon(prefix .. "icon"); At(icon, x + 4, py + 4); icon.tex:SetTexture(facts and facts.icon or QUESTION); icon.itemID = id
            Button(prefix .. "remove", "x", 26, "secondary", function() set[id] = nil; P.QueueRefresh() end); At(pool[prefix .. "remove"], x + width - 30, py + 5)
        else name:SetText(empty) end
    end
    SelectedItem("selectedInclude", r.include, left + 12, iy, col - 24, HasItemFilters(r) and "No explicit inclusions" or "Add specific items to match.")
    iy = top + 206
    Button("builderPick", "Choose from bags", col - 24, "secondary", function()
        MI().Picker.Open({ purpose = "Include specific items", selected = r.include, onDone = function(set)
            r.include = set; for id in pairs(set) do r.exclude[id] = nil end; P.QueueRefresh() end })
    end); At(pool.builderPick, left + 12, iy); pool.builderPick:SetHeight(26)
    local idBox = Edit("builderId", col - 108); At(idBox, left + 12, iy + 30)
    R.Interact.Tip(idBox, "Add item", "Enter an item ID or paste an item link. Unresolved references keep their identity.")
    if idBox:GetText() == "" then
        local hint = Text("builderIdHint", "small"); hint:SetParent(idBox); hint:ClearAllPoints(); hint:SetPoint("LEFT", idBox, "LEFT", 6, 0); hint:SetText("Item ID or link"); Tone(hint, "quiet")
    end
    if not idBox.hintHook then
        idBox.hintHook = true
        idBox:HookScript("OnTextChanged", function(self) if pool.builderIdHint then pool.builderIdHint:SetShown(self:GetText() == "" and editing ~= nil) end end)
    end
    local function Add(id) r.include[id] = true; r.exclude[id] = nil; P.QueueRefresh() end
    idBox:SetScript("OnEnterPressed", function(self) AddById(self, Add) end)
    Button("builderAdd", "Add item", 74, "secondary", function() AddById(idBox, Add) end); At(pool.builderAdd, left + col - 86, iy + 30)
    local includeMode = Text("builderIncludeMode", "small"); Wide(includeMode, left + 12, top + 266, col - 24); includeMode:SetText(HasItemFilters(r) and "Listed items also match, bypassing filters." or "Only the specific items listed here match."); Tone(includeMode, "dim")
    Button("moreItemFilters", #P.FilterSummary(r) > 0 and "Edit filters..." or "Item filters...", col - 24, "secondary", function() P.OpenItemFilters("filters") end)
    At(pool.moreItemFilters, left + 12, top + 288); pool.moreItemFilters:SetHeight(24)
    local function Illustrate(key, button, texture)
        local art = Get(key, function()
            local frame = CreateFrame("Frame", nil, button); frame.tex = frame:CreateTexture(nil, "ARTWORK"); frame.tex:SetAllPoints(); return frame
        end)
        art:SetFrameLevel(button:GetFrameLevel() + 4); art:ClearAllPoints(); art:SetPoint("LEFT", button, "LEFT", 6, 0); art:SetSize(22, 22); art.tex:SetTexture(texture)
        button.text:ClearAllPoints(); button.text:SetPoint("LEFT", button, "LEFT", 34, 0); button.text:SetPoint("RIGHT", button, "RIGHT", -6, 0)
        local mark = Get(key .. "selected", function() return art:CreateTexture(nil, "OVERLAY") end)
        mark:SetTexture(R.PATH .. [[media\guides\status-done-small]]); mark:ClearAllPoints(); mark:SetPoint("RIGHT", button, "RIGHT", -8, 0); mark:SetSize(18, 18)
        mark:SetShown(button.twichSelected == true or (button.IsSelected and button:IsSelected()))
        button.text:SetPoint("RIGHT", button, "RIGHT", -30, 0)
        return art
    end
    local dy = Panel("destinationPanel", "Where should they go?", mid, top, col, 320)
    -- Presentation order follows the player's destination choices; the stored kind and engine order are unchanged.
    for i, kind in ipairs({ "bank", "guild", "mail", "keep", "never" }) do
        local b = Get("destinationChoice" .. kind, function() return Wg().Tab(f, "", col - 24, function() end) end)
        local labels = { bank = "My bank", guild = "Guild bank", mail = "Mail to recipient..." }
        b.text:SetText(labels[kind] or MI().KIND_LABEL[kind]); b:SetSelected(r.kind == kind)
        b:SetScript("OnClick", function()
            r.kind = kind
            if MI().HAS_FLOW[kind] then r.flow = r.flow or "deposit" end
            if not MI().NEEDS_DEST[kind] then r.dest = nil
            elseif r.dest then local d = MI().Dest(r.dest); if not d or d.kind ~= kind then r.dest = nil end end
            P.QueueRefresh()
        end)
        b:SetHeight(36); At(b, mid + 12, dy + (i - 1) * 40)
        local icons = { bank = "coins", guild = "tabard", mail = "sealed-scroll", keep = "leather-backpack", never = "sword-and-shield" }
        b.twichSelected = r.kind == kind
        Illustrate("destinationArt" .. kind, b, kind == "bank" and R.PATH .. [[media\icons\magicBank-small]] or R.PATH .. "media\\npcs\\" .. icons[kind] .. "-small")
    end
    Button("advancedDestination", "Destination details", col - 24, "secondary", function() destAdvanced = not destAdvanced; P.QueueRefresh() end)
    At(pool.advancedDestination, mid + 12, top + 284)
    local bottom = top + 332
    local fy = Panel("flowPanel", "How should they move?", left, bottom, col, 244)
    if MI().HAS_FLOW[r.kind] and not r.design then
        for i, flow in ipairs(MI().FLOW_ORDER) do
            local b = Get("flowChoice" .. flow, function() return Wg().Tab(f, "", col - 24, function() end) end)
            b.text:SetText(MI().FLOW_LABEL[flow]); b:SetSelected((r.flow or "deposit") == flow)
            b:SetScript("OnClick", function()
                r.flow = flow; if flow ~= "deposit" and (r.keep or 0) <= 0 then r.keep = 20 end; P.QueueRefresh()
            end)
            b:SetHeight(34); At(b, left + 12, fy + (i - 1) * 40)
            b.twichSelected = (r.flow or "deposit") == flow
            local art = Illustrate("flowArt" .. flow, b, flow == "balance" and R.PATH .. [[media\npcs\balance-scales-small]] or R.PATH .. [[media\guides\status-current-small]])
            if flow ~= "balance" then art.tex:SetRotation(flow == "deposit" and -math.pi / 2 or math.pi / 2) end
        end
    else
        local t = Text("noFlow", "small"); Wide(t, left + 12, fy, col - 24)
        t:SetText("This action has no transfer direction. No items move while editing.")
    end
    local flowHelp = Text("selectedFlowHelp", "small"); Wide(flowHelp, left + 12, bottom + 170, col - 24)
    local flowWords = { deposit = "Deposit extras above the keep amount.", withdraw = "Withdraw whole stacks up to the target, never over it.", balance = "Deposit extras and withdraw whole stacks up to the target." }
    flowHelp:SetText(MI().HAS_FLOW[r.kind] and not r.design and flowWords[r.flow or "deposit"] or "")
    local ky = Panel("limitsPanel", "What should stay?", mid, bottom, col, 244)
    local qty = Edit("builderKeep", 72); At(qty, mid + 140, ky); qty:SetWidth(60)
    Button("keepMinus", "-", 28, "secondary", r.kind ~= "never" and function() if pool.builderKeep:HasFocus() then pool.builderKeep:ClearFocus() end; r.keep = math.max(0, (r.keep or 0) - 1); P.QueueRefresh() end or nil)
    At(pool.keepMinus, mid + 108, ky)
    Button("keepPlus", "+", 28, "secondary", r.kind ~= "never" and function() if pool.builderKeep:HasFocus() then pool.builderKeep:ClearFocus() end; r.keep = math.min(MI().MAX_KEEP, (r.keep or 0) + 1); P.QueueRefresh() end or nil)
    At(pool.keepPlus, mid + 208, ky)
    qty:SetEnabled(r.kind ~= "never")
    if not qty:HasFocus() then qty:SetText(tostring(r.keep or 0)) end
    qty.read = function(self)
        if not editing then return end
        local n = tonumber(self:GetText())
        if n and n >= 0 and n <= MI().MAX_KEEP and n == math.floor(n) then editing.keep = n
        else self:SetText(tostring(editing.keep or 0)); Say("Enter a valid whole keep quantity.", "warn") end
        P.QueueRefresh()
    end
    qty:SetScript("OnEnterPressed", function(self) self:read(); self:ClearFocus() end)
    qty:SetScript("OnEscapePressed", function(self) self:SetText(tostring(editing.keep or 0)); self:ClearFocus() end)
    if not qty.builderHook then qty.builderHook = true; qty:HookScript("OnEditFocusLost", function(self) self:read() end) end
    local unit = Text("builderKeepUnit", "small"); Wide(unit, mid + 12, ky + 4, 94); unit:SetText("Keep in bags:")
    local exclusion = Text("builderExclusions", "small"); Wide(exclusion, mid + 12, ky + 40, col - 24)
    exclusion:SetText("Never include these:")
    Button("advancedLimits", "Exclusions and limits", col - 24, "secondary", function() limitsAdvanced = not limitsAdvanced; P.QueueRefresh() end)
    At(pool.advancedLimits, mid + 12, bottom + 188)
    local safe = Text("builderSafety", "small"); Wide(safe, mid + 12, bottom + 214, col - 24)
    safe:SetText("Existing item protections still apply.")
    SelectedItem("selectedExclude", r.exclude, mid + 12, bottom + 105, col - 24, "No rule-specific exclusions")
    Button("excludePick", "Choose exclusions...", col - 24, "secondary", function()
        MI().Picker.Open({ purpose = "Exclude item types from this rule", selected = r.exclude, onDone = function(set)
            r.exclude = set; P.QueueRefresh() end })
    end); At(pool.excludePick, mid + 12, bottom + 148)
    local rx, ry, rw = cols == 3 and (mid + col + 12) or PAD, cols == 3 and top or (bottom + 256), cols == 3 and col or full
    local reviewY = Panel("reviewPanel", "Rule review", rx, ry, rw, cols == 3 and 576 or 210)
    local actionLabel, destinationLabel = P.RowCells(r)
    destinationLabel = r.kind == "bank" and "My bank" or r.kind == "keep" and "Bags" or r.kind == "never" and "No transfers" or destinationLabel
    local reviewArt = Get("reviewIdentityArt", function() return pool.reviewPanel:CreateTexture(nil, "ARTWORK") end)
    reviewArt:ClearAllPoints(); reviewArt:SetPoint("TOPLEFT", pool.reviewPanel, "TOPLEFT", 12, -44); reviewArt:SetSize(40, 40); PaintRuleArtwork(reviewArt, r)
    local identity = Text("reviewIdentity", "body"); Wide(identity, rx + 62, reviewY + 8, rw - 74); identity:SetParent(pool.reviewPanel); identity:SetText(r.name or "New rule"); identity:SetHeight(32)
    reviewY = reviewY + 60
    local summaryHeight = 0
    local fields = { { "Applies to", P.ItemsText(r) }, { "Destination", destinationLabel }, { "Behavior", actionLabel }, { "Keep in bags", r.kind == "never" and "All matching items" or r.keep > 0 and (r.keep .. " of each") or P.KeepText(r) } }
    for i, field in ipairs(fields) do
        local label = Text("reviewLabel" .. i, "small"); label:SetParent(pool.reviewPanel); Wide(label, rx + 12, reviewY + summaryHeight, 88); label:SetText(field[1] .. ":"); Tone(label, "dim")
        local value = Text("reviewValue" .. i, "body"); value:SetParent(pool.reviewPanel); Wide(value, rx + 108, reviewY + summaryHeight, rw - 120); value:SetText(field[2])
        summaryHeight = summaryHeight + math.max(H(label), H(value)) + 12
    end
    R.Interact.Tip(pool.reviewPanel, "Rule review", P.Sentence(r))
    local probe = MI().CleanRule((function() local copy = {} for k, v in pairs(r) do copy[k] = v end copy.id = copy.id or "rnew" return copy end)())
    local code, why = MI().Problem(probe, false)
    local ready = Text("builderReady", "body"); Wide(ready, rx + 12, reviewY + summaryHeight + 18, rw - 24)
    ready:SetText(code and ("Needs attention: " .. (why or code)) or "Ready to save"); Tone(ready, code and "warn" or nil)
    ready:SetParent(pool.reviewPanel)
    local statusFace = Get("reviewStatusFace", function()
        local frame = CreateFrame("Frame", nil, pool.reviewPanel)
        if R.SettingsCraft then frame.face = R.SettingsCraft.Sheet(frame, "selection", { layer = "BACKGROUND", corner = 8 }) end
        return frame
    end)
    if statusFace.face then statusFace.face:SetTint(code and .85 or .58, code and .75 or .76, code and .57 or .36) end
    At(statusFace, rx + 10, reviewY + summaryHeight + 10); statusFace:SetSize(rw - 20, H(ready) + 30)
    ready:SetParent(statusFace)
    local stateArt = Get("reviewStateArt", function() return statusFace:CreateTexture(nil, "ARTWORK") end)
    stateArt:SetTexture(R.PATH .. (code and [[media\guides\status-current-small]] or [[media\guides\status-done-small]])); stateArt:ClearAllPoints(); stateArt:SetPoint("LEFT", statusFace, "LEFT", 5, 0); stateArt:SetSize(22, 22)
    ready:ClearAllPoints(); ready:SetPoint("LEFT", statusFace, "LEFT", 34, 0); ready:SetWidth(rw - 62); statusFace:SetHeight(H(ready) + 24)
    local reviewHeight = math.max(cols == 3 and 576 or 260, 104 + summaryHeight + 18 + H(ready) + 104)
    pool.reviewPanel:SetHeight(reviewHeight)
    local safety = Text("reviewSafety", "small"); Wide(safety, rx + 14, ry + reviewHeight - 104, rw - 28); safety:SetParent(pool.reviewPanel)
    safety:SetText("Nothing moves automatically. Transfers still require review and your action.")
    local enabled = Check("e4on", function(v) turnOn = v; P.QueueRefresh() end)
    enabled:SetChecked(turnOn and not code); enabled:SetActive(not code)
    At(enabled, rx + 12, ry + reviewHeight - 48)
    local enText = Text("e4onT", "small"); Wide(enText, rx + 52, ry + reviewHeight - 46, rw - 64); enText:SetText("Enable when saved")
    if code then turnOn = false end
    y = math.max(bottom + 256, ry + reviewHeight + 12)
    if destAdvanced then y = DrawDestStep(y) + 16 end
    if limitsAdvanced then y = DrawKeepStep(y) + 16 end
    if r.id then
        Button("builderDelete", "Delete", 84, "danger", function()
            local id = r.id
            R.Interact.Confirm("TWICHUI_MI_RULE_DELETE", "Delete the saved rule and discard this draft? No items move.", function()
                MI().DeleteRule(id); editing = nil; P.QueueRefresh(); QueueRelayout()
            end, { accept = "Delete" })
        end); At(pool.builderDelete, PAD, y); pool.builderDelete:SetHeight(32)
        Button("builderDuplicate", "Duplicate", 120, "secondary", function()
            local copy = MI().CleanRule(r); copy.id = nil; copy.name = (copy.name .. " copy"):sub(1, MI().MAX_NAME); copy.enabled = false; StartEdit(copy)
        end); At(pool.builderDuplicate, PAD + 92, y); pool.builderDuplicate:SetHeight(32)
        local copyArt = Get("builderDuplicateArt", function()
            local frame = CreateFrame("Frame", nil, pool.builderDuplicate); frame.tex = frame:CreateTexture(nil, "ARTWORK"); frame.tex:SetAllPoints(); return frame
        end)
        copyArt:SetFrameLevel(pool.builderDuplicate:GetFrameLevel() + 4); copyArt:ClearAllPoints(); copyArt:SetPoint("LEFT", pool.builderDuplicate, "LEFT", 6, 0); copyArt:SetSize(20, 20); copyArt.tex:SetTexture(R.PATH .. [[media\npcs\sealed-scroll-small]])
        pool.builderDuplicate.text:ClearAllPoints(); pool.builderDuplicate.text:SetPoint("LEFT", pool.builderDuplicate, "LEFT", 30, 0); pool.builderDuplicate.text:SetPoint("RIGHT", pool.builderDuplicate, "RIGHT", -6, 0)
    end
    Button("eCancel", "Cancel", 90, "secondary", function()
        editing = nil
        said = nil
        P.QueueRefresh()
        QueueRelayout()
    end)
    At(pool.eCancel, full + PAD - 190, y)
    pool.eCancel:SetHeight(32)
    Button("eSave", "Save", 90, "primary", function()
        if pool.builderKeep and pool.builderKeep:HasFocus() then pool.builderKeep:ClearFocus() end
        local rule = editing
        rule.enabled = turnOn
        local id, why = MI().SaveRule(rule)
        if not id then Say(why, "warn") return end
        local saved = MI().Rule(id)
        editing = nil
        if turnOn and saved and not saved.enabled then Say(("Saved \"%s\", turned off: %s"):format(saved.name, select(2, MI().Problem(saved, false)) or ""), "warn")
        else Say(("Saved \"%s\"%s."):format(saved and saved.name or "", saved and saved.enabled and ", turned on" or ", turned off")) end
        QueueRelayout()
    end)
    At(pool.eSave, full + PAD - 90, y)
    pool.eSave:SetHeight(32)
    R.Interact.Tip(pool.eSave, "Save", "Saves the rule. It starts moving items only when you open a mailbox, bank or guild bank, review and press the action yourself.")
    return y + 34
end

function P.Refresh()
    if not (f and f:IsShown() and built) then return end
    local view = R.SettingsUI and R.SettingsUI.View and R.SettingsUI.View("magicInventory")
    if view and view.reset then
        view.reset.button:SetEnabled(editing == nil)
        view.reset.text:SetText(editing and "Save or cancel the rule draft before resetting this page." or "Reset this page's settings. The confirmation lists what changes; saved inventory rules are retained.")
    end
    for k in pairs(touched) do touched[k] = nil end
    local y = 4
    if said then
        local s = Text("said", "small")
        Wide(s, PAD, y)
        s:SetText(said)
        Tone(s, saidTone == "warn" and "warn" or "dim")
        y = y + H(s) + 8
    end
    if editing then
        y = DrawEditor(y)
    else
        local tasks = { { "rules", "Your rules", 140 }, { "destinations", "Destinations", 140 },
            { "guild", "Guild arrangement", 174 }, { "protected", "Protected items", 148 } }
        local x = PAD
        local tabWidth = math.floor((math.max(W, f:GetWidth() or W) - PAD * 2 - 18) / 4)
        local tabIcons = { rules = "sealed-scroll", destinations = "coins", guild = "tabard", protected = "sword-and-shield" }
        for _, entry in ipairs(tasks) do
            local b = Get("task" .. entry[1], function()
                return Wg().Tab(f, entry[2], entry[3], function() P.SetTask(entry[1]) end)
            end)
            b:SetSize(tabWidth, 36)
            b.text:SetText(entry[1] == "guild" and tabWidth < 200 and "Guild layout" or entry[2])
            local art = Get("taskArt" .. entry[1], function()
                local holder = CreateFrame("Frame", nil, b); holder.tex = holder:CreateTexture(nil, "ARTWORK"); holder.tex:SetAllPoints(); return holder
            end)
            art:SetFrameLevel(b:GetFrameLevel() + 4); art:ClearAllPoints(); art:SetPoint("LEFT", b, "LEFT", 6, 0); art:SetSize(20, 20)
            art.tex:SetTexture(entry[1] == "destinations" and R.PATH .. [[media\icons\magicBank-small]] or R.PATH .. "media\\npcs\\" .. tabIcons[entry[1]] .. "-small")
            b.text:ClearAllPoints(); b.text:SetPoint("LEFT", b, "LEFT", 32, 0); b.text:SetPoint("RIGHT", b, "RIGHT", -4, 0)
            At(b, x, y); b:SetSelected(task == entry[1]); x = x + tabWidth + 6
        end
        y = y + 42
        if task == "guild" and P.DrawGuildPreview then y = P.DrawGuildPreview(y)
        elseif task == "destinations" then y = DrawDests(y)
        elseif task == "protected" then y = DrawNever(y)
        else y = DrawList(y) end
    end
    if editing and itemAdvanced then DrawItemFilters() end
    for k, c in pairs(pool) do if not touched[k] then c:Hide() end end
    local newHeight = math.max(120, y + 8)
    f:SetHeight(newHeight)
    if newHeight ~= height then
        height = newHeight
        QueueRelayout()
    end
end

local function Build()
    built = true
end

-- Only while the page is shown: answers about items named here, and the bags and guild bank for the destinations.
local EVENTS = { "GET_ITEM_INFO_RECEIVED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANK_UPDATE_TABS", "GUILDBANKBAGSLOTS_CHANGED", "BAG_UPDATE_DELAYED" }

function P.Frame()
    if f then return f end
    f = CreateFrame("Frame")
    f:SetWidth(W)
    f:Hide()
    f:SetScript("OnShow", function(self)
        if not built then
            Build()
            if MI().GuildBank and MI().GuildBank.IsOpen() then task = "guild" end
        end
        for _, e in ipairs(EVENTS) do self:RegisterEvent(e) end
        P.Refresh()
    end)
    f:SetScript("OnSizeChanged", function() if built then P.QueueRefresh() end end)
    f:SetScript("OnHide", function(self)
        itemAdvanced = false
        if pool.filterEditor then pool.filterEditor:Hide(); pool.filterShade:Hide() end
        if P.GuildHidden then P.GuildHidden() end
        local src = P.Drag and P.Drag.Active() and P.Drag.Source()
        if src and src.kind == "rule" then P.Drag.Cancel() end
        for _, e in ipairs(EVENTS) do self:UnregisterEvent(e) end
        for _, c in pairs(pool) do if c.ClearFocus then c:ClearFocus() end end
        said = nil
        local mi = MI()
        if mi and mi.Picker and mi.Picker.IsShown() then mi.Picker.Cancel() end
    end)
    f:SetScript("OnEvent", function(_, event)
        if P.OnEvent then P.OnEvent(event) end
        P.QueueRefresh()
    end)
    return f
end

function P.SetTask(key)
    if key ~= "rules" and key ~= "destinations" and key ~= "guild" and key ~= "protected" then return false end
    if editing then return false end -- Save or Cancel the existing private edit before switching tasks.
    if P.Drag and P.Drag.Active() then P.Drag.Cancel() end
    if P.GuildHidden then P.GuildHidden() end
    task = key; said = nil
    P.QueueRefresh(); QueueRelayout()
    return true
end
function P.Task() return task end
function P.Editing() return editing end
function P.ControlCount() local n = 0 for _ in pairs(pool) do n = n + 1 end return n end
P.NewFromTemplate = NewFromTemplate   -- the New rule list's choice, by template key
function P.Control(key) return pool[key] end

-- A change made anywhere (here, the review, a profile change) redraws the page if it is shown. Registered once.
if R.MagicInventory then R.MagicInventory.OnChange(function() P.QueueRefresh() end) end
-- A rule being edited belongs to the profile it came from: a profile change puts the editor away, unsaved.
if R.Profiles and R.Profiles.OnApply then
    R.Profiles.OnApply("views", "magic-inventory-page", function()
        editing = nil; selectedRule = nil; itemAdvanced = false
        if pool.filterEditor then pool.filterEditor:Hide(); pool.filterShade:Hide() end
        if P.GuildProfileChanged then P.GuildProfileChanged() end
        P.QueueRefresh()
    end)
end

local function Count()
    local n, on = 0, 0
    for _, r in ipairs(R.MagicInventory.Rules()) do
        n = n + 1
        if r.enabled then on = on + 1 end
    end
    return n, on
end

K.Page({
    key = "magicInventory", icon = "magicInventory", name = "Magic Inventory", order = 47, group = "everyday", compact = true,
    description = "Rules that pick out items to mail to a character you name, or deposit in your bank or a guild bank tab. Nothing moves until you review it and press the action yourself.",
    keywords = "magic inventory mail mailbox send bank deposit guild bank tab bank alt alt cloth herbs ore materials mats disenchant boe bind on equip greens transfer move route rules keep never transfer recipient",
    when = function() return R.MagicInventory ~= nil and R.MagicInventory.Run ~= nil end,
    overview = {
        label = "Magic Inventory", tip = "Rules that prepare items to mail or deposit; nothing moves until you review and click.",
        when = function() return R.MagicInventory ~= nil end,
        status = function()
            if not R:Enabled("magicInventory") or not R.MagicInventory.Enabled() then return K.OnOff(false) end
            local n, on = Count()
            if n == 0 then return K.OnOff(false, nil, "No rules yet") end
            return K.OnOff(on > 0, ("%d of %d rules on"):format(on, n), ("%d, none on"):format(n))
        end,
    },
    build = function()
        K.Card({
            title = "Magic Inventory", icon = "magicInventory", inPageHeader = true, compact = true,
            help = "Nothing moves by itself. Review the proposed moves at the mailbox, bank or guild bank and press the action yourself. Sent mail and deposits cannot be undone. No money is sent and C.O.D. is never used. Withdrawals require a rule and take whole stacks without passing its target.\n\nQuest items, conjured items, equipment-set items, locked items and the Never transfer list are protected. Soulbound items never go by mail or to guild banks. Uncertain item data is left alone.\n\nRecipients belong to this character unless you choose All my characters; they stay out of configuration shares and backups. Names are checked for form, not whether the recipient exists.",
            what = "Picks out items by rules you make (cloth for your bank alt, herbs for your bank, green gear for a friend) and lists them when you open a mailbox, bank or guild bank.",
            summary = function()
                local n, on = Count()
                if n == 0 then return "No rules yet." end
                return ("%d %s, %d turned on."):format(n, n == 1 and "rule" or "rules", on)
            end,
            consequence = "Nothing moves by itself. At the mailbox, bank or guild bank a small Magic Inventory button opens a review of exactly what would move and where; you prepare and send each mail, or deposit, with your own click. Sent mail and deposits can't be undone. No money is sent and C.O.D. is never used. Nothing is taken out of a bank unless a rule says to withdraw, and then only whole stacks, never past its target.",
            details = {
                { "Which items are never moved?", "Quest items, conjured items, items in an equipment set, locked items, anything on the Never transfer list, and soulbound items by mail or to a guild bank (your own bank can take them). An item the game hasn't fully described yet is left where it is." },
                { "Who gets my recipients?", "Only the character you set them on, unless you tick \"All my characters\". Recipients are kept out of shared settings and backups. TwichUI checks a name's form, not whether the character exists or who plays it." },
                { "What about guild banks?", "The game has the guild bank window, but whether Forever's realms have guild vaults isn't known to TwichUI. If one opens, its button appears there too." },
            },
        })
        K.Toggle("magicInventory", "Use Magic Inventory",
            "On: the Magic Inventory button appears at a mailbox, bank or guild bank, and its review lists what your rules would move. Nothing moves until you press an action there. Off: no button and nothing is listened for. Your rules are kept either way.")
    end,
    host = function() return P.Frame() end, hostAfter = "Magic Inventory", hostHeight = function() return P.Height() end,
})
