"""Development opt-in is an explicit, auditable packaging transformation."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('devbuild', Path(__file__).resolve().parents[1]/'tools/build_auction_dev.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class Build(unittest.TestCase):
    def test_private_archive_and_release_isolation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)/'repo'
            root.mkdir()
            def git(*args):
                return subprocess.check_output(['git', '-C', str(root), *args], stderr=subprocess.DEVNULL)
            git('init')
            for addon in m.ADDONS:
                p = root/addon
                p.mkdir()
                (p/(addon+'.toc')).write_text('## Interface: 123\n## Version: unchanged\n')
            marker = root/m.MARKER
            marker.parent.mkdir()
            marker.write_text('development = false\nverified = {}\n')
            guide = root/m.GUIDE
            guide.parent.mkdir(parents=True)
            guide.write_text('Visit an auctioneer.\n')
            (root/'private.txt').write_text('excluded')
            git('add', '.')
            git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-m', 'fixture')
            output = Path(tmp)/'dev.zip'
            result = m.build(root, output)
            with zipfile.ZipFile(output) as archive:
                self.assertNotIn('private.txt', archive.namelist())
                self.assertEqual(archive.read(m.MARKER), b'development = true\nverified = {}\n')
                manifest = json.loads(archive.read('AUCTION-HOUSE-BUILD.json'))
                self.assertEqual(manifest['native_transaction_modes_enabled'], [])
                self.assertEqual(manifest['source_commit'], result['source_commit'])
                for addon in m.ADDONS:
                    self.assertEqual(archive.read(f'{addon}/{addon}.toc'), (root/addon/(addon+'.toc')).read_bytes())
            self.assertIn('development = false', marker.read_text())
            first = output.read_bytes()
            m.build(root, output)
            self.assertEqual(output.read_bytes(), first)
            marker.write_text('development = true\nverified = {}\n')
            with self.assertRaisesRegex(ValueError, 'clean tree'):
                m.build(root, output)


if __name__ == '__main__':
    unittest.main()
