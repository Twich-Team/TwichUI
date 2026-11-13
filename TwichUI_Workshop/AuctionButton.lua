-- TwichUI Workshop: the progress bar, and the Scan prices button on the auction house window
-- The scan is started by the player's click, here or in the Workshop's Opportunities view (or, when automatic updates are on and Auto.lua may, on opening) (the same Session.StartScan, the same
-- Scan.lua state). While a scan runs both show an overall progress bar (Scan.Progress: asking, waiting, then the reading) and the same
-- one-line message; afterwards the auction house window keeps the last message until it closes.
--
-- The button belongs to the auction house window (a child of AuctionHouseFrame, under its lower right corner, clear of the tabs on the
-- left), so it shows and hides with it. It exists once the Workshop has been loaded this session (the Workshop is load on demand: nothing
-- of it is built at login). It is made when Blizzard's auction house UI exists; the one event it waits for is unregistered once it is made.
-- It prices what the Workshop's recipes know, which is what was read while the Workshop window was open (closing that window forgets
-- them: Session.Reset), so with nothing read the scan says to open a profession first instead of starting.

local R = TwichUI
local W = R.Workshop
local S, SC = W.Session, W.Scan
local AB = {}
W.AuctionButton = AB

local BAR_W, BTN_W, H = 280, 120, 24

local L, K
local btn, bar, status, ev
local attached = false
local stale = false      -- the auction house was closed since the last change: its old result isn't shown again on opening

local function Paint(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

---------------------------------------------------------------------------
-- A small progress bar (a recessed track, a filling bar, a word on top)
---------------------------------------------------------------------------
-- bar:Set(fraction 0..1, text) ; bar:Set(nil) clears the fill. Used by the Opportunities view and the auction house button.
function W.NewBar(parent, w, h)
    L = L or R.Look
    K = K or L.pal
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetSize(w, h)
    L.Well(b, 0.9)
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetPoint("TOPLEFT", 2, -2)
    b.fill:SetPoint("BOTTOMLEFT", 2, 2)
    b.fill:SetColorTexture(K.tealLo[1], K.tealLo[2], K.tealLo[3], 1)
    b.edge = b:CreateTexture(nil, "OVERLAY")     -- a thin lit end, so a short fill is still seen
    b.edge:SetPoint("TOPRIGHT", b.fill, "TOPRIGHT")
    b.edge:SetPoint("BOTTOMRIGHT", b.fill, "BOTTOMRIGHT")
    b.edge:SetWidth(1)
    b.edge:SetColorTexture(K.teal[1], K.teal[2], K.teal[3], 1)
    b.text = L.Text(b, "small")
    b.text:SetPoint("CENTER")
    b.text:SetWidth(w - 12)
    b.text:SetWordWrap(false)
    b.inner = w - 4
    function b:Set(frac, text)
        if frac == nil then
            self.fill:Hide(); self.edge:Hide()
        else
            frac = math.max(0, math.min(1, frac))
            self.fill:SetWidth(math.max(1, math.floor(self.inner * frac + 0.5)))
            self.fill:Show(); self.edge:Show()
        end
        self.text:SetText(text or "")
        Paint(self.text, K.text)
    end
    return b
end

-- "Reading listings... " and 0.42 -> "Reading listings 42%"
function AB.BarText(msg, frac)
    msg = (msg or "Scanning"):gsub("%.+$", "")
    return ("%s %d%%"):format(msg, math.floor((frac or 0) * 100 + 0.5))
end

---------------------------------------------------------------------------
-- The button on the auction house window
---------------------------------------------------------------------------
function AB.Refresh()
    if not btn then return end
    local busy = SC.Busy()
    local A = W.Auto
    local prompting = not busy and A ~= nil and A.Prompting()
    -- while a scan runs the button is its Stop (Scan.Stop); during the short saving step it can only wait, so it says so and is off
    if busy then
        local saving = SC.phase == "saving"
        btn.text:SetText(saving and "Saving..." or "Stop")
        btn:SetEnabled(not saving)
    else
        btn.text:SetText(prompting and "Update prices" or "Scan prices")
        btn:SetEnabled(true)
    end
    local msg, tone = SC.Message()
    if prompting and not SC.Busy() then msg, tone = "Prices are due for an update.", "warn" end
    if busy then
        local frac = SC.Progress() or 0
        bar:Set(frac, AB.BarText(msg, frac))
        bar:Show()
        status:Hide()
    else
        bar:Hide()
        status:SetText(msg or "")
        Paint(status, tone == "good" and K.sage or (tone == "warn" and K.gold or K.textDim))
        status:SetShown(msg ~= nil and (prompting or not stale))
    end
end

local function Attach()
    if attached or type(AuctionHouseFrame) ~= "table" then return end
    attached = true
    L, K = R.Look, R.Look.pal
    local F = R.FrameLook
    local AH = AuctionHouseFrame
    btn = F.Button(AH, "Scan prices", BTN_W, "primary", function()
        -- a click while a scan runs is its Stop; otherwise it is the player's own scan (never marked automatic), which also answers a prompt
        if SC.Busy() then SC.Stop() else
            if W.Auto then W.Auto.Answered() end
            S.StartScan()
        end
        AB.Refresh()
    end)
    btn:SetHeight(H)
    btn:SetPoint("TOPRIGHT", AH, "BOTTOMRIGHT", -6, -4)
    R.Interact.Tip(btn, "Scan prices", "Reads every listing at this auction house once, so the Workshop can price your crafts. It only reads: it never buys, bids or posts. It starts when you press this, or, if you turned on automatic updates and the game allows it, once an hour when you open the auction house; \"Update prices\" means one is due. While it runs, this button stops it and nothing is saved. It can take a little while.")
    bar = W.NewBar(AH, BAR_W, H)
    bar:SetPoint("TOPRIGHT", btn, "TOPLEFT", -8, 0)
    bar:Hide()
    status = L.Text(AH, "small")
    status:SetPoint("TOPRIGHT", btn, "TOPLEFT", -8, -5)
    status:SetWidth(BAR_W + 120)
    status:SetJustifyH("RIGHT")
    status:SetWordWrap(false)
    status:Hide()
    SC.Listen(function() stale = false; AB.Refresh() end)
    if AH.HookScript then
        AH:HookScript("OnHide", function() stale = true; AB.Refresh() end)
        AH:HookScript("OnShow", AB.Refresh)
    end
    if ev then ev:UnregisterAllEvents() end
    AB.Refresh()
end

function AB.Attached() return attached end
function AB.Button() return btn end
function AB.Bar() return bar end
function AB.Status() return status end

-- Made now when Blizzard's auction house window exists, otherwise when it is loaded (its own load on demand)
function AB.Start()
    if attached then return end
    if type(AuctionHouseFrame) == "table" then return Attach() end
    ev = ev or CreateFrame("Frame")
    ev:SetScript("OnEvent", function(_, event, name)
        if event == "ADDON_LOADED" and name ~= "Blizzard_AuctionHouseUI" then return end
        Attach()
    end)
    ev:RegisterEvent("ADDON_LOADED")
    ev:RegisterEvent("AUCTION_HOUSE_SHOW")   -- (the frame may be made by another addon's load)
end

AB.Start()
