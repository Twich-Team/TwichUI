"""Offline regression coverage for the manual one-click release entrypoint.

No network, tags or releases are created in the actual TwichUI repository.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import one_click_release as one  # noqa: E402
import release as rel  # noqa: E402


class TemporaryGit(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.invalid")
        (self.root / "version.txt").write_text("start\n")
        self.git("add", ".")
        self.git("commit", "-qm", "start")
        self.git("tag", "-a", "v1.3.0", "-m", "1.3.0")
        (self.root / "version.txt").write_text("next\n")
        self.git("commit", "-qam", "next")
        self.head = self.git("rev-parse", "HEAD")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root,
                              check=True, text=True, capture_output=True).stdout.strip()

    def test_stable_uses_plain_semver(self):
        self.assertEqual(one.planned_version("2.0.0", "stable", self.head, self.root), "2.0.0")

    def test_alpha_and_beta_are_source_bound(self):
        for channel in ("alpha", "beta"):
            value = one.planned_version("2.0.0", channel, self.head, self.root)
            self.assertEqual(value, f"2.0.0-{channel}.1.g{self.head[:7]}")
            self.assertLessEqual(len(value), 40)

    def test_rejects_old_versions_and_invalid_inputs(self):
        for value in ("1.3.0", "1.2.9", "v2.0.0", "02.0.0", "2.0.0;true", "2.0"):
            with self.subTest(value=value), self.assertRaises(rel.ReleaseError):
                one.planned_version(value, "beta", self.head, self.root)
        with self.assertRaises(rel.ReleaseError):
            one.planned_version("2.0.0", "nightly", self.head, self.root)
        with self.assertRaises(rel.ReleaseError):
            one.planned_version("2.0.0", "stable", "0" * 40, self.root)

    def test_old_2_0_0_tag_blocks_reusing_that_version_on_new_source(self):
        self.git("tag", "v2.0.0")
        (self.root / "version.txt").write_text("later\n")
        self.git("commit", "-qam", "later")
        new = self.git("rev-parse", "HEAD")
        with self.assertRaisesRegex(rel.ReleaseError, "prematurely created tag"):
            one.planned_version("2.0.0", "stable", new, self.root)
        self.assertEqual(one.planned_version("2.0.1", "stable", new, self.root), "2.0.1")

    def test_same_source_tag_may_pass_version_planning_but_not_lightweight_tag_check(self):
        self.git("tag", "v2.0.0")
        self.assertEqual(one.planned_version("2.0.0", "stable", self.head, self.root), "2.0.0")


class FakeGitHub:
    def __init__(self, source, existing=None):
        self.repo = "Twich-Team/TwichUI"
        self.source = source
        self.existing = existing
        self.requests = []

    def _gh(self, args, body=None):
        self.requests.append((args, body))
        path = args[-1]
        if path.endswith("/git/ref/tags/v2.0.0"):
            return self.existing
        if path.endswith("/git/tags") and body:
            return {"sha": "a" * 40}
        if path.endswith("/git/refs") and body:
            self.existing = {"object": {"type": "tag", "sha": body["sha"]}}
            return {"ref": body["ref"]}
        return {}

    def tag_commit(self, tag):
        return self.source if self.existing else None


class TagTests(unittest.TestCase):
    SOURCE = "b" * 40
    META = {"commit": SOURCE, "tag": "v2.0.0", "version": "2.0.0", "release_kind": "stable"}

    def setUp(self):
        patch = mock.patch.object(one, "check_context", return_value=self.SOURCE)
        patch.start()
        self.addCleanup(patch.stop)

    def test_new_tag_is_annotated_and_created_only_once(self):
        gh = FakeGitHub(self.SOURCE)
        self.assertEqual(one.ensure_tag(self.META, gh), "created")
        self.assertEqual(gh.existing["object"]["type"], "tag")
        self.assertEqual(one.ensure_tag(self.META, gh), "existing")
        self.assertEqual(sum(p[-1].endswith("/git/tags") for p, b in gh.requests), 1)

    def test_lightweight_tag_is_not_moved_or_deleted(self):
        gh = FakeGitHub(self.SOURCE, {"object": {"type": "commit", "sha": self.SOURCE}})
        with self.assertRaisesRegex(rel.ReleaseError, "lightweight tag"):
            one.ensure_tag(self.META, gh)
        self.assertFalse(any("-X" in path for path, body in gh.requests))

    def test_wrong_commit_refuses_without_mutation(self):
        gh = FakeGitHub("c" * 40, {"object": {"type": "tag", "sha": "a" * 40}})
        with self.assertRaisesRegex(rel.ReleaseError, "another commit"):
            one.ensure_tag(self.META, gh)
        self.assertFalse(any("-X" in path for path, body in gh.requests))


class EntryPointTests(unittest.TestCase):
    def test_no_automatic_release_trigger(self):
        workflow = (Path(__file__).resolve().parent.parent /
                    ".github/workflows/one-click-release.yml").read_text()
        self.assertIn("workflow_dispatch:", workflow)
        self.assertNotIn("\n  push:", workflow)
        self.assertNotIn("\n  pull_request:", workflow)
        self.assertIn("github.ref == 'refs/heads/main'", workflow)
        self.assertIn("environment: release", workflow)
        self.assertIn("tools/release.py seal", workflow)
        self.assertIn("tools/release.py publish", workflow)
        self.assertIn("release: ", workflow)
        self.assertIn("cancel-in-progress: false", workflow)

    def test_context_refuses_pushes_or_other_sha(self):
        with mock.patch.dict(os.environ, {
            "GITHUB_EVENT_NAME": "push", "GITHUB_REF": "refs/heads/main",
            "GITHUB_SHA": "b" * 40,
        }), self.assertRaisesRegex(rel.ReleaseError, "manual dispatch"):
            one.check_context(TagTests.META)
        with mock.patch.dict(os.environ, {
            "GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REF": "refs/heads/main",
            "GITHUB_SHA": "c" * 40,
        }), self.assertRaisesRegex(rel.ReleaseError, "source does not match"):
            one.check_context(TagTests.META)


if __name__ == "__main__":
    unittest.main()
