#!/usr/bin/env python3
"""Small, deterministic offline/feature/milestone runner; see docs/testing.md."""
import argparse
import concurrent.futures
import hashlib
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
ALIASES = {'development': 'fast', 'release': 'full'}
COVERAGE = {
    'groupfinder': ['feature interaction', 'contract validation', 'visual structural checks'],
    'smoke': ['shared UI construction', 'simulator lifecycle'],
    'interact': ['feature interaction', 'replay/determinism', 'negative controls', 'visual structural checks'],
    'diagnose': ['contract validation', 'simulator lifecycle', 'negative controls'],
    'auctionproof': ['simulator lifecycle', 'replay/determinism', 'negative controls'],
    'auctionpreview': ['feature interaction', 'replay/determinism', 'negative controls', 'visual structural checks'],
    'workshop': ['feature interaction', 'replay/determinism', 'negative controls', 'visual structural checks'],
    'testlab': ['contract validation', 'replay/determinism', 'visual structural checks'],
    'settings': ['shared UI construction', 'feature interaction', 'visual structural checks'],
    'reminders': ['feature interaction', 'visual structural checks'],
    'lab-guard': ['contract validation', 'negative controls'],
}


def describe(selection, requested):
    selection['verification_profile'] = requested
    selection['selection_reason'] = (
        'complete discovery and unchanged default simulator catalogs' if selection['tier'] == 'full' else
        'complete offline discovery; no simulator' if selection['tier'] == 'unit' else
        'direct feature tests and syntax; no simulator' if selection['tier'] == 'fast' else
        'affected groups and recursive shared dependencies; explicit scoped simulator selections')
    selected = {s['script'] for s in selection['simulators']}
    selection['omitted_catalogs'] = [s for s in FULL_SIMULATORS if s not in selected]
    selection['coverage_classification'] = {
        'offline': ['unit tests', 'contracts, migrations, performance, packaging and mutation harnesses as selected by module'],
        'simulators': {s['script']: COVERAGE[s['script']] for s in selection['simulators']},
        'not_established': ['real-client acceptance', 'pixel baseline regression (structural screenshots only)',
                            'production mutation campaigns (separate policy)', 'real-client packaged-install acceptance'],
    }
    if requested == 'release':
        selection['selection_reason'] += '; candidate archive checked by existing release checker'
        selection['coverage_classification']['release_packaging'] = ['existing candidate archive validation']
    return selection


def source_identity(repo):
    def git(*args):
        return subprocess.check_output(['git', '-C', str(repo), *args])
    try:
        commit = git('rev-parse', 'HEAD').decode().strip()
        diff = git('diff', '--binary', 'HEAD', '--')
        digest = hashlib.sha256(diff)
        for name in sorted(git('ls-files', '--others', '--exclude-standard', '-z').split(b'\0')):
            if name:
                digest.update(name + b'\0')
                digest.update((repo / os.fsdecode(name)).read_bytes())
        return dict(commit=commit, dirty=bool(diff or git('ls-files', '--others', '--exclude-standard')),
                    working_tree_sha256=digest.hexdigest())
    except subprocess.CalledProcessError:
        return dict(commit=None, dirty=None, working_tree_sha256=None)


def merge_simulators(specs):
    # Different positional args remain distinct (e.g. Settings subsets). An
    # unfiltered catalog dominates filters only for the same script/args.
    out = []
    for spec in specs:
        prior = next((s for s in out if s['script'] == spec['script'] and s.get('args', []) == spec.get('args', [])), None)
        if prior is None:
            out.append(dict(spec))
        elif not prior.get('only') or not spec.get('only'):
            prior.pop('only', None)
        else:
            prior['only'] = sorted(set(prior['only']) | set(spec['only']))
    return out



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


def plan(repo, tier, group, additional=()):
    tier = ALIASES.get(tier, tier)
    if additional and tier != 'integration':
        raise ValueError('--with-group requires integration')
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

    for target in [group, *additional]:
        if target not in groups:
            raise ValueError(f'unknown integration group: {target}')
        visit(target)
    tests, syntax = set(), set()
    for name in sorted(selected):
        tests.update(expand(repo, groups[name]['tests'], tests=True))
        syntax.update(expand(repo, groups[name]['syntax']))
    # Shared dependency tests and syntax are included; simulator choices belong
    # to the requested feature, avoiding unrelated full UI catalog replays.
    sims = merge_simulators([s for target in [group, *additional] for s in groups[target]['simulators']]) if tier in ('feature', 'integration') else []
    return dict(tier=tier, group=group, groups=sorted(selected), tests=sorted(tests),
                syntax=sorted(syntax), simulators=sims)


