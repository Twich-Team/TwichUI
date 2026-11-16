#!/usr/bin/env python3
"""Small, deterministic offline/feature/milestone runner; see docs/testing.md."""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time

REPO = Path(__file__).resolve().parent.parent
LUA_INIT = 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"'
# These opt-ins change assertions/coverage or overwrite reviewed fixtures.
CLEAR_ENV = (
    'LUA_INIT', 'LUA_PATH', 'LUA_CPATH', 'PYTHONPATH', 'PYTHONHOME',
    'TWICHUI_GENERATE_CONTRACT', 'TWICHUI_SETTINGS_INVENTORY',
    'MARKET_SEED', 'MARKET_SCENARIOS', 'MARKET_ALL', 'DIST_SEED', 'DIST_SCENARIOS',
    'CRAFT_SEED', 'CRAFT_SCENARIOS', 'CRAFT_ALL', 'CHAIN_SEED', 'CHAIN_SCENARIOS',
    'H2_SEEDS', 'H2_PIPE_SEEDS', 'VALUE_SEEDS', 'L3_MARKET_ARTIFACT',
)
FULL_SIMULATORS = ('lab-guard', 'smoke', 'interact', 'diagnose', 'auctionproof', 'auctionpreview', 'workshop', 'testlab', 'settings', 'reminders')
# Layout tests build many complete mock clients (baseline peak ~4 GiB). They
# run after the worker pool, one at a time; never overlap two large heaps.
EXCLUSIVE = ('test_layout',)


def discover(repo):
    return sorted(p.name for p in (repo / 'tests').glob('test_*')
                  if p.is_file() and p.suffix in ('.lua', '.py'))


def expand(repo, patterns, tests=False):
    root = repo / 'tests' if tests else repo
    found = set()
    for pattern in patterns:
        matches = [p for p in root.glob(pattern) if p.is_file()]
        if not matches:
            raise ValueError(f'empty {"test" if tests else "syntax"} pattern: {pattern}')
        found.update(str(p.relative_to(root)) for p in matches)
    return found


def plan(repo, tier, group):
    groups = json.loads((repo / 'tests/groups.json').read_text())
    # Validate every group so stale patterns cannot quietly narrow coverage.
    for name, spec in groups.items():
        expand(repo, spec['tests'], tests=True)
        expand(repo, spec['syntax'])
        if not spec['tests'] or any(dep not in groups for dep in spec['dependencies']):
            raise ValueError(f'invalid group: {name}')
    if tier in ('unit', 'full') and not group:
        tests = discover(repo)
        syntax = set()
        if tier == 'full':
            for folder in [repo / '!!!TwichUI', *repo.glob('TwichUI_*')]:
                syntax.update(str(p.relative_to(repo)) for p in folder.rglob('*.lua')
                              if 'libs' not in [s.lower() for s in p.parts])
        sims = [{'script': s} for s in FULL_SIMULATORS] if tier == 'full' else []
        return dict(tier=tier, group=None, groups=[], tests=tests, syntax=sorted(syntax), simulators=sims)
    if group not in groups:
        raise ValueError('choose a feature group: ' + ', '.join(groups))
    selected, visiting = set(), set()

    def visit(name):
        if name in visiting:
            raise ValueError(f'dependency cycle at {name}')
        if name in selected:
            return
        visiting.add(name)
        if tier != 'fast':
            for dep in groups[name]['dependencies']:
                visit(dep)
        visiting.remove(name)
        selected.add(name)

    visit(group)
    tests, syntax = set(), set()
    for name in sorted(selected):
        tests.update(expand(repo, groups[name]['tests'], tests=True))
        syntax.update(expand(repo, groups[name]['syntax']))
    # Shared dependency tests and syntax are included; simulator choices belong
    # to the requested feature, avoiding unrelated full UI catalog replays.
    sims = groups[group]['simulators'] if tier == 'feature' else []
    return dict(tier=tier, group=group, groups=sorted(selected), tests=sorted(tests),
                syntax=sorted(syntax), simulators=sims)


def child_env(tmp):
    env = {k: v for k, v in os.environ.items() if k not in CLEAR_ENV}
    env.update(TMPDIR=str(tmp), PYTHONDONTWRITEBYTECODE='1')
    return env


def judge(name, code, output):
    if code != 0:
        return False
    if name.endswith('.lua'):
        return bool(re.search(r'PASSED|OK', output)) and 'ERROR:' not in output
    return True


