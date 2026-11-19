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
-- Real nested expressions, independent item types and unknown evidence.
local T=L.JunkTree
local tree={type='group',match='any',children={
 {type='group',match='all',children={{type='kind',value='gear'},{type='upgrade',value=false}}},
 {type='group',match='all',children={{type='kind',value='materials'},{type='profession',value=false}}},
}}
assert(T.Match(tree,{kind='gear',upgrade=false})==true)
assert(T.Match(tree,{kind='gear',upgrade=true})==false)
assert(T.Match(tree,{kind='gear'})==nil,'unknown upgrade is not no')
assert(T.Match(tree,{kind='materials',profession=false})==true,'irrelevant gear branch cannot block proven material branch')
assert(T.Match(tree,{kind='materials'})==nil)
assert(T.Match({type='group',match='any',children={}}, {})==false,'empty groups never match')
local copy=assert(T.Copy(tree));assert(T.Equal(copy,tree) and copy~=tree)
assert(not T.Move(tree,tree,tree,1,true))
local gear,materials=tree.children[1],tree.children[2]
assert(not T.Move(tree,gear,gear,1,true),'cannot drop into self')
assert(not T.Move(tree,gear,gear.children[1],1,true),'cannot drop into a leaf')
local leaf=gear.children[2]
assert(T.Move(tree,leaf,materials,1,false) and gear.children[2]==leaf,'validation has no side effects')
assert(T.Move(tree,leaf,materials,1,true) and materials.children[1]==leaf)
assert(T.Move(tree,leaf,gear,2,true) and T.Equal(tree,copy),'cross-group movement and ordering round trip')
local deep={type='group',match='all',children={}};local cursor=deep
for i=1,4 do local g={type='group',match='all',children={}};cursor.children[1]=g;cursor=g end
assert(not T.Copy(deep),'excessive nesting refused')
local many={type='group',match='any',children={}}
for i=1,32 do many.children[i]={type='kind',value='gear'} end
assert(not T.Copy(many),'node count bounded')
local cycle={type='group',match='all',children={}};cycle.children[1]=cycle;assert(not T.Copy(cycle))
assert(not T.Copy({type='alien'}))
-- Version-1 rules read without writes; saving the tree upgrades only the extension.
db.ui.workshopJunk.rules={v=1,rows={{kind='gear',on=true,match='all',qualityMin=0,qualityMax=2,wearable='any',upgrade='no',classReagent='any',profession='any'}}}
local rows=L.JunkRules();rows[1].tree=T.FromRule(rows[1])
assert(db.ui.workshopJunk.rules.v==1)
local before=L.JunkRules();assert(L.SaveJunkRule(1,rows[1],before))
assert(db.ui.workshopJunk.rules.v==2 and L.JunkAllows(300,2,{quality=1,upgrade=false}))
assert(not L.JunkAllows(300,2,{quality=1}))
local codec=c.LibStub and c.LibStub('LibSerialize',true)
if codec then local ok,decoded=codec:Deserialize(codec:Serialize(db.ui.workshopJunk.rules));assert(ok);db.ui.workshopJunk.rules=decoded;assert(L.JunkAllows(300,2,{quality=1,upgrade=false})) end
print('PASSED nested junk trees: AND/OR truth, unknowns, movement, bounds, migration and persistence')
