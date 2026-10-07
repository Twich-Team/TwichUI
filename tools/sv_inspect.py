#!/usr/bin/env python3
"""TwichUI SavedVariables inspector: what addons keep on disk, outside the game.

An addon in the game can only see data of addons loaded right now, and can't
read files. This tool reads WoW's SavedVariables files directly, so it can show
what the game can't:

  scan        every account and character's saved files, which addon each
              belongs to (exact: one file per addon folder), sizes on disk, and
              which files belong to addons not installed in this game folder,
              with the evidence and what's uncertain. Read-only.
  show NAME   one addon's files and the variables in each, with sizes and
              entry counts. Values are never printed. Read-only.
  quarantine  moves the files of addons that aren't installed to a quarantine
              folder. A dry run unless --apply; with --apply only while WoW is
              closed, after listing every file and a typed confirmation.
  restore ID  puts a quarantined batch back (same rules).
  quarantined lists quarantined batches.

Safety:
  * Saved files are read as data with a strict reader and never run.
  * Nothing is ever chosen for you. Installed addons (on or off) and Blizzard's
    own files are never moved; only addons you name, and only if their folder
    isn't in Interface/AddOns.
  * Files are copied, checked (SHA-256), and only then removed; the manifest
    keeps where each came from. Restore refuses to overwrite a file.
  * Everything stays on this computer. --redact hides account, realm and
    character names in the output (for sharing a report).

Examples (Windows: py tools\\sv_inspect.py ...; WSL: python3 tools/sv_inspect.py ...):
  sv_inspect.py scan
  sv_inspect.py --flavor _classic_beta_ show ProfessionMaster
  sv_inspect.py quarantine --addon ProfessionMaster            (dry run)
  sv_inspect.py quarantine --addon ProfessionMaster --apply
  sv_inspect.py quarantined
  sv_inspect.py restore 20261007-142233 --apply
"""

import argparse
import csv
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

DEFAULT_ROOTS = [
    r"C:\Program Files (x86)\World of Warcraft",
    r"C:\Program Files\World of Warcraft",
    "/mnt/c/Program Files (x86)/World of Warcraft",
    "/mnt/c/Program Files/World of Warcraft",
]
DEFAULT_QUARANTINE = Path.home() / "TwichUI SavedVariables quarantine"
MAX_DEPTH = 500


# ---------------------------------------------------------------------------
# Reading a SavedVariables file as data
# ---------------------------------------------------------------------------
class ParseError(Exception):
    pass


_IDENT = re.compile(rb"[A-Za-z_][A-Za-z0-9_]*")
_NUMBER = re.compile(
    rb"-?(?:\d+\.#(?:INF|IND|QNAN|SNAN)\d*"          # 1.#INF and friends
    rb"|0[xX][0-9a-fA-F]+"
    rb"|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)")
_LONG_OPEN = re.compile(rb"\[(=*)\[")
_WORDS = {b"true", b"false", b"nil", b"inf", b"nan"}


