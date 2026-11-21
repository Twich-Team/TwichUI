"""No live endpoints: workflow invariants, CI selection and candidate retry regressions."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
import ci_verify
import release
import test_release_tools as fixtures
FakeCurseForge = fixtures.FakeCurseForge


class RetryIdentityTests(unittest.TestCase):
    setUp = fixtures.PublishTests.setUp
    publish = fixtures.PublishTests.publish
    state = fixtures.PublishTests.state
    # Reuse publisher fixtures without repeating inherited tests.
    def test_mismatched_rebuild_rejected_after_partial_upload(self):
        self.gh.fail_publish = True
        cf = FakeCurseForge([('uploaded', 1)])
        with self.assertRaises(release.ReleaseError):
            self.publish(cf)
        self.zip.write_bytes(b'different zip')
        self.gh.fail_publish = False
        with self.assertRaisesRegex(release.ReleaseError, 'identity mismatch'):
            self.publish(cf)
        # Even resealing local metadata cannot override an accepted remote candidate.
        self.meta['candidate'] = release.candidate_identity(self.meta, self.zip, 'notes\n')
        with self.assertRaisesRegex(release.ReleaseError, 'identity mismatch'):
            self.publish(cf)
        self.assertEqual(len(cf.uploads), 1)

    def test_corrupt_remote_asset_rejected_before_cf(self):
        cf = FakeCurseForge([('failed', 'HTTP 400')])
        with self.assertRaises(release.ReleaseError):
            self.publish(cf)
        self.gh.releases_[0]['assets'][0]['bytes'] = b'corrupted'
        retry = FakeCurseForge([('uploaded', 2)])
        with self.assertRaisesRegex(release.ReleaseError, 'differs'):
            self.publish(retry)
        self.assertEqual(retry.uploads, [])

    def test_notes_version_source_and_channel_bound(self):
        for key in ('commit', 'version', 'channel'):
            meta = dict(self.meta, **{key: 'changed'})
            with self.assertRaises(release.ReleaseError):
                release.verify_candidate(meta, self.zip, 'notes\n')
        with self.assertRaises(release.ReleaseError):
            release.verify_candidate(self.meta, self.zip, 'different notes')


class IsolationTests(unittest.TestCase):
    def test_workflow_has_only_read_only_verification_and_internal_builds(self):
        workflow = (ROOT / '.github/workflows/release.yml').read_text()
        for required in ('pull_request:', 'branches: [main]', 'push:', 'workflow_dispatch:',
                         'contents: read', "github.event_name == 'workflow_dispatch'", 'overwrite: false'):
            self.assertIn(required, workflow)
        for forbidden in ('secrets.', 'github.token', 'contents: write', 'release.py publish',
                          'pull_request_target:', 'update_training_data.sh', 'tags:', 'overwrite: true'):
            self.assertNotIn(forbidden, workflow)
        # The one-click publisher is explicitly dispatched and never runs on a PR,
        # a main push, or a tag push. Publication itself is no longer globally held.
        policy = json.loads((ROOT / '.github/release-policy.json').read_text())
        self.assertIs(type(policy.get('publication_enabled')), bool)  # emergency hold remains valid
        release_workflow = (ROOT / '.github/workflows/one-click-release.yml').read_text()
        self.assertIn('workflow_dispatch:', release_workflow)
        self.assertIn("github.ref == 'refs/heads/main'", release_workflow)
        self.assertIn('environment: release', release_workflow)
        for forbidden in ('\\n  push:', '\\n  pull_request:', 'pull_request_target:', 'tags:'):
            self.assertNotIn(forbidden.replace('\\n', '\n'), release_workflow)

    def test_conservative_scope(self):
        self.assertEqual(ci_verify.selection(['tools/release.py']), ['development', 'release-tools'])
        for paths in ([], ['!!!TwichUI/Core.lua'], ['unknown'], ['tools/release.py', 'TwichUI_Workshop/Main.lua']):
            self.assertEqual(ci_verify.selection(paths), [])

    def test_internal_plan_works_during_hold(self):
        with tempfile.TemporaryDirectory() as directory:
            subprocess.run([sys.executable, '-I', str(ROOT / 'tools/release.py'), 'internal', '--out', directory],
                           check=True, cwd=ROOT)
            meta = json.loads(Path(directory, 'meta.json').read_text())
            self.assertFalse(meta['publish'])
            self.assertFalse(meta['certified'])
            self.assertEqual(len(meta['commit']), 40)
            self.assertIn(meta['commit'][:12], meta['version'])