def recommend(repo, paths):
    """Use group membership as a starting point for reviewing changed files."""
    changed = {}
    for raw in paths:
        path = Path(raw)
        if path.is_absolute() or '..' in path.parts or not path.parts:
            raise ValueError(f'expected a repo-relative file path: {raw!r}')
        changed[path.as_posix()] = []

    groups = json.loads((repo / 'tests/groups.json').read_text())
    for name, spec in sorted(groups.items()):
        for key, root, reason in (('syntax', repo, 'syntax glob'),
                                  ('tests', repo / 'tests', 'test glob')):
            matched = {match.relative_to(repo).as_posix()
                       for pattern in spec[key] for match in root.glob(pattern) if match.is_file()}
            for path in changed.keys() & matched:
                changed[path].append((name, reason))

    print('Advisory matches from tests/groups.json. Review actual consumers and assertions.')
    for path, matches in changed.items():
        print(f'{path!r}:')
        if not matches:
            print('  Unmapped. Inspect callers, manifests and test inventory.')
            print('  If scope remains unknown, preview complete offline discovery with ./tests/run.sh --list.')
        for name, reason in matches:
            print(f'  {name} ({reason}): ./tests/run.sh development {name} --list')
        if len(matches) > 1 or any(name in ('core', 'shared-ui') for name, _ in matches):
            print('  Possible shared scope or overlapping globs. Inspect consumers before choosing groups.')
    print('Checkpoint preview: ./tests/run.sh feature GROUP --list')
    print('Cross-feature preview: ./tests/run.sh integration GROUP --with-group OTHER --list')
    print('If shared/global risk cannot be excluded, review the full gate with ./tests/run.sh full --list.')
    return 0


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


def run_test(repo, name, output_dir, processes, timeout, measure=False):
    start = time.perf_counter()
    command = ['lua5.1', '-e', LUA_INIT, name] if name.endswith('.lua') else [sys.executable, '-B', '-m', 'unittest', '-q', name[:-3]]
    metrics_path = output_dir / (name + '.metrics.json')
    if measure:
        command = [sys.executable, '-B', str(repo / 'tools/measure_command.py'), str(metrics_path), '--', *command]
    with tempfile.TemporaryDirectory(prefix=name + '-', dir=output_dir / 'tmp') as tmp:
        code, output, timed_out = processes.run(command, repo / 'tests', child_env(Path(tmp)), timeout)
    (output_dir / (name + '.log')).write_text(output)
    counts = re.findall(r'^Ran (\d+) tests? in ', output, re.M) if name.endswith('.py') else []
    return dict(metrics=json.loads(metrics_path.read_text()) if measure and metrics_path.is_file() else None, test=name, passed=not timed_out and judge(name, code, output), exit_code=code,
                timed_out=timed_out, python_cases=int(counts[-1]) if counts else None, seconds=time.perf_counter() - start)


def run_tests(repo, names, jobs, output_dir, processes, timeout, measure=False):
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
        futures = [pool.submit(run_test, repo, n, output_dir, processes, timeout, measure) for n in normal]
        # Report in discovery order, independent of completion order.
        for future in futures:
            report(future.result())
    for name in exclusive:
        report(run_test(repo, name, output_dir, processes, timeout, measure))
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
    for path in [repo / 'tools/test_runner.py', repo / 'tools/measure_command.py', *sorted((repo / 'tools/simlab').glob('*.py'))]:
        compile(path.read_bytes(), str(path), 'exec')
    (output_dir / 'syntax.log').write_text(''.join(out))
    print(f'ok   syntax ({len(lua)} Lua files; runner/simulator Python and shell scripts)', flush=True)
    return True


