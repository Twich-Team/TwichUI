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

local function RuleStatus()
    local rows,held=Launcher().JunkRules()
    if held then return "Held for a newer version" end
    local on=0
    for _,r in ipairs(rows) do if r.on then on=on+1 end end
    return #rows==0 and "No rules yet" or (on.." of "..#rows.." on")
end

K.Page({key="junkMarking",name="Junk marking",icon="vendors",group="everyday",order=45.5,
    description="Choose which items are marked as junk using your own rules.",
    keywords="junk rules rule builder conditions templates quality gear upgrade ignore never mark protections bags vendor",
    when=function() return Launcher()~=nil end,
    overview={label="Junk marking",tip="Mark selected Advisor Vendor recommendations in EllesmereUI Bags.",
        status=Status},
    build=function()
        K.Header("Junk marking", "Marks carried items in EllesmereUI Bags when one of your rules matches every copy you carry. Add \"Workshop recommends Vendor\" to wait for Workshop's complete advice. Workshop corrects its own marks; manual and older marks stay under your control.")
        local junk=K.ProxyToggle("workshopVendorJunk", "Mark items as junk",
            "Off by default. Marks carried items that match your junk rules. The Workshop Vendor condition waits for the complete Advisor evaluation for every carried copy. Requires EllesmereUI Bags and its Junk Marker. Marks apply to every copy of an item ID across your account, including future copies. EllesmereUI may sell them through Auto Sell Junk or its Sell Junk button. Workshop corrects its own marks when their rules no longer match and withholds automatic selling while their evaluation is pending or disabled. Older and manual marks stay under your control; use EllesmereUI's junk coin to change them. Workshop respects manual unmarking for the rest of the session and leaves custom categories alone. Workshop itself sells nothing. Uses the Item Advisor service. Use Load Item Advisor below once; enabled junk marking loads the authorized service on future logins.", false,
            function() return Launcher().VendorJunkEnabled() end,
            function(on) Launcher().SetVendorJunkEnabled(on) end)
        K.Button("Item Advisor service", "Load Item Advisor (Experimental)", function()
            local ok,why=Launcher().SetEnabled(true)
            if ok then ok,why=Launcher().Load() end
            if not ok then R.Print("Junk marking: "..Launcher().Explain(why)) end
            K.RefreshOverview()
        end,"Load the Workshop Advisor dependency without opening Workshop or starting a scan. Junk marking remains controlled here. Your enabled junk feature loads this dependency on future logins.")
        K.Status("Junk marking",Status)

        K.Header("Marking rules", "Rules identify candidates: build them from conditions, test them on an item, and save when the sentence says what you mean. Any enabled rule can mark an item.")
        K.Status("Your rules",RuleStatus)
        K.Button("Marking rules", "Open the rule builder", function()
            if R.JunkBuilder then R.JunkBuilder.Open() end
        end,"Create, edit and test marking rules in a window of their own. Nothing is saved until you press Save, and nothing is marked or sold by testing.")

        K.Header("Protections", "Protections can prevent an item from being marked, and they always win over a rule. The Cozy Sleeping Bag, quest items and keys are always protected.")
        K.Button("Never mark items", "Choose from bags / drop item", function() R.WorkshopJunkSettings.Open() end,
            "Choose bag items or drop them into the ignore area. The list is shared across your account and covers every copy of each item ID. This prevents new Workshop marks; remove existing junk marks in EllesmereUI.")
        K.Status("Never mark list", function() return #Launcher().JunkIgnoreList().." items · Cozy Sleeping Bag always protected" end)
    end,
})
