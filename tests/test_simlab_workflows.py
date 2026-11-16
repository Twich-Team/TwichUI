"""Partial simulator selections must judge every selected pose and label scope."""
import contextlib
import concurrent.futures
import fcntl
import importlib.util
import io
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SIMLAB = Path(__file__).resolve().parent.parent / 'tools/simlab'
sys.path.insert(0, str(SIMLAB))
spec = importlib.util.spec_from_file_location('workshop_verdict', SIMLAB / 'workshop_verdict.py')
verdict = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verdict)
sys.path.remove(str(SIMLAB))


class WorkshopSelection(unittest.TestCase):
    def sample(self, fail=False):
        checks = [('PASS', layer, 'init ' + layer, 'true', 'true') for layer in verdict.LAYERS]
        checks += [('PASS', 'state', name, 'true', 'true') for name in [
            'REACH: the Add button is reachable at its hit point',
            'NEGATIVE CONTROL: with a mouse-enabled frame planted over it',
            'NEGATIVE CONTROL: with the overlay removed, the Add button is reachable again',
            *['NEGATIVE CONTROL extra ' + str(i) for i in range(5)],
        ]]
        if fail:
            checks[0] = ('FAIL', 'init', 'init init', 'true', 'false')
        count = len(checks)
        done = re.match(r'^(\d+) (\d+) (\d+) (\d+) (\w+) (\w+)$', f'1 1 {count - int(fail)} {int(fail)} false false')
        return dict(checks=checks, steps=verdict.STEPS, done=done, errors=[], cls=dict(known={}, unknown=[], unexpected=[]))

    def run_verdict(self, selected, fail=False):
        loaded = []

        def load(run, name):
            loaded.append(name)
            if name == 'wrong':
                data = self.sample()
                checks = list(data['checks'])
                checks[0] = ('FAIL', 'init', 'doctored', 'true', 'false')
                data['checks'] = checks
                data['done'] = re.match(r'^(\d+) (\d+) (\d+) (\d+) (\w+) (\w+)$', f'1 1 {len(checks)-1} 1 false false')
                return data
            return self.sample(fail=fail)

        output = io.StringIO()
        with (mock.patch.object(sys, 'argv', ['verdict', '/unused', 'doctored', '1', *selected]),
              mock.patch.object(verdict, 'load', side_effect=load),
              mock.patch.object(verdict, 'read_rgba', return_value=(1600, 1200, [])),
              mock.patch.object(verdict, 'distinct_colours', return_value=600),
              contextlib.redirect_stdout(output)):
            result = verdict.main()
        return result, loaded, output.getvalue()

    def test_subset_does_not_load_omitted_poses_or_claim_full_coverage(self):
        status, loaded, output = self.run_verdict(['design', 'craft', 'wrong'])
        self.assertEqual(status, 0, output)
        self.assertEqual(loaded, ['design', 'craft', 'wrong'])
        self.assertIn('FOCUSED ONLY; not complete regression coverage', output)
        self.assertIn('exactly the doctored check failed', output)
        self.assertNotIn('overview.png', output)

    def test_selected_failed_assertion_propagates(self):
        status, loaded, output = self.run_verdict(['design'], fail=True)
        self.assertEqual(status, 1, output)
        self.assertIn('FAIL', output)

    def test_invalid_empty_or_incomplete_negative_control_selection_fails(self):
        for selected in (['bogus'], ['wrong'], ['design', 'wrong'], ['design', 'design']):
            with self.subTest(selected=selected):
                status, loaded, output = self.run_verdict(selected)
                self.assertEqual(status, 2, output)
                self.assertFalse(loaded)

    def test_default_requires_all_25_launches(self):
        status, loaded, output = self.run_verdict([])
        # Mocked small-screen image dimensions deliberately fail; discovery
        # must still require every default pose and the wrong control.
        self.assertEqual(loaded, list(verdict.SHOTS) + ['wrong'])
        self.assertIn('FULL REGRESSION', output)
        self.assertEqual(status, 1)


