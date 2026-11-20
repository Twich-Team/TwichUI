dofile(TESTS .. 'harness.lua')
dofile(TESTS .. 'settings_mock.lua')
local c,S = SettingsClient()
local R,K = c.TwichUI,S.K
local C,D = R.ClassPortrait,R.ClassPortraitDisplay
local page = assert(K.pages.classPortrait)
assert(page.def.overview and page.def.icon == 'classPortrait')
local reset,preview
for _,row in ipairs(page.rows) do
    if row:GetName() == 'Reset to Automatic' then reset = row end
    if row:GetName() == 'Show Decoration Preview' then preview = row end
end
assert(reset and preview)
local refreshed = 0
K.onRefresh = function() refreshed = refreshed+1 end
C.Set('enabled',true); C.Set('automatic',false); C.Set('size',140); C.Set('x',20); C.Set('y',-10)
reset.click()
assert(C.Get('enabled') and C.Get('automatic') and C.Get('size') == 100 and C.Get('x') == 0 and C.Get('y') == 0)
assert(refreshed == 1, 'reset redraws the displayed slider/toggle values')
C.Set('enabled',false)
preview.click(); assert(D.PreviewActive(), 'preview can configure while off')
assert(refreshed == 2, 'preview refreshes attachment status')
preview.click(); assert(not D.PreviewActive(), 'second click stops preview')
assert(refreshed == 3)
assert(R.SettingsSearch.Run('class portrait')[1].entry.page == 'classPortrait', 'search routes to feature')
print('PASSED')
