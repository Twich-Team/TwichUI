"""tools/release.py: versions, release notes, .toc stamping, package checks and publishing.

Versions and notes are worked out in throwaway git repositories (main and beta pushes, stable tags, a first
release, diverged branches, re-runs, a shallow clone). Publishing runs against in-memory stand-ins for GitHub
and CurseForge, so it shows the order of steps and what a re-run does, not that the real services accept them.

Run: python3 -m unittest discover -s tests -p "test_release_tools.py"
"""
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import release as rel  # noqa: E402

CORE_TOC = "## Interface: 16001\n## Title: |cffC9A24ATwich|rUI\n## Version: 1.0.0\n## X-Curse-Project-ID: 1719280\n\nCore.lua\n"
SETTINGS_TOC = ("## Interface: 16001\n## Title: Settings\n## Version: 1.0.0\n## RequiredDeps: !!!TwichUI\n"
                "## LoadOnDemand: 1\n\nKit.lua\n")
NAVDATA_TOC = ("## Interface: 16001\n## Title: Navigation Data\n## Version: 1.0.0\n## RequiredDeps: !!!TwichUI\n"
               "## LoadOnDemand: 1\n\nData\\Map0.lua\n")
DIAG_TOC = ("## Interface: 16001\n## Title: Diagnostics\n## Version: 1.0.0\n## RequiredDeps: !!!TwichUI\n"
            "## LoadOnDemand: 1\n\nBase.lua\n")
LAYOUTS_TOC = ("## Interface: 16001\n## Title: Layouts\n## Version: 1.0.0\n## RequiredDeps: !!!TwichUI\n"
               "## LoadOnDemand: 1\n\nCanon.lua\n")


