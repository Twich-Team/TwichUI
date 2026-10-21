-- TwichUI: ammunition warning, the controller and the frame
-- Reads what is equipped and carried, asks State.lua what is wrong, and shows one line of text near the centre of the
-- screen when something is. It never equips, moves, buys, destroys or uses anything, and says nothing in chat.
--
-- Game APIs and events (each one is used by Blizzard's own UI in the Forever source, or documented there):
--   UnitUsesAmmo("player") (Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua: it shows the ammo slot);
--   GetInventoryItemID / GetInventoryItemCount / GetInventoryItemTexture with INVSLOT_AMMO (0) and INVSLOT_RANGED (18)
--   (Blizzard_FrameXMLBase/Constants.lua; PaperDollFrame.lua prints the ammo slot's count with GetInventoryItemCount);
--   C_Item.GetItemInfoInstant, C_Item.GetItemIconByID; C_Container.GetContainerNumSlots / GetContainerItemID;
--   events PLAYER_ENTERING_WORLD, PLAYER_EQUIPMENT_CHANGED (slot, hasCurrent), BAG_UPDATE_DELAYED,
--   UNIT_INVENTORY_CHANGED (unit), PLAYER_REGEN_DISABLED / PLAYER_REGEN_ENABLED.
-- None of this has been seen in the game; docs/ammo-warning.md lists what to check.
--
-- Lifecycle:
--   * Off (the default): no frame, no timer, no event.
--   * On, but the equipped ranged weapon takes no ammunition (or there is none): PLAYER_ENTERING_WORLD and
--     PLAYER_EQUIPMENT_CHANGED for the ranged slot only (everything else is dropped before any work). That is all
--     it takes to notice a weapon that does need ammunition being equipped, whatever the class. No bag is read.
--   * On, and the client says the ranged weapon takes ammunition (UnitUsesAmmo): also the ammo slot,
--     BAG_UPDATE_DELAYED and UNIT_INVENTORY_CHANGED for the player, plus the two combat events while "Only in
--     combat" is chosen. They only note that a look is due. Swapping back to a weapon without ammunition drops them.
--   * A look is one short timer however many events arrive (COALESCE seconds), so a burst of bag updates or an
--     equipment swap is judged once, after it has settled. No OnUpdate, no polling.
--   * A look reads at most six values from the character, and the bags only when nothing is selected (to tell
--     "carrying some" from "none"); it stops at the first compatible stack.
--   * unknown (information not there yet, as just after login): nothing is concluded. What is shown stays as it is
--     and the look is repeated a few times, then it gives up and shows nothing. Missing data is never a warning.
--   * Switching it off, a profile change or the settings preview ending puts everything away at once.
--
-- Sound (off by default): once, when a problem begins while it can be seen, never when a look is the first after
-- login, a refresh or switching on, never more than every SOUND_GAP seconds, never in the preview.
-- Two presentations of the one state (ui.ammo.style): "standard", a line of text on a plain frame that appears and
-- disappears, and "rpg", a separate frame drawn in the zone arrival card's type with a bronze rule, which settles in
-- once when a warning begins and fades once when it ends. Only one is ever visible. The rpg frame borrows the arrival
-- card's fonts, rule and palette (modules/Arrival.lua) and its Reduced motion switch, and nothing else: no Notify queue,
-- no hold or dismissal timer, no zone event, no sound. It stays up for as long as the problem does.

local R = TwichUI
local AM = R.Ammo
local AI = R.AmmoItems
local AS = R.AmmoState
local MS = R.MenuStyle
local W = {}
R.AmmoWarning = W

local COALESCE = 0.15     -- seconds an event waits so a burst is one look
local RETRY = 1.0         -- seconds before looking again when the data was not there
local MAX_RETRIES = 3
local SOUND_GAP = 5       -- seconds between two alert sounds
local PAD_PANEL, PAD_BARE = 10, 2
local RPG_PAD, RPG_RISE = 8, 8       -- the rpg card's margin; pixels it settles upward (0 with Reduced motion)
local RPG_FADE_IN, RPG_FADE_OUT = 0.6, 0.35
local WHITE = [[Interface\Buttons\WHITE8x8]]
local FLAGS = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE", shadow = "" }

local AMMO_SLOT = INVSLOT_AMMO or 0
local RANGED_SLOT = INVSLOT_RANGED or 18

local frame, handle          -- the standard warning and its move handle, made when first shown
local rpg = { drawn = {} }   -- the RPG Notification frame, its parts and animations, made when first shown in that style
local evf                    -- the event frame, made when first needed
local registered = {}        -- [event] = true
local token = 0              -- bumped by Teardown: timers from an earlier life do nothing
local soonQueued, retryQueued = false, false
local worldSeen = false
local monitoring, running = false, false   -- monitoring: the weapon takes ammunition, so bags and ammo slot matter
local inCombat = false
local retries = 0
local quiet = true           -- the next definite look makes no sound
local shown, shownIcon       -- the problem on screen now ("noAmmo" ...) and the item its icon comes from
local current = "inactive"   -- the last definite state
local lastAmmo               -- the ammunition last seen selected (for the icon once it is gone)
local layoutRev, drawn = 1, {}
local preview = { active = false, position = false, index = 1 }
local stats = { looks = 0, sounds = 0, soundsHeld = 0, soundsRefused = 0 }
local lastSound

local input, result = {}, {}

---------------------------------------------------------------------------
-- Reading the game
---------------------------------------------------------------------------
local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Number(v)
    v = Plain(v)
    if type(v) == "number" and v == v then return v end
    return nil
end

local function InWorld() return worldSeen or (R.Life ~= nil and R.Life.InWorld()) end

local function SlotItem(slot)
    if not GetInventoryItemID then return nil end
    return Number(GetInventoryItemID("player", slot))
end

local function LastBag() return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 end

-- Whether the carried bags (the backpack and the equipped bags, quivers and pouches included; never the bank, mail
-- or the auction house) hold ammunition the weapon can use, and the first such item. true / false / nil (unreadable).
local function Carries(needs)
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID) then return nil end
    for bag = 0, LastBag() do
        local slots = Number(C_Container.GetContainerNumSlots(bag))
        if slots then
            for slot = 1, slots do
                local id = Number(C_Container.GetContainerItemID(bag, slot))
                if id then
                    local kind = AI.Kind(id)
                    if (kind == "arrow" or kind == "bullet") and (needs == nil or kind == needs) then return true, id end
                end
            end
        end
    end
    return false
end

local function Read()
    local i = input
    local uses
    if UnitUsesAmmo then uses = Plain(UnitUsesAmmo("player")) end
    if type(uses) ~= "boolean" then uses = nil end
    i.usesAmmo = uses

    local rangedId = SlotItem(RANGED_SLOT)
    i.hasRanged = rangedId ~= nil
    i.needs = nil
    if rangedId and C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(rangedId)
        i.needs = AS.NeedsFor(Plain(classID), Plain(subClassID))
    end

    local ammoId = SlotItem(AMMO_SLOT)
    i.equippedId, i.equippedKind, i.equippedCount = ammoId, nil, nil
    if ammoId then
        i.equippedKind = AI.Kind(ammoId)
        if GetInventoryItemCount then i.equippedCount = Number(GetInventoryItemCount("player", AMMO_SLOT)) end
        lastAmmo = ammoId
    end
    i.carries = Carries
end

local function IconFor(itemID)
    if not itemID then return nil end
    local texture
    if C_Item and C_Item.GetItemIconByID then texture = Plain(C_Item.GetItemIconByID(itemID)) end
    if texture == nil and C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
        texture = Plain(icon)
    end
    return texture
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
local function PlaceFrame(f)
    if not f then return end
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local px, py = AM.Position()
    local x, y = AM.ClampPosition(px, py, sw, sh)
    local scale = AM.Get("scale") / 100
    local ox, oy = AM.FromOffset(x, y, scale)
    f:SetScale(scale)
    f:SetAlpha(AM.Get("opacity") / 100)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
end

local function Place()
    PlaceFrame(frame)
    PlaceFrame(rpg.root)
end

-- The drag handle over a warning frame (either style): it takes the mouse only while positioning.
local function MakeHandle(f)
    local h = CreateFrame("Frame", nil, f, "BackdropTemplate")
    h:SetFrameStrata("DIALOG")
    h:SetAllPoints(f)
    h:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    h:SetBackdropColor(0.18, 0.33, 0.33, 0.45)
    h:SetBackdropBorderColor(0.58, 0.78, 0.76, 1)
    h:RegisterForDrag("LeftButton")
    h:EnableMouse(false)
    h:Hide()
    local label = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("BOTTOM", h, "TOP", 0, 3)
    label:SetText("Ammunition warning: drag to move, right-click to finish")
    h:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        f:StartMoving()
    end)
    h:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local cx, cy = f:GetCenter()
        local px, py = UIParent:GetCenter()
        if cx and px then
            local x, y = AM.ToOffset(cx, cy, f:GetEffectiveScale(), px, py, UIParent:GetEffectiveScale())
            if x then AM.SetPosition(math.floor(x + 0.5), math.floor(y + 0.5)) end
        end
        Place()   -- StartMoving re-anchored the frame: put it back on the saved place
    end)
    h:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then W.PositionEnd() end
    end)
    return h
