import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT/'tools'/(name+'.py'))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m
builder, verifier = module('build_auction_dev'), module('verify_auction_dev')


class Verify(unittest.TestCase):
    def test_exact_source_and_forged_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)/'source'
            repo.mkdir()
            def git(*args):
                return subprocess.check_output(['git', '-C', str(repo), *args], stderr=subprocess.DEVNULL)
            git('init')
            for addon in builder.ADDONS:
                d = repo/addon
                d.mkdir()
                (d/(addon+'.toc')).write_text('## Version: preserved\n')
            marker = repo/builder.MARKER
            marker.parent.mkdir()
            marker.write_text('development = false\nverified = {}\n')
            guide = repo/builder.GUIDE
            guide.parent.mkdir(parents=True)
            guide.write_text('Owner test instructions')
            git('add', '.')
            git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-m', 'source')
            commit = git('rev-parse', 'HEAD').decode().strip()
            archive = Path(tmp)/'build.zip'
            builder.build(repo, archive)
            self.assertTrue(verifier.verify(repo, archive, commit)['verified'])
            with self.assertRaises(ValueError):
                verifier.verify(repo, archive, '0'*40)
            with zipfile.ZipFile(archive) as z:
                entries = {n:z.read(n) for n in z.namelist()}
            entries[builder.MARKER] = b'development = true\nverified = {buyItem=true}\n'
            manifest = json.loads(entries['AUCTION-HOUSE-BUILD.json'])
            import hashlib
            manifest['files'][builder.MARKER] = hashlib.sha256(entries[builder.MARKER]).hexdigest()
            entries['AUCTION-HOUSE-BUILD.json'] = json.dumps(manifest).encode()
            with zipfile.ZipFile(archive, 'w') as z:
                for name, data in entries.items():z.writestr(name, data)
            with self.assertRaises(ValueError):
                verifier.verify(repo, archive, commit)


if __name__ == '__main__':
    unittest.main()
