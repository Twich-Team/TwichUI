#!/usr/bin/env python3
"""TwichUI release tooling, used by .github/workflows/release.yml (see RELEASING.md).

One place decides a build's version and release notes, stamps the .toc files, checks the packaged zip and
publishes it, so every destination gets the same version and the same notes.

  release.py plan    --ref REF [--sha SHA] --out DIR [--repo-url URL] [--github-output FILE] [--repo-dir DIR]
  release.py stamp   --meta DIR/meta.json
  release.py check   --meta DIR/meta.json ZIP
  release.py publish --meta DIR/meta.json --zip ZIP --notes DIR/notes.md --repo OWNER/NAME
                     (needs GH_TOKEN and CF_API_KEY in the environment)

Channels: a push to main is an alpha, a push to beta a beta, and a stable tag (vMAJOR.MINOR.PATCH) a release.
Commit text is only ever handled as data: read from git with NUL separators, escaped for Markdown, and handed
to gh and curl in files. Nothing here runs a shell. Standard library only (Python 3.8+).
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.parse
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CORE, SETTINGS, NAVDATA = "!!!TwichUI", "TwichUI_Settings", "TwichUI_NavData"
ADDONS = (CORE, SETTINGS, NAVDATA)
LOAD_ON_DEMAND = (SETTINGS, NAVDATA)   # each needs CORE and loads only when asked for (the settings window, the first route)
TOCS = {a: f"{a}/{a}.toc" for a in ADDONS}
PROJECT = "TwichUI"
CHANNEL_BY_BRANCH = {"main": "alpha", "beta": "beta"}
STABLE_TAG = re.compile(r"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
PRE_TAG = re.compile(r"^v([0-9]+)\.([0-9]+)\.([0-9]+)-(alpha|beta)\.([0-9]+)\.g([0-9a-f]{7})$")
# TwichConfig keeps the addon version of a shared setup only when it is at most 40 characters (L.addon).
MAX_VERSION_LEN = 40
# The version the first stable release takes; prereleases made before any stable tag build toward it.
FIRST_VERSION = (1, 0, 0)
MAX_ENTRIES = 100
MAX_SUBJECT = 200
MAX_HIGHLIGHTS = 20000
# CurseForge, as BigWigsMods/packager v2.6.1 uploads it (upload_curseforge): the WoW site, and the game version
# type of WoW: Forever, whose versions are named from the interface (16001 -> 1.60.1).
CF_SITE = "https://wow.curseforge.com"
CF_FOREVER_TYPE = 88568
MARKER = re.compile(r"<!-- twichui-release (\{[^<>]*\}) -->")


class ReleaseError(Exception):
    pass


def git(*args, cwd=None):
    r = subprocess.run(["git", *args], cwd=cwd or REPO_ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    if r.returncode != 0:
        raise ReleaseError(f"git {' '.join(args)} failed: {r.stderr.strip()}")
    return r.stdout


def lines(text):
    return [s for s in text.splitlines() if s.strip()]


def version_of(m):
    return tuple(int(x) for x in m.groups()[:3])


# ---------------------------------------------------------------------------
# plan: which channel, version and notes this build gets, or why it publishes nothing
# ---------------------------------------------------------------------------

def nearest(tags, head, cwd):
    """The tag (of those given, all ancestors of head) with the fewest commits between it and head."""
    best = None
    for t in tags:
        n = int(git("rev-list", "--count", f"{t}..{head}", cwd=cwd).strip())
        if best is None or n < best[0]:
            best = (n, t)
    return best[1] if best else None


def plan(ref, sha=None, repo_url=None, cwd=None):
    cwd = cwd or REPO_ROOT
    if git("rev-parse", "--is-shallow-repository", cwd=cwd).strip() == "true":
        raise ReleaseError("the checkout is shallow: versions and notes need the full history and tags (fetch-depth: 0)")
    head = git("rev-parse", "HEAD", cwd=cwd).strip()
    if sha and sha != head:
        raise ReleaseError(f"checked out {head}, but the event is for {sha}")

    if ref.startswith("refs/heads/"):
        branch = ref[len("refs/heads/"):]
        channel = CHANNEL_BY_BRANCH.get(branch)
        if not channel:
            raise ReleaseError(f"branch {branch!r} has no release channel")
        source = branch
    elif ref.startswith("refs/tags/"):
        tag = ref[len("refs/tags/"):]
        if not STABLE_TAG.match(tag):
            raise ReleaseError(f"tag {tag!r} is not a stable version tag (vMAJOR.MINOR.PATCH)")
        if git("rev-parse", f"refs/tags/{tag}^{{commit}}", cwd=cwd).strip() != head:
            raise ReleaseError(f"tag {tag} does not point at the checked-out commit")
        channel, source = "release", tag
    else:
        raise ReleaseError(f"unsupported ref {ref!r}")

    at_head = set(lines(git("tag", "--points-at", "HEAD", cwd=cwd)))
    reachable = set(lines(git("tag", "--merged", "HEAD", cwd=cwd)))
    stable = {t: version_of(STABLE_TAG.match(t)) for t in reachable if STABLE_TAG.match(t)}
    earlier_stable = {t: v for t, v in stable.items() if t not in at_head}
    meta = {"schema": 1, "channel": channel, "ref": ref, "source": source, "commit": head,
            "publish": True, "skip_reason": None, "warnings": []}

    def skip(reason):
        meta.update(publish=False, skip_reason=reason)
        return meta, None

    previous = None
    if channel == "release":
        version = tag[1:]
        if earlier_stable:
            previous = max(earlier_stable, key=earlier_stable.get)
            if earlier_stable[previous] >= stable[tag]:
                raise ReleaseError(f"{tag} is not newer than {previous}, which this commit already contains; "
                                   "nothing was published (retired tags belong outside v*, e.g. archive/v3.0.12)")
        meta["base"] = tag
    else:
        stable_here = sorted(t for t in at_head if STABLE_TAG.match(t))
        if stable_here:
            return skip(f"this commit is the stable release {stable_here[0]}")
        pre = lambda t: (m := PRE_TAG.match(t)) and m.group(4) == channel
        mine = sorted(t for t in at_head if pre(t))
        if mine:
            return skip(f"this commit was already published as {mine[0]}")
        newer = sorted(t for t in lines(git("tag", "--contains", "HEAD", cwd=cwd)) if pre(t))
        if newer:
            return skip(f"superseded: {newer[0]} already contains this commit")
        if earlier_stable:
            base = max(earlier_stable, key=earlier_stable.get)
            major, minor, patch = earlier_stable[base]
            target = (major, minor, patch + 1)
            distance = int(git("rev-list", "--count", f"{base}..HEAD", cwd=cwd).strip())
        else:
            base, target = None, FIRST_VERSION
            distance = int(git("rev-list", "--count", "HEAD", cwd=cwd).strip())
        version = "{}.{}.{}".format(*target) + f"-{channel}.{distance}.g{head[:7]}"
        meta["base"] = base
        previous = nearest(sorted(t for t in reachable if pre(t)), "HEAD", cwd) or base

    if len(version) > MAX_VERSION_LEN:
        raise ReleaseError(f"version {version!r} is longer than {MAX_VERSION_LEN} characters")
    tag_name = f"v{version}"
    meta.update(version=version, tag=tag_name, prerelease=channel != "release",
                make_latest=channel == "release",
                previous={"tag": previous, "commit": git("rev-parse", f"{previous}^{{commit}}", cwd=cwd).strip()}
                if previous else None,
                packager_name=f"{{package-name}}-{tag_name}{{classic}}:{tag_name}{{classic}}")
    highlights = tag_message(tag, cwd) if channel == "release" else None
    return meta, notes(meta, repo_url, highlights, cwd)


def tag_message(tag, cwd):
    """The message of an annotated stable tag, without its signature: optional, hand-written highlights."""
    if git("cat-file", "-t", f"refs/tags/{tag}", cwd=cwd).strip() != "tag":
        return None
    text = git("tag", "-l", "--format=%(contents)", tag, cwd=cwd)
    text = re.split(r"^-----BEGIN (?:PGP|SSH) SIGNATURE-----", text, flags=re.M)[0].strip()
    if not text or text in (tag, tag[1:]):
        return None
    return text[:MAX_HIGHLIGHTS]


# ---------------------------------------------------------------------------
# Release notes from commits
# ---------------------------------------------------------------------------

CC = re.compile(r"^(?P<type>[A-Za-z]+)(?:\([^)]*\))?(?P<bang>!)?:\s+(?P<text>.+)$")
SECTIONS = [("feat", "Features"), ("fix", "Fixes"), ("perf", "Performance"), (None, "Changes")]
MAINTENANCE = {"build", "chore", "ci", "docs", "refactor", "style", "test", "tests"}
SKIP_MARK = re.compile(r"\[(?:skip changelog|no changelog|changelog skip)\]", re.I)
CI_MARK = re.compile(r"\s*\[(?:skip ci|ci skip)\]", re.I)
UNSAFE = re.compile(r"[\x00-\x1f\x7f​-‏‪-‮⁦-⁩]")
MD_SPECIAL = re.compile(r"([\\`*_\[\]<>|~&])")


def md_escape(text):
    """Commit text as plain Markdown text: no markup, links, HTML, @mentions or invisible direction marks."""
    text = " ".join(UNSAFE.sub(" ", text).split())
    if len(text) > MAX_SUBJECT:
        text = text[:MAX_SUBJECT - 1].rstrip() + "…"
    return MD_SPECIAL.sub(r"\\\1", text).replace("@", "@​")


def commits(rng, cwd):
    out = git("log", "-z", "--no-merges", "--format=%H%x00%s%x00%b", rng, cwd=cwd)
    fields = out.split("\0")
    for i in range(0, len(fields) - 2, 3):
        yield fields[i].strip(), fields[i + 1], fields[i + 2]


def classify(subject, body):
    """(section type or None, text, breaking), or None for a commit that stays out of the notes."""
    subject = CI_MARK.sub("", subject).strip()
    if not subject or subject.startswith(("fixup!", "squash!", "amend!")) or SKIP_MARK.search(subject + "\n" + body):
        return None
    m = CC.match(subject)
    if m and (m.group("type").lower() in MAINTENANCE or m.group("type").lower() in dict(SECTIONS)):
        kind = m.group("type").lower()
        breaking = bool(m.group("bang")) or "BREAKING CHANGE:" in body
        return kind, m.group("text"), breaking
    return None, subject, False


def notes(meta, repo_url, highlights, cwd):
    head, prev = meta["commit"], meta["previous"]
    rng = f"{prev['commit']}..{head}" if prev else head
    groups = {kind: [] for kind, _ in SECTIONS}
    seen, hidden, total = set(), 0, 0
    for sha, subject, body in commits(rng, cwd):
        c = classify(subject, body)
        if not c:
            continue
        kind, text, breaking = c
        if kind in MAINTENANCE and not breaking:
            hidden += 1
            continue
        kind = kind if kind in groups else None
        key = (kind, " ".join(text.lower().split()))
        if key in seen:
            continue
        seen.add(key)
        total += 1
        if sum(len(v) for v in groups.values()) < MAX_ENTRIES:
            groups[kind].append(f"- {'**Breaking:** ' if breaking else ''}{md_escape(text)} ({sha[:7]})")

    short = head[:7]
    commit_ref = f"[`{short}`]({repo_url}/commit/{head})" if repo_url else f"`{short}`"
    kinds = {"alpha": "Alpha build: a development build from `main`, for testing; it may hold unfinished changes.",
             "beta": "Beta build: a test build from `beta`, for checking before a release.",
             "release": "Stable release."}
    out = [f"## {PROJECT} {meta['version']}", "", f"{kinds[meta['channel']]} Commit {commit_ref}.", ""]
    if prev:
        since = f"Changes since {prev['tag']} (`{prev['commit'][:7]}`)"
        if repo_url:
            since += f": [compare]({repo_url}/compare/{prev['commit'][:12]}...{head[:12]})"
        out += [since + ".", ""]
    elif meta["channel"] == "release":
        out += ["The first release.", ""]
    else:
        out += ["No earlier release was found, so this lists the whole history.", ""]
    if highlights:
        out += ["### Highlights", "", highlights, ""]
    if meta["channel"] == "release" and not prev:
        groups = {kind: [] for kind, _ in SECTIONS}  # a first release lists no development history
        total = hidden = 0
    for kind, title in SECTIONS:
        if groups[kind]:
            out += [f"### {title}", ""] + groups[kind] + [""]
    listed = sum(len(v) for v in groups.values())
    if total > listed:
        out += [f"…and {total - listed} more.", ""]
    if not total and prev:
        out += ["No player-facing changes are listed." if hidden else "No new commits.", ""]
    if hidden:
        out += [f"_{hidden} maintenance commit{'s' if hidden != 1 else ''} (build, tests, documentation) not listed._", ""]
    return "\n".join(out).rstrip() + "\n"


# ---------------------------------------------------------------------------
# stamp: the packaged .toc files carry the build's version
# ---------------------------------------------------------------------------

VERSION_LINE = re.compile(rb"^## Version:[^\r\n]*", re.M)


def stamp(version, root=None):
    root = Path(root or REPO_ROOT)
    for rel in TOCS.values():
        path = root / rel
        data = path.read_bytes()
        found = VERSION_LINE.findall(data)
        if len(found) != 1:
            raise ReleaseError(f"{rel} has {len(found)} '## Version:' lines; expected exactly one")
        path.write_bytes(VERSION_LINE.sub(b"## Version: " + version.encode("ascii"), data))


# ---------------------------------------------------------------------------
# check: what the zip must (and must not) hold
# ---------------------------------------------------------------------------

FORBIDDEN = {".git", ".github", ".release", ".continue", ".clinerules", ".pkgmeta", ".gitignore", ".env",
             ".DS_Store", "tests", "tools", "assets", "CLAUDE.md", "RELEASING.md", "TASK_NOTES.md", "luac.out"}
TEXT = (".lua", ".toc", ".xml", ".md", ".txt")
MACHINE_PATH = re.compile(r"/home/[A-Za-z]|/Users/[A-Za-z]|[A-Za-z]:\\+Users\\+", re.I)
SECRET = re.compile(r"CF_API_KEY|WAGO_API_TOKEN|ghp_[A-Za-z0-9]{20}|github_pat_|-----BEGIN [A-Z ]*PRIVATE KEY")


def toc_field(text, field):
    m = re.search(r"^## " + re.escape(field) + r":[ \t]*([^\r\n]*?)[ \t]*\r?$", text, re.M)
    return m.group(1) if m else None


def check_archive(zip_path, version, root=None):
    """Problems with the packaged zip, as a list of messages (empty when it is fine)."""
    root = Path(root or REPO_ROOT)
    problems = []
    with zipfile.ZipFile(zip_path) as z:
        names = [n for n in z.namelist() if not n.endswith("/")]
        files = set(names)
        tops = {n.split("/", 1)[0] for n in z.namelist()}
        if tops != set(ADDONS):
            problems.append(f"top-level folders are {sorted(tops)}; expected exactly {', '.join(ADDONS)}")
        for n in names:
            parts = n.split("/")
            if n.startswith("/") or ".." in parts or "\\" in n:
                problems.append(f"unsafe path {n}")
            if parts[0] in ADDONS and len(parts) > 1 and parts[1] in ADDONS:
                problems.append(f"nested addon folder {n}")
            if "twitchui" in n.lower():
                problems.append(f"misspelled name {n}")
            bad = [p for p in parts if p in FORBIDDEN or "Zone.Identifier" in p or p.endswith((".code-workspace", ".zip"))]
            if bad:
                problems.append(f"development file in package: {n}")
            if n.endswith(TEXT):
                text = z.read(n).decode("utf-8", "replace")
                if MACHINE_PATH.search(text):
                    problems.append(f"machine-specific path in {n}")
                if SECRET.search(text):
                    problems.append(f"secret-like text in {n}")
        tocs = {}
        for addon, rel in TOCS.items():
            if rel not in files:
                problems.append(f"missing {rel}")
                continue
            tocs[addon] = text = z.read(rel).decode("utf-8", "replace")
            if toc_field(text, "Version") != version:
                problems.append(f"{rel} has Version {toc_field(text, 'Version')!r}; expected {version!r}")
            committed = (root / rel).read_text(encoding="utf-8", errors="replace")
            if toc_field(text, "Interface") != toc_field(committed, "Interface"):
                problems.append(f"{rel} Interface changed in packaging")
            for line in text.splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    listed = f"{addon}/" + line.replace("\\", "/")
                    if listed not in files:
                        problems.append(f"{rel} loads {line}, which is not in the package")
        if len(tocs) == len(TOCS):
            core = tocs[CORE]
            for addon in LOAD_ON_DEMAND:
                other = tocs[addon]
                if toc_field(other, "Interface") != toc_field(core, "Interface"):
                    problems.append(f"{addon}.toc has a different Interface value from {CORE}.toc")
                if toc_field(other, "LoadOnDemand") != "1":
                    problems.append(f"{addon} is not load on demand")
                if toc_field(other, "RequiredDeps") != CORE:
                    problems.append(f"{addon} does not require {CORE}")
            if not (toc_field(core, "X-Curse-Project-ID") or "").isdigit():
                problems.append(f"{CORE}.toc has no X-Curse-Project-ID")
    return problems


# ---------------------------------------------------------------------------
# publish: draft GitHub release -> CurseForge (once) -> publish the GitHub release
# ---------------------------------------------------------------------------

RECONCILE = (
    "CurseForge may or may not have received {label} (state: {state}). Nothing is retried automatically.\n"
    "Check the project's Files page on CurseForge, then edit the draft GitHub release {tag} and change\n"
    "\"curseforge\": \"{state}\" in its last line to \"uploaded\" (the file is there) or \"retry\" (it is not),\n"
    "and re-run the failed job.")


def marker(body):
    m = MARKER.search(body or "")
    return json.loads(m.group(1)) if m else None


def with_marker(body, state):
    text = json.dumps(state, sort_keys=True)
    if "--" in text:
        raise ReleaseError("release marker would not be a valid HTML comment")
    body = MARKER.sub("", body or "").rstrip()
    return f"{body}\n\n<!-- twichui-release {text} -->\n"


class GitHub:
    """The few GitHub calls publishing needs, through `gh api` (the token stays in GH_TOKEN)."""

    def __init__(self, repo):
        self.repo = repo

    def _gh(self, args, body=None, raw=None):
        with tempfile.TemporaryDirectory() as d:
            cmd = ["gh", "api", "-H", "Accept: application/vnd.github+json", *args]
            if body is not None:
                p = Path(d, "body.json")
                p.write_text(json.dumps(body), encoding="utf-8")
                cmd += ["--input", str(p)]
            if raw is not None:
                cmd += ["-H", "Content-Type: application/octet-stream", "--input", str(raw)]
            r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            if "HTTP 404" in r.stderr:
                return None
            raise ReleaseError(f"GitHub API {' '.join(args[:3])} failed: {r.stderr.strip()[:500]}")
        return json.loads(r.stdout) if r.stdout.strip() else {}

    def releases(self):
        out, page = [], 1
        while True:
            batch = self._gh([f"repos/{self.repo}/releases?per_page=100&page={page}"]) or []
            out += batch
            if len(batch) < 100:
                return out
            page += 1

    def tag_commit(self, tag):
        ref = self._gh([f"repos/{self.repo}/git/ref/tags/{urllib.parse.quote(tag, safe='')}"])
        if not ref:
            return None
        obj = ref["object"]
        while obj["type"] == "tag":
            obj = self._gh([f"repos/{self.repo}/git/tags/{obj['sha']}"])["object"]
        return obj["sha"]

    def create_draft(self, tag, sha, name, body, prerelease):
        return self._gh(["-X", "POST", f"repos/{self.repo}/releases"],
                        {"tag_name": tag, "target_commitish": sha, "name": name, "body": body,
                         "draft": True, "prerelease": prerelease})

    def update(self, release_id, fields):
        return self._gh(["-X", "PATCH", f"repos/{self.repo}/releases/{release_id}"], fields)

    def delete_asset(self, asset_id):
        self._gh(["-X", "DELETE", f"repos/{self.repo}/releases/assets/{asset_id}"])

    def upload_asset(self, release_id, path, name):
        url = (f"https://uploads.github.com/repos/{self.repo}/releases/{release_id}/assets"
               f"?name={urllib.parse.quote(name, safe='')}")
        return self._gh(["-X", "POST", url], raw=path)


class CurseForge:
    """CurseForge's upload API, with curl. The token is passed in a header file, never on the command line."""

    def __init__(self, token, project_id, site=CF_SITE):
        self.token, self.project_id, self.site = token, project_id, site

    def _curl(self, args, d):
        header = Path(d, "auth")
        header.write_text(f"X-Api-Token: {self.token}\n")
        header.chmod(0o600)
        out = Path(d, "out")
        r = subprocess.run(["curl", "-sS", "-o", str(out), "-w", "%{http_code}", "-H", f"@{header}", *args],
                           capture_output=True, text=True)
        body = out.read_text(errors="replace") if out.exists() else ""
        return r.returncode, r.stdout.strip(), body, r.stderr.strip()

    def game_version_id(self, name):
        with tempfile.TemporaryDirectory() as d:
            code, http, body, err = self._curl(["--retry", "3", "--max-time", "60",
                                                f"{self.site}/api/game/wow/versions"], d)
        if code != 0 or http != "200":
            raise ReleaseError(f"could not read CurseForge game versions (curl {code}, HTTP {http}): {err[:200]}")
        versions = [v for v in json.loads(body) if v.get("gameVersionTypeID") == CF_FOREVER_TYPE]
        exact = [v for v in versions if v.get("name") == name]
        if exact:
            return exact[0]["id"], name, None
        # As the packager does: the newest version below the wanted one, else the newest at all.
        key = lambda v: tuple(int(x) for x in re.findall(r"\d+", v.get("name", "")))
        want = tuple(int(x) for x in name.split("."))
        lower = [v for v in versions if key(v) < want]
        pick = max(lower or versions, key=lambda v: v["id"], default=None)
        if not pick:
            raise ReleaseError("CurseForge lists no WoW: Forever game versions")
        return pick["id"], pick["name"], f"CurseForge has no game version {name}; using {pick['name']}"

    def upload(self, zip_path, metadata):
        """('uploaded', file id) | ('failed', why): certainly not received | ('unknown', why): may have been."""
        with tempfile.TemporaryDirectory() as d:
            meta = Path(d, "metadata.json")
            meta.write_text(json.dumps(metadata), encoding="utf-8")
            code, http, body, err = self._curl(
                ["--max-time", "600", "-F", f"metadata=<{meta}", "-F", f"file=@{zip_path}",
                 f"{self.site}/api/projects/{self.project_id}/upload-file"], d)
        if code == 0 and http == "200":
            try:
                return "uploaded", int(json.loads(body)["id"])
            except (ValueError, KeyError, TypeError):
                return "unknown", f"HTTP 200 without a file id: {body[:200]}"
        if code in (6, 7):  # could not resolve or connect: nothing was sent
            return "failed", f"curl {code}: {err[:200]}"
        if code == 0 and http.startswith("4") and http not in ("408",):
            return "failed", f"HTTP {http}: {body[:300]}"
        return "unknown", f"curl {code}, HTTP {http or '-'}: {(err or body)[:300]}"


