#!/usr/bin/env python3
"""tools/mutate.py: the mutation runner behind tools/mutate.sh (docs/workshop/testing-roadmap.md, milestone M4).

A mutation is one deliberate, exact-text defect (for example `<=` instead of `<`) planted in a COPY of the Workshop source. The runner
runs the focused offline tests against the copy and reports whether they notice. It answers "would these tests catch this mistake?",
not "is the code right?". Nothing here runs in the game and nothing in the repository is ever edited.

ISOLATION (the rules this file exists to keep; tests/test_mutate.py checks them):
  * The live checkout is only READ. Every mutation gets its own disposable copy under a fresh temporary folder (never inside the
    repository): the core addon's code files, the Workshop and Test Lab folders, the test helpers and the tests that mutation names.
    The core folder is a real folder of COPIES, not a symlink, because `ROOT .. "../TwichUI_Workshop/"` must resolve beside it.
  * A mutation may only change a file under an allowed target folder (default: TwichUI_Workshop/).
  * The source set is read ONCE, at the start, into memory, and every copy (the baseline's and each mutant's) is written from those bytes, so
    all mutants are compared with the same baseline source by construction. After the last mutant the live files are compared with what
    was read: a difference means the checkout moved under the campaign (or something wrote to it) and the run is reported as an
    infrastructure error.
  * Child processes get a minimal environment (no inherited seeds or LUA_INIT), a private HOME and TMPDIR inside the copy, and run in
    their own process group, which is killed on a timeout, on Ctrl-C and on SIGTERM. The temporary folder is removed in every case that
    Python can observe; a SIGKILL of the runner itself leaves `twichui-mutate-*` in the temp folder (harmless; delete it).

OUTCOMES (never mixed):
  killed      the mutant ran and a relevant test failed (kind: assertion | runtime-error | caught-error | no-pass-marker)
  survived    the mutant applied, every relevant test passed: the defect went unnoticed
  invalid     the pattern was missing or ambiguous, the replacement changed nothing, or the mutated file no longer parses
  timeout     a test exceeded its limit (never a kill: a hang is not a detection)
  infra       the harness, the copy or the test command failed independently of the mutation
A baseline run of every needed test on an UNMODIFIED copy comes first. If it fails the campaign stops (exit 3).

EXIT STATUS: 0 every selected mutation ended as the catalog expects (killed, or a documented known survivor) and nothing else happened;
1 an unexpected survivor, an unexpected kill of a known survivor, an invalid mutation or a timeout; 2 an infrastructure error (also a
source tree that changed during the run); 3 the baseline failed; 64 bad arguments or a bad catalog; 130/143 interrupted (SIGINT/SIGTERM).
"""
from __future__ import annotations

import argparse
import concurrent.futures
import dataclasses
import difflib
import importlib.util
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

sys.dont_write_bytecode = True

EXIT_OK, EXIT_FAILED, EXIT_INFRA, EXIT_BASELINE, EXIT_USAGE = 0, 1, 2, 3, 64
TEMP_PREFIX = "twichui-mutate-"
ID_RE = re.compile(r"^[a-z0-9]+(\.[a-z0-9]+(-[a-z0-9]+)*)+$")
TEST_RE = re.compile(r"^test_[A-Za-z0-9_]+\.lua$")
STATUSES = ("killed", "survived", "invalid", "timeout", "infra")
RUNTIME_ERROR_RE = re.compile(r"attempt to |bad argument|stack overflow|not enough memory|invalid order function|string expected|table expected")
INFRA_OUTPUT_RE = re.compile(r"cannot open (\./)?test_|module 'bit' not found|No such file or directory.*(lua5\.1|luac5\.1)")


class Usage(Exception):
    """Bad arguments or a bad catalog (exit 64)."""


class Infra(Exception):
    """The harness failed, independently of any mutation (exit 2)."""


class Invalid(Exception):
    """A mutation that cannot be applied unambiguously (reported, never counted as a kill)."""


class Interrupted(BaseException):
    def __init__(self, signum):
        super().__init__(signum)
        self.signum = signum


