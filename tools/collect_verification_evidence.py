#!/usr/bin/env python3
"""Collect bounded CI diagnostics; never consume historical outputs or caches."""
import argparse
import hashlib
import json
import platform
import os
import subprocess
from pathlib import Path

LIMIT_BYTES = 20 * 1024 * 1024
LIMIT_FILES = 500


def collect(root, destination, max_bytes=LIMIT_BYTES, max_files=LIMIT_FILES):
    root, destination = root.resolve(), destination.resolve()
    destination.mkdir(parents=True, exist_ok=False)
    manifest = dict(format=1, retained=[], omitted=[], limits=dict(bytes=max_bytes, files=max_files))
    def command(*args):
        try:
            result = subprocess.run(args, cwd=root, capture_output=True, text=True)
        except FileNotFoundError:
            return dict(exit_code=127, output='unavailable: ' + args[0])
        return dict(exit_code=result.returncode, output=(result.stdout + result.stderr).strip())
    manifest['environment'] = dict(platform=platform.platform(), python=platform.python_version(),
                                   lua=command('lua5.1', '-v'))
    manifest['ci'] = {key: os.environ.get(key) for key in
                      ('GITHUB_SHA', 'GITHUB_REF', 'GITHUB_BASE_REF', 'GITHUB_RUN_ID',
                       'GITHUB_RUN_ATTEMPT', 'RUNNER_OS', 'RUNNER_ARCH')}
    manifest['source'] = {name: command('git', 'rev-parse', ref) for name, ref in
                          [('commit', 'HEAD'), ('tree', 'HEAD^{tree}'),
                           ('fixtures', 'HEAD:tests/fixtures'), ('scenarios', 'HEAD:tools/simlab/scenarios')]}
    # The runner report carries selection, source identity, outcomes and actual artifact paths.
    # Only known diagnostic locations are allowed; never walk roots/cache/WTF/tmp or old images.
    locations = [('test-output/verification', {'.json', '.log'})]
    locations += [(p, {'.png', '.stdout', '.stderr', '.json'}) for p in
                  ('test-output/simlab/artifacts', 'test-output/simlab-workers/worker-1/artifacts',
                   'test-output/simlab-workers/worker-2/artifacts')]
    candidates = []
    for relative, suffixes in locations:
        folder = root / relative
        if not folder.exists():
            continue
        if folder.is_symlink() or not folder.resolve().is_relative_to(root):
            raise ValueError('unsafe evidence directory: ' + relative)
        for path in folder.rglob('*'):
            if path.suffix not in suffixes or not path.is_file():
                continue
            rel = path.relative_to(root)
            if 'tmp' in rel.parts:
                continue
            if any(part.is_symlink() for part in [path, *path.parents] if part != root):
                raise ValueError('symlinked evidence: ' + str(rel))
            candidates.append(path)
    # Reports first, then logs/telemetry, then PNGs. Never truncate a retained file.
    candidates.sort(key=lambda p: (0 if p.name == 'report.json' else 2 if p.suffix == '.png' else 1, str(p)))
    size = 0
    for path in candidates:
        rel = str(path.relative_to(root))
        length = path.stat().st_size
        if size + length > max_bytes or len(manifest['retained']) >= max_files:
            manifest['omitted'].append(dict(path=rel, bytes=length, reason='artifact budget'))
            continue
        data = path.read_bytes()
        if len(data) != length:
            raise ValueError('evidence changed while collecting: ' + rel)
        target = destination / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        size += length
        manifest['retained'].append(dict(path=rel, bytes=length, sha256=hashlib.sha256(data).hexdigest()))
    manifest['payload_bytes'] = size
    (destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True, help='new directory outside test-output')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.out.resolve().is_relative_to((root / 'test-output').resolve()):
        parser.error('destination must be outside test-output')
    result = collect(root, args.out)
    print(f"Evidence: {len(result['retained'])} files / {result['payload_bytes']} bytes; "
          f"{len(result['omitted'])} omitted (see manifest)")


if __name__ == '__main__':
    main()