class Repo:
    """A throwaway repository with the two addon folders."""

    def __init__(self, root):
        self.root = Path(root)
        self.run("init", "-q", "-b", "main")
        self.run("config", "user.email", "test@example.invalid")
        self.run("config", "user.name", "Test")
        self.run("config", "commit.gpgsign", "false")
        self.run("config", "tag.gpgsign", "false")
        self.write(rel.TOCS[rel.CORE], CORE_TOC)
        self.write(rel.TOCS[rel.SETTINGS], SETTINGS_TOC)
        self.write(rel.TOCS[rel.NAVDATA], NAVDATA_TOC)
        self.write(rel.TOCS[rel.DIAGNOSTICS], DIAG_TOC)
        self.write(rel.TOCS[rel.LAYOUTS], LAYOUTS_TOC)
        self.n = 0

    def run(self, *args):
        env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        return subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True, text=True,
                              env=env).stdout.strip()

    def write(self, path, text):
        p = self.root / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)

    def commit(self, message):
        self.n += 1
        self.write("!!!TwichUI/Core.lua", f"-- {self.n}\n")
        self.run("add", "-A")
        self.run("commit", "-q", "-m", message)
        return self.run("rev-parse", "HEAD")

    def tag(self, name, message=None):
        self.run("tag", *(["-a", "-m", message] if message else []), name)

    def plan(self, ref):
        return rel.plan(ref, repo_url="https://github.com/o/r", cwd=self.root)


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Repo(self.tmp.name)

    def test_main_push_after_a_stable_tag(self):
        r = self.repo
        r.commit("first")
        r.tag("v1.0.0")
        r.commit("add a thing")
        head = r.commit("fix: a crash")
        meta, notes = r.plan("refs/heads/main")
        self.assertEqual(meta["channel"], "alpha")
        self.assertEqual(meta["version"], f"1.0.1-alpha.2.g{head[:7]}")
        self.assertEqual(meta["tag"], "v" + meta["version"])
        self.assertTrue(meta["prerelease"])
        self.assertFalse(meta["make_latest"])
        self.assertEqual(meta["previous"]["tag"], "v1.0.0")
        self.assertIn("### Fixes", notes)
        self.assertIn("- a crash", notes)
        self.assertIn("- add a thing", notes)
        self.assertNotIn("first", notes)
        self.assertIn("compare", notes)

    def test_next_alpha_starts_after_the_last_published_alpha(self):
        r = self.repo
        r.commit("first")
        r.tag("v1.0.0")
        r.commit("one")
        meta, _ = r.plan("refs/heads/main")
        r.tag(meta["tag"])  # what publishing the alpha leaves behind
        r.commit("two")
        meta2, notes = r.plan("refs/heads/main")
        self.assertEqual(meta2["previous"]["tag"], meta["tag"])
        self.assertIn("- two", notes)
        self.assertNotIn("- one", notes)

    def test_beta_ignores_alpha_tags(self):
        r = self.repo
        r.commit("first")
        r.tag("v1.0.0")
        r.commit("one")
        meta, _ = r.plan("refs/heads/main")
        r.tag(meta["tag"])
        r.run("branch", "beta")
        r.run("checkout", "-q", "beta")
        head = r.commit("two")
        meta, notes = r.plan("refs/heads/beta")
        self.assertEqual(meta["version"], f"1.0.1-beta.2.g{head[:7]}")
        self.assertEqual(meta["previous"]["tag"], "v1.0.0")
        self.assertIn("- one", notes)
        self.assertIn("Beta build", notes)

    def test_beta_push_of_a_commit_already_published_as_alpha(self):
        r = self.repo
        r.commit("first")
        r.tag("v1.0.0")
        r.commit("one")
        meta, _ = r.plan("refs/heads/main")
        r.tag(meta["tag"])
        meta, _ = r.plan("refs/heads/beta")
        self.assertTrue(meta["publish"])
        self.assertEqual(meta["channel"], "beta")
        self.assertIn("-beta.1.", meta["version"])

    def test_stable_tag(self):
        r = self.repo
        r.commit("first")
        r.tag("v1.0.0")
        r.commit("one")
        meta, _ = r.plan("refs/heads/main")
        r.tag(meta["tag"])
        r.commit("two")
        r.tag("v1.1.0", "Bigger **highlights**, written by hand.")
        meta, notes = r.plan("refs/tags/v1.1.0")
        self.assertEqual((meta["channel"], meta["version"], meta["tag"]), ("release", "1.1.0", "v1.1.0"))
        self.assertFalse(meta["prerelease"])
        self.assertTrue(meta["make_latest"])
        self.assertEqual(meta["previous"]["tag"], "v1.0.0", "stable notes skip prerelease tags")
        self.assertIn("- one", notes)
        self.assertIn("- two", notes)
        self.assertIn("### Highlights\n\nBigger **highlights**, written by hand.", notes)
        self.assertIn("{classic}", meta["packager_name"])

    def test_lightweight_stable_tag_has_no_highlights(self):
        r = self.repo
        r.commit("first")
        r.tag("v1.0.0")
        _, notes = r.plan("refs/tags/v1.0.0")
        self.assertNotIn("Highlights", notes)
        self.assertIn("The first release.", notes)

    def test_first_release_without_tags(self):
        r = self.repo
        r.commit("first")
        head = r.commit("second")
        meta, notes = r.plan("refs/heads/main")
        self.assertEqual(meta["version"], f"1.0.0-alpha.2.g{head[:7]}", "prereleases build toward 1.0.0")
        self.assertIsNone(meta["previous"])
        self.assertIn("- first", notes)
        self.assertIn("whole history", notes)

    def test_version_reset_with_retired_tags_archived(self):
        r = self.repo
        r.commit("old work")
        r.tag("archive/v3.0.12")  # a retired 3.x tag, moved out of v*
        head = r.commit("launch prep")
        meta, _ = r.plan("refs/heads/main")
        self.assertEqual(meta["version"], f"1.0.0-alpha.2.g{head[:7]}")
        r.run("tag", "v1.0.0")
        meta, notes = r.plan("refs/tags/v1.0.0")
        self.assertEqual(meta["version"], "1.0.0")
        self.assertIsNone(meta["previous"])
        self.assertIn("The first release.", notes)
        self.assertNotIn("launch prep", notes, "a first release lists no development history")
        r.commit("after launch")
        meta, _ = r.plan("refs/heads/main")
        self.assertTrue(meta["version"].startswith("1.0.1-alpha.1."))

    def test_stable_tag_below_a_contained_one_is_refused(self):
        r = self.repo
        r.commit("old work")
        r.tag("v3.0.12")  # a retired tag left in place
        r.commit("launch")
        r.tag("v1.0.0")
        with self.assertRaisesRegex(rel.ReleaseError, "not newer than v3.0.12"):
            r.plan("refs/tags/v1.0.0")

    def test_diverged_branches_use_the_tags_they_contain(self):
        r = self.repo
        r.commit("first")
        r.tag("v1.0.0")
        r.run("branch", "beta")
        r.commit("main only")
        r.tag("v1.0.1")
        r.commit("after 1.0.1")
        main, _ = r.plan("refs/heads/main")
        self.assertTrue(main["version"].startswith("1.0.2-alpha.1."))
        r.run("checkout", "-q", "beta")
        r.commit("beta only")
        beta, notes = r.plan("refs/heads/beta")
        self.assertTrue(beta["version"].startswith("1.0.1-beta.1."), beta["version"])
        self.assertNotIn("main only", notes)

    def test_rerun_and_duplicates_publish_nothing(self):
        r = self.repo
        r.commit("first")
        r.tag("v1.0.0")
        meta, notes = r.plan("refs/heads/main")
        self.assertFalse(meta["publish"])
        self.assertIn("stable release v1.0.0", meta["skip_reason"])
        self.assertIsNone(notes)

        r.commit("one")
        meta, _ = r.plan("refs/heads/main")
        r.tag(meta["tag"])
        again, _ = r.plan("refs/heads/main")
        self.assertFalse(again["publish"])
        self.assertIn("already published", again["skip_reason"])

        old = r.run("rev-parse", "HEAD")
        r.commit("two")
        newer, _ = r.plan("refs/heads/main")
        r.tag(newer["tag"])
        r.run("checkout", "-q", old)
        r.run("tag", "-d", meta["tag"])  # the older build's tag is gone: it is still superseded
        stale, _ = r.plan("refs/heads/main")
        self.assertFalse(stale["publish"])
        self.assertIn("superseded", stale["skip_reason"])

    def test_missing_previous_tag_falls_back_to_stable(self):
        r = self.repo
        r.commit("first")
        r.tag("v1.0.0")
        r.commit("one")
        meta, _ = r.plan("refs/heads/main")
        r.tag(meta["tag"])
        r.run("tag", "-d", meta["tag"])
        r.commit("two")
        meta, notes = r.plan("refs/heads/main")
        self.assertEqual(meta["previous"]["tag"], "v1.0.0")
        self.assertIn("- one", notes)

    def test_refusals(self):
        r = self.repo
        r.commit("first")
        r.tag("v1.0.0")
        r.tag("v1.0.0-beta1")
        r.commit("one")
        with self.assertRaisesRegex(rel.ReleaseError, "not a stable version tag"):
            r.plan("refs/tags/v1.0.0-beta1")
        with self.assertRaisesRegex(rel.ReleaseError, "does not point at"):
            r.plan("refs/tags/v1.0.0")
        with self.assertRaisesRegex(rel.ReleaseError, "no release channel"):
            r.plan("refs/heads/feature")
        with self.assertRaisesRegex(rel.ReleaseError, "is for"):
            rel.plan("refs/heads/main", sha="0" * 40, cwd=r.root)

    def test_shallow_clone_is_refused(self):
        r = self.repo
        r.commit("first")
        r.commit("second")
        clone = Path(self.tmp.name) / "shallow"
        subprocess.run(["git", "clone", "-q", "--depth", "1", f"file://{r.root}", str(clone)], check=True)
        with self.assertRaisesRegex(rel.ReleaseError, "shallow"):
            rel.plan("refs/heads/main", cwd=clone)

    def test_version_fits_shared_setups(self):
        r = self.repo
        r.commit("first")
        r.tag("v100.200.300")
        r.commit("one")
        meta, _ = r.plan("refs/heads/main")
        self.assertLessEqual(len(meta["version"]), rel.MAX_VERSION_LEN)


class NotesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Repo(self.tmp.name)
        self.repo.commit("first")
        self.repo.tag("v1.0.0")

    def notes(self):
        return self.repo.plan("refs/heads/main")[1]

    def test_commit_text_is_inert(self):
        r = self.repo
        r.commit('evil <script>alert(1)</script> $(touch pwned) `x` [link](http://x) @someone *b* | \u202eabc')
        notes = self.notes()
        self.assertNotIn("<script>", notes)
        self.assertIn("\\<script\\>", notes)
        self.assertIn("\\[link\\](http://x)", notes)
        self.assertIn("@\u200bsomeone", notes)
        self.assertIn("\\`x\\`", notes)
        self.assertNotIn("\u202e", notes)
        self.assertFalse((Path(self.tmp.name) / "pwned").exists())

    def test_grouping_merges_duplicates_and_skips(self):
        r = self.repo
        r.commit("feat(pins): share a pin")
        r.commit("fix!: settings reset")
        r.commit("chore: tidy")
        r.commit("ci: pin actions")
        r.commit("plain change")
        r.commit("plain change")
        r.commit("fixup! plain change")
        r.commit("noise [skip changelog]")
        r.commit("quiet [skip ci]")
        r.run("checkout", "-q", "-b", "side")
        r.commit("from a branch")
        r.run("checkout", "-q", "main")
        r.run("merge", "-q", "--no-ff", "-m", "Merge branch 'side'", "side")
        notes = self.notes()
        self.assertIn("### Features\n\n- share a pin", notes)
        self.assertIn("### Fixes\n\n- **Breaking:** settings reset", notes)
        self.assertEqual(notes.count("plain change"), 1)
        self.assertNotIn("fixup", notes)
        self.assertNotIn("noise", notes)
        self.assertIn("- quiet (", notes)
        self.assertIn("- from a branch", notes)
        self.assertNotIn("Merge branch", notes)
        self.assertIn("_2 maintenance commits", notes)
        self.assertNotIn("tidy", notes)

    def test_only_maintenance(self):
        self.repo.commit("ci: something")
        self.assertIn("No player-facing changes", self.notes())

    def test_long_history_is_capped(self):
        for i in range(rel.MAX_ENTRIES + 5):
            self.repo.commit(f"change {i}")
        notes = self.notes()
        self.assertEqual(notes.count("\n- change "), rel.MAX_ENTRIES)
        self.assertIn("…and 5 more.", notes)


