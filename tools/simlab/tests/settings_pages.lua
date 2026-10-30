-- Simulator lab test (docs/simulator-lab.md), run by the simulator's run-tests against the lab's copy of the addon:
-- every settings page this client describes opens through R:OpenSettings and constructs (it is selected and has a
-- view). It says nothing about what a control does when used (tools/simlab/interact.sh does that for one page), or
-- how a page looks.
local Out = rawget(_G, "A_Print") or print

test("every settings page opens through R:OpenSettings and constructs", function()
    local R = TwichUI
    assertTrue(R:OpenSettings("overview"))
    local K, UI = R.SettingsKit, R.SettingsUI
    local failed, built = {}, 0
    for _, page in ipairs(K.list) do
        local ok, why = R:OpenSettings(page.key)
        local view = UI.View(page.key)
        local selected = UI.Selected()
        local fine = ok and view ~= nil and selected == page.key
        if fine then
            built = built + 1
        else
            failed[#failed + 1] = page.key
        end
        Out(("SIMLAB page %s %s selected=%s why=%s"):format(page.key, fine and "ok" or "FAILED", tostring(selected), tostring(why)))
    end
    Out(("SIMLAB pages described=%d constructed=%d"):format(#K.list, built))
    assertEquals("", table.concat(failed, " "))
end)
