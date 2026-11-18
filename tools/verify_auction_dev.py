#!/usr/bin/env python3
"""Verify an AH development archive against exact committed source bytes."""
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


def verify(repo, archive, commit):
    actual = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD']).decode().strip()
    if actual != commit:
        raise ValueError('Source checkout does not match requested commit')
    expected = {}
    raw = subprocess.check_output(['git', '-C', str(repo), 'archive', commit])
    with tarfile.open(fileobj=io.BytesIO(raw), mode='r:') as source:
        for entry in source.getmembers():
            if entry.isfile() and (entry.name.split('/')[0] in ADDONS or entry.name in (GUIDE, 'LICENSE', 'LICENSE.md')):
                expected[entry.name] = source.extractfile(entry).read()
    original = expected[MARKER]
    if original.count(b'development = false') != 1 or b'verified = {}' not in original:
        raise ValueError('Unexpected source marker or transaction gates')
    expected[MARKER] = original.replace(b'development = false', b'development = true')
    expected['AUCTION-HOUSE-START-HERE.txt'] = expected.pop(GUIDE)
    with zipfile.ZipFile(archive) as bundle:
        names = bundle.namelist()
        if len(names) != len(set(names)) or set(names) != set(expected) | {'AUCTION-HOUSE-BUILD.json'}:
            raise ValueError('Unexpected, missing or duplicate archive entries')
        manifest = json.loads(bundle.read('AUCTION-HOUSE-BUILD.json'))
        if manifest['source_commit'] != commit or manifest['native_transaction_modes_enabled'] != []:
            raise ValueError('Incorrect source identity or enabled native transactions')
        transformation = [{'path': MARKER, 'change': 'development = false -> true',
                           'source_sha256': hashlib.sha256(original).hexdigest()}]
        if manifest['source_transformations'] != transformation:
            raise ValueError('Unexpected source transformations')
        hashes = {name: hashlib.sha256(data).hexdigest() for name, data in expected.items()}
        if manifest['files'] != hashes:
            raise ValueError('Manifest file set or hashes differ from committed source')
        for name, data in expected.items():
            if bundle.read(name) != data:
                raise ValueError('Archive bytes differ from source: '+name)
        for addon in ADDONS:
            if f'{addon}/{addon}.toc' not in expected:
                raise ValueError('Missing addon: '+addon)
    return dict(source_commit=commit, sha256=hashlib.sha256(Path(archive).read_bytes()).hexdigest(),
                entries=len(names), addons=list(ADDONS), development_marker=True,
                native_transaction_modes_enabled=[], verified=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--zip', type=Path, required=True)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    print(json.dumps(verify(args.repo, args.zip, args.commit), indent=2))
