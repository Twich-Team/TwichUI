-- TwichUI Fishing: the fishing pole, the optional fishing outfit, and putting your own gear back
--
-- Equipping is always the player's key press: the fishing key's secure action (Action.lua) uses the pole (type "item":
-- SECURE_ACTIONS.item equips an equippable item that is not worn, Blizzard_FrameXML/SecureTemplates.lua) or puts on the
-- outfit (type "equipmentset", C_EquipmentSet.UseEquipmentSet). Just before that press acts, Capture keeps what was worn
-- (TwichUIFishingDB.chars[...].gear.snapshot: item id and link per slot). A snapshot already kept is never replaced, so
-- the original gear is never overwritten by fishing gear.
--
-- Putting it back (Restore): when the session ends (config gear.restoreOnEnd), on /tui fish restore, or with the fishing
-- key while a restoration is pending. Out of combat it uses C_Item.EquipItemByName(link, slot) from addon code, which the
-- Forever API documentation does not mark as restricted; whether the client allows it outside a key press is NOT verified
-- in the game, so a failed or blocked restoration is kept as "pending" and the fishing key then does it as a secure
-- /equipslot macro (a secure slash command, Blizzard_ChatFrameBase/Shared/SlashCommands.lua). In combat nothing is
-- changed by addon code; with config gear.combatWeapons the fishing key is set up as combat begins to put your weapons back
-- with that same secure macro, on your press.
--
-- Changes the player makes while fishing are kept: a slot the player changes to anything other than a fishing pole is
-- dropped from the restoration (and a slot the player puts back by hand counts as restored). The snapshot is cleared only
-- when every slot in it is back or was the player's own choice, or by /tui fish forget.

local R = TwichUI
local F = R.Fishing
local S = F.Store
local G = {}
F.Gear = G

local expect = nil        -- { kind = "equip" | "restore", slots = { [slot] = true }, untilAt, fresh }
G.EXPECT_SECONDS = 2.5

local function Record()
    local c = S.Char()
    return c and c.gear or nil
end

function G.State()
    local g = Record()
    return g and g.state or "none"
end

function G.Snapshot()
    local g = Record()
    return g and g.snapshot or nil
end

---------------------------------------------------------------------------
-- Reading the game
---------------------------------------------------------------------------
function G.IsPole(itemID)
    itemID = F.Count(itemID)
    if not (itemID and C_Item and C_Item.GetItemInfoInstant) then return false end
    local _, _, _, _, _, class, sub = C_Item.GetItemInfoInstant(itemID)
    return F.Num(class) == F.WEAPON_CLASS and F.Num(sub) == F.POLE_SUBCLASS
end

-- The item worn in a slot: id and link (nil, nil when empty or unreadable).
function G.Worn(slot)
    local id = GetInventoryItemID and F.Count(GetInventoryItemID("player", slot))
    if not id then return nil, nil end
    local link = GetInventoryItemLink and F.Readable(GetInventoryItemLink("player", slot))
    return id, type(link) == "string" and link or nil
end

function G.PoleWorn()
    return G.IsPole((G.Worn(F.MAINHAND)))
end

-- Every bag slot as { bag, slot, item, link, count, hasLoot, locked, quality }; fn(entry) is called for each (stop: return true).
function G.EachBagItem(fn)
    local C = C_Container
    if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return end
    for _, bag in ipairs(F.BAGS) do
        local n = F.Count(C.GetContainerNumSlots(bag)) or 0
        for slot = 1, n do
            local info = C.GetContainerItemInfo(bag, slot)
            if type(info) == "table" then
                local id = F.Count(info.itemID)
                if id and fn({ bag = bag, slot = slot, item = id, link = F.Readable(info.hyperlink), count = F.Count(info.stackCount) or 1,
                    hasLoot = F.Readable(info.hasLoot) == true, locked = F.Readable(info.isLocked) == true,
                    quality = F.Num(info.quality) or 0 }) then return end
            end
        end
    end
end

function G.FreeSlots()
    local C = C_Container
    if not (C and C.GetContainerNumFreeSlots) then return nil end
    local free = 0
    for _, bag in ipairs(F.BAGS) do
        local n, family = C.GetContainerNumFreeSlots(bag)
        n, family = F.Count(n), F.Num(family)
        if n and (family == nil or family == 0) then free = free + n end
    end
    return free
