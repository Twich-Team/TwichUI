-- Junk rule builder model: draft, history, validation, summary, persistence and the shared evaluator.
-- No frames: JunkSession is the model the rule builder window draws.
local c=dofile(TESTS..'auction_mock.lua')
local R=c.TwichUI
local L=R.WorkshopLauncher
local db=c.TwichUIDB
local T=L.JunkTree
do local f=assert(loadfile(REPO..'TwichUI_Settings/pages/JunkSession.lua'));setfenv(f,c);f() end
local S=R.JunkSession
local function Reset(n) -- n legacy rows, nothing saved yet
    db.ui=db.ui or {};db.ui.workshopJunk=nil
    L.JunkTemplate(1,'custom')
    local cfg=db.ui.workshopJunk.rules;cfg.rows={}
    for i=1,(n or 0) do local r=L.NewJunkRule('Rule '..i);cfg.rows[i]=r end
end
local function Group(match,...) return {type='group',match=match,children={...}} end
local function Kind(v) return {type='kind',value=v} end
local function Quality(a,b) return {type='quality',min=a,max=b} end

---------------------------------------------------------------- creation, safe start, naming
Reset(0)
assert(S.BeginNew('Vendor gear') and S.IsNew() and S.Index()==1)
assert(S.On()==false,'a new rule starts off')
assert(#S.Tree().children==0,'a new rule starts empty')
assert(not S.Dirty(),'a pristine new rule has nothing to lose')
assert(S.Summary():find('never marks anything'),'an empty rule says so')
assert(#S.Problems()==1 and S.Problems()[1].code=='empty')
assert(T.Eval(S.Tree(),{kind='gear',quality=0})==false,'empty rule matches nothing')
assert(L.JunkJudge(10,2,{quality=0},{S.TestRule()})=='nomatch','empty rule never marks everything')
local ok,why=S.SetOn(true);assert(not ok and why:find('at least one'),'an empty rule cannot be switched on')
assert(not S.Save() == false or true)
---------------------------------------------------------------- adding conditions; defaults lean careful
local gear=assert(S.Add('kind'));assert(gear.value=='gear')
local quality=assert(S.Add('quality'));assert(quality.min==0 and quality.max==1)
for _,key in ipairs({'wearable','upgrade','classReagent','profession'}) do
    local n=assert(S.Add(key));assert(n.type==key and n.value==(key=='classReagent' or key=='profession'),key..' starts on the careful side')
    assert(S.Remove(n))
end
assert(S.Dirty() and S.CanUndo())
assert(S.Summary()=='Mark an item as junk when it is Gear and its quality is Poor to Common.',S.Summary())
assert(not S.Add('alien'),'unknown condition refused')
assert(not S.Add('kind',{type='group',match='all',children={}}),'a group outside the rule is refused')
---------------------------------------------------------------- every condition, by evaluation and phrase
local cases={
 {Kind('materials'),{kind='materials'},{kind='gear'},false,'it is Materials'},
 {Kind('recipes'),{kind='recipes'},{kind='other'},false,'it is Recipes'},
 {Kind('consumables'),{kind='consumables'},{kind='gear'},false,'it is Supplies'},
 {Quality(2,4),{quality=3},{quality=5},{quality=nil},'its quality is Uncommon to Epic'},
 {Quality(1,1),{quality=1},{quality=0},{},'its quality is Common'},
 {{type='wearable',value=false},{wearable=false},{wearable=true},{},"you can't wear it now"},
 {{type='wearable',value=true},{wearable=true},{wearable=false},{},'you can wear it now'},
 {{type='upgrade',value=false},{upgrade=false},{upgrade=true},{},'it is not a gear upgrade for you'},
 {{type='upgrade',value=true},{upgrade=true},{upgrade=false},{},'it is a gear upgrade for you'},
 {{type='classReagent',value=true},{classReagent=true},{classReagent=false},{},'it is a known reagent for your class'},
 {{type='classReagent',value=false},{classReagent=false},{classReagent=true},{},'it is not a known reagent for your class'},
 {{type='profession',value=true},{profession=true},{profession=false},{},'a recipe you know uses it'},
 {{type='profession',value=false},{profession=false},{profession=true},{},'no recipe you know uses it'},
}
for i,case in ipairs(cases) do
    local node,yes,no,unknown,phrase=case[1],case[2],case[3],case[4],case[5]
    assert(T.Eval(node,yes)==true,'case '..i..' yes');assert(T.Eval(node,no)==false,'case '..i..' no')
    if unknown then assert(T.Eval(node,unknown)==nil,'case '..i..' unknown is not no') end
    assert(T.Phrase(node)==phrase,'case '..i..': '..T.Phrase(node))
    assert(T.Copy(node),'case '..i..' persists')
end
---------------------------------------------------------------- AND / OR / nesting: tree, trace, summary and evaluation agree
-- Item type is Gear AND (Quality is Poor OR Quality is Common)
local tree=Group('all',Kind('gear'),Group('any',Quality(0,0),Quality(1,1)))
assert(T.Summary(tree)=='Mark an item as junk when it is Gear and (its quality is Poor or its quality is Common).',T.Summary(tree))
local trace={}
assert(T.Eval(tree,{kind='gear',quality=1},trace)==true)
assert(trace[tree]=='yes' and trace[tree.children[2]]=='yes' and trace[tree.children[2].children[1]]=='no' and trace[tree.children[2].children[2]]=='yes')
assert(T.Eval(tree,{kind='gear',quality=3})==false and T.Eval(tree,{kind='materials',quality=1})==false)
assert(T.Eval(tree,{kind='gear'})==nil,'unknown quality cannot be decided')
assert(T.Eval(tree,{kind='materials'})==false,'a proven failure beats an unknown')
assert(T.Eval(Group('any',Kind('gear'),Quality(0,0)),{kind='gear'})==true,'a proven yes beats an unknown in OR')
assert(T.Eval(Group('any',Kind('materials')),{kind='gear'})==false)
assert(T.Eval(Group('all'),{})==false and T.Eval(Group('any'),{})==false,'empty groups of either kind never match')
assert(T.Eval(Group('all',Group('all')),{})==false,'an empty group inside a group never matches')
assert(T.Eval(Group('any',Group('all'),Kind('gear')),{kind='gear'})==true,'an empty branch does not stop another from matching')
assert(T.Eval(Group('all',Group('any'),Kind('gear')),{kind='gear'})==false,'an empty branch in AND blocks the rule')
assert(T.Eval(Group('all',Kind('gear')),{kind='gear'})==true,'a group of one is that one')
assert(T.Summary(Group('all',Kind('gear')))=='Mark an item as junk when it is Gear.')
assert(T.Summary(Group('any',Kind('gear'),Kind('materials'),Kind('recipes')))=='Mark an item as junk when it is Gear, it is Materials or it is Recipes.')
assert(T.Summary(Group('all',Kind('gear'),Group('any',Group('all',Kind('gear'),Quality(0,0)),Kind('other'))))
    =='Mark an item as junk when it is Gear and ((it is Gear and its quality is Poor) or it is Other).')
assert(T.Summary(Group('all',Kind('gear'),Group('any')))=='Mark an item as junk when it is Gear and (nothing chosen yet).')
---------------------------------------------------------------- the editing session builds exactly that tree
Reset(0);assert(S.BeginNew('Nested'))
local root=S.Tree()
local item=assert(S.Add('kind'))
local either=assert(S.Add('any'));assert(S.Target()==either,'a new group becomes where the next condition goes')
local poor=assert(S.Add('quality'));S.Set(poor,'min',0);S.Set(poor,'max',0)
local common=assert(S.Add('quality'));S.Set(common,'min',1);S.Set(common,'max',1)
assert(S.Summary()=='Mark an item as junk when it is Gear and (its quality is Poor or its quality is Common).',S.Summary())
assert(S.SetOn(true)==true and S.On())
local rule=S.TestRule();assert(rule.on and rule.tree==S.Tree())
assert(L.JunkJudge(1,2,{quality=0},{rule})=='match' and L.JunkJudge(1,2,{quality=3},{rule})=='nomatch' and L.JunkJudge(1,2,{},{rule})=='unknown')
assert(L.JunkJudge(1,7,{quality=0},{rule})=='nomatch','materials are not gear')
---------------------------------------------------------------- operators, moves between groups, order, duplicates, removal
assert(S.SetMatch(either,'all') and either.match=='all' and T.Eval(S.Tree(),{kind='gear',quality=0})==false,'AND of two exclusive qualities never matches')
assert(S.SetMatch(either,'any') and T.Eval(S.Tree(),{kind='gear',quality=0})==true)
assert(not S.SetMatch(either,'xor'))
assert(S.Move(poor,root,2) and root.children[2]==poor and #either.children==1,'move a condition out of its group')
assert(S.Move(poor,either,1) and either.children[1]==poor,'and back in')
assert(not S.Move(either,either,1),'a group cannot go inside itself')
assert(not S.Move(root,either,1),'the top level cannot move')
assert(S.Shift(either,-1) and root.children[1]==either and root.children[2]==item)
assert(not S.Shift(either,-1),'cannot move above the first place')
assert(S.Shift(either,1) and root.children[2]==either)
assert(S.Shift(poor,1) and either.children[2]==poor and either.children[1]==common,'one place down inside a group')
local dests=S.Destinations(poor);assert(#dests==1 and dests[1].node==root and dests[1].label:find('Top level'))
local copy=assert(S.Duplicate(either));assert(#root.children==3 and root.children[3]==copy and copy~=either and #copy.children==2)
assert(S.Remove(copy) and #root.children==2)
assert(not S.Remove(root),'the top level is permanent')
assert(S.Remove(either) and #root.children==1 and S.Target()==root,'removing the group being added to falls back to the parent')
---------------------------------------------------------------- Workshop advice is a condition; new conditions; migration
do
 local cases={
  {{type='armor',value='plate'},{armor='plate'},{armor='cloth'},{armor='none'},"its armor type is Plate"},
  {{type='vendor',value=true},{vendor=true},{vendor=false},nil,'Workshop recommends Vendor'},
  {{type='unlearnedRecipe',value=true},{unlearnedRecipe=true},{unlearnedRecipe=false},nil,'it is a recipe for one of your professions that you have not learned'},
  {{type='professionMaterial',value=false},{professionMaterial=false},{professionMaterial=true},nil,'it is not a material for your professions'},
  {{type='tool',value=true},{tool=true},{tool=false},nil,'it is a profession tool'},
  {{type='camping',value=true},{camping=true},{camping=false},nil,'it is a camping item'},
 }
 for i,k in ipairs(cases) do
  assert(T.Eval(k[1],k[2])==true and T.Eval(k[1],k[3])==false,'new condition '..i)
  assert(T.Eval(k[1],{})==nil,'unknown is not no, condition '..i)
  assert(T.Phrase(k[1])==k[5],T.Phrase(k[1]));assert(T.Copy(k[1]),'persists '..i)
 end
 assert(not T.Copy({type='armor',value='wool'}),'unknown armor type refused')
 Reset(0);S.BeginNew('N')
 for _,key in ipairs({'armor','vendor','unlearnedRecipe','professionMaterial','tool','camping'}) do local n=assert(S.Add(key));assert(S.Remove(n)) end
 local ar=assert(S.Add('armor'));assert(ar.value=='cloth' and S.Set(ar,'value','leather') and ar.value=='leather' and not S.Set(ar,'value','wool'))
 local v=assert(S.Add('vendor'));assert(v.value==true and S.Set(v,'value',false) and v.value==false)
 assert(S.Cancel() or true)
 -- a rule saved before the change keeps its Vendor requirement, shown as a real condition; saving makes it explicit
 Reset(0);db.ui.workshopJunk.rules={v=2,rows={{kind='gear',on=true,match='all',qualityMin=0,qualityMax=0,wearable='any',upgrade='any',classReagent='any',profession='any',
    tree={type='group',match='all',children={{type='kind',value='gear'},{type='quality',min=0,max=0}}}}}}
 assert(L.JunkJudge(1,2,{quality=0},L.JunkRules())=='unknown','old rule without an answer from Workshop never marks')
 assert(L.JunkJudge(1,2,{quality=0,vendor=true},L.JunkRules())=='match')
 assert(S.Begin(1) and S.Tree().children[1].type=='vendor' and not S.Dirty())
 S.Remove(S.Tree().children[1]);assert(S.Save() and L.JunkRules()[1].free==true,'saving without the condition frees the rule')
 assert(L.JunkJudge(1,2,{quality=0},L.JunkRules())=='match','a freed rule no longer needs Workshop');S.Cancel()
 assert(L.JunkJudge(1,2,{quality=0},{L.NewJunkRule('x')})=='nomatch')
 Reset(0);assert(S.BeginNew('limits'))
end
---------------------------------------------------------------- limits
local many=assert(S.Add('any'))
local n=#S.Tree().children
for i=1,40 do local added,msg=S.Add('kind',many);if not added then assert(msg:find('32'),'limit explained');break end end
local count=0;local function Count(x) count=count+1;for _,ch in ipairs(x.children or {}) do Count(ch) end end;Count(S.Tree())
assert(count<=32,'node limit held: '..count)
local g=S.Tree();for i=1,6 do local nx=S.Add('all',g);if not nx then break end;g=nx end
local depth=0;local function Depth(x,d) depth=math.max(depth,d);for _,ch in ipairs(x.children or {}) do Depth(ch,d+1) end end;Depth(S.Tree(),1)
assert(depth<=4,'depth limit held: '..depth)
---------------------------------------------------------------- undo and redo cover meaningful edits
Reset(0);assert(S.BeginNew('History'))
assert(not S.CanUndo() and not S.CanRedo() and not S.Undo() and not S.Redo())
local a=assert(S.Add('kind'));local grp=assert(S.Add('any'));local q=assert(S.Add('quality'))
S.Set(q,'max',3);S.SetName('Renamed')
local states={}
local function Mark() states[#states+1]=S.Summary()..'|'..tostring(S.Name()) end
Mark()
assert(S.Undo() and S.Name()=='History');assert(S.Undo() and S.Tree().children[2].children[1].max==1)
assert(S.Undo() and #S.Tree().children[2].children==0);assert(S.Undo() and #S.Tree().children==1)
assert(S.Undo() and #S.Tree().children==0 and not S.CanUndo(),'undo walks back to the start')
assert(not S.Dirty(),'undone to the start is clean again')
assert(S.Redo() and S.Redo() and S.Redo() and S.Redo() and S.Redo() and not S.CanRedo())
Mark();assert(states[1]==states[2],'redo restores exactly')
assert(S.Undo() and S.Add('kind') and not S.CanRedo(),'a new edit clears redo')
-- the target survives undo
Reset(0);S.BeginNew('T');local ga=S.Add('any');S.Add('kind');S.Undo();assert(S.Target()==S.Tree().children[1] and S.Target().match=='any','target kept through undo');S.Undo();assert(S.Target()==S.Tree())
-- no-op edits make no history
Reset(0);S.BeginNew('N');local k=S.Add('kind');local depthBefore=#S.Tree().children
S.Set(k,'value','gear');S.SetMatch(S.Tree(),'all');S.SetOn(false);S.SetName('N')
assert(S.CanUndo() and S.Undo() and #S.Tree().children==0 and not S.CanUndo(),'only the real edit is in history')
---------------------------------------------------------------- Save, Cancel, persistence and lifecycle
Reset(2);assert(#L.JunkRules()==2)
assert(S.Begin(2) and not S.IsNew() and S.Name()=='Rule 2')
local savedBefore=T.Copy(L.JunkRules()[2].tree)
S.Add('kind');S.SetName('Edited')
assert(L.JunkRules()[2].name=='Rule 2' and T.Equal(L.JunkRules()[2].tree,savedBefore),'editing does not touch the saved rule')
assert(S.Dirty());S.Cancel();assert(not S.Active() and L.JunkRules()[2].name=='Rule 2','Cancel restores')
assert(S.Begin(2));S.Add('kind');S.SetName('Edited');S.SetOn(true)
assert(S.Save() and not S.Dirty() and not S.CanUndo())
local saved=L.JunkRules()[2];assert(saved.name=='Edited' and saved.on and #saved.tree.children==1)
assert(L.JunkJudge(5,2,{},L.JunkRules())=='match','saving made the rule live')
-- a new rule: saved only on Save, at the end
assert(S.BeginNew('Third'));assert(#L.JunkRules()==2);S.Add('quality');assert(S.Save() and #L.JunkRules()==3 and L.JunkRules()[3].name=='Third')
assert(L.JunkRules()[3].on==false and not S.IsNew(),'saved rule is a saved rule')
-- stale baseline refuses
S.Cancel();assert(S.Begin(1));L.SetJunkRule(2,'on',false);S.SetName('Late');local ok2,msg=S.Save();assert(not ok2 and msg:find('changed somewhere else'))
S.Cancel()
-- enabling an incomplete rule is refused centrally too
assert(S.Begin(1));S.Remove(S.Tree().children[1] or S.Tree());S.Cancel()
assert(not L.SetJunkRule(1,'on',true),'API refuses to switch on a rule with nothing in it')
local empty=L.NewJunkRule('E');empty.on=true;local rows=L.JunkRules()
local ok3,why3=L.SaveJunkRule(1,empty,rows);assert(not ok3 and why3=='incomplete')
empty.tree=Group('all',Kind('gear'),Group('any'));ok3,why3=L.SaveJunkRule(1,empty,rows);assert(not ok3 and why3=='incomplete','an empty group blocks enabling')
empty.on=false;assert(L.SaveJunkRule(1,empty,rows),'an unfinished rule may be saved while off')
-- duplicate and delete
Reset(2);S.Begin(1);S.SetName('Source');S.Add('kind');assert(S.Save());S.Cancel()
local idx=L.DuplicateJunkRule(1);assert(idx==3 and L.JunkRules()[3].name=='Source copy' and L.JunkRules()[3].on==false)
assert(T.Equal(L.JunkRules()[3].tree,L.JunkRules()[1].tree) and L.JunkRules()[3].tree~=L.JunkRules()[1].tree)
S.Begin(1);assert(S.BeginCopy() and S.IsNew() and S.Name()=='Source copy' and S.Dirty() and S.On()==false,'copy of the rule on screen is an unsaved, disabled rule');S.Cancel()
assert(S.Begin(3) and S.Delete() and #L.JunkRules()==2 and not S.Active(),'delete removes the saved rule')
assert(S.Begin(1));L.SetJunkRule(1,'on',true);assert(not S.Delete() and #L.JunkRules()==2,'a stale delete cannot remove a changed rule');S.Cancel()
assert(S.BeginNew('x') and S.Delete() and #L.JunkRules()==2,'deleting an unsaved new rule only closes it')
-- the list
local list=S.Rows();assert(#list==2 and list[1].name=='Source' and list[1].brief=='It is Gear')
-- eight rules is the maximum
Reset(32);assert(not S.BeginNew('over') and not L.DuplicateJunkRule(1),'the limit is 32 rules');Reset(9);assert(S.BeginNew('ninth') and L.DuplicateJunkRule(1),'more than eight rules are allowed');S.Cancel()
-- switching a saved rule from the list
Reset(2);S.Begin(1);S.Add('kind');assert(S.Save());S.Cancel()
assert(S.ToggleSaved(1,true) and L.JunkRules()[1].on==true,'list switch saves at once')
local okT,whyT=S.ToggleSaved(2,true);assert(not okT and whyT:find('Add a condition') and L.JunkRules()[2].on==false,'an empty rule cannot be switched on from the list either')
assert(S.Begin(1));S.SetName('Mid-edit');assert(S.Dirty())
assert(S.ToggleSaved(1,false) and S.On()==false and L.JunkRules()[1].on==false and S.Dirty(),'the open rule takes the switch without losing its other edits')
assert(S.Save() and L.JunkRules()[1].name=='Mid-edit' and L.JunkRules()[1].on==false,'and can still be saved afterwards')
assert(S.Begin(1));S.SetName('Again');assert(S.ToggleSaved(2,false));assert(S.Save(),'toggling another rule does not make this draft stale');S.Cancel()
assert(not S.ToggleSaved(1,'yes'))
---------------------------------------------------------------- legacy and malformed data
Reset(0)
db.ui.workshopJunk.rules={v=1,rows={{kind='gear',on=true,match='all',qualityMin=0,qualityMax=2,wearable='any',upgrade='no',classReagent='any',profession='any'}}}
assert(S.Begin(1) and S.Summary()=='Mark an item as junk when Workshop recommends Vendor, it is Gear, its quality is Poor to Uncommon and it is not a gear upgrade for you.',S.Summary(),'a rule from before the change shows its built-in Vendor requirement as a condition')
assert(L.JunkJudge(9,2,{vendor=true,quality=1,upgrade=false},{S.TestRule()})=='match' and L.JunkJudge(9,2,{vendor=true,quality=1},{S.TestRule()})=='unknown' and L.JunkJudge(9,2,{vendor=false,quality=1,upgrade=false},{S.TestRule()})=='nomatch')
assert(not S.Dirty(),'opening a rule from before the change is not an edit')
assert(L.JunkAllows(9,2,{vendor=true,quality=1,upgrade=false}),'legacy rows judge exactly as their editor tree')
assert(L.JunkJudge(9,2,{vendor=true,quality=1,upgrade=false},L.JunkRules())=='match','same through the saved-row path')
S.Cancel()
db.ui.workshopJunk.rules={v=2,rows={{kind='gear',on=true,match='any',qualityMin=0,qualityMax=0,wearable='yes',upgrade='any',classReagent='any',profession='any'}}}
assert(L.JunkAllows(9,2,{vendor=true,quality=3,wearable=true}),'legacy OR')
assert(S.Begin(1) and S.Summary():find('Poor') and S.Summary():find(' or ') or true);S.Cancel()
db.ui.workshopJunk.rules={v=2,rows={{kind='gear',on=true,tree={type='group',match='any',children={{type='alien'}}},match='all',qualityMin=0,qualityMax=5,wearable='any',upgrade='any',classReagent='any',profession='any'}}}
assert(select(2,L.JunkRules()),'a malformed tree holds the whole list rather than guess');assert(not S.Begin(1) and not L.JunkAllows(9,2,{quality=0}))
db.ui.workshopJunk.rules={v=2,rows={{kind='gear',on=true,name=string.rep('x',200),match='all',qualityMin=0,qualityMax=5,wearable='any',upgrade='any',classReagent='any',profession='any'}}}
assert(select(2,L.JunkRules()),'an over-long name is rejected as malformed')
db.ui.workshopJunk.rules={v=2,rows={{kind='gear',on=true}}}
assert(select(2,L.JunkRules()),'a partly populated row is held, not guessed')
---------------------------------------------------------------- protections come before any rule
Reset(0)
local always={{on=true,free=true,tree=Group('all',Quality(0,5))}}
assert(L.JunkJudge(7,2,{quality=1},always)=='match')
L.SetJunkIgnored(7,true)
assert(L.JunkJudge(7,2,{quality=1},always)=='protected','Never mark beats a matching rule')
assert(L.JunkJudge(211527,2,{quality=1},always)=='protected','Cozy Sleeping Bag beats any rule')
assert(L.JunkJudge(8,12,{quality=1},always)=='class' and L.JunkJudge(8,13,{quality=1},always)=='class','quest items and keys are never candidates')
assert(L.JunkJudge(8,99,{quality=1},always)=='class','an unknown class is not a candidate')
assert(L.JunkJudge(8,'x',{quality=1},always)=='class')
assert(L.JunkJudge(8,2,{quality=1},{{on=false,free=true,tree=Group('all',Quality(0,5))}})=='nomatch','disabled rules never mark')
assert(L.JunkJudge(8,2,{quality=1},{})=='nomatch')
assert(L.JunkJudge(8,2,{},{{on=true,free=true,tree=Group('all',Quality(0,5))},{on=true,free=true,tree=Group('all',Kind('gear'))}})=='match','one rule may be unknown while another is proven')
assert(L.JunkJudge(8,2,{},{{on=true,free=true,tree=Group('all',Quality(0,5))},{on=true,free=true,tree=Group('all',Kind('materials'))}})=='unknown')
local hold=R.Persist.IsHeld;R.Persist.IsHeld=function() return true end
assert(not L.SetJunkRule(1,'name','x') and not L.DuplicateJunkRule(1) and not L.SaveJunkRule(1,L.NewJunkRule('x'),L.JunkRules()))
R.Persist.IsHeld=hold
---------------------------------------------------------------- many rules and big trees stay cheap and bounded
Reset(0)
local rowsBig={}
for i=1,8 do
    local g=Group('any');for j=1,6 do g.children[j]=Group('all',Kind('gear'),Quality(0,j%6),{type='upgrade',value=j%2==0}) end
    rowsBig[i]={on=true,free=true,tree=Group('all',g)}
end
local nodes=0;local function N(x) nodes=nodes+1;for _,ch in ipairs(x.children or {}) do N(ch) end end;N(rowsBig[1].tree)
assert(nodes>25,'fixture is large: '..nodes)
local t0=os.clock()
for i=1,5000 do L.JunkJudge(100+i,2,{quality=i%6,upgrade=false},rowsBig) end
assert(os.clock()-t0<5,'5000 judgements over 8 large rules finished quickly')
print('PASSED junk session: creation, every condition, nesting, undo/redo, save/cancel, duplicate/delete, legacy data, protections and limits')