def simulator_capacity():
    """Conservative admission check; no claim of a kernel memory reservation."""
    cores = float(len(os.sched_getaffinity(0)))
    quota, period = Path('/sys/fs/cgroup/cpu.max').read_text().split()
    if quota != 'max':
        cores = min(cores, int(quota) / int(period))
    memory = Path('/sys/fs/cgroup/memory.max').read_text().strip()
    available = int(next(line.split()[1] for line in Path('/proc/meminfo').read_text().splitlines() if line.startswith('MemAvailable:'))) * 1024
    if memory != 'max':
        available = min(available, int(memory) - int(Path('/sys/fs/cgroup/memory.current').read_text()))
    if cores < 4 or available < 8 * 1024 ** 3:
        raise ValueError(f'two simulator workers require >=4 quota CPUs and >=8 GiB available; found {cores:g} CPUs, {available / 1024**3:.2f} GiB')
    return dict(quota_cpus=cores, available_bytes=available, workers=2,
                guard='admission only; no kernel memory reservation; serial within each catalog')


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
    parser.add_argument('tier', nargs='?', choices=('unit', 'fast', 'development', 'feature', 'integration', 'full', 'release'), default='unit')
    parser.add_argument('group', nargs='?')
    parser.add_argument('--with-group', action='append', default=[], help='additional affected group for integration; repeatable')
    parser.add_argument('--profile', choices=('local', 'cloud'), default='local',
                        help='cloud uses no game assets; all selections/assertions remain, visual/client gates stay local')
    parser.add_argument('--jobs', type=int, choices=range(1, 5), default=2, metavar='1..4')
    parser.add_argument('--list', action='store_true', help='show exact tests, syntax files and simulator selections; run nothing')
    parser.add_argument('--recommend', nargs='+', metavar='PATH',
                        help='suggest group previews for changed repo-relative files; run nothing')
    parser.add_argument('--sim-jobs', type=int, choices=(1, 2), default=1, help='opt-in isolated catalog workers; default serial')
    parser.add_argument('--measure', action='store_true', help='opt-in per-command CPU/RSS telemetry (Linux /proc)')
    parser.add_argument('--release-meta', type=Path, help='existing packaging metadata for release archive validation')
    parser.add_argument('--release-zip', type=Path, help='existing candidate archive; checked, never published')
    parser.add_argument('--timeout', type=float, default=300, help='per offline test in seconds (default 300)')
    args = parser.parse_args(argv)
    if args.recommend:
        if args.group or args.with_group or args.tier != 'unit':
            parser.error('--recommend chooses groups from paths; omit the tier and group arguments')
        try:
            return recommend(REPO, args.recommend)
        except ValueError as exc:
            parser.error(str(exc))
    if args.timeout <= 0 or (args.tier in ('full', 'release') and args.group):
        parser.error('timeout must be positive; full does not accept a feature group')
    try:
        selection = describe(plan(REPO, args.tier, args.group, args.with_group), args.tier)
    except ValueError as exc:
        parser.error(str(exc))
    selection['profile'] = args.profile
    if args.list:
        print(json.dumps(selection, indent=2))
        return 0
    if args.tier == 'release' and (not args.release_meta or not args.release_zip or not args.release_meta.is_file() or not args.release_zip.is_file()):
        parser.error('release requires existing --release-meta and --release-zip (or use --list)')
    if args.tier != 'release' and (args.release_meta or args.release_zip):
        parser.error('release archive arguments require release')
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
    identity = source_identity(REPO)
    rows, sims = [], []
    syntax_ok = True
    incomplete = dict(selection=selection, source=identity, passed=False, complete=False,
                      exit_code=None, tests=[], simulators=[])
    (output_dir / 'report.json').write_text(json.dumps(incomplete, indent=2) + '\n')
    try:
        if selection['tier'] != 'unit':
            syntax_ok = syntax_checks(REPO, selection, processes, output_dir)
        rows = run_tests(REPO, selection['tests'], args.jobs, output_dir, processes, args.timeout, args.measure)
        # No inheritance of pose filters, synthetic settings overrides or asset
        # switches may silently turn a milestone into a partial run.
        def run_simulator(index, spec, worker=None):
            tmp = output_dir / 'tmp' if worker is None else output_dir / 'tmp' / f'sim-worker-{worker}'
            tmp.mkdir(exist_ok=True)
            env = simulator_env(tmp, args.profile)
            if args.measure:
                env['SIMLAB_METRICS'] = '1'
            if worker is not None:
                env['SIMLAB_WORKER'] = str(worker)
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
            duplicate = sum(s['script'] == spec['script'] for s in selection['simulators']) > 1
            log_name = f'{index}-{spec["script"]}' if duplicate else spec['script']
            (output_dir / (log_name + '.log')).write_text(output)
            passed = code == 0 and not timed_out
            artifacts = re.findall(r'^artifacts: (.+)$', output, re.M)
            launches, checks, scenarios = 0, 0, []
            if artifacts:
                for path in Path(artifacts[-1]).glob('*.stderr'):
                    launches += 1
                    log = path.read_text(errors='replace')
                    count = len(re.findall(r'^SIMLAB check (?:PASS|FAIL) ', log, re.M))
                    checks += count
                    startup = re.search(r'\[\s*([\d.]+)s\].*\[Startup\] end post-event workarounds', log)
                    stamps = re.findall(r'\[\s*([\d.]+)s\]', log)
                    scenarios.append(dict(scenario=path.stem, structured_assertions=count,
                                          intentional_negative_control=path.stem == 'wrong',
                                          failed_assertion_markers=len(re.findall(r'^SIMLAB check FAIL ', log, re.M)),
                                          bootstrap_seconds=float(startup[1]) if startup else None,
                                          last_native_timestamp_seconds=float(stamps[-1]) if stamps else None,
                                          metrics=json.loads(path.with_suffix('.metrics.json').read_text()) if path.with_suffix('.metrics.json').is_file() else None))
            row = dict(**spec, worker=worker, passed=passed, exit_code=code, timed_out=timed_out,
                             artifacts=artifacts[-1] if artifacts else None,
                             screenshots=sorted(p.name for p in Path(artifacts[-1]).glob('*.png')) if artifacts else [],
                             telemetry=[dict(file=p.name, **json.loads(p.read_text())) for p in sorted(Path(artifacts[-1]).glob('*.metrics.json'))] if artifacts else [],
                             launches=launches, scenario_checks=checks, scenarios=sorted(scenarios, key=lambda s: s['scenario']), seconds=time.perf_counter() - t)
            print(f'{"ok  " if passed else "FAIL"} simulator {spec["script"]} ({row["seconds"]:.3f}s)', flush=True)
            if not passed:
                print(output, flush=True)
            return row

        resource_budget = None
        if args.sim_jobs == 2 and selection['simulators']:
            resource_budget = simulator_capacity()
            def lane(worker):
                return [(index, run_simulator(index, spec, worker))
                        for index, spec in list(enumerate(selection['simulators']))[worker - 1::2]]
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                futures = [pool.submit(lane, worker) for worker in (1, 2)]
                indexed = [row for future in futures for row in future.result()]
            sims = [row for _, row in sorted(indexed)]
        else:
            sims = [run_simulator(index, spec) for index, spec in enumerate(selection['simulators'])]
        package = None
        if args.tier == 'release':
            cmd = [sys.executable, '-I', 'tools/release.py', 'check', '--meta', str(args.release_meta.resolve()), str(args.release_zip.resolve())]
            code, output, timed_out = processes.run(cmd, REPO, child_env(output_dir / 'tmp'), 120)
            (output_dir / 'package.log').write_text(output)
            package = dict(exit_code=code, passed=code == 0 and not timed_out,
                           archive_sha256=hashlib.sha256(args.release_zip.read_bytes()).hexdigest(),
                           metadata_sha256=hashlib.sha256(args.release_meta.read_bytes()).hexdigest())
        passed = (package is None or package['passed']) and syntax_ok and all(row['passed'] for row in rows) and all(row['passed'] for row in sims)
        final_identity = source_identity(REPO)
        source_unchanged = identity == final_identity
        passed = passed and source_unchanged
        if not source_unchanged:
            print('FAIL source changed during verification; preserve this result and rerun affected checks on frozen source', flush=True)
        report = dict(metrics_enabled=args.measure, simulator_workers=args.sim_jobs, simulator_resource_budget=resource_budget, complete=True, package=package, automated_release_gate_passed=passed and args.tier == 'release' and args.profile == 'local', source=identity, source_after=final_identity, source_unchanged=source_unchanged,
                      exit_code=0 if passed else 1,
                      slowest_tests=sorted(rows, key=lambda r: r['seconds'], reverse=True)[:20],
                      slowest_scenarios=sorted([dict(catalog=s['script'], **r) for s in sims for r in s['scenarios'] if r['metrics']],
                                               key=lambda r: r['metrics']['wall_seconds'], reverse=True)[:20],
                      selection=selection, jobs=args.jobs, layout_workers=1, seconds=time.perf_counter() - start,
                      local_milestone_passed=passed and selection['tier'] == 'full' and args.profile == 'local',
                      unsupported_coverage=(['game asset rendering, client fonts and visual fidelity']
                                            if args.profile == 'cloud' else []),
                      syntax_passed=syntax_ok, tests=rows, simulators=sims, passed=passed)
        (output_dir / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(f'verification profile: {args.tier}; omitted catalogs: {", ".join(selection["omitted_catalogs"]) or "none"}', flush=True)
        print(f'{sum(r["passed"] for r in rows)} passed, {sum(not r["passed"] for r in rows)} failed; '
              f'{len(sims)} simulator suites; {report["seconds"]:.3f}s; {"PASS" if passed else "FAIL"}', flush=True)
        return 0 if passed else 1
    except (KeyboardInterrupt, OSError, ValueError, SyntaxError) as exc:
        incomplete.update(exit_code=130 if isinstance(exc, KeyboardInterrupt) else 2,
                          seconds=time.perf_counter() - start, tests=rows, simulators=sims,
                          error=type(exc).__name__ + ': ' + str(exc))
        (output_dir / 'report.json').write_text(json.dumps(incomplete, indent=2) + '\n')
        if not isinstance(exc, KeyboardInterrupt):
            raise
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