end

local function SetHandle(h, on)
    if not h then return end
    h:SetShown(on)
    h:EnableMouse(on)
end

local function Build()
    if frame then return end
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetFrameStrata("HIGH")
    f:SetSize(10, 10)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(false)      -- click-through: only the move handle, in positioning mode, takes the mouse
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end   -- TwichUI keeps the place, not the game's layout cache
    f:Hide()
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.text = f:CreateFontString(nil, "OVERLAY")

    frame, handle = f, MakeHandle(f)
end

-- Draws the text, icon, font and look. Only when something it depends on changed (Present decides).
local function Layout(text, texture)
    local size = AM.Get("fontSize")
    local fallback = rawget(_G, "STANDARD_TEXT_FONT") or [[Fonts\FRIZQT__.TTF]]
    local file = MS.Fonts.Resolve(AM.Get("font"), fallback)
    local outline = AM.Get("fontOutline")
    local flags = FLAGS[outline] or ""
    local fs = frame.text
    if fs:SetFont(file, size, flags) == false then fs:SetFont(fallback, size, flags) end
    if outline == "shadow" then
        fs:SetShadowColor(0, 0, 0, 0.9)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
    local r, g, b = MS.ParseColor(AM.Get("textColor"))
    fs:SetTextColor(r, g, b)
    fs:SetText(text)

    -- the scale first: a border is drawn for the frame's scale as it is then (EllesmereUI's textured ones read it)
    PlaceFrame(frame)
    local edge = AM.Look.ApplyInset(frame)
    local look = AM.Look
    local panel = look.Get("bgTexture") ~= "none" or (look.Get("borderTexture") ~= "none" and look.Get("borderSize") > 0)
    local pad = (edge or 0) + (panel and PAD_PANEL or PAD_BARE)

    local iconSize = 0
    local showIcon = AM.Get("icon") and texture ~= nil
    frame.icon:SetShown(showIcon)
    if showIcon then
        iconSize = math.ceil(size * 1.15)
        frame.icon:SetTexture(texture)
        frame.icon:SetSize(iconSize, iconSize)
    end
    local gap = showIcon and math.max(6, math.floor(size / 4)) or 0
    local textW = fs:GetStringWidth() or 0
    local textH = fs:GetStringHeight() or size
    local h = math.max(textH, iconSize)
    frame.icon:ClearAllPoints()
    fs:ClearAllPoints()
    if showIcon then
        frame.icon:SetPoint("LEFT", frame, "LEFT", pad, 0)
        fs:SetPoint("LEFT", frame.icon, "RIGHT", gap, 0)
    else
        fs:SetPoint("CENTER", frame, "CENTER", 0, 0)
    end
    frame:SetSize(math.max(1, pad * 2 + iconSize + gap + textW), math.max(1, pad * 2 + h))
