"""Fast safety/correctness guards for opt-in experiment code, not a new format gate."""
import copy
import importlib.util
import json
import hashlib
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('game_ready',ROOT/'tools/experiments/market_game_ready.py')
G=importlib.util.module_from_spec(spec);spec.loader.exec_module(G)
sys.path.insert(0,str(ROOT/'tools/experiments'))
from market_fixed_records import encode_rows
from measure_game_ready import numeric_metrics


def fixture(root,representation,count=16,delta=0,epoch=0,state=None):
    f=json.loads((ROOT/'tests/fixtures/workshop_summary_v3/synthetic.json').read_text())
    rich=json.loads(f['parts']['93']);rich[0][3]=str(int(rich[0][3])+delta)
    if state is not None and state!=0:
        r=rich[0];r[2]=state;r[8]=1;r[6]=5 if state==1 else 0 if state==2 else None
        for i in (3,4,5,9):r[i]=None
        r[10]=r[11]=0
        r[13]=[[state,None,None,r[6]]for _ in r[13]]
    current=[r[:13]for r in rich];h=f['manifest']
    for projection,rows in [('current',current),('history',rich)]:
        raw=G.canonical(rows);h['partitions'if projection=='current'else'history_partitions']=[dict(bucket=29,bytes=len(raw),record_count=len(rows),sha256=G.sha(raw))]
    h['source_watermark']=str(int(h['source_watermark'])+epoch)
    h.pop('generation_id');h['generation_id']=G.sha(G.canonical(h))
    layouts=[]
    for projection,rows in [('current',current),('history',rich)]:
        actual=representation;partitions=count
        if representation.startswith('fixed-')and projection=='history':actual='json';partitions=64
        folder=root/f'{actual}-{projection}-{partitions}';folder.mkdir(parents=True)
        descriptors=[]
        for b in range(partitions):
            group=[r for r in rows if r[0]%partitions==b];data=G.source(group,actual,h['generation_id'],b,partitions)
            (folder/f'{b:02}.lua').write_bytes(data)
            d=dict(bucket=b,bytes=len(G.canonical(group)),sha256=G.sha(G.canonical(group)),record_count=len(group),source_bytes=len(data))
            if actual in ('proof','hybrid','packed-proof','packed-hybrid','fixed-proof','fixed-hybrid'):d['merkle_root']=G.tree(group,h['generation_id'],representation.startswith(('packed-','fixed-')))[0]
            descriptors.append(d)
        layouts.append(dict(projection=projection,representation=actual,count=partitions,descriptors=descriptors,max_source_bytes=max(d['source_bytes']for d in descriptors)))
    (root/'fixture.json').write_bytes(G.canonical(dict(manifest=h,layouts=layouts,semantic_sha256=G.sha(G.canonical(rich)),records=len(rich),profile='unit',history_days=2)))
    config=root/'config.json';config.write_text(json.dumps(dict(root=str(root),representation=representation,count=count,history_count=count)))
    return config,rich[0][1]