class StampTests(unittest.TestCase):
    def test_stamps_only_the_version_line(self):
        with tempfile.TemporaryDirectory() as d:
            for rel_path, text in ((rel.TOCS[rel.CORE], CORE_TOC), (rel.TOCS[rel.SETTINGS], SETTINGS_TOC), (rel.TOCS[rel.NAVDATA], NAVDATA_TOC), (rel.TOCS[rel.DIAGNOSTICS], DIAG_TOC), (rel.TOCS[rel.LAYOUTS], LAYOUTS_TOC)):
                p = Path(d, rel_path)
                p.parent.mkdir(parents=True)
                p.write_bytes(text.replace("\n", "\r\n").encode())
            rel.stamp("2.0.1-beta.3.gabcdef0", d)
            core = Path(d, rel.TOCS[rel.CORE]).read_bytes()
            self.assertEqual(core, CORE_TOC.replace("1.0.0", "2.0.1-beta.3.gabcdef0").replace("\n", "\r\n").encode())

    def test_refuses_missing_or_repeated_version(self):
        with tempfile.TemporaryDirectory() as d:
            for rel_path in rel.TOCS.values():
                p = Path(d, rel_path)
                p.parent.mkdir(parents=True)
                p.write_text("## Interface: 16001\n## Version: 1\n## Version: 2\n")
            with self.assertRaisesRegex(rel.ReleaseError, "2 '## Version:' lines"):
                rel.stamp("3", d)