# --------------------------------------------------------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------------------------------------------------------
@dataclasses.dataclass
class Suite:
    """Where the sources are and how a test is run. Defaults describe this repository; a catalog may override any field (SUITE = {...})."""
    repo: Path
    core_dir: str = "!!!TwichUI"
    core_suffixes: tuple = (".lua", ".toc", ".xml")
    copy_dirs: tuple = ("TwichUI_Workshop", "TwichUI_TestLab")
    copy_files: tuple = (".pkgmeta",)
    tests_dir: str = "tests"
    tests_subdirs: tuple = ("fixtures",)
    targets: tuple = ("TwichUI_Workshop/",)
    command: tuple = ("lua5.1", "-e", 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"', "{test}")
    syntax_check: tuple = ("luac5.1", "-p", "{file}")
    pass_marker: str = r"PASSED|OK"        # what tests/run.sh greps for
    error_marker: str = "ERROR:"           # an error the addon caught and handed to the error handler: run.sh fails the test too
    broad_tests: tuple = ()
    timeout_max: float = 120.0


def load_catalog(path: Path, suite: Suite):
    if not path.is_file():
        raise Usage(f"catalog not found: {path}")
    spec = importlib.util.spec_from_file_location("twichui_mutation_catalog", str(path))
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except Exception as e:  # a broken catalog is a usage problem, not a crash
        raise Usage(f"catalog {path} did not load: {type(e).__name__}: {e}")
    overrides = getattr(mod, "SUITE", {}) or {}
    for key, value in overrides.items():
        if not hasattr(suite, key) or key == "repo":
            raise Usage(f"catalog SUITE has an unknown field: {key}")
        setattr(suite, key, tuple(value) if isinstance(value, list) else value)
    raw = getattr(mod, "MUTATIONS", None)
    if not isinstance(raw, (list, tuple)):
        raise Usage("catalog must define MUTATIONS (a list)")
    return [dict(r) for r in raw]


@dataclasses.dataclass
class Mutation:
    id: str
    file: str
    find: str
    replace: str
    why: str
    tests: tuple
    smoke: bool = False
    expect: str = "killed"
    note: str = ""

    @property
    def group(self):
        return self.id.split(".")[0]


FIELDS = {f.name for f in dataclasses.fields(Mutation) if f.name != "group"}


def build_mutations(raw, suite: Suite):
    problems, out, seen = [], [], set()
    for i, r in enumerate(raw):
        label = r.get("id", f"#{i}") if isinstance(r, dict) else f"#{i}"
        extra = set(r) - FIELDS
        missing = {"id", "file", "find", "replace", "why", "tests"} - set(r)
        if extra or missing:
            problems.append(f"{label}: unknown fields {sorted(extra)} / missing fields {sorted(missing)}")
            continue
        r = dict(r)
        r["tests"] = tuple(r["tests"]) if isinstance(r["tests"], (list, tuple)) else r["tests"]
        m = Mutation(**r)
        if not isinstance(m.id, str) or not ID_RE.match(m.id):
            problems.append(f"{label}: id must look like area.topic.name (lowercase, digits, hyphens)")
        elif m.id in seen:
            problems.append(f"{m.id}: duplicate id")
        seen.add(m.id)
        if not (isinstance(m.file, str) and isinstance(m.find, str) and isinstance(m.replace, str) and isinstance(m.why, str)):
            problems.append(f"{label}: file, find, replace and why must be strings")
            continue
        if not m.find or m.find == m.replace:
            problems.append(f"{label}: find must be non-empty and different from replace")
        if not m.why.strip():
            problems.append(f"{label}: why (the defect it simulates) is required")
        p = m.file
        if p.startswith("/") or "\\" in p or ".." in p.split("/") or not any(p.startswith(t) for t in suite.targets):
            problems.append(f"{label}: file must be a relative path under {list(suite.targets)}, got {p!r}")
        if not isinstance(m.tests, tuple) or not m.tests or not all(isinstance(t, str) and TEST_RE.match(t) for t in m.tests):
            problems.append(f"{label}: tests must be a non-empty list of test_*.lua names")
        elif not all((suite.repo / suite.tests_dir / t).is_file() for t in m.tests):
            problems.append(f"{label}: a named test does not exist in {suite.tests_dir}/")
        if m.expect not in ("killed", "survived"):
            problems.append(f"{label}: expect must be 'killed' or 'survived'")
        if m.expect == "survived" and not m.note.strip():
            problems.append(f"{label}: a known survivor needs a note saying why it is acceptable")
        out.append(m)
    for t in suite.broad_tests:
        if not (suite.repo / suite.tests_dir / t).is_file():
            problems.append(f"SUITE.broad_tests names a missing test: {t}")
    if problems:
        raise Usage("catalog problems:\n  " + "\n  ".join(problems))
    return out


def select(mutations, groups, ids, smoke, everything):
    if not (groups or ids or smoke or everything):
        smoke = True
    known = {m.id for m in mutations}
    for i in ids:
        if i not in known:
            raise Usage(f"unknown mutation id: {i} (see --list)")
    chosen = []
    for m in mutations:
        hit = everything or (smoke and m.smoke) or m.id in ids or any(m.id == g or m.id.startswith(g + ".") for g in groups)
        if hit:
            chosen.append(m)
    for g in groups:
        if not any(m.id == g or m.id.startswith(g + ".") for m in mutations):
            raise Usage(f"no mutation belongs to group {g!r} (see --list)")
    if not chosen:
        raise Usage("nothing selected")
    return chosen


# --------------------------------------------------------------------------------------------------------------------------
# The source set, its snapshot and the disposable copy
# --------------------------------------------------------------------------------------------------------------------------
def _walk(base: Path, rel: str, suffixes=None):
    top = base / rel
    if not top.is_dir():
        raise Infra(f"source folder is missing: {rel}")
    found = []
    for dirpath, dirnames, filenames in os.walk(top, followlinks=False):
        dirnames[:] = sorted(d for d in dirnames if d != "__pycache__")
        for d in dirnames:
            if (Path(dirpath) / d).is_symlink():
                raise Infra(f"symlink in the source set: {Path(dirpath, d).relative_to(base)}")
        for name in sorted(filenames):
            p = Path(dirpath) / name
            if p.is_symlink():
                raise Infra(f"symlink in the source set: {p.relative_to(base)}")
            if suffixes is None or name.endswith(tuple(suffixes)):
                found.append(p.relative_to(base).as_posix())
    return found


def common_files(suite: Suite):
    """Every file all copies share (relative, posix), sorted."""
    repo, files = suite.repo, []
    files += _walk(repo, suite.core_dir, suite.core_suffixes)
    for d in suite.copy_dirs:
        files += _walk(repo, d)
    for f in suite.copy_files:
        if (repo / f).is_file():
            files.append(f)
    tests = repo / suite.tests_dir
    if not tests.is_dir():
        raise Infra(f"tests folder is missing: {suite.tests_dir}")
    for p in sorted(tests.iterdir()):
        if p.is_file() and not p.is_symlink() and p.suffix == ".lua" and not p.name.startswith("test_"):   # the helpers (harness.lua, mi_mock.lua, ...)
            files.append(f"{suite.tests_dir}/{p.name}")
    for sub in suite.tests_subdirs:
        if (tests / sub).is_dir():
            files += _walk(repo, f"{suite.tests_dir}/{sub}")
    return sorted(set(files))


def snapshot(suite: Suite, tests):
    """{relative path: bytes} of the common files and the named tests, read from the live checkout (the only time the campaign reads it)."""
    rels = common_files(suite) + [f"{suite.tests_dir}/{t}" for t in sorted(set(tests))]
    snap = {}
    for rel in rels:
        p = suite.repo / rel
        if not p.is_file() or p.is_symlink():
            raise Infra(f"source file is missing or a symlink: {rel}")
        snap[rel] = p.read_bytes()
    return snap


def stage_tree(suite: Suite, snap, tests, dest: Path):
    """Writes the common files and `tests` into `dest` from the campaign's snapshot (never from the live checkout). Returns the files written."""
    wanted = set(common_files_from(snap, suite)) | {f"{suite.tests_dir}/{t}" for t in tests}
    dest.mkdir(parents=True)
    for rel in sorted(wanted):
        if rel not in snap:
            raise Infra(f"file not in the campaign snapshot: {rel}")
        target = dest / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(snap[rel])
    (dest / ".sandbox" / "home").mkdir(parents=True)
    (dest / ".sandbox" / "tmp").mkdir()
    return sorted(wanted)


def common_files_from(snap, suite: Suite):
    prefix = f"{suite.tests_dir}/test_"
    return [r for r in snap if not r.startswith(prefix)]


def check_unchanged(suite: Suite, snap, tests):
    """Re-reads the live checkout and says which files differ from the snapshot now (empty list: byte-identical)."""
    now = snapshot(suite, tests)
    return sorted([r for r in set(now) | set(snap) if now.get(r) != snap.get(r)])


# --------------------------------------------------------------------------------------------------------------------------
# Applying a mutation
# --------------------------------------------------------------------------------------------------------------------------
def apply_to_bytes(data: bytes, m: Mutation) -> bytes:
    needle = m.find.encode("utf-8")
    n = data.count(needle)
    if n == 0:
        raise Invalid("pattern not found exactly once: found 0 times (the source changed, or the pattern is misspelled)")
    if n > 1:
        raise Invalid(f"pattern is ambiguous: found {n} times (add context so it matches exactly once)")
    return data.replace(needle, m.replace.encode("utf-8"), 1)


def short_diff(old: bytes, new: bytes, rel: str) -> str:
    a = old.decode("utf-8", "replace").splitlines()
    b = new.decode("utf-8", "replace").splitlines()
    return "\n".join(difflib.unified_diff(a, b, f"a/{rel}", f"b/{rel}", lineterm="", n=1))


def which_or_infra(argv0: str):
    if shutil.which(argv0) is None:
        raise Infra(f"required tool not found on PATH: {argv0}")


# --------------------------------------------------------------------------------------------------------------------------
# Running a child process
# --------------------------------------------------------------------------------------------------------------------------
class Children:
    """The live process groups, so an interrupt can end all of them."""

    def __init__(self):
        self.lock = threading.Lock()
        self.live = set()

    def add(self, p):
        with self.lock:
            self.live.add(p)

    def drop(self, p):
        with self.lock:
            self.live.discard(p)

    def kill_all(self):
        with self.lock:
            procs = list(self.live)
        for p in procs:
            kill_group(p)


def kill_group(p):
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
    except OSError:
        try:
            p.kill()
        except OSError:
            pass


def child_env(stage: Path):
    env = {"PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"), "HOME": str(stage / ".sandbox" / "home"),
           "TMPDIR": str(stage / ".sandbox" / "tmp"), "LANG": "C", "LC_ALL": "C"}
    for key in ("LUA_PATH", "LUA_CPATH"):
        if key in os.environ:
            env[key] = os.environ[key]
    return env


