-- Optional integrated status and transaction review, using existing materials
-- and passive snapshots. No update driver and no native calls on page opening.
local R,W=TwichUI,TwichUI.Workshop
local A,UI=W.AuctionUI,W.UI
local panel,review
local function Money(n) return n~=nil and UI.Money(n) or "Unavailable" end
function A.DebugShown() return panel and panel:IsShown() or false end
function A.UpdateDebug()
    if not panel or not panel:IsShown() then return end
    local h=R.AuctionHost.Snapshot()
    local q=W.AuctionReads.Snapshot()
    local t=W.AuctionActions.Snapshot()
    panel.text:SetText("Interface: "..(h.state=="twichui" and "TwichUI" or h.state=="recovery" and "Restoration pending" or "Blizzard")..
        "   ·   Auctioneer: "..(R.AuctionHost.IsCurrent(h.visit) and "Connected" or "Unavailable").."\nPage: "..A.Mode()..
        "   ·   Live request: "..q.state.."   ·   Throttle: "..(q.throttle and "Ready" or "Busy")..
        "\nSent: "..(q.lastRequest or "None").."   ·   Response: "..(q.lastResponse or "None")..
        "\nResults: "..q.results.."   ·   Complete: "..(q.complete and "Yes" or "No / unverified")..
        "\nAction: "..t.state.."   ·   "..(t.message or "No action pending").."\nRead error: "..(q.error or "None")..
        "\nRestore: "..h.reason.."   ·   Open: "..string.format("%.1f",h.openMS or 0).." ms   ·   Switch: "..string.format("%.2f",h.switchMS or 0).." ms"..
        "\nFrame time estimate: "..(GetFramerate and string.format("%.2f ms at %.0f FPS",1000/math.max(1,GetFramerate()),GetFramerate()) or "Unavailable")..
        "   ·   Detailed capture: /tui perf start auction 2")
end
function A.ToggleDebug()
    if not A.IsShown() or A.Context()~="auctioneer" then return end
    if not panel then
        panel=CreateFrame("Frame",nil,A.Frame(),"BackdropTemplate")
        panel:SetSize(720,234);panel:SetPoint("BOTTOM",0,52);panel:SetFrameStrata("DIALOG")
        UI.Panel(panel,"card");panel:EnableMouse(true)
        panel.text=A.Text(panel,"",12,14,-14,-14);panel.text:SetWordWrap(true);panel.text:SetHeight(196)
        panel.close=R.FrameLook.Close(panel,function() panel:Hide() end);panel.close:SetPoint("TOPRIGHT",-4,-4)
        panel:Hide()
    end
    panel:SetShown(not panel:IsShown());A.UpdateDebug()
end
function A.UpdateReview()
    if not review or not review:IsShown() then return end
    local d=W.AuctionActions.Review()
    if not d then review:Hide();return end
    review.id=d.id
    review.displayed=d
    local state=d.state=="quoted" and "Authoritative quote — confirm this total" or d.state=="review" and "Review auction action" or "Waiting for native result"
    local vendor=d.vendor and (d.vendor.status=="below" and "\nWARNING: below vendor value. Confirmation is held for one second." or d.vendor.status=="unknown" and "\nVendor value is unavailable." or "") or ""
    review.text:SetText(state.."\n"..d.kind.." · Item "..d.item.."\nQuantity: "..d.quantity..
        (d.desired and (" · Needed: "..d.desired.." · Excess: "..d.excess) or "")..
        (d.estimated and "\nEstimate (quote required): " or "\nTotal: ")..Money(d.total)..(d.deposit and ("\nDeposit upfront: "..Money(d.deposit)) or "")..
        (d.duration and ("\nDuration choice: "..d.duration) or "")..vendor..
        "\n"..(d.reason or d.message or "Every action needs your explicit confirmation."))
    review.confirm.text:SetText(d.kind=="buyCommodity" and d.state=="review" and "Request quote" or "Confirm")
    review.confirm:SetEnabled(d.allowed and (d.state=="review" or d.state=="quoted"))
end
function A.ReviewAction(id,why)
    if not id then A.Note(why);return false end
    if not review then
        review=CreateFrame("Frame",nil,A.Frame(),"BackdropTemplate")
        review:SetSize(540,300);review:SetPoint("CENTER");review:SetFrameStrata("DIALOG");review:EnableMouse(true)
        UI.Panel(review,"card")
        review.text=A.Text(review,"",14,18,-18,-18);review.text:SetHeight(214);review.text:SetWordWrap(true)
        review.confirm=UI.Button(review,"Confirm",180,"primary",function()
            local d=W.AuctionActions.Review();if not d or d.id~=review.id then return end
            local function Confirm()
                local ok,reason=W.AuctionActions.Confirm(d.id,review.displayed)
                if not ok then A.Note(reason) end
                A.UpdateReview();A.UpdateDebug()
            end
            if d.vendor and d.vendor.status=="below" then
                R.Interact.Confirm("TWICHUI_AH_VENDOR_REVIEW",R.AuctionPrice.VendorQuestion(d.vendor,"the reviewed item",Money),Confirm,{accept="Post anyway",hold=1})
            else Confirm() end
        end,32)
        review.confirm:SetPoint("BOTTOMLEFT",18,18)
        review.cancel=UI.Button(review,"Dismiss",180,"secondary",function() W.AuctionActions.Cancel();review:Hide() end,32)
        review.cancel:SetPoint("BOTTOMRIGHT",-18,18)
    end
    review:Show();A.UpdateReview();return true
end
function A.HideExtras()
    if panel then panel:Hide() end
    if review then review:Hide() end
    W.AuctionActions.Cancel()
end

function A.HideReview()
    if review then review:Hide() end
    W.AuctionActions.Cancel()
end
