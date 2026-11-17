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
import zipfile
from unittest import mock

REPO = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('test_runner', REPO / 'tools/test_runner.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class Selection(unittest.TestCase):
    def test_profiles_preserve_full_and_merge_integration_without_extra_catalogs(self):
        self.assertEqual(runner.plan(REPO, 'release', None), runner.plan(REPO, 'full', None))
        self.assertEqual(runner.plan(REPO, 'development', 'market'), runner.plan(REPO, 'fast', 'market'))
        combined = runner.plan(REPO, 'integration', 'market', ['crafting'])
        for group in ('market', 'crafting'):
            self.assertLessEqual(set(runner.plan(REPO, 'feature', group)['tests']), set(combined['tests']))
        self.assertEqual(len(combined['simulators']), 1)
        self.assertEqual(set(combined['simulators'][0]['only']), {'craft', 'opps', 'history', 'wrong', 'shop', 'strategy', 'shopcollect'})
        desc = runner.describe(combined, 'integration')
        self.assertIn('settings', desc['omitted_catalogs'])
        self.assertIn('reminders', desc['omitted_catalogs'])
        self.assertIn('negative controls', desc['coverage_classification']['simulators']['workshop'])
        with self.assertRaises(ValueError):
            runner.plan(REPO, 'feature', 'market', ['crafting'])
        with self.assertRaises(ValueError):
            runner.plan(REPO, 'integration', 'market', ['typo'])

    def test_unfiltered_catalog_dominates_and_distinct_args_survive(self):
        self.assertEqual(runner.merge_simulators([
            {'script': 'workshop', 'only': ['craft', 'wrong']}, {'script': 'workshop'}]), [{'script': 'workshop'}])
        self.assertEqual(len(runner.merge_simulators([
            {'script': 'settings', 'args': ['workshop']}, {'script': 'settings', 'args': ['profiles']} ])), 2)

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
        try:
            state = stat.read_text().split()[2]
        except (FileNotFoundError, ProcessLookupError):
            state = None  # Reaped before open (ENOENT) or during read (ESRCH).
        self.assertIn(state, (None, 'Z'), 'descendant is still running')

    def test_generation_and_seed_overrides_are_not_inherited(self):
        harmful = {k: '1' for k in runner.CLEAR_ENV}
        with mock.patch.dict(os.environ, harmful):
            env = runner.child_env(self.out / 'tmp')
        self.assertFalse(set(runner.CLEAR_ENV).intersection(env))
        self.assertEqual(env['TMPDIR'], str(self.out / 'tmp'))
        self.assertEqual(env['PYTHONDONTWRITEBYTECODE'], '1')

    def test_parallel_catalog_failure_propagates_and_reports_both_lanes(self):
        (self.repo / 'sample.lua').write_text('return true')
        (self.repo / 'tests/test_ok.lua').write_text('print("PASSED")')
        groups = {name: dict(tests=['test_ok.lua'], syntax=['sample.lua'], dependencies=[],
                             simulators=[{'script': script}])
                  for name, script in (('a', 'settings'), ('b', 'reminders'))}
        (self.repo / 'tests/groups.json').write_text(json.dumps(groups))
        (self.repo / 'tools/simlab/run.sh').write_text('''set -eu
test -n "$SIMLAB_WORKER"
if [ "$1" = reminders ]; then echo 'controlled simulator failure'; exit 7; fi
exit 0
''')
        with (mock.patch.object(runner, 'REPO', self.repo),
              mock.patch.object(runner, 'syntax_checks', return_value=True),
              mock.patch.object(runner, 'run_tests', return_value=[]),
              mock.patch.object(runner, 'simulator_capacity', return_value={'workers': 2}),
              mock.patch.object(runner, 'source_identity', return_value={'commit': 'frozen'})):
            code = runner.main(['integration', 'a', '--with-group', 'b', '--sim-jobs', '2'])
        self.assertEqual(code, 1)
        report = json.loads(next((self.repo / 'test-output/verification').glob('*/report.json')).read_text())
        self.assertTrue(report['complete'])
        self.assertFalse(report['passed'])
        self.assertEqual([(s['worker'], s['exit_code']) for s in report['simulators']], [(1, 0), (2, 7)])

    def test_release_archive_rejection_cannot_set_certification_flags(self):
        shutil.copyfile(REPO / 'tools/release.py', self.repo / 'tools/release.py')
        metadata = self.repo / 'meta.json'
        metadata.write_text(json.dumps({'version': '1.0.0'}))
        archive = self.repo / 'candidate.zip'
        with zipfile.ZipFile(archive, 'w'):
            pass  # Valid ZIP container, missing every required addon.
        selection = dict(tier='full', group=None, groups=[], tests=[], syntax=[], simulators=[])
        with (mock.patch.object(runner, 'REPO', self.repo),
              mock.patch.object(runner, 'plan', return_value=selection),
              mock.patch.object(runner, 'syntax_checks', return_value=True),
              mock.patch.object(runner, 'run_tests', return_value=[]),
              mock.patch.object(runner, 'source_identity', return_value={'commit': 'frozen'})):
            code = runner.main(['release', '--release-meta', str(metadata), '--release-zip', str(archive)])
        self.assertEqual(code, 1)
        report_dir = next((self.repo / 'test-output/verification').iterdir())
        report = json.loads((report_dir / 'report.json').read_text())
        self.assertFalse(report['package']['passed'])
        self.assertFalse(report['local_milestone_passed'])
        self.assertFalse(report['automated_release_gate_passed'])
        self.assertIn('missing !!!TwichUI/!!!TwichUI.toc', (report_dir / 'package.log').read_text())


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


class Evidence(unittest.TestCase):
    def test_parallel_admission_refuses_small_cpu_and_memory_quotas(self):
        files = {'/sys/fs/cgroup/cpu.max': '400000 100000',
                 '/sys/fs/cgroup/memory.max': str(16 * 1024**3),
                 '/sys/fs/cgroup/memory.current': str(2 * 1024**3),
                 '/proc/meminfo': 'MemAvailable: 16777216 kB\n'}
        with (mock.patch.object(runner.os, 'sched_getaffinity', return_value={0, 1, 2, 3}),
              mock.patch.object(Path, 'read_text', lambda path: files[str(path)])):
            self.assertEqual(runner.simulator_capacity()['workers'], 2)
            files['/sys/fs/cgroup/cpu.max'] = '200000 100000'
            with self.assertRaises(ValueError):
                runner.simulator_capacity()
            files['/sys/fs/cgroup/cpu.max'] = '400000 100000'
            files['/sys/fs/cgroup/memory.current'] = str(10 * 1024**3)
            with self.assertRaises(ValueError):
                runner.simulator_capacity()

    def test_source_identity_detects_tracked_and_untracked_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            subprocess.run(['git', 'init', '-q', tmp], check=True)
            (repo / 'file').write_text('original')
            subprocess.run(['git', '-C', tmp, 'add', '.'], check=True)
            subprocess.run(['git', '-C', tmp, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                            'commit', '-qm', 'baseline'], check=True)
            original = runner.source_identity(repo)
            self.assertFalse(original['dirty'])
            (repo / 'file').write_text('changed')
            changed = runner.source_identity(repo)
            self.assertTrue(changed['dirty'])
            self.assertNotEqual(original, changed)
            (repo / 'new.py').write_text('untracked input')
            self.assertNotEqual(changed, runner.source_identity(repo))

    def test_measurement_records_cpu_memory_and_propagates_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'metrics.json'
            result = subprocess.run([sys.executable, '-B', str(REPO / 'tools/measure_command.py'), str(path), '--',
                                     sys.executable, '-c', 'import time; end=time.process_time()+.4\nwhile time.process_time()<end: pass\nraise SystemExit(7)'])
            self.assertEqual(result.returncode, 7)
            report = json.loads(path.read_text())
            self.assertEqual(report['exit_code'], 7)
            self.assertGreater(report['wall_seconds'], 0)
            self.assertGreater(report['reaped_child_user_seconds'], 0)
            self.assertGreater(report['sampled_peak_tree_rss_bytes'], 0)

    def test_auction_preview_selection_preserves_default_and_control_dependencies(self):
        spec = importlib.util.spec_from_file_location('auction_preview', REPO / 'tools/simlab/auctionpreview_verdict.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(module.select([]), list(module.POSES))
        self.assertEqual(len(module.POSES), 41)
        self.assertTrue({'scopedpriced', 'scopedoutside', 'scopedabsent', 'scopedunknown', 'scopedcorrupt', 'scopedfuture'} <= set(module.POSES))
        focused = runner.plan(REPO, 'feature', 'auction-preview')['simulators'][0]['only']
        self.assertTrue({'scopedpriced', 'scopedoutside', 'scopedabsent', 'scopedunknown', 'scopedcorrupt', 'scopedfuture', 'shell', 'replay', 'wrong'} <= set(focused))
        self.assertEqual(len(module.POSES) - len(focused), 27)
        for names in (['typo'], ['wrong'], ['replay'], ['shell', 'shell']):
            with self.assertRaises(ValueError):
                module.select(names)
        self.assertEqual(module.select(['shell', 'replay', 'wrong']), ['shell', 'replay', 'wrong'])

if __name__ == '__main__':
    unittest.main()