def game_version(interface):
    i = str(interface)
    if not re.fullmatch(r"16[0-9]{3}", i):
        raise ReleaseError(f"Interface {i} is not a WoW: Forever interface (16xxx)")
    return f"{int(i[:-4])}.{int(i[-4:-2])}.{int(i[-2:])}"


def publish(meta, zip_path, notes_text, gh, cf, log=print, sleep=time.sleep):
    """Publish one build. Safe to re-run: every step looks at what is already there first."""
    tag, sha, channel = meta["tag"], meta["commit"], meta["channel"]

    def save(fields):
        # Every edit repeats the tag and commit: a draft edited without them is published by GitHub under its
        # placeholder tag ("untagged-..."), not ours (seen 2026-10-15 with v1.0.0-alpha.116.g0926105).
        return gh.update(rel["id"], {"tag_name": tag, "target_commitish": sha, **fields})

    def tag_on_github():
        for wait in (0, 2, 4, 8):  # GitHub may make the tag a moment after the release is published
            sleep(wait)
            remote = gh.tag_commit(tag)
            if remote:
                return remote
        return None
    zip_path = Path(zip_path)
    label = zip_path.name[len(CORE) + 1:-len(".zip")] if zip_path.name.startswith(CORE + "-") else tag

    remote = gh.tag_commit(tag)
    if remote and remote != sha:
        raise ReleaseError(f"tag {tag} already exists on {remote}, not {sha}; nothing was published")
    all_releases = gh.releases()
    ours = lambda r: (m := marker(r.get("body"))) and (m.get("channel"), m.get("commit"), m.get("version")) == \
        (channel, sha, meta["version"])
    # By tag, or by what our marker records (GitHub may have given the release its placeholder tag)
    rel = next((r for r in all_releases if r.get("tag_name") == tag), None) or \
        next((r for r in all_releases if ours(r)), None)
    if not rel and channel != "release":
        for r in all_releases:
            m = marker(r.get("body"))
            if m and m.get("channel") == channel and m.get("commit") == sha:
                if not r.get("draft"):
                    log(f"This commit is already published as {r['tag_name']}; nothing to do.")
                    return "already-published"
                raise ReleaseError(f"an unfinished draft {r['tag_name']} exists for this commit; finish or delete it")

    if rel:
        state = marker(rel.get("body"))
        if not state:
            raise ReleaseError(f"release {tag} exists but was not made by this workflow; reconcile it by hand")
        if state.get("commit") != sha:
            raise ReleaseError(f"release {tag} records commit {state.get('commit')}, not {sha}")
        if not rel.get("draft"):
            if rel.get("tag_name") == tag and tag_on_github() == sha:
                log(f"{tag} is already published ({rel.get('html_url')}); nothing to do.")
                return "already-published"
            stray = rel.get("tag_name")
            rel = save({})
            if tag_on_github() != sha:
                raise ReleaseError(f"release {tag} is published but its tag could not be set to {sha}: fix it by hand")
            log(f"{tag} was published under the tag {stray}; it now has its own tag."
                + (f" Delete the leftover tag {stray} by hand." if stray != tag else ""))
            return "repaired"
    else:
        state = {"channel": channel, "commit": sha, "version": meta["version"], "curseforge": "not-started"}
        rel = gh.create_draft(tag, sha, tag, with_marker(notes_text, state), meta["prerelease"])
        log(f"Created draft release {tag}.")

    # Assets on the draft: the zip, and release.json for addon managers that install from GitHub releases.
    # An asset already uploaded by an earlier attempt is kept, so GitHub and CurseForge hold the same zip.
    # GitHub drops the leading "!!!" from asset names, so the zip goes up as TwichUI-...zip, the name
    # release.json gives (the zip's folders inside keep their names).
    asset_name = zip_path.name.lstrip("!")
    with tempfile.TemporaryDirectory() as d:
        with zipfile.ZipFile(zip_path) as z:
            interface = toc_field(z.read(TOCS[CORE]).decode("utf-8", "replace"), "Interface")
        rj = Path(d, "release.json")
        rj.write_text(json.dumps({"releases": [{"name": PROJECT, "version": tag, "filename": asset_name,
                                                 "nolib": False, "metadata": [{"flavor": "forever",
                                                                               "interface": int(interface)}]}]}))
        existing = {a["name"]: a for a in rel.get("assets", [])}
        for path, name in ((zip_path, asset_name), (rj, "release.json")):
            a = existing.get(name)
            if a and a.get("state") == "uploaded":
                continue
            if a:
                gh.delete_asset(a["id"])
            uploaded = gh.upload_asset(rel["id"], path, name) or {}
            if uploaded.get("name", name) != name:
                raise ReleaseError(f"GitHub stored {name} as {uploaded.get('name')}; release.json would not match it")
            log(f"Attached {name}.")

    cf_state = state.get("curseforge")
    if cf_state in ("uploading", "unknown"):
        raise ReleaseError(RECONCILE.format(label=label, state=cf_state, tag=tag))
    if cf_state not in ("uploaded", "not-started", "failed", "retry"):
        raise ReleaseError(f"unknown CurseForge state {cf_state!r} in release {tag}")
    if cf_state != "uploaded":
        version_id, version_name, warning = cf.game_version_id(game_version(interface))
        if warning:
            log(f"::warning::{warning}")
        state["curseforge"] = "uploading"
        rel = save({"body": with_marker(rel.get("body"), state)})
        result, detail = cf.upload(zip_path, {
            "displayName": label, "gameVersions": [version_id], "releaseType": channel,
            "changelog": notes_text, "changelogType": "markdown"})
        state["curseforge"] = result
        if result == "uploaded":
            state["curseforge_file"] = detail
        rel = save({"body": with_marker(rel.get("body"), state)})
        if result == "failed":
            raise ReleaseError(f"CurseForge refused the upload ({detail}). The GitHub release is still a draft; "
                               "re-running the job tries CurseForge again.")
        if result == "unknown":
            raise ReleaseError(f"CurseForge upload outcome unknown ({detail}).\n"
                               + RECONCILE.format(label=label, state="unknown", tag=tag))
        log(f"Uploaded {label} to CurseForge ({channel}, file {detail}, game version {version_name}).")

    remote = gh.tag_commit(tag)
    if remote and remote != sha:
        raise ReleaseError(f"tag {tag} appeared on {remote}, not {sha}; the GitHub release is left as a draft")
    rel = save({"draft": False, "prerelease": meta["prerelease"],
                "make_latest": "true" if meta["make_latest"] else "false"})
    if rel.get("tag_name") != tag:
        raise ReleaseError(f"GitHub published {tag} under the tag {rel.get('tag_name')}; re-run the job to repair it")
    remote = tag_on_github()
    if remote != sha:
        raise ReleaseError(f"published {tag}, but the tag points at {remote}, not {sha}: fix the tag by hand")
    log(f"Published GitHub {'prerelease' if meta['prerelease'] else 'release'} {tag}.")
    return "published"


