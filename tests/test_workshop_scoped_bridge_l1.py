"""Offline schema-3 proof; no runtime integration, generated expectations or simulator."""
import copy
import hashlib
import json
from pathlib import Path
import unittest
import test_workshop_bridge as legacy

ROOT = Path(__file__).resolve().parents[1]
MIRROR = ROOT / 'tests/fixtures/market_bridge_scoped_l1'
F = MIRROR / 'fixtures'
load = lambda p: json.loads(p.read_text())


def expanded_plan():
    resources = [load(ROOT / 'tests/fixtures/market_bridge_v1/generation-schema2.schema.json')]
    resources += [load(MIRROR / f) for f in ('selection.schema.json', 'generation-schema3.schema.json')]
    by_id = {r['$id']: r for r in resources}
    def expand(value):
        if isinstance(value, list):
            return [expand(x) for x in value]
        if not isinstance(value, dict):
            return value
        if '$ref' in value:
            uri, _, pointer = value['$ref'].partition('#')
            result = by_id[uri]
            if pointer:
                for part in pointer.lstrip('/').split('/'):
                    result = result[part]
            return expand(result)
        if isinstance(value.get('const'), list):
            values = value['const']
            # The existing primitive schema engine compares const by scalar value.
            # Array const becomes set/length validation; prototype separately
            # checks exact required-feature order and empty exclusion list.
            p = {'type': 'array', 'minItems': len(values), 'maxItems': len(values), 'uniqueItems': True}
            if values:
                p['items'] = {'enum': values}
            return p
        return {k: expand(v) for k, v in value.items() if k not in ('$id', '$schema')}
    return expand(resources[-1])


def j(value):
    return 'J.Parse(' + legacy.lua(legacy.encoded(value)) + ')'


class ScopedProof(unittest.TestCase):
    def run_proof(self, lines):
        prefix = ['local P=dofile(' + legacy.lua(str(ROOT / 'tests/prototypes/scoped_bridge_l1.lua')) + ')',
                  'local plan=' + legacy.lua(expanded_plan()),
                  'local g=' + j(load(F / 'scoped.json')),
                  'local expected=' + j(load(F / 'selection.json'))]
        legacy.BridgeReader.run_lua(self, prefix + lines)

    def test_mirror_hashes_and_legacy_unchanged(self):
        hashes = load(MIRROR / 'SHA256SUMS.json')
        self.assertEqual(len(hashes), 15)
        pin = load(MIRROR / 'UPSTREAM.json')
        self.assertRegex(pin['commit'], r'^[0-9a-f]{40}$')
        self.assertEqual(pin['hash_manifest_sha256'], hashlib.sha256((MIRROR / 'SHA256SUMS.json').read_bytes()).hexdigest())
        self.assertEqual(pin['legacy_schema_dependency']['sha256'], hashlib.sha256((ROOT / 'tests/fixtures/market_bridge_v1/generation-schema2.schema.json').read_bytes()).hexdigest())
        for rel, sha in hashes.items():
            self.assertEqual(hashlib.sha256((MIRROR / rel).read_bytes()).hexdigest(), sha, rel)
        self.assertEqual((F / 'legacy-schema2.json').read_text().strip(),
                         legacy.encoded(load(ROOT / 'tests/fixtures/market_bridge_v1/source-canonical-generation.json')))

    def test_scoped_semantics_and_actual_legacy_refusal(self):
        self.run_proof([
            'P.Validate(g,plan,expected)',
            'assert(not g.coverage.generation_complete and g.scope.scope_complete and not g.scope.whole_market_complete)',
            'assert(g.records[1].current.state=="absent" and g.records[1].current.supply==0)',
            'assert(g.scope.date_coverage[2].state=="no_observation" and g.scope.date_coverage[2].observation_ref==J.NULL)',
            'assert(P.Value(g.records[2],"recent_copper")==100 and P.Value(g.records[3],"recent_copper")==100)',
            'assert(g.records[4].current.supply==10 and g.records[4].current.priced_supply==0)',
            'assert(g.records[4].current.metrics.recent_copper==J.NULL)',
            'local excluded=' + j(load(F / 'source.json')['records'][-1]),
            'local r,why=P.Lookup(g,excluded.item_id,excluded.variant_key);assert(r==nil and why=="outside_scope")',
            'local h=J.Copy(g);h.records=nil;assert(not pcall(S.Header,h),"production reader accepted unknown schema")',
            'local unknown=' + j(load(F / 'unknown-scoped.json')),
            'P.Validate(unknown,plan,unknown.scope.request);assert(unknown.records[1].current.state=="unknown" and unknown.records[1].current.supply==J.NULL)',
            'local large=' + j(load(F / 'large-money-scoped.json')),
            'P.Validate(large,plan,large.scope.request)',
            'local value,reason=P.Value(large.records[2],"quantity_weighted_ask_copper");assert(value==nil and reason=="unsupported")',
            'assert(large.records[2].current.metrics.quantity_weighted_ask_copper=="9223372036854775807")',
        ])

    def test_negative_generations_rehashed_and_previous_retained(self):
        good = load(F / 'scoped.json')
        lines = ['local state={};P.Accept(state,g,plan,expected)', 'local original=state.active.generation_id']
        for case in load(F / 'cases.json'):
            if case['target'] != 'generation':
                continue
            bad = copy.deepcopy(good)
            p = bad
            for part in case['path'][:-1]:
                p = p[part]
            final = case['path'][-1]
            if case['op'] == 'set':
                p[final] = case['value']
            else:
                p[final].pop()
            if case.get('reseal'):
                if case.get('refresh_record_hashes', True):
                    bad['scope']['record_sha256'] = [hashlib.sha256(legacy.encoded(r).encode()).hexdigest() for r in bad['records']]
                legacy.seal(bad)
            lines += ['do local bad=' + j(bad),
                      'assert(not pcall(P.Accept,state,bad,plan,expected),' + legacy.lua(case['name']) + ')',
                      'assert(state.active.generation_id==original) end']
        lines += ['assert(not pcall(P.Accept,state,g,plan,expected,{canonical_bytes=1}));assert(state.active.generation_id==original)',
                  'local newer=' + j(load(F / 'short-window-scoped.json')),
                  'P.Accept(state,newer,plan,newer.scope.request);assert(state.previous.generation_id==original)',
                  'P.Accept(state,newer,plan,newer.scope.request);assert(state.previous.generation_id==original)']
        self.run_proof(lines)

    def test_assignment_bytes_use_existing_parser(self):
        g = load(F / 'scoped.json')
        h = {k: v for k, v in g.items() if k != 'records'}
        raw = {'transport_version': 1, 'manifest': legacy.encoded(h),
               'records': [legacy.encoded(r) for r in g['records']],
               'receipt': legacy.encoded(load(F / 'receipt.json'))}
        self.run_proof(['local raw=' + legacy.lua(raw),
                        'local value=J.Parse(raw.manifest);value.records=J.Array()',
                        'for _,text in ipairs(raw.records) do value.records[#value.records+1]=J.Parse(text) end',
                        'P.Validate(value,plan,expected);assert(value.generation_id==g.generation_id)',
                        'assert(J.Parse(raw.receipt).generation_id==value.generation_id)'])


if __name__ == '__main__':
    unittest.main()
