#!/usr/bin/env python3
"""Fetch one immutable Actions candidate and promote it through the existing publisher.

Invoked only by the main-only manual workflow. Standard library, no rebuilding.
The read-only preflight and protected publishing job repeat the same validation.
"""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
import release as rel


def artifact_record(artifact, run, requested, now=None):
    now = now or dt.datetime.now(dt.timezone.utc)
    if artifact.get('id') != int(requested['artifact_id']) or artifact.get('expired') is not False:
        raise rel.ReleaseError('candidate artifact is missing or expired')
    try:
        expires = dt.datetime.fromisoformat(artifact['expires_at'].replace('Z', '+00:00'))
        created = dt.datetime.fromisoformat(artifact['created_at'].replace('Z', '+00:00'))
    except (KeyError, ValueError, TypeError) as exc:
        raise rel.ReleaseError('artifact timestamps are missing or invalid') from exc
    if expires <= now or created > now or now - created > dt.timedelta(days=30):
        raise rel.ReleaseError('candidate artifact is stale or expired')
    origin = artifact.get('workflow_run', {})
    if (run.get('id') != origin.get('id') or run.get('head_sha') != origin.get('head_sha') or
            run.get('path') != '.github/workflows/release-candidate.yml' or
            run.get('event') != 'workflow_dispatch' or run.get('head_branch') != 'main' or
            run.get('status') != 'completed' or run.get('conclusion') != 'success'):
        raise rel.ReleaseError('artifact must come from a successful main-only candidate workflow')
    if not artifact.get('name', '').startswith('candidate-' + requested['source'] + '-'):
        raise rel.ReleaseError('artifact name/source provenance mismatch')


def unpack_candidate(container, target):
    with zipfile.ZipFile(container) as archive:
        names = archive.namelist()
        if (len(names) != 3 or len(set(names)) != 3 or
                any(Path(n).name != n or '\\' in n for n in names) or
                'meta.json' not in names or 'notes.md' not in names or
                sum(n.endswith('.zip') for n in names) != 1 or
                sum(i.file_size for i in archive.infolist()) > 256 * 1024 * 1024):
            raise rel.ReleaseError('unexpected candidate artifact layout/size')
        # Write only flat regular files; never honor archive paths, symlinks or permissions.
        for name in names:
            (target / name).write_bytes(archive.read(name))
    return next(target.glob('*.zip'))


def protected_tag(gh, meta):
    if meta['channel'] != 'release':
        return
    tag = meta['tag']
    ref = gh._gh([f'repos/{gh.repo}/git/ref/tags/{tag}']) or {}
    if ref.get('object', {}).get('type') != 'tag' or gh.tag_commit(tag) != meta['commit']:
        raise rel.ReleaseError('stable/hotfix requires an existing annotated tag on the exact candidate source')
    policies = gh._gh([f'repos/{gh.repo}/rulesets?includes_parents=true']) or []
    for policy in policies:
        rule = gh._gh([f'repos/{gh.repo}/rulesets/{policy["id"]}']) or {}
        names = rule.get('conditions', {}).get('ref_name', {})
        if (rule.get('target') == 'tag' and rule.get('enforcement') == 'active' and
                names.get('include') == ['refs/tags/v*'] and not names.get('exclude') and
                {'update', 'deletion'} <= {r['type'] for r in rule.get('rules', [])} and
                not rule.get('bypass_actors')):
            return
    raise rel.ReleaseError('stable tags require an active v* update/deletion ruleset without bypass actors')


