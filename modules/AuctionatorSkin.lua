-- TwichUI: Auctionator skin
-- Hands Auctionator's auction house frames to EllesmereUI's skinning API
-- (EllesmereUI.RegisterSkin). EllesmereUI does all the painting and keeps it
-- in sync with theme/accent changes; this file only finds the frames.
--
-- Frames are found by walking Auctionator's tab frames and recognising widget
-- types (buttons, edit boxes, scroll bars, insets...) rather than by hard-coded
-- names, so most Auctionator updates keep working. Everything is idempotent:
-- re-running a pass on already-skinned frames is nearly free.
--
-- Toggles: /twichui > "Skin Auctionator", and EllesmereUI's own
-- Blizzard Window Skins > Third-Party Addons > TwichUI.

local R = TwichUI
local ADDON = R.ADDON
local ModuleOn   -- defined below

local S                     -- EllesmereUI skin facade, set when EUI dispatches us
local hookedTabFrames = {}  -- tab content frames we've hooked OnShow on
local hookedLists = {}      -- results lists we re-run header skinning on

local diag = { dispatched = false, passes = 0, counts = {}, seen = {}, errors = {}, lastTrigger = "none" }

-- Every primitive call goes through here: counts what was skinned and keeps
-- the first error per primitive instead of aborting the whole pass.
local function Call(kind, frame, ...)
    local fn = S and S[kind]
    if not fn then
        diag.errors[kind] = diag.errors[kind] or "primitive missing in this EllesmereUI version"
        return
    end
    local ok, err = pcall(fn, frame, ...)
    if ok then
        local seen = diag.seen[kind]
        if not seen then seen = setmetatable({}, { __mode = "k" }); diag.seen[kind] = seen end
        if frame and not seen[frame] then
            seen[frame] = true
            diag.counts[kind] = (diag.counts[kind] or 0) + 1
        end
    elseif not diag.errors[kind] then
        diag.errors[kind] = tostring(err)
    end
end

local TAB_FRAMES = {        -- Auctionator's own tabs (Source_ModernAH/Tabs/Main.lua)
    "AuctionatorShoppingFrame",
    "AuctionatorSellingFrame",
    "AuctionatorCancellingFrame",
    "AuctionatorConfigFrame",
}

---------------------------------------------------------------------------
-- Widget recognition
---------------------------------------------------------------------------
local function IsType(f, t)
    local ok, res = pcall(f.IsObjectType, f, t)
    return ok and res
end

local function IsMiniTab(b)
    -- Auctionator's sub-tabs (Shopping lists / Selling bag) share this mixin.
    local mix = AuctionatorMiniTabButtonMixin
    return mix and b.OnClick ~= nil and b.OnClick == mix.OnClick
end

local function IsPanelButton(b)
    -- UIPanelButtonTemplate / UIPanelDynamicResizeButtonTemplate 3-slice art.
    return b.Left and b.Middle and b.Right and not b.LeftActive
end

local function IsScrollBar(f)
    return f.Track and (f.Back or f.Forward) and not f.GetText
end

local function IsCloseButton(b, parent)
    return parent and parent.CloseButton == b
end

---------------------------------------------------------------------------
-- Results lists: column headers pool and rebuild, so re-run on show/refresh.
---------------------------------------------------------------------------
local function SkinList(list)
    Call("SortHeaderBar", list)
    if hookedLists[list] then return end
    hookedLists[list] = true
    list:HookScript("OnShow", function(l)
        C_Timer.After(0, function() if S then Call("SortHeaderBar", l) end end)
    end)
    if list.HeaderContainer and list.HeaderContainer.HookScript then
        list.HeaderContainer:HookScript("OnSizeChanged", function()
            if S then Call("SortHeaderBar", list) end
        end)
    end
end

---------------------------------------------------------------------------
-- Tree walk
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Extra clean-up for the parts the generic pass can't recognise:
-- item icons, bag group headers, the refresh button, the trim around scroll
-- bars, and Blizzard's gold label text.
---------------------------------------------------------------------------
local done = setmetatable({}, { __mode = "k" })

local function Fade(region)
    if not region then return end
    if S and S.FadeRegions and region.GetRegions then pcall(S.FadeRegions, region) end
    if region.SetAlpha and region.GetObjectType and region:GetObjectType() == "Texture" then region:SetAlpha(0) end
end

