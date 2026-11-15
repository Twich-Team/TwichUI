"""Exercise selection, coverage guards, process failures, timeout and isolation."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('test_runner', REPO / 'tools/test_runner.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class Selection(unittest.TestCase):
    def test_full_discovery_keeps_every_original_test_and_new_python_tests(self):
        tests = runner.discover(REPO)
        self.assertGreaterEqual(sum(n.endswith('.lua') for n in tests), 213)
        for name in ('sv_inspect', 'release_tools', 'wizard_art', 'reminder_gallery', 'mutate', 'test_runner', 'simlab_png'):
            self.assertIn('test_' + name + '.py', tests)
        self.assertEqual(runner.plan(REPO, 'unit', None)['tests'], tests)
        full = runner.plan(REPO, 'full', None)
        self.assertEqual(full['tests'], tests)
        self.assertEqual([s['script'] for s in full['simulators']], list(runner.FULL_SIMULATORS))
        self.assertTrue(all('libs' not in [p.lower() for p in Path(s).parts] for s in full['syntax']))

    def test_focused_and_feature_are_explicit_deduplicated_and_nonempty(self):
        groups = json.loads((REPO / 'tests/groups.json').read_text())
        for group in groups:
            fast = runner.plan(REPO, 'fast', group)
            feature = runner.plan(REPO, 'feature', group)
            self.assertTrue(fast['tests'])
            self.assertEqual(fast['tests'], sorted(set(fast['tests'])))
            self.assertLessEqual(set(fast['tests']), set(feature['tests']))
            self.assertFalse(fast['simulators'])
        focus = runner.plan(REPO, 'fast', 'workshop-settings')
        self.assertIn('test_workshop_worth_designer.lua', focus['tests'])
        self.assertNotIn('test_layout_wizard.lua', focus['tests'])
        feature = runner.plan(REPO, 'feature', 'workshop-settings')
        self.assertIn('test_workshop_market_reference.lua', feature['tests'])
        self.assertIn('test_settings_kit.lua', feature['tests'])
        self.assertIn('test_lifecycle.lua', feature['tests'])
        self.assertEqual(feature['simulators'], [{'script': 'workshop', 'only': ['design', 'craft', 'wrong']}])

    def test_typos_cannot_silently_run_nothing(self):
        with self.assertRaises(ValueError):
            runner.plan(REPO, 'fast', 'workshoop')
        with self.assertRaises(ValueError):
            runner.expand(REPO, ['tests/no_such_test_*.lua'])


class Execution(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / 'repo'
        (self.repo / 'tests').mkdir(parents=True)
        (self.repo / 'tools/simlab').mkdir(parents=True)
        self.out = Path(self.tmp.name) / 'output'
        (self.out / 'tmp').mkdir(parents=True)
        self.processes = runner.Processes()
        self.addCleanup(self.processes.stop)

    def test_failures_are_visible_in_parallel_and_logs_are_complete(self):
        files = {
            'test_good.lua': 'print("PASSED")',
            'test_caught.lua': 'print("PASSED"); print("ERROR: caught addon error")',
            'test_exit.lua': 'print("OK"); os.exit(7)',
            'test_no_marker.lua': 'print("nothing was asserted")',
            'test_trace.lua': 'print("EARLY FAILURE DETAIL"); for i=1,12 do print(i) end; error("trace preserved")',
        }
        for name, body in files.items():
            (self.repo / 'tests' / name).write_text(body)
        rows = runner.run_tests(self.repo, sorted(files), 2, self.out, self.processes, 3)
        self.assertEqual([r['test'] for r in rows], sorted(files))
        self.assertEqual(sum(r['passed'] for r in rows), 1)
        self.assertEqual(next(r for r in rows if r['test'] == 'test_exit.lua')['exit_code'], 7)
        self.assertIn('EARLY FAILURE DETAIL', (self.out / 'test_trace.lua.log').read_text())
        self.assertIn('stack traceback:', (self.out / 'test_trace.lua.log').read_text())

    def test_failed_python_module_runs_once_and_cli_propagates_failure(self):
        (self.repo / 'sample.lua').write_text('return true')
        (self.repo / 'tests/test_ok.lua').write_text('print("PASSED")')
        (self.repo / 'tests/test_bad.py').write_text('''from pathlib import Path
import unittest
p=Path('count.txt'); p.write_text(p.read_text()+'x' if p.exists() else 'x')
class Fails(unittest.TestCase):
    def test_fails(self): self.fail('controlled Python failure')
''')
        (self.repo / 'tests/groups.json').write_text(json.dumps({'demo': dict(tests=['test_*.lua'], syntax=['sample.lua'], dependencies=[], simulators=[])}))
        shutil.copyfile(REPO / 'tools/test_runner.py', self.repo / 'tools/test_runner.py')
        result = subprocess.run([sys.executable, '-B', str(self.repo / 'tools/test_runner.py'), '--jobs', '2'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('controlled Python failure', result.stdout)
        self.assertEqual((self.repo / 'tests/count.txt').read_text(), 'x')
        report = json.loads(next((self.repo / 'test-output/verification').glob('*/report.json')).read_text())
        self.assertEqual(len(report['tests']), 2)
        self.assertFalse(report['passed'])

    def test_timeout_is_failure_and_kills_descendant_process(self):
        pid_file = Path(self.tmp.name) / 'child.pid'
        code = ('import subprocess,time; from pathlib import Path; '
                'p=subprocess.Popen(["sleep","30"]); '
                f'Path({str(pid_file)!r}).write_text(str(p.pid)); time.sleep(30)')
        status, output, timed_out = self.processes.run([sys.executable, '-c', code], self.repo, os.environ.copy(), .3)
        self.assertTrue(timed_out)
        self.assertNotEqual(status, 0)
        pid = int(pid_file.read_text())
        stat = Path(f'/proc/{pid}/stat')
        self.assertTrue(not stat.exists() or stat.read_text().split()[2] == 'Z', 'descendant is still running')

    def test_generation_and_seed_overrides_are_not_inherited(self):
        harmful = {k: '1' for k in runner.CLEAR_ENV}
        with mock.patch.dict(os.environ, harmful):
            env = runner.child_env(self.out / 'tmp')
        self.assertFalse(set(runner.CLEAR_ENV).intersection(env))
        self.assertEqual(env['TMPDIR'], str(self.out / 'tmp'))
        self.assertEqual(env['PYTHONDONTWRITEBYTECODE'], '1')


class CloudProfile(unittest.TestCase):
    def test_profile_keeps_filters_cleared_and_selects_assets_explicitly(self):
        with mock.patch.dict(os.environ, {'SIMLAB_ONLY': 'wrong', 'SIMLAB_ASSETS': '1',
                                         'SIMLAB_BIN': '/verified/launcher', 'SIMLAB_FORWARD': 'injected=1'}):
            cloud = runner.simulator_env(Path('/tmp'), 'cloud')
            local = runner.simulator_env(Path('/tmp'), 'local')
        self.assertEqual(cloud['SIMLAB_ASSETS'], '0')
        self.assertEqual(cloud['SIMLAB_BIN'], '/verified/launcher')
        for key in ('SIMLAB_ONLY', 'SIMLAB_FORWARD'):
            self.assertNotIn(key, cloud)
        for key in ('SIMLAB_ASSETS', 'SIMLAB_BIN'):
            self.assertNotIn(key, local)

if __name__ == '__main__':
    unittest.main()
