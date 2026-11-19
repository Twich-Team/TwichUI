local c=dofile(TESTS..'auction_mock.lua')
local L=c.TwichUI.WorkshopLauncher
local db=c.TwichUIDB
assert(L.JunkTemplate(1,'nonupgrade'))
-- Start with just this rule; other legacy rules are intentionally not in use.
local saved=db.ui.workshopJunk.rules
saved.rows={saved.rows[1]}
assert(not L.JunkAllows(100,2,{quality=1,upgrade=false}),'templates start disabled')
assert(L.SetJunkRule(1,'on',true))
assert(L.JunkAllows(100,2,{quality=1,upgrade=false}))
assert(not L.JunkAllows(100,2,{quality=3,upgrade=false}))
assert(not L.JunkAllows(100,2,{quality=1,upgrade=true}))
assert(not L.JunkAllows(100,2,{quality=1}),'unknown upgrade is not no')
assert(L.SetJunkRule(1,'match','any'))
assert(L.JunkAllows(100,2,{quality=3,upgrade=false}),'OR combines conditions')
assert(not L.JunkAllows(100,2,{quality=1}),'unknown requested facts block even OR')
assert(L.SetJunkIgnored(100,true));assert(not L.JunkAllows(100,2,{quality=1,upgrade=false}))
assert(not L.JunkAllows(211527,2,{quality=1,upgrade=false}))
assert(not L.SetJunkRule(1,'qualityMin',5),'invalid reversed range refused')
assert(L.JunkTemplate(1,'materials'));assert(L.SetJunkRule(1,'on',true))
assert(L.SetJunkRule(1,'profession','yes'))
assert(L.JunkAllows(200,7,{profession=true}))
assert(not L.JunkAllows(200,7,{profession=false}))
assert(not L.JunkAllows(200,7,{}))
assert(L.SetJunkRule(1,'classReagent','no'))
assert(not L.JunkAllows(200,7,{profession=true}),'unknown class membership cannot satisfy no')
db.ui.workshopJunk.rules={v=99,rows={}}
assert(not L.JunkAllows(200,7,{profession=true}) and not L.JunkTemplate(1,'poor'),'future rules held')
print('PASSED junk rules: AND/OR, quality ranges, upgrades, profession, unknowns, ignores and future versions')