class ArchiveTests(unittest.TestCase):
    VERSION = "1.0.1-alpha.2.gabcdef0"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for rel_path, text in ((rel.TOCS[rel.CORE], CORE_TOC), (rel.TOCS[rel.SETTINGS], SETTINGS_TOC), (rel.TOCS[rel.NAVDATA], NAVDATA_TOC), (rel.TOCS[rel.DIAGNOSTICS], DIAG_TOC), (rel.TOCS[rel.LAYOUTS], LAYOUTS_TOC)):
            (self.root / rel_path).parent.mkdir(parents=True)
            (self.root / rel_path).write_text(text)

    def make(self, files=None, version=VERSION, drop=()):
        entries = {
            rel.TOCS[rel.CORE]: CORE_TOC.replace("1.0.0", version),
            rel.TOCS[rel.SETTINGS]: SETTINGS_TOC.replace("1.0.0", version),
            rel.TOCS[rel.NAVDATA]: NAVDATA_TOC.replace("1.0.0", version),
            rel.TOCS[rel.DIAGNOSTICS]: DIAG_TOC.replace("1.0.0", version),
            rel.TOCS[rel.LAYOUTS]: LAYOUTS_TOC.replace("1.0.0", version),
            "!!!TwichUI/Core.lua": "-- core\n",
            "TwichUI_Settings/Kit.lua": "-- kit\n",
            "TwichUI_NavData/Data/Map0.lua": "-- walking map\n",
            "TwichUI_Diagnostics/Base.lua": "-- diagnostics\n",
            "TwichUI_Layouts/Canon.lua": "-- layouts\n",
        }
        entries.update(files or {})
        path = self.root / "pkg.zip"
        with zipfile.ZipFile(path, "w") as z:
            for name, text in entries.items():
                if name not in drop:
                    z.writestr(name, text)
        return rel.check_archive(path, self.VERSION, self.root)

    def test_good_package(self):
        self.assertEqual(self.make(), [])

    def test_good_package_with_windows_line_endings(self):
        # the packager writes CRLF unless told otherwise (-u)
        crlf = {rel.TOCS[rel.CORE]: CORE_TOC.replace("1.0.0", self.VERSION).replace("\n", "\r\n"),
                rel.TOCS[rel.SETTINGS]: SETTINGS_TOC.replace("1.0.0", self.VERSION).replace("\n", "\r\n"),
                rel.TOCS[rel.NAVDATA]: NAVDATA_TOC.replace("1.0.0", self.VERSION).replace("\n", "\r\n"),
                rel.TOCS[rel.DIAGNOSTICS]: DIAG_TOC.replace("1.0.0", self.VERSION).replace("\n", "\r\n"),
                rel.TOCS[rel.LAYOUTS]: LAYOUTS_TOC.replace("1.0.0", self.VERSION).replace("\n", "\r\n")}
        self.assertEqual(self.make(crlf), [])

    def test_problems_are_found(self):
        cases = {
            "top-level": {"TwichUI/Core.lua": ""},
            "nested addon": {"!!!TwichUI/TwichUI_Settings/Kit.lua": ""},
            "misspelled": {"TwitchUI_Settings/x.lua": ""},
            "development file": {"!!!TwichUI/tests/test.lua": ""},
            "machine-specific": {"!!!TwichUI/x.lua": "-- C:\\Users\\rich\\x"},
            "secret-like": {"!!!TwichUI/y.lua": "CF_API_KEY = 1"},
        }
        for what, extra in cases.items():
            with self.subTest(what):
                self.assertTrue(any(what in p for p in self.make(extra)), self.make(extra))
        self.assertTrue(any("Version" in p for p in self.make(version="1.0.0")))
        self.assertTrue(any("loads Core.lua" in p for p in self.make(drop=("!!!TwichUI/Core.lua",))))
        lod = SETTINGS_TOC.replace("## LoadOnDemand: 1\n", "").replace("1.0.0", self.VERSION)
        self.assertTrue(any("load on demand" in p for p in self.make({rel.TOCS[rel.SETTINGS]: lod})))
        navlod = NAVDATA_TOC.replace("## LoadOnDemand: 1\n", "").replace("1.0.0", self.VERSION)
        self.assertTrue(any("TwichUI_NavData is not load on demand" in p for p in self.make({rel.TOCS[rel.NAVDATA]: navlod})))
        self.assertTrue(any("top-level" in p for p in self.make(drop=(rel.TOCS[rel.NAVDATA], "TwichUI_NavData/Data/Map0.lua"))))
        diaglod = DIAG_TOC.replace("## LoadOnDemand: 1\n", "").replace("1.0.0", self.VERSION)
        self.assertTrue(any("TwichUI_Diagnostics is not load on demand" in p for p in self.make({rel.TOCS[rel.DIAGNOSTICS]: diaglod})))
        layoutslod = LAYOUTS_TOC.replace("## LoadOnDemand: 1\n", "").replace("1.0.0", self.VERSION)
        self.assertTrue(any("TwichUI_Layouts is not load on demand" in p for p in self.make({rel.TOCS[rel.LAYOUTS]: layoutslod})))
        self.assertTrue(any("top-level" in p for p in self.make(drop=(rel.TOCS[rel.LAYOUTS], "TwichUI_Layouts/Canon.lua"))))