def run_process(children: Children, argv, cwd: Path, env, timeout: float):
    """(returncode, output text, seconds, timed_out). stdout and stderr are merged; the child is its own process group."""
    start = time.monotonic()
    try:
        p = subprocess.Popen(list(argv), cwd=str(cwd), env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, start_new_session=True)
    except OSError as e:
        return 127, f"could not start {argv[0]}: {e}", 0.0, False
    children.add(p)
    timed_out = False
    try:
        try:
            out, _ = p.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            kill_group(p)
            out, _ = p.communicate()
    except BaseException:
        kill_group(p)
        raise
    finally:
        children.drop(p)
    return p.returncode, (out or b"").decode("utf-8", "replace"), time.monotonic() - start, timed_out


def test_argv(suite: Suite, test: str):
    return [part.replace("{test}", test) for part in suite.command]


def judge(suite: Suite, rc: int, out: str):
    """('pass', '') or ('fail', kind) or ('infra', why). Kind says HOW the test failed, so a crash is not mistaken for an assertion."""
    if rc < 0 or rc in (126, 127):
        return "infra", f"the test command could not run (exit {rc})"
    if INFRA_OUTPUT_RE.search(out):
        return "infra", "the test environment is broken (a file or module is missing)"
    has_error = suite.error_marker in out
    if rc == 0 and re.search(suite.pass_marker, out) and not has_error:
        return "pass", ""
    if rc == 0:
        return "fail", "caught-error" if has_error else "no-pass-marker"
    first = next((ln for ln in out.splitlines() if ln.startswith("lua5.1:") or "attempt to" in ln), "")
    return "fail", "runtime-error" if RUNTIME_ERROR_RE.search(first) else "assertion"


