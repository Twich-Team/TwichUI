-- Production table/evaluator, independent integer arithmetic and native-context adapter.
local c=dofile(TESTS..'auction_mock.lua')
local W=c.TwichUI.Workshop
local DE,D=W.Disenchant,W.DisenchantData
local now=1000000
c.time=function()return now end
local f={item=100,quality=2,classID=4,equipLoc='INVTYPE_CHEST',itemLevel=5,actualLevel=true,canDisenchant=true,enchantSkill=1}
local priceMode,calls='normal',0
local function value(id)return (id%43+1)*7 end
W.Pricing.Price=function(id)
 calls=calls+1
 if priceMode=='missing' and id==10938 then return nil,'unlisted' end
 if priceMode=='loading' and id==10938 then return nil,'loading' end
 return {price=value(id),at=priceMode=='old' and now-86401 or priceMode=='future' and now+1 or now,reference=priceMode~='local'}
end
local function copy(t)local o={};for k,v in pairs(t)do o[k]=v end;return o end
local function estimate(changes)
 local input=copy(f);for k,v in pairs(changes or {})do input[k]=v end
 return DE.ForItem(input,{now=now})
end
local function expected(row)
 local numerator=0
 for i=3,#row do
  -- Independent denominator 200: percent / 100 times midpoint / 2.
  local x=row[i];numerator=numerator+x[1]*(x[2]+x[3])*value(x[4])
 end
 return math.floor(numerator/200)
