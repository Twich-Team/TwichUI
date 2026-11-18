#!/usr/bin/env python3
"""Build a private AH development ZIP from clean, committed source; never publish."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import zipfile

ADDONS = ('!!!TwichUI', 'TwichUI_Settings', 'TwichUI_Workshop', 'TwichUI_Diagnostics',
          'TwichUI_NavData', 'TwichUI_Layouts', 'TwichUI_LayoutWizard', 'TwichUI_TestLab')
MARKER = '!!!TwichUI/auction/Build.lua'
GUIDE = 'docs/workshop/auction-house/development-test.md'


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def build(repo, output):
    repo, output = Path(repo).resolve(), Path(output).resolve()
    if git(repo, 'status', '--porcelain').strip():
        raise ValueError('Commit the source first: development archives require a clean tree.')
    commit = git(repo, 'rev-parse', 'HEAD').decode().strip()
    files = {}
    with tarfile.open(fileobj=io.BytesIO(git(repo, 'archive', 'HEAD')), mode='r:') as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue
            name = member.name
            if name.split('/')[0] in ADDONS or name in (GUIDE, 'LICENSE', 'LICENSE.md'):
                files[name] = archive.extractfile(member).read()
    for addon in ADDONS:
        if f'{addon}/{addon}.toc' not in files:
            raise ValueError(f'Missing addon manifest: {addon}')
    source = files[MARKER]
    if source.count(b'development = false') != 1 or b'verified = {}' not in source:
        raise ValueError('Unexpected development marker or native activation gates.')
    files[MARKER] = source.replace(b'development = false', b'development = true')
    files['AUCTION-HOUSE-START-HERE.txt'] = files.pop(GUIDE)
    manifest = dict(source_commit=commit, build='private-auction-development',
                    source_transformations=[dict(path=MARKER, change='development = false -> true',
                                                source_sha256=hashlib.sha256(source).hexdigest())],
                    native_transaction_modes_enabled=[],
                    files={name: hashlib.sha256(data).hexdigest() for name, data in sorted(files.items())})
    files['AUCTION-HOUSE-BUILD.json'] = (json.dumps(manifest, indent=2, sort_keys=True)+'\n').encode()
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED)
    with zipfile.ZipFile(output) as archive:
        if set(archive.namelist()) != set(files) or any(archive.read(n) != d for n, d in files.items()):
            raise ValueError('Archive verification failed.')
    return dict(path=str(output), source_commit=commit, entries=len(files),
                sha256=hashlib.sha256(output.read_bytes()).hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.repo, args.output), indent=2))
