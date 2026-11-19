-- Shared synthetic native boundary for proof and supervised integration tests.
return function(Same)
local function Setup()
    local c = MakeClient("Proof", { "!!!TwichUI" })
    local t = { now = 0, combat = false, available = true, valid = true, loads = 0, mutations = 0, faults = {}, frames = 0 }
    local R = c.TwichUI
    c.print = function() end
    c.Enum.PlayerInteractionType = { Auctioneer = 21 }
    c.InCombatLockdown = function() return t.combat end
    c.GetTime = function() return t.now end
    c.C_PlayerInteractionManager = {
        IsInteractingWithNpcOfType = function(k) Same(k, 21); return t.available end,
        IsValidNPCInteraction = function(k) Same(k, 21); return t.valid end,
    }
    c.C_AddOns.LoadAddOn = function() t.loads = t.loads + 1; error("Host must never load an addon") end
    R.Fault = function(source, err) t.faults[#t.faults + 1] = { source, err } end
    c.C_AuctionHouse = setmetatable({}, { __index = function(_, k) return function() error("unexpected auction API: " .. k) end end })
    local function Frame(parent)
        local f = { parent = parent, points = {}, scale = 0.8, shown = true, children = {}, hooks = {}, scripts = {} }
        if parent then parent.children[#parent.children + 1] = f end
        function f:GetParent() return self.parent end
        function f:GetChildren() return unpack(self.children) end
        function f:HasFocus() return self.focus or false end
        function f:GetScale() return self.scale end
        function f:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
        function f:IsProtected() return self.protected or false end
        function f:IsClampedToScreen() return self.clamped or false end
        function f:GetNumPoints() return #self.points end
        function f:GetPoint(i) return unpack(self.points[i], 1, 5) end
        function f:ClearAllPoints()
            Same(t.combat, false, "no anchor writes in combat")
            t.mutations = t.mutations + 1
            if self == t.f then t.nativeMutations = (t.nativeMutations or 0) + 1 end
            self.points = {}
            if self.failClear then self.failClear = nil; error("injected clear failure") end
        end
        function f:SetPoint(...)
            Same(t.combat, false, "no anchor writes in combat")
            t.mutations = t.mutations + 1
            if self == t.f then t.nativeMutations = (t.nativeMutations or 0) + 1 end
            if self.failPoint then self.failPoint = nil; error("injected anchor failure") end
            self.points[#self.points + 1] = { ... }
        end
        function f:GetLeft()
            if self == c.UIParent then return 0 end
            if self.badGeometry then return nil end
            local p = self.points[1]
            return p and p[3] == "TOPRIGHT" and (c.UIParent:GetRight() * c.UIParent:GetEffectiveScale() / self:GetEffectiveScale() + p[4]) or 40
        end
        function f:GetRight() return self == c.UIParent and 1920 or self:GetLeft() and self:GetLeft()+800 end
        function f:GetBottom() return self == c.UIParent and 0 or 80 end
        function f:GetTop() return self == c.UIParent and 1080 or 580 end
        function f:GetAlpha() return self.alpha or 1 end
        function f:GetFrameStrata() return self.strata or "HIGH" end
        function f:IsShown() return self.shown end
        function f:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
        function f:Show() self.shown = true; self.shows = (self.shows or 0) + 1 end
        function f:Hide()
            local shown = self.shown
            self.shown = false
            if self == t.f then t.available = false end -- native OnHide closes the session
            if shown then for _, fn in ipairs(self.hooks.OnHide or {}) do fn(self) end end
        end
        function f:HookScript(k, fn)
            self.hooks[k] = self.hooks[k] or {}; table.insert(self.hooks[k], fn)
        end
        function f:SetScript(k, fn) self.scripts[k] = fn end
        function f:Click() self.scripts.OnClick(self) end
        function f:SetSize() end
        function f:SetClampedToScreen(v) self.clamped = v end
        function f:SetFrameStrata() end
        function f:SetText(v) self.text = v end
        function f:GetDisplayMode() return self.mode or c.AuctionHouseFrameDisplayMode.Buy end
        return f
    end
    c.UIParent = Frame(); c.UIParent.scale = 0.75
    c.AuctionHouseFrameDisplayMode = { Buy = {} }
    c.AuctionHouseFrame = Frame(c.UIParent)
    local f = c.AuctionHouseFrame
    f.points = { { "TOPLEFT", c.UIParent, "TOPLEFT", 27, -18 }, { "BOTTOMRIGHT", c.UIParent, "BOTTOMRIGHT", -300, 200 } }
    c.CreateFrame = function() t.frames = t.frames + 1; return Frame(c.UIParent) end
    t.timers = {}
    c.C_Timer.NewTimer = function(delay, fn)
        local timer = { fn = fn, delay = delay }
        function timer:Cancel() self.cancelled = true end
        t.timers[#t.timers + 1] = timer
        return timer
    end
    c.C_Timer.NewTicker = function(_, fn)
        local timer = { fn = fn }; function timer:Cancel() self.cancelled = true end
        t.timer = timer; return timer
    end
    R.AuctionWindow = { LifecycleBusy = function() return t.posting end }
    R.AuctionScan = { Busy = function() return t.searching end }
    local function Load()
        local fn = assert(loadfile(ROOT .. "auction/Host.lua")); setfenv(fn, c); fn()
        t.H = R.AuctionHost
    end
    Load()
    t.c, t.R, t.f, t.Load, t.Frame = c, R, f, Load, Frame
    function t.Flush()
        local timers = t.timers; t.timers = {}
        for _, timer in ipairs(timers) do if not timer.cancelled then t.now = t.now + timer.delay; timer.fn() end end
    end
    function t.Tick() if t.timer and not t.timer.cancelled then t.timer.fn() end end
    function t.Open() t.available = true; f:Show(); c.FireEvent("AUCTION_HOUSE_SHOW") end
    function t.Restored()
        Same(f:GetNumPoints(), 2, "all anchors restored")
        Same(select(4, f:GetPoint(1)), 27)
        Same(select(4, f:GetPoint(2)), -300)
        Same(t.H.Snapshot().leased, false)
        Same(t.H.Snapshot().watching, false)
        Same(f.scale, 0.8)
        Same(f.parent, c.UIParent)
    end
    return t
end
return Setup
end
