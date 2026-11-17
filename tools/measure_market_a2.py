#!/usr/bin/env python3
"""Make disposable synthetic A2 fixtures; optionally run the existing reader/Market mocks.

No producer checkout, game installation, delivery, or SavedVariables access.
Generated artifacts belong under test-output or /tmp, never in a live AddOns tree.
"""
import argparse
import copy
import datetime as dt
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests'))
from test_workshop_bridge import encoded, lua, packed, seal

FIX = ROOT / 'tests/fixtures/market_bridge_scoped_l1/fixtures/scoped.json'
CASES = {'10-dense': (10, 60), '100-sparse': (100, 4), '100-dense': (100, 60)}
sha = lambda data: hashlib.sha256(data).hexdigest()


def generation(count, closes):
    g = json.loads(FIX.read_text())
    template = copy.deepcopy(g['records'][1])
    observation = copy.deepcopy(g['observations'][0])
    start = dt.date(2026, 9, 17)
    days = [start + dt.timedelta(days=i) for i in range(60)]
    selected = list(range(60)) if closes == 60 else [0, 20, 40, 59]
    g['observations'] = []
    for i in selected:
        o = copy.deepcopy(observation)
        day = days[i].isoformat()
        o.update(utc_day=day, observed_at=day+'T12:00:00.123456Z',
                 upstream_updated_at=day+'T11:00:00Z', observation_id=str(1000+i),
                 snapshot_id=str(2000+i), payload_sha256=sha(('payload:'+day).encode()),
                 snapshot_content_sha256=sha(('snapshot:'+day).encode()))
        g['observations'].append(o)
    g['watermark_observation_id'] = g['observations'][-1]['observation_id']
    g['current_observation_ref'] = closes-1
    g['coverage'].update(history_from_day=days[0].isoformat(), available_observed_days=closes,
                         delivered_observed_days=closes)
    g['records'] = []
    for item in range(10001, 10001+count):
        r = copy.deepcopy(template)
        r.update(item_id=item, variant_json=encoded({'id': item}))
        r['variant_key'] = sha(r['variant_json'].encode())
        r['daily'] = [dict(template['daily'][0], observation_ref=i) for i in range(closes)]
        r['current']['observation_ref'] = closes-1
        r['current']['coverage'].update(observed_days_60=closes, priced_days_60=closes,
                                       priced_days_14=sum(i >= 46 for i in selected))
        r['current']['metrics']['historical_value_copper'] = '100'
        g['records'].append(r)
    variants = [{'item_id': r['item_id'], 'variant_key': r['variant_key']} for r in g['records']]
    scope = g['scope']; request = scope['request']
    request.update(history_from_day=days[0].isoformat(), variants=variants)
    scope.update(included=variants, requested_count=count,
                 request_digest=sha(encoded(request).encode()),
                 selection_id=sha(encoded({k: v for k, v in request.items()
                                           if k not in ('history_from_day', 'history_through_day')}).encode()),
                 record_sha256=[sha(encoded(r).encode()) for r in g['records']],
                 date_coverage=[{'day': day.isoformat(),
                                 'state': 'complete_close' if i in selected else 'no_observation',
                                 'observation_ref': selected.index(i) if i in selected else None}
                                for i, day in enumerate(days)])
    g['record_count'] = count
    return seal(g)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--case', choices=CASES, required=True)
    p.add_argument('--out', type=Path, default=ROOT / 'test-output/market-a2')
    p.add_argument('--measure', action='store_true', help='one diagnostic sample, not an optimization comparison')
    a = p.parse_args()
    dest = a.out.resolve()
    if not any(dest.is_relative_to(root) for root in ((ROOT/'test-output').resolve(), Path('/tmp'))):
        p.error('--out must be under repository test-output or /tmp')
    g = generation(*CASES[a.case]); raw = packed(g)
    artifact = 'TwichUIMarketData = '+lua(raw)+'\n'
    assert len(encoded(g)) <= 2*1024**2 and len(artifact) <= 3*1024**2
    folder = dest/a.case/'TwichUI_MarketData'; folder.mkdir(parents=True, exist_ok=True)
    (folder/'Data.lua').write_text(artifact)
    interface = next(line for line in (ROOT/'TwichUI_Workshop/TwichUI_Workshop.toc').read_text().splitlines()
                     if line.startswith('## Interface:'))
    (folder/'TwichUI_MarketData.toc').write_text(interface+'\n## Title: Synthetic A2 Market test\n'
                                              '## LoadOnDemand: 1\n## RequiredDeps: !!!TwichUI\nData.lua\n')
    bad = copy.deepcopy(raw)
    bad['records'][-1] = bad['records'][-1].replace('"recent_copper":"100"', '"recent_copper":"101"', 1)
    assert bad != raw
    corrupt = folder.parent/'TwichUI_MarketAuditCorrupt'; corrupt.mkdir(exist_ok=True)
    (corrupt/'Data.lua').write_text('TwichUIMarketData = '+lua(bad)+'\n')
    (corrupt/'TwichUI_MarketAuditCorrupt.toc').write_text(interface+'\n## Title: Synthetic A2 corrupt replacement\n'
                                                      '## LoadOnDemand: 1\n'
                                                      '## RequiredDeps: TwichUI_Workshop, TwichUI_MarketData\nData.lua\n')
    report = dict(case=a.case, generation=g['generation_id'], canonical_bytes=len(encoded(g)),
                  lua_bytes=len(artifact), artifact_sha256=sha(artifact.encode()), fixture_sha256=sha(FIX.read_bytes()),
                  source_revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                  source_sha256={str(f.relative_to(ROOT)): sha(f.read_bytes()) for f in
                                 [ROOT/'TwichUI_Workshop'/name for name in
                                  ('Data.lua', 'Bridge.lua', 'BridgeCodec.lua', 'BridgeSchema.lua',
                                   'BridgeValidate.lua', 'ServerMarket.lua')]})
    if a.measure:
        setup = 'require("bit");ROOT="../!!!TwichUI/";REPO="../";TESTS="./"'
        proc = subprocess.run(['lua5.1', '-e', setup, 'bench_market_bridge.lua', str(folder/'Data.lua'),
                               str(corrupt/'Data.lua'), str(CASES[a.case][1])],
                              cwd=ROOT/'tests', capture_output=True, text=True, timeout=120)
        (folder.parent/'console.txt').write_text(proc.stdout+proc.stderr)
        if proc.returncode:
            raise RuntimeError(proc.stdout+proc.stderr)
        report['measurement'] = json.loads(proc.stdout.splitlines()[-1])
    (folder.parent/('report.json' if a.measure else 'fixture.json')).write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