def tail(text: str, lines=14, chars=1800):
    t = "\n".join(text.rstrip().splitlines()[-lines:])
    return t if len(t) <= chars else "..." + t[-chars:]


def first_failure_line(out: str):
    for ln in out.splitlines():
        if ln.startswith("lua5.1:") or "MISMATCH" in ln or "expected" in ln:
            return ln.strip()[:300]
    return (out.strip().splitlines() or [""])[-1][:300]


# --------------------------------------------------------------------------------------------------------------------------
# One mutation
# --------------------------------------------------------------------------------------------------------------------------
@dataclasses.dataclass
class Result:
    id: str
    status: str = "infra"
    message: str = ""
    kind: str = ""
    killed_by: str = ""
    tests_run: list = dataclasses.field(default_factory=list)   # [{test, status, seconds}]
    seconds: float = 0.0
    excerpt: str = ""
    diff: str = ""
    kept: str = ""
    broad_killed_by: str = ""
    expected: bool = False
    command: str = ""


@dataclasses.dataclass
class Context:
    suite: Suite
    snap: dict
    root: Path
    children: Children
    cancel: threading.Event
    baseline_secs: dict
    fixed_timeout: float = 0.0
    keep_failed: bool = False
    broad: bool = False

    def timeout_for(self, test):
        if self.fixed_timeout:
            return self.fixed_timeout
        return min(self.suite.timeout_max, max(10.0, self.baseline_secs.get(test, 5.0) * 6 + 5))


def evaluate(ctx: Context, index: int, m: Mutation) -> Result:
    res = Result(id=m.id)
    stage = ctx.root / f"{index:03d}-{m.id}"
    started = time.monotonic()
    out_text = ""
    try:
        try:
            out_text = _evaluate(ctx, stage, m, res)
        except Invalid as e:
            res.status, res.message = "invalid", str(e)
        except Infra as e:
            res.status, res.message = "infra", str(e)
        except Interrupted:
            raise
        except Exception as e:  # nothing a mutant or a test does may take the campaign down
            res.status, res.message = "infra", f"{type(e).__name__}: {e}"
        res.seconds = time.monotonic() - started
        res.expected = res.status == m.expect
        if ctx.keep_failed and not res.expected and stage.exists():
            res.kept = str(stage)
            _write_artifacts(stage, m, res, out_text, ctx.suite)
    finally:
        if not res.kept and stage.exists():
            shutil.rmtree(stage, ignore_errors=True)
    return res


