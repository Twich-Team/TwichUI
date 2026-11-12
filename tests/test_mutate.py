"""tools/mutate.py (the Workshop mutation runner, testing roadmap M4): harness-level tests on a tiny FAKE repository.

What is proved here is the runner's behaviour, not the Workshop's: that a pattern must match exactly once, that a baseline failure stops the
campaign, that killed / survived / invalid / timeout / infra are told apart and never confused, that every copy lives outside the checkout and
is removed, and that the checkout is byte-identical afterwards. The real catalog is NOT run here (that takes minutes; see
docs/workshop/testing-roadmap.md); only its patterns are checked against the real source (test_real_catalog_matches_the_source).

Run: python3 -B -m unittest -q test_mutate     (from tests/; ./tests/run.sh does this)
"""
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent / "tools"
REAL_REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
sys.dont_write_bytecode = True
import mutate  # noqa: E402

HAVE_LUA = shutil.which("lua5.1") is not None and shutil.which("luac5.1") is not None

CALC = """-- fake production file
function Add(a, b)
  return a + b
end
function Cmp(a, b)
  if a < b then return "lt" end
  if a > b then return "gt" end
  return "eq"
end
function Wait(n)
  while n > 0 do
    n = n - 1
  end
  return n
end
function Pick(t)
  return t.value
end
function Twice(a)
  local x = a * 2
  local y = a * 2
  return x + y
end
function Unchecked(a)
  return a * 1
end
"""
TEST_CALC = """local f = assert(loadfile("../TwichUI_Workshop/calc.lua")); f()
assert(Add(2, 3) == 5, "Add(2, 3) expected 5")
assert(Cmp(1, 2) == "lt", "Cmp(1, 2) expected lt")
assert(Cmp(2, 1) == "gt", "Cmp(2, 1) expected gt")
assert(Wait(5) == 0, "Wait(5) expected 0")
assert(Pick({ value = 7 }) == 7, "Pick expected 7")
assert(Twice(3) == 12, "Twice(3) expected 12")
print("PASSED")
"""
TEST_EXIT = """local f = assert(loadfile("../TwichUI_Workshop/calc.lua")); f()
if Add(1, 1) ~= 2 then os.exit(127) end
print("PASSED")
"""
TEST_SELFKILL = """local f = assert(loadfile("../TwichUI_Workshop/calc.lua")); f()
if Add(1, 1) ~= 2 then os.execute("kill -9 $PPID") end
print("PASSED")
"""
TEST_SLEEP = """local f = assert(loadfile("../TwichUI_Workshop/calc.lua")); f()
if Add(1, 1) ~= 2 then os.execute("sleep 37.123") end
print("PASSED")
"""
TEST_ENV = """assert(os.getenv("MUT_LEAK") == nil, "the caller's environment leaked into the test")
assert(os.getenv("HOME"):find(".sandbox", 1, true), "HOME is not the private one")
print("PASSED")
"""
TEST_EXTRA = """local f = assert(loadfile("../TwichUI_Workshop/calc.lua")); f()
assert(Unchecked(3) == 3, "Unchecked(3) expected 3")
print("PASSED")
"""
TEST_BROKEN = """error("this test is broken before any mutation")
"""
TEST_ERRORMARK = """local f = assert(loadfile("../TwichUI_Workshop/calc.lua")); f()
if Add(1, 1) ~= 2 then print("ERROR: something the addon caught") end
print("PASSED")
"""


def digest_tree(root):
    out = {}
    for p in sorted(Path(root).rglob("*")):
        if p.is_file():
            out[str(p.relative_to(root))] = hashlib.sha256(p.read_bytes()).hexdigest()
    return out


def entry(id, find, replace, tests=("test_calc.lua",), file="TwichUI_Workshop/calc.lua", why="a fake defect", **kw):
    d = dict(id=id, file=file, find=find, replace=replace, why=why, tests=tests)
    d.update(kw)
    return d