class Reader:
    """Reads the client's format: Name = value lines, where values are nil,
    booleans, numbers, strings and tables of those. Anything else (a function
    call, an operator) is an error; nothing is evaluated."""

    def __init__(self, data):
        self.d = data
        self.i = 0

    def fail(self, msg):
        line = self.d.count(b"\n", 0, self.i) + 1
        raise ParseError(f"{msg} (line {line})")

    def ws(self):
        d, n = self.d, len(self.d)
        while self.i < n:
            c = d[self.i]
            if c in b" \t\r\n\f\v":
                self.i += 1
            elif d.startswith(b"--", self.i):
                m = _LONG_OPEN.match(d, self.i + 2)
                if m:
                    end = d.find(b"]" + m.group(1) + b"]", m.end())
                    if end < 0:
                        self.fail("unfinished comment")
                    self.i = end + len(m.group(1)) + 2
                else:
                    nl = d.find(b"\n", self.i)
                    self.i = n if nl < 0 else nl + 1
            else:
                break

    def string(self):
        d, n = self.d, len(self.d)
        q = d[self.i]
        self.i += 1
        while self.i < n:
            c = d[self.i]
            if c == q:
                self.i += 1
                return
            if c == 0x5C:                    # backslash: skip the escaped character
                self.i += 2
            elif c == 0x0A:
                self.fail("line break inside a string")
            else:
                self.i += 1
        self.fail("unfinished string")

    def long_string(self, m):
        end = self.d.find(b"]" + m.group(1) + b"]", m.end())
        if end < 0:
            self.fail("unfinished long string")
        self.i = end + len(m.group(1)) + 2

    def value(self, depth):
        """Skips one value; returns how many table entries it holds."""
        d = self.d
        if self.i >= len(d):
            self.fail("value expected")
        c = d[self.i:self.i + 1]
        if c == b"{":
            return self.table(depth + 1)
        if c in (b'"', b"'"):
            self.string()
            return 0
        m = _LONG_OPEN.match(d, self.i)
        if m:
            self.long_string(m)
            return 0
        m = _NUMBER.match(d, self.i)
        if m:
            self.i = m.end()
            return 0
        neg = c == b"-"
        m = _IDENT.match(d, self.i + (1 if neg else 0))
        if m and m.group() in _WORDS and (not neg or m.group() in (b"inf", b"nan")):
            self.i = m.end()
            if d.startswith(b"(ind)", self.i):    # -nan(ind)
                self.i += 5
            return 0
        if m:
            self.fail(f"unexpected name '{m.group().decode(errors='replace')}'")
        self.fail(f"unexpected '{c.decode(errors='replace')}'")

    def table(self, depth):
        if depth > MAX_DEPTH:
            self.fail("tables nested too deeply")
        d = self.d
        self.i += 1
        entries = 0
        while True:
            self.ws()
            if self.i >= len(d):
                self.fail("unfinished table")
            c = d[self.i:self.i + 1]
            if c == b"}":
                self.i += 1
                return entries
            if c == b"[" and not _LONG_OPEN.match(d, self.i):
                self.i += 1
                self.ws()
                start = self.i
                if self.value(depth) or d[start:start + 1] == b"{":
                    self.fail("a table can't be a key here")
                self.ws()
                if d[self.i:self.i + 1] != b"]":
                    self.fail("']' expected")
                self.i += 1
                self.ws()
                if d[self.i:self.i + 1] != b"=":
                    self.fail("'=' expected")
                self.i += 1
                self.ws()
                entries += 1 + self.value(depth)
            else:
                m = _IDENT.match(d, self.i)
                if m and m.group() not in _WORDS:
                    self.i = m.end()
                    self.ws()
                    if d[self.i:self.i + 1] != b"=" or d[self.i:self.i + 2] == b"==":
                        self.fail(f"unexpected name '{m.group().decode(errors='replace')}'")
                    self.i += 1
                    self.ws()
                entries += 1 + self.value(depth)
            self.ws()
            c = d[self.i:self.i + 1]
            if c in (b",", b";"):
                self.i += 1
            elif c != b"}":
                self.fail("',' or '}' expected")


def read_variables(data):
    """[(name, bytes on disk, entries, kind)] for each top-level variable."""
    r = Reader(data)
    found = []
    r.ws()
    while r.i < len(data):
        m = _IDENT.match(data, r.i)
        if not m or m.group() in _WORDS:
            r.fail("variable name expected")
        start = r.i
        r.i = m.end()
        r.ws()
        if data[r.i:r.i + 1] != b"=" or data[r.i:r.i + 2] == b"==":
            r.fail("'=' expected after a variable name")
        r.i += 1
        r.ws()
        vstart = r.i
        entries = r.value(0)
        raw = data[vstart:r.i]
        kind = "table" if raw.startswith(b"{") else ("nil" if raw == b"nil" else "value")
        r.ws()
        if data[r.i:r.i + 1] == b";":
            r.i += 1
            r.ws()
        found.append([m.group().decode("ascii"), start, entries, kind])
    out = []
    for n, (name, start, entries, kind) in enumerate(found):
        end = found[n + 1][1] if n + 1 < len(found) else len(data)
        out.append((name, end - start, entries, kind))
    return out