# ---------------------------------------------------------------------------

def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("plan")
    a.add_argument("--ref", required=True)
    a.add_argument("--sha")
    a.add_argument("--out", required=True)
    a.add_argument("--repo-url")
    a.add_argument("--github-output")
    a.add_argument("--repo-dir", help="the repository to read (default: the one this script is in)")
    a = sub.add_parser("stamp")
    a.add_argument("--meta", required=True)
    a = sub.add_parser("check")
    a.add_argument("--meta", required=True)
    a.add_argument("zip")
    a = sub.add_parser("publish")
    a.add_argument("--meta", required=True)
    a.add_argument("--zip", required=True)
    a.add_argument("--notes", required=True)
    a.add_argument("--repo", required=True)
    args = p.parse_args(argv)

    try:
        if args.cmd == "plan":
            meta, text = plan(args.ref, args.sha, args.repo_url, args.repo_dir)
            out = Path(args.out)
            out.mkdir(parents=True, exist_ok=True)
            (out / "meta.json").write_text(json.dumps(meta, indent=2) + "\n")
            if text is not None:
                (out / "notes.md").write_text(text, encoding="utf-8")
            for w in meta["warnings"]:
                print(f"::warning::{w}")
            print(json.dumps(meta, indent=2))
            if args.github_output:
                with open(args.github_output, "a") as f:
                    for k in ("publish", "channel", "version", "tag", "packager_name"):
                        v = meta.get(k)
                        f.write(f"{k}={str(v).lower() if isinstance(v, bool) else (v or '')}\n")
            return 0
        meta = json.loads(Path(args.meta).read_text())
        if args.cmd == "stamp":
            stamp(meta["version"])
            print(f"Stamped Version {meta['version']} into {', '.join(TOCS.values())}")
        elif args.cmd == "check":
            problems = check_archive(args.zip, meta["version"])
            for msg in problems:
                print(f"::error::{msg}")
            if problems:
                return 1
            print(f"{Path(args.zip).name}: {', '.join(ADDONS)}, all at Version {meta['version']}: OK")
        elif args.cmd == "publish":
            token = os.environ.get("CF_API_KEY")
            if not token:
                raise ReleaseError("CF_API_KEY is not set")
            with zipfile.ZipFile(args.zip) as z:
                project = toc_field(z.read(TOCS[CORE]).decode("utf-8", "replace"), "X-Curse-Project-ID")
            publish(meta, args.zip, Path(args.notes).read_text(encoding="utf-8"),
                    GitHub(args.repo), CurseForge(token, project))
        return 0
    except ReleaseError as e:
        for i, line in enumerate(str(e).splitlines()):
            print(f"::error::{line}" if i == 0 else line, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
