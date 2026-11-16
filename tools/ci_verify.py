#!/usr/bin/env python3
"""Conservative offline CI selection; no source-to-test dependency inference."""
import argparse
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RELEASE_FILES = {"tools/release.py", "tools/ci_verify.py", "tests/test_release_tools.py",
                 "tests/test_release_isolation.py", ".github/workflows/release.yml",
                 ".github/release-policy.json", ".pkgmeta", "RELEASING.md", "docs/testing.md"}


def selection(paths):
    if paths and all(p in RELEASE_FILES or p.startswith("docs/") or p.endswith(".md") for p in paths):
        return ["development", "release-tools"]
    return []  # Existing complete offline discovery; never simulator/release certification.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="")
    args = parser.parse_args()
    paths = []
    if args.base and set(args.base) != {"0"}:
        result = subprocess.run(["git", "diff", "--name-only", "-z", args.base, "HEAD"],
                                cwd=ROOT, capture_output=True)
        if result.returncode == 0:
            paths = [p for p in result.stdout.decode().split("\0") if p]
    tier = selection(paths)
    print("CI selection:", tier or "complete offline fallback (scope unknown or outside release/docs)", flush=True)
    return subprocess.call([str(ROOT / "tests/run.sh"), *tier], cwd=ROOT)


if __name__ == "__main__":
    raise SystemExit(main())