class LocalLauncher(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.repo = self.base / 'checkout'
        self.scripts = self.repo / 'tools/simlab'
        self.scripts.mkdir(parents=True)
        shutil.copyfile(SIMLAB / 'run.sh', self.scripts / 'run.sh')
        self.install = self.base / 'installation'
        binary = self.install / 'release/wow-ui-sim-v0.1.37-forever-linux-x86_64/wow-sim'
        binary.parent.mkdir(parents=True)
        binary.write_text('#!/bin/sh\nexit 0\n')
        binary.chmod(0o755)
        (self.install / 'deps/lib').mkdir(parents=True)
        ui = self.install / 'xdg/cache/wow-ui-sim/blizzard-ui'
        ui.mkdir(parents=True)
        (ui / 'immutable').write_text('cache seed')
        self.env = dict(os.environ, WOWSIM_INSTALL=str(self.install))

    def run_launcher(self):
        return subprocess.run(['bash', str(self.scripts / 'run.sh'), 'smoke'],
                              env=self.env, capture_output=True, text=True)

    def test_cache_is_copied_locally_and_child_failure_propagates(self):
        (self.scripts / 'smoke.sh').write_text('''set -eu
echo changed > "$WOWSIM_LAB/xdg/cache/wow-ui-sim/blizzard-ui/immutable"
echo "artifacts: $SIMLAB_RUN"
exit 7
''')
        result = self.run_launcher()
        self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
        self.assertEqual((self.install / 'xdg/cache/wow-ui-sim/blizzard-ui/immutable').read_text(), 'cache seed')
        self.assertEqual((self.repo / 'test-output/simlab/xdg/cache/wow-ui-sim/blizzard-ui/immutable').read_text(), 'changed\n')
        self.assertFalse(list((self.repo / 'test-output/simlab/xdg/cache').glob('.seed-*')))
        self.assertIn(str(self.repo / 'test-output/simlab/artifacts/smoke-'), result.stdout)

    def test_symlinked_output_is_refused(self):
        outside = self.base / 'outside'
        outside.mkdir()
        (self.repo / 'test-output').symlink_to(outside, target_is_directory=True)
        result = self.run_launcher()
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertEqual(list(outside.iterdir()), [])

    def test_worker_state_caches_and_artifacts_are_disjoint(self):
        (self.scripts / 'smoke.sh').write_text('''set -eu
echo "$SIMLAB_WORKER" > "$WOWSIM_LAB/home/owner"
echo "$SIMLAB_WORKER" > "$WOWSIM_LAB/xdg/cache/wow-ui-sim/blizzard-ui/immutable"
echo "artifacts: $SIMLAB_RUN"
''')
        def launch(worker):
            return subprocess.run(['bash', str(self.scripts / 'run.sh'), 'smoke'],
                                  env=dict(self.env, SIMLAB_WORKER=str(worker)), capture_output=True, text=True)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(launch, (1, 2)))
        for worker, result in enumerate(results, 1):
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            state = self.repo / f'test-output/simlab-workers/worker-{worker}'
            self.assertEqual((state / 'home/owner').read_text(), f'{worker}\n')
            self.assertEqual((state / 'xdg/cache/wow-ui-sim/blizzard-ui/immutable').read_text(), f'{worker}\n')
            self.assertIn(str(state / 'artifacts'), result.stdout)
        self.assertEqual((self.install / 'xdg/cache/wow-ui-sim/blizzard-ui/immutable').read_text(), 'cache seed')
        with (self.repo / 'test-output/simlab-workers/worker-1.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(launch(1).returncode, 2)
            self.assertEqual(launch(2).returncode, 0)
        self.assertEqual(launch('../escape').returncode, 2)

    def test_worker_parent_symlink_is_refused(self):
        outside = self.base / 'outside'
        outside.mkdir()
        (self.repo / 'test-output').mkdir()
        (self.repo / 'test-output/simlab-workers').symlink_to(outside, target_is_directory=True)
        self.env['SIMLAB_WORKER'] = '1'
        result = self.run_launcher()
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertEqual(list(outside.iterdir()), [])


class TestLabSelection(unittest.TestCase):
    def test_idle_subset_judges_only_idle(self):
        spec = importlib.util.spec_from_file_location('testlab_verdict', SIMLAB / 'testlab_verdict.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        checks = [('PASS', 'init' if i < 4 else 'state', 'check ' + str(i), 'true', 'true') for i in range(10)]
        done = re.match(r'^(\d+) (\d+) (\d+) (\d+) (\w+) (\w+)$', '1 1 10 0 false false')
        data = dict(checks=checks, steps=module.STEPS, done=done, errors=[], cls=dict(known={}, unknown=[], unexpected=[]))
        output = io.StringIO()
        with (mock.patch.object(sys, 'argv', ['verdict', '/unused', '1', 'idle']),
              mock.patch.object(module, 'load', return_value=data) as load,
              mock.patch.object(module, 'read_rgba', return_value=(1600, 1200, [])),
              mock.patch.object(module, 'distinct_colours', return_value=600),
              contextlib.redirect_stdout(output)):
            result = module.main()
        self.assertEqual(result, 0, output.getvalue())
        self.assertEqual([call.args[1] for call in load.call_args_list], ['idle'])
        self.assertIn('FOCUSED ONLY', output.getvalue())

    def test_unknown_pose_rejected_before_loading(self):
        spec = importlib.util.spec_from_file_location('testlab_verdict', SIMLAB / 'testlab_verdict.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with (mock.patch.object(sys, 'argv', ['verdict', '/unused', '1', 'idlee']),
              mock.patch.object(module, 'load') as load, contextlib.redirect_stdout(io.StringIO())):
            self.assertEqual(module.main(), 2)
            load.assert_not_called()


if __name__ == '__main__':
    unittest.main()