end

local function Present(text, texture)
    Build()
    if drawn.rev ~= layoutRev or drawn.text ~= text or drawn.texture ~= texture then
        Layout(text, texture)
        drawn.rev, drawn.text, drawn.texture = layoutRev, text, texture
    end
    frame:Show()
end

local function SampleIcon()
    local id = lastAmmo
    if not id then
        local first = AI.List()[1]
        id = first and first.id or 2512
    end
    return IconFor(id)
end

---------------------------------------------------------------------------
-- The RPG Notification style: its own frame, never the zone arrival card's (see the header)
---------------------------------------------------------------------------
local SyncEvents   -- (below: Render, and a fade that ends, ask it to follow the frames being shown)

local function Palette()
    local style = R.ChronicleStyle and R.ChronicleStyle.color
    return style or {
        text = { 0.93, 0.88, 0.76 }, textDim = { 0.78, 0.74, 0.66 }, stone = { 0.62, 0.58, 0.51 },
        bronze = { 0.55, 0.43, 0.22 }, bronzeLo = { 0.30, 0.23, 0.13 }, gold = { 0.79, 0.64, 0.29 },
    }
end

local function RpgReduced() return R:Enabled("arrivalReducedMotion") end

local function RpgBuild()
    if rpg.root then return end
    local root = CreateFrame("Frame", nil, UIParent)
    root:SetFrameStrata("HIGH")
    root:SetSize(10, 10)
    root:SetClampedToScreen(true)
    root:SetMovable(true)
    root:EnableMouse(false)   -- click-through, as the standard frame is
    if root.SetDontSavePosition then root:SetDontSavePosition(true) end
    root:Hide()
    -- the root carries place, scale and the opacity setting; the card inside is what the animations fade and move
    local card = CreateFrame("Frame", nil, root)
    card:SetAllPoints(root)
    card:EnableMouse(false)
    rpg.root, rpg.card = root, card
    rpg.heading = card:CreateFontString(nil, "OVERLAY")
    rpg.primary = card:CreateFontString(nil, "OVERLAY")
    rpg.detail = card:CreateFontString(nil, "OVERLAY")
    local Ar = R.Arrival
    rpg.rule = Ar and Ar.Rule and Ar.Rule(card, Palette()) or nil

    local enter = card:CreateAnimationGroup()
    enter:SetToFinalAlpha(true)
    -- lower the card at once, then let it rise back to its place as it fades in: the two moves add to nothing
    rpg.drop = enter:CreateAnimation("Translation")
    rpg.drop:SetDuration(0)
    rpg.drop:SetOrder(1)
    rpg.rise = enter:CreateAnimation("Translation")
    rpg.rise:SetSmoothing("OUT")
    rpg.rise:SetDuration(RPG_FADE_IN)
    rpg.rise:SetOrder(1)
    local fadeIn = enter:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetSmoothing("OUT")
    fadeIn:SetDuration(RPG_FADE_IN)
    fadeIn:SetOrder(1)
    rpg.enter = enter

    local leave = card:CreateAnimationGroup()
    leave:SetToFinalAlpha(true)
    local fadeOut = leave:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetSmoothing("IN")
    fadeOut:SetDuration(RPG_FADE_OUT)
    leave:SetScript("OnFinished", function()
        if not rpg.fading then return end
        rpg.fading = false
        rpg.card:SetAlpha(1)
        rpg.root:Hide()
        SyncEvents()
    end)
    rpg.leave = leave
    rpg.handle = MakeHandle(root)
