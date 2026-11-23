-- Connect existing presentation surfaces; no Workshop loading and no animation pricing.
local F = TwichUI.Fishing
local E, S = F.Economy, F.Store
local function Provider(kind, id, q)
    if S.Get("economy.enabled") == false then return nil end
    if kind == "item" then
        local row = E.Item(id, q)
        return row and row.total ~= nil and E.Text(row.total) or nil
    end
    if kind ~= "session" then return nil end
    local v = E.Scope("session")
    if not v or (not v.total and not v.market) then return nil end
    local items = {}
    for _, group in ipairs({ v.direct, v.contents, v.provisional }) do
        for item, row in pairs(group) do if row.total ~= nil then items[item] = E.Text(row.total) end end
    end
    local text = v.total and E.Text(v.total) .. (v.complete and "" or " *") or "Prices pending / unavailable"
    local rate = S.Get("economy.perHour") and v.perHour and (E.Text(v.perHour) .. "/h") or nil
    return { text = text, items = items, perHourText = rate }
end
F.Present.SetValueProvider(Provider)
F.Subscribe("ECONOMY", function()
    -- Hud.serial was bumped before this event; the presentation's session cache is invalid.
    if F.CatchList.Shown() then F.CatchList.Refresh() end
    if F.CastBar.Shown() then F.CastBar.RefreshLines() end
end)
