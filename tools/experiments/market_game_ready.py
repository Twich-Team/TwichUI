#!/usr/bin/env python3
"""Opt-in synthetic layout experiment; never discovers or writes a game install.

Run generation with the existing Market backend environment. The production
sealer validates the upstream Contract 3 fixture. Local layouts are experiments,
not negotiated contracts or a Companion implementation.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time


COUNTS = (1, 2, 4, 8, 16, 32, 64)


def canonical(v):
    return json.dumps(v, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()


def sha(v):
    return hashlib.sha256(v).hexdigest()


def literal(v):
    """Only typed atoms/arrays; no imported Lua, identifiers or expressions."""
    if v is None:
        return 'false'
    if type(v) is int and 0 <= v <= 9007199254740991:
        return str(v)
    if type(v) is str and re.fullmatch('[0-9a-f]{64}', v):
        return '"' + v + '"'
    if type(v) is list:
        return '{' + ','.join(literal(x) for x in v) + '}'
    raise ValueError('unsupported generated-source value')


def compact(row):
    values = [int(v) if type(v) is str and re.fullmatch('[1-9][0-9]{0,10}', v) else v for v in row[2:13]]
    if len(row) == 14:
        values.append([[int(v) if type(v) is str and re.fullmatch('[1-9][0-9]{0,10}', v) else v for v in day] for day in row[13]])
    return values


def tree(rows, generation, portable=False):
    size = 1 << (max(1, len(rows))-1).bit_length()
    nodes = [''] * (2*size)
    for i in range(size):
        nodes[size+i] = sha(b'row\0'+(b'' if portable else generation.encode()+b'\0')+canonical(rows[i])) if i < len(rows) else sha(b'empty\0'+(b'' if portable else generation.encode()))
    for i in range(size-1, 0, -1):
        nodes[i] = sha(b'node\0'+nodes[2*i].encode()+nodes[2*i+1].encode())
    return nodes[1:]


def source(rows, representation, generation, bucket, count):
    if representation.startswith('fixed-'):
        from market_fixed_records import encode_rows
        payload='"'+encode_rows(rows)+'"'
    elif representation == 'json':
        # Matches native export::literal: every byte is a three-digit escape.
        raw = canonical(rows)
        payload = '"' + ''.join('\\%03d' % b for b in raw) + '"'
    elif representation in ('array', 'verified-array', 'proof', 'hybrid', 'packed-proof', 'packed-hybrid', 'fixed-proof', 'fixed-hybrid'):
        payload = '{' + ','.join(literal([r[0], r[1], *compact(r)]) for r in rows) + '}'
    elif representation == 'index':
        items = {}
        for r in rows:
            items.setdefault(r[0], []).append(r)
        payload = '{' + ','.join('[' + literal(item) + ']={' + ','.join(
            '[' + literal(r[1]) + ']=' + literal(compact(r)) for r in group) + '}' for item, group in items.items()) + '}'
    else:
        raise ValueError(representation)
    suffix = ''
    if representation in ('proof','hybrid','packed-proof','packed-hybrid','fixed-proof','fixed-hybrid'):
        nodes=tree(rows,generation,representation.startswith(('packed-','fixed-')))
        # Fixed-width hexadecimal SHA words, not a parser/compression scheme.
        suffix=',' + ('"'+''.join(nodes)+'"' if representation.startswith(('packed-','fixed-')) else literal(nodes))
    return ('return{' + ','.join((literal(1), literal(sha(canonical(rows)) if representation.startswith(('packed-','fixed-')) else generation), literal(bucket), literal(count), payload)) + suffix + '}\n').encode()


def build(market, destination, records, days, profile, counts=COUNTS):
    if destination.exists():
        raise ValueError('a new disposable destination is required')
    sys.path.insert(0, str(market / 'backend'))
    os.environ.setdefault('DATABASE_URL', 'sqlite://')
    from market import workshop_summary as producer
    original = json.loads((market / 'contracts/workshop-summary/v3/fixtures/synthetic.json').read_text())['manifest']
    metadata = {k: original[k] for k in ('issuer_id', 'market', 'pricing_algorithm', 'history_basis', 'source_kind', 'source_watermark', 'source_observation', 'generated_at', 'synthetic', 'observations')}
    from datetime import datetime, timedelta, timezone
    end = datetime.fromisoformat(metadata['generated_at'].replace('Z', '+00:00'))
    metadata['observations'] = [dict(observation_id=str(903-days+i), observed_at=(end-timedelta(days=days-1-i)).strftime('%Y-%m-%dT%H:%M:%SZ'), scope_complete=True, synthetic=False) for i in range(days)]
    # Admission exercise only, like the existing cold benchmark. Always mark the
    # surrounding experiment synthetic; no genuine source records are used.
    metadata['synthetic'] = False
    metadata['source_observation'] = {k: metadata['observations'][-1][k] for k in ('observation_id', 'observed_at', 'scope_complete')}
    metadata['source_watermark'] = '902'
    rows = []
    base_count = max(160, records * 9 // 10)
    for i in range(records):
        item = 64+i if i < base_count else 65 + (i-base_count) % 128
        if profile == 'skew' and base_count <= i < base_count+min(384, records-base_count):
            item = 65
        variant = sha(canonical({'id': item})) if i < base_count else sha(('variant:' + str(i)).encode())
        price = 1000 + item % 997
        missing = item % 29 == 0
        row = [item, variant, 2 if missing else 0, None if missing else str(price), None if missing else str(price+3),
               None if missing else str(price-5), 0 if missing else 5, 0, int(missing),
               str(price+7) if days >= 3 and not missing else None, 0 if missing else min(days, 14), 0 if missing else days, days]
        row.append([[2, None, None, 0] if missing else [0, str(price), str(price-5), 5] for _ in range(days)])
        rows.append(row)
    rows.sort(key=lambda r: (r[0], r[1]))
    at = time.process_time()
    h, parts = producer.seal_split(metadata, rows)
    producer_ms = (time.process_time()-at)*1000
    destination.mkdir(parents=True)
    (destination/'upstream.json').write_bytes(canonical({'manifest': h, 'parts': {str(k): v.decode() for k, v in parts.items()}}))
    results = []
    for count in counts:
        buckets = [[] for _ in range(count)]
        for r in rows:
            buckets[r[0] % count].append(r)
        for representation in ('json', 'array', 'index', 'verified-array', 'proof', 'hybrid', 'packed-proof', 'packed-hybrid', 'fixed-proof', 'fixed-hybrid'):
            for projection in ('current', 'history'):
                if representation.startswith('fixed-') and projection=='history':continue
                folder = destination / f'{representation}-{projection}-{count}'
                folder.mkdir()
                descriptors = []
                gen_start = time.process_time()
                for b, group in enumerate(buckets):
                    group = [r[:13] if projection == 'current' else r for r in group]
                    data = source(group, representation, h['generation_id'], b, count)
                    raw = canonical(group)
                    descriptors.append(dict(bucket=b, bytes=len(raw), sha256=sha(raw), source_bytes=len(data), source_sha256=sha(data), record_count=len(group)))
                    if representation in ('proof','hybrid','packed-proof','packed-hybrid','fixed-proof','fixed-hybrid'):
                        descriptors[-1]['merkle_root'] = tree(group, h['generation_id'], representation.startswith(('packed-','fixed-')))[0]
                    (folder/f'{b:02}.lua').write_bytes(data)
                generation_ms = (time.process_time()-gen_start)*1000
                results.append(dict(count=count, representation=representation, projection=projection, generation_cpu_us=round(generation_ms*1000),
                    total_source_bytes=sum(d['source_bytes'] for d in descriptors), total_raw_bytes=sum(d['bytes'] for d in descriptors),
                    max_source_bytes=max(d['source_bytes'] for d in descriptors), max_raw_bytes=max(d['bytes'] for d in descriptors),
                    descriptors=descriptors))
    report = dict(synthetic=True, native=False, records=records, unique_items=len({r[0] for r in rows}), history_days=days,
                  profile=profile, semantic_sha256=sha(canonical(rows)), manifest=h, producer_cpu_us=round(producer_ms*1000), layouts=results)
    (destination/'fixture.json').write_bytes(canonical(report))
    return report


def add_controls(destination):
    """Upgrade an ignored experiment fixture generated before proof controls."""
    report = json.loads((destination/'fixture.json').read_text())
    upstream = json.loads((destination/'upstream.json').read_text())
    parts = upstream['parts']
    for count in COUNTS:
        for projection in ('current', 'history'):
            rows = sorted((r for k, raw in parts.items() if (int(k) < 64) == (projection == 'current') for r in json.loads(raw)), key=lambda r: (r[0], r[1]))
            groups = [[] for _ in range(count)]
            for r in rows:
                groups[r[0] % count].append(r)
            for representation in ('verified-array', 'proof', 'hybrid', 'packed-proof', 'packed-hybrid', 'fixed-proof', 'fixed-hybrid'):
                if representation.startswith('fixed-') and projection=='history':continue
                exists=any(x['count']==count and x['projection']==projection and x['representation']==representation for x in report['layouts'])
                if exists and not representation.startswith(('packed-','fixed-')):continue
                if exists:report['layouts']=[x for x in report['layouts']if not(x['count']==count and x['projection']==projection and x['representation']==representation)]
                folder=destination/f'{representation}-{projection}-{count}';folder.mkdir(exist_ok=representation.startswith(('packed-','fixed-')))
                start=time.process_time();descriptors=[]
                for b, group in enumerate(groups):
                    data=source(group,representation,report['manifest']['generation_id'],b,count);raw=canonical(group)
                    descriptors.append(dict(bucket=b,bytes=len(raw),sha256=sha(raw),source_bytes=len(data),source_sha256=sha(data),record_count=len(group)))
                    if representation in ('proof','hybrid','packed-proof','packed-hybrid','fixed-proof','fixed-hybrid'):descriptors[-1]['merkle_root']=tree(group,report['manifest']['generation_id'],representation.startswith(('packed-','fixed-')))[0]
                    (folder/f'{b:02}.lua').write_bytes(data)
                report['layouts'].append(dict(count=count,representation=representation,projection=projection,generation_cpu_us=round((time.process_time()-start)*1e6),
                    total_source_bytes=sum(d['source_bytes']for d in descriptors),total_raw_bytes=sum(d['bytes']for d in descriptors),
                    max_source_bytes=max(d['source_bytes']for d in descriptors),max_raw_bytes=max(d['bytes']for d in descriptors),descriptors=descriptors))
    (destination/'fixture.json').write_bytes(canonical(report))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--market-root', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--records', type=int, default=16384)
    p.add_argument('--days', type=int, choices=(2, 60), default=2)
    p.add_argument('--profile', choices=('mixed', 'skew'), default='mixed')
    a = p.parse_args()
    if not 256 <= a.records <= 32768:
        p.error('bounded experiment: 256..32768 records')
    r = build(a.market_root.resolve(), a.out.resolve(), a.records, a.days, a.profile)
    print(json.dumps({k: r[k] for k in ('records', 'unique_items', 'history_days', 'profile', 'semantic_sha256', 'producer_cpu_us')}))


if __name__ == '__main__':
    main()