def prepare(gh, requested, actor, target):
    if not re.fullmatch(r'[1-9][0-9]*', requested['artifact_id']):
        raise rel.ReleaseError('invalid artifact ID')
    if not re.fullmatch(r'[0-9a-f]{40}', requested['source']) or not re.fullmatch(r'[0-9a-f]{64}', requested['sha256']):
        raise rel.ReleaseError('full source SHA and SHA256 required')
    permission = gh._gh([f'repos/{gh.repo}/collaborators/{actor}/permission']) or {}
    if permission.get('permission') not in ('admin', 'maintain', 'write'):
        raise rel.ReleaseError('only an authorized maintainer can request promotion')
    if not (gh._gh([f'repos/{gh.repo}/branches/main']) or {}).get('protected'):
        raise rel.ReleaseError('main must be protected before promotion')
    environment = gh._gh([f'repos/{gh.repo}/environments/release']) or {}
    local_policy = json.loads((rel.REPO_ROOT / ".github/release-policy.json").read_text())
    rel.validate_environment(environment, local_policy)
    artifact = gh._gh([f'repos/{gh.repo}/actions/artifacts/{requested["artifact_id"]}']) or {}
    run_id = artifact.get('workflow_run', {}).get('id')
    run = gh._gh([f'repos/{gh.repo}/actions/runs/{run_id}']) or {}
    artifact_record(artifact, run, requested)
    container = target / 'download.zip'
    with container.open('wb') as stream:
        result = subprocess.run(['gh', 'api', f'repos/{gh.repo}/actions/artifacts/{requested["artifact_id"]}/zip'],
                                stdout=stream, stderr=subprocess.PIPE)
    if result.returncode:
        raise rel.ReleaseError('candidate download failed; missing/expired artifacts must never be rebuilt in promotion')
    payload = target / 'payload'
    payload.mkdir()
    candidate = unpack_candidate(container, payload)
    meta = json.loads((payload / 'meta.json').read_text())
    notes = (payload / 'notes.md').read_text(encoding='utf-8')
    # Reviewed evidence is code-reviewed on main, not supplied inside an untrusted artifact.
    ledger = rel.REPO_ROOT / 'docs/releases' / (requested['sha256'] + '.json')
    if not ledger.is_file():
        raise rel.ReleaseError('reviewed exact-candidate evidence is missing from main')
    evidence = json.loads(ledger.read_text())
    rel.validate_promotion(meta, candidate, notes, requested, evidence)
    protected_tag(gh, meta)
    # Reject versions older than any existing public stable release. Preserve historical records.
    history = gh.releases()
    current = [rel.version_of(m) for r in history if not r.get('draft') and
               (m := rel.STABLE_TAG.fullmatch(r.get('tag_name', '')))]
    match = rel.STABLE_TAG.fullmatch(meta['tag']) or rel.PRE_TAG.fullmatch(meta['tag'])
    if not match or (current and (rel.version_of(match) < max(current) or
                                  (meta['channel'] != 'release' and rel.version_of(match) == max(current)))):
        raise rel.ReleaseError('candidate is superseded by public stable history')
    if meta.get('release_kind') == 'hotfix':
        base = meta.get('hotfix_base', '')
        base_version = rel.STABLE_TAG.fullmatch(base)
        if (not base_version or not any(r.get('tag_name') == base and not r.get('draft') and
                                       not r.get('prerelease') for r in history)):
            raise rel.ReleaseError('hotfix base must be a published stable release')
        major, minor, patch = rel.version_of(base_version)
        if rel.version_of(match) != (major, minor, patch + 1):
            raise rel.ReleaseError('hotfix must advance its released line by one patch')
    return meta, candidate, notes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for field in ('artifact-id', 'source', 'version', 'channel', 'sha256', 'repo', 'actor'):
        parser.add_argument('--' + field, required=True)
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    try:
        if os.environ.get('GITHUB_EVENT_NAME') != 'workflow_dispatch' or os.environ.get('GITHUB_REF') != 'refs/heads/main':
            raise rel.ReleaseError('promotion runs only from manual dispatch on main')
        requested = {k: getattr(args, k) for k in ('artifact_id', 'source', 'version', 'channel', 'sha256')}
        gh = rel.GitHub(args.repo)
        with tempfile.TemporaryDirectory() as directory:
            meta, candidate, notes = prepare(gh, requested, args.actor, Path(directory))
            # Latest main policy prevents a hold restored during approval from being bypassed.
            policy = gh._gh([f'repos/{args.repo}/contents/.github/release-policy.json?ref=main']) or {}
            import base64
            enabled = json.loads(base64.b64decode(policy.get('content', '')).decode()).get('publication_enabled') is True
            summary = json.dumps({'promotion': requested, 'publication_enabled': enabled}, indent=2)
            print(summary)
            if os.environ.get('GITHUB_STEP_SUMMARY'):
                with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as stream:
                    stream.write('### Exact candidate for protected manual release approval\n```json\n' + summary + '\n```\n')
            if os.environ.get('GITHUB_OUTPUT'):
                with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
                    stream.write('enabled=' + str(enabled).lower() + '\n')
            if args.publish:
                if not enabled or not rel.publication_enabled():
                    raise rel.ReleaseError('publication is held; no upload attempted')
                token = os.environ.get('CF_API_KEY')
                if not token:
                    raise rel.ReleaseError('protected environment CF_API_KEY is missing')
                with zipfile.ZipFile(candidate) as archive:
                    project = rel.toc_field(archive.read(rel.TOCS[rel.CORE]).decode(), 'X-Curse-Project-ID')
                rel.publish(meta, candidate, notes, gh, rel.CurseForge(token, project))
        return 0
    except (rel.ReleaseError, ValueError, KeyError, OSError, zipfile.BadZipFile) as exc:
        print('::error::' + str(exc))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