# ---------------------------------------------------------------------------
# Finding the game folder and its files
# ---------------------------------------------------------------------------
def native(path):
    """C:\\... works under WSL too (as /mnt/c/...), and /mnt/c/... on Windows."""
    m = re.match(r"^([A-Za-z]):[\\/](.*)$", path)
    if m and os.name != "nt":
        return Path("/mnt") / m.group(1).lower() / m.group(2).replace("\\", "/")
    m = re.match(r"^/mnt/([a-z])/(.*)$", path)
    if m and os.name == "nt":
        return Path(f"{m.group(1).upper()}:\\") / m.group(2)
    return Path(path)


def find_flavor(args):
    roots = [native(args.wow_dir)] if args.wow_dir else [native(p) for p in DEFAULT_ROOTS]
    root = next((r for r in roots if r.is_dir()), None)
    if not root:
        sys.exit("World of Warcraft folder not found. Pass it with --wow-dir.")
    if (root / "WTF").is_dir() and (root / "Interface").is_dir():
        return root, flavor_id(root)
    flavors = sorted(p for p in root.iterdir() if p.is_dir() and re.match(r"^_.+_$", p.name) and (p / "WTF").is_dir())
    if args.flavor:
        pick = [p for p in flavors if args.flavor in (p.name, flavor_id(p))]
        if not pick:
            sys.exit(f"No game folder '{args.flavor}' with saved data. Found: {', '.join(p.name for p in flavors) or 'none'}")
        return pick[0], flavor_id(pick[0])
    if len(flavors) == 1:
        return flavors[0], flavor_id(flavors[0])
    sys.exit("More than one game folder has saved data; choose one with --flavor: "
             + ", ".join(f"{p.name} ({flavor_id(p)})" for p in flavors))


def flavor_id(folder):
    try:
        lines = (folder / ".flavor.info").read_text(errors="replace").splitlines()
        return lines[1].strip() if len(lines) > 1 else folder.name
    except OSError:
        return folder.name


def installed_addons(game):
    base = game / "Interface" / "AddOns"
    return {p.name.lower(): p.name for p in base.iterdir() if p.is_dir()} if base.is_dir() else {}


def read_addons_txt(path):
    states = {}
    try:
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if ":" in line:
                name, _, state = line.rpartition(":")
                states[name.strip()] = state.strip()
    except OSError:
        pass
    return states


class Group:
    """One addon's saved file in one place (.lua and its .lua.bak)."""

    def __init__(self, scope, account, realm, character, addon, folder):
        self.scope, self.account, self.realm, self.character = scope, account, realm, character
        self.addon, self.folder = addon, folder
        self.files = []                 # Paths

    def size(self):
        return sum(f.stat().st_size for f in self.files)

    def main(self):
        return next((f for f in self.files if f.name.lower().endswith(".lua")), None)

    def where(self, names):
        if self.scope == "machine":
            return "this computer (all accounts)"
        if self.scope == "account":
            return f"account {names.account(self.account)}"
        return f"{names.character(self.character)} on {names.realm(self.realm)} (account {names.account(self.account)})"


def addon_of(filename):
    low = filename.lower()
    if low.endswith(".lua.bak"):
        return filename[:-8]
    if low.endswith(".lua"):
        return filename[:-4]
    return None


def collect(game):
    """Groups of saved files, files in places the tool doesn't recognise,
    character folders without saved data, and AddOns.txt per character."""
    wtf = game / "WTF"
    groups, odd, empty_chars, addons_txt = {}, [], [], {}

    def add(folder, scope, account=None, realm=None, character=None):
        for f in sorted(folder.iterdir()):
            if not f.is_file():
                continue
            addon = addon_of(f.name)
            if not addon:
                continue
            key = (scope, account, realm, character, addon.lower())
            g = groups.get(key) or Group(scope, account, realm, character, addon, folder)
            groups[key] = g
            g.files.append(f)

    if (wtf / "SavedVariables").is_dir():
        add(wtf / "SavedVariables", "machine")
    accounts = wtf / "Account"
    if accounts.is_dir():
        for acct in sorted(p for p in accounts.iterdir() if p.is_dir()):
            if (acct / "SavedVariables").is_dir():
                add(acct / "SavedVariables", "account", acct.name)
            for f in acct.iterdir():
                if f.is_file() and addon_of(f.name):
                    odd.append(f)
            for realm in sorted(p for p in acct.iterdir() if p.is_dir() and p.name != "SavedVariables"):
                for char in sorted(p for p in realm.iterdir() if p.is_dir()):
                    addons_txt[(acct.name, realm.name, char.name)] = read_addons_txt(char / "AddOns.txt")
                    if (char / "SavedVariables").is_dir():
                        add(char / "SavedVariables", "character", acct.name, realm.name, char.name)
                    else:
                        empty_chars.append((acct.name, realm.name, char.name))
    return list(groups.values()), odd, empty_chars, addons_txt


