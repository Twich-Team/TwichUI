"""Candidate/promotion policy and mocked immutable Actions transport; no live publishing."""
import datetime as dt
import json
import base64
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'tools'))
import release as rel
import release_promotion as promotion
import test_release_tools as fixtures


class CandidateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = fixtures.Repo(self.tmp.name)
        self.repo.commit('first')
        self.repo.tag('v1.2.2')
        self.source = self.repo.commit('fix: released line')
        self.repo.run('update-ref', 'refs/remotes/origin/main', self.source)

    def plan(self, kind, version, base=None):
        return rel.candidate_plan(kind, version, self.source, self.repo.root, base)

    def test_all_channels_and_history_notes_work_during_hold(self):
        self.repo.write('.github/release-policy.json', '{"publication_enabled":false}')
        for kind in ('alpha', 'beta', 'stable', 'hotfix'):
            version = '1.2.3' if kind in ('stable', 'hotfix') else f'1.2.3-{kind}.1.g{self.source[:7]}'
            meta, notes = self.plan(kind, version, 'v1.2.2' if kind == 'hotfix' else None)
            self.assertFalse(meta['publish'])
            self.assertEqual(meta['commit'], self.source)
            self.assertIn('released line', notes)
            self.assertEqual(meta['previous']['tag'], 'v1.2.2')

    def test_bad_versions_sources_and_hotfixes_rejected(self):
        cases = [('alpha', '1.2.3', None), ('beta', '1.2.3-alpha.1.g' + self.source[:7], None),
                 ('stable', '1.2.2', None), ('hotfix', '1.2.4', 'v1.2.2'), ('hotfix', '1.2.3', None),
                 ('stable', '1.2.3', 'v1.2.2'), ('alpha', '1.2.3-alpha.1.gabcdef0', None)]
        for case in cases:
            with self.subTest(case=case), self.assertRaises(rel.ReleaseError):
                self.plan(*case)
        self.repo.run('update-ref', 'refs/remotes/origin/main', 'HEAD~1')
        with self.assertRaises(rel.ReleaseError):
            self.plan('stable', '1.2.3')


class PromotionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.zip = self.root / 'candidate.zip'
        self.meta = dict(schema=2, channel='alpha', release_kind='alpha', version='1.0.1-alpha.2.gabcdef0',
                         commit='abcdef0' + 'a' * 33, tag='v1.0.1-alpha.2.gabcdef0', prerelease=True, make_latest=False)
        self.notes = 'Reviewed notes\n'
        texts = [fixtures.CORE_TOC, fixtures.SETTINGS_TOC, fixtures.NAVDATA_TOC, fixtures.DIAG_TOC,
                 fixtures.LAYOUTS_TOC, fixtures.WIZARD_TOC, fixtures.WORKSHOP_TOC]
        with zipfile.ZipFile(self.zip, 'w') as archive:
            for addon, text in zip(rel.ADDONS, texts):
                archive.writestr(rel.TOCS[addon], text.replace('1.0.0', self.meta['version']))
                for line in text.splitlines():
                    if line and not line.startswith('#'):
                        archive.writestr(addon + '/' + line.replace('\\', '/'), '-- fixture\n')
        for addon, text in zip(rel.ADDONS, texts):
            path = self.root / rel.TOCS[addon]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        self.meta['candidate'] = rel.candidate_identity(self.meta, self.zip, self.notes)
        self.request = dict(artifact_id='42', source=self.meta['commit'], channel='alpha',
                            version=self.meta['version'], sha256=rel.sha256(self.zip))
        self.evidence = dict(candidate=dict(self.request), verification='https://example.invalid/report',
                             client_acceptance='https://example.invalid/client', limitations='Tester alpha; not certified')
        self.env = dict(deployment_branch_policy=dict(protected_branches=True, custom_branch_policies=False),
                        protection_rules=[dict(type='required_reviewers', reviewers=[{'id':1}], prevent_self_review=True)])
        self.policy = dict(publication_enabled=False, environment_admin_bypass_disabled=True,
                           environment_configuration_evidence='https://example.invalid/settings-review')
        self.now = dt.datetime.now(dt.timezone.utc)
        self.artifact = dict(id=42, expired=False, name='candidate-' + self.request['source'] + '-123-1',
                             created_at=(self.now-dt.timedelta(days=1)).isoformat(),
                             expires_at=(self.now+dt.timedelta(days=1)).isoformat(), workflow_run=dict(id=123, head_sha='b'*40))
        self.run = dict(id=123, head_sha='b'*40, path='.github/workflows/release-candidate.yml',
                        event='workflow_dispatch', head_branch='main', status='completed', conclusion='success')

    def validate(self):
        return rel.validate_promotion(self.meta, self.zip, self.notes, self.request, self.evidence)

    def test_exact_candidate_passes_and_binding_changes_fail(self):
        self.assertEqual(self.validate()['sha256'], self.request['sha256'])
        for key in self.request:
            original = self.request[key]
            self.request[key] = 'changed'
            with self.subTest(key=key), self.assertRaises(rel.ReleaseError):
                self.validate()
            self.request[key] = original
        self.zip.write_bytes(b'different rebuild')
        with self.assertRaisesRegex(rel.ReleaseError, 'identity mismatch'):
            self.validate()

    def test_certification_and_client_evidence_required(self):
        for kind in ('beta', 'stable', 'hotfix'):
            version = '1.0.1-beta.2.gabcdef0' if kind == 'beta' else '1.0.1'
            with zipfile.ZipFile(self.zip) as archive:
                files = {n:archive.read(n) for n in archive.namelist()}
            with zipfile.ZipFile(self.zip, 'w') as archive:
                for name, data in files.items():
                    archive.writestr(name, data.replace(self.meta['version'].encode(), version.encode()))
            self.meta.update(release_kind=kind, channel='beta' if kind=='beta' else 'release',
                             prerelease=kind=='beta', make_latest=kind!='beta', version=version, tag='v'+version)
            self.meta['candidate'] = rel.candidate_identity(self.meta, self.zip, self.notes)
            self.request.update(channel=kind, version=version, sha256=rel.sha256(self.zip))
            self.evidence['candidate'] = dict(self.request)
            with self.subTest(kind=kind), self.assertRaisesRegex(rel.ReleaseError, 'certification'):
                self.validate()
            self.evidence.update(release_gate_passed=True, client_accepted=True)
            self.validate()
            self.evidence.pop('release_gate_passed')
        self.evidence['client_acceptance'] = ''
        with self.assertRaises(rel.ReleaseError):
            self.validate()

    def test_missing_stale_expired_failed_or_forged_origin_rejected(self):
        promotion.artifact_record(self.artifact, self.run, self.request, self.now)
        for field, value in [('expired',True), ('id',43), ('created_at',(self.now-dt.timedelta(days=31)).isoformat()),
                             ('expires_at',(self.now-dt.timedelta(days=1)).isoformat()), ('name','internal-other')]:
            data = dict(self.artifact, **{field:value})
            with self.subTest(field=field), self.assertRaises(rel.ReleaseError):
                promotion.artifact_record(data, self.run, self.request, self.now)
        for field,value in [('conclusion','failure'),('path','.github/workflows/release.yml'),('event','pull_request'),
                            ('head_branch','untrusted'),('head_sha','c'*40)]:
            with self.subTest(field=field), self.assertRaises(rel.ReleaseError):
                promotion.artifact_record(self.artifact, dict(self.run, **{field:value}), self.request, self.now)

    def test_unprotected_environment_rejected(self):
        rel.validate_environment(self.env, self.policy)
        for data in ({}, dict(self.env, deployment_branch_policy=None),
                     dict(self.env, protection_rules=[]), dict(self.env, protection_rules=[dict(type='required_reviewers',reviewers=[1],prevent_self_review=False)])):
            with self.assertRaises(rel.ReleaseError):
                rel.validate_environment(data, self.policy)

    def test_missing_owner_bypass_attestation_fails_closed(self):
        for policy in ({}, dict(self.policy, environment_admin_bypass_disabled=False),
                       dict(self.policy, environment_configuration_evidence='')):
            with self.assertRaisesRegex(rel.ReleaseError, 'owner evidence'):
                rel.validate_environment(self.env, policy)

    def test_flat_artifact_only_and_no_rebuilt_fallback(self):
        container = self.root / 'outer.zip'
        for bad in (None, '../escape', 'nested/meta.json'):
            with zipfile.ZipFile(container, 'w') as archive:
                archive.writestr('meta.json', json.dumps(self.meta))
                archive.writestr('notes.md', self.notes)
                archive.writestr('candidate.zip', self.zip.read_bytes())
                if bad: archive.writestr(bad, 'bad')
            target = self.root / ('payload' + str(bad is None)); target.mkdir(exist_ok=True)
            if bad:
                with self.assertRaises(rel.ReleaseError): promotion.unpack_candidate(container, target)
            else:
                self.assertEqual(promotion.unpack_candidate(container, target).read_bytes(), self.zip.read_bytes())

    def test_prepare_downloads_exact_id_and_uses_main_reviewed_evidence(self):
        policy_dir = self.root / '.github'; policy_dir.mkdir()
        (policy_dir / 'release-policy.json').write_text(json.dumps(self.policy))
        ledger = self.root / 'docs/releases'; ledger.mkdir(parents=True)
        (ledger / (self.request['sha256'] + '.json')).write_text(json.dumps(self.evidence))
        container = self.root / 'transport.zip'
        with zipfile.ZipFile(container, 'w') as archive:
            archive.writestr('meta.json', json.dumps(self.meta)); archive.writestr('notes.md', self.notes)
            archive.writestr('candidate.zip', self.zip.read_bytes())
        def api(args):
            path = args[0]
            if path.endswith('/permission'): return {'permission':'write'}
            if path.endswith('/branches/main'): return {'protected':True}
            if path.endswith('/environments/release'): return self.env
            if path.endswith('/artifacts/42'): return self.artifact
            if path.endswith('/runs/123'): return self.run
            self.fail('unexpected API call: ' + path)
        gh = mock.Mock(repo='org/repo'); gh._gh.side_effect=api; gh.releases.return_value=[]
        def download(command, stdout, stderr):
            self.assertEqual(command[-1], 'repos/org/repo/actions/artifacts/42/zip')
            stdout.write(container.read_bytes())
            return types.SimpleNamespace(returncode=0)
        with mock.patch.object(rel, 'REPO_ROOT', self.root), mock.patch.object(promotion.subprocess, 'run', side_effect=download):
            target=self.root/'download'; target.mkdir()
            meta, candidate, text = promotion.prepare(gh,self.request,'maintainer',target)
            self.assertEqual(rel.sha256(candidate), self.request['sha256'])
            self.assertEqual(text,self.notes)

    def test_stable_requires_annotated_protected_matching_tag(self):
        gh=mock.Mock(repo='org/repo'); gh._gh.return_value={}
        with self.assertRaises(rel.ReleaseError): promotion.protected_tag(gh,dict(self.meta,channel='release'))
        gh._gh.side_effect=[{'object':{'type':'tag'}},[{'id':1}],dict(target='tag',enforcement='active',
            conditions={'ref_name':{'include':['refs/tags/v*'],'exclude':[]}},rules=[{'type':'update'},{'type':'deletion'}],bypass_actors=[])]
        gh.tag_commit.return_value=self.meta['commit']
        promotion.protected_tag(gh,dict(self.meta,channel='release'))

    def test_manual_main_only_and_hold_prevent_publication(self):
        # The real CLI, missing inputs/artifact. Ref guard fails before any network access.
        command=[sys.executable,'-I',str(Path(promotion.__file__))]
        for k,v in dict(self.request,repo='org/repo',actor='maintainer').items(): command.extend(['--'+k.replace('_','-'),v])
        result=subprocess.run(command+['--publish'],capture_output=True,text=True,env={'GITHUB_EVENT_NAME':'pull_request','GITHUB_REF':'refs/heads/main'})
        self.assertEqual(result.returncode,1)
        self.assertIn('manual dispatch on main',result.stdout)

    def test_hold_is_rechecked_after_approval_before_credentials_or_upload(self):
        args=['release_promotion.py','--artifact-id','42','--source',self.request['source'],
              '--version',self.request['version'],'--channel','alpha','--sha256',self.request['sha256'],
              '--repo','org/repo','--actor','maintainer','--publish']
        policy={'content':base64.b64encode(b'{"publication_enabled":false}').decode()}
        with mock.patch.object(sys,'argv',args), mock.patch.dict(os.environ,{
                'GITHUB_EVENT_NAME':'workflow_dispatch','GITHUB_REF':'refs/heads/main'}), \
             mock.patch.object(promotion,'prepare',return_value=(self.meta,self.zip,self.notes)), \
             mock.patch.object(rel.GitHub,'_gh',return_value=policy), mock.patch.object(rel,'publish') as upload:
            self.assertEqual(promotion.main(),1)
            upload.assert_not_called()

    def test_workflow_protects_publication_and_never_rebuilds(self):
        root=Path(rel.__file__).resolve().parent.parent
        workflow=(root/'.github/workflows/release-promotion.yml').read_text()
        for required in ('workflow_dispatch:', "github.ref == 'refs/heads/main'", 'group: public-release-promotion',
                         'cancel-in-progress: false', 'needs.preflight.outputs.enabled', 'name: release',
                         'secrets.CF_API_KEY', 'inputs.artifact_id', 'inputs.sha256', '--publish'):
            self.assertIn(required,workflow)
        for forbidden in ('push:', 'pull_request:', 'packager@', 'release.py stamp', 'overwrite: true'):
            self.assertNotIn(forbidden,workflow)
        preflight=workflow.split('  publish:',1)[0]
        self.assertNotIn('secrets.',preflight)
        self.assertNotIn('contents: write',preflight)
        for file in ('release.yml','release-candidate.yml'):
            text=(root/'.github/workflows'/file).read_text()
            self.assertNotIn('secrets.',text)
            self.assertNotIn('contents: write',text)