@unittest.skipUnless(HAVE_LUA, "lua5.1 and luac5.1 are needed")
class MutateTests(unittest.TestCase):
    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="mutate-test-")).resolve()
        self.addCleanup(shutil.rmtree, self.base, True)
        self.repo = self.base / "repo"
        self.tmp = self.base / "tmp"
        self.tmp.mkdir()
        (self.repo / "!!!TwichUI").mkdir(parents=True)
        (self.repo / "!!!TwichUI" / "stub.lua").write_text("-- core\n")
        (self.repo / "TwichUI_Workshop").mkdir()
        (self.repo / "TwichUI_Workshop" / "calc.lua").write_text(CALC)
        (self.repo / "TwichUI_TestLab").mkdir()
        (self.repo / "TwichUI_TestLab" / "lab.lua").write_text("-- lab\n")
        (self.repo / "tests").mkdir()
        (self.repo / "tests" / "helper.lua").write_text("-- helper\n")
        for name, body in (("test_calc.lua", TEST_CALC), ("test_exit.lua", TEST_EXIT), ("test_selfkill.lua", TEST_SELFKILL),
                           ("test_sleep.lua", TEST_SLEEP), ("test_env.lua", TEST_ENV), ("test_broken.lua", TEST_BROKEN),
                           ("test_errormark.lua", TEST_ERRORMARK), ("test_extra.lua", TEST_EXTRA)):
            (self.repo / "tests" / name).write_text(body)
        self.before = digest_tree(self.repo)

    # -- helpers ---------------------------------------------------------------------------------------------------------
    def run_tool(self, entries, *args, suite=None, env_extra=None, timeout=120):
        suite = dict(dict(command=["lua5.1", "{test}"], copy_files=[], tests_subdirs=[]), **(suite or {}))
        cat = self.base / "catalog.py"
        cat.write_text(f"SUITE = {suite!r}\nMUTATIONS = {entries!r}\n")
        env = dict(os.environ, TMPDIR=str(self.tmp))
        env.update(env_extra or {})
        p = subprocess.run([sys.executable, "-B", "-I", str(TOOLS / "mutate.py"), "--repo", str(self.repo), "--catalog", str(cat), *args],
                           capture_output=True, text=True, env=env, timeout=timeout)
        return p.returncode, p.stdout + p.stderr

    def run_json(self, entries, *args, **kw):
        out_json = self.base / "result.json"
        code, text = self.run_tool(entries, "--all", "--json", str(out_json), *args, **kw)
        data = json.loads(out_json.read_text()) if out_json.exists() else None
        return code, text, data

    def by_id(self, data):
        return {r["id"]: r for r in data["results"]}

    def assertClean(self):
        """No temporary copy is left and the checkout is byte-identical."""
        self.assertEqual(list(self.tmp.iterdir()), [], "temporary folder not removed")
        self.assertEqual(digest_tree(self.repo), self.before, "the checkout changed")

    # -- 1-3: the match must be exact ------------------------------------------------------------------------------------
    def test_apply_matches_exactly_once(self):
        m = mutate.Mutation(id="a.b.c", file="x", find="a + b", replace="a - b", why="w", tests=("test_calc.lua",))
        self.assertEqual(mutate.apply_to_bytes(CALC.encode(), m), CALC.replace("a + b", "a - b").encode())

    def test_missing_pattern_is_invalid_not_killed(self):
        code, text, data = self.run_json([entry("fake.m.missing", "return a % b", "return a - b")])
        r = self.by_id(data)["fake.m.missing"]
        self.assertEqual(r["status"], "invalid")
        self.assertIn("found 0 times", r["message"])
        self.assertEqual(code, 1)
        self.assertEqual(r["tests_run"], [], "an invalid mutation must not run a test")
        self.assertClean()

    def test_ambiguous_pattern_is_invalid(self):
        code, text, data = self.run_json([entry("fake.m.ambiguous", "a * 2", "a * 3")])
        r = self.by_id(data)["fake.m.ambiguous"]
        self.assertEqual(r["status"], "invalid")
        self.assertIn("ambiguous: found 2 times", r["message"])
        self.assertEqual(code, 1)
        self.assertClean()

    def test_unchanged_replacement_is_rejected_by_the_catalog_check(self):
        code, text = self.run_tool([entry("fake.m.same", "a + b", "a + b")], "--all")
        self.assertEqual(code, 64)
        self.assertIn("different from replace", text)
        self.assertClean()

    # -- 4: the baseline guards the campaign ---------------------------------------------------------------------------
    def test_baseline_failure_stops_the_campaign(self):
        code, text, data = self.run_json([entry("fake.m.add", "return a + b", "return a - b", tests=("test_broken.lua",))])
        self.assertEqual(code, 3)
        self.assertIn("BASELINE FAILED: test_broken.lua", text)
        self.assertNotIn("[  1/1]", text, "no mutation may be classified after a failed baseline")
        self.assertEqual(data["results"], [])
        self.assertClean()

    # -- 5-6: killed and survived are reported distinctly -----------------------------------------------------------------
    def test_killed_survived_and_kinds(self):
        entries = [
            entry("fake.m.add", "return a + b", "return a - b"),                                   # an assertion fails
            entry("fake.m.pick", "return t.value", "return t.value.x"),                            # the code crashes
            entry("fake.m.unchecked", "return a * 1", "return a * 2"),                             # nothing tests it
        ]
        code, text, data = self.run_json(entries)
        r = self.by_id(data)
        self.assertEqual((r["fake.m.add"]["status"], r["fake.m.add"]["kind"]), ("killed", "assertion"))
        self.assertEqual(r["fake.m.add"]["killed_by"], "test_calc.lua")
        self.assertEqual((r["fake.m.pick"]["status"], r["fake.m.pick"]["kind"]), ("killed", "runtime-error"))
        self.assertEqual(r["fake.m.unchecked"]["status"], "survived")
        self.assertEqual(data["counts"], {"killed": 2, "survived": 1, "invalid": 0, "timeout": 0, "infra": 0})
        self.assertEqual(code, 1, "an unexpected survivor fails the campaign")
        self.assertIn("SURVIVED (expected killed): fake.m.unchecked", text)
        self.assertIn("reproduce:  bash", text)
        self.assertIn("detection: 2 of 3 applied mutations killed", text)
        self.assertClean()

    def test_known_survivor_is_expected_and_listed(self):
        code, text, data = self.run_json([entry("fake.m.unchecked", "return a * 1", "return a * 2", expect="survived", note="not observable")])
        self.assertEqual(code, 0)
        self.assertIn("known survivors", text)
        self.assertEqual(self.by_id(data)["fake.m.unchecked"]["expected"], True)
        self.assertClean()

    def test_known_survivor_that_is_killed_is_flagged(self):
        code, text, data = self.run_json([entry("fake.m.add", "return a + b", "return a - b", expect="survived", note="stale")])
        self.assertEqual(code, 1)
        self.assertIn("NOT AS EXPECTED", text)
        self.assertClean()

    def test_broad_says_where_a_survivor_is_caught(self):
        e = [entry("fake.m.unchecked", "return a * 1", "return a * 2")]
        code, text, data = self.run_json(e, "--broad", suite=dict(broad_tests=["test_extra.lua"]))
        r = self.by_id(data)["fake.m.unchecked"]
        self.assertEqual((r["status"], r["broad_killed_by"]), ("survived", "test_extra.lua"))     # still a survivor of its focused tests
        self.assertIn("broader run: a test outside the focused set DOES fail: test_extra.lua", text)
        self.assertEqual(code, 1)
        code, text, data = self.run_json(e)
        self.assertEqual(self.by_id(data)["fake.m.unchecked"]["broad_killed_by"], "", "the broader tests are opt-in")
        self.assertClean()

    def test_a_clean_campaign_exits_zero(self):
        code, text, data = self.run_json([entry("fake.m.add", "return a + b", "return a - b")])
        self.assertEqual(code, 0)
        self.assertIn("detection: 1 of 1 applied mutations killed", text)
        self.assertNotIn("NOT a clean score", text)
        self.assertClean()

    def test_an_error_the_addon_caught_is_a_failure_like_run_sh(self):
        code, text, data = self.run_json([entry("fake.m.add", "return a + b", "return a - b", tests=("test_errormark.lua",))])
        r = self.by_id(data)["fake.m.add"]
        self.assertEqual((r["status"], r["kind"]), ("killed", "caught-error"))
        self.assertClean()

    # -- 7: syntax-invalid mutants -------------------------------------------------------------------------------------
    def test_syntax_error_is_invalid_not_a_kill(self):
        code, text, data = self.run_json([entry("fake.m.syntax", "return a + b", "return a + +")])
        r = self.by_id(data)["fake.m.syntax"]
        self.assertEqual(r["status"], "invalid")
        self.assertIn("does not parse", r["message"])
        self.assertEqual(r["tests_run"], [])
        self.assertEqual(data["counts"]["killed"], 0)
        self.assertEqual(code, 1)
        self.assertIn("NOT a clean score", text)
        self.assertClean()

    # -- 8: a hang is a timeout, not a detection -----------------------------------------------------------------------
    def test_timeout_is_not_a_kill(self):
        started = time.monotonic()
        code, text, data = self.run_json([entry("fake.m.hang", "n = n - 1", "n = n + 1")], "--timeout", "2")
        r = self.by_id(data)["fake.m.hang"]
        self.assertEqual(r["status"], "timeout")
        self.assertEqual(r["killed_by"], "")
        self.assertEqual(data["counts"]["killed"], 0)
        self.assertEqual(code, 1)
        self.assertLess(time.monotonic() - started, 30)
        self.assertClean()

    # -- 9: infrastructure failures are not kills ----------------------------------------------------------------------
    def test_test_command_failures_are_infra(self):
        entries = [entry("fake.m.exit127", "return a + b", "return a - b", tests=("test_exit.lua",)),
                   entry("fake.m.selfkill", "return a + b", "return a - b", tests=("test_selfkill.lua",))]
        code, text, data = self.run_json(entries)
        r = self.by_id(data)
        self.assertEqual(r["fake.m.exit127"]["status"], "infra")
        self.assertEqual(r["fake.m.selfkill"]["status"], "infra")
        self.assertEqual(data["counts"]["killed"], 0)
        self.assertEqual(code, 2)
        self.assertClean()

    def test_missing_tool_is_an_infrastructure_error(self):
        code, text = self.run_tool([entry("fake.m.add", "return a + b", "return a - b")], "--all", suite=dict(command=["no-such-lua-xyz", "{test}"]))
        self.assertEqual(code, 2)
        self.assertIn("required tool not found", text)
        self.assertClean()

    def test_source_edited_during_the_run_is_reported(self):
        live = self.repo / "TwichUI_Workshop" / "calc.lua"
        (self.repo / "tests" / "test_liveedit.lua").write_text(
            f'local f = assert(loadfile("../TwichUI_Workshop/calc.lua")); f()\nlocal h = io.open("{live}", "a"); h:write("-- edited\\n"); h:close()\nprint("PASSED")\n')
        self.before = digest_tree(self.repo)
        code, text = self.run_tool([entry("fake.m.add", "return a + b", "return a - b", tests=("test_liveedit.lua",))], "--all")
        live.write_text(CALC)               # undo what the fake test did to the fake checkout
        self.assertEqual(code, 2, text)     # a test wrote to the checkout: the runner must notice and refuse to trust the results
        self.assertIn("SOURCE CHANGED DURING THE RUN", text)
        self.assertClean()

    def test_the_callers_environment_does_not_reach_the_tests(self):
        # test_env.lua is its own baseline: it fails (exit 3) if MUT_LEAK, or the caller's real HOME, reached it
        code, text, data = self.run_json([entry("fake.m.env", "return a + b", "return a - b", tests=("test_env.lua",), expect="survived", note="the test does not use calc.lua")],
                                         env_extra={"MUT_LEAK": "1"})
        self.assertEqual(code, 0, text)
        self.assertEqual(self.by_id(data)["fake.m.env"]["status"], "survived")
        self.assertClean()

    # -- 10-12: copies, cleanup, --keep-failed, untouched sources -------------------------------------------------------
    def test_copies_are_outside_the_checkout_and_the_checkout_is_untouched(self):
        # the temporary folder inside the repository is refused outright
        inside = self.repo / "scratch"
        inside.mkdir()
        code, text = self.run_tool([entry("fake.m.add", "return a + b", "return a - b")], "--all", env_extra={"TMPDIR": str(inside)})
        self.assertEqual(code, 2)
        self.assertIn("inside the repository", text)
        shutil.rmtree(inside)
        self.assertEqual(digest_tree(self.repo), self.before)

    def test_mutation_cannot_target_outside_the_workshop(self):
        for bad in ("tests/test_calc.lua", "!!!TwichUI/stub.lua", "TwichUI_Workshop/../tests/test_calc.lua", "/etc/passwd"):
            code, text = self.run_tool([entry("fake.m.bad", "x", "y", file=bad)], "--all")
            self.assertEqual(code, 64, bad)
            self.assertIn("relative path under", text)
        self.assertClean()

    def test_keep_failed_keeps_only_the_failed_copy(self):
        entries = [entry("fake.m.add", "return a + b", "return a - b"),                           # killed: removed
                   entry("fake.m.unchecked", "return a * 1", "return a * 2")]                      # survives: kept
        code, text = self.run_tool(entries, "--all", "--keep-failed")
        self.assertEqual(code, 1)
        roots = list(self.tmp.iterdir())
        self.assertEqual(len(roots), 1)
        kept = sorted(p.name for p in roots[0].iterdir())
        self.assertEqual(len(kept), 1, kept)
        self.assertTrue(kept[0].endswith("fake.m.unchecked"))
        stage = roots[0] / kept[0]
        for name in ("MUTATION.txt", "OUTPUT.txt", "REPRODUCE.txt"):
            self.assertTrue((stage / name).is_file(), name)
        self.assertIn("a * 2", (stage / "TwichUI_Workshop" / "calc.lua").read_text())      # the mutation is in the copy
        self.assertIn("-  return a * 1", (stage / "MUTATION.txt").read_text())
        self.assertIn(str(stage), text)
        self.assertEqual(digest_tree(self.repo), self.before)                               # and only there
        shutil.rmtree(roots[0])

    def test_keep_failed_keeps_nothing_when_all_is_as_expected(self):
        code, text = self.run_tool([entry("fake.m.add", "return a + b", "return a - b")], "--all", "--keep-failed")
        self.assertEqual(code, 0)
        self.assertClean()

    def test_parallel_copies_do_not_influence_each_other(self):
        entries = [entry("fake.m.add", "return a + b", "return a - b"), entry("fake.m.lt", 'if a < b then return "lt" end', 'if a < b then return "gt" end'),
                   entry("fake.m.wait", "return n\n", "return n + 1\n"), entry("fake.m.twice", "return x + y", "return x")]
        code, text, data = self.run_json(entries, "--jobs", "4")
        self.assertEqual(code, 0, text)
        self.assertEqual(data["counts"]["killed"], 4)
        self.assertClean()

    # -- selection, catalog validation ------------------------------------------------------------------------------------
    def test_selection_and_listing(self):
        entries = [entry("fake.m.add", "return a + b", "return a - b", smoke=True), entry("other.m.lt", 'if a < b then return "lt" end', 'if a < b then return "gt" end')]
        code, text = self.run_tool(entries, "--list")
        self.assertEqual(code, 0)
        self.assertIn("fake.m.add", text)
        self.assertNotIn("other.m.lt", text, "with no selection only the smoke group is used")
        code, text = self.run_tool(entries, "--group", "other", "--list")
        self.assertIn("other.m.lt", text)
        self.assertNotIn("fake.m.add", text)
        code, text = self.run_tool(entries, "--id", "nope.x.y", "--list")
        self.assertEqual(code, 64)
        code, text = self.run_tool(entries, "--group", "missing", "--list")
        self.assertEqual(code, 64)
        self.assertClean()

    def test_bad_arguments_exit_64_not_2(self):
        code, text = self.run_tool([entry("fake.m.add", "return a + b", "return a - b")], "--jobs", "0")
        self.assertEqual(code, 64, text)
        code, text = self.run_tool([entry("fake.m.add", "return a + b", "return a - b")], "--no-such-option")
        self.assertEqual(code, 64, text)
        self.assertClean()

    def test_catalog_validation(self):
        for bad, needle in ((entry("Bad Id", "a", "b"), "id must look like"),
                            (entry("fake.m.t", "a", "b", tests=("test_missing.lua",)), "does not exist"),
                            (entry("fake.m.n", "a", "b", expect="survived"), "needs a note"),
                            (entry("fake.m.u", "a", "b", bogus=1), "unknown fields")):
            code, text = self.run_tool([bad], "--all")
            self.assertEqual(code, 64, needle)
            self.assertIn(needle, text)
        code, text = self.run_tool([entry("fake.m.d", "a", "b"), entry("fake.m.d", "c", "d")], "--all")
        self.assertEqual(code, 64)
        self.assertIn("duplicate", text)

    def test_check_validates_without_running_tests(self):
        code, text = self.run_tool([entry("fake.m.ok", "return a + b", "return a - b"), entry("fake.m.gone", "nope", "yes"),
                                    entry("fake.m.syntax", "return a + b", "return a + +")], "--all", "--check")
        self.assertEqual(code, 1)
        self.assertIn("ok      fake.m.ok", text)
        self.assertIn("INVALID fake.m.gone", text)
        self.assertIn("INVALID fake.m.syntax", text)
        self.assertClean()

    # -- interruption ---------------------------------------------------------------------------------------------------------
    def test_sigterm_removes_the_copies_and_the_children(self):
        cat = self.base / "catalog.py"
        cat.write_text(f"SUITE = {dict(command=['lua5.1', '{test}'], copy_files=[], tests_subdirs=[])!r}\n"
                       f"MUTATIONS = {[entry('fake.m.sleep', 'return a + b', 'return a - b', tests=('test_sleep.lua',))]!r}\n")
        env = dict(os.environ, TMPDIR=str(self.tmp))
        p = subprocess.Popen([sys.executable, "-B", "-I", str(TOOLS / "mutate.py"), "--repo", str(self.repo), "--catalog", str(cat), "--all"],
                             env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline and not sleepers():
                time.sleep(0.1)
            self.assertTrue(sleepers(), "the mutant's test never started")
            p.send_signal(signal.SIGTERM)
            out, _ = p.communicate(timeout=20)
        finally:
            if p.poll() is None:
                p.kill()
        self.assertEqual(p.returncode, 143, out)
        self.assertIn("interrupted", out)
        time.sleep(0.5)
        self.assertEqual(sleepers(), [], "a child process survived the interrupt")
        self.assertClean()

    # -- the judge ---------------------------------------------------------------------------------------------------------
    def test_judge(self):
        s = mutate.Suite(repo=REAL_REPO)
        self.assertEqual(mutate.judge(s, 0, "PASSED\n"), ("pass", ""))
        self.assertEqual(mutate.judge(s, 0, "ERROR: x\nPASSED\n"), ("fail", "caught-error"))
        self.assertEqual(mutate.judge(s, 0, "nothing\n"), ("fail", "no-pass-marker"))
        self.assertEqual(mutate.judge(s, 1, "lua5.1: t.lua:3: expected 5\n"), ("fail", "assertion"))
        self.assertEqual(mutate.judge(s, 1, "lua5.1: P.lua:9: attempt to index a nil value\n"), ("fail", "runtime-error"))
        self.assertEqual(mutate.judge(s, 127, "")[0], "infra")
        self.assertEqual(mutate.judge(s, -9, "")[0], "infra")
        self.assertEqual(mutate.judge(s, 1, "lua5.1: cannot open test_x.lua\n")[0], "infra")

    # -- the real catalog ------------------------------------------------------------------------------------------------------
    def test_real_catalog_matches_the_source(self):
        """Every pattern of the shipped catalog still matches the Workshop source exactly once and still parses (no test is run)."""
        before = digest_tree(REAL_REPO / "TwichUI_Workshop")
        p = subprocess.run(["bash", str(TOOLS / "mutate.sh"), "--all", "--check"], capture_output=True, text=True,
                           env=dict(os.environ, TMPDIR=str(self.tmp)), cwd=str(self.base))
        self.assertEqual(p.returncode, 0, p.stdout[-3000:] + p.stderr[-1000:])
        self.assertEqual(digest_tree(REAL_REPO / "TwichUI_Workshop"), before)
        self.assertEqual(list(self.tmp.iterdir()), [])


def sleepers():
    """Processes running `sleep 37.123` (the fake mutant's test), found through /proc."""
    found = []
    for d in Path("/proc").iterdir():
        if d.name.isdigit():
            try:
                if b"37.123" in (d / "cmdline").read_bytes():
                    found.append(int(d.name))
            except OSError:
                pass
    return found


if __name__ == "__main__":
    unittest.main()