def classify(group, installed):
    if group.addon.lower().startswith("blizzard_"):
        return "game"
    return "installed" if group.addon.lower() in installed else "not installed"


# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
def size_text(n):
    if n >= 1048576:
        return f"{n / 1048576:.1f} MB"
    if n >= 1024:
        return f"{n / 1024:.0f} KB"
    return f"{n} B"


def when(path):
    return time.strftime("%Y-%m-%d", time.localtime(path.stat().st_mtime))


class Names:
    """Shows account, realm and character names, or stand-ins with --redact."""

    def __init__(self, redact):
        self.redact, self.seen = redact, {}

    def _alias(self, kind, name):
        if not self.redact or name is None:
            return name
        key = (kind, name)
        if key not in self.seen:
            self.seen[key] = f"<{kind}{sum(1 for k in self.seen if k[0] == kind) + 1}>"
        return self.seen[key]

    def account(self, n): return self._alias("account", n)
    def realm(self, n): return self._alias("realm", n)
    def character(self, n): return self._alias("character", n)


def stem(name):
    return re.sub(r"[^a-z0-9]", "", name.lower())


def similar_installed(addon, installed):
    s = stem(addon)
    hits = []
    for low, real in installed.items():
        t = stem(real)
        if len(s) >= 4 and len(t) >= 4 and (s.startswith(t) or t.startswith(s) or s[:6] == t[:6]):
            hits.append(real)
    return sorted(hits)[:3]


def variables_text(main, limit=None):
    try:
        found = read_variables(main.read_bytes())
    except ParseError as e:
        return None, f"couldn't be read as saved data: {e}"
    except OSError as e:
        return None, f"couldn't be opened: {e.strerror}"
    names = [v[0] for v in found]
    if limit and len(names) > limit:
        names = names[:limit] + [f"and {len(found) - limit} more"]
    return found, ", ".join(names) if names else "no variables"


# ---------------------------------------------------------------------------
# Is WoW running?
# ---------------------------------------------------------------------------
_WOW_EXE = re.compile(r"^wow[a-z0-9]*\.exe$", re.I)


def wow_running():
    """True, False, or None when it can't be told."""
    for cmd in (["tasklist", "/FO", "CSV", "/NH"], ["tasklist.exe", "/FO", "CSV", "/NH"]):
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=20, errors="replace").stdout
        except (OSError, subprocess.SubprocessError):
            continue
        rows = list(csv.reader(io.StringIO(out)))
        if not rows:
            continue
        return any(row and _WOW_EXE.match(row[0].strip()) for row in rows)
    return None


