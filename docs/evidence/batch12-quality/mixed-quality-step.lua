-- Test-only metadata values from Forever ItemQuality enums. These deliberately
-- synthetic inputs do not claim the named example items have these rarities.
Lab.Step("W27 mixed quality presentation", function()
    Lab.BUDGET = 60 -- additional metadata/redraw step, without shortening baseline
    -- No-assets simulator returns white for all native quality palette entries.
    -- This test provider uses TwichUI's existing Loot quality palette instead.
    local palette = assert(TwichUI.LootRules.QUALITY_COLOR)
    C_Item.GetItemQualityColor = function(q)
        local c = palette[q]
        if c then return c[1],c[2],c[3] end
    end
    local W = TwichUI.Workshop
    local quality = { [118]=2,[3382]=3,[2851]=4,[2841]=2,
        [2447]=2,[765]=3,[2320]=4,[2770]=2,[2771]=3,[3371]=1 }
    local original = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(item)
        local a = { original(item) }
        a[3] = quality[item] or a[3]
        return unpack(a, 1, 17)
    end
    local window = W.Window.Frame()
    for id in pairs(quality) do
        -- Scenario Event(name) drops arguments; exercise the real handler with
        -- the documented item ID/success payload so selected details invalidate.
        window:GetScript("OnEvent")(window,"GET_ITEM_INFO_RECEIVED",id,true)
        Lab.Settle(.3)
    end
    Lab.Settle(1)
    W.Window.Render()
    local lists = W.Window.Lists()
    local rows = params.view == "craft" and lists.queue.rows or params.view == "shop" and lists.shop.rows or lists.opps.rows
    local colors, checked = {}, 0
    for _, row in ipairs(rows) do
        local item = row.entry and row.entry.outItem or row.rec and row.rec.outItem or row.data and row.data.item
        if row:IsShown() and quality[item] and W.Observe.ItemFacts(item) == row.name:GetText() then
            local r,g,b = row.name:GetTextColor()
            local expected = palette[quality[item]]
            local er,eg,eb = expected[1],expected[2],expected[3]
            local function rgb(x,y,z) return ("%.3f %.3f %.3f"):format(x,y,z) end
            Lab.Check("display","W27 actual row RGB "..item,rgb(er,eg,eb),rgb(r,g,b))
            colors[quality[item]], checked = true, checked + 1
        end
    end
    if params.view == "opps" then
        local detail = W.Window.Opps().detail
        local function checkFont(fs,item)
            local actual = { fs:GetTextColor() }
            local expected = palette[quality[item]]
            local function rgb(c) return ("%.3f %.3f %.3f"):format(c[1],c[2],c[3]) end
            Lab.Check("display","W27 selected detail RGB "..item,rgb(expected),rgb(actual))
        end
        checkFont(detail.name,detail.item)
        for _, line in ipairs(detail.mats) do
            if line:IsShown() and quality[line.item] then checkFont(line.name,line.item) end
        end
    end
    Lab.Check("display","W27 uncommon visible",true,colors[2]==true)
    Lab.Check("display","W27 rare visible",true,colors[3]==true)
    Lab.Check("display","W27 epic visible",true,colors[4]==true)
    Lab.Check("state","W27 at least three item names checked",true,checked>=3)
    Lab.Settle(.5)
end)
