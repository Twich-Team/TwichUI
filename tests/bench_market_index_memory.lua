-- Pure Lua 5.1 numeric item -> row-position table footprint, not a reader/cache fix.
require('bit')
TwichUI={Workshop={}}
dofile('TwichUI_Workshop/Data.lua');dofile('TwichUI_Workshop/BridgeCodec.lua')
local J=TwichUI.Workshop.BridgeCodec
local count=tonumber(arg[1]) or 32
assert(count>=1 and count<=10000 and count==math.floor(count))
local out=J.Object();out.mode='index';out.count=count;out.synthetic=true
local cpuStart=os.clock()
for _,capacity in ipairs({1,2,4,8,16,64})do
 collectgarbage('collect');collectgarbage('collect')
 local before=collectgarbage('count')*1024;local start=os.clock()
 local indexes={}
 for b=0,capacity-1 do
  local index={};indexes[b+1]=index
  for n=1,count do index[n*64+b]=n end
 end
 local us=math.floor((os.clock()-start)*1000000+.5)
 collectgarbage('collect');collectgarbage('collect')
 local bytes=math.floor(collectgarbage('count')*1024-before+.5)
 assert(indexes[capacity][count*64+capacity-1]==count and bytes>0)
 out['index'..capacity..'_bytes']=bytes;out['index'..capacity..'_build_us']=us
end
out.cpu_ms=math.floor((os.clock()-cpuStart)*1000+.5)
print(J.Encode(out))