end

local function RpgFont(fs, file, size, fallbackObject, flags)
    local Ar = R.Arrival
    if Ar and Ar.SetFont then
        Ar.SetFont(fs, file, size, fallbackObject, flags)
    elseif fs:SetFont(file, size, flags) == false then
        fs:SetFont(rawget(_G, "STANDARD_TEXT_FONT") or [[Fonts\FRIZQT__.TTF]], size, flags)
    end
end

-- Sizes, fonts, text and shape for a state. The main line takes the Text size setting; the heading and the supporting
-- line are drawn smaller (about half and 0.6) so the hierarchy stays when the size changes.
local function RpgLayout(state, isPreview)
    local K, Ar = Palette(), R.Arrival
    local size = AM.Get("fontSize")
    local headSize, detailSize = math.max(11, math.floor(size * 0.5 + 0.5)), math.max(12, math.floor(size * 0.6 + 0.5))
    local flags = FLAGS[AM.Get("fontOutline")] or ""
    local titleFont = Ar and Ar.FONT_TITLE or rawget(_G, "STANDARD_TEXT_FONT") or [[Fonts\FRIZQT__.TTF]]
    local lineFont = Ar and Ar.FONT_LINE or titleFont
    local mainFile = MS.Fonts.Resolve(AM.Get("font"), titleFont)   -- "Game font" means the arrival card's own face

    local function Dress(fs, file, px, object, color, alpha)
        RpgFont(fs, file, px, object, flags)
        if AM.Get("fontOutline") == "shadow" then
            fs:SetShadowColor(0, 0, 0, 0.9)
            fs:SetShadowOffset(1, -1)
        else
            fs:SetShadowOffset(0, 0)
        end
        fs:SetTextColor(color[1], color[2], color[3], alpha or 1)
    end
    local r, g, b = MS.ParseColor(AM.Get("textColor"))
    Dress(rpg.heading, lineFont, headSize, "SubZoneTextFont", K.stone)
    Dress(rpg.primary, mainFile, size, "ZoneTextFont", { r, g, b })
    Dress(rpg.detail, lineFont, detailSize, "SubZoneTextFont", K.stone)
    rpg.heading:SetText(isPreview and "Ammunition (preview)" or "Ammunition")
    rpg.primary:SetText(AS.MESSAGES[state])
    local detail = AS.DETAIL and AS.DETAIL[state]
    rpg.detail:SetText(detail or "")
    rpg.detail:SetShown(detail ~= nil)

    local hw, hh = rpg.heading:GetStringWidth() or 0, rpg.heading:GetStringHeight() or headSize
    local pw, ph = rpg.primary:GetStringWidth() or 0, rpg.primary:GetStringHeight() or size
    local dw, dh = 0, 0
    if detail then dw, dh = rpg.detail:GetStringWidth() or 0, rpg.detail:GetStringHeight() or detailSize end
    local ruleWidth = math.max(120, math.floor(pw * 0.6))
    local pad, gap = RPG_PAD, 6
    rpg.heading:ClearAllPoints()
    rpg.heading:SetPoint("TOP", rpg.card, "TOP", 0, -pad)
    local above = rpg.heading
    local height = pad + hh
    if rpg.rule then
        rpg.rule:SetWidth(ruleWidth)
        rpg.rule:ClearAllPoints()
        rpg.rule:SetPoint("TOP", above, "BOTTOM", 0, -5)
        above, height = rpg.rule, height + 5 + 2
    end
    rpg.primary:ClearAllPoints()
    rpg.primary:SetPoint("TOP", above, "BOTTOM", 0, -gap)
    height = height + gap + ph
    rpg.detail:ClearAllPoints()
    if detail then
        rpg.detail:SetPoint("TOP", rpg.primary, "BOTTOM", 0, -4)
        height = height + 4 + dh
    end
    rpg.root:SetSize(math.max(1, math.max(hw, pw, dw, ruleWidth) + pad * 2), math.max(1, height + pad))
    PlaceFrame(rpg.root)
