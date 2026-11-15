"""Execute pinned bridge generations through the real Lua reader; no generated expectations."""
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
FIXTURES=ROOT/'tests/fixtures/market_bridge_v1'
def encoded(value):return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True)
def lua(value):
    if value is None:return 'nil'
    if isinstance(value,bool):return 'true' if value else 'false'
    if isinstance(value,int):return str(value)
    if isinstance(value,str):return '"'+''.join(chr(b) if 32<=b<127 and b not in (34,92) else '\\%03d'%b for b in value.encode())+'"'
    if isinstance(value,list):return '{'+','.join(lua(v) for v in value)+'}'
    return '{'+','.join('['+lua(k)+']='+lua(v) for k,v in value.items())+'}'
def seal(g):
    body={k:v for k,v in g.items() if k not in ('generation_id','integrity')};manifest={k:v for k,v in body.items() if k!='records'}
    sha=lambda x:hashlib.sha256(encoded(x).encode()).hexdigest()
    g['generation_id']=sha(body);g['integrity']={'records_bytes':len(encoded(g['records'])),'records_sha256':sha(g['records']),'manifest_sha256':sha(manifest)}
    return g
def packed(g):
    h={k:v for k,v in g.items() if k!='records'}
    return {'transport_version':1,'manifest':encoded(h),'records':[encoded(r) for r in g['records']],
            'receipt':encoded({'schema_version':1,'generation_id':g['generation_id'],'desktop_build':'synthetic-reader-test','completed_at':'2026-11-15T13:00:00Z'})}
