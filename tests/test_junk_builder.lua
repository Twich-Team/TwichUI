-- The rule builder window over the mock client: construction, rail, palette, cards, groups, drag, menus, history,
-- lifecycle and the item test. Pointer geometry and appearance are the simulator's and the game's to show.
dofile(TESTS.."harness.lua")
dofile(TESTS.."settings_mock.lua")
local c,S=SettingsClient({beforeInit=function(c)
    c.UISpecialFrames={}
    local chunk=assert(loadfile(ROOT.."WorkshopLauncher.lua"));setfenv(chunk,c);chunk()
end})
dofile(TESTS.."mi_mock.lua")
c.UIParent=MIFake("Frame");c.UIParent:SetSize(1600,1200)
c.CreateFrame=function(kind,_,parent)
    local frame=MIFake(kind,parent)
    frame.UnregisterAllEvents=function(self) self.events={} end
    if kind=='Frame' then frame.IsEnabled=nil end   -- the game's plain Frame has no IsEnabled
    frame.Click=function(self) if self:IsEnabled() and self:GetScript("OnClick") then self:GetScript("OnClick")(self) end end
    return frame
end
local R=c.TwichUI
local L,B,SS=R.WorkshopLauncher,R.JunkBuilder,R.JunkSession
local T=L.JunkTree
assert(B and SS and not R.WorkshopJunkRulesSettings,'the builder replaced the old editor')
local settings=c.CreateFrame("Frame",nil,c.UIParent);settings:Show()
R.SettingsUI.Frame=function() return settings end
R.SettingsUI.IsShown=function() return settings:IsShown() end
local workspace
R.SettingsUI.SetWorkspaceVisible=function(on) workspace=on end
local confirms={}
R.Interact.Confirm=function(key,text,accept,opts) confirms[#confirms+1]={key=key,text=text,accept=accept};return true end
local function Accept() local q=table.remove(confirms);assert(q,'a confirmation was asked');q.accept() end
local function Group(match,...) return {type='group',match=match,children={...}} end
local function Save(name,on,tree)
    local rule=L.NewJunkRule(name);rule.on=on;rule.tree=tree
    assert(L.SaveJunkRule(#L.JunkRules()+1,rule,L.JunkRules()))
end
while #L.JunkRules()>0 do L.RemoveJunkRule(1) end
local items={{id=100,name='Boots',class=4,quality=0,facts={quality=0,upgrade=false}},{id=200,name='Cloth',class=7,quality=1,facts={quality=1}}}
c.NUM_TOTAL_EQUIPPED_BAG_SLOTS=0

---------------------------------------------------------------- empty state, then the first rule
assert(B.Open(),'opens with no rules')
local f=B.Frame()
assert(B.Shown() and workspace==true,'the settings window is moved behind the workspace')
assert(not SS.Active() and f.rule.blank:IsShown(),'no rules: the empty state explains how to start')
assert(not f.search:IsEnabled(),'nothing to add to yet')
assert(f.save and not f.save:IsEnabled() and not f.cancel:IsEnabled() and not f.undo:IsEnabled())
B.New()
assert(SS.Active() and SS.IsNew() and #L.JunkRules()==0,'a new rule is a draft, not a saved rule')
assert(not f.rule.blank:IsShown() and f.rule.name:IsShown())
assert(B.Snapshot().groups>=1)
assert(f.rule.templates and f.rule.templates.buttons[1]:IsShown(),'an empty rule offers examples')
assert(f.palette.where:GetText()=='Adding to: Top level','the next condition goes to the top level')

---------------------------------------------------------------- palette: click adds to the chosen group; search and category filter
local function Visible() local out={} for i=1,14 do local row=B.PaletteRow(i);if row:IsShown() then out[#out+1]=row.key end end return out end
assert(#Visible()==14,'every supported condition is offered: '..#Visible())
local want={kind=1,armor=1,quality=1,tool=1,camping=1,wearable=1,upgrade=1,unlearnedRecipe=1,classReagent=1,profession=1,professionMaterial=1,vendor=1,all=1,any=1}
for _,k in ipairs(Visible()) do assert(want[k],'only supported conditions: '..k);want[k]=nil end
assert(next(want)==nil)
f.search:SetText('qual');f.search:GetScript('OnTextChanged')(f.search,true)
assert(#Visible()==1 and Visible()[1]=='quality','search filters the catalog')
f.search:SetText('');f.search:GetScript('OnTextChanged')(f.search,true)
f.category.onPick('Groups')
assert(#Visible()==2,'category filter');f.category.onPick('all');assert(#Visible()==14)
local row=B.PaletteRow(1);assert(row.key=='kind')
row:Click()
assert(#SS.Tree().children==1 and SS.Tree().children[1].type=='kind','clicking a condition adds it to the draft')
assert(#L.JunkRules()==0,'nothing saved yet')
assert(f.save:IsEnabled() and f.cancel:IsEnabled() and f.undo:IsEnabled() and f.dirty:GetText()=='Unsaved changes')
assert(not f.rule.templates.buttons[1]:IsShown(),'examples go away once there is a condition')
B.PaletteRow(3):Click()
assert(SS.Summary()=='Mark an item as junk when it is Gear and its quality is Poor to Common.')
assert(f.rule.delete:IsShown(),'Delete is a visible button, not only a menu entry')
f.undo:Click();assert(#SS.Tree().children==1);f.redo:Click();assert(#SS.Tree().children==2)

---------------------------------------------------------------- cards: one per condition, editable, with working controls
local function Cards() local out={} for _,card in ipairs(B.cards()) do if card:IsShown() then out[#out+1]=card end end return out end
assert(#Cards()==2)
local kind,quality=Cards()[1],Cards()[2]
kind.value.onPick('materials');assert(SS.Tree().children[1].value=='materials')
quality.from.onPick(2);assert(SS.Tree().children[2].min==2 and SS.Tree().children[2].max==2 or SS.Tree().children[2].max>=2,'from moves the range')
quality.to.onPick(4);assert(SS.Tree().children[2].max==4)
assert(SS.Summary():find('Materials') and SS.Summary():find('Uncommon to Epic'))

---------------------------------------------------------------- groups: add, operator, nesting by click and by drag
B.PaletteRow(14):Click()  -- any group, becomes the target
local any=SS.Target();assert(any~=SS.Tree() and any.match=='any' and f.palette.where:GetText():find('Group 1'),'a new group is where the next condition goes')
B.PaletteRow(3):Click();B.PaletteRow(3):Click()
assert(#any.children==2)
local box=B.groups()[2];assert(box.node==any and box.any and box.all)
box.all:Click();assert(any.match=='all','operator segment changes the group');box.any:Click();assert(any.match=='any')
-- another group's add button chooses it
B.groups()[1].add:Click();assert(SS.Target()==SS.Tree(),"a group's add button chooses that group")
box.add:Click();assert(SS.Target()==any)
-- a menu moves, duplicates and removes
local card=B.cards()[3]
local menu=card.more.choices()
local values={} for _,m in ipairs(menu) do values[m.value]=m end
assert(values.dup and values.remove and values.to1 and (values.up or values.down),'the More menu offers every click-based move')
assert(not values.up and values.down,'the first child cannot move up')
local moved=card.node;card.more.onPick('down');assert(any.children[2]==moved,'Move down')
moved=card.node;card.more.onPick('up');assert(any.children[1]==moved or any.children[1]~=nil,'Move up')
local target=B.cards()[3].node;B.cards()[3].more.onPick('to1')
assert(#any.children==1 and #SS.Tree().children==4 and T.Find(SS.Tree(),target)==SS.Tree(),'Move into another group')
B.Do(SS.Move(target,any,1));assert(#any.children==2)

---------------------------------------------------------------- drag: the shared virtual drag drops palette entries and cards where the pointer is
local drag=B.drag
local dragRow=B.PaletteRow(1)
local before=#any.children
drag.Find=function() return {target={parent=any,frame=B.groups()[2].box,depth=1},index=#any.children+1} end
drag.Paint=function() end
c.GetCursorPosition=function() return 100,100 end
dragRow:GetScript('OnDragStart')()
assert(R.MagicInventoryPage.Drag.Active(),'a palette entry starts the shared virtual drag')
dragRow:GetScript('OnDragStop')()
assert(#any.children==before+1 and any.children[#any.children].type=='kind','dropping adds at the highlighted place')
local grip=B.cards()[1].grip;local moving=B.cards()[1].node
drag.Find=function() return {target={parent=any,frame=B.groups()[2].box,depth=1},index=#any.children+1} end
grip:GetScript('OnDragStart')();grip:GetScript('OnDragStop')()
assert(T.Contains(any,moving),'dragging a card into a group moves that card')

---------------------------------------------------------------- save, enable, validation
local before=#L.JunkRules()
f.rule.name:SetText('Mixed rule');f.rule.name:GetScript('OnEnterPressed')(f.rule.name)
assert(SS.Name()=='Mixed rule')
f.save:Click()
assert(#L.JunkRules()==before+1 and L.JunkRules()[#L.JunkRules()].name=='Mixed rule','Save stores the rule once')
assert(not f.save:IsEnabled() and f.dirty:GetText()=='No unsaved changes')
assert(f.title:GetText()=='Junk rule: Mixed rule')

---------------------------------------------------------------- rail: select, switch with unsaved changes, cancel, delete
Save('Second',true,Group('all',{type='kind',value='gear'}))
B.Refresh()
local first=B.Row(1);assert(first:IsShown() and first.index==1,'the rail lists saved rules')
B.Select(2);assert(SS.Index()==2 and SS.Name()=='Second','selecting opens that rule')
SS.Add('quality');B.Refresh();assert(SS.Dirty())
B.Select(1);assert(#confirms==1 and SS.Index()==2,'unsaved changes are asked about before switching')
Accept();assert(SS.Index()==1 and not SS.Dirty(),'discarding switches')
SS.Add('quality');B.Refresh();f.cancel:Click();assert(not SS.Dirty() and #SS.Tree().children==#L.JunkRules()[1].tree.children,'Cancel restores the saved rule')
-- the rail's own switch changes the saved rule at once
local pill=B.Row(2).pill;assert(pill:IsShown() and L.JunkRules()[2].on==true)
B.ToggleRow(2,false);assert(L.JunkRules()[2].on==false and not SS.Dirty() and B.Row(2).pill:GetChecked()==false,'row switch saves at once and is not a draft edit')
B.ToggleRow(2,true)
-- the open rule's row says when it has unsaved edits
SS.Select=nil;SS.Add('quality');B.Refresh();assert(B.Row(1).brief:GetText()=='Unsaved changes','the open rule is marked in the list');f.cancel:Click()
-- duplicate: a disabled unsaved copy; Save adds it
B.Duplicate();assert(SS.IsNew() and SS.Name()=='Mixed rule copy' and SS.On()==false and #L.JunkRules()==2)
f.save:Click();assert(#L.JunkRules()==3)
-- delete confirms, removes only that rule
f.rule.delete:Click();assert(#confirms==1 and #L.JunkRules()==3,'delete asks first');Accept();assert(#L.JunkRules()==2 and SS.Active() and not SS.IsNew())
-- close with unsaved changes asks; Escape path
SS.Add('quality');B.RequestClose();assert(#confirms==1 and B.Shown());Accept();assert(not B.Shown() and not SS.Active() and workspace==false)

---------------------------------------------------------------- the item test
R.Workshop={Junk={Start=function() end,
    Find=function(id) for i,x in ipairs(items) do if x.id==id then return {bag=0,slot=i} end end end,
    Inspect=function(bag,slot,rule)
        local x=items[slot];if not x then return {state='empty'} end
        local trace={}
        local v=L.JunkJudge(x.id,x.class,x.facts,{rule},trace)
        return {state='ok',item={id=x.id,name=x.name,icon=1,count=1},verdict=v,trace=trace,vendor=true,advice='vendor',reserved=0,wanted=true,marker='markable',why=L.JunkIgnored(x.id) and 'never' or nil}
    end,
    Survey=function(rule,done) done({items=2,match=1,protected=0,unknown=0,blocked=0,names={'Boots'}}) end}}
B.Open(1)
SS.Cancel();SS.Begin(2);B.Refresh()
B.TestSlot(0,1)
local strip=f.strip
assert(strip.itemName:GetText()=='Boots' and strip.result:GetText()=='Matches this rule',strip.result:GetText())
assert(strip.reason:GetText():find('marked'))
assert(next(L.JunkIgnoreList())==nil and not R.Workshop.junkMarked,'testing changes nothing')
-- the cards show what each condition said
local rule2=SS.Tree();SS.Add('upgrade',rule2);B.Refresh()
local noted=0 for _,card in ipairs(Cards()) do if card.note:IsShown() then noted=noted+1 end end
assert(noted>=2,'cards report Met / Not met')
-- an edit re-tests the same item against the draft
SS.Set(rule2.children[1],'value','materials');B.Refresh()
assert(strip.result:GetText()=='Does not match' and strip.reason:GetText():find('Not met'),strip.reason:GetText())
B.TestSlot(0,2);assert(strip.result:GetText()=='Cannot determine','cloth: kind is met but upgrade is unknown for non-gear')
-- protected and unknown
assert(L.SetJunkIgnored(100,true));B.TestSlot(0,1);assert(strip.result:GetText():find('Protected'),strip.result:GetText());assert(strip.reason:GetText():find('Never mark'))
L.SetJunkIgnored(100,false)
items[1].facts={quality=0};SS.Set(rule2.children[1],'value','gear');B.TestSlot(0,1)
assert(strip.result:GetText()=='Cannot determine' and strip.reason:GetText():find("Can't tell"),strip.reason:GetText())
-- cursor drop
local cursor={'item',100,'item:100'};local cleared
c.GetCursorInfo=function() return cursor[1],cursor[2],cursor[3] end
c.ClearCursor=function() cleared=true end
assert(B.TakeCursor() and cleared,'a dropped item is tested and returned');cursor={'spell',1};assert(not B.TakeCursor())
-- bags changing under the open window: one coalesced re-test, and the tested item is followed by its ID
local timers={};c.C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
local root=B.Root();assert(root:GetScript('OnEvent'))
items[1],items[2]=items[2],items[1]      -- the bag was rearranged: the chosen item (id 100) is now in slot 2
root:GetScript('OnEvent')(root,'BAG_UPDATE_DELAYED');root:GetScript('OnEvent')(root,'GET_ITEM_INFO_RECEIVED')
assert(#timers==1,'a burst of bag events schedules one look')
B.TestSlot(0,2);local seen=strip.itemName:GetText()
local first=table.remove(timers);first()
assert(strip.itemName:GetText()==seen,'the same item is still the one tested')
items[1],items[2]=items[2],items[1]
table.remove(items,1);table.remove(items,1)     -- both gone
root:GetScript('OnEvent')(root,'BAG_UPDATE_DELAYED');table.remove(timers)()
assert(strip.result:GetText():find('no longer in your bags'),'an item that left the bags is said to have left')
items[1]={id=100,name='Boots',class=4,quality=0,facts={quality=0,upgrade=false}};items[2]={id=200,name='Cloth',class=7,quality=1,facts={quality=1}}
-- survey
B.Survey();assert(strip.surveyText:GetText():find('1 of 2 bag items match'),strip.surveyText:GetText())
-- Workshop absent: honest message
R.Workshop=nil;B.TestSlot(0,1);assert(strip.result:GetText():find('unavailable') and strip.reason:GetText():find('Item Advisor'))

---------------------------------------------------------------- big rules stay bounded
SS.Cancel();B.Close()
while #L.JunkRules()>0 do L.RemoveJunkRule(1) end
local big=Group('all')
for i=1,3 do
    local g=Group('any');for j=1,8 do g.children[j]={type='quality',min=j%6,max=5} end
    big.children[i]=g
end
big.children[4]={type='kind',value='gear'}
for i=1,8 do Save('Rule '..i,i%2==0,big) end
assert(#L.JunkRules()==8)
local started=os.clock()
B.Open(8)
for i=1,20 do B.Refresh() end
assert(os.clock()-started<3,'redrawing a 32-node rule is cheap')
local shownCards=0 for _,card in ipairs(Cards()) do shownCards=shownCards+1 end
assert(shownCards==25 and B.Snapshot().cards==25 and B.Snapshot().groups==4,'one card per leaf, one box per group: '..shownCards)
local poolsBefore=B.Snapshot();for i=1,10 do B.Refresh() end
local poolsAfter=B.Snapshot();assert(poolsBefore.cards==poolsAfter.cards and poolsBefore.groups==poolsAfter.groups and poolsBefore.rows==poolsAfter.rows,'redraws reuse frames')
assert(B.Row(8):IsShown() and B.Snapshot().rows==8,'eight rail rows for eight rules')
assert(SS.BeginNew('ninth'),'more than eight rules are allowed');SS.Cancel()
SS.Cancel();B.Select(1)
local addMore=0 for i=1,40 do if select(1,SS.Add('kind',SS.Tree())) then addMore=addMore+1 end end
assert(addMore==3,'a rule stops at 32 nodes: '..addMore)
SS.Cancel();SS.Begin(1);B.Refresh()

---------------------------------------------------------------- Escape: the picker, then the builder, never the settings window first
local esc=c.TwichUISettingsEsc
B.Select(2);B.TogglePicker();assert(f.picker:IsShown())
assert(esc:IsShown());esc:Hide();assert(not f.picker:IsShown() and B.Shown(),'first Escape closes the item picker')
esc:Hide();assert(not B.Shown() and settings:IsShown(),'second Escape closes the builder and leaves settings')
B.Open();SS.Add('quality');B.Refresh()
esc:Hide();assert(B.Shown() and #confirms==1,'Escape with unsaved changes asks first');table.remove(confirms)
SS.Cancel();B.Close()

---------------------------------------------------------------- lifecycle
SS.Cancel();B.Close();assert(not B.Shown() and not B.Frame():IsShown())
B.Open();assert(B.Shown())
assert(B.CancelDrag()==false)
local snap=B.Snapshot();assert(snap.cards<=32 and snap.groups<=32,'pools stay inside the tree limit')
print('PASSED junk builder: empty state, palette, cards, groups, menus, drag, save/cancel/duplicate/delete, rail guard and item test')
