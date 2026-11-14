#!/usr/bin/env bash
# No arguments: every offline test (CI-compatible). Tiers: docs/testing.md.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v python3 >/dev/null || { echo 'tests: python3 is required' >&2; exit 2; }
exec python3 -B "$repo/tools/test_runner.py" "$@"