def _evaluate(ctx: Context, stage: Path, m: Mutation, res: Result) -> str:
    suite = ctx.suite
    if ctx.cancel.is_set():
        raise Infra("cancelled")
    stage_tree(suite, ctx.snap, m.tests + (suite.broad_tests if ctx.broad else ()), stage)
    target = stage / m.file
    if not target.is_file() or target.is_symlink():
        raise Invalid(f"target file is not part of the copy: {m.file}")
    old = target.read_bytes()
    new = apply_to_bytes(old, m)
    res.diff = short_diff(old, new, m.file)
    target.write_bytes(new)
    which_or_infra(suite.syntax_check[0])
    rc, out, _, _ = run_process(ctx.children, [p.replace("{file}", str(target)) for p in suite.syntax_check], stage, child_env(stage), 30)
    if rc != 0:
        raise Invalid("the mutated file does not parse: " + (out.strip().splitlines() or ["?"])[-1])

    env, cwd = child_env(stage), stage / suite.tests_dir
    last_out = ""
    for test in m.tests:
        rc, out, secs, timed_out = run_process(ctx.children, test_argv(suite, test), cwd, env, ctx.timeout_for(test))
        last_out = out
        res.command = " ".join(test_argv(suite, test))
        entry = {"test": test, "seconds": round(secs, 2)}
        res.tests_run.append(entry)
        if timed_out:
            entry["status"] = "timeout"
            res.status, res.message = "timeout", f"{test} exceeded {ctx.timeout_for(test):.0f} s (a hang is not a detection)"
            res.excerpt = tail(out, 6)
            return out
        verdict, detail = judge(suite, rc, out)
        entry["status"] = verdict
        if verdict == "infra":
            res.status, res.message, res.excerpt = "infra", f"{test}: {detail}", tail(out, 8)
            return out
        if verdict == "fail":
            res.status, res.killed_by, res.kind = "killed", test, detail
            res.message = first_failure_line(out)
            res.excerpt = tail(out, 10)
            return out
    res.status, res.message = "survived", "every relevant test passed"
    res.excerpt = tail(last_out, 4)
    if ctx.broad and suite.broad_tests:
        for test in suite.broad_tests:
            if test in m.tests:
                continue
            rc, out, secs, timed_out = run_process(ctx.children, test_argv(suite, test), cwd, env, ctx.timeout_for(test))
            if not timed_out and judge(suite, rc, out)[0] == "fail":
                res.broad_killed_by = test
                break
    return last_out


def _write_artifacts(stage: Path, m: Mutation, res: Result, out: str, suite: Suite):
    """What --keep-failed leaves beside the copy: what was mutated, the last test output and how to rerun it by hand."""
    (stage / "MUTATION.txt").write_text(
        f"id:       {m.id}\nfile:     {m.file}\nwhy:      {m.why}\nexpected: {m.expect}\nresult:   {res.status}"
        f"{' (' + res.kind + ')' if res.kind else ''}\nmessage:  {res.message}\n\n{res.diff}\n", encoding="utf-8")
    (stage / "OUTPUT.txt").write_text(out, encoding="utf-8")
    argv = " ".join("'" + a + "'" if (" " in a or ";" in a or "!" in a) else a for a in test_argv(suite, res.tests_run[-1]["test"])) if res.tests_run else ""
    (stage / "REPRODUCE.txt").write_text(f"cd '{stage / suite.tests_dir}' && env -i PATH=\"$PATH\" {argv}\n", encoding="utf-8")


# --------------------------------------------------------------------------------------------------------------------------
# The campaign
# --------------------------------------------------------------------------------------------------------------------------
def run_baseline(ctx: Context, tests):
    """Every needed test on an UNMODIFIED copy. Returns (ok, entries); also fills ctx.baseline_secs (used for the time limits)."""
    suite = ctx.suite
    stage = ctx.root / "000-baseline"
    staged = stage_tree(suite, ctx.snap, tests, stage)
    entries, ok = [], True
    try:
        for test in sorted(tests):
            timeout = ctx.fixed_timeout or suite.timeout_max
            rc, out, secs, timed_out = run_process(ctx.children, test_argv(suite, test), stage / suite.tests_dir, child_env(stage), timeout)
            ctx.baseline_secs[test] = secs
            verdict, detail = ("timeout", "") if timed_out else judge(suite, rc, out)
            entries.append({"test": test, "status": verdict, "seconds": round(secs, 2), "output": tail(out, 14) if verdict != "pass" else ""})
            if verdict != "pass":
                ok = False
        # a test must not write into the tree it runs in: the next mutant would no longer be compared with the same baseline
        for rel in staged:
            p = stage / rel
            if not p.is_file() or p.read_bytes() != ctx.snap[rel]:
                raise Infra(f"a baseline test changed its own copy: {rel}")
    finally:
        shutil.rmtree(stage, ignore_errors=True)
    return ok, entries


