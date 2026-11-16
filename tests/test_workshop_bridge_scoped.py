"""Production schema-3 reader conformance. Expectations are independent pinned facts."""
import copy
import hashlib
import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path
import test_workshop_bridge as legacy

ROOT = legacy.ROOT
FIX = ROOT / 'tests/fixtures/market_bridge_scoped_l1/fixtures'
load = lambda name: json.loads((FIX / name).read_text())


def rehash(g):
    g['scope']['record_sha256'] = [hashlib.sha256(legacy.encoded(r).encode()).hexdigest() for r in g['records']]
    return legacy.seal(g)


class ScopedReader(unittest.TestCase):
    def run_reader(self, lines):
        legacy.BridgeReader.run_lua(self, lines)

    def test_available_absent_unknown_excluded_and_exact_variants(self):
        g = load('scoped.json')
        lines = ['local raw=' + legacy.lua(legacy.packed(g)), 'drain(raw,true)',
                 'assert(B.Capabilities().schemas[3]==3 and not B.Capabilities().summary_index)',
                 'local scope=B.Scope();assert(scope.type=="explicit_variants" and scope.scope_complete and not scope.whole_market_complete)',
                 'assert(B.Status().scoped and B.Status().schema==3 and B.Status().records==5)']
        for i, state in enumerate(['observed_absent', 'priced', 'priced', 'supply_only', 'priced']):
            r = g['records'][i]
            args = str(r['item_id']) + ',' + legacy.lua(r['variant_key'])
            lines += ['assert(B.Availability(' + args + ').state==' + legacy.lua(state) + ')',
                      'assert(B.Availability(' + args + ',"2026-11-14").state=="unknown_coverage")',
                      'assert(B.Availability(' + args + ',"2026-11-12").state=="outside_scope")']
        historical = g['records'][0]
        a = str(historical['item_id']) + ',' + legacy.lua(historical['variant_key'])
        excluded = load('source.json')['records'][-1]
        e = str(excluded['item_id']) + ',' + legacy.lua(excluded['variant_key'])
        lines += ['assert(B.Value(' + a + ')==nil)',
                  'assert(B.Availability(' + a + ',"2026-11-13").state=="priced")',
                  'local h=B.History(' + a + ',"recent");assert(#h.points==2 and #h.gaps==2 and h.points[2].v==nil)',
                  'assert(h.points[2].state=="absent" and h.points[2].copper==nil)',
                  'local supply=B.History(' + a + ',"supply");assert(supply.points[2].v==0)',
                  'assert(B.Availability(' + e + ').state=="outside_scope")',
                  'local v,why=B.Value(' + e + ');assert(v==nil and why=="outside_scope")',
                  'assert(B.Availability(10001,string.rep("f",64)).state=="outside_scope")',
                  'local scope=B.Scope();scope.scope_complete=false;assert(B.Scope().scope_complete)',
                  'preserved()']
        self.run_reader(lines)

    def test_negative_corpus_and_last_good_retention(self):
        good = load('scoped.json')
        lines = ['local raw=' + legacy.lua(legacy.packed(good)), 'TwichUIMarketData=raw;drain(raw,true)',
                 'local original=B.Status().generation']
        for case in load('cases.json'):
            bad = copy.deepcopy(good)
            p = bad if case['target'] == 'generation' else bad['scope']['request']
            for part in case['path'][:-1]:
                p = p[part]
            key = case['path'][-1]
            if case['op'] == 'set': p[key] = case['value']
            elif case['op'] == 'pop': p[key].pop()
            else: p[key].append(copy.deepcopy(p[key][0]))
            if case.get('reseal', case['target'] == 'request'):
                if case.get('refresh_record_hashes', True): rehash(bad)
                else: legacy.seal(bad)
            lines += ['do local bad=' + legacy.lua(legacy.packed(bad)),
                      'drain(bad,false);assert(B.Status().generation==original and B.Status().ready,' + legacy.lua(case['name']) + ') end']
        # A coherently sealed but unsolicited different market is refused when the caller pins its expected identity.
        other = copy.deepcopy(good)
        other['market']['house_id'] = other['scope']['request']['market']['house_id'] = 110
        request = other['scope']['request']
        other['scope']['request_digest'] = hashlib.sha256(legacy.encoded(request).encode()).hexdigest()
        stable = {k: v for k, v in request.items() if k not in ['history_from_day', 'history_through_day']}
        other['scope']['selection_id'] = hashlib.sha256(legacy.encoded(stable).encode()).hexdigest()
        rehash(other)
        lines += ['B.Begin(' + legacy.lua(legacy.packed(other)) + ',false,{market=J.Parse(' + legacy.lua(legacy.encoded(good['market'])) + ')})',
                  'for i=1,200000 do local ok,why=B.Step();if why~="loading" then assert(not ok);break end end',
                  'assert(B.Status().generation==original)',
                  'local bad=' + legacy.lua(legacy.packed(good)) + ';bad.records[1]=bad.records[1].." ";TwichUIMarketData=bad;drain(bad,false)',
                  'local count=B.Status().failures;assert(not B.Load());assert(B.Status().failures==count and not B.Status().loading)',
                  'assert(B.Status().generation==original);preserved()']
        self.run_reader(lines)

    def test_numeric_window_receipt_budget_and_invalid_startup(self):
        good = load('scoped.json')
        large = load('large-money-scoped.json')
        args = str(large['records'][1]['item_id']) + ',' + legacy.lua(large['records'][1]['variant_key'])
        lines = ['drain(' + legacy.lua(legacy.packed(large)) + ',true)',
                 'local value,why=B.Value(' + args + ',"mean");assert(value==nil and why=="unsupported")',
                 'assert(B.Availability(' + args + ').state=="priced")',
                 'drain(' + legacy.lua(legacy.packed(load('unknown-scoped.json'))) + ',true)',
                 'assert(B.Availability(2,' + legacy.lua(load('unknown-scoped.json')['records'][0]['variant_key']) + ').state=="unknown_coverage")',
                 'drain(' + legacy.lua(legacy.packed(good)) + ',true);local previous=B.Status().generation',
                 'local raw=' + legacy.lua(legacy.packed(good)),
                 'B.SCOPED_BYTES=1;drain(raw,false);assert(B.Status().generation==previous and B.Status().refusal=="canonical_bytes");B.SCOPED_BYTES=2*1024*1024',
                 'raw.receipt=raw.receipt:gsub("2026%-11%-15T13:00:00Z","2020-01-01T00:00:00Z");drain(raw,false)',
                 'assert(B.Status().generation==previous);preserved()']
        self.run_reader(lines)
        large['records'][1]['current']['metrics']['recent_copper'] = '9223372036854775807'
        rehash(large)
        self.run_reader(['drain(' + legacy.lua(legacy.packed(large)) + ',false)'])
        large['records'][1]['current']['arithmetic_status'] = 'unsupported'
        large['records'][1]['current']['metrics']['recent_copper'] = None
        large['records'][1]['current']['metrics']['minimum_copper'] = None
        rehash(large)
        self.run_reader(['drain(' + legacy.lua(legacy.packed(large)) + ',true)',
                         'assert(B.Availability(' + args + ').state=="unsupported")',
                         'local v,why=B.Value(' + args + ');assert(v==nil and why=="unsupported")'])
        raw = legacy.packed(good)
        header = json.loads(raw['manifest']);header['integrity']['records_bytes'] = 2
        raw['manifest'] = legacy.encoded(header)
        actual = len(raw['manifest']) + 11 + len(legacy.encoded(good['records']))
        self.run_reader(['B.SCOPED_BYTES=' + str(actual-1), 'drain(' + legacy.lua(raw) + ',false)',
                         'assert(B.Status().refusal=="canonical_bytes","trusted a falsely small declared size")'])
        self.run_reader(['drain({transport_version=9},false)', 'assert(B.Availability(1,string.rep("f",64)).state=="invalid_generation")', 'preserved()'])

    def test_valid_replacement_clears_cache_and_preserves_scope_identity(self):
        good, newer = load('scoped.json'), load('short-window-scoped.json')
        key = legacy.lua(good['records'][1]['variant_key'])
        self.run_reader(['drain(' + legacy.lua(legacy.packed(good)) + ',true)',
                         'B.Record(10001,' + key + ');assert(B.Status().cache_entries==1)',
                         'local previous=B.Status().generation;local selection=B.Scope().selection_id;local digest=B.Scope().request_digest',
                         'drain(' + legacy.lua(legacy.packed(newer)) + ',true)',
                         'assert(B.Status().generation~=previous and B.Status().cache_entries==0)',
                         'assert(B.Scope().selection_id==selection and B.Scope().request_digest~=digest)',
                         'assert(B.Scope().history_from_day=="2026-11-15")',
                         'assert(#B.History(10001,' + key + ',"recent").points==1)',
                         'assert(B.Availability(10001,' + key + ',"2026-11-13").state=="outside_scope")',
                         'assert(B.Availability(10001,' + key + ',"2026-11-15").complete)',
                         'preserved()'])

    def test_large_scoped_manifest_and_legacy_parser_bounds(self):
        g = load('scoped.json')
        template = g['records'][1]
        g['records'] = []
        for item in range(10000, 10250):
            r = copy.deepcopy(template)
            r['item_id'] = item
            r['variant_json'] = legacy.encoded({'id': item})
            r['variant_key'] = hashlib.sha256(r['variant_json'].encode()).hexdigest()
            g['records'].append(r)
        variants = [{'item_id': r['item_id'], 'variant_key': r['variant_key']} for r in g['records']]
        request = g['scope']['request'];request['variants'] = variants
        g['scope']['included'] = variants
        g['record_count'] = g['scope']['requested_count'] = len(variants)
        g['scope']['request_digest'] = hashlib.sha256(legacy.encoded(request).encode()).hexdigest()
        stable = {k: v for k, v in request.items() if k not in ('history_from_day', 'history_through_day')}
        g['scope']['selection_id'] = hashlib.sha256(legacy.encoded(stable).encode()).hexdigest()
        rehash(g)
        raw = legacy.packed(g)
        self.assertGreater(len(raw['manifest']), 65536)
        self.assertLess(len(raw['manifest']), 256*1024)
        self.run_reader(['drain(' + legacy.lua(raw) + ',true)',
                         'assert(B.Status().records==250)',
                         'local text="\\\""..string.rep("a",65536).."\\\""',
                         'assert(not pcall(J.Parse,text))',
                         'assert(#J.Parse(text,nil,256*1024)==65536)',
                         'assert(not pcall(J.Parse,text,nil,256*1024+1))',
                         'preserved()'])

    def test_compiled_schema_matches_trusted_mirror(self):
        subprocess.run([sys.executable, str(ROOT / 'tools/compile_bridge_schema.py'), '--check'], check=True)
        spec = importlib.util.spec_from_file_location('compile_bridge_schema', ROOT / 'tools/compile_bridge_schema.py')
        module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        self.run_reader(['assert(J.Encode(TwichUI.Workshop.BridgeSchemas[3],nil,-20)==' + legacy.lua(legacy.encoded(module.plans()[2])) + ')'])


if __name__ == '__main__': unittest.main()