@unittest.skipUnless(shutil.which('lua5.1'),'Lua 5.1 required')
class GameReady(unittest.TestCase):
    def test_sparse_operation_counts_do_not_invent_timings(self):
        result=numeric_metrics([{'engine_partialReuses':1,'cpu_ms':2,'optional_ms':1},{'cpu_ms':4}])
        self.assertEqual(result['engine_partialReuses'],dict(median=.5,minimum=0,maximum=1))
        self.assertEqual(result['cpu_ms']['median'],3)
        self.assertNotIn('optional_ms',result)

    def lua(self,config,body,key):
        init="require('bit');ROOT='../!!!TwichUI/';REPO='../';TESTS='./';local c=dofile(TESTS..'auction_mock.lua');local W=c.TwichUI.Workshop;local pending={};c.C_Timer.After=function(_,fn)pending[#pending+1]=fn end;c.GetTimePreciseSec=os.clock;arg={};arg[12]="+json.dumps(str(config))+";local X=dofile(TESTS..'bench_market_game_ready.lua');local h,input=X.setup(c);W.Bridge.Begin(input);local key="+json.dumps(key)+";local function tick()local batch=pending;pending={};for _,fn in ipairs(batch)do fn()end end;local function drain()for i=1,1000 do if #pending==0 then return end;tick()end;error('retry loop')end;"
        p=subprocess.run(['lua5.1','-e',init+'drain();'+body],cwd=ROOT/'tests',text=True,capture_output=True,timeout=15)
        return p

    def test_atoms_reject_source_injection_and_unsafe_literals(self):
        for bad in ['";_G.bad=true;--','os.execute("bad")','return 1','\\000','',True,-1,1.5,9007199254740992,{},b'bad']:
            with self.subTest(value=repr(bad)),self.assertRaises(ValueError):G.literal(bad)
        self.assertEqual(G.literal([None,0,99999999999]),'{false,0,99999999999}')

    def test_fixed_record_exact_bounds_and_windows_base_conversion(self):
        row=[2147483647,'a'*64,0,'99999999999','99999999998','99999999997',9007199254740991,0,0,'99999999996',14,60,60]
        data=encode_rows([row]);self.assertEqual(len(data),135)
        body="local original=tonumber;tonumber=function(s,base)if base==16 then assert(#s<=7 or original(s,base)<=4294967295,'Windows unsigned long overflow')end;return original(s,base)end;local F=dofile('market_fixed_records.lua');local data="+json.dumps(data)+";assert(F.Count(data)==1);local r=F.Row(data,1);assert(r[1]==2147483647 and r[2]==string.rep('a',64) and r[4]==99999999999 and r[7]==9007199254740991 and r[13]==60);local id,key=F.Key(data,1);assert(id==r[1] and key==r[2]);"
        p=subprocess.run(['lua5.1','-e',body],cwd=ROOT/'tests',text=True,capture_output=True,timeout=5)
        self.assertEqual(p.returncode,0,p.stderr)
        for bad in ['0','1;os.execute("bad")',9007199254740992,False]:
            changed=copy.deepcopy(row);changed[3]=bad
            with self.subTest(bad=bad),self.assertRaises(ValueError):encode_rows([changed])

    def test_external_oracle_hash_preserves_exact_full_snapshot(self):
        cmd=['lua5.1','tests/bench_market_opportunities.lua','opps','session','20','2','3','1','off','none']
        a=subprocess.run(cmd,cwd=ROOT,text=True,capture_output=True,timeout=15)
        self.assertEqual(a.returncode,0,a.stderr);reference=json.loads(a.stdout)
        with tempfile.TemporaryDirectory()as d:
            path=Path(d)/'oracle.bin';env=dict(os.environ,BENCH_ORACLE_SNAPSHOT=str(path))
            b=subprocess.run(cmd,cwd=ROOT,text=True,capture_output=True,timeout=15,env=env)
            self.assertEqual(b.returncode,0,b.stderr);self.assertTrue(json.loads(b.stdout)['oracle_passed'])
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),reference['result_sha256'])

    def test_unavailable_is_not_observed_absence_or_zero_price(self):
        for state in range(5):
            for rep,count in [('json',64),('packed-proof',16),('fixed-proof',16)]:
                with self.subTest(state=state,rep=rep),tempfile.TemporaryDirectory()as d:
                    config,key=fixture(Path(d),rep,count,state=state)
                    body="local B=W.Bridge;B.Record(2589,key,{current=true});drain();local r=assert(B.Record(2589,key,{current=true}));assert(r.current.state==h.states["+str(state+1)+"]);"
                    if state:body+="assert(r.current.metrics.recent_copper==W.BridgeCodec.NULL);"
                    if state==2:body+="assert(r.current.supply==0);"
                    if state in (3,4):body+="assert(r.current.supply==W.BridgeCodec.NULL);"
                    p=self.lua(config,body,key);self.assertEqual(p.returncode,0,p.stderr)

    def test_variants_missing_warm_reuse_and_cancelled_completion(self):
        for rep,count in [('json',64),('json',16),('array',16),('index',16),('verified-array',16),('proof',16),('hybrid',16),('packed-proof',16),('packed-hybrid',16),('fixed-proof',16),('fixed-hybrid',16)]:
            with self.subTest(rep=rep,count=count),tempfile.TemporaryDirectory()as d:
                config,key=fixture(Path(d),rep,count)
                body="local B=W.Bridge;local r,why=B.Record(2589,key,{current=true});assert(not r and why=='loading');drain();r=assert(B.Record(2589,key,{current=true}));assert(r.current.metrics.recent_copper=='120');local before=#pending;local hashes=0;local sha=W.BridgeCodec.SHA;W.BridgeCodec.SHA=function(...)hashes=hashes+1;return sha(...)end;for i=1,20 do assert(B.Record(2589,key,{current=true}).current.metrics.recent_copper=='120')end;assert(#pending==before and hashes==0,'warm query repeated authentication');local _,why=B.Record(2589,string.rep('f',64),{current=true});if why=='loading'then drain();_,why=B.Record(2589,string.rep('f',64),{current=true})end;assert(why=='not_observed');B.Record(9001,key,{current=true});B.Cancel();drain();assert(not W.Summary.Pending());"
                p=self.lua(config,body,key);self.assertEqual(p.returncode,0,p.stderr)

    def test_proof_rejects_valid_value_tampering_and_removed_records(self):
        for change in ['price','removed','false-missing']:
            with self.subTest(change=change),tempfile.TemporaryDirectory()as d:
                root=Path(d);config,key=fixture(root,'proof')
                p=root/'proof-current-16/13.lua';s=p.read_text()
                if change=='price':
                    self.assertIn(',0,120,',s);s=s.replace(',0,120,',',0,121,',1)
                elif change=='false-missing':
                    s=s.replace(key,'f'*64,1)
                else:
                    start=s.index(',{{');end=s.index('},{"',start)
                    s=s[:start]+',{}'+s[end+1:]
                p.write_text(s)
                r=self.lua(config,"W.Bridge.Record(2589,key,{current=true});drain()",key)
                self.assertNotEqual(r.returncode,0)
                self.assertIn('rejected',r.stderr)

    def test_packed_files_reuse_unchanged_content_across_generations(self):
        for rep in ('packed-proof','fixed-proof'):
            with self.subTest(rep=rep),tempfile.TemporaryDirectory()as d:
                a=Path(d)/'a';b=Path(d)/'b';a.mkdir();b.mkdir()
                fixture(a,rep);fixture(b,rep,epoch=1)
                self.assertNotEqual(json.loads((a/'fixture.json').read_text())['manifest']['generation_id'],json.loads((b/'fixture.json').read_text())['manifest']['generation_id'])
                for p in a.glob(rep+'-*/*.lua'):self.assertEqual(p.read_bytes(),(b/p.relative_to(a)).read_bytes())

    def test_fixed_records_reject_price_tampering_false_misses_and_truncation(self):
        for damage in ['price','false-missing','removed']:
            with self.subTest(damage=damage),tempfile.TemporaryDirectory()as d:
                root=Path(d);config,key=fixture(root,'fixed-proof')
                p=root/'fixed-proof-current-16/13.lua';s=p.read_text();m=re.search(r',16,"([0-9a-fz]*)","',s)
                self.assertIsNotNone(m);data=m[1];self.assertEqual(len(data),135)
                if damage=='price':data=data[:73]+format(121,'010x')+data[83:]
                elif damage=='false-missing':data=data[:8]+'f'*64+data[72:]
                else:data=''
                p.write_text(s[:m.start(1)]+data+s[m.end(1):])
                r=self.lua(config,"W.Bridge.Record(2589,key,{current=true});drain()",key)
                self.assertNotEqual(r.returncode,0);self.assertIn('rejected',r.stderr)

    def test_replaced_generation_cannot_publish_queued_old_data(self):
        for rep in ('proof','fixed-proof','fixed-hybrid'):
            with self.subTest(rep=rep),tempfile.TemporaryDirectory()as d:
                a=Path(d)/'a';b=Path(d)/'b';a.mkdir();b.mkdir()
                config,key=fixture(a,rep);new,_=fixture(b,rep,delta=100)
                body="local B=W.Bridge;B.Record(2589,key,{current=true});arg[12]="+json.dumps(str(new))+";h,input=X.setup(c);B.Begin(input);drain();local r,why=B.Record(2589,key,{current=true});assert(not r and why=='loading');drain();r=assert(B.Record(2589,key,{current=true}));assert(r.current.metrics.recent_copper=='220');"
                p=self.lua(config,body,key);self.assertEqual(p.returncode,0,p.stderr)


if __name__=='__main__':unittest.main()
