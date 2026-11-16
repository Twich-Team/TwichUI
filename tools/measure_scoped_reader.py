#!/usr/bin/env python3
"""Targeted synthetic production-reader measurements, not Forever frame-time acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]

def startup():
    baseline='5133a43477237bf7cd97a429a680a751a9533f7c'
    files=('Data','BridgeCodec','BridgeSchema','BridgeValidate','Bridge','ServerMarket')
    result={'evidence':'offline Lua module startup without bridge data; not full Workshop/game startup','baseline_revision':baseline}
    with tempfile.TemporaryDirectory(prefix='l3-startup-') as d:
        old=Path(d)/'baseline';old.mkdir()
        for n in files:
            (old/(n+'.lua')).write_bytes(subprocess.check_output(['git','show',baseline+':TwichUI_Workshop/'+n+'.lua'],cwd=ROOT))
        for label,path in [('baseline',old),('l3',ROOT/'TwichUI_Workshop')]:
            samples=[]
            for _ in range(3):
                script="""require('bit');TwichUI={Workshop={}};TwichUIDB={keep='profile'};TwichUIWorkshopDB={keep='local'}
local calls=0;C_AddOns={LoadAddOn=function()calls=calls+1 end};C_Timer={After=function()calls=calls+1 end};ReloadUI=function()calls=calls+1 end
collectgarbage('collect');local base=collectgarbage('count');local compile,init=0,0
"""
                for n in files:
                    script+='do local at=os.clock();local fn=assert(loadfile('+json.dumps(str(path/(n+'.lua')))+'));compile=compile+os.clock()-at;at=os.clock();fn();init=init+os.clock()-at end\n'
                script+="""collectgarbage('collect');local B=TwichUI.Workshop.Bridge
