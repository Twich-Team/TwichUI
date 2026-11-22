#!/usr/bin/env python3
"""Opt-in campaign over the existing Opportunities benchmark; no default CI work."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[2]
FILES=('tests/bench_market_opportunities.lua','tests/bench_market_game_ready.lua','tools/experiments/market_game_ready.py',
       'tools/experiments/measure_game_ready.py','tools/experiments/market_fixed_records.py','tests/market_fixed_records.lua','TwichUI_Workshop/Summary.lua','TwichUI_Workshop/BridgeCodec.lua','TwichUI_Workshop/Pricing.lua','TwichUI_Workshop/OpportunityEngine.lua')


def identity():
    return {p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest()for p in FILES}


def run(fixture, output, recipes, counts, representations, reps, history, native_cohort=False, scenario='none',history_item=1001):
    meta=json.loads((fixture/'fixture.json').read_text())
    start_identity=identity()
    report=dict(synthetic=True,real_client=False,host=platform.platform(),machine=platform.machine(),python=platform.python_version(),
        addon_source=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),sources=start_identity,
        fixture_sha256=hashlib.sha256((fixture/'fixture.json').read_bytes()).hexdigest(),semantic_sha256=meta['semantic_sha256'],
        fixture=str(fixture),records=meta['records'],history_days=meta['history_days'],profile=meta['profile'],
        clock='Lua os.clock CPU; Python perf_counter process elapsed; modeled 60Hz minimum After; warm OS file cache, cold Lua process',
        repeats=reps,discarded_warmups=1,native_cohort=native_cohort,scenario=scenario,history_item=history_item,cases=[])
    def save():
        output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2)+'\n')
    with tempfile.TemporaryDirectory(prefix='game-ready-config-')as temp:
        for count in counts:
            for representation in representations:
                layouts=[l for l in meta['layouts']if l['count']==count and l['representation']==representation]
                assert len(layouts)==(1 if representation.startswith('fixed-')else 2)
                invalid=[l['projection']for l in layouts if representation=='json' and l['max_raw_bytes']>1048576]
                for n in recipes:
                    case=dict(partitions=count,representation=representation,recipes=n,history_probe=history,layouts=layouts)
                    if invalid:
                        case.update(status='rejected-current-contract-bound',projections=invalid);report['cases'].append(case);save();continue
                    if any(l['max_source_bytes']>(8 if representation.startswith('fixed-')else 4)*1024*1024 for l in layouts if l['projection']=='current' or history):
                        case.update(status='not-measured-source-safety-cap',source_safety_cap_bytes=(8 if representation.startswith('fixed-')else 4)*1024*1024);report['cases'].append(case);save();continue
                    if history and representation in ('proof','hybrid','packed-proof','packed-hybrid','fixed-proof','fixed-hybrid'):
                        case.update(status='not-implemented-history-proof');report['cases'].append(case);save();continue
                    config=Path(temp)/'case.json';config.write_text(json.dumps(dict(root=str(fixture),representation=representation,count=count,history_count=count,history_probe=history,native_cohort=native_cohort,history_item=history_item)))
                    samples=[]
                    for repeat in range(reps+1):
                        command=['lua5.1','tests/bench_market_opportunities.lua','opps','session',str(n),str(meta['history_days']),'3','1','off',scenario,'off','20','tests/bench_market_game_ready.lua',str(config)]
                        snapshot=Path(temp)/'oracle.bin';env=dict(os.environ,BENCH_ORACLE_SNAPSHOT=str(snapshot))
                        began=time.perf_counter();p=subprocess.run(command,cwd=ROOT,text=True,capture_output=True,timeout=300,env=env)
                        if p.returncode:
                            case.update(status='failed',stderr=p.stderr,returncode=p.returncode);break
                        row=json.loads(p.stdout);row['process_elapsed_seconds']=time.perf_counter()-began
                        row['result_sha256']=hashlib.sha256(snapshot.read_bytes()).hexdigest()
                        assert row['oracle_passed']and row['semantic_fixture_sha256']==meta['semantic_sha256']
                        assert row['warm_crafts']==0 and row['warm_record_calls']==0 and row['warm_estimator_reused']
                        if repeat:samples.append(row)
                    else:
                        case.update(status='measured',samples=samples,metrics={k:dict(median=statistics.median(s[k]for s in samples),minimum=min(s[k]for s in samples),maximum=max(s[k]for s in samples))
                            for k,v in samples[0].items()if type(v)in(int,float)})
                    report['cases'].append(case);save()
                    print(n,count,representation,case['status'],round(case.get('metrics',{}).get('cpu_ms',{}).get('median',0),2),flush=True)
    report['source_unchanged']=start_identity==identity();assert report['source_unchanged']
    # Economic checksums must agree across representations/counts for each input.
    hashes={}
    for case in report['cases']:
        if case['status']=='measured':
            key=case['recipes'];values={s['result_sha256']for s in case['samples']}
            assert len(values)==1
            if key in hashes:assert hashes[key]==values
            hashes[key]=values
    report['economic_results_equal']=True;save()
    if any(c['status']=='failed'for c in report['cases']):raise SystemExit('one or more measured cases failed; inspect report')
    return report


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--fixture',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
    p.add_argument('--recipes',type=int,nargs='+',default=[120])
    p.add_argument('--counts',type=int,nargs='+',choices=[1,2,4,8,16,32,64],default=[1,2,4,8,16,32,64])
    p.add_argument('--representations',nargs='+',choices=['json','array','index','verified-array','proof','hybrid','packed-proof','packed-hybrid','fixed-proof','fixed-hybrid'],default=['json','array','index','verified-array','proof','hybrid','packed-proof','packed-hybrid','fixed-proof','fixed-hybrid'])
    p.add_argument('--reps',type=int,choices=range(1,6),default=3);p.add_argument('--history',action='store_true')
    p.add_argument('--native-cohort',action='store_true',help='158 distinct references / 58 buckets at 120 recipes')
    p.add_argument('--scenario',choices=['none','reopen'],default='none')
    p.add_argument('--history-item',type=int,default=1001)
    a=p.parse_args();run(a.fixture.resolve(),a.report.resolve(),a.recipes,a.counts,a.representations,a.reps,a.history,a.native_cohort,a.scenario,a.history_item)


if __name__=='__main__':main()