class Processes:
    def __init__(self):
        self.lock = threading.Lock()
        self.children = set()
        self.cancelled = False

    def stop(self):
        with self.lock:
            self.cancelled = True
            for proc in self.children:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def run(self, command, cwd, env, timeout):
        with self.lock:
            if self.cancelled:
                return 130, 'interrupted', False
            proc = subprocess.Popen(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True, errors='replace', start_new_session=True)
            self.children.add(proc)
        timed_out = False
        try:
            try:
                output, _ = proc.communicate(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                output, _ = proc.communicate()
            return proc.returncode, output, timed_out
        finally:
            with self.lock:
                self.children.discard(proc)


def run_test(repo, name, output_dir, processes, timeout):
    start = time.perf_counter()
    command = ['lua5.1', '-e', LUA_INIT, name] if name.endswith('.lua') else [sys.executable, '-B', '-m', 'unittest', '-q', name[:-3]]
    with tempfile.TemporaryDirectory(prefix=name + '-', dir=output_dir / 'tmp') as tmp:
        code, output, timed_out = processes.run(command, repo / 'tests', child_env(Path(tmp)), timeout)
    (output_dir / (name + '.log')).write_text(output)
    counts = re.findall(r'^Ran (\d+) tests? in ', output, re.M) if name.endswith('.py') else []
    return dict(test=name, passed=not timed_out and judge(name, code, output), exit_code=code,
                timed_out=timed_out, python_cases=int(counts[-1]) if counts else None, seconds=time.perf_counter() - start)


def run_tests(repo, names, jobs, output_dir, processes, timeout):
    rows = []

    def report(row):
        rows.append(row)
        print(f'{"ok  " if row["passed"] else "FAIL"} {row["test"]} ({row["seconds"]:.3f}s)', flush=True)
        if not row['passed']:
            print((output_dir / (row['test'] + '.log')).read_text(), end='', flush=True)
            if row['timed_out']:
                print(f'\nTIMEOUT after {timeout}s; process group killed', flush=True)

    normal = [n for n in names if not n.startswith(EXCLUSIVE)]
    exclusive = [n for n in names if n.startswith(EXCLUSIVE)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = [pool.submit(run_test, repo, n, output_dir, processes, timeout) for n in normal]
        # Report in discovery order, independent of completion order.
        for future in futures:
            report(future.result())
    for name in exclusive:
        report(run_test(repo, name, output_dir, processes, timeout))
    return sorted(rows, key=lambda row: row['test'])


def syntax_checks(repo, selection, processes, output_dir):
    lua = sorted(set(selection['syntax']) | {'tests/' + n for n in selection['tests'] if n.endswith('.lua')})
    commands = [['luac5.1', '-p', *lua]] if lua else []
    commands += [['bash', '-n', str(p.relative_to(repo))] for p in [repo / 'tests/run.sh', *sorted((repo / 'tools/simlab').glob('*.sh'))]]
    out = []
    for cmd in commands:
        code, log, timed_out = processes.run(cmd, repo, child_env(output_dir / 'tmp'), 60)
        out.append(log)
        if code or timed_out:
            (output_dir / 'syntax.log').write_text(''.join(out))
            print('FAIL syntax:', ' '.join(cmd), log, flush=True)
            return False
    for path in [repo / 'tools/test_runner.py', *sorted((repo / 'tools/simlab').glob('*.py'))]:
        compile(path.read_bytes(), str(path), 'exec')
    (output_dir / 'syntax.log').write_text(''.join(out))
    print(f'ok   syntax ({len(lua)} Lua files; runner/simulator Python and shell scripts)', flush=True)
    return True


def simulator_env(tmp, profile):
    env = {k: v for k, v in child_env(tmp).items()
           if (not k.startswith('SIMLAB_') or k == 'SIMLAB_WOW') and k != 'WOWSIM_LAB'}
    if profile == 'cloud':
        env['SIMLAB_ASSETS'] = '0'
        # Explicit runtime launcher for verified user-space shared libraries.
        if os.environ.get('SIMLAB_BIN'):
            env['SIMLAB_BIN'] = os.environ['SIMLAB_BIN']
    return env


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tier', nargs='?', choices=('unit', 'fast', 'feature', 'full'), default='unit')
    parser.add_argument('group', nargs='?')
    parser.add_argument('--profile', choices=('local', 'cloud'), default='local',
                        help='cloud uses no game assets; all selections/assertions remain, visual/client gates stay local')
    parser.add_argument('--jobs', type=int, choices=range(1, 5), default=2, metavar='1..4')
    parser.add_argument('--list', action='store_true', help='show exact tests, syntax files and simulator selections; run nothing')
    parser.add_argument('--timeout', type=float, default=300, help='per offline test in seconds (default 300)')
    args = parser.parse_args(argv)
    if args.timeout <= 0 or (args.tier == 'full' and args.group):
        parser.error('timeout must be positive; full does not accept a feature group')
    try:
        selection = plan(REPO, args.tier, args.group)
    except ValueError as exc:
        parser.error(str(exc))
    selection['profile'] = args.profile
    if args.list:
        print(json.dumps(selection, indent=2))
        return 0
    # Each invocation has deterministic filenames within its own directory.
    base = REPO / 'test-output/verification'
    base.mkdir(parents=True, exist_ok=True)
    output_dir = Path(tempfile.mkdtemp(prefix=f'{args.tier}-{args.group or "all"}-', dir=base))
    (output_dir / 'tmp').mkdir()
    print(f'profile: {args.profile}; cloud results never satisfy the local milestone gate')
    print(f'{args.tier} {args.group or "all"}: {len(selection["tests"])} test files/modules, {args.jobs} workers; layout tests serial', flush=True)
    print(f'artifacts: {output_dir}', flush=True)
    processes = Processes()

    def interrupted(signum, frame):
        processes.stop()
        raise KeyboardInterrupt

    previous = {sig: signal.signal(sig, interrupted) for sig in (signal.SIGINT, signal.SIGTERM)}
    start = time.perf_counter()
    rows, sims = [], []
    syntax_ok = True
    try:
        if args.tier != 'unit':
            syntax_ok = syntax_checks(REPO, selection, processes, output_dir)
        rows = run_tests(REPO, selection['tests'], args.jobs, output_dir, processes, args.timeout)
        # No inheritance of pose filters, synthetic settings overrides or asset
        # switches may silently turn a milestone into a partial run.
        env = simulator_env(output_dir / 'tmp', args.profile)
        for spec in selection['simulators']:
            cmd = (['bash', 'tools/simlab/tests/lab_guard.sh'] if spec['script'] == 'lab-guard' else
                   ['bash', 'tools/simlab/run.sh', spec['script'], *spec.get('args', [])])
            if spec.get('only'):
                env['SIMLAB_ONLY'] = ' '.join(spec['only'])
            else:
                env.pop('SIMLAB_ONLY', None)
            t = time.perf_counter()
            # Full catalogs can take many launches. Each launch retains its own
            # existing timeout; the whole suite gets a separate generous guard.
            code, output, timed_out = processes.run(cmd, REPO, env, 3600)
            (output_dir / (spec['script'] + '.log')).write_text(output)
            passed = code == 0 and not timed_out
            artifacts = re.findall(r'^artifacts: (.+)$', output, re.M)
            launches, checks = 0, 0
            if artifacts:
                for path in Path(artifacts[-1]).glob('*.stderr'):
                    launches += 1
                    log = path.read_text(errors='replace')
                    checks += len(re.findall(r'^SIMLAB check (?:PASS|FAIL) ', log, re.M))
            sims.append(dict(**spec, passed=passed, exit_code=code, timed_out=timed_out,
                             artifacts=artifacts[-1] if artifacts else None,
                             launches=launches, scenario_checks=checks, seconds=time.perf_counter() - t))
            print(f'{"ok  " if passed else "FAIL"} simulator {spec["script"]} ({sims[-1]["seconds"]:.3f}s)', flush=True)
            if not passed:
                print(output, flush=True)
        passed = syntax_ok and all(row['passed'] for row in rows) and all(row['passed'] for row in sims)
        report = dict(selection=selection, jobs=args.jobs, layout_workers=1, seconds=time.perf_counter() - start,
                      local_milestone_passed=passed and args.tier == 'full' and args.profile == 'local',
                      unsupported_coverage=(['game asset rendering, client fonts and visual fidelity']
                                            if args.profile == 'cloud' else []),
                      syntax_passed=syntax_ok, tests=rows, simulators=sims, passed=passed)
        (output_dir / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(f'{sum(r["passed"] for r in rows)} passed, {sum(not r["passed"] for r in rows)} failed; '
              f'{len(sims)} simulator suites; {report["seconds"]:.3f}s; {"PASS" if passed else "FAIL"}', flush=True)
        return 0 if passed else 1
    except KeyboardInterrupt:
        print('Interrupted; child process groups stopped. No complete regression result.', flush=True)
        return 130
    finally:
        processes.stop()
        for sig, handler in previous.items():
            signal.signal(sig, handler)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, SyntaxError) as exc:
        print(f'test runner: {exc}', file=sys.stderr)
        sys.exit(2)