def run_campaign(args, suite: Suite, chosen):
    tests = sorted({t for m in chosen for t in m.tests} | set(suite.broad_tests if args.broad else ()))
    which_or_infra(suite.command[0])
    which_or_infra(suite.syntax_check[0])
    snap = snapshot(suite, tests)
    tmp_parent = Path(tempfile.gettempdir()).resolve()
    repo_real = suite.repo.resolve()
    if tmp_parent == repo_real or repo_real in tmp_parent.parents:
        raise Infra(f"the temporary folder {tmp_parent} is inside the repository; set TMPDIR elsewhere")
    root = Path(tempfile.mkdtemp(prefix=TEMP_PREFIX)).resolve()
    children, cancel = Children(), threading.Event()
    ctx = Context(suite, snap, root, children, cancel, {}, fixed_timeout=args.timeout or 0.0, keep_failed=args.keep_failed, broad=args.broad)
    started = time.monotonic()
    report = {"baseline": [], "results": [], "changed_files": [], "interrupted": 0}
    results = {}
    pool = None
    old_handlers = {}
    try:
        def on_signal(signum, frame):
            raise Interrupted(signum)

        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            old_handlers[sig] = signal.signal(sig, on_signal)
        print(f"mutation campaign: {len(chosen)} mutation(s), {len(tests)} distinct test file(s), jobs={args.jobs}")
        print(f"temporary copies: {root}")
        ok, entries = run_baseline(ctx, tests)
        report["baseline"] = entries
        for e in entries:
            print(f"baseline  {e['status']:<8} {e['test']}  ({e['seconds']:.1f}s)")
        if not ok:
            report["aborted"] = "baseline failed"
            for e in entries:
                if e["status"] != "pass":
                    print(f"\nBASELINE FAILED: {e['test']} ({e['status']}) on an unmodified copy, so no mutation can be judged.")
                    print(f"  command: {' '.join(test_argv(suite, e['test']))}   [run in the copy's {suite.tests_dir}/ folder]")
                    for ln in e["output"].splitlines():
                        print("    | " + ln)
            return EXIT_BASELINE, report, results, started
        pool = concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs)
        futures = {pool.submit(evaluate, ctx, i + 1, m): m for i, m in enumerate(chosen)}
        done = 0
        for fut in concurrent.futures.as_completed(futures):
            m = futures[fut]
            res = fut.result()
            results[m.id] = res
            done += 1
            kind = f" ({res.kind})" if res.kind else ""
            who = res.killed_by or (res.tests_run[-1]["test"] if res.tests_run else "")
            flag = "" if res.expected else "  <-- NOT AS EXPECTED"
            print(f"[{done:>3}/{len(chosen)}] {res.status:<8} {m.id:<46} {who}{kind} {res.seconds:.1f}s{flag}", flush=True)
        report["changed_files"] = check_unchanged(suite, snap, tests)
        return None, report, results, started
    except Interrupted as e:
        report["interrupted"] = e.signum
        return 128 + e.signum, report, results, started
    finally:
        cancel.set()
        children.kill_all()
        if pool is not None:
            pool.shutdown(wait=True, cancel_futures=True)
        children.kill_all()
        for sig, handler in old_handlers.items():
            signal.signal(sig, handler)
        if root.exists() and not any(root.iterdir()):
            shutil.rmtree(root, ignore_errors=True)   # nothing kept: the whole temporary folder goes
        report["root"] = str(root)


