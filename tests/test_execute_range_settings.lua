dofile(TESTS .. 'harness.lua')
dofile(TESTS .. 'settings_mock.lua')
local c,S = SettingsClient()
local R,K = c.TwichUI,S.K
local C = R.ExecuteRange
local page = assert(K.pages.executeRange)
assert(page.def.icon == 'diagOperations' and R.Icons.Get(page.def.icon))
assert(not R:Enabled('executeRange') and C.Get('threshold') == 20 and C.Get('target') and C.Get('nameplates'))
assert(C.Get('appearance') == 'both' and c.TwichUIDB.ui.executeRange == nil,'no eager persisted defaults')
local main = assert(K.rowsById.executeRange)
for _,id in ipairs({'executeRangeThreshold','executeRangeTarget','executeRangeNameplates','executeRangeAppearance'}) do
    local row = assert(K.rowsById[id],id)
    assert(row.parent == main and not row:Enabled() and row:DisabledReason(),'off prerequisite is explained')
    assert(S.variables['TWICHUI_' .. id], 'unique persisted control registered')
end
local threshold = S.variables.TWICHUI_executeRangeThreshold
assert(threshold.slider.min == 1 and threshold.slider.max == 100 and threshold.slider.step == 1)
threshold:SetValue(1); assert(C.Get('threshold') == 1)
threshold:SetValue(100); assert(C.Get('threshold') == 100)
assert(not C.Set('threshold',0) and not C.Set('threshold',101) and not C.Set('threshold',math.huge))
S.variables.TWICHUI_executeRange:SetValue(true)
assert(R:Enabled('executeRange') and K.rowsById.executeRangeThreshold:Enabled())
for _,choice in ipairs(C.CHOICES.appearance) do
    S.variables.TWICHUI_executeRangeAppearance:SetValue(choice[1]); assert(C.Get('appearance') == choice[1])
end
local reset, status, warning
for _,row in ipairs(page.rows) do
    if row:GetName() == 'Execute Range settings' then reset = row end
    if row:GetName() == 'EllesmereUI health bars' then status = row end
    if row:GetName() == 'Protected health and combat' then warning = row end
end
assert(reset and status and warning,'reset, status and persistent restriction explanation')
assert(status.detail():find('Missing or incompatible',1,true))
local originalStatus = R.ExecuteRangeDisplay.Status
R.ExecuteRangeDisplay.Status = function() return 'on',false,0,true,false end
assert(status.detail():find('Health is restricted',1,true),'unknown health explanation')
R.ExecuteRangeDisplay.Status = function() return 'on',false,0,false,true end
assert(status.detail():find('waits until combat ends',1,true),'protected layout explanation')
R.ExecuteRangeDisplay.Status = originalStatus
local found
for _,result in ipairs(R.SettingsSearch.Run('health threshold')) do if result.entry.page == 'executeRange' then found = true end end
assert(found,'global search discovers threshold page')
C.Set('threshold',35); C.Set('target',false); C.Set('nameplates',false); C.Set('appearance','marker')
local group = assert(R.TwichConfig.Group('executeRange'))
assert(group.complete,'sharing group has all defaults and validators')
local shared = assert(R.TwichConfig.Build({all=true})).groups.executeRange
assert(shared.modules.executeRange == true and shared.executeRange.threshold == 35
    and shared.executeRange.target == false and shared.executeRange.nameplates == false and shared.executeRange.appearance == 'marker')
local original = R.Profiles.Current()
assert(R.Profiles.Duplicate('Execute copy'))
C.Set('threshold',25); assert(C.Get('threshold') == 25)
assert(R.Profiles.Switch(original)); assert(C.Get('threshold') == 35,'profile settings copied independently')
S.ClickReset(reset)
assert(C.Get('threshold') == 20 and C.Get('target') and C.Get('nameplates') and C.Get('appearance') == 'both')
assert(R:Enabled('executeRange'),'section reset preserves main switch')
print('PASSED')