def require_closed(args):
    state = wow_running()
    if state:
        sys.exit("WoW is running. Close it completely first: it rewrites saved files when it exits, "
                 "and a running game may hold them open. Nothing was changed.")
    if state is None and not args.wow_closed:
        sys.exit("Couldn't tell whether WoW is running. Close it, then add --wow-closed. Nothing was changed.")


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
def cmd_scan(args):
    game, flavor = find_flavor(args)
    names = Names(args.redact)
    installed = installed_addons(game)
    groups, odd, empty_chars, addons_txt = collect(game)
    running = wow_running()
    print("TwichUI SavedVariables inspector: read-only scan")
    print(f"Game folder: {game.name} ({flavor}); {len(installed)} addon folders installed")
    print("Sizes are on disk and include the game's .bak copy of each file.")
    if running:
        print("WoW is running: files can change when it exits. Close it for a settled picture.")
    print()

    by_class = {"installed": [], "not installed": [], "game": []}
    for g in groups:
        by_class[classify(g, installed)].append(g)

    missing = {}
    for g in by_class["not installed"]:
        missing.setdefault(g.addon.lower(), []).append(g)
    total = sum(g.size() for gs in missing.values() for g in gs)
    print(f"NOT INSTALLED in this game folder: {len(missing)} addons, {size_text(total)}. Nothing is selected.")
    print("  Review each one: you may reinstall it, it may have been renamed, or another")
    print("  game folder may use it. Quarantine keeps the files so they can be put back.")
    for key in sorted(missing, key=lambda k: -sum(g.size() for g in missing[k])):
        gs = missing[key]
        addon = gs[0].addon
        print()
        print(f"  {addon}  {size_text(sum(g.size() for g in gs))} in {sum(len(g.files) for g in gs)} file(s)")
        for g in sorted(gs, key=lambda g: (g.scope, g.realm or "", g.character or "")):
            main = g.main()
            _, vars_text = variables_text(main, 6) if main else (None, "only a .bak copy")
            print(f"    {g.where(names)}: {size_text(g.size())}, last saved {when(g.files[0])}; {vars_text}")
        print("    evidence:")
        print(f"      - no folder Interface/AddOns/{addon} here")
        listed = [(k, st[name]) for k, st in addons_txt.items() for name in st if name.lower() == key]
        if listed:
            on = sum(1 for _, s in listed if s == "enabled")
            print(f"      - named in {len(listed)} character(s)' addon lists (AddOns.txt), {on} as enabled:"
                  " likely installed at some point while they played")
        else:
            print("      - not named in any character's addon list (AddOns.txt)")
        near = similar_installed(addon, installed)
        if near:
            print(f"      - similar installed name(s): {', '.join(near)} (renamed? check before removing)")
        print(f"    to quarantine: sv_inspect.py quarantine --addon \"{addon}\"")

    inst = {}
    for g in by_class["installed"]:
        inst.setdefault(g.addon.lower(), []).append(g)
    print()
    print(f"INSTALLED: {len(inst)} addons with saved data, {size_text(sum(g.size() for g in by_class['installed']))}."
          " Never moved by this tool (also when turned off).")
    for key in sorted(inst, key=lambda k: -sum(g.size() for g in inst[k]))[:args.top]:
        gs = inst[key]
        print(f"  {gs[0].addon}: {size_text(sum(g.size() for g in gs))} in {len(gs)} place(s)")
    if len(inst) > args.top:
        print(f"  ... and {len(inst) - args.top} more (sv_inspect.py show NAME for any addon)")
    print()
    print(f"GAME (Blizzard_): {len(by_class['game'])} files, {size_text(sum(g.size() for g in by_class['game']))}. Never moved.")
    if odd:
        print()
        print(f"LEFT ALONE: {len(odd)} saved file(s) in a place this tool doesn't recognise (an account folder's top level):")
        for f in odd[:10]:
            acct = f.parent.name
            print(f"  account {names.account(acct)}: {f.name}")
    if empty_chars:
        print()
        print(f"{len(empty_chars)} character folder(s) have no saved data folder (only their addon list).")
    unparsed = []
    for g in groups:
        main = g.main()
        if main and classify(g, installed) != "game":
            try:
                read_variables(main.read_bytes())
            except (ParseError, OSError) as e:
                unparsed.append((g, e))
    if unparsed:
        print()
        print(f"{len(unparsed)} file(s) couldn't be read as saved data (they were not run, only read):")
        for g, e in unparsed[:10]:
            print(f"  {g.addon} for {g.where(names)}: {e}")


def cmd_show(args):
    game, flavor = find_flavor(args)
    names = Names(args.redact)
    installed = installed_addons(game)
    groups, _, _, addons_txt = collect(game)
    gs = [g for g in groups if g.addon.lower() == args.addon.lower()]
    if not gs:
        sys.exit(f"No saved files for '{args.addon}' in {game.name}.")
    state = classify(gs[0], installed)
    print(f"{gs[0].addon} ({state}) in {game.name} ({flavor})")
    for g in sorted(gs, key=lambda g: (g.scope, g.realm or "", g.character or "")):
        print()
        extra = ""
        if g.scope == "character" and state == "installed":
            st = addons_txt.get((g.account, g.realm, g.character), {})
            listed = next((v for k, v in st.items() if k.lower() == g.addon.lower()), None)
            extra = f"; this character's addon list says: {listed or 'not listed'}"
        print(f"  {g.where(names)}{extra}")
        for f in g.files:
            print(f"    {f.name}: {size_text(f.stat().st_size)}, last saved {when(f)}")
        main = g.main()
        if not main:
            continue
        found, text = variables_text(main)
        if found is None:
            print(f"    {text}")
            continue
        for name, size, entries, kind in found:
            detail = f"{entries} entries" if kind == "table" else kind
            print(f"      {name}: {size_text(size)} ({detail})")