def summarize(args, chosen, results, report, started, code):
    elapsed = time.monotonic() - started
    counts = {s: 0 for s in STATUSES}
    unexpected, known = [], []
    for m in chosen:
        r = results.get(m.id)
        if r is None:
            continue
        counts[r.status] += 1
        if not r.expected:
            unexpected.append((m, r))
        elif m.expect == "survived":
            known.append((m, r))
    print()
    for m, r in unexpected:
        print("-" * 78)
        print(f"{r.status.upper()} (expected {m.expect}): {m.id}")
        print(f"  file:       {m.file}")
        print(f"  defect:     {m.why}")
        print(f"  transform:  - {m.find.strip().splitlines()[0][:100]}")
        print(f"              + {m.replace.strip().splitlines()[0][:100] if m.replace.strip() else '(removed)'}")
        print(f"  tests:      {', '.join(m.tests)}")
        print(f"  command:    {r.command or '(not reached)'}   [run in the copy's tests/ folder]")
        print(f"  result:     {r.message}")
        if r.excerpt:
            print("  output:")
            for ln in r.excerpt.splitlines():
                print("    | " + ln)
        if r.broad_killed_by:
            print(f"  broader run: a test outside the focused set DOES fail: {r.broad_killed_by}")
        print(f"  reproduce:  bash {Path(__file__).resolve().parent / 'mutate.sh'} --id {m.id}" + ("" if r.kept else " --keep-failed"))
        if r.kept:
            print(f"  kept copy:  {r.kept}   (MUTATION.txt, OUTPUT.txt, REPRODUCE.txt)")
    if args.verbose:
        for m in chosen:
            r = results.get(m.id)
            if r and r.expected and r.status == "killed":
                print(f"killed {m.id}: {r.message}")
    if report.get("changed_files"):
        print("SOURCE CHANGED DURING THE RUN (results are not trustworthy):")
        for f in report["changed_files"][:20]:
            print("  " + f)
    kinds = {}
    for r in results.values():
        if r.status == "killed":
            kinds[r.kind] = kinds.get(r.kind, 0) + 1
    print("=" * 78)
    print(f"selected {len(chosen)}   killed {counts['killed']}   survived {counts['survived']}   invalid {counts['invalid']}   "
          f"timeout {counts['timeout']}   infra {counts['infra']}   (elapsed {elapsed:.1f}s)")
    if kinds:
        print("killed by: " + ", ".join(f"{k} {v}" for k, v in sorted(kinds.items())))
    if known:
        print("known survivors (documented in the catalog, expected): " + ", ".join(m.id for m, _ in known))
    applied = counts["killed"] + counts["survived"]
    excluded = counts["invalid"] + counts["timeout"] + counts["infra"] + (len(chosen) - len(results))
    if code == EXIT_BASELINE:
        print("RESULT: baseline failed; no mutation was classified.")
    elif code and code > 128:
        print(f"RESULT: interrupted; {len(results)} of {len(chosen)} finished. Temporary copies were removed.")
    else:
        print(f"detection: {counts['killed']} of {applied} applied mutations killed"
              + (f"; {excluded} excluded (invalid, timeout, infra or not run), so this is NOT a clean score" if excluded else ""))
    return counts, unexpected


def exit_code(counts, unexpected, report, results, chosen):
    if report.get("changed_files") or counts["infra"]:
        return EXIT_INFRA
    if unexpected or len(results) != len(chosen):
        return EXIT_FAILED
    return EXIT_OK


# --------------------------------------------------------------------------------------------------------------------------
# Command line
# --------------------------------------------------------------------------------------------------------------------------
class Parser(argparse.ArgumentParser):
    def error(self, message):   # argparse's default exit status is 2, which this tool uses for an infrastructure error
        self.print_usage(sys.stderr)
        print(f"mutate: {message}", file=sys.stderr)
        raise SystemExit(EXIT_USAGE)


def parse_args(argv):
    here = Path(__file__).resolve().parent
    ap = Parser(
        prog="mutate.sh", formatter_class=argparse.RawDescriptionHelpFormatter,
        description="Plants deliberate defects in a disposable copy of the Workshop source and checks that the focused tests notice.",
        epilog="""examples (from any folder):
  bash tools/mutate.sh                       the smoke group (a few mutations of each kind)
  bash tools/mutate.sh --group market        every market and pricing mutation
  bash tools/mutate.sh --group crafting      every crafting, stock, shopping and economics mutation
  bash tools/mutate.sh --all --jobs 4        the whole catalog, four copies at a time
  bash tools/mutate.sh --id market.trend.window-start
  bash tools/mutate.sh --list                what exists (add --verbose for the exact edits)
  bash tools/mutate.sh --check               validate the catalog against the source without running any test
  bash tools/mutate.sh --keep-failed         keep the copy of every mutation that did not end as expected, for debugging

exit status: 0 as expected | 1 survivor, unexpected result, invalid or timeout | 2 infrastructure error | 3 baseline failed | 64 usage | 130/143 interrupted""")
    ap.add_argument("--group", action="append", default=[], metavar="NAME", help="a group (market, crafting) or an id prefix (market.trend); repeatable")
    ap.add_argument("--id", action="append", default=[], metavar="ID", dest="ids", help="one mutation id; repeatable")
    ap.add_argument("--smoke", action="store_true", help="the small default group (what runs with no selection)")
    ap.add_argument("--all", action="store_true", help="the whole catalog")
    ap.add_argument("--list", action="store_true", help="list the selected mutations and exit")
    ap.add_argument("--check", action="store_true", help="validate the selected mutations (match exactly once, still parse); runs no test")
    ap.add_argument("--keep-failed", action="store_true", help="keep the copy of each mutation that did not end as expected")
    ap.add_argument("--broad", action="store_true", help="also run the catalog's broader test files against survivors, to say whether anything else catches them")
    ap.add_argument("--jobs", type=int, default=1, metavar="N", help="mutations evaluated at once (default 1); each has its own copy")
    ap.add_argument("--timeout", type=float, default=0.0, metavar="SEC", help="fixed time limit per test (default: 6 x its baseline time + 5 s, at most 120)")
    ap.add_argument("--json", metavar="FILE", help="also write the full result as JSON")
    ap.add_argument("--verbose", "-v", action="store_true")
    ap.add_argument("--catalog", metavar="FILE", help="a catalog file (default: tools/mutations/workshop.py)")
    ap.add_argument("--repo", metavar="DIR", help="the checkout to read (default: this script's repository)")
    args = ap.parse_args(argv)
    if args.jobs < 1 or args.jobs > 16:
        ap.error("--jobs must be 1 to 16")
    args.here = here
    return args