-- Thin quality-coloured outline drawn by us, replacing Blizzard's bevelled frame.
local function Outline(btn)
    local o = {}
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
                           { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
        local t = btn:CreateTexture(nil, "OVERLAY", nil, 6)
        t:SetColorTexture(0, 0, 0, 1)
        t:SetPoint(pts[1], btn.Icon, pts[1])
        t:SetPoint(pts[2], btn.Icon, pts[2])
        if pts[3] then t:SetWidth(pts[3]) else t:SetHeight(pts[4]) end
        o[i] = t
    end
    return o
end

local function UpdateItemBorder(btn)
    local d = done[btn]
    if not (d and d.outline) then return end
    local r, g, b = 0, 0, 0
    if btn.IconBorder and btn.IconBorder:IsShown() and btn.Icon and btn.Icon:IsShown() then
        r, g, b = btn.IconBorder:GetVertexColor()
        -- plain white/grey items get a neutral dark edge instead of white
        if r and r > 0.9 and g > 0.9 and b > 0.9 then r, g, b = 0, 0, 0 end
    end
    for _, t in ipairs(d.outline) do t:SetColorTexture(r or 0, g or 0, b or 0, 1) end
    if btn.IconBorder then btn.IconBorder:SetAlpha(0) end
end

local function SkinItemButton(btn)
    if not S or done[btn] or not btn.Icon then return end
    done[btn] = {}
    Call("SquareIcon", btn.Icon)                 -- crop the baked bevel
    if btn.EmptySlot then btn.EmptySlot:SetAlpha(0) end
    if btn.IconBorder then btn.IconBorder:SetAlpha(0) end
    local pushed = btn.GetPushedTexture and btn:GetPushedTexture()
    if pushed then pushed:SetColorTexture(0, 0, 0, 0.35) end
    local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if hl then hl:SetColorTexture(1, 1, 1, 0.12) end
    done[btn].outline = Outline(btn)
    if btn.SetItemInfo then hooksecurefunc(btn, "SetItemInfo", UpdateItemBorder) end
    UpdateItemBorder(btn)
end

local function SkinGroupTitle(title)
    if not S or not title or done[title] then return end
    done[title] = true
    Call("Button", title)
    local fs = title.Text or (title.GetFontString and title:GetFontString())
    if fs then
        fs:SetTextColor(1, 1, 1)
        Call("Font", fs)
    end
end

local function SkinRefreshButton(btn)
    if not S or done[btn] then return end
    done[btn] = true
    Call("Button", btn, { "Icon" })
    if btn.Icon then
        btn.Icon:SetDesaturated(true)
        btn.Icon:SetVertexColor(1, 1, 1, 0.85)
    end
end

local function CleanScrollBar(sb)
    -- WowTrimScrollBar keeps a framed background that the house scroll bar
    -- skin doesn't touch; fade it (alpha only) so just the thin thumb remains.
    if done[sb] then return end
    done[sb] = true
    if sb.Background then Fade(sb.Background) end
    for _, k in ipairs({ "Back", "Forward" }) do
        local b = sb[k]
        if b then
            Fade(b)
            for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
                local t = b[getter] and b[getter](b)
                if t then t:SetAlpha(0) end
            end
        end
    end
end

-- Blizzard's gold label colour (GameFontNormal) -> white, like the rest of the theme.
local function WhitenGoldText(frame)
    for i = 1, select("#", frame:GetRegions()) do
        local r = select(i, frame:GetRegions())
        if r and r.GetObjectType and r:GetObjectType() == "FontString" and not done[r] then
            local cr, cg, cb = r:GetTextColor()
            if cr and cr > 0.95 and cg > 0.75 and cg < 0.88 and cb < 0.1 then
                done[r] = true
                r:SetTextColor(1, 1, 1)
            end
        end
    end
end

local function IsItemButton(b) return b.Icon and b.IconBorder and b.EmptySlot end
local function IsRefreshButton(b)
    if not b.Icon or b.IconBorder or (b.GetText and b:GetText() and b:GetText() ~= "") then return false end
    local w, h = b:GetSize()
    return w and h and w <= 36 and h <= 36 and math.abs(w - h) < 4
end

-- Bag view items and group headers are created as you browse, so catch them
-- when Auctionator sets them up (hooks on its shared templates).
local mixinsHooked = false
local function HookAuctionatorMixins()
    if mixinsHooked then return end
    if AuctionatorGroupsViewItemMixin and AuctionatorGroupsViewItemMixin.SetItemInfo then
        mixinsHooked = true
        hooksecurefunc(AuctionatorGroupsViewItemMixin, "SetItemInfo", function(self)
            if ModuleOn() and S then SkinItemButton(self) end
        end)
    end
    if AuctionatorGroupsViewGroupMixin and AuctionatorGroupsViewGroupMixin.SetName then
        mixinsHooked = true
        hooksecurefunc(AuctionatorGroupsViewGroupMixin, "SetName", function(self)
            if ModuleOn() and S then SkinGroupTitle(self.GroupTitle) end
        end)
    end
end

local Walk
Walk = function(frame, parent, depth)
    if not frame or depth > 14 then return end
    if frame.IsForbidden and frame:IsForbidden() then return end

    -- Result rows live in ScrollBox targets; they're pooled row buttons, not
    -- widgets, and Auctionator draws their highlight itself. Leave them alone.
    if frame.ScrollTarget and frame.GetDataProvider then return end

    if IsType(frame, "EditBox") then
        Call("EditBox", frame)
        return
    elseif IsType(frame, "CheckButton") then
        Call("Checkbox", frame)
        return
    elseif IsType(frame, "DropdownButton") then
        Call("Dropdown", frame)
        return
    elseif IsType(frame, "Button") then
        if IsItemButton(frame) then
            SkinItemButton(frame)
        elseif parent and parent.GroupTitle == frame then
            SkinGroupTitle(frame)
        elseif IsRefreshButton(frame) then
            SkinRefreshButton(frame)
        elseif IsCloseButton(frame, parent) then
            Call("CloseButton", frame)
        elseif IsMiniTab(frame) then
            Call("Tab", frame)
        elseif IsPanelButton(frame) then
            Call("Button", frame)
            Call("StateButtonLabel", frame)
        end
        return
    end

    if IsScrollBar(frame) then
        Call("ScrollBar", frame)
        CleanScrollBar(frame)
        return
    end

    WhitenGoldText(frame)

    if frame.HeaderContainer then
        SkinList(frame)
    end

    if frame.NineSlice then
        if frame.CloseButton then
            Call("Panel", frame)                -- dialog (ButtonFrameTemplate)
        else
            Call("Inset", frame)                -- inset box behind lists/prices
        end
    end

    for i = 1, select("#", frame:GetChildren()) do
        Walk(select(i, frame:GetChildren()), frame, depth + 1)
    end
end

---------------------------------------------------------------------------
-- Top-level AH tabs added through LibAHTab (Auctionator, and any other
-- addon using the same library, e.g. Journalator/Collectionator).
---------------------------------------------------------------------------
local function LibTabs()
    local lib = LibStub and LibStub("LibAHTab-1-0", true)
    return lib, lib and lib.internalState and lib.internalState.Tabs
end

local function SyncLibTabSelection()
    if not S then return end
    local _, tabs = LibTabs()
    if not tabs then return end
    for _, tab in ipairs(tabs) do
        Call("Tab", tab)
        local shown = tab.frameRef and tab.frameRef:IsShown() or false
        Call("SetTabSelection", tab, shown and true or false)
    end
end

local libHooked = false
local function HookLibTabs()
    if libHooked then return end
    local lib = LibTabs()
    if not lib or type(lib.SetSelected) ~= "function" then return end
    libHooked = true
    hooksecurefunc(lib, "SetSelected", SyncLibTabSelection)
    if AuctionHouseFrame and AuctionHouseFrame.SetDisplayMode then
        -- Picking a Blizzard tab (Buy/Sell/Auctions) deselects ours.
        hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", SyncLibTabSelection)
    end
end

---------------------------------------------------------------------------
-- Passes
---------------------------------------------------------------------------
local function SkinTabFrame(f)
    if not S or not f then return end
    Walk(f, f:GetParent(), 0)
end

local function Stage(name, fn)
    local ok, err = pcall(fn)
    if not ok and not diag.errors[name] then diag.errors[name] = tostring(err) end
end

local function SkinAll(trigger)
    if type(trigger) == "string" then diag.lastTrigger = trigger end
    if not S or not AuctionHouseFrame then return end
    diag.passes = diag.passes + 1
    Stage("lib tabs", function() HookLibTabs(); SyncLibTabSelection() end)
    Stage("templates", HookAuctionatorMixins)
    for _, name in ipairs(TAB_FRAMES) do
        local f = _G[name]
        if f then
            Stage(name, function() SkinTabFrame(f) end)
            if not hookedTabFrames[f] then
                hookedTabFrames[f] = true
                -- Sub-panels (buy dialogs, bag view, config pages) appear
                -- lazily, so sweep again whenever a tab is shown.
                f:HookScript("OnShow", function(self)
                    C_Timer.After(0, function() SkinTabFrame(self) end)
                end)
            end
        end
    end
end

-- Auctionator builds its frames when the auction house first opens, which
-- is after EllesmereUI hands us the facade at login. Sweep on every AH open.
local function Schedule(trigger)
    -- Let Auctionator's own handlers finish building frames first.
    C_Timer.After(0, function() SkinAll(trigger) end)
    C_Timer.After(0.5, function() SkinAll(trigger) end)
end

local ahHooked = false
local function HookAHFrame()
    if ahHooked or not AuctionHouseFrame then return end
    ahHooked = true
    AuctionHouseFrame:HookScript("OnShow", function() Schedule("AuctionHouseFrame:OnShow") end)
end

local watcher = CreateFrame("Frame")
ModuleOn = function() return R:Enabled("auctionatorSkin") end
watcher:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(_, event, arg)
    if not ModuleOn() then return end
    if event == "ADDON_LOADED" then
        if arg == "Blizzard_AuctionHouseUI" then HookAHFrame() end
        -- Hook Auctionator's item/group templates before any are created.
        if arg == "Auctionator" then HookAuctionatorMixins() end
        return
    end
    if Enum and Enum.PlayerInteractionType
        and arg ~= Enum.PlayerInteractionType.Auctioneer then return end
    HookAHFrame()
    Schedule("interaction event")
end)