def batch_dir(args):
    return native(args.quarantine_dir) if args.quarantine_dir else DEFAULT_QUARANTINE


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def confirm(word, prompt):
    try:
        answer = input(f"{prompt} Type {word} to go ahead, anything else to stop: ")
    except EOFError:
        answer = ""
    if answer.strip() != word:
        sys.exit("Stopped. Nothing was changed.")


def save_manifest(path, manifest):
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    os.replace(tmp, path)


def cmd_quarantine(args):
    game, flavor = find_flavor(args)
    names = Names(args.redact)
    installed = installed_addons(game)
    groups, _, _, _ = collect(game)
    wanted = {a.lower() for a in args.addon}
    chosen = []
    for a in args.addon:
        gs = [g for g in groups if g.addon.lower() == a.lower()]
        if not gs:
            sys.exit(f"No saved files for '{a}' in {game.name}. Nothing was changed.")
        state = classify(gs[0], installed)
        if state != "not installed":
            sys.exit(f"'{a}' is {'a game file' if state == 'game' else 'installed'}; this tool only moves files of addons "
                     "that aren't installed in this game folder. Nothing was changed.")
    for g in groups:
        if g.addon.lower() not in wanted:
            continue
        if args.scope != "all" and g.scope != args.scope:
            continue
        if args.account and g.account != args.account:
            continue
        if args.character and (g.character or "").lower() != args.character.lower():
            continue
        chosen.append(g)
    if not chosen:
        sys.exit("Nothing matches those choices. Nothing was changed.")
    files = [(g, f) for g in chosen for f in g.files]
    print(f"{'Would move' if not args.apply else 'Moving'} {len(files)} file(s), {size_text(sum(g.size() for g in chosen))}, "
          f"from {game.name} ({flavor}):")
    for g, f in files:
        print(f"  {g.addon} for {g.where(names)}: {f.name} ({size_text(f.stat().st_size)}, last saved {when(f)})")
    if not args.apply:
        print("Dry run: nothing was moved. Add --apply to move them to the quarantine folder.")
        return
    require_closed(args)
    qroot = batch_dir(args)
    batch = time.strftime("%Y%m%d-%H%M%S")
    dest_root = qroot / batch
    print(f"They go to: {dest_root}")
    confirm("MOVE", f"Move these {len(files)} file(s)?")
    dest_root.mkdir(parents=True, exist_ok=False)
    wtf = game / "WTF"
    manifest = {"created": time.strftime("%Y-%m-%d %H:%M:%S"), "game": str(game), "flavor": flavor, "files": []}
    mpath = dest_root / "manifest.json"
    for g, f in files:
        rel = f.relative_to(wtf)
        target = dest_root / "WTF" / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        digest = sha256(f)
        entry = {"path": rel.as_posix(), "addon": g.addon, "scope": g.scope, "size": f.stat().st_size,
                 "sha256": digest, "status": "copying"}
        manifest["files"].append(entry)
        save_manifest(mpath, manifest)
        shutil.copy2(f, target)
        if sha256(target) != digest:
            entry["status"] = "copy failed check"
            save_manifest(mpath, manifest)
            sys.exit(f"The copy of {f.name} didn't match; the original was left in place. Stopped.")
        f.unlink()
        entry["status"] = "quarantined"
        save_manifest(mpath, manifest)
    print(f"Done. Batch {batch}: {len(files)} file(s) quarantined. To put them back: "
          f"sv_inspect.py restore {batch} --apply")


def load_batch(args, batch):
    root = batch_dir(args) / batch
    mpath = root / "manifest.json"
    if not mpath.is_file():
        sys.exit(f"No quarantined batch '{batch}' in {batch_dir(args)}.")
    return root, mpath, json.loads(mpath.read_text(encoding="utf-8"))