class FakeGitHub:
    def __init__(self):
        self.releases_, self.tags, self.next_id, self.calls = [], {}, 1, []

    def releases(self):
        return [dict(r) for r in self.releases_]

    def tag_commit(self, tag):
        return self.tags.get(tag)

    def _find(self, rid):
        return next(r for r in self.releases_ if r["id"] == rid)

    def create_draft(self, tag, sha, name, body, prerelease):
        self.calls.append("create")
        r = {"id": self.next_id, "tag_name": tag, "target": sha, "name": name, "body": body, "draft": True,
             "prerelease": prerelease, "assets": [], "html_url": f"https://example.invalid/{tag}"}
        self.next_id += 1
        self.releases_.append(r)
        return dict(r)

    def update(self, rid, fields):
        r = self._find(rid)
        if getattr(self, "fail_publish", False) and fields.get("draft") is False:
            raise rel.ReleaseError("GitHub API failed")
        if r["draft"] and "tag_name" not in fields:
            # as GitHub did on 2026-10-15: a draft edited without its tag falls back to the placeholder tag
            r["tag_name"] = f"untagged-{rid:020x}"
        if "target_commitish" in fields:
            r["target"] = fields.pop("target_commitish")
        r.update(fields)
        if r["draft"] is False and r["tag_name"] not in self.tags:
            self.tags[r["tag_name"]] = r["target"]
        if fields.get("draft") is False:
            self.calls.append(f"publish latest={fields['make_latest']}")
        return dict(r)

    def delete_asset(self, aid):
        for r in self.releases_:
            r["assets"] = [a for a in r["assets"] if a["id"] != aid]

    def upload_asset(self, rid, path, name):
        self.calls.append(f"asset {name}")
        asset = {"id": len(self.calls), "name": name.lstrip("!"), "state": "uploaded"}  # as GitHub renames
        self._find(rid)["assets"].append(asset)
        return dict(asset)