R:OnSkin(function(facade)
    if not ModuleOn() then return end
    S = facade
    diag.dispatched = true
    SkinAll("login")   -- no-op until the AH has been opened once
end)

---------------------------------------------------------------------------
-- /aeskin        status report (paste this when something looks wrong)
-- /aeskin apply  run a skinning pass right now (with the AH open)
---------------------------------------------------------------------------
local function P(fmt, ...) print(("|cffC9A24ATwichUI (Auctionator skin):|r " .. fmt):format(...)) end
local function Ver(a)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get(a, "Version") or "?"
end

SLASH_TWICHUIAUCTION1 = "/aeskin"
SlashCmdList.TWICHUIAUCTION = function(msg)
    if msg and msg:lower():match("apply") then
        if not S then P("EllesmereUI has not activated this skin (see /aeskin)."); return end
        if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
            P("Open the auction house first."); return
        end
        SkinAll("manual")
        P("pass done.")
        return
    end
    P("EllesmereUI %s, Auctionator %s, TwichUI %s, module %s", Ver("EllesmereUI"), Ver("Auctionator"), Ver(ADDON), ModuleOn() and "on" or "OFF")
    local db = EllesmereUIDB
    P("third-party skins master: %s, this addon: %s",
        (db and db.thirdPartySkinsOff) and "OFF" or "on",
        (db and db.thirdPartySkinAddons and db.thirdPartySkinAddons.TwichUI == false) and "OFF" or "on")
    local child = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EllesmereUIBlizzardSkin")
    P("Blizz UI Enhanced loaded: %s, activated by EllesmereUI: %s", tostring(child), tostring(diag.dispatched))
    P("AH frame: %s, passes: %d, last trigger: %s", AuctionHouseFrame and "yes" or "no", diag.passes, diag.lastTrigger)
    local found = {}
    for _, n in ipairs(TAB_FRAMES) do found[#found + 1] = n:gsub("^Auctionator", "") .. "=" .. (_G[n] and "y" or "n") end
    local _, tabs = LibTabs()
    P("tab frames: %s, AH tabs: %d", table.concat(found, " "), tabs and #tabs or 0)
    local parts = {}
    for k, v in pairs(diag.counts) do parts[#parts + 1] = k .. "=" .. v end
    table.sort(parts)
    P("skinned: %s", #parts > 0 and table.concat(parts, ", ") or "nothing yet")
    for k, e in pairs(diag.errors) do P("|cffff6060error|r in %s: %s", k, e) end
end
