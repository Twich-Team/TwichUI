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

    def test_malformed_identifiers_fail_closed_without_guessing_update_direction(self):
        lines=[]
        for index in range(4):
            for bad in [None, True, False, -1, 2147483648, '1', {}, []]:
                args=[1,1,2,1]
                args[index]=bad
                # An omitted receipt parameter is the public helper's documented default.
                if index==3 and bad is None:
                    continue
                lines+=['do local c=B.CheckCompatibility('+','.join(lua(x) for x in args)+')',
                        'assert(not c.compatible and c.reason=="invalid_contract")',
                        'assert(not c.message:find("Update TwichUI",1,true)) end']
        self.run_lua(lines)

    def test_bad_receipts_and_corruption_preserve_data_and_allow_recovery(self):
        base=json.loads((FIXTURES/'source-canonical-generation.json').read_text())
        good=packed(base)
        lines=['drain('+lua(good)+',true)', 'local original=J.Encode((B.Receipt()))',
               'local key='+lua(base['records'][1]['variant_key']),
               'local originalRecord=J.Encode(B.Record(2589,key))']
        mutations=[lambda r:r.pop('schema_version'),lambda r:r.update(schema_version=None),
                   lambda r:r.update(schema_version='1'),lambda r:r.update(generation_id='0'*64),
                   lambda r:r.update(desktop_build=''),lambda r:r.update(desktop_build='x'*81),
                   lambda r:r.update(completed_at='not-a-date'),lambda r:r.update(extra='untrusted')]
        for mutate in mutations:
            raw=copy.deepcopy(good);receipt=json.loads(raw['receipt']);mutate(receipt)
            raw['receipt']=json.dumps(receipt,sort_keys=True,separators=(',',':'))
            lines+=['drain('+lua(raw)+',false)',
                    'assert(B.Status().generation=='+lua(base['generation_id'])+')',
                    'assert(J.Encode((B.Receipt()))==original and J.Encode(B.Record(2589,key))==originalRecord)',
                    'preserved()']
        raw=copy.deepcopy(good);raw['records'][1]+=';error("must never execute")'
        lines+=['drain('+lua(raw)+',false)',
                'assert(J.Encode((B.Receipt()))==original and J.Encode(B.Record(2589,key))==originalRecord)',
                'drain('+lua(good)+',true)',
                'assert(B.Status().error==nil and B.Status().compatibility_message==nil)',
                'assert(J.Encode(B.Record(2589,key))==originalRecord)']
        self.run_lua(lines)

    def test_cold_refusals_and_real_companion_builds(self):
        base=json.loads((FIXTURES/'source-canonical-generation.json').read_text())
        lines=[]
        for version,reason,message in [(0,'older_companion','Update TwichUI Market Companion'),
                                       (999,'newer_addon','Update TwichUI to import it.')]:
            raw=packed(base);raw['transport_version']=version
            lines+=['drain('+lua(raw)+',false)',
                    'assert(not B.Status().ready and B.Status().state=="invalid")',
                    'assert(B.Compatibility()==nil and B.Receipt()==nil)',
                    'assert(B.Status().compatibility_reason=='+lua(reason)+')',
                    'assert(B.Status().compatibility_message:find('+lua(message)+',1,true))']
        for build in ['2.0.0-beta.3','2.0.0-beta.4']:
            raw=packed(base);receipt=json.loads(raw['receipt']);receipt['desktop_build']=build
            raw['receipt']=json.dumps(receipt,sort_keys=True,separators=(',',':'))
            lines+=['drain('+lua(raw)+',true)',
                    'assert(B.CompatibilityText()=='+lua('Market data from Companion '+build)+')',
                    'assert(B.CompatibilityText(true):find("transport 1 · contract 1 · schema 2 · receipt 1",1,true))',
                    'assert(B.CompatibilityText(true):find("reader contract 2 required · installed 3",1,true))']
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