end

local function RpgHideNow()
    if not rpg.root then return end
    rpg.live, rpg.fading = false, false
    rpg.enter:Stop()
    rpg.leave:Stop()
    rpg.card:SetAlpha(1)      -- a stopped fade must not leave the card transparent for the next use
    rpg.root:Hide()
    SetHandle(rpg.handle, false)
end

-- The warning ended: fade the card out once (a Stop first, so nothing is left half-way). Not live any more at once.
local function RpgEnd()
    if not (rpg.root and rpg.live) then return end
    rpg.live = false
    SetHandle(rpg.handle, false)
    rpg.enter:Stop()
    rpg.fading = true
    rpg.card:SetAlpha(1)
    rpg.leave:Play()
end

local function RpgShow(state, isPreview, positioning)
    RpgBuild()
    local d = rpg.drawn
    if d.rev ~= layoutRev or d.state ~= state or d.preview ~= isPreview then
        RpgLayout(state, isPreview)
        d.rev, d.state, d.preview = layoutRev, state, isPreview
    end
    if not rpg.live then
        local wasFading = rpg.fading
        rpg.leave:Stop()
        rpg.fading = false
        rpg.live = true
        rpg.root:Show()
        if wasFading then
            rpg.card:SetAlpha(1)   -- it never left: no second entrance
        else
            local rise = RpgReduced() and 0 or RPG_RISE
            rpg.drop:SetOffset(0, -rise)
            rpg.rise:SetOffset(0, rise)
            rpg.card:SetAlpha(0)
            rpg.enter:Play()
        end
    end
    SetHandle(rpg.handle, positioning)