class BridgeReader(unittest.TestCase):
    def run_lua(self,lines):
        self.assertIsNotNone(shutil.which('lua5.1'),'Lua 5.1 required')
        setup=['require("bit")','TwichUI={Workshop={}}','TwichUIDB={localProfile="preserved"}',
               'TwichUIWorkshopDB={v=2,markets={localScan={items={[2589]="500,10,3,10,0"},h2={[2589]="original-local-history"}}}}',
               'local localDB,profile=TwichUIWorkshopDB,TwichUIDB',
               'local function fingerprint(t) if type(t)~="table" then return tostring(t) end local k={} for x in pairs(t) do k[#k+1]=x end table.sort(k,function(a,b)return tostring(a)<tostring(b)end) local out={} for _,x in ipairs(k)do out[#out+1]=tostring(x).."="..fingerprint(t[x]) end return "{"..table.concat(out,",").."}" end',
               'local before=fingerprint(localDB)..fingerprint(profile)',
               'GetTimePreciseSec=function()return os.clock()end']
        for file in ['Data','BridgeCodec','BridgeSchema','BridgeValidate','Bridge']:
            setup+=['dofile('+lua(str(ROOT/'TwichUI_Workshop'/(file+'.lua')))+')']
        setup+=['local J,B,S=TwichUI.Workshop.BridgeCodec,TwichUI.Workshop.Bridge,TwichUI.Workshop.BridgeValidate',
                'local function drain(raw,good) B.Begin(raw) for i=1,200000 do local ok,why=B.Step(3) if why~="loading" then assert(ok==good,"unexpected reader result: "..tostring(why));return end end error("reader never completed") end',
                'local function preserved()assert(TwichUIWorkshopDB==localDB and TwichUIDB==profile and before==fingerprint(localDB)..fingerprint(profile),"local saved data changed")end']
        script='\n'.join(setup+lines+['preserved()','print("PASSED bridge reader")'])+'\n'
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'test.lua';p.write_text(script)
            result=subprocess.run(['lua5.1',str(p)],capture_output=True,text=True,timeout=120)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
    def test_fixtures_lazy_records_history_and_local_separation(self):
        lines=[]
        for name in ['canonical-generation.json','provisional-generation.json','source-canonical-generation.json','source-provisional-generation.json','fractional-close-generation.json']:
            g=json.loads((FIXTURES/name).read_text());v=next(r for r in g['records'] if r['item_id']==2589)
            lines+=['drain('+lua(packed(g))+',true)','assert(B.Status().generation=='+lua(g['generation_id'])+')',
                    'assert(B.Status().cache_entries==0,"eager decoded cache")',
                    'local r=B.Record(2589,'+lua(v['variant_key'])+')',
                    'assert(r.current.metrics.recent_copper=="120")',
                    'local h=B.History(2589,'+lua(v['variant_key'])+',"recent",{days=60})',
                    'assert(#h.points==2 and h.points[1].copper=="100" and h.points[2].copper=="120")',
                    'assert(h.algorithm=='+lua(g['pricing_algorithm'])+' and h.basis=='+lua(g['history_basis'])+')',
                    'assert(B.Record(2589)==nil,"item aggregate silently matched exact variant")',
                    'r.current.metrics.recent_copper="1";assert(B.Record(2589,'+lua(v['variant_key'])+').current.metrics.recent_copper=="120","returned cache mutable")',
                    'preserved()']
        lines+=['assert(B.Status().cache_entries<=B.CACHE_MAX)']
        self.run_lua(lines)
    def test_invalid_generation_keeps_previous_and_no_local_mutation(self):
        base=json.loads((FIXTURES/'source-canonical-generation.json').read_text());lines=['drain('+lua(packed(base))+',true)']
        mutations=[lambda g:g.update(schema_version=3),lambda g:g.update(pricing_algorithm='future'),
            lambda g:g['coverage'].update(generation_complete=False),lambda g:g['records'][1].update(variant_key='a'*64),
            lambda g:g['records'][0]['current'].update(supply=1),lambda g:g['records'][1]['daily'][0].update(observation_ref=60),lambda g:g['records'][1].update(daily=[]),
            lambda g:g['records'][1]['current']['metrics'].update(historical_value_copper='100'),
            lambda g:g['records'].append(copy.deepcopy(g['records'][1]))]
        for mutate in mutations:
            g=copy.deepcopy(base);mutate(g);seal(g)
            lines+=['drain('+lua(packed(g))+',false)','assert(B.Status().generation=='+lua(base['generation_id'])+')','preserved()']
        bad=packed(base);bad['records'][1]=bad['records'][1].replace('"recent_copper":"120"','"recent_copper":"121"')
        lines+=['drain('+lua(bad)+',false)','assert(B.Status().generation=='+lua(base['generation_id'])+')',
                'C_AddOns={LoadAddOn=function()error("must not unexpectedly load anything")end}',
                'assert(B.Status().ready and B.Market().house_id==114)','preserved()']
        self.run_lua(lines)
    def test_partial_scope_unknown_is_not_absence_or_fabricated_day(self):
        g=json.loads((FIXTURES/'partial-unknown-generation.json').read_text());key=g['records'][1]['variant_key']
        self.run_lua(['drain('+lua(packed(g))+',true)','local r=B.Record(2589,'+lua(key)+')',
          'assert(r.current.state=="unknown" and r.current.supply==J.NULL and B.Value(2589,'+lua(key)+',"recent")==nil)',
          'local h=B.History(2589,'+lua(key)+',"recent",{days=2});assert(#h.points==1 and #h.gaps==1 and h.gaps[1].why=="only_incomplete_server_observations")'])
    def test_json_sha_properties_and_large_currency_strings(self):
        import random
        rng=random.Random(14031);lines=[]
        for _ in range(80):
            raw=bytes(rng.randrange(256) for _ in range(rng.randrange(0,1024))).decode('latin1')
            # UTF-8 bytes are the independently hashed source string.
            lines+=['assert(J.SHA('+lua(raw)+')=='+lua(hashlib.sha256(raw.encode()).hexdigest())+')']
            value={'text':raw,'money':'9223372036854775807','count':rng.randrange(0,9007199254740992),'null':None,'flags':[True,False]}
            text=encoded(value);lines+=['assert(J.Encode(J.Parse('+lua(text)+'))=='+lua(text)+')']
        lines+=['assert(not pcall(J.Parse,\'{"a":null,"a":1}\'))','assert(not pcall(J.Parse,"9007199254740993"))',
                'assert(not pcall(J.Parse,string.rep("[",15).."0"..string.rep("]",15)))']
        self.run_lua(lines)
    def test_absent_bridge_combat_and_schema_plan_hashes(self):
        for manifest in ['SHA256SUMS.json','SCHEMA2-SHA256SUMS.json']:
            for name,digest in json.loads((FIXTURES/manifest).read_text()).items():self.assertEqual(hashlib.sha256((FIXTURES/name).read_bytes()).hexdigest(),digest)
        lines=['local calls=0;C_AddOns={LoadAddOn=function(name)calls=calls+1;assert(name=="TwichUI_MarketData");return false,"MISSING" end}',
               'assert(not B.Status().ready and calls==0)','assert(not B.Load() and calls==1)','assert(B.Status().state=="absent")',
               'InCombatLockdown=function()return true end;assert(not B.Load() and calls==1)',
               'assert(S.Time("2026-11-14T12:00:00.9Z")>S.Time("2026-11-14T12:00:00.123456Z"))']
        for version,name in [(1,'generation.schema.json'),(2,'generation-schema2.schema.json')]:
            lines+=['assert(J.Encode(TwichUI.Workshop.BridgeSchemas['+str(version)+'],nil,-20)=='+lua(encoded(json.loads((FIXTURES/name).read_text())))+')']
        self.run_lua(lines)
if __name__=='__main__':unittest.main()
