#!/usr/bin/env python3
"""Separate synthetic producer, reference transform and durable filesystem costs.

Not the Windows Companion, HTTP throughput or production A/B publisher. All writes
are to a new TemporaryDirectory; no game discovery or live configuration access.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import sys
import tempfile
import time

from market_game_ready import canonical, source


def atomic(path, data):
    path.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent,delete=False)as f:
        name=f.name;f.write(data);f.flush();os.fsync(f.fileno())
    os.replace(name,path)
    fd=os.open(path.parent,os.O_RDONLY)
    try:os.fsync(fd)
    finally:os.close(fd)
    assert path.read_bytes()==data


def metrics(samples):
    return {k:dict(median=statistics.median(s[k]for s in samples),minimum=min(s[k]for s in samples),maximum=max(s[k]for s in samples))for k in samples[0]}


def run(market,fixture,reps):
    os.environ.setdefault('DATABASE_URL','sqlite://');sys.path.insert(0,str(market/'backend'))
    from market import workshop_summary as producer
    f=json.loads((fixture/'upstream.json').read_text());h=f['manifest']
    rows=sorted((r for key,raw in f['parts'].items()if int(key)>=64 for r in json.loads(raw)),key=lambda r:(r[0],r[1]))
    keys=('issuer_id','market','pricing_algorithm','history_basis','source_kind','source_watermark','source_observation','generated_at','synthetic','observations')
    metadata={k:h[k]for k in keys};seals=[]
    for i in range(reps+1):
        cpu=time.process_time();wall=time.perf_counter();new,parts=producer.seal_split(metadata,rows)
        elapsed=dict(cpu_ms=(time.process_time()-cpu)*1000,elapsed_ms=(time.perf_counter()-wall)*1000)
        assert new==h and all(parts[int(k)].decode()==raw for k,raw in f['parts'].items())
        if i:seals.append(elapsed)
    report=dict(synthetic=True,real_client=False,network_measured=False,windows_measured=False,fixture=str(fixture),source_generation=h['generation_id'],
        producer=dict(samples=seals,metrics=metrics(seals)),layouts=[])
    for current,history,rep in [(64,64,'json'),(8,32,'fixed-hybrid'),(16,32,'fixed-hybrid'),(16,64,'fixed-hybrid'),(32,32,'fixed-hybrid'),(32,64,'fixed-hybrid')]:
        transforms=[];publications=[];source_files=[]
        for i in range(reps+1):
            cpu=time.process_time();wall=time.perf_counter();source_files=[]
            for projection,count,representation in [('current',current,rep),('history',history,'json')]:
                buckets=[[]for _ in range(count)]
                for r in rows:buckets[r[0]%count].append(r[:13]if projection=='current'else r)
                for b,group in enumerate(buckets):
                    source_files.append((f'{projection}-{b:02}',source(group,representation,h['generation_id'],b,count)))
            transform=dict(cpu_ms=(time.process_time()-cpu)*1000,elapsed_ms=(time.perf_counter()-wall)*1000)
            if i:transforms.append(transform)
            cpu=time.process_time();wall=time.perf_counter()
            with tempfile.TemporaryDirectory(prefix='game-ready-durable-')as temp:
                base=Path(temp)
                for folder,data in source_files:
                    atomic(base/folder/'Data.lua',data)
                    atomic(base/folder/'Fixture.toc',b'## LoadOnDemand: 1\nData.lua\n')
                    atomic(base/folder/'.owner.json',b'{"synthetic":true}\n')
                # A single root pointer last; this is I/O timing, not a claim
                # of equivalent ownership, rollback or reader validation.
                atomic(base/'root.json',canonical(dict(generation=h['generation_id'],current=current,history=history)))
                publication=dict(cpu_ms=(time.process_time()-cpu)*1000,elapsed_ms=(time.perf_counter()-wall)*1000)
            if i:publications.append(publication)
        report['layouts'].append(dict(current=current,history=history,representation=rep,folders_two_banks=2*(current+history)+1,
            source_bytes_one_bank=sum(len(data)for _,data in source_files),writes_one_bank=3*(current+history)+1,
            transform=dict(samples=transforms,metrics=metrics(transforms)),durable_publication=dict(samples=publications,metrics=metrics(publications))))
    return report


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--market-root',type=Path,required=True);p.add_argument('--fixture',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True);p.add_argument('--reps',type=int,choices=range(1,6),default=3)
    a=p.parse_args();r=run(a.market_root.resolve(),a.fixture.resolve(),a.reps)
    r['tool_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(r,indent=2)+'\n')
    print(json.dumps(r['producer']['metrics']),flush=True)


if __name__=='__main__':main()
