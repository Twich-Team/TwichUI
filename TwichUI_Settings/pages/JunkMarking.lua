-- Independent feature settings; Workshop provides item advice, not navigation.
local R=TwichUI
local K=R.SettingsKit
local function Launcher() return R.WorkshopLauncher end
local function Loaded() return Launcher() and Launcher().Enabled() and Launcher().Loaded() end

local function Status()
    if not Launcher().VendorJunkEnabled() then return "Off" end
    if not Loaded() then return "Waiting for Item Advisor" end
    local ej=R.EllesmereJunk
    local status=ej and ej.Status() or "not-ready"
    return status=="ready" and "On" or (ej and ej.REASONS[status] or "EllesmereUI Bags is unavailable.")
end

K.Page({key="junkMarking",name="Junk marking",icon="vendors",group="everyday",order=45.5,
    description="Choose which Vendor recommendations may be marked using your own rules.",
    keywords="junk rules conditions templates quality gear upgrade ignore bags vendor",
    when=function() return Launcher()~=nil end,
    overview={label="Junk marking",tip="Mark selected Advisor Vendor recommendations in EllesmereUI Bags.",
        status=Status},
    build=function()
        K.Header("Junk marking", "Only Vendor recommendations in the item types you allow are marked. Cozy Sleeping Bag, quest items, keys and your Never mark list are protected. Existing EllesmereUI marks must be removed with its junk coin.")
        local junk=K.ProxyToggle("workshopVendorJunk", "Mark Vendor recommendations as junk",
            "Off by default. Marks carried items when Workshop recommends Vendor for every carried copy. Requires EllesmereUI Bags and its Junk Marker. Marks apply to every copy of an item ID across your account, including future copies. EllesmereUI may sell them through Auto Sell Junk or its Sell Junk button. Turning this off leaves existing marks; unmark with EllesmereUI's junk coin. Workshop respects manual unmarking for the rest of the session and leaves custom categories alone. Workshop itself sells nothing. Uses the Item Advisor service. Use Load Item Advisor below once; enabled junk marking loads the authorized service on future logins.", false,
            function() return Launcher().VendorJunkEnabled() end,
            function(on) Launcher().SetVendorJunkEnabled(on) end)
        K.Button("Item Advisor service", "Load Item Advisor (Experimental)", function()
            local ok,why=Launcher().SetEnabled(true)
            if ok then ok,why=Launcher().Load() end
            if not ok then R.Print("Junk marking: "..Launcher().Explain(why)) end
            K.RefreshOverview()
        end,"Load the Workshop Advisor dependency without opening Workshop or starting a scan. Junk marking remains controlled here. Your enabled junk feature loads this dependency on future logins.")
        K.Button("Never mark items", "Choose from bags / drop item", function() R.WorkshopJunkSettings.Open() end,
            "Choose bag items or drop them into the ignore area. The list is shared across your account and covers every copy of each item ID. This prevents new Workshop marks; remove existing junk marks in EllesmereUI.")
        K.Status("Never mark list", function() return #Launcher().JunkIgnoreList().." items · Cozy Sleeping Bag always protected" end)
        K.Status("Junk marking",Status)

    end,
    host=function() return R.WorkshopJunkRulesSettings.Frame() end,
    hostAfter="Junk marking",hostHeight=function() return R.WorkshopJunkRulesSettings.Height() end,
})
