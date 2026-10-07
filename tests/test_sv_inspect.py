"""tools/sv_inspect.py: reading saved files as data (never running them),
sorting files into installed / not installed / game, and quarantine and
restore with a dry run, a typed confirmation, WoW closed, and checked copies.
Works on a made-up game folder in a temporary directory.

Run: python3 -m unittest discover -s tests -p "test_sv_inspect.py"
"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import sv_inspect as sv  # noqa: E402

GONE = (b'\r\nGoneDB = {\r\n["list"] = {\r\n[1] = "a",\r\n[2] = "say \\"hi\\" \\\\ -- not a comment",\r\n},\r\n'
        b'["n"] = 1.5e-07,\r\n["f"] = false,\r\n}\r\nGoneOther = nil\r\nGoneCount = 42\r\n')


def write(path, data=b"\r\nX = {\r\n}\r\n"):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return path


class Fixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name) / "World of Warcraft"
        self.game = root / "_classic_beta_"
        write(self.game / ".flavor.info", b"Product Flavor!STRING:0\nwow_classic_beta\n")
        (self.game / "Interface" / "AddOns" / "Kept").mkdir(parents=True)
        (self.game / "Interface" / "AddOns" / "SettingsPackV2").mkdir(parents=True)
        wtf = self.game / "WTF"
        write(wtf / "SavedVariables" / "Blizzard_Console.lua")
        acct = wtf / "Account" / "ACCT1"
        self.gone = write(acct / "SavedVariables" / "Gone.lua", GONE)
        self.gone_bak = write(acct / "SavedVariables" / "Gone.lua.bak", GONE)
        write(acct / "SavedVariables" / "Kept.lua", b"\r\nKeptDB = {\r\n[\"a\"] = 1,\r\n}\r\n")
        write(acct / "SavedVariables" / "SettingsPack.lua")
        write(acct / "SavedVariables" / "Blizzard_SavedSets.lua")
        write(acct / "Stray.lua")
        char = acct / "Realm Name" / "Hero"
        self.gone_char = write(char / "SavedVariables" / "Gone.lua", b"\r\nGoneChar = {\r\n}\r\n")
        write(char / "SavedVariables" / "Kept.lua")
        write(char / "AddOns.txt", b"Kept: enabled\r\nGone: disabled\r\n")
        write(acct / "Realm Name" / "Alt" / "AddOns.txt", b"Gone: enabled\r\n")
        self.q = Path(self.tmp.name) / "quarantine"
        self.base = ["--wow-dir", str(root), "--quarantine-dir", str(self.q)]

    def tearDown(self):
        self.tmp.cleanup()

    def run_tool(self, *args, answer="", running=False):
        out = io.StringIO()
        code = 0
        with contextlib.redirect_stdout(out), mock.patch.object(sv, "wow_running", return_value=running), \
                mock.patch("builtins.input", return_value=answer):
            try:
                sv.main(self.base + list(args))
            except SystemExit as e:
                code = e.code
                if isinstance(code, str):
                    out.write(code)
        return out.getvalue(), code


class Reading(unittest.TestCase):
    def test_variables_and_sizes(self):
        found = sv.read_variables(GONE)
        self.assertEqual([v[0] for v in found], ["GoneDB", "GoneOther", "GoneCount"])
        self.assertEqual(sum(v[1] for v in found), len(GONE) - 2)       # all but the leading line break
        db = found[0]
        self.assertEqual((db[2], db[3]), (5, "table"))                    # list, its 2 items, n, f
        self.assertEqual(found[1][3], "nil")
        self.assertEqual(found[2][3], "value")

    def test_code_is_refused_not_run(self):
        for bad in (b'os.execute("rm -rf /")', b"X = os.time()", b"X = {f = function() end}",
                    b"X = 1 + 2", b'X = "unfinished', b"X = {", b'X = loadstring("print(1)")()'):
            with self.subTest(bad=bad), self.assertRaises(sv.ParseError):
                sv.read_variables(bad)

    def test_other_forms_still_read(self):
        data = b'-- a comment\nX = { 1, two = 2; [true] = [[long\nstring]], -1.#INF, -nan(ind), 0x1F, }\nY = -inf\n'
        self.assertEqual([v[0] for v in sv.read_variables(data)], ["X", "Y"])


class Scan(Fixture):
    def test_scan_sorts_files(self):
        out, code = self.run_tool("scan")
        self.assertEqual(code, 0)
        self.assertIn("NOT INSTALLED in this game folder: 2 addons", out)
        self.assertIn("Gone ", out)
        self.assertIn("named in 2 character(s)' addon lists (AddOns.txt), 1 as enabled", out)
        self.assertIn("similar installed name(s): SettingsPackV2", out)
        self.assertIn("INSTALLED: 1 addons", out)
        self.assertIn("GAME (Blizzard_): 2 files", out)
        self.assertIn("LEFT ALONE: 1 saved file(s)", out)
        self.assertIn("1 character folder(s) have no saved data folder", out)
        self.assertNotIn('say \\"hi', out, "values are never printed")

    def test_redact(self):
        out, _ = self.run_tool("--redact", "scan")
        self.assertNotIn("ACCT1", out)
        self.assertNotIn("Hero", out)
        self.assertNotIn("Realm Name", out)
        self.assertIn("<account1>", out)

    def test_show(self):
        out, _ = self.run_tool("show", "gone")
        self.assertIn("GoneDB:", out)
        self.assertIn("(5 entries)", out)
        self.assertIn("GoneChar:", out)


class Quarantine(Fixture):
    def test_dry_run_moves_nothing(self):
        out, code = self.run_tool("quarantine", "--addon", "Gone")
        self.assertEqual(code, 0)
        self.assertIn("Would move 3 file(s)", out)
        self.assertTrue(self.gone.exists() and not self.q.exists())

    def test_refuses_installed_and_game(self):
        for name in ("Kept", "Blizzard_SavedSets"):
            out, code = self.run_tool("quarantine", "--addon", name, "--apply", answer="MOVE")
            self.assertIn("Nothing was changed", out)
            self.assertNotEqual(code, 0)
        self.assertFalse(self.q.exists())

    def test_refuses_while_wow_runs_or_unknown(self):
        out, _ = self.run_tool("quarantine", "--addon", "Gone", "--apply", answer="MOVE", running=True)
        self.assertIn("WoW is running", out)
        out, _ = self.run_tool("quarantine", "--addon", "Gone", "--apply", answer="MOVE", running=None)
        self.assertIn("--wow-closed", out)
        self.assertTrue(self.gone.exists())

    def test_needs_the_typed_word(self):
        out, _ = self.run_tool("quarantine", "--addon", "Gone", "--apply", answer="yes")
        self.assertIn("Stopped. Nothing was changed.", out)
        self.assertTrue(self.gone.exists())

    def test_move_and_restore(self):
        before = self.gone.read_bytes()
        out, code = self.run_tool("quarantine", "--addon", "Gone", "--scope", "account", "--apply", answer="MOVE")
        self.assertEqual(code, 0, out)
        self.assertFalse(self.gone.exists() or self.gone_bak.exists())
        self.assertTrue(self.gone_char.exists(), "only the chosen scope moves")
        batch = next(p for p in self.q.iterdir()).name
        manifest = json.loads((self.q / batch / "manifest.json").read_text())
        self.assertEqual({e["status"] for e in manifest["files"]}, {"quarantined"})
        out, _ = self.run_tool("quarantined")
        self.assertIn("2 file(s) held", out)
        # a file back in place blocks that one file's restore
        write(self.gone_bak, b"new")
        out, _ = self.run_tool("restore", batch, "--apply", answer="RESTORE")
        self.assertIn("skipped Gone", out)
        self.assertEqual(self.gone.read_bytes(), before)
        self.assertEqual(self.gone_bak.read_bytes(), b"new", "never overwritten")


if __name__ == "__main__":
    unittest.main()