end

function G.BagCount(itemID)
    local n = 0
    G.EachBagItem(function(e) if e.item == itemID then n = n + e.count end end)
    return n
end

-- The pole to equip: the preferred one if it is in the bags, otherwise the best other pole there (highest quality, then
-- the first found). nil when no pole is in the bags. preferredMissing is true when a preferred pole is set but not found.
function G.FindPole()
    local want = S.Get("gear.pole")
    local best, preferred
    G.EachBagItem(function(e)
        if G.IsPole(e.item) then
            if want and e.item == want and not preferred then preferred = e end
            if not best or e.quality > best.quality then best = e end
        end
    end)
    if preferred then return preferred, false end
    return best, want and true or false
end

-- The outfit chosen in the settings: its equipment set id, whether it is worn, and why not when it can't be used.
function G.Outfit()
    local name = S.Get("gear.outfit")
    if not name then return nil end
    local E = C_EquipmentSet
    if not (E and E.GetEquipmentSetID and E.GetEquipmentSetInfo) then return nil, nil, "unsupported" end
    if E.CanUseEquipmentSets and not F.Readable(E.CanUseEquipmentSets()) then return nil, nil, "unsupported" end
    local id = F.Count(E.GetEquipmentSetID(name))
    if not id then return nil, nil, "missing" end
    local _, _, _, isEquipped = E.GetEquipmentSetInfo(id)
    return id, F.Readable(isEquipped) == true, nil
end