def cmd_list(chosen, verbose):
    width = max(len(m.id) for m in chosen)
    for m in chosen:
        mark = "S" if m.smoke else " "
        exp = "" if m.expect == "killed" else "  [known survivor]"
        print(f"{mark} {m.id:<{width}}  {', '.join(m.tests)}{exp}")
        print(f"    {m.why}")
        if verbose:
            print(f"    {m.file}")
            print("    - " + m.find.replace("\n", "\n      "))
            print("    + " + m.replace.replace("\n", "\n      "))
    print(f"\n{len(chosen)} mutation(s); S = in the smoke group")


def cmd_check(args, suite, chosen):
    which_or_infra(suite.syntax_check[0])
    root = Path(tempfile.mkdtemp(prefix=TEMP_PREFIX)).resolve()
    children, bad = Children(), 0
    try:
        for m in chosen:
            try:
                new = apply_to_bytes((suite.repo / m.file).read_bytes(), m)
                probe = root / "probe.lua"
                probe.write_bytes(new)
                rc, out, _, _ = run_process(children, [p.replace("{file}", str(probe)) for p in suite.syntax_check], root, child_env_plain(root), 30)
                if rc != 0:
                    raise Invalid("the mutated file does not parse: " + (out.strip().splitlines() or ["?"])[-1])
                print(f"ok      {m.id}")
            except FileNotFoundError:
                bad += 1
                print(f"INVALID {m.id}: file not found: {m.file}")
            except Invalid as e:
                bad += 1
                print(f"INVALID {m.id}: {e}")
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print(f"\n{len(chosen) - bad} of {len(chosen)} valid")
    return EXIT_FAILED if bad else EXIT_OK


def child_env_plain(root: Path):
    return {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": str(root), "TMPDIR": str(root), "LANG": "C"}


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    repo = Path(args.repo).resolve() if args.repo else args.here.parent
    suite = Suite(repo=repo)
    catalog = Path(args.catalog) if args.catalog else args.here / "mutations" / "workshop.py"
    try:
        suite_raw = load_catalog(catalog, suite)
        mutations = build_mutations(suite_raw, suite)
        chosen = select(mutations, args.group, args.ids, args.smoke, args.all)
        if args.list:
            cmd_list(chosen, args.verbose)
            return EXIT_OK
        if args.check:
            return cmd_check(args, suite, chosen)
        code, report, results, started = run_campaign(args, suite, chosen)
    except Usage as e:
        print(f"mutate: {e}", file=sys.stderr)
        return EXIT_USAGE
    except Infra as e:
        print(f"mutate: infrastructure error: {e}", file=sys.stderr)
        return EXIT_INFRA
    counts, unexpected = summarize(args, chosen, results, report, started, code)
    if report.get("root") and Path(report["root"]).exists():
        print(f"kept copies are under {report['root']} (delete the folder when done)")
    if args.json:
        data = {"format": 1, "elapsed_seconds": round(time.monotonic() - started, 1), "counts": counts, "exit": None,
                "baseline": report["baseline"], "changed_files": report["changed_files"],
                "results": [dict(dataclasses.asdict(results[m.id]), expect=m.expect, file=m.file, why=m.why) for m in chosen if m.id in results]}
        final = code if code is not None else exit_code(counts, unexpected, report, results, chosen)
        data["exit"] = final
        Path(args.json).write_text(json.dumps(data, indent=2), encoding="utf-8")
    if code is not None:
        return code
    return exit_code(counts, unexpected, report, results, chosen)


if __name__ == "__main__":
    sys.exit(main())
