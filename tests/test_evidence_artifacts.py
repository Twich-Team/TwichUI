"""Bounded artifact collection preserves failures and refuses redirected input."""
import hashlib
import importlib.util
import json
import os
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('evidence', ROOT / 'tools/collect_verification_evidence.py')
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'repo'
        self.root.mkdir()
        self.out = Path(self.tmp.name) / 'bundle'
        stub = type('Result', (), dict(returncode=0, stdout='fixture identity', stderr=''))()
        self.command = patch.object(evidence.subprocess, 'run', return_value=stub)
        self.command.start()
        self.addCleanup(self.command.stop)

    def write(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def test_failed_report_logs_and_capture_retained_with_identity(self):
        files = {'test-output/verification/run/report.json': b'{"passed":false}',
                 'test-output/verification/run/failure.log': b'failure traceback',
                 'test-output/simlab/artifacts/run/view.png': b'exact capture'}
        for name, data in files.items():
            self.write(name, data)
        for name in ('test-output/verification/run/tmp/private.log',
                     'test-output/simlab/xdg/cache/cache.json', 'test-output/old-review/view.png'):
            self.write(name, b'excluded')
        result = evidence.collect(self.root, self.out)
        self.assertEqual({r['path'] for r in result['retained']}, set(files))
        for row in result['retained']:
            data = files[row['path']]
            self.assertEqual((self.out / row['path']).read_bytes(), data)
            self.assertEqual(row['sha256'], hashlib.sha256(data).hexdigest())
        self.assertEqual(result['source']['fixtures']['output'], 'fixture identity')
        self.assertEqual(json.loads((self.out / 'manifest.json').read_text()), result)

    def test_budget_keeps_report_first_and_records_omission_without_truncation(self):
        self.write('test-output/verification/run/report.json', b'{}')
        self.write('test-output/verification/run/large.log', b'x' * 100)
        self.write('test-output/simlab/artifacts/run/a.png', b'png')
        result = evidence.collect(self.root, self.out, max_bytes=4, max_files=1)
        self.assertEqual([r['path'] for r in result['retained']], ['test-output/verification/run/report.json'])
        self.assertEqual(len(result['omitted']), 2)
        self.assertEqual(result['payload_bytes'], 2)

    def test_symlink_file_and_parent_refused(self):
        outside = Path(self.tmp.name) / 'outside'
        outside.mkdir()
        (outside / 'secret.log').write_text('do not collect')
        for mode in ('file', 'directory'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as dest:
                root = Path(dest) / 'repo'
                folder = root / 'test-output/verification/run'
                folder.mkdir(parents=True)
                if mode == 'file':
                    (folder / 'secret.log').symlink_to(outside / 'secret.log')
                else:
                    (folder / 'redirect').symlink_to(outside, target_is_directory=True)
                    # rglob does not traverse directory symlinks: nothing is copied.
                if mode == 'file':
                    with self.assertRaisesRegex(ValueError, 'symlinked'):
                        evidence.collect(root, Path(dest) / 'out')
                else:
                    self.assertEqual(evidence.collect(root, Path(dest) / 'out')['retained'], [])

    def test_workflow_retains_failures_and_blocks_new_output_tracking(self):
        workflow = (ROOT / '.github/workflows/release.yml').read_text()
        for required in ('git diff --no-renames --name-only --diff-filter=A',
                         'HEAD -- test-output/', 'collect_verification_evidence.py',
                         'retention-days: 14', 'overwrite: false'):
            self.assertIn(required, workflow)
        for name in ('Collect verification diagnostics', 'Retain bounded verification diagnostics'):
            step = workflow.split('- name: ' + name, 1)[1].split('\n      - ', 1)[0]
            self.assertIn('if: ${{ always() }}', step)

    def test_tracking_guard_rejects_additions_and_moves_but_allows_removals(self):
        # Exercise the actual workflow shell, including Git rename handling.
        self.command.stop()
        script = (ROOT / '.github/workflows/release.yml').read_text().split(
            '- name: Refuse new tracked test outputs', 1)[1].split(
            'run: |\n', 1)[1].split('\n      - name:', 1)[0]
        script = '\n'.join(line[10:] for line in script.splitlines())
        def git(*args):
            return subprocess.check_output(['git', *args], cwd=self.root, text=True).strip()
        git('init', '-q')
        git('config', 'user.email', 'fixture@example.invalid')
        git('config', 'user.name', 'Fixture')
        self.write('test-output/legacy.png', b'original')
        self.write('outside.png', b'move me')
        git('add', '.')
        git('commit', '-qm', 'baseline')
        base = git('rev-parse', 'HEAD')
        (self.root / 'test-output/legacy.png').unlink()
        git('add', '-u')
        git('commit', '-qm', 'safe removal')
        env = dict(os.environ, BASE=base)
        result = subprocess.run(['bash', '-e', '-c', script], cwd=self.root, env=env, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        for mode in ('addition', 'rename'):
            if mode == 'addition':
                self.write('test-output/new.png', b'new')
                git('add', '.')
            else:
                git('mv', 'outside.png', 'test-output/moved.png')
            git('commit', '-qm', mode)
            result = subprocess.run(['bash', '-e', '-c', script], cwd=self.root, env=env, capture_output=True)
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn(b'test-output/', result.stdout)
            env['BASE'] = git('rev-parse', 'HEAD')

    def test_missing_lua_still_preserves_available_diagnostics(self):
        self.command.stop()
        with patch.object(evidence.subprocess, 'run', side_effect=FileNotFoundError):
            result = evidence.collect(self.root, self.out)
        self.assertEqual(result['environment']['lua']['exit_code'], 127)

    def test_existing_destination_refused(self):
        self.out.mkdir()
        with self.assertRaises(FileExistsError):
            evidence.collect(self.root, self.out)


if __name__ == '__main__':
    unittest.main()
