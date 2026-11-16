#!/usr/bin/env python3
"""Compile only pinned, trusted JSON schemas into Lua data. No runtime schema fetching."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
V1 = ROOT / 'tests/fixtures/market_bridge_v1'
SCOPED = ROOT / 'tests/fixtures/market_bridge_scoped_l1'
FILES = [V1 / 'generation.schema.json', V1 / 'generation-schema2.schema.json', SCOPED / 'generation-schema3.schema.json']

def plans():
    resources = [json.loads(p.read_text()) for p in FILES + [SCOPED / 'selection.schema.json']]
    by_id = {p['$id']: p for p in resources}
    def expand(value):
        if isinstance(value, list): return [expand(x) for x in value]
        if not isinstance(value, dict): return value
        if '$ref' in value:
            uri, _, pointer = value['$ref'].partition('#')
            result = by_id[uri]
            for part in pointer.lstrip('/').split('/') if pointer else []:
                result = result[part.replace('~1', '/').replace('~0', '~')]
            return expand(result)
        return {k: expand(v) for k, v in value.items()}
    return [expand(r) for r in resources[:3]]

def lua(value):
    if value is None: return 'J.NULL'
    if isinstance(value, bool): return 'true' if value else 'false'
    if isinstance(value, int): return str(value)
    if isinstance(value, str): return json.dumps(value, ensure_ascii=True)
    if isinstance(value, list): return 'setmetatable({' + ','.join(lua(v) for v in value) + '},J.ARRAY)'
    return 'setmetatable({' + ','.join('[' + lua(k) + ']=' + lua(value[k]) for k in sorted(value)) + '},J.OBJECT)'

def render():
    lines = ['-- Generated from pinned trusted Market schemas. Regenerate; never edit independently.', 'local W=TwichUI.Workshop', 'local J=W.BridgeCodec', 'W.BridgeSchemas={']
    for version, (path, plan) in enumerate(zip(FILES, plans()), 1):
        lines += ['-- ' + path.name + ' SHA256 ' + hashlib.sha256(path.read_bytes()).hexdigest(), '[' + str(version) + ']=' + lua(plan) + ',']
    return '\n'.join(lines + ['}', ''])

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    target = ROOT / 'TwichUI_Workshop/BridgeSchema.lua'
    if args.check:
        if target.read_text() != render(): raise SystemExit('BridgeSchema.lua differs from pinned schemas; regenerate')
    else: target.write_text(render())