def cmd_restore(args):
    root, mpath, manifest = load_batch(args, args.batch)
    wtf = native(manifest["game"]) / "WTF"
    todo, blocked = [], []
    for e in manifest["files"]:
        if e["status"] != "quarantined":
            continue
        src, dest = root / "WTF" / e["path"], wtf / e["path"]
        if dest.exists():
            blocked.append((e, "a file is already there"))
        elif not src.is_file():
            blocked.append((e, "the quarantined copy is missing"))
        else:
            todo.append((e, src, dest))
    print(f"Batch {args.batch} ({manifest['flavor']}, quarantined {manifest['created']}):")
    for e, _, _ in todo:
        print(f"  {'would restore' if not args.apply else 'restoring'} {e['addon']}: {e['path'] if not args.redact else e['path'].rsplit('/', 1)[-1]}")
    for e, why in blocked:
        print(f"  skipped {e['addon']}: {e['path'] if not args.redact else e['path'].rsplit('/', 1)[-1]} ({why})")
    if not todo:
        print("Nothing to restore.")
        return
    if not args.apply:
        print("Dry run: nothing was moved. Add --apply to put them back.")
        return
    require_closed(args)
    confirm("RESTORE", f"Put {len(todo)} file(s) back?")
    for e, src, dest in todo:
        if sha256(src) != e["sha256"]:
            print(f"  {e['path']}: the quarantined copy changed since it was moved; left in quarantine.")
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
        if sha256(dest) != e["sha256"]:
            dest.unlink()
            sys.exit(f"The restored copy of {e['path']} didn't match; it was removed again. Stopped.")
        src.unlink()
        e["status"] = "restored"
        save_manifest(mpath, manifest)
    print("Done.")


def cmd_quarantined(args):
    root = batch_dir(args)
    batches = sorted(p for p in root.iterdir() if (p / "manifest.json").is_file()) if root.is_dir() else []
    if not batches:
        print(f"No quarantined files in {root}.")
        return
    print(f"Quarantine folder: {root}")
    for b in batches:
        m = json.loads((b / "manifest.json").read_text(encoding="utf-8"))
        held = [e for e in m["files"] if e["status"] == "quarantined"]
        addons = sorted({e["addon"] for e in held})
        print(f"  {b.name} ({m['flavor']}): {len(held)} file(s) held, {size_text(sum(e['size'] for e in held))}"
              f"{': ' + ', '.join(addons) if addons else ''}")


def main(argv=None):
    p = argparse.ArgumentParser(description="See and tidy WoW's SavedVariables files, outside the game.")
    p.add_argument("--wow-dir", help="World of Warcraft folder (default: the usual install places)")
    p.add_argument("--flavor", help="game folder such as _classic_beta_ or _retail_, when there are several")
    p.add_argument("--quarantine-dir", help=f"where quarantined files go (default: {DEFAULT_QUARANTINE})")
    p.add_argument("--redact", action="store_true", help="hide account, realm and character names in the output")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan", help="what's saved, and which files belong to addons not installed (read-only)")
    s.add_argument("--top", type=int, default=15, help="how many installed addons to list by size")
    s = sub.add_parser("show", help="one addon's files and variables (read-only)")
    s.add_argument("addon")
    s = sub.add_parser("quarantine", help="move a not-installed addon's files to the quarantine folder")
    s.add_argument("--addon", action="append", required=True, help="addon folder name (repeat for several)")
    s.add_argument("--scope", choices=["all", "machine", "account", "character"], default="all")
    s.add_argument("--account", help="only this account folder")
    s.add_argument("--character", help="only this character")
    s.add_argument("--apply", action="store_true", help="really move them (otherwise a dry run)")
    s.add_argument("--wow-closed", action="store_true", help="WoW is closed (when the tool can't check)")
    s = sub.add_parser("restore", help="put a quarantined batch back")
    s.add_argument("batch")
    s.add_argument("--apply", action="store_true", help="really put them back (otherwise a dry run)")
    s.add_argument("--wow-closed", action="store_true", help="WoW is closed (when the tool can't check)")
    sub.add_parser("quarantined", help="list quarantined batches")
    args = p.parse_args(argv)
    {"scan": cmd_scan, "show": cmd_show, "quarantine": cmd_quarantine,
     "restore": cmd_restore, "quarantined": cmd_quarantined}[args.cmd](args)


if __name__ == "__main__":
    main()