---------------------------------------------------------------------------
-- What the fishing key should do about gear (Action.lua asks; nothing changes here)
--   { kind = "outfit", name } | { kind = "equip", item, bag, slot } | { kind = "none", why } | nil (nothing to do)
---------------------------------------------------------------------------
function G.Plan()
    if not S.Get("gear.manage") then return nil end
    local outfitID, outfitWorn, outfitWhy = G.Outfit()
    if outfitID and not outfitWorn then
        if (G.FreeSlots() or 0) < 1 then return { kind = "none", why = "bags-full" } end
        return { kind = "outfit", name = S.Get("gear.outfit"), set = outfitID }
    end
    if outfitWhy == "missing" then F.Note("outfit-missing") end
    if G.PoleWorn() then return nil end
    local pole, preferredMissing = G.FindPole()
    if not pole then return { kind = "none", why = "no-pole" } end
    -- A pole takes both hands: whatever is in the off hand needs a free bag slot (the pole's own slot takes the main hand).
    if G.Worn(F.OFFHAND) and (G.FreeSlots() or 0) < 1 then return { kind = "none", why = "bags-full" } end
    return { kind = "equip", item = pole.item, bag = pole.bag, slot = pole.slot, preferredMissing = preferredMissing }
end

---------------------------------------------------------------------------
-- The snapshot
---------------------------------------------------------------------------
-- Keeps what is worn in the slots a change will touch. Never replaces a snapshot already kept.
function G.Capture(kind)
    local g = Record()
    if not g then return false end
    if g.snapshot then return false end
    local slots = {}
    local list = F.WEAPON_SLOTS
    if kind == "outfit" then
        list = {}
        for s = F.FIRST_SLOT, F.LAST_SLOT do list[#list + 1] = s end
    end
    for _, slot in ipairs(list) do
        local id, link = G.Worn(slot)
        slots[slot] = { id = id or 0, link = link }
    end
    g.snapshot = { at = F.Now(), kind = kind == "outfit" and "outfit" or "pole", slots = slots }
    g.state = "fishing"
    F.Emit("GEAR", "captured")
    return true
end

local function Clear(why)
    local g = Record()
    if not g then return end
    g.snapshot, g.state, g.failed = nil, "none", nil
    F.Emit("GEAR", why or "cleared")
end

-- Slots still to put back: { [slot] = entry } (not kept by the player's own choice, not yet back).
function G.Outstanding()
    local snap = G.Snapshot()
    local out, n = {}, 0
    if not snap then return out, 0 end
    for slot, e in pairs(snap.slots) do
        if not (e.kept or e.leave) then
            local id = G.Worn(slot) or 0
            if id ~= e.id then out[slot] = e; n = n + 1 end
        end
    end
    return out, n
end

-- Drops slots that are back (or kept) and clears a snapshot with nothing left to do. Returns what is left.
local function Settle()
    local snap = G.Snapshot()
    if not snap then return 0 end
    -- while the fishing gear is still going on, a slot not changed yet is not "back": wait until the press has settled
    if expect and expect.kind == "equip" and F.Clock() <= expect.untilAt then return -1 end
    local left = 0
    for slot, e in pairs(snap.slots) do
        local id = G.Worn(slot) or 0
        if e.kept or e.leave or id == e.id then
            if not (e.kept or e.leave) then snap.slots[slot] = nil end
        else
            left = left + 1
        end
    end
    if left == 0 then Clear("restored") end
    return left
end
G.Settle = Settle

---------------------------------------------------------------------------
-- Own changes and the player's
---------------------------------------------------------------------------
local function Expect(kind, slots, fresh)
    expect = { kind = kind, slots = slots, untilAt = F.Clock() + G.EXPECT_SECONDS, fresh = fresh }
    if C_Timer and C_Timer.After then C_Timer.After(G.EXPECT_SECONDS + 0.1, function() G.CheckExpect() end) end
end

-- The fishing key is about to equip (Action.lua, just before the secure action runs).
function G.BeginEquip(plan)
    local fresh = G.Capture(plan.kind == "outfit" and "outfit" or "pole")
    local slots = {}
    if plan.kind == "outfit" then for s = F.FIRST_SLOT, F.LAST_SLOT do slots[s] = true end
    else slots[F.MAINHAND], slots[F.OFFHAND] = true, true end
    Expect("equip", slots, fresh)
end

-- The time for an expected change has passed.
function G.CheckExpect()
    local e = expect
    if not e or F.Clock() < e.untilAt then return end
    expect = nil
    if e.kind == "equip" then
        if not G.PoleWorn() and not select(2, G.Outfit()) then
            F.Note("equip-failed", "the fishing gear was not put on")
            -- nothing changed: a snapshot made for this press only is dropped (the gear it describes is still worn)
            if e.fresh and select(2, G.Outstanding()) == 0 then Clear("equip-failed") end
        end
        Settle()
    elseif e.kind == "restore" then
        local left = Settle()
        if left > 0 then
            local g = Record()
            g.state = "pending"
            F.Note("restore-failed", left .. " slot(s) not put back")
            F.Say("TwichUI: your own gear isn't fully back on. Press the fishing key, or type /tui fish restore.")
            F.Emit("GEAR", "pending")
        end
    end
end

function G.OnEquipmentChanged(slot)
    slot = F.Count(slot)
    local snap = G.Snapshot()
    if not (slot and snap) then return end
    local entry = snap.slots[slot]
    local own = expect and expect.slots[slot] and F.Clock() <= expect.untilAt
    if not own and entry and not entry.kept then
        local id = G.Worn(slot) or 0
        if id == entry.id then
            -- the player put it back by hand: that slot is done
        elseif slot == F.MAINHAND and G.IsPole(id) then
            -- another pole: still fishing gear, still to be put back
        elseif slot == F.OFFHAND and G.PoleWorn() then
            -- the pole emptied the off hand: still to be put back
        else
            entry.kept = true
            F.Emit("GEAR", "kept", slot)
        end
    end
    if expect and expect.kind == "restore" and own then
        if select(2, G.Outstanding()) == 0 then expect = nil end
    end
    Settle()
    F.Emit("GEAR", "changed", slot)
end

---------------------------------------------------------------------------
-- Putting it back
---------------------------------------------------------------------------
local ORDER = { F.MAINHAND, F.OFFHAND, F.RANGED }

local function RestoreOrder()
    local snap = G.Snapshot()
    local list, seen = {}, {}
    for _, s in ipairs(ORDER) do if snap.slots[s] then list[#list + 1] = s; seen[s] = true end end
    local rest = {}
    for s in pairs(snap.slots) do if not seen[s] then rest[#rest + 1] = s end end
    table.sort(rest)
    for _, s in ipairs(rest) do list[#list + 1] = s end
    return list
end

local function Have(entry)
    if entry.id == 0 then return true end
    if C_Item and C_Item.GetItemCount then return (F.Count(C_Item.GetItemCount(entry.id)) or 0) > 0 end
    return G.BagCount(entry.id) > 0
end

-- Puts the snapshot back with addon code (out of combat only). Returns "done", "pending", "nothing" or a refusal code.
function G.Restore(reason)
    local g = Record()
    if not (g and g.snapshot) then return "nothing" end
    if Settle() == 0 then return "done" end
    expect = nil
    if F.InCombat() then
        g.state = "pending"
        F.Emit("GEAR", "pending")
        return "combat"
    end
    if not (C_Item and C_Item.EquipItemByName) then
        g.state = "pending"
        F.Note("unsupported", "EquipItemByName")
        return "unsupported"
    end
    local slots, missing = {}, 0
    g.state = "pending"   -- until the changes are seen (a change can be reported while the items are being equipped)
    for _, slot in ipairs(RestoreOrder()) do
        if not g.snapshot then break end
        local e = g.snapshot.slots[slot]
        if e and not (e.kept or e.leave) and (G.Worn(slot) or 0) ~= e.id then
            if e.id == 0 then
                -- the slot was empty and the outfit filled it: taking an item off into the bags is not done by addon code here;
                -- it is left on and reported (docs/fishing-feasibility.md, "Unsupported or restricted")
                e.leave = true
                F.Note("restore-left-on", "slot " .. slot .. " was empty before fishing")
            elseif not Have(e) then
                e.missing = true
                missing = missing + 1
            else
                e.missing = nil
                local ok, err = pcall(C_Item.EquipItemByName, e.link or e.id, slot)
                if not ok then F.Note("restore-error", tostring(err):sub(1, 80)) end
                slots[slot] = true
            end
        end
    end
    if missing > 0 then F.Note("restore-missing", missing .. " item(s) no longer in your bags") end
    if not g.snapshot or Settle() == 0 then return "done" end
    Expect("restore", slots)
    F.Emit("GEAR", "restoring", reason)
    return "pending"
end

-- The secure macro the fishing key runs to put your weapons back (in combat, or when addon code could not): nil when
-- nothing is to be done. Weapons only: armour can't be changed in combat, and the macro names items by id.
function G.RestoreMacro(weaponsOnly)
    local snap = G.Snapshot()
    if not snap then return nil end
    local cmd = (rawget(_G, "SLASH_EQUIP_TO_SLOT1")) or "/equipslot"
    if type(cmd) ~= "string" or not cmd:match("^/[%w_]+$") then cmd = "/equipslot" end
    local lines = {}
    for _, slot in ipairs(RestoreOrder()) do
        local e = snap.slots[slot]
        local weapon = slot == F.MAINHAND or slot == F.OFFHAND or slot == F.RANGED
        if e and not (e.kept or e.leave) and e.id ~= 0 and (G.Worn(slot) or 0) ~= e.id and (weapon or not weaponsOnly) then
            lines[#lines + 1] = ("%s %d item:%d"):format(cmd, slot, e.id)
        end
    end
    if #lines == 0 then return nil end
    return table.concat(lines, "\n")
end

-- The player's key press is about to run the restore macro.
function G.BeginMacroRestore()
    local slots = {}
    for slot in pairs(G.Outstanding()) do slots[slot] = true end
    Expect("restore", slots)
end

function G.OnSessionEnd(reason)
    if S.Get("gear.restoreOnEnd") and G.State() ~= "none" then G.Restore(reason) end
end

-- After a reload or a login: settle the record against what is worn now.
function G.Reconcile()
    if not G.Snapshot() then return end
    Settle()
end

-- /tui fish forget: drop the snapshot without restoring (the player's explicit choice).
function G.Forget()
    if not G.Snapshot() then return false end
    Clear("forgotten")
    return true
end

-- Read only, for diagnostics and later stages.
function G.Status()
    local snap = G.Snapshot()
    local left = select(2, G.Outstanding())
    local kept, missing, leftOn = 0, 0, 0
    if snap then
        for _, e in pairs(snap.slots) do
            if e.kept then kept = kept + 1 end
            if e.leave then leftOn = leftOn + 1 end
            if e.missing then missing = missing + 1 end
        end
    end
    return { state = G.State(), poleWorn = G.PoleWorn(), outstanding = left, kept = kept, missing = missing, leftOn = leftOn,
        since = snap and snap.at or nil, kind = snap and snap.kind or nil, expecting = expect and expect.kind or nil }
end