end
local result=estimate()
assert(result.state=='ok' and result.expectedGross==expected(D.Find(4,2,5)))
assert(result.value==195,'armor: floor(0.8*1.5*133 + 0.2*1.5*119)')
assert(estimate({classID=2}).value==182,'weapon: floor(0.8*1.5*119 + 0.2*1.5*133)')
assert(result.value==result.expectedGross and result.outcomeReference and result.quality=='limited')
assert(result.priceSource=='market_server' and #result.materials==2)
assert(result.outcomes:find('Strange Dust',1,true) and result.source:find('Classic',1,true))
assert(not result.why:find('Classic',1,true))
assert(estimate({classID=2}).expectedGross==expected(D.Find(2,2,5)),'weapon/armor yields differ')
-- Every captured client bracket, at both boundaries; no cross-bracket guessing.
local csv=assert(io.open(TESTS..'fixtures/disenchant_forever/brackets.csv'))
local n,unsupported=0,0
for line in csv:lines()do
 local class,quality,lo,hi=line:match('^(%d+),(%d+),(%d+),(%d+)$')
 if class then
  class,quality,lo,hi=tonumber(class),tonumber(quality),tonumber(lo),tonumber(hi)
  for _,level in ipairs({lo,hi})do
   local row=D.Find(class,quality,level)
   assert(row and row[1]==lo and row[2]==hi,'runtime bracket differs from pinned client data')
   local r=estimate({classID=class,quality=quality,itemLevel=level})
   if row.unconfirmed then assert(r.state=='unknown' and not r.value);unsupported=unsupported+1
   else assert(r.state=='ok' and r.value==expected(row),'independent yield arithmetic');n=n+1 end
  end
 end
end
csv:close();assert(n==104 and unsupported==4,'all 54 captured client brackets must be considered')
for seed=1,96 do
 f.itemLevel=5+(seed*13)%95;f.classID=seed%2==0 and 4 or 2;f.quality=2
 local row=D.Find(f.classID,2,f.itemLevel)
 assert(estimate().expectedGross==expected(row),'deterministic seeded yields')
end
f.itemLevel,f.classID=5,4
assert(estimate({itemLevel=4}).state=='unknown')
assert(estimate({quality=3,itemLevel=5}).state=='unknown','unconfirmed low rare bracket is not priced')
assert(estimate({itemLevel=100}).state=='unknown')
assert(estimate({quality=1}).state=='unavailable')
assert(estimate({equipLoc='INVTYPE_BODY'}).state=='unavailable')
assert(estimate({equipLoc='INVTYPE_TABARD'}).state=='unavailable')
assert(estimate({item=11287,classID=2}).state=='unavailable','known nondisenchantable wand')
assert(estimate({item=242266}).state=='unknown','special rewards do not use ordinary materials')
assert(estimate({variant='suffix',actualLevel=false}).state=='unknown')
assert(estimate({variant='suffix',actualLevel=true}).state=='ok','actual level allows a yield estimate without pricing its variant')
assert(estimate({canDisenchant=false}).state=='unavailable')
assert(estimate({item=0}).state=='unknown')
for _,mode in ipairs({'missing','loading','old','future'})do
 priceMode=mode;local r=estimate()
 assert(r.state=='unknown' and not r.value and not r.expectedGross,'missing/stale material cannot be zero or a partial total')
 assert(r.outcomes and r.outcomeReference,'material breakdown can exist without a price')
 if mode=='loading' then assert(r.pending)end
end
priceMode='local';assert(estimate().priceSource=='local','local fallback is usable')
priceMode='normal'
-- No unsigned caller can label its own table as the bundled reference.
local spoof={reference={},verified=false,client='forever',item=100,eligible=true,source='unverified',outcomes={{p=1,materials={{item=10940,qty=100}}}},values={[10940]={value=100,quality='good'}}}
assert(DE.Evaluate(f,spoof).state=='unknown')
-- Character reads preserve a definite false and use the numeric profession ID.
c.C_SpellBook={ContainsAnyDisenchantSpell=function()return false end}
c.GetProfessions=function()return 1 end
c.GetProfessionInfo=function()return 'localized',nil,75,300,nil,nil,333 end
assert(DE.Character().canDisenchant==false and DE.Character().enchantSkill==75)
c.C_SpellBook=nil;assert(DE.Character().canDisenchant==true)
c.GetProfessionInfo=function()return 'localized',nil,75,300,nil,nil,171 end
assert(DE.Character().canDisenchant==false)
c.GetProfessions=nil;c.GetProfessionInfo=nil;assert(DE.Character().canDisenchant==nil)
local layout={enabled=true,lines={{id='disenchant',when='always'},{id='outcomes',when='shift'}}}
local r={disenchant=result,vendor={state='ok',value=1},auction={state='unavailable'}}
local rec=W.Worth.Recommend(r)
assert(rec.kind=='possible' and not rec.pick and not rec.text:find('Classic',1,true),'direct worth comparison promoted a reference into a proven winner')
local originalVendor=r.vendor.value;r.vendor.value=result.value*2
assert(W.Worth.Recommend(r).kind=='possible','a vendor comparison is also qualified when DE uses a reference')
r.vendor.value=originalVendor
local lines=W.WorthLayout.Lines(r,{money=tostring},layout,false)
assert(lines[1][1]=='Disenchant (average)' and lines[1][2]==tostring(result.value))
assert(W.WorthLayout.UsesDisenchant(layout,false))
assert(not W.WorthLayout.UsesDisenchant({lines={{id='vendor',when='always'}}},false))
-- One configured field expands to a right-column list, one icon per material.
result.outcomes='fixture';result.yields={{item=11137,min=1,max=2,chance=75},{item=11135,min=1,max=2,chance=20},{item=11139,min=1,max=1,chance=5}}
local yieldLayout={enabled=true,lines={{id='outcomes',when='always'}}}
local yieldContext={money=tostring,itemIcon=function(id)return id+9000 end}
local list=W.WorthLayout.Lines(r,yieldContext,yieldLayout,false)
assert(#list==4 and list[2][1]=='Disenchant yields')
-- Native tooltip row height comes from the left text: empty continuation
-- strings collapse the right-hand material list onto the same baseline.
assert(list[3][1]==' ' and list[4][1]==' ','yield continuation rows must reserve native tooltip height')
for i,m in ipairs(result.yields) do
 assert(list[i+1][2]:find('|T'..(m.item+9000)..':14:14:0:0|t',1,true),'material icon missing')
 assert(not list[i+1][2]:find('\n',1,true) and not list[i+1][2]:find(';',1,true),'materials share a horizontal line')
end
assert(list[2][2]:find('Vision Dust',1,true) and list[2][2]:find('1–2 (75%)',1,true))
local preview=W.WorthLayout.Rows(r,yieldContext,yieldLayout,false)
local _,breaks=preview.rows[1].line[2]:gsub('\n','')
assert(breaks==2,'designer must retain the same vertical material list')
print('PASSED all client brackets, independent expected-value model, exclusions, missing/fresh prices, character context and shared layout')
