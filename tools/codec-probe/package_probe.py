#!/usr/bin/env python3
"""Package only the removable DEV addon; never a TwichUI release artifact."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile
from generate_vectors import make

ROOT = Path(__file__).resolve().parents[2]
ADDON = Path(__file__).resolve().parent / 'TwichUI_CodecProbe'
FILES = ('TwichUI_CodecProbe.toc', 'Vectors.lua', 'Engine.lua', 'Probe.lua', 'Build.lua')


def write_package(out, source, vectors, manifest):
    assert re.fullmatch('[0-9a-f]{40}', source)
    raw = {n: (vectors if n == 'Vectors.lua' else ADDON / n).read_bytes() for n in FILES if n != 'Build.lua'}
    hashes = {n: hashlib.sha256(data).hexdigest() for n, data in raw.items()}
    generator_sha = hashlib.sha256((ADDON.parent / 'generate_vectors.py').read_bytes()).hexdigest()
    build = 'local _, P = ...\nP.Build = { kind="development-only", format=1, commit="' + source + '", '
    build += 'generator_sha256=' + json.dumps(generator_sha) + ', zlib_runtime=' + json.dumps(manifest['zlib_runtime']) + ', files={\n'
    build += ''.join(f'  [{json.dumps(k)}]={json.dumps(v)},\n' for k, v in hashes.items()) + '} }\n'
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name in FILES:
            value = build.encode() if name == 'Build.lua' else raw[name]
            info = zipfile.ZipInfo('TwichUI_CodecProbe/' + name, (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, value)
    with zipfile.ZipFile(out) as archive:
        assert archive.testzip() is None
        assert set(archive.namelist()) == {'TwichUI_CodecProbe/' + x for x in FILES}
    result = {'kind': 'development-only', 'source_commit': source, 'zip_bytes': out.stat().st_size,
              'zip_sha256': hashlib.sha256(out.read_bytes()).hexdigest(), 'files_sha256': hashes,
              'fixture_generator_sha256': generator_sha,
              'zlib_runtime': manifest['zlib_runtime'],
              'real_game_executed': False}
    out.with_suffix('.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def package(out, source):
    with tempfile.TemporaryDirectory(prefix='codec-probe-vectors-') as directory:
        destination = Path(directory)
        manifest = make(destination)
        return write_package(out, source, destination / 'Vectors.lua', manifest)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out', type=Path, required=True)
    args = p.parse_args()
    assert not args.out.exists() and not args.out.with_suffix('.json').exists(), 'Preserve existing artifacts; use a new output path'
    assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip(), 'Commit verified source before packaging'
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    print(json.dumps(package(args.out, source), indent=2))
