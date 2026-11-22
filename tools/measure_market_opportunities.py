#!/usr/bin/env python3
"""Opt-in synthetic audit workloads; never selected by routine test discovery."""
import argparse
import hashlib
import json
import platform
from pathlib import Path
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--report', type=Path, required=True)
    p.add_argument('--reps', type=int, default=3)
    p.add_argument('--suite', choices=['reader', 'opportunities', 'memory', 'index', 'all'], default='all')
    p.add_argument('--days', type=int, choices=[2, 60], default=2)
    p.add_argument('--contract', type=int, choices=[2, 3], default=2, help='PR1 coupled or negotiated split projection')
    p.add_argument('--rows', type=int, default=32, help='records per bucket; opt-in scale, 1..768')
    p.add_argument('--case', action='append', help='exact mode/pattern/count selector; repeatable')
    a = p.parse_args()
    if not 1 <= a.reps <= 10:
        p.error('--reps must be 1..10')
    if not 1 <= a.rows <= 768:
        p.error('--rows must be 1..768')
    cases = []
    if a.suite in ('reader', 'all'):
        cases += [('reader', pattern, a.rows) for pattern in ('single', 'alternating', 'single-distinct', 'alternating-distinct', 'batched')]
    if a.suite in ('opportunities', 'all'):
        cases += [('opportunities', path, n) for n in (20, 100, 500, 1000) for path in ('session', 'ui')]
    if a.suite in ('memory', 'all'):
        cases += [('memory', str(n), 32) for n in (1, 2, 4, 8, 16, 64)]
    if a.suite == 'index':
        cases = [('index', 'numeric', 32)]
    if a.case:
        available = {'/'.join(map(str,c)) for c in cases}
        if set(a.case)-available:
            p.error('unknown case: '+str(set(a.case)-available))
        cases = [c for c in cases if '/'.join(map(str,c)) in a.case]
    report = dict(source=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                  harness_sha256=hashlib.sha256((ROOT/'tests/bench_market_opportunities.lua').read_bytes()).hexdigest(),
                  index_harness_sha256=hashlib.sha256((ROOT/'tests/bench_market_index_memory.lua').read_bytes()).hexdigest(),
                  host=platform.platform(), python=platform.python_version(), clock='Lua os.clock CPU; Python perf_counter subprocess elapsed',
                  limitations='Synthetic 60Hz minimum timer delay; not the WoW scheduler. Peak heap sampled at callbacks/lookups, not exact peak. Includes harness observer overhead.',
                  contract=a.contract, rows_per_bucket=a.rows, samples=[])
    # One discarded warm-up per case; each sample is a fresh Lua process.
    for mode, pattern, count in cases:
        samples = []
        for rep in range(a.reps+1):
            start = time.perf_counter()
            command = (['lua5.1', 'tests/bench_market_index_memory.lua', str(count)] if mode == 'index' else
                       ['lua5.1', 'tests/bench_market_opportunities.lua', mode, pattern, str(count), str(a.days), str(a.contract), str(a.rows)])
            result = subprocess.run(command,
                                    cwd=ROOT, text=True, capture_output=True, timeout=600, check=True)
            row = json.loads(result.stdout)
            row['subprocess_wall_seconds'] = time.perf_counter()-start
            if rep:
                samples.append(row)
        metrics = {k: dict(median=statistics.median(s[k] for s in samples), minimum=min(s[k] for s in samples), maximum=max(s[k] for s in samples))
                   for k,v in samples[0].items() if isinstance(v, (int,float)) and not isinstance(v,bool)}
        report['samples'].append(dict(case=[mode,pattern,count,a.days], runs=samples, metrics=metrics))
        a.report.parent.mkdir(parents=True, exist_ok=True)
        a.report.write_text(json.dumps(report, indent=2)+'\n')
        print(mode, pattern, count, 'CPU ms', round(metrics['cpu_ms']['median'], 2), flush=True)

if __name__ == '__main__':
    main()