assert(not B.Status().ready and not B.Status().loading and B.Status().cache_entries==0 and calls==0 and TwichUIMarketData==nil)
assert(TwichUIDB.keep=='profile' and TwichUIWorkshopDB.keep=='local')
print(math.floor(compile*1e6+.5)..' '..math.floor(init*1e6+.5)..' '..math.floor((collectgarbage('count')-base)*1024+.5))
"""
                proc=subprocess.run(['lua5.1','-'],input=script,text=True,capture_output=True,check=True,timeout=30)
                samples.append(dict(zip(('compile_us','initialize_us','retained_bytes'),map(int,proc.stdout.split()))))
            result[label]={'samples':samples,'metrics':{k:{'median':statistics.median(x[k] for x in samples),'worst':max(x[k] for x in samples)} for k in samples[0]}}
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--market-root',type=Path)
    p.add_argument('--startup-only',action='store_true',help='compare unloaded reader modules against the pinned development base')
    p.add_argument('--report',type=Path,required=True)
    p.add_argument('--case',type=int,help='one variant count from the documented cases, for targeted diagnosis')
    a=p.parse_args()
    if a.startup_only:
        report=startup()
        a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));return
    if not a.market_root:p.error('--market-root is required for scoped workload generation')
    sys.path[:0]=[str(a.market_root/'contracts/bridge/scoped-l1'),str(a.market_root/'scripts'),str(ROOT/'tests')]
    import reference as ref
    from build_fixtures import request_for,SESSION
    from bridge_workloads import generate
    from test_workshop_bridge import lua
    rows=[]
    with tempfile.TemporaryDirectory(prefix='l3-reader-bench-') as d:
        temp=Path(d)
        for count,profile in [(10,'sixty'),(100,'sparse-sixty'),(100,'sixty'),(155,'sixty'),(166,'sixty')]:
            if a.case and a.case!=count: continue
            source,_=generate(count,profile)
            g=ref.project(source,request_for(source),SESSION,SESSION,budget={})
            receipt=ref.receipt(g)
            artifact=ref.lua_source(g,receipt).replace(b'TwichUIMarketDataL1 =',b'TwichUIMarketData =',1)
            path=temp/'Data.lua';path.write_bytes(artifact)
            samples=[]
            for sample in range(3):
                code=['require("bit")','TwichUI={Workshop={}}','TwichUIDB={keep="profile"};TwichUIWorkshopDB={keep="local"}',
                      'GetTimePreciseSec=function()return os.clock()end']
                for name in ('Data','BridgeCodec','BridgeSchema','BridgeValidate','Bridge'):
                    code.append('dofile('+lua(str(ROOT/'TwichUI_Workshop'/(name+'.lua')))+')')
                code+=['local J,B=TwichUI.Workshop.BridgeCodec,TwichUI.Workshop.Bridge',
                       'collectgarbage("collect");local base=collectgarbage("count")*1024',
                       'local started=os.clock();local assign=assert(loadfile('+lua(str(path))+'));local compile=(os.clock()-started)*1e6',
                       'started=os.clock();assign();local assignment=(os.clock()-started)*1e6;assign=nil',
                       'local function finish()for i=1,1000000 do local ok,why=B.Step();if why~="loading" then return ok,why end end error("validation deadline")end',
                       'started=os.clock();B.Begin(TwichUIMarketData);local ok,why=finish();local validation=(os.clock()-started)*1e6',
                       'local out=J.Object();out.compile_us=math.floor(compile+.5);out.assignment_us=math.floor(assignment+.5);out.validation_us=math.floor(validation+.5)',
                       'out.accepted=ok;out.worst_slice_us=math.floor(B.Status().largest_slice_ms*1000+.5);out.slices=B.Status().slices',
                       'collectgarbage("collect");out.retained_bytes=math.floor(collectgarbage("count")*1024-base+.5)',
                       'if ok then local item=10001;local key=B.Variants(item)[1]',
                       'started=os.clock();local r=B.Record(item,key);out.first_record_us=math.floor((os.clock()-started)*1e6+.5)',
                       'started=os.clock();local h=B.History(item,key,"recent");out.history_us=math.floor((os.clock()-started)*1e6+.5)',
                       'assert(r.current.metrics.recent_copper=="100");assert(#h.points=='+str(4 if profile=='sparse-sixty' else 60)+')',
                       'B.EachItem(function(id)for _,v in ipairs(B.Variants(id))do B.Record(id,v)end end)',
                       'collectgarbage("collect");out.warm_retained_bytes=math.floor(collectgarbage("count")*1024-base+.5);out.cache_entries=B.Status().cache_entries',
                       'local previous=B.Status().generation;local raw=TwichUIMarketData;local bad={transport_version=1,manifest=raw.manifest,records={},receipt=raw.receipt};for i,text in ipairs(raw.records)do bad.records[i]=text end;bad.records[1]=bad.records[1].." "',
                       'B.Begin(bad);local rejected=finish();assert(not rejected and B.Status().generation==previous)',
                       'out.corrupt_retained=true end',
                       'assert(TwichUIDB.keep=="profile" and TwichUIWorkshopDB.keep=="local")','print(J.Encode(out))']
                script=temp/'bench.lua';script.write_text('\n'.join(code)+'\n')
                run=subprocess.run(['lua5.1',str(script)],capture_output=True,text=True,timeout=180)
                if run.returncode:raise RuntimeError(run.stdout+run.stderr)
                result=json.loads(run.stdout);assert result['accepted']==(count!=166),(count,profile,len(ref.canonical(g)),result)
                samples.append(result)
            metrics={key:{'median':statistics.median(s[key] for s in samples),'worst':max(s[key] for s in samples)}
                     for key,value in samples[0].items() if isinstance(value,int) and not isinstance(value,bool)}
            rows.append(dict(variants=count,profile=profile,canonical_bytes=len(ref.canonical(g)),lua_bytes=len(artifact),manifest_bytes=ref.sizes(g,receipt)['manifest_bytes'],
                             accepted=count!=166,samples=samples,metrics=metrics))
    report=dict(origin='synthetic',runtime='offline Lua 5.1 with global GC enabled; CPU clock, not installed Forever frames',samples_per_case=3,
                budgets=dict(canonical_bytes=2*1024**2,lua_bytes=3*1024**2,default_variants=100,contract_variants=1000),cases=rows,
                source_sha256={str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in [ROOT/'TwichUI_Workshop'/n for n in ('Bridge.lua','BridgeCodec.lua','BridgeValidate.lua','BridgeSchema.lua')]})
    a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