end

local function StandardHide()
    if not frame then return end
    frame:Hide()
    SetHandle(handle, false)
end

-- What is on screen now: the sample while previewing or positioning, else the real problem, else nothing. The chosen
-- style shows it and the other is put away at once, so exactly one presentation is ever visible.
local function Render()
    local state = preview.active and AS.ORDER[preview.index] or shown
    if AM.Get("style") == "rpg" then
        StandardHide()
        if state then RpgShow(state, preview.active, preview.active and preview.position) else RpgEnd() end
    else
        RpgHideNow()
        if state and preview.active then
            Present(AS.MESSAGES[state], SampleIcon())
            SetHandle(handle, preview.position)
        elseif state then
            Present(AS.MESSAGES[state], IconFor(shownIcon or lastAmmo))
            SetHandle(handle, false)
        else
            StandardHide()
        end
    end
    SyncEvents()   -- the scale events are wanted only while a frame is on screen
end
W.Render = Render

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function OnEvent(_, event, arg)
    if event == "PLAYER_ENTERING_WORLD" then
        worldSeen = true
        W.Refresh()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        if preview.active then W.PreviewStop() end   -- a preview or a move never carries into a fight
        if running and AM.Get("show") == "combat" then W.Note() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        if running and AM.Get("show") == "combat" then W.Note() end
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        -- a border is drawn in whole pixels for the scale the frame has now: draw the look again
        layoutRev = layoutRev + 1
        if (frame and frame:IsShown()) or (rpg.live) then W.Render() end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- other slots are not this feature's business; the ammo slot only matters while the weapon takes ammunition
        if arg == RANGED_SLOT or (arg == AMMO_SLOT and monitoring) then W.Note() end
    else
        W.Note()   -- BAG_UPDATE_DELAYED, UNIT_INVENTORY_CHANGED (the client delivers only the player's)
    end
end

local UNIT_EVENTS = { UNIT_INVENTORY_CHANGED = true }

-- Registers exactly the events wanted now and drops the rest.
function SyncEvents()
    local want = {}
    if R:Enabled("ammoWarning") then
        want.PLAYER_ENTERING_WORLD = true
        if InWorld() then want.PLAYER_EQUIPMENT_CHANGED = true end   -- how a weapon that takes ammunition is noticed
        if monitoring and InWorld() then
            want.BAG_UPDATE_DELAYED, want.UNIT_INVENTORY_CHANGED = true, true
            if AM.Get("show") == "combat" then want.PLAYER_REGEN_ENABLED = true end
        end
        if preview.active or (monitoring and InWorld() and AM.Get("show") == "combat") then
            want.PLAYER_REGEN_DISABLED = true
        end
    end
    if ((frame and frame:IsShown()) or (rpg.root and rpg.root:IsShown())) and R:Enabled("ammoWarning") then
        want.UI_SCALE_CHANGED, want.DISPLAY_SIZE_CHANGED = true, true
    end
    if not evf then
        if next(want) == nil then return end
        evf = CreateFrame("Frame")
        evf:SetScript("OnEvent", OnEvent)
    end
    for event in pairs(registered) do
        if not want[event] then
            evf:UnregisterEvent(event)
            registered[event] = nil
        end
    end
    for event in pairs(want) do
        if not registered[event] then
            if UNIT_EVENTS[event] and evf.RegisterUnitEvent then evf:RegisterUnitEvent(event, "player") else evf:RegisterEvent(event) end
            registered[event] = true
        end
    end
end

---------------------------------------------------------------------------
-- Looking
---------------------------------------------------------------------------
local function PlaySound()
    if not PlaySoundFile then return false end
    local path = R:ResolveSound(AM.Get("soundName")) or R:ResolveSound(AM.DEFAULTS.soundName)
    if not path then return false end
    local ok = PlaySoundFile(path, AM.Get("soundChannel"))
    return ok and true or false
end

local function MaybeSound()
    if not AM.Get("sound") then return end
    local now = GetTime()
    if lastSound and now >= lastSound and now - lastSound < SOUND_GAP then
        stats.soundsHeld = stats.soundsHeld + 1
        return
    end
    lastSound = now
    if PlaySound() then stats.sounds = stats.sounds + 1 else stats.soundsRefused = stats.soundsRefused + 1 end
end

local function Look()
    if not running then return end
    stats.looks = stats.looks + 1
    Read()
    AS.Evaluate(input, result)
    local state = result.state
    local watch = input.usesAmmo ~= false   -- unknown counts: bags are watched until the client has said
    if state == "unknown" then
        if retries < MAX_RETRIES then
            retries = retries + 1
            if not retryQueued then
                retryQueued = true
                local mine = token
                C_Timer.After(RETRY, function()
                    if mine ~= token then return end
                    retryQueued = false
                    Look()
                end)
            end
            return   -- keep what is shown; nothing is concluded from missing data
        end
        state = "inactive"   -- it never came: show nothing
    else
        retries = 0
    end

    if watch ~= monitoring then
        monitoring = watch
        SyncEvents()
    end
    local before = shown
    local began = AS.IsProblem(state) and not AS.IsProblem(current)
    current = state
    if AS.Visible(state, AM.Get("show"), inCombat) then
        shown, shownIcon = state, result.iconItem
    else
        shown, shownIcon = nil, nil
    end
    if shown ~= before or (shown and shownIcon ~= drawn.item) then
        drawn.item = shownIcon
        Render()
    end
    if began and shown and not quiet then MaybeSound() end
    quiet = false
end

-- Something changed that may matter: one look soon, however many events come first.
function W.Note()
    if not running or soonQueued then return end
    soonQueued = true
    local mine = token
    C_Timer.After(COALESCE, function()
        if mine ~= token then return end
        soonQueued = false
        retries = 0
        Look()
    end)
end

---------------------------------------------------------------------------
-- Refresh: everything, from the top. Safe to call at any time.
---------------------------------------------------------------------------
local function Teardown()
    token = token + 1
    soonQueued, retryQueued = false, false
    running, monitoring = false, false
    preview.active, preview.position = false, false
    shown, shownIcon, current, lastAmmo = nil, nil, "inactive", nil
    drawn.item = nil
    StandardHide()
    RpgHideNow()
    SyncEvents()
end

function W.Refresh()
    if not R:Enabled("ammoWarning") then
        if evf or running or frame or rpg.root then Teardown() end
        return
    end
    SyncEvents()
    if InWorld() then
        running = true
        inCombat = Plain(UnitAffectingCombat and UnitAffectingCombat("player")) == true
        retries, quiet = 0, true
        Look()
    else
        running, monitoring = false, false
        shown, shownIcon, current = nil, nil, "inactive"
        SyncEvents()
        if frame or rpg.root then Render() end
    end
    -- a setting changed under a warning that is showing (or a preview): draw it again for the new look
    if (frame or rpg.root) and (shown or preview.active) then Render() end
end
AM.Refresh = W.Refresh

---------------------------------------------------------------------------
-- Preview, moving and the sound test (settings)
---------------------------------------------------------------------------
function W.PreviewActive() return preview.active end
function W.PositioningActive() return preview.position end

-- Shows a sample of the warning. Not in combat; only while the feature is on. Nothing real is changed or remembered.
function W.PreviewStart()
    if not R:Enabled("ammoWarning") then return false, "off" end
    if InCombatLockdown() then return false, "combat" end
    if not preview.active then
        preview.active, preview.index = true, 1
        SyncEvents()
        Render()
    end
    return true
end

function W.PreviewStop()
    if not preview.active then return end
    preview.active, preview.position = false, false
    SyncEvents()
    if frame or rpg.root then Render() end
end

-- The next of the three messages, so each can be judged.
function W.PreviewNext()
    if not preview.active then return false end
    preview.index = preview.index % #AS.ORDER + 1
    Render()
    return true
end

function W.PreviewMessage() return preview.active and AS.MESSAGES[AS.ORDER[preview.index]] or nil end

-- Unlocks the warning: the sample with a handle to drag. Not in combat.
function W.PositionStart()
    local ok, why = W.PreviewStart()
    if not ok then return false, why end
    preview.position = true
    Render()
    return true
end

function W.PositionEnd()
    if not preview.position then return end
    preview.position = false
    Render()
end

function W.ResetPosition() AM.SetPosition(nil, nil) end

-- Plays the chosen sound once, for the settings button. Never part of the preview.
function W.TestSound() return PlaySound() end

---------------------------------------------------------------------------
-- Status, for settings, /tui diagnostics and the tests: plain values
---------------------------------------------------------------------------
function W.Snapshot()
    local events = 0
    for _ in pairs(registered) do events = events + 1 end
    return { enabled = R:Enabled("ammoWarning"), monitoring = monitoring, running = running, events = events, state = current,
        shown = shown, style = AM.Get("style"), rpgVisible = rpg.live == true, standardVisible = frame ~= nil and frame:IsShown() and true or false,
        preview = preview.active, positioning = preview.position, retries = retries, looks = stats.looks,
        sounds = stats.sounds, soundsHeld = stats.soundsHeld, soundsRefused = stats.soundsRefused, built = frame ~= nil, rpgBuilt = rpg.root ~= nil }
end

function W.Frame() return frame end
function W.RpgFrame() return rpg.root end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
AM.Subscribe(function()
    layoutRev = layoutRev + 1
    if R:Enabled("ammoWarning") or evf or frame then W.Refresh() end
end)
AM.SubscribeMoved(Place)

R:OnInit(function() W.Refresh() end)
R.Profiles.OnApply("layout", "ammo", function() W.Refresh() end)
R.OnSettingsClosed(function()
    -- the sample goes away with the settings window; moving (an explicit, visible mode) is left to its own end
    if preview.active and not preview.position then W.PreviewStop() end
end)
