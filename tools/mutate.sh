#!/usr/bin/env bash
# The mutation runner (docs/workshop/testing-roadmap.md, M4). It reads the checkout and works only on disposable copies in a temporary
# folder; see the header of tools/mutate.py. Run it with bash from any folder:  bash tools/mutate.sh --help
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
command -v python3 >/dev/null || { echo "mutate: python3 is required" >&2; exit 2; }
exec python3 -B -I "$here/mutate.py" "$@"