class FakeCurseForge:
    def __init__(self, results):
        self.results, self.uploads = list(results), []

    def game_version_id(self, name):
        return 1234, name, None

    def upload(self, zip_path, metadata):
        self.uploads.append(metadata)
        return self.results.pop(0)


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.zip = Path(self.tmp.name, "!!!TwichUI-v1.0.1-alpha.2.gabcdef0-forever.zip")
        with zipfile.ZipFile(self.zip, "w") as z:
            z.writestr(rel.TOCS[rel.CORE], CORE_TOC)
        self.meta = {"channel": "alpha", "version": "1.0.1-alpha.2.gabcdef0", "tag": "v1.0.1-alpha.2.gabcdef0",
                     "commit": "a" * 40, "prerelease": True, "make_latest": False}
        self.gh = FakeGitHub()
        self.log = []

    def publish(self, cf):
        return rel.publish(self.meta, self.zip, "notes\n", self.gh, cf, log=self.log.append, sleep=lambda s: None)

    def state(self):
        return rel.marker(self.gh.releases_[0]["body"])

    def test_happy_path_then_rerun(self):
        cf = FakeCurseForge([("uploaded", 99)])
        self.assertEqual(self.publish(cf), "published")
        self.assertEqual(self.gh.calls, ["create", "asset " + self.zip.name.lstrip("!"), "asset release.json",
                                         "publish latest=false"])
        self.assertEqual(cf.uploads[0]["releaseType"], "alpha")
        self.assertEqual(cf.uploads[0]["displayName"], "v1.0.1-alpha.2.gabcdef0-forever")
        self.assertEqual(cf.uploads[0]["gameVersions"], [1234])
        self.assertEqual(self.state()["curseforge"], "uploaded")
        self.assertEqual(self.gh.tags[self.meta["tag"]], self.meta["commit"])
        self.assertEqual([a["name"] for a in self.gh.releases_[0]["assets"]],
                         ["TwichUI-v1.0.1-alpha.2.gabcdef0-forever.zip", "release.json"])
        self.assertEqual(self.publish(FakeCurseForge([])), "already-published")
        self.assertEqual(len(cf.uploads), 1)

    def test_release_keeps_its_tag_through_every_edit(self):
        self.publish(FakeCurseForge([("uploaded", 99)]))
        self.assertEqual(self.gh.releases_[0]["tag_name"], self.meta["tag"])
        self.assertEqual(list(self.gh.tags), [self.meta["tag"]], "no placeholder tag is made")

    def test_release_published_under_a_placeholder_tag_is_repaired(self):
        # what the first alpha (v1.0.0-alpha.116.g0926105) was left as
        r = self.gh.create_draft(self.meta["tag"], self.meta["commit"], self.meta["tag"],
                                 rel.with_marker("notes", {"channel": "alpha", "commit": self.meta["commit"],
                                                           "version": self.meta["version"],
                                                           "curseforge": "uploaded"}), True)
        self.gh.update(r["id"], {"draft": False, "make_latest": "false"})
        stray = self.gh.releases_[0]["tag_name"]
        self.assertTrue(stray.startswith("untagged-"))
        cf = FakeCurseForge([])
        self.assertEqual(self.publish(cf), "repaired")
        self.assertEqual(cf.uploads, [], "CurseForge is not uploaded again")
        self.assertEqual(self.gh.releases_[0]["tag_name"], self.meta["tag"])
        self.assertEqual(self.gh.tags[self.meta["tag"]], self.meta["commit"])
        self.assertIn(f"Delete the leftover tag {stray}", self.log[-1])
        self.assertEqual(self.publish(cf), "already-published")

    def test_tag_made_a_moment_late(self):
        real = self.gh.tag_commit
        seen = []

        def late(tag):
            seen.append(tag)
            return real(tag) if len(seen) > 3 else None  # missing for the first checks after publishing
        self.gh.tag_commit = late
        self.assertEqual(self.publish(FakeCurseForge([("uploaded", 1)])), "published")

    def test_stable_is_marked_latest(self):
        self.meta.update(channel="release", prerelease=False, make_latest=True)
        cf = FakeCurseForge([("uploaded", 1)])
        self.publish(cf)
        self.assertEqual(cf.uploads[0]["releaseType"], "release")
        self.assertIn("publish latest=true", self.gh.calls)
        self.assertFalse(self.gh.releases_[0]["prerelease"])

    def test_refused_upload_stays_draft_and_rerun_retries(self):
        with self.assertRaisesRegex(rel.ReleaseError, "refused"):
            self.publish(FakeCurseForge([("failed", "HTTP 400")]))
        self.assertTrue(self.gh.releases_[0]["draft"])
        self.assertEqual(self.state()["curseforge"], "failed")
        self.assertNotIn(self.meta["tag"], self.gh.tags)
        cf = FakeCurseForge([("uploaded", 5)])
        self.assertEqual(self.publish(cf), "published")
        self.assertEqual(len(cf.uploads), 1)
        self.assertEqual(self.gh.calls.count("create"), 1)
        self.assertEqual(self.gh.calls.count("asset " + self.zip.name.lstrip("!")), 1)

    def test_ambiguous_upload_is_not_retried(self):
        with self.assertRaisesRegex(rel.ReleaseError, "outcome unknown"):
            self.publish(FakeCurseForge([("unknown", "curl 28")]))
        cf = FakeCurseForge([("uploaded", 5)])
        with self.assertRaisesRegex(rel.ReleaseError, "Nothing is retried"):
            self.publish(cf)
        self.assertEqual(cf.uploads, [])
        # the maintainer checks CurseForge, finds the file there and records it
        r = self.gh.releases_[0]
        r["body"] = r["body"].replace('"curseforge": "unknown"', '"curseforge": "uploaded"')
        self.assertEqual(self.publish(cf), "published")
        self.assertEqual(cf.uploads, [])

    def test_retry_after_checking_curseforge(self):
        with self.assertRaises(rel.ReleaseError):
            self.publish(FakeCurseForge([("unknown", "HTTP 502")]))
        r = self.gh.releases_[0]
        r["body"] = r["body"].replace('"curseforge": "unknown"', '"curseforge": "retry"')
        cf = FakeCurseForge([("uploaded", 7)])
        self.assertEqual(self.publish(cf), "published")
        self.assertEqual(len(cf.uploads), 1)

    def test_interrupted_upload_is_not_retried(self):
        self.gh.create_draft(self.meta["tag"], self.meta["commit"], self.meta["tag"],
                             rel.with_marker("notes", {"channel": "alpha", "commit": self.meta["commit"],
                                                       "curseforge": "uploading"}), True)
        cf = FakeCurseForge([("uploaded", 1)])
        with self.assertRaisesRegex(rel.ReleaseError, "uploading"):
            self.publish(cf)
        self.assertEqual(cf.uploads, [])

    def test_github_publish_failure_does_not_upload_twice(self):
        self.gh.fail_publish = True
        cf = FakeCurseForge([("uploaded", 3)])
        with self.assertRaises(rel.ReleaseError):
            self.publish(cf)
        self.gh.fail_publish = False
        self.assertEqual(self.publish(cf), "published")
        self.assertEqual(len(cf.uploads), 1)

    def test_tag_on_another_commit(self):
        self.gh.tags[self.meta["tag"]] = "b" * 40
        cf = FakeCurseForge([])
        with self.assertRaisesRegex(rel.ReleaseError, "already exists"):
            self.publish(cf)
        self.assertEqual(self.gh.calls, [])

    def test_release_not_made_by_the_workflow(self):
        self.gh.create_draft(self.meta["tag"], self.meta["commit"], "x", "hand-written", True)
        self.gh.calls.clear()
        with self.assertRaisesRegex(rel.ReleaseError, "not made by this workflow"):
            self.publish(FakeCurseForge([]))
        self.assertEqual(self.gh.calls, [])

    def test_same_commit_published_under_another_version(self):
        other = self.gh.create_draft("v1.0.1-alpha.1.gabcdef0", self.meta["commit"], "x",
                                     rel.with_marker("n", {"channel": "alpha", "commit": self.meta["commit"],
                                                           "curseforge": "uploaded"}), True)
        self.gh.update(other["id"], {"draft": False, "make_latest": "false"})
        cf = FakeCurseForge([])
        self.assertEqual(self.publish(cf), "already-published")
        self.assertEqual(cf.uploads, [])

    def test_failed_curseforge_lookup_uploads_nothing(self):
        class NoVersions(FakeCurseForge):
            def game_version_id(self, name):
                raise rel.ReleaseError("could not read CurseForge game versions")
        cf = NoVersions([])
        with self.assertRaisesRegex(rel.ReleaseError, "game versions"):
            self.publish(cf)
        self.assertEqual(self.state()["curseforge"], "not-started", "a re-run may try again")
        self.assertTrue(self.gh.releases_[0]["draft"])

    def test_game_version_from_interface(self):
        self.assertEqual(rel.game_version("16001"), "1.60.1")
        with self.assertRaises(rel.ReleaseError):
            rel.game_version("110200")


