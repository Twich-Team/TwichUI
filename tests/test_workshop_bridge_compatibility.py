"""Versioned cross-repository policy and atomic compatibility refusals, Lua 5.1."""
import copy
import hashlib
import json
from test_workshop_bridge import BridgeReader, FIXTURES, ROOT, lua, packed, seal

class Compatibility(BridgeReader):
    def test_explicit_contract_matrix(self):
        fixture=ROOT/'tests/fixtures/market_bridge_compatibility/v1.json'
        pin=json.loads((fixture.parent/'UPSTREAM.json').read_text())
        self.assertEqual(hashlib.sha256(fixture.read_bytes()).hexdigest(),pin['sha256'])
        policy=json.loads(fixture.read_text())
        lines=[]
        for case in policy['cases']:
            args=[case['transport'],case['contract'],case['schema'],case.get('receipt',1)]
            lines+=['do local c=B.CheckCompatibility('+','.join(lua(x) for x in args)+')',
                    'assert(c.compatible=='+lua(case['compatible'])+','+lua(case['name'])+')',
                    'assert(c.reason=='+lua(case.get('reason'))+')']
            if 'minimum_reader_version' in case:lines+=['assert(c.minimum_reader_version=='+lua(case['minimum_reader_version'])+')']
            lines+=['end']
        self.run_lua(lines)

    def test_unknown_versions_keep_last_validated_generation_and_direction(self):
        base=json.loads((FIXTURES/'source-canonical-generation.json').read_text())
        good=packed(base)
        lines=['drain('+lua(good)+',true)','assert(B.Compatibility().minimum_reader_version==2)',
               'assert(B.Status().desktop_build=="synthetic-reader-test")']
        for field,value,reason in [('transport',2,'newer_addon'),('contract_version',2,'newer_addon'),('schema_version',4,'newer_addon'),('transport',0,'older_companion'),('contract_version',0,'older_companion'),('schema_version',0,'older_companion'),('receipt',2,'newer_addon'),('receipt',0,'older_companion')]:
            g=copy.deepcopy(base)
            if field not in ('transport','receipt'):g[field]=value;seal(g)
            raw=packed(g)
            if field=='transport':raw['transport_version']=value
            if field=='receipt':
                receipt=json.loads(raw['receipt']);receipt['schema_version']=value
                raw['receipt']=json.dumps(receipt,sort_keys=True,separators=(',',':'))
            lines+=['drain('+lua(raw)+',false)','assert(B.Status().generation=='+lua(base['generation_id'])+')',
                    'assert(B.Status().compatibility_reason=='+lua(reason)+')',
                    'assert(B.Status().compatibility_message:find('+lua('Update TwichUI to' if reason=='newer_addon' else 'Update TwichUI Market Companion')+',1,true))',
                    'assert(B.Receipt().desktop_build=="synthetic-reader-test")','preserved()']
        # Marketing version never determines data compatibility; display text is escaped.
        raw=packed(base);receipt=json.loads(raw['receipt']);receipt['desktop_build']='99.999.0|cffff0000\nfixture'
        raw['receipt']=json.dumps(receipt,sort_keys=True,separators=(',',':'))
        lines+=['drain('+lua(raw)+',true)','assert(B.Status().compatibility_message==nil)',
                'assert(B.CompatibilityText():find("99.999.0||cffff0000 fixture",1,true))','preserved()']
        self.run_lua(lines)
