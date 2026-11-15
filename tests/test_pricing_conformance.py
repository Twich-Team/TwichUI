"""Execute the same authored JSON expectations against the dormant Lua module."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
FIXTURES = REPO/'tests/fixtures/pricing_v1'


def lua(value):
    if value is None: return 'nil'
    if isinstance(value,bool): return 'true' if value else 'false'
    if isinstance(value,int): return str(value)
    if isinstance(value,str):
        return '"'+''.join(chr(c) if 32<=c<127 and c not in (34,92) else '\\%03d'%c for c in value.encode())+'"'
    if isinstance(value,list): return '{'+','.join(lua(v) for v in value)+'}'
    return '{'+','.join('['+lua(k)+']='+lua(v) for k,v in value.items())+'}'


class PricingConformance(unittest.TestCase):
    def test_shared_fixtures_in_lua(self):
        runtime=shutil.which('lua5.1')
        self.assertIsNotNone(runtime,'Lua 5.1 is required; missing tooling is not a skip')
        for name, digest in json.loads((FIXTURES/'SHA256SUMS.json').read_text()).items():
            self.assertEqual(hashlib.sha256((FIXTURES/name).read_bytes()).hexdigest(),digest)
        snapshots=json.loads((FIXTURES/'snapshots.json').read_text())['cases']
        temporal=json.loads((FIXTURES/'temporal.json').read_text())['cases']
        boundaries=json.loads((FIXTURES/'boundaries.json').read_text())
        lines=['TwichUI={Workshop={}}','dofile('+lua(str(REPO/'TwichUI_Workshop/Data.lua'))+')',
               'dofile('+lua(str(REPO/'TwichUI_Workshop/PricingV1.lua'))+')','local P=TwichUI.Workshop.PricingV1']
        for case in snapshots:
            source=case['provenance']['source_kind'] if case['provenance'] else 'auctions'
            rows=[]
            for original in case['listings']:
                r={**original,'item_id':case['item']['id'],'variant_key':case['variant_key']}
                if source=='auctions' and r['unit_copper'] is not None:
                    r['total_copper']=str(int(r['unit_copper'])*r['quantity']);r['unit_copper']=None
                rows.append(r)
            lines+=['do local result,why=P.Snapshot('+lua(rows)+','+str(case['item']['id'])+','+lua(case['variant_key'])+','+lua(source)+',P.ALGORITHM)']
            if case['id'] in ('above-lua-exact','signed64-maximum'):
                lines+=['assert(result==nil and why=="numeric_range",'+lua(case['id'])+')']
            else:
                lines+=['assert(result,'+lua(case['id'])+')']
                for actual,expected in [('minimum_listing_copper','canonical_minimum'),('recent_copper','workshop_recent'),('anchor_copper','anchor'),('q25_copper','q25'),('q50_copper','q50'),('q75_copper','q75')]:
                    lines+=['assert(result.'+actual+'=='+lua(case['expected'][expected])+','+lua(case['id']+' '+actual)+')']
            lines+=['end']
        key='a'*64
        for case in temporal:
            points=[]
            for i,p in enumerate(case['points']):
                points.append({'observation_id':i+1,'market_key':'fixture-market','item_id':2589,'variant_key':key,
                    'algorithm':'twichui-pricing-v1','observed_at':int(datetime.datetime.fromisoformat(p['observed_at'].replace('Z','+00:00')).timestamp()),
                    'complete':p['complete'],'state':p['state'],'recent_copper':p['unit_copper'],
                    'synthetic':True,'content_id':'fixture-content-'+str(i)})
            now=int(datetime.datetime.fromisoformat(case['as_of'].replace('Z','+00:00')).timestamp())
            lines+=['do local result,why=P.History('+lua(points)+',"fixture-market",2589,'+lua(key)+','+str(now)+',P.ALGORITHM)',
                    'assert(result,'+lua(case['id'])+')']
            for actual,expected in [('market_value_copper','canonical_market_value'),('historical_value_copper','canonical_historical_value'),('priced_days_60','canonical_priced_days_60')]:
                lines+=['assert(result.'+actual+'=='+lua(case['expected'][expected])+','+lua(case['id']+' '+actual)+')']
            lines+=['end']
        for case in boundaries['quality']:
            lines+=['assert(P.Quality('+lua(case['input'])+')=='+lua(case['expected'])+','+lua(case['id'])+')']
        bridge=REPO/'tests/fixtures/market_bridge_v1'
        for name,digest in json.loads((bridge/'SHA256SUMS.json').read_text()).items():
            self.assertEqual(hashlib.sha256((bridge/name).read_bytes()).hexdigest(),digest)
        for name in ['canonical-generation.json','provisional-generation.json']:
            h=json.loads((bridge/name).read_text())
            lines+=['assert(P.SupportsHeader('+lua(h)+'))']
            for field in ['contract_version','schema_version','transport_version','quality_policy']:
                wrong={**h,field:2};lines+=['assert(not P.SupportsHeader('+lua(wrong)+'))']
            wrong={**h,'history_basis':'legacy-local-buckets'};lines+=['assert(not P.SupportsHeader('+lua(wrong)+'))']
        lines+=['print("PASSED shared Lua pricing: 23 snapshot, 8 temporal, 11 quality cases")']
        with tempfile.TemporaryDirectory(prefix='pricing-conformance-') as temp:
            p=Path(temp)/'conformance.lua';p.write_text('\n'.join(lines)+'\n')
            result=subprocess.run([runtime,str(p)],capture_output=True,text=True,timeout=30,env=os.environ.copy())
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('PASSED',result.stdout)


if __name__=='__main__': unittest.main()