class CurseForgeClientTests(unittest.TestCase):
    """The real curl calls, against a local stand-in for CurseForge's upload API."""

    def setUp(self):
        import http.server
        import threading
        test = self
        self.requests, self.status, self.reply = [], 200, b'{"id": 4242}'

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                test.requests.append((self.path, self.headers.get("X-Api-Token"), b""))
                body = json_bytes([{"id": 1, "gameVersionTypeID": rel.CF_FOREVER_TYPE, "name": "1.60.1"},
                                   {"id": 2, "gameVersionTypeID": rel.CF_FOREVER_TYPE, "name": "1.50.0"},
                                   {"id": 3, "gameVersionTypeID": 517, "name": "11.2.0"}])
                self.answer(200, body)

            def do_POST(self):
                data = self.rfile.read(int(self.headers.get("Content-Length") or 0))
                test.requests.append((self.path, self.headers.get("X-Api-Token"), data))
                self.answer(test.status, test.reply)

            def answer(self, code, body):
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        self.server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.cf = rel.CurseForge("secret-token", "1719280", site=f"http://127.0.0.1:{self.server.server_port}")
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.zip = Path(self.tmp.name, "a.zip")
        self.zip.write_bytes(b"PK-zip-bytes")

    def test_game_versions(self):
        self.assertEqual(self.cf.game_version_id("1.60.1"), (1, "1.60.1", None))
        vid, name, warning = self.cf.game_version_id("1.70.0")
        self.assertEqual((vid, name), (2, "1.50.0"))
        self.assertIn("no game version 1.70.0", warning)
        self.assertEqual(self.requests[0][:2], ("/api/game/wow/versions", "secret-token"))

    def test_upload_outcomes(self):
        meta = {"displayName": "v1-forever", "releaseType": "alpha", "changelog": "a \"quoted\" $(x) note"}
        self.assertEqual(self.cf.upload(self.zip, meta), ("uploaded", 4242))
        path, token, data = self.requests[-1]
        self.assertEqual((path, token), ("/api/projects/1719280/upload-file", "secret-token"))
        self.assertIn(json_bytes(meta), data)
        self.assertIn(b"PK-zip-bytes", data)
        self.status, self.reply = 400, b'{"errorMessage": "bad"}'
        self.assertEqual(self.cf.upload(self.zip, meta)[0], "failed")
        self.status = 502
        self.assertEqual(self.cf.upload(self.zip, meta)[0], "unknown")
        self.status, self.reply = 200, b"not json"
        self.assertEqual(self.cf.upload(self.zip, meta)[0], "unknown")

    def test_unreachable_is_a_certain_failure(self):
        self.server.shutdown()
        self.server.server_close()
        self.assertEqual(self.cf.upload(self.zip, {})[0], "failed")


def json_bytes(value):
    import json
    return json.dumps(value).encode()


if __name__ == "__main__":
    unittest.main()
