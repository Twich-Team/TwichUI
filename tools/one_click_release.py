#!/usr/bin/env python3
"""Small helpers for the manually dispatched, one-click TwichUI release workflow.

Never publishes by itself. The existing release.py remains responsible for stamping,
sealing and idempotent GitHub/CurseForge publishing.
"""
import argparse
import json
import os
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import release as rel

BASE_VERSION = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")


def planned_version(base, channel, source, cwd):
    """Accept a simple base version; derive a source-bound prerelease suffix."""
    match = BASE_VERSION.fullmatch(base)
    if not match or channel not in ("alpha", "beta", "stable"):
        raise rel.ReleaseError("enter an exact X.Y.Z version and alpha, beta or stable")
    if not re.fullmatch(r"[0-9a-f]{40}", source):
        raise rel.ReleaseError("full source SHA required")
    if rel.git("rev-parse", "HEAD", cwd=cwd).strip() != source:
        raise rel.ReleaseError("release source must be the currently checked-out commit")
    if rel.git("rev-parse", "--is-shallow-repository", cwd=cwd).strip() == "true":
        raise rel.ReleaseError("fetch complete history and tags before releasing")
    version = tuple(int(x) for x in match.groups())
    earlier = [t for t in rel.lines(rel.git("tag", "--merged", source, cwd=cwd))
               if rel.STABLE_TAG.fullmatch(t)]
    previous = max(earlier, key=lambda t: rel.version_of(rel.STABLE_TAG.fullmatch(t)), default=None)
    if previous:
        old = rel.version_of(rel.STABLE_TAG.fullmatch(previous))
        # A rerun of an already tagged stable is allowed only at that exact source;
        # rel.publish still checks the release marker and package identity.
        same_tag = previous == "v" + base and rel.git("rev-parse", previous + "^{commit}", cwd=cwd).strip() == source
        if version < old or (version == old and not (channel == "stable" and same_tag)):
            raise rel.ReleaseError(
                f"{base} does not advance existing tag {previous}; choose a newer version "
                "or have the owner resolve the prematurely created tag")
    if channel == "stable":
        return base
    distance = int(rel.git("rev-list", "--count",
                           f"{previous}..{source}" if previous else source, cwd=cwd))
    if distance < 1:
        raise rel.ReleaseError("prerelease must contain changes after the latest stable tag")
    actual = f"{base}-{channel}.{distance}.g{source[:7]}"
    if len(actual) > rel.MAX_VERSION_LEN:
        raise rel.ReleaseError("the prerelease version is too long")
    return actual


def check_context(meta):
    """Fail closed outside an explicit dispatch on protected main at this exact SHA."""
    if os.getenv("GITHUB_EVENT_NAME") != "workflow_dispatch" or os.getenv("GITHUB_REF") != "refs/heads/main":
        raise rel.ReleaseError("publication requires a manual dispatch from main")
    source = os.getenv("GITHUB_SHA")
    if not source or meta.get("commit") != source or rel.git("rev-parse", "HEAD").strip() != source:
        raise rel.ReleaseError("candidate source does not match the workflow checkout")
    if meta.get("release_kind") not in ("alpha", "beta", "stable"):
        raise rel.ReleaseError("unsupported one-click release channel")
    if meta.get("tag") != "v" + meta.get("version", ""):
        raise rel.ReleaseError("candidate tag/version mismatch")
    return source


def ensure_tag(meta, gh):
    """Create a protected, annotated tag only once; never move or delete a tag."""
    source = check_context(meta)
    tag = meta["tag"]
    existing = gh._gh([f"repos/{gh.repo}/git/ref/tags/{tag}"])
    if existing:
        if gh.tag_commit(tag) != source:
            raise rel.ReleaseError(f"{tag} exists on another commit; protected tags are never moved")
        if existing.get("object", {}).get("type") != "tag":
            raise rel.ReleaseError(
                f"{tag} exists as a lightweight tag; an owner must resolve it under "
                "the tag protection rules before releasing")
        return "existing"
    created = gh._gh(["-X", "POST", f"repos/{gh.repo}/git/tags"], {
        "tag": tag, "message": f"TwichUI {meta['version']}\nSource: {source}",
        "object": source, "type": "commit",
    }) or {}
    if not re.fullmatch(r"[a-f0-9]{40}", created.get("sha", "")):
        raise rel.ReleaseError("GitHub did not return a new annotated tag object")
    gh._gh(["-X", "POST", f"repos/{gh.repo}/git/refs"], {
        "ref": "refs/tags/" + tag, "sha": created["sha"],
    })
    if gh.tag_commit(tag) != source:
        raise rel.ReleaseError("new tag does not point to the certified source")
    return "created"


def pre_publish(meta, gh):
    """Validate release identity and published history before creating any public tag."""
    check_context(meta)
    if not rel.publication_enabled():
        raise rel.ReleaseError("publication is disabled in .github/release-policy.json")
    remote = gh._gh([f"repos/{gh.repo}/branches/main"]) or {}
    if not remote.get("protected") or remote.get("commit", {}).get("sha") != meta["commit"]:
        raise rel.ReleaseError("main must remain protected and at the certified source")
    actor = os.getenv("GITHUB_TRIGGERING_ACTOR", "")
    permission = gh._gh([f"repos/{gh.repo}/collaborators/{actor}/permission"]) or {}
    if permission.get("permission") not in ("admin", "maintain", "write"):
        raise rel.ReleaseError("only a repository maintainer may publish")
    published = [r for r in gh.releases() if not r.get("draft")]
    stable = [rel.version_of(m) for r in published
              if not r.get("prerelease") and (m := rel.STABLE_TAG.fullmatch(r.get("tag_name", "")))]
    requested = rel.version_of(rel.STABLE_TAG.fullmatch("v" + meta["version"].split("-")[0]))
    if stable and requested <= max(stable):
        same = next((r for r in published if r.get("tag_name") == meta["tag"]), None)
        if meta["release_kind"] != "stable" or requested != max(stable) or not same:
            raise rel.ReleaseError("a newer or equal stable release is already published")
    return True


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("version", help="print the stamped version")
    a.add_argument("--base", required=True)
    a.add_argument("--channel", choices=("alpha", "beta", "stable"), required=True)
    a.add_argument("--source", required=True)
    a = sub.add_parser("tag", help="preflight and create/reuse an annotated tag")
    a.add_argument("--meta", required=True)
    a.add_argument("--repo", required=True)
    a.add_argument("--zip", required=True)
    a.add_argument("--notes", required=True)
    args = p.parse_args()
    try:
        if args.cmd == "version":
            print(planned_version(args.base, args.channel, args.source, rel.REPO_ROOT))
            return 0
        meta = json.loads(Path(args.meta).read_text())
        rel.verify_candidate(meta, args.zip, Path(args.notes).read_text(encoding="utf-8"))
        gh = rel.GitHub(args.repo)
        pre_publish(meta, gh)
        print(f"Protected {ensure_tag(meta, gh)} annotated tag {meta['tag']}")
        return 0
    except (rel.ReleaseError, ValueError, KeyError, OSError) as exc:
        print(f"::error::{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
